# ooc_iserdes.tcl — out-of-context synth of iserdes_byte_in to validate the ISERDESE2
# instantiation and confirm it maps (12 ISERDES) on the given part. run:
#   vivado -mode batch -source ooc_iserdes.tcl -tclargs <part>
set part [expr {$argc > 0 ? [lindex $argv 0] : "xc7a200tfbg676-2"}]
set root "D:/techbistro/upwork/JPEG_Encoder_Project/JPEG_ENC_8f"
set_param general.maxThreads 1
puts "ISERDES_OOC_PART=$part"
read_verilog "$root/JPEG_ENC_8f.srcs/sources_1/new/iserdes_byte_in.v"
synth_design -top iserdes_byte_in -part $part -mode out_of_context
report_utilization -file $root/iserdes_ooc_util.rpt
set nis [llength [get_cells -hier -filter {REF_NAME == ISERDESE2 || PRIMITIVE_TYPE =~ *ISERDES*}]]
puts "ISERDES_OOC_DONE  ISERDESE2_count=$nis"
