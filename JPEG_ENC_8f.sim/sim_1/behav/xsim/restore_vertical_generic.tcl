# restore_vertical_generic.tcl  —  run:
#   vivado -mode batch -source restore_vertical_generic.tcl
# T7 cleanup: the per-mode builds left a (N_H=4,N_V=1?/N_V=4) generic override on
# the sources_1 fileset in the .xpr. Reset it to the vertical default (N_H=16, N_V=1)
# so the plain build (build_wide_synth.tcl, which sets no generic) synthesizes the
# vertical column-strip configuration again. rom_wide.hex was already restored to the
# vertical ROM via git.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr
set_property generic "N_H=16 N_V=1" [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "RESTORE_GENERIC: [get_property generic [get_filesets sources_1]]"
close_project
puts "RESTORE_VERTICAL_DONE"
