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
!USES <../fs.pl>
!USES <../look.pl>

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
 \_

ABYSS dispose_main: [ @MainPane p ]
 | (p.cwd.deinit)[]
 | (p.name.deinit)[]
 | (records_free)[ @(p.files) ]
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
 | FOR [ USIZE i = 0 | i < n | i += 1 ]
 |  | IF [ (str_eq)[ ((p.files.at)[i].name.cstr)[] | keep AS @CONST C1 ] ]
 |  |  | p.table.list.cursor = i AS I32
 |  |  \_
 |  \_
 \_

; --- reading --------------------------------------------------------------------

; read again when the current folder is another one, sorted again when the
; header was clicked
ABYSS update_main: [ @MainPane p | @CONST C1 cwd ]
 | IF [ !((p.cwd.equals)[ cwd ]) ]
 |  | (p.cwd.deinit)[]
 |  | p.cwd = (String.of)[ cwd ]
 |  | (p.name.deinit)[]
 |  | p.name = (folder_name)[ cwd ]
 |  | p.year = (now_utc)[].year
 |  |
 |  | (read_folder)[ @(p.files) | cwd | TRUE | "" ]
 |  | (main_sort)[ p ]
 |  | p.table.list.cursor = 0       ; sorting kept it on a file: not wanted here
 |  \_
 | IF [ p.table.sort != p.sort || p.table.desc != p.desc ]
 |  | (main_sort)[ p ]
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
 | (ui.table_row)[ @(p.table) | i | id ]
 |
 | ; the icon and the name are of one column, in two colours
 | C1 name{280}
 | BufferSink b = (BufferSink.over)[ name | 280 ]
 | (b.print)[ SELECT [ e.broken | "%s → missing" | SELECT [ e.dir | "%s/" | "%s" ] ] | (e.name.cstr)[] ]
 | (draw_icon)[ ui | e ]
 | (ui.put_cell)[ (fg)[ (record_color)[ e | i == p.table.list.cursor ] ] | name AS @CONST C1 | p.table.sized{COL_NAME} - ICON_W | TRUE ]
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
 | (ui.table_cell)[ @(p.table) | (fg)[ DIM ] | size AS @CONST C1 ]
 | (ui.table_cell)[ @(p.table) | (fg)[ DIM ] | date AS @CONST C1 ]
 \_

ABYSS main_pane: [ @Ui ui | @MainPane p | @CONST C1 cwd ]
 | (update_main)[ p | cwd ]
 | U32 id = (ui.id)[ "main" ]
 | I32 n = (p.files.size)[] AS I32
 |
 | IF [ (ui.focused)[ id ] ]
 |  | IF [ (ui.take)[ 'j' AS U32 ] ]
 |  |  | p.table.list.cursor += 1
 |  | ELIF [ (ui.take)[ 'k' AS U32 ] ]
 |  |  | p.table.list.cursor -= 1
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
 | (ui.table)[ @(p.table) | id | MAIN_HEADS | p.widths AS @CONST I32 | 3 | n | GROW | GROW ]
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | (main_row)[ ui | p | i | id ]
 |  \_
 | (ui.table_end)[]
 | (ui.close)[]
 \_
