# SPDX-License-Identifier: GPL-3.0-only
namespace eval ::xiaokai::schematicPlugins {
    variable actions [dict create \
        lceda_clip lceda2orcadMenuFromClip \
        lceda_number lceda2orcadMenuDialog \
        lceda_clear lceda2orcadMenuClearOlb \
        netloc_page ::netloc::menuRun \
        netloc_sheet netlocSelectEntireNet \
        bom_export bomtoolMenuExport \
        drctool drctoolMenuRun \
        drc_run drctoolMenuRun \
        textaffix textaffixMenuRun]
    variable descriptions [dict create \
        drctool "\u53cc\u51fb\u76f4\u63a5\u68c0\u67e5\u5f53\u524d\u8bbe\u8ba1\u548c PCB \u7f51\u8868\uff0c\u663e\u793a\u4e2d\u6587\u9519\u8bef\uff1b\u96c6\u5408\u7a97\u53e3\u81ea\u52a8\u6700\u5c0f\u5316\u3002" \
        drc_run "\u53cc\u51fb\u76f4\u63a5\u68c0\u67e5\u5f53\u524d\u8bbe\u8ba1\u548c PCB \u7f51\u8868\uff0c\u663e\u793a\u4e2d\u6587\u9519\u8bef\u3002" \
        lceda "\u4ece\u526a\u8d34\u677f\u8bc6\u522b\u7acb\u521b EDA \u5668\u4ef6\u7f16\u53f7\uff0c\u5e76\u5c06\u5668\u4ef6\u6dfb\u52a0\u5230\u5f53\u524d\u539f\u7406\u56fe\u3002" \
        netlocator "\u5728\u539f\u7406\u56fe\u4e2d\u5b9a\u4f4d\u7f51\u7edc\u3001\u9009\u62e9\u6574\u7f51\uff0c\u6216\u67e5\u770b\u5f53\u524d\u9009\u4e2d\u7f51\u7edc\u540d\u79f0\u3002" \
        bom "\u6253\u5f00 BOM \u6574\u7406\u5de5\u4f5c\u53f0\uff0c\u5bfc\u5165\u5e76\u6574\u7406\u539f\u7406\u56fe\u7269\u6599\u6e05\u5355\u3002" \
        lceda_clip "\u8bfb\u53d6\u526a\u8d34\u677f\u4e2d\u7684\u7acb\u521b EDA \u5668\u4ef6\u7f16\u53f7\uff0c\u81ea\u52a8\u67e5\u627e\u5e76\u6dfb\u52a0\u5bf9\u5e94\u5668\u4ef6\u3002" \
        lceda_number "\u6253\u5f00\u5668\u4ef6\u7f16\u53f7\u8f93\u5165\u7a97\u53e3\uff0c\u8f93\u5165\u6216\u7c98\u8d34\u7acb\u521b EDA \u7f16\u53f7\u540e\u6dfb\u52a0\u5668\u4ef6\u3002" \
        lceda_clear "\u5220\u9664\u63d2\u4ef6\u751f\u6210\u7684 OLB \u5e93\u6587\u4ef6\uff1b\u4fdd\u7559\u5668\u4ef6\u7f13\u5b58\uff0c\u4e4b\u540e\u4ecd\u53ef\u91cd\u65b0\u751f\u6210\u3002" \
        netloc_page "\u67e5\u627e\u5f53\u524d\u9009\u4e2d\u7684\u7f51\u7edc\u51fa\u73b0\u5728\u54ea\u4e9b\u539f\u7406\u56fe\u9875\uff0c\u5e76\u8df3\u8f6c\u9ad8\u4eae\u7f51\u7edc\u3002\uff08Alt+F2\uff09" \
        netloc_sheet "\u5728\u5f53\u524d\u539f\u7406\u56fe\u9875\u9009\u62e9\u4e0e\u5f53\u524d\u7f51\u7edc\u76f8\u8fde\u7684\u5168\u90e8\u5bfc\u7ebf\u3002\uff08Alt+F3\uff09" \
        bom_export "\u81ea\u52a8\u8bfb\u53d6\u5f53\u524d\u539f\u7406\u56fe\uff0c\u751f\u6210\u539f\u751f BOM \u5e76\u81ea\u52a8\u6574\u7406\u4e3a Excel \u5de5\u4f5c\u7c3f\u3002"]
}

dict set ::xiaokai::schematicPlugins::descriptions textaffix "\u5355\u51fb\u6216\u6846\u9009\u5c5e\u6027\u3001\u5bfc\u7ebf\u5373\u53ef\u5904\u7406\uff1b\u5df2\u6709\u76f8\u540c\u524d\u540e\u7f00\u65f6\u53ef\u53bb\u6389\u3002\u9ed8\u8ba4\u8fde\u7eed\u5904\u7406\uff0cEsc \u505c\u6b62\u5e76\u5173\u95ed\u3002"

proc xiaokaiSchematicPluginsEnabled {args} { return true }

proc xiaokaiSchematicPluginsUpdateSelection {args} {
    set w .xiaokaiSchematicPlugins
    if {![winfo exists $w]} { return }
    set selected [$w.results.tv selection]
    set item [lindex $selected 0]
    set enabled [expr {[llength $selected] == 1
        && [dict exists $::xiaokai::schematicPlugins::actions $item]}]
    $w.run configure -state [expr {$enabled ? "normal" : "disabled"}]

    set description "\u9009\u62e9\u4e00\u9879\u529f\u80fd\uff0c\u8fd9\u91cc\u4f1a\u663e\u793a\u8be6\u7ec6\u8bf4\u660e\u3002"
    if {[llength $selected] == 1} {
        if {[dict exists $::xiaokai::schematicPlugins::descriptions $item]} {
            set description [dict get $::xiaokai::schematicPlugins::descriptions $item]
        }
    }
    $w.desc configure -text $description
}

proc xiaokaiSchematicPluginsRun {args} {
    set w .xiaokaiSchematicPlugins
    if {![winfo exists $w]} { return 0 }
    set selected [$w.results.tv selection]
    if {[llength $selected] != 1} { return 0 }
    set item [lindex $selected 0]
    if {![dict exists $::xiaokai::schematicPlugins::actions $item]} { return 0 }
    set command [dict get $::xiaokai::schematicPlugins::actions $item]
    if {$item in {drctool drc_run textaffix}} {
        wm iconify $w
        update idletasks
    }
    if {[catch {uplevel #0 $command} message options]} {
        puts "Xiaokai Toolbox plugin action failed ($command): $message"
        if {[dict exists $options -errorinfo]} {
            puts [dict get $options -errorinfo]
        }
        catch {tk_messageBox -parent $w -icon error -type ok \
            -title "\u6267\u884c\u5931\u8d25" -message $message}
        wm deiconify $w
        raise $w
        return 0
    }
    return 1
}

proc xiaokaiSchematicPluginsActivate {args} {
    set w .xiaokaiSchematicPlugins
    if {![winfo exists $w]} { return }
    set selected [$w.results.tv selection]
    if {[llength $selected] == 1
        && [dict exists $::xiaokai::schematicPlugins::actions [lindex $selected 0]]} {
        xiaokaiSchematicPluginsRun
    }
}

proc xiaokaiSchematicPluginsOpen {args} {
    set hadTk [expr {[llength [info commands winfo]] > 0}]
    if {[catch {package require Tk} message options]} {
        puts "Xiaokai Toolbox plugin manager: could not load Tk: $message"
        if {[dict exists $options -errorinfo]} {
            puts [dict get $options -errorinfo]
        }
        return 0
    }
    if {!$hadTk} {
        catch {update}
        catch {wm withdraw .}
    }

    set w .xiaokaiSchematicPlugins
    if {[winfo exists $w]} {
        wm deiconify $w
        raise $w
        focus $w.results.tv
        return 1
    }

    if {[catch {
        if {[catch {package require capAppUtils}]} {
            toplevel $w
        } else {
            capAppUtils::capTopLevel $w
        }
        wm title $w "\u5c0f\u5f00\u5de5\u5177\u7bb1 - \u539f\u7406\u56fe\u63d2\u4ef6\u96c6\u5408"
        wm geometry $w 620x430
        wm minsize $w 520 320
        wm resizable $w 1 1
        wm attributes $w -topmost 1

        ttk::style configure Xiaokai.Treeview \
            -font {{Segoe UI} 10} -rowheight 26 \
            -background white -foreground #202020
        ttk::style map Xiaokai.Treeview \
            -background [list selected #2878C8] \
            -foreground [list selected white]

        ttk::label $w.hdr -anchor w \
            -text "\u539f\u7406\u56fe\u63d2\u4ef6\u529f\u80fd" \
            -font {{Segoe UI} 10}
        ttk::label $w.hint -anchor w \
            -text "\u53cc\u51fb\u529f\u80fd\u6267\u884c\uff1bDRC \u68c0\u67e5\u65f6\u6b64\u7a97\u53e3\u81ea\u52a8\u6700\u5c0f\u5316\u3002"
        ttk::label $w.desc -anchor nw -justify left -wraplength 570 \
            -text "\u9009\u62e9\u4e00\u9879\u529f\u80fd\uff0c\u8fd9\u91cc\u4f1a\u663e\u793a\u8be6\u7ec6\u8bf4\u660e\u3002"
        frame $w.results
        ttk::treeview $w.results.tv -style Xiaokai.Treeview \
            -show tree -selectmode browse -height 12 \
            -yscrollcommand [list $w.results.scroll set]
        ttk::scrollbar $w.results.scroll -orient vertical \
            -command [list $w.results.tv yview]
        grid $w.results.tv -row 0 -column 0 -sticky nsew
        grid $w.results.scroll -row 0 -column 1 -sticky ns
        grid rowconfigure $w.results 0 -weight 1
        grid columnconfigure $w.results 0 -weight 1

        set tree $w.results.tv
        set lceda [$tree insert {} end -id lceda \
            -text "1. \u7acb\u521b EDA \u8f6c OrCAD" -open 0]
        $tree insert $lceda end -id lceda_clip \
            -text "01  \u4ece\u526a\u8d34\u677f\u6dfb\u52a0\u5668\u4ef6"
        $tree insert $lceda end -id lceda_number \
            -text "02  \u6309\u7f16\u53f7\u6dfb\u52a0\u5668\u4ef6"
        $tree insert $lceda end -id lceda_clear \
            -text "03  \u6e05\u9664\u751f\u6210\u7684 OLB"

        set netloc [$tree insert {} end -id netlocator \
            -text "2. Netlocator" -open 0]
        $tree insert $netloc end -id netloc_page \
            -text "01  \u8de8\u9875\u5b9a\u4f4d\u9009\u4e2d\u7f51\u7edc\uff08Alt+F2\uff09"
        $tree insert $netloc end -id netloc_sheet \
            -text "02  \u9009\u62e9\u5f53\u524d\u9875\u6574\u7f51\uff08Alt+F3\uff09"
        set bom [$tree insert {} end -id bomtool \
            -text "3. BOM \u6574\u7406\u5de5\u5177" -open 0]
        $tree insert $bom end -id bom_export \
            -text "01  \u81ea\u52a8\u751f\u6210\u5e76\u6574\u7406 BOM"

        $tree insert {} end -id drctool -text "4. DRC\u4e2d\u6587\u589e\u5f3a\u7248"
        $tree insert {} end -id textaffix -text "5. \u6587\u5b57\u524d\u540e\u7f00"

        ttk::button $w.run -text "\u6267\u884c" -width 12 \
            -state disabled -command xiaokaiSchematicPluginsRun
        ttk::button $w.close -text "\u5173\u95ed" -width 12 \
            -command [list wm withdraw $w]
        grid $w.hdr -row 0 -column 0 -columnspan 2 -sticky we -padx 14 -pady {14 4}
        grid $w.results -row 1 -column 0 -columnspan 2 -sticky nsew -padx 14 -pady 4
        grid $w.desc -row 2 -column 0 -columnspan 2 -sticky we -padx 14 -pady {8 4}
        grid $w.hint -row 3 -column 0 -columnspan 2 -sticky w -padx 14 -pady {4 10}
        grid $w.run -row 4 -column 0 -sticky e -padx 14 -pady {0 14}
        grid $w.close -row 4 -column 1 -sticky e -padx {0 14} -pady {0 14}

        grid rowconfigure $w 1 -weight 1
        grid columnconfigure $w 0 -weight 1
        wm attributes $w -topmost 1
        wm protocol $w WM_DELETE_WINDOW [list wm withdraw $w]
        bind $tree <<TreeviewSelect>> xiaokaiSchematicPluginsUpdateSelection
        bind $tree <Double-Button-1> xiaokaiSchematicPluginsActivate
        bind $tree <Return> xiaokaiSchematicPluginsActivate
        bind $w <Return> xiaokaiSchematicPluginsActivate
        bind $w <Escape> [list wm withdraw $w]
        wm deiconify $w
        raise $w
        focus $tree
    } message options]} {
        catch {destroy $w}
        puts "Xiaokai Toolbox plugin manager: could not create window: $message"
        if {[dict exists $options -errorinfo]} {
            puts [dict get $options -errorinfo]
        }
        return 0
    }
    return 1
}

if {[llength [info commands RegisterAction]]} {
    catch {UnregisterAction "xiaokaiSchematicPluginsAltK"}
    if {[catch {
        RegisterAction "xiaokaiSchematicPluginsAltK" \
            "xiaokaiSchematicPluginsEnabled" "Alt+K" \
            "xiaokaiSchematicPluginsOpen" "Schematic"
    } message]} {
        puts "Xiaokai Toolbox: Alt+K registration failed: $message"
    } else {
        puts "Xiaokai Toolbox schematic plugin manager loaded; press Alt+K."
    }
}
