; tasks.pl -- what runs beside the frames: copying, moving, deleting. A task
; is a stack of steps, the next one last; each frame works on the tasks for
; a slice of time and asks to be woken again, so the program keeps
; answering keys while a big folder is copied. Nothing is overwritten: a
; name that is taken gets " (2)", and a file is made only if it is not there

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

!USES <fs.pl>

CONST U64 TASK_SLICE_MS = 12    ; the work done in one frame, at most
CONST U64 TASK_KEEP_MS = 3000   ; a task that ended is shown this long
CONST U64 TASK_ERR_MS = 12000   ; one that failed, this long
CONST U64 ENTRY_WEIGHT = 4096   ; a folder or a link counts as this many bytes
CONST USIZE COPY_CHUNK = 1048576
CONST I32 EXDEV = 18            ; rename: not on one file system
CONST I32 E_INTR = 4            ; a call a signal broke off: made again
CONST I32 AT_FDCWD = -100
CONST ISIZE UTIME_OMIT = 1073741822     ; utimensat: this time left as it is

; Linux's numbers, as std's File has them
CONST I32 O_READ = 0x80000                  ; O_RDONLY | O_CLOEXEC
CONST I32 O_MAKE = 0x800C1                  ; O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC

LOCAL U8 copy_buf{COPY_CHUNK}

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
CONST I32 CLASH_KEEP = 0        ; keep both: the new one as "name (2)"
CONST I32 CLASH_SKIP = 1        ; leave that one out
CONST I32 CLASH_OVER = 2        ; overwrite: a file replaced, a folder merged into

TYPE TaskKind: ENUM
 | TK_COPY
 | TK_MOVE
 | TK_DELETE
 \_

TYPE StepKind: ENUM
 | SK_COPY          ; src to dst: a file, a link, a folder and all in it
 | SK_MOVE          ; src to dst, renamed; across disks a copy, then SK_DROP
 | SK_DELETE        ; src and all in it
 | SK_RMDIR         ; src, a folder the steps before emptied
 | SK_DROP          ; src, once copied: deleted only if nothing failed
 | SK_WEIGH         ; src counted into the total, a folder by its entries in
 |                  ;   turn: no walk of a whole tree in one frame
 | SK_SEAL          ; src, a folder copied: its own mode and time at last
 \_

TYPE Step: STRUCT
 | StepKind kind
 | String src
 | String dst
 | U64 weight       ; SK_MOVE: what it counts for; SK_DROP: the failures
 |                  ;   before; SK_WEIGH: 1 to count entries, 0 bytes
 | U32 mode         ; SK_SEAL: the mode and the time to give src
 | I64 sec
 | U32 nsec
 \_

TYPE Task: STRUCT
 | TaskKind kind
 | String title             ; copy 3 → ~/work
 | Vector<Step> steps       ; what is left, the next last
 | I32 in                   ; a file being copied: its two ends; -1: none
 | I32 out
 | String target            ; the file `out` writes, taken away if it fails
 | String now               ; the name being worked on
 | U64 total                ; bytes, entries as ENTRY_WEIGHT; a delete: entries
 | U64 done
 | I32 failed               ; steps that could not be done
 | String error             ; the first of them: what and why
 | U64 ended                ; now_ms when it ended; 0: it runs
 | B1 counting              ; the steps now are SK_WEIGH: no share done yet
 | I64 src_sec              ; the file being copied: its time and mode, for
 | U32 src_nsec             ;   the copy once it is whole
 | U32 src_mode
 | B1 over                  ; a name taken is overwritten, not a failure
 | String replace           ; the file `target` is written aside for: renamed
 |                          ;   over it once whole; empty: none
 \_

; --- paths ----------------------------------------------------------------------

B1 taken: [ @CONST C1 path ]
 | RET [ ((fs_link_info)[ path ].is_ok)[] ]
 \_

; `name` in `dir`, or if that is taken "name (2)", "name (3)": before the
; extension, as "notes (2).txt"
String free_name: [ @CONST C1 dir | @CONST C1 name ]
 | String first = (join_path)[ dir | name ]
 | IF [ !((taken)[ (first.cstr)[] ]) ]
 |  | RET [ first ]
 |  \_
 | (first.deinit)[]
 |
 | USIZE n = (str_len)[ name ]
 | USIZE dot = n
 | FOR [ USIZE i = 1 | i < n | i += 1 ]
 |  | IF [ name{i} == '.' ]
 |  |  | dot = i
 |  |  \_
 |  \_
 | C1 stem{256}
 | (str_copy)[ stem | SELECT [ dot + 1 < 256 | dot + 1 | 256 ] | name ]
 | FOR [ I32 k = 2 | k < 10000 | k += 1 ]
 |  | C1 alt{512}
 |  | BufferSink b = (BufferSink.over)[ alt | 512 ]
 |  | (b.print)[ "%s (%d)%s" | stem AS @CONST C1 | k | name + dot ]
 |  | String p = (join_path)[ dir | alt AS @CONST C1 ]
 |  | IF [ !((taken)[ (p.cstr)[] ]) ]
 |  |  | RET [ p ]
 |  |  \_
 |  | (p.deinit)[]
 |  \_
 | RET [ (join_path)[ dir | name ] ]
 \_

; --- a task ---------------------------------------------------------------------

ABYSS step_push: [ @Task t | StepKind k | @CONST C1 src | @CONST C1 dst | U64 weight ]
 | Step s
 | s.kind = k
 | s.src = (String.of)[ src ]
 | s.dst = (String.of)[ dst ]
 | s.weight = weight
 | (t.steps.push)[ s ]
 \_

ABYSS step_free: [ @Step s ]
 | (s.src.deinit)[]
 | (s.dst.deinit)[]
 \_

Task task_new: [ TaskKind k ]
 | Task t
 | t.kind = k
 | t.title = (String.of)[ "" ]
 | t.target = (String.of)[ "" ]
 | t.now = (String.of)[ "" ]
 | t.error = (String.of)[ "" ]
 | t.replace = (String.of)[ "" ]
 | t.in = -1
 | t.out = -1
 | RET [ t ]
 \_

ABYSS task_free: [ @Task t ]
 | IF [ t.in >= 0 ]
 |  | (px_close)[ t.in ]
 |  | (px_close)[ t.out ]
 |  \_
 | FOR [ USIZE i = 0 | i < (t.steps.size)[] | i += 1 ]
 |  | (step_free)[ (t.steps.at)[ i ] ]
 |  \_
 | (t.steps.deinit)[]
 | (t.title.deinit)[]
 | (t.target.deinit)[]
 | (t.now.deinit)[]
 | (t.error.deinit)[]
 | (t.replace.deinit)[]
 \_

ABYSS task_title: [ @Task t | @CONST C1 verb | USIZE n | @CONST C1 one | @CONST C1 into ]
 | C1 s{512}
 | BufferSink b = (BufferSink.over)[ s | 512 ]
 | IF [ n == 1 ]
 |  | String name = (get_dirname)[ one ]
 |  | (b.print)[ "%s %s" | verb | (name.cstr)[] ]
 |  | (name.deinit)[]
 | ELSE
 |  | (b.print)[ "%s %d items" | verb | n AS I32 ]
 |  \_
 | IF [ into != NULL ]
 |  | String short = (get_shorter_path)[ into ]
 |  | (b.print)[ " → %s" | (short.cstr)[] ]
 |  | (short.deinit)[]
 |  \_
 | (t.title.deinit)[]
 | t.title = (String.of)[ s AS @CONST C1 ]
 \_

; `paths` copied, or moved, into the folder `into`; a name taken there as
; `clash` says. A path moved to where it is already is left as it is;
; copied there, it is copied as "name (2)"
Task task_transfer: [ B1 move | @Vector<String> paths | @CONST C1 into | I32 clash ]
 | Task t = (task_new)[ SELECT [ move | TK_MOVE | TK_COPY ] ]
 | t.over = clash == CLASH_OVER
 | USIZE n = (paths.size)[]
 | @CONST C1 one = ""
 | IF [ n > 0 ]
 |  | one = ((paths.at)[ 0 ].cstr)[]
 |  \_
 | (task_title)[ @t | SELECT [ move | "move" | "copy" ] | n | one | into ]
 | ; pushed from the last, so the first goes first
 | FOR [ USIZE k = n | k > 0 | k -= 1 ]
 |  | @CONST C1 src = ((paths.at)[ k - 1 ].cstr)[]
 |  | String up = (get_parent_path)[ src ]
 |  | B1 here = (up.equals)[ into ]
 |  | (up.deinit)[]
 |  | IF [ move && here ]
 |  |  | CONTINUE
 |  |  \_
 |  | String name = (get_dirname)[ src ]
 |  | ; a name taken here: as `clash` says -- but a copy into its own
 |  | ; folder is always kept beside the original
 |  | String dst = (join_path)[ into | (name.cstr)[] ]
 |  | IF [ (taken)[ (dst.cstr)[] ] && (here || clash == CLASH_KEEP) ]
 |  |  | (dst.deinit)[]
 |  |  | dst = (free_name)[ into | (name.cstr)[] ]
 |  | ELIF [ (taken)[ (dst.cstr)[] ] && clash == CLASH_SKIP ]
 |  |  | (name.deinit)[]
 |  |  | (dst.deinit)[]
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ move ]
 |  |  | ; a rename, as a rule: one unit, and no walk of what it holds
 |  |  | (step_push)[ @t | SK_MOVE | src | (dst.cstr)[] | ENTRY_WEIGHT ]
 |  |  | t.total += ENTRY_WEIGHT
 |  | ELSE
 |  |  | (step_push)[ @t | SK_COPY | src | (dst.cstr)[] | 0 ]
 |  |  \_
 |  | (name.deinit)[]
 |  | (dst.deinit)[]
 |  \_
 | ; what is copied weighed first, a step at a time, on top of the stack
 | IF [ !move ]
 |  | FOR [ USIZE k = 0 | k < n | k += 1 ]
 |  |  | (step_push)[ @t | SK_WEIGH | ((paths.at)[ k ].cstr)[] | "" | 0 ]
 |  |  \_
 |  \_
 | RET [ t ]
 \_

; `paths` deleted, and all in them: for good, not to a trash
Task task_delete: [ @Vector<String> paths ]
 | Task t = (task_new)[ TK_DELETE ]
 | USIZE n = (paths.size)[]
 | @CONST C1 one = ""
 | IF [ n > 0 ]
 |  | one = ((paths.at)[ 0 ].cstr)[]
 |  \_
 | (task_title)[ @t | "delete" | n | one | NULL ]
 | FOR [ USIZE k = n | k > 0 | k -= 1 ]
 |  | @CONST C1 src = ((paths.at)[ k - 1 ].cstr)[]
 |  | (step_push)[ @t | SK_DELETE | src | "" | 0 ]
 |  \_
 | FOR [ USIZE k = 0 | k < n | k += 1 ]
 |  | (step_push)[ @t | SK_WEIGH | ((paths.at)[ k ].cstr)[] | "" | 1 ]
 |  \_
 | RET [ t ]
 \_

; --- doing it -------------------------------------------------------------------

ABYSS task_fail: [ @Task t | @CONST C1 path | @CONST C1 why ]
 | t.failed += 1
 | IF [ (t.error.size)[] == 0 ]
 |  | String short = (get_shorter_path)[ path ]
 |  | C1 s{600}
 |  | BufferSink b = (BufferSink.over)[ s | 600 ]
 |  | (b.print)[ "%s: %s" | (short.cstr)[] | why ]
 |  | (short.deinit)[]
 |  | (t.error.deinit)[]
 |  | t.error = (String.of)[ s AS @CONST C1 ]
 |  \_
 \_

ABYSS task_fail_io: [ @Task t | @CONST C1 path | IoError e ]
 | (task_fail)[ t | path | (io_error_text)[ e ] ]
 \_

; the errno of the call that just failed, as a reason
LOCAL @CONST C1 errno_text: []
 | RET [ (io_error_text)[ (io_error_of)[ (io_errno)[] ] ] ]
 \_

ABYSS task_now: [ @Task t | @CONST C1 path ]
 | (t.now.deinit)[]
 | t.now = (get_dirname)[ path ]
 \_

; the file being copied, closed; what was written of it taken away if `bad`
ABYSS copy_end: [ @Task t | B1 bad ]
 | (px_close)[ t.in ]
 | (px_close)[ t.out ]
 | t.in = -1
 | t.out = -1
 | IF [ bad ]
 |  | (fs_remove)[ (t.target.cstr)[] ]
 |  | RET []
 |  \_
 | (px_chmod)[ (t.target.cstr)[] | t.src_mode ]
 | (set_time)[ (t.target.cstr)[] | t.src_sec | t.src_nsec ]
 | ; written aside of a file it overwrites: over it now, in one rename
 | IF [ (t.replace.size)[] > 0 ]
 |  | Result<B1 | IoError> r = (fs_rename)[ (t.target.cstr)[] | (t.replace.cstr)[] ]
 |  | IF [ (r.is_err)[] ]
 |  |  | (task_fail_io)[ t | (t.replace.cstr)[] | (r.error)[] ]
 |  |  | (fs_remove)[ (t.target.cstr)[] ]
 |  |  \_
 |  | (t.replace.deinit)[]
 |  | t.replace = (String.of)[ "" ]
 |  \_
 \_

; a chunk of the file being copied; a call a signal broke off is made again
ABYSS copy_chunk: [ @Task t ]
 | ISIZE n = (px_read)[ t.in | copy_buf AS @ABYSS | COPY_CHUNK ]
 | WHILE [ n < 0 && (io_errno)[] == E_INTR ]
 |  | n = (px_read)[ t.in | copy_buf AS @ABYSS | COPY_CHUNK ]
 |  \_
 | IF [ n < 0 ]
 |  | (task_fail)[ t | (t.target.cstr)[] | (errno_text)[] ]
 |  | (copy_end)[ t | TRUE ]
 |  | RET []
 |  \_
 | IF [ n == 0 ]
 |  | (copy_end)[ t | FALSE ]
 |  | RET []
 |  \_
 | USIZE put = 0
 | WHILE [ put < (n AS USIZE) ]
 |  | ISIZE w = (px_write)[ t.out | (copy_buf + put) AS @CONST ABYSS | (n AS USIZE) - put ]
 |  | IF [ w < 0 && (io_errno)[] == E_INTR ]
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ w <= 0 ]
 |  |  | ; nothing written, and no error said: the disk is full
 |  |  | (task_fail)[ t | (t.target.cstr)[] | SELECT [ w < 0 | (errno_text)[] | (io_error_text)[ IO_NO_SPACE ] ] ]
 |  |  | (copy_end)[ t | TRUE ]
 |  |  | RET []
 |  |  \_
 |  | put += w AS USIZE
 |  \_
 | t.done += n AS U64
 \_

; the entries of the folder `src`, each a step of `k` from it to the same
; name in `dst`
ABYSS push_children: [ @Task t | StepKind k | @CONST C1 src | @CONST C1 dst | U64 weight ]
 | Result<os:Dir | IoError> d = (os:Dir.open)[ src ]
 | IF [ (d.is_err)[] ]
 |  | (task_fail_io)[ t | src | (d.error)[] ]
 |  | RET []
 |  \_
 | os:Dir dir = (d.unwrap)[]
 | POSTLUDE (dir.close)[]
 | DirEntry e
 | WHILE [ (dir.next)[ @e ] ]
 |  | String a = (join_path)[ src | e.name AS @CONST C1 ]
 |  | String b = (String.of)[ "" ]
 |  | IF [ k == SK_COPY ]
 |  |  | (b.deinit)[]
 |  |  | b = (join_path)[ dst | e.name AS @CONST C1 ]
 |  |  \_
 |  | (step_push)[ t | k | (a.cstr)[] | (b.cstr)[] | weight ]
 |  | (a.deinit)[]
 |  | (b.deinit)[]
 |  \_
 \_

; `path` given the modification time sec.nsec, its access time left
LOCAL ABYSS set_time: [ @CONST C1 path | I64 sec | U32 nsec ]
 | Timespec ts{2}
 | ts{0}.sec = 0
 | ts{0}.nsec = UTIME_OMIT
 | ts{1}.sec = sec AS ISIZE
 | ts{1}.nsec = nsec AS ISIZE
 | (px_utimensat)[ AT_FDCWD | path | ts AS @CONST Timespec | 0 ]
 \_

; `src` into the total: a copy counts its bytes and ENTRY_WEIGHT an entry,
; a delete (`entries`) 1 an entry; a folder's entries weighed after it
ABYSS do_weigh: [ @Task t | @CONST C1 src | B1 entries ]
 | (task_now)[ t | src ]
 | Result<FileInfo | IoError> r = (fs_link_info)[ src ]
 | IF [ (r.is_err)[] ]
 |  | RET []
 |  \_
 | FileInfo i = (r.unwrap)[]
 | t.total += SELECT [ entries | 1 | ENTRY_WEIGHT ]
 | IF [ i.kind == FS_FILE && !entries ]
 |  | t.total += i.size
 |  \_
 | IF [ i.kind == FS_DIR ]
 |  | (push_children)[ t | SK_WEIGH | src | "" | SELECT [ entries | 1 | 0 ] ]
 |  \_
 \_

ABYSS do_copy: [ @Task t | @CONST C1 src | @CONST C1 dst ]
 | (task_now)[ t | src ]
 | Result<FileInfo | IoError> r = (fs_link_info)[ src ]
 | IF [ (r.is_err)[] ]
 |  | (task_fail_io)[ t | src | (r.error)[] ]
 |  | RET []
 |  \_
 | FileInfo i = (r.unwrap)[]
 |
 | ; there already: overwritten only if the paste said so -- a folder merged
 | ; into its namesake; a file or a link written aside, and renamed over it
 | ; only once it is whole, so a copy that fails leaves the old one be
 | @CONST C1 put = dst
 | String aside = (String.of)[ "" ]
 | POSTLUDE (aside.deinit)[]
 | B1 merge = FALSE
 | Result<FileInfo | IoError> there = (fs_link_info)[ dst ]
 | IF [ (there.is_ok)[] ]
 |  | IF [ !(t.over) ]
 |  |  | (task_fail)[ t | dst | "there already" ]
 |  |  | RET []
 |  |  \_
 |  | B1 was_dir = (there.unwrap)[].kind == FS_DIR
 |  | IF [ was_dir != (i.kind == FS_DIR) ]
 |  |  | (task_fail)[ t | dst | "a file and a folder have this name" ]
 |  |  | RET []
 |  |  \_
 |  | merge = was_dir
 |  | IF [ !merge ]
 |  |  | String up = (get_parent_path)[ dst ]
 |  |  | String part = (get_dirname)[ dst ]
 |  |  | (part.append)[ ".pluf-part" ]
 |  |  | (aside.deinit)[]
 |  |  | aside = (free_name)[ (up.cstr)[] | (part.cstr)[] ]
 |  |  | (up.deinit)[]
 |  |  | (part.deinit)[]
 |  |  | put = (aside.cstr)[]
 |  |  \_
 |  \_
 |
 | IF [ i.kind == FS_LINK ]
 |  | C1 to{4096}
 |  | ISIZE n = (px_readlink)[ src | to | 4095 ]
 |  | IF [ n < 0 ]
 |  |  | (task_fail)[ t | src | (errno_text)[] ]
 |  |  | RET []
 |  |  \_
 |  | to{n} = '\0'
 |  | IF [ (px_symlink)[ to AS @CONST C1 | put ] != 0 ]
 |  |  | (task_fail)[ t | dst | (errno_text)[] ]
 |  |  | RET []
 |  |  \_
 |  | IF [ (aside.size)[] > 0 && ((fs_rename)[ put | dst ].is_err)[] ]
 |  |  | (task_fail)[ t | dst | (errno_text)[] ]
 |  |  | (fs_remove)[ put ]
 |  |  \_
 |  | t.done += ENTRY_WEIGHT
 |  | RET []
 |  \_
 |
 | IF [ i.kind == FS_DIR ]
 |  | IF [ (is_under)[ dst | src ] ]
 |  |  | (task_fail)[ t | src | "a folder cannot go into itself" ]
 |  |  | RET []
 |  |  \_
 |  | IF [ !merge ]
 |  |  | Result<B1 | IoError> m = (fs_make_dir)[ dst ]
 |  |  | IF [ (m.is_err)[] ]
 |  |  |  | (task_fail_io)[ t | dst | (m.error)[] ]
 |  |  |  | RET []
 |  |  |  \_
 |  |  \_
 |  | ; writable while its entries go in; its own mode and time after them
 |  | (px_chmod)[ dst | ((i.mode & 0xFFF) | 0x1C0) ]
 |  | (step_push)[ t | SK_SEAL | dst | "" | 0 ]
 |  | @Step seal = (t.steps.at)[ (t.steps.size)[] - 1 ]
 |  | seal.mode = i.mode & 0xFFF
 |  | seal.sec = i.modified
 |  | seal.nsec = i.modified_ns
 |  | t.done += ENTRY_WEIGHT
 |  | (push_children)[ t | SK_COPY | src | dst | 0 ]
 |  | RET []
 |  \_
 |
 | IF [ i.kind != FS_FILE ]
 |  | (task_fail)[ t | src | "not a file, a folder or a link" ]
 |  | RET []
 |  \_
 | I32 fin = (px_open)[ src | O_READ ]
 | IF [ fin < 0 ]
 |  | (task_fail)[ t | src | (errno_text)[] ]
 |  | RET []
 |  \_
 | I32 fout = (px_open)[ put | O_MAKE | ((i.mode & 0xFFF) | 0x180) ]
 | IF [ fout < 0 ]
 |  | (task_fail)[ t | put | (errno_text)[] ]
 |  | (px_close)[ fin ]
 |  | RET []
 |  \_
 | t.in = fin
 | t.out = fout
 | t.src_sec = i.modified
 | t.src_nsec = i.modified_ns
 | t.src_mode = i.mode & 0xFFF
 | (t.target.deinit)[]
 | t.target = (String.of)[ put ]
 | (t.replace.deinit)[]
 | t.replace = (String.of)[ SELECT [ (aside.size)[] > 0 | dst | "" ] ]
 | t.done += ENTRY_WEIGHT
 \_

ABYSS do_move: [ @Task t | @CONST C1 src | @CONST C1 dst | U64 weight ]
 | (task_now)[ t | src ]
 | IF [ (is_under)[ dst | src ] ]
 |  | (task_fail)[ t | src | "a folder cannot go into itself" ]
 |  | RET []
 |  \_
 | ; there already, and to be overwritten: a file renamed over it, as a
 | ; rename does; a folder copied into it, merged, and then taken away
 | Result<FileInfo | IoError> there = (fs_link_info)[ dst ]
 | IF [ (there.is_ok)[] ]
 |  | IF [ !(t.over) ]
 |  |  | (task_fail)[ t | dst | "there already" ]
 |  |  | RET []
 |  |  \_
 |  | Result<FileInfo | IoError> me = (fs_link_info)[ src ]
 |  | IF [ (me.is_err)[] ]
 |  |  | (task_fail_io)[ t | src | (me.error)[] ]
 |  |  | RET []
 |  |  \_
 |  | B1 was_dir = (there.unwrap)[].kind == FS_DIR
 |  | IF [ was_dir != ((me.unwrap)[].kind == FS_DIR) ]
 |  |  | (task_fail)[ t | dst | "a file and a folder have this name" ]
 |  |  | RET []
 |  |  \_
 |  | IF [ was_dir ]
 |  |  | t.done += weight
 |  |  | I32 was = t.failed
 |  |  | (step_push)[ t | SK_DROP | src | "" | was AS U64 ]
 |  |  | (step_push)[ t | SK_COPY | src | dst | 0 ]
 |  |  | (step_push)[ t | SK_WEIGH | src | "" | 0 ]
 |  |  | RET []
 |  |  \_
 |  \_
 | Result<B1 | IoError> r = (fs_rename)[ src | dst ]
 | IF [ (r.is_ok)[] ]
 |  | t.done += weight
 |  | RET []
 |  \_
 | IF [ (io_errno)[] != EXDEV ]
 |  | (task_fail_io)[ t | src | (r.error)[] ]
 |  | RET []
 |  \_
 | ; another disk: a copy, and then, if it all went, the original away
 | t.done += weight
 | I32 before = t.failed
 | (step_push)[ t | SK_DROP | src | "" | before AS U64 ]
 | (step_push)[ t | SK_COPY | src | dst | 0 ]
 | (step_push)[ t | SK_WEIGH | src | "" | 0 ]
 \_

ABYSS do_delete: [ @Task t | @CONST C1 src ]
 | (task_now)[ t | src ]
 | Result<FileInfo | IoError> r = (fs_link_info)[ src ]
 | IF [ (r.is_err)[] ]
 |  | (task_fail_io)[ t | src | (r.error)[] ]
 |  | RET []
 |  \_
 | IF [ (r.unwrap)[].kind == FS_DIR ]
 |  | (step_push)[ t | SK_RMDIR | src | "" | 0 ]
 |  | (push_children)[ t | SK_DELETE | src | "" | 0 ]
 |  | RET []
 |  \_
 | Result<B1 | IoError> g = (fs_remove)[ src ]
 | IF [ (g.is_err)[] ]
 |  | (task_fail_io)[ t | src | (g.error)[] ]
 |  | RET []
 |  \_
 | IF [ t.kind == TK_DELETE ]
 |  | t.done += 1
 |  \_
 \_

; the next step, or the next chunk of the file being copied
ABYSS task_step: [ @Task t ]
 | IF [ t.in >= 0 ]
 |  | (copy_chunk)[ t ]
 |  | RET []
 |  \_
 | Step s
 | IF [ !((t.steps.pop)[ @s ]) ]
 |  | RET []
 |  \_
 | POSTLUDE (step_free)[ @s ]
 | @CONST C1 src = (s.src.cstr)[]
 | t.counting = s.kind == SK_WEIGH
 | IF [ s.kind == SK_WEIGH ]
 |  | (do_weigh)[ t | src | s.weight == 1 ]
 | ELIF [ s.kind == SK_SEAL ]
 |  | (px_chmod)[ src | s.mode ]
 |  | (set_time)[ src | s.sec | s.nsec ]
 | ELIF [ s.kind == SK_COPY ]
 |  | (do_copy)[ t | src | (s.dst.cstr)[] ]
 | ELIF [ s.kind == SK_MOVE ]
 |  | (do_move)[ t | src | (s.dst.cstr)[] | s.weight ]
 | ELIF [ s.kind == SK_DELETE ]
 |  | (do_delete)[ t | src ]
 | ELIF [ s.kind == SK_RMDIR ]
 |  | Result<B1 | IoError> g = (fs_remove_dir)[ src ]
 |  | IF [ (g.is_err)[] ]
 |  |  | (task_fail_io)[ t | src | (g.error)[] ]
 |  |  \_
 |  | IF [ t.kind == TK_DELETE ]
 |  |  | t.done += 1
 |  |  \_
 | ELIF [ s.kind == SK_DROP ]
 |  | ; `weight`: how many had failed before its copy began
 |  | IF [ (t.failed AS U64) == s.weight ]
 |  |  | (step_push)[ t | SK_DELETE | src | "" | 0 ]
 |  |  \_
 |  \_
 \_

B1 task_running: [ @CONST Task t ]
 | RET [ t.ended == 0 ]
 \_

; every task worked on for a slice of time; those that ended long enough
; ago taken off. TRUE: something on the disk changed
B1 tasks_run: [ @Vector<Task> ts ]
 | U64 start = (now_ms)[]
 | B1 changed = FALSE
 | FOR [ USIZE i = 0 | i < (ts.size)[] | i += 1 ]
 |  | @Task t = (ts.at)[ i ]
 |  | WHILE [ (task_running)[ t ] && (now_ms)[] - start < TASK_SLICE_MS ]
 |  |  | IF [ t.in < 0 && (t.steps.size)[] == 0 ]
 |  |  |  | t.ended = (now_ms)[]
 |  |  |  | (t.now.deinit)[]
 |  |  |  | t.now = (String.of)[ "" ]
 |  |  |  | BREAK
 |  |  |  \_
 |  |  | (task_step)[ t ]
 |  |  | changed = TRUE
 |  |  \_
 |  \_
 |
 | USIZE i = 0
 | WHILE [ i < (ts.size)[] ]
 |  | @Task t = (ts.at)[ i ]
 |  | U64 keep = SELECT [ t.failed > 0 | TASK_ERR_MS | TASK_KEEP_MS ]
 |  | IF [ !((task_running)[ t ]) && (now_ms)[] - t.ended > keep ]
 |  |  | Task gone = (ts.remove)[ i ]
 |  |  | (task_free)[ @gone ]
 |  |  | changed = TRUE
 |  |  | CONTINUE
 |  |  \_
 |  | i += 1
 |  \_
 | RET [ changed ]
 \_

; is any task still at work?
B1 tasks_busy: [ @Vector<Task> ts ]
 | FOR [ USIZE i = 0 | i < (ts.size)[] | i += 1 ]
 |  | IF [ (task_running)[ (ts.at)[ i ] ] ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_
