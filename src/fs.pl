
USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

CONST USIZE WORD = 512
CONST F64 GB = 1e9             ; as disks are sold
CONST F64 GIB = 1073741824.0   ; 2^30, as df -h counts
CONST @CONST C1 MONTHS{} = [ "Jan" | "Feb" | "Mar" | "Apr" | "May" | "Jun" | "Jul" | "Aug" | "Sep" | "Oct" | "Nov" | "Dec" ]

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


Result<String | IoError> get_realpath: [ @CONST C1 cwd ]
 | C1 full{4096}
 | Result<USIZE | IoError> r = (fs_real)[ full | 4096 | cwd ]
 | IF [ (r.is_err)[] ]
 |  | RET [ (Result<String | IoError>.err)[ (r.error)[] ] ]
 |  \_
 | RET [ (Result<String | IoError>.ok)[ (String.of)[full] ] ]
 \_

String get_shorter_path: [ @CONST C1 cwd ]
 | @CONST C1 home = ((env)[ "HOME" ].unwrap_or)[ "/" ]
 | String s = (String.of)[cwd]
 | (s.replace)[ home | "~" ]
 | RET [ s ]
 \_

String get_dirname: [ @CONST C1 path ]
 | Split s = (Split.over)[ path | '/' ]
 | Span<C1> field
 | WHILE [ (s.next_span)[ @field ] ]
 |  \_
 | RET [ (String.of_span)[field] ]
 \_

; the folder around `path`, which is absolute; / is its own
String get_parent_path: [ @CONST C1 path ]
 | String s = (String.of)[ path ]
 | USIZE cut = 0
 | FOR [ USIZE i = 0 | path{i} != '\0' | i += 1 ]
 |  | IF [ path{i} == '/' ]
 |  |  | cut = i
 |  |  \_
 |  \_
 | (s.truncate)[ SELECT [ cut > 0 | cut | 1 ] ]
 | RET [ s ]
 \_

; a size for a narrow column: 512B, 6K, 3.1M
ABYSS size_text: [ @C1 out | U64 n ]
 | BufferSink b = (BufferSink.over)[ out | 16 ]
 | F64 v = n AS F64
 | IF [ n < 1024 ]
 |  | (b.print)[ "%uB" | n AS U32 ]
 | ELIF [ n < 1024 * 1024 ]
 |  | (b.print)[ "%.0fK" | v / 1024.0 ]
 | ELIF [ n < 1024 * 1024 * 1024 ]
 |  | (b.print)[ "%.1fM" | v / 1048576.0 ]
 | ELSE
 |  | (b.print)[ "%.1fG" | v / GIB ]
 |  \_
 \_
