# Design: JPEG-LS Encoder as a Synthesizable AXI4-Stream IP

**Date:** 2026-06-26
**Status:** Approved (pending spec review)
**Target device:** Xilinx Artix-7 `xc7a200tfbg676-2`

## Problem / Context

The current design (`top_jls_vertical`) is **not synthesizable as real hardware**:

1. **No real pixel input.** `image_generator.v` is a simulation-only file reader
   (`$fopen`/`$fgetc` inside `` `ifndef SYNTHESIS ``). Under synthesis all of its outputs
   tie to `0`, so the encoders would never receive pixels. The top has no external pixel port.
2. **Port-direction mismatch.** `top_jls_vertical` declares `i_x`/`i_e`/`i_w`/`i_h` as
   **outputs** (driven by the internal generator), but `top_jls_vertical.xdc` pins them as
   **inputs**. They cannot both be correct on hardware.
3. **4 Gb/s / 500 MHz is unachievable on Artix-7.** That target (from prior sim work) required
   500 MHz clocks; the `clk_wiz` `.xci` is actually configured far lower. Synthesizable
   throughput is set by whatever Fmax the encoder closes at (~100–150 MHz, ~1 pixel/cycle),
   not 4 Gb/s.

Behavioral simulation and lossless compression are verified and working; only the
*hardware-realizability* of the design is the problem.

## Goals

- Refactor the encoder into a **synthesizable AXI4-Stream IP** with a real pixel-input path.
- Build a **self-contained bitstream** (synthesis → place & route → bitstream) that **closes
  timing** (WNS ≥ 0) on the `-2` part, and report achieved clock / utilization / throughput.
- **Preserve behavioral-sim correctness**: the existing benchmark sweep must still produce
  **bit-exact lossless** output (regression proof the refactor changed no encoding behavior).

## Non-Goals / Out of Scope

- 4 Gb/s throughput (architecturally impossible at synthesizable Artix-7 clocks).
- Near-lossless: **NEAR is removed; the encoder is lossless-only** (`nr` parameter fixed `0`).
- DDR/MIG + AXI DMA block design (deferred; the bitstream uses an on-chip AXIS source).
- AXI4-Lite control plane (dimensions delivered via sideband ports instead).
- Changing the internal encoder algorithm or the splitter/FIFO pipeline behavior.

## Decisions (settled during brainstorming)

| Decision | Choice |
|---|---|
| Synthesis depth | Full build to **bitstream**, timing closed |
| Pixel input | **AXI4-Stream** slave (in) + master (out), product-grade IP |
| Dimensions / SOF | **Sideband control ports** (`i_w`, `i_h`, `i_sof`) |
| NEAR | **Removed** — lossless only (`nr = 0`) |
| Bitstream harness | **On-chip AXIS test source** (BRAM `.coe`), self-contained |
| Starting config | `N_E = 2`, `N_H = 2`, `N_V = 1` (vertical, two column strips) |
| Module rename | `top_jls_vertical` → **`jls_encoder_axis`** |

## Architecture

Three layers:

```
jls_demo_top                         ← bitstream/impl top (synthesizable harness)
 ├─ clk_wiz_0                         (diff clk in → wr_clk / rd_clk)
 ├─ axis_image_source                 on-chip AXIS master (BRAM .coe image) + sideband
 ├─ jls_encoder_axis  ← THE IP        AXIS slave in, N_E AXIS masters out
 │   ├─ axis_pixel_in                 AXIS slave → splitter (i_x/i_e), tready backpressure
 │   ├─ splitter_block                (unchanged)
 │   ├─ fifo_wrapper_input            (unchanged)
 │   ├─ fifo_read_control             (unchanged)
 │   ├─ encoder_wrapper → jls_encoder (unchanged, nr=0)
 │   ├─ fifo_wrapper_output           (unchanged drain core)
 │   └─ axis_master_out [N_E]         FIFO drain → AXIS master, real tready backpressure
 ├─ axis_sink                         tready=1, byte counters, done
 └─ status I/O                        done / byte-count → LEDs; start button; reset
```

The **internal pipeline is untouched** — only the input edge (replace `image_generator` with
`axis_pixel_in` + sideband) and the output edge (`axis_master_out` adapters) change.

### AXIS slave (pixel input) — `axis_pixel_in`

- Ports: `s_axis_aclk` (= `wr_clk`/`clk`), `s_axis_aresetn`, `s_axis_tdata[7:0]`,
  `s_axis_tvalid`, `s_axis_tready`, `s_axis_tlast`.
- `s_axis_tready = sys_rdy & ~fifo_full_cur` (reuses the existing per-encoder backpressure
  `fifo_full[encoder_sel_comb]`). A pixel transfers on `tvalid && tready` and drives the
  splitter's `i_x` (= `tdata`) and `i_e` (= transfer strobe).
- Sideband inputs `i_w[15:0]`, `i_h[13:0]`, `i_sof` are latched on `i_sof` (start of frame).
  `tlast` is accepted as an optional end-of-frame marker (sanity-check only; framing is driven
  by `i_w`/`i_h` as today).

### AXIS master (compressed output) — `axis_master_out` (×N_E)

- Per encoder channel: `m_axis_tdata[15:0]`, `m_axis_tvalid`, `m_axis_tready`, `m_axis_tlast`.
- Maps the existing output: `tdata ← o_data[ch]`, `tvalid ← o_e[ch]`, `tlast ← o_last[ch]`.
- Adds **real `tready` backpressure**: the output FIFO is read only when downstream is ready,
  with a one-entry hold/skid register so a word already presented is held until accepted.
  (The existing full-rate drain in `fifo_wrapper_output.v` is preserved as the FIFO core; the
  adapter gates `rd_en` with `tready` and registers the AXIS-visible `tvalid`/`tdata`.)
- Flattened bus form for the top: `m_axis_tdata[N_E*16-1:0]`, `m_axis_tvalid[N_E-1:0]`,
  `m_axis_tready[N_E-1:0]`, `m_axis_tlast[N_E-1:0]`.

### Clocking

- Keep the `clk_wiz_0` dual-clock structure: `clk_out1` = `wr_clk` (AXIS/IO + FIFO write/read
  side), `clk_out2` = `rd_clk` (encoder). The async CDC FIFOs are core to the architecture and
  stay. AXIS slave/master live in the `wr_clk` domain.
- Set the `.xci` to a realistic target; **let synthesis report Fmax**, then constrain the
  bitstream clock safely below it (positive WNS). Align the `clk_wiz` simulation model to the
  `.xci` so sim and synth use one coherent config. Report the achieved clock and the resulting
  throughput (≈ `encoder_clock × pixels/cycle`).

### Bitstream harness — `jls_demo_top`

- `axis_image_source`: synthesizable AXIS master backed by a BRAM initialized from a `.coe`
  (modest image, ~256×256). Streams pixels with `tvalid`, honors `tready`, asserts `tlast` at
  frame end, and drives the sideband `i_w`/`i_h`/`i_sof`.
- `axis_sink`: holds `tready = 1` on every channel, counts output bytes per channel, raises
  `done` when all channels report `tlast`.
- Real top-level I/O (the only physical pins): differential clock, reset, start button, status
  LEDs (`done` + a few byte-count bits). A **new minimal XDC** (`jls_demo_top.xdc`) constrains
  these; the legacy `top_jls_vertical.xdc` (wrong port directions) is retired.
- Config: `N_E = 2`, `N_H = 2`, `N_V = 1`. Two 16 K×8 line buffers ≈ 17% of BRAM36 — fits with
  large margin and keeps first-pass timing closure tractable.

## File-level change plan

**Rename / transform**
- `…/sources_1/imports/FPGA Encoders/top_jls_vertical.v` → `jls_encoder_axis.v`: remove
  `image_generator` instance, add `axis_pixel_in` + sideband ports + `axis_master_out[N_E]`;
  keep all internal instances. Module + file renamed.

**New synthesizable modules**
- `axis_pixel_in.v` — AXIS slave → splitter adapter.
- `axis_master_out.v` — output-FIFO → AXIS master adapter (×N_E via generate).
- `jls_demo_top.v` — bitstream top (source + IP + sink + status).
- `axis_image_source.v` — BRAM-backed synthesizable AXIS pixel source.
- `axis_sink.v` — AXIS drain + byte counters + done.
- `jls_demo_top.xdc` — minimal pin/timing constraints.
- image `.coe` (+ BRAM IP if needed) for `axis_image_source`.

**Removed from the synthesizable hierarchy**
- `image_generator.v` — no longer in the IP. (Its file-reading logic moves to the testbench as
  an AXIS driver; the synthesizable source is `axis_image_source`.)

**Testbench**
- `…/sim_1/imports/FPGA Encoders/tb_top_jls_vertical.v` → `tb_jls_encoder_axis.v`: read the PGM
  and drive `s_axis` (tvalid/tready handshake, sideband `i_w`/`i_h`/`i_sof`); capture the N_E
  AXIS master channels (same EOI/slice logic). Same output filenames so `verify_lossless.py`
  is unchanged.

**Project / scripts**
- Update Vivado filesets (`.xpr`/`.srcs`) for the renamed/added/removed files and set the synth
  top to `jls_demo_top`.
- Update the sim `.prj` and `run_hv_benchmark.ps1` to the new top/TB names.
- `clk_wiz_0` `.xci`: realistic clock target; align sim model.

## Verification

1. **Behavioral regression (lossless).** Build the updated `.prj`, run
   `run_hv_benchmark.ps1` for at least 300×300 and 1500×1500 across block/vertical/horizontal,
   and `verify_lossless.py` each → **bit-exact match required**. This proves the AXIS refactor
   changed no encoding behavior.
2. **Synthesis.** `launch_runs synth_1` on `jls_demo_top` → must complete with no errors;
   record utilization (LUT/FF/BRAM/DSP) and the post-synth Fmax / failing paths.
3. **Implementation → bitstream.** `launch_runs impl_1 -to_step write_bitstream` → must reach
   `write_bitstream` with **WNS ≥ 0** at the chosen clock. Record achieved clock, throughput
   (Mpix/s and effective Gb/s), and final utilization.

## Risks / Mitigations

- **Timing closure of the JLS pipeline** (feedback in context-RAM update / reconstruction):
  start at a conservative clock that closes, report Fmax, raise only as slack allows. The clock
  is set below measured Fmax, so closure is by construction.
- **Output AXIS backpressure correctness**: the demo sink holds `tready=1` (matches today's
  always-accept drain), but the adapter implements true backpressure so the IP is correct
  behind a real consumer. Verified in sim by toggling `tready`.
- **Rename churn** (TB, `.xpr`, `.prj`, scripts): handled as an explicit step; the sim `.prj`
  flow is the regression gate and is updated in lockstep.
- **BRAM `.coe` build**: if generating a BRAM IP is heavy, `axis_image_source` may instead use
  an inferred ROM (`reg [7:0] mem [...]` with `$readmemh` initial — synthesizable to block ROM)
  to avoid IP regeneration.

## Done = 
Behavioral sweep bit-exact lossless on the AXIS design **and** a timing-closed bitstream for
`jls_demo_top` on `xc7a200tfbg676-2`, with utilization + achieved clock + throughput reported.
