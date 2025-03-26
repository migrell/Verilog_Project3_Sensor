module dnt_led (
    input clk,
    input rst,
    input fsm_error,
    output reg [4:0] led_status,
    output [4:0] led
);
    reg [24:0] led_counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led_counter <= 0;
            led_status <= 0;
        end else begin
            if (fsm_error) begin
                if (led_counter >= 10000000) begin  // Fixed comparison syntax
                    led_counter <= 0;
                    led_status <= ~led_status;  // Toggle LED status
                end else begin
                    led_counter <= led_counter + 1;
                end
            end else begin
                led_counter <= 0;
                led_status <= 0;
            end
        end
    end

    // Fixed ternary operator syntax and width mismatches
    assign led = fsm_error ? 5'b11111 : led_status;

endmodule