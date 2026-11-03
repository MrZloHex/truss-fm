; files.pl -- what the file keys do to App: y and d fill the clipboard, p
; pastes it as a task, D asks and deletes as a task, r renames and n makes
; a folder through the prompt. They work on main_selection: the rows chosen
; with V, or the file under the cursor

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

USE <modular.pl>
!USES <app.pl>
!USES <../core/fs.pl>
!USES <../core/tasks.pl>
!USES <../core/config.pl>
!USES <../ui/main.pl>

; the rows chosen in visual, or the file under the cursor, into the clipboard; `cut`: the
; paste moves them
ABYSS file_yank: [ @AppData me | B1 cut ]
 | (strings_clear)[ @(me.clip) ]
 | (main_selection)[ @(me.listing) | @(me.clip) ]
 | me.clip_cut = cut
 | C1 s{64}
 | BufferSink b = (BufferSink.over)[ s | 64 ]
 | (b.print)[ "%d %s" | (me.clip.size)[] AS I32 | SELECT [ cut | "to move" | "copied" ] ]
 | (app_note)[ me | s AS @CONST C1 ]
 \_

; what the clipboard holds, copied or moved here, as a task
ABYSS file_paste: [ @AppData me ]
 | IF [ (me.clip.size)[] == 0 ]
 |  | (app_note)[ me | "nothing to paste: y copies, d cuts" ]
 |  | RET []
 |  \_
 | (me.tasks.push)[ (task_transfer)[ me.clip_cut | @(me.clip) | (me.cwd.cstr)[] ] ]
 | IF [ me.clip_cut ]
 |  | (strings_clear)[ @(me.clip) ]
 |  \_
 \_

; the rows chosen in visual, or the file under the cursor, asked about before they go
ABYSS file_ask_delete: [ @AppData me ]
 | (strings_clear)[ @(me.pending) ]
 | (main_selection)[ @(me.listing) | @(me.pending) ]
 | IF [ (me.pending.size)[] > 0 ]
 |  | me.prompt = PR_DELETE
 |  | IF [ !(CFG.confirm_delete) ]
 |  |  | (file_delete_now)[ me ]
 |  |  \_
 |  \_
 \_

ABYSS file_delete_now: [ @AppData me ]
 | (me.tasks.push)[ (task_delete)[ @(me.pending) ] ]
 | (strings_clear)[ @(me.pending) ]
 | me.prompt = PR_NONE
 \_

; the file under the cursor asked a new name, its own to begin with
ABYSS file_ask_rename: [ @AppData me ]
 | String path = (main_path)[ @(me.listing) | me.listing.table.list.cursor ]
 | IF [ (path.size)[] == 0 ]
 |  | (path.deinit)[]
 |  | RET []
 |  \_
 | (me.renaming.deinit)[]
 | me.renaming = path
 | String name = (get_dirname)[ (path.cstr)[] ]
 | (input_set)[ @(me.field) | (name.cstr)[] ]
 | (name.deinit)[]
 | me.prompt = PR_RENAME
 \_

ABYSS file_ask_mkdir: [ @AppData me ]
 | (input_set)[ @(me.field) | "" ]
 | me.prompt = PR_MKDIR
 \_

; what was typed, done: the rename or the new folder
ABYSS file_prompt_done: [ @AppData me | @CONST C1 name ]
 | Prompt was = me.prompt
 | me.prompt = PR_NONE
 | IF [ !((name_ok)[ name ]) ]
 |  | (app_note)[ me | "not a name: no / and not . or .." ]
 |  | RET []
 |  \_
 | String to = (join_path)[ (me.cwd.cstr)[] | name ]
 | POSTLUDE (to.deinit)[]
 | IF [ was == PR_RENAME && (me.renaming.equals)[ (to.cstr)[] ] ]
 |  | RET []
 |  \_
 | IF [ ((fs_link_info)[ (to.cstr)[] ].is_ok)[] ]
 |  | (app_note)[ me | "that name is taken here" ]
 |  | RET []
 |  \_
 | ; not SELECT: it would do both
 | Result<B1 | IoError> r
 | IF [ was == PR_RENAME ]
 |  | r = (fs_rename)[ (me.renaming.cstr)[] | (to.cstr)[] ]
 | ELSE
 |  | r = (fs_make_dir)[ (to.cstr)[] ]
 |  \_
 | IF [ (r.is_err)[] ]
 |  | (app_note)[ me | (io_error_text)[ (r.error)[] ] ]
 |  | RET []
 |  \_
 | ; the cursor goes to it, where the folder is read again
 | (app_refresh)[ me | TRUE ]
 | (read_folder)[ @(me.listing.files) | (me.cwd.cstr)[] | CFG.hidden | "" ]
 | (main_sort)[ @(me.listing) ]
 | me.listing.table.list.cursor = (main_find)[ @(me.listing) | name | me.listing.table.list.cursor ]
 | me.listing.stale = FALSE
 \_
