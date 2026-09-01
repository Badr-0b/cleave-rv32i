/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_regfile — 32 x 32-bit register file for the Cleave RV32I core.
 *
 * Two combinational read ports (rs1/rs2) so the single-cycle datapath gets both
 * source operands in the same cycle it fetches. One synchronous write port that
 * commits on the rising clock edge when write-enable is asserted. x0 is the RISC-V
 * zero register: it always reads 0 and is never written. That is enforced two ways
 * for robustness on ASIC flops (which have no guaranteed power-up value): a read
 * mux forces 0 for address 0, and the write path is guarded so index 0 is never
 * updated. A third read-only debug port (dbg_rs -> dbg_data) lets test programs be
 * observed from outside the core.
 */

`default_nettype none

module cleave_regfile (
    input  wire        clk,       // core clock (write port only)
    input  wire        we,        // write enable
    input  wire [4:0]  rs1,       // read address 1
    input  wire [4:0]  rs2,       // read address 2
    input  wire [4:0]  rd,        // write address
    input  wire [31:0] wd,        // write data
    output wire [31:0] rd1,       // read data 1
    output wire [31:0] rd2,       // read data 2
    input  wire [4:0]  dbg_rs,    // debug read address (observability)
    output wire [31:0] dbg_data   // debug read data
);

  // 1. Area Optimization: Only instantiate registers x1 through x31
  reg [31:0] regs [1:31];

  // 3. Simulation Optimization: Prevent 'X' propagation during early testing
`ifdef SIMULATION
  integer i;
  initial begin
    for (i = 1; i < 32; i = i + 1) begin
      regs[i] = 32'h0;
    end
  end
`endif

  // Combinational read ports: x0 reads as 0, everything else reads the array.
  // Plain reads (no same-cycle write-through): single-cycle semantics need the
  // OLD register value here — the new value is written on this cycle's posedge.
  // Forwarding wd would create a combinational loop when rd == rs1/rs2, since wd
  // is itself computed from these read outputs.
  assign rd1 = (rs1 == 5'd0) ? 32'h0 : regs[rs1];

  assign rd2 = (rs2 == 5'd0) ? 32'h0 : regs[rs2];

  // Debug port doesn't strictly need write-through, but keeping it consistent is fine
  assign dbg_data = (dbg_rs == 5'd0) ? 32'h0 : regs[dbg_rs];

  // Synchronous write, guarded so x0 (index 0) is never modified
  always @(posedge clk) begin
    if (we && (rd != 5'd0)) begin
      regs[rd] <= wd;
    end
  end

endmodule

`default_nettype wire
