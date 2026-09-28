# build_power_seu.tcl  —  run:
#   vivado -mode batch -source build_power_seu.tcl -tclargs <tag> <N_E> <N_H> <N_V> <W> <H> <MHz> <MULT> <DIV> <romhex> [BPP]
# Mission-configuration power + SEU data (reviewer Req 5 / Req 8).
# Builds jls_demo_top at the requested lane count / clock (1:1, MMCM VCO = 200*MULT),
# then from the ROUTED design writes:
#   eval/power/<tag>_power_vectorless_typ.rpt   (default activity, typical, 25 C)
#   eval/power/<tag>_power_vectorless_wc.rpt    (default activity, process max, 70 C ambient)
#   eval/power/<tag>_power_hier.rpt             (per-module hierarchy, typical)
#   eval/power/<tag>_util_hier.rpt, <tag>_timing.rpt
#   eval/power/<tag>_routed.dcp                 (kept so SAIF can be re-applied later)
#   eval/power/<tag>_funcsim.v                  (post-route functional netlist for SAIF sim)
#   eval/seu/<tag>.ebd                          (essential-bits map -> SEU-sensitive CRAM bits)
if {$argc < 10} { puts "USAGE: <tag> <N_E> <N_H> <N_V> <W> <H> <MHz> <MULT> <DIV> <romhex>"; exit 1 }
lassign $argv tag NE NH NV W H MHZ MULT DIV romhex BPP
if {$BPP eq ""} { set BPP 8 }

set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
set pdir "$root/eval/power"
set sdir "$root/eval/seu"
file mkdir $pdir
file mkdir $sdir
open_project $root/JPEG_ENC_8f.xpr

# --- clock (1:1) ---
config_ip_cache -disable_cache
set_property -dict [list \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $MHZ \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $MHZ \
    CONFIG.MMCM_DIVCLK_DIVIDE {1} \
    CONFIG.MMCM_CLKFBOUT_MULT_F $MULT \
    CONFIG.MMCM_CLKOUT0_DIVIDE_F $DIV \
    CONFIG.MMCM_CLKOUT1_DIVIDE [expr {int($DIV)}] ] [get_ips clk_wiz_0]
reset_target -quiet all [get_ips clk_wiz_0]
generate_target all [get_ips clk_wiz_0]
catch { reset_run clk_wiz_0_synth_1 }
catch { synth_ip [get_ips clk_wiz_0] }
puts "PWR_CLK_SET out1=[get_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ [get_ips clk_wiz_0]]"

# --- ROM + generics + constraints ---
file copy -force $root/JPEG_ENC_8f.sim/images/$romhex $root/JPEG_ENC_8f.srcs/sources_1/new/rom_wide.hex
catch { set_property is_enabled false [get_files -quiet top_jls_vertical.xdc] }
catch { set_property is_enabled false [get_files -quiet jls_demo_top.xdc] }
catch { set_property is_enabled false [get_files -quiet jls_serial_demo_top.xdc] }
catch { set_property is_enabled true  [get_files -quiet jls_demo_top_wide.xdc] }
set_property top jls_demo_top [get_filesets sources_1]
set_property generic "N_E=$NE N_H=$NH N_V=$NV IMG_W=$W IMG_H=$H BPP=$BPP" [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "PWR_GENERIC_SET: [get_property generic [get_filesets sources_1]]"

reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { puts "PWR_SYNTH_FAILED"; exit 1 }
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { puts "PWR_IMPL_FAILED"; exit 1 }

open_run impl_1
write_checkpoint -force $pdir/${tag}_routed.dcp
report_timing_summary -file $pdir/${tag}_timing.rpt
report_utilization -file $pdir/${tag}_util.rpt
report_utilization -hierarchical -hierarchical_depth 4 -file $pdir/${tag}_util_hier.rpt

# Vectorless, typical corner, 25 C ambient (Vivado default activity: 12.5 % toggle, SP 0.5)
set_operating_conditions -process typical -ambient_temp 25
report_power -file $pdir/${tag}_power_vectorless_typ.rpt
report_power -hierarchical_depth 4 -file $pdir/${tag}_power_hier.rpt
# Worst-case static: maximum process corner, 70 C ambient
set_operating_conditions -process maximum -ambient_temp 70
report_power -file $pdir/${tag}_power_vectorless_wc.rpt
set_operating_conditions -process typical -ambient_temp 25

# Post-route functional netlist for the SAIF (activity-annotated) power run
write_verilog -force -mode funcsim $pdir/${tag}_funcsim.v

# SEU: essential-bits map
set_property BITSTREAM.SEU.ESSENTIALBITS YES [current_design]
write_bitstream -force $sdir/${tag}.bit
puts "PWR_SEU_DONE $tag WNS=[get_property STATS.WNS [get_runs impl_1]] WHS=[get_property STATS.WHS [get_runs impl_1]]"
