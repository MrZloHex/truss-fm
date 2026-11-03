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
!USES <../core/fs.pl>
!USES <look.pl>
!USES <../core/config.pl>
!USES <../core/rules.pl>
!USES <../core/job.pl>
!USES <../core/tasks.pl>

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
 | PV_RUNNING      ; a previewer is at work
 | PV_FILE          ; none fits: what `file` says it is
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
 | B1 want_open             ; ↲ OPEN clicked: the program sees to it
 | B1 want_with             ; o WITH clicked
 |
 | Job job                  ; the previewer the config gave this file, if any
 | B1 job_image             ; image: what it prints is a picture
 | B1 ansi                  ; the text is a previewer's: its colours are kept
 | String via               ; that previewer's program, for the header
 | String desc              ; PV_FILE: file's word for it
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
 | (job_stop)[ @(p.job) ]
 | p.ansi = FALSE
 | (p.via.deinit)[]
 | p.via = (String.of)[ "" ]
 | (p.desc.deinit)[]
 | p.desc = (String.of)[ "" ]
 | p.kind = PV_NONE
 | p.head_len = 0
 | p.lines = 0
 | p.mode = 0
 \_

ABYSS dispose_preview: [ @PreviewPane p ]
 | (preview_forget)[ p ]
 | (p.path.deinit)[]
 | (p.files.deinit)[]
 | (p.job.out.deinit)[]
 | (p.via.deinit)[]
 | (p.desc.deinit)[]
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
 |  |  | (preview_describe)[ p ]
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
CONST USIZE PREVIEW_CMD_TEXT = 262144      ; what is kept of a previewer's text
CONST USIZE PREVIEW_CMD_IMAGE = 33554432   ; and of its picture

; the previewer the config gives the file at `path`, started. FALSE: none
; fits, or it cannot be started
B1 preview_by_rule: [ @PreviewPane p | @CONST C1 path ]
 | @Opener o = (rule_for)[ @(CFG.previewers) | path ]
 | IF [ o == NULL ]
 |  | RET [ FALSE ]
 |  \_
 | p.job_image = o.term
 | IF [ !((job_start)[ @(p.job) | (o.cmd.cstr)[] | path | SELECT [ o.term | PREVIEW_CMD_IMAGE | PREVIEW_CMD_TEXT ] ]) ]
 |  | RET [ FALSE ]
 |  \_
 | ; its program's name, for the header: ${EDITOR:-x} and the like as written
 | C1 word{64}
 | USIZE n = 0
 | @CONST C1 c = (o.cmd.cstr)[]
 | WHILE [ c{n} != '\0' && c{n} != ' ' && n + 1 < 64 ]
 |  | word{n} = c{n}
 |  | n += 1
 |  \_
 | word{n} = '\0'
 | (p.via.deinit)[]
 | p.via = (String.of)[ word AS @CONST C1 ]
 | RET [ TRUE ]
 \_

; where a previewer's picture is put to be read: $XDG_CACHE_HOME/pluf, or
; ~/.cache/pluf, made if need be; `png` its kind
ABYSS preview_cache: [ @C1 out | B1 png ]
 | BufferSink b = (BufferSink.over)[ out | 4096 ]
 | Option<@CONST C1> cache = (env)[ "XDG_CACHE_HOME" ]
 | IF [ (cache.is_some)[] && (cache.unwrap)[]{0} == '/' ]
 |  | (b.print)[ "%s/pluf" | (cache.unwrap)[] ]
 | ELSE
 |  | (b.print)[ "%s/.cache/pluf" | ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 | (fs_make_dirs)[ out AS @CONST C1 ]
 | (b.print)[ "/preview.%s" | SELECT [ png | "png" | "ppm" ] ]
 \_

; the previewer's work taken in: some more of what it printed, and once it
; is done, that shown -- as text with its colours, or as a picture
ABYSS preview_pump: [ @Ui ui | @PreviewPane p ]
 | IF [ p.kind != PV_RUNNING ]
 |  | RET []
 |  \_
 | IF [ !((job_pump)[ @(p.job) ]) ]
 |  | (ui.wake_in)[ 30 ]
 |  | RET []
 |  \_
 | @CONST C1 out = (p.job.out.cstr)[]
 | USIZE n = (p.job.out.size)[]
 | IF [ n == 0 ]
 |  | (preview_describe)[ p ]
 |  | RET []
 |  \_
 | IF [ p.job_image ]
 |  | ; PNG by its mark, else taken for PPM
 |  | B1 png = n > 4 && (out{1} AS U8) == ('P' AS U8) && (out{2} AS U8) == ('N' AS U8) && (out{3} AS U8) == ('G' AS U8)
 |  | C1 file{4096}
 |  | (preview_cache)[ file | png ]
 |  | (fs_remove)[ file AS @CONST C1 ]
 |  | I32 fd = (px_open)[ file AS @CONST C1 | O_MAKE | 0x180 ]
 |  | IF [ fd >= 0 ]
 |  |  | (px_write)[ fd | out AS @CONST ABYSS | n ]
 |  |  | (px_close)[ fd ]
 |  |  | p.has_img = (image_load)[ @(p.img) | file AS @CONST C1 ]
 |  |  \_
 |  | IF [ p.has_img ]
 |  |  | p.kind = PV_IMAGE
 |  | ELSE
 |  |  | (preview_describe)[ p ]
 |  |  \_
 |  | (ui.redo)[]
 |  | RET []
 |  \_
 | USIZE keep = SELECT [ n < PREVIEW_HEAD | n | PREVIEW_HEAD ]
 | FOR [ USIZE i = 0 | i < keep | i += 1 ]
 |  | p.head{i} = out{i}
 |  \_
 | p.head_len = keep
 | C1 last = '\n'
 | I64 lines = (count_lines)[ out | n | @last ]
 | p.lines = SELECT [ last == '\n' | lines | lines + 1 ]
 | p.ansi = TRUE
 | p.kind = PV_TEXT
 | (ui.redo)[]
 \_

; no previewer, or none that worked: what `file` says the file is
ABYSS preview_describe: [ @PreviewPane p ]
 | @CONST C1 argv{} = [ "file" | "-b" | "--" | (p.path.cstr)[] | NULL ]
 | String said = (String.of)[ "" ]
 | (process_output<System>)[ argv | @said ]
 | ; one line, no end
 | USIZE n = 0
 | @CONST C1 s = (said.cstr)[]
 | WHILE [ s{n} != '\0' && s{n} != '\n' ]
 |  | n += 1
 |  \_
 | (said.truncate)[ n ]
 | (p.desc.deinit)[]
 | p.desc = said
 | p.kind = PV_FILE
 \_

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
 |  | p.kind = SELECT [ (read_folder)[ @(p.files) | path AS @CONST C1 | CFG.hidden | "" ] | PV_DIR | PV_UNREADABLE ]
 | ELIF [ (preview_by_rule)[ p | path AS @CONST C1 ] ]
 |  | p.kind = PV_RUNNING
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
 | IF [ p.kind == PV_TEXT && p.ansi ]
 |  | (b.print)[ "%s · by %s" | size AS @CONST C1 | (p.via.cstr)[] ]
 | ELIF [ p.kind == PV_IMAGE && (p.via.size)[] > 0 ]
 |  | (b.print)[ "%s · %d×%d · by %s" | size AS @CONST C1 | p.img.w | p.img.h | (p.via.cstr)[] ]
 | ELIF [ p.kind == PV_TEXT && p.lines >= 0 ]
 |  | (b.print)[ "text · %s · %s %s" | size AS @CONST C1 | count AS @CONST C1 | SELECT [ p.lines == 1 | "line" | "lines" ] ]
 | ELIF [ p.kind == PV_TEXT ]
 |  | (b.print)[ "text · %s" | size AS @CONST C1 ]
 | ELIF [ p.kind == PV_IMAGE ]
 |  | (b.print)[ "image · %s · %d×%d" | size AS @CONST C1 | p.img.w | p.img.h ]
 | ELIF [ p.kind == PV_DIR ]
 |  | (b.print)[ "folder · %d %s" | entries AS I32 | SELECT [ entries == 1 | "entry" | "entries" ] ]
 | ELIF [ p.kind == PV_BROKEN ]
 |  | (b.print)[ "link" ]
 | ELIF [ p.kind == PV_RUNNING ]
 |  | (b.print)[ "%s · %s …" | size AS @CONST C1 | (p.via.cstr)[] ]
 | ELIF [ p.kind == PV_FILE ]
 |  | (b.print)[ "%s" | size AS @CONST C1 ]
 | ELSE
 |  | (b.print)[ "binary · %s" | size AS @CONST C1 ]
 |  \_
 | (ui.text)[ GROW | 1 ]
 | (ui.put_cell)[ (fg)[ DIM ] | line AS @CONST C1 | width | TRUE ]
 \_

; a text's lines from the top, as many as `rows`, cut to `width`. Comments
; dim; the first other line of a table, its header, amber; in Markdown its
; headings amber
; --- a previewer's colours --------------------------------------------------------

; the 16 colours of a terminal, as near the palette as they go: black,
; red, green, yellow, blue, magenta, cyan, white, then their bright ones
Color ansi16: [ I32 k ]
 | IF [ k == 0 ]
 |  | RET [ LINE ]
 |  \_
 | IF [ k == 1 || k == 9 ]
 |  | RET [ RED ]
 |  \_
 | IF [ k == 2 || k == 10 ]
 |  | RET [ SAGE ]
 |  \_
 | IF [ k == 3 || k == 11 ]
 |  | RET [ AMBER ]
 |  \_
 | IF [ k == 4 || k == 12 ]
 |  | RET [ STEEL ]
 |  \_
 | IF [ k == 5 || k == 13 ]
 |  | RET [ 0xFFD787AF AS Color ]
 |  \_
 | IF [ k == 6 || k == 14 ]
 |  | RET [ 0xFF87D7D7 AS Color ]
 |  \_
 | IF [ k == 8 ]
 |  | RET [ DIM ]
 |  \_
 | RET [ TEXT ]
 \_

; xterm's 256: the 16, a 6×6×6 cube, 24 greys
Color ansi256: [ I32 n ]
 | IF [ n < 16 ]
 |  | RET [ (ansi16)[ n ] ]
 |  \_
 | IF [ n >= 232 ]
 |  | U32 g = (8 + 10 * (n - 232)) AS U32
 |  | RET [ (0xFF000000 | (g << 16) | (g << 8) | g) AS Color ]
 |  \_
 | I32 c = n - 16
 | U32 lv{6} = [ 0 | 95 | 135 | 175 | 215 | 255 ]
 | RET [ (0xFF000000 | (lv{c / 36} << 16) | (lv{(c / 6) % 6} << 8) | lv{c % 6}) AS Color ]
 \_

; a line as a terminal would colour it: its ESC [ ... m set the colour of
; what follows -- 30-37, 90-97, 38;5;n, 38;2;r;g;b, 39 and 0 back -- any
; other sequence left out; no more than `width` cells
ABYSS ansi_line: [ @Ui ui | @CONST C1 s | I32 width ]
 | Color c = TEXT
 | C1 run{PREVIEW_LINE}
 | USIZE n = 0
 | I32 cells = 0
 | USIZE i = 0
 | WHILE [ s{i} != '\0' && cells < width ]
 |  | IF [ (s{i} AS U8) == 0x1B AS U8 && s{i + 1} == '[' ]
 |  |  | ; what came before, in the colour it had
 |  |  | run{n} = '\0'
 |  |  | IF [ n > 0 ]
 |  |  |  | (ui.put)[ (fg)[ c ] | run AS @CONST C1 ]
 |  |  |  \_
 |  |  | n = 0
 |  |  | ; the numbers, to the letter that ends it
 |  |  | I32 nums{16}
 |  |  | I32 k = 0
 |  |  | I32 v = 0
 |  |  | USIZE j = i + 2
 |  |  | WHILE [ s{j} != '\0' && ((s{j} >= '0' && s{j} <= '9') || s{j} == ';') ]
 |  |  |  | IF [ s{j} == ';' ]
 |  |  |  |  | IF [ k < 16 ]
 |  |  |  |  |  | nums{k} = v
 |  |  |  |  |  | k += 1
 |  |  |  |  |  \_
 |  |  |  |  | v = 0
 |  |  |  | ELSE
 |  |  |  |  | v = v * 10 + ((s{j} - '0') AS I32)
 |  |  |  |  \_
 |  |  |  | j += 1
 |  |  |  \_
 |  |  | IF [ k < 16 ]
 |  |  |  | nums{k} = v
 |  |  |  | k += 1
 |  |  |  \_
 |  |  | IF [ s{j} == 'm' ]
 |  |  |  | I32 q = 0
 |  |  |  | WHILE [ q < k ]
 |  |  |  |  | I32 x = nums{q}
 |  |  |  |  | IF [ x == 0 || x == 39 ]
 |  |  |  |  |  | c = TEXT
 |  |  |  |  | ELIF [ x >= 30 && x <= 37 ]
 |  |  |  |  |  | c = (ansi16)[ x - 30 ]
 |  |  |  |  | ELIF [ x >= 90 && x <= 97 ]
 |  |  |  |  |  | c = (ansi16)[ x - 90 + 8 ]
 |  |  |  |  | ELIF [ x == 38 && q + 2 < k && nums{q + 1} == 5 ]
 |  |  |  |  |  | c = (ansi256)[ nums{q + 2} ]
 |  |  |  |  |  | q += 2
 |  |  |  |  | ELIF [ x == 38 && q + 4 < k && nums{q + 1} == 2 ]
 |  |  |  |  |  | c = (0xFF000000 | ((nums{q + 2} AS U32) << 16) | ((nums{q + 3} AS U32) << 8) | (nums{q + 4} AS U32)) AS Color
 |  |  |  |  |  | q += 4
 |  |  |  |  | ELIF [ x == 48 && q + 1 < k ]
 |  |  |  |  |  | ; a background: not kept, its numbers stepped over
 |  |  |  |  |  | q += SELECT [ nums{q + 1} == 5 | 2 | SELECT [ nums{q + 1} == 2 | 4 | 0 ] ]
 |  |  |  |  |  \_
 |  |  |  |  | q += 1
 |  |  |  |  \_
 |  |  |  \_
 |  |  | i = SELECT [ s{j} == '\0' | j | j + 1 ]
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ ((s{i} AS U8) & 0xC0) != 0x80 ]
 |  |  | cells += 1
 |  |  \_
 |  | IF [ n + 1 < PREVIEW_LINE ]
 |  |  | run{n} = s{i}
 |  |  | n += 1
 |  |  \_
 |  | i += 1
 |  \_
 | ; a character cut at `width` mid-way: its continuation bytes too
 | WHILE [ s{i} != '\0' && ((s{i} AS U8) & 0xC0) == 0x80 && n + 1 < PREVIEW_LINE ]
 |  | run{n} = s{i}
 |  | n += 1
 |  | i += 1
 |  \_
 | run{n} = '\0'
 | IF [ n > 0 ]
 |  | (ui.put)[ (fg)[ c ] | run AS @CONST C1 ]
 |  \_
 \_

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
 |  | IF [ p.ansi ]
 |  |  | (ansi_line)[ ui | line AS @CONST C1 | width ]
 |  | ELSE
 |  |  | (ui.put_cell)[ (fg)[ c ] | line AS @CONST C1 | width | TRUE ]
 |  |  \_
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
 | DateTime d = (local_date)[ p.entry.modified ]
 | (preview_label)[ ui | "modified" ]
 | ((ui.pen)[ (fg)[ TEXT ] ].print)[ "%02d %s %d %02d:%02d" | d.day AS I32 | MONTHS{(d.month AS I32) - 1} | d.year AS I32 | d.hour AS I32 | d.minute AS I32 ]
 |
 | C1 perm{12}
 | (mode_text)[ perm | p.mode | p.entry.dir | p.entry.broken ]
 | (preview_label)[ ui | "perm" ]
 | (ui.put)[ (fg)[ TEXT ] | perm AS @CONST C1 ]
 \_

; ↲ OPEN and o WITH, as Enter and o: a click says so in `want_open`,
; `want_with` -- a folder has none, Enter goes into it
ABYSS preview_actions: [ @Ui ui | @PreviewPane p ]
 | IF [ p.kind == PV_DIR ]
 |  | RET []
 |  \_
 | (ui.row)[ GROW | 1 ]
 | U32 open = (ui.id)[ "preview-open" ]
 | @Node a = (ui.text)[ FIT | 1 ]
 | (a.with_id)[ open ]
 | (ui.cursor_on)[ open | CUR_HAND ]
 | (ui.put)[ (button_style)[ TRUE ] | " ↲ OPEN " ]
 | (ui.space)[ 1 | 1 ]
 | U32 with = (ui.id)[ "preview-with" ]
 | @Node w = (ui.text)[ FIT | 1 ]
 | (w.with_id)[ with ]
 | (ui.cursor_on)[ with | CUR_HAND ]
 | (ui.put)[ (button_style)[ FALSE ] | " o WITH " ]
 | (ui.close)[]
 | p.want_open = (ui.clicked)[ open ]
 | p.want_with = (ui.clicked)[ with ]
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
 | ELIF [ p.kind == PV_RUNNING ]
 |  | (preview_note)[ ui | DIM | "…" ]
 | ELIF [ p.kind == PV_FILE ]
 |  | ; file's words, wrapped to the column
 |  | (ui.paragraph)[ (p.desc.cstr)[] ]
 | ELIF [ p.kind == PV_BROKEN ]
 |  | (preview_note)[ ui | C_BROKEN | "✗ points to nothing" ]
 | ELIF [ p.kind == PV_UNREADABLE ]
 |  | (preview_note)[ ui | C_BROKEN | "cannot be read" ]
 |  \_
 \_

ABYSS preview_pane: [ @Ui ui | @PreviewPane p | @MainPane m ]
 | (update_preview)[ p | m ]
 | (preview_pump)[ ui | p ]
 | U32 id = (ui.id)[ "preview" ]
 | ; the body's size is known from the last frame
 | Rect r = (ui.rect_of)[ id ]
 | I32 width = SELECT [ r.w > 1 | r.w | 1 ]
 | B1 shown = p.kind != PV_NONE
 |
 | (ui.box)[ "" | (pct)[ CFG.preview_width ] | GROW ]
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
 |  | (preview_actions)[ ui | p ]
 |  \_
 | (ui.close)[]
 \_
