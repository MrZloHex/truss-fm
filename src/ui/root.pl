; root.pl -- the parent column: the folder around the current one, and in it
; the current one in amber. Hidden entries are left out, unless the current
; folder is one

USE <std/core/core.pl>
USE <std/alloc/string.pl>

USE <modular.pl>
!USES <common.pl>
!USES <../fs.pl>

CONST I32 ROOT_W_PERC = 25      ; its width, frame and all

TYPE RootPane: STRUCT
 | ListState list
 | String cwd               ; the folder it was read for
 | String title             ; the parent's name, in capitals
 | I32 here                 ; the row of `cwd`; -1: none, at /
 | Vector<FileRecord> files
 \_

ABYSS dispose_root: [ @RootPane p ]
 | (p.cwd.deinit)[]
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
 | String parent = (get_parent_path)[ cwd ]
 | POSTLUDE (parent.deinit)[]
 | String here = (get_dirname)[ cwd ]
 | POSTLUDE (here.deinit)[]
 |
 | (p.title.deinit)[]
 | p.title = (folder_title)[ (parent.cstr)[] ]
 | (read_folder)[ @(p.files) | (parent.cstr)[] | FALSE | (here.cstr)[] ]
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

ABYSS root_pane: [ @Ui ui | @RootPane p | @CONST C1 cwd ]
 | (update_root)[ p | cwd ]
 | U32 id = (ui.id)[ "root" ]
 | I32 n = (p.files.size)[] AS I32
 |
 | IF [ (ui.focused)[ id ] ]
 |  | IF [ (ui.take)[ 'j' AS U32 ] ]
 |  |  | p.list.cursor += 1
 |  | ELIF [ (ui.take)[ 'k' AS U32 ] ]
 |  |  | p.list.cursor -= 1
 |  |  \_
 |  \_
 |
 | ; the list's width is known from the last frame
 | I32 width = (name_width)[ (ui.rect_of)[ id ].w ]
 |
 | (ui.box)[ (p.title.cstr)[] | (pct)[ ROOT_W_PERC ] | GROW ]
 | (ui.list)[ @(p.list) | id | n | GROW | GROW ]
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | (ui.list_row)[ @(p.list) | i | id ]
 |  | (folder_row)[ ui | (p.files.at)[ i AS USIZE ] | i == p.list.cursor | i == p.here | width ]
 |  \_
 | (ui.end)[]
 | (ui.close)[]
 \_
