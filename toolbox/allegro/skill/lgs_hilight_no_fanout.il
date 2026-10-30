 
 
 
 
 
 
 
 
 
 
 
 
 

   


 
 
 
axlCmdRegister( "hl_nf_top" `xkC5__lgs_hilight_no_fanoutsmd_top ?cmdType "general")
axlCmdRegister( "hl_nf_botm" `xkC5__lgs_hilight_no_fanoutsmd_botm ?cmdType "general")
axlCmdRegister( "hl_nf" `xkC5__lgs_hilight_smd_main ?cmdType "general")

 
 
 
(defun xkC5__lgs_hilight_smd_main ()
let(()
 xkC5_lgs_hilight_bBox=nil
 xkC5_lgs_view_number=0


 

 
 
 
procedure(xkC5__lgs_creat_hilight_smd_main_form()
 xkC5_lgs_hilight_smd_main_form=axlFormCreate((gensym) list("_lgs_creat_hilight_smd_main_form" "FILE_TYPE=FORM_DEFN VERSION=2\t\nFORM\t\nFIXED\t\nPORT 58 19\t\nHEADER \"D2\243\272\316\264\311\310\263\366 SMD \322\375\275\305\274\354\262\351\"\t\nTILE\t\nFIELD lgs_h_top\t\nFLOC 2 2\t\nMENUBUTTON \"\274\354\262\351\266\245\262\343\" 24 3\t\nENDFIELD\t\nFIELD lgs_h_botm\t\nFLOC 30 2\t\nMENUBUTTON \"\274\354\262\351\265\327\262\343\" 24 3\t\nENDFIELD\t\nFIELD lgs_info\t\nFLOC 2 7\t\nSTRFILLIN 54 80\t\nENDFIELD\t\nFIELD lgs_first\t\nFLOC 2 12\t\nMENUBUTTON \"\312\327\317\356\" 12 3\t\nENDFIELD\t\nFIELD lgs_prev\t\nFLOC 16 12\t\nMENUBUTTON \"\311\317\322\273\317\356\" 12 3\t\nENDFIELD\t\nFIELD lgs_next\t\nFLOC 30 12\t\nMENUBUTTON \"\317\302\322\273\317\356\" 12 3\t\nENDFIELD\t\nFIELD lgs_last\t\nFLOC 44 12\t\nMENUBUTTON \"\304\251\317\356\" 12 3\t\nENDFIELD\t\nENDTILE\t\nENDFORM\t\t\n") '(e inner) 'xkC5__lgs_hilight_smd_main_back t)
 when(xkC5_lgs_hilight_smd_main_form axlFormDisplay(xkC5_lgs_hilight_smd_main_form) )
) 

 
 
 
(defun xkC5__lgs_hilight_smd_main_back ( xkC5_lgs_hilight_smd_main_form)
case(xkC5_lgs_hilight_smd_main_form->curField

	("lgs_h_top"
		xkC5__lgs_hilight_no_fanoutsmd_top()
		sprintf(xkC5_lgs_info "\267\242\317\326 %d \270\366\316\264\311\310\263\366\322\375\275\305" length(xkC5_lgs_hilight_bBox))
		axlFormSetField( xkC5_lgs_hilight_smd_main_form "lgs_info" xkC5_lgs_info)
		xkC5_lgs_view_number = 0
	t)

	("lgs_h_botm"
		xkC5__lgs_hilight_no_fanoutsmd_botm()
		sprintf(xkC5_lgs_info "\267\242\317\326 %d \270\366\316\264\311\310\263\366\322\375\275\305" length(xkC5_lgs_hilight_bBox))
		axlFormSetField( xkC5_lgs_hilight_smd_main_form "lgs_info" xkC5_lgs_info)
		xkC5_lgs_view_number = 0
	t)
	
	("lgs_first"
		if(length( xkC5_lgs_hilight_bBox) != 0
		then
			xkC5_lgs_view_number = 1
			xkC5_lgs_bBox = nthelem(xkC5_lgs_view_number xkC5_lgs_hilight_bBox)
			axlWindowBoxSet(list((caar( xkC5_lgs_bBox)-200):(cadar( xkC5_lgs_bBox)-200) 
					     (caar( xkC5_lgs_bBox)+200):(cadar( xkC5_lgs_bBox)+200)))
			sprintf(xkC5_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC5_lgs_view_number length(xkC5_lgs_hilight_bBox))
			axlFormSetField( xkC5_lgs_hilight_smd_main_form "lgs_info" xkC5_lgs_info)					 
		) 
	t)
	
	("lgs_next"
		if(length( xkC5_lgs_hilight_bBox) > xkC5_lgs_view_number
		then
			xkC5_lgs_view_number++
			xkC5_lgs_bBox = nthelem(xkC5_lgs_view_number xkC5_lgs_hilight_bBox)
			axlWindowBoxSet(list((caar( xkC5_lgs_bBox)-200):(cadar( xkC5_lgs_bBox)-200) 
					     (caar( xkC5_lgs_bBox)+200):(cadar( xkC5_lgs_bBox)+200)))
			sprintf(xkC5_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC5_lgs_view_number length(xkC5_lgs_hilight_bBox))
			axlFormSetField( xkC5_lgs_hilight_smd_main_form "lgs_info" xkC5_lgs_info)					 
		) 
	t)
	
	("lgs_prev"
		if(xkC5_lgs_view_number > 1
		then
			xkC5_lgs_view_number--
			xkC5_lgs_bBox = nthelem(xkC5_lgs_view_number xkC5_lgs_hilight_bBox)
			axlWindowBoxSet(list((caar( xkC5_lgs_bBox)-200):(cadar( xkC5_lgs_bBox)-200) 
					     (caar( xkC5_lgs_bBox)+200):(cadar( xkC5_lgs_bBox)+200)))
			sprintf(xkC5_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC5_lgs_view_number length(xkC5_lgs_hilight_bBox))
			axlFormSetField( xkC5_lgs_hilight_smd_main_form "lgs_info" xkC5_lgs_info)					 
		) 
	t)
	
	("lgs_last"
		if(length( xkC5_lgs_hilight_bBox) != 0
		then
			xkC5_lgs_view_number = length( xkC5_lgs_hilight_bBox)
			xkC5_lgs_bBox = nthelem(xkC5_lgs_view_number xkC5_lgs_hilight_bBox)
			axlWindowBoxSet(list((caar( xkC5_lgs_bBox)-200):(cadar( xkC5_lgs_bBox)-200) 
					     (caar( xkC5_lgs_bBox)+200):(cadar( xkC5_lgs_bBox)+200)))
			sprintf(xkC5_lgs_info "\265\332 %d \317\356 / \271\262 %d \317\356" xkC5_lgs_view_number length(xkC5_lgs_hilight_bBox))
			axlFormSetField( xkC5_lgs_hilight_smd_main_form "lgs_info" xkC5_lgs_info)					 
		) 
	t)
	
	(("done" "cancel")
		unless(xkC5_lgs_hilight_smd_main_form->doneState == 3 axlFormClose(xkC5_lgs_hilight_smd_main_form))
	t)
	
	("lgs_hilight_help"
		xkC5__lgs_hilight_smd_help_Form()
	t)



) 
) 

 
 
 
(defun xkC5__lgs_hilight_smd_help_Form ()
	setq( lgsfindcompshelpform "./xkC5_lgshilighthelp.form")
        deleteFile( lgsfindcompshelpform)
        xkC5_FORMFINDHELPFILE = outfile( lgsfindcompshelpform)
        fprintf( xkC5_FORMFINDHELPFILE "FILE_TYPE=FORM_DEFN VERSION=2\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "FORM\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "FIXED\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "PORT 33 70\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "HEADER \"Hilight SMD V1.0\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TILE\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "GROUP \"\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "FLOC 3 0\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "FSIZE 28 6\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "INFO group\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDGROUP\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"Hilight SMD V1.0\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 10 2\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"Hilight SMD without fanout\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 8 4\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"Revision:1.0\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 13 6\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"Write by:Li Guangsheng/24445\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 6 8\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"HUAWEI CAD \"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 12 10\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"DATA:05/25/2002\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 11 12\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"Have any Problem Please Contact Me!\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 4 14\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TEXT \"ADD:1618   TEL:50574\"\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "TLOC 8 16\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTEXT\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "FIELD lgsok\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "FLOC 11 18\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "MENUBUTTON \"OK\" 10 3\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDFIELD\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDTILE\t\n")
        fprintf( xkC5_FORMFINDHELPFILE "ENDFORM\t\n")
        close( xkC5_FORMFINDHELPFILE)
        xkC5_findhelpform = (axlFormCreate (gensym) lgsfindcompshelpform `("E" "OUTER") `xkC5_lgs_find_help_Callback t)
        axlFormDisplay( xkC5_findhelpform)
) 

 
 
 
(defun xkC5_lgs_find_help_Callback (xkC5_findhelpform)
	axlFormClose( xkC5_findhelpform)
	deleteFile( lgsfindcompshelpform)
) 

 
 
 
(defun xkC5__lgs_hilight_no_fanoutsmd_top ()

xkC5__lgs_creat_hilight_smd_form()
axlUIWPrint( xkC5_lgs_hilight_smd_form "\325\375\324\332\266\301\310\241\322\375\275\305\241\255")
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" 1)                                                      
xkC5_lgs_smd_bBox = nil

axlShell("setwindow pcb")
axlVisibleDesign( nil)
axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
axlVisibleLayer("BOARD GEOMETRY/SILKSCREEN_TOP" t)
axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_TOP" t)
axlVisibleLayer("ETCH/TOP" t)
axlVisibleLayer("VIA CLASS/TOP" t)
axlVisibleLayer("PIN/TOP" t)
axlFlushDisplay()
axlShell("redraw")
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" 2)
axlSetFindFilter(?enabled '(noall pins) ?onButtons '(noall pins))
xkC5_lgs_all_pins_list = axlGetSelSet(axlAddSelectAll())
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" 10)
axlUIWPrint( xkC5_lgs_hilight_smd_form "\325\375\324\332\274\354\262\351\316\264\311\310\263\366\322\375\275\305\241\255")
axlClearSelSet()
axlSetFindFilter(?enabled '(noall VIAS CLINESEGS SHAPES) ?onButtons '(noall VIAS CLINESEGS SHAPES))

 
xkC5_lgs_hilight_bBox = nil
xkC5_lgs_time = 11
xkC5_lgs_step = length( xkC5_lgs_all_pins_list)/45
xkC5_lgs_i = 0
foreach(xkC5_lgs_item_pin xkC5_lgs_all_pins_list
	xkC5_lgs_i++
	if((xkC5_lgs_item_pin->isThrough==nil) && (xkC5_lgs_item_pin->startEnd=='("ETCH/TOP" "ETCH/TOP"))
	then
		
		xkC5_lgs_item_bBox_mi = list(list( (caar(xkC5_lgs_item_pin->bBox)+caadr(xkC5_lgs_item_pin->bBox))/2-1 
					      (cadar(xkC5_lgs_item_pin->bBox)+cadadr(xkC5_lgs_item_pin->bBox))/2-1) 
					list( (caar(xkC5_lgs_item_pin->bBox)+caadr(xkC5_lgs_item_pin->bBox))/2+1 
					      (cadar(xkC5_lgs_item_pin->bBox)+cadadr(xkC5_lgs_item_pin->bBox))/2+1))
		 
		if(axlSingleSelectBox( xkC5_lgs_item_bBox_mi) == nil
		then
			 
			if(xkC5_lgs_item_pin~>net~>bBox != xkC5_lgs_item_pin~>bBox
			then
				xkC5_lgs_hilight_bBox = append( xkC5_lgs_hilight_bBox list(xkC5_lgs_item_bBox_mi))
			) 
		) 
	) 
	
	if(xkC5_lgs_i > xkC5_lgs_step
	then
		xkC5_lgs_i = 0
		xkC5_lgs_time++
		axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" xkC5_lgs_time)
	
	) 

) 
 
axlShell("setwindow pcb")
axlShell("hilight")
axlShell("setwindow form.find")
axlShell("FORM find all_off")
axlShell("FORM find pins YES")
xkC5_lgs_step = length( xkC5_lgs_hilight_bBox)/45
xkC5_lgs_i = 0
xkC5_lgs_time++
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" xkC5_lgs_time)
axlUIWPrint( xkC5_lgs_hilight_smd_form "\325\375\324\332\270\337\301\301\275\341\271\373\241\255")

foreach(xkC5_lgs_item_bBox xkC5_lgs_hilight_bBox
	xkC5_lgs_i++
	sprintf(xkC5_lgs_command_line "pick grid %1.2f %1.2f" caar( xkC5_lgs_item_bBox)+1 cadar( xkC5_lgs_item_bBox)+1)
	axlShell( xkC5_lgs_command_line)
	
	if(xkC5_lgs_i > xkC5_lgs_step
	then
		xkC5_lgs_i = 0
		xkC5_lgs_time++
		axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" xkC5_lgs_time)
	
	) 

) 
axlShell("setwindow pcb")
axlShell("done")
axlFormClose( xkC5_lgs_hilight_smd_form)

 
printf( "Hilight SMD Pin without fanout V1.0-----Write by HUAWEI: LiGuangsheng/24445\t\n")
printf( "Hilight SMD Pin without fanout Successful\t\n")
printf( " %d SMD Pin on ETCH/TOP without fanout, Already Hilight!\t\n" length( xkC5_lgs_hilight_bBox))


 
) 

 
 
 






 
 
 
(defun xkC5__lgs_hilight_no_fanoutsmd_botm ()

xkC5__lgs_creat_hilight_smd_form()
axlUIWPrint( xkC5_lgs_hilight_smd_form "\325\375\324\332\266\301\310\241\322\375\275\305\241\255")
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" 1)                                                      
xkC5_lgs_smd_bBox = nil

axlShell("setwindow pcb")
axlVisibleDesign( nil)
axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
axlVisibleLayer("BOARD GEOMETRY/SILKSCREEN_BOTTOM" t)
axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" t)
axlVisibleLayer("ETCH/BOTTOM" t)
axlVisibleLayer("VIA CLASS/BOTTOM" t)
axlVisibleLayer("PIN/BOTTOM" t)
axlFlushDisplay()
axlShell("redraw")
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" 2)
axlSetFindFilter(?enabled '(noall pins) ?onButtons '(noall pins))
xkC5_lgs_all_pins_list = axlGetSelSet(axlAddSelectAll())
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" 10)
axlUIWPrint( xkC5_lgs_hilight_smd_form "\325\375\324\332\274\354\262\351\316\264\311\310\263\366\322\375\275\305\241\255")
axlClearSelSet()
axlSetFindFilter(?enabled '(noall VIAS CLINESEGS SHAPES) ?onButtons '(noall VIAS CLINESEGS SHAPES))

 
xkC5_lgs_hilight_bBox = nil
xkC5_lgs_time = 11
xkC5_lgs_step = length( xkC5_lgs_all_pins_list)/45
xkC5_lgs_i = 0

foreach(xkC5_lgs_item_pin xkC5_lgs_all_pins_list
	xkC5_lgs_i++
	if((xkC5_lgs_item_pin->isThrough==nil) && (xkC5_lgs_item_pin->startEnd=='("ETCH/BOTTOM" "ETCH/BOTTOM"))
	then
		
		xkC5_lgs_item_bBox_mi = list(list( (caar(xkC5_lgs_item_pin->bBox)+caadr(xkC5_lgs_item_pin->bBox))/2-1 
					      (cadar(xkC5_lgs_item_pin->bBox)+cadadr(xkC5_lgs_item_pin->bBox))/2-1) 
				        list( (caar(xkC5_lgs_item_pin->bBox)+caadr(xkC5_lgs_item_pin->bBox))/2+1 
				              (cadar(xkC5_lgs_item_pin->bBox)+cadadr(xkC5_lgs_item_pin->bBox))/2+1))
		 
		if(axlSingleSelectBox( xkC5_lgs_item_bBox_mi) == nil
		then
			 
			if(xkC5_lgs_item_pin~>net~>bBox != xkC5_lgs_item_pin~>bBox
			then
				xkC5_lgs_hilight_bBox = append( xkC5_lgs_hilight_bBox list(xkC5_lgs_item_bBox_mi))
			) 
		) 
	) 
	
	if(xkC5_lgs_i > xkC5_lgs_step
	then
		xkC5_lgs_i = 0
		xkC5_lgs_time++
		axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" xkC5_lgs_time)
	
	) 
	

) 
 
axlShell("setwindow pcb")
axlShell("hilight")
axlShell("setwindow form.find")
axlShell("FORM find all_off")
axlShell("FORM find pins YES")
xkC5_lgs_step = length( xkC5_lgs_hilight_bBox)/45
xkC5_lgs_i = 0
xkC5_lgs_time++
axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" xkC5_lgs_time)
axlUIWPrint( xkC5_lgs_hilight_smd_form "\325\375\324\332\270\337\301\301\275\341\271\373\241\255")

foreach(xkC5_lgs_item_bBox xkC5_lgs_hilight_bBox
	xkC5_lgs_i++
	sprintf(xkC5_lgs_command_line "pick grid %1.2f %1.2f" caar( xkC5_lgs_item_bBox)+1 cadar( xkC5_lgs_item_bBox)+1)
	axlShell( xkC5_lgs_command_line)
		
	if(xkC5_lgs_i > xkC5_lgs_step
	then
		xkC5_lgs_i = 0
		xkC5_lgs_time++
		axlFormSetField( xkC5_lgs_hilight_smd_form "lgs_progress" xkC5_lgs_time)
	
	) 

) 
axlShell("setwindow pcb")
axlShell("done")
axlFormClose( xkC5_lgs_hilight_smd_form)

 
printf( "Hilight SMD Pin without fanout V1.0-----Write by HUAWEI: LiGuangsheng/24445\t\n")
printf( "Hilight SMD Pin without fanout Successful\t\n")
printf( " %d SMD Pin on ETCH/BOTTOM without fanout, Already Hilight!\t\n" length( xkC5_lgs_hilight_bBox))

 

) 

 
 
 



 
 
 
(defun xkC5__lgs_creat_hilight_smd_form ()
 
xkC5_hilightsmd_Form=outfile("xkC5_lgs_hilight_smd_Form.form" "w")
fprintf(xkC5_hilightsmd_Form "#Write by lgs \t\n")
fprintf(xkC5_hilightsmd_Form "FILE_TYPE=FORM_DEFN VERSION=2\t\n")
fprintf(xkC5_hilightsmd_Form "FORM\t\n")     
fprintf(xkC5_hilightsmd_Form "FIXED\t\n")               
fprintf(xkC5_hilightsmd_Form "PORT 45 14\t\n")          
fprintf(xkC5_hilightsmd_Form "HEADER \"\316\264\311\310\263\366\322\375\275\305\243\272\274\354\262\351\275\370\266\310\"\t\n")
fprintf(xkC5_hilightsmd_Form "TILE\t\n")                
fprintf(xkC5_hilightsmd_Form "FIELD lgs_progress\t\n")      
fprintf(xkC5_hilightsmd_Form "FLOC 3 1\t\n")            
fprintf(xkC5_hilightsmd_Form "PROGRESS 40 3\t\n")       
fprintf(xkC5_hilightsmd_Form "ENDFIELD\t\n")            
fprintf(xkC5_hilightsmd_Form "ENDTILE\t\n")             
fprintf(xkC5_hilightsmd_Form "ENDFORM  \t\n")           
close(xkC5_hilightsmd_Form)
xkC5_lgs_hilight_smd_form = axlFormCreate( (gensym) "xkC5_lgs_hilight_smd_Form.form" '(e outer) 'xkC5__lgs_nil t)
deleteFile( "xkC5_lgs_hilight_smd_Form.form")
axlFormDisplay( xkC5_lgs_hilight_smd_form)
(defun xkC5__lgs_nil (xkC5_hilightsmd_Form)
1==1
)
 
) 


 
 
 
 
 


 
xkC5_lgs_view_number = 0
xkC5__lgs_creat_hilight_smd_main_form()

) 
) 
 
 
