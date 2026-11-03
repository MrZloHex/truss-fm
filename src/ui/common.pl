; common.pl -- what the columns share: a file's record, a folder read into
; records, and the pieces of a row that more than one column draws

USE <std/core/core.pl>
USE <std/core/sort.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

USE <modular.pl>
!USES <../core/fs.pl>
!USES <look.pl>

CONST I32 ICON_W = 2        ; ▸, ✗ or nothing, and a space
CONST I32 SIDE_W = 5        ; a count or a size: 142, 19.1M
CONST I32 BAR_W = 1         ; a list's last cell is its scrollbar's
CONST I32 NAME_MIN = 4      ; the least a name gets; it takes what is left

TYPE FileRecord: STRUCT
 | String name
 | B1 dir
 | B1 broken                ; a link to nothing
 | B1 hidden
 | B1 exec                  ; a file someone may run: a x in its mode
 | I32 count                ; a folder's entries; -1: it cannot be read
 | U64 size
 | I64 modified             ; seconds since 1970
 \_

; --- records --------------------------------------------------------------------

ABYSS records_clear: [ @Vector<FileRecord> v ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | ((v.at)[i].name.deinit)[]
 |  \_
 | (v.clear)[]
 \_

ABYSS records_free: [ @Vector<FileRecord> v ]
 | (records_clear)[ v ]
 | (v.deinit)[]
 \_

; the record in row `i`; NULL when there is none, as in an empty folder
@FileRecord record_at: [ @Vector<FileRecord> v | I32 i ]
 | IF [ i < 0 || (i AS USIZE) >= (v.size)[] ]
 |  | RET [ NULL ]
 |  \_
 | RET [ (v.at)[ i AS USIZE ] ]
 \_

; how many entries a folder has; -1: it cannot be read
I32 count_entries: [ @CONST C1 path ]
 | Result<os:Dir | IoError> d = (os:Dir.open)[ path ]
 | IF [ (d.is_err)[] ]
 |  | RET [ -1 ]
 |  \_
 | os:Dir dir = (d.unwrap)[]
 | POSTLUDE (dir.close)[]
 | I32 n = 0
 | DirEntry e
 | WHILE [ (dir.next)[ @e ] ]
 |  | n += 1
 |  \_
 | RET [ n ]
 \_

; the entry `e` of the folder `dir`; a link is taken for what it points at
FileRecord record_of: [ @CONST C1 dir | @DirEntry e ]
 | FileRecord r
 | r.name = (String.of)[ e.name AS @CONST C1 ]
 | r.hidden = e.name{0} == '.'
 | r.dir = e.kind == FS_DIR
 | r.count = -1
 |
 | C1 path{4096}
 | BufferSink b = (BufferSink.over)[ path | 4096 ]
 | (b.print)[ "%s/%s" | dir | e.name AS @CONST C1 ]
 | Result<FileInfo | IoError> fi = (fs_info)[ path AS @CONST C1 ]
 | IF [ (fi.is_err)[] ]
 |  | r.broken = e.kind == FS_LINK
 |  | RET [ r ]
 |  \_
 |
 | FileInfo info = (fi.unwrap)[]
 | r.dir = info.kind == FS_DIR
 | r.exec = info.kind == FS_FILE && (info.mode & 0x49) != 0
 | r.size = info.size
 | r.modified = info.modified
 | IF [ r.dir ]
 |  | r.count = (count_entries)[ path AS @CONST C1 ]
 |  \_
 | RET [ r ]
 \_

; folders first, then by name
B1 record_before: [ @CONST FileRecord a | @CONST FileRecord b ]
 | IF [ a.dir != b.dir ]
 |  | RET [ a.dir ]
 |  \_
 | RET [ (str_cmp)[ (a.name.cstr)[] | (b.name.cstr)[] ] < 0 ]
 \_

; the folder `path` into `out`, which is cleared, folders first. Hidden
; entries are left out, unless `hidden` or one is named `keep`. FALSE: the
; folder cannot be read
B1 read_folder: [ @Vector<FileRecord> out | @CONST C1 path | B1 hidden | @CONST C1 keep ]
 | (records_clear)[ out ]
 | Result<os:Dir | IoError> d = (os:Dir.open)[ path ]
 | IF [ (d.is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | os:Dir dir = (d.unwrap)[]
 | POSTLUDE (dir.close)[]
 |
 | DirEntry e
 | WHILE [ (dir.next)[ @e ] ]
 |  | @CONST C1 name = e.name AS @CONST C1
 |  | IF [ hidden || name{0} != '.' || (str_eq)[ name | keep ] ]
 |  |  | (out.push)[ (record_of)[ path | @e ] ]
 |  |  \_
 |  \_
 | (sort_by<FileRecord>)[ out.data | (out.size)[] | record_before ]
 | RET [ TRUE ]
 \_

; --- keys -----------------------------------------------------------------------

; what a column with the focus was asked to do with its cursor's folder
CONST I32 GO_NONE = 0
CONST I32 GO_IN = 1         ; l, →, Enter: into the folder
CONST I32 GO_UP = 2         ; h, ←, Backspace: up a folder

; j and k move the cursor, as the arrows do in the list itself
ABYSS move_keys: [ @Ui ui | @I32 cursor ]
 | IF [ (ui.take)[ 'j' AS U32 ] ]
 |  | ?cursor += 1
 | ELIF [ (ui.take)[ 'k' AS U32 ] ]
 |  | ?cursor -= 1
 |  \_
 \_

I32 go_keys: [ @Ui ui ]
 | IF [ (ui.take)[ 'l' AS U32 ] || (ui.take)[ KEY_RIGHT ] || (ui.take)[ KEY_ENTER ] ]
 |  | RET [ GO_IN ]
 |  \_
 | IF [ (ui.take)[ 'h' AS U32 ] || (ui.take)[ KEY_LEFT ] || (ui.take)[ KEY_BACKSPACE ] ]
 |  | RET [ GO_UP ]
 |  \_
 | RET [ GO_NONE ]
 \_

; the folder a column asks to go to, in `go`: for GO_UP the one around
; `cwd`, the current folder; for GO_IN `e` of `dir`, the folder the column
; lists, if it is a folder that can be read. `e` is NULL in an empty folder
ABYSS ask_go: [ @String go | I32 how | @CONST C1 cwd | @CONST C1 dir | @CONST FileRecord e ]
 | IF [ how == GO_UP ]
 |  | (go.deinit)[]
 |  | ?go = (get_parent_path)[ cwd ]
 | ELIF [ how == GO_IN && e != NULL && e.dir && !(e.broken) && e.count >= 0 ]
 |  | C1 path{4096}
 |  | BufferSink b = (BufferSink.over)[ path | 4096 ]
 |  | (b.print)[ SELECT [ (str_eq)[ dir | "/" ] | "%s%s" | "%s/%s" ] | dir | (e.name.cstr)[] ]
 |  | (go.deinit)[]
 |  | ?go = (String.of)[ path AS @CONST C1 ]
 |  \_
 \_

; --- pieces of a row ------------------------------------------------------------

; a name's colour: red for a broken link, else as on the cursor, hidden,
; a folder, a program, a file
Color record_color: [ @CONST FileRecord e | B1 lit ]
 | IF [ e.broken ]
 |  | RET [ C_BROKEN ]
 |  \_
 | IF [ lit ]
 |  | RET [ TEXT ]
 |  \_
 | IF [ e.hidden ]
 |  | RET [ C_HIDDEN ]
 |  \_
 | IF [ e.exec ]
 |  | RET [ C_EXEC ]
 |  \_
 | RET [ SELECT [ e.dir | C_DIR | TEXT ] ]
 \_

; ✗ a broken link, ▸ a folder, room for one for a file
ABYSS draw_icon: [ @Ui ui | @CONST FileRecord e ]
 | IF [ e.broken ]
 |  | (ui.put)[ (fg)[ C_BROKEN ] | "✗ " ]
 | ELIF [ e.dir ]
 |  | (ui.put)[ (fg)[ C_DIR ] | "▸ " ]
 | ELSE
 |  | (ui.put)[ (fg)[ TEXT ] | "  " ]
 |  \_
 \_

; what the narrow column beside a name says: a folder's count, a file's
; size; nothing for a broken link or a folder that cannot be read
ABYSS side_text: [ @C1 out | @CONST FileRecord e ]
 | out{0} = '\0'
 | IF [ e.broken ]
 |  | RET []
 |  \_
 | IF [ !(e.dir) ]
 |  | (size_text)[ out | e.size ]
 | ELIF [ e.count >= 0 ]
 |  | BufferSink b = (BufferSink.over)[ out | 16 ]
 |  | (b.print)[ "%d" | e.count ]
 |  \_
 \_

; what a list of `width` cells leaves a name: its icon, side and bar taken
I32 name_width: [ I32 width ]
 | I32 w = width - ICON_W - SIDE_W - BAR_W
 | RET [ SELECT [ w < NAME_MIN | NAME_MIN | w ] ]
 \_

; a row as the root column and a folder's preview have it: the icon, the
; name with / for a folder, its count or size. `here`: the folder the main
; column shows, in amber
ABYSS folder_row: [ @Ui ui | @CONST FileRecord e | B1 lit | B1 here | I32 width ]
 | C1 name{260}
 | BufferSink b = (BufferSink.over)[ name | 260 ]
 | (b.print)[ SELECT [ e.dir | "%s/" | "%s" ] | (e.name.cstr)[] ]
 | Color c = (record_color)[ e | lit ]
 | IF [ here && !lit && !(e.broken) ]
 |  | c = AMBER
 |  \_
 |
 | (draw_icon)[ ui | e ]
 | (ui.put_cell)[ (fg)[ c ] | name AS @CONST C1 | width | TRUE ]
 | C1 side{16}
 | (side_text)[ side | e ]
 | (ui.put_cell)[ (fg)[ DIM ] | side AS @CONST C1 | SIDE_W | FALSE ]
 \_

; the last part of `path`; / for the root
String folder_name: [ @CONST C1 path ]
 | String name = (get_dirname)[ path ]
 | IF [ (name.size)[] == 0 ]
 |  | (name.deinit)[]
 |  | name = (String.of)[ "/" ]
 |  \_
 | RET [ name ]
 \_

; the same in capitals, as a column's title
String folder_title: [ @CONST C1 path ]
 | String name = (folder_name)[ path ]
 | (name.upper)[]
 | RET [ name ]
 \_
