; remote.pl -- is a folder on a mount over the network answering? A server
; that stops answering holds every call that reaches it for ever, so before
; one is made the mount is asked, by a job beside the frames (`stat -f`: a
; statfs is the server's to answer, not the cache's). A mount is up, not known
; yet (a probe is out, and has not been out for long) or down (it has not
; answered for REMOTE_DEAD_MS, or answered no): nothing is called on it unless
; it is up, and a call that asks is told so at once, until its probe answers
; again. A mount in use is asked ahead of time, so an answer is there when
; it is wanted

USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

!USES <fs.pl>
!USES <sys.pl>
!USES <job.pl>
!USES <extern/poll.pl>

CONST U64 REMOTE_FRESH_MS = 3000     ; an answer is good for this long
CONST U64 REMOTE_AHEAD_MS = 1000     ; a mount in use is asked again this long after an answer
CONST U64 REMOTE_ASKED_MS = 10000    ; "in use": something asked about it this recently
CONST U64 REMOTE_RETRY_MS = 1000     ; a mount that is down is asked again this often
CONST U64 REMOTE_DEAD_MS = 2500      ; a probe out this long: the mount is down
CONST U64 REMOTE_WAIT_MS = 300       ; how long a call waits for the answer, once per probe
CONST USIZE REMOTE_PATH = 4096       ; the longest path walked
CONST I32 REMOTE_LINKS = 40          ; links followed in one walk, then the real call may say ELOOP
CONST U64 REMOTE_LOOK_MS = 1000      ; how often the mounts are looked at
CONST USIZE REMOTE_OUT = 4096        ; what a probe may print
; the question: a statfs of the mount point, which is "$1"
CONST @CONST C1 REMOTE_PROBE = "stat -f -c %T -- %1"

; what a mount is, as asked
CONST I32 REMOTE_UP = 0
CONST I32 REMOTE_UNKNOWN = 1         ; a probe is out, and has not been for long
CONST I32 REMOTE_DOWN = 2

TYPE Remote: STRUCT
 | String path              ; the mount point
 | Job probe                ; the question, while it is out: `live`
 | B1 up                    ; it answered, the last time one came back
 | U64 ok_at                ; now_ms of that answer
 | U64 tried_at             ; now_ms the last probe was started
 | U64 asked_at             ; now_ms something last asked about the mount
 | B1 waited                ; a call has waited for this probe already
 \_

LOCAL Vector<Remote> remotes
LOCAL Vector<Job> strays     ; probes of mounts that are gone, still out
LOCAL U64 remotes_sig       ; mounts_signature when they were read
LOCAL U64 remotes_look      ; now_ms they were last looked at
LOCAL B1 remotes_read

; a mount that is gone from the list: freed, but a probe still out is left
; be -- killing a process stuck in the kernel would only hold the caller --
; and kept in `strays`, to be taken in when it ends
LOCAL ABYSS remote_free: [ @Remote r ]
 | (r.path.deinit)[]
 | IF [ !(r.probe.live) ]
 |  | (r.probe.out.deinit)[]
 | ELSE
 |  | (strays.push)[ r.probe ]
 |  \_
 \_

; the remote mounts, read again when the mounts changed; the state of one
; that stays is kept
LOCAL ABYSS remote_sync: []
 | U64 now = (now_ms)[]
 | IF [ remotes_read && now - remotes_look < REMOTE_LOOK_MS ]
 |  | RET []
 |  \_
 | remotes_look = now
 | U64 sig = (mounts_signature)[]
 | IF [ remotes_read && sig == remotes_sig ]
 |  | RET []
 |  \_
 | remotes_read = TRUE
 | remotes_sig = sig
 | Vector<Mount> ms
 | POSTLUDE (mounts_free)[ @ms ]
 | (read_mounts)[ @ms ]
 | Vector<Remote> fresh
 | FOR [ USIZE i = 0 | i < (ms.size)[] | i += 1 ]
 |  | @Mount m = (ms.at)[ i ]
 |  | IF [ !(m.remote) ]
 |  |  | CONTINUE
 |  |  \_
 |  | Remote r
 |  | B1 kept = FALSE
 |  | FOR [ USIZE k = 0 | k < (remotes.size)[] | k += 1 ]
 |  |  | @Remote old = (remotes.at)[ k ]
 |  |  | IF [ !kept && (old.path.equals)[ (m.path.cstr)[] ] ]
 |  |  |  | r = ?old
 |  |  |  | ; its string is r's now: the old one is left empty
 |  |  |  | old.path = (String.of)[ "" ]
 |  |  |  | kept = TRUE
 |  |  |  \_
 |  |  \_
 |  | IF [ !kept ]
 |  |  | r.path = (String.of)[ (m.path.cstr)[] ]
 |  |  | r.probe.live = FALSE
 |  |  | r.probe.done = FALSE
 |  |  | r.probe.ok = FALSE
 |  |  | r.probe.out = (String.of)[ "" ]
 |  |  | r.probe.limit = REMOTE_OUT
 |  |  | r.up = TRUE
 |  |  | r.ok_at = 0
 |  |  | r.tried_at = 0
 |  |  | r.asked_at = 0
 |  |  | r.waited = FALSE
 |  |  \_
 |  | (fresh.push)[ r ]
 |  \_
 | FOR [ USIZE k = 0 | k < (remotes.size)[] | k += 1 ]
 |  | @Remote old = (remotes.at)[ k ]
 |  | IF [ (old.path.size)[] > 0 ]
 |  |  | (remote_free)[ old ]
 |  | ELSE
 |  |  | (old.path.deinit)[]
 |  |  \_
 |  \_
 | (remotes.deinit)[]
 | remotes = fresh
 \_

; its probe's answer taken in, if it has come
LOCAL ABYSS remote_pump: [ @Remote r ]
 | IF [ !(r.probe.live) ]
 |  | RET []
 |  \_
 | IF [ !((job_pump)[ @(r.probe) ]) ]
 |  | RET []
 |  \_
 | r.up = r.probe.ok
 | IF [ r.up ]
 |  | r.ok_at = (now_ms)[]
 |  \_
 \_

; the question asked, if it is not out already
LOCAL ABYSS remote_start: [ @Remote r ]
 | IF [ r.probe.live ]
 |  | RET []
 |  \_
 | r.tried_at = (now_ms)[]
 | r.waited = FALSE
 | (job_start)[ @(r.probe) | REMOTE_PROBE | (r.path.cstr)[] | REMOTE_OUT ]
 \_

; a probe that has been out for REMOTE_DEAD_MS makes its mount down; it is
; left running, to be taken in when it ends
LOCAL B1 remote_dead: [ @Remote r | U64 now ]
 | IF [ r.probe.live && now - r.tried_at >= REMOTE_DEAD_MS ]
 |  | r.up = FALSE
 |  \_
 | RET [ !(r.up) ]
 \_

; what the mount `r` is. Not asked again within REMOTE_FRESH_MS of an answer;
; else a probe is started and waited for a little -- once, not at every call.
; One still out is "not known" until REMOTE_DEAD_MS. A mount that is down is
; not waited for: the answer of its probe, if it came, is all that is looked at
LOCAL I32 remote_check: [ @Remote r ]
 | (remote_pump)[ r ]
 | U64 now = (now_ms)[]
 | r.asked_at = now
 | IF [ r.up && now - r.ok_at < REMOTE_FRESH_MS ]
 |  | RET [ REMOTE_UP ]
 |  \_
 | IF [ !(r.probe.live) && (r.up || now - r.tried_at >= REMOTE_RETRY_MS) ]
 |  | (remote_start)[ r ]
 |  \_
 | IF [ !(r.up) ]
 |  | RET [ REMOTE_DOWN ]
 |  \_
 | IF [ !(r.probe.live) ]
 |  | ; it could not be started: nothing is known against the mount
 |  | RET [ REMOTE_UP ]
 |  \_
 | IF [ (remote_dead)[ r | now ] ]
 |  | RET [ REMOTE_DOWN ]
 |  \_
 | IF [ !(r.waited) ]
 |  | r.waited = TRUE
 |  | I32 fd = ((r.probe.p.output)[].fd_of)[]
 |  | U64 end = now + REMOTE_WAIT_MS
 |  | WHILE [ r.probe.live ]
 |  |  | U64 t = (now_ms)[]
 |  |  | IF [ t >= end ]
 |  |  |  | BREAK
 |  |  |  \_
 |  |  | PollFd pf = [ .fd = fd | .events = POLLIN ]
 |  |  | (poll)[ @pf | 1 | (end - t) AS I32 ]
 |  |  | (remote_pump)[ r ]
 |  |  \_
 |  \_
 | IF [ !(r.probe.live) ]
 |  | IF [ r.up ]
 |  |  | RET [ REMOTE_UP ]
 |  |  \_
 |  | RET [ REMOTE_DOWN ]
 |  \_
 | IF [ (remote_dead)[ r | (now_ms)[] ] ]
 |  | RET [ REMOTE_DOWN ]
 |  \_
 | RET [ REMOTE_UNKNOWN ]
 \_

; --- paths, by their names --------------------------------------------------------

; the folder `dir` and `name` as one path, `dir`/`name`, in `out`: / has no
; second /. Where `name` is a link, it is not looked at
ABYSS join_into: [ @C1 out | USIZE cap | @CONST C1 dir | @CONST C1 name ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | (b.print)[ "%s%s%s" | dir | SELECT [ (str_eq)[ dir | "/" ] | "" | "/" ] | name ]
 \_

; a step of a walk, by names alone: `path` (absolute; "" is the root) goes into
; the folder `comp`, `.` stays, `..` goes up (the root has no up). FALSE: it
; does not fit `cap`, and `path` is as it was
B1 path_step: [ @C1 path | USIZE cap | @CONST C1 comp ]
 | IF [ comp{0} == '\0' || (str_eq)[ comp | "." ] ]
 |  | RET [ TRUE ]
 |  \_
 | USIZE n = (str_len)[ path AS @CONST C1 ]
 | IF [ (str_eq)[ comp | ".." ] ]
 |  | WHILE [ n > 0 && path{n - 1} != '/' ]
 |  |  | n -= 1
 |  |  \_
 |  | IF [ n > 0 ]
 |  |  | n -= 1
 |  |  \_
 |  | path{n} = '\0'
 |  | RET [ TRUE ]
 |  \_
 | IF [ n + 1 + (str_len)[ comp ] + 1 > cap ]
 |  | RET [ FALSE ]
 |  \_
 | path{n} = '/'
 | (str_copy)[ path + n + 1 | cap - n - 1 | comp ]
 | RET [ TRUE ]
 \_

; --- what a path is ---------------------------------------------------------------

; what the remote mounts that hold `path` are, by its name: the worst of them,
; and its mount point in `out` (cap bytes; `out` may be NULL). Each is asked
; as remote_check says. A link is not followed: see remote_state_deep
I32 remote_state: [ @CONST C1 path | @C1 out | USIZE cap ]
 | (remote_sync)[]
 | I32 worst = REMOTE_UP
 | FOR [ USIZE i = 0 | i < (remotes.size)[] | i += 1 ]
 |  | @Remote r = (remotes.at)[ i ]
 |  | IF [ (is_under)[ path | (r.path.cstr)[] ] ]
 |  |  | I32 s = (remote_check)[ r ]
 |  |  | IF [ s > worst ]
 |  |  |  | worst = s
 |  |  |  | IF [ out != NULL && cap > 0 ]
 |  |  |  |  | (str_copy)[ out | cap | (r.path.cstr)[] ]
 |  |  |  |  \_
 |  |  |  \_
 |  |  \_
 |  \_
 | RET [ worst ]
 \_

; the same, with every link on the way to `path` followed -- by lstat and
; readlink, each step made only where the mount under it answers, so that
; nothing hangs on a link into a dead mount. A relative path starts at the
; working folder, which the kernel knows. A path that is not there, or too
; long, or past REMOTE_LINKS links, is up: the real call says why not
I32 remote_state_deep: [ @CONST C1 path | @C1 out | USIZE cap ]
 | (remote_sync)[]
 | IF [ (remotes.size)[] == 0 || (str_len)[ path ] >= REMOTE_PATH ]
 |  | RET [ REMOTE_UP ]
 |  \_
 | C1 rest{REMOTE_PATH}       ; what is left to walk
 | C1 prefix{REMOTE_PATH}     ; where it is: no links in it
 | C1 cand{REMOTE_PATH}
 | C1 target{REMOTE_PATH}
 | prefix{0} = '\0'
 | IF [ path{0} != '/' ]
 |  | IF [ ((fs_cwd)[ prefix | REMOTE_PATH ].is_err)[] ]
 |  |  | RET [ REMOTE_UP ]
 |  |  \_
 |  | IF [ (str_eq)[ prefix AS @CONST C1 | "/" ] ]
 |  |  | prefix{0} = '\0'
 |  |  \_
 |  | I32 s = (remote_state)[ prefix AS @CONST C1 | out | cap ]
 |  | IF [ s != REMOTE_UP ]
 |  |  | RET [ s ]
 |  |  \_
 |  \_
 | (str_copy)[ rest | REMOTE_PATH | path ]
 | USIZE pos = 0
 | I32 links = 0
 | LOOP
 |  | WHILE [ rest{pos} == '/' ]
 |  |  | pos += 1
 |  |  \_
 |  | IF [ rest{pos} == '\0' ]
 |  |  | BREAK
 |  |  \_
 |  | C1 comp{256}
 |  | USIZE n = 0
 |  | WHILE [ rest{pos} != '/' && rest{pos} != '\0' ]
 |  |  | IF [ n + 1 >= 256 ]
 |  |  |  | RET [ REMOTE_UP ]
 |  |  |  \_
 |  |  | comp{n} = rest{pos}
 |  |  | n += 1
 |  |  | pos += 1
 |  |  \_
 |  | comp{n} = '\0'
 |  | IF [ (str_eq)[ comp AS @CONST C1 | "." ] || (str_eq)[ comp AS @CONST C1 | ".." ] ]
 |  |  | (path_step)[ prefix | REMOTE_PATH | comp AS @CONST C1 ]
 |  |  | CONTINUE
 |  |  \_
 |  | (str_copy)[ cand | REMOTE_PATH | prefix AS @CONST C1 ]
 |  | IF [ !((path_step)[ cand | REMOTE_PATH | comp AS @CONST C1 ]) ]
 |  |  | RET [ REMOTE_UP ]
 |  |  \_
 |  | I32 s = (remote_state)[ cand AS @CONST C1 | out | cap ]
 |  | IF [ s != REMOTE_UP ]
 |  |  | RET [ s ]
 |  |  \_
 |  | Stat st
 |  | IF [ !((px_stat_of)[ cand AS @CONST C1 | @st ]) ]
 |  |  | RET [ REMOTE_UP ]
 |  |  \_
 |  | IF [ (st.mode & 0xF000) != 0xA000 ]
 |  |  | (str_copy)[ prefix | REMOTE_PATH | cand AS @CONST C1 ]
 |  |  | CONTINUE
 |  |  \_
 |  | ; a link: its target put in front of what is left
 |  | links += 1
 |  | ISIZE got = (px_readlink)[ cand AS @CONST C1 | target | REMOTE_PATH - 1 ]
 |  | IF [ links > REMOTE_LINKS || got <= 0 ]
 |  |  | RET [ REMOTE_UP ]
 |  |  \_
 |  | USIZE tl = got AS USIZE
 |  | target{tl} = '\0'
 |  | USIZE rl = (str_len)[ (rest + pos) AS @CONST C1 ]
 |  | IF [ tl + 1 + rl + 1 > REMOTE_PATH ]
 |  |  | RET [ REMOTE_UP ]
 |  |  \_
 |  | (join_into)[ cand | REMOTE_PATH | target AS @CONST C1 | (rest + pos) AS @CONST C1 ]
 |  | (str_copy)[ rest | REMOTE_PATH | cand AS @CONST C1 ]
 |  | pos = 0
 |  | IF [ target{0} == '/' ]
 |  |  | prefix{0} = '\0'
 |  |  \_
 |  \_
 | RET [ REMOTE_UP ]
 \_

; may a call be made on `path`? Anything not on a remote mount: yes at once,
; by its name alone. On one: only if it is up -- not while it is not known
B1 remote_ok: [ @CONST C1 path ]
 | RET [ (remote_state)[ path | NULL | 0 ] == REMOTE_UP ]
 \_

; the same where `path` may be a link, or lead through one
B1 remote_ok_deep: [ @CONST C1 path ]
 | RET [ (remote_state_deep)[ path | NULL | 0 ] == REMOTE_UP ]
 \_

; the mount point of the remote that is DOWN (declared) and holds `path`, in
; `out` (cap bytes); FALSE: none is
B1 remote_mount: [ @CONST C1 path | @C1 out | USIZE cap ]
 | RET [ (remote_state)[ path | out | cap ] == REMOTE_DOWN ]
 \_

; the mount at `path` as last known, nothing asked: for the places row. A
; mount not known is up
B1 remote_up: [ @CONST C1 path ]
 | FOR [ USIZE i = 0 | i < (remotes.size)[] | i += 1 ]
 |  | @Remote r = (remotes.at)[ i ]
 |  | IF [ (r.path.equals)[ path ] ]
 |  |  | RET [ r.up ]
 |  |  \_
 |  \_
 | RET [ TRUE ]
 \_

; once a frame: the mounts looked at, the probes that are out taken in (those
; of mounts that are gone too), and a probe started where it is wanted: for a
; mount that is down, once a second; for one that was asked about lately, one
; second after its last answer, so the next one is there before the last goes
; stale. An idle mount is not asked at all
ABYSS remote_tick: []
 | (remote_sync)[]
 | U64 now = (now_ms)[]
 | FOR [ USIZE i = 0 | i < (remotes.size)[] | i += 1 ]
 |  | @Remote r = (remotes.at)[ i ]
 |  | (remote_pump)[ r ]
 |  | (remote_dead)[ r | now ]
 |  | IF [ !(r.probe.live) ]
 |  |  | IF [ !(r.up) ]
 |  |  |  | IF [ now - r.tried_at >= REMOTE_RETRY_MS ]
 |  |  |  |  | (remote_start)[ r ]
 |  |  |  |  \_
 |  |  |  | CONTINUE
 |  |  |  \_
 |  |  | IF [ r.asked_at != 0 && now - r.asked_at < REMOTE_ASKED_MS && now - r.ok_at >= REMOTE_AHEAD_MS ]
 |  |  |  | (remote_start)[ r ]
 |  |  |  \_
 |  |  \_
 |  \_
 | ; a stray that ended is waited for, and let go; one that runs is left be
 | USIZE s = 0
 | WHILE [ s < (strays.size)[] ]
 |  | @Job j = (strays.at)[ s ]
 |  | IF [ (job_pump)[ j ] ]
 |  |  | (j.out.deinit)[]
 |  |  | (strays.remove)[ s ]
 |  | ELSE
 |  |  | s += 1
 |  |  \_
 |  \_
 \_
