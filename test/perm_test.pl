; perm_test.pl -- mode_apply, perm_flags and owner_split from core/perm.pl
USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/io/io.pl>
!USES <../src/core/perm.pl>

LOCAL I32 bad = 0

LOCAL ABYSS want: [ B1 ok | @CONST C1 what ]
 | IF [ !ok ]
 |  | (stderr.print)[ "FAIL: %s\n" | what ]
 |  | bad += 1
 |  \_
 \_

; `spec` on `old` (a folder if `dir`) gives `expect`
LOCAL ABYSS gives: [ @CONST C1 spec | U32 old | B1 dir | U32 expect ]
 | U32 got = 0xFFFF
 | B1 ok = (mode_apply)[ spec | old | dir | @got ]
 | IF [ !ok || got != expect ]
 |  | (stderr.print)[ "FAIL: %s on %o gives %o, wanted %o\n" | spec | old | got | expect ]
 |  | bad += 1
 |  \_
 \_

LOCAL ABYSS refuses: [ @CONST C1 spec ]
 | U32 got = 0x1234
 | (want)[ !((mode_apply)[ spec | 0x1A4 | FALSE | @got ]) && got == 0x1234 | spec ]
 \_

; `typed` is recursive or not, and `rest` is what is left of it
LOCAL ABYSS flags: [ @CONST C1 typed | B1 rec | @CONST C1 rest ]
 | B1 got = FALSE
 | @CONST C1 r = (perm_flags)[ typed | @got ]
 | IF [ got != rec || !((str_eq)[ r | rest ]) ]
 |  | (stderr.print)[ "FAIL: perm_flags %s gives %d, \"%s\"\n" | typed | got AS I32 | r ]
 |  | bad += 1
 |  \_
 \_

; `spec` splits into `user` and `group`, or is refused (both NULL)
LOCAL ABYSS owner: [ @CONST C1 spec | @CONST C1 user | @CONST C1 group ]
 | C1 u{16}
 | C1 g{16}
 | B1 ok = (owner_split)[ spec | u | g | 16 ]
 | IF [ user == NULL ]
 |  | (want)[ !ok | spec ]
 |  | RET []
 |  \_
 | IF [ !ok || !((str_eq)[ u AS @CONST C1 | user ]) || !((str_eq)[ g AS @CONST C1 | group ]) ]
 |  | (stderr.print)[ "FAIL: owner_split %s gives %d, \"%s\" \"%s\"\n" | spec | ok AS I32 | u AS @CONST C1 | g AS @CONST C1 ]
 |  | bad += 1
 |  \_
 \_

I32 main: []
 | (flags)[ "u+x" | FALSE | "u+x" ]
 | (flags)[ "-R go-w" | TRUE | "go-w" ]
 | (flags)[ "  -R   :users" | TRUE | ":users" ]
 | (flags)[ "-R" | TRUE | "" ]
 | (flags)[ "-Rx" | FALSE | "-Rx" ]
 | (flags)[ "-w" | FALSE | "-w" ]
 | (owner)[ "bob" | "bob" | "" ]
 | (owner)[ "bob:staff" | "bob" | "staff" ]
 | (owner)[ ":staff" | "" | "staff" ]
 | (owner)[ "bob:" | "bob" | "" ]
 | (owner)[ " bob:staff " | "bob" | "staff" ]
 | (owner)[ "1000:100" | "1000" | "100" ]
 | (owner)[ "" | NULL | NULL ]
 | (owner)[ ":" | NULL | NULL ]
 | (owner)[ "a:b:c" | NULL | NULL ]
 | (owner)[ "a b" | NULL | NULL ]
 | (owner)[ "averyveryverylongname" | NULL | NULL ]
 | (gives)[ "755" | 0x1A4 | FALSE | 0x1ED ]
 | (gives)[ "0600" | 0x1ED | FALSE | 0x180 ]
 | (gives)[ "4755" | 0x1A4 | FALSE | 0x9ED ]
 | (gives)[ "u+x" | 0x1A4 | FALSE | 0x1E4 ]
 | (gives)[ "go-w" | 0x1B6 | FALSE | 0x1A4 ]
 | (gives)[ "a=r" | 0x1ED | FALSE | 0x124 ]
 | (gives)[ "+x" | 0x1A4 | FALSE | 0x1ED ]
 | (gives)[ "+X" | 0x1A4 | FALSE | 0x1A4 ]
 | (gives)[ "+X" | 0x1A4 | TRUE | 0x1ED ]
 | (gives)[ "+X" | 0x1E4 | FALSE | 0x1ED ]
 | (gives)[ "u=rwx,g=rx,o=" | 0x1A4 | FALSE | 0x1E8 ]
 | (gives)[ "u+s,o+t" | 0x1A4 | FALSE | 0xBA4 ]
 | (refuses)[ "g=u" ]
 | (refuses)[ "" ]
 | (refuses)[ "9" ]
 | (refuses)[ "75" ]
 | (refuses)[ "77777" ]
 | (refuses)[ "758" ]
 | (refuses)[ "u+q" ]
 | (refuses)[ "u" ]
 | (refuses)[ "u+x," ]
 | (refuses)[ ",u+x" ]
 | (refuses)[ "x+u" ]
 | IF [ bad != 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "perm_test: ok\n" ]
 | RET [ 0 ]
 \_
