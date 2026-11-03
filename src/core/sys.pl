; sys.pl -- the C library's calls pluf makes itself, under names of its own,
; and the numbers they take: what std does not wrap, or wraps with more
; than a copy of a big file wants

USE <std/core/core.pl>
USE <std/os/time.pl>
USE <std/core/date.pl>

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
