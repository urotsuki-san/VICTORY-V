`timescale 1ns/1ps

// Euclid-A0 bring-up engine.
//
// The seed changes the coordinate order only. A candidate is dropped once its
// accumulated squared distance cannot beat an already completed candidate.
// The accepted winner is therefore exact even when some later coordinates are
// never visited.
module vv_euclid_a0 (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        req_i,
  input  logic        we_i,
  input  logic [7:0]  addr_i,
  input  logic [63:0] wdata_i,
  input  logic [7:0]  wstrb_i,
  input  logic [1:0]  source_i,
  output logic [63:0] rdata_o,
  output logic        ready_o,

  output logic        busy_o,
  output logic        done_o,
  output logic        exact_o,
  output logic        atlas_hit_o,
  output logic [1:0]  winner_o
);
  localparam logic [7:0] REG_CONTROL = 8'h00;
  localparam logic [7:0] REG_STATUS  = 8'h08;
  localparam logic [7:0] REG_QUERY   = 8'h10;
  localparam logic [7:0] REG_POINT0  = 8'h18;
  localparam logic [7:0] REG_POINT1  = 8'h20;
  localparam logic [7:0] REG_POINT2  = 8'h28;
  localparam logic [7:0] REG_POINT3  = 8'h30;
  localparam logic [7:0] REG_RESULT  = 8'h38;
  localparam logic [7:0] REG_STATS   = 8'h40;
  localparam logic [7:0] REG_ATLAS   = 8'h48;
  localparam logic [7:0] REG_ID      = 8'h50;

  localparam logic [1:0] ST_IDLE   = 2'd0;
  localparam logic [1:0] ST_CALC   = 2'd1;
  localparam logic [1:0] ST_FINISH = 2'd2;

  logic [1:0] state_q;

  logic [63:0] query_q;
  logic [63:0] point_q [0:3];
  logic [2:0]  dims_m1_q;
  logic [3:0]  valid_mask_q;
  logic [7:0]  seed_q;
  logic [1:0]  owner_q;

  logic [1:0]  candidate_q;
  logic [2:0]  axis_q;
  logic [3:0]  term_count_q;
  logic [19:0] partial_q;
  logic [19:0] lower_q [0:3];
  logic [19:0] best_distance_q;
  logic        best_valid_q;
  logic [1:0]  winner_q;

  logic [15:0] jobs_q;
  logic [15:0] atlas_hits_q;
  logic [15:0] visited_terms_q;
  logic [15:0] skipped_terms_q;
  logic [15:0] decision_cycles_q;

  logic busy_q;
  logic done_q;
  logic exact_q;
  logic atlas_hit_q;
  logic error_q;

  logic        atlas_valid_q;
  logic [63:0] atlas_query_q;
  logic [63:0] atlas_point_q [0:3];
  logic [2:0]  atlas_dims_m1_q;
  logic [3:0]  atlas_valid_mask_q;
  logic [1:0]  atlas_winner_q;
  logic [5:0]  atlas_radius_q;

  logic [63:0] control_read;
  logic [63:0] control_write;
  logic [2:0]  start_dims_m1;
  logic [3:0]  start_valid_mask;
  logic [7:0]  start_seed;

  logic atlas_match;
  logic [5:0] radius_0;
  logic [5:0] radius_1;
  logic [5:0] radius_2;
  logic [5:0] radius_3;
  logic [5:0] atlas_radius_next;

  logic signed [8:0] delta_now;
  logic [8:0]  abs_delta_now;
  logic [17:0] square_now;
  logic [19:0] next_partial;

  function automatic logic [63:0] merge64(
    input logic [63:0] old_value,
    input logic [63:0] new_value,
    input logic [7:0] strobe
  );
    integer byte_index;
    begin
      merge64 = old_value;
      for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
        if (strobe[byte_index])
          merge64[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
    end
  endfunction

  function automatic logic signed [7:0] coord(
    input logic [63:0] packed_point,
    input logic [2:0] axis
  );
    begin
      case (axis)
        3'd0: coord = $signed(packed_point[7:0]);
        3'd1: coord = $signed(packed_point[15:8]);
        3'd2: coord = $signed(packed_point[23:16]);
        3'd3: coord = $signed(packed_point[31:24]);
        3'd4: coord = $signed(packed_point[39:32]);
        3'd5: coord = $signed(packed_point[47:40]);
        3'd6: coord = $signed(packed_point[55:48]);
        default: coord = $signed(packed_point[63:56]);
      endcase
    end
  endfunction

  function automatic logic [8:0] abs_delta(
    input logic [63:0] left_point,
    input logic [63:0] right_point,
    input logic [2:0] axis
  );
    logic signed [8:0] delta;
    begin
      delta = $signed(coord(left_point, axis)) - $signed(coord(right_point, axis));
      abs_delta = delta[8] ? $unsigned(-delta) : $unsigned(delta);
    end
  endfunction

  function automatic logic [11:0] point_l1(
    input logic [63:0] left_point,
    input logic [63:0] right_point,
    input logic [2:0] dims_m1
  );
    integer axis;
    logic [11:0] total;
    begin
      total = 12'd0;
      for (axis = 0; axis < 8; axis = axis + 1)
        if (axis <= dims_m1)
          total = total + abs_delta(left_point, right_point, axis[2:0]);
      point_l1 = total;
    end
  endfunction

  function automatic logic inside_radius(
    input logic [63:0] point,
    input logic [63:0] center,
    input logic [2:0] dims_m1,
    input logic [5:0] radius
  );
    integer axis;
    logic ok;
    begin
      ok = 1'b1;
      for (axis = 0; axis < 8; axis = axis + 1)
        if ((axis <= dims_m1) && (abs_delta(point, center, axis[2:0]) > {3'd0, radius}))
          ok = 1'b0;
      inside_radius = ok;
    end
  endfunction

  // The difference between two squared distances is affine in the query.
  // For an L-infinity movement r, its magnitude can change by at most
  // 2*r*L1(winner-rival). The power-of-two choices below deliberately round
  // the reusable region inward.
  function automatic logic [5:0] safe_radius(
    input logic [19:0] margin,
    input logic [11:0] l1
  );
    logic [24:0] scaled;
    begin
      scaled = {13'd0, l1};
      if (l1 == 12'd0)                            safe_radius = 6'd31;
      else if ({5'd0, margin} > (scaled << 5))   safe_radius = 6'd16;
      else if ({5'd0, margin} > (scaled << 4))   safe_radius = 6'd8;
      else if ({5'd0, margin} > (scaled << 3))   safe_radius = 6'd4;
      else if ({5'd0, margin} > (scaled << 2))   safe_radius = 6'd2;
      else if ({5'd0, margin} > (scaled << 1))   safe_radius = 6'd1;
      else                                        safe_radius = 6'd0;
    end
  endfunction

  function automatic logic [5:0] face_radius(
    input logic        rival_valid,
    input logic [1:0]  rival_index,
    input logic [1:0]  selected_index,
    input logic [19:0] rival_lower,
    input logic [19:0] selected_distance,
    input logic [63:0] selected_point,
    input logic [63:0] rival_point,
    input logic [2:0]  dims_m1
  );
    logic [11:0] l1;
    logic [19:0] margin;
    begin
      if (!rival_valid || (rival_index == selected_index)) begin
        face_radius = 6'd31;
      end else begin
        l1 = point_l1(selected_point, rival_point, dims_m1);
        margin = (rival_lower >= selected_distance) ?
                 (rival_lower - selected_distance) : 20'd0;
        face_radius = safe_radius(margin, l1);
      end
    end
  endfunction

  function automatic logic [5:0] min6(
    input logic [5:0] a,
    input logic [5:0] b
  );
    begin
      min6 = (a < b) ? a : b;
    end
  endfunction

  // Use plain always @* here rather than always_comb. Icarus 12 widens
  // always_comb sensitivity for the variable selects in this small engine and
  // can keep reevaluating the block at time zero. Gowin accepts the same
  // combinational logic in this form.
  always @* begin
    control_read = {40'd0, seed_q, valid_mask_q, 1'b0, dims_m1_q, 7'd0};
    control_write = merge64(control_read, wdata_i, wstrb_i);
    start_dims_m1 = control_write[10:8];
    start_valid_mask = control_write[15:12];
    start_seed = control_write[23:16];

    rdata_o = 64'd0;
    case (addr_i)
      REG_CONTROL: rdata_o = control_read;
      REG_STATUS:  rdata_o = {44'd0, decision_cycles_q[7:0], owner_q, winner_q,
                              error_q, atlas_hit_q, exact_q, done_q, busy_q};
      REG_QUERY:   rdata_o = query_q;
      REG_POINT0:  rdata_o = point_q[0];
      REG_POINT1:  rdata_o = point_q[1];
      REG_POINT2:  rdata_o = point_q[2];
      REG_POINT3:  rdata_o = point_q[3];
      REG_RESULT:  rdata_o = {24'd0, best_distance_q, skipped_terms_q[7:0],
                              visited_terms_q[7:0], 2'd0, winner_q};
      REG_STATS:   rdata_o = {atlas_hits_q, jobs_q, skipped_terms_q, visited_terms_q};
      REG_ATLAS:   rdata_o = {48'd0, atlas_radius_q, 5'd0, atlas_winner_q, atlas_valid_q};
      REG_ID:      rdata_o = 64'h4555_434c_4944_4130; // "EUCLIDA0"
      default:     rdata_o = 64'd0;
    endcase
    ready_o = req_i;
  end

  always @* begin
    delta_now = $signed(coord(query_q, axis_q)) - $signed(coord(point_q[candidate_q], axis_q));
    abs_delta_now = delta_now[8] ? $unsigned(-delta_now) : $unsigned(delta_now);
    square_now = abs_delta_now * abs_delta_now;
    next_partial = partial_q + {2'd0, square_now};
  end

  always @* begin
    atlas_match = atlas_valid_q &&
                  (atlas_dims_m1_q == start_dims_m1) &&
                  (atlas_valid_mask_q == start_valid_mask) &&
                  (atlas_point_q[0] == point_q[0]) &&
                  (atlas_point_q[1] == point_q[1]) &&
                  (atlas_point_q[2] == point_q[2]) &&
                  (atlas_point_q[3] == point_q[3]) &&
                  inside_radius(query_q, atlas_query_q, start_dims_m1, atlas_radius_q) &&
                  !control_write[2];
  end

  always @* begin
    radius_0 = face_radius(valid_mask_q[0], 2'd0, winner_q, lower_q[0], best_distance_q,
                           point_q[winner_q], point_q[0], dims_m1_q);
    radius_1 = face_radius(valid_mask_q[1], 2'd1, winner_q, lower_q[1], best_distance_q,
                           point_q[winner_q], point_q[1], dims_m1_q);
    radius_2 = face_radius(valid_mask_q[2], 2'd2, winner_q, lower_q[2], best_distance_q,
                           point_q[winner_q], point_q[2], dims_m1_q);
    radius_3 = face_radius(valid_mask_q[3], 2'd3, winner_q, lower_q[3], best_distance_q,
                           point_q[winner_q], point_q[3], dims_m1_q);
    atlas_radius_next = min6(min6(radius_0, radius_1), min6(radius_2, radius_3));
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_IDLE;
      query_q <= 64'd0;
      point_q[0] <= 64'd0;
      point_q[1] <= 64'd0;
      point_q[2] <= 64'd0;
      point_q[3] <= 64'd0;
      dims_m1_q <= 3'd7;
      valid_mask_q <= 4'hf;
      seed_q <= 8'd0;
      owner_q <= 2'd0;
      candidate_q <= 2'd0;
      axis_q <= 3'd0;
      term_count_q <= 4'd0;
      partial_q <= 20'd0;
      lower_q[0] <= 20'd0;
      lower_q[1] <= 20'd0;
      lower_q[2] <= 20'd0;
      lower_q[3] <= 20'd0;
      best_distance_q <= 20'hfffff;
      best_valid_q <= 1'b0;
      winner_q <= 2'd0;
      jobs_q <= 16'd0;
      atlas_hits_q <= 16'd0;
      visited_terms_q <= 16'd0;
      skipped_terms_q <= 16'd0;
      decision_cycles_q <= 16'd0;
      busy_q <= 1'b0;
      done_q <= 1'b0;
      exact_q <= 1'b0;
      atlas_hit_q <= 1'b0;
      error_q <= 1'b0;
      atlas_valid_q <= 1'b0;
      atlas_query_q <= 64'd0;
      atlas_point_q[0] <= 64'd0;
      atlas_point_q[1] <= 64'd0;
      atlas_point_q[2] <= 64'd0;
      atlas_point_q[3] <= 64'd0;
      atlas_dims_m1_q <= 3'd0;
      atlas_valid_mask_q <= 4'd0;
      atlas_winner_q <= 2'd0;
      atlas_radius_q <= 6'd0;
    end else begin
      if (busy_q && decision_cycles_q != 16'hffff)
        decision_cycles_q <= decision_cycles_q + 16'd1;

      case (state_q)
        ST_CALC: begin
          if (!valid_mask_q[candidate_q]) begin
            if (candidate_q == 2'd3)
              state_q <= ST_FINISH;
            else begin
              candidate_q <= candidate_q + 2'd1;
              axis_q <= (seed_q[2:0] <= dims_m1_q) ? seed_q[2:0] : 3'd0;
              term_count_q <= 4'd0;
              partial_q <= 20'd0;
            end
          end else if (best_valid_q && (partial_q >= best_distance_q)) begin
            lower_q[candidate_q] <= partial_q;
            skipped_terms_q <= skipped_terms_q + ({12'd0, dims_m1_q} + 16'd1 - term_count_q);
            if (candidate_q == 2'd3)
              state_q <= ST_FINISH;
            else begin
              candidate_q <= candidate_q + 2'd1;
              axis_q <= (seed_q[2:0] <= dims_m1_q) ? seed_q[2:0] : 3'd0;
              term_count_q <= 4'd0;
              partial_q <= 20'd0;
            end
          end else begin
            visited_terms_q <= visited_terms_q + 16'd1;
            if (term_count_q == {1'b0, dims_m1_q}) begin
              lower_q[candidate_q] <= next_partial;
              if (!best_valid_q || (next_partial < best_distance_q)) begin
                best_distance_q <= next_partial;
                best_valid_q <= 1'b1;
                winner_q <= candidate_q;
              end
              if (candidate_q == 2'd3)
                state_q <= ST_FINISH;
              else begin
                candidate_q <= candidate_q + 2'd1;
                axis_q <= (seed_q[2:0] <= dims_m1_q) ? seed_q[2:0] : 3'd0;
                term_count_q <= 4'd0;
                partial_q <= 20'd0;
              end
            end else begin
              partial_q <= next_partial;
              term_count_q <= term_count_q + 4'd1;
              axis_q <= (axis_q == dims_m1_q) ? 3'd0 : axis_q + 3'd1;
            end
          end
        end

        ST_FINISH: begin
          state_q <= ST_IDLE;
          busy_q <= 1'b0;
          done_q <= 1'b1;
          exact_q <= 1'b1;
          atlas_hit_q <= 1'b0;
          atlas_valid_q <= 1'b1;
          atlas_query_q <= query_q;
          atlas_point_q[0] <= point_q[0];
          atlas_point_q[1] <= point_q[1];
          atlas_point_q[2] <= point_q[2];
          atlas_point_q[3] <= point_q[3];
          atlas_dims_m1_q <= dims_m1_q;
          atlas_valid_mask_q <= valid_mask_q;
          atlas_winner_q <= winner_q;
          atlas_radius_q <= atlas_radius_next;
        end

        default: ;
      endcase

      if (req_i && we_i) begin
        case (addr_i)
          REG_QUERY: begin
            if (!busy_q) query_q <= merge64(query_q, wdata_i, wstrb_i);
            else error_q <= 1'b1;
          end
          REG_POINT0: begin
            if (!busy_q) point_q[0] <= merge64(point_q[0], wdata_i, wstrb_i);
            else error_q <= 1'b1;
          end
          REG_POINT1: begin
            if (!busy_q) point_q[1] <= merge64(point_q[1], wdata_i, wstrb_i);
            else error_q <= 1'b1;
          end
          REG_POINT2: begin
            if (!busy_q) point_q[2] <= merge64(point_q[2], wdata_i, wstrb_i);
            else error_q <= 1'b1;
          end
          REG_POINT3: begin
            if (!busy_q) point_q[3] <= merge64(point_q[3], wdata_i, wstrb_i);
            else error_q <= 1'b1;
          end
          REG_CONTROL: begin
            if (!busy_q) begin
              dims_m1_q <= start_dims_m1;
              valid_mask_q <= start_valid_mask;
              seed_q <= start_seed;

              if (control_write[1]) begin
                done_q <= 1'b0;
                exact_q <= 1'b0;
                atlas_hit_q <= 1'b0;
                error_q <= 1'b0;
              end
              if (control_write[2])
                atlas_valid_q <= 1'b0;

              if (control_write[0]) begin
                owner_q <= source_i;
                jobs_q <= jobs_q + 16'd1;
                done_q <= 1'b0;
                exact_q <= 1'b0;
                atlas_hit_q <= 1'b0;
                error_q <= 1'b0;
                decision_cycles_q <= 16'd0;
                visited_terms_q <= 16'd0;
                skipped_terms_q <= 16'd0;

                if (start_valid_mask == 4'd0) begin
                  done_q <= 1'b1;
                  error_q <= 1'b1;
                end else if (atlas_match) begin
                  done_q <= 1'b1;
                  exact_q <= 1'b1;
                  atlas_hit_q <= 1'b1;
                  winner_q <= atlas_winner_q;
                  best_distance_q <= 20'd0;
                  atlas_hits_q <= atlas_hits_q + 16'd1;
                end else begin
                  state_q <= ST_CALC;
                  busy_q <= 1'b1;
                  candidate_q <= 2'd0;
                  axis_q <= (start_seed[2:0] <= start_dims_m1) ? start_seed[2:0] : 3'd0;
                  term_count_q <= 4'd0;
                  partial_q <= 20'd0;
                  lower_q[0] <= 20'd0;
                  lower_q[1] <= 20'd0;
                  lower_q[2] <= 20'd0;
                  lower_q[3] <= 20'd0;
                  best_distance_q <= 20'hfffff;
                  best_valid_q <= 1'b0;
                  winner_q <= 2'd0;
                end
              end
            end else if (control_write[0]) begin
              error_q <= 1'b1;
            end
          end
          default: ;
        endcase
      end
    end
  end

  assign busy_o = busy_q;
  assign done_o = done_q;
  assign exact_o = exact_q;
  assign atlas_hit_o = atlas_hit_q;
  assign winner_o = winner_q;
endmodule
