`timescale 1ns / 1ps

module top_dut (
    input clk,
    input rst,
    input btn_start,
    input btn_next,  // 추가 버튼 입력
    input [1:0] hw_sw,  // XDC 파일에 정의된 스위치

    output [8:0] led,  // 9개 LED로 확장
    output fsm_error,
    output dut_io,

    // FSM 상태 모니터링을 위한 출력
    output idle,
    output start,
    output wait_state,
    output read,
    output sync_low_out,
    output sync_high_out,
    output data_sync_out,
    output data_bit_out,
    output stop_out
);
    // 내부 신호
    wire tick_10msec;
    wire [3:0] current_state;
    wire [7:0] dnt_data;
    wire [7:0] dnt_sensor_data;
    wire sensor_data;

    
    wire btn_start_clean;
    wire btn_next_clean;

    // DUT 컨트롤러 인스턴스
    dut_ctr U_DUT_CTR (
        .clk(clk),
        .rst(rst),
        .btn_start(btn_start_clean),
        .btn_next(btn_next_clean),  // 추가 버튼 연결
        .tick_counter(tick_10msec),
        .sensor_data(sensor_data),
        .current_state(current_state),
        .dnt_data(dnt_data),
        .dnt_sensor_data(dnt_sensor_data),
        .dnt_io(dut_io),

        // FSM 상태 모니터링 출력 연결
        .idle(idle),
        .start(start),
        .wait_state(wait_state),
        .read(read),
        .sync_low_out(sync_low_out),
        .sync_high_out(sync_high_out),
        .data_sync_out(data_sync_out),
        .data_bit_out(data_bit_out),
        .stop_out(stop_out)
    );

    // 틱 생성기 인스턴스
    tick_gen U_TICK_GEN (
        .clk(clk),
        .rst(rst),
        .tick_10msec(tick_10msec)
    );


    debounce_btn U_DEBOUNCE_START (
        .clk(clk),
        .rst(rst),
        .noisy_btn(btn_start),
        .debounced_btn(btn_start_clean)
    );

    debounce_btn U_DEBOUNCE_NEXT (
        .clk(clk),
        .rst(rst),
        .noisy_btn(btn_next),
        .debounced_btn(btn_next_clean)
    );


    // FSM 오류 감지 로직
    assign fsm_error = (current_state > 4'b1000) || 
                      ((idle != 1) && (start != 1) && (wait_state != 1) && 
                       (sync_low_out != 1) && (sync_high_out != 1) && 
                       (data_sync_out != 1) && (data_bit_out != 1) && 
                       (stop_out != 1) && (read != 1));

    // 9개 LED 배열 직접 연결 - 상태 출력을 LED에 직접 매핑
    assign led = {
        idle,
        start,
        wait_state,
        sync_low_out,
        sync_high_out,
        data_sync_out,
        data_bit_out,
        stop_out,
        read
    };

endmodule

// 9개 LED 배열 직접 연결 - 상태

// `timescale 1ns / 1ps

// module top_dut(
//     input clk,
//     input rst,
//     input btn_start,

//     output [8:0] led,  // 9개 LED로 확장
//     output fsm_error,
//     output dut_io
// );
//     // 내부 신호
//     wire tick_10msec;
//     wire [3:0] current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire sensor_data;

//     // FSM 상태 신호를 내부 wire로 선언
//     wire idle;
//     wire start;
//     wire wait_state;
//     wire read;
//     wire sync_low_out;
//     wire sync_high_out;
//     wire data_sync_out;
//     wire data_bit_out;
//     wire stop_out;

//     // DUT 컨트롤러 인스턴스
//     dut_ctr U_DUT_CTR(  
//         .clk(clk),
//         .rst(rst),
//         .btn_start(btn_start),
//         .tick_counter(tick_10msec),
//         .sensor_data(sensor_data),
//         .current_state(current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dut_io),

//         // FSM 상태 모니터링 출력 연결
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .read(read),
//         .sync_low_out(sync_low_out),
//         .sync_high_out(sync_high_out),
//         .data_sync_out(data_sync_out),
//         .data_bit_out(data_bit_out),
//         .stop_out(stop_out)
//     );

//     // 틱 생성기 인스턴스
//     tick_gen U_TICK_GEN(
//         .clk(clk),
//         .rst(rst),
//         .tick_10msec(tick_10msec)
//     );

//     // FSM 오류 감지 로직
//     assign fsm_error = (current_state > 4'b1000) || 
//                       ((idle != 1) && (start != 1) && (wait_state != 1) && 
//                        (sync_low_out != 1) && (sync_high_out != 1) && 
//                        (data_sync_out != 1) && (data_bit_out != 1) && 
//                        (stop_out != 1) && (read != 1));

//     // 9개 LED 배열 직접 연결 - 상태 출력을 LED에 직접 매핑
//     assign led = {idle, start, wait_state, sync_low_out, sync_high_out, 
//                  data_sync_out, data_bit_out, stop_out, read};

// endmodule


// `timescale 1ns / 1ps

// module top_dut(
//     input clk,
//     input rst,
//     input btn_start,

//     output [4:0] led,
//     output fsm_error,
//     output dut_io,

//     // FSM 상태 모니터링을 위한 출력 추가
//     output idle,
//     output start,
//     output wait_state,
//     output read
// );
//     // 내부 신호
//     wire tick_10msec;
//     wire [3:0] current_state;
//     wire [7:0] dnt_data;
//     wire [7:0] dnt_sensor_data;
//     wire sensor_data;
//     wire [4:0] led_status;  // led_status 와이어 추가

//     // DUT 컨트롤러 인스턴스
//     dut_ctr U_DUT_CTR(  
//         .clk(clk),
//         .rst(rst),
//         .btn_start(btn_start),
//         .tick_counter(tick_10msec),
//         .sensor_data(sensor_data),
//         .current_state(current_state),
//         .dnt_data(dnt_data),
//         .dnt_sensor_data(dnt_sensor_data),
//         .dnt_io(dut_io),

//         // FSM 상태 모니터링 출력 연결
//         .idle(idle),
//         .start(start),
//         .wait_state(wait_state),
//         .read(read)
//     );

//     // 틱 생성기 인스턴스
//     tick_gen U_TICK_GEN(
//         .clk(clk),
//         .rst(rst),
//         .tick_10msec(tick_10msec)
//     );

//     // FSM 오류 감지 로직 개선 - 현재 state 기반
//     assign fsm_error = (current_state == 4'b1111) || 
//                        ((idle != 1) && (start != 1) && (wait_state != 1) && (read != 1));

//     // LED 컨트롤러 수정 및 연결
//     dnt_led U_DNT_LED(
//         .clk(clk),
//         .rst(rst),
//         .fsm_error(fsm_error),
//         .led_status(led_status),
//         .led(led)
//     );

// endmodule


