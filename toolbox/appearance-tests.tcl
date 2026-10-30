package require Tk
wm withdraw .
set root [file dirname [file normalize [info script]]]
set output [file join $root out skin-validation]
file mkdir $output
set ::env(XIAOKAI_SKIN_SETTINGS) [file join $output capture-test-settings]
source [file join $root .. autoload xiaokaiSchematicPlugins.tcl]
set count 0
proc check {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
    incr ::count
}
proc lceda2orcadMenuFromClip {} { incr ::executed }
set executed 0
check {[xiaokaiSchematicPluginsOpen] == 1} "Window opens in stock Cadence Tk"
set w .xiaokaiSchematicPlugins
update
check {[llength [$w.results.tv children {}]] == 4} "Four functional categories"
set tree $w.results.tv
foreach category {editing signals output checks} {
    check {![$tree item $category -open]} "Categories start collapsed"
    $tree selection set $category
    xiaokaiSchematicPluginsActivate
    check {[$tree item $category -open]} "Enter opens category"
    xiaokaiSchematicPluginsActivate
    check {![$tree item $category -open]} "Enter closes category"
}
check {[$tree item lceda -text] eq "Orcad\u5185\u76f4\u63a5\u653e\u7f6e\u7acb\u521b\u5143\u4ef6"} "Placement renamed"
check {[$tree item bomtool -text] eq "BOM\u8f93\u51fa\u589e\u5f3a\u7248"} "BOM renamed"
check {[$tree item netlocator -text] eq "Signal\u4e00\u952e\u5168\u7f51\u7edc\u9ad8\u4eae"} "Signal renamed"
check {[$tree item textaffix -text] eq "\u4efb\u610f\u4f4d\u7f6e\u6279\u91cf\u524d/\u540e\u6dfb\u52a0\u6587\u5b57"} "Text editing renamed"
check {[$tree parent textaffix] eq "editing" && [$tree parent drctool] eq "checks"} "Tools assigned to functional categories"
update
lassign [$tree bbox editing] x y width height
xiaokaiSchematicPluginsClick [expr {$x+90}] [expr {$y+$height/2}]
check {[$tree item editing -open]} "Category label click opens"
xiaokaiSchematicPluginsClick [expr {$x+90}] [expr {$y+$height/2}]
check {![$tree item editing -open]} "Category label click closes"
check {[$w.run cget -state] eq "disabled"} "No selection cannot execute"
$w.results.tv selection set lceda_clip
xiaokaiSchematicPluginsUpdateSelection
check {[$w.run cget -state] eq "normal"} "Action can execute"
xiaokaiSchematicPluginsRun
check {$executed == 1} "Selected action reaches existing command"
$w.results.tv selection set lceda
check {[xiaokaiSchematicPluginsRun] == 0} "Group is not an action"
check {![winfo exists $w.appearance]} "No skin picker"
check {[::xiaokai::schematicPlugins::readSkin] eq "orcad-a"} "Fixed blue and white appearance"
destroy $w
check {[xiaokaiSchematicPluginsOpen] == 1} "Window can reopen"
check {[::xiaokai::schematicPlugins::readSkin] eq "orcad-a"} "Reopen retains fixed appearance"
wm geometry $w 620x430+80+80
$w.results.tv item editing -open 1
$w.results.tv item lceda -open 1
$w.results.tv selection set lceda_clip
xiaokaiSchematicPluginsUpdateSelection
update
set status [open [file join $output capture-checks.log] w]
puts $status "$count Capture Tk appearance and action checks passed"
close $status
if {[lsearch -exact $argv --check] >= 0} { destroy .; exit 0 }
# Leave the fixed appearance visible for a screenshot.
proc stage {id} {
    ::xiaokai::schematicPlugins::applySkin
    update
    set marker [open [file join $::output capture-ready.txt] w]
    puts $marker "$id [winfo rootx $::w] [winfo rooty $::w] [winfo width $::w] [winfo height $::w]"
    close $marker
}
stage orcad-a
proc poll {} {
    set signal [file join $::output capture-next.txt]
    if {[file exists $signal]} {
        set f [open $signal r]; set command [string trim [read $f]]; close $f
        file delete $signal
        if {$command eq "quit"} { destroy .; exit }
        stage orcad-b
    }
    after 100 poll
}
poll
after 45000 {destroy .; exit}
vwait forever
