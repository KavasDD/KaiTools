# SPDX-License-Identifier: GPL-3.0-only
# Capture 17.4 adapter. The occurrence walk follows Cadence's installed example:
# tools/capture/tclscripts/capCustomSamples/capGenerateBOM.tcl.
# All database operations below are READ ONLY.
namespace eval ::bomtool {
    variable scriptPath [file normalize [info script]]
    variable uiEncoding utf-8
}
proc ::bomtool::captureProp {design occ inst name} {
    set pn [DboTclHelper_sMakeCString $name]
    set pv [DboTclHelper_sMakeCString]
    try {
        foreach obj [list $occ $inst] {
            if {$obj eq "NULL"} { continue }
            if {![$obj IsVariantPropMapEmpty] && [$obj GetVariantProp $pn $pv]} {
                return [DboTclHelper_sGetConstCharPtr $pv]
            }
        }
        set status [$occ GetEffectivePropStringValue $pn $pv]
        try {
            if {[$status OK]} { return [DboTclHelper_sGetConstCharPtr $pv] }
            return ""
        } finally { $status -delete }
    } finally {
        DboTclHelper_sDeleteCString $pn
        DboTclHelper_sDeleteCString $pv
    }
}
proc ::bomtool::captureWalk {design parent rowsName} {
    upvar 1 $rowsName rows
    set status [DboState]; set iter NULL
    try {
        set iter [$parent NewChildrenIter $status $::IterDefs_INSTS]
        if {$iter eq "NULL" || ![$status OK]} { error "Capture: cannot enumerate occurrences." }
        set child [$iter NextOccurrence $status]
        while {$child ne "NULL"} {
            set occ [DboOccurrenceToDboInstOccurrence $child]
            if {[$occ IsPrimitive $status]} {
                set refCString [DboTclHelper_sMakeCString]
                try {
                    set rs [$occ GetReference $refCString]
                    try {
                        if {![$rs OK]} { error "Capture: cannot read occurrence reference." }
                        set ref [clean [DboTclHelper_sGetConstCharPtr $refCString]]
                    } finally { $rs -delete }
                } finally { DboTclHelper_sDeleteCString $refCString }
                if {$ref eq "" || [string first ? $ref] >= 0} { error "Capture: unannotated part '$ref'; annotate before BOM export." }
                set inst [$occ GetPartInst $status]
                set row [dict create ref $ref refs [list [string toupper $ref]] row [expr {[llength $rows]+2}] file capture]
                set notStuffed [DboTclHelper_sGetConstCharPtr [$design GetCISNotStuffedString]]
                foreach {key prop} {value Value footprint {PCB Footprint} description Dsecription option Option empty EMPTY material MATERIAL dnp DNP voltage Voltage tolerance Tolerance part_number {Part Number}} {
                    set value [captureProp $design $occ $inst $prop]
                    dict set row $key $value
                    if {$notStuffed ne "" && $value eq $notStuffed} {
                        dict set row variant_nc 1
                        dict lappend row variant_nc_sources [list $prop $value]
                    }
                }
                if {[get $row description] eq ""} { dict set row description [captureProp $design $occ $inst Description] }
                if {[get $row variant_nc] eq "1"} {
                    dict set row original_dnp [get $row dnp]
                    dict set row dnp YES
                }
                lappend rows $row
            } else {
                captureWalk $design $occ rows
            }
            set child [$iter NextOccurrence $status]
        }
        # NULL is the documented end-of-iteration sentinel. Capture returns
        # IDS_DBOSTATE_AT_END here, so !OK is normal, not a traversal failure.
        # See capinfomodel/dboimnew.html, "Iterators". Tcl exceptions still
        # propagate through finally and cancel export; do not catch them here.
    } finally {
        if {$iter ne "NULL"} { delete_DboOccurrenceChildrenIter $iter }
        $status -delete
    }
}
proc ::bomtool::captureRows {} {
    if {![info exists ::DboSession_s_pDboSession]} { error "Run Export Active Design inside OrCAD Capture CIS 17.4." }
    set session $::DboSession_s_pDboSession
    DboSession -this $session
    set design [$session GetActiveDesign]
    if {$design eq "NULL"} { error "Open a design in Capture first." }
    set status [DboState]
    try {
        set root [$design GetRootOccurrence $status]
        if {$root eq "NULL" || ![$status OK]} { error "Capture: root occurrence is unavailable." }
        set rows {}; captureWalk $design $root rows
    } finally { $status -delete }
    if {![llength $rows]} { error "The active design has no primitive parts." }
    return [collapseCaptureSections $rows]
}
proc ::bomtool::collapseCaptureSections {rows} {
    # Keep original section rows for the workbook and diagnose all differences.
    set physical {}; set result {}
    foreach row $rows {
        dict lappend physical [string toupper [get $row ref]] $row
    }
    dict for {ref sections} $physical {
        set merged [lindex $sections 0]; set differences {}; set conflicts {}
        foreach {key label} {value Value footprint {PCB Footprint} description Dsecription option Option empty EMPTY material MATERIAL dnp DNP voltage Voltage tolerance Tolerance part_number {Part Number}} {
            set values {}; set evidence {}; set first ""
            foreach section $sections {
                set value [clean [get $section $key]]
                lappend evidence "原始BOM第[get $section row]行=\"$value\""
                if {$value ne ""} {
                    if {$first eq ""} { set first [get $section $key] }
                    lappend values [string toupper $value]
                }
            }
            if {[clean [get $merged $key]] eq ""} { dict set merged $key $first }
            set rawValues {}; foreach section $sections { lappend rawValues [get $section $key] }
            if {[llength [lsort -unique $rawValues]] > 1} {
                lappend differences "$label：[join $evidence "；"]"
            }
            if {$key in {value footprint option voltage tolerance part_number} && [llength [lsort -unique $values]] > 1} {
                lappend conflicts $label
            }
        }
        set states {}; set stateEvidence {}; set ncSources {}
        foreach section $sections {
            set evidence [ncEvidence $section]
            set nc [expr {[llength $evidence] > 0}]; lappend states $nc
            set label "焊接"; if {$nc} { set label "不焊接（[join $evidence "；"]）" }
            lappend stateEvidence "原始BOM第[get $section row]行=$label"
            set ncSources [concat $ncSources [get $section variant_nc_sources]]
        }
        if {[llength [lsort -unique $states]] > 1} {
            lappend conflicts "焊接状态"
            lappend differences "焊接状态：[join $stateEvidence "；"]"
        }
        if {[llength $ncSources]} { dict set merged variant_nc_sources [lsort -unique $ncSources]; dict set merged variant_nc 1 }
        dict set merged capture_sections $sections
        dict set merged capture_differences [join $differences "\n"]
        dict set merged capture_conflict [join $conflicts "、"]
        lappend result $merged
    }
    return $result
}
proc ::bomtool::exportCapture {outdir {rows ""} {overrides {}}} {
    if {$rows eq ""} { set rows [captureRows] }
    return [preprocess [applyCategoryOverrides $rows $overrides] $outdir]
}
proc ::bomtool::moduleA {input outdir {encoding utf-8}} { return [preprocess [readBom $input $encoding] $outdir] }
proc ::bomtool::outputDirectory {parent label} {
    set base [file join $parent ${label}_[clock format [clock seconds] -format %Y%m%d_%H%M%S]]
    set path $base; set i 1
    while {[file exists $path]} { set path ${base}_$i; incr i }
    file mkdir $path
    return $path
}
proc ::bomtool::chooseBom {title} {
    return [tk_getOpenFile -title $title -filetypes {{{BOM text} {.csv .txt .tsv}} {{All files} *}}]
}
proc ::bomtool::finishCategoryDialog {result} {
    variable categoryDialogResult
    set categoryDialogResult $result
}
proc ::bomtool::requestCategoryOverrides {candidates} {
    variable categoryDialogResult
    if {![llength $candidates]} { return {} }
    set w .bomcategorydialog
    if {[winfo exists $w]} { destroy $w }
    toplevel $w
    set result __cancel__
    try {
        wm title $w "确认批量位号分类"
        wm transient $w .
        wm protocol $w WM_DELETE_WINDOW [list ::bomtool::finishCategoryDialog __cancel__]
        label $w.note -text "发现以下连续位号组（每组至少8个）。请选择分类；选择“其他”将保留默认分类。" \
            -anchor w -justify left -wraplength 620
        pack $w.note -padx 14 -pady 10 -fill x
        frame $w.rows
        pack $w.rows -padx 14 -fill both -expand 1
        set choices {cap res ind diode mos ic conn batt xtal other}
        set labels {}
        set labelToCategory {}
        foreach category $choices {
            set label [cn $category]
            lappend labels $label
            dict set labelToCategory $label $category
        }
        set i 0
        foreach candidate $candidates {
            lassign $candidate prefix refs
            set line $w.rows.row$i
            frame $line
            label $line.family -text "$prefix（[llength $refs] 个）" -width 20 -anchor w
            label $line.refs -text [join $refs ", "] -width 52 -anchor w
            ttk::combobox $line.category -state readonly -values $labels -width 14 \
                -textvariable ::bomtool::categoryChoice($prefix)
            set ::bomtool::categoryChoice($prefix) [cn other]
            grid $line.family -row 0 -column 0 -sticky w -padx 4
            grid $line.refs -row 0 -column 1 -sticky w -padx 4
            grid $line.category -row 0 -column 2 -sticky e -padx 4
            pack $line -fill x -pady 3
            incr i
        }
        frame $w.buttons
        button $w.buttons.ok -text "继续整理" -width 12 -command [list ::bomtool::finishCategoryDialog accept]
        button $w.buttons.cancel -text "取消" -width 12 -command [list ::bomtool::finishCategoryDialog __cancel__]
        pack $w.buttons.cancel $w.buttons.ok -side right -padx 6 -pady 10
        pack $w.buttons -fill x -padx 14
        set categoryDialogResult ""
        grab set $w
        tkwait variable ::bomtool::categoryDialogResult
        set result $categoryDialogResult
        if {$result eq "accept"} {
            set overrides {}
            foreach candidate $candidates {
                lassign $candidate prefix refs
                set selected $::bomtool::categoryChoice($prefix)
                if {![dict exists $labelToCategory $selected]} { error "Unknown category selection: $selected" }
                set category [dict get $labelToCategory $selected]
                foreach ref $refs { dict set overrides $ref $category }
            }
            set result $overrides
        }
    } finally {
        foreach candidate $candidates { unset -nocomplain ::bomtool::categoryChoice([lindex $candidate 0]) }
        if {[winfo exists $w]} {
            if {[grab current $w] eq $w} { grab release $w }
            destroy $w
        }
    }
    return $result
}
proc ::bomtool::runUI {action} {
    variable uiEncoding
    if {[catch {
        switch -- $action {
            A {
                set input [chooseBom "选择已有原生BOM（可选导入）"]
                if {$input eq ""} { return }
                set parent [tk_chooseDirectory -title "选择结果保存目录"]
                if {$parent eq ""} { return }
                set result [moduleA $input [outputDirectory $parent module_a] $uiEncoding]
            }
            export {
                set rows [captureRows]
                set candidates [categoryCandidates $rows]
                set overrides [requestCategoryOverrides $candidates]
                if {$overrides eq "__cancel__"} { return }
                set parent [tk_chooseDirectory -title "选择结果保存目录：自动读取原理图并按七列生成BOM"]
                if {$parent eq ""} { return }
                set result [exportCapture [outputDirectory $parent capture_bom] $rows $overrides]
            }
            default { error "Unknown action: $action" }
        }
        puts "BOM Workbench: $result"
        set message "处理完成\n输入位号：[get $result input_references]\n合并组数：[get $result groups]\n过滤记录：[get $result excluded]\n告警条数：[get $result warnings]\n\n结果文件：[get $result workbook]"
        set icon info
        if {[get $result pending_packages 0] > 0} {
            append message "\n\n注意：[get $result pending_packages] 个位号的分部属性冲突，暂未计入合并BOM。请查看Excel的告警及过滤清单，核对后再用于采购。"
            set icon warning
        }
        tk_messageBox -title "BOM整理工具" -icon $icon -message $message
    } err options]} {
        if {[get $options -code] == 0} { return }
        puts "BOM Workbench ERROR: $err"
        if {[dict exists $options -errorinfo]} { puts [dict get $options -errorinfo] }
        tk_messageBox -title "BOM处理失败" -icon error -message $err
        return 0
    }
    return 1
}
proc ::bomtool::log {message} {
    puts "bomtool: $message"
    catch {flush stdout}
}
proc ::bomtool::showWindow {w} {
    wm deiconify $w
    raise $w
    focus $w
}
proc ::bomtool::dialog {args} {
    # A fresh Capture session does not necessarily load Tk. Cadence's own
    # capAppLaunchMenu.tcl requires Tk at the click boundary for this reason.
    set hadTk [expr {[llength [info commands winfo]] > 0}]
    package require Tk 8.6
    if {!$hadTk} { wm withdraw . }
    set w .bomworkbench
    if {[winfo exists $w]} { showWindow $w; return }
    try {
    toplevel $w; wm title $w "BOM整理工具 $::bomtool::version - Capture CIS"
    label $w.title -text "读取当前原理图 → 按七列生成原生BOM → 整理为Excel" -padx 18 -pady 12
    pack $w.title
    foreach {id label action} [list export "自动生成并整理BOM" export a "导入已有TXT/CSV（可选）" A] {
        button $w.$id -text $label -command [list ::bomtool::runUI $action] -width 49
        pack $w.$id -padx 18 -pady 5 -fill x
    }
    frame $w.encoding
    label $w.encoding.label -text "文件导入编码："
    tk_optionMenu $w.encoding.menu ::bomtool::uiEncoding utf-8 cp936 unicode
    pack $w.encoding.label $w.encoding.menu -side left -padx 8
    pack $w.encoding -pady 10
    label $w.note -text "自动使用指定的Line Item Definition，无需手工导出。\n结果集中在BOM.xlsx；电容暂不区分材质。" -pady 10
    pack $w.note
    showWindow $w
    } on error {message options} {
        # Never leave a partial toplevel that subsequent clicks only raise.
        catch {destroy $w}
        return -options $options $message
    }
}
proc ::bomtool::openFromMenu {args} {
    log "open callback begin (version $::bomtool::version)"
    if {[catch {::bomtool::dialog} message options]} {
        log "open FAILED: $message"
        if {[dict exists $options -errorinfo]} { log [dict get $options -errorinfo] }
        if {[llength [info commands tk_messageBox]]} {
            catch {tk_messageBox -title "BOM工具无法打开" -icon error -message "打开失败：$message\n详情见Capture Command Window中的bomtool日志。"}
        }
        return 0
    }
    log "open OK"
    return 1
}
proc ::bomtool::exportFromMenu {args} {
    log "direct BOM export begin (version $::bomtool::version)"
    set hadTk [expr {[llength [info commands winfo]] > 0}]
    if {[catch {package require Tk 8.6} message options]} {
        log "direct BOM export FAILED to load Tk: $message"
        if {[dict exists $options -errorinfo]} { log [dict get $options -errorinfo] }
        if {[llength [info commands tk_messageBox]]} {
            catch {tk_messageBox -title "BOM\u5de5\u5177\u65e0\u6cd5\u542f\u52a8" \
                -icon error -message "\u65e0\u6cd5\u542f\u52a8 BOM \u8f93\u51fa\uff1a$message"}
        }
        return 0
    }
    if {!$hadTk} {
        catch {update}
        catch {wm withdraw .}
    }
    if {[catch {set completed [::bomtool::runUI export]} message options]} {
        log "direct BOM export FAILED: $message"
        if {[dict exists $options -errorinfo]} { log [dict get $options -errorinfo] }
        if {[llength [info commands tk_messageBox]]} {
            catch {tk_messageBox -title "BOM\u5904\u7406\u5931\u8d25" \
                -icon error -message $message}
        }
        return 0
    }
    if {$completed ne "1"} {
        log "direct BOM export cancelled or failed"
        return 0
    }
    log "direct BOM export finished"
    return 1
}
# Global entry point used by the unified OrCAD plugin window.
proc bomtoolMenuEnabled {args} { return true }
proc bomtoolMenuOpen {args} { return [::bomtool::openFromMenu {*}$args] }
proc bomtoolMenuExport {args} { return [::bomtool::exportFromMenu {*}$args] }
::bomtool::log "$::bomtool::version loaded from $::bomtool::scriptPath; run bomtoolMenuOpen to open"

foreach obsolete {moduleB compare loadRules clearRules} {
    if {[llength [info commands ::bomtool::$obsolete]]} { rename ::bomtool::$obsolete {} }
}
if {[llength [info commands winfo]] && [winfo exists .bomworkbench]} {
    destroy .bomworkbench
    ::bomtool::openFromMenu
}
