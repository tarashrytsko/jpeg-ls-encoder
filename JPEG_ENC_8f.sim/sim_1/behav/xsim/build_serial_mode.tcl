# build_serial_mode.tcl  —  vivado -mode batch -source build_serial_mode.tcl \
#                              -tclargs <N_H> <N_V> [LB_DEPTH] [IMG_W] [IMG_H]
# Full P&R of jls_serial_demo_top in a chosen split direction (N_H*N_V=12):
#   vertical 12 1  |  horizontal 1 12  |  block 4 3
# Optional LB_DEPTH/IMG_W/IMG_H (default 1024/300/300) size the line buffers + dims —
# horizontal (N_H=1) at width W needs LB_DEPTH >= W (e.g. `1 12 4096 3000 3000`).
# Produces jls_serial_demo_top_h<N_H>v<N_V>_<W>x<H>.bit; restores the canonical config after.
set NH [lindex $argv 0]
set NV [lindex $argv 1]
if {$NH eq "" || $NV eq ""} { puts "usage: -tclargs <N_H> <N_V> \[LB_DEPTH\] \[IMG_W\] \[IMG_H\]"; exit 1 }
set LB [lindex $argv 2]; if {$LB eq ""} { set LB 1024 }
set W  [lindex $argv 3]; if {$W  eq ""} { set W 300 }
set H  [lindex $argv 4]; if {$H  eq ""} { set H 300 }
set tag "h${NH}v${NV}_${W}x${H}"
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr
set_param general.maxThreads 1

proc add_if_absent {fs path} {
    if {[llength [get_files -quiet [file tail $path]]] == 0} {
        if {$fs eq ""} { add_files -norecurse [list $path] } \
        else { add_files -fileset $fs -norecurse [list $path] }
    }
}
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/iserdes_byte_in.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/byte_gearbox_12.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/axis_sink.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/jls_serial_demo_top.v"
add_if_absent "constrs_1" "$root/JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_serial_demo_top.xdc"

catch { set_property is_enabled false [get_files -quiet jls_demo_top_wide.xdc] }
catch { set_property is_enabled false [get_files -quiet jls_demo_top.xdc] }
catch { set_property is_enabled false [get_files -quiet top_jls_vertical.xdc] }
set_property is_enabled true [get_files -quiet jls_serial_demo_top.xdc]

set_property top jls_serial_demo_top [get_filesets sources_1]
set_property generic "N_H=$NH N_V=$NV LB_DEPTH=$LB IMG_W=$W IMG_H=$H" [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "SERIALMODE_SYNTH_FAILED $tag"; exit 1 }

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "SERIALMODE_IMPL_FAILED $tag"; exit 1 }

open_run impl_1
report_utilization    -file $root/serialmode_${tag}_util.rpt
report_timing_summary -file $root/serialmode_${tag}_timing.rpt
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "SERIALMODE_IMPL $tag WNS=$wns WHS=$whs"

catch { set_property SEVERITY {Warning} [get_drc_checks UCIO-1] }
catch { set_property SEVERITY {Warning} [get_drc_checks NSTD-1] }
write_bitstream -force $root/jls_serial_demo_top_${tag}.bit
puts "SERIALMODE_BITSTREAM_DONE $tag"

# ---- restore canonical 12-lane @ 45 jls_demo_top config ----
set_property is_enabled false [get_files -quiet jls_serial_demo_top.xdc]
catch { set_property is_enabled true [get_files -quiet jls_demo_top_wide.xdc] }
set_property top jls_demo_top [get_filesets sources_1]
set_property generic "N_E=12 N_H=12 N_V=1 IMG_W=300 IMG_H=300" [get_filesets sources_1]
update_compile_order -fileset sources_1
close_project
puts "SERIALMODE_RESTORED_CANONICAL $tag"
