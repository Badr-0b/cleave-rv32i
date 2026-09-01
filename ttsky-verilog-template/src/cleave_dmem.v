/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_dmem — on-chip data RAM for the Cleave RV32I single-cycle core.
 *
 * The only block the LOAD / STORE instructions talk to. Physically a bank of
 * 32-bit words, but RV32I addresses memory per byte and can move a byte, a
 * half-word, or a full word, so this module does the two jobs that raw storage
 * does not:
 *
 *   1. Sub-word write masking (stores). A byte-strobe wstrb[3:0] derived from the
 *      access size (funct3) and the byte offset (addr[1:0]) enables only the lanes
 *      the store touches; the surrounding bytes of that word keep their value. This
 *      is the natural SRAM write-mask structure — one shared word bank, per-byte
 *      write enables — so it hardens to flops-with-enables (no external RAM macro).
 *      SW -> all four lanes, SH -> the two lanes of the addressed half, SB -> one.
 *
 *   2. Sub-word load extension (loads). The addressed sub-word is selected from the
 *      read word and widened to 32 bits: LB/LH sign-extend, LBU/LHU zero-extend,
 *      LW returns the whole word. The extend lives HERE (not in the core) so all
 *      sub-word / endianness reasoning stays in one unit-tested module and the
 *      datapath just routes a finished 32-bit rdata to writeback.
 *
 * Writes are synchronous (posedge clk, gated by mem_write). Reads are combinational
 * so a load resolves in the same cycle the single-cycle core needs it. There is no
 * mem_read port: rdata is always driven and the core selects it via result_src ==
 * MEM, so a read enable would only add a dead output mux.
 *
 * Little-endian: byte offset 0 is bits [7:0] of the word. Accesses are assumed
 * naturally aligned (RV32I requires it); misaligned addresses are undefined here —
 * there is no trap path in this core, the same treatment as illegal opcodes.
 */

`default_nettype none

module cleave_dmem #(
    parameter integer DEPTH = 64,          // number of 32-bit words (DEPTH*4 bytes)
    parameter integer AW    = 6            // word-index width = log2(DEPTH)
) (
    input  wire        clk,                // core clock (write port only)
    input  wire        mem_write,          // 1 = store this cycle
    input  wire [2:0]  funct3,             // access size + signedness (see below)
    input  wire [31:0] addr,               // byte address = ALU result (rs1 + imm)
    input  wire [31:0] wdata,              // store data = rs2
    output reg  [31:0] rdata               // load result, sign/zero-extended
);

  localparam [2:0] F3_B  = 3'b000,         // LB  / SB
                   F3_H  = 3'b001,         // LH  / SH
                   F3_W  = 3'b010,         // LW  / SW
                   F3_BU = 3'b100,         // LBU
                   F3_HU = 3'b101;         // LHU

  reg [31:0] ram [0:DEPTH-1];

  // Word index, dropping the byte-offset bits [1:0]. The slice is inherently
  // in-range (AW bits index a 2**AW-deep array), so out-of-range byte addresses
  // truncate-and-wrap within the RAM — same convention as cleave_imem.
  wire [AW-1:0] idx = addr[AW+1:2];
  wire [1:0]    off = addr[1:0];

  // ---------------------------------------------------------------------------
  // Store: byte-lane write mask.
  // ---------------------------------------------------------------------------
  reg  [3:0]  wstrb;
  always @(*) begin
    wstrb = 4'b0000;
    if (mem_write) begin
      case (funct3)
        F3_B:    wstrb = 4'b0001 << off;
        F3_H:    wstrb = 4'b0011 << off;
        F3_W:    wstrb = 4'b1111;
        default: wstrb = 4'b0000;
      endcase
    end
  end

  wire [31:0] wdata_aligned = wdata << (8 * off);

  // 1. Explicit unrolling guarantees flawless Yosys byte-enable inference
  always @(posedge clk) begin
    if (wstrb[0]) ram[idx][7:0]   <= wdata_aligned[7:0];
    if (wstrb[1]) ram[idx][15:8]  <= wdata_aligned[15:8];
    if (wstrb[2]) ram[idx][23:16] <= wdata_aligned[23:16];
    if (wstrb[3]) ram[idx][31:24] <= wdata_aligned[31:24];
  end

  // ---------------------------------------------------------------------------
  // Load: select the addressed sub-word from the read word
  // ---------------------------------------------------------------------------
  wire [31:0] word = ram[idx];
  wire [7:0]  lane_b = word[8*off +: 8];
  wire [15:0] lane_h = off[1] ? word[31:16] : word[15:0];

  always @(*) begin
    case (funct3)
      F3_B:    rdata = {{24{lane_b[7]}},  lane_b};
      F3_BU:   rdata = {24'b0,            lane_b};
      F3_H:    rdata = {{16{lane_h[15]}}, lane_h};
      F3_HU:   rdata = {16'b0,            lane_h};
      F3_W:    rdata = word;
      // 2. Mux optimization: Don't care state saves gates for invalid sizes
      default: rdata = 32'bx; 
    endcase
  end

`ifdef SIMULATION
  integer k;
  initial for (k = 0; k < DEPTH; k = k + 1) ram[k] = 32'h0;
`endif

endmodule

`default_nettype wire