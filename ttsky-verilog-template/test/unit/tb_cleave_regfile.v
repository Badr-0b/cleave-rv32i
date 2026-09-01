/*
 * Unit test — cleave_regfile (32x32, x0=0, 2 read + 1 write + debug port).
 * Compile with -DSIMULATION so unwritten registers read 0 deterministically.
 * Checks: write/readback, x0 stays 0 even when written, independent dual reads,
 * debug port mirrors a normal read, overwrite, and no-write when we=0.
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_regfile;
  reg         clk = 1'b0;
  reg         we;
  reg  [4:0]  rs1, rs2, rd, dbg_rs;
  reg  [31:0] wd;
  wire [31:0] rd1, rd2, dbg_data;
  integer     errors = 0;

  cleave_regfile dut (
    .clk(clk), .we(we), .rs1(rs1), .rs2(rs2), .rd(rd), .wd(wd),
    .rd1(rd1), .rd2(rd2), .dbg_rs(dbg_rs), .dbg_data(dbg_data)
  );

  always #5 clk = ~clk;

  task check(input [31:0] got, input [31:0] exp, input [8*32-1:0] name);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %h exp %h", name, got, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  // Drive a synchronous write on the next rising edge.
  task wr(input [4:0] a, input [31:0] d);
    begin
      @(negedge clk); rd = a; wd = d; we = 1'b1;
      @(posedge clk); #1; we = 1'b0;
    end
  endtask

  initial begin
    we = 0; rs1 = 0; rs2 = 0; rd = 0; wd = 0; dbg_rs = 0;
    @(negedge clk);

    // Write x5, read it back on port 1.
    wr(5'd5, 32'hDEAD_BEEF);
    rs1 = 5'd5; #1; check(rd1, 32'hDEAD_BEEF, "x5 write/readback");

    // x0 must stay 0 even after an attempted write.
    wr(5'd0, 32'hFFFF_FFFF);
    rs1 = 5'd0; #1; check(rd1, 32'h0000_0000, "x0 stays 0 after write");

    // Independent dual reads.
    wr(5'd6, 32'h1111_1111);
    rs1 = 5'd5; rs2 = 5'd6; #1;
    check(rd1, 32'hDEAD_BEEF, "dual read port1 = x5");
    check(rd2, 32'h1111_1111, "dual read port2 = x6");

    // Debug port mirrors a normal read.
    dbg_rs = 5'd6; #1; check(dbg_data, 32'h1111_1111, "debug port = x6");
    dbg_rs = 5'd0; #1; check(dbg_data, 32'h0000_0000, "debug port x0 = 0");

    // Overwrite.
    wr(5'd5, 32'h2222_2222);
    rs1 = 5'd5; #1; check(rd1, 32'h2222_2222, "x5 overwrite");

    // No write when we=0.
    @(negedge clk); rd = 5'd7; wd = 32'h3333_3333; we = 1'b0;
    @(posedge clk); #1;
    rs1 = 5'd7; #1; check(rd1, 32'h0000_0000, "we=0 -> no write (x7 stays 0)");

    if (errors == 0) $display("\nALL cleave_regfile TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
