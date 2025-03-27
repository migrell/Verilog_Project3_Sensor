module dist_calculator(
    input clk,                    // 시스템 클럭 (100MHz)
    input reset,                  // 리셋 신호
    input echo,                   // 초음파 센서 에코 핀
    input btn_start,              // 시작 버튼 입력
    output reg trigger,           // 초음파 센서 트리거 핀
    output [6:0] msec,            // 측정된 거리 값 (0-99cm)
    output reg [3:0] led_indicator,  // LED 상태 표시
    output reg start,             // 측정 시작 플래그
    output reg done               // 측정 완료 플래그
);

    // 상태 정의 - FSM 다이어그램에 맞게 수정
    localparam IDLE = 3'd0;
    localparam TRIGGER = 3'd1;
    localparam WAIT_ECHO = 3'd2;
    localparam COUNT_ECHO = 3'd3;
    localparam COMPLETE = 3'd4;   // 새로운 상태 추가: 측정 완료

    // 내부 레지스터
    reg [2:0] current_state;      // 상태 비트 확장 (5개 상태 필요)
    reg [2:0] next_state;
    reg [31:0] counter;           // 범용 카운터
    reg [31:0] echo_counter;      // 에코 펄스 폭 측정용 카운터
    reg [31:0] distance_cm;       // 계산된 거리 (cm)
    reg echo_prev;                // 이전 에코 신호 상태
    reg [31:0] done_counter;      // done 신호 유지 카운터
    reg btn_start_prev;           // 이전 버튼 상태 (엣지 감지용)
    reg measurement_valid;        // 유효한 측정이 완료되었는지 표시
    
    // 측정된 거리 값을 저장하는 레지스터
    reg [6:0] distance_output;    // 출력용 거리 값 (0-99cm)

    // 에코 신호 엣지 감지
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;
    
    // 버튼 엣지 감지
    wire btn_start_posedge = btn_start && !btn_start_prev;

    // msec 출력 할당 (7비트로 제한, 0-99)
    assign msec = distance_output;

    // 상태 머신 - 상태 전이
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            echo_prev <= 0;
            btn_start_prev <= 0;
        end else begin
            current_state <= next_state;
            echo_prev <= echo;
            btn_start_prev <= btn_start;
        end
    end

    // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (btn_start_posedge)  // 버튼 상승 엣지로 시작
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
                else if (counter >= 100000000)  // 1초 타임아웃 (100,000,000 클럭 @ 100MHz)
                    next_state = COMPLETE;  // 에코가 없어도 완료 상태로 전환
                else
                    next_state = WAIT_ECHO;
            end
            
            COUNT_ECHO: begin
                if (echo_negedge)  // 에코 신호가 끝나면
                    next_state = COMPLETE;
                else if (echo_counter >= 30000000)  // 300ms 제한 (30,000,000 클럭 @ 100MHz)
                    next_state = COMPLETE;  // 최대 측정 시간 초과
                else
                    next_state = COUNT_ECHO;
            end
            
            COMPLETE: begin
                if (done_counter >= 10000000)  // done 신호 100ms 유지 (10,000,000 클럭 @ 100MHz)
                    next_state = IDLE;
                else
                    next_state = COMPLETE;
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
            distance_output <= 0;
            trigger <= 0;
            led_indicator <= 4'b0000;
            start <= 0;
            done <= 0;
            done_counter <= 0;
            measurement_valid <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    counter <= 0;
                    echo_counter <= 0;
                    trigger <= 0;
                    led_indicator <= 4'b0001;
                    start <= 0;
                    done <= 0;
                    done_counter <= 0;
                    // IDLE 상태에서는 이전 유효한 측정값 유지
                end
                
                TRIGGER: begin
                    counter <= counter + 1;
                    trigger <= 1;  // 트리거 신호 생성 (10us)
                    led_indicator <= 4'b0010;
                    start <= 1;
                    measurement_valid <= 0;
                    
                    if (counter >= 1000) begin
                        trigger <= 0;  // 트리거 신호 종료
                    end
                end
                
                WAIT_ECHO: begin
                    counter <= counter + 1;  // 타임아웃 감지를 위한 카운터
                    trigger <= 0;
                    led_indicator <= 4'b0100;
                    start <= 0;
                end
                
                COUNT_ECHO: begin
                    echo_counter <= echo_counter + 1;  // 에코 시간 측정
                    led_indicator <= 4'b1000;
                end
                
                COMPLETE: begin
                    done_counter <= done_counter + 1;
                    done <= 1;  // 완료 신호 활성화
                    led_indicator <= 4'b1111;
                    
                    if (done_counter == 0) begin  // 첫 사이클에서만 거리 계산
                        if (echo_counter > 0 && echo_counter < 30000000) begin  // 유효한 측정
                            // 거리 계산 개선: 정확도를 높이기 위해 고정소수점 연산 사용
                            // 거리(cm) = 에코 시간(us) / 58 = 에코 카운트 / (58 * 100)
                            // 먼저 100을 곱하고 5800으로 나눠 소수점 정확도 향상
                            distance_cm <= (echo_counter * 100) / 5800;
                            measurement_valid <= 1;
                        end
                    end
                    
                    // 결과 할당 - 유효한 측정이 있을 때만 업데이트
                    if (measurement_valid) begin
                        if (distance_cm > 9900) begin  // 99cm 이상이면 99cm로 표시
                            distance_output <= 99;
                        end else begin
                            distance_output <= (distance_cm / 100);  // cm 단위로 변환 (소수점 제거)
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