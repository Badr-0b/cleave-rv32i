riscv_core_project/
├── src/                     # Your RTL and timing constraints
│   ├── top.v                # Top-level RISC-V module wrapper
│   ├── alu.v, decode.v...   # CPU sub-modules
│   └── constraints.sdc      # Synopsys Design Constraints (clocks, delays)
├── config/                  # Flow configuration
│   └── config.tcl           # OpenROAD setup, PDK pointers, die area
├── macros/                  # Hard macros (if applicable)
│   ├── sram_32x2048.lef     # Abstract views of SRAM/custom blocks
│   └── sram_32x2048.gds     # Physical layouts of macros
└── runs/                    # Generated sequentially by the EDA flow
    └── RUN_2026.08.26/
        ├── 1-synthesis/     
        ├── 2-floorplan/     
        ├── 3-placement/     
        ├── 4-cts/           
        ├── 5-routing/       
        └── 6-signoff/


