# build_serial_demo.tcl  —  vivado -mode batch -source build_serial_demo.tcl
# Full P&R of jls_serial_demo_top (ISERDES serial-in -> CDC -> 12-lane encoder) to a
# bitstream on xc7a200tfbg676-2. clk_wiz_0 (encoder MMCM) stays at 45 MHz; the top's own
# MMCME2_BASE makes 360/45 for the ISERDES. ser_d[11:0] auto-placed (UCIO downgraded).
# Restores the canonical jls_demo_top / 12-lane config at the end.
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
set_property generic "" [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "SERIAL_SYNTH_FAILED"; exit 1 }

reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "SERIAL_IMPL_FAILED"; exit 1 }

open_run impl_1
report_utilization    -file $root/serialdemo_util.rpt
report_timing_summary -file $root/serialdemo_timing.rpt
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "SERIALDEMO_IMPL WNS=$wns WHS=$whs"

# unconstrained ser_d are auto-placed for this demo -> downgrade the blocking DRCs
catch { set_property SEVERITY {Warning} [get_drc_checks UCIO-1] }
catch { set_property SEVERITY {Warning} [get_drc_checks NSTD-1] }
write_bitstream -force $root/jls_serial_demo_top.bit
puts "SERIALDEMO_BITSTREAM_DONE"

# ---- restore canonical 12-lane @ 45 jls_demo_top config ----
set_property is_enabled false [get_files -quiet jls_serial_demo_top.xdc]
catch { set_property is_enabled true [get_files -quiet jls_demo_top_wide.xdc] }
set_property top jls_demo_top [get_filesets sources_1]
set_property generic "N_E=12 N_H=12 N_V=1 IMG_W=300 IMG_H=300" [get_filesets sources_1]
update_compile_order -fileset sources_1
close_project
puts "SERIALDEMO_RESTORED_CANONICAL"
