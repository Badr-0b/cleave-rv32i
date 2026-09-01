/*
 * Copyright (c) 2026 Cleave project
 * SPDX-License-Identifier: Apache-2.0
 *
 * cleave_pc — program counter register for the Cleave RV32I single-cycle core.
 *
 * Holds the current instruction address. On active-HIGH reset the PC returns to
 * 0 (the reset vector); otherwise it latches pc_next on every rising clock edge.
 * Single-cycle: exactly one instruction is fetched and retired per clock, so
 * pc_next is simply whatever the core's next-PC mux selects (pc+4, branch/jump
 * target, etc.).
 */

`default_nettype none

module cleave_pc (
    input  wire        clk,       // core clock
    input  wire        rst,       // active-HIGH synchronous reset
    input  wire [31:0] pc_next,   // next-PC value from the core's next-PC mux
    output reg  [31:0] pc         // current program counter
);

  always @(posedge clk) begin
    if (rst)
      pc <= 32'h0000_0000;        // reset vector
    else
      pc <= pc_next;
  end

endmodule

`default_nettype wire
