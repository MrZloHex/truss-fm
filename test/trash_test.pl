; trash_test.pl -- the .trashinfo parser and its percent-decoding, from
; core/trash.pl
USE <std/core/core.pl>
USE <std/io/io.pl>
!USES <../src/core/trash.pl>

LOCAL I32 bad = 0

LOCAL ABYSS want: [ B1 ok | @CONST C1 what ]
 | IF [ !ok ]
 |  | (stderr.print)[ "FAIL: %s\n" | what ]
 |  | bad += 1
 |  \_
 \_

; `s` decodes to `expect`
LOCAL ABYSS decodes: [ @CONST C1 s | @CONST C1 expect ]
 | C1 out{256}
 | B1 ok = (url_decode)[ out | 256 | s ]
 | IF [ !ok || !((str_eq)[ out AS @CONST C1 | expect ]) ]
 |  | (stderr.print)[ "FAIL: %s decodes to %s, wanted %s\n" | s | out AS @CONST C1 | expect ]
 |  | bad += 1
 |  \_
 \_

LOCAL ABYSS refuses: [ @CONST C1 s ]
 | C1 out{256}
 | (want)[ !((url_decode)[ out | 256 | s ]) | s ]
 \_

; a file's text gives the path `expect`; `date`: it has a good date
LOCAL ABYSS parses: [ @CONST C1 text | @CONST C1 expect | B1 date ]
 | C1 path{4096}
 | I64 when = 0
 | B1 ok = (trashinfo_parse)[ text | path | @when ]
 | IF [ !ok || !((str_eq)[ path AS @CONST C1 | expect ]) || (when > 0) != date ]
 |  | (stderr.print)[ "FAIL: \"%s\" gives path %s, wanted %s\n" | text | path AS @CONST C1 | expect ]
 |  | bad += 1
 |  \_
 \_

I32 main: []
 | (decodes)[ "/home/me/plain.txt" | "/home/me/plain.txt" ]
 | (decodes)[ "/home/me/notes%20old.txt" | "/home/me/notes old.txt" ]
 | (decodes)[ "/h/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82" | "/h/привет" ]
 | (decodes)[ "%2f%2F%41%7e" | "//A~" ]
 | (decodes)[ "/a/b?c#d" | "/a/b?c#d" ]
 | (decodes)[ "/a/100%25" | "/a/100%" ]
 | (decodes)[ "" | "" ]
 | (refuses)[ "/a/%zz" ]
 | (refuses)[ "/a/%2" ]
 | (refuses)[ "/a/%" ]
 | (refuses)[ "/a/%00b" ]
 |
 | (parses)[ "[Trash Info]\nPath=/home/me/a%20b.txt\nDeletionDate=2026-11-04T10:12:03\n" | "/home/me/a b.txt" | TRUE ]
 | (parses)[ "[Trash Info]\r\nPath=/x/y\r\nDeletionDate=2026-01-31T23:59:59\r\n" | "/x/y" | TRUE ]
 | (parses)[ "[Trash Info]\nDeletionDate=2026-11-04T10:12:03\nPath=/x/a?b#c%3Fd\n" | "/x/a?b#c?d" | TRUE ]
 | (parses)[ "[Trash Info]\nPath=/x/y\n" | "/x/y" | FALSE ]
 | (parses)[ "[Trash Info]\nPath=/x/y\nDeletionDate=yesterday\n" | "/x/y" | FALSE ]
 | (parses)[ "[Trash Info]\nPath=/x/y\nDeletionDate=2026-13-04T10:12:03\n" | "/x/y" | FALSE ]
 | C1 path{4096}
 | I64 when = 0
 | (want)[ !((trashinfo_parse)[ "[Trash Info]\nDeletionDate=2026-11-04T10:12:03\n" | path | @when ]) | "missing Path=" ]
 | (want)[ when > 0 | "date read though Path= is missing" ]
 | (want)[ !((trashinfo_parse)[ "[Trash Info]\nPath=/x/%zz\n" | path | @when ]) | "bad escape in Path=" ]
 | (want)[ !((trashinfo_parse)[ "" | path | @when ]) | "empty text" ]
 | (want)[ !((trashinfo_parse)[ "[Trash Info]\nPath=\n" | path | @when ]) | "empty Path=" ]
 | ; the date is local time: it comes back as the same wall clock
 | I64 t = (trash_date)[ "2026-11-04T10:12:03" ]
 | DateTime d = (local_date)[ t ]
 | (want)[ t > 0 && d.year == 2026 && d.month == 11 && d.day == 4 && d.hour == 10 && d.minute == 12 && d.second == 3 | "DeletionDate is local time" ]
 | (want)[ (trash_date)[ "2026-11-04" ] == -1 | "short date" ]
 |
 | IF [ bad != 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "trash_test: ok\n" ]
 | RET [ 0 ]
 \_
