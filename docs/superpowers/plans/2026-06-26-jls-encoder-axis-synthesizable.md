# Synthesizable AXI4-Stream JPEG-LS Encoder — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the JPEG-LS encoder into a synthesizable AXI4-Stream IP (`jls_encoder_axis`) with a real pixel-input path, wrap it in a self-contained on-chip-source harness (`jls_demo_top`), and build a timing-closed bitstream on `xc7a200tfbg676-2` — while the behavioral sim stays bit-exact lossless.

**Architecture:** The verified internal pipeline (`splitter_block → fifo_wrapper_input → fifo_read_control → encoder_wrapper → fifo_wrapper_output`) is untouched. Only the edges change: a new `axis_pixel_in` adapter replaces the sim-only `image_generator` (it mirrors the generator's FSM exactly, sourcing pixels from an AXIS slave instead of `$fgetc`), and `fifo_wrapper_output` gains AXIS-master `tready` backpressure. A bitstream harness feeds the IP from an on-chip BRAM image source and routes the compressed output to pins.

**Tech Stack:** Verilog-2001, Xilinx Vivado 2024.2 (xsim for behavioral sim, `synth_1`/`impl_1` for build), PowerShell sweep script, Python verifier.

---

## Background facts (verified, for the implementer)

- **`image_generator` FSM (the behavior to preserve)** — `image_generator.v:69-119`:
  `S_IDLE` waits for `i_sof` → latches `i_w`/`i_h` → `S_SOF` holds `i_sof_st = {N_E{1'b1}}` for
  `SOF_STRETCH=3000` cycles → `S_PIXEL` emits one pixel/cycle while `pix_cnt < total_pixels`
  and `!backpressure` (`backpressure = |fifo_overflow`) → `S_DONE`. `pixel_valid` and `i_sof_st`
  are registered (default 0 each cycle). `axis_pixel_in` must reproduce this exactly, replacing
  `pixel_out <= $fgetc(fp)` with an AXIS transfer and taking `i_w`/`i_h` from sideband ports.
- **Splitter consumes** `i_sof` (top input, NOT the synchronized one — `top_jls_vertical.v:122`),
  `i_sof_st` (N_E-bit, from generator), `i_e`/`i_x`/`i_w`/`i_h`. Header: `block_split.v:3-27`.
- **Backpressure today**: `top_jls_vertical.v:147-148`
  `fifo_full_cur = fifo_full[encoder_sel_comb]; fifo_overflow_masked = {N_E{fifo_full_cur}}`.
- **Output FIFO read-domain** (`fifo_wrapper_output.v:131-151`) currently drains at full rate
  (`fifo_rd_en = ~fifo_empty`) and sets `dout_valid <= fifo_rd_en`; `dout_last` is held 0 (the TB
  finds slice ends by detecting the `FFD9` EOI byte pair, not by `o_last`). The wr-domain count +
  gray-coded CDC (`fifo_wrapper_output.v:49-122`) is kept as-is.
- **NEAR**: `jls_encoder.v:10` `parameter [2:0] NEAR = 3'd0`. Fixed at 0 = lossless. Leave the
  parameter; do not route a port. `encoder_wrapper.v:6` passes `nr` (default 0) down.
- **Clocks** (`clk_wiz_0.xci`): 200 MHz in → `clk_out1` 33.33 MHz (`wr_clk`/`clk`),
  `clk_out2` 10 MHz (`rd_clk`). This is conservative and will close timing trivially — keep it for
  the first bitstream; a later task probes higher Fmax.
- **XDC pins** (`top_jls_vertical.xdc`): diff clk `clk_in1_p`=R3 / `clk_in1_n`=P3 (LVDS_25),
  `rstn`=R8 (LVCMOS25). Output-data ports (`o_e*`, `o_data*`, `o_last*`) already have PACKAGE_PIN
  assignments in that file — reuse them for the harness outputs.
- **Sim compile list**: `JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_top_jls_vertical_vlog.prj` lists every
  compiled `.v` (verbatim list in the design assessment). The benchmark sweep
  (`run_hv_benchmark.ps1`) elaborates `xil_defaultlib.tb_top_jls_vertical`, snapshot
  `tb_top_jls_vertical_behav`, parses the `BENCHMARK_RESULT` line, runs `run_quit.tcl`.
- **Project**: `JPEG_ENC_8f.xpr` synth `TopModule` = `top_jls_vertical`; sim `TopModule` =
  `tb_top_jls_vertical`. Edit project state via **Vivado TCL** (`set_property top …`,
  `add_files`/`remove_files`), never by hand-editing the `.xpr` XML.

---

## File Structure

**New synthesizable RTL** (in `JPEG_ENC_8f.srcs/sources_1/new/`):
- `axis_pixel_in.v` — AXIS slave → splitter adapter (the `image_generator` FSM, AXIS-sourced).
- `axis_image_source.v` — on-chip AXIS master backed by a `$readmemh` ROM (bitstream harness source).
- `jls_demo_top.v` — bitstream/impl top: clk_wiz + image source + `jls_encoder_axis` + output to pins.

**Modified RTL:**
- `…/sources_1/imports/FPGA Encoders/top_jls_vertical.v` → renamed file+module `jls_encoder_axis.v`.
- `…/sources_1/new/fifo_wrapper_output.v` — add per-channel `m_axis_tready`, AXIS register-slice.

**Removed from build:** `…/sources_1/new/image_generator.v` (no longer instantiated anywhere).

**New constraints:** `…/constrs_1/imports/new/jls_demo_top.xdc`.

**Test / tooling:**
- `…/sim_1/imports/FPGA Encoders/tb_top_jls_vertical.v` → `tb_jls_encoder_axis.v` (drives AXIS, reads PGM inline, ties `m_axis_tready=1`).
- `JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_top_jls_vertical_vlog.prj` — updated file/module list.
- `run_hv_benchmark.ps1` — updated TB/top module + snapshot names + file paths.
- `tools/pgm_to_hex.py` (new) — PGM → `$readmemh` hex for the ROM source.
- `JPEG_ENC_8f.sim/sim_1/behav/xsim/build_synth.tcl`, `build_impl.tcl` (new) — Vivado batch build.

---

# PART A — AXIS IP refactor + behavioral lossless regression

The gate for Part A is: **the benchmark sweep still produces bit-exact lossless output**
(`verify_lossless.py` passes). That integration sim is the test for every Part-A task.

## Task A1: `axis_pixel_in.v` — AXIS slave pixel adapter

**Files:**
- Create: `JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v`

- [ ] **Step 1: Write the module** (mirrors `image_generator.v:58-119`, AXIS-sourced)

```verilog
`timescale 1ns/1ps
// AXIS slave -> splitter adapter. Reproduces image_generator's control FSM exactly
// (S_IDLE -> S_SOF stretch -> S_PIXEL), but sources pixels from an AXI4-Stream slave
// instead of $fgetc, and takes image dimensions from sideband ports. Lossless only.
module axis_pixel_in #(
    parameter integer N_E         = 2,
    parameter integer SOF_STRETCH = 3000
)(
    input  wire                  clk,            // wr_clk domain
    input  wire                  rstn,           // = sys_rdy
    input  wire                  i_sof,          // sideband start-of-frame pulse
    input  wire [15:0]           i_w_in,         // sideband image width
    input  wire [13:0]           i_h_in,         // sideband image height
    input  wire [N_E-1:0]        fifo_overflow,  // backpressure (= fifo_full masked)

    // AXI4-Stream slave (pixels in)
    input  wire [7:0]            s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,   // accepted; framing driven by i_w/i_h

    // to splitter_block (same signals image_generator produced)
    output reg  [7:0]            pixel_out,
    output reg                   pixel_valid,
    output reg  [15:0]           i_w,
    output reg  [13:0]           i_h,
    output reg  [N_E-1:0]        i_sof_st
);
    localparam S_IDLE = 2'd0, S_SOF = 2'd1, S_PIXEL = 2'd2, S_DONE = 2'd3;

    reg  [1:0]  state;
    reg  [31:0] sof_cnt;
    reg  [31:0] pix_cnt;
    reg  [31:0] total_pixels;
    wire        backpressure = |fifo_overflow;

    // Accept a pixel only while actively streaming and not backpressured.
    assign s_axis_tready = (state == S_PIXEL) && (pix_cnt < total_pixels) && !backpressure;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= S_IDLE; sof_cnt <= 0; pix_cnt <= 0; total_pixels <= 0;
            pixel_out <= 0; pixel_valid <= 0; i_w <= 0; i_h <= 0; i_sof_st <= 0;
        end else begin
            pixel_valid <= 1'b0;          // default low (registered), like image_generator
            i_sof_st    <= {N_E{1'b0}};
            case (state)
                S_IDLE: if (i_sof) begin
                    i_w          <= i_w_in;
                    i_h          <= i_h_in;
                    total_pixels <= i_w_in * i_h_in;
                    sof_cnt      <= 0;
                    pix_cnt      <= 0;
                    state        <= S_SOF;
                end
                S_SOF: begin
                    i_sof_st <= {N_E{1'b1}};
                    if (sof_cnt < SOF_STRETCH - 1) sof_cnt <= sof_cnt + 1;
                    else begin sof_cnt <= 0; state <= S_PIXEL; end
                end
                S_PIXEL: begin
                    if (pix_cnt < total_pixels) begin
                        if (s_axis_tvalid && s_axis_tready) begin
                            pixel_out   <= s_axis_tdata;
                            pixel_valid <= 1'b1;
                            pix_cnt     <= pix_cnt + 1;
                        end
                    end else begin
                        state <= S_DONE;
                    end
                end
                S_DONE: ;
            endcase
        end
    end
endmodule
```

- [ ] **Step 2: Add it to the sim compile list**

In `JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_top_jls_vertical_vlog.prj`, add this line in the
`verilog xil_defaultlib …` block (e.g. right after the `block_split.v` line):

```
"../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v" \
```

- [ ] **Step 3: Verify it compiles standalone**

Run (from `JPEG_ENC_8f.sim/sim_1/behav/xsim/`):
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v" -log xvlog_axis_pixel_in.log
```
Expected: `INFO: [VRFC 10-xxxx] analyzing module axis_pixel_in` and no errors.

- [ ] **Step 4: Commit**

```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v" "JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_top_jls_vertical_vlog.prj"
git commit -m "feat(axis): add axis_pixel_in AXIS slave pixel adapter (mirrors image_generator FSM)"
```

## Task A2: `fifo_wrapper_output.v` — AXIS-master `tready` backpressure

Replace the full-rate read-domain block with a 1-deep AXIS register slice that reads only when
the downstream is ready, so the IP is correct behind a real consumer. With `m_axis_tready` tied
high (the demo sink and the TB), this reduces to the current verified full-rate behavior.

**Files:**
- Modify: `JPEG_ENC_8f.srcs/sources_1/new/fifo_wrapper_output.v` (ports + read-domain block)

- [ ] **Step 1: Add the `m_axis_tready` input port**

Change the port list (the `output reg [N_E-1:0] dout_last,` line region) to add, after
`o_last_enc`:
```verilog
    input  wire [N_E-1:0]           m_axis_tready,
```
(Place it among the inputs, e.g. immediately after `input wire [N_E-1:0] o_last_enc,`.)

- [ ] **Step 2: Replace the read-domain always block** (`fifo_wrapper_output.v:124-151`)

Replace the `wire [N_E-1:0] fifo_rd_en = ~fifo_empty;` line (line 25) AND the entire
read-domain block (lines 124-151) with:

```verilog
    // ------------------------------------------------------------------
    // READ DOMAIN: AXIS master with tready backpressure.
    // One outstanding read max (standard FIFO has 1-cycle read latency, so a
    // requested word lands the next cycle). dout_valid/dout_flat are the AXIS
    // tvalid/tdata; reads are gated by tready so no word is dropped when the
    // consumer stalls. With tready held high this matches the prior full-rate drain.
    // ------------------------------------------------------------------
    reg  [LEN_WIDTH-1:0] rd_cnt  [0:N_E-1];
    reg  [2:0]           rd_ptr  [0:N_E-1];
    reg  [N_E-1:0]       pending;          // a read issued last cycle; data on dout now
    reg  [N_E-1:0]       last_pend;        // that pending word is a slice-final word

    wire [N_E-1:0] out_free = ~dout_valid | m_axis_tready;   // output reg free next cycle
    // full-rate when ready; <=1 outstanding read under backpressure (no data loss)
    wire [N_E-1:0] fifo_rd_en = (~fifo_empty) & out_free & (~pending | m_axis_tready);

    // slice-final detection: the word at rd_cnt is the last of slice rd_ptr
    wire [N_E-1:0] read_is_last;
    genvar li;
    generate
        for (li = 0; li < N_E; li = li + 1) begin : GEN_LAST
            assign read_is_last[li] =
                (rd_ptr[li] != wr_ptr_rd[li]) &&
                (rd_cnt[li] == end_pos[li][rd_ptr[li][1:0]]);
        end
    endgenerate

    integer ri;
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            dout_valid <= 0;
            dout_last  <= 0;
            pending    <= 0;
            last_pend  <= 0;
            for (ri = 0; ri < N_E; ri = ri + 1) begin
                rd_cnt[ri] <= 0;
                rd_ptr[ri] <= 0;
            end
        end else begin
            for (ri = 0; ri < N_E; ri = ri + 1) begin
                // consumer accepts the currently presented word
                if (dout_valid[ri] && m_axis_tready[ri]) begin
                    dout_valid[ri] <= 1'b0;
                    dout_last[ri]  <= 1'b0;
                end
                // a previously requested word lands now -> present it
                if (pending[ri]) begin
                    dout_valid[ri] <= 1'b1;
                    dout_last[ri]  <= last_pend[ri];
                    if (last_pend[ri]) rd_ptr[ri] <= rd_ptr[ri] + 1'b1;
                end
                // issue a new read
                if (fifo_rd_en[ri]) rd_cnt[ri] <= rd_cnt[ri] + 1'b1;
                pending[ri]   <= fifo_rd_en[ri];
                last_pend[ri] <= read_is_last[ri] & fifo_rd_en[ri];
            end
        end
    end
```

Note: `fifo_dout_flat` is the FIFO `dout` and is already wired to the FIFO instance; with one
outstanding read it holds the pending word until the next read, so AXIS `tdata = fifo_dout_flat`
is valid whenever `dout_valid` is high. Leave the `fifo_dout_flat` output and the FIFO
instantiation (lines 27-47) and the wr-domain/CDC blocks (lines 49-122) unchanged. The
`fifo_valid` IP flag is intentionally unused (we trust registered `rd_en`, per the prior fix).

- [ ] **Step 3: Verify it compiles standalone**

```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/fifo_wrapper_output.v" -log xvlog_fwo.log
```
Expected: analyzes `fifo_wrapper_output` with no errors. (Full functional check is the A6 sim.)

- [ ] **Step 4: Commit**

```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/fifo_wrapper_output.v"
git commit -m "feat(axis): output FIFO drain becomes AXIS master with tready backpressure"
```

## Task A3: Transform `top_jls_vertical` → `jls_encoder_axis`

Remove `image_generator`, instantiate `axis_pixel_in`, expose AXIS slave + sideband + N_E AXIS
masters, and wire `m_axis_tready` to the output FIFO.

**Files:**
- Rename: `…/sources_1/imports/FPGA Encoders/top_jls_vertical.v` → `jls_encoder_axis.v`
- Modify: the module (ports + image_generator removal + axis_pixel_in + output tready)

- [ ] **Step 1: Rename the file (git mv)**

```bash
git mv "JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/top_jls_vertical.v" "JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v"
```

- [ ] **Step 2: Replace the module header + ports** (`jls_encoder_axis.v:2-24`)

Replace the `module top_jls_vertical #(…)(…);` declaration with:

```verilog
module jls_encoder_axis #(
    parameter integer N_E = 2,
    parameter integer N_H = 2,   // columns. N_H=1 => horizontal split
    parameter integer N_V = 1,   // swaths.  N_V=1 => vertical split
    parameter integer L   = 64,
    parameter [2:0]   nr  = 3'd0 // NEAR fixed 0 (lossless)
)(
    input  wire        rstn,
    output wire        clk,         // wr_clk (also s_axis_aclk / m_axis_aclk)
    input  wire        clk_in1_p,
    input  wire        clk_in1_n,
    output wire        sys_rdy,

    // sideband control
    input  wire        i_sof,
    input  wire [15:0] i_w,
    input  wire [13:0] i_h,

    // AXI4-Stream slave (pixels in), clocked by clk
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // AXI4-Stream masters (compressed out, N_E channels), clocked by clk
    output wire [N_E*16-1:0] m_axis_tdata,
    output wire [N_E-1:0]    m_axis_tvalid,
    input  wire [N_E-1:0]    m_axis_tready,
    output wire [N_E-1:0]    m_axis_tlast
);
```

- [ ] **Step 3: Replace the `image_generator` instance** (`jls_encoder_axis.v:94-110`)

The top now drives the splitter from `axis_pixel_in`. Replace the
`image_generator #(…) u_image_generator (…);` block with:

```verilog
    // =================================================================
    // AXIS slave pixel adapter (replaces sim-only image_generator)
    // =================================================================
    wire [7:0]  gen_x;
    wire        gen_e;
    wire [15:0] gen_w;
    wire [13:0] gen_h;

    axis_pixel_in #(.N_E(N_E)) u_axis_pixel_in (
        .clk           (clk),
        .rstn          (sys_rdy),
        .i_sof         (i_sof),
        .i_w_in        (i_w),
        .i_h_in        (i_h),
        .fifo_overflow (fifo_overflow_masked),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .pixel_out     (gen_x),
        .pixel_valid   (gen_e),
        .i_w           (gen_w),
        .i_h           (gen_h),
        .i_sof_st      (o_sof_st)
    );
```

- [ ] **Step 4: Rewire splitter + downstream to the adapter signals**

The old top used the top-level outputs `i_x`/`i_e`/`i_w`/`i_h` (driven by the generator). Now
the adapter drives internal `gen_x`/`gen_e`/`gen_w`/`gen_h`. Update the `splitter_block` instance
(`jls_encoder_axis.v:115-136`): change `.i_e(i_e)` → `.i_e(gen_e)`, `.i_x(i_x)` → `.i_x(gen_x)`,
`.i_w(i_w)` → `.i_w(gen_w)`, `.i_h(i_h)` → `.i_h(gen_h)`. Leave `.i_sof(i_sof)` and
`.i_sof_st(o_sof_st)` as-is. (`i_w`/`i_h` are now input ports = the sideband dims; the splitter
must use the adapter's registered `gen_w`/`gen_h` which equal the latched sideband values.)

- [ ] **Step 5: Wire `m_axis_tready` into the output FIFO + map AXIS master outputs**

In the `fifo_wrapper_output #(…) u_fifo_wrapper_output (…)` instance
(`jls_encoder_axis.v:241-255`): rename the output mappings and add tready —
```verilog
        .din_flat       (e_data),
        .wr_en          (e_e),
        .o_last_enc     (o_last_enc),
        .m_axis_tready  (m_axis_tready),
        .fifo_dout_flat (m_axis_tdata),
        .dout_valid     (m_axis_tvalid),
        .dout_last      (m_axis_tlast),
        .wr_rst_busy    (wr_rst_busy_output),
        .rd_rst_busy    (rd_rst_busy_output)
```

- [ ] **Step 6: Remove now-dead top signals**

Delete the old `i_sof` synchronizer if unused downstream (`jls_encoder_axis.v:57-73` — `sof_sync*`,
`i_sof_r`, `i_sof_in`); the splitter uses the raw `i_sof`. Keep the clk_wiz, fifo_reset,
fifo_wrapper_input, fifo_write_control, fifo_read_control, encoder_wrapper instances unchanged.
Confirm no remaining reference to `i_x`/`i_e` as top ports (they no longer exist).

- [ ] **Step 7: Verify the IP elaborates standalone**

```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v" "../../../../JPEG_ENC_8f.srcs/sources_1/new/fifo_wrapper_output.v" "../../../../JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v" -log xvlog_ip.log
```
Expected: `analyzing module jls_encoder_axis` with no errors (other submodules will report as
undeclared at this stage — that's fine; full elaboration is in A6).

- [ ] **Step 8: Commit**

```bash
git add -A "JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/"
git commit -m "refactor: top_jls_vertical -> jls_encoder_axis with AXIS slave/master + sideband"
```

## Task A4: Rewrite the testbench to drive AXIS

The TB now owns the pixel source: read the PGM, set `i_w`/`i_h`, pulse `i_sof`, stream bytes on
`s_axis` honoring `s_axis_tready`, tie `m_axis_tready=1`, capture the N_E master channels.

**Files:**
- Rename: `…/sim_1/imports/FPGA Encoders/tb_top_jls_vertical.v` → `tb_jls_encoder_axis.v`
- Modify: DUT instance, add PGM-reading AXIS driver, keep capture/EOI/BENCHMARK_RESULT logic

- [ ] **Step 1: Rename the file (git mv)**

```bash
git mv "JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/tb_top_jls_vertical.v" "JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/tb_jls_encoder_axis.v"
```

- [ ] **Step 2: Rename the module and add PGM-source params**

Change `module tb_top_jls_vertical #(` → `module tb_jls_encoder_axis #(` and add to the param list:
```verilog
    parameter PGM_FILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.sim/images/world_gray_300x300.pgm",
```
(Keep existing `N_E`, `N_H`, `N_V`, `NUM_SLICES`, `MAX_BYTES_PER_SLICE`.)

- [ ] **Step 3: Replace the DUT I/O regs/wires + DUT instance**

Replace the `// DUT I/O` block and the `top_jls_vertical #(…) dut (…)` instance
(`tb_top_jls_vertical.v:33-76`) with:

```verilog
    // ---- DUT I/O ----
    reg  i_sof = 0;
    reg  [15:0] i_w = 0;
    reg  [13:0] i_h = 0;
    wire clk;
    wire sys_rdy;

    reg  [7:0]  s_axis_tdata  = 0;
    reg         s_axis_tvalid = 0;
    wire        s_axis_tready;
    reg         s_axis_tlast  = 0;

    wire [N_E*16-1:0] m_axis_tdata;
    wire [N_E-1:0]    m_axis_tvalid;
    wire [N_E-1:0]    m_axis_tready_w = {N_E{1'b1}};  // always-ready sink (matches old drain)
    wire [N_E-1:0]    m_axis_tlast;

    // capture aliases so existing capture logic keeps its names
    wire [N_E-1:0]    o_e    = m_axis_tvalid;
    wire [N_E*16-1:0] o_data = m_axis_tdata;
    wire [N_E-1:0]    o_last = m_axis_tlast;

    jls_encoder_axis #(.N_E(N_E), .N_H(N_H), .N_V(N_V)) dut (
        .rstn          (rstn),
        .clk           (clk),
        .clk_in1_p     (clk_in1_p),
        .clk_in1_n     (clk_in1_n),
        .sys_rdy       (sys_rdy),
        .i_sof         (i_sof),
        .i_w           (i_w),
        .i_h           (i_h),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready_w),
        .m_axis_tlast  (m_axis_tlast)
    );
```

- [ ] **Step 4: Replace the `i_sof` pulse block with a PGM-reading AXIS driver**

Replace the old `// Pulse i_sof` initial block (`tb_top_jls_vertical.v:51-57`) with: open the PGM,
parse `W`/`H`, set sideband dims, pulse `i_sof`, then stream pixels on `s_axis`:

```verilog
    // ---- PGM source -> AXIS slave ----
    integer fp, hdr_len, fw, fh, fdepth, sret, p;
    reg [8*256-1:0] hline;
    initial begin
        fp = $fopen(PGM_FILE, "rb");
        if (fp == 0) begin $display("TB: cannot open %s", PGM_FILE); $finish; end
        hdr_len = $fgets(hline, fp);                       // "P5"
        hdr_len = $fgets(hline, fp);                       // "W H" (skip # comments)
        while (hline[8*(hdr_len-1) +: 8] == 8'h0A && hline[8*(hdr_len-2) +: 8] == 8'h23)
            hdr_len = $fgets(hline, fp);
        sret = $sscanf(hline, "%d %d", fw, fh);
        if (sret < 2) begin
            sret = $sscanf(hline, "%d", fw);
            hdr_len = $fgets(hline, fp); sret = $sscanf(hline, "%d", fh);
        end
        hdr_len = $fgets(hline, fp);                       // maxval
        sret = $sscanf(hline, "%d", fdepth);

        wait (sys_rdy);
        @(posedge clk);
        i_w = fw[15:0];
        i_h = fh[13:0];
        @(posedge clk);
        i_sof = 1; @(posedge clk); i_sof = 0;              // SOF pulse

        // stream W*H bytes with AXIS handshake (advance only when tready)
        for (p = 0; p < fw*fh; p = p + 1) begin
            s_axis_tdata  = $fgetc(fp);
            s_axis_tvalid = 1;
            s_axis_tlast  = (p == fw*fh - 1);
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);          // hold until accepted
        end
        s_axis_tvalid = 0; s_axis_tlast = 0;
        $fclose(fp);
    end
```

- [ ] **Step 5: Keep the capture, watchdog, EOI, and BENCHMARK_RESULT logic unchanged**

The output-capture `always @(posedge clk)` block, `do_close`, watchdog, and the final
`$fwrite`/`BENCHMARK_RESULT` initial block (`tb_top_jls_vertical.v:96-222`) reference `o_e`,
`o_data`, `i_w`, `i_h` — all still valid via the aliases and the `i_w`/`i_h` regs above. Leave
them as-is. The debug blocks that probe `dut.u_image_generator.pix_cnt`
(`tb_top_jls_vertical.v:256-264`) must change: replace `dut.u_image_generator.pix_cnt` with
`dut.u_axis_pixel_in.pix_cnt`.

- [ ] **Step 6: Verify the TB elaborates** (deferred to A6 full build — it needs all submodules).

- [ ] **Step 7: Commit**

```bash
git add -A "JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/"
git commit -m "test: tb_jls_encoder_axis drives the AXIS slave from a PGM source"
```

## Task A5: Update the sim compile list + sweep script for the renames

**Files:**
- Modify: `JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_top_jls_vertical_vlog.prj`
- Modify: `JPEG_ENC_8f.sim/sim_1/behav/xsim/run_hv_benchmark.ps1`

- [ ] **Step 1: Fix the `.prj` file list**

In `tb_top_jls_vertical_vlog.prj`: (a) remove the `image_generator.v` line; (b) change the
`…/top_jls_vertical.v` line to `…/jls_encoder_axis.v`; (c) change the
`…/tb_top_jls_vertical.v` line to `…/tb_jls_encoder_axis.v`; (d) confirm the `axis_pixel_in.v`
line added in A1 is present. (Optionally rename the file to `tb_jls_encoder_axis_vlog.prj`; if so,
update the `xvlog -prj` argument in the script.)

- [ ] **Step 2: Fix the sweep script module names**

In `run_hv_benchmark.ps1`: change the `xelab` elaboration target
`xil_defaultlib.tb_top_jls_vertical` → `xil_defaultlib.tb_jls_encoder_axis`; the `--snapshot`
name `tb_top_jls_vertical_behav` → `tb_jls_encoder_axis_behav` (and the matching `xsim …_behav`
arg). Update `$tbFile` (line 47) to the new TB path. The `Set-PgmFile` substitution now targets
the **TB** `PGM_FILE` parameter (the image source moved into the TB) — point `$imgGen` at
`$tbFile` and keep the same `parameter\s+PGM_FILE\s*=\s*"…"` regex (it matches the TB param added
in A4). `Set-TbParams` (N_E/N_H/N_V/MAX_BYTES) is unchanged. `BENCHMARK_RESULT` parsing unchanged.

- [ ] **Step 3: Commit**

```bash
git add "JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_top_jls_vertical_vlog.prj" "JPEG_ENC_8f.sim/sim_1/behav/xsim/run_hv_benchmark.ps1"
git commit -m "build(sim): update compile list + sweep for AXIS rename, drop image_generator"
```

## Task A6: Behavioral lossless regression (the Part-A gate)

**Files:** none (run only)

- [ ] **Step 1: Run the sweep for 300×300, all three modes**

```powershell
& "D:\techbistro\upwork\JPEG_Encoder_Project\JPEG_ENC_8f\JPEG_ENC_8f.sim\sim_1\behav\xsim\run_hv_benchmark.ps1" -Images 300x300 -Grids 2x2 -Modes block,vertical,horizontal
```
Expected: three `BENCHMARK_RESULT` lines; output files
`output_h2v2_300x300.jls`, `output_h4v1_300x300.jls`, `output_h1v4_300x300.jls` in
`JPEG_ENC_8f.sim/output_block/`. (Ratios ~7.5:1, matching pre-refactor numbers.)

- [ ] **Step 2: Verify bit-exact lossless**

```powershell
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h2v2_300x300.jls" "JPEG_ENC_8f.sim/images/world_gray_300x300.pgm" 2 2
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h4v1_300x300.jls" "JPEG_ENC_8f.sim/images/world_gray_300x300.pgm" 4 1
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h1v4_300x300.jls" "JPEG_ENC_8f.sim/images/world_gray_300x300.pgm" 1 4
```
Expected: `LOSSLESS: exact match (300x300)` for all three. **This proves the AXIS refactor changed
no encoding behavior.** If any differ, debug before proceeding (compare against the pre-refactor
`.jls` byte-for-byte; the most likely culprit is the A2 read-domain slice or the A4 handshake).

- [ ] **Step 3: Run the 1500×1500 regression**

```powershell
& "…\run_hv_benchmark.ps1" -Images 1500x1500 -Grids 2x2 -Modes block,vertical,horizontal
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h2v2_1500x1500.jls" "JPEG_ENC_8f.sim/images/world_gray_1500x1500.pgm" 2 2
```
Expected: ratio ~4.17:1, `LOSSLESS: exact match (1500x1500)`.

- [ ] **Step 4: Commit the regression results**

```bash
git add "JPEG_ENC_8f.sim/output_block/hv_benchmark_results.csv"
git commit -m "test: AXIS refactor passes lossless regression (300/1500, all modes)"
```

## Task A7: Backpressure sim check (AXIS master correctness)

Prove the A2 slice loses no data when the consumer stalls.

**Files:**
- Modify (temporarily): `tb_jls_encoder_axis.v` — drive `m_axis_tready_w` with a stall pattern

- [ ] **Step 1: Add a stall generator** — replace the constant ready with a toggling pattern:

```verilog
    reg [3:0] rdy_lfsr = 4'hF;
    always @(posedge clk) rdy_lfsr <= {rdy_lfsr[2:0], rdy_lfsr[3]^rdy_lfsr[2]};
    wire [N_E-1:0] m_axis_tready_w = {N_E{rdy_lfsr[0]}};   // ~50% backpressure
```

- [ ] **Step 2: Run 300×300 block + verify lossless**

```powershell
& "…\run_hv_benchmark.ps1" -Images 300x300 -Grids 2x2 -Modes block
python verify_lossless.py "JPEG_ENC_8f.sim/output_block/output_h2v2_300x300.jls" "JPEG_ENC_8f.sim/images/world_gray_300x300.pgm" 2 2
```
Expected: identical output bytes to A6 (`LOSSLESS: exact match`). Backpressure must not change the
compressed stream — only its timing.

- [ ] **Step 3: Revert to constant-ready and commit the verified state**

Restore `wire [N_E-1:0] m_axis_tready_w = {N_E{1'b1}};` (the demo/TB sink). Commit:
```bash
git add "JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/tb_jls_encoder_axis.v"
git commit -m "test: verify AXIS master is lossless under tready backpressure"
```

---

# PART B — Bitstream harness + synth/impl/timing closure

The gate for Part B is: **`impl_1` reaches `write_bitstream` with WNS ≥ 0**, with utilization,
achieved clock, and throughput reported.

## Task B1: ROM image + `axis_image_source.v`

**Files:**
- Create: `tools/pgm_to_hex.py`
- Create: `JPEG_ENC_8f.srcs/sources_1/new/rom_image.hex` (generated)
- Create: `JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v`

- [ ] **Step 1: Write the PGM→hex converter**

```python
# tools/pgm_to_hex.py  —  usage: python tools/pgm_to_hex.py in.pgm out.hex
import sys
def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, "rb") as f:
        data = f.read()
    # parse P5 header: magic, (comments), "W H", maxval, then raw bytes
    idx = 0
    def token(i):
        while data[i:i+1].isspace(): i += 1
        if data[i:i+1] == b'#':
            while data[i:i+1] != b'\n': i += 1
            return token(i)
        j = i
        while not data[j:j+1].isspace(): j += 1
        return data[i:j], j
    magic, idx = token(idx); assert magic == b'P5', magic
    w, idx = token(idx); h, idx = token(idx); mx, idx = token(idx)
    idx += 1  # single whitespace after maxval
    w, h = int(w), int(h)
    px = data[idx:idx + w*h]
    with open(dst, "w") as f:
        for b in px:
            f.write("%02X\n" % b)
    print("wrote %d bytes (%dx%d) to %s" % (len(px), w, h, dst))
if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Generate a small ROM image (64×64) from an existing PGM**

A 64×64 image keeps the ROM at 4096×8 (1 BRAM) and the sim/impl fast. Crop with Python:
```powershell
python -c "import sys; d=open('JPEG_ENC_8f.sim/images/world_gray_300x300.pgm','rb').read(); i=d.index(b'255')+4; px=bytearray();
[px.extend(d[i+r*300:i+r*300+64]) for r in range(64)];
open('JPEG_ENC_8f.sim/images/rom_64x64.pgm','wb').write(b'P5\n64 64\n255\n'+bytes(px))"
python tools/pgm_to_hex.py JPEG_ENC_8f.sim/images/rom_64x64.pgm "JPEG_ENC_8f.srcs/sources_1/new/rom_image.hex"
```
Expected: `wrote 4096 bytes (64x64) to …/rom_image.hex`.

- [ ] **Step 3: Write the synthesizable AXIS source**

```verilog
`timescale 1ns/1ps
// On-chip AXIS pixel source for the bitstream harness. A $readmemh ROM streams a
// fixed image; self-starts after rstn. Drives the sideband dims + i_sof. Synthesizable
// (inferred block ROM).
module axis_image_source #(
    parameter integer IMG_W   = 64,
    parameter integer IMG_H   = 64,
    parameter         HEXFILE = "rom_image.hex"
)(
    input  wire        clk,
    input  wire        rstn,           // = sys_rdy
    output reg  [15:0] i_w,
    output reg  [13:0] i_h,
    output reg         i_sof,
    output reg  [7:0]  s_axis_tdata,
    output reg         s_axis_tvalid,
    input  wire        s_axis_tready,
    output reg         s_axis_tlast
);
    localparam integer N = IMG_W * IMG_H;
    (* rom_style = "block" *) reg [7:0] rom [0:N-1];
    initial $readmemh(HEXFILE, rom);

    localparam S_IDLE=2'd0, S_SOF=2'd1, S_RUN=2'd2, S_DONE=2'd3;
    reg [1:0]  state;
    reg [31:0] addr;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= S_IDLE; addr <= 0; i_sof <= 0;
            i_w <= 0; i_h <= 0; s_axis_tdata <= 0; s_axis_tvalid <= 0; s_axis_tlast <= 0;
        end else begin
            i_sof <= 1'b0;
            case (state)
                S_IDLE: begin
                    i_w <= IMG_W[15:0]; i_h <= IMG_H[13:0];
                    i_sof <= 1'b1;                 // one-shot SOF
                    addr  <= 0; state <= S_SOF;
                end
                S_SOF: begin                       // wait until the IP is ready for pixels
                    s_axis_tdata  <= rom[0];
                    s_axis_tvalid <= 1'b1;
                    s_axis_tlast  <= (N == 1);
                    if (s_axis_tvalid && s_axis_tready) begin
                        addr  <= 1;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (addr == N) begin
                            s_axis_tvalid <= 1'b0; s_axis_tlast <= 1'b0; state <= S_DONE;
                        end else begin
                            s_axis_tdata <= rom[addr];
                            s_axis_tlast <= (addr == N-1);
                            addr <= addr + 1;
                        end
                    end
                end
                S_DONE: s_axis_tvalid <= 1'b0;
            endcase
        end
    end
endmodule
```

- [ ] **Step 4: Commit**

```bash
git add tools/pgm_to_hex.py "JPEG_ENC_8f.srcs/sources_1/new/rom_image.hex" "JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v"
git commit -m "feat(harness): synthesizable AXIS ROM image source + PGM->hex tool"
```

## Task B2: `jls_demo_top.v` — bitstream top

**Files:**
- Create: `JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v`

- [ ] **Step 1: Write the harness top**

Self-contained: `axis_image_source` → `jls_encoder_axis` → output pins (reuse old XDC pins).
`m_axis_tready` tied high (constant-ready sink). The encoder outputs drive real pins so synthesis
cannot prune the design.

```verilog
`timescale 1ns/1ps
module jls_demo_top #(
    parameter integer N_E   = 2,
    parameter integer N_H   = 2,
    parameter integer N_V   = 1,
    parameter integer IMG_W = 64,
    parameter integer IMG_H = 64
)(
    input  wire              rstn,
    input  wire              clk_in1_p,
    input  wire              clk_in1_n,
    output wire              clk,
    output wire [N_E-1:0]    o_e,
    output wire [N_E-1:0]    o_last,
    output wire [N_E*16-1:0] o_data
);
    wire        sys_rdy;
    wire [15:0] src_w;
    wire [13:0] src_h;
    wire        src_sof;
    wire [7:0]  src_tdata;
    wire        src_tvalid;
    wire        src_tready;
    wire        src_tlast;

    axis_image_source #(.IMG_W(IMG_W), .IMG_H(IMG_H), .HEXFILE("rom_image.hex")) u_src (
        .clk(clk), .rstn(sys_rdy),
        .i_w(src_w), .i_h(src_h), .i_sof(src_sof),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast)
    );

    jls_encoder_axis #(.N_E(N_E), .N_H(N_H), .N_V(N_V)) u_ip (
        .rstn(rstn), .clk(clk), .clk_in1_p(clk_in1_p), .clk_in1_n(clk_in1_n),
        .sys_rdy(sys_rdy),
        .i_sof(src_sof), .i_w(src_w), .i_h(src_h),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast),
        .m_axis_tdata(o_data), .m_axis_tvalid(o_e),
        .m_axis_tready({N_E{1'b1}}), .m_axis_tlast(o_last)
    );
endmodule
```

- [ ] **Step 2: Compile-check**

```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v" "../../../../JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v" -log xvlog_demo.log
```
Expected: analyzes `jls_demo_top` with no errors.

- [ ] **Step 3: Commit**

```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v"
git commit -m "feat(harness): jls_demo_top self-contained bitstream top"
```

## Task B3: `jls_demo_top.xdc` — pin/timing constraints

**Files:**
- Create: `JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_demo_top.xdc`

- [ ] **Step 1: Build the XDC from the known-good pins**

Read `top_jls_vertical.xdc` and copy the constraint lines for: `clk_in1_p` (R3, LVDS_25),
`clk_in1_n` (P3, LVDS_25), `rstn` (R8, LVCMOS25, `set_false_path -from`), and the PACKAGE_PIN +
IOSTANDARD lines for the output ports `o_e[0]`,`o_e[1]`, `o_last[0]`,`o_last[1]`, and
`o_data[0..31]` (the old file's `o_e0/o_e1`, `o_last0/o_last1`, `o_data0[15:0]`/`o_data1[15:0]`
pins — same package pins, just bus-indexed names). Do **not** copy the `i_e`/`i_x`/`i_w`/`i_h`
input-port lines (those ports no longer exist). Add the encoder clock period constraint so timing
is analyzed:
```tcl
# clk_wiz generates clk (33.33 MHz) and rd_clk (10 MHz) from the 200 MHz diff input;
# create_clock on the source lets the tool derive both via the MMCM.
create_clock -name sys_clk_pin -period 5.000 [get_ports clk_in1_p]
```
(200 MHz diff input = 5 ns period. The MMCM-generated clocks are auto-constrained.)

- [ ] **Step 2: Commit**

```bash
git add "JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_demo_top.xdc"
git commit -m "feat(harness): jls_demo_top XDC (reuse AC701 clk/reset/output pins)"
```

## Task B4: Add sources to the Vivado project + set synth top (TCL)

**Files:**
- Create: `JPEG_ENC_8f.sim/sim_1/behav/xsim/build_synth.tcl`

- [ ] **Step 1: Write the project-prep + synth TCL**

```tcl
# build_synth.tcl  —  run: vivado -mode batch -source build_synth.tcl
open_project D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.xpr

# refresh source set: drop the renamed/removed files, add the new ones
catch { remove_files [get_files -quiet image_generator.v] }
catch { remove_files [get_files -quiet top_jls_vertical.v] }
add_files -norecurse {
  "JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v"
  JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v
  JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v
  JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v
}
add_files -fileset constrs_1 -norecurse "JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_demo_top.xdc"
# rom_image.hex must be found by $readmemh at elaboration — add as a design source
add_files -norecurse JPEG_ENC_8f.srcs/sources_1/new/rom_image.hex

set_property top jls_demo_top [get_filesets sources_1]
# retire the old top_jls_vertical.xdc from the active constraints
catch { set_property is_enabled false [get_files -quiet top_jls_vertical.xdc] }
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
open_run synth_1
report_utilization -file synth_util.rpt
report_timing_summary -file synth_timing.rpt
puts "SYNTH DONE"
```

- [ ] **Step 2: Run synthesis**

```powershell
cd "D:\techbistro\upwork\JPEG_Encoder_Project\JPEG_ENC_8f"
vivado -mode batch -source JPEG_ENC_8f.sim\sim_1\behav\xsim\build_synth.tcl -log build_synth.vlog
```
Expected: `synth_1` completes (`Synth Design complete`), `SYNTH DONE`, and `synth_util.rpt` /
`synth_timing.rpt` are written. **Inspect `synth_util.rpt`** (expect BRAM ≈ 2 line buffers ≈ 17%,
LUT/FF modest) and `synth_timing.rpt` (note WNS; at 33.33/10 MHz it should be large-positive).

- [ ] **Step 3: Triage any synthesis errors**

Likely issues and fixes (all should already be handled by Part A, verify):
- `$readmemh` file not found → ensure `rom_image.hex` is added and path is relative to the run dir
  (use `HEXFILE` with just the filename; Vivado searches the source set).
- multiple-driver / undriven top output → confirm `o_data`/`o_e`/`o_last` come only from the IP.
- black-box `clk_wiz_0`/`fifo_*`/`fifo_output` → ensure the IPs are generated
  (`generate_target all [get_ips]` if needed).

- [ ] **Step 4: Commit**

```bash
git add "JPEG_ENC_8f.sim/sim_1/behav/xsim/build_synth.tcl" synth_util.rpt synth_timing.rpt JPEG_ENC_8f.xpr
git commit -m "build(synth): synth_1 closes for jls_demo_top; util+timing reports"
```

## Task B5: Implementation → bitstream (timing closure)

**Files:**
- Create: `JPEG_ENC_8f.sim/sim_1/behav/xsim/build_impl.tcl`

- [ ] **Step 1: Write the impl TCL**

```tcl
# build_impl.tcl  —  run: vivado -mode batch -source build_impl.tcl
open_project D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.xpr
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
open_run impl_1
report_utilization        -file impl_util.rpt
report_timing_summary     -file impl_timing.rpt
set wns [get_property STATS.WNS [get_runs impl_1]]
puts "IMPL DONE  WNS=$wns"
```

- [ ] **Step 2: Run implementation**

```powershell
vivado -mode batch -source JPEG_ENC_8f.sim\sim_1\behav\xsim\build_impl.tcl -log build_impl.vlog
```
Expected: `impl_1` reaches `write_bitstream`, `jls_demo_top.bit` appears under
`JPEG_ENC_8f.runs/impl_1/`, and `IMPL DONE WNS=<positive>`. Confirm **WNS ≥ 0** in
`impl_timing.rpt` (Design Timing Summary). At 33.33/10 MHz closure is expected with large slack.

- [ ] **Step 3: If WNS < 0** (unlikely at these clocks): read the failing paths in
`impl_timing.rpt`, identify the worst path (likely inside `jls_encoder` context-RAM feedback). For
a guaranteed-closing first bitstream, lower the encoder clock: in `clk_wiz_0.xci` raise
`MMCM_CLKOUT1_DIVIDE` (slower `rd_clk`), `generate_target all [get_ips clk_wiz_0]`, and re-run
B5. Record the clock that closes.

- [ ] **Step 4: Commit the build artifacts + reports**

```bash
git add impl_util.rpt impl_timing.rpt
git commit -m "build(impl): timing-closed bitstream for jls_demo_top (WNS>=0)"
```

## Task B6: Probe real Fmax (optional throughput milestone)

**Files:**
- Modify: `JPEG_ENC_8f.gen/.../clk_wiz_0.xci` (or via TCL `set_property`)

- [ ] **Step 1: Raise the encoder clock toward Fmax**

The first bitstream closes trivially at 10 MHz. To report realistic throughput, raise `rd_clk`
(and `wr_clk`) and re-close. Reconfigure `clk_wiz_0` for `clk_out2` (rd_clk) = 100 MHz
(`MMCM_CLKOUT1_DIVIDE = 6` with MULT=3 → wait: 200×3/… ; set requested freq via TCL):
```tcl
open_project …/JPEG_ENC_8f.xpr
set_property -dict [list \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100.000}] [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
```

- [ ] **Step 2: Re-run synth + impl (B4/B5 TCL), read WNS**

If WNS ≥ 0 at 100 MHz, that's the deliverable clock. If negative, step the requested freq down
(90, 80, …) until WNS ≥ 0. **Record the highest closing rd_clk.** Real throughput ≈ that clock ×
1 pixel/cycle per active encoder column (N_H), e.g. 100 MHz × 2 = 200 Mpix/s = 1.6 Gb/s at the
8-bit input.

- [ ] **Step 3: Commit the final clock + reports**

```bash
git add JPEG_ENC_8f.gen JPEG_ENC_8f.srcs/sources_1/ip/clk_wiz_0 impl_timing.rpt impl_util.rpt
git commit -m "build: close timing at highest stable rd_clk; record real throughput"
```

## Task B7: Document results

**Files:**
- Modify: `JPEG_ENC_8f.sim/output_block/BENCHMARKS.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a "Synthesis / Bitstream" section** to `BENCHMARKS.md` with: device, top
(`jls_demo_top`), config (N_E=2, 2×1), utilization (LUT/FF/BRAM/DSP from `impl_util.rpt`), achieved
clock (from B6), WNS, and computed throughput (Mpix/s and Gb/s).

- [ ] **Step 2: Update `CLAUDE.md`** — replace the "500 MHz / 4 Gb/s sim-only" clocking note with
the real synthesizable result: `jls_encoder_axis` is the AXIS IP, `jls_demo_top` is the bitstream
top, lossless-only (NEAR removed), achieved clock + throughput, and that `image_generator` is gone
(TB sources pixels via AXIS). Note 4 Gb/s is a sim-only/architectural figure, not synthesizable.

- [ ] **Step 3: Commit**

```bash
git add "JPEG_ENC_8f.sim/output_block/BENCHMARKS.md" CLAUDE.md
git commit -m "docs: record synthesizable AXIS IP results (util, Fmax, throughput)"
```

---

## Self-Review (against the spec)

**Spec coverage:**
- AXIS slave input → Task A1, A3. ✓
- AXIS master output + tready backpressure → A2, A3, A7. ✓
- Sideband i_w/i_h/i_sof → A1, A3, A4. ✓
- NEAR removed (lossless only) → background note + A3 (nr=0 parameter kept). ✓
- On-chip BRAM AXIS source harness → B1, B2. ✓
- N_E=2 / 2×1 config → A3 defaults, B2. ✓
- Rename top_jls_vertical → jls_encoder_axis → A3, A5, B4. ✓
- Behavioral lossless regression → A6, A7. ✓
- Synthesis (util + Fmax) → B4. ✓
- Implementation → bitstream, WNS ≥ 0 → B5, B6. ✓
- Report achieved clock/throughput/util → B6, B7. ✓
- clk_wiz: keep dual-clock, measure Fmax → background + B5/B6. ✓
- image_generator removed from synthesizable hierarchy → A5, B4. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code; commands have expected
output. The one judgment call left to the implementer is the exact output-pin lines copied from
`top_jls_vertical.xdc` in B3 — that's a concrete copy instruction, not a placeholder.

**Type/name consistency:** `axis_pixel_in` ports (`i_w_in`/`i_h_in`/`fifo_overflow`/`s_axis_*`/
`pixel_out`/`pixel_valid`/`i_sof_st`) are consistent across A1↔A3. `fifo_wrapper_output` gains
`m_axis_tready` (A2) used in A3 Step 5. `jls_encoder_axis` port names (A3 Step 2) match the DUT
instance in A4 Step 3 and the B2 `jls_demo_top` instance. `axis_image_source` ports (B1) match the
B2 instance. ✓

## Risks (carried from the spec)

- **A2 read-domain slice** is the trickiest change; A6 (lossless regression) and A7 (backpressure)
  are the guards. If A6 fails, diff the new `.jls` against a pre-refactor capture to localize.
- **`$readmemh` ROM** must be reachable at synth elaboration — added as a design source in B4.
- **First bitstream at 10 MHz** closes by construction; B6 separately pushes for a realistic Fmax.
