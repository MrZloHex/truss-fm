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

; what a task is at, after its bar: speed and time left for a copy, items
; and the time for a delete, entries for an unpacking, else the name it is at
ABYSS task_doing: [ @Ui ui | @Task t ]
 | C1 s{96}
 | IF [ t.extracting ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "%d · %s" | t.done AS I32 | (t.now.cstr)[] ]
 |  | RET []
 |  \_
 | IF [ t.running_cmd ]
 |  | (ui.put)[ (fg)[ DIM ] | "working…" ]
 |  | RET []
 |  \_
 | IF [ t.counting ]
 |  | IF [ t.kind == TK_DELETE ]
 |  |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "sizing… %d items · %s" | t.total AS I32 | (t.now.cstr)[] ]
 |  | ELSE
 |  |  | C1 sz{16}
 |  |  | (size_text)[ sz | t.total ]
 |  |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "sizing… %s · %s" | sz AS @CONST C1 | (t.now.cstr)[] ]
 |  |  \_
 |  | RET []
 |  \_
 | ; a move that only renames has no speed to tell
 | B1 speed = t.kind == TK_COPY || t.kind == TK_DELETE || (t.kind == TK_MOVE && t.copied)
 | IF [ !speed ]
 |  | (ui.put)[ (fg)[ DIM ] | (t.now.cstr)[] ]
 |  | RET []
 |  \_
 | IF [ !(t.rated) || t.rate == 0 ]
 |  | (ui.put)[ (fg)[ DIM ] | "—" ]
 | ELSE
 |  | IF [ t.kind == TK_DELETE ]
 |  |  | (pace_items)[ s | 96 | t.rate ]
 |  | ELSE
 |  |  | (pace_bytes)[ s | 96 | t.rate ]
 |  |  \_
 |  | (ui.put)[ (fg)[ TEXT ] | s AS @CONST C1 ]
 |  | U64 left = SELECT [ t.total > t.done | t.total - t.done | 0 ]
 |  | IF [ t.kind == TK_DELETE ]
 |  |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ " · %d left" | left AS I32 ]
 |  |  \_
 |  | (pace_left)[ s | 96 | (pace_secs)[ left | t.rate ] ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ " · %s" | s AS @CONST C1 ]
 |  \_
 | ((ui.pen)[ (fg)[ DIM ] ].print)[ " · %s" | (t.now.cstr)[] ]
 \_

; copy 3 items → ~/work  ███████─────────  42%  12.3 MB/s · 34 s left · big.iso
; and its buttons. A click on the line makes it the task the keys act on; a
; button's click is passed on as its key, for that task
ABYSS task_line: [ @Ui ui | @App a | @Task t | B1 cur ]
 | (ui.row)[ GROW | 1 ]
 | U32 lid = (ui.idn)[ "task" | t.id AS I32 ]
 | @Node line = (ui.text)[ GROW | 1 ]
 | (line.with_id)[ lid ]
 | (ui.cursor_on)[ lid | CUR_HAND ]
 | IF [ cur ]
 |  | (line.background)[ C_CURSOR ]
 |  \_
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
 | IF [ t.extracting || t.running_cmd ]
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
 | IF [ t.counting || t.extracting || t.running_cmd ]
 |  | (ui.put)[ (fg)[ DIM ] | "   …   " ]
 |  \_
 | IF [ !(t.counting) && !(t.extracting) && !(t.running_cmd) ]
 |  | ((ui.pen)[ (fg)[ TEXT ] ].print)[ " %3d%%  " | pct ]
 |  \_
 |
 | B1 running = (task_running)[ t ]
 | IF [ t.failed > 0 && !running ]
 |  | ((ui.pen)[ (fg)[ C_BROKEN ] ].print)[ "✗ %d failed: %s" | t.failed | (t.error.cstr)[] ]
 | ELIF [ !running ]
 |  | (ui.put)[ (fg)[ DIM ] | "done" ]
 | ELIF [ t.paused ]
 |  | (ui.put)[ (fg)[ DIM ] | "paused" ]
 | ELSE
 |  | IF [ t.failed > 0 ]
 |  |  | ((ui.pen)[ (fg)[ C_BROKEN ] ].print)[ "✗ %d  " | t.failed ]
 |  |  \_
 |  | (task_doing)[ ui | t ]
 |  \_
 | B1 picked = (ui.clicked)[ lid ]
 |
 | ; the buttons: ids by the task's, so a click is for this one wherever its line is
 | I32 base = 1000 + (t.id AS I32) * 4
 | IF [ running ]
 |  | IF [ (answer)[ ui | "[P]" | SELECT [ t.paused | "resume" | "pause" ] | base ] ]
 |  |  | picked = TRUE
 |  |  | (str_copy)[ a.clicked | 16 | "P" ]
 |  |  \_
 |  | IF [ (answer)[ ui | "[K]" | "cancel" | base + 1 ] ]
 |  |  | picked = TRUE
 |  |  | (str_copy)[ a.clicked | 16 | "K" ]
 |  |  \_
 |  \_
 | IF [ (task_held)[ t ] ]
 |  | IF [ (t.bad_src.size)[] > 0 || t.kind == TK_EXTRACT ]
 |  |  | IF [ (answer)[ ui | "[R]" | "retry" | base + 2 ] ]
 |  |  |  | picked = TRUE
 |  |  |  | (str_copy)[ a.clicked | 16 | "R" ]
 |  |  |  \_
 |  |  \_
 |  | IF [ (answer)[ ui | "[Esc]" | "dismiss" | base + 3 ] ]
 |  |  | picked = TRUE
 |  |  | (str_copy)[ a.clicked | 16 | "dismiss" ]
 |  |  \_
 |  \_
 | IF [ picked ]
 |  | a.task_cur = t.id
 |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  \_
 | (ui.close)[]
 \_

; the last line, while something is asked: a name, or yes or no
ABYSS task_status: [ @Ui ui | @App a ]
 | IF [ a.prompt == PR_RENAME || a.prompt == PR_MKDIR || a.prompt == PR_TOUCH || a.prompt == PR_OPEN || a.prompt == PR_SHELL || a.prompt == PR_CHMOD || a.prompt == PR_CHOWN ]
 |  | (ui.row)[ GROW | 1 ]
 |  | (ui.text)[ FIT | 1 ]
 |  | (ui.put)[ (bold)[ AMBER ] | SELECT [ a.prompt == PR_RENAME | " rename to " | SELECT [ a.prompt == PR_MKDIR | " new folder " | SELECT [ a.prompt == PR_TOUCH | " new file " | SELECT [ a.prompt == PR_OPEN | " open with " | SELECT [ a.prompt == PR_CHMOD | " chmod " | SELECT [ a.prompt == PR_CHOWN | " chown " | " : " ] ] ] ] ] ] ]
 |  | I32 got = (ui.input)[ @(a.field) | (ui.id)[ "prompt" ] | GROW | SELECT [ a.prompt == PR_SHELL | "a command -- the chosen files are \"$@\"" | SELECT [ a.prompt == PR_CHMOD | "755 or u+x,go-w -- -R first: folders' insides too" | SELECT [ a.prompt == PR_CHOWN | "user, user:group or :group -- -R first: folders' insides too" | "a name" ] ] ] ]
 |  | (ui.text)[ FIT | 1 ]
 |  | (ui.put)[ (fg)[ DIM ] | " [enter] ok · [esc] cancel " ]
 |  | (ui.close)[]
 |  | IF [ got == IN_SUBMIT ]
 |  |  | C1 name{INPUT_CAP}
 |  |  | (str_copy)[ name | INPUT_CAP AS USIZE | (input_text)[ @(a.field) ] ]
 |  |  | IF [ a.prompt == PR_OPEN ]
 |  |  |  | (open_typed)[ a | ui | name AS @CONST C1 ]
 |  |  | ELIF [ a.prompt == PR_SHELL ]
 |  |  |  | (shell_typed)[ a | ui | name AS @CONST C1 ]
 |  |  | ELIF [ a.prompt == PR_CHMOD ]
 |  |  |  | (file_chmod_done)[ a | name AS @CONST C1 ]
 |  |  | ELIF [ a.prompt == PR_CHOWN ]
 |  |  |  | (file_chown_done)[ a | name AS @CONST C1 ]
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
 |  |  | IF [ (answer)[ ui | key AS @CONST C1 | ((a.labels.at)[ i ].cstr)[] | 20 + (i AS I32) ] ]
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
 | IF [ a.prompt == PR_CANCEL ]
 |  | I32 at = (task_index)[ @(a.tasks) | a.cancel_id ]
 |  | IF [ at < 0 ]
 |  |  | a.prompt = PR_NONE
 |  |  | RET []
 |  |  \_
 |  | @Task ct = (a.tasks.at)[ at AS USIZE ]
 |  | (ui.row)[ GROW | 1 ]
 |  | (ui.text)[ FIT | 1 ]
 |  | (ui.put)[ (bold)[ C_BROKEN ] | " cancel " ]
 |  | (ui.put_cell)[ (bold)[ C_BROKEN ] | (ct.title.cstr)[] | TASK_TITLE | TRUE ]
 |  | (ui.put)[ (bold)[ C_BROKEN ] | "? " ]
 |  | IF [ (answer)[ ui | "[y]" | "yes" | 0 ] ]
 |  |  | (file_cancel_now)[ a ]
 |  | ELIF [ (answer)[ ui | "[n]" | "no" | 1 ] ]
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
 | IF [ a.emptying ]
 |  | ((ui.pen)[ (bold)[ C_BROKEN ] ].print)[ " empty the trash, %d %s gone for good? " | a.empty_n | SELECT [ a.empty_n == 1 | "item" | "items" ] ]
 | ELIF [ n == 1 ]
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
 | ; the task the keys act on stands out; it is always among those shown
 | I32 cur = (task_pick)[ @(a.tasks) | a.task_cur ]
 | I32 hold = (task_pick_held)[ @(a.tasks) | a.task_cur ]
 | USIZE first = n - shown
 | IF [ cur >= 0 && (cur AS USIZE) < first ]
 |  | first = cur AS USIZE
 |  \_
 | FOR [ USIZE i = first | i < first + shown | i += 1 ]
 |  | B1 mine = (i AS I32) == cur || ((i AS I32) == hold && cur < 0)
 |  | (task_line)[ ui | a | (a.tasks.at)[ i ] | mine && n > 1 ]
 |  \_
 | (task_status)[ ui | a ]
 | (ui.close)[]
 \_
