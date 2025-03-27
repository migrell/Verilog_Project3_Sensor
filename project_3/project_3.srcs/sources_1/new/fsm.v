module fsm_controller(
    input clk,
    input reset,
    input [1:0] sw,
    input btn_run,
    input sw_mode_in,
    output reg [1:0] current_state,
    output is_clock_mode,
    output reg sw2,
    output reg sw3
);
    // 상태 정의
    parameter STATE_0 = 2'b00;  // Stopwatch Mode Msec:Sec
    parameter STATE_1 = 2'b01;  // Stopwatch Mode Hour:Min
    parameter STATE_2 = 2'b10;  // Clock Mode Sec:Msec
    parameter STATE_3 = 2'b11;  // Clock Mode Hour:Min
    
    // 다음 상태를 저장할 레지스터
    reg [1:0] next_state;
    
    // 다음 상태 논리 (조합 논리)
    always @(*) begin
        // 기본값은 현재 상태 유지
        next_state = current_state;
        
        case (current_state)
            STATE_0: begin // Stopwatch Msec:Sec
                if (sw == 2'b01)           // sw[0]=1, sw[1]=0
                    next_state = STATE_1;
                else if (sw == 2'b10)      // sw[0]=0, sw[1]=1
                    next_state = STATE_2;
            end
            
            STATE_1: begin // Stopwatch Hour:Min
                if (sw == 2'b00)           // sw[0]=0, sw[1]=0
                    next_state = STATE_0;
                else if (sw == 2'b11)      // sw[0]=1, sw[1]=1
                    next_state = STATE_3;
            end
            
            STATE_2: begin // Clock Sec:Msec
                if (sw == 2'b00)           // sw[0]=0, sw[1]=0
                    next_state = STATE_0;
                else if (sw == 2'b11)      // sw[0]=1, sw[1]=1
                    next_state = STATE_3;
            end
            
            STATE_3: begin // Clock Hour:Min
                if (sw == 2'b01)           // sw[0]=1, sw[1]=0
                    next_state = STATE_1;
                else if (sw == 2'b10)      // sw[0]=0, sw[1]=1
                    next_state = STATE_2;
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
        sw2 = 1'b0;
        sw3 = 1'b0;
        
        // 현재 상태와 입력에 따라 출력 결정
        case (current_state)
            STATE_0, STATE_1: begin
                // 스톱워치 모드 (STATE_0, STATE_1)
                sw2 = 1'b1;
                sw3 = 1'b0;
            end
            
            STATE_2, STATE_3: begin
                // 시계 모드 (STATE_2, STATE_3)
                sw2 = 1'b0;
                sw3 = 1'b1;
            end
        endcase
    end
    
    // is_clock_mode 신호 할당
    assign is_clock_mode = sw3;
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