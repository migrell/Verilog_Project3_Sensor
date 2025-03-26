`timescale 1ns / 1ps

module tb_top_dut();
   reg clk;
   reg rst;
   reg btn_start;
   
   reg dht_sensor_data;
   reg io_oe;
   
   wire [4:0] led;
   wire fsm_error;
   wire dut_io;
   
   // 양방향 I/O 설정 (호스트 → 센서, 센서 → 호스트)
   assign dut_io = (io_oe) ? dht_sensor_data : 1'bz;
   
   // DUT 인스턴스화 - 모듈명과 포트명 수정
   top_dut dut (
     .clk(clk),
     .rst(rst),
     .btn_start(btn_start),
     .led(led),
     .fsm_error(fsm_error),
     .dut_io(dut_io)
   );
   
   // 클럭 생성 (10ns 주기, 100MHz)
   always #5 clk = ~clk;
   
   initial begin
     // 초기화
     clk = 0;
     rst = 1;
     io_oe = 0;  // 초기에는 센서가 데이터를 출력하지 않음
     btn_start = 0;
     
     // 리셋 해제
     #100;
     rst = 0;
     
     // 버튼 입력으로, 시작 신호 생성 (18ms 시작 신호 트리거)
     #100;
     btn_start = 1;
     
     #100;
     btn_start = 0;
     
     // 호스트 모듈의 I/O 신호가 HIGH가 될 때까지 대기
     wait(dut_io);
     
     // 입력 모드로 전환 (센서 응답 시뮬레이션)
     #30000;  // 30μs 딜레이
     io_oe = 1;  // 센서 출력 활성화
     
     // 센서 응답: LOW 신호 (80μs)
     dht_sensor_data = 1'b0;
     #80000;  // 80μs
     
     // 센서 응답: HIGH 신호 (80μs)
     dht_sensor_data = 1'b1;
     #80000;  // 80μs
     
     // 데이터 비트 시뮬레이션 (예시: 첫 번째 비트 '0')
     // 모든 비트는 50μs LOW 시작 후 26-70μs HIGH(0/1)
     // LOW 신호 (50μs)
     dht_sensor_data = 1'b0;
     #50000;  // 50μs
     
     // HIGH 신호 (26-28μs: '0', 70μs: '1')
     dht_sensor_data = 1'b1;
     #28000;  // 28μs ('0' 비트)
     
     // 다시 LOW로 돌아감
     dht_sensor_data = 1'b0;
     #50000;  // 다음 비트 시작
     
     // 시뮬레이션 종료
     $stop;
   end
endmodule