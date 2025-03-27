module cu(
    input clk,               // 시스템 클럭 (100MHz)
    input reset,             // 리셋 신호
    input btn_start,         // 시작 버튼
    input echo,              // 에코 신호
    input dp_done,           // DP에서 측정 완료 신호
    input tick_10msec,       // 10msec 주기 신호
    output reg trigger,      // 초음파 센서 트리거 핀
    output reg start_dp,     // DP 시작 신호
    output reg [3:0] led_status,  // LED 상태 표시
    output reg fsm_error     // FSM 오류 신호 (상태 고착 감지)
);

    // 상태 정의 - FSM에 맞게 4개 상태로 수정
    localparam IDLE = 2'd0;
    localparam TRIGGER = 2'd1;
    localparam WAIT_ECHO = 2'd2;
    localparam COUNT_ECHO = 2'd3;

    // 내부 레지스터
    reg [1:0] current_state;
    reg [1:0] next_state;
    reg [1:0] prev_state;    // 이전 상태 저장용
    reg [31:0] counter;
    reg [31:0] cycle_counter;    // 측정 사이클 카운터 추가
    reg echo_prev;           // 에코 신호의 이전 값
    
    // 상태 모니터링을 위한 레지스터
    reg [31:0] state_timeout_counter;  // 상태 타임아웃 카운터
    reg [31:0] idle_counter;           // IDLE 상태 지속 시간 카운터
    reg [7:0] error_count;             // 연속 오류 횟수 카운터 추가
    
    // 상태별 타임아웃 값 (클럭 사이클 수) - 시뮬레이션을 위해 축소
    // Original values:
    // localparam TRIGGER_TIMEOUT = 2000;         // 20us (10us 트리거 + 여유)
    // localparam WAIT_ECHO_TIMEOUT = 25_000_000; // 250ms (최대 에코 대기 시간)
    // localparam COUNT_ECHO_TIMEOUT = 25_000_000; // 250ms (최대 에코 지속 시간)
    // localparam IDLE_TIMEOUT_MS = 10000;        // 100초 (10msec tick 기준)
    
    // Modified values for simulation:
    localparam TRIGGER_TIMEOUT = 2000;         // 20us (unchanged)
    localparam WAIT_ECHO_TIMEOUT = 250_000;    // 2.5ms (1/100 of original)
    localparam COUNT_ECHO_TIMEOUT = 250_000;   // 2.5ms (1/100 of original)
    localparam IDLE_TIMEOUT_MS = 100;          // 1s (1/100 of original)
    
    // 에코 신호 엣지 감지
    wire echo_posedge = echo && !echo_prev;
    wire echo_negedge = !echo && echo_prev;

    // 상태 머신 - 상태 전이
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= IDLE;
            echo_prev <= 0;
            prev_state <= IDLE;
            cycle_counter <= 0;
        end else begin
            prev_state <= current_state;
            current_state <= next_state;
            echo_prev <= echo;
            
            // 측정 사이클 완료시 카운터 증가
            if (current_state == COUNT_ECHO && next_state == IDLE) begin
                cycle_counter <= cycle_counter + 1;
                
                // 1000번 측정 후에는 카운터 리셋
                if (cycle_counter >= 999)
                    cycle_counter <= 0;
            end
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
                else if (state_timeout_counter >= WAIT_ECHO_TIMEOUT)  // 타임아웃 발생
                    next_state = IDLE;
                else
                    next_state = WAIT_ECHO;
            end
            
            COUNT_ECHO: begin
                if (echo_negedge)  // 에코 신호가 끝나면
                    next_state = IDLE;
                else if (state_timeout_counter >= COUNT_ECHO_TIMEOUT)  // 타임아웃 발생
                    next_state = IDLE;
                else
                    next_state = COUNT_ECHO;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // 상태 타임아웃 및 오류 감지 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_timeout_counter <= 0;
            idle_counter <= 0;
            fsm_error <= 0;
            error_count <= 0;
        end else begin
            // 상태가 변경되면 타임아웃 카운터 리셋
            if (current_state != prev_state) begin
                state_timeout_counter <= 0;
            end else begin
                state_timeout_counter <= state_timeout_counter + 1;
            end
            
            // IDLE 상태 타임아웃 처리 (10msec tick 기반)
            if (current_state == IDLE) begin
                if (tick_10msec) begin
                    idle_counter <= idle_counter + 1;
                    if (idle_counter >= IDLE_TIMEOUT_MS) begin
                        fsm_error <= 1;  // IDLE 상태에 너무 오래 머물러 있음
                    end
                end
            end else begin
                idle_counter <= 0;
            end
            
            // 상태별 타임아웃 처리
            case (current_state)
                TRIGGER: begin
                    if (state_timeout_counter >= TRIGGER_TIMEOUT) begin
                        fsm_error <= 1;  // TRIGGER 상태 타임아웃
                        error_count <= error_count + 1;
                    end
                end
                
                WAIT_ECHO: begin
                    if (state_timeout_counter >= WAIT_ECHO_TIMEOUT) begin
                        fsm_error <= 1;  // WAIT_ECHO 상태 타임아웃
                        error_count <= error_count + 1;
                    end
                end
                
                COUNT_ECHO: begin
                    if (state_timeout_counter >= COUNT_ECHO_TIMEOUT) begin
                        fsm_error <= 1;  // COUNT_ECHO 상태 타임아웃
                        error_count <= error_count + 1;
                    end
                end
                
                default: begin
                    // IDLE 상태는 위에서 별도로 처리
                end
            endcase
            
            // 오류가 발생했을 때 오류 LED 깜빡임 또는 리셋 로직을 추가할 수 있음
            if (btn_start) begin
                fsm_error <= 0;  // 버튼을 누르면 오류 상태 클리어
                if (error_count > 0)
                    error_count <= error_count - 1;
            end
            
            // 연속 오류가 5회 이상이면 시스템 상태 강제 리셋
            if (error_count >= 5) begin
                fsm_error <= 1;
            end
        end
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
                    if (fsm_error)
                        led_status <= 4'b1111;  // 오류 발생 시 모든 LED 켜기
                    else
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
// module cu(
//     input clk,               // 시스템 클럭 (100MHz)
//     input reset,             // 리셋 신호
//     input btn_start,         // 시작 버튼
//     input echo,              // 에코 신호
//     input dp_done,           // DP에서 측정 완료 신호
//     input tick_10msec,
//     output reg trigger,      // 초음파 센서 트리거 핀
//     output reg start_dp,     // DP 시작 신호
//     output reg [3:0] led_status  // LED 상태 표시
// );

//     // 상태 정의 - FSM에 맞게 4개 상태로 수정
//     localparam IDLE = 2'd0;
//     localparam TRIGGER = 2'd1;
//     localparam WAIT_ECHO = 2'd2;
//     localparam COUNT_ECHO = 2'd3;

//     // 내부 레지스터
//     reg [1:0] current_state;
//     reg [1:0] next_state;
//     reg [31:0] counter;
//     reg echo_prev;  // 에코 신호의 이전 값

//     // 에코 신호 엣지 감지
//     wire echo_posedge = echo && !echo_prev;
//     wire echo_negedge = !echo && echo_prev;

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
//             trigger <= 0;
//             start_dp <= 0;
//             led_status <= 4'b0000;
//         end else begin
//             case (current_state)
//                 IDLE: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     start_dp <= 0;
//                     led_status <= 4'b0001;
//                 end
                
//                 TRIGGER: begin
//                     counter <= counter + 1;
//                     trigger <= 1;  // 트리거 신호 생성 (10us)
//                     led_status <= 4'b0010;
                    
//                     if (counter >= 1000) begin
//                         trigger <= 0;  // 트리거 신호 종료
//                     end
//                 end
                
//                 WAIT_ECHO: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     led_status <= 4'b0100;
//                     start_dp <= 1;  // DP 모듈 시작
//                 end
                
//                 COUNT_ECHO: begin
//                     start_dp <= 0;  // 시작 신호는 한 클럭만 유지
//                     led_status <= 4'b1000;
//                 end
                
//                 default: begin
//                     counter <= 0;
//                     trigger <= 0;
//                     start_dp <= 0;
//                     led_status <= 4'b0000;
//                 end
//             endcase
//         end
//     end

// endmodule