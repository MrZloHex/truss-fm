; tasks_test.pl -- the speed and time-left words from core/pace.pl, and the
; task engine's cancel and retry: a copy given up leaves no half file, a
; failed step is done again alone
USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/time.pl>
!USES <../src/core/tasks.pl>

LOCAL I32 bad = 0
LOCAL U8 chunk{1048576}

LOCAL ABYSS want: [ B1 ok | @CONST C1 what ]
 | IF [ !ok ]
 |  | (stderr.print)[ "FAIL: %s\n" | what ]
 |  | bad += 1
 |  \_
 \_

LOCAL ABYSS says: [ @CONST C1 got | @CONST C1 expect ]
 | IF [ !((str_eq)[ got | expect ]) ]
 |  | (stderr.print)[ "FAIL: \"%s\", wanted \"%s\"\n" | got | expect ]
 |  | bad += 1
 |  \_
 \_

LOCAL ABYSS left_is: [ U64 secs | @CONST C1 expect ]
 | C1 s{64}
 | (pace_left)[ s | 64 | secs ]
 | (says)[ s AS @CONST C1 | expect ]
 \_

LOCAL ABYSS bytes_are: [ U64 bps | @CONST C1 expect ]
 | C1 s{64}
 | (pace_bytes)[ s | 64 | bps * 1000 ]
 | (says)[ s AS @CONST C1 | expect ]
 \_

; a file of `mb` megabytes
LOCAL ABYSS make_file: [ @CONST C1 path | I32 mb ]
 | I32 fd = (px_open)[ path | O_MAKE | 0x1A4 ]
 | FOR [ I32 i = 0 | i < mb | i += 1 ]
 |  | (px_write)[ fd | chunk AS @CONST ABYSS | 1048576 ]
 |  \_
 | (px_close)[ fd ]
 \_

; the tasks in `ts` worked until none is busy
LOCAL ABYSS finish: [ @Vector<Task> ts ]
 | FOR [ I32 i = 0 | i < 100000 && (tasks_busy)[ ts ] | i += 1 ]
 |  | (tasks_run)[ ts ]
 |  \_
 \_

LOCAL B1 has: [ @CONST C1 path ]
 | RET [ (taken)[ path ] ]
 \_

I32 main: []
 | (left_is)[ 5 | "5 s left" ]
 | (left_is)[ 59 | "59 s left" ]
 | (left_is)[ 60 | "1 min left" ]
 | (left_is)[ 61 | "2 min left" ]
 | (left_is)[ 120 | "2 min left" ]
 | (left_is)[ 3600 | "1 h left" ]
 | (left_is)[ 3900 | "1 h 5 min left" ]
 | (left_is)[ 7500 | "2 h 5 min left" ]
 | (bytes_are)[ 800 | "800 B/s" ]
 | (bytes_are)[ 512 * 1024 | "512 KB/s" ]
 | (bytes_are)[ 12 * 1048576 + 314573 | "12.3 MB/s" ]
 | (bytes_are)[ 2147483648 AS U64 | "2.0 GB/s" ]
 | C1 it{32}
 | (pace_items)[ it | 32 | 42000 ]
 | (says)[ it AS @CONST C1 | "42.0 items/s" ]
 | ; the first look is taken whole, then mixed 2 : 1; no time passed changes nothing
 | (want)[ (pace_mix)[ 0 | FALSE | 1000 | 1000 ] == 1000000 | "first look" ]
 | (want)[ (pace_mix)[ 3000 | TRUE | 0 | 1000 ] == 2000 | "mixed" ]
 | (want)[ (pace_mix)[ 77 | TRUE | 5 | 0 ] == 77 | "no time" ]
 | (want)[ (pace_secs)[ 100 | 0 ] == 0 | "no speed, no time" ]
 | (want)[ (pace_secs)[ 100 | 10000 ] == 10 | "100 at 10 a second" ]
 |
 | ; a copy given up half way through a big file
 | String base = (String.of)[ "obj/tasks_test_dir" ]
 | (fs_make_dir)[ (base.cstr)[] ]
 | String from = (join_path)[ (base.cstr)[] | "from" ]
 | String into = (join_path)[ (base.cstr)[] | "into" ]
 | (fs_make_dir)[ (from.cstr)[] ]
 | (fs_make_dir)[ (into.cstr)[] ]
 | String small = (join_path)[ (from.cstr)[] | "a-small" ]
 | String big = (join_path)[ (from.cstr)[] | "b-big" ]
 | (make_file)[ (small.cstr)[] | 1 ]
 | (make_file)[ (big.cstr)[] | 4 ]
 | Vector<String> paths
 | (paths.push)[ (String.of)[ (small.cstr)[] ] ]
 | (paths.push)[ (String.of)[ (big.cstr)[] ] ]
 | Task t = (task_transfer)[ FALSE | @paths | (into.cstr)[] | CLASH_KEEP ]
 | Vector<Task> ts
 | (ts.push)[ t ]
 | @Task r = (ts.at)[ 0 ]
 | ; until the big one is open, and a chunk of it written
 | FOR [ I32 i = 0 | i < 1000 && !(r.in >= 0 && (r.target.size)[] > 0 && r.done > 1048576 * 2) | i += 1 ]
 |  | (task_step)[ r ]
 |  \_
 | String half = (join_path)[ (into.cstr)[] | "b-big" ]
 | (want)[ r.in >= 0 && (has)[ (half.cstr)[] ] | "the big file is half copied" ]
 | (task_pause)[ r | TRUE ]
 | (want)[ !((tasks_busy)[ @ts ]) | "a paused task is not busy" ]
 | (task_pause)[ r | FALSE ]
 | (task_cancel)[ r ]
 | (want)[ !((task_running)[ r ]) | "cancelled: ended" ]
 | (want)[ !((has)[ (half.cstr)[] ]) | "cancelled: the half file is gone" ]
 | String whole = (join_path)[ (into.cstr)[] | "a-small" ]
 | (want)[ (has)[ (whole.cstr)[] ] | "cancelled: the finished file stays" ]
 | (want)[ r.in < 0 && (r.steps.size)[] == 0 | "cancelled: nothing left to do" ]
 |
 | ; a step that fails is kept, and done again alone
 | Vector<String> two
 | String lost = (join_path)[ (from.cstr)[] | "c-lost" ]
 | (two.push)[ (String.of)[ (small.cstr)[] ] ]
 | (two.push)[ (String.of)[ (lost.cstr)[] ] ]
 | String into2 = (join_path)[ (base.cstr)[] | "into2" ]
 | (fs_make_dir)[ (into2.cstr)[] ]
 | Task t2 = (task_transfer)[ FALSE | @two | (into2.cstr)[] | CLASH_KEEP ]
 | (ts.push)[ t2 ]
 | (finish)[ @ts ]
 | @Task f = (ts.at)[ 1 ]
 | (want)[ f.failed >= 1 && (task_held)[ f ] | "a failure keeps the task" ]
 | (want)[ (f.bad_src.size)[] == 1 && (str_eq)[ ((f.bad_src.at)[ 0 ].cstr)[] | (lost.cstr)[] ] | "only the failed one is kept" ]
 | (make_file)[ (lost.cstr)[] | 1 ]
 | Task again = (task_retry)[ f ]
 | (want)[ again.over && (again.steps.size)[] == 2 | "a retry: its step and its sizing" ]
 | (ts.push)[ again ]
 | (finish)[ @ts ]
 | String got = (join_path)[ (into2.cstr)[] | "c-lost" ]
 | (want)[ (has)[ (got.cstr)[] ] | "the retry copied it" ]
 | @Task g = (ts.at)[ 2 ]
 | (want)[ g.failed == 0 && !((task_held)[ g ]) | "and did not fail" ]
 |
 | ; everything made here taken away, by a delete of the folder
 | Vector<String> gone
 | (gone.push)[ (String.of)[ (base.cstr)[] ] ]
 | Task d = (task_delete)[ @gone | NULL ]
 | (ts.push)[ d ]
 | (finish)[ @ts ]
 | (want)[ !((has)[ (base.cstr)[] ]) | "the test folder is gone" ]
 |
 | IF [ bad != 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "tasks_test: ok\n" ]
 | RET [ 0 ]
 \_
