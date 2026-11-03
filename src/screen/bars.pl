; bars.pl -- the lines around the columns: § FILES and the tabs and the
; disk at the top, the path and what the clipboard holds under it, the keys
; at the bottom. Each fits what it shows to the width it has

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

USE <modular.pl>
!USES <../ui/look.pl>
!USES <../app/app.pl>

; how many cells `s` takes: its characters, not its bytes
I32 cells: [ @CONST C1 s ]
 | I32 n = 0
 | FOR [ USIZE i = 0 | s{i} != '\0' | i += 1 ]
 |  | IF [ ((s{i} AS U8) & 0xC0) != 0x80 ]
 |  |  | n += 1
 |  |  \_
 |  \_
 | RET [ n ]
 \_

; § FILES, the tabs, and at the far end the disk. A tab clicked: in `want`
ABYSS top_bar: [ @Ui ui | @App a | @I32 want ]
 | @Node bar = (ui.row)[ GROW | 1 ]
 | (bar.spacing)[ 1 ]
 | (bar.background)[ BAR ]
 |
 | (ui.text)[ FIT | 1 ]
 | (ui.put)[ (bold)[ AMBER ] | "§ FILES" ]
 | (ui.space)[ 4 | 1 ]
 |
 | FOR [ USIZE i = 0 | i < (a.tabs.size)[] | i += 1 ]
 |  | U32 id = (ui.idn)[ "tab" | i AS I32 ]
 |  | B1 on = a.tab == (i AS U32)
 |  | C1 label{64}
 |  | BufferSink b = (BufferSink.over)[ label | 64 ]
 |  | (b.print)[ "[%d] %s" | (i AS I32) + 1 | ((a.tabs.at)[ i ].label.cstr)[] ]
 |  | @Node t = (ui.text)[ FIT | 1 ]
 |  | (t.with_id)[ id ]
 |  | (t.pad)[ 1 | 0 ]
 |  | (t.background)[ SELECT [ on | AMBER | SEL ] ]
 |  | (ui.cursor_on)[ id | CUR_HAND ]
 |  | (ui.put)[ (fg)[ SELECT [ on | INK | TEXT2 ] ] | label AS @CONST C1 ]
 |  | IF [ (ui.clicked)[ id ] ]
 |  |  | ?want = i AS I32
 |  |  \_
 |  \_
 |
 | @Node disk = (ui.text)[ GROW | 1 ]
 | (disk.text_align)[ AL_END ]
 | (ui.put)[ (fg)[ TEXT ] | (a.partition.name.cstr)[] ]
 | (ui.put)[ (fg)[ DIM ] | " " ]
 | ((ui.pen)[ (bold)[ (disk_color)[ a.partition.usage AS I32 ] ] ].print)[ "%.0f%%" | a.partition.usage AS F64 ]
 | ((ui.pen)[ (fg)[ DIM ] ].print)[ " · free %.0f GB " | a.partition.free ]
 | (ui.close)[]
 \_

CONST @CONST C1 PATH_HINTS = "[/] filter · ['] jump · [b] bookmark · [.] hidden · [~] home"

; > the path, what is in the clipboard, a note, and at the far end the keys
; -- those left out first when the line is too short for all
ABYSS path_bar: [ @Ui ui | @App a ]
 | C1 status{512}
 | BufferSink st = (BufferSink.over)[ status | 512 ]
 | IF [ (a.clip.size)[] > 0 ]
 |  | (st.print)[ "   clipboard: %d %s" | (a.clip.size)[] AS I32 | SELECT [ a.clip_cut | "to move" | "to copy" ] ]
 |  \_
 | B1 noting = (a.note.size)[] > 0 && (now_ms)[] - a.note_at < NOTE_MS
 | IF [ noting ]
 |  | (st.print)[ "   %s" | (a.note.cstr)[] ]
 |  \_
 | B1 typing = a.prompt == PR_FILTER
 | B1 filtered = (a.listing.filter.size)[] > 0
 | I32 used = 3 + (cells)[ (a.rel_cwd.cstr)[] ] + SELECT [ a.places.jump | 4 | 0 ] + (cells)[ status AS @CONST C1 ]
 | IF [ filtered ]
 |  | used += 16 + (cells)[ (a.listing.filter.cstr)[] ]
 |  \_
 | B1 hints = !typing && used + 4 + (cells)[ PATH_HINTS ] + 1 <= ui.cols
 |
 | @Node bar = (ui.row)[ GROW | 1 ]
 | (bar.spacing)[ 1 ]
 | (ui.space)[ 1 | 1 ]
 | (ui.text)[ FIT | 1 ]
 | (ui.put)[ (fg)[ AMBER ] | "> " ]
 | (ui.put)[ (fg)[ TEXT ] | (a.rel_cwd.cstr)[] ]
 | IF [ a.places.jump ]
 |  | (ui.put)[ (bold)[ AMBER ] | "  '_" ]
 |  \_
 | ; the filter: typed here, or kept, with how to give it up
 | IF [ typing ]
 |  | (ui.put)[ (bold)[ C_MATCH ] | "   / " ]
 |  | I32 got = (ui.input)[ @(a.filter_field) | (ui.id)[ "filter" ] | 24 | "filter" ]
 |  | IF [ got == IN_CHANGED ]
 |  |  | (main_filter)[ @(a.listing) | (input_text)[ @(a.filter_field) ] ]
 |  |  | (ui.redo)[]
 |  | ELIF [ got == IN_SUBMIT ]
 |  |  | a.prompt = PR_NONE
 |  |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  | (ui.text)[ FIT | 1 ]
 |  | (ui.put)[ (fg)[ DIM ] | " [enter] keep · [esc] clear · [↑↓] move" ]
 | ELIF [ filtered ]
 |  | (ui.put)[ (bold)[ C_MATCH ] | "   /" ]
 |  | (ui.put)[ (bold)[ C_MATCH ] | (a.listing.filter.cstr)[] ]
 |  | (ui.put)[ (fg)[ DIM ] | "  [esc] clear" ]
 |  \_
 | IF [ (a.clip.size)[] > 0 ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "   clipboard: %d %s" | (a.clip.size)[] AS I32 | SELECT [ a.clip_cut | "to move" | "to copy" ] ]
 |  \_
 | IF [ noting ]
 |  | (ui.put)[ (fg)[ TEXT ] | "   " ]
 |  | (ui.put)[ (fg)[ TEXT ] | (a.note.cstr)[] ]
 |  \_
 | IF [ hints ]
 |  | (ui.space)[ 4 | 1 ]
 |  | @Node keys = (ui.text)[ GROW | 1 ]
 |  | (keys.text_align)[ AL_END ]
 |  | (ui.put)[ (fg)[ DIM ] | PATH_HINTS ]
 |  | (ui.space)[ 1 | 1 ]
 |  \_
 | (ui.close)[]
 \_

; the keys, the most wanted first: as many as the line holds
CONST @CONST C1 HOT_KEYS{} = [ "[hjkl]" | "[o]" | "[V]" | "[y]" | "[d]" | "[p]" | "[D]" | "[u]" | "[X]" | "[r]" | "[n]" | "[1-9]" | "[t]" | "[x]" | "[q]" ]
CONST @CONST C1 HOT_WHAT{} = [ " move, open" | " open with" | " select" | " copy" | " cut" | " paste" | " trash" | " untrash" | " delete" | " rename" | " new folder" | " tab" | " new tab" | " close tab" | " quit" ]
CONST I32 NHOT = COUNT [ HOT_KEYS ]
CONST I32 HOT_GAP = 3

ABYSS hotkeys: [ @Ui ui | @App a ]
 | (ui.text)[ GROW | 1 ]
 | I32 room = ui.cols - 1
 | ; q, to quit, keeps its place at the end whatever else goes
 | I32 quit = (cells)[ HOT_KEYS{NHOT - 1} ] + (cells)[ HOT_WHAT{NHOT - 1} ]
 | I32 used = 1 + quit
 | (ui.put)[ (fg)[ TEXT ] | " " ]
 | FOR [ I32 i = 0 | i < NHOT - 1 | i += 1 ]
 |  | I32 w = (cells)[ HOT_KEYS{i} ] + (cells)[ HOT_WHAT{i} ] + HOT_GAP
 |  | IF [ used + w > room ]
 |  |  | BREAK
 |  |  \_
 |  | (ui.put)[ (fg)[ AMBER ] | HOT_KEYS{i} ]
 |  | (ui.put)[ (fg)[ TEXT ] | HOT_WHAT{i} ]
 |  | (ui.put)[ (fg)[ TEXT ] | "   " ]
 |  | used += w
 |  \_
 | (ui.put)[ (fg)[ AMBER ] | HOT_KEYS{NHOT - 1} ]
 | (ui.put)[ (fg)[ TEXT ] | HOT_WHAT{NHOT - 1} ]
 \_

