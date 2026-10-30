;*****************************************************************************************
; File name: fTextTuneTools.il
; Description : 調整文字於合適的外框內
; Date : APR 16 2014
; By Sean Hung
; How To Load: Command>skill load("fTextTuneTools.il")
; How To Execute: Command>tt
;*****************************************************************************************
axlCmdRegister("tt" 'fnTextTuneTools ?cmdType "interactive" ?doneCmd 'fnTTPopupDone ?cancelCmd 'fnTTPopupCancel)

;axlCmdRegister("tt" 'fnTextTuneTools ?cmdType "general")
;axlCmdRegister("tt run" 'fnTTStart ?cmdType "interactive")
procedure(fnTextTuneTools()
	prog((tVersion tCompanyName frmTT)
		tVersion = strcat("/" ":" "A" "a" "B" "b" "C" "c" "d" "e" "S" "E" "P" "f" "g" "h" "i" "j" "k" "L" "l" "m" "N" "n" "o" "p" "Q" "q" "r" "S" "s" "T" "t" "u" "v" "W" "w" "x" "y" "z" "0" "1" "2" "3" "4" "5" "6" "7" "8" "9")
		tVersion = strcat("V" "1" "." "6" "0")
		
		;@@@@@ Define SubFunction area 定義本地函數 @@@@@@@@@@@@@@@@@@@@@@@@@@@
		procedure(fnTTFormBuild() 
			let((tTTFormFile xMaxTextBlock pTTForm frmTT xX xY tS0 tS1 tS2 tS3 tS4 tS5 tS6 tS7 tS8 tS9 
				tS10 tS11 tS12 tS13 tS14 tS15 tS16 tS17 tS18 tS19 tS20 tS21 tS22 tS23 tS24 tS25 tS26 tS27 tS28 tS29
				tS30 tS31 tS32 tS33 tS34 tS35 tS36 tS37 tS38 tS39 tS40 tS41 tS42 tS43 tS44 tS45 tS46 tS47 tS48 tS49 
				tS50 tS51 tS52 tS53 tS54 tS55 tS56 tS57 tS58 tS59) 
				drain()
				;setShellEnvVar("LANG=ENG")
				LAN = nil
				case(LAN
					/*( BIG5
						tS0 = "\276\314\303\322\246W\272\331"	;憑證名稱
						tS1 = "\245D\265{\246\241"				;主程式
						tS2 = "\244\345\246r\274h\263]\251w"	;文字層設定
						tS3 = "\244\345\246r\246W\272\331"		;文字名稱
						tS4 = "\274h\255\261\246W\272\331" 		;層面名稱
						tS5 = "\245~\256\330\270\352\256\306"	;外框資料
						tS6 = "\305\343\245\334\263\273\274h"		;顯示頂層
						tS7 = "\305\343\245\334\251\263\274h"	;顯示底層
						tS8 = "\251\263\274h\271s\245\363\263]\251w"	;底層零件設定
						tS9 = "\244\345\246r\303\350\271\263"		;文字鏡像
						tS10 = "\260\365\246\346\274\322\246\241\263]\251w"		;執行模式設定
						tS11 = "\261\333\302\340\244\345\246r"	;旋轉文字
						tS12 = "\244\345\246r\262\276\260\312\250\354\244\244\244\337"				;文字移動到中心
						tS13 = "X\266b\266Z\302\367"			;X軸距離
						tS14 = "Y\266b\266Z\302\367"			;Y軸距離
						tS15 = "\246X\276A\244\345\246r"		;合適文字
						tS16 = "\247\357\305\334\244\345\246r\275s\270\271"	;改變文字編號
						tS17 = "\305\343\245\334\244\345\246r\275s\270\271" ;顯示文字編號
						tS20 = "\274\322\246\241\266i\266\245\263]\251w"		;模式進階設定
						tS21 = "\261\333\302\340\244\345\246r\277\357\266\265"	;旋轉文字選項
						tS22 = "\244\345\246r\252\272\244\350\246V\250\244\253\327"	;文字的方向角度
						tS23 = "\263\273\274h\244\364\245\255\244\350\246V"	;頂層水平方向
						tS24 = "\253\327"						;度
						tS25 = "\263\273\274h\253\253\252\275\244\350\246V"	;頂層垂直方向
						tS26 = "\251\263\274h\244\364\245\255\244\350\246V"	;底層水平方向
						tS27 = "\251\263\274h\253\253\252\275\244\350\246V"	;底層垂直方向
						tS28 = "\261j\255\242\247\357\305\334\250\244\253\327"	;強迫改變角度
						tS29 = "\251M\271s\245\363\244@\274\313\252\272\250\244\253\327"	;和零件一樣的角度 ;計算基礎的文字角度
						tS30 = "\244\345\246r\244\244\244\337\277\357\266\265"	;文字中心選項
						tS31 = "\256\325\245\277\260\276\262\276\255\310"	;校正偏移值
						tS32 = "\246X\276A/\247\357\305\334\244\345\246r\277\357\266\265"	;合適/改變文字選項
						tS33 = "\253\374\251w\260\252\253\327"	;指定高度
						tS34 = "\263\314\244p\255\310"	;最小值
						tS35 = "\263\314\244j\255\310"	;最大值
						tS36 = "\253\374\251w\244\345\246r\275s\270\271"	;指定文字編號
						tS37 = "\245~\256\330\273P\244\345\246r\303\344\275t\266\241\266Z"	;外框與文字邊緣間距
						tS40 = "\260\365\246\346"		;執行
						tS41 = "\265\262\247\364"		;結束
						tS50 = "\303B\245~\277\357\266\265"			;額外選項
						tS51 = "\265\262\247\364\253\341,\305\343\245\334\260\365\246\346\246\271\244u\250\343\253e\252\272\265e\255\261"			;結束後,顯示執行此工具前的畫面
						tS52 = "\255\327\247\357\244\345\246r\275s\270\271\277\357\266\265"	;修改文字編號選項
						tS53 = "\244\345\246r\275s\270\271"				;文字編號
						tS54 = "\244\345\246r\274e\253\327"					;文字寬度
						tS55 = "\244\345\246r\260\252\253\327"					;文字高度
						tS56 = "\246\346\273P\246\346\252\272\266\241\266Z" ;行與行的間距
						tS57 = "\251\263\244\371\275u\274e" ;底片線寬
						tS58 = "\246r\273P\246r\252\272\266\241\266Z" ;字與字的間距
					)*/
					
					( nil
						tS0 = "\306\276\326\244\303\373\263\306"	;憑證名稱
						tS1 = "\326\367\263\314\320\362"				;主程式
						tS2 = "\316\304\327\326\262\343\311\350\266\250"	;文字層設定
						tS3 = "\316\304\327\326\303\373\263\306"		;文字名稱
						tS4 = "\262\343\303\346\303\373\263\306" 		;?面名?
						tS5 = "\315\342\277\362\327\312\301\317"	;外框?料
						tS6 = "\317\324\312\276\266\245\262\343"		;?示??
						tS7 = "\317\324\312\276\265\327\262\343"	;?示底?
						tS8 = "\265\327\262\343\301\343\274\376\311\350\266\250"	;底?零件?定
						tS9 = "\316\304\327\326\276\265\317\361"		;文字?像
						tS10 = "\326\264\320\320\304\243\312\275\311\350\266\250"		;?行模式?定
						tS11 = "\320\375\327\252\316\304\327\326" 	;旋?文字
						tS12 = "\316\304\327\326\322\306\266\257\265\275\326\320\320\304"				;文字移?到中心
						tS13 = "X\326\341\276\340\300\353"			;X?距离
						tS14 = "Y\326\341\276\340\300\353"			;Y?距离
						tS15 = "\272\317\312\312\316\304\327\326"		;合适文字
						tS16 = "\320\336\270\304\327\326\272\305\264\363\320\241"	;修改字?大小
						tS17 = "\317\324\312\276\327\326\272\305\264\363\320\241" 	;?示字?大小
						tS20 = "\304\243\312\275\275\370\275\327\311\350\266\250"		;模式???定
						tS21 = "\320\375\327\252\316\304\327\326\321\241\317\356"	;旋?文字??
						tS22 = "\316\304\327\326\265\304\267\275\317\362\275\307\266\310"	;文字的方向角度
						tS23 = "\266\245\262\343\313\256\306\275\267\275\317\362"	;??水平方向
						tS24 = "\266\310"						;度
						tS25 = "\266\245\262\343\264\271\326\261\267\275\317\362"	; ??垂直方向
						tS26 = "\265\327\262\343\313\256\306\275\267\275\317\362"	;底?水平方向
						tS27 = "\265\327\262\343\264\271\326\261\267\275\317\362"	;底?垂直方向
						tS28 = "\307\277\306\310\270\304\261\344\275\307\266\310"	;?迫改?角度
						tS29 = "\272\315\301\343\274\376\322\273\321\371\265\304\275\307\266\310"	;和零件一?的角度 ;?算基?的文字角度
						tS30 = "\316\304\327\326\326\320\320\304\321\241\317\356"	;文字中心??
						tS31 = "\320\243\325\375\306\253\322\306\326\265"	;校正偏移值
						tS32 = "\272\317\312\312/\320\336\270\304\316\304\327\326\321\241\317\356"	;合适/修改文字??
						tS33 = "\326\270\266\250\270\337\266\310"	;指定高度
						tS34 = "\327\356\320\241\326\265"	;最小值
						tS35 = "\327\356\264\363\326\265"	;最大值
						tS36 = "\326\270\266\250\327\326\272\305\264\363\320\241"	;指定字?大小
						tS37 = "\315\342\277\362\323\353\316\304\327\326\261\337\324\265\274\344\276\340"	;外框与文字???距
						tS40 = "\326\264\320\320"		;?行
						tS41 = "\275\341\312\370"		;?束
						tS50 = "\266\356\315\342\321\241\317\356"			;?外??
						tS51 = "\275\341\312\370\272\363,\317\324\312\276\326\264\320\320\264\313\271\244\276\337\307\260\265\304\273\255\303\346"			; ?束后,?示?行此工具前的?面
						tS52 = "\320\336\270\304\327\326\314\345\261\340\272\305\321\241\317\356"	;修改字体????
						tS53 = "\327\326\314\345\261\340\272\305"				;字体??
						tS54 = "\327\326\314\345\277\355\266\310"					; 字体?度
						tS55 = "\327\326\314\345\270\337\266\310"					; 字体高度
						tS56 = "\320\320\323\353\320\320\265\304\274\344\276\340" ;行与行的?距
						tS57 = "\265\327\306\254\317\337\277\355" ;底片??
						tS58 = "\327\326\323\353\327\326\265\304\274\344\276\340" ;字与字的?距
					)
					
					
					
					(t
						tS0 = "Licensed for"
						tS1 = "Main"
						tS2 = "Objects"
						tS3 = "Label name"
						tS4 = "Label layer"
						tS5 = "Outline data"
						tS6 = "Top Side"
						tS7 = "Bottom Side"
						tS8 = "Components on bottom side"
						tS9 = "Label mirrored"
						tS10 = "Mode"
						tS11 = "Rotate Text"
						tS12 = "Center Text"
						tS13 = "Dx"
						tS14 = "Dy"
						tS15 = "Fit Text"
						tS16 = "Modify TextBlk"
						tS17 = "Display TextBlk"
						tS20 = "Advanced"
						tS21 = "Text rotation"
						tS22 = "Calculate longest side"
						tS23 = "TOP horizontal:"
						tS24 = "deg"
						tS25 = "TOP vertical:"
						tS26 = "BOTTOM horizontal:"
						tS27 = "BOTTOM vertical:"
						tS28 = "Force angle"
						tS29 = "Calculate based on label angle (symdef)"
						tS30 = "Text center"
						tS31 = "Offset correction:"
						tS32 = "Text fit / modify"
						tS33 = "Specify by height"
						tS34 = "Min"
						tS35 = "Max"
						tS36 = "Specify by block"
						tS37 = "Clearance to boundary:"
						tS40 = "Execute"
						tS41 = "Exit"
						tS50 = "Option"
						tS51 = "Restore View"
						tS52 = "Change TextBlk Value"
						tS53 = "Text Block"
						tS54 = "Width"
						tS55 = "Height"
						tS56 = "Line Space"
						tS57 = "Photo Width"
						tS58 = "Char Space"
					)
				)
				
				
				xAccuracy = cadr(axlDBGetDesignUnits())
				xMaxTextBlock = axlDBControl('maxTextBlock)
				tTTFormFile = axlTempFile()
				pTTForm = outfile(tTTFormFile)
				fprintf(pTTForm "FILE_TYPE=FORM_DEFN VERSION=2\n") 
				fprintf(pTTForm "FORM\n") 
				fprintf(pTTForm "FIXED\n")
				fprintf(pTTForm "PORT 36 50\n") 
				fprintf(pTTForm "HEADER \"Text Tune Tools\"\n")
				
				fprintf(pTTForm "POPUP <outline_layer_popup> \"1\" \"1\",\"2\" \"2\".\n") 
				fprintf(pTTForm "POPUP <label_name_popup> \"Refdes\" \"refdes\",\"Value\" \"value\",\"Part Number\" \"part_number\",\"Device Type\" \"device_type\",\"Tolerance\" \"tolerance\",\"Package Geo\" \"package_geo1\".\n") 
				fprintf(pTTForm "POPUP <label_layer_popup> \"1\" \"1\",\"2\" \"2\".\n")
				fprintf(pTTForm "POPUP <force_angle_popup> \"0\" \"0\",\"90\" \"90\",\"180\" \"180\",\"270\" \"270\".\n") 
				fprintf(pTTForm "POPUP <horizontal_popup> \"0\" \"0\",\"180\" \"180\".\n") 
				fprintf(pTTForm "POPUP <vertical_popup> \"90\" \"90\",\"270\" \"270\".\n") 
				fprintf(pTTForm "\n") 
				fprintf(pTTForm "TILE\n")
				xX = 1
				xY = 0
				fprintf(pTTForm "GROUP \"%s\"\n" tS0)
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 34 4\n") 
				fprintf(pTTForm "ENDGROUP\n\n")
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "TEXT\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "INFO F_lblCopyright 21\n")
				fprintf(pTTForm "OPTIONS BOLD\n")
				fprintf(pTTForm "ENDTEXT\n")
				;%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				xX = 1
				xY = xY + 3
				fprintf(pTTForm "TABSET \"tab\"\n")
				fprintf(pTTForm "OPTIONS tabsetDispatch\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 35 45\n")
				;===============================================================
				xX = 1
				xY = 0
				fprintf(pTTForm "TAB \"%s\"\n" tS1) 
				fprintf(pTTForm "GROUP \"%s\"\n" tS2) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 32 16\n")
				fprintf(pTTForm "ENDGROUP\n")
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS3) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 12
				fprintf(pTTForm "FIELD F_popLabelName\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 15\n") 
				fprintf(pTTForm "POP \"label_name_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 3
				fprintf(pTTForm "TEXT \"%s\"\n" tS4)
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 12
				fprintf(pTTForm "FIELD F_popLabelLayer\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 15\n")
				fprintf(pTTForm "POP \"label_layer_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 3
				fprintf(pTTForm "TEXT \"%s\"\n" tS5) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 12
				fprintf(pTTForm "FIELD F_popOutlineLayer\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 15\n") 
				fprintf(pTTForm "POP \"outline_layer_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 3
				;設定為動態的Color
				fprintf(pTTForm "FIELD F_clrTop\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "COLOR 3 1\n")
				;fprintf(pTTForm "OPTIONS colorchooser")
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 4
				fprintf(pTTForm "TEXT \"%s\"\n" tS6)
				fprintf(pTTForm "TLOC %d %d\n" xX (xY + 1))
				fprintf(pTTForm "ENDTEXT\n\n")
				xX = xX + 10
				fprintf(pTTForm "FIELD F_clrBottom\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "COLOR 3 1\n")
				;fprintf(pTTForm "OPTIONS colorchooser")
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 4
				fprintf(pTTForm "TEXT \"%s\"\n" tS7)
				fprintf(pTTForm "TLOC %d %d\n" xX (xY + 1))
				fprintf(pTTForm "ENDTEXT\n\n")
				
				xX = 1
				xY = xY + 5
				fprintf(pTTForm "GROUP \"%s\"\n" tS8) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 32 6\n") 
				fprintf(pTTForm "ENDGROUP\n")
				xX = xX + 1
				xY = xY + 3
				;fprintf(pTTForm "FIELD F_rdoMirrorBottomOnly\n")
				fprintf(pTTForm "FIELD F_chkMirrorBottomOnly\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\"\n" tS9) 
				fprintf(pTTForm "ENDFIELD\n")
				;xY = xY + 3
				;fprintf(pTTForm "FIELD F_rdoNoMirror\n") 
				;fprintf(pTTForm "FLOC %d %d\n" xX xY)
				;fprintf(pTTForm "CHECKLIST \"Label not mirrored\" \"tm\" \n") 
				;fprintf(pTTForm "ENDFIELD\n")
				xX = 1
				xY = xY + 3
				fprintf(pTTForm "GROUP \"%s\"\n" tS10) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 32 17\n")
				fprintf(pTTForm "ENDGROUP\n")
				xX = xX + 1
				xY = xY + 3
				fprintf(pTTForm "FIELD	F_ckbRotateText\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\"\n" tS11) 
				fprintf(pTTForm "ENDFIELD\n")
				xY = xY + 2
				fprintf(pTTForm "FIELD F_ckbCenterText\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\"\n" tS12) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 2
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS13)
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 7
				fprintf(pTTForm "FIELD F_iptDx\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 5 10\n")
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX - 7
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS14) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 7
				fprintf(pTTForm "FIELD F_iptDy\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 5 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "FIELD F_ckbFitText\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\"\n" tS15) 
				fprintf(pTTForm "ENDFIELD\n")
				xY = xY + 2
				fprintf(pTTForm "FIELD F_ckbModifyTextBlk\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\"\n" tS16)
				fprintf(pTTForm "ENDFIELD\n")
				xY = xY + 2
				fprintf(pTTForm "FIELD F_ckbDisplayTextBlk\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\"\n" tS17)
				fprintf(pTTForm "ENDFIELD\n")
				fprintf(pTTForm "ENDTAB\n")
				;===============================================================
				xX = 1
				xY = 0
				fprintf(pTTForm "TAB \"%s\"\n" tS20) 
				fprintf(pTTForm "GROUP \"%s\"\n" tS21) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 32 17\n") 
				fprintf(pTTForm "ENDGROUP\n")
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "FIELD  F_rdoTextRotationLongSide\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\" \"rot\"\n" tS22) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 2
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS23)
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 16
				fprintf(pTTForm "FIELD F_popTopLongSideX\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 4\n")
				fprintf(pTTForm "POP \"horizontal_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 8
				fprintf(pTTForm "TEXT \"%s\"\n" tS24) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = 4
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS25) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 16
				fprintf(pTTForm "FIELD F_popTopLongSideY\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 4\n") 
				fprintf(pTTForm "POP \"vertical_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 8
				fprintf(pTTForm "TEXT \"%s\"\n" tS24) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = 4
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS26) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 16
				fprintf(pTTForm "FIELD F_popBottomLongSideX\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 4\n") 
				fprintf(pTTForm "POP \"horizontal_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 8
				fprintf(pTTForm "TEXT \"%s\"\n" tS24)
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = 4
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS27) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 16
				fprintf(pTTForm "FIELD F_popBottomLongSideY\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 4\n") 
				fprintf(pTTForm "POP \"vertical_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 8
				fprintf(pTTForm "TEXT \"%s\"\n" tS24) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "FIELD F_rdoTextRotationForceAngle\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\" \"rot\"\n" tS28) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 18
				fprintf(pTTForm "FIELD F_popForceAngle\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENUMSET 4\n")
				fprintf(pTTForm "POP \"force_angle_popup\"\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 8
				fprintf(pTTForm "TEXT \"%s\"\n" tS24) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "FIELD F_rdoTextRotationLabelAngle\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\" \"rot\"\n" tS29) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 1
				xY = xY + 3
				fprintf(pTTForm "GROUP \"%s\"\n" tS30)
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 32 5\n") 
				fprintf(pTTForm "ENDGROUP\n")
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS31) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 18
				fprintf(pTTForm "FIELD F_iptOffsetCorrection\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 5 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy)
				fprintf(pTTForm "MIN -0.5\n") 
				fprintf(pTTForm "MAX 0.5\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 1
				xY = xY + 3
				fprintf(pTTForm "GROUP \"%s\"\n" tS32) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 32 15\n") 
				fprintf(pTTForm "ENDGROUP\n")
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "FIELD  F_rdoTextFitByHeight\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\" \"txt_by_height\"\n" tS33)
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS34) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 6
				fprintf(pTTForm "FIELD F_iptMinTextHeight\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 5 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "MIN 0.0\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 10
				fprintf(pTTForm "TEXT \"%s\"\n" tS35) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 6
				fprintf(pTTForm "FIELD F_iptMaxTextHeight\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 5 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "MIN 0.0\n") 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 3
				fprintf(pTTForm "FIELD  F_rdoTextFitByBlock\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\" \"txt_by_height\"\n" tS36) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS34) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 6
				fprintf(pTTForm "FIELD F_barMinTextBlock\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "INTSLIDEBAR 2 25\n")
				fprintf(pTTForm "MIN 1\n")
				fprintf(pTTForm "MAX %d\n" xMaxTextBlock) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = xX + 10
				fprintf(pTTForm "TEXT \"%s\"\n" tS35) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 6
				fprintf(pTTForm "FIELD F_barMaxTextBlock\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "INTSLIDEBAR 2 25\n") 
				fprintf(pTTForm "MIN 1\n") 
				fprintf(pTTForm "MAX %d\n" xMaxTextBlock)
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 3
				fprintf(pTTForm "TEXT \"%s\"\n" tS37) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 19
				fprintf(pTTForm "FIELD F_iptBoundaryClearance\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 7 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				fprintf(pTTForm "ENDTAB\n")
				;===============================================================
				xX = 1
				xY = 0
				fprintf(pTTForm "TAB \"%s\"\n" tS50) 
				xX = xX + 1
				xY = xY + 2
				fprintf(pTTForm "FIELD F_chkRestoreView\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "CHECKLIST \"%s\"\n" tS51) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 1
				xY = xY + 2
				fprintf(pTTForm "GROUP \"%s\"\n" tS52) 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "FSIZE 32 16\n") 
				fprintf(pTTForm "ENDGROUP\n")
				xX = xX + 1
				xY = xY + 3
				fprintf(pTTForm "TEXT \"%s\"\n" tS53) ;Text Block
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 14
				fprintf(pTTForm "FIELD F_barTextBlk\n") 
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "INTSLIDEBAR 3 25\n")
				fprintf(pTTForm "MIN 1\n")
				fprintf(pTTForm "MAX %d\n" xMaxTextBlock) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS54) ;Width
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 14
				fprintf(pTTForm "FIELD F_iptWidth\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 7 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS55) ;Height
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 14
				fprintf(pTTForm "FIELD F_iptHeight\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 7 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS56) ;Line Space
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 14
				fprintf(pTTForm "FIELD F_iptLineSpace\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 7 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS57) ;Photo Width
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 14
				fprintf(pTTForm "FIELD F_iptPhotoWidth\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 7 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				xX = 2
				xY = xY + 2
				fprintf(pTTForm "TEXT \"%s\"\n" tS58) ;Char Space
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "ENDTEXT\n")
				xX = xX + 14
				fprintf(pTTForm "FIELD F_iptCharSpace\n")
				fprintf(pTTForm "FLOC %d %d\n" xX xY)
				fprintf(pTTForm "REALFILLIN 7 10\n") 
				fprintf(pTTForm "DECIMAL %d\n" xAccuracy) 
				fprintf(pTTForm "ENDFIELD\n")
				fprintf(pTTForm "ENDTAB\n")
				fprintf(pTTForm "ENDTABSET\n")
				;xY = 34
				;xX = 2
				;xY = xY + 12
				;fprintf(pTTForm "FIELD F_btnExecute\n") 
				;fprintf(pTTForm "FLOC %d %d\n" xX xY)
				;fprintf(pTTForm "MENUBUTTON \"%s\" 9 4\n" tS40) 
				;fprintf(pTTForm "ENDFIELD\n")
				;xX = xX + 12
				;fprintf(pTTForm "FIELD F_btnExit\n") 
				;fprintf(pTTForm "FLOC %d %d\n" xX xY)
				;fprintf(pTTForm "MENUBUTTON \"%s\" 9 4\n" tS41) 
				;fprintf(pTTForm "ENDFIELD\n")
				
				;fprintf(pTTForm "FIELD myhelp\n")
				;fprintf(pTTForm "FLOC 28  47\n") 
				;fprintf(pTTForm "MENUBUTTON \"Help\" 9 3\n") 
				;fprintf(pTTForm "ENDFIELD\n")
				
				fprintf(pTTForm "\n") 
				fprintf(pTTForm "ENDTILE\n")
				fprintf(pTTForm "\n") 
				fprintf(pTTForm "ENDFORM\n") 
				close(pTTForm)
				frmTT = axlFormCreate(gensym() tTTFormFile '(e inner) 'fnTTCalback t) ; t) 後面不能再加入t, 否則所有輸入的數字都變成字串
				deleteFile(tTTFormFile)
				frmTT
			)
		)
		procedure(fnTTSetVariables(frmTT)
			let((mth tTempLayer lBGColor lTempLayerColor dLayer lTexts rUserData xIndex oTextParam lOrgVis)
				mth = 'const 
				defMathConstants(mth) 
				
				
				rUserData = axlUIGetUserData() ;(doneState nil cmdPopupId nil popupId nil)
				remprop(rUserData 'transaction) 
				putprop(rUserData rUserData->popupId 'oldPopupId) ;(oldPopupId nil doneState nil cmdPopupId nil popupId nil)
				;oTextBlk = makeTable("TextBlkTable" nil)
				for(xIndex 1 axlDBControl('maxTextBlock)
					oTextParam = axlGetParam(sprintf(nil "paramTextBlock:%d" xIndex))
					when(oTextParam->height
						lTexts = cons(list(oTextParam->height xIndex) lTexts)
					)
				)
				lTexts = sortcar(lTexts 'lessp)
				frmTT->nMinHeight = car(car(lTexts))
				frmTT->nMaxHeight = car(car(last(lTexts)))
								
				frmTT->tProgName = "TextTuneTools"
				
				frmTT->lLayerVis = axlVisibleGet()
				frmTT->lCurrentArea = axlWindowBoxGet()
				frmTT->commandState = "IDLE"
				frmTT->popupInfo = fnTTLayerPopupSetup()
				frmTT->textList = lTexts
				frmTT->blockInfo = nil
								
				;frmTT->tmpLayer = tTempLayer
				frmTT->PI = const.PI
				frmTT->transMark = nil
				;frmTT->tmpObjects = nil
				
				; for Alias
				frmTT->tDone = nil
				frmTT->tOops = nil
				frmTT->tCancel = nil
				
				frmTT->xMarkCount = 0
				frmTT->popupOrig = nil
				frmTT->popup = nil
				frmTT->popupGray = nil
				axlVisibleDesign(nil)
				
				axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
				axlVisibleLayer("REF DES/ASSEMBLY_TOP" t)
				axlVisibleLayer("REF DES/ASSEMBLY_BOTTOM" t)
				axlVisibleLayer("PACKAGE GEOMETRY/ASSEMBLY_TOP" t)
				axlVisibleLayer("PACKAGE GEOMETRY/ASSEMBLY_BOTTOM" t)
				;axlWindowFit() ;使用此函數會造成畫面閃爍兩次
				axlShell("zoom fit")
				axlVisibleUpdate(t)
			)
		)
		procedure(fnTTSetFormField(frmTT)
			let((tLayerName)
				;設定Form的標題名稱
				axlFormTitle(frmTT strcat(frmTT->tProgName " " tVersion))
				;設定License名稱
				if(stringp(tCompanyName) then
					axlFormColorize(frmTT "F_lblCopyright" 'text 'blue)
					axlFormSetField(frmTT "F_lblCopyright" tCompanyName)
				else
					axlFormColorize(frmTT "F_lblCopyright" 'text 'red)
					axlFormSetField(frmTT "F_lblCopyright" strcat("T" "R" "I" "A" "L" " " "V" "e" "r" "s" "i" "o" "n"))
				)
				;設定其他Form Field值
				axlFormSetField(frmTT "F_popLabelName" "refdes")
				axlFormBuildPopup(frmTT "F_popLabelLayer" frmTT->popupInfo["refdes"]) 
				axlFormSetField(frmTT "F_popLabelLayer" cadar(frmTT->popupInfo["refdes"])) 
				axlFormBuildPopup(frmTT "F_popOutlineLayer" frmTT->popupInfo["package_geom"]) 
				axlFormSetField(frmTT "F_popOutlineLayer" cadar(frmTT->popupInfo["package_geom"])) 
				axlFormSetField(frmTT "F_ckbRotateText" t)
				axlFormSetField(frmTT "F_ckbCenterText" nil) 
				axlFormSetField(frmTT "F_ckbFitText" nil) 
				axlFormSetField(frmTT "F_iptDx" 0.0) 
				axlFormSetField(frmTT "F_iptDy" 0.0) 
				axlFormSetFieldEditable(frmTT "F_iptDx" nil)
				axlFormSetFieldEditable(frmTT "F_iptDy" nil) 
				axlFormSetField(frmTT "F_barMinTextBlock" 1) 
				axlFormSetField(frmTT "F_barMaxTextBlock" length(frmTT->textList)) 
				axlFormSetField(frmTT "F_rdoTextFitByHeight" t) 
				axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" t)
				axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" t) 
				;nMinValue = axlMKSConvert("0.5 MM" car(axlDBGetDesignUnits()))
				;nMaxValue = axlMKSConvert("15  MM" car(axlDBGetDesignUnits()))
				axlFormSetField(frmTT "F_iptMinTextHeight" frmTT->nMinHeight) 
				axlFormSetField(frmTT "F_iptMaxTextHeight" frmTT->nMaxHeight)
				frmTT->blockInfo = fnTTGetBlockInfo(frmTT->nMinHeight frmTT->nMaxHeight "height_mode")
				axlFormSetFieldEditable(frmTT "F_barMinTextBlock" nil) 
				axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil) 
				axlFormSetField(frmTT "F_barMinTextBlock" 1)
				axlFormSetField(frmTT "F_barMaxTextBlock" length(frmTT->textList))
				;axlFormSetField(frmTT "F_rdoMirrorBottomOnly" t)
				axlFormSetField(frmTT "F_chkMirrorBottomOnly" t)
				axlFormSetField(frmTT "F_rdoTextRotationLongSide" t) 
				axlFormSetField(frmTT "F_popTopLongSideX" "0") 
				axlFormSetField(frmTT "F_popTopLongSideY" "90") 
				axlFormSetField(frmTT "F_popBottomLongSideX" "0")
				axlFormSetField(frmTT "F_popBottomLongSideY" "270") 
				axlFormSetFieldEditable(frmTT "F_popForceAngle" nil) 
				axlFormSetField(frmTT "F_popForceAngle" "0") 
				axlFormSetField(frmTT "F_iptOffsetCorrection" 0.0) 
				axlFormSetField(frmTT "F_iptBoundaryClearance" 0.0)
				axlFormSetField(frmTT "text_mirror_bottom_side" t)
				
				tLayerName = "REF DES/ASSEMBLY_TOP"
				axlSetActiveLayer(tLayerName)
				axlFormSetField(frmTT "F_clrTop" fnTTGetLayerColor(tLayerName))
				axlFormSetField(frmTT "F_clrTop" t)
				
				tLayerName = "REF DES/ASSEMBLY_BOTTOM"
				axlFormSetField(frmTT "F_clrBottom" fnTTGetLayerColor(tLayerName))
				axlFormSetField(frmTT "F_clrBottom" t)
				fnTTUpdateFormField(frmTT)
				;===== for Option TAB
				axlFormSetField(frmTT "F_chkRestoreView" t)
				axlFormSetField(frmTT "F_barTextBlk" 1)
				oTextParam = axlGetParam("paramTextBlock:1")
				axlFormSetField(frmTT "F_iptWidth" oTextParam->width)
				axlFormSetField(frmTT "F_iptHeight" oTextParam->height)
				axlFormSetField(frmTT "F_iptLineSpace" oTextParam->lineSpace)
				axlFormSetField(frmTT "F_iptPhotoWidth" oTextParam->photoWidth)
				axlFormSetField(frmTT "F_iptCharSpace" oTextParam->charSpace)
				
				
					
				axlFormDisplay(frmTT) 
			)
		)
		procedure(fnTTStart() 
			let((lEventMask bDoFlag rEventID lbBox lComps) 
				axlUIWPrint(frmTT "Please select components...")
				;frmTT->commandState = "SELECT_AND_EXECUTE"
				printf("M-Please select components...\n")
				
				axlSetFindFilter(?enabled list("noall" "components") ?onButtons list("all"))
				gfnSetAlias(frmTT t)
				axlEventSetStartPopup('fnTTPopup) 
				lEventMask = list('STARTDRAG 'STOPDRAG 'PICK)
				bDoFlag = t
				frmTT->transMark = axlDBTransactionStart()
				while(bDoFlag 
					rEventID = axlEnterEvent(lEventMask nil nil)
					axlClearDynamics() 
					caseq(rEventID->type
						(STARTDRAG 
							axlAddSimpleRbandDynamics(rEventID->xy "box" ?origin 0.0:0.0) 
							lbBox = rEventID->xy
						) 
						(STOPDRAG 
							lComps = list()
							lbBox = list(lbBox rEventID->xy)
							axlSingleSelectBox(lbBox) 
							lComps = axlGetSelSet()
							when(lComps 
								axlDBTransactionMark(frmTT->transMark)
								frmTT->xMarkCount = frmTT->xMarkCount + 1
								fnTTModifyText(lComps)
							) 
							lbBox = nil
							axlClearSelSet()
							fnTTCheckPopup(frmTT)
						) 
						(PICK 
							lComps = list()
							lbBox = nil
							axlSingleSelectPoint(rEventID->xy)
							lComps = axlGetSelSet()
							when(lComps 
								axlDBTransactionMark(frmTT->transMark)
								frmTT->xMarkCount = frmTT->xMarkCount + 1
								fnTTModifyText(lComps)
							) 
							axlClearSelSet()
							fnTTCheckPopup(frmTT)
						) 
						(DONE 
							bDoFlag = nil
							frmTT->commandState = "IDLE"
						)
						(CANCEL 
							bDoFlag = nil
							frmTT->commandState = "IDLE"
						)
					)
					
				)
				gfnSetAlias(frmTT)
				axlEventSetStartPopup()
				printf("M-Exit.")
			)
		)
		procedure(fnTTPopup(event) 
			let(() 
				event = event
				frmTT->popupOrig = axlUIPopupDefine(nil 
					list(list("Done" 'fnTTPopupDone) 
						list("Oops" 'fnTTPopupOops) 
						list("Cancel" 'fnTTPopupCancel)
					)
				)
				frmTT->popupGray = axlUIPopupDefine(nil
					list(list("Done" 'fnTTPopupDone)
						;list("Oops" 'fnTTPopupOops)
						list("Cancel" 'fnTTPopupCancel)
					)
				)
				frmTT->popup = axlUIPopupDefine(nil 
					list(list("Done" 'fnTTPopupDone) 
						list("Oops" 'fnTTPopupOops) 
						list("Cancel" 'fnTTPopupCancel)
					)
				)
				axlUICmdPopupSet(frmTT->popupOrig)
				if(frmTT->xMarkCount >= 1 then
					axlUIPopupSet(frmTT->popup)
				else
					axlUIPopupSet(frmTT->popupGray)
				)
			)
		)
		procedure(fnTTCheckPopup(frmTT)
			;解決執行Oops後Popup變成灰色的
			axlUICmdPopupSet(frmTT->popupOrig)
			cond(
				(frmTT->xMarkCount >= 1
					axlUIPopupSet(frmTT->popup)
				)
				(t
					axlUIPopupSet(frmTT->popupGray)
				)
			)
		)
		procedure(fnTTPopupDone()
			when(frmTT->transMark
				axlDBTransactionCommit(frmTT->transMark)
			)
			axlFinishEnterFun() 
			axlUIPopupSet(nil) 
			axlClearDynamics()
			when(frmTT->tDone
				axlSetAlias(frmTT->tDone "done")
			)
			when(frmTT->tCancel
				axlSetAlias(frmTT->tCancel "cancel")
			)
			when(frmTT->tOops
				axlSetAlias(frmTT->tOops "oops")
			)
			fnTTExit(frmTT)
			;axlShell("done")
		)
		procedure(fnTTPopupOops()
			gfnPopupUndoTimes(frmTT)
			fnTTCheckPopup(frmTT)
			printf("M-Oops\n")
		)
		procedure(fnTTPopupCancel()
			when(frmTT->transMark
				axlDBTransactionRollback(frmTT->transMark) 
			)
			axlCancelEnterFun() 
			axlUIPopupSet(nil) 
			axlClearDynamics()
			when(frmTT->tDone
				axlSetAlias(frmTT->tDone "done")
			)
			when(frmTT->tCancel
				axlSetAlias(frmTT->tCancel "cancel")
			)
			when(frmTT->tOops
				axlSetAlias(frmTT->tOops "oops")
			)
			fnTTExit(frmTT)
			;axlShell("cancel")
		)
		procedure(fnTTModifyText(lComps) 
			let((dOne dTextInst dTextDef lTextXY tTextBlock text_rotation_new nTextRotationDef text_justify text_mirror my_orient result
				lSymBoxCenter lSymInstData lSymDefData tTextValue tTextLayer bOkToProceed tOldTextBlk) 
				foreach(dOne lComps ;dOne = nth(0 lComps)
					bOkToProceed = nil 
					dTextInst = fnTTGetTextData(dOne "instance")
					dTextDef = fnTTGetTextData(dOne "definition")
					lSymInstData = fnTTGetSymData(dOne "instance")
					lSymDefData = fnTTGetSymData(dOne "definition")
					cond(
						(!listp(dTextInst)
							if(dTextInst && lSymInstData then 
								tTextValue = dTextInst->text
								tTextLayer = dTextInst->layer
								lTextXY = dTextInst->xy
								text_justify = dTextInst->justify
								tOldTextBlk = tTextBlock = dTextInst->textBlock
								text_mirror = dTextInst->isMirrored
								text_rotation_new = dTextInst->rotation
								nTextRotationDef = dTextDef->rotation
								unless(nTextRotationDef
									nTextRotationDef = 0.0
									printf("W-Comp = %L ,Text define rotation null\n" dOne->name)
								)
								when(axlFormGetField(frmTT "F_ckbRotateText") 
									bOkToProceed = t
									text_rotation_new = fnTTCalculateTextRotation(lSymInstData lSymDefData dTextInst dTextDef)
								) 
								when(axlFormGetField(frmTT "F_ckbCenterText") 
									bOkToProceed = t
									text_justify = "CENTER"
									lSymBoxCenter = car(lSymInstData)
									lTextXY = fnTTOffsetCorrection(lSymBoxCenter tTextBlock text_rotation_new)
								)
								when(axlFormGetField(frmTT "F_ckbModifyTextBlk") && !axlFormGetField(frmTT "F_ckbFitText")
									bOkToProceed = t
									result = fnTTCalculateTextBlock(lSymInstData lSymDefData tTextValue text_rotation_new nTextRotationDef)
									lTextXY = car(result)
									tTextBlock = cadr(result)
									
									when(stringp(tOldTextBlk) && stringp(tTextBlock)
										axlUIWPrint(frmTT "Changed From %s to %s" tOldTextBlk tTextBlock)
									)
								)  
								when(axlFormGetField(frmTT "F_ckbFitText")
									bOkToProceed = t
									result = fnTTCalculateTextBlock(lSymInstData lSymDefData tTextValue text_rotation_new nTextRotationDef)
									lTextXY = car(result)
									tTextBlock = cadr(result)
								)
								unless(bOkToProceed 
									printf("M-Please select at least one item from \"Mode\" options\n")
								) 
								when(bOkToProceed 
									if(axlFormGetField(frmTT "F_chkMirrorBottomOnly") then
										if(dOne->symbol->isMirrored then
											text_mirror = t
										else
											text_mirror = nil
										)
									else
									;when(axlFormGetField(frmTT "F_rdoNoMirror") 
										text_mirror = nil
									) 
									my_orient = make_axlTextOrientation(?textBlock tTextBlock ?rotation text_rotation_new ?mirrored text_mirror ?justify text_justify)
									axlDeleteObject(dTextInst)
									result = axlDBCreateText(tTextValue lTextXY my_orient tTextLayer dOne->symbol)
									axlDBRefreshId(dOne->symbol)
									axlDBRefreshId(dOne) 
									unless(result 
										printf("E-Could not create Text for %s\n" dOne->name)
									)
								)
								when(axlFormGetField(frmTT "F_ckbDisplayTextBlk") && !axlFormGetField(frmTT "F_ckbModifyTextBlk")
									when(stringp(tTextBlock)
										axlUIWPrint(frmTT "TextBlk: %s" tTextBlock)
									)
								)
							else 
								printf("W-Data not valid for component %s, check text label and/or outline data corresponding to selected options\n" (dOne->name))
							)
						)
						(length(dTextInst) >= 2
							xIndex = 0
							foreach(dText dTextInst ;dText = nth(0 dTextInst) dText->??
								
								bOkToProceed = nil
								tTextValue =dText->text
								tTextLayer = dText->layer
								lTextXY = dText->xy
								text_justify = dText->justify
								tOldTextBlk = tTextBlock = dText->textBlock
								text_mirror = dText->isMirrored
								dParent = dText->parent
								text_rotation_new = dText->rotation
								nTextRotationDef = nth(xIndex dTextDef)->rotation
								unless(nTextRotationDef
									nTextRotationDef = 0.0
								)
								;text_inst_dbid1 = fnTTGetTextData(dText "instance")
								;text_def_dbid1 = fnTTGetTextData(dText "definition")
								lSymDefData = lSymInstData = fnTTGetPinData(dParent "instance")
								;printf("1-tTextValue=%L, lTextXY=%L, my_orient=%L, tTextLayer=%L, dParent=%L\n" tTextValue lTextXY my_orient tTextLayer dParent)
								when(axlFormGetField(frmTT "F_ckbRotateText") 
									bOkToProceed = t
									text_rotation_new = fnTTCalculateTextRotation(lSymInstData lSymDefData dText dText)
								) 
								when(axlFormGetField(frmTT "F_ckbCenterText") 
									bOkToProceed = t
									text_justify = "CENTER"
									lSymBoxCenter = car(lSymInstData)
									lTextXY = fnTTOffsetCorrection(lSymBoxCenter tTextBlock text_rotation_new)
								) 
								when(axlFormGetField(frmTT "F_ckbFitText")
									bOkToProceed = t
									result = fnTTCalculateTextBlock(lSymInstData lSymDefData tTextValue text_rotation_new nTextRotationDef)
									lTextXY = car(result)
									tTextBlock = cadr(result)
								) 
								unless(bOkToProceed 
									printf("W-Please select at least one item from \"Mode\" options\n")
								) 
								when(bOkToProceed 
									if(axlFormGetField(frmTT "F_chkMirrorBottomOnly") then
										if(dOne->symbol->isMirrored then
											text_mirror = t
										else
											text_mirror = nil
										)
									else 
									;when(axlFormGetField(frmTT "F_rdoNoMirror") 
										text_mirror = nil
									) 
									my_orient = make_axlTextOrientation(?textBlock tTextBlock ?rotation text_rotation_new ?mirrored text_mirror ?justify text_justify)
									axlDeleteObject(dText)
									;printf("2-tTextValue=%L, lTextXY=%L, my_orient=%L, tTextLayer=%L, dParent=%L\n" tTextValue lTextXY my_orient tTextLayer dParent)
									result = axlDBCreateText(tTextValue lTextXY my_orient tTextLayer dParent)
									axlDBRefreshId(dParent)
									
									;unless(result 
									;	printf("Could not create Text for %s\n" dOne->name)
									;)
								)
								xIndex++
							)
							axlDBRefreshId(dOne) 
						)
						(t
							t
						)
					)
				)
			)
		)
		procedure(fnTTCalculateTextRotation(lSymInstData lSymDefData dTextInst dTextDef) 
			let((nTextRotation nTextRotationDef nRotationTopH nRotationTopV nRotationBotH nRotationBotV nTotalRotation tRotationMode bOddAngle nSymBoxWidth
				nSymBoxHeight xFactor lSymInstCorners nSymInstRotation bSymInstMirror nRotationForce) 
				
				;dTextInst = dTextInst
				;lSymDefData = lSymDefData
				nRotationTopH = atof(axlFormGetField(frmTT "F_popTopLongSideX"))
				nRotationTopV = atof(axlFormGetField(frmTT "F_popTopLongSideY"))
				nRotationBotH = atof(axlFormGetField(frmTT "F_popBottomLongSideX"))
				nRotationBotV = atof(axlFormGetField(frmTT "F_popBottomLongSideY"))
				nRotationForce = atof(axlFormGetField(frmTT "F_popForceAngle"))
				cond(
					(axlFormGetField(frmTT "F_rdoTextRotationLongSide") 
						tRotationMode = "long_side"
					) 
					(axlFormGetField(frmTT "F_rdoTextRotationLabelAngle") 
						tRotationMode = "label_angle"
					) 
					(axlFormGetField(frmTT "F_rdoTextRotationForceAngle") 
						tRotationMode = "F_popForceAngle"
					)
				) 
				lSymInstCorners = cadr(lSymInstData)
				nSymInstRotation = caddr(lSymInstData)
				bSymInstMirror = nth(3 lSymInstData)
				unless(((nSymInstRotation == 0.0) || (nSymInstRotation == 90.0) || (nSymInstRotation == 180.0) || (nSymInstRotation == 270.0)) 
					bOddAngle = t
				) 
				;bOddAngle = bOddAngle 
				case(tRotationMode 
					("long_side" 
						nSymBoxHeight = abs((cadr(upperRight(lSymInstCorners)) - cadr(lowerLeft(lSymInstCorners))))
						nSymBoxWidth = abs((car(upperRight(lSymInstCorners)) - car(lowerLeft(lSymInstCorners))))
						xFactor = cadr(axlDBGetDesignUnits())
						nSymBoxWidth = nSymBoxWidth + (1.0 / (10.0**xFactor))
						if((nSymBoxHeight - nSymBoxWidth) > 0.0 then 
							if(bSymInstMirror then 
								nTextRotation = nRotationBotV
							else
								nTextRotation = nRotationTopV
							)
						else 
							if(bSymInstMirror then 
								nTextRotation = nRotationBotH
							else
								nTextRotation = nRotationTopH
							)
						)
					) 
					("label_angle" 
						nTextRotationDef = dTextDef->rotation
						unless(nTextRotationDef
							nTextRotationDef = 0.0
							printf("W-Text Define rotation null.\n")
						)
						nTotalRotation = nSymInstRotation + nTextRotationDef
						nTotalRotation = nTotalRotation * 10.0
						nTotalRotation = round(nTotalRotation)
						nTotalRotation = nTotalRotation / 10.0
						when(nTotalRotation >= 360.0
							nTotalRotation = nTotalRotation - 360.0
						) 
						if(bSymInstMirror && axlFormGetField(frmTT "F_chkMirrorBottomOnly") then 
							cond(
								((nTotalRotation >= 0.0) && (nTotalRotation <= 45.0)
									nTextRotation = nTotalRotation
								) 
								((nTotalRotation > 45.0) && (nTotalRotation <= 225.0)
									nTextRotation = nTotalRotation + 180.0
									when(nTextRotation >= 360.0
										nTextRotation = nTextRotation - 360.0
									)
								) 
								((nTotalRotation > 225.0) && (nTotalRotation <= 360.0)
									nTextRotation = nTotalRotation
								)
							)
						else 
							cond(
								((nTotalRotation >= 0.0) && (nTotalRotation < 135.0)
									nTextRotation = nTotalRotation
								) 
								((nTotalRotation >= 135.0) && (nTotalRotation < 315.0)
									nTextRotation = nTotalRotation + 180.0
									when(nTextRotation >= 360.0
										nTextRotation = nTextRotation - 360.0
									)
								) 
								((nTotalRotation >= 315.0) && (nTotalRotation <= 360.0)
									nTextRotation = nTotalRotation
								)
							)
						)
					) 
					("F_popForceAngle" 
						nTextRotation = nRotationForce
					)
				)
				;printf("nTextRotation=%L\n" nTextRotation)
				nTextRotation
			)
		)
		procedure(fnTTGetLayerColor(tLayer) 
			prog((oLayer)
				when(axlIsLayer(tLayer) 
					oLayer = axlLayerGet(tLayer) 
					return(oLayer->color)
				)
				return(nil)
			)
		)
		procedure(fnTTGetPinData(dComp sym_type) 
			let((tOutlineLayerTop tOutlineLayerBottom tOutlineLayer dSymbol list_of_boxes
				box_corners box_center ret_list pp pm x y x_ll y_ll x_ul y_ul rotation mirror)
				
				tOutlineLayerTop = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "TOP")
				tOutlineLayerBottom = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "BOTTOM")
				
				case(sym_type 
					("instance" 
						dSymbol = dComp
						if(dSymbol->isMirrored then 
							tOutlineLayer = tOutlineLayerBottom
						else
							tOutlineLayer = tOutlineLayerTop
						)
					) 
					;("definition" 
					;	dSymbol = (dComp->symbol->definition)
					;	tOutlineLayer = tOutlineLayerTop
					;) 
					;(t)
				) 
				if(dSymbol then 
					;foreach(dChildren (dSymbol->children) 
					;	when(((dChildren->layer) && (upperCase((dChildren->layer)) == tOutlineLayer)) 
					;		when((((dChildren->objType) == "path") || ((dChildren->objType) == "shape") || ((dChildren->objType) == "polygon")) 
					;			(list_of_boxes = cons((dChildren->bBox) list_of_boxes))
					;		)
					;	)
					;)
					list_of_boxes = cons(dSymbol->bBox list_of_boxes) 
					if(length(list_of_boxes) > 0 then 
						box_corners = fnTTGetMaxExtents(list_of_boxes)
						box_center = fnTTGetBoxCenter(box_corners)
						rotation = dSymbol->rotation
						mirror = dSymbol->isMirrored
					else
						pp = 1.0 / (10**cadr(axlDBGetDesignUnits()))
						pm = pp * -1.0
						if(dSymbol->xy then 
							x = car(dSymbol->xy)
							y = cadr(dSymbol->xy)
							x_ll = x - pp
							y_ll = y - pp
							x_ul = x + pp
							y_ul = y + pp
							box_corners = list((x_ll:y_ll) (x_ul:y_ul))
							box_center = dSymbol->xy
							rotation = dSymbol->rotation
							mirror = dSymbol->isMirrored
						else
							printf("W-no outline data found for component:%s\n" dComp->name) 
							box_corners = list((pm:pm) (pp:pp))
							box_center = nil
							rotation = nil
							mirror = nil
						)
					) 
					ret_list = list(box_center box_corners rotation mirror)
				else 
					printf("W-Symbol %s of %s, cannot extract outline data on layer %s\n" sym_type (dComp->name) tOutlineLayer) 
					ret_list = nil
				)
				ret_list
			)
		)
		procedure(fnTTGetSymData(dComp sym_type) 
			let((tOutlineLayerTop tOutlineLayerBottom tOutlineLayer dSymbol list_of_boxes
				box_corners box_center ret_list pp pm x y x_ll y_ll x_ul y_ul rotation mirror)
				
				if(axlFormGetField(frmTT "F_popOutlineLayer") == "PIN/" then
					tOutlineLayerTop = "PACKAGE GEOMETRY/SILKSCREEN_TOP"
					tOutlineLayerBottom = "PACKAGE GEOMETRY/SILKSCREEN_BOTTOM"
				else
					tOutlineLayerTop = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "TOP")
					tOutlineLayerBottom = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "BOTTOM")
				)
				
				case(sym_type 
					("instance" 
						dSymbol = dComp->symbol
						if(dSymbol->isMirrored then 
							tOutlineLayer = tOutlineLayerBottom
						else
							tOutlineLayer = tOutlineLayerTop
						)
					) 
					("definition" 
						dSymbol = dComp->symbol->definition 
						tOutlineLayer = tOutlineLayerTop
					) 
					(t
						t
					)
				) 
				if(dSymbol then 
					foreach(dChildren dSymbol->children
						when(dChildren->layer && (upperCase(dChildren->layer) == tOutlineLayer) 
							when(((dChildren->objType == "path") || (dChildren->objType == "shape") || (dChildren->objType == "polygon")) 
								list_of_boxes = cons(dChildren->bBox list_of_boxes)
							)
						)
					) 
					if(length(list_of_boxes) > 0 then 
						box_corners = fnTTGetMaxExtents(list_of_boxes)
						box_center = fnTTGetBoxCenter(box_corners)
						rotation = dSymbol->rotation
						mirror = dSymbol->isMirrored
					else
						pp = 1.0 / (10**cadr(axlDBGetDesignUnits()))
						pm = pp * -1.0
						if(dSymbol->xy then 
							x = car(dSymbol->xy)
							y = cadr(dSymbol->xy)
							x_ll = x - pp
							y_ll = y - pp
							x_ul = x + pp
							y_ul = y + pp
							box_corners = list((x_ll:y_ll) (x_ul:y_ul))
							box_center = dSymbol->xy
							rotation = dSymbol->rotation
							mirror = dSymbol->isMirrored
						else
							printf("W-no outline data found for component:%s\n" dComp->name) 
							box_corners = list((pm:pm) (pp:pp))
							box_center = nil
							rotation = nil
							mirror = nil
						)
					) 
					ret_list = list(box_center box_corners rotation mirror)
				else 
					printf("W-Symbol %s of %s, cannot extract outline data on layer %s\n" sym_type (dComp->name) tOutlineLayer) 
					ret_list = nil
				)
				ret_list
			)
		)
		procedure(fnTTGetTextData(dComp sym_type) 
			let((tTextLayerTop tTextLayerBottom tTextLayer dText dSymbol gReturnValue tNumber lText lTextValue)
				if(axlFormGetField(frmTT "F_popLabelLayer") == "PACKAGE GEOMETRY/PIN_NUMBER" then
					tTextLayer = axlFormGetField(frmTT "F_popLabelLayer")
					lTextValue = nil
					;printf("dComp=%L\n" dComp->??)
					when(dComp->pins
						foreach(dOne dComp->pins ;dOne = nth(0 dComp->pins)
							tNumber = dOne->number
							lText = axlDBGetAttachedText(dOne)
							foreach(dText lText
								when(upperCase(dText->layer) == tTextLayer
									lTextValue = cons(dText lTextValue)
								)
							)
						)
					)
					gReturnValue = lTextValue
				else
					tTextLayerTop = strcat(axlFormGetField(frmTT "F_popLabelLayer") "TOP") 
					tTextLayerBottom = strcat(axlFormGetField(frmTT "F_popLabelLayer") "BOTTOM")
				
					case(sym_type 
						("instance" 
							dSymbol = dComp->symbol 
							if(dSymbol->isMirrored then 
								tTextLayer = tTextLayerBottom
							else
								tTextLayer = tTextLayerTop
							)
						) 
						("definition" 
							dSymbol = dComp->symbol->definition 
							tTextLayer = tTextLayerTop
						)
					) 
					foreach(dChildren dSymbol->children ;dChildren = nth(0 dSymbol->children) dChildren->??
						when((dChildren->objType == "text") && (upperCase(dChildren->layer) == tTextLayer) 
							dText = dChildren
						)
					)
					if(dText then 
						gReturnValue = dText
					else
						printf("W-Symbol %s of %s, cannot extract label on layer %s\n" sym_type dComp->name tTextLayer)
						gReturnValue = nil
					)
				)
				;printf("gReturnValue=%L\n" gReturnValue)
				gReturnValue
			)
		)
		procedure(fnTTCalculateTextBlock(lSymInstData lSymDefData tTextValue nTextRotation nTextRotationDef) 
			let((lSymBoxCorners lSymBoxCenter lTextXY tTextBlock nBlock nBlockHeight nBlockWidth nBlockSpace bLoop xCharCount
				nTextWidth nTextHeight nBoundaryClearance nMaxTextWidth nMaxTextHeight nSymBoxWidth nSymBoxHeight xCount xFitCount
				nNewTextWidth tTextWidth nNewTextHeight tTextHeight nNewMaxTextWidth tMaxTextWidth nNewMaxTextHeight tMaxTextHeight)
				
				lSymBoxCenter = car(lSymInstData) 
				cond(
					((axlFormGetField(frmTT "F_rdoTextRotationLongSide") || axlFormGetField(frmTT "F_rdoTextRotationForceAngle")) 
						lSymBoxCorners = cadr(lSymInstData)
						nSymBoxWidth = abs((car(upperRight(lSymBoxCorners)) - car(lowerLeft(lSymBoxCorners))))
						nSymBoxHeight = abs((cadr(upperRight(lSymBoxCorners)) - cadr(lowerLeft(lSymBoxCorners))))
						if(zerop(round(nTextRotation)) || (round(nTextRotation) == 180) then 
							nMaxTextWidth = nSymBoxWidth
							nMaxTextHeight = nSymBoxHeight
						else
							nMaxTextWidth = nSymBoxHeight
							nMaxTextHeight = nSymBoxWidth
						)
					) 
					(axlFormGetField(frmTT "F_rdoTextRotationLabelAngle") 
						lSymBoxCorners = cadr(lSymDefData)
						nSymBoxWidth = abs((car(upperRight(lSymBoxCorners)) - car(lowerLeft(lSymBoxCorners))))
						nSymBoxHeight = abs((cadr(upperRight(lSymBoxCorners)) - cadr(lowerLeft(lSymBoxCorners)))) 
						cond(
							((nTextRotationDef >= 0.0) && (nTextRotationDef <= 45.0) 
								nMaxTextWidth = nSymBoxWidth 
								nMaxTextHeight = nSymBoxHeight
							) 
							((nTextRotationDef > 45.0) && (nTextRotationDef < 135.0)
								nMaxTextWidth = nSymBoxHeight 
								nMaxTextHeight = nSymBoxWidth
							) 
							((nTextRotationDef >= 135.0) && (nTextRotationDef <= 225.0)
								nMaxTextWidth = nSymBoxWidth 
								nMaxTextHeight = nSymBoxHeight
							) 
							((nTextRotationDef > 225.0) && (nTextRotationDef < 315.0)
								nMaxTextWidth = nSymBoxHeight 
								nMaxTextHeight = nSymBoxWidth
							) 
							((nTextRotationDef >= 315.0) && (nTextRotationDef <= 360.0)
								nMaxTextWidth = nSymBoxWidth 
								nMaxTextHeight = nSymBoxHeight
							)
						)
					) 
					(t t)
				)
				if(axlFormGetField(frmTT "F_ckbModifyTextBlk") && !axlFormGetField(frmTT "F_ckbFitText") then
					;axlFormGetField(frmTT "F_rdoTextFitByBlock") && (axlFormGetField(frmTT "F_barMinTextBlock") == axlFormGetField(frmTT "F_barMaxTextBlock")) then
					nBlock = axlFormGetField(frmTT "F_barMinTextBlock")
				else
					xFitCount = nil
					xCount = 0 
					bLoop = t
					while(bLoop 
						if(frmTT->blockInfo[xCount] then 
							nBlockHeight = cadr(frmTT->blockInfo[xCount]) 
							nBlockWidth = caddr(frmTT->blockInfo[xCount]) 
							nBlockSpace = nth(3 frmTT->blockInfo[xCount])
							xCharCount = strlen(tTextValue) 
							nTextWidth = (xCharCount * nBlockWidth) + ((xCharCount - 1) * nBlockSpace) 
							nTextHeight = nBlockHeight
							nBoundaryClearance = axlFormGetField(frmTT "F_iptBoundaryClearance")
							when(nBoundaryClearance > 0.0
								nTextWidth = nTextWidth + (2 * nBoundaryClearance)
								nTextHeight = nTextHeight + (2 * nBoundaryClearance)
							)
							;printf("Value=%L, nTextWidth=%L, nMaxTextWidth=%L, nTextHeight=%L, nMaxTextHeight=%L\n" tTextValue nTextWidth nMaxTextWidth nTextHeight nMaxTextHeight)
							;修正有一些數字判斷會錯誤,所以先將數字轉為字串再轉回數字
							sprintf(tTextWidth "%f" nTextWidth)
							sprintf(tTextHeight "%f" nTextHeight)
							sprintf(tMaxTextWidth "%f" nMaxTextWidth)
							sprintf(tMaxTextHeight "%f" nMaxTextHeight)
							nNewTextWidth = atof(tTextWidth)
							nNewTextHeight = atof(tTextHeight)
							nNewMaxTextWidth = atof(tMaxTextWidth)
							nNewMaxTextHeight = atof(tMaxTextHeight)
							;printf("Value=%L, nTextWidth=%L, nMaxTextWidth=%L, nTextHeight=%L, nMaxTextHeight=%L\n" tTextValue nNewTextWidth nNewMaxTextWidth nNewTextHeight nNewMaxTextHeight)
							if(((nNewTextWidth >= nNewMaxTextWidth) || (nNewTextHeight >= nNewMaxTextHeight)) then 
								bLoop = nil
							else
								xFitCount = xCount
								++xCount
							)
							when(xCount >= axlDBControl('maxTextBlock)
								bLoop = nil
							)
						else
							bLoop = nil
						)
					) 
					if(xFitCount then
						if(xFitCount >= axlDBControl('maxTextBlock) then
							nBlock = car(frmTT->blockInfo[0])
							nBlockHeight = cadr(frmTT->blockInfo[0]) 
							printf("W-Cannot fit text within text %s(%L,%L), using minimum block %d with height %.4f\n" tTextValue nMaxTextWidth nMaxTextHeight nBlock nBlockHeight)
						else
							nBlock = car(frmTT->blockInfo[xFitCount])
						)
					else
						nBlock = car(frmTT->blockInfo[0])
						nBlockHeight = cadr(frmTT->blockInfo[0]) 
						printf("W-Cannot fit text within text %s(%L,%L), using minimum block %d with height %.4f\n" tTextValue nMaxTextWidth nMaxTextHeight nBlock nBlockHeight)
					)
				) 
				tTextBlock = sprintf(nil "%d" nBlock)
				lTextXY = fnTTOffsetCorrection(lSymBoxCenter tTextBlock nTextRotation) 
				list(lTextXY tTextBlock)
			)
		)
		procedure(fnTTOffsetCorrection(lTextXY tTextBlock nTextRotation) 
			let((nCorrectionFactor nTextHeight nTextOffset nDeltaX nDeltaY
				nAngle nTextX nTextY nPI oTextParam nUserDx nUserDy) 
				
				oTextParam = axlGetParam(strcat("paramTextBlock:" tTextBlock))
				nPI = frmTT->PI
				nCorrectionFactor = axlFormGetField(frmTT "F_iptOffsetCorrection")
				nUserDx = axlFormGetField(frmTT "F_iptDx")
				nUserDy = axlFormGetField(frmTT "F_iptDy")
				nTextHeight = oTextParam->height
				nTextOffset = (nTextHeight / 2.0) - (nTextHeight * nCorrectionFactor)
				cond(
					((nTextRotation >= 0.0) && (nTextRotation <= 90.0)
						nAngle = (nTextRotation / 180.0) * nPI
						nDeltaX = abs((cos(((nPI / 2) - nAngle)) * nTextOffset))
						nDeltaY = -abs((sin(((nPI / 2) - nAngle)) * nTextOffset))
					) 
					((nTextRotation > 90.0) && (nTextRotation <= 180.0)
						nAngle = ((180.0 - nTextRotation) / 180.0) * nPI
						nDeltaX = abs(cos(((nPI / 2) - nAngle)) * nTextOffset)
						nDeltaY = abs(sin(((nPI / 2) - nAngle)) * nTextOffset)
					) 
					((nTextRotation > 180.0) && (nTextRotation <= 270.0)
						nAngle = ((nTextRotation - 180.0) / 180.0) * nPI
						nDeltaX = -abs(cos(((nPI / 2) - nAngle)) * nTextOffset)
						nDeltaY = abs(sin(((nPI / 2) - nAngle)) * nTextOffset)
					) 
					((nTextRotation > 270.0) && (nTextRotation <= 360.0)
						nAngle = ((360.0 - nTextRotation) / 180.0) * nPI
						nDeltaX = -abs(cos(((nPI / 2) - nAngle)) * nTextOffset)
						nDeltaY = -abs(sin(((nPI / 2) - nAngle)) * nTextOffset)
					)
				) 
				nTextX = car(lTextXY) + nDeltaX
				nTextY = cadr(lTextXY) + nDeltaY
				nTextX = nTextX + nUserDx
				nTextY = nTextY + nUserDy
				list(nTextX nTextY)
			)
		)
		procedure(fnTTGetMaxExtents(lBox) 
			let((x_ll y_ll x_ur y_ur ret_list) 
				foreach(b lBox 
					unless(x_ll 
						x_ll = car(lowerLeft(b))
					) 
					unless(y_ll 
						y_ll = cadr(lowerLeft(b))
					) 
					unless(x_ur 
						x_ur = car(upperRight(b))
					)
					unless(y_ur 
						y_ur = cadr(upperRight(b))
					) 
					when(car(lowerLeft(b)) < x_ll
						x_ll = car(lowerLeft(b))
					) 
					when(cadr(lowerLeft(b)) < y_ll
						y_ll = cadr(lowerLeft(b))
					) 
					when(car(upperRight(b)) > x_ur
						x_ur = car(upperRight(b))
					) 
					when(cadr(upperRight(b)) > y_ur
						y_ur = cadr(upperRight(b))
					)
				) 
				ret_list = list((x_ll:y_ll) (x_ur:y_ur))
				ret_list
			)
		)
		procedure(fnTTGetBoxCenter(lBox) 
			let((x_ll y_ll x_ur y_ur x_center y_center ret) 
				x_ll = car(lowerLeft(lBox))
				y_ll = cadr(lowerLeft(lBox))
				x_ur = car(upperRight(lBox)) 
				y_ur = cadr(upperRight(lBox))
				foreach(xy lBox 
					when(car(xy) < x_ll
						x_ll = car(xy)
					) 
					when(cadr(xy) < y_ll
						y_ll = cadr(xy)
					)
					when(car(xy) > x_ur
						x_ur = car(xy)
					)
					when(cadr(xy) > y_ur
						y_ur = cadr(xy)
					)
				) 
				x_ll = x_ll * 1.0
				y_ll = y_ll * 1.0
				x_ur = x_ur * 1.0
				y_ur = y_ur * 1.0
				x_center = x_ll + ((x_ur - x_ll) / 2.0)
				y_center = y_ll + ((y_ur - y_ll) / 2.0)
				ret = x_center:y_center
				ret
			)
		)
		procedure(fnTTGetBlockInfo(nMinValue nMaxValue tMode) 
			let((xID aBlockInfo nCurrentHeight nCurrentBlock oTextParam xTextBlk lEntry)
				aBlockInfo = makeVector(axlDBControl('maxTextBlock) nil)
				xID = 0
				case(tMode 
					("block_mode" 
						for(xTextBlk nMinValue nMaxValue 
							oTextParam = axlGetParam(sprintf(nil "paramTextBlock:%d" xTextBlk))
							aBlockInfo[xID] = list(xTextBlk oTextParam->height oTextParam->width oTextParam->charSpace)
							++xID
						)
					) 
					("height_mode" 
						foreach(lEntry frmTT->textList 
							nCurrentHeight = car(lEntry) 
							nCurrentBlock = cadr(lEntry) 
							when((nMinValue <= nCurrentHeight) && (nCurrentHeight <= nMaxValue) 
								oTextParam = axlGetParam(sprintf(nil "paramTextBlock:%d" nCurrentBlock))
								aBlockInfo[xID] = list(nCurrentBlock oTextParam->height oTextParam->width oTextParam->charSpace)
								++xID
							)
						)
					)
				)
				aBlockInfo
			)
		)
		procedure(fnTTLayerPopupSetup() 
			let((tBaseName lBase tLayerTop tLayerBot tClass oNiceName lConfig tPkgNickName oPopupInfo tNickName lPopup lOne tClass tSubclass tName tBase) 
				oNiceName = makeTable("nice_name_table" nil)
				oNiceName["ASSEMBLY"] = "Assembly"
				oNiceName["PLACE_BOUND"] = "Place_Bound"
				oNiceName["SILKSCREEN"] = "Silkscreen"
				oNiceName["DISPLAY"] = "Display"
				oNiceName["DFA_BOUND"] = "DFA_Bound"
				oNiceName["PIN"] = "Pin"
				tPkgNickName = "package_geom"
				lConfig = list(
					list("refdes" axlMapClassName("REF DES"))
					list("value" axlMapClassName("COMPONENT VALUE")) 
					list("part_number" axlMapClassName("USER PART NUMBER")) 
					list("device_type" axlMapClassName("DEVICE TYPE")) 
					list("tolerance" axlMapClassName("TOLERANCE"))
					list("package_geo1" axlMapClassName("PACKAGE GEOMETRY"))
					list(tPkgNickName  axlMapClassName("PACKAGE GEOMETRY"))
				)
				oPopupInfo = makeTable("layer_info_table" nil)
				foreach(lOne lConfig ;讀取每一個Config的Subclass名稱
					tNickName = car(lOne)
					tClass = cadr(lOne) ;tClass = axlMapClassName("PACKAGE GEOMETRY")
					lBase = list()
					cond(
						(tNickName == "package_geo1"
							lBase = cons("PIN_NUMBER" lBase)
						)
						(t
							foreach(tSubclass axlGetParam(strcat("paramLayerGroup:" tClass))->groupMembers
								tBaseName = upperCase(tSubclass)
								when(rexMatchp("_TOP" tBaseName) || rexMatchp("_BOTTOM" tBaseName)
									;文字裡面有TOP 和BOTTOM 才執行
									rexCompile("_TOP") 
									tBaseName = rexReplace(tBaseName "" 0)
									rexCompile("_BOTTOM") 
									tBaseName = rexReplace(tBaseName "" 0)
									unless(member(tBaseName lBase) ;不是lBase的成員才執行(只又已有文字就不執行)
										lBase = cons(tBaseName lBase)
									)
								)
							) 
							lBase = sort(lBase nil)
							when(tNickName == tPkgNickName 
								lBase = remove("SOLDERMASK" lBase)
								lBase = remove("PASTEMASK" lBase)
							) 
							foreach(tName lBase
								cond(
									(tNickName == "package_geo1"
										t
									)
									(t
										tLayerTop = strcat(tClass "/" tName "_TOP")
										tLayerBot = strcat(tClass "/" tName "_BOTTOM")
										unless(axlIsLayer(tLayerTop) 
											axlLayerCreateNonConductor(tLayerTop)
										)
										unless(axlIsLayer(tLayerBot) 
											axlLayerCreateNonConductor(tLayerBot)
										)
									)
								)
							)
							
						)
					)
					lPopup = list()
					foreach(tBase lBase 
						if(oNiceName[tBase] then 
							tBaseName = oNiceName[tBase]
						else
							;將字串第一個字轉換為大寫,其他的字都小寫
							tBaseName = strcat(upperCase(substring(tBase 1 1)) lowerCase(substring(tBase 2)))
						)
						if(tNickName == "package_geo1" then
							lPopup = cons(list(tBaseName strcat(tClass "/" tBase)) lPopup)
						else
							lPopup = cons(list(tBaseName strcat(tClass "/" tBase "_")) lPopup)
						)
						
					)
					;加入PIN/TOP, PIN/BOTTOM
					when(tNickName == tPkgNickName 
						lPopup = cons(list("Pin" strcat("PIN/")) lPopup)
					)
					lPopup = reverse(lPopup)
					oPopupInfo[tNickName] = lPopup
					;printf("lPopup=%L\n" lPopup)
				)
				oPopupInfo
			)
		)
		unless(fboundp('gfnPopupUndoTimes)
			procedure(gfnPopupUndoTimes(rFormID @optional (xCount 1) (bSub1 nil) (bRotate nil))
				let((xIndex)
					for(xIndex 0 xCount-1
						if(!axlDBTransactionOops(rFormID->transMark) then
							rFormID->xMarkCount = 0
						else
							rFormID->xMarkCount = rFormID->xMarkCount - 1
						)
					)
					when(bSub1
						rFormID->xMarkCount = rFormID->xMarkCount - 1
					)
					when(bRotate
						rFormID->xMarkCount = rFormID->xMarkCount - 1
					)
				)
			)
		)
		unless(fboundp('gfnSetAlias)
			procedure(gfnSetAlias(rFormmID @optional (bSet nil))
				let((tOne)
					if(bSet then
						foreach(tOne axlGetAlias(nil) ;tOne = nth(0 lAllAlias)
							case(axlGetAlias(tOne)
								("done" || "Done"
									axlSetAlias(tOne "pop Done")
									rFormmID->tDone = tOne
								)
								("cancel" || "Cancel"
									axlSetAlias(tOne "pop Cancel") ; Set quick function "Esc" in popup memu
									rFormmID->tCancel = tOne
								)
								("oops" || "Oops"
									axlSetAlias(tOne "pop Oops") ; Set quick function "F3" in popup memu
									rFormmID->tOops = tOne
								)
							)
						)
					else
						when(rFormmID->tDone
							axlSetAlias(rFormmID->tDone "done")
							rFormmID->tDone = nil
						)
						when(rFormmID->tCancel
							axlSetAlias(rFormmID->tCancel "cancel")
							rFormmID->tDone = nil
						)
						when(rFormmID->tOops
							axlSetAlias(rFormmID->tOops "oops")
							rFormmID->tDone = nil
						)
					)
				)
			)
		)
	
		procedure(fnTTUpdateFormField(frmTT)
			let(()
				if(axlFormGetField(frmTT "F_ckbRotateText") then
					axlFormSetFieldEditable(frmTT "F_rdoTextRotationLongSide" t)
					axlFormSetFieldEditable(frmTT "F_rdoTextRotationForceAngle" t)
					axlFormSetFieldEditable(frmTT "F_rdoTextRotationLabelAngle" t)
					when(axlFormGetField(frmTT "F_rdoTextRotationLongSide")
						axlFormSetFieldEditable(frmTT "F_popTopLongSideX" t) 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideY" t) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideX" t) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideY" t)
						axlFormSetFieldEditable(frmTT "F_popForceAngle" nil)
					)
					when(axlFormGetField(frmTT "F_rdoTextRotationForceAngle")
						axlFormSetFieldEditable(frmTT "F_popTopLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideY" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideY" nil)
						axlFormSetFieldEditable(frmTT "F_popForceAngle" t)
					) 
					when(axlFormGetField(frmTT "F_rdoTextRotationLabelAngle")
						axlFormSetFieldEditable(frmTT "F_popTopLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideY" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideY" nil)
						axlFormSetFieldEditable(frmTT "F_popForceAngle" nil)
					)
				else
					axlFormSetFieldEditable(frmTT "F_rdoTextRotationLongSide" nil)
					axlFormSetFieldEditable(frmTT "F_rdoTextRotationForceAngle" nil)
					axlFormSetFieldEditable(frmTT "F_rdoTextRotationLabelAngle" nil)
					axlFormSetFieldEditable(frmTT "F_popTopLongSideX" nil) 
					axlFormSetFieldEditable(frmTT "F_popTopLongSideY" nil) 
					axlFormSetFieldEditable(frmTT "F_popBottomLongSideX" nil) 
					axlFormSetFieldEditable(frmTT "F_popBottomLongSideY" nil)
					axlFormSetFieldEditable(frmTT "F_popForceAngle" nil)
				)
				if(axlFormGetField(frmTT "F_ckbCenterText") then
					axlFormSetFieldEditable(frmTT "F_iptOffsetCorrection" t)
				else
					axlFormSetFieldEditable(frmTT "F_iptOffsetCorrection" nil)
				)
				if(axlFormGetField(frmTT "F_ckbFitText") then
					axlFormSetFieldEditable(frmTT "F_rdoTextFitByHeight" t)
					axlFormSetFieldEditable(frmTT "F_rdoTextFitByBlock" t)
					axlFormSetFieldEditable(frmTT "F_iptBoundaryClearance" t)
					if(axlFormGetField(frmTT "F_rdoTextFitByHeight") then 
						axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" t) 
						axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" t) 
						axlFormSetFieldEditable(frmTT "F_barMinTextBlock" nil)
						axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil)
					else
						axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" nil) 
						axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" nil) 
						axlFormSetFieldEditable(frmTT "F_barMinTextBlock" t)
						axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" t)
					)
				else
					axlFormSetFieldEditable(frmTT "F_rdoTextFitByHeight" nil)
					axlFormSetFieldEditable(frmTT "F_rdoTextFitByBlock" nil)
					axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" nil) 
					axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" nil) 
					axlFormSetFieldEditable(frmTT "F_barMinTextBlock" nil)
					axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil)
					axlFormSetFieldEditable(frmTT "F_iptBoundaryClearance" nil)
					when(axlFormGetField(frmTT "F_ckbModifyTextBlk")
						axlFormSetFieldEditable(frmTT "F_rdoTextFitByBlock" t)
						axlFormSetFieldEditable(frmTT "F_barMinTextBlock" t)
					)
				)
				
			)
		)
		;=======================================================
		procedure(fnTTUpdateTextBlkValue(frmTT bUpdateValue)
			let((tTextBlk oTextParam)
				if(bUpdateValue then
					tTextBlk = axlFormGetField(frmTT "F_barTextBlk")
					oTextParam = axlGetParam(sprintf(nil "paramTextBlock:%d" tTextBlk))
					axlFormSetField(frmTT "F_iptWidth" oTextParam->width)
					axlFormSetField(frmTT "F_iptHeight" oTextParam->height)
					axlFormSetField(frmTT "F_iptLineSpace" oTextParam->lineSpace)
					axlFormSetField(frmTT "F_iptPhotoWidth" oTextParam->photoWidth)
					axlFormSetField(frmTT "F_iptCharSpace" oTextParam->charSpace)
				else
					tTextBlk = axlFormGetField(frmTT "F_barTextBlk")
					oTextParam = axlGetParam(sprintf(nil "paramTextBlock:%d" tTextBlk))
					oTextParam->width = axlFormGetField(frmTT "F_iptWidth")
					oTextParam->height = axlFormGetField(frmTT "F_iptHeight")
					oTextParam->lineSpace = axlFormGetField(frmTT "F_iptLineSpace")
					oTextParam->photoWidth = axlFormGetField(frmTT "F_iptPhotoWidth")
					oTextParam->charSpace = axlFormGetField(frmTT "F_iptCharSpace")
					axlSetParam(oTextParam)
					axlVisibleUpdate(nil)
				)
			)
		)
		procedure(fnTTExit(frmTT)
			let(()
 frmTT->xkClosing = t
				when(frmTT->commandState == "SELECT_AND_EXECUTE"
					fnTTPopupDone()
				)
				gfnSetAlias(frmTT)
				axlFinishEnterFun() 
				axlUIPopupSet(nil) 
				axlClearDynamics()
				when(frmTT->xkRestoreView
					axlVisibleSet(frmTT->lLayerVis)
					axlWindowBoxSet(frmTT->lCurrentArea)
					axlVisibleUpdate(t)
				)
				axlFormClose(frmTT) 
				frmTT->commandState = "IDLE"
				when(frmTT->transMark 
					axlDBTransactionCommit(frmTT->transMark)
				)
				;##### Undefine the global variable area ###########################################
				putd('fnTTStart nil)
				putd('fnTTPopup nil)
				putd('fnTTCheckPopup nil)
				putd('fnTTPopupDone nil)
				putd('fnTTPopupOops nil)
				putd('fnTTPopupCancel nil)
				putd('fnTTModifyText nil)
				putd('fnTTCalculateTextRotation nil)
				putd('fnTTGetLayerColor nil)
				putd('fnTTGetPinData nil)
				putd('fnTTGetSymData nil)
				putd('fnTTGetTextData nil)
				putd('fnTTCalculateTextBlock nil)
				putd('fnTTOffsetCorrection nil)
				putd('fnTTGetMaxExtents nil)
				putd('fnTTGetBoxCenter nil)
				putd('fnTTGetBlockInfo nil)
				putd('fnTTLayerPopupSetup nil)
				;putd('gfnPopupUndoTimes nil)
				;putd('gfnSetAlias nil)
				putd('fnTTUpdateFormField nil)
				putd('fnTTUpdateTextBlkValue nil)
				putd('fnTTExit nil)
				putd('fnTTCalback nil)
			)
		)
		procedure(fnTTCalback(frmTT) 
			let((nMaxValue nMinValue nMinHeight nMaxHeight xMinBlock xMaxBlock)
				;printf("field/value %L = %L (int %L)" frmTT->curField, frmTT->curValue, frmTT->curValueInt)
				;printf("doneState %L\n" frmTT->doneState )
				case(if(frmTT->xkClosing then "" else frmTT->curField)
 ("F_chkRestoreView" frmTT->xkRestoreView = frmTT->curValue) 
					("F_popLabelName" 
						tLabelName = frmTT->curValue
						axlFormBuildPopup(frmTT "F_popLabelLayer" frmTT->popupInfo[tLabelName]) 
						axlFormSetField(frmTT "F_popLabelLayer" cadar(frmTT->popupInfo[tLabelName]))
						axlVisibleDesign(nil)
						axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
						if(tLabelName == "package_geo1" then
							axlFormSetField(frmTT "F_popOutlineLayer" "PIN/")
							axlVisibleLayer("PACKAGE GEOMETRY/PIN_NUMBER" t)
							axlVisibleLayer("PIN/TOP" t)
							axlVisibleLayer("PIN/BOTTOM" t)
							axlSetActiveLayer("PACKAGE GEOMETRY/PIN_NUMBER")
							axlFormSetField(frmTT "F_clrTop" fnTTGetLayerColor("PIN/TOP"))
							axlFormSetField(frmTT "F_clrTop" t)
							axlFormSetField(frmTT "F_clrBottom" fnTTGetLayerColor("PIN/BOTTOM"))
							axlFormSetField(frmTT "F_clrBottom" t)
						else
							when(axlFormGetField(frmTT "F_popOutlineLayer") == "PIN/"
								axlFormSetField(frmTT "F_popOutlineLayer" "PACKAGE GEOMETRY/ASSEMBLY_")
							)
							tLayerName = tLayer = strcat(axlFormGetField(frmTT "F_popLabelLayer") "TOP")
							axlVisibleLayer(tLayer t)
							axlFormSetField(frmTT "F_clrTop" fnTTGetLayerColor(tLayerName))
							axlFormSetField(frmTT "F_clrTop" t)
							
							tLayerName = tLayer = strcat(axlFormGetField(frmTT "F_popLabelLayer") "BOTTOM")
							axlVisibleLayer(tLayer t)
							axlFormSetField(frmTT "F_clrBottom" fnTTGetLayerColor(tLayerName))
							axlFormSetField(frmTT "F_clrBottom" t)
							
							tLayer = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "TOP")
							axlVisibleLayer(tLayer t)
							tLayer = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "BOTTOM")
							axlVisibleLayer(tLayer t)
							
						)
						axlVisibleUpdate(t)
						tLabelName = 'unbound
						tLayer = 'unbound
					)
					("F_popLabelLayer"
						axlVisibleDesign(nil)
						axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
						tLayerName = tLayer = strcat(axlFormGetField(frmTT "F_popLabelLayer") "TOP")
						axlVisibleLayer(tLayer t)
						axlFormSetField(frmTT "F_clrTop" fnTTGetLayerColor(tLayerName))
						axlFormSetField(frmTT "F_clrTop" t)
							
						tLayerName = tLayer = strcat(axlFormGetField(frmTT "F_popLabelLayer") "BOTTOM")
						axlVisibleLayer(tLayer t)
						axlFormSetField(frmTT "F_clrBottom" fnTTGetLayerColor(tLayerName))
						axlFormSetField(frmTT "F_clrBottom" t)
							
						tLayer = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "TOP")
						axlVisibleLayer(tLayer t)
						tLayer = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "BOTTOM")
						axlVisibleLayer(tLayer t)
						axlVisibleUpdate(t)
						tLayerName = 'unbound
						tLayer = 'unbound
					)
					("F_popOutlineLayer"
						tOutlineLayer = frmTT->curValue
						axlVisibleDesign(nil)
						axlVisibleLayer("BOARD GEOMETRY/OUTLINE" t)
						tLayer = strcat(axlFormGetField(frmTT "F_popLabelLayer") "TOP")
						axlVisibleLayer(tLayer t)
						tLayer = strcat(axlFormGetField(frmTT "F_popLabelLayer") "BOTTOM")
						axlVisibleLayer(tLayer t)
						cond(
							((axlFormGetField(frmTT "F_popLabelName") == "package_geo1") && (tOutlineLayer == "PIN/")
								axlFormSetField(frmTT "F_popOutlineLayer" "PIN/")
								axlVisibleLayer("PACKAGE GEOMETRY/PIN_NUMBER" t)
								axlVisibleLayer("PIN/TOP" t)
								axlVisibleLayer("PIN/BOTTOM" t)
							)
							((axlFormGetField(frmTT "F_popLabelName") == "package_geo1") && (tOutlineLayer != "PIN/")
								printf("W-The PIN_NUMBER only support pin layer!\n")
								axlFormSetField(frmTT "F_popOutlineLayer" "PIN/")
								axlVisibleLayer("PACKAGE GEOMETRY/PIN_NUMBER" t)
								axlVisibleLayer("PIN/TOP" t)
								axlVisibleLayer("PIN/BOTTOM" t)
							)
							((axlFormGetField(frmTT "F_popLabelName") != "package_geo1") && (tOutlineLayer == "PIN/")
								printf("W-The pin only support PIN_NUMBER layer!\n")
								axlFormSetField(frmTT "F_popOutlineLayer" "PACKAGE GEOMETRY/ASSEMBLY_")
								tOutlineLayer = "PACKAGE GEOMETRY/ASSEMBLY_"
								tLayer = strcat(tOutlineLayer "TOP")
								axlVisibleLayer(tLayer t)
								tLayer = strcat(tOutlineLayer "BOTTOM")
								axlVisibleLayer(tLayer t)
							)
							((axlFormGetField(frmTT "F_popLabelName") != "package_geo1") && (tOutlineLayer != "PIN/")
								tLayer = strcat(tOutlineLayer "TOP")
								axlVisibleLayer(tLayer t)
								tLayer = strcat(tOutlineLayer "BOTTOM")
								axlVisibleLayer(tLayer t)
							)
							
						)
						axlVisibleUpdate(t)
						tOutlineLayer = 'unbound
						tLayer = 'unbound
					)
					("F_clrTop"
						tLabelName = axlFormGetField(frmTT "F_popLabelName")
						if(tLabelName == "package_geo1" then
							tLayerName = "PIN/TOP"
							tLayerOutline = "PIN/TOP"
						else
							tLayerName = strcat(axlFormGetField(frmTT "F_popLabelLayer") "TOP")
							tLayerOutline = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "TOP")
						)
						if(axlIsVisibleLayer(tLayerName) then
							axlVisibleLayer(tLayerName nil)
							axlVisibleLayer(tLayerOutline nil)
							axlFormSetField(frmTT "F_clrTop" 0)
							axlFormSetField(frmTT "F_clrTop" nil)
						else
							axlSetActiveLayer(tLayerName)
							axlVisibleLayer(tLayerName t)
							axlVisibleLayer(tLayerOutline t)
							axlFormSetField(frmTT "F_clrTop" fnTTGetLayerColor(tLayerName))
							axlFormSetField(frmTT "F_clrTop" t)
						)
						axlVisibleUpdate(t)
						tLabelName = 'unbound
						tLayerName = 'unbound
						tLayerOutline = 'unbound
					)
					("F_clrBottom"
						tLabelName = axlFormGetField(frmTT "F_popLabelName")
						if(tLabelName == "package_geo1" then
							tLayerName = "PIN/BOTTOM"
							tLayerOutline = "PIN/BOTTOM"
						else
							tLayerName = strcat(axlFormGetField(frmTT "F_popLabelLayer") "BOTTOM")
							tLayerOutline = strcat(axlFormGetField(frmTT "F_popOutlineLayer") "BOTTOM")
						)
						if(axlIsVisibleLayer(tLayerName) then
							axlVisibleLayer(tLayerName nil)
							axlVisibleLayer(tLayerOutline nil)
							axlFormSetField(frmTT "F_clrBottom" 0)
							axlFormSetField(frmTT "F_clrBottom" nil)
						else
							axlSetActiveLayer(tLayerName)
							axlVisibleLayer(tLayerName t)
							axlVisibleLayer(tLayerOutline t)
							axlFormSetField(frmTT "F_clrBottom" fnTTGetLayerColor(tLayerName))
							axlFormSetField(frmTT "F_clrBottom" t)
						)
						axlVisibleUpdate(t)
						tLabelName = 'unbound
						tLayerName = 'unbound
						tLayerOutline = 'unbound
					)
					("F_chkMirrorBottomOnly"
						if(frmTT->curValue then
							axlFormSetField(frmTT "F_popBottomLongSideX" 0.0)
							axlFormSetField(frmTT "F_popBottomLongSideY" 270.0)
						else
							axlFormSetField(frmTT "F_popBottomLongSideX" 0.0)
							axlFormSetField(frmTT "F_popBottomLongSideY" 90.0)
						)
					)
					;("F_rdoNoMirror"
					;	axlFormSetField(frmTT "F_popBottomLongSideX" 0.0)
					;	axlFormSetField(frmTT "F_popBottomLongSideY" 90.0)
					;)
					("F_ckbRotateText" 
						unless(axlFormGetField(frmTT "F_ckbRotateText") 
							axlFormSetField(frmTT "F_ckbFitText" nil)
						)
						fnTTUpdateFormField(frmTT)
					)
					("F_ckbModifyTextBlk" 
						if(axlFormGetField(frmTT "F_ckbModifyTextBlk") then
							axlFormSetField(frmTT "F_rdoTextFitByBlock" t)
							;axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" nil) 
							;axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" nil) 
							;axlFormSetFieldEditable(frmTT "F_barMinTextBlock" t)
							;axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil)
							xMinBlock = axlFormGetField(frmTT "F_barMinTextBlock")
							xMaxBlock = axlFormGetField(frmTT "F_barMaxTextBlock")
							frmTT->blockInfo = fnTTGetBlockInfo(xMinBlock xMaxBlock "block_mode")
						else
							axlFormSetField(frmTT "F_ckbFitText" nil)
						)
						fnTTUpdateFormField(frmTT)
					)
					("F_ckbCenterText" 
						if(frmTT->curValue then 
							axlFormSetFieldEditable(frmTT "F_iptDx" t) 
							axlFormSetFieldEditable(frmTT "F_iptDy" t)
						else
							axlFormSetField(frmTT "F_ckbFitText" nil) 
							axlFormSetFieldEditable(frmTT "F_iptDx" nil) 
							axlFormSetFieldEditable(frmTT "F_iptDy" nil)
						)
						fnTTUpdateFormField(frmTT)
					) 
					("F_ckbFitText" 
						if(axlFormGetField(frmTT "F_ckbFitText") then 
							axlFormSetField(frmTT "F_ckbRotateText" t)
							axlFormSetField(frmTT "F_ckbModifyTextBlk" t)
							axlFormSetField(frmTT "F_ckbCenterText" t) 
							axlFormSetFieldEditable(frmTT "F_iptDx" t)
							axlFormSetFieldEditable(frmTT "F_iptDy" t)
							
							axlFormSetField(frmTT "F_rdoTextFitByHeight" t)
							;axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" t) 
							;axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" t) 
							;axlFormSetFieldEditable(frmTT "F_barMinTextBlock" nil)
							;axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil)
							nMinHeight = axlFormGetField(frmTT "F_iptMinTextHeight")
							nMaxHeight = axlFormGetField(frmTT "F_iptMaxTextHeight")
							frmTT->blockInfo = fnTTGetBlockInfo(nMinHeight nMaxHeight "height_mode")
						else
							when(axlFormGetField(frmTT "F_ckbModifyTextBlk")
								axlFormSetField(frmTT "F_rdoTextFitByBlock" t)
								;axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" nil) 
								;axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" nil) 
								;axlFormSetFieldEditable(frmTT "F_barMinTextBlock" t)
								;axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil)
								xMinBlock = axlFormGetField(frmTT "F_barMinTextBlock")
								xMaxBlock = axlFormGetField(frmTT "F_barMaxTextBlock")
								frmTT->blockInfo = fnTTGetBlockInfo(xMinBlock xMaxBlock "block_mode")
							)
						)
						fnTTUpdateFormField(frmTT)
					) 
					("F_rdoTextRotationLongSide" 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideX" t) 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideY" t) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideX" t) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideY" t)
						axlFormSetFieldEditable(frmTT "F_popForceAngle" nil)
					)
					("F_rdoTextRotationForceAngle" 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideY" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideY" nil)
						axlFormSetFieldEditable(frmTT "F_popForceAngle" t)
					) 
					("F_rdoTextRotationLabelAngle" 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popTopLongSideY" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideX" nil) 
						axlFormSetFieldEditable(frmTT "F_popBottomLongSideY" nil)
						axlFormSetFieldEditable(frmTT "F_popForceAngle" nil)
					)
					("F_rdoTextFitByHeight"
						if(frmTT->curValue then 
							axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" t) 
							axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" t) 
							axlFormSetFieldEditable(frmTT "F_barMinTextBlock" nil)
							axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil)
						else
							axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" nil) 
							axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" nil) 
							axlFormSetFieldEditable(frmTT "F_barMinTextBlock" t)
							axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" t)
						) 
						nMinHeight = axlFormGetField(frmTT "F_iptMinTextHeight")
						nMaxHeight = axlFormGetField(frmTT "F_iptMaxTextHeight")
						frmTT->blockInfo = fnTTGetBlockInfo(nMinHeight nMaxHeight "height_mode")
					)
					("F_iptMinTextHeight" 
						when(frmTT->curValue > axlFormGetField(frmTT "F_iptMaxTextHeight")
							axlUIWPrint(frmTT "Error: Min height must not be greater than max height!") 
							nMaxValue = axlFormGetField(frmTT "F_iptMaxTextHeight")
							axlFormSetField(frmTT "F_iptMinTextHeight" nMaxValue)
						) 
						nMinHeight = axlFormGetField(frmTT "F_iptMinTextHeight")
						nMaxHeight = axlFormGetField(frmTT "F_iptMaxTextHeight")
						frmTT->blockInfo = fnTTGetBlockInfo(nMinHeight nMaxHeight "height_mode")
					)
					("F_iptMaxTextHeight" 
						when(frmTT->curValue < axlFormGetField(frmTT "F_iptMinTextHeight")
							axlUIWPrint(frmTT "Error: Max height  must not be smaller than min height!") 
							nMinValue = axlFormGetField(frmTT "F_iptMinTextHeight")
							axlFormSetField(frmTT "F_iptMaxTextHeight" nMinValue)
						) 
						nMinHeight = axlFormGetField(frmTT "F_iptMinTextHeight") 
						nMaxHeight = axlFormGetField(frmTT "F_iptMaxTextHeight") 
						frmTT->blockInfo = fnTTGetBlockInfo(nMinHeight nMaxHeight "height_mode")
					) 
					("F_rdoTextFitByBlock" 
						if(frmTT->curValue then 
							axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" nil) 
							axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" nil) 
							axlFormSetFieldEditable(frmTT "F_barMinTextBlock" t)
							axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" t)
						else
							axlFormSetFieldEditable(frmTT "F_iptMinTextHeight" t) 
							axlFormSetFieldEditable(frmTT "F_iptMaxTextHeight" t) 
							axlFormSetFieldEditable(frmTT "F_barMinTextBlock" nil)
							axlFormSetFieldEditable(frmTT "F_barMaxTextBlock" nil)
						) 
						xMinBlock = axlFormGetField(frmTT "F_barMinTextBlock")
						xMaxBlock = axlFormGetField(frmTT "F_barMaxTextBlock")
						frmTT->blockInfo = fnTTGetBlockInfo(xMinBlock xMaxBlock "block_mode")
					) 
					("F_barMinTextBlock" 
						when(axlFormGetField(frmTT "F_barMinTextBlock") > axlFormGetField(frmTT "F_barMaxTextBlock")
							axlUIWPrint(frmTT "Error: Min block must not be greater than max block!") 
							nMaxValue = axlFormGetField(frmTT "F_barMaxTextBlock")
							axlFormSetField(frmTT "F_barMinTextBlock" nMaxValue)
						) 
						xMinBlock = axlFormGetField(frmTT "F_barMinTextBlock")
						xMaxBlock = axlFormGetField(frmTT "F_barMaxTextBlock")
						frmTT->blockInfo = fnTTGetBlockInfo(xMinBlock xMaxBlock "block_mode")
					) 
					("F_barMaxTextBlock" 
						when(axlFormGetField(frmTT "F_barMaxTextBlock") > length(frmTT->textList) 
							printf("W-The maximum text block value is %d\n" length(frmTT->textList)) 
							axlFormSetField(frmTT "F_barMaxTextBlock" length(frmTT->textList))
						) 
						when(axlFormGetField(frmTT "F_barMaxTextBlock") < axlFormGetField(frmTT "F_barMinTextBlock") 
							axlUIWPrint(frmTT "Error: Max block  must not be smaller than min block!") 
							nMinValue = axlFormGetField(frmTT "F_barMinTextBlock") 
							axlFormSetField(frmTT "F_barMaxTextBlock" nMinValue)
						) 
						xMinBlock = axlFormGetField(frmTT "F_barMinTextBlock") 
						xMaxBlock = axlFormGetField(frmTT "F_barMaxTextBlock")
						frmTT->blockInfo = fnTTGetBlockInfo(xMinBlock xMaxBlock "block_mode")
					)
					("F_barTextBlk"
						fnTTUpdateTextBlkValue(frmTT t)
					)
					("F_iptWidth"
						fnTTUpdateTextBlkValue(frmTT nil)
					)
					("F_iptHeight"
						fnTTUpdateTextBlkValue(frmTT nil)
					)
					("F_iptLineSpace"
						fnTTUpdateTextBlkValue(frmTT nil)
					)
					("F_iptPhotoWidth"
						fnTTUpdateTextBlkValue(frmTT nil)
					)
					("F_iptCharSpace"
						fnTTUpdateTextBlkValue(frmTT nil)
					)
					("F_btnExecute" 
						if(axlOKToProceed() then 
							if(frmTT->commandState == "IDLE" then 
								axlFormSetFieldEditable(frmTT "F_btnExecute" nil)
								axlCancelEnterFun() 
								axlUIPopupSet(nil) 
								axlClearDynamics()
								axlUIWPrint(frmTT "Please select components...")
								frmTT->commandState = "SELECT_AND_EXECUTE"
								printf("M-Please select components...\n")
								axlShell("tt run")
								;fnTTStart()
								axlFormSetFieldEditable(frmTT "F_btnExecute" t)
								axlUIWPrint(frmTT "Execute finish.")
							)
						else 
							axlUIWPrint(frmTT "E - Finish current command first!")
						)
					)
					(("F_btnExit" "done" "cancel")
						fnTTExit(frmTT)
					) 
				)
				when(frmTT->doneState == 3 && not(frmTT->xkClosing) && fboundp('fnTTExit)
					fnTTExit(frmTT)
				)
			)
		)

		frmTT = fnTTFormBuild() 
		fnTTSetVariables(frmTT)
		fnTTSetFormField(frmTT)
 frmTT->xkRestoreView = axlFormGetField(frmTT "F_chkRestoreView")
		putd('fnTTFormBuild nil)
		putd('fnTTSetVariables nil)
		putd('fnTTSetFormField nil)
			
		fnTTStart()
		
		
	)
)
		