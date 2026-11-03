; frame.pl -- one frame of pluf, top to bottom: the bars, the four columns,
; the tasks, the keys. Built again for every event; what lasts is in App

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

USE <modular.pl>
!USES <../ui/look.pl>
!USES <../ui/places.pl>
!USES <../ui/root.pl>
!USES <../ui/main.pl>
!USES <../ui/preview.pl>
!USES <../core/tasks.pl>
!USES <../app/app.pl>
!USES <bars.pl>
!USES <taskbox.pl>
!USES <keys.pl>
!USES <help.pl>

; the tasks' slice of time, and the columns read again as they change the
; disk: now and then while they run, all of it once as they end
ABYSS tick: [ @Ui ui | @App a ]
 | ; the tasks get their slice of time; the columns are read again as they
 | ; change the disk, now and then while they run and once as they end
 | IF [ (a.tasks.size)[] > 0 ]
 |  | B1 changed = (tasks_run)[ @(a.tasks) ]
 |  | B1 busy = (tasks_busy)[ @(a.tasks) ]
 |  | IF [ changed && !busy ]
 |  |  | (app_refresh)[ a | TRUE ]
 |  | ELIF [ changed && (now_ms)[] - a.refreshed > REFRESH_MS ]
 |  |  | (app_refresh)[ a | FALSE ]
 |  |  \_
 |  | (ui.wake_in)[ SELECT [ busy | 1 | 250 ] ]
 |  \_
 | IF [ (a.note.size)[] > 0 && (now_ms)[] - a.note_at < NOTE_MS ]
 |  | (ui.wake_in)[ 500 ]
 |  \_
 |
 \_

B1 frame: [ @Ui ui | @App a ]
 | IF [ ui.cols != a.cols || ui.rows != a.rows ]
 |  | a.cols = ui.cols
 |  | a.rows = ui.rows
 |  | (ui.redo)[]
 |  \_
 | a.clicked{0} = '\0'
 | (tick)[ ui | a ]
 | (keys_first)[ ui | a ]
 |
 | ; a column -- or the path bar -- asks for another folder in `go`; the
 | ; program goes there once all are drawn, and builds the frame again in it
 | String go = (String.of)[ "" ]
 | POSTLUDE (go.deinit)[]
 | I32 want = -1
 | (ui.column)[ GROW | GROW ]
 | (top_bar)[ ui | a | @want ]
 | (path_bar)[ ui | a | @go ]
 | IF [ a.help ]
 |  | (help_screen)[ ui | a ]
 | ELSE
 |  | (ui.row)[ GROW | GROW ]
 |  | (places_pane)[ ui | @(a.places) | (a.cwd.cstr)[] | @go ]
 |  | (root_pane)[ ui | @(a.root) | (a.cwd.cstr)[] | @go ]
 |  | (main_pane)[ ui | @(a.listing) | (a.cwd.cstr)[] | @go ]
 |  | (preview_pane)[ ui | @(a.preview) | @(a.listing) ]
 |  | (ui.close)[]
 |  \_
 |
 | (tasks_bar)[ ui | a ]
 | (status_line)[ ui | a ]
 | (ui.close)[]
 |
 | ; the help open: only what closes it -- q too, which does not quit here
 | IF [ a.help ]
 |  | IF [ (hit)[ ui | a | "?" ] || (ui.take)[ KEY_ESC ] || (ui.take)[ 'q' AS U32 ] ]
 |  |  | a.help = FALSE
 |  |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  | RET [ TRUE ]
 |  \_
 |
 | IF [ (keys_prompt)[ ui | a ] ]
 |  | RET [ TRUE ]
 |  \_
 | (keys_files)[ ui | a ]
 | (keys_move)[ ui | a | @go | want ]
 | ; Q: out, and the shell to this folder -- through the file --cd-file names
 | IF [ (hit)[ ui | a | "Q" ] ]
 |  | IF [ (a.cd_file.size)[] == 0 ]
 |  |  | (app_note)[ a | "Q needs pluf's shell function: eval \"$(pluf --init zsh)\" in your rc" ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | C1 line{4200}
 |  | BufferSink b = (BufferSink.over)[ line | 4200 ]
 |  | (b.print)[ "%s\n" | (a.cwd.cstr)[] ]
 |  | IF [ ((write_file)[ (a.cd_file.cstr)[] | line AS @CONST C1 ].is_err)[] ]
 |  |  | (app_note)[ a | "the --cd-file cannot be written" ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | RET [ FALSE ]
 |  \_
 | RET [ !((hit)[ ui | a | "q" ]) ]
 \_
