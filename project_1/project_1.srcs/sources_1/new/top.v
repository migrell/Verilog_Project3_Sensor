module ultrasonic_distance_meter(
    input clk,           // 시스템 클럭 (100MHz)
    input reset,         // 리셋 신호
    input echo,          // 초음파 센서 에코 핀
    output trigger,      // 초음파 센서 트리거 핀
    output [3:0] fnd_comm,  // FND 공통단자 선택 신호
    output [7:0] fnd_font,  // FND 세그먼트 신호 (7세그먼트 + 도트)
    output [3:0] led     // LED 상태 출력
);

    // 내부 신호
    wire [6:0] w_msec;       // 거리 값 (0-99cm)
    wire w_dp_done;          // DP 모듈에서 측정 완료 신호
    wire w_start_dp;         // CU에서 DP 시작 신호
    
    // LED 출력 할당
    assign led = w_led_status;

    // CU(Control Unit) 인스턴스
    cu U_cu(
        .clk(clk),
        .reset(reset),
        .dp_done(w_dp_done),
        .trigger(trigger),
        .start_dp(w_start_dp),
        .led_status(w_led_status)
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
        .msec(w_msec),
        .fnd_font(fnd_font),
        .fnd_comm(fnd_comm)
    );

endmodule