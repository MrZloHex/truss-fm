; root.pl -- the parent column: the folder around the current one, and in it
; the current one in amber. Hidden entries are left out, unless the current
; folder is one. l and → on a folder go into it: the current one becomes the
; first folder in it, and this column keeps the keys. Enter and a double-click
; open the folder itself and the main column has the keys. Going up is a step up

USE <std/core/core.pl>
USE <std/alloc/string.pl>

USE <modular.pl>
!USES <common.pl>
!USES <../core/fs.pl>
!USES <../core/config.pl>


TYPE RootPane: STRUCT
 | ListState list
 | String cwd               ; the folder it was read for
 | String dir               ; the one around it, that it lists
 | String title             ; that one's name, in capitals
 | I32 here                 ; the row of `cwd`; -1: none, at /
 | Vector<FileRecord> files
 \_

ABYSS dispose_root: [ @RootPane p ]
 | (p.cwd.deinit)[]
 | (p.dir.deinit)[]
 | (p.title.deinit)[]
 | (records_free)[ @(p.files) ]
 \_

; read again only when the current folder is another one
ABYSS update_root: [ @RootPane p | @CONST C1 cwd ]
 | IF [ (p.cwd.equals)[ cwd ] ]
 |  | RET []
 |  \_
 | (p.cwd.deinit)[]
 | p.cwd = (String.of)[ cwd ]
 |
 | (p.dir.deinit)[]
 | p.dir = (get_parent_path)[ cwd ]
 | String here = (get_dirname)[ cwd ]
 | POSTLUDE (here.deinit)[]
 |
 | (p.title.deinit)[]
 | p.title = (folder_title)[ (p.dir.cstr)[] ]
 | (read_folder)[ @(p.files) | (p.dir.cstr)[] | CFG.hidden && CFG.root_hidden | (here.cstr)[] ]
 |
 | p.here = -1
 | FOR [ USIZE i = 0 | i < (p.files.size)[] | i += 1 ]
 |  | IF [ (here.equals)[ ((p.files.at)[i].name.cstr)[] ] ]
 |  |  | p.here = i AS I32
 |  |  \_
 |  \_
 | ; the cursor starts on it, and is the keys' from here on
 | p.list.cursor = SELECT [ p.here >= 0 | p.here | 0 ]
 \_

; the folder `e` of `dir` opened, if it can be read: it is the one asked for
; and the main column takes the focus
ABYSS root_open: [ @Ui ui | @String go | @CONST C1 dir | @CONST FileRecord e ]
 | IF [ e != NULL && e.dir && !(e.broken) && e.count >= 0 ]
 |  | (ask_go)[ go | GO_IN | "" | dir | e ]
 |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  | (ui.redo)[]
 |  \_
 \_

; into the folder `e` of `dir`, as the parent column of ranger does: the
; current folder becomes the first folder in it, so this column lists `e` and
; keeps the focus. With no folder to enter in it, `e` itself is the one asked
; for and the main column takes the focus. Only `e` is read, and only now
ABYSS root_into: [ @Ui ui | @String go | @CONST C1 dir | @CONST FileRecord e ]
 | IF [ e == NULL || !(e.dir) || e.broken || e.count < 0 ]
 |  | RET []
 |  \_
 | C1 path{4096}
 | BufferSink b = (BufferSink.over)[ path | 4096 ]
 | (b.print)[ SELECT [ (str_eq)[ dir | "/" ] | "%s%s" | "%s/%s" ] | dir | (e.name.cstr)[] ]
 | IF [ !((first_subfolder)[ go | path AS @CONST C1 | CFG.hidden && CFG.root_hidden ]) ]
 |  | (go.deinit)[]
 |  | ?go = (String.of)[ path AS @CONST C1 ]
 |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  \_
 | (ui.redo)[]
 \_

; `go`: the folder it asks to go to, if one was opened or left
ABYSS root_pane: [ @Ui ui | @RootPane p | @CONST C1 cwd | @String go ]
 | (update_root)[ p | cwd ]
 | U32 id = (ui.id)[ "root" ]
 | I32 n = (p.files.size)[] AS I32
 |
 | IF [ (ui.focused)[ id ] ]
 |  | (move_keys)[ ui | @(p.list) ]
 |  | @CONST FileRecord e = (record_at)[ @(p.files) | p.list.cursor ]
 |  | ; Enter opens the folder; l and → are a step down here, not in the main column
 |  | IF [ (ui.take)[ KEY_ENTER ] ]
 |  |  | (root_open)[ ui | go | (p.dir.cstr)[] | e ]
 |  | ELSE
 |  |  | I32 how = (go_keys)[ ui ]
 |  |  | IF [ how == GO_IN ]
 |  |  |  | (root_into)[ ui | go | (p.dir.cstr)[] | e ]
 |  |  | ELSE
 |  |  |  | (ask_go)[ go | how | cwd | (p.dir.cstr)[] | e ]
 |  |  |  \_
 |  |  \_
 |  \_
 |
 | ; the list's width is known from the last frame
 | I32 width = (name_width)[ (ui.rect_of)[ id ].w ]
 |
 | ((ui.box)[ (p.title.cstr)[] | (pct)[ CFG.root_width ] | GROW ].pads)[ ui.theme.box_pad | 0 | 0 | 0 ]
 | (ui.list)[ @(p.list) | id | n | GROW | GROW ]
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | (ui.list_row)[ @(p.list) | i | id ]
 |  | (folder_row)[ ui | (p.files.at)[ i AS USIZE ] | i == p.list.cursor | i == p.here | width ]
 |  \_
 | (ui.end)[]
 | (ui.close)[]
 |
 | ; a double press on a folder: as Enter
 | IF [ (press_row)[ ui | id | @(p.list) | BTN_LEFT | 2 ] == p.list.cursor ]
 |  | @CONST FileRecord e = (record_at)[ @(p.files) | p.list.cursor ]
 |  | (root_open)[ ui | go | (p.dir.cstr)[] | e ]
 |  \_
 \_
