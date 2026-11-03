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
!USES <../core/sys.pl>

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
 | Vector<FileRecord> all    ; the folder as read, sorted: these own the names
 | Vector<FileRecord> files  ; what is shown: `all` that the filter lets through,
 |                          ;   copies sharing their names -- never freed here
 | String filter            ; / typed: the letters a name must hold, in order
 | I32 restore              ; the row to put the cursor on, plus one; 0: none
 | B1 stale                 ; the folder changed: read it again, the cursor kept
 | I64 seen_sec             ; the folder's own time when it was read: an entry
 | U32 seen_nsec            ;   made or taken away changes it
 | B1 visual                 ; V: the rows from `anchor` to the cursor are chosen
 | I32 anchor
 | B1 want_open             ; l, →, Enter on a file: the program opens it
 | B1 sorting               ; s was pressed: n, s, d or r says how
 | B1 want_menu             ; a right press on a row: its actions are offered
 | String anchor_name       ; the file `anchor` is on: a row moves as the folder
 |                          ;   is read again or sorted, the file does not
 \_

ABYSS dispose_main: [ @MainPane p ]
 | (p.cwd.deinit)[]
 | (p.name.deinit)[]
 | (records_free)[ @(p.all) ]
 | (p.files.deinit)[]
 | (p.filter.deinit)[]
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
 | p.sort = p.table.sort
 | p.desc = p.table.desc
 | C1 keep{256}
 | (main_cursor_name)[ p | keep ]
 |
 | USIZE n = (p.all.size)[]
 | IF [ p.sort == COL_SIZE ]
 |  | (sort_stable_by<FileRecord>)[ p.all.data | n | main_before_size ]
 | ELIF [ p.sort == COL_DATE ]
 |  | (sort_stable_by<FileRecord>)[ p.all.data | n | main_before_date ]
 | ELSE
 |  | (sort_stable_by<FileRecord>)[ p.all.data | n | main_before_name ]
 |  \_
 | IF [ p.desc ]
 |  | (p.all.reverse)[]
 |  \_
 | (sort_stable_by<FileRecord>)[ p.all.data | n | main_before_rank ]
 |
 | (main_view)[ p ]
 | p.table.list.cursor = (main_find)[ p | keep AS @CONST C1 | p.table.list.cursor ]
 | (anchor_fix)[ p ]
 \_

; the name under the cursor, in `out` (256): "" when there is none
ABYSS main_cursor_name: [ @MainPane p | @C1 out ]
 | out{0} = '\0'
 | @FileRecord e = (record_at)[ @(p.files) | p.table.list.cursor ]
 | IF [ e != NULL ]
 |  | (str_copy)[ out | 256 | (e.name.cstr)[] ]
 |  \_
 \_

; the folder read into `all`, sorted, and the view made of it. The view
; goes first: its copies' names are freed with the old `all`
ABYSS main_read: [ @MainPane p | @CONST C1 cwd ]
 | (p.files.clear)[]
 | (read_folder)[ @(p.all) | cwd | CFG.hidden | "" ]
 | (main_seen)[ p ]
 | (main_sort)[ p ]
 \_

; does `name` hold the letters of `q`, in order? Case counts only when `q`
; has a capital. In `hits`, a bit for each of name's first 64 bytes matched
B1 fuzzy_hit: [ @CONST C1 name | @CONST C1 q | @U64 hits ]
 | B1 exact = FALSE
 | FOR [ USIZE k = 0 | q{k} != '\0' | k += 1 ]
 |  | IF [ q{k} >= 'A' && q{k} <= 'Z' ]
 |  |  | exact = TRUE
 |  |  \_
 |  \_
 | U64 m = 0
 | USIZE j = 0
 | FOR [ USIZE i = 0 | name{i} != '\0' && q{j} != '\0' | i += 1 ]
 |  | C1 a = name{i}
 |  | C1 b = q{j}
 |  | IF [ !exact && a >= 'A' && a <= 'Z' ]
 |  |  | a = (a + 32) AS C1
 |  |  \_
 |  | IF [ !exact && b >= 'A' && b <= 'Z' ]
 |  |  | b = (b + 32) AS C1
 |  |  \_
 |  | IF [ a == b ]
 |  |  | IF [ i < 64 ]
 |  |  |  | m = m | ((1 AS U64) << (i AS U64))
 |  |  |  \_
 |  |  | j += 1
 |  |  \_
 |  \_
 | ?hits = m
 | RET [ q{j} == '\0' ]
 \_

; `files` made again: what of `all` the filter lets through
ABYSS main_view: [ @MainPane p ]
 | (p.files.clear)[]
 | @CONST C1 q = (p.filter.cstr)[]
 | FOR [ USIZE i = 0 | i < (p.all.size)[] | i += 1 ]
 |  | @FileRecord e = (p.all.at)[ i ]
 |  | U64 hits = 0
 |  | IF [ q{0} == '\0' || (fuzzy_hit)[ (e.name.cstr)[] | q | @hits ] ]
 |  |  | (p.files.push)[ ?e ]
 |  |  \_
 |  \_
 \_

; the filter `q`: what it lets through shown, the cursor on its file if
; that is still there, else at the top
ABYSS main_filter: [ @MainPane p | @CONST C1 q ]
 | C1 keep{256}
 | (main_cursor_name)[ p | keep ]
 | (p.filter.deinit)[]
 | p.filter = (String.of)[ q ]
 | (main_view)[ p ]
 | p.table.list.cursor = (main_find)[ p | keep AS @CONST C1 | 0 ]
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
 |  | p.year = (local_date)[ (unix_time)[] ].year
 |  | ; a filter is for the folder it was typed in
 |  | (p.filter.deinit)[]
 |  | p.filter = (String.of)[ "" ]
 |  |
 |  | (main_read)[ p | cwd ]
 |  | p.table.list.cursor = SELECT [ went_up | (main_find)[ p | (from.cstr)[] | 0 ] | 0 ]
 |  \_
 | IF [ p.stale ]
 |  | ; the cursor stays on its file, or where it was if that is gone
 |  | String keep = (main_path)[ p | p.table.list.cursor ]
 |  | POSTLUDE (keep.deinit)[]
 |  | String name = (get_dirname)[ (keep.cstr)[] ]
 |  | POSTLUDE (name.deinit)[]
 |  | (main_read)[ p | cwd ]
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
 | DateTime d = (local_date)[ when ]
 | BufferSink b = (BufferSink.over)[ out | 16 ]
 | IF [ d.year == year ]
 |  | (b.print)[ "%02d %s" | d.day AS I32 | MONTHS{(d.month AS I32) - 1} ]
 | ELSE
 |  | (b.print)[ "%d" | d.year AS I32 ]
 |  \_
 \_

; how many cells `s` takes: its characters, not its bytes
I32 name_cells: [ @CONST C1 s ]
 | I32 n = 0
 | FOR [ USIZE i = 0 | s{i} != '\0' | i += 1 ]
 |  | IF [ ((s{i} AS U8) & 0xC0) != 0x80 ]
 |  |  | n += 1
 |  |  \_
 |  \_
 | RET [ n ]
 \_

; `s` in `width` cells, the characters the filter matched (`hits`) in
; C_MATCH, the rest in `c`
ABYSS name_lit: [ @Ui ui | @CONST C1 s | U64 hits | Color c | I32 width ]
 | USIZE i = 0
 | WHILE [ s{i} != '\0' ]
 |  | C1 one{8}
 |  | USIZE n = 0
 |  | one{n} = s{i}
 |  | n += 1
 |  | WHILE [ s{i + n} != '\0' && ((s{i + n} AS U8) & 0xC0) == 0x80 && n < 7 ]
 |  |  | one{n} = s{i + n}
 |  |  | n += 1
 |  |  \_
 |  | one{n} = '\0'
 |  | B1 lit = i < 64 && (hits & ((1 AS U64) << (i AS U64))) != 0
 |  | ; colour alone: a style with more would lose the row's fill
 |  | IF [ lit ]
 |  |  | (ui.put)[ (fg)[ C_MATCH ] | one AS @CONST C1 ]
 |  | ELSE
 |  |  | (ui.put)[ (fg)[ c ] | one AS @CONST C1 ]
 |  |  \_
 |  | i += n
 |  \_
 | I32 left = width - (name_cells)[ s ]
 | IF [ left > 0 ]
 |  | (ui.spaces)[ left ]
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
 | Color c = (record_color)[ e | picked || here ]
 | I32 width = p.table.sized{COL_NAME} - ICON_W
 | U64 hits = 0
 | IF [ (p.filter.size)[] > 0 && (fuzzy_hit)[ (e.name.cstr)[] | (p.filter.cstr)[] | @hits ] && (name_cells)[ name AS @CONST C1 ] <= width ]
 |  | (name_lit)[ ui | name AS @CONST C1 | hits | c | width ]
 | ELSE
 |  | (ui.put_cell)[ (fg)[ c ] | name AS @CONST C1 | width | TRUE ]
 |  \_
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
 |  | (move_keys)[ ui | @(p.table.list) ]
 |  | I32 how = (go_keys)[ ui ]
 |  | @CONST FileRecord e = (record_at)[ @(p.files) | p.table.list.cursor ]
 |  | (ask_go)[ go | how | cwd | cwd | e ]
 |  | ; into a file: it is opened, as the config says
 |  | p.want_open = how == GO_IN && e != NULL && !(e.dir) && !(e.broken)
 |  | ; s and n, s, d: by name, size, date -- the same again the other way;
 |  | ; s r the other way. Any other key gives it up
 |  | IF [ p.sorting && (ui.key)[] != 0 ]
 |  |  | p.sorting = FALSE
 |  |  | I32 col = -1
 |  |  | IF [ (ui.take)[ 'n' AS U32 ] ]
 |  |  |  | col = COL_NAME
 |  |  | ELIF [ (ui.take)[ 's' AS U32 ] ]
 |  |  |  | col = COL_SIZE
 |  |  | ELIF [ (ui.take)[ 'd' AS U32 ] ]
 |  |  |  | col = COL_DATE
 |  |  | ELIF [ (ui.take)[ 'r' AS U32 ] ]
 |  |  |  | p.table.desc = !(p.table.desc)
 |  |  | ELIF [ (ui.key)[] != 0 ]
 |  |  |  | (ui.consume)[]
 |  |  |  \_
 |  |  | IF [ col >= 0 ]
 |  |  |  | p.table.desc = col == p.table.sort && !(p.table.desc)
 |  |  |  | p.table.sort = col
 |  |  |  \_
 |  |  | (ui.redo)[]
 |  | ELIF [ (ui.take)[ 's' AS U32 ] ]
 |  |  | p.sorting = TRUE
 |  |  | (ui.redo)[]
 |  |  \_
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
 | IF [ (p.filter.size)[] > 0 ]
 |  | ((ui.pen)[ ui.theme.title ].print)[ "%s · %d of %d" | (p.name.cstr)[] | n | (p.all.size)[] AS I32 ]
 | ELSE
 |  | ((ui.pen)[ ui.theme.title ].print)[ "%s · %d" | (p.name.cstr)[] | n ]
 |  \_
 | ; the mode, in the bottom edge, as vim has it at the bottom
 | I32 lo = 0
 | I32 hi = 0
 | IF [ p.sorting ]
 |  | (ui.subtitle)[]
 |  | ((ui.pen)[ (bold)[ C_MARK ] ].print)[ "sort: [n]ame [s]ize [d]ate [r]everse" ]
 | ELIF [ (chosen_rows)[ p | @lo | @hi ] ]
 |  | (ui.subtitle)[]
 |  | ((ui.pen)[ (bold)[ C_MARK ] ].print)[ "-- VISUAL LINE -- %d" | hi - lo + 1 ]
 |  \_
 | ; the mouse, before the table takes the press: a right one puts the
 | ; cursor on its row and offers its actions; Shift and a left one chooses
 | ; from the cursor to that row, as V; a plain one ends a choosing
 | I32 right = (press_row)[ ui | id | @(p.table.list) | BTN_RIGHT | 1 ]
 | IF [ right >= 0 && !(ui.used) ]
 |  | (ui.consume)[]
 |  | p.table.list.cursor = right
 |  | (ui.set_focus)[ id ]
 |  | p.want_menu = TRUE
 |  \_
 | IF [ !(ui.used) && (press_row)[ ui | id | @(p.table.list) | BTN_LEFT | 1 ] >= 0 ]
 |  | IF [ (ui.ev.mods & MOD_SHIFT) != 0 ]
 |  |  | IF [ !(p.visual) ]
 |  |  |  | (visual_on)[ p ]
 |  |  |  \_
 |  | ELIF [ p.visual && ui.ev.clicks < 2 ]
 |  |  | (visual_off)[ p ]
 |  |  \_
 |  \_
 | (ui.table)[ @(p.table) | id | MAIN_HEADS | p.widths AS @CONST I32 | 3 | n | GROW | GROW ]
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | (main_row)[ ui | p | i | id ]
 |  \_
 | (ui.table_end)[]
 | (ui.close)[]
 |
 | ; a double press on a row, its first having put the cursor there: into
 | ; a folder, a file opened -- as Enter
 | IF [ (press_row)[ ui | id | @(p.table.list) | BTN_LEFT | 2 ] == p.table.list.cursor ]
 |  | @CONST FileRecord e = (record_at)[ @(p.files) | p.table.list.cursor ]
 |  | (ask_go)[ go | GO_IN | cwd | cwd | e ]
 |  | p.want_open = e != NULL && !(e.dir) && !(e.broken)
 |  \_
 \_
