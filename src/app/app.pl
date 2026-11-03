; app.pl -- what the program keeps between frames: the folder it is in, the
; disk under it, and each column's own state

USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>
USE <modular.pl>

!USES <../core/fs.pl>
!USES <../core/tasks.pl>
!USES <../core/trash.pl>
!USES <../core/config.pl>
!USES <../ui/places.pl>
!USES <../ui/root.pl>
!USES <../ui/main.pl>
!USES <../ui/preview.pl>

TYPE Partition: STRUCT
 | String name              ; /dev/nvme0n1p2
 | F32 usage                ; how full, in percent
 | F64 free                 ; GiB
 \_

CONST USIZE MAX_TABS = 9
CONST U64 NOTE_MS = 4000        ; how long a note is shown
CONST U64 REFRESH_MS = 400      ; how often the columns are read while a task runs

; what the line at the bottom of the tasks asks
TYPE Prompt: ENUM
 | PR_NONE
 | PR_RENAME        ; a new name for `renaming`
 | PR_MKDIR         ; a name for a new folder here
 | PR_DELETE        ; y or n, for `pending`
 | PR_OPEN          ; a command to open `pending` with
 | PR_CLASH         ; o, s or k: what the paste does with names taken here
 | PR_FILTER        ; letters typed into the path bar: the main column narrows
 | PR_MENU          ; a row's actions, offered by a right press: a click or a key
 | PR_CHOOSE        ; o: which program to open `pending` with, 1 to 9, e to type
 \_

TYPE Tab: STRUCT
 | String cwd               ; where the tab is
 | String label             ; its folder's name, for the top bar
 | I32 cursor               ; the main column's row, kept while away
 | I32 slot                 ; its number, 1 to 9: 1 goes to it; there may be gaps
 \_

TYPE AppData: STRUCT
 | Vector<Tab> tabs
 | U32 tab                  ; the open one; its folder is `cwd`
 | String cwd               ; where it is, in full
 | String rel_cwd           ; the same with ~ for home
 | Partition partition
 | I32 cols                 ; the screen the last frame was built for
 | I32 rows
 |
 | Vector<Task> tasks
 | Vector<String> clip      ; what y or d took, full paths
 | B1 clip_cut              ; d: the paste moves them
 | U64 refreshed            ; now_ms the columns were last read for a task
 |
 | Prompt prompt
 | InputState field         ; what is typed for it
 | InputState filter_field  ; and for the filter, in the path bar
 | String renaming          ; PR_RENAME: the full path
 | Vector<String> pending   ; PR_DELETE: what goes
 | Vector<String> undo_from ; the last batch put in the trash: where each was,
 | Vector<String> undo_put  ;   and where it went -- u puts them back
 | Vector<String> choices   ; PR_CHOOSE: the commands on offer, term: before
 |                          ;   one that wants the terminal
 | I32 clashes              ; PR_CLASH: how many names the paste finds taken
 | String clash_one         ;   the first of them
 | String note              ; a word at the bottom: done, or what failed
 | U64 note_at              ; now_ms it was said
 | String cd_file           ; --cd-file: Q writes the folder here, for the
 |                          ;   shell function to go to; empty: Q cannot
 | B1 help                  ; ? : the keys shown in the columns' place
 | ScrollState help_sc      ;   and how far down they are
 | C1 clicked{16}           ; a key a click stands for, this frame: "y" for the
 |                          ;   [y] copy clicked; "" for none
 | I32 close_tab            ; a tab middle-clicked, to close; -1: none
 |
 | PlacesPane  places
 | RootPane    root
 | MainPane    listing
 | PreviewPane preview
 \_

; the disk under `path`; what cannot be found of it is shown as nothing,
; not a crash
Partition partition_of: [ @CONST C1 path ]
 | Partition p
 | Option<String> name = (get_phy_part_name)[ path ]
 | IF [ (name.is_some)[] ]
 |  | p.name = (name.unwrap)[]
 | ELSE
 |  | p.name = (String.of)[ "?" ]
 |  \_
 | p.usage = ((get_phy_part_usage)[ path ].unwrap_or)[ 0.0 ]
 | p.free = ((get_phy_part_free)[ path ].unwrap_or)[ 0.0 ]
 | RET [ p ]
 \_

; the program is in `cwd` now, which it takes: the path, the disk and the
; open tab follow; the columns read it on their next frame
ABYSS app_enter: [ @AppData a | String cwd ]
 | (a.cwd.deinit)[]
 | (a.rel_cwd.deinit)[]
 | (a.partition.name.deinit)[]
 | a.cwd = cwd
 | a.rel_cwd = (get_shorter_path)[ (cwd.cstr)[] ]
 | a.partition = (partition_of)[ (cwd.cstr)[] ]
 | ; a filter is for the folder it was typed in
 | (a.listing.filter.deinit)[]
 | a.listing.filter = (String.of)[ "" ]
 |
 | @Tab t = (a.tabs.at)[ a.tab AS USIZE ]
 | (t.cwd.deinit)[]
 | (t.label.deinit)[]
 | t.cwd = (String.of)[ (cwd.cstr)[] ]
 | t.label = (folder_name)[ (cwd.cstr)[] ]
 \_

; a tab in `cwd`, its row `cursor`, number `slot`
Tab tab_of: [ @CONST C1 cwd | I32 cursor | I32 slot ]
 | Tab t
 | t.cwd = (String.of)[ cwd ]
 | t.label = (folder_name)[ cwd ]
 | t.cursor = cursor
 | t.slot = slot
 | RET [ t ]
 \_

; where the tab numbered `slot` is among the tabs; -1: there is none
I32 tab_at_slot: [ @AppData a | I32 slot ]
 | FOR [ USIZE i = 0 | i < (a.tabs.size)[] | i += 1 ]
 |  | IF [ (a.tabs.at)[ i ].slot == slot ]
 |  |  | RET [ i AS I32 ]
 |  |  \_
 |  \_
 | RET [ -1 ]
 \_

; the lowest number no tab has; 0: all nine are taken
I32 free_slot: [ @AppData a ]
 | FOR [ I32 k = 1 | k <= (MAX_TABS AS I32) | k += 1 ]
 |  | IF [ (tab_at_slot)[ a | k ] < 0 ]
 |  |  | RET [ k ]
 |  |  \_
 |  \_
 | RET [ 0 ]
 \_

; a new tab, numbered `slot`, in `cwd`, put among the others in order of
; their numbers -- the open one still the open one. Where it went
I32 tab_add: [ @AppData a | @CONST C1 cwd | I32 cursor | I32 slot ]
 | I32 open = (a.tabs.at)[ a.tab AS USIZE ].slot
 | (a.tabs.push)[ (tab_of)[ cwd | cursor | slot ] ]
 | USIZE i = (a.tabs.size)[] - 1
 | WHILE [ i > 0 && (a.tabs.at)[ i - 1 ].slot > slot ]
 |  | (a.tabs.swap)[ i - 1 | i ]
 |  | i -= 1
 |  \_
 | a.tab = (tab_at_slot)[ a | open ] AS U32
 | RET [ i AS I32 ]
 \_

ABYSS tab_free: [ @Tab t ]
 | (t.cwd.deinit)[]
 | (t.label.deinit)[]
 \_

; to the folder of the open tab, with its row; home if it is gone since
ABYSS tab_enter: [ @AppData a ]
 | @Tab t = (a.tabs.at)[ a.tab AS USIZE ]
 | a.listing.restore = t.cursor + 1
 | ; resolved before app_enter frees t.cwd
 | Result<String | IoError> full = (get_realpath)[ (t.cwd.cstr)[] ]
 | IF [ (full.is_err)[] ]
 |  | full = (get_realpath)[ ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 | IF [ (full.is_ok)[] ]
 |  | (app_enter)[ a | (full.unwrap)[] ]
 |  \_
 \_

ABYSS strings_clear: [ @Vector<String> v ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | ((v.at)[ i ].deinit)[]
 |  \_
 | (v.clear)[]
 \_

ABYSS app_note: [ @AppData a | @CONST C1 s ]
 | (a.note.deinit)[]
 | a.note = (String.of)[ s ]
 | a.note_at = (now_ms)[]
 \_

; the columns read again: what is on the disk changed. Not `all`, as a
; task runs: the main column only, and only if its folder's entries changed
; -- each read counts what every subfolder holds
ABYSS app_refresh: [ @AppData a | B1 all ]
 | a.refreshed = (now_ms)[]
 | IF [ !all ]
 |  | IF [ (main_changed)[ @(a.listing) ] ]
 |  |  | a.listing.stale = TRUE
 |  |  \_
 |  | RET []
 |  \_
 | a.listing.stale = TRUE
 | (a.root.cwd.deinit)[]
 | a.root.cwd = (String.of)[ "" ]
 | (a.preview.path.deinit)[]
 | a.preview.path = (String.of)[ "" ]
 \_

; the folder it is in gone -- a disk unmounted, a folder deleted from
; elsewhere: up to the nearest one that is still there, and said so.
; TRUE: it moved
B1 app_check_gone: [ @AppData a ]
 | IF [ ((fs_info)[ (a.cwd.cstr)[] ].is_ok)[] ]
 |  | RET [ FALSE ]
 |  \_
 | String up = (get_parent_path)[ (a.cwd.cstr)[] ]
 | LOOP
 |  | Result<String | IoError> r = (get_realpath)[ (up.cstr)[] ]
 |  | IF [ (r.is_ok)[] ]
 |  |  | String gone = (folder_name)[ (a.cwd.cstr)[] ]
 |  |  | C1 s{300}
 |  |  | BufferSink b = (BufferSink.over)[ s | 300 ]
 |  |  | (b.print)[ "%s is gone" | (gone.cstr)[] ]
 |  |  | (gone.deinit)[]
 |  |  | (up.deinit)[]
 |  |  | (app_enter)[ a | (r.unwrap)[] ]
 |  |  | (app_refresh)[ a | TRUE ]
 |  |  | (app_note)[ a | s AS @CONST C1 ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | String next = (get_parent_path)[ (up.cstr)[] ]
 |  | (up.deinit)[]
 |  | up = next
 |  \_
 \_

; dotfiles shown, or no longer, for this run: every column read again, the
; cursor kept on its file where it is still shown
ABYSS app_toggle_hidden: [ @AppData a ]
 | CFG.hidden = !(CFG.hidden)
 | (app_refresh)[ a | TRUE ]
 | (app_note)[ a | SELECT [ CFG.hidden | "hidden files shown" | "hidden files hidden" ] ]
 \_

; is `name` one a file can have here? No / and not . or ..
B1 name_ok: [ @CONST C1 name ]
 | IF [ name{0} == '\0' || (str_eq)[ name | "." ] || (str_eq)[ name | ".." ] ]
 |  | RET [ FALSE ]
 |  \_
 | FOR [ USIZE i = 0 | name{i} != '\0' | i += 1 ]
 |  | IF [ name{i} == '/' ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  \_
 | RET [ TRUE ]
 \_

IFACE AppOps: [ @AppData me ]
 | ; to the folder `path`; FALSE, and nothing changes, when it is not one
 | B1 go_to: [ @CONST C1 path ]
 |  | Result<String | IoError> full = (get_realpath)[ path ]
 |  | IF [ (full.is_err)[] ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | (app_enter)[ me | (full.unwrap)[] ]
 |  | RET [ TRUE ]
 |  \_
 |
 | ; to tab `i`; the tab left keeps its row
 | ABYSS open_tab: [ USIZE i ]
 |  | IF [ i == (me.tab AS USIZE) || i >= (me.tabs.size)[] ]
 |  |  | RET []
 |  |  \_
 |  | (me.tabs.at)[ me.tab AS USIZE ].cursor = me.listing.table.list.cursor
 |  | me.tab = i AS U32
 |  | (tab_enter)[ me ]
 |  \_
 |
 | ; a new tab where the open one is, under the lowest free number, opened
 | ABYSS new_tab: []
 |  | I32 slot = (free_slot)[ me ]
 |  | IF [ slot == 0 ]
 |  |  | (app_note)[ me | "all nine tabs are in use: x closes one" ]
 |  |  | RET []
 |  |  \_
 |  | I32 at = (tab_add)[ me | (me.cwd.cstr)[] | me.listing.table.list.cursor | slot ]
 |  | (me.open_tab)[ at AS USIZE ]
 |  \_
 |
 | ; 1 to 9: to the tab with that number -- made, at home, if there is none
 | ABYSS goto_slot: [ I32 slot ]
 |  | I32 at = (tab_at_slot)[ me | slot ]
 |  | IF [ at < 0 ]
 |  |  | at = (tab_add)[ me | ((env)[ "HOME" ].unwrap_or)[ "/" ] | 0 | slot ]
 |  |  \_
 |  | (me.open_tab)[ at AS USIZE ]
 |  \_
 |
 | ; Shift and 1 to 9: the tab with that number here, where the open one
 | ; is -- made, or moved -- and opened
 | ABYSS here_slot: [ I32 slot ]
 |  | I32 cursor = me.listing.table.list.cursor
 |  | I32 at = (tab_at_slot)[ me | slot ]
 |  | IF [ at == (me.tab AS I32) ]
 |  |  | RET []
 |  |  \_
 |  | IF [ at < 0 ]
 |  |  | at = (tab_add)[ me | (me.cwd.cstr)[] | cursor | slot ]
 |  | ELSE
 |  |  | @Tab t = (me.tabs.at)[ at AS USIZE ]
 |  |  | (t.cwd.deinit)[]
 |  |  | (t.label.deinit)[]
 |  |  | t.cwd = (String.of)[ (me.cwd.cstr)[] ]
 |  |  | t.label = (folder_name)[ (me.cwd.cstr)[] ]
 |  |  | t.cursor = cursor
 |  |  \_
 |  | (me.open_tab)[ at AS USIZE ]
 |  \_
 |
 | ; the open tab closed, unless it is the last; the one after it opens
 | ABYSS close_tab: []
 |  | IF [ (me.tabs.size)[] <= 1 ]
 |  |  | RET []
 |  |  \_
 |  | USIZE gone = me.tab AS USIZE
 |  | Tab t = (me.tabs.remove)[ gone ]
 |  | (tab_free)[ @t ]
 |  | IF [ gone >= (me.tabs.size)[] ]
 |  |  | gone = (me.tabs.size)[] - 1
 |  |  \_
 |  | me.tab = gone AS U32
 |  | (tab_enter)[ me ]
 |  \_
 |
 | ABYSS dispose: []
 |  | (me.cwd.deinit)[]
 |  | (me.rel_cwd.deinit)[]
 |  | (me.partition.name.deinit)[]
 |  | (dispose_root)[ @(me.root) ]
 |  | (dispose_main)[ @(me.listing) ]
 |  | (dispose_preview)[ @(me.preview) ]
 |  | (dispose_places)[ @(me.places) ]
 |  | FOR [ USIZE i = 0 | i < (me.tabs.size)[] | i += 1 ]
 |  |  | (tab_free)[ (me.tabs.at)[ i ] ]
 |  |  \_
 |  | (me.tabs.deinit)[]
 |  | FOR [ USIZE i = 0 | i < (me.tasks.size)[] | i += 1 ]
 |  |  | (task_free)[ (me.tasks.at)[ i ] ]
 |  |  \_
 |  | (me.tasks.deinit)[]
 |  | (strings_clear)[ @(me.clip) ]
 |  | (me.clip.deinit)[]
 |  | (strings_clear)[ @(me.pending) ]
 |  | (me.pending.deinit)[]
 |  | (strings_clear)[ @(me.undo_from) ]
 |  | (me.undo_from.deinit)[]
 |  | (strings_clear)[ @(me.undo_put) ]
 |  | (me.undo_put.deinit)[]
 |  | (me.renaming.deinit)[]
 |  | (me.cd_file.deinit)[]
 |  | (me.clash_one.deinit)[]
 |  | (strings_clear)[ @(me.choices) ]
 |  | (me.choices.deinit)[]
 |  | (me.note.deinit)[]
 |  \_
 |
 + ANONYMOUS:
 | Self make: [ String cwd ]
 |  | Self s
 |  | (s.tabs.push)[ (tab_of)[ "" | 0 | 1 ] ]
 |  | s.tab = 0
 |  | s.close_tab = -1
 |  | s.listing.table.sort = CFG.sort
 |  | s.listing.table.desc = CFG.sort_desc
 |  | (app_enter)[ @s | cwd ]
 |  | ; the config's tabs after the one asked for; one not there is left out
 |  | FOR [ USIZE i = 0 | i < (CFG.tabs.size)[] && (s.tabs.size)[] < MAX_TABS | i += 1 ]
 |  |  | Result<String | IoError> full = (get_realpath)[ ((CFG.tabs.at)[ i ].cstr)[] ]
 |  |  | IF [ (full.is_ok)[] ]
 |  |  |  | String f = (full.unwrap)[]
 |  |  |  | (s.tabs.push)[ (tab_of)[ (f.cstr)[] | 0 | ((s.tabs.size)[] AS I32) + 1 ] ]
 |  |  |  | (f.deinit)[]
 |  |  |  \_
 |  |  \_
 |  | RET [ s ]
 |  \_
 \_

CLASS App: AppData IMPL [ AppOps ]
