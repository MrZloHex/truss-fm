; command.pl -- a program run on files, as a task: chmod -R and chown -R,
; whose work could be a whole tree. It runs beside the frames, the files
; as arguments and never in its text; a failure is the last line it said

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>

!USES <job.pl>
!USES <tasks.pl>

CONST USIZE COMMAND_LIMIT = 0x7FFFFFFF  ; never reached: only its tail is kept
CONST USIZE COMMAND_KEEP = 4096         ;   that much of it, a failure's words

; the sh `script` run in `dir`, `spec` as its "$1" and `paths` after it, as a
; task called "`verb` <name>" or "`verb` N items"
Task task_command: [ @CONST C1 verb | @CONST C1 script | @CONST C1 spec | @Vector<String> paths | @CONST C1 dir ]
 | Task t = (task_new)[ TK_RUN ]
 | USIZE n = (paths.size)[]
 | @CONST C1 one = ""
 | IF [ n > 0 ]
 |  | one = ((paths.at)[ 0 ].cstr)[]
 |  \_
 | (task_title)[ @t | verb | n | one | NULL ]
 | IF [ !((job_start_many)[ @(t.job) | script | dir | spec | paths | COMMAND_LIMIT ]) ]
 |  | (task_fail)[ @t | one | "sh cannot be started" ]
 |  | RET [ t ]
 |  \_
 | t.running_cmd = TRUE
 | RET [ t ]
 \_

; a frame's share of the program's work. TRUE: it has ended
B1 command_step: [ @Task t ]
 | B1 over = (job_pump)[ @(t.job) ]
 | ; a tree full of failures says a lot: the last of it is all that is wanted
 | IF [ (t.job.out.size)[] > 2 * COMMAND_KEEP ]
 |  | String tail = (String.of)[ (t.job.out.cstr)[] + (t.job.out.size)[] - COMMAND_KEEP ]
 |  | (t.job.out.deinit)[]
 |  | t.job.out = tail
 |  \_
 | IF [ !over ]
 |  | RET [ FALSE ]
 |  \_
 | t.running_cmd = FALSE
 | IF [ t.job.ok ]
 |  | RET [ TRUE ]
 |  \_
 | ; the last line it said, or that it failed
 | @CONST C1 s = (t.job.out.cstr)[]
 | USIZE end = (t.job.out.size)[]
 | WHILE [ end > 0 && (s{end - 1} == '\n' || s{end - 1} == ' ') ]
 |  | end -= 1
 |  \_
 | USIZE start = end
 | WHILE [ start > 0 && s{start - 1} != '\n' ]
 |  | start -= 1
 |  \_
 | t.failed += 1
 | (t.error.deinit)[]
 | t.error = (String.of)[ "" ]
 | IF [ end > start ]
 |  | (t.error.append_n)[ s + start | end - start ]
 | ELSE
 |  | (t.error.append)[ "it failed" ]
 |  \_
 | RET [ TRUE ]
 \_
