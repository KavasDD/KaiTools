# SPDX-License-Identifier: GPL-3.0-only
# lceda2orcad core -- fetch / parse / XML build, pure TCL.
#
# Developed standalone so it can be exercised in tclsh.exe, which has none of
# Capture's commands. The installed menu file concatenates this verbatim.
# Pure ASCII: the Command Window decodes output as GBK.

namespace eval lceda {
    variable API "https://easyeda.com/api/products/%s/components?version=6.4.19.5"
    variable UA "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    variable dataDir ""
    variable httpReady 0
    variable pkgReady 0

    # How to open the TCP connection, in the order they get tried.
    #
    # Why this is a list instead of one hardcoded call: easyeda.com publishes
    # both A and AAAA records, and Tcl 8.6.5 (what Capture 17.4 ships) has a
    # broken async connect fallback. It walks getaddrinfo's list, and on a
    # machine with a routable-looking IPv6 address the AAAA records come first.
    # When the IPv6 attempt fails, the retry reuses the same socket instead of
    # making a fresh one, so connect() answers WSAEINVAL and http reports
    #     connect failed invalid argument
    # for every part -- which is exactly what users on IPv6-capable networks
    # saw. Machines with only link-local fe80:: addresses never hit it, because
    # there getaddrinfo puts IPv4 first and the first attempt succeeds.
    #
    # -myaddr 0.0.0.0 pins the family: Tcl's TcpConnect skips candidate pairs
    # whose local and remote families differ, so an AF_INET local address
    # excludes every AAAA candidate and the broken retry is never entered.
    # Verified both ways -- -myaddr :: fails on an IPv4-only host, so the
    # option really does pin the family rather than being ignored.
    #
    # IPv4 is not forced unconditionally, though: an IPv6-only network would
    # then have nothing left to try. Hence the ladder. Blocking connect is
    # last-ditch -- it is a different code path in Tcl that skips the async
    # machinery altogether, at the cost of freezing the UI until the OS
    # gives up (~21 s).
    variable connectPlan {
        {-myaddr 0.0.0.0 -async}  "IPv4, async"
        {-async}                  "any family, async"
        {-myaddr 0.0.0.0}         "IPv4, blocking"
        {}                        "any family, blocking"
    }
    # Index into connectPlan. Sticky for the session: once something works, the
    # next part must not pay for the failing attempts again. 20 parts x a dead
    # IPv6 connect is minutes of waiting.
    variable connectAt 0
}

# ---------------------------------------------------------------- packages ---

# Cadence ships tls 1.6.6 inside Capture's own tclPackages, and tcllib has the
# json parser. Both directories have to be on auto_path before the requires.
# Put Cadence's bundled tcllib and Capture's tclPackages on auto_path. Split out
# from initHttp so a cache-only rebuild can get the json parser without paying
# for the TLS setup.
proc lceda::initPackages {{pSpb ""}} {
    variable pkgReady
    if {$pkgReady} { return 1 }

    set lRoots {}
    if {$pSpb ne ""} { lappend lRoots $pSpb }
    # Cadence install root: derive from tclsh/Capture location when possible.
    foreach lVar {CDS_INST_DIR SPB_17_4} {
        if {[info exists ::env($lVar)]} { lappend lRoots $::env($lVar) }
    }
    lappend lRoots "C:/orcad/Cadence/SPB_17.4"

    foreach lRoot $lRoots {
        foreach lSub {
            "tcltk/lib/tcllib1.15"
            "tools/capture/tclscripts/capStartPage/tclPackages"
            "tools/capture/tclscripts/capOrCADStartPage/tclPackages"
        } {
            set lDir [file join $lRoot $lSub]
            if {[file isdirectory $lDir] && [lsearch -exact $::auto_path $lDir] < 0} {
                lappend ::auto_path $lDir
            }
        }
    }
    if {[catch {package require json} lErr]} {
        return -code error "cannot load TCL package json: $lErr"
    }
    set pkgReady 1
    return 1
}

proc lceda::initHttp {{pSpb ""}} {
    variable httpReady
    if {$httpReady} { return 1 }
    lceda::initPackages $pSpb

    foreach lPkg {http tls} {
        if {[catch {package require $lPkg} lErr]} {
            puts "lceda2orcad: cannot load TCL package $lPkg: $lErr"
            return 0
        }
    }

    # SNI is mandatory. Without -servername the handshake dies with
    # "sslv3 alert handshake failure" on every protocol version.
    http::register https 443 ::lceda::sniSocket
    # The http package overrides a User-Agent passed via -headers with its own,
    # and easyeda answers 403 to that one. It has to be set here.
    variable UA
    http::config -useragent $UA
    set httpReady 1
    return 1
}

proc lceda::sniSocket {args} {
    variable connectPlan
    variable connectAt

    # socket's syntax is "socket ?options? host port", so the tail is fixed no
    # matter what options http prepended.
    set lHost [lindex $args end-1]
    set lPort [lindex $args end]

    # Drop the connect options http chose so the ladder is the only thing
    # deciding. Only these two are dropped, not every option: anything else
    # http passes is still its business and gets forwarded untouched.
    set lRest {}
    for {set i 0} {$i < [llength $args] - 2} {incr i} {
        set lOpt [lindex $args $i]
        switch -exact -- $lOpt {
            -async  { }
            -myaddr { incr i }
            default { lappend lRest $lOpt }
        }
    }

    set lOpts [lindex $connectPlan [expr {$connectAt * 2}]]
    set lCmd [concat [list tls::socket -servername $lHost \
                           -require 0 -request 0] $lRest $lOpts [list $lHost $lPort]]
    return [eval $lCmd]
}

# Walks the connect ladder. Returns an http token on success.
#
# The retry cannot live in sniSocket: an async connect failure does not surface
# there. The socket is created fine and the error only appears later, when http
# gets the writable event and reads [fconfigure -error] -- by then sniSocket has
# long returned. So the whole request is what gets retried.
proc lceda::httpGet {pUrl pHdrs} {
    variable connectPlan
    variable connectAt

    set lCount [expr {[llength $connectPlan] / 2}]
    set lTried {}
    for {} {$connectAt < $lCount} {incr connectAt} {
        set lWhat [lindex $connectPlan [expr {$connectAt * 2 + 1}]]
        if {[catch {
            http::geturl $pUrl -headers $pHdrs -timeout 30000 -binary 1
        } lTok]} {
            # A connect-level failure is worth another strategy. Anything else
            # (bad URL, DNS with no records at all, a TLS refusal) would fail
            # the same way on every strategy, so it is reported straight away
            # rather than after four attempts.
            if {![lceda::connectFailed $lTok]} {
                return -code error $lTok
            }
            lappend lTried "$lWhat -> $lTok"
            continue
        }
        # A timeout also counts: an unroutable address that black-holes rather
        # than refusing looks like this.
        if {[http::status $lTok] eq "timeout"} {
            http::cleanup $lTok
            lappend lTried "$lWhat -> timed out"
            continue
        }
        if {[llength $lTried]} {
            puts "lceda2orcad: connected using $lWhat (earlier attempts failed)"
        }
        return $lTok
    }

    # Everything failed. Reset so a later call starts from the top instead of
    # inheriting an exhausted index and reporting "no strategies left".
    set connectAt 0
    return -code error "cannot reach easyeda.com. Tried: [join $lTried {; }].\
        Check the network, and note that a proxy set only in Internet Options\
        is not used -- TCL does not read it."
}

# Is this an error from opening the connection, as opposed to anything above it?
# http 2.8.9 words it "connect failed <reason>" (http-2.8.9.tm:911), and Tcl
# words a synchronous one "couldn't open socket: <reason>".
proc lceda::connectFailed {pMsg} {
    foreach lPat {"connect failed" "couldn't open socket" "connection refused"
                  "network is unreachable" "host is unreachable"} {
        if {[string first $lPat $pMsg] >= 0} { return 1 }
    }
    return 0
}

# ------------------------------------------------------------------- fetch ---

proc lceda::normalizeLcsc {pPart} {
    set lP [string toupper [string trim $pPart]]
    if {![regexp {^C[0-9]+$} $lP]} {
        return -code error "not an LCSC part number: $pPart"
    }
    return $lP
}

proc lceda::cacheDir {} {
    variable dataDir
    return [file join $dataDir cache]
}

proc lceda::cachePath {pLcsc} {
    return [file join [lceda::cacheDir] $pLcsc.json]
}

# Returns the raw JSON text. Cache is the source of truth: a hit never touches
# the network.
proc lceda::fetch {pLcsc {pForce 0}} {
    set lLcsc [lceda::normalizeLcsc $pLcsc]
    set lPath [lceda::cachePath $lLcsc]
    if {!$pForce && [file exists $lPath] && [file size $lPath] > 0} {
        set lH [open $lPath rb]
        set lTxt [read $lH]
        close $lH
        return [encoding convertfrom utf-8 $lTxt]
    }

    if {![lceda::initHttp]} {
        return -code error "TCL http/tls packages unavailable"
    }

    variable API
    set lUrl [format $API $lLcsc]
    # Referer and Origin are required -- without them the API answers 403.
    set lHdrs [list \
        Accept "application/json, text/plain, */*" \
        Accept-Language "zh-CN,zh;q=0.9" \
        Referer "https://easyeda.com/" \
        Origin "https://easyeda.com"]

    if {[catch {lceda::httpGet $lUrl $lHdrs} lTok]} {
        return -code error "network error: $lTok"
    }
    set lCode [http::ncode $lTok]
    set lRaw [http::data $lTok]
    set lErr [http::error $lTok]
    http::cleanup $lTok

    if {$lErr ne ""} { return -code error "transfer failed: $lErr" }
    if {$lCode ne "200"} {
        return -code error "HTTP $lCode for $lLcsc"
    }

    set lTxt [encoding convertfrom utf-8 $lRaw]
    # Only cache once it parses and actually carries a usable component.
    if {[catch {json::json2dict $lTxt} lD]} {
        return -code error "response is not JSON: $lD"
    }
    if {[catch {lceda::resultOf $lD} lRes]} {
        return -code error "$lLcsc: $lRes"
    }
    if {![dict exists $lRes dataStr]} {
        return -code error "$lLcsc: no dataStr in response, not a parsable symbol"
    }

    file mkdir [lceda::cacheDir]
    set lH [open $lPath wb]
    puts -nonewline $lH $lRaw
    close $lH
    return $lTxt
}

# The cache written by the old Python code holds the bare "result" object, while
# we store the full response for provenance. Accept either so existing caches
# keep working.
proc lceda::resultOf {pDict} {
    # An unknown part number gets {"success":false,"code":404,"message":"..."}
    # with no result key at all, so the failure flag has to be checked first.
    if {[dict exists $pDict success]
     && ![string is true -strict [dict get $pDict success]]} {
        set lMsg ""
        catch {set lMsg [dict get $pDict message]}
        set lCode ""
        catch {set lCode [dict get $pDict code]}
        if {$lMsg eq ""} { set lMsg "API reported failure" }
        if {$lCode ne ""} { append lMsg " (code $lCode)" }
        return -code error $lMsg
    }
    if {[dict exists $pDict result]} {
        set lR [dict get $pDict result]
        if {$lR eq "null" || $lR eq ""} {
            return -code error "empty result, part number may not exist"
        }
        return $lR
    }
    # bare result object: the cache written by the old Python code
    if {[dict exists $pDict dataStr]} { return $pDict }
    return -code error "unrecognised response shape"
}

# Read one cached file and return its result dict. Errors if the file is absent
# or unusable, so callers can skip a bad entry without aborting a rebuild.
proc lceda::loadCached {pLcsc} {
    lceda::initPackages
    set lPath [lceda::cachePath $pLcsc]
    if {![file exists $lPath]} {
        return -code error "not cached: $lPath"
    }
    set lH [open $lPath r]
    fconfigure $lH -encoding utf-8
    set lTxt [read $lH]
    close $lH
    if {[catch {json::json2dict $lTxt} lD]} {
        return -code error "cached JSON is unreadable: $lD"
    }
    return [lceda::resultOf $lD]
}

proc lceda::cachedParts {} {
    set lOut {}
    foreach lF [lsort [glob -nocomplain -directory [lceda::cacheDir] *.json]] {
        lappend lOut [file rootname [file tail $lF]]
    }
    return $lOut
}

# ---------------------------------------------------------------------------
# parse -- LCEDA shape strings to an intermediate representation
#
# Port of parse.py. Coordinates: LCEDA and Capture both use 1 unit = 10 mil, so
# nothing is scaled. IR coordinates are relative to the symbol origin
# (head.x/head.y) with y growing downward, matching Capture.
#
# A pin is a dict: number name connX connY bodyX bodyY side dot clock
#                  nameVisible numberVisible
# A symbol is a dict: lcsc name prefix footprint manufacturer mfrPart
#                     pins rects polylines skipped
# ---------------------------------------------------------------------------

# Pin path first segment, e.g. M315,185h10 / M 325 188 L 328 185 / M315 185 v-10
set lceda::PATH_HEAD \
    {M\s*(-?[0-9.]+)[,\s]+(-?[0-9.]+)\s*([hvlHVL])\s*(-?[0-9.]+)(?:[,\s]+(-?[0-9.]+))?}

# Tolerant float conversion, matching Python's float() inside try/except.
# "" and any non-numeric text fall back to the default. The value is compared
# against a number regex first so expr never evaluates it as an expression.
proc lceda::num {pValue {pDefault 0.0}} {
    set lV [string trim $pValue]
    if {![regexp {^[-+]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][-+]?[0-9]+)?$} $lV]} {
        return [lceda::zero [expr {double($pDefault)}]]
    }
    return [lceda::zero [expr {double($lV)}]]
}

# Collapse IEEE negative zero to positive zero. "-0" is a legal double and
# survives arithmetic (expr {-0.0 - 0.0} is -0.0), so an untouched -0.0 would
# reach the generated XML as the text "-0" where Capture expects "0". Comparing
# against 0 catches both signs; re-assigning drops the sign bit.
proc lceda::zero {pValue} {
    if {$pValue == 0} { return 0.0 }
    return $pValue
}

# dict get with Python's "or default" semantics: a missing key and an empty
# value both yield the default.
proc lceda::dictOr {pDict pKey {pDefault {}}} {
    if {[catch {dict get $pDict $pKey} lV]} { return $pDefault }
    if {$lV eq "" || $lV eq "null"} { return $pDefault }
    return $lV
}

# Which side of the body the pin sits on, from the body direction relative to
# the connect end.
proc lceda::pinSide {pConnX pConnY pBodyX pBodyY} {
    set lDx [expr {$pBodyX - $pConnX}]
    set lDy [expr {$pBodyY - $pConnY}]
    if {abs($lDx) >= abs($lDy)} {
        return [expr {$lDx > 0 ? "LEFT" : "RIGHT"}]
    }
    return [expr {$lDy > 0 ? "TOP" : "BOTTOM"}]
}

# Split on a literal multi-char separator. TCL's split treats its argument as a
# set of single characters, so "^^" would also split on a single "^".
proc lceda::splitStr {pText pSep} {
    set lOut {}
    set lStart 0
    set lLen [string length $pSep]
    while {[set lIdx [string first $pSep $pText $lStart]] >= 0} {
        lappend lOut [string range $pText $lStart [expr {$lIdx - 1}]]
        set lStart [expr {$lIdx + $lLen}]
    }
    lappend lOut [string range $pText $lStart end]
    return $lOut
}

# Parse one P~ shape. Seven ^^-separated segments.
proc lceda::parsePin {pRaw} {
    variable PATH_HEAD
    set lSeg [lceda::splitStr $pRaw "^^"]
    if {[llength $lSeg] < 5} { return "" }

    set lHead [split [lindex $lSeg 0] "~"]
    if {[llength $lHead] < 7} { return "" }
    set lNumber [string trim [lindex $lHead 3]]
    set lConnX [lceda::num [lindex $lHead 4]]
    set lConnY [lceda::num [lindex $lHead 5]]

    # Derive the body end from the path: more reliable than the rotation field,
    # which only has four discrete values.
    set lPath [string trim [lindex [split [lindex $lSeg 2] "~"] 0]]
    if {![regexp $PATH_HEAD $lPath -> lPx lPy lCmd lVal lVal2]} { return "" }
    set lPx [lceda::num $lPx]
    set lPy [lceda::num $lPy]
    set lV [lceda::num $lVal]
    switch -exact -- $lCmd {
        h { set lBodyX [expr {$lPx + $lV}] ; set lBodyY $lPy }
        H { set lBodyX $lV                 ; set lBodyY $lPy }
        v { set lBodyX $lPx ; set lBodyY [expr {$lPy + $lV}] }
        V { set lBodyX $lPx ; set lBodyY $lV }
        l { set lBodyX [expr {$lPx + $lV}]
            set lBodyY [expr {$lPy + [lceda::num $lVal2]}] }
        default {
            set lBodyX $lV
            set lBodyY [lceda::num $lVal2]
        }
    }

    set lNameSeg [split [lindex $lSeg 3] "~"]
    set lName ""
    if {[llength $lNameSeg] > 4} { set lName [string trim [lindex $lNameSeg 4]] }
    set lNameVis [expr {[string trim [lindex $lNameSeg 0]] ne "0"}]

    set lNumSeg [split [lindex $lSeg 4] "~"]
    set lNumVis [expr {[string trim [lindex $lNumSeg 0]] ne "0"}]
    if {$lNumber eq ""} {
        # Nothing in head, fall back to the displayed text.
        if {[llength $lNumSeg] > 4} { set lNumber [string trim [lindex $lNumSeg 4]] }
    }

    set lDot 0
    if {[llength $lSeg] > 5} {
        set lDot [expr {[string trim [lindex [split [lindex $lSeg 5] "~"] 0]] eq "1"}]
    }
    set lClock 0
    if {[llength $lSeg] > 6} {
        set lClock [expr {[string trim [lindex [split [lindex $lSeg 6] "~"] 0]] eq "1"}]
    }

    if {$lName eq ""} { set lName $lNumber }
    return [dict create \
        number $lNumber name $lName \
        connX $lConnX connY $lConnY bodyX $lBodyX bodyY $lBodyY \
        side [lceda::pinSide $lConnX $lConnY $lBodyX $lBodyY] \
        dot $lDot clock $lClock \
        nameVisible $lNameVis numberVisible $lNumVis]
}

proc lceda::pinLength {pPin} {
    return [expr {abs([dict get $pPin connX] - [dict get $pPin bodyX])
                + abs([dict get $pPin connY] - [dict get $pPin bodyY])}]
}

# Dots in a footprint name become "d" -- Allegro rejects footprint names with
# decimal points. Only the dot changes; LCEDA names like
# LQFN-56_L7.0-W7.0-P0.4-EP keep their dashes and underscores.
proc lceda::sanitizeFootprint {pName} {
    return [string map {. d} $pName]
}

# Pin sort key: number length first, then the number as text. Mirrors
# sort(key=lambda p: (len(p.number), p.number)).
proc lceda::pinCompare {pA pB} {
    set lNa [dict get $pA number]
    set lNb [dict get $pB number]
    set lLa [string length $lNa]
    set lLb [string length $lNb]
    if {$lLa != $lLb} { return [expr {$lLa < $lLb ? -1 : 1}] }
    return [string compare $lNa $lNb]
}

# result dict (from lceda::resultOf) to symbol IR, translated to the origin.
proc lceda::parseSymbol {pResult} {
    set lData [lceda::dictOr $pResult dataStr]
    set lHead [lceda::dictOr $lData head]
    set lPara [lceda::dictOr $lHead c_para]
    set lOx [lceda::num [lceda::dictOr $lHead x 0]]
    set lOy [lceda::num [lceda::dictOr $lHead y 0]]

    set lLcsc [lceda::dictOr $lPara "Supplier Part"]
    if {$lLcsc eq ""} { set lLcsc [lceda::dictOr $pResult lcsc] }
    set lName [lceda::dictOr $pResult title]
    if {$lName eq ""} { set lName [lceda::dictOr $lPara name] }

    set lSym [dict create \
        lcsc $lLcsc \
        name $lName \
        prefix [lceda::dictOr $lPara pre "U?"] \
        footprint [lceda::sanitizeFootprint [lceda::dictOr $lPara package]] \
        manufacturer [lceda::dictOr $lPara Manufacturer] \
        mfrPart [lceda::dictOr $lPara "Manufacturer Part"] \
        pins {} rects {} polylines {} skipped {}]

    foreach lRaw [lceda::dictOr $lData shape] {
        set lKind [lindex [split $lRaw "~"] 0]
        if {$lKind eq "P"} {
            set lPin [lceda::parsePin $lRaw]
            if {$lPin eq ""} {
                dict lappend lSym skipped [string range $lRaw 0 59]
                continue
            }
            dict set lPin connX [lceda::zero [expr {[dict get $lPin connX] - $lOx}]]
            dict set lPin connY [lceda::zero [expr {[dict get $lPin connY] - $lOy}]]
            dict set lPin bodyX [lceda::zero [expr {[dict get $lPin bodyX] - $lOx}]]
            dict set lPin bodyY [lceda::zero [expr {[dict get $lPin bodyY] - $lOy}]]
            dict lappend lSym pins $lPin
        } elseif {$lKind eq "R"} {
            # R~x~y~rx~ry~width~height~...
            set lF [split $lRaw "~"]
            if {[llength $lF] >= 7} {
                dict lappend lSym rects [dict create \
                    x [lceda::zero [expr {[lceda::num [lindex $lF 1]] - $lOx}]] \
                    y [lceda::zero [expr {[lceda::num [lindex $lF 2]] - $lOy}]] \
                    width  [lceda::num [lindex $lF 5]] \
                    height [lceda::num [lindex $lF 6]]]
            }
        } elseif {$lKind eq "PL"} {
            set lF [split $lRaw "~"]
            set lCoords {}
            if {[llength $lF] > 1} {
                foreach lC [split [lindex $lF 1] " "] {
                    if {[string trim $lC] ne ""} { lappend lCoords [lceda::num $lC] }
                }
            }
            set lPts {}
            for {set i 0} {$i < [llength $lCoords] - 1} {incr i 2} {
                set j [expr {$i + 1}]
                lappend lPts [list \
                    [lceda::zero [expr {[lindex $lCoords $i] - $lOx}]] \
                    [lceda::zero [expr {[lindex $lCoords $j] - $lOy}]]]
            }
            if {[llength $lPts] >= 2} {
                dict lappend lSym polylines [dict create points $lPts]
            }
        } elseif {$lKind in {E T A PT PI}} {
            dict lappend lSym skipped $lKind
        }
    }

    dict set lSym pins [lsort -command lceda::pinCompare [dict get $lSym pins]]
    return $lSym
}

# ---------------------------------------------------------------------------
# xml -- IR to OrCAD Capture library XML (olb.xsd)
#
# Port of olbxml.py. Structure, checked against a real library exported with
# XMATIC_OLB2XML (olb.xsd's description of NormalView is incomplete):
#     Lib > Package > LibPart > {NormalView, PhysicalPart}
# PhysicalPart sits inside LibPart, not Package; suffix is ".Normal"; Cadence
# never writes Rect/SymbolVector under NormalView, the body outline is 4 Lines;
# every SymbolPinScalar needs all 9 boolean children; position starts at 0.
# 1 unit = 10 mil, same as LCEDA, no scaling.
# ---------------------------------------------------------------------------

set lceda::GRID 10
# Pin line length 3 grids: Cadence's own libraries use 30 (MICROPHONE start
# x=0, hotpt x=-30). Capture places the pin number above the pin line based on
# its length, so the length has to be right for the number to land right.
set lceda::PIN_LENGTH 30

# LCEDA's electrical type field is unreliable (STM32 has one value for every
# pin, RP2040 gives GND and GPIO the same), so everything is emitted as Passive
# to avoid bogus ERC errors. 4 = Passive in Capture's label table.
set lceda::DEFAULT_PIN_TYPE 4

# Python's round() is banker's rounding -- ties go to the even integer -- while
# TCL's round() is half-away-from-zero. round(0.5) is 0 in Python but 1 in TCL,
# and _snap probes half-grid offsets, so exact halves are the common case, not
# an edge case. Every coordinate would drift half a grid without this.
proc lceda::bankersRound {pValue} {
    set lV [expr {double($pValue)}]
    set lFloor [expr {floor($lV)}]
    set lDiff [expr {$lV - $lFloor}]
    if {$lDiff > 0.5} { return [expr {int($lFloor) + 1}] }
    if {$lDiff < 0.5} { return [expr {int($lFloor)}] }
    # exact tie: pick the even neighbour
    set lF [expr {int($lFloor)}]
    if {$lF % 2 == 0} { return $lF }
    return [expr {$lF + 1}]
}

proc lceda::snap {pValue} {
    variable GRID
    return [expr {[lceda::bankersRound [expr {double($pValue) / $GRID}]] * $GRID}]
}

proc lceda::floorG {pValue} {
    variable GRID
    return [expr {int(floor(double($pValue) / $GRID)) * $GRID}]
}

proc lceda::ceilG {pValue} {
    variable GRID
    return [expr {int(ceil(double($pValue) / $GRID)) * $GRID}]
}

# xml.sax.saxutils.quoteattr. Escapes &, <, > (ampersand first), then newline,
# CR and tab as numeric refs, then wraps: double quotes normally, single quotes
# if the text contains a double quote but no single quote, and double quotes
# with &quot; if it contains both.
proc lceda::quoteattr {pText} {
    set lT [string map {& &amp; < &lt; > &gt;} $pText]
    # The replacements are braced: a bare &#10; inside [list ...] would end the
    # command at the semicolon, since ; separates commands inside brackets too.
    set lT [string map [list \n {&#10;} \r {&#13;} \t {&#9;}] $lT]
    if {[string first "\"" $lT] >= 0} {
        if {[string first "'" $lT] >= 0} {
            return "\"[string map {\" &quot;} $lT]\""
        }
        return "'$lT'"
    }
    return "\"$lT\""
}

# U? -> U. Capture's refdesPrefix carries no question mark.
proc lceda::refdesPrefix {pSym} {
    set lP [string trimright [dict get $pSym prefix] "?"]
    if {$lP eq ""} { return "U" }
    return $lP
}

# Snap pins to the 100 mil grid. LCEDA lets pins sit anywhere, but a pin off
# grid cannot be wired in Capture. First find a whole-symbol translation that
# lands the most pins on grid naturally (many libraries sit half a grid off),
# then snap the rest individually; if a snapped pin collides with an occupied
# slot, push it sideways.
# Returns a 2-element list: {snapped report}, where snapped maps pin number to
# {connX connY bodyX bodyY} and report is a dict of
# {translate origin renamed moved total collisions}.
proc lceda::snapPins {pPins} {
    variable GRID
    set lReport [dict create translate {0 0} origin {0 0} renamed 0 \
                            moved 0 total [llength $pPins] collisions {}]
    if {![llength $pPins]} { return [list {} $lReport] }

    # Candidate translations; a half-grid offset is by far the most common case.
    # Strictly-greater keeps the first winner on a tie, like Python's max().
    set lBestN -1
    set lDx 0
    set lDy 0
    foreach ddx [list 0 [expr {$GRID / 2}]] {
        foreach ddy [list 0 [expr {$GRID / 2}]] {
            set lN 0
            foreach p $pPins {
                if {[lceda::onGrid [expr {[dict get $p connX] + $ddx}]]
                 && [lceda::onGrid [expr {[dict get $p connY] + $ddy}]]} { incr lN }
            }
            if {$lN > $lBestN} { set lBestN $lN ; set lDx $ddx ; set lDy $ddy }
        }
    }
    dict set lReport translate [list $lDx $lDy]

    # Unit vector pointing away from the symbol (the direction the pin sticks out).
    set lOutward [dict create LEFT {-1 0} RIGHT {1 0} TOP {0 -1} BOTTOM {0 1}]
    # On a collision, step perpendicular to the pin: left/right pins move up or
    # down, top/bottom pins move left or right. Stepping along the pin axis only
    # lengthens the pin -- both pins stay on the same line and still look stacked.
    set lAside [dict create LEFT {0 1} RIGHT {0 1} TOP {1 0} BOTTOM {1 0}]

    set lPlaced [dict create]
    set lResult [dict create]
    set lMoved [dict get $lReport moved]

    foreach p $pPins {
        set lCx [expr {[dict get $p connX] + $lDx}]
        set lCy [expr {[dict get $p connY] + $lDy}]
        set lSx [lceda::snap $lCx]
        set lSy [lceda::snap $lCy]
        if {$lSx != $lCx || $lSy != $lCy} { incr lMoved }

        set lSide [dict get $p side]
        set lO {-1 0}
        catch {set lO [dict get $lOutward $lSide]}
        set lA {0 1}
        catch {set lA [dict get $lAside $lSide]}
        set lAx [lindex $lA 0]
        set lAy [lindex $lA 1]

        if {[dict exists $lPlaced "$lSx,$lSy"]} {
            dict lappend lReport collisions \
                [list [dict get $lPlaced "$lSx,$lSy"] [dict get $p number]]
            # Nearest free slot: +1, -1, +2, -2 ... so the shift stays small.
            set lLimit [expr {[llength $pPins] + 1}]
            for {set k 1} {$k <= $lLimit} {incr k} {
                set lHit 0
                foreach lStep [list $k [expr {-$k}]] {
                    set lNx [expr {$lSx + $lAx * $lStep * $GRID}]
                    set lNy [expr {$lSy + $lAy * $lStep * $GRID}]
                    if {![dict exists $lPlaced "$lNx,$lNy"]} {
                        set lSx $lNx ; set lSy $lNy ; set lHit 1 ; break
                    }
                }
                if {$lHit} { break }
            }
        }

        dict set lPlaced "$lSx,$lSy" [dict get $p number]
        # Body end: keep the pin perpendicular to the body edge, one grid long.
        set lSbx [expr {$lSx - [lindex $lO 0] * $GRID}]
        set lSby [expr {$lSy - [lindex $lO 1] * $GRID}]
        dict set lResult [dict get $p number] [list $lSx $lSy $lSbx $lSby]
    }

    dict set lReport moved $lMoved
    return [list $lResult $lReport]
}

# value % GRID == 0, for floats. TCL's % is integer-only, so use fmod. Only the
# comparison against zero matters, and -0.0 == 0, so the sign convention
# difference between fmod and Python's floored % is irrelevant here.
proc lceda::onGrid {pValue} {
    variable GRID
    return [expr {fmod(double($pValue), $GRID) == 0}]
}

# OrCAD rejects duplicate pin names; every duplicate gets an incrementing
# suffix. *Every* one of them is suffixed (GND1/GND2/GND3) with no bare GND
# left over -- a mix is harder to read. Empty names fall back to the pin number.
# Returns a dict of pin number -> display name.
proc lceda::dedupeNames {pPins} {
    set lCounts [dict create]
    foreach p $pPins {
        set lN [dict get $p name]
        dict incr lCounts $lN
    }
    set lSeen [dict create]
    set lOut [dict create]
    foreach p $pPins {
        set lN [dict get $p name]
        set lNum [dict get $p number]
        set lBase $lN
        if {$lBase eq ""} { set lBase "P$lNum" }
        if {[dict exists $lCounts $lN] && [dict get $lCounts $lN] > 1} {
            dict incr lSeen $lN
            dict set lOut $lNum "$lBase[dict get $lSeen $lN]"
        } else {
            dict set lOut $lNum $lBase
        }
    }
    return $lOut
}

# Rewrite pin coordinates in place: body end on the body edge, connect end
# extended out by the full PIN_LENGTH.
#
# LCEDA pin lengths vary wildly and snapping may have shifted them. Capture
# positions the pin number from the pin line length, so normalising to the same
# 3-grid length as the stock libraries is what puts the numbers where a native
# part has them. The coordinate perpendicular to the pin keeps its snapped value
# (including any collision shift); only the along-axis coordinate changes.
proc lceda::attachPins {pSnappedVar pPins pBody} {
    upvar 1 $pSnappedVar lSnapped
    variable PIN_LENGTH
    lassign $pBody lX1 lY1 lX2 lY2
    set lEdge [dict create LEFT $lX1 RIGHT $lX2 TOP $lY1 BOTTOM $lY2]
    set lSign [dict create LEFT -1 RIGHT 1 TOP -1 BOTTOM 1]
    foreach p $pPins {
        set lNum [dict get $p number]
        if {![dict exists $lSnapped $lNum]} { continue }
        set lSide [dict get $p side]
        if {![dict exists $lEdge $lSide]} { continue }
        lassign [dict get $lSnapped $lNum] lCx lCy lBx lBy
        set lE [dict get $lEdge $lSide]
        set lS [dict get $lSign $lSide]
        if {$lSide eq "LEFT" || $lSide eq "RIGHT"} {
            dict set lSnapped $lNum \
                [list [expr {$lE + $lS * $PIN_LENGTH}] $lCy $lE $lCy]
        } else {
            dict set lSnapped $lNum \
                [list $lCx [expr {$lE + $lS * $PIN_LENGTH}] $lCx $lE]
        }
    }
}

proc lceda::bbox {pCoords} {
    if {![llength $pCoords]} { return {0 0 0 0} }
    set lXs {} ; set lYs {}
    foreach c $pCoords { lappend lXs [lindex $c 0] ; lappend lYs [lindex $c 1] }
    set lXs [lsort -real $lXs]
    set lYs [lsort -real $lYs]
    return [list [lindex $lXs 0] [lindex $lYs 0] [lindex $lXs end] [lindex $lYs end]]
}

# Build the full library XML. Returns {xml reportsDict}, reportsDict keyed by
# lcsc. pOlbPath is the full path of the target .olb -- Lib/Defn's name uses it,
# not a library nickname.
proc lceda::buildLibXml {pSymbols {pOlbPath "lceda.olb"}} {
    variable GRID
    variable DEFAULT_PIN_TYPE
    set lOut {}
    set lReports [dict create]

    lappend lOut {<?xml version="1.0" encoding="UTF-8" standalone="no" ?>}
    lappend lOut "<Lib>"
    lappend lOut "  <Defn name=[lceda::quoteattr $pOlbPath]/>"
    # Font table: two stock Cadence libraries export the same 24 entries. Capture
    # computes pin-number placement from the font metrics, so without this table
    # it falls back to the app default font and the numbers sit too far out.
    lappend lOut "  <DefaultValues>"
    lappend lOut "    <Defn/>"
    for {set i 0} {$i < 24} {incr i} {
        if {$i == 13} {
            set lH -9 ; set lW 5 ; set lFont "Courier New"
        } elseif {$i == 3 || $i == 4 || $i >= 17} {
            set lH 8 ; set lW 0 ; set lFont "Arial"
        } else {
            set lH -9 ; set lW 4 ; set lFont "Arial"
        }
        lappend lOut "    <DefaultFont><Defn charset=\"0\" escapement=\"0\" height=\"$lH\" index=\"$i\" italic=\"0\" name=\"$lFont\" orientation=\"0\" weight=\"400\" width=\"$lW\"/></DefaultFont>"
    }
    lappend lOut "  </DefaultValues>"

    set lStamp [clock seconds]
    foreach lSym $pSymbols {
        lappend lOut {*}[lceda::buildPackage $lSym $lStamp lReports]
    }

    lappend lOut "</Lib>"
    return [list "[join $lOut \n]\n" $lReports]
}

proc lceda::buildPackage {pSym pStamp pReportsVar} {
    variable GRID
    variable DEFAULT_PIN_TYPE
    upvar 1 $pReportsVar lReports
    set o {}
    set lPins [dict get $pSym pins]

    lassign [lceda::snapPins $lPins] lSnapped lReport
    set lNames [lceda::dedupeNames $lPins]
    set lRenamed 0
    foreach p $lPins {
        if {[dict get $lNames [dict get $p number]] ne [dict get $p name]} { incr lRenamed }
    }
    dict set lReport renamed $lRenamed

    lappend o "  <Package>"
    # alphabeticNumbering is not a boolean; the schema types it xs:long. Exporting
    # PassiveFilter.olb to XML showed all 29 packages with alphabeticNumbering="2"
    # plus isHomogeneous="1": 2 is the single-section part with no section suffix.
    # 0 renders as U1-1 and 1 as U1A, both wrong.
    lappend o "    <Defn alphabeticNumbering=\"2\" isHomogeneous=\"1\" name=[lceda::quoteattr [dict get $pSym name]] pcbFootprint=[lceda::quoteattr [dict get $pSym footprint]] pcbLib=\"\" refdesPrefix=[lceda::quoteattr [lceda::refdesPrefix $pSym]] timestamp=\"$pStamp\" timezone=\"0\"/>"
    lappend o "    <LibPart>"
    lappend o "      <Defn CellName=[lceda::quoteattr [dict get $pSym name]]/>"
    lappend o "      <NormalView>"
    lappend o "        <Defn suffix=\".Normal\"/>"

    # Body outline: prefer LCEDA's rectangle, fall back to the pin extent.
    set lBody {}
    set lRects [dict get $pSym rects]
    if {[llength $lRects]} {
        set r [lindex $lRects 0]
        # floor/ceil outward so a short rectangle (an 0603 resistor body is only
        # 8 units tall) is not rounded flat into a line.
        lassign [dict get $lReport translate] lTx lTy
        set lBody [list \
            [lceda::floorG [expr {[dict get $r x] + $lTx}]] \
            [lceda::floorG [expr {[dict get $r y] + $lTy}]] \
            [lceda::ceilG [expr {[dict get $r x] + [dict get $r width] + $lTx}]] \
            [lceda::ceilG [expr {[dict get $r y] + [dict get $r height] + $lTy}]]]
    } elseif {[dict size $lSnapped]} {
        set lBx {} ; set lBy {}
        dict for {k v} $lSnapped { lappend lBx [lindex $v 2] ; lappend lBy [lindex $v 3] }
        set lBx [lsort -real $lBx] ; set lBy [lsort -real $lBy]
        set lBody [list [lindex $lBx 0] [lindex $lBy 0] [lindex $lBx end] [lindex $lBy end]]
    }

    # Move the origin to the body's top-left corner: every stock Cadence library
    # has a non-negative bbox (x0..N y0..M) with the origin there, so the part
    # grows down and right from the insertion point. With the origin mid-body the
    # part hangs above the insertion point and hits the top of the sheet.
    # Attach the pins to the body edge first, then move the origin, so the offset
    # applies to the final coordinates.
    if {[llength $lBody]} {
        lceda::attachPins lSnapped $lPins $lBody
        set lOffx [expr {-[lindex $lBody 0]}]
        set lOffy [expr {-[lindex $lBody 1]}]
        if {$lOffx != 0 || $lOffy != 0} {
            set lBody [list 0 0 [expr {[lindex $lBody 2] + $lOffx}] \
                                [expr {[lindex $lBody 3] + $lOffy}]]
            dict for {k v} $lSnapped {
                lassign $v cx cy bx by
                dict set lSnapped $k [list [expr {$cx + $lOffx}] [expr {$cy + $lOffy}] \
                                           [expr {$bx + $lOffx}] [expr {$by + $lOffy}]]
            }
            dict set lReport origin [list $lOffx $lOffy]
        }
    }

    # SymbolBBox frames the body only, not the protruding pins -- every stock
    # Cadence library does this (MICROPHONE's bbox is x0..20 with the pin hotpt at
    # x=-30, outside it). Capture uses this box to find the body interior when
    # placing pin names; too large a box pushes the names outside the body.
    if {[llength $lBody]} {
        lassign $lBody lBx1 lBy1 lBx2 lBy2
    } else {
        set lC {}
        dict for {k v} $lSnapped { lappend lC [list [lindex $v 2] [lindex $v 3]] }
        lassign [lceda::bbox $lC] lBx1 lBy1 lBx2 lBy2
    }

    # Refdes stays one grid above the body; Value sits at the body's lower edge.
    foreach lPair [list [list "Part Reference" [expr {$lBy1 - $GRID}]] \
                        [list "Value" $lBy2]] {
        lassign $lPair lPropName lLocY
        lappend o "        <SymbolDisplayProp>"
        lappend o "          <Defn locX=\"$lBx1\" locY=\"$lLocY\" name=[lceda::quoteattr $lPropName] rotation=\"0\" textJustification=\"0\"/>"
        lappend o "          <PropFont>"
        lappend o "            <Defn charset=\"0\" escapement=\"0\" height=\"-9\" italic=\"0\" name=\"\" orientation=\"0\" weight=\"400\" width=\"4\"/>"
        lappend o "          </PropFont>"
        lappend o "          <PropColor><Defn val=\"48\"/></PropColor>"
        lappend o "          <PropDispType><Defn ValueIfValueExist=\"0\" val=\"1\"/></PropDispType>"
        lappend o "        </SymbolDisplayProp>"
    }

    lappend o "        <SymbolColor><Defn val=\"48\"/></SymbolColor>"
    lappend o "        <SymbolBBox>"
    lappend o "          <Defn x1=\"$lBx1\" x2=\"$lBx2\" y1=\"$lBy1\" y2=\"$lBy2\"/>"
    lappend o "        </SymbolBBox>"
    lappend o "        <IsPinNumbersVisible><Defn val=\"1\"/></IsPinNumbersVisible>"
    # Pin names on the top and bottom sides rotate 90 degrees with the pin; all
    # six packages in the stock Cadence libraries use 1.
    lappend o "        <IsPinNamesRotated><Defn val=\"1\"/></IsPinNamesRotated>"
    lappend o "        <IsPinNamesVisible><Defn val=\"1\"/></IsPinNamesVisible>"
    lappend o "        <ContentsLibName><Defn name=\"\"/></ContentsLibName>"
    lappend o "        <ContentsViewName><Defn name=\"\"/></ContentsViewName>"
    lappend o "        <ContentsViewType><Defn type=\"0\"/></ContentsViewType>"
    lappend o "        <PartValue><Defn name=[lceda::quoteattr [dict get $pSym name]]/></PartValue>"
    lappend o "        <Reference><Defn name=[lceda::quoteattr [lceda::refdesPrefix $pSym]]/></Reference>"

    # Body outline as 4 Lines: Cadence never writes a Rect under NormalView.
    if {[llength $lBody]} {
        lassign $lBody x1 y1 x2 y2
        foreach lSeg [list [list $x1 $y1 $x2 $y1] [list $x2 $y1 $x2 $y2] \
                           [list $x2 $y2 $x1 $y2] [list $x1 $y2 $x1 $y1]] {
            lassign $lSeg lx1 ly1 lx2 ly2
            lappend o "        <Line>"
            lappend o "          <Defn lineStyle=\"0\" lineWidth=\"0\" x1=\"$lx1\" x2=\"$lx2\" y1=\"$ly1\" y2=\"$ly2\"/>"
            lappend o "        </Line>"
        }
    }

    # LCEDA polylines become one Line per segment.
    lassign [dict get $lReport translate] lTx lTy
    lassign [dict get $lReport origin] lOx2 lOy2
    foreach lPoly [dict get $pSym polylines] {
        set lPts {}
        foreach pt [dict get $lPoly points] {
            lappend lPts [list \
                [expr {[lceda::snap [expr {[lindex $pt 0] + $lTx}]] + $lOx2}] \
                [expr {[lceda::snap [expr {[lindex $pt 1] + $lTy}]] + $lOy2}]]
        }
        for {set i 0} {$i < [llength $lPts] - 1} {incr i} {
            lassign [lindex $lPts $i] px1 py1
            lassign [lindex $lPts [expr {$i + 1}]] px2 py2
            if {$px1 == $px2 && $py1 == $py2} { continue }
            lappend o "        <Line>"
            lappend o "          <Defn lineStyle=\"0\" lineWidth=\"0\" x1=\"$px1\" x2=\"$px2\" y1=\"$py1\" y2=\"$py2\"/>"
            lappend o "        </Line>"
        }
    }

    set lIndex 0
    foreach p $lPins {
        lassign [dict get $lSnapped [dict get $p number]] cx cy bx by
        lappend o "        <SymbolPinScalar>"
        lappend o "          <Defn hotptX=\"$cx\" hotptY=\"$cy\" name=[lceda::quoteattr [dict get $lNames [dict get $p number]]] position=\"$lIndex\" startX=\"$bx\" startY=\"$by\" type=\"$DEFAULT_PIN_TYPE\" visible=\"1\"/>"
        # All 9 boolean children must be present or XMATIC rejects the whole library.
        foreach lTV [list [list IsLong 1] \
                          [list IsClock [expr {[dict get $p clock] ? 1 : 0}]] \
                          [list IsDot [expr {[dict get $p dot] ? 1 : 0}]] \
                          [list IsLeftPointing 0] [list IsRightPointing 0] \
                          [list IsNetStyle 0] [list IsNoConnect 0] [list IsGlobal 0] \
                          [list IsNumberVisible [expr {[dict get $p numberVisible] ? 1 : 0}]]] {
            lassign $lTV lTag lVal
            lappend o "          <$lTag><Defn val=\"$lVal\"/></$lTag>"
        }
        lappend o "        </SymbolPinScalar>"
        incr lIndex
    }

    lappend o "      </NormalView>"

    # Physical pin-number map: PhysicalPart is NormalView's sibling, inside LibPart.
    lappend o "      <PhysicalPart>"
    lappend o "        <Defn/>"
    set lIndex 0
    foreach p $lPins {
        lappend o "        <PinNumber>"
        lappend o "          <Defn number=[lceda::quoteattr [dict get $p number]] position=\"$lIndex\"/>"
        lappend o "        </PinNumber>"
        incr lIndex
    }
    lappend o "      </PhysicalPart>"
    lappend o "    </LibPart>"
    lappend o "  </Package>"

    dict set lReports [dict get $pSym lcsc] $lReport
    return $o
}


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
set ::lceda2orcadVersion "1.3.7"

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
    set lSyms {}
    set ::lcedaPkgs {}
    array unset ::lcedaByLcsc
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

# Drop our .olb from Capture's session if it is open.
#
# This is what makes the SECOND placement work. PlacePartEx leaves the library
# open in the session, but we rebuild the .olb from scratch on every add -- so
# the next round has Capture holding a DboLib for a file we just deleted and
# replaced. Placement then either fails or hangs on a modal error.
#
# Cadence's own scripts treat this as a hard precondition rather than something
# to recover from: capLibPropUtil.tcl:99 and capLibUtil.tcl:147 both call
# GetOpenLib first and refuse to touch a library that is open. We can't refuse,
# so we close it instead -- GetOpenLib (never GetLib, which would open it) then
# RemoveLib, the pairing capRev.tcl:92 uses.
#
# A library must be unloaded before its file is deleted or overwritten.
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

    # Close it before deleting, or Capture keeps a handle to a library whose
    # file is gone. See lceda2orcadCloseOlb.
    if {![lceda2orcadCloseOlb]} {
        puts "lceda2orcad: cannot unload the generated library from Capture; close it in the current session and retry"
        return 0
    }

    # The 3-argument form of XML2OLB appends rather than overwrites, so a stale
    # .olb would accumulate duplicate packages. Delete it first.
    set lOlbPath [lceda2orcadOlbPath]
    if {[file exists $lOlbPath]} {
        if {[catch {file delete -force $lOlbPath} lErr]} {
            puts "lceda2orcad: cannot replace $lOlbPath ($lErr)"
            puts "lceda2orcad: close the library in Capture and retry"
            return 0
        }
        if {[file exists $lOlbPath]} {
            puts "lceda2orcad: library still exists after delete: $lOlbPath"
            return 0
        }
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

proc lceda2orcadPlace {pPkg {pPropNames {}} {pPropValues {}}} {
    set lFrame [DboTclHelper_sGetConstCharPtr [capGetMostRecentSchFrameID]]
    if {[catch {ui::SchematicActivate $lFrame}]} {
        puts "lceda2orcad: no active schematic page -- open one and retry"
        return 0
    }
    if {![llength [info commands PlacePartEx]]} {
        puts "lceda2orcad: PlacePartEx is not registered in this Capture build"
        return 0
    }

    set lBase [list $::lcedaOlb $pPkg "" 0 $pPropNames $pPropValues]
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
proc lceda2orcadAdd {pLcsc} {
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
    puts "lceda2orcad: placing $lPkg"
    return [lceda2orcadPlace $lPkg]
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
    if {[lceda2orcadAdd $lLcsc]} {
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
    wm title $lForm "\u7acb\u521bEDA\u8f6cOrCAD"
    wm resizable $lForm 0 0

    label  $lForm.lbl -text "\u7acb\u521b\u7f16\u53f7\uff1a"
    entry  $lForm.in -width 18 -textvariable ::lceda2orcadEntry
    button $lForm.go -text "\u6dfb\u52a0" -width 10 -command lceda2orcadDialogRun
    button $lForm.cb -text "\u4ece\u526a\u8d34\u677f\u7c98\u8d34" -command lceda2orcadDialogPaste
    label  $lForm.st -textvariable ::lceda2orcadStatus -anchor w -width 44

    grid $lForm.lbl -row 0 -column 0 -sticky w  -padx 6 -pady 6
    grid $lForm.in  -row 0 -column 1 -sticky we -padx 6 -pady 6
    grid $lForm.go  -row 0 -column 2 -padx 6 -pady 6
    grid $lForm.cb  -row 1 -column 1 -sticky we -padx 6 -pady {0 6}
    grid $lForm.st  -row 2 -column 0 -columnspan 3 -sticky we -padx 6 -pady {0 6}

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
        puts "\u7acb\u521bEDA\u8f6cOrCAD\uff1a\u7f13\u5b58\u5143\u4ef6\u5e93\u6587\u4ef6\u4e0d\u5b58\u5728\uff0c\u65e0\u9700\u6e05\u9664\u3002"
        return 1
    }

    if {![lceda2orcadCloseOlb]} {
        puts "\u7acb\u521bEDA\u8f6cOrCAD\uff1aCapture \u4e2d\u7684\u5668\u4ef6\u5e93\u65e0\u6cd5\u5378\u8f7d\uff0c\u672a\u5220\u9664\u6587\u4ef6\u3002"
        puts "\u8bf7\u5173\u95ed Capture \u4e2d\u6253\u5f00\u7684\u7acb\u521b\u5668\u4ef6\u5e93\u540e\u91cd\u8bd5\u3002"
        return 0
    }
    if {[catch {file delete -force $lOlbPath} lErr]} {
        puts "\u7acb\u521bEDA\u8f6cOrCAD\uff1a\u65e0\u6cd5\u6e05\u9664\u7f13\u5b58\u5143\u4ef6\u5e93 $lOlbPath\uff1a$lErr"
        puts "\u8bf7\u786e\u8ba4\u8be5\u5e93\u672a\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\u540e\u91cd\u8bd5\u3002"
        return 0
    }
    if {[file exists $lOlbPath]} {
        puts "\u7acb\u521bEDA\u8f6cOrCAD\uff1a\u5220\u9664\u547d\u4ee4\u5df2\u6267\u884c\uff0c\u4f46\u6587\u4ef6\u4ecd\u5b58\u5728\uff1a$lOlbPath"
        puts "\u8bf7\u5173\u95ed\u5176\u4ed6\u5360\u7528\u8be5\u5e93\u7684\u7a0b\u5e8f\u540e\u91cd\u8bd5\u3002"
        return 0
    }
    puts "\u7acb\u521bEDA\u8f6cOrCAD\uff1a\u5df2\u5220\u9664\u5e93\u6587\u4ef6 $lOlbPath"
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
