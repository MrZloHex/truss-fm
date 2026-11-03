; app.pl -- what the program keeps between frames: the folder it is in, the
; disk under it, and each column's own state

USE <std/core/core.pl>
USE <std/alloc/string.pl>

!USES <fs.pl>
!USES <ui/places.pl>
!USES <ui/root.pl>
!USES <ui/main.pl>
!USES <ui/preview.pl>

TYPE Partition: STRUCT
 | String name              ; /dev/nvme0n1p2
 | F32 usage                ; how full, in percent
 | F64 free                 ; GiB
 \_

TYPE AppData: STRUCT
 | U32 tab
 | String cwd               ; where it is, in full
 | String rel_cwd           ; the same with ~ for home
 | Partition partition
 | I32 cols                 ; the screen the last frame was built for
 | I32 rows
 |
 | PlacesPane  places
 | RootPane    root
 | MainPane    listing
 | PreviewPane preview
 \_

IFACE AppOps: [ @AppData me ]
 | ABYSS dispose: []
 |  | (me.cwd.deinit)[]
 |  | (me.rel_cwd.deinit)[]
 |  | (me.partition.name.deinit)[]
 |  | (dispose_root)[ @(me.root) ]
 |  | (dispose_main)[ @(me.listing) ]
 |  | (dispose_preview)[ @(me.preview) ]
 |  \_
 |
 + ANONYMOUS:
 | Self make: [ String cwd ]
 |  | Self s
 |  | @CONST C1 at = (cwd.cstr)[]
 |  | s.cwd = cwd
 |  | s.rel_cwd = (get_shorter_path)[ at ]
 |  |
 |  | ; what cannot be found of the disk is shown as nothing, not a crash
 |  | Option<String> name = (get_phy_part_name)[ at ]
 |  | IF [ (name.is_some)[] ]
 |  |  | s.partition.name = (name.unwrap)[]
 |  | ELSE
 |  |  | s.partition.name = (String.of)[ "?" ]
 |  |  \_
 |  | s.partition.usage = ((get_phy_part_usage)[ at ].unwrap_or)[ 0.0 ]
 |  | s.partition.free  = ((get_phy_part_free)[ at ].unwrap_or)[ 0.0 ]
 |  | RET [ s ]
 |  \_
 \_

CLASS App: AppData IMPL [ AppOps ]
