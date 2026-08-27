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

  vv_cluster_bringup #(
    .CLK_HZ (50_000_000),
    .UART_BAUD (115_200)
  ) u_soc (
    .clk_i (clk),
    .rst_ni (rst_ni),
    .uart_rx_i (uart_rx),
    .uart_tx_o (uart_tx),
    .led_o (status_led),
    .debug_mailbox32_o (),
    .debug_mailbox_p_o (),
    .debug_mailbox_e_o (),
    .debug_halted32_o (),
    .debug_halted_p_o (),
    .debug_halted_e_o (),
    .debug_cause32_o (),
    .debug_cause_p_o (),
    .debug_cause_e_o (),
    .debug_p_released_o (),
    .debug_e_released_o ()
  );

  // V13 is active low. All three CPU boot milestones must pass.
  assign led_V13 = ~(status_led[0] && status_led[1] && status_led[2]);
endmodule
