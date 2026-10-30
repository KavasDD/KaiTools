;highlight_padstack.il
;
;Rev 1, 16 Sep 2003 
;
;Program by Geoff Meek email: meekg@rogers.com
;
;This program makes a list of component pin padstacks / vias, and a list of drill sizes in the layout.
;The users then picks a name from either list. ...the padstacks are highlighted.
;Made and tested in Allegro v14.2
;
;Type "hps" the start program.

axlCmdRegister( "hps" `_ps_highlight)

;********************************************************************************
(defun _ps_highlight ()

	padstacklist=makeTable("atable1" 0)					;make empty table for all padstacks.
	drillsizelist=makeTable("atable2" 0)					;make empty table for all Drill sizes.
	
	vis_list = axlVisibleGet()							;store design visibility
	
	allpadstacks()										;run sub routine to fill in these lists.

 	hps_form()										;Make Form
 	
 	
 	Form=axlFormCreate( (gensym) "hps_formd.form" '(e outer) 'hps_form_Action t)
 	
 	padlist=nil										;initialize variable.
 	foreach( pad padstacklist							;go thru padstacklist table.
 		padlist=cons( pad padlist)						;build a list of padstacks.
 	);end foreach
 	
 	padstacklist=sort(padlist 'alphalessp)					;put in alphabetical order.
 
 	foreach( name padstacklist							;go thru list and 
 		axlFormSetField( Form "padstacklist" name)			;add name to form list
	);end foreach
	
	procedure(floatToString(val)							;This function converts floating 
		let((stringval)								;numbers to strings.
			sprintf(stringval "%g" val)
		);let
	);procedure
 
	
	drilllist=nil										;initialize variable.
	foreach( Drill drillsizelist							;go thru drillsizelist table.
		drilllist=cons(floatToString(Drill) drilllist)		;build a list of drill sizes.
	);end foreach
	
 	drillsizelist=sort(drilllist 'alphalessp)				;put in alphabetical order.
 	
	foreach( Drill drillsizelist							;go thru list and
		axlFormSetField( Form "drillholelist" Drill)			;add size to form list
	);end foreach
	
	axlFormDisplay(Form)
	
 
); end defun _ps_highlight

;******************************************************************************

(defun hps_form ()
	
   	hps_formd=outfile("hps_formd.form" "w")
   
	fprintf(hps_formd "FILE_TYPE=FORM_DEFN VERSION=2\n")   
   	fprintf(hps_formd "FORM\n")	
   	fprintf(hps_formd "FIXED\n")
   	fprintf(hps_formd "PORT 27 45\n")
   	fprintf(hps_formd "HEADER \"Select Padstacks\"\n")
   	fprintf(hps_formd "TILE\n")
  
   	fprintf(hps_formd "FIELD padstacklist\n")
   	fprintf(hps_formd "FLOC 2 2\n")
   	fprintf(hps_formd "LIST \"Pad Stacks\" 24 9\n")
   	fprintf(hps_formd "ENDFIELD\n")

	fprintf(hps_formd "FIELD drillholelist\n")
	fprintf(hps_formd "FLOC 2 22\n")
	fprintf(hps_formd "LIST \"Drill Sizes\" 24 4\n")
	fprintf(hps_formd "ENDFIELD\n")

	fprintf(hps_formd "FIELD Done\n")
	fprintf(hps_formd "FLOC 12 30\n")
	fprintf(hps_formd "MENUBUTTON \"Done\" 2 3\n")
	fprintf(hps_formd "ENDFIELD\n")
	
	fprintf(hps_formd "TEXT \"Drill Sizes\"\n")
	fprintf(hps_formd "TLOC 2 20\n")
   	fprintf(hps_formd "ENDTEXT\n")
	
   	fprintf(hps_formd "ENDTILE\n")
   	fprintf(hps_formd "ENDFORM\n");
   	close(hps_formd)
   
);end defun hps_form

;*********************************************************************************** 

(defun hps_form_Action (hps_formd)
  (case hps_formd ->curField
  
	("padstacklist"								;When a name is selected in the list,
		highlightPS()								;Run sub routine to highlight padstacks
		axlUIWUpdate(nil)
		axlFlushDisplay()
	);
	
     ("drillholelist"								;When a name is selected in the list,
     	highlightPS()								;Run sub routine to highlight padstacks
		axlUIWUpdate(nil)
		axlFlushDisplay()
		axlShell("redisplay")
     )
     
     
     ("Done"
     	axlClearSelSet()
     	deleteFile("hps_formd.form")
     	axlFormClose(hps_formd )
     	axlCancelEnterFun()
   	)
     
   ); end case hps_formd ->curField
); end defun hps_form_Action

;************************************************************************************

(defun allpadstacks ()
	
	axlVisibleDesign(nil)
	axlVisibleLayer("PIN/TOP" t)
	axlVisibleLayer("PIN/BOTTOM" t)
	axlVisibleLayer("PIN/SOLDERMASK_TOP" t)
	axlVisibleLayer("PIN/SOLDERMASK_BOTTOM" t)
	axlVisibleLayer("VIA CLASS/TOP" t)
	axlVisibleLayer("VIA CLASS/BOTTOM" t)
	axlVisibleLayer("MANUFACTURING/NCDRILL_FIGURE" t)
	
	axlClearSelSet()
	axlSetFindFilter(?enabled list("noall" "pins" "vias")
	        ?onButtons list("noall" "pins" "vias"))
	axlAddSelectAll()
	pin_list = axlGetSelSet()
	axlVisibleSet(vis_list)								;restore design visibility
	axlVisibleUpdate(t)
	axlClearSelSet()

	foreach(pin_db pin_list								;go thru layout pin list
	
		padstack_db = pin_db->definition					;Extract PadstackID from pinID
		pad_name=padstack_db->name						;Extract Padstack Name from PadstackID
		padstacklist[pad_name]=pad_name					;add to padstacklist table
		Drillsize = padstack_db->drillDiameter				;Extract Drill Diameter from PadstackID
		drillsizelist[Drillsize]=Drillsize					;add to drillsizelist table
		
	);end foreach
	
);end of defun allpadstacks

;*************************************************************************

(defun highlightPS ()

	axlClearSelSet()
	axlSetFindFilter(?enabled list("noall" "pins" "vias")
        ?onButtons list("noall" "pins" "vias"))
	axlAddSelectAll()
	pin_list = axlGetSelSet()
	axlClearSelSet()
	
	countd=0											;count number of drills
	count=0											;count number of padstacks
	
	foreach(pin_db pin_list								;go thru pins and vias in design

		padstack_db = pin_db->definition					
		pad_name=padstack_db->name						;extract padstack name
		
		drill = padstack_db->drillDiameter					;extract drill diameter
		
		if( (pad_name==hps_formd->curValue) then			;if the pin has the same padstack
			count=count+1								;as was selected in form list,
			axlAddSelectObject( pin_db )					;highlight pin or via
			axlFormListSelect(hps_formd "drillholelist" nil)	;deselect drill list
		);end if
		
		if( (floatToString(drill)==hps_formd->curValue) then	;if the pin has the same drill size
			countd=countd+1							;as was selected in form list,
			axlAddSelectObject( pin_db )					;highlight pin or via
			axlFormListSelect(hps_formd "padstacklist" nil)	;deselect padstack list 
		);end if
		
	);end foreach
	
	if( (count==0) then									; Final count displayed
		message=sprintf(nil "%n Drill Holes Found " countd )
		axlUIWPrint(hps_formd message)
	else
		message=sprintf(nil "%n Padstacks Found " count )
		axlUIWPrint(hps_formd message)
	);end if
	
	if( count==0 && countd==0 then
		message=sprintf(nil "Layer has to be visible!")
		axlUIWPrint(hps_formd message)
	);
	
);end defun highlightPS 
 