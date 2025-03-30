module dist_calculator(
    input clk,                    // 시스템 클럭 (100MHz)
    input reset,                  // 리셋 신호
    input echo,                   // 초음파 센서 에코 핀
    input btn_run,                // 시작 버튼 입력 (btn_start에서 변경)
    output reg trigger,           // 초음파 센서 트리거 핀
    output [6:0] msec,            // 측정된 거리 값 (0-99cm)
    output reg [3:0] led_indicator,  // LED 상태 표시
    output reg dist_start,        // 측정 시작 플래그 (start에서 변경)
    output reg done               // 측정 완료 플래그
);

    // 상태 정의
    localparam IDLE = 2'd0;
    localparam TRIGGER = 2'd1;
    localparam WAIT_ECHO = 2'd2;
    localparam COUNT_ECHO = 2'd3;

    // 내부 레지스터
    reg [1:0] current_state;
    reg [1:0] next_state;
    reg [31:0] counter;           // 범용 카운터
    reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
    reg [31:0] distance_cm;       // 계산된 거리 (cm)
    reg echo_prev;                // 이전 에코 신호 상태
    reg btn_prev;                 // 이전 버튼 상태
    
    // 에코 신호 엣지 감지
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;
    
    // 버튼 엣지 감지
    wire btn_posedge = btn_run && !btn_prev;

    // 마지막 측정된 유효한 거리 값 저장
    reg [6:0] last_valid_distance;
    
    // msec 출력 할당 - 유효한 측정값만 출력
    assign msec = (distance_cm > 0) ? 
                  ((distance_cm > 99) ? 99 : distance_cm[6:0]) : 
                  last_valid_distance;  // 유효한 측정이 없으면 마지막 값 유지

    // 유효한 거리 저장 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            last_valid_distance <= 7'd15;  // 기본값 15cm로 시작
        end else if (distance_cm > 0 && distance_cm <= 99) begin
            // 유효한 측정이 있으면 값 업데이트
            last_valid_distance <= distance_cm[6:0];
        end
    end

    // 상태 머신 - 상태 전이
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            echo_prev <= 0;
            btn_prev <= 0;
        end else begin
            current_state <= next_state;
            echo_prev <= echo;
            btn_prev <= btn_run;
        end
    end

    // 상태 머신 - 다음 상태 결정
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (btn_posedge)  // 버튼 에지 감지로만 시작 (눌렀다 떼었을 때)
                    next_state = TRIGGER;
                else
                    next_state = IDLE;
            end
            
            TRIGGER: begin
                if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
                    next_state = WAIT_ECHO;
                end else begin
                    next_state = TRIGGER;
                end
            end
            
            WAIT_ECHO: begin
                if (echo_posedge)  // 에코 신호가 시작되면
                    next_state = COUNT_ECHO;
                else if (counter >= 30000000)  // 300ms 타임아웃
                    next_state = IDLE;  // 타임아웃 시 IDLE로 돌아감
                else
                    next_state = WAIT_ECHO;
            end
            
            COUNT_ECHO: begin
                if (echo_negedge)  // 에코 신호가 끝나면
                    next_state = IDLE;
                else
                    next_state = COUNT_ECHO;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // 상태 머신 - 동작 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
            echo_counter <= 0;
            distance_cm <= 0;
            trigger <= 0;
            led_indicator <= 4'b0000;
            dist_start <= 0;
            done <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    counter <= 0;
                    echo_counter <= 0;
                    trigger <= 0;
                    led_indicator <= 4'b0001;
                    dist_start <= 0;
                    // IDLE 상태에서는 done 신호가 유지됨
                end
                
                TRIGGER: begin
                    counter <= counter + 1;
                    trigger <= 1;  // 트리거 신호 생성 (10us)
                    led_indicator <= 4'b0010;
                    dist_start <= 1;
                    done <= 0;  // 새 측정 시작할 때 done 리셋
                    
                    if (counter >= 1000) begin
                        trigger <= 0;  // 트리거 신호 종료
                    end
                end
                
                WAIT_ECHO: begin
                    counter <= counter + 1;  // 타임아웃 카운터
                    trigger <= 0;
                    led_indicator <= 4'b0100;
                    dist_start <= 0;
                    
                    // 타임아웃 시 거리 값을 0으로 설정 (마지막 유효 측정값 유지)
                    if (counter >= 30000000) begin
                        distance_cm <= 0;  // 거리 값 초기화
                        done <= 1;  // 타임아웃 시에도 done 신호 생성
                    end
                end
                
                COUNT_ECHO: begin
                    echo_counter <= echo_counter + 1;  // 에코 시간 측정
                    led_indicator <= 4'b1000;
                    
                    if (echo_negedge) begin
                        done <= 1;  // 측정 완료
                        
                        if (echo_counter > 100 && echo_counter < 30000000) begin  // 유효한 측정 범위 내일 때만
                            // 거리 계산: Distance(cm) = echo_time(us) / 58
                            // 100MHz에서 1us = 100 clock cycles
                            // 따라서 Distance(cm) = (echo_counter * 10) / 5800 
                            distance_cm <= (echo_counter * 10) / 5800;
                            
                            // 최소값 제한 (너무 작은 값 방지)
                            if ((echo_counter * 10) / 5800 == 0)
                                distance_cm <= 7'd1;  // 최소 1cm
                        end else begin
                            // 너무 짧거나 긴 에코 시간이면 0으로 설정
                            distance_cm <= 0;
                        end
                    end
                end
                
                default: begin
                    counter <= 0;
                    trigger <= 0;
                    led_indicator <= 4'b0000;
                end
            endcase
        end
    end

endmodule
// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 3'd0;
//     localparam TRIGGER = 3'd1;
//     localparam WAIT_ECHO = 3'd2;
//     localparam COUNT_ECHO = 3'd3;
//     localparam COMPLETE = 3'd4;   // 새로운 상태 추가: 측정 완료

//     // 내부 레지스터
//     reg [2:0] current_state;      // 상태 비트 확장 (5개 상태 필요)
//     reg [2:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태
//     reg [31:0] done_counter;      // done 신호 유지 카운터
//     reg btn_start_prev;           // 이전 버튼 상태 (엣지 감지용)
//     reg measurement_valid;        // 유효한 측정이 완료되었는지 표시
    
//     // 측정된 거리 값을 저장하는 레지스터
//     reg [6:0] distance_output;    // 출력용 거리 값 (0-99cm)

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;
    
//     // 버튼 엣지 감지
//     wire btn_start_posedge = btn_start && !btn_start_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = distance_output;

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//             btn_start_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//             btn_start_prev <= btn_start;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start_posedge)  // 버튼 상승 엣지로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end
            
//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end
            
//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else if (counter >= 100000000)  // 1초 타임아웃 (100,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 에코가 없어도 완료 상태로 전환
//                 else
//                     next_state = WAIT_ECHO;
//             end
            
//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = COMPLETE;
//                 else if (echo_counter >= 30000000)  // 300ms 제한 (30,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 최대 측정 시간 초과
//                 else
//                     next_state = COUNT_ECHO;
//             end
            
//             COMPLETE: begin
//                 if (done_counter >= 10000000)  // done 신호 100ms 유지 (10,000,000 클럭 @ 100MHz)
//                     next_state = IDLE;
//                 else
//                     next_state = COMPLETE;
//             end
            
//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             distance_output <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//             done_counter <= 0;
//             measurement_valid <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                     done_counter <= 0;
//                     // IDLE 상태에서는 이전 유효한 측정값 유지
//                 end
                
//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
//                     measurement_valid <= 0;
                    
//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end
                
//                 WAIT_ECHO: begin
//                     counter <= counter + 1;  // 타임아웃 감지를 위한 카운터
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end
                
//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
//                 end
                
//                 COMPLETE: begin
//                     done_counter <= done_counter + 1;
//                     done <= 1;  // 완료 신호 활성화
//                     led_indicator <= 4'b1111;
                    
//                     if (done_counter == 0) begin  // 첫 사이클에서만 거리 계산
//                         if (echo_counter > 0 && echo_counter < 30000000) begin  // 유효한 측정
//                             // 거리 계산 개선: 정확도를 높이기 위해 고정소수점 연산 사용
//                             // 거리(cm) = 에코 시간(us) / 58 = 에코 카운트 / (58 * 100)
//                             // 먼저 100을 곱하고 5800으로 나눠 소수점 정확도 향상
//                             distance_cm <= (echo_counter * 100) / 5800;
//                             measurement_valid <= 1;
//                         end
//                     end
                    
//                     // 결과 할당 - 유효한 측정이 있을 때만 업데이트
//                     if (measurement_valid) begin
//                         if (distance_cm > 9900) begin  // 99cm 이상이면 99cm로 표시
//                             distance_output <= 99;
//                         end else begin
//                             distance_output <= (distance_cm / 100);  // cm 단위로 변환 (소수점 제거)
//                         end
//                     end
//                 end
                
//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule




// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = (distance_cm > 99) ? 99 : distance_cm[6:0];

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start)  // 버튼 입력으로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end
            
//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end
            
//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else
//                     next_state = WAIT_ECHO;
//             end
            
//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = IDLE;
//                 else
//                     next_state = COUNT_ECHO;
//             end
            
//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                 end
                
//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
                    
//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end
                
//                 WAIT_ECHO: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end
                
//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
                    
//                     if (echo_negedge) begin
//                         done <= 1;
//                         // 거리 계산: 거리(cm) = 에코 시간(us) / 58
//                         // 100MHz 클럭에서 1us = 100 클럭 카운트
//                         // 따라서 거리(cm) = 카운트 / 5800
//                         distance_cm <= echo_counter / 58;  // 스케일링 필요
//                     end
//                 end
                
//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule
// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 3'd0;
//     localparam TRIGGER = 3'd1;
//     localparam WAIT_ECHO = 3'd2;
//     localparam COUNT_ECHO = 3'd3;
//     localparam COMPLETE = 3'd4;   // 새로운 상태 추가: 측정 완료

//     // 내부 레지스터
//     reg [2:0] current_state;      // 상태 비트 확장 (5개 상태 필요)
//     reg [2:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태
//     reg [31:0] done_counter;      // done 신호 유지 카운터
//     reg btn_start_prev;           // 이전 버튼 상태 (엣지 감지용)
//     reg measurement_valid;        // 유효한 측정이 완료되었는지 표시
    
//     // 측정된 거리 값을 저장하는 레지스터
//     reg [6:0] distance_output;    // 출력용 거리 값 (0-99cm)

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;
    
//     // 버튼 엣지 감지
//     wire btn_start_posedge = btn_start && !btn_start_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = distance_output;

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//             btn_start_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//             btn_start_prev <= btn_start;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start_posedge)  // 버튼 상승 엣지로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end
            
//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end
            
//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else if (counter >= 100000000)  // 1초 타임아웃 (100,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 에코가 없어도 완료 상태로 전환
//                 else
//                     next_state = WAIT_ECHO;
//             end
            
//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = COMPLETE;
//                 else if (echo_counter >= 30000000)  // 300ms 제한 (30,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 최대 측정 시간 초과
//                 else
//                     next_state = COUNT_ECHO;
//             end
            
//             COMPLETE: begin
//                 if (done_counter >= 10000000)  // done 신호 100ms 유지 (10,000,000 클럭 @ 100MHz)
//                     next_state = IDLE;
//                 else
//                     next_state = COMPLETE;
//             end
            
//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             distance_output <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//             done_counter <= 0;
//             measurement_valid <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                     done_counter <= 0;
//                     // IDLE 상태에서는 이전 유효한 측정값 유지
//                 end
                
//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
//                     measurement_valid <= 0;
                    
//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end
                
//                 WAIT_ECHO: begin
//                     counter <= counter + 1;  // 타임아웃 감지를 위한 카운터
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end
                
//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
//                 end
                
//                 COMPLETE: begin
//                     done_counter <= done_counter + 1;
//                     done <= 1;  // 완료 신호 활성화
//                     led_indicator <= 4'b1111;
                    
//                     if (done_counter == 0) begin  // 첫 사이클에서만 거리 계산
//                         if (echo_counter > 0 && echo_counter < 30000000) begin  // 유효한 측정
//                             // 거리 계산 개선: 정확도를 높이기 위해 고정소수점 연산 사용
//                             // 거리(cm) = 에코 시간(us) / 58 = 에코 카운트 / (58 * 100)
//                             // 먼저 100을 곱하고 5800으로 나눠 소수점 정확도 향상
//                             distance_cm <= (echo_counter * 100) / 5800;
//                             measurement_valid <= 1;
//                         end
//                     end
                    
//                     // 결과 할당 - 유효한 측정이 있을 때만 업데이트
//                     if (measurement_valid) begin
//                         if (distance_cm > 9900) begin  // 99cm 이상이면 99cm로 표시
//                             distance_output <= 99;
//                         end else begin
//                             distance_output <= (distance_cm / 100);  // cm 단위로 변환 (소수점 제거)
//                         end
//                     end
//                 end
                
//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule




// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = (distance_cm > 99) ? 99 : distance_cm[6:0];

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start)  // 버튼 입력으로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end
            
//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end
            
//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else
//                     next_state = WAIT_ECHO;
//             end
            
//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = IDLE;
//                 else
//                     next_state = COUNT_ECHO;
//             end
            
//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                 end
                
//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
                    
//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end
                
//                 WAIT_ECHO: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end
                
//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
                    
//                     if (echo_negedge) begin
//                         done <= 1;
//                         // 거리 계산: 거리(cm) = 에코 시간(us) / 58
//                         // 100MHz 클럭에서 1us = 100 클럭 카운트
//                         // 따라서 거리(cm) = 카운트 / 5800
//                         distance_cm <= echo_counter / 58;  // 스케일링 필요
//                     end
//                 end
                
//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule
// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 3'd0;
//     localparam TRIGGER = 3'd1;
//     localparam WAIT_ECHO = 3'd2;
//     localparam COUNT_ECHO = 3'd3;
//     localparam COMPLETE = 3'd4;   // 새로운 상태 추가: 측정 완료

//     // 내부 레지스터
//     reg [2:0] current_state;      // 상태 비트 확장 (5개 상태 필요)
//     reg [2:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태
//     reg [31:0] done_counter;      // done 신호 유지 카운터
//     reg btn_start_prev;           // 이전 버튼 상태 (엣지 감지용)
//     reg measurement_valid;        // 유효한 측정이 완료되었는지 표시
    
//     // 측정된 거리 값을 저장하는 레지스터
//     reg [6:0] distance_output;    // 출력용 거리 값 (0-99cm)

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;
    
//     // 버튼 엣지 감지
//     wire btn_start_posedge = btn_start && !btn_start_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = distance_output;

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//             btn_start_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//             btn_start_prev <= btn_start;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start_posedge)  // 버튼 상승 엣지로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end
            
//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end
            
//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else if (counter >= 100000000)  // 1초 타임아웃 (100,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 에코가 없어도 완료 상태로 전환
//                 else
//                     next_state = WAIT_ECHO;
//             end
            
//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = COMPLETE;
//                 else if (echo_counter >= 30000000)  // 300ms 제한 (30,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 최대 측정 시간 초과
//                 else
//                     next_state = COUNT_ECHO;
//             end
            
//             COMPLETE: begin
//                 if (done_counter >= 10000000)  // done 신호 100ms 유지 (10,000,000 클럭 @ 100MHz)
//                     next_state = IDLE;
//                 else
//                     next_state = COMPLETE;
//             end
            
//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             distance_output <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//             done_counter <= 0;
//             measurement_valid <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                     done_counter <= 0;
//                     // IDLE 상태에서는 이전 유효한 측정값 유지
//                 end
                
//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
//                     measurement_valid <= 0;
                    
//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end
                
//                 WAIT_ECHO: begin
//                     counter <= counter + 1;  // 타임아웃 감지를 위한 카운터
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end
                
//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
//                 end
                
//                 COMPLETE: begin
//                     done_counter <= done_counter + 1;
//                     done <= 1;  // 완료 신호 활성화
//                     led_indicator <= 4'b1111;
                    
//                     if (done_counter == 0) begin  // 첫 사이클에서만 거리 계산
//                         if (echo_counter > 0 && echo_counter < 30000000) begin  // 유효한 측정
//                             // 거리 계산 개선: 정확도를 높이기 위해 고정소수점 연산 사용
//                             // 거리(cm) = 에코 시간(us) / 58 = 에코 카운트 / (58 * 100)
//                             // 먼저 100을 곱하고 5800으로 나눠 소수점 정확도 향상
//                             distance_cm <= (echo_counter * 100) / 5800;
//                             measurement_valid <= 1;
//                         end
//                     end
                    
//                     // 결과 할당 - 유효한 측정이 있을 때만 업데이트
//                     if (measurement_valid) begin
//                         if (distance_cm > 9900) begin  // 99cm 이상이면 99cm로 표시
//                             distance_output <= 99;
//                         end else begin
//                             distance_output <= (distance_cm / 100);  // cm 단위로 변환 (소수점 제거)
//                         end
//                     end
//                 end
                
//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule




// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = (distance_cm > 99) ? 99 : distance_cm[6:0];

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start)  // 버튼 입력으로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end
            
//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end
            
//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else
//                     next_state = WAIT_ECHO;
//             end
            
//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = IDLE;
//                 else
//                     next_state = COUNT_ECHO;
//             end
            
//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                 end
                
//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
                    
//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end
                
//                 WAIT_ECHO: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end
                
//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
                    
//                     if (echo_negedge) begin
//                         done <= 1;
//                         // 거리 계산: 거리(cm) = 에코 시간(us) / 58
//                         // 100MHz 클럭에서 1us = 100 클럭 카운트
//                         // 따라서 거리(cm) = 카운트 / 5800
//                         distance_cm <= echo_counter / 58;  // 스케일링 필요
//                     end
//                 end
                
//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule

// module dist_calculator (
//     input            clk,            // 시스템 클럭 (100MHz)
//     input            reset,          // 리셋 신호
//     input            echo,           // 초음파 센서 에코 핀
//     input            btn_start,      // 시작 버튼 입력
//     output reg       trigger,        // 초음파 센서 트리거 핀
//     output     [6:0] msec,           // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg       start,          // 측정 시작 플래그
//     output reg       done            // 측정 완료 플래그
// );

//     // 상태 정의
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;  // 범용 카운터
//     reg [31:0] echo_counter;  // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;  // 계산된 거리 (cm)
//     reg echo_prev;  // 이전 에코 신호 상태

//     // 테스트 모드 변수 - 실제 측정값 대신 강제 값 생성
//     reg [6:0] test_value;  // 테스트용 값
//     reg [27:0] test_counter;  // 테스트용 카운터
//     reg use_test_value;  // 테스트 값 사용 플래그

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // 테스트 모드 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             test_value <= 7'd25;  // 초기 테스트값 25cm
//             test_counter <= 0;
//             use_test_value <= 1'b1;  // 기본적으로 테스트 값 사용
//         end else begin
//             // 테스트 값 자동 변경
//             test_counter <= test_counter + 1;
//             if (test_counter >= 28'd100000000) begin  // 1초마다
//                 test_counter <= 0;
//                 test_value   <= test_value + 7'd5;  // 5cm씩 증가
//                 if (test_value >= 7'd90) begin
//                     test_value <= 7'd25;  // 25cm로 리셋
//                 end
//             end

//             // 실제 에코 신호가 감지되면 테스트 값 사용 해제
//             if (echo_posedge) begin
//                 use_test_value <= 1'b0;  // 실제 값 사용
//             end

//             // 10번 연속 에코 놓치면 다시 테스트 값 사용
//             if (current_state == WAIT_ECHO && counter >= 30000000) begin
//                 use_test_value <= 1'b1;  // 다시 테스트 값 사용
//             end
//         end
//     end

//     // msec 출력 할당 - 테스트 모드 또는 실제 측정값 선택
//     assign msec = use_test_value ? test_value : 
//                  (distance_cm > 99) ? 99 : distance_cm[6:0];

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start)  // 버튼 입력으로 시작
//                     next_state = TRIGGER;
//                 else next_state = IDLE;
//             end

//             TRIGGER: begin
//                 if (counter >= 5000) begin  // 50us (5000 클럭 @ 100MHz) - 더 긴 트리거
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end

//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else if (counter >= 30000000)  // 300ms 타임아웃
//                     next_state = IDLE;
//                 else next_state = WAIT_ECHO;
//             end

//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = IDLE;
//                 else if (echo_counter >= 30000000)  // 300ms 최대 측정 시간
//                     next_state = IDLE;
//                 else next_state = COUNT_ECHO;
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 15;  // 초기값 15cm
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;  // IDLE 상태 LED 표시
//                     start <= 0;

//                     // 다음 상태가 TRIGGER면 done 신호 리셋
//                     if (next_state == TRIGGER) begin
//                         done <= 0;
//                     end
//                 end

//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (50us로 확장)
//                     led_indicator <= 4'b0010;  // TRIGGER 상태 LED 표시
//                     start <= 1;
//                 end

//                 WAIT_ECHO: begin
//                     counter <= counter + 1;  // 타임아웃 감지용 카운터
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;  // WAIT_ECHO 상태 LED 표시
//                     start <= 0;

//                     // 타임아웃 시 테스트 값 사용
//                     if (counter >= 30000000 - 1) begin
//                         done <= 1;  // 측정 완료 신호
//                     end
//                 end

//                 COUNT_ECHO: begin
//                     echo_counter  <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;  // COUNT_ECHO 상태 LED 표시

//                     if (echo_negedge) begin
//                         done <= 1;  // 측정 완료 신호 활성화

//                         // 거리 계산: 거리(cm) = 에코 시간(us) / 58
//                         // 100MHz 클럭에서 1us = 100 클럭 카운트
//                         // 따라서 거리(cm) = echo_counter / 5800
//                         distance_cm <= echo_counter / 5800;

//                         // 최소값 보정 (0으로 계산되면 1cm로 설정)
//                         if ((echo_counter / 5800) == 0) distance_cm <= 1;
//                     end
//                 end

//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule
// // module dist_calculator(
// //     input clk,                    // 시스템 클럭 (100MHz)
// //     input reset,                  // 리셋 신호
// //     input echo,                   // 초음파 센서 에코 핀
// //     input btn_start,              // 시작 버튼 입력
// //     output reg trigger,           // 초음파 센서 트리거 핀
// //     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
// //     output reg [3:0] led_indicator,  // LED 상태 표시
// //     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [6:0] distance_cm;        // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태

//     // 자체 타이머 추가 - 외부 입력이 없어도 주기적으로 측정 시작
//     reg [27:0] auto_timer;
//     reg auto_trigger;
//     parameter AUTO_PERIOD = 28'd10000000; // 0.1초마다 자동 측정 (100MHz 기준)

//     // 에코 신호 동기화
//     reg [2:0] echo_sync;

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo_sync[2] & ~echo_prev;
//     wire echo_negedge = ~echo_sync[2] & echo_prev;

//     // 시뮬레이션용 카운터 초음파 값 생성 (실제 센서가 동작하지 않는 경우)
//     reg [26:0] sim_counter;
//     reg [6:0] simulated_value;
//     reg value_valid;

//     // msec 출력 할당
//     assign msec = value_valid ? distance_cm : 7'd15;

//     // 에코 신호 동기화
//     always @(posedge clk) begin
//         echo_sync <= {echo_sync[1:0], echo};
//     end

//     // 자체 타이머 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             auto_timer <= 0;
//             auto_trigger <= 0;
//             sim_counter <= 0;
//             simulated_value <= 7'd20;
//         end else begin
//             // 자동 타이머 증가
//             if (auto_timer >= AUTO_PERIOD) begin
//                 auto_timer <= 0;
//                 auto_trigger <= 1;
//             end else begin
//                 auto_timer <= auto_timer + 1;

//                 // 트리거는 한 클럭만 유지
//                 if (auto_trigger)
//                     auto_trigger <= 0;
//             end

//             // 시뮬레이션 값 생성 로직
//             sim_counter <= sim_counter + 1;
//             if (sim_counter >= 27'd100000000) begin  // 1초마다
//                 sim_counter <= 0;
//                 simulated_value <= simulated_value + 7'd5;
//                 if (simulated_value >= 7'd90)
//                     simulated_value <= 7'd20;
//             end
//         end
//     end

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//             value_valid <= 0;
//             distance_cm <= 7'd15;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo_sync[2];
//         end
//     end

//     // 상태 머신 - 다음 상태 결정
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start || auto_trigger)  // 버튼 입력 또는 자동 타이머로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end

//             TRIGGER: begin
//                 if (counter >= 5000) begin  // 50us (5000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end

//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else if (counter >= 10000000)  // 100ms 타임아웃
//                     next_state = IDLE;
//                 else
//                     next_state = WAIT_ECHO;
//             end

//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = IDLE;
//                 else if (echo_counter >= 10000000)  // 100ms 최대 측정 시간
//                     next_state = IDLE;
//                 else
//                     next_state = COUNT_ECHO;
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;  // IDLE 상태 LED 표시
//                     start <= 0;

//                     // IDLE 상태에서 타임아웃이 반복되면 시뮬레이션 값 사용
//                     if (next_state == TRIGGER) begin
//                         done <= 0; // 새 측정 시작 시 done 신호 리셋
//                     end
//                 end

//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (50us로 확장)
//                     led_indicator <= 4'b0010;  // TRIGGER 상태 LED 표시
//                     start <= 1;
//                 end

//                 WAIT_ECHO: begin
//                     counter <= counter + 1;
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;  // WAIT_ECHO 상태 LED 표시
//                     start <= 0;

//                     // 타임아웃 시 시뮬레이션 값 사용
//                     if (counter >= 10000000 - 1) begin
//                         distance_cm <= simulated_value;  // 시뮬레이션 값 사용
//                         value_valid <= 1;
//                         done <= 1;  // 측정 완료 신호
//                     end
//                 end

//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;
//                     led_indicator <= 4'b1000;  // COUNT_ECHO 상태 LED 표시

//                     if (echo_negedge) begin
//                         done <= 1;  // 측정 완료 신호 활성화

//                         // 실제 거리 계산 (에코 신호가 정상이면)
//                         if (echo_counter > 500 && echo_counter < 30000000) begin // 유효 범위 검사
//                             distance_cm <= echo_counter / 5800;  // 거리 계산
//                             value_valid <= 1;

//                             // 최소값 보정
//                             if ((echo_counter / 5800) == 0) 
//                                 distance_cm <= 7'd1;
//                         end else begin
//                             // 에코 신호가 비정상적이면 시뮬레이션 값 사용
//                             distance_cm <= simulated_value;
//                             value_valid <= 1;
//                         end
//                     end
//                 end

//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule
// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 3'd0;
//     localparam TRIGGER = 3'd1;
//     localparam WAIT_ECHO = 3'd2;
//     localparam COUNT_ECHO = 3'd3;
//     localparam COMPLETE = 3'd4;   // 새로운 상태 추가: 측정 완료

//     // 내부 레지스터
//     reg [2:0] current_state;      // 상태 비트 확장 (5개 상태 필요)
//     reg [2:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태
//     reg [31:0] done_counter;      // done 신호 유지 카운터
//     reg btn_start_prev;           // 이전 버튼 상태 (엣지 감지용)
//     reg measurement_valid;        // 유효한 측정이 완료되었는지 표시

//     // 측정된 거리 값을 저장하는 레지스터
//     reg [6:0] distance_output;    // 출력용 거리 값 (0-99cm)

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // 버튼 엣지 감지
//     wire btn_start_posedge = btn_start && !btn_start_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = distance_output;

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//             btn_start_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//             btn_start_prev <= btn_start;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start)  // 버튼 입력으로 시작 (엣지 감지 사용하지 않음)
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end

//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end

//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else if (counter >= 100000000)  // 1초 타임아웃 (100,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 에코가 없어도 완료 상태로 전환
//                 else
//                     next_state = WAIT_ECHO;
//             end

//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = COMPLETE;
//                 else if (echo_counter >= 30000000)  // 300ms 제한 (30,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 최대 측정 시간 초과
//                 else
//                     next_state = COUNT_ECHO;
//             end

//             COMPLETE: begin
//                 if (done_counter >= 10000000)  // done 신호 100ms 유지 (10,000,000 클럭 @ 100MHz)
//                     next_state = IDLE;
//                 else
//                     next_state = COMPLETE;
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             distance_output <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//             done_counter <= 0;
//             measurement_valid <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                     done_counter <= 0;
//                     // IDLE 상태에서는 이전 유효한 측정값 유지
//                 end

//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
//                     measurement_valid <= 0;

//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end

//                 WAIT_ECHO: begin
//                     counter <= counter + 1;  // 타임아웃 감지를 위한 카운터
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end

//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
//                 end

//                 COMPLETE: begin
//                     done_counter <= done_counter + 1;
//                     done <= 1;  // 완료 신호 활성화
//                     led_indicator <= 4'b1111;

//                     if (done_counter == 0) begin  // 첫 사이클에서만 거리 계산
//                         if (echo_counter > 0 && echo_counter < 30000000) begin  // 유효한 측정
//                             // 거리 계산 개선: 정확도를 높이기 위해 고정소수점 연산 사용
//                             // 거리(cm) = 에코 시간(us) / 58 = 에코 카운트 / (58 * 100)
//                             // 먼저 100을 곱하고 5800으로 나눠 소수점 정확도 향상
//                             distance_cm <= (echo_counter * 100) / 5800;
//                             measurement_valid <= 1;
//                         end
//                     end

//                     // 결과 할당 - 유효한 측정이 있을 때만 업데이트
//                     if (measurement_valid) begin
//                         if (distance_cm > 9900) begin  // 99cm 이상이면 99cm로 표시
//                             distance_output <= 99;
//                         end else begin
//                             distance_output <= (distance_cm / 100);  // cm 단위로 변환 (소수점 제거)
//                         end
//                     end
//                 end

//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule

// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = (distance_cm > 99) ? 99 : distance_cm[6:0];

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start)  // 버튼 입력으로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end

//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end

//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else
//                     next_state = WAIT_ECHO;
//             end

//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = IDLE;
//                 else
//                     next_state = COUNT_ECHO;
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                 end

//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;

//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end

//                 WAIT_ECHO: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end

//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;

//                     if (echo_negedge) begin
//                         done <= 1;
//                         // 거리 계산: 거리(cm) = 에코 시간(us) / 58
//                         // 100MHz 클럭에서 1us = 100 클럭 카운트
//                         // 따라서 거리(cm) = 카운트 / 5800
//                         distance_cm <= echo_counter / 5800;  // 올바른 스케일링
//                     end
//                 end

//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule

// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 3'd0;
//     localparam TRIGGER = 3'd1;
//     localparam WAIT_ECHO = 3'd2;
//     localparam COUNT_ECHO = 3'd3;
//     localparam COMPLETE = 3'd4;   // 새로운 상태 추가: 측정 완료

//     // 내부 레지스터
//     reg [2:0] current_state;      // 상태 비트 확장 (5개 상태 필요)
//     reg [2:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태
//     reg [31:0] done_counter;      // done 신호 유지 카운터
//     reg btn_start_prev;           // 이전 버튼 상태 (엣지 감지용)
//     reg measurement_valid;        // 유효한 측정이 완료되었는지 표시

//     // 측정된 거리 값을 저장하는 레지스터
//     reg [6:0] distance_output;    // 출력용 거리 값 (0-99cm)

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // 버튼 엣지 감지
//     wire btn_start_posedge = btn_start && !btn_start_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = distance_output;

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//             btn_start_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//             btn_start_prev <= btn_start;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start_posedge)  // 버튼 상승 엣지로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end

//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end

//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else if (counter >= 100000000)  // 1초 타임아웃 (100,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 에코가 없어도 완료 상태로 전환
//                 else
//                     next_state = WAIT_ECHO;
//             end

//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = COMPLETE;
//                 else if (echo_counter >= 30000000)  // 300ms 제한 (30,000,000 클럭 @ 100MHz)
//                     next_state = COMPLETE;  // 최대 측정 시간 초과
//                 else
//                     next_state = COUNT_ECHO;
//             end

//             COMPLETE: begin
//                 if (done_counter >= 10000000)  // done 신호 100ms 유지 (10,000,000 클럭 @ 100MHz)
//                     next_state = IDLE;
//                 else
//                     next_state = COMPLETE;
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             distance_output <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//             done_counter <= 0;
//             measurement_valid <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                     done_counter <= 0;
//                     // IDLE 상태에서는 이전 유효한 측정값 유지
//                 end

//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;
//                     measurement_valid <= 0;

//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end

//                 WAIT_ECHO: begin
//                     counter <= counter + 1;  // 타임아웃 감지를 위한 카운터
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end

//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;
//                 end

//                 COMPLETE: begin
//                     done_counter <= done_counter + 1;
//                     done <= 1;  // 완료 신호 활성화
//                     led_indicator <= 4'b1111;

//                     if (done_counter == 0) begin  // 첫 사이클에서만 거리 계산
//                         if (echo_counter > 0 && echo_counter < 30000000) begin  // 유효한 측정
//                             // 거리 계산 개선: 정확도를 높이기 위해 고정소수점 연산 사용
//                             // 거리(cm) = 에코 시간(us) / 58 = 에코 카운트 / (58 * 100)
//                             // 먼저 100을 곱하고 5800으로 나눠 소수점 정확도 향상
//                             distance_cm <= (echo_counter * 100) / 5800;
//                             measurement_valid <= 1;
//                         end
//                     end

//                     // 결과 할당 - 유효한 측정이 있을 때만 업데이트
//                     if (measurement_valid) begin
//                         if (distance_cm > 9900) begin  // 99cm 이상이면 99cm로 표시
//                             distance_output <= 99;
//                         end else begin
//                             distance_output <= (distance_cm / 100);  // cm 단위로 변환 (소수점 제거)
//                         end
//                     end
//                 end

//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule




// module dist_calculator(
//     input clk,                    // 시스템 클럭 (100MHz)
//     input reset,                  // 리셋 신호
//     input echo,                   // 초음파 센서 에코 핀
//     input btn_start,              // 시작 버튼 입력
//     output reg trigger,           // 초음파 센서 트리거 핀
//     output [6:0] msec,            // 측정된 거리 값 (0-99cm)
//     output reg [3:0] led_indicator,  // LED 상태 표시
//     output reg start,             // 측정 시작 플래그
//     output reg done               // 측정 완료 플래그
// );

//     // 상태 정의 - FSM 다이어그램에 맞게 수정
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;           // 범용 카운터
//     reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
//     reg [31:0] distance_cm;       // 계산된 거리 (cm)
//     reg echo_prev;                // 이전 에코 신호 상태

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // msec 출력 할당 (7비트로 제한, 0-99)
//     assign msec = (distance_cm > 99) ? 99 : distance_cm[6:0];

//     // 상태 머신 - 상태 전이
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= IDLE;
//             echo_prev <= 0;
//         end else begin
//             current_state <= next_state;
//             echo_prev <= echo;
//         end
//     end

//     // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
//     always @(*) begin
//         case (current_state)
//             IDLE: begin
//                 if (btn_start)  // 버튼 입력으로 시작
//                     next_state = TRIGGER;
//                 else
//                     next_state = IDLE;
//             end

//             TRIGGER: begin
//                 if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
//                     next_state = WAIT_ECHO;
//                 end else begin
//                     next_state = TRIGGER;
//                 end
//             end

//             WAIT_ECHO: begin
//                 if (echo_posedge)  // 에코 신호가 시작되면
//                     next_state = COUNT_ECHO;
//                 else
//                     next_state = WAIT_ECHO;
//             end

//             COUNT_ECHO: begin
//                 if (echo_negedge)  // 에코 신호가 끝나면
//                     next_state = IDLE;
//                 else
//                     next_state = COUNT_ECHO;
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // 상태 머신 - 동작 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             counter <= 0;
//             echo_counter <= 0;
//             distance_cm <= 0;
//             trigger <= 0;
//             led_indicator <= 4'b0000;
//             start <= 0;
//             done <= 0;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     echo_counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0001;
//                     start <= 0;
//                     done <= 0;
//                 end

//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_indicator <= 4'b0010;
//                     start <= 1;

//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end

//                 WAIT_ECHO: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0100;
//                     start <= 0;
//                 end

//                 COUNT_ECHO: begin
//                     echo_counter <= echo_counter + 1;  // 에코 시간 측정
//                     led_indicator <= 4'b1000;

//                     if (echo_negedge) begin
//                         done <= 1;
//                         // 거리 계산: 거리(cm) = 에코 시간(us) / 58
//                         // 100MHz 클럭에서 1us = 100 클럭 카운트
//                         // 따라서 거리(cm) = 카운트 / 5800
//                         distance_cm <= echo_counter / 58;  // 스케일링 필요
//                     end
//                 end

//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_indicator <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule
