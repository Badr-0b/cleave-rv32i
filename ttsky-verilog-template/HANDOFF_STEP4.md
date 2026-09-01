# HANDOFF — Cleave RV32I, Step 4 (verification complete → entering backend)

**Date:** 2026-09-01
**Scope:** Design-only PoC → DRC/LVS-clean GDSII (no shuttle, no fab). Supersedes `HANDOFF_STEP3.md`
(kept for history; it predates the finished datapath and is stale). Forward roadmap: `WHATS_NEXT.md`.
Stage checklist: `../PROJECT_STAGES.md`.

## 1. Locked decisions (unchanged)
- **ISA:** full RV32I base integer. FENCE/ECALL/EBREAK decode as NOPs. No CSR, no traps, no pipelining,
  no external bus. On-chip ROM + byte-addressable RAM.
- **Regfile:** full 32×32 (x0 = 0, `regs[1:31]` — dead x0 storage dropped).
- **Backend:** qflow stack (Yosys, graywolf, qrouter, Magic, netgen, OpenSTA) → Magic DRC clean + netgen
  LVS clean + OpenSTA sign-off, against `sky130_fd_sc_hd`. Render via KLayout/GDS3D. **No OpenLane.**

## 2. Status — RTL complete + functionally proven ✅
All build stages A–K are **done and integrated** — `cleave_core.v` is the real single-cycle datapath
(fetch→decode→regfile→ALU→dmem→writeback, next-PC mux with branch/JAL/JALR sharing the ALU adder,
debug read-out port), **not** the stub `HANDOFF_STEP3.md` described.

| Area | State |
|------|-------|
| Leaf modules (pc, imem, regfile, alu, immgen, branch, control, dmem) | ✅ done, unit-benched |
| `cleave_core.v` integration | ✅ done |
| `tt_um_cleave.v` wrapper | ✅ wires the real core (its header comment still says "SKELETON" — stale, cosmetic) |
| **Proof program** | ✅ baked into `cleave_imem.v` (64 words), exercises every instruction group, parks at `BEQ x0,x0,0` @ PC 0xFC |
| **Unit + integration tests** | ✅ **10/10** via `test/unit/run_unit_tests.ps1` |
| **Waveforms** | ✅ captured (see §4) |
| **Synthesis sanity** | ✅ standalone yosys → sky130 (`synth/`) — reference only; qflow re-synthesizes from RTL |

**Proof program is generated** by `test/gen/asm.py` (an independent RV32I assembler + ISS). It is
load-bearing: to change the program, edit `asm.py`, re-run it, and repaste the ROM lines into
`src/cleave_imem.v` and the golden array into `test/unit/tb_cleave_proof.v`. The bench asserts all 32
registers + data-memory words + PC-park against the ISS golden, with negative controls (poison
instructions behind each taken branch; verified to FAIL when the RTL is broken).

## 3. Key encodings (still the source of truth for the datapath)
- **`alu_ctrl` (4 bits):** `{instr[30], funct3}` for R-type. ADD=0000, SUB=1000, SLL=0001, SLT=0010,
  SLTU=0011, XOR=0100, SRL=0101, SRA=1101, OR=0110, AND=0111.
- **`imm_sel` (3 bits):** I=000, S=001, B=010, U=011, J=100 (immgen `default` = don't-care X).
- **Reset:** wrapper converts TinyTapeout active-low `rst_n` → active-high `rst`; `cleave_pc` resets PC=0.
- **Observability:** `ui_in[4:0]`=register select, `ui_in[6:5]`=byte select → `uo_out` byte.

## 4. How to verify (env)
- **Sim:** `iverilog`/`vvp` at `C:\msys64\mingw64\bin` (that dir on PATH for its DLLs). Full suite:
  `powershell -File test\unit\run_unit_tests.ps1` → 10/10.
- **Waveforms:** compile `tb_cleave_proof.v` with `-DSIMULATION -DDUMP` → emits `cleave_proof.vcd`; open in
  GTKWave with the `cleave.gtkw` view (shows PC stepping, instr, regfile writes, branch flags, debug out).
  The brief red/X at t=0 is the pre-reset state and is expected. (`.vcd/.vvp/.gtkw` are gitignored.)
- **Synthesis (sanity):** `synth/synth.ys` via the oss-cad-suite yosys — prepend both
  `oss-cad-suite\bin` **and** `oss-cad-suite\lib` to PATH (libreadline8.dll lives in `lib`).

## 5. Immediate next step — Phase 3 backend (qflow → sky130, in WSL2)
Follow **`docs/qflow-sky130-runbook.md`** (local/gitignored):
1. Setup: create a qflow project, copy the 10 `src/*.v` into `source/`, point `qflow_vars.sh` at the
   open_pdks-generated tech (`techname=sky130_fd_sc_hd`, `techdir=…/sky130A/libs.tech/qflow`). No
   open_pdks rebuild needed.
2. Flow: `qflow gui` (recommended) or CLI `synthesize → place → route → sta → migrate → drc → gdsii → lvs
   tt_um_cleave`. Relaxed clock (30–50 ns) and low utilization (~30–40%); expect a long qrouter run
   (~3.1k flops, ~0.34 mm² die).

## 6. Definition of done
Magic **DRC clean** + netgen **LVS clean** (vs the synthesized netlist) + OpenSTA timing pass at the
chosen clock → `tt_um_cleave.gds` → optional KLayout/GDS3D render + portfolio writeup.
