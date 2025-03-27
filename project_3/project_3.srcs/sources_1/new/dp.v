
`timescale 1ns / 1ps

module stopwatch_dp(
    input clk,
    input reset,
    input run,
    input clear,
    output [6:0] msec,
    output [5:0] sec,
    output [5:0] min,
    output [4:0] hour
    );

    reg [19:0] clk_div;
    wire clk_10ms;

    wire w_clk_100hz;
    wire w_msec_tick, w_sec_tick, w_min_tick;

    // msec //.BIT_WIDTH(7)
    time_counter #(.TICK_COUNT(100)) U_time_msec(
        .clk(clk),
        .reset(reset),
        .tick(w_clk_100hz),
        .clear(clear),
        .o_time(msec),
        .o_tick(w_msec_tick)
    );

    // sec
    time_counter #(.TICK_COUNT(60)) U_time_sec(
        .clk(clk),
        .reset(reset),
        .tick(w_msec_tick),
        .clear(clear),
        .o_time(sec),
        .o_tick(w_sec_tick)
    );

    // min
    time_counter #(.TICK_COUNT(60)) U_time_min(
        .clk(clk),
        .reset(reset),
        .tick(w_sec_tick),
        .clear(clear),
        .o_time(min),
        .o_tick(w_min_tick)
    );

    // hour
    time_counter #(.TICK_COUNT(24)) U_time_hour(
        .clk(clk),
        .reset(reset),
        .tick(w_min_tick),
        .clear(clear),
        .o_time(hour),
        .o_tick()
    );

    clk_div_100 U_clk_div(
        .clk(clk),
        .reset(reset),
        .run(run),
        .clear(clear),
        .o_clk(w_clk_100hz)
    );


endmodule


// ----------------------------------- //
module time_counter (
    input clk,
    input reset,
    input tick,
    input clear,
    output [6:0] o_time,
    output o_tick
);
    parameter TICK_COUNT = 100;
    
    reg [$clog2(TICK_COUNT)-1:0] count_reg;
    reg tick_reg;
    
    assign o_time = count_reg;
    assign o_tick = tick_reg;
    
    always @(posedge clk, posedge reset) begin
        if(reset) begin
            count_reg <= 0;
            tick_reg <= 0;
        end else begin
            if(clear) begin
                count_reg <= 0;
                tick_reg <= 0;
            end else if(tick) begin
                if(count_reg >= TICK_COUNT - 1) begin
                    count_reg <= 0;
                    tick_reg <= 1'b1;
                end else begin
                    count_reg <= count_reg + 1;
                    tick_reg <= 1'b0;
                end
            end else begin
                tick_reg <= 1'b0; // tick 신호가 없을 때 항상 tick_reg를 0으로 설정
            end
        end
    end
endmodule



module clk_div_100 (
    input clk,
    input reset,
    input run,
    input clear,
    output o_clk
);
    // 디버깅을 위해 시간을 더 빠르게 설정
    parameter FCOUNT = 5_000_000; // 약 500Hz
    
    reg [$clog2(FCOUNT)-1:0] count_reg;
    reg clk_reg;
    
    assign o_clk = clk_reg;
    
    always @(posedge clk, posedge reset) begin
        if(reset) begin
            count_reg <= 0;
            clk_reg <= 0;
        end else if(clear) begin
            count_reg <= 0;
            clk_reg <= 0;
        end else if(run) begin
            if(count_reg >= FCOUNT - 1) begin
                count_reg <= 0;
                clk_reg <= 1'b1; // 펄스 생성
            end else begin
                count_reg <= count_reg + 1;
                clk_reg <= 1'b0;
            end
        end else begin
            clk_reg <= 1'b0; // run이 아닐 때는 0으로 유지
        end
    end
endmodule