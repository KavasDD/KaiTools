# Text uses page coordinates; all geometry is read afresh before preview/write.
proc ::xiaokai::drc::reviewRect {native} {
    try {
        set a [DboTclHelper_sGetCRectTopLeft $native]
        set b [DboTclHelper_sGetCRectBottomRight $native]
        try {
            set x [DboTclHelper_sGetCPointX $a]; set y [DboTclHelper_sGetCPointY $a]
            set u [DboTclHelper_sGetCPointX $b]; set v [DboTclHelper_sGetCPointY $b]
            return [list [expr {min($x,$u)}] [expr {min($y,$v)}] [expr {max($x,$u)}] [expr {max($y,$v)}]]
        } finally {DboTclHelper_sDeleteCPoint $a; DboTclHelper_sDeleteCPoint $b}
    } finally {DboTclHelper_sDeleteCRect $native}
}
proc ::xiaokai::drc::reviewTextSize {text} {
    # Small native schematic note, not the size of the details-panel text.
    set width 4
    foreach c [split $text ""] {scan $c %c n; incr width [expr {$n > 127 ? 8 : 5}]}
    return [list [expr {max(16,$width)}] 12]
}
proc ::xiaokai::drc::reviewTransformRect {object box} {
    lassign $box l t r b; set xs {}; set ys {}
    foreach xy [list [list $l $t] [list $r $t] [list $r $b] [list $l $b]] {
        set local [DboTclHelper_sMakeCPoint {*}$xy]
        try {
            set point [$object GetOffsetGraphicPoint $local]
            try {lappend xs [DboTclHelper_sGetCPointX $point]; lappend ys [DboTclHelper_sGetCPointY $point]} finally {DboTclHelper_sDeleteCPoint $point}
        } finally {DboTclHelper_sDeleteCPoint $local}
    }
    return [list [tcl::mathfunc::min {*}$xs] [tcl::mathfunc::min {*}$ys] [tcl::mathfunc::max {*}$xs] [tcl::mathfunc::max {*}$ys]]
}
proc ::xiaokai::drc::reviewGraphicRect {object state} {
    set box [reviewRect [$object GetOffsetBoundingBox $state]]
    if {$box ne {0 0 0 0}} {return $box}
    # An unrendered Text has an empty display cache even after successful
    # creation. Its persisted definition and placement are already available.
    if {[$object GetObjectType] == $::DboBaseObject_GRAPHIC_COMMENTTEXT_INST} {
        set definition [[DboGraphicInstanceToDboGraphicCommentTextInst $object] GetDboCommentText]
        return [reviewTransformRect $object [reviewRect [$definition GetBoundingBox]]]
    }
    return $box
}
# Read the actual pin hotspot again for every plan/write. Do not move the Text
# away from that point, even when symbols, wires or other Text overlap it.
proc ::xiaokai::drc::reviewFaultPoint {page row partId} {
    set s [DboState]; set focus {}; set found 0
    try {
        set it [$page NewPartInstsIter $s]
        try {
            for {set part [$it NextPartInst $s]} {$part ne "NULL"} {set part [$it NextPartInst $s]} {
                if {[$part GetId $s] ne $partId} {continue}
                set found 1
                set pins [$part NewPinsIter $s]
                try {
                    for {set pin [$pins NextPin $s]} {$pin ne "NULL"} {set pin [$pins NextPin $s]} {
                        foreach target [get $row _targets {}] {
                            if {[get $target _pin_id] ne [$pin GetId $s]} {continue}
                            set point [$pin GetOffsetHotSpot $s]
                            try {
                                lappend focus [list [DboTclHelper_sGetCPointX $point] [DboTclHelper_sGetCPointY $point]]
                            } finally {DboTclHelper_sDeleteCPoint $point}
                        }
                    }
                } finally {delete_DboPartInstPinsIter $pins}
                break
            }
        } finally {delete_DboPagePartInstsIter $it}
        if {!$found} {error "器件已不存在，请重新检查。"}
        set focus [lsort -unique $focus]
        if {[llength $focus] != 1} {error "错误未唯一对应一个连接点，请在列表定位核对。"}
        return [lindex $focus 0]
    } finally {$s -delete}
}
proc ::xiaokai::drc::reviewPlacement {candidate checkedResult {offset 0} {reserved {}}} {
    set row [dict get $candidate row]
    set page [reviewPage [dict get $checkedResult design] [get $row _schematic] [get $row sheet_name]]
    set point [reviewFaultPoint $page $row [dict get $candidate part_id]]
    lassign $point x y
    lassign [reviewTextSize [get $candidate text "核对漏接"]] width height
    set rect [list $x $y [expr {$x+$width}] [expr {$y+$height}]]
    return [dict merge $candidate [dict create x $x y $y text_rect $rect fault_point $point]]
}
