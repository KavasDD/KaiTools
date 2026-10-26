# SPDX-License-Identifier: GPL-3.0-only
# Minimal OOXML workbook writer, pure Tcl 8.6. ZIP uses stored entries so no
# external zip executable, Excel automation or Python is needed in Capture.
proc ::bomtool::xml {s} {
    if {[regexp {[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]} $s]} {
        error "Excel export: text contains a control character that XML cannot represent."
    }
    return [string map [list & &amp\; < &lt\; > &gt\; \" &quot\; ' &apos\;] $s]
}
proc ::bomtool::le {n bytes} {
    set hex ""
    for {set i 0} {$i < $bytes} {incr i} {
        append hex [format %02x [expr {($n >> (8*$i)) & 255}]]
    }
    return [binary format H* $hex]
}
proc ::bomtool::zipStored {path entries} {
    set f [open $path {WRONLY CREAT EXCL}]; set central ""; set count 0
    fconfigure $f -translation binary -encoding binary
    try {
        dict for {name text} $entries {
            set name [encoding convertto utf-8 $name]
            set data [encoding convertto utf-8 $text]
            set size [string length $data]; set crc [zlib crc32 $data]
            set offset [tell $f]; set len [string length $name]
            # Fixed valid DOS date: 1980-01-01; UTF-8 flag; no compression.
            set header [le 0x04034b50 4]
            foreach n [list 20 2048 0 0 33] { append header [le $n 2] }
            foreach n [list $crc $size $size] { append header [le $n 4] }
            append header [le $len 2][le 0 2]$name
            puts -nonewline $f $header$data
            append central [le 0x02014b50 4]
            foreach n [list 20 20 2048 0 0 33] { append central [le $n 2] }
            foreach n [list $crc $size $size] { append central [le $n 4] }
            foreach n [list $len 0 0 0 0] { append central [le $n 2] }
            append central [le 0 4][le $offset 4]$name
            incr count
        }
        set start [tell $f]
        puts -nonewline $f $central
        puts -nonewline $f [le 0x06054b50 4][le 0 2][le 0 2][le $count 2][le $count 2][le [string length $central] 4][le $start 4][le 0 2]
    } finally { close $f }
}
proc ::bomtool::excelColumn {number} {
    set out ""
    while {$number > 0} {
        incr number -1
        set out [format %c [expr {65+$number%26}]]$out
        set number [expr {$number/26}]
    }
    return $out
}
proc ::bomtool::sheetXml {headers rows {numericColumns {}}} {
    set height [expr {[llength $rows]+1}]; set width [llength $headers]
    if {$height > 1048576 || $width > 16384} { error "Excel sheet exceeds row/column limits." }
    set last [excelColumn $width]
    set s {<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">}
    append s "<dimension ref=\"A1:$last$height\"/>"
    append s {<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>}
    for {set c 1} {$c <= $width} {incr c} {
        set label [lindex $headers [expr {$c-1}]]
        set w 23
        if {$label in [list "序号" "数量" "源行号"]} { set w 9 }
        if {$label in [list "位号" Reference]} { set w 52 }
        if {$label in [list "具体原因" "本次处理" "建议处理" "备注" "原始值" "分组键" "不焊接依据"]} { set w 55 }
        append s "<col min=\"$c\" max=\"$c\" width=\"$w\" customWidth=\"1\"/>"
    }
    append s {</cols><sheetData>}
    set r 0
    foreach row [linsert $rows 0 $headers] {
        incr r; set c 0
        if {[llength $row] != $width} { error "Excel export: column count mismatch at row $r" }
        append s "<row r=\"$r\">"
        foreach value $row {
            incr c; set address [excelColumn $c]$r
            if {[string length $value] > 32767} { error "Excel cell $address exceeds 32767 characters; export stopped without truncation." }
            set style [expr {$r == 1 ? 1 : 0}]
            if {$r > 1 && $c in $numericColumns && [regexp {^[0-9]+(?:\.[0-9]+)?$} $value]} {
                append s "<c r=\"$address\" s=\"$style\"><v>$value</v></c>"
            } else {
                # Explicit text preserves 0402 and prevents BOM text becoming formulas.
                append s "<c r=\"$address\" s=\"$style\" t=\"inlineStr\"><is><t xml:space=\"preserve\">[xml $value]</t></is></c>"
            }
        }
        append s {</row>}
    }
    append s "</sheetData><autoFilter ref=\"A1:$last$height\"/></worksheet>"
    return $s
}
proc ::bomtool::writeWorkbook {path sheets} {
    set entries {}
    set types {<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>}
    set book {<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>}
    set rels {<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">}
    set id 0
    foreach sheet $sheets {
        incr id
        lassign $sheet name headers rows numericColumns
        append types "<Override PartName=\"/xl/worksheets/sheet$id.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        append book "<sheet name=\"[xml $name]\" sheetId=\"$id\" r:id=\"rId$id\"/>"
        append rels "<Relationship Id=\"rId$id\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet$id.xml\"/>"
        dict set entries xl/worksheets/sheet$id.xml [sheetXml $headers $rows $numericColumns]
    }
    append types {</Types>}; append book {</sheets></workbook>}
    append rels {<Relationship Id="styles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>}
    dict set entries {[Content_Types].xml} $types
    dict set entries xl/workbook.xml $book
    dict set entries xl/_rels/workbook.xml.rels $rels
    dict set entries _rels/.rels {<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="workbook" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>}
    dict set entries xl/styles.xml {<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF245A81"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>}
    file mkdir [file dirname $path]
    set tempPath "$path.[pid].[clock clicks].tmp"
    try {
        zipStored $tempPath $entries
        file rename -force $tempPath $path
    } finally { if {[file exists $tempPath]} { file delete $tempPath } }
    return $path
}
