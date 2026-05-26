@echo off
cd /d "D:\techbistro\upwork\JPEG_Encoder_Project\JPEG_ENC_8f\JPEG_ENC_8f.sim\sim_1\behav\xsim"
set PATH=C:\Xilinx\Vivado\2024.2\bin;%PATH%

echo === CWD: %CD% ===
echo === Compile ===
xvlog --incr --relax -prj tb_top_jls_vertical_vlog.prj -log xvlog.log
if errorlevel 1 (
    echo COMPILE FAILED
    exit /b 1
)
echo COMPILE OK

echo === Elaborate ===
xelab --debug typical --relax --mt 2 -L xil_defaultlib -L fifo_generator_v13_2_11 -L unisims_ver -L unimacro_ver -L secureip -L xpm --snapshot tb_top_jls_vertical_behav xil_defaultlib.tb_top_jls_vertical xil_defaultlib.glbl -log elaborate.log
if errorlevel 1 (
    echo ELABORATE FAILED
    exit /b 1
)
echo ELABORATE OK

echo === Simulate ===
xsim tb_top_jls_vertical_behav -tclbatch tb_top_jls_vertical.tcl -log simulate.log
if errorlevel 1 (
    echo SIMULATE FAILED
    exit /b 1
)
echo SIMULATE OK
