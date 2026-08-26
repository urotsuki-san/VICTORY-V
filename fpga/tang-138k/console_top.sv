module top (
  input  logic       clk50,
  input  logic       s0,
  input  logic       UART_RXD,
  output logic       UART_TXD,
  output logic [7:0] led
);
  logic rst_ni;

  vv_reset_sync u_reset (
    .clk_i (clk50),
    .arst_ni (s0),
    .rst_ni (rst_ni)
  );

  vv_cluster_bringup #(
    .CLK_HZ (50_000_000),
    .UART_BAUD (115_200)
  ) u_soc (
    .clk_i (clk50),
    .rst_ni (rst_ni),
    .uart_rx_i (UART_RXD),
    .uart_tx_o (UART_TXD),
    .led_o (led),
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
endmodule
