# Design: Wide-Input 16-Lane JPEG-LS Encoder (≈512 MB/s)

**Date:** 2026-06-26
**Status:** Approved (pending spec review)
**Target device:** Xilinx Artix-7 `xc7a200tfbg676-2`
**Builds on:** the synthesizable AXI4-Stream IP (`jls_encoder_axis` / `jls_demo_top`) from
`2026-06-26-jls-encoder-axis-synthesizable-design.md` (branch `feature/jls-encoder-axis`).

## Problem / Context

The current synthesizable design closes timing at ~30 MHz encoder clock and ~60 MB/s
(2 lanes, 1 pixel/cycle input). A direct synthesis test at 500 MB/s (500 MHz / 1 byte/cycle)
fails by **WNS −14.5 ns** — the JPEG-LS encoder is inherently **1 pixel/cycle** (causal
prediction: each pixel depends on its left/upper neighbors), so a faster single datapath is
impossible. Throughput must come from **parallel lanes fed by a wide input**.

Feasibility (from `impl_util.rpt` + the IP `.xci` files): per-lane BRAM today is ~66 RAMB36,
**dominated by the FIFOs** (output FIFO 65536-deep = 29 RAMB36/lane, input FIFO 131072-deep =
4), not the line buffer. Those depths only paper over the serial 1-px/cycle feed. With a wide
feed + shallow FIFOs + a line buffer sized to the (now narrow) strip, per-lane BRAM drops to
~5, so **16 lanes fit** (~64–80 RAMB36 ≈ 20%, LUT ~36%, FF ~10%).

## Goal

A **synthesizable, timing-closed** 16-lane JPEG-LS encoder reaching **≈512 MB/s** (512 Mpix/s)
on `xc7a200tfbg676-2`, lossless, verified bit-exact in behavioral sim and built to a bitstream.

## Non-Goals / Out of Scope

- A single faster encoder (architecturally impossible — 1 px/cycle).
- 4 Gb/s at a single byte/cycle (needs 500 MHz; not synthesizable).
- Changing the JPEG-LS encoding math (each lane is the *unchanged* proven encoder core).
- Near-lossless (stays lossless-only; `NEAR=0`, inherited from the AXIS design).
- A general external memory/DMA controller (the wide feed is modeled by an on-chip
  column-strided ROM source for the bitstream; a real DMA is a future integration).

## Decisions (settled during brainstorming)

| Decision | Choice |
|---|---|
| Parallelism | **16 lanes**, vertical column-strips (`N_E=16, N_H=16, N_V=1`) |
| Clock / throughput | `rd_clk` ≈ **32 MHz** → 16 × 32 = **512 Mpix/s**; `wr_clk` ≥ rd (dual-clock retained) |
| Architecture | **Keep dual-clock + splitter + per-lane async FIFOs** (option C), widened |
| Input width | **128-bit** (16 × 8-bit), **column-strided** (one pixel per strip per cycle) |
| Per-lane BRAM | line buffer parameterized to strip width; FIFOs regenerated **shallow** |
| Output | **on-chip sink** (per-lane drain) + `done`/checksum **status pins**; sim captures all 16 |

## Architecture

```
128-bit wide input (16 px/cycle, column-strided: slot j = strip j's current pixel)
        │                                                            [wr_clk]
        ▼
splitter_block (WIDENED): route bus[j] -> lane j for all 16; shared intra-strip
   (x,y) + SOF/line-end; o_e[15:0] all assert each valid cycle
        │ 16 lanes
        ▼
fifo_wrapper_input  (16 async FIFOs, SHALLOW ~512)            [wr_clk -> rd_clk]
        ▼
fifo_read_control + encoder_wrapper  (16 jls_encoder lanes, 1 px/cycle each) [rd_clk]
   per-lane dims: i_w = W/16 (col_w), i_h = H; line buffer depth = LB_DEPTH
        │ 16 lanes
        ▼
fifo_wrapper_output (16 async FIFOs, SHALLOW ~2048) + AXIS-master drain [rd_clk -> wr_clk]
        ▼
on-chip sink: 16x tready=1, per-lane byte-count + rolling checksum, done -> status pins
```

The internal pipeline is **already parameterized over `N_E`/`N_H`/`N_V`**, so 16 lanes
instantiate by parameter; `encoder_wrapper` already computes per-lane `col_w = W/N_H` and
`row_h = H/N_V`. The *new* work is the wide input edge, the BRAM shrink, and the wide harness.

### Wide input + widened splitter
- New top-level input `s_axis_tdata[127:0]` (16 pixels), `s_axis_tvalid`, `s_axis_tready`,
  `s_axis_tlast`, plus sideband `i_w` (full image width), `i_h`, `i_sof`. Each lane's strip
  width is `W/16`.
- The splitter no longer time-multiplexes one pixel via `encoder_sel`. Instead it routes
  `s_axis_tdata[j*8 +: 8] → lane j` for all 16 lanes, asserts all `o_e[15:0]` on a valid
  transfer, and maintains **one shared intra-strip (x,y)** counter (all lanes advance in
  lockstep) driving per-lane SOF (`i_sof_st`) and line-end. Input is accepted when
  `tvalid && tready`, `tready` gated by FIFO-full (any lane full → stall, all lanes lockstep).
- Column-strided ordering: as the shared (x,y) walks the strip raster (x: 0..W/16−1, y++),
  slot j carries strip j's pixel at that (x,y). Each lane thus sees a clean `(W/16)×H` raster
  sub-image — the unchanged encoder core handles it.

### Per-lane BRAM shrink
- **Line buffer** (`jls_encoder.v`): replace `reg [7:0] linebuffer [0:(1<<14)-1]` with a
  parameterized depth `LB_DEPTH` (default **1024**, ≥ max strip width). Max image width =
  16 × 1024 = **16384** (unchanged). Each lane buffers only its strip → 16 lanes use the same
  total line-buffer BRAM as one full-width lane (~8 RAMB36).
- **FIFOs**: regenerate `fifo_generator_0` (input) depth 131072→~512 and `fifo_output`
  (output) depth 65536→~2048. Justification: the wide feed delivers all 16 lanes synchronously
  and the on-chip sink drains at full rate; compressed-word rate per lane is ≪ 1/cycle
  (ratio > 1), so shallow FIFOs never overflow.

### Demo harness (`jls_demo_top`, wide variant) + output
- `axis_image_source` widened to a **128-bit column-strided** synthesizable ROM source
  (ROM laid out so each read yields strip-0..15's pixel at the current (x,y)); drives the
  sideband dims/SOF.
- On-chip **sink**: ties all 16 `m_axis_tready` high, accumulates per-lane byte counts and a
  rolling checksum (e.g. XOR/CRC of output words), raises `done` when all lanes hit `tlast`.
  Exposes `done` + checksum/byte-count (~32 bits) to status pins so synthesis cannot prune the
  lanes and completion is observable on a board.
- New XDC (`jls_demo_top` wide): diff clk (R3/P3), reset (R8), status outputs to pins.

### Clocking
Keep `clk_wiz_0` dual-clock, but run the wide design **1:1** (`wr_clk = rd_clk = 32 MHz`). A
wide design ingests N_E pixels/cycle and the lanes consume N_E pixels/cycle — the **same rate** —
so 1:1 is the natural ratio. Critically, 1:1 also **aligns the two SOF stretches**
(`axis_pixel_in` on wr_clk vs `fifo_read_control` on rd_clk, both 3000 cycles): at any wr>rd
ratio the input finishes SOF in less wall-time and floods the (now shallow) input FIFOs before
the read side drains, and `fifo_write_control` drops pixels at a full FIFO (the old 131072-deep
FIFO masked this; verified failure at 2:1 — encoders starved at ~2661/4096 pixels). 32 MHz × 16
lanes = 512 Mpix/s is exactly the design point. Report the achieved clock + throughput.

## File-level change plan

**Modified RTL**
- `jls_encoder.v` — parameterize line-buffer depth (`LB_DEPTH`, default 1024).
- `block_split.v` — widen to 128-bit input, route 16 pixels/cycle, lockstep (x,y)/SOF.
- `jls_encoder_axis.v` — widen `s_axis_tdata` to 128-bit; params `N_E=16,N_H=16,N_V=1`.
- `fifo_wrapper_input.v` / IP `fifo_generator_0` — shallow input FIFO.
- `fifo_wrapper_output.v` / IP `fifo_output` — shallow output FIFO (AXIS-master drain kept).

**New**
- wide `axis_image_source` (128-bit column-strided ROM source) + interleaved ROM hex.
- on-chip `axis_sink` (per-lane counters + checksum + done).
- wide `jls_demo_top` + `jls_demo_top` wide XDC.
- 16-lane testbench (capture 16 streams, reassemble strips) + sim `.prj`.
- tools to build the 16-strip interleaved ROM + split/reassemble for verification.

## Verification

1. **Behavioral lossless (gate):** a test image (width divisible by 16) fed via the wide
   interface; the TB captures all 16 per-lane compressed streams; `verify_lossless.py` with
   `N_H=16, N_V=1` reassembles the 16 column strips and confirms **bit-exact** match. Sanity
   cross-check: one strip encoded standalone matches that lane's output.
2. **Synthesis:** 16-lane `jls_demo_top` → `synth_1` completes; report utilization (expect
   BRAM ≈ 20%, LUT ≈ 36%).
3. **Implementation → bitstream:** `impl_1 → write_bitstream`, **WNS ≥ 0** at the chosen
   `rd_clk`; report achieved clock and throughput (target ≈ 512 Mpix/s = 512 MB/s).

## Risks / Mitigations

- **Congestion lowers Fmax** across 16 lanes → chose 32 MHz (well under the ~46 MHz single-lane
  Fmax) for margin; if it still misses, raise lane count / lower clock (20 lanes @ 25 MHz).
- **Wide splitter lockstep correctness** (all lanes share (x,y)) — verified by the per-lane
  lossless reassembly + the single-strip cross-check.
- **Shallow output FIFO overflow** if a lane bursts compressed words faster than drain — the
  sink drains all 16 in parallel at full rate; depth 2048 covers worst-case bursts. Verified by
  the lossless gate (overflow would corrupt/short the stream).
- **Column-strided ROM layout** must match the splitter's slot→strip mapping — built by a tool
  and cross-checked against the reassembly.

## Done =
16-lane wide design is **bit-exact lossless** in sim (16-strip reassembly) **and** a
timing-closed bitstream (`jls_demo_top`, WNS ≥ 0) on `xc7a200tfbg676-2` at a clock giving
≈512 MB/s, with utilization + achieved clock + throughput reported.
