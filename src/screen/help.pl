; help.pl -- ? : every key, and what the mouse does, in place of the four
; columns until ?, Esc or q closes it. Two columns of it where the screen is
; wide enough, one where it is not; j k, the arrows, PgUp PgDn and the wheel
; move it

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/io/io.pl>

USE <modular.pl>
!USES <../ui/look.pl>
!USES <../app/app.pl>

; a line each: its keys and what they do; "#" for keys makes a heading of
; what, "" for both a gap
CONST @CONST C1 HELP_L_KEYS{} = [
  "#" | "j k · ↓ ↑" | "h · ← · Backspace" | "l · → · Enter" | "gg · G" | "Ctrl-d · Ctrl-u" |
  "Ctrl-f · Ctrl-b" | "Tab · Shift-Tab" | "~" | "' then a key" | "" |
  "#" | "/" | "s then n · s · d" | "s then r" | "." | "" |
  "#" | "1 – 9" | "Shift + 1 – 9" | "t · x" | "" |
  "#" | "Enter · l · click" | "D · Delete" | "b" ]
CONST @CONST C1 HELP_L_WHAT{} = [
  "MOVING" | "down, up" | "up a folder" | "into a folder; open a file" | "top, bottom" | "half a page down, up" |
  "a page down, up -- PgDn PgUp Home End too" | "the next, the previous column" | "home" | "jump to a place: h e o d m p v / t, yours" | "" |
  "FINDING AND VIEWING" | "filter: Enter keeps, Esc clears, ↑ ↓ move" | "sort by name, size, date -- again flips" | "reverse the order" | "show or hide hidden files" | "" |
  "TABS" | "to that tab -- made, at home, if new" | "that tab here, where you are" | "new tab here · close this one" | "" |
  "THE PLACES COLUMN" | "go there" | "forget the bookmark" | "bookmark the folder you are in" ]

CONST @CONST C1 HELP_R_KEYS{} = [
  "#" | "V" | "y · d · p" | "D · Delete" | "u" | "X" | "r · n" | "E" | "o" | "Esc" | "" |
  "#" | "click · double-click" | "Shift-click" | "right-click" | "wheel" | "middle-click a tab" | "click a part of the path" | "" |
  "#" | "?" | "q · Ctrl-C" | "Q" ]
CONST @CONST C1 HELP_R_WHAT{} = [
  "FILES" | "choose the rows from here to the cursor" | "copy · cut · paste here" | "to the trash" | "put the last trashed back" | "delete for good, asked first" | "rename · new folder" | "unpack an archive into a folder" | "open with … -- 1 to 9 picks, e types" | "end choosing; clear the filter" | "" |
  "THE MOUSE" | "the cursor there · open it" | "choose from the cursor to there" | "a row's actions" | "scroll" | "close it" | "go to that folder" | "" |
  "THE REST" | "this help -- ?, Esc or q closes it" | "quit" | "quit, the shell to this folder (pluf --init)" ]

CONST I32 HELP_L = COUNT [ HELP_L_KEYS ]
CONST I32 HELP_R = COUNT [ HELP_R_KEYS ]
STATIC_ASSERT [ COUNT [ HELP_L_WHAT ] == HELP_L && COUNT [ HELP_R_WHAT ] == HELP_R | "what each key does, for each" ]

CONST I32 HELP_KEYS_W = 26      ; the keys' cells, what they do after them
CONST I32 HELP_HALF_W = 78      ; a column's: two side by side from twice this

; one line: a heading, a gap, or keys and what they do, `w` cells
ABYSS help_item: [ @Ui ui | @CONST C1 keys | @CONST C1 what | I32 w ]
 | IF [ (str_eq)[ keys | "#" ] ]
 |  | (ui.put_cell)[ (bold)[ AMBER ] | what | w | TRUE ]
 |  | RET []
 |  \_
 | (ui.put_cell)[ (fg)[ C_KEY ] | keys | HELP_KEYS_W | TRUE ]
 | (ui.put_cell)[ (fg)[ TEXT ] | what | w - HELP_KEYS_W | TRUE ]
 \_

; the help, in the columns' place
ABYSS help_screen: [ @Ui ui | @App a ]
 | U32 id = (ui.id)[ "help" ]
 | B1 two = ui.cols >= 2 * HELP_HALF_W + 4
 | I32 rows = SELECT [ two | SELECT [ HELP_L > HELP_R | HELP_L | HELP_R ] | HELP_L + 1 + HELP_R ]
 |
 | ; j k and g G as the lists have them; the area does the arrows and pages
 | IF [ (ui.focused)[ id ] ]
 |  | IF [ (ui.take)[ 'j' AS U32 ] ]
 |  |  | a.help_sc.top += 1
 |  | ELIF [ (ui.take)[ 'k' AS U32 ] ]
 |  |  | a.help_sc.top -= 1
 |  | ELIF [ (ui.take)[ 'G' AS U32 ] ]
 |  |  | a.help_sc.top = rows
 |  | ELIF [ (ui.take)[ 'g' AS U32 ] ]
 |  |  | a.help_sc.top = 0
 |  |  \_
 |  \_
 |
 | (ui.box)[ "HELP" | GROW | GROW ]
 | (ui.subtitle)[]
 | (ui.put)[ (fg)[ DIM ] | "? · Esc · q to close" ]
 | (ui.scroll_area)[ @(a.help_sc) | id | GROW | GROW ]
 | IF [ two ]
 |  | FOR [ I32 i = 0 | i < rows | i += 1 ]
 |  |  | (ui.text)[ GROW | 1 ]
 |  |  | IF [ i < HELP_L ]
 |  |  |  | (help_item)[ ui | HELP_L_KEYS{i} | HELP_L_WHAT{i} | HELP_HALF_W ]
 |  |  | ELSE
 |  |  |  | (ui.spaces)[ HELP_HALF_W ]
 |  |  |  \_
 |  |  | (ui.spaces)[ 4 ]
 |  |  | IF [ i < HELP_R ]
 |  |  |  | (help_item)[ ui | HELP_R_KEYS{i} | HELP_R_WHAT{i} | HELP_HALF_W ]
 |  |  |  \_
 |  |  \_
 | ELSE
 |  | I32 w = ui.cols - 6
 |  | FOR [ I32 i = 0 | i < HELP_L | i += 1 ]
 |  |  | (ui.text)[ GROW | 1 ]
 |  |  | (help_item)[ ui | HELP_L_KEYS{i} | HELP_L_WHAT{i} | w ]
 |  |  \_
 |  | (ui.text)[ GROW | 1 ]
 |  | FOR [ I32 i = 0 | i < HELP_R | i += 1 ]
 |  |  | (ui.text)[ GROW | 1 ]
 |  |  | (help_item)[ ui | HELP_R_KEYS{i} | HELP_R_WHAT{i} | w ]
 |  |  \_
 |  \_
 | (ui.close)[]
 | (ui.close)[]
 \_
