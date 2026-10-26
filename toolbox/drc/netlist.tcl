# SPDX-License-Identifier: GPL-3.0-only
# Capture's PST writer runs against the current in-process DboSession.
proc ::xiaokai::drc::readNativeText {path} {
    set f [open $path r]
    try {fconfigure $f -encoding [encoding system]; return [read $f]} finally {close $f}
}
proc ::xiaokai::drc::nativeNetlist {design directory} {
    set root [COrPathUtil_sGetCDSRootDir]
    if {![llength [info commands ::orExecutePst]]} {
        load [file join $root tools bin orPstSwp64.dll] Orpstswp
    }
    set source [cstring $design GetName]
    set config [file join $root tools capture allegro.cfg]
    set combine {}; set naming 0; set length 31
    COrSpecificProjectManagerWrapper_initializeSpecificPM $source
    try {
        set custom [COrSpecificProjectManagerWrapper_GetParameterFromProject {Design Resources} {Allegro Setup Configuration File}]
        if {$custom ne ""} {
            set custom [string map {\\ /} $custom]
            if {[file pathtype $custom] ne "absolute"} {set custom [file join [file dirname $source] $custom]}
            set config $custom
        }
        set combine [COrSpecificProjectManagerWrapper_GetParameterFromProject {Design Resources} {Allegro Netlist Combine Property String}]
        set preferredLength [COrSpecificProjectManagerWrapper_GetParameterFromProject {Design Resources} {Allegro Setup Part Type Length}]
        if {[string is integer -strict $preferredLength] && $preferredLength > 0} {set length $preferredLength}
    } finally {COrSpecificProjectManagerWrapper_resetSpecificPM}
    if {![file isfile $config]} {error "网表配置文件不存在：$config"}
    return [orExecutePst $::DboSession_s_pDboSession Capture $source $directory $config 0 $combine $naming R C L J 0 $length]
}
proc ::xiaokai::drc::netlistRows {text} {
    set rows {}
    # PST prefixes actual messages with #1, #2, ... (Batch DRC does not).
    set text [regsub -all -line {^\s*#[0-9]+\s+} $text ""]
    foreach diagnostic [diagnostics $text] {
        set message [dict get $diagnostic message]
        if {![regexp -nocase {^\s*(ERROR|FATAL)\(} $message]} {continue}
        set row [row netlist_error $diagnostic]
        if {[regexp -nocase {\minstance\s+([^\s:]+):\s*(.+?),\s*(.+?)\s+\([-0-9.]+,\s*[-0-9.]+\)} $message -> ref schematic sheet]} {
            dict set row refdes $ref
            dict set row sheet_name $sheet
            dict set diagnostic schematic $schematic
        }
        if {[regexp -nocase {(?:refdes|reference|component|part)\s*[:=]?\s*['"]([A-Za-z][A-Za-z0-9_.-]*)['"]} $message -> ref]} {
            dict set row refdes $ref
        }
        dict set row _diagnostic $diagnostic
        lappend rows $row
    }
    # The native footer merely repeats that the preceding errors prevent output.
    if {[llength $rows] > 1} {
        set detailed {}
        foreach row $rows {if {![regexp {\(ORCAP-36018\)} [dict get $row message]]} {lappend detailed $row}}
        if {[llength $detailed]} {set rows $detailed}
    }
    return $rows
}
proc ::xiaokai::drc::netlistCheck {design workdir} {
    set directory [file join $workdir netlist]
    set rows {}; set code ""; set failure ""; set restoreSuppress 0
    try {
        file mkdir $directory
        if {[llength [info commands GetOptionBool]] && [llength [info commands SetOptionBool]] &&
            ![catch {GetOptionBool SuppressMsgBoxInTcl} oldSuppress]} {
            SetOptionBool SuppressMsgBoxInTcl TRUE
            set restoreSuppress 1
        }
        set code [nativeNetlist $design $directory]
        set log [file join $directory netlist.log]
        if {[file isfile $log]} {set rows [netlistRows [readNativeText $log]]}
        if {$code ne "0" && ![llength $rows]} {error "Capture 网表输出失败，返回码：$code。请查看本次网表日志。"}
        if {![llength $rows]} {
            foreach name {pstchip.dat pstxprt.dat pstxnet.dat} {
                if {![file isfile [file join $directory $name]] || [file size [file join $directory $name]] == 0} {
                    error "Capture 未生成完整网表，缺少 $name。"
                }
            }
        }
    } on error {msg options} {
        set failure $msg
        lappend rows [row netlist_error [dict create message "网表输出未完成：$msg"]]
    } finally {
        if {$restoreSuppress} {SetOptionBool SuppressMsgBoxInTcl [expr {$oldSuppress ? "TRUE" : "FALSE"}]}
    }
    return [dict create rows $rows directory $directory code $code ok [expr {![llength $rows]}] failure $failure]
}
