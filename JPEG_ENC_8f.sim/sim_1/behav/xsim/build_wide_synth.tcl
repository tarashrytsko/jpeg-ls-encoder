# build_wide_synth.tcl  —  run: vivado -mode batch -source build_wide_synth.tcl
# Synthesizes the wide 16-lane jls_demo_top. clk_wiz is already at 32/32 (1:1).
# Adds the wide harness sources, swaps the constraints to the wide XDC, and runs synth_1.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

# Drop dangling refs to renamed/deleted files (no-op if already gone).
foreach stale { top_jls_vertical.v image_generator.v jls_encoder2.v
                splitter_vertical.v splitter_horizontal.v top_jls_horizontal.v
                tb_top_jls_vertical.v } {
    catch { remove_files [get_files -quiet $stale] }
}

# Add a source by basename if not already present; pass spaced paths as a [list].
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

# Enable only the wide XDC; disable the older constraint files.
catch { set_property is_enabled false [get_files -quiet top_jls_vertical.xdc] }
catch { set_property is_enabled false [get_files -quiet jls_demo_top.xdc] }
catch { set_property is_enabled true  [get_files -quiet jls_demo_top_wide.xdc] }

set_property top jls_demo_top [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set pr [get_property PROGRESS [get_runs synth_1]]
puts "WIDE_SYNTH_PROGRESS: $pr  STATUS: [get_property STATUS [get_runs synth_1]]"
if {$pr ne "100%"} {
    puts "WIDE_SYNTH_FAILED"
} else {
    open_run synth_1
    report_utilization    -file $root/wide_synth_util.rpt
    report_timing_summary -file $root/wide_synth_timing.rpt
    puts "WIDE_SYNTH_DONE"
}
