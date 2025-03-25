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

    // 에코 신호 엣지 감지
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;

    // msec 출력 할당 (7비트로 제한, 0-99)
    assign msec = (distance_cm > 99) ? 99 : distance_cm[6:0];

    // 상태 머신 - 상태 전이
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            echo_prev <= 0;
        end else begin
            current_state <= next_state;
            echo_prev <= echo;
        end
    end

    // 상태 머신 - 다음 상태 결정 (FSM 다이어그램에 맞게 수정)
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (btn_start)  // 버튼 입력으로 시작
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
            start <= 0;
            done <= 0;
        end else begin
            case (current_state)
                IDLE: begin
                    counter <= 0;
                    echo_counter <= 0;
                    trigger <= 0;
                    led_indicator <= 4'b0001;
                    start <= 0;
                    done <= 0;
                end
                
                TRIGGER: begin
                    counter <= counter + 1;
                    trigger <= 1;  // 트리거 신호 생성 (10us)
                    led_indicator <= 4'b0010;
                    start <= 1;
                    
                    if (counter >= 1000) begin
                        trigger <= 0;  // 트리거 신호 종료
                    end
                end
                
                WAIT_ECHO: begin
                    counter <= 0;
                    trigger <= 0;
                    led_indicator <= 4'b0100;
                    start <= 0;
                end
                
                COUNT_ECHO: begin
                    echo_counter <= echo_counter + 1;  // 에코 시간 측정
                    led_indicator <= 4'b1000;
                    
                    if (echo_negedge) begin
                        done <= 1;
                        // 거리 계산: 거리(cm) = 에코 시간(us) / 58
                        // 100MHz 클럭에서 1us = 100 클럭 카운트
                        // 따라서 거리(cm) = 카운트 / 5800
                        distance_cm <= echo_counter / 58;  // 스케일링 필요
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