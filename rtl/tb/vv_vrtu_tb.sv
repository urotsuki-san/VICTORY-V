`timescale 1ns/1ps

module vv_vrtu_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic cfg_we;
  logic [1:0] cfg_index;
  logic cfg_valid;
  logic [63:0] cfg_vbase;
  logic [63:0] cfg_vtop;
  logic [63:0] cfg_pbase;
  logic [4:0] cfg_perm;
  logic cfg_require_parent;
  logic cfg_parent_valid;
  logic [63:0] cfg_parent_base;
  logic [63:0] cfg_parent_top;
  logic [4:0] cfg_parent_perm;
  logic cfg_lock;
  logic locked;
  logic cfg_error;
  logic [15:0] cfg_cause;

  logic imem_req;
  logic [63:0] imem_vaddr;
  logic imem_user;
  logic [63:0] imem_paddr;
  logic imem_fault;
  logic [15:0] imem_cause;

  logic dmem_req;
  logic dmem_write;
  logic dmem_user;
  logic dmem_region;
  logic [3:0] dmem_size;
  logic [63:0] dmem_vaddr;
  logic [63:0] dmem_paddr;
  logic dmem_fault;
  logic [15:0] dmem_cause;
  logic dmem_device;

  always #5 clk = ~clk;

  vv_vrtu #(
    .ENTRY_COUNT (4),
    .PHYS_ADDR_BITS (17),
    .LOCK_ON_RESET (1'b0)
  ) dut (
    .clk_i (clk),
    .rst_ni (rst_n),
    .cfg_we_i (cfg_we),
    .cfg_index_i (cfg_index),
    .cfg_valid_i (cfg_valid),
    .cfg_vbase_i (cfg_vbase),
    .cfg_vtop_i (cfg_vtop),
    .cfg_pbase_i (cfg_pbase),
    .cfg_perm_i (cfg_perm),
    .cfg_require_parent_i (cfg_require_parent),
    .cfg_parent_valid_i (cfg_parent_valid),
    .cfg_parent_base_i (cfg_parent_base),
    .cfg_parent_top_i (cfg_parent_top),
    .cfg_parent_perm_i (cfg_parent_perm),
    .cfg_lock_i (cfg_lock),
    .locked_o (locked),
    .cfg_error_o (cfg_error),
    .cfg_cause_o (cfg_cause),
    .imem_req_i (imem_req),
    .imem_vaddr_i (imem_vaddr),
    .imem_user_i (imem_user),
    .imem_paddr_o (imem_paddr),
    .imem_fault_o (imem_fault),
    .imem_cause_o (imem_cause),
    .dmem_req_i (dmem_req),
    .dmem_write_i (dmem_write),
    .dmem_user_i (dmem_user),
    .dmem_region_i (dmem_region),
    .dmem_size_i (dmem_size),
    .dmem_vaddr_i (dmem_vaddr),
    .dmem_paddr_o (dmem_paddr),
    .dmem_fault_o (dmem_fault),
    .dmem_cause_o (dmem_cause),
    .dmem_device_o (dmem_device)
  );

  task automatic configure(
    input logic [1:0] index,
    input logic valid,
    input logic [63:0] vbase,
    input logic [63:0] vtop,
    input logic [63:0] pbase,
    input logic [4:0] perm
  );
    begin
      cfg_index = index;
      cfg_valid = valid;
      cfg_vbase = vbase;
      cfg_vtop = vtop;
      cfg_pbase = pbase;
      cfg_perm = perm;
      cfg_we = 1'b1;
      @(posedge clk);
      #1;
      cfg_we = 1'b0;
    end
  endtask

  initial begin
    cfg_we = 1'b0;
    cfg_index = 2'd0;
    cfg_valid = 1'b0;
    cfg_vbase = 64'd0;
    cfg_vtop = 64'd0;
    cfg_pbase = 64'd0;
    cfg_perm = 5'd0;
    cfg_require_parent = 1'b0;
    cfg_parent_valid = 1'b0;
    cfg_parent_base = 64'd0;
    cfg_parent_top = 64'd0;
    cfg_parent_perm = 5'd0;
    cfg_lock = 1'b0;
    imem_req = 1'b0;
    imem_vaddr = 64'd0;
    imem_user = 1'b0;
    dmem_req = 1'b0;
    dmem_write = 1'b0;
    dmem_user = 1'b0;
    dmem_region = 1'b0;
    dmem_size = 4'd8;
    dmem_vaddr = 64'd0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    #1;

    imem_req = 1'b1;
    imem_user = 1'b1;
    imem_vaddr = 64'h40;
    #1;
    if (imem_fault || imem_paddr !== 64'h40)
      $fatal(1, "RAM execute translation failed");
    imem_req = 1'b0;

    dmem_req = 1'b1;
    dmem_write = 1'b1;
    dmem_vaddr = 64'h0001_0020;
    #1;
    if (dmem_fault || dmem_paddr !== 64'h0001_0020 || !dmem_device)
      $fatal(1, "MMIO supervisor translation failed");
    dmem_region = 1'b1;
    #1;
    if (!dmem_fault || dmem_cause !== 16'd27)
      $fatal(1, "region device access was not rejected");
    dmem_region = 1'b0;
    dmem_req = 1'b0;

    imem_req = 1'b1;
    imem_user = 1'b0;
    imem_vaddr = 64'h0001_0000;
    #1;
    if (!imem_fault || imem_cause !== 16'd21)
      $fatal(1, "MMIO execute permission was not rejected");
    imem_req = 1'b0;

    dmem_req = 1'b1;
    dmem_write = 1'b0;
    dmem_vaddr = 64'h0002_0000;
    #1;
    if (!dmem_fault || dmem_cause !== 16'd20)
      $fatal(1, "unmapped address did not report VRTU miss");
    dmem_req = 1'b0;

    // R/W/U data mapping. Runtime descriptors are W^X.
    configure(2'd2, 1'b1, 64'h0002_0000, 64'h0002_1000,
              64'h0000_8000, 5'b0_1011);
    if (cfg_error)
      $fatal(1, "valid descriptor was rejected: cause=%0d", cfg_cause);

    dmem_req = 1'b1;
    dmem_user = 1'b1;
    dmem_size = 4'd1;
    dmem_vaddr = 64'h0002_0fff;
    #1;
    if (dmem_fault || dmem_paddr !== 64'h0000_8fff)
      $fatal(1, "byte-sized boundary translation failed");
    dmem_size = 4'd2;
    #1;
    if (!dmem_fault || dmem_cause !== 16'd20)
      $fatal(1, "logical access size was not checked");
    dmem_req = 1'b0;
    dmem_user = 1'b0;
    dmem_size = 4'd8;

    configure(2'd3, 1'b1, 64'h0002_0800, 64'h0002_1800,
              64'h0000_a000, 5'b0_0001);
    if (!cfg_error || cfg_cause !== 16'd22)
      $fatal(1, "overlap was not rejected at configuration");

    configure(2'd3, 1'b1, 64'h0003_0000, 64'h0003_0800,
              64'h0000_a000, 5'b0_0111);
    if (!cfg_error || cfg_cause !== 16'd31)
      $fatal(1, "W^X descriptor was accepted");

    cfg_require_parent = 1'b1;
    cfg_parent_valid = 1'b1;
    cfg_parent_base = 64'h0000_a000;
    cfg_parent_top = 64'h0000_b000;
    cfg_parent_perm = 5'b0_0011;
    configure(2'd3, 1'b1, 64'h0003_0000, 64'h0003_0800,
              64'h0000_a000, 5'b0_0001);
    if (cfg_error)
      $fatal(1, "attenuated parent mapping was rejected");
    configure(2'd3, 1'b1, 64'h0003_0000, 64'h0003_0800,
              64'h0000_a000, 5'b0_0100);
    if (!cfg_error || cfg_cause !== 16'd31)
      $fatal(1, "parent capability permission was amplified");
    cfg_require_parent = 1'b0;

    cfg_lock = 1'b1;
    @(posedge clk);
    #1;
    cfg_lock = 1'b0;
    if (!locked)
      $fatal(1, "VRTU lock did not close");

    configure(2'd0, 1'b0, 64'd0, 64'd0, 64'd0, 5'd0);
    imem_req = 1'b1;
    imem_vaddr = 64'h40;
    #1;
    if (imem_fault)
      $fatal(1, "locked descriptor bank was modified");

    $display("PASS vv_vrtu_tb");
    $finish;
  end
endmodule
