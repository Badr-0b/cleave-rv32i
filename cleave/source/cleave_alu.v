/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_alu — arithmetic/logic unit for the Cleave RV32I single-cycle core.
 *
 * Purely combinational. Computes one of ten RV32I base-integer operations selected
 * by alu_ctrl. The encoding is deliberate: alu_ctrl[2:0] mirrors the instruction's
 * funct3 field and alu_ctrl[3] is the instr[30] modifier bit (add vs sub, srl vs
 * sra), so the control unit can form alu_ctrl for R-type as {instr[30], funct3}
 * with no lookup. Shift amounts use only the low 5 bits of b (RV32 semantics). The
 * zero flag reports result == 0 (branch conditions are handled separately by
 * cleave_branch, so zero may be unused in the datapath).
 */

`default_nettype none

module cleave_alu (
    input  wire [31:0] a,          // operand A (rs1, or PC for AUIPC/jumps)
    input  wire [31:0] b,          // operand B (rs2, or immediate)
    input  wire [3:0]  alu_ctrl,   // operation select (see header)
    output reg  [31:0] result,     // ALU result
    output wire        zero        // result == 0
);

  // ALU op codes: {modifier, funct3-like}
  localparam [3:0] ALU_ADD  = 4'b0000,
                   ALU_SUB  = 4'b1000,
                   ALU_SLL  = 4'b0001,
                   ALU_SLT  = 4'b0010,
                   ALU_SLTU = 4'b0011,
                   ALU_XOR  = 4'b0100,
                   ALU_SRL  = 4'b0101,
                   ALU_SRA  = 4'b1101,
                   ALU_OR   = 4'b0110,
                   ALU_AND  = 4'b0111;

  wire [4:0] shamt = b[4:0];

  // 1. Shared Adder/Subtractor Logic
  // If the operation is SUB, we invert B and add 1 (via the carry-in)
  wire is_sub = (alu_ctrl == ALU_SUB);
  wire [31:0] adder_b = is_sub ? ~b : b;
  wire [31:0] add_sub_res = a + adder_b + is_sub;

  // 2. Shared right barrel shifter (SRL/SRA)
  // One shifter serves both: the fill bit is 0 for SRL (logical) and a[31] for
  // SRA (arithmetic). {fill, a} >>> shamt then keeps the low 32 bits.
  wire        sra_fill = (alu_ctrl == ALU_SRA) & a[31];
  wire [31:0] shr_res  = $signed({sra_fill, a}) >>> shamt;

  // 3. Shared magnitude comparator (SLT/SLTU)
  // Same trick as cleave_branch: flip the MSB for signed compares, keep it for
  // unsigned, then do one unsigned less-than. One comparator covers both ops.
  wire is_unsigned = (alu_ctrl == ALU_SLTU);
  wire slt = {is_unsigned ? a[31] : ~a[31], a[30:0]}
           < {is_unsigned ? b[31] : ~b[31], b[30:0]};

  always @(*) begin
    case (alu_ctrl)
      ALU_ADD  : result = add_sub_res;              // shared adder/sub
      ALU_SUB  : result = add_sub_res;              // shared adder/sub
      ALU_SLL  : result = a << shamt;
      ALU_SLT  : result = slt ? 32'd1 : 32'd0;      // shared comparator
      ALU_SLTU : result = slt ? 32'd1 : 32'd0;      // shared comparator
      ALU_XOR  : result = a ^ b;
      ALU_SRL  : result = shr_res;                  // shared right shifter
      ALU_SRA  : result = shr_res;                  // shared right shifter
      ALU_OR   : result = a | b;
      ALU_AND  : result = a & b;
      default  : result = add_sub_res; // Safe default
    endcase
  end

  // 2. NOR Reduction for the Zero Flag
  assign zero = ~|result;

endmodule

`default_nettype wire