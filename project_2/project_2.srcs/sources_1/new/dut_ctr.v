module dut_ctr (
    input clk,
    input rst,
    input btn_start,
    input tick_counter,

    output reg sensor_data,
    output reg [3:0] current_state,
    output reg [7:0] dnt_data,
    output reg [7:0] dnt_sensor_data,
    output reg dnt_io,

    // FSM 상태 모니터링을 위한 출력 추가
    output reg idle,
    output reg start,
    output reg wait_state,  // 'wait'은 예약어이므로 wait_state로 명명
    output reg read
);

    // 상태 정의 확장
    localparam IDLE = 4'b0000;
    localparam START = 4'b0001;
    localparam WAIT = 4'b0010;
    localparam SYNC_LOW = 4'b0011;  // 센서 응답 LOW 기다림 (80us)
    localparam SYNC_HIGH = 4'b0100; // 센서 응답 HIGH 기다림 (80us)
    localparam DATA_SYNC = 4'b0101; // 데이터 비트 시작 감지 (50us LOW)
    localparam DATA_BIT = 4'b0110;  // 데이터 비트 값 읽기 (26-70us HIGH)
    localparam STOP = 4'b0111;      // 데이터 수신 완료
    localparam READ = 4'b1000;      // 기존 READ 상태 유지

     // 타이밍 파라미터
    localparam TICK_SEC = 18;      // 18msec for start signal
    localparam WAIT_TIME = 30;     // 30msec for wait state
    localparam SYNC_CNT = 8;       // 80us for sync signals (10us tick 기준)
    localparam DATA_SYNC_CNT = 5;  // 50us for data bit start
    localparam DATA_0_CNT = 3;     // ~30us for '0' bit
    localparam DATA_1_CNT = 7;     // ~70us for '1' bit
    localparam STOP_CNT = 5;       // 종료 후 대기 시간
    localparam TIME_OUT = 100;     // 타임아웃 카운터

    reg [1:0] state, next_state;
    reg [7:0] tick_count;
    reg [5:0] bit_count;
    reg[39:0] received_data;
    reg data_bit;
    reg prev_dht_io;

    // 상태 레지스터 업데이트
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tick_count <= 0;
            bit_count <=0;
            received_data <=0;
            prev_dht_io <=1;
        end else begin
            state <= next_state;
            prev_dht_io <= dnt_io;

        if(tick_counter)
            tick_count <= tick_count +1;

            if(state == DATA_BIT && next_state == DATA_SYNC)begin
                received_data <= {received_data[38:0], data_bit};
                bit_count <= bit_count +1;
            end

        if(state != next_state)
            tick_count <=0;


        end
    end

    // FSM 상태 출력 변수 업데이트 로직 (추가)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            idle <= 1'b1;
            start <= 1'b0;
            wait_state <= 1'b0;
            read <= 1'b0;
        end else begin
            // 각 상태에 따라 출력 설정
            case (state)
                IDLE: begin
                    idle <= 1'b1;
                    start <= 1'b0;
                    wait_state <= 1'b0;
                    read <= 1'b0;
                end
                START: begin
                    idle <= 1'b0;
                    start <= 1'b1;
                    wait_state <= 1'b0;
                    read <= 1'b0;
                end
                WAIT: begin
                    idle <= 1'b0;
                    start <= 1'b0;
                    wait_state <= 1'b1;
                    read <= 1'b0;
                end
                READ: begin
                    idle <= 1'b0;
                    start <= 1'b0;
                    wait_state <= 1'b0;
                    read <= 1'b1;
                end
                default: begin
                    idle <= 1'b1;
                    start <= 1'b0;
                    wait_state <= 1'b0;
                    read <= 1'b0;
                end
            endcase
        end
    end
        // 다음 상태 로직
    always @(*) begin
        // 기본값 설정
        next_state = state;
        dnt_io = 1'b1;  // 기본값 HIGH
        data_bit = 1'b0; // 기본 데이터 비트 0
        
        case (state)
            IDLE: begin
                if (btn_start == 1) begin
                    next_state = START;
                    dnt_data = 0;
                end
            end
            
            START: begin
                dnt_io = 1'b0;  // START 상태에서 LOW 출력
                if (tick_count >= TICK_SEC) begin
                    next_state = WAIT;
                end
            end
            
            WAIT: begin
                dnt_io = 1'b1;  // WAIT 상태에서 HIGH 출력 (풀업)
                if (tick_count >= WAIT_TIME) begin
                    next_state = SYNC_LOW;
                end
            end
            
            SYNC_LOW: begin
                // 입력 모드로 전환 (센서로부터 응답 대기)
                // 센서의 80us LOW 응답 감지
                if (!dnt_io && tick_count >= SYNC_CNT) begin
                    next_state = SYNC_HIGH;
                end else if (tick_count >= TIME_OUT) begin
                    // 타임아웃 - 응답 없음
                    next_state = IDLE;
                end
            end
            
            SYNC_HIGH: begin
                // 센서의 80us HIGH 응답 감지
                if (dnt_io && tick_count >= SYNC_CNT) begin
                    next_state = DATA_SYNC;
                    bit_count = 0;  // 비트 카운터 초기화
                end else if (tick_count >= TIME_OUT) begin
                    // 타임아웃
                    next_state = IDLE;
                end
            end
            
            DATA_SYNC: begin
                // 비트 데이터 전송 시작 감지 (50us LOW)
                if (!dnt_io && tick_count >= DATA_SYNC_CNT) begin
                    next_state = DATA_BIT;
                end else if (bit_count >= 40) begin
                    // 40비트 모두 수신 완료
                    next_state = STOP;
                end else if (tick_count >= TIME_OUT) begin
                    // 타임아웃
                    next_state = IDLE;
                end
            end
            
            DATA_BIT: begin
                // 비트 값 결정 (HIGH 시간 측정)
                if (dnt_io) begin
                    // HIGH 신호가 임계값(DATA_0_CNT)보다 길면 '1', 짧으면 '0'
                    if (tick_count >= DATA_1_CNT) begin
                        data_bit = 1'b1;  // '1' 비트
                        next_state = DATA_SYNC;
                    end else if (tick_count >= DATA_0_CNT && !dnt_io && prev_dht_io) begin
                        // HIGH에서 LOW로 전환 감지됨
                        data_bit = 1'b0;  // '0' 비트
                        next_state = DATA_SYNC;
                    end
                end
                
                if (tick_count >= TIME_OUT) begin
                    // 타임아웃
                    next_state = IDLE;
                end
            end
            
            STOP: begin
                // 데이터 수신 완료
                if (tick_count >= STOP_CNT) begin
                    next_state = READ;
                end
            end
            
            READ: begin
                dnt_io = 1'b0;  // READ 상태에서 LOW 출력
                next_state = IDLE;  // 바로 IDLE로 복귀
            end
            
            default: next_state = IDLE;
        endcase
    end



    // 출력 로직 (변경 없음)
    always @(posedge clk) begin
        if (rst) begin
            sensor_data <= 0;
            current_state <= 0;
            dnt_sensor_data <= 0;
        end else begin
            current_state <= state;

            if (state == STOP) begin
                 dnt_sensor_data <= received_data[39:32];
            end
        end
    end

endmodule

// module dut_ctr (
//     input clk,
//     input rst,
//     input btn_start,
//     input tick_counter,

//     output reg sensor_data,
//     output reg [3:0] current_state,
//     output reg [7:0] dnt_data,
//     output reg [7:0] dnt_sensor_data,
//     output reg dnt_io
// );

//     // parameters START_CNT = 1800, WAIT_CNT = 3, SYNC_CNT = 8 , DATA_SYNC= 5, DATA_0 = 4; , DATA_1 = 7, DATA_1 = 7,
//     //            STOP_CNT = 5 , TIME_OUT = 2000; 

//     // State declaration
//     localparam IDLE = 2'b00, START = 2'b01, WAIT = 2'b10, READ = 2'b11;

//     // Timing parameters
//     localparam TICK_SEC = 18; // 18msec for start signal
//     localparam WAIT_TIME = 30; // 30msec for wait state

//     reg [1:0] state, next_state;
//     reg [7:0] tick_count;

//     // State register
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state <= IDLE;
//             tick_count <= 0;
//         end else begin
//             state <= next_state;
//             if (tick_counter)
//                 tick_count <= tick_count + 1;
//         end
//     end

//     // Next state logic
//     always @(*) begin
//         // Default assignments
//         next_state = state;
//         dnt_io = 1'b1; // Default high based on timing diagram

//         case (state)
//             IDLE: begin
//                 if (btn_start == 1) begin
//                     next_state = START;
//                     dnt_data = 0;
//                 end
//             end

//             START: begin
//                 dnt_io = 1'b0; // Pull low in START state
//                 if (tick_count >= TICK_SEC) begin
//                     next_state = WAIT;
//                 end
//             end

//             WAIT: begin
//                 dnt_io = 1'b1; // Pull high in WAIT state
//                 if (tick_count >= WAIT_TIME) begin
//                     next_state = READ;
//                 end
//             end

//             READ: begin
//                 dnt_io = 1'b0; // Set low for read operation
//                 next_state = IDLE; // Return to IDLE after READ
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // Output logic
//     always @(posedge clk) begin
//         if (rst) begin
//             sensor_data <= 0;
//             current_state <= 0;
//             dnt_sensor_data <= 0;
//         end else begin
//             current_state <= state;
//             // Add sensor data reading logic here
//             if (state == READ) begin
//                 dnt_sensor_data <= dnt_data; // Update sensor data in READ state
//             end
//         end
//     end

// endmodule






















