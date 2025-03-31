module dp (
    input clk,
    input reset,
    input echo,
    input start_trigger,
    output reg done,       // reg로 변경
    output reg [6:0] msec  // reg로 변경
);
    // 내부 신호
    reg [19:0] echo_counter;     // 에코 펄스 폭 측정
    reg [23:0] tick_counter;     // 타이밍 카운터 추가 (더 넓은 범위로 설정)
    reg echo_prev;               // 이전 에코 상태
    reg echo_detected;           // 에코 감지 플래그 추가
    reg measuring;               // 측정 중 플래그
    
    // 에코 신호 엣지 감지 개선
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;
    
    // 10ms 타이밍 생성 (100MHz 클럭 기준) - 내부에서 직접 생성
    wire tick_10ms = (tick_counter >= 24'd1_000_000); // 10ms마다 1 생성

    // 틱 카운터 업데이트
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tick_counter <= 24'd0;
        end else begin
            if (tick_counter >= 24'd1_000_000) begin
                tick_counter <= 24'd0; // 카운터 리셋
            end else begin
                tick_counter <= tick_counter + 1'b1;
            end
        end
    end
    
    // 에코 펄스 폭 측정 및 거리 계산
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            echo_counter <= 0;
            echo_prev <= 0;
            echo_detected <= 0;
            msec <= 0;
            done <= 0;
            measuring <= 0;
        end else begin
            // 에코 엣지 감지를 위한 이전 상태 저장
            echo_prev <= echo;
            
            // 기본적으로 done 신호는 0으로 유지
            if (done) done <= 0;
            
            // 시작 트리거를 받으면 측정 시작
            if (start_trigger) begin
                measuring <= 1;
                echo_counter <= 0;
                echo_detected <= 0;
                done <= 0;
            end
            
            // 에코 신호 상승 에지 (초음파 반사파 도착 시작)
            if (echo_posedge && measuring) begin
                echo_counter <= 0;
                echo_detected <= 1;
            end
            
            // 에코 펄스 유지 중 카운터 증가
            if (echo && measuring && echo_detected) begin
                echo_counter <= echo_counter + 1;
            end
            
            // 에코 신호 하강 에지 (측정 완료)
            if (echo_negedge && measuring && echo_detected) begin
                // 거리 계산: echo_counter / 58 (100MHz 클럭 기준)
                if (echo_counter < 58) begin
                    msec <= 7'd1; // 최소 1cm
                end else if (echo_counter > 58*400) begin // 약 4m 이상
                    msec <= 7'd99; // 최대 99cm로 제한
                end else begin
                    msec <= echo_counter / 58;
                end
                done <= 1;
                measuring <= 0;
            end
            
            // 타임아웃 처리 (독립적인 내부 틱 사용)
            if (measuring && tick_10ms) begin
                // 측정 시작 후 10ms 이상 경과했는데도 에코 측정이 완료되지 않았다면
                if (!echo_detected) begin
                    // 에코 자체가 감지되지 않은 경우 (장애물 없음 또는 응답 없음)
                    msec <= 7'd0;
                    done <= 1;
                    measuring <= 0;
                end else if (!echo && echo_detected) begin
                    // 에코가 시작되었고 이미 끝난 경우 (정상 측정 완료)
                    // 이 경우는 위의 echo_negedge 조건에서 처리됨
                end else if (echo && echo_detected && echo_counter > 58*400) begin
                    // 에코가 시작되었지만 너무 오래 지속되는 경우 (범위 초과)
                    msec <= 7'd99;
                    done <= 1;
                    measuring <= 0;
                end
            end
        end
    end
endmodule

// module dp(
//     input clk,              // 시스템 클럭 (100MHz)
//     input reset,            // 리셋 신호
//     input echo,             // 초음파 센서 에코 핀
//     input start_trigger,    // 측정 시작 트리거 (CU에서 제공)
//     output reg done,        // 측정 완료 신호
//     output reg [6:0] msec   // 계산된 거리 값 (0-99cm)
// );

//     // 내부 레지스터
//     reg [31:0] distance_counter;
//     reg [31:0] distance_cm;
//     reg [31:0] timeout_counter;      // 타임아웃 감지용 카운터 추가
//     reg processing;
//     reg echo_prev;
//     reg timeout_flag;                // 타임아웃 플래그 추가
//     reg echo_detected;               // 에코 신호가 감지되었는지 확인하는 플래그 추가
    
//     // 에코 신호의 상승/하강 에지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

//     // 파라미터 - 실제 하드웨어 구현을 위한 값으로 변경
//     parameter TIMEOUT_VALUE = 25_000_000;  // 250ms 타임아웃 (원래 값으로 복원)
//     parameter MIN_VALID_ECHO = 100;        // 최소 유효 에코 폭

//     // 디버깅용 상태 표시
//     reg [2:0] state;
//     localparam STATE_IDLE = 3'd0;
//     localparam STATE_WAIT_ECHO = 3'd1;
//     localparam STATE_COUNTING = 3'd2;
//     localparam STATE_DONE = 3'd3;
//     localparam STATE_TIMEOUT = 3'd4;

//     // 거리 계산 및 에코 감지 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             distance_counter <= 0;
//             distance_cm <= 0;
//             timeout_counter <= 0;
//             timeout_flag <= 0;
//             processing <= 0;
//             done <= 0;
//             msec <= 0;
//             echo_prev <= 0;
//             echo_detected <= 0;
//             state <= STATE_IDLE;
//         end else begin
//             echo_prev <= echo; // 이전 에코 상태 저장
            
//             case (state)
//                 STATE_IDLE: begin
//                     // 측정 시작 신호 대기
//                     if (start_trigger && !processing) begin
//                         state <= STATE_WAIT_ECHO;
//                         processing <= 1;
//                         distance_counter <= 0;
//                         timeout_counter <= 0;
//                         timeout_flag <= 0;
//                         echo_detected <= 0;
//                         done <= 0;
//                     end
//                 end
                
//                 STATE_WAIT_ECHO: begin
//                     // 에코 신호 대기 또는 타임아웃 감지
//                     if (echo_posedge) begin
//                         // 에코 시작 - 카운터 리셋
//                         state <= STATE_COUNTING;
//                         distance_counter <= 0;
//                         timeout_counter <= 0;
//                         echo_detected <= 1;
//                     end else begin
//                         // 타임아웃 카운터 증가
//                         timeout_counter <= timeout_counter + 1;
                        
//                         // 타임아웃 체크
//                         if (timeout_counter >= TIMEOUT_VALUE - 1) begin
//                             state <= STATE_TIMEOUT;
//                             timeout_flag <= 1;
//                         end
//                     end
//                 end
                
//                 STATE_COUNTING: begin
//                     // 에코 HIGH 동안 카운트
//                     if (echo) begin
//                         distance_counter <= distance_counter + 1;
//                     end
                    
//                     // 에코 종료 감지
//                     if (echo_negedge) begin
//                         state <= STATE_DONE;
//                     end
                    
//                     // 에코 카운팅 중 타임아웃 체크
//                     timeout_counter <= timeout_counter + 1;
//                     if (timeout_counter >= TIMEOUT_VALUE - 1) begin
//                         state <= STATE_TIMEOUT;
//                         timeout_flag <= 1;
//                     end
//                 end
                
//                 STATE_DONE: begin
//                     // 거리 계산 완료
//                     processing <= 0;
//                     done <= 1;
                    
//                     // 에코 펄스 폭 검증
//                     if (distance_counter >= MIN_VALID_ECHO) begin
//                         // 거리 계산 - 정확한 스케일링 적용
//                         // 거리(cm) = 에코 시간(us) / 58
//                         // 100MHz 클럭에서 1us = 100 클럭 카운트
//                         // 따라서 거리(cm) = 카운트 / 5800
                        
//                         // 개선된 계산 방식 - 측정 정확도 향상
//                         distance_cm <= (distance_counter / 5800);
                        
//                         // msec 출력 범위 제한 (0-99cm)
//                         if ((distance_counter / 5800) > 99)
//                             msec <= 99;
//                         else
//                             msec <= (distance_counter / 5800);
//                     end else begin
//                         // 에코 펄스가 너무 짧음 - 노이즈일 가능성 높음
//                         msec <= 7'd0; // 유효하지 않은 측정 표시
//                     end
                    
//                     state <= STATE_IDLE; // 다음 측정 준비
//                 end
                
//                 STATE_TIMEOUT: begin
//                     // 타임아웃 발생
//                     processing <= 0;
//                     done <= 1;
//                     msec <= 7'd0; // 타임아웃 시 0 출력
//                     state <= STATE_IDLE; // 다음 측정 준비
//                 end
                
//                 default: state <= STATE_IDLE;
//             endcase
//         end
//     end

// endmodule