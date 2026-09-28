#!/usr/bin/env bash
# tools/saif_power.sh <tag>   (tag = n12_45 | n16_32 | b12_45 | b16_45)
# Activity-annotated power for a routed mission build (reviewer Req 5):
#   1. simulate eval/power/<tag>_funcsim.v (post-route functional netlist) with tb_saif,
#      logging a SAIF over the streaming window [first source beat, done];
#   2. re-open eval/power/<tag>_routed.dcp, read the SAIF, report_power (typical, 25 C)
#      -> eval/power/<tag>_power_saif.rpt (+ _hier), and print the net match rate.
set -e
tag=$1
ROOT="D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
B="C:/Xilinx/Vivado/2024.2/bin"
W="$ROOT/eval/power/saif/$tag"
mkdir -p "$W"; cd "$W"
cp ../xsim.ini ../glbl.v ../tb_saif.v ../run_saif.tcl .
"$B/xvlog.bat" --relax "$ROOT/eval/power/${tag}_funcsim.v" tb_saif.v glbl.v > xvlog.log 2>&1
"$B/xelab.bat" --debug typical --relax --mt 4 -L unisims_ver -L unimacro_ver -L secureip \
    --snapshot saif_$tag work.tb_saif work.glbl > xelab.log 2>&1
"$B/xsim.bat" saif_$tag -tclbatch run_saif.tcl > xsim.log 2>&1
grep -E "SAIF_(START|END|TIMEOUT)" xsim.log
cat > rpt.tcl <<EOF
open_checkpoint $ROOT/eval/power/${tag}_routed.dcp
set_operating_conditions -process typical -ambient_temp 25
read_saif -strip_path tb_saif/dut $W/act.saif
report_power -file $ROOT/eval/power/${tag}_power_saif.rpt
report_power -hierarchical_depth 4 -file $ROOT/eval/power/${tag}_power_saif_hier.rpt
set_operating_conditions -process maximum -ambient_temp 70
report_power -file $ROOT/eval/power/${tag}_power_saif_wc.rpt
EOF
"$B/vivado.bat" -mode batch -nojournal -nolog -source rpt.tcl > vivado_rpt.log 2>&1
grep -E "Total On-Chip|Dynamic \(W\)|Design Nets Matched" "$ROOT/eval/power/${tag}_power_saif.rpt"
