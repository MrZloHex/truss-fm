; where.pl -- which partition a path is on, how full it is, what is left
;
;   ./where [path]

USE <std/core/core.pl>
USE <std/alloc/alloc.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

CONST USIZE WORD = 512
CONST F64 GB = 1e9             ; as disks are sold
CONST F64 GIB = 1073741824.0   ; 2^30, as df -h counts

; the next space-separated word of `s` into `out`; where it stopped
LOCAL @CONST C1 field: [ @CONST C1 s | @C1 out ]
 | USIZE n = 0
 | WHILE [ ?s == ' ' ]
 |  | s += 1
 |  \_
 | WHILE [ ?s != '\0' && ?s != ' ' && ?s != '\n' ]
 |  | IF [ n + 1 < WORD ]
 |  |  | out{n} = ?s
 |  |  | n += 1
 |  |  \_
 |  | s += 1
 |  \_
 | out{n} = '\0'
 | RET [ s ]
 \_

; mountinfo's lines read: id parent major:minor root mountpoint options...
; - fstype source options. The first line for device `dev`.
LOCAL B1 find_mount: [ @CONST C1 text | @CONST C1 dev | @C1 source | @C1 mount | @C1 fstype ]
 | C1 word{WORD}
 | @CONST C1 line = text
 | WHILE [ ?line != '\0' ]
 |  | @CONST C1 p = (field)[ (field)[ line | word ] | word ]
 |  | p = (field)[ p | word ]
 |  | B1 hit = (str_eq)[ word | dev ]
 |  | p = (field)[ (field)[ p | word ] | mount ]
 |  | IF [ hit ]
 |  |  | LOOP
 |  |  |  | p = (field)[ p | word ]
 |  |  |  | IF [ word{0} == '\0' || (str_eq)[ word | "-" ] ]
 |  |  |  |  | BREAK
 |  |  |  |  \_
 |  |  |  \_
 |  |  | (field)[ (field)[ p | fstype ] | source ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | WHILE [ ?line != '\0' && ?line != '\n' ]
 |  |  | line += 1
 |  |  \_
 |  | IF [ ?line == '\n' ]
 |  |  | line += 1
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

I32 main: [ I32 argc | @@C1 argv ]
 | @CONST C1 path = SELECT [ argc > 1 | argv{1} AS @CONST C1 | "." ]
 |
 | Result<FileInfo | IoError> info = (fs_info)[ path ]
 | Result<FsSpace | IoError> room = (fs_space)[ path ]
 | IF [ (info.is_err)[] || (room.is_err)[] ]
 |  | (stdout.print)[ "%s: no such place, or not allowed\n" | path ]
 |  | RET [ 1 ]
 |  \_
 | FileInfo i = (info.unwrap)[]
 | FsSpace s = (room.unwrap)[]
 |
 | ; "259:4", as mountinfo writes it
 | C1 dev{32}
 | USIZE n = (fmt_u64)[ dev | i.dev_major AS U64 | 10 ]
 | dev{n} = ':'
 | n += 1
 | n += (fmt_u64)[ dev + n | i.dev_minor AS U64 | 10 ]
 | dev{n} = '\0'
 |
 | C1 source{WORD}
 | C1 mount{WORD}
 | C1 fstype{WORD}
 | (str_copy)[ source | WORD | "unknown" ]
 | (str_copy)[ mount | WORD | "?" ]
 | (str_copy)[ fstype | WORD | "?" ]
 | String all
 | POSTLUDE (all.deinit)[]
 | IF [ ((read_file)[ "/proc/self/mountinfo" | @all ].is_ok)[] ]
 |  | (find_mount)[ (all.cstr)[] | dev | source | mount | fstype ]
 |  \_
 |
 | U64 used = s.total - s.free
 | ; /proc and the like hold nothing, so have no size to be a share of
 | U64 whole = used + s.available
 | F64 percent = SELECT [ whole > 0 | 100.0 * (used AS F64) / (whole AS F64) | 0.0 ]
 | (stdout.print)[ "Device:  %s (%s), %s\n" | source | dev | fstype ]
 | (stdout.print)[ "Mounted: %s\n" | mount ]
 | (stdout.print)[ "Used:    %.1f GB of %.1f GB, %.1f GiB of %.1f GiB (%.0f%% full)\n" | (used AS F64) / GB | (s.total AS F64) / GB | (used AS F64) / GIB | (s.total AS F64) / GIB | percent ]
 | (stdout.print)[ "Left:    %.1f GB, %.1f GiB\n" | (s.available AS F64) / GB | (s.available AS F64) / GIB ]
 | RET [ 0 ]
 \_
