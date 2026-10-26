# SPDX-License-Identifier: GPL-3.0-only
source -encoding utf-8 [file join [file dirname [info script]] core.tcl]
source -encoding utf-8 [file join [file dirname [info script]] presentation.tcl]
source -encoding utf-8 [file join [file dirname [info script]] capture.tcl]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
set rules $::xiaokai::drc::rules
assert {[dict size $rules] == 11}
set original {RunElectricalRules 1 RunPhysicalRules 1 RunOnlineRules 1 RunCustomRules 1
    RunPhysicalRulePCBFootprintProp 1 RunPhysicalRulePCBFootprintPath 1 RunPhysicalRulePwrGndShort 1
    RunPhysicalRuleDeviceZeroPins 1 RunPhysicalRuleHighSpeedProps 1 RunElectricRuleOffpage 1
    RunFutureRule 1 RunElectricalReports 1 RunPhysicalReports 1
    Scope 1 Mode 1 IgnoreWarnings ORCAP-1829
    ERCMatrix {IN_PIN {- E W} OUT_PIN {E - W}}}
dict for {id spec} $rules {dict set original [lindex $spec 1] 1}
dict for {id spec} $rules {
    set cfg [${ns}::configFor $original $id {D:/报告 "test"/native.drc}]
    set on {}; dict for {k v} $cfg {if {[string match Run* $k] && $v eq "1"} {lappend on $k}}
    assert {[llength $on] == 2}
    assert {[dict get $cfg [lindex $spec 1]] == 1}
    assert {[dict get $cfg Scope] == 0 && [dict get $cfg Mode] == 0}
    assert {[dict get $cfg ERCMatrix] eq [dict get $original ERCMatrix]}
    assert {[dict get $cfg DRCMarkerForWarnings] == 0}
}
assert {[catch {${ns}::configFor $original forbidden file}]}
set batch [${ns}::batchConfig $original file]
set enabled {}; dict for {k v} $batch {if {[string match Run* $k] && $v eq "1"} {lappend enabled $k}}
assert {[llength $enabled] == 13}
dict for {id spec} $rules {assert {[dict get $batch [lindex $spec 1]] == 1}}
assert {[dict get $batch RunElectricalRules] == 1 && [dict get $batch RunPhysicalRules] == 1}
assert {[dict get $batch ERCMatrix] eq [dict get $original ERCMatrix]}
foreach {heading rule} {
    {Checking For Single Node Nets} single_node_nets
    {Checking For Unconnected Bus Nets} unconnected_bus
    {Checking Pin to Port Connections} hier_port_conn
    {INFO(ORCAP-2242): Checking Incorrect Pin Group Assignment} pin_group_assign
    {Checking Power Pin Visibility} power_pin_visibility
    {Checking Normal Convert View Sync} convert_view_sync
    {INFO(ORCAP-36105): Checking Missing Pin Numbers} missing_pin_num
    {Checking Name Property for Hierarchical Instances} name_prop_consistency
} {
    set parsed [${ns}::diagnostics "$heading\nERROR(ORCAP-99999): native test\n"]
    assert {[dict get [lindex $parsed 0] rule_id] eq $rule}
}
assert {[${ns}::diagnosticRule {WARNING(ORCAP-1608): Net has no driving source X_BAR}] eq "drive_source_pin_conflict"}
assert {[${ns}::diagnosticRule {WARNING(ORCAP-9999): Duplicate net name CLK}] eq "duplicate_net_name"}
set unidentified [lindex [${ns}::diagnostics {ERROR(ORCAP-99999): unfamiliar diagnostic}] 0]
set unidentifiedRow [${ns}::row "" $unidentified]
assert {[dict get $unidentifiedRow rule_id] eq ""}
assert {[dict get [${ns}::explain $unidentifiedRow] title] ne ""}
set header {Checking Schematic: halfadd_A HALFADD}
set text "$header\r\nChecking Electrical Rules\r\nWARNING(ORCAP-1829): Possible pin type conflict U3A,O  Output Connected to Input\r\n                    HALFADD, HALFADD  (3.50, 2.90) \r\n\r\nINFO(ORCAP-2242): Checking Incorrect Pin Group Assignment\r\nChecking Schematic: halfadd_B HALFADD\r\nERROR(ORCAP-1): example\r\n  continued\r\n"
set diags [${ns}::diagnostics $text]
assert {[llength $diags] == 2}
assert {[dict get [lindex $diags 0] schematic] eq "halfadd_A HALFADD"}
set r [${ns}::row drive_source_pin_conflict [lindex $diags 0]]
assert {[dict get $r refdes] eq "U3A" && [dict get $r pin_info] eq "O"}
assert {[dict get $r sheet_name] eq "HALFADD"}
set contexts {{path / schematic FULLADD} {path /halfadd_A schematic HALFADD} {path /halfadd_B schematic HALFADD}}
assert {[${ns}::resolveContexts {halfadd_A HALFADD} $contexts] eq "/halfadd_A"}
assert {[${ns}::resolveContexts HALFADD $contexts] eq "/halfadd_A /halfadd_B"}
assert {[${ns}::resolveContexts FULLADD $contexts] eq "/"}
set pin {hierarchy_path /halfadd_A schematic HALFADD sheet_name HALFADD refdes U3A instance_ref U3
    pin_name O pin_number 3 pin_type 2 net_name {<NET,1>} flat_net flatA is_power 0}
set pinB [dict replace $pin hierarchy_path /halfadd_B refdes U3B flat_net flatB net_name NET_B]
set model [dict create contexts $contexts pins [list $pin $pinB]]
set enriched [${ns}::enrich drive_source_pin_conflict [lindex $diags 0] $model]
assert {[llength $enriched] == 1}
set er [lindex [lindex $enriched 0] 0]
assert {[dict get $er hierarchy_path] eq "/halfadd_A"}
assert {[dict get $er net_name] eq "<NET,1>"}
set singleDiag {schematic {halfadd_A HALFADD} message {WARNING(ORCAP-1600): Net has fewer than two connections LOCAL}}
set sharedPower [dict replace $pin refdes U3A package_ref U3 pin_name VCC pin_number 14 is_power 1 local_net LOCAL net_name VCC]
set otherSection [dict replace $sharedPower refdes U3B]
set modelPower [dict create contexts $contexts pins [list $sharedPower $otherSection]]
set enrichedPower [${ns}::enrich single_node_nets $singleDiag $modelPower]
assert {[dict get [lindex [lindex $enrichedPower 0] 0] net_name] eq "VCC"}
assert {[llength [lindex [lindex $enrichedPower 0] 1]] == 1}
assert {[${ns}::exempt {*}[lindex $enrichedPower 0] {{net_name VCC}}]}
set anotherPower [dict replace $sharedPower refdes U4A package_ref U4]
dict lappend modelPower pins $anotherPower
set enrichedPower [${ns}::enrich single_node_nets $singleDiag $modelPower]
assert {![${ns}::exempt {*}[lindex $enrichedPower 0] {{net_name VCC}}]}
set power [dict replace $pin is_power 1 net_name VCC]
set single [dict replace $er rule_id single_node_nets]
assert {[${ns}::exempt $single [list $power] {{net_name VCC}}]}
assert {![${ns}::exempt $single [list $pin] {{refdes *}}]}
assert {![${ns}::exempt $single [list $power $power] {{net_name VCC}}]}
assert {![${ns}::exempt $er [list $power] {{net_name VCC}}]}
assert {![${ns}::exempt $single {} {{net_name VCC}}]}
assert {[catch {${ns}::exempt $single [list $power] {{arbitrary *}}}]}
# Verify callback and settings restoration when Capture fails, including the
# "no callback/no new report" case that must not be reported as a clean design.
proc ::capAutoDRCConfig_InitDRCConfig {} {return ORIGINAL}
set suppressOption 0
proc ::GetOptionBool {key} {return $::suppressOption}
proc ::SetOptionBool {key value} {set ::suppressOption [expr {$value eq "TRUE"}]}
proc ::TclScript {path} {
    set ::replayFile $path
    source $path
}
proc ::Menu {args} {
    assert {$::suppressOption == 1}
    assert {$args eq {{PCB::Design Rules Check} | MessageBox YES {One or more errors or warnings were encountered.}}}
    error "Injected native failure"
}
set tmp [file join [file dirname [info script]] test-output unit-[pid]]
assert {[catch {${ns}::nativePass $original [file join $tmp missing.drc]} message]}
assert {[capAutoDRCConfig_InitDRCConfig] eq "ORIGINAL"}
assert {![llength [info commands ${ns}::savedConfigHook]]}
assert {$suppressOption == 0}
assert {![file exists $replayFile]}
rename Menu {}
proc ::Menu {args} {capAutoDRCConfig_InitDRCConfig}
assert {[catch {${ns}::nativePass $original [file join $tmp missing.drc]} message]}
assert {[string match {*Capture*} $message]}
file mkdir $tmp
set staleReport [file join $tmp stale.drc]
set f [open $staleReport w]; puts $f "Checking Entire Design: stale"; close $f
assert {[catch {${ns}::nativePass $original $staleReport}]}
assert {![file exists $staleReport]}
set result [${ns}::writeReports $tmp [list [dict replace $er message "<script>alert(1)</script>\n\"quoted\", 中文"]] {drive_source_pin_conflict 1} 0]
set f [open [dict get $result html] r]; fconfigure $f -encoding utf-8; set html [read $f]; close $f
assert {[string first {&lt;script&gt;} $html] >= 0}
assert {[string first {<script>alert} $html] < 0}
set f [open [dict get $result csv] r]; fconfigure $f -encoding utf-8; set csv [read $f]; close $f
assert {[string index $csv 0] eq "\ufeff"}
assert {[string first {""quoted""} $csv] >= 0}
set f [open [file join $tmp config.json] w]; fconfigure $f -encoding utf-8
puts $f [${ns}::configJson [dict replace $original ReportFileName "D:/中文/\"x\"\n\t\\test"]]; close $f
puts "PASS: 11-rule allowlist, native settings, hierarchy instances, power whitelist, failure cleanup, HTML/CSV"
puts "Artifacts: $tmp"
# Check the deployed, system-encoding-safe single-file payload as well.
source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
assert {[dict size $::xiaokai::drc::rules] == 11}
set result [${ns}::writeReports [file join $tmp delivered] {} {} 0]
set f [open [dict get $result html] r]; fconfigure $f -encoding utf-8; set html [read $f]; close $f
assert {[string first "DRC\u4e2d\u6587\u589e\u5f3a\u7248\u62a5\u544a" $html] >= 0}
assert {[string first {\u5c0f} $html] < 0}
puts "PASS: delivered plugin UTF-8 HTML + multi-section power-pin whitelist"
set a [dict replace $er message {WARNING(ORCAP-1): No driving source} net_name RESET]
set b [dict replace $a pin_info U2.3 refdes U2 message {WARNING(ORCAP-1): No driving source U2}]
assert {[dict size [${ns}::groupRows [list $a $b]]] == 1}
assert {[dict size [${ns}::groupRows [list $a [dict replace $b hierarchy_path /halfadd_B]]]] == 2}
assert {[dict size [${ns}::groupRows [list $a $a]]] == 1}
assert {[dict size [${ns}::groupRows [list $a] DOES_NOT_EXIST]] == 0}
assert {[dict get [${ns}::explain $a] kind] eq "no_driver"}
assert {[dict get [${ns}::explain [dict replace $a message {Possible pin type conflict}]] kind] eq "pin_conflict"}
set groups [${ns}::groupRows [list $a $b] RESET]
assert {[llength [lindex [dict values $groups] 0]] == 2}
puts "PASS: Chinese causes, shared-net grouping, occurrence isolation, search, exact deduplication"
# A docked Project Manager can belong to a different project after Batch DRC.
# Activate by full project path before selecting; refuse a mismatched design.
rename ::xiaokai::drc::cstring ::xiaokai::drc::realCString
proc ::xiaokai::drc::cstring {design args} {
    if {$design eq "wrong"} {return D:/other.dsn}
    return D:/reports/inspection.dsn
}
namespace eval ::ui {}
proc ::ui::PMActivate {path} {set ::activatedProject $path}
proc ::SelectPMItem {path} {
    if {![info exists ::activatedProject]} {error "Project not activated"}
}
proc ::GetActivePMDesign {} {return $::activeTestDesign}
set activeTestDesign expected
assert {[${ns}::focusDesign expected inspection.dsn] eq "expected"}
assert {$activatedProject eq "D:/reports/inspection.opj"}
set activeTestDesign wrong
assert {[catch {${ns}::focusDesign expected inspection.dsn}]}
rename ::xiaokai::drc::cstring {}; rename ::xiaokai::drc::realCString ::xiaokai::drc::cstring
puts "PASS: activate owning project before selection, reject wrong design"
