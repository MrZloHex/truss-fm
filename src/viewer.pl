
USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

USE <modular.pl>
!USES <app.pl>

TYPE RootPane: STRUCT
 | ListState list
 | String cwd
 | Vector<DirEntry> files
 \_



ABYSS update_root: [ @RootPane p | String cwd ]
 | IF [ (p.cwd.equals)[(cwd.cstr)[]] ]
 |  | RET []
 |  \_
 |
 | Result<os:Dir | IoError> d = (os:Dir.open)[ (cwd.cstr)[] ]
 | IF [ (d.is_err)[] ]
 |  | RET [ ]
 |  \_
 | os:Dir dir = (d.unwrap)[]
 | POSTLUDE (dir.close)[]
 |
 | DirEntry e
 | WHILE [ (dir.next)[ @e ] ]
 |  | (p.files.push)[e]
 |  \_
 | 
 | p.cwd = cwd
 \_

ABYSS root_pane: [ @Ui ui | @RootPane p | String cwd ]
 | (update_root)[ p | cwd ] 
 |
 | (ui.box)[ ((get_dirname)[(cwd.cstr)[]].cstr)[] | (pct)[20] | GROW ]
 | 
 | U32 id = (ui.id)[ "root" ]
 | (ui.list)[ @(p.list) | id | (p.files.size)[] | GROW | GROW ]
 | FOR [ USIZE i = 0 | i < (p.files.size)[] | i += 1 ]
 |  | @DirEntry e = (p.files.at)[i]
 |  | (ui.list_row)[ @(p.list) | i | id ]
 |  | (ui.put)[ (fg)[ AMBER ] | e.name ]
 |  \_
 | (ui.end)[]
 | (ui.close)[]
 \_

ABYSS main_pane: [ @Ui ui | @App a ]
 | (ui.box)[ "MAIN" | GROW | GROW ]
 | 
 | (ui.close)[]
 \_
