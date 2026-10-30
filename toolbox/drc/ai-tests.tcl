source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ns ::xiaokai::drc
set pin {hierarchy_path / schematic ROOT sheet_name P refdes U1 pin_number 3 pin_name EN pin_type 1 net_name A local_net A flat_net secret-native-pointer _part_id 10 _pin_id 11 _pin_point {100 100}}
set row [dict create rule_id unconnected_pin _targets [list $pin] message {Unconnected U1,EN}]
set fixture [dict create pins [list $pin [dict replace $pin refdes U2 _part_id 20] [dict replace $pin flat_net other-native net_name B _part_id 30]]]
rename ${ns}::snapshot ${ns}::nativeSnapshot
proc ${ns}::snapshot {design} {return $::fixture}
set payload [${ns}::aiPayload [dict create r1 [dict create row $row]] {design mock} {核查此连接} batch-1]
set json [dict get $payload json]
assert {[string first secret-native-pointer $json] == -1 && [string first other-native $json] == -1}
assert {[string first _part_id $json] == -1 && [string first _pin_id $json] == -1}
assert {[string first U2 $json] >= 0 && [string first U1 $json] >= 0}
assert {[string first F1.DRC $json] >= 0 && [string first F1.PINS $json] >= 0}
assert {[string first target_networks $json] >= 0 && [string first endpoints $json] >= 0}
assert {[catch {${ns}::aiPayload {} {design mock} q batch}]}
assert {[catch {${ns}::aiPayload [dict create r1 [dict create row $row]] {design mock} [string repeat x 2001] batch}]}
set f [open [file join [file dirname [info script]] test-output ai-payload.json] w]
fconfigure $f -encoding utf-8; puts $f $json; close $f
proc enc {s} {return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $s]]}
set body "OK\tbatch-1\nF1\tuncertain\t[enc F1.DRC]\t[enc 待核查]\t[enc 查阅手册]\t[enc 检查引脚]\n"
set job {request_id batch-1 bindings {F1 r1}}
set parsed [${ns}::aiReadResult $body $job]
assert {[dict get $parsed r1 reason] eq "待核查"}
assert {[dict get $parsed r1 baseline]}
set proven "OK\tbatch-1\nF1\terror\t[enc {F1.DS1, F1.PINS, F1.DRC}]\t[enc 输入悬空]\t[enc {PDF 第 11 页}]\t[enc 输入悬空]\t[enc {TI SCLS264R 第 11 页 原文}]\n"
assert {[dict get [${ns}::aiReadResult $proven $job] r1 verdict] eq "error"}
assert {[dict get [${ns}::aiReadResult [string map {error allowed} $proven] $job] r1 verdict] eq "allowed"}
foreach invalid [list [string map {batch-1 wrong} $body] [string map {F1\t F2\t} $body] \
    [string map {uncertain error} $body] "$body[lindex [split $body \n] 1]\n" "OK\tbatch-1\n"] {
    assert {[catch {${ns}::aiReadResult $invalid $job}]}
}
assert {[catch {${ns}::aiReadResult "ERROR\t[enc {API 请求失败}]\n" $job} message] && $message eq "API 请求失败"}
# Stale/native-project changes and closed review discard completed responses.
package require Tk; wm withdraw .
proc ${ns}::resultState {r} {return stale}
set directory [file join [file dirname [info script]] test-output ai-stale]
file mkdir $directory
set output [file join $directory result.tsv]; set f [open $output w]; puts -nonewline $f $body; close $f
set ::xiaokai::drc::reviewPreview {design mock}; toplevel .xiaokaiDrc; ttk::notebook .xiaokaiDrc.tabs; ttk::frame .xiaokaiDrc.tabs.review
set ::xiaokai::drc::aiJob [dict merge $job [dict create output $output directory $directory cancel [file join $directory cancel] checked {design mock} started [clock milliseconds] cancelled 0]]
set ::xiaokai::drc::reviewItems {r1 {row example}}
${ns}::aiPoll
assert {![dict exists $::xiaokai::drc::reviewItems r1 ai] && [string first 已丢弃 $::xiaokai::drc::aiStatus] >= 0}
assert {![file exists $output]}
destroy .xiaokaiDrc.tabs.review
puts "PASS: sanitized occurrence/net context, bounded payload, strict batch/target/completeness validation, no automatic confirmation, stale result discarded and temporary request cleaned"
exit 0
