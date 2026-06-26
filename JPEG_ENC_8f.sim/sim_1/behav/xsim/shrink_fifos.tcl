# shrink_fifos.tcl  —  run: vivado -mode batch -source shrink_fifos.tcl
# Shrinks the per-lane FIFOs so 16 lanes fit in BRAM:
#   fifo_generator_0 (input, 8-bit):  131072 -> 512
#   fifo_output      (output, 16-bit): 65536 -> 2048
# The deep FIFOs only buffered the old serial 1-px/cycle feed; with the wide
# synchronous feed + full-rate sink, shallow suffices.
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
open_project $root/JPEG_ENC_8f.xpr

config_ip_cache -disable_cache

set_property -dict [list CONFIG.Input_Depth {512}]  [get_ips fifo_generator_0]
set_property -dict [list CONFIG.Input_Depth {2048}] [get_ips fifo_output]

generate_target all [get_ips fifo_generator_0]
generate_target all [get_ips fifo_output]
catch { reset_run fifo_generator_0_synth_1 }
catch { reset_run fifo_output_synth_1 }
catch { synth_ip [get_ips fifo_generator_0] }
catch { synth_ip [get_ips fifo_output] }

puts "FIFOS_SHRUNK in_depth=[get_property CONFIG.Input_Depth [get_ips fifo_generator_0]] out_depth=[get_property CONFIG.Input_Depth [get_ips fifo_output]]"
