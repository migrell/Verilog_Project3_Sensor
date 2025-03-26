`timescale 1ns / 1ps

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
            if (tick_counter >= 1_000_000 - 1) begin  // Fixed comparison syntax
                tick_counter <= 0;
                tick_10msec <= 1;  // Generate tick when counter reaches target
            end else begin
                tick_counter <= tick_counter + 1;  // Fixed variable name
                tick_10msec <= 0; 
            end
        end
    end
endmodule

