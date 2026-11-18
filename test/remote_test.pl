; remote_test.pl -- join_into and path_step from core/remote.pl: paths by their names
USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/io/io.pl>
!USES <../src/core/remote.pl>

LOCAL I32 bad = 0

; `dir` and `name` join as `expect`
LOCAL ABYSS joins: [ @CONST C1 dir | @CONST C1 name | @CONST C1 expect ]
 | C1 out{64}
 | (join_into)[ out | 64 | dir | name ]
 | IF [ !((str_eq)[ out AS @CONST C1 | expect ]) ]
 |  | (stderr.print)[ "FAIL: join %s + %s gives %s, wanted %s\n" | dir | name | out AS @CONST C1 | expect ]
 |  | bad += 1
 |  \_
 \_

; from `start`, the steps `a`, `b` (NULL: none) make `expect`
LOCAL ABYSS steps: [ @CONST C1 start | @CONST C1 a | @CONST C1 b | @CONST C1 expect ]
 | C1 p{64}
 | (str_copy)[ p | 64 | start ]
 | IF [ a != NULL ]
 |  | (path_step)[ p | 64 | a ]
 |  \_
 | IF [ b != NULL ]
 |  | (path_step)[ p | 64 | b ]
 |  \_
 | IF [ !((str_eq)[ p AS @CONST C1 | expect ]) ]
 |  | (stderr.print)[ "FAIL: %s, %s, %s gives %s, wanted %s\n" | start | SELECT [ a == NULL | "" | a ] | SELECT [ b == NULL | "" | b ] | p AS @CONST C1 | expect ]
 |  | bad += 1
 |  \_
 \_

I32 main: []
 | ; the root has no second /
 | (joins)[ "/" | "srv" | "/srv" ]
 | (joins)[ "/mnt" | "srv" | "/mnt/srv" ]
 | (joins)[ "/mnt/" | "srv" | "/mnt//srv" ]
 | ; a name goes in, . stays, .. goes up
 | (steps)[ "" | "mnt" | "srv" | "/mnt/srv" ]
 | (steps)[ "/mnt/srv" | ".." | NULL | "/mnt" ]
 | (steps)[ "/mnt/srv" | ".." | ".." | "" ]
 | (steps)[ "" | ".." | NULL | "" ]
 | (steps)[ "/a" | "." | "b" | "/a/b" ]
 | (steps)[ "/a/b" | ".." | "c" | "/a/c" ]
 | (steps)[ "/a" | "" | NULL | "/a" ]
 | ; too long for the room: the path stays
 | C1 small{8}
 | (str_copy)[ small | 8 | "/abc" ]
 | (path_step)[ small | 8 | "defgh" ]
 | IF [ !((str_eq)[ small AS @CONST C1 | "/abc" ]) ]
 |  | (stderr.print)[ "FAIL: a step past the room changed the path to %s\n" | small AS @CONST C1 ]
 |  | bad += 1
 |  \_
 | IF [ (path_step)[ small | 8 | "defgh" ] ]
 |  | (stderr.print)[ "FAIL: a step past the room fits\n" ]
 |  | bad += 1
 |  \_
 | ; nothing is mounted over the network by this name: up, and no walk
 | IF [ !((remote_ok)[ "/definitely/not/a/mount" ]) || !((remote_ok_deep)[ "relative/../x" ]) ]
 |  | (stderr.print)[ "FAIL: an ordinary path is not up\n" ]
 |  | bad += 1
 |  \_
 | IF [ bad != 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "remote_test: ok\n" ]
 | RET [ 0 ]
 \_
