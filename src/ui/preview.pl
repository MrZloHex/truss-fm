; preview.pl -- the last column: what is under the main column's cursor. Text:
; its first lines, a table's header in amber. Pictures: as the backend draws
; them. Folders: their listing. It is read once per file, as the cursor comes
; to it

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

USE <modular.pl>
!USES <common.pl>
!USES <main.pl>
!USES <../fs.pl>
!USES <../look.pl>

CONST I32 PREVIEW_W_PERC = 20
CONST USIZE PREVIEW_HEAD = 32768        ; what is kept of a text
CONST U64 PREVIEW_COUNT = 16777216      ; past this its lines are not counted
CONST U64 PREVIEW_IMAGE = 33554432      ; past this a picture is not opened
CONST I32 PREVIEW_LINE = 512            ; the most of a line that is looked at
CONST I32 LABEL_W = 10                  ; modified, perm

TYPE PreviewKind: ENUM
 | PV_NONE          ; nothing under the cursor
 | PV_TEXT
 | PV_BINARY
 | PV_IMAGE
 | PV_DIR
 | PV_BROKEN
 | PV_UNREADABLE
 \_

TYPE PreviewPane: STRUCT
 | String path              ; what it was read for
 | PreviewKind kind
 | FileRecord entry         ; its own copy: the main column's may be read again
 | U32 mode
 |
 | C1 head{PREVIEW_HEAD}    ; the start of a text
 | USIZE head_len
 | I64 lines                ; a text's lines; -1: too long to count
 |
 | Image img
 | B1 has_img
 |
 | Vector<FileRecord> files ; a folder's listing
 \_

; --- reading --------------------------------------------------------------------

; what is kept of the last file, so the next can be read
ABYSS preview_forget: [ @PreviewPane p ]
 | (p.entry.name.deinit)[]
 | (records_clear)[ @(p.files) ]
 | IF [ p.has_img ]
 |  | (image_free)[ @(p.img) ]
 |  | p.has_img = FALSE
 |  \_
 | p.kind = PV_NONE
 | p.head_len = 0
 | p.lines = 0
 | p.mode = 0
 \_

ABYSS dispose_preview: [ @PreviewPane p ]
 | (preview_forget)[ p ]
 | (p.path.deinit)[]
 | (p.files.deinit)[]
 \_

B1 preview_is_image: [ @CONST C1 name ]
 | RET [ (str_ends)[ name | ".png" ] || (str_ends)[ name | ".qoi" ] || (str_ends)[ name | ".ppm" ] || (str_ends)[ name | ".pgm" ] ]
 \_

; the newlines in `n` bytes of `s`; `last` is left on the last byte
I64 count_lines: [ @CONST C1 s | USIZE n | @C1 last ]
 | I64 lines = 0
 | FOR [ USIZE i = 0 | i < n | i += 1 ]
 |  | lines += SELECT [ s{i} == '\n' | 1 | 0 ]
 |  \_
 | IF [ n > 0 ]
 |  | ?last = s{n - 1}
 |  \_
 | RET [ lines ]
 \_

; the head of a text, and how many lines it has; a NUL in the head makes it
; a binary
ABYSS preview_read_text: [ @PreviewPane p | @CONST C1 path ]
 | Result<File | IoError> r = (File.open)[ path | FILE_READ ]
 | IF [ (r.is_err)[] ]
 |  | p.kind = PV_UNREADABLE
 |  | RET []
 |  \_
 | File f = (r.unwrap)[]
 | POSTLUDE (f.close)[]
 |
 | Result<USIZE | IoError> got = (f.read)[ p.head AS @U8 | PREVIEW_HEAD ]
 | IF [ (got.is_err)[] ]
 |  | p.kind = PV_UNREADABLE
 |  | RET []
 |  \_
 | p.head_len = (got.unwrap)[]
 | FOR [ USIZE i = 0 | i < p.head_len | i += 1 ]
 |  | IF [ p.head{i} == '\0' ]
 |  |  | p.kind = PV_BINARY
 |  |  | RET []
 |  |  \_
 |  \_
 |
 | p.kind = PV_TEXT
 | IF [ p.entry.size > PREVIEW_COUNT ]
 |  | p.lines = -1
 |  | RET []
 |  \_
 | C1 last = '\n'
 | I64 n = (count_lines)[ p.head AS @CONST C1 | p.head_len | @last ]
 | C1 chunk{65536}
 | LOOP
 |  | Result<USIZE | IoError> more = (f.read)[ chunk AS @U8 | 65536 ]
 |  | IF [ (more.is_err)[] || (more.unwrap)[] == 0 ]
 |  |  | BREAK
 |  |  \_
 |  | n += (count_lines)[ chunk AS @CONST C1 | (more.unwrap)[] | @last ]
 |  \_
 | ; a last line with no newline is a line too
 | p.lines = SELECT [ last == '\n' | n | n + 1 ]
 \_

; read again only when the cursor is on another file
ABYSS update_preview: [ @PreviewPane p | @MainPane m ]
 | I32 at = m.table.list.cursor
 | B1 some = at >= 0 && (at AS USIZE) < (m.files.size)[]
 | C1 path{4096}
 | path{0} = '\0'
 | IF [ some ]
 |  | BufferSink b = (BufferSink.over)[ path | 4096 ]
 |  | (b.print)[ "%s/%s" | (m.cwd.cstr)[] | ((m.files.at)[ at AS USIZE ].name.cstr)[] ]
 |  \_
 | IF [ (p.path.equals)[ path AS @CONST C1 ] ]
 |  | RET []
 |  \_
 |
 | (p.path.deinit)[]
 | p.path = (String.of)[ path AS @CONST C1 ]
 | (preview_forget)[ p ]
 | IF [ !some ]
 |  | RET []
 |  \_
 |
 | p.entry = ?((m.files.at)[ at AS USIZE ])
 | p.entry.name = (String.of)[ (p.entry.name.cstr)[] ]
 | Result<FileInfo | IoError> fi = (fs_link_info)[ path AS @CONST C1 ]
 | IF [ (fi.is_ok)[] ]
 |  | ; the link's own: a broken one has no other
 |  | p.mode = (fi.unwrap)[].mode
 |  | p.entry.modified = SELECT [ p.entry.broken | (fi.unwrap)[].modified | p.entry.modified ]
 |  \_
 |
 | IF [ p.entry.broken ]
 |  | p.kind = PV_BROKEN
 | ELIF [ p.entry.dir ]
 |  | p.kind = SELECT [ (read_folder)[ @(p.files) | path AS @CONST C1 | TRUE | "" ] | PV_DIR | PV_UNREADABLE ]
 | ELIF [ (preview_is_image)[ (p.entry.name.cstr)[] ] && p.entry.size <= PREVIEW_IMAGE ]
 |  | p.has_img = (image_load)[ @(p.img) | path AS @CONST C1 ]
 |  | p.kind = SELECT [ p.has_img | PV_IMAGE | PV_BINARY ]
 | ELSE
 |  | (preview_read_text)[ p | path AS @CONST C1 ]
 |  \_
 \_

; --- pieces ---------------------------------------------------------------------

; 41329 as 41 329
ABYSS group_digits: [ @C1 out | I64 n ]
 | C1 raw{32}
 | BufferSink b = (BufferSink.over)[ raw | 32 ]
 | (b.print)[ "%lld" | n ]
 | USIZE len = (str_len)[ raw AS @CONST C1 ]
 | USIZE o = 0
 | FOR [ USIZE i = 0 | i < len | i += 1 ]
 |  | IF [ i > 0 && (len - i) % 3 == 0 ]
 |  |  | out{o} = ' '
 |  |  | o += 1
 |  |  \_
 |  | out{o} = raw{i}
 |  | o += 1
 |  \_
 | out{o} = '\0'
 \_

; -rw-r--r--
ABYSS mode_text: [ @C1 out | U32 mode | B1 dir | B1 link ]
 | out{0} = SELECT [ link | 'l' | SELECT [ dir | 'd' | '-' ] ]
 | FOR [ U32 i = 0 | i < 9 | i += 1 ]
 |  | B1 on = (mode & ((1 AS U32) << (8 - i))) != 0
 |  | C1 c = SELECT [ i % 3 == 0 | 'r' | SELECT [ i % 3 == 1 | 'w' | 'x' ] ]
 |  | out{(i + 1) AS USIZE} = SELECT [ on | c | '-' ]
 |  \_
 | out{10} = '\0'
 \_

; the next line of the head from `?at` into `line`, a tab as a space, and
; `?at` past it. TRUE: it has a comma or a tab, as a table's lines do
B1 next_line: [ @PreviewPane p | @USIZE at | @C1 line ]
 | USIZE i = ?at
 | I32 n = 0
 | B1 table = FALSE
 | WHILE [ i < p.head_len && p.head{i} != '\n' ]
 |  | C1 c = p.head{i}
 |  | table = table || c == ',' || c == '\t'
 |  | IF [ n + 1 < PREVIEW_LINE && c != '\r' ]
 |  |  | line{n} = SELECT [ c == '\t' | ' ' | c ]
 |  |  | n += 1
 |  |  \_
 |  | i += 1
 |  \_
 | line{n} = '\0'
 | ?at = i + 1
 | RET [ table ]
 \_

; --- drawing --------------------------------------------------------------------

ABYSS preview_rule: [ @Ui ui | I32 width ]
 | (ui.text)[ GROW | 1 ]
 | (ui.repeat_s)[ (fg)[ LINE ] | "─" | width ]
 \_

; a line that says what is not shown
ABYSS preview_note: [ @Ui ui | Color c | @CONST C1 s ]
 | (ui.text)[ GROW | 1 ]
 | (ui.put)[ (fg)[ c ] | s ]
 \_

; the name, and under it what it is
ABYSS preview_head: [ @Ui ui | @PreviewPane p | I32 width ]
 | (ui.text)[ GROW | 1 ]
 | (ui.put_cell)[ (fg)[ TEXT ] | (p.entry.name.cstr)[] | width | TRUE ]
 |
 | C1 size{16}
 | (size_text)[ size | p.entry.size ]
 | C1 count{32}
 | (group_digits)[ count | p.lines ]
 | USIZE entries = (p.files.size)[]
 |
 | C1 line{128}
 | BufferSink b = (BufferSink.over)[ line | 128 ]
 | IF [ p.kind == PV_TEXT && p.lines >= 0 ]
 |  | (b.print)[ "text · %s · %s %s" | size AS @CONST C1 | count AS @CONST C1 | SELECT [ p.lines == 1 | "line" | "lines" ] ]
 | ELIF [ p.kind == PV_TEXT ]
 |  | (b.print)[ "text · %s" | size AS @CONST C1 ]
 | ELIF [ p.kind == PV_IMAGE ]
 |  | (b.print)[ "image · %s · %d×%d" | size AS @CONST C1 | p.img.w | p.img.h ]
 | ELIF [ p.kind == PV_DIR ]
 |  | (b.print)[ "folder · %d %s" | entries AS I32 | SELECT [ entries == 1 | "entry" | "entries" ] ]
 | ELIF [ p.kind == PV_BROKEN ]
 |  | (b.print)[ "link" ]
 | ELSE
 |  | (b.print)[ "binary · %s" | size AS @CONST C1 ]
 |  \_
 | (ui.text)[ GROW | 1 ]
 | (ui.put_cell)[ (fg)[ DIM ] | line AS @CONST C1 | width | TRUE ]
 \_

; a text's lines from the top, as many as `rows`, cut to `width`. Comments
; dim; the first other line of a table, its header, amber; in Markdown its
; headings amber
ABYSS preview_text: [ @Ui ui | @PreviewPane p | I32 rows | I32 width ]
 | B1 markdown = (str_ends)[ (p.entry.name.cstr)[] | ".md" ]
 | B1 more = p.lines < 0 || p.lines > (rows AS I64)
 | I32 room = SELECT [ more | rows - 1 | rows ]
 | B1 header_seen = FALSE
 | USIZE at = 0
 | I32 shown = 0
 |
 | WHILE [ at < p.head_len && shown < room ]
 |  | C1 line{PREVIEW_LINE}
 |  | B1 table = (next_line)[ p | @at | line ]
 |  | Color c = TEXT
 |  | IF [ line{0} == '#' ]
 |  |  | c = SELECT [ markdown | C_HEADER | DIM ]
 |  | ELIF [ !header_seen && line{0} != '\0' ]
 |  |  | header_seen = TRUE
 |  |  | c = SELECT [ table | C_HEADER | TEXT ]
 |  |  \_
 |  | (ui.text)[ GROW | 1 ]
 |  | (ui.put_cell)[ (fg)[ c ] | line AS @CONST C1 | width | TRUE ]
 |  | shown += 1
 |  \_
 |
 | IF [ !more || rows <= 0 ]
 |  | RET []
 |  \_
 | IF [ p.lines < 0 ]
 |  | (preview_note)[ ui | DIM | "… too long to count" ]
 |  | RET []
 |  \_
 | C1 left{32}
 | (group_digits)[ left | p.lines - (shown AS I64) ]
 | (ui.text)[ GROW | 1 ]
 | ((ui.pen)[ (fg)[ DIM ] ].print)[ "… %s more lines" | left AS @CONST C1 ]
 \_

; a folder's entries, as the root column draws them
ABYSS preview_dir: [ @Ui ui | @PreviewPane p | I32 rows | I32 width ]
 | I32 n = (p.files.size)[] AS I32
 | IF [ n == 0 ]
 |  | (preview_note)[ ui | DIM | "empty" ]
 |  | RET []
 |  \_
 | I32 name = (name_width)[ width ]
 | I32 room = SELECT [ n > rows | rows - 1 | n ]
 | FOR [ I32 i = 0 | i < room | i += 1 ]
 |  | (ui.text)[ GROW | 1 ]
 |  | (folder_row)[ ui | (p.files.at)[ i AS USIZE ] | FALSE | FALSE | name ]
 |  \_
 | IF [ n > rows && rows > 0 ]
 |  | (ui.text)[ GROW | 1 ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "… %d more" | n - room ]
 |  \_
 \_

ABYSS preview_label: [ @Ui ui | @CONST C1 label ]
 | (ui.text)[ GROW | 1 ]
 | (ui.put_cell)[ (fg)[ DIM ] | label | LABEL_W | TRUE ]
 \_

ABYSS preview_meta: [ @Ui ui | @PreviewPane p ]
 | DateTime d = (date_of_unix)[ p.entry.modified ]
 | (preview_label)[ ui | "modified" ]
 | ((ui.pen)[ (fg)[ TEXT ] ].print)[ "%02d %s %d %02d:%02d" | d.day AS I32 | MONTHS{(d.month AS I32) - 1} | d.year AS I32 | d.hour AS I32 | d.minute AS I32 ]
 |
 | C1 perm{12}
 | (mode_text)[ perm | p.mode | p.entry.dir | p.entry.broken ]
 | (preview_label)[ ui | "perm" ]
 | (ui.put)[ (fg)[ TEXT ] | perm AS @CONST C1 ]
 \_

ABYSS preview_actions: [ @Ui ui ]
 | (ui.text)[ GROW | 1 ]
 | (ui.put)[ (button_style)[ TRUE ] | " ↲ OPEN " ]
 | (ui.put)[ (fg)[ TEXT ] | " " ]
 | (ui.put)[ (button_style)[ FALSE ] | " o WITH " ]
 \_

ABYSS preview_body: [ @Ui ui | @PreviewPane p | Rect r | I32 width ]
 | IF [ p.kind == PV_TEXT ]
 |  | (preview_text)[ ui | p | r.h | width ]
 | ELIF [ p.kind == PV_IMAGE ]
 |  | (ui.image)[ @(p.img) | GROW | GROW ]
 | ELIF [ p.kind == PV_DIR ]
 |  | (preview_dir)[ ui | p | r.h | width ]
 | ELIF [ p.kind == PV_BINARY ]
 |  | (preview_note)[ ui | DIM | "no preview" ]
 | ELIF [ p.kind == PV_BROKEN ]
 |  | (preview_note)[ ui | C_BROKEN | "✗ points to nothing" ]
 | ELIF [ p.kind == PV_UNREADABLE ]
 |  | (preview_note)[ ui | C_BROKEN | "cannot be read" ]
 |  \_
 \_

ABYSS preview_pane: [ @Ui ui | @PreviewPane p | @MainPane m ]
 | (update_preview)[ p | m ]
 | U32 id = (ui.id)[ "preview" ]
 | ; the body's size is known from the last frame
 | Rect r = (ui.rect_of)[ id ]
 | I32 width = SELECT [ r.w > 1 | r.w | 1 ]
 | B1 shown = p.kind != PV_NONE
 |
 | (ui.box)[ "PREVIEW" | (pct)[ PREVIEW_W_PERC ] | GROW ]
 | IF [ shown ]
 |  | (preview_head)[ ui | p | width ]
 |  | (preview_rule)[ ui | width ]
 |  \_
 |
 | @Node body = (ui.column)[ GROW | GROW ]
 | (body.with_id)[ id ]
 | (preview_body)[ ui | p | r | width ]
 | (ui.close)[]
 |
 | IF [ shown ]
 |  | (preview_rule)[ ui | width ]
 |  | (preview_meta)[ ui | p ]
 |  | (ui.space)[ 1 | 1 ]
 |  | (preview_actions)[ ui ]
 |  \_
 | (ui.close)[]
 \_
