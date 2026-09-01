/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_immgen — immediate generator for the Cleave RV32I single-cycle core.
 *
 * RISC-V encodes immediates in five layouts (I/S/B/U/J), each scattering the bits
 * to different positions in the 32-bit instruction so the register fields can stay
 * put. This purely combinational block picks the layout via imm_sel and reassembles
 * the bits into a single sign-extended 32-bit immediate. Bit 31 of the instruction
 * is always the sign source. B- and J-type targets are 2-byte aligned, so their
 * least-significant bit is a hardwired 0. U-type is not sign-extended: its 20 bits
 * become the high 20 bits of the result, low 12 zeroed.
 */

`default_nettype none

module cleave_immgen (
    input  wire [31:0] instr,      // full instruction word
    input  wire [2:0]  imm_sel,    // which immediate format to build
    output reg  [31:0] imm         // reassembled, sign-extended immediate
);

  localparam [2:0] IMM_I = 3'b000,
                   IMM_S = 3'b001,
                   IMM_B = 3'b010,
                   IMM_U = 3'b011,
                   IMM_J = 3'b100;

  always @(*) begin
    case (imm_sel)
      IMM_I : imm = {{20{instr[31]}}, instr[31:20]};
      IMM_S : imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      IMM_B : imm = {{19{instr[31]}}, instr[31], instr[7],
                     instr[30:25], instr[11:8], 1'b0};
      IMM_U : imm = {instr[31:12], 12'b0};
      IMM_J : imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20],
                     instr[30:21], 1'b0};
      default: imm = 32'bx;  // Yosys optimization: Don't care state minimizes gates
    endcase
  end

endmodule

`default_nettype wire
