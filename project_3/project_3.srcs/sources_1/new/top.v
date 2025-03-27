`timescale 1ns / 1ps

module top_stopwatch (
    input clk,
    input reset,
    input btn_run,  // 좌측 버튼 - 스톱워치 실행/정지/시 설정
    input btn_clear,  // 우측 버튼 - 스톱워치 초기화
    input btn_sec,  // 아래쪽 버튼 - 초 설정 (시계 모드)
    input btn_min,  // 위쪽 버튼 - 분 설정 (시계 모드)
    input [1:0] hw_sw,  // 추가: 하드웨어 스위치 입력
    input rx,  // UART RX 입력 추가
    output tx,  // UART TX 출력 추가
    output [3:0] fnd_comm,
    output [7:0] fnd_font,
    output [3:0] led
);
    // 디바운싱된 버튼 신호들
    wire w_btn_run, w_btn_clear, w_btn_min, w_btn_sec;
    // 모드별 버튼 분기
    wire w_btn_hour;

    // FSM 신호들
    wire [1:0] current_state;
    wire is_clock_mode, sw2, sw3;

    // 스톱워치 제어 신호
    wire w_run, w_clear;

    // 시간 데이터 신호들 (스톱워치와 시계)
    wire [6:0] s_msec, c_msec, disp_msec;
    wire [5:0] s_sec, s_min, c_sec, c_min, disp_sec, disp_min;
    wire [4:0] s_hour, c_hour, disp_hour;

    // UART로부터 오는 제어 신호
    wire [1:0] uart_sw;
    wire uart_w_run, uart_w_clear;
    wire uart_btn_hour, uart_btn_min, uart_btn_sec;
    // UART RX 신호 (수정 전 없었던 부분)
    wire w_rx_done;      // RX 완료 신호
    wire [7:0] w_rx_data; // RX 데이터

    // 하드웨어와 UART 스위치 신호 결합
    wire [1:0] combined_sw = hw_sw | uart_sw;  // 두 스위치 신호 중 하나라도 1이면 1

    // 최종 버튼 신호 (하드웨어 버튼 + UART 명령)
    wire final_btn_hour = (w_btn_hour | uart_btn_hour) & is_clock_mode; // 시계 모드 조건 추가
    wire final_btn_min = (w_btn_min | uart_btn_min) & is_clock_mode;    // 시계 모드 조건 추가
    wire final_btn_sec = (w_btn_sec | uart_btn_sec) & is_clock_mode;    // 시계 모드 조건 추가

    // 모드에 따른 버튼 기능 분기
    assign w_btn_hour = w_btn_run & is_clock_mode;  // 시계 모드에서 시간 설정 기능

    // LED 출력 할당
    assign led[0] = current_state[0];  // 현재 상태 하위 비트
    assign led[1] = current_state[1];  // 현재 상태 상위 비트
    assign led[2] = w_run;  // 스톱워치 실행 중일 때 켜짐
    assign led[3] = is_clock_mode;  // 시계 모드일 때 켜짐

    // 버튼 디바운싱 모듈들 (btn_type 파라미터 적용)
    btn_debounce U_Btn_DB_RUN (
        .clk(clk),
        .reset(reset),
        .i_btn(btn_run),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data),
        .btn_type(3'd0),
        .o_btn(w_btn_run)
    );

    btn_debounce U_Btn_DB_CLEAR (
        .clk(clk),
        .reset(reset),
        .i_btn(btn_clear),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data),
        .btn_type(3'd1),
        .o_btn(w_btn_clear)
    );

    btn_debounce U_Btn_DB_SEC (
        .clk(clk),
        .reset(reset),
        .i_btn(btn_sec),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data),
        .btn_type(3'd2),
        .o_btn(w_btn_sec)
    );

    btn_debounce U_Btn_DB_MIN (
        .clk(clk),
        .reset(reset),
        .i_btn(btn_min),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data),
        .btn_type(3'd3),
        .o_btn(w_btn_min)
    );

    // UART + FIFO + CU 모듈 추가
    uart_fifo_top U_UART_FIFO_TOP (
        .clk(clk),
        .rst(reset),
        .rx(rx),
        .tx(tx),
        .w_run(uart_w_run),
        .w_clear(uart_w_clear),
        .btn_hour(uart_btn_hour),
        .btn_min(uart_btn_min),
        .btn_sec(uart_btn_sec),
        .sw(uart_sw),
        .o_run(w_run),
        .current_state(current_state),
        .w_rx_done(w_rx_done),
        .w_rx_data(w_rx_data)
    );


    // FSM 컨트롤러 - 포트 이름 수정
    fsm_controller U_FSM (
        .clk(clk),
        .reset(reset),
        .sw(combined_sw),  // 변경: combined_sw로 연결
        .btn_run(w_btn_run | uart_w_run),  // 하드웨어 버튼 또는 UART 명령
        .sw_mode_in(is_clock_mode),  // 필요에 따라 적절한 신호 연결
        .current_state(current_state),
        .is_clock_mode(is_clock_mode),
        .sw2(sw2),
        .sw3(sw3)
    );

    // 스톱워치 제어 유닛
    stopwatch_cu U_STOPWATCH_CU (
        .clk(clk),
        .reset(reset),
        .i_btn_run((w_btn_run | uart_w_run) & ~is_clock_mode),  // 스톱워치 모드에서만 동작
        .i_btn_clear((w_btn_clear | uart_w_clear) & ~is_clock_mode),
        .o_run(w_run),
        .o_clear(w_clear)
    );

    // 스톱워치 데이터 패스
    stopwatch_dp U_STOPWATCH_DP (
        .clk  (clk),
        .reset(reset),
        .run  (w_run),
        .clear(w_clear),
        .msec (s_msec),
        .sec  (s_sec),
        .min  (s_min),
        .hour (s_hour)
    );

    // 시계 모듈
    clock U_CLOCK (
        .clk(clk),
        .reset(reset),
        .btn_sec(final_btn_sec),     // 시계 모드에서만 동작하도록 변경됨
        .btn_min(final_btn_min),     // 시계 모드에서만 동작하도록 변경됨
        .btn_hour(final_btn_hour),   // 시계 모드에서만 동작하도록 변경됨
        .enable(is_clock_mode),  // is_clock_mode 신호 사용
        .o_1hz(),
        .o_msec(c_msec),
        .o_sec(c_sec),
        .o_min(c_min),
        .o_hour(c_hour)
    );

    // 디스플레이 멀티플렉서
    display_mux U_DISPLAY_MUX (
        .sw_mode(is_clock_mode),     // is_clock_mode 사용
        .current_state(current_state),
        .sw_msec(s_msec),
        .sw_sec(s_sec),
        .sw_min(s_min),
        .sw_hour(s_hour),
        .clk_msec(c_msec),
        .clk_sec(c_sec),
        .clk_min(c_min),
        .clk_hour(c_hour),
        .o_msec(disp_msec),
        .o_sec(disp_sec),
        .o_min(disp_min),
        .o_hour(disp_hour)
    );

    // FND 컨트롤러
    fnd_controller U_FND_CTRL (
        .clk(clk),
        .reset(reset),
        .sw_mode(is_clock_mode),
        .sw(uart_sw),
        .current_state(current_state),
        .msec(disp_msec),
        .sec(disp_sec),
        .min(disp_min),
        .hour(disp_hour),
        .fnd_font(fnd_font),
        .fnd_comm(fnd_comm)
    );

endmodule