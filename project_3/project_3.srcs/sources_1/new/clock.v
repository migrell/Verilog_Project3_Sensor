`timescale 1ns / 1ps

module clock(
    input clk,
    input reset,
    input btn_sec,
    input btn_min,
    input btn_hour,
    input enable,
    output o_1hz,
    output reg [6:0] o_msec,
    output reg [5:0] o_sec, o_min,
    output reg [4:0] o_hour
);
    // 1Hz 신호 생성 (1초마다 펄스)
    reg [26:0] clk_counter;
    
    // 100Hz 신호 생성 (msec 용)
    reg [19:0] msec_counter;
    wire msec_pulse;
    
    // 버튼 에지 감지를 위한 이전 버튼 상태 레지스터 추가
    reg prev_btn_hour, prev_btn_min, prev_btn_sec;
    
    // 버튼 디바운싱을 위한 카운터 추가
    reg [7:0] debounce_count_hour;
    reg [7:0] debounce_count_min;
    reg [7:0] debounce_count_sec;
    
    // 처리된 버튼 신호
    reg btn_hour_processed;
    reg btn_min_processed;
    reg btn_sec_processed;
    
    // 버튼 이전 상태 추적 및 디바운싱
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            prev_btn_hour <= 1'b0;
            prev_btn_min <= 1'b0;
            prev_btn_sec <= 1'b0;
            debounce_count_hour <= 8'd0;
            debounce_count_min <= 8'd0;
            debounce_count_sec <= 8'd0;
            btn_hour_processed <= 1'b0;
            btn_min_processed <= 1'b0;
            btn_sec_processed <= 1'b0;
        end else begin
            // 이전 버튼 상태 업데이트
            prev_btn_hour <= btn_hour;
            prev_btn_min <= btn_min;
            prev_btn_sec <= btn_sec;
            
            // 기본적으로 처리된 버튼 신호는 비활성화
            btn_hour_processed <= 1'b0;
            btn_min_processed <= 1'b0;
            btn_sec_processed <= 1'b0;
            
            // Hour 버튼 디바운싱
            if (btn_hour & ~prev_btn_hour) begin
                // 상승 에지 감지됨
                if (debounce_count_hour == 8'd0) begin
                    // 첫 번째 감지일 때만 신호 처리
                    btn_hour_processed <= 1'b1;
                    debounce_count_hour <= 8'd200; // 디바운싱 카운터 설정 (약 2µs @ 100MHz)
                end
            end else if (debounce_count_hour > 0) begin
                debounce_count_hour <= debounce_count_hour - 1;
            end
            
            // Min 버튼 디바운싱
            if (btn_min & ~prev_btn_min) begin
                // 상승 에지 감지됨
                if (debounce_count_min == 8'd0) begin
                    // 첫 번째 감지일 때만 신호 처리
                    btn_min_processed <= 1'b1;
                    debounce_count_min <= 8'd200; // 디바운싱 카운터 설정
                end
            end else if (debounce_count_min > 0) begin
                debounce_count_min <= debounce_count_min - 1;
            end
            
            // Sec 버튼 디바운싱
            if (btn_sec & ~prev_btn_sec) begin
                // 상승 에지 감지됨
                if (debounce_count_sec == 8'd0) begin
                    // 첫 번째 감지일 때만 신호 처리
                    btn_sec_processed <= 1'b1;
                    debounce_count_sec <= 8'd200; // 디바운싱 카운터 설정
                end
            end else if (debounce_count_sec > 0) begin
                debounce_count_sec <= debounce_count_sec - 1;
            end
        end
    end
    
    // 1Hz 클럭 생성
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_counter <= 0;
        end else begin
            if (clk_counter >= 100_000_000 - 1) begin  // 100MHz 클럭에서 1초
                clk_counter <= 0;
            end else begin
                clk_counter <= clk_counter + 1;
            end
        end
    end
    
    assign o_1hz = (clk_counter == 100_000_000 - 1);
    
    // 100Hz 클럭 생성 (msec 계산용)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            msec_counter <= 0;
        end else begin
            if (msec_counter >= 1_000_000 - 1) begin  // 100MHz 클럭에서 10ms
                msec_counter <= 0;
            end else begin
                msec_counter <= msec_counter + 1;
            end
        end
    end
    
    assign msec_pulse = (msec_counter == 1_000_000 - 1);
    
    // 시계 카운팅 로직
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            o_msec <= 0;
            o_sec <= 0;
            o_min <= 0;
            o_hour <= 0;
        end
        
        else if (enable) begin
            // msec 카운팅 (100Hz로 작동)
            if (msec_pulse) begin
                if (o_msec >= 99) begin
                    o_msec <= 0;
                end else begin
                    o_msec <= o_msec + 1;
                end
            end
            
            // 시 버튼이 처리된 경우에만 증가
            if (btn_hour_processed) begin
                if (o_hour >= 23) begin
                    o_hour <= 0;
                end else begin
                    o_hour <= o_hour + 1;
                end
            end
            
            // 분 버튼이 처리된 경우에만 증가
            else if (btn_min_processed) begin
                if (o_min >= 59) begin
                    o_min <= 0;
                end else begin
                    o_min <= o_min + 1;
                end
            end
            
            // 초 버튼이 처리된 경우에만 증가
            else if (btn_sec_processed) begin
                if (o_sec >= 59) begin
                    o_sec <= 0;
                end else begin
                    o_sec <= o_sec + 1;
                end
            end
            
            // 자동 카운팅 (버튼이 눌리지 않았을 때)
            else if (o_1hz) begin
                // 초 증가
                o_msec <= 0; // 새로운 초가 시작될 때 밀리초 초기화
                
                if (o_sec >= 59) begin
                    o_sec <= 0;
                    // 분 증가
                    if (o_min >= 59) begin
                        o_min <= 0;
                        // 시간 증가
                        if (o_hour >= 23) begin
                            o_hour <= 0;
                        end else begin
                            o_hour <= o_hour + 1;
                        end
                    end else begin
                        o_min <= o_min + 1;
                    end
                end else begin
                    o_sec <= o_sec + 1;
                end
            end
        end
    end
endmodule
//이전 코드
// `timescale 1ns / 1ps

// module clock(
//     input clk,
//     input reset,
//     input btn_sec,
//     input btn_min,
//     input btn_hour,
//     input enable,
//     output o_1hz,
//     output reg [6:0] o_msec,
//     output reg [5:0] o_sec, o_min,
//     output reg [4:0] o_hour
// );
//     // 1Hz 신호 생성 (1초마다 펄스)
//     reg [26:0] clk_counter;
    
//     // 100Hz 신호 생성 (msec 용)
//     reg [19:0] msec_counter;
//     wire msec_pulse;
    
//     // 1Hz 클럭 생성
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             clk_counter <= 0;
//         end else begin
//             if (clk_counter >= 100_000_000 - 1) begin  // 100MHz 클럭에서 1초
//                 clk_counter <= 0;
//             end else begin
//                 clk_counter <= clk_counter + 1;
//             end
//         end
//     end
    
//     assign o_1hz = (clk_counter == 100_000_000 - 1);
    
//     // 100Hz 클럭 생성 (msec 계산용)
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             msec_counter <= 0;
//         end else begin
//             if (msec_counter >= 1_000_000 - 1) begin  // 100MHz 클럭에서 10ms
//                 msec_counter <= 0;
//             end else begin
//                 msec_counter <= msec_counter + 1;
//             end
//         end
//     end
    
//     assign msec_pulse = (msec_counter == 1_000_000 - 1);
    
//     // 시계 카운팅 로직
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             o_msec <= 0;
//             o_sec <= 0;
//             o_min <= 0;
//             o_hour <= 0;
//         end
        
//         else if (enable) begin
//             // msec 카운팅 (100Hz로 작동)
//             if (msec_pulse) begin
//                 if (o_msec >= 99) begin
//                     o_msec <= 0;
//                 end else begin
//                     o_msec <= o_msec + 1;
//                 end
//             end
            
//             // 시 버튼이 눌렸을 때
//             if (btn_hour) begin
//                 if (o_hour >= 23) begin
//                     o_hour <= 0;
//                 end else begin
//                     o_hour <= o_hour + 1;
//                 end
//             end
            
//             // 분 버튼이 눌렸을 때
//             else if (btn_min) begin
//                 if (o_min >= 59) begin
//                     o_min <= 0;
//                 end else begin
//                     o_min <= o_min + 1;
//                 end
//             end
            
//             // 초 버튼이 눌렸을 때
//             else if (btn_sec) begin
//                 if (o_sec >= 59) begin
//                     o_sec <= 0;
//                 end else begin
//                     o_sec <= o_sec + 1;
//                 end
//             end
            
//             // 자동 카운팅 (버튼이 눌리지 않았을 때)
//             else if (o_1hz) begin
//                 // 초 증가
//                 o_msec <= 0; // 새로운 초가It  시작될 때 밀리초 초기화
                
//                 if (o_sec >= 59) begin
//                     o_sec <= 0;
//                     // 분 증가
//                     if (o_min >= 59) begin
//                         o_min <= 0;
//                         // 시간 증가
//                         if (o_hour >= 23) begin
//                             o_hour <= 0;
//                         end else begin
//                             o_hour <= o_hour + 1;
//                         end
//                     end else begin
//                         o_min <= o_min + 1;
//                     end
//                 end else begin
//                     o_sec <= o_sec + 1;
//                 end
//             end
//         end
//     end
// endmodule