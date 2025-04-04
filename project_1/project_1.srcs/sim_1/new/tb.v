module tb_ultrasonic_distance_meter;
    // Basic signals
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
    parameter SIM_ACCEL = 10;  // Simulation acceleration factor
    
    // Debug monitoring signals
    wire [1:0] cu_current_state;
    wire [31:0] cu_timeout_counter;
    wire [6:0] dut_msec;
    
    // Test control variables
    reg [31:0] test_count = 0;
    reg [31:0] test_pass_count = 0;
    reg [31:0] test_fail_count = 0;
    reg [3:0] test_scenario = 0;
    reg timeout_detected = 0;
    reg enable_echo = 1;
    
    // Connect monitoring signals to DUT internal signals
    assign cu_current_state = DUT.U_cu.current_state;
    assign cu_timeout_counter = DUT.U_cu.state_timeout_counter;
    assign dut_msec = DUT.w_msec;
    
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
    
    // Echo generation process
    initial begin
        forever begin
            @(posedge trigger); // Wait for trigger signal to go HIGH
            $display("Time=%0t ns: Trigger detected HIGH", $time);
            
            @(negedge trigger); // Wait for trigger signal to go LOW
            $display("Time=%0t ns: Trigger detected LOW", $time);
            
            if (enable_echo) begin
                // Add delay before echo returns (for 20cm distance)
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
    
    // Timeout detection
    always @(posedge clk) begin
        if (DUT.U_cu.fsm_error && !timeout_detected) begin
            timeout_detected = 1;
            $display("Time=%0t ns: Error condition detected, fsm_error flag set", $time);
        end else if (reset || btn_start) begin
            timeout_detected = 0; // Reset timeout flag
        end
    end
    
    // Main test sequence - simplified
    initial begin
        // Initialize signals
        reset = 0;
        echo = 0;
        btn_start = 0;
        enable_echo = 1;
        
        // Apply reset pulse
        #100;
        $display("Time=%0t ns: Applying RESET", $time);
        reset = 1;
        #100;
        reset = 0;
        $display("Time=%0t ns: Released RESET", $time);
        
        // Allow system to stabilize after reset
        #5000;
        
        // Test Case 1: Normal measurement (20cm)
        test_scenario = 1;
        test_count = test_count + 1;
        $display("Time=%0t ns: Starting test scenario %0d - Normal measurement test (20cm)", 
                $time, test_scenario);
        
        btn_start = 1;
        #5000;
        btn_start = 0;
        
        // Wait for complete measurement cycle
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Verify results for Test Case 1
        check_measurement(20);
        
        // Test Case 2: Timeout test
        test_scenario = 2;
        test_count = test_count + 1;
        $display("Time=%0t ns: Starting test scenario %0d - Timeout test (no echo)", 
                $time, test_scenario);
        enable_echo = 0;
        timeout_detected = 0;
        
        btn_start = 1;
        #5000;
        btn_start = 0;
        
        // Wait for timeout to occur
        #((CLK_PERIOD*600000)/SIM_ACCEL);
        
        // Verify results for Test Case 2
        check_timeout();
        
        // Test Case 3: Error recovery test
        test_scenario = 3;
        test_count = test_count + 1;
        $display("Time=%0t ns: Starting test scenario %0d - Error recovery test", 
                $time, test_scenario);
        enable_echo = 1;
        
        btn_start = 1;
        #5000;
        btn_start = 0;
        
        // Wait for measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Verify results for Test Case 3
        check_measurement(20);
        
        // Print final test summary
        $display("\n=== TEST SUMMARY ===");
        $display("Total tests: %0d", test_count);
        $display("Passed: %0d", test_pass_count);
        $display("Failed: %0d", test_fail_count);
        $display("Pass rate: %0.2f%%", (test_pass_count * 100.0) / test_count);
        $display("===================\n");
        
        // End simulation
        $display("Time=%0t ns: Simulation complete", $time);
        #10000;
        $finish;
    end
    
    // Task for checking measurement results
    task check_measurement;
        input [6:0] expected_distance;
        begin
            if (dut_msec >= expected_distance-1 && dut_msec <= expected_distance+1) begin
                $display("Time=%0t ns: TEST PASSED - Measured distance %0d cm is within range of expected %0d cm", 
                        $time, dut_msec, expected_distance);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("Time=%0t ns: TEST FAILED - Measured distance %0d cm is outside expected range", 
                        $time, dut_msec);
                test_fail_count = test_fail_count + 1;
            end
        end
    endtask
    
    // Task for checking timeout conditions
    task check_timeout;
        begin
            if (timeout_detected && DUT.U_cu.fsm_error) begin
                $display("Time=%0t ns: TEST PASSED - Timeout correctly detected and error flag set", $time);
                test_pass_count = test_pass_count + 1;
            end else begin
                $display("Time=%0t ns: TEST FAILED - Timeout not properly handled", $time);
                test_fail_count = test_fail_count + 1;
            end
        end
    endtask
    
    // Enhanced monitor for important signals
    initial begin
        $display("Time\t\tState\tEcho\tTrigger\tLED\tDistance\tTimeout");
        forever begin
            #(CLK_PERIOD*20000);
            $display("%0t ns\t%b\t%b\t%b\t%b\t%0d\t\t%b",
                     $time, cu_current_state, echo, trigger, led, 
                     dut_msec, timeout_detected);
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
//     parameter SIM_ACCEL = 10;  // Simulation acceleration factor
    
//     // Debug monitoring signals
//     wire [1:0] cu_current_state;
//     wire [31:0] cu_timeout_counter;
//     wire cu_echo_posedge;
//     wire cu_echo_negedge;
    
//     // Assign debug signals from DUT
//     assign cu_current_state = DUT.U_cu.current_state;
//     assign cu_timeout_counter = DUT.U_cu.state_timeout_counter;
//     assign cu_echo_posedge = DUT.U_cu.echo_posedge;
//     assign cu_echo_negedge = DUT.U_cu.echo_negedge;
    
//     // Test control signals
//     reg enable_echo = 1; // Flag to control echo generation
    
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
    
//     // Echo generation process
//     initial begin
//         forever begin
//             @(posedge trigger); // Wait for trigger signal to go HIGH
//             $display("Time=%0t ns: Trigger detected HIGH", $time);
            
//             @(negedge trigger); // Wait for trigger signal to go LOW
//             $display("Time=%0t ns: Trigger detected LOW", $time);
            
//             if (enable_echo) begin
//                 // Add delay before echo returns (for 20cm distance)
//                 // 20cm = sound travels 40cm (round trip) at 340m/s = ~1.18ms
//                 #((CLK_PERIOD*3000)/SIM_ACCEL);
                
//                 // Generate echo pulse for 20cm measurement
//                 $display("Time=%0t ns: Starting ECHO pulse for 20cm", $time);
//                 echo = 1;
                
//                 // Echo pulse duration for 20cm (~1160us)
//                 #((CLK_PERIOD*116000)/SIM_ACCEL);
                
//                 // End echo pulse
//                 echo = 0;
//                 $display("Time=%0t ns: ECHO pulse ended", $time);
//             end
//         end
//     end
    
//     // Main test sequence
//     initial begin
//         // Initialize signals
//         reset = 0;
//         echo = 0;
//         btn_start = 0;
//         enable_echo = 1;
        
//         // Apply reset pulse
//         #100;
//         $display("Time=%0t ns: Applying RESET", $time);
//         reset = 1;
//         #100;
//         reset = 0;
//         $display("Time=%0t ns: Released RESET", $time);
        
//         // Allow system to stabilize after reset
//         #5000;
        
//         // Test Case 1: Normal measurement (20cm)
//         $display("Time=%0t ns: Starting normal measurement test (20cm)", $time);
        
//         // Use longer button press to ensure detection
//         btn_start = 1;
//         #5000;
//         btn_start = 0;
//         $display("Time=%0t ns: Button released", $time);
        
//         // Wait for complete measurement cycle
//         #((CLK_PERIOD*300000)/SIM_ACCEL);
        
//         // Test Case 2: Another normal measurement
//         $display("Time=%0t ns: Starting second measurement test", $time);
        
//         btn_start = 1;
//         #5000;
//         btn_start = 0;
        
//         // Wait for measurement to complete
//         #((CLK_PERIOD*300000)/SIM_ACCEL);
        
//         // Test Case 3: Timeout test - disable echo generation
//         $display("Time=%0t ns: Starting timeout test - disabling echo", $time);
//         enable_echo = 0;
        
//         btn_start = 1;
//         #5000;
//         btn_start = 0;
        
//         // Wait for timeout to occur
//         #((CLK_PERIOD*600000)/SIM_ACCEL);
        
//         // Test Case 4: Error recovery after timeout
//         $display("Time=%0t ns: Testing error recovery", $time);
//         enable_echo = 1; // Re-enable echo generation
        
//         btn_start = 1;
//         #5000;
//         btn_start = 0;
        
//         // Wait for measurement to complete
//         #((CLK_PERIOD*300000)/SIM_ACCEL);
        
//         // Test Case 5: Reset during measurement
//         $display("Time=%0t ns: Testing reset during measurement", $time);
        
//         btn_start = 1;
//         #5000;
//         btn_start = 0;
        
//         // Wait for trigger to start
//         #10000;
        
//         // Apply reset in the middle of measurement
//         reset = 1;
//         #100;
//         reset = 0;
//         $display("Time=%0t ns: Applied reset during measurement", $time);
        
//         // Allow stabilization and start new measurement
//         #10000;
//         btn_start = 1;
//         #5000;
//         btn_start = 0;
        
//         // Wait for final measurement to complete
//         #((CLK_PERIOD*300000)/SIM_ACCEL);
        
//         // End simulation
//         $display("Time=%0t ns: Simulation complete", $time);
//         #10000;
//         $finish;
//     end
    
//     // Enhanced monitor for important signals including FSM state
//     initial begin
//         $display("Time\t\tReset\tBtn\tTrigger\tEcho\tLED\tCU_State\tTimeout");
//         forever begin
//             #(CLK_PERIOD*10000);
//             $display("%0t ns\t%b\t%b\t%b\t%b\t%b\t%b\t\t%0d",
//                      $time, reset, btn_start, trigger, echo, led, 
//                      cu_current_state, cu_timeout_counter);
//         end
//     end
    
// endmodule
