; text_test.pl -- looks_binary from core/text.pl
USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/io/io.pl>
!USES <../src/core/text.pl>

LOCAL I32 bad = 0

LOCAL ABYSS want: [ B1 ok | @CONST C1 what ]
 | IF [ !ok ]
 |  | (stderr.print)[ "FAIL: %s\n" | what ]
 |  | bad += 1
 |  \_
 \_

LOCAL B1 bin: [ @CONST C1 s ]
 | RET [ (looks_binary)[ s | (str_len)[ s ] ] ]
 \_

I32 main: []
 | ; random-looking bytes, like the pulse cookie
 | C1 rnd{256}
 | U32 x = 12345
 | FOR [ I32 i = 0 | i < 256 | i += 1 ]
 |  | x = x * 1103515245 + 12345
 |  | rnd{i} = ((x >> 16) & 0xFF) AS C1
 |  | IF [ rnd{i} == 0 ]
 |  |  | rnd{i} = 1 AS C1
 |  |  \_
 |  \_
 | (want)[ (looks_binary)[ rnd | 256 ] | "random bytes" ]
 | (want)[ !(bin)[ "plain ascii text\nsecond line\n" ] | "ascii" ]
 | (want)[ !(bin)[ "Привет, мир\nещё строка\n" ] | "cyrillic" ]
 | (want)[ !(bin)[ "a\tb\r\nc\td\r\n" ] | "tabs and crlf" ]
 | (want)[ !(bin)[ "\e[31mred\e[0m \e[1;32mgreen\e[0m\n" ] | "sgr codes" ]
 | (want)[ (bin)[ "\x01\x02\x03\x04\x05\x06\x07\x0e\x0f\x10 text" ] | "controls" ]
 | (want)[ (looks_binary)[ "h\0i\0\n\0" | 6 ] | "utf-16" ]
 | (want)[ !(looks_binary)[ "ab\xD0" | 3 ] | "cut sequence at the end" ]
 | IF [ bad > 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "text_test: ok\n" ]
 | RET [ 0 ]
 \_
