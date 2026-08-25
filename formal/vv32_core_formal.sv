`timescale 1ns/1ps

module vv32_core_formal;
  import vv32_pkg::*;

  (* gclk *) logic clk;
  logic rst_n;
  (* anyseq *) logic [31:0] imem_rdata;
  (* anyseq *) logic [31:0] dmem_rdata;
  (* anyseq *) logic irq;

  logic imem_req;
  logic [31:0] imem_addr;
  logic dmem_req;
  logic dmem_we;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0] dmem_wstrb;
  logic halted;
  logic [31:0] debug_pc;
  logic [31:0] debug_cause;
  logic [31:0] debug_error;
  logic debug_region_active;
  logic debug_root_locked;

  vv32_core #(
    .DATA_MEMORY_BYTES(65536),
    .STORE_BUFFER_DEPTH(8)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .imem_req_o(imem_req),
    .imem_addr_o(imem_addr),
    .imem_rdata_i(imem_rdata),
    .imem_ready_i(1'b1),
    .dmem_req_o(dmem_req),
    .dmem_we_o(dmem_we),
    .dmem_addr_o(dmem_addr),
    .dmem_wdata_o(dmem_wdata),
    .dmem_wstrb_o(dmem_wstrb),
    .dmem_rdata_i(dmem_rdata),
    .dmem_ready_i(1'b1),
    .irq_i(irq),
    .halted_o(halted),
    .debug_pc_o(debug_pc),
    .debug_cause_o(debug_cause),
    .debug_error_o(debug_error),
    .debug_region_active_o(debug_region_active),
    .debug_root_locked_o(debug_root_locked)
  );

  initial rst_n = 1'b0;
  always_ff @(posedge clk) begin
    rst_n <= 1'b1;

    if (rst_n) begin
      assert(dut.regs_q[0] == 32'd0);
      assert(!dut.cap_valid_q[0]);
      assert(!dut.secret_q[0]);
      assert(debug_pc[1:0] == 2'b00);

      // A buffered region must not write external memory before commit.
      if (debug_region_active && dmem_we) begin
        assert(dut.state_q == ST_COMMIT);
      end

      // Root lock is monotonic until reset.
      if (!$initstate && $past(debug_root_locked)) begin
        assert(debug_root_locked);
      end

      // The implementation can never hold more stores than physical entries.
      assert(dut.sb_count_q <= 8);
    end
  end

  always_ff @(posedge clk) begin
    cover(rst_n && debug_region_active);
    cover(rst_n && dut.state_q == ST_COMMIT);
    cover(rst_n && halted);
  end
endmodule
