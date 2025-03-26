`timescale 1ns / 1ps

module top_dut(
    input clk,
    input rst,
    input btn_start,
    
    output [4:0] led,
    output fsm_error,
    output dut_io
);
    // Internal signals
    wire tick_10msec;
    wire [3:0] current_state;
    wire [7:0] dnt_data;
    wire [7:0] dnt_sensor_data;
    wire sensor_data;

    // DUT Controller instantiation
    dut_ctr U_DUT_CTR(  
        .clk(clk),
        .rst(rst),
        .btn_start(btn_start),
        .tick_counter(tick_10msec),
        .sensor_data(sensor_data),
        .current_state(current_state),
        .dnt_data(dnt_data),
        .dnt_sensor_data(dnt_sensor_data),
        .dnt_io(dut_io)
    );

    // Tick generator instantiation
    tick_gen U_TICK_GEN(
        .clk(clk),
        .rst(rst),
        .tick_10msec(tick_10msec)
    );
    
    // LED controller instantiation
    dnt_led U_DNT_LED(
        .clk(clk),
        .rst(rst),
        .fsm_error(fsm_error),
        .led_status(led_status),
        .led(led)
    );
    
    // FSM error detection (example implementation based on state conditions)
    assign fsm_error = (current_state == 4'b1111); // Error if invalid state

endmodule










    

