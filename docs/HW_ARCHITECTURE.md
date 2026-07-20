# HW Architecture — How the JPEG‑LS Encoder Reaches ~4 Gb/s on Artix‑7

**Target device:** Xilinx Artix‑7 `xc7a200tfbg676‑2` · **Toolchain:** Vivado 2024.2 · **Standard:** JPEG‑LS
(ISO/IEC 14495), lossless.

**One‑sentence summary:** the design reaches ~4 Gb/s by *giving up on a fast clock* — impossible for
causal JPEG‑LS on Artix‑7 — and instead running **12–16 independent, tile‑parallel encoder lanes at a
modest 32–45 MHz** in a width‑balanced, 1:1‑clocked, CDC‑bridged datapath whose line buffers are sized
to the strip width so the whole fabric of lanes fits in ~11 % of the device's block RAM.

This document is the high‑level "why it works" companion to the implementation‑level reference in
[`RTL_HW_IMPLEMENTATION.md`](RTL_HW_IMPLEMENTATION.md).

---

## 1. The core problem, and the one idea that solves it

JPEG‑LS is **fundamentally serial**. Each pixel's prediction reads its causal neighbours (the
reconstructed `a/b/c/d` context from the line buffer), and the run/regular decision → Golomb coding →
context‑statistics update form a **per‑pixel feedback loop**. Consequences:

- A single encoder processes **exactly one pixel per clock** — it cannot be pipelined to more.
- On this device (‑2 speed grade) a single encoder closes timing at only **~45–53 MHz**, so one
  encoder ≈ **45–53 MB/s**.

You therefore **cannot** reach 4 Gb/s by making one encoder faster: 500 MHz does not synthesize on
Artix‑7. (An earlier "4 Gb/s @ 500 MHz" figure was a *behavioral‑simulation / architectural* result,
not a synthesizable one — see §6.)

**The entire architecture is built around a single answer: spatial parallelism.**
Split the image into *N* independent tiles, encode all *N* simultaneously, each at a comfortable clock:

```
throughput  =  N lanes  ×  clock  ×  1 pixel/cycle
```

Everything else in the design exists to **feed and drain those N lanes without stalling**.

---

## 2. Data flow

```
                200 MHz differential board clock  (pins R3/P3)
                        │   IBUFDS → clk_wiz_0 (MMCM)
                        ▼
        ┌───────────────────────────┬───────────────────────────┐
        │        wr_clk             │          rd_clk           │   1:1 ratio
        │   (AXIS / I/O side)       │      (encoder side)       │  (both 32 or 45 MHz)
        ▼                           │                           ▼
  ── wr_clk domain ────────────     │     ──────────────── rd_clk domain ──────────
   WIDE input word, N px/cycle      │
   (128-bit / 16 lanes,             │
    96-bit / 12 lanes)              │
        │  block_split.v            │
        │  (x,y) → lane k, strided  │
        ▼                           │
   fifo_wrapper_input.v  ══ N async FIFOs ══  CDC  ══════════════╗ gray-code ptr
   (per-lane, shallow)                                           ║ + 2-FF sync
   ═══════════════════════════════════════════════════════════════╝
                                          fifo_read_control.v  (single pass,
                                          drains ALL N lanes every cycle)
                                                │
                                                ▼
                                    encoder_wrapper.v : N × jls_encoder
                                    (one tile per lane, fully independent)
                                    ┌───────────────────────────────────────┐
                                    │ 10-stage pipeline, 1 pixel/clock:       │
                                    │  A coord (ii,jj)  → B line/frame flags  │
                                    │  C line-buffer ctx (a,b,c,d)            │
                                    │  D quantized prediction                 │
                                    │  E error + reconstruction loop          │
                                    │  F ctx-RAM update (N/A/B/C) +           │
                                    │    run/regular decision + Golomb k      │
                                    │  G Golomb coding                        │
                                    │  H 57-bit bitstream merge               │
                                    │  J byte output + 0xFF stuffing          │
                                    │  K FFD8/FFD9 header/footer              │
                                    └───────────────────────────────────────┘
                                                │
                                                ▼
                                    fifo_wrapper_output.v : N async FIFOs
                                    → AXIS masters, 16-bit words, tready backpressure
                                                │
                                                ▼
                              N parallel compressed JPEG-LS segments  →  ~4 Gb/s aggregate
```

`fifo_reset_bram_async.v` sequences all FIFO resets against MMCM lock and raises `sys_rdy` only when it
is safe to start.

---

## 3. The architectural pillars

### 3.1 Independent tiles — an `N_H × N_V` grid, one block per lane
The image is partitioned into `N_E = N_H·N_V` **uniform** tiles. The same RTL supports all three cut
directions by choosing the factorization:

| Mode | (N_H, N_V) | Per‑lane tile |
|---|---|---|
| Vertical   | (N, 1) | tall column strip `W/N × H` |
| Horizontal | (1, N) | wide row strip `W × H/N` |
| Block      | (a, b), `a·b=N` | `W/a × H/b` |

Each tile is encoded as a **self‑contained JPEG‑LS stream** — its own `FFD8/FFD9` markers and its own
context state — so lanes never communicate. This makes the workload *embarrassingly parallel*.
Compression is essentially unaffected by the cut: at equal parallelism the three directions land within
**~1 %** of each other (tile **area**, not aspect ratio, drives the ratio). *Hard requirement:* `W % N_H
== 0` and `H % N_V == 0` (uniform tiles feed the lockstep splitter; enforced by the strided‑input tooling).

### 3.2 Wide lockstep input
The input is **one wide word per cycle** — 128‑bit (16 px) or 96‑bit (12 px) — strided so **byte k =
lane k's next pixel**. The splitter presents to every lane on the same cycle, in lockstep. This is what
turns "N serial encoders" into a single *N‑wide datapath*.

### 3.3 The 1:1 clock balance (the non‑obvious keystone)
Balance the two rates:

```
  input rate       =  N px/cycle × wr_clk
  lane consumption =  N lanes × 1 px/cycle × rd_clk
```

These stay matched **only if `wr_clk = rd_clk`**. A 2:1 (fast‑write) ratio floods the shallow per‑lane
input FIFOs and was *verified to deadlock*. The design therefore deliberately **trades clock speed for
width**: both domains run at the same modest frequency (32 or 45 MHz).

### 3.4 Clock domains and CDC
The 200 MHz differential board clock drives an MMCM (`clk_wiz_0`) that produces both `wr_clk` and
`rd_clk`. The I/O side and the encoder side are bridged by **asynchronous FIFOs with gray‑code pointers
and 2‑FF synchronisers** (`fifo_wrapper_input` / `fifo_wrapper_output`). Nothing starts encoding until
`fifo_reset_bram_async` has sequenced the FIFO resets against MMCM `LOCKED` and asserted `sys_rdy`.

### 3.5 BRAM‑frugal memory — what actually lets 16 lanes fit
Two memories dominate each lane:

- **Line buffer** — sized to the *per‑lane strip width* (`LB_DEPTH = i_w / N_H`), **not** the full image
  width. Because vertical/block strips are only `W/N_H` wide, this stays small.
- **366‑context statistics tables** (`N/A/B/C`, per JPEG‑LS Appendix C), inferred as block RAM.

The payoff: **all 16 lanes use only 40 BRAM tiles (11 %)** of the `xc7a200t`, versus a naïve ~860.
Without strip‑width line buffers, sixteen encoders would not fit on the part. `LB_DEPTH` is a
build‑time parameter (default 1024 → strip widths up to 16 384 for the wide grid); horizontal (`N_H=1`,
full‑width strips) is the one mode that scales `LB_DEPTH` with image width.

### 3.6 Backpressured output
Each lane drains through its own async output FIFO exposed as an **AXIS master** with `tready`
handshaking (one read outstanding, lossless under stall), yielding **N independent compressed
segments** that a host reassembles by tile position.

---

## 4. Throughput (all measured, timing‑closed on `xc7a200tfbg676‑2`)

| Configuration | Lanes × clock | Throughput | Timing (WNS) | Utilisation (LUT / FF / BRAM / DSP) |
|---|---|---|---|---|
| **16‑lane @ 32 MHz** — canonical ~4 Gb/s | 16 × 32 MHz | 512 MB/s ≈ **4.1 Gb/s** | **+8.25 ns** | 29.4 % / 9.3 % / 11 % / 2.6 % |
| **12‑lane @ 45 MHz** — active repo config | 12 × 45 MHz | 540 MB/s ≈ **4.3 Gb/s** | +0.65 ns | 24.3 % / 7.0 % / 8.2 % / 1.9 % |
| **16‑lane @ 53.33 MHz** — real fmax | 16 × 53.33 MHz | 853 MB/s ≈ **6.83 Gb/s** | +0.16 ns | — |

(8‑bit pixels, so MB/s = Mpix/s; Gb/s = MB/s × 8 / 1000.)

---

## 5. Why this is a *bandwidth* architecture, not a *speed* one

The tell‑tale sign: at 32 MHz the 16‑lane build closes with **+8.25 ns of slack** — enormous. The clock
is deliberately low; the 4 Gb/s comes entirely from **width** (16 lanes in lockstep). An fmax sweep
(MMCM reconfigured above 32 MHz, re‑implemented through routing) shows the encoder domain itself closes
up to **53.33 MHz** — so the per‑lane pipeline has ample headroom, and the practical limiter at higher
rates is the **cross‑domain CDC path**, not the encoder logic. The 32 MHz operating point is kept as a
comfortable guard‑band; the 12‑lane @ 45 MHz variant is the repo's shipped default (540 MB/s with a
smaller footprint).

---

## 6. Honesty note — the "500 MHz" figure

An earlier **4 Gb/s @ 500 MHz** result was a **behavioral‑simulation / architectural** number.
**500 MHz is not synthesizable on Artix‑7.** The parallel‑lane approach documented here (many encoders
at a modest clock) is the *first real synthesizable* path to ~4 Gb/s on this device — and it is proven
by timing‑closed bitstreams, not simulation alone.

---

## 7. Feeding the core from a serial link (optional front‑end)

If pixels arrive as *serial* lanes instead of a wide bus, a front‑end reconstructs the wide word and
hands it to the same parallel core through the async CDC FIFO — decoupling pin count from internal
parallelism:

- **ISERDES front‑end** (`iserdes_byte_in.v`): 12× `ISERDESE2`, 1:8 SDR deserialise, 12 lanes @
  360 Mb/s → 12 bytes @ 45 MHz. Fabric ≤ 45 MHz; robust on the ‑2 speed grade. End‑to‑end lossless and
  byte‑identical to the parallel path; timing‑closed to a bitstream (see `RTL_HW_IMPLEMENTATION.md` §15–16).
- **Fabric byte‑gearbox** (`byte_gearbox_12.v`): 1 byte @ ~540 MHz → 12‑byte word @ 45 MHz, via a
  registered async FIFO. At the ‑2 fabric edge (~520 MHz); ‑3 reaches 540 MHz.

The encoder core itself is unchanged in either case — it is now also a packaged Vivado IP,
`user.org:user:jls_encoder:1.0`, instantiated `N_E` times by `encoder_wrapper`.

---

## 8. Component map

| Block | File | Role |
|---|---|---|
| Splitter | `sources_1/new/block_split.v` | (x,y) → lane, wide lockstep striding |
| Input FIFOs / CDC | `sources_1/new/fifo_wrapper_input.v` | N async FIFOs, wr_clk → rd_clk |
| Read control | `sources_1/new/fifo_read_control.v` | single‑pass drain of all N lanes |
| Encoder fabric | `sources_1/new/encoder_wrapper.v` | N × `jls_encoder` (the IP) |
| Encoder core | `imports/FPGA Encoders/jls_encoder.v` | 10‑stage pipeline, 1 px/clock |
| Output FIFOs / CDC | `sources_1/new/fifo_wrapper_output.v` | N async FIFOs → AXIS masters |
| Reset sequencing | `sources_1/new/fifo_reset_bram_async.v` | gates start on MMCM lock → `sys_rdy` |
| AXIS IP top | `imports/FPGA Encoders/jls_encoder_axis.v` | AXIS slave in, N AXIS masters out |
| Clocking | `clk_wiz_0` (MMCM) | 200 MHz → wr_clk + rd_clk |
| Serial front‑ends | `iserdes_byte_in.v`, `byte_gearbox_12.v` | serial → wide word (optional) |

See [`RTL_HW_IMPLEMENTATION.md`](RTL_HW_IMPLEMENTATION.md) for per‑block detail, the full size × direction
verification matrix, per‑mode bitstream results, and the fmax methodology.
