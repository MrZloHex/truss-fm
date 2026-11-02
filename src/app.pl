
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
 | Partition partition
 \_

IFACE AppOps: [ @AppData me ]
 | ABYSS dispose: []
 |  | (me.partition.name.deinit)[]
 |  \_
 | 
 + ANONYMOUS:
 | Self make: [ @CONST C1 cwd ]
 |  | Self s
 |  | s.partition.name  = ((get_phy_part_name)[ cwd ].unwrap)[]
 |  | s.partition.usage = ((get_phy_part_usage)[ cwd ].unwrap)[]
 |  | s.partition.free  = ((get_phy_part_free)[ cwd ].unwrap)[]
 |  | RET [ s ]
 |  \_
 \_

CLASS App: AppData IMPL [ AppOps ]
