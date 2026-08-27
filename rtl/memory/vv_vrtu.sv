`timescale 1ns/1ps

module vv_vrtu #(
  parameter integer ENTRY_COUNT = 4,
  parameter integer INDEX_BITS = (ENTRY_COUNT <= 1) ? 1 : $clog2(ENTRY_COUNT),
  parameter integer PHYS_ADDR_BITS = 17,
  parameter bit LOCK_ON_RESET = 1'b1,
  parameter logic [63:0] RAM_TOP = 64'h0000_0000_0001_0000,
  parameter logic [63:0] ROOT_TOP = 64'h0000_0000_0002_0000
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  input  logic                    cfg_we_i,
  input  logic [INDEX_BITS-1:0]   cfg_index_i,
  input  logic                    cfg_valid_i,
  input  logic [63:0]             cfg_vbase_i,
  input  logic [63:0]             cfg_vtop_i,
  input  logic [63:0]             cfg_pbase_i,
  input  logic [4:0]              cfg_perm_i,
  input  logic                    cfg_require_parent_i,
  input  logic                    cfg_parent_valid_i,
  input  logic [63:0]             cfg_parent_base_i,
  input  logic [63:0]             cfg_parent_top_i,
  input  logic [4:0]              cfg_parent_perm_i,
  input  logic                    cfg_lock_i,
  output logic                    locked_o,
  output logic                    cfg_error_o,
  output logic [15:0]             cfg_cause_o,

  input  logic                    imem_req_i,
  input  logic [63:0]             imem_vaddr_i,
  input  logic                    imem_user_i,
  output logic [63:0]             imem_paddr_o,
  output logic                    imem_fault_o,
  output logic [15:0]             imem_cause_o,

  input  logic                    dmem_req_i,
  input  logic                    dmem_write_i,
  input  logic                    dmem_user_i,
  input  logic                    dmem_region_i,
  input  logic [3:0]              dmem_size_i,
  input  logic [63:0]             dmem_vaddr_i,
  output logic [63:0]             dmem_paddr_o,
  output logic                    dmem_fault_o,
  output logic [15:0]             dmem_cause_o,
  output logic                    dmem_device_o
);
  localparam logic [4:0] PERM_R = 5'b0_0001;
  localparam logic [4:0] PERM_W = 5'b0_0010;
  localparam logic [4:0] PERM_X = 5'b0_0100;
  localparam logic [4:0] PERM_U = 5'b0_1000;
  localparam logic [4:0] PERM_DEVICE = 5'b1_0000;

  localparam logic [15:0] CAUSE_VRTU_MISS          = 16'd20;
  localparam logic [15:0] CAUSE_VRTU_PERMISSION    = 16'd21;
  localparam logic [15:0] CAUSE_VRTU_CONFLICT      = 16'd22;
  localparam logic [15:0] CAUSE_REGION_DEVICE      = 16'd27;
  localparam logic [15:0] CAUSE_CAPABILITY_GENERATION_WRAP = 16'd30;
  localparam logic [15:0] CAUSE_VRTU_CONFIGURATION = 16'd31;
  localparam logic [63:0] PHYS_LIMIT = (64'd1 << PHYS_ADDR_BITS);

  logic                  entry_valid_q [0:ENTRY_COUNT-1];
  logic [31:0]           entry_generation_q [0:ENTRY_COUNT-1];
  logic [63:0]           entry_vbase_q [0:ENTRY_COUNT-1];
  logic [63:0]           entry_vtop_q [0:ENTRY_COUNT-1];
  logic [63:0]           entry_pbase_q [0:ENTRY_COUNT-1];
  logic [4:0]            entry_perm_q [0:ENTRY_COUNT-1];
  logic                  locked_q;
  logic                  cfg_error_q;
  logic [15:0]           cfg_cause_q;

  logic                  ig_valid_q;
  logic [INDEX_BITS-1:0] ig_index_q;
  logic [31:0]           ig_generation_q;
  logic [63:0]           ig_vbase_q;
  logic [63:0]           ig_vtop_q;
  logic [63:0]           ig_pbase_q;
  logic [4:0]            ig_perm_q;

  logic                  dg_valid_q;
  logic [INDEX_BITS-1:0] dg_index_q;
  logic [31:0]           dg_generation_q;
  logic [63:0]           dg_vbase_q;
  logic [63:0]           dg_vtop_q;
  logic [63:0]           dg_pbase_q;
  logic [4:0]            dg_perm_q;

  logic                  i_select_valid;
  logic [INDEX_BITS-1:0] i_select_index;
  logic [31:0]           i_select_generation;
  logic [63:0]           i_select_vbase;
  logic [63:0]           i_select_vtop;
  logic [63:0]           i_select_pbase;
  logic [4:0]            i_select_perm;

  logic                  d_select_valid;
  logic [INDEX_BITS-1:0] d_select_index;
  logic [31:0]           d_select_generation;
  logic [63:0]           d_select_vbase;
  logic [63:0]           d_select_vtop;
  logic [63:0]           d_select_pbase;
  logic [4:0]            d_select_perm;

  integer scan_i;
  integer reset_i;
  integer cfg_i;
  integer i_matches;
  integer d_matches;
  logic [63:0] i_end;
  logic [63:0] d_end;
  logic [63:0] i_candidate;
  logic [63:0] d_candidate;
  logic [4:0] i_required_perm;
  logic [4:0] d_required_perm;
  logic i_guard_hit;
  logic d_guard_hit;

  logic cfg_reject;
  logic [15:0] cfg_reject_cause;
  logic [64:0] cfg_length;
  logic [64:0] cfg_phys_end;

  assign locked_o = locked_q;
  assign cfg_error_o = cfg_error_q;
  assign cfg_cause_o = cfg_cause_q;

  always_comb begin
    cfg_reject = 1'b0;
    cfg_reject_cause = 16'd0;
    cfg_length = 65'd0;
    cfg_phys_end = 65'd0;

    if (cfg_we_i && !locked_q) begin
      if (cfg_index_i >= ENTRY_COUNT) begin
        cfg_reject = 1'b1;
        cfg_reject_cause = CAUSE_VRTU_CONFIGURATION;
      end else if (entry_generation_q[cfg_index_i] == 32'hffff_ffff) begin
        cfg_reject = 1'b1;
        cfg_reject_cause = CAUSE_CAPABILITY_GENERATION_WRAP;
      end else if (cfg_valid_i) begin
        cfg_length = {1'b0, cfg_vtop_i} - {1'b0, cfg_vbase_i};
        cfg_phys_end = {1'b0, cfg_pbase_i} + cfg_length;
        if (cfg_vtop_i <= cfg_vbase_i || cfg_length[64] || cfg_phys_end[64] ||
            cfg_phys_end[63:0] > PHYS_LIMIT) begin
          cfg_reject = 1'b1;
          cfg_reject_cause = CAUSE_VRTU_CONFIGURATION;
        end else if (((cfg_perm_i & PERM_W) != 0) && ((cfg_perm_i & PERM_X) != 0)) begin
          cfg_reject = 1'b1;
          cfg_reject_cause = CAUSE_VRTU_CONFIGURATION;
        end else if (((cfg_perm_i & PERM_DEVICE) != 0) && ((cfg_perm_i & PERM_X) != 0)) begin
          cfg_reject = 1'b1;
          cfg_reject_cause = CAUSE_VRTU_CONFIGURATION;
        end else if (cfg_require_parent_i &&
                     (!cfg_parent_valid_i ||
                      cfg_pbase_i < cfg_parent_base_i ||
                      cfg_phys_end[63:0] > cfg_parent_top_i ||
                      ((cfg_perm_i & ~cfg_parent_perm_i) != 0))) begin
          cfg_reject = 1'b1;
          cfg_reject_cause = CAUSE_VRTU_CONFIGURATION;
        end else begin
          for (cfg_i = 0; cfg_i < ENTRY_COUNT; cfg_i = cfg_i + 1) begin
            if ((cfg_i != cfg_index_i) && entry_valid_q[cfg_i] &&
                (cfg_vbase_i < entry_vtop_q[cfg_i]) &&
                (entry_vbase_q[cfg_i] < cfg_vtop_i)) begin
              cfg_reject = 1'b1;
              cfg_reject_cause = CAUSE_VRTU_CONFLICT;
            end
          end
        end
      end
    end
  end

  always_comb begin
    i_end = imem_vaddr_i + 64'd4;
    d_end = dmem_vaddr_i + {60'd0, dmem_size_i};
    i_required_perm = PERM_X;
    d_required_perm = dmem_write_i ? PERM_W : PERM_R;

    imem_paddr_o = 64'd0;
    imem_fault_o = 1'b0;
    imem_cause_o = 16'd0;
    i_select_valid = 1'b0;
    i_select_index = '0;
    i_select_generation = 32'd0;
    i_select_vbase = 64'd0;
    i_select_vtop = 64'd0;
    i_select_pbase = 64'd0;
    i_select_perm = 5'd0;
    i_matches = 0;
    i_guard_hit = 1'b0;
    i_candidate = 64'd0;

    if (imem_req_i) begin
      if (ig_valid_q &&
          entry_valid_q[ig_index_q] &&
          entry_generation_q[ig_index_q] == ig_generation_q &&
          imem_vaddr_i >= ig_vbase_q &&
          i_end >= imem_vaddr_i &&
          i_end <= ig_vtop_q) begin
        i_guard_hit = 1'b1;
        i_select_valid = 1'b1;
        i_select_index = ig_index_q;
        i_select_generation = ig_generation_q;
        i_select_vbase = ig_vbase_q;
        i_select_vtop = ig_vtop_q;
        i_select_pbase = ig_pbase_q;
        i_select_perm = ig_perm_q;
      end else begin
        for (scan_i = 0; scan_i < ENTRY_COUNT; scan_i = scan_i + 1) begin
          if (entry_valid_q[scan_i] &&
              imem_vaddr_i >= entry_vbase_q[scan_i] &&
              i_end >= imem_vaddr_i &&
              i_end <= entry_vtop_q[scan_i]) begin
            i_matches = i_matches + 1;
            i_select_valid = 1'b1;
            i_select_index = scan_i[INDEX_BITS-1:0];
            i_select_generation = entry_generation_q[scan_i];
            i_select_vbase = entry_vbase_q[scan_i];
            i_select_vtop = entry_vtop_q[scan_i];
            i_select_pbase = entry_pbase_q[scan_i];
            i_select_perm = entry_perm_q[scan_i];
          end
        end
      end

      if (!i_guard_hit && i_matches == 0) begin
        imem_fault_o = 1'b1;
        imem_cause_o = CAUSE_VRTU_MISS;
      end else if (!i_guard_hit && i_matches > 1) begin
        imem_fault_o = 1'b1;
        imem_cause_o = CAUSE_VRTU_CONFLICT;
      end else if ((i_select_perm & i_required_perm) == 0 ||
                   (imem_user_i && (i_select_perm & PERM_U) == 0)) begin
        imem_fault_o = 1'b1;
        imem_cause_o = CAUSE_VRTU_PERMISSION;
      end else begin
        i_candidate = i_select_pbase + (imem_vaddr_i - i_select_vbase);
        if (i_candidate + 64'd4 > PHYS_LIMIT || i_candidate + 64'd4 < i_candidate) begin
          imem_fault_o = 1'b1;
          imem_cause_o = CAUSE_VRTU_MISS;
        end else begin
          imem_paddr_o = i_candidate;
        end
      end
    end

    dmem_paddr_o = 64'd0;
    dmem_fault_o = 1'b0;
    dmem_cause_o = 16'd0;
    dmem_device_o = 1'b0;
    d_select_valid = 1'b0;
    d_select_index = '0;
    d_select_generation = 32'd0;
    d_select_vbase = 64'd0;
    d_select_vtop = 64'd0;
    d_select_pbase = 64'd0;
    d_select_perm = 5'd0;
    d_matches = 0;
    d_guard_hit = 1'b0;
    d_candidate = 64'd0;

    if (dmem_req_i) begin
      if (dmem_size_i == 0) begin
        dmem_fault_o = 1'b1;
        dmem_cause_o = CAUSE_VRTU_MISS;
      end else begin
        if (dg_valid_q &&
            entry_valid_q[dg_index_q] &&
            entry_generation_q[dg_index_q] == dg_generation_q &&
            dmem_vaddr_i >= dg_vbase_q &&
            d_end >= dmem_vaddr_i &&
            d_end <= dg_vtop_q) begin
          d_guard_hit = 1'b1;
          d_select_valid = 1'b1;
          d_select_index = dg_index_q;
          d_select_generation = dg_generation_q;
          d_select_vbase = dg_vbase_q;
          d_select_vtop = dg_vtop_q;
          d_select_pbase = dg_pbase_q;
          d_select_perm = dg_perm_q;
        end else begin
          for (scan_i = 0; scan_i < ENTRY_COUNT; scan_i = scan_i + 1) begin
            if (entry_valid_q[scan_i] &&
                dmem_vaddr_i >= entry_vbase_q[scan_i] &&
                d_end >= dmem_vaddr_i &&
                d_end <= entry_vtop_q[scan_i]) begin
              d_matches = d_matches + 1;
              d_select_valid = 1'b1;
              d_select_index = scan_i[INDEX_BITS-1:0];
              d_select_generation = entry_generation_q[scan_i];
              d_select_vbase = entry_vbase_q[scan_i];
              d_select_vtop = entry_vtop_q[scan_i];
              d_select_pbase = entry_pbase_q[scan_i];
              d_select_perm = entry_perm_q[scan_i];
            end
          end
        end

        dmem_device_o = d_select_valid && ((d_select_perm & PERM_DEVICE) != 0);
        if (!d_guard_hit && d_matches == 0) begin
          dmem_fault_o = 1'b1;
          dmem_cause_o = CAUSE_VRTU_MISS;
        end else if (!d_guard_hit && d_matches > 1) begin
          dmem_fault_o = 1'b1;
          dmem_cause_o = CAUSE_VRTU_CONFLICT;
        end else if ((d_select_perm & d_required_perm) == 0 ||
                     (dmem_user_i && (d_select_perm & PERM_U) == 0)) begin
          dmem_fault_o = 1'b1;
          dmem_cause_o = CAUSE_VRTU_PERMISSION;
        end else if (dmem_region_i && ((d_select_perm & PERM_DEVICE) != 0)) begin
          dmem_fault_o = 1'b1;
          dmem_cause_o = CAUSE_REGION_DEVICE;
        end else begin
          d_candidate = d_select_pbase + (dmem_vaddr_i - d_select_vbase);
          if (d_candidate + {60'd0, dmem_size_i} > PHYS_LIMIT ||
              d_candidate + {60'd0, dmem_size_i} < d_candidate) begin
            dmem_fault_o = 1'b1;
            dmem_cause_o = CAUSE_VRTU_MISS;
          end else begin
            dmem_paddr_o = d_candidate;
          end
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      locked_q <= LOCK_ON_RESET;
      cfg_error_q <= 1'b0;
      cfg_cause_q <= 16'd0;
      ig_valid_q <= 1'b0;
      dg_valid_q <= 1'b0;
      ig_index_q <= '0;
      dg_index_q <= '0;
      ig_generation_q <= 32'd0;
      dg_generation_q <= 32'd0;
      ig_vbase_q <= 64'd0;
      ig_vtop_q <= 64'd0;
      ig_pbase_q <= 64'd0;
      ig_perm_q <= 5'd0;
      dg_vbase_q <= 64'd0;
      dg_vtop_q <= 64'd0;
      dg_pbase_q <= 64'd0;
      dg_perm_q <= 5'd0;
      for (reset_i = 0; reset_i < ENTRY_COUNT; reset_i = reset_i + 1) begin
        entry_valid_q[reset_i] <= 1'b0;
        entry_generation_q[reset_i] <= 32'd0;
        entry_vbase_q[reset_i] <= 64'd0;
        entry_vtop_q[reset_i] <= 64'd0;
        entry_pbase_q[reset_i] <= 64'd0;
        entry_perm_q[reset_i] <= 5'd0;
      end
      if (ENTRY_COUNT > 0) begin
        entry_valid_q[0] <= 1'b1;
        entry_generation_q[0] <= 32'd1;
        entry_vbase_q[0] <= 64'd0;
        entry_vtop_q[0] <= RAM_TOP;
        entry_pbase_q[0] <= 64'd0;
        // A0 keeps one locked bootstrap RWX descriptor because E0 has two
        // entries. Runtime descriptor writes remain W^X.
        entry_perm_q[0] <= PERM_R | PERM_W | PERM_X | PERM_U;
      end
      if (ENTRY_COUNT > 1) begin
        entry_valid_q[1] <= 1'b1;
        entry_generation_q[1] <= 32'd1;
        entry_vbase_q[1] <= RAM_TOP;
        entry_vtop_q[1] <= ROOT_TOP;
        entry_pbase_q[1] <= RAM_TOP;
        entry_perm_q[1] <= PERM_R | PERM_W | PERM_DEVICE;
      end
    end else begin
      cfg_error_q <= 1'b0;
      cfg_cause_q <= 16'd0;

      if (cfg_lock_i)
        locked_q <= 1'b1;

      if (cfg_we_i && !locked_q) begin
        if (cfg_reject) begin
          cfg_error_q <= 1'b1;
          cfg_cause_q <= cfg_reject_cause;
        end else begin
          entry_valid_q[cfg_index_i] <= cfg_valid_i;
          entry_generation_q[cfg_index_i] <= entry_generation_q[cfg_index_i] + 32'd1;
          entry_vbase_q[cfg_index_i] <= cfg_vbase_i;
          entry_vtop_q[cfg_index_i] <= cfg_vtop_i;
          entry_pbase_q[cfg_index_i] <= cfg_pbase_i;
          entry_perm_q[cfg_index_i] <= cfg_perm_i;
          ig_valid_q <= 1'b0;
          dg_valid_q <= 1'b0;
        end
      end else begin
        if (imem_req_i && !imem_fault_o && i_select_valid) begin
          ig_valid_q <= 1'b1;
          ig_index_q <= i_select_index;
          ig_generation_q <= i_select_generation;
          ig_vbase_q <= i_select_vbase;
          ig_vtop_q <= i_select_vtop;
          ig_pbase_q <= i_select_pbase;
          ig_perm_q <= i_select_perm;
        end
        if (dmem_req_i && !dmem_fault_o && d_select_valid) begin
          dg_valid_q <= 1'b1;
          dg_index_q <= d_select_index;
          dg_generation_q <= d_select_generation;
          dg_vbase_q <= d_select_vbase;
          dg_vtop_q <= d_select_vtop;
          dg_pbase_q <= d_select_pbase;
          dg_perm_q <= d_select_perm;
        end
      end
    end
  end
endmodule
