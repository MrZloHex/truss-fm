; main.pl -- the main column: the current folder as a table of name, size and
; date, sorted by whichever of them the header was clicked on

USE <std/core/core.pl>
USE <std/core/sort.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

USE <modular.pl>
!USES <common.pl>
!USES <../core/fs.pl>
!USES <look.pl>
!USES <../core/config.pl>

; the columns, in the order the header has them
CONST I32 COL_NAME = 0
CONST I32 COL_SIZE = 1
CONST I32 COL_DATE = 2
CONST @CONST C1 MAIN_HEADS{} = [ "NAME" | "SIZE" | "DATE" ]

CONST I32 MAIN_SIZE = 5
CONST I32 MAIN_DATE = 6
CONST I32 MAIN_EDGES = 4    ; a cell before each column and after the last
CONST I32 MAIN_NAME = 8     ; the least a name gets; it takes what is left

TYPE MainPane: STRUCT
 | TableState table
 | I32 widths{3}            ; the table keeps a pointer to them
 |
 | String cwd               ; the folder it was read for
 | String name              ; its last part, the title
 |
 | I64 year                 ; a date of this year leaves its year out
 | I32 sort                 ; the column `files` is sorted by now
 | B1 desc
 |
 | Vector<FileRecord> files
 | I32 restore              ; the row to put the cursor on, plus one; 0: none
 | B1 stale                 ; the folder changed: read it again, the cursor kept
 | I64 seen_sec             ; the folder's own time when it was read: an entry
 | U32 seen_nsec            ;   made or taken away changes it
 | B1 visual                 ; V: the rows from `anchor` to the cursor are chosen
 | I32 anchor
 | B1 want_open             ; l, →, Enter on a file: the program opens it
 | String anchor_name       ; the file `anchor` is on: a row moves as the folder
 |                          ;   is read again or sorted, the file does not
 \_

ABYSS dispose_main: [ @MainPane p ]
 | (p.cwd.deinit)[]
 | (p.name.deinit)[]
 | (records_free)[ @(p.files) ]
 | (p.anchor_name.deinit)[]
 \_

; --- the visual selection --------------------------------------------------------

; the full path of row `i`; empty when there is no such row
String main_path: [ @MainPane p | I32 i ]
 | @FileRecord e = (record_at)[ @(p.files) | i ]
 | IF [ e == NULL ]
 |  | RET [ (String.of)[ "" ] ]
 |  \_
 | RET [ (join_path)[ (p.cwd.cstr)[] | (e.name.cstr)[] ] ]
 \_

; the chosen rows, `lo` to `hi` both in; FALSE: none, not in visual
B1 chosen_rows: [ @MainPane p | @I32 lo | @I32 hi ]
 | I32 n = (p.files.size)[] AS I32
 | IF [ !(p.visual) || n == 0 ]
 |  | RET [ FALSE ]
 |  \_
 | I32 a = SELECT [ p.anchor < n | p.anchor | n - 1 ]
 | I32 c = p.table.list.cursor
 | ?lo = SELECT [ a < c | a | c ]
 | ?hi = SELECT [ a < c | c | a ]
 | RET [ TRUE ]
 \_

B1 row_chosen: [ @MainPane p | I32 i ]
 | I32 lo = 0
 | I32 hi = 0
 | RET [ (chosen_rows)[ p | @lo | @hi ] && i >= lo && i <= hi ]
 \_

ABYSS visual_off: [ @MainPane p ]
 | p.visual = FALSE
 \_

; visual from the row under the cursor, held by its file's name
ABYSS visual_on: [ @MainPane p ]
 | @FileRecord e = (record_at)[ @(p.files) | p.table.list.cursor ]
 | IF [ e == NULL ]
 |  | RET []
 |  \_
 | p.visual = TRUE
 | p.anchor = p.table.list.cursor
 | (p.anchor_name.deinit)[]
 | p.anchor_name = (String.of)[ (e.name.cstr)[] ]
 \_

; after the rows moved: the anchor back on its file, or visual ended if
; that file is gone -- never on another file in its place
ABYSS anchor_fix: [ @MainPane p ]
 | IF [ !(p.visual) ]
 |  | RET []
 |  \_
 | I32 at = (main_find)[ p | (p.anchor_name.cstr)[] | -1 ]
 | IF [ at < 0 ]
 |  | p.visual = FALSE
 | ELSE
 |  | p.anchor = at
 |  \_
 \_

; what an operation works on, in `out` as new strings: the rows chosen in
; visual, or out of it the file under the cursor. Visual ends
ABYSS main_selection: [ @MainPane p | @Vector<String> out ]
 | I32 lo = 0
 | I32 hi = 0
 | IF [ (chosen_rows)[ p | @lo | @hi ] ]
 |  | FOR [ I32 i = lo | i <= hi | i += 1 ]
 |  |  | (out.push)[ (main_path)[ p | i ] ]
 |  |  \_
 |  | p.visual = FALSE
 |  | RET []
 |  \_
 | String path = (main_path)[ p | p.table.list.cursor ]
 | IF [ (path.size)[] > 0 ]
 |  | (out.push)[ path ]
 | ELSE
 |  | (path.deinit)[]
 |  \_
 \_

; --- sorting --------------------------------------------------------------------

; folders, files, hidden ones, broken links
I32 main_rank: [ @CONST FileRecord e ]
 | IF [ e.broken ]
 |  | RET [ 3 ]
 |  \_
 | IF [ e.dir ]
 |  | RET [ 0 ]
 |  \_
 | RET [ SELECT [ e.hidden | 2 | 1 ] ]
 \_

B1 main_before_rank: [ @CONST FileRecord a | @CONST FileRecord b ]
 | RET [ (main_rank)[ a ] < (main_rank)[ b ] ]
 \_

B1 main_before_name: [ @CONST FileRecord a | @CONST FileRecord b ]
 | RET [ (str_cmp)[ (a.name.cstr)[] | (b.name.cstr)[] ] < 0 ]
 \_

; a folder's size is how many entries it has, as the column shows
B1 main_before_size: [ @CONST FileRecord a | @CONST FileRecord b ]
 | U64 x = SELECT [ a.dir | a.count AS U64 | a.size ]
 | U64 y = SELECT [ b.dir | b.count AS U64 | b.size ]
 | RET [ x < y ]
 \_

B1 main_before_date: [ @CONST FileRecord a | @CONST FileRecord b ]
 | RET [ a.modified < b.modified ]
 \_

; by the table's column and direction, then by rank: stable, so the column's
; order stays inside each rank. The cursor stays on its file
ABYSS main_sort: [ @MainPane p ]
 | USIZE n = (p.files.size)[]
 | p.sort = p.table.sort
 | p.desc = p.table.desc
 | IF [ n == 0 ]
 |  | RET []
 |  \_
 |
 | C1 keep{256}
 | keep{0} = '\0'
 | I32 at = p.table.list.cursor
 | IF [ at >= 0 && (at AS USIZE) < n ]
 |  | (str_copy)[ keep | 256 | ((p.files.at)[ at AS USIZE ].name.cstr)[] ]
 |  \_
 |
 | IF [ p.sort == COL_SIZE ]
 |  | (sort_stable_by<FileRecord>)[ p.files.data | n | main_before_size ]
 | ELIF [ p.sort == COL_DATE ]
 |  | (sort_stable_by<FileRecord>)[ p.files.data | n | main_before_date ]
 | ELSE
 |  | (sort_stable_by<FileRecord>)[ p.files.data | n | main_before_name ]
 |  \_
 | IF [ p.desc ]
 |  | (p.files.reverse)[]
 |  \_
 | (sort_stable_by<FileRecord>)[ p.files.data | n | main_before_rank ]
 |
 | p.table.list.cursor = (main_find)[ p | keep AS @CONST C1 | p.table.list.cursor ]
 | (anchor_fix)[ p ]
 \_

; the folder's time, as it is now
ABYSS main_seen: [ @MainPane p ]
 | Result<FileInfo | IoError> r = (fs_info)[ (p.cwd.cstr)[] ]
 | IF [ (r.is_ok)[] ]
 |  | FileInfo i = (r.unwrap)[]
 |  | p.seen_sec = i.modified
 |  | p.seen_nsec = i.modified_ns
 |  \_
 \_

; has an entry been made or taken away since the folder was read?
B1 main_changed: [ @MainPane p ]
 | Result<FileInfo | IoError> r = (fs_info)[ (p.cwd.cstr)[] ]
 | IF [ (r.is_err)[] ]
 |  | RET [ TRUE ]
 |  \_
 | FileInfo i = (r.unwrap)[]
 | RET [ i.modified != p.seen_sec || i.modified_ns != p.seen_nsec ]
 \_

; the row of the file named `name`; `none` when there is no such file
I32 main_find: [ @MainPane p | @CONST C1 name | I32 none ]
 | FOR [ USIZE i = 0 | i < (p.files.size)[] | i += 1 ]
 |  | IF [ (str_eq)[ ((p.files.at)[i].name.cstr)[] | name ] ]
 |  |  | RET [ i AS I32 ]
 |  |  \_
 |  \_
 | RET [ none ]
 \_

; --- reading --------------------------------------------------------------------

; read again when the current folder is another one, sorted again when the
; header was clicked. The cursor starts at the top; after going up, on the
; folder it came from
ABYSS update_main: [ @MainPane p | @CONST C1 cwd ]
 | IF [ !((p.cwd.equals)[ cwd ]) ]
 |  | p.visual = FALSE
 |  | String from = (get_dirname)[ (p.cwd.cstr)[] ]
 |  | POSTLUDE (from.deinit)[]
 |  | String above = (get_parent_path)[ (p.cwd.cstr)[] ]
 |  | POSTLUDE (above.deinit)[]
 |  | B1 went_up = (p.cwd.size)[] > 0 && (above.equals)[ cwd ]
 |  |
 |  | (p.cwd.deinit)[]
 |  | p.cwd = (String.of)[ cwd ]
 |  | (p.name.deinit)[]
 |  | p.name = (folder_name)[ cwd ]
 |  | p.year = (now_utc)[].year
 |  |
 |  | (read_folder)[ @(p.files) | cwd | CFG.hidden | "" ]
 |  | (main_seen)[ p ]
 |  | (main_sort)[ p ]
 |  | p.table.list.cursor = SELECT [ went_up | (main_find)[ p | (from.cstr)[] | 0 ] | 0 ]
 |  \_
 | IF [ p.stale ]
 |  | ; the cursor stays on its file, or where it was if that is gone
 |  | String keep = (main_path)[ p | p.table.list.cursor ]
 |  | POSTLUDE (keep.deinit)[]
 |  | String name = (get_dirname)[ (keep.cstr)[] ]
 |  | POSTLUDE (name.deinit)[]
 |  | (read_folder)[ @(p.files) | cwd | CFG.hidden | "" ]
 |  | (main_seen)[ p ]
 |  | (main_sort)[ p ]
 |  | I32 n = (p.files.size)[] AS I32
 |  | I32 was = SELECT [ p.table.list.cursor < n | p.table.list.cursor | n - 1 ]
 |  | p.table.list.cursor = (main_find)[ p | (name.cstr)[] | SELECT [ was < 0 | 0 | was ] ]
 |  | (anchor_fix)[ p ]
 |  | p.stale = FALSE
 |  \_
 | IF [ p.table.sort != p.sort || p.table.desc != p.desc ]
 |  | (main_sort)[ p ]
 |  \_
 | ; a tab come back to: its row. Last, so it holds when two tabs share a folder
 | IF [ p.restore > 0 ]
 |  | p.table.list.cursor = p.restore - 1
 |  | p.restore = 0
 |  \_
 \_

; --- drawing --------------------------------------------------------------------

; 22 Oct; from another year, the year
ABYSS date_text: [ @C1 out | I64 when | I64 year ]
 | DateTime d = (date_of_unix)[ when ]
 | BufferSink b = (BufferSink.over)[ out | 16 ]
 | IF [ d.year == year ]
 |  | (b.print)[ "%02d %s" | d.day AS I32 | MONTHS{(d.month AS I32) - 1} ]
 | ELSE
 |  | (b.print)[ "%d" | d.year AS I32 ]
 |  \_
 \_

ABYSS main_row: [ @Ui ui | @MainPane p | I32 i | U32 id ]
 | @FileRecord e = (p.files.at)[ i AS USIZE ]
 | @Node row = (ui.table_row)[ @(p.table) | i | id ]
 | ; a chosen row is filled whole, as the cursor's is: not cell by cell
 | B1 picked = (row_chosen)[ p | i ]
 | B1 here = i == p.table.list.cursor
 | IF [ picked ]
 |  | (row.background)[ SELECT [ here | C_CHOSEN_CUR | C_CHOSEN ] ]
 |  \_
 |
 | ; the icon and the name are of one column, in two colours
 | C1 name{280}
 | BufferSink b = (BufferSink.over)[ name | 280 ]
 | (b.print)[ SELECT [ e.broken | "%s → missing" | SELECT [ e.dir | "%s/" | "%s" ] ] | (e.name.cstr)[] ]
 | (draw_icon)[ ui | e ]
 | (ui.put_cell)[ (fg)[ (record_color)[ e | picked || here ] ] | name AS @CONST C1 | p.table.sized{COL_NAME} - ICON_W | TRUE ]
 | (ui.pen)[ (fg)[ TEXT ] ]
 | (ui.spaces)[ 1 ]
 | p.table.col = COL_SIZE
 |
 | IF [ e.broken ]
 |  | (ui.table_cell)[ @(p.table) | (fg)[ DIM ] | "—" ]
 |  | (ui.table_cell)[ @(p.table) | (fg)[ DIM ] | "link" ]
 |  | RET []
 |  \_
 | C1 size{16}
 | (side_text)[ size | e ]
 | C1 date{16}
 | (date_text)[ date | e.modified | p.year ]
 | Style side = (fg)[ SELECT [ picked | TEXT2 | DIM ] ]
 | (ui.table_cell)[ @(p.table) | side | size AS @CONST C1 ]
 | (ui.table_cell)[ @(p.table) | side | date AS @CONST C1 ]
 \_

; `go`: the folder it asks to go to, if one was opened or left
ABYSS main_pane: [ @Ui ui | @MainPane p | @CONST C1 cwd | @String go ]
 | (update_main)[ p | cwd ]
 | U32 id = (ui.id)[ "main" ]
 | I32 n = (p.files.size)[] AS I32
 |
 | IF [ (ui.focused)[ id ] ]
 |  | (move_keys)[ ui | @(p.table.list.cursor) ]
 |  | I32 how = (go_keys)[ ui ]
 |  | @CONST FileRecord e = (record_at)[ @(p.files) | p.table.list.cursor ]
 |  | (ask_go)[ go | how | cwd | cwd | e ]
 |  | ; into a file: it is opened, as the config says
 |  | p.want_open = how == GO_IN && e != NULL && !(e.dir) && !(e.broken)
 |  | ; V: visual line, from here to wherever the cursor goes; V again or
 |  | ; Esc ends it
 |  | IF [ (ui.take)[ 'V' AS U32 ] ]
 |  |  | IF [ p.visual ]
 |  |  |  | (visual_off)[ p ]
 |  |  | ELSE
 |  |  |  | (visual_on)[ p ]
 |  |  |  \_
 |  |  \_
 |  \_
 |
 | ; the name takes what the other columns leave, as wide as the pane is
 | I32 width = (ui.rect_of)[ id ].w - MAIN_SIZE - MAIN_DATE - MAIN_EDGES
 | p.widths{COL_NAME} = SELECT [ width < MAIN_NAME | MAIN_NAME | width ]
 | p.widths{COL_SIZE} = -MAIN_SIZE
 | p.widths{COL_DATE} = -MAIN_DATE
 |
 | (ui.box)[ "" | GROW | GROW ]
 | (ui.title)[]
 | ((ui.pen)[ ui.theme.title ].print)[ "%s · %d" | (p.name.cstr)[] | n ]
 | ; the mode, in the bottom edge, as vim has it at the bottom
 | I32 lo = 0
 | I32 hi = 0
 | IF [ (chosen_rows)[ p | @lo | @hi ] ]
 |  | (ui.subtitle)[]
 |  | ((ui.pen)[ (bold)[ C_MARK ] ].print)[ "-- VISUAL LINE -- %d" | hi - lo + 1 ]
 |  \_
 | (ui.table)[ @(p.table) | id | MAIN_HEADS | p.widths AS @CONST I32 | 3 | n | GROW | GROW ]
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | (main_row)[ ui | p | i | id ]
 |  \_
 | (ui.table_end)[]
 | (ui.close)[]
 \_
