source [file join [file dirname [info script]] .. .. autoload drctoolMenu.tcl]
package require Tk; wm withdraw .
proc assert {condition} {if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}}
set ::helper [lindex $argv 0]
rename ::xiaokai::drc::aiHelper ::xiaokai::drc::realAiHelper
proc ::xiaokai::drc::aiHelper {} {return $::helper}
rename ::xiaokai::drc::resultState ::xiaokai::drc::realResultState
proc ::xiaokai::drc::resultState {r} {return current}
proc tk_messageBox {args} {error UNEXPECTED_MESSAGE_BOX}
proc tk_chooseDirectory {args} {error UNEXPECTED_FOLDER_DIALOG}
proc tk_getOpenFile {args} {error UNEXPECTED_FILE_DIALOG}
proc waitPanel {} {
    set deadline [expr {[clock milliseconds]+12000}]
    while {[dict size $::xiaokai::drc::panelJobs]} {
        update; after 20
        if {[clock milliseconds]>$deadline} {error PANEL_TIMEOUT}
    }
    update
}
proc oneWindow {} {
    set windows {}
    foreach child [winfo children .] {if {[winfo toplevel $child] eq $child} {lappend windows $child}}
    assert {$windows eq ".xiaokaiDrc"}
}
try {
    ::xiaokai::drc::show
    set pin {refdes U1 pin_number 3 _part_id 10 _pin_id 11 part_number FIXTURE123 footprint TEST}
    set row [dict create rule_id unconnected_pin hierarchy_path / _schematic ROOT sheet_name P refdes U1 _pin_specific 1 \
        _targets [list $pin] message {WARNING(ORCAP-1831): Unconnected pin U1,3}]
    set ::xiaokai::drc::result [dict create rows [list $row] design mock review_contexts {{path / schematic ROOT}}]
    ::xiaokai::drc::render
    set tree .xiaokaiDrc.list.tree
    set parent [lindex [$tree children {}] 0]
    $tree selection set [lindex [$tree children $parent] 0]
    ::xiaokai::drc::uiTab review; update
    assert {[winfo exists .xiaokaiDrc.tabs.review.tree]}
    dict set ::xiaokai::drc::reviewItems r1 ai {verdict uncertain reason preserved}
    ::xiaokai::drc::uiTab results; update
    ::xiaokai::drc::uiTab review; update
    assert {[dict get $::xiaokai::drc::reviewItems r1 ai reason] eq "preserved"}
    oneWindow
    ::xiaokai::drc::uiNative; update
    assert {[string first ORCAP-1831 [.xiaokaiDrc.tabs.native.text get 1.0 end]]>=0}
    ::xiaokai::drc::aiSettings; update; waitPanel
    assert {[winfo exists .xiaokaiDrc.tabs.settings.shared] && ![winfo exists .xiaokaiDrc.tabs.settings.secret]}
    set ::xiaokai::drc::settingsEndpoint [lindex $argv 2]
    set ::xiaokai::drc::settingsSecret dummy-panel-key
    set ::xiaokai::drc::settingsModel ""
    ::xiaokai::drc::settingsAction save; waitPanel
    assert {$::xiaokai::drc::settingsSecret eq "dummy-panel-key"}
    assert {!$::xiaokai::drc::settingsSavedKey}
    assert {[string first 模型 $::xiaokai::drc::settingsStatus]>=0}
    set ::xiaokai::drc::settingsModel fixture-model
    set ::xiaokai::drc::settingsSecret dummy-panel-key
    set ::xiaokai::drc::settingsModel ""
    ::xiaokai::drc::settingsAction models; waitPanel
    assert {$::xiaokai::drc::settingsSecret eq "dummy-panel-key"}
    assert {$::xiaokai::drc::settingsModels eq {fixture-model second-model}}
    set ::xiaokai::drc::settingsModel fixture-model
    ::xiaokai::drc::settingsAction save
    assert {$::xiaokai::drc::settingsSecret eq "dummy-panel-key"}
    waitPanel
    assert {[string first 已保存 $::xiaokai::drc::settingsStatus]>=0}
    assert {$::xiaokai::drc::settingsSecret eq "********" && $::xiaokai::drc::settingsSavedKey}
    ::xiaokai::drc::settingsAction test; waitPanel
    assert {[string first 连接成功 $::xiaokai::drc::settingsStatus]>=0}
    assert {$::xiaokai::drc::settingsModel eq "fixture-model"}
    set ::xiaokai::drc::settingsSecret wrong-draft-key
    ::xiaokai::drc::settingsAction test; waitPanel
    assert {$::xiaokai::drc::settingsSecret eq "wrong-draft-key"}
    assert {[string first {HTTP 401} $::xiaokai::drc::settingsStatus]>=0}
    assert {[string first invalid_api_key $::xiaokai::drc::settingsStatus]>=0}
    assert {[string first wrong-draft-key $::xiaokai::drc::settingsStatus]<0}
    set ::xiaokai::drc::settingsSecret $::xiaokai::drc::settingsKeyMarker
    ::xiaokai::drc::settingsAction read; waitPanel
    assert {$::xiaokai::drc::settingsSecret eq "********"}
    oneWindow
    ::xiaokai::drc::datasheetShow; waitPanel
    assert {[string first 未匹配 $::xiaokai::drc::datasheetStatus]>=0}
    set ::xiaokai::drc::datasheetPath [lindex $argv 1]
    ::xiaokai::drc::datasheetAction import; waitPanel
    assert {[string first 已归档 $::xiaokai::drc::datasheetStatus]>=0}
    set content [.xiaokaiDrc.tabs.datasheet.text get 1.0 end]
    assert {[string first {PDF 第 11 页} $content]>=0}
    ::xiaokai::drc::uiTab results; update
    ::xiaokai::drc::uiTab datasheet; update
    assert {[.xiaokaiDrc.tabs.datasheet.text get 1.0 end] eq $content}
    set ::xiaokai::drc::datasheetPath Z:/no-such-file.pdf
    ::xiaokai::drc::datasheetAction import; waitPanel
    assert {$::xiaokai::drc::datasheetStatus ne ""}
    assert {[.xiaokaiDrc.tabs.datasheet.text get 1.0 end] eq $content}
    set ::xiaokai::drc::settingsSecret unsaved-key
    ::xiaokai::drc::uiHide
    assert {$::xiaokai::drc::settingsSecret eq "********" && [wm state .xiaokaiDrc] eq "withdrawn"}
    oneWindow
    puts "PASS: one Tk window, shared settings redirect without Key fields, results/AI/native/PDF state; settings backend roundtrip, inline errors, DPAPI over stdin"
} on error {msg opts} {puts stderr [dict get $opts -errorinfo]; exit 1}
exit 0
