module ultrasonic_distance_meter(
    input clk,           // 시스템 클럭 (100MHz)
    input reset,         // 리셋 신호
    input echo,          // 초음파 센서 에코 핀
    input btn_run,     // 시작 버튼
    output trigger,      // 초음파 센서 트리거 핀
    output [3:0] fnd_comm,  // FND 공통단자 선택 신호
    output [7:0] fnd_font,  // FND 세그먼트 신호 (7세그먼트 + 도트)
    output [3:0] led     // LED 상태 출력
);

    // 내부 신호
    wire [6:0] w_msec;         // 거리 값 (0-99cm)
    wire w_dp_done;            // DP 모듈에서 측정 완료 신호
    wire w_start_dp;           // CU에서 DP 시작 신호
    wire w_tick_10msec;        // 10msec 주기 신호
    wire [3:0] w_led_status;   // LED 상태 신호
    wire w_fsm_error;          // FSM 오류 감지 신호
    wire w_btn_debounced;      // 디바운스된 버튼 신호
    
    // 10msec tick generator 인스턴스
    tick_generator U_tick_generator(
        .clk(clk),
        .reset(reset),
        .tick_10msec(w_tick_10msec)
    );
    
    // 버튼 디바운스 모듈 추가
    btn_debounce U_btn_debounce(
        .clk(clk),
        .reset(reset),
        .i_btn(btn_run),
        .rx_done(1'b0),        // UART 기능 미사용 시 0으로 설정
        .rx_data(8'h00),       // UART 기능 미사용 시 0으로 설정
        .btn_type(3'd0),       // RUN 버튼 타입(0) 선택
        .o_btn(w_btn_debounced)
    );
    
    // LED 컨트롤러 모듈 인스턴스화
    led_controller U_led_controller(
        .clk(clk),
        .reset(reset),
        .fsm_error(w_fsm_error),
        .led_status(w_led_status),
        .led(led)
    );

    // CU(Control Unit) 인스턴스 - 디바운스된 버튼 신호 사용
    cu U_cu(
        .clk(clk),
        .reset(reset),
        .btn_run(w_btn_debounced),  // 디바운스된 버튼 신호 사용
        .echo(echo),
        .dp_done(w_dp_done),
        .tick_10msec(w_tick_10msec),
        .trigger(trigger),
        .start_dp(w_start_dp),
        .led_status(w_led_status),
        .fsm_error(w_fsm_error)
    );

    // DP(Distance Processor) 인스턴스
    dp U_dp(
        .clk(clk),
        .reset(reset),
        .echo(echo),
        .start_trigger(w_start_dp),
        .done(w_dp_done),
        .msec(w_msec)
    );

    // FND 컨트롤러 인스턴스 (간소화된 버전)
    fnd_controller U_fnd_controller(
        .clk(clk),
        .reset(reset),
        .sw_mode(1'b0),
        .sw(2'b00),
        .msec(w_msec),
        .sec(6'd0),
        .min(6'd0),
        .hour(5'd0),
        .current_state(2'b00),
        .fnd_font(fnd_font),
        .fnd_comm(fnd_comm)
    );
endmodule