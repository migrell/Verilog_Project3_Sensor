module dut_ctr (
    
input clk,
input rst,

output sensor_data,
output current_state[3:0],
output dnt_data[7:0],
output dnt_sensor_data[7:0],
output next_state,
output dnt_time,


localparam IDLE =2'b00, START =2'b01, WAIT = 2'b10, READ= 2'b11;

localparam tick_sec = 18msec ;    

always @(current_state) begin
    clk <=0;
    rst <=0;
    sensor_data<=0;
    current_state <=0;
    dnt_data <=0;
    dnt_sensor_data <=0;

    case (*)
      IDLE : if (btn_start == 1) begin
        next_state <= START;
        dnt_data = 0;
      end


       START: if (tick_count>= tick_sec) begin
        next_state <= wait;
        dnt_time <= 30msec
      end

        WAIT: if (tick_count>= tick_sec) begin
        next_state <= wait;
        dnt_time <= 30msec   
      end

        READ: if (WAIT>= 30msec) begin
        next_state <= READ;
        dnt_io = 0;  
        end

        default: next_state = Idle
                 clk =0;
                 rst =0;
                 sensor_data=0;
                 current_state =0;
                 dnt_data =0;
                 dnt_sensor_data =0;
           endcase
        end
);
endmodule


module dnt_led (
    input clk,
    input rst,
    input fsm_error,
    input [4:0] led_status,
    output led
);
reg [24:0] led_counter;
reg led_state;

always @(posedge clk or posedge rst) begin
  if (rst) begin
    led_counter <=0;
    led_status <=0;
  end else begin
    if (fsm_error) begin
      if (led_status >=10_000_000) begin
        led_counter <=0;
        led_status <= ~ led_status;
      end else begin
        led_counter <= led_counter + 1;
      end
    end else begin
      led_counter <=0;
      led_status <=0;
    end
  end
end

assign led = fsm_error ?(led_status 4'b111 : 4'b0000) :led_status;


endmodule























    

