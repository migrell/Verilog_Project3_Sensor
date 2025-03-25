module cu(
    input clk,               // 시스템 클럭 (100MHz)
    input reset,             // 리셋 신호
    input dp_done,           // DP에서 측정 완료 신호
    output reg trigger,      // 초음파 센서 트리거 핀
    output reg start_dp,     // DP 시작 신호
    output reg [3:0] led_status  // LED 상태 표시
);

    // 상태 정의
    localparam IDLE = 2'd0;
    localparam TRIG = 2'd1;
    localparam WAIT_DP = 2'd2;
    localparam DONE = 2'd3;

    // 내부 레지스터
    reg [1:0] current_state;
    reg [1:0] next_state;
    reg [31:0] counter;

    // 상태 머신 - 상태 전이
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // 상태 머신 - 다음 상태 결정
    always @(*) begin
        case (current_state)
            IDLE: begin
                next_state = TRIG;
            end
            TRIG: begin
                if (counter >= 1000) begin  // 10us (1000 클럭 @ 100MHz)
                    next_state = WAIT_DP;
                end else begin
                    next_state = TRIG;
                end
            end
            WAIT_DP: begin
                if (dp_done) begin
                    next_state = DONE;
                end else begin
                    next_state = WAIT_DP;
                end
            end
            DONE: begin
                // 측정 완료 후 일정 시간 대기 (60ms)
                if (counter >= 6000000) begin  // 60ms (6M 클럭 @ 100MHz)
                    next_state = IDLE;
                end else begin
                    next_state = DONE;
                end
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
                
                TRIG: begin
                    counter <= counter + 1;
                    trigger <= 1;  // 트리거 신호 생성 (10us)
                    led_status <= 4'b0010;
                    
                    if (counter >= 1000) begin
                        trigger <= 0;  // 트리거 신호 종료
                        start_dp <= 1; // DP 모듈 시작
                    end
                end
                
                WAIT_DP: begin
                    trigger <= 0;
                    start_dp <= 0; // 시작 신호는 한 클럭만 유지
                    counter <= 0;
                    led_status <= 4'b0100;
                end
                
                DONE: begin
                    counter <= counter + 1;
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