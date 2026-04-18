# 64-bit Priority Encoder: DFT & ATPG Workflow

This repository contains the design, testbench, synthesis, and Design-for-Test (DFT) implementation for a 64:6 Scalable Lookahead Priority Encoder with pipelined registered I/O. The project showcases a complete ASIC verification and testing flow utilizing **Cadence Genus** (for synthesis and scan insertion) and **Cadence Modus** (for ATPG fault simulating and test vector generation).

## Architecture Overview

The core module `pe64_top` encapsulates:
- **Input Pipeline**: 64 D-Flip-Flops for data inputs `d[63:0]` and 1 for the `enable` signal.
- **Priority Logic**: A purely combinational 64:6 lookahead priority encoder hierarchy (utilizing 4:2 block instances).
- **Output Pipeline**: 6 D-Flip-Flops for the encoded output `q[5:0]` and 1 for the `valid` flag.

**Total Scannable Elements:** 72 Flip-Flops.

## Repository Structure

- `rtl/`: Contains the Verilog source `pe64_top.v` with hierarchical components.
- `tb/`: Functional testing verification testbench `pe64_top_tb.v`.
- `constraints/`: `.sdc` timing constraints tailored for 90nm slow operating conditions (100MHz target).
- `scripts/`: Tcl automation bindings.
  - `run_genus_dft_pe64.tcl` — Genus synthesis, DFT scan replacement, and mapping.
  - `runmodus.atpg.tcl` — Modus logic testing, ATPG parallel vector extraction.
- `netlists/`: Post-synthesis unflattened and flattened (test) structural netlists alongside SDF and SCANDEF files.
- `reports/`: Exported logs and analysis on Area, Power, Gates, and ATPG Fault Coverage from Genus/Modus.
- `docs/`: Original coursework/presentation report `ATPG_DFT_Fault_simulation_vikramaditya.pdf`.

## DFT Scan Insertion details

During synthesis with Cadence Genus, we utilize `muxed_scan` mapping style:
- **Target clock:** Derived test clock domain mapping from `clk`.
- **Shift enable:** Configured natively to the `scan_en` port.
- **Scan chain length:** Single chain of 72 `SDFFQXL` elements ensuring a 100% coverage map.

## Usage

1. Open a terminal authenticated with the Cadence EDA Toolchain.
2. Formulate logic via Genus:
   ```bash
   genus -f scripts/run_genus_dft_pe64.tcl
   ```
3. Pass extracted structural test netlist to Modus:
   ```bash
   modus -f scripts/runmodus.atpg.tcl
   ```
