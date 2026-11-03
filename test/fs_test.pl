; fs_test.pl -- join_path and is_under from core/fs.pl
USE <std/core/core.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
!USES <../src/core/fs.pl>

LOCAL I32 bad = 0

LOCAL ABYSS want: [ B1 ok | @CONST C1 what ]
 | IF [ !ok ]
 |  | (stderr.print)[ "FAIL: %s\n" | what ]
 |  | bad += 1
 |  \_
 \_

LOCAL ABYSS joins: [ @CONST C1 dir | @CONST C1 name | @CONST C1 expect ]
 | String s = (join_path)[ dir | name ]
 | (want)[ (str_eq)[ (s.cstr)[] | expect ] | expect ]
 | (s.deinit)[]
 \_

I32 main: []
 | (joins)[ "/a" | "b" | "/a/b" ]
 | (joins)[ "/" | "b" | "/b" ]
 | (joins)[ "/a/b" | "c.txt" | "/a/b/c.txt" ]
 | (want)[ (is_under)[ "/a/b" | "/a" ] | "child is under" ]
 | (want)[ (is_under)[ "/a" | "/a" ] | "dir is under itself" ]
 | (want)[ !((is_under)[ "/ab" | "/a" ]) | "/ab not under /a" ]
 | (want)[ !((is_under)[ "/a" | "/a/b" ]) | "parent not under child" ]
 | (want)[ (is_under)[ "/x" | "/" ] | "all under /" ]
 | IF [ bad != 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "fs_test: ok\n" ]
 | RET [ 0 ]
 \_
