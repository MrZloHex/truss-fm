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
!USES <../core/trash.pl>
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

; what the clipboard holds, copied or moved here, as a task. Names taken
; here -- not a copy's own, beside its original -- are asked about first
ABYSS file_paste: [ @AppData me ]
 | IF [ (me.clip.size)[] == 0 ]
 |  | (app_note)[ me | "nothing to paste: y copies, d cuts" ]
 |  | RET []
 |  \_
 | me.clashes = 0
 | FOR [ USIZE i = 0 | i < (me.clip.size)[] | i += 1 ]
 |  | @CONST C1 src = ((me.clip.at)[ i ].cstr)[]
 |  | String up = (get_parent_path)[ src ]
 |  | B1 here = (up.equals)[ (me.cwd.cstr)[] ]
 |  | (up.deinit)[]
 |  | String name = (get_dirname)[ src ]
 |  | String dst = (join_path)[ (me.cwd.cstr)[] | (name.cstr)[] ]
 |  | IF [ !here && (taken)[ (dst.cstr)[] ] ]
 |  |  | IF [ me.clashes == 0 ]
 |  |  |  | (me.clash_one.deinit)[]
 |  |  |  | me.clash_one = (String.of)[ (name.cstr)[] ]
 |  |  |  \_
 |  |  | me.clashes += 1
 |  |  \_
 |  | (name.deinit)[]
 |  | (dst.deinit)[]
 |  \_
 | IF [ me.clashes > 0 ]
 |  | me.prompt = PR_CLASH
 |  | RET []
 |  \_
 | (file_paste_as)[ me | CLASH_KEEP ]
 \_

; the paste, names taken here dealt with as `clash` says
ABYSS file_paste_as: [ @AppData me | I32 clash ]
 | me.prompt = PR_NONE
 | (me.tasks.push)[ (task_transfer)[ me.clip_cut | @(me.clip) | (me.cwd.cstr)[] | clash ] ]
 | IF [ me.clip_cut ]
 |  | (strings_clear)[ @(me.clip) ]
 |  \_
 \_

; the rows chosen in visual, or the file under the cursor, asked about
; before they go for good -- X; D is the trash
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

; the rows chosen in visual, or the file under the cursor, to the trash:
; renames, at once, no question -- u puts them back
ABYSS file_trash: [ @AppData me ]
 | Vector<String> paths
 | (main_selection)[ @(me.listing) | @paths ]
 | IF [ (paths.size)[] == 0 ]
 |  | (paths.deinit)[]
 |  | RET []
 |  \_
 | (strings_clear)[ @(me.undo_from) ]
 | (strings_clear)[ @(me.undo_put) ]
 | String why = (String.of)[ "" ]
 | String put = (String.of)[ "" ]
 | I32 failed = 0
 | FOR [ USIZE i = 0 | i < (paths.size)[] | i += 1 ]
 |  | @CONST C1 path = ((paths.at)[ i ].cstr)[]
 |  | IF [ (trash_one)[ path | @put | @why ] ]
 |  |  | (me.undo_from.push)[ (String.of)[ path ] ]
 |  |  | (me.undo_put.push)[ (String.of)[ (put.cstr)[] ] ]
 |  | ELSE
 |  |  | failed += 1
 |  |  \_
 |  \_
 | C1 s{300}
 | BufferSink b = (BufferSink.over)[ s | 300 ]
 | IF [ failed > 0 ]
 |  | (b.print)[ "%d not trashed: %s" | failed | (why.cstr)[] ]
 | ELSE
 |  | (b.print)[ "%d in the trash · u puts back" | (me.undo_from.size)[] AS I32 ]
 |  \_
 | (app_note)[ me | s AS @CONST C1 ]
 | (why.deinit)[]
 | (put.deinit)[]
 | (strings_clear)[ @paths ]
 | (paths.deinit)[]
 | (app_refresh)[ me | TRUE ]
 | ; the first trashing makes the trash: the places read again, to list it
 | me.places.read = FALSE
 \_

; the last batch put in the trash, back where it was
ABYSS file_untrash: [ @AppData me ]
 | USIZE n = (me.undo_from.size)[]
 | IF [ n == 0 ]
 |  | (app_note)[ me | "nothing to put back" ]
 |  | RET []
 |  \_
 | String why = (String.of)[ "" ]
 | I32 back = 0
 | FOR [ USIZE i = 0 | i < n | i += 1 ]
 |  | IF [ (trash_restore)[ ((me.undo_put.at)[ i ].cstr)[] | ((me.undo_from.at)[ i ].cstr)[] | @why ] ]
 |  |  | back += 1
 |  |  \_
 |  \_
 | C1 s{300}
 | BufferSink b = (BufferSink.over)[ s | 300 ]
 | IF [ back < (n AS I32) ]
 |  | (b.print)[ "%d put back, %d not: %s" | back | (n AS I32) - back | (why.cstr)[] ]
 | ELSE
 |  | (b.print)[ "%d put back" | back ]
 |  \_
 | (app_note)[ me | s AS @CONST C1 ]
 | (why.deinit)[]
 | (strings_clear)[ @(me.undo_from) ]
 | (strings_clear)[ @(me.undo_put) ]
 | (app_refresh)[ me | TRUE ]
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
 | (main_read)[ @(me.listing) | (me.cwd.cstr)[] ]
 | me.listing.table.list.cursor = (main_find)[ @(me.listing) | name | me.listing.table.list.cursor ]
 | me.listing.stale = FALSE
 \_
