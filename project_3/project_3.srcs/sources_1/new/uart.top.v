`timescale 1ns / 1ps
module uart_fifo_top (
    // 시스템 신호
    input wire clk,      // 시스템 클록
    input wire rst,      // 리셋 신호
    
    // UART 인터페이스
    input wire rx,       // UART RX 입력
    output wire tx,      // UART TX 출력
    
    // 스톱워치 & 시계 제어 신호 (추가)
    output wire w_run,          // 스톱워치 실행/정지
    output wire w_clear,        // 스톱워치 초기화
    output wire btn_hour,       // 시계 시간 증가
    output wire btn_min,        // 시계 분 증가
    output wire btn_sec,        // 시계 초 증가
    output wire [1:0] sw,       // 모드 선택
    
    // 상태 입력 (추가)
    input wire o_run,           // 현재 스톱워치 실행 상태
    input wire [1:0] current_state,  // 현재 FSM 상태
    
    // 버튼 디바운싱용 신호 출력 (추가)
    output wire w_rx_done,      // RX 완료 신호
    output wire [7:0] w_rx_data // RX 데이터
);
    // 내부 연결 신호
    wire w_tick;         // 보드레이트 틱 신호
    wire w_tx_done;      // TX 완료 신호
    
    // 테스트벤치용 추가 신호
    reg btn_start = 1'b1;  // 시작 버튼 신호, 항상 활성화
    wire [7:0] rdata;      // 데이터 읽기 값
    wire rd;               // 읽기 신호
    
    // 내부 FIFO 신호
    wire [7:0] tx_fifo_rdata;    // TX FIFO 출력 데이터
    wire       tx_fifo_empty;    // TX FIFO 엠티 신호
    wire       tx_rd;            // TX FIFO 읽기 신호
    wire       tx_fifo_full;     // TX FIFO 풀 신호
    wire [7:0] rx_fifo_wdata;    // RX FIFO 입력 데이터
    wire       rx_fifo_full;     // RX FIFO 풀 신호
    wire       rx_wr;            // RX FIFO 쓰기 신호
    wire       rx_fifo_empty;    // RX FIFO 엠티 신호
    wire [7:0] rx_fifo_rdata;    // RX FIFO 읽기 데이터
    wire       w_rx_rd;          // RX FIFO 읽기 신호
    wire [7:0] tx_wdata;         // TX FIFO 입력 데이터
    wire       tx_wr;            // TX FIFO 쓰기 신호
    wire       tx_start;         // TX 시작 신호
    
    // UART RX에서 받은 데이터를 직접 rx_fifo_wdata에 연결
    assign rx_fifo_wdata = w_rx_data;
    
    // 테스트벤치용 신호 연결
    assign rdata = rx_fifo_rdata;
    assign rd = w_rx_rd;
    
    // UART CU 인스턴스 추가
    uart_cu U_UART_CU (
        // 시스템 신호
        .clk(clk),
        .reset(rst),
        
        // FIFO 인터페이스 - 입력
        .rx_fifo_rdata(rx_fifo_rdata),
        .rx_fifo_empty(rx_fifo_empty),
        .tx_fifo_full(tx_fifo_full),
        
        // FIFO 인터페이스 - 출력
        .w_rx_rd(w_rx_rd),
        .tx_wdata(tx_wdata),
        .tx_wr(tx_wr),
        
        // 스톱워치 & 시계 제어 신호
        .w_run(w_run),
        .w_clear(w_clear),
        .btn_hour(btn_hour),
        .btn_min(btn_min),
        .btn_sec(btn_sec),
        .sw(sw),
        
        // 상태 입력
        .o_run(o_run),
        .current_state(current_state)
    );
    
    // TX 부분
    assign tx_start = ~tx_fifo_empty;  // TX FIFO가 비어있지 않으면 전송 시작
    assign tx_rd = w_tx_done & ~tx_fifo_empty;  // TX 완료되고 FIFO가 비어있지 않으면 다음 데이터 읽기
    
    // RX 부분
    assign rx_wr = w_rx_done & ~rx_fifo_full;  // RX 완료되고 FIFO가 가득 차지 않았으면 데이터 쓰기
    
    // FIFO TX 인스턴스
    FIFO u_fifo_tx (
        .clk(clk),
        .reset(rst),
        .wdata(tx_wdata),
        .wr(tx_wr),
        .rd(tx_rd),
        .rdata(tx_fifo_rdata),
        .full(tx_fifo_full),
        .empty(tx_fifo_empty)
    );
    
    // UART TX 모듈
    uart_tx U_uart_tx (
        .clk(clk),
        .rst(rst),
        .tick(w_tick),
        .start_trigger(tx_start),
        .data_in(tx_fifo_rdata),
        .o_tx_done(w_tx_done),
        .o_tx(tx)
    );
    
    // 보드레이트 생성기
    baud_tick_gen U_tick_gen (
        .clk(clk),
        .rst(rst),
        .baud_tick(w_tick)
    );
    
    // UART RX 모듈
    uart_rx u_UART_Rx (
        .clk(clk),
        .rst(rst),
        .tick(w_tick),
        .rx(rx),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data)
    );
    
    // FIFO RX 인스턴스
    FIFO u_fifo_rx (
        .clk(clk),
        .reset(rst),
        .wdata(rx_fifo_wdata),
        .wr(rx_wr),
        .rd(w_rx_rd),
        .rdata(rx_fifo_rdata),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty)
    );
endmodule

module uart_tx (
    input clk,
    input rst,
    input tick,
    input start_trigger,
    input [7:0] data_in,
    output o_tx_done,
    output o_tx,
    // 디버깅용 출력 추가
    output [2:0] o_state,
    output [2:0] o_bit_count,
    output [3:0] o_tick_count
);

    // 상태 정의 - SEND 제거 및 단순화
    localparam IDLE = 3'h0, START = 3'h1, DATA = 3'h2, STOP = 3'h3;
    
    reg [2:0] state, next;
    reg tx_reg, tx_next;
    reg [2:0] bit_count, bit_count_next;
    reg [3:0] tick_count_reg, tick_count_next;
    reg [7:0] temp_data_reg, temp_data_next;
    reg tx_done_reg, tx_done_next;
    
    // 출력 할당
    assign o_tx = tx_reg;
    assign o_tx_done = tx_done_reg;
    // 디버깅용 출력 할당
    assign o_state = state;
    assign o_bit_count = bit_count;
    assign o_tick_count = tick_count_reg;
    
    // 순차 로직 - 상태 및 레지스터 업데이트
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            tx_reg <= 1'b1;         // 리셋시 TX는 항상 High
            tx_done_reg <= 1'b0;
            bit_count <= 3'b000;
            tick_count_reg <= 4'b0000;
            temp_data_reg <= 8'h00;
        end else begin
            state <= next;
            tx_reg <= tx_next;      // tx_next가 tx_reg로 제대로 업데이트되는지 확인
            tx_done_reg <= tx_done_next;
            bit_count <= bit_count_next;
            tick_count_reg <= tick_count_next;
            temp_data_reg <= temp_data_next;
        end
    end
    
    // 조합 로직 - 다음 상태 및 출력 결정
    always @(*) begin
        // 기본값 설정 - 엣지 케이스 방지
        next = state;
        tx_next = tx_reg;  // 중요: 기본값으로 현재 값 유지
        tx_done_next = tx_done_reg;
        tick_count_next = tick_count_reg;
        bit_count_next = bit_count;
        temp_data_next = temp_data_reg;
        
        case (state)
            IDLE: begin
                tx_next = 1'b1;        // 명시적으로 1 할당
                tx_done_next = 1'b0;
                tick_count_next = 4'b0000;
                bit_count_next = 3'b000;
                
                if (start_trigger) begin
                    next = START;
                    temp_data_next = data_in;
                end
            end
            
            START: begin
                tx_next = 1'b0;  // 시작 비트는 반드시 0
                
                if (tick) begin
                    if (tick_count_reg == 4'b1111) begin  // 15에 도달
                        next = DATA;
                        tick_count_next = 4'b0000;
                    end else begin
                        tick_count_next = tick_count_reg + 4'b0001;
                    end
                end
            end
            
            DATA: begin
                // 가장 중요한 부분: 데이터 비트를 tx_next에 할당
                tx_next = temp_data_reg[bit_count];
                
                if (tick) begin
                    if (tick_count_reg == 4'b1111) begin  // 15에 도달
                        tick_count_next = 4'b0000;
                        
                        if (bit_count == 3'b111) begin  // 비트 7에 도달 (8비트 모두 전송)
                            next = STOP;
                        end else begin
                            bit_count_next = bit_count + 3'b001;
                        end
                    end else begin
                        tick_count_next = tick_count_reg + 4'b0001;
                    end
                end
            end
            
            STOP: begin
                tx_next = 1'b1;  // 정지 비트는 반드시 1
                
                if (tick) begin
                    if (tick_count_reg == 4'b1111) begin  // 15에 도달
                        next = IDLE;
                        tx_done_next = 1'b1;  // 전송 완료
                        tick_count_next = 4'b0000;
                    end else begin
                        tick_count_next = tick_count_reg + 4'b0001;
                    end
                end
            end
            
            default: begin
                next = IDLE;
                tx_next = 1'b1;
                tx_done_next = 1'b0;
                tick_count_next = 4'b0000;
                bit_count_next = 3'b000;
            end
        endcase
    end
endmodule

`timescale 1ns / 1ps

module uart_rx (
    input clk,rst,tick,rx,
    output rx_done,
    output [7:0] rx_data
);

    localparam IDLE = 0, START = 1, DATA = 2, STOP = 3 ;
    reg [1:0] state,next;
    reg rx_done_reg, rx_done_next;
    reg [2:0] bit_count_reg, bit_count_next;
    reg [4:0] tick_count_reg, tick_count_next;
    reg [7:0] rx_data_reg, rx_data_next;

    //output
    assign rx_done = rx_done_reg;
    assign rx_data = rx_data_reg;

    //state
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 0;
            rx_done_reg <=0;
            rx_data_reg <=0;
            bit_count_reg <=0;
            tick_count_reg <=0;
        end else begin
            state <= next;
            rx_done_reg <= rx_done_next;
            rx_data_reg <= rx_data_next;
            bit_count_reg <= bit_count_next;
            tick_count_reg <= tick_count_next;
        end
    end

    //next
    always @(*) begin
        next = state;
        tick_count_next = tick_count_reg;
        bit_count_next = bit_count_reg;
        rx_data_next = rx_data_reg;
        rx_done_next  = 0;
        
        case (state)
            IDLE:  begin
                rx_done_next = 1'b0;
                tick_count_next = 0;
                bit_count_next = 0;
                if (rx==0) begin
                    next = START;
                end
            end

            START : begin
                if (tick) begin
                    if (tick_count_reg==7) begin
                        next = DATA;
                        tick_count_next = 0;
                    end else begin
                        tick_count_next = tick_count_reg+1;
                    end
                end
            end

            DATA : begin
                if (tick) begin
                    if (tick_count_reg==15) begin
                        //read data
                        rx_data_next[bit_count_reg] = rx;
                        tick_count_next = 0;
                        if (bit_count_reg==7) begin
                            next = STOP;
                        end else begin
                            bit_count_next = bit_count_reg+1;
                        end
                    end else begin
                        tick_count_next = tick_count_reg+1;
                    end 
                end
            end

            STOP : begin
                if (tick) begin
                    if (tick_count_reg==15) begin  // 원래 23에서 15로 변경
                        next = IDLE;
                        rx_done_next = 1'b1;
                    end else begin
                        tick_count_next = tick_count_reg+1;
                    end
                end
            end 
        endcase
    end
endmodule

//원래코드 
// `timescale 1ns / 1ps

// module uart_rx (
//     input clk,rst,tick,rx,
//     output rx_done,
//     output [7:0] rx_data
// );

//     localparam IDLE = 0, START = 1, DATA = 2, STOP = 3 ;
//     reg [1:0] state,next;
//     reg rx_reg, rx_next;
//     reg rx_done_reg, rx_done_next;
//     reg [2:0] bit_count_reg, bit_count_next;
//     reg [4:0] tick_count_reg, tick_count_next;
//     reg [7:0] rx_data_reg, rx_data_next;

//     //output
//     assign rx_done = rx_done_reg;
//     assign rx_data = rx_data_reg;

//     //state
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             state <= 0;
//             rx_done_reg <=0;
//             rx_data_reg <=0;
//             bit_count_reg <=0;
//             tick_count_reg <=0;
//         end else begin
//             state <= next;
//             rx_done_reg <= rx_done_next;
//             rx_data_reg <= rx_data_next;
//             bit_count_reg <=bit_count_next;
//             tick_count_reg <= tick_count_next;
//         end
//     end

//     //next
//     always @(*) begin
//         next = state;
//         tick_count_next = tick_count_reg;
//         bit_count_next = bit_count_reg;
//         rx_data_next = rx_data_reg;
//         rx_done_next  = 0;
//         case (state)
//             IDLE:  begin
//                 rx_done_next = 1'b0;
//                 tick_count_next = 0;
//                 bit_count_next = 0;
//                 if (rx==0) begin
//                     next = START;
//                 end
//             end

//             START : begin
//                 if (tick) begin
//                      if (tick_count_reg==7) begin
//                     next = DATA;
//                     tick_count_next = 0;
//                 end else begin
//                     tick_count_next = tick_count_reg+1;
//                 end
//                 end
//             end

//             DATA : begin
//                 if (tick) begin
//                     if (tick_count_reg==15) begin
//                     //read data
//                     rx_data_next [bit_count_reg] = rx;
//                     tick_count_next = 0;
//                     if (bit_count_reg==7) begin
//                         next = STOP;
//                     end else begin
//                         next = DATA;
//                         bit_count_next = bit_count_reg+1;
//                     end
//                 end else begin
//                     tick_count_next = tick_count_reg+1;
//                 end 
//                 end
//             end

//             STOP : begin
//                 if (tick) begin
//                     if (tick_count_reg==23) begin
//                     next = IDLE;
//                     rx_done_next = 1'b1;
//                 end else begin
//                     tick_count_next = tick_count_reg+1;
//                 end
//                 end
//             end 
//         endcase
//     end
// endmodule

`timescale 1ns / 1ps

module baud_tick_gen (
    input clk,
    input rst,
    output baud_tick
);
    // 보드레이트를 낮춰서 더 안정적인 통신을 할 수 있도록 함
    parameter BAUD_RATE = 9600;
    // BAUD_COUNT = 100_000_000 / 9600 / 16 = 651
    localparam BAUD_COUNT = 651;
    localparam COUNTER_WIDTH = 10;  // 651을 표현하기 위해 최소 10비트 필요

    reg [COUNTER_WIDTH-1:0] count_reg, count_next;
    reg tick_reg, tick_next;

    assign baud_tick = tick_reg;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count_reg <= 0;
            tick_reg <= 0;
        end else begin
            count_reg <= count_next;
            tick_reg <= tick_next;
        end
    end

    always @(*) begin
        count_next = count_reg + 1;
        tick_next = 1'b0;  // tick_next 초기화

        if (count_reg >= BAUD_COUNT-1) begin
            count_next = 0;
            tick_next = 1'b1;
        end
    end
endmodule





//원래 코드 
// `timescale 1ns / 1ps

// module baud_tick_gen (
//     input clk,
//     input rst,
//     output baud_tick
// );
//     //parameter BAUD_RATE = 115200;
//     parameter BAUD_RATE = 9600;
//     localparam BAUD_COUNT = 100_000_000 / BAUD_RATE / 16; // 반올림 처리
//     localparam COUNTER_WIDTH = $clog2(BAUD_COUNT);  // 정확한 비트 수 설정

//     reg [COUNTER_WIDTH-1:0] count_reg, count_next;
//     reg tick_reg, tick_next;

//     assign baud_tick = tick_reg;

//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             count_reg <= 0;
//             tick_reg <= 0;
//         end else begin
//             count_reg <= count_next;
//             tick_reg <= tick_next;
//         end
//     end

//     always @(*) begin
//         count_next = count_reg + 1;
//         tick_next = 1'b0;  // tick_next 초기화

//         if (count_reg >= BAUD_COUNT-1) begin
//             count_next = 0;
//             tick_next = 1'b1;
//         end
//     end
// endmodule