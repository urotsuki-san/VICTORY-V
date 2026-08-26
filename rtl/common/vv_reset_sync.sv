module vv_reset_sync #(
  parameter integer STAGES = 4
) (
  input  logic clk_i,
  input  logic arst_ni,
  output logic rst_ni
);
  logic [STAGES-1:0] sync_q;

  always_ff @(posedge clk_i or negedge arst_ni) begin
    if (!arst_ni)
      sync_q <= '0;
    else
      sync_q <= {sync_q[STAGES-2:0], 1'b1};
  end

  assign rst_ni = sync_q[STAGES-1];
endmodule
