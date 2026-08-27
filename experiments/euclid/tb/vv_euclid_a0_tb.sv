`timescale 1ns/1ps

module vv_euclid_a0_tb;
  logic clk;
  logic rst_n;
  logic req;
  logic we;
  logic [7:0] addr;
  logic [63:0] wdata;
  logic [7:0] wstrb;
  logic [63:0] rdata;
  logic ready;
  logic busy;
  logic done;
  logic exact;
  logic atlas_hit;
  logic [1:0] winner;

  vv_euclid_a0 dut (
    .clk_i (clk),
    .rst_ni (rst_n),
    .req_i (req),
    .we_i (we),
    .addr_i (addr),
    .wdata_i (wdata),
    .wstrb_i (wstrb),
    .source_i (2'd1),
    .rdata_o (rdata),
    .ready_o (ready),
    .busy_o (busy),
    .done_o (done),
    .exact_o (exact),
    .atlas_hit_o (atlas_hit),
    .winner_o (winner)
  );

  always #5 clk = ~clk;

  task automatic write64(input logic [7:0] a, input logic [63:0] d);
    begin
      @(negedge clk);
      req = 1'b1;
      we = 1'b1;
      addr = a;
      wdata = d;
      wstrb = 8'hff;
      @(negedge clk);
      req = 1'b0;
      we = 1'b0;
      addr = 8'd0;
      wdata = 64'd0;
    end
  endtask

  task automatic start_job;
    begin
      write64(8'h00, 64'h0000_0000_0000_f701);
    end
  endtask

  task automatic wait_done;
    integer timeout;
    begin
      timeout = 0;
      while (!done && timeout < 200) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (!done) $fatal(1, "Euclid job timed out");
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    req = 1'b0;
    we = 1'b0;
    addr = 8'd0;
    wdata = 64'd0;
    wstrb = 8'hff;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    write64(8'h10, 64'h0000_0000_0000_0000);
    write64(8'h18, 64'h0000_0000_0000_0001);
    write64(8'h20, 64'h0000_0000_0000_0064);
    write64(8'h28, 64'h0000_0000_0000_0078);
    write64(8'h30, 64'h0000_0000_0000_009c);
    start_job();
    wait_done();

    if (!exact) $fatal(1, "first Euclid result is not exact");
    if (atlas_hit) $fatal(1, "first Euclid job unexpectedly hit Atlas");
    if (winner != 2'd0) $fatal(1, "first Euclid winner mismatch: %0d", winner);

    write64(8'h10, 64'h0000_0000_0000_0002);
    start_job();
    wait_done();
    if (!exact || !atlas_hit || winner != 2'd0)
      $fatal(1, "Atlas hit mismatch exact=%0d hit=%0d winner=%0d", exact, atlas_hit, winner);

    write64(8'h00, 64'h0000_0000_0000_0006); // clear status and Atlas
    write64(8'h10, 64'h0000_0000_0000_0000);
    write64(8'h18, 64'h0000_0000_0000_0001);
    write64(8'h20, 64'h0000_0000_0000_00ff); // -1, tie with point0; lower index wins
    write64(8'h28, 64'h0000_0000_0000_0064);
    write64(8'h30, 64'h0000_0000_0000_009c);
    start_job();
    wait_done();
    if (!exact || winner != 2'd0)
      $fatal(1, "tie rule mismatch: %0d", winner);

    $display("vv_euclid_a0_tb PASS");
    $finish;
  end
endmodule
