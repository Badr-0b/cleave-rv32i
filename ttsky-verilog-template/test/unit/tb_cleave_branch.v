/*
 * Unit test — cleave_branch (6 RV32I branch conditions).
 * Emphasis on the signed vs unsigned divergence, plus equal-operand boundaries
 * and the non-branch funct3 falling through to take=0.
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_branch;
  reg  [31:0] rs1, rs2;
  reg  [2:0]  funct3;
  wire        take;
  integer     errors = 0;

  cleave_branch dut (.rs1(rs1), .rs2(rs2), .funct3(funct3), .take(take));

  localparam [2:0] BEQ=3'b000, BNE=3'b001, BLT=3'b100,
                   BGE=3'b101, BLTU=3'b110, BGEU=3'b111, NOTBR=3'b010;

  task check(input [2:0] f3, input [31:0] a, input [31:0] b,
             input exp, input [8*28-1:0] name);
    begin
      funct3 = f3; rs1 = a; rs2 = b; #1;
      if (take !== exp) begin
        $display("FAIL %0s: f3=%b a=%h b=%h take=%b exp=%b", name, f3, a, b, take, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  initial begin
    check(BEQ, 32'd5, 32'd5, 1'b1, "BEQ equal");
    check(BEQ, 32'd5, 32'd6, 1'b0, "BEQ unequal");
    check(BNE, 32'd5, 32'd6, 1'b1, "BNE unequal");
    check(BNE, 32'd5, 32'd5, 1'b0, "BNE equal");
    check(BLT, 32'hFFFF_FFFF, 32'd1, 1'b1, "BLT -1<1 signed");
    check(BGE, 32'hFFFF_FFFF, 32'd1, 1'b0, "BGE -1>=1 no");
    check(BLTU,32'hFFFF_FFFF, 32'd1, 1'b0, "BLTU big<1 no");
    check(BGEU,32'hFFFF_FFFF, 32'd1, 1'b1, "BGEU big>=1 yes");
    check(BGE, 32'd7, 32'd7, 1'b1, "BGE equal yes");
    check(BGEU,32'd7, 32'd7, 1'b1, "BGEU equal yes");
    check(BLT, 32'd7, 32'd7, 1'b0, "BLT equal no");
    check(BLTU,32'd7, 32'd7, 1'b0, "BLTU equal no");
    check(NOTBR,32'd5, 32'd5, 1'b0, "non-branch f3 -> 0");

    if (errors == 0) $display("\nALL cleave_branch TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
