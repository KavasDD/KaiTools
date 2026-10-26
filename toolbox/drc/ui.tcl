# SPDX-License-Identifier: GPL-3.0-only
namespace eval ::xiaokai::drc {
    variable result {}
    variable itemRows {}
    variable status "点击“检查当前设计”开始。"
    variable query ""
    variable details "选中问题查看中文说明；双击具体位置跳转。"
    variable launchPending 0
    variable freshnessTimer ""
    variable stale 0
    variable completeStatus ""
}
proc ::xiaokai::drc::foreground {} {
    set w .xiaokaiDrc
    if {![winfo exists $w]} {return}
    wm title $w "DRC中文增强版"
    wm deiconify $w
    wm attributes $w -topmost 1
    raise $w
    focus $w.list.tree
    watchFreshness
}
proc ::xiaokai::drc::watchFreshness {} {
    variable freshnessTimer
    if {$freshnessTimer ne ""} {after cancel $freshnessTimer}
    set freshnessTimer [after 1500 ::xiaokai::drc::pollFreshness]
}
proc ::xiaokai::drc::pollFreshness {} {
    variable freshnessTimer; variable result; variable busy
    set freshnessTimer ""
    if {![winfo exists .xiaokaiDrc] || [wm state .xiaokaiDrc] eq "withdrawn"} {return}
    if {!$busy && [dict exists $result rows]} {refreshFreshness $result}
    watchFreshness
}
proc ::xiaokai::drc::refreshFreshness {checkedResult} {
    variable status; variable stale; variable completeStatus
    if {$stale} {return 0}
    if {[catch {resultState $checkedResult} state]} {set state unavailable}
    switch $state {
        stale {
            set stale 1
            set status "设计已修改，结果待更新。请重新检查。"
            detailText "设计已修改，结果待更新。重新检查后可继续双击定位和导出。"
            .xiaokaiDrc.bar.export configure -state disabled
            return 0
        }
        other {set status "请切回本次检查的设计；当前显示的是上次检查结果。"; return 0}
        unavailable {set status "无法确认当前设计状态，请切回设计或重新检查。"; return 0}
    }
    if {$completeStatus ne "" && ([string match {请切回*} $status] || [string match {无法确认*} $status])} {set status $completeStatus}
    return 1
}
proc ::xiaokai::drc::start {} {
    variable busy; variable launchPending; variable query
    show
    foreground
    if {$busy || $launchPending} {return}
    set query ""
    set launchPending 1
    # Let Tk map the results window and minimize the launcher before native work.
    after idle {
        set ::xiaokai::drc::launchPending 0
        ::xiaokai::drc::uiCheck
    }
}
proc ::xiaokai::drc::netlistProgress {} {
    variable status
    if {![llength [info commands winfo]] || ![winfo exists .xiaokaiDrc]} {return}
    set status "DRC 已完成，正在输出网表…"
    detailText "正在用 Capture 原生引擎输出 PCB 网表，请稍候。"
    update idletasks
}
proc ::xiaokai::drc::show {} {
    package require Tk
    set w .xiaokaiDrc
    if {[winfo exists $w]} {foreground; return}
    toplevel $w
    wm title $w "DRC中文增强版"
    wm attributes $w -topmost 1
    wm geometry $w 900x590
    wm minsize $w 640 430
    ttk::frame $w.bar -padding 10
    ttk::button $w.bar.check -text "检查当前设计" -command ::xiaokai::drc::uiCheck
    ttk::entry $w.bar.search -textvariable ::xiaokai::drc::query -width 26
    ttk::label $w.bar.label -text "搜索："
    ttk::button $w.bar.export -text "导出报告" -command ::xiaokai::drc::uiExport -state disabled
    pack $w.bar.check -side left -padx {0 18}
    pack $w.bar.label $w.bar.search -side left
    pack $w.bar.export -side right
    ttk::label $w.status -textvariable ::xiaokai::drc::status -padding {12 5}
    ttk::frame $w.list -padding {10 5}
    ttk::treeview $w.list.tree -columns {location count} -show {tree headings} -selectmode browse
    $w.list.tree heading #0 -text "问题 / 受影响对象"
    $w.list.tree heading location -text "位置"
    $w.list.tree heading count -text "条数"
    $w.list.tree column #0 -width 390 -minwidth 200
    $w.list.tree column location -width 330 -minwidth 160
    $w.list.tree column count -width 55 -stretch 0 -anchor center
    ttk::scrollbar $w.list.scroll -orient vertical -command [list $w.list.tree yview]
    $w.list.tree configure -yscrollcommand [list $w.list.scroll set]
    pack $w.list.scroll -side right -fill y
    pack $w.list.tree -fill both -expand 1
    ttk::frame $w.bottom -padding 10
    text $w.bottom.text -height 6 -wrap word -font TkDefaultFont -relief flat -state disabled
    ttk::button $w.bottom.native -text "原生详细信息" -command ::xiaokai::drc::uiNative -state disabled
    pack $w.bottom.text -fill both -expand 1
    pack $w.bottom.native -side left -padx {0 10} -pady {8 0}
    pack $w.bar $w.status -fill x
    pack $w.bottom -side bottom -fill x
    pack $w.list -fill both -expand 1
    bind $w.bar.search <KeyRelease> {::xiaokai::drc::render}
    bind $w.list.tree <<TreeviewSelect>> {::xiaokai::drc::uiSelect}
    bind $w.list.tree <Double-Button-1> {::xiaokai::drc::uiDouble %x %y; break}
    bind $w.list.tree <Return> {::xiaokai::drc::uiLocate; break}
    wm protocol $w WM_DELETE_WINDOW [list wm withdraw $w]
    detailText "选中问题查看中文说明；双击具体位置跳转。"
    watchFreshness
}
proc ::xiaokai::drc::detailText {text} {
    set t .xiaokaiDrc.bottom.text
    if {![winfo exists $t]} {return}
    $t configure -state normal
    $t delete 1.0 end
    $t insert end $text
    $t configure -state disabled
}
proc ::xiaokai::drc::uiCheck {} {
    variable busy; variable result; variable status; variable powerWhitelist; variable stale; variable completeStatus
    if {$busy} {return}
    set result {}; set stale 0; set completeStatus ""; set status "正在保存并检查…"
    detailText "正在保存并检查当前设计，请稍候。"
    .xiaokaiDrc.bar.check configure -state disabled
    .xiaokaiDrc.bar.export configure -state disabled
    render
    update idletasks
    try {
        set result [run "" $powerWhitelist]
        set n [dict get $result violations]
        if {$n == 0} {
            set status "检查完成，未发现问题。"
            detailText "检查完成，未发现问题。"
        } else {
            set status "发现 $n 条问题，已按共性原因归纳。展开后双击具体位置。"
            detailText "选中问题查看中文说明；展开后双击具体位置跳转。"
        }
        if {[dict get $result waived]} {append status "  电源白名单豁免 [dict get $result waived] 条。"}
        set completeStatus $status
        .xiaokaiDrc.bar.export configure -state normal
    } on error {msg opts} {
        set result {}; set status "检查未完成"
        detailText $msg
        puts [dict get $opts -errorinfo]
    } finally {
        .xiaokaiDrc.bar.check configure -state normal
        render
        foreground
    }
}
proc ::xiaokai::drc::render {} {
    variable result; variable itemRows; variable query
    set t .xiaokaiDrc.list.tree
    if {![winfo exists $t]} {return}
    $t delete [$t children {}]
    set itemRows {}
    .xiaokaiDrc.bottom.native configure -state disabled
    $t tag configure unavailable -foreground #777777
    if {![dict exists $result rows]} {return}
    dict for {key rows} [groupRows [dict get $result rows] $query] {
        set first [lindex $rows 0]; set desc [explain $first]
        set location "[get $first hierarchy_path] · [get $first sheet_name]"
        if {[get $first net_name] ne ""} {append location " · [get $first net_name]"}
        if {[get $first net_name] eq "" && [get $first refdes] ne ""} {append location " · [get $first refdes]"}
        set parent [$t insert {} end -text [dict get $desc title] -values [list $location [llength $rows]]]
        dict set itemRows $parent $rows
        foreach row $rows {
            set childDesc [explain $row]
            set label [get $childDesc summary [get $childDesc title]]
            set position "[get $row hierarchy_path] · [get $row sheet_name]"
            set tags {}
            if {![canLocate $row]} {append position " · 无定位信息"; set tags unavailable}
            set child [$t insert $parent end -text $label -tags $tags -values [list $position ""]]
            dict set itemRows $child [list $row]
        }
    }
}
proc ::xiaokai::drc::selectedRows {} {
    variable itemRows
    set t .xiaokaiDrc.list.tree
    set id [lindex [$t selection] 0]
    return [get $itemRows $id {}]
}
proc ::xiaokai::drc::uiSelect {} {
    set rows [selectedRows]
    if {![llength $rows]} {return}
    set row [lindex $rows 0]; set desc [explain $row]
    detailText "[dict get $desc explanation]\n\n建议：[dict get $desc suggestion]\n\n位置：[get $row hierarchy_path] · [get $row sheet_name]    [get $row pin_info]"
    if {![canLocate $row]} {detailText "[dict get $desc explanation]\n\n建议：[dict get $desc suggestion]\n\n无定位信息：原生报告未提供可用对象或坐标。"}
    .xiaokaiDrc.bottom.native configure -state normal
}
proc ::xiaokai::drc::uiDouble {x y} {
    set t .xiaokaiDrc.list.tree
    if {[$t identify region $x $y] ni {tree cell}} {return}
    set id [$t identify row $x $y]
    if {$id eq ""} {return}
    $t selection set $id
    $t focus $id
    # Parents expand; leaves locate. A multi-position group never jumps to an
    # arbitrary first occurrence.
    if {[llength [$t children $id]]} {
        $t item $id -open [expr {![$t item $id -open]}]
        return
    }
    # Finish the mouse event before asking Capture to activate a native page.
    # Pass the clicked row explicitly; a queued selection event cannot change it.
    variable itemRows; variable result
    set rows [get $itemRows $id {}]
    if {[llength $rows] == 1} {after idle [list ::xiaokai::drc::uiLocateRow [lindex $rows 0] $result]}
}
proc ::xiaokai::drc::uiLocate {} {
    variable result
    set rows [selectedRows]
    if {[llength $rows] != 1} {return}
    uiLocateRow [lindex $rows 0] $result
}
proc ::xiaokai::drc::uiLocateRow {row checkedResult} {
    variable status; variable busy
    if {$busy} {return}
    if {![refreshFreshness $checkedResult]} {return}
    if {![canLocate $row]} {set status "无定位信息：请查看原生详细信息。"; return}
    if {[catch {locate $row $checkedResult} msg]} {set status $msg} else {set status "已定位：[get $row hierarchy_path] · [get $row sheet_name]"}
}
proc ::xiaokai::drc::uiNative {} {
    set rows [selectedRows]
    if {![llength $rows]} {return}
    set messages {}; foreach row $rows {lappend messages [get $row message]}
    set w .xiaokaiDrcNative
    catch {destroy $w}
    toplevel $w; wm title $w "原生详细信息"; wm geometry $w 760x380
    text $w.text -wrap word -font TkFixedFont
    $w.text insert end [join $messages \n\n]
    $w.text configure -state disabled
    pack $w.text -fill both -expand 1
}
proc ::xiaokai::drc::uiExport {} {
    variable result; variable status
    if {![dict exists $result rows]} {return}
    if {![refreshFreshness $result]} {return}
    set dir [tk_chooseDirectory -title "导出中文报告和 CSV"]
    if {$dir eq ""} {return}
    if {[catch {
        set out [file join $dir drc_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[clock clicks]]
        set saved [writeReports $out [dict get $result rows] [dict get $result counts] [dict get $result waived]]
        if {[file isdirectory [file join [dict get $result workdir] netlist]]} {
            file copy [file join [dict get $result workdir] netlist] [file join $out netlist]
        }
        set status "报告已导出：[dict get $saved html]"
    } msg]} {set status "导出失败：$msg"}
}
