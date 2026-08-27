`timescale 1ns/1ps

module vv32_contract_tb;
  import vv32_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic imem_req;
  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;
  logic imem_ready;
  logic dmem_req;
  logic dmem_we;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [3:0] dmem_wstrb;
  logic [31:0] dmem_rdata;
  logic dmem_ready;
  logic halted;
  logic [31:0] debug_pc;
  logic [31:0] debug_cause;
  logic [31:0] debug_error;
  logic debug_region;
  logic debug_root_locked;

  logic [31:0] rom [0:63];
  logic [31:0] ram [0:63];
  integer cycles;
  integer max_store_entries;
  logic [31:0] admitted_release_cycle;
  logic saw_region;
  logic saw_publication;

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

  vv32_core #(
    .DATA_MEMORY_BYTES (256),
    .STORE_BUFFER_DEPTH (2),
    .MAX_CONTRACT_CAP_ALLOCS (2)
  ) dut (
    .clk_i (clk),
    .rst_ni (rst_n),
    .imem_req_o (imem_req),
    .imem_addr_o (imem_addr),
    .imem_rdata_i (imem_rdata),
    .imem_ready_i (imem_ready),
    .dmem_req_o (dmem_req),
    .dmem_we_o (dmem_we),
    .dmem_addr_o (dmem_addr),
    .dmem_wdata_o (dmem_wdata),
    .dmem_wstrb_o (dmem_wstrb),
    .dmem_rdata_i (dmem_rdata),
    .dmem_ready_i (dmem_ready),
    .irq_i (1'b0),
    .halted_o (halted),
    .debug_pc_o (debug_pc),
    .debug_cause_o (debug_cause),
    .debug_error_o (debug_error),
    .debug_region_active_o (debug_region),
    .debug_root_locked_o (debug_root_locked)
  );

  always #5 clk = ~clk;
  assign imem_ready = imem_req;
  assign imem_rdata = rom[imem_addr[7:2]];
  assign dmem_ready = dmem_req;
  assign dmem_rdata = ram[dmem_addr[7:2]];

  always_ff @(posedge clk) begin
    if (debug_region && !saw_region) begin
      saw_region <= 1'b1;
      admitted_release_cycle <= dut.region_release_cycle_q;
    end
    if (dut.sb_count_q > max_store_entries)
      max_store_entries <= dut.sb_count_q;
    if (dmem_req && dmem_we && dmem_ready) begin
      saw_publication <= 1'b1;
      if (dut.cycle_q < admitted_release_cycle)
        $fatal(1, "store published before fixed release: now=%0d release=%0d",
               dut.cycle_q, admitted_release_cycle);
      if (dmem_wstrb[0]) ram[dmem_addr[7:2]][7:0] <= dmem_wdata[7:0];
      if (dmem_wstrb[1]) ram[dmem_addr[7:2]][15:8] <= dmem_wdata[15:8];
      if (dmem_wstrb[2]) ram[dmem_addr[7:2]][23:16] <= dmem_wdata[23:16];
      if (dmem_wstrb[3]) ram[dmem_addr[7:2]][31:24] <= dmem_wdata[31:24];
    end
  end

  initial begin
    for (integer index = 0; index < 64; index = index + 1) begin
      rom[index] = {OP_NOP, 26'd0};
      ram[index] = 32'd0;
    end
    cycles = 0;
    max_store_entries = 0;
    admitted_release_cycle = 32'd0;
    saw_region = 1'b0;
    saw_publication = 1'b0;

    // ContractSpec(1 store granule, 32 insns, 6 register writes,
    // 1 capability allocation, fixed release +40 cycles) = 0x5084c401.
    rom[0]  = enc_i(OP_MOVI, 5'd1, 5'd0, 16'h0080);
    rom[1]  = enc_i(OP_MOVI, 5'd2, 5'd0, 16'h0008);
    rom[2]  = enc_r(OP_CROOT, 5'd10, 5'd1, 5'd2, 11'h003);
    rom[3]  = enc_i(OP_LUI, 5'd3, 5'd0, 16'h5084);
    rom[4]  = enc_i(OP_ORI, 5'd3, 5'd3, 16'hc401);
    rom[5]  = enc_r(OP_VPREP, 5'd12, 5'd10, 5'd3, 11'd0);
    rom[6]  = enc_r(OP_MOV, 5'd13, 5'd12, 5'd0, 11'd0);
    rom[7]  = enc_b(OP_VTRYC, 5'd13, rel(7, 17));
    rom[8]  = enc_i(OP_MOVI, 5'd5, 5'd0, 16'h0012);
    rom[9]  = enc_i(OP_CSTB, 5'd5, 5'd10, 16'd0);
    rom[10] = enc_i(OP_MOVI, 5'd5, 5'd0, 16'h0034);
    rom[11] = enc_i(OP_CSTB, 5'd5, 5'd10, 16'd1);
    rom[12] = enc_i(OP_MOVI, 5'd6, 5'd0, 16'd4);
    rom[13] = enc_r(OP_CBOUNDS, 5'd11, 5'd10, 5'd6, 11'd0);
    rom[14] = {OP_VIC, 26'd0};
    rom[15] = {OP_HALT, 26'd0};
    rom[17] = {OP_HALT, 26'd0};

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    while (!halted && cycles < 800) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (!halted)
      $fatal(1, "contract test timed out");
    if (!saw_region || !saw_publication)
      $fatal(1, "contract region/publication was not observed");
    if (max_store_entries != 1)
      $fatal(1, "same granule was not merged: max=%0d", max_store_entries);
    if (ram[0] !== 32'd0 || ram[16'h0080 >> 2][15:0] !== 16'h3412)
      $fatal(1, "merged store payload mismatch: %h", ram[16'h0080 >> 2]);
    if (!dut.cap_valid_q[11] || dut.cap_base_q[11] !== 32'h0000_0080 ||
        dut.cap_top_q[11] !== 32'h0000_0084)
      $fatal(1, "contract capability allocation did not commit");
    if (dut.contract_valid_q || debug_region || debug_error != 32'd0 || debug_cause != 32'd0)
      $fatal(1, "contract did not close cleanly");

    $display("VV32 CONTRACT PASS");
    $finish;
  end
endmodule
