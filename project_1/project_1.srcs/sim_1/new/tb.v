
module tb_ultrasonic_distance_meter;
    // Testbench signals
    reg clk;
    reg reset;
    reg echo;
    reg btn_start;
    wire trigger;
    wire [3:0] fnd_comm;
    wire [7:0] fnd_font;
    wire [3:0] led;
    
    // Simulation parameters
    parameter CLK_PERIOD = 10; // 10ns for 100MHz clock
    parameter SIM_ACCEL = 50;  // Simulation acceleration factor for improved timing accuracy
    
    // Timeout and counter parameters
    parameter ECHO_WAIT_TIMEOUT = 25_000_000; // 250ms echo wait timeout (same as in CU module)
    parameter ECHO_COUNT_TIMEOUT = 25_000_000; // 250ms echo count timeout
    
    // Timeout counters
    reg [31:0] echo_wait_counter;
    reg [31:0] echo_count_counter;
    reg echo_timeout_occurred;
    
    // Test control signals
    reg enable_forced_echo = 1; // Flag to control forced echo generation
    reg enable_timeout_test = 0; // Flag to enable timeout test case
    
    // Device Under Test (DUT) instantiation
    ultrasonic_distance_meter DUT (
        .clk(clk),
        .reset(reset),
        .echo(echo),
        .btn_start(btn_start),
        .trigger(trigger),
        .fnd_comm(fnd_comm),
        .fnd_font(fnd_font),
        .led(led)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk; // Generate 100MHz clock
    end
    
    // Timeout counter management - monitors for timeout conditions
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            echo_wait_counter <= 0;
            echo_count_counter <= 0;
            echo_timeout_occurred <= 0;
        end else begin
            // Echo wait timeout counter - starts when trigger goes low and resets when echo detected
            if (trigger) begin
                echo_wait_counter <= 0;
            end else if (!echo && !echo_timeout_occurred) begin
                echo_wait_counter <= echo_wait_counter + 1;
                
                if (echo_wait_counter >= ECHO_WAIT_TIMEOUT/SIM_ACCEL) begin
                    echo_timeout_occurred <= 1;
                    $display("Time=%0t ns: WARNING - Echo wait timeout occurred", $time);
                end
            end
            
            // Echo count timeout counter - active during echo pulse
            if (!echo) begin
                echo_count_counter <= 0;
            end else begin
                echo_count_counter <= echo_count_counter + 1;
                
                if (echo_count_counter >= ECHO_COUNT_TIMEOUT/SIM_ACCEL) begin
                    echo_timeout_occurred <= 1;
                    $display("Time=%0t ns: WARNING - Echo count timeout occurred", $time);
                end
            end
            
            // Reset timeout flag when button is pressed
            if (btn_start) begin
                echo_timeout_occurred <= 0;
            end
        end
    end
    
    // Echo generation process - handles responding to trigger with appropriate echo
    initial begin
        forever begin
            @(posedge trigger); // Wait for trigger signal to go HIGH
            $display("Time=%0t ns: Trigger detected HIGH", $time);
            
            @(negedge trigger); // Wait for trigger signal to go LOW
            $display("Time=%0t ns: Trigger detected LOW", $time);
            
            if (enable_forced_echo && !enable_timeout_test) begin
                // Add delay before echo returns (for 20cm distance)
                // 20cm = sound travels 40cm (round trip) at 340m/s = ~1.18ms
                // But we use accelerated simulation time
                #((CLK_PERIOD*3000)/SIM_ACCEL);
                
                // Generate echo pulse for 20cm measurement
                $display("Time=%0t ns: Starting ECHO pulse for 20cm", $time);
                echo = 1;
                
                // Echo pulse duration for 20cm (~1160us)
                #((CLK_PERIOD*116000)/SIM_ACCEL);
                
                // End echo pulse
                echo = 0;
                $display("Time=%0t ns: ECHO pulse ended", $time);
            end
        end
    end
    
    // Main test sequence
    initial begin
        // Initialize signals
        reset = 0;
        echo = 0;
        btn_start = 0;
        enable_forced_echo = 1;
        enable_timeout_test = 0;
        
        // Apply reset pulse
        #100;
        $display("Time=%0t ns: Applying RESET", $time);
        reset = 1;
        #100;
        reset = 0;
        $display("Time=%0t ns: Released RESET", $time);
        
        // Allow system to stabilize after reset
        #2000;
        
        // Test Case 1: Normal measurement (20cm)
        $display("Time=%0t ns: Starting normal measurement test (20cm)", $time);
        
        // Press button to start measurement
        btn_start = 1;
        #2000; // Hold button for 2us
        btn_start = 0;
        $display("Time=%0t ns: Button released", $time);
        
        // Wait for complete measurement cycle
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Test Case 2: Another normal measurement
        $display("Time=%0t ns: Starting second measurement test", $time);
        
        btn_start = 1;
        #2000;
        btn_start = 0;
        
        // Wait for measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Test Case 3: Timeout test - disable echo generation
        $display("Time=%0t ns: Starting timeout test - disabling echo", $time);
        enable_forced_echo = 0;
        enable_timeout_test = 1;
        
        btn_start = 1;
        #2000;
        btn_start = 0;
        
        // Wait for timeout to occur - should be around ECHO_WAIT_TIMEOUT/SIM_ACCEL
        #((CLK_PERIOD*600000)/SIM_ACCEL);
        
        // Test Case 4: Error recovery after timeout
        $display("Time=%0t ns: Testing error recovery", $time);
        enable_forced_echo = 1; // Re-enable echo generation
        enable_timeout_test = 0;
        
        btn_start = 1;
        #2000;
        btn_start = 0;
        
        // Wait for measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Test Case 5: Reset during measurement
        $display("Time=%0t ns: Testing reset during measurement", $time);
        
        btn_start = 1;
        #2000;
        btn_start = 0;
        
        // Wait for trigger to start
        #10000;
        
        // Apply reset in the middle of measurement
        reset = 1;
        #100;
        reset = 0;
        $display("Time=%0t ns: Applied reset during measurement", $time);
        
        // Allow stabilization and start new measurement
        #10000;
        btn_start = 1;
        #2000;
        btn_start = 0;
        
        // Wait for final measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // End simulation
        $display("Time=%0t ns: Simulation complete", $time);
        #10000;
        $finish;
    end
    
    // Enhanced monitor for important signals
    initial begin
        $display("Time\t\tReset\tBtn\tTrigger\tEcho\tLED\tTimeout");
        forever begin
            #(CLK_PERIOD*1000);
            $display("%0t ns\t%b\t%b\t%b\t%b\t%b\t%b",
                     $time, reset, btn_start, trigger, echo, led, echo_timeout_occurred);
        end
    end
    
endmodule



// module tb_ultrasonic_distance_meter;
//     // Testbench signals
//     reg clk;
//     reg reset;
//     reg echo;
//     reg btn_start;
//     wire trigger;
//     wire [3:0] fnd_comm;
//     wire [7:0] fnd_font;
//     wire [3:0] led;
    
//     // Simulation parameters
//     parameter CLK_PERIOD = 10; // 10ns for 100MHz clock
//     parameter SIM_ACCEL = 50;  // Simulation acceleration factor for improved timing accuracy
    
//     // Device Under Test (DUT) instantiation
//     ultrasonic_distance_meter DUT (
//         .clk(clk),
//         .reset(reset),
//         .echo(echo),
//         .btn_start(btn_start),
//         .trigger(trigger),
//         .fnd_comm(fnd_comm),
//         .fnd_font(fnd_font),
//         .led(led)
//     );

//     // Clock generation
//     initial begin
//         clk = 0;
//         forever #(CLK_PERIOD/2) clk = ~clk; // Generate 100MHz clock
//     end
    
//     // Monitor for important signals
//     initial begin
//         $display("Time\t\tReset\tBtnStart\tTrigger\tEcho\tLED\tFND_comm\tFND_font");
//         $monitor("%0t ns\t%b\t%b\t\t%b\t%b\t%b\t%b\t%h",
//                  $time, reset, btn_start, trigger, echo, led, fnd_comm, fnd_font);
//     end
    
//     // Echo generation process
//     initial begin
//         forever begin
//             @(posedge trigger); // Wait for trigger signal to go HIGH
//             $display("Time=%0t ns: Trigger detected HIGH", $time);
            
//             @(negedge trigger); // Wait for trigger signal to go LOW
//             $display("Time=%0t ns: Trigger detected LOW", $time);
            
//             // Add delay before echo returns (for 20cm distance)
//             // 20cm = sound travels 40cm (round trip) at 340m/s = ~1.18ms
//             // But we use accelerated simulation time
//             #((CLK_PERIOD*3000)/SIM_ACCEL);
            
//             // Generate echo pulse for 20cm measurement
//             $display("Time=%0t ns: Starting ECHO pulse for 20cm", $time);
//             echo = 1;
            
//             // Echo pulse duration for 20cm (~1160us)
//             #((CLK_PERIOD*116000)/SIM_ACCEL);
            
//             // End echo pulse
//             echo = 0;
//             $display("Time=%0t ns: ECHO pulse ended", $time);
//         end
//     end
    
//     // Main test sequence with improved timing
//     initial begin
//         // Initialize signals
//         reset = 0;
//         echo = 0;
//         btn_start = 0;
        
//         // Apply reset pulse
//         #100;
//         $display("Time=%0t ns: Applying RESET", $time);
//         reset = 1;
//         #100;
//         reset = 0;
//         $display("Time=%0t ns: Released RESET", $time);
        
//         // Allow system to stabilize after reset
//         #2000;
        
//         // Test Case 1: Normal measurement (20cm)
//         $display("Time=%0t ns: Starting normal measurement test (20cm)", $time);
        
//         // Press button to start measurement - hold longer to ensure detection
//         btn_start = 1;
//         #2000; // Hold button for 2us
//         btn_start = 0;
//         $display("Time=%0t ns: Button released", $time);
        
//         // Wait for complete measurement cycle
//         #((CLK_PERIOD*300000)/SIM_ACCEL);
        
//         // Test Case 2: Another measurement
//         $display("Time=%0t ns: Starting second measurement test", $time);
        
//         btn_start = 1;
//         #2000;
//         btn_start = 0;
        
//         // Wait for measurement to complete
//         #((CLK_PERIOD*300000)/SIM_ACCEL);
        
//         // Test Case 3: Test reset functionality
//         $display("Time=%0t ns: Testing reset functionality", $time);
//         reset = 1;
//         #100;
//         reset = 0;
        
//         // Wait and start another measurement
//         #10000;
//         btn_start = 1;
//         #2000;
//         btn_start = 0;
        
//         // Wait for measurement to complete
//         #((CLK_PERIOD*300000)/SIM_ACCEL);
        
//         // End simulation
//         $display("Time=%0t ns: Simulation complete", $time);
//         #10000;
//         $finish;
//     end
    
// endmodule