module dp(
    input clk,              // 시스템 클럭 (100MHz)
    input reset,            // 리셋 신호
    input echo,             // 초음파 센서 에코 핀
    input start_trigger,    // 측정 시작 트리거 (CU에서 제공)
    output reg done,        // 측정 완료 신호
    output reg [6:0] msec   // 계산된 거리 값 (0-99cm)
);

    // 내부 레지스터
    reg [31:0] distance_counter;
    reg [31:0] distance_cm;
    reg [31:0] timeout_counter;      // 타임아웃 감지용 카운터 추가
    reg processing;
    reg echo_prev;
    reg timeout_flag;                // 타임아웃 플래그 추가
    
    // 에코 신호의 상승/하강 에지 감지
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;

    // 파라미터
    parameter TIMEOUT_VALUE = 25_000_000;  // 250ms 타임아웃
    parameter MIN_VALID_ECHO = 100;        // 최소 유효 에코 폭

    // 거리 계산 및 에코 감지 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            distance_counter <= 0;
            distance_cm <= 0;
            timeout_counter <= 0;
            timeout_flag <= 0;
            processing <= 0;
            done <= 0;
            msec <= 0;
            echo_prev <= 0;
        end else begin
            echo_prev <= echo; // 이전 에코 상태 저장
            
            if (start_trigger && !processing) begin
                // 측정 시작
                processing <= 1;
                distance_counter <= 0;
                timeout_counter <= 0;
                timeout_flag <= 0;
                done <= 0;
            end else if (processing) begin
                // 에코 신호 대기 중 타임아웃 카운터 증가
                if (!echo && !timeout_flag) begin
                    timeout_counter <= timeout_counter + 1;
                    
                    // 타임아웃 체크
                    if (timeout_counter >= TIMEOUT_VALUE - 1) begin
                        timeout_flag <= 1;
                        processing <= 0;
                        done <= 1;
                        msec <= 0; // 유효하지 않은 측정 표시
                    end
                end
                
                if (echo_posedge) begin
                    // 에코 시작 - 카운터 리셋
                    distance_counter <= 0;
                    timeout_counter <= 0; // 에코 감지 시 타임아웃 카운터 리셋
                end else if (echo) begin
                    // 에코 HIGH 동안 카운트
                    distance_counter <= distance_counter + 1;
                end else if (echo_negedge) begin
                    // 에코 종료 - 거리 계산
                    processing <= 0;
                    done <= 1;
                    
                    // 에코 펄스 폭 검증
                    if (distance_counter >= MIN_VALID_ECHO) begin
                        // 거리 계산: 거리(cm) = 에코 시간(us) / 58
                        // 100MHz 클럭에서 1us = 100 클럭 카운트
                        // 따라서 거리(cm) = 카운트 / 5800
                        distance_cm <= distance_counter / 5800;
                        
                        // msec 출력 범위 제한 (0-99cm)
                        if (distance_counter / 5800 > 99)
                            msec <= 99;
                        else
                            msec <= (distance_counter / 5800);
                    end else begin
                        // 에코 펄스가 너무 짧음 - 노이즈일 가능성 높음
                        msec <= 0; // 유효하지 않은 측정 표시
                    end
                end
            end
        end
    end

endmodule