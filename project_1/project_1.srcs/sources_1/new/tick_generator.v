module tick_generator(
    input clk,
    input reset,
    output reg tick_10msec
);
    // 10ms = 1,000,000 클럭 @100MHz
    reg [19:0] counter;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
            tick_10msec <= 0;
        end else begin
            if (counter >= 1_000_000 - 1) begin
                counter <= 0;
                tick_10msec <= 1;
            end else begin
                counter <= counter + 1;
                tick_10msec <= 0;
            end
        end
    end
endmodule