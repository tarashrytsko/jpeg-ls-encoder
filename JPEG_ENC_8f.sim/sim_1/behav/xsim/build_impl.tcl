# build_impl.tcl  —  run: vivado -mode batch -source build_impl.tcl
# Runs implementation through write_bitstream for jls_demo_top and reports timing.
# Assumes synth_1 is already complete (build_synth.tcl).
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set st [get_property STATUS   [get_runs impl_1]]
set pr [get_property PROGRESS [get_runs impl_1]]
puts "IMPL_STATUS: $st  PROGRESS: $pr"
if {$pr ne "100%"} {
    puts "IMPL_FAILED"
} else {
    open_run impl_1
    report_utilization    -file $root/impl_util.rpt
    report_timing_summary -file $root/impl_timing.rpt
    set wns [get_property STATS.WNS [get_runs impl_1]]
    set whs [get_property STATS.WHS [get_runs impl_1]]
    puts "IMPL_DONE WNS=$wns WHS=$whs"
}
