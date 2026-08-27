`timescale 1ns/1ps

module vv64_contract_tb;
  import vv64_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic imem_req;
  logic [63:0] imem_addr;
  logic [31:0] imem_rdata;
  logic imem_ready;
  logic dmem_req;
  logic dmem_we;
  logic dmem_probe;
  logic [3:0] dmem_size;
  logic [63:0] dmem_addr;
  logic [63:0] dmem_wdata;
  logic [7:0] dmem_wstrb;
  logic [63:0] dmem_rdata;
  logic dmem_ready;
  logic dmem_fault;
  logic [15:0] dmem_fault_cause;
  logic halted;
  logic [63:0] debug_pc;
  logic [63:0] debug_cause;
  logic [63:0] debug_error;
  logic debug_region;
  logic debug_root_locked;
  logic [15:0] debug_cap_alloc;

  logic [31:0] rom [0:63];
  logic [63:0] ram [0:31];
  integer cycles;
  integer probe_count;
  integer publication_count;

  function automatic logic [31:0] enc_r(
    input logic [5:0] op,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [4:0] rs2,
    input logic [10:0] aux
  );
    enc_r = {op, rd, rs1, rs2, aux};
  endfunction

  function automatic logic [31:0] enc_i(
    input logic [5:0] op,
    input logic [4:0] rd,
    input logic [4:0] rs1,
    input logic [15:0] imm
  );
    enc_i = {op, rd, rs1, imm};
  endfunction

  function automatic logic [31:0] enc_b(
    input logic [5:0] op,
    input logic [4:0] rs1,
    input integer off_words
  );
    enc_b = {op, rs1, off_words[20:0]};
  endfunction

  function automatic integer rel(input integer from_index, input integer to_index);
    rel = to_index - (from_index + 1);
  endfunction

  vv64_core #(
    .DATA_MEMORY_BYTES (64'd256),
    .STORE_BUFFER_DEPTH (4),
    .CAP_DIRECTORY_ENTRIES (8),
    .CAP_GENERATION_BITS (32),
    .MAX_CONTRACT_CAP_ALLOCS (2)
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
    .dmem_probe_o (dmem_probe),
    .dmem_size_o (dmem_size),
    .dmem_addr_o (dmem_addr),
    .dmem_wdata_o (dmem_wdata),
    .dmem_wstrb_o (dmem_wstrb),
    .dmem_rdata_i (dmem_rdata),
    .dmem_ready_i (dmem_ready),
    .dmem_fault_i (dmem_fault),
    .dmem_fault_cause_i (dmem_fault_cause),
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
  assign imem_rdata = rom[imem_addr[7:2]];
  assign dmem_ready = dmem_req;
  assign dmem_rdata = ram[dmem_addr[7:3]];
  assign dmem_fault = dmem_probe && (dmem_addr == 64'd8);
  assign dmem_fault_cause = dmem_fault ? 16'd21 : 16'd0;

  always_ff @(posedge clk) begin
    if (dmem_req && dmem_probe)
      probe_count <= probe_count + 1;
    if (dmem_req && !dmem_probe && dmem_we && dmem_ready) begin
      publication_count <= publication_count + 1;
      for (integer byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
        if (dmem_wstrb[byte_index])
          ram[dmem_addr[7:3]][byte_index*8 +: 8] <= dmem_wdata[byte_index*8 +: 8];
      end
    end
  end

  initial begin
    for (integer index = 0; index < 64; index = index + 1)
      rom[index] = {OP_NOP, 26'd0};
    for (integer index = 0; index < 32; index = index + 1)
      ram[index] = 64'd0;
    cycles = 0;
    probe_count = 0;
    publication_count = 0;

    // ContractSpec(2 granules, 32 insns, 8 register writes,
    // 1 capability allocation) = 0x00050402.
    rom[0]  = enc_i(OP_MOVI, 5'd1, 5'd0, 16'd0);
    rom[1]  = enc_i(OP_MOVI, 5'd2, 5'd0, 16'd128);
    rom[2]  = enc_r(OP_CROOT, 5'd10, 5'd1, 5'd2, 11'h003);
    rom[3]  = enc_i(OP_LUI, 5'd3, 5'd0, 16'h0005);
    rom[4]  = enc_i(OP_ORI, 5'd3, 5'd3, 16'h0402);
    rom[5]  = enc_r(OP_VPREP, 5'd12, 5'd10, 5'd3, 11'd0);
    rom[6]  = enc_b(OP_VTRYC, 5'd12, rel(6, 15));
    rom[7]  = enc_i(OP_MOVI, 5'd6, 5'd0, 16'd64);
    rom[8]  = enc_r(OP_CBOUNDS, 5'd11, 5'd10, 5'd6, 11'd0);
    rom[9]  = enc_i(OP_MOVI, 5'd5, 5'd0, 16'd1);
    rom[10] = enc_i(OP_CSTW, 5'd5, 5'd10, 16'd0);
    rom[11] = enc_i(OP_MOVI, 5'd5, 5'd0, 16'd2);
    rom[12] = enc_i(OP_CSTW, 5'd5, 5'd10, 16'd8);
    rom[13] = {OP_VIC, 26'd0};
    rom[14] = {OP_HALT, 26'd0};
    rom[15] = enc_r(OP_VERR, 5'd14, 5'd0, 5'd0, 11'd0);
    rom[16] = {OP_HALT, 26'd0};

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    while (!halted && cycles < 800) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (!halted)
      $fatal(1, "VV64 contract test timed out");
    if (probe_count != 2)
      $fatal(1, "preflight did not inspect both entries: %0d", probe_count);
    if (publication_count != 0 || ram[0] != 64'd0 || ram[1] != 64'd0)
      $fatal(1, "preflight fault allowed partial publication");
    if (debug_error != 64'd21 || dut.regs_q[14] != 64'd21)
      $fatal(1, "preflight fault was not reported: %0d", debug_error);
    if (dut.cap_valid_q[11] || debug_cap_alloc != 16'd1)
      $fatal(1, "Capability Directory or allocator did not roll back");
    if (dut.contract_valid_q || debug_region || debug_cause != 64'd0)
      $fatal(1, "contract did not abort cleanly");
    if (dmem_size != 4'd0 && dmem_size != 4'd8)
      $fatal(1, "unexpected memory size output");

    $display("VV64 CONTRACT PREFLIGHT PASS");
    $finish;
  end
endmodule
