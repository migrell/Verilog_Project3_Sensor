module btn_debounce(
    input clk,
    input reset,
    input i_btn,
    input rx_done,         // UART RX 완료 신호 추가
    input [7:0] rx_data,   // UART RX 데이터 추가
    input [2:0] btn_type,  // 버튼 타입 지정 (0: RUN, 1: CLEAR, 2: SEC, 3: MIN, 4: HOUR)
    output o_btn
);
    // 버튼 상태 저장 레지스터
    reg prev_btn;
    reg [19:0] debounce_cnt;  // 100MHz 클럭에서 약 10ms 디바운스 타이머 
    reg stable_btn;           // 디바운스 처리된 안정적인 버튼 상태
    reg btn_edge_pulse;       // 버튼 엣지 감지 펄스 (1클럭 지속)
    
    // UART 관련 레지스터
    reg prev_rx_done;
    reg uart_cmd_pulse;       // UART 명령 감지 펄스 (1클럭 지속)
    
    // 각 버튼 타입별 명령어 감지
    wire run_cmd = (rx_data == 8'h52) || (rx_data == 8'h72);   // 'R' 또는 'r'
    wire clear_cmd = (rx_data == 8'h43) || (rx_data == 8'h63); // 'C' 또는 'c'
    wire sec_cmd = (rx_data == 8'h53) || (rx_data == 8'h73);   // 'S' 또는 's'
    wire min_cmd = (rx_data == 8'h4D) || (rx_data == 8'h6D);   // 'M' 또는 'm'
    wire hour_cmd = (rx_data == 8'h48) || (rx_data == 8'h68);  // 'H' 또는 'h'
    
    // 버튼 타입에 따른 명령어 선택
    reg cmd_match;
    always @(*) begin
        case(btn_type)
            3'd0: cmd_match = run_cmd;
            3'd1: cmd_match = clear_cmd;
            3'd2: cmd_match = sec_cmd;
            3'd3: cmd_match = min_cmd;
            3'd4: cmd_match = hour_cmd;
            default: cmd_match = 1'b0;
        endcase
    end
    
    // 디바운스 및 엣지 감지 로직
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            prev_btn <= 1'b0;
            prev_rx_done <= 1'b0;
            debounce_cnt <= 20'd0;
            stable_btn <= 1'b0;
            btn_edge_pulse <= 1'b0;
            uart_cmd_pulse <= 1'b0;
        end else begin
            // 이전 버튼 상태 저장
            prev_btn <= stable_btn;
            
            // 디바운스 로직 - 버튼 입력이 변경되면 카운터 증가
            if(i_btn != stable_btn) begin
                if(debounce_cnt >= 20'd1000000)  // 10ms = 1,000,000 클럭 (100MHz 기준)
                    stable_btn <= i_btn;
                debounce_cnt <= debounce_cnt + 20'd1;
            end else begin
                debounce_cnt <= 20'd0;
            end
            
            // 버튼 엣지 감지 - 안정화된 버튼의 상승 엣지에서 1클럭 펄스 생성
            btn_edge_pulse <= stable_btn & ~prev_btn;
            
            // UART 명령 감지
            prev_rx_done <= rx_done;
            uart_cmd_pulse <= (rx_done & ~prev_rx_done) & cmd_match;
        end
    end
    
    // 최종 출력: 하드웨어 버튼 또는 UART 명령에 의한 펄스
    assign o_btn = btn_edge_pulse | uart_cmd_pulse;

endmodule