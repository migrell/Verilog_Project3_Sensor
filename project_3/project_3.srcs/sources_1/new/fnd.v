module fnd_controller(
    input clk,
    input reset,
    input sw_mode,
    input [1:0] sw,
    input [6:0] msec,
    input [5:0] sec,
    input [5:0] min,
    input [4:0] hour,
    input [1:0] current_state,  // Add this line
    output [7:0] fnd_font,
    output [3:0] fnd_comm
);
    wire [3:0] w_digit_msec_1, w_digit_msec_10,
               w_digit_sec_1, w_digit_sec_10,
               w_digit_min_1, w_digit_min_10,
               w_digit_hour_1, w_digit_hour_10;
    wire [2:0] w_seg_sel;
    wire w_clk_100hz;
    
    // 도트 토글 신호 생성 (0.5초 간격)
    reg [24:0] dot_counter;
    reg r_dot_toggle;
    
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            dot_counter <= 0;
            r_dot_toggle <= 0;
        end else begin
            if (dot_counter == 25_000_000 - 1) begin  // 0.5초마다 (100MHz 기준)
                dot_counter <= 0;
                r_dot_toggle <= ~r_dot_toggle;  // 도트 상태 반전
            end else begin
                dot_counter <= dot_counter + 1;
            end
        end
    end

    // 클럭 분주 (100Hz 생성)
    clk_divider U_clk_divider(
        .clk(clk),
        .reset(reset),
        .o_clk(w_clk_100hz)
    );

    // 디스플레이 스캔 카운터
    counter_8 U_counter_8(
        .clk(w_clk_100hz),
        .reset(reset),
        .o_sel(w_seg_sel)
    );

    // 디스플레이 선택 디코더
    decoder_3x8 U_decoder(
        .seg_select(w_seg_sel),
        .seg_comm(fnd_comm)
    );

    // msec 값 분할
    digit_splitter #(.BIT_WIDTH(7)) U_msec_ds(
        .bcd(msec),
        .digit_1(w_digit_msec_1),
        .digit_10(w_digit_msec_10)
    );

    // sec 값 분할
    digit_splitter #(.BIT_WIDTH(6)) U_sec_ds(
        .bcd(sec),
        .digit_1(w_digit_sec_1),
        .digit_10(w_digit_sec_10)
    );

    // min 값 분할
    digit_splitter #(.BIT_WIDTH(6)) U_min_ds(
        .bcd(min),
        .digit_1(w_digit_min_1),
        .digit_10(w_digit_min_10)
    );

    // hour 값 분할
    digit_splitter #(.BIT_WIDTH(5)) U_hour_ds(
        .bcd(hour),
        .digit_1(w_digit_hour_1),
        .digit_10(w_digit_hour_10)
    );

    // 멀티플렉서에서 선택된 BCD 값
    reg [3:0] r_bcd;
    reg dot_out;
    
    // FSM 상태에 따른 디스플레이 로직 수정
    // 멀티플렉서 로직 수정 - FSM 상태에 맞게 조정
    
    always @(*) begin
    // 기본값
    r_bcd = 4'h0;
    dot_out = 1'b1;  // 도트 OFF (active low)

    case (current_state)
        2'b00: begin // STATE_0: Stopwatch Mode Msec:Sec
            case (w_seg_sel[1:0])
                2'b00: begin r_bcd = w_digit_sec_1; dot_out = 1'b1; end    // 밀리초 1의 자리
                2'b01: begin r_bcd = w_digit_sec_10; dot_out = 1'b1; end   // 밀리초 10의 자리
                2'b10: begin r_bcd = w_digit_msec_1; dot_out = ~r_dot_toggle; end  // 초 1의 자리, 도트 깜빡임
                2'b11: begin r_bcd = w_digit_msec_10; dot_out = 1'b1; end    // 초 10의 자리
            endcase
        end

        2'b01: begin // STATE_1: Stopwatch Mode Hour:Min
            case (w_seg_sel[1:0])
                2'b00: begin r_bcd = w_digit_min_1; dot_out = 1'b1; end     // 분 1의 자리
                2'b01: begin r_bcd = w_digit_min_10; dot_out = 1'b1; end    // 분 10의 자리
                2'b10: begin r_bcd = w_digit_hour_1; dot_out = ~r_dot_toggle; end // 시 1의 자리, 도트 깜빡임
                2'b11: begin r_bcd = w_digit_hour_10; dot_out = 1'b1; end   // 시 10의 자리
            endcase
        end

        2'b10: begin // STATE_2: Clock Mode Sec:Msec
            case (w_seg_sel[1:0])
                2'b00: begin r_bcd = w_digit_msec_1; dot_out = 1'b1; end     // 초 1의 자리
                2'b01: begin r_bcd = w_digit_msec_10; dot_out = 1'b1; end    // 초 10의 자리
                2'b10: begin r_bcd = w_digit_sec_1; dot_out = ~r_dot_toggle; end // 밀리초 1의 자리, 도트 깜빡임
                2'b11: begin r_bcd = w_digit_sec_10; dot_out = 1'b1; end   // 밀리초 10의 자리
            endcase
        end

        2'b11: begin // STATE_3: Clock Mode Hour:Min
            case (w_seg_sel[1:0])
                2'b00: begin r_bcd = w_digit_min_1; dot_out = 1'b1; end     // 분 1의 자리
                2'b01: begin r_bcd = w_digit_min_10; dot_out = 1'b1; end    // 분 10의 자리
                2'b10: begin r_bcd = w_digit_hour_1; dot_out = ~r_dot_toggle; end // 시 1의 자리, 도트 깜빡임
                2'b11: begin r_bcd = w_digit_hour_10; dot_out = 1'b1; end   // 시 10의 자리
            endcase
        end
    endcase
end


    wire [6:0] seg_pattern;
    // BCD를 7세그먼트로 변환
    bcdtoseg U_bcdtoseg(
        .bcd(r_bcd),
        .seg(seg_pattern)
    );
    
    // 최종 출력: 세그먼트 패턴 + 도트
    assign fnd_font = {dot_out, seg_pattern};  // MSB가 도트
    
endmodule




// --------------------------------------------------------------//


module clk_divider (
    input clk,
    input reset,
    output o_clk
);

    // 100MHz를 100Hz로 분주 (500,000 카운트)
    parameter FCOUNT = 100_000;

    reg [$clog2(FCOUNT)-1:0] r_counter;  
    reg r_clk;
    
    assign o_clk = r_clk;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            r_counter <= 0;
            r_clk <= 1'b0;  
        end else begin
            if (r_counter == FCOUNT - 1) begin
                r_counter <= 0;
                r_clk <= ~r_clk;  // 50% 듀티 사이클을 위해 반전
            end else begin
                r_counter <= r_counter + 1;
            end
        end
    end

endmodule




module counter_8 (
    input clk,
    input reset,
    output [2:0] o_sel
);

    reg [2:0] r_counter;
    assign o_sel = r_counter;

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            r_counter <= 0;
        end else begin
            r_counter <= r_counter + 1;
        end
    end
    
endmodule




module decoder_3x8 (
    input [2:0] seg_select,
    output reg [3:0] seg_comm
);

    always @(seg_select) begin
        case (seg_select)
            3'b000: seg_comm = 4'b1110;  // 첫 번째 자리
            3'b001: seg_comm = 4'b1101;  // 두 번째 자리
            3'b010: seg_comm = 4'b1011;  // 세 번째 자리
            3'b011: seg_comm = 4'b0111;  // 네 번째 자리
            3'b100: seg_comm = 4'b1110;  // 다섯 번째 자리 (첫 번째와 동일)
            3'b101: seg_comm = 4'b1101;  // 여섯 번째 자리 (두 번째와 동일)
            3'b110: seg_comm = 4'b1011;  // 일곱 번째 자리 (세 번째와 동일)
            3'b111: seg_comm = 4'b0111;  // 여덟 번째 자리 (네 번째와 동일)
            default: seg_comm = 4'b1111; // 모두 꺼짐
        endcase
    end
    
endmodule



module digit_splitter #(parameter BIT_WIDTH = 7)(
    input [BIT_WIDTH-1:0] bcd,
    output [3:0] digit_1,
    output [3:0] digit_10
);

    assign digit_1 = bcd % 10;  // 1의자리
    assign digit_10 = bcd / 10 % 10;  // 10의 자리
    
endmodule
//MUX 8X1
module mux_8x1 (
    input [2:0] sel, //8개선택
    input [3:0] x0,
    input [3:0] x1,
    input [3:0] x2,
    input [3:0] x3,
    input [3:0] x4,
    input [3:0] x5,
    input [3:0] x6,  
    input [3:0] x7,
    input dot_toggle,
    output reg dot_out,  
    output reg [3:0] y

);
 always @(*) begin
        case (sel)
           3'b000: begin y = x0; dot_out = 1'b0; end
            3'b001: begin y = x1; dot_out = 1'b0; end
            3'b010: begin y = x2; dot_out = 1'b0; end
            3'b011: begin y = x3; dot_out = 1'b0; end
            3'b100: begin y = x4; dot_out = 1'b0; end
            3'b101: begin y = x5; dot_out = 1'b0; end
            3'b110: begin y = x6; dot_out = dot_toggle; end // 7번째 자리(인덱스 6)에 도트 토글 적용
            3'b111: begin y = x7; dot_out = 1'b0; end
            default: begin y = 4'hf; dot_out = 1'b0; end
        endcase
    end
    endmodule





// module mux_4x1 (
//     input [1:0] sel,
//     input [3:0] digit_1,
//     input [3:0] digit_10,
//     input [3:0] digit_100,
//     input [3:0] digit_1000,
//     output [3:0] bcd
// );

//     reg [3:0] r_bcd;
//     assign bcd = r_bcd;

//     always @(sel, digit_1, digit_10, digit_100, digit_1000) begin
//         case (sel)
//             2'b00: r_bcd = digit_1;
//             2'b01: r_bcd = digit_10;
//             2'b10: r_bcd = digit_100;
//             2'b11: r_bcd = digit_1000; 
//             default: r_bcd = 4'bx;
//         endcase
//     end
    
// endmodule




module bcdtoseg (
    input [3:0] bcd,
    output reg [6:0] seg  // 7개 세그먼트만 (도트 제외)
);
    always @(bcd) begin
        case (bcd)
            4'h0: seg = 7'b1000000;  // 도트 비트 제외
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000;
            4'hB: seg = 7'b0000011;
            4'hC: seg = 7'b1000110;
            4'hD: seg = 7'b0100001;
            4'hE: seg = 7'b0000110;
            4'hF: seg = 7'b0001110;
            default: seg = 7'b1111111;
        endcase
    end
endmodule

module mux_2x1(
    input sw_mode,
    input [3:0] msec_sec,
    input [3:0] min_hour,
    input dot_msec_sec,
    input dot_min_hour,
    output reg [3:0] bcd,
    output reg dot_out
);
    always @(*) begin
        // 가운데 아래 세그먼트만 켜지도록 직접 값을 조작
        bcd = 4'hf;  // 이 값 자체는 중요하지 않음
        dot_out = 1'b1;  // 도트 꺼짐 (필요에 따라 조정)
    
    end
endmodule


// module clk_divider (
//     input clk,
//     input reset,
//     output o_clk
// );

//     // 100MHz를 100Hz로 분주 (500,000 카운트)
//     parameter FCOUNT = 100_000;

//     reg [$clog2(FCOUNT)-1:0] r_counter;  
//     reg r_clk;
    
//     assign o_clk = r_clk;

//     always @(posedge clk, posedge reset) begin
//         if (reset) begin
//             r_counter <= 0;
//             r_clk <= 1'b0;  
//         end else begin
//             if (r_counter == FCOUNT - 1) begin
//                 r_counter <= 0;
//                 r_clk <= ~r_clk;  // 50% 듀티 사이클을 위해 반전
//             end else begin
//                 r_counter <= r_counter + 1;
//             end
//         end
//     end

// endmodule


 


// 0.5초 간격으로 도트를 토글하는 모듈
module dot_module(
    input clk,
    input reset,
    output reg dot_toggle
);
    // 0.5초 간격의 카운터 (100MHz 기준)
    reg [24:0] dot_counter;
    
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            dot_counter <= 0;
            dot_toggle <= 0;
        end else begin
            if (dot_counter == 50_000_000 - 1) begin  // 0.5초마다
                dot_counter <= 0;
                dot_toggle <= ~dot_toggle;  // 도트 상태 반전
            end else begin
                dot_counter <= dot_counter + 1;
            end
        end
    end
endmodule