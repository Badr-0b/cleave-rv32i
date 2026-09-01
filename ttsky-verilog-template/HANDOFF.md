# HANDOFF — Cleave RV32I, Step 2 (TinyTapeout wrapper + info.yaml scaffold)

## 1. Summary
Scaffolded the TinyTapeout SKY130 wrapper for the **Cleave** RV32I single-cycle core as a
**compilable skeleton only**. Created a top module `tt_um_cleave` that matches the template's
exact TinyTapeout interface, instantiates a tied-off stub core `cleave_core`, drives every
output so nothing floats, and converts the platform's active-low reset to an active-high reset
for the core. Updated `info.yaml` to point at the new top module and source files with a
provisional pin mapping. The design elaborates cleanly under Icarus Verilog. **No CPU/datapath
logic, no functional testbench, no simulation, no git, and no GDS were done** — those are yours.

## 2. Files created
- `src/tt_um_cleave.v` — TinyTapeout top-level wrapper (skeleton).
- `src/cleave_core.v` — RV32I core stub (no datapath; the seam for your design).
- `HANDOFF.md` — this document (repo root of `ttsky-verilog-template/`).

## 3. Files modified
### `info.yaml` — changed keys (before → after)
```
title:        ""                    →  title:        "Cleave RV32I Single-Cycle Core"
author:       ""   # Your name      →  author:       ""   # TODO: fill in your name   (left blank on purpose)
top_module:  "tt_um_example"        →  top_module:  "tt_um_cleave"

source_files:                          source_files:
  - "project.v"                    →     - "tt_um_cleave.v"
                                         - "cleave_core.v"
```
`pinout:` block — filled provisionally (see §5). `ui[0..7]` → `core_in[0..7]`,
`uo[0..7]` → `core_dbg[0..7]`, `uio[0..7]` left blank. A `# PROVISIONAL` banner comment was
added above the `pinout:` key. `language` was already `"Verilog"` (unchanged). `yaml_version: 6`
untouched.

**No other files were modified.** `src/config.json` and `test/Makefile` were **not** touched.

### Example file retained (not deleted)
`src/project.v` (the original `tt_um_example` top) is **kept on disk but is no longer referenced**
by `info.yaml`'s `source_files`. It will not be compiled/synthesized. Delete it yourself whenever
you like; it was left in place per the step-2 constraint against deleting template files.

## 4. Confirmed TinyTapeout top-level interface (as READ from `src/project.v`)
Read from the template's own example top `tt_um_example`. Every port, width, direction:

| Port     | Width | Dir    | Notes                                                        |
|----------|-------|--------|-------------------------------------------------------------|
| `ui_in`  | [7:0] | input  | Dedicated inputs                                            |
| `uo_out` | [7:0] | output | Dedicated outputs                                          |
| `uio_in` | [7:0] | input  | Bidirectional IOs, input path                              |
| `uio_out`| [7:0] | output | Bidirectional IOs, output path                            |
| `uio_oe` | [7:0] | output | Bidirectional IOs, output-enable (active high: 0=in, 1=out)|
| `ena`    | 1     | input  | Always 1 when powered; can be ignored                     |
| `clk`    | 1     | input  | Clock                                                      |
| `rst_n`  | 1     | input  | Reset, **active LOW**                                      |

**Difference from assumed interface: NONE.** The names, widths, and directions matched the
described interface exactly. (The only surprise was the file name: the example top is in
`src/project.v`, and the module is named `tt_um_example` — there is no `tt_um_example.v`.)

## 5. PROPOSED pin mapping — **PROVISIONAL — user must approve/change**
| Pin(s)        | Direction | Provisional meaning                              | Wrapper signal            |
|---------------|-----------|--------------------------------------------------|---------------------------|
| `ui_in[7:0]`  | in        | External control/data input bus into the core    | → `cleave_core.core_in`   |
| `uo_out[7:0]` | out       | Core debug/status byte                           | ← `cleave_core.core_dbg`  |
| `uio_in[7:0]` | in        | Unused for now                                   | tied off (in `_unused`)   |
| `uio_out[7:0]`| out       | Unused — driven to `8'h00`                        | `assign uio_out = 8'h00`  |
| `uio_oe[7:0]` | out       | All bidir pins set as **inputs** (`0` = input)   | `assign uio_oe  = 8'h00`  |
| `ena`         | in        | Ignored (always 1 when powered)                  | in `_unused`              |
| `clk`         | in        | Clock, passed straight to core                   | → `cleave_core.clk`       |
| `rst_n`       | in        | Reset, converted to active-high (see §7)         | → `~rst_n` → `core.rst`   |

This mapping is a starting proposal, not final. Change it when you decide how the core is
actually driven/observed (e.g. serial load, opcode window, debug bus, etc.).

## 6. `cleave_core` stub port list + where you plug in the datapath
```verilog
module cleave_core (
    input  wire       clk,       // core clock
    input  wire       rst,       // active-HIGH reset
    input  wire [7:0] core_in,   // external control/data input bus (from ui_in)
    output wire [7:0] core_dbg   // debug/status byte (to uo_out)
);
```
Currently `assign core_dbg = 8'h00;` and all inputs are absorbed by an `_unused` wire.

**Build your datapath in `src/cleave_core.v`, at the marker:**
```
// ==========================================================================
// TODO: user implements datapath here
//   - program counter / instruction fetch
//   - instruction decode
//   - 32x32 register file
//   - ALU
//   - control unit
//   - drive core_dbg from a real status/debug source
// ==========================================================================
```
Widen/rename the port list as your real interface firms up, then update the instantiation in
`src/tt_um_cleave.v` and the pin mapping in `info.yaml` to match. When you start driving
`core_dbg` and consuming `core_in`/`clk`/`rst` for real, drop them from the stub's `_unused`
wire so the linter can catch genuinely dangling signals.

## 7. Reset polarity decision
- **Platform:** TinyTapeout supplies `rst_n`, **active LOW**.
- **Core:** `cleave_core` declares `rst`, **active HIGH** (common core convention; whether it is
  used synchronously or asynchronously is your call inside the core).
- **Conversion site:** in `src/tt_um_cleave.v`:
  ```verilog
  wire rst = ~rst_n;   // active-low platform reset -> active-high core reset
  ```

## 8. Elaboration check (compile only — NOT functional sim)
- **Result: PASS** (exit code 0, no errors, no warnings). Output object file produced.
- `iverilog` was not on the shell PATH; it is installed at
  `C:\msys64\mingw64\bin\iverilog.exe` and needs the msys64 mingw64 `bin` on PATH for its DLLs.
- **Exact command run (PowerShell, from `ttsky-verilog-template/`):**
  ```powershell
  $env:PATH = "C:\msys64\mingw64\bin;" + $env:PATH
  & "C:\msys64\mingw64\bin\iverilog.exe" -o "$env:TEMP\tt_elab_check.out" src\tt_um_cleave.v src\cleave_core.v
  ```
- Equivalent to the plan's `iverilog -o /tmp/tt_elab_check.out src/tt_um_cleave.v src/cleave_core.v`
  once `iverilog` is on PATH. No functional testbench was written or run.

## 9. Next steps for the user (do these yourself)
1. **Design the core** inside `src/cleave_core.v` — fetch, decode, 32×32 register file, ALU,
   control, and (if needed) a memory/instruction interface. Update `core_in`/`core_dbg` (or the
   whole port list) to the real interface and adjust the instantiation in `tt_um_cleave.v`.
2. **Finalize the pin mapping** in `info.yaml` (`pinout:` block) once the real I/O is known, and
   remove the "PROVISIONAL" banner.
3. **Update `test/Makefile`** — set `PROJECT_SOURCES` to `tt_um_cleave.v cleave_core.v` (plus any
   new source files) so cocotb sim picks them up. *(Intentionally left for you — out of step 2.)*
4. **Write a testbench** and **run functional simulation** (iverilog + GTKWave, or the template's
   cocotb `test/` flow).
5. Only after functional sign-off: hardening / GDS (qflow, OpenROAD / the template's GDS flow).
