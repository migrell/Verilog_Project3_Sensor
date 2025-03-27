// ----------------------
// [2] Tick Generator
// ----------------------
module tick_gen(
    input clk,
    input rst,
    output reg tick_10msec
);
    reg [19:0] tick_counter;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tick_counter <= 0;
            tick_10msec <= 0;
        end else begin
            if (tick_counter >= 1_000_000 - 1) begin  // 10ms 주기
                tick_counter <= 0;
                tick_10msec <= 1;
            end else begin
                tick_counter <= tick_counter + 1;
                // 펄스 폭을 크게 증가시킴 (약 50,000 클럭 동안 유지)
                if (tick_counter < 50000)
                    tick_10msec <= 1;
                else
                    tick_10msec <= 0;
            end
        end
    end
endmodule
// // ----------------------
// // [2] Tick Generator
// // ----------------------
// module tick_gen(
//     input clk,
//     input rst,
//     output reg tick_10msec
// );
//     reg [19:0] tick_counter;

//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             tick_counter <= 0;
//             tick_10msec <= 0;
//         end else begin
//             if (tick_counter >= 1_000_000 - 1) begin  // 10ms 주기
//                 tick_counter <= 0;
//                 tick_10msec <= 1;
//             end else begin
//                 tick_counter <= tick_counter + 1;
//                 if (tick_counter < 10)
//                     tick_10msec <= 1;
//                 else
//                     tick_10msec <= 0;
//             end
//         end
//     end
// endmodule



// module tick_gen(
//     input clk,
//     input rst,
//     output reg tick_10msec
// );
//     reg [19:0] tick_counter;
    
//     always @(posedge clk or posedge rst) begin
//         if (rst) begin
//             tick_counter <= 0;
//             tick_10msec <= 0;
//         end else begin
//             if (tick_counter >= 1_000_000 - 1) begin  // 10ms 주기
//                 tick_counter <= 0;
//                 tick_10msec <= 1;  // 펄스 시작
//             end else begin
//                 tick_counter <= tick_counter + 1;
                
//                 // 펄스 유지 시간을 10 클럭 사이클로 설정
//                 if (tick_counter < 10)
//                     tick_10msec <= 1;
//                 else
//                     tick_10msec <= 0;
//             end
//         end
//     end
// endmodule