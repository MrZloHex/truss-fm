
USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
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


; a word of mountinfo as it was: \040 a space, \011 a tab, \134 a backslash
LOCAL ABYSS unescape: [ @C1 s ]
 | USIZE r = 0
 | USIZE w = 0
 | WHILE [ s{r} != '\0' ]
 |  | B1 oct = s{r} == '\\' && s{r + 1} >= '0' && s{r + 1} <= '7'
 |  | IF [ oct && s{r + 2} >= '0' && s{r + 2} <= '7' && s{r + 3} >= '0' && s{r + 3} <= '7' ]
 |  |  | s{w} = (((s{r + 1} - '0') * 64) + ((s{r + 2} - '0') * 8) + (s{r + 3} - '0')) AS C1
 |  |  | r += 4
 |  | ELSE
 |  |  | s{w} = s{r}
 |  |  | r += 1
 |  |  \_
 |  | w += 1
 |  \_
 | s{w} = '\0'
 \_

TYPE Mount: STRUCT
 | String source            ; /dev/nvme0n1p2, or user@host:/home
 | String path              ; where it is mounted: /
 | B1 remote                ; over the network: sshfs, nfs, smb
 \_

; the file systems that are over the network, as mountinfo names them
CONST @CONST C1 REMOTE_FS{} = [ "fuse.sshfs" | "sshfs" | "nfs" | "nfs4" | "cifs" | "smb3" | "fuse.rclone" | "fuse.davfs" | "davfs" | "" ]

; is a file system of this type over the network?
B1 fs_remote: [ @CONST C1 fstype ]
 | FOR [ USIZE k = 0 | REMOTE_FS{k}{0} != 0 | k += 1 ]
 |  | IF [ (str_eq)[ fstype | REMOTE_FS{k} ] ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

ABYSS mounts_free: [ @Vector<Mount> v ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | ((v.at)[i].source.deinit)[]
 |  | ((v.at)[i].path.deinit)[]
 |  \_
 | (v.deinit)[]
 \_

; every block device that is mounted, in `out`, as mountinfo has them: a
; device once, where it was mounted first; loop devices left out -- snaps
; and the like -- but for an image the user mounted, under /run/media.
; And what is mounted over the network (sshfs, nfs, smb), `remote` set
ABYSS read_mounts: [ @Vector<Mount> out ]
 | String text
 | POSTLUDE (text.deinit)[]
 | IF [ ((read_file)[ "/proc/self/mountinfo" | @text ].is_err)[] ]
 |  | RET []
 |  \_
 | C1 word{WORD}
 | C1 mount{WORD}
 | C1 kind{WORD}
 | @CONST C1 line = (text.cstr)[]
 | WHILE [ ?line != '\0' ]
 |  | ; id, parent, maj:min, root, then the mount point
 |  | @CONST C1 p = (field)[ (field)[ (field)[ (field)[ line | word ] | word ] | word ] | word ]
 |  | p = (field)[ p | mount ]
 |  | LOOP
 |  |  | p = (field)[ p | word ]
 |  |  | IF [ word{0} == '\0' || (str_eq)[ word | "-" ] ]
 |  |  |  | BREAK
 |  |  |  \_
 |  |  \_
 |  | ; the type, then the source
 |  | (field)[ (field)[ p | kind ] | word ]
 |  | B1 remote = (fs_remote)[ kind AS @CONST C1 ]
 |  | IF [ remote || ((str_starts)[ word | "/dev/" ] && (!((str_starts)[ word | "/dev/loop" ]) || (str_starts)[ mount | "/run/media/" ])) ]
 |  |  | B1 seen = FALSE
 |  |  | FOR [ USIZE i = 0 | i < (out.size)[] | i += 1 ]
 |  |  |  | IF [ ((out.at)[i].source.equals)[ word AS @CONST C1 ] ]
 |  |  |  |  | seen = TRUE
 |  |  |  |  \_
 |  |  |  \_
 |  |  | IF [ !seen ]
 |  |  |  | (unescape)[ mount ]
 |  |  |  | Mount m
 |  |  |  | m.source = (String.of)[ word AS @CONST C1 ]
 |  |  |  | m.path = (String.of)[ mount AS @CONST C1 ]
 |  |  |  | m.remote = remote
 |  |  |  | (out.push)[ m ]
 |  |  |  \_
 |  |  \_
 |  | WHILE [ ?line != '\0' && ?line != '\n' ]
 |  |  | line += 1
 |  |  \_
 |  | IF [ ?line == '\n' ]
 |  |  | line += 1
 |  |  \_
 |  \_
 \_

; what is mounted, as one number: another number, another set of mounts
U64 mounts_signature: []
 | String text
 | POSTLUDE (text.deinit)[]
 | IF [ ((read_file)[ "/proc/self/mountinfo" | @text ].is_err)[] ]
 |  | RET [ 0 ]
 |  \_
 | U64 h = 14695981039346656037      ; FNV-1a
 | @CONST C1 s = (text.cstr)[]
 | FOR [ USIZE i = 0 | s{i} != '\0' | i += 1 ]
 |  | h = (h ^ ((s{i} AS U8) AS U64)) * 1099511628211
 |  \_
 | RET [ h ]
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

; where the file system `path` is on is mounted, in `out`: / for /home/x
; when /home is no mount of its own. FALSE: it cannot be told
B1 mount_point_of: [ @CONST C1 path | @C1 out | USIZE cap ]
 | String mounts
 | POSTLUDE (mounts.deinit)[]
 | IF [ ((read_file)[ "/proc/self/mountinfo" | @mounts ].is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | Result<FileInfo | IoError> info = (fs_info)[ path ]
 | IF [ (info.is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | FileInfo i = (info.unwrap)[]
 | C1 dev{32}
 | USIZE n = (fmt_u64)[ dev | i.dev_major AS U64 | 10 ]
 | dev{n} = ':'
 | n += 1
 | n += (fmt_u64)[ dev + n | i.dev_minor AS U64 | 10 ]
 | dev{n} = '\0'
 | C1 source{WORD}
 | C1 mount{WORD}
 | C1 fstype{WORD}
 | IF [ !((find_mount)[ (mounts.cstr)[] | dev | source | mount | fstype ]) ]
 |  | RET [ FALSE ]
 |  \_
 | (unescape)[ mount ]
 | (str_copy)[ out | cap | mount AS @CONST C1 ]
 | RET [ TRUE ]
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

; --- paths ----------------------------------------------------------------------

; `dir`/`name`; / has no second /
String join_path: [ @CONST C1 dir | @CONST C1 name ]
 | String s = (String.of)[ dir ]
 | IF [ !((str_eq)[ dir | "/" ]) ]
 |  | (s.append)[ "/" ]
 |  \_
 | (s.append)[ name ]
 | RET [ s ]
 \_

; is `path` `dir` or in it?
B1 is_under: [ @CONST C1 path | @CONST C1 dir ]
 | USIZE n = (str_len)[ dir ]
 | IF [ !((str_starts)[ path | dir ]) ]
 |  | RET [ FALSE ]
 |  \_
 | RET [ path{n} == '\0' || path{n} == '/' || (str_eq)[ dir | "/" ] ]
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
