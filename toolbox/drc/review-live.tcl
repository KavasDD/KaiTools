# Development only: the launcher provides a separate copy of FullAdder.
proc xkReviewLive {} {
    set directory $::env(XIAOKAI_REVIEW_TEST_DIR)
    set f [open [file join $directory review-live.log] w]
    fconfigure $f -encoding utf-8 -buffering line
    set ns ::xiaokai::drc
    try {
        source [file join $::env(XIAOKAI_REVIEW_TEST_REPO) autoload drctoolMenu.tcl]
        Open [file join $directory review.opj]
        set checked [${ns}::run [file join $directory reports]]
        if {[dict get $checked violations] != 0} {error "Sample not clean"}
        set design [dict get $checked design]
        set page [${ns}::reviewPage $design FULLADD FULLADD]
        set s [DboState]; set it [$page NewPartInstsIter $s]
        set part [$it NextPartInst $s]
        while {$part ne "NULL" && ![$part IsPrimitive $s]} {set part [$it NextPartInst $s]}
        delete_DboPagePartInstsIter $it
        if {$part eq "NULL"} {error "No primitive part"}
        set point [DboTclHelper_sMakeCPoint 700 450]
        ${ns}::reviewCheckStatus [$part SetLocation $point]
        DboTclHelper_sDeleteCPoint $point
        ${ns}::reviewCheckStatus [$page MarkModified]
        # A normal user Text with the same wording has no ownership attribute
        # and must remain untouched by both the switch and a subsequent check.
        set point [DboTclHelper_sMakeCPoint 200 200]
        set rect [DboTclHelper_sMakeCRect 200 200 400 220]
        set font [DboTclHelper_sMakeLOGFONT {Microsoft YaHei} -12 0 0 0 400 0 0 0 134 0 0 0 0]
        set text [DboTclHelper_sMakeCString "已确认：普通用户备注"]
        set userText [$page NewGraphicCommentTextInst $s $rect $point $text $font 0]
        if {$userText eq "NULL" || ![$s OK]} {error "Could not create user Text fixture"}
        set userTextId [$userText GetId $s]
        DboTclHelper_sDeleteCPoint $point; DboTclHelper_sDeleteCRect $rect
        DboTclHelper_sDeleteLOGFONT $font; DboTclHelper_sDeleteCString $text
        $s -delete
        set checked [${ns}::run [file join $directory reports]]
        set entry {}
        foreach row [dict get $checked rows] {
            if {[dict get $row rule_id] ne "unconnected_pin" || [dict get $row hierarchy_path] ne "/"} {continue}
            set candidate [${ns}::reviewCandidate $row $checked]
            dict set candidate text "已确认：示例器件引脚漏接"
            set entry [${ns}::reviewPlacement $candidate $checked]
            break
        }
        if {$entry eq ""} {error "Missing root defect"}
        lassign [dict get [dict get $entry row] _focus_point] pinX pinY
        lassign [dict get $entry text_rect] l t r b
        if {$l != $pinX || $t != $pinY} {error "Text is not anchored at the exact fault"}
        puts $f [list EXACT_FAULT [dict get $entry fault_point] [dict get $entry text_rect]]
        dict set entry text "已确认：示例器件引脚漏接"; dict set entry confirmed 1
        puts $f [list PREVIEW $entry]
        set applied [${ns}::reviewApply [list $entry] $checked]
        set checked [dict get $applied result]
        puts $f [list APPLIED [dict get $applied count] BACKUP [dict get $applied backup]]
        set owned [${ns}::reviewOwned [dict get $checked design]]
        if {[llength $owned] != 1 || ![dict get [lindex $owned 0] unchanged]} {error "Owned Text readback failed"}
        puts $f [list NATIVE_TEXT [${ns}::reviewText [dict get [lindex $owned 0] inst]]]
        # Compact evidence window on the real objects. Placement uses the switch.
        set ::xiaokai::drc::result $checked
        ${ns}::show; ${ns}::reviewShow
        set id [lindex [.xiaokaiDrc.tabs.review.tree children {}] 0]
        .xiaokaiDrc.tabs.review.tree selection set $id; ${ns}::reviewSelect
        if {[winfo exists .xiaokaiDrc.tabs.review.buttons]} {error "Legacy multi-step buttons retained"}
        if {[string length $::xiaokai::drc::reviewNote] > 5} {error "Default note is not concise"}
        ${ns}::reviewReset
        destroy .xiaokaiDrc
        # Save, close and reopen: ownership must survive independently of RAM.
        ${ns}::focusDesign [dict get $checked design] review.dsn [file join $directory review.opj]
        Menu "File::Close"
        Open [file join $directory review.opj]
        set design [${ns}::activeDesign]
        set owned [${ns}::reviewOwned $design]
        if {[llength $owned] != 1} {error "Ownership not persisted"}
        puts $f REOPENED
        set record [lindex $owned 0]; set inst [dict get $record inst]
        set text [DboTclHelper_sMakeCString "用户手动修改后保留的备注"]
        set comment [DboGraphicInstanceToDboGraphicCommentTextInst $inst]
        ${ns}::reviewCheckStatus [$comment SetText $text]
        DboTclHelper_sDeleteCString $text
        ${ns}::reviewCheckStatus [[dict get $record page] MarkModified]
        set removed [${ns}::reviewRemove $design]
        if {[dict get $removed removed] != 0 || [dict get $removed preserved] != 1} {error "Edited Text was not preserved"}
        puts $f [list EDIT_PRESERVED $removed]
        # A second annotation is removed, while the edited note is retained.
        set checked [${ns}::run [file join $directory reports]]
        foreach row [dict get $checked rows] {
            if {[dict get $row rule_id] eq "unconnected_pin" && [dict get $row hierarchy_path] eq "/"} {
                set candidate [${ns}::reviewCandidate $row $checked]
                dict set candidate text "已确认：用于开关测试"
                set entry [${ns}::reviewPlacement $candidate $checked]; break
            }
        }
        dict set entry text "已确认：用于开关测试"; dict set entry confirmed 1
        set applied [${ns}::reviewApply [list $entry] $checked]
        set removed [${ns}::reviewRemove [dict get [dict get $applied result] design]]
        if {[dict get $removed removed] != 1 || [dict get $removed preserved] != 1} {error "Text removal isolation failed"}
        puts $f [list REMOVED $removed]
        set final [${ns}::run [file join $directory reports]]
        if {[${ns}::reviewKeys [dict get $final rows]] ne [${ns}::reviewKeys [dict get $checked rows]]} {error "Connectivity changed"}
        set page [${ns}::reviewPage [dict get $final design] FULLADD FULLADD]
        set s [DboState]; set it [$page NewCommentGraphicsIter $s]; set userFound 0
        try {
            for {set inst [$it NextCommentGraphic $s]} {$inst ne "NULL"} {set inst [$it NextCommentGraphic $s]} {
                if {[$inst GetId $s] == $userTextId && [${ns}::reviewText $inst] eq "已确认：普通用户备注"} {set userFound 1}
            }
        } finally {delete_DboPageCommentGraphicsIter $it; $s -delete}
        if {!$userFound} {error "Normal user Text not preserved"}
        puts $f USER_TEXT_PRESERVED
        puts $f PASS
    } on error {msg opts} {puts $f [dict get $opts -errorinfo]; puts $f FAIL} finally {
        close $f
        # Save only the disposable fixture, then exit normally to avoid Capture
        # recovery settings affecting the user's next session.
        catch {${ns}::saveCurrentDesign [${ns}::activeDesign]}
        after 500 {Menu "File::Exit"}
    }
}
after 1500 xkReviewLive
