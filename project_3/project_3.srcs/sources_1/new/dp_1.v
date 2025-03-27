// dp.v 파일 수정 - 포트 연결 너비 일치하도록 
module dp (
    input clk,
    input reset,
    input echo,
    input start_trigger,
    output reg done,        // reg로 변경
    output reg [6:0] msec   // reg로 변경
);
    // 내부 신호
    reg [19:0] echo_counter; // 에코 펄스 폭 측정
    reg echo_prev;           // 이전 에코 상태
    reg measuring;           // 측정 중 플래그
    
    // 에코 펄스 폭 측정 및 거리 계산
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            echo_counter <= 0;
            echo_prev <= 0;
            msec <= 0;
            done <= 0;
            measuring <= 0;
        end else begin
            echo_prev <= echo;
            done <= 0; // 기본값 설정
            
            // 측정 시작 트리거
            if (start_trigger) begin
                measuring <= 1;
                echo_counter <= 0;
            end
            
            // 에코 펄스 상승 에지
            if (echo && !echo_prev && measuring) begin
                echo_counter <= 0;
            end
            
            // 에코 펄스 폭 측정
            if (echo && measuring) begin
                echo_counter <= echo_counter + 1;
            end
            
            // 에코 펄스 하강 에지 (측정 완료)
            if (!echo && echo_prev && measuring) begin
                // 거리 = 펄스 폭(us) * 음속(340m/s) / 2
                // = 펄스 폭(클럭 수) * 340 / 2 / 클럭주파수(MHz)
                // 100MHz 클럭에서, 1cm = 58.24 클럭 사이클
                // 따라서 거리(cm) = 에코 카운터 / 58
                msec <= echo_counter / 58;
                done <= 1;
                measuring <= 0;
            end
            
            // 타임아웃 처리
            if (echo_counter > 1_000_000) begin // 10ms 이상 (범위 외)
                msec <= 7'd99; // 최대 값으로 표시
                done <= 1;
                measuring <= 0;
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