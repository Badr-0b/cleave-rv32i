# Cleave RV32I — module unit tests

Self-checking Icarus Verilog benches for each RTL block, one file per module. These
are fast, deterministic, and independent of the cocotb flow in the parent `test/`
directory (which drives the whole `tt_um_cleave` design). Run these while building and
before every commit.

## Run

```powershell
powershell -File test\unit\run_unit_tests.ps1
```

The runner compiles and runs every `tb_<module>.v` against its source in `../../src`,
prints a per-module PASS/FAIL table, and exits non-zero if anything fails (CI-friendly).
Build artifacts land in `test/unit/build/` (git-ignored).

To run one module by hand (example, control unit):

```powershell
$env:PATH = "C:\msys64\mingw64\bin;" + $env:PATH
iverilog -g2012 -DSIMULATION -o build\ctl.vvp test\unit\tb_cleave_control.v src\cleave_control.v
vvp build\ctl.vvp
```

`-DSIMULATION` is passed so `cleave_regfile` zero-initializes its array for
deterministic reads; it is harmless for the other modules.

## Coverage

| Bench | Module | What it checks |
|-------|--------|----------------|
| `tb_cleave_pc.v`      | `cleave_pc`      | reset→0, latches `pc_next`, re-reset |
| `tb_cleave_imem.v`    | `cleave_imem`    | baked program, byte→word index, address wrap |
| `tb_cleave_regfile.v` | `cleave_regfile` | write/readback, x0=0, dual reads, debug port, we=0 |
| `tb_cleave_alu.v`     | `cleave_alu`     | 10 ops, ADD/SUB wrap, shift sign-ext + shamt mask, SLT/SLTU, zero |
| `tb_cleave_immgen.v`  | `cleave_immgen`  | I/S/B/U/J reassembly + sign extension |
| `tb_cleave_branch.v`  | `cleave_branch`  | 6 conditions, signed/unsigned divergence, boundaries |
| `tb_cleave_control.v` | `cleave_control` | full decode vector, don't-care contract, illegal-opcode flag |

### Note on the control-unit bench

`cleave_control` deliberately drives some outputs to `x` (don't-care) where a signal is
unused for a given opcode, so synthesis can minimize logic. The bench uses a **masked
comparator**: expected fields marked `x` are skipped, but every *defined* field must
match exactly — so an *unintended* `x` in a required signal still fails. This matches the
RTL's optimization contract instead of fighting it.
