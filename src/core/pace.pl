; pace.pl -- how fast a task goes, and how long it has left: a speed kept
; smoothed, and said in words. Pure: no clock is read here

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/io/io.pl>

CONST U64 PACE_WINDOW_MS = 500          ; the speed is looked at this often

; the speed, in thousandths of a unit a second, after `units` more were done
; in `ms`: the first look is taken as it is, later ones mixed into the old
; (`have`) two parts to one
U64 pace_mix: [ U64 old | B1 have | U64 units | U64 ms ]
 | IF [ ms == 0 ]
 |  | RET [ old ]
 |  \_
 | U64 now = (units * 1000000) / ms
 | IF [ !have ]
 |  | RET [ now ]
 |  \_
 | RET [ (old * 2 + now) / 3 ]
 \_

; seconds to do `left` units at `mrate` thousandths of a unit a second;
; 0 when the speed is not known
U64 pace_secs: [ U64 left | U64 mrate ]
 | IF [ mrate == 0 ]
 |  | RET [ 0 ]
 |  \_
 | RET [ (left * 1000) / mrate ]
 \_

; bytes a second: 800 B/s, 512 KB/s, 12.3 MB/s, 1.2 GB/s
ABYSS pace_bytes: [ @C1 out | USIZE cap | U64 mrate ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | U64 bps = mrate / 1000
 | IF [ bps < 1024 ]
 |  | (b.print)[ "%d B/s" | bps AS I32 ]
 | ELIF [ bps < 1048576 ]
 |  | (b.print)[ "%d KB/s" | (bps / 1024) AS I32 ]
 | ELIF [ bps < 1073741824 ]
 |  | U64 t = (bps * 10) / 1048576
 |  | (b.print)[ "%d.%d MB/s" | (t / 10) AS I32 | (t % 10) AS I32 ]
 | ELSE
 |  | U64 t = (bps * 10) / 1073741824
 |  | (b.print)[ "%d.%d GB/s" | (t / 10) AS I32 | (t % 10) AS I32 ]
 |  \_
 \_

; entries a second: 42.0 items/s
ABYSS pace_items: [ @C1 out | USIZE cap | U64 mrate ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | (b.print)[ "%d.%d items/s" | (mrate / 1000) AS I32 | ((mrate % 1000) / 100) AS I32 ]
 \_

; the time left: 34 s left, 2 min left, 1 h 5 min left
ABYSS pace_left: [ @C1 out | USIZE cap | U64 secs ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | IF [ secs < 60 ]
 |  | (b.print)[ "%d s left" | secs AS I32 ]
 | ELIF [ secs < 3600 ]
 |  | (b.print)[ "%d min left" | ((secs + 59) / 60) AS I32 ]
 | ELSE
 |  | U64 m = (secs % 3600) / 60
 |  | IF [ m == 0 ]
 |  |  | (b.print)[ "%d h left" | (secs / 3600) AS I32 ]
 |  | ELSE
 |  |  | (b.print)[ "%d h %d min left" | (secs / 3600) AS I32 | m AS I32 ]
 |  |  \_
 |  \_
 \_
