module led_controller(
    input clk,               // System clock (100MHz)
    input reset,             // Reset signal
    input fsm_error,         // FSM error detection signal
    input [3:0] led_status,  // LED status from CU
    output [3:0] led         // LED output
);

    // Blinking counter and state for error indication
    reg [24:0] led_blink_counter;
    reg led_blink_state;
    
    // Blink LED when error occurs (about 5Hz)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            led_blink_counter <= 0;
            led_blink_state <= 0;
        end else begin
            if (fsm_error) begin
                // When error occurs, make LEDs blink (approx 5Hz)
                if (led_blink_counter >= 10_000_000) begin
                    led_blink_counter <= 0;
                    led_blink_state <= ~led_blink_state;
                end else begin
                    led_blink_counter <= led_blink_counter + 1;
                end
            end else begin
                led_blink_counter <= 0;
                led_blink_state <= 0;
            end
        end
    end
    
    // LED output selection: blinking when error, normal status otherwise
    assign led = fsm_error ? (led_blink_state ? 4'b1111 : 4'b0000) : led_status;

endmodule