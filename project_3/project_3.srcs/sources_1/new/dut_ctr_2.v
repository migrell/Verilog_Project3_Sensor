module dut_ctr(
    input clk,
    input rst,
    input btn_run,
    input tick_counter,
    input btn_next,

    input sensor_data,   // output reg에서 input으로 변경
    output reg [3:0] current_state,
    output reg [7:0] dnt_data,
    output reg [7:0] dnt_sensor_data,
    output reg dnt_io,

    output reg idle,
    output reg start,
    output reg wait_state,
    output reg sync_low_out,
    output reg sync_high_out,
    output reg data_sync_out,
    output reg data_bit_out,
    output reg stop_out,
    output reg read
);
    localparam IDLE = 4'b0000;
    localparam START = 4'b0001;
    localparam WAIT = 4'b0010;
    localparam SYNC_LOW = 4'b0011;
    localparam SYNC_HIGH = 4'b0100;
    localparam DATA_SYNC = 4'b0101;
    localparam DATA_BIT = 4'b0110;
    localparam STOP = 4'b0111;
    localparam READ = 4'b1000;
    localparam MAX_BITS = 3;

    reg [3:0] state;
    reg [5:0] bit_count;
    reg [39:0] received_data;

    reg [2:0] btn_sync;
    reg btn_edge;
    reg [2:0] next_btn_sync;
    reg next_btn_edge;

    reg [9:0] tick_count;
    reg [7:0] delay_counter;
    reg [7:0] bit_timeout_counter;
    reg tick_prev;
    
    // 온습도 데이터 저장 변수 추가
    reg [7:0] temperature;  // 온도 저장
    reg [7:0] humidity;     // 습도 저장
    reg is_temp_display;    // 온도/습도 표시 선택
    
    // 현재 비트 값 저장 변수 (case문 밖으로 이동)
    reg bit_value;
    
    // 펄스 관리 변수
    reg pulse_active;
    reg [19:0] pulse_counter;

    // 엣지 감지와 펄스 처리를 위한 always 블록
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_sync <= 3'b000;
            btn_edge <= 1'b0;
            next_btn_sync <= 3'b000;
            next_btn_edge <= 1'b0;
            tick_prev <= 0;
            pulse_active <= 0;
            pulse_counter <= 0;
            // sensor_data <= 0; // 이 줄 제거
        end else begin
            btn_sync <= {btn_sync[1:0], btn_run};
            btn_edge <= (btn_sync[1] & ~btn_sync[2]);
            next_btn_sync <= {next_btn_sync[1:0], btn_next};
            next_btn_edge <= (next_btn_sync[1] & ~next_btn_sync[2]);
            tick_prev <= tick_counter;
            
            // 펄스 신호 관리 로직
            if (pulse_active) begin
                if (pulse_counter < 20'd50000) begin  // 약 0.5ms 지속 (100MHz 클럭 기준)
                    pulse_counter <= pulse_counter + 1;
                    // sensor_data <= 1'b1;  // 이 줄 제거
                end else begin
                    pulse_active <= 0;
                    pulse_counter <= 0;
                    // sensor_data <= 1'b0;  // 이 줄 제거
                end
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tick_count <= 0;
            bit_count <= 0;
            received_data <= 0;
            dnt_data <= 0;
            dnt_io <= 1'b1;
            current_state <= IDLE;
            dnt_sensor_data <= 0;
            delay_counter <= 0;
            bit_timeout_counter <= 0;
            temperature <= 8'd25;  // 기본 온도값 25°C
            humidity <= 8'd50;     // 기본 습도값 50%
            is_temp_display <= 1;  // 기본적으로 온도 표시
            bit_value <= 0;        // 비트 값 초기화

            idle <= 1'b1;
            start <= 1'b0;
            wait_state <= 1'b0;
            sync_low_out <= 1'b0;
            sync_high_out <= 1'b0;
            data_sync_out <= 1'b0;
            data_bit_out <= 1'b0;
            stop_out <= 1'b0;
            read <= 1'b0;
        end else begin
            idle <= 1'b0;
            start <= 1'b0;
            wait_state <= 1'b0;
            sync_low_out <= 1'b0;
            sync_high_out <= 1'b0;
            data_sync_out <= 1'b0;
            data_bit_out <= 1'b0;
            stop_out <= 1'b0;
            read <= 1'b0;

            if (tick_counter & ~tick_prev) begin
                delay_counter <= delay_counter + 1;
                bit_timeout_counter <= bit_timeout_counter + 1;
            end
            
            // 온도/습도 디스플레이 전환 (IDLE 상태에서만)
            if (state == IDLE && next_btn_edge) begin
                is_temp_display <= ~is_temp_display;
                if (is_temp_display) 
                    dnt_sensor_data <= humidity;  // 다음은 습도 표시
                else 
                    dnt_sensor_data <= temperature;  // 다음은 온도 표시
            end

            case (state)
                IDLE: begin
                    idle <= 1'b1;
                    dnt_io <= 1'b1;
                    current_state <= IDLE;
                    if (btn_edge) begin
                        state <= START;
                        delay_counter <= 0;
                        bit_count <= 0;
                        bit_timeout_counter <= 0;
                    end
                end
                START: begin
                    start <= 1'b1;
                    dnt_io <= 1'b0;
                    current_state <= START;
                    if (delay_counter >= 50) begin
                        state <= WAIT;
                        delay_counter <= 0;
                    end
                end
                WAIT: begin
                    wait_state <= 1'b1;
                    dnt_io <= 1'b1;
                    current_state <= WAIT;
                    if (delay_counter >= 50) begin
                        state <= SYNC_LOW;
                        delay_counter <= 0;
                    end
                end
                SYNC_LOW: begin
                    sync_low_out <= 1'b1;
                    dnt_io <= 1'b0;
                    current_state <= SYNC_LOW;
                    if (delay_counter >= 50) begin
                        state <= SYNC_HIGH;
                        delay_counter <= 0;
                    end
                end
                SYNC_HIGH: begin
                    sync_high_out <= 1'b1;
                    dnt_io <= 1'b1;
                    current_state <= SYNC_HIGH;
                    if (delay_counter >= 50) begin
                        state <= DATA_SYNC;
                        delay_counter <= 0;
                    end
                end
                DATA_SYNC: begin
                    data_sync_out <= 1'b1;
                    dnt_io <= 1'b0;
                    current_state <= DATA_SYNC;
                    if (delay_counter >= 50) begin
                        state <= DATA_BIT;
                        delay_counter <= 0;
                        bit_timeout_counter <= 0;
                    end
                end
                DATA_BIT: begin
                    data_bit_out <= 1'b1;
                    dnt_io <= 1'b1;
                    current_state <= DATA_BIT;
                    
                    // 비트 값 결정 - case 문 외부로 이동
                    if (bit_count < 8)      // 첫 8비트: 습도 정수부 
                        bit_value = bit_count[0];
                    else if (bit_count < 16) // 다음 8비트: 습도 소수부
                        bit_value = ~bit_count[0];
                    else if (bit_count < 24) // 다음 8비트: 온도 정수부
                        bit_value = bit_count[1];
                    else                     // 마지막 8비트: 온도 소수부
                        bit_value = ~bit_count[1];
                    
                    if (next_btn_edge || bit_timeout_counter >= 30) begin
                        received_data <= {received_data[38:0], bit_value};
                        pulse_active <= 1'b1;  // 펄스 활성화 플래그 설정 (sensor_data 직접 할당하지 않음)
                        pulse_counter <= 0;
                        bit_count <= bit_count + 1;
                        delay_counter <= 0;
                        bit_timeout_counter <= 0;
                        state <= STOP;
                    end
                end
                STOP: begin
                    stop_out <= 1'b1;
                    dnt_io <= 1'b1;
                    current_state <= STOP;
                    if (delay_counter >= 100) begin
                        state <= READ;
                        delay_counter <= 0;
                    end
                end
                READ: begin
                    read <= 1'b1;
                    dnt_io <= 1'b0;
                    current_state <= READ;
                    
                    // 데이터 처리 (비트 카운트가 32 이상이면 온도/습도 업데이트)
                    if (bit_count >= 32) begin
                        // DHT 센서 형식에 맞게 데이터 처리 (실제 센서 동작 시뮬레이션)
                        humidity <= received_data[39:32];      // 습도 정수부
                        temperature <= received_data[23:16];   // 온도 정수부
                        
                        // 현재 표시 모드에 따라 디스플레이 데이터 설정
                        if (is_temp_display)
                            dnt_sensor_data <= received_data[23:16];  // 온도
                        else
                            dnt_sensor_data <= received_data[39:32];  // 습도
                    end else if (bit_count > 0) begin
                        // 충분한 데이터를 수집하지 못한 경우, 값 시뮬레이션
                        humidity <= humidity + 1;
                        temperature <= temperature + 1;
                        
                        // 현재 표시 모드에 따라 디스플레이 데이터 설정
                        if (is_temp_display)
                            dnt_sensor_data <= temperature + 1;
                        else
                            dnt_sensor_data <= humidity + 1;
                    end
                    
                    if (delay_counter >= 50) begin
                        state <= IDLE;
                        delay_counter <= 0;
                    end
                end
                default: begin
                    state <= IDLE;
                    current_state <= IDLE;
                end
            endcase
        end
    end
endmodule


















