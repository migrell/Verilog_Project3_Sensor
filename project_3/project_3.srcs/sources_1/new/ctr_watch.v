
// 스톱워치 모듈 (제어 + 데이터패스 통합)
module stopwatch_module(
    input clk,
    input reset,
    input btn_run,
    input btn_clear,
    output o_run,
    output o_clear,
    output [6:0] o_msec,
    output [5:0] o_sec, o_min,
    output [4:0] o_hour
);
    wire run, clear;
    
    // 스톱워치 제어 유닛
    stopwatch_cu U_CU(
        .clk(clk),
        .reset(reset),
        .i_btn_run(btn_run),
        .i_btn_clear(btn_clear),
        .o_run(run),
        .o_clear(clear)
    );
    
    assign o_run = run;
    assign o_clear = clear;
    
    // 스톱워치 데이터 패스
    stopwatch_dp U_DP(
        .clk(clk),
        .reset(reset),
        .run(run),
        .clear(clear),
        .msec(o_msec),
        .sec(o_sec),
        .min(o_min),
        .hour(o_hour)
    );
endmodule