; taskbox.pl -- the TASKS box above the keys: a line a task, its bar and
; what it is at, and under them the question being asked -- a name to type,
; or y or n. Not there while there is neither

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

USE <modular.pl>
!USES <../ui/look.pl>
!USES <../core/tasks.pl>
!USES <../app/app.pl>
!USES <../app/files.pl>
!USES <../app/open.pl>

CONST I32 TASK_BAR = 24         ; cells of a task's bar
CONST I32 TASK_TITLE = 36       ; its title, at most
CONST USIZE TASK_LINES = 4      ; tasks shown at once

; copy 3 items → ~/work  ███████─────────  42%  big.iso
ABYSS task_line: [ @Ui ui | @Task t ]
 | (ui.text)[ GROW | 1 ]
 | U64 total = SELECT [ t.total > 0 | t.total | 1 ]
 | U64 done = SELECT [ t.done > total | total | t.done ]
 | I32 pct = ((done * 100) / total) AS I32
 | IF [ !((task_running)[ t ]) && t.failed == 0 ]
 |  | pct = 100
 |  \_
 | (ui.put)[ (fg)[ TEXT ] | " " ]
 | (ui.put_cell)[ (fg)[ TEXT ] | (t.title.cstr)[] | TASK_TITLE | TRUE ]
 | (ui.put)[ (fg)[ TEXT ] | " " ]
 |
 | I32 fill = (pct * TASK_BAR) / 100
 | C1 bar{TASK_BAR * 3 + 1}
 | BufferSink b = (BufferSink.over)[ bar | (TASK_BAR * 3 + 1) AS USIZE ]
 | FOR [ I32 i = 0 | i < fill | i += 1 ]
 |  | (b.print)[ "█" ]
 |  \_
 | (ui.put)[ (fg)[ C_TASK ] | bar AS @CONST C1 ]
 | BufferSink r = (BufferSink.over)[ bar | (TASK_BAR * 3 + 1) AS USIZE ]
 | FOR [ I32 i = fill | i < TASK_BAR | i += 1 ]
 |  | (r.print)[ "─" ]
 |  \_
 | (ui.put)[ (fg)[ C_TRACK ] | bar AS @CONST C1 ]
 | IF [ t.counting ]
 |  | (ui.put)[ (fg)[ DIM ] | "   …   " ]
 |  \_
 | IF [ !(t.counting) ]
 |  | ((ui.pen)[ (fg)[ TEXT ] ].print)[ " %3d%%  " | pct ]
 |  \_
 |
 | IF [ t.failed > 0 ]
 |  | ((ui.pen)[ (fg)[ C_BROKEN ] ].print)[ "✗ %d failed: %s" | t.failed | (t.error.cstr)[] ]
 | ELIF [ !((task_running)[ t ]) ]
 |  | (ui.put)[ (fg)[ DIM ] | "done" ]
 | ELIF [ t.counting ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "counting… %s" | (t.now.cstr)[] ]
 | ELSE
 |  | (ui.put)[ (fg)[ DIM ] | (t.now.cstr)[] ]
 |  \_
 \_

; the last line, while something is asked: a name, or yes or no
ABYSS task_status: [ @Ui ui | @App a ]
 | IF [ a.prompt == PR_RENAME || a.prompt == PR_MKDIR || a.prompt == PR_OPEN ]
 |  | (ui.row)[ GROW | 1 ]
 |  | (ui.text)[ FIT | 1 ]
 |  | (ui.put)[ (bold)[ AMBER ] | SELECT [ a.prompt == PR_RENAME | " rename to " | SELECT [ a.prompt == PR_MKDIR | " new folder " | " open with " ] ] ]
 |  | I32 got = (ui.input)[ @(a.field) | (ui.id)[ "prompt" ] | GROW | "a name" ]
 |  | (ui.text)[ FIT | 1 ]
 |  | (ui.put)[ (fg)[ DIM ] | " [enter] ok · [esc] cancel " ]
 |  | (ui.close)[]
 |  | IF [ got == IN_SUBMIT ]
 |  |  | C1 name{INPUT_CAP}
 |  |  | (str_copy)[ name | INPUT_CAP AS USIZE | (input_text)[ @(a.field) ] ]
 |  |  | IF [ a.prompt == PR_OPEN ]
 |  |  |  | (open_typed)[ a | ui | name AS @CONST C1 ]
 |  |  | ELSE
 |  |  |  | (file_prompt_done)[ a | name AS @CONST C1 ]
 |  |  |  \_
 |  |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  | RET []
 |  \_
 |
 | IF [ a.prompt != PR_DELETE ]
 |  | RET []
 |  \_
 | (ui.text)[ GROW | 1 ]
 | IF [ a.prompt == PR_DELETE ]
 |  | USIZE n = (a.pending.size)[]
 |  | String one = (get_dirname)[ ((a.pending.at)[ 0 ].cstr)[] ]
 |  | IF [ n == 1 ]
 |  |  | ((ui.pen)[ (bold)[ C_BROKEN ] ].print)[ " delete %s for good? " | (one.cstr)[] ]
 |  | ELSE
 |  |  | ((ui.pen)[ (bold)[ C_BROKEN ] ].print)[ " delete %d items for good? " | n AS I32 ]
 |  |  \_
 |  | (one.deinit)[]
 |  | (ui.put)[ (fg)[ AMBER ] | "[y]" ]
 |  | (ui.put)[ (fg)[ TEXT ] | " yes   " ]
 |  | (ui.put)[ (fg)[ AMBER ] | "[n]" ]
 |  | (ui.put)[ (fg)[ TEXT ] | " no" ]
 |  | RET []
 |  \_
 |
 \_

; only while there is a task, or a question to ask
ABYSS tasks_bar: [ @Ui ui | @App a ]
 | USIZE n = (a.tasks.size)[]
 | B1 asking = a.prompt != PR_NONE
 | IF [ n == 0 && !asking ]
 |  | RET []
 |  \_
 | USIZE shown = SELECT [ n > TASK_LINES | TASK_LINES | n ]
 | (ui.box)[ "TASKS" | GROW | (shown AS I32) + SELECT [ asking | 3 | 2 ] ]
 | FOR [ USIZE i = n - shown | i < n | i += 1 ]
 |  | (task_line)[ ui | (a.tasks.at)[ i ] ]
 |  \_
 | (task_status)[ ui | a ]
 | (ui.close)[]
 \_

