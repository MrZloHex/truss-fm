; main.pl -- pluf: a file manager and picker. The frame, top to bottom: the
; title bar, the path, the four columns, the tasks, the keys

USE <std/os/args.pl>
USE <std/io/io.pl>
USE <std/alloc/alloc.pl>
USE <std/core/result.pl>

USE <modular.pl>
USE <look.pl>

!USES <app.pl>
!USES <ui/places.pl>
!USES <ui/root.pl>
!USES <ui/main.pl>
!USES <ui/preview.pl>

CONST @CONST C1 TABS{} = [ "[1] logs" | "[2] dotfiles" | "[3] downloads" ]
CONST I32 NTABS = COUNT [ TABS ]

; § FILES, the tabs, and at the far end the disk
ABYSS top_bar: [ @Ui ui | @App a ]
 | @Node bar = (ui.row)[ GROW | 1 ]
 | (bar.spacing)[ 1 ]
 | (bar.background)[ BAR ]
 |
 | (ui.text)[ FIT | 1 ]
 | (ui.put)[ (bold)[ AMBER ] | "§ FILES" ]
 | (ui.space)[ 4 | 1 ]
 |
 | FOR [ I32 i = 0 | i < NTABS | i += 1 ]
 |  | U32 id = (ui.idn)[ "tab" | i ]
 |  | B1 on = a.tab == i
 |  | @Node t = (ui.text)[ FIT | 1 ]
 |  | (t.with_id)[ id ]
 |  | (t.pad)[ 1 | 0 ]
 |  | (t.background)[ SELECT [ on | AMBER | SEL ] ]
 |  | (ui.cursor_on)[ id | CUR_HAND ]
 |  | (ui.put)[ (fg)[ SELECT [ on | INK | TEXT2 ] ] | TABS{i} ]
 |  | IF [ (ui.clicked)[ id ] ]
 |  |  | a.tab = i
 |  |  \_
 |  \_
 |
 | @Node disk = (ui.text)[ GROW | 1 ]
 | (disk.text_align)[ AL_END ]
 | (ui.put)[ (fg)[ TEXT ] | (a.partition.name.cstr)[] ]
 | (ui.put)[ (fg)[ DIM ] | " " ]
 | ((ui.pen)[ (bold)[ (disk_color)[ a.partition.usage AS I32 ] ] ].print)[ "%.0f%%" | a.partition.usage AS F64 ]
 | ((ui.pen)[ (fg)[ DIM ] ].print)[ " · free %.0f GB " | a.partition.free ]
 | (ui.close)[]
 \_

; > the path, and at the far end its keys
ABYSS path_bar: [ @Ui ui | @App a ]
 | @Node bar = (ui.row)[ GROW | 1 ]
 | (bar.spacing)[ 1 ]
 | (ui.space)[ 1 | 1 ]
 |
 | (ui.text)[ FIT | 1 ]
 | (ui.put)[ (fg)[ AMBER ] | "> " ]
 | (ui.put)[ (fg)[ TEXT ] | (a.rel_cwd.cstr)[] ]
 | (ui.space)[ 4 | 1 ]
 |
 | @Node keys = (ui.text)[ GROW | 1 ]
 | (keys.text_align)[ AL_END ]
 | (ui.put)[ (fg)[ DIM ] | "[ctrl-l] path · [/] filter · [~] home" ]
 | (ui.space)[ 1 | 1 ]
 | (ui.close)[]
 \_

ABYSS tasks_bar: [ @Ui ui | @App a ]
 | (ui.box)[ "TASKS" | GROW | 3 ]
 | (ui.close)[]
 \_

ABYSS hotkey: [ @Ui ui | @CONST C1 key | @CONST C1 what ]
 | (ui.put)[ (fg)[ AMBER ] | key ]
 | (ui.put)[ (fg)[ TEXT ] | what ]
 \_

ABYSS hotkeys: [ @Ui ui | @App a ]
 | (ui.text)[ GROW | 1 ]
 | (hotkey)[ ui | " [hjkl]" | " move   " ]
 | (hotkey)[ ui | "[space]" | " mark   " ]
 | (hotkey)[ ui | "[q]" | " quit" ]
 \_

B1 frame: [ @Ui ui | @App a ]
 | ; the columns size their lists by where those were in the last frame, as
 | ; the layout is known only once a frame is built. On a new screen size --
 | ; the first frame, a resize -- that is stale: build one more at once
 | IF [ ui.cols != a.cols || ui.rows != a.rows ]
 |  | a.cols = ui.cols
 |  | a.rows = ui.rows
 |  | (ui.redo)[]
 |  \_
 |
 | (ui.column)[ GROW | GROW ]
 | (top_bar)[ ui | a ]
 | (path_bar)[ ui | a ]
 |
 | (ui.row)[ GROW | GROW ]
 | (places_pane)[ ui | @(a.places) ]
 | (root_pane)[ ui | @(a.root) | (a.cwd.cstr)[] ]
 | (main_pane)[ ui | @(a.listing) | (a.cwd.cstr)[] ]
 | (preview_pane)[ ui | @(a.preview) | @(a.listing) ]
 | (ui.close)[]
 |
 | (tasks_bar)[ ui | a ]
 | (hotkeys)[ ui | a ]
 | (ui.close)[]
 |
 | RET [ !(ui.shortcut)[ "q" ] ]
 \_

I32 main: [ I32 argc | @@C1 argv ]
 | (stdout.print)[ "PROLIFE\n" ]
 | Args args = (Args.over)[ argc | argv ]
 | @CONST C1 path = "."
 | IF [ (args.size)[] > 1 ]
 |  | path = (args.get)[ 1 ]
 |  \_
 |
 | Result<String | IoError> cwd = (get_realpath)[ path ]
 | IF [ (cwd.is_err)[] ]
 |  | RET [ -1 ]
 |  \_
 | App a = (App.make)[ (cwd.unwrap)[] ]
 | POSTLUDE (a.dispose)[]
 |
 | (stdout.print)[ "Current path `%s`\n" | (a.cwd.cstr)[] ]
 | (stdout.print)[ "Relative path `%s`\n" | (a.rel_cwd.cstr)[] ]
 |
 | AppConfig cfg = [ .title = "PLUF" | .focus = "main" | .theme = (app_theme)[] ]
 | (app_run<App>)[ @cfg | argc | argv | frame | @a ]
 | RET [ 0 ]
 \_


