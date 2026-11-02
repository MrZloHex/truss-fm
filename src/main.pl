
USE <std/os/args.pl>
USE <std/io/io.pl>
USE <std/alloc/alloc.pl>
USE <std/core/result.pl>

USE <modular.pl>
USE <look.pl>

!USES <app.pl>


CONST @CONST C1 TABS{} = [ "[1] logs" | "[2] dotfiles" | "[3] downloads" ]

ABYSS top_bar: [ @Ui ui | @App a ]
 | @Node top_bar = (ui.row)[ GROW | 1 ]
 | (top_bar.spacing)[ 1 ]
 | (top_bar.background)[ BAR ]
 |  (ui.text)[ FIT | 1 ] 
 |   (ui.put)[ (bold)[AMBER] | "§ FILES" ]
 |  (ui.space)[ 4 | 1 ]
 | FOR [ I32 i = 0 | i < 3 | i += 1 ]
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
 | @Node right = (ui.text)[ GROW | 1 ]
 | (right.text_align)[ AL_END ]
 | (ui.put)[ (fg)[ TEXT ] | (a.partition.name.cstr)[] ]
 | (ui.put)[ (fg)[ DIM ] | " " ]
 | ((ui.pen)[ (bold)[ (disk_color)[ a.partition.usage AS I32 ] ] ].print)[ "%.0f%%" | a.partition.usage AS F64 ]
 | ((ui.pen)[ (fg)[ DIM ] ].print)[ " · free %.0f GB " | a.partition.free ]
;| (ui.space)[ 2 | 1 ]
 | (ui.close)[]
 \_
 
ABYSS subtop_bar: [ @Ui ui | @App a ]
 | @Node bar = (ui.row)[ GROW | 1 ]
 | (bar.spacing)[ 1 ]
 | (ui.space)[ 1 | 1 ]
 |  (ui.text)[ FIT | 1 ] 
 |   (ui.put)[ (fg)[AMBER] | "> " ]
 |   (ui.put)[ (fg)[TEXT]  | (a.rel_cwd.cstr)[] ]
 |  (ui.space)[ 4 | 1 ]
 |
 | @Node right = (ui.text)[ GROW | 1 ]
 | (right.text_align)[ AL_END ]
 | (ui.put)[ (fg)[ DIM ] | "[ctrl-l] path · [/] filter · [~] home" ]
 | (ui.space)[ 1 | 1 ]
 | (ui.close)[]
 \_

ABYSS places_pane: [ @Ui ui | @App a ]
 | (ui.box)[ "PLACES" | (pct)[15] | GROW ]
 |  
 | (ui.close)[]
 |
 \_

ABYSS root_pane: [ @Ui ui | @App a ]
 | (ui.box)[ "QWE" | (pct)[20] | GROW ]
 | 
 | (ui.close)[]
 \_

ABYSS main_pane: [ @Ui ui | @App a ]
 | (ui.box)[ "MAIN" | GROW | GROW ]
 | 
 | (ui.close)[]
 \_

ABYSS preview_pane: [ @Ui ui | @App a ]
 | (ui.box)[ "Preview" | (pct)[20] | GROW ]
 | 
 | (ui.close)[]
 \_

ABYSS tasks_bar: [ @Ui ui | @App a ]
 | (ui.box)[ "TASKS" | GROW | 3 ]
 | (ui.close)[]
 \_

ABYSS hotkeys: [ @Ui ui | @App a ]
 | (ui.text)[ GROW | 1 ]
 | (ui.put)[ (fg)[ AMBER ] | " [hjkl]" ]
 | (ui.put)[ (fg)[ TEXT ] | " move   " ]
 | (ui.put)[ (fg)[ AMBER ] | "[space]" ]
 | (ui.put)[ (fg)[ TEXT ] | " mark   " ]
 | (ui.put)[ (fg)[ AMBER ] | "[q]" ]
 | (ui.put)[ (fg)[ TEXT ] | " quit" ]
 \_

B1 frame: [ @Ui ui | @App a ]
 | 
 | (ui.column)[ GROW | GROW ]
 | (top_bar)[ ui | a ]
 | (subtop_bar)[ ui | a ]
 | @Node body = (ui.row)[ GROW | GROW ]

 | (places_pane)[ ui | a ]
 | (root_pane)[ ui | a ]
 | (main_pane)[ ui | a ]
 | (preview_pane)[ ui | a ]
 
 | (ui.close)[]

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
 | Result<String | IoError> r_cwd = (get_realpath)[ path ]
 | IF [ (r_cwd.is_err)[] ]
 |  | RET [ -1 ]
 |  \_
 
 | 
 |
 | App a = (App.make)[ (r_cwd.unwrap)[] ]
 | POSTLUDE (a.dispose)[]
 |
 | (stdout.print)[ "Current path `%s`\n" | (a.cwd.cstr)[] ]
 | (stdout.print)[ "Relative path `%s`\n" | (a.rel_cwd.cstr)[] ]

 | AppConfig cfg = [ .title = "PLUF" | .focus = "tasks" | .theme = (app_theme)[] ]
 | (app_run<App>)[ @cfg | argc | argv | frame | @a ]
 |
 | RET [ 0 ]
 \_
