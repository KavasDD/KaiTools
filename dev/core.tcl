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
