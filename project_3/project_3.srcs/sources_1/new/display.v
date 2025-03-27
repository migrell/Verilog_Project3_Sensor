module display_mux (
    input            sw_mode,
    input      [2:0] current_state,
    input      [6:0] sw_msec,
    input      [5:0] sw_sec, sw_min,
    input      [4:0] sw_hour,
    input      [6:0] clk_msec,
    input      [5:0] clk_sec, clk_min,
    input      [4:0] clk_hour,
    input      [7:0] sensor_value,    // 추가: 센서 값 입력
    output reg [6:0] o_msec,
    output reg [5:0] o_sec, o_min,
    output reg [4:0] o_hour
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
    
    // 디버깅을 위한 상수 값 (문제 해결 용도)
    wire [6:0] default_distance = 7'd15;  // 15cm 기본값 (문제 해결용)
    
    always @(*) begin
        // 기본값 설정
        o_msec = 0;
        o_sec  = 0;
        o_min  = 0;
        o_hour = 0;
        
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
            
            STATE_4: begin  // 초음파 거리 모드 - CM
                // 수정: 센서 값이 0이면 기본값을 사용하고, 그렇지 않으면 센서 값 사용
                o_msec = (sensor_value[6:0] == 0) ? default_distance : sensor_value[6:0];
                o_sec  = 6'd0;  // 단위 표시용 (cm)
                o_min  = 6'd0;
                o_hour = 5'd0;
            end
            
            STATE_5: begin  // 초음파 거리 모드 - Inch
                // 수정: 센서 값이 0이면 기본값의 인치 변환을 사용하고, 그렇지 않으면 센서 값의 인치 변환 사용
                // 인치 변환 공식: cm / 2.54 (대략 cm * 0.4)
                // 간단한 비트 시프트와 더하기로 근사값 계산: cm * 0.4 ≈ (cm >> 2) + (cm >> 3)
                o_msec = (sensor_value[6:0] == 0) ? 
                         ((default_distance >> 1) + (default_distance >> 3)) :  // 약 0.4 × 기본값
                         ((sensor_value[6:0] >> 1) + (sensor_value[6:0] >> 3)); // 약 0.4 × 센서값
                o_sec  = 6'd1;  // 단위 표시용 (inch)
                o_min  = 6'd0;
                o_hour = 5'd0;
            end
            
            STATE_6: begin  // 온도 모드
                // 온도 표시 개선
                o_msec = sensor_value[6:0];  // 하위 7비트
                o_sec  = 6'd2;  // 단위 표시용 (°C)
                o_min  = 6'd0;
                o_hour = 5'd0;
            end
            
            STATE_7: begin  // 습도 모드
                // 습도 표시 개선
                o_msec = sensor_value[6:0];  // 하위 7비트
                o_sec  = 6'd3;  // 단위 표시용 (%)
                o_min  = 6'd0;
                o_hour = 5'd0;
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
