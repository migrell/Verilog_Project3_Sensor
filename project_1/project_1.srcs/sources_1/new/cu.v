module cu(
    input clk,               // 시스템 클럭 (100MHz)
    input reset,             // 리셋 신호
    input btn_start,         // 시작 버튼
    input echo,              // 에코 신호
    input dp_done,           // DP에서 측정 완료 신호
    input tick_10msec,
    output reg trigger,      // 초음파 센서 트리거 핀
    output reg start_dp,     // DP 시작 신호
    output reg [3:0] led_status  // LED 상태 표시
);

    // 상태 정의 - FSM에 맞게 4개 상태로 수정
    localparam IDLE = 2'd0;
    localparam TRIGGER = 2'd1;
    localparam WAIT_ECHO = 2'd2;
    localparam COUNT_ECHO = 2'd3;

    // 내부 레지스터
    reg [1:0] current_state;
    reg [1:0] next_state;
    reg [31:0] counter;
    reg echo_prev;  // 에코 신호의 이전 값

    // 에코 신호 엣지 감지
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;

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
            trigger <= 0;
            start_dp <= 0;
            led_status <= 4'b0000;
        end else begin
            case (current_state)
                IDLE: begin
                    counter <= 0;
                    trigger <= 0;
                    start_dp <= 0;
                    led_status <= 4'b0001;
                end
                
                TRIGGER: begin
                    counter <= counter + 1;
                    trigger <= 1;  // 트리거 신호 생성 (10us)
                    led_status <= 4'b0010;
                    
                    if (counter >= 1000) begin
                        trigger <= 0;  // 트리거 신호 종료
                    end
                end
                
                WAIT_ECHO: begin
                    counter <= 0;
                    trigger <= 0;
                    led_status <= 4'b0100;
                    start_dp <= 1;  // DP 모듈 시작
                end
                
                COUNT_ECHO: begin
                    start_dp <= 0;  // 시작 신호는 한 클럭만 유지
                    led_status <= 4'b1000;
                end
                
                default: begin
                    counter <= 0;
                    trigger <= 0;
                    start_dp <= 0;
                    led_status <= 4'b0000;
                end
            endcase
        end
    end

endmodule