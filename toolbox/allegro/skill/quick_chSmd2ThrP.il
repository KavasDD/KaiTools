 
axlCmdRegister("quick_smd2thrp" 'xkC8_quick_chSmd2ThrP )

 
 


  

defun( xkC8_quick_chSmd2ThrP ()
    let( ()
	  xkC8_Dehilightall()	
	   
      xkC8_curdsnunit = axlGetParam("paramDesign")->units
	   

	   
	  xkC8_chSmd2ThrPformcreat()
	  ))
	  
	  
 
	   
	       
		   
	  	   
	  	   
	  	   
		   
	  	   
	  	   
	  	   
		   
		   
	       
defun(xkC8_Dehilightall ()	  	  
	 axlShell("dehilight")
	 axlShell("setwindow form.mini")
	 axlShell("FORM mini dhlt_all")
	 axlShell("setwindow pcb")
	 axlShell("done")
	 )
	  
 
	  
 defun( xkC8_chSmd2ThrPformcreat ()
 let( ()
        xkC8_form_file = "./xkC8_chSmd2ThrP.form"
        xkC8_formc = outfile(xkC8_form_file "w")
        fprintf(xkC8_formc "FILE_TYPE=FORM_DEFN VERSION=2\t\n")
		
        fprintf(xkC8_formc "FORM\t\n")
        fprintf(xkC8_formc "FIXED\t\n")
        fprintf(xkC8_formc "PORT 36 21\t\n")
        fprintf(xkC8_formc "HEADER \"D4\243\272SMD \323\353\315\250\277\327\322\375\275\305\274\344\276\340\274\354\262\351\"\t\n")
        fprintf(xkC8_formc "TILE\t\n")    
		
         
        fprintf(xkC8_formc "FIELD TOP\t\n")
        fprintf(xkC8_formc "FLOC 5 4\t\n")
        fprintf(xkC8_formc "FGROUP \"layer\"\t\n")
        fprintf(xkC8_formc "CHECKLIST \"\266\245\262\343\" \"layer\"\t\n")
        fprintf(xkC8_formc "ENDFIELD\t\n")		
		
        fprintf(xkC8_formc "FIELD BTM\t\n")
        fprintf(xkC8_formc "FLOC 15 4\t\n")
        fprintf(xkC8_formc "FGROUP \"layer\"\t\n")
        fprintf(xkC8_formc "CHECKLIST \"\265\327\262\343\" \"layer\"\t\n")
        fprintf(xkC8_formc "ENDFIELD\t\n")
		
		 
		fprintf(xkC8_formc "\t\n")
		fprintf(xkC8_formc "TEXT \"\274\354\262\351\303\346\"\t\n")
		fprintf(xkC8_formc "TLOC 5 1\t\n")		
		fprintf(xkC8_formc "ENDTEXT\n\t\n")
		
		fprintf(xkC8_formc "\t\n")
		fprintf(xkC8_formc "TEXT \"\327\356\320\241\274\344\276\340\243\250\265\261\307\260\311\350\274\306\265\245\316\273\243\251\"\t\n")
		fprintf(xkC8_formc "TLOC 5 7\t\n")
		 
		fprintf(xkC8_formc "ENDTEXT\n\t\n")	 
		
		
		fprintf(xkC8_formc "TEXT \"\274\344\276\340\"\t\n" ) 
		fprintf(xkC8_formc "TLOC 6 10\t\n")
		fprintf(xkC8_formc "ENDTEXT\t\n")


        fprintf(xkC8_formc,"FIELD clearance\n\t\n")   
        fprintf(xkC8_formc,"FLOC 10 10\t\n")
        fprintf(xkC8_formc,"REALFILLIN 8 12\t\n")	
        fprintf(xkC8_formc,"ENDFIELD\n\t\n")


		fprintf(xkC8_formc "TEXT %L\t\n" xkC8_curdsnunit)  
		fprintf(xkC8_formc "TLOC 20 10\t\n")
		fprintf(xkC8_formc "ENDTEXT\t\n")		
		
		 
        fprintf(xkC8_formc "FIELD next_view\t\n")
        fprintf(xkC8_formc "FLOC 10 13\t\n")
        fprintf(xkC8_formc "STRFILLIN 8 8\t\n")
        fprintf(xkC8_formc "ENDFIELD\t\n")

		
        fprintf(xkC8_formc "FIELD prv_ctl\t\n")
        fprintf(xkC8_formc "FLOC 5 13\t\n")
        fprintf(xkC8_formc "MENUBUTTON \"<<\" 3 3\t\n")
        fprintf(xkC8_formc "ENDFIELD\t\n")
   

        fprintf(xkC8_formc "FIELD next_ctl\t\n")
        fprintf(xkC8_formc "FLOC 21 13\t\n")
        fprintf(xkC8_formc "MENUBUTTON \">>\" 3 3\t\n")
        fprintf(xkC8_formc "ENDFIELD\t\n")
		
		
		 
        fprintf(xkC8_formc "FIELD check\t\n")
        fprintf(xkC8_formc "FLOC 5 16\t\n")
        fprintf(xkC8_formc "MENUBUTTON \"\274\354\262\351\" 8 3\t\n")
        fprintf(xkC8_formc "ENDFIELD\t\n")

        fprintf(xkC8_formc "FIELD exit\t\n")
        fprintf(xkC8_formc "FLOC 17 16\t\n")
        fprintf(xkC8_formc "MENUBUTTON \"\271\330\261\325\" 8 3\t\n") 
        fprintf(xkC8_formc "ENDFIELD\t\n")	
        
		
        fprintf(xkC8_formc "ENDTILE\t\n") 
        fprintf(xkC8_formc "ENDFORM\t\n") 
        close( xkC8_formc)
		
		
		  xkC8_Smd2Tform = axlFormCreate( (gensym) xkC8_form_file `(e inner) 'xkC8_formc_action t)
		  axlFormDisplay(xkC8_Smd2Tform)
		  axlUIWPrint(xkC8_Smd2Tform "D4\243\272\260\264\265\261\307\260\311\350\274\306\265\245\316\273\274\354\262\351") 
		  axlFormSetField(xkC8_Smd2Tform "clearance" axlMKSConvert(120 "mils"))
		  axlFormSetField(xkC8_Smd2Tform "BTM" t)
 xkC8_total=0
 axlFormSetField(xkC8_Smd2Tform "next_view" "0/0")
		  
		  
		   
		  
		  
		  
		  
 
        ))  

 

		
defun( xkC8_formc_action (xkC8_Smd2Tform)
      let( ()
	  case(xkC8_Smd2Tform -> curField
	  
	       ("prv_ctl"
				   axlMsgPut("Location the previous position.")		   
				   axlUIWPrint(xkC8_Smd2Tform "D4\243\272\260\264\265\261\307\260\311\350\274\306\265\245\316\273\274\354\262\351") 
				   xkC8_location_previous()
		            
		   )
		   
	       ("next_ctl"
				   axlMsgPut("Location the next position.")
				   axlUIWPrint(xkC8_Smd2Tform "D4\243\272\260\264\265\261\307\260\311\350\274\306\265\245\316\273\274\354\262\351") 
				   xkC8_location_next()
		           
		   )		   
		   
		   
		   ("check"
		          axlUIWPrint(xkC8_Smd2Tform "D4\243\272\260\264\265\261\307\260\311\350\274\306\265\245\316\273\274\354\262\351") 
				  xkC8_Dehilightall()
				  xkC8_clearance = axlFormGetField(xkC8_Smd2Tform "clearance")
				  xkC8_layert = axlFormGetField(xkC8_Smd2Tform "TOP")
				  xkC8_layerb = axlFormGetField(xkC8_Smd2Tform "BTM")
				  if(or(xkC8_layert xkC8_layerb) == nil
				     then
				     axlUIConfirm("\307\353\317\310\321\241\324\361\274\354\262\351\303\346\241\243")
				     else
					   cond(
					       (xkC8_layert == t xkC8_layer = "TOP")
						   (xkC8_layerb == t xkC8_layer = "BTM")
							)
		               xkC8_check_highl(xkC8_layer)
   	                   axlMsgPut("Cheching the clearance .")
					   xkC8_ref = sprintf(dummy "0/%L" xkC8_total)
					   axlFormSetField(xkC8_Smd2Tform "next_view" xkC8_ref)
                  )					
		   )
		   (("exit" "done" "cancel")
				  axlMsgPut("Thank you for use my skill!")
                  unless(xkC8_Smd2Tform->doneState == 3 axlFormClose(xkC8_Smd2Tform))
				   
                  deleteFile(xkC8_form_file)

                  				  
		   )
	  )
	  ))

	  
defun(xkC8_getsymbBox (xkC8_sym) 
    let( (xkC8_elemlist xkC8_one)
	
	 xkC8_cursymbox=nil
 xkC8_elemlist = xkC8_sym->symbol->children
	 
	 foreach(xkC8_one xkC8_elemlist 
	         if(and(xkC8_one->objType == "shape" or((xkC8_one->layer == "PACKAGE GEOMETRY/PLACE_BOUND_BOTTOM") (xkC8_one->layer == "PACKAGE GEOMETRY/PLACE_BOUND_TOP")))
			    then
			    xkC8_cursymbox = xkC8_one->bBox
			    )
			 )
		or(xkC8_cursymbox xkC8_sym->symbol->bBox)
	 
	 ))     


	 
	  
 

defun(xkC8_getallbBox (xkC8_allsym)
      let( ()
	  
	   

	  xkC8_Toppthsym = list()     
	  xkC8_Topsmdsym2box = list()
      xkC8_Btmsmdsym = list()	
	  
	  xkC8_Btmpthsym = list()     
	  xkC8_Btmsmdsym2box = list()
	  xkC8_Topsmdsym = list()



	  foreach(xkC8_onesym xkC8_allsym
	          xkC8_cursympins = xkC8_onesym -> pins
			  xkC8_cursympin1 = car(xkC8_cursympins)
			  
			if(xkC8_cursympin1 && xkC8_cursympin1->isThrough
			   then
			   if(xkC8_cursympin1 && xkC8_cursympin1->isMirrored
			     then
				 xkC8_Btmpthsym = append1(xkC8_Btmpthsym xkC8_onesym)
				 else
				 xkC8_Toppthsym = append1(xkC8_Toppthsym xkC8_onesym)
				 )
			   else
			   if(xkC8_cursympin1 && xkC8_cursympin1->isMirrored
			     then 
				 xkC8_onesymbox = xkC8_getsymbBox(xkC8_onesym)
				  
				 xkC8_Btmcursmdsym2box = cons(xkC8_onesym xkC8_onesymbox)
				 xkC8_Btmsmdsym2box = append1(xkC8_Btmsmdsym2box xkC8_Btmcursmdsym2box)				 
				 else
				 xkC8_onesymbox = xkC8_getsymbBox(xkC8_onesym)
				  
				 xkC8_Topcursmdsym2box = cons(xkC8_onesym xkC8_onesymbox)
				 xkC8_Topsmdsym2box = append1(xkC8_Topsmdsym2box xkC8_Topcursmdsym2box)
				 )
			   )
	        )
			xkC8_Toppthpin2box = list()          
			xkC8_Btmpthpin2box = list()          
			
	  
	  foreach(xkC8_pthsym xkC8_Toppthsym
	           if( or(strcmp(xkC8_pthsym->name "TP") == 1 strcmp(xkC8_pthsym->name "MARK") == 1 
			       strcmp(xkC8_pthsym->name "ID") == 1 strcmp(xkC8_pthsym->name "REF") == 1 length(xkC8_pthsym->pins) == 1)
			   then
			   remd(xkC8_pthsym xkC8_Toppthsym)
			   else	  
	           xkC8_cursympins = xkC8_pthsym->pins
			   xkC8_curpthpin2box = list()
			   foreach(xkC8_pin xkC8_cursympins
			           xkC8_curpinbox = xkC8_pin->bBox 
					   xkC8_curpin2box = cons(xkC8_pin xkC8_curpinbox)
					   xkC8_curpthpin2box = append1(xkC8_curpthpin2box xkC8_curpin2box)
					   )
			   xkC8_Toppthpin2box = append(xkC8_Toppthpin2box xkC8_curpthpin2box)
			   )
			   )
	  
	  foreach(xkC8_pthsym xkC8_Btmpthsym
	           if( or(strcmp(xkC8_pthsym->name "TP") == 1 strcmp(xkC8_pthsym->name "MARK") == 1 strcmp(xkC8_pthsym->name "ID") == 1 strcmp(xkC8_pthsym->name "REF") == 1 length(xkC8_pthsym->pins) == 1)
			   then
			   remd(xkC8_pthsym xkC8_Btmpthsym)
			   else
	           xkC8_cursympins = xkC8_pthsym->pins
			   xkC8_curpthpin2box = list()
			   foreach(xkC8_pin xkC8_cursympins
			           xkC8_curpinbox = xkC8_pin->bBox 
					   xkC8_curpin2box = cons(xkC8_pin xkC8_curpinbox)
					   xkC8_curpthpin2box = append1(xkC8_curpthpin2box xkC8_curpin2box)
					   )
			   xkC8_Btmpthpin2box = append(xkC8_Btmpthpin2box xkC8_curpthpin2box)
			   )
			   )
	   ))
	   
	   
	 
	
 	   
defun(xkC8_check_highl (xkC8_item)       
      let( ()	
      xkC8_total=0
 xkC8_hlloclist=nil
 xkC8_allsym = setof(component axlDBGetDesign()->components component->pins)  
	  xkC8_getallbBox(xkC8_allsym)
	   
	   
	  if(xkC8_item ==  "TOP" 
		 then xkC8_pin = xkC8_Btmpthpin2box xkC8_sym = xkC8_Topsmdsym2box
		      axlVisibleDesign(nil)
			  axlVisibleLayer("PIN/TOP" t)
			  axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_TOP" t)
			  axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			  axlVisibleLayer("ETCH/TOP" t)
			  axlVisibleLayer("VIA CLASS/TOP" t)
			  axlUIWRedraw(nil)
		 else
			  xkC8_pin = xkC8_Toppthpin2box xkC8_sym = xkC8_Btmsmdsym2box
			  axlVisibleDesign(nil)
			  axlVisibleLayer("PIN/BOTTOM" t)
			  axlVisibleLayer("PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" t)
			  axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
			  axlVisibleLayer("ETCH/BOTTOM" t)
			  axlVisibleLayer("VIA CLASS/BOTTOM" t)	
              axlUIWRedraw(nil)			  
			 )
		   
	  if(or(xkC8_pin xkC8_sym) == nil
	      then 
		  axlUIConfirm("\265\261\307\260\303\346\303\273\323\320\264\375\274\354\262\351\266\324\317\363\241\243")
		  else
		  xkC8_n = 1
		  xkC8_hlloclist = list()
		  xkC8_hlpin2sym = list()
		  
		  xkC8_hlpinlist = list()
		  xkC8_hlsymlist = list()
		    while( (xkC8_n <= length(xkC8_pin))

			    xkC8_curpin = nthelem(xkC8_n xkC8_pin)   
				
				xkC8_curpinhlloclist = list()
				xkC8_curpinl = list()
				
		       foreach(xkC8_onesym xkC8_sym
			          if(
				          xkC8_sym2pthpin(xkC8_curpin xkC8_onesym)		 
				          then
						  axlDBControl('highlightColor 17)
				          axlHighlightObject(car(xkC8_curpin) t)
				          axlHighlightObject(car(xkC8_onesym) t)
						  
						   
						   
						  
						  
					      xkC8_curpinl = append1(xkC8_curpinl list(car(xkC8_curpin) car(xkC8_onesym)))
				          xkC8_curpinhlloclist = append1(xkC8_curpinhlloclist xkC8_curcenter)				  
				          
						  
						  
						  )
			         )
					 
			       xkC8_hlpin2sym = append(xkC8_hlpin2sym xkC8_curpinl)
			       xkC8_hlloclist = append(xkC8_hlloclist xkC8_curpinhlloclist)
			       xkC8_n = xkC8_n+1
			  )
			  
			xkC8_total = length(xkC8_hlloclist)  
		  )

			 
		))

		
	 

	
defun(xkC8_sym2pthpin (xkC8_a xkC8_b)	
      let( ()
	      xkC8_tt1 = cdr(xkC8_a)   
	      xkC8_tt2 = cdr(xkC8_b)    
		  
	      xkC8_left   = car(nth(0 xkC8_tt1))
	      xkC8_bottom    = cadr(nth(0 xkC8_tt1))
	      xkC8_right  = car(nth(1 xkC8_tt1))
	      xkC8_top = cadr(nth(1 xkC8_tt1))
		  

	      xkC8_lt  = car(nth(0 xkC8_tt2))
	      xkC8_bm  = cadr(nth(0 xkC8_tt2))
	      xkC8_rt  = car(nth(1 xkC8_tt2))
	      xkC8_tp  = cadr(nth(1 xkC8_tt2))

            xkC8_casea = and(xkC8_lt-xkC8_clearance>=xkC8_left xkC8_lt-xkC8_clearance<=xkC8_right)
            xkC8_caseb = and(xkC8_bm-xkC8_clearance<=xkC8_top xkC8_bm-xkC8_clearance>=xkC8_bottom)
            xkC8_casec = and(xkC8_tp+xkC8_clearance<=xkC8_top xkC8_tp+xkC8_clearance>=xkC8_bottom)
            xkC8_cased = and(xkC8_rt+xkC8_clearance>=xkC8_left xkC8_rt+xkC8_clearance<=xkC8_right)
			
			xkC8_casee = and(xkC8_lt-xkC8_clearance<=xkC8_left xkC8_rt+xkC8_clearance>=xkC8_right)
			xkC8_casef = and(xkC8_tp+xkC8_clearance>=xkC8_top xkC8_bm-xkC8_clearance<=xkC8_bottom)
			
			xkC8_caseg = and(xkC8_lt-xkC8_clearance<=xkC8_left xkC8_rt+xkC8_clearance>=xkC8_right xkC8_tp+xkC8_clearance>=xkC8_top xkC8_bm-xkC8_clearance<=xkC8_bottom)
			xkC8_caseh = and(xkC8_lt-xkC8_clearance>=xkC8_left xkC8_rt+xkC8_clearance<=xkC8_right xkC8_tp+xkC8_clearance<=xkC8_top xkC8_bm-xkC8_clearance>=xkC8_bottom)
			
			xkC8_result = or(and(xkC8_casea xkC8_caseb) and(xkC8_casea xkC8_casec) and(xkC8_cased xkC8_caseb) and(xkC8_cased xkC8_casec) and(xkC8_caseb xkC8_casee) and(xkC8_casec xkC8_casee) and(xkC8_casea xkC8_casef) and(xkC8_cased xkC8_casef) xkC8_caseg xkC8_caseh)
         if(xkC8_result
		   then
		   xkC8_curcenter = list((max(xkC8_rt xkC8_right xkC8_lt xkC8_left)+ min(xkC8_rt xkC8_right xkC8_lt xkC8_left))*0.5 (max(xkC8_tp xkC8_top xkC8_bm xkC8_bottom)+min(xkC8_tp xkC8_top xkC8_bm xkC8_bottom))*0.5)
		   
            )
	  ))
	  

 

	   
 

defun(xkC8_location_next ()
   let( (xkC8_curlocnum)
	  if(xkC8_total ==0
	     then
		 axlUIConfirm("\265\261\307\260\303\346\303\273\323\320\274\354\262\351\275\341\271\373\241\243")
		 else
	    xkC8_curlocnum = atoi(car(parseString(axlFormGetField(xkC8_Smd2Tform "next_view") "/")))
		if(xkC8_curlocnum == xkC8_total
		   then xkC8_curlocnum = 1
		   else
		   xkC8_curlocnum = xkC8_curlocnum+1
		  )
    	xkC8_refdes = sprintf(dummy " %d/%d" xkC8_curlocnum xkC8_total)
		xkC8_x = car(nthelem(xkC8_curlocnum xkC8_hlloclist))
		xkC8_y = cadr(nthelem(xkC8_curlocnum xkC8_hlloclist))
    	axlFormSetField(xkC8_Smd2Tform "next_view" xkC8_refdes)
	    axlWindowBoxSet(list((xkC8_x-axlMKSConvert(400 "mils")):(xkC8_y-axlMKSConvert(320 "mils")) (xkC8_x+axlMKSConvert(400 "mils")):(xkC8_y+axlMKSConvert(320 "mils"))))

      )
	 )
	)


	
 	

defun(xkC8_location_previous ()
   let( (xkC8_curlocnum)
	  if(xkC8_total ==0
	     then
		 axlUIConfirm("\265\261\307\260\303\346\303\273\323\320\274\354\262\351\275\341\271\373\241\243")
		 else	
	    xkC8_curlocnum = atoi(car(parseString(axlFormGetField(xkC8_Smd2Tform "next_view") "/")))
		
		if(or(xkC8_curlocnum == 1 xkC8_curlocnum == 0)
		   then xkC8_curlocnum = xkC8_total
		   else
		   xkC8_curlocnum = xkC8_curlocnum-1   
		  )
      	xkC8_refdes = sprintf(dummy " %d/%d" xkC8_curlocnum xkC8_total)
		xkC8_x = car(nthelem(xkC8_curlocnum xkC8_hlloclist))
		xkC8_y = cadr(nthelem(xkC8_curlocnum xkC8_hlloclist))
    	axlFormSetField(xkC8_Smd2Tform "next_view" xkC8_refdes)
	    axlWindowBoxSet(list((xkC8_x-axlMKSConvert(400 "mils")):(xkC8_y-axlMKSConvert(320 "mils")) (xkC8_x+axlMKSConvert(400 "mils")):(xkC8_y+axlMKSConvert(320 "mils"))))

      )
	 )
	)  