# build_wide_mode.tcl  —  run:
#   vivado -mode batch -source build_wide_mode.tcl -tclargs <N_H> <N_V>
# Builds a timing-closed jls_demo_top bitstream for one wide split mode.
# Copies the mode ROM (rom_wide_h<NH>v<NV>.hex) into the synthesized rom_wide.hex,
# overrides the (N_H,N_V) generic on jls_demo_top, then runs synth_1 + impl_1
# through write_bitstream. Reports mode-tagged util/timing and prints MODE_DONE.
# clk_wiz is assumed already at 32/32 (1:1) — clkwiz_3232.tcl. N_E stays 16.

if {$argc < 2} { puts "USAGE: -tclargs <N_H> <N_V>"; exit 1 }
set NH [lindex $argv 0]
set NV [lindex $argv 1]
set tag "h${NH}v${NV}"

set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

# --- 1. Swap in the mode ROM (the synthesized source axis_image_source reads) ---
set moderom "$root/JPEG_ENC_8f.sim/images/rom_wide_${tag}.hex"
set synthrom "$root/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex"
if {![file exists $moderom]} { puts "MODE_ROM_MISSING: $moderom"; exit 1 }
file copy -force $moderom $synthrom
puts "MODE_ROM_COPIED: $moderom -> rom_wide.hex"

# --- 2. Ensure the wide harness sources + XDC are in the project (idempotent) ---
foreach stale { top_jls_vertical.v image_generator.v jls_encoder2.v
                splitter_vertical.v splitter_horizontal.v top_jls_horizontal.v
                tb_top_jls_vertical.v } {
    catch { remove_files [get_files -quiet $stale] }
}
proc add_if_absent {fileset path} {
    set bn [file tail $path]
    if {[llength [get_files -quiet $bn]] == 0} {
        if {$fileset eq ""} { add_files -norecurse [list $path] } \
        else { add_files -fileset $fileset -norecurse [list $path] }
    }
}
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/axis_sink.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex"
add_if_absent "constrs_1" "$root/JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_demo_top_wide.xdc"
catch { set_property is_enabled false [get_files -quiet top_jls_vertical.xdc] }
catch { set_property is_enabled false [get_files -quiet jls_demo_top.xdc] }
catch { set_property is_enabled true  [get_files -quiet jls_demo_top_wide.xdc] }

# --- 3. Set top + (N_H,N_V) generic (full string so stale values don't linger) ---
set_property top jls_demo_top [get_filesets sources_1]
set_property generic "N_H=$NH N_V=$NV" [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "MODE_GENERIC_SET: N_H=$NH N_V=$NV"

# --- 4. Synthesis ---
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
set spr [get_property PROGRESS [get_runs synth_1]]
puts "MODE_SYNTH_PROGRESS: $spr  STATUS: [get_property STATUS [get_runs synth_1]]"
if {$spr ne "100%"} { puts "MODE_SYNTH_FAILED $tag"; exit 1 }

# --- 5. Implementation -> bitstream ---
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
set ipr [get_property PROGRESS [get_runs impl_1]]
puts "MODE_IMPL_PROGRESS: $ipr  STATUS: [get_property STATUS [get_runs impl_1]]"
if {$ipr ne "100%"} { puts "MODE_IMPL_FAILED $tag"; exit 1 }

open_run impl_1
report_utilization    -file $root/mode_${tag}_util.rpt
report_timing_summary -file $root/mode_${tag}_timing.rpt
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "MODE_DONE $tag WNS=$wns WHS=$whs"
