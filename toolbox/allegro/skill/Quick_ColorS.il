/* 
├─ 
│ ├─        程序名称： Quick_ColorS
│ ├─        程序功能：快速设置颜色
│ ├─        创建时间：2013年12月16日 
│ ├─        作    者：王凯
├─ 

*/ 


;load("Quick_ColorS.il")



axlCmdRegister("quick_colorset" 'Quick_ColorSet)


;the Color define

;white   =  '(255 255 255)  
;blank   =  '(0 0 0)
;darkred =  '(169 5 18)
;lightred=  '(255 0 0)
;green   =  '(0 221 0)
;blue    =  '(18 18 225)
;qingse  =  '(0 255 255)
;zise    =  '(255 0 255)





defun( Quick_ColorSet ()

	axlColorSet('all '(	(14 210 255) (255 0 0) (231 32 236) (0 181 77) (166 16 255) (2 39 249) (180 97 140) (215 215 62) 
						(190 192 233) (5 148 123) (179 179 185) (70 168 102) (222 168 3) (255 178 255) (124 171 186) (67 134 188) 
						(215 0 253) (181 145 0) (147 166 166) (227 98 66) (191 0 191) (215 0 107) (0 255 0) (131 131 131) 
						(156 134 114) (202 133 106) (252 78 90) (239 155 63) (215 215 0) (129 180 78) (0 221 0) (0 215 155)
						(240, 240, 0) (189 66 255) (255 51 153) (217 217 217) (185 241 255) (233 191 255) (255 176 216) (189 255 189)
						(202 189 170) (130 130 255) (117 255 217) (189 255 189) (151 203 255) (0 64 64) (0 128 0) (128 128 0)  )
				)
	



      etchcolorslist = list(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 )
	  Quick_ColorSetTr()

	  


	  )


    

defun( Quick_ColorSetTr ()
let(()

;Get all the etch/pin/via/boundary/antietch layers    etchcolorslist
etchl = axlGetParam("paramLayerGroup:ETCH")->groupMembers
etchlayers = append(list("BOTTOM") reverse(cdr(reverse(etchl))))
etchlnum = length(etchlayers)



;Get all the DRC layers   17
drclayers = axlGetParam("paramLayerGroup:Drc Error Class")->groupMembers
;Get all the Via layers   66
vialayers = axlGetParam("paramLayerGroup:Via Class")->groupMembers
;Get all the boundary layers 9
boundarylayers = axlGetParam("paramLayerGroup:Boundary")->groupMembers
;Get all the antietch layers 22
antietchlayers = axlGetParam("paramLayerGroup:Anti Etch")->groupMembers

regionlayers = axlGetParam("paramLayerGroup:Constraint Region")->groupMembers

viaoutlayers = axlGetParam("paramLayerGroup:Via Keepout")->groupMembers

rtoutlayers = axlGetParam("paramLayerGroup:Route Keepout")->groupMembers



/* ---------------------------------
change the pins colors
--------------------------------- */
             i = 0
		 while(i < etchlnum
		     cursetlayer = nth(i etchlayers)
			 cursetpinyer = sprintf(nil "PIN/%s" cursetlayer)
			 
			 setcolor = nth(i etchcolorslist)			 
			 crucolor = axlLayerGet(cursetpinyer)
		     crucolor->color=setcolor
			 axlLayerSet(crucolor)
			 axlVisibleUpdate(t)
			 i++
			 )
/* ---------------------------------
change the etch colors
--------------------------------- */
             i = 0			 
		 while(i < etchlnum
		     cursetlayer = nth(i etchlayers)
			 cursetetchlayer = sprintf(nil "ETCH/%s" cursetlayer)
			 setcolor = nth(i etchcolorslist)			 
			 crucolor = axlLayerGet(cursetetchlayer)
		     crucolor->color=setcolor
			 axlLayerSet(crucolor)
			 axlVisibleUpdate(t)
			 i++
			 )
/* ---------------------------------
Drc error class
--------------------------------- */
         foreach(one drclayers	
                  curdrc = 	sprintf(nil "Drc Error Class/%s" one)
                  curdrccolor = axlLayerGet(curdrc)
				  curdrccolor->color=33
			      axlLayerSet(curdrccolor)
			      axlVisibleUpdate(t)	
                )				  
 /* ---------------------------------
Via  class
--------------------------------- */                  				  
         foreach(one vialayers	
                  curvia = 	sprintf(nil "Via Class/%s" one)
                  curviacolor = axlLayerGet(curvia)
				  curviacolor->color=11
			      axlLayerSet(curviacolor)
			      axlVisibleUpdate(t)	
                )				 
 /* ---------------------------------
Boundary
--------------------------------- */                  				  
         foreach(one boundarylayers	
                  curbun = 	sprintf(nil "Boundary/%s" one)
                  curbuncolor = axlLayerGet(curbun)
				  curbuncolor->color=42
			      axlLayerSet(curbuncolor)
			      axlVisibleUpdate(t)	
                )	
/* ---------------------------------
Anti
--------------------------------- */				
         foreach(one antietchlayers	
                  curant = 	sprintf(nil "Anti Etch/%s" one)
                  curantcolor = axlLayerGet(curant)
				  curantcolor->color=14
			      axlLayerSet(curantcolor)
			      axlVisibleUpdate(t)	
                )	

/* ---------------------------------
region
--------------------------------- */				
         foreach(one regionlayers	
                  curant = 	sprintf(nil "Constraint Region/%s" one)
                  curantcolor = axlLayerGet(curant)
				  curantcolor->color=21
			      axlLayerSet(curantcolor)
			      axlVisibleUpdate(t)	
                )

/* ---------------------------------
via keep out
--------------------------------- */				
         foreach(one viaoutlayers	
                  curant = 	sprintf(nil "Via Keepout/%s" one)
                  curantcolor = axlLayerGet(curant)
				  curantcolor->color=29
			      axlLayerSet(curantcolor)
			      axlVisibleUpdate(t)	
                )

/* ---------------------------------
route keepout
--------------------------------- */				
         foreach(one rtoutlayers	
                  curant = 	sprintf(nil "Route Keepout/%s" one)
                  curantcolor = axlLayerGet(curant)
				  curantcolor->color=13
			      axlLayerSet(curantcolor)
			      axlVisibleUpdate(t)	
                )







				
/* ---------------------------------
change other colors
--------------------------------- */					
				
	            q1=axlLayerGet("PACKAGE GEOMETRY/SILKSCREEN_TOP")
	            q1->color=36
	          	axlLayerSet(q1)
				
	            q2=axlLayerGet("PACKAGE GEOMETRY/SILKSCREEN_BOTTOM")
	            q2->color=20
	            axlLayerSet(q2)

	            q3=axlLayerGet("PACKAGE GEOMETRY/ASSEMBLY_TOP")
	            q3->color=29
	          	axlLayerSet(q3)
				
	            q4=axlLayerGet("PACKAGE GEOMETRY/ASSEMBLY_BOTTOM")
	            q4->color=7
	            axlLayerSet(q4)
				
	            q5=axlLayerGet("PACKAGE GEOMETRY/PLACE_BOUND_TOP")
	            q5->color=16
	            axlLayerSet(q5)				
				
	            q6=axlLayerGet("BOARD GEOMETRY/SILKSCREEN_TOP")
	            q6->color=39
	            axlLayerSet(q6)
				
	            q7=axlLayerGet("BOARD GEOMETRY/SILKSCREEN_BOTTOM")
	            q7->color=29
	            axlLayerSet(q7)
				
	            q8=axlLayerGet("BOARD GEOMETRY/OUTLINE")
	            q8->color=36
	           	axlLayerSet(q8)
				
                q9=axlLayerGet("REF DES/SILKSCREEN_TOP")
	            q9->color=36
	          	axlLayerSet(q9)
				
	            q10=axlLayerGet("REF DES/SILKSCREEN_BOTTOM")
	            q10->color=20
	            axlLayerSet(q10)
				
                q11=axlLayerGet("REF DES/ASSEMBLY_TOP")
	            q11->color=37
	          	axlLayerSet(q11)
				
	            q12=axlLayerGet("REF DES/ASSEMBLY_BOTTOM")
	            q12->color=18
	            axlLayerSet(q12)				
				
				
                q13=axlLayerGet("COMPONENT VALUE/ASSEMBLY_TOP")
	            q13->color=1
	          	axlLayerSet(q13)
				
				q14=axlLayerGet("COMPONENT VALUE/SILKSCREEN_TOP")
	            q14->color=1
	          	axlLayerSet(q14)		
				
	            q15=axlLayerGet("COMPONENT VALUE/ASSEMBLY_BOTTOM")
	            q15->color=8
	            axlLayerSet(q15)

	            q16=axlLayerGet("COMPONENT VALUE/SILKSCREEN_BOTTOM")
	            q16->color=8
	            axlLayerSet(q16)				
				
                q17=axlLayerGet("PIN/SOLDERMASK_TOP")
	            q17->color=23
	          	axlLayerSet(q17)
				
				q18=axlLayerGet("PIN/SOLDERMASK_BOTTOM")
	            q18->color=3
	          	axlLayerSet(q18)		
				
	            q19=axlLayerGet("PIN/PASTEMASK_BOTTOM")
	            q19->color=7
	            axlLayerSet(q19)

	            q20=axlLayerGet("PIN/PASTEMASK_BOTTOM")
	            q20->color=18
	            axlLayerSet(q20)	

                q21=axlLayerGet("PACKAGE GEOMETRY/SOLDERMASK_TOP")
	            q21->color=23
	          	axlLayerSet(q21)
				
				q22=axlLayerGet("PACKAGE GEOMETRY/SOLDERMASK_BOTTOM")
	            q22->color=3
	          	axlLayerSet(q22)		
				
	            q23=axlLayerGet("PACKAGE GEOMETRY/PASTEMASK_BOTTOM")
	            q23->color=7
	            axlLayerSet(q23)

	            q24=axlLayerGet("PACKAGE GEOMETRY/PASTEMASK_BOTTOM")
	            q24->color=18
	            axlLayerSet(q24)

                q25=axlLayerGet("BOARD GEOMETRY/SOLDERMASK_TOP")
	            q25->color=23
	          	axlLayerSet(q25)
				
				q26=axlLayerGet("BOARD GEOMETRY/SOLDERMASK_BOTTOM")
	            q26->color=3
	          	axlLayerSet(q26)	
				
				
				q27=axlLayerGet("ROUTE KEEPIN/ALL")
                q27->color=17
                axlLayerSet(q27)
				
	            q28=axlLayerGet("PACKAGE GEOMETRY/PIN_NUMBER")
	            q28->color=36
	            axlLayerSet(q28)				
				
				
	            axlVisibleUpdate(t)
; /* ---------------------------------
; change other colors 2rd solution
; --------------------------------- */	 
; otherlayerlist = '("PACKAGE GEOMETRY/SILKSCREEN_TOP" "BOARD GEOMETRY/SILKSCREEN_TOP" "REF DES/SILKSCREEN_TOP" 
                   ; "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" "BOARD GEOMETRY/SILKSCREEN_BOTTOM""REF DES/SILKSCREEN_BOTTOM" 
				   ; "BOARD GEOMETRY/OUTLINE" "ROUTE KEEPIN/ALL" 
				   
				   
				   
				   ; )


				   
	  
	  ))
	  
	  
	  
	  
	  
; load("Quick_ColorS.il")	  
	  

	  
	  