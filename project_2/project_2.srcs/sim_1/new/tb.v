`timescale 1ns / 1ps


module tb_dht11(

reg clk;
reg reset;
reg btn_start;


reg dht_sensor_data;
reg io_oe;

wire led;
wire dht_io;

dht11 dut (
    .clk,
    .reset,





);












    );
endmodule
