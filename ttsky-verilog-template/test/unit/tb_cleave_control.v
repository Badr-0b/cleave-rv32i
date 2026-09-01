/*
 * Unit test — cleave_control (full-RV32I decode -> control vector).
 *
 * Two properties are tested:
 *   1. Every state-altering / defined routing signal is checked EXACTLY, and is
 *      never allowed to be X (an unintended X in a required field fails).
 *   2. The don't-care fields the RTL deliberately drives to X (imm_sel on R-type,
 *      result_src on stores/branches, alu_ctrl on LUI/JAL, all routing on an
 *      illegal opcode) are encoded as x in the expected vector and SKIPPED by the
 *      masked comparator — so the bench matches the optimization contract.
 *
 * Bit layout [17:0]:
 *   [17] reg_write [16] illegal_instr [15] alu_src_a [14] alu_src_b
 *   [13] mem_read  [12] mem_write     [11] branch    [10] jump  [9] jalr
 *   [8:7] result_src  [6:4] imm_sel  [3:0] alu_ctrl
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_control;
  reg  [6:0] opcode;
  reg  [2:0] funct3;
  reg        funct7b5;
  wire       reg_write, alu_src_a, alu_src_b, mem_read, mem_write, branch, jump, jalr, illegal_instr;
  wire [1:0] result_src;
  wire [2:0] imm_sel;
  wire [3:0] alu_ctrl;
  integer    errors = 0;

  cleave_control dut (
    .opcode(opcode), .funct3(funct3), .funct7b5(funct7b5),
    .reg_write(reg_write), .alu_src_a(alu_src_a), .alu_src_b(alu_src_b),
    .mem_read(mem_read), .mem_write(mem_write), .branch(branch),
    .jump(jump), .jalr(jalr), .result_src(result_src),
    .imm_sel(imm_sel), .alu_ctrl(alu_ctrl), .illegal_instr(illegal_instr)
  );

  wire [17:0] vec = {reg_write, illegal_instr, alu_src_a, alu_src_b,
                     mem_read, mem_write, branch, jump, jalr,
                     result_src, imm_sel, alu_ctrl};

  function [17:0] mk;
    input rw, ill, a, b, mr, mw, br, jmp, jr;
    input [1:0] rs;
    input [2:0] is;
    input [3:0] ac;
    mk = {rw, ill, a, b, mr, mw, br, jmp, jr, rs, is, ac};
  endfunction

  // Masked equality: expected bits == x are skipped; defined expected bits must match.
  function match;
    input [17:0] a;
    input [17:0] e;
    integer i;
    reg ok;
    begin
      ok = 1'b1;
      for (i = 0; i < 18; i = i + 1)
        if (e[i] !== 1'bx && a[i] !== e[i]) ok = 1'b0;
      match = ok;
    end
  endfunction

  task check(input [6:0] op, input [2:0] f3, input b30,
             input [17:0] exp, input [8*28-1:0] name);
    begin
      opcode = op; funct3 = f3; funct7b5 = b30; #1;
      if (!match(vec, exp)) begin
        $display("FAIL %0s\n     got %b\n     exp %b (x=don't-care)", name, vec, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  localparam [6:0] LOAD=7'b0000011, IMM=7'b0010011, AUIPC=7'b0010111,
                   STORE=7'b0100011, REG=7'b0110011, LUI=7'b0110111,
                   BRANCH=7'b1100011, JALR=7'b1100111, JAL=7'b1101111,
                   FENCE=7'b0001111, SYSTEM=7'b1110011;

  localparam [1:0] R_ALU=2'b00, R_MEM=2'b01, R_PC4=2'b10, R_IMM=2'b11, R_X=2'bxx;
  localparam [2:0] I_I=3'b000, I_S=3'b001, I_B=3'b010, I_U=3'b011, I_J=3'b100, I_X=3'bxxx;
  localparam [3:0] A_ADD=4'b0000, A_SUB=4'b1000, A_SLL=4'b0001, A_SRL=4'b0101,
                   A_SRA=4'b1101, A_X=4'bxxxx;

  initial begin
    //           op      f3      b30    rw ill a  b  mr mw br jmp jr  result imm   alu
    check(REG,   3'b000, 1'b0, mk(1, 0, 0, 0, 0, 0, 0, 0, 0, R_ALU, I_X,  A_ADD), "ADD");
    check(REG,   3'b000, 1'b1, mk(1, 0, 0, 0, 0, 0, 0, 0, 0, R_ALU, I_X,  A_SUB), "SUB (instr30)");
    check(IMM,   3'b000, 1'b1, mk(1, 0, 0, 1, 0, 0, 0, 0, 0, R_ALU, I_I,  A_ADD), "ADDI neg-imm stays ADD");
    check(IMM,   3'b001, 1'b0, mk(1, 0, 0, 1, 0, 0, 0, 0, 0, R_ALU, I_I,  A_SLL), "SLLI");
    check(IMM,   3'b101, 1'b1, mk(1, 0, 0, 1, 0, 0, 0, 0, 0, R_ALU, I_I,  A_SRA), "SRAI");
    check(IMM,   3'b101, 1'b0, mk(1, 0, 0, 1, 0, 0, 0, 0, 0, R_ALU, I_I,  A_SRL), "SRLI");
    check(LOAD,  3'b010, 1'b0, mk(1, 0, 0, 1, 1, 0, 0, 0, 0, R_MEM, I_I,  A_ADD), "LW");
    check(STORE, 3'b010, 1'b0, mk(0, 0, 0, 1, 0, 1, 0, 0, 0, R_X,   I_S,  A_ADD), "SW (result_src X)");
    check(BRANCH,3'b000, 1'b0, mk(0, 0, 0, 0, 0, 0, 1, 0, 0, R_X,   I_B,  A_ADD), "BEQ (result_src X)");
    check(LUI,   3'b000, 1'b0, mk(1, 0, 0, 0, 0, 0, 0, 0, 0, R_IMM, I_U,  A_X  ), "LUI (alu_ctrl X)");
    check(AUIPC, 3'b000, 1'b0, mk(1, 0, 1, 1, 0, 0, 0, 0, 0, R_ALU, I_U,  A_ADD), "AUIPC (a=PC)");
    check(JAL,   3'b000, 1'b0, mk(1, 0, 0, 0, 0, 0, 0, 1, 0, R_PC4, I_J,  A_X  ), "JAL (alu_ctrl X)");
    check(JALR,  3'b000, 1'b0, mk(1, 0, 0, 1, 0, 0, 0, 1, 1, R_PC4, I_I,  A_ADD), "JALR (alu adds target)");
    check(FENCE, 3'b000, 1'b0, mk(0, 0, 0, 0, 0, 0, 0, 0, 0, R_ALU, I_I,  A_ADD), "FENCE NOP");
    check(SYSTEM,3'b000, 1'b0, mk(0, 0, 0, 0, 0, 0, 0, 0, 0, R_ALU, I_I,  A_ADD), "SYSTEM NOP");

    // Illegal opcodes: must flag illegal_instr AND keep every state-altering signal 0.
    check(7'b1111111, 3'b000, 1'b0, mk(0, 1, 1'bx,1'bx, 0,0,0,0,0, R_X, I_X, A_X), "illegal all-ones");
    check(7'b0101011, 3'b010, 1'b1, mk(0, 1, 1'bx,1'bx, 0,0,0,0,0, R_X, I_X, A_X), "illegal custom-2");

    if (errors == 0) $display("\nALL cleave_control TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
