/*
 * Unit test — cleave_pc (program counter register).
 * Checks: reset forces PC=0; PC latches pc_next each clock; re-reset returns to 0.
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_pc;
  reg         clk = 1'b0;
  reg         rst;
  reg  [31:0] pc_next;
  wire [31:0] pc;
  integer     errors = 0;

  cleave_pc dut (.clk(clk), .rst(rst), .pc_next(pc_next), .pc(pc));

  always #5 clk = ~clk;

  task check(input [31:0] got, input [31:0] exp, input [8*28-1:0] name);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %h exp %h", name, got, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  initial begin
    // Reset holds PC at the reset vector.
    rst = 1'b1; pc_next = 32'hDEAD_BEEF;
    @(posedge clk); #1; check(pc, 32'h0000_0000, "reset -> 0");

    // Sequential stepping.
    rst = 1'b0; pc_next = 32'h0000_0004;
    @(posedge clk); #1; check(pc, 32'h0000_0004, "latch 0x4");
    pc_next = 32'h0000_0008;
    @(posedge clk); #1; check(pc, 32'h0000_0008, "latch 0x8");

    // Non-sequential (branch/jump target).
    pc_next = 32'h0000_0100;
    @(posedge clk); #1; check(pc, 32'h0000_0100, "latch 0x100");

    // Re-assert reset mid-stream.
    rst = 1'b1; pc_next = 32'h0000_0200;
    @(posedge clk); #1; check(pc, 32'h0000_0000, "re-reset -> 0");

    if (errors == 0) $display("\nALL cleave_pc TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
