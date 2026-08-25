`timescale 1ns/1ps

module vv32_core #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000,
  parameter integer DATA_MEMORY_BYTES = 65536,
  parameter integer STORE_BUFFER_DEPTH = 8
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  output logic        imem_req_o,
  output logic [31:0] imem_addr_o,
  input  logic [31:0] imem_rdata_i,
  input  logic        imem_ready_i,

  output logic        dmem_req_o,
  output logic        dmem_we_o,
  output logic [31:0] dmem_addr_o,
  output logic [31:0] dmem_wdata_o,
  output logic [3:0]  dmem_wstrb_o,
  input  logic [31:0] dmem_rdata_i,
  input  logic        dmem_ready_i,

  input  logic        irq_i,

  output logic        halted_o,
  output logic [31:0] debug_pc_o,
  output logic [31:0] debug_cause_o,
  output logic [31:0] debug_error_o,
  output logic        debug_region_active_o,
  output logic        debug_root_locked_o
);
  import vv32_pkg::*;

  vv32_state_t state_q;
  logic [31:0] pc_q;
  logic [31:0] instruction_q;
  logic [31:0] instruction_pc_q;

  logic [31:0] regs_q [0:31];
  logic        cap_valid_q [0:31];
  logic [31:0] cap_base_q [0:31];
  logic [31:0] cap_top_q [0:31];
  logic [4:0]  cap_perm_q [0:31];
  logic        secret_q [0:31];

  logic        interrupt_enable_q;
  logic        root_locked_q;
  logic [31:0] vtvec_q;
  logic [31:0] vepc_q;
  logic [31:0] vcause_q;
  logic [31:0] vbadaddr_q;
  logic [31:0] verror_q;
  logic [31:0] cycle_q;
  logic [31:0] instret_q;

  logic        region_active_q;
  logic [31:0] region_fail_pc_q;
  logic [4:0]  region_store_quota_q;
  logic [7:0]  region_budget_q;
  logic [7:0]  region_used_q;

  logic [31:0] sb_addr_q [0:STORE_BUFFER_DEPTH-1];
  logic [31:0] sb_data_q [0:STORE_BUFFER_DEPTH-1];
  logic [3:0]  sb_strb_q [0:STORE_BUFFER_DEPTH-1];
  logic [5:0]  sb_count_q;
  logic [5:0]  commit_index_q;

  logic [4:0]  mem_rd_q;
  logic [31:0] mem_addr_q;
  logic [1:0]  mem_size_q;
  logic        mem_signed_q;
  logic        mem_secret_q;
  logic [31:0] mem_wdata_q;
  logic [3:0]  mem_wstrb_q;

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

  integer i;
  integer k;
  logic [32:0] temp_sum;
  logic [31:0] temp_value;
  logic [31:0] temp_target;
  logic [31:0] temp_word;
  logic [31:0] temp_base;
  logic [31:0] temp_top;
  logic [31:0] temp_cursor;
  logic [31:0] temp_length;
  logic [31:0] temp_address;
  logic [31:0] temp_end;
  logic [1:0]  temp_size;
  logic [3:0]  temp_strb;
  logic [31:0] temp_store_data;
  logic        temp_signed;

  function automatic logic [31:0] sext16(input logic [15:0] value);
    sext16 = {{16{value[15]}}, value};
  endfunction

  function automatic logic [31:0] sext8(input logic [7:0] value);
    sext8 = {{24{value[7]}}, value};
  endfunction

  function automatic logic [31:0] sext_half(input logic [15:0] value);
    sext_half = {{16{value[15]}}, value};
  endfunction

  function automatic logic [31:0] signext13_words(input logic signed [12:0] value);
    signext13_words = {{17{value[12]}}, value, 2'b00};
  endfunction

  function automatic logic [31:0] signext21_words(input logic signed [20:0] value);
    signext21_words = {{9{value[20]}}, value, 2'b00};
  endfunction

  function automatic logic [3:0] store_strobe(
    input logic [1:0] size,
    input logic [1:0] address_low
  );
    begin
      case (size)
        2'd0: store_strobe = 4'b0001 << address_low;
        2'd1: store_strobe = address_low[1] ? 4'b1100 : 4'b0011;
        default: store_strobe = 4'b1111;
      endcase
    end
  endfunction

  function automatic logic [31:0] store_data(
    input logic [31:0] value,
    input logic [1:0] size,
    input logic [1:0] address_low
  );
    begin
      case (size)
        2'd0: store_data = (value & 32'h0000_00ff) << (address_low * 8);
        2'd1: store_data = (value & 32'h0000_ffff) << (address_low[1] * 16);
        default: store_data = value;
      endcase
    end
  endfunction

  function automatic logic [31:0] forwarded_word(
    input logic [31:0] memory_word,
    input logic [31:0] aligned_address
  );
    logic [31:0] result;
    integer index;
    begin
      result = memory_word;
      for (index = 0; index < STORE_BUFFER_DEPTH; index = index + 1) begin
        if ((index < sb_count_q) && (sb_addr_q[index] == aligned_address)) begin
          if (sb_strb_q[index][0]) result[7:0]   = sb_data_q[index][7:0];
          if (sb_strb_q[index][1]) result[15:8]  = sb_data_q[index][15:8];
          if (sb_strb_q[index][2]) result[23:16] = sb_data_q[index][23:16];
          if (sb_strb_q[index][3]) result[31:24] = sb_data_q[index][31:24];
        end
      end
      forwarded_word = result;
    end
  endfunction

  function automatic logic [31:0] csr_read(input logic [15:0] csr);
    begin
      case (csr)
        CSR_VSTATUS:       csr_read = {29'd0, region_active_q, root_locked_q, interrupt_enable_q};
        CSR_VTVEC:         csr_read = vtvec_q;
        CSR_VEPC:          csr_read = vepc_q;
        CSR_VCAUSE:        csr_read = vcause_q;
        CSR_VBADADDR:      csr_read = vbadaddr_q;
        CSR_VCYCLE:        csr_read = cycle_q;
        CSR_VINSTRET:      csr_read = instret_q;
        CSR_VERROR:        csr_read = verror_q;
        CSR_VREGION_COUNT: csr_read = {26'd0, sb_count_q};
        CSR_VREGION_LIMIT: csr_read = {24'd0, region_budget_q};
        default:           csr_read = 32'd0;
      endcase
    end
  endfunction

  task automatic write_integer(
    input logic [4:0] destination,
    input logic [31:0] value,
    input logic secret_value
  );
    begin
      if (destination != 5'd0) begin
        regs_q[destination] <= value;
        cap_valid_q[destination] <= 1'b0;
        cap_base_q[destination] <= 32'd0;
        cap_top_q[destination] <= 32'd0;
        cap_perm_q[destination] <= 5'd0;
        secret_q[destination] <= secret_value;
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
        cap_base_q[destination] <= cap_base_q[source];
        cap_top_q[destination] <= cap_top_q[source];
        cap_perm_q[destination] <= cap_perm_q[source];
        secret_q[destination] <= secret_q[source];
      end
    end
  endtask

  task automatic write_capability(
    input logic [4:0] destination,
    input logic [31:0] cursor,
    input logic [31:0] base,
    input logic [31:0] top,
    input logic [4:0] permissions
  );
    begin
      if (destination != 5'd0) begin
        regs_q[destination] <= cursor;
        cap_valid_q[destination] <= 1'b1;
        cap_base_q[destination] <= base;
        cap_top_q[destination] <= top;
        cap_perm_q[destination] <= permissions;
        secret_q[destination] <= 1'b0;
      end
    end
  endtask

  task automatic scrub_secrets;
    integer index;
    begin
      for (index = 1; index < 32; index = index + 1) begin
        if (secret_q[index]) begin
          regs_q[index] <= 32'd0;
          cap_valid_q[index] <= 1'b0;
          cap_base_q[index] <= 32'd0;
          cap_top_q[index] <= 32'd0;
          cap_perm_q[index] <= 5'd0;
          secret_q[index] <= 1'b0;
        end
      end
    end
  endtask

  task automatic abort_region(input logic [31:0] error_code);
    begin
      region_active_q <= 1'b0;
      region_store_quota_q <= 5'd0;
      region_budget_q <= 8'd0;
      region_used_q <= 8'd0;
      sb_count_q <= 6'd0;
      commit_index_q <= 6'd0;
      verror_q <= error_code;
      pc_q <= region_fail_pc_q;
      state_q <= ST_FETCH;
      scrub_secrets();
    end
  endtask

  task automatic take_trap(
    input logic [31:0] cause,
    input logic [31:0] bad_address
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
    input logic [31:0] cause,
    input logic [31:0] bad_address
  );
    begin
      if (region_active_q) begin
        abort_region(cause);
      end else begin
        take_trap(cause, bad_address);
      end
    end
  endtask

  always_comb begin
    imem_req_o = (state_q == ST_FETCH);
    imem_addr_o = pc_q;

    dmem_req_o = 1'b0;
    dmem_we_o = 1'b0;
    dmem_addr_o = 32'd0;
    dmem_wdata_o = 32'd0;
    dmem_wstrb_o = 4'd0;

    if (state_q == ST_LOAD) begin
      dmem_req_o = 1'b1;
      dmem_we_o = 1'b0;
      dmem_addr_o = {mem_addr_q[31:2], 2'b00};
    end else if (state_q == ST_STORE) begin
      dmem_req_o = 1'b1;
      dmem_we_o = 1'b1;
      dmem_addr_o = {mem_addr_q[31:2], 2'b00};
      dmem_wdata_o = mem_wdata_q;
      dmem_wstrb_o = mem_wstrb_q;
    end else if (state_q == ST_COMMIT) begin
      dmem_req_o = 1'b1;
      dmem_we_o = 1'b1;
      dmem_addr_o = sb_addr_q[commit_index_q];
      dmem_wdata_o = sb_data_q[commit_index_q];
      dmem_wstrb_o = sb_strb_q[commit_index_q];
    end
  end

  assign halted_o = (state_q == ST_HALT);
  assign debug_pc_o = pc_q;
  assign debug_cause_o = vcause_q;
  assign debug_error_o = verror_q;
  assign debug_region_active_o = region_active_q;
  assign debug_root_locked_o = root_locked_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_FETCH;
      pc_q <= RESET_PC;
      instruction_q <= 32'd0;
      instruction_pc_q <= RESET_PC;
      interrupt_enable_q <= 1'b0;
      root_locked_q <= 1'b0;
      vtvec_q <= 32'd0;
      vepc_q <= 32'd0;
      vcause_q <= 32'd0;
      vbadaddr_q <= 32'd0;
      verror_q <= 32'd0;
      cycle_q <= 32'd0;
      instret_q <= 32'd0;
      region_active_q <= 1'b0;
      region_fail_pc_q <= 32'd0;
      region_store_quota_q <= 5'd0;
      region_budget_q <= 8'd0;
      region_used_q <= 8'd0;
      sb_count_q <= 6'd0;
      commit_index_q <= 6'd0;
      mem_rd_q <= 5'd0;
      mem_addr_q <= 32'd0;
      mem_size_q <= 2'd0;
      mem_signed_q <= 1'b0;
      mem_secret_q <= 1'b0;
      mem_wdata_q <= 32'd0;
      mem_wstrb_q <= 4'd0;
      for (i = 0; i < 32; i = i + 1) begin
        regs_q[i] <= 32'd0;
        cap_valid_q[i] <= 1'b0;
        cap_base_q[i] <= 32'd0;
        cap_top_q[i] <= 32'd0;
        cap_perm_q[i] <= 5'd0;
        secret_q[i] <= 1'b0;
      end
      for (i = 0; i < STORE_BUFFER_DEPTH; i = i + 1) begin
        sb_addr_q[i] <= 32'd0;
        sb_data_q[i] <= 32'd0;
        sb_strb_q[i] <= 4'd0;
      end
    end else begin
      cycle_q <= cycle_q + 32'd1;

      case (state_q)
        ST_FETCH: begin
          if (irq_i && interrupt_enable_q && !region_active_q) begin
            instruction_pc_q <= pc_q;
            vcause_q <= {16'd0, CAUSE_INTERRUPT};
            vbadaddr_q <= 32'd0;
            vepc_q <= pc_q;
            interrupt_enable_q <= 1'b0;
            pc_q <= vtvec_q;
          end else if (region_active_q && (region_used_q >= region_budget_q)) begin
            abort_region({16'd0, CAUSE_REGION_BUDGET});
          end else if (imem_ready_i) begin
            instruction_q <= imem_rdata_i;
            instruction_pc_q <= pc_q;
            pc_q <= pc_q + 32'd4;
            if (region_active_q) region_used_q <= region_used_q + 8'd1;
            state_q <= ST_EXEC;
          end
        end

        ST_EXEC: begin
          instret_q <= instret_q + 32'd1;
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
              write_integer(rd_w, {imm16_w, 16'd0}, 1'b0);
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
              write_integer(rd_w, regs_q[rs1_w] & {16'd0, imm16_w}, secret_q[rs1_w]);
              state_q <= ST_FETCH;
            end
            OP_OR: begin
              write_integer(rd_w, regs_q[rs1_w] | regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_ORI: begin
              write_integer(rd_w, regs_q[rs1_w] | {16'd0, imm16_w}, secret_q[rs1_w]);
              state_q <= ST_FETCH;
            end
            OP_XOR: begin
              write_integer(rd_w, regs_q[rs1_w] ^ regs_q[rs2_w], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_XORI: begin
              write_integer(rd_w, regs_q[rs1_w] ^ {16'd0, imm16_w}, secret_q[rs1_w]);
              state_q <= ST_FETCH;
            end
            OP_SHL: begin
              write_integer(rd_w, regs_q[rs1_w] << regs_q[rs2_w][4:0], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_SHR: begin
              write_integer(rd_w, regs_q[rs1_w] >> regs_q[rs2_w][4:0], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_SAR: begin
              write_integer(rd_w, $signed(regs_q[rs1_w]) >>> regs_q[rs2_w][4:0], secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_CMPEQ: begin
              write_integer(rd_w, (regs_q[rs1_w] == regs_q[rs2_w]) ? 32'd1 : 32'd0, secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_CMPLT: begin
              write_integer(rd_w, ($signed(regs_q[rs1_w]) < $signed(regs_q[rs2_w])) ? 32'd1 : 32'd0, secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end
            OP_CMPULT: begin
              write_integer(rd_w, (regs_q[rs1_w] < regs_q[rs2_w]) ? 32'd1 : 32'd0, secret_q[rs1_w] | secret_q[rs2_w]);
              state_q <= ST_FETCH;
            end

            OP_BRZ, OP_BRNZ: begin
              if (secret_q[branch_rs1_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else begin
                if (((opcode_w == OP_BRZ) && (regs_q[branch_rs1_w] == 32'd0)) ||
                    ((opcode_w == OP_BRNZ) && (regs_q[branch_rs1_w] != 32'd0))) begin
                  pc_q <= instruction_pc_q + 32'd4 + signext21_words(off21_w);
                end
                state_q <= ST_FETCH;
              end
            end
            OP_JAL: begin
              write_integer(rd_w, instruction_pc_q + 32'd4, 1'b0);
              pc_q <= instruction_pc_q + 32'd4 + signext21_words(off21_w);
              state_q <= ST_FETCH;
            end
            OP_JALR: begin
              if (secret_q[rs1_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else begin
                temp_target = regs_q[rs1_w] + sext16(imm16_w);
                if (temp_target[1:0] != 2'b00) begin
                  fault({16'd0, CAUSE_INSTRUCTION_ALIGNMENT}, temp_target);
                end else begin
                  write_integer(rd_w, instruction_pc_q + 32'd4, 1'b0);
                  pc_q <= temp_target;
                  state_q <= ST_FETCH;
                end
              end
            end
            OP_HALT: begin
              if (region_active_q) abort_region({16'd0, CAUSE_REGION_REQUIRED});
              else state_q <= ST_HALT;
            end
            OP_TRAP: begin
              fault({16'd0, CAUSE_EXPLICIT_TRAP}, {16'd0, imm16_w});
            end
            OP_CSRR: begin
              write_integer(rd_w, csr_read(imm16_w), 1'b0);
              state_q <= ST_FETCH;
            end
            OP_CSRW: begin
              if (region_active_q) begin
                abort_region({16'd0, CAUSE_REGION_REQUIRED});
              end else if (secret_q[rs1_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else begin
                case (imm16_w)
                  CSR_VSTATUS: interrupt_enable_q <= regs_q[rs1_w][0];
                  CSR_VTVEC: begin
                    if (regs_q[rs1_w][1:0] != 2'b00)
                      fault({16'd0, CAUSE_INSTRUCTION_ALIGNMENT}, regs_q[rs1_w]);
                    else
                      vtvec_q <= regs_q[rs1_w];
                  end
                  CSR_VEPC: vepc_q <= regs_q[rs1_w];
                  CSR_VERROR: verror_q <= regs_q[rs1_w];
                  default: ;
                endcase
                if (!((imm16_w == CSR_VTVEC) && (regs_q[rs1_w][1:0] != 2'b00))) state_q <= ST_FETCH;
              end
            end
            OP_EI: begin
              if (region_active_q) abort_region({16'd0, CAUSE_REGION_REQUIRED});
              else begin interrupt_enable_q <= 1'b1; state_q <= ST_FETCH; end
            end
            OP_DI: begin
              if (region_active_q) abort_region({16'd0, CAUSE_REGION_REQUIRED});
              else begin interrupt_enable_q <= 1'b0; state_q <= ST_FETCH; end
            end
            OP_VRET: begin
              if (region_active_q) begin
                abort_region({16'd0, CAUSE_REGION_REQUIRED});
              end else if (vepc_q[1:0] != 2'b00) begin
                fault({16'd0, CAUSE_INSTRUCTION_ALIGNMENT}, vepc_q);
              end else begin
                pc_q <= vepc_q;
                interrupt_enable_q <= 1'b1;
                state_q <= ST_FETCH;
              end
            end

            OP_CROOT: begin
              temp_sum = {1'b0, regs_q[rs1_w]} + {1'b0, regs_q[rs2_w]};
              if (root_locked_q) begin
                fault({16'd0, CAUSE_ROOT_LOCKED}, 32'd0);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else if ((regs_q[rs2_w] == 32'd0) || temp_sum[32] || (temp_sum[31:0] > DATA_MEMORY_BYTES)) begin
                fault({16'd0, CAUSE_CAPABILITY_BOUNDS}, regs_q[rs1_w]);
              end else begin
                write_capability(rd_w, regs_q[rs1_w], regs_q[rs1_w], temp_sum[31:0], aux_w[4:0]);
                state_q <= ST_FETCH;
              end
            end
            OP_CBOUNDS: begin
              temp_sum = {1'b0, regs_q[rs1_w]} + {1'b0, regs_q[rs2_w]};
              if (!cap_valid_q[rs1_w]) begin
                fault({16'd0, CAUSE_CAPABILITY_TAG}, 32'd0);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else if (temp_sum[32] || (regs_q[rs1_w] < cap_base_q[rs1_w]) || (temp_sum[31:0] > cap_top_q[rs1_w])) begin
                fault({16'd0, CAUSE_CAPABILITY_BOUNDS}, regs_q[rs1_w]);
              end else begin
                write_capability(rd_w, regs_q[rs1_w], regs_q[rs1_w], temp_sum[31:0], cap_perm_q[rs1_w]);
                state_q <= ST_FETCH;
              end
            end
            OP_CPERM: begin
              if (!cap_valid_q[rs1_w]) begin
                fault({16'd0, CAUSE_CAPABILITY_TAG}, 32'd0);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else begin
                write_capability(rd_w, regs_q[rs1_w], cap_base_q[rs1_w], cap_top_q[rs1_w], cap_perm_q[rs1_w] & regs_q[rs2_w][4:0]);
                state_q <= ST_FETCH;
              end
            end
            OP_CINC: begin
              // CINC uses a signed two's-complement register offset.  The
              // wrapped 32-bit cursor is checked against the monotonic bounds;
              // positive overflow therefore falls below base and negative
              // underflow falls above top.
              temp_cursor = regs_q[rs1_w] + regs_q[rs2_w];
              if (!cap_valid_q[rs1_w]) begin
                fault({16'd0, CAUSE_CAPABILITY_TAG}, 32'd0);
              end else if (secret_q[rs1_w] || secret_q[rs2_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else if ((temp_cursor < cap_base_q[rs1_w]) || (temp_cursor > cap_top_q[rs1_w])) begin
                fault({16'd0, CAUSE_CAPABILITY_BOUNDS}, temp_cursor);
              end else begin
                write_capability(rd_w, temp_cursor, cap_base_q[rs1_w], cap_top_q[rs1_w], cap_perm_q[rs1_w]);
                state_q <= ST_FETCH;
              end
            end
            OP_CGETTAG: begin
              write_integer(rd_w, cap_valid_q[rs1_w] ? 32'd1 : 32'd0, 1'b0);
              state_q <= ST_FETCH;
            end
            OP_CGETPERM: begin
              write_integer(rd_w, cap_valid_q[rs1_w] ? {27'd0, cap_perm_q[rs1_w]} : 32'd0, 1'b0);
              state_q <= ST_FETCH;
            end

            OP_CLDB, OP_CLDBU, OP_CLDH, OP_CLDHU, OP_CLDW,
            OP_CSTB, OP_CSTH, OP_CSTW: begin
              if ((opcode_w == OP_CLDB) || (opcode_w == OP_CLDBU) || (opcode_w == OP_CSTB)) temp_size = 2'd0;
              else if ((opcode_w == OP_CLDH) || (opcode_w == OP_CLDHU) || (opcode_w == OP_CSTH)) temp_size = 2'd1;
              else temp_size = 2'd2;

              temp_sum = {1'b0, regs_q[rs1_w]} + {{17{imm16_w[15]}}, imm16_w};
              temp_address = temp_sum[31:0];
              if (temp_size == 2'd0) temp_end = temp_address + 32'd1;
              else if (temp_size == 2'd1) temp_end = temp_address + 32'd2;
              else temp_end = temp_address + 32'd4;

              if (secret_q[rs1_w]) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, 32'd0);
              end else if (!cap_valid_q[rs1_w]) begin
                fault({16'd0, CAUSE_CAPABILITY_TAG}, temp_address);
              end else if (((opcode_w <= OP_CLDW) && ((cap_perm_q[rs1_w] & CAP_R) == 0)) ||
                           ((opcode_w >= OP_CSTB) && ((cap_perm_q[rs1_w] & CAP_W) == 0))) begin
                fault({16'd0, CAUSE_CAPABILITY_PERMISSION}, temp_address);
              end else if (temp_sum[32] || (temp_address < cap_base_q[rs1_w]) || (temp_end > cap_top_q[rs1_w]) ||
                           (temp_end > DATA_MEMORY_BYTES)) begin
                fault({16'd0, CAUSE_CAPABILITY_BOUNDS}, temp_address);
              end else if (((temp_size == 2'd1) && temp_address[0]) || ((temp_size == 2'd2) && (temp_address[1:0] != 2'b00))) begin
                fault({16'd0, CAUSE_DATA_ALIGNMENT}, temp_address);
              end else if ((opcode_w >= OP_CSTB) && secret_q[rd_w] && ((cap_perm_q[rs1_w] & CAP_S) == 0)) begin
                fault({16'd0, CAUSE_SECRET_FLOW}, temp_address);
              end else if (opcode_w <= OP_CLDW) begin
                mem_rd_q <= rd_w;
                mem_addr_q <= temp_address;
                mem_size_q <= temp_size;
                mem_signed_q <= (opcode_w == OP_CLDB) || (opcode_w == OP_CLDH);
                mem_secret_q <= ((cap_perm_q[rs1_w] & CAP_S) != 0);
                state_q <= ST_LOAD;
              end else begin
                temp_strb = store_strobe(temp_size, temp_address[1:0]);
                temp_store_data = store_data(regs_q[rd_w], temp_size, temp_address[1:0]);
                if (region_active_q) begin
                  if ((sb_count_q >= region_store_quota_q) || (sb_count_q >= STORE_BUFFER_DEPTH)) begin
                    abort_region({16'd0, CAUSE_REGION_STORE_QUOTA});
                  end else begin
                    sb_addr_q[sb_count_q] <= {temp_address[31:2], 2'b00};
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
              if (!cap_valid_q[rs2_w] || ((cap_perm_q[rs2_w] & CAP_D) == 0)) begin
                fault({16'd0, CAUSE_DECLASSIFY_DENIED}, 32'd0);
              end else begin
                write_integer(rd_w, regs_q[rs1_w], 1'b0);
                state_q <= ST_FETCH;
              end
            end
            OP_VLOCK: begin
              if (region_active_q) abort_region({16'd0, CAUSE_REGION_REQUIRED});
              else begin root_locked_q <= 1'b1; state_q <= ST_FETCH; end
            end

            OP_VTRY: begin
              if (region_active_q) begin
                abort_region({16'd0, CAUSE_REGION_NESTED});
              end else if ((vtry_stores_w == 5'd0) || (vtry_stores_w > STORE_BUFFER_DEPTH) || (vtry_budget_w == 8'd0)) begin
                fault({16'd0, CAUSE_REGION_STORE_QUOTA}, 32'd0);
              end else begin
                region_active_q <= 1'b1;
                region_fail_pc_q <= instruction_pc_q + 32'd4 + signext13_words(vtry_off13_w);
                region_store_quota_q <= vtry_stores_w;
                region_budget_q <= vtry_budget_w;
                region_used_q <= 8'd0;
                sb_count_q <= 6'd0;
                verror_q <= 32'd0;
                state_q <= ST_FETCH;
              end
            end
            OP_VCHK: begin
              if (!region_active_q) begin
                fault({16'd0, CAUSE_REGION_REQUIRED}, 32'd0);
              end else if (secret_q[rs1_w]) begin
                abort_region({16'd0, CAUSE_SECRET_FLOW});
              end else if (regs_q[rs1_w] == 32'd0) begin
                abort_region((imm16_w == 16'd0) ? {16'd0, CAUSE_EXPLICIT_TRAP} : {16'd0, imm16_w});
              end else begin
                state_q <= ST_FETCH;
              end
            end
            OP_VIC: begin
              if (!region_active_q) begin
                fault({16'd0, CAUSE_REGION_REQUIRED}, 32'd0);
              end else if (sb_count_q == 0) begin
                region_active_q <= 1'b0;
                region_store_quota_q <= 5'd0;
                region_budget_q <= 8'd0;
                region_used_q <= 8'd0;
                verror_q <= 32'd0;
                state_q <= ST_FETCH;
              end else begin
                commit_index_q <= 6'd0;
                state_q <= ST_COMMIT;
              end
            end
            OP_VABT: begin
              if (!region_active_q) fault({16'd0, CAUSE_REGION_REQUIRED}, 32'd0);
              else abort_region((imm16_w == 16'd0) ? {16'd0, CAUSE_EXPLICIT_TRAP} : {16'd0, imm16_w});
            end
            OP_VERR: begin
              write_integer(rd_w, verror_q, 1'b0);
              state_q <= ST_FETCH;
            end
            OP_WFI: begin
              if (region_active_q) abort_region({16'd0, CAUSE_REGION_REQUIRED});
              else state_q <= ST_WFI;
            end

            default: fault({16'd0, CAUSE_ILLEGAL_INSTRUCTION}, instruction_q);
          endcase
        end

        ST_LOAD: begin
          if (dmem_ready_i) begin
            temp_word = forwarded_word(dmem_rdata_i, {mem_addr_q[31:2], 2'b00});
            case (mem_size_q)
              2'd0: begin
                case (mem_addr_q[1:0])
                  2'd0: temp_value = mem_signed_q ? sext8(temp_word[7:0]) : {24'd0, temp_word[7:0]};
                  2'd1: temp_value = mem_signed_q ? sext8(temp_word[15:8]) : {24'd0, temp_word[15:8]};
                  2'd2: temp_value = mem_signed_q ? sext8(temp_word[23:16]) : {24'd0, temp_word[23:16]};
                  default: temp_value = mem_signed_q ? sext8(temp_word[31:24]) : {24'd0, temp_word[31:24]};
                endcase
              end
              2'd1: begin
                if (mem_addr_q[1]) temp_value = mem_signed_q ? sext_half(temp_word[31:16]) : {16'd0, temp_word[31:16]};
                else temp_value = mem_signed_q ? sext_half(temp_word[15:0]) : {16'd0, temp_word[15:0]};
              end
              default: temp_value = temp_word;
            endcase
            write_integer(mem_rd_q, temp_value, mem_secret_q);
            state_q <= ST_FETCH;
          end
        end

        ST_STORE: begin
          if (dmem_ready_i) state_q <= ST_FETCH;
        end

        ST_COMMIT: begin
          if (dmem_ready_i) begin
            if (commit_index_q + 6'd1 >= sb_count_q) begin
              region_active_q <= 1'b0;
              region_store_quota_q <= 5'd0;
              region_budget_q <= 8'd0;
              region_used_q <= 8'd0;
              sb_count_q <= 6'd0;
              commit_index_q <= 6'd0;
              verror_q <= 32'd0;
              state_q <= ST_FETCH;
            end else begin
              commit_index_q <= commit_index_q + 6'd1;
            end
          end
        end

        ST_WFI: begin
          if (irq_i) begin
            if (interrupt_enable_q) begin
              instruction_pc_q <= pc_q;
              vcause_q <= {16'd0, CAUSE_INTERRUPT};
              vbadaddr_q <= 32'd0;
              vepc_q <= pc_q;
              interrupt_enable_q <= 1'b0;
              pc_q <= vtvec_q;
            end
            state_q <= ST_FETCH;
          end
        end

        default: state_q <= ST_HALT;
      endcase

      regs_q[0] <= 32'd0;
      cap_valid_q[0] <= 1'b0;
      cap_base_q[0] <= 32'd0;
      cap_top_q[0] <= 32'd0;
      cap_perm_q[0] <= 5'd0;
      secret_q[0] <= 1'b0;
    end
  end
endmodule
