`timescale 1ns / 1ps

module tick_gen(
    input clk,
    input rst,
    output reg tick_10msec

    );
    reg [19:0] tick_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_count <= 0;
            tick_10msec <= 0;
        end else begin
            if (tick_counter >= 1_000_000=1) begin
                tick_counter <= 0;
                tick_10msec <= 1; //by tick high
            end else begin
               counter <= counter + 1;
               tick_10msec <= 0; 
            end
        end
    end
endmodule




