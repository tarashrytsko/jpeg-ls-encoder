# build_synth.tcl  —  run: vivado -mode batch -source build_synth.tcl
# Refreshes the project source set for the AXIS refactor, sets jls_demo_top as the
# synthesis top, and runs synth_1, writing utilization + timing reports.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

# Drop dangling references to renamed/deleted files (catch = no-op if already absent).
# Match by basename so the spaced "FPGA Encoders" path is not an issue.
foreach stale {
    top_jls_vertical.v image_generator.v jls_encoder2.v
    splitter_vertical.v splitter_horizontal.v top_jls_horizontal.v
    tb_top_jls_vertical.v
} {
    catch { remove_files [get_files -quiet $stale] }
}

# Add a source if its basename is not already in the project. Paths may contain a
# space ("FPGA Encoders"), so pass them to add_files as a single-element [list].
proc add_if_absent {fileset path} {
    set bn [file tail $path]
    if {[llength [get_files -quiet $bn]] == 0} {
        if {$fileset eq ""} {
            add_files -norecurse [list $path]
        } else {
            add_files -fileset $fileset -norecurse [list $path]
        }
    }
}
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder_axis.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/axis_pixel_in.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/axis_image_source.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/jls_demo_top.v"
add_if_absent "" "$root/JPEG_ENC_8f.srcs/sources_1/new/rom_image.hex"
add_if_absent "constrs_1" "$root/JPEG_ENC_8f.srcs/constrs_1/imports/new/jls_demo_top.xdc"

# Retire the old (wrong-direction) constraints file.
catch { set_property is_enabled false [get_files -quiet top_jls_vertical.xdc] }

set_property top jls_demo_top [get_filesets sources_1]
update_compile_order -fileset sources_1

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

set st [get_property STATUS   [get_runs synth_1]]
set pr [get_property PROGRESS [get_runs synth_1]]
puts "SYNTH_STATUS: $st  PROGRESS: $pr"
if {$pr ne "100%"} {
    puts "SYNTH_FAILED"
} else {
    open_run synth_1
    report_utilization     -file $root/synth_util.rpt
    report_timing_summary  -file $root/synth_timing.rpt
    puts "SYNTH_DONE"
}
