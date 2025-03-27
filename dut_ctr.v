
// ----------------------
// [3] DUT Controller (FSM)
// ----------------------
module dut_ctr(
    input clk,
    input rst,
    input btn_start,
    input tick_counter,
    input btn_next,

    output reg sensor_data,
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

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_sync <= 3'b000;
            btn_edge <= 1'b0;
            next_btn_sync <= 3'b000;
            next_btn_edge <= 1'b0;
            tick_prev <= 0;
        end else begin
            btn_sync <= {btn_sync[1:0], btn_start};
            btn_edge <= (btn_sync[1] & ~btn_sync[2]);
            next_btn_sync <= {next_btn_sync[1:0], btn_next};
            next_btn_edge <= (next_btn_sync[1] & ~next_btn_sync[2]);
            tick_prev <= tick_counter;
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
            sensor_data <= 0;
            dnt_sensor_data <= 0;
            delay_counter <= 0;
            bit_timeout_counter <= 0;

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
                    if (next_btn_edge || bit_timeout_counter >= 30) begin
                        received_data <= {received_data[38:0], 1'b1};
                        sensor_data <= 1'b1;
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
                        dnt_sensor_data <= received_data[39:32];
                        delay_counter <= 0;
                    end
                end
                READ: begin
                    read <= 1'b1;
                    dnt_io <= 1'b0;
                    current_state <= READ;
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






// module dut_ctr (
//     input clk,
//     input rst,
//     input btn_start,
//     input tick_counter,
//     input btn_next,  // T17 핀에 연결될 추가 버튼 입력

//     output reg sensor_data,
//     output reg [3:0] current_state,
//     output reg [7:0] dnt_data,
//     output reg [7:0] dnt_sensor_data,
//     output reg dnt_io,

//     output reg idle,
//     output reg start,
//     output reg wait_state,
//     output reg sync_low_out,
//     output reg sync_high_out,
//     output reg data_sync_out,
//     output reg data_bit_out,
//     output reg stop_out,
//     output reg read
// );

//     localparam IDLE       = 4'b0000;
//     localparam START      = 4'b0001;
//     localparam WAIT       = 4'b0010;
//     localparam SYNC_LOW   = 4'b0011;
//     localparam SYNC_HIGH  = 4'b0100;
//     localparam DATA_SYNC  = 4'b0101;
//     localparam DATA_BIT   = 4'b0110;
//     localparam STOP       = 4'b0111;
//     localparam READ       = 4'b1000;

//     localparam MAX_BITS = 3;

//     reg [3:0] state;
//     reg [5:0] bit_count;
//     reg [39:0] received_data;

//     reg [2:0] btn_sync;
//     reg btn_edge;

//     reg [2:0] next_btn_sync;
//     reg next_btn_edge;

//     reg [9:0] tick_count;
//     reg [7:0] delay_counter;
//     reg tick_prev;

//     // 엣지 감지 블록
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             btn_sync <= 3'b000;
//             btn_edge <= 1'b0;
//             next_btn_sync <= 3'b000;
//             next_btn_edge <= 1'b0;
//             tick_prev <= 0;
//         end else begin
//             // btn_start rising edge
//             btn_sync <= {btn_sync[1:0], btn_start};
//             btn_edge <= (btn_sync[1] & ~btn_sync[2]);

//             // btn_next (T17)
//             next_btn_sync <= {next_btn_sync[1:0], btn_next};
//             next_btn_edge <= (next_btn_sync[1] & ~next_btn_sync[2]);

//             tick_prev <= tick_counter;
//         end
//     end

//     // FSM
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state <= IDLE;
//             tick_count <= 0;
//             bit_count <= 0;
//             received_data <= 0;
//             dnt_data <= 0;
//             dnt_io <= 1'b1;
//             current_state <= IDLE;
//             sensor_data <= 0;
//             dnt_sensor_data <= 0;
//             delay_counter <= 0;

//             idle <= 1'b1;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;
//         end else begin
//             idle <= 1'b0;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;

//             if (tick_counter & ~tick_prev) begin
//                 delay_counter <= delay_counter + 1;
//             end

//             case (state)
//                 IDLE: begin
//                     idle <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= IDLE;

//                     if (btn_edge) begin
//                         state <= START;
//                         delay_counter <= 0;
//                         bit_count <= 0;
//                     end
//                 end

//                 START: begin
//                     start <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= START;

//                     if (delay_counter >= 50) begin
//                         state <= WAIT;
//                         delay_counter <= 0;
//                     end
//                 end

//                 WAIT: begin
//                     wait_state <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= WAIT;

//                     if (delay_counter >= 50) begin
//                         state <= SYNC_LOW;
//                         delay_counter <= 0;
//                     end
//                 end

//                 SYNC_LOW: begin
//                     sync_low_out <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= SYNC_LOW;

//                     if (delay_counter >= 50) begin
//                         state <= SYNC_HIGH;
//                         delay_counter <= 0;
//                     end
//                 end

//                 SYNC_HIGH: begin
//                     sync_high_out <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= SYNC_HIGH;

//                     if (delay_counter >= 50) begin
//                         state <= DATA_SYNC;
//                         delay_counter <= 0;
//                     end
//                 end

//                 DATA_SYNC: begin
//                     data_sync_out <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= DATA_SYNC;

//                     if (delay_counter >= 50) begin
//                         state <= DATA_BIT;
//                         delay_counter <= 0;
//                     end
//                 end

//                 DATA_BIT: begin
//                     data_bit_out <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= DATA_BIT;

//                     if (next_btn_edge) begin
//                         received_data <= {received_data[38:0], 1'b1};
//                         sensor_data <= 1'b1;
//                         bit_count <= bit_count + 1;
//                         delay_counter <= 0;
//                         state <= STOP;
//                     end
//                     else if (delay_counter >= 50) begin
//                         received_data <= {received_data[38:0], 1'b1};
//                         sensor_data <= 1'b1;
//                         bit_count <= bit_count + 1;
//                         delay_counter <= 0;

//                         if (bit_count >= MAX_BITS - 1) begin
//                             state <= STOP;
//                         end else begin
//                             state <= DATA_SYNC;
//                         end
//                     end
//                 end

//                 STOP: begin
//                     stop_out <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= STOP;

//                     if (delay_counter >= 100) begin
//                         state <= READ;
//                         dnt_sensor_data <= received_data[39:32];
//                         delay_counter <= 0;
//                     end
//                 end

//                 READ: begin
//                     read <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= READ;

//                     if (delay_counter >= 50) begin
//                         state <= IDLE;
//                         delay_counter <= 0;
//                     end
//                 end

//                 default: begin
//                     state <= IDLE;
//                     current_state <= IDLE;
//                 end
//             endcase
//         end
//     end

// endmodule





// module dut_ctr (
//     input clk,
//     input rst,
//     input btn_start,
//     input tick_counter,
//     input btn_next,  // T17 핀에 연결될 추가 버튼 입력

//     output reg sensor_data,
//     output reg [3:0] current_state,
//     output reg [7:0] dnt_data,
//     output reg [7:0] dnt_sensor_data,
//     output reg dnt_io,

//     // FSM 상태 모니터링을 위한 출력
//     output reg idle,
//     output reg start,
//     output reg wait_state,
//     output reg sync_low_out,
//     output reg sync_high_out,
//     output reg data_sync_out,
//     output reg data_bit_out,
//     output reg stop_out,
//     output reg read
// );

//     // 상태 정의
//     localparam IDLE = 4'b0000;
//     localparam START = 4'b0001;
//     localparam WAIT = 4'b0010;
//     localparam SYNC_LOW = 4'b0011;
//     localparam SYNC_HIGH = 4'b0100;
//     localparam DATA_SYNC = 4'b0101;
//     localparam DATA_BIT = 4'b0110;
//     localparam STOP = 4'b0111;
//     localparam READ = 4'b1000;

//     // 타이밍 파라미터
//     localparam MAX_BITS = 3;
    
//     // 상태 변수
//     reg [3:0] state;
//     reg [5:0] bit_count;
//     reg [39:0] received_data;
    
//     // 버튼 동기화 및 엣지 감지를 위한 변수
//     reg [2:0] btn_sync;
//     reg btn_edge;
    
//     // 추가 버튼 동기화 및 엣지 감지
//     reg [2:0] next_btn_sync;
//     reg next_btn_edge;
    
//     // 타이머 관련 변수
//     reg [9:0] tick_count;
//     reg [7:0] delay_counter;
//     reg tick_prev;
    
//     // 직접 STOP으로 이동하기 위한 플래그
//     reg direct_to_stop;
    
//     // 버튼 엣지 감지
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             btn_sync <= 3'b000;
//             btn_edge <= 1'b0;
//             next_btn_sync <= 3'b000;
//             next_btn_edge <= 1'b0;
//             tick_prev <= 0;
//         end else begin
//             // 시작 버튼 동기화 및 엣지 감지
//             btn_sync <= {btn_sync[1:0], btn_start};
//             btn_edge <= (btn_sync[1] & ~btn_sync[2]);
            
//             // 추가 버튼 동기화 및 엣지 감지
//             next_btn_sync <= {next_btn_sync[1:0], btn_next};
//             next_btn_edge <= (next_btn_sync[1] & ~next_btn_sync[2]);
            
//             // tick_counter 엣지 감지
//             tick_prev <= tick_counter;
//         end
//     end
    
//     // 통합된 상태 머신 및 출력 제어
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state <= IDLE;
//             tick_count <= 0;
//             bit_count <= 0;
//             received_data <= 0;
//             dnt_data <= 0;
//             dnt_io <= 1'b1;
//             current_state <= IDLE;
//             sensor_data <= 0;
//             dnt_sensor_data <= 0;
//             delay_counter <= 0;
//             direct_to_stop <= 0;
            
//             // 상태 출력 초기화
//             idle <= 1'b1;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;
//         end else begin
//             // 기본적으로 모든 상태 출력 비활성화
//             idle <= 1'b0;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;
            
//             // tick_counter 상승 엣지 감지 시 delay_counter 증가
//             if (tick_counter & ~tick_prev) begin
//                 delay_counter <= delay_counter + 1;
//             end
            
//             // 상태에 따른 출력 설정
//             case (state)
//                 IDLE: begin
//                     idle <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= IDLE;
//                     direct_to_stop <= 0;
                    
//                     // 버튼 누름 감지 시 상태 전환
//                     if (btn_edge) begin
//                         state <= START;
//                         bit_count <= 0;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 START: begin
//                     start <= 1'b1;
//                     dnt_io <= 1'b0;  // START 상태에서 LOW 출력
//                     current_state <= START;
                    
//                     // 약 0.5초 후 다음 상태로
//                     if (delay_counter >= 50) begin
//                         state <= WAIT;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 WAIT: begin
//                     wait_state <= 1'b1;
//                     dnt_io <= 1'b1;  // WAIT 상태에서 HIGH 출력
//                     current_state <= WAIT;
                    
//                     if (delay_counter >= 50) begin
//                         state <= SYNC_LOW;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 SYNC_LOW: begin
//                     sync_low_out <= 1'b1;
//                     dnt_io <= 1'b0;  // SYNC_LOW 상태에서 LOW 출력
//                     current_state <= SYNC_LOW;
                    
//                     if (delay_counter >= 50) begin
//                         state <= SYNC_HIGH;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 SYNC_HIGH: begin
//                     sync_high_out <= 1'b1;
//                     dnt_io <= 1'b1;  // SYNC_HIGH 상태에서 HIGH 출력
//                     current_state <= SYNC_HIGH;
                    
//                     if (delay_counter >= 50) begin
//                         state <= DATA_SYNC;
//                         bit_count <= 0;  // 비트 카운트 초기화
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 DATA_SYNC: begin
//                     data_sync_out <= 1'b1;
//                     dnt_io <= 1'b0;  // DATA_SYNC 상태에서 LOW 출력
//                     current_state <= DATA_SYNC;
                    
//                     if (delay_counter >= 50) begin
//                         // 이전에 direct_to_stop이 설정되었거나 비트 카운트가 충분하면 STOP으로 이동
//                         if (direct_to_stop || bit_count >= MAX_BITS) begin
//                             state <= STOP;
//                             delay_counter <= 0;
//                             direct_to_stop <= 0;  // 플래그 초기화
//                         end else begin
//                             state <= DATA_BIT;
//                             delay_counter <= 0;
                            
//                             // 마지막 비트 직전이면 다음 사이클에서 STOP으로 바로 이동하도록 플래그 설정
//                             if (bit_count == MAX_BITS - 1) begin
//                                 direct_to_stop <= 1;
//                             end
//                         end
//                     end
//                 end
                
//                 DATA_BIT: begin
//                     data_bit_out <= 1'b1;
//                     dnt_io <= 1'b1;  // DATA_BIT 상태에서 HIGH 출력
//                     current_state <= DATA_BIT;
                    
//                     // 중요: 추가 버튼이 눌리면 즉시 STOP 상태로 전환
//                     if (next_btn_edge) begin
//                         state <= STOP;
//                         delay_counter <= 0;
                        
//                         // 데이터 비트 처리 및 비트 카운트 증가 (전환 전에 처리)
//                         received_data <= {received_data[38:0], 1'b1};
//                         sensor_data <= 1'b1;
//                         bit_count <= bit_count + 1;
//                     end
//                     else if (delay_counter >= 50) begin
//                         // 일반적인 타이머 기반 상태 전환
//                         received_data <= {received_data[38:0], 1'b1};
//                         sensor_data <= 1'b1;
//                         bit_count <= bit_count + 1;
                        
//                         // direct_to_stop 플래그가 설정되었으면 바로 STOP으로 이동
//                         if (direct_to_stop) begin
//                             state <= STOP;
//                             delay_counter <= 0;
//                             direct_to_stop <= 0;  // 플래그 초기화
//                         end else begin
//                             state <= DATA_SYNC;
//                             delay_counter <= 0;
//                         end
//                     end
//                 end
                
//                 STOP: begin
//                     stop_out <= 1'b1;
//                     dnt_io <= 1'b1;  // STOP 상태에서 HIGH 출력
//                     current_state <= STOP;
                    
//                     // STOP 상태에서는 더 오래 대기 (다른 상태의 2배)
//                     if (delay_counter >= 100) begin
//                         state <= READ;
//                         dnt_sensor_data <= received_data[39:32];
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 READ: begin
//                     read <= 1'b1;
//                     dnt_io <= 1'b0;  // READ 상태에서 LOW 출력
//                     current_state <= READ;
                    
//                     if (delay_counter >= 50) begin
//                         state <= IDLE;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 default: begin
//                     state <= IDLE;
//                     idle <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= IDLE;
//                 end
//             endcase
//         end
//     end

// endmodule
 
 
 
 
 
 
 //2번 깜빡임  module dut_ctr (
//     input clk,
//     input rst,
//     input btn_start,
//     input tick_counter,

//     output reg sensor_data,
//     output reg [3:0] current_state,
//     output reg [7:0] dnt_data,
//     output reg [7:0] dnt_sensor_data,
//     output reg dnt_io,

//     // FSM 상태 모니터링을 위한 출력
//     output reg idle,
//     output reg start,
//     output reg wait_state,
//     output reg sync_low_out,
//     output reg sync_high_out,
//     output reg data_sync_out,
//     output reg data_bit_out,
//     output reg stop_out,
//     output reg read
// );

//     // 상태 정의
//     localparam IDLE = 4'b0000;
//     localparam START = 4'b0001;
//     localparam WAIT = 4'b0010;
//     localparam SYNC_LOW = 4'b0011;
//     localparam SYNC_HIGH = 4'b0100;
//     localparam DATA_SYNC = 4'b0101;
//     localparam DATA_BIT = 4'b0110;
//     localparam STOP = 4'b0111;
//     localparam READ = 4'b1000;

//     // 타이밍 파라미터 단순화
//     localparam MAX_BITS = 3;  // 테스트를 위해 3개 비트만 읽음
    
//     // 상태 변수
//     reg [3:0] state;
//     reg [5:0] bit_count;
//     reg [39:0] received_data;
    
//     // 버튼 동기화 및 엣지 감지를 위한 변수
//     reg [3:0] btn_sync;  // 더 안정적인 동기화를 위해 4비트로 확장
//     reg btn_edge;
    
//     // 타이머 관련 변수
//     reg [9:0] tick_count;
//     reg [7:0] delay_counter;
//     reg [1:0] tick_sync;  // 2단계 동기화
    
//     // 상태 전환을 위한 특수 플래그
//     reg go_to_stop_flag;  // DATA_BIT에서 STOP으로의 강제 전환 플래그
    
//     // 버튼 및 tick_counter 엣지 감지
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             btn_sync <= 4'b0000;
//             btn_edge <= 1'b0;
//             tick_sync <= 2'b00;
//         end else begin
//             // 4단계 동기화로 더 안정적인 버튼 감지
//             btn_sync <= {btn_sync[2:0], btn_start};
            
//             // 버튼 상승 엣지 감지 - 2단계 확인으로 더 안정적
//             btn_edge <= (btn_sync[2:1] == 2'b01);
            
//             // tick_counter 2단계 동기화
//             tick_sync <= {tick_sync[0], tick_counter};
//         end
//     end
    
//     // 통합된 상태 머신 및 출력 제어
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state <= IDLE;
//             tick_count <= 0;
//             bit_count <= 0;
//             received_data <= 0;
//             dnt_data <= 0;
//             dnt_io <= 1'b1;
//             current_state <= IDLE;
//             sensor_data <= 0;
//             dnt_sensor_data <= 0;
//             delay_counter <= 0;
//             go_to_stop_flag <= 0;
            
//             // 상태 출력 초기화
//             idle <= 1'b1;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;
//         end else begin
//             // 기본적으로 모든 상태 출력 비활성화
//             idle <= 1'b0;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;
            
//             // 엣지 감지를 통한 딜레이 카운터 증가 (더 안정적인 방식)
//             if (tick_sync == 2'b01) begin  // 상승 엣지 감지
//                 delay_counter <= delay_counter + 1;
//             end
            
//             // 상태에 따른 출력 설정
//             case (state)
//                 IDLE: begin
//                     idle <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= IDLE;
//                     go_to_stop_flag <= 0;  // 플래그 초기화
                    
//                     // 버튼 누름 감지 시 상태 전환
//                     if (btn_edge) begin
//                         state <= START;
//                         bit_count <= 0;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 START: begin
//                     start <= 1'b1;
//                     dnt_io <= 1'b0;  // START 상태에서 LOW 출력
//                     current_state <= START;
                    
//                     // 약 0.5초 후 다음 상태로
//                     if (delay_counter >= 50) begin
//                         state <= WAIT;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 WAIT: begin
//                     wait_state <= 1'b1;
//                     dnt_io <= 1'b1;  // WAIT 상태에서 HIGH 출력
//                     current_state <= WAIT;
                    
//                     if (delay_counter >= 50) begin
//                         state <= SYNC_LOW;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 SYNC_LOW: begin
//                     sync_low_out <= 1'b1;
//                     dnt_io <= 1'b0;  // SYNC_LOW 상태에서 LOW 출력
//                     current_state <= SYNC_LOW;
                    
//                     if (delay_counter >= 50) begin
//                         state <= SYNC_HIGH;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 SYNC_HIGH: begin
//                     sync_high_out <= 1'b1;
//                     dnt_io <= 1'b1;  // SYNC_HIGH 상태에서 HIGH 출력
//                     current_state <= SYNC_HIGH;
                    
//                     if (delay_counter >= 50) begin
//                         state <= DATA_SYNC;
//                         bit_count <= 0;  // 비트 카운트 초기화
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 DATA_SYNC: begin
//                     data_sync_out <= 1'b1;
//                     dnt_io <= 1'b0;  // DATA_SYNC 상태에서 LOW 출력
//                     current_state <= DATA_SYNC;
                    
//                     if (delay_counter >= 50) begin
//                         // 최대 비트 수에 도달했을 때 STOP으로 직접 이동
//                         if (bit_count >= MAX_BITS) begin
//                             state <= STOP;
//                             delay_counter <= 0;
//                         end else begin
//                             // 마지막 비트 전이면 플래그 설정
//                             if (bit_count == MAX_BITS - 1) begin
//                                 go_to_stop_flag <= 1;  // 다음에 STOP으로 이동하도록 플래그 설정
//                             end
//                             state <= DATA_BIT;
//                             delay_counter <= 0;
//                         end
//                     end
//                 end
                
//                 DATA_BIT: begin
//                     data_bit_out <= 1'b1;
//                     dnt_io <= 1'b1;  // DATA_BIT 상태에서 HIGH 출력
//                     current_state <= DATA_BIT;
                    
//                     if (delay_counter >= 50) begin
//                         // 데이터 비트 처리
//                         received_data <= {received_data[38:0], 1'b1};
//                         sensor_data <= 1'b1;
//                         bit_count <= bit_count + 1;
                        
//                         // 조건부 상태 전환 강화
//                         if (go_to_stop_flag || bit_count >= MAX_BITS - 1) begin
//                             state <= STOP;  // 마지막 비트 후 직접 STOP으로 이동
//                             go_to_stop_flag <= 0;  // 플래그 초기화
//                         end else begin
//                             state <= DATA_SYNC;
//                         end
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 STOP: begin
//                     stop_out <= 1'b1;
//                     dnt_io <= 1'b1;  // STOP 상태에서 HIGH 출력
//                     current_state <= STOP;
                    
//                     if (delay_counter >= 50) begin
//                         state <= READ;
//                         dnt_sensor_data <= received_data[39:32];  // 상위 8비트만 사용
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 READ: begin
//                     read <= 1'b1;
//                     dnt_io <= 1'b0;  // READ 상태에서 LOW 출력
//                     current_state <= READ;
                    
//                     if (delay_counter >= 50) begin
//                         state <= IDLE;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 default: begin
//                     state <= IDLE;
//                     idle <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= IDLE;
//                 end
//             endcase
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
//     output reg dnt_io,

//     // FSM 상태 모니터링을 위한 출력
//     output reg idle,
//     output reg start,
//     output reg wait_state,
//     output reg sync_low_out,
//     output reg sync_high_out,
//     output reg data_sync_out,
//     output reg data_bit_out,
//     output reg stop_out,
//     output reg read
// );

//     // 상태 정의
//     localparam IDLE = 4'b0000;
//     localparam START = 4'b0001;
//     localparam WAIT = 4'b0010;
//     localparam SYNC_LOW = 4'b0011;
//     localparam SYNC_HIGH = 4'b0100;
//     localparam DATA_SYNC = 4'b0101;
//     localparam DATA_BIT = 4'b0110;
//     localparam STOP = 4'b0111;
//     localparam READ = 4'b1000;

//     // 타이밍 파라미터
//     localparam MAX_BITS = 3;
    
//     // 상태 변수
//     reg [3:0] state;
//     reg [5:0] bit_count;
//     reg [39:0] received_data;
    
//     // 버튼 동기화 및 엣지 감지를 위한 변수
//     reg [2:0] btn_sync;
//     reg btn_edge;
    
//     // 타이머 관련 변수
//     reg [9:0] tick_count;
//     reg [7:0] delay_counter;
//     reg tick_prev;
    
//     // 추가적인 상태 안정화 변수
//     reg stable_state;  // 상태 안정성 유지 플래그
    
//     // 버튼 엣지 감지
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             btn_sync <= 3'b000;
//             btn_edge <= 1'b0;
//             tick_prev <= 0;
//         end else begin
//             // 버튼 동기화 및 엣지 감지
//             btn_sync <= {btn_sync[1:0], btn_start};
//             btn_edge <= (btn_sync[1] & ~btn_sync[2]);
            
//             // tick_counter 엣지 감지
//             tick_prev <= tick_counter;
//         end
//     end

//     // FSM 상태 및 출력 제어
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state <= IDLE;
//             bit_count <= 0;
//             received_data <= 0;
//             dnt_data <= 0;
//             dnt_io <= 1'b1;
//             current_state <= IDLE;
//             sensor_data <= 0;
//             dnt_sensor_data <= 0;
//             delay_counter <= 0;
//             stable_state <= 0;
            
//             // 상태 출력 초기화
//             idle <= 1'b1;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;
//         end else begin
//             // 기본적으로 모든 상태 출력 비활성화
//             idle <= 1'b0;
//             start <= 1'b0;
//             wait_state <= 1'b0;
//             sync_low_out <= 1'b0;
//             sync_high_out <= 1'b0;
//             data_sync_out <= 1'b0;
//             data_bit_out <= 1'b0;
//             stop_out <= 1'b0;
//             read <= 1'b0;
            
//             // tick_counter 상승 엣지 감지 시 delay_counter 증가
//             if (tick_counter && !tick_prev) begin
//                 delay_counter <= delay_counter + 1;
//             end
            
//             // 상태에 따른 출력 설정
//             case (state)
//                 IDLE: begin
//                     idle <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= IDLE;
//                     stable_state <= 0;
                    
//                     // 버튼 누름 감지 시 상태 전환
//                     if (btn_edge) begin
//                         state <= START;
//                         bit_count <= 0;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 START: begin
//                     start <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= START;
                    
//                     // 약 0.5초 후 다음 상태로
//                     if (delay_counter >= 50) begin
//                         state <= WAIT;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 WAIT: begin
//                     wait_state <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= WAIT;
                    
//                     if (delay_counter >= 50) begin
//                         state <= SYNC_LOW;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 SYNC_LOW: begin
//                     sync_low_out <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= SYNC_LOW;
                    
//                     if (delay_counter >= 50) begin
//                         state <= SYNC_HIGH;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 SYNC_HIGH: begin
//                     sync_high_out <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= SYNC_HIGH;
                    
//                     if (delay_counter >= 50) begin
//                         state <= DATA_SYNC;
//                         bit_count <= 0;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 DATA_SYNC: begin
//                     data_sync_out <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= DATA_SYNC;
                    
//                     if (delay_counter >= 50) begin
//                         // 3개 비트를 모두 읽었으면 STOP으로 이동
//                         if (bit_count >= MAX_BITS) begin
//                             state <= STOP;
//                             stable_state <= 1;  // 안정적인 상태 전환을 위한 플래그
//                             delay_counter <= 0;
//                         end else begin
//                             state <= DATA_BIT;
//                             delay_counter <= 0;
//                         end
//                     end
//                 end
                
//                 DATA_BIT: begin
//                     data_bit_out <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= DATA_BIT;
                    
//                     if (delay_counter >= 50) begin
//                         // 시뮬레이션을 위해 항상 1로 설정
//                         received_data <= {received_data[38:0], 1'b1};
//                         sensor_data <= 1'b1;
                        
//                         // 마지막 비트 처리 후 STOP으로 바로 이동
//                         if (bit_count == MAX_BITS - 1) begin
//                             bit_count <= bit_count + 1;
//                             state <= STOP;
//                             stable_state <= 1;  // 안정적인 상태 전환을 위한 플래그
//                             delay_counter <= 0;
//                         end else begin
//                             bit_count <= bit_count + 1;
//                             state <= DATA_SYNC;
//                             delay_counter <= 0;
//                         end
//                     end
//                 end
                
//                 STOP: begin
//                     stop_out <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= STOP;
                    
//                     // 상태 안정화: stable_state가 1인 경우에만 전환 허용
//                     // 또는 충분한 시간이 지난 경우(100 틱 이상)
//                     if ((stable_state && delay_counter >= 50) || delay_counter >= 100) begin
//                         state <= READ;
//                         dnt_sensor_data <= received_data[39:32];
//                         stable_state <= 0;  // 플래그 초기화
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 READ: begin
//                     read <= 1'b1;
//                     dnt_io <= 1'b0;
//                     current_state <= READ;
                    
//                     if (delay_counter >= 50) begin
//                         state <= IDLE;
//                         delay_counter <= 0;
//                     end
//                 end
                
//                 default: begin
//                     state <= IDLE;
//                     idle <= 1'b1;
//                     dnt_io <= 1'b1;
//                     current_state <= IDLE;
//                 end
//             endcase
//         end
//     end

// endmodule


//그나마 성공
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






















