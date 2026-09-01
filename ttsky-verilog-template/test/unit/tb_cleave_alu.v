/*
 * Unit test — cleave_alu (10 RV32I ops + zero flag).
 * Covers ADD/SUB wrap, logic ops, shifts with sign-extension and shamt masking,
 * SLT vs SLTU signedness divergence, and the zero flag.
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_alu;
  reg  [31:0] a, b;
  reg  [3:0]  alu_ctrl;
  wire [31:0] result;
  wire        zero;
  integer     errors = 0;

  cleave_alu dut (.a(a), .b(b), .alu_ctrl(alu_ctrl), .result(result), .zero(zero));

  localparam [3:0] ADD=4'b0000, SUB=4'b1000, SLL=4'b0001, SLT=4'b0010,
                   SLTU=4'b0011, XOR=4'b0100, SRL=4'b0101, SRA=4'b1101,
                   OR=4'b0110, AND=4'b0111;

  task check(input [3:0] op, input [31:0] x, input [31:0] y,
             input [31:0] exp_r, input exp_z, input [8*32-1:0] name);
    begin
      alu_ctrl = op; a = x; b = y; #1;
      if (result !== exp_r || zero !== exp_z) begin
        $display("FAIL %0s: r=%h(exp %h) z=%b(exp %b)", name, result, exp_r, zero, exp_z);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  initial begin
    check(ADD, 32'd5, 32'd7, 32'd12, 1'b0, "ADD 5+7");
    check(ADD, 32'hFFFF_FFFF, 32'd1, 32'd0, 1'b1, "ADD wrap -> 0, zero");
    check(SUB, 32'd12, 32'd5, 32'd7, 1'b0, "SUB 12-5");
    check(SUB, 32'd0, 32'd1, 32'hFFFF_FFFF, 1'b0, "SUB 0-1 -> -1");
    check(SUB, 32'd9, 32'd9, 32'd0, 1'b1, "SUB equal -> zero");
    check(AND, 32'hF0F0_F0F0, 32'hFF00_FF00, 32'hF000_F000, 1'b0, "AND");
    check(OR,  32'h0F0F_0000, 32'h0000_00F0, 32'h0F0F_00F0, 1'b0, "OR");
    check(XOR, 32'hAAAA_AAAA, 32'hFFFF_FFFF, 32'h5555_5555, 1'b0, "XOR");
    check(SLL, 32'd1, 32'd4, 32'h0000_0010, 1'b0, "SLL 1<<4");
    check(SLL, 32'd1, 32'd32, 32'd1, 1'b0, "SLL shamt masked (32->0)");
    check(SRL, 32'h8000_0000, 32'd4, 32'h0800_0000, 1'b0, "SRL logical");
    check(SRA, 32'h8000_0000, 32'd4, 32'hF800_0000, 1'b0, "SRA arith (sign ext)");
    check(SRA, 32'h4000_0000, 32'd4, 32'h0400_0000, 1'b0, "SRA positive");
    check(SLT, 32'hFFFF_FFFF, 32'd1, 32'd1, 1'b0, "SLT -1<1 signed");
    check(SLT, 32'd1, 32'hFFFF_FFFF, 32'd0, 1'b1, "SLT 1<-1 false");
    check(SLTU,32'hFFFF_FFFF, 32'd1, 32'd0, 1'b1, "SLTU big<1 false");
    check(SLTU,32'd1, 32'd2, 32'd1, 1'b0, "SLTU 1<2 true");

    if (errors == 0) $display("\nALL cleave_alu TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
