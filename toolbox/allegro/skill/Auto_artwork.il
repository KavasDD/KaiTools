/* -------------------------------------------------------------------
This skill is use to setup the artworkclass information
-------------------------------------------------------------------*/ 
axlCmdRegister("Autoart" 'Autoart)
procedure(Autoart()
      let(()

			 ;delet the old films
			 delnum = 0
	         oldartlayerlist = car(list(axlGetParam("artwork")->groupMembers)) ;("top" "bottom")
			 oldartlayerlistcount = length(oldartlayerlist)
			 deloldartlayerlist = list()
			 while((oldartlayerlistcount-1 >= delnum)
			 drlid = axlGetParam(strcat("artwork:" nth(delnum oldartlayerlist)))
			 deloldartlayerlist = append1(deloldartlayerlist drlid)
			 delnum = delnum+1
			 )
			 axlDeleteObject(deloldartlayerlist)
			 ;delet done
			 /* -------------------------------------------------------------------
			 list of the films wait for creating 
			 -------------------------------------------------------------------*/ 
			 layerlist = car(list(axlGetParam("paramLayerGroup:ETCH")->groupMembers)) 
             layercont = length(layerlist)
             layertotal = layercont
             num = 0
             namelist = list("01_" "02_" "03_" "04_" "05_" "06_" "07_" "08_" "09_" "10_" "11_" "12_" "13_" "14_" "15_" 
			 "16_" "17_" "18_" "19_" "20_" "21_" "22_" "23_" "24_" "25_" "26_" "27_" "28_" "29_" "30_" "31_" "32_" "33_" "34_" "35_" "36_")
             drilllist = list("1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12 " "13" "14" "15" "16" "17" "18" "19" 
			 "20" "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31" "32" "33" "34" "35" "36")
             drilllayer = strcat("MANUFACTURING/NCLEGEND-1-"  nth(layertotal-1 drilllist))
             drilllayerlist = list("BOARD GEOMETRY/OUTLINE" "BOARD GEOMETRY/DIMENSION" "MANUFACTURING/NCDRILL_LEGEND" "MANUFACTURING/NCDRILL_FIGURE")
             drillname = strcat( "DRILL")
             layercheck = axlIsLayer(drilllayer) 
			 ;DO DRILL work or not
			 if((layercheck == nil)
			then axlUIConfirm("Please NC DRILL First")
			  )
			  
			  
			 ;For all etch layer   
             while((layercont >= 1) 
                     numadd = nth(num namelist)
                     layeradd = list("BOARD GEOMETRY/OUTLINE" strcat("ETCH/",car(layerlist)) 
                                   strcat("VIA CLASS/",car(layerlist)) strcat("PIN/",car(layerlist)))
                     layername = strcat(numadd,car(layerlist))					 
                     Filmcreat(layername layeradd) 
                       layercont = layercont-1
                       layerlist = cdr(layerlist)
                       num = num+1
                   )				   
            ;DRILL   ！！！！！！！！！！with B/B VIA         
             posbdrillist = car(list(axlGetParam("paramLayerGroup:MANUFACTURING")->groupMembers))   

			 posbdrilltotal = length(posbdrillist)
			 numdrl = 0
             while((posbdrilltotal-1 >= numdrl)
			 posbdrillayer = nth(numdrl posbdrillist)
			 if(strncmp("NCLEGEND" posbdrillayer 8) == 0
			   drilllayerlist = append1(drilllayerlist strcat("MANUFACTURING/" posbdrillayer))
			   )
			   numdrl = numdrl+1
			   )
		   Filmcreat(drillname     drilllayerlist)  
           ; PASTEMASK_TOP
           Filmcreat(strcat( "PASTEMASK_TOP") '("BOARD GEOMETRY/OUTLINE" 
												"PIN/PASTEMASK_TOP" 
												"PACKAGE GEOMETRY/PASTEMASK_TOP" ))
           
			; PASTEMASK_BOTTOM
           Filmcreat(strcat( "PASTEMASK_BOTTOM") '("BOARD GEOMETRY/OUTLINE" 
												"PIN/PASTEMASK_BOTTOM" 
												"PACKAGE GEOMETRY/PASTEMASK_BOTTOM" ))
            
			;SOLDERMASK_TOP
           Filmcreat(strcat( "SOLDERMASK_TOP") '("BOARD GEOMETRY/OUTLINE" 
												"PIN/SOLDERMASK_TOP"
												"PACKAGE GEOMETRY/SOLDERMASK_TOP" 
												"BOARD GEOMETRY/SOLDERMASK_TOP" 
												"VIA CLASS/SOLDERMASK_TOP" ))
          
		  ;SOLDERMASK_BOTTOM
           Filmcreat(strcat( "SOLDERMASK_BOTTOM") '("BOARD GEOMETRY/OUTLINE" 
												"PIN/SOLDERMASK_BOTTOM"
												"PACKAGE GEOMETRY/SOLDERMASK_BOTTOM"
												"BOARD GEOMETRY/SOLDERMASK_BOTTOM" 
												"VIA CLASS/SOLDERMASK_BOTTOM" ))
           
		   ;SILKSCREEN_TOP
           Filmcreat(strcat( "SILKSCREEN_TOP")  '("BOARD GEOMETRY/OUTLINE"  
												"REF DES/SILKSCREEN_TOP" 
												"PACKAGE GEOMETRY/SILKSCREEN_TOP" 
												"BOARD GEOMETRY/SILKSCREEN_TOP" ))
           
		   ;SILKSCREEN_BOTTOM
           Filmcreat(strcat( "SILKSCREEN_BOTTOM")  '("BOARD GEOMETRY/OUTLINE"  
												"REF DES/SILKSCREEN_BOTTOM"
												"PACKAGE GEOMETRY/SILKSCREEN_BOTTOM"
												"BOARD GEOMETRY/SILKSCREEN_BOTTOM" ))
           ;ADT
           Filmcreat(strcat( "ADT")  '("BOARD GEOMETRY/OUTLINE"  
												"REF DES/SILKSCREEN_TOP"
												"PIN/TOP"
												"PACKAGE GEOMETRY/SILKSCREEN_TOP"
												"BOARD GEOMETRY/SILKSCREEN_TOP" ))
			
			;ADB
           Filmcreat(strcat( "ADB")  '("BOARD GEOMETRY/OUTLINE"  
												"REF DES/SILKSCREEN_BOTTOM"
												"PIN/BOTTOM"
												"PACKAGE GEOMETRY/SILKSCREEN_BOTTOM"
												"BOARD GEOMETRY/SILKSCREEN_BOTTOM" ))

		  	;ALL
           Filmcreat(strcat( "ALL")  '("BOARD GEOMETRY/OUTLINE"  
												"PACKAGE GEOMETRY/SILKSCREEN_TOP"
												"PACKAGE GEOMETRY/SILKSCREEN_BOTTOM"
												"PIN/TOP"
												"PIN/BOTTOM" ))
           ;user preferrence layer1 
          ;Filmcreat(strcat(nth(layertotal+7 namelist) "user preferrence layer1")  '("BOARD GEOMETRY/OUTLINE"  
          ;                     "REF DES/SILKSCREEN_BOTTOM" "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM" "BOARD GEOMETRY/SILKSCREEN_BOTTOM" ))
		  					
         )
		 )

procedure( Filmcreat(FilmName artList)
      let(()
           axlVisibleDesign(nil)
           foreach( layer artList axlVisibleLayer(layer t)) 
           axlUIWRedraw(nil) 
		   ;need to judge the unit is mils or others???
          (axlDBCreateFilmRec FilmName 0 0 0 6000 100000 1 0 0 0 0 0 1 1)
         )
		 )