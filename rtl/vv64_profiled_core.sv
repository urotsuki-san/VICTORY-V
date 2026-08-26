`timescale 1ns/1ps

module vv64_profiled_core #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_0000_0000,
  parameter logic [63:0] DATA_MEMORY_BYTES = 64'd131072,
  parameter bit PERFORMANCE_PROFILE = 1'b1
) (
  input  logic        clk_i,
  input  logic        rst_ni,

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

  assign performance_profile_o = PERFORMANCE_PROFILE;

  vv64_core #(
    .RESET_PC (RESET_PC),
    .DATA_MEMORY_BYTES (DATA_MEMORY_BYTES),
    .STORE_BUFFER_DEPTH (PROFILE_STORE_BUFFER_DEPTH),
    .CAP_DIRECTORY_ENTRIES (PROFILE_CAP_DIRECTORY_ENTRIES)
  ) u_core (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .imem_req_o (imem_req_o),
    .imem_addr_o (imem_addr_o),
    .imem_rdata_i (imem_rdata_i),
    .imem_ready_i (imem_ready_i),
    .dmem_req_o (dmem_req_o),
    .dmem_we_o (dmem_we_o),
    .dmem_addr_o (dmem_addr_o),
    .dmem_wdata_o (dmem_wdata_o),
    .dmem_wstrb_o (dmem_wstrb_o),
    .dmem_rdata_i (dmem_rdata_i),
    .dmem_ready_i (dmem_ready_i),
    .irq_i (irq_i),
    .halted_o (halted_o),
    .debug_pc_o (debug_pc_o),
    .debug_cause_o (debug_cause_o),
    .debug_error_o (debug_error_o),
    .debug_region_active_o (debug_region_active_o),
    .debug_root_locked_o (debug_root_locked_o),
    .debug_cap_alloc_o (debug_cap_alloc_o)
  );
endmodule
