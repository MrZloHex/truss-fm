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
!USES <../ui/main.pl>

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
 | ; an extraction's end is not known: its count, on an empty track
 | IF [ t.extracting ]
 |  | pct = 0
 |  \_
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
 | IF [ t.counting || t.extracting ]
 |  | (ui.put)[ (fg)[ DIM ] | "   …   " ]
 |  \_
 | IF [ !(t.counting) && !(t.extracting) ]
 |  | ((ui.pen)[ (fg)[ TEXT ] ].print)[ " %3d%%  " | pct ]
 |  \_
 |
 | IF [ t.failed > 0 ]
 |  | ((ui.pen)[ (fg)[ C_BROKEN ] ].print)[ "✗ %d failed: %s" | t.failed | (t.error.cstr)[] ]
 | ELIF [ !((task_running)[ t ]) ]
 |  | (ui.put)[ (fg)[ DIM ] | "done" ]
 | ELIF [ t.extracting ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "%d · %s" | t.done AS I32 | (t.now.cstr)[] ]
 | ELIF [ t.counting ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "counting… %s" | (t.now.cstr)[] ]
 | ELSE
 |  | (ui.put)[ (fg)[ DIM ] | (t.now.cstr)[] ]
 |  \_
 \_

; a row's actions, offered by a right press: what each says, its key, and
; the key a click on it stands for
CONST @CONST C1 MENU_WHAT{} = [ "open" | "open with" | "copy" | "cut" | "paste" | "rename" | "extract" | "trash" | "delete" | "new folder" ]
CONST @CONST C1 MENU_KEY{} = [ "[⏎]" | "[o]" | "[y]" | "[d]" | "[p]" | "[r]" | "[E]" | "[D]" | "[X]" | "[n]" ]
CONST @CONST C1 MENU_CODE{} = [ "open" | "o" | "y" | "d" | "p" | "r" | "E" | "D" | "X" | "n" ]
CONST I32 NMENU = COUNT [ MENU_WHAT ]
STATIC_ASSERT [ COUNT [ MENU_KEY ] == NMENU && COUNT [ MENU_CODE ] == NMENU | "a key and a code for each action" ]

; an answer to click: its key in amber, what it does; TRUE when clicked
B1 answer: [ @Ui ui | @CONST C1 key | @CONST C1 what | I32 k ]
 | U32 id = (ui.idn)[ "answer" | k ]
 | @Node t = (ui.text)[ FIT | 1 ]
 | (t.with_id)[ id ]
 | (t.pad)[ 1 | 0 ]
 | (ui.cursor_on)[ id | CUR_HAND ]
 | B1 over = (ui.hovered)[ id ]
 | IF [ over ]
 |  | (t.background)[ C_CURSOR ]
 |  \_
 | IF [ key{0} != '\0' ]
 |  | (ui.put)[ (fg)[ AMBER ] | key ]
 |  | (ui.put)[ (fg)[ TEXT ] | " " ]
 |  \_
 | (ui.put)[ (fg)[ SELECT [ key{0} == '\0' | DIM | TEXT ] ] | what ]
 | RET [ (ui.clicked)[ id ] ]
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
 | IF [ a.prompt == PR_MENU ]
 |  | (ui.row)[ GROW | 1 ]
 |  | (ui.text)[ FIT | 1 ]
 |  | String name = (main_path)[ @(a.listing) | a.listing.table.list.cursor ]
 |  | String base = (get_dirname)[ (name.cstr)[] ]
 |  | ((ui.pen)[ (bold)[ AMBER ] ].print)[ " %s: " | (base.cstr)[] ]
 |  | (name.deinit)[]
 |  | (base.deinit)[]
 |  | FOR [ I32 i = 0 | i < NMENU | i += 1 ]
 |  |  | IF [ (answer)[ ui | MENU_KEY{i} | MENU_WHAT{i} | i ] ]
 |  |  |  | (str_copy)[ a.clicked | 16 | MENU_CODE{i} ]
 |  |  |  \_
 |  |  \_
 |  | IF [ (answer)[ ui | "" | "cancel" | NMENU ] ]
 |  |  | a.prompt = PR_NONE
 |  |  \_
 |  | (ui.close)[]
 |  | RET []
 |  \_
 |
 | IF [ a.prompt == PR_CHOOSE ]
 |  | (ui.row)[ GROW | 1 ]
 |  | (ui.text)[ FIT | 1 ]
 |  | String one = (get_dirname)[ ((a.pending.at)[ 0 ].cstr)[] ]
 |  | IF [ (a.pending.size)[] == 1 ]
 |  |  | ((ui.pen)[ (bold)[ AMBER ] ].print)[ " open %s with: " | (one.cstr)[] ]
 |  | ELSE
 |  |  | ((ui.pen)[ (bold)[ AMBER ] ].print)[ " open %d with: " | (a.pending.size)[] AS I32 ]
 |  |  \_
 |  | (one.deinit)[]
 |  | FOR [ USIZE i = 0 | i < (a.choices.size)[] | i += 1 ]
 |  |  | C1 key{8}
 |  |  | BufferSink b = (BufferSink.over)[ key | 8 ]
 |  |  | (b.print)[ "[%d]" | (i AS I32) + 1 ]
 |  |  | IF [ (answer)[ ui | key AS @CONST C1 | ((a.choices.at)[ i ].cstr)[] | 20 + (i AS I32) ] ]
 |  |  |  | a.prompt = PR_NONE
 |  |  |  | (open_pick)[ a | ui | i ]
 |  |  |  \_
 |  |  \_
 |  | IF [ (answer)[ ui | "[e]" | "type a command" | 30 ] ]
 |  |  | (open_edit)[ a ]
 |  |  | (ui.set_focus)[ (ui.id)[ "prompt" ] ]
 |  |  \_
 |  | IF [ (answer)[ ui | "" | "cancel" | 31 ] ]
 |  |  | a.prompt = PR_NONE
 |  |  \_
 |  | (ui.close)[]
 |  | RET []
 |  \_
 | IF [ a.prompt == PR_CLASH ]
 |  | (ui.row)[ GROW | 1 ]
 |  | (ui.text)[ FIT | 1 ]
 |  | IF [ a.clashes == 1 ]
 |  |  | ((ui.pen)[ (bold)[ AMBER ] ].print)[ " %s is here already: " | (a.clash_one.cstr)[] ]
 |  | ELSE
 |  |  | ((ui.pen)[ (bold)[ AMBER ] ].print)[ " %d names are taken here: " | a.clashes ]
 |  |  \_
 |  | IF [ (answer)[ ui | "[o]" | "overwrite" | 0 ] ]
 |  |  | (file_paste_as)[ a | CLASH_OVER ]
 |  |  \_
 |  | IF [ (answer)[ ui | "[s]" | "skip" | 1 ] ]
 |  |  | (file_paste_as)[ a | CLASH_SKIP ]
 |  |  \_
 |  | IF [ (answer)[ ui | "[k]" | "keep both" | 2 ] ]
 |  |  | (file_paste_as)[ a | CLASH_KEEP ]
 |  |  \_
 |  | IF [ (answer)[ ui | "" | "cancel" | 3 ] ]
 |  |  | a.prompt = PR_NONE
 |  |  \_
 |  | (ui.close)[]
 |  | RET []
 |  \_
 | IF [ a.prompt != PR_DELETE ]
 |  | RET []
 |  \_
 | (ui.row)[ GROW | 1 ]
 | (ui.text)[ FIT | 1 ]
 | USIZE n = (a.pending.size)[]
 | String one = (get_dirname)[ ((a.pending.at)[ 0 ].cstr)[] ]
 | IF [ n == 1 ]
 |  | ((ui.pen)[ (bold)[ C_BROKEN ] ].print)[ " delete %s for good? " | (one.cstr)[] ]
 | ELSE
 |  | ((ui.pen)[ (bold)[ C_BROKEN ] ].print)[ " delete %d items for good? " | n AS I32 ]
 |  \_
 | (one.deinit)[]
 | IF [ (answer)[ ui | "[y]" | "yes" | 0 ] ]
 |  | (file_delete_now)[ a ]
 | ELIF [ (answer)[ ui | "[n]" | "no" | 1 ] ]
 |  | (strings_clear)[ @(a.pending) ]
 |  | a.prompt = PR_NONE
 |  \_
 | (ui.close)[]
 \_

; only while there is a task, or a question to ask
ABYSS tasks_bar: [ @Ui ui | @App a ]
 | USIZE n = (a.tasks.size)[]
 | B1 asking = a.prompt != PR_NONE && a.prompt != PR_FILTER
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

