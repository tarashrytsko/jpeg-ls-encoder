run -all
open_saif act.saif
log_saif [get_objects -r /tb_saif/dut/*]
run -all
close_saif
quit
