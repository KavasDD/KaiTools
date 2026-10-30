# SPDX-License-Identifier: GPL-3.0-only
# netlocator -- locate a net across every page of an OrCAD Capture design.
#
# Pick a wire on a schematic page, press Alt+F2, and a window lists every
# page where that net appears. Double-click a page row to open it and select
# all wires of that net on that page (equivalent to Select Entire Net, but the
# navigation to the right page is done for you).
#
# Needs Capture's own commands (GetSelectedObjects, SelectObjectById,
# RegisterAction, the Dbo* SWIG bindings). It does nothing in
# plain tclsh. Pure ASCII: Capture's Command Window decodes output as GBK.
#
# Install: from the Command Window,
#     source {d:/selfsoftware/autoload/netlocatorMenu.tcl}
#     netloc::install
# then restart Capture. Or just source it each session.

namespace eval ::netloc {
    variable version "1.2.6"
    # Resolve this file's own location once, while it is being sourced.
    # [info script] is only reliable here; called later it returns whatever
    # else is running. (Same reasoning as lceda2orcadMenu.tcl.)
    variable home [file dirname [file normalize [info script]]]
}

proc ::netloc::log {pText} {
    puts "netlocator: $pText"
    catch {flush stdout}
}

proc ::netloc::safeRegister {pLabel pName pEnabled pKey pAction pScope} {
    if {[catch {RegisterAction $pName $pEnabled $pKey $pAction $pScope} lErr]} {
        netloc::log "register $pLabel FAILED: $lErr"
        return 0
    }
    if {$pKey ne ""} {
        netloc::log "register $pLabel OK (key $pKey, scope $pScope)"
    } else {
        netloc::log "register $pLabel OK"
    }
    return 1
}

# ------------------------------------------------------------- small helpers ---

# CString -> plain Tcl string.
proc ::netloc::cstr {pCStr} {
    return [DboTclHelper_sGetConstCharPtr $pCStr]
}

# A DboNet's canonical (schematic-net) name. Two page-local DboNets belong to
# the same electrical net when their schematic net names match; that is what we
# group on, not the page-local GetNetName, so an aliased net on another page is
# not missed.
proc ::netloc::netNameOf {pNet {pCStr ""}} {
    set lNull NULL
    if {$pCStr eq ""} {
        set pCStr [DboTclHelper_sMakeCString]
    }
    # Prefer the schematic net's name.
    if {![catch {$pNet GetSchematicNet} lSchNet] && $lSchNet ne $lNull} {
        if {![catch {$lSchNet GetName $pCStr}]} {
            set lName [netloc::cstr $pCStr]
            if {$lName ne ""} { return $lName }
        }
    }
    # Fall back to the page-local net name.
    set lStatus [DboState]
    catch {$pNet GetNetName $lStatus $pCStr}
    catch {$lStatus -delete}
    return [netloc::cstr $pCStr]
}

# --------------------------------------------------------------- selection ---

# The wire currently selected on the active schematic page, or "" plus a reason
# left in ::netloc::lastError.
variable ::netloc::lastError ""

proc ::netloc::selectedWire {} {
    set ::netloc::lastError ""
    # IsSchematicViewActive is not exported by some Capture 16.6 builds.
    # When it is available use it; otherwise GetSelectedObjects is the portable test.
    if {[llength [info commands IsSchematicViewActive]]} {
        if {[catch {IsSchematicViewActive} lActive] || $lActive != 1} {
            set ::netloc::lastError "open a schematic page first"
            return ""
        }
    } elseif {![llength [info commands GetSelectedObjects]]} {
        set ::netloc::lastError "Capture selection API is unavailable"
        return ""
    }
    if {[catch {GetSelectedObjects} lSel]} {
        set ::netloc::lastError "could not read the current selection"
        return ""
    }
    if {[llength $lSel] == 0} {
        set ::netloc::lastError "select one wire of the net, then press the key again"
        return ""
    }
    # Find the first object that answers GetNet -- that is a wire. Other
    # selectable things (parts, text) do not, so a mixed selection still works.
    set lStatus [DboState]
    foreach lObj $lSel {
        if {![catch {$lObj GetNet $lStatus} lNet] && $lNet ne "NULL"} {
            catch {$lStatus -delete}
            return $lObj
        }
    }
    catch {$lStatus -delete}
    set ::netloc::lastError "the selection has no wire -- click a wire (not a pin or part)"
    return ""
}

# Wire -> canonical net name, or "".
proc ::netloc::netOf {pWire} {
    set lStatus [DboState]
    if {[catch {$pWire GetNet $lStatus} lNet] || $lNet eq "NULL"} {
        catch {$lStatus -delete}
        return ""
    }
    catch {$lStatus -delete}
    return [netloc::netNameOf $lNet]
}

proc ::netloc::wireName {pWire {pCStr ""}} {
    if {$pCStr eq ""} {
        set pCStr [DboTclHelper_sMakeCString]
    }
    if {![catch {$pWire GetNetName $pCStr}]} {
        return [netloc::cstr $pCStr]
    }
    return ""
}

# ----------------------------------------------------------------- scanning ---

# Walk every schematic and page of the active design. Returns a list of hits,
# each {schematicName pageName wireCount}, for pages carrying pNetName.
# Grouped and counted per page.
proc ::netloc::scan {pNetName} {
    netloc::log "scan begin for '$pNetName'"
    set lNull NULL
    set lHits {}

    set lSession $::DboSession_s_pDboSession
    DboSession -this $lSession
    set lDesign [$lSession GetActiveDesign]
    if {$lDesign == $lNull} { return {} }

    set lStatus [DboState]
    set lSchIter [$lDesign NewViewsIter $lStatus $::IterDefs_SCHEMATICS]
    set lView [$lSchIter NextView $lStatus]
    while {$lView != $lNull} {
        set lSch [DboViewToDboSchematic $lView]
        set lSchName [netloc::nameOfObj $lSch]

        set lPageStatus [DboState]
        set lPageIter [$lSch NewPagesIter $lPageStatus]
        set lPage [$lPageIter NextPage $lPageStatus]
        while {$lPage != $lNull} {
            set lCount [netloc::countNetOnPage $lPage $pNetName]
            if {$lCount > 0} {
                lappend lHits [list $lSchName [netloc::nameOfObj $lPage] $lCount]
            }
            set lPage [$lPageIter NextPage $lPageStatus]
        }
        catch {delete_DboSchematicPagesIter $lPageIter}
        catch {$lPageStatus -delete}

        set lView [$lSchIter NextView $lStatus]
    }
    catch {delete_DboLibViewsIter $lSchIter}
    catch {$lStatus -delete}
    DboTclHelper_sReleaseAllCreatedPtrs
    set lHits [netloc::sortHits $lHits]
    netloc::log "scan complete for '$pNetName': [llength $lHits] page(s)"
    return $lHits
}

proc ::netloc::sortHits {pHits} {
    return [lsort -dictionary -index 1 $pHits]
}

proc ::netloc::showSchematicName {pHits} {
    set lNames {}
    foreach lHit $pHits {
        set lName [lindex $lHit 0]
        if {[lsearch -exact $lNames $lName] < 0} {
            lappend lNames $lName
            if {[llength $lNames] > 1} { return 1 }
        }
    }
    return 0
}

# Object's name (page or schematic), as a plain string.
proc ::netloc::nameOfObj {pObj} {
    set lCStr [DboTclHelper_sMakeCString]
    catch {$pObj GetName $lCStr}
    return [netloc::cstr $lCStr]
}

# How many nets on this page match pNetName by canonical name.
proc ::netloc::countNetOnPage {pPage pNetName} {
    set lStatus [DboState]
    set lCStr [DboTclHelper_sMakeCString]
    set lNull NULL
    set lCount 0
    set lError ""
    if {[catch {
        set lWireIter [$pPage NewWiresIter $lStatus]
        set lWire [$lWireIter NextWire $lStatus]
        while {$lWire ne $lNull} {
            if {[netloc::wireName $lWire $lCStr] eq $pNetName} { incr lCount }
            set lWire [$lWireIter NextWire $lStatus]
        }
    } lError]} {}
    if {[info exists lWireIter]} { catch {delete_DboPageWiresIter $lWireIter} }
    catch {$lStatus -delete}
    if {$lError ne ""} {
        netloc::log "wire scan failed for '$pNetName': $lError"
        return 0
    }
    return $lCount
}

# ------------------------------------------------------------- navigation ---

# Open the named page and select every wire of pNetName on it.
proc ::netloc::goto {pSchName pPageName pNetName} {
    netloc::log "open request: $pSchName / $pPageName / '$pNetName'"
    set lNull NULL
    set lSession $::DboSession_s_pDboSession
    DboSession -this $lSession
    set lDesign [$lSession GetActiveDesign]
    if {$lDesign == $lNull} { return 0 }

    # Find the page object by name.
    set lStatus [DboState]
    set lSchCStr [DboTclHelper_sMakeCString $pSchName]
    set lSch [$lDesign GetSchematic $lSchCStr $lStatus]
    if {$lSch == $lNull} {
        puts "netlocator: schematic '$pSchName' not found"
        catch {$lStatus -delete}
        return 0
    }
    set lPageCStr [DboTclHelper_sMakeCString $pPageName]
    set lPage [$lSch GetPage $lPageCStr $lStatus]
    catch {$lStatus -delete}
    if {$lPage == $lNull} {
        puts "netlocator: page '$pPageName' not found"
        return 0
    }

    set lIds [netloc::netWireIds $lPage $pNetName]
    if {![llength $lIds]} {
        puts "netlocator: no wires for '$pNetName' on '$pPageName'"
        return 0
    }
    set lModernSelector [expr {
        [llength [info commands sch::dbSelectObjectByIdEx]] ||
        [llength [info commands sch::dbSelectObjectById]]
    }]
    if {!$lModernSelector} {
        netloc::openPageByMenu $pSchName $pPageName
    }
    catch {UnSelectAll}
    if {[llength [info commands sch::dbSelectObjectByIdEx]]} {
        netloc::log "selector: sch::dbSelectObjectByIdEx"
    } elseif {[llength [info commands sch::dbSelectObjectById]]} {
        netloc::log "selector: sch::dbSelectObjectById"
    } else {
        netloc::log "selector: legacy SelectObjectById"
    }
    set lFirst 1
    foreach lId $lIds {
        # The sch::* selector has an explicit shouldOpenTab flag. Open the
        # target page on the first wire, then keep subsequent selections there.
        set lOpen [expr {$lFirst ? 1 : 0}]
        if {[llength [info commands sch::dbSelectObjectByIdEx]]} {
            if {[catch {sch::dbSelectObjectByIdEx $lId $lOpen 0}]} {
                catch {SelectObjectById $lId}
            }
        } elseif {[llength [info commands sch::dbSelectObjectById]]} {
            if {[catch {sch::dbSelectObjectById $lId $lOpen}]} {
                catch {SelectObjectById $lId}
            }
        } else {
            catch {SelectObjectById $lId}
        }
        set lFirst 0
    }
    DboTclHelper_sReleaseAllCreatedPtrs
    netloc::log "selected [llength $lIds] wire(s) on $pPageName"
    return 1
}

# OrCAD Capture 17.4 does not expose the newer sch::dbSelectObjectById API.
# Drive Capture's own View > Next Page command until the requested page is
# active, verifying the result after every step.
proc ::netloc::openPageByMenu {pSchName pPageName} {
    # Official OrCAD Capture command: unlike SelectPMItem (which only changes
    # the project-manager selection), OPage actually opens the schematic view.
    if {[llength [info commands OPage]]} {
        if {![catch {OPage $pSchName $pPageName} lErr]} {
            catch {update}
            netloc::log "page open OPage $pSchName/$pPageName: OK"
            return 1
        }
        netloc::log "page open OPage FAILED for '$pSchName/$pPageName': $lErr"
    }
    if {![llength [info commands SelectPMItem]]} {
        netloc::log "page switch unavailable: OPage/SelectPMItem missing"
        return 0
    }
    set lStart ""
    if {[llength [info commands GetActivePage]]} {
        catch {
            set lPage [GetActivePage]
            if {$lPage ne "" && $lPage ne "NULL"} { set lStart [netloc::nameOfObj $lPage] }
        }
    }
    if {$lStart eq $pPageName} {
        netloc::log "page switch $pPageName: already active"
        return 1
    }
    set lPath "$pSchName/$pPageName"
    if {[catch {SelectPMItem $lPath} lErr]} {
        netloc::log "page switch SelectPMItem FAILED for '$lPath': $lErr"
        return 0
    }
    catch {update}
    if {[llength [info commands GetActivePage]] && ![catch {set lPage [GetActivePage]}] && $lPage ne "" && $lPage ne "NULL"} {
        set lNow [netloc::nameOfObj $lPage]
        if {$lNow eq $pPageName} {
            netloc::log "page switch $lStart -> $pPageName: OK"
            return 1
        }
        netloc::log "page switch requested '$lPath', active page is '$lNow'"
    }
    # SelectPMItem can succeed while the result dialog owns focus, so a
    # GetActivePage verification may legitimately be unavailable here.
    netloc::log "page switch requested '$lPath'"
    return 1
}

proc ::netloc::debugPageApi {} {
    puts "netlocator: DEBUG OPage=[llength [info commands OPage]] GetActivePage=[llength [info commands GetActivePage]] SelectPMItem=[llength [info commands SelectPMItem]] GetActivePM=[llength [info commands GetActivePM]]"
    if {[llength [info commands GetActivePage]]} {
        if {![catch {set lPage [GetActivePage]}]} {
            puts "netlocator: DEBUG active page=[netloc::nameOfObj $lPage]"
        }
    }
    foreach lCmd [info commands *Page*] {
        puts "netlocator: DEBUG command=$lCmd"
    }
}

# Best-effort page open. The wrapper takes numeric ids we do not reliably have,
# so the primary path is: iterate the PM pages, match by name, open via the
# schematic occurrence the iterator hands back.
proc ::netloc::openPage {pSch pPage} {
    set lPageName [netloc::nameOfObj $pPage]
    set lSchName [netloc::nameOfObj $pSch]

    if {![llength [info commands GetActivePM]]} { return }
    if {[catch {GetActivePM} lPM] || $lPM eq "" || $lPM eq "NULL"} { return }

    # COrPMPageIter_NextPage fills a schematic-occurrence out-parameter we can
    # pass to the open call. Names come from the PM tree, so match on those.
    if {[catch {
        set lIter [COrPMPageIter_sNewPMPageIter $lPM $::COrCapPMIter_ALL 0]
        set lSchOcc 0
        set lPmPage [$lIter NextPage lSchOcc]
        while {$lPmPage ne "" && $lPmPage ne "NULL" && $lPmPage != 0} {
            # The PM page object exposes name accessors via the same GetName.
            set lNm ""
            catch {set lNm [netloc::nameOfObj $lPmPage]}
            if {$lNm eq $lPageName} {
                set lOpened 0
                if {![catch {
                    set lPageId [$lPmPage GetPageID]
                    COrSpecificProjectManagerWrapper_OpenSchPage $lPageId $lSchOcc
                }]} {
                    set lOpened 1
                } elseif {![catch {
                    set lPageId [$lPmPage GetPageID]
                    COrSpecificProjectManagerWrapper_OpenSchPage $lPageId
                }]} {
                    set lOpened 1
                } elseif {![catch {
                    COrSpecificProjectManagerWrapper_OpenSchPage $lPmPage
                }]} {
                    set lOpened 1
                }
                if {$lOpened} {
                    netloc::log "page open $lSchName/$lPageName: OK"
                } else {
                    netloc::log "page open $lSchName/$lPageName: FAILED"
                }
                break
            }
            set lSchOcc 0
            set lPmPage [$lIter NextPage lSchOcc]
        }
        catch {delete_COrPMPageIter $lIter}
    } lErr]} {
        # No wrapper on this build: SelectObjectById cross-probes to the page on
        # its own, so silently rely on that.
    }
}

# Ids of every wire whose net matches pNetName on this page.
proc ::netloc::netWireIds {pPage pNetName} {
    set lIds {}
    set lStatus [DboState]
    set lCStr [DboTclHelper_sMakeCString]
    set lNull NULL
    catch {
        set lWireIter [$pPage NewWiresIter $lStatus]
        set lWire [$lWireIter NextWire $lStatus]
        while {$lWire ne $lNull} {
            if {[netloc::wireName $lWire $lCStr] eq $pNetName && ![catch {$lWire GetId $lStatus} lId]} {
                lappend lIds $lId
            }
            set lWire [$lWireIter NextWire $lStatus]
        }
        delete_DboPageWiresIter $lWireIter
    }
    catch {$lStatus -delete}
    return $lIds
}

proc ::netloc::selectEntireNet {args} {
    netloc::log "Select Entire Net requested"
    set lWire [netloc::selectedWire]
    if {$lWire eq ""} {
        netloc::log $::netloc::lastError
        return 0
    }
    if {![llength [info commands GetActivePage]] ||
        [catch {GetActivePage} lPage] || $lPage eq "" || $lPage eq "NULL"} {
        netloc::log "could not get the active schematic page"
        return 0
    }
    set lNetName [netloc::wireName $lWire]
    if {$lNetName eq ""} {
        netloc::log "could not read the selected wire's net name"
        return 0
    }
    set lIds [netloc::netWireIds $lPage $lNetName]
    if {![llength $lIds]} {
        netloc::log "no wires found for '$lNetName' on the active page"
        return 0
    }
    if {[catch {UnSelectAll} lError]} {
        netloc::log "could not clear the current selection: $lError"
        return 0
    }
    foreach lId $lIds {
        if {[catch {SelectObjectById $lId} lError]} {
            netloc::log "could not select wire $lId: $lError"
            return 0
        }
    }
    DboTclHelper_sReleaseAllCreatedPtrs
    netloc::log "selected [llength $lIds] wire(s) on the active page"
    return 1
}

# Diagnostic command for the Capture command window. It does not change the
# design; it prints every page and the net names exposed by DboPageNetsIter.
proc ::netloc::debugScan {pWanted} {
    set lStatus [DboState]
    set lCStr [DboTclHelper_sMakeCString]
    set lNull NULL
    set lSession $::DboSession_s_pDboSession
    DboSession -this $lSession
    set lDesign [$lSession GetActiveDesign]
    if {$lDesign eq $lNull} { puts "netlocator: DEBUG no active design"; return }
    set lSchIter [$lDesign NewViewsIter $lStatus $::IterDefs_SCHEMATICS]
    set lView [$lSchIter NextView $lStatus]
    while {$lView ne $lNull} {
        set lSch [DboViewToDboSchematic $lView]
        set lSchName [netloc::nameOfObj $lSch]
        set lPageIter [$lSch NewPagesIter $lStatus]
        set lPage [$lPageIter NextPage $lStatus]
        while {$lPage ne $lNull} {
            set lPageName [netloc::nameOfObj $lPage]
            set lNames {}
            catch {
                set lWireIter [$lPage NewWiresIter $lStatus]
                set lWire [$lWireIter NextWire $lStatus]
                while {$lWire ne $lNull} {
                    set lNm [netloc::wireName $lWire $lCStr]
                    if {$lNm ne "" && [lsearch -exact $lNames $lNm] < 0} {
                        lappend lNames $lNm
                    }
                    set lWire [$lWireIter NextWire $lStatus]
                }
                delete_DboPageWiresIter $lWireIter
            }
            puts "netlocator: DEBUG $lSchName/$lPageName nets=[join $lNames {, }] wanted='$pWanted' match=[expr {[lsearch -exact $lNames $pWanted] >= 0}]"
            set lPage [$lPageIter NextPage $lStatus]
        }
        catch {delete_DboSchematicPagesIter $lPageIter}
        set lView [$lSchIter NextView $lStatus]
    }
    catch {delete_DboLibViewsIter $lSchIter}
    catch {$lStatus -delete}
    puts "netlocator: DEBUG complete"
}

# ------------------------------------------------------------------ Tk form ---

# Load Tk, hiding the stray "." root the same way Cadence's own scripts do.
proc ::netloc::tk {} {
    # Capture 16.6 commonly ships Tk 8.5 while newer releases ship 8.6.
    if {[catch {package require Tk} lErr]} {
        netloc::log "Tk unavailable: $lErr"
        return 0
    }
    catch {update}
    catch {wm withdraw .}
    return 1
}

# Current results, keyed by tree row id: rowId -> {schName pageName netName}.
variable ::netloc::rows

proc ::netloc::formatHit {pHit pShowSchematic} {
    lassign $pHit lSch lPage lCount
    if {$pShowSchematic} {
        return "$lSch / $lPage  ($lCount)"
    }
    return "$lPage  ($lCount)"
}

proc ::netloc::show {pNetName pHits} {
    netloc::log "show result window for '$pNetName' ([llength $pHits] page(s))"
    if {![netloc::tk]} {
        puts "netlocator: Tk unavailable. '$pNetName' appears on:"
        set lShowSchematic [netloc::showSchematicName $pHits]
        foreach lHit $pHits {
            puts "  [netloc::formatHit $lHit $lShowSchematic]"
        }
        return
    }

    set lForm .netloc
    if {![winfo exists $lForm]} {
        if {[catch {package require capAppUtils} lErr]} {
            toplevel $lForm
        } else {
            capAppUtils::capTopLevel $lForm
        }
        frame $lForm.results
        set lTree [listbox $lForm.results.tv -height 14 -width 76 \
            -font {{Segoe UI} 10} -background white -foreground #202020 \
            -selectbackground #2878C8 -selectforeground white \
            -highlightthickness 0 -exportselection 0 -selectmode browse \
            -yscrollcommand [list $lForm.results.scroll set]]
        scrollbar $lForm.results.scroll -orient vertical -command [list $lTree yview]
        $lTree configure -yscrollcommand [list $lForm.results.scroll set]
        grid $lTree -row 0 -column 0 -sticky nsew
        grid $lForm.results.scroll -row 0 -column 1 -sticky ns
        grid rowconfigure $lForm.results 0 -weight 1
        grid columnconfigure $lForm.results 0 -weight 1

        ttk::label $lForm.hdr -anchor w
        ttk::label $lForm.hint \
            -text "Select a page, then open it to highlight the matching wires." \
            -anchor w
        ttk::button $lForm.open -text "Open selected page" \
            -command [list ::netloc::onRowActivate $lTree]
        ttk::button $lForm.close -text "Close" -command [list wm withdraw $lForm]
        grid $lForm.hdr -row 0 -column 0 -columnspan 2 -sticky we -padx 14 -pady {14 4}
        grid $lForm.results -row 1 -column 0 -columnspan 2 -sticky nsew -padx 14 -pady 4
        grid $lForm.hint -row 2 -column 0 -columnspan 2 -sticky w -padx 14 -pady {4 10}
        grid $lForm.open -row 3 -column 0 -sticky e -padx 14 -pady {0 14}
        grid $lForm.close -row 3 -column 1 -sticky e -padx {0 14} -pady {0 14}

        grid rowconfigure $lForm 1 -weight 1
        grid columnconfigure $lForm 0 -weight 1
        wm geometry $lForm 620x430
        wm minsize $lForm 520 320
        wm attributes $lForm -topmost 1
        wm protocol $lForm WM_DELETE_WINDOW [list wm withdraw $lForm]
        bind $lTree <Double-1> [list ::netloc::onRowActivate $lTree]
        bind $lTree <Return>   [list ::netloc::onRowActivate $lTree]
        bind $lForm <Return>   [list ::netloc::onRowActivate $lTree]
        bind $lForm <Escape>   [list wm withdraw $lForm]
    }
    wm title $lForm "Signal\u4e00\u952e\u5168\u7f51\u7edc\u9ad8\u4eae: $pNetName"

    set lShowSchematic [netloc::showSchematicName $pHits]
    set lTree $lForm.results.tv
    $lForm.hdr configure -text "Net '$pNetName' appears on [llength $pHits] page(s). Double-click a page to locate its wires."

    # Reuse the same native window and refresh its rows for each selected net.
    $lTree delete 0 end
    array unset ::netloc::rows
    array set ::netloc::rows {}
    set lRow 0
    foreach lHit [netloc::sortHits $pHits] {
        lassign $lHit lSch lPage lCount
        $lTree insert end [netloc::formatHit $lHit $lShowSchematic]
        set ::netloc::rows($lRow) [list $lSch $lPage $pNetName]
        incr lRow
    }
    if {[$lTree size] > 0} {
        $lTree selection set 0
        $lTree activate 0
    }

    update idletasks
    wm attributes $lForm -topmost 1
    wm deiconify $lForm
    raise $lForm
    focus $lTree
}

proc ::netloc::showStatus {pTitle pText} {
    netloc::log "popup: $pTitle - $pText"
    if {![netloc::tk]} { return }
    set lForm .netloc_status
    if {![winfo exists $lForm]} {
        toplevel $lForm
        label $lForm.msg -anchor w -justify left -padx 12 -pady 12
        ttk::button $lForm.ok -text OK -width 10 \
            -command [list wm withdraw $lForm]
        pack $lForm.msg -fill both -expand 1
        pack $lForm.ok -pady {0 10}
        wm protocol $lForm WM_DELETE_WINDOW [list wm withdraw $lForm]
        bind $lForm <Escape> [list wm withdraw $lForm]
    }
    wm title $lForm $pTitle
    $lForm.msg configure -text $pText
    update idletasks
    wm deiconify $lForm
    raise $lForm
}

proc ::netloc::onRowActivate {pTree} {
    set lRow [$pTree curselection]
    if {$lRow eq "" || ![info exists ::netloc::rows($lRow)]} { return }
    lassign $::netloc::rows($lRow) lSch lPage lNet
    netloc::goto $lSch $lPage $lNet
}

# --------------------------------------------------------------- entry point ---

proc ::netloc::onHotkey {args} {
    netloc::log "Locate requested"
    set lWire [netloc::selectedWire]
    if {$lWire eq ""} {
        netloc::log $::netloc::lastError
        netloc::showStatus "Locate Selected Net" $::netloc::lastError
        return
    }
    set lNet [netloc::netOf $lWire]
    if {$lNet eq ""} {
        netloc::log "could not read the net name of the selected wire"
        netloc::showStatus "Locate Selected Net" "Could not read the selected wire's net name."
        return
    }
    netloc::log "selected net '$lNet'; scanning design"
    set lHits [netloc::scan $lNet]
    if {![llength $lHits]} {
        netloc::log "net '$lNet' found on no page"
        netloc::showStatus "Locate Selected Net" "Net '$lNet' was not found on any schematic page."
        return
    }
    netloc::log "found [llength $lHits] page(s); opening result window"
    netloc::show $lNet $lHits
}

# Menu handler: page callbacks get "pPage pOcc", design callbacks get "pLib",
# so {args} absorbs whatever arity the context uses.
proc ::netloc::menuRun {args} {
    netloc::invoke "Locate Selected Net" ::netloc::onHotkey
}

proc ::netloc::signalRun {args} {
    netloc::invoke "Show Signal Name" ::netloc::signalRunImpl
}

proc ::netloc::signalRunImpl {} {
    netloc::log "Show Signal Name requested"
    set lWire [netloc::selectedWire]
    if {$lWire eq ""} {
        netloc::log $::netloc::lastError
        netloc::showStatus "Signal Name" $::netloc::lastError
        return
    }
    set lNet [netloc::netOf $lWire]
    if {$lNet eq ""} {
        netloc::log "selected object has no readable net"
        netloc::showStatus "Signal Name" "The selected object has no readable net name."
        return
    }
    netloc::log "signal/net name: '$lNet'"
    netloc::showStatus "Signal Name" $lNet
}

proc ::netloc::enabled {} {
    return true
}

# ------------------------------------------------------------------ install ---

proc ::netloc::findSpbData {} {
    if {[info exists ::env(HOME)]
     && [file isdirectory [file join $::env(HOME) cdssetup]]} {
        return [file normalize $::env(HOME)]
    }
    foreach lDrive {C: D: E:} {
        foreach lName {orcad/Cadence/SPB_Data Cadence/SPB_Data} {
            set lP "$lDrive/$lName"
            if {[file isdirectory [file join $lP cdssetup]]} { return $lP }
        }
    }
    return ""
}

proc ::netloc::install {{pDest ""}} {
    set lSrc [file join $::netloc::home [file tail [info script]]]
    if {![file exists $lSrc]} {
        set lSrc [file join $::netloc::home netlocatorMenu.tcl]
    }
    if {![file exists $lSrc]} {
        puts "netlocator: cannot find my own file under $::netloc::home"
        return 0
    }

    if {$pDest ne ""} {
        set lDest $pDest
    } else {
        set lSpb [netloc::findSpbData]
        if {$lSpb eq ""} {
            puts "netlocator: cannot find Cadence's SPB_Data folder."
            puts "netlocator: pass it explicitly, e.g."
            puts "  netloc::install {C:/orcad/Cadence/SPB_Data/cdssetup/OrCAD_Capture/tclscripts/capAutoLoad}"
            return 0
        }
        puts "netlocator: SPB_Data is $lSpb"
        set lDest [file join $lSpb cdssetup OrCAD_Capture tclscripts capAutoLoad]
    }

    if {[catch {file mkdir $lDest} lErr]} {
        puts "netlocator: cannot create $lDest: $lErr"
        return 0
    }
    set lTarget [file join $lDest netlocatorMenu.tcl]
    if {[file normalize $lSrc] eq [file normalize $lTarget]} {
        puts "netlocator: already installed at $lTarget"
        return 1
    }
    if {[catch {file copy -force $lSrc $lTarget} lErr]} {
        puts "netlocator: copy failed: $lErr"
        return 0
    }
    puts "netlocator: installed $lTarget"
    puts "netlocator: restart Capture; Alt+F2 locates the selected net, Alt+F3 selects it on the current page"
    return 1
}

# Capture often reports callback errors only as a silent menu no-op. Always
# catch at this boundary so the Command Window contains the real failure.
proc ::netloc::invoke {pLabel pCommand args} {
    netloc::log "$pLabel callback begin"
    if {[catch {uplevel 1 [linsert $args 0 $pCommand]} lErr lOpts]} {
        netloc::log "$pLabel callback FAILED: $lErr"
        if {[dict exists $lOpts -errorinfo]} {
            netloc::log [dict get $lOpts -errorinfo]
        }
        return 0
    }
    netloc::log "$pLabel callback end"
    return 1
}

# ------------------------------------------------------------- registration ---

# Use stable action IDs and Capture's documented "Schematic" keyboard scope.
proc netlocEnabled {} { return [::netloc::enabled] }
proc netlocLocate {args} { ::netloc::invoke "Locate Net (Alt+F2)" ::netloc::onHotkey {*}$args }
# Remove registrations from a prior source/reload before binding the new IDs.
catch {UnregisterAction "Locate Net (Alt+F2)"}
catch {UnregisterAction "netlocLocateNetAltF2"}
::netloc::safeRegister "Locate Net (Alt+F2)" "netlocLocateNetAltF2" netlocEnabled "Alt+F2" netlocLocate Schematic
proc netlocSelectEntireNet {args} { ::netloc::invoke "Select Entire Net (Alt+F3)" ::netloc::selectEntireNet {*}$args }
catch {UnregisterAction "Select Entire Net (Alt+F3)"}
catch {UnregisterAction "netlocSelectEntireNetAltF3"}
::netloc::safeRegister "Select Entire Net (Alt+F3)" "netlocSelectEntireNetAltF3" netlocEnabled "Alt+F3" netlocSelectEntireNet Schematic

# Load banner: the only reliable proof Capture actually scanned this file. If
# you never see this line, the folder is not on the autoload search path --
# source the file by hand instead.
netloc::log "$::netloc::version: loaded (Alt+F2 locates a net; Alt+F3 selects it on the current page)"
