# SPDX-License-Identifier: GPL-3.0-only
# Keep Dbo pointers local to a single operation. Undo stores names/IDs/values,
# then resolves fresh objects; deleted objects and closed designs are never used.
namespace eval ::xiaokai::textaffix {
    variable active 0
    variable busy 0
    variable pending ""
    variable escapePipe ""
    variable history {}
    variable historyDesign ""
    variable status "设置文字和位置，单击或框选即可处理；Esc 停止并关闭。"
    variable text NC/
    variable side before
    variable removeExisting 1
    variable properties 1
    variable networks 1
    variable property Value
}

proc ::xiaokai::textaffix::check {state} {
    try {
        if {![$state OK]} {error "Capture 拒绝了本次修改（属性可能只读，或名称不合法）。"}
    } finally {$state -delete}
}

proc ::xiaokai::textaffix::readString {obj method args} {
    set c [DboTclHelper_sMakeCString]
    try {
        check [$obj $method {*}$args $c]
        return [DboTclHelper_sGetConstCharPtr $c]
    } finally {DboTclHelper_sDeleteCString $c}
}

proc ::xiaokai::textaffix::each {obj make next destroy args} {
    set s [DboState]; set it NULL; set result {}
    try {
        set it [$obj $make $s {*}$args]
        if {$it eq "NULL" || ![$s OK]} {error "无法读取原理图对象：$make"}
        for {set item [$it $next $s]} {$item ne "NULL"} {set item [$it $next $s]} {
            lappend result $item
        }
    } finally {
        if {$it ne "NULL"} {$destroy $it}
        $s -delete
    }
    return $result
}

proc ::xiaokai::textaffix::id {obj} {
    set s [DboState]
    try {return [$obj GetId $s]} finally {$s -delete}
}

proc ::xiaokai::textaffix::design {} {
    if {![llength [info commands GetSelectedObjects]] || ![IsSchematicViewActive]} {
        error "请先打开一张原理图。"
    }
    set session $::DboSession_s_pDboSession
    DboSession -this $session
    set d [$session GetActiveDesign]
    if {$d eq "NULL"} {error "请先打开原理图设计。"}
    return $d
}

proc ::xiaokai::textaffix::netName {wire} {
    set s [DboState]
    try {
        set net [$wire GetNet $s]
        if {$net eq "NULL"} {return ""}
        set schnet [$net GetSchematicNet]
        if {$schnet ne "NULL"} {return [readString $schnet GetName]}
        return [readString $wire GetNetName]
    } finally {$s -delete}
}

proc ::xiaokai::textaffix::row {obj page kind prop schName pageName} {
    if {$kind eq "prop"} {
        set n [DboTclHelper_sMakeCString $prop]
        try {set value [readString $obj GetEffectivePropStringValue $n]} finally {DboTclHelper_sDeleteCString $n}
    } else {set value [readString $obj GetName]}
    return [dict create key [list $schName $pageName [id $obj] $kind $prop] \
        object $obj page $page kind $kind prop $prop value $value]
}

# A fresh inventory also lets undo validate the current values before restoring.
# Network names are scoped to one schematic, across its pages (Capture's
# DboSchematicNet scope). All aliases and connected name sources travel together.
proc ::xiaokai::textaffix::inventory {design propNames {scope {}} {scanNets 1}} {
    set rows {}; set wireNets {}; set memberNets {}; set seeds {}; set names {}
    foreach view [each $design NewViewsIter NextView delete_DboLibViewsIter $::IterDefs_SCHEMATICS] {
        set sch [DboViewToDboSchematic $view]
        set sn [readString $sch GetName]
        if {[llength $scope] && $sn ne [lindex $scope 0]} {continue}
        foreach page [each $sch NewPagesIter NextPage delete_DboSchematicPagesIter] {
            set pn [readString $page GetName]
            if {![llength $scope] || $pn eq [lindex $scope 1]} {
              foreach part [each $page NewPartInstsIter NextPartInst delete_DboPagePartInstsIter] {
                foreach prop $propNames {
                    # A missing property on a part is not created by box selection.
                    if {[catch {row $part $page prop $prop $sn $pn} r]} {continue}
                    dict set rows [dict get $r key] $r
                }
              }
            }
            if {!$scanNets} {continue}
            foreach wire [each $page NewWiresIter NextWire delete_DboPageWiresIter] {
                set name [netName $wire]
                set nk [list $sn $name]
                set wk [list $sn $pn [id $wire] wire ""]
                dict set wireNets $wk $nk
                dict set names $nk 1
                if {![dict exists $seeds $nk]} {
                    dict set seeds $nk [dict create key $wk object $wire page $page kind create prop "" value $name]
                }
                foreach spec {
                    {NewAliasesIter NextAlias delete_DboWireAliasesIter}
                    {NewOffPageConnectorsIter NextOffPageConnector delete_DboWireOffPageConnectorsIter}
                    {NewGlobalsIter NextGlobal delete_DboWireGlobalsIter}
                    {NewPortsIter NextPort delete_DboWirePortsIter}
                } {
                    lassign $spec make next del
                    if {$make eq "NewPortsIter"} {
                        set objects [each $wire $make $next $del $::IterDefs_ALL]
                    } else {set objects [each $wire $make $next $del]}
                    foreach obj $objects {
                        set r [row $obj $page name "" $sn $pn]
                        set key [dict get $r key]
                        dict set rows $key $r
                        dict set memberNets $key $nk
                    }
                }
            }
            # Enumerate page symbols too: a connector/port/global need not be
            # attached to a wire. Preserve wire-derived membership when present.
            foreach spec {
                {NewOffPageConnectorsIter NextOffPageConnector delete_DboPageOffPageConnectorsIter 1}
                {NewGlobalsIter NextGlobal delete_DboPageGlobalsIter 0}
                {NewPortsIter NextPort delete_DboPagePortsIter 1}
            } {
                lassign $spec make next del all
                set args {}; if {$all} {lappend args $::IterDefs_ALL}
                foreach obj [each $page $make $next $del {*}$args] {
                    set r [row $obj $page name "" $sn $pn]
                    set key [dict get $r key]
                    dict set rows $key $r
                    if {![dict exists $memberNets $key]} {
                        set name [dict get $r value]
                        # Empty, detached symbols remain individual targets.
                        if {$name ne ""} {dict set memberNets $key [list $sn $name]}
                    }
                }
            }
        }
    }
    return [dict create rows $rows wireNets $wireNets memberNets $memberNets seeds $seeds names $names]
}

proc ::xiaokai::textaffix::isType {obj types} {
    set type [$obj GetObjectType]
    foreach name $types {
        if {[info exists ::DboBaseObject_$name] && $type == [set ::DboBaseObject_$name]} {return 1}
    }
    return 0
}

proc ::xiaokai::textaffix::isNameSource {obj} {
    return [isType $obj {ALIAS OFF_PAGE_CONNECTOR DBGLOBAL GLOBAL_SYMBOL PORT}]
}

proc ::xiaokai::textaffix::selection {selected} {
    variable properties; variable networks; variable property
    set page [GetActivePage]
    set pn [readString $page GetName]; set sn [readString [$page GetOwner] GetName]
    set keys {}; set fallback {}; set wires {}; set props [list $property]; set explicit {}
    foreach obj $selected {
        if {[isType $obj {DISPLAY_PROP}]} {
            set dp [DboBaseObjectToDboDisplayProp $obj]
            set prop [readString $dp GetName]
            set owner [$dp GetOwner]
            if {$properties && [isType $owner {PART_INSTANCE PLACED_INSTANCE DRAWN_INSTANCE}]} {
                # A display property is just a view: modify its owner's value.
                lappend props $prop
                set key [list $sn $pn [id $owner] prop $prop]
                dict set explicit [list $sn $pn [id $owner]] 1
                lappend keys $key
            } elseif {$networks && [isType $owner {WIRE WIRE_SCALAR WIRE_BUS}]} {
                lappend wires [list $sn $pn [id $owner] wire ""]
            } elseif {$networks && [isNameSource $owner]} {
                # Symbol Name displays belong to the symbol, not its wire.
                lappend keys [list $sn $pn [id $owner] name ""]
            }
        } elseif {$properties && [isType $obj {PART_INSTANCE PLACED_INSTANCE DRAWN_INSTANCE}]} {
            lappend fallback [list $sn $pn [id $obj] prop $property]
        } elseif {$networks && [isType $obj {WIRE WIRE_SCALAR WIRE_BUS}]} {
            lappend wires [list $sn $pn [id $obj] wire ""]
        } elseif {$networks && [isNameSource $obj]} {
            lappend keys [list $sn $pn [id $obj] name ""]
        }
    }
    # Capture may include both a part and a selected display property in a box.
    # Prefer the explicitly selected fields over the part's fallback property.
    foreach key $fallback {
        lassign $key ks kp ki kk kprop
        if {![dict exists $explicit [list $ks $kp $ki]]} {lappend keys $key}
    }
    return [dict create keys $keys wires $wires props [lsort -unique $props]]
}

proc ::xiaokai::textaffix::targets {inv selection} {
    set result {}; set nets {}; set rows [dict get $inv rows]
    foreach key [dict get $selection keys] {
        if {![dict exists $rows $key]} {continue}
        if {[dict exists $inv memberNets $key]} {
            dict set nets [dict get $inv memberNets $key] 1
        } else {lappend result [dict get $rows $key]}
    }
    foreach key [dict get $selection wires] {
        if {[dict exists $inv wireNets $key]} {dict set nets [dict get $inv wireNets $key] 1}
    }
    dict for {nk ignored} $nets {
        set found 0
        dict for {key net} [dict get $inv memberNets] {
            if {$net eq $nk} {lappend result [dict get $rows $key]; set found 1}
        }
        if {!$found && [lindex $nk 1] ne ""} {lappend result [dict get $inv seeds $nk]}
    }
    return $result
}

proc ::xiaokai::textaffix::writeValue {row value} {
    set obj [dict get $row object]; set kind [dict get $row kind]
    set c [DboTclHelper_sMakeCString $value]
    try {
        if {$kind eq "prop"} {
            set n [DboTclHelper_sMakeCString [dict get $row prop]]
            try {check [$obj SetEffectivePropStringValue $n $c]} finally {DboTclHelper_sDeleteCString $n}
        } elseif {$kind eq "created" && $value eq ""} {
            check [[$obj GetOwner] DeleteAlias $obj]
        } elseif {$kind eq "create"} {
            set s [DboState]
            set pt [$obj GetPoint 0 $s]
            # This static helper requires the containing library/design even
            # though its SWIG argument accepts any DboBaseObject.
            set font [DboLib_sGetDefaultAliasFont [$obj GetContainingLib] $s]
            try {
                set alias [$obj NewAlias $s $c $pt $font $::DboValue_NOROTATION 0]
                if {$alias eq "NULL" || ![$s OK]} {error "无法为导线创建网络名称。"}
                lassign [dict get $row key] sn pn ignored
                dict set row key [list $sn $pn [id $alias] name ""]
                dict set row object $alias
                dict set row kind created
                dict set row before ""
            } finally {
                DboTclHelper_sDeleteCPoint $pt
                DboTclHelper_sDeleteLOGFONT $font
                $s -delete
            }
        } else {check [$obj SetName $c]}
        check [[dict get $row page] MarkModified]
    } finally {DboTclHelper_sDeleteCString $c}
    return $row
}

proc ::xiaokai::textaffix::refresh {rows} {
    set pages {}
    foreach row $rows {dict set pages [dict get $row page] 1}
    dict for {page ignored} $pages {DboTclHelper_sEvalPage $page}
    ZoomRedraw
}

proc ::xiaokai::textaffix::applySelection {} {
    variable busy; variable history; variable historyDesign; variable status
    variable text; variable side; variable removeExisting; variable property
    if {$busy} {return 0}
    set busy 1; set done {}
    try {
        appendText "" $text $side $removeExisting
        if {[string trim $property] eq ""} {error "请输入框选元件时要修改的属性名。"}
        set d [design]
        set selected [GetSelectedObjects]
        set sel [selection $selected]
        set scanNets [expr {[llength [dict get $sel wires]] > 0}]
        foreach key [dict get $sel keys] {if {[lindex $key 3] eq "name"} {set scanNets 1}}
        set page [GetActivePage]
        set scope [list [readString [$page GetOwner] GetName] [readString $page GetName]]
        set inv [inventory $d [dict get $sel props] $scope $scanNets]
        set plan [makePlan [targets $inv $sel] $text $side $removeExisting]
        if {![llength $plan]} {set status "没有可处理的目标。可继续单击或框选；Esc 停止并关闭。"; return 0}
        # Validate net names before making any change.
        foreach row $plan {
            if {[dict get $row kind] eq "prop"} {continue}
            set c [DboTclHelper_sMakeCString [dict get $row after]]
            try {
                if {![DboPage_IsValidNetName $c]} {error "网络名称不合法：[dict get $row after]"}
            } finally {DboTclHelper_sDeleteCString $c}
        }
        foreach row $plan {lappend done [writeValue $row [dict get $row after]]}
        refresh $done
        if {$historyDesign ne $d} {set history {}; set historyDesign $d}
        set saved {}
        foreach row $done {lappend saved [dict remove $row object page value]}
        lappend history $saved
        set history [lrange $history end-49 end]
        set status "已处理 [llength $done] 处文字。可继续单击或框选；Esc 停止并关闭。"
        return [llength $done]
    } on error {message options} {
        foreach row [lreverse $done] {catch {writeValue $row [dict get $row before]}}
        catch {refresh $done}
        set status "处理失败：$message"
        puts "Text affix: [dict get $options -errorinfo]"
        return -1
    } finally {set busy 0}
}

proc ::xiaokai::textaffix::undo {} {
    variable history; variable historyDesign; variable status; variable busy
    if {$busy || ![llength $history]} {set status "没有可撤销的添加。"; return 0}
    set busy 1; set done {}
    try {
        set d [design]
        if {$d ne $historyDesign} {set history {}; error "当前设计已变化，撤销记录已清空。"}
        set batch [lindex $history end]; set props {}
        foreach r $batch {if {[dict get $r kind] eq "prop"} {lappend props [dict get $r prop]}}
        set inv [inventory $d [lsort -unique $props]]; set restore {}
        foreach r $batch {
            set key [dict get $r key]
            if {![dict exists $inv rows $key]} {error "目标已删除或图页已变化，无法撤销本批添加。"}
            set live [dict get $inv rows $key]
            if {[dict get $live value] ne [dict get $r after]} {error "目标文字已被再次编辑，无法撤销本批添加。"}
            lappend restore [dict merge $live $r]
        }
        foreach r [lreverse $restore] {writeValue $r [dict get $r before]; lappend done $r}
        refresh $restore
        set history [lrange $history 0 end-1]
        set status "已撤销上次处理（[llength $restore] 处）。可继续单击或框选。"
        return [llength $restore]
    } on error {message} {set status "撤销失败：$message"; return -1} finally {set busy 0}
}

proc ::xiaokai::textaffix::stop {} {
    variable active; variable pending; variable escapePipe
    set active 0
    if {$pending ne ""} {after cancel $pending; set pending ""}
    if {$escapePipe ne ""} {
        set pipe $escapePipe; set escapePipe ""
        fileevent $pipe readable ""
        catch {puts $pipe STOP; flush $pipe}
        catch {close $pipe}
    }
    if {[llength [info commands ::xiaokai::textaffix::updateControls]]} {updateControls}
}

proc ::xiaokai::textaffix::start {} {
    variable active; variable text; variable side; variable removeExisting; variable status
    variable properties; variable networks
    if {[catch {
        design
        startEscapeWatcher
    } why]} {set status $why; return 0}
    set active 1
    set status "连续添加中：单击属性／导线／页间连接符等，或框选。Esc 停止并关闭。"
    updateControls
    return 1
}

proc ::xiaokai::textaffix::startEscapeWatcher {} {
    variable helperImage; variable escapePipe
    if {$escapePipe ne ""} {return}
    if {![info exists helperImage]} {error "请加载生成的 textaffixMenu.tcl 后再打开工具。"}
    set dir [file join $::env(LOCALAPPDATA) XiaokaiToolbox textaffix]
    file mkdir $dir
    set path [file join $dir textaffixKeys-1.0.0.exe]
    set bytes [binary decode base64 $helperImage]
    set installed ""
    if {[file exists $path]} {
        set f [open $path rb]
        try {set installed [read $f]} finally {close $f}
    }
    if {$installed ne $bytes} {
        set f [open $path wb]
        try {puts -nonewline $f $bytes} finally {close $f}
    }
    set escapePipe [open [list | $path [pid]] r+]
    fconfigure $escapePipe -blocking 0 -buffering line -encoding ascii
    fileevent $escapePipe readable [list ::xiaokai::textaffix::escapeReadable $escapePipe]
}

proc ::xiaokai::textaffix::escapeReadable {pipe} {
    variable escapePipe; variable active; variable status
    if {$pipe ne $escapePipe} {return}
    if {[gets $pipe line] >= 0 && $line eq "ESC"} {
        hide
    } elseif {[eof $pipe]} {
        stop
        set status "Esc 退出功能未能启动。请关闭后重新打开工具。"
    }
}

proc ::xiaokai::textaffix::needsEvent {command args} {
    variable active; variable busy
    return [expr {$active && !$busy && $command eq "OnLButtonUp"}]
}

proc ::xiaokai::textaffix::onEvent {args} {
    variable pending
    if {$pending eq ""} {set pending [after idle ::xiaokai::textaffix::applyPending]}
}

proc ::xiaokai::textaffix::applyPending {} {
    variable active; variable pending
    set pending ""
    if {$active} {applySelection}
}

proc ::xiaokai::textaffix::onCloseDesign {args} {
    variable history; variable historyDesign
    hide
    set history {}; set historyDesign ""
}

proc textaffixMenuEnabled {args} {return 1}
proc textaffixMenuRun {args} {::xiaokai::textaffix::show}
if {[llength [info commands RegisterAction]] && ![info exists ::xiaokai::textaffix::registered]} {
    RegisterAction _cdnOrSchViewCmdComplete ::xiaokai::textaffix::needsEvent "" ::xiaokai::textaffix::onEvent ""
    RegisterAction _cdnOrNotifyDesignPreClose textaffixMenuEnabled "" ::xiaokai::textaffix::onCloseDesign ""
    set ::xiaokai::textaffix::registered 1
}
