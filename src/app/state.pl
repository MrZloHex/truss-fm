; state.pl -- what trufm keeps from one run to the next: the tabs, the main
; column's order and whether hidden files show. Kept in
; $XDG_CONFIG_HOME/trufm/state, else ~/.config/trufm/state, beside the
; bookmarks; written as
; trufm quits, read as it starts, over what the config says
;
;   hidden = true
;   sort = 0                 0 name, 1 size, 2 date
;   sort_desc = false
;   open = 2                 the open tab's number
;   tab = 1 14 /home/me      a tab: its number, its row, its folder

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/process.pl>

!USES <../core/fs.pl>
!USES <../core/config.pl>
!USES <app.pl>

CONST USIZE STATE_LINE = 4200

; the state file's folder, in `out`
ABYSS state_dir: [ @C1 out | USIZE cap ]
 | Option<@CONST C1> st = (env)[ "XDG_CONFIG_HOME" ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | IF [ (st.is_some)[] && (st.unwrap)[]{0} == '/' ]
 |  | (b.print)[ "%s/trufm" | (st.unwrap)[] ]
 | ELSE
 |  | (b.print)[ "%s/.config/trufm" | ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 \_

; the tabs, the order and hidden written down, for the next run. Written
; aside first, then renamed over the old, so a crash leaves one whole
ABYSS state_save: [ @AppData a ]
 | (a.tabs.at)[ a.tab AS USIZE ].cursor = (main_unfiltered_row)[ @(a.listing) ]
 | String text = (String.of)[ "" ]
 | POSTLUDE (text.deinit)[]
 | C1 line{STATE_LINE}
 | BufferSink b = (BufferSink.over)[ line | STATE_LINE ]
 | (b.print)[ "hidden = %s\nsort = %d\nsort_desc = %s\nopen = %d\n" | SELECT [ CFG.hidden | "true" | "false" ] | a.listing.table.sort | SELECT [ a.listing.table.desc | "true" | "false" ] | (a.tabs.at)[ a.tab AS USIZE ].slot ]
 | (text.append)[ line AS @CONST C1 ]
 | FOR [ USIZE i = 0 | i < (a.tabs.size)[] | i += 1 ]
 |  | @Tab t = (a.tabs.at)[ i ]
 |  | ; a folder with a line end in its name cannot be one line
 |  | IF [ ((str_find)[ (t.cwd.cstr)[] | '\n' ].is_some)[] || (t.cwd.size)[] == 0 ]
 |  |  | CONTINUE
 |  |  \_
 |  | BufferSink c = (BufferSink.over)[ line | STATE_LINE ]
 |  | (c.print)[ "tab = %d %d %s\n" | t.slot | t.cursor | (t.cwd.cstr)[] ]
 |  | (text.append)[ line AS @CONST C1 ]
 |  \_
 |
 | C1 dir{4096}
 | (state_dir)[ dir | 4096 ]
 | (fs_make_dirs)[ dir AS @CONST C1 ]
 | C1 file{4200}
 | C1 part{4200}
 | BufferSink f = (BufferSink.over)[ file | 4200 ]
 | (f.print)[ "%s/state" | dir AS @CONST C1 ]
 | BufferSink p = (BufferSink.over)[ part | 4200 ]
 | (p.print)[ "%s/state.%d.part" | dir AS @CONST C1 | (process_id)[] ]
 | IF [ ((write_file)[ part AS @CONST C1 | (text.cstr)[] ].is_ok)[] ]
 |  | (fs_rename)[ part AS @CONST C1 | file AS @CONST C1 ]
 | ELSE
 |  | ; a half-written aside is not kept
 |  | (fs_remove)[ part AS @CONST C1 ]
 |  \_
 \_

; a whole number, 0 or more, at `s`, into `out`; after it and its blanks.
; NULL: none there
LOCAL @CONST C1 take_count: [ @CONST C1 s | @I32 out ]
 | IF [ ?s < '0' || ?s > '9' ]
 |  | RET [ NULL ]
 |  \_
 | I32 n = 0
 | WHILE [ ?s >= '0' && ?s <= '9' ]
 |  | ; a number too big for a count is none
 |  | IF [ n > 100000000 ]
 |  |  | RET [ NULL ]
 |  |  \_
 |  | n = n * 10 + ((?s - '0') AS I32)
 |  | s += 1
 |  \_
 | WHILE [ ?s == ' ' ]
 |  | s += 1
 |  \_
 | ?out = n
 | RET [ s ]
 \_

; the last run's state, over the config's: the order, hidden, and the
; tabs -- they take the place of the config's. A folder no longer there
; is left out. `start`: the folder named on the command line, put in the
; tab that was open; NULL: none was, that tab opens where it was
ABYSS state_load: [ @AppData a | @CONST C1 start ]
 | C1 dir{4096}
 | (state_dir)[ dir | 4096 ]
 | C1 file{4200}
 | BufferSink f = (BufferSink.over)[ file | 4200 ]
 | (f.print)[ "%s/state" | dir AS @CONST C1 ]
 | String text
 | POSTLUDE (text.deinit)[]
 | IF [ ((read_file)[ file AS @CONST C1 | @text ].is_err)[] ]
 |  | RET []
 |  \_
 |
 | Vector<Tab> tabs
 | I32 open = 0
 | Split lines = (Split.over)[ (text.cstr)[] | '\n' ]
 | C1 line{STATE_LINE}
 | WHILE [ (lines.next)[ line | STATE_LINE ] ]
 |  | @CONST C1 l = line AS @CONST C1
 |  | IF [ (str_starts)[ l | "hidden = " ] ]
 |  |  | CFG.hidden = (str_eq)[ l + 9 | "true" ]
 |  | ELIF [ (str_starts)[ l | "sort_desc = " ] ]
 |  |  | a.listing.table.desc = (str_eq)[ l + 12 | "true" ]
 |  | ELIF [ (str_starts)[ l | "sort = " ] ]
 |  |  | I32 s = 0
 |  |  | IF [ (take_count)[ l + 7 | @s ] != NULL && s <= 2 ]
 |  |  |  | a.listing.table.sort = s
 |  |  |  \_
 |  | ELIF [ (str_starts)[ l | "open = " ] ]
 |  |  | (take_count)[ l + 7 | @open ]
 |  | ELIF [ (str_starts)[ l | "tab = " ] ]
 |  |  | I32 slot = 0
 |  |  | I32 cursor = 0
 |  |  | @CONST C1 at = (take_count)[ l + 6 | @slot ]
 |  |  | IF [ at != NULL ]
 |  |  |  | at = (take_count)[ at | @cursor ]
 |  |  |  \_
 |  |  | ; in order of their numbers, whatever the file's order; a number
 |  |  | ; once, the first wins
 |  |  | B1 fits = at != NULL && slot >= 1 && slot <= (MAX_TABS AS I32)
 |  |  | USIZE put = 0
 |  |  | WHILE [ put < (tabs.size)[] && (tabs.at)[ put ].slot < slot ]
 |  |  |  | put += 1
 |  |  |  \_
 |  |  | IF [ put < (tabs.size)[] && (tabs.at)[ put ].slot == slot ]
 |  |  |  | fits = FALSE
 |  |  |  \_
 |  |  | IF [ fits ]
 |  |  |  | B1 up = (remote_ok_deep)[ at ]
 |  |  |  | Result<String | IoError> full = (get_realpath)[ SELECT [ up | at | "/" ] ]
 |  |  |  | IF [ up && (full.is_ok)[] ]
 |  |  |  |  | String d = (full.unwrap)[]
 |  |  |  |  | Result<FileInfo | IoError> fi = (fs_info)[ (d.cstr)[] ]
 |  |  |  |  | IF [ (fi.is_ok)[] && (fi.unwrap)[].kind == FS_DIR ]
 |  |  |  |  |  | (tabs.insert)[ put | (tab_of)[ (d.cstr)[] | cursor | slot ] ]
 |  |  |  |  |  \_
 |  |  |  |  | (d.deinit)[]
 |  |  |  |  \_
 |  |  |  \_
 |  |  \_
 |  \_
 | IF [ (tabs.size)[] == 0 ]
 |  | (tabs.deinit)[]
 |  | RET []
 |  \_
 |
 | ; the saved tabs in place of the ones made at the start
 | FOR [ USIZE i = 0 | i < (a.tabs.size)[] | i += 1 ]
 |  | (tab_free)[ (a.tabs.at)[ i ] ]
 |  \_
 | (a.tabs.deinit)[]
 | a.tabs = tabs
 | I32 at = (tab_at_slot)[ a | open ]
 | a.tab = SELECT [ at < 0 | 0 | at ] AS U32
 | IF [ start != NULL ]
 |  | @Tab t = (a.tabs.at)[ a.tab AS USIZE ]
 |  | IF [ !((t.cwd.equals)[ start ]) ]
 |  |  | (t.cwd.deinit)[]
 |  |  | (t.label.deinit)[]
 |  |  | t.cwd = (String.of)[ start ]
 |  |  | t.label = (folder_name)[ start ]
 |  |  | t.cursor = 0
 |  |  \_
 |  \_
 | (tab_enter)[ a | -1 ]
 \_
