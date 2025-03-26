module dnt_led (
    input clk,
    input rst,
    input fsm_error,
    output reg [4:0] led_status,
    output [4:0] led
);
    reg [24:0] led_counter;
    
    // LED 깜빡임 로직 개선
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            led_counter <= 0;
            led_status <= 5'b00000;
        end else begin
            if (fsm_error) begin
                // 오류 시 LED 깜빡임 (더 짧은 주기로 변경)
                if (led_counter >= 5000000) begin  // 깜빡임 주기 감소
                    led_counter <= 0;
                    led_status <= ~led_status;  // 모든 LED 토글
                end else begin
                    led_counter <= led_counter + 1;
                end
            end else begin
                // 정상 상태일 때는 모든 LED를 켜서 정상 동작 표시
                led_counter <= 0;
                led_status <= 5'b00001;  // 첫 번째 LED만 켜짐
            end
        end
    end

    // 최종 LED 출력 - fsm_error 시 모든 LED 켜짐
    assign led = fsm_error ? 5'b11111 : led_status;
endmodule