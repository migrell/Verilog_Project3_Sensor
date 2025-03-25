module btn_debounce(
    input clk,
    input reset,
    input i_btn,
    input rx_done,         // UART RX 완료 신호 추가
    input [7:0] rx_data,   // UART RX 데이터 추가
    input [2:0] btn_type,  // 버튼 타입 지정 (0: RUN, 1: CLEAR, 2: SEC, 3: MIN, 4: HOUR)
    output o_btn
);
    // 직접적인 버튼 엣지 감지
    reg prev_btn;
    
    // UART 신호 엣지 감지
    reg prev_rx_done;
    
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            prev_btn <= 1'b0;
            prev_rx_done <= 1'b0;
        end else begin
            prev_btn <= i_btn;
            prev_rx_done <= rx_done;
        end
    end
    
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
    
    // 출력 신호: 하드웨어 버튼의 엣지 또는 (UART rx_done의 엣지 & 해당 버튼 명령)
    assign o_btn = (i_btn & ~prev_btn) | ((rx_done & ~prev_rx_done) & cmd_match);
endmodule