`timescale 1ns/1ps

module vv_dual_bringup_tb;
  logic clk;
  logic rst_n;
  logic uart_tx;
  logic [7:0] led;
  logic [63:0] mailbox32;
  logic [63:0] mailbox64;
  logic halted32;
  logic halted64;
  logic [31:0] cause32;
  logic [63:0] cause64;
  integer cycles;

  vv_dual_bringup #(
    .CLK_HZ (1_000_000),
    .UART_BAUD (100_000),
    .VV64_RELEASE_CYCLES (10_000)
  ) dut (
    .clk_i (clk),
    .rst_ni (rst_n),
    .uart_rx_i (1'b1),
    .uart_tx_o (uart_tx),
    .led_o (led),
    .debug_mailbox32_o (mailbox32),
    .debug_mailbox64_o (mailbox64),
    .debug_halted32_o (halted32),
    .debug_halted64_o (halted64),
    .debug_cause32_o (cause32),
    .debug_cause64_o (cause64)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cycles = 0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    while (!(halted32 && halted64) && cycles < 50_000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (!(halted32 && halted64))
      $fatal(1, "dual-core bring-up timed out: h32=%b h64=%b", halted32, halted64);
    if (mailbox32[7:0] !== 8'h32)
      $fatal(1, "VV32 mailbox mismatch: %h", mailbox32);
    if (mailbox64[7:0] !== 8'h64)
      $fatal(1, "VV64 mailbox mismatch: %h", mailbox64);
    if ((cause32 !== 32'd0) || (cause64 !== 64'd0))
      $fatal(1, "unexpected cause: vv32=%h vv64=%h", cause32, cause64);
    if (led[5:0] !== 6'b11_1111)
      $fatal(1, "status LEDs did not settle: %b", led);

    $display("DUAL BRING-UP PASS cycles=%0d led=%b", cycles, led);
    $finish;
  end
endmodule
