proc dualVth {args} {
	parse_proc_arguments -args $args results
	set savings $results(-savings)
	
	############################################################################################################################################################
	# Name : SUPPRESS INFORMATION MESSAGES
	# Description : Suppress terminal messages
	############################################################################################################################################################
	
	suppress_message PWR-601
	suppress_message PWR-246
	suppress_message NED-045
	suppress_message LNK-041
	suppress_message PTE-018

	############################################################################################################################################################
	# Name : VARIABLES
	# Description: Declaration of variables and lists
	############################################################################################################################################################
	
	set cell_list_full_name [list]			
	set cell_list_priority [list]
	set LVT_leak_power_list [list]
	set HVT_leak_power_list [list]
	set current_savings 0
	set start_power 0
	set end_power $start_power
	set number_HVT 0
	set swap_direction 0
	set end_flag 0
	set iteration 1
	set compute_delay 0
	set ctw_one 0
	set clocks_design [get_clocks]
	foreach_in_collection clock $clocks_design {
		set clk_period [get_attribute $clock period]
	}
	#############################################################################################################################################################	

	#############################################################################################################################################################
	# Name : PREPARATION STAGE
	# Description : - Checks if the required saving is one of the critical situation : 1 or 0
	#				- If it is an intermediate value, creates a list of leakage power and cell delay when all the cells are LVT; then swaps all the cells to
	#					HVT and creates other two similar lists with the new values (for HVT); finally swap the circuit back to the original configuration
	#				- Set the dichotomous variable to half of the total cells
	#############################################################################################################################################################
	if {$savings == 0.0} {
		#puts "no cell swapped"
	} else {
		if {$savings == 1.0} {
			set start_power [get_attribute [current_design] leakage_power]
			foreach_in_collection cell [get_cells] {
				size_cell $cell [regsub {HS65_LL} [get_attribute $cell ref_name] "HS65_LH"]
			}
			set end_power [get_attribute [current_design] leakage_power]
			set current_savings [expr ($start_power-$end_power)/$start_power]
		} else {
			foreach_in_collection cell [get_cells] {
				lappend cell_list_full_name [get_attribute $cell full_name]
				lappend LVT_leak_power_list [get_attribute $cell leakage_power]
				set start_power [expr $start_power + [get_attribute $cell leakage_power]]
				lappend cell_list_priority -1
				set cell_obj [get_cells $cell]
				set arc_collection [get_timing_arcs -of_objects $cell_obj]
				set delay_max_fall_collection [get_attribute $arc_collection delay_max_fall]
				set delay_max_rise_collection [get_attribute $arc_collection delay_max_rise]
				set delay_max_fall_collection [lsort [concat $delay_max_fall_collection $delay_max_rise_collection]]
				lappend LVT_delay_prop_list [lindex $delay_max_fall_collection end]
			}
			set end_power $start_power
			foreach_in_collection cell [get_cells] {
				size_cell $cell [regsub {HS65_LL} [get_attribute $cell ref_name] "HS65_LH"]
			}
			foreach cell $cell_list_full_name {
				lappend HVT_leak_power_list [get_attribute [get_cells $cell] leakage_power]
				set cell_obj [get_cells $cell]
				set arc_collection [get_timing_arcs -of_objects $cell_obj]
				set delay_max_fall_collection [get_attribute $arc_collection delay_max_fall]
				set delay_max_rise_collection [get_attribute $arc_collection delay_max_rise]
				set delay_max_fall_collection [lsort [concat $delay_max_fall_collection $delay_max_rise_collection]]
				lappend HVT_delay_prop_list [lindex $delay_max_fall_collection end]
			}
			foreach_in_collection cell [get_cells] {
				size_cell $cell [regsub {HS65_LH} [get_attribute $cell ref_name] "HS65_LL"]
			}	
			set cell_to_swap [expr {round (double([llength $cell_list_priority])/2)}]	
		}
	}
	############################################################################################################################################################
	
	############################################################################################################################################################
	# Name : MAIN LOOP
	# Description: It is composed of different sections:
	#					- a) if the dichotomous algorithm states that not enought cells (i.e. to reach the power saving constraint) have been swapped (from LVT 
	#						to HVT), recompute the priority indexes updating cell delay informations before going on. Anyway, every dichotomous cycle slack
	#						informations are updated
	#					- b) swap the required amount of cell (half of the previous iteration) from HVT to LVT or viceversa according to the necessity
	#					- c) performs the smart decisions, choosing the kind of swapping, deciding if the dichotomous algorithm has ended and if an additional
	#						final adjustment has to be performed
	############################################################################################################################################################	
	if {($savings < 1.0) & ($savings > 0.0)} {
		while {$end_flag==0} {
	####### a) section #####################################################
			incr iteration
			if {$swap_direction==0} {
				if {$compute_delay == 1} {
					set LVT_delay_prop_list [list]
				}
				set slack_maximum_list [list]

				foreach cell $cell_list_full_name {
					set cell_obj [get_cells $cell]
					set reference_name [get_attribute $cell_obj ref_name]
					if {[regexp {HS65_LL} $reference_name]} {
						if {$compute_delay == 1} {
							set arc_collection [get_timing_arcs -of_objects $cell_obj]
							set delay_max_fall_collection [get_attribute $arc_collection delay_max_fall]
							set delay_max_rise_collection [get_attribute $arc_collection delay_max_rise]
							set delay_max_fall_collection [lsort [concat $delay_max_fall_collection $delay_max_rise_collection]]
							lappend LVT_delay_prop_list [lindex $delay_max_fall_collection end]
						}
						set pin_collection [get_pins -of_objects $cell_obj]
						foreach_in_collection pin $pin_collection {
							set dir [get_attribute $pin direction]
							if {$dir == "out"} {
								lappend slack_maximum_list [get_attribute $pin max_slack]
							}
						}
					} else {
					if {$compute_delay == 1} {
						lappend LVT_delay_prop_list 0
					}
						lappend slack_maximum_list 0
					}
				}
				foreach_in_collection cell [get_cells] {
					set reference_name [get_attribute $cell ref_name]
					set name [get_attribute $cell full_name]
					if {[regexp {HS65_LL} $reference_name]} {
						set LVT_delay_prop [lindex $LVT_delay_prop_list [lsearch $cell_list_full_name $name]]
						set slack_maximum [lindex $slack_maximum_list [lsearch $cell_list_full_name $name]]
						set LVT_leak_power [lindex $LVT_leak_power_list [lsearch $cell_list_full_name $name]]
						if {$compute_delay == 1} {
							size_cell $cell [regsub {HS65_LL} $reference_name "HS65_LH"]
							set arc_collection [get_timing_arcs -of_objects [get_cells $name]]
							set delay_max_fall_collection [get_attribute $arc_collection delay_max_fall]
							set delay_max_rise_collection [get_attribute $arc_collection delay_max_rise]
							set delay_max_fall_collection [lsort [concat $delay_max_fall_collection $delay_max_rise_collection]]
							set HVT_delay_prop [lindex $delay_max_fall_collection end]
						}
						set HVT_delay_prop [lindex $HVT_delay_prop_list [lsearch $cell_list_full_name $name]]
						set HVT_leak_power [lindex $HVT_leak_power_list [lsearch $cell_list_full_name $name]]
						if {$compute_delay == 1} {
							size_cell $cell [regsub {HS65_LH} $reference_name "HS65_LL"]
						}
						set index [lsearch $cell_list_full_name $name]
						lset cell_list_priority $index [expr (($LVT_leak_power-$HVT_leak_power)/$LVT_leak_power)/(($HVT_delay_prop-$LVT_delay_prop)/$HVT_delay_prop)*($slack_maximum/$clk_period)]

					} else {
						set index [lsearch $cell_list_full_name $name]
						lset cell_list_priority $index -1000
					}
				}
			}
	################################################################################
	
	####### b) section #############################################################
			if {$swap_direction==0} {
				set swap_cell_priority_list [list]
				set indices_clp [lsort -indices -real $cell_list_priority]
				for {set i 0} {($i<$cell_to_swap) & ($number_HVT < [llength $cell_list_full_name]) & ($i<[llength $cell_list_priority])} {incr i} {
					lappend swap_cell_priority_list [lindex $cell_list_full_name [lindex $indices_clp end]]
					set cell_obj [get_cells [lindex $cell_list_full_name [lindex $indices_clp end]]]
					set reference_name [get_attribute $cell_obj ref_name]
					set end_power [expr $end_power - [lindex $LVT_leak_power_list [lindex $indices_clp end]] + [lindex $HVT_leak_power_list [lindex $indices_clp end]]]
					lset cell_list_priority [lindex $indices_clp end] -1000
					set indices_clp [lreplace $indices_clp end end]
					size_cell $cell_obj [regsub {HS65_LL} $reference_name "HS65_LH"]					
					incr number_HVT
				}
			} else {
				for {set i 0} {($i<$cell_to_swap) & ($number_HVT > 0)} {incr i} {
					set cell_obj [get_cells [lindex $swap_cell_priority_list end]]
					set end_power [expr $end_power + [lindex $LVT_leak_power_list [lsearch $cell_list_full_name [lindex $swap_cell_priority_list end]]] - [lindex $HVT_leak_power_list [lsearch $cell_list_full_name [lindex $swap_cell_priority_list end]]]]
					set swap_cell_priority_list [lreplace $swap_cell_priority_list end end]
					set reference_name [get_attribute $cell_obj ref_name]
					size_cell $cell_obj [regsub {HS65_LH} $reference_name "HS65_LL"]
					incr number_HVT -1
				}
			}
	###############################################################################
	
	####### c) section #############################################################
			set current_savings [expr ($start_power-$end_power)/$start_power]
			if {$number_HVT > [expr {round (0.85*[llength $cell_list_full_name])}]} {
				set compute_delay 1
			} else {
				set compute_delay 0
			}
			if {$cell_to_swap == 1} {
				set ctw_one 1
				if {$swap_direction == 0} {
					if {($current_savings > $savings)} {
						set end_flag 1
					}
				}
			}
			if {$current_savings>$savings} {
				set swap_direction 1
			} else {
				set swap_direction 0
			}
			if {$ctw_one == 0} {
				set cell_to_swap [expr {round (double([llength $swap_cell_priority_list])/2)}]		
			}
	###############################################################################
		}
	}
	
	############################################################################################################################################################
	
	############################################################################################################################################################
	# Name : SAVING PRINT
	# Description: Optional final saving print to terminal
	############################################################################################################################################################
	#puts "###############################"
	#puts "final saving = $current_savings"
	#puts "###############################"
	############################################################################################################################################################
	return
}

define_proc_attributes dualVth \
-info "Post-Synthesis Dual-Vth cell assignment" \
-define_args \
{
	{-savings "minimum % of leakage savings in range [0, 1]" lvt float required}
}

