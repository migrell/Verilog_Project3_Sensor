module dut_ctr (
    input clk,
    input rst,
    input btn_start,
    input tick_counter,
    
    output reg sensor_data,
    output reg [3:0] current_state,
    output reg [7:0] dnt_data,
    output reg [7:0] dnt_sensor_data,
    output reg dnt_io
);

    // State declaration
    localparam IDLE = 2'b00, START = 2'b01, WAIT = 2'b10, READ = 2'b11;
    
    // Timing parameters
    localparam TICK_SEC = 18; // 18msec for start signal
    localparam WAIT_TIME = 30; // 30msec for wait state
    
    reg [1:0] state, next_state;
    reg [7:0] tick_count;
    
    // State register
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tick_count <= 0;
        end else begin
            state <= next_state;
            if (tick_counter)
                tick_count <= tick_count + 1;
        end
    end
    
    // Next state logic
    always @(*) begin
        // Default assignments
        next_state = state;
        dnt_io = 1'b1; // Default high based on timing diagram
        
        case (state)
            IDLE: begin
                if (btn_start == 1) begin
                    next_state = START;
                    dnt_data = 0;
                end
            end
            
            START: begin
                dnt_io = 1'b0; // Pull low in START state
                if (tick_count >= TICK_SEC) begin
                    next_state = WAIT;
                end
            end
            
            WAIT: begin
                dnt_io = 1'b1; // Pull high in WAIT state
                if (tick_count >= WAIT_TIME) begin
                    next_state = READ;
                end
            end
            
            READ: begin
                dnt_io = 1'b0; // Set low for read operation
                next_state = IDLE; // Return to IDLE after READ
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Output logic
    always @(posedge clk) begin
        if (rst) begin
            sensor_data <= 0;
            current_state <= 0;
            dnt_sensor_data <= 0;
        end else begin
            current_state <= state;
            // Add sensor data reading logic here
            if (state == READ) begin
                dnt_sensor_data <= dnt_data; // Update sensor data in READ state
            end
        end
    end

endmodule




















    

