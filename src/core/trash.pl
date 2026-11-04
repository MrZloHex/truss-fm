; trash.pl -- the freedesktop trash, as other file managers and trash-cli
; keep it: a file goes to files/ of a trash folder, renamed, and beside it
; in info/ a <name>.trashinfo says where it was and when. On the disk of
; home that folder is ~/.local/share/Trash; on any other, .Trash-<uid> at
; that disk's top -- a file is only ever renamed, never copied across disks.
;
;   [Trash Info]
;   Path=/home/me/notes%20old.txt
;   DeletionDate=2026-11-04T10:12:03

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

!USES <fs.pl>
!USES <tasks.pl>
!USES <sys.pl>

CONST USIZE TRASH_PATH = 4096

U32 px_getuid: []
 + SYMBOL "getuid"


; the home trash: $XDG_DATA_HOME/Trash, or ~/.local/share/Trash
ABYSS trash_home: [ @C1 out | USIZE cap ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | Option<@CONST C1> data = (env)[ "XDG_DATA_HOME" ]
 | IF [ (data.is_some)[] && (data.unwrap)[]{0} == '/' ]
 |  | (b.print)[ "%s/Trash" | (data.unwrap)[] ]
 | ELSE
 |  | (b.print)[ "%s/.local/share/Trash" | ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 \_

LOCAL B1 same_disk: [ @CONST C1 a | @CONST C1 b ]
 | Result<FileInfo | IoError> x = (fs_info)[ a ]
 | Result<FileInfo | IoError> y = (fs_info)[ b ]
 | IF [ (x.is_err)[] || (y.is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | FileInfo p = (x.unwrap)[]
 | FileInfo q = (y.unwrap)[]
 | RET [ p.dev_major == q.dev_major && p.dev_minor == q.dev_minor ]
 \_

; the trash a file at `path` goes to, made if it is not there yet, with
; its files/ and info/: the home one on home's disk, else .Trash-<uid> at
; the top of the file's. FALSE: there is none to be had
B1 trash_for: [ @CONST C1 path | @C1 out | USIZE cap ]
 | C1 home{TRASH_PATH}
 | (trash_home)[ home | TRASH_PATH ]
 | ; the home trash's disk is home's -- the trash itself may not be yet
 | @CONST C1 h = ((env)[ "HOME" ].unwrap_or)[ "/" ]
 | IF [ (same_disk)[ path | h ] ]
 |  | (str_copy)[ out | cap | home AS @CONST C1 ]
 | ELSE
 |  | C1 top{TRASH_PATH}
 |  | IF [ !((mount_point_of)[ path | top | TRASH_PATH ]) ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | BufferSink b = (BufferSink.over)[ out | cap ]
 |  | (b.print)[ "%s/.Trash-%u" | (SELECT [ (str_eq)[ top AS @CONST C1 | "/" ] | "" | top AS @CONST C1 ]) | (px_getuid)[] ]
 |  \_
 | FOR [ I32 k = 0 | k < 2 | k += 1 ]
 |  | C1 sub{TRASH_PATH}
 |  | BufferSink s = (BufferSink.over)[ sub | TRASH_PATH ]
 |  | (s.print)[ "%s/%s" | out AS @CONST C1 | SELECT [ k == 0 | "files" | "info" ] ]
 |  | IF [ ((fs_make_dirs)[ sub AS @CONST C1 ].is_err)[] ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  \_
 | (px_chmod)[ out AS @CONST C1 | 0x1C0 ]
 | RET [ TRUE ]
 \_

; `path` as a trashinfo's Path wants it: every byte but letters, digits,
; - . _ ~ / as %XX
LOCAL ABYSS url_path: [ @BufferSink b | @CONST C1 path ]
 | FOR [ USIZE i = 0 | path{i} != '\0' | i += 1 ]
 |  | C1 c = path{i}
 |  | B1 plain = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' || c == '~' || c == '/'
 |  | IF [ plain ]
 |  |  | (b.putc)[ c ]
 |  | ELSE
 |  |  | (b.print)[ "%%%02X" | (c AS U8) AS U32 ]
 |  |  \_
 |  \_
 \_

; `path` -- full, as realpath has it -- to the trash; in `put` where it
; went, for undo. FALSE, and why in `why`: it is where it was
B1 trash_one: [ @CONST C1 path | @String put | @String why ]
 | C1 bin{TRASH_PATH}
 | IF [ !((trash_for)[ path | bin | TRASH_PATH ]) ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ "no trash on this disk: X deletes for good" ]
 |  | RET [ FALSE ]
 |  \_
 | String name = (get_dirname)[ path ]
 | POSTLUDE (name.deinit)[]
 |
 | ; a name of its own in the trash: its info file made first, O_EXCL,
 | ; holds it -- name, name.2, name.3 ...
 | C1 info{TRASH_PATH}
 | C1 dest{TRASH_PATH}
 | I32 fd = -1
 | FOR [ I32 k = 1 | k < 10000 && fd < 0 | k += 1 ]
 |  | C1 as{512}
 |  | BufferSink a = (BufferSink.over)[ as | 512 ]
 |  | IF [ k == 1 ]
 |  |  | (a.print)[ "%s" | (name.cstr)[] ]
 |  | ELSE
 |  |  | (a.print)[ "%s.%d" | (name.cstr)[] | k ]
 |  |  \_
 |  | BufferSink i = (BufferSink.over)[ info | TRASH_PATH ]
 |  | (i.print)[ "%s/info/%s.trashinfo" | bin AS @CONST C1 | as AS @CONST C1 ]
 |  | BufferSink d = (BufferSink.over)[ dest | TRASH_PATH ]
 |  | (d.print)[ "%s/files/%s" | bin AS @CONST C1 | as AS @CONST C1 ]
 |  | IF [ !((taken)[ dest AS @CONST C1 ]) ]
 |  |  | fd = (px_open)[ info AS @CONST C1 | O_MAKE | 0x180 ]
 |  |  \_
 |  \_
 | IF [ fd < 0 ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ "the trash cannot be written" ]
 |  | RET [ FALSE ]
 |  \_
 |
 | C1 text{12288}
 | BufferSink t = (BufferSink.over)[ text | 12288 ]
 | ; the spec's date is the local one, with no zone
 | I64 secs = (unix_time)[]
 | Tm now
 | (px_localtime_r)[ @secs | @now ]
 | (t.print)[ "[Trash Info]\nPath=" ]
 | (url_path)[ @t | path ]
 | (t.print)[ "\nDeletionDate=%04d-%02d-%02dT%02d:%02d:%02d\n" | now.year + 1900 | now.mon + 1 | now.mday | now.hour | now.min | now.sec ]
 | USIZE n = (str_len)[ text AS @CONST C1 ]
 | ISIZE w = (px_write)[ fd | text AS @CONST ABYSS | n ]
 | (px_close)[ fd ]
 | IF [ w != (n AS ISIZE) ]
 |  | (fs_remove)[ info AS @CONST C1 ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ "the trash cannot be written" ]
 |  | RET [ FALSE ]
 |  \_
 |
 | Result<B1 | IoError> r = (fs_rename)[ path | dest AS @CONST C1 ]
 | IF [ (r.is_err)[] ]
 |  | (fs_remove)[ info AS @CONST C1 ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ (io_error_text)[ (r.error)[] ] ]
 |  | RET [ FALSE ]
 |  \_
 | (put.deinit)[]
 | ?put = (String.of)[ dest AS @CONST C1 ]
 | RET [ TRUE ]
 \_

; what `put` -- a trash's files/<name> -- held, back at `path`, its info
; file gone. FALSE, and why: something is at `path` now, or it is gone
B1 trash_restore: [ @CONST C1 put | @CONST C1 path | @String why ]
 | IF [ (taken)[ path ] ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ "something else is there now" ]
 |  | RET [ FALSE ]
 |  \_
 | String up = (get_parent_path)[ path ]
 | (fs_make_dirs)[ (up.cstr)[] ]
 | (up.deinit)[]
 | Result<B1 | IoError> r = (fs_rename)[ put | path ]
 | IF [ (r.is_err)[] ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ (io_error_text)[ (r.error)[] ] ]
 |  | RET [ FALSE ]
 |  \_
 | ; <trash>/files/<name> -> <trash>/info/<name>.trashinfo
 | String bin = (get_parent_path)[ put ]
 | String top = (get_parent_path)[ (bin.cstr)[] ]
 | String name = (get_dirname)[ put ]
 | C1 info{TRASH_PATH}
 | BufferSink b = (BufferSink.over)[ info | TRASH_PATH ]
 | (b.print)[ "%s/info/%s.trashinfo" | (top.cstr)[] | (name.cstr)[] ]
 | (fs_remove)[ info AS @CONST C1 ]
 | (bin.deinit)[]
 | (top.deinit)[]
 | (name.deinit)[]
 | RET [ TRUE ]
 \_

; --- the trash as a folder to look at -------------------------------------------

; is `dir` the files/ of a trash: the home one, a .Trash-<uid> at the top of
; a disk, or <top>/.Trash/<uid>?
B1 trash_files_dir: [ @CONST C1 dir ]
 | IF [ !((str_ends)[ dir | "/files" ]) ]
 |  | RET [ FALSE ]
 |  \_
 | String up = (get_parent_path)[ dir ]
 | String base = (get_dirname)[ (up.cstr)[] ]
 | String above = (get_parent_path)[ (up.cstr)[] ]
 | String above_name = (get_dirname)[ (above.cstr)[] ]
 | C1 home{TRASH_PATH}
 | (trash_home)[ home | TRASH_PATH ]
 | B1 yes = (up.equals)[ home AS @CONST C1 ] || (str_starts)[ (base.cstr)[] | ".Trash-" ] || (above_name.equals)[ ".Trash" ]
 | ; home reached through a link: the same layout, with its info/ beside
 | IF [ !yes && (base.equals)[ "Trash" ] ]
 |  | String info = (join_path)[ (up.cstr)[] | "info" ]
 |  | Result<FileInfo | IoError> fi = (fs_info)[ (info.cstr)[] ]
 |  | yes = (fi.is_ok)[] && (fi.unwrap)[].kind == FS_DIR && (above_name.equals)[ "share" ]
 |  | (info.deinit)[]
 |  \_
 | (up.deinit)[]
 | (base.deinit)[]
 | (above.deinit)[]
 | (above_name.deinit)[]
 | RET [ yes ]
 \_

; the info file of `item`, a trash's files/<name>, in `out`. FALSE: `item`
; is not directly in a trash's files/
B1 trash_info_of: [ @CONST C1 item | @C1 out | USIZE cap ]
 | String bin = (get_parent_path)[ item ]
 | String top = (get_parent_path)[ (bin.cstr)[] ]
 | String name = (get_dirname)[ item ]
 | B1 yes = (trash_files_dir)[ (bin.cstr)[] ]
 | IF [ yes ]
 |  | BufferSink b = (BufferSink.over)[ out | cap ]
 |  | (b.print)[ "%s/info/%s.trashinfo" | (top.cstr)[] | (name.cstr)[] ]
 |  \_
 | (bin.deinit)[]
 | (top.deinit)[]
 | (name.deinit)[]
 | RET [ yes ]
 \_

LOCAL I32 hex_val: [ C1 c ]
 | IF [ c >= '0' && c <= '9' ]
 |  | RET [ (c - '0') AS I32 ]
 |  \_
 | IF [ c >= 'a' && c <= 'f' ]
 |  | RET [ (c - 'a') AS I32 + 10 ]
 |  \_
 | IF [ c >= 'A' && c <= 'F' ]
 |  | RET [ (c - 'A') AS I32 + 10 ]
 |  \_
 | RET [ -1 ]
 \_

; `s` with its %XX undone, into `out`. FALSE: a % not followed by two hex
; digits, a %00, or not enough room. Nothing else is touched: a ? or # stays
B1 url_decode: [ @C1 out | USIZE cap | @CONST C1 s ]
 | USIZE o = 0
 | FOR [ USIZE i = 0 | s{i} != '\0' | i += 1 ]
 |  | C1 c = s{i}
 |  | IF [ c == '%' ]
 |  |  | I32 hi = (hex_val)[ s{i + 1} ]
 |  |  | IF [ hi < 0 ]
 |  |  |  | RET [ FALSE ]
 |  |  |  \_
 |  |  | I32 lo = (hex_val)[ s{i + 2} ]
 |  |  | IF [ lo < 0 || (hi == 0 && lo == 0) ]
 |  |  |  | RET [ FALSE ]
 |  |  |  \_
 |  |  | c = (hi * 16 + lo) AS C1
 |  |  | i += 2
 |  |  \_
 |  | IF [ o + 1 >= cap ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | out{o} = c
 |  | o += 1
 |  \_
 | out{o} = '\0'
 | RET [ TRUE ]
 \_

; n digits of `s` from `at` as a number; -1: one is not a digit
LOCAL I32 digits_at: [ @CONST C1 s | USIZE at | USIZE n ]
 | I32 v = 0
 | FOR [ USIZE i = 0 | i < n | i += 1 ]
 |  | IF [ s{at + i} < '0' || s{at + i} > '9' ]
 |  |  | RET [ -1 ]
 |  |  \_
 |  | v = v * 10 + (s{at + i} - '0') AS I32
 |  \_
 | RET [ v ]
 \_

; 2026-11-04T10:12:03, local time, as seconds since 1970; -1: it is not that
I64 trash_date: [ @CONST C1 s ]
 | IF [ (str_len)[ s ] < 19 || s{4} != '-' || s{7} != '-' || (s{10} != 'T' && s{10} != ' ') || s{13} != ':' || s{16} != ':' ]
 |  | RET [ -1 ]
 |  \_
 | I32 y = (digits_at)[ s | 0 | 4 ]
 | I32 mo = (digits_at)[ s | 5 | 2 ]
 | I32 d = (digits_at)[ s | 8 | 2 ]
 | I32 h = (digits_at)[ s | 11 | 2 ]
 | I32 mi = (digits_at)[ s | 14 | 2 ]
 | I32 se = (digits_at)[ s | 17 | 2 ]
 | IF [ y < 1970 || mo < 1 || mo > 12 || d < 1 || d > 31 || h < 0 || h > 23 || mi < 0 || mi > 59 || se < 0 || se > 60 ]
 |  | RET [ -1 ]
 |  \_
 | Tm t
 | t.sec = se
 | t.min = mi
 | t.hour = h
 | t.mday = d
 | t.mon = mo - 1
 | t.year = y - 1900
 | t.wday = 0
 | t.yday = 0
 | t.isdst = -1
 | t.gmtoff = 0
 | t.zone = ""
 | RET [ (px_mktime)[ @t ] ]
 \_

; a .trashinfo's `text`: the Path, decoded, into `path` (TRASH_PATH); the
; DeletionDate into `when` (-1: none). FALSE: there is no usable Path
B1 trashinfo_parse: [ @CONST C1 text | @C1 path | @I64 when ]
 | ?when = -1
 | path{0} = '\0'
 | B1 got = FALSE
 | USIZE i = 0
 | WHILE [ text{i} != '\0' ]
 |  | USIZE e = i
 |  | WHILE [ text{e} != '\0' && text{e} != '\n' ]
 |  |  | e += 1
 |  |  \_
 |  | ; the line, without a \r at its end
 |  | USIZE n = e - i
 |  | IF [ n > 0 && text{i + n - 1} == '\r' ]
 |  |  | n -= 1
 |  |  \_
 |  | IF [ n < 12000 ]
 |  |  | C1 line{12000}
 |  |  | FOR [ USIZE k = 0 | k < n | k += 1 ]
 |  |  |  | line{k} = text{i + k}
 |  |  |  \_
 |  |  | line{n} = '\0'
 |  |  | IF [ (str_starts)[ line AS @CONST C1 | "Path=" ] && !got ]
 |  |  |  | got = (url_decode)[ path | TRASH_PATH | (line AS @CONST C1) + 5 ]
 |  |  | ELIF [ (str_starts)[ line AS @CONST C1 | "DeletionDate=" ] ]
 |  |  |  | ?when = (trash_date)[ (line AS @CONST C1) + 13 ]
 |  |  |  \_
 |  |  \_
 |  | i = SELECT [ text{e} == '\0' | e | e + 1 ]
 |  \_
 | IF [ !got || path{0} == '\0' ]
 |  | path{0} = '\0'
 |  | RET [ FALSE ]
 |  \_
 | RET [ TRUE ]
 \_

; what the trash knows of `item`, a files/<name>: where it was, in full,
; into `path` (TRASH_PATH), and when it went, into `when` (-1: not known).
; FALSE: no readable info file with a Path. A relative Path is of the
; disk's top, as the spec has it
B1 trash_origin: [ @CONST C1 item | @C1 path | @I64 when ]
 | ?when = -1
 | path{0} = '\0'
 | C1 info{TRASH_PATH}
 | IF [ !((trash_info_of)[ item | info | TRASH_PATH ]) ]
 |  | RET [ FALSE ]
 |  \_
 | I32 fd = (px_open)[ info AS @CONST C1 | O_READ ]
 | IF [ fd < 0 ]
 |  | RET [ FALSE ]
 |  \_
 | C1 text{16384}
 | ISIZE n = (px_read)[ fd | text AS @ABYSS | 16383 ]
 | (px_close)[ fd ]
 | IF [ n <= 0 ]
 |  | RET [ FALSE ]
 |  \_
 | text{n AS USIZE} = '\0'
 | IF [ !((trashinfo_parse)[ text AS @CONST C1 | path | when ]) ]
 |  | RET [ FALSE ]
 |  \_
 | IF [ path{0} == '/' ]
 |  | RET [ TRUE ]
 |  \_
 | ; relative: of the top of the disk the trash is on
 | String bin = (get_parent_path)[ item ]
 | String trash = (get_parent_path)[ (bin.cstr)[] ]
 | String top = (get_parent_path)[ (trash.cstr)[] ]
 | String kind = (get_dirname)[ (top.cstr)[] ]
 | IF [ (kind.equals)[ ".Trash" ] ]
 |  | String again = (get_parent_path)[ (top.cstr)[] ]
 |  | (top.deinit)[]
 |  | top = again
 |  \_
 | String full = (join_path)[ (top.cstr)[] | path AS @CONST C1 ]
 | B1 ok = (str_len)[ (full.cstr)[] ] < TRASH_PATH
 | IF [ ok ]
 |  | (str_copy)[ path | TRASH_PATH | (full.cstr)[] ]
 | ELSE
 |  | path{0} = '\0'
 |  \_
 | (full.deinit)[]
 | (kind.deinit)[]
 | (top.deinit)[]
 | (trash.deinit)[]
 | (bin.deinit)[]
 | RET [ ok ]
 \_

; `item`, a trash's files/<name>, back to `orig`; where it went to, if
; that is taken, a free name beside it, is in `landed`. FALSE, and why in `why`
B1 trash_put_back: [ @CONST C1 item | @CONST C1 orig | @String landed | @String why ]
 | String dst = (String.of)[ orig ]
 | IF [ (taken)[ orig ] ]
 |  | String up = (get_parent_path)[ orig ]
 |  | String name = (get_dirname)[ orig ]
 |  | (dst.deinit)[]
 |  | dst = (free_name)[ (up.cstr)[] | (name.cstr)[] ]
 |  | (up.deinit)[]
 |  | (name.deinit)[]
 |  \_
 | (landed.deinit)[]
 | ?landed = (String.of)[ (dst.cstr)[] ]
 | B1 ok = (trash_restore)[ item | (dst.cstr)[] | why ]
 | (dst.deinit)[]
 | RET [ ok ]
 \_
