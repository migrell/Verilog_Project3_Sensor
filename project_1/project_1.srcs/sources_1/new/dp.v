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
    reg processing;
    reg echo_prev;
    
    // 에코 신호의 상승/하강 에지 감지
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;

    // 거리 계산 및 에코 감지 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            distance_counter <= 0;
            distance_cm <= 0;
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
                done <= 0;
            end else if (processing) begin
                if (echo_posedge) begin
                    // 에코 시작 - 카운터 리셋
                    distance_counter <= 0;
                end else if (echo) begin
                    // 에코 HIGH 동안 카운트
                    distance_counter <= distance_counter + 1;
                end else if (echo_negedge) begin
                    // 에코 종료 - 거리 계산
                    processing <= 0;
                    done <= 1;
                    
                    // 거리 계산: 거리(cm) = 에코 시간(us) / 58
                    // 100MHz 클럭에서 1us = 100 클럭 카운트
                    // 따라서 거리(cm) = 카운트 / 5800
                    distance_cm <= distance_counter / 5800;
                    
                    // msec 출력 범위 제한 (0-99cm)
                    if (distance_counter / 5800 > 99)
                        msec <= 99;
                    else
                        msec <= (distance_counter / 5800);
                end
            end
        end
    end

endmodule