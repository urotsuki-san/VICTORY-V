module vv_sram #(
  parameter integer DATA_WIDTH = 32,
  parameter integer ADDR_WIDTH = 14
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,
  input  logic                  req_i,
  input  logic                  we_i,
  input  logic [63:0]           addr_i,
  input  logic [DATA_WIDTH-1:0] wdata_i,
  input  logic [DATA_WIDTH/8-1:0] wstrb_i,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic                  ready_o
);
  localparam integer BYTES_PER_WORD = DATA_WIDTH / 8;
  localparam integer BYTE_LSB = $clog2(BYTES_PER_WORD);
  localparam integer WORDS = 1 << (ADDR_WIDTH - BYTE_LSB);

  logic [DATA_WIDTH-1:0] memory_q [0:WORDS-1];
  logic pending_q;
  integer byte_index;
  wire [ADDR_WIDTH-BYTE_LSB-1:0] word_index_w = addr_i[ADDR_WIDTH-1:BYTE_LSB];

  assign ready_o = pending_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q <= 1'b0;
      rdata_o <= '0;
    end else if (pending_q) begin
      pending_q <= 1'b0;
    end else if (req_i) begin
      pending_q <= 1'b1;
      if (we_i) begin
        for (byte_index = 0; byte_index < BYTES_PER_WORD; byte_index = byte_index + 1) begin
          if (wstrb_i[byte_index])
            memory_q[word_index_w][byte_index*8 +: 8] <= wdata_i[byte_index*8 +: 8];
        end
      end else begin
        rdata_o <= memory_q[word_index_w];
      end
    end
  end
endmodule
