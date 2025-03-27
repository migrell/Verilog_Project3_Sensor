module led_indicator(
    input clk,
    input reset,
    input [1:0] current_state,
    input run,
    input sw2,                  // Add this
    input sw3,                  // Add this
    input is_clock_mode,
    output reg [3:0] led
);

    always @(posedge clk or posedge reset) begin
        if(reset) begin
            led <= 4'b0000;
        end else begin
            led[0] <= current_state[0];  // LSB of current state
            led[1] <= current_state[1];  // MSB of current state
            led[2] <= sw2;               // Stopwatch state
            led[3] <= sw3;               // Clock state
        end
    end
endmodule