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
    reg [2:0] sync;
    reg [15:0] stable_counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync <= 3'b000;
            stable_counter <= 0;
            debounced_btn <= 0;
        end else begin
            // 버튼 동기화 (노이즈 제거)
            sync <= {sync[1:0], noisy_btn};

            if (sync[2] == sync[1]) begin
                if (stable_counter < 16'hFFFF)
                    stable_counter <= stable_counter + 1;
                else
                    debounced_btn <= sync[2];
            end else begin
                stable_counter <= 0;
            end
        end
    end
endmodule



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
