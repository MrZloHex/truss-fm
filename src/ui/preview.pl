; preview.pl -- the last column: what is under the main column's cursor. Text:
; its first lines, coloured by core/syntax.pl where it knows the language, else
; a table's header in amber. Pictures: as the backend draws
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
!USES <../core/sys.pl>
!USES <../core/text.pl>
!USES <../core/syntax.pl>
!USES <look.pl>
!USES <../core/config.pl>
!USES <../core/rules.pl>
!USES <../core/job.pl>
!USES <../core/tasks.pl>

CONST USIZE PREVIEW_HEAD = 32768        ; what is kept of a text
CONST U64 PREVIEW_COUNT = 16777216      ; past this its lines are not counted
CONST U64 PREVIEW_IMAGE = 33554432      ; past this a picture is not opened
CONST U64 PREVIEW_SMALL = 262144        ; up to this it is read here, past it by ImageMagick
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
 | PV_DOWN          ; on a mount over the network that does not answer
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
 | B1 props                 ; i : the file's facts in place of its preview
 | B1 diff                  ; = : what git says changed in the file, in its place
 |
 | Job job                  ; the previewer the config gave this file, if any
 | B1 job_image             ; image: what it prints is a picture
 | B1 ansi                  ; the text is a previewer's: its colours are kept
 | B1 has_lang              ; the text is highlighted here, by `lang`
 | Lang lang
 | String via               ; that previewer's program, for the header
 | String desc              ; PV_FILE: file's word for it
 \_

; --- reading --------------------------------------------------------------------

; what is kept of the last file, so the next can be read
ABYSS preview_forget: [ @PreviewPane p ]
 | (p.entry.name.deinit)[]
 | (p.entry.origin.deinit)[]
 | (records_clear)[ @(p.files) ]
 | IF [ p.has_img ]
 |  | (image_free)[ @(p.img) ]
 |  | p.has_img = FALSE
 |  \_
 | (job_stop)[ @(p.job) ]
 | p.ansi = FALSE
 | p.has_lang = FALSE
 | (p.via.deinit)[]
 | p.via = (String.of)[ "" ]
 | (p.desc.deinit)[]
 | p.desc = (String.of)[ "" ]
 | p.kind = PV_NONE
 | p.head_len = 0
 | p.lines = 0
 | p.mode = 0
 \_

; the file under the cursor read again, as it is when the cursor comes to it
ABYSS preview_redo: [ @PreviewPane p ]
 | (p.path.deinit)[]
 | p.path = (String.of)[ "" ]
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

; the head of a text, and how many lines it has; a head that does not look
; like text makes it a binary
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
 | IF [ (looks_binary)[ p.head AS @CONST C1 | p.head_len ] ]
 |  | (preview_describe)[ p ]
 |  | RET []
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

; what git says changed in the file `name` of the folder `dir`: its diff
; against HEAD, or the staged and the unstaged one when there is no commit; a
; file git does not know is shown whole, as new. The file is "$1"
CONST @CONST C1 DIFF_SCRIPT = "git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'not in a git work tree'; exit 0; }\nf=$1\nif ! git ls-files --error-unmatch -- \"$f\" >/dev/null 2>&1; then\n  [ -d \"$f\" ] && exit 0\n  git check-ignore -q -- \"$f\" && exit 0\n  git --no-pager diff --no-index --color=always -- /dev/null \"$f\"\nelif git rev-parse -q --verify HEAD >/dev/null 2>&1; then\n  git --no-pager diff --color=always HEAD -- \"$f\"\nelse\n  git --no-pager diff --color=always --cached -- \"$f\"\n  git --no-pager diff --color=always -- \"$f\"\nfi"

; the diff of `name` in `dir`, started. FALSE: it cannot be started
B1 preview_by_diff: [ @PreviewPane p | @CONST C1 dir | @CONST C1 name ]
 | p.job_image = FALSE
 | IF [ !((job_start_in)[ @(p.job) | DIFF_SCRIPT | dir | name | PREVIEW_CMD_TEXT ]) ]
 |  | RET [ FALSE ]
 |  \_
 | (p.via.deinit)[]
 | p.via = (String.of)[ "git diff" ]
 | RET [ TRUE ]
 \_

; the file at `path` is one the highlighter knows: by its name, or by the
; #! of a file with no extension. Then `lang` is its language, and no
; preview. rule is looked at
B1 preview_own: [ @PreviewPane p | @CONST C1 path ]
 | p.has_lang = FALSE
 | IF [ !(CFG.highlight) ]
 |  | RET [ FALSE ]
 |  \_
 | @CONST C1 name = (p.entry.name.cstr)[]
 | IF [ (syntax_by_name)[ @(p.lang) | name ] ]
 |  | p.has_lang = TRUE
 |  | RET [ TRUE ]
 |  \_
 | IF [ !((syntax_dotless)[ name ]) ]
 |  | RET [ FALSE ]
 |  \_
 | ; the first line of a file with no extension
 | Result<File | IoError> r = (File.open)[ path | FILE_READ ]
 | IF [ (r.is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | File f = (r.unwrap)[]
 | POSTLUDE (f.close)[]
 | C1 first{128}
 | Result<USIZE | IoError> got = (f.read)[ first AS @U8 | 127 ]
 | IF [ (got.is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | first{(got.unwrap)[]} = '\0'
 | FOR [ I32 i = 0 | first{i} != '\0' | i += 1 ]
 |  | IF [ first{i} == '\n' ]
 |  |  | first{i} = '\0'
 |  |  | BREAK
 |  |  \_
 |  \_
 | p.has_lang = (syntax_by_shebang)[ @(p.lang) | first AS @CONST C1 ]
 | RET [ p.has_lang ]
 \_

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

; a picture with no rule, made small by ImageMagick beside the frames: read
; here, a 12-megapixel PNG holds the screen for seconds. -1 not looked for
; yet, 0 not there, 1 there
CONST @CONST C1 PREVIEW_MAGICK = "magick %f[0] -resize '800x800>' -depth 8 ppm:-"
I32 magick_there = -1

B1 preview_by_magick: [ @PreviewPane p | @CONST C1 path ]
 | IF [ magick_there < 0 ]
 |  | magick_there = SELECT [ (program_there)[ PREVIEW_MAGICK ] | 1 | 0 ]
 |  \_
 | IF [ magick_there == 0 ]
 |  | RET [ FALSE ]
 |  \_
 | IF [ !((job_start)[ @(p.job) | PREVIEW_MAGICK | path | PREVIEW_CMD_IMAGE ]) ]
 |  | RET [ FALSE ]
 |  \_
 | p.job_image = TRUE
 | (p.via.deinit)[]
 | p.via = (String.of)[ "magick" ]
 | RET [ TRUE ]
 \_

; where a previewer's picture is put to be read: $XDG_CACHE_HOME/trufm, or
; ~/.cache/trufm, made if need be; `png` its kind
ABYSS preview_cache: [ @C1 out | B1 png ]
 | BufferSink b = (BufferSink.over)[ out | 4096 ]
 | Option<@CONST C1> cache = (env)[ "XDG_CACHE_HOME" ]
 | IF [ (cache.is_some)[] && (cache.unwrap)[]{0} == '/' ]
 |  | (b.print)[ "%s/trufm" | (cache.unwrap)[] ]
 | ELSE
 |  | (b.print)[ "%s/.cache/trufm" | ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 | (fs_make_dirs)[ out AS @CONST C1 ]
 | (b.print)[ "/preview.%s" | SELECT [ png | "png" | "ppm" ] ]
 \_

; ImageMagick gave no picture (not there, a format it lacks, a failure): the
; file read here, if it is not too big for that; else what `file` says
ABYSS preview_in_place: [ @Ui ui | @PreviewPane p ]
 | IF [ p.entry.size <= PREVIEW_IMAGE ]
 |  | p.has_img = (image_load)[ @(p.img) | (p.path.cstr)[] ]
 |  \_
 | IF [ p.has_img ]
 |  | p.kind = PV_IMAGE
 | ELSE
 |  | (preview_describe)[ p ]
 |  \_
 | (ui.redo)[]
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
 | B1 magick = p.job_image && (p.via.equals)[ "magick" ]
 | IF [ magick && (n == 0 || !(p.job.ok)) ]
 |  | (preview_in_place)[ ui | p ]
 |  | RET []
 |  \_
 | IF [ n == 0 && p.diff ]
 |  | (p.desc.deinit)[]
 |  | p.desc = (String.of)[ "no changes" ]
 |  | p.kind = PV_FILE
 |  | (ui.redo)[]
 |  | RET []
 |  \_
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
 |  | ELIF [ magick ]
 |  |  | (preview_in_place)[ ui | p ]
 |  |  | RET []
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

; a pipe, a socket or a device (what a link points at): not to be opened
B1 preview_special: [ @CONST C1 path ]
 | Result<FileInfo | IoError> fi = (fs_info)[ path ]
 | RET [ (fi.is_ok)[] && (fi.unwrap)[].kind == FS_OTHER ]
 \_

ABYSS update_preview: [ @PreviewPane p | @MainPane m ]
 | I32 at = m.table.list.cursor
 | B1 some = at >= 0 && (at AS USIZE) < (m.files.size)[]
 | C1 path{4096}
 | path{0} = '\0'
 | IF [ some ]
 |  | (join_into)[ path | 4096 | (m.cwd.cstr)[] | ((m.files.at)[ at AS USIZE ].name.cstr)[] ]
 |  \_
 | ; a mount that was not answering is looked at again, as it comes back
 | IF [ (p.path.equals)[ path AS @CONST C1 ] && (p.kind != PV_DOWN || !((remote_ok_deep)[ path AS @CONST C1 ])) ]
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
 | p.entry.origin = (String.of)[ (p.entry.origin.cstr)[] ]
 | ; a mount over the network that does not answer: nothing is called on it
 | IF [ !((remote_ok)[ path AS @CONST C1 ]) ]
 |  | p.kind = PV_DOWN
 |  | RET []
 |  \_
 | Result<FileInfo | IoError> fi = (fs_link_info)[ path AS @CONST C1 ]
 | IF [ (fi.is_ok)[] ]
 |  | ; the link's own: a broken one has no other
 |  | p.mode = (fi.unwrap)[].mode
 |  | p.entry.modified = SELECT [ p.entry.broken | (fi.unwrap)[].modified | p.entry.modified ]
 |  \_
 | ; a link into a mount that does not answer: not followed
 | IF [ (fi.is_ok)[] && (fi.unwrap)[].kind == FS_LINK && !((remote_ok_deep)[ path AS @CONST C1 ]) ]
 |  | p.kind = PV_DOWN
 |  | RET []
 |  \_
 |
 | IF [ p.entry.broken ]
 |  | p.kind = PV_BROKEN
 | ELIF [ (preview_special)[ path AS @CONST C1 ] ]
 |  | ; a pipe, a socket, a device: never opened, a read could wait for ever
 |  | (preview_describe)[ p ]
 | ELIF [ p.diff && (preview_by_diff)[ p | (m.cwd.cstr)[] | (p.entry.name.cstr)[] ] ]
 |  | p.kind = PV_RUNNING
 | ELIF [ p.entry.dir ]
 |  | p.kind = SELECT [ (read_folder)[ @(p.files) | path AS @CONST C1 | CFG.hidden | "" ] | PV_DIR | PV_UNREADABLE ]
 | ELIF [ !((preview_own)[ p | path AS @CONST C1 ]) && (preview_by_rule)[ p | path AS @CONST C1 ] ]
 |  | p.kind = PV_RUNNING
 | ELIF [ (preview_is_image)[ (p.entry.name.cstr)[] ] && p.entry.size <= PREVIEW_SMALL ]
 |  | p.has_img = (image_load)[ @(p.img) | path AS @CONST C1 ]
 |  | p.kind = SELECT [ p.has_img | PV_IMAGE | PV_BINARY ]
 | ELIF [ (preview_is_image)[ (p.entry.name.cstr)[] ] && (preview_by_magick)[ p | path AS @CONST C1 ] ]
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
 | ELIF [ p.kind == PV_DOWN ]
 |  | (b.print)[ "remote · not answering" ]
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

; what colour a kind of the highlighter's is
Color syntax_color: [ I32 kind ]
 | SWITCH [ kind ]
 | CASE [ SY_COMMENT ]
 |  | RET [ C_COMMENT ]
 | CASE [ SY_STRING ]
 |  | RET [ C_STRING ]
 | CASE [ SY_NUMBER ]
 |  | RET [ C_NUMBER ]
 | CASE [ SY_KEYWORD ]
 |  | RET [ C_KEYWORD ]
 | CASE [ SY_TYPE ]
 |  | RET [ C_TYPE ]
 | CASE [ SY_PREPROC ]
 |  | RET [ C_PREPROC ]
 | CASE [ SY_GUIDE ]
 |  | RET [ C_GUIDE ]
 | CASE [ SY_HEAD ]
 |  | RET [ C_HEADER ]
 | CASE [ SY_ADD ]
 |  | RET [ C_ADD ]
 | CASE [ SY_DEL ]
 |  | RET [ C_DEL ]
 | ELSE
 |  | RET [ TEXT ]
 |  \_
 \_

; a line as the highlighter cuts it, a run to a colour; no more than `width`
; cells. `?state` is what the line before left open
ABYSS syntax_draw: [ @Ui ui | @Lang l | @CONST C1 s | @I32 state | @SynSpan sp | I32 width ]
 | I32 n = (syntax_line)[ l | s | state | sp | PREVIEW_LINE + 2 ]
 | C1 run{PREVIEW_LINE}
 | I32 cells = 0
 | FOR [ I32 k = 0 | k < n && cells < width | k += 1 ]
 |  | I32 m = 0
 |  | I32 i = sp{k}.at
 |  | I32 stop = sp{k}.at + sp{k}.len
 |  | WHILE [ i < stop && m + 1 < PREVIEW_LINE ]
 |  |  | IF [ ((s{i} AS U8) & 0xC0) != 0x80 ]
 |  |  |  | IF [ cells >= width ]
 |  |  |  |  | BREAK
 |  |  |  |  \_
 |  |  |  | cells += 1
 |  |  |  \_
 |  |  | run{m} = s{i}
 |  |  | m += 1
 |  |  | i += 1
 |  |  \_
 |  | run{m} = '\0'
 |  | IF [ m > 0 ]
 |  |  | (ui.put)[ (fg)[ (syntax_color)[ sp{k}.kind ] ] | run AS @CONST C1 ]
 |  |  \_
 |  \_
 \_

ABYSS preview_text: [ @Ui ui | @PreviewPane p | I32 rows | I32 width ]
 | B1 markdown = (str_ends)[ (p.entry.name.cstr)[] | ".md" ]
 | B1 more = p.lines < 0 || p.lines > (rows AS I64)
 | I32 room = SELECT [ more | rows - 1 | rows ]
 | B1 header_seen = FALSE
 | I32 carried = 0
 | SynSpan spans{514}
 | USIZE at = 0
 | I32 shown = 0
 |
 | WHILE [ at < p.head_len && shown < room ]
 |  | C1 line{PREVIEW_LINE}
 |  | B1 table = (next_line)[ p | @at | line ]
 |  | Color c = TEXT
 |  | IF [ p.has_lang ]
 |  |  | c = TEXT
 |  | ELIF [ line{0} == '#' ]
 |  |  | c = SELECT [ markdown | C_HEADER | DIM ]
 |  | ELIF [ !header_seen && line{0} != '\0' ]
 |  |  | header_seen = TRUE
 |  |  | c = SELECT [ table | C_HEADER | TEXT ]
 |  |  \_
 |  | (ui.text)[ GROW | 1 ]
 |  | IF [ p.ansi ]
 |  |  | (ansi_line)[ ui | line AS @CONST C1 | width ]
 |  | ELIF [ p.has_lang ]
 |  |  | (syntax_draw)[ ui | @(p.lang) | line AS @CONST C1 | @carried | spans | width ]
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

; 04 Nov 2026 13:05:09
ABYSS prop_date: [ @C1 out | USIZE cap | I64 secs ]
 | DateTime d = (local_date)[ secs ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | (b.print)[ "%02d %s %d %02d:%02d:%02d" | d.day AS I32 | MONTHS{(d.month AS I32) - 1} | d.year AS I32 | d.hour AS I32 | d.minute AS I32 | d.second AS I32 ]
 \_

CONST I32 PROP_LINES = 4        ; the most lines a value is given

; the cells in `s`: a UTF-8 continuation byte is none
I32 cells_of: [ @CONST C1 s ]
 | I32 n = 0
 | FOR [ USIZE i = 0 | s{i} != '\0' | i += 1 ]
 |  | IF [ ((s{i} AS U8) & 0xC0) != 0x80 ]
 |  |  | n += 1
 |  |  \_
 |  \_
 | RET [ n ]
 \_

; a label and its value. A value longer than the column goes on under itself,
; in the value's place, PROP_LINES lines at the most, the last cut with …
ABYSS prop_line: [ @Ui ui | @CONST C1 label | @CONST C1 value | I32 width ]
 | I32 room = SELECT [ width > LABEL_W | width - LABEL_W | 1 ]
 | IF [ room > 120 ]
 |  | room = 120
 |  \_
 | USIZE at = 0
 | FOR [ I32 row = 0 | row < PROP_LINES && (value{at} != '\0' || row == 0) | row += 1 ]
 |  | B1 cut = row == PROP_LINES - 1 && (cells_of)[ value + at ] > room
 |  | I32 take = SELECT [ cut | room - 1 | room ]
 |  | C1 piece{512}
 |  | USIZE n = 0
 |  | I32 cells = 0
 |  | WHILE [ value{at} != '\0' ]
 |  |  | B1 head = ((value{at} AS U8) & 0xC0) != 0x80
 |  |  | IF [ head && cells >= take ]
 |  |  |  | BREAK
 |  |  |  \_
 |  |  | IF [ head ]
 |  |  |  | cells += 1
 |  |  |  \_
 |  |  | IF [ n + 1 < 512 ]
 |  |  |  | piece{n} = value{at}
 |  |  |  | n += 1
 |  |  |  \_
 |  |  | at += 1
 |  |  \_
 |  | piece{n} = '\0'
 |  | (preview_label)[ ui | SELECT [ row == 0 | label | "" ] ]
 |  | (ui.put)[ (fg)[ TEXT ] | piece AS @CONST C1 ]
 |  | IF [ cut ]
 |  |  | (ui.put)[ (fg)[ DIM ] | "…" ]
 |  |  \_
 |  \_
 \_

; a trashed file's origin and its date, above the facts
ABYSS preview_trashed: [ @Ui ui | @PreviewPane p | I32 width ]
 | IF [ (p.entry.origin.size)[] > 0 ]
 |  | String short = (get_shorter_path)[ (p.entry.origin.cstr)[] ]
 |  | (prop_line)[ ui | "from" | (short.cstr)[] | width ]
 |  | (short.deinit)[]
 |  \_
 | IF [ p.entry.deleted > 0 ]
 |  | C1 when{40}
 |  | (prop_date)[ when | 40 | p.entry.deleted ]
 |  | (preview_label)[ ui | "deleted" ]
 |  | (ui.put)[ (fg)[ TEXT ] | when AS @CONST C1 ]
 |  \_
 \_

ABYSS preview_meta: [ @Ui ui | @PreviewPane p | I32 width ]
 | (preview_trashed)[ ui | p | width ]
 | DateTime d = (local_date)[ p.entry.modified ]
 | (preview_label)[ ui | "modified" ]
 | ((ui.pen)[ (fg)[ TEXT ] ].print)[ "%02d %s %d %02d:%02d" | d.day AS I32 | MONTHS{(d.month AS I32) - 1} | d.year AS I32 | d.hour AS I32 | d.minute AS I32 ]
 |
 | C1 perm{12}
 | (mode_text)[ perm | p.mode | p.entry.dir | p.entry.broken ]
 | (preview_label)[ ui | "perm" ]
 | (ui.put)[ (fg)[ TEXT ] | perm AS @CONST C1 ]
 \_

; --- the properties sheet -------------------------------------------------------

; 1 234 bytes · 1K
ABYSS bytes_text: [ @C1 out | USIZE cap | U64 n ]
 | C1 digits{32}
 | (group_digits)[ digits | n AS I64 ]
 | C1 human{16}
 | (size_text)[ human | n ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | (b.print)[ "%s bytes · %s" | digits AS @CONST C1 | human AS @CONST C1 ]
 \_

; the rows chosen with V: how many, how big, how many folders. Sizes are
; the entries' own, nothing is walked
ABYSS props_chosen: [ @Ui ui | @MainPane m | I32 lo | I32 hi | I32 width ]
 | U64 total = 0
 | I32 files = 0
 | I32 dirs = 0
 | FOR [ I32 i = lo | i <= hi | i += 1 ]
 |  | @FileRecord e = (record_at)[ @(m.files) | i ]
 |  | IF [ e != NULL ]
 |  |  | IF [ e.dir ]
 |  |  |  | dirs += 1
 |  |  | ELSE
 |  |  |  | files += 1
 |  |  |  | total += e.size
 |  |  |  \_
 |  |  \_
 |  \_
 | C1 v{128}
 | BufferSink b = (BufferSink.over)[ v | 128 ]
 | (b.print)[ "%d" | hi - lo + 1 ]
 | (prop_line)[ ui | "chosen" | v AS @CONST C1 | width ]
 | BufferSink f = (BufferSink.over)[ v | 128 ]
 | (f.print)[ "%d" | files ]
 | (prop_line)[ ui | "files" | v AS @CONST C1 | width ]
 | (bytes_text)[ v | 128 | total ]
 | (prop_line)[ ui | "size" | v AS @CONST C1 | width ]
 | BufferSink d = (BufferSink.over)[ v | 128 ]
 | (d.print)[ "%d" | dirs ]
 | (prop_line)[ ui | "folders" | v AS @CONST C1 | width ]
 \_

; the cursor's file: name, path, type, size, mode, owner, times, inode, links,
; device and mount
ABYSS props_file: [ @Ui ui | @PreviewPane p | I32 width ]
 | Stat st
 | IF [ !((remote_ok)[ (p.path.cstr)[] ]) ]
 |  | (preview_note)[ ui | C_REMOTE_DOWN | "not answering" ]
 |  | RET []
 |  \_
 | IF [ !((px_stat_of)[ (p.path.cstr)[] | @st ]) ]
 |  | (preview_note)[ ui | C_BROKEN | "cannot be read" ]
 |  | RET []
 |  \_
 | U32 kind = st.mode & 0xF000
 | B1 link = kind == 0xA000
 | B1 dir = kind == 0x4000
 | (prop_line)[ ui | "name" | (p.entry.name.cstr)[] | width ]
 | (prop_line)[ ui | "path" | (p.path.cstr)[] | width ]
 | (preview_trashed)[ ui | p | width ]
 |
 | C1 v{1100}
 | @CONST C1 type = "file"
 | IF [ dir ]
 |  | type = "folder"
 | ELIF [ kind == 0x1000 ]
 |  | type = "fifo"
 | ELIF [ kind == 0xC000 ]
 |  | type = "socket"
 | ELIF [ kind == 0x2000 ]
 |  | type = "character device"
 | ELIF [ kind == 0x6000 ]
 |  | type = "block device"
 |  \_
 | IF [ link ]
 |  | C1 target{1024}
 |  | ISIZE n = (px_readlink)[ (p.path.cstr)[] | target | 1023 ]
 |  | target{SELECT [ n > 0 | n AS USIZE | 0 ]} = '\0'
 |  | BufferSink b = (BufferSink.over)[ v | 1100 ]
 |  | (b.print)[ "link → %s%s" | target AS @CONST C1 | SELECT [ p.entry.broken | " (broken)" | "" ] ]
 |  | (prop_line)[ ui | "type" | v AS @CONST C1 | width ]
 | ELSE
 |  | (prop_line)[ ui | "type" | type | width ]
 |  \_
 |
 | IF [ dir ]
 |  | BufferSink b = (BufferSink.over)[ v | 1100 ]
 |  | IF [ p.entry.count >= 0 ]
 |  |  | (b.print)[ "%d entries" | p.entry.count ]
 |  | ELSE
 |  |  | (b.print)[ "cannot be read" ]
 |  |  \_
 |  | (prop_line)[ ui | "size" | v AS @CONST C1 | width ]
 | ELSE
 |  | (bytes_text)[ v | 1100 | st.size ]
 |  | (prop_line)[ ui | "size" | v AS @CONST C1 | width ]
 |  \_
 |
 | C1 perm{12}
 | (mode_text)[ perm | st.mode | dir | link ]
 | perm{0} = SELECT [ kind == 0x1000 | 'p' | SELECT [ kind == 0xC000 | 's' | SELECT [ kind == 0x2000 | 'c' | SELECT [ kind == 0x6000 | 'b' | perm{0} ] ] ] ]
 | BufferSink o = (BufferSink.over)[ v | 1100 ]
 | ; the octal on a line of its own when both do not fit
 | IF [ width - LABEL_W >= 15 ]
 |  | (o.print)[ "%s  %03o" | perm AS @CONST C1 | st.mode & 0xFFF ]
 |  | (prop_line)[ ui | "perm" | v AS @CONST C1 | width ]
 | ELSE
 |  | (prop_line)[ ui | "perm" | perm AS @CONST C1 | width ]
 |  | (o.print)[ "%03o" | st.mode & 0xFFF ]
 |  | (prop_line)[ ui | "octal" | v AS @CONST C1 | width ]
 |  \_
 |
 | C1 who{128}
 | (px_user_name)[ who | 128 | st.uid ]
 | (prop_line)[ ui | "owner" | who AS @CONST C1 | width ]
 | (px_group_name)[ who | 128 | st.gid ]
 | (prop_line)[ ui | "group" | who AS @CONST C1 | width ]
 |
 | (prop_date)[ v | 1100 | st.mtime ]
 | (prop_line)[ ui | "modified" | v AS @CONST C1 | width ]
 | (prop_date)[ v | 1100 | st.atime ]
 | (prop_line)[ ui | "accessed" | v AS @CONST C1 | width ]
 | (prop_date)[ v | 1100 | st.ctime ]
 | (prop_line)[ ui | "changed" | v AS @CONST C1 | width ]
 |
 | BufferSink n = (BufferSink.over)[ v | 1100 ]
 | (n.print)[ "%llu" | st.ino ]
 | (prop_line)[ ui | "inode" | v AS @CONST C1 | width ]
 | BufferSink l = (BufferSink.over)[ v | 1100 ]
 | (l.print)[ "%llu" | st.nlink ]
 | (prop_line)[ ui | "links" | v AS @CONST C1 | width ]
 | BufferSink d = (BufferSink.over)[ v | 1100 ]
 | (d.print)[ "%u:%u" | st.dev_major | st.dev_minor ]
 | (prop_line)[ ui | "device" | v AS @CONST C1 | width ]
 |
 | ; a link lives where its folder does, not where it points
 | String where = SELECT [ link | (get_parent_path)[ (p.path.cstr)[] ] | (String.of)[ (p.path.cstr)[] ] ]
 | IF [ !((mount_point_of)[ (where.cstr)[] | v | 1100 ]) ]
 |  | (str_copy)[ v | 1100 | "?" ]
 |  \_
 | (prop_line)[ ui | "mount" | v AS @CONST C1 | width ]
 | (where.deinit)[]
 \_

; the sheet in the preview's place: a summary while rows are chosen
ABYSS preview_props: [ @Ui ui | @PreviewPane p | @MainPane m | I32 width ]
 | I32 lo = 0
 | I32 hi = 0
 | IF [ (chosen_rows)[ m | @lo | @hi ] ]
 |  | (props_chosen)[ ui | m | lo | hi | width ]
 | ELIF [ p.kind != PV_NONE ]
 |  | (props_file)[ ui | p | width ]
 |  \_
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
 | ELIF [ p.kind == PV_DOWN ]
 |  | (preview_note)[ ui | C_REMOTE_DOWN | "not answering" ]
 |  \_
 \_

ABYSS preview_pane: [ @Ui ui | @PreviewPane p | @MainPane m ]
 | (update_preview)[ p | m ]
 | (preview_pump)[ ui | p ]
 | U32 id = (ui.id)[ "preview" ]
 | ; the body's size is known from the last frame
 | Rect r = (ui.rect_of)[ id ]
 | I32 width = SELECT [ r.w > 1 | r.w | 1 ]
 | B1 shown = p.kind != PV_NONE && !(p.props)
 |
 | (ui.box)[ "" | (pct)[ CFG.preview_width ] | GROW ]
 | IF [ shown ]
 |  | (preview_head)[ ui | p | width ]
 |  | (preview_rule)[ ui | width ]
 |  \_
 |
 | @Node body = (ui.column)[ GROW | GROW ]
 | (body.with_id)[ id ]
 | IF [ p.props ]
 |  | (preview_props)[ ui | p | m | width ]
 | ELSE
 |  | (preview_body)[ ui | p | r | width ]
 |  \_
 | (ui.close)[]
 |
 | IF [ shown ]
 |  | (preview_rule)[ ui | width ]
 |  | (preview_meta)[ ui | p | width ]
 |  | (ui.space)[ 1 | 1 ]
 |  | (preview_actions)[ ui | p ]
 |  \_
 | (ui.close)[]
 \_
