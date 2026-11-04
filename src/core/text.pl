USE <std/core/core.pl>

; --- is it text -------------------------------------------------------------------

; how many bytes of `buf` start a bad UTF-8 sequence. A sequence cut off by
; the end of the buffer is not bad
USIZE bad_utf8: [ @CONST C1 buf | USIZE n ]
 | USIZE bad = 0
 | USIZE i = 0
 | WHILE [ i < n ]
 |  | U32 c = (buf{i} AS U8) AS U32
 |  | USIZE want = 0
 |  | IF [ c < 0x80 ]
 |  |  | i += 1
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ c >= 0xC2 && c <= 0xDF ]
 |  |  | want = 1
 |  |  \_
 |  | IF [ c >= 0xE0 && c <= 0xEF ]
 |  |  | want = 2
 |  |  \_
 |  | IF [ c >= 0xF0 && c <= 0xF4 ]
 |  |  | want = 3
 |  |  \_
 |  | IF [ want == 0 ]
 |  |  | bad += 1
 |  |  | i += 1
 |  |  | CONTINUE
 |  |  \_
 |  | USIZE k = 1
 |  | B1 ok = TRUE
 |  | WHILE [ k <= want && i + k < n ]
 |  |  | IF [ (((buf{i + k}) AS U8) & 0xC0) != 0x80 ]
 |  |  |  | ok = FALSE
 |  |  |  | BREAK
 |  |  |  \_
 |  |  | k += 1
 |  |  \_
 |  | i += SELECT [ ok | k | 1 ]
 |  | bad += SELECT [ ok | 0 | 1 ]
 |  \_
 | RET [ bad ]
 \_

; the first `n` bytes of `buf` do not look like text: a NUL, or more than
; a few controls (not tab, newline, CR, form feed, nor ESC, which colour
; codes use) and bad UTF-8 starts, in all or in 2% of them
B1 looks_binary: [ @CONST C1 buf | USIZE n ]
 | USIZE odd = (bad_utf8)[ buf | n ]
 | FOR [ USIZE i = 0 | i < n | i += 1 ]
 |  | U32 c = (buf{i} AS U8) AS U32
 |  | IF [ c == 0 ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | IF [ (c < 0x20 && c != 9 && c != 10 && c != 12 && c != 13 && c != 27) || c == 0x7F ]
 |  |  | odd += 1
 |  |  \_
 |  \_
 | RET [ odd > 8 || odd * 50 > n ]
 \_
