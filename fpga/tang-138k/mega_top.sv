module top (
  input  logic clk,
  input  logic key1_F4,
  input  logic uart_rx,
  output logic uart_tx,
  output logic led_V13
);
  logic rst_ni;
  logic [7:0] status_led;

  vv_reset_sync u_reset (
    .clk_i (clk),
    .arst_ni (~key1_F4),
    .rst_ni (rst_ni)
  );

  vv_dual_bringup #(
    .CLK_HZ (50_000_000),
    .UART_BAUD (115_200)
  ) u_soc (
    .clk_i (clk),
    .rst_ni (rst_ni),
    .uart_rx_i (uart_rx),
    .uart_tx_o (uart_tx),
    .led_o (status_led),
    .debug_mailbox32_o (),
    .debug_mailbox64_o (),
    .debug_halted32_o (),
    .debug_halted64_o (),
    .debug_cause32_o (),
    .debug_cause64_o ()
  );

  // The onboard V13 LED is active low. It stays on after both cores report.
  assign led_V13 = ~(status_led[0] && status_led[1]);
endmodule
