`timescale 1ns / 1ps

module tb_dht11();
  reg clk;
  reg reset;
  reg btn_start;
  
  reg dht_sensor_data;
  reg io_oe;
  
  wire led;
  wire dht_io;
  
  assign dht_io = (io_oe) ? dht_sensor_data : 1'bz;
  
  dht11 dut (
    .clk(clk),
    .reset(reset),
    .btn_start(btn_start),
    .led(led),
    .dht_io(dht_io)
  );
    
  always #5 clk = ~clk;
  
  initial begin
    clk = 0;
    reset = 1;
    io_oe = 0;
    btn_start = 0;
    
    #100;
    reset = 0;

    #100;
    btn_start = 1;

    #100;
    btn_start = 0;

    wait(dht_io);
    #30000; //입력 모드 변환

    io_oe = 1;
    dht_sensor_data = 1'b0;

    #80000;
    
    dht_sensor_data = 1'b1;
    #80000;
    #50000;
    $stop;
  end
  
endmodule