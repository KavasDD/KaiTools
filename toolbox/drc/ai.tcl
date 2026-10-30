namespace eval ::xiaokai::drc {
    variable aiJob {}
    variable aiQuestion "仅报告有具体连接及手册依据的新发现；无新增判错依据时简短说明。"
    variable aiStatus "填写 AI 接口后，可分析当前项或全部连接候选。"
    variable aiLog ""
}
proc ::xiaokai::drc::aiLogLine {line} {
    variable aiLog
    append aiLog $line \n
    set w .xiaokaiDrc.tabs.review.progressLog
    if {[winfo exists $w]} {panelText $w $aiLog; $w see end}
}
proc ::xiaokai::drc::aiReadProgress {} {
    variable aiJob
    set path [dict get $aiJob cancel].progress
    if {![file exists $path] || [file size $path] > 65536} {return}
    set f [open $path r]; fconfigure $f -encoding utf-8 -translation lf
    try {set lines [split [string trimright [read $f] \n] \n]} finally {close $f}
    set seen [get $aiJob progress_seen 0]
    foreach line [lrange $lines $seen end] {if {$line ne ""} {aiLogLine $line; dict set aiJob stage [string range $line 10 end]}}
    dict set aiJob progress_seen [llength $lines]
}
proc ::xiaokai::drc::aiHelper {} {
    variable aiHelperImage; variable aiHelperName
    if {![info exists aiHelperImage]} {error "AI 辅助程序未打包，请重新生成插件。"}
    set directory [file join $::env(LOCALAPPDATA) XiaokaiToolbox AI bin]
    file mkdir $directory
    set path [file join $directory $aiHelperName]
    if {![file exists $path]} {
        set temp $path.[pid].tmp; set f [open $temp wb]
        try {puts -nonewline $f [binary decode base64 $aiHelperImage]} finally {close $f}
        file rename -force $temp $path
    }
    return $path
}
proc ::xiaokai::drc::aiSettings {} {
    uiTab settings
}
proc ::xiaokai::drc::aiJsonObject {d} {
    set pairs {}; dict for {k v} $d {lappend pairs "[quote $k]:[quote $v]"}
    return \{[join $pairs ,]\}
}
proc ::xiaokai::drc::aiPin {pin} {
    set clean {}
    foreach field {hierarchy_path schematic sheet_name refdes pin_number pin_name pin_type net_name local_net is_power is_primitive part_number manufacturer footprint no_connect} {
        dict set clean $field [get $pin $field]
    }
    return $clean
}
proc ::xiaokai::drc::aiPayload {items checkedResult question requestId} {
    if {![dict size $items] || [dict size $items] > 40} {error "每次分析支持 1～40 项；请先选中具体核查项。"}
    if {[string length $question] > 2000} {error "问题请控制在 2000 字以内。"}
    set model [snapshot [dict get $checkedResult design]]
    set rows {}; set bindings {}; set evidencePreviews {}; set index 0
    dict for {uiId item} $items {
        set id F[incr index]; set row [dict get $item row]
        set evidence [list [aiJsonObject [dict create id $id.DRC type native_drc text [get $row message]]]]
        set targets {}; set nets {}; set parts {}
        foreach pin [get $row _targets {}] {
            lappend targets [aiJsonObject [aiPin $pin]]
            if {[get $pin flat_net] ne ""} {lappend nets [get $pin flat_net]}
            lappend parts [list [get $pin hierarchy_path] [get $pin _part_id]]
        }
        set connected {}; set total 0; set descriptions {}
        foreach pin [dict get $model pins] {
            if {([get $pin flat_net] ne "" && [get $pin flat_net] in $nets) || \
                [list [get $pin hierarchy_path] [get $pin _part_id]] in $parts} {
                incr total
                if {$total <= 400} {
                    lappend connected [aiJsonObject [aiPin $pin]]
                    lappend descriptions "[get $pin hierarchy_path] · [get $pin refdes] [get $pin pin_number]([get $pin pin_name]) → [get $pin net_name {未命名／未解析}]"
                }
            }
        }
        # Evidence references bind to a concrete native observation per item.
        set facts [connectionFacts $row $model]; set networks {}
        foreach network [dict get $facts networks] {
            set endpoints {}; set count 0
            foreach pin [dict get $network endpoints] {
                incr count
                if {$count <= 100} {lappend endpoints [aiJsonObject [aiPin $pin]]}
            }
            lappend networks "\{\"name\":[quote [get $network name]],\"endpoints\":\[[join $endpoints ,]\],\"total\":$count,\"truncated\":[expr {$count > 100 ? "true" : "false"}]\}"
        }
        set context "\{\"id\":[quote $id.PINS],\"type\":\"native_pins\",\"pins\":\[[join $connected ,]\],\"total\":$total,\"truncated\":[expr {$total > 400 ? "true" : "false"}],\"target_networks\":\[[join $networks ,]\],\"unresolved_targets\":[llength [dict get $facts unresolved]],\"coverage\":\"target_networks contains primitive pin endpoints matched by native flat-net identity across the design occurrence snapshot; pins also includes other pins on target components. This is not a wire geometry or expected-connection specification.\"\}"
        lappend evidence $context
        set fields [aiJsonObject [dict create id $id rule [get $row rule_id] path [get $row hierarchy_path] \
            schematic [get $row _schematic] sheet [get $row sheet_name] refdes [get $row refdes]]]
        set fields [string range $fields 0 end-1]
        append fields ",\"targets\":\[[join $targets ,]\],\"evidence\":\[[join $evidence ,]\]\}"
        lappend rows $fields
        dict set bindings $id $uiId
        dict set evidencePreviews $uiId "$id.PINS 原生引脚／相关网络（共 $total 项，最多发送 400 项）：\n[join $descriptions \n]"
    }
    set json "\{\"request_id\":[quote $requestId],\"question\":[quote $question],\"scope\":\"OrCAD native DRC connection candidates\",\"limitations\":\[\"No verified design intent\",\"Datasheets only when an exact reviewed model and document match is supplied\",\"no_connect=unknown means unavailable\",\"Pin types are native enums\",\"Do not assume a floating pin or single-node net is an error\"\],\"findings\":\[[join $rows ,]\]\}"
    if {[string length [encoding convertto utf-8 $json]] > 200000} {error "工程上下文较多，请选中具体项进行 AI 分析。"}
    return [dict create json $json bindings $bindings evidence_previews $evidencePreviews]
}
proc ::xiaokai::drc::aiStart {{scope selected}} {
    variable aiJob; variable aiQuestion; variable aiStatus; variable reviewPreview; variable reviewItems
    if {[dict size $aiJob]} {set aiStatus "AI 请求正在结束，请稍候。"; return}
    set ::xiaokai::drc::aiLog ""
    aiLogLine "[clock format [clock seconds] -format %H:%M:%S]  读取当前工程与连接候选"
    if {[catch {
        if {[resultState $reviewPreview] ne "current"} {error "工程已变化，请重新检查。"}
        if {$scope eq "all"} {set selected $reviewItems} else {
            set id [reviewSelected]
            if {![dict exists $reviewItems $id]} {error "请先选中一项连接候选。"}
            set selected [dict create $id [dict get $reviewItems $id]]
        }
        set requestId "[pid]-[clock milliseconds]-[clock clicks]"
        set payload [aiPayload $selected $reviewPreview $aiQuestion $requestId]
        aiLogLine "发送 [dict size $selected] 项连接候选及相关器件、引脚、网络和证据；本次未上传 DSN 或原理图图片。"
        set helper [aiHelper]
        set directory [file join $::env(LOCALAPPDATA) XiaokaiToolbox AI jobs $requestId]
        file mkdir $directory
        set input [file join $directory request.json]; set output [file join $directory result.tsv]; set cancel [file join $directory cancel]
        set f [open $input w]; fconfigure $f -encoding utf-8 -translation lf
        try {puts -nonewline $f [dict get $payload json]} finally {close $f}
        set aiJob [dict create request_id $requestId directory $directory output $output cancel $cancel \
            checked $reviewPreview bindings [dict get $payload bindings] evidence_previews [dict get $payload evidence_previews] cancelled 0 started [clock milliseconds]]
        exec $helper --analyze $input $output $cancel >NUL 2>NUL &
    } msg]} {set aiJob {}; set aiStatus $msg; aiLogLine "启动失败：$msg"; return}
    set aiStatus "正在分析 [dict size $selected] 项；可以继续定位核对，或取消请求。"
    if {[winfo exists .xiaokaiDrc.tabs.review.ai.analyze]} {.xiaokaiDrc.tabs.review.ai.analyze configure -text "取消分析"}
    if {[winfo exists .xiaokaiDrc.tabs.review.progress]} {.xiaokaiDrc.tabs.review.progress start 15}
    after 250 ::xiaokai::drc::aiPoll
}
proc ::xiaokai::drc::aiCancel {} {
    variable aiJob; variable aiStatus
    if {![dict size $aiJob]} {return}
    dict set aiJob cancelled 1
    catch {set f [open [dict get $aiJob cancel] w]; close $f}
    set aiStatus "已取消；本次结果不会应用。"
    aiLogLine "已请求取消；等待后台结束，本次结果不会应用。"
    if {[winfo exists .xiaokaiDrc.tabs.review.ai.analyze]} {.xiaokaiDrc.tabs.review.ai.analyze configure -text "取消中…" -state disabled}
}
proc ::xiaokai::drc::aiReviewClosed {widget} {if {$widget eq ".xiaokaiDrc.tabs.review"} {aiCancel}}
proc ::xiaokai::drc::aiDecode {s} {return [encoding convertfrom utf-8 [binary decode base64 $s]]}
proc ::xiaokai::drc::aiReadResult {body job} {
    set lines [split [string trimright $body \n] \n]
    set header [split [lindex $lines 0] \t]
    if {[lindex $header 0] eq "ERROR" && [llength $header] == 2} {error [aiDecode [lindex $header 1]]}
    if {$header ne [list OK [dict get $job request_id]]} {error "AI 批次不匹配，结果未应用。"}
    set output {}; set bindings [dict get $job bindings]
    foreach line [lrange $lines 1 end] {
        set fields [split $line \t]; lassign $fields id verdict evidence reason next note sources
        if {[llength $fields] ni {6 7} || ![dict exists $bindings $id] || [dict exists $output [dict get $bindings $id]] || $verdict ni {uncertain error allowed}} {
            error "AI 结果对象或格式无效，结果未应用。"
        }
        if {$verdict in {error allowed} && (![regexp {\.DS1(?:,|$)} [aiDecode $evidence]] || $sources eq "")} {error "AI 判断缺少已核实手册依据。"}
        set baseline [expr {$verdict eq "uncertain"}]
        foreach citation [split [aiDecode $evidence] ,] {
            if {[string trim $citation] ni [list $id.DRC $id.PINS]} {set baseline 0}
        }
        dict set output [dict get $bindings $id] [dict create verdict $verdict baseline $baseline evidence [aiDecode $evidence] \
            reason [aiDecode $reason] next_step [aiDecode $next] suggested_text [aiDecode $note] sources [aiDecode $sources]]
    }
    if {[dict size $output] != [dict size $bindings]} {error "AI 结果不完整，结果未应用。"}
    return $output
}
proc ::xiaokai::drc::aiPoll {} {
    variable aiJob; variable aiStatus; variable reviewPreview; variable reviewItems
    if {![dict size $aiJob]} {return}
    catch {aiReadProgress}
    set job $aiJob; set path [dict get $job output]
    if {![file exists $path] && [clock milliseconds]-[dict get $job started] < 240000} {
        if {![get $job cancelled 0]} {
            set seconds [expr {([clock milliseconds]-[dict get $job started])/1000}]
            set aiStatus "[get $job stage {后台准备分析}] · 已用 $seconds 秒；可继续定位或取消。"
        }
        after 250 ::xiaokai::drc::aiPoll; return
    }
    set aiJob {}
    try {
        if {[dict get $job cancelled]} {return}
        if {![file exists $path]} {error "AI 请求超时，请检查接口配置。"}
        if {![winfo exists .xiaokaiDrc.tabs.review] || $reviewPreview ne [dict get $job checked] || \
            [resultState [dict get $job checked]] ne "current"} {error "工程或检查批次已变化，AI 结果已丢弃，请重新检查。"}
        if {[file size $path] > 1048576} {error "AI 返回结果过大。"}
        set f [open $path r]; fconfigure $f -encoding utf-8 -translation lf
        try {set body [read $f]} finally {close $f}
        set results [aiReadResult $body $job]
        dict for {id item} $results {if {![dict exists $reviewItems $id]} {error "AI 对应核查项已变化。"}}
        dict for {id item} $results {
            dict set item context "[get $item sources]\n[dict get $job evidence_previews $id]"
            dict set reviewItems $id ai $item
        }
        reviewReflow; reviewSelect
        aiLogLine "完成：已校验 [dict size $results] 项对象与证据，双击列表查看结论。"
        set noEvidence 0; set verified 0
        dict for {id item} $results {
            if {[get $item baseline 0]} {incr noEvidence}
            if {[get $item verdict] in {error allowed}} {incr verified}
        }
        set aiStatus "已核对 [dict size $results] 项：$verified 项手册核实，$noEvidence 项未新增判错依据。双击连接引脚定位。"
    } on error {msg opts} {
        set aiStatus [lindex [split $msg \n] 0]
        aiLogLine "失败：$msg"
        panelText .xiaokaiDrc.tabs.review.evidence "本次 AI 分析失败，结果未应用：\n\n$msg"
    } finally {
        if {[winfo exists .xiaokaiDrc.tabs.review.progress]} {.xiaokaiDrc.tabs.review.progress stop}
        if {[winfo exists .xiaokaiDrc.tabs.review.ai.analyze]} {.xiaokaiDrc.tabs.review.ai.analyze configure -text "分析全部" -state normal}
        # This is our unique job directory, never a user project directory.
        catch {file delete -force [dict get $job cancel]}
        catch {file delete -force [dict get $job cancel].progress}
        foreach name {request.json result.tsv} {catch {file delete -force [file join [dict get $job directory] $name]}}
        catch {file delete [dict get $job directory]}
    }
}
