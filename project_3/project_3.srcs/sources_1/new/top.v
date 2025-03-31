module top_stopwatch (
    input clk,
    input reset,
    input btn_run,   // 좌측 버튼 - 스톱워치 실행/정지/시 설정
    // input btn_start,
    input btn_clear, // 우측 버튼 - 스톱워치 초기화
    // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
    // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

    input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
    input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
    input [3:0] hw_sw,  // 하드웨어 스위치 입력 (4비트로 확장)
    input rx,  // UART RX 입력
    output tx,  // UART TX 출력
    // 추가된 인터페이스
    output trigger,
    output [3:0] led_indicator,  // 4비트 벡터로 수정 (XDC 파일에 맞춤)
    output dist_start,
    output dist_IDLE,
    output start,
    output idle,
    output read,
    input echo,
    inout dht_data,
    output [3:0] fnd_comm,
    output [7:0] fnd_font,
    output [8:0] led,  // 9비트로 확장
    output done,  // Added for XDC compatibility
    output wait_state,
    output sync_low_out,
    output sync_high_out,
    output data_sync_out,
    output data_bit_out,
    output stop_out,
    output dut_io,  // Fixed for XDC compatibility
    output fsm_error  // Added for XDC compatibility
);
    // 디바운싱된 버튼 신호들
    wire w_btn_run, w_btn_clear;
    // 모드별 버튼 분기
    wire w_btn_hour;
    
    // FSM 신호들 (3비트로 확장)
    wire [2:0] current_state;
    wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
    wire sw2, sw3, sw4, sw5;

    // 스톱워치 제어 신호
    wire w_run, w_clear;

    // 시간 데이터 신호들 (스톱워치와 시계)
    wire [6:0] s_msec, c_msec, disp_msec;
    wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
    wire [4:0] s_hour, c_hour, disp_hour;

    // UART로부터 오는 제어 신호
    wire [1:0] uart_sw;
    wire uart_w_run, uart_w_clear;
    wire uart_btn_hour, uart_btn_min, uart_btn_sec;
    // UART RX 신호
    wire       w_rx_done;  // RX 완료 신호
    wire [7:0] w_rx_data;  // RX 데이터
    wire ultrasonic_enable, temp_humid_enable;

    // 초음파 센서 신호
    wire [6:0] w_msec;
    wire       w_dp_done;
    wire       w_tick_10msec;

    // CU와 DP 사이의 신호
    wire       cu_trigger;
    wire       cu_start_dp;
    wire [3:0] cu_led_status;
    wire       cu_fsm_error;
    wire       w_start_dp;

    // 다음 신호들에 대한 중개 변수 생성
    wire [6:0] w_msec_dp;  // dp 모듈에서 나오는 msec
    wire [6:0] w_msec_ultra;  // dist_calculator에서 나오는 msec
    wire       w_dp_done_dp;  // dp 모듈에서 나오는 done
    wire       w_dp_done_ultra;  // dist_calculator에서 나오는 done
    
    // 멀티드라이버 해결을 위한 트리거 신호 분리
    wire ultrasonic_trigger;  // dist_calculator 모듈에서 나오는 트리거 신호

    // 실제 신호 선택에 사용할 mux
    assign w_msec = is_ultrasonic_mode ? w_msec_ultra : w_msec_dp;
    assign w_dp_done = is_ultrasonic_mode ? w_dp_done_ultra : w_dp_done_dp;
    
    // 트리거 신호 선택 - 멀티드라이버 해결을 위해 cu_trigger만 사용
    assign trigger = cu_trigger;

    // 메타스테이블 방지를 위한 에코 신호 동기화
    reg  [2:0] echo_sync;
    wire       sync_echo;

    // 메타스테이블 방지 (에코 신호 동기화)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            echo_sync <= 3'b000;
        end else begin
            echo_sync <= {echo_sync[1:0], echo};
        end
    end
    assign sync_echo = echo_sync[2];  // 3단계 동기화 후 사용

    // 초음파 측정 시작 버튼 신호 - btn_run으로 연결
    wire btn_start_signal;
    assign btn_start_signal = (is_ultrasonic_mode ? (btn_run | ultrasonic_mode_btn) : 1'b0) | ultrasonic_enable;

    // 타이밍 신호 생성 - 10ms 틱 생성기 (방법 1: U_TICK_GEN 유지)
    tick_generator U_TICK_GEN (
        .clk(clk),
        .reset(reset),
        .tick_10msec(w_tick_10msec)  // 정상 연결
    );

    // 신호 연결 
    assign done = w_dp_done;  // 측정 완료 신호 연결
    assign fsm_error = cu_fsm_error;  // FSM 오류 신호 연결
    // 트리거 신호는 위에서 직접 할당함

    // DUT 컨트롤러 신호
    wire sensor_data;
    wire [3:0] dut_current_state;
    wire [7:0] dnt_data;
    wire [7:0] dnt_sensor_data;
    wire dnt_io;

    // UART 통신 안정화를 위한 초기화 지연
    reg [25:0] uart_init_counter;
    reg uart_ready;

    // 측정된 거리 저장 레지스터
    reg [6:0] ultrasonic_distance;

    // 초음파 거리 측정 및 저장 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ultrasonic_distance <= 7'd0;
        end else begin
            // 초음파 모드이고 측정이 완료되었을 때만 업데이트
            if (is_ultrasonic_mode && w_dp_done) begin
                if (w_msec > 0 && w_msec <= 99) begin
                    ultrasonic_distance <= w_msec;
                end
            end
        end
    end

    // UART 초기화 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            uart_init_counter <= 26'd0;
            uart_ready <= 1'b0;
        end else if (uart_init_counter < 26'd50000000) begin  // 약 0.5초 대기 (100MHz 기준)
            uart_init_counter <= uart_init_counter + 1;
            uart_ready <= 1'b0;
        end else begin
            uart_ready <= 1'b1;  // UART 초기화 완료
        end
    end

    // 하드웨어와 UART 스위치 신호 결합
    wire [3:0] combined_sw = hw_sw | {2'b00, uart_sw};

    // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
    wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
    wire final_btn_min = (uart_btn_min) & is_clock_mode;
    wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

    // 센서 데이터 표시용 MUX - 초음파 모드일 때는 저장된 거리 값 사용
    wire [7:0] display_sensor_data;
    assign display_sensor_data = is_ultrasonic_mode ? 
                               {1'b0, ultrasonic_distance} :  // 저장된 측정값 표시
                               dnt_sensor_data;

    // DHT11 센서 양방향 연결 (inout 포트에 연결)
    assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

    // dut_io 출력 포트에 dnt_io 연결 (추가)
    assign dut_io = dnt_io;

    // dht_data 입력 감지
    assign sensor_data = dht_data;

    btn_debounce U_Btn_DB_RUN (
        .clk(clk),
        .reset(reset),
        .i_btn(btn_run),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data),
        .btn_type(3'd0),
        .o_btn(w_btn_run)
    );

    btn_debounce U_Btn_DB_CLEAR (
        .clk(clk),
        .reset(reset),
        .i_btn(btn_clear),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data),
        .btn_type(3'd1),
        .o_btn(w_btn_clear)
    );

    // UART + FIFO + CU 모듈 - UART 초기화 로직 적용
    uart_fifo_top U_UART_FIFO_TOP (
        .clk(clk),
        .rst(reset & uart_ready),  // UART 초기화 후에만 리셋 신호 전달
        .rx(rx),
        .tx(tx),
        .w_run(uart_w_run),
        .w_clear(uart_w_clear),
        .btn_hour(uart_btn_hour),
        .btn_min(uart_btn_min),
        .btn_sec(uart_btn_sec),
        .sw(uart_sw),
        .o_run(w_run),
        .current_state(current_state),
        .w_rx_done(w_rx_done),
        .w_rx_data(w_rx_data),
        .ultrasonic_enable(ultrasonic_enable),
        .temp_humid_enable(temp_humid_enable)
    );

    // FSM 컨트롤러 - 확장된 버전
    fsm_controller U_FSM (
        .clk(clk),
        .reset(reset),
        .sw(combined_sw & {4{uart_ready}}),  // UART 초기화 후에만 스위치 신호 전달
        .btn_run(w_btn_run | uart_w_run),
        .sw_mode_in(is_clock_mode),
        .current_state(current_state),
        .is_clock_mode(is_clock_mode),
        .is_ultrasonic_mode(is_ultrasonic_mode),
        .is_temp_humid_mode(is_temp_humid_mode),
        .sw2(sw2),
        .sw3(sw3),
        .sw4(sw4),
        .sw5(sw5)
    );

    // 스톱워치 제어 유닛
    stopwatch_cu U_STOPWATCH_CU (
        .clk(clk),
        .reset(reset),
        .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
        .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
        .o_run(w_run),
        .o_clear(w_clear)
    );

    // 스톱워치 데이터 패스
    stopwatch_dp U_STOPWATCH_DP (
        .clk  (clk),
        .reset(reset),
        .run  (w_run),
        .clear(w_clear),
        .msec (s_msec),
        .sec  (s_sec),
        .min  (s_min),
        .hour (s_hour)
    );

    // 시계 모듈
    clock U_CLOCK (
        .clk(clk),
        .reset(reset),
        .btn_sec(final_btn_sec & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
        .btn_min(final_btn_min & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
        .btn_hour(final_btn_hour & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
        .enable(is_clock_mode),
        .o_1hz(),
        .o_msec(c_msec),
        .o_sec(c_sec),
        .o_min(c_min),
        .o_hour(c_hour)
    );

    // 초음파 CU 모듈 인스턴스화
    cu U_CU (
        .clk(clk),
        .reset(reset),
        .btn_run(btn_start_signal),  // btn_run으로 측정 시작
        .echo(sync_echo),  // 동기화된 에코 신호 사용
        .dp_done(w_dp_done_dp),  // dp 모듈에서 나오는 done 신호 연결
        .tick_10msec(w_tick_10msec),  // 10ms 주기 신호
        .trigger(cu_trigger),  // 초음파 센서 트리거 핀
        .start_dp(w_start_dp),  // DP 시작 신호
        .led_status(cu_led_status),  // LED 상태 표시
        .fsm_error(cu_fsm_error)  // FSM 오류 신호
    );

    // 초음파 DP 모듈 인스턴스 수정
    dp U_DP (
        .clk          (clk),
        .reset        (reset),
        .echo         (sync_echo),
        .start_trigger(w_start_dp),
        .done         (w_dp_done_dp),  // 이름 수정
        .msec         (w_msec_dp)      // 이름 수정
    );

    // 초음파 거리 측정 모듈 수정
    dist_calculator U_ULTRASONIC (
        .clk          (clk),
        .reset        (reset),
        .echo         (sync_echo),
        .btn_run      (btn_start_signal),
        .trigger      (ultrasonic_trigger),  // 내부에서만 사용하는 트리거 신호로 변경
        .msec         (w_msec_ultra),      // 이름 수정
        .led_indicator(led_indicator),
        .dist_start   (dist_start),
        .done         (w_dp_done_ultra)    // 이름 수정
    );

    dut_ctr U_DUT_CTR (
        .clk(clk),
        .rst(reset),
        .btn_run((w_btn_run & is_temp_humid_mode | temp_humid_enable) & uart_ready),
        .tick_counter(w_tick_10msec),
        .btn_next(temp_humid_mode_btn & uart_ready),
        .sensor_data(dht_data),  // dht_data로 직접 연결
        .current_state(dut_current_state),
        .dnt_data(dnt_data),
        .dnt_sensor_data(dnt_sensor_data),
        .dnt_io(dnt_io),
        .idle(idle),
        .start(start),
        .wait_state(wait_state),
        .sync_low_out(sync_low_out),
        .sync_high_out(sync_high_out),
        .data_sync_out(data_sync_out),
        .data_bit_out(data_bit_out),
        .stop_out(stop_out),
        .read(read)
    );

    // 디스플레이 멀티플렉서
    display_mux U_DISPLAY_MUX (
        .sw_mode(is_clock_mode),
        .current_state(current_state),
        .sw_msec(s_msec),
        .sw_sec(s_sec),
        .sw_min(s_min),
        .sw_hour(s_hour),
        .clk_msec(c_msec),
        .clk_sec(c_sec),
        .clk_min(c_min),
        .clk_hour(c_hour),
        .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
        .o_msec(disp_msec),
        .o_sec(disp_sec),
        .o_min(disp_min),
        .o_hour(disp_hour)
    );

    // FND 컨트롤러
    fnd_controller U_FND_CTRL (
        .clk(clk),
        .reset(reset),
        .sw_mode(is_clock_mode),
        .sw(uart_sw),
        .current_state(current_state),
        .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
        .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
        .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
        .hour(is_ultrasonic_mode || is_temp_humid_mode ? 5'd0 : disp_hour),
        .fnd_font(fnd_font),
        .fnd_comm(fnd_comm)
    );

    // dist_IDLE 출력 신호 할당 (초음파 모듈의 dist_IDLE 상태를 확인하기 위함)
    assign dist_IDLE = (U_ULTRASONIC.current_state == U_ULTRASONIC.IDLE) ? 1'b1 : 1'b0;

    // LED 디버깅 개선 - 각 신호 상태 표시
    assign led = is_ultrasonic_mode ? {
        sync_echo,            // LED[8]: 동기화된 에코 신호 상태
        btn_run,              // LED[7]: 버튼 입력 상태
        btn_start_signal,     // LED[6]: 시작 신호 상태
        cu_trigger,           // LED[5]: 트리거 신호 상태
        ultrasonic_distance[3:0]  // LED[4:1]: 측정된 거리
        } :
        // 온습도 모드일 때 DUT 상태 표시
        {
        idle,
        start,
        wait_state,
        sync_low_out,
        sync_high_out,
        data_sync_out,
        data_bit_out,
        stop_out,
        read
    };

endmodule

//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     // input btn_start,
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [3:0] hw_sw,  // 하드웨어 스위치 입력 (4비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire [3:0] w_led_indicator;   // LED 상태 표시 추가
//     wire w_start_dp;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // UART 통신 안정화를 위한 초기화 지연
//     reg [25:0] uart_init_counter;
//     reg uart_ready;

//     // 에코 신호 모니터링
//     reg echo_detected;           // 에코 신호가 감지되었는지 기록
//     reg [25:0] echo_mon_counter; // 에코 모니터링 타이머

//     // 에코 신호 확인 로직 추가
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             echo_detected <= 1'b0;
//             echo_mon_counter <= 26'd0;
//         end else if (is_ultrasonic_mode) begin
//             // 에코 신호 감지하면 플래그 설정
//             if (echo) begin
//                 echo_detected <= 1'b1;
//             end

//             // 주기적으로 에코 감지 상태 초기화 (3초마다)
//             if (echo_mon_counter >= 26'd300000000) begin
//                 echo_mon_counter <= 26'd0;
//                 echo_detected <= 1'b0;
//             end else begin
//                 echo_mon_counter <= echo_mon_counter + 1;
//             end
//         end else begin
//             echo_detected <= 1'b0;
//             echo_mon_counter <= 26'd0;
//         end
//     end

//     // btn_start 디바운싱 모듈 인스턴스 추가
//     wire debounced_btn_start;

//     btn_start_debounce U_Btn_DB_START (
//         .clk(clk),
//         .reset(reset),
//         .btn_start_in(btn_start),         // 입력은 T18에 매핑된 btn_start
//         .btn_start_out(debounced_btn_start)  // 디바운싱된 출력
//     );

//     // 초음파 자동 측정을 위한 카운터 추가
//     reg [27:0] ultrasonic_auto_counter;
//     reg ultrasonic_auto_trigger;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_auto_counter <= 28'd0;
//             ultrasonic_auto_trigger <= 1'b0;
//         end else if (is_ultrasonic_mode) begin
//             if (ultrasonic_auto_counter >= 28'd100000000) begin  // 1초마다 (수정: 측정 간격 늘림)
//                 ultrasonic_auto_counter <= 28'd0;
//                 ultrasonic_auto_trigger <= 1'b1;
//             end else begin
//                 ultrasonic_auto_counter <= ultrasonic_auto_counter + 1;
//                 ultrasonic_auto_trigger <= 1'b0;
//             end
//         end else begin
//             ultrasonic_auto_counter <= 28'd0;
//             ultrasonic_auto_trigger <= 1'b0;
//         end
//     end

//     // UART 초기화 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             uart_init_counter <= 26'd0;
//             uart_ready <= 1'b0;
//         end else if (uart_init_counter < 26'd50000000) begin  // 약 0.5초 대기 (100MHz 기준)
//             uart_init_counter <= uart_init_counter + 1;
//             uart_ready <= 1'b0;
//         end else begin
//             uart_ready <= 1'b1;  // UART 초기화 완료
//         end
//     end

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [3:0] combined_sw = hw_sw | {2'b00, uart_sw};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 버튼 시작 신호 - 디바운싱된 btn_start 사용
//     wire ultrasonic_btn_start;

//     // 첫 번째 코드처럼 수정: 디바운싱된 버튼 직접 사용하여 안정성 개선
//     assign ultrasonic_btn_start = is_ultrasonic_mode ? debounced_btn_start : 1'b0;

//     // 더 안정적인 초음파 값 표시를 위한 개선된 레지스터 추가
//     reg [6:0] ultrasonic_value;
//     reg ultrasonic_value_valid;
//     reg [25:0] display_hold_counter;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd0;  // 초기값 0으로 설정
//             ultrasonic_value_valid <= 1'b0;
//             display_hold_counter <= 26'd0;
//         end else if (is_ultrasonic_mode) begin
//             // 측정 완료 시 값 업데이트
//             if (w_dp_done) begin
//                 // 최소 1cm 이상의 값만 받아들이도록 수정
//                 if (w_msec >= 7'd1) begin
//                     ultrasonic_value <= w_msec;  // 측정된 값 저장
//                     ultrasonic_value_valid <= 1'b1;
//                     display_hold_counter <= 26'd100000000;  // 약 1초간 유지
//                 end
//             end else if (display_hold_counter > 0) begin
//                 // 표시 유지 시간 카운트다운
//                 display_hold_counter <= display_hold_counter - 1;
//             end else if (!ultrasonic_value_valid) begin
//                 // 유효한 값이 없으면 기본값 사용
//                 ultrasonic_value <= 7'd0;  // 기본값 0으로 설정
//                 ultrasonic_value_valid <= 1'b1;
//             end
//         end else begin
//             // 모드가 변경되면 초기화
//             ultrasonic_value_valid <= 1'b0;
//         end
//     end

//     // 센서 데이터 표시용 MUX
//     wire [7:0] display_sensor_data;

//     // 첫 번째 코드와 같이 수정: 항상 현재 측정된 값 표시
//     assign display_sensor_data = is_ultrasonic_mode ? 
//                                {1'b0, ultrasonic_value} :  
//                                dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 - UART 초기화 로직 적용
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset & uart_ready),  // UART 초기화 후에만 리셋 신호 전달
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw & {4{uart_ready}}),  // UART 초기화 후에만 스위치 신호 전달
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_min(final_btn_min & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_hour(final_btn_hour & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈 - 첫 번째 코드와 같이 수정
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start((debounced_btn_start | ultrasonic_auto_trigger | ultrasonic_enable) & uart_ready),
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(w_led_indicator),  // LED 인디케이터 연결
//         .start(w_start_dp),  // start 신호 연결
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어)
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_run((w_btn_run & is_temp_humid_mode | temp_humid_enable) & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? 5'd0 : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: 초음파 모드일 때는 디버깅 정보 표시, 아닐 때는 DUT 상태 표시
//     assign led = is_ultrasonic_mode ? 
//                  {
//                    echo,              // LED[8]: 에코 신호 직접 표시
//                    echo_detected,     // LED[7]: 에코 감지 여부
//                    ultrasonic_btn_start, // LED[6]: 초음파 시작 버튼
//                    w_dp_done,         // LED[5]: 측정 완료 신호
//                    w_led_indicator    // LED[4:1]: 초음파 FSM 상태
//                  } :  
//                  {
//                      idle,
//                      start,
//                      wait_state,
//                      sync_low_out,
//                      sync_high_out,
//                      data_sync_out,
//                      data_bit_out,
//                      stop_out,
//                      read
//                  };  // 온습도 모드일 때 DUT 상태 표시

// endmodule

// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,    // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_start,
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     // input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [3:0] hw_sw,  // 하드웨어 스위치 입력 (4비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     output [3:0] led_indicator,
//     output dist_start,
//     output idle,
//     output read,
//     output dist_IDLE,
//     output start,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire [3:0] w_led_indicator;  // LED 상태 표시 추가
//     wire w_dist_start;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // assign 명령문 수정 - 변수명 충돌 해결
//     assign w_dist_start = dist_start;  // dist_start 신호 연결
//     assign w_led_indicator = led_indicator;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, dut_start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // UART 통신 안정화를 위한 초기화 지연
//     reg [25:0] uart_init_counter;
//     reg uart_ready;

//     // 에코 신호 모니터링
//     reg echo_detected;  // 에코 신호가 감지되었는지 기록
//     reg [25:0] echo_mon_counter;  // 에코 모니터링 타이머

//     // 측정된 거리 저장 레지스터
//     reg [6:0] ultrasonic_distance;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_distance <= 7'd0;
//         end else begin
//             // 초음파 모드이고 측정이 완료되었을 때만 업데이트
//             if (is_ultrasonic_mode && w_dp_done) begin
//                 if (w_msec > 0 && w_msec <= 99) begin
//                     ultrasonic_distance <= w_msec;
//                 end else begin
//                     // 유효하지 않은 범위일 경우 마지막 유효한 값 유지
//                     ultrasonic_distance <= ultrasonic_distance;
//                 end
//             end
//         end
//     end

//     // 에코 신호 확인 로직 추가
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             echo_detected <= 1'b0;
//             echo_mon_counter <= 26'd0;
//         end else if (is_ultrasonic_mode) begin
//             // 에코 신호 감지하면 플래그 설정
//             if (echo) begin
//                 echo_detected <= 1'b1;
//             end

//             // 주기적으로 에코 감지 상태 초기화 (1초마다)
//             if (echo_mon_counter >= 26'd100000000) begin
//                 echo_mon_counter <= 26'd0;
//                 echo_detected <= 1'b0;
//             end else begin
//                 echo_mon_counter <= echo_mon_counter + 1;
//             end
//         end else begin
//             echo_detected <= 1'b0;
//             echo_mon_counter <= 26'd0;
//         end
//     end

//     // btn_start 디바운싱 모듈 인스턴스 추가 - 상승 에지 감지 모듈로 변경
//     wire debounced_btn_start;

//     btn_start_debounce U_Btn_DB_START (
//         .clk(clk),
//         .reset(reset),
//         .btn_start_in(btn_start),  // 입력은 T18에 매핑된 btn_start
//         .btn_start_out(debounced_btn_start)  // 디바운싱된 출력
//     );

//     // UART 초기화 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             uart_init_counter <= 26'd0;
//             uart_ready <= 1'b0;
//         end else if (uart_init_counter < 26'd50000000) begin  // 약 0.5초 대기 (100MHz 기준)
//             uart_init_counter <= uart_init_counter + 1;
//             uart_ready <= 1'b0;
//         end else begin
//             uart_ready <= 1'b1;  // UART 초기화 완료
//         end
//     end

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [3:0] combined_sw = hw_sw | {2'b00, uart_sw};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 버튼 시작 신호 - 디바운싱된 버튼 (상승 에지 감지)만 사용
//     wire ultrasonic_btn_start;
//     assign ultrasonic_btn_start = is_ultrasonic_mode ? debounced_btn_start : 1'b0;

//     // 센서 데이터 표시용 MUX - 초음파 모드일 때는 저장된 거리 값 사용
//     wire [7:0] display_sensor_data;
//     assign display_sensor_data = is_ultrasonic_mode ? 
//                                {1'b0, ultrasonic_distance} :  // 저장된 측정값 표시
//                                dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 - UART 초기화 로직 적용
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset & uart_ready),  // UART 초기화 후에만 리셋 신호 전달
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw & {4{uart_ready}}),  // UART 초기화 후에만 스위치 신호 전달
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_min(final_btn_min & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_hour(final_btn_hour & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈 - 상승 에지로만 측정 시작
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(debounced_btn_start | ultrasonic_enable),  // 버튼 상승 에지로 측정 시작
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(led_indicator),  // LED 인디케이터 연결
//         .dist_start(dist_start),  // dist_start 신호 연결 (이름 변경됨)
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어)
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_run((w_btn_run & is_temp_humid_mode | temp_humid_enable) & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? 5'd0 : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // dist_IDLE 출력 신호 할당 (초음파 모듈의 dist_IDLE 상태를 확인하기 위함)
//     assign dist_IDLE = (U_ULTRASONIC.current_state == U_ULTRASONIC.dist_IDLE) ? 1'b1 : 1'b0;

//     assign led = is_ultrasonic_mode ? 
//              {
//                echo,              // LED[8]: 에코 신호 직접 표시
//                echo_detected,     // LED[7]: 에코 감지 여부
//                ultrasonic_btn_start,  // LED[6]: 초음파 시작 버튼
//                w_dp_done,         // LED[5]: 측정 완료 신호
//                w_msec[3:0]        // LED[4:1]: 실제 측정된 거리
//              } :
//              // 온습도 모드일 때 DUT 상태 표시
//              {
//                idle,
//                start,
//                wait_state,
//                sync_low_out,
//                sync_high_out,
//                data_sync_out,
//                data_bit_out,
//                stop_out,
//                read
//              };

// endmodule
// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_start,
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     // input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [3:0] hw_sw,  // 하드웨어 스위치 입력 (4비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire [3:0] w_led_indicator;   // LED 상태 표시 추가
//     wire w_start_dp;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // UART 통신 안정화를 위한 초기화 지연
//     reg [25:0] uart_init_counter;
//     reg uart_ready;

//     // btn_start 디바운싱 모듈 인스턴스 추가
//     wire debounced_btn_start;

//     btn_start_debounce U_Btn_DB_START (
//         .clk(clk),
//         .reset(reset),
//         .btn_start_in(btn_start),         // 입력은 T18에 매핑된 btn_start
//         .btn_start_out(debounced_btn_start)  // 디바운싱된 출력
//     );

//     // 초음파 자동 측정을 위한 카운터 추가 - 주기 수정
//     reg [27:0] ultrasonic_auto_counter;
//     reg ultrasonic_auto_trigger;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_auto_counter <= 28'd0;
//             ultrasonic_auto_trigger <= 1'b0;
//         end else if (is_ultrasonic_mode) begin
//             if (ultrasonic_auto_counter >= 28'd200000000) begin  // 2초마다로 변경
//                 ultrasonic_auto_counter <= 28'd0;
//                 ultrasonic_auto_trigger <= 1'b1;
//             end else begin
//                 ultrasonic_auto_counter <= ultrasonic_auto_counter + 1;
//                 // 트리거는 한 클럭만 유지
//                 if (ultrasonic_auto_trigger)
//                     ultrasonic_auto_trigger <= 1'b0;
//             end
//         end else begin
//             ultrasonic_auto_counter <= 28'd0;
//             ultrasonic_auto_trigger <= 1'b0;
//         end
//     end

//     // UART 초기화 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             uart_init_counter <= 26'd0;
//             uart_ready <= 1'b0;
//         end else if (uart_init_counter < 26'd50000000) begin  // 약 0.5초 대기 (100MHz 기준)
//             uart_init_counter <= uart_init_counter + 1;
//             uart_ready <= 1'b0;
//         end else begin
//             uart_ready <= 1'b1;  // UART 초기화 완료
//         end
//     end

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [3:0] combined_sw = hw_sw | {2'b00, uart_sw};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 버튼 시작 신호 - 디바운싱된 btn_start 사용
//     wire ultrasonic_btn_start;
//     assign ultrasonic_btn_start = is_ultrasonic_mode ? (debounced_btn_start | ultrasonic_auto_trigger) : 1'b0;

//     // 더 안정적인 초음파 값 표시를 위한 개선된 레지스터 추가 - 조건 수정
//     reg [6:0] ultrasonic_value;
//     reg ultrasonic_value_valid;
//     reg [25:0] display_hold_counter;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd15;  // 초기값 15cm
//             ultrasonic_value_valid <= 1'b0;
//             display_hold_counter <= 26'd0;
//         end else if (is_ultrasonic_mode) begin
//             // 측정 완료 시 유효한 값만 업데이트 - 조건 완화
//             if (w_dp_done) begin
//                 if (w_msec >= 7'd1 && w_msec <= 7'd99) begin  // 1cm에서 99cm 사이의 유효한 값만 사용
//                     ultrasonic_value <= w_msec;
//                     ultrasonic_value_valid <= 1'b1;
//                     display_hold_counter <= 26'd200000000;  // 약 2초간 유지로 늘림
//                 end
//             end else if (display_hold_counter > 0) begin
//                 // 표시 유지 시간 카운트다운
//                 display_hold_counter <= display_hold_counter - 1;
//             end else if (!ultrasonic_value_valid) begin
//                 // 유효한 값이 없으면 기본값 사용
//                 ultrasonic_value <= 7'd15;
//                 ultrasonic_value_valid <= 1'b1;
//             end
//         end else begin
//             // 모드가 변경되면 초기화
//             ultrasonic_value_valid <= 1'b0;
//         end
//     end

//     // 센서 데이터 표시용 MUX
//     wire [7:0] display_sensor_data;
//     assign display_sensor_data = is_ultrasonic_mode ? 
//                                 {1'b0, ultrasonic_value_valid ? ultrasonic_value : 7'd15} : 
//                                 dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 - UART 초기화 로직 적용
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset & uart_ready),  // UART 초기화 후에만 리셋 신호 전달
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw & {4{uart_ready}}),  // UART 초기화 후에만 스위치 신호 전달
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_min(final_btn_min & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_hour(final_btn_hour & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(ultrasonic_btn_start | ultrasonic_enable),  // 디바운싱된 버튼, 자동 트리거, UART 명령 사용
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(w_led_indicator),  // LED 인디케이터 연결
//         .start(w_start_dp),  // start 신호 연결
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어)
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_run((w_btn_run & is_temp_humid_mode | temp_humid_enable) & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? 5'd0 : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: 초음파 모드일 때는 초음파 상태 표시, 아닐 때는 DUT 상태 표시
//     assign led = is_ultrasonic_mode ? 
//                  {5'b00000, w_led_indicator} :  // 초음파 모드일 때 상태 표시
//                  {
//                      idle,
//                      start,
//                      wait_state,
//                      sync_low_out,
//                      sync_high_out,
//                      data_sync_out,
//                      data_bit_out,
//                      stop_out,
//                      read
//                  };  // 온습도 모드일 때 DUT 상태 표시

// endmodule
// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_start,
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     // input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [3:0] hw_sw,  // 하드웨어 스위치 입력 (4비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire w_start_dp;
//     wire [3:0] w_led_status;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // UART 통신 안정화를 위한 초기화 지연
//     reg [25:0] uart_init_counter;
//     reg uart_ready;

//     // btn_start 디바운싱 모듈 인스턴스 추가
//     wire debounced_btn_start;

//     btn_start_debounce U_Btn_DB_START (
//         .clk(clk),
//         .reset(reset),
//         .btn_start_in(btn_start),         // 입력은 T18에 매핑된 btn_start
//         .btn_start_out(debounced_btn_start)  // 디바운싱된 출력
//     );

//     // 초음파 자동 측정을 위한 카운터 추가
//     reg [27:0] ultrasonic_auto_counter;
//     reg ultrasonic_auto_trigger;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_auto_counter <= 28'd0;
//             ultrasonic_auto_trigger <= 1'b0;
//         end else if (is_ultrasonic_mode) begin
//             if (ultrasonic_auto_counter >= 28'd50000000) begin  // 0.5초마다
//                 ultrasonic_auto_counter <= 28'd0;
//                 ultrasonic_auto_trigger <= 1'b1;
//             end else begin
//                 ultrasonic_auto_counter <= ultrasonic_auto_counter + 1;
//                 ultrasonic_auto_trigger <= 1'b0;
//             end
//         end else begin
//             ultrasonic_auto_counter <= 28'd0;
//             ultrasonic_auto_trigger <= 1'b0;
//         end
//     end

//     // UART 초기화 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             uart_init_counter <= 26'd0;
//             uart_ready <= 1'b0;
//         end else if (uart_init_counter < 26'd50000000) begin  // 약 0.5초 대기 (100MHz 기준)
//             uart_init_counter <= uart_init_counter + 1;
//             uart_ready <= 1'b0;
//         end else begin
//             uart_ready <= 1'b1;  // UART 초기화 완료
//         end
//     end

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [3:0] combined_sw = hw_sw | {2'b00, uart_sw};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 버튼 시작 신호 - 디바운싱된 btn_start 사용
//     wire ultrasonic_btn_start;
//     assign ultrasonic_btn_start = is_ultrasonic_mode ? (debounced_btn_start | ultrasonic_auto_trigger) : 1'b0;

//     // 더 안정적인 초음파 값 표시를 위한 개선된 레지스터 추가
//     reg [6:0] ultrasonic_value;
//     reg ultrasonic_value_valid;
//     reg [25:0] display_hold_counter;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd15;  // 초기값 15cm
//             ultrasonic_value_valid <= 1'b0;
//             display_hold_counter <= 26'd0;
//         end else if (is_ultrasonic_mode) begin
//             // 측정 완료 시 유효한 값만 업데이트
//             if (w_dp_done && w_msec > 7'd0) begin
//                 ultrasonic_value <= w_msec;
//                 ultrasonic_value_valid <= 1'b1;
//                 display_hold_counter <= 26'd100000000;  // 약 1초간 유지
//             end else if (display_hold_counter > 0) begin
//                 // 표시 유지 시간 카운트다운
//                 display_hold_counter <= display_hold_counter - 1;
//             end else if (!ultrasonic_value_valid) begin
//                 // 유효한 값이 없으면 기본값 사용
//                 ultrasonic_value <= 7'd15;
//                 ultrasonic_value_valid <= 1'b1;
//             end
//         end else begin
//             // 모드가 변경되면 초기화
//             ultrasonic_value_valid <= 1'b0;
//         end
//     end

//     // 센서 데이터 표시용 MUX
//     wire [7:0] display_sensor_data;
//     assign display_sensor_data = is_ultrasonic_mode ? 
//                                 {1'b0, ultrasonic_value_valid ? ultrasonic_value : 7'd15} : 
//                                 dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 - UART 초기화 로직 적용
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset & uart_ready),  // UART 초기화 후에만 리셋 신호 전달
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw & {4{uart_ready}}),  // UART 초기화 후에만 스위치 신호 전달
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_min(final_btn_min & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .btn_hour(final_btn_hour & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(ultrasonic_btn_start | ultrasonic_enable),  // 디바운싱된 버튼, 자동 트리거, UART 명령 사용
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(),
//         .start(),
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어)
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_run((w_btn_run & is_temp_humid_mode | temp_humid_enable) & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn & uart_ready),  // UART 초기화 후에만 버튼 신호 전달
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? 5'd0 : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: DUT 상태 표시용 확장된 LED
//     assign led = {
//         idle,
//         start,
//         wait_state,
//         sync_low_out,
//         sync_high_out,
//         data_sync_out,
//         data_bit_out,
//         stop_out,
//         read
//     };

// endmodule
// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,   // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_clear, // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [2:0] hw_sw,  // 하드웨어 스위치 입력 (3비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire w_start_dp;
//     wire [3:0] w_led_status;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // 초음파 모드 버튼 디바운싱 및 엣지 감지
//     reg [ 3:0] ultrasonic_btn_sync;  // 4단계 시프트 레지스터로 확장
//     reg        ultrasonic_btn_edge;
//     reg        ultrasonic_btn_active;  // 버튼 상태 유지 플래그 추가

//     // 모드 전환을 위한 레지스터
//     reg        mode_switch_requested;
//     reg [ 1:0] mode_selection;  // 0: 시계, 1: 초음파, 2: 온습도
//     reg [25:0] mode_transition_counter;
//     // top_stopwatch 모듈 내부에 추가할 리셋 및 UART 초기화 로직

//     // UART 초기화 및 자동 작동 방지를 위한 레지스터
//     reg [25:0] uart_init_counter;
//     reg        uart_initialized;
//     reg        auto_operation_blocked;

//     // UART 초기화 및 자동 작동 방지 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             uart_init_counter <= 26'd0;
//             uart_initialized <= 1'b0;
//             auto_operation_blocked <= 1'b1;  // 리셋 후 자동 작동 차단
//         end else begin
//             // UART 초기화를 위한 시간 지연
//             if (uart_init_counter < 26'd50000000) begin  // 약 0.5초 (100MHz 기준)
//                 uart_init_counter <= uart_init_counter + 1;
//                 uart_initialized  <= 1'b0;
//             end else begin
//                 uart_initialized <= 1'b1;  // UART 초기화 완료
//             end

//             // 사용자 입력이나 UART 명령을 받으면 자동 작동 차단 해제
//             if (w_rx_done || btn_run || btn_clear) begin
//                 auto_operation_blocked <= 1'b0;
//             end
//         end
//     end

//     // 기존 상태 및 모드 신호에 UART 초기화 및 자동 작동 차단 조건 적용
//     wire safe_mode_operation = uart_initialized & ~auto_operation_blocked;

//     // 스위치 및 모드 전환 요청에 안전 조건 적용
//     wire safe_force_ultrasonic_mode = force_ultrasonic_mode & safe_mode_operation;
//     wire safe_force_temp_humid_mode = force_temp_humid_mode & safe_mode_operation;
//     wire safe_force_clock_mode = force_clock_mode | ~safe_mode_operation;  // 안전하지 않으면 시계 모드

//     // 실제 사용할 상태와 모드 플래그 - 안전 조건 적용
//     wire [2:0] effective_state = safe_force_ultrasonic_mode ? 3'b100 :
//                             (safe_force_temp_humid_mode ? 3'b110 :
//                             3'b010);  // 기본 시계 모드
//     wire effective_is_ultrasonic_mode = safe_force_ultrasonic_mode;
//     wire effective_is_temp_humid_mode = safe_force_temp_humid_mode;
//     wire effective_is_clock_mode = safe_force_clock_mode;

//     // 초음파 버튼 디바운싱 및 엣지 감지 개선
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_btn_sync   <= 4'b0000;
//             ultrasonic_btn_edge   <= 1'b0;
//             ultrasonic_btn_active <= 1'b0;
//         end else begin
//             // 4단계 시프트 레지스터를 통한 디바운싱
//             ultrasonic_btn_sync <= {
//                 ultrasonic_btn_sync[2:0], ultrasonic_mode_btn
//             };

//             // 모든 샘플이 1인 경우만 버튼이 눌렸다고 판단
//             if (ultrasonic_btn_sync == 4'b1111 && !ultrasonic_btn_active) begin
//                 ultrasonic_btn_edge   <= 1'b1;  // 버튼 엣지 활성화
//                 ultrasonic_btn_active <= 1'b1;  // 버튼 활성 상태 설정
//             end else if (ultrasonic_btn_sync == 4'b0000) begin
//                 ultrasonic_btn_active <= 1'b0;  // 버튼에서 손을 뗌
//                 ultrasonic_btn_edge   <= 1'b0;  // 엣지 감지 초기화
//             end else begin
//                 ultrasonic_btn_edge <= 1'b0;  // 엣지는 한 클럭만 유지
//             end
//         end
//     end

//     // 모드 전환 요청 처리
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             mode_switch_requested <= 1'b0;
//             mode_selection <= 2'b00;  // 기본 시계 모드
//             mode_transition_counter <= 26'd0;
//         end else begin
//             // 모드 전환 버튼 감지
//             if (ultrasonic_btn_edge) begin
//                 mode_switch_requested <= 1'b1;
//                 mode_selection <= 2'b01;  // 초음파 모드 선택
//                 mode_transition_counter <= 26'd50000000;  // 약 0.5초 대기
//             end else if (temp_humid_mode_btn) begin
//                 mode_switch_requested <= 1'b1;
//                 mode_selection <= 2'b10;  // 온습도 모드 선택
//                 mode_transition_counter <= 26'd50000000;  // 약 0.5초 대기
//             end else if (mode_transition_counter > 0) begin
//                 mode_transition_counter <= mode_transition_counter - 1;
//             end else begin
//                 mode_switch_requested <= 1'b0;  // 요청 초기화
//             end
//         end
//     end

//     // 하드웨어 스위치와 모드 요청을 조합하여 강제 모드 설정
//     wire force_ultrasonic_mode = (hw_sw[1] || (mode_switch_requested && mode_selection == 2'b01));
//     wire force_temp_humid_mode = (hw_sw[2] || (mode_switch_requested && mode_selection == 2'b10));
//     wire force_clock_mode = (~hw_sw[1] & ~hw_sw[2] & ~mode_switch_requested);

//     // 강제 상태 코드 설정 (display_mux의 파라미터와 일치)
//     wire [2:0] forced_state = force_ultrasonic_mode ? 3'b100 :  // STATE_4 (초음파 CM)
//     (force_temp_humid_mode ? 3'b110 :  // STATE_6 (온도)
//     3'b010);  // STATE_2 (시계 초:밀리초)

//     // 실제 사용할 상태와 모드 플래그
//     wire [2:0] effective_state = forced_state;
//     wire effective_is_ultrasonic_mode = force_ultrasonic_mode;
//     wire effective_is_temp_humid_mode = force_temp_humid_mode;
//     wire effective_is_clock_mode = force_clock_mode;

//     // 초음파 센서 데이터
//     wire [7:0] ultrasonic_data;
//     assign ultrasonic_data[6:0] = w_msec;
//     assign ultrasonic_data[7]   = 1'b0;  // 상위 비트는 0으로 설정

//     // 초음파 버튼 시작 신호 - 초음파 모드일 때만 활성화
//     wire ultrasonic_btn_start;
//     assign ultrasonic_btn_start = effective_is_ultrasonic_mode ? ultrasonic_mode_btn : 1'b0;

//     // 자동 측정 트리거 생성 - 초음파 모드일 때마다 주기적 측정 수행
//     reg [27:0] auto_measure_counter;
//     reg auto_measure_trigger;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             auto_measure_counter <= 28'd0;
//             auto_measure_trigger <= 1'b0;
//         end else if (effective_is_ultrasonic_mode) begin
//             // 약 0.5초마다 자동 측정 트리거 생성
//             if (auto_measure_counter >= 28'd50000000) begin
//                 auto_measure_counter <= 28'd0;
//                 auto_measure_trigger <= 1'b1;
//             end else begin
//                 auto_measure_counter <= auto_measure_counter + 1;
//                 auto_measure_trigger <= 1'b0;
//             end
//         end else begin
//             auto_measure_counter <= 28'd0;
//             auto_measure_trigger <= 1'b0;
//         end
//     end

//     // 초음파 센서 측정값 저장 레지스터 및 상태
//     reg [6:0] ultrasonic_value;
//     reg ultrasonic_value_valid;
//     reg [25:0] value_display_counter;

//     // 초음파 값 저장 로직 개선
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd15;  // 기본값
//             ultrasonic_value_valid <= 1'b0;
//             value_display_counter <= 26'd0;
//         end else if (effective_is_ultrasonic_mode) begin
//             // 측정 완료 시 값 업데이트
//             if (w_dp_done) begin
//                 if (w_msec > 7'd0) begin  // 유효한 측정값만 저장
//                     ultrasonic_value <= w_msec;
//                     ultrasonic_value_valid <= 1'b1;
//                     value_display_counter <= 26'd100000000;  // 약 1초 표시
//                 end
//             end else if (value_display_counter > 0) begin
//                 value_display_counter <= value_display_counter - 1;
//             end else if (!ultrasonic_value_valid) begin
//                 // 유효한 값이 없으면 기본값 사용
//                 ultrasonic_value <= 7'd15;
//                 ultrasonic_value_valid <= 1'b1;
//             end
//         end else begin
//             // 모드가 변경되면 값 초기화
//             ultrasonic_value_valid <= 1'b0;
//             value_display_counter  <= 26'd0;
//         end
//     end

//     // 센서 데이터 표시용 MUX
//     wire [7:0] display_sensor_data;

//     // 적절한 센서 값 선택
//     assign display_sensor_data = effective_is_ultrasonic_mode ? {1'b0, ultrasonic_value} :
//                               (effective_is_temp_humid_mode ? dnt_sensor_data : 8'd0);

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [2:0] combined_sw = hw_sw | {uart_sw, 1'b0};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & effective_is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & effective_is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & effective_is_clock_mode;

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 추가
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset),
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw),
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~effective_is_clock_mode & ~effective_is_ultrasonic_mode & ~effective_is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~effective_is_clock_mode & ~effective_is_ultrasonic_mode & ~effective_is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec),
//         .btn_min(final_btn_min),
//         .btn_hour(final_btn_hour),
//         .enable(effective_is_clock_mode),  // 강제 모드 플래그 사용
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈 - 버튼 활성화 로직 개선
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(ultrasonic_btn_start | auto_measure_trigger | ultrasonic_enable),  // 수동/자동 트리거 조합
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(),
//         .start(),
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어) - 강제 모드 플래그 사용
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_start(w_btn_run & effective_is_temp_humid_mode | temp_humid_enable),  // 강제 모드 플래그 사용
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn),  // 온습도 모드용 버튼 직접 사용
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서 - 강제 상태 사용
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(effective_is_clock_mode),  // 모드 플래그 사용
//         .current_state(effective_state),  // 강제 상태 사용
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러 - 강제 상태 사용
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(effective_is_clock_mode),
//         .sw(uart_sw),
//         .current_state(effective_state),  // 강제 상태 사용
//         .msec(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? disp_sec : disp_sec),  // 단위 표시 유지
//         .min(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? 5'd0 : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: DUT 상태 표시용 확장된 LED
//     assign led = {
//         idle,
//         start,
//         wait_state,
//         sync_low_out,
//         sync_high_out,
//         data_sync_out,
//         data_bit_out,
//         stop_out,
//         read
//     };

// endmodule


// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [2:0] hw_sw,  // 하드웨어 스위치 입력 (3비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire w_start_dp;
//     wire [3:0] w_led_status;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // FSM 디버깅 및 강제 모드 설정을 위한 추가 레지스터
//     reg [2:0] debug_current_state;
//     reg debug_is_ultrasonic_mode;

//     // 시스템 초기화 딜레이
//     reg [25:0] init_counter;
//     reg system_ready;

//     // 초음파 측정값 강제 설정 (트러블슈팅용)
//     reg [6:0] forced_ultrasonic_value;
//     reg [25:0] value_display_counter;
//     reg ultrasonic_update_flag;

//     // 버튼 엣지 감지
//     reg ultrasonic_btn_prev;
//     wire ultrasonic_btn_edge;

//     // 초기화 및 시스템 준비
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             init_counter <= 26'd0;
//             system_ready <= 1'b0;
//             debug_current_state <= 3'b000;
//             debug_is_ultrasonic_mode <= 1'b0;
//         end else if (init_counter < 26'd50000000) begin  // 약 0.5초 대기
//             init_counter <= init_counter + 1;
//             system_ready <= 1'b0;
//         end else begin
//             system_ready <= 1'b1;
//             debug_current_state <= current_state;
//             debug_is_ultrasonic_mode <= is_ultrasonic_mode;
//         end
//     end

//     // 강제 모드 및 상태 설정 (트러블슈팅용)
//     wire force_test_mode = system_ready & 1'b1;  // 1로 설정하여 테스트 모드 활성화
//     wire force_ultrasonic_mode = force_test_mode & hw_sw[1];  // 스위치 1이 초음파 모드
//     wire force_temp_humid_mode = force_test_mode & hw_sw[2];  // 스위치 2가 온습도 모드
//     wire force_clock_mode = force_test_mode & (~hw_sw[1] & ~hw_sw[2]);  // 기본 시계 모드

//     // 강제 상태 설정
//     wire [2:0] forced_state = force_ultrasonic_mode ? 3'b100 :  // 초음파 모드 CM
//                               (force_temp_humid_mode ? 3'b110 :  // 온도 모드
//                               (force_clock_mode ? 3'b010 : current_state));  // 시계 모드 또는 현재 상태

//     // 실제 사용할 상태 및 모드 플래그
//     wire [2:0] effective_state = forced_state;
//     wire effective_is_ultrasonic_mode = force_ultrasonic_mode;
//     wire effective_is_temp_humid_mode = force_temp_humid_mode;
//     wire effective_is_clock_mode = force_clock_mode;

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [2:0] combined_sw = hw_sw | {uart_sw, 1'b0};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & effective_is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & effective_is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & effective_is_clock_mode;

//     // 초음파 센서 데이터 (추가)
//     wire [7:0] ultrasonic_data;
//     assign ultrasonic_data[6:0] = w_msec;
//     assign ultrasonic_data[7] = 1'b0;  // 상위 비트는 0으로 설정

//     // 버튼 엣지 감지 로직
//     assign ultrasonic_btn_edge = ultrasonic_mode_btn & ~ultrasonic_btn_prev;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_btn_prev <= 1'b0;
//         end else begin
//             ultrasonic_btn_prev <= ultrasonic_mode_btn;
//         end
//     end

//     // 초음파 버튼 시작 신호 - 직접 연결
//     wire ultrasonic_btn_start;
//     assign ultrasonic_btn_start = effective_is_ultrasonic_mode ? ultrasonic_mode_btn : 1'b0;

//     // 자동 측정 트리거 생성 (추가)
//     reg [27:0] auto_measure_counter;
//     reg auto_measure_trigger;

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             auto_measure_counter <= 28'd0;
//             auto_measure_trigger <= 1'b0;
//         end else if (effective_is_ultrasonic_mode) begin
//             // 약 0.5초마다 자동 측정 트리거 생성
//             if (auto_measure_counter >= 28'd50000000) begin
//                 auto_measure_counter <= 28'd0;
//                 auto_measure_trigger <= 1'b1;
//             end else begin
//                 auto_measure_counter <= auto_measure_counter + 1;
//                 auto_measure_trigger <= 1'b0;
//             end
//         end else begin
//             auto_measure_counter <= 28'd0;
//             auto_measure_trigger <= 1'b0;
//         end
//     end

//     // 강제 초음파 값 생성 (트러블슈팅용)
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             forced_ultrasonic_value <= 7'd20;  // 초기값 20cm
//             value_display_counter <= 26'd0;
//             ultrasonic_update_flag <= 1'b0;
//         end else if (effective_is_ultrasonic_mode) begin
//             // 버튼이 눌리면 값 변경
//             if (ultrasonic_btn_edge) begin
//                 forced_ultrasonic_value <= forced_ultrasonic_value + 7'd5;  // 5cm씩 증가
//                 if (forced_ultrasonic_value >= 7'd90)  // 90cm 이상이면 리셋
//                     forced_ultrasonic_value <= 7'd10;  // 10cm로 초기화
//                 value_display_counter <= 26'd100000000;  // 약 1초간 표시
//                 ultrasonic_update_flag <= 1'b1;
//             end else if (value_display_counter > 0) begin
//                 value_display_counter <= value_display_counter - 1;
//             end else begin
//                 // 카운터가 0이 되면 자동으로 기본값으로 설정
//                 ultrasonic_update_flag <= 1'b0;
//             end
//         end else begin
//             forced_ultrasonic_value <= 7'd20;  // 초기값
//             ultrasonic_update_flag <= 1'b0;
//         end
//     end

//     // 초음파 센서 측정값 저장 레지스터
//     reg [6:0] ultrasonic_value;

//     // 초음파 센서 값 저장 로직 (트러블슈팅 수정)
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd0;
//         end else if (effective_is_ultrasonic_mode) begin
//             // 직접 버튼이 눌렸을 때 강제 값 사용
//             if (ultrasonic_update_flag) begin
//                 ultrasonic_value <= forced_ultrasonic_value;
//             end
//             // 실제 초음파 측정 완료 시 값 업데이트
//             else if (w_dp_done && w_msec > 7'd0) begin
//                 ultrasonic_value <= w_msec;
//             end
//             // 초기 기본값 설정
//             else if (ultrasonic_value == 7'd0) begin
//                 ultrasonic_value <= 7'd15;  // 기본값
//             end
//         end
//     end

//     // 센서 데이터 표시용 MUX - 수정
//     wire [7:0] display_sensor_data;

//     // 트러블슈팅: 강제 값을 포함한 멀티플렉싱
//     assign display_sensor_data = effective_is_ultrasonic_mode ? 
//                                  {1'b0, (ultrasonic_value > 7'd0 ? ultrasonic_value : 7'd15)} :
//                                  (effective_is_temp_humid_mode ? dnt_sensor_data : 8'd0);

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 추가
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset),
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw),
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~effective_is_clock_mode & ~effective_is_ultrasonic_mode & ~effective_is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~effective_is_clock_mode & ~effective_is_ultrasonic_mode & ~effective_is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec),
//         .btn_min(final_btn_min),
//         .btn_hour(final_btn_hour),
//         .enable(effective_is_clock_mode),  // 강제 모드 플래그 사용
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈 - 수정: 버튼과 자동 트리거 사용
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(ultrasonic_btn_start | auto_measure_trigger | ultrasonic_enable),  // 수동 + 자동 트리거
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(),
//         .start(),
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어) - 강제 모드 플래그 사용
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_start(w_btn_run & effective_is_temp_humid_mode | temp_humid_enable),  // 강제 모드 플래그 사용
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn),  // 온습도 모드용 버튼 직접 사용
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서 - 강제 상태 사용
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(effective_is_clock_mode),
//         .current_state(effective_state),  // 강제 상태 사용
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러 - 강제 상태 사용
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(effective_is_clock_mode),
//         .sw(uart_sw),
//         .current_state(effective_state),  // 강제 상태 사용
//         .msec(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? disp_sec : disp_sec),  // 단위 표시 유지
//         .min(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(effective_is_ultrasonic_mode || effective_is_temp_humid_mode ? 5'd0 : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: DUT 상태 표시용 확장된 LED
//     assign led = {
//         idle,
//         start,
//         wait_state,
//         sync_low_out,
//         sync_high_out,
//         data_sync_out,
//         data_bit_out,
//         stop_out,
//         read
//     };

// endmodule


// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [2:0] hw_sw,  // 하드웨어 스위치 입력 (3비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire w_start_dp;
//     wire [3:0] w_led_status;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [2:0] combined_sw = hw_sw | {uart_sw, 1'b0};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 센서 데이터 (추가)
//     wire [7:0] ultrasonic_data;
//     assign ultrasonic_data[6:0] = w_msec;
//     assign ultrasonic_data[7] = 1'b0;  // 상위 비트는 0으로 설정

//     // 초음파 버튼 시작 신호 - ultrasonic_mode_btn을 직접 사용
//     wire ultrasonic_btn_start;
//     assign ultrasonic_btn_start = is_ultrasonic_mode ? ultrasonic_mode_btn : 1'b0;

//     // 초음파 센서 측정값 저장 레지스터 - 개선된 방식
//     reg [6:0] ultrasonic_value;
//     reg [19:0] display_stable_counter;  // 안정적인 표시를 위한 카운터 추가
//     reg ultrasonic_updated;             // 업데이트 플래그

//     // 초음파 센서 값 저장 로직 개선
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd0;
//             display_stable_counter <= 20'd0;
//             ultrasonic_updated <= 1'b0;
//         end else begin
//             // 초음파 측정 완료 시 값 업데이트
//             if (is_ultrasonic_mode && w_dp_done) begin
//                 // 0이 아닌 값만 업데이트 (노이즈 필터링)
//                 if (w_msec > 0) begin
//                     ultrasonic_value <= w_msec;
//                     ultrasonic_updated <= 1'b1;
//                     display_stable_counter <= 20'd20000000;  // 약 0.2초 (100MHz 기준)
//                 end
//             end else if (display_stable_counter > 0) begin
//                 display_stable_counter <= display_stable_counter - 1;
//             end else begin
//                 ultrasonic_updated <= 1'b0;  // 표시 시간 종료
//             end
//         end
//     end

//     // 센서 데이터 표시용 MUX - 개선된 방식
//     wire [7:0] display_sensor_data;

//     // 수정: 초음파 값이 업데이트되고 안정적인 표시 기간 동안 표시
//     assign display_sensor_data = is_ultrasonic_mode ? 
//                                (ultrasonic_updated ? {1'b0, ultrasonic_value} : 8'd15) : 
//                                dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 추가
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset),
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw),
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec),
//         .btn_min(final_btn_min),
//         .btn_hour(final_btn_hour),
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈 - 직접 ultrasonic_btn_start 연결
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(ultrasonic_btn_start | ultrasonic_enable),  // 버튼 또는 UART 명령으로 측정 시작
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(),
//         .start(),
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어) - XDC에 매핑된 temp_humid_mode_btn 사용
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_start(w_btn_run & is_temp_humid_mode | temp_humid_enable),
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn),  // 온습도 모드용 버튼 사용
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서 - 올바른 current_state 연결
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),  // 정확한 current_state 전달
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러 수정 - 센서 데이터 처리 개선
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? disp_sec : disp_sec),  // 수정: 단위 표시를 위해 disp_sec 사용
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? 5'd0 : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: DUT 상태 표시용 확장된 LED
//     assign led = {
//         idle,
//         start,
//         wait_state,
//         sync_low_out,
//         sync_high_out,
//         data_sync_out,
//         data_bit_out,
//         stop_out,
//         read
//     };

// endmodule

// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [2:0] hw_sw,  // 하드웨어 스위치 입력 (3비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire w_start_dp;
//     wire [3:0] w_led_status;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [2:0] combined_sw = hw_sw | {uart_sw, 1'b0};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 센서 데이터 (추가)
//     wire [7:0] ultrasonic_data;
//     assign ultrasonic_data[6:0] = w_msec;
//     assign ultrasonic_data[7] = 1'b0;  // 상위 비트는 0으로 설정

//     // 초음파 버튼 시작 신호 - ultrasonic_mode_btn을 직접 사용
//     wire ultrasonic_btn_start;
//     assign ultrasonic_btn_start = is_ultrasonic_mode ? ultrasonic_mode_btn : 1'b0;

//     // 초음파 센서 측정값 저장 레지스터
//     reg [6:0] ultrasonic_value;
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd0;
//         end else if (is_ultrasonic_mode && w_dp_done) begin
//             // 초음파 측정 완료 시 값 업데이트
//             ultrasonic_value <= w_msec;
//         end
//     end

//     // 센서 데이터 표시용 MUX
//     wire [7:0] display_sensor_data;
//     assign display_sensor_data = is_ultrasonic_mode ? {1'b0, ultrasonic_value} : dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 추가
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset),
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw),
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec),
//         .btn_min(final_btn_min),
//         .btn_hour(final_btn_hour),
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈 - 직접 ultrasonic_btn_start 연결
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(ultrasonic_btn_start | ultrasonic_enable),  // 버튼 또는 UART 명령으로 측정 시작
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(),
//         .start(),
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어) - XDC에 매핑된 temp_humid_mode_btn 사용
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_start(w_btn_run & is_temp_humid_mode | temp_humid_enable),
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn),  // 온습도 모드용 버튼 사용
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러 수정 - 센서 데이터 처리 개선
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? {1'b0, display_sensor_data[7:4]} : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: DUT 상태 표시용 확장된 LED
//     assign led = {
//         idle,
//         start,
//         wait_state,
//         sync_low_out,
//         sync_high_out,
//         data_sync_out,
//         data_bit_out,
//         stop_out,
//         read
//     };

// endmodule
// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음

//     input ultrasonic_mode_btn,  // XDC에 매핑된 초음파 모드 버튼 (T18)
//     input temp_humid_mode_btn,  // XDC에 매핑된 온습도 모드 버튼 (W19)
//     input [2:0] hw_sw,  // 하드웨어 스위치 입력 (3비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire w_start_dp;
//     wire [3:0] w_led_status;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [2:0] combined_sw = hw_sw | {uart_sw, 1'b0};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 센서 데이터 (추가)
//     wire [7:0] ultrasonic_data;
//     assign ultrasonic_data[6:0] = w_msec;
//     assign ultrasonic_data[7] = 1'b0;  // 상위 비트는 0으로 설정

//     // 초음파 센서 측정값 저장 레지스터
//     reg [6:0] ultrasonic_value;
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd0;
//         end else if (is_ultrasonic_mode && w_dp_done) begin
//             // 초음파 측정 완료 시 값 업데이트
//             ultrasonic_value <= w_msec;
//         end
//     end

//     // 센서 데이터 표시용 MUX
//     wire [7:0] display_sensor_data;
//     assign display_sensor_data = is_ultrasonic_mode ? {1'b0, ultrasonic_value} : dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 추가
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset),
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw),
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec),
//         .btn_min(final_btn_min),
//         .btn_hour(final_btn_hour),
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈 - XDC에 매핑된 ultrasonic_mode_btn 사용
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(ultrasonic_mode_btn | (w_btn_run & is_ultrasonic_mode) | ultrasonic_enable),
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(),
//         .start(),
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어) - XDC에 매핑된 temp_humid_mode_btn 사용
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_start(w_btn_run & is_temp_humid_mode | temp_humid_enable),
//         .tick_counter(w_tick_10msec),
//         .btn_next(temp_humid_mode_btn),  // 온습도 모드용 버튼 사용
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러 수정 - 센서 데이터 처리 개선
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? {1'b0, display_sensor_data[7:4]} : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: DUT 상태 표시용 확장된 LED
//     assign led = {
//         idle,
//         start,
//         wait_state,
//         sync_low_out,
//         sync_high_out,
//         data_sync_out,
//         data_bit_out,
//         stop_out,
//         read
//     };

// endmodule
// module top_stopwatch (
//     input clk,
//     input reset,
//     input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
//     input btn_clear,  // 우측 버튼 - 스톱워치 초기화
//     // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
//     // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음
//     input debounced_btn,  // 디바운싱된 입력 (U17)
//     input [2:0] hw_sw,  // 하드웨어 스위치 입력 (3비트로 확장)
//     input rx,  // UART RX 입력
//     output tx,  // UART TX 출력
//     // 추가된 인터페이스
//     output trigger,
//     input echo,
//     inout dht_data,
//     output [3:0] fnd_comm,
//     output [7:0] fnd_font,
//     output [8:0] led  // 9비트로 확장
// );
//     // 디바운싱된 버튼 신호들
//     wire w_btn_run, w_btn_clear;
//     // 모드별 버튼 분기
//     wire w_btn_hour;

//     // 디바운싱된 버튼을 btn_next로 사용
//     wire btn_next;
//     assign btn_next = debounced_btn;  // debounced_btn을 btn_next로 연결

//     // FSM 신호들 (3비트로 확장)
//     wire [2:0] current_state;
//     wire is_clock_mode, is_ultrasonic_mode, is_temp_humid_mode;
//     wire sw2, sw3, sw4, sw5;

//     // 스톱워치 제어 신호
//     wire w_run, w_clear;

//     // 시간 데이터 신호들 (스톱워치와 시계)
//     wire [6:0] s_msec, c_msec, disp_msec;
//     wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
//     wire [4:0] s_hour, c_hour, disp_hour;

//     // UART로부터 오는 제어 신호
//     wire [1:0] uart_sw;
//     wire uart_w_run, uart_w_clear;
//     wire uart_btn_hour, uart_btn_min, uart_btn_sec;
//     // UART RX 신호
//     wire       w_rx_done;  // RX 완료 신호
//     wire [7:0] w_rx_data;  // RX 데이터
//     wire ultrasonic_enable, temp_humid_enable;

//     // 초음파 센서 신호
//     wire [6:0] w_msec;
//     wire w_dp_done;
//     wire w_start_dp;
//     wire [3:0] w_led_status;
//     wire w_fsm_error;
//     wire w_tick_10msec;

//     // DUT 컨트롤러 신호
//     wire sensor_data;
//     wire [3:0] dut_current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire dnt_io;
//     wire idle, start, wait_state, sync_low_out, sync_high_out;
//     wire data_sync_out, data_bit_out, stop_out, read;

//     // 하드웨어와 UART 스위치 신호 결합
//     wire [2:0] combined_sw = hw_sw | {uart_sw, 1'b0};

//     // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
//     wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
//     wire final_btn_min = (uart_btn_min) & is_clock_mode;
//     wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

//     // 초음파 센서 데이터 (추가)
//     wire [7:0] ultrasonic_data;
//     assign ultrasonic_data[6:0] = w_msec;
//     assign ultrasonic_data[7] = 1'b0;  // 상위 비트는 0으로 설정

//     // 초음파 센서 측정값 저장 레지스터
//     reg [6:0] ultrasonic_value;
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             ultrasonic_value <= 7'd0;
//         end else if (is_ultrasonic_mode && w_dp_done) begin
//             // 초음파 측정 완료 시 값 업데이트
//             ultrasonic_value <= w_msec;
//         end
//     end

//     // 센서 데이터 표시용 MUX
//     wire [7:0] display_sensor_data;
//     assign display_sensor_data = is_ultrasonic_mode ? {1'b0, ultrasonic_value} : dnt_sensor_data;

//     // DHT11 센서 양방향 연결 (inout 포트에 연결)
//     assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

//     // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
//     btn_debounce U_Btn_DB_RUN (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_run),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd0),
//         .o_btn(w_btn_run)
//     );

//     btn_debounce U_Btn_DB_CLEAR (
//         .clk(clk),
//         .reset(reset),
//         .i_btn(btn_clear),
//         .rx_done(w_rx_done),
//         .rx_data(w_rx_data),
//         .btn_type(3'd1),
//         .o_btn(w_btn_clear)
//     );

//     // UART + FIFO + CU 모듈 추가
//     uart_fifo_top U_UART_FIFO_TOP (
//         .clk(clk),
//         .rst(reset),
//         .rx(rx),
//         .tx(tx),
//         .w_run(uart_w_run),
//         .w_clear(uart_w_clear),
//         .btn_hour(uart_btn_hour),
//         .btn_min(uart_btn_min),
//         .btn_sec(uart_btn_sec),
//         .sw(uart_sw),
//         .o_run(w_run),
//         .current_state(current_state),
//         .w_rx_done(w_rx_done),
//         .w_rx_data(w_rx_data),
//         .ultrasonic_enable(ultrasonic_enable),
//         .temp_humid_enable(temp_humid_enable)
//     );

//     // FSM 컨트롤러 - 확장된 버전
//     fsm_controller U_FSM (
//         .clk(clk),
//         .reset(reset),
//         .sw(combined_sw),
//         .btn_run(w_btn_run | uart_w_run),
//         .sw_mode_in(is_clock_mode),
//         .current_state(current_state),
//         .is_clock_mode(is_clock_mode),
//         .is_ultrasonic_mode(is_ultrasonic_mode),
//         .is_temp_humid_mode(is_temp_humid_mode),
//         .sw2(sw2),
//         .sw3(sw3),
//         .sw4(sw4),
//         .sw5(sw5)
//     );

//     // 스톱워치 제어 유닛
//     stopwatch_cu U_STOPWATCH_CU (
//         .clk(clk),
//         .reset(reset),
//         .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode & ~is_ultrasonic_mode & ~is_temp_humid_mode),
//         .o_run(w_run),
//         .o_clear(w_clear)
//     );

//     // 스톱워치 데이터 패스
//     stopwatch_dp U_STOPWATCH_DP (
//         .clk  (clk),
//         .reset(reset),
//         .run  (w_run),
//         .clear(w_clear),
//         .msec (s_msec),
//         .sec  (s_sec),
//         .min  (s_min),
//         .hour (s_hour)
//     );

//     // 시계 모듈
//     clock U_CLOCK (
//         .clk(clk),
//         .reset(reset),
//         .btn_sec(final_btn_sec),
//         .btn_min(final_btn_min),
//         .btn_hour(final_btn_hour),
//         .enable(is_clock_mode),
//         .o_1hz(),
//         .o_msec(c_msec),
//         .o_sec(c_sec),
//         .o_min(c_min),
//         .o_hour(c_hour)
//     );

//     // 초음파 거리 측정 모듈
//     dist_calculator U_ULTRASONIC (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(w_btn_run & is_ultrasonic_mode | ultrasonic_enable),
//         .trigger(trigger),
//         .msec(w_msec),  // 초음파 거리 출력
//         .led_indicator(),
//         .start(),
//         .done(w_dp_done)  // 측정 완료 신호 연결
//     );

//     // 10ms 틱 생성기
//     tick_generator U_TICK_GEN (
//         .clk(clk),
//         .reset(reset),
//         .tick_10msec(w_tick_10msec)
//     );

//     // DUT 컨트롤러 (온습도 센서 제어) - 개선된 버전
//     dut_ctr U_DUT_CTR (
//         .clk(clk),
//         .rst(reset),
//         .btn_start(w_btn_run & is_temp_humid_mode | temp_humid_enable),
//         .tick_counter(w_tick_10msec),
//         .btn_next(btn_next),  // 온도/습도 표시 전환용 버튼
//         .sensor_data(sensor_data),
//         .current_state(dut_current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dnt_io),
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out),
//         .read(read)
//     );

//     // 디스플레이 멀티플렉서
//     display_mux U_DISPLAY_MUX (
//         .sw_mode(is_clock_mode),
//         .current_state(current_state),
//         .sw_msec(s_msec),
//         .sw_sec(s_sec),
//         .sw_min(s_min),
//         .sw_hour(s_hour),
//         .clk_msec(c_msec),
//         .clk_sec(c_sec),
//         .clk_min(c_min),
//         .clk_hour(c_hour),
//         .sensor_value(display_sensor_data),  // 통합된 센서 값 연결
//         .o_msec(disp_msec),
//         .o_sec(disp_sec),
//         .o_min(disp_min),
//         .o_hour(disp_hour)
//     );

//     // FND 컨트롤러 수정 - 센서 데이터 처리 개선
//     fnd_controller U_FND_CTRL (
//         .clk(clk),
//         .reset(reset),
//         .sw_mode(is_clock_mode),
//         .sw(uart_sw),
//         .current_state(current_state),
//         .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
//         .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
//         .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
//         .hour(is_ultrasonic_mode || is_temp_humid_mode ? {1'b0, display_sensor_data[7:4]} : disp_hour),
//         .fnd_font(fnd_font),
//         .fnd_comm(fnd_comm)
//     );

//     // LED 출력: DUT 상태 표시용 확장된 LED
//     assign led = {
//         idle,
//         start,
//         wait_state,
//         sync_low_out,
//         sync_high_out,
//         data_sync_out,
//         data_bit_out,
//         stop_out,
//         read
//     };

// endmodule
