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
        lappend evidence "Value\u4e2d\u542b\u72ec\u7acb\u4e0d\u710a\u6807\u8bb0 $marker\uff08\u539f\u503c\uff1a[get $row value]\uff09"
    }
    if {$opt in {NS NC DNP DNI DNE NO FALSE {NOT FITTED} {NOT STUFFED}}} {
        lappend evidence "Option=[get $row option]\uff08\u88c5\u914d\u9009\u9879\u6807\u8bb0\u4e3a\u4e0d\u710a\u63a5\uff09"
    }
    # Capture may synthesize DNP=YES from CIS state. Report the source, not
    # the derived value as though it were an original schematic property.
    if {[get $row original_dnp] ne ""} { set dnp [string toupper [clean [get $row original_dnp]]] }
    if {$dnp in {1 YES TRUE NC DNP NS} && ([get $row variant_nc] ne "1" || [get $row original_dnp] ne "")} {
        lappend evidence "DNP=[get $row original_dnp [get $row dnp]]\uff08\u7981\u6b62\u88c5\u914d\u5c5e\u6027\uff09"
    }
    foreach key {value option} label {Value Option} {
        if {[regexp {\u4e0d\u710a|\u4e0d\u8d34|\u4e0d\u88c5} [get $row $key] marker]} {
            lappend evidence "$label=[get $row $key]\uff08\u542b\u4e2d\u6587\u6807\u8bb0\uff1a$marker\uff09"
        }
    }
    foreach source [get $row variant_nc_sources] {
        lassign $source prop val
        lappend evidence "Capture/CIS\u5c5e\u6027 $prop=$val\uff08\u5339\u914d\u8bbe\u8ba1\u7684\u4e0d\u88c5\u914d\u6807\u8bb0\uff09"
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
    if {[string match {CHOKE|*} $norm]} { return "\u5171\u6a21\u7535\u611f [displayValue $category [string range $norm 6 end]]" }
    if {[string match {MODEL|*} $norm]} { return [string range $norm 6 end] }
    if {[string match {BEAD-MODEL|*} $norm]} { return "\u78c1\u73e0 [string range $norm 11 end]" }
    if {[string match {NTC|*} $norm]} { return "NTC\u70ed\u654f\u7535\u963b [displayValue res [string range $norm 4 end]]" }
    if {[string match {LED|*} $norm]} {
        set color [string range $norm 4 end]
        return "LED [get [dict create GREEN \u7eff\u8272 RED \u7ea2\u8272] $color $color]"
    }
    if {[string match {BEAD|*} $norm]} {
        set fields [lrange [split $norm |] 1 end]; set out "\u78c1\u73e0 [lindex $fields 0]"
        foreach field [lrange $fields 1 end] {
            if {[regexp {^([0-9.eE+\-]+)Hz$} $field -> n]} {
                if {$n >= 1000000} { set field "[num [expr {$n/1000000.0}]]MHz" }
                append out " / \u6d4b\u8bd5\u9891\u7387$field"
            } elseif {[regexp {^[0-9.eE+\-]+A$} $field]} { append out " / \u6700\u5927\u7535\u6d41$field"
            } else { append out " / $field" }
        }
        return $out
    }
    if {[regexp {^(.+)\|(L[0-9]{6})$} $norm -> base hint]} { return "[displayValue $category $base] / \u5c01\u88c5\u7b80\u7801$hint" }
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
            lappend excluded [list $ref [get $p row] [join $reason {;}] [get $p value] [get $p footprint] [join [ncEvidence $p] "\uff1b"]]
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


# SPDX-License-Identifier: GPL-3.0-only
# Interpret Value in device context. Subtypes are encoded in norm_value so the
# required category:footprint:value key still prevents incompatible merging.
proc ::bomtool::mountedValue {value} {
    set s [clean [string map [list {&#x20;} " " {&#32;} " " {&nbsp;} " "] $value]]
    set token {NC|DNP|DNI|DNE|NS}
    while {[regsub -nocase "^($token)(\$|\[/,;_ \\-\]+)" $s "" next]} { set s [clean $next] }
    while {[regsub -nocase "\[/,;_ \\-\]+($token)\$" $s "" next]} { set s [clean $next] }
    return $s
}
proc ::bomtool::deviceInfo {row ref} {
    set ref [string toupper $ref]
    set value [mountedValue [get $row value]]
    set s [string toupper $value]; set fp [footprint [get $row footprint]]
    set cat [category $ref]; set kind ""
    # Recognizable function takes precedence over a misleading single letter.
    if {[regexp {^(CONN?[_-]|CON_DIP_|HDR[-_]|HEADER)} $s]} { set cat conn }
    if {[regexp {^CPU(?:_FAN)?[0-9]+$} $ref]} { set cat conn }
    if {[regexp {^RTCBAT[0-9]+$} $ref]} { set cat batt }
    if {[regexp {^[XY][0-9]+$} $ref] && [regexp -nocase {MHz} $value]} { set cat xtal }
    if {[regexp {^AC[0-9]+$} $ref] && [regexp -nocase {^C(?:01005|0201|0402|0603|0805|1206|1210|1812|2010|2512)$} [clean [get $row footprint]]]} { set cat cap }
    if {[regexp {^AR[0-9]+$} $ref] && [regexp -nocase {^R(?:01005|0201|0402|0603|0805|1206|1210|1812|2010|2512)$} [clean [get $row footprint]]]} { set cat res }
    if {[regexp -nocase {NTC} $value]} {
        set cat res; set kind ntc
        regsub -all -nocase {NTC} $value "" value
        regsub -all {\(\s*\)|\[\s*\]} $value "" value
        set value [string trim $value " \t\r\n()[]{}_/,-"]
        set s [string toupper $value]
    }
    if {[regexp {^LED} $ref]} { set cat diode; set kind led }
    set override [get $row category_override]
    if {$override in {cap res ind diode mos ic conn batt xtal other}} { set cat $override }
    if {$cat eq "ind"} {
        if {[regexp {^(CHK|CHOKE|CH)} $ref]} { set kind choke
        } elseif {[regexp {^(P?FB|LV)} $ref] || [regexp -nocase {^FB[0-9]} [get $row footprint]] || [regexp -nocase {ohm} $value]} { set kind bead }
    }
    if {$kind eq "ntc"} { regsub -nocase {^NTC[_ /-]+} $value "" value }
    set info [valueInfo $cat $value [get $row material] [get $row footprint] [get $row voltage] [get $row tolerance]]
    set extraWarnings {}; set packageHint ""
    if {$kind eq "led"} {
        set colors [dict create G GREEN GREEN GREEN R RED RED RED]
        set color [get $colors $s $s]
        dict set info norm "LED|$color"; dict set info parsed 1
    } elseif {$kind eq "bead"} {
        # Values without explicit ohms are accepted only after bead recognition.
        set impedanceValue [string map [list \u03a9 OHM \u2126 OHM] $s]
        if {[regexp {^([0-9]*\.?[0-9]+)\s*(?:OHMS?|R)?($|[/,; ].*)} $impedanceValue -> ohms tail]} {
            dict set info number [num $ohms]; dict set info parsed 1
            set freq ""; set current ""
            if {[regexp {(^|[/,; ])([0-9]*\.?[0-9]+)\s*([KMG]?)HZ($|[/,; ])} $tail full before n unit after]} {
                set freq [num [expr {double($n)*[dict get [dict create "" 1 K 1000 M 1000000 G 1000000000] $unit]}]]
                set tail [string map [list $full "$before$after"] $tail]
            }
            if {[regexp {(^|[/,; ])([0-9]*\.?[0-9]+)\s*(M?)A($|[/,; ])} $tail full before n unit after]} {
                set current [num [expr {double($n)*($unit eq "M" ? .001 : 1)}]]
                set tail [string map [list $full "$before$after"] $tail]
            }
            set tail [string trim $tail " /,;"]
            set norm "BEAD|[num $ohms]Ohm"
            if {$freq ne ""} { append norm "|${freq}Hz" }
            if {$current ne ""} { append norm "|${current}A" }
            if {$tail ne ""} { append norm "|$tail" }
            dict set info norm $norm; dict set info residual $tail
            dict set info frequency $freq; dict set info current $current
        } else {
            dict set info norm "BEAD-MODEL|$s"
            if {[regexp {[A-Z]} $s] && [regexp {[0-9]} $s]} { dict set info parsed 1 }
        }
    } elseif {$kind eq "ntc"} {
        set norm [get $info norm]
        if {[regexp {\|B=[0-9]+$} $norm]} {
            set beta [string range $norm [expr {[string last | $norm]+1}] end]
            set norm [string range $norm 0 [expr {[string last | $norm]-1}]]
            dict set info residual ""
            append norm "|$beta"
        }
        dict set info norm "NTC|$norm"
    } elseif {$cat eq "ind"} {
        if {[regexp {^(?:[0-9]*\.?[0-9]+M_)?[0-9]*\.?[0-9]+A(?:/[0-9]*\.?[0-9]+A)?(?:_[0-9]*\.?[0-9]+M)?$} [get $info residual]]} {
            dict set info residual ""
        }
        if {[get $info parsed] && [regexp {^L[0-9]{6}$} [get $info residual]]} {
            set packageHint [get $info residual]
            # Keep the unknown physical equivalence in identity, but no warning.
            dict set info residual ""
        }
        if {![get $info parsed] && [regexp {[A-Z]} $s] && [regexp {[0-9]} $s]} {
            dict set info parsed 1
            dict set info norm "MODEL|$s"
        }
        if {$kind eq "choke"} { dict set info norm "CHOKE|[get $info norm]" }
    }
    if {$cat eq "res" && [get $info parsed] && [get $info residual] eq "04" && [regexp -- {-04$} $value]} {
        set packageHint 0402
        if {$fp eq "0402"} {
            dict set info norm [string range [get $info norm] 0 end-3]
            dict set info residual ""
        } elseif {$fp ne ""} {
            dict set info residual ""
            lappend extraWarnings WARN-VALUE-FOOTPRINT
        }
    }
    return [dict merge $info [dict create category $cat subtype $kind package_hint $packageHint extra_warnings $extraWarnings]]
}


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
        if {$label in [list "\u5e8f\u53f7" "\u6570\u91cf" "\u6e90\u884c\u53f7"]} { set w 9 }
        if {$label in [list "\u4f4d\u53f7" Reference]} { set w 52 }
        if {$label in [list "\u5177\u4f53\u539f\u56e0" "\u672c\u6b21\u5904\u7406" "\u5efa\u8bae\u5904\u7406" "\u5907\u6ce8" "\u539f\u59cb\u503c" "\u5206\u7ec4\u952e" "\u4e0d\u710a\u63a5\u4f9d\u636e"]} { set w 55 }
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


# SPDX-License-Identifier: GPL-3.0-only
# Chinese presentation is assembled into an ASCII-safe Capture deliverable.
proc ::bomtool::cn {code} {
    set names [dict create cap "\u7535\u5bb9" res "\u7535\u963b" ind "\u7535\u611f/\u78c1\u73e0" diode "\u4e8c\u6781\u7ba1" mos "MOS/\u4e09\u6781\u7ba1" ic "\u96c6\u6210\u7535\u8def" conn "\u8fde\u63a5\u5668" batt "\u7535\u6c60\u5ea7" xtal "\u6676\u632f" other "\u5176\u4ed6" \
        NC "\u4e0d\u710a\u63a5" TP "\u6d4b\u8bd5\u70b9" MARK "\u5b9a\u4f4d\u6807\u8bb0\u70b9" HOLE "\u87ba\u4e1d\u5b54/\u5b89\u88c5\u5b54" DUPLICATE_REFERENCE "\u4f4d\u53f7\u91cd\u590d\uff0c\u5df2\u9694\u79bb" MISSING_FIELD "\u7f3a\u5c11\u503c\u6216\u5c01\u88c5\uff0c\u5df2\u9694\u79bb" MISSING_REFERENCE "\u7f3a\u5c11\u4f4d\u53f7\uff0c\u5df2\u9694\u79bb" \
        PACKAGE_CONFLICT "\u540c\u4f4d\u53f7\u5206\u90e8\u5c5e\u6027\u51b2\u7a81\uff0c\u5f85\u6838\u5bf9\uff08\u4e0d\u7b49\u4e8e\u4e0d\u710a\u63a5\uff09" WARN-PACKAGE-CONFLICT "\u540c\u4f4d\u53f7\u5206\u90e8\u5173\u952e\u5c5e\u6027\u51b2\u7a81" WARN-PACKAGE-METADATA "\u540c\u4f4d\u53f7\u5206\u90e8\u8f85\u52a9\u5b57\u6bb5\u5dee\u5f02\u6216\u7a7a\u503c\u8865\u9f50" \
        OBSERVED_MATCH "\u89c4\u683c\u5df2\u5339\u914d" NEEDS_SELECTION "\u9700\u9009\u62e9\u6ee1\u8db3\u5408\u5e76\u89c4\u683c\u7684\u5668\u4ef6" REVIEW_LIBRARY "\u9700\u68c0\u67e5\u539f\u7406\u56fe\u5e93" \
        WARN-0OHM-FOOTPRINT "0\u03a9\u7535\u963b\u4f7f\u7528\u7535\u5bb9\u5c01\u88c5\u540d" WARN-CATEGORY-FOOTPRINT "\u4f4d\u53f7\u7c7b\u522b\u4e0e\u5c01\u88c5\u540d\u4e0d\u7b26" WARN-VALUE-FOOTPRINT "\u503c\u4e2d\u7684\u5c01\u88c5\u7b80\u7801\u4e0ePCB\u5c01\u88c5\u4e0d\u7b26" WARN-MISSING-FIELD "\u5668\u4ef6\u503c\u6216\u5c01\u88c5\u7f3a\u5931" \
        WARN-UNPARSED-SUFFIX "\u89c4\u683c\u540e\u7f00\u65e0\u6cd5\u5b8c\u6574\u8bc6\u522b" WARN-UNPARSED-VALUE "\u5668\u4ef6\u503c\u65e0\u6cd5\u89e3\u6790\u4e3a\u6807\u79f0\u6570\u503c" WARN-DUPLICATE-REFERENCE "\u540c\u4e00\u4f4d\u53f7\u91cd\u590d\u51fa\u73b0" WARN-MISSING-REFERENCE "\u8bb0\u5f55\u7f3a\u5c11\u4f4d\u53f7"]
    return [get $names $code $code]
}
proc ::bomtool::cnReasons {codes} {
    set out {}; foreach code [split $codes {;}] { if {$code ne ""} { lappend out [cn $code] } }
    return [join $out "\uff1b"]
}
proc ::bomtool::warningDetail {code ref category value fp} {
    switch -- $code {
        WARN-PACKAGE-CONFLICT {
            return [list "\u4f4d\u53f7 $ref \u7684\u591a\u4e2a\u5206\u90e8\u5b58\u5728\u5173\u952e\u5c5e\u6027\u51b2\u7a81\u3002" "\u8be5\u4f4d\u53f7\u6682\u4e0d\u8ba1\u5165\u5408\u5e76BOM\uff0c\u653e\u5165\u8fc7\u6ee4\u6e05\u5355\u5f85\u6838\u5bf9\uff1b\u5176\u4ed6\u5668\u4ef6\u7ee7\u7eed\u5bfc\u51fa\u3002\u6b64\u539f\u56e0\u4e0d\u8868\u793a\u4e0d\u710a\u63a5\u3002" "\u6309\u4e0b\u5217\u5b57\u6bb5\u53ca\u539f\u59cbBOM\u884c\u53f7\u68c0\u67e5\u5404\u5206\u90e8\u7684\u578b\u53f7\u3001\u5c01\u88c5\u3001\u89c4\u683c\u6216\u710a\u63a5\u72b6\u6001\uff1b\u82e5\u5b9e\u9645\u4e3a\u4e0d\u540c\u5668\u4ef6\uff0c\u8bf7\u4fee\u6b63\u91cd\u590d\u4f4d\u53f7\u540e\u91cd\u65b0\u5bfc\u51fa\u3002"]
        }
        WARN-PACKAGE-METADATA {
            return [list "\u4f4d\u53f7 $ref \u7684\u591a\u4e2a\u5206\u90e8\u5b58\u5728\u8f85\u52a9\u5b57\u6bb5\u5dee\u5f02\u6216\u90e8\u5206\u5b57\u6bb5\u4e3a\u7a7a\u3002" "\u540c\u4e00\u4f4d\u53f7\u4ec5\u8ba1\u4e00\u4e2a\u5668\u4ef6\uff1b\u7a7a\u5b57\u6bb5\u7528\u5176\u4ed6\u5206\u90e8\u975e\u7a7a\u503c\u8865\u9f50\uff0c\u8f85\u52a9\u5b57\u6bb5\u591a\u503c\u65f6\u4fdd\u7559\u9996\u4e2a\u975e\u7a7a\u503c\u3002\u539f\u59cb\u5206\u90e8\u8bb0\u5f55\u5168\u90e8\u4fdd\u7559\u3002" "\u6838\u5bf9\u4e0b\u5217\u5dee\u5f02\uff1b\u63cf\u8ff0\u3001EMPTY\u3001\u6750\u8d28\u5dee\u5f02\u4e0d\u518d\u4e2d\u6b62\u5bfc\u51fa\uff0c\u7535\u5bb9\u6682\u4e0d\u6309\u6750\u8d28\u533a\u5206\u3002"]
        }
        WARN-VALUE-FOOTPRINT {
            return [list "\u4f4d\u53f7 $ref \u7684\u503c $value \u4e2d\uff0c-04\u8868\u793a0402\u5c01\u88c5\uff0c\u4f46PCB Footprint\u4e3a $fp\u3002" "\u4fdd\u7559\u539f\u59cbPCB\u5c01\u88c5\u548c\u7b80\u7801\uff0c\u4e0d\u63090402\u81ea\u52a8\u5408\u5e76\uff1b\u7ed3\u679c\u6807\u8bb0\u4e3a\u9700\u68c0\u67e5\u539f\u7406\u56fe\u5e93\u3002" "\u786e\u8ba4\u5b9e\u9645\u710a\u76d8\u5c3a\u5bf8\uff0c\u7edf\u4e00\u503c\u4e2d\u7684\u5c01\u88c5\u7b80\u7801\u4e0ePCB Footprint\u540e\u91cd\u65b0\u5bfc\u51fa\u3002"]
        }
        WARN-0OHM-FOOTPRINT {
            return [list "\u4f4d\u53f7 $ref \u662f0\u03a9\u7535\u963b\uff0c\u539f\u5c01\u88c5\u4e3a $fp\uff0c\u4f7f\u7528\u4e86C\u524d\u7f00\u7535\u5bb9\u5c01\u88c5\u540d\u3002" "\u5141\u8bb8\u63090\u03a9\u4f8b\u5916\u5728\u7535\u963b\u7ec4\u5185\u5408\u5e76\uff0c\u4e0d\u4f1a\u5408\u5165\u7535\u5bb9\u7ec4\u3002" "\u786e\u8ba4\u710a\u76d8\u5c3a\u5bf8\u6b63\u786e\uff1b\u5efa\u8bae\u5c06\u5e93\u5c01\u88c5\u540d\u89c4\u8303\u4e3a\u7535\u963b\u5c01\u88c5\u540d\u3002"]
        }
        WARN-CATEGORY-FOOTPRINT {
            return [list "\u4f4d\u53f7 $ref \u88ab\u8bc6\u522b\u4e3a[cn $category]\uff0c\u539f\u503c\u4e3a $value\uff0c\u5c01\u88c5 $fp \u7684C/R\u524d\u7f00\u4e0e\u7c7b\u522b\u4e0d\u7b26\u3002" "\u4fdd\u7559\u5728\u539f\u7c7b\u522b\u5185\uff0c\u5408\u5e76\u7ed3\u679c\u6807\u8bb0\u4e3a\u9700\u68c0\u67e5\u539f\u7406\u56fe\u5e93\u3002" "\u6838\u5bf9\u4f4d\u53f7\u3001\u5668\u4ef6\u503c\u548cPCB\u5c01\u88c5\uff0c\u4fee\u6b63\u539f\u7406\u56fe\u5e93\uff1b\u4e0d\u5f97\u8de8\u7c7b\u522b\u5408\u5e76\u3002"]
        }
        WARN-MISSING-FIELD {
            set missing {}; if {$value eq ""} { lappend missing "\u5668\u4ef6\u503c" }; if {$fp eq ""} { lappend missing "PCB\u5c01\u88c5" }
            return [list "\u4f4d\u53f7 $ref \u7f3a\u5c11[join $missing "\u3001"]\u3002" "\u5df2\u79fb\u5165\u8fc7\u6ee4\u6e05\u5355\uff0c\u4e0d\u8ba1\u5165\u6700\u7ec8BOM\u3002" "\u5728\u539f\u7406\u56fe\u4e2d\u8865\u9f50\u5b57\u6bb5\u540e\u91cd\u65b0\u5bfc\u51fa\u3002"]
        }
        WARN-UNPARSED-SUFFIX {
            return [list "\u4f4d\u53f7 $ref \u7684\u503c $value \u5305\u542b\u672a\u5b8c\u6574\u8bc6\u522b\u7684\u540e\u7f00\uff0c\u53ef\u80fd\u662f\u529f\u7387\u3001\u7535\u6d41\u3001\u5c01\u88c5\u7b80\u7801\u6216\u5176\u4ed6\u89c4\u683c\u3002" "\u540e\u7f00\u539f\u6587\u4fdd\u7559\u5728\u5206\u7ec4\u952e\u4e2d\uff0c\u4ec5\u4e0e\u76f8\u540c\u540e\u7f00\u5408\u5e76\u3002" "\u68c0\u67e5\u5f52\u4e00\u5316\u660e\u7ec6\uff1b\u786e\u8ba4\u540e\u7f00\u542b\u4e49\u540e\u89c4\u8303\u5668\u4ef6\u503c\uff0c\u4e0d\u8981\u76f4\u63a5\u5220\u9664\u3002"]
        }
        WARN-UNPARSED-VALUE {
            return [list "\u4f4d\u53f7 $ref \u6309\u524d\u7f00\u5f52\u4e3a[cn $category]\uff0c\u4f46\u503c $value \u65e0\u6cd5\u89e3\u6790\u4e3a\u5bf9\u5e94\u6807\u79f0\u6570\u503c\u3002" "\u4fdd\u7559\u539f\u6587\u5206\u7ec4\uff1b\u4e0d\u4f1a\u4ec5\u56e0\u65e0\u6cd5\u89e3\u6790\u800c\u4e22\u5f03\u5668\u4ef6\u3002" "\u82e5\u4e3a\u578b\u53f7\u7f16\u7801\u53ef\u4fdd\u7559\uff1b\u82e5\u4e3a\u5bb9\u91cf/\u963b\u503c/\u611f\u503c\uff0c\u8bf7\u89c4\u8303\u5355\u4f4d\u3002\u540c\u65f6\u6838\u5bf9\u4f4d\u53f7\u524d\u7f00\u662f\u5426\u6b63\u786e\u3002"]
        }
        WARN-DUPLICATE-REFERENCE {
            return [list "\u4f4d\u53f7 $ref \u5728\u8f93\u5165BOM\u4e2d\u51fa\u73b0\u591a\u6b21\uff0c\u65e0\u6cd5\u786e\u8ba4\u662f\u5426\u91cd\u590d\u8ba1\u6570\u6216\u5c5e\u6027\u51b2\u7a81\u3002" "\u8be5\u4f4d\u53f7\u6240\u6709\u8bb0\u5f55\u5747\u9694\u79bb\uff0c\u4e0d\u8ba1\u5165\u6700\u7ec8BOM\u3002" "\u6309\u6e90\u884c\u53f7\u6838\u5bf9\u539f\u59cbBOM\uff0c\u6d88\u9664\u91cd\u590d\u6216\u4fee\u6b63\u4f4d\u53f7\u540e\u91cd\u65b0\u5bfc\u51fa\u3002"]
        }
        WARN-MISSING-REFERENCE {
            return [list "\u8be5\u884c\u6709\u6570\u636e\u4f46\u6ca1\u6709\u4f4d\u53f7\uff0c\u503c\u4e3a $value\uff0c\u5c01\u88c5\u4e3a $fp\u3002" "\u5df2\u79fb\u5165\u8fc7\u6ee4\u6e05\u5355\uff0c\u4e0d\u8ba1\u5165\u6700\u7ec8BOM\u3002" "\u8865\u9f50\u4f4d\u53f7\uff1b\u82e5\u662f\u9644\u6ce8\u6216\u8f85\u6599\uff0c\u8bf7\u5355\u72ec\u7ef4\u62a4\u3002"]
        }
        default { return [list [cn $code] "\u8bf7\u6838\u5bf9\u539f\u59cb\u8bb0\u5f55\u3002" "\u6839\u636e\u539f\u7406\u56fe\u786e\u8ba4\u540e\u5904\u7406\u3002"] }
    }
}
proc ::bomtool::presentSheets {sheets} {
    set result {}
    set compact {}; set n 0
    foreach r [lindex [lindex $sheets 0] 2] {
        incr n
        lassign $r refs qty cat fp norm key required volt tol status eligible sourceRows originals issues warnings
        set note ""
        if {$status ne "OBSERVED_MATCH"} { set note [cn $status] }
        if {$warnings ne ""} { if {$note ne ""} { append note "\uff1b" }; append note [cnReasons $warnings] }
        lappend compact [list $n $refs $qty [cn $cat] $required $fp $note]
    }
    lappend result [list "\u5408\u5e76BOM" [list "\u5e8f\u53f7" "\u4f4d\u53f7" "\u6570\u91cf" "\u7c7b\u522b" "\u89c4\u683c\u53c2\u6570" "\u5c01\u88c5" "\u5907\u6ce8"] $compact {1 3}]
    set excluded {}
    foreach r [lindex [lindex $sheets 1] 2] {
        lassign $r ref line reasons value fp evidence
        lappend excluded [list $ref $line [cnReasons $reasons] $evidence $value $fp]
    }
    lappend result [list "\u8fc7\u6ee4\u6e05\u5355" [list "\u4f4d\u53f7" "\u6e90\u884c\u53f7" "\u8fc7\u6ee4\u539f\u56e0" "\u4e0d\u710a\u63a5\u4f9d\u636e" "\u539f\u59cb\u503c" "\u539f\u59cb\u5c01\u88c5"] $excluded {2}]
    set warnings {}
    foreach r [lindex [lindex $sheets 2] 2] {
        lassign $r code ref line cat value fp extra
        lassign [warningDetail $code $ref $cat $value $fp] detail effect action
        if {$extra ne ""} { append detail "\n" $extra }
        lappend warnings [list $ref [cn $code] $detail $effect $action $line $value $fp $code]
    }
    lappend result [list "\u544a\u8b66" [list "\u4f4d\u53f7" "\u95ee\u9898\u7c7b\u578b" "\u5177\u4f53\u539f\u56e0" "\u672c\u6b21\u5904\u7406" "\u5efa\u8bae\u5904\u7406" "\u6e90\u884c\u53f7" "\u539f\u59cb\u503c" "\u539f\u59cb\u5c01\u88c5" "\u544a\u8b66\u7f16\u53f7"] $warnings {6}]
    set audit {}
    foreach r [lindex [lindex $sheets 3] 2] {
        lset r 2 [cn [lindex $r 2]]; lset r 8 [cnReasons [lindex $r 8]]; lappend audit $r
    }
    lappend result [list "\u5f52\u4e00\u5316\u660e\u7ec6" [list "\u4f4d\u53f7" "\u6e90\u884c\u53f7" "\u7c7b\u522b" "\u539f\u59cb\u5c01\u88c5" "\u5f52\u4e00\u5316\u5c01\u88c5" "\u539f\u59cb\u503c" "\u5f52\u4e00\u5316\u503c" "\u5206\u7ec4\u952e" "\u8fc7\u6ee4\u539f\u56e0"] $audit {2}]
    # The native sheet intentionally uses the user's exact seven column names.
    lappend result [lindex $sheets 4]
    set summary {}
    set labels [dict create Version "\u8f6f\u4ef6\u7248\u672c" InputRows "\u539f\u751f\u8bb0\u5f55\u6570" InputReferences "\u8f93\u5165\u4f4d\u53f7\u6570" Groups "\u5408\u5e76\u7ec4\u6570" Excluded "\u8fc7\u6ee4\u8bb0\u5f55\u6570" Warnings "\u544a\u8b66\u6761\u6570" MaterialPolicy "\u6750\u8d28\u5904\u7406" GroupKey "\u5206\u7ec4\u89c4\u5219" \
        ClassificationPolicy "\u9ed8\u8ba4\u5206\u7c7b\u65b9\u5f0f" MergePolicy "\u9ed8\u8ba4\u5408\u5e76\u65b9\u5f0f" FilterPolicy "\u9ed8\u8ba4\u8fc7\u6ee4\u65b9\u5f0f" WarningPolicy "\u9ed8\u8ba4\u544a\u8b66\u65b9\u5f0f"         InductorPolicy "\u7535\u611f\u89c4\u683c\u5904\u7406" SpecialCategoryPolicy "\u7279\u6b8a\u5206\u7c7b\u89c4\u5219" FootprintPolicy "\u5c01\u88c5\u5f52\u4e00\u4e0e\u663e\u793a" ValuePolicy "\u5668\u4ef6\u503c\u89e3\u6790\u4e0e\u4fdd\u7559" SpecificationPolicy "\u5408\u5e76\u89c4\u683c\u8ba1\u7b97" CaptureSectionPolicy "\u591a\u5355\u5143\u5668\u4ef6\u5904\u7406" BatchClassificationPolicy "\u6279\u91cf\u5206\u7c7b\u8be2\u95ee"]
    foreach r [lindex [lindex $sheets 5] 2] {
        lassign $r k v
        if {$k eq "MaterialPolicy"} { set v "\u6682\u4e0d\u533a\u5206\u6750\u8d28" }
        if {$k eq "GroupKey"} { set v "\u5668\u4ef6\u7c7b\u522b:\u5f52\u4e00\u5316\u5c01\u88c5:\u5f52\u4e00\u5316\u503c" }
        if {$k eq "ClassificationPolicy"} {
            set v "\u6309\u4f4d\u53f7\u524d\u7f00\u5206\u7c7b\uff1aC/PC=\u7535\u5bb9\uff1bR/PR=\u7535\u963b\uff1bL/PL/FB/PFB/LV/CH/CHK/CHOKE=\u7535\u611f\u6216\u78c1\u73e0\uff1bD=\u4e8c\u6781\u7ba1\uff1bQ/PQ/QN=MOS/\u4e09\u6781\u7ba1\uff1bU/PU/AU=\u96c6\u6210\u7535\u8def\uff1bJ/JGPIO/PCI/PCIE/SATA/USB/COM=\u8fde\u63a5\u5668\uff1b\u5176\u4f59\u4e3a\u5176\u4ed6\u3002\u957f\u524d\u7f00\u4f18\u5148\u3002"
        }
        if {$k eq "SpecialCategoryPolicy"} {
            set v "AC+\u5e38\u89c1C\u5c01\u88c5\u8bc6\u522b\u4e3a\u7535\u5bb9\uff1bAR+R\u5c01\u88c5\u8bc6\u522b\u4e3a\u7535\u963b\uff0cAR+\u5176\u4ed6\u5c01\u88c5\u4e0d\u6309\u5c01\u88c5\u731c\u6d4b\u3002CPU/CPU_FAN\u4e3a\u8fde\u63a5\u5668\uff1bRTCBAT\u4e3a\u7535\u6c60\u5ea7\uff1bX/Y\u4f4d\u53f7\u4e14Value\u542bMHz\u4e3a\u6676\u632f\uff1bValue\u542bNTC\u4e3aNTC\u70ed\u654f\u7535\u963b\uff1bLED\u4e3a\u4e8c\u6781\u7ba1\u3002"
        }
        if {$k eq "MergePolicy"} {
            set v "\u5206\u7ec4\u952e\u4e3a\u7c7b\u522b:\u5f52\u4e00\u5316\u5c01\u88c5:\u5f52\u4e00\u5316\u503c\uff1b\u4e09\u9879\u5b8c\u5168\u76f8\u540c\u624d\u5408\u5e76\u3002\u4f4d\u53f7\u62c6\u5206\u540e\u9010\u9879\u8ba1\u6570\uff1b\u5df2\u8bc6\u522b\u7684\u7b49\u4ef7\u5355\u4f4d\u5148\u5f52\u4e00\uff0c\u672a\u77e5\u578b\u53f7/\u89c4\u683c\u540e\u7f00\u539f\u6837\u7559\u5728\u952e\u5185\uff0c\u907f\u514d\u9519\u8bef\u5408\u5e76\u3002"
        }
        if {$k eq "FootprintPolicy"} {
            set v "\u5e38\u89c1C0402/R0402/L0402/FB0402\u7b49\u53ea\u5728\u5f52\u4e00\u5316\u5206\u7ec4\u53ca\u5408\u5e76BOM\u5c01\u88c5\u5217\u4e2d\u7edf\u4e00\u663e\u793a\u4e3a0402\uff1b\u7c7b\u522b\u4ecd\u53c2\u4e0e\u5206\u7ec4\u3002\u539f\u59cb\u5b8c\u6574\u5c01\u88c5\u540d\u4fdd\u5b58\u5728\u201c\u539f\u59cbBOM\u201d\u8868\uff1b\u590d\u6742\u5c01\u88c5\u4e0d\u731c\u7b49\u6548\u3002"
        }
        if {$k eq "ValuePolicy"} {
            set v "\u7535\u5bb9\u7edf\u4e00\u4e3apF\u3001\u7535\u963b\u7edf\u4e00\u4e3aOhm\u3001\u7535\u611f\u7edf\u4e00\u4e3anH\uff1b\u652f\u6301\u5e38\u89c1\u5355\u4f4d\u5927\u5c0f\u5199\u3001\u5bb9\u5dee\u548c\u8010\u538b\u89e3\u6790\u3002NTC\u963b\u503c\u4e0eB\u503c\u4fdd\u7559\uff1b\u6676\u632fValue\u4fdd\u7559\u539f\u89c4\u683c\uff1b\u672a\u8bc6\u522b\u540e\u7f00\u4e0d\u5220\u9664\u3002"
        }
        if {$k eq "SpecificationPolicy"} {
            set v "\u540c\u7ec4\u8010\u538b\u53d6\u5df2\u77e5\u6700\u5927\u503c\u3001\u5bb9\u5dee\u53d6\u5df2\u77e5\u6700\u5c0f\u503c\uff1b\u53ea\u586b\u8865\u540c\u7ec4\u5df2\u6709\u89c4\u683c\u3002\u82e5\u6ca1\u6709\u5355\u4e00\u539f\u5668\u4ef6\u540c\u65f6\u6ee1\u8db3\u5408\u5e76\u89c4\u683c\uff0c\u6807\u8bb0\u9700\u9009\u62e9\u5668\u4ef6\uff0c\u4e0d\u865a\u6784\u6599\u53f7\u3002\u7535\u5bb9\u6750\u8d28\u4e0d\u53c2\u4e0e\u5206\u7ec4\u6216\u4f18\u52a3\u5224\u65ad\u3002"
        }
        if {$k eq "FilterPolicy"} {
            set v "\u8fc7\u6ee4\u72ec\u7acbNC/DNP/DNI/DNE/NS\u3001Option\u4e0d\u88c5\u914d\u3001DNP\u5c5e\u6027\u53ca\u4e2d\u6587\u4e0d\u88c5\u914d\u6807\u8bb0\uff1b\u8fc7\u6ee4\u6d4b\u8bd5\u70b9TP\u3001\u5b9a\u4f4d\u70b9MARK/FID\u3001\u5b89\u88c5\u5b54HOLE/BOSS/MH\u3002\u7f3a\u5c11\u503c/\u5c01\u88c5\u3001\u91cd\u590d\u4f4d\u53f7\u53caCapture\u5173\u952e\u5c5e\u6027\u51b2\u7a81\u7684\u8bb0\u5f55\u9694\u79bb\uff0c\u4e0d\u8ba1\u5165\u53ef\u91c7\u8d2d\u5408\u5e76\u9879\u3002"
        }
        if {$k eq "WarningPolicy"} {
            set v "\u544a\u8b66\u5217\u51fa\u4f4d\u53f7\u3001\u95ee\u9898\u3001\u539f\u56e0\u3001\u5f53\u6b21\u5904\u7406\u3001\u5efa\u8bae\u53ca\u6e90\u884c\u3002\u7c7b\u522b\u4e0e\u5c01\u88c5\u4e0d\u7b26\u30010\u03a9\u7535\u963b\u7528C\u5c01\u88c5\u3001-04\u5c01\u88c5\u7b80\u7801\u51b2\u7a81\u3001\u503c/\u540e\u7f00\u65e0\u6cd5\u89e3\u6790\u7b49\u4f1a\u544a\u8b66\uff1b\u672a\u77e5\u539f\u6587\u4fdd\u7559\uff0c\u4e0d\u56e0\u666e\u901a\u89e3\u6790\u544a\u8b66\u800c\u9759\u9ed8\u5220\u9664\u3002"
        }
        if {$k eq "CaptureSectionPolicy"} {
            set v "\u540c\u4f4d\u53f7\u591a\u5355\u5143\u5148\u6bd4\u8f83\u503c\u3001\u5c01\u88c5\u3001\u88c5\u914d\u72b6\u6001\u7b49\u5173\u952e\u5c5e\u6027\uff1b\u5173\u952e\u5dee\u5f02\u5219\u6574\u4e2a\u4f4d\u53f7\u9694\u79bb\u5e76\u544a\u8b66\uff0c\u8f85\u52a9\u5b57\u6bb5\u5dee\u5f02\u8bb0\u5f55\u540e\u5408\u5e76\u7a7a\u503c\uff0c\u4e0d\u91cd\u590d\u8ba1\u6570\u3002"
        }
        if {$k eq "BatchClassificationPolicy"} {
            set v "\u9ed8\u8ba4\u5f52\u4e3a\u5176\u4ed6\u3001\u540c\u524d\u7f00\u8fde\u7eed\u7f16\u53f7\u4e14\u6570\u91cf\u81f3\u5c118\u4e2a\u65f6\uff0c\u5bfc\u51fa\u524d\u9010\u7ec4\u8be2\u95ee\u5206\u7c7b\uff1b\u672c\u6b21\u9009\u62e9\u53ea\u4f5c\u7528\u4e8e\u672c\u6b21\u5bfc\u51fa\uff0c\u53d6\u6d88\u5219\u4e0d\u751f\u6210BOM\u3002"
        }
        if {$k eq "InductorPolicy"} { set v "nH/uH\u7edf\u4e00\u5f52\u4e00\u4e3anH\uff1b\u7535\u6d41\u989d\u5b9a\u503c\u53ca\u6570\u5b57/M\u89c4\u683c\u7ec4\u5408\u53c2\u4e0e\u5206\u7ec4\u5e76\u4fdd\u7559\uff0c\u4e0d\u4f5c\u4e3a\u672a\u77e5\u540e\u7f00\u544a\u8b66\u3002" }
        lappend summary [list [get $labels $k $k] $v]
    }
    lappend summary [list "\u539f\u751fBOM\u8868\u5934" [join $::bomtool::nativeHeaders \t]]
    lappend summary [list "Line Item Definition" $::bomtool::lineItemDefinition]
    lappend result [list "\u6c47\u603b" [list "\u9879\u76ee" "\u5185\u5bb9"] $summary {}]
    return $result
}


# SPDX-License-Identifier: GPL-3.0-only
# Capture 17.4 adapter. The occurrence walk follows Cadence's installed example:
# tools/capture/tclscripts/capCustomSamples/capGenerateBOM.tcl.
# All database operations below are READ ONLY.
namespace eval ::bomtool {
    variable scriptPath [file normalize [info script]]
    variable uiEncoding utf-8
}
proc ::bomtool::captureProp {design occ inst name} {
    set pn [DboTclHelper_sMakeCString $name]
    set pv [DboTclHelper_sMakeCString]
    try {
        foreach obj [list $occ $inst] {
            if {$obj eq "NULL"} { continue }
            if {![$obj IsVariantPropMapEmpty] && [$obj GetVariantProp $pn $pv]} {
                return [DboTclHelper_sGetConstCharPtr $pv]
            }
        }
        set status [$occ GetEffectivePropStringValue $pn $pv]
        try {
            if {[$status OK]} { return [DboTclHelper_sGetConstCharPtr $pv] }
            return ""
        } finally { $status -delete }
    } finally {
        DboTclHelper_sDeleteCString $pn
        DboTclHelper_sDeleteCString $pv
    }
}
proc ::bomtool::captureWalk {design parent rowsName} {
    upvar 1 $rowsName rows
    set status [DboState]; set iter NULL
    try {
        set iter [$parent NewChildrenIter $status $::IterDefs_INSTS]
        if {$iter eq "NULL" || ![$status OK]} { error "Capture: cannot enumerate occurrences." }
        set child [$iter NextOccurrence $status]
        while {$child ne "NULL"} {
            set occ [DboOccurrenceToDboInstOccurrence $child]
            if {[$occ IsPrimitive $status]} {
                set refCString [DboTclHelper_sMakeCString]
                try {
                    set rs [$occ GetReference $refCString]
                    try {
                        if {![$rs OK]} { error "Capture: cannot read occurrence reference." }
                        set ref [clean [DboTclHelper_sGetConstCharPtr $refCString]]
                    } finally { $rs -delete }
                } finally { DboTclHelper_sDeleteCString $refCString }
                if {$ref eq "" || [string first ? $ref] >= 0} { error "Capture: unannotated part '$ref'; annotate before BOM export." }
                set inst [$occ GetPartInst $status]
                set row [dict create ref $ref refs [list [string toupper $ref]] row [expr {[llength $rows]+2}] file capture]
                set notStuffed [DboTclHelper_sGetConstCharPtr [$design GetCISNotStuffedString]]
                foreach {key prop} {value Value footprint {PCB Footprint} description Dsecription option Option empty EMPTY material MATERIAL dnp DNP voltage Voltage tolerance Tolerance part_number {Part Number}} {
                    set value [captureProp $design $occ $inst $prop]
                    dict set row $key $value
                    if {$notStuffed ne "" && $value eq $notStuffed} {
                        dict set row variant_nc 1
                        dict lappend row variant_nc_sources [list $prop $value]
                    }
                }
                if {[get $row description] eq ""} { dict set row description [captureProp $design $occ $inst Description] }
                if {[get $row variant_nc] eq "1"} {
                    dict set row original_dnp [get $row dnp]
                    dict set row dnp YES
                }
                lappend rows $row
            } else {
                captureWalk $design $occ rows
            }
            set child [$iter NextOccurrence $status]
        }
        # NULL is the documented end-of-iteration sentinel. Capture returns
        # IDS_DBOSTATE_AT_END here, so !OK is normal, not a traversal failure.
        # See capinfomodel/dboimnew.html, "Iterators". Tcl exceptions still
        # propagate through finally and cancel export; do not catch them here.
    } finally {
        if {$iter ne "NULL"} { delete_DboOccurrenceChildrenIter $iter }
        $status -delete
    }
}
proc ::bomtool::captureRows {} {
    if {![info exists ::DboSession_s_pDboSession]} { error "Run Export Active Design inside OrCAD Capture CIS 17.4." }
    set session $::DboSession_s_pDboSession
    DboSession -this $session
    set design [$session GetActiveDesign]
    if {$design eq "NULL"} { error "Open a design in Capture first." }
    set status [DboState]
    try {
        set root [$design GetRootOccurrence $status]
        if {$root eq "NULL" || ![$status OK]} { error "Capture: root occurrence is unavailable." }
        set rows {}; captureWalk $design $root rows
    } finally { $status -delete }
    if {![llength $rows]} { error "The active design has no primitive parts." }
    return [collapseCaptureSections $rows]
}
proc ::bomtool::collapseCaptureSections {rows} {
    # Keep original section rows for the workbook and diagnose all differences.
    set physical {}; set result {}
    foreach row $rows {
        dict lappend physical [string toupper [get $row ref]] $row
    }
    dict for {ref sections} $physical {
        set merged [lindex $sections 0]; set differences {}; set conflicts {}
        foreach {key label} {value Value footprint {PCB Footprint} description Dsecription option Option empty EMPTY material MATERIAL dnp DNP voltage Voltage tolerance Tolerance part_number {Part Number}} {
            set values {}; set evidence {}; set first ""
            foreach section $sections {
                set value [clean [get $section $key]]
                lappend evidence "\u539f\u59cbBOM\u7b2c[get $section row]\u884c=\"$value\""
                if {$value ne ""} {
                    if {$first eq ""} { set first [get $section $key] }
                    lappend values [string toupper $value]
                }
            }
            if {[clean [get $merged $key]] eq ""} { dict set merged $key $first }
            set rawValues {}; foreach section $sections { lappend rawValues [get $section $key] }
            if {[llength [lsort -unique $rawValues]] > 1} {
                lappend differences "$label\uff1a[join $evidence "\uff1b"]"
            }
            if {$key in {value footprint option voltage tolerance part_number} && [llength [lsort -unique $values]] > 1} {
                lappend conflicts $label
            }
        }
        set states {}; set stateEvidence {}; set ncSources {}
        foreach section $sections {
            set evidence [ncEvidence $section]
            set nc [expr {[llength $evidence] > 0}]; lappend states $nc
            set label "\u710a\u63a5"; if {$nc} { set label "\u4e0d\u710a\u63a5\uff08[join $evidence "\uff1b"]\uff09" }
            lappend stateEvidence "\u539f\u59cbBOM\u7b2c[get $section row]\u884c=$label"
            set ncSources [concat $ncSources [get $section variant_nc_sources]]
        }
        if {[llength [lsort -unique $states]] > 1} {
            lappend conflicts "\u710a\u63a5\u72b6\u6001"
            lappend differences "\u710a\u63a5\u72b6\u6001\uff1a[join $stateEvidence "\uff1b"]"
        }
        if {[llength $ncSources]} { dict set merged variant_nc_sources [lsort -unique $ncSources]; dict set merged variant_nc 1 }
        dict set merged capture_sections $sections
        dict set merged capture_differences [join $differences "\n"]
        dict set merged capture_conflict [join $conflicts "\u3001"]
        lappend result $merged
    }
    return $result
}
proc ::bomtool::exportCapture {outdir {rows ""} {overrides {}}} {
    if {$rows eq ""} { set rows [captureRows] }
    return [preprocess [applyCategoryOverrides $rows $overrides] $outdir]
}
proc ::bomtool::moduleA {input outdir {encoding utf-8}} { return [preprocess [readBom $input $encoding] $outdir] }
proc ::bomtool::outputDirectory {parent label} {
    set base [file join $parent ${label}_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
    set path $base; set i 1
    while {[file exists $path]} { set path ${base}_$i; incr i }
    file mkdir $path
    return $path
}
proc ::bomtool::chooseBom {title} {
    return [tk_getOpenFile -title $title -filetypes {{{BOM text} {.csv .txt .tsv}} {{All files} *}}]
}
proc ::bomtool::finishCategoryDialog {result} {
    variable categoryDialogResult
    set categoryDialogResult $result
}
proc ::bomtool::requestCategoryOverrides {candidates} {
    variable categoryDialogResult
    if {![llength $candidates]} { return {} }
    set w .bomcategorydialog
    if {[winfo exists $w]} { destroy $w }
    toplevel $w
    set result __cancel__
    try {
        wm title $w "\u786e\u8ba4\u6279\u91cf\u4f4d\u53f7\u5206\u7c7b"
        wm transient $w .
        wm protocol $w WM_DELETE_WINDOW [list ::bomtool::finishCategoryDialog __cancel__]
        label $w.note -text "\u53d1\u73b0\u4ee5\u4e0b\u8fde\u7eed\u4f4d\u53f7\u7ec4\uff08\u6bcf\u7ec4\u81f3\u5c118\u4e2a\uff09\u3002\u8bf7\u9009\u62e9\u5206\u7c7b\uff1b\u9009\u62e9\u201c\u5176\u4ed6\u201d\u5c06\u4fdd\u7559\u9ed8\u8ba4\u5206\u7c7b\u3002" \
            -anchor w -justify left -wraplength 620
        pack $w.note -padx 14 -pady 10 -fill x
        frame $w.rows
        pack $w.rows -padx 14 -fill both -expand 1
        set choices {cap res ind diode mos ic conn batt xtal other}
        set labels {}
        set labelToCategory {}
        foreach category $choices {
            set label [cn $category]
            lappend labels $label
            dict set labelToCategory $label $category
        }
        set i 0
        foreach candidate $candidates {
            lassign $candidate prefix refs
            set line $w.rows.row$i
            frame $line
            label $line.family -text "$prefix\uff08[llength $refs] \u4e2a\uff09" -width 20 -anchor w
            label $line.refs -text [join $refs ", "] -width 52 -anchor w
            ttk::combobox $line.category -state readonly -values $labels -width 14 \
                -textvariable ::bomtool::categoryChoice($prefix)
            set ::bomtool::categoryChoice($prefix) [cn other]
            grid $line.family -row 0 -column 0 -sticky w -padx 4
            grid $line.refs -row 0 -column 1 -sticky w -padx 4
            grid $line.category -row 0 -column 2 -sticky e -padx 4
            pack $line -fill x -pady 3
            incr i
        }
        frame $w.buttons
        button $w.buttons.ok -text "\u7ee7\u7eed\u6574\u7406" -width 12 -command [list ::bomtool::finishCategoryDialog accept]
        button $w.buttons.cancel -text "\u53d6\u6d88" -width 12 -command [list ::bomtool::finishCategoryDialog __cancel__]
        pack $w.buttons.cancel $w.buttons.ok -side right -padx 6 -pady 10
        pack $w.buttons -fill x -padx 14
        set categoryDialogResult ""
        grab set $w
        tkwait variable ::bomtool::categoryDialogResult
        set result $categoryDialogResult
        if {$result eq "accept"} {
            set overrides {}
            foreach candidate $candidates {
                lassign $candidate prefix refs
                set selected $::bomtool::categoryChoice($prefix)
                if {![dict exists $labelToCategory $selected]} { error "Unknown category selection: $selected" }
                set category [dict get $labelToCategory $selected]
                foreach ref $refs { dict set overrides $ref $category }
            }
            set result $overrides
        }
    } finally {
        foreach candidate $candidates { unset -nocomplain ::bomtool::categoryChoice([lindex $candidate 0]) }
        if {[winfo exists $w]} {
            if {[grab current $w] eq $w} { grab release $w }
            destroy $w
        }
    }
    return $result
}
proc ::bomtool::runUI {action} {
    variable uiEncoding
    if {[catch {
        switch -- $action {
            A {
                set input [chooseBom "\u9009\u62e9\u5df2\u6709\u539f\u751fBOM\uff08\u53ef\u9009\u5bfc\u5165\uff09"]
                if {$input eq ""} { return }
                set parent [tk_chooseDirectory -title "\u9009\u62e9\u7ed3\u679c\u4fdd\u5b58\u76ee\u5f55"]
                if {$parent eq ""} { return }
                set result [moduleA $input [outputDirectory $parent module_a] $uiEncoding]
            }
            export {
                set rows [captureRows]
                set candidates [categoryCandidates $rows]
                set overrides [requestCategoryOverrides $candidates]
                if {$overrides eq "__cancel__"} { return }
                set parent [tk_chooseDirectory -title "\u9009\u62e9\u7ed3\u679c\u4fdd\u5b58\u76ee\u5f55\uff1a\u81ea\u52a8\u8bfb\u53d6\u539f\u7406\u56fe\u5e76\u6309\u4e03\u5217\u751f\u6210BOM"]
                if {$parent eq ""} { return }
                set result [exportCapture [outputDirectory $parent capture_bom] $rows $overrides]
            }
            default { error "Unknown action: $action" }
        }
        puts "BOM Workbench: $result"
        set message "\u5904\u7406\u5b8c\u6210\n\u8f93\u5165\u4f4d\u53f7\uff1a[get $result input_references]\n\u5408\u5e76\u7ec4\u6570\uff1a[get $result groups]\n\u8fc7\u6ee4\u8bb0\u5f55\uff1a[get $result excluded]\n\u544a\u8b66\u6761\u6570\uff1a[get $result warnings]\n\n\u7ed3\u679c\u6587\u4ef6\uff1a[get $result workbook]"
        set icon info
        if {[get $result pending_packages 0] > 0} {
            append message "\n\n\u6ce8\u610f\uff1a[get $result pending_packages] \u4e2a\u4f4d\u53f7\u7684\u5206\u90e8\u5c5e\u6027\u51b2\u7a81\uff0c\u6682\u672a\u8ba1\u5165\u5408\u5e76BOM\u3002\u8bf7\u67e5\u770bExcel\u7684\u544a\u8b66\u53ca\u8fc7\u6ee4\u6e05\u5355\uff0c\u6838\u5bf9\u540e\u518d\u7528\u4e8e\u91c7\u8d2d\u3002"
            set icon warning
        }
        tk_messageBox -title "BOM\u8f93\u51fa\u589e\u5f3a\u7248" -icon $icon -message $message
    } err options]} {
        if {[get $options -code] == 0} { return }
        puts "BOM Workbench ERROR: $err"
        if {[dict exists $options -errorinfo]} { puts [dict get $options -errorinfo] }
        tk_messageBox -title "BOM\u5904\u7406\u5931\u8d25" -icon error -message $err
        return 0
    }
    return 1
}
proc ::bomtool::log {message} {
    puts "bomtool: $message"
    catch {flush stdout}
}
proc ::bomtool::showWindow {w} {
    wm deiconify $w
    raise $w
    focus $w
}
proc ::bomtool::dialog {args} {
    # A fresh Capture session does not necessarily load Tk. Cadence's own
    # capAppLaunchMenu.tcl requires Tk at the click boundary for this reason.
    set hadTk [expr {[llength [info commands winfo]] > 0}]
    package require Tk 8.6
    if {!$hadTk} { wm withdraw . }
    set w .bomworkbench
    if {[winfo exists $w]} { showWindow $w; return }
    try {
    toplevel $w; wm title $w "BOM\u8f93\u51fa\u589e\u5f3a\u7248 $::bomtool::version - Capture CIS"
    label $w.title -text "\u8bfb\u53d6\u5f53\u524d\u539f\u7406\u56fe \u2192 \u6309\u4e03\u5217\u751f\u6210\u539f\u751fBOM \u2192 \u6574\u7406\u4e3aExcel" -padx 18 -pady 12
    pack $w.title
    foreach {id label action} [list export "\u81ea\u52a8\u751f\u6210\u5e76\u6574\u7406BOM" export a "\u5bfc\u5165\u5df2\u6709TXT/CSV\uff08\u53ef\u9009\uff09" A] {
        button $w.$id -text $label -command [list ::bomtool::runUI $action] -width 49
        pack $w.$id -padx 18 -pady 5 -fill x
    }
    frame $w.encoding
    label $w.encoding.label -text "\u6587\u4ef6\u5bfc\u5165\u7f16\u7801\uff1a"
    tk_optionMenu $w.encoding.menu ::bomtool::uiEncoding utf-8 cp936 unicode
    pack $w.encoding.label $w.encoding.menu -side left -padx 8
    pack $w.encoding -pady 10
    label $w.note -text "\u81ea\u52a8\u4f7f\u7528\u6307\u5b9a\u7684Line Item Definition\uff0c\u65e0\u9700\u624b\u5de5\u5bfc\u51fa\u3002\n\u7ed3\u679c\u96c6\u4e2d\u5728BOM.xlsx\uff1b\u7535\u5bb9\u6682\u4e0d\u533a\u5206\u6750\u8d28\u3002" -pady 10
    pack $w.note
    showWindow $w
    } on error {message options} {
        # Never leave a partial toplevel that subsequent clicks only raise.
        catch {destroy $w}
        return -options $options $message
    }
}
proc ::bomtool::openFromMenu {args} {
    log "open callback begin (version $::bomtool::version)"
    if {[catch {::bomtool::dialog} message options]} {
        log "open FAILED: $message"
        if {[dict exists $options -errorinfo]} { log [dict get $options -errorinfo] }
        if {[llength [info commands tk_messageBox]]} {
            catch {tk_messageBox -title "BOM\u5de5\u5177\u65e0\u6cd5\u6253\u5f00" -icon error -message "\u6253\u5f00\u5931\u8d25\uff1a$message\n\u8be6\u60c5\u89c1Capture Command Window\u4e2d\u7684bomtool\u65e5\u5fd7\u3002"}
        }
        return 0
    }
    log "open OK"
    return 1
}
proc ::bomtool::exportFromMenu {args} {
    log "direct BOM export begin (version $::bomtool::version)"
    set hadTk [expr {[llength [info commands winfo]] > 0}]
    if {[catch {package require Tk 8.6} message options]} {
        log "direct BOM export FAILED to load Tk: $message"
        if {[dict exists $options -errorinfo]} { log [dict get $options -errorinfo] }
        if {[llength [info commands tk_messageBox]]} {
            catch {tk_messageBox -title "BOM\u5de5\u5177\u65e0\u6cd5\u542f\u52a8" \
                -icon error -message "\u65e0\u6cd5\u542f\u52a8 BOM \u8f93\u51fa\uff1a$message"}
        }
        return 0
    }
    if {!$hadTk} {
        catch {update}
        catch {wm withdraw .}
    }
    if {[catch {set completed [::bomtool::runUI export]} message options]} {
        log "direct BOM export FAILED: $message"
        if {[dict exists $options -errorinfo]} { log [dict get $options -errorinfo] }
        if {[llength [info commands tk_messageBox]]} {
            catch {tk_messageBox -title "BOM\u5904\u7406\u5931\u8d25" \
                -icon error -message $message}
        }
        return 0
    }
    if {$completed ne "1"} {
        log "direct BOM export cancelled or failed"
        return 0
    }
    log "direct BOM export finished"
    return 1
}
# Global entry point used by the unified OrCAD plugin window.
proc bomtoolMenuEnabled {args} { return true }
proc bomtoolMenuOpen {args} { return [::bomtool::openFromMenu {*}$args] }
proc bomtoolMenuExport {args} { return [::bomtool::exportFromMenu {*}$args] }
::bomtool::log "$::bomtool::version loaded from $::bomtool::scriptPath; run bomtoolMenuOpen to open"

foreach obsolete {moduleB compare loadRules clearRules} {
    if {[llength [info commands ::bomtool::$obsolete]]} { rename ::bomtool::$obsolete {} }
}
if {[llength [info commands winfo]] && [winfo exists .bomworkbench]} {
    destroy .bomworkbench
    ::bomtool::openFromMenu
}
