module vv_uart_tx #(
  parameter integer CLK_HZ = 50_000_000,
  parameter integer BAUD = 115_200
) (
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       valid_i,
  input  logic [7:0] data_i,
  output logic       ready_o,
  output logic       tx_o,
  output logic       busy_o
);
  localparam integer CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;
  localparam integer COUNT_BITS = $clog2(CLKS_PER_BIT);

  logic [9:0] shift_q;
  logic [3:0] bit_index_q;
  logic [COUNT_BITS-1:0] clock_count_q;
  logic busy_q;

  assign ready_o = !busy_q;
  assign busy_o = busy_q;
  assign tx_o = busy_q ? shift_q[0] : 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      shift_q <= 10'h3ff;
      bit_index_q <= 4'd0;
      clock_count_q <= '0;
      busy_q <= 1'b0;
    end else if (!busy_q) begin
      if (valid_i) begin
        shift_q <= {1'b1, data_i, 1'b0};
        bit_index_q <= 4'd0;
        clock_count_q <= CLKS_PER_BIT - 1;
        busy_q <= 1'b1;
      end
    end else if (clock_count_q != 0) begin
      clock_count_q <= clock_count_q - 1'b1;
    end else if (bit_index_q == 4'd9) begin
      shift_q <= 10'h3ff;
      busy_q <= 1'b0;
    end else begin
      shift_q <= {1'b1, shift_q[9:1]};
      bit_index_q <= bit_index_q + 1'b1;
      clock_count_q <= CLKS_PER_BIT - 1;
    end
  end
endmodule
