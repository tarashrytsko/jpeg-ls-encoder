vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xpm
vlib modelsim_lib/msim/fifo_generator_v13_2_11
vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/blk_mem_gen_v8_4_9

vmap xpm modelsim_lib/msim/xpm
vmap fifo_generator_v13_2_11 modelsim_lib/msim/fifo_generator_v13_2_11
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap blk_mem_gen_v8_4_9 modelsim_lib/msim/blk_mem_gen_v8_4_9

vlog -work xpm  -incr -mfcu  -sv "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" \
"C:/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"C:/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93  \
"C:/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work fifo_generator_v13_2_11  -incr -mfcu  "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" \
"../../ipstatic/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_11  -93  \
"../../ipstatic/hdl/fifo_generator_v13_2_rfs.vhd" \

vlog -work fifo_generator_v13_2_11  -incr -mfcu  "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" \
"../../ipstatic/hdl/fifo_generator_v13_2_rfs.v" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" \
"../../../JPEG_ENC_8f.gen/sources_1/ip/fifo_output/sim/fifo_output.v" \
"../../../JPEG_ENC_8f.gen/sources_1/ip/fifo_generator_0/sim/fifo_generator_0.v" \

vlog -work blk_mem_gen_v8_4_9  -incr -mfcu  "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" \
"../../ipstatic/simulation/blk_mem_gen_v8_4.v" \

vlog -work xil_defaultlib  -incr -mfcu  "+incdir+../../../JPEG_ENC_8f.gen/sources_1/ip/clk_wiz_0" \
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

