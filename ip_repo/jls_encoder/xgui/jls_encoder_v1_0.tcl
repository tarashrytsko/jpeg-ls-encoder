# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "L" -parent ${Page_0}
  ipgui::add_param $IPINST -name "LB_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NEAR" -parent ${Page_0}
  ipgui::add_param $IPINST -name "N_E" -parent ${Page_0}


}

proc update_PARAM_VALUE.L { PARAM_VALUE.L } {
	# Procedure called to update L when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.L { PARAM_VALUE.L } {
	# Procedure called to validate L
	return true
}

proc update_PARAM_VALUE.LB_DEPTH { PARAM_VALUE.LB_DEPTH } {
	# Procedure called to update LB_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.LB_DEPTH { PARAM_VALUE.LB_DEPTH } {
	# Procedure called to validate LB_DEPTH
	return true
}

proc update_PARAM_VALUE.NEAR { PARAM_VALUE.NEAR } {
	# Procedure called to update NEAR when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NEAR { PARAM_VALUE.NEAR } {
	# Procedure called to validate NEAR
	return true
}

proc update_PARAM_VALUE.N_E { PARAM_VALUE.N_E } {
	# Procedure called to update N_E when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.N_E { PARAM_VALUE.N_E } {
	# Procedure called to validate N_E
	return true
}


proc update_MODELPARAM_VALUE.NEAR { MODELPARAM_VALUE.NEAR PARAM_VALUE.NEAR } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NEAR}] ${MODELPARAM_VALUE.NEAR}
}

proc update_MODELPARAM_VALUE.N_E { MODELPARAM_VALUE.N_E PARAM_VALUE.N_E } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.N_E}] ${MODELPARAM_VALUE.N_E}
}

proc update_MODELPARAM_VALUE.L { MODELPARAM_VALUE.L PARAM_VALUE.L } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.L}] ${MODELPARAM_VALUE.L}
}

proc update_MODELPARAM_VALUE.LB_DEPTH { MODELPARAM_VALUE.LB_DEPTH PARAM_VALUE.LB_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.LB_DEPTH}] ${MODELPARAM_VALUE.LB_DEPTH}
}

