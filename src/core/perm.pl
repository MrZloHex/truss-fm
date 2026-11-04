; perm.pl -- what is typed for chmod and chown, worked out: a mode, octal
; (644, 0755) or symbolic clauses (u+x,go-w); a leading -R; an owner,
; user:group. Pure: no file is touched here

USE <std/core/core.pl>
USE <std/core/str.pl>

; the permission bits (and setuid, setgid, sticky) `spec` makes of `old`,
; into `out`. A folder's X counts as x. No who letter means all, whatever
; the umask says. FALSE: it is not a mode, `out` is left alone
B1 mode_apply: [ @CONST C1 spec | U32 old | B1 dir | @U32 out ]
 | USIZE n = (str_len)[ spec ]
 | IF [ n == 0 ]
 |  | RET [ FALSE ]
 |  \_
 |
 | ; octal: three or four digits
 | IF [ spec{0} >= '0' && spec{0} <= '7' ]
 |  | IF [ n < 3 || n > 4 ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | U32 v = 0
 |  | FOR [ USIZE i = 0 | i < n | i += 1 ]
 |  |  | IF [ spec{i} < '0' || spec{i} > '7' ]
 |  |  |  | RET [ FALSE ]
 |  |  |  \_
 |  |  | v = v * 8 + ((spec{i} - '0') AS U32)
 |  |  \_
 |  | ?out = v
 |  | RET [ TRUE ]
 |  \_
 |
 | ; symbolic: clauses split by commas, each who, then one or more op and perms
 | U32 mode = old & 0xFFF
 | USIZE i = 0
 | B1 more = TRUE
 | WHILE [ more ]
 |  | U32 who = 0           ; 1 u, 2 g, 4 o
 |  | B1 who_on = TRUE
 |  | WHILE [ who_on ]
 |  |  | C1 w = spec{i}
 |  |  | IF [ w == 'u' ]
 |  |  |  | who |= 1
 |  |  | ELIF [ w == 'g' ]
 |  |  |  | who |= 2
 |  |  | ELIF [ w == 'o' ]
 |  |  |  | who |= 4
 |  |  | ELIF [ w == 'a' ]
 |  |  |  | who |= 7
 |  |  | ELSE
 |  |  |  | who_on = FALSE
 |  |  |  \_
 |  |  | IF [ who_on ]
 |  |  |  | i += 1
 |  |  |  \_
 |  |  \_
 |  | B1 all = who == 0 || who == 7
 |  | IF [ who == 0 ]
 |  |  | who = 7
 |  |  \_
 |  | IF [ spec{i} != '+' && spec{i} != '-' && spec{i} != '=' ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  |
 |  | WHILE [ spec{i} == '+' || spec{i} == '-' || spec{i} == '=' ]
 |  |  | C1 op = spec{i}
 |  |  | i += 1
 |  |  | U32 rwx = 0
 |  |  | U32 special = 0
 |  |  | B1 perms = TRUE
 |  |  | WHILE [ perms ]
 |  |  |  | C1 p = spec{i}
 |  |  |  | IF [ p == 'r' ]
 |  |  |  |  | rwx |= 4
 |  |  |  | ELIF [ p == 'w' ]
 |  |  |  |  | rwx |= 2
 |  |  |  | ELIF [ p == 'x' ]
 |  |  |  |  | rwx |= 1
 |  |  |  | ELIF [ p == 'X' ]
 |  |  |  |  | IF [ dir || (mode & 0x49) != 0 ]
 |  |  |  |  |  | rwx |= 1
 |  |  |  |  |  \_
 |  |  |  | ELIF [ p == 's' ]
 |  |  |  |  | special |= (SELECT [ (who & 1) != 0 | 0x800 | 0 ]) | (SELECT [ (who & 2) != 0 | 0x400 | 0 ])
 |  |  |  | ELIF [ p == 't' ]
 |  |  |  |  | special |= 0x200
 |  |  |  | ELSE
 |  |  |  |  | perms = FALSE
 |  |  |  |  \_
 |  |  |  | IF [ perms ]
 |  |  |  |  | i += 1
 |  |  |  |  \_
 |  |  |  \_
 |  |  | U32 bits = special
 |  |  | IF [ (who & 1) != 0 ]
 |  |  |  | bits |= rwx << 6
 |  |  |  \_
 |  |  | IF [ (who & 2) != 0 ]
 |  |  |  | bits |= rwx << 3
 |  |  |  \_
 |  |  | IF [ (who & 4) != 0 ]
 |  |  |  | bits |= rwx
 |  |  |  \_
 |  |  | IF [ op == '+' ]
 |  |  |  | mode |= bits
 |  |  | ELIF [ op == '-' ]
 |  |  |  | mode = mode & (~bits)
 |  |  | ELSE
 |  |  |  | ; = clears what the who letters own first
 |  |  |  | U32 own = 0
 |  |  |  | IF [ (who & 1) != 0 ]
 |  |  |  |  | own |= 0x9C0
 |  |  |  |  \_
 |  |  |  | IF [ (who & 2) != 0 ]
 |  |  |  |  | own |= 0x438
 |  |  |  |  \_
 |  |  |  | IF [ (who & 4) != 0 ]
 |  |  |  |  | own |= 0x7
 |  |  |  |  \_
 |  |  |  | IF [ all ]
 |  |  |  |  | own |= 0x200
 |  |  |  |  \_
 |  |  |  | mode = (mode & (~own)) | bits
 |  |  |  \_
 |  |  \_
 |  |
 |  | IF [ spec{i} == ',' ]
 |  |  | i += 1
 |  | ELIF [ spec{i} == '\0' ]
 |  |  | more = FALSE
 |  | ELSE
 |  |  | RET [ FALSE ]
 |  |  \_
 |  \_
 | ?out = mode
 | RET [ TRUE ]
 \_

; what was typed past a leading `-R ` (recursive): `?rec` says whether it was
; there, and the result points at the rest, past the spaces
@CONST C1 perm_flags: [ @CONST C1 typed | @B1 rec ]
 | USIZE i = 0
 | WHILE [ typed{i} == ' ' ]
 |  | i += 1
 |  \_
 | ?rec = FALSE
 | IF [ typed{i} == '-' && typed{i + 1} == 'R' && (typed{i + 2} == ' ' || typed{i + 2} == '\0') ]
 |  | ?rec = TRUE
 |  | i += 2
 |  | WHILE [ typed{i} == ' ' ]
 |  |  | i += 1
 |  |  \_
 |  \_
 | RET [ typed + i ]
 \_

; `user`, `user:group` or `:group` split into `user` and `group` (each of
; `cap` bytes; empty for the one not given). FALSE: nothing in it, more than
; one colon, or a part too long
B1 owner_split: [ @CONST C1 spec | @C1 user | @C1 group | USIZE cap ]
 | USIZE i = 0
 | WHILE [ spec{i} == ' ' ]
 |  | i += 1
 |  \_
 | USIZE n = 0
 | USIZE colons = 0
 | user{0} = '\0'
 | group{0} = '\0'
 | USIZE g = 0
 | WHILE [ spec{i} != '\0' && spec{i} != ' ' ]
 |  | IF [ spec{i} == ':' ]
 |  |  | colons += 1
 |  | ELIF [ colons == 0 ]
 |  |  | IF [ n + 1 >= cap ]
 |  |  |  | RET [ FALSE ]
 |  |  |  \_
 |  |  | user{n} = spec{i}
 |  |  | n += 1
 |  |  | user{n} = '\0'
 |  | ELSE
 |  |  | IF [ g + 1 >= cap ]
 |  |  |  | RET [ FALSE ]
 |  |  |  \_
 |  |  | group{g} = spec{i}
 |  |  | g += 1
 |  |  | group{g} = '\0'
 |  |  \_
 |  | i += 1
 |  \_
 | ; only spaces may follow
 | WHILE [ spec{i} == ' ' ]
 |  | i += 1
 |  \_
 | RET [ colons <= 1 && spec{i} == '\0' && (n > 0 || g > 0) ]
 \_
