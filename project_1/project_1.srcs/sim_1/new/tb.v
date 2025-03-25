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
    parameter CLK_PERIOD = 10; // 10ns for 100MHz
    
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
        forever #(CLK_PERIOD/2) clk = ~clk; // 100MHz clock
    end
    
    // Main test sequence
    initial begin
        // Initialize signals
        reset = 0;
        echo = 0;
        btn_start = 0;
        
        // Apply reset
        #100;
        reset = 1;
        #100;
        reset = 0;
        #100;
        
        // Display test starting
        $display("Starting Ultrasonic Distance Meter Test");
        
        // Test Scenario 1: Normal measurement cycle
        $display("Scenario 1: Normal measurement cycle - 20cm distance");
        btn_start = 1;
        #(CLK_PERIOD*20); // Hold button for a short time
        btn_start = 0;
        
        // Wait for trigger pulse to complete
        wait(trigger == 1);
        $display("Trigger pulse started at %0t ns", $time);
        wait(trigger == 0);
        $display("Trigger pulse ended at %0t ns", $time);
        
        // Simulate delay before echo returns (proportional to distance)
        // For 20cm, echo should return after ~1160us (20cm * 2 / 34300cm/s * 1000000)
        // At 100MHz, this is 116,000 clock cycles
        #(CLK_PERIOD*3000); // Small delay before echo rising edge
        
        // Echo pulse starts (rising edge)
        echo = 1;
        $display("Echo pulse started at %0t ns", $time);
        
        // Echo pulse duration for 20cm = ~1160us
        // At 100MHz, this is 116,000 clock cycles
        #(CLK_PERIOD*116000);
        
        // Echo pulse ends (falling edge)
        echo = 0;
        $display("Echo pulse ended at %0t ns - Distance measured: 20cm", $time);
        
        // Allow system to process the measurement
        #(CLK_PERIOD*10000);
        
        // Test Scenario 2: No echo returns (timeout)
        $display("\nScenario 2: No echo returns (timeout)");
        btn_start = 1;
        #(CLK_PERIOD*20);
        btn_start = 0;
        
        // Wait for trigger pulse to complete
        wait(trigger == 1);
        $display("Trigger pulse started at %0t ns", $time);
        wait(trigger == 0);
        $display("Trigger pulse ended at %0t ns", $time);
        
        // No echo returns, wait for timeout period
        // WAIT_ECHO_TIMEOUT is 25_000_000 clock cycles (250ms)
        #(CLK_PERIOD*26_000_000); // Slightly longer than timeout
        $display("Timeout occurred at %0t ns", $time);
        
        // Check if error flag is set (should see LED blinking)
        $display("System should be in error state now");
        
        // Test Scenario 3: Error recovery using button
        $display("\nScenario 3: Error recovery using button");
        btn_start = 1;
        #(CLK_PERIOD*20);
        btn_start = 0;
        $display("Button pressed to clear error state at %0t ns", $time);
        
        // Wait to observe error recovery
        #(CLK_PERIOD*10000);
        
        // Test Scenario 4: Another normal measurement after recovery
        $display("\nScenario 4: Normal measurement after recovery - 50cm distance");
        btn_start = 1;
        #(CLK_PERIOD*20);
        btn_start = 0;
        
        // Wait for trigger pulse to complete
        wait(trigger == 1);
        $display("Trigger pulse started at %0t ns", $time);
        wait(trigger == 0);
        $display("Trigger pulse ended at %0t ns", $time);
        
        // Simulate delay for 50cm distance
        #(CLK_PERIOD*3000);
        
        // Echo pulse starts
        echo = 1;
        $display("Echo pulse started at %0t ns", $time);
        
        // Echo pulse duration for 50cm
        #(CLK_PERIOD*290000); // 50cm * 2 / 34300 * 1000000 ≈ 2900us
        
        // Echo pulse ends
        echo = 0;
        $display("Echo pulse ended at %0t ns - Distance measured: 50cm", $time);
        
        // Allow system to process the measurement
        #(CLK_PERIOD*10000);
        
        // End simulation
        $display("\nTest completed at %0t ns", $time);
        #(CLK_PERIOD*1000);
        $finish;
    end
    
    // Monitor important signals
    initial begin
        $monitor("Time=%0t ns, Reset=%b, Btn=%b, Trigger=%b, Echo=%b, LED=%b",
                 $time, reset, btn_start, trigger, echo, led);
    end
    
endmodule