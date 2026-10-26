# SPDX-License-Identifier: GPL-3.0-only
proc ::xiaokai::textaffix::updateControls {} {
    variable active
    set w .xiaokaiTextAffix
    if {![llength [info commands winfo]] || ![winfo exists $w]} {return}
    $w.status configure -foreground [expr {$active ? "#1765a3" : "#555555"}]
}

proc ::xiaokai::textaffix::hide {} {
    stop
    if {[llength [info commands winfo]] && [winfo exists .xiaokaiTextAffix]} {wm withdraw .xiaokaiTextAffix}
}

proc ::xiaokai::textaffix::preview {args} {
    variable text; variable side
    set w .xiaokaiTextAffix
    if {[winfo exists $w]} {
        set result "${text}10K"
        if {$side eq "after"} {set result "10K${text}"}
        $w.preview configure -text "示例：10K  →  $result"
    }
}

proc ::xiaokai::textaffix::show {} {
    set hadTk [expr {[llength [info commands winfo]] > 0}]
    package require Tk
    if {!$hadTk} {catch {wm withdraw .}}
    set w .xiaokaiTextAffix
    if {[winfo exists $w]} {wm deiconify $w; raise $w; start; return}
    if {[catch {package require capAppUtils}]} {toplevel $w} else {capAppUtils::capTopLevel $w}
    wm title $w "文字前后缀"
    wm resizable $w 0 0
    wm attributes $w -topmost 1
    ttk::label $w.label -text "添加文字"
    ttk::entry $w.text -textvariable ::xiaokai::textaffix::text -width 36
    ttk::radiobutton $w.before -text "添加到现有文字前" -variable ::xiaokai::textaffix::side -value before
    ttk::radiobutton $w.after -text "添加到现有文字后" -variable ::xiaokai::textaffix::side -value after
    ttk::label $w.preview -foreground #1765a3
    ttk::checkbutton $w.properties -text "元件属性" -variable ::xiaokai::textaffix::properties
    ttk::entry $w.propname -textvariable ::xiaokai::textaffix::property -width 24
    ttk::label $w.prophint -text "单击属性文字：修改该属性；选中元件：使用右侧属性名。" -wraplength 440
    ttk::checkbutton $w.networks -text "网络名称（导线／标签／页间连接符／端口／电源）" -variable ::xiaokai::textaffix::networks
    ttk::checkbutton $w.removeExisting -text "已有相同前缀／后缀时去掉原有前缀／后缀" -variable ::xiaokai::textaffix::removeExisting
    ttk::label $w.note -text "网络：同步修改当前原理图各页的同网标签；无标签时添加网络别名。\n框选整颗元件默认修改 Value，可在上方换成其他属性名。" -wraplength 440 -justify left
    ttk::button $w.apply -text "处理当前选择" -command ::xiaokai::textaffix::applySelection
    ttk::button $w.undo -text "撤销上次处理" -command ::xiaokai::textaffix::undo
    ttk::button $w.close -text "关闭（Esc）" -command ::xiaokai::textaffix::hide
    ttk::label $w.status -textvariable ::xiaokai::textaffix::status -wraplength 440 -justify left
    grid $w.label -row 0 -column 0 -sticky w -padx 12 -pady {14 6}
    grid $w.text -row 0 -column 1 -sticky ew -padx 12 -pady {14 6}
    grid $w.before -row 1 -column 0 -sticky w -padx 12 -pady 4
    grid $w.after -row 1 -column 1 -sticky w -padx 12 -pady 4
    grid $w.preview -row 2 -column 0 -columnspan 2 -sticky w -padx 12 -pady 6
    grid $w.properties -row 3 -column 0 -sticky w -padx 12 -pady 4
    grid $w.propname -row 3 -column 1 -sticky ew -padx 12 -pady 4
    grid $w.prophint -row 4 -column 0 -columnspan 2 -sticky w -padx 12 -pady 3
    grid $w.networks -row 5 -column 0 -columnspan 2 -sticky w -padx 12 -pady 4
    grid $w.removeExisting -row 6 -column 0 -columnspan 2 -sticky w -padx 12 -pady 4
    grid $w.note -row 7 -column 0 -columnspan 2 -sticky w -padx 12 -pady 6
    grid $w.apply -row 8 -column 0 -sticky ew -padx 12 -pady 6
    grid $w.undo -row 8 -column 1 -sticky ew -padx 12 -pady 6
    grid $w.close -row 9 -column 0 -columnspan 2 -sticky ew -padx 12 -pady 6
    grid $w.status -row 10 -column 0 -columnspan 2 -sticky w -padx 12 -pady {6 14}
    wm protocol $w WM_DELETE_WINDOW ::xiaokai::textaffix::hide
    bind $w <Escape> ::xiaokai::textaffix::hide
    foreach name {text side} {trace add variable ::xiaokai::textaffix::$name write ::xiaokai::textaffix::preview}
    preview
    updateControls
    start
    focus $w.text
}
