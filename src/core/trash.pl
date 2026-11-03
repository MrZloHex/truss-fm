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
