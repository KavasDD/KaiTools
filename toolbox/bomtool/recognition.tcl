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
