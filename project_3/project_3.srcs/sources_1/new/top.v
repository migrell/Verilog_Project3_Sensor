module top_stopwatch (
    input clk,
    input reset,
    input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
    input btn_clear,  // 우측 버튼 - 스톱워치 초기화
    // input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드) - 사용하지 않음
    // input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드) - 사용하지 않음
    input debounced_btn,  // 디바운싱된 입력 (T18) - 초음파 센서 측정 버튼으로 직접 사용
    input [2:0] hw_sw,  // 하드웨어 스위치 입력 (3비트로 확장)
    input rx,  // UART RX 입력
    output tx,  // UART TX 출력
    // 추가된 인터페이스
    output trigger,
    input echo,
    inout dht_data,
    output [3:0] fnd_comm,
    output [7:0] fnd_font,
    output [8:0] led  // 9비트로 확장
);
    // 디바운싱된 버튼 신호들
    wire w_btn_run, w_btn_clear;
    // 모드별 버튼 분기
    wire w_btn_hour;

    // 버튼 분기 및 신호 라우팅
    // 초음파 모드와 온습도 모드를 위한 별도의 버튼 신호
    wire ultrasonic_mode_btn;   // 초음파 모드에서의 버튼 신호
    wire temp_humid_mode_btn;   // 온습도 모드에서의 버튼 신호
    
    // 모드에 따라 debounced_btn 신호 분기
    assign ultrasonic_mode_btn = is_ultrasonic_mode ? debounced_btn : 1'b0;
    assign temp_humid_mode_btn = is_temp_humid_mode ? debounced_btn : 1'b0;

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
    wire w_dp_done;
    wire w_start_dp;
    wire [3:0] w_led_status;
    wire w_fsm_error;
    wire w_tick_10msec;

    // DUT 컨트롤러 신호
    wire sensor_data;
    wire [3:0] dut_current_state;
    wire [7:0] dnt_data;
    wire [7:0] dnt_sensor_data;
    wire dnt_io;
    wire idle, start, wait_state, sync_low_out, sync_high_out;
    wire data_sync_out, data_bit_out, stop_out, read;

    // 하드웨어와 UART 스위치 신호 결합
    wire [2:0] combined_sw = hw_sw | {uart_sw, 1'b0};

    // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
    wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode;
    wire final_btn_min = (uart_btn_min) & is_clock_mode;
    wire final_btn_sec = (uart_btn_sec) & is_clock_mode;

    // 초음파 센서 데이터 (추가)
    wire [7:0] ultrasonic_data;
    assign ultrasonic_data[6:0] = w_msec;
    assign ultrasonic_data[7] = 1'b0;  // 상위 비트는 0으로 설정

    // 초음파 센서 측정값 저장 레지스터
    reg [6:0] ultrasonic_value;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ultrasonic_value <= 7'd0;
        end else if (is_ultrasonic_mode && w_dp_done) begin
            // 초음파 측정 완료 시 값 업데이트
            ultrasonic_value <= w_msec;
        end
    end
    
    // 센서 데이터 표시용 MUX
    wire [7:0] display_sensor_data;
    assign display_sensor_data = is_ultrasonic_mode ? {1'b0, ultrasonic_value} : dnt_sensor_data;

    // DHT11 센서 양방향 연결 (inout 포트에 연결)
    assign dht_data = dnt_io ? 1'bz : 1'b0;  // 출력 모드일 때만 0 출력, 입력 모드에서는 하이 임피던스

    // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
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

    // UART + FIFO + CU 모듈 추가
    uart_fifo_top U_UART_FIFO_TOP (
        .clk(clk),
        .rst(reset),
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
        .sw(combined_sw),
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
        .btn_sec(final_btn_sec),
        .btn_min(final_btn_min),
        .btn_hour(final_btn_hour),
        .enable(is_clock_mode),
        .o_1hz(),
        .o_msec(c_msec),
        .o_sec(c_sec),
        .o_min(c_min),
        .o_hour(c_hour)
    );

    // 초음파 거리 측정 모듈 - 수정된 부분: debounced_btn을 직접 연결
    dist_calculator U_ULTRASONIC (
        .clk(clk),
        .reset(reset),
        .echo(echo),
        .btn_start(ultrasonic_mode_btn | (w_btn_run & is_ultrasonic_mode) | ultrasonic_enable),
        .trigger(trigger),
        .msec(w_msec),  // 초음파 거리 출력
        .led_indicator(),
        .start(),
        .done(w_dp_done)  // 측정 완료 신호 연결
    );

    // 10ms 틱 생성기
    tick_generator U_TICK_GEN (
        .clk(clk),
        .reset(reset),
        .tick_10msec(w_tick_10msec)
    );

    // DUT 컨트롤러 (온습도 센서 제어) - 수정: temp_humid_mode_btn을 직접 연결
    dut_ctr U_DUT_CTR (
        .clk(clk),
        .rst(reset),
        .btn_start(w_btn_run & is_temp_humid_mode | temp_humid_enable),
        .tick_counter(w_tick_10msec),
        .btn_next(temp_humid_mode_btn),  // 온습도 모드일 때만 버튼 사용
        .sensor_data(sensor_data),
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

    // FND 컨트롤러 수정 - 센서 데이터 처리 개선
    fnd_controller U_FND_CTRL (
        .clk(clk),
        .reset(reset),
        .sw_mode(is_clock_mode),
        .sw(uart_sw),
        .current_state(current_state),
        .msec(is_ultrasonic_mode || is_temp_humid_mode ? display_sensor_data[6:0] : disp_msec),
        .sec(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_sec),
        .min(is_ultrasonic_mode || is_temp_humid_mode ? 6'd0 : disp_min),
        .hour(is_ultrasonic_mode || is_temp_humid_mode ? {1'b0, display_sensor_data[7:4]} : disp_hour),
        .fnd_font(fnd_font),
        .fnd_comm(fnd_comm)
    );

    // LED 출력: DUT 상태 표시용 확장된 LED
    assign led = {
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