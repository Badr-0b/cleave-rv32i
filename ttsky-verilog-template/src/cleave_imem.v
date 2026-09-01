/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_imem — on-chip instruction ROM for the Cleave RV32I single-cycle core.
 *
 * Combinational (asynchronous) word read: present a byte address, get the 32-bit
 * instruction back the same cycle. The program is baked in at elaboration via the
 * initial block below, so the ROM hardens to constant logic (no external memory
 * bus). RISC-V instructions are word-aligned, so the low two address bits are
 * ignored and the ROM is indexed by addr[ADDR_MSB:2].
 *
 * DEPTH words → DEPTH*4 bytes of program space. Out-of-range fetches wrap within
 * the ROM (index truncates); keep programs within DEPTH words.
 *
 * PROGRAM: the RV32I proof program (64 words, fills the ROM exactly). It exercises
 * every instruction group once — all I/R-type ALU ops, LUI/AUIPC, every load/store
 * width (LB/LH/LW/LBU/LHU, SB/SH/SW), all six conditional branches (taken cases
 * jump over a "poison" ADDI so a mis-decoded branch is caught downstream), a
 * JAL/JALR call+return, and FENCE/ECALL (decoded as NOPs) — then parks in the
 * canonical `BEQ x0,x0,0` self-loop at word 63 (PC 0xFC). Assembled and
 * cross-checked by an independent ISS; the golden end state is asserted by
 * test/unit/tb_cleave_proof.v. See that bench for the disassembly + expected state.
 */

`default_nettype none

module cleave_imem #(
    parameter integer DEPTH = 64,          // number of 32-bit words
    parameter integer AW    = 6            // address index width = log2(DEPTH)
) (
    input  wire [31:0] addr,               // byte address (from the PC)
    output wire [31:0] instr               // fetched instruction word
);

  // Word-addressed ROM. An initialized reg array read-only elsewhere infers a ROM.
  reg [31:0] rom [0:DEPTH-1];

  // Index by the word address, dropping the byte-offset bits [1:0].
  wire [AW-1:0] word_index = addr[AW+1:2];

  assign instr = rom[word_index];

  // --------------------------------------------------------------------------
  // RV32I proof program. Generated (assembler + ISS); do not hand-edit encodings
  // without regenerating the golden state in tb_cleave_proof.v. Any unused words
  // default to NOP (ADDI x0,x0,0) so an out-of-range fetch still behaves.
  // --------------------------------------------------------------------------
  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1)
      rom[i] = 32'h0000_0013;              // NOP fill

    // ---- ALU immediate ----
    rom[ 0] = 32'h06400193;  // addi  x3,  x0, 100
    rom[ 1] = 32'hFCE00213;  // addi  x4,  x0, -50
    rom[ 2] = 32'h0F01C393;  // xori  x7,  x3, 0xF0
    rom[ 3] = 32'h0011E413;  // ori   x8,  x3, 1
    rom[ 4] = 32'h00F1F493;  // andi  x9,  x3, 0x0F   (x9 = 4, reused as shift amount)
    rom[ 5] = 32'h00022513;  // slti  x10, x4, 0
    rom[ 6] = 32'h00023593;  // sltiu x11, x4, 0
    rom[ 7] = 32'h00419613;  // slli  x12, x3, 4
    rom[ 8] = 32'h0021D693;  // srli  x13, x3, 2
    rom[ 9] = 32'h40125713;  // srai  x14, x4, 1
    // ---- ALU register (shift amount = x9 = 4) ----
    rom[10] = 32'h004182B3;  // add   x5,  x3, x4
    rom[11] = 32'h40418333;  // sub   x6,  x3, x4
    rom[12] = 32'h009197B3;  // sll   x15, x3, x9
    rom[13] = 32'h0091D8B3;  // srl   x17, x3, x9
    rom[14] = 32'h40925933;  // sra   x18, x4, x9
    rom[15] = 32'h003229B3;  // slt   x19, x4, x3
    rom[16] = 32'h0041BA33;  // sltu  x20, x3, x4
    rom[17] = 32'h0041CAB3;  // xor   x21, x3, x4
    rom[18] = 32'h0091EB33;  // or    x22, x3, x9
    rom[19] = 32'h0091FBB3;  // and   x23, x3, x9
    // ---- U-type ----
    rom[20] = 32'h123450B7;  // lui   x1,  0x12345
    rom[21] = 32'h00000117;  // auipc x2,  0        (x2 = PC of this instr = 0x54)
    // ---- memory: stores + all load widths ----
    rom[22] = 32'h01000C13;  // addi  x24, x0, 16   (data base byte)
    rom[23] = 32'hDEADCCB7;  // lui   x25, 0xDEADC
    rom[24] = 32'h0DECEC93;  // ori   x25, x25, 0xDE (x25 = 0xDEADC0DE)
    rom[25] = 32'h019C2023;  // sw    x25, 0(x24)
    rom[26] = 32'h000C2D03;  // lw    x26, 0(x24)
    rom[27] = 32'h000C1D83;  // lh    x27, 0(x24)   -> 0xFFFFC0DE
    rom[28] = 32'h000C5E03;  // lhu   x28, 0(x24)   -> 0x0000C0DE
    rom[29] = 32'h000C0E83;  // lb    x29, 0(x24)   -> 0xFFFFFFDE
    rom[30] = 32'h001C4F03;  // lbu   x30, 1(x24)   -> 0x000000C0
    rom[31] = 32'h019C0423;  // sb    x25, 8(x24)   (mem byte 24 low byte = 0xDE)
    rom[32] = 32'h019C1623;  // sh    x25, 12(x24)  (mem byte 28 low half = 0xC0DE)
    // ---- control flow: witness accumulator in x31 ----
    rom[33] = 32'h00000F93;  // addi  x31, x0, 0
    rom[34] = 32'h00000463;  // beq   x0, x0, +8    (taken; skip poison)
    rom[35] = 32'h100F8F93;  // addi  x31, x31, 0x100  POISON
    rom[36] = 32'h001F8F93;  // L1: addi x31, x31, 1
    rom[37] = 32'h00419463;  // bne   x3, x4, +8    (taken)
    rom[38] = 32'h200F8F93;  // addi  x31, x31, 0x200  POISON
    rom[39] = 32'h002F8F93;  // L2: addi x31, x31, 2
    rom[40] = 32'h00324463;  // blt   x4, x3, +8    (taken; -50 < 100)
    rom[41] = 32'h400F8F93;  // addi  x31, x31, 0x400  POISON
    rom[42] = 32'h004F8F93;  // L3: addi x31, x31, 4
    rom[43] = 32'h0041D463;  // bge   x3, x4, +8    (taken)
    rom[44] = 32'h400F8F93;  // addi  x31, x31, 0x400  POISON
    rom[45] = 32'h008F8F93;  // L4: addi x31, x31, 8
    rom[46] = 32'h0041E463;  // bltu  x3, x4, +8    (taken; 100 <u 0xFFFFFFCE)
    rom[47] = 32'h400F8F93;  // addi  x31, x31, 0x400  POISON
    rom[48] = 32'h010F8F93;  // L5: addi x31, x31, 16
    rom[49] = 32'h00327463;  // bgeu  x4, x3, +8    (taken)
    rom[50] = 32'h400F8F93;  // addi  x31, x31, 0x400  POISON
    rom[51] = 32'h020F8F93;  // L6: addi x31, x31, 32
    rom[52] = 32'h00418463;  // beq   x3, x4, +8    (NOT taken; fall through)
    rom[53] = 32'h040F8F93;  // addi  x31, x31, 64  (must execute)
    rom[54] = 32'h00319463;  // L7: bne x3, x3, +8  (NOT taken; fall through)
    rom[55] = 32'h080F8F93;  // addi  x31, x31, 128 (must execute) -> x31 = 0xFF
    // ---- JAL / JALR subroutine ----
    rom[56] = 32'h00C0086F;  // L8: jal x16, +12    (call SUB; link x16 = 0xE4; x5 keeps ADD result)
    rom[57] = 32'h100F8F93;  // addi  x31, x31, 256 (after return -> x31 = 0x1FF)
    rom[58] = 32'h00C0006F;  // jal   x0, +12       (J DONE; skip subroutine body)
    rom[59] = 32'h40418333;  // SUB: sub x6, x3, x4 (x6 = 150; tests SUB + proves the call ran)
    rom[60] = 32'h00080067;  // jalr  x0, 0(x16)    (return via x16)
    // ---- SYSTEM / FENCE decode-as-NOP coverage ----
    rom[61] = 32'h0000000F;  // DONE: fence
    rom[62] = 32'h00000073;  // ecall
    // ---- park ----
    rom[63] = 32'h00000063;  // beq   x0, x0, 0     (self-loop; PC parks at 0xFC)
  end

endmodule

`default_nettype wire
