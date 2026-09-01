/*
 * Integration PROOF bench — cleave_core running the committed cleave_imem program.
 * Compile with -DSIMULATION (regfile + dmem zero-init deterministically).
 *
 * Unlike tb_cleave_core.v (which overwrites the ROM with a tiny smoke program),
 * this bench runs the REAL proof program baked into cleave_imem.v — the exact
 * bits that get synthesized — and asserts the full architectural end state against
 * a golden model produced by an independent assembler+ISS (see scratchpad asm.py,
 * summarized in cleave_imem.v). It is the Stage-K "working RV32I in sim" proof.
 *
 * What it checks (end-to-end, after the program parks at BEQ x0,x0,0 @ 0xFC):
 *   - All 32 architectural registers x0..x31 == golden (via the debug read-out
 *     port). This transitively covers every ALU op, LUI/AUIPC, all load widths,
 *     and the JAL/JALR link values.
 *   - Data memory words written by SW/SB/SH == golden (hierarchical peek).
 *   - PC parked at the self-loop (0xFC) and does not advance on further clocks.
 *
 * Teeth / negative controls (verified to FAIL when the RTL is broken):
 *   - x31 == 0x1FF is a control-flow signature. Each taken branch jumps over a
 *     POISON `addi x31,x31,0x1xx`; if any taken branch were mis-decoded as
 *     not-taken, a poison bit (0x100/0x200/0x400) would appear in x31. If a
 *     not-taken branch were mis-taken, the +64/+128 fall-through adds would be
 *     skipped. If JAL/JALR mis-linked or mis-returned, the +256 (0x100) after
 *     return would be lost or the program would diverge. Any of these breaks x31.
 *   - x6 == 0x96 (SUB result, computed in the subroutine body) proves the JAL/JALR
 *     subroutine actually ran and returned; x5 == 0x32 asserts the R-type ADD result.
 *   - illegal_instr must never assert while valid code runs (checked live).
 *   - x0 reads 0.
 * Confirmed to fail-when-it-should (e.g. forcing cleave_branch.take=1 breaks the
 * x31 signature and the PC-park checks) before trusting the pass.
 */
`default_nettype none
`timescale 1ns/1ps

module tb_cleave_proof;
  reg        clk = 1'b0;
  reg        rst;
  reg  [7:0] core_in;
  wire [7:0] core_dbg;
  integer    errors = 0;

  cleave_core u_dut (
    .clk(clk), .rst(rst), .core_in(core_in), .core_dbg(core_dbg)
  );

  always #5 clk = ~clk;

  // Golden architectural register file (from the independent assembler/ISS).
  reg [31:0] golden [0:31];
  initial begin
    golden[ 0] = 32'h00000000;
    golden[ 1] = 32'h12345000;
    golden[ 2] = 32'h00000054;
    golden[ 3] = 32'h00000064;
    golden[ 4] = 32'hFFFFFFCE;
    golden[ 5] = 32'h00000032;   // ADD  x3+x4 = 50
    golden[ 6] = 32'h00000096;   // SUB  x3-x4 = 150 (subroutine body; proves JAL/JALR call+return)
    golden[ 7] = 32'h00000094;
    golden[ 8] = 32'h00000065;
    golden[ 9] = 32'h00000004;
    golden[10] = 32'h00000001;
    golden[11] = 32'h00000000;
    golden[12] = 32'h00000640;
    golden[13] = 32'h00000019;
    golden[14] = 32'hFFFFFFE7;
    golden[15] = 32'h00000640;
    golden[16] = 32'h000000E4;   // JAL link (return address into the subroutine caller)
    golden[17] = 32'h00000006;
    golden[18] = 32'hFFFFFFFC;
    golden[19] = 32'h00000001;
    golden[20] = 32'h00000001;
    golden[21] = 32'hFFFFFFAA;
    golden[22] = 32'h00000064;
    golden[23] = 32'h00000004;
    golden[24] = 32'h00000010;
    golden[25] = 32'hDEADC0DE;
    golden[26] = 32'hDEADC0DE;
    golden[27] = 32'hFFFFC0DE;
    golden[28] = 32'h0000C0DE;
    golden[29] = 32'hFFFFFFDE;
    golden[30] = 32'h000000C0;
    golden[31] = 32'h000001FF;   // control-flow signature
  end

  // Read a full 32-bit register through the byte-wide debug port.
  task read_reg(input [4:0] r, output [31:0] val);
    begin
      core_in = {1'b0, 2'b00, r}; #1; val[7:0]   = core_dbg;
      core_in = {1'b0, 2'b01, r}; #1; val[15:8]  = core_dbg;
      core_in = {1'b0, 2'b10, r}; #1; val[23:16] = core_dbg;
      core_in = {1'b0, 2'b11, r}; #1; val[31:24] = core_dbg;
    end
  endtask

  task check(input [31:0] got, input [31:0] exp, input [8*48-1:0] name);
    begin
      if (got !== exp) begin
        $display("FAIL %0s: got %h exp %h", name, got, exp);
        errors = errors + 1;
      end else $display("ok   %0s = %h", name, got);
    end
  endtask

  // Live guard: valid code must never decode as an illegal opcode.
  always @(posedge clk)
    if (!rst && u_dut.illegal_instr) begin
      $display("FAIL illegal_instr asserted at pc=%h", u_dut.pc);
      errors = errors + 1;
    end

  reg [31:0] v;
  integer    r;

  // Waveform dump for GTKWave (compile with -DDUMP). Off by default so the
  // regular self-checking run is unaffected.
`ifdef DUMP
  initial begin
    $dumpfile("cleave_proof.vcd");
    $dumpvars(0, tb_cleave_proof);
  end
`endif

  initial begin
    rst = 1'b1; core_in = 8'h00;

    // Hold reset a couple of cycles, then run to the park.
    repeat (2) @(negedge clk);
    rst = 1'b0;
    repeat (80) @(negedge clk);          // ample cycles to reach & settle at park

    // ---- Full architectural register file ----
    for (r = 0; r < 32; r = r + 1) begin
      read_reg(r[4:0], v);
      if (v !== golden[r]) begin
        $display("FAIL x%0d: got %h exp %h", r, v, golden[r]);
        errors = errors + 1;
      end else $display("ok   x%0d = %h", r, v);
    end

    // ---- Data memory: SW / SB / SH results (hierarchical peek) ----
    check(u_dut.u_dmem.ram[4], 32'hDEADC0DE, "mem[word4]  SW");
    check(u_dut.u_dmem.ram[6] & 32'h0000_00FF, 32'h000000DE, "mem[word6]  SB byte");
    check(u_dut.u_dmem.ram[7] & 32'h0000_FFFF, 32'h0000C0DE, "mem[word7]  SH half");

    // ---- PC parked at the self-loop and stays put ----
    check(u_dut.pc, 32'h0000_00FC, "PC parked @ 0xFC");
    repeat (5) @(negedge clk);
    check(u_dut.pc, 32'h0000_00FC, "PC still parked after more clocks");

    if (errors == 0) $display("\nALL cleave_core PROOF TESTS PASSED");
    else begin $display("\n%0d FAILURE(S)", errors); $fatal; end
    $finish;
  end
endmodule

`default_nettype wire
