`timescale 1ns / 1ps

module tb_ultrasonic_distance_meter;
    // 입력 신호 선언
    reg clk;                // 시스템 클럭 (100MHz)
    reg reset;              // 리셋 신호
    reg echo;               // 초음파 센서 에코 핀
    reg btn_start;          // 시작 버튼
    
    // 출력 신호 선언
    wire trigger;           // 초음파 센서 트리거 핀
    wire [3:0] fnd_comm;    // FND 공통단자 선택 신호
    wire [7:0] fnd_font;    // FND 세그먼트 신호 (7세그먼트 + 도트)
    wire [3:0] led;         // LED 상태 출력
    
    // 내부 모니터링 신호 (테스트벤치에서만 사용)
    wire [6:0] monitor_msec;
    wire monitor_dp_done;
    wire monitor_start_dp;
    wire monitor_tick_10msec;
    
    // 테스트 시나리오를 위한 파라미터
    parameter CLK_PERIOD = 10;  // 10ns (100MHz)
    parameter ECHO_DELAY = 1000; // 에코 시작까지 딜레이 (1us)
    parameter ECHO_WIDTH = 5800*17; // 17cm에 해당하는 에코 폭 (약 17*58us)
    
    // DUT (Design Under Test) 인스턴스화
    ultrasonic_distance_meter DUT (
        .clk(clk),
        .reset(reset),
        .echo(echo),
        .btn_start(btn_start),
        .trigger(trigger),
        .fnd_comm(fnd_comm),
        .fnd_font(fnd_font),
        .led(led)
    );
    
    // 내부 신호에 대한 모니터링을 위한 연결
    // 이 부분은 실제 시뮬레이션에서 필요한 모듈의 내부 신호를 모니터링하기 위한 것입니다.
    assign monitor_msec = DUT.w_msec;
    assign monitor_dp_done = DUT.w_dp_done;
    assign monitor_start_dp = DUT.w_start_dp;
    assign monitor_tick_10msec = DUT.w_tick_10msec;
    
    // 클럭 생성
    always begin
        #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 테스트 시나리오
    initial begin
        // 파형 덤프 설정 (시뮬레이터에 따라 다를 수 있음)
        $dumpfile("ultrasonic_test.vcd");
        $dumpvars(0, tb_ultrasonic_distance_meter);
        
        // 초기화
        clk = 0;
        reset = 0;
        echo = 0;
        btn_start = 0;
        
        // 리셋 적용
        #100;
        reset = 1;
        #100;
        reset = 0;
        #100;
        
        // 측정 시작 버튼 누름
        btn_start = 1;
        #20;
        btn_start = 0;
        
        // 트리거 신호 생성 확인 (10us 후에 생성되어야 함)
        #2000;
        
        // 에코 신호 시뮬레이션 (실제 거리 측정 시나리오)
        // 트리거 이후 일정 시간 후 에코 시작
        #ECHO_DELAY;
        echo = 1;
        
        // 17cm에 해당하는 에코 지속 시간
        #ECHO_WIDTH;
        echo = 0;
        
        // 결과 확인 시간
        #10000;
        
        // 두 번째 측정 시나리오 (다른 거리)
        btn_start = 1;
        #20;
        btn_start = 0;
        
        // 트리거 이후 대기
        #2000;
        
        // 에코 시뮬레이션 (다른 거리)
        #ECHO_DELAY;
        echo = 1;
        
        // 20cm에 해당하는 에코 지속 시간
        #(5800*20); // 20cm
        echo = 0;
        
        // 최종 결과 확인
        #100000;
        
        // 시뮬레이션 종료
        $display("Test completed");
        $finish;
    end
    
    // 모니터링 로직
    initial begin
        $monitor("Time=%t, Reset=%b, Btn=%b, Trigger=%b, Echo=%b, LED=%b, MSec=%d",
                 $time, reset, btn_start, trigger, echo, led, monitor_msec);
    end
    
    // 각 주요 신호 변화 감지 및 출력
    always @(posedge trigger) begin
        $display("Time=%t: Trigger signal activated", $time);
    end
    
    always @(negedge trigger) begin
        $display("Time=%t: Trigger signal deactivated", $time);
    end
    
    always @(posedge echo) begin
        $display("Time=%t: Echo signal started", $time);
    end
    
    always @(negedge echo) begin
        $display("Time=%t: Echo signal ended - Distance calculation should start", $time);
    end
    
    always @(monitor_msec) begin
        $display("Time=%t: Distance updated to %d cm", $time, monitor_msec);
    end
    
    always @(monitor_tick_10msec) begin
        if(monitor_tick_10msec)
            $display("Time=%t: 10ms tick generated", $time);
    end
    
endmodule