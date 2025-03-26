module main(
    input clk,        // 50MHz 클럭
    input reset,      // 리셋 신호
    input echo,       // 울트라소닉 센서 에코 신호
    input button,     // 버튼 입력 신호
    output trigger,   // 울트라소닉 센서 트리거 신호
    output [7:0] fnd_font,  // FND에 표시할 값
    output [3:0] fnd_comm   // FND 자리 선택
);

    // 1us 타이머 (clock division)
    wire clk_1us;
    wire [15:0] w_distance;

    // 울트라소닉 제어 유닛 (FSM을 통한 제어)
    wire [19:0] time_count;
    wire trigger_signal;

    // 버튼 디바운싱
    wire debounced_button;

    debounce u_debounce (
        .clk(clk),
        .reset(reset),
        .button_in(button),
        .button_out(debounced_button)
    );

    // 1us 클럭 생성 (50MHz -> 1us 분주기)
    clk_divider_1 u_clk_divider (
        .clk(clk),
        .reset(reset),
        .o_clk(clk_1us)
    );

    // Ultrasonic 센서 제어 (Trigger 및 Echo 신호)
    us_cu u_us_cu (
        .clk(clk_1us),
        .reset(reset),
        .echo(echo),
        .trigger(trigger_signal),
        .time_count(time_count)
    );

    // 거리 계산 모듈 (time_count를 바탕으로 거리 변환)
    dist u_dist (
        .time_count(time_count),
        .distance(w_distance),
        .done()  // 완료 신호는 사용 안 함
    );

    // FND 컨트롤러 (거리 값을 7세그먼트로 표시)
    fnd_controller u_fnd_controller (
        .clk(clk),
        .reset(reset),
        .data_in(w_distance),  // 거리 값 입력
        .fnd_font(fnd_font),
        .fnd_comm(fnd_comm)
    );

    // 버튼 눌렀을 때 트리거 신호 설정
    reg trigger_signal_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            trigger_signal_reg <= 0;
        end else if (debounced_button) begin
            trigger_signal_reg <= 1;  // 버튼 눌렸을 때 트리거 신호 활성화
        end else begin
            trigger_signal_reg <= 0;  // 버튼 떼었을 때 트리거 비활성화
        end
    end

    // 트리거 신호 연결
    assign trigger = trigger_signal_reg;

endmodule

module debounce(
    input clk,
    input reset,
    input button_in,    // 버튼 입력
    output reg button_out  // 디바운싱 처리된 버튼 출력
);

    reg [3:0] button_shift_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            button_shift_reg <= 4'b1111;  // 리셋 시 버튼 상태 초기화
            button_out <= 0;
        end else begin
            button_shift_reg <= {button_shift_reg[2:0], button_in};  // 시프트 레지스터
            if (button_shift_reg == 4'b1110) button_out <= 1;  // 버튼 눌림
            else if (button_shift_reg == 4'b0001) button_out <= 0;  // 버튼 떼짐
        end
    end

endmodule

module bin_to_bcd (
    input [15:0] binary,
    output reg [3:0] thousands,
    output reg [3:0] hundreds,
    output reg [3:0] tens,
    output reg [3:0] ones
);
    integer i;
    reg [19:0] bcd;

    always @(*) begin
        bcd = 0;
        bcd[15:0] = binary;  // 16비트 값을 BCD 변환 시작

        for (i = 0; i < 16; i = i + 1) begin
            if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
            if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
            if (bcd[11:8]  >= 5) bcd[11:8]  = bcd[11:8]  + 3;
            if (bcd[7:4]   >= 5) bcd[7:4]   = bcd[7:4]   + 3;
            
            bcd = bcd << 1;  // 왼쪽으로 쉬프트
        end

        thousands = bcd[19:16];
        hundreds  = bcd[15:12];
        tens      = bcd[11:8];
        ones      = bcd[7:4];
    end
endmodule

// 1us 클럭 분주기 (bard tick 1us module)
module clk_divider_1(
    input clk,       // 50MHz 클럭
    input reset,     // 리셋 신호
    output reg o_clk // 1us 클럭 출력
);

    parameter CLK_DIV = 50;  // 50MHz -> 1us 타이머를 위한 분주기 설정
    reg [15:0] count;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;
            o_clk <= 0;
        end else begin
            if (count == CLK_DIV - 1) begin
                count <= 0;
                o_clk <= ~o_clk;
            end else begin
                count <= count + 1;
            end
        end
    end

endmodule

////////////////////////////////////////////////////////////////////////////////
// 울트라소닉 제어 유닛 (FSM - us controller)
module us_cu(
    input clk,
    input reset,
    input echo,
    output reg trigger,
    output reg [19:0] time_count
);

    reg [19:0] counter;
    reg echo_prev;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            trigger <= 0;
            counter <= 0;
            time_count <= 0; 
        end else begin
            // Trigger Pulse: 10us 하이로 유지
            if (counter < 1000) begin
                trigger <= 1;
            end else begin
                trigger <= 0;
            end

            // Echo 신호 상승 에지에서 카운터 초기화
            if (echo && !echo_prev) begin
                counter <= 0;  // 카운터 초기화
            end 
            // Echo 신호 하강 에지에서 time_count 업데이트
            else if (!echo && echo_prev) begin
                time_count <= counter;  // 반사 시간 기록
            end else begin
                counter <= counter + 1;  // 카운터 증가
            end

            echo_prev <= echo;  // echo_prev 값 갱신
        end
    end

endmodule

////////////////////////////////////////////////////////////////////////////////
// 거리 계산 모듈 (dist calculator)
module dist(
    input [19:0] time_count,
    output reg [15:0] distance,
    output reg done   // 거리 계산 완료 신호
);

    always @(*) begin
        distance = (time_count * 34) / 2000; // 음속 340m/s -> 거리 계산 (cm)
        done = (time_count != 0);  // time_count가 0이 아니면 계산 완료
    end

endmodule