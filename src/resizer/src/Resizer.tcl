# Resizer, LEF/DEF gate resizer
# Copyright (c) 2019, Parallax Software, Inc.
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

namespace eval sta {

# Defined by SWIG interface Resizer.i.
define_cmd_args "set_dont_use" {cell dont_use}

define_cmd_args "set_wire_rc" {[-layer layer_name]\
				 [-resistance res ][-capacitance cap]\
				 [-corner corner_name]}

proc set_wire_rc { args } {
   parse_key_args "set_wire_rc" args \
    keys {-layer -resistance -capacitance -corner} flags {}

  set wire_res 0.0
  set wire_cap 0.0

  if { [info exists keys(-layer)] } {
    if { [info exists keys(-resistance)] \
	   || [info exists keys(-capacitance)] } {
      sta_error "Use -layer or -resistance/-capacitance but not both."
    }
    set layer_name $keys(-layer)
    set layer [[[ord::get_db] getTech] findLayer $layer_name]
    if { $layer == "NULL" } {
      sta_error "layer $layer_name not found."
    }
    set layer_width [ord::dbu_to_microns [$layer getWidth]]
    set res_ohm_per_micron [expr [$layer getResistance] / $layer_width]
    set cap_pf_per_micron [expr [ord::dbu_to_microns 1] * $layer_width \
			     * [$layer getCapacitance] \
			     + [$layer getEdgeCapacitance] * 2]
    # ohms/sq
    set wire_res [expr $res_ohm_per_micron * 1e+6]
    # F/m^2
    set wire_cap [expr $cap_pf_per_micron * 1e-12 * 1e+6]
    puts "$wire_res $wire_cap"
  } else {
    if { [info exists keys(-resistance)] } {
      set res $keys(-resistance)
      check_positive_float "-resistance" $res
      set wire_res [expr [resistance_ui_sta $res] / [distance_ui_sta 1.0]]
    }

    if { [info exists keys(-capacitance)] } {
      set cap $keys(-capacitance)
      check_positive_float "-capacitance" $cap
      set wire_cap [expr [capacitance_ui_sta $cap] / [distance_ui_sta 1.0]]
    }
  }

  set corner [parse_corner keys]
  check_argc_eq0 "set_wire_rc" $args

  set_wire_rc_cmd $wire_res $wire_cap $corner
}

define_cmd_args "resize" {[-buffer_inputs]\
			    [-buffer_outputs]\
			    [-resize]\
			    [-repair_max_cap]\
			    [-repair_max_slew]\
			    [-resize_libraries resize_libs]\
			    [-buffer_cell buffer_cell]\
			    [-dont_use lib_cells]}

proc resize { args } {
  parse_key_args "resize" args \
    keys {-buffer_cell -resize_libraries -dont_use -max_utilization} \
    flags {-buffer_inputs -buffer_outputs -resize -repair_max_cap -repair_max_slew}

  set buffer_inputs [info exists flags(-buffer_inputs)]
  set buffer_outputs [info exists flags(-buffer_outputs)]
  set resize [info exists flags(-resize)]
  set repair_max_cap [info exists flags(-repair_max_cap)]
  set repair_max_slew [info exists flags(-repair_max_slew)]
  # With no options you get the whole salmai.
  if { !($buffer_inputs || $buffer_outputs || $resize \
	   || $repair_max_cap || $repair_max_slew) } {
    set buffer_inputs 1
    set buffer_outputs 1
    set resize 1
    set repair_max_cap 1
    set repair_max_slew 1
  }
  set buffer_cell "NULL"
  if { [info exists keys(-buffer_cell)] } {
    set buffer_cell_name $keys(-buffer_cell)
    # check for -buffer_cell [get_lib_cell arg] return ""
    if { $buffer_cell_name != "" } {
      set buffer_cell [get_lib_cell_error "-buffer_cell" $buffer_cell_name]
      if { $buffer_cell != "NULL" } {
	if { ![get_property $buffer_cell is_buffer] } {
	  sta_error "Error: [get_name $buffer_cell] is not a buffer."
	}
      }
    }
  }
  if { $buffer_cell == "NULL" && ($buffer_inputs || $buffer_outputs \
				    || $repair_max_cap || $repair_max_slew) } {
    sta_error "Error: resize -buffer_cell required for buffer insertion."
  }

  if { [info exists keys(-resize_libraries)] } {
    set resize_libs [get_liberty_error "-resize_libraries" $keys(-resize_libraries)]
  } else {
    set resize_libs [get_libs *]
  }

  set dont_use {}
  if { [info exists keys(-dont_use)] } {
    set dont_use [get_lib_cells -quiet $keys(-dont_use)]
  }

  set max_util 0.0
  if { [info exists keys(-max_utilization)] } {
    set max_util $keys(-max_utilization)
    if {!([string is double $max_util] && $max_util >= 0.0 && $max_util <= 100)} {
      sta_error "-max_utilization must be between 0 and 100%."
    }
    set max_util [expr $max_util / 100.0]
  }

  check_argc_eq0 "resize" $args

  resizer_preamble $resize_libs
  set_dont_use $dont_use
  set_max_utilization $max_util
  if { $buffer_inputs } {
    buffer_inputs $buffer_cell
  }
  if { $buffer_outputs } {
    buffer_outputs $buffer_cell
  }
  if { $resize } {
    resize_to_target_slew
  }
  if { $repair_max_cap || $repair_max_slew } {
    rebuffer_nets $repair_max_cap $repair_max_slew $buffer_cell
  }
}

define_cmd_args "get_pin_net" {pin_name}

proc get_pin_net { pin_name } {
  set pin [get_pin_error "pin_name" $pin_name]
  return [$pin net]
}

define_cmd_args "report_design_area" {}

proc report_design_area {} {
  set util [format %.0f [expr [utilization] * 100]]
  set area [format_area [design_area] 0]
  puts "Design area ${area} u^2 ${util}% utilization."
}

# sta namespace end
}
