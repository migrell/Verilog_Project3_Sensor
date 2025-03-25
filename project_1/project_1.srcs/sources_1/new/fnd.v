module fnd_controller(
    input clk,
    input reset,
    input [6:0] msec,      // 거리 값 입력 (0-99cm)
    output [7:0] fnd_font,
    output [3:0] fnd_comm
);
    wire [3:0] w_digit_msec_1, w_digit_msec_10;
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

    // 멀티플렉서에서 선택된 BCD 값
    reg [3:0] r_bcd;
    reg dot_out;
    
    // 멀티플렉서 로직 - 간소화된 버전
    always @(*) begin
        // 기본값
        r_bcd = 4'h0;
        dot_out = 1'b1;  // 도트 OFF (active low)

        case (w_seg_sel[1:0])
            2'b00: begin r_bcd = w_digit_msec_1; dot_out = 1'b1; end    // cm 1의 자리
            2'b01: begin r_bcd = w_digit_msec_10; dot_out = 1'b1; end   // cm 10의 자리
            2'b10: begin r_bcd = 4'h0; dot_out = 1'b1; end              // 사용하지 않음
            2'b11: begin r_bcd = 4'h0; dot_out = 1'b1; end              // 사용하지 않음
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