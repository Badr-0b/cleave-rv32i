/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_control — main + ALU decode for the Cleave RV32I single-cycle core.
 *
 * Purely combinational. Turns the fetched instruction's opcode / funct3 /
 * instr[30] into the full datapath control vector: register-write enable, the two
 * ALU operand-source selects, memory read/write, branch / jump / jalr flags, the
 * writeback source select, the immediate-format select, and the ALU op. Encodings
 * match the modules already built: alu_ctrl = {instr[30], funct3} (cleave_alu),
 * imm_sel = I/S/B/U/J as 000/001/010/011/100 (cleave_immgen), and cleave_branch
 * takes funct3 directly (this unit only says whether the opcode is a branch).
 *
 * The block sets a safe NOP default for every output, then a case(opcode) overrides
 * only the fields a given opcode needs — so any unlisted/illegal opcode, plus FENCE
 * and SYSTEM (ECALL/EBREAK), fall through as a harmless no-op (no arch-state change),
 * which is the intended single-cycle treatment (no CSR / trap logic).
 *
 * illegal_instr flags an *unrecognized opcode* only — it does NOT validate funct3/
 * funct7, so a malformed encoding under an otherwise-legal opcode is not caught.
 * With no trap path in this core, nothing acts on it in hardware; it is a
 * simulation/debug assertion hook (the proof-program bench raises $error if it ever
 * asserts while running valid code). Full illegal-instruction detection would need
 * the whole funct7 field and a trap mechanism — out of scope here by design.
 */

`default_nettype none

module cleave_control (
    input  wire [6:0] opcode,       // instr[6:0]
    input  wire [2:0] funct3,       // instr[14:12]
    input  wire       funct7b5,     // instr[30]  (add/sub, srl/sra modifier)
    output reg        reg_write,    // rd write enable
    output reg        alu_src_a,    // 1 = PC (AUIPC), 0 = rs1
    output reg        alu_src_b,    // 1 = imm,        0 = rs2
    output reg        mem_read,     // load
    output reg        mem_write,    // store
    output reg        branch,       // conditional-branch opcode
    output reg        jump,         // JAL or JALR (unconditional)
    output reg        jalr,         // 1 = JALR target rs1+imm, 0 = JAL target pc+imm
    output reg [1:0]  result_src,   // 00 ALU, 01 MEM, 10 PC+4, 11 IMM (LUI)
    output reg [2:0]  imm_sel,      // I/S/B/U/J for cleave_immgen
    output reg [3:0]  alu_ctrl,     // for cleave_alu
    output reg        illegal_instr // 1 = unrecognized opcode (sim/debug assert; no trap taken)
);

  // ---- RV32I base opcodes (instr[6:0]) ----
  localparam [6:0] OP_LOAD   = 7'b0000011,
                   OP_IMM    = 7'b0010011,
                   OP_AUIPC  = 7'b0010111,
                   OP_STORE  = 7'b0100011,
                   OP_REG    = 7'b0110011,
                   OP_LUI    = 7'b0110111,
                   OP_BRANCH = 7'b1100011,
                   OP_JALR   = 7'b1100111,
                   OP_JAL    = 7'b1101111,
                   OP_FENCE  = 7'b0001111,
                   OP_SYSTEM = 7'b1110011;

  // ---- imm_sel encodings ----
  localparam [2:0] IMM_I = 3'b000,
                   IMM_S = 3'b001,
                   IMM_B = 3'b010,
                   IMM_U = 3'b011,
                   IMM_J = 3'b100;

  // ---- result_src encodings ----
  localparam [1:0] RES_ALU = 2'b00,
                   RES_MEM = 2'b01,
                   RES_PC4 = 2'b10,
                   RES_IMM = 2'b11;

  localparam [3:0] ALU_ADD = 4'b0000;

  wire is_shift_imm = (funct3 == 3'b001) || (funct3 == 3'b101);

  always @(*) begin
    // Baseline defaults: State-altering signals MUST be 0.
    // Routing signals default to safe values, but are overridden to X below when unused.
    reg_write     = 1'b0;
    mem_read      = 1'b0;
    mem_write     = 1'b0;
    branch        = 1'b0;
    jump          = 1'b0;
    jalr          = 1'b0;
    illegal_instr = 1'b0;
    
    alu_src_a     = 1'b0;
    alu_src_b     = 1'b0;
    result_src    = RES_ALU;
    imm_sel       = IMM_I;
    alu_ctrl      = ALU_ADD;

    case (opcode)
      OP_REG: begin
        reg_write = 1'b1;
        alu_src_b = 1'b0;
        alu_ctrl  = {funct7b5, funct3};
        imm_sel   = 3'bx; // Optimization: No immediate used, save mux logic
      end

      OP_IMM: begin
        reg_write = 1'b1;
        alu_src_b = 1'b1;
        imm_sel   = IMM_I;
        alu_ctrl  = is_shift_imm ? {funct7b5, funct3} : {1'b0, funct3};
      end

      OP_LOAD: begin
        reg_write  = 1'b1;
        alu_src_b  = 1'b1;
        imm_sel    = IMM_I;
        mem_read   = 1'b1;
        result_src = RES_MEM;
        alu_ctrl   = ALU_ADD;
      end

      OP_STORE: begin
        alu_src_b  = 1'b1;
        imm_sel    = IMM_S;
        mem_write  = 1'b1;
        alu_ctrl   = ALU_ADD;
        result_src = 2'bx; // Optimization: Nothing written to RegFile
      end

      OP_BRANCH: begin
        branch     = 1'b1;
        imm_sel    = IMM_B;
        result_src = 2'bx; // Optimization: Nothing written to RegFile
      end

      OP_LUI: begin
        reg_write  = 1'b1;
        imm_sel    = IMM_U;
        result_src = RES_IMM;
        alu_ctrl   = 4'bx; // Optimization: ALU bypass, don't care
      end

      OP_AUIPC: begin
        reg_write  = 1'b1;
        alu_src_a  = 1'b1;
        alu_src_b  = 1'b1;
        imm_sel    = IMM_U;
        result_src = RES_ALU;
        alu_ctrl   = ALU_ADD;
      end

      OP_JAL: begin
        reg_write  = 1'b1;
        jump       = 1'b1;
        imm_sel    = IMM_J;
        result_src = RES_PC4;
        alu_ctrl   = 4'bx; // Optimization: ALU not used for JAL (target is PC+IMM)
      end

      OP_JALR: begin
        reg_write  = 1'b1;
        jump       = 1'b1;
        jalr       = 1'b1;
        alu_src_b  = 1'b1;
        imm_sel    = IMM_I;
        result_src = RES_PC4;
        alu_ctrl   = ALU_ADD;
      end

      OP_FENCE, OP_SYSTEM: begin
        // Treated as NOPs for now.
      end

      default: begin
        // Illegal opcode: Flag it and aggressively set all routing to X to save area
        illegal_instr = 1'b1;
        alu_src_a     = 1'bx;
        alu_src_b     = 1'bx;
        result_src    = 2'bx;
        imm_sel       = 3'bx;
        alu_ctrl      = 4'bx;
      end
    endcase
  end

endmodule

`default_nettype wire
