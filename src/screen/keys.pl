; keys.pl -- what the keys do that no column took, in the order a frame
; meets them: the delete question before anything is drawn, the prompt and
; the file keys after, and last the one change of folder a frame may make --
; a tab, a place, a jump, the parent column

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

USE <modular.pl>
!USES <../core/config.pl>
!USES <../ui/places.pl>
!USES <../ui/main.pl>
!USES <../app/app.pl>
!USES <../app/files.pl>
!USES <../app/open.pl>

CONST @CONST C1 TAB_KEYS{} = [ "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ]
; Shift and 1 to 9, as a US keyboard has them
CONST @CONST C1 TAB_HERE{} = [ "!" | "@" | "#" | "$" | "%" | "^" | "&" | "*" | "(" ]

; the key `k` pressed, or a click on what stands for it -- [y] copy in the
; keys' line, Copy in a row's actions
B1 hit: [ @Ui ui | @App a | @CONST C1 k ]
 | IF [ (str_eq)[ a.clicked AS @CONST C1 | k ] ]
 |  | a.clicked{0} = '\0'
 |  | RET [ TRUE ]
 |  \_
 | RET [ (ui.shortcut)[ k ] ]
 \_

; before the columns are drawn: the folder gone from under it, and the
; delete question, which takes every key so nothing moves under it
ABYSS keys_first: [ @Ui ui | @App a ]
 | ; the folder gone under it -- an unmount, a delete from elsewhere: up to
 | ; one that is there. The program wakes at least once a second, so soon
 | IF [ (app_check_gone)[ a ] ]
 |  | (ui.redo)[]
 |  \_
 |
 | ; names a paste finds taken: o overwrites, s skips them, k keeps both;
 | ; anything else gives the paste up
 | IF [ a.prompt == PR_CLASH && (ui.key)[] != 0 ]
 |  | IF [ (ui.take)[ 'o' AS U32 ] ]
 |  |  | (file_paste_as)[ a | CLASH_OVER ]
 |  | ELIF [ (ui.take)[ 's' AS U32 ] ]
 |  |  | (file_paste_as)[ a | CLASH_SKIP ]
 |  | ELIF [ (ui.take)[ 'k' AS U32 ] ]
 |  |  | (file_paste_as)[ a | CLASH_KEEP ]
 |  | ELSE
 |  |  | (ui.consume)[]
 |  |  | a.prompt = PR_NONE
 |  |  \_
 |  | (ui.redo)[]
 |  \_
 |
 | ; which program to open with: 1 to 9, e to type one, anything else gives
 | ; it up
 | IF [ a.prompt == PR_CHOOSE && (ui.key)[] != 0 ]
 |  | U32 k = (ui.key)[]
 |  | (ui.consume)[]
 |  | IF [ k >= ('1' AS U32) && k <= ('9' AS U32) && (k - ('1' AS U32)) < ((a.choices.size)[] AS U32) ]
 |  |  | a.prompt = PR_NONE
 |  |  | (open_pick)[ a | ui | (k - ('1' AS U32)) AS USIZE ]
 |  | ELIF [ k == ('e' AS U32) ]
 |  |  | (open_edit)[ a ]
 |  |  | (ui.set_focus)[ (ui.id)[ "prompt" ] ]
 |  | ELSE
 |  |  | a.prompt = PR_NONE
 |  |  \_
 |  | (ui.redo)[]
 |  \_
 |
 | ; give a task up: y does, anything else keeps it going
 | IF [ a.prompt == PR_CANCEL && (ui.key)[] != 0 ]
 |  | IF [ (ui.take)[ 'y' AS U32 ] ]
 |  |  | (file_cancel_now)[ a ]
 |  | ELSE
 |  |  | (ui.consume)[]
 |  |  | a.prompt = PR_NONE
 |  |  \_
 |  | (ui.redo)[]
 |  \_
 |
 | ; the delete question takes every key, before the columns can see one:
 | ; nothing moves under it. y deletes, anything else keeps
 | IF [ a.prompt == PR_DELETE && (ui.key)[] != 0 ]
 |  | IF [ (ui.take)[ 'y' AS U32 ] ]
 |  |  | (file_delete_now)[ a ]
 |  | ELSE
 |  |  | (ui.consume)[]
 |  |  | (strings_clear)[ @(a.pending) ]
 |  |  | a.prompt = PR_NONE
 |  |  \_
 |  | (ui.redo)[]
 |  \_
 |
 \_

; after: a prompt open takes the keys, Esc gives it up. TRUE: one is open,
; nothing else is done this frame
B1 keys_prompt: [ @Ui ui | @App a ]
 | ; the filter being typed: ↑ ↓ move in what it lets through; Esc clears it
 | IF [ a.prompt == PR_FILTER ]
 |  | @ListState l = @(a.listing.table.list)
 |  | IF [ (ui.take)[ KEY_DOWN ] && l.cursor + 1 < l.count ]
 |  |  | l.cursor += 1
 |  |  | (ui.redo)[]
 |  | ELIF [ (ui.take)[ KEY_UP ] && l.cursor > 0 ]
 |  |  | l.cursor -= 1
 |  |  | (ui.redo)[]
 |  |  \_
 |  | IF [ (ui.take)[ KEY_ESC ] ]
 |  |  | (main_filter)[ @(a.listing) | "" ]
 |  |  | a.prompt = PR_NONE
 |  |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  | RET [ TRUE ]
 |  \_
 | ; a row's actions: a click on one, or its key, closes them and does it
 | ; below as the key would; Esc or any other key only closes them
 | IF [ a.prompt == PR_MENU ]
 |  | IF [ a.clicked{0} != '\0' || (ui.key)[] != 0 ]
 |  |  | a.prompt = PR_NONE
 |  |  | (ui.take)[ KEY_ESC ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  | RET [ a.prompt != PR_NONE ]
 |  \_
 | IF [ a.prompt != PR_NONE ]
 |  | IF [ (ui.take)[ KEY_ESC ] ]
 |  |  | a.prompt = PR_NONE
 |  |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  | RET [ TRUE ]
 |  \_
 | RET [ FALSE ]
 \_

; y d p D r n o, Enter on a file, Esc out of V
ABYSS keys_files: [ @Ui ui | @App a ]
 | ; what the places column had to say: a bookmark taken off, or not
 | IF [ (a.places.said.size)[] > 0 ]
 |  | (app_note)[ a | (a.places.said.cstr)[] ]
 |  | (a.places.said.deinit)[]
 |  | a.places.said = (String.of)[ "" ]
 |  \_
 | ; the files
 | B1 did = TRUE
 | IF [ (hit)[ ui | a | "y" ] ]
 |  | (file_yank)[ a | FALSE ]
 | ELIF [ (hit)[ ui | a | "d" ] ]
 |  | (file_yank)[ a | TRUE ]
 | ELIF [ (hit)[ ui | a | "p" ] ]
 |  | (file_paste)[ a ]
 | ELIF [ (hit)[ ui | a | "D" ] || (ui.take)[ KEY_DELETE ] ]
 |  | (file_trash)[ a ]
 | ELIF [ (hit)[ ui | a | "X" ] ]
 |  | (file_ask_delete)[ a ]
 | ELIF [ (hit)[ ui | a | "?" ] ]
 |  | a.help = TRUE
 |  | a.help_sc.top = 0
 |  | (ui.set_focus)[ (ui.id)[ "help" ] ]
 | ELIF [ (hit)[ ui | a | "E" ] ]
 |  | (file_extract)[ a ]
 | ELIF [ (hit)[ ui | a | "P" ] ]
 |  | (file_pause)[ a ]
 | ELIF [ (hit)[ ui | a | "K" ] ]
 |  | (file_ask_cancel)[ a ]
 | ELIF [ (hit)[ ui | a | "R" ] ]
 |  | (file_retry)[ a ]
 | ELIF [ (hit)[ ui | a | "dismiss" ] ]
 |  | (file_dismiss)[ a ]
 | ELIF [ (hit)[ ui | a | "u" ] ]
 |  | IF [ a.listing.trash ]
 |  |  | (file_restore)[ a ]
 |  | ELSE
 |  |  | (file_untrash)[ a ]
 |  |  \_
 | ELIF [ (hit)[ ui | a | "Z" ] ]
 |  | (file_ask_empty)[ a ]
 | ELIF [ (hit)[ ui | a | "r" ] ]
 |  | (file_ask_rename)[ a ]
 | ELIF [ (hit)[ ui | a | "n" ] ]
 |  | (file_ask_mkdir)[ a ]
 | ELIF [ (hit)[ ui | a | "c" ] ]
 |  | (file_ask_chmod)[ a ]
 | ELIF [ (hit)[ ui | a | "C" ] ]
 |  | (file_ask_chown)[ a ]
 | ELIF [ (hit)[ ui | a | "a" ] ]
 |  | (file_git)[ a | TRUE ]
 | ELIF [ (hit)[ ui | a | "A" ] ]
 |  | (file_git)[ a | FALSE ]
 | ELIF [ (hit)[ ui | a | "L" ] ]
 |  | (file_paste_links)[ a ]
 | ELIF [ (hit)[ ui | a | "i" ] ]
 |  | a.preview.props = !(a.preview.props)
 |  | ; the sheet and the diff share the place: one at a time
 |  | IF [ a.preview.props && a.preview.diff ]
 |  |  | a.preview.diff = FALSE
 |  |  | (preview_redo)[ @(a.preview) ]
 |  |  \_
 | ELIF [ (hit)[ ui | a | "=" ] ]
 |  | IF [ !(a.listing.git.on) ]
 |  |  | (app_note)[ a | "not in a git work tree" ]
 |  | ELSE
 |  |  | a.preview.diff = !(a.preview.diff)
 |  |  | a.preview.props = FALSE
 |  |  | (preview_redo)[ @(a.preview) ]
 |  |  \_
 | ELIF [ (hit)[ ui | a | ":" ] ]
 |  | (shell_ask)[ a ]
 | ELIF [ (hit)[ ui | a | "o" ] || a.preview.want_with ]
 |  | (open_ask)[ a ]
 | ELIF [ a.listing.want_open || a.preview.want_open || (hit)[ ui | a | "open" ] ]
 |  | (open_now)[ a | ui ]
 | ELIF [ (hit)[ ui | a | "/" ] ]
 |  | (input_set)[ @(a.filter_field) | (a.listing.filter.cstr)[] ]
 |  | a.prompt = PR_FILTER
 | ELIF [ (str_eq)[ a.clicked AS @CONST C1 | "V" ] ]
 |  | a.clicked{0} = '\0'
 |  | IF [ a.listing.visual ]
 |  |  | (visual_off)[ @(a.listing) ]
 |  | ELSE
 |  |  | (visual_on)[ @(a.listing) ]
 |  |  \_
 | ELIF [ a.listing.want_menu ]
 |  | a.listing.want_menu = FALSE
 |  | a.prompt = PR_MENU
 | ELIF [ a.listing.visual && (ui.take)[ KEY_ESC ] ]
 |  | (visual_off)[ @(a.listing) ]
 | ELIF [ (a.listing.filter.size)[] > 0 && (ui.take)[ KEY_ESC ] ]
 |  | (main_filter)[ @(a.listing) | "" ]
 | ELIF [ a.preview.props && (ui.take)[ KEY_ESC ] ]
 |  | a.preview.props = FALSE
 | ELIF [ a.preview.diff && (ui.take)[ KEY_ESC ] ]
 |  | a.preview.diff = FALSE
 |  | (preview_redo)[ @(a.preview) ]
 | ELIF [ (task_pick_held)[ @(a.tasks) | a.task_cur ] >= 0 && (ui.take)[ KEY_ESC ] ]
 |  | (file_dismiss)[ a ]
 | ELSE
 |  | did = FALSE
 |  \_
 | IF [ did ]
 |  | IF [ a.prompt == PR_RENAME || a.prompt == PR_MKDIR || a.prompt == PR_OPEN || a.prompt == PR_SHELL || a.prompt == PR_CHMOD || a.prompt == PR_CHOWN ]
 |  |  | (ui.set_focus)[ (ui.id)[ "prompt" ] ]
 |  | ELIF [ a.prompt == PR_FILTER ]
 |  |  | (ui.set_focus)[ (ui.id)[ "filter" ] ]
 |  |  \_
 |  | (ui.redo)[]
 |  \_
 |
 \_

; the one change of folder a frame: a tab (`want` from a click), . ~ b,
; t x, and else `go`, what a column asked for
ABYSS keys_move: [ @Ui ui | @App a | @String go | I32 want ]
 | ; 1 to 9: to that tab, made if need be; Shift and it: that tab here
 | I32 slot = 0
 | B1 here = FALSE
 | FOR [ I32 i = 0 | i < (MAX_TABS AS I32) | i += 1 ]
 |  | IF [ (hit)[ ui | a | TAB_KEYS{i} ] ]
 |  |  | slot = i + 1
 |  |  \_
 |  | IF [ (hit)[ ui | a | TAB_HERE{i} ] ]
 |  |  | slot = i + 1
 |  |  | here = TRUE
 |  |  \_
 |  \_
 | IF [ (hit)[ ui | a | "." ] ]
 |  | (app_toggle_hidden)[ a ]
 |  | (ui.redo)[]
 |  \_
 | IF [ (hit)[ ui | a | "~" ] ]
 |  | (go.deinit)[]
 |  | ?go = (String.of)[ ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 | IF [ (hit)[ ui | a | "b" ] ]
 |  | I32 got = (bookmark_add)[ @(a.places) | (a.cwd.cstr)[] ]
 |  | IF [ got == BM_ADDED ]
 |  |  | (app_note)[ a | "bookmarked" ]
 |  | ELIF [ got == BM_THERE ]
 |  |  | (app_note)[ a | "already a place" ]
 |  | ELSE
 |  |  | (app_note)[ a | "the bookmarks file cannot be written" ]
 |  |  \_
 |  | (ui.redo)[]
 |  \_
 |
 | IF [ a.close_tab >= 0 ]
 |  | (a.open_tab)[ a.close_tab AS USIZE ]
 |  | (a.close_tab)[]
 |  | a.close_tab = -1
 |  | (ui.redo)[]
 | ELIF [ (hit)[ ui | a | "t" ] ]
 |  | (a.new_tab)[]
 |  | (ui.redo)[]
 | ELIF [ (hit)[ ui | a | "x" ] ]
 |  | (a.close_tab)[]
 |  | (ui.redo)[]
 | ELIF [ slot > 0 && here ]
 |  | (a.here_slot)[ slot ]
 |  | (ui.redo)[]
 | ELIF [ slot > 0 ]
 |  | (a.goto_slot)[ slot ]
 |  | (ui.redo)[]
 | ELIF [ want >= 0 ]
 |  | (a.open_tab)[ want AS USIZE ]
 |  | (ui.redo)[]
 | ELIF [ (go.size)[] > 0 && !((a.cwd.equals)[ (go.cstr)[] ]) && (a.go_to)[ (go.cstr)[] ] ]
 |  | (ui.redo)[]
 |  \_
 \_
