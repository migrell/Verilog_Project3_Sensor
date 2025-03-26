`timescale 1ns / 1ps
module top_dut(
    input clk,
    input rst,
    input btn_start,
    
    output led [4:0],
    output fsm_error,
    output dut_io


  dut_ctr U_DUT_CTR(  
     clk(clk),
     rst(rst),
     sensor_data(sensor_data),
     current_state(current_state),
     dnt_data(dnt_data),
     dnt_sensor_data(dnt_sensor_data),
     next_state(next_state),
     dnt_time(dnt_time),
     );


     tick_gen U_TICK_GEN(
     clk(clk),
     rst(rst),
     tick_10msec(tick_counter),
     tick_counter(tick_10msec)
    );
 
);


endmodule












    

