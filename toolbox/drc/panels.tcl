namespace eval ::xiaokai::drc {
    variable panelJobs {}
    variable settingsLoaded 0
    variable settingsEndpoint ""
    variable settingsModel ""
    variable settingsSecret ""
    variable settingsSavedKey 0
    variable settingsKeyHint "Key 尚未保存"
    variable settingsKeyMarker "********"
    variable settingsModels {}
    variable settingsModelRequest {}
    variable settingsJson 0
    variable settingsClear 0
    variable settingsStatus "正在读取设置…"
    variable datasheetComponent {}
    variable datasheetHeading "选择一个问题或原理图器件后，点击“读取所选器件”。"
    variable datasheetStatus ""
    variable datasheetPath ""
}
proc ::xiaokai::drc::uiTab {name} {
    show
    if {[.xiaokaiDrc.tabs select] ne ".xiaokaiDrc.tabs.$name"} {.xiaokaiDrc.tabs select .xiaokaiDrc.tabs.$name}
}
proc ::xiaokai::drc::panelStart {kind request} {
    variable panelJobs
    if {[dict exists $panelJobs $kind]} {return 0}
    set root [file join $::env(LOCALAPPDATA) XiaokaiToolbox AI jobs]
    file mkdir $root
    set output [file join $root panel-[pid]-[clock clicks].tsv]
    set cancel $output.cancel
    set channel [open |[list [aiHelper] --panel-job $output $cancel] r+]
    fconfigure $channel -encoding utf-8 -translation lf -blocking 0
    # Keys never go into command arguments or request files.
    puts $channel [aiJsonObject $request]; flush $channel
    dict set panelJobs $kind [dict create output $output cancel $cancel channel $channel started [clock milliseconds] action [get $request action]]
    after 150 [list ::xiaokai::drc::panelPoll $kind]
    return 1
}
proc ::xiaokai::drc::panelPoll {kind} {
    variable panelJobs
    if {![dict exists $panelJobs $kind]} {return}
    set job [dict get $panelJobs $kind]; set path [dict get $job output]
    if {![file exists $path] && [clock milliseconds]-[dict get $job started] < 110000} {
        after 150 [list ::xiaokai::drc::panelPoll $kind]; return
    }
    dict unset panelJobs $kind
    try {
        if {![file exists $path]} {error "操作超时，请重试。"}
        if {[file size $path] > 16777216} {error "资料过大，无法显示。"}
        set f [open $path r]; fconfigure $f -encoding utf-8 -translation lf
        try {set body [read $f]} finally {close $f}
        set lines [split [string trimright $body \n] \n]
        if {[lindex $lines 0] ne "OK"} {error [aiDecode [lindex [split [lindex $lines 0] \t] 1]]}
        set data {}; foreach line [lrange $lines 1 end] {
            lassign [split $line \t] key value; dict set data $key [aiDecode $value]
        }
        if {$kind eq "settings"} {
            set action [dict get $job action]
            if {$action eq "settings-read"} {
                set ::xiaokai::drc::settingsEndpoint [get $data endpoint]
                set ::xiaokai::drc::settingsModel [get $data model]
                set ::xiaokai::drc::settingsJson [get $data json_mode 0]
            }
            set ::xiaokai::drc::settingsSavedKey [get $data saved_key 0]
            if {$action eq "settings-read" || $action eq "settings-save"} {
                set ::xiaokai::drc::settingsSecret [expr {$::xiaokai::drc::settingsSavedKey ? $::xiaokai::drc::settingsKeyMarker : ""}]
                set ::xiaokai::drc::settingsKeyHint [expr {$::xiaokai::drc::settingsSavedKey ? "Key 已加密保存；星号代表已保存，填写新 Key 可替换。" : "当前未保存 Key；免 Key 代理可留空。"}]
                set ::xiaokai::drc::settingsClear 0
            }
            if {[dict exists $data models]} {
                set ::xiaokai::drc::settingsModels [split [get $data models] \n]
                if {[winfo exists .xiaokaiDrc.tabs.settings.model]} {.xiaokaiDrc.tabs.settings.model configure -values $::xiaokai::drc::settingsModels}
            }
            set ::xiaokai::drc::settingsStatus [get $data message "设置已读取；Key 留空保留已保存的密钥。"]
            if {[get $data warning] ne ""} {append ::xiaokai::drc::settingsStatus " [get $data warning]"}
            if {$action eq "settings-read" && [get $data endpoint] ne ""} {after 350 ::xiaokai::drc::settingsAutoModels}
        } else {
            set ::xiaokai::drc::datasheetStatus [get $data message]
            if {[dict exists $data text]} {panelText .xiaokaiDrc.tabs.datasheet.text [get $data text]}
        }
    } on error {msg opts} {
        set ::xiaokai::drc::${kind}Status $msg
        if {$kind eq "settings" && [dict get $job action] eq "settings-read"} {set ::xiaokai::drc::settingsLoaded 0}
    } finally {
        catch {close [dict get $job channel]}
        catch {file delete -force $path [dict get $job cancel]}
        panelControls $kind normal
    }
}
proc ::xiaokai::drc::panelControls {kind state} {
    set w .xiaokaiDrc.tabs.$kind
    if {$kind eq "settings"} {set widgets {endpoint model secret json clear actions.save actions.test actions.models}} else {set widgets {tools.read tools.open tools.chip tools.lcsc import.path import.go}}
    foreach child $widgets {if {[winfo exists $w.$child]} {$w.$child configure -state $state}}
}
proc ::xiaokai::drc::panelText {widget value} {
    if {![winfo exists $widget]} {return}
    $widget configure -state normal; $widget delete 1.0 end; $widget insert end $value; $widget configure -state disabled
}
proc ::xiaokai::drc::settingsBuild {} {
    set w .xiaokaiDrc.tabs.settings
    ttk::label $w.shared -text "AI 地址、Key 和模型统一在小开工具箱左下角「API KEY」中填写。OrCAD 与 Allegro 共用，保存后下次请求生效。" -wraplength 570
    grid $w.shared -row 0 -column 0 -sticky nw -padx 14 -pady 16
}
proc ::xiaokai::drc::settingsAction {action} {
    variable settingsStatus; variable settingsSecret
    settingsKeyEdited
    if {$::xiaokai::drc::settingsSavedKey && $settingsSecret eq $::xiaokai::drc::settingsKeyMarker} {set secret ""} else {set secret $settingsSecret}
    set request [dict create action settings-$action endpoint $::xiaokai::drc::settingsEndpoint model $::xiaokai::drc::settingsModel \
        secret $secret json_mode $::xiaokai::drc::settingsJson clear_key $::xiaokai::drc::settingsClear]
    if {[catch {set started [panelStart settings $request]} msg]} {set settingsStatus "无法读取或保存设置：$msg"; return}
    if {$started} {
        if {$action eq "models"} {set ::xiaokai::drc::settingsModelRequest [list $::xiaokai::drc::settingsEndpoint $settingsSecret $::xiaokai::drc::settingsClear]}
        set settingsStatus [expr {$action eq "models" ? "正在获取服务商模型列表…" : ($action eq "test" ? "正在调用所选模型测试连接…" : "正在处理…")}]
        panelControls settings disabled
    }
}
proc ::xiaokai::drc::settingsKeyEdited {} {
    variable settingsKeyHint; variable settingsSecret
    if {$::xiaokai::drc::settingsSavedKey && ($settingsSecret eq $::xiaokai::drc::settingsKeyMarker || $settingsSecret eq "")} {
        set settingsKeyHint "Key 已加密保存；填写新 Key 可替换，留空保留已保存的 Key。"
    } elseif {$settingsSecret ne ""} {
        set settingsKeyHint "新 Key 尚未保存；获取模型和测试连接将使用此 Key。"
    } else {set settingsKeyHint "当前未填写 Key；免 Key 代理可留空。"}
}
proc ::xiaokai::drc::settingsAutoModels {} {
    if {![winfo exists .xiaokaiDrc.tabs.settings] || [.xiaokaiDrc.tabs select] ne ".xiaokaiDrc.tabs.settings" || [dict exists $::xiaokai::drc::panelJobs settings]} {return}
    if {[string trim $::xiaokai::drc::settingsEndpoint] eq ""} {return}
    set signature [list $::xiaokai::drc::settingsEndpoint $::xiaokai::drc::settingsSecret $::xiaokai::drc::settingsClear]
    if {$signature ne $::xiaokai::drc::settingsModelRequest} {settingsAction models}
}
proc ::xiaokai::drc::datasheetBuild {} {
    set w .xiaokaiDrc.tabs.datasheet
    ttk::label $w.heading -textvariable ::xiaokai::drc::datasheetHeading -wraplength 600
    ttk::frame $w.tools
    foreach {name label action} {read 读取所选器件 read open 打开PDF open chip 半导小芯 chip lcsc 立创商城 lcsc} {
        ttk::button $w.tools.$name -text $label -command [list ::xiaokai::drc::datasheetAction $action]
        pack $w.tools.$name -side left -padx {0 8}
    }
    ttk::frame $w.import
    ttk::entry $w.import.path -textvariable ::xiaokai::drc::datasheetPath
    ttk::button $w.import.go -text "导入 PDF 路径" -command {::xiaokai::drc::datasheetAction import}
    pack $w.import.go -side right -padx {8 0}; pack $w.import.path -fill x -expand 1
    text $w.text -wrap word -font TkDefaultFont -state disabled -height 8
    ttk::scrollbar $w.scroll -command [list $w.text yview]; $w.text configure -yscrollcommand [list $w.scroll set]
    ttk::label $w.status -textvariable ::xiaokai::drc::datasheetStatus -wraplength 600
    pack $w.heading $w.tools $w.import -fill x -pady {0 10}
    pack $w.status -side bottom -fill x -pady 8
    pack $w.scroll -side right -fill y; pack $w.text -fill both -expand 1
}
proc ::xiaokai::drc::datasheetAction {action} {
    variable datasheetComponent; variable datasheetStatus; variable datasheetHeading; variable panelJobs
    if {[dict exists $panelJobs datasheet]} {return}
    if {[catch {
        if {$action eq "read" || ![dict size $datasheetComponent]} {
            set info [datasheetInfo]
            if {[get $info part_number] eq ""} {error "器件未填写型号，无法匹配手册。"}
            set datasheetComponent {}
            foreach field {part_number manufacturer footprint refdes datasheet_url lcsc} {dict set datasheetComponent $field [get $info $field]}
            set datasheetHeading "[get $info refdes] · [get $info part_number]    封装：[get $info footprint {未填写}]"
            panelText .xiaokaiDrc.tabs.datasheet.text ""
        }
        set path [string trim [string trim $::xiaokai::drc::datasheetPath] {"}]
        set request [dict merge $datasheetComponent [dict create action datasheet-$action path $path]]
        if {$action eq "import" && [get $request path] eq ""} {error "请在本页填写下载好的 PDF 完整路径。"}
        if {[panelStart datasheet $request]} {set datasheetStatus "正在读取／提取手册…"; panelControls datasheet disabled}
    } msg]} {set datasheetStatus $msg}
}
proc ::xiaokai::drc::uiHide {} {
    set ::xiaokai::drc::settingsSecret [expr {$::xiaokai::drc::settingsSavedKey ? $::xiaokai::drc::settingsKeyMarker : ""}]
    set ::xiaokai::drc::settingsModelRequest {}
    aiCancel
    wm withdraw .xiaokaiDrc
}
proc ::xiaokai::drc::uiTabChanged {} {
    if {![winfo exists .xiaokaiDrc.tabs]} {return}
    switch [.xiaokaiDrc.tabs select] {
        .xiaokaiDrc.tabs.review {
            if {[winfo exists .xiaokaiDrc.tabs.review.tree] && $::xiaokai::drc::reviewPreview eq $::xiaokai::drc::result} {
                reviewShow
            } else {reviewSelectedShow}
        }
        .xiaokaiDrc.tabs.settings {
            # Settings are owned by the launcher, never read secrets into Tk.
        }
    }
}
