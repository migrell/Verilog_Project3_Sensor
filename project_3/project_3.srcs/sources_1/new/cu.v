
`timescale 1ns / 1ps

// ------ Control Unit ----- //

module stopwatch_cu(
    input clk,
    input reset,
    input i_btn_run,
    input i_btn_clear,
    output reg o_run,
    output reg o_clear
    );

    parameter STOP = 2'b00, RUN = 2'b01, CLEAR = 2'b10;
    reg [1:0] state, next;

    always @(posedge clk, posedge reset) begin
        if(reset) state <= STOP;
        else state <= next;
    end

    // next
    always @(*) begin
        next <= state;
        case (state)
            STOP: begin
                if(i_btn_run == 1'b1) next <= RUN;
                else if(i_btn_clear == 1'b1) next <= CLEAR;
                else next <= state;
            end
            RUN: begin
                if(i_btn_run == 1'b1) next <= STOP;
                else next <= state;
            end
            CLEAR: begin
                if(i_btn_clear == 1'b1) next <= STOP;
                else next <= state;
            end
            default: next <= state;
        endcase
    end

    // output
    always @(*) begin
        o_run = 1'b0;
        o_clear = 1'b0;
        case (state)
            STOP: begin
                o_run <= 1'b0;
                o_clear <= 1'b0;
            end
            RUN: begin
                o_run <= 1'b1;
                o_clear <= 1'b0;
            end
            CLEAR: begin
                // o_run <= 1'b0;
                o_clear <= 1'b1;
            end
            default: begin
                o_run <= 1'b0;
                o_clear <= 1'b0;
            end
        endcase
    end


endmodule