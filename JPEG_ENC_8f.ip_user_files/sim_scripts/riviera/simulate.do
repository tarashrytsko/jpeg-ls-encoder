transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+tb_top_jls_vertical  -L xil_defaultlib -L xpm -L fifo_generator_v13_2_11 -L blk_mem_gen_v8_4_9 -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.tb_top_jls_vertical xil_defaultlib.glbl

do {tb_top_jls_vertical.udo}

run 1000ns

endsim

quit -force
