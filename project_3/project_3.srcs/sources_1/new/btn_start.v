module btn_start_debounce (
    input clk,
    input reset,
    input btn_run_in,          // btn_start_in에서 btn_run_in으로 변경
    output reg btn_run_out     // btn_start_out에서 btn_run_out으로 변경
);
    // 동기화 및 디바운스 레지스터
    reg [2:0] btn_sync;
    reg [19:0] debounce_counter;
    parameter DEBOUNCE_DELAY = 20'd10; // 매우 짧은 지연으로 수정
    
    // 버튼 상태 감지용 레지스터
    reg btn_debounced;        // 디바운싱된 버튼 상태
    reg btn_debounced_prev;   // 이전 디바운싱된 버튼 상태
    
    // 디바운스 로직 - 버튼이 눌릴 때 펄스 생성 (상승 에지)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            btn_sync <= 3'b000;
            debounce_counter <= 20'd0;
            btn_debounced <= 1'b0;
            btn_debounced_prev <= 1'b0;
            btn_run_out <= 1'b0;         // btn_start_out에서 btn_run_out으로 변경
        end else begin
            // 3단계 동기화
            btn_sync <= {btn_sync[1:0], btn_run_in};   // btn_start_in에서 btn_run_in으로 변경
            
            // 디바운스 로직
            if (btn_sync[2] != btn_sync[1]) begin
                // 버튼 상태 변화 감지되면 카운터 리셋
                debounce_counter <= 20'd0;
            end else if (debounce_counter < DEBOUNCE_DELAY) begin
                // 안정화 대기 (매우 짧게 설정)
                debounce_counter <= debounce_counter + 1;
            end else begin
                // 안정화된 버튼 상태를 저장
                btn_debounced <= btn_sync[2];
            end
            
            // 이전 상태 저장
            btn_debounced_prev <= btn_debounced;
            
            // 버튼이 눌릴 때(상승 에지) 펄스 생성
            if (!btn_debounced_prev && btn_debounced) begin
                btn_run_out <= 1'b1;  // 펄스 활성화   // btn_start_out에서 btn_run_out으로 변경
            end else begin
                btn_run_out <= 1'b0;  // 한 클럭 후 펄스 비활성화   // btn_start_out에서 btn_run_out으로 변경
            end
            
            // 즉각 반응을 위해 원시 입력에도 반응
            if (btn_sync[2] && !btn_sync[1]) begin
                btn_run_out <= 1'b1;  // 원시 입력 상승 에지에도 즉시 반응   // btn_start_out에서 btn_run_out으로 변경
            end
        end
    end
endmodule
// module btn_start_debounce (
//     input clk,
//     input reset,
//     input btn_start_in,
//     output reg btn_start_out
// );
//     // 동기화 및 디바운스 레지스터
//     reg [2:0] btn_sync;
//     reg [19:0] debounce_counter;
//     parameter DEBOUNCE_DELAY = 20'd100000; // 1ms @ 100MHz
    
//     // 주기적 펄스 생성을 위한 카운터
//     reg [25:0] pulse_counter;
//     parameter PULSE_PERIOD = 26'd10000000; // 0.1초마다 펄스 생성 (100MHz 기준)
    
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             btn_sync <= 3'b000;
//             debounce_counter <= 20'd0;
//             btn_start_out <= 1'b0;
//             pulse_counter <= 26'd0;
//         end else begin
//             // 3단계 동기화
//             btn_sync <= {btn_sync[1:0], btn_start_in};
            
//             // 디바운싱
//             if (btn_sync[2] != btn_sync[1]) begin
//                 // 버튼 상태 변화 감지되면 카운터 리셋
//                 debounce_counter <= 20'd0;
//             end else if (debounce_counter < DEBOUNCE_DELAY) begin
//                 // 안정화 대기
//                 debounce_counter <= debounce_counter + 1;
//             end else begin
//                 // 안정화된 상태에서:
//                 // 1. 버튼 상승 엣지 검출 시 즉시 펄스 생성
//                 if (btn_sync[2] == 1'b1 && pulse_counter == 0) begin
//                     btn_start_out <= 1'b1;
//                     pulse_counter <= 26'd1; // 카운팅 시작
//                 // 2. 버튼이 계속 눌려있는 경우 주기적으로 펄스 생성
//                 end else if (btn_sync[2] == 1'b1 && pulse_counter >= PULSE_PERIOD) begin
//                     btn_start_out <= 1'b1;
//                     pulse_counter <= 26'd1; // 카운팅 재시작
//                 end else begin
//                     // 펄스는 짧게 유지 (1 클럭)
//                     btn_start_out <= 1'b0;
                    
//                     // 버튼이 눌려있는 동안 계속 카운팅
//                     if (btn_sync[2] == 1'b1) begin
//                         pulse_counter <= pulse_counter + 1;
//                     end else begin
//                         // 버튼에서 손을 떼면 카운터 리셋
//                         pulse_counter <= 26'd0;
//                     end
//                 end
//             end
//         end
//     end
// endmodule
// module btn_start_debounce (
//     input clk,
//     input reset,
//     input btn_start_in,
//     output reg btn_start_out
// );
//     // 동기화 및 디바운스 레지스터
//     reg [2:0] btn_sync;
//     reg [19:0] debounce_counter;
//     parameter DEBOUNCE_DELAY = 20'd100000; // 1ms @ 100MHz
    
//     // 엣지 감지 레지스터
//     reg btn_prev;
//     wire btn_edge;
    
//     // 엣지 감지
//     assign btn_edge = btn_sync[2] & ~btn_prev;
    
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             btn_sync <= 3'b000;
//             debounce_counter <= 20'd0;
//             btn_start_out <= 1'b0;
//             btn_prev <= 1'b0;
//         end else begin
//             // 3단계 동기화
//             btn_sync <= {btn_sync[1:0], btn_start_in};
            
//             // 이전 버튼 상태 저장
//             btn_prev <= btn_sync[2];
            
//             // 디바운싱
//             if (btn_sync[2] != btn_sync[1]) begin
//                 // 버튼 상태 변화 감지되면 카운터 리셋
//                 debounce_counter <= 20'd0;
//             end else if (debounce_counter < DEBOUNCE_DELAY) begin
//                 // 안정화 대기
//                 debounce_counter <= debounce_counter + 1;
//             end else if (btn_edge) begin
//                 // 상승 엣지 감지되면 출력 펄스 생성
//                 btn_start_out <= 1'b1;
//             end else begin
//                 btn_start_out <= 1'b0;
//             end
//         end
//     end
// endmodule