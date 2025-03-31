`timescale 1ns / 1ps

// ----------------------
// [1] 디바운스 모듈
// ----------------------
module debounce_btn(
    input clk,
    input rst,
    input noisy_btn,           // 입력 버튼
    output reg debounced_btn   // 디바운싱된 출력
);
    // 동기화 및 디바운스용 레지스터
    reg [2:0] sync;
    reg [19:0] stable_counter;
    
    // 엣지 감지 관련 레지스터
    reg prev_debounced;
    reg [19:0] pulse_width_counter;
    reg pulse_active;
    
    // 메인 디바운스 로직
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync <= 3'b000;
            stable_counter <= 0;
            debounced_btn <= 0;
            prev_debounced <= 0;
            pulse_width_counter <= 0;
            pulse_active <= 0;
        end else begin
            // 동기화 - 메타스테이빌리티 방지
            sync <= {sync[1:0], noisy_btn};
            
            // 디바운스 로직
            if (sync[2] != sync[1]) begin
                // 입력이 변경되면 카운터 리셋
                stable_counter <= 0;
            end else if (stable_counter < 20'd50000) begin  // 약 0.5ms @ 100MHz로 감소
                // 안정화 시간 대기
                stable_counter <= stable_counter + 1;
            end else begin
                // 충분히 안정화되면 디바운스된 출력 업데이트
                debounced_btn <= sync[2];
            end
            
            // 이전 상태 저장
            prev_debounced <= debounced_btn;
            
            // 엣지 감지 및 펄스 폭 확장 로직
            if (debounced_btn && !prev_debounced) begin
                // 상승 엣지 감지 시 펄스 활성화
                pulse_active <= 1;
                pulse_width_counter <= 0;
            end else if (pulse_active) begin
                if (pulse_width_counter < 20'd25000) begin
                    // 펄스 유지 (약 0.25ms @ 100MHz)
                    pulse_width_counter <= pulse_width_counter + 1;
                end else begin
                    // 펄스 종료 및 디바운스 출력 비활성화
                    pulse_active <= 0;
                    debounced_btn <= 0;  // 자동으로 버튼을 해제
                end
            end
        end
    end
endmodule


// `timescale 1ns / 1ps

// // ----------------------
// // [1] 디바운스 모듈
// // ----------------------
// module debounce_btn(
//     input clk,
//     input rst,
//     input noisy_btn,           // 입력 버튼
//     output reg debounced_btn   // 디바운싱된 출력
// );
//     // 동기화 및 디바운스용 레지스터
//     reg [2:0] sync;
//     reg [19:0] stable_counter;
    
//     // 엣지 감지 관련 레지스터
//     reg prev_debounced;
//     reg [19:0] pulse_width_counter;
//     reg pulse_active;
    
//     // 메인 디바운스 로직
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             sync <= 3'b000;
//             stable_counter <= 0;
//             debounced_btn <= 0;
//             prev_debounced <= 0;
//             pulse_width_counter <= 0;
//             pulse_active <= 0;
//         end else begin
//             // 동기화 - 메타스테이빌리티 방지
//             sync <= {sync[1:0], noisy_btn};
            
//             // 디바운스 로직
//             if (sync[2] != sync[1]) begin
//                 // 입력이 변경되면 카운터 리셋
//                 stable_counter <= 0;
//             end else if (stable_counter < 20'd100000) begin  // 약 1ms @ 100MHz
//                 // 안정화 시간 대기
//                 stable_counter <= stable_counter + 1;
//             end else begin
//                 // 충분히 안정화되면 디바운스된 출력 업데이트
//                 debounced_btn <= sync[2];
//             end
            
//             // 이전 상태 저장
//             prev_debounced <= debounced_btn;
            
//             // 엣지 감지 및 펄스 폭 확장 로직
//             if (debounced_btn && !prev_debounced) begin
//                 // 상승 엣지 감지 시 펄스 활성화
//                 pulse_active <= 1;
//                 pulse_width_counter <= 0;
//             end else if (pulse_active) begin
//                 if (pulse_width_counter < 20'd50000) begin
//                     // 펄스 유지 (약 0.5ms @ 100MHz)
//                     pulse_width_counter <= pulse_width_counter + 1;
//                 end else begin
//                     // 펄스 종료 및 디바운스 출력 비활성화
//                     pulse_active <= 0;
//                     debounced_btn <= 0;  // 이 부분이 중요: 자동으로 버튼을 해제
//                 end
//             end
//         end
//     end
// endmodule

// `timescale 1ns / 1ps

// module debounce_btn(
//     input clk,
//     input rst,
//     input noisy_btn,           // 입력 버튼
//     output reg debounced_btn   // 디바운싱된 출력
// );
//     reg [2:0] sync;
//     reg [15:0] stable_counter;

//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             sync <= 3'b000;
//             stable_counter <= 0;
//             debounced_btn <= 0;
//         end else begin
//             // 버튼 동기화 (노이즈 제거)
//             sync <= {sync[1:0], noisy_btn};

//             if (sync[2] == sync[1]) begin
//                 if (stable_counter < 16'hFFFF)
//                     stable_counter <= stable_counter + 1;
//                 else
//                     debounced_btn <= sync[2];
//             end else begin
//                 stable_counter <= 0;
//             end
//         end
//     end
// endmodule
// // ----------------------
// // [1] 디바운스 모듈
// // ----------------------
// module debounce_btn(
//     input clk,
//     input rst,
//     input noisy_btn,           // 입력 버튼
//     output reg debounced_btn   // 디바운싱된 출력
// );
//     reg [2:0] sync;
//     reg [15:0] stable_counter;

//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             sync <= 3'b000;
//             stable_counter <= 0;
//             debounced_btn <= 0;
//         end else begin
//             // 버튼 동기화 (노이즈 제거)
//             sync <= {sync[1:0], noisy_btn};

//             if (sync[2] == sync[1]) begin
//                 if (stable_counter < 16'hFFFF)
//                     stable_counter <= stable_counter + 1;
//                 else
//                     debounced_btn <= sync[2];
//             end else begin
//                 stable_counter <= 0;
//             end
//         end
//     end
// endmodule



// `timescale 1ns / 1ps

// module debounce_btn(
//     input clk,
//     input rst,
//     input noisy_btn,           // 입력 버튼
//     output reg debounced_btn   // 디바운싱된 출력
// );
//     reg [2:0] sync;
//     reg [15:0] stable_counter;

//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             sync <= 3'b000;
//             stable_counter <= 0;
//             debounced_btn <= 0;
//         end else begin
//             // 버튼 동기화 (노이즈 제거)
//             sync <= {sync[1:0], noisy_btn};

//             if (sync[2] == sync[1]) begin
//                 if (stable_counter < 16'hFFFF)
//                     stable_counter <= stable_counter + 1;
//                 else
//                     debounced_btn <= sync[2];
//             end else begin
//                 stable_counter <= 0;
//             end
//         end
//     end
// endmodule
