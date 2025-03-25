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
    parameter SIM_ACCEL = 1000; // Acceleration factor for simulation
    
    // DUT instantiation
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
        
        // Scenario 1: Reset operation test
        #100;
        reset = 1;
        #100;
        reset = 0;
        #100;
        
        // Scenario 2: Normal measurement cycle (20cm distance)
        btn_start = 1;
        #(CLK_PERIOD*20);
        btn_start = 0;
        
        // Wait for trigger pulse
        wait(trigger == 1);
        wait(trigger == 0);
        
        // Simulate delay before echo returns (for 20cm)
        #(CLK_PERIOD*3000/SIM_ACCEL);
        
        // Echo pulse starts
        echo = 1;
        
        // Echo pulse duration for 20cm (~1160us)
        #(CLK_PERIOD*116000/SIM_ACCEL);
        
        // Echo pulse ends
        echo = 0;
        
        // Allow system to process measurement
        #(CLK_PERIOD*10000/SIM_ACCEL);
        
        // Scenario 3: No echo returns (timeout)
        btn_start = 1;
        #(CLK_PERIOD*20);
        btn_start = 0;
        
        // Wait for trigger pulse
        wait(trigger == 1);
        wait(trigger == 0);
        
        // No echo returns, wait for timeout period
        #(CLK_PERIOD*25000000/SIM_ACCEL);
        
        // Check LED blinking for a few cycles
        repeat(3) begin
            wait(led == 4'b1111);
            wait(led == 4'b0000);
        end
        
        // Scenario 4: Error recovery using button
        btn_start = 1;
        #(CLK_PERIOD*20);
        btn_start = 0;
        
        // Wait to observe error recovery
        #(CLK_PERIOD*10000/SIM_ACCEL);
        
        // End simulation
        #(CLK_PERIOD*1000);
        $finish;
    end
    
    // Monitor important signals
    initial begin
        $monitor("Time=%0t ns, Trigger=%b, Echo=%b, LED=%b",
                 $time, trigger, echo, led);
    end
    
endmodule