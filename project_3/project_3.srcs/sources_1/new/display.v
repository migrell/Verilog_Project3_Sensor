module display_mux(
    input sw_mode,               // 안 써도 됨 (참고용)
    input [1:0] current_state,   // FSM 현재 상태
    input [6:0] sw_msec,
    input [5:0] sw_sec, sw_min,
    input [4:0] sw_hour,
    input [6:0] clk_msec,
    input [5:0] clk_sec, clk_min,
    input [4:0] clk_hour,
    output reg [6:0] o_msec,
    output reg [5:0] o_sec, o_min,
    output reg [4:0] o_hour
);

    always @(*) begin
        case (current_state)
            2'b00, 2'b01: begin  // 스톱워치 모드
                o_msec = sw_msec;
                o_sec  = sw_sec;
                o_min  = sw_min;
                o_hour = sw_hour;
            end
            2'b10, 2'b11: begin  // 시계 모드
                o_msec = clk_msec;
                o_sec  = clk_sec;
                o_min  = clk_min;
                o_hour = clk_hour;
            end
            default: begin
                o_msec = 0;
                o_sec  = 0;
                o_min  = 0;
                o_hour = 0;
            end
        endcase
    end

endmodule