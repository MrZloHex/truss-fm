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

; before the columns are drawn: the folder gone from under it, and the
; delete question, which takes every key so nothing moves under it
ABYSS keys_first: [ @Ui ui | @App a ]
 | ; the folder gone under it -- an unmount, a delete from elsewhere: up to
 | ; one that is there. The program wakes at least once a second, so soon
 | IF [ (app_check_gone)[ a ] ]
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
 | ; the files
 | B1 did = TRUE
 | IF [ (ui.shortcut)[ "y" ] ]
 |  | (file_yank)[ a | FALSE ]
 | ELIF [ (ui.shortcut)[ "d" ] ]
 |  | (file_yank)[ a | TRUE ]
 | ELIF [ (ui.shortcut)[ "p" ] ]
 |  | (file_paste)[ a ]
 | ELIF [ (ui.shortcut)[ "D" ] || (ui.take)[ KEY_DELETE ] ]
 |  | (file_ask_delete)[ a ]
 | ELIF [ (ui.shortcut)[ "r" ] ]
 |  | (file_ask_rename)[ a ]
 | ELIF [ (ui.shortcut)[ "n" ] ]
 |  | (file_ask_mkdir)[ a ]
 | ELIF [ (ui.shortcut)[ "o" ] || a.preview.want_with ]
 |  | (open_ask)[ a ]
 | ELIF [ a.listing.want_open || a.preview.want_open ]
 |  | (open_now)[ a | ui ]
 | ELIF [ a.listing.visual && (ui.take)[ KEY_ESC ] ]
 |  | (visual_off)[ @(a.listing) ]
 | ELSE
 |  | did = FALSE
 |  \_
 | IF [ did ]
 |  | IF [ a.prompt == PR_RENAME || a.prompt == PR_MKDIR || a.prompt == PR_OPEN ]
 |  |  | (ui.set_focus)[ (ui.id)[ "prompt" ] ]
 |  |  \_
 |  | (ui.redo)[]
 |  \_
 |
 \_

; the one change of folder a frame: a tab (`want` from a click), . ~ b,
; t x, and else `go`, what a column asked for
ABYSS keys_move: [ @Ui ui | @App a | @String go | I32 want ]
 | FOR [ I32 i = 0 | i < (MAX_TABS AS I32) | i += 1 ]
 |  | IF [ (ui.shortcut)[ TAB_KEYS{i} ] ]
 |  |  | want = i
 |  |  \_
 |  \_
 | IF [ (ui.shortcut)[ "." ] ]
 |  | (app_toggle_hidden)[ a ]
 |  | (ui.redo)[]
 |  \_
 | IF [ (ui.shortcut)[ "~" ] ]
 |  | (go.deinit)[]
 |  | ?go = (String.of)[ ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 | IF [ (ui.shortcut)[ "b" ] ]
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
 | IF [ (ui.shortcut)[ "t" ] ]
 |  | (a.new_tab)[]
 |  | (ui.redo)[]
 | ELIF [ (ui.shortcut)[ "x" ] ]
 |  | (a.close_tab)[]
 |  | (ui.redo)[]
 | ELIF [ want >= 0 ]
 |  | (a.open_tab)[ want AS USIZE ]
 |  | (ui.redo)[]
 | ELIF [ (go.size)[] > 0 && !((a.cwd.equals)[ (go.cstr)[] ]) && (a.go_to)[ (go.cstr)[] ] ]
 |  | (ui.redo)[]
 |  \_
 \_
