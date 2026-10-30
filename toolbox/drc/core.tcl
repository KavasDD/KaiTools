# SPDX-License-Identifier: GPL-3.0-only
# Native Batch DRC reporting. No design-file parser and no independent ERC matrix.
namespace eval ::xiaokai::drc {
    variable version 1.9.9
    variable fields {rule_id rule_name hierarchy_path sheet_name refdes net_name pin_info message}
    # Complete allowlist; all eleven leaves run in one native Batch DRC call.
    variable rules {
        single_node_nets {{Check single node nets} RunElectricRuleSingleNodeNets electrical}
        drive_source_pin_conflict {{Check no driving source and Pin type conflicts} RunElectricRuleNoDrivingSource electrical}
        duplicate_net_name {{Check duplicate net names} RunElectricRuleDuplicateNetNames electrical}
        hier_port_conn {{Check hierarchical port connections} RunElectricRulePorts electrical}
        unconnected_bus {{Check unconnected bus nets} RunElectricRuleWires electrical}
        unconnected_pin {{Check unconnected pins} RunElectricRuleFloatingPins electrical}
        power_pin_visibility {{Check power pin visibility} RunPhysicalRulePwrPinVisibility physical}
        convert_view_sync {{Check normal convert view sync} RunPhysicalRuleNormalConvertSync physical}
        pin_group_assign {{Check incorrect Pin Group assignment} RunPhysicalRulePinGroup physical}
        missing_pin_num {{Check missing pin numbers} RunPhysicalRuleMissingPinNumber physical}
        name_prop_consistency {{Check name prop consistency} RunPhysicalRuleNamePropHierBlocks physical}
    }
    variable powerWhitelist {}
    variable busy 0
}
proc ::xiaokai::drc::get {d key {default ""}} {
    if {[dict exists $d $key]} {return [dict get $d $key]}
    return $default
}
proc ::xiaokai::drc::quote {s} {
    set result "\""
    foreach c [split $s ""] {
        scan $c %c n
        switch -- $c {
            "\"" {append result {\"}}
            "\\" {append result {\\}}
            default {
                if {$n < 32} {append result [format {\u%04x} $n]} else {append result $c}
            }
        }
    }
    append result "\""
    return $result
}
proc ::xiaokai::drc::configJson {config} {
    set pairs {}
    dict for {k v} $config {
        if {$k in {ERCMatrix DefaultERCMatrix}} {
            set rows {}
            dict for {row cells} $v {
                set a {}; foreach cell $cells {lappend a [quote $cell]}
                lappend rows "[quote $row]:\[[join $a ,]\]"
            }
            set value "\{[join $rows ,]\}"
        } else {set value [quote $v]}
        lappend pairs "[quote $k]:$value"
    }
    return "\{[join $pairs ,]\}"
}
proc ::xiaokai::drc::configFor {original rule report} {
    variable rules
    if {![dict exists $rules $rule]} {error "Unknown DRC rule: $rule"}
    lassign [dict get $rules $rule] name leaf category
    set cfg $original
    # Covers online rules, reports, simulation and installed custom extensions,
    # including future Run* keys returned by Capture.
    dict for {k v} $cfg {if {[string match Run* $k]} {dict set cfg $k 0}}
    dict set cfg [expr {$category eq "electrical" ? "RunElectricalRules" : "RunPhysicalRules"}] 1
    dict set cfg $leaf 1
    foreach {k v} {DoModal 1 Scope 0 Action 0 Mode 0 PreferredMode 0
        ShowDRCOutput 0 ShowDRCOutputType 0 DRCMarkerForWarnings 0
        PreserveWaivedDRC 1 IgnoreWarnings {} CustomElectricalDRC {} CustomPhysicalDRC {}} {
        dict set cfg $k $v
    }
    dict set cfg ReportFileName $report
    return $cfg
}
proc ::xiaokai::drc::batchConfig {original report} {
    variable rules
    set cfg [configFor $original single_node_nets $report]
    dict set cfg RunElectricalRules 1
    dict set cfg RunPhysicalRules 1
    dict for {id spec} $rules {dict set cfg [lindex $spec 1] 1}
    return $cfg
}
proc ::xiaokai::drc::diagnosticRule {message {section ""}} {
    # Classify native results, never make additional electrical decisions.
    # General electrical results share a section, so resolve their message IDs
    # first. The other rules have explicit native report section headings.
    if {[regexp {\(ORCAP-1600\)} $message]} {return single_node_nets}
    if {[regexp {\(ORCAP-(1608|1829)\)} $message]} {return drive_source_pin_conflict}
    if {[regexp {\(ORCAP-1831\)} $message]} {return unconnected_pin}
    if {[regexp -nocase {no driving source|no driver|pin type conflict} $message]} {return drive_source_pin_conflict}
    if {[regexp -nocase {duplicate.*net.*name|net.*name.*duplicat|same net name} $message]} {return duplicate_net_name}
    return $section
}
proc ::xiaokai::drc::ignoredDiagnostic {message} {
    # The combined native checkbox also detects missing drivers. Ignore only
    # electrical pin-type conflicts; keep no-driving-source diagnostics.
    return [regexp -nocase {\(ORCAP-1829\)|pin\s+type\s+conflict} $message]
}
proc ::xiaokai::drc::reportSection {line} {
    foreach {pattern rule} {
        {Checking For Single Node Nets} single_node_nets
        {Checking For Unconnected Bus Nets} unconnected_bus
        {Checking Pin to Port Connections} hier_port_conn
        {Checking Incorrect Pin Group Assignment} pin_group_assign
        {Checking Power Pin Visibility} power_pin_visibility
        {Checking Normal Convert View Sync} convert_view_sync
        {Checking Missing Pin Numbers} missing_pin_num
        {Checking Name Property for Hierarchical Instances} name_prop_consistency
        {Checking.*Duplicate Net} duplicate_net_name
    } {
        if {[regexp -nocase $pattern $line]} {return $rule}
    }
    return ""
}
proc ::xiaokai::drc::diagnostics {text} {
    # Capture's native .drc output, not a DSN parser. Keep continuation lines
    # verbatim. INFO messages describe progress and are never violations.
    set result {}; set current {}; set schematic ""; set section ""
    foreach line [split [string map [list "\r\n" "\n" "\r" "\n"] $text] \n] {
        if {[regexp {^(?:WARNING|ERROR|FATAL)\([^)]*\):} $line]} {
            if {[dict size $current]} {lappend result $current}
            set current [dict create schematic $schematic message $line rule_id [diagnosticRule $line $section]]
        } elseif {[regexp {^Checking Schematic:\s*(.*?)\s*$} $line -> name]} {
            if {[dict size $current]} {lappend result $current; set current {}}
            set schematic $name
            set section ""
        } elseif {[regexp {^Checking Entire Design:} $line]} {
            if {[dict size $current]} {lappend result $current; set current {}}
            set schematic ""
            set section ""
        } elseif {[reportSection $line] ne ""} {
            if {[dict size $current]} {lappend result $current; set current {}}
            set section [reportSection $line]
        } elseif {[regexp {^Checking (?:Electrical|Physical) Rules} $line]} {
            if {[dict size $current]} {lappend result $current; set current {}}
            set section ""
        } elseif {[dict size $current]} {
            if {[regexp {^\s+\S} $line]} {
                dict append current message \n$line
            } else {lappend result $current; set current {}}
        }
    }
    if {[dict size $current]} {lappend result $current}
    return $result
}
proc ::xiaokai::drc::row {rule diagnostic} {
    variable rules
    # Preserve an unfamiliar native diagnostic without inventing a twelfth
    # rule or dropping it. Empty rule metadata means classification unavailable.
    set name ""
    if {$rule eq "netlist_error"} {set name "网表输出错误"} elseif {$rule ne ""} {set name [lindex [dict get $rules $rule] 0]}
    set row [dict create rule_id $rule rule_name $name \
        hierarchy_path "" sheet_name "" refdes "" net_name "" pin_info "" message [dict get $diagnostic message]]
    set msg [dict get $row message]
    if {$rule eq "netlist_error" && [regexp -nocase {\minstance\s+([^\s:]+):} $msg -> ref]} {
        dict set row refdes $ref
    }
    # Native location is "schematic, sheet (x, y)"; schematic may be an
    # occurrence path. The Capture adapter resolves definition-only locations.
    if {[regexp -line {^\s+(.+?),\s+(.+?)\s+\([-0-9.]+,\s*[-0-9.]+\)} $msg -> path sheet]} {
        dict set row hierarchy_path [string trim $path]
        dict set row sheet_name [string trim $sheet]
    }
    if {$rule eq "netlist_error" && [regexp -nocase {\minstance\s+[^\s:]+:\s*(.+?),\s*(.+?)\s+\([-0-9.]+,\s*[-0-9.]+\)} $msg -> path sheet]} {
        dict set row hierarchy_path [string trim $path]
        dict set row sheet_name [string trim $sheet]
    }
    if {[regexp -nocase {\mnet(?:\s+name)?\s*[:=]?\s*['"]([^'"\r\n]+)['"]} $msg -> net]} {
        dict set row net_name $net
    }
    if {$rule eq "single_node_nets" && [regexp -nocase {Net has fewer than two connections ([^\r\n]+)} $msg -> net]} {
        dict set row net_name [string trim $net]
    }
    if {$rule eq "drive_source_pin_conflict" && [regexp -nocase {Net has no driving source ([^\r\n]+)} $msg -> net]} {
        dict set row net_name [string trim $net]
    }
    if {[regexp -nocase {(?:conflict|unconnected pin|pin)\s+([^\s,]+),([^\s,]+)} $msg -> ref pin]} {
        dict set row refdes $ref
        dict set row pin_info $pin
    }
    return $row
}
proc ::xiaokai::drc::exempt {row pins whitelist} {
    if {[get $row rule_id] ne "single_node_nets" || [llength $pins] != 1} {return 0}
    set pin [lindex $pins 0]
    if {![get $pin is_power 0]} {return 0}
    # Whitelist entries are dictionaries of explicit, case-insensitive glob
    # selectors. A net-only entry still requires one verified Power pin.
    foreach entry $whitelist {
        if {![dict size $entry]} {error "Empty power whitelist selector"}
        set match 1
        dict for {key pattern} $entry {
            if {$key ni {hierarchy_path sheet_name refdes net_name pin_name pin_number}} {error "Invalid whitelist selector: $key"}
            set actual [get $pin $key]
            if {$actual eq "" || ![string match -nocase $pattern $actual]} {set match 0}
        }
        if {$match} {return 1}
    }
    return 0
}
proc ::xiaokai::drc::html {s} {
    return [string map {& &amp; < &lt; > &gt; \" &quot; ' &#39;} $s]
}
proc ::xiaokai::drc::writeReports {outdir rows counts waived} {
    variable fields; variable rules
    file mkdir $outdir
    set csv [file join $outdir drc.csv]; set report [file join $outdir drc.html]
    set f [open $csv w]
    try {
        fconfigure $f -encoding utf-8 -translation crlf
        puts -nonewline $f \ufeff
        set records [list $fields]
        foreach row $rows {set cells {}; foreach key $fields {lappend cells [dict get $row $key]}; lappend records $cells}
        foreach cells $records {
            set quoted {}; foreach cell $cells {lappend quoted "\"[string map {\" \"\"} $cell]\""}
            puts $f [join $quoted ,]
        }
    } finally {close $f}
    set f [open $report w]
    try {
        fconfigure $f -encoding utf-8 -translation lf
        puts $f {<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>DRC中文增强版报告</title><style>body{font:14px system-ui;margin:24px;color:#253047}table{border-collapse:collapse;width:100%;margin:20px 0}th,td{border:1px solid #ccd3df;padding:8px;text-align:left;vertical-align:top;white-space:pre-wrap;overflow-wrap:anywhere}th{background:#edf2fa;position:sticky;top:0}input{padding:8px;width:360px}small{color:#536078}</style><h1>DRC中文增强版报告</h1>}
        puts $f "<p>Capture 原生 DRC + PCB 网表 · Occurrences · [llength $rows] 条问题 · 电源单点白名单豁免 $waived 条</p>"
        puts $f {<p><a href="drc.csv">下载 CSV</a> · <input id="search" placeholder="筛选规则、路径、位号或网络" aria-label="筛选结果"></p><table><thead><tr><th>规则</th><th>问题数</th></tr></thead><tbody>}
        dict for {id spec} $rules {
            if {[get $counts $id 0] == 0} {continue}
            set desc [explain [dict create rule_id $id]]
            puts $f "<tr><td>[html [dict get $desc title]]</td><td>[get $counts $id 0]</td></tr>"
        }
        if {[get $counts netlist_error 0]} {puts $f "<tr><td>网表输出错误</td><td>[get $counts netlist_error]</td></tr>"}
        puts $f {</tbody></table><table id="results"><thead><tr>}
        foreach key $fields {puts $f "<th>[html $key]</th>"}
        puts $f {</tr></thead><tbody>}
        foreach row $rows {
            puts $f <tr>
            foreach key $fields {
                set value [dict get $row $key]
                if {$key eq "message"} {set desc [explain $row]; set value "[dict get $desc explanation]\n[dict get $desc suggestion]\n\n$value"}
                puts $f "<td>[html $value]</td>"
            }
            puts $f </tr>
        }
        puts $f {</tbody></table><small>DRC 沿用 Capture 当前 ERC Matrix，忽略引脚电气类型冲突。原始 DRC 与设计文件放在同一目录，网表及日志在 netlist 目录。字段无对应对象时留空。</small><script>document.getElementById('search').addEventListener('input',function(){const q=this.value.toLowerCase();document.querySelectorAll('#results tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q));});</script></html>}
    } finally {close $f}
    return [dict create html $report csv $csv violations [llength $rows] waived $waived counts $counts]
}
