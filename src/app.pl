
USE <std/alloc/string.pl>

!USES <fs.pl>

TYPE Partition: STRUCT
 | String name
 | F32 usage
 | F64 free
 \_

TYPE AppData: STRUCT
 | U32 tab
 |
 | String cwd
 | String rel_cwd
 | Partition partition
 \_

IFACE AppOps: [ @AppData me ]
 | ABYSS dispose: []
 |  | (me.partition.name.deinit)[]
 |  | (me.cwd.deinit)[]
 |  | (me.rel_cwd.deinit)[]
 |  \_
 | 
 + ANONYMOUS:
 | Self make: [ String cwd ]
 |  | Self s
 |  | s.cwd = cwd
 |  | s.rel_cwd = (get_shorter_path)[ (cwd.cstr)[] ]
 |  | s.partition.name  = ((get_phy_part_name)[ (cwd.cstr)[] ].unwrap)[]
 |  | s.partition.usage = ((get_phy_part_usage)[ (cwd.cstr)[] ].unwrap)[]
 |  | s.partition.free  = ((get_phy_part_free)[ (cwd.cstr)[] ].unwrap)[]
 |  | RET [ s ]
 |  \_
 \_

CLASS App: AppData IMPL [ AppOps ]
