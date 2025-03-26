module dnt_led (
    input clk,
    input rst,
    input fsm_error,
    output reg [8:0] led_status,  // 9개 LED로 확장
    output [8:0] led  // 9개 LED로 확장
);
    reg [24:0] led_counter;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led_counter <= 0;
            led_status <= 9'b000000001;  // 첫 번째 LED만 켜짐 (IDLE 상태)
        end else begin
            if (fsm_error) begin
                // 오류 시 LED 깜빡임
                if (led_counter >= 5000000) begin
                    led_counter <= 0;
                    led_status <= ~led_status;  // 모든 LED 토글
                end else begin
                    led_counter <= led_counter + 1;
                end
            end else begin
                // 정상 상태일 때는 FSM 상태 표시를 위해 led_status 값은 변경하지 않음
                led_counter <= 0;
            end
        end
    end

    // 최종 LED 출력
    assign led = fsm_error ? 9'b111111111 : led_status;
endmodule