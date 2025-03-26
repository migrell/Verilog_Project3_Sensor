module tick_gen(
    input clk,
    input rst,
    output reg tick_10msec
);
    reg [19:0] tick_counter;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_counter <= 0;
            tick_10msec <= 0;
        end else begin
            if (tick_counter >= 1_000_000 - 1) begin
                tick_counter <= 0;
                tick_10msec <= 1;  // 틱 신호 활성화
            end else begin
                tick_counter <= tick_counter + 1;
                // 펄스 폭을 1 클럭 사이클로 줄임
                tick_10msec <= (tick_counter == 0) ? 1 : 0;
            end
        end
    end
endmodule