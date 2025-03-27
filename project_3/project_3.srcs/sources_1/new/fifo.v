
`timescale 1ns / 1ps

module FIFO (
    input clk, reset,
    input [7:0] wdata,
    input wr, rd,
    output [7:0] rdata,
    output full, empty
);

    // Internal signals
    wire [3:0] waddr, raddr;
    
    // Instance of register_file
    register_file u_reg_file (
        .clk(clk),
        .waddr(waddr),
        .wdata(wdata),
        .wr(wr && !full), // Write only when not full
        .raddr(raddr),
        .rdata(rdata),
        .rd(rd && !empty)  // Read only when not empty
    );
    
    // Instance of FIFO_control_unit
    FIFO_control_unit u_ctrl_unit (
        .clk(clk),
        .reset(reset),
        .wr(wr),
        .waddr(waddr),
        .full(full),
        .rd(rd),
        .raddr(raddr),
        .empty(empty)
    );
    
endmodule



`timescale 1ns / 1ps

module register_file (
    input clk,
    //write
    input [3:0] waddr,
    input [7:0] wdata,
    input wr,
    //read
    input [3:0] raddr,
    output [7:0] rdata,
    input rd
);
    reg [7:0] mem [0:15];
    
    //write
    always @(posedge clk) begin
        if (wr) begin
            mem[waddr] <= wdata;
        end
    end
    
    //read (using assign for combinational read)
    assign rdata = (rd) ? mem[raddr] : 8'b0; // Output 0 when not reading.
    
endmodule

`timescale 1ns / 1ps

module FIFO_control_unit (
    input clk, reset,
    //wr
    input wr,
    output [3:0] waddr,
    output full,
    //read
    input rd,
    output [3:0] raddr,
    output empty 
);

    //1비트 상태 out
    reg full_reg, full_next, empty_reg, empty_next;
    //W,R address 관리
    reg [3:0] wptr_reg, wptr_next, rptr_reg, rptr_next;
    
    // Assign outputs
    assign waddr = wptr_reg;
    assign raddr = rptr_reg;
    assign full = full_reg;
    assign empty = empty_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            full_reg <= 0;
            empty_reg <= 1;
            wptr_reg <= 0;
            rptr_reg <= 0;
        end else begin
            full_reg <= full_next;
            empty_reg <= empty_next;
            wptr_reg <= wptr_next;
            rptr_reg <= rptr_next;
        end
    end
    
    always @(*) begin
        full_next = full_reg;
        empty_next = empty_reg;
        wptr_next = wptr_reg;
        rptr_next = rptr_reg;
        
        case ({wr,rd})
            2'b01: begin // rd=1 일때
                if (!empty_reg) begin
                    rptr_next = (rptr_reg + 1); // Modulo 16 for wrap-around
                    full_next = 0;
                    if (wptr_reg == (rptr_next)) begin
                        empty_next = 1;
                    end
                end
            end
            2'b10: begin // wr=1 일때
                if (!full_reg) begin
                    wptr_next = (wptr_reg + 1); // Modulo 16 for wrap-around
                    empty_next = 0;
                    if ((wptr_next) == rptr_reg) begin
                        full_next = 1;
                    end
                end
            end
            2'b11: begin //Both wr and rd
                if (empty_reg) begin
                    wptr_next = (wptr_reg + 1) % 16;
                    empty_next = 0;
                end else if(full_reg) begin
                    rptr_next = (rptr_reg + 1) % 16;
                    full_next = 0;
                end else begin
                    wptr_next = (wptr_reg + 1) % 16;
                    rptr_next = (rptr_reg + 1) % 16;
                end
            end
        endcase
    end
    
endmodule
