module fsm_controller (
    input clk,
    input reset,
    input [3:0] sw,        // 4개 스위치로 확장 [W17, W16, V16, V17]
    input btn_run,
    input sw_mode_in,
    output reg [2:0] current_state,
    output reg is_clock_mode,
    output reg is_ultrasonic_mode,
    output reg is_temp_humid_mode,
    output reg sw2,
    output reg sw3,
    output reg sw4,
    output reg sw5
);
    // 상태 정의
    parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
    parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
    parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
    parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
    parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM - 스위치 조합 1000
    parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch - 스위치 조합 1000 (버튼으로 전환)
    parameter STATE_6 = 3'b110;  // Temperature Mode - 스위치 조합 0100
    parameter STATE_7 = 3'b111;  // Humidity Mode - 스위치 조합 0100 (버튼으로 전환)
    
    // sw[1:0]은 V16, V17에 해당함
    wire sw0, sw1;
    assign sw0 = sw[0]; // V17
    assign sw1 = sw[1]; // V16
    
    // 버튼 엣지 감지
    reg btn_run_prev;
    wire btn_run_edge;
    assign btn_run_edge = btn_run & ~btn_run_prev;
    
    // 스위치 동기화 및 디바운싱
    reg [3:0] sw_meta1, sw_meta2, sw_meta3, sw_stable;
    reg [3:0] prev_sw;
    reg [19:0] sw_debounce_counter;
    parameter SW_DEBOUNCE_DELAY = 20'd50000; // 0.5ms @ 100MHz
    
    // 스위치 엣지 감지
    wire [3:0] sw_rising_edge;
    assign sw_rising_edge = sw_stable & ~prev_sw;
    
    // 모드 전환 관련 변수
    reg mode_change_requested;
    reg [1:0] requested_mode; // 00: 기본, 01: 초음파, 10: 온습도
    reg [25:0] mode_transition_counter;
    parameter MODE_TRANSITION_DELAY = 26'd10000000; // 100ms @ 100MHz
    
    // 초음파 모드와 온습도 모드 플래그
    reg ultrasonic_mode_flag;
    reg temp_humid_mode_flag;
    
    // 모드 전환 완료 신호
    reg transition_done;
    reg [25:0] done_pulse_counter;
    parameter DONE_PULSE_DURATION = 26'd10000000; // 100ms
    
    // 스위치 값과 버튼 상태 동기화
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sw_meta1 <= 4'b0000;
            sw_meta2 <= 4'b0000;
            sw_meta3 <= 4'b0000;
            sw_stable <= 4'b0000;
            prev_sw <= 4'b0000;
            btn_run_prev <= 1'b0;
            sw_debounce_counter <= 20'd0;
        end else begin
            // 3단계 동기화로 메타스테이블 해결
            sw_meta1 <= sw;
            sw_meta2 <= sw_meta1;
            sw_meta3 <= sw_meta2;
            
            // 디바운싱 카운터
            if (sw_meta3 != sw_stable) begin
                if (sw_debounce_counter >= SW_DEBOUNCE_DELAY) begin
                    sw_stable <= sw_meta3;
                    sw_debounce_counter <= 20'd0;
                end else begin
                    sw_debounce_counter <= sw_debounce_counter + 1;
                end
            end else begin
                sw_debounce_counter <= 20'd0;
            end
            
            // 이전 값 저장
            prev_sw <= sw_stable;
            btn_run_prev <= btn_run;
        end
    end
    
    // 모드 전환 요청 처리
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mode_change_requested <= 1'b0;
            requested_mode <= 2'b00;
            mode_transition_counter <= 26'd0;
            ultrasonic_mode_flag <= 1'b0;
            temp_humid_mode_flag <= 1'b0;
            transition_done <= 1'b0;
            done_pulse_counter <= 26'd0;
        end else begin
            // 전환 완료 신호 처리
            if (transition_done) begin
                done_pulse_counter <= done_pulse_counter + 1;
                if (done_pulse_counter >= DONE_PULSE_DURATION) begin
                    transition_done <= 1'b0;
                    done_pulse_counter <= 26'd0;
                end
            end
            
            // 스위치 상승 엣지 감지에 따른 모드 전환 요청
            if (sw_rising_edge[3]) begin
                mode_change_requested <= 1'b1;
                requested_mode <= 2'b01; // 초음파 모드
                mode_transition_counter <= MODE_TRANSITION_DELAY;
                ultrasonic_mode_flag <= 1'b1;
                temp_humid_mode_flag <= 1'b0;
            end else if (sw_rising_edge[2] && !sw_stable[3]) begin
                mode_change_requested <= 1'b1;
                requested_mode <= 2'b10; // 온습도 모드
                mode_transition_counter <= MODE_TRANSITION_DELAY;
                ultrasonic_mode_flag <= 1'b0;
                temp_humid_mode_flag <= 1'b1;
            end
            
            // 모드 전환 타이머
            if (mode_transition_counter > 0) begin
                mode_transition_counter <= mode_transition_counter - 1;
                if (mode_transition_counter == 1) begin
                    mode_change_requested <= 1'b0;
                    transition_done <= 1'b1;
                    done_pulse_counter <= 26'd0;
                end
            end
            
            // 스위치 값이 바뀌면 플래그 상태도 갱신
            if (sw_stable[3]) begin
                ultrasonic_mode_flag <= 1'b1;
                temp_humid_mode_flag <= 1'b0;
            end else if (sw_stable[2] && !sw_stable[3]) begin
                ultrasonic_mode_flag <= 1'b0;
                temp_humid_mode_flag <= 1'b1;
            end else if (!sw_stable[3] && !sw_stable[2]) begin
                ultrasonic_mode_flag <= 1'b0;
                temp_humid_mode_flag <= 1'b0;
            end
        end
    end
    
    // 상태 머신 및 출력 제어
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= STATE_0;
            is_clock_mode <= 1'b0;
            is_ultrasonic_mode <= 1'b0;
            is_temp_humid_mode <= 1'b0;
            sw2 <= 1'b0;
            sw3 <= 1'b0;
            sw4 <= 1'b0;
            sw5 <= 1'b0;
        end else begin
            // 강제 모드 전환 처리 (스위치 또는 요청에 따른)
            if (sw_stable[3] || (mode_change_requested && requested_mode == 2'b01)) begin
                // 초음파 모드 CM (STATE_4)
                current_state <= STATE_4;
                is_clock_mode <= 1'b0;
                is_ultrasonic_mode <= 1'b1;
                is_temp_humid_mode <= 1'b0;
                sw2 <= 1'b1;
                sw3 <= 1'b0;
                sw4 <= 1'b1;
                sw5 <= 1'b0;
            end else if (sw_stable[2] || (mode_change_requested && requested_mode == 2'b10)) begin
                // 온습도 모드 온도 (STATE_6)
                current_state <= STATE_6;
                is_clock_mode <= 1'b0;
                is_ultrasonic_mode <= 1'b0;
                is_temp_humid_mode <= 1'b1;
                sw2 <= 1'b0;
                sw3 <= 1'b1;
                sw4 <= 1'b1;
                sw5 <= 1'b1;
            end else begin
                // 시계/스톱워치 모드 (sw[1:0]에 따라)
                if (sw0 == 1'b0 && sw1 == 1'b0) begin
                    // STATE_0 - 스톱워치 Msec:Sec
                    current_state <= STATE_0;
                    is_clock_mode <= 1'b0;
                    is_ultrasonic_mode <= 1'b0;
                    is_temp_humid_mode <= 1'b0;
                    sw2 <= 1'b0;
                    sw3 <= 1'b0;
                    sw4 <= 1'b0;
                    sw5 <= 1'b0;
                end else if (sw0 == 1'b1 && sw1 == 1'b0) begin
                    // STATE_1 - 스톱워치 Hour:Min
                    current_state <= STATE_1;
                    is_clock_mode <= 1'b0;
                    is_ultrasonic_mode <= 1'b0;
                    is_temp_humid_mode <= 1'b0;
                    sw2 <= 1'b0;
                    sw3 <= 1'b0;
                    sw4 <= 1'b0;
                    sw5 <= 1'b0;
                end else if (sw0 == 1'b0 && sw1 == 1'b1) begin
                    // STATE_2 - 시계 Sec:Msec
                    current_state <= STATE_2;
                    is_clock_mode <= 1'b1;
                    is_ultrasonic_mode <= 1'b0;
                    is_temp_humid_mode <= 1'b0;
                    sw2 <= 1'b0;
                    sw3 <= 1'b0;
                    sw4 <= 1'b0;
                    sw5 <= 1'b1;
                end else begin // sw0 == 1'b1 && sw1 == 1'b1
                    // STATE_3 - 시계 Hour:Min
                    current_state <= STATE_3;
                    is_clock_mode <= 1'b1;
                    is_ultrasonic_mode <= 1'b0;
                    is_temp_humid_mode <= 1'b0;
                    sw2 <= 1'b0;
                    sw3 <= 1'b0;
                    sw4 <= 1'b0;
                    sw5 <= 1'b1;
                end
            end
            
            // 버튼에 따른 내부 모드 전환 (CM/Inch, 온도/습도)
            if (btn_run_edge) begin
                case (current_state)
                    STATE_0: begin
                        // 스톱워치 Msec:Sec -> Hour:Min
                        current_state <= STATE_1;
                    end
                    STATE_1: begin
                        // 스톱워치 Hour:Min -> Msec:Sec
                        current_state <= STATE_0;
                    end
                    STATE_2: begin
                        // 시계 Sec:Msec -> Hour:Min
                        current_state <= STATE_3;
                    end
                    STATE_3: begin
                        // 시계 Hour:Min -> Sec:Msec
                        current_state <= STATE_2;
                    end
                    STATE_4: begin
                        // 초음파 CM -> Inch
                        current_state <= STATE_5;
                    end
                    STATE_5: begin
                        // 초음파 Inch -> CM
                        current_state <= STATE_4;
                    end
                    STATE_6: begin
                        // 온도 -> 습도
                        current_state <= STATE_7;
                    end
                    STATE_7: begin
                        // 습도 -> 온도
                        current_state <= STATE_6;
                    end
                    default: begin
                        // 기본 모드로 리셋
                        current_state <= STATE_0;
                    end
                endcase
                
                // 내부 모드 전환 시 transition_done 신호 설정
                transition_done <= 1'b1;
                done_pulse_counter <= 26'd0;
            end
        end
    end
endmodule

// module fsm_controller (
//     input clk,
//     input reset,
//     input [3:0] sw,        // 4개 스위치로 확장 [W17, W16, V16, V17]
//     input btn_run,
//     input sw_mode_in,
//     output reg [2:0] current_state,
//     output reg is_clock_mode,
//     output reg is_ultrasonic_mode,
//     output reg is_temp_humid_mode,
//     output reg sw2,
//     output reg sw3,
//     output reg sw4,
//     output reg sw5
// );
//     // 상태 정의
//     parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
//     parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM - 스위치 조합 1000
//     parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch - 스위치 조합 1000 (버튼으로 전환)
//     parameter STATE_6 = 3'b110;  // Temperature Mode - 스위치 조합 0100
//     parameter STATE_7 = 3'b111;  // Humidity Mode - 스위치 조합 0100 (버튼으로 전환)

//     // sw[1:0]은 V16, V17에 해당함
//     wire sw0, sw1;
//     assign sw0 = sw[0]; // V17
//     assign sw1 = sw[1]; // V16

//     // 버튼 엣지 감지
//     reg btn_run_prev;
//     wire btn_run_edge;
//     assign btn_run_edge = btn_run & ~btn_run_prev;

//     // 스위치 상태 안정화
//     reg [3:0] sw_reg;
//     reg [3:0] sw_stable;
//     reg [19:0] debounce_counter;
//     parameter DEBOUNCE_LIMIT = 20'd100000; // 1ms @ 100MHz

//     // 상태 전환 제어 신호
//     reg [31:0] timeout_counter;
//     reg state_change_done;
//     reg state_transition_active;
//     reg [2:0] target_state;
//     parameter TIMEOUT_MAX = 32'd10000000;  // 100ms (100MHz 기준)

//     // 온습도 센서 모드 전환을 위한 추가 신호
//     reg temp_humid_toggle;
//     reg force_mode_change;
//     reg [31:0] force_transition_counter;
//     parameter FORCE_TIMEOUT = 32'd50000000;  // 500ms (100MHz 기준)

//     // Idle 상태 방지를 위한 타임아웃 카운터
//     reg [31:0] idle_timeout_counter;
//     parameter IDLE_TIMEOUT_MAX = 32'd100000000;  // 1초 (100MHz 기준)
//     reg idle_detected;

//     // 스위치 안정화 처리
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             sw_reg <= 4'b0000;
//             sw_stable <= 4'b0000;
//             debounce_counter <= 20'd0;
//         end else begin
//             sw_reg <= sw; // 현재 스위치 상태 저장

//             // 스위치 상태가 변했으면 디바운싱 시작
//             if (sw_reg != sw) begin
//                 debounce_counter <= 20'd0;
//             end else if (debounce_counter < DEBOUNCE_LIMIT) begin
//                 debounce_counter <= debounce_counter + 1;
//             end else begin
//                 sw_stable <= sw_reg; // 안정화된 스위치 상태 저장
//             end
//         end
//     end

//     // 버튼 엣지 감지 레지스터 업데이트
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             btn_run_prev <= 1'b0;
//         end else begin
//             btn_run_prev <= btn_run;
//         end
//     end

//     // 비동기 스위치 감지 로직 - 우선순위가 높은 전환 로직
//     wire ultrasonic_mode_req = sw_stable[3];
//     wire temp_humid_mode_req = !sw_stable[3] && sw_stable[2];

//     // 메인 FSM 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             // 리셋 시 스위치 상태에 따라 초기 상태 설정
//             if (sw[3]) begin
//                 // W17 스위치가 켜져 있으면 초음파 모드로 시작
//                 current_state <= STATE_4;
//                 is_clock_mode <= 1'b0;
//                 is_ultrasonic_mode <= 1'b1;
//                 is_temp_humid_mode <= 1'b0;
//                 sw2 <= 1'b1;
//                 sw3 <= 1'b0;
//                 sw4 <= 1'b1;
//                 sw5 <= 1'b0;
//                 target_state <= STATE_4;
//             end else if (sw[2]) begin
//                 // W16 스위치가 켜져 있으면 온습도 모드로 시작
//                 current_state <= STATE_6;
//                 is_clock_mode <= 1'b0;
//                 is_ultrasonic_mode <= 1'b0;
//                 is_temp_humid_mode <= 1'b1;
//                 sw2 <= 1'b0;
//                 sw3 <= 1'b1;
//                 sw4 <= 1'b1;
//                 sw5 <= 1'b1;
//                 target_state <= STATE_6;
//             end else begin
//                 current_state <= STATE_0;  // 초기 상태는 스톱워치 모드 (STATE_0)
//                 is_clock_mode <= 1'b0;
//                 is_ultrasonic_mode <= 1'b0;
//                 is_temp_humid_mode <= 1'b0;
//                 sw2 <= 1'b0;
//                 sw3 <= 1'b0;
//                 sw4 <= 1'b0;
//                 sw5 <= 1'b0;  // 스톱워치 모드 초기화
//                 target_state <= STATE_0;
//             end

//             timeout_counter <= 32'd0;
//             state_change_done <= 1'b0;
//             state_transition_active <= 1'b0;
//             temp_humid_toggle <= 1'b0;
//             force_mode_change <= 1'b0;
//             force_transition_counter <= 32'd0;
//             idle_timeout_counter <= 32'd0;
//             idle_detected <= 1'b0;
//         end else begin
//             // 우선순위 모드 전환 로직 - 가장 높은 우선순위
//             if (ultrasonic_mode_req) begin
//                 // W17 스위치가 켜져 있으면 초음파 모드로 즉시 전환
//                 current_state <= STATE_4;
//                 is_clock_mode <= 1'b0;
//                 is_ultrasonic_mode <= 1'b1;
//                 is_temp_humid_mode <= 1'b0;
//                 sw2 <= 1'b1;
//                 sw3 <= 1'b0;
//                 sw4 <= 1'b1;
//                 sw5 <= 1'b0;

//                 // 관련 카운터 초기화
//                 timeout_counter <= 32'd0;
//                 state_transition_active <= 1'b0;
//                 force_mode_change <= 1'b0;
//                 force_transition_counter <= 32'd0;
//                 idle_timeout_counter <= 32'd0;
//                 idle_detected <= 1'b0;
//             end else if (temp_humid_mode_req) begin
//                 // W16 스위치가 켜져 있으면 온습도 모드로 즉시 전환
//                 current_state <= STATE_6;
//                 is_clock_mode <= 1'b0;
//                 is_ultrasonic_mode <= 1'b0;
//                 is_temp_humid_mode <= 1'b1;
//                 sw2 <= 1'b0;
//                 sw3 <= 1'b1;
//                 sw4 <= 1'b1;
//                 sw5 <= 1'b1;

//                 // 관련 카운터 초기화
//                 timeout_counter <= 32'd0;
//                 state_transition_active <= 1'b0;
//                 force_mode_change <= 1'b0;
//                 force_transition_counter <= 32'd0;
//                 idle_timeout_counter <= 32'd0;
//                 idle_detected <= 1'b0;
//             end else begin
//                 // 강제 전환 타이머 (모드 전환이 안될 때 사용)
//                 if (force_mode_change) begin
//                     force_transition_counter <= force_transition_counter + 1;
//                     if (force_transition_counter >= FORCE_TIMEOUT) begin
//                         // 강제 전환 타임아웃 발생 - 타겟 상태로 즉시 전환
//                         current_state <= target_state;
//                         state_transition_active <= 1'b0;
//                         state_change_done <= 1'b1;
//                         force_mode_change <= 1'b0;
//                         force_transition_counter <= 32'd0;

//                         // 모드 플래그 즉시 업데이트
//                         case (target_state)
//                             STATE_0, STATE_1: begin  // 스톱워치 모드
//                                 is_clock_mode <= 1'b0;
//                                 is_ultrasonic_mode <= 1'b0;
//                                 is_temp_humid_mode <= 1'b0;
//                             end
//                             STATE_2, STATE_3: begin  // 시계 모드
//                                 is_clock_mode <= 1'b1;
//                                 is_ultrasonic_mode <= 1'b0;
//                                 is_temp_humid_mode <= 1'b0;
//                             end
//                             STATE_4, STATE_5: begin  // 초음파 모드
//                                 is_clock_mode <= 1'b0;
//                                 is_ultrasonic_mode <= 1'b1;
//                                 is_temp_humid_mode <= 1'b0;
//                             end
//                             STATE_6, STATE_7: begin  // 온습도 모드
//                                 is_clock_mode <= 1'b0;
//                                 is_ultrasonic_mode <= 1'b0;
//                                 is_temp_humid_mode <= 1'b1;
//                             end
//                         endcase
//                     end
//                 end else begin
//                     force_transition_counter <= 32'd0;
//                 end

//                 // 일반 타임아웃 카운터 관리
//                 if (state_transition_active) begin
//                     timeout_counter <= timeout_counter + 1;
//                     if (timeout_counter >= TIMEOUT_MAX) begin
//                         // 타임아웃 발생 - 상태 전환 강제 완료
//                         current_state <= target_state;
//                         state_transition_active <= 1'b0;
//                         state_change_done <= 1'b1;
//                         timeout_counter <= 32'd0;
//                     end
//                 end else begin
//                     timeout_counter <= 32'd0;
//                 end

//                 // done 신호 리셋
//                 if (state_change_done && !state_transition_active && !force_mode_change) begin
//                     state_change_done <= 1'b0;
//                 end

//                 // Idle 상태 감지 및 처리
//                 if (current_state == STATE_0 && !state_transition_active && !force_mode_change) begin
//                     idle_timeout_counter <= idle_timeout_counter + 1;
//                     if (idle_timeout_counter >= IDLE_TIMEOUT_MAX) begin
//                         idle_detected <= 1'b1;
//                         // Idle 상태가 오래 지속되면 강제로 초기화
//                         if (sw_stable[3]) begin
//                             // 초음파 모드로 전환 시도 중이라면 강제 전환
//                             current_state <= STATE_4;
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b1;
//                             is_temp_humid_mode <= 1'b0;
//                             sw2 <= 1'b1;
//                             sw3 <= 1'b0;
//                             sw4 <= 1'b1;
//                             sw5 <= 1'b0;
//                             idle_timeout_counter <= 32'd0;
//                             idle_detected <= 1'b0;
//                         end
//                     end
//                 end else if (current_state != STATE_0) begin
//                     // STATE_0 아닌 다른 상태로 정상 전환되면 카운터 리셋
//                     idle_timeout_counter <= 32'd0;
//                     idle_detected <= 1'b0;
//                 end

//                 // 스위치 입력에 따른 모드 전환 - 일반 FSM 로직
//                 if (!state_transition_active && !force_mode_change) begin
//                     // FSM 다이어그램에 따른 상태 전환 로직
//                     case (current_state)
//                         STATE_0: begin  // 스톱워치 Msec:Sec
//                             if (sw0 == 1'b1 && sw1 == 1'b0) begin  // SW[0]=1, SW[1]=0
//                                 target_state <= STATE_1;  // 스톱워치 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_2;  // 시계 Sec:Msec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_1: begin  // 스톱워치 Hour:Min
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin  // SW[0]=0, SW[1]=0
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_3;  // 시계 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_2: begin  // 시계 Sec:Msec
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin  // SW[0]=0, SW[1]=0
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b1 && sw1 == 1'b1) begin  // SW[0]=1, SW[1]=1
//                                 target_state <= STATE_3;  // 시계 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_3: begin  // 시계 Hour:Min
//                             if (sw0 == 1'b1 && sw1 == 1'b0) begin  // SW[0]=1, SW[1]=0
//                                 target_state <= STATE_1;  // 스톱워치 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_2;  // 시계 Sec:Msec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         default: begin
//                             // 다른 상태에서 시계/스톱워치 모드로 돌아올 때
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end
//                     endcase

//                     // 버튼 입력에 따른 상태 전환 (모드 내)
//                     if (btn_run_edge) begin
//                         case (current_state)
//                             STATE_0: begin
//                                 target_state <= STATE_1;  // 스톱워치 Msec:Sec -> Hour:Min
//                                 state_transition_active <= 1'b1;
//                             end
//                             STATE_1: begin
//                                 target_state <= STATE_0;  // 스톱워치 Hour:Min -> Msec:Sec
//                                 state_transition_active <= 1'b1;
//                             end
//                             STATE_2: begin
//                                 target_state <= STATE_3;  // 시계 Sec:Msec -> Hour:Min
//                                 state_transition_active <= 1'b1;
//                             end
//                             STATE_3: begin
//                                 target_state <= STATE_2;  // 시계 Hour:Min -> Sec:Msec
//                                 state_transition_active <= 1'b1;
//                             end
//                             STATE_4: begin
//                                 target_state <= STATE_5;  // 초음파 CM -> Inch
//                                 state_transition_active <= 1'b1;
//                             end
//                             STATE_5: begin
//                                 target_state <= STATE_4;  // 초음파 Inch -> CM
//                                 state_transition_active <= 1'b1;
//                             end
//                             STATE_6: begin
//                                 // 온도 -> 습도 (직접 상태 변경)
//                                 current_state <= STATE_7;
//                                 temp_humid_toggle <= ~temp_humid_toggle;
//                             end
//                             STATE_7: begin
//                                 // 습도 -> 온도 (직접 상태 변경)
//                                 current_state <= STATE_6;
//                                 temp_humid_toggle <= ~temp_humid_toggle;
//                             end
//                             default: begin
//                                 // 기본값 처리
//                             end
//                         endcase
//                     end
//                 end

//                 // 상태 변경 진행 중이고 아직 타임아웃 발생 전이면 즉시 상태 전환 허용
//                 if (state_transition_active && timeout_counter < TIMEOUT_MAX/2) begin
//                     if (!state_change_done) begin
//                         current_state <= target_state;
//                         state_change_done <= 1'b1;
//                         state_transition_active <= 1'b0;
//                         timeout_counter <= 32'd0;
//                     end
//                 end

//                 // 상태에 따른 모드 플래그와 출력 설정
//                 case (current_state)
//                     STATE_0, STATE_1: begin  // 스톱워치 모드
//                         is_clock_mode <= 1'b0;
//                         is_ultrasonic_mode <= 1'b0;
//                         is_temp_humid_mode <= 1'b0;
//                         sw2 <= 1'b0;
//                         sw3 <= 1'b0;
//                         sw4 <= 1'b0;
//                         sw5 <= 1'b0;
//                     end

//                     STATE_2, STATE_3: begin  // 시계 모드
//                         is_clock_mode <= 1'b1;
//                         is_ultrasonic_mode <= 1'b0;
//                         is_temp_humid_mode <= 1'b0;
//                         sw2 <= 1'b0;
//                         sw3 <= 1'b0;
//                         sw4 <= 1'b0;
//                         sw5 <= 1'b1;
//                     end

//                     STATE_4, STATE_5: begin  // 초음파 모드
//                         is_clock_mode <= 1'b0;
//                         is_ultrasonic_mode <= 1'b1;
//                         is_temp_humid_mode <= 1'b0;
//                         sw2 <= 1'b1;
//                         sw3 <= 1'b0;
//                         sw4 <= 1'b1;
//                         sw5 <= 1'b0;
//                     end

//                     STATE_6, STATE_7: begin  // 온습도 모드
//                         is_clock_mode <= 1'b0;
//                         is_ultrasonic_mode <= 1'b0;
//                         is_temp_humid_mode <= 1'b1;
//                         sw2 <= 1'b0;
//                         sw3 <= 1'b1;
//                         sw4 <= 1'b1;
//                         sw5 <= 1'b1;
//                     end

//                     default: begin
//                         // 기본값 설정
//                         is_clock_mode <= 1'b0;
//                         is_ultrasonic_mode <= 1'b0;
//                         is_temp_humid_mode <= 1'b0;
//                         sw2 <= 1'b0;
//                         sw3 <= 1'b0;
//                         sw4 <= 1'b0;
//                         sw5 <= 1'b0;
//                     end
//                 endcase
//             end
//         end
//     end
// endmodule
// module fsm_controller (
//     input clk,
//     input reset,
//     input [3:0] sw,        // 4개 스위치로 확장 [W17, W16, V16, V17]
//     input btn_run,
//     input sw_mode_in,
//     output reg [2:0] current_state,
//     output reg is_clock_mode,
//     output reg is_ultrasonic_mode,
//     output reg is_temp_humid_mode,
//     output reg sw2,
//     output reg sw3,
//     output reg sw4,
//     output reg sw5
// );
//     // 상태 정의
//     parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
//     parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM - 스위치 조합 1000
//     parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch - 스위치 조합 1000 (버튼으로 전환)
//     parameter STATE_6 = 3'b110;  // Temperature Mode - 스위치 조합 0100
//     parameter STATE_7 = 3'b111;  // Humidity Mode - 스위치 조합 0100 (버튼으로 전환)

//     // sw[1:0]은 V16, V17에 해당함
//     wire sw0, sw1;
//     assign sw0 = sw[0]; // V17
//     assign sw1 = sw[1]; // V16

//     // 버튼 엣지 감지
//     reg btn_run_prev;
//     wire btn_run_edge;
//     assign btn_run_edge = btn_run & ~btn_run_prev;

//     // 상태 전환 제어 신호
//     reg [31:0] timeout_counter;
//     reg state_change_done;
//     reg state_transition_active;
//     reg [2:0] target_state;
//     parameter TIMEOUT_MAX = 32'd10000000;  // 100ms (100MHz 기준)

//     // 온습도 센서 모드 전환을 위한 추가 신호
//     reg temp_humid_toggle;
//     reg force_mode_change;
//     reg [31:0] force_transition_counter;
//     parameter FORCE_TIMEOUT = 32'd50000000;  // 500ms (100MHz 기준)

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             btn_run_prev <= 1'b0;
//         end else begin
//             btn_run_prev <= btn_run;
//         end
//     end

//     // 메인 FSM 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= STATE_0;  // 초기 상태는 스톱워치 모드 (STATE_0)
//             is_clock_mode <= 1'b0;
//             is_ultrasonic_mode <= 1'b0;
//             is_temp_humid_mode <= 1'b0;
//             sw2 <= 1'b0;
//             sw3 <= 1'b0;
//             sw4 <= 1'b0;
//             sw5 <= 1'b0;  // 스톱워치 모드 초기화
//             timeout_counter <= 32'd0;
//             state_change_done <= 1'b0;
//             state_transition_active <= 1'b0;
//             target_state <= STATE_0;
//             temp_humid_toggle <= 1'b0;
//             force_mode_change <= 1'b0;
//             force_transition_counter <= 32'd0;
//         end else begin
//             // 강제 전환 타이머 (모드 전환이 안될 때 사용)
//             if (force_mode_change) begin
//                 force_transition_counter <= force_transition_counter + 1;
//                 if (force_transition_counter >= FORCE_TIMEOUT) begin
//                     // 강제 전환 타임아웃 발생 - 타겟 상태로 즉시 전환
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     force_mode_change <= 1'b0;
//                     force_transition_counter <= 32'd0;

//                     // 모드 플래그 즉시 업데이트
//                     case (target_state)
//                         STATE_0, STATE_1: begin  // 스톱워치 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_2, STATE_3: begin  // 시계 모드
//                             is_clock_mode <= 1'b1;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_4, STATE_5: begin  // 초음파 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b1;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_6, STATE_7: begin  // 온습도 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b1;
//                         end
//                     endcase
//                 end
//             end else begin
//                 force_transition_counter <= 32'd0;
//             end

//             // 일반 타임아웃 카운터 관리
//             if (state_transition_active) begin
//                 timeout_counter <= timeout_counter + 1;
//                 if (timeout_counter >= TIMEOUT_MAX) begin
//                     // 타임아웃 발생 - 상태 전환 강제 완료
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     timeout_counter <= 32'd0;
//                 end
//             end else begin
//                 timeout_counter <= 32'd0;
//             end

//             // done 신호 리셋
//             if (state_change_done && !state_transition_active && !force_mode_change) begin
//                 state_change_done <= 1'b0;
//             end

//             // 스위치 입력에 따른 모드 전환
//             if (!state_transition_active && !force_mode_change) begin
//                 // W17 (sw[3])이 1이면 초음파 모드
//                 if (sw[3] == 1'b1) begin  // W17=1 (1xxx) - 초음파 모드
//                     target_state <= STATE_4;
//                     if ((current_state == STATE_0) || (current_state == STATE_1) || 
//                         (current_state == STATE_6) || (current_state == STATE_7)) begin
//                         // STATE_0, STATE_1(스톱워치), STATE_6, STATE_7(온습도)에서 강제 전환
//                         force_mode_change <= 1'b1;
//                         force_transition_counter <= 32'd0;
//                     end else if ((current_state != STATE_4) && (current_state != STATE_5)) begin
//                         state_transition_active <= 1'b1;
//                     end
//                 end
//                 // W16 (sw[2])이 1이면 온습도 모드
//                 else if (sw[2] == 1'b1) begin  // W16=1 (01xx) - 온습도 모드
//                     target_state <= STATE_6;
//                     if ((current_state == STATE_0) || (current_state == STATE_1)) begin
//                         // STATE_0, STATE_1(스톱워치)에서도 강제 전환
//                         force_mode_change <= 1'b1;
//                         force_transition_counter <= 32'd0;
//                     end else if ((current_state != STATE_6) && (current_state != STATE_7)) begin
//                         state_transition_active <= 1'b1;
//                     end
//                 end
//                 // W17=0, W16=0이면 시계/스톱워치 모드
//                 else begin  // W17=0, W16=0 (00xx) - 시계/스톱워치 모드
//                     // FSM 다이어그램에 따른 상태 전환 로직
//                     case (current_state)
//                         STATE_0: begin  // 스톱워치 Msec:Sec
//                             if (sw0 == 1'b1 && sw1 == 1'b0) begin  // SW[0]=1, SW[1]=0
//                                 target_state <= STATE_1;  // 스톱워치 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_2;  // 시계 Sec:Msec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_1: begin  // 스톱워치 Hour:Min
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin  // SW[0]=0, SW[1]=0
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_3;  // 시계 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_2: begin  // 시계 Sec:Msec
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin  // SW[0]=0, SW[1]=0
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b1 && sw1 == 1'b1) begin  // SW[0]=1, SW[1]=1
//                                 target_state <= STATE_3;  // 시계 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_3: begin  // 시계 Hour:Min
//                             if (sw0 == 1'b1 && sw1 == 1'b0) begin  // SW[0]=1, SW[1]=0
//                                 target_state <= STATE_1;  // 스톱워치 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_2;  // 시계 Sec:Msec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         default: begin
//                             // 다른 상태에서 시계/스톱워치 모드로 돌아올 때
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end
//                     endcase
//                 end

//                 // 버튼 입력에 따른 상태 전환 (모드 내)
//                 if (btn_run_edge) begin
//                     case (current_state)
//                         STATE_0: begin
//                             target_state <= STATE_1;  // 스톱워치 Msec:Sec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_1: begin
//                             target_state <= STATE_0;  // 스톱워치 Hour:Min -> Msec:Sec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_2: begin
//                             target_state <= STATE_3;  // 시계 Sec:Msec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_3: begin
//                             target_state <= STATE_2;  // 시계 Hour:Min -> Sec:Msec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_4: begin
//                             target_state <= STATE_5;  // 초음파 CM -> Inch
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_5: begin
//                             target_state <= STATE_4;  // 초음파 Inch -> CM
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_6: begin
//                             // 온도 -> 습도 (직접 상태 변경)
//                             current_state <= STATE_7;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         STATE_7: begin
//                             // 습도 -> 온도 (직접 상태 변경)
//                             current_state <= STATE_6;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         default: begin
//                             // 기본값 처리
//                         end
//                     endcase
//                 end
//             end

//             // 상태 변경 진행 중이고 아직 타임아웃 발생 전이면 즉시 상태 전환 허용
//             if (state_transition_active && timeout_counter < TIMEOUT_MAX/2) begin
//                 if (!state_change_done) begin
//                     current_state <= target_state;
//                     state_change_done <= 1'b1;
//                     state_transition_active <= 1'b0;
//                     timeout_counter <= 32'd0;
//                 end
//             end

//             // 상태에 따른 모드 플래그와 출력 설정
//             case (current_state)
//                 STATE_0, STATE_1: begin  // 스톱워치 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_2, STATE_3: begin  // 시계 모드
//                     is_clock_mode <= 1'b1;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b1;
//                 end

//                 STATE_4, STATE_5: begin  // 초음파 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b1;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b1;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_6, STATE_7: begin  // 온습도 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b1;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b1;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b1;
//                 end

//                 default: begin
//                     // 기본값 설정
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b0;
//                 end
//             endcase
//         end
//     end
// endmodule



// module fsm_controller (
//     input clk,
//     input reset,
//     input [3:0] sw,        // 4개 스위치로 확장 [W17, W16, V16, V17]
//     input btn_run,
//     input sw_mode_in,
//     output reg [2:0] current_state,
//     output reg is_clock_mode,
//     output reg is_ultrasonic_mode,
//     output reg is_temp_humid_mode,
//     output reg sw2,
//     output reg sw3,
//     output reg sw4,
//     output reg sw5
// );
//     // 상태 정의
//     parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
//     parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM - 스위치 조합 1000
//     parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch - 스위치 조합 1000 (버튼으로 전환)
//     parameter STATE_6 = 3'b110;  // Temperature Mode - 스위치 조합 0100
//     parameter STATE_7 = 3'b111;  // Humidity Mode - 스위치 조합 0100 (버튼으로 전환)

//     // sw[1:0]은 V16, V17에 해당함
//     wire sw0, sw1;
//     assign sw0 = sw[0]; // V17
//     assign sw1 = sw[1]; // V16

//     // 버튼 엣지 감지
//     reg btn_run_prev;
//     wire btn_run_edge;
//     assign btn_run_edge = btn_run & ~btn_run_prev;

//     // 상태 전환 제어 신호
//     reg [31:0] timeout_counter;
//     reg state_change_done;
//     reg state_transition_active;
//     reg [2:0] target_state;
//     parameter TIMEOUT_MAX = 32'd10000000;  // 100ms (100MHz 기준)

//     // 온습도 센서 모드 전환을 위한 추가 신호
//     reg temp_humid_toggle;
//     reg force_mode_change;
//     reg [31:0] force_transition_counter;
//     parameter FORCE_TIMEOUT = 32'd50000000;  // 500ms (100MHz 기준)

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             btn_run_prev <= 1'b0;
//         end else begin
//             btn_run_prev <= btn_run;
//         end
//     end

//     // 메인 FSM 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= STATE_0;  // 초기 상태는 스톱워치 모드 (STATE_0)
//             is_clock_mode <= 1'b0;
//             is_ultrasonic_mode <= 1'b0;
//             is_temp_humid_mode <= 1'b0;
//             sw2 <= 1'b0;
//             sw3 <= 1'b0;
//             sw4 <= 1'b0;
//             sw5 <= 1'b0;  // 스톱워치 모드 초기화
//             timeout_counter <= 32'd0;
//             state_change_done <= 1'b0;
//             state_transition_active <= 1'b0;
//             target_state <= STATE_0;
//             temp_humid_toggle <= 1'b0;
//             force_mode_change <= 1'b0;
//             force_transition_counter <= 32'd0;
//         end else begin
//             // 강제 전환 타이머 (모드 전환이 안될 때 사용)
//             if (force_mode_change) begin
//                 force_transition_counter <= force_transition_counter + 1;
//                 if (force_transition_counter >= FORCE_TIMEOUT) begin
//                     // 강제 전환 타임아웃 발생 - 타겟 상태로 즉시 전환
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     force_mode_change <= 1'b0;
//                     force_transition_counter <= 32'd0;

//                     // 모드 플래그 즉시 업데이트
//                     case (target_state)
//                         STATE_0, STATE_1: begin  // 스톱워치 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_2, STATE_3: begin  // 시계 모드
//                             is_clock_mode <= 1'b1;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_4, STATE_5: begin  // 초음파 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b1;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_6, STATE_7: begin  // 온습도 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b1;
//                         end
//                     endcase
//                 end
//             end else begin
//                 force_transition_counter <= 32'd0;
//             end

//             // 일반 타임아웃 카운터 관리
//             if (state_transition_active) begin
//                 timeout_counter <= timeout_counter + 1;
//                 if (timeout_counter >= TIMEOUT_MAX) begin
//                     // 타임아웃 발생 - 상태 전환 강제 완료
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     timeout_counter <= 32'd0;
//                 end
//             end else begin
//                 timeout_counter <= 32'd0;
//             end

//             // done 신호 리셋
//             if (state_change_done && !state_transition_active && !force_mode_change) begin
//                 state_change_done <= 1'b0;
//             end

//             // 스위치 입력에 따른 모드 전환
//             if (!state_transition_active && !force_mode_change) begin
//                 // 상위 스위치 [W17, W16]로 주 모드 결정
//                 if (sw[3:2] == 2'b10) begin  // W17=1, W16=0 (1000) - 초음파 모드
//                     target_state <= STATE_4;
//                     if ((current_state == STATE_6) || (current_state == STATE_7)) begin
//                         force_mode_change <= 1'b1;
//                         force_transition_counter <= 32'd0;
//                     end else if ((current_state != STATE_4) && (current_state != STATE_5)) begin
//                         state_transition_active <= 1'b1;
//                     end
//                 end
//                 else if (sw[3:2] == 2'b01) begin  // W17=0, W16=1 (0100) - 온습도 모드
//                     target_state <= STATE_6;
//                     if ((current_state != STATE_6) && (current_state != STATE_7)) begin
//                         state_transition_active <= 1'b1;
//                     end
//                 end
//                 else if (sw[3:2] == 2'b00) begin  // W17=0, W16=0 - 시계/스톱워치 모드
//                     // FSM 다이어그램에 따른 상태 전환 로직
//                     case (current_state)
//                         STATE_0: begin  // 스톱워치 Msec:Sec
//                             if (sw0 == 1'b1 && sw1 == 1'b0) begin  // SW[0]=1, SW[1]=0
//                                 target_state <= STATE_1;  // 스톱워치 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_2;  // 시계 Sec:Msec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_1: begin  // 스톱워치 Hour:Min
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin  // SW[0]=0, SW[1]=0
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_3;  // 시계 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_2: begin  // 시계 Sec:Msec
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin  // SW[0]=0, SW[1]=0
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b1 && sw1 == 1'b1) begin  // SW[0]=1, SW[1]=1
//                                 target_state <= STATE_3;  // 시계 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         STATE_3: begin  // 시계 Hour:Min
//                             if (sw0 == 1'b1 && sw1 == 1'b0) begin  // SW[0]=1, SW[1]=0
//                                 target_state <= STATE_1;  // 스톱워치 Hour:Min으로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                             else if (sw0 == 1'b0 && sw1 == 1'b1) begin  // SW[0]=0, SW[1]=1
//                                 target_state <= STATE_2;  // 시계 Sec:Msec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end

//                         default: begin
//                             // 다른 상태에서 시계/스톱워치 모드로 돌아올 때
//                             if (sw0 == 1'b0 && sw1 == 1'b0) begin
//                                 target_state <= STATE_0;  // 스톱워치 Msec:Sec로 전환
//                                 state_transition_active <= 1'b1;
//                             end
//                         end
//                     endcase
//                 end

//                 // 버튼 입력에 따른 상태 전환 (모드 내)
//                 if (btn_run_edge) begin
//                     case (current_state)
//                         STATE_0: begin
//                             target_state <= STATE_1;  // 스톱워치 Msec:Sec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_1: begin
//                             target_state <= STATE_0;  // 스톱워치 Hour:Min -> Msec:Sec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_2: begin
//                             target_state <= STATE_3;  // 시계 Sec:Msec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_3: begin
//                             target_state <= STATE_2;  // 시계 Hour:Min -> Sec:Msec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_4: begin
//                             target_state <= STATE_5;  // 초음파 CM -> Inch
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_5: begin
//                             target_state <= STATE_4;  // 초음파 Inch -> CM
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_6: begin
//                             // 온도 -> 습도 (직접 상태 변경)
//                             current_state <= STATE_7;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         STATE_7: begin
//                             // 습도 -> 온도 (직접 상태 변경)
//                             current_state <= STATE_6;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         default: begin
//                             // 기본값 처리
//                         end
//                     endcase
//                 end
//             end

//             // 상태 변경 진행 중이고 아직 타임아웃 발생 전이면 즉시 상태 전환 허용
//             if (state_transition_active && timeout_counter < TIMEOUT_MAX/2) begin
//                 if (!state_change_done) begin
//                     current_state <= target_state;
//                     state_change_done <= 1'b1;
//                     state_transition_active <= 1'b0;
//                     timeout_counter <= 32'd0;
//                 end
//             end

//             // 상태에 따른 모드 플래그와 출력 설정
//             case (current_state)
//                 STATE_0, STATE_1: begin  // 스톱워치 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_2, STATE_3: begin  // 시계 모드
//                     is_clock_mode <= 1'b1;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b1;
//                 end

//                 STATE_4, STATE_5: begin  // 초음파 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b1;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b1;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_6, STATE_7: begin  // 온습도 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b1;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b1;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b1;
//                 end

//                 default: begin
//                     // 기본값 설정
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b0;
//                 end
//             endcase
//         end
//     end
// endmodule
// module fsm_controller (
//     input clk,
//     input reset,
//     input [3:0] sw,  // 4개 스위치로 확장 [W17, W16, V16, V17]
//     input btn_run,
//     input sw_mode_in,
//     output reg [2:0] current_state,
//     output reg is_clock_mode,
//     output reg is_ultrasonic_mode,
//     output reg is_temp_humid_mode,
//     output reg sw2,
//     output reg sw3,
//     output reg sw4,
//     output reg sw5
// );
//     // 상태 정의
//     parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
//     parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
//     parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch
//     parameter STATE_6 = 3'b110;  // Temperature Mode
//     parameter STATE_7 = 3'b111;  // Humidity Mode

//     // 버튼 엣지 감지
//     reg  btn_run_prev;
//     wire btn_run_edge;
//     assign btn_run_edge = btn_run & ~btn_run_prev;

//     // 상태 전환 제어 신호
//     reg [31:0] timeout_counter;
//     reg state_change_done;
//     reg state_transition_active;
//     reg [2:0] target_state;
//     parameter TIMEOUT_MAX = 32'd10000000;  // 100ms (100MHz 기준)

//     // 온습도 센서 모드 전환을 위한 추가 신호
//     reg temp_humid_toggle;
//     reg force_mode_change;
//     reg [31:0] force_transition_counter;
//     parameter FORCE_TIMEOUT = 32'd50000000;  // 500ms (100MHz 기준)

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             btn_run_prev <= 1'b0;
//         end else begin
//             btn_run_prev <= btn_run;
//         end
//     end

//     // 메인 FSM-모드 및 스위치 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= STATE_2;  // 기본 시계 모드로 시작
//             is_clock_mode <= 1'b1;
//             is_ultrasonic_mode <= 1'b0;
//             is_temp_humid_mode <= 1'b0;
//             sw2 <= 1'b0;
//             sw3 <= 1'b0;
//             sw4 <= 1'b0;
//             sw5 <= 1'b1;  // 시계 모드 초기화
//             timeout_counter <= 32'd0;
//             state_change_done <= 1'b0;
//             state_transition_active <= 1'b0;
//             target_state <= STATE_2;
//             temp_humid_toggle <= 1'b0;
//             force_mode_change <= 1'b0;
//             force_transition_counter <= 32'd0;
//         end else begin
//             // 강제 전환 타이머 (모드 전환이 안될 때 사용)
//             if (force_mode_change) begin
//                 force_transition_counter <= force_transition_counter + 1;
//                 if (force_transition_counter >= FORCE_TIMEOUT) begin
//                     // 강제 전환 타임아웃 발생 - 타겟 상태로 즉시 전환
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     force_mode_change <= 1'b0;
//                     force_transition_counter <= 32'd0;

//                     // 모드 플래그 즉시 업데이트
//                     case (target_state)
//                         STATE_0, STATE_1: begin  // 스톱워치 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_2, STATE_3: begin  // 시계 모드
//                             is_clock_mode <= 1'b1;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_4, STATE_5: begin  // 초음파 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b1;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_6, STATE_7: begin  // 온습도 모드
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b1;
//                         end
//                     endcase
//                 end
//             end else begin
//                 force_transition_counter <= 32'd0;
//             end

//             // 일반 타임아웃 카운터 관리
//             if (state_transition_active) begin
//                 timeout_counter <= timeout_counter + 1;
//                 if (timeout_counter >= TIMEOUT_MAX) begin
//                     // 타임아웃 발생 - 상태 전환 강제 완료
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     timeout_counter <= 32'd0;
//                 end
//             end else begin
//                 timeout_counter <= 32'd0;
//             end

//             // done 신호 리셋
//             if (state_change_done && !state_transition_active && !force_mode_change) begin
//                 state_change_done <= 1'b0;
//             end

//             // 스위치 입력에 따른 모드 전환 - 스위치 매핑 수정
//             if (!state_transition_active && !force_mode_change) begin
//                 // 상위 2비트(W17, W16)로 주 모드 결정
//                 case (sw[3:2])
//                     2'b10: begin  // W17=1, W16=0 (1000) - 초음파 모드
//                         target_state <= STATE_4;
//                         if ((current_state == STATE_6) || (current_state == STATE_7)) begin
//                             force_mode_change <= 1'b1;
//                             force_transition_counter <= 32'd0;
//                         end else if ((current_state != STATE_4) && (current_state != STATE_5)) begin
//                             state_transition_active <= 1'b1;
//                         end
//                     end

//                     2'b01: begin  // W17=0, W16=1 (0100) - 온습도 모드
//                         target_state <= STATE_6;
//                         if ((current_state != STATE_6) && (current_state != STATE_7)) begin
//                             state_transition_active <= 1'b1;
//                         end
//                     end

//                     2'b00: begin  // W17=0, W16=0 - 시계/스톱워치 모드는 하위 2비트로 결정
//                         // 하위 2비트(V16, V17)로 시계/스톱워치 모드 결정
//                         case (sw[1:0])
//                             2'b00: begin  // 시계 모드 (SW[0]=0, SW[1]=0)
//                                 target_state <= STATE_2;
//                                 if ((current_state == STATE_6) || (current_state == STATE_7)) begin
//                                     force_mode_change <= 1'b1;
//                                     force_transition_counter <= 32'd0;
//                                 end else if ((current_state != STATE_2) && (current_state != STATE_3)) begin
//                                     state_transition_active <= 1'b1;
//                                 end
//                             end

//                             2'b01, 2'b10, 2'b11: begin  // 스톱워치 모드 (SW[0]=1 또는 SW[1]=1)
//                                 target_state <= STATE_0;
//                                 if ((current_state == STATE_6) || (current_state == STATE_7)) begin
//                                     force_mode_change <= 1'b1;
//                                     force_transition_counter <= 32'd0;
//                                 end else if ((current_state != STATE_0) && (current_state != STATE_1)) begin
//                                     state_transition_active <= 1'b1;
//                                 end
//                             end
//                         endcase
//                     end

//                     default: begin
//                         // 다른 스위치 조합은 무시
//                     end
//                 endcase

//                 // 버튼 입력에 따른 상태 전환 (모드 내)
//                 if (btn_run_edge) begin
//                     case (current_state)
//                         STATE_0: begin
//                             target_state <= STATE_1;  // 스톱워치 Msec:Sec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_1: begin
//                             target_state <= STATE_0;  // 스톱워치 Hour:Min -> Msec:Sec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_2: begin
//                             target_state <= STATE_3;  // 시계 Sec:Msec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_3: begin
//                             target_state <= STATE_2;  // 시계 Hour:Min -> Sec:Msec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_4: begin
//                             target_state <= STATE_5;  // 초음파 CM -> Inch
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_5: begin
//                             target_state <= STATE_4;  // 초음파 Inch -> CM
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_6: begin
//                             // 온도 -> 습도 (직접 상태 변경)
//                             current_state <= STATE_7;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         STATE_7: begin
//                             // 습도 -> 온도 (직접 상태 변경)
//                             current_state <= STATE_6;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         default: begin
//                             // 기본값 처리
//                         end
//                     endcase
//                 end
//             end

//             // 상태 변경 진행 중이고 아직 타임아웃 발생 전이면 즉시 상태 전환 허용
//             if (state_transition_active && timeout_counter < TIMEOUT_MAX/2) begin
//                 if (!state_change_done) begin
//                     current_state <= target_state;
//                     state_change_done <= 1'b1;
//                     state_transition_active <= 1'b0;
//                     timeout_counter <= 32'd0;
//                 end
//             end

//             // 상태에 따른 모드 플래그와 출력 설정
//             case (current_state)
//                 STATE_0, STATE_1: begin  // 스톱워치 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_2, STATE_3: begin  // 시계 모드
//                     is_clock_mode <= 1'b1;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b1;
//                 end

//                 STATE_4, STATE_5: begin  // 초음파 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b1;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b1;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_6, STATE_7: begin  // 온습도 모드
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b1;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b1;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b1;
//                 end

//                 default: begin
//                     // 기본값 설정
//                     is_clock_mode <= 1'b1;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b1;
//                 end
//             endcase
//         end
//     end
// endmodule

// // module fsm_controller (
// //     input clk,
// //     input reset,
// //     input [2:0] sw,
// //     input btn_run,
// //     input sw_mode_in,
// //     output reg [2:0] current_state,
// //     output reg is_clock_mode,
// //     output reg is_ultrasonic_mode,
// //     output reg is_temp_humid_mode,
//     output reg sw2,
//     output reg sw3,
//     output reg sw4,
//     output reg sw5
// );
//     // ���� ����
//     parameter STATE_0 = 3'b000;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 3'b001;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 3'b010;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 3'b011;  // Clock Mode Hour:Min
//     parameter STATE_4 = 3'b100;  // Ultrasonic Mode CM
//     parameter STATE_5 = 3'b101;  // Ultrasonic Mode Inch
//     parameter STATE_6 = 3'b110;  // Temperature Mode
//     parameter STATE_7 = 3'b111;  // Humidity Mode

//     // ��ư ���� ����
//     reg btn_run_prev;
//     wire btn_run_edge;
//     assign btn_run_edge = btn_run & ~btn_run_prev;

//     // ���� ��ȯ ���� ��ȣ
//     reg [31:0] timeout_counter;
//     reg state_change_done;
//     reg state_transition_active;
//     reg [2:0] target_state;
//     parameter TIMEOUT_MAX = 32'd10000000;  // 100ms (100MHz ����)

//     // �½��� ���� ��� ��ȯ�� ���� �߰� ��ȣ
//     reg temp_humid_toggle;
//     reg force_mode_change;
//     reg [31:0] force_transition_counter;
//     parameter FORCE_TIMEOUT = 32'd50000000;  // 500ms (100MHz ����)

//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             btn_run_prev <= 1'b0;
//         end else begin
//             btn_run_prev <= btn_run;
//         end
//     end

//     // ���� FSM ����
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= STATE_2;  // �⺻ �ð� ���� ����
//             is_clock_mode <= 1'b1;
//             is_ultrasonic_mode <= 1'b0;
//             is_temp_humid_mode <= 1'b0;
//             sw2 <= 1'b0;
//             sw3 <= 1'b0;
//             sw4 <= 1'b0;
//             sw5 <= 1'b1;  // �ð� ��� �ʱ�ȭ
//             timeout_counter <= 32'd0;
//             state_change_done <= 1'b0;
//             state_transition_active <= 1'b0;
//             target_state <= STATE_2;
//             temp_humid_toggle <= 1'b0;
//             force_mode_change <= 1'b0;
//             force_transition_counter <= 32'd0;
//         end else begin
//             // ���� ��ȯ Ÿ�̸� (��� ��ȯ�� �ȵ� �� ���)
//             if (force_mode_change) begin
//                 force_transition_counter <= force_transition_counter + 1;
//                 if (force_transition_counter >= FORCE_TIMEOUT) begin
//                     // ���� ��ȯ Ÿ�Ӿƿ� �߻� - Ÿ�� ���·� ��� ��ȯ
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     force_mode_change <= 1'b0;
//                     force_transition_counter <= 32'd0;

//                     // ��� �÷��� ��� ������Ʈ
//                     case (target_state)
//                         STATE_0, STATE_1: begin  // �����ġ ���
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_2, STATE_3: begin  // �ð� ���
//                             is_clock_mode <= 1'b1;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_4, STATE_5: begin  // ������ ���
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b1;
//                             is_temp_humid_mode <= 1'b0;
//                         end
//                         STATE_6, STATE_7: begin  // �½��� ���
//                             is_clock_mode <= 1'b0;
//                             is_ultrasonic_mode <= 1'b0;
//                             is_temp_humid_mode <= 1'b1;
//                         end
//                     endcase
//                 end
//             end else begin
//                 force_transition_counter <= 32'd0;
//             end

//             // �Ϲ� Ÿ�Ӿƿ� ī���� ����
//             if (state_transition_active) begin
//                 timeout_counter <= timeout_counter + 1;
//                 if (timeout_counter >= TIMEOUT_MAX) begin
//                     // Ÿ�Ӿƿ� �߻� - ���� ��ȯ ���� �Ϸ�
//                     current_state <= target_state;
//                     state_transition_active <= 1'b0;
//                     state_change_done <= 1'b1;
//                     timeout_counter <= 32'd0;
//                 end
//             end else begin
//                 timeout_counter <= 32'd0;
//             end

//             // done ��ȣ ����
//             if (state_change_done && !state_transition_active && !force_mode_change) begin
//                 state_change_done <= 1'b0;
//             end

//             // ����ġ �Է¿� ���� ��� ��ȯ - ����ġ ���� ����
//             if (!state_transition_active && !force_mode_change) begin
//                 case (sw)
//                     3'b001: begin  // W17=1, V16=0, U17=0 (001) - ������ ���
//                         target_state <= STATE_4;
//                         if ((current_state == STATE_6) || (current_state == STATE_7)) begin
//                             force_mode_change <= 1'b1;
//                             force_transition_counter <= 32'd0;
//                         end else if ((current_state != STATE_4) && (current_state != STATE_5)) begin
//                             state_transition_active <= 1'b1;
//                         end
//                     end

//                     3'b010: begin  // W17=0, V16=1, U17=0 (010) - �½��� ���
//                         target_state <= STATE_6;
//                         if ((current_state != STATE_6) && (current_state != STATE_7)) begin
//                             state_transition_active <= 1'b1;
//                         end
//                     end

//                     3'b100: begin  // W17=0, V16=0, U17=1 (100) - �����ġ ���
//                         target_state <= STATE_0;
//                         if ((current_state == STATE_6) || (current_state == STATE_7)) begin
//                             force_mode_change <= 1'b1;
//                             force_transition_counter <= 32'd0;
//                         end else if ((current_state != STATE_0) && (current_state != STATE_1)) begin
//                             state_transition_active <= 1'b1;
//                         end
//                     end

//                     3'b000: begin  // W17=0, V16=0, U17=0 (000) - �ð� ���
//                         target_state <= STATE_2;
//                         if ((current_state == STATE_6) || (current_state == STATE_7)) begin
//                             force_mode_change <= 1'b1;
//                             force_transition_counter <= 32'd0;
//                         end else if ((current_state != STATE_2) && (current_state != STATE_3)) begin
//                             state_transition_active <= 1'b1;
//                         end
//                     end

//                     default: begin
//                         // �ٸ� ����ġ ������ ����
//                     end
//                 endcase

//                 // ��ư �Է¿� ���� ���� ��ȯ (��� ��)
//                 if (btn_run_edge) begin
//                     case (current_state)
//                         STATE_0: begin
//                             target_state <= STATE_1;  // �����ġ Msec:Sec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_1: begin
//                             target_state <= STATE_0;  // �����ġ Hour:Min -> Msec:Sec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_2: begin
//                             target_state <= STATE_3;  // �ð� Sec:Msec -> Hour:Min
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_3: begin
//                             target_state <= STATE_2;  // �ð� Hour:Min -> Sec:Msec
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_4: begin
//                             target_state <= STATE_5;  // ������ CM -> Inch
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_5: begin
//                             target_state <= STATE_4;  // ������ Inch -> CM
//                             state_transition_active <= 1'b1;
//                         end
//                         STATE_6: begin
//                             // �µ� -> ���� (���� ���� ����)
//                             current_state <= STATE_7;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         STATE_7: begin
//                             // ���� -> �µ� (���� ���� ����)
//                             current_state <= STATE_6;
//                             temp_humid_toggle <= ~temp_humid_toggle;
//                         end
//                         default: begin
//                             // �⺻�� ó��
//                         end
//                     endcase
//                 end
//             end

//             // ���� ���� ���� ���̰� ���� Ÿ�Ӿƿ� �߻� ���̸� ��� ���� ��ȯ ���
//             if (state_transition_active && timeout_counter < TIMEOUT_MAX/2) begin
//                 if (!state_change_done) begin
//                     current_state <= target_state;
//                     state_change_done <= 1'b1;
//                     state_transition_active <= 1'b0;
//                     timeout_counter <= 32'd0;
//                 end
//             end

//             // ���¿� ���� ��� �÷��׿� ��� ����
//             case (current_state)
//                 STATE_0, STATE_1: begin  // �����ġ ���
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_2, STATE_3: begin  // �ð� ���
//                     is_clock_mode <= 1'b1;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b1;
//                 end

//                 STATE_4, STATE_5: begin  // ������ ���
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b1;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b1;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b0;
//                 end

//                 STATE_6, STATE_7: begin  // �½��� ���
//                     is_clock_mode <= 1'b0;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b1;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b1;
//                     sw4 <= 1'b1;
//                     sw5 <= 1'b1;
//                 end

//                 default: begin
//                     // �⺻�� ����
//                     is_clock_mode <= 1'b1;
//                     is_ultrasonic_mode <= 1'b0;
//                     is_temp_humid_mode <= 1'b0;
//                     sw2 <= 1'b0;
//                     sw3 <= 1'b0;
//                     sw4 <= 1'b0;
//                     sw5 <= 1'b1;
//                 end
//             endcase
//         end
//     end
// endmodule
// module fsm_controller(
//     input clk,
//     input reset,
//     input [2:0] sw,
//     input btn_run,
//     input sw_mode_in,
//     output reg [2:0] current_state,
//     output is_clock_mode,
//     output is_ultrasonic_mode,
//     output is_temp_humid_mode,
//     output reg sw2,
//     output reg sw3,
//     output reg sw4,
//     output reg sw5
// );
//     // 상태 정의 (3비트)
//     localparam STATE_0 = 3'b000;  // 스톱워치 Msec:Sec
//     localparam STATE_1 = 3'b001;  // 스톱워치 Hour:Min
//     localparam STATE_2 = 3'b010;  // 시계 Sec:Msec
//     localparam STATE_3 = 3'b011;  // 시계 Hour:Min
//     localparam STATE_4 = 3'b100;  // 초음파 CM
//     localparam STATE_5 = 3'b101;  // 초음파 Inch
//     localparam STATE_6 = 3'b110;  // 온도
//     localparam STATE_7 = 3'b111;  // 습도

//     reg [2:0] next_state;

//     // FSM 상태 전이 - 기존 전환 조건 유지하면서 추가된 상태 처리
//     always @(*) begin
//         next_state = current_state;

//         case (current_state)
//             STATE_0: begin
//                 if (sw == 3'b001) next_state = STATE_1;
//                 else if (sw == 3'b010) next_state = STATE_2;
//                 else if (sw == 3'b100) next_state = STATE_4;
//             end
//             STATE_1: begin
//                 if (sw == 3'b000) next_state = STATE_0;
//                 else if (sw == 3'b011) next_state = STATE_3;
//                 else if (sw == 3'b101) next_state = STATE_5;
//             end
//             STATE_2: begin
//                 if (sw == 3'b000) next_state = STATE_0;
//                 else if (sw == 3'b011) next_state = STATE_3;
//                 else if (sw == 3'b110) next_state = STATE_6;
//             end
//             STATE_3: begin
//                 if (sw == 3'b001) next_state = STATE_1;
//                 else if (sw == 3'b010) next_state = STATE_2;
//                 else if (sw == 3'b111) next_state = STATE_7;
//             end
//             STATE_4: begin
//                 if (sw == 3'b000) next_state = STATE_0;
//                 else if (sw == 3'b101) next_state = STATE_5;
//                 else if (sw == 3'b110) next_state = STATE_6;
//             end
//             STATE_5: begin
//                 if (sw == 3'b001) next_state = STATE_1;
//                 else if (sw == 3'b100) next_state = STATE_4;
//                 else if (sw == 3'b111) next_state = STATE_7;
//             end
//             STATE_6: begin
//                 if (sw == 3'b010) next_state = STATE_2;
//                 else if (sw == 3'b100) next_state = STATE_4;
//                 else if (sw == 3'b111) next_state = STATE_7;
//             end
//             STATE_7: begin
//                 if (sw == 3'b011) next_state = STATE_3;
//                 else if (sw == 3'b101) next_state = STATE_5;
//                 else if (sw == 3'b110) next_state = STATE_6;
//             end
//         endcase
//     end

//     // FSM 상태 저장 - 단순화된 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset)
//             current_state <= STATE_0;
//         else 
//             current_state <= next_state;
//     end

//     // 모드 신호 설정
//     always @(*) begin
//         sw2 = 0;  // 스톱워치
//         sw3 = 0;  // 시계
//         sw4 = 0;  // 초음파
//         sw5 = 0;  // 온습도

//         case (current_state)
//             STATE_0, STATE_1: sw2 = 1;
//             STATE_2, STATE_3: sw3 = 1;
//             STATE_4, STATE_5: sw4 = 1;
//             STATE_6, STATE_7: sw5 = 1;
//         endcase
//     end

//     assign is_clock_mode = sw3;
//     assign is_ultrasonic_mode = sw4;
//     assign is_temp_humid_mode = sw5;
// endmodule

// module fsm_controller(
//     input clk,
//     input reset,
//     input [1:0] sw,
//     input btn_run,
//     input sw_mode_in,
//     output reg [1:0] current_state,
//     output is_clock_mode,
//     output reg sw2,
//     output reg sw3
// );
//     // 상태 정의
//     parameter STATE_0 = 2'b00;  // Stopwatch Mode Msec:Sec
//     parameter STATE_1 = 2'b01;  // Stopwatch Mode Hour:Min
//     parameter STATE_2 = 2'b10;  // Clock Mode Sec:Msec
//     parameter STATE_3 = 2'b11;  // Clock Mode Hour:Min

//     // 다음 상태를 저장할 레지스터
//     reg [1:0] next_state;

//     // 다음 상태 논리 (조합 논리)
//     always @(*) begin
//         // 기본값은 현재 상태 유지
//         next_state = current_state;

//         case (current_state)
//             STATE_0: begin // Stopwatch Msec:Sec
//                 if (sw == 2'b01)           // sw[0]=1, sw[1]=0
//                     next_state = STATE_1;
//                 else if (sw == 2'b10)      // sw[0]=0, sw[1]=1
//                     next_state = STATE_2;
//             end

//             STATE_1: begin // Stopwatch Hour:Min
//                 if (sw == 2'b00)           // sw[0]=0, sw[1]=0
//                     next_state = STATE_0;
//                 else if (sw == 2'b11)      // sw[0]=1, sw[1]=1
//                     next_state = STATE_3;
//             end

//             STATE_2: begin // Clock Sec:Msec
//                 if (sw == 2'b00)           // sw[0]=0, sw[1]=0
//                     next_state = STATE_0;
//                 else if (sw == 2'b11)      // sw[0]=1, sw[1]=1
//                     next_state = STATE_3;
//             end

//             STATE_3: begin // Clock Hour:Min
//                 if (sw == 2'b01)           // sw[0]=1, sw[1]=0
//                     next_state = STATE_1;
//                 else if (sw == 2'b10)      // sw[0]=0, sw[1]=1
//                     next_state = STATE_2;
//             end
//         endcase
//     end

//     // 상태 등록 프로세스 (순차 논리)
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_state <= STATE_0;
//         end else begin
//             current_state <= next_state;
//         end
//     end

//     // 출력 논리 (메일리 모델 - 현재 상태와 입력에 기반)
//     always @(*) begin
//         // 기본값 설정
//         sw2 = 1'b0;
//         sw3 = 1'b0;

//         // 현재 상태와 입력에 따라 출력 결정
//         case (current_state)
//             STATE_0, STATE_1: begin
//                 // 스톱워치 모드 (STATE_0, STATE_1)
//                 sw2 = 1'b1;
//                 sw3 = 1'b0;
//             end

//             STATE_2, STATE_3: begin
//                 // 시계 모드 (STATE_2, STATE_3)
//                 sw2 = 1'b0;
//                 sw3 = 1'b1;
//             end
//         endcase
//     end

//     // is_clock_mode 신호 할당
//     assign is_clock_mode = sw3;
// endmodule
