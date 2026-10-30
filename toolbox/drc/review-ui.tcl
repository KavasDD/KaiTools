proc ::xiaokai::drc::reviewSelectedShow {} {
    set rows [selectedRows]
    if {[llength $rows] == 1} {reviewShow [lindex $rows 0]} else {reviewShow}
}
proc ::xiaokai::drc::reviewButtonToggle {} {
    variable reviewVisible
    set reviewVisible [expr {!$reviewVisible}]
    reviewToggle
}
proc ::xiaokai::drc::reviewShow {{selectedRow {}}} {
    variable result; variable reviewPreview; variable reviewItems; variable reviewConfirmed; variable reviewHint
    if {![dict exists $result rows] || ![refreshFreshness $result]} {return}
    set w .xiaokaiDrc.tabs.review
    if {[winfo exists $w.tree] && $reviewPreview eq $result} {
        if {[dict size $selectedRow]} {
            dict for {id item} $reviewItems {
                if {[reviewKey [dict get $item row]] eq [reviewKey $selectedRow]} {
                    $w.tree selection set $id; $w.tree focus $id; $w.tree see $id; reviewSelect; break
                }
            }
        }
        uiTab review
        return
    }
    aiCancel
    set reviewPreview $result; set reviewItems {}; set reviewConfirmed {}
    set reviewHint "双击定位；点击左上方“一键放置 Text”即可标注。"
    foreach child [winfo children $w] {destroy $child}
    ttk::frame $w.ai -padding 10
    ttk::entry $w.ai.question -textvariable ::xiaokai::drc::aiQuestion
    ttk::button $w.ai.analyze -text "分析全部" -command ::xiaokai::drc::reviewAiAction
    ttk::button $w.ai.datasheet -text "器件手册" -command ::xiaokai::drc::datasheetShow
    pack $w.ai.analyze $w.ai.datasheet -side right -padx 5
    pack $w.ai.question -side left -fill x -expand 1
    ttk::label $w.aiStatus -textvariable ::xiaokai::drc::aiStatus -wraplength 780 -padding {10 0 10 6}
    ttk::progressbar $w.progress -mode indeterminate
    text $w.progressLog -height 2 -wrap word -font TkDefaultFont -state disabled
    panelText $w.progressLog $::xiaokai::drc::aiLog
    ttk::treeview $w.tree -columns {state object position text} -show headings -selectmode browse -height 5
    foreach {column label width} {state 状态 90 object 对象 80 position 图纸 280 text 短标注 180} {
        $w.tree heading $column -text $label; $w.tree column $column -width $width -minwidth 60
    }
    ttk::label $w.connectionStatus -textvariable ::xiaokai::drc::connectionStatus -wraplength 780 -padding {10 4}
    ttk::frame $w.connections
    ttk::treeview $w.connections.tree -columns {net refdes pin position} -show headings -selectmode browse -height 4 \
        -yscrollcommand [list $w.connections.scroll set]
    foreach {column label width} {net 网络 160 refdes 器件 70 pin 引脚 110 position 层次与图纸 270} {
        $w.connections.tree heading $column -text $label; $w.connections.tree column $column -width $width -minwidth 45
    }
    ttk::scrollbar $w.connections.scroll -command [list $w.connections.tree yview]
    pack $w.connections.scroll -side right -fill y
    pack $w.connections.tree -fill both -expand 1
    bind $w.connections.tree <Double-Button-1> {::xiaokai::drc::connectionClick %x %y; break}
    text $w.evidence -height 7 -wrap word -font TkDefaultFont -state disabled
    ttk::panedwindow $w.body -orient vertical
    foreach {name weight} {candidates 2 endpoints 2 details 3} {
        ttk::frame $w.body.$name
        $w.body add $w.body.$name -weight $weight
    }
    ttk::label $w.hint -textvariable ::xiaokai::drc::reviewHint -wraplength 780 -padding 10
    pack $w.ai $w.aiStatus -fill x
    pack $w.progress $w.progressLog -fill x -padx 10 -pady {0 5}
    pack $w.hint -side bottom -fill x
    pack $w.body -fill both -expand 1 -padx 10
    pack $w.tree -in $w.body.candidates -fill both -expand 1
    pack $w.connectionStatus -in $w.body.endpoints -fill x
    pack $w.connections -in $w.body.endpoints -fill both -expand 1
    pack $w.evidence -in $w.body.details -fill both -expand 1 -pady 3
    set index 0; set selected ""
    foreach row [dict get $result rows] {
        if {[get $row rule_id] ni {unconnected_pin single_node_nets drive_source_pin_conflict}} {continue}
        set id r[incr index]; set item [dict create row $row]
        if {[catch {reviewCandidate $row $result} candidate]} {dict set item blocked $candidate} else {set item [dict merge $item $candidate]}
        dict set reviewItems $id $item
        $w.tree insert {} end -id $id -values [list "待核对" [get $row refdes] "[get $row _schematic]/[get $row sheet_name] · [get $row hierarchy_path]" [reviewShortText $row]]
        if {[dict size $selectedRow] && [reviewKey $row] eq [reviewKey $selectedRow]} {set selected $id}
    }
    bind $w.tree <<TreeviewSelect>> ::xiaokai::drc::reviewSelect
    bind $w.tree <Double-Button-1> {::xiaokai::drc::reviewDouble %x %y; break}
    if {$selected eq ""} {set selected [lindex [$w.tree children {}] 0]}
    if {$selected ne ""} {$w.tree selection set $selected; $w.tree focus $selected; $w.tree see $selected; reviewSelect}
    if {!$index} {set reviewHint "当前没有可标注的连接核查项。"}
    uiTab review
}
proc ::xiaokai::drc::reviewReset {} {
    variable reviewPreview; variable reviewItems
    set reviewPreview {}; set reviewItems {}
    set ::xiaokai::drc::connectionChecked {}; set ::xiaokai::drc::connectionSnapshot {}; set ::xiaokai::drc::connectionRows {}
    set w .xiaokaiDrc.tabs.review
    if {![winfo exists $w]} {return}
    foreach child [winfo children $w] {destroy $child}
    ttk::label $w.empty -text "检查完成后，在此核对连接依据。"
    pack $w.empty -anchor w
}
proc ::xiaokai::drc::reviewAiAction {} {
    variable aiJob
    if {[dict size $aiJob]} {aiCancel} else {aiStart all}
}
proc ::xiaokai::drc::reviewSelected {} {
    if {![winfo exists .xiaokaiDrc.tabs.review.tree]} {return ""}
    return [lindex [.xiaokaiDrc.tabs.review.tree selection] 0]
}
proc ::xiaokai::drc::reviewSelect {} {
    variable reviewItems; variable reviewNote
    set id [reviewSelected]
    if {$id eq "noEvidence"} {
        set ::xiaokai::drc::connectionRows {}
        set t .xiaokaiDrc.tabs.review.connections.tree; $t delete [$t children {}]
        set ::xiaokai::drc::connectionStatus "展开列表，选择具体项查看实际网络端点。"
        panelText .xiaokaiDrc.tabs.review.evidence "这些候选仅有原生检查与连接事实，未获得可判错的新依据。原生提示继续保留；没有将其判为正确或忽略。"
        return
    }
    if {![dict exists $reviewItems $id]} {return}
    set item [dict get $reviewItems $id]; set row [dict get $item row]; set desc [explain $row]
    connectionRender $row $::xiaokai::drc::reviewPreview
    set reviewNote [reviewShortText $row]
    set verifiedNote [reviewVerifiedNote $row $::xiaokai::drc::reviewPreview]
    if {$verifiedNote ne ""} {set reviewNote $verifiedNote}
    set text "[get $desc summary]\n建议：[get $desc suggestion]\n\n原始依据：\n[get $row message]"
    foreach pin [get $row _targets {}] {
        append text "\n\n器件：[get $pin refdes] · [get $pin part_number {型号未填写}]\n封装：[get $pin footprint {未填写}]\nNC 标记：[get $pin no_connect unknown]"
    }
    if {[dict exists $item ai]} {
        set ai [dict get $item ai]
        set assessment [expr {[get $ai verdict] eq {allowed} ? {手册允许悬空} : ([get $ai verdict] eq {error} ? {手册与原生连接依据一致} : {待核对})}]
        if {[get $ai baseline 0]} {
            append text "\n\nAI：未获得可判错的新依据，保留原生检查提示。\n依据：[get $ai evidence]"
        } else {
            append text "\n\nAI 核对：$assessment\n[get $ai reason]\n下一步：[get $ai next_step]\n依据：[get $ai evidence]\n\n[get $ai sources]"
        }
    }
    if {[dict exists $item blocked]} {append text "\n\n仅列表核对：[dict get $item blocked]"}
    set t .xiaokaiDrc.tabs.review.evidence; $t configure -state normal; $t delete 1.0 end; $t insert end $text; $t configure -state disabled
}
proc ::xiaokai::drc::reviewLocate {} {
    variable reviewPreview; variable reviewItems; variable reviewHint
    set id [reviewSelected]; if {![dict exists $reviewItems $id]} {return}
    reviewJump [dict get $reviewItems $id row] $reviewPreview
}
proc ::xiaokai::drc::reviewDouble {x y} {
    variable reviewItems; variable reviewPreview
    set tree .xiaokaiDrc.tabs.review.tree; set id [$tree identify row $x $y]
    if {$id eq ""} {return}
    $tree selection set $id; $tree focus $id
    if {$id eq "noEvidence"} {$tree item $id -open [expr {![$tree item $id -open]}]; reviewSelect; return}
    if {[dict exists $reviewItems $id]} {
        after idle [list ::xiaokai::drc::reviewJump [dict get $reviewItems $id row] $reviewPreview]
    }
}
proc ::xiaokai::drc::reviewJump {row checked} {
    variable reviewPreview; variable reviewHint
    if {$reviewPreview ne $checked} {set reviewHint "检查批次已变化，请重新选择。"; return}
    if {[catch {locate $row $checked} msg]} {set reviewHint $msg} else {set reviewHint "已定位连接点。"}
}
proc ::xiaokai::drc::reviewReflow {} {
    variable reviewItems
    if {![winfo exists .xiaokaiDrc.tabs.review.tree]} {return}
    set tree .xiaokaiDrc.tabs.review.tree; set baseline {}
    dict for {id item} $reviewItems {
        set verdict [get [get $item ai {}] verdict]
        if {[get [get $item ai {}] baseline 0]} {lappend baseline $id}
        $tree move $id {} end
        $tree set $id state [expr {$verdict eq "allowed" ? "允许悬空" : ($verdict eq "error" ? "手册核实" : ([dict exists $item ai] ? "未证实" : "待核对"))}]
        set row [dict get $item row]
        set note [reviewVerifiedNote $row $::xiaokai::drc::reviewPreview]
        .xiaokaiDrc.tabs.review.tree set $id text [expr {$note eq "" ? [reviewShortText $row] : $note}]
    }
    if {[$tree exists noEvidence]} {$tree delete noEvidence}
    if {[llength $baseline]} {
        $tree insert {} end -id noEvidence -values [list "未新增依据" "[llength $baseline] 项" {未获得可判错的新依据，保留原生检查提示。} {展开查看}] -open 0
        foreach id $baseline {$tree move $id noEvidence end}
        $tree configure -show {tree headings}; $tree column #0 -width 20 -minwidth 20 -stretch 0
        if {[lindex [$tree selection] 0] in $baseline} {$tree selection set noEvidence}
    }
}
proc ::xiaokai::drc::reviewToggle {} {
    variable reviewVisible; variable result; variable busy; variable status; variable powerWhitelist
    variable stale; variable completeStatus; variable reviewWorking
    set desired $reviewVisible
    if {$busy || $reviewWorking} {set reviewVisible [expr {!$desired}]; return}
    set reviewWorking 1
    try {
        if {$desired} {
            aiCancel
            set status "正在检查并放置短标注…"; update idletasks
            if {![dict exists $result rows] || $stale || [resultState $result] ne "current"} {set result [run "" $powerWhitelist]; set stale 0}
            # Withdraw previous tool notes before planning; no user Text is touched.
            set removed [reviewRemove [dict get $result design]]
            if {[dict get $removed removed]} {set result [run "" $powerWhitelist]}
            set plan [reviewPlan $result]; set entries [dict get $plan entries]
            if {[llength $entries]} {
                set applied [reviewApply $entries $result]
                set result [dict get $applied result]; set reviewVisible 1; set stale 0
                set status "已放置 [dict get $applied count] 处短标注，复查一致。再点开关即可关闭。"
            } else {set reviewVisible 0; set status "当前没有可放置的连接提示。"}
            set skipped [dict get $plan skipped]
            if {[llength $skipped]} {
                append status " [llength $skipped] 项仅保留在列表。"
                set explanations {}
                foreach entry $skipped {
                    set row [dict get $entry row]
                    lappend explanations "[get $row refdes] · [get $row sheet_name]：[dict get $entry reason]"
                }
                detailText [join $explanations \n]
            }
        } else {
            set design [activeDesign]
            if {![dict exists $result source] || ![string equal -nocase \
                [file normalize [string map {\\ /} [cstring $design GetName]]] [file normalize [dict get $result source]]]} {
                set reviewVisible 1; error "请切回本次检查的设计后关闭 Text。"
            }
            set removed [reviewRemove $design]
            set reviewVisible 0
            set result [run "" $powerWhitelist]; set stale 0
            set status "已关闭 [dict get $removed removed] 处短标注，并重新检查。"
            if {[dict get $removed preserved]} {append status " 手动修改的备注已保留。"}
        }
        set completeStatus $status; render
        reviewReset
        .xiaokaiDrc.tabs select .xiaokaiDrc.tabs.results
    } on error {msg opts} {
        if {$desired} {set reviewVisible 0}
        set stale 1; set status "Text 操作未完成：$msg"; detailText $status
        puts [dict get $opts -errorinfo]
    } finally {
        set reviewWorking 0
        if {[winfo exists .xiaokaiDrc.bar.text]} {
            .xiaokaiDrc.bar.text configure -text [expr {$reviewVisible ? "关闭 Text" : "一键放置 Text"}]
        }
    }
}
