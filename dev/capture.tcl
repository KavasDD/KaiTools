# SPDX-License-Identifier: GPL-3.0-only
# ---------------------------------------------------------------------------
# Capture layer -- data locations, XML2OLB import, placement, menu.
#
# Everything above this line is standalone TCL and runs in tclsh. Everything
# below needs Capture's own commands (XMATIC_XML2OLB, PlacePartEx,
# RegisterAction).
# ---------------------------------------------------------------------------

# Single source of truth for the version. dist\build.ps1 greps this line and
# stamps the value into install.cmd, so the installer cannot disagree with what
# it installs. Bump it when changing behaviour worth telling apart across
# machines.
set ::lceda2orcadVersion "1.4.5"

# Data lives beside this script: cache/ for the fetched JSON, out/ for the
# generated XML and the .olb. The autoload folder under SPB_Data is user
# writable, so no separate location is needed.
# [info script] is only this file while it is being sourced -- called later from
# the Command Window it returns whatever else is running. So resolve it once,
# here, and keep it.
set ::lceda2orcadHome [file dirname [file normalize [info script]]]

proc lceda2orcadDataDir {} {
    if {[info exists ::env(LCEDA2ORCAD_DATA)]} { return $::env(LCEDA2ORCAD_DATA) }
    return [file join $::lceda2orcadHome lceda2orcad-data]
}

set ::lcedaOlb [file join [lceda2orcadDataDir] out lceda.olb]
set ::lcedaXml [file join [lceda2orcadDataDir] out lceda.xml]
set ::lceda::dataDir [lceda2orcadDataDir]

proc lceda2orcadOlbPath {} {
    set lDir [file dirname $::lcedaOlb]
    set lName [file tail $::lcedaOlb]
    foreach lPath [glob -nocomplain -directory $lDir -types f *] {
        if {[string equal -nocase [file tail $lPath] $lName]} {
            return $lPath
        }
    }
    return $::lcedaOlb
}

# Rebuild the XML from every part in the cache. XML2OLB writes a whole library
# at a time, so a new part means regenerating all of them; the cache makes that
# free after the first fetch.
# Sets ::lcedaPkgs (package names) and ::lcedaByLcsc (code -> package name).
proc lceda2orcadBuildXml {} {
    set lParts [lceda::cachedParts]
    if {![llength $lParts]} {
        puts "lceda2orcad: cache is empty, nothing to build"
        return 0
    }
    # Never unload or replace a library that an interactive placement command
    # or a placed instance may still reference in this Capture session.
    if {![info exists ::lceda2orcadBuildSerial]} {set ::lceda2orcadBuildSerial 0}
    incr ::lceda2orcadBuildSerial
    set ::lcedaOlb [file join [file dirname $::lcedaOlb] "lceda_[pid]_[clock clicks -milliseconds]_$::lceda2orcadBuildSerial.olb"]
    set lSyms {}
    set ::lcedaPkgs {}
    array unset ::lcedaByLcsc
    array unset ::lcedaUnitsByPackage
    foreach lCode $lParts {
        if {[catch {lceda::loadCached $lCode} lRes]} {
            puts "lceda2orcad: skipping $lCode: $lRes"
            continue
        }
        if {[catch {lceda::parseSymbol $lRes} lSym]} {
            puts "lceda2orcad: skipping $lCode: parse failed: $lSym"
            continue
        }
        set lName [dict get $lSym name]
        if {$lName eq ""} {
            puts "lceda2orcad: skipping $lCode: no part name"
            continue
        }
        lappend lSyms $lSym
        lappend ::lcedaPkgs $lName
        set ::lcedaByLcsc($lCode) $lName
        set units [list ""]
        if {[dict exists $lSym sections]} {
            set units {};set index 0
            foreach unit [dict get $lSym sections] {lappend units [lceda::sectionSuffix $index];incr index}
        }
        set ::lcedaUnitsByPackage($lName) $units
    }
    if {![llength $lSyms]} {
        puts "lceda2orcad: no usable parts in the cache"
        return 0
    }

    lassign [lceda::buildLibXml $lSyms $::lcedaOlb] lXml lReports
    file mkdir [file dirname $::lcedaXml]
    set lH [open $::lcedaXml w]
    fconfigure $lH -encoding utf-8 -translation lf
    puts -nonewline $lH $lXml
    close $lH

    # Report only what needed fixing; a clean part says nothing.
    dict for {lCode lRep} $lReports {
        set lMsg {}
        if {[dict get $lRep moved] > 0} {
            lappend lMsg "[dict get $lRep moved]/[dict get $lRep total] pins snapped to grid"
        }
        set lColl [dict get $lRep collisions]
        if {[llength $lColl]} {
            lappend lMsg "[llength $lColl] pin collision(s) shifted aside"
        }
        if {[dict get $lRep renamed] > 0} {
            lappend lMsg "[dict get $lRep renamed] duplicate pin name(s) suffixed"
        }
        if {[llength $lMsg]} { puts "lceda2orcad: $lCode -- [join $lMsg {; }]" }
    }
    puts "lceda2orcad: wrote [llength $lSyms] package(s) to $::lcedaXml"
    return 1
}

# Explicit user-requested removal helper only. Normal build/import/placement
# never calls this: interactive commands can still reference previous libraries.
proc lceda2orcadCloseOlb {} {
    if {![info exists ::DboSession_s_pDboSession]} { return 1 }
    if {[catch {
        set lSession $::DboSession_s_pDboSession
        DboSession -this $lSession
    } lErr]} {
        puts "lceda2orcad: cannot access Capture library session: $lErr"
        return 0
    }

    set lPath [lceda2orcadOlbPath]
    set lTried {}
    foreach lNamePath [list [file nativename $lPath] $lPath] {
        if {[lsearch -exact $lTried $lNamePath] >= 0} { continue }
        lappend lTried $lNamePath
        set lStatus [DboState]
        set lName [DboTclHelper_sMakeCString $lNamePath]
        if {[catch {$lSession GetOpenLib $lName $lStatus} lLib]} {
            catch {DboTclHelper_sDeleteCString $lName}
            puts "lceda2orcad: cannot check whether the library is open: $lLib"
            return 0
        }
        catch {DboTclHelper_sDeleteCString $lName}
        if {$lLib eq "NULL"} { continue }

        # The OLB is generated output: discard in-memory edits before deleting it.
        if {[catch {DboSession_RemoveLib $lSession $lLib} lErr]} {
            puts "lceda2orcad: cannot unload the open library: $lErr"
            return 0
        }
        # Avoid global SWIG cleanup here; the menu callback may own other live
        # Capture pointers that this helper would also invalidate.
    }
    return 1
}

# XML -> .olb. XMATIC reports failure through a TCL global rather than a return
# value, so check that as well as the output file.
proc lceda2orcadImport {args} {
    if {![file exists $::lcedaXml]} {
        puts "lceda2orcad: $::lcedaXml not found -- fetch a part first"
        return 0
    }
    file mkdir [file dirname $::lcedaOlb]

    # Generated libraries are immutable within a Capture session. A second
    # build gets a new filename, so old interactive/native references stay valid.
    if {[file exists $::lcedaOlb]} {
        puts "lceda2orcad: refusing to replace an existing generated library; rebuild XML first"
        return 0
    }

    # mErrorInfo lives in a namespace created by Cadence's own
    # OrHandlerXMLImportExport.tcl, which Capture may not have sourced yet --
    # XMATIC_XML2OLB itself is registered from C++, so it works either way. A
    # plain `set` of that variable therefore fails with "parent namespace
    # doesn't exist" on a machine where the handler has not loaded, and because
    # it sits before the call, the conversion never even starts. So don't clear
    # it: read a baseline (empty if the namespace is absent) and compare after,
    # which is also what tells a fresh message apart from a stale one.
    set lErrBefore ""
    catch {set lErrBefore $::OrHandlerXMLImportExport::mErrorInfo}

    if {[catch {XMATIC_XML2OLB $::lcedaXml $::lcedaOlb} lErr]} {
        puts "lceda2orcad: XML2OLB raised: $lErr"
        return 0
    }

    set lErrAfter ""
    catch {set lErrAfter $::OrHandlerXMLImportExport::mErrorInfo}
    if {$lErrAfter ne "" && $lErrAfter ne $lErrBefore} {
        puts "lceda2orcad: XML2OLB reported: $lErrAfter"
    }
    if {![file exists $::lcedaOlb] || [file size $::lcedaOlb] == 0} {
        puts "lceda2orcad: XML2OLB produced no library"
        return 0
    }
    # Capture 17.4 writes a canonical on-disk spelling (commonly LCEDA.OLB).
    # Its library/session lookup is not consistently case-insensitive. Passing
    # the requested lower-case alias immediately after XML2OLB can crash the UI
    # placement command for heterogeneous packages. Resolve and retain the exact
    # file spelling for placement; later builds use new immutable filenames.
    set ::lcedaOlb [lceda2orcadOlbPath]
    puts "lceda2orcad: built $::lcedaOlb ([file size $::lcedaOlb] bytes)"
    return 1
}

# Place a package on the active schematic page.
#
# PlacePartEx signature, from the SWIG argument-error strings in Capture.exe:
#   aLibraryName aPackageName aDeviceDesignator aIsConvert aProp aValue \
#   bShowErrorPopup
# so the bare 0 is aIsConvert, not a display flag.
#
# pPropNames/pPropValues (args 5-6) set properties on the *placed instance*. We
# deliberately leave them empty: an instance-level override does not inherit the
# symbol's "Value Only" display setting, which is what hid the value. The library
# symbol already carries PartValue plus a SymbolDisplayProp for Value with
# display type 1 (= Value Only), so inheriting is both correct and enough.
# Capture's own PWL extractor places the same way --
# OrHandlerCapPSpicePWLExtractor.tcl:438 passes "" "" for these.
#
# Callers can still pass overrides for extra properties; doing so may re-hide
# Value, so pass Value's display state yourself if you do.
#
# The trailing 0 is bShowErrorPopup, and passing it explicitly matters: left off,
# a failure raises a MODAL dialog behind Capture's window, which looks exactly
# like a hang -- output stops after "placing <pkg>" and nothing responds.
# orHandlerPartSearch.tcl:555 passes 1 there because it is driven by a visible
# browser; we want the message in the Command Window instead.
#
# But not every 17.4 registers that 7-argument overload. Within one install the
# 6-argument form is the common one (PSpiceModelBrowser.tcl:317,
# OrHandlerUnifiedSearch.tcl:775, OrHandlerCapPSpicePWLExtractor.tcl:438) and
# only orHandlerPartSearch.tcl uses 7 -- so we try 7 first and fall back.
#
# The fallback must NOT test the error text. SWIG's dispatcher reports arity
# mismatch and type mismatch with the same sentence: "No matching function for
# overloaded 'PlacePartEx'" occurs 62 times in Capture.exe (once per overloaded
# symbol) while "Wrong # args for overloaded function" occurs zero times. An
# earlier version guarded the retry with a match on "*argument*", which that
# sentence does not contain -- so the retry was dead code and a build without the
# 7-argument form simply failed. Walk the candidates instead and let any error
# from a non-final form advance to the next one.
set ::lceda2orcadPlaceArity ""

# True only for "this signature does not exist" -- never for a placement that was
# dispatched and then failed. The distinction matters: a real failure retried with
# the 6-argument form would raise the modal dialog the 7th argument exists to
# suppress, turning one hang into another.
#
# These are the three rejection sentences Capture.exe actually contains:
# "No matching function for overloaded" x62 (SWIG's overload dispatcher, one per
# symbol), "wrong # args" x1 and "Wrong number of arguments" x1. Counted in the
# binary rather than guessed -- guessing is what produced the earlier dead guard.
proc lceda2orcadIsDispatchError {pErr} {
    # Each pattern needs its own brace group: the patterns contain spaces, and a
    # bare {a b c d} list would be split on whitespace into single words that
    # match nothing.
    foreach lPat [list {*no matching function*} {*wrong # args*} \
                       {*wrong number of arguments*}] {
        if {[string match -nocase $lPat $pErr]} { return 1 }
    }
    return 0
}

proc lceda2orcadPlace {pPkg {pPropNames {}} {pPropValues {}} {pDesignator ""}} {
    set lFrame [DboTclHelper_sGetConstCharPtr [capGetMostRecentSchFrameID]]
    if {[catch {ui::SchematicActivate $lFrame}]} {
        puts "lceda2orcad: no active schematic page -- open one and retry"
        return 0
    }
    if {![llength [info commands PlacePartEx]]} {
        puts "lceda2orcad: PlacePartEx is not registered in this Capture build"
        return 0
    }

    set units [list ""]
    if {[info exists ::lcedaUnitsByPackage($pPkg)]} {set units $::lcedaUnitsByPackage($pPkg)}
    set pDesignator [string toupper [string trim $pDesignator]]
    if {$pDesignator eq ""} {set pDesignator [lindex $units 0]}
    if {[lsearch -exact $units $pDesignator] < 0} {
        puts "lceda2orcad: invalid unit '$pDesignator' for $pPkg; available units: $units"
        return 0
    }
    set ::lceda2orcadPlacedUnit $pDesignator
    puts "lceda2orcad: place package=$pPkg unit=$pDesignator"
    set lBase [list $::lcedaOlb $pPkg $pDesignator 0 $pPropNames $pPropValues]
    # 7 first: it keeps failures in the Command Window instead of a modal dialog.
    set lForms [list [linsert $lBase end 0] $lBase]
    # Once a build has told us which form it has, stop probing the other one --
    # otherwise every placement pays a failed dispatch, and on a build that only
    # has 6 the discarded 7-arg error would be printed every time.
    if {$::lceda2orcadPlaceArity eq "6"} {
        set lForms [list $lBase]
    } elseif {$::lceda2orcadPlaceArity eq "7"} {
        set lForms [list [linsert $lBase end 0]]
    }

    set lLast [expr {[llength $lForms] - 1}]
    for {set i 0} {$i <= $lLast} {incr i} {
        set lArgs [lindex $lForms $i]
        if {![catch {PlacePartEx {*}$lArgs} lErr]} {
            set ::lceda2orcadPlaceArity [llength $lArgs]
            return 1
        }
        if {$i == $lLast || ![lceda2orcadIsDispatchError $lErr]} { break }
        # Say it once so the fallback is visible rather than silent, then keep
        # going -- this is the expected path on a build without the 7-arg form.
        puts "lceda2orcad: [llength $lArgs]-arg PlacePartEx rejected ($lErr)"
    }
    puts "lceda2orcad: PlacePartEx failed: $lErr"
    return 0
    return 1
}

# One-shot: LCSC code in, placed part out.
#   lceda2orcadAdd C2040
proc lceda2orcadAdd {pLcsc {pDesignator ""}} {
    if {[catch {lceda::normalizeLcsc $pLcsc} lCode]} {
        puts "lceda2orcad: $lCode"
        return 0
    }
    if {[catch {lceda::initHttp} lErr]} {
        puts "lceda2orcad: cannot set up HTTPS: $lErr"
        return 0
    }
    if {[catch {lceda::fetch $lCode} lErr]} {
        puts "lceda2orcad: fetch failed for $lCode: $lErr"
        return 0
    }
    if {![lceda2orcadBuildXml]} { return 0 }
    if {![lceda2orcadImport]} { return 0 }

    if {![info exists ::lcedaByLcsc($lCode)]} {
        puts "lceda2orcad: $lCode fetched but no package name recorded"
        return 0
    }
    set lPkg $::lcedaByLcsc($lCode)
    lceda2orcadSetUnitChoices $::lcedaUnitsByPackage($lPkg)
    puts "lceda2orcad: placing $lPkg"
    return [lceda2orcadPlace $lPkg {} {} $pDesignator]
}

proc lceda2orcadPackages {} {
    if {[info exists ::lcedaPkgs]} { return $::lcedaPkgs }
    return {}
}

# Menu handler. Arity differs by context -- page callbacks get "pPage pOcc",
# design callbacks get "pLib" (capMenuUtil.tcl) -- so {args} absorbs both.
proc lceda2orcadMenuPlace {pPkg args} {
    lceda2orcadPlace $pPkg
}

# Rebuild the .olb from the cache without going to the network. Use after
# clearing the cache, or if the .olb was deleted or corrupted.
proc lceda2orcadMenuRebuild {args} {
    if {![lceda2orcadBuildXml]} { return }
    lceda2orcadImport
}

# Loading Tk creates the "." root window, which would otherwise pop up as a
# stray empty frame. Cadence hides it the same way -- update, then withdraw --
# in capAppLaunchMenu.tcl:26, capinit.tcl:42, capAppsManager.tcl:78 and four
# others. The update must come first or the withdraw can be missed.
# Returns 1 if Tk is usable.
proc lceda2orcadTk {} {
    if {[catch {package require Tk 8.6}]} {
        return 0
    }
    catch {update}
    catch {wm withdraw .}
    return 1
}

# Pull an LCSC code out of the clipboard. Browser copies often bring along
# whitespace or a whole product title, so match the code rather than trusting
# the whole string.
proc lceda2orcadClipLcsc {} {
    if {![lceda2orcadTk]} {
        puts "lceda2orcad: Tk unavailable, cannot read clipboard"
        return ""
    }
    if {[catch {clipboard get} lText]} {
        return ""
    }
    if {[regexp -nocase {C[0-9]{3,10}} $lText lHit]} {
        return [string toupper $lHit]
    }
    return ""
}

proc lceda2orcadMenuFromClip {args} {
    set lLcsc [lceda2orcadClipLcsc]
    if {$lLcsc eq ""} {
        puts "lceda2orcad: no LCSC code in clipboard (expects something like C2040)"
        return
    }
    puts "lceda2orcad: clipboard -> $lLcsc"
    lceda2orcadAdd $lLcsc
}

# Non-modal input form. Capture's own forms (capDRCUtils.tcl:100,
# capExportDesignCacheLaunch.tcl:225 and seven others) all share one shape:
# capTopLevel -> build widgets -> autoAdoptWindow, which reparents the Tk
# toplevel onto Capture's MFC main window. Not one of them calls tkwait or
# vwait; a blocking wait would fight Capture's message pump. So all work
# happens in button callbacks and the window stays open for the next part.
set ::lceda2orcadEntry ""
set ::lceda2orcadUnit "\u81ea\u52a8"
set ::lceda2orcadUnitEntry ""
set ::lceda2orcadUnitChoices [list "\u81ea\u52a8"]
proc lceda2orcadSetUnitChoices {units} {
    set choices [list "\u81ea\u52a8"]
    foreach unit $units {if {$unit ne ""} {lappend choices $unit}}
    set ::lceda2orcadUnitChoices $choices
    if {![info exists ::lceda2orcadUnit] || $::lceda2orcadUnit ni $choices} {
        set ::lceda2orcadUnit "\u81ea\u52a8"
    }
    if {[llength [info commands winfo]]} {
        foreach widget {.lceda2orcad.unit .xiaokaiSchematicPlugins.number.unit} {
            if {[winfo exists $widget]} {$widget configure -values $choices}
        }
    }
    return $choices
}
# Typing reads cache only; opening the selector may download an uncached part.
# Both entry points use parsed sections, the same data used by library creation.
proc lceda2orcadRefreshUnits {{download 0}} {
    set code [string toupper [string trim $::lceda2orcadEntry]]
    if {![regexp {^C[0-9]{3,10}$} $code]} {return [lceda2orcadSetUnitChoices {}]}
    if {![file exists [lceda::cachePath $code]]} {
        lceda2orcadSetUnitChoices {}
        if {!$download} {return $::lceda2orcadUnitChoices}
        set ::lceda2orcadStatus "\u6b63\u5728\u8bfb\u53d6 $code \u7684\u5355\u5143\u6570\u91cf..."
        update idletasks
        if {[catch {lceda::fetch $code} message]} {
            set ::lceda2orcadStatus "$code \u8bfb\u53d6\u5931\u8d25\uff1a$message"
            return $::lceda2orcadUnitChoices
        }
    }
    if {[catch {lceda::parseSymbol [lceda::loadCached $code]} symbol]} {
        lceda2orcadSetUnitChoices {}
        if {$download} {set ::lceda2orcadStatus "$code \u8bfb\u53d6\u5931\u8d25\uff1a$symbol"}
        return $::lceda2orcadUnitChoices
    }
    set units {}
    if {[dict exists $symbol sections]} {
        set index 0
        foreach section [dict get $symbol sections] {lappend units [lceda::sectionSuffix $index];incr index}
    }
    lceda2orcadSetUnitChoices $units
    if {$download} {
        set count [expr {max(1,[llength $units])}]
        set ::lceda2orcadStatus "$code\uff1a$count \u4e2a\u5355\u5143\uff0c\u9009\u62e9\u540e\u70b9\u51fb\u6dfb\u52a0\u3002"
    }
    return $::lceda2orcadUnitChoices
}
proc lceda2orcadEntryChanged {args} {
    if {$::lceda2orcadUnitEntry ne $::lceda2orcadEntry} {
        set ::lceda2orcadUnitEntry $::lceda2orcadEntry
        set ::lceda2orcadUnit "\u81ea\u52a8"
        lceda2orcadRefreshUnits
    }
}
if {![llength [trace info variable ::lceda2orcadEntry]]} {
    trace add variable ::lceda2orcadEntry write lceda2orcadEntryChanged
}
set ::lceda2orcadStatus "\u8f93\u5165\u6216\u7c98\u8d34\u7acb\u521b\u7f16\u53f7\uff0c\u7136\u540e\u6309\u56de\u8f66\u952e\u3002"

proc lceda2orcadDialogRun {} {
    set lLcsc [string toupper [string trim $::lceda2orcadEntry]]
    if {![regexp {^C[0-9]{3,10}$} $lLcsc]} {
        set ::lceda2orcadStatus "\u7f16\u53f7\u683c\u5f0f\u4e0d\u6b63\u786e\uff1a$lLcsc"
        return
    }
    set ::lceda2orcadStatus "\u6b63\u5728\u83b7\u53d6 $lLcsc ..."
    # No event loop of our own, so nudge Tk to repaint the label before the
    # blocking fetch in lceda2orcadAdd.
    update idletasks
    set unit $::lceda2orcadUnit
    if {$unit eq "\u81ea\u52a8"} {set unit ""}
    if {[lceda2orcadAdd $lLcsc $unit]} {
        set ::lceda2orcadStatus "\u5df2\u6dfb\u52a0 $lLcsc\u3002"
    } else {
        set ::lceda2orcadStatus "$lLcsc \u6dfb\u52a0\u5931\u8d25\uff0c\u8bf7\u67e5\u770b Capture \u547d\u4ee4\u7a97\u53e3\u3002"
    }
}

proc lceda2orcadDialogPaste {} {
    set lLcsc [lceda2orcadClipLcsc]
    if {$lLcsc eq ""} {
        set ::lceda2orcadStatus "\u526a\u8d34\u677f\u4e2d\u6ca1\u6709\u627e\u5230\u7acb\u521b\u7f16\u53f7\u3002"
        return
    }
    set ::lceda2orcadEntry $lLcsc
    lceda2orcadDialogRun
}

proc lceda2orcadMenuDialog {args} {
    if {![lceda2orcadTk]} {
        puts "lceda2orcad: Tk unavailable -- use lceda2orcadAdd <code> instead"
        return
    }
    set lForm .lceda2orcad

    # Re-invoking the menu must not fail: toplevel errors out on an existing
    # window name, so raise the old one instead of rebuilding it.
    if {[winfo exists $lForm]} {
        wm deiconify $lForm
        raise $lForm
        focus $lForm.in
        return
    }

    if {[catch {package require capAppUtils} lErr]} {
        puts "lceda2orcad: capAppUtils unavailable ($lErr) -- plain window"
        toplevel $lForm
    } else {
        capAppUtils::capTopLevel $lForm
    }
    wm title $lForm "Orcad\u5185\u76f4\u63a5\u653e\u7f6e\u7acb\u521b\u5143\u4ef6"
    wm resizable $lForm 0 0

    lceda2orcadRefreshUnits
    label  $lForm.lbl -text "\u7acb\u521b\u7f16\u53f7\uff1a"
    entry  $lForm.in -width 18 -textvariable ::lceda2orcadEntry
    button $lForm.go -text "\u6dfb\u52a0" -width 10 -command lceda2orcadDialogRun
    label $lForm.unitLabel -text "\u5355\u5143\uff1a"
    ttk::combobox $lForm.unit -width 12 -state readonly -textvariable ::lceda2orcadUnit -values $::lceda2orcadUnitChoices -postcommand {lceda2orcadRefreshUnits 1}
    button $lForm.cb -text "\u4ece\u526a\u8d34\u677f\u7c98\u8d34" -command lceda2orcadDialogPaste
    label  $lForm.st -textvariable ::lceda2orcadStatus -anchor w -width 44

    grid $lForm.lbl -row 0 -column 0 -sticky w  -padx 6 -pady 6
    grid $lForm.in  -row 0 -column 1 -sticky we -padx 6 -pady 6
    grid $lForm.go  -row 0 -column 2 -padx 6 -pady 6
    grid $lForm.cb  -row 1 -column 1 -sticky we -padx 6 -pady {0 6}
    grid $lForm.unitLabel -row 2 -column 0 -sticky w -padx 6 -pady {0 6}
    grid $lForm.unit -row 2 -column 1 -sticky we -padx 6 -pady {0 6}
    grid $lForm.st  -row 3 -column 0 -columnspan 3 -sticky we -padx 6 -pady {0 6}

    # Enter runs it, so the whole flow is paste + Enter with no mouse.
    bind $lForm.in <Return> lceda2orcadDialogRun
    bind $lForm.in <KP_Enter> lceda2orcadDialogRun
    bind $lForm <Escape> [list wm withdraw $lForm]

    catch {capAppUtils::autoAdoptWindow $lForm}
    focus $lForm.in
}

proc lceda2orcadMenuList {args} {
    set lCached [lceda::cachedParts]
    if {![llength $lCached]} {
        puts "lceda2orcad: cache is empty ([lceda::cacheDir])"
        return
    }

    puts "lceda2orcad: [llength $lCached] part(s) cached in [lceda::cacheDir]"
    foreach lCode $lCached {
        if {[info exists ::lcedaByLcsc($lCode)]} {
            puts "  $lCode  $::lcedaByLcsc($lCode)"
        } else {
            puts "  $lCode"
        }
    }
}

proc lceda2orcadMenuClearOlb {args} {
    set lOlbPath [lceda2orcadOlbPath]
    if {![file exists $lOlbPath]} {
        puts "Orcad\u5185\u76f4\u63a5\u653e\u7f6e\u7acb\u521b\u5143\u4ef6\uff1a\u7f13\u5b58\u5143\u4ef6\u5e93\u6587\u4ef6\u4e0d\u5b58\u5728\uff0c\u65e0\u9700\u6e05\u9664\u3002"
        return 1
    }

    if {![lceda2orcadCloseOlb]} {
        puts "Orcad\u5185\u76f4\u63a5\u653e\u7f6e\u7acb\u521b\u5143\u4ef6\uff1aCapture \u4e2d\u7684\u5668\u4ef6\u5e93\u65e0\u6cd5\u5378\u8f7d\uff0c\u672a\u5220\u9664\u6587\u4ef6\u3002"
        puts "\u8bf7\u5173\u95ed Capture \u4e2d\u6253\u5f00\u7684\u7acb\u521b\u5668\u4ef6\u5e93\u540e\u91cd\u8bd5\u3002"
        return 0
    }
    if {[catch {file delete -force $lOlbPath} lErr]} {
        puts "Orcad\u5185\u76f4\u63a5\u653e\u7f6e\u7acb\u521b\u5143\u4ef6\uff1a\u65e0\u6cd5\u6e05\u9664\u7f13\u5b58\u5143\u4ef6\u5e93 $lOlbPath\uff1a$lErr"
        puts "\u8bf7\u786e\u8ba4\u8be5\u5e93\u672a\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\u540e\u91cd\u8bd5\u3002"
        return 0
    }
    if {[file exists $lOlbPath]} {
        puts "Orcad\u5185\u76f4\u63a5\u653e\u7f6e\u7acb\u521b\u5143\u4ef6\uff1a\u5220\u9664\u547d\u4ee4\u5df2\u6267\u884c\uff0c\u4f46\u6587\u4ef6\u4ecd\u5b58\u5728\uff1a$lOlbPath"
        puts "\u8bf7\u5173\u95ed\u5176\u4ed6\u5360\u7528\u8be5\u5e93\u7684\u7a0b\u5e8f\u540e\u91cd\u8bd5\u3002"
        return 0
    }
    puts "Orcad\u5185\u76f4\u63a5\u653e\u7f6e\u7acb\u521b\u5143\u4ef6\uff1a\u5df2\u5220\u9664\u5e93\u6587\u4ef6 $lOlbPath"
    puts "\u5668\u4ef6\u6570\u636e\u7f13\u5b58\u4e0e XML \u5df2\u4fdd\u7559\uff1b\u9700\u8981\u65f6\u518d\u91cd\u65b0\u751f\u6210\u5e93\u6587\u4ef6\u3002"
    return 1
}

# Install this file into Capture's user-level autoload folder so it loads at
# startup. Run it once from the Command Window after sourcing this file from
# wherever you unpacked it:
#     source d:/somewhere/lceda2orcadMenu.tcl
#     lceda2orcadInstall
# Nothing is rewritten on the way -- the data folder is resolved relative to the
# installed copy, so a plain file copy is a complete install.
#
# The autoload folder location is compiled into Capture.exe; the
# CaptureTclAutoLoadScope preference only switches which scopes are scanned, it
# cannot move the folder. The path has no version segment -- a 17.4.0 level was
# tested and is not scanned.
proc lceda2orcadInstall {{pDest ""}} {
    set lSrc [file join $::lceda2orcadHome [file tail [info script]]]
    if {![file exists $lSrc]} {
        # info script is unreliable once we are past sourcing; fall back to the
        # conventional name in the home directory.
        set lSrc [file join $::lceda2orcadHome lceda2orcadMenu.tcl]
    }
    if {![file exists $lSrc]} {
        puts "lceda2orcad: cannot find my own file under $::lceda2orcadHome"
        return 0
    }

    if {$pDest ne ""} {
        set lDest $pDest
    } else {
        set lSpb [lceda2orcadFindSpbData]
        if {$lSpb eq ""} {
            puts "lceda2orcad: cannot find Cadence's SPB_Data folder."
            puts "lceda2orcad: pass it explicitly, e.g."
            puts "  lceda2orcadInstall {C:/orcad/Cadence/SPB_Data/cdssetup/OrCAD_Capture/tclscripts/capAutoLoad}"
            return 0
        }
        puts "lceda2orcad: SPB_Data is $lSpb"
        set lDest [file join $lSpb cdssetup OrCAD_Capture tclscripts capAutoLoad]
    }

    if {[catch {file mkdir $lDest} lErr]} {
        puts "lceda2orcad: cannot create $lDest: $lErr"
        return 0
    }
    set lTarget [file join $lDest lceda2orcadMenu.tcl]
    if {[file normalize $lSrc] eq [file normalize $lTarget]} {
        puts "lceda2orcad: already installed at $lTarget"
        return 1
    }
    if {[catch {file copy -force $lSrc $lTarget} lErr]} {
        puts "lceda2orcad: copy failed: $lErr"
        return 0
    }
    puts "lceda2orcad: installed $lTarget"
    puts "lceda2orcad: restart Capture; parts and cache will live in"
    puts "  [file join $lDest lceda2orcad-data]"
    return 1
}

# Cadence sets HOME to SPB_Data at install time. If that has been changed by
# something else, fall back to the usual install locations.
proc lceda2orcadFindSpbData {} {
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

# Report which build is loaded and where its data lives. Worth having in the
# Command Window when a problem only reproduces on one machine -- the answer is
# usually "an older copy is installed" or "the data folder is not where you
# think".
proc lceda2orcadVersion {} {
    puts "lceda2orcad $::lceda2orcadVersion"
    puts "  script : $::lceda2orcadHome/lceda2orcadMenu.tcl"
    puts "  data   : [lceda2orcadDataDir]"
    puts "  cache  : [llength [lceda::cachedParts]] part(s) in [lceda::cacheDir]"
    if {[file exists $::lcedaOlb]} {
        puts "  olb    : [file size $::lcedaOlb] bytes"
    } else {
        puts "  olb    : not built yet"
    }
    # Which PlacePartEx overload this build accepted. Worth printing: a report of
    # "No matching function for overloaded 'PlacePartEx'" is exactly what this
    # line answers, and it varies between installs of the same 17.4.
    if {$::lceda2orcadPlaceArity eq ""} {
        puts "  place  : arity not probed yet (place a part first)"
    } else {
        puts "  place  : PlacePartEx/$::lceda2orcadPlaceArity"
    }
    return $::lceda2orcadVersion
}

# Load banner: the only reliable way to tell whether Capture actually scanned
# this folder. If you never see this line, the folder is not on the autoload
# search path -- source this file by hand instead. The version is here too, so a
# stale installed copy is visible without running anything.
puts "lceda2orcad $::lceda2orcadVersion: menu registered from [info script]"
