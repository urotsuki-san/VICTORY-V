`timescale 1ns/1ps

module vv32_region_irq_tb;
  import vv32_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic irq = 1'b0;
  logic imem_req;
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic imem_ready;
  logic dmem_req;
  logic dmem_we;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0] dmem_wstrb;
  logic [31:0] dmem_rdata = 32'd0;
  logic dmem_ready;
  logic halted;
  logic [31:0] debug_pc;
  logic [31:0] debug_cause;
  logic [31:0] debug_error;
  logic debug_region;
  logic debug_root_locked;
  logic [31:0] rom [0:31];
  integer cycles;

  function automatic logic [31:0] enc_i(
    input logic [5:0] op,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [15:0] imm
  );
    enc_i = {op, rd, rs1, imm};
  endfunction

  function automatic logic [31:0] enc_vtry(
    input logic [4:0] stores,
    input logic [7:0] budget,
    input integer off_words
  );
    enc_vtry = {OP_VTRY, stores, budget, off_words[12:0]};
  endfunction

  always #5 clk = ~clk;
  assign imem_ready = imem_req;
  assign imem_rdata = rom[imem_addr[6:2]];
  assign dmem_ready = dmem_req;

  vv32_core #(.DATA_MEMORY_BYTES(256), .STORE_BUFFER_DEPTH(2)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_o(imem_req), .imem_addr_o(imem_addr),
    .imem_rdata_i(imem_rdata), .imem_ready_i(imem_ready),
    .dmem_req_o(dmem_req), .dmem_we_o(dmem_we), .dmem_addr_o(dmem_addr),
    .dmem_wdata_o(dmem_wdata), .dmem_wstrb_o(dmem_wstrb),
    .dmem_rdata_i(dmem_rdata), .dmem_ready_i(dmem_ready),
    .irq_i(irq), .halted_o(halted), .debug_pc_o(debug_pc),
    .debug_cause_o(debug_cause), .debug_error_o(debug_error),
    .debug_region_active_o(debug_region), .debug_root_locked_o(debug_root_locked)
  );

  initial begin
    for (integer i = 0; i < 32; i = i + 1)
      rom[i] = {OP_NOP, 26'd0};
    rom[0] = enc_i(OP_MOVI, 5'd1, 5'd0, 16'h0024); // handler @ 0x24
    rom[1] = enc_i(OP_CSRW, 5'd0, 5'd1, CSR_VTVEC);
    rom[2] = {OP_EI, 26'd0};
    rom[3] = enc_i(OP_MOVI, 5'd5, 5'd0, 16'd7);
    rom[4] = enc_vtry(5'd1, 8'd32, 2);             // fail @ 0x1c
    rom[5] = enc_i(OP_MOVI, 5'd5, 5'd0, 16'd99);
    rom[6] = {OP_NOP, 26'd0};
    rom[7] = {OP_HALT, 26'd0};
    rom[8] = {OP_NOP, 26'd0};
    rom[9] = {OP_HALT, 26'd0};

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    cycles = 0;
    while (!(debug_region && dut.regs_q[5] == 32'd99) && cycles < 200) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (cycles >= 200)
      $fatal(1, "region setup timed out");
    irq = 1'b1;
    @(posedge clk);
    irq = 1'b0;
    cycles = 0;
    while (!halted && cycles < 200) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    if (!halted)
      $fatal(1, "interrupt handler did not halt");
    if (dut.regs_q[5] !== 32'd7)
      $fatal(1, "interrupt rollback failed: r5=%h", dut.regs_q[5]);
    if (dut.vepc_q !== 32'h0000_001c)
      $fatal(1, "interrupt resume PC mismatch: %h", dut.vepc_q);
    if (debug_cause !== 32'd13 || debug_error !== 32'd19 || debug_region)
      $fatal(1, "interrupt witness mismatch");
    $display("VV32 REGION IRQ PASS");
    $finish;
  end
endmodule
