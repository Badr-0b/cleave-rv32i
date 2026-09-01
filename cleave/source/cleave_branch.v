/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_branch — branch-condition comparator for the Cleave RV32I core.
 *
 * Purely combinational. Evaluates the six RV32I conditional-branch tests
 * (BEQ/BNE/BLT/BGE/BLTU/BGEU) on the two register operands, selected by the
 * branch instruction's funct3 field, and outputs a single take/don't-take bit.
 * The core gates this with the control unit's `branch` signal before it can
 * redirect the PC, so a non-branch funct3 landing here is harmless. Signed vs
 * unsigned is the only subtlety: BLT/BGE use $signed, BLTU/BGEU the raw values.
 */

`default_nettype none

module cleave_branch (
    input  wire [31:0] rs1,          // first source operand
    input  wire [31:0] rs2,          // second source operand
    input  wire [2:0]  funct3,       // branch type (instr[14:12])
    output reg         take          // condition met (before AND with control.branch)
);

  localparam [2:0] F3_BEQ  = 3'b000,
                   F3_BNE  = 3'b001,
                   F3_BLT  = 3'b100,
                   F3_BGE  = 3'b101,
                   F3_BLTU = 3'b110,
                   F3_BGEU = 3'b111;

  // 1. Equality check (Synthesizes to a small, fast XOR->NOR tree)
  wire eq = (rs1 == rs2);

  // 2. Shared Magnitude Comparator (Massive Area Optimization)
  // Determine if the current instruction is an unsigned branch
  wire is_unsigned = (funct3 == F3_BLTU) || (funct3 == F3_BGEU);
  
  // Flip the MSB for signed comparisons, keep it as-is for unsigned
  wire cmp_msb1 = is_unsigned ? rs1[31] : ~rs1[31];
  wire cmp_msb2 = is_unsigned ? rs2[31] : ~rs2[31];
  
  // Single 32-bit comparator handles both signed and unsigned logic
  wire lt = {cmp_msb1, rs1[30:0]} < {cmp_msb2, rs2[30:0]};

  always @(*) begin
    case (funct3)
      F3_BEQ  : take =  eq;
      F3_BNE  : take = ~eq;
      F3_BLT  : take =  lt;
      F3_BGE  : take = ~lt;
      F3_BLTU : take =  lt;
      F3_BGEU : take = ~lt;
      default : take = 1'b0;   // funct3 010/011 aren't branches → never take
    endcase
  end

endmodule

`default_nettype wire