# SPDX-License-Identifier: GPL-3.0-only
# Run with Capture's bundled tclsh.exe; also works with stock Tcl 8.6.
source [file join [file dirname [info script]] .. .. autoload bomtoolMenu.tcl]
set ::passed 0
proc check {name script expected} {
    set actual [uplevel 1 $script]
    if {$actual ne $expected} { error "$name: expected <$expected>, got <$actual>" }
    incr ::passed
}
proc truth {name expression} {
    if {![uplevel 1 [list expr $expression]]} { error "$name failed" }
    incr ::passed
}
proc row {refs value footprint {option ""} {material ""} {line 2}} {
    return [dict create refs [::bomtool::refs $refs] ref $refs value $value footprint $footprint option $option material $material row $line]
}
proc vi {cat value} { return [::bomtool::valueInfo $cat $value] }
set tmp [file join [file dirname [info script]] test-output]
file mkdir $tmp

foreach {ref cat} {C1 cap PC1 cap CA1 cap CV1 cap R1 res PR1 res L1 ind PL1 ind FB1 ind CH1 ind CHK1 ind CHOKE1 ind D1 diode Q1 mos PQ1 mos QN1 mos U1 ic PU1 ic AU1 ic J1 conn JGPIO1 conn PCI1 conn PCIE1 conn SATA1 conn USB1 conn PFB1 ind T1 other COM1 conn LED1 diode RTCBAT1 batt} {
    check "category $ref" {::bomtool::category $ref} $cat
}
check case_value {dict get [vi cap 100nf] norm} 100000pF
check equivalent_value {dict get [vi cap 0.1uF/16V,X7R] norm} 100000pF
check embedded_decimal {dict get [vi res 4K7/F] norm} 4700Ohm
check tolerance_F {dict get [vi res 4K7/F] tolerance} 1
check tolerance_J {dict get [vi res 4.7K_J] tolerance} 5
check mega {dict get [vi res 1MOhm] norm} 1000000Ohm
check milli {dict get [vi res 1mOhm] norm} 0.001Ohm
check voltage_decimal {dict get [vi cap 1uF/6V3] voltage} 6.3
check zero {dict get [vi res 0_J] norm} 0
check opaque_part {dict get [vi ic NCV123] norm} NCV123
check material_alias {dict get [vi cap 22PF/50V,NPO] material} C0G
check power_not_erased {dict get [vi res 100R/2W] residual} 2W
check unknown_suffix {dict get [vi cap 100nF/ABC] norm} 100000pF|ABC
check footprint_simple {::bomtool::footprint C0402} 0402
check footprint_do_not_guess {::bomtool::footprint C0402_CUSTOM} C0402_CUSTOM
check ranges {::bomtool::refs {R1-R3; C1~C2}} {R1 R2 R3 C1 C2}
check bad_range {catch {::bomtool::refs R5-R1}} 1
foreach {ref value fp option reason} {
    R1 NC/10K R0402 {} NC R2 10K/NC R0402 {} NC R3 10K R0402 ns NC
    TP1 TP TP30_SMD {} TP J1 NCV123 SOT23 {} {}
    J2 2X5_NC10 HEADER_NCPIN10 {} {} BOSS4 NC/HOLE_6_1D3_73 PH_C6 {} {NC HOLE}
    H_CPU_SK1 HOLE NPHOLE_4d2mm {} HOLE MARK1 FIDUCIAL MARK_1 {} MARK
} {
    check "filter $ref" {::bomtool::exclusions $ref [row $ref $value $fp $option]} $reason
}
check dnp {::bomtool::exclusions R1 [dict merge [row R1 10k 0402] {dnp YES}]} NC
set r [::bomtool::normalize [row R1 0 C0402] R1]
check zero_warning {dict get $r warnings} WARN-0OHM-FOOTPRINT
check zero_key {dict get $r group_key} res:0402:0
set r [::bomtool::normalize [row R1 10k C0402] R1]
truth bad_res_warning {"WARN-CATEGORY-FOOTPRINT" in [dict get $r warnings]}
set r [::bomtool::normalize [row C1 10nF R0402] C1]
truth bad_cap_warning {"WARN-CATEGORY-FOOTPRINT" in [dict get $r warnings]}
set rows [list [row {R1,C1,L1} 0 0402] [row R2 0 C0402 {} {} 3] [row R3 0 R0402 {} {} 4]]
set stats [::bomtool::preprocess $rows [file join $tmp categories]]
check cross_category_isolation {dict get $stats groups} 3
set parts [::bomtool::explode [list [row C1 22pF C0402] [row C2 22pF/50V,NPO 0402 {} {} 3]]]
set spec [::bomtool::targetSpecs $parts]
check pf_material_ignored {dict get $spec material} {}
check missing_specs_inherit {dict get $spec voltage} 50
check observed_source {dict get $spec eligible} C2
set parts [::bomtool::explode [list [row C1 100nF/50V/X5R/5% 0402] [row C2 0.1uF/16V/X7R/1% C0402 {} {} 3]]]
set spec [::bomtool::targetSpecs $parts]
check combined_voltage {dict get $spec voltage} 50
check combined_tolerance {dict get $spec tolerance} 1
check combined_material_ignored {dict get $spec material} {}
check no_invented_part {dict get $spec status} NEEDS_SELECTION
check material_boundary {dict get [::bomtool::targetSpecs [::bomtool::explode [list [row C1 1nF/X5R 0402]]]] material} {}
check material_below_boundary {dict get [::bomtool::targetSpecs [::bomtool::explode [list [row C1 999pF/X7R 0402]]]] material} {}
check unranked_material {dict get [::bomtool::targetSpecs [::bomtool::explode [list [row C1 1uF/X8R 0402]]]] status} OBSERVED_MATCH

set path [file join $tmp quoted.csv]
::bomtool::writeCsv $path {Reference Value {PCB Footprint} Description} [list [list {C1,C2} 100nF C0402 "quoted \"part\",\nsecond line"]]
set read [::bomtool::readBom $path]
check csv_roundtrip {dict get [lindex $read 0] description} "quoted \"part\",\nsecond line"
check csv_quantity {llength [dict get [lindex $read 0] refs]} 2
check malformed_csv {catch {::bomtool::parseDelimited {"unclosed} ,}} 1
check trailing_csv_junk {catch {::bomtool::parseDelimited {"a"bad,b} ,}} 1
set rows [list [row R1 10K 0402] [row R1 20K 0402 {} {} 3]]
check duplicate_quarantine {dict get [::bomtool::preprocess $rows [file join $tmp duplicates]] groups} 0

check comparison_removed {llength [info commands ::bomtool::moduleB]} 0
check rule_loading_removed {llength [info commands ::bomtool::loadRules]} 0
check capture_required {catch {::bomtool::captureRows}} 1
set stats [::bomtool::preprocess [list [row C1 100nF/50V/X5R 0402] [row C2 100nf/16V/X7R C0402 {} {} 3]] [file join $tmp materials]]
check same_value_different_material {dict get $stats groups} 1
proc normalized {ref value fp} { return [::bomtool::normalize [row $ref $value $fp] $ref] }
check cpu_socket_category {dict get [normalized CPU1 SKL_S_CPU_LGA/CPU SKT_LGA1151] category} conn
check cpu_fan_category {dict get [normalized CPU_FAN1 H4X1-PO-WH h1x4_fan] category} conn
check ac_c_footprint_is_cap {dict get [normalized AC1 10uF C0402] category} cap
check ar_c_footprint_is_not_assumed_cap {dict get [normalized AR1 100nF C0603] category} other
check ar_r_footprint_is_res {dict get [normalized AR70 100K R0402] category} res
check ar_r_footprint_value_is_parsed {dict get [normalized AR70 100K R0402] norm} 100000Ohm
check ar_unknown_footprint_not_forced {dict get [normalized AR2 10K UDFN] category} other
check x_mhz_is_crystal {dict get [normalized X1 24MHz Xtal_2520] category} xtal
check y_mhz_is_crystal {dict get [normalized Y2 32.768MHz XTAL_3215] category} xtal
check x_without_mhz_not_assumed_crystal {dict get [normalized X3 24pF 0402] category} other
check crystal_value_preserved {dict get [normalized X1 24MHz Xtal_2520] norm} 24MHZ
check rtc_battery_holder_category {dict get [normalized RTCBAT1 85205-02701 bat2-2032] category} batt
set ntc [normalized PRT1 {100k (NTC)/B=4485} R0402]
check ntc_value_category {dict get $ntc category} res
check ntc_value_subtype {dict get $ntc subtype} ntc
check ntc_value_normalized {dict get $ntc norm} NTC|100000Ohm|B=4485
check ntc_value_no_false_warning {dict get $ntc warnings} {}
set family {}
for {set n 1} {$n <= 8} {incr n} { lappend family [row ZX$n IC SOT23] }
check regular_unknown_family_candidate {llength [::bomtool::categoryCandidates $family]} 1
check regular_unknown_family_refs {llength [lindex [lindex [::bomtool::categoryCandidates $family] 0] 1]} 8
set familyWithGap [lrange $family 0 6]
lappend familyWithGap [row ZX9 IC SOT23]
check noncontiguous_family_not_candidate {llength [::bomtool::categoryCandidates $familyWithGap]} 0
check auto_classified_family_not_candidate {llength [::bomtool::categoryCandidates [list [row CPU1 IC SOT23] [row CPU2 IC SOT23] [row CPU3 IC SOT23] [row CPU4 IC SOT23] [row CPU5 IC SOT23] [row CPU6 IC SOT23] [row CPU7 IC SOT23] [row CPU8 IC SOT23]]]} 0
set overrideRows [::bomtool::applyCategoryOverrides $family [dict create ZX1 conn]]
check category_override_applied {dict get [::bomtool::normalize [lindex $overrideRows 0] ZX1] category} conn
set inductor [normalized L20 0.22uH_36A/80A_0.82m IND]
check inductance_reference_category {dict get $inductor category} ind
check inductance_value_normalized {dict get $inductor norm} 220nH|36A/80A_0.82M
check inductance_value_parsed {dict get $inductor parsed} 1
check inductance_spec_suffix_preserved {dict get $inductor norm} 220nH|36A/80A_0.82M
check inductance_known_suffix_no_warning {dict get $inductor warnings} {}
check inductance_current_suffix_no_warning {dict get [normalized L22 0.47uH_5A IND] warnings} {}
check inductance_current_dcr_suffix_no_warning {dict get [normalized L23 1.0uH_7.5m_11A/17A IND] warnings} {}
check nanohenry_value_normalized {dict get [normalized L21 220nH IND] norm} 220nH
foreach {ref value fp expected} {
    CHK1 HSF2012F2SF-500T04 CHOKE_4P CHOKE|MODEL|HSF2012F2SF-500T04
    COM1 CONN-COM-66 DSUB9 CONN-COM-66
    C1 NC/2.2uF/16V C0402 2200000pF
    FB1 120ohm/100MHz,2.5A FB0603 BEAD|120Ohm|100000000Hz|2.5A
    LV1 30 L0603 BEAD|30Ohm
    LED1 g LED0603 LED|GREEN
    LED2 r LED0603 LED|RED
    L1 0.68uH/L444018 IND_SMD2 680nH|L444018
    R1 NTC_100K R0402 NTC|100000Ohm
    R2 4.7K-04 R0402 4700Ohm
} {
    set part [normalized $ref $value $fp]
    check "norm $value" {dict get $part norm} $expected
    check "no false warning $value" {dict get $part warnings} {}
}
check nc_voltage {dict get [normalized C1 NC/2.2uF/16V C0402] voltage} 16
check nc_excluded {dict get [normalized C1 NC/2.2uF/16V C0402] exclusions} NC
check nc_only_excluded {dict get [normalized C1 NC C0402] exclusions} NC
check nc_only_evidence {llength [::bomtool::ncEvidence [row C1 NC C0402]]} 1
check nc_only_no_value_warning {dict get [normalized C1 NC C0402] warnings} {}
set ncStats [::bomtool::preprocess [list [row C1 NC C0402]] [file join $tmp nc-only]]
check nc_only_filtered {dict get $ncStats excluded} 1
check nc_only_not_grouped {dict get $ncStats groups} 0
check nc_suffix {dict get [normalized R1 0R/NC R0402] norm} 0
check entity_nc {dict get [normalized C1 {&#x20;NC/2.2uF/16V} C0402] exclusions} NC
check model_nc_not_stripped {::bomtool::mountedValue NCV123} NCV123
check equivalent_bead_units {dict get [normalized FB1 120OHM/100000kHz,2500mA FB0603] norm} BEAD|120Ohm|100000000Hz|2.5A
truth current_preserved {[dict get [normalized FB1 120ohm/100MHz,2A FB0603] group_key] ne [dict get [normalized FB2 120ohm/100MHz,2.5A FB0603] group_key]}
truth frequency_preserved {[dict get [normalized FB1 120ohm/10MHz,2A FB0603] group_key] ne [dict get [normalized FB2 120ohm/100MHz,2A FB0603] group_key]}
truth unknown_frequency_not_invented {[dict get [normalized FB1 30 FB0603] group_key] ne [dict get [normalized FB2 30ohm/100MHz FB0603] group_key]}
truth ntc_isolation {[dict get [normalized R1 NTC_100K R0402] group_key] ne [dict get [normalized R2 100K R0402] group_key]}
truth led_color_isolation {[dict get [normalized LED1 g LED0603] group_key] ne [dict get [normalized LED2 r LED0603] group_key]}
truth bead_inductor_isolation {[dict get [normalized FB1 30 FB0603] group_key] ne [dict get [normalized L1 30nH L0603] group_key]}
truth model_isolation {[dict get [normalized CHK1 HSF2012F2SF-500T04 CHOKE] group_key] ne [dict get [normalized CHK2 HSF2012F2SF-500T05 CHOKE] group_key]}
truth package_conflict {"WARN-VALUE-FOOTPRINT" in [dict get [normalized R1 4.7K-04 R0603] warnings]}
truth package_hint_preserved {[dict get [normalized L1 0.68uH/L444018 IND] group_key] ne [dict get [normalized L2 0.68uH/L444020 IND] group_key]}
check connection_value_precedence {dict get [normalized C1 CON_DIP_V_3_0_20 HEADER] category} conn
set nsRow [row PR24 10K_J R0402 ns]
truth option_evidence {[string match *Option=ns* [join [::bomtool::ncEvidence $nsRow]]]}
truth nc_value_evidence {[string match *NC/0R* [join [::bomtool::ncEvidence [row R6340 NC/0R R0402]]]]}
check ordinary_value_no_nc_evidence {::bomtool::ncEvidence [row R1 10K_J R0402]} {}
check dual_evidence {llength [::bomtool::ncEvidence [row C1 NC/100nF C0402 ns]]} 2
truth explicit_dnp_evidence {[string match *DNP=YES* [join [::bomtool::ncEvidence [dict merge [row R1 10K R0402] {dnp YES}]]]]}
set cisRow [dict merge [row U1 IC SOIC8] {dnp YES original_dnp {} variant_nc 1 variant_nc_sources {{{Part Number} {Not Stuffed}}}}]
check cis_evidence_not_synthetic_dnp {llength [::bomtool::ncEvidence $cisRow]} 1
truth cis_property_recorded {[string match {*Part Number=Not Stuffed*} [join [::bomtool::ncEvidence $cisRow]]]}
check cis_still_excluded {::bomtool::exclusions U1 $cisRow} NC
check tp_has_no_nc_evidence {::bomtool::ncEvidence [row TP1 TP TP30_SMD]} {}
puts "PASS: $::passed assertions (Tcl [info patchlevel])"
