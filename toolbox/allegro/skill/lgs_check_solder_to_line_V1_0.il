 
 
 
 
 
 
 
 
 
 
 
 
 




 
 
 

axlCmdRegister( "solder2line check" `xkC7__lgs_check_solder_to_line ?cmdType "general")

 
 
 
(defun xkC7__lgs_check_solder_to_line ()

xkC7__lgs_check_solder_to_line_main_formlgs_area_list = nil
xkC7_lgs_hilight_bBox = nil
xkC7_lgs_view_number = 0
xkC7_lgs_soder_adder = 2
xkC7_lgs_zoom_i = 70
xkC7_lgs_bBox_win = nil
xkC7_lgs_stol_checksamenet = nil
xkC7_lgs_layer = nil
xkC7__lgs_check_solder_to_line_main_form()
axlFormSetField( xkC7_lgs_stol_main_form "lgs_distance_D" xkC7_lgs_soder_adder)
axlFormSetField( xkC7_lgs_stol_main_form "lgs_distance_O" xkC7_lgs_soder_adder*1.4142)
axlFormSetField( xkC7_lgs_stol_main_form "stol_checksamenet" xkC7_lgs_stol_checksamenet)
) 

 
 
 
(defun xkC7__lgs_solder_to_line_check ( xkC7_lgs_layer xkC7_lgs_soder_adder)

xkC7__lgs_creat_progress_form()
xkC7_lgs_area_list = nil
xkC7_lgs_area_list_small = nil
xkC7_lgs_area_list45 = nil
xkC7_lgs_hilight_bBox = nil
xkC7_lgs_bBox_win = nil
xkC7_lgs_view_number = 0
xkC7_lgs_times = 0

axlSetFindFilter(?enabled '(noall pins) ?onButtons '(noall pins))
xkC7_lgs_all_pins_list = axlGetSelSet(axlAddSelectAll())
axlClearSelSet()

foreach(xkC7_lgs_item_pins xkC7_lgs_all_pins_list

	xkC7_lgs_times++
	xkC7_lgs_all_pads_list = xkC7_lgs_item_pins->pads

	foreach(xkC7_lgs_item_pads xkC7_lgs_all_pads_list

		if(((xkC7_lgs_item_pads->layer == xkC7_lgs_layer) && (xkC7_lgs_item_pads->figureName == "RECTANGLE") && (xkC7_lgs_item_pads->type == "REGULAR"))
		   ||((xkC7_lgs_item_pads->layer == xkC7_lgs_layer) && (xkC7_lgs_item_pads->figureName == "SQUARE") && (xkC7_lgs_item_pads->type == "REGULAR"))
		then
			 
			if(mod( round( xkC7_lgs_item_pins->rotation) 90) == 0
			then
				 
				xkC7_lgs_item_bBox = xkC7_lgs_item_pads->bBox
                	
				if(xkC7__lgs_bBox_check_0( xkC7_lgs_item_bBox)		 
				then
					xkC7_lgs_item_1x = car( car( xkC7_lgs_item_bBox))
					xkC7_lgs_item_1y = nthelem( 2 car( xkC7_lgs_item_bBox))
					xkC7_lgs_item_2x = car( nthelem( 2 xkC7_lgs_item_bBox))
					xkC7_lgs_item_2y = nthelem( 2 nthelem( 2 xkC7_lgs_item_bBox))
                	
					if(xkC7_lgs_item_1x < xkC7_lgs_item_2x
					then
						xkC7_lgs_item_1x_n = xkC7_lgs_item_1x - xkC7_lgs_soder_adder + car( xkC7_lgs_item_pins->xy)
						xkC7_lgs_item_2x_n = xkC7_lgs_item_2x + xkC7_lgs_soder_adder + car( xkC7_lgs_item_pins->xy)
                	
					else
						xkC7_lgs_item_1x_n = xkC7_lgs_item_1x + xkC7_lgs_soder_adder + car( xkC7_lgs_item_pins->xy)
						xkC7_lgs_item_2x_n = xkC7_lgs_item_2x - xkC7_lgs_soder_adder + car( xkC7_lgs_item_pins->xy)
                	
					  ) 
                	
					if(xkC7_lgs_item_1y < xkC7_lgs_item_2y
					then
						xkC7_lgs_item_1y_n = xkC7_lgs_item_1y - xkC7_lgs_soder_adder + cadr( xkC7_lgs_item_pins->xy)
						xkC7_lgs_item_2y_n = xkC7_lgs_item_2y + xkC7_lgs_soder_adder + cadr( xkC7_lgs_item_pins->xy)
					else
						xkC7_lgs_item_1y_n = xkC7_lgs_item_1y + xkC7_lgs_soder_adder + cadr( xkC7_lgs_item_pins->xy)
						xkC7_lgs_item_2y_n = xkC7_lgs_item_2y - xkC7_lgs_soder_adder + cadr( xkC7_lgs_item_pins->xy)
                	
					  ) 
                	
					xkC7_lgs_item_bBox = list( list( xkC7_lgs_item_1x_n xkC7_lgs_item_1y_n) list( xkC7_lgs_item_2x_n xkC7_lgs_item_2y_n))
                	
					xkC7_lgs_area_list = cons( list( xkC7_lgs_item_bBox) xkC7_lgs_area_list)		 
                	
					xkC7_lgs_item_1x_n_samll = xkC7_lgs_item_1x + car( xkC7_lgs_item_pins->xy)
					xkC7_lgs_item_2x_n_samll = xkC7_lgs_item_2x + car( xkC7_lgs_item_pins->xy)
										
					xkC7_lgs_item_1y_n_samll = xkC7_lgs_item_1y + cadr( xkC7_lgs_item_pins->xy)
					xkC7_lgs_item_2y_n_samll = xkC7_lgs_item_2y + cadr( xkC7_lgs_item_pins->xy)
					
					xkC7_lgs_item_bBox = list( list( xkC7_lgs_item_1x_n_samll xkC7_lgs_item_1y_n_samll) list( xkC7_lgs_item_2x_n_samll xkC7_lgs_item_2y_n_samll))
					
					xkC7_lgs_area_list_small = cons( list( xkC7_lgs_item_bBox) xkC7_lgs_area_list_small)
        	        	
        	        	
					) 
				 
			 
			else if(mod( round( xkC7_lgs_item_pins->rotation) 45) == 90			 
				then
					xkC7_lgs_item_bBox = xkC7_lgs_item_pads->parent->bBox
					
					xkC7_ya = (caar( xkC7_lgs_item_bBox) + cadadr( xkC7_lgs_item_bBox))/1.4142
					xkC7_yb = (caar( xkC7_lgs_item_bBox) + cadar( xkC7_lgs_item_bBox))/1.4142
					xkC7_yc = (caadr( xkC7_lgs_item_bBox) + cadar( xkC7_lgs_item_bBox))/1.4142
					xkC7_yd = (caadr( xkC7_lgs_item_bBox) + cadadr( xkC7_lgs_item_bBox))/1.4142
					
					xkC7_pin_x = car( xkC7_lgs_item_pins->xy)
					xkC7_pin_y = cadr( xkC7_lgs_item_pins->xy)
					
					xkC7_pax = xkC7_yb + xkC7_pin_x
					xkC7_pay = xkC7_ya + xkC7_pin_y
					
					xkC7_pbx = xkC7_ya + xkC7_pin_x
					xkC7_pby = xkC7_yb + xkC7_pin_y
					
					xkC7_pcx = xkC7_yd + xkC7_pin_x
					xkC7_pcy = xkC7_yc + xkC7_pin_y
					
					xkC7_pdx = xkC7_yc + xkC7_pin_x
					xkC7_pdy = xkC7_yd + xkC7_pin_y
					
					xkC7_lgs_item_bBox_list = nil
					
					xkC7_lgs_item_bBox_list = cons( list( list(xkC7_pin_x-0.1 xkC7_pin_y-0.1) list(xkC7_pdx+0.1 xkC7_pdy+0.1)) xkC7_lgs_item_bBox_list)
					xkC7_lgs_item_bBox_list = cons( list( list(xkC7_pax-xkC7_lgs_soder_adder xkC7_pay-0.1) list(xkC7_pax xkC7_pay+0.1)) xkC7_lgs_item_bBox_list)
					xkC7_lgs_item_bBox_list = cons( list( list(xkC7_pbx-0.1 xkC7_pby-xkC7_lgs_soder_adder) list(xkC7_pbx xkC7_pby+0.1)) xkC7_lgs_item_bBox_list)
					xkC7_lgs_item_bBox_list = cons( list( list(xkC7_pcx xkC7_pcy-0.1) list(xkC7_pcx+xkC7_lgs_soder_adder xkC7_pcy+0.1)) xkC7_lgs_item_bBox_list)
					xkC7_lgs_item_bBox_list = cons( list( list(xkC7_pdx xkC7_pdy-0.1) list(xkC7_pdx+0.1 xkC7_pdy+xkC7_lgs_soder_adder)) xkC7_lgs_item_bBox_list)
					
					
					xkC7_lgs_area_list = cons( xkC7_lgs_item_bBox_list xkC7_lgs_area_list)
					
				
				
				
				) 
			) 
			 
			
			
		) 
	) 

			xkC7_lgs_temp = round( xkC7_lgs_times * 50 / length( xkC7_lgs_all_pins_list))
			axlFormSetField( xkC7_lgs_progress_form "lgs_progress" xkC7_lgs_temp)
			axlUIWPrint( xkC7_lgs_stol_main_form "%d%% Complete!" xkC7_lgs_temp)
) 


axlSetFindFilter(?enabled '(noall VIAS CLINESEGS SHAPES PINS) ?onButtons '(noall VIAS CLINESEGS SHAPES PINS))

if(xkC7_lgs_stol_checksamenet == nil
then						 

	xkC7_lgs_times = 0
	foreach(xkC7_lgs_item_bBox_list xkC7_lgs_area_list
		xkC7_lgs_times++
		xkC7_lgs_temp_select_list = nil
		foreach(xkC7_lgs_item_bBox xkC7_lgs_item_bBox_list
			axlSingleSelectBox( xkC7_lgs_item_bBox)
			xkC7_lgs_temp_select_list = append( axlGetSelSet()~>net xkC7_lgs_temp_select_list)
		
		) 
		
		if(xkC7__lgs_check_list_same(xkC7_lgs_temp_select_list) == nil
		then
			xkC7_lgs_hilight_bBox = cons( xkC7_lgs_item_bBox_list xkC7_lgs_hilight_bBox)
		 ) 
	
		axlClearSelSet()
	
		xkC7_lgs_temp = round( xkC7_lgs_times * 50 / length( xkC7_lgs_area_list)) + 50
		axlFormSetField( xkC7_lgs_progress_form "lgs_progress" xkC7_lgs_temp)
		axlUIWPrint( xkC7_lgs_stol_main_form "%d%% Complete!" xkC7_lgs_temp)

	) 

else						 

	xkC7_lgs_times = 0
	foreach(xkC7_lgs_item_bBox xkC7_lgs_area_list
		xkC7_lgs_times++
		axlSingleSelectBox( car( xkC7_lgs_item_bBox))
		xkC7_lgs_temp1 = axlGetSelSet()
		axlClearSelSet()
		axlSingleSelectBox( car( nthelem(xkC7_lgs_times xkC7_lgs_area_list_small)))
		if(xkC7_lgs_temp1 != axlGetSelSet()
		then
			xkC7_lgs_hilight_bBox = cons( xkC7_lgs_item_bBox xkC7_lgs_hilight_bBox)
		) 

		xkC7_lgs_temp = round( xkC7_lgs_times * 50 / length( xkC7_lgs_area_list)) + 50
		axlFormSetField( xkC7_lgs_progress_form "lgs_progress" xkC7_lgs_temp)
		axlUIWPrint( xkC7_lgs_stol_main_form "%d%% Complete!" xkC7_lgs_temp)
		
	) 
	


) 
axlFormClose( xkC7_lgs_progress_form)

) 

 
 
 
(defun xkC7__lgs_bBox_check_0 ( xkC7_lgs_check_bBox)
(prog ()
if(((car( car( xkC7_lgs_check_bBox))-car( nthelem( 2 xkC7_lgs_check_bBox))) != 0)
&& (nthelem( 2 car( xkC7_lgs_check_bBox))-nthelem( 2 nthelem( 2 xkC7_lgs_check_bBox)) != 0)
then
	return( t)

else
	return( nil)
  ) 
)) 
 
 
 
(defun xkC7__lgs_check_list_same (xkC7_item_list)
prog(()

if(length( xkC7_item_list) < 2
then
	return( t)
) 

for(xkC7_i 1 length( xkC7_item_list)-1
	if(nthelem(xkC7_i xkC7_item_list) != nthelem(xkC7_i+1 xkC7_item_list)
	then
		return( nil)
	) 
   ) 
return( t)

)) 

 
 
 
(defun xkC7__lgs_stol_main_back ( xkC7_lgs_stol_main_form)
case(xkC7_lgs_stol_main_form->curField

	("stol_checksamenet"
		xkC7_lgs_stol_checksamenet = xkC7_lgs_stol_main_form->curValue	
	)

	("lgs_distance_D"
		xkC7_lgs_soder_adder = xkC7_lgs_stol_main_form->curValue
		 
		axlFormSetField( xkC7_lgs_stol_main_form "lgs_distance_O" xkC7_lgs_soder_adder*1.4142)
	t)

	("lgs_distance_O"
		xkC7_lgs_soder_adder = 0.7071 * xkC7_lgs_stol_main_form->curValue
		axlFormSetField( xkC7_lgs_stol_main_form "lgs_distance_D" xkC7_lgs_soder_adder)
		 
	t)

	("lgs_h_top"
		axlShell("setwindow pcb")
		axlVisibleDesign( nil)
		axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
		axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
		 
		 
		axlVisibleLayer("ETCH/TOP" t)
		axlVisibleLayer("VIA CLASS/TOP" t)
		axlVisibleLayer("PIN/TOP" t)
		axlFlushDisplay()
		axlShell("redraw")
		xkC7_lgs_layer = "top"
		xkC7__lgs_solder_to_line_check( "PIN/SOLDERMASK_TOP" xkC7_lgs_soder_adder)

		sprintf(xkC7_lgs_info "%d Errors be find!" length(xkC7_lgs_hilight_bBox))
		axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" xkC7_lgs_info)

	t)

	("lgs_h_botm"
		axlShell("setwindow pcb")
		axlVisibleDesign( nil)
		axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
		axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
		 
		 
		axlVisibleLayer("ETCH/BOTTOM" t)
		axlVisibleLayer("VIA CLASS/BOTTOM" t)
		axlVisibleLayer("PIN/BOTTOM" t)
		axlFlushDisplay()
		axlShell("redraw")
		xkC7_lgs_layer = "bottom"
		xkC7__lgs_solder_to_line_check( "PIN/SOLDERMASK_BOTTOM" xkC7_lgs_soder_adder)

		sprintf(xkC7_lgs_info "%d Errors be find!" length(xkC7_lgs_hilight_bBox))
		axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" xkC7_lgs_info)

	t)
	
	("lgs_zoom"

			xkC7_lgs_zoom = xkC7_lgs_stol_main_form->curValue
			xkC7_lgs_zoom_i = 70 + 4.5*xkC7_lgs_zoom
			axlFormSetField( xkC7_lgs_stol_main_form "shadow_factor"  strcat(sprintf( xkC7_lgs_temp "%d" xkC7_lgs_zoom) "%"))
			if(xkC7_lgs_bBox_win != nil
			then
			axlWindowBoxSet(list((caar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i)
					     (caar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i)))
			) 
			

	t)


	("lgs_first"
		if(xkC7_lgs_layer == "top"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
			 
			 
			axlVisibleLayer("ETCH/TOP" t)
			axlVisibleLayer("VIA CLASS/TOP" t)
			axlVisibleLayer("PIN/TOP" t)
			axlFlushDisplay()
			axlShell("redraw")
		
		else if(xkC7_lgs_layer == "bottom"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
			 
			 
			axlVisibleLayer("ETCH/BOTTOM" t)
			axlVisibleLayer("VIA CLASS/BOTTOM" t)
			axlVisibleLayer("PIN/BOTTOM" t)
			axlFlushDisplay()
			axlShell("redraw")

		)) 
	
	
		if(length( xkC7_lgs_hilight_bBox) != 0
		then
			axlClearSelSet()
			xkC7_lgs_view_number = 1
			xkC7_lgs_bBox_win = car( nthelem(xkC7_lgs_view_number xkC7_lgs_hilight_bBox))
			axlWindowBoxSet(list((caar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i)
					     (caar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i)))
			axlSetFindFilter(?enabled '(noall VIAS CLINESEGS SHAPES PINS) ?onButtons '(noall VIAS CLINESEGS SHAPES PINS))
			axlSingleSelectBox( xkC7_lgs_bBox_win)
			sprintf(xkC7_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC7_lgs_view_number length(xkC7_lgs_hilight_bBox))
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" xkC7_lgs_info)
		else
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" "\307\353\317\310\274\354\262\351\241\243")
			axlUIWPrint( xkC7_lgs_stol_main_form "%s" "\307\353\317\310\274\354\262\351\241\243")
		) 
	t)

	("lgs_next"
		if(xkC7_lgs_layer == "top"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
			 
			 
			axlVisibleLayer("ETCH/TOP" t)
			axlVisibleLayer("VIA CLASS/TOP" t)
			axlVisibleLayer("PIN/TOP" t)
			axlFlushDisplay()
			axlShell("redraw")
		
		else if(xkC7_lgs_layer == "bottom"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
			 
			 
			axlVisibleLayer("ETCH/BOTTOM" t)
			axlVisibleLayer("VIA CLASS/BOTTOM" t)
			axlVisibleLayer("PIN/BOTTOM" t)
			axlFlushDisplay()
			axlShell("redraw")

		)) 

		if(length( xkC7_lgs_hilight_bBox) > xkC7_lgs_view_number
		then
			axlClearSelSet()
			xkC7_lgs_view_number++
			xkC7_lgs_bBox_win = car( nthelem(xkC7_lgs_view_number xkC7_lgs_hilight_bBox))
			axlWindowBoxSet(list((caar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i)
					     (caar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i)))
			axlSetFindFilter(?enabled '(noall VIAS CLINESEGS SHAPES PINS) ?onButtons '(noall VIAS CLINESEGS SHAPES PINS))
			axlSingleSelectBox( xkC7_lgs_bBox_win)
			sprintf(xkC7_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC7_lgs_view_number length(xkC7_lgs_hilight_bBox))
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" xkC7_lgs_info)
		else
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" "\307\353\317\310\274\354\262\351\241\243")
			axlUIWPrint( xkC7_lgs_stol_main_form "%s" "\307\353\317\310\274\354\262\351\241\243")
		) 
	t)

	("lgs_prev"
		if(xkC7_lgs_layer == "top"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
			 
			 
			axlVisibleLayer("ETCH/TOP" t)
			axlVisibleLayer("VIA CLASS/TOP" t)
			axlVisibleLayer("PIN/TOP" t)
			axlFlushDisplay()
			axlShell("redraw")
		
		else if(xkC7_lgs_layer == "bottom"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
			 
			 
			axlVisibleLayer("ETCH/BOTTOM" t)
			axlVisibleLayer("VIA CLASS/BOTTOM" t)
			axlVisibleLayer("PIN/BOTTOM" t)
			axlFlushDisplay()
			axlShell("redraw")

		)) 

		if(xkC7_lgs_view_number > 1
		then
			axlClearSelSet()
			xkC7_lgs_view_number--
			xkC7_lgs_bBox_win = car( nthelem(xkC7_lgs_view_number xkC7_lgs_hilight_bBox))
			axlWindowBoxSet(list((caar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i)
					     (caar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i)))
			axlSetFindFilter(?enabled '(noall VIAS CLINESEGS SHAPES PINS) ?onButtons '(noall VIAS CLINESEGS SHAPES PINS))
			axlSingleSelectBox( xkC7_lgs_bBox_win)
			sprintf(xkC7_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC7_lgs_view_number length(xkC7_lgs_hilight_bBox))
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" xkC7_lgs_info)
		else
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" "\307\353\317\310\274\354\262\351\241\243")
			axlUIWPrint( xkC7_lgs_stol_main_form "%s" "\307\353\317\310\274\354\262\351\241\243")
		) 
	t)

	("lgs_last"
		if(xkC7_lgs_layer == "top"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
			 
			 
			axlVisibleLayer("ETCH/TOP" t)
			axlVisibleLayer("VIA CLASS/TOP" t)
			axlVisibleLayer("PIN/TOP" t)
			axlFlushDisplay()
			axlShell("redraw")
		
		else if(xkC7_lgs_layer == "bottom"
		then
			axlShell("setwindow pcb")
			axlVisibleDesign( nil)
			axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
			 
			 
			axlVisibleLayer("ETCH/BOTTOM" t)
			axlVisibleLayer("VIA CLASS/BOTTOM" t)
			axlVisibleLayer("PIN/BOTTOM" t)
			axlFlushDisplay()
			axlShell("redraw")

		)) 

		if(length( xkC7_lgs_hilight_bBox) != 0
		then
			axlClearSelSet()
			xkC7_lgs_view_number = length( xkC7_lgs_hilight_bBox)
			xkC7_lgs_bBox_win = car( nthelem(xkC7_lgs_view_number xkC7_lgs_hilight_bBox))
			axlWindowBoxSet(list((caar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)-xkC7_lgs_zoom_i)
					     (caar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i):(cadar( xkC7_lgs_bBox_win)+xkC7_lgs_zoom_i)))
			axlSetFindFilter(?enabled '(noall VIAS CLINESEGS SHAPES PINS) ?onButtons '(noall VIAS CLINESEGS SHAPES PINS))
			axlSingleSelectBox( xkC7_lgs_bBox_win)
			sprintf(xkC7_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC7_lgs_view_number length(xkC7_lgs_hilight_bBox))
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" xkC7_lgs_info)
		else
			axlFormSetField( xkC7_lgs_stol_main_form "lgs_info" "\307\353\317\310\274\354\262\351\241\243")
			axlUIWPrint( xkC7_lgs_stol_main_form "%s" "\307\353\317\310\274\354\262\351\241\243")
		) 
	t)

	(("done" "cancel")
		unless(xkC7_lgs_stol_main_form->doneState == 3 axlFormClose(xkC7_lgs_stol_main_form))
	t)

	("lgs_hilight_help"
		xkC7__lgs_stol_help_Form()
	t)
 
	) 

) 


 
 
 
procedure(xkC7__lgs_check_solder_to_line_main_form()
 xkC7_lgs_stol_main_form=axlFormCreate((gensym) list("_lgs_check_solder_to_line_main_form" "FILE_TYPE=FORM_DEFN VERSION=2\t\nFORM\t\nFIXED\t\nPORT 58 34\t\nHEADER \"D3\243\272\272\270\305\314\323\353\327\337\317\337\274\344\276\340\274\354\262\351\"\t\nTILE\t\nTEXT \"\274\344\276\340\243\250\265\261\307\260\311\350\274\306\265\245\316\273\243\251\"\t\nTLOC 2 1\t\nENDTEXT\t\nFIELD lgs_distance_D\t\nFLOC 42 1\t\nREALFILLIN 12 12\t\nREALMIN 0\t\nENDFIELD\t\nTEXT \"\320\261\317\362\276\340\300\353\"\t\nTLOC 2 5\t\nENDTEXT\t\nFIELD lgs_distance_O\t\nFLOC 42 5\t\nREALFILLIN 12 12\t\nREALMIN 0\t\nENDFIELD\t\nFIELD stol_checksamenet\t\nFLOC 2 9\t\nCHECKLIST \"\315\254\312\261\274\354\262\351\315\254\315\370\302\347\"\t\nENDFIELD\t\nFIELD lgs_h_top\t\nFLOC 2 13\t\nMENUBUTTON \"\274\354\262\351\266\245\262\343\" 24 3\t\nENDFIELD\t\nFIELD lgs_h_botm\t\nFLOC 30 13\t\nMENUBUTTON \"\274\354\262\351\265\327\262\343\" 24 3\t\nENDFIELD\t\nFIELD lgs_info\t\nFLOC 2 18\t\nSTRFILLIN 54 80\t\nENDFIELD\t\nFIELD lgs_first\t\nFLOC 2 23\t\nMENUBUTTON \"\312\327\317\356\" 12 3\t\nENDFIELD\t\nFIELD lgs_prev\t\nFLOC 16 23\t\nMENUBUTTON \"\311\317\322\273\317\356\" 12 3\t\nENDFIELD\t\nFIELD lgs_next\t\nFLOC 30 23\t\nMENUBUTTON \"\317\302\322\273\317\356\" 12 3\t\nENDFIELD\t\nFIELD lgs_last\t\nFLOC 44 23\t\nMENUBUTTON \"\304\251\317\356\" 12 3\t\nENDFIELD\t\nTEXT \"\313\365\267\305\"\t\nTLOC 2 28\t\nENDTEXT\t\nFIELD lgs_zoom\t\nFLOC 12 28\t\nTRACKBAR 32 4\t\nMIN 0\t\nMAX 100\t\nENDFIELD\t\nTEXT\t\nTLOC 46 28\t\nINFO shadow_factor 8\t\nENDTEXT\t\nENDTILE\t\nENDFORM\t\t\n") '(e inner) 'xkC7__lgs_stol_main_back t)
 when(xkC7_lgs_stol_main_form axlFormDisplay(xkC7_lgs_stol_main_form) )
) 

 
 
 
(defun xkC7__lgs_creat_progress_form ()
 
xkC7_hilightsmd_Form=outfile("xkC7_lgs_progress_Form.form" "w")
fprintf(xkC7_hilightsmd_Form "#Write by lgs \t\n")
fprintf(xkC7_hilightsmd_Form "FILE_TYPE=FORM_DEFN VERSION=2\t\n")
fprintf(xkC7_hilightsmd_Form "FORM\t\n")
fprintf(xkC7_hilightsmd_Form "FIXED\t\n")
fprintf(xkC7_hilightsmd_Form "PORT 45 14\t\n")
fprintf(xkC7_hilightsmd_Form "HEADER \"\272\270\305\314\323\353\327\337\317\337\243\272\274\354\262\351\275\370\266\310\"\t\n")
fprintf(xkC7_hilightsmd_Form "TILE\t\n")
fprintf(xkC7_hilightsmd_Form "FIELD lgs_progress\t\n")
fprintf(xkC7_hilightsmd_Form "FLOC 3 1\t\n")
fprintf(xkC7_hilightsmd_Form "PROGRESS 40 3\t\n")
fprintf(xkC7_hilightsmd_Form "ENDFIELD\t\n")
fprintf(xkC7_hilightsmd_Form "ENDTILE\t\n")
fprintf(xkC7_hilightsmd_Form "ENDFORM  \t\n")
close(xkC7_hilightsmd_Form)
xkC7_lgs_progress_form = axlFormCreate( (gensym) "xkC7_lgs_progress_Form.form" '(e outer) 'xkC7__lgs_nil t)
deleteFile( "xkC7_lgs_progress_Form.form")
axlFormDisplay( xkC7_lgs_progress_form)
(defun xkC7__lgs_nil (xkC7_lgs_progress_form)
1==1
)
 
) 
 
 
 
(defun xkC7__lgs_stol_help_Form ()
	setq( lgsfindcompshelpform "./xkC7_lgsstolhelp.form")
        deleteFile( lgsfindcompshelpform)
        xkC7_FORMFINDHELPFILE = outfile( lgsfindcompshelpform)
        fprintf( xkC7_FORMFINDHELPFILE "FILE_TYPE=FORM_DEFN VERSION=2\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "FORM\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "FIXED\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "PORT 33 70\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "HEADER \"Hilight SMD V1.0\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TILE\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "GROUP \"\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "FLOC 3 0\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "FSIZE 28 6\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "INFO group\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDGROUP\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"Solder to Line V1.0\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 10 2\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"Check Solder to Line Error\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 8 4\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"Revision:1.0\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 13 6\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"Write by:Li Guangsheng/24445\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 6 8\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"HUAWEI CAD \"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 12 10\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"DATA:05/25/2002\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 11 12\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"Have any Problem Please Contact Me!\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 4 14\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TEXT \"ADD:1618   TEL:50574\"\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "TLOC 8 16\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "FIELD lgsok\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "FLOC 11 18\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "MENUBUTTON \"OK\" 10 3\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDFIELD\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDTILE\t\n")
        fprintf( xkC7_FORMFINDHELPFILE "ENDFORM\t\n")
        close( xkC7_FORMFINDHELPFILE)
        xkC7_findhelpform = (axlFormCreate (gensym) lgsfindcompshelpform `("E" "OUTER") `xkC7_lgs_find_help_Callback t)
        axlFormDisplay( xkC7_findhelpform)
) 

 
 
 
(defun xkC7_lgs_find_help_Callback (xkC7_findhelpform)
	axlFormClose( xkC7_findhelpform)
	deleteFile( lgsfindcompshelpform)
) 

 
 
 
