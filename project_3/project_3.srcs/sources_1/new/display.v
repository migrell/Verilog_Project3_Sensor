module display_mux(
    input sw_mode,               // 안 써도 됨 (참고용)
    input [2:0] current_state,   // FSM 현재 상태 (3비트로 확장)
    input [6:0] sw_msec,
    input [5:0] sw_sec, sw_min,
    input [4:0] sw_hour,
    input [6:0] clk_msec,
    input [5:0] clk_sec, clk_min,
    input [4:0] clk_hour,
    output reg [6:0] o_msec,
    output reg [5:0] o_sec, o_min,
    output reg [4:0] o_hour,
    output reg[7:0] sensor_value
);

    // 상태 정의
    parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
    parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
    parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
    parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
    parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
    parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch
    parameter STATE_6 = 3'b110;  // Temperature Mode
    parameter STATE_7 = 3'b111;  // Humidity Mode

    always @(*) begin
        case (current_state)
            STATE_0, STATE_1: begin  // 스톱워치 모드
                o_msec = sw_msec;
                o_sec  = sw_sec;
                o_min  = sw_min;
                o_hour = sw_hour;
            end
            
            STATE_2, STATE_3: begin  // 시계 모드
                o_msec = clk_msec;
                o_sec  = clk_sec;
                o_min  = clk_min;
                o_hour = clk_hour;
            end
            
            STATE_4, STATE_5, STATE_6, STATE_7: begin  // 센서 모드들
                // 초음파 및 온습도 센서 데이터는 DUT 컨트롤러에서 직접 처리
                // 이 모드들에서는 dut_ctr 모듈의 출력을 사용하므로
                // 여기서는 기본값만 설정
                o_msec = 0;
                o_sec  = 0;
                o_min  = 0;
                o_hour = 0;
                
                sensor_value = dnt_sensor_data;
            end
            
            default: begin
                o_msec = 0;
                o_sec  = 0;
                o_min  = 0;
                o_hour = 0;
            end
        endcase
    end
endmodule