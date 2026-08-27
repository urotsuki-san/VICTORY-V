`timescale 1ns/1ps

module vv64_profiled_core #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_0000_0000,
  parameter logic [63:0] DATA_MEMORY_BYTES = 64'd131072,
  parameter bit PERFORMANCE_PROFILE = 1'b1
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        user_mode_i,

  output logic        imem_req_o,
  output logic [63:0] imem_addr_o,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_ready_i,

  output logic        dmem_req_o,
  output logic        dmem_we_o,
  output logic [63:0] dmem_addr_o,
  output logic [63:0] dmem_wdata_o,
  output logic [7:0]  dmem_wstrb_o,
  input  logic [63:0] dmem_rdata_i,
  input  logic        dmem_ready_i,

  input  logic        irq_i,

  output logic        halted_o,
  output logic [63:0] debug_pc_o,
  output logic [63:0] debug_cause_o,
  output logic [63:0] debug_error_o,
  output logic        debug_region_active_o,
  output logic        debug_root_locked_o,
  output logic [15:0] debug_cap_alloc_o,
  output logic        performance_profile_o
);
  localparam integer PROFILE_STORE_BUFFER_DEPTH = PERFORMANCE_PROFILE ? 8 : 2;
  localparam integer PROFILE_CAP_DIRECTORY_ENTRIES = PERFORMANCE_PROFILE ? 32 : 8;
  localparam integer PROFILE_CONTRACT_CAP_ALLOCS = PERFORMANCE_PROFILE ? 8 : 2;
  localparam integer PROFILE_VRTU_ENTRIES = PERFORMANCE_PROFILE ? 4 : 2;
  localparam integer PROFILE_VRTU_INDEX_BITS =
      (PROFILE_VRTU_ENTRIES <= 1) ? 1 : $clog2(PROFILE_VRTU_ENTRIES);

  logic        core_imem_req;
  logic [63:0] core_imem_addr;
  logic        core_imem_ready;
  logic        core_imem_fault;
  logic [15:0] core_imem_fault_cause;

  logic        core_dmem_req;
  logic        core_dmem_we;
  logic        core_dmem_probe;
  logic [3:0]  core_dmem_size;
  logic [63:0] core_dmem_addr;
  logic [63:0] core_dmem_wdata;
  logic [7:0]  core_dmem_wstrb;
  logic        core_dmem_ready;
  logic        core_dmem_fault;
  logic [15:0] core_dmem_fault_cause;

  logic        vrtu_locked;
  logic        vrtu_cfg_error;
  logic [15:0] vrtu_cfg_cause;
  logic        vrtu_dmem_device;
  logic [63:0] vrtu_imem_addr;
  logic [63:0] vrtu_dmem_addr;

  assign performance_profile_o = PERFORMANCE_PROFILE;

  assign imem_req_o = core_imem_req && !core_imem_fault;
  assign imem_addr_o = vrtu_imem_addr;
  assign core_imem_ready = core_imem_fault || imem_ready_i;

  // Probe cycles exercise the same VRTU path as publication but never reach
  // the external bus. Once all entries pass, the core enters the no-fault
  // commit sequence.
  assign dmem_req_o = core_dmem_req && !core_dmem_fault && !core_dmem_probe;
  assign dmem_we_o = core_dmem_we;
  assign dmem_addr_o = vrtu_dmem_addr;
  assign dmem_wdata_o = core_dmem_wdata;
  assign dmem_wstrb_o = core_dmem_wstrb;
  assign core_dmem_ready = core_dmem_fault || core_dmem_probe || dmem_ready_i;

  vv_vrtu #(
    .ENTRY_COUNT (PROFILE_VRTU_ENTRIES),
    .INDEX_BITS (PROFILE_VRTU_INDEX_BITS),
    .PHYS_ADDR_BITS (17),
    .LOCK_ON_RESET (1'b1),
    .RAM_TOP (64'h0000_0000_0001_0000),
    .ROOT_TOP (64'h0000_0000_0002_0000)
  ) u_vrtu (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .cfg_we_i (1'b0),
    .cfg_index_i ({PROFILE_VRTU_INDEX_BITS{1'b0}}),
    .cfg_valid_i (1'b0),
    .cfg_vbase_i (64'd0),
    .cfg_vtop_i (64'd0),
    .cfg_pbase_i (64'd0),
    .cfg_perm_i (5'd0),
    .cfg_require_parent_i (1'b0),
    .cfg_parent_valid_i (1'b0),
    .cfg_parent_base_i (64'd0),
    .cfg_parent_top_i (64'd0),
    .cfg_parent_perm_i (5'd0),
    .cfg_lock_i (1'b0),
    .locked_o (vrtu_locked),
    .cfg_error_o (vrtu_cfg_error),
    .cfg_cause_o (vrtu_cfg_cause),
    .imem_req_i (core_imem_req),
    .imem_vaddr_i (core_imem_addr),
    .imem_user_i (user_mode_i),
    .imem_paddr_o (vrtu_imem_addr),
    .imem_fault_o (core_imem_fault),
    .imem_cause_o (core_imem_fault_cause),
    .dmem_req_i (core_dmem_req),
    .dmem_write_i (core_dmem_we),
    .dmem_user_i (user_mode_i),
    .dmem_region_i (debug_region_active_o),
    .dmem_size_i (core_dmem_size),
    .dmem_vaddr_i (core_dmem_addr),
    .dmem_paddr_o (vrtu_dmem_addr),
    .dmem_fault_o (core_dmem_fault),
    .dmem_cause_o (core_dmem_fault_cause),
    .dmem_device_o (vrtu_dmem_device)
  );

  vv64_core #(
    .RESET_PC (RESET_PC),
    .DATA_MEMORY_BYTES (DATA_MEMORY_BYTES),
    .STORE_BUFFER_DEPTH (PROFILE_STORE_BUFFER_DEPTH),
    .CAP_DIRECTORY_ENTRIES (PROFILE_CAP_DIRECTORY_ENTRIES),
    .MAX_CONTRACT_CAP_ALLOCS (PROFILE_CONTRACT_CAP_ALLOCS),
    .CAP_GENERATION_BITS (32)
  ) u_core (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .imem_req_o (core_imem_req),
    .imem_addr_o (core_imem_addr),
    .imem_rdata_i (imem_rdata_i),
    .imem_ready_i (core_imem_ready),
    .imem_fault_i (core_imem_fault),
    .imem_fault_cause_i (core_imem_fault_cause),
    .dmem_req_o (core_dmem_req),
    .dmem_we_o (core_dmem_we),
    .dmem_probe_o (core_dmem_probe),
    .dmem_size_o (core_dmem_size),
    .dmem_addr_o (core_dmem_addr),
    .dmem_wdata_o (core_dmem_wdata),
    .dmem_wstrb_o (core_dmem_wstrb),
    .dmem_rdata_i (dmem_rdata_i),
    .dmem_ready_i (core_dmem_ready),
    .dmem_fault_i (core_dmem_fault),
    .dmem_fault_cause_i (core_dmem_fault_cause),
    .irq_i (irq_i),
    .halted_o (halted_o),
    .debug_pc_o (debug_pc_o),
    .debug_cause_o (debug_cause_o),
    .debug_error_o (debug_error_o),
    .debug_region_active_o (debug_region_active_o),
    .debug_root_locked_o (debug_root_locked_o),
    .debug_cap_alloc_o (debug_cap_alloc_o)
  );

  wire unused_vrtu_locked = vrtu_locked;
  wire unused_vrtu_cfg_error = vrtu_cfg_error;
  wire [15:0] unused_vrtu_cfg_cause = vrtu_cfg_cause;
  wire unused_vrtu_dmem_device = vrtu_dmem_device;
endmodule
