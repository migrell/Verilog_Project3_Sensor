module fsm_controller (
    input clk,
    input reset,
    input [2:0] sw,
    input btn_run,
    input sw_mode_in,
    output reg [2:0] current_state,
    output reg is_clock_mode,
    output reg is_ultrasonic_mode,
    output reg is_temp_humid_mode,
    output reg sw2,
    output reg sw3,
    output reg sw4,
    output reg sw5
);
    // 디바운싱 및 상태 변수
    reg [2:0] prev_sw;
    reg [19:0] mode_change_counter;
    parameter MODE_CHANGE_DELAY = 20'd500000;  // 약 5ms (100MHz 기준)
    
    // 버튼 엣지 감지 변수
    reg btn_run_prev;
    wire btn_run_edge;
    
    // 상태 정의
    parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
    parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
    parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
    parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
    parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
    parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch
    parameter STATE_6 = 3'b110;  // Temperature Mode
    parameter STATE_7 = 3'b111;  // Humidity Mode
    
    // 버튼 엣지 감지
    assign btn_run_edge = btn_run & ~btn_run_prev;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            btn_run_prev <= 1'b0;
        end else begin
            btn_run_prev <= btn_run;
        end
    end
    
    // 모드 및 상태 제어 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            prev_sw <= 3'b000;
            mode_change_counter <= 20'd0;
            is_clock_mode <= 1'b1;       // 기본 모드는 시계 모드
            is_ultrasonic_mode <= 1'b0;
            is_temp_humid_mode <= 1'b0;
            current_state <= STATE_2;    // 시계 모드 초기 상태
            sw2 <= 1'b0;
            sw3 <= 1'b0;
            sw4 <= 1'b0;
            sw5 <= 1'b0;
        end else begin
            // 스위치 변경 감지 및 디바운싱
            if (sw != prev_sw) begin
                mode_change_counter <= 20'd0;  // 카운터 리셋
                prev_sw <= sw;  // 새 스위치 상태 저장
            end else if (mode_change_counter < MODE_CHANGE_DELAY) begin
                mode_change_counter <= mode_change_counter + 1;
            end else begin
                // 스위치 값이 안정화된 후의 모드 설정
                if (prev_sw[1]) begin  // 초음파 모드
                    is_clock_mode <= 1'b0;
                    is_ultrasonic_mode <= 1'b1;
                    is_temp_humid_mode <= 1'b0;
                    // 초음파 모드 진입 시 항상 CM 모드로 시작
                    if (!is_ultrasonic_mode)
                        current_state <= STATE_4;
                    
                    // 출력 스위치 상태 업데이트
                    sw2 <= 1'b1;
                    sw3 <= 1'b0;
                end else if (prev_sw[2]) begin  // 온습도 모드
                    is_clock_mode <= 1'b0;
                    is_ultrasonic_mode <= 1'b0;
                    is_temp_humid_mode <= 1'b1;
                    // 온습도 모드 진입 시 항상 온도 모드로 시작
                    if (!is_temp_humid_mode)
                        current_state <= STATE_6;
                    
                    // 출력 스위치 상태 업데이트
                    sw2 <= 1'b0;
                    sw3 <= 1'b1;
                end else begin  // 시계 모드
                    is_clock_mode <= 1'b1;
                    is_ultrasonic_mode <= 1'b0;
                    is_temp_humid_mode <= 1'b0;
                    // 시계 모드 진입 시 항상 초:밀리초 표시로 시작
                    if (!is_clock_mode)
                        current_state <= STATE_2;
                    
                    // 출력 스위치 상태 업데이트
                    sw2 <= 1'b0;
                    sw3 <= 1'b0;
                end
                
                // 버튼에 따른 상태 전환 로직
                if (btn_run_edge) begin
                    if (is_clock_mode) begin
                        // 시계 모드 내에서의 상태 전환
                        if (current_state == STATE_2)  // 초:밀리초
                            current_state <= STATE_3;  // 시:분
                        else
                            current_state <= STATE_2;  // 다시 초:밀리초로
                    end else if (is_ultrasonic_mode) begin
                        // 초음파 모드 내에서의 상태 전환
                        if (current_state == STATE_4)  // CM 모드
                            current_state <= STATE_5;  // Inch 모드
                        else
                            current_state <= STATE_4;  // 다시 CM 모드로
                    end else if (is_temp_humid_mode) begin
                        // 온습도 모드 내에서의 상태 전환
                        if (current_state == STATE_6)  // 온도 모드
                            current_state <= STATE_7;  // 습도 모드
                        else
                            current_state <= STATE_6;  // 다시 온도 모드로
                    end
                end
            end
            
            // 상태와 모드 플래그 간의 일관성 확인
            case (current_state)
                STATE_0, STATE_1: begin  // 스톱워치 모드
                    sw4 <= 1'b0;
                    sw5 <= 1'b0;
                end
                
                STATE_2, STATE_3: begin  // 시계 모드
                    if (!is_clock_mode) begin
                        // 상태에 맞게 모드 플래그 수정
                        is_clock_mode <= 1'b1;
                        is_ultrasonic_mode <= 1'b0;
                        is_temp_humid_mode <= 1'b0;
                    end
                    sw4 <= 1'b0;
                    sw5 <= 1'b1;
                end
                
                STATE_4, STATE_5: begin  // 초음파 모드
                    if (!is_ultrasonic_mode) begin
                        // 상태에 맞게 모드 플래그 수정
                        is_clock_mode <= 1'b0;
                        is_ultrasonic_mode <= 1'b1;
                        is_temp_humid_mode <= 1'b0;
                    end
                    sw4 <= 1'b1;
                    sw5 <= 1'b0;
                end
                
                STATE_6, STATE_7: begin  // 온습도 모드
                    if (!is_temp_humid_mode) begin
                        // 상태에 맞게 모드 플래그 수정
                        is_clock_mode <= 1'b0;
                        is_ultrasonic_mode <= 1'b0;
                        is_temp_humid_mode <= 1'b1;
                    end
                    sw4 <= 1'b1;
                    sw5 <= 1'b1;
                end
                
                default: begin  // 정의되지 않은 상태
                    current_state <= STATE_2;  // 기본 시계 모드로
                    is_clock_mode <= 1'b1;
                    is_ultrasonic_mode <= 1'b0;
                    is_temp_humid_mode <= 1'b0;
                    sw4 <= 1'b0;
                    sw5 <= 1'b0;
                end
            endcase
        end
    end
endmodule
// module fsm_controller(
//     input clk,
//     input reset,
//     input [2:0] sw,
//     input btn_run,
//     input sw_mode_in,
//     output reg [2:0] current_state,
//     output is_clock_mode,
//     output is_ultrasonic_mode,
//     output is_temp_humid_mode,
//     output reg sw2,
//     output reg sw3,
//     output reg sw4,
//     output reg sw5
// );
//     // 상태 정의 (3비트)
//     localparam STATE_0 = 3'b000;  // 스톱워치 Msec:Sec
//     localparam STATE_1 = 3'b001;  // 스톱워치 Hour:Min
//     localparam STATE_2 = 3'b010;  // 시계 Sec:Msec
//     localparam STATE_3 = 3'b011;  // 시계 Hour:Min
//     localparam STATE_4 = 3'b100;  // 초음파 CM
//     localparam STATE_5 = 3'b101;  // 초음파 Inch
//     localparam STATE_6 = 3'b110;  // 온도
//     localparam STATE_7 = 3'b111;  // 습도
    
//     reg [2:0] next_state;
    
//     // FSM 상태 전이 - 기존 전환 조건 유지하면서 추가된 상태 처리
//     always @(*) begin
//         next_state = current_state;
        
//         case (current_state)
//             STATE_0: begin
//                 if (sw == 3'b001) next_state = STATE_1;
//                 else if (sw == 3'b010) next_state = STATE_2;
//                 else if (sw == 3'b100) next_state = STATE_4;
//             end
//             STATE_1: begin
//                 if (sw == 3'b000) next_state = STATE_0;
//                 else if (sw == 3'b011) next_state = STATE_3;
//                 else if (sw == 3'b101) next_state = STATE_5;
//             end
//             STATE_2: begin
//                 if (sw == 3'b000) next_state = STATE_0;
//                 else if (sw == 3'b011) next_state = STATE_3;
//                 else if (sw == 3'b110) next_state = STATE_6;
//             end
//             STATE_3: begin
//                 if (sw == 3'b001) next_state = STATE_1;
//                 else if (sw == 3'b010) next_state = STATE_2;
//                 else if (sw == 3'b111) next_state = STATE_7;
//             end
//             STATE_4: begin
//                 if (sw == 3'b000) next_state = STATE_0;
//                 else if (sw == 3'b101) next_state = STATE_5;
//                 else if (sw == 3'b110) next_state = STATE_6;
//             end
//             STATE_5: begin
//                 if (sw == 3'b001) next_state = STATE_1;
//                 else if (sw == 3'b100) next_state = STATE_4;
//                 else if (sw == 3'b111) next_state = STATE_7;
//             end
//             STATE_6: begin
//                 if (sw == 3'b010) next_state = STATE_2;
//                 else if (sw == 3'b100) next_state = STATE_4;
//                 else if (sw == 3'b111) next_state = STATE_7;
//             end
//             STATE_7: begin
//                 if (sw == 3'b011) next_state = STATE_3;
//                 else if (sw == 3'b101) next_state = STATE_5;
//                 else if (sw == 3'b110) next_state = STATE_6;
//             end
//         endcase
//     end
    
//     // FSM 상태 저장 - 단순화된 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset)
//             current_state <= STATE_0;
//         else 
//             current_state <= next_state;
//     end
    
//     // 모드 신호 설정
//     always @(*) begin
//         sw2 = 0;  // 스톱워치
//         sw3 = 0;  // 시계
//         sw4 = 0;  // 초음파
//         sw5 = 0;  // 온습도
        
//         case (current_state)
//             STATE_0, STATE_1: sw2 = 1;
//             STATE_2, STATE_3: sw3 = 1;
//             STATE_4, STATE_5: sw4 = 1;
//             STATE_6, STATE_7: sw5 = 1;
//         endcase
//     end
    
//     assign is_clock_mode = sw3;
//     assign is_ultrasonic_mode = sw4;
//     assign is_temp_humid_mode = sw5;
// endmodule

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