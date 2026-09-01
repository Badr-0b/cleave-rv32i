/*
 * Unit test — cleave_immgen (I/S/B/U/J immediate reassembly + sign extension).
 * Feeds raw instruction words with known immediates and checks each format.
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_immgen;
  reg  [31:0] instr;
  reg  [2:0]  imm_sel;
  wire [31:0] imm;
  integer     errors = 0;

  cleave_immgen dut (.instr(instr), .imm_sel(imm_sel), .imm(imm));

  localparam [2:0] I=3'b000, S=3'b001, B=3'b010, U=3'b011, J=3'b100;

  task check(input [2:0] sel, input [31:0] iw, input [31:0] exp, input [8*32-1:0] name);
    begin
      imm_sel = sel; instr = iw; #1;
      if (imm !== exp) begin
        $display("FAIL %0s: sel=%b instr=%h imm=%h exp=%h", name, sel, iw, imm, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  initial begin
    // I-type
    check(I, 32'h00A0_0000, 32'h0000_000A, "I  +10");
    check(I, 32'hFFC0_0000, 32'hFFFF_FFFC, "I  -4 (sign ext)");
    // S-type (split field)
    check(S, 32'hFE00_0C00, 32'hFFFF_FFF8, "S  -8 (split, sign ext)");
    // U-type (upper 20, low 12 zero, not sign extended)
    check(U, 32'h1234_5ABC, 32'h1234_5000, "U  upper 20 kept");
    // B-type (shuffled, LSB=0)
    check(B, 32'h0000_0400, 32'h0000_0008, "B  +8");
    check(B, 32'hFE00_0C80, 32'hFFFF_FFF8, "B  -8 (shuffled, sign ext)");
    // J-type (shuffled, LSB=0)
    check(J, 32'h0040_0000, 32'h0000_0004, "J  +4");
    check(J, 32'hFFDF_F000, 32'hFFFF_FFFC, "J  -4 (shuffled, sign ext)");

    if (errors == 0) $display("\nALL cleave_immgen TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
