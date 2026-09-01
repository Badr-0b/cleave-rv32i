/*
 * Unit test — cleave_imem (on-chip instruction ROM, combinational word read).
 * Checks representative words of the baked-in RV32I proof program, byte->word
 * indexing (low 2 bits ignored), and address wrap beyond DEPTH. The ROM now holds
 * the real 64-word proof program (see cleave_imem.v / tb_cleave_proof.v), so these
 * expectations are spot-checks of the committed encodings, not the old placeholder.
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_imem;
  reg  [31:0] addr;
  wire [31:0] instr;
  integer     errors = 0;

  cleave_imem dut (.addr(addr), .instr(instr));   // defaults DEPTH=64, AW=6

  localparam [31:0] PARK = 32'h0000_0063;         // BEQ x0,x0,0 self-loop at word 63

  task check(input [31:0] a, input [31:0] exp, input [8*28-1:0] name);
    begin
      addr = a; #1;
      if (instr !== exp) begin
        $display("FAIL %0s: addr=%h instr=%h exp=%h", name, a, instr, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  initial begin
    // Representative program words (byte addr = word * 4).
    check(32'h0000_0000, 32'h06400193, "word0  addi x3,x0,100");
    check(32'h0000_0050, 32'h123450B7, "word20 lui x1,0x12345");
    check(32'h0000_0054, 32'h00000117, "word21 auipc x2,0");
    check(32'h0000_0088, 32'h00000463, "word34 beq x0,x0,+8");
    check(32'h0000_00E0, 32'h00C0086F, "word56 jal x16,SUB");
    check(32'h0000_00FC, PARK,         "word63 park self-loop");
    // Byte offset within a word is ignored (0x02 -> same word as 0x00).
    check(32'h0000_0002, 32'h06400193, "byte offset ignored");
    // Address at DEPTH*4 wraps to word 0 (index truncates to AW bits).
    check(32'h0000_0100, 32'h06400193, "wrap to word0");

    if (errors == 0) $display("\nALL cleave_imem TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
