`timescale 1ns / 1ps


module register ( 
    input clk,
    input [31:0] d,
    input [3:0] addr, 
    output [31:0] q


);

    reg [31:0] q_reg[15:0];  //32bit memory + 16개 block 추가 
    assign q = q_reg[addr];


    always @(posedge clk) begin

        q_reg[addr] <= d;


    end

endmodule
