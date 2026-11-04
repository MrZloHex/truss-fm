; sys.pl -- the C library's calls trufm makes itself, under names of its own,
; and the numbers they take: what std does not wrap, or wraps with more
; than a copy of a big file wants

USE <std/core/core.pl>
USE <std/os/time.pl>
USE <std/core/date.pl>
USE <std/os/fs.pl>

; Linux's numbers, as std's File has them
CONST I32 O_READ = 0x80000                  ; O_RDONLY | O_CLOEXEC
CONST I32 O_MAKE = 0x800C1                  ; O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC

ISIZE px_read: [ I32 fd | @ABYSS buf | USIZE n ]
 + SYMBOL "read"
ISIZE px_write: [ I32 fd | @CONST ABYSS buf | USIZE n ]
 + SYMBOL "write"
I32 px_open: [ @CONST C1 path | I32 flags | ... ]
 + SYMBOL "open"
I32 px_close: [ I32 fd ]
 + SYMBOL "close"
I32 px_chmod: [ @CONST C1 path | U32 mode ]
 + SYMBOL "chmod"
ISIZE px_readlink: [ @CONST C1 path | @C1 buf | USIZE n ]
 + SYMBOL "readlink"
I32 px_symlink: [ @CONST C1 target | @CONST C1 path ]
 + SYMBOL "symlink"
I32 px_chown: [ @CONST C1 path | U32 uid | U32 gid ]
 + SYMBOL "chown"
I32 px_lchown: [ @CONST C1 path | U32 uid | U32 gid ]
 + SYMBOL "lchown"
I32 px_utimensat: [ I32 dirfd | @CONST C1 path | @CONST Timespec times | I32 flags ]
 + SYMBOL "utimensat"

; what a paste does with a name taken where it goes
I32 px_kill: [ I32 pid | I32 sig ]
 + SYMBOL "kill"

; struct tm, as glibc has it on a 64-bit machine
TYPE Tm: STRUCT
 | I32 sec
 | I32 min
 | I32 hour
 | I32 mday
 | I32 mon          ; 0 to 11
 | I32 year         ; since 1900
 | I32 wday
 | I32 yday
 | I32 isdst
 | I64 gmtoff
 | @CONST C1 zone
 \_

@Tm px_localtime_r: [ @CONST I64 t | @Tm out ]
 + SYMBOL "localtime_r"

I64 px_mktime: [ @Tm t ]
 + SYMBOL "mktime"

; `secs` since 1970 as the clock on the wall has them, here: the local zone
DateTime local_date: [ I64 secs ]
 | Tm t
 | (px_localtime_r)[ @secs | @t ]
 | DateTime d
 | d.year = (t.year + 1900) AS I64
 | d.month = (t.mon + 1) AS U8
 | d.day = t.mday AS U8
 | d.hour = t.hour AS U8
 | d.minute = t.min AS U8
 | d.second = t.sec AS U8
 | d.weekday = t.wday AS U8
 | d.yearday = t.yday AS U16
 | RET [ d ]
 \_

; --- what a file is, as the kernel has it ---------------------------------------

; struct passwd and struct group both begin with the name; the rest is not read
TYPE NameEnt: STRUCT
 | @CONST C1 name
 \_

@NameEnt px_getpwuid: [ U32 uid ]
 + SYMBOL "getpwuid"
@NameEnt px_getgrgid: [ U32 gid ]
 + SYMBOL "getgrgid"

; struct passwd and struct group both begin: name, password, then the number
TYPE IdEnt: STRUCT
 | @CONST C1 name
 | @CONST C1 pass
 | U32 id
 \_

@IdEnt px_getpwnam: [ @CONST C1 name ]
 + SYMBOL "getpwnam"
@IdEnt px_getgrnam: [ @CONST C1 name ]
 + SYMBOL "getgrnam"

; no change: what chown takes for an id left as it is
CONST U32 ID_KEEP = 0xFFFFFFFF

; a file's own facts, std's FileInfo lacks (a link is not followed)
TYPE Stat: STRUCT
 | U32 mode                 ; the type bits and the permissions
 | U32 uid
 | U32 gid
 | U64 ino
 | U64 nlink
 | U64 size
 | U32 dev_major
 | U32 dev_minor
 | U32 rdev_major
 | U32 rdev_minor
 | I64 atime                ; seconds since 1970
 | I64 mtime
 | I64 ctime
 \_

; `path` into `out`, through statx, whose struct is the same on every machine.
; FALSE: it cannot be read
B1 px_stat_of: [ @CONST C1 path | @Stat out ]
 | RET [ (px_stat_flags)[ path | FS_AT_SYMLINK_NOFOLLOW | out ] ]
 \_

; the same through a link, to what it points at. FALSE: it points at nothing
B1 px_stat_through: [ @CONST C1 path | @Stat out ]
 | RET [ (px_stat_flags)[ path | 0 | out ] ]
 \_

LOCAL B1 px_stat_flags: [ @CONST C1 path | I32 flags | @Stat out ]
 | StatxData st
 | IF [ (fs_sys_statx)[ FS_AT_FDCWD | path | flags | FS_STATX_BASIC | @st ] != 0 ]
 |  | RET [ FALSE ]
 |  \_
 | out.mode = st.mode AS U32
 | out.uid = st.uid
 | out.gid = st.gid
 | out.ino = st.ino
 | out.nlink = st.nlink AS U64
 | out.size = st.size
 | out.dev_major = st.dev_major
 | out.dev_minor = st.dev_minor
 | out.rdev_major = st.rdev_major
 | out.rdev_minor = st.rdev_minor
 | out.atime = st.atime.sec
 | out.mtime = st.mtime.sec
 | out.ctime = st.ctime.sec
 | RET [ TRUE ]
 \_

; the number of the user `name` (a name, or digits). FALSE: there is none such
B1 px_user_id: [ @CONST C1 name | @U32 out ]
 | IF [ name{0} >= '0' && name{0} <= '9' ]
 |  | RET [ (id_digits)[ name | out ] ]
 |  \_
 | @IdEnt e = (px_getpwnam)[ name ]
 | IF [ e == NULL ]
 |  | RET [ FALSE ]
 |  \_
 | ?out = e.id
 | RET [ TRUE ]
 \_

; the same for a group
B1 px_group_id: [ @CONST C1 name | @U32 out ]
 | IF [ name{0} >= '0' && name{0} <= '9' ]
 |  | RET [ (id_digits)[ name | out ] ]
 |  \_
 | @IdEnt e = (px_getgrnam)[ name ]
 | IF [ e == NULL ]
 |  | RET [ FALSE ]
 |  \_
 | ?out = e.id
 | RET [ TRUE ]
 \_

; all digits, and a number an id can be (not the one that means "keep")
LOCAL B1 id_digits: [ @CONST C1 s | @U32 out ]
 | U64 v = 0
 | FOR [ USIZE i = 0 | s{i} != '\0' | i += 1 ]
 |  | IF [ s{i} < '0' || s{i} > '9' || v > 0xFFFFFFFF ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | v = v * 10 + ((s{i} - '0') AS U64)
 |  \_
 | IF [ v >= 0xFFFFFFFF ]
 |  | RET [ FALSE ]
 |  \_
 | ?out = v AS U32
 | RET [ TRUE ]
 \_

; the user's name for `uid` into `out`; its number when it has none
ABYSS px_user_name: [ @C1 out | USIZE cap | U32 uid ]
 | @NameEnt e = (px_getpwuid)[ uid ]
 | IF [ e != NULL && e.name != NULL ]
 |  | (str_copy)[ out | cap | e.name ]
 | ELSE
 |  | BufferSink b = (BufferSink.over)[ out | cap ]
 |  | (b.print)[ "%u" | uid ]
 |  \_
 \_

; the same for a group
ABYSS px_group_name: [ @C1 out | USIZE cap | U32 gid ]
 | @NameEnt e = (px_getgrgid)[ gid ]
 | IF [ e != NULL && e.name != NULL ]
 |  | (str_copy)[ out | cap | e.name ]
 | ELSE
 |  | BufferSink b = (BufferSink.over)[ out | cap ]
 |  | (b.print)[ "%u" | gid ]
 |  \_
 \_
