; root.pl -- the parent column: the folder around the current one, and in it
; the current one in amber. Hidden entries are left out, unless the current
; folder is one. A folder opened here (l, →, Enter) is the current one next,
; and the main column has the keys: on the amber row that is only the
; second. Going up is a step up

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

; `go`: the folder it asks to go to, if one was opened or left
ABYSS root_pane: [ @Ui ui | @RootPane p | @CONST C1 cwd | @String go ]
 | (update_root)[ p | cwd ]
 | U32 id = (ui.id)[ "root" ]
 | I32 n = (p.files.size)[] AS I32
 |
 | IF [ (ui.focused)[ id ] ]
 |  | (move_keys)[ ui | @(p.list) ]
 |  | I32 how = (go_keys)[ ui ]
 |  | @CONST FileRecord e = (record_at)[ @(p.files) | p.list.cursor ]
 |  | (ask_go)[ go | how | cwd | (p.dir.cstr)[] | e ]
 |  | ; into a folder, as the parent column of ranger: that folder opened,
 |  | ; and the main column takes the keys -- on the current one's row only
 |  | ; the second, it is open already
 |  | IF [ how == GO_IN && e != NULL && e.dir && !(e.broken) && e.count >= 0 ]
 |  |  | (ui.set_focus)[ (ui.id)[ "main" ] ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  \_
 |
 | ; the list's width is known from the last frame
 | I32 width = (name_width)[ (ui.rect_of)[ id ].w ]
 |
 | (ui.box)[ (p.title.cstr)[] | (pct)[ CFG.root_width ] | GROW ]
 | (ui.list)[ @(p.list) | id | n | GROW | GROW ]
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | (ui.list_row)[ @(p.list) | i | id ]
 |  | (folder_row)[ ui | (p.files.at)[ i AS USIZE ] | i == p.list.cursor | i == p.here | width ]
 |  \_
 | (ui.end)[]
 | (ui.close)[]
 \_
