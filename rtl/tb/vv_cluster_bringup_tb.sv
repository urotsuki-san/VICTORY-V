`timescale 1ns/1ps

module vv_cluster_bringup_tb;
  logic clk;
  logic rst_n;
  logic uart_tx;
  logic [7:0] led;
  logic [63:0] mailbox32;
  logic [63:0] mailbox_p;
  logic [63:0] mailbox_e;
  logic halted32;
  logic halted_p;
  logic halted_e;
  logic [31:0] cause32;
  logic [63:0] cause_p;
  logic [63:0] cause_e;
  logic p_released;
  logic e_released;
  integer cycles;

  vv_cluster_bringup #(
    .CLK_HZ (1_000_000),
    .UART_BAUD (100_000),
    .P_RELEASE_CYCLES (10_000),
    .E_RELEASE_CYCLES (10_000)
  ) dut (
    .clk_i (clk),
    .rst_ni (rst_n),
    .uart_rx_i (1'b1),
    .uart_tx_o (uart_tx),
    .led_o (led),
    .debug_mailbox32_o (mailbox32),
    .debug_mailbox_p_o (mailbox_p),
    .debug_mailbox_e_o (mailbox_e),
    .debug_halted32_o (halted32),
    .debug_halted_p_o (halted_p),
    .debug_halted_e_o (halted_e),
    .debug_cause32_o (cause32),
    .debug_cause_p_o (cause_p),
    .debug_cause_e_o (cause_e),
    .debug_p_released_o (p_released),
    .debug_e_released_o (e_released)
  );

  always #5 clk = ~clk;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cycles = 0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    while (!(halted32 && halted_p && halted_e) && cycles < 80_000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (!(halted32 && halted_p && halted_e))
      $fatal(1, "cluster timed out: vv32=%b p=%b e=%b", halted32, halted_p, halted_e);
    if (!p_released || !e_released)
      $fatal(1, "release chain failed: p=%b e=%b", p_released, e_released);
    if (mailbox32[7:0] !== 8'h32)
      $fatal(1, "VV32 mailbox mismatch: %h", mailbox32);
    if (mailbox_p[7:0] !== 8'h50)
      $fatal(1, "P mailbox mismatch: %h", mailbox_p);
    if (mailbox_e[7:0] !== 8'h45)
      $fatal(1, "E mailbox mismatch: %h", mailbox_e);
    if ((cause32 !== 32'd0) || (cause_p !== 64'd0) || (cause_e !== 64'd0))
      $fatal(1, "unexpected cause: vv32=%h p=%h e=%h", cause32, cause_p, cause_e);
    if (led[6:0] !== 7'b0_111111)
      $fatal(1, "status LEDs did not settle: %b", led);

    $display("1P1E+VV32 BRING-UP PASS cycles=%0d led=%b", cycles, led);
    $finish;
  end
endmodule
