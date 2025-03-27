module uart_cu(
   // 시스템 신호
   input  wire        clk,
   input  wire        reset,
   
   // FIFO 인터페이스 - 입력
   input  wire [7:0]  rx_fifo_rdata,    // RX FIFO에서 읽은 데이터
   input  wire        rx_fifo_empty,    // RX FIFO 비어있음 상태 
   input  wire        tx_fifo_full,     // TX FIFO 가득참 상태
   
   // FIFO 인터페이스 - 출력
   output reg         w_rx_rd,          // RX FIFO 읽기 신호
   output reg  [7:0]  tx_wdata,         // TX FIFO에 쓸 데이터
   output reg         tx_wr,            // TX FIFO 쓰기 신호
   
   // 스톱워치 & 시계 출력 신호
   output reg         w_run,            // 스톱워치 실행/정지
   output reg         w_clear,          // 스톱워치 초기화
   output reg         btn_hour,         // 시계 시간 증가
   output reg         btn_min,          // 시계 분 증가
   output reg         btn_sec,          // 시계 초 증가
   output reg  [1:0]  sw,               // 모드 선택
   
   // 상태 입력
   input  wire        o_run,            // 현재 스톱워치 실행 상태
   input  wire [1:0]  current_state     // 현재 FSM 상태
);

   // FSM 상태 정의 
   localparam IDLE = 2'b00; //대기상태
   localparam READ_CMD = 2'b01; //명령 읽기 상태
   localparam PROCESS_CMD = 2'b10; //명령 처리 상태
   localparam SEND_RESPONSE = 2'b11; //응답 전송 상태
   
   // 명령어 아스키 코드 정의
   localparam CMD_RUN = 8'h52;        // 'R'
   localparam CMD_RUN_LOWER = 8'h72;  // 'r'
   localparam CMD_CLEAR = 8'h43;      // 'C'
   localparam CMD_CLEAR_LOWER = 8'h63;// 'c'
   localparam CMD_HOUR = 8'h48;       // 'H'
   localparam CMD_HOUR_LOWER = 8'h68; // 'h'
   localparam CMD_MIN = 8'h4D;        // 'M'
   localparam CMD_MIN_LOWER = 8'h6D;  // 'm'
   localparam CMD_SEC = 8'h53;        // 'S'
   localparam CMD_SEC_LOWER = 8'h73;  // 's'
   
   // 레지스터 선언
   reg [1:0] state, next_state;       // 현재 상태와 다음 상태
   reg [7:0] cmd_reg;                 // 명령 저장 레지스터
   reg [15:0] timeout_counter;        // 타임아웃 카운터
   reg cmd_read_done;                 // 명령 읽기 완료 플래그
   
   // 버튼 펄스 지속 시간 -> 값이 1씩 증가하게 함 
   reg [19:0] button_timer;           // 버튼 신호 지속 타이머
   reg button_active;                 // 버튼 활성화 상태 플래그
   reg button_cooldown;               // 버튼 쿨다운 상태 플래그

   // 디바운스 관련 레지스터
   reg [7:0] rx_data_shift_reg;       // 시프트 레지스터
   reg rx_done_reg;                   // RX 완료 레지스터
   reg rx_edge_detect;                // 에지 감지 레지스터
   wire rx_data_debounced;            // 디바운스된 RX 데이터
   wire rx_cmd_edge;                  // RX 명령 에지
   
   // Run 명령 전용 처리 신호
   reg is_run_cmd;                    // Run 명령 감지 플래그
   reg run_toggle_pending;            // Run 토글 대기 플래그
   
   // 버튼 타이머 제어용 신호 (멀티 드라이브 방지)
   reg timer_start;                   // 타이머 시작 신호
   reg [1:0] btn_sel;                 // 버튼 선택 신호 (00: none, 01: hour, 10: min, 11: sec)
   
   // 디바운스 로직 - btn_debounce 모듈과 유사한 방식
   always @(posedge clk or posedge reset) begin
       if (reset) begin
           rx_data_shift_reg <= 8'h00;
           rx_done_reg <= 1'b0;
           rx_edge_detect <= 1'b0;
           is_run_cmd <= 1'b0;
           run_toggle_pending <= 1'b0;
       end else begin
           // 새 명령 수신 시
           if (state == READ_CMD && w_rx_rd && !rx_fifo_empty) begin
               // Run 명령 감지
               if (rx_fifo_rdata == CMD_RUN || rx_fifo_rdata == CMD_RUN_LOWER) begin
                   is_run_cmd <= 1'b1;
                   
                   // 시프트 레지스터 업데이트 (btn_debounce와 유사)
                   rx_data_shift_reg <= {1'b1, rx_data_shift_reg[7:1]};
               end else begin
                   is_run_cmd <= 1'b0;
                   // 다른 명령이면 시프트 레지스터 클리어
                   rx_data_shift_reg <= {1'b0, rx_data_shift_reg[7:1]};
               end
               
               rx_done_reg <= 1'b1;  // RX 완료 표시
           end else if (state == IDLE) begin
               rx_done_reg <= 1'b0;  // 다음 명령을 위해 초기화
           end
           
           // 에지 감지기 (btn_debounce와 유사)
           rx_edge_detect <= rx_data_debounced & rx_done_reg;
           
           // Run 토글 대기 플래그 처리
           if (rx_cmd_edge && is_run_cmd) begin
               run_toggle_pending <= 1'b1;
           end else if (state == PROCESS_CMD && run_toggle_pending) begin
               run_toggle_pending <= 1'b0;  // 처리 완료 후 클리어
           end
       end
   end
   
   // 디바운스 신호 생성 (btn_debounce와 유사)
   assign rx_data_debounced = &rx_data_shift_reg;
   
   // 명령 에지 감지 (상승 에지에서 명령 처리)
   assign rx_cmd_edge = rx_data_debounced & rx_done_reg & (~rx_edge_detect);
    
    // 개선된 버튼 타이머 관리 로직
always @(posedge clk or posedge reset) begin
    if (reset) begin
        button_timer <= 20'd0;
        btn_hour <= 1'b0;
        btn_min <= 1'b0;
        btn_sec <= 1'b0;
        button_active <= 1'b0;
        button_cooldown <= 1'b0;
    end else begin
        // 기본값으로 모든 버튼 비활성화
        btn_hour <= 1'b0;
        btn_min <= 1'b0;
        btn_sec <= 1'b0;
        
        // 타이머 시작 신호가 발생하고 버튼이 비활성 상태인 경우
        if (timer_start && !button_active && !button_cooldown) begin
            button_active <= 1'b1;
            button_timer <= 20'd50000;  // 쿨다운 타이머 설정 (0.5ms)
            
            // 버튼 선택에 따라 단 한 클럭 사이클 동안만 신호 활성화
            case (btn_sel)
                2'b01: btn_hour <= 1'b1;
                2'b10: btn_min <= 1'b1;
                2'b11: btn_sec <= 1'b1;
                default: ; // 아무 버튼도 활성화하지 않음
            endcase
        end
        // 타이머 카운트 다운
        else if (button_timer > 0) begin
            button_timer <= button_timer - 1;
            
            if (button_timer == 1) begin
                button_active <= 1'b0;
                button_cooldown <= 1'b0;  // 쿨다운 종료
            end
        end
    end
end
   // 상태 레지스터 업데이트
   always @(posedge clk or posedge reset) begin
       if (reset) begin
           state <= IDLE;
           cmd_reg <= 8'h00;
           timeout_counter <= 16'h0000;
           cmd_read_done <= 1'b0;
       end else begin
           state <= next_state;
           
           // 타임아웃 카운터 업데이트
           if (state == IDLE) begin
               timeout_counter <= 16'h0000;
               cmd_read_done <= 1'b0;
           end else begin
               timeout_counter <= timeout_counter + 1;
               
               // 타임아웃 발생 시(약 65ms @ 100MHz)
               if (timeout_counter == 16'hFFFF) begin
                   timeout_counter <= 16'h0000;
                   state <= IDLE;
               end
           end
           
           // 명령 레지스터 업데이트
           if (state == READ_CMD && w_rx_rd && !rx_fifo_empty) begin
               cmd_reg <= rx_fifo_rdata;
               cmd_read_done <= 1'b1;
           end
       end
   end
   
   // 다음 상태 결정 로직
   always @(*) begin
       next_state = state;
       
       case (state)
           IDLE: begin
               if (!rx_fifo_empty)
                   next_state = READ_CMD;
           end
           
           READ_CMD: begin
               if (cmd_read_done)
                   next_state = PROCESS_CMD;
               else if (rx_fifo_empty)
                   next_state = IDLE;
           end
           
           PROCESS_CMD: begin
               next_state = SEND_RESPONSE;
           end
           
           SEND_RESPONSE: begin
               if (!tx_fifo_full)
                   next_state = IDLE;
           end
           
           default: next_state = IDLE;
       endcase
   end
   
   // 명령 처리 로직
   always @(posedge clk or posedge reset) begin
       if (reset) begin
           w_rx_rd <= 1'b0;
           tx_wdata <= 8'h00;
           tx_wr <= 1'b0;
           w_run <= 1'b0;
           w_clear <= 1'b0;
           sw <= 2'b00;
           timer_start <= 1'b0;
           btn_sel <= 2'b00;
       end else begin
           // 기본값으로 초기화
           w_rx_rd <= 1'b0;
           tx_wr <= 1'b0;
           w_clear <= 1'b0;
           timer_start <= 1'b0;  // 타이머 시작 신호 초기화
           
           case (state)
               IDLE: begin
                   // 대기 상태
               end
               
               READ_CMD: begin
                   // FIFO에서 명령 읽기
                   if (!rx_fifo_empty && !cmd_read_done)
                       w_rx_rd <= 1'b1;
               end
               
               PROCESS_CMD: begin
                   // Run 명령 처리
                   if (run_toggle_pending && is_run_cmd) begin
                       if (current_state[1] == 1'b0) begin  // 스톱워치 모드에서만
                           w_run <= ~o_run;  // 현재 상태에 기반하여 토글
                       end
                   end
                   // 다른 명령 처리
                   else if (cmd_read_done) begin
                       case (cmd_reg)
                           CMD_CLEAR, CMD_CLEAR_LOWER: begin
                               if (current_state[1] == 1'b0) begin  // 스톱워치 모드에서만
                                   w_clear <= 1'b1;
                                   w_run <= 1'b0;    // 실행 중이라면 정지
                               end
                           end
                           
                           CMD_HOUR, CMD_HOUR_LOWER: begin
                               if (current_state[1] == 1'b1 && !button_active && !button_cooldown) begin  // 시계 모드 & 버튼 비활성 상태
                                   btn_sel <= 2'b01;  // hour 버튼 선택
                                   timer_start <= 1'b1;  // 타이머 시작 신호 활성화
                               end
                           end
                           
                           CMD_MIN, CMD_MIN_LOWER: begin
                               if (current_state[1] == 1'b1 && !button_active && !button_cooldown) begin  // 시계 모드 & 버튼 비활성 상태
                                   btn_sel <= 2'b10;  // min 버튼 선택
                                   timer_start <= 1'b1;  // 타이머 시작 신호 활성화
                               end
                           end
                           
                           CMD_SEC, CMD_SEC_LOWER: begin
                               if (current_state[1] == 1'b1 && !button_active && !button_cooldown) begin  // 시계 모드 & 버튼 비활성 상태
                                   btn_sel <= 2'b11;  // sec 버튼 선택
                                   timer_start <= 1'b1;  // 타이머 시작 신호 활성화
                               end
                           end
                           
                           default: begin
                               // 알 수 없는 명령 - 무시
                           end
                       endcase
                   end
               end
               
               SEND_RESPONSE: begin
                   // 응답 전송 로직 (루프백)
                   if (!tx_fifo_full) begin
                       tx_wdata <= cmd_reg;
                       tx_wr <= 1'b1;
                   end
               end
           endcase
       end
   end
endmodule