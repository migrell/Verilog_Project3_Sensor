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

    // FSM 상태 모니터링을 위한 출력 (9개 상태 모두 표시)
    output reg idle,           // IDLE 상태
    output reg start,          // START 상태
    output reg wait_state,     // WAIT 상태 ('wait'은 예약어)
    output reg sync_low_out,   // SYNC_LOW 상태 (추가)
    output reg sync_high_out,  // SYNC_HIGH 상태 (추가)
    output reg data_sync_out,  // DATA_SYNC 상태 (추가)
    output reg data_bit_out,   // DATA_BIT 상태 (추가)
    output reg stop_out,       // STOP 상태 (추가)
    output reg read            // READ 상태
);

    // 상태 정의 확장 (변경 없음)
    localparam IDLE = 4'b0000;
    localparam START = 4'b0001;
    localparam WAIT = 4'b0010;
    localparam SYNC_LOW = 4'b0011;
    localparam SYNC_HIGH = 4'b0100;
    localparam DATA_SYNC = 4'b0101;
    localparam DATA_BIT = 4'b0110;
    localparam STOP = 4'b0111;
    localparam READ = 4'b1000;

    // 타이밍 파라미터 (원래 값으로 복원)
    localparam TICK_SEC = 18;       // 18msec for start signal
    localparam WAIT_TIME = 30;      // 30msec for wait state
    localparam SYNC_CNT = 8;        // 80us for sync signals (10us tick 기준)
    localparam DATA_SYNC_CNT = 5;   // 50us for data bit start
    localparam DATA_0_CNT = 3;      // ~30us for '0' bit
    localparam DATA_1_CNT = 7;      // ~70us for '1' bit
    localparam STOP_CNT = 5;        // 종료 후 대기 시간
    localparam TIME_OUT = 100;      // 타임아웃 카운터
    
    // 디버깅 지연 타이머 제거
    localparam DEBUG_DELAY = 0;    // 디버깅 지연 비활성화

    reg [3:0] state, next_state;
    reg [9:0] tick_count;            // 더 큰 타이머 값을 위해 크기 증가 (7비트->10비트)
    reg [5:0] bit_count;
    reg [39:0] received_data;
    reg data_bit;
    reg prev_dht_io;
    reg [39:0] data_reg;
    reg [7:0] count_reg;
    
    // 디버깅용 타이머 추가
    reg [9:0] debug_timer;
    
    // 다음 값 계산을 위한 임시 변수들
    reg [5:0] next_bit_count;
    reg [39:0] next_data_reg;
    reg next_data_bit;
    
    // 디버깅 타이머 카운터 - 제거하지 않고 유지하되 값을 0으로 설정
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            debug_timer <= 0;
        end else begin
            debug_timer <= 0;  // 항상 0으로 유지하여 지연 없애기
        end
    end
    
    // 상태 레지스터 및 변수 업데이트
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tick_count <= 0;
            bit_count <= 0;
            received_data <= 0;
            prev_dht_io <= 1;
            data_reg <= 0;
            count_reg <= 0;
            data_bit <= 0;
            debug_timer <= 0;
        end else begin
            // 디버깅 타이머 무시하고 항상 상태 전환 허용
            state <= next_state;
            
            // 상태 변화 시 tick_count 초기화 확실히 적용
            if (state != next_state) begin
                tick_count <= 0;
            end
            
            prev_dht_io <= dnt_io;
            
            // 순차적으로 한 번에 하나씩만 업데이트
            bit_count <= next_bit_count;
            data_reg <= next_data_reg;
            data_bit <= next_data_bit;
            
            // 타이머 카운트 - 상태가 변했을 때 초기화 제외하고는 항상 증가
            if (tick_counter && state == next_state)
                tick_count <= tick_count + 1;
                
            // 데이터 비트가 확정되면 received_data에 저장
            if (state == DATA_BIT && next_state == DATA_SYNC) begin
                received_data <= {received_data[38:0], data_bit};
            end
            
            // count_reg 업데이트 로직 (필요한 경우)
            if (state == IDLE && next_state == START) begin
                count_reg <= 0;
            end else if (state == SYNC_HIGH && next_state == DATA_SYNC) begin
                count_reg <= 0;
            end
        end
    end

    // FSM 상태 출력 변수 업데이트 로직 (변경 없음)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
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
            // 모든 상태 출력 초기화
            idle <= 1'b0;
            start <= 1'b0;
            wait_state <= 1'b0;
            sync_low_out <= 1'b0;
            sync_high_out <= 1'b0;
            data_sync_out <= 1'b0;
            data_bit_out <= 1'b0;
            stop_out <= 1'b0;
            read <= 1'b0;
            
            // 현재 상태에 해당하는 출력만 활성화
            case (state)
                IDLE: idle <= 1'b1;
                START: start <= 1'b1;
                WAIT: wait_state <= 1'b1;
                SYNC_LOW: sync_low_out <= 1'b1;
                SYNC_HIGH: sync_high_out <= 1'b1;
                DATA_SYNC: data_sync_out <= 1'b1;
                DATA_BIT: data_bit_out <= 1'b1;
                STOP: stop_out <= 1'b1;
                READ: read <= 1'b1;
                default: idle <= 1'b1;
            endcase
        end
    end

    // 다음 상태 로직 (수정: 비트 카운트 조건 수정, 타이밍 정확도 향상)
    always @(*) begin
        // 기본값 설정 - 현재 값 유지
        next_state = state;
        dnt_io = 1'b1;
        next_bit_count = bit_count;
        next_data_reg = data_reg;
        next_data_bit = data_bit;
        dnt_data = dnt_data;  // 현재 값 유지
        
        case (state)
            IDLE: begin
                if (btn_start == 1) begin
                    next_state = START;
                    dnt_data = 0;
                    next_bit_count = 0;  // 비트 카운트 초기화
                end
            end
            
            START: begin
                dnt_io = 1'b0;  // START 상태에서 LOW 출력
                if (tick_count >= TICK_SEC) begin
                    next_state = WAIT;
                end
            end
            
            WAIT: begin
                dnt_io = 1'b1;  // WAIT 상태에서 HIGH 출력
                if (tick_count >= WAIT_TIME) begin
                    next_state = SYNC_LOW;
                end
            end
            
            SYNC_LOW: begin
                // 센서 응답 시뮬레이션
                dnt_io = (tick_count < SYNC_CNT/2) ? 1'b0 : 1'b1;
                
                if (tick_count >= SYNC_CNT) begin
                    next_state = SYNC_HIGH;
                end
            end
            
            SYNC_HIGH: begin
                // 센서 응답 시뮬레이션
                dnt_io = 1'b1;
                
                if (tick_count >= SYNC_CNT) begin
                    next_state = DATA_SYNC;
                    next_bit_count = 0;  // 비트 카운트 초기화
                end
            end
            
            DATA_SYNC: begin
                // 센서 응답 시뮬레이션
                dnt_io = (tick_count < DATA_SYNC_CNT/2) ? 1'b0 : 1'b1;
                
                if (tick_count >= DATA_SYNC_CNT) begin
                    if (bit_count >= 40) begin  // 3에서 40으로 수정 - 40비트 모두 읽기 위해
                        next_state = STOP;
                    end else begin
                        next_state = DATA_BIT;
                    end
                end
            end
            
            DATA_BIT: begin
                // 센서 응답 시뮬레이션
                dnt_io = 1'b1;
                
                if (tick_count >= DATA_1_CNT) begin
                    next_data_bit = 1'b1;  // '1' 비트
                    next_state = DATA_SYNC;
                    next_bit_count = bit_count + 1;  // 비트 카운트 증가
                end else if (tick_count >= DATA_0_CNT) begin
                    next_data_bit = 1'b0;  // '0' 비트
                    next_state = DATA_SYNC;
                    next_bit_count = bit_count + 1;  // 비트 카운트 증가
                end
            end
            
            STOP: begin
                if (tick_count >= STOP_CNT) begin
                    next_state = READ;
                end
            end
            
            READ: begin
                dnt_io = 1'b0;  // READ 상태에서 LOW 출력
                if (tick_count >= TICK_SEC/2) begin
                    next_state = IDLE;
                    next_bit_count = 0;  // 다음 사이클을 위한 비트 카운트 초기화
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    // 출력 로직
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
//     output reg dnt_io,

//     // FSM 상태 모니터링을 위한 출력 추가
//     output reg idle,
//     output reg start,
//     output reg wait_state,  // 'wait'은 예약어이므로 wait_state로 명명
//     output reg read
// );

//     // 상태 정의 확장
//     localparam IDLE = 4'b0000;
//     localparam START = 4'b0001;
//     localparam WAIT = 4'b0010;
//     localparam SYNC_LOW = 4'b0011;  // 센서 응답 LOW 기다림 (80us)
//     localparam SYNC_HIGH = 4'b0100; // 센서 응답 HIGH 기다림 (80us)
//     localparam DATA_SYNC = 4'b0101; // 데이터 비트 시작 감지 (50us LOW)
//     localparam DATA_BIT = 4'b0110;  // 데이터 비트 값 읽기 (26-70us HIGH)
//     localparam STOP = 4'b0111;      // 데이터 수신 완료
//     localparam READ = 4'b1000;      // 기존 READ 상태 유지

//     // 타이밍 파라미터
//     localparam TICK_SEC = 18;      // 18msec for start signal
//     localparam WAIT_TIME = 30;     // 30msec for wait state
//     localparam SYNC_CNT = 8;       // 80us for sync signals (10us tick 기준)
//     localparam DATA_SYNC_CNT = 5;  // 50us for data bit start
//     localparam DATA_0_CNT = 3;     // ~30us for '0' bit
//     localparam DATA_1_CNT = 7;     // ~70us for '1' bit
//     localparam STOP_CNT = 5;       // 종료 후 대기 시간
//     localparam TIME_OUT = 100;     // 타임아웃 카운터

//     reg [3:0] state, next_state;
//     reg [7:0] tick_count;
//     reg [5:0] bit_count;
//     reg [39:0] received_data;
//     reg data_bit;
//     reg prev_dht_io;
//     reg [39:0] data_reg, data_next;
//     reg [7:0] count_reg;  // count_reg 추가

//     // 상태 레지스터 업데이트
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state <= IDLE;
//             tick_count <= 0;
//             bit_count <= 0;
//             received_data <= 0;
//             prev_dht_io <= 1;
//             data_reg <= 0;
//             count_reg <= 0;
//         end else begin
//             state <= next_state;
//             prev_dht_io <= dnt_io;
//             data_reg <= data_next;  // data_reg 업데이트 추가

//             if(tick_counter)
//                 tick_count <= tick_count + 1;

//             if(state == DATA_BIT && next_state == DATA_SYNC) begin
//                 received_data <= {received_data[38:0], data_bit};
//                 bit_count <= bit_count + 1;
//             end

//             if(state != next_state)
//                 tick_count <= 0;
//         end
//     end

//     // FSM 상태 출력 변수 업데이트 로직 (추가)
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             idle <= 1'b1;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             read <= 1'b0;
//         end else begin
//             // 각 상태에 따라 출력 설정
//             case (state)
//                 IDLE: begin
//                     idle <= 1'b1;
//                     start <= 1'b0;
//                     wait_state <= 1'b0;
//                     read <= 1'b0;
//                 end
//                 START: begin
//                     idle <= 1'b0;
//                     start <= 1'b1;
//                     wait_state <= 1'b0;
//                     read <= 1'b0;
//                 end
//                 WAIT: begin
//                     idle <= 1'b0;
//                     start <= 1'b0;
//                     wait_state <= 1'b1;
//                     read <= 1'b0;
//                 end
//                 // SYNC_LOW, SYNC_HIGH, DATA_SYNC, DATA_BIT, STOP 상태에서도 READ 신호 활성화
//                 SYNC_LOW, SYNC_HIGH, DATA_SYNC, DATA_BIT, STOP, READ: begin
//                     idle <= 1'b0;
//                     start <= 1'b0;
//                     wait_state <= 1'b0;
//                     read <= 1'b1;
//                 end
//                 default: begin
//                     idle <= 1'b1;
//                     start <= 1'b0;
//                     wait_state <= 1'b0;
//                     read <= 1'b0;
//                 end
//             endcase
//         end
//     end

//     // 다음 상태 로직
//     always @(*) begin
//         // 기본값 설정
//         next_state = state;
//         dnt_io = 1'b1;  // 기본값 HIGH
//         data_bit = 1'b0; // 기본 데이터 비트 0
//         data_next = data_reg;  // 기본값 설정 추가

//         case (state)
//             IDLE: begin
//                 if (btn_start == 1) begin
//                     next_state = START;
//                     dnt_data = 0;
//                 end
//             end

//             START: begin
//                 dnt_io = 1'b0;  // START 상태에서 LOW 출력
//                 if (tick_count >= TICK_SEC) begin
//                     next_state = WAIT;
//                 end
//             end

//             WAIT: begin
//                 dnt_io = 1'b1;  // WAIT 상태에서 HIGH 출력 (풀업)
//                 if (tick_count >= WAIT_TIME) begin
//                     next_state = SYNC_LOW;
//                 end
//             end

//             SYNC_LOW: begin
//                 // 입력 모드로 전환 (센서로부터 응답 대기)
//                 // 센서의 80us LOW 응답 감지
//                 if (!dnt_io && tick_count >= SYNC_CNT) begin
//                     next_state = SYNC_HIGH;
//                 end else if (tick_count >= TIME_OUT) begin
//                     // 타임아웃 - 응답 없음
//                     next_state = IDLE;
//                 end

//                 // 추가된 데이터 처리 로직
//                 if (count_reg < 40) begin
//                     data_next[bit_count] = 1'b0;
//                     data_next = {1'b0, data_reg[38:0]}; // 데이터 쉬프트
//                 end else begin
//                     data_next[bit_count] = 1'b1;
//                 end
//             end

//             SYNC_HIGH: begin
//                 // 센서의 80us HIGH 응답 감지
//                 if (dnt_io && tick_count >= SYNC_CNT) begin
//                     next_state = DATA_SYNC;
//                     bit_count = 0;  // 비트 카운터 초기화
//                 end else if (tick_count >= TIME_OUT) begin
//                     // 타임아웃
//                     next_state = IDLE;
//                 end

//                 // 추가된 데이터 처리 로직
//                 if (count_reg < 40) begin
//                     data_next[bit_count] = 1'b0;
//                     data_next = {1'b0, data_reg[38:0]}; // 데이터 쉬프트
//                 end else begin
//                     data_next[bit_count] = 1'b1;
//                 end
//             end

//             DATA_SYNC: begin
//                 // 비트 데이터 전송 시작 감지 (50us LOW)
//                 if (!dnt_io && tick_count >= DATA_SYNC_CNT) begin
//                     next_state = DATA_BIT;
//                 end else if (bit_count >= 40) begin
//                     // 40비트 모두 수신 완료
//                     next_state = STOP;
//                 end else if (tick_count >= TIME_OUT) begin
//                     // 타임아웃
//                     next_state = IDLE;
//                 end

//                 // 추가된 데이터 처리 로직
//                 if (count_reg < 40) begin
//                     data_next[bit_count] = 1'b0;
//                     data_next = {1'b0, data_reg[38:0]}; // 데이터 쉬프트
//                 end else begin
//                     data_next[bit_count] = 1'b1;
//                 end
//             end

//             DATA_BIT: begin
//                 // 비트 값 결정 (HIGH 시간 측정)
//                 if (dnt_io) begin
//                     // HIGH 신호가 임계값(DATA_0_CNT)보다 길면 '1', 짧으면 '0'
//                     if (tick_count >= DATA_1_CNT) begin
//                         data_bit = 1'b1;  // '1' 비트
//                         next_state = DATA_SYNC;
//                     end else if (tick_count >= DATA_0_CNT && !dnt_io && prev_dht_io) begin
//                         // HIGH에서 LOW로 전환 감지됨
//                         data_bit = 1'b0;  // '0' 비트
//                         next_state = DATA_SYNC;
//                     end
//                 end

//                 if (tick_count >= TIME_OUT) begin
//                     // 타임아웃
//                     next_state = IDLE;
//                 end
//             end

//             STOP: begin
//                 // 데이터 수신 완료
//                 if (tick_count >= STOP_CNT) begin
//                     next_state = READ;
//                 end
//             end

//             READ: begin
//                 dnt_io = 1'b0;  // READ 상태에서 LOW 출력
//                 next_state = IDLE;  // 바로 IDLE로 복귀
//             end

//             default: next_state = IDLE;
//         endcase
//     end

//     // 출력 로직 추가
//     always @(posedge clk) begin
//         if (rst) begin
//             sensor_data <= 0;
//             current_state <= 0;
//             dnt_sensor_data <= 0;
//         end else begin
//             current_state <= state;

//             if (state == STOP) begin
//                 dnt_sensor_data <= received_data[39:32];
//             end
//         end
//     end

// endmodule

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






















