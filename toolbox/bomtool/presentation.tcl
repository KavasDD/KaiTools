# SPDX-License-Identifier: GPL-3.0-only
# Chinese presentation is assembled into an ASCII-safe Capture deliverable.
proc ::bomtool::cn {code} {
    set names [dict create cap "电容" res "电阻" ind "电感/磁珠" diode "二极管" mos "MOS/三极管" ic "集成电路" conn "连接器" batt "电池座" xtal "晶振" other "其他" \
        NC "不焊接" TP "测试点" MARK "定位标记点" HOLE "螺丝孔/安装孔" DUPLICATE_REFERENCE "位号重复，已隔离" MISSING_FIELD "缺少值或封装，已隔离" MISSING_REFERENCE "缺少位号，已隔离" \
        PACKAGE_CONFLICT "同位号分部属性冲突，待核对（不等于不焊接）" WARN-PACKAGE-CONFLICT "同位号分部关键属性冲突" WARN-PACKAGE-METADATA "同位号分部辅助字段差异或空值补齐" \
        OBSERVED_MATCH "规格已匹配" NEEDS_SELECTION "需选择满足合并规格的器件" REVIEW_LIBRARY "需检查原理图库" \
        WARN-0OHM-FOOTPRINT "0Ω电阻使用电容封装名" WARN-CATEGORY-FOOTPRINT "位号类别与封装名不符" WARN-VALUE-FOOTPRINT "值中的封装简码与PCB封装不符" WARN-MISSING-FIELD "器件值或封装缺失" \
        WARN-UNPARSED-SUFFIX "规格后缀无法完整识别" WARN-UNPARSED-VALUE "器件值无法解析为标称数值" WARN-DUPLICATE-REFERENCE "同一位号重复出现" WARN-MISSING-REFERENCE "记录缺少位号"]
    return [get $names $code $code]
}
proc ::bomtool::cnReasons {codes} {
    set out {}; foreach code [split $codes {;}] { if {$code ne ""} { lappend out [cn $code] } }
    return [join $out "；"]
}
proc ::bomtool::warningDetail {code ref category value fp} {
    switch -- $code {
        WARN-PACKAGE-CONFLICT {
            return [list "位号 $ref 的多个分部存在关键属性冲突。" "该位号暂不计入合并BOM，放入过滤清单待核对；其他器件继续导出。此原因不表示不焊接。" "按下列字段及原始BOM行号检查各分部的型号、封装、规格或焊接状态；若实际为不同器件，请修正重复位号后重新导出。"]
        }
        WARN-PACKAGE-METADATA {
            return [list "位号 $ref 的多个分部存在辅助字段差异或部分字段为空。" "同一位号仅计一个器件；空字段用其他分部非空值补齐，辅助字段多值时保留首个非空值。原始分部记录全部保留。" "核对下列差异；描述、EMPTY、材质差异不再中止导出，电容暂不按材质区分。"]
        }
        WARN-VALUE-FOOTPRINT {
            return [list "位号 $ref 的值 $value 中，-04表示0402封装，但PCB Footprint为 $fp。" "保留原始PCB封装和简码，不按0402自动合并；结果标记为需检查原理图库。" "确认实际焊盘尺寸，统一值中的封装简码与PCB Footprint后重新导出。"]
        }
        WARN-0OHM-FOOTPRINT {
            return [list "位号 $ref 是0Ω电阻，原封装为 $fp，使用了C前缀电容封装名。" "允许按0Ω例外在电阻组内合并，不会合入电容组。" "确认焊盘尺寸正确；建议将库封装名规范为电阻封装名。"]
        }
        WARN-CATEGORY-FOOTPRINT {
            return [list "位号 $ref 被识别为[cn $category]，原值为 $value，封装 $fp 的C/R前缀与类别不符。" "保留在原类别内，合并结果标记为需检查原理图库。" "核对位号、器件值和PCB封装，修正原理图库；不得跨类别合并。"]
        }
        WARN-MISSING-FIELD {
            set missing {}; if {$value eq ""} { lappend missing "器件值" }; if {$fp eq ""} { lappend missing "PCB封装" }
            return [list "位号 $ref 缺少[join $missing "、"]。" "已移入过滤清单，不计入最终BOM。" "在原理图中补齐字段后重新导出。"]
        }
        WARN-UNPARSED-SUFFIX {
            return [list "位号 $ref 的值 $value 包含未完整识别的后缀，可能是功率、电流、封装简码或其他规格。" "后缀原文保留在分组键中，仅与相同后缀合并。" "检查归一化明细；确认后缀含义后规范器件值，不要直接删除。"]
        }
        WARN-UNPARSED-VALUE {
            return [list "位号 $ref 按前缀归为[cn $category]，但值 $value 无法解析为对应标称数值。" "保留原文分组；不会仅因无法解析而丢弃器件。" "若为型号编码可保留；若为容量/阻值/感值，请规范单位。同时核对位号前缀是否正确。"]
        }
        WARN-DUPLICATE-REFERENCE {
            return [list "位号 $ref 在输入BOM中出现多次，无法确认是否重复计数或属性冲突。" "该位号所有记录均隔离，不计入最终BOM。" "按源行号核对原始BOM，消除重复或修正位号后重新导出。"]
        }
        WARN-MISSING-REFERENCE {
            return [list "该行有数据但没有位号，值为 $value，封装为 $fp。" "已移入过滤清单，不计入最终BOM。" "补齐位号；若是附注或辅料，请单独维护。"]
        }
        default { return [list [cn $code] "请核对原始记录。" "根据原理图确认后处理。"] }
    }
}
proc ::bomtool::presentSheets {sheets} {
    set result {}
    set compact {}; set n 0
    foreach r [lindex [lindex $sheets 0] 2] {
        incr n
        lassign $r refs qty cat fp norm key required volt tol status eligible sourceRows originals issues warnings
        set note ""
        if {$status ne "OBSERVED_MATCH"} { set note [cn $status] }
        if {$warnings ne ""} { if {$note ne ""} { append note "；" }; append note [cnReasons $warnings] }
        lappend compact [list $n $refs $qty [cn $cat] $required $fp $note]
    }
    lappend result [list "合并BOM" [list "序号" "位号" "数量" "类别" "规格参数" "封装" "备注"] $compact {1 3}]
    set excluded {}
    foreach r [lindex [lindex $sheets 1] 2] {
        lassign $r ref line reasons value fp evidence
        lappend excluded [list $ref $line [cnReasons $reasons] $evidence $value $fp]
    }
    lappend result [list "过滤清单" [list "位号" "源行号" "过滤原因" "不焊接依据" "原始值" "原始封装"] $excluded {2}]
    set warnings {}
    foreach r [lindex [lindex $sheets 2] 2] {
        lassign $r code ref line cat value fp extra
        lassign [warningDetail $code $ref $cat $value $fp] detail effect action
        if {$extra ne ""} { append detail "\n" $extra }
        lappend warnings [list $ref [cn $code] $detail $effect $action $line $value $fp $code]
    }
    lappend result [list "告警" [list "位号" "问题类型" "具体原因" "本次处理" "建议处理" "源行号" "原始值" "原始封装" "告警编号"] $warnings {6}]
    set audit {}
    foreach r [lindex [lindex $sheets 3] 2] {
        lset r 2 [cn [lindex $r 2]]; lset r 8 [cnReasons [lindex $r 8]]; lappend audit $r
    }
    lappend result [list "归一化明细" [list "位号" "源行号" "类别" "原始封装" "归一化封装" "原始值" "归一化值" "分组键" "过滤原因"] $audit {2}]
    # The native sheet intentionally uses the user's exact seven column names.
    lappend result [lindex $sheets 4]
    set summary {}
    set labels [dict create Version "软件版本" InputRows "原生记录数" InputReferences "输入位号数" Groups "合并组数" Excluded "过滤记录数" Warnings "告警条数" MaterialPolicy "材质处理" GroupKey "分组规则" \
        ClassificationPolicy "默认分类方式" MergePolicy "默认合并方式" FilterPolicy "默认过滤方式" WarningPolicy "默认告警方式"         InductorPolicy "电感规格处理" SpecialCategoryPolicy "特殊分类规则" FootprintPolicy "封装归一与显示" ValuePolicy "器件值解析与保留" SpecificationPolicy "合并规格计算" CaptureSectionPolicy "多单元器件处理" BatchClassificationPolicy "批量分类询问"]
    foreach r [lindex [lindex $sheets 5] 2] {
        lassign $r k v
        if {$k eq "MaterialPolicy"} { set v "暂不区分材质" }
        if {$k eq "GroupKey"} { set v "器件类别:归一化封装:归一化值" }
        if {$k eq "ClassificationPolicy"} {
            set v "按位号前缀分类：C/PC=电容；R/PR=电阻；L/PL/FB/PFB/LV/CH/CHK/CHOKE=电感或磁珠；D=二极管；Q/PQ/QN=MOS/三极管；U/PU/AU=集成电路；J/JGPIO/PCI/PCIE/SATA/USB/COM=连接器；其余为其他。长前缀优先。"
        }
        if {$k eq "SpecialCategoryPolicy"} {
            set v "AC+常见C封装识别为电容；AR+R封装识别为电阻，AR+其他封装不按封装猜测。CPU/CPU_FAN为连接器；RTCBAT为电池座；X/Y位号且Value含MHz为晶振；Value含NTC为NTC热敏电阻；LED为二极管。"
        }
        if {$k eq "MergePolicy"} {
            set v "分组键为类别:归一化封装:归一化值；三项完全相同才合并。位号拆分后逐项计数；已识别的等价单位先归一，未知型号/规格后缀原样留在键内，避免错误合并。"
        }
        if {$k eq "FootprintPolicy"} {
            set v "常见C0402/R0402/L0402/FB0402等只在归一化分组及合并BOM封装列中统一显示为0402；类别仍参与分组。原始完整封装名保存在“原始BOM”表；复杂封装不猜等效。"
        }
        if {$k eq "ValuePolicy"} {
            set v "电容统一为pF、电阻统一为Ohm、电感统一为nH；支持常见单位大小写、容差和耐压解析。NTC阻值与B值保留；晶振Value保留原规格；未识别后缀不删除。"
        }
        if {$k eq "SpecificationPolicy"} {
            set v "同组耐压取已知最大值、容差取已知最小值；只填补同组已有规格。若没有单一原器件同时满足合并规格，标记需选择器件，不虚构料号。电容材质不参与分组或优劣判断。"
        }
        if {$k eq "FilterPolicy"} {
            set v "过滤独立NC/DNP/DNI/DNE/NS、Option不装配、DNP属性及中文不装配标记；过滤测试点TP、定位点MARK/FID、安装孔HOLE/BOSS/MH。缺少值/封装、重复位号及Capture关键属性冲突的记录隔离，不计入可采购合并项。"
        }
        if {$k eq "WarningPolicy"} {
            set v "告警列出位号、问题、原因、当次处理、建议及源行。类别与封装不符、0Ω电阻用C封装、-04封装简码冲突、值/后缀无法解析等会告警；未知原文保留，不因普通解析告警而静默删除。"
        }
        if {$k eq "CaptureSectionPolicy"} {
            set v "同位号多单元先比较值、封装、装配状态等关键属性；关键差异则整个位号隔离并告警，辅助字段差异记录后合并空值，不重复计数。"
        }
        if {$k eq "BatchClassificationPolicy"} {
            set v "默认归为其他、同前缀连续编号且数量至少8个时，导出前逐组询问分类；本次选择只作用于本次导出，取消则不生成BOM。"
        }
        if {$k eq "InductorPolicy"} { set v "nH/uH统一归一为nH；电流额定值及数字/M规格组合参与分组并保留，不作为未知后缀告警。" }
        lappend summary [list [get $labels $k $k] $v]
    }
    lappend summary [list "原生BOM表头" [join $::bomtool::nativeHeaders \t]]
    lappend summary [list "Line Item Definition" $::bomtool::lineItemDefinition]
    lappend result [list "汇总" [list "项目" "内容"] $summary {}]
    return $result
}
