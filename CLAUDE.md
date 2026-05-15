# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Xilinx Vivado FPGA project implementing a **JPEG-LS lossless/near-lossless image encoder** with a parallel 3-encoder architecture. Target device: Xilinx Artix-7 (xc7a200tfbg676-2).

Standard: JPEG-LS (ISO/IEC 14495). Test images use `.pgm` (Netpbm P5) format; output is `.jls` bitstream.

## Build & Simulation

This project uses the **Vivado GUI/TCL flow** — there is no Makefile or CMake.

**Open project:**
```
vivado JPEG_ENC_8f.xpr
```

**Run synthesis (TCL console inside Vivado):**
```tcl
launch_runs synth_1
wait_on_run synth_1
```

**Run implementation:**
```tcl
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
```

**Run simulation (xsim):**
```tcl
launch_simulation
run all
```

Simulation scripts for other simulators (modelsim, questa, activehdl, riviera) are in `JPEG_ENC_8f.ip_user_files/sim_scripts/`.

**Single testbench run from command line:**
```bash
xsim JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_jls_encoder.wdb -R
```

## Source Layout

```
JPEG_ENC_8f.srcs/
  sources_1/new/        ← Active user modules (edit these)
  sources_1/imports/    ← Legacy imported modules
  sim_1/imports/        ← Testbench
  constrs_1/imports/new/top_jls_vertical.xdc  ← Pin/timing constraints
JPEG_ENC_8f.gen/        ← Generated IP (BRAM, FIFO, Clock Wizard) — do not edit
JPEG_ENC_8f.runs/       ← Build artifacts
```

## Architecture

### Encoding Pipeline

```
External pixels
      │
      ▼
block_split.v          ← Maps (x,y) coordinates → encoder block index
      │
      ▼ (3 streams)
fifo_wrapper_input.v   ← 3× async input FIFOs (CDC: wr_clk → rd_clk)
      │
      ▼
fifo_read_control.v    ← FSM gating FIFO reads: SOF→READ→GAP→DONE
      │
      ▼
encoder_wrapper.v      ← Instantiates N_E=3 jls_encoder2 cores
      │
      ▼ (3 streams)
fifo_wrapper_output.v  ← 3× async output FIFOs (16-bit compressed words)
      │
      ▼
Compressed JPEG-LS bitstream (3 parallel segments)
```

`image_generator.v` provides test pixels from a BRAM (`blk_mem_gen_0`) during simulation. `fifo_reset_bram_async.v` sequences FIFO resets against clock lock, asserting `sys_rdy` when safe to start.

### jls_encoder2.v — Core Algorithm (1392 lines)

The heart of the design. Implements a **10-stage pipeline** processing one pixel per clock cycle:

| Stage | Function |
|-------|----------|
| A | Pixel coordinate generation (ii, jj) |
| B | Line/frame flags (fc, lc, nfr) |
| C | Line buffer read → context pixels (a, b, c, d) |
| D | Context fixup, quantized prediction (qp1) |
| E | Error computation and reconstruction loop |
| F | Context RAM update (N, B, C tables); run/regular decision; Golomb k |
| G | Golomb coding |
| H | Bitstream merge (57-bit shift register) |
| J | Byte output with 0xFF stuffing |
| K | JPEG-LS header/footer insertion (FFD8/FFD9 markers) |

Key parameters:
- `NEAR` — 0 = lossless, 1–7 = near-lossless tolerance
- `N_E` — number of parallel encoders (default 3)
- `L` — slice height in lines (default 64)
- 366 contexts per encoder, each holding N/A/B/C tables

### Block Geometry

The image is divided into a **3×3 grid** (3 horizontal × 3 vertical blocks). The 9 blocks are distributed across 3 encoders. `fifo_write_control.v` maps pixel (x,y) → encoder block and tracks exact pixel counts per slice. `fifo_read_control.v` mirrors this on the read side.

### Clock Domains

| Domain | Frequency | Usage |
|--------|-----------|-------|
| `wr_clk` | 100 MHz | Input pixel writes |
| `rd_clk` | 10 MHz | Encoder operation |
| `clk_in` | 200 MHz differential | Board input → clk_wiz_0 |

All clock domain crossings use async FIFOs or toggle synchronizers.

## Key Design Constraints

- **Line buffer depth:** 16384 entries (2^14) — limits max image width.
- **Context memory:** 366 entries × (N+A+B+C fields) per encoder — sized for JPEG-LS Appendix C.
- **0xFF byte stuffing:** Required by JPEG-LS spec; handled in Stage J of the pipeline.
- **Golomb J-table:** 32-entry lookup hardcoded in the encoder.
- The XDC file maps the differential clock to pins R3/P3, single-ended clock to E17, and reset to R8.

## Testbench

`sim_1/imports/FPGA Encoders/tb_jls_encoder.v` drives the DUT:
- Loads a `.pgm` file and streams pixels via AXI-Stream-like handshake (`i_e`/`i_last`).
- Configurable `NEAR` parameter and bubble insertion (randomized gaps to stress flow control).
- Captures compressed output to a `.jls` file for validation.
