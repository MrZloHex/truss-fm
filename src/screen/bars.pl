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
!USES <../ui/preview.pl>
!USES <../core/sys.pl>

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
 |  | (b.print)[ "[%d] %s" | (a.tabs.at)[ i ].slot | ((a.tabs.at)[ i ].label.cstr)[] ]
 |  | @Node t = (ui.text)[ FIT | 1 ]
 |  | (t.with_id)[ id ]
 |  | (t.pad)[ 1 | 0 ]
 |  | (t.background)[ SELECT [ on | AMBER | SEL ] ]
 |  | (ui.cursor_on)[ id | CUR_HAND ]
 |  | (ui.put)[ (fg)[ SELECT [ on | INK | TEXT2 ] ] | label AS @CONST C1 ]
 |  | IF [ (ui.clicked)[ id ] ]
 |  |  | ?want = i AS I32
 |  |  \_
 |  | ; the middle button closes it
 |  | I32 mx = 0
 |  | I32 my = 0
 |  | IF [ (ui.pressed_in)[ id | BTN_MIDDLE | @mx | @my ] ]
 |  |  | a.close_tab = i AS I32
 |  |  \_
 |  \_
 | ; [+]: a new tab, as t
 | IF [ (a.tabs.size)[] < MAX_TABS ]
 |  | U32 plus = (ui.id)[ "tab-new" ]
 |  | @Node pn = (ui.text)[ FIT | 1 ]
 |  | (pn.with_id)[ plus ]
 |  | (ui.cursor_on)[ plus | CUR_HAND ]
 |  | (ui.put)[ (fg)[ DIM ] | "[+]" ]
 |  | IF [ (ui.clicked)[ plus ] ]
 |  |  | (str_copy)[ a.clicked | 16 | "t" ]
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


; > the path, what is in the clipboard, a note, and at the far end the keys
; -- those left out first when the line is too short for all
; the path, a part at a time: a click on one goes to that folder, in `go`
ABYSS crumbs: [ @Ui ui | @App a | @String go | I32 room ]
 | @CONST C1 rel = (a.rel_cwd.cstr)[]
 | ; longer than `room`: its first parts left out, … in their place -- the
 | ; end, the folder you are in, is the part that has to show
 | I32 skip = 0
 | IF [ (cells)[ rel ] > room ]
 |  | I32 slashes = 0
 |  | FOR [ USIZE c = 1 | rel{c} != '\0' | c += 1 ]
 |  |  | IF [ rel{c - 1} == '/' ]
 |  |  |  | slashes += 1
 |  |  |  \_
 |  |  | IF [ rel{c} == '/' && (cells)[ rel + c ] + 1 <= room ]
 |  |  |  | skip = slashes + 1
 |  |  |  | BREAK
 |  |  |  \_
 |  |  \_
 |  \_
 | C1 full{4096}
 | USIZE n = 0
 | USIZE i = 0
 | IF [ rel{0} == '~' ]
 |  | n = (str_copy)[ full | 4096 | ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  | i = 1
 |  \_
 | I32 k = 0
 | LOOP
 |  | ; the part from i to the next / -- "~" or "" (the root) the first
 |  | USIZE j = i
 |  | WHILE [ rel{j} != '\0' && rel{j} != '/' ]
 |  |  | j += 1
 |  |  \_
 |  | C1 part{512}
 |  | USIZE m = 0
 |  | IF [ k == 0 && rel{0} == '~' ]
 |  |  | part{0} = '~'
 |  |  | m = 1
 |  | ELIF [ k == 0 && j == 0 ]
 |  |  | part{0} = '/'
 |  |  | m = 1
 |  | ELSE
 |  |  | FOR [ USIZE x = i | x < j && m + 1 < 512 | x += 1 ]
 |  |  |  | part{m} = rel{x}
 |  |  |  | m += 1
 |  |  |  \_
 |  |  | IF [ n + 1 < 4096 && (n == 0 || full{n - 1} != '/') ]
 |  |  |  | full{n} = '/'
 |  |  |  | n += 1
 |  |  |  \_
 |  |  | FOR [ USIZE x = i | x < j && n + 1 < 4096 | x += 1 ]
 |  |  |  | full{n} = rel{x}
 |  |  |  | n += 1
 |  |  |  \_
 |  |  \_
 |  | part{m} = '\0'
 |  | full{n} = '\0'
 |  | IF [ n == 0 ]
 |  |  | full{0} = '/'
 |  |  | full{1} = '\0'
 |  |  | n = 1
 |  |  \_
 |  | IF [ k == skip && skip > 0 ]
 |  |  | (ui.text)[ FIT | 1 ]
 |  |  | (ui.put)[ (fg)[ DIM ] | "…/" ]
 |  |  \_
 |  | IF [ m > 0 && k >= skip ]
 |  |  | U32 id = (ui.idn)[ "crumb" | k ]
 |  |  | @Node t = (ui.text)[ FIT | 1 ]
 |  |  | (t.with_id)[ id ]
 |  |  | (ui.cursor_on)[ id | CUR_HAND ]
 |  |  | B1 last = rel{j} == '\0'
 |  |  | (ui.put)[ (fg)[ SELECT [ (ui.hovered)[ id ] && !last | AMBER | TEXT ] ] | part AS @CONST C1 ]
 |  |  | IF [ (ui.clicked)[ id ] && !last ]
 |  |  |  | (go.deinit)[]
 |  |  |  | ?go = (String.of)[ full AS @CONST C1 ]
 |  |  |  \_
 |  |  \_
 |  | IF [ rel{j} == '\0' ]
 |  |  | BREAK
 |  |  \_
 |  | ; the / between, when the part before was not the root's own
 |  | IF [ !(k == 0 && j == 0) && k >= skip ]
 |  |  | (ui.text)[ FIT | 1 ]
 |  |  | (ui.put)[ (fg)[ DIM ] | "/" ]
 |  |  \_
 |  | i = j + 1
 |  | k += 1
 |  \_
 \_

ABYSS path_bar: [ @Ui ui | @App a | @String go ]
 | B1 typing = a.prompt == PR_FILTER
 | B1 filtered = (a.listing.filter.size)[] > 0
 |
 | @Node bar = (ui.row)[ GROW | 1 ]
 | (bar.spacing)[ 1 ]
 | (ui.space)[ 1 | 1 ]
 | (ui.text)[ FIT | 1 ]
 | (ui.put)[ (fg)[ AMBER ] | "> " ]
 | ; the parts close together, not spaced as the bar's are
 | @Node path = (ui.row)[ FIT | 1 ]
 | (path.spacing)[ 0 ]
 | ; the room it has: what the filter, the jump mark and [?] help leave it
 | I32 room = ui.cols - 18 - SELECT [ a.places.jump | 4 | 0 ]
 | IF [ typing ]
 |  | room -= 70
 | ELIF [ filtered ]
 |  | room -= 18 + (cells)[ (a.listing.filter.cstr)[] ]
 |  \_
 | (crumbs)[ ui | a | go | SELECT [ room < 12 | 12 | room ] ]
 | (ui.close)[]
 | (ui.text)[ FIT | 1 ]
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
 | ; at the far end, where help is -- a click opens it too
 | U32 hid = (ui.id)[ "help-hint" ]
 | @Node keys = (ui.text)[ GROW | 1 ]
 | (keys.with_id)[ hid ]
 | (keys.text_align)[ AL_END ]
 | (ui.cursor_on)[ hid | CUR_HAND ]
 | (ui.put)[ (fg)[ AMBER ] | "[?]" ]
 | (ui.put)[ (fg)[ DIM ] | " help " ]
 | IF [ (ui.clicked)[ hid ] ]
 |  | (str_copy)[ a.clicked | 16 | "?" ]
 |  \_
 | (ui.close)[]
 \_


; --- the status line ---------------------------------------------------------------

; the bottom line: on the left the file under the cursor -- its mode, size,
; time, and where a link points -- in the middle what the program has to
; say, on the right the clipboard, what V chose, and where the cursor is
ABYSS status_line: [ @Ui ui | @App a ]
 | @MainPane m = @(a.listing)
 | I32 n = (m.files.size)[] AS I32
 | I32 at = m.table.list.cursor
 | @FileRecord e = (record_at)[ @(m.files) | at ]
 |
 | @Node bar = (ui.row)[ GROW | 1 ]
 | (bar.spacing)[ 2 ]
 | (ui.space)[ 0 | 1 ]
 | (ui.text)[ FIT | 1 ]
 | IF [ e != NULL ]
 |  | String path = (main_path)[ m | at ]
 |  | Result<FileInfo | IoError> li = (fs_link_info)[ (path.cstr)[] ]
 |  | ; not SELECT: an unwrap of a file gone since would trap
 |  | B1 link = FALSE
 |  | U32 bits = 0
 |  | I64 when = e.modified
 |  | IF [ (li.is_ok)[] ]
 |  |  | FileInfo own = (li.unwrap)[]
 |  |  | link = own.kind == FS_LINK
 |  |  | bits = own.mode
 |  |  | IF [ link ]
 |  |  |  | ; a link's own time: a broken one has no other
 |  |  |  | when = own.modified
 |  |  |  \_
 |  |  \_
 |  | C1 mode{12}
 |  | (mode_text)[ mode | bits | e.dir | link ]
 |  | (ui.put)[ (fg)[ DIM ] | mode AS @CONST C1 ]
 |  | C1 size{16}
 |  | (side_text)[ size | e ]
 |  | ((ui.pen)[ (fg)[ TEXT ] ].print)[ "  %s%s" | size AS @CONST C1 | SELECT [ e.dir | " entries" | "" ] ]
 |  | DateTime d = (local_date)[ when ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "  %04d-%02d-%02d %02d:%02d" | d.year AS I32 | d.month AS I32 | d.day AS I32 | d.hour AS I32 | d.minute AS I32 ]
 |  | IF [ link ]
 |  |  | C1 to{1024}
 |  |  | ISIZE k = (px_readlink)[ (path.cstr)[] | to | 1023 ]
 |  |  | IF [ k >= 0 ]
 |  |  |  | to{k} = '\0'
 |  |  |  | (ui.put)[ (fg)[ SELECT [ e.broken | C_BROKEN | C_DIR ] ] | "  → " ]
 |  |  |  | (ui.put)[ (fg)[ SELECT [ e.broken | C_BROKEN | C_DIR ] ] | to AS @CONST C1 ]
 |  |  |  \_
 |  |  \_
 |  | (path.deinit)[]
 | ELSE
 |  | (ui.put)[ (fg)[ DIM ] | "empty" ]
 |  \_
 |
 | ; what the program has to say, for a while
 | @Node said = (ui.text)[ GROW | 1 ]
 | (said.text_align)[ AL_CENTER ]
 | IF [ (a.note.size)[] > 0 && (now_ms)[] - a.note_at < NOTE_MS ]
 |  | (ui.put)[ (fg)[ AMBER ] | (a.note.cstr)[] ]
 |  \_
 |
 | (ui.text)[ FIT | 1 ]
 | IF [ (a.clip.size)[] > 0 ]
 |  | ((ui.pen)[ (fg)[ DIM ] ].print)[ "%d %s   " | (a.clip.size)[] AS I32 | SELECT [ a.clip_cut | "to move" | "to copy" ] ]
 |  \_
 | I32 lo = 0
 | I32 hi = 0
 | IF [ (chosen_rows)[ m | @lo | @hi ] ]
 |  | ; what V chose: how many, and the files' bytes
 |  | U64 bytes = 0
 |  | FOR [ I32 i = lo | i <= hi | i += 1 ]
 |  |  | @FileRecord r = (record_at)[ @(m.files) | i ]
 |  |  | IF [ r != NULL && !(r.dir) ]
 |  |  |  | bytes += r.size
 |  |  |  \_
 |  |  \_
 |  | C1 sz{16}
 |  | (size_text)[ sz | bytes ]
 |  | ((ui.pen)[ (fg)[ C_MARK ] ].print)[ "%d chosen · %s   " | hi - lo + 1 | sz AS @CONST C1 ]
 |  \_
 | IF [ !(CFG.hidden) ]
 |  | (ui.put)[ (fg)[ DIM ] | "hidden off   " ]
 |  \_
 | ((ui.pen)[ (fg)[ TEXT ] ].print)[ "%d/%d " | SELECT [ n > 0 | at + 1 | 0 ] | n ]
 | (ui.close)[]
 \_


