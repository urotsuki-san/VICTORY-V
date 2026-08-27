`timescale 1ns/1ps

module vv64_core_tb;
  import vv64_pkg::*;

  logic clk;
  logic rst_n;
  logic imem_req;
  logic [63:0] imem_addr;
  logic [31:0] imem_rdata;
  logic imem_ready;
  logic dmem_req;
  logic dmem_we;
  logic [63:0] dmem_addr;
  logic [63:0] dmem_wdata;
  logic [7:0] dmem_wstrb;
  logic dmem_probe;
  logic [3:0] dmem_size;
  logic [63:0] dmem_rdata;
  logic dmem_ready;
  logic halted;
  logic [63:0] debug_pc;
  logic [63:0] debug_cause;
  logic [63:0] debug_error;
  logic debug_region;
  logic debug_root_locked;
  logic [15:0] debug_cap_alloc;

  logic [31:0] instruction_memory [0:63];
  logic [63:0] memory [0:31];
  integer cycle_count;
  integer byte_index;

  function automatic logic [31:0] enc_r(
    input logic [5:0] opcode,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2,
    input logic [10:0] aux
  );
    enc_r = {opcode, rd, rs1, rs2, aux};
  endfunction

  function automatic logic [31:0] enc_i(
    input logic [5:0] opcode,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [15:0] immediate
  );
    enc_i = {opcode, rd, rs1, immediate};
  endfunction

  function automatic logic [31:0] enc_b(
    input logic [5:0] opcode,
    input logic [4:0] rs1,
    input integer word_offset
  );
    enc_b = {opcode, rs1, word_offset[20:0]};
  endfunction

  function automatic logic [31:0] enc_vtry(
    input logic [4:0] stores,
    input logic [7:0] budget,
    input integer word_offset
  );
    enc_vtry = {OP_VTRY, stores, budget, word_offset[12:0]};
  endfunction

  vv64_core #(
    .DATA_MEMORY_BYTES (64'd256),
    .STORE_BUFFER_DEPTH (4),
    .CAP_DIRECTORY_ENTRIES (8)
  ) dut (
    .clk_i (clk),
    .rst_ni (rst_n),
    .imem_req_o (imem_req),
    .imem_addr_o (imem_addr),
    .imem_rdata_i (imem_rdata),
    .imem_ready_i (imem_ready),
    .imem_fault_i (1'b0),
    .imem_fault_cause_i (16'd0),
    .dmem_req_o (dmem_req),
    .dmem_we_o (dmem_we),
    .dmem_addr_o (dmem_addr),
    .dmem_wdata_o (dmem_wdata),
    .dmem_wstrb_o (dmem_wstrb),
    .dmem_probe_o (dmem_probe),
    .dmem_size_o (dmem_size),
    .dmem_rdata_i (dmem_rdata),
    .dmem_ready_i (dmem_ready),
    .dmem_fault_i (1'b0),
    .dmem_fault_cause_i (16'd0),
    .irq_i (1'b0),
    .halted_o (halted),
    .debug_pc_o (debug_pc),
    .debug_cause_o (debug_cause),
    .debug_error_o (debug_error),
    .debug_region_active_o (debug_region),
    .debug_root_locked_o (debug_root_locked),
    .debug_cap_alloc_o (debug_cap_alloc)
  );

  always #5 clk = ~clk;

  assign imem_ready = imem_req;
  assign imem_rdata = instruction_memory[imem_addr[7:2]];
  assign dmem_ready = dmem_req;
  assign dmem_rdata = memory[dmem_addr[7:3]];

  always_ff @(posedge clk) begin
    if (dmem_req && !dmem_probe && dmem_we && dmem_ready) begin
      for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
        if (dmem_wstrb[byte_index])
          memory[dmem_addr[7:3]][byte_index*8 +: 8] <= dmem_wdata[byte_index*8 +: 8];
      end
    end
  end

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cycle_count = 0;
    for (integer index = 0; index < 64; index = index + 1)
      instruction_memory[index] = {OP_NOP, 26'd0};
    for (integer index = 0; index < 32; index = index + 1)
      memory[index] = 64'd0;

    instruction_memory[0]  = enc_i(OP_MOVI, 5'd1, 5'd0, 16'd0);
    instruction_memory[1]  = enc_i(OP_MOVI, 5'd2, 5'd0, 16'd128);
    instruction_memory[2]  = enc_r(OP_CROOT, 5'd10, 5'd1, 5'd2, 11'd3);
    instruction_memory[3]  = enc_i(OP_MOVI, 5'd3, 5'd0, 16'd1);
    instruction_memory[4]  = enc_i(OP_CSTW, 5'd3, 5'd10, 16'd0);
    instruction_memory[5]  = enc_i(OP_CLDW, 5'd4, 5'd10, 16'd0);
    instruction_memory[6]  = enc_r(OP_CMPEQ, 5'd5, 5'd3, 5'd4, 11'd0);
    instruction_memory[7]  = enc_vtry(5'd1, 8'd16, 10);
    instruction_memory[8]  = enc_i(OP_MOVI, 5'd3, 5'd0, 16'd2);
    instruction_memory[9]  = enc_i(OP_CSTW, 5'd3, 5'd10, 16'd0);
    instruction_memory[10] = enc_i(OP_VCHK, 5'd0, 5'd5, 16'h0055);
    instruction_memory[11] = {OP_VIC, 26'd0};
    instruction_memory[12] = enc_vtry(5'd1, 8'd16, 5);
    instruction_memory[13] = enc_i(OP_MOVI, 5'd3, 5'd0, 16'd3);
    instruction_memory[14] = enc_i(OP_CSTW, 5'd3, 5'd10, 16'd0);
    instruction_memory[15] = enc_i(OP_MOVI, 5'd5, 5'd0, 16'd0);
    instruction_memory[16] = enc_i(OP_VCHK, 5'd0, 5'd5, 16'h1234);
    instruction_memory[17] = {OP_HALT, 26'd0};
    instruction_memory[18] = enc_i(OP_CLDW, 5'd4, 5'd10, 16'd0);
    instruction_memory[19] = enc_i(OP_MOVI, 5'd7, 5'd0, 16'd2);
    instruction_memory[20] = enc_r(OP_CMPEQ, 5'd8, 5'd4, 5'd7, 11'd0);
    instruction_memory[21] = enc_b(OP_BRZ, 5'd8, 3);
    instruction_memory[22] = {OP_VLOCK, 26'd0};
    instruction_memory[23] = {OP_HALT, 26'd0};
    instruction_memory[24] = {OP_NOP, 26'd0};
    instruction_memory[25] = enc_i(OP_TRAP, 5'd0, 5'd0, 16'hdead);

    repeat (5) @(posedge clk);
    rst_n = 1'b1;

    while (!halted && cycle_count < 2000) begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
    end

    if (!halted)
      $fatal(1, "VV64 core did not halt");
    if (memory[0][31:0] !== 32'd2)
      $fatal(1, "rollback failed: memory=%h", memory[0]);
    if (dut.regs_q[3] !== 64'd2 || dut.regs_q[5] !== 64'd1)
      $fatal(1, "aborted VV64 register writes were not restored");
    if (debug_cause !== 64'd0)
      $fatal(1, "unexpected trap cause: %h", debug_cause);
    if (debug_error !== 64'h0000_0000_0000_1234)
      $fatal(1, "unexpected Victory error: %h", debug_error);
    if (!debug_root_locked)
      $fatal(1, "VLOCK was not observed");
    if (debug_region)
      $fatal(1, "region remained active after abort");
    if (debug_cap_alloc == 0)
      $fatal(1, "capability directory was not used");

    if (dmem_size > 4'd8)
      $fatal(1, "invalid logical memory size: %0d", dmem_size);

    $display("VV64 CORE PASS cycles=%0d pc=%h", cycle_count, debug_pc);
    $finish;
  end
endmodule
