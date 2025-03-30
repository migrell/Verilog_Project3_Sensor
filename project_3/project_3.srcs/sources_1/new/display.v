module display_mux (
    input            sw_mode,        // 시계 모드 활성화 신호
    input      [2:0] current_state,  // 현재 FSM 상태
    input      [6:0] sw_msec,        // 스톱워치 밀리초
    input      [5:0] sw_sec,         // 스톱워치 초
    input      [5:0] sw_min,         // 스톱워치 분
    input      [4:0] sw_hour,        // 스톱워치 시
    input      [6:0] clk_msec,       // 시계 밀리초
    input      [5:0] clk_sec,        // 시계 초
    input      [5:0] clk_min,        // 시계 분
    input      [4:0] clk_hour,       // 시계 시
    input      [7:0] sensor_value,   // 센서 값 입력 (초음파, 온습도)
    output reg [6:0] o_msec,         // 출력 밀리초
    output reg [5:0] o_sec,          // 출력 초
    output reg [5:0] o_min,          // 출력 분
    output reg [4:0] o_hour          // 출력 시
);

    // 상태 정의
    parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
    parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
    parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
    parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
    parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
    parameter STATE_5 = 3'b101;  // 사용하지 않음 (이전에 Ultrasonic Mode Inch)
    parameter STATE_6 = 3'b110;  // Temperature Mode
    parameter STATE_7 = 3'b111;  // Humidity Mode

    always @(*) begin
        // 기본값 설정
        o_msec = 7'd0;
        o_sec  = 6'd0;
        o_min  = 6'd0;
        o_hour = 5'd0;

        case (current_state)
            STATE_0, STATE_1: begin
                // 스톱워치 모드
                o_msec = sw_msec;
                o_sec  = sw_sec;
                o_min  = sw_min;
                o_hour = sw_hour;
            end

            STATE_2, STATE_3: begin
                // 시계 모드
                o_msec = clk_msec;
                o_sec  = clk_sec;
                o_min  = clk_min;
                o_hour = clk_hour;
            end
            // 초음파 거리 모드 처리 부분
            STATE_4, STATE_5: begin
                // 센서 값을 직접 출력 (msec 출력에 할당)
                o_msec = sensor_value[6:0];  // 하위 7비트만 사용
                o_sec = 6'd0;   // 센티미터 모드 (특수 표시를 위한 값)
                o_min = 6'd0;
                o_hour = 5'd0;
            end

            STATE_6: begin
                // 온도 모드
                o_msec = sensor_value[6:0];  // 하위 7비트만 사용
                o_sec  = 6'd2;  // 온도 모드 (°C 표시를 위한 값)
                o_min  = 6'd0;
                o_hour = 5'd0;
            end

            STATE_7: begin
                // 습도 모드
                o_msec = sensor_value[6:0];  // 하위 7비트만 사용
                o_sec  = 6'd3;  // 습도 모드 (% 표시를 위한 값)
                o_min  = 6'd0;
                o_hour = 5'd0;
            end

            default: begin
                o_msec = 7'd0;
                o_sec  = 6'd0;
                o_min  = 6'd0;
                o_hour = 5'd0;
            end
        endcase
    end

endmodule
// module display_mux (
//     input            sw_mode,
//     input      [2:0] current_state,
//     input      [6:0] sw_msec,
//     input      [5:0] sw_sec, sw_min,
//     input      [4:0] sw_hour,
//     input      [6:0] clk_msec,
//     input      [5:0] clk_sec, clk_min,
//     input      [4:0] clk_hour,
//     input      [7:0] sensor_value,    // 추가: 센서 값 입력
//     output reg [6:0] o_msec,
//     output reg [5:0] o_sec, o_min,
//     output reg [4:0] o_hour
// );
//     // 상태 정의
//     parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
//     parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
//     parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch
//     parameter STATE_6 = 3'b110;  // Temperature Mode
//     parameter STATE_7 = 3'b111;  // Humidity Mode

//     // 디버깅을 위한 임시 값 (실제 코드에서는 제거)
//     // wire [7:0] debug_sensor = 8'h32; // 50 (테스트용)

//     always @(*) begin
//         // 기본값 설정
//         o_msec = 0;
//         o_sec  = 0;
//         o_min  = 0;
//         o_hour = 0;

//         case (current_state)
//             STATE_0, STATE_1: begin  // 스톱워치 모드
//                 o_msec = sw_msec;
//                 o_sec  = sw_sec;
//                 o_min  = sw_min;
//                 o_hour = sw_hour;
//             end

//             STATE_2, STATE_3: begin  // 시계 모드
//                 o_msec = clk_msec;
//                 o_sec  = clk_sec;
//                 o_min  = clk_min;
//                 o_hour = clk_hour;
//             end

//             STATE_4: begin  // 초음파 거리 모드 - CM
//                 // 단순화된 출력 - 전체 값 표시
//                 o_msec = {1'b0, sensor_value[6:0]};  // 하위 7비트
//                 o_sec  = 6'b0;
//                 o_min  = 6'b0;
//                 o_hour = 5'b0;
//             end

//             STATE_5: begin  // 초음파 거리 모드 - Inch
//                 // 단순화된 인치 변환 - 비트 시프트 사용
//                 o_msec = {1'b0, sensor_value[6:1]};  // 센서값/2 근사치
//                 o_sec  = 6'b0;
//                 o_min  = 6'b0;
//                 o_hour = 5'b0;
//             end

//             STATE_6: begin  // 온도 모드
//                 // 온도를 그대로 표시 (BCD 변환 없이)
//                 o_msec = {1'b0, sensor_value[6:0]};
//                 o_sec  = 6'b0;
//                 o_min  = 6'b0;
//                 o_hour = 5'b0;
//             end

//             STATE_7: begin  // 습도 모드
//                 // 습도를 그대로 표시
//                 o_msec = {1'b0, sensor_value[6:0]};
//                 o_sec  = 6'b0;
//                 o_min  = 6'b0;
//                 o_hour = 5'b0;
//             end

//             default: begin
//                 o_msec = 0;
//                 o_sec  = 0;
//                 o_min  = 0;
//                 o_hour = 0;
//             end
//         endcase
//     end
// endmodule

// module display_mux(
//     input sw_mode,               // 안 써도 됨 (참고용)
//     input [2:0] current_state,   // FSM 현재 상태 (3비트로 확장)
//     input [6:0] sw_msec,
//     input [5:0] sw_sec, sw_min,
//     input [4:0] sw_hour,
//     input [6:0] clk_msec,
//     input [5:0] clk_sec, clk_min,
//     input [4:0] clk_hour,
//     output reg [6:0] o_msec,
//     output reg [5:0] o_sec, o_min,
//     output reg [4:0] o_hour,
//     output reg[7:0] sensor_value
// );

//     // 상태 정의
//     parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
//     parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
//     parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch
//     parameter STATE_6 = 3'b110;  // Temperature Mode
//     parameter STATE_7 = 3'b111;  // Humidity Mode

//     always @(*) begin
//         case (current_state)
//             STATE_0, STATE_1: begin  // 스톱워치 모드
//                 o_msec = sw_msec;
//                 o_sec  = sw_sec;
//                 o_min  = sw_min;
//                 o_hour = sw_hour;
//             end

//             STATE_2, STATE_3: begin  // 시계 모드
//                 o_msec = clk_msec;
//                 o_sec  = clk_sec;
//                 o_min  = clk_min;
//                 o_hour = clk_hour;
//             end

//             STATE_4, STATE_5, STATE_6, STATE_7: begin  // 센서 모드들
//                 // 초음파 및 온습도 센서 데이터는 DUT 컨트롤러에서 직접 처리
//                 // 이 모드들에서는 dut_ctr 모듈의 출력을 사용하므로
//                 // 여기서는 기본값만 설정
//                 o_msec = 0;
//                 o_sec  = 0;
//                 o_min  = 0;
//                 o_hour = 0;

//                 sensor_value = dnt_sensor_data;
//             end

//             default: begin
//                 o_msec = 0;
//                 o_sec  = 0;
//                 o_min  = 0;
//                 o_hour = 0;
//             end
//         endcase
//     end
// endmodule
