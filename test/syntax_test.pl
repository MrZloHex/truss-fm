; syntax_test.pl -- the tokenizer of core/syntax.pl
USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/io/io.pl>
!USES <../src/core/syntax.pl>

LOCAL I32 bad = 0

LOCAL ABYSS want: [ B1 ok | @CONST C1 what ]
 | IF [ !ok ]
 |  | (stderr.print)[ "FAIL: %s\n" | what ]
 |  | bad += 1
 |  \_
 \_

; the line cut up, a letter to a byte for its kind: . plain, c comment,
; s string, n number, k keyword, t type, p preproc, g guide, h heading, + -
LOCAL ABYSS shape: [ @Lang l | @CONST C1 s | @I32 state | @C1 out ]
 | SynSpan sp{600}
 | I32 n = (syntax_line)[ l | s | state | sp | 600 ]
 | @CONST C1 letters = ".csnktpgh+-"
 | I32 at = 0
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | (want)[ sp{i}.at == at | "spans follow one another" ]
 |  | FOR [ I32 k = 0 | k < sp{i}.len | k += 1 ]
 |  |  | out{at} = letters{sp{i}.kind}
 |  |  | at += 1
 |  |  \_
 |  \_
 | out{at} = '\0'
 | (want)[ at == (str_len)[ s ] AS I32 | "spans cover the line" ]
 \_

LOCAL ABYSS is: [ @Lang l | @I32 state | @CONST C1 line | @CONST C1 expect ]
 | C1 out{700}
 | (shape)[ l | line | state | out ]
 | IF [ !((str_eq)[ out | expect ]) ]
 |  | (stderr.print)[ "FAIL: %s\n   got  %s\n   want %s\n" | line | out | expect ]
 |  | bad += 1
 |  \_
 \_

I32 main: []
 | Lang l
 | I32 st = 0
 |

 | ; PLUM: a comment, a string holding the comment mark, a char, escapes
 | (want)[ (syntax_by_name)[ @l | "main.pl" ] | "pl is PLUM" ]
 | (is)[ @l | @st | " | I32 n = 0x1F ; count" | ".g.ttt.....nnnn.ccccccc" ]
 | (is)[ @l | @st | " | (f)[ \"a ; b\" ]  ; z" | ".g......sssssss....ccc" ]
 | (is)[ @l | @st | "\"a\\\"b\" x" | "ssssss.." ]
 | (is)[ @l | @st | " | C1 c = ';' ; x" | ".g.tt.....sss.ccc" ]
 | (is)[ @l | @st | " | IF [ x ]" | ".g.kk......" ]
 | (is)[ @l | @st | " \\_" | ".gg" ]
 | (is)[ @l | @st | "!USES <../x.pl>" | "ppppp.sssssssss" ]
 |
 | ; C: a block comment over three lines, a comment mark in a string
 | (want)[ (syntax_by_name)[ @l | "a.c" ] | "c" ]
 | st = 0
 | (is)[ @l | @st | "int x; /* start" | "ttt....cccccccc" ]
 | (want)[ st == SS_BLOCK | "the comment is still open" ]
 | (is)[ @l | @st | " middle " | "cccccccc" ]
 | (is)[ @l | @st | "end */ int y;" | "cccccc.ttt..." ]
 | (want)[ st == SS_NONE | "and closed" ]
 | (is)[ @l | @st | "puts(\"// no\"); // yes" | ".....sssssss...cccccc" ]
 |
 | ; Python: a triple-quoted string over lines; UTF-8 in a string and a comment
 | (want)[ (syntax_by_name)[ @l | "a.py" ] | "py" ]
 | (is)[ @l | @st | "x = \"\"\"abc" | "....ssssss" ]
 | (want)[ st == SS_TRIPLE_D | "the string is still open" ]
 | (is)[ @l | @st | "still in" | "ssssssss" ]
 | (is)[ @l | @st | "end\"\"\" + 1" | "ssssss...n" ]
 | (want)[ st == SS_NONE | "the string is closed" ]
 | (is)[ @l | @st | "x = \"héllo\" # ñ" | "....ssssssss.cccc" ]
 |
 | ; shell, JSON, a conf file
 | (want)[ (syntax_by_name)[ @l | "run.sh" ] | "sh" ]
 | (is)[ @l | @st | "echo $HOME # c" | ".....ttttt.ccc" ]
 | (is)[ @l | @st | "echo a#b" | "........" ]
 | (is)[ @l | @st | "it's fine" | "........." ]
 | (want)[ (syntax_by_name)[ @l | "a.json" ] | "json" ]
 | (is)[ @l | @st | "{\"a\": 1, \"b\": \"x\"}" | ".ttt..n..ttt..sss." ]
 | (want)[ (syntax_by_name)[ @l | "trufm.conf" ] | "conf" ]
 | (is)[ @l | @st | "key = value # no" | "kkk.........cccc" ]
 | (is)[ @l | @st | "[main]" | "pppppp" ]
 |
 | ; a diff, Markdown
 | (want)[ (syntax_by_name)[ @l | "x.patch" ] | "patch" ]
 | (is)[ @l | @st | "+added" | "++++++" ]
 | (is)[ @l | @st | "-gone" | "-----" ]
 | (is)[ @l | @st | "@@ -1 +1 @@ fn" | "kkkkkkkkkkk..." ]
 | (is)[ @l | @st | "--- a/x" | "ppppppp" ]
 | (want)[ (syntax_by_name)[ @l | "README.md" ] | "md" ]
 | (is)[ @l | @st | "# Title" | "hhhhhhh" ]
 | (is)[ @l | @st | "```c" | "cccc" ]
 | (want)[ st == SS_FENCE | "a fence is open" ]
 | (is)[ @l | @st | "x = 1" | "sssss" ]
 | (is)[ @l | @st | "```" | "ccc" ]
 | (want)[ st == SS_NONE | "and shut" ]
 | (is)[ @l | @st | "- item `code` end" | "k......ssssss...." ]
 | (is)[ @l | @st | "**bold** x" | "tttttttt.." ]
 |
 | ; which file, by name or by its first line
 | (want)[ !((syntax_by_name)[ @l | "README" ]) | "README has none" ]
 | (want)[ (syntax_dotless)[ "README" ] && !((syntax_dotless)[ "a.c" ]) | "dotless" ]
 | (want)[ (syntax_by_name)[ @l | "Makefile" ] | "Makefile" ]
 | (want)[ (syntax_by_shebang)[ @l | "#!/usr/bin/env python3" ] && l.flags == (LF_TRIPLE | LF_CAPS) | "python script" ]
 | (want)[ (syntax_by_shebang)[ @l | "#!/bin/bash" ] && l.flags == LF_DOLLAR | "bash script" ]
 | (want)[ !((syntax_by_shebang)[ @l | "int main" ]) | "not a script" ]
 |
 | IF [ bad > 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "syntax_test: ok\n" ]
 | RET [ 0 ]
 \_
