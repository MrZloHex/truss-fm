
USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

CONST USIZE WORD = 512
CONST F64 GB = 1e9             ; as disks are sold
CONST F64 GIB = 1073741824.0   ; 2^30, as df -h counts

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


Option<String> get_phy_part_name: [ @CONST C1 cwd ]
 | String mounts
 | POSTLUDE (mounts.deinit)[]
 | IF [ ((read_file)[ "/proc/self/mountinfo" | @mounts ].is_err)[] ]
 |  | RET [ (Option<String>.none)[] ]
 |  \_
 | 
 | Result<FileInfo | IoError> info = (fs_info)[ cwd ]
 | IF [ (info.is_err)[] ]
 |  | RET [ (Option<String>.none)[] ]
 |  \_
 | FileInfo i = (info.unwrap)[]
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
 | (find_mount)[ (mounts.cstr)[] | dev | source | mount | fstype ]
 |
 | RET [ (Option<String>.some)[(String.of)[source]] ]
 \_

Option<F32> get_phy_part_usage: [ @CONST C1 cwd ]
 | Result<FsSpace | IoError> room = (fs_space)[ cwd ]
 | IF [ (room.is_err)[] ]
 |  | RET [ (Option<F32>.none)[] ]
 |  \_
 | FsSpace s = (room.unwrap)[]
 | U64 used = s.total - s.free
 |
 | U64 whole = used + s.available
 | RET [ (Option<F32>.some)[SELECT [ whole > 0 | 100.0 * (used AS F64) / (whole AS F64) | 0.0 ]] ]
 \_

Option<F64> get_phy_part_free: [ @CONST C1 cwd ]
 | Result<FsSpace | IoError> room = (fs_space)[ cwd ]
 | IF [ (room.is_err)[] ]
 |  | RET [ (Option<F64>.none)[] ]
 |  \_
 | FsSpace s = (room.unwrap)[]
 | RET [ (Option<F64>.some)[(s.available AS F64) / GIB] ]
 \_
