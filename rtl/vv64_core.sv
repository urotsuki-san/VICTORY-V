`timescale 1ns/1ps

module vv64_core #(
  parameter logic [63:0] RESET_PC = 64'h0000_0000_0000_0000,
  parameter logic [63:0] DATA_MEMORY_BYTES = 64'd131072,
  parameter integer STORE_BUFFER_DEPTH = 8,
  parameter integer CAP_DIRECTORY_ENTRIES = 32,
  parameter integer CAP_GENERATION_BITS = 32,
  parameter integer MAX_CONTRACT_CAP_ALLOCS = 8
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  output logic        imem_req_o,
  output logic [63:0] imem_addr_o,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_ready_i,
  input  logic        imem_fault_i,
  input  logic [15:0] imem_fault_cause_i,

  output logic        dmem_req_o,
  output logic        dmem_we_o,
  output logic [63:0] dmem_addr_o,
  output logic [63:0] dmem_wdata_o,
  output logic [7:0]  dmem_wstrb_o,
  output logic        dmem_probe_o,
  output logic [3:0]  dmem_size_o,
  input  logic [63:0] dmem_rdata_i,
  input  logic        dmem_ready_i,
  input  logic        dmem_fault_i,
  input  logic [15:0] dmem_fault_cause_i,

  input  logic        irq_i,

  output logic        halted_o,
  output logic [63:0] debug_pc_o,
  output logic [63:0] debug_cause_o,
  output logic [63:0] debug_error_o,
  output logic        debug_region_active_o,
  output logic        debug_root_locked_o,
  output logic [15:0] debug_cap_alloc_o
);
  import vv64_pkg::*;

  localparam integer CAP_INDEX_BITS = $clog2(CAP_DIRECTORY_ENTRIES);

  vv64_state_t state_q;
  logic [63:0] pc_q;
  logic [31:0] instruction_q;
  logic [63:0] instruction_pc_q;

  logic [63:0] regs_q [0:31];
  logic        cap_valid_q [0:31];
  logic [CAP_INDEX_BITS-1:0] cap_index_q [0:31];
  logic [CAP_GENERATION_BITS-1:0] cap_generation_q [0:31];
  logic        secret_q [0:31];
  logic [31:0] contract_token_tag_q [0:31];

  logic [63:0] region_regs_q [0:31];
  logic        region_cap_valid_q [0:31];
  logic [CAP_INDEX_BITS-1:0] region_cap_index_q [0:31];
  logic [CAP_GENERATION_BITS-1:0] region_cap_generation_q [0:31];
  logic        region_secret_q [0:31];
  logic [31:0] region_contract_token_tag_q [0:31];

  logic        dir_valid_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [63:0] dir_base_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [63:0] dir_top_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [4:0]  dir_perm_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [CAP_GENERATION_BITS-1:0] dir_generation_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [CAP_INDEX_BITS-1:0] cap_alloc_q;

  logic        region_dir_valid_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [63:0] region_dir_base_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [63:0] region_dir_top_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [4:0]  region_dir_perm_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [CAP_GENERATION_BITS-1:0] region_dir_generation_q [0:CAP_DIRECTORY_ENTRIES-1];
  logic [CAP_INDEX_BITS-1:0] region_cap_alloc_q;

  logic        interrupt_enable_q;
  logic        root_locked_q;
  logic [63:0] vtvec_q;
  logic [63:0] vepc_q;
  logic [63:0] vcause_q;
  logic [63:0] vbadaddr_q;
  logic [63:0] verror_q;
  logic [63:0] cycle_q;
  logic [63:0] instret_q;

  logic        region_active_q;
  logic [63:0] region_fail_pc_q;
  logic [4:0]  region_store_quota_q;
  logic [7:0]  region_budget_q;
  logic [7:0]  region_used_q;
  logic [4:0]  region_register_quota_q;
  logic [4:0]  region_register_count_q;
  logic [31:0] region_register_dirty_q;
  logic [4:0]  region_cap_quota_q;
  logic [4:0]  region_cap_used_q;
  logic        region_arena_valid_q;
  logic [63:0] region_arena_base_q;
  logic [63:0] region_arena_top_q;
  logic        region_fixed_release_q;
  logic        region_secret_mode_q;
  logic [63:0] region_release_cycle_q;

  logic        contract_valid_q;
  logic [31:0] contract_generation_q;
  logic [4:0]  contract_store_quota_q;
  logic [7:0]  contract_budget_q;
  logic [4:0]  contract_register_quota_q;
  logic [4:0]  contract_cap_quota_q;
  logic        contract_fixed_release_q;
  logic        contract_secret_mode_q;
  logic [6:0]  contract_release_delta_q;
  logic [63:0] contract_arena_base_q;
  logic [63:0] contract_arena_top_q;
  logic [4:0]  contract_arena_perm_q;

  logic        release_abort_q;
  logic        release_interrupt_q;
  logic [63:0] release_error_q;
  logic [63:0] release_cycle_q;

  logic [63:0] sb_addr_q [0:STORE_BUFFER_DEPTH-1];
  logic [63:0] sb_data_q [0:STORE_BUFFER_DEPTH-1];
  logic [7:0]  sb_strb_q [0:STORE_BUFFER_DEPTH-1];
  logic [5:0]  sb_count_q;
  logic [5:0]  commit_index_q;
  logic [5:0]  preflight_index_q;

  logic [4:0]  mem_rd_q;
  logic [63:0] mem_addr_q;
  logic [1:0]  mem_size_q;
  logic        mem_signed_q;
  logic        mem_secret_q;
  logic [63:0] mem_wdata_q;
  logic [7:0]  mem_wstrb_q;

  wire [5:0] opcode_w = instruction_q[31:26];
  wire [4:0] rd_w = instruction_q[25:21];
  wire [4:0] rs1_w = instruction_q[20:16];
  wire [4:0] rs2_w = instruction_q[15:11];
  wire [10:0] aux_w = instruction_q[10:0];
  wire [15:0] imm16_w = instruction_q[15:0];
  wire [4:0] branch_rs1_w = instruction_q[25:21];
  wire signed [20:0] off21_w = instruction_q[20:0];
  wire [4:0] vtry_stores_w = instruction_q[25:21];
  wire [7:0] vtry_budget_w = instruction_q[20:13];
  wire signed [12:0] vtry_off13_w = instruction_q[12:0];
  wire [4:0] xmem_function_w = instruction_q[15:11];
  wire signed [10:0] xmem_imm11_w = instruction_q[10:0];

  integer i;
  logic [64:0] temp_sum;
  logic [64:0] temp_end_sum;
  logic [63:0] temp_value;
  logic [63:0] temp_target;
  logic [63:0] temp_dword;
  logic [63:0] temp_cursor;
  logic [63:0] temp_address;
  logic [63:0] temp_end;
  logic [1:0]  temp_size;
  logic [7:0]  temp_strb;
  logic [63:0] temp_store_data;
  logic        temp_is_load;
  logic        temp_is_store;
  logic        temp_signed;
  logic        temp_address_overflow;
  logic        temp_merge_found;
  integer      temp_merge_index;
  integer      temp_byte_index;
  logic [31:0] temp_contract_spec;
  logic [31:0] temp_contract_generation;

  function automatic logic [63:0] sext16(input logic [15:0] value);
    sext16 = {{48{value[15]}}, value};
  endfunction

  function automatic logic [63:0] sext11(input logic [10:0] value);
    sext11 = {{53{value[10]}}, value};
  endfunction

  function automatic logic [63:0] sext8(input logic [7:0] value);
    sext8 = {{56{value[7]}}, value};
  endfunction

  function automatic logic [63:0] sext_half(input logic [15:0] value);
    sext_half = {{48{value[15]}}, value};
  endfunction

  function automatic logic [63:0] signext13_words(input logic signed [12:0] value);
    signext13_words = {{49{value[12]}}, value, 2'b00};
  endfunction

  function automatic logic [63:0] signext21_words(input logic signed [20:0] value);
    signext21_words = {{41{value[20]}}, value, 2'b00};
  endfunction

  function automatic logic cap_live(input logic [4:0] register_index);
    logic [CAP_INDEX_BITS-1:0] slot;
    begin
      slot = cap_index_q[register_index];
      cap_live = cap_valid_q[register_index] &&
                 dir_valid_q[slot] &&
                 (cap_generation_q[register_index] == dir_generation_q[slot]);
    end
  endfunction

  function automatic logic [63:0] cap_base(input logic [4:0] register_index);
    cap_base = dir_base_q[cap_index_q[register_index]];
  endfunction

  function automatic logic [63:0] cap_top(input logic [4:0] register_index);
    cap_top = dir_top_q[cap_index_q[register_index]];
  endfunction

  function automatic logic [4:0] cap_permissions(input logic [4:0] register_index);
    cap_permissions = dir_perm_q[cap_index_q[register_index]];
  endfunction


  function automatic logic contract_token_live(input logic [4:0] register_index);
    contract_token_live = contract_valid_q &&
                          (contract_token_tag_q[register_index] != 32'd0) &&
                          (contract_token_tag_q[register_index] == contract_generation_q);
  endfunction

  function automatic logic opcode_writes_rd(
    input logic [5:0] opcode,
    input logic [4:0] xmem_function
  );
    begin
      case (opcode)
        OP_MOV, OP_MOVI, OP_LUI, OP_ADD, OP_ADDI, OP_SUB, OP_MUL,
        OP_AND, OP_ANDI, OP_OR, OP_ORI, OP_XOR, OP_XORI,
        OP_SHL, OP_SHR, OP_SAR, OP_CMPEQ, OP_CMPLT, OP_CMPULT,
        OP_JAL, OP_JALR, OP_CSRR,
        OP_CROOT, OP_CBOUNDS, OP_CPERM, OP_CINC,
        OP_CGETTAG, OP_CGETPERM,
        OP_CLDB, OP_CLDBU, OP_CLDH, OP_CLDHU, OP_CLDW,
        OP_VDECLASS, OP_VERR, OP_VPREP:
          opcode_writes_rd = 1'b1;
        OP_XMEM:
          opcode_writes_rd = (xmem_function == XMEM_CLDD);
        default:
          opcode_writes_rd = 1'b0;
      endcase
    end
  endfunction

  function automatic logic [7:0] store_strobe(
    input logic [1:0] size,
    input logic [2:0] address_low
  );
    begin
      case (size)
        2'd0: store_strobe = 8'b0000_0001 << address_low;
        2'd1: store_strobe = 8'b0000_0011 << ({address_low[2:1], 1'b0});
        2'd2: store_strobe = address_low[2] ? 8'b1111_0000 : 8'b0000_1111;
        default: store_strobe = 8'b1111_1111;
      endcase
    end
  endfunction

  function automatic logic [63:0] store_data(
    input logic [63:0] value,
    input logic [1:0] size,
    input logic [2:0] address_low
  );
    begin
      case (size)
        2'd0: store_data = (value & 64'h0000_0000_0000_00ff) << (address_low * 8);
        2'd1: store_data = (value & 64'h0000_0000_0000_ffff) << (address_low[2:1] * 16);
        2'd2: store_data = (value & 64'h0000_0000_ffff_ffff) << (address_low[2] * 32);
        default: store_data = value;
      endcase
    end
  endfunction

  function automatic logic [63:0] forwarded_dword(
    input logic [63:0] memory_dword,
    input logic [63:0] aligned_address
  );
    logic [63:0] result;
    integer index;
    integer byte_index;
    begin
      result = memory_dword;
      for (index = 0; index < STORE_BUFFER_DEPTH; index = index + 1) begin
        if ((index < sb_count_q) && (sb_addr_q[index] == aligned_address)) begin
          for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1) begin
            if (sb_strb_q[index][byte_index])
              result[byte_index*8 +: 8] = sb_data_q[index][byte_index*8 +: 8];
          end
        end
      end
      forwarded_dword = result;
    end
  endfunction

  function automatic logic [63:0] csr_read(input logic [15:0] csr);
    begin
      case (csr)
        CSR_VSTATUS:       csr_read = {61'd0, region_active_q, root_locked_q, interrupt_enable_q};
        CSR_VTVEC:         csr_read = vtvec_q;
        CSR_VEPC:          csr_read = vepc_q;
        CSR_VCAUSE:        csr_read = vcause_q;
        CSR_VBADADDR:      csr_read = vbadaddr_q;
        CSR_VCYCLE:        csr_read = cycle_q;
        CSR_VINSTRET:      csr_read = instret_q;
        CSR_VERROR:        csr_read = verror_q;
        CSR_VREGION_COUNT: csr_read = {58'd0, sb_count_q};
        CSR_VREGION_LIMIT: csr_read = {56'd0, region_budget_q};
        CSR_VCAP_ALLOC:    csr_read = {{(64-CAP_INDEX_BITS){1'b0}}, cap_alloc_q};
        CSR_VCONTRACT:     csr_read = contract_valid_q ? {32'd0, contract_generation_q} : 64'd0;
        CSR_VRELEASE:      csr_read = (state_q == ST_RELEASE) ? release_cycle_q : region_release_cycle_q;
        CSR_VREGION_CAPS:  csr_read = {54'd0, region_cap_quota_q, region_cap_used_q};
        default:           csr_read = 64'd0;
      endcase
    end
  endfunction

  task automatic write_integer(
    input logic [4:0] destination,
    input logic [63:0] value,
    input logic secret_value
  );
    begin
      if (destination != 5'd0) begin
        regs_q[destination] <= value;
        cap_valid_q[destination] <= 1'b0;
        cap_index_q[destination] <= '0;
        cap_generation_q[destination] <= '0;
        secret_q[destination] <= secret_value;
        contract_token_tag_q[destination] <= 32'd0;
      end
    end
  endtask

  task automatic copy_register(
    input logic [4:0] destination,
    input logic [4:0] source
  );
    begin
      if (destination != 5'd0) begin
        regs_q[destination] <= regs_q[source];
        cap_valid_q[destination] <= cap_valid_q[source];
        cap_index_q[destination] <= cap_index_q[source];
        cap_generation_q[destination] <= cap_generation_q[source];
        secret_q[destination] <= secret_q[source];
        contract_token_tag_q[destination] <= contract_token_tag_q[source];
      end
    end
  endtask

  task automatic write_capability_reference(
    input logic [4:0] destination,
    input logic [63:0] cursor,
    input logic [4:0] source
  );
    begin
      if (destination != 5'd0) begin
        regs_q[destination] <= cursor;
        cap_valid_q[destination] <= cap_valid_q[source];
        cap_index_q[destination] <= cap_index_q[source];
        cap_generation_q[destination] <= cap_generation_q[source];
        secret_q[destination] <= 1'b0;
        contract_token_tag_q[destination] <= 32'd0;
      end
    end
  endtask

  task automatic allocate_capability(
    input logic [4:0] destination,
    input logic [63:0] cursor,
    input logic [63:0] base,
    input logic [63:0] top,
    input logic [4:0] permissions
  );
    logic [CAP_INDEX_BITS-1:0] slot;
    logic [CAP_GENERATION_BITS-1:0] generation;
    begin
      if (destination != 5'd0) begin
        slot = cap_alloc_q;
        generation = dir_generation_q[slot] + 1'b1;

        dir_valid_q[slot] <= 1'b1;
        dir_base_q[slot] <= base;
        dir_top_q[slot] <= top;
        dir_perm_q[slot] <= permissions;
        dir_generation_q[slot] <= generation;

        regs_q[destination] <= cursor;
        cap_valid_q[destination] <= 1'b1;
        cap_index_q[destination] <= slot;
        cap_generation_q[destination] <= generation;
        secret_q[destination] <= 1'b0;
        contract_token_tag_q[destination] <= 32'd0;

        if (cap_alloc_q == CAP_DIRECTORY_ENTRIES-1)
          cap_alloc_q <= '0;
        else
          cap_alloc_q <= cap_alloc_q + 1'b1;
      end
    end
  endtask

  task automatic scrub_secrets;
    integer index;
    begin
      for (index = 1; index < 32; index = index + 1) begin
        if (secret_q[index]) begin
          regs_q[index] <= 64'd0;
          cap_valid_q[index] <= 1'b0;
          cap_index_q[index] <= '0;
          cap_generation_q[index] <= '0;
          secret_q[index] <= 1'b0;
          contract_token_tag_q[index] <= 32'd0;
        end
      end
    end
  endtask

  task automatic snapshot_region_state;
    integer index;
    begin
      for (index = 0; index < 32; index = index + 1) begin
        region_regs_q[index] <= regs_q[index];
        region_cap_valid_q[index] <= cap_valid_q[index];
        region_cap_index_q[index] <= cap_index_q[index];
        region_cap_generation_q[index] <= cap_generation_q[index];
        region_secret_q[index] <= secret_q[index];
        region_contract_token_tag_q[index] <= contract_token_tag_q[index];
      end
      for (index = 0; index < CAP_DIRECTORY_ENTRIES; index = index + 1) begin
        region_dir_valid_q[index] <= dir_valid_q[index];
        region_dir_base_q[index] <= dir_base_q[index];
        region_dir_top_q[index] <= dir_top_q[index];
        region_dir_perm_q[index] <= dir_perm_q[index];
        region_dir_generation_q[index] <= dir_generation_q[index];
      end
      region_cap_alloc_q <= cap_alloc_q;
    end
  endtask

  task automatic restore_region_state;
    integer index;
    begin
      for (index = 0; index < 32; index = index + 1) begin
        regs_q[index] <= region_regs_q[index];
        cap_valid_q[index] <= region_cap_valid_q[index];
        cap_index_q[index] <= region_cap_index_q[index];
        cap_generation_q[index] <= region_cap_generation_q[index];
        secret_q[index] <= region_secret_q[index];
        contract_token_tag_q[index] <= region_contract_token_tag_q[index];
      end
      for (index = 0; index < CAP_DIRECTORY_ENTRIES; index = index + 1) begin
        dir_valid_q[index] <= region_dir_valid_q[index];
        dir_base_q[index] <= region_dir_base_q[index];
        dir_top_q[index] <= region_dir_top_q[index];
        dir_perm_q[index] <= region_dir_perm_q[index];
        dir_generation_q[index] <= region_dir_generation_q[index];
      end
      cap_alloc_q <= region_cap_alloc_q;
    end
  endtask

  task automatic clear_region_bookkeeping;
    begin
      region_active_q <= 1'b0;
      region_store_quota_q <= 5'd0;
      region_budget_q <= 8'd0;
      region_used_q <= 8'd0;
      region_register_quota_q <= 5'd0;
      region_register_count_q <= 5'd0;
      region_register_dirty_q <= 32'd0;
      region_cap_quota_q <= 5'd0;
      region_cap_used_q <= 5'd0;
      region_arena_valid_q <= 1'b0;
      region_arena_base_q <= 64'd0;
      region_arena_top_q <= 64'd0;
      region_fixed_release_q <= 1'b0;
      region_secret_mode_q <= 1'b0;
      region_release_cycle_q <= 64'd0;
      sb_count_q <= 6'd0;
      commit_index_q <= 6'd0;
      preflight_index_q <= 6'd0;
    end
  endtask

  task automatic finish_region_commit;
    begin
      clear_region_bookkeeping();
      release_abort_q <= 1'b0;
      release_interrupt_q <= 1'b0;
      release_error_q <= 64'd0;
      release_cycle_q <= 64'd0;
      verror_q <= 64'd0;
      state_q <= ST_FETCH;
    end
  endtask

  task automatic abort_region(input logic [63:0] error_code);
    begin
      restore_region_state();
      if (region_fixed_release_q && (cycle_q < region_release_cycle_q)) begin
        release_abort_q <= 1'b1;
        release_interrupt_q <= 1'b0;
        release_error_q <= error_code;
        release_cycle_q <= region_release_cycle_q;
        clear_region_bookkeeping();
        state_q <= ST_RELEASE;
      end else begin
        clear_region_bookkeeping();
        release_abort_q <= 1'b0;
        release_interrupt_q <= 1'b0;
        release_error_q <= 64'd0;
        verror_q <= error_code;
        pc_q <= region_fail_pc_q;
        state_q <= ST_FETCH;
      end
    end
  endtask

  task automatic take_trap(
    input logic [63:0] cause,
    input logic [63:0] bad_address
  );
    begin
      vcause_q <= cause;
      vbadaddr_q <= bad_address;
      vepc_q <= instruction_pc_q;
      interrupt_enable_q <= 1'b0;
      pc_q <= vtvec_q;
      state_q <= ST_FETCH;
    end
  endtask

  task automatic fault(
    input logic [63:0] cause,
    input logic [63:0] bad_address
  );
    begin
      if (region_active_q)
        abort_region(cause);
      else
        take_trap(cause, bad_address);
    end
  endtask

  always_comb begin
    imem_req_o = (state_q == ST_FETCH);
    imem_addr_o = pc_q;

    dmem_req_o = 1'b0;
    dmem_we_o = 1'b0;
    dmem_addr_o = 64'd0;
    dmem_wdata_o = 64'd0;
    dmem_wstrb_o = 8'd0;
    dmem_probe_o = 1'b0;
    dmem_size_o = 4'd0;

    if (state_q == ST_LOAD) begin
      dmem_req_o = 1'b1;
      dmem_addr_o = {mem_addr_q[63:3], 3'b000};
      dmem_size_o = 4'd1 << mem_size_q;
    end else if (state_q == ST_STORE) begin
      dmem_req_o = 1'b1;
      dmem_we_o = 1'b1;
      dmem_addr_o = {mem_addr_q[63:3], 3'b000};
      dmem_wdata_o = mem_wdata_q;
      dmem_wstrb_o = mem_wstrb_q;
      dmem_size_o = 4'd1 << mem_size_q;
    end else if (state_q == ST_PREFLIGHT) begin
      dmem_req_o = 1'b1;
      dmem_we_o = 1'b1;
      dmem_probe_o = 1'b1;
      dmem_addr_o = sb_addr_q[preflight_index_q];
      dmem_wdata_o = sb_data_q[preflight_index_q];
      dmem_wstrb_o = sb_strb_q[preflight_index_q];
      dmem_size_o = 4'd8;
    end else if (state_q == ST_COMMIT) begin
      dmem_req_o = 1'b1;
      dmem_we_o = 1'b1;
      dmem_addr_o = sb_addr_q[commit_index_q];
      dmem_wdata_o = sb_data_q[commit_index_q];
      dmem_wstrb_o = sb_strb_q[commit_index_q];
      dmem_size_o = 4'd8;
    end
  end

  assign halted_o = (state_q == ST_HALT);
  assign debug_pc_o = pc_q;
  assign debug_cause_o = vcause_q;
  assign debug_error_o = verror_q;
  assign debug_region_active_o = region_active_q;
  assign debug_root_locked_o = root_locked_q;
  assign debug_cap_alloc_o = {{(16-CAP_INDEX_BITS){1'b0}}, cap_alloc_q};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_FETCH;
      pc_q <= RESET_PC;
      instruction_q <= 32'd0;
      instruction_pc_q <= RESET_PC;
      interrupt_enable_q <= 1'b0;
      root_locked_q <= 1'b0;
      vtvec_q <= 64'd0;
      vepc_q <= 64'd0;
      vcause_q <= 64'd0;
      vbadaddr_q <= 64'd0;
      verror_q <= 64'd0;
      cycle_q <= 64'd0;
      instret_q <= 64'd0;
      region_active_q <= 1'b0;
      region_fail_pc_q <= 64'd0;
      region_store_quota_q <= 5'd0;
      region_budget_q <= 8'd0;
      region_used_q <= 8'd0;
      region_register_quota_q <= 5'd0;
      region_register_count_q <= 5'd0;
      region_register_dirty_q <= 32'd0;
      region_cap_quota_q <= 5'd0;
      region_cap_used_q <= 5'd0;
      region_arena_valid_q <= 1'b0;
      region_arena_base_q <= 64'd0;
      region_arena_top_q <= 64'd0;
      region_fixed_release_q <= 1'b0;
      region_secret_mode_q <= 1'b0;
      region_release_cycle_q <= 64'd0;
      contract_valid_q <= 1'b0;
      contract_generation_q <= 32'd0;
      contract_store_quota_q <= 5'd0;
      contract_budget_q <= 8'd0;
      contract_register_quota_q <= 5'd0;
      contract_cap_quota_q <= 5'd0;
      contract_fixed_release_q <= 1'b0;
      contract_secret_mode_q <= 1'b0;
      contract_release_delta_q <= 7'd0;
      contract_arena_base_q <= 64'd0;
      contract_arena_top_q <= 64'd0;
      contract_arena_perm_q <= 5'd0;
      release_abort_q <= 1'b0;
      release_interrupt_q <= 1'b0;
      release_error_q <= 64'd0;
      release_cycle_q <= 64'd0;
      sb_count_q <= 6'd0;
      commit_index_q <= 6'd0;
      preflight_index_q <= 6'd0;
      mem_rd_q <= 5'd0;
      mem_addr_q <= 64'd0;
      mem_size_q <= 2'd0;
      mem_signed_q <= 1'b0;
      mem_secret_q <= 1'b0;
      mem_wdata_q <= 64'd0;
      mem_wstrb_q <= 8'd0;
      cap_alloc_q <= '0;
      region_cap_alloc_q <= '0;

      for (i = 0; i < 32; i = i + 1) begin
        regs_q[i] <= 64'd0;
        cap_valid_q[i] <= 1'b0;
        cap_index_q[i] <= '0;
        cap_generation_q[i] <= '0;
        secret_q[i] <= 1'b0;
        contract_token_tag_q[i] <= 32'd0;
        region_regs_q[i] <= 64'd0;
        region_cap_valid_q[i] <= 1'b0;
        region_cap_index_q[i] <= '0;
        region_cap_generation_q[i] <= '0;
        region_secret_q[i] <= 1'b0;
        region_contract_token_tag_q[i] <= 32'd0;
      end
      for (i = 0; i < CAP_DIRECTORY_ENTRIES; i = i + 1) begin
        dir_valid_q[i] <= 1'b0;
        dir_base_q[i] <= 64'd0;
        dir_top_q[i] <= 64'd0;
        dir_perm_q[i] <= 5'd0;
        dir_generation_q[i] <= '0;
        region_dir_valid_q[i] <= 1'b0;
        region_dir_base_q[i] <= 64'd0;
        region_dir_top_q[i] <= 64'd0;
        region_dir_perm_q[i] <= 5'd0;
        region_dir_generation_q[i] <= '0;
      end
      for (i = 0; i < STORE_BUFFER_DEPTH; i = i + 1) begin
        sb_addr_q[i] <= 64'd0;
        sb_data_q[i] <= 64'd0;
        sb_strb_q[i] <= 8'd0;
      end
    end else begin
      cycle_q <= cycle_q + 64'd1;

      case (state_q)
        ST_FETCH: begin
          if (irq_i && interrupt_enable_q) begin
            instruction_pc_q <= pc_q;
            vcause_q <= {48'd0, CAUSE_INTERRUPT};
            vbadaddr_q <= 64'd0;
            interrupt_enable_q <= 1'b0;
            if (region_active_q) begin
              restore_region_state();
              vepc_q <= region_fail_pc_q;
              if (region_fixed_release_q && (cycle_q < region_release_cycle_q)) begin
                release_abort_q <= 1'b1;
                release_interrupt_q <= 1'b1;
                release_error_q <= {48'd0, CAUSE_REGION_PREEMPTED};
                release_cycle_q <= region_release_cycle_q;
                clear_region_bookkeeping();
                state_q <= ST_RELEASE;
              end else begin
                clear_region_bookkeeping();
                verror_q <= {48'd0, CAUSE_REGION_PREEMPTED};
                pc_q <= vtvec_q;
                state_q <= ST_FETCH;
              end
            end else begin
              vepc_q <= pc_q;
              pc_q <= vtvec_q;
              state_q <= ST_FETCH;
            end
          end else if (region_active_q && (region_used_q >= region_budget_q)) begin
            abort_region({48'd0, CAUSE_REGION_BUDGET});
          end else if (imem_fault_i) begin
            vbadaddr_q <= pc_q;
            fault({48'd0, imem_fault_cause_i}, pc_q);
          end else if (imem_ready_i) begin
            instruction_q <= imem_rdata_i;
            instruction_pc_q <= pc_q;
            pc_q <= pc_q + 64'd4;
            if (region_active_q)
              region_used_q <= region_used_q + 8'd1;
            state_q <= ST_EXEC;
          end
        end

        ST_EXEC: begin
          instret_q <= instret_q + 64'd1;
          if (region_active_q && opcode_writes_rd(opcode_w, xmem_function_w) &&
              (rd_w != 5'd0) && !region_register_dirty_q[rd_w] &&
              (region_register_count_q >= region_register_quota_q)) begin
            abort_region({48'd0, CAUSE_REGION_REG_QUOTA});
          end else begin
            if (region_active_q && opcode_writes_rd(opcode_w, xmem_function_w) &&
                (rd_w != 5'd0) && !region_register_dirty_q[rd_w]) begin
              region_register_dirty_q[rd_w] <= 1'b1;
              region_register_count_q <= region_register_count_q + 5'd1;
            end
            case (opcode_w)
            OP_NOP: state_q <= ST_FETCH;

            OP_MOV: begin
              copy_register(rd_w, rs1_w);
              state_q <= ST_FETCH;
            end
            OP_MOVI: begin
              write_integer(rd_w, sext16(imm16_w), 1'b0);
              state_q <= ST_FETCH;
            end
            OP_LUI: begin
              write_integer(rd_w, {32'd0, imm16_w, 16'd0}, 1'b0);
              state_q <= ST_FETCH;
            end
            OP_ADD: begin
              write_integer(rd_w, regs_q[rs1_w] + regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_ADDI: begin
              write_integer(rd_w, regs_q[rs1_w] + sext16(imm16_w), secret_q[rs1_w]);
              state_q <= ST_FETCH;
            end
            OP_SUB: begin
              write_integer(rd_w, regs_q[rs1_w] - regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_MUL: begin
              write_integer(rd_w, regs_q[rs1_w] * regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_AND: begin
              write_integer(rd_w, regs_q[rs1_w] & regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_ANDI: begin
              write_integer(rd_w, regs_q[rs1_w] & {48'd0, imm16_w}, secret_q[rs1_w]);
              state_q <= ST_FETCH;
            end
            OP_OR: begin
              write_integer(rd_w, regs_q[rs1_w] | regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_ORI: begin
              write_integer(rd_w, regs_q[rs1_w] | {48'd0, imm16_w}, secret_q[rs1_w]);
              state_q <= ST_FETCH;
            end
            OP_XOR: begin
              write_integer(rd_w, regs_q[rs1_w] ^ regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_XORI: begin
              write_integer(rd_w, regs_q[rs1_w] ^ {48'd0, imm16_w}, secret_q[rs1_w]);
              state_q <= ST_FETCH;
            end
            OP_SHL: begin
              write_integer(rd_w, regs_q[rs1_w] << regs_q[rs2_w][5:0], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_SHR: begin
              write_integer(rd_w, regs_q[rs1_w] >> regs_q[rs2_w][5:0], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_SAR: begin
              write_integer(rd_w, $signed(regs_q[rs1_w]) >>> regs_q[rs2_w][5:0], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_CMPEQ: begin
              write_integer(rd_w, (regs_q[rs1_w] == regs_q[rs2_w]) ? 64'd1 : 64'd0, secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_CMPLT: begin
              write_integer(rd_w, ($signed(regs_q[rs1_w]) < $signed(regs_q[rs2_w])) ? 64'd1 : 64'd0, secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_CMPULT: begin
              write_integer(rd_w, (regs_q[rs1_w] < regs_q[rs2_w]) ? 64'd1 : 64'd0, secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end

            OP_BRZ, OP_BRNZ: begin
              if (secret_q[branch_rs1_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else begin
                if (((opcode_w == OP_BRZ) && (regs_q[branch_rs1_w] == 64'd0)) ||
                    ((opcode_w == OP_BRNZ) && (regs_q[branch_rs1_w] != 64'd0)))
                  pc_q <= instruction_pc_q + 64'd4 + signext21_words(off21_w);
                state_q <= ST_FETCH;
              end
            end
            OP_JAL: begin
              write_integer(rd_w, instruction_pc_q + 64'd4, 1'b0);
              pc_q <= instruction_pc_q + 64'd4 + signext21_words(off21_w);
              state_q <= ST_FETCH;
            end
            OP_JALR: begin
              if (secret_q[rs1_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else begin
                temp_target = regs_q[rs1_w] + sext16(imm16_w);
                if (temp_target[1:0] != 2'b00)
                  fault({48'd0, CAUSE_INSTRUCTION_ALIGNMENT}, temp_target);
                else begin
                  write_integer(rd_w, instruction_pc_q + 64'd4, 1'b0);
                  pc_q <= temp_target;
                  state_q <= ST_FETCH;
                end
              end
            end
            OP_HALT: begin
              if (region_active_q)
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              else
                state_q <= ST_HALT;
            end
            OP_TRAP: fault({48'd0, CAUSE_EXPLICIT_TRAP}, {48'd0, imm16_w});
            OP_CSRR: begin
              write_integer(rd_w, csr_read(imm16_w), 1'b0);
              state_q <= ST_FETCH;
            end
            OP_CSRW: begin
              if (region_active_q) begin
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              end else if (secret_q[rs1_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else begin
                case (imm16_w)
                  CSR_VSTATUS: interrupt_enable_q <= regs_q[rs1_w][0];
                  CSR_VTVEC: begin
                    if (regs_q[rs1_w][1:0] != 2'b00)
                      fault({48'd0, CAUSE_INSTRUCTION_ALIGNMENT}, regs_q[rs1_w]);
                    else
                      vtvec_q <= regs_q[rs1_w];
                  end
                  CSR_VEPC: vepc_q <= regs_q[rs1_w];
                  CSR_VERROR: verror_q <= regs_q[rs1_w];
                  default: ;
                endcase
                if (!((imm16_w == CSR_VTVEC) && (regs_q[rs1_w][1:0] != 2'b00)))
                  state_q <= ST_FETCH;
              end
            end
            OP_EI: begin
              if (region_active_q)
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              else begin
                interrupt_enable_q <= 1'b1;
                state_q <= ST_FETCH;
              end
            end
            OP_DI: begin
              if (region_active_q)
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              else begin
                interrupt_enable_q <= 1'b0;
                state_q <= ST_FETCH;
              end
            end
            OP_VRET: begin
              if (region_active_q) begin
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              end else if (vepc_q[1:0] != 2'b00) begin
                fault({48'd0, CAUSE_INSTRUCTION_ALIGNMENT}, vepc_q);
              end else begin
                pc_q <= vepc_q;
                interrupt_enable_q <= 1'b1;
                state_q <= ST_FETCH;
              end
            end

            OP_CROOT: begin
              temp_sum = {1'b0, regs_q[rs1_w]} + {1'b0, regs_q[rs2_w]};
              if (region_active_q) begin
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              end else if (root_locked_q) begin
                fault({48'd0, CAUSE_ROOT_LOCKED}, 64'd0);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else if ((regs_q[rs2_w] == 64'd0) || temp_sum[64] || (temp_sum[63:0] > DATA_MEMORY_BYTES)) begin
                fault({48'd0, CAUSE_CAPABILITY_BOUNDS}, regs_q[rs1_w]);
              end else if (dir_generation_q[cap_alloc_q] == {CAP_GENERATION_BITS{1'b1}}) begin
                fault({48'd0, CAUSE_CAPABILITY_GENERATION_WRAP}, regs_q[rs1_w]);
              end else begin
                allocate_capability(rd_w, regs_q[rs1_w], regs_q[rs1_w], temp_sum[63:0], aux_w[4:0]);
                state_q <= ST_FETCH;
              end
            end
            OP_CBOUNDS: begin
              temp_sum = {1'b0, regs_q[rs1_w]} + {1'b0, regs_q[rs2_w]};
              if (!cap_valid_q[rs1_w]) begin
                fault({48'd0, CAUSE_CAPABILITY_TAG}, 64'd0);
              end else if (!cap_live(rs1_w)) begin
                fault({48'd0, CAUSE_CAPABILITY_STALE}, regs_q[rs1_w]);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else if (temp_sum[64] || (regs_q[rs1_w] < cap_base(rs1_w)) || (temp_sum[63:0] > cap_top(rs1_w))) begin
                fault({48'd0, CAUSE_CAPABILITY_BOUNDS}, regs_q[rs1_w]);
              end else if (region_active_q && (region_cap_used_q >= region_cap_quota_q)) begin
                abort_region({48'd0, CAUSE_REGION_CAP_QUOTA});
              end else if (dir_generation_q[cap_alloc_q] == {CAP_GENERATION_BITS{1'b1}}) begin
                fault({48'd0, CAUSE_CAPABILITY_GENERATION_WRAP}, regs_q[rs1_w]);
              end else begin
                allocate_capability(rd_w, regs_q[rs1_w], regs_q[rs1_w], temp_sum[63:0], cap_permissions(rs1_w));
                if (region_active_q)
                  region_cap_used_q <= region_cap_used_q + 5'd1;
                state_q <= ST_FETCH;
              end
            end
            OP_CPERM: begin
              if (!cap_valid_q[rs1_w]) begin
                fault({48'd0, CAUSE_CAPABILITY_TAG}, 64'd0);
              end else if (!cap_live(rs1_w)) begin
                fault({48'd0, CAUSE_CAPABILITY_STALE}, regs_q[rs1_w]);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else if (region_active_q && (region_cap_used_q >= region_cap_quota_q)) begin
                abort_region({48'd0, CAUSE_REGION_CAP_QUOTA});
              end else if (dir_generation_q[cap_alloc_q] == {CAP_GENERATION_BITS{1'b1}}) begin
                fault({48'd0, CAUSE_CAPABILITY_GENERATION_WRAP}, regs_q[rs1_w]);
              end else begin
                allocate_capability(rd_w, regs_q[rs1_w], cap_base(rs1_w), cap_top(rs1_w), cap_permissions(rs1_w) & regs_q[rs2_w][4:0]);
                if (region_active_q)
                  region_cap_used_q <= region_cap_used_q + 5'd1;
                state_q <= ST_FETCH;
              end
            end
            OP_CINC: begin
              temp_cursor = regs_q[rs1_w] + regs_q[rs2_w];
              if (!cap_valid_q[rs1_w]) begin
                fault({48'd0, CAUSE_CAPABILITY_TAG}, 64'd0);
              end else if (!cap_live(rs1_w)) begin
                fault({48'd0, CAUSE_CAPABILITY_STALE}, regs_q[rs1_w]);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else if ((temp_cursor < cap_base(rs1_w)) || (temp_cursor > cap_top(rs1_w))) begin
                fault({48'd0, CAUSE_CAPABILITY_BOUNDS}, temp_cursor);
              end else begin
                write_capability_reference(rd_w, temp_cursor, rs1_w);
                state_q <= ST_FETCH;
              end
            end
            OP_CGETTAG: begin
              write_integer(rd_w, cap_live(rs1_w) ? 64'd1 : 64'd0, 1'b0);
              state_q <= ST_FETCH;
            end
            OP_CGETPERM: begin
              write_integer(rd_w, cap_live(rs1_w) ? {59'd0, cap_permissions(rs1_w)} : 64'd0, 1'b0);
              state_q <= ST_FETCH;
            end

            OP_CLDB, OP_CLDBU, OP_CLDH, OP_CLDHU, OP_CLDW,
            OP_CSTB, OP_CSTH, OP_CSTW, OP_XMEM: begin
              temp_is_load = 1'b0;
              temp_is_store = 1'b0;
              temp_signed = 1'b0;

              if (opcode_w == OP_XMEM) begin
                if (xmem_function_w == XMEM_CLDD) begin
                  temp_size = 2'd3;
                  temp_is_load = 1'b1;
                end else if (xmem_function_w == XMEM_CSTD) begin
                  temp_size = 2'd3;
                  temp_is_store = 1'b1;
                end else begin
                  temp_size = 2'd0;
                end
                temp_value = sext11(xmem_imm11_w);
              end else begin
                if ((opcode_w == OP_CLDB) || (opcode_w == OP_CLDBU) || (opcode_w == OP_CSTB))
                  temp_size = 2'd0;
                else if ((opcode_w == OP_CLDH) || (opcode_w == OP_CLDHU) || (opcode_w == OP_CSTH))
                  temp_size = 2'd1;
                else
                  temp_size = 2'd2;

                temp_is_load = (opcode_w >= OP_CLDB) && (opcode_w <= OP_CLDW);
                temp_is_store = (opcode_w >= OP_CSTB) && (opcode_w <= OP_CSTW);
                temp_signed = (opcode_w == OP_CLDB) || (opcode_w == OP_CLDH);
                temp_value = sext16(imm16_w);
              end

              temp_address = regs_q[rs1_w] + temp_value;
              temp_address_overflow = (!temp_value[63] && (temp_address < regs_q[rs1_w])) ||
                                      (temp_value[63] && (temp_address > regs_q[rs1_w]));
              temp_end_sum = {1'b0, temp_address} + (65'd1 << temp_size);
              temp_end = temp_end_sum[63:0];

              if ((opcode_w == OP_XMEM) && !temp_is_load && !temp_is_store) begin
                fault({48'd0, CAUSE_ILLEGAL_INSTRUCTION}, {32'd0, instruction_q});
              end else if (secret_q[rs1_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else if (!cap_valid_q[rs1_w]) begin
                fault({48'd0, CAUSE_CAPABILITY_TAG}, temp_address);
              end else if (!cap_live(rs1_w)) begin
                fault({48'd0, CAUSE_CAPABILITY_STALE}, temp_address);
              end else if ((temp_is_load && ((cap_permissions(rs1_w) & CAP_R) == 0)) ||
                           (temp_is_store && ((cap_permissions(rs1_w) & CAP_W) == 0))) begin
                fault({48'd0, CAUSE_CAPABILITY_PERMISSION}, temp_address);
              end else if (temp_address_overflow || temp_end_sum[64] ||
                           (temp_address < cap_base(rs1_w)) || (temp_end > cap_top(rs1_w)) ||
                           (temp_end > DATA_MEMORY_BYTES)) begin
                fault({48'd0, CAUSE_CAPABILITY_BOUNDS}, temp_address);
              end else if (region_active_q && region_arena_valid_q &&
                           ((temp_address < region_arena_base_q) || (temp_end > region_arena_top_q))) begin
                abort_region({48'd0, CAUSE_REGION_ARENA});
              end else if (((temp_size == 2'd1) && temp_address[0]) ||
                           ((temp_size == 2'd2) && (temp_address[1:0] != 2'b00)) ||
                           ((temp_size == 2'd3) && (temp_address[2:0] != 3'b000))) begin
                fault({48'd0, CAUSE_DATA_ALIGNMENT}, temp_address);
              end else if (temp_is_store && secret_q[rd_w] && ((cap_permissions(rs1_w) & CAP_S) == 0)) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, temp_address);
              end else if (temp_is_load) begin
                mem_rd_q <= rd_w;
                mem_addr_q <= temp_address;
                mem_size_q <= temp_size;
                mem_signed_q <= temp_signed;
                mem_secret_q <= ((cap_permissions(rs1_w) & CAP_S) != 0);
                state_q <= ST_LOAD;
              end else begin
                temp_strb = store_strobe(temp_size, temp_address[2:0]);
                temp_store_data = store_data(regs_q[rd_w], temp_size, temp_address[2:0]);
                if (region_active_q) begin
                  temp_merge_found = 1'b0;
                  temp_merge_index = 0;
                  for (i = 0; i < STORE_BUFFER_DEPTH; i = i + 1) begin
                    if ((i < sb_count_q) && (sb_addr_q[i] == {temp_address[63:3], 3'b000})) begin
                      temp_merge_found = 1'b1;
                      temp_merge_index = i;
                    end
                  end
                  if (temp_merge_found) begin
                    for (temp_byte_index = 0; temp_byte_index < 8; temp_byte_index = temp_byte_index + 1) begin
                      if (temp_strb[temp_byte_index])
                        sb_data_q[temp_merge_index][temp_byte_index*8 +: 8] <= temp_store_data[temp_byte_index*8 +: 8];
                    end
                    sb_strb_q[temp_merge_index] <= sb_strb_q[temp_merge_index] | temp_strb;
                    state_q <= ST_FETCH;
                  end else if ((sb_count_q >= region_store_quota_q) || (sb_count_q >= STORE_BUFFER_DEPTH)) begin
                    abort_region({48'd0, CAUSE_REGION_STORE_QUOTA});
                  end else begin
                    sb_addr_q[sb_count_q] <= {temp_address[63:3], 3'b000};
                    sb_data_q[sb_count_q] <= temp_store_data;
                    sb_strb_q[sb_count_q] <= temp_strb;
                    sb_count_q <= sb_count_q + 6'd1;
                    state_q <= ST_FETCH;
                  end
                end else begin
                  mem_addr_q <= temp_address;
                  mem_wdata_q <= temp_store_data;
                  mem_wstrb_q <= temp_strb;
                  state_q <= ST_STORE;
                end
              end
            end

            OP_VDECLASS: begin
              if (!cap_live(rs2_w) || ((cap_permissions(rs2_w) & CAP_D) == 0))
                fault({48'd0, CAUSE_DECLASSIFY_DENIED}, 64'd0);
              else begin
                write_integer(rd_w, regs_q[rs1_w], 1'b0);
                state_q <= ST_FETCH;
              end
            end
            OP_VLOCK: begin
              if (region_active_q)
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              else begin
                root_locked_q <= 1'b1;
                state_q <= ST_FETCH;
              end
            end

            OP_VTRY: begin
              if (region_active_q) begin
                abort_region({48'd0, CAUSE_REGION_NESTED});
              end else if ((vtry_stores_w == 5'd0) ||
                           (vtry_stores_w > STORE_BUFFER_DEPTH) ||
                           (vtry_budget_w == 8'd0)) begin
                fault({48'd0, CAUSE_REGION_STORE_QUOTA}, 64'd0);
              end else begin
                snapshot_region_state();
                region_active_q <= 1'b1;
                region_fail_pc_q <= instruction_pc_q + 64'd4 + signext13_words(vtry_off13_w);
                region_store_quota_q <= vtry_stores_w;
                region_budget_q <= vtry_budget_w;
                region_used_q <= 8'd0;
                region_register_quota_q <= 5'd31;
                region_register_count_q <= 5'd0;
                region_register_dirty_q <= 32'd0;
                region_cap_quota_q <= 5'd0;
                region_cap_used_q <= 5'd0;
                region_arena_valid_q <= 1'b0;
                region_arena_base_q <= 64'd0;
                region_arena_top_q <= 64'd0;
                region_fixed_release_q <= 1'b0;
                region_secret_mode_q <= 1'b0;
                region_release_cycle_q <= 64'd0;
                sb_count_q <= 6'd0;
                commit_index_q <= 6'd0;
                preflight_index_q <= 6'd0;
                release_abort_q <= 1'b0;
                release_interrupt_q <= 1'b0;
                release_error_q <= 64'd0;
                verror_q <= 64'd0;
                state_q <= ST_FETCH;
              end
            end
            OP_VPREP: begin
              temp_contract_spec = regs_q[rs2_w][31:0];
              temp_contract_generation = contract_generation_q + 32'd1;
              if (region_active_q) begin
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              end else if ((rd_w == 5'd0) || contract_valid_q || (aux_w != 11'd0)) begin
                fault({48'd0, CAUSE_CONTRACT_ADMISSION}, 64'd0);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({48'd0, CAUSE_SECRET_FLOW}, 64'd0);
              end else if (!cap_valid_q[rs1_w]) begin
                fault({48'd0, CAUSE_CAPABILITY_TAG}, regs_q[rs1_w]);
              end else if (!cap_live(rs1_w)) begin
                fault({48'd0, CAUSE_CAPABILITY_STALE}, regs_q[rs1_w]);
              end else if ((temp_contract_spec[4:0] == 5'd0) ||
                           (temp_contract_spec[4:0] > STORE_BUFFER_DEPTH) ||
                           (temp_contract_spec[12:5] == 8'd0) ||
                           (temp_contract_spec[17:13] == 5'd0) ||
                           (temp_contract_spec[17:13] > 5'd31) ||
                           (temp_contract_spec[22:18] > MAX_CONTRACT_CAP_ALLOCS) ||
                           (temp_contract_spec[23] && (temp_contract_spec[31:25] == 7'd0)) ||
                           (temp_contract_spec[24] && !temp_contract_spec[23]) ||
                           (temp_contract_spec[24] && ((cap_permissions(rs1_w) & CAP_S) == 0)) ||
                           ((cap_permissions(rs1_w) & (CAP_R | CAP_W)) == 0) ||
                           (temp_contract_generation == 32'd0)) begin
                fault({48'd0, CAUSE_CONTRACT_ADMISSION}, regs_q[rs2_w]);
              end else begin
                contract_valid_q <= 1'b1;
                contract_generation_q <= temp_contract_generation;
                contract_store_quota_q <= temp_contract_spec[4:0];
                contract_budget_q <= temp_contract_spec[12:5];
                contract_register_quota_q <= temp_contract_spec[17:13];
                contract_cap_quota_q <= temp_contract_spec[22:18];
                contract_fixed_release_q <= temp_contract_spec[23];
                contract_secret_mode_q <= temp_contract_spec[24];
                contract_release_delta_q <= temp_contract_spec[31:25];
                contract_arena_base_q <= cap_base(rs1_w);
                contract_arena_top_q <= cap_top(rs1_w);
                contract_arena_perm_q <= cap_permissions(rs1_w);
                regs_q[rd_w] <= {32'd0, temp_contract_generation};
                cap_valid_q[rd_w] <= 1'b0;
                cap_index_q[rd_w] <= '0;
                cap_generation_q[rd_w] <= '0;
                secret_q[rd_w] <= 1'b0;
                contract_token_tag_q[rd_w] <= temp_contract_generation;
                state_q <= ST_FETCH;
              end
            end
            OP_VTRYC: begin
              if (region_active_q) begin
                abort_region({48'd0, CAUSE_REGION_NESTED});
              end else if (!contract_token_live(branch_rs1_w)) begin
                fault({48'd0, CAUSE_CONTRACT_TOKEN}, regs_q[branch_rs1_w]);
              end else begin
                snapshot_region_state();
                contract_valid_q <= 1'b0;
                region_active_q <= 1'b1;
                region_fail_pc_q <= instruction_pc_q + 64'd4 + signext21_words(off21_w);
                region_store_quota_q <= contract_store_quota_q;
                region_budget_q <= contract_budget_q;
                region_used_q <= 8'd0;
                region_register_quota_q <= contract_register_quota_q;
                region_register_count_q <= 5'd0;
                region_register_dirty_q <= 32'd0;
                region_cap_quota_q <= contract_cap_quota_q;
                region_cap_used_q <= 5'd0;
                region_arena_valid_q <= 1'b1;
                region_arena_base_q <= contract_arena_base_q;
                region_arena_top_q <= contract_arena_top_q;
                region_fixed_release_q <= contract_fixed_release_q;
                region_secret_mode_q <= contract_secret_mode_q;
                region_release_cycle_q <= cycle_q + {57'd0, contract_release_delta_q};
                sb_count_q <= 6'd0;
                commit_index_q <= 6'd0;
                preflight_index_q <= 6'd0;
                release_abort_q <= 1'b0;
                release_interrupt_q <= 1'b0;
                release_error_q <= 64'd0;
                verror_q <= 64'd0;
                state_q <= ST_FETCH;
              end
            end
            OP_VCANCEL: begin
              if (region_active_q) begin
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              end else if (!contract_token_live(rs1_w)) begin
                fault({48'd0, CAUSE_CONTRACT_TOKEN}, regs_q[rs1_w]);
              end else begin
                contract_valid_q <= 1'b0;
                contract_token_tag_q[rs1_w] <= 32'd0;
                state_q <= ST_FETCH;
              end
            end
            OP_VCHK: begin
              if (!region_active_q)
                fault({48'd0, CAUSE_REGION_REQUIRED}, 64'd0);
              else if (secret_q[rs1_w])
                abort_region({48'd0, CAUSE_SECRET_FLOW});
              else if (regs_q[rs1_w] == 64'd0)
                abort_region((imm16_w == 16'd0) ? {48'd0, CAUSE_EXPLICIT_TRAP} : {48'd0, imm16_w});
              else
                state_q <= ST_FETCH;
            end
            OP_VIC: begin
              if (!region_active_q) begin
                fault({48'd0, CAUSE_REGION_REQUIRED}, 64'd0);
              end else if (region_fixed_release_q && (cycle_q < region_release_cycle_q)) begin
                release_abort_q <= 1'b0;
                release_interrupt_q <= 1'b0;
                release_error_q <= 64'd0;
                release_cycle_q <= region_release_cycle_q;
                state_q <= ST_RELEASE;
              end else if (sb_count_q == 0) begin
                finish_region_commit();
              end else begin
                preflight_index_q <= 6'd0;
                state_q <= ST_PREFLIGHT;
              end
            end
            OP_VABT: begin
              if (!region_active_q)
                fault({48'd0, CAUSE_REGION_REQUIRED}, 64'd0);
              else
                abort_region((imm16_w == 16'd0) ? {48'd0, CAUSE_EXPLICIT_TRAP} : {48'd0, imm16_w});
            end
            OP_VERR: begin
              write_integer(rd_w, verror_q, 1'b0);
              state_q <= ST_FETCH;
            end
            OP_WFI: begin
              if (region_active_q)
                abort_region({48'd0, CAUSE_REGION_REQUIRED});
              else
                state_q <= ST_WFI;
            end

            default: fault({48'd0, CAUSE_ILLEGAL_INSTRUCTION}, {32'd0, instruction_q});
            endcase
          end
        end

        ST_LOAD: begin
          if (dmem_fault_i) begin
            vbadaddr_q <= dmem_addr_o;
            fault({48'd0, dmem_fault_cause_i}, dmem_addr_o);
          end else if (dmem_ready_i) begin
            temp_dword = forwarded_dword(dmem_rdata_i, {mem_addr_q[63:3], 3'b000});
            temp_value = temp_dword >> (mem_addr_q[2:0] * 8);
            case (mem_size_q)
              2'd0: temp_value = mem_signed_q ? sext8(temp_value[7:0]) : {56'd0, temp_value[7:0]};
              2'd1: temp_value = mem_signed_q ? sext_half(temp_value[15:0]) : {48'd0, temp_value[15:0]};
              2'd2: temp_value = {32'd0, temp_value[31:0]};
              default: ;
            endcase
            write_integer(mem_rd_q, temp_value, mem_secret_q);
            state_q <= ST_FETCH;
          end
        end

        ST_STORE: begin
          if (dmem_fault_i) begin
            vbadaddr_q <= dmem_addr_o;
            fault({48'd0, dmem_fault_cause_i}, dmem_addr_o);
          end else if (dmem_ready_i) begin
            state_q <= ST_FETCH;
          end
        end

        ST_PREFLIGHT: begin
          if (dmem_fault_i) begin
            vbadaddr_q <= dmem_addr_o;
            abort_region({48'd0, dmem_fault_cause_i});
          end else if (dmem_ready_i) begin
            if (preflight_index_q + 6'd1 >= sb_count_q) begin
              commit_index_q <= 6'd0;
              state_q <= ST_COMMIT;
            end else begin
              preflight_index_q <= preflight_index_q + 6'd1;
            end
          end
        end

        ST_COMMIT: begin
          if (dmem_fault_i) begin
            vbadaddr_q <= dmem_addr_o;
            vcause_q <= {48'd0, CAUSE_COMMIT_PROTOCOL};
            verror_q <= {48'd0, CAUSE_COMMIT_PROTOCOL};
            clear_region_bookkeeping();
            state_q <= ST_HALT;
          end else if (dmem_ready_i) begin
            if (commit_index_q + 6'd1 >= sb_count_q) begin
              finish_region_commit();
            end else begin
              commit_index_q <= commit_index_q + 6'd1;
            end
          end
        end

        ST_RELEASE: begin
          if (cycle_q >= release_cycle_q) begin
            if (release_abort_q) begin
              verror_q <= release_error_q;
              release_abort_q <= 1'b0;
              release_error_q <= 64'd0;
              if (release_interrupt_q) begin
                release_interrupt_q <= 1'b0;
                pc_q <= vtvec_q;
              end else begin
                pc_q <= region_fail_pc_q;
              end
              state_q <= ST_FETCH;
            end else if (sb_count_q == 0) begin
              finish_region_commit();
            end else begin
              preflight_index_q <= 6'd0;
              state_q <= ST_PREFLIGHT;
            end
          end
        end

        ST_WFI: begin
          if (irq_i) begin
            if (interrupt_enable_q) begin
              instruction_pc_q <= pc_q;
              vcause_q <= {48'd0, CAUSE_INTERRUPT};
              vbadaddr_q <= 64'd0;
              vepc_q <= pc_q;
              interrupt_enable_q <= 1'b0;
              pc_q <= vtvec_q;
            end
            state_q <= ST_FETCH;
          end
        end

        default: state_q <= ST_HALT;
      endcase

      regs_q[0] <= 64'd0;
      cap_valid_q[0] <= 1'b0;
      cap_index_q[0] <= '0;
      cap_generation_q[0] <= '0;
      secret_q[0] <= 1'b0;
      contract_token_tag_q[0] <= 32'd0;
    end
  end
endmodule
