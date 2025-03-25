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
    parameter SIM_ACCEL = 10;  // Simulation acceleration factor
    
    // Debug monitoring signals
    wire [1:0] cu_current_state;
    wire [31:0] cu_timeout_counter;
    wire cu_echo_posedge;
    wire cu_echo_negedge;
    wire [6:0] dut_msec;            // Distance value from DP module
    reg [1:0] prev_cu_state;         // Previous FSM state
    wire state_changed;              // State change detection
    
    // Echo timing measurement variables
    time echo_start_time;            // Time when echo signal started
    time echo_end_time;              // Time when echo signal ended
    reg [31:0] echo_duration;        // Echo pulse duration in ns
    
    // Test statistics variables
    reg [31:0] test_count;           // Total test count
    reg [31:0] test_pass_count;      // Passed test count
    reg [31:0] test_fail_count;      // Failed test count
    
    // Test control variables
    reg [6:0] expected_distance;     // Expected distance value
    reg [6:0] measured_distance;     // Measured distance value
    reg [3:0] test_scenario;         // Current test scenario number
    reg timeout_detected;            // Timeout detection flag
    
    // Assign debug signals from DUT
    assign cu_current_state = DUT.U_cu.current_state;
    assign cu_timeout_counter = DUT.U_cu.state_timeout_counter;
    assign cu_echo_posedge = DUT.U_cu.echo_posedge;
    assign cu_echo_negedge = DUT.U_cu.echo_negedge;
    assign dut_msec = DUT.w_msec;    // Distance value from top module
    assign state_changed = (prev_cu_state != cu_current_state);
    
    // Test control signals
    reg enable_echo = 1; // Flag to control echo generation
    
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
    
    // FSM state tracking
    always @(posedge clk) begin
        prev_cu_state <= cu_current_state;
        
        if (state_changed) begin
            case(cu_current_state)
                2'b00: $display("Time=%0t ns: FSM State changed to IDLE", $time);
                2'b01: $display("Time=%0t ns: FSM State changed to TRIGGER", $time);
                2'b10: $display("Time=%0t ns: FSM State changed to WAIT_ECHO", $time);
                2'b11: $display("Time=%0t ns: FSM State changed to COUNT_ECHO", $time);
                default: $display("Time=%0t ns: FSM State changed to UNKNOWN", $time);
            endcase
        end
    end
    
    // Echo duration measurement
    always @(posedge echo) begin
        echo_start_time = $time;
        $display("Time=%0t ns: Echo signal started", echo_start_time);
    end
    
    always @(negedge echo) begin
        if (echo_start_time > 0) begin  // Ensure echo_start_time was recorded
            echo_end_time = $time;
            echo_duration = echo_end_time - echo_start_time;
            $display("Time=%0t ns: Echo signal ended, duration=%0d ns", 
                    echo_end_time, echo_duration);
            
            // Calculate theoretical distance for verification
            $display("Time=%0t ns: Theoretical distance = %0d cm", 
                    $time, (echo_duration/10000)/58);
        end
    end
    
    // Timeout detection
    always @(posedge clk) begin
        if (cu_current_state == 2'b10 && cu_timeout_counter >= 249000) begin
            // Detection threshold set just below WAIT_ECHO_TIMEOUT (250,000)
            timeout_detected = 1;
            $display("Time=%0t ns: Timeout condition detected in WAIT_ECHO state", $time);
        end else if (cu_current_state == 2'b11 && cu_timeout_counter >= 249000) begin
            // Detection threshold set just below COUNT_ECHO_TIMEOUT (250,000)
            timeout_detected = 1;
            $display("Time=%0t ns: Timeout condition detected in COUNT_ECHO state", $time);
        end else if (reset || btn_start) begin
            timeout_detected = 0; // Reset timeout flag
        end
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
                // 20cm = sound travels 40cm (round trip) at 340m/s = ~1.18ms
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
        // Initialize all variables
        reset = 0;
        echo = 0;
        btn_start = 0;
        enable_echo = 1;
        test_count = 0;
        test_pass_count = 0;
        test_fail_count = 0;
        test_scenario = 0;
        expected_distance = 20; // Default expected distance is 20cm
        measured_distance = 0;
        timeout_detected = 0;
        prev_cu_state = 2'b00; // Initialize to IDLE
        echo_start_time = 0;
        echo_end_time = 0;
        echo_duration = 0;
        
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
        
        // Use longer button press to ensure detection
        btn_start = 1;
        #5000;
        btn_start = 0;
        $display("Time=%0t ns: Button released", $time);
        
        // Wait for complete measurement cycle
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Verify test results for scenario 1
        measured_distance = dut_msec;
        if (measured_distance >= 19 && measured_distance <= 21) begin
            $display("Time=%0t ns: TEST PASSED - Measured distance %0d cm is within range of expected 20cm", 
                    $time, measured_distance);
            test_pass_count = test_pass_count + 1;
        end else begin
            $display("Time=%0t ns: TEST FAILED - Measured distance %0d cm is outside expected range", 
                    $time, measured_distance);
            test_fail_count = test_fail_count + 1;
        end
        
        // Test Case 2: Another normal measurement
        test_scenario = 2;
        test_count = test_count + 1;
        $display("Time=%0t ns: Starting test scenario %0d - Second measurement test", 
                $time, test_scenario);
        
        btn_start = 1;
        #5000;
        btn_start = 0;
        
        // Wait for measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Verify test results for scenario 2
        measured_distance = dut_msec;
        if (measured_distance >= 19 && measured_distance <= 21) begin
            $display("Time=%0t ns: TEST PASSED - Measured distance %0d cm is within range of expected 20cm", 
                    $time, measured_distance);
            test_pass_count = test_pass_count + 1;
        end else begin
            $display("Time=%0t ns: TEST FAILED - Measured distance %0d cm is outside expected range", 
                    $time, measured_distance);
            test_fail_count = test_fail_count + 1;
        end
        
        // Test Case 3: Timeout test - disable echo generation
        test_scenario = 3;
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
        
        // Verify test results for scenario 3
        if (timeout_detected && DUT.U_cu.fsm_error) begin
            $display("Time=%0t ns: TEST PASSED - Timeout correctly detected and error flag set", $time);
            test_pass_count = test_pass_count + 1;
        end else begin
            $display("Time=%0t ns: TEST FAILED - Timeout not properly handled", $time);
            test_fail_count = test_fail_count + 1;
        end
        
        // Test Case 4: Error recovery after timeout
        test_scenario = 4;
        test_count = test_count + 1;
        $display("Time=%0t ns: Starting test scenario %0d - Error recovery test", 
                $time, test_scenario);
        enable_echo = 1; // Re-enable echo generation
        
        btn_start = 1;
        #5000;
        btn_start = 0;
        
        // Wait briefly to check if error flag is cleared
        #10000;
        
        // Verify initial part of test scenario 4
        if (!DUT.U_cu.fsm_error) begin
            $display("Time=%0t ns: TEST PART 1 PASSED - Error flag cleared by button press", $time);
        end else begin
            $display("Time=%0t ns: TEST PART 1 FAILED - Error flag not cleared", $time);
            test_fail_count = test_fail_count + 1;
        end
        
        // Wait for measurement to complete
        #((CLK_PERIOD*290000)/SIM_ACCEL);
        
        // Verify second part of test scenario 4
        measured_distance = dut_msec;
        if (measured_distance >= 19 && measured_distance <= 21) begin
            $display("Time=%0t ns: TEST PART 2 PASSED - System recovered and measured correctly: %0d cm", 
                    $time, measured_distance);
            test_pass_count = test_pass_count + 1;
        end else begin
            $display("Time=%0t ns: TEST PART 2 FAILED - System did not recover properly", $time);
            test_fail_count = test_fail_count + 1;
        end
        
        // Test Case 5: Reset during measurement
        test_scenario = 5;
        test_count = test_count + 1;
        $display("Time=%0t ns: Starting test scenario %0d - Reset during measurement", 
                $time, test_scenario);
        
        btn_start = 1;
        #5000;
        btn_start = 0;
        
        // Wait for trigger to start
        #10000;
        
        // Apply reset in the middle of measurement
        reset = 1;
        #100;
        reset = 0;
        $display("Time=%0t ns: Applied reset during measurement", $time);
        
        // Verify system returns to IDLE state after reset
        #100;
        if (cu_current_state == 2'b00) begin
            $display("Time=%0t ns: TEST PART 1 PASSED - System returned to IDLE state after reset", $time);
        end else begin
            $display("Time=%0t ns: TEST PART 1 FAILED - System did not return to IDLE state", $time);
            test_fail_count = test_fail_count + 1;
        end
        
        // Allow stabilization and start new measurement
        #10000;
        btn_start = 1;
        #5000;
        btn_start = 0;
        
        // Wait for final measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Verify system can perform measurement after reset
        measured_distance = dut_msec;
        if (measured_distance >= 19 && measured_distance <= 21) begin
            $display("Time=%0t ns: TEST PART 2 PASSED - System recovered after reset: %0d cm", 
                    $time, measured_distance);
            test_pass_count = test_pass_count + 1;
        end else begin
            $display("Time=%0t ns: TEST PART 2 FAILED - System did not recover after reset", $time);
            test_fail_count = test_fail_count + 1;
        end
        
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
    
    // Enhanced monitor for important signals including FSM state
    initial begin
        $display("Time\t\tReset\tBtn\tTrigger\tEcho\tLED\tCU_State\tTimeout\tDistance");
        forever begin
            #(CLK_PERIOD*10000);
            $display("%0t ns\t%b\t%b\t%b\t%b\t%b\t%b\t\t%0d\t%0d",
                     $time, reset, btn_start, trigger, echo, led, 
                     cu_current_state, cu_timeout_counter, dut_msec);
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
