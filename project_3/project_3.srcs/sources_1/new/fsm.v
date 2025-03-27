module fsm_controller(
    input clk,
    input reset,
    input [2:0] sw,          // 3비트로 확장
    input btn_run,
    input sw_mode_in,
    output reg [2:0] current_state,  // 3비트로 확장
    output is_clock_mode,
    output is_ultrasonic_mode,
    output is_temp_humid_mode,
    output reg sw2,
    output reg sw3,
    output reg sw4,
    output reg sw5
);
    // 상태 정의 (3비트로 확장)
    parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
    parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
    parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
    parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
    parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
    parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch
    parameter STATE_6 = 3'b110;  // Temperature Mode
    parameter STATE_7 = 3'b111;  // Humidity Mode
    
    // 다음 상태를 저장할 레지스터
    reg [2:0] next_state;
    
    // 다음 상태 논리 (조합 논리)
    always @(*) begin
        // 기본값은 현재 상태 유지
        next_state = current_state;
        
        case (current_state)
            // 기존 스톱워치/시계 모드 전환 로직 유지하면서 확장
            STATE_0: begin // Stopwatch Msec:Sec
                if (sw == 3'b001)           // sw[0]=1, 나머지=0
                    next_state = STATE_1;
                else if (sw == 3'b010)      // sw[1]=1, 나머지=0
                    next_state = STATE_2;
                else if (sw == 3'b100)      // sw[2]=1, 나머지=0
                    next_state = STATE_4;   // 초음파 모드로 전환
            end
            
            STATE_1: begin // Stopwatch Hour:Min
                if (sw == 3'b000)
                    next_state = STATE_0;
                else if (sw == 3'b011)
                    next_state = STATE_3;
                else if (sw == 3'b101)
                    next_state = STATE_5;   // 초음파 인치 모드로 전환
            end
            
            STATE_2: begin // Clock Sec:Msec
                if (sw == 3'b000)
                    next_state = STATE_0;
                else if (sw == 3'b011)
                    next_state = STATE_3;
                else if (sw == 3'b110)
                    next_state = STATE_6;   // 온도 모드로 전환
            end
            
            STATE_3: begin // Clock Hour:Min
                if (sw == 3'b001)
                    next_state = STATE_1;
                else if (sw == 3'b010)
                    next_state = STATE_2;
                else if (sw == 3'b111)
                    next_state = STATE_7;   // 습도 모드로 전환
            end
            
            // 새로운 모드 상태 전환 로직 추가
            STATE_4: begin // Ultrasonic CM
                if (sw == 3'b000)
                    next_state = STATE_0;
                else if (sw == 3'b101)
                    next_state = STATE_5;
                else if (sw == 3'b110)
                    next_state = STATE_6;
            end
            
            STATE_5: begin // Ultrasonic Inch
                if (sw == 3'b001)
                    next_state = STATE_1;
                else if (sw == 3'b100)
                    next_state = STATE_4;
                else if (sw == 3'b111)
                    next_state = STATE_7;
            end
            
            STATE_6: begin // Temperature
                if (sw == 3'b010)
                    next_state = STATE_2;
                else if (sw == 3'b100)
                    next_state = STATE_4;
                else if (sw == 3'b111)
                    next_state = STATE_7;
            end
            
            STATE_7: begin // Humidity
                if (sw == 3'b011)
                    next_state = STATE_3;
                else if (sw == 3'b101)
                    next_state = STATE_5;
                else if (sw == 3'b110)
                    next_state = STATE_6;
            end
        endcase
    end
    
    // 상태 등록 프로세스 (순차 논리)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= STATE_0;
        end else begin
            current_state <= next_state;
        end
    end
    
    // 출력 논리 (메일리 모델 - 현재 상태와 입력에 기반)
    always @(*) begin
        // 기본값 설정
        sw2 = 1'b0;  // 스톱워치 모드
        sw3 = 1'b0;  // 시계 모드
        sw4 = 1'b0;  // 초음파 모드
        sw5 = 1'b0;  // 온습도 모드
        
        // 현재 상태와 입력에 따라 출력 결정
        case (current_state)
            STATE_0, STATE_1: begin
                // 스톱워치 모드
                sw2 = 1'b1;
            end
            
            STATE_2, STATE_3: begin
                // 시계 모드
                sw3 = 1'b1;
            end
            
            STATE_4, STATE_5: begin
                // 초음파 모드
                sw4 = 1'b1;
            end
            
            STATE_6, STATE_7: begin
                // 온습도 모드
                sw5 = 1'b1;
            end
        endcase
    end
    
    // 모드 신호 할당
    assign is_clock_mode = sw3;
    assign is_ultrasonic_mode = sw4;
    assign is_temp_humid_mode = sw5;
endmodule

// module fsm_controller(
//     input clk,
//     input reset,
//     input [1:0] sw,
//     input btn_run,
//     input sw_mode_in,
//     output reg [1:0] current_state,
//     output is_clock_mode,
//     output reg sw2,
//     output reg sw3
// );
//     // 상태 정의
//     parameter STATE_0 = 2'b00;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 2'b01;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 2'b10;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 2'b11;  // Clock Mode Hour:Min
    
//     // 다음 상태를 저장할 레지스터
//     reg [1:0] next_state;
    
//     // 다음 상태 논리 (조합 논리)
//     always @(*) begin
//         // 기본값은 현재 상태 유지
//         next_state = current_state;
        
//         case (current_state)
//             STATE_0: begin // Stopwatch Msec:Sec
//                 if (sw == 2'b01)           // sw[0]=1, sw[1]=0
//                     next_state = STATE_1;
//                 else if (sw == 2'b10)      // sw[0]=0, sw[1]=1
//                     next_state = STATE_2;
//             end
            
//             STATE_1: begin // Stopwatch Hour:Min
//                 if (sw == 2'b00)           // sw[0]=0, sw[1]=0
//                     next_state = STATE_0;
//                 else if (sw == 2'b11)      // sw[0]=1, sw[1]=1
//                     next_state = STATE_3;
//             end
            
//             STATE_2: begin // Clock Sec:Msec
//                 if (sw == 2'b00)           // sw[0]=0, sw[1]=0
//                     next_state = STATE_0;
//                 else if (sw == 2'b11)      // sw[0]=1, sw[1]=1
//                     next_state = STATE_3;
//             end
            
//             STATE_3: begin // Clock Hour:Min
//                 if (sw == 2'b01)           // sw[0]=1, sw[1]=0
//                     next_state = STATE_1;
//                 else if (sw == 2'b10)      // sw[0]=0, sw[1]=1
//                     next_state = STATE_2;
//             end
//         endcase
//     end
    
//     // 상태 등록 프로세스 (순차 논리)
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= STATE_0;
//         end else begin
//             current_state <= next_state;
//         end
//     end
    
//     // 출력 논리 (메일리 모델 - 현재 상태와 입력에 기반)
//     always @(*) begin
//         // 기본값 설정
//         sw2 = 1'b0;
//         sw3 = 1'b0;
        
//         // 현재 상태와 입력에 따라 출력 결정
//         case (current_state)
//             STATE_0, STATE_1: begin
//                 // 스톱워치 모드 (STATE_0, STATE_1)
//                 sw2 = 1'b1;
//                 sw3 = 1'b0;
//             end
            
//             STATE_2, STATE_3: begin
//                 // 시계 모드 (STATE_2, STATE_3)
//                 sw2 = 1'b0;
//                 sw3 = 1'b1;
//             end
//         endcase
//     end
    
//     // is_clock_mode 신호 할당
//     assign is_clock_mode = sw3;
// endmodule