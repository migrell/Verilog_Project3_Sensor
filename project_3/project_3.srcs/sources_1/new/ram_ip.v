`timescale 1ns / 1ps
//test
module ram_ip #(
    parameter ADDR_WIDTH = 4,
    DATA_WIDTH = 8 
) (
    input                     clk,
    input  [ADDR_WIDTH -1:0] waddr,    // DATA_WIDTH에서 ADDR_WIDTH로 수정
    input  [DATA_WIDTH -1:0] wdata,
    input                     wr,
    output [DATA_WIDTH - 1:0] rdata 
);
    reg [DATA_WIDTH - 1 : 0] ram[0:2**ADDR_WIDTH -1];
    
    //Write
    always @(posedge clk) begin
        if(wr) begin
            ram[waddr] <= wdata;
        end
    end
    
    assign rdata = ram[waddr];
    
endmodule
//커밋 TEST


//FF설계

// assign rdata = rdata_reg; //reg타입으로 연결 
// read
    // always @(posedge clk) begin
        // if(!wr) begin
            // rdata_reg <= ram[waddr];
        // end
    // end
// endmodule
