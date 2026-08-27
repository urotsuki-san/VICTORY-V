`timescale 1ns/1ps

module vv32_core_tb;
  import vv32_pkg::*;

  logic clk;
  logic rst_n;
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
  logic irq;
  logic halted;
  logic [31:0] debug_pc;
  logic [31:0] debug_cause;
  logic [31:0] debug_error;
  logic debug_region_active;
  logic debug_root_locked;

  logic [31:0] imem [0:255];
  logic [31:0] dmem [0:16383];
  integer i;
  integer cycles;

  vv32_core #(
    .RESET_PC(32'h0000_0000),
    .DATA_MEMORY_BYTES(65536),
    .STORE_BUFFER_DEPTH(8)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .imem_req_o(imem_req),
    .imem_addr_o(imem_addr),
    .imem_rdata_i(imem_rdata),
    .imem_ready_i(imem_ready),
    .dmem_req_o(dmem_req),
    .dmem_we_o(dmem_we),
    .dmem_addr_o(dmem_addr),
    .dmem_wdata_o(dmem_wdata),
    .dmem_wstrb_o(dmem_wstrb),
    .dmem_rdata_i(dmem_rdata),
    .dmem_ready_i(dmem_ready),
    .irq_i(irq),
    .halted_o(halted),
    .debug_pc_o(debug_pc),
    .debug_cause_o(debug_cause),
    .debug_error_o(debug_error),
    .debug_region_active_o(debug_region_active),
    .debug_root_locked_o(debug_root_locked)
  );

  always #5 clk = ~clk;

  always_comb begin
    imem_ready = 1'b1;
    imem_rdata = imem[imem_addr[9:2]];
    dmem_ready = 1'b1;
    dmem_rdata = dmem[dmem_addr[15:2]];
  end

  always_ff @(posedge clk) begin
    if (dmem_req && dmem_we && dmem_ready) begin
      if (dmem_wstrb[0]) dmem[dmem_addr[15:2]][7:0]   <= dmem_wdata[7:0];
      if (dmem_wstrb[1]) dmem[dmem_addr[15:2]][15:8]  <= dmem_wdata[15:8];
      if (dmem_wstrb[2]) dmem[dmem_addr[15:2]][23:16] <= dmem_wdata[23:16];
      if (dmem_wstrb[3]) dmem[dmem_addr[15:2]][31:24] <= dmem_wdata[31:24];
    end
  end

  function automatic [31:0] enc_none(input [5:0] op);
    enc_none = {op, 26'd0};
  endfunction

  function automatic [31:0] enc_r(
    input [5:0] op,
    input [4:0] rd,
    input [4:0] rs1,
    input [4:0] rs2,
    input [10:0] aux
  );
    enc_r = {op, rd, rs1, rs2, aux};
  endfunction

  function automatic [31:0] enc_i(
    input [5:0] op,
    input [4:0] rd,
    input [4:0] rs1,
    input [15:0] imm
  );
    enc_i = {op, rd, rs1, imm};
  endfunction

  function automatic [31:0] enc_b(
    input [5:0] op,
    input [4:0] rs1,
    input integer off_words
  );
    enc_b = {op, rs1, off_words[20:0]};
  endfunction

  function automatic [31:0] enc_vtry(
    input [4:0] stores,
    input [7:0] budget,
    input integer off_words
  );
    enc_vtry = {OP_VTRY, stores, budget, off_words[12:0]};
  endfunction

  function automatic integer rel(input integer from_index, input integer to_index);
    rel = to_index - (from_index + 1);
  endfunction

  localparam integer I_FAIL1 = 22;
  localparam integer I_FAIL2 = 17;
  localparam integer I_BAD   = 23;

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    irq = 1'b0;
    for (i = 0; i < 256; i = i + 1) imem[i] = enc_none(OP_NOP);
    for (i = 0; i < 16384; i = i + 1) dmem[i] = 32'd0;

    // Create c10=[0x100,0x104), lock root creation, then commit value 2.
    imem[0]  = enc_i(OP_MOVI, 5'd1, 5'd0, 16'h0100);
    imem[1]  = enc_i(OP_MOVI, 5'd2, 5'd0, 16'h0004);
    imem[2]  = enc_r(OP_CROOT, 5'd10, 5'd1, 5'd2, 11'h003);
    imem[3]  = enc_none(OP_VLOCK);
    imem[4]  = enc_vtry(5'd1, 8'd16, rel(4, I_FAIL1));
    imem[5]  = enc_i(OP_MOVI, 5'd3, 5'd0, 16'h0002);
    imem[6]  = enc_i(OP_CSTW, 5'd3, 5'd10, 16'h0000);
    imem[7]  = enc_i(OP_MOVI, 5'd4, 5'd0, 16'h0001);
    imem[8]  = enc_i(OP_VCHK, 5'd0, 5'd4, 16'h1111);
    imem[9]  = enc_none(OP_VIC);

    // Buffer 99, fail the check, and prove rollback preserves 2.
    imem[10] = enc_vtry(5'd1, 8'd16, rel(10, I_FAIL2));
    imem[11] = enc_i(OP_MOVI, 5'd5, 5'd0, 16'h0063);
    imem[12] = enc_i(OP_CSTW, 5'd5, 5'd10, 16'h0000);
    imem[13] = enc_i(OP_MOVI, 5'd6, 5'd0, 16'h0000);
    imem[14] = enc_i(OP_VCHK, 5'd0, 5'd6, 16'h2222);
    imem[15] = enc_none(OP_VIC);
    imem[16] = enc_none(OP_HALT);

    imem[17] = enc_i(OP_CLDW, 5'd7, 5'd10, 16'h0000);
    imem[18] = enc_i(OP_MOVI, 5'd8, 5'd0, 16'h0002);
    imem[19] = enc_r(OP_CMPEQ, 5'd9, 5'd7, 5'd8, 11'd0);
    imem[20] = enc_b(OP_BRZ, 5'd9, rel(20, I_BAD));
    imem[21] = enc_r(OP_VERR, 5'd11, 5'd0, 5'd0, 11'd0);
    imem[22] = enc_none(OP_HALT);
    imem[23] = enc_i(OP_TRAP, 5'd0, 5'd0, 16'hdead);

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    cycles = 0;
    while (!halted && cycles < 500) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (!halted) begin
      $fatal(1, "timeout: core did not halt");
    end
    if (dmem[16'h0100 >> 2] !== 32'd2) begin
      $fatal(1, "rollback failure: memory=0x%08x", dmem[16'h0100 >> 2]);
    end
    if (debug_error !== 32'h0000_2222) begin
      $fatal(1, "unexpected Victory error: 0x%08x", debug_error);
    end
    if (dut.regs_q[5] !== 32'd0 || dut.regs_q[6] !== 32'd0) begin
      $fatal(1, "aborted VV32 register writes were not restored");
    end
    if (dut.regs_q[7] !== 32'd2 || dut.regs_q[9] !== 32'd1 || dut.regs_q[11] !== 32'h0000_2222) begin
      $fatal(1, "architectural register check failed");
    end
    if (!debug_root_locked || debug_region_active) begin
      $fatal(1, "security state check failed");
    end

    $display("VICTORY-V RTL PASS: commit, rollback, capability access, and VLOCK");
    $finish;
  end
endmodule
