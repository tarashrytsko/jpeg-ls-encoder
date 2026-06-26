# Wide-Input 16-Lane JPEG-LS Encoder (~512 MB/s) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reach ~512 MB/s synthesizable, timing-closed JPEG-LS throughput on `xc7a200tfbg676-2` by feeding **16 parallel encoder lanes** with a **128-bit column-strided wide input** (16 pixels/cycle) at ~32 MHz.

**Architecture:** Keep the dual-clock + splitter + per-lane async-FIFO structure (option C). Widen the AXIS slave + splitter from 1 pixel/cycle to 16 (one per vertical column-strip, lockstep over intra-strip (xs,ys)); the N_E-parameterized pipeline instantiates 16 lanes; the encoder core is unchanged but its line buffer is parameterized to the (narrow) strip width and the FIFOs are regenerated shallow so 16 lanes fit (~20% BRAM). Builds on the `jls_encoder_axis`/`jls_demo_top` AXIS design (branch `feature/jls-encoder-axis`).

**Tech Stack:** Verilog-2001, Vivado 2024.2 (xsim + synth_1/impl_1), PowerShell sweep, Python verifier/ROM tools.

---

## Background facts (verified)

- **Splitter** `block_split.v` (module `splitter_block`) is a 1-pixel/cycle time-mux: tracks global (x_cnt,y_cnt), computes `encoder_sel` from block geometry, routes one `i_x[7:0]` to `o_x[encoder_sel*8+:8]`. SOF handling: waits for `i_sof_st` (SOF stretch) to fall → `frame_active`. We replace the per-pixel mux with a 16-wide lockstep broadcast over **intra-strip** (xs,ys).
- **Encoder** `jls_encoder.v`: line buffer `reg [7:0] linebuffer [0:(1<<14)-1]` (line ~1477), indexed by `a_ii`/`e_ii` ∈ `[0, a_wl]` where `a_wl = blk_w-1` (strip width−1, line 348/471). So only `stripW` entries are used → safe to parameterize depth to `LB_DEPTH` (≥ max stripW). `blk_w` per lane = `col_w = i_w/N_H`, computed in `encoder_wrapper`.
- **encoder_wrapper** already derives per-lane `col_w = i_w/N_H` and `row_h = i_h/N_V` and passes them to each `jls_encoder` — so with `N_H=16,N_V=1` each lane encodes a `(i_w/16) × i_h` strip. **No change needed there.**
- **`jls_encoder_axis`** (AXIS IP): `s_axis_tdata[7:0]` → widen to `[N_E*8-1:0]` (128-bit); params become `N_E=16,N_H=16,N_V=1`.
- **`axis_pixel_in`**: FSM S_IDLE→S_SOF(stretch 3000)→S_PIXEL; `pixel_out[7:0]`/`pixel_valid`; `total_pixels=i_w*i_h`. Widen `pixel_out` to 128-bit and count `pix_cnt += N_E` per transfer.
- **FIFO IPs**: `fifo_generator_0` (input) depth 131072, `fifo_output` depth 65536 — regenerate shallow (512 / 2048) to cut per-lane BRAM from ~33 to ~2.5.
- **Verifier** `verify_lossless.py <jls> <pgm> <N_H> <N_V>` reassembles an N_H×N_V grid; use `16 1`.

---

## File Structure

**Modified RTL** (in `JPEG_ENC_8f.srcs/sources_1/`):
- `imports/FPGA Encoders/jls_encoder.v` — parameterize line-buffer depth (`LB_DEPTH`).
- `new/axis_pixel_in.v` — 128-bit data, count `+= N_E`/transfer.
- `new/block_split.v` — 16-wide lockstep broadcast + intra-strip counter.
- `imports/FPGA Encoders/jls_encoder_axis.v` — 128-bit `s_axis_tdata`; `N_E=16,N_H=16,N_V=1`.
- `new/jls_demo_top.v` — 128-bit, 16-lane, status output (rewritten for wide harness).
- `new/axis_image_source.v` — 128-bit column-strided ROM source (rewritten).

**New**
- `new/axis_sink.v` — 16-lane on-chip sink (byte counts + checksum + done).
- `constrs_1/imports/new/jls_demo_top_wide.xdc` — diff clk, reset, status pins.
- `sim_1/imports/FPGA Encoders/tb_jls_wide.v` — 16-lane TB (capture 16 streams).
- `JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_jls_wide_vlog.prj` — sim compile list.
- `tools/make_strided_rom.py` — build column-strided ROM hex from a PGM.
- `tools/pgm_to_strided_hex.py` (if separate from TB feed).
- Build TCL: `build_wide_synth.tcl`, `build_wide_impl.tcl`.

**IP reconfig (TCL):** `fifo_generator_0` depth→512, `fifo_output` depth→2048; clk_wiz `rd_clk`≈32 MHz / `wr_clk`≈32 MHz.

---

# PART A — Wide datapath + behavioral lossless gate

Gate: a 16-strip image fed wide is **bit-exact lossless** (`verify_lossless.py … 16 1`).

## Task A1: Parameterize the encoder line-buffer depth

**Files:** Modify `JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder.v`

- [ ] **Step 1: Add an `LB_DEPTH` parameter.** In the `module jls_encoder #( … )` parameter list (after `parameter L=64`), add:
```verilog
    ,parameter integer LB_DEPTH = 1024   // line buffer depth = max strip width (i_w/N_H). 1024 -> max image width 16384
```

- [ ] **Step 2: Use it for the line buffer.** Find `reg [7:0] linebuffer [0:(1<<14)-1];` (~line 1477) and replace with:
```verilog
    reg [7:0] linebuffer [0:LB_DEPTH-1];
```
Leave the read (`c_d <= linebuffer[a_ii];`) and write (`if(e_e) linebuffer[e_ii] <= e_x;`) unchanged — `a_ii`/`e_ii` ∈ [0, a_wl] = [0, stripW-1] ≤ LB_DEPTH-1.

- [ ] **Step 3: Compile-check.** From `JPEG_ENC_8f.sim/sim_1/behav/xsim/`:
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder.v" -log xvlog_jls.log
```
Expected: analyzes `jls_encoder`, no errors.

- [ ] **Step 4: Thread `LB_DEPTH` down.** In `encoder_wrapper.v`, the `jls_encoder` instantiation (inside the `ENC_INST` generate) — add `.LB_DEPTH(1024)` to its `#( … )` parameter map (keep existing `NEAR`/`N_E`/`L`). Compile-check `encoder_wrapper.v` similarly. Commit:
```bash
git add "JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder.v" "JPEG_ENC_8f.srcs/sources_1/new/encoder_wrapper.v"
git commit -m "feat(wide): parameterize jls_encoder line-buffer depth (LB_DEPTH=1024)"
```

## Task A2: Widen `axis_pixel_in` to 128-bit

**Files:** Modify `JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v`

- [ ] **Step 1: Widen data ports + count.** Change `s_axis_tdata` and `pixel_out` from `[7:0]` to `[N_E*8-1:0]`, and increment the pixel count by `N_E` per transfer (each transfer carries N_E pixels). Replace the port lines and the S_PIXEL increment:
  - Port: `input  wire [N_E*8-1:0] s_axis_tdata,` and `output reg [N_E*8-1:0] pixel_out,`
  - In `S_PIXEL`, the accept block becomes:
```verilog
                S_PIXEL: begin
                    if (pix_cnt < total_pixels) begin
                        if (s_axis_tvalid && s_axis_tready) begin
                            pixel_out   <= s_axis_tdata;
                            pixel_valid <= 1'b1;
                            pix_cnt     <= pix_cnt + N_E;   // N_E pixels per wide transfer
                        end
                    end else begin
                        state <= S_DONE;
                    end
                end
```
  (`total_pixels <= i_w_in * i_h_in;` in S_IDLE stays — full pixel count; pix_cnt advances N_E/transfer so it reaches total after (i_w*i_h)/N_E transfers.)

- [ ] **Step 2: Compile-check + commit.**
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v" -log xvlog_api.log
```
```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v"
git commit -m "feat(wide): axis_pixel_in carries N_E pixels/cycle (128-bit)"
```

## Task A3: Widen `block_split` to 16-pixel lockstep broadcast

This is the crux. Replace the 1-pixel time-mux with a 16-wide broadcast over **intra-strip** (xs,ys). Each cycle all N_E lanes get a pixel (lane k ← `i_x[k*8+:8]`).

**Files:** Modify `JPEG_ENC_8f.srcs/sources_1/new/block_split.v`

- [ ] **Step 1: Widen `i_x` + rewrite the routing.** Change the port `input wire [7:0] i_x,` → `input wire [N_E*8-1:0] i_x,`. Then replace the body from the "Pixel counters" block through the "DATA routing" block with the intra-strip + broadcast logic below (keep the parameters, the `i_sof_st` falling-edge detect, and the `frame_active_after_stretch` latch — but change its end-of-frame test to the intra-strip end):

Replace the pixel-counter `always` block, the block-geometry/`encoder_sel` logic, and the data-routing `always` block with:
```verilog
    // strip width (per lane). Each lane encodes a stripW x i_h sub-image.
    wire [15:0] stripW = i_w / N_H;

    // intra-strip counters (shared across all lanes - lockstep)
    reg [15:0] xs;
    reg [13:0] ys;
    always @(posedge clk) begin
        if (!sys_rdy || i_sof) begin
            xs <= 0; ys <= 0;
        end else if (i_e && frame_active) begin
            if (xs == stripW-1) begin
                xs <= 0;
                if (ys < i_h-1) ys <= ys + 1;
            end else xs <= xs + 1;
        end
    end

    assign encoder_sel_comb = {$clog2(N_E){1'b0}};

    integer k;
    always @(posedge clk) begin
        if (!sys_rdy) begin
            o_e <= 0; o_x <= 0; o_w <= 0; o_h <= 0; o_last_enc <= 0;
        end else begin
            o_e <= 0; o_x <= 0; o_last_enc <= 0;
            for (k=0; k<N_E; k=k+1) begin
                o_w[k*16 +:16] <= i_w;   // full width; encoder_wrapper derives col_w=i_w/N_H
                o_h[k*14 +:14] <= i_h;
            end
            if (i_e && frame_active) begin
                for (k=0; k<N_E; k=k+1) begin
                    o_e[k] <= 1'b1;
                    o_x[k*8 +:8] <= i_x[k*8 +:8];     // lane k <- strip k's pixel
                    if (xs == stripW-1 && ys == i_h-1)
                        o_last_enc[k] <= 1'b1;
                end
            end
        end
    end

    always @(posedge clk) begin
        x_cnt_d <= {1'b0, xs}; y_cnt_d <= ys; encoder_sel_d <= {$clog2(N_E){1'b0}};
    end
```
And change the `frame_active_after_stretch` end-of-frame test from `x_cnt == i_w-1 && y_cnt == i_h-1` to `xs == stripW-1 && ys == i_h-1`. Delete the now-unused block-geometry arrays (`blk_w_arr`/`blk_x_start`/etc.), the `clog2` function/`x_block_idx`/`block_idx`/`encoder_sel` wire, and the old `x_cnt`/`y_cnt` regs (replaced by `xs`/`ys`). Keep `i, k` integer decls as needed.

- [ ] **Step 2: Compile-check + commit.**
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/block_split.v" -log xvlog_split.log
```
```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/block_split.v"
git commit -m "feat(wide): splitter broadcasts N_E pixels/cycle over intra-strip (xs,ys)"
```

## Task A4: Widen `jls_encoder_axis` + set 16 lanes

**Files:** Modify `JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v`

- [ ] **Step 1: Params + wide slave.** Change defaults to `N_E=16, N_H=16, N_V=1`. Change the slave data port `input wire [7:0] s_axis_tdata,` → `input wire [N_E*8-1:0] s_axis_tdata,`. The internal `gen_x` wire (adapter→splitter) widens to `[N_E*8-1:0]`: change `wire [7:0] gen_x;` → `wire [N_E*8-1:0] gen_x;`. The `axis_pixel_in` instance and `splitter_block` instance already use `gen_x`/`s_axis_tdata` — they now carry 128-bit. No other connection changes (m_axis stays N_E×16 as before).

- [ ] **Step 2: Compile-check (analyze) + commit.**
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v" "../../../../JPEG_ENC_8f.srcs/sources_1/new/block_split.v" "../../../../JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v" -log xvlog_ip.log
```
Expected: `analyzing module jls_encoder_axis` no syntax error.
```bash
git add "JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v"
git commit -m "feat(wide): jls_encoder_axis 128-bit slave, N_E=16/N_H=16/N_V=1"
```

## Task A5: Shrink the FIFO IP depths

**Files:** TCL (run via vivado batch); regenerates `fifo_generator_0` + `fifo_output`.

- [ ] **Step 1: Write `JPEG_ENC_8f.sim/sim_1/behav/xsim/shrink_fifos.tcl`:**
```tcl
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr
config_ip_cache -disable_cache
set_property -dict [list CONFIG.Input_Depth {512}  CONFIG.Output_Depth {512}]  [get_ips fifo_generator_0]
set_property -dict [list CONFIG.Input_Depth {2048} CONFIG.Output_Depth {2048}] [get_ips fifo_output]
generate_target all [get_ips fifo_generator_0 fifo_output]
catch { reset_run fifo_generator_0_synth_1 }
catch { reset_run fifo_output_synth_1 }
catch { synth_ip [get_ips fifo_generator_0] }
catch { synth_ip [get_ips fifo_output] }
puts "FIFOS_SHRUNK in=[get_property CONFIG.Input_Depth [get_ips fifo_generator_0]] out=[get_property CONFIG.Input_Depth [get_ips fifo_output]]"
```

- [ ] **Step 2: Run it.**
```powershell
vivado -mode batch -source JPEG_ENC_8f.sim\sim_1\behav\xsim\shrink_fifos.tcl -log shrink_fifos.vlog -nojournal
```
Expected: `FIFOS_SHRUNK in=512 out=2048`. Confirm the `.xci` files now show the reduced depths.

- [ ] **Step 3: Commit** the changed `.xci` + regenerated `.gen` for the two IPs:
```bash
git add JPEG_ENC_8f.srcs/sources_1/ip/fifo_generator_0 JPEG_ENC_8f.srcs/sources_1/ip/fifo_output JPEG_ENC_8f.gen/sources_1/ip/fifo_generator_0 JPEG_ENC_8f.gen/sources_1/ip/fifo_output "JPEG_ENC_8f.sim/sim_1/behav/xsim/shrink_fifos.tcl"
git commit -m "feat(wide): shrink input FIFO 131072->512, output FIFO 65536->2048"
```

## Task A6: 16-lane testbench + column-strided PGM feed

**Files:** Create `tools/make_strided_hex.py`, `sim_1/imports/FPGA Encoders/tb_jls_wide.v`, `JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_jls_wide_vlog.prj`

- [ ] **Step 1: Strided-feed helper** `tools/make_strided_hex.py` — converts a PGM into the per-cycle 128-bit column-strided words (one 16-byte word per (ys,xs), each byte = strip k's pixel at (xs,ys)):
```python
# tools/make_strided_hex.py  —  python tools/make_strided_hex.py in.pgm out.hex N_H
import sys
def token(d,i):
    while d[i:i+1].isspace(): i+=1
    if d[i:i+1]==b'#':
        while d[i:i+1]!=b'\n': i+=1
        return token(d,i)
    j=i
    while not d[j:j+1].isspace(): j+=1
    return d[i:j],j
def main():
    src,dst,NH = sys.argv[1], sys.argv[2], int(sys.argv[3])
    d=open(src,'rb').read(); i=0
    mg,i=token(d,i); assert mg==b'P5'
    w,i=token(d,i); h,i=token(d,i); mx,i=token(d,i); i+=1
    w,h=int(w),int(h); px=d[i:i+w*h]
    assert w % NH == 0, "width must be divisible by N_H"
    sw=w//NH
    with open(dst,'w') as f:
        for ys in range(h):
            for xs in range(sw):
                # 128-bit word: byte k (k=0..NH-1) = strip k's pixel at (xs,ys)
                word=0
                for k in range(NH):
                    word |= px[ys*w + k*sw + xs] << (8*k)
                f.write("%032X\n" % word)
    print("wrote %d strided words (%dx%d, N_H=%d, stripW=%d) to %s"%(h*sw,w,h,NH,sw,dst))
if __name__=="__main__": main()
```

- [ ] **Step 2: Testbench** `tb_jls_wide.v` — adapt `tb_jls_encoder_axis.v` (READ it first): params `N_E=16,N_H=16,N_V=1,NUM_SLICES=1`; DUT `jls_encoder_axis #(.N_E(16),.N_H(16),.N_V(16==N_H?N_H:N_H)...)`—use `.N_E(16),.N_H(16),.N_V(1)`. Drive the wide slave from a strided `.hex` (read with `$readmemh` into a `reg [127:0] feed [0:h*sw-1]`), one 128-bit word per `@(posedge clk)` honoring `s_axis_tready`; set sideband `i_w=full_w`, `i_h=full_h`, pulse `i_sof`. Keep the per-lane capture (`o_e`/`o_data`/`o_last`) + EOI/`do_close` + `$fwrite` writing `output_h16v1_<W>x<H>.jls` in swath-major/enc-minor order, and the watchdog. (The feed `.hex` path + dims are TB parameters.)

- [ ] **Step 3: Sim compile list** `tb_jls_wide_vlog.prj` — copy `tb_top_jls_vertical_vlog.prj`, keep the same design sources (block_split, encoder_wrapper, fifo_read_control, fifo_reset_bram_async, fifo_wrapper_input, fifo_wrapper_output, fifo_write_control, jls_encoder, merger, jls_encoder_axis, axis_pixel_in, clk_wiz, fifo_generator_0, fifo_output), replace the TB line with `tb_jls_wide.v`. Commit A6:
```bash
git add tools/make_strided_hex.py "JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/tb_jls_wide.v" "JPEG_ENC_8f.sim/sim_1/behav/xsim/tb_jls_wide_vlog.prj"
git commit -m "test(wide): 16-lane testbench + column-strided PGM feed"
```

## Task A7: Behavioral lossless gate (16-strip reassembly)

**Files:** none (run only). Use a width-divisible-by-16 image (e.g. crop `world_gray_3000x3000.pgm` to 256×256 → `tools/crop_pgm.py`, or use 1024×1024; 16 | width).

- [ ] **Step 1: Build the strided feed + run.** Crop a 256×256 image (256/16=16-wide strips):
```
python tools/crop_pgm.py JPEG_ENC_8f.sim/images/world_gray_300x300.pgm JPEG_ENC_8f.sim/images/wide_256.pgm 256 256
python tools/make_strided_hex.py JPEG_ENC_8f.sim/images/wide_256.pgm JPEG_ENC_8f.sim/images/wide_256_strided.hex 16
```
Compile/elaborate/run `tb_jls_wide` (xvlog -prj tb_jls_wide_vlog.prj; xelab … xil_defaultlib.tb_jls_wide; xsim … run_quit.tcl), TB feed = `wide_256_strided.hex`, dims 256×256 → writes `output_h16v1_256x256.jls`.

- [ ] **Step 2: Verify lossless.**
```
python verify_lossless.py JPEG_ENC_8f.sim/output_block/output_h16v1_256x256.jls JPEG_ENC_8f.sim/images/wide_256.pgm 16 1
```
Expected: `LOSSLESS: exact match (256x256)`. If it fails, the most likely culprits are the A3 splitter intra-strip counting or the A6 strided layout (slot k must = strip k's pixel) — diff against a single-lane encode of strip 0 (`N_H=1` on a 16-wide image).

- [ ] **Step 3: Commit** the gate result (CSV/log). 
```bash
git add JPEG_ENC_8f.sim/output_block/hv_benchmark_results.csv
git commit -m "test(wide): 16-lane wide datapath bit-exact lossless (256x256, 16 strips)"
```

---

# PART B — Wide harness + timing-closed bitstream

Gate: `impl_1 → write_bitstream`, **WNS ≥ 0** at ~32 MHz, ~512 Mpix/s.

## Task B1: Wide on-chip AXIS ROM source (128-bit, column-strided)

**Files:** Rewrite `JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v`; new strided ROM hex.

- [ ] **Step 1: Generate a 128-bit-wide strided ROM** for a 256×256 demo image:
```
python tools/make_strided_hex.py JPEG_ENC_8f.sim/images/wide_256.pgm JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex 16
```
(4096 lines, each a 32-hex-digit 128-bit word.)

- [ ] **Step 2: Rewrite `axis_image_source.v`** to a 128-bit source over `N=stripW*H` words:
```verilog
`timescale 1ns/1ps
module axis_image_source #(
    parameter integer N_E   = 16,
    parameter integer IMG_W = 256,
    parameter integer IMG_H = 256,
    parameter         HEXFILE = "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex"
)(
    input  wire              clk,
    input  wire              rstn,
    output reg  [15:0]       i_w,
    output reg  [13:0]       i_h,
    output reg               i_sof,
    output wire [N_E*8-1:0]  s_axis_tdata,
    output wire              s_axis_tvalid,
    input  wire              s_axis_tready,
    output wire              s_axis_tlast
);
    localparam integer SW = IMG_W / N_E;          // strip width
    localparam integer N  = SW * IMG_H;           // strided words
    (* rom_style = "block" *) reg [N_E*8-1:0] rom [0:N-1];
    initial $readmemh(HEXFILE, rom);
    localparam S_IDLE=2'd0, S_RUN=2'd1, S_DONE=2'd2;
    reg [1:0] state; reg [31:0] addr;
    assign s_axis_tdata  = rom[addr];
    assign s_axis_tvalid = (state == S_RUN);
    assign s_axis_tlast  = (state == S_RUN) && (addr == N-1);
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin state<=S_IDLE; addr<=0; i_sof<=0; i_w<=0; i_h<=0; end
        else begin
            i_sof <= 1'b0;
            case (state)
                S_IDLE: begin i_w<=IMG_W[15:0]; i_h<=IMG_H[13:0]; i_sof<=1'b1; addr<=0; state<=S_RUN; end
                S_RUN:  if (s_axis_tvalid && s_axis_tready) begin
                            if (addr==N-1) state<=S_DONE; else addr<=addr+1;
                        end
                S_DONE: ;
            endcase
        end
    end
endmodule
```
(Block-ROM is fine here — combinational `rom[addr]` of a 128-bit×4096 array; if Vivado prefers, it maps to BRAM. `i_w` = full width 256.)

- [ ] **Step 3: Compile-check + commit.**
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v" -log xvlog_src.log
```
```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v" "JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex"
git commit -m "feat(wide-harness): 128-bit column-strided on-chip ROM source"
```

## Task B2: 16-lane sink + wide `jls_demo_top`

**Files:** Create `JPEG_ENC_8f.srcs/sources_1/new/axis_sink.v`; rewrite `jls_demo_top.v`.

- [ ] **Step 1: `axis_sink.v`** — drains all N_E lanes, counts bytes + rolling checksum, raises `done`:
```verilog
`timescale 1ns/1ps
module axis_sink #(parameter integer N_E = 16)(
    input  wire              clk,
    input  wire              rstn,
    input  wire [N_E*16-1:0] m_axis_tdata,
    input  wire [N_E-1:0]    m_axis_tvalid,
    output wire [N_E-1:0]    m_axis_tready,
    input  wire [N_E-1:0]    m_axis_tlast,
    output reg  [31:0]       total_words,
    output reg  [31:0]       checksum,
    output reg               done
);
    assign m_axis_tready = {N_E{1'b1}};
    reg [N_E-1:0] lane_done;
    integer k;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin total_words<=0; checksum<=0; done<=0; lane_done<=0; end
        else begin
            for (k=0;k<N_E;k=k+1) begin
                if (m_axis_tvalid[k]) begin
                    total_words <= total_words + 1'b1;
                    checksum    <= checksum ^ {16'd0, m_axis_tdata[k*16 +:16]};
                    if (m_axis_tlast[k]) lane_done[k] <= 1'b1;
                end
            end
            done <= &lane_done;
        end
    end
endmodule
```

- [ ] **Step 2: Rewrite `jls_demo_top.v`** for 16 lanes + sink + status:
```verilog
`timescale 1ns/1ps
module jls_demo_top #(
    parameter integer N_E   = 16,
    parameter integer N_H   = 16,
    parameter integer N_V   = 1,
    parameter integer IMG_W = 256,
    parameter integer IMG_H = 256
)(
    input  wire        rstn,
    input  wire        clk_in1_p,
    input  wire        clk_in1_n,
    output wire        clk,
    output wire        done,
    output wire [30:0] status     // checksum[30:0] (observable; prevents pruning)
);
    wire        sys_rdy;
    wire [15:0] src_w;  wire [13:0] src_h;  wire src_sof;
    wire [N_E*8-1:0]  src_tdata;  wire src_tvalid, src_tready, src_tlast;
    wire [N_E*16-1:0] m_tdata;    wire [N_E-1:0] m_tvalid, m_tready, m_tlast;
    wire [31:0] total_words, checksum;

    axis_image_source #(.N_E(N_E), .IMG_W(IMG_W), .IMG_H(IMG_H)) u_src (
        .clk(clk), .rstn(sys_rdy), .i_w(src_w), .i_h(src_h), .i_sof(src_sof),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast));

    jls_encoder_axis #(.N_E(N_E), .N_H(N_H), .N_V(N_V)) u_ip (
        .rstn(rstn), .clk(clk), .clk_in1_p(clk_in1_p), .clk_in1_n(clk_in1_n),
        .sys_rdy(sys_rdy), .i_sof(src_sof), .i_w(src_w), .i_h(src_h),
        .s_axis_tdata(src_tdata), .s_axis_tvalid(src_tvalid),
        .s_axis_tready(src_tready), .s_axis_tlast(src_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .m_axis_tlast(m_tlast));

    axis_sink #(.N_E(N_E)) u_sink (
        .clk(clk), .rstn(sys_rdy), .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .total_words(total_words), .checksum(checksum), .done(done));

    assign status = checksum[30:0];
endmodule
```

- [ ] **Step 3: Compile-check + commit.**
```
xvlog --relax "../../../../JPEG_ENC_8f.srcs/sources_1/new/axis_sink.v" "../../../../JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v" -log xvlog_demo.log
```
```bash
git add "JPEG_ENC_8f.srcs/sources_1/new/axis_sink.v" "JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v"
git commit -m "feat(wide-harness): 16-lane axis_sink + jls_demo_top (status pins)"
```

## Task B3: Wide XDC

**Files:** Create `JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_demo_top_wide.xdc`

- [ ] **Step 1:** Reuse the clk/reset pins from `top_jls_vertical.xdc` (clk_in1_p=R3/clk_in1_n=P3 LVDS_25, rstn=R8 LVCMOS25 + its `set_false_path`), and map `done` + `status[30:0]` (32 ports) to the package pins the old XDC assigned to `o_e*`/`o_data*`/`o_last*` (any 32 valid free LVCMOS25 output pins — reuse the o_data0/o_data1 pin list = 32 pins for status, plus one for done). Add `create_clock -name sys_clk_pin -period 5.000 [get_ports clk_in1_p]`. No input-pixel port constraints.

- [ ] **Step 2: Commit.**
```bash
git add "JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_demo_top_wide.xdc"
git commit -m "feat(wide-harness): XDC for 16-lane jls_demo_top (status pins)"
```

## Task B4: Synthesis (16 lanes, ~32 MHz)

**Files:** Create `JPEG_ENC_8f.sim/sim_1/behav/xsim/build_wide_synth.tcl`

- [ ] **Step 1:** Write a synth TCL like the existing `build_synth.tcl` but: set clk_wiz `rd_clk`≈32 MHz / `wr_clk`≈32 MHz (VCO valid; e.g. MULT=8 DIVCLK=1 VCO=1600? — use REQUESTED 32/32 and let Vivado solve, with `config_ip_cache -disable_cache` + `synth_ip` as in `build_fmax2.tcl`); add the new sources (`axis_sink.v`, ensure wide `jls_demo_top.v`/`axis_image_source.v`/`rom_wide.hex` present, `jls_demo_top_wide.xdc` in constrs, disable old `jls_demo_top.xdc`); `set_property top jls_demo_top`; ensure `jls_encoder_axis` instantiates with N_E=16 (it's the default now); `reset_run synth_1; launch_runs synth_1; wait_on_run; report_utilization -file wide_synth_util.rpt; report_timing_summary -file wide_synth_timing.rpt; puts "WIDE_SYNTH_DONE"`.

- [ ] **Step 2: Run + inspect.**
```powershell
vivado -mode batch -source JPEG_ENC_8f.sim\sim_1\behav\xsim\build_wide_synth.tcl -log build_wide_synth.vlog -nojournal
```
Expected: `synth_design Complete!`; util BRAM ≈ 20%, LUT ≈ 36%. Commit reports + TCL + `.xpr`:
```bash
git add "JPEG_ENC_8f.sim/sim_1/behav/xsim/build_wide_synth.tcl" wide_synth_util.rpt wide_synth_timing.rpt JPEG_ENC_8f.xpr JPEG_ENC_8f.srcs/sources_1/ip/clk_wiz_0/clk_wiz_0.xci JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0
git commit -m "build(wide): synth_1 completes for 16-lane jls_demo_top"
```

## Task B5: Implementation → bitstream (timing-closed)

**Files:** reuse `build_impl.tcl` (it's top-agnostic).

- [ ] **Step 1: Run impl.**
```powershell
vivado -mode batch -source JPEG_ENC_8f.sim\sim_1\behav\xsim\build_impl.tcl -log build_wide_impl.vlog -nojournal
```
Expected: `write_bitstream Complete!`, **WNS ≥ 0**, `jls_demo_top.bit` produced. If WNS < 0 at 32 MHz: lower clk (e.g. 25 MHz) or raise lanes (20), re-run B4/B5.

- [ ] **Step 2: Commit reports.**
```bash
git add impl_util.rpt impl_timing.rpt
git commit -m "build(wide): timing-closed bitstream, 16 lanes ~32 MHz (~512 Mpix/s)"
```

## Task B6: Document

**Files:** Modify `JPEG_ENC_8f.sim/output_block/BENCHMARKS.md`, `CLAUDE.md`

- [ ] **Step 1:** Add a "Wide 16-lane ~512 MB/s" section: device, config (N_E=16, 128-bit input), util, achieved clock + WNS, throughput (16 × clk Mpix/s), and that lossless was verified by 16-strip reassembly. Update CLAUDE.md's throughput note (60 MB/s single-lane vs ~512 MB/s wide 16-lane). Commit:
```bash
git add "JPEG_ENC_8f.sim/output_block/BENCHMARKS.md" CLAUDE.md
git commit -m "docs: record wide 16-lane ~512 MB/s synthesizable result"
```

---

## Self-Review (against spec)

- 16 lanes, N_E=16/N_H=16/N_V=1 → A4, B2. ✓
- Wide 128-bit column-strided input + widened splitter → A2, A3, A6 (strided feed). ✓
- Line buffer parameterized (LB_DEPTH=1024, ≤16384 width) → A1. ✓
- Shallow FIFOs (input 512, output 2048) → A5. ✓
- Dual-clock retained, ~32 MHz → B4. ✓
- On-chip sink + status pins → B2, B3. ✓
- Lossless 16-strip reassembly gate → A7. ✓
- Synth + impl timing-closed bitstream → B4, B5. ✓
- encoder_wrapper unchanged (derives col_w) — confirmed; A1 only adds .LB_DEPTH. ✓

**Placeholders:** none — code complete for each module; the XDC pin list (B3) is a concrete copy-from-old-XDC instruction. **Names:** `axis_sink` ports match B2 instance; `s_axis_tdata[N_E*8-1:0]`, `gen_x[N_E*8-1:0]`, `pixel_out[N_E*8-1:0]` consistent A2↔A3↔A4; `jls_demo_top` status/done match B3 XDC.

## Risks
- **A3 splitter intra-strip counting** is the highest-risk change (like the AXIS drain) — the A7 lossless gate + single-strip cross-check guard it; expect possible iteration.
- **Shallow output FIFO (2048) overflow** under a compressed-word burst — the sink drains all lanes full-rate; the A7 gate would catch corruption.
- **Congestion lowers Fmax at 16 lanes** — 32 MHz has margin; fall back to 25 MHz / 20 lanes (B5 note).
- **clk_wiz reconfigure** needs the disable-cache + synth_ip dance (proven in `build_fmax2.tcl`).
