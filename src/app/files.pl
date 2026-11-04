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
!USES <../core/perm.pl>
!USES <../core/extract.pl>
!USES <../core/command.pl>
!USES <../core/job.pl>
!USES <../core/git.pl>
!USES <../core/config.pl>
!USES <../ui/main.pl>

; what is kept of git's words, and the commands: chmod -R and chown -R get their
; mode or owner as "$1", the files after it
CONST USIZE GIT_ACTION_LIMIT = 16384
CONST @CONST C1 CHMOD_R_SCRIPT = "s=$1; shift; chmod -R -- \"$s\" \"$@\""
CONST @CONST C1 CHOWN_R_SCRIPT = "s=$1; shift; chown -R -- \"$s\" \"$@\""
; git's add; and its restore --staged, with reset in its place for an old git
; or a repository with no commit yet
CONST @CONST C1 GIT_ADD_SCRIPT = "git add -- \"$@\""
CONST @CONST C1 GIT_UNSTAGE_SCRIPT = "git restore --staged -- \"$@\" 2>/dev/null || git reset -q -- \"$@\""

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
 | me.emptying = FALSE
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
 | ; what goes from a trash takes its info file after it
 | Vector<String> infos
 | FOR [ USIZE i = 0 | i < (me.pending.size)[] | i += 1 ]
 |  | C1 info{TRASH_PATH}
 |  | info{0} = '\0'
 |  | (trash_info_of)[ ((me.pending.at)[ i ].cstr)[] | info | TRASH_PATH ]
 |  | (infos.push)[ (String.of)[ info AS @CONST C1 ] ]
 |  \_
 | (me.tasks.push)[ (task_delete)[ @(me.pending) | @infos ] ]
 | (strings_clear)[ @infos ]
 | (infos.deinit)[]
 | (strings_clear)[ @(me.pending) ]
 | me.emptying = FALSE
 | me.prompt = PR_NONE
 \_

; Z in the trash: everything in it, asked about first as a delete is. What is
; left in info/ with no item is taken too
ABYSS file_ask_empty: [ @AppData me ]
 | IF [ !(me.listing.trash) ]
 |  | (app_note)[ me | "Z empties the trash: go there with ' t" ]
 |  | RET []
 |  \_
 | (strings_clear)[ @(me.pending) ]
 | Result<os:Dir | IoError> d = (os:Dir.open)[ (me.cwd.cstr)[] ]
 | IF [ (d.is_ok)[] ]
 |  | os:Dir dir = (d.unwrap)[]
 |  | DirEntry e
 |  | WHILE [ (dir.next)[ @e ] ]
 |  |  | (me.pending.push)[ (join_path)[ (me.cwd.cstr)[] | e.name AS @CONST C1 ] ]
 |  |  \_
 |  | (dir.close)[]
 |  \_
 | me.empty_n = (me.pending.size)[] AS I32
 | ; info files whose item is gone
 | String top = (get_parent_path)[ (me.cwd.cstr)[] ]
 | String infos = (join_path)[ (top.cstr)[] | "info" ]
 | Result<os:Dir | IoError> f = (os:Dir.open)[ (infos.cstr)[] ]
 | IF [ (f.is_ok)[] ]
 |  | os:Dir dir2 = (f.unwrap)[]
 |  | DirEntry e2
 |  | WHILE [ (dir2.next)[ @e2 ] ]
 |  |  | String one = (join_path)[ (infos.cstr)[] | e2.name AS @CONST C1 ]
 |  |  | String item = (String.of)[ e2.name AS @CONST C1 ]
 |  |  | IF [ (str_ends)[ (item.cstr)[] | ".trashinfo" ] ]
 |  |  |  | (item.truncate)[ (item.size)[] - 10 ]
 |  |  |  \_
 |  |  | String at = (join_path)[ (me.cwd.cstr)[] | (item.cstr)[] ]
 |  |  | IF [ !((taken)[ (at.cstr)[] ]) ]
 |  |  |  | (me.pending.push)[ (String.of)[ (one.cstr)[] ] ]
 |  |  |  \_
 |  |  | (at.deinit)[]
 |  |  | (item.deinit)[]
 |  |  | (one.deinit)[]
 |  |  \_
 |  | (dir2.close)[]
 |  \_
 | (infos.deinit)[]
 | (top.deinit)[]
 | IF [ (me.pending.size)[] == 0 ]
 |  | (app_note)[ me | "the trash is empty" ]
 |  | RET []
 |  \_
 | me.emptying = TRUE
 | me.prompt = PR_DELETE
 \_

; `put` was put back by hand: u has no business with it any more
ABYSS undo_drop: [ @AppData me | @CONST C1 put ]
 | USIZE i = 0
 | WHILE [ i < (me.undo_put.size)[] ]
 |  | IF [ ((me.undo_put.at)[ i ].equals)[ put ] ]
 |  |  | String a = (me.undo_put.remove)[ i ]
 |  |  | String b = (me.undo_from.remove)[ i ]
 |  |  | (a.deinit)[]
 |  |  | (b.deinit)[]
 |  |  | CONTINUE
 |  |  \_
 |  | i += 1
 |  \_
 \_

; the files in the trash that were chosen, or are under the cursor, each put
; back where its info file says -- a free name beside it if that is taken
ABYSS file_restore: [ @AppData me ]
 | Vector<String> paths
 | (main_selection)[ @(me.listing) | @paths ]
 | IF [ (paths.size)[] == 0 ]
 |  | (paths.deinit)[]
 |  | RET []
 |  \_
 | String why = (String.of)[ "" ]
 | String landed = (String.of)[ "" ]
 | String aside = (String.of)[ "" ]
 | I32 back = 0
 | I32 renamed = 0
 | I32 failed = 0
 | FOR [ USIZE i = 0 | i < (paths.size)[] | i += 1 ]
 |  | @CONST C1 path = ((paths.at)[ i ].cstr)[]
 |  | String name = (get_dirname)[ path ]
 |  | @FileRecord r = (record_at)[ @(me.listing.files) | (main_find)[ @(me.listing) | (name.cstr)[] | -1 ] ]
 |  | (name.deinit)[]
 |  | IF [ r == NULL || (r.origin.size)[] == 0 ]
 |  |  | (why.deinit)[]
 |  |  | why = (String.of)[ "no info file: not known where it was" ]
 |  |  | failed += 1
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ (trash_put_back)[ path | (r.origin.cstr)[] | @landed | @why ] ]
 |  |  | back += 1
 |  |  | (undo_drop)[ me | path ]
 |  |  | IF [ !((landed.equals)[ (r.origin.cstr)[] ]) ]
 |  |  |  | renamed += 1
 |  |  |  | (aside.deinit)[]
 |  |  |  | aside = (get_shorter_path)[ (landed.cstr)[] ]
 |  |  |  \_
 |  | ELSE
 |  |  | failed += 1
 |  |  \_
 |  \_
 | C1 s{600}
 | BufferSink b = (BufferSink.over)[ s | 600 ]
 | (b.print)[ "restored %d" | back ]
 | IF [ renamed > 0 ]
 |  | (b.print)[ " · %d under a free name, as %s" | renamed | (aside.cstr)[] ]
 |  \_
 | IF [ failed > 0 ]
 |  | (b.print)[ " · %d not: %s" | failed | (why.cstr)[] ]
 |  \_
 | (app_note)[ me | s AS @CONST C1 ]
 | (why.deinit)[]
 | (landed.deinit)[]
 | (aside.deinit)[]
 | (strings_clear)[ @paths ]
 | (paths.deinit)[]
 | (app_refresh)[ me | TRUE ]
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

; --- the tasks ------------------------------------------------------------------

; P : the task the keys act on, stopped, or going on again
ABYSS file_pause: [ @AppData me ]
 | I32 i = (task_pick)[ @(me.tasks) | me.task_cur ]
 | IF [ i < 0 ]
 |  | RET []
 |  \_
 | @Task t = (me.tasks.at)[ i AS USIZE ]
 | (task_pause)[ t | !(t.paused) ]
 \_

; K : asks whether to give the task up
ABYSS file_ask_cancel: [ @AppData me ]
 | I32 i = (task_pick)[ @(me.tasks) | me.task_cur ]
 | IF [ i < 0 ]
 |  | RET []
 |  \_
 | me.cancel_id = (me.tasks.at)[ i AS USIZE ].id
 | me.prompt = PR_CANCEL
 \_

; the task asked about, given up: its half-written file gone, a half-unpacked
; folder removed by a task of its own; the columns read again
ABYSS file_cancel_now: [ @AppData me ]
 | me.prompt = PR_NONE
 | I32 i = (task_index)[ @(me.tasks) | me.cancel_id ]
 | IF [ i < 0 || !((task_running)[ (me.tasks.at)[ i AS USIZE ] ]) ]
 |  | (app_note)[ me | "it has ended already" ]
 |  | RET []
 |  \_
 | Task t = (me.tasks.remove)[ i AS USIZE ]
 | (task_cancel)[ @t ]
 | C1 line{600}
 | BufferSink b = (BufferSink.over)[ line | 600 ]
 | (b.print)[ "cancelled: %s" | (t.title.cstr)[] ]
 | (app_note)[ me | line AS @CONST C1 ]
 | ; the folder an unpacking made, with what came out of it so far
 | IF [ t.kind == TK_EXTRACT && (t.dest.size)[] > 0 ]
 |  | Vector<String> gone
 |  | (gone.push)[ (String.of)[ (t.dest.cstr)[] ] ]
 |  | (me.tasks.push)[ (task_delete)[ @gone | NULL ] ]
 |  | (strings_clear)[ @gone ]
 |  | (gone.deinit)[]
 |  \_
 | (task_free)[ @t ]
 | (app_refresh)[ me | TRUE ]
 \_

; R : what failed in the task kept with failures, done again as a task of its own
ABYSS file_retry: [ @AppData me ]
 | I32 i = (task_pick_held)[ @(me.tasks) | me.task_cur ]
 | IF [ i < 0 ]
 |  | RET []
 |  \_
 | Task t = (me.tasks.remove)[ i AS USIZE ]
 | IF [ t.kind == TK_EXTRACT ]
 |  | (me.tasks.push)[ (task_extract)[ (t.target.cstr)[] | (t.into.cstr)[] ] ]
 | ELIF [ (t.bad_src.size)[] > 0 ]
 |  | (me.tasks.push)[ (task_retry)[ @t ] ]
 | ELSE
 |  | (app_note)[ me | "nothing to retry: dismiss it" ]
 |  | (me.tasks.push)[ t ]
 |  | RET []
 |  \_
 | (task_free)[ @t ]
 \_

; Esc, or a click on dismiss: the task kept with failures taken off
ABYSS file_dismiss: [ @AppData me ]
 | I32 i = (task_pick_held)[ @(me.tasks) | me.task_cur ]
 | IF [ i < 0 ]
 |  | RET []
 |  \_
 | Task t = (me.tasks.remove)[ i AS USIZE ]
 | (task_free)[ @t ]
 \_

; the archives among the rows chosen in visual -- or the file under the
; cursor -- each unpacked here, into a folder of its own, as a task
ABYSS file_extract: [ @AppData me ]
 | Vector<String> paths
 | (main_selection)[ @(me.listing) | @paths ]
 | I32 started = 0
 | FOR [ USIZE i = 0 | i < (paths.size)[] | i += 1 ]
 |  | @CONST C1 p = ((paths.at)[ i ].cstr)[]
 |  | IF [ (is_archive)[ p ] ]
 |  |  | (me.tasks.push)[ (task_extract)[ p | (me.cwd.cstr)[] ] ]
 |  |  | started += 1
 |  |  \_
 |  \_
 | IF [ started == 0 ]
 |  | (app_note)[ me | "not an archive trufm knows: an extract.<ext> line in the config teaches it" ]
 |  \_
 | (strings_clear)[ @paths ]
 | (paths.deinit)[]
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

; the file under the cursor asked a mode, its own in octal to begin with
ABYSS file_ask_chmod: [ @AppData me ]
 | String path = (main_path)[ @(me.listing) | me.listing.table.list.cursor ]
 | POSTLUDE (path.deinit)[]
 | IF [ (path.size)[] == 0 ]
 |  | RET []
 |  \_
 | ; through a link, as chmod does
 | Result<FileInfo | IoError> fi = (fs_info)[ (path.cstr)[] ]
 | IF [ (fi.is_err)[] ]
 |  | (app_note)[ me | (io_error_text)[ (fi.error)[] ] ]
 |  | RET []
 |  \_
 | C1 text{16}
 | BufferSink b = (BufferSink.over)[ text | 16 ]
 | (b.print)[ "%03o" | (fi.unwrap)[].mode & 0xFFF ]
 | (input_set)[ @(me.field) | text AS @CONST C1 ]
 | me.prompt = PR_CHMOD
 \_

; the mode typed, given to the rows chosen in visual or the file under the
; cursor -- not what is in a folder, unless it starts with -R: then chmod -R
; runs as a task. A mode that is none changes nothing, and starts nothing
ABYSS file_chmod_done: [ @AppData me | @CONST C1 typed ]
 | me.prompt = PR_NONE
 | B1 rec = FALSE
 | @CONST C1 spec = (perm_flags)[ typed | @rec ]
 | U32 probe = 0
 | IF [ !((mode_apply)[ spec | 0 | FALSE | @probe ]) ]
 |  | C1 s{300}
 |  | BufferSink b = (BufferSink.over)[ s | 300 ]
 |  | (b.print)[ "not a mode: %s" | spec ]
 |  | (app_note)[ me | s AS @CONST C1 ]
 |  | RET []
 |  \_
 | Vector<String> paths
 | (main_selection)[ @(me.listing) | @paths ]
 | IF [ rec ]
 |  | IF [ (paths.size)[] > 0 ]
 |  |  | (me.tasks.push)[ (task_command)[ "chmod -R" | CHMOD_R_SCRIPT | spec | @paths | (me.cwd.cstr)[] ] ]
 |  |  \_
 |  | (strings_clear)[ @paths ]
 |  | (paths.deinit)[]
 |  | RET []
 |  \_
 | I32 done = 0
 | I32 failed = 0
 | @CONST C1 why = ""
 | FOR [ USIZE i = 0 | i < (paths.size)[] | i += 1 ]
 |  | @CONST C1 path = ((paths.at)[ i ].cstr)[]
 |  | Result<FileInfo | IoError> fi = (fs_info)[ path ]
 |  | B1 ok = FALSE
 |  | IF [ (fi.is_err)[] ]
 |  |  | IF [ failed == 0 ]
 |  |  |  | why = (io_error_text)[ (fi.error)[] ]
 |  |  |  \_
 |  | ELSE
 |  |  | FileInfo info = (fi.unwrap)[]
 |  |  | U32 mode = 0
 |  |  | IF [ (mode_apply)[ spec | info.mode | info.kind == FS_DIR | @mode ] ]
 |  |  |  | ok = (px_chmod)[ path | mode ] == 0
 |  |  |  | IF [ !ok && failed == 0 ]
 |  |  |  |  | why = (io_error_text)[ (io_error_of)[ (io_errno)[] ] ]
 |  |  |  |  \_
 |  |  |  \_
 |  |  \_
 |  | IF [ ok ]
 |  |  | done += 1
 |  | ELSE
 |  |  | failed += 1
 |  |  \_
 |  \_
 | C1 s{300}
 | BufferSink b = (BufferSink.over)[ s | 300 ]
 | IF [ failed > 0 ]
 |  | (b.print)[ "chmod: %d failed, %d changed: %s" | failed | done | why ]
 | ELSE
 |  | (b.print)[ "chmod %s: %d changed" | spec | done ]
 |  \_
 | (app_note)[ me | s AS @CONST C1 ]
 | (strings_clear)[ @paths ]
 | (paths.deinit)[]
 | (app_refresh)[ me | TRUE ]
 \_

; the file under the cursor asked an owner, its own as user:group to begin with
ABYSS file_ask_chown: [ @AppData me ]
 | String path = (main_path)[ @(me.listing) | me.listing.table.list.cursor ]
 | POSTLUDE (path.deinit)[]
 | IF [ (path.size)[] == 0 ]
 |  | RET []
 |  \_
 | ; through a link, as chown does
 | Stat st
 | IF [ !((px_stat_through)[ (path.cstr)[] | @st ]) ]
 |  | (px_stat_of)[ (path.cstr)[] | @st ]
 |  \_
 | C1 u{128}
 | C1 g{128}
 | (px_user_name)[ u | 128 | st.uid ]
 | (px_group_name)[ g | 128 | st.gid ]
 | C1 text{300}
 | BufferSink b = (BufferSink.over)[ text | 300 ]
 | (b.print)[ "%s:%s" | u AS @CONST C1 | g AS @CONST C1 ]
 | (input_set)[ @(me.field) | text AS @CONST C1 ]
 | me.prompt = PR_CHOWN
 \_

; the owner typed, given to the rows chosen in visual or the file under the
; cursor, through links as chown does (a broken link's own); -R first: chown
; -R as a task. A name that is none changes nothing
ABYSS file_chown_done: [ @AppData me | @CONST C1 typed ]
 | me.prompt = PR_NONE
 | B1 rec = FALSE
 | @CONST C1 spec = (perm_flags)[ typed | @rec ]
 | C1 user{128}
 | C1 group{128}
 | IF [ !((owner_split)[ spec | user | group | 128 ]) ]
 |  | (app_note)[ me | "not an owner: user, user:group or :group" ]
 |  | RET []
 |  \_
 | U32 uid = ID_KEEP
 | U32 gid = ID_KEEP
 | C1 s{400}
 | BufferSink b = (BufferSink.over)[ s | 400 ]
 | IF [ user{0} != '\0' && !((px_user_id)[ user AS @CONST C1 | @uid ]) ]
 |  | (b.print)[ "chown: no such user: %s" | user AS @CONST C1 ]
 |  | (app_note)[ me | s AS @CONST C1 ]
 |  | RET []
 |  \_
 | IF [ group{0} != '\0' && !((px_group_id)[ group AS @CONST C1 | @gid ]) ]
 |  | (b.print)[ "chown: no such group: %s" | group AS @CONST C1 ]
 |  | (app_note)[ me | s AS @CONST C1 ]
 |  | RET []
 |  \_
 | Vector<String> paths
 | (main_selection)[ @(me.listing) | @paths ]
 | IF [ rec ]
 |  | ; user:group as chown has it, a lone user without the colon
 |  | C1 norm{300}
 |  | BufferSink n = (BufferSink.over)[ norm | 300 ]
 |  | (n.print)[ "%s" | user AS @CONST C1 ]
 |  | IF [ group{0} != '\0' ]
 |  |  | (n.print)[ ":%s" | group AS @CONST C1 ]
 |  |  \_
 |  | IF [ (paths.size)[] > 0 ]
 |  |  | (me.tasks.push)[ (task_command)[ "chown -R" | CHOWN_R_SCRIPT | norm AS @CONST C1 | @paths | (me.cwd.cstr)[] ] ]
 |  |  \_
 |  | (strings_clear)[ @paths ]
 |  | (paths.deinit)[]
 |  | RET []
 |  \_
 | I32 done = 0
 | I32 failed = 0
 | @CONST C1 why = ""
 | FOR [ USIZE i = 0 | i < (paths.size)[] | i += 1 ]
 |  | @CONST C1 path = ((paths.at)[ i ].cstr)[]
 |  | Stat st
 |  | ; a link that points at nothing has only itself to give
 |  | ; (not SELECT: it would do both)
 |  | I32 r = 0
 |  | IF [ (px_stat_through)[ path | @st ] ]
 |  |  | r = (px_chown)[ path | uid | gid ]
 |  | ELSE
 |  |  | r = (px_lchown)[ path | uid | gid ]
 |  |  \_
 |  | IF [ r == 0 ]
 |  |  | done += 1
 |  | ELSE
 |  |  | IF [ failed == 0 ]
 |  |  |  | why = (strerror)[ (io_errno)[] ] AS @CONST C1 
 |  |  |  \_
 |  |  | failed += 1
 |  |  \_
 |  \_
 | BufferSink o = (BufferSink.over)[ s | 400 ]
 | IF [ failed > 0 ]
 |  | (o.print)[ "chown: %d failed, %d changed: %s" | failed | done | why ]
 | ELSE
 |  | (o.print)[ "chown %s: %d changed" | spec | done ]
 |  \_
 | (app_note)[ me | s AS @CONST C1 ]
 | (strings_clear)[ @paths ]
 | (paths.deinit)[]
 | (app_refresh)[ me | TRUE ]
 \_

; a stages the rows chosen in visual or the file under the cursor, A unstages
; them: git run beside the frames, in this folder, the files as its "$@". The
; answer is taken in by git_action_step
ABYSS file_git: [ @AppData me | B1 stage ]
 | IF [ !(me.listing.git.on) ]
 |  | (app_note)[ me | "not in a git work tree" ]
 |  | RET []
 |  \_
 | IF [ me.git_busy ]
 |  | (app_note)[ me | "git is still at work" ]
 |  | RET []
 |  \_
 | Vector<String> paths
 | POSTLUDE (paths.deinit)[]
 | (main_selection)[ @(me.listing) | @paths ]
 | IF [ (paths.size)[] > 0 ]
 |  | @CONST C1 script = SELECT [ stage | GIT_ADD_SCRIPT | GIT_UNSTAGE_SCRIPT ]
 |  | IF [ (job_start_many)[ @(me.git_job) | script | (me.cwd.cstr)[] | NULL | @paths | GIT_ACTION_LIMIT ] ]
 |  |  | me.git_busy = TRUE
 |  |  | me.git_staging = stage
 |  |  | me.git_n = (paths.size)[] AS I32
 |  | ELSE
 |  |  | (app_note)[ me | "sh cannot be started" ]
 |  |  \_
 |  \_
 | (strings_clear)[ @paths ]
 \_

; the git a / A started, once it is done: said, and git asked again so the
; marks follow. Called every frame
ABYSS git_action_step: [ @Ui ui | @AppData me ]
 | IF [ !(me.git_busy) ]
 |  | RET []
 |  \_
 | IF [ !((job_pump)[ @(me.git_job) ]) ]
 |  | (ui.wake_in)[ 30 ]
 |  | RET []
 |  \_
 | me.git_busy = FALSE
 | C1 s{400}
 | BufferSink b = (BufferSink.over)[ s | 400 ]
 | IF [ me.git_job.ok ]
 |  | (b.print)[ "%s %d" | SELECT [ me.git_staging | "staged" | "unstaged" ] | me.git_n ]
 | ELSE
 |  | ; git's first line is its complaint
 |  | C1 first{300}
 |  | USIZE n = 0
 |  | @CONST C1 out = (me.git_job.out.cstr)[]
 |  | WHILE [ out{n} != '\0' && out{n} != '\n' && n + 1 < 300 ]
 |  |  | first{n} = out{n}
 |  |  | n += 1
 |  |  \_
 |  | first{n} = '\0'
 |  | (b.print)[ "git: %s" | SELECT [ n > 0 | first AS @CONST C1 | "it failed" ] ]
 |  \_
 | (app_note)[ me | s AS @CONST C1 ]
 | (job_stop)[ @(me.git_job) ]
 | (git_ask)[ @(me.listing.git) | (me.cwd.cstr)[] | TRUE ]
 | (preview_redo)[ @(me.preview) ]
 | (ui.redo)[]
 \_

; the clipboard pasted as links, not copies: a link here to each item, by
; its full path, under a free name. The clipboard stays as it is
ABYSS file_paste_links: [ @AppData me ]
 | IF [ (me.clip.size)[] == 0 ]
 |  | (app_note)[ me | "nothing to link: y copies" ]
 |  | RET []
 |  \_
 | I32 done = 0
 | I32 failed = 0
 | @CONST C1 why = ""
 | FOR [ USIZE i = 0 | i < (me.clip.size)[] | i += 1 ]
 |  | @CONST C1 src = ((me.clip.at)[ i ].cstr)[]
 |  | String name = (get_dirname)[ src ]
 |  | String dst = (free_name)[ (me.cwd.cstr)[] | (name.cstr)[] ]
 |  | IF [ (px_symlink)[ src | (dst.cstr)[] ] == 0 ]
 |  |  | done += 1
 |  | ELSE
 |  |  | IF [ failed == 0 ]
 |  |  |  | why = (io_error_text)[ (io_error_of)[ (io_errno)[] ] ]
 |  |  |  \_
 |  |  | failed += 1
 |  |  \_
 |  | (name.deinit)[]
 |  | (dst.deinit)[]
 |  \_
 | C1 s{300}
 | BufferSink b = (BufferSink.over)[ s | 300 ]
 | IF [ failed > 0 ]
 |  | (b.print)[ "linked %d, %d failed: %s" | done | failed | why ]
 | ELSE
 |  | (b.print)[ "linked %d" | done ]
 |  \_
 | (app_note)[ me | s AS @CONST C1 ]
 | (app_refresh)[ me | TRUE ]
 \_
