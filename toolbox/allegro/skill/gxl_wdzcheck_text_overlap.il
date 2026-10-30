; load "jkcheck_text_overlap.il" 
axlCmdRegister( "ch_text_overlap" `xkB5_check_text_overlap)

xkB5_layer = "TOP"
xkB5_clearance = 3
xkB5_text_pad = t
xkB5_text_testpoint = nil
xkB5_text_text = nil
xkB5_barcode_overlap = nil
xkB5_refdes_component = nil
xkB5_formname = nil
xkB5_location = makeTable("loc" 0)
xkB5_num = 0 
xkB5_cnt = 0

(defun xkB5_check_text_overlap ()
    axlVisibleDesign(nil)
    xkB5_turn_on_layer( xkB5_layer)
    xkB5_formname = "./refdes_over.form" 
    xkB5_biuld_form(xkB5_formname)
)

(defun xkB5_biuld_form (xkB5_formname)
(prog ()  
   xkB5_pform = outfile(xkB5_formname "w")

   fprintf(xkB5_pform "FILE_TYPE=FORM_DEFN VERSION=2\t\n")

   fprintf(xkB5_pform "FORM\t\n")

   fprintf(xkB5_pform "FIXED\t\n")

   fprintf(xkB5_pform "PORT 50 31\t\n")

   fprintf(xkB5_pform "HEADER \"D8 丝印重叠检查（增强版）\"\t\n")

   fprintf(xkB5_pform "POPUP <Layer_Names>")

   fprintf(xkB5_pform "\"TOP\" \"TOP\",\"BOTTOM\" \"BOTTOM\".\t\n")

   fprintf(xkB5_pform "TILE\t\n")

   
   fprintf(xkB5_pform "TEXT \"选择检查层：\"\t\n")

   fprintf(xkB5_pform "TLOC 3 1\t\n")

   fprintf(xkB5_pform "ENDTEXT\t\n")

   fprintf(xkB5_pform "FIELD check_layer\t\n")

   fprintf(xkB5_pform "FLOC 6 3\t\n")

   fprintf(xkB5_pform "ENUMSET 11\t\n")

   fprintf(xkB5_pform "POP \"Layer_Names\"\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   
   fprintf(xkB5_pform "TEXT \"检查间距：\"\t\n")

   fprintf(xkB5_pform "TLOC 3 6\t\n")

   fprintf(xkB5_pform "ENDTEXT\t\n")

   fprintf(xkB5_pform "FIELD clearance\t\n")

   fprintf(xkB5_pform "FLOC 14 6\t\n")

   fprintf(xkB5_pform "REALFILLIN 6 6\t\n")

   fprintf(xkB5_pform "REALMIN -50.0\t\n")

   fprintf(xkB5_pform "REALMAX 100.0\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

 
   fprintf(xkB5_pform "FIELD text_pad\t\n")

   fprintf(xkB5_pform "FLOC 6 9\t\n")

   fprintf(xkB5_pform "FGROUP \"Overlap\"\t\n")

   fprintf(xkB5_pform "CHECKLIST \"文字与焊盘\" \"overlap\"\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD text_testpoint\t\n")

   fprintf(xkB5_pform "FLOC 6 11\t\n")

   fprintf(xkB5_pform "FGROUP \"Overlap\"\t\n")

   fprintf(xkB5_pform "CHECKLIST \"文字与测试点\" \"overlap\"\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD text_text\t\n")

   fprintf(xkB5_pform "FLOC 6 13\t\n")

   fprintf(xkB5_pform "FGROUP \"Overlap\"\t\n")

   fprintf(xkB5_pform "CHECKLIST \"文字与文字\" \"overlap\"\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD refdes_component\t\n")

   fprintf(xkB5_pform "FLOC 6 15\t\n")

   fprintf(xkB5_pform "FGROUP \"Overlap\"\t\n")

   fprintf(xkB5_pform "CHECKLIST \"位号与封装\" \"overlap\"\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD barcode_overlap\t\n")

   fprintf(xkB5_pform "FLOC 6 17\t\n")

   fprintf(xkB5_pform "FGROUP \"Overlap\"\t\n")

   fprintf(xkB5_pform "CHECKLIST \"条码重叠\" \"overlap\"\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

      
   fprintf(xkB5_pform "TEXT \"检查结果：\"\t\n")

   fprintf(xkB5_pform "TLOC 3 20\t\n")

   fprintf(xkB5_pform "ENDTEXT\t\n")
   
   fprintf(xkB5_pform "FIELD next_view\t\n")

   fprintf(xkB5_pform "FLOC 6 22\t\n")

   fprintf(xkB5_pform "STRFILLIN 10 20\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD prv_ctl\t\n")
   
   fprintf(xkB5_pform "FLOC 18 22\t\n")

   fprintf(xkB5_pform "MENUBUTTON \"<<\" 3 3\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD next_ctl\t\n")
   
   fprintf(xkB5_pform "FLOC 22 22\t\n")

   fprintf(xkB5_pform "MENUBUTTON \">>\" 3 3\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   
   fprintf(xkB5_pform "FIELD done\t\n")

   fprintf(xkB5_pform "FLOC 2 26\t\n")

   fprintf(xkB5_pform "MENUBUTTON \"关闭\" 8 3\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD check\t\n")

   fprintf(xkB5_pform "FLOC 13 26\t\n")

   fprintf(xkB5_pform "MENUBUTTON \"检查\" 8 3\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   fprintf(xkB5_pform "FIELD unselect\t\n")

   fprintf(xkB5_pform "FLOC 24 26\t\n")

   fprintf(xkB5_pform "MENUBUTTON \"取消高亮\" 10 3\t\n")

   fprintf(xkB5_pform "ENDFIELD\t\n")

   
   fprintf(xkB5_pform "ENDTILE\t\n")

   fprintf(xkB5_pform "ENDFORM\t\n")

   close(xkB5_pform)

   
   xkB5_form=axlFormCreate( (gensym) "refdes_over.form" 
   `(e inner) `xkB5_pform_Action t)

   
   axlFormDisplay(xkB5_form)

   axlFormSetField(xkB5_form "check_layer" xkB5_layer)

   axlFormSetField(xkB5_form "clearance" xkB5_clearance)

   axlFormSetField(xkB5_form "text_pad" xkB5_text_pad)

   axlFormSetField(xkB5_form "text_testpoint" xkB5_text_testpoint)

   axlFormSetField(xkB5_form "text_text" xkB5_text_text)

   axlFormSetField(xkB5_form "barcode_overlap" xkB5_barcode_overlap)

   axlFormSetField(xkB5_form "refdes_component" xkB5_refdes_component)

)) 

(defun xkB5_pform_Action (xkB5_form)

 
 axlDBRefreshId(axlDBGetDesign())
   (case xkB5_form->curField
 

   	(("done" "cancel")

    	    axlFormClose(xkB5_form)

    	    axlCancelEnterFun()

    	    deleteFile(xkB5_formname)
   	    axlMsgPut("Done")
    	    nil

   	)

   	("check"
   	    xkB5_init_loc_text()
   	    axlMsgPut("Cheching overlapping text .")
     	    xkB5_turn_on_layer(xkB5_layer)	 
   	    xkB5_refdes_on_pad()
   	    axlFormSetField(xkB5_form "next_view" sprintf(dummy "共 %d 项" xkB5_cnt))
   	    t
   	)
   	("unselect"
   	    axlMsgPut("unSelect all objects.")
   	    xkB5_unselect_object()
   	    t
   	)
   	("next_ctl"
   	    axlMsgPut("Location the next position.")
   	    xkB5_location_text(xkB5_location)
   	    t
   	)
   	("prv_ctl"
   	    axlMsgPut("Location the previous position.")
   	    xkB5_location_prv(xkB5_location)
   	    t
   	)
   	
   	("check_layer"
   	    xkB5_layer = xkB5_form->curValue
     	    xkB5_turn_on_layer(xkB5_layer)	;turn on the layer etch : etch pin via 
   	    axlMsgPut("Select %s layer" xkB5_layer)
   	    t
   	)
   	("clearance"

    	    xkB5_clearance = xkB5_form->curValue
   	    axlMsgPut("Set clearance : %f" xkB5_clearance)
    	    t

   	)
   	("text_pad"
    	    xkB5_text_pad = xkB5_form->curValue

   	    if(xkB5_text_pad then
   	     	axlMsgPut("Check text on pad." )
   	    else
   	     	axlMsgPut("Don't check text on pad." )   	    
   	    )
    	    t

   	)
   	("text_testpoint"
    	    xkB5_text_testpoint = xkB5_form->curValue 
    	    if(xkB5_layer == "TOP" then 
    	        if(xkB5_text_testpoint axlMsgPut("Top side hasn't testpointes." ))
    	    else
   	    	if(xkB5_text_testpoint then 
  	    	    axlMsgPut("Check text on testpoint." )
   	    	else
   	    	    axlMsgPut("Don't check text on testpoint." )
   	        )    	    	
    	    )   	    
    	    t

   	)
  	("barcode_overlap"
    	    xkB5_barcode_overlap = xkB5_form->curValue 

   	    if(xkB5_barcode_overlap then 
   	    	axlMsgPut("Check bar code ." )
   	    else
   	    	axlMsgPut("Don't check bar code ." )
   	    )
    	    t

   	)  

   	("refdes_component"
    	    xkB5_refdes_component = xkB5_form->curValue 

   	    if(xkB5_refdes_component then 
   	    	axlMsgPut("Check refdes on component." )
   	    else
   	    	axlMsgPut("Don't check refdes on component." )
   	    )
    	    t

   	)  

 	("text_text"
    	    xkB5_text_text = xkB5_form->curValue 

   	    if(xkB5_text_text then 
   	    	axlMsgPut("Check text on text." )
   	    else
   	    	axlMsgPut("Don't check text on text." )
   	    )
    	    t

   	)  

    )
)

(defun xkB5_refdes_on_pad ()
	
    if(xkB5_barcode_overlap then
    	xkB5_Going_On=axlGetParam("paramLayerGroup:PACKAGE GEOMETRY/paramLayer:SILKSCREEN_TOP")

    	xkB5_Going_On->visible=t

    	axlSetParam(xkB5_Going_On)  	
    	xkB5_Going_On=axlGetParam("paramLayerGroup:PACKAGE GEOMETRY/paramLayer:SILKSCREEN_BOTTOM")

    	xkB5_Going_On->visible=t

    	axlSetParam(xkB5_Going_On)  	
    
    	axlUIWRedraw(nil)
    	axlClearSelSet()
 
    )  
    
    xkB5_unselect_object()
    axlSetFindFilter(?enabled '(noall text lines)
    	    ?onButtons '(noall text lines))

    xkB5_alltexts = axlGetSelSet(axlAddSelectAll())
        
    if(xkB5_text_pad then
    	xkB5_cnt = 0
    	if(xkB5_layer == "TOP" then
  	    axlSetFindFilter(?enabled '(noall pins shapes)          ; modified by wudezhou 2002/10/15
  	    ?onButtons '(noall pins shapes))
    	else
  	    axlSetFindFilter(?enabled '(noall pins shapes)          ; modified by wudezhou 2002/10/15
  	    ?onButtons '(noall pins shapes))
    	)
    	foreach(xkB5_txt xkB5_alltexts xkB5_text_on_pad(xkB5_txt));end foreach
    	axlMsgPut("Total of text on %s pad : %d" xkB5_layer xkB5_cnt)
    )
    if(xkB5_text_testpoint then
    	xkB5_cnt = 0
    	if(xkB5_layer == "TOP" then
  	    axlSetFindFilter(?enabled '(noall )

  	    ?onButtons '(noall ))
    	else
  	    axlSetFindFilter(?enabled '(noall vias)

  	    ?onButtons '(noall vias))
    	)
    	foreach(xkB5_txt xkB5_alltexts xkB5_text_on_testpoints(xkB5_txt))
    	axlMsgPut("Total of text on %s testpoint : %d" xkB5_layer xkB5_cnt)
    )
    if(xkB5_text_text then    
    	xkB5_cnt = 0
        xkB5_allseltext = nil
    	axlSetFindFilter(?enabled '(noall text) ?onButtons '(noall text))

    	foreach(xkB5_txt xkB5_alltexts xkB5_text_overlap_text(xkB5_txt))
        axlHighlightObject( xkB5_allseltext) 
    	axlMsgPut("Total of text on %s text : %d" xkB5_layer xkB5_cnt)
    )
    if(xkB5_refdes_component then
        xkB5_allselcom = nil
    	xkB5_cnt = 0
	axlSetFindFilter(?enabled '(noall shapes) ?onButtons '(noall shapes))

    	foreach(xkB5_txt xkB5_alltexts xkB5_refdes_overlap_component(xkB5_txt))
        axlHighlightObject( xkB5_allselcom)     
    	axlMsgPut("Total of refdes on %s component : %d" xkB5_layer xkB5_cnt)
    )
    if(xkB5_barcode_overlap then      
    	axlSetFindFilter(?enabled '(noall pins vias text) ?onButtons '(noall pins vias text ))

        xkB5_allselcom = nil
    	xkB5_cnt = 0
    	foreach(xkB5_txt xkB5_alltexts  	; i=0 j=0 k=0 n=0 ++i txt = nthelem(i alltexts)
	   if(xkB5_txt->text == "BAR  CODE" then 
	   	xkB5_barcode_overlap_atom(xkB5_txt)
	   )
    	)
        axlHighlightObject( xkB5_allselcom)     
    	axlMsgPut("Bar code overlaps other item.")
    	
    	xkB5_Going_On=axlGetParam("paramLayerGroup:PACKAGE GEOMETRY/paramLayer:SILKSCREEN_TOP")

    	xkB5_Going_On->visible=nil

    	axlSetParam(xkB5_Going_On)  	
    	xkB5_Going_On=axlGetParam("paramLayerGroup:PACKAGE GEOMETRY/paramLayer:SILKSCREEN_BOTTOM")

    	xkB5_Going_On->visible=nil

    	axlSetParam(xkB5_Going_On)  	
    	xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:PACKAGE GEOMETRY/paramLayer:SILKSCREEN_%s" xkB5_layer))

    	xkB5_Going_On->visible=t

    	axlSetParam(xkB5_Going_On)   
    
    	axlUIWRedraw(nil)
    	axlClearSelSet()
   
    )
) 

(defun xkB5_barcode_overlap_atom (xkB5_txt)
(prog ()

    xkB5_bars = xkB5_txt->parent->name
    xkB5_barx = xkB5_txt->parent->name
    if(xkB5_txt->layer == strcat( "PACKAGE GEOMETRY/SILKSCREEN_" xkB5_layer) 
    || (xkB5_txt->layer != strcat( "PACKAGE GEOMETRY/SILKSCREEN_" xkB5_layer) 
    && index(xkB5_barx "X") == "X") then
	if(axlSingleSelectBox(xkB5_get_bar_code_box(xkB5_txt)) != nil then
	    xkB5_allboxes = axlGetSelSet() 
	    axlClearSelSet()
	    xkB5_have = nil
	    foreach(xkB5_item xkB5_allboxes ;++k item = nthelem(k allboxes)
	        if(xkB5_txt->text != xkB5_item->text && (xkB5_item->objType != "via" 
	        || xkB5_item->testPoint != nil)  then
	            xkB5_allselcom = cons(xkB5_item xkB5_allselcom)
	       	    xkB5_allselcom = cons(xkB5_txt->parent xkB5_allselcom)
		    xkB5_have = t
		)
	    )
	    if(xkB5_have then ++xkB5_cnt xkB5_add_loc_text(xkB5_txt))
	)    
    )
))

(defun xkB5_refdes_overlap_component ( xkB5_txt)
(prog ()
let( (xkB5_item xkB5_allbox)

    if(xkB5_txt->layer == strcat( "REF DES/SILKSCREEN_" xkB5_layer) then 
	if(axlSingleSelectBox(xkB5_getbox(xkB5_txt)) != nil then
	    xkB5_allboxes = axlGetSelSet() 
	    axlClearSelSet()
	    xkB5_have = nil
	    foreach(xkB5_item xkB5_allboxes ;++k item = nthelem(k allboxes)
	        if(xkB5_item->objType == "shape" && 
	        xkB5_item->layer == strcat( "PACKAGE GEOMETRY/PLACE_BOUND_" xkB5_layer) then
	            xkB5_allselcom = cons(xkB5_item xkB5_allselcom)
	       	    xkB5_allselcom = cons(xkB5_txt xkB5_allselcom)
	       	    xkB5_have = t
		)
	    )
	    if(xkB5_have then ++xkB5_cnt xkB5_add_loc_text(xkB5_txt))
	)	    
    )					
)))

(defun xkB5_text_overlap_text ( xkB5_txt)
(prog ()
let( (xkB5_item xkB5_allbox)
	
	if(xkB5_txt->layer == strcat( "REF DES/SILKSCREEN_" xkB5_layer) 
	|| xkB5_txt->layer == strcat( "PACKAGE GEOMETRY/SILKSCREEN_" xkB5_layer) then 	    
	    
	  if(xkB5_txt->objType == "text" then                   ;added by wudezhou 2002/10/16
	  
	    if(axlSingleSelectBox(xkB5_getbox(xkB5_txt)) != nil then
	    	xkB5_allboxes = axlGetSelSet() 
		axlClearSelSet()
		xkB5_allbox = nil
		foreach(xkB5_item xkB5_allboxes	;++n item = nthelem(n allboxes)
		    if(xkB5_item->text != xkB5_txt->text then
		        xkB5_allbox = cons(xkB5_item xkB5_allbox)
		    )		    
		)
		xkB5_have = nil
	    	foreach(xkB5_item xkB5_allbox ;++k item = nthelem(k allbox)
		    if(xkB5_item->objType == "text" then
		        if(xkB5_text_on_text(xkB5_txt xkB5_item) != nil then 
		        xkB5_allseltext = cons(xkB5_item xkB5_allseltext)
		    	xkB5_allseltext = cons(xkB5_txt xkB5_allseltext)
		    	xkB5_have = t
		        )
		    )
		)
		if(xkB5_have then ++xkB5_cnt xkB5_add_loc_text(xkB5_txt))
	    )
	  );end if "text"  	    
	)					
)))

(defun xkB5_text_on_pad (xkB5_txt)
(prog ()
let( (xkB5_item xkB5_allbox)
	
    
    if(xkB5_txt->layer == strcat( "REF DES/SILKSCREEN_" xkB5_layer) 
    	|| xkB5_txt->layer == strcat( "PACKAGE GEOMETRY/SILKSCREEN_" xkB5_layer) 
    	|| xkB5_txt->layer == strcat( "BOARD GEOMETRY/SILKSCREEN_" xkB5_layer) then 	; modified by wudezhou 2002/10/15 
    	
    	case((xkB5_txt->objType)      ; modified by wudezhou 2002/10/15
        ("text"	    		    
	    if(axlSingleSelectBox(xkB5_getbox(xkB5_txt)) != nil then
	    	xkB5_allboxes = axlGetSelSet() 
		axlClearSelSet()
		xkB5_allbox = nil
		foreach(xkB5_item xkB5_allboxes	;++n item = nthelem(n allboxes)
		    ;if(item->text != txt->text then
		        xkB5_allbox = cons(xkB5_item xkB5_allbox)
		    ;)		    
		)
		xkB5_have = nil
	    	foreach(xkB5_item xkB5_allbox ;++k item = nthelem(k allbox)
		    if(xkB5_item->objType == "pin" then
			;allselpad = cons(txt allselpad)
			axlHighlightObject(list(xkB5_txt xkB5_item))
			xkB5_have = t
		    else if(xkB5_item->objType == "shape" 
		        && (xkB5_item->layer == strcat( "PACKAGE GEOMETRY/SOLDERMASK_" xkB5_layer) 
		            || xkB5_item->layer == strcat( "BOARD GEOMETRY/SOLDERMASK_" xkB5_layer)) then
		        
		        axlHighlightObject(list(xkB5_txt xkB5_item))
			xkB5_have = t		        
		        );end if "shape"	
		    );end if "pin"
		);end foreach
		if(xkB5_have then ++xkB5_cnt xkB5_add_loc_text(xkB5_txt))
	    )	    
	)
        ("path"                 ; modified by wudezhou 2002/10/15
            foreach(xkB5_path_seg xkB5_txt->segments   
            	if(axlSingleSelectBox(xkB5_getbox(xkB5_path_seg)) != nil then
	    		xkB5_allboxes = axlGetSelSet() 
			axlClearSelSet()
			xkB5_allbox = nil
			foreach(xkB5_item xkB5_allboxes	;++n item = nthelem(n allboxes)
		    	;if(item->text != txt->text then
			       xkB5_allbox = cons(xkB5_item xkB5_allbox)
			;  )		    
			)
			xkB5_have = nil
	    		foreach(xkB5_item xkB5_allbox ;++k item = nthelem(k allbox)
         		    	if(xkB5_item->objType == "pin" then
	 				;allselpad = cons(txt allselpad)
					axlHighlightObject(list(xkB5_txt xkB5_item))
					xkB5_have = t
				else if(xkB5_item->objType == "shape" 
		        		&& (xkB5_item->layer == strcat( "PACKAGE GEOMETRY/SOLDERMASK_" xkB5_layer)
		        		    || xkB5_item->layer == strcat( "BOARD GEOMETRY/SOLDERMASK_" xkB5_layer)) then		        
		        		axlHighlightObject(list(xkB5_txt xkB5_item))
					xkB5_have = t		        
		        		);end if "shape"	
		    	   	);end if
			);end foreach
			if(xkB5_have then ++xkB5_cnt xkB5_add_loc_text(xkB5_txt))
	    	)   
	    );end foreach 
        )
       );end case          
    );end if text_layer
    						
)))

(defun xkB5_text_on_testpoints (xkB5_txt)
(prog ()
let( (xkB5_item xkB5_allbox)
	
    if(xkB5_txt->layer == strcat( "REF DES/SILKSCREEN_" xkB5_layer) 
    	|| xkB5_txt->layer == strcat( "PACKAGE GEOMETRY/SILKSCREEN_" xkB5_layer) then 	
    	
    	case((xkB5_txt->objType)
        ("text"    
	    if(axlSingleSelectBox(xkB5_getbox(xkB5_txt)) != nil then
	    	xkB5_allboxes = axlGetSelSet() 
		axlClearSelSet()
		xkB5_allselvia = nil
		xkB5_have = nil
	    	foreach(xkB5_item xkB5_allboxes ;++k item = nthelem(k allbox)
		    if(xkB5_layer == "BOTTOM" && xkB5_item->objType == "via" && xkB5_item->testPoint != nil then 
			xkB5_allselvia = cons(xkB5_txt xkB5_allselvia)
		        axlHighlightObject(list(xkB5_item xkB5_txt))
		        xkB5_have = t
		    );end if		    
		);end foreach
		if(xkB5_have then ++xkB5_cnt xkB5_add_loc_text(xkB5_txt))
	    );end if
	 );end "text"
	 ("path"                       ;added by wudezhou 2002.10.15
            ;foreach(path_seg txt->segments   
            ;	if(axlSingleSelectBox(getbox(path_seg)) != nil then
            ;		allboxes = axlGetSelSet() 
	        ;	axlClearSelSet()
	    	;	allselvia = nil
		;	have = nil
	    	;	foreach(item allboxes ;++k item = nthelem(k allbox)
		;   		if(layer == "BOTTOM" && item->objType == "via" && item->testPoint != nil then 
		;			allselvia = cons(txt allselvia)
		;        		axlHighlightObject(list(item txt))
		;       		have = t
		;    	        );end if		    
		;	);end foreach
		;	if(have then ++cnt add_loc_text(txt))
	   	; );end if	 
	    ;);end foreach 	 
	 );end "path"
	 );end case	    
    )					
)))

(defun xkB5_get_bar_code_box (xkB5_txt)
(prog ()
    if(xkB5_txt->text == "BAR  CODE"  then  
    	xkB5_box = xkB5_txt->parent->bBox	
    	xkB5_bleft   = car( nth(0 xkB5_box)) - xkB5_clearance
    	xkB5_btop    = cadr(nth(1 xkB5_box)) + xkB5_clearance	
    	xkB5_bright  = car( nth(1 xkB5_box)) + xkB5_clearance
    	xkB5_bbottom = cadr(nth(0 xkB5_box)) - xkB5_clearance    
    	return(list(xkB5_bleft:xkB5_btop xkB5_bright:xkB5_bbottom)) 
    )
    return(nil)
))

(defun xkB5_getbox (xkB5_txt)
(prog ()
    
    if(xkB5_txt->objType =="line" then               ;added by wudezhou 
        xkB5_startp_x = car(nth(0 xkB5_txt->startEnd))
    	xkB5_startp_y = cadr(nth(0 xkB5_txt->startEnd))
    	xkB5_endp_x = car(nth(1 xkB5_txt->startEnd))
    	xkB5_endp_y = cadr(nth(1 xkB5_txt->startEnd))
    	
        if(xkB5_startp_x != xkB5_endp_x && xkB5_startp_y != xkB5_endp_y then       ;used for diagonal lines
              	xkB5_left = (xkB5_startp_x + xkB5_endp_x)/2.0-4.0
              	xkB5_top = (xkB5_startp_y + xkB5_endp_y)/2.0-4.0
    		xkB5_right = (xkB5_startp_x + xkB5_endp_x)/2.0+4.0
    		xkB5_bottom = (xkB5_startp_y + xkB5_endp_y)/2.0+4.0
        else
            	xkB5_left = car(nth(0 xkB5_txt->bBox))
    		xkB5_top = cadr(nth(0 xkB5_txt->bBox))
    		xkB5_right = car(nth(1 xkB5_txt->bBox))
    		xkB5_bottom = cadr(nth(1 xkB5_txt->bBox))
    	);end if 
     
    else if(xkB5_txt->objType =="text" then          
   	xkB5_loff = 3 xkB5_toff = 0 xkB5_roff = -4 xkB5_boff = 16
     	xkB5_left = car(nth(0 xkB5_txt->bBox)) - xkB5_clearance
     	xkB5_top = cadr(nth(1 xkB5_txt->bBox)) + xkB5_clearance	
     	xkB5_right = car(nth(1 xkB5_txt->bBox)) + xkB5_clearance
     	xkB5_bottom = cadr(nth(0 xkB5_txt->bBox)) - xkB5_clearance
	;    boff = round((top - bottom)/5)+3
           
     if(xkB5_layer == "TOP" then
    	case(round(xkB5_txt->rotation)
    	    (0
    	    	xkB5_boff = round(abs(xkB5_top - xkB5_bottom)/5)+3
    	     	xkB5_left = xkB5_left + xkB5_loff 	xkB5_top = xkB5_top + xkB5_toff 	
    	    	xkB5_right = xkB5_right + xkB5_roff  	xkB5_bottom = xkB5_bottom + xkB5_boff
    	  	t 
    	    )
    	    (90
    	    	xkB5_boff = round(abs(xkB5_right - xkB5_left)/5)+3
    	     	xkB5_left = xkB5_left - xkB5_toff 	xkB5_top = xkB5_top + xkB5_roff 	
    	    	xkB5_right = xkB5_right - xkB5_boff  	xkB5_bottom = xkB5_bottom + xkB5_loff
    	  	t 
    	    )
    	    (180
    	    	xkB5_boff = round(abs(xkB5_top - xkB5_bottom)/5)+3
    	     	xkB5_left = xkB5_left - xkB5_roff 	xkB5_top = xkB5_top - xkB5_boff 	
    	    	xkB5_right = xkB5_right - xkB5_loff  	xkB5_bottom = xkB5_bottom - xkB5_toff
    	  	t 
    	    )
    	    (270
    	    	xkB5_boff = round(abs(xkB5_right - xkB5_left)/5)+3
    	     	xkB5_left = xkB5_left + xkB5_boff 	xkB5_top = xkB5_top - xkB5_loff 	
    	    	xkB5_right = xkB5_right + xkB5_toff  	xkB5_bottom = xkB5_bottom - xkB5_roff
    	  	t 
    	    )
    	)
      )	    
      if(xkB5_layer == "BOTTOM" then
    	case(round(xkB5_txt->rotation)
    	    (0
    	    	xkB5_boff = round(abs(xkB5_top - xkB5_bottom)/5)+3
    	     	xkB5_left = xkB5_left - xkB5_roff 	xkB5_top = xkB5_top + xkB5_toff 	
    	    	xkB5_right = xkB5_right - xkB5_loff  	xkB5_bottom = xkB5_bottom + xkB5_boff
    	  	t 
    	    )
    	    (90
    	    	xkB5_boff = round(abs(xkB5_right - xkB5_left)/5)+3
    	     	xkB5_left = xkB5_left - xkB5_toff 	xkB5_top = xkB5_top - xkB5_loff 	
    	    	xkB5_right = xkB5_right - xkB5_boff  	xkB5_bottom = xkB5_bottom - xkB5_roff
    	  	t 
    	    )
    	    (180
    	    	xkB5_boff = round(abs(xkB5_top - xkB5_bottom)/5)+3
    	     	xkB5_left = xkB5_left + xkB5_loff 	xkB5_top = xkB5_top - xkB5_boff 	
    	    	xkB5_right = xkB5_right + xkB5_roff  	xkB5_bottom = xkB5_bottom - xkB5_toff
    	  	t 
    	    )
    	    (270
    	    	xkB5_boff = round(abs(xkB5_right - xkB5_left)/5)+3
    	     	xkB5_left = xkB5_left + xkB5_boff 	xkB5_top = xkB5_top + xkB5_roff 	
    	    	xkB5_right = xkB5_right + xkB5_toff  	xkB5_bottom = xkB5_bottom + xkB5_loff
    	  	t 
    	    )	    	    
    	);case	    
      )     
     );end if is text    
    );end if is path
    return(list(xkB5_left:xkB5_top xkB5_right:xkB5_bottom))		   
))     

(defun xkB5_text_on_text (text xkB5_item)
(prog ()
(let (xkB5_tt1 xkB5_tt2 xkB5_left xkB5_top xkB5_right xkB5_bottom xkB5_lt xkB5_tp xkB5_rt xkB5_bm )

    xkB5_tt2 = xkB5_getbox(xkB5_item)
    xkB5_lt  = car(nth(0 xkB5_tt2))
    xkB5_tp  = cadr(nth(0 xkB5_tt2))	
    xkB5_rt  = car(nth(1 xkB5_tt2))
    xkB5_bm  = cadr(nth(1 xkB5_tt2))
    
    xkB5_tt1    = xkB5_getbox(text)
    xkB5_left   = car(nth(0 xkB5_tt1))
    xkB5_top    = cadr(nth(0 xkB5_tt1))	
    xkB5_right  = car(nth(1 xkB5_tt1))
    xkB5_bottom = cadr(nth(1 xkB5_tt1))
    
    if(xkB5_lt>=xkB5_left && xkB5_lt<=xkB5_right && xkB5_tp<=xkB5_top && xkB5_tp>=xkB5_bottom return(t) )
    if(xkB5_lt>=xkB5_left && xkB5_lt<=xkB5_right && xkB5_bm<=xkB5_top && xkB5_bm>=xkB5_bottom return(t) )
    if(xkB5_rt>=xkB5_left && xkB5_rt<=xkB5_right && xkB5_bm<=xkB5_top && xkB5_bm>=xkB5_bottom return(t) )
    if(xkB5_rt>=xkB5_left && xkB5_rt<=xkB5_right && xkB5_tp<=xkB5_top && xkB5_tp>=xkB5_bottom return(t) )
	
    return(nil)    
)))

(defun xkB5_unselect_object ()
(let (xkB5_allsel)
    axlSetFindFilter(?enabled '(noall shapes pins vias text lines) ?onButtons '(noall shapes pins vias text lines))

   ; axlSetFindFilter(?enabled '(all) ?onButtons '(all))

    xkB5_allsel = axlGetSelSet(axlAddSelectAll())

    axlClearSelSet()

    axlSetFindFilter(?enabled '(noall symbols) ?onButtons '(noall symbols))

    xkB5_allsel = axlGetSelSet(axlAddSelectAll())

    axlClearSelSet()

))

(defun xkB5_turn_on_layer ( xkB5_layer)
    axlVisibleDesign(nil)
    	
    xkB5_Going_On=axlGetParam("paramLayerGroup:BOARD GEOMETRY/paramLayer:OUTLINE")

    xkB5_Going_On->visible=t

    axlSetParam(xkB5_Going_On)


    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:VIA CLASS/paramLayer:%s" xkB5_layer))

    if(xkB5_layer == "BOTTOM" then
    	xkB5_Going_On->visible=t

    else
    	xkB5_Going_On->visible=nil
    )    
    axlSetParam(xkB5_Going_On)
   

    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:PIN/paramLayer:%s" xkB5_layer))

    xkB5_Going_On->visible=t

    axlSetParam(xkB5_Going_On)
    
    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:PACKAGE GEOMETRY/paramLayer:SILKSCREEN_%s" xkB5_layer))

    xkB5_Going_On->visible=t

    axlSetParam(xkB5_Going_On)  	
    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:REF DES/paramLayer:SILKSCREEN_%s" xkB5_layer))

    xkB5_Going_On->visible=t

    axlSetParam(xkB5_Going_On)


    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:PACKAGE GEOMETRY/paramLayer:PLACE_BOUND_%s" xkB5_layer))

    xkB5_Going_On->visible = xkB5_refdes_component
    axlSetParam(xkB5_Going_On)
    
          ; added by wudezhou 2002/10/15
    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:PACKAGE GEOMETRY/paramLayer:SOLDERMASK_%s" xkB5_layer))

    xkB5_Going_On->visible = t
    axlSetParam(xkB5_Going_On)	    
          ; added by wudezhou 2002/10/15
    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:BOARD GEOMETRY/paramLayer:SOLDERMASK_%s" xkB5_layer))

    xkB5_Going_On->visible = t
    axlSetParam(xkB5_Going_On)	 
          ; added by wudezhou 2002/10/15
    xkB5_Going_On=axlGetParam(sprintf(dummy "paramLayerGroup:BOARD GEOMETRY/paramLayer:SILKSCREEN_%s" xkB5_layer))
    xkB5_Going_On->visible=t
    axlSetParam(xkB5_Going_On)     
    
    axlUIWRedraw(nil)
    axlClearSelSet()

)

(defun xkB5_init_loc_text ()
    xkB5_location = makeTable("loc" 0)
    xkB5_num = 0    
)

(defun xkB5_add_loc_text (xkB5_item)  	; modified by wudezhou at Oct 12,2002
    if(xkB5_item != nil then		;i = 0 i++ item = nthelem(i alltexts)
    	++xkB5_num    	  
    	if(xkB5_item->objType == "text" then
    		xkB5_x = nthelem(1 xkB5_item->xy) 
    		xkB5_y = nthelem(2 xkB5_item->xy)
    		xkB5_location[xkB5_num] = sprintf(dummy "%s,%f,%f" xkB5_item->text xkB5_x xkB5_y)
    	else if(xkB5_item->objType == "path" then
    	        xkB5_x = car(nth(0 xkB5_item->bBox)) 
    		xkB5_y = cadr(nth(0 xkB5_item->bBox)) 
    		xkB5_location[xkB5_num] = sprintf(dummy "%s,%f,%f" xkB5_item->objType xkB5_x xkB5_y)
    		)  	
    	)
    	
    )
)

(defun xkB5_location_text ( xkB5_location)
    xkB5_viewx = 400
    xkB5_viewy = 300

    if(tablep(xkB5_location) == t && length(xkB5_location) > 0 then 
    	if(xkB5_num < length(xkB5_location) then 
    	    ++xkB5_num 
    	else 
    	    xkB5_num = 1
    	)    	     
        xkB5_lst = parseString(xkB5_location[xkB5_num] ",")
    	xkB5_refdes = sprintf(dummy " %d/%d : %s" xkB5_num length(xkB5_location) nthelem(1 xkB5_lst))
    	xkB5_x = atoi(nthelem(2 xkB5_lst))
    	xkB5_y = atoi(nthelem(3 xkB5_lst))
    	;Display the refdes on the interface.
    	axlFormSetField(xkB5_form "next_view" xkB5_refdes)
	axlWindowBoxSet(list(xkB5_x-xkB5_viewx:xkB5_y-xkB5_viewy xkB5_x+xkB5_viewx:xkB5_y+xkB5_viewy))
    )
)
(defun xkB5_location_prv ( xkB5_location)
    xkB5_viewx = 400
    xkB5_viewy = 300

    if(tablep(xkB5_location) == t && length(xkB5_location) > 0 then 
    	if(xkB5_num > 1 then 
    	   --xkB5_num 
    	else 
    	   xkB5_num = length(xkB5_location)
    	)    	     
        xkB5_lst = parseString(xkB5_location[xkB5_num] ",")
    	xkB5_refdes = sprintf(dummy " %d/%d : %s" xkB5_num length(xkB5_location) nthelem(1 xkB5_lst))
    	xkB5_x = atoi(nthelem(2 xkB5_lst))
    	xkB5_y = atoi(nthelem(3 xkB5_lst))
    	;Display the refdes on the interface.
    	axlFormSetField(xkB5_form "next_view" xkB5_refdes)
	axlWindowBoxSet(list(xkB5_x-xkB5_viewx:xkB5_y-xkB5_viewy xkB5_x+xkB5_viewx:xkB5_y+xkB5_viewy))
    )
)
