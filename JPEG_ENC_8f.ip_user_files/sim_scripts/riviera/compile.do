transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

vlib work
vlib riviera/xpm
vlib riviera/fifo_generator_v13_2_11
vlib riviera/xil_defaultlib
vlib riviera/blk_mem_gen_v8_4_9

vmap xpm riviera/xpm
vmap fifo_generator_v13_2_11 riviera/fifo_generator_v13_2_11
vmap xil_defaultlib riviera/xil_defaultlib
vmap blk_mem_gen_v8_4_9 riviera/blk_mem_gen_v8_4_9

vlog -work xpm  -incr "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" -l xpm -l fifo_generator_v13_2_11 -l xil_defaultlib -l blk_mem_gen_v8_4_9 \
"C:/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -93  -incr \
"C:/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work fifo_generator_v13_2_11  -incr -v2k5 "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" -l xpm -l fifo_generator_v13_2_11 -l xil_defaultlib -l blk_mem_gen_v8_4_9 \
"../../ipstatic/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_11 -93  -incr \
"../../ipstatic/hdl/fifo_generator_v13_2_rfs.vhd" \

vlog -work fifo_generator_v13_2_11  -incr -v2k5 "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" -l xpm -l fifo_generator_v13_2_11 -l xil_defaultlib -l blk_mem_gen_v8_4_9 \
"../../ipstatic/hdl/fifo_generator_v13_2_rfs.v" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" -l xpm -l fifo_generator_v13_2_11 -l xil_defaultlib -l blk_mem_gen_v8_4_9 \
"../../../JPEG_ENC_8f.gen/sources_1/ip/fifo_output/sim/fifo_output.v" \
"../../../JPEG_ENC_8f.gen/sources_1/ip/fifo_generator_0/sim/fifo_generator_0.v" \

vlog -work blk_mem_gen_v8_4_9  -incr -v2k5 "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" -l xpm -l fifo_generator_v13_2_11 -l xil_defaultlib -l blk_mem_gen_v8_4_9 \
"../../ipstatic/simulation/blk_mem_gen_v8_4.v" \

vlog -work xil_defaultlib  -incr -v2k5 "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" -l xpm -l fifo_generator_v13_2_11 -l xil_defaultlib -l blk_mem_gen_v8_4_9 \
"../../../JPEG_ENC_8f.gen/sources_1/ip/blk_mem_gen_0_1/sim/blk_mem_gen_0.v" \
"../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0/clk_wiz_0_clk_wiz.v" \
"../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0/clk_wiz_0.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/block_split.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/encoder_wrapper.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/fifo_read_control.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/fifo_reset_bram_async.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/fifo_wrapper_input.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/fifo_wrapper_output.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/fifo_write_control.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/new/image_generator.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/jls_encoder.v" \
"../../../JPEG_ENC_8f.srcs/sources_1/imports/FPGA Encoders/top_jls_vertical.v" \
"../../../JPEG_ENC_8f.srcs/sim_1/imports/FPGA Encoders/tb_top_jls_vertical.v" \

vlog -work xil_defaultlib \
"glbl.v"

