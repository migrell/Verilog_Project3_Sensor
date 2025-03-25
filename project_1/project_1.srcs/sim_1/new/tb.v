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
    
    // Monitor for important signals
    initial begin
        $display("Time\t\tReset\tBtnStart\tTrigger\tEcho\tLED\tFND_comm\tFND_font");
        $monitor("%0t ns\t%b\t%b\t\t%b\t%b\t%b\t%b\t%h",
                 $time, reset, btn_start, trigger, echo, led, fnd_comm, fnd_font);
    end
    
    // Echo generation process
    initial begin
        forever begin
            @(posedge trigger); // Wait for trigger signal to go HIGH
            $display("Time=%0t ns: Trigger detected HIGH", $time);
            
            @(negedge trigger); // Wait for trigger signal to go LOW
            $display("Time=%0t ns: Trigger detected LOW", $time);
            
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
    
    // Main test sequence with improved timing
    initial begin
        // Initialize signals
        reset = 0;
        echo = 0;
        btn_start = 0;
        
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
        
        // Press button to start measurement - hold longer to ensure detection
        btn_start = 1;
        #2000; // Hold button for 2us
        btn_start = 0;
        $display("Time=%0t ns: Button released", $time);
        
        // Wait for complete measurement cycle
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Test Case 2: Another measurement
        $display("Time=%0t ns: Starting second measurement test", $time);
        
        btn_start = 1;
        #2000;
        btn_start = 0;
        
        // Wait for measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // Test Case 3: Test reset functionality
        $display("Time=%0t ns: Testing reset functionality", $time);
        reset = 1;
        #100;
        reset = 0;
        
        // Wait and start another measurement
        #10000;
        btn_start = 1;
        #2000;
        btn_start = 0;
        
        // Wait for measurement to complete
        #((CLK_PERIOD*300000)/SIM_ACCEL);
        
        // End simulation
        $display("Time=%0t ns: Simulation complete", $time);
        #10000;
        $finish;
    end
    
endmodule