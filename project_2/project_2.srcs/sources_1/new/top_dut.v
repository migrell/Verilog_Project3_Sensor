`timescale 1ns / 1ps

module top_dut(
    input clk,
    input rst,
    input btn_start,
    
    output [8:0] led,  // 9개 LED로 확장
    output fsm_error,
    output dut_io,
    
    // FSM 상태 모니터링을 위한 출력 (9개 상태)
    output idle,
    output start,
    output wait_state,
    output read,
    // 추가된 상태 출력
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
    wire [8:0] led_status;  // LED 상태 9개로 확장

    // DUT 컨트롤러 인스턴스 (추가된 포트 연결)
    dut_ctr U_DUT_CTR(  
        .clk(clk),
        .rst(rst),
        .btn_start(btn_start),
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
        // 추가된 상태 출력 연결
        .sync_low_out(sync_low_out),
        .sync_high_out(sync_high_out),
        .data_sync_out(data_sync_out),
        .data_bit_out(data_bit_out),
        .stop_out(stop_out)
    );

    // 틱 생성기 인스턴스 (변경 없음)
    tick_gen U_TICK_GEN(
        .clk(clk),
        .rst(rst),
        .tick_10msec(tick_10msec)
    );
    
    // FSM 오류 감지 로직 (FSM 상태 개수를 고려하여 수정)
    assign fsm_error = (current_state > 4'b1000) || 
                      ((idle != 1) && (start != 1) && (wait_state != 1) && 
                       (sync_low_out != 1) && (sync_high_out != 1) && 
                       (data_sync_out != 1) && (data_bit_out != 1) && 
                       (stop_out != 1) && (read != 1));
    
    // 9개 LED 배열 직접 연결 - 상태 출력을 LED에 직접 매핑
    assign led = {idle, start, wait_state, sync_low_out, sync_high_out, 
                 data_sync_out, data_bit_out, stop_out, read};

endmodule

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
    

