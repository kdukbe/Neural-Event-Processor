# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "CHANNELS" -parent ${Page_0}
  ipgui::add_param $IPINST -name "EVENT_DRIVEN" -parent ${Page_0}
  ipgui::add_param $IPINST -name "IBUFFER_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ID_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "IFIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "OBUFFER_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "OFIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PENDING_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "POST_SAMPLES" -parent ${Page_0}
  ipgui::add_param $IPINST -name "REFRACTORY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "THRESHOLD" -parent ${Page_0}
  ipgui::add_param $IPINST -name "WFIFO_DEPTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "WINDOW_DEPTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.CHANNELS { PARAM_VALUE.CHANNELS } {
	# Procedure called to update CHANNELS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CHANNELS { PARAM_VALUE.CHANNELS } {
	# Procedure called to validate CHANNELS
	return true
}

proc update_PARAM_VALUE.EVENT_DRIVEN { PARAM_VALUE.EVENT_DRIVEN } {
	# Procedure called to update EVENT_DRIVEN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.EVENT_DRIVEN { PARAM_VALUE.EVENT_DRIVEN } {
	# Procedure called to validate EVENT_DRIVEN
	return true
}

proc update_PARAM_VALUE.IBUFFER_DEPTH { PARAM_VALUE.IBUFFER_DEPTH } {
	# Procedure called to update IBUFFER_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.IBUFFER_DEPTH { PARAM_VALUE.IBUFFER_DEPTH } {
	# Procedure called to validate IBUFFER_DEPTH
	return true
}

proc update_PARAM_VALUE.ID_WIDTH { PARAM_VALUE.ID_WIDTH } {
	# Procedure called to update ID_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ID_WIDTH { PARAM_VALUE.ID_WIDTH } {
	# Procedure called to validate ID_WIDTH
	return true
}

proc update_PARAM_VALUE.IFIFO_DEPTH { PARAM_VALUE.IFIFO_DEPTH } {
	# Procedure called to update IFIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.IFIFO_DEPTH { PARAM_VALUE.IFIFO_DEPTH } {
	# Procedure called to validate IFIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.OBUFFER_DEPTH { PARAM_VALUE.OBUFFER_DEPTH } {
	# Procedure called to update OBUFFER_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.OBUFFER_DEPTH { PARAM_VALUE.OBUFFER_DEPTH } {
	# Procedure called to validate OBUFFER_DEPTH
	return true
}

proc update_PARAM_VALUE.OFIFO_DEPTH { PARAM_VALUE.OFIFO_DEPTH } {
	# Procedure called to update OFIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.OFIFO_DEPTH { PARAM_VALUE.OFIFO_DEPTH } {
	# Procedure called to validate OFIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.PENDING_DEPTH { PARAM_VALUE.PENDING_DEPTH } {
	# Procedure called to update PENDING_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PENDING_DEPTH { PARAM_VALUE.PENDING_DEPTH } {
	# Procedure called to validate PENDING_DEPTH
	return true
}

proc update_PARAM_VALUE.POST_SAMPLES { PARAM_VALUE.POST_SAMPLES } {
	# Procedure called to update POST_SAMPLES when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.POST_SAMPLES { PARAM_VALUE.POST_SAMPLES } {
	# Procedure called to validate POST_SAMPLES
	return true
}

proc update_PARAM_VALUE.REFRACTORY { PARAM_VALUE.REFRACTORY } {
	# Procedure called to update REFRACTORY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.REFRACTORY { PARAM_VALUE.REFRACTORY } {
	# Procedure called to validate REFRACTORY
	return true
}

proc update_PARAM_VALUE.THRESHOLD { PARAM_VALUE.THRESHOLD } {
	# Procedure called to update THRESHOLD when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.THRESHOLD { PARAM_VALUE.THRESHOLD } {
	# Procedure called to validate THRESHOLD
	return true
}

proc update_PARAM_VALUE.WFIFO_DEPTH { PARAM_VALUE.WFIFO_DEPTH } {
	# Procedure called to update WFIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.WFIFO_DEPTH { PARAM_VALUE.WFIFO_DEPTH } {
	# Procedure called to validate WFIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.WINDOW_DEPTH { PARAM_VALUE.WINDOW_DEPTH } {
	# Procedure called to update WINDOW_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.WINDOW_DEPTH { PARAM_VALUE.WINDOW_DEPTH } {
	# Procedure called to validate WINDOW_DEPTH
	return true
}


proc update_MODELPARAM_VALUE.ID_WIDTH { MODELPARAM_VALUE.ID_WIDTH PARAM_VALUE.ID_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ID_WIDTH}] ${MODELPARAM_VALUE.ID_WIDTH}
}

proc update_MODELPARAM_VALUE.CHANNELS { MODELPARAM_VALUE.CHANNELS PARAM_VALUE.CHANNELS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CHANNELS}] ${MODELPARAM_VALUE.CHANNELS}
}

proc update_MODELPARAM_VALUE.IFIFO_DEPTH { MODELPARAM_VALUE.IFIFO_DEPTH PARAM_VALUE.IFIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.IFIFO_DEPTH}] ${MODELPARAM_VALUE.IFIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.WINDOW_DEPTH { MODELPARAM_VALUE.WINDOW_DEPTH PARAM_VALUE.WINDOW_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.WINDOW_DEPTH}] ${MODELPARAM_VALUE.WINDOW_DEPTH}
}

proc update_MODELPARAM_VALUE.OFIFO_DEPTH { MODELPARAM_VALUE.OFIFO_DEPTH PARAM_VALUE.OFIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.OFIFO_DEPTH}] ${MODELPARAM_VALUE.OFIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.WFIFO_DEPTH { MODELPARAM_VALUE.WFIFO_DEPTH PARAM_VALUE.WFIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.WFIFO_DEPTH}] ${MODELPARAM_VALUE.WFIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.PENDING_DEPTH { MODELPARAM_VALUE.PENDING_DEPTH PARAM_VALUE.PENDING_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PENDING_DEPTH}] ${MODELPARAM_VALUE.PENDING_DEPTH}
}

proc update_MODELPARAM_VALUE.IBUFFER_DEPTH { MODELPARAM_VALUE.IBUFFER_DEPTH PARAM_VALUE.IBUFFER_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.IBUFFER_DEPTH}] ${MODELPARAM_VALUE.IBUFFER_DEPTH}
}

proc update_MODELPARAM_VALUE.OBUFFER_DEPTH { MODELPARAM_VALUE.OBUFFER_DEPTH PARAM_VALUE.OBUFFER_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.OBUFFER_DEPTH}] ${MODELPARAM_VALUE.OBUFFER_DEPTH}
}

proc update_MODELPARAM_VALUE.THRESHOLD { MODELPARAM_VALUE.THRESHOLD PARAM_VALUE.THRESHOLD } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.THRESHOLD}] ${MODELPARAM_VALUE.THRESHOLD}
}

proc update_MODELPARAM_VALUE.REFRACTORY { MODELPARAM_VALUE.REFRACTORY PARAM_VALUE.REFRACTORY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.REFRACTORY}] ${MODELPARAM_VALUE.REFRACTORY}
}

proc update_MODELPARAM_VALUE.POST_SAMPLES { MODELPARAM_VALUE.POST_SAMPLES PARAM_VALUE.POST_SAMPLES } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.POST_SAMPLES}] ${MODELPARAM_VALUE.POST_SAMPLES}
}

proc update_MODELPARAM_VALUE.EVENT_DRIVEN { MODELPARAM_VALUE.EVENT_DRIVEN PARAM_VALUE.EVENT_DRIVEN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.EVENT_DRIVEN}] ${MODELPARAM_VALUE.EVENT_DRIVEN}
}

