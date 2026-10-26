# SPDX-License-Identifier: GPL-3.0-only
# BOM Workbench: pure Tcl 8.6; no Capture commands or external packages here.
namespace eval ::bomtool {
    variable version 1.3.10
    variable nativeHeaders {Reference Value {PCB Footprint} Dsecription Option EMPTY MATERIAL}
    variable lineItemDefinition "\{Reference\}\t\{Value\}\t\{PCB Footprint\}\t\{Dsecription\}\t\{Option\}\t\{EMPTY\}\t\{MATERIAL\}"
}

proc ::bomtool::get {d key {default ""}} {
    if {[dict exists $d $key]} { return [dict get $d $key] }
    return $default
}
proc ::bomtool::unique {xs} { return [lsort -dictionary -unique $xs] }
proc ::bomtool::clean {s} { return [string trim $s " \t\r\n\ufeff"] }
proc ::bomtool::num {n} { return [format %.12g $n] }

# Return {physical_start_line fields} records. Handles escaped quotes/newlines.
proc ::bomtool::parseDelimited {text sep} {
    set text [string map [list "\r\n" "\n" "\r" "\n"] $text]
    set records {}; set fields {}; set field ""; set quoted 0; set closed 0
    set line 1; set start 1; set n [string length $text]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $text $i]
        if {$quoted} {
            if {$c eq "\""} {
                if {[string index $text [expr {$i+1}]] eq "\""} {
                    append field "\""; incr i
                } else { set quoted 0; set closed 1 }
            } else { append field $c }
        } elseif {$c eq $sep || $c eq "\n"} {
            lappend fields $field; set field ""; set closed 0
            if {$c eq "\n"} {
                lappend records [list $start $fields]; set fields {}
                set start [expr {$line+1}]
            }
        } elseif {$c eq "\"" && $field eq "" && !$closed} {
            set quoted 1
        } elseif {$closed && [string trim $c] ne ""} {
            error "CSV: unexpected character after quote at line $line"
        } elseif {!$closed} { append field $c }
        if {$c eq "\n"} { incr line }
    }
    if {$quoted} { error "CSV: unclosed quote at line $start" }
    if {$field ne "" || [llength $fields] || $closed} {
        lappend fields $field; lappend records [list $start $fields]
    }
    return $records
}
proc ::bomtool::readText {path {encoding utf-8}} {
    set f [open $path r]
    try { fconfigure $f -encoding $encoding -translation auto; return [string trimleft [read $f] \ufeff] } finally { close $f }
}
proc ::bomtool::writeCsv {path headers rows} {
    file mkdir [file dirname $path]
    set f [open $path w]
    try {
        fconfigure $f -encoding utf-8 -translation crlf
        puts -nonewline $f \ufeff
        foreach row [linsert $rows 0 $headers] {
            set cells {}
            foreach cell $row { lappend cells "\"[string map [list \" \"\"] $cell]\"" }
            puts $f [join $cells ,]
        }
    } finally { close $f }
    return $path
}
proc ::bomtool::refs {text} {
    set text [string toupper [string map [list \uff0c , \uff1b \; \u3001 , \uff5e ~] $text]]
    set result {}
    foreach token [regexp -all -inline {[^,;\s]+} $text] {
        if {[regexp {^([A-Z_]+)([0-9]+)[~\-]([A-Z_]*)([0-9]+)$} $token -> p a q b] && ($q eq "" || $p eq $q)} {
            scan $a %d a; scan $b %d b
            if {$b < $a || $b-$a > 10000} { error "Invalid reference range: $token" }
            for {set j $a} {$j <= $b} {incr j} { lappend result $p$j }
        } else {
            if {![regexp {^[A-Z][A-Z0-9_./+()\-]*$} $token]} { error "Invalid reference: $token" }
            lappend result $token
        }
    }
    return $result
}
proc ::bomtool::category {ref} {
    # Longest prefixes first: PCI/PCIE precede PC, CH/CHK/CHOKE precede C.
    foreach {prefix cat} {
        RTCBAT batt CHOKE ind JGPIO conn PCIE conn CHK ind SATA conn USB conn COM conn LED diode PFB ind
        PCI conn PC cap PR res PL ind FB ind CH ind PQ mos QN mos
        PU ic AU ic C cap R res L ind D diode Q mos U ic J conn
    } {
        if {[string match ${prefix}* [string toupper $ref]]} { return $cat }
    }
    return other
}
proc ::bomtool::categoryCandidates {rows} {
    set families {}
    foreach row $rows {
        set ref [string toupper [get $row ref]]
        if {![regexp {^([A-Z_]+)([0-9]+)$} $ref -> prefix number]} { continue }
        if {[dict get [deviceInfo $row $ref] category] ne "other"} { continue }
        if {[llength [exclusions $ref $row]]} { continue }
        dict lappend families $prefix [expr {$number + 0}]
    }
    set candidates {}
    dict for {prefix numbers} $families {
        set numbers [lsort -integer -unique $numbers]
        if {[llength $numbers] < 8 || [lindex $numbers end] - [lindex $numbers 0] + 1 != [llength $numbers]} { continue }
        set refs {}
        foreach number $numbers { lappend refs ${prefix}$number }
        lappend candidates [list $prefix $refs]
    }
    return [lsort -dictionary -index 0 $candidates]
}
proc ::bomtool::applyCategoryOverrides {rows overrides} {
    set out {}
    foreach row $rows {
        set ref [string toupper [get $row ref]]
        if {[dict exists $overrides $ref]} { dict set row category_override [dict get $overrides $ref] }
        lappend out $row
    }
    return $out
}
proc ::bomtool::footprint {s} {
    set s [string toupper [clean $s]]
    if {[regexp {^(?:C|R|L|FB)?(01005|0201|0402|0603|0805|1206|1210|1812|2010|2512)$} $s -> size]} { return $size }
    return $s
}
proc ::bomtool::column {name} {
    set name [string tolower [string map [list " " "" _ "" - ""] [clean $name]]]
    switch -- $name {
        reference - references - refdes - designator - designators - partreference - \u4f4d\u53f7 { return ref }
        value - comment - \u503c - \u53c2\u6570 { return value }
        pcbfootprint - footprint - package - \u5c01\u88c5 { return footprint }
        option - fitted - populate { return option }
        empty { return empty }
        dnp - donotpopulate { return dnp }
        material - dielectric - \u6750\u8d28 { return material }
        description - dsecription - \u63cf\u8ff0 { return description }
        voltage - ratedvoltage { return voltage }
        tolerance { return tolerance }
        default { return "" }
    }
}
proc ::bomtool::readBom {path {encoding utf-8}} {
    if {[string tolower [file extension $path]] eq ".xlsx"} { error "Export the worksheet as CSV first (XLSX is not a text BOM)." }
    set text [readText $path $encoding]
    set sep ,
    # Capture's native .BOM.txt is tab-delimited, including its preamble.
    if {[string first \t $text] >= 0} { set sep \t }
    set records [parseDelimited $text $sep]
    set columns {}; set header -1
    foreach record $records {
        lassign $record line cells
        set candidate {}; set i 0
        foreach c $cells { set k [column $c]; if {$k ne ""} { dict set candidate $k $i }; incr i }
        if {[dict exists $candidate ref] && [dict exists $candidate value] && [dict exists $candidate footprint]} {
            set columns $candidate; set header $line; break
        }
    }
    if {$header < 0} { set columns [dict create ref 0 value 1 footprint 2 description 3 option 4 empty 5 material 6] }
    set out {}
    foreach record $records {
        lassign $record line cells
        if {$line <= $header || [string trim [join $cells ""]] eq ""} { continue }
        set ref [clean [lindex $cells [dict get $columns ref]]]
        if {[column $ref] eq "ref" && [column [lindex $cells [dict get $columns value]]] eq "value"} { continue }
        if {[regexp {^_+$} $ref]} { continue }
        set d [dict create row $line file [file tail $path]]
        dict for {key index} $columns { dict set d $key [clean [lindex $cells $index]] }
        dict set d refs [refs $ref]
        if {$ref eq ""} { dict set d input_issue MISSING_REFERENCE }
        lappend out $d
    }
    if {![llength $out]} { error "No BOM records in $path" }
    return $out
}
proc ::bomtool::ncEvidence {row} {
    set evidence {}
    set value [string toupper [string map [list {&#x20;} " " {&#32;} " " {&nbsp;} " "] [get $row value]]]
    set opt [string toupper [clean [get $row option]]]
    set dnp [string toupper [clean [get $row dnp]]]
    if {[regexp {(^|[/,;_\s-])(NC|DNP|DNI|DNE|NS|NO[ -]?STUFF|NOT[ -]?FITTED)($|[/,;_\s-])} $value -> before marker]} {
        lappend evidence "Value中含独立不焊标记 $marker（原值：[get $row value]）"
    }
    if {$opt in {NS NC DNP DNI DNE NO FALSE {NOT FITTED} {NOT STUFFED}}} {
        lappend evidence "Option=[get $row option]（装配选项标记为不焊接）"
    }
    # Capture may synthesize DNP=YES from CIS state. Report the source, not
    # the derived value as though it were an original schematic property.
    if {[get $row original_dnp] ne ""} { set dnp [string toupper [clean [get $row original_dnp]]] }
    if {$dnp in {1 YES TRUE NC DNP NS} && ([get $row variant_nc] ne "1" || [get $row original_dnp] ne "")} {
        lappend evidence "DNP=[get $row original_dnp [get $row dnp]]（禁止装配属性）"
    }
    foreach key {value option} label {Value Option} {
        if {[regexp {\u4e0d\u710a|\u4e0d\u8d34|\u4e0d\u88c5} [get $row $key] marker]} {
            lappend evidence "$label=[get $row $key]（含中文标记：$marker）"
        }
    }
    foreach source [get $row variant_nc_sources] {
        lassign $source prop val
        lappend evidence "Capture/CIS属性 $prop=$val（匹配设计的不装配标记）"
    }
    return $evidence
}
proc ::bomtool::exclusions {ref row} {
    set out {}; set value [string toupper [string map [list {&#x20;} " " {&#32;} " " {&nbsp;} " "] [get $row value]]]
    if {[llength [ncEvidence $row]]} { lappend out NC }
    set fp [string toupper [get $row footprint]]
    if {[regexp {^(TP|TESTPOINT)([0-9_]|$)} $ref] || [regexp {^(TP|TESTPOINT|TEST_POINT)([0-9_]|$)} $value] ||
        [regexp {^(TP[0-9_]|ICTPAD|PAD_TEST|TESTPOINT)} $fp]} { lappend out TP }
    if {[regexp {^(MARK|FID|FIDUCIAL)([0-9_]|$)} $ref] ||
        [regexp {^(MARK|FIDUCIAL)([0-9_ -]|$)} "$value"] || [regexp {^(MARK|FIDUCIAL)([0-9_ -]|$)} $fp]} { lappend out MARK }
    if {[regexp {^(HOLE|BOSS|MH)([0-9_]|$)} $ref] ||
        [regexp {(^|[/_ ])(NP)?HOLE([0-9_ /]|$)} "$value $fp"] ||
        [regexp {^(MOUNTING_HOLE|SCREW_HOLE)} $fp]} { lappend out HOLE }
    return $out
}

# Parsed specs stay outside norm_value. Unknown suffixes stay IN norm_value;
# wattage/current/part suffixes must never disappear silently during merging.
proc ::bomtool::valueInfo {cat value {material ""} {footprint ""} {voltage ""} {tolerance ""}} {
    set raw [clean [string map [list \u00b5 u \u03bc u \u03a9 OHM \u2126 OHM] $value]]
    set s [string toupper $raw]
    set result [dict create norm $s number "" voltage "" tolerance "" material "" residual "" parsed 0]
    if {$cat ni {cap res ind}} { return $result }
    set tail ""; set number ""; set unit ""
    if {$cat eq "cap" && [regexp {^([0-9]*\.?[0-9]+)\s*([PNU]?)(?:F)?($|[/,;_ \-].*)} $s -> n p tail]} {
        # Bare capacitor numbers are ambiguous; require an explicit unit.
        if {[regexp {^[0-9]*\.?[0-9]+\s*([PNU]F?|F)} $s]} {
            set scale [dict get [dict create P 1 N 1000 U 1000000 "" 1000000000000] $p]
            set number [expr {double($n)*$scale}]; set unit pF
        }
    } elseif {$cat eq "res"} {
        if {[regexp {^([0-9]+)([RKM])([0-9]+)(?:OHMS?|R)?($|[/,;_ \-].*)} $s -> a p b tail]} {
            set scale [dict get [dict create R 1 K 1000 M 1000000] $p]
            set number [expr {double("$a.$b")*$scale}]
        } elseif {[regexp {^([0-9]*\.?[0-9]+)\s*([RKM]?)(?:OHMS?|R)?($|[/,;_ \-].*)} $s -> n p tail]} {
            set scale [dict get [dict create "" 1 R 1 K 1000 M 1000000] $p]
            set number [expr {double($n)*$scale}]
        }
        # Preserve SI distinction: mOhm/mR denotes milliohm; M denotes megaohm.
        if {$number ne "" && [regexp {^[0-9]*\.?[0-9]+\s*m(?:[Oo][Hh][Mm]|R)} $raw]} { set number [expr {$number/1.0e9}] }
        set unit Ohm
    } elseif {$cat eq "ind" && [regexp {^([0-9]*\.?[0-9]+)\s*([PNUM]?)H($|[/,;_ \-].*)} $s -> n p tail]} {
        set number [expr {double($n)*[dict get [dict create P .001 N 1 U 1000 M 1000000 "" 1000000000] $p]}]
        set unit nH
    }
    if {$number eq ""} { return $result }
    dict set result parsed 1; dict set result number [num $number]
    set volt ""; set tol ""; set mat ""
    # Support both 6.3V and the common Capture spelling 6V3.
    if {[regexp {([0-9]+)V([0-9]+)} $tail full a b]} {
        set volt [num "$a.$b"]; set tail [string map [list $full ""] $tail]
    }
    if {[regexp {([0-9]*\.?[0-9]+)\s*V} $tail full v]} {
        set volt [num $v]; set tail [string map [list $full ""] $tail]
    }
    if {[regexp {([0-9]*\.?[0-9]+)\s*%} $tail full t]} {
        set tol [num $t]; set tail [string map [list $full ""] $tail]
    } elseif {[regexp {(^|[/,_ -])([BDFGJKM])($|[/,_ -])} $tail full before code after]} {
        set tol [dict get [dict create B .1 D .5 F 1 G 2 J 5 K 10 M 20] $code]
        set tail [string map [list $full "$before$after"] $tail]
    }
    if {[regexp {C0G|COG|NP0|NPO|X7R|X5R|Y5V|X8R|X7S|X6S|Z5U} $tail mat]} {
        set tail [string map [list $mat ""] $tail]
    }
    if {$mat eq ""} { set mat [string toupper [clean $material]] }
    if {$mat in {NP0 NPO COG}} { set mat C0G }
    if {$voltage ne "" && [regexp {^([0-9]*\.?[0-9]+)\s*V?$} [string toupper $voltage] -> v]} {
        if {$volt eq "" || $v > $volt} { set volt [num $v] }
    }
    if {$tolerance ne "" && [regexp {^([0-9]*\.?[0-9]+)\s*%?$} $tolerance -> t]} {
        if {$tol eq "" || $t < $tol} { set tol [num $t] }
    }
    set tail [string trim $tail " /,;_-"]
    # A literal full footprint in the value is redundant, not a new spec.
    if {$tail ne "" && [::bomtool::footprint $tail] eq [::bomtool::footprint $footprint]} { set tail "" }
    set norm [num $number]$unit
    if {$cat eq "res" && $number == 0} { set norm 0 }
    if {$tail ne ""} { append norm "|$tail" }
    dict set result norm $norm; dict set result residual $tail
    dict set result voltage $volt; dict set result tolerance $tol; dict set result material $mat
    return $result
}

proc ::bomtool::normalize {row ref {applyRules 1}} {
    set info [deviceInfo $row $ref]
    set cat [get $info category]; set fp [footprint [get $row footprint]]
    set warnings [get $info extra_warnings]
    set rawfp [string toupper [get $row footprint]]
    set excluded [exclusions $ref $row]
    if {$cat eq "res" && [regexp {^C[0-9]} $rawfp]} {
        if {[get $info number] ne "" && [get $info number] == 0} {
            lappend warnings WARN-0OHM-FOOTPRINT
        } else { lappend warnings WARN-CATEGORY-FOOTPRINT }
    } elseif {$cat eq "cap" && [regexp {^R[0-9]} $rawfp]} { lappend warnings WARN-CATEGORY-FOOTPRINT }
    if {($fp eq "" || [dict get $info norm] eq "") &&
        !("NC" in $excluded && [mountedValue [get $row value]] eq "")} { lappend warnings WARN-MISSING-FIELD }
    if {[get $info residual] ne ""} { lappend warnings WARN-UNPARSED-SUFFIX }
    if {$cat in {cap res ind} && ![get $info parsed] && [mountedValue [get $row value]] ne ""} { lappend warnings WARN-UNPARSED-VALUE }
    return [dict merge $row $info [dict create ref $ref category $cat norm_footprint $fp \
        group_key "$cat:$fp:[dict get $info norm]" exclusions $excluded warnings $warnings]]
}
proc ::bomtool::explode {rows {applyRules 1}} {
    set out {}
    foreach row $rows { foreach ref [dict get $row refs] { lappend out [normalize $row $ref $applyRules] } }
    return $out
}

proc ::bomtool::targetSpecs {parts} {
    set volt ""; set tol ""; set mat ""; set issues {}
    foreach p $parts {
        set v [get $p voltage]; set t [get $p tolerance]
        if {$v ne "" && ($volt eq "" || $v > $volt)} { set volt $v }
        if {$t ne "" && ($tol eq "" || $t < $tol)} { set tol $t }
    }
    # Material is retained as source data only; no ranking or requirement.
    set eligible {}
    foreach p $parts {
        set ok 1
        foreach k {voltage tolerance material} desired [list $volt $tol $mat] {
            if {$desired ne "" && [get $p $k] ne $desired} { set ok 0 }
        }
        if {$ok} { lappend eligible [get $p ref] }
    }
    set state OBSERVED_MATCH
    if {![llength $eligible]} { set state NEEDS_SELECTION }
    if {[llength $issues]} { set state REVIEW_MATERIAL; set eligible {} }
    return [dict create voltage $volt tolerance $tol material $mat eligible [unique $eligible] status $state issues $issues]
}
proc ::bomtool::displayValue {category norm} {
    if {[string match {CHOKE|*} $norm]} { return "共模电感 [displayValue $category [string range $norm 6 end]]" }
    if {[string match {MODEL|*} $norm]} { return [string range $norm 6 end] }
    if {[string match {BEAD-MODEL|*} $norm]} { return "磁珠 [string range $norm 11 end]" }
    if {[string match {NTC|*} $norm]} { return "NTC热敏电阻 [displayValue res [string range $norm 4 end]]" }
    if {[string match {LED|*} $norm]} {
        set color [string range $norm 4 end]
        return "LED [get [dict create GREEN 绿色 RED 红色] $color $color]"
    }
    if {[string match {BEAD|*} $norm]} {
        set fields [lrange [split $norm |] 1 end]; set out "磁珠 [lindex $fields 0]"
        foreach field [lrange $fields 1 end] {
            if {[regexp {^([0-9.eE+\-]+)Hz$} $field -> n]} {
                if {$n >= 1000000} { set field "[num [expr {$n/1000000.0}]]MHz" }
                append out " / 测试频率$field"
            } elseif {[regexp {^[0-9.eE+\-]+A$} $field]} { append out " / 最大电流$field"
            } else { append out " / $field" }
        }
        return $out
    }
    if {[regexp {^(.+)\|(L[0-9]{6})$} $norm -> base hint]} { return "[displayValue $category $base] / 封装简码$hint" }
    # norm_value uses pF / Ohm / nH for exact, readable, stable keys.
    if {[regexp {^([0-9.eE+\-]+)(pF|Ohm|nH)$} $norm -> n unit]} {
        if {$unit eq "pF"} {
            if {$n >= 1000000} { return "[num [expr {$n/1000000.0}]]uF" }
            if {$n >= 1000} { return "[num [expr {$n/1000.0}]]nF" }
        }
        if {$unit eq "Ohm"} {
            if {$n >= 1000000} { return "[num [expr {$n/1000000.0}]]MOhm" }
            if {$n >= 1000} { return "[num [expr {$n/1000.0}]]kOhm" }
        }
        if {$unit eq "nH" && $n >= 1000} { return "[num [expr {$n/1000.0}]]uH" }
    }
    if {$category eq "res" && $norm eq "0"} { return 0Ohm }
    return $norm
}
proc ::bomtool::preprocess {rows outdir} {
    set atoms [explode $rows]; set counts {}
    foreach p $atoms { dict incr counts [get $p ref] }
    set groups {}; set excluded {}; set warnings {}; set audit {}; set pending 0
    foreach row $rows {
        if {[get $row capture_conflict] ne ""} { incr pending }
        if {[get $row capture_differences] ne ""} {
            set code WARN-PACKAGE-METADATA
            if {[get $row capture_conflict] ne ""} { set code WARN-PACKAGE-CONFLICT }
            lappend warnings [list $code [get $row ref] [get $row row] "" [get $row value] [get $row footprint] [get $row capture_differences]]
        }
        if {[get $row input_issue] ne ""} {
            lappend warnings [list WARN-MISSING-REFERENCE "" [get $row row] "" [get $row value] [get $row footprint]]
            lappend excluded [list "" [get $row row] MISSING_REFERENCE [get $row value] [get $row footprint] ""]
        }
    }
    foreach p $atoms {
        set ref [get $p ref]; set key [get $p group_key]; set ws [get $p warnings]
        if {[dict get $counts $ref] > 1} { lappend ws WARN-DUPLICATE-REFERENCE }
        foreach w $ws { lappend warnings [list $w $ref [get $p row] [get $p category] [get $p value] [get $p footprint]] }
        set reason [get $p exclusions]
        if {[get $p capture_conflict] ne ""} { lappend reason PACKAGE_CONFLICT }
        if {[dict get $counts $ref] > 1} { lappend reason DUPLICATE_REFERENCE }
        # Empty identity must not merge unspecified parts into a purchasable item.
        if {"WARN-MISSING-FIELD" in $ws} { lappend reason MISSING_FIELD }
        lappend audit [list $ref [get $p row] [get $p category] [get $p footprint] [get $p norm_footprint] [get $p value] [get $p norm] $key [join $reason {;}]]
        if {[llength $reason]} {
            lappend excluded [list $ref [get $p row] [join $reason {;}] [get $p value] [get $p footprint] [join [ncEvidence $p] "；"]]
        } else { dict lappend groups $key $p }
    }
    set merged {}
    foreach key [lsort -dictionary [dict keys $groups]] {
        set parts [dict get $groups $key]; set first [lindex $parts 0]; set refs {}; set sourceRows {}; set rawValues {}; set ws {}
        foreach p $parts {
            lappend refs [get $p ref]; lappend sourceRows [get $p row]; lappend rawValues [get $p value]
            set ws [concat $ws [get $p warnings]]
        }
        set spec [targetSpecs $parts]; set status [get $spec status]
        if {"WARN-CATEGORY-FOOTPRINT" in $ws || "WARN-VALUE-FOOTPRINT" in $ws} { set status REVIEW_LIBRARY }
        set v [displayValue [get $first category] [get $first norm]]
        if {[get $spec voltage] ne ""} { append v /[get $spec voltage]V }
        if {[get $spec tolerance] ne ""} { append v /[get $spec tolerance]% }
        if {[get $spec material] ne ""} { append v /[get $spec material] }
        lappend merged [list [join [unique $refs] ,] [llength $refs] [get $first category] [get $first norm_footprint] \
            [get $first norm] $key $v [get $spec voltage] [get $spec tolerance] $status \
            [join [get $spec eligible] ,] [join [unique $sourceRows] ,] [join [unique $rawValues] { ; }] [join [get $spec issues] {;}] [join [unique $ws] {;}]]
    }
    set raw {}
    foreach row $rows {
        set originals [get $row capture_sections [list $row]]
        foreach original $originals {
            lappend raw $original
        }
    }
    # Restore traversal order so warning source-row numbers match the raw sheet.
    set indexed {}; foreach row $raw { lappend indexed [list [get $row row] $row] }
    set raw {}
    foreach pair [lsort -integer -index 0 $indexed] {
        set values {}; set row [lindex $pair 1]
        foreach k {ref value footprint description option empty material} { lappend values [get $row $k] }
        lappend raw $values
    }
    set sheets [list \
        [list "\u5408\u5e76BOM" {Reference Quantity device_category norm_footprint norm_value group_key RequiredValue Voltage Tolerance Status ObservedMatchingReferences SourceRows OriginalValues Issues Warnings} $merged {2 8 9}] \
        [list "\u8fc7\u6ee4\u6e05\u5355" {Reference SourceRow Reasons Value Footprint NCEvidence} $excluded {2}] \
        [list "\u544a\u8b66" {Code Reference SourceRow Category Value Footprint} $warnings {3}] \
        [list "\u5f52\u4e00\u5316\u660e\u7ec6" {Reference SourceRow Category OriginalFootprint NormFootprint OriginalValue NormValue group_key Exclusions} $audit {2}] \
        [list "\u539f\u59cbBOM" $::bomtool::nativeHeaders $raw {}]]
    set summary [list [list Version $::bomtool::version] [list InputRows [llength $raw]] [list InputReferences [llength $atoms]] \
        [list Groups [llength $merged]] [list Excluded [llength $excluded]] [list Warnings [llength $warnings]] \
        [list MaterialPolicy IGNORED] [list GroupKey {device_category:norm_footprint:norm_value}] \
        [list ClassificationPolicy PREFIX] [list MergePolicy DEFAULT] [list FilterPolicy DEFAULT] \
        [list WarningPolicy DEFAULT] [list InductorPolicy DEFAULT] [list SpecialCategoryPolicy DEFAULT] \
        [list FootprintPolicy NORMALIZED] [list ValuePolicy DEFAULT] [list SpecificationPolicy DEFAULT] \
        [list CaptureSectionPolicy DEFAULT] [list BatchClassificationPolicy DEFAULT]]
    lappend sheets [list "\u6c47\u603b" {Metric Value} $summary {}]
    set workbook [writeWorkbook [file join $outdir BOM.xlsx] [presentSheets $sheets]]
    return [dict create input_references [llength $atoms] groups [llength $merged] excluded [llength $excluded] warnings [llength $warnings] pending_packages $pending workbook $workbook outdir $outdir]
}
