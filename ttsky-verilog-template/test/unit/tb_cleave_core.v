/*
 * Integration test — cleave_core (full single-cycle datapath).
 * Compile with -DSIMULATION (regfile + dmem zero-init deterministically).
 *
 * Loads a hand-assembled micro-program directly into the instruction ROM via a
 * hierarchical assignment (sim-only) so a real program runs without disturbing
 * cleave_imem's committed placeholder contents. The program exercises the whole
 * integration — I-type + R-type ALU, a data-RAM store/load round-trip, and a
 * not-taken branch — then parks in a self-loop. Results are read back through the
 * observability port (core_in[4:0]=reg, core_in[6:5]=byte) and checked.
 *
 * Teeth / negative controls:
 *   - x5 == 0xAA proves the not-taken branch fell through (a broken branch-taken
 *     redirect would skip the instruction and leave x5 == 0).
 *   - x4 == 0x128 proves the dmem store->load round-trip.
 *   - PC parks at the self-loop and does not advance (checked hierarchically).
 *   - x0 reads 0.
 * Verified to fail when it should (forcing branch always-taken breaks the x5/park
 * checks) before trusting the pass.
 *
 *   [0] ADDI x1, x0, 0x123     x1 = 0x123
 *   [1] ADDI x2, x0, 5         x2 = 5
 *   [2] ADD  x3, x1, x2        x3 = 0x128
 *   [3] SW   x3, 0(x0)         mem[0] = 0x128
 *   [4] LW   x4, 0(x0)         x4 = 0x128
 *   [5] BEQ  x1, x2, +8        not taken (x1 != x2)
 *   [6] ADDI x5, x0, 0xAA      x5 = 0xAA  (executed => branch not taken)
 *   [7] BEQ  x0, x0, 0         self-loop (park)
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_core;
  reg        clk = 1'b0;
  reg        rst;
  reg  [7:0] core_in;
  wire [7:0] core_dbg;
  integer    errors = 0;

  cleave_core u_dut (
    .clk(clk), .rst(rst), .core_in(core_in), .core_dbg(core_dbg)
  );

  always #5 clk = ~clk;

  // Read a full 32-bit register through the byte-wide debug port.
  task read_reg(input [4:0] r, output [31:0] val);
    begin
      core_in = {1'b0, 2'b00, r}; #1; val[7:0]   = core_dbg;
      core_in = {1'b0, 2'b01, r}; #1; val[15:8]  = core_dbg;
      core_in = {1'b0, 2'b10, r}; #1; val[23:16] = core_dbg;
      core_in = {1'b0, 2'b11, r}; #1; val[31:24] = core_dbg;
    end
  endtask

  task check(input [31:0] got, input [31:0] exp, input [8*40-1:0] name);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %h exp %h", name, got, exp);
        errors = errors + 1;
      end else $display("ok   %0s", name);
    end
  endtask

  reg [31:0] v;
  reg [31:0] pc_parked;

  initial begin
    rst = 1'b1; core_in = 8'h00;
    #1;  // let cleave_imem's time-0 initial populate the ROM first

    // Overwrite the ROM with our program (hierarchical, sim-only).
    u_dut.u_imem.rom[0] = 32'h1230_0093;  // ADDI x1, x0, 0x123
    u_dut.u_imem.rom[1] = 32'h0050_0113;  // ADDI x2, x0, 5
    u_dut.u_imem.rom[2] = 32'h0020_81B3;  // ADD  x3, x1, x2
    u_dut.u_imem.rom[3] = 32'h0030_2023;  // SW   x3, 0(x0)
    u_dut.u_imem.rom[4] = 32'h0000_2203;  // LW   x4, 0(x0)
    u_dut.u_imem.rom[5] = 32'h0020_8463;  // BEQ  x1, x2, +8
    u_dut.u_imem.rom[6] = 32'h0AA0_0293;  // ADDI x5, x0, 0xAA
    u_dut.u_imem.rom[7] = 32'h0000_0063;  // BEQ  x0, x0, 0  (self-loop)

    // Hold reset a couple of cycles, then run.
    repeat (2) @(negedge clk);
    rst = 1'b0;
    repeat (20) @(negedge clk);            // ample time to reach the park

    // ---- Check register results via the debug port ----
    read_reg(5'd1, v); check(v, 32'h0000_0123, "x1 = ADDI 0x123");
    read_reg(5'd2, v); check(v, 32'h0000_0005, "x2 = ADDI 5");
    read_reg(5'd3, v); check(v, 32'h0000_0128, "x3 = ADD x1+x2");
    read_reg(5'd4, v); check(v, 32'h0000_0128, "x4 = LW (dmem round-trip)");
    read_reg(5'd5, v); check(v, 32'h0000_00AA, "x5 = ADDI 0xAA (branch not taken)");
    read_reg(5'd0, v); check(v, 32'h0000_0000, "x0 stays 0");

    // ---- PC parked at the self-loop and stays put ----
    pc_parked = u_dut.u_pc.pc;
    check(pc_parked, 32'h0000_001C, "PC parked at self-loop 0x1C");
    repeat (5) @(negedge clk);
    check(u_dut.u_pc.pc, 32'h0000_001C, "PC still parked after more clocks");

    if (errors == 0) $display("\nALL cleave_core TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
