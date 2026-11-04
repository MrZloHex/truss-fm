; job.pl -- a command run beside the frames, for what it prints: a
; previewer. Each frame reads what is there to read and no more, so a slow
; one never holds the screen still; it is stopped at `limit` bytes, and
; killed when what it was run for is no longer wanted

USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/process.pl>

!USES <rules.pl>
!USES <sys.pl>
!USES <extern/poll.pl>

CONST USIZE JOB_CHUNK = 16384

; setsid there, to give each job a process group of its own: 1 yes, -1 no,
; 0 not looked for yet
LOCAL I32 have_setsid

TYPE Job: STRUCT
 | Process p
 | B1 live                  ; started, and not yet waited for
 | B1 done                  ; all it printed is in `out`, or all it may
 | B1 ok                    ; it ended, and with 0
 | String out
 | USIZE limit
 \_

; `cmd` run on the file `file`, as rules.pl runs a rule: sh -c, the file
; in "$@"; its stdout to read, its stdin and stderr nothing. FALSE: it
; could not be started
B1 job_start: [ @Job j | @CONST C1 cmd | @CONST C1 file | USIZE limit ]
 | String line = (shell_line)[ cmd ]
 | POSTLUDE (line.deinit)[]
 | RET [ (job_spawn)[ j | (line.cstr)[] | file | NULL | limit ] ]
 \_

; the sh `script` run in the folder `dir`, the file as "$1" ("$@"): what it
; prints, to stdout and to stderr both, to read. FALSE: it could not be
; started
B1 job_start_in: [ @Job j | @CONST C1 script | @CONST C1 dir | @CONST C1 file | USIZE limit ]
 | String line = (String.of)[ "cd \"$1\" || exit 1; shift; {\n" ]
 | POSTLUDE (line.deinit)[]
 | (line.append)[ script ]
 | (line.append)[ "\n} 2>&1" ]
 | RET [ (job_spawn)[ j | (line.cstr)[] | dir | file | limit ] ]
 \_

; the sh `script` run in `dir` as job_start_in does, with any number of
; files: `lead` (if not NULL) is "$1", the strings of `files` follow it in
; "$@". They are never put into the script. FALSE: it could not be started
B1 job_start_many: [ @Job j | @CONST C1 script | @CONST C1 dir | @CONST C1 lead | @Vector<String> files | USIZE limit ]
 | String line = (String.of)[ "cd \"$1\" || exit 1; shift; {\n" ]
 | POSTLUDE (line.deinit)[]
 | (line.append)[ script ]
 | (line.append)[ "\n} 2>&1" ]
 | (job_stop)[ j ]
 | IF [ have_setsid == 0 ]
 |  | have_setsid = SELECT [ (program_there)[ "setsid" ] | 1 | -1 ]
 |  \_
 | Vector<@CONST C1> argv
 | POSTLUDE (argv.deinit)[]
 | IF [ have_setsid > 0 ]
 |  | (argv.push)[ "setsid" ]
 |  \_
 | (argv.push)[ "sh" ]
 | (argv.push)[ "-c" ]
 | (argv.push)[ (line.cstr)[] ]
 | (argv.push)[ "trufm" ]
 | (argv.push)[ dir ]
 | IF [ lead != NULL ]
 |  | (argv.push)[ lead ]
 |  \_
 | FOR [ USIZE i = 0 | i < (files.size)[] | i += 1 ]
 |  | (argv.push)[ ((files.at)[ i ].cstr)[] ]
 |  \_
 | (argv.push)[ NULL ]
 | Result<Process | IoError> r = (Process.spawn)[ argv.data AS @CONST @CONST C1 | PROCESS_NULL | PROCESS_PIPE | PROCESS_NULL ]
 | IF [ (r.is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | j.p = (r.unwrap)[]
 | j.live = TRUE
 | j.done = FALSE
 | j.ok = FALSE
 | j.limit = limit
 | (j.out.deinit)[]
 | j.out = (String.of)[ "" ]
 | RET [ TRUE ]
 \_

; sh -c `line` trufm `a1` [`a2`]: started, its stdout to read
LOCAL B1 job_spawn: [ @Job j | @CONST C1 line | @CONST C1 a1 | @CONST C1 a2 | USIZE limit ]
 | (job_stop)[ j ]
 | ; under setsid it leads a group of its own, and all it starts -- sh's
 | ; children, a pipe's -- goes with it when it is killed
 | IF [ have_setsid == 0 ]
 |  | have_setsid = SELECT [ (program_there)[ "setsid" ] | 1 | -1 ]
 |  \_
 | @CONST C1 alone{} = [ "setsid" | "sh" | "-c" | line | "trufm" | a1 | a2 | NULL ]
 | @CONST C1 plain{} = [ "sh" | "-c" | line | "trufm" | a1 | a2 | NULL ]
 | Result<Process | IoError> r = (Process.spawn)[ SELECT [ have_setsid > 0 | alone AS @CONST @CONST C1 | plain AS @CONST @CONST C1 ] | PROCESS_NULL | PROCESS_PIPE | PROCESS_NULL ]
 | IF [ (r.is_err)[] ]
 |  | RET [ FALSE ]
 |  \_
 | j.p = (r.unwrap)[]
 | j.live = TRUE
 | j.done = FALSE
 | j.ok = FALSE
 | j.limit = limit
 | (j.out.deinit)[]
 | j.out = (String.of)[ "" ]
 | RET [ TRUE ]
 \_

; it is done: waited for, and how it ended noted
LOCAL ABYSS job_reap: [ @Job j ]
 | IF [ j.live ]
 |  | Result<ExitStatus | IoError> e = (j.p.wait)[]
 |  | j.ok = (e.is_ok)[] && (e.unwrap)[].exited && (e.unwrap)[].code == 0
 |  | j.live = FALSE
 |  \_
 | j.done = TRUE
 \_

; what it printed since, read without waiting. TRUE: it is done
B1 job_pump: [ @Job j ]
 | IF [ j.done || !(j.live) ]
 |  | RET [ TRUE ]
 |  \_
 | I32 fd = ((j.p.output)[].fd_of)[]
 | U8 buf{JOB_CHUNK}
 | LOOP
 |  | PollFd pf = [ .fd = fd | .events = POLLIN ]
 |  | IF [ (poll)[ @pf | 1 | 0 ] <= 0 ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | ISIZE n = (px_read)[ fd | buf AS @ABYSS | JOB_CHUNK ]
 |  | IF [ n <= 0 ]
 |  |  | ; the end of what it prints: it has ended, or is about to
 |  |  | (job_reap)[ j ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | (j.out.append_n)[ buf AS @CONST C1 | n AS USIZE ]
 |  | IF [ (j.out.size)[] >= j.limit ]
 |  |  | ; enough to show: the rest is not wanted
 |  |  | (job_kill)[ j ]
 |  |  | (job_reap)[ j ]
 |  |  | j.ok = TRUE
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 \_

; it, and what it started, killed
LOCAL ABYSS job_kill: [ @Job j ]
 | IF [ have_setsid > 0 ]
 |  | (px_kill)[ -((j.p.id)[]) | 9 ]
 |  \_
 | (j.p.kill)[ 9 ]
 \_

; stopped (SIGSTOP) or let go on (SIGCONT), with all it started
ABYSS job_pause: [ @Job j | B1 stop ]
 | IF [ !(j.live) ]
 |  | RET []
 |  \_
 | I32 sig = SELECT [ stop | 19 | 18 ]
 | IF [ have_setsid > 0 ]
 |  | (px_kill)[ -((j.p.id)[]) | sig ]
 | ELSE
 |  | (px_kill)[ (j.p.id)[] | sig ]
 |  \_
 \_

; killed if it runs, and what it printed let go
ABYSS job_stop: [ @Job j ]
 | IF [ j.live ]
 |  | (job_kill)[ j ]
 |  | (job_reap)[ j ]
 |  \_
 | j.done = FALSE
 | (j.out.deinit)[]
 | j.out = (String.of)[ "" ]
 \_

B1 job_running: [ @Job j ]
 | RET [ j.live && !(j.done) ]
 \_
