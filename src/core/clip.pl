; clip.pl -- text put on the clipboard: by the first program there is for it
; (wl-copy, xclip, xsel), else, in a terminal, by an OSC 52 report, which
; the terminal itself may act on. The text goes to the program as an argument
; to sh and is piped from there, so it is never in the command's text

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/process.pl>

!USES <sys.pl>

CONST @CONST C1 B64_DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

; $1 piped to the program there is, left running behind (a clipboard owner
; stays till something else is copied); exit 3: there is none. xclip and xsel
; need a display, wl-copy a Wayland one
CONST @CONST C1 CLIP_SCRIPT = "if [ -n \"$WAYLAND_DISPLAY\" ] && command -v wl-copy >/dev/null 2>&1; then set -- \"$1\" wl-copy; elif [ -n \"$DISPLAY\" ] && command -v xclip >/dev/null 2>&1; then set -- \"$1\" xclip -selection clipboard; elif [ -n \"$DISPLAY\" ] && command -v xsel >/dev/null 2>&1; then set -- \"$1\" xsel -ib; else exit 3; fi; t=$1; shift; (printf %s \"$t\" | \"$@\") </dev/null >/dev/null 2>&1 &"

CONST I32 CLIP_SENT = 0
CONST I32 CLIP_NONE = 1       ; no program for it
CONST I32 CLIP_FAILED = 2

; the most an OSC 52 report carries: terminals refuse more
CONST USIZE OSC_MAX = 74000

; `n` bytes of `s` in base 64, with = to fill
String base64: [ @CONST C1 s | USIZE n ]
 | String out = (String.of)[ "" ]
 | USIZE i = 0
 | WHILE [ i < n ]
 |  | U32 b0 = (s{i} AS U8) AS U32
 |  | U32 b1 = 0
 |  | U32 b2 = 0
 |  | IF [ i + 1 < n ]
 |  |  | b1 = (s{i + 1} AS U8) AS U32
 |  |  \_
 |  | IF [ i + 2 < n ]
 |  |  | b2 = (s{i + 2} AS U8) AS U32
 |  |  \_
 |  | U32 v = (b0 << 16) + (b1 << 8) + b2
 |  | (out.push)[ B64_DIGITS{((v >> 18) & 63) AS USIZE} ]
 |  | (out.push)[ B64_DIGITS{((v >> 12) & 63) AS USIZE} ]
 |  | IF [ i + 1 < n ]
 |  |  | (out.push)[ B64_DIGITS{((v >> 6) & 63) AS USIZE} ]
 |  | ELSE
 |  |  | (out.push)[ '=' ]
 |  |  \_
 |  | IF [ i + 2 < n ]
 |  |  | (out.push)[ B64_DIGITS{(v & 63) AS USIZE} ]
 |  | ELSE
 |  |  | (out.push)[ '=' ]
 |  |  \_
 |  | i += 3
 |  \_
 | RET [ out ]
 \_

; the OSC 52 report that sets the clipboard to `text`: ESC ] 52 ; c ; data BEL
String clip_osc52: [ @CONST C1 text ]
 | String data = (base64)[ text | (str_len)[ text ] ]
 | String out = (String.of)[ "\e]52;c;" ]
 | (out.append)[ (data.cstr)[] ]
 | (out.push)[ '\a' ]
 | (data.deinit)[]
 | RET [ out ]
 \_

; `text` to a clipboard program; CLIP_NONE when there is none
I32 clip_send: [ @CONST C1 text ]
 | @CONST C1 argv{} = [ "sh" | "-c" | CLIP_SCRIPT | "trufm" | text | NULL ]
 | Result<ExitStatus | IoError> r = (process_run)[ argv ]
 | IF [ (r.is_err)[] || !((r.unwrap)[].exited) ]
 |  | RET [ CLIP_FAILED ]
 |  \_
 | I32 code = (r.unwrap)[].code
 | IF [ code == 3 ]
 |  | RET [ CLIP_NONE ]
 |  \_
 | RET [ SELECT [ code == 0 | CLIP_SENT | CLIP_FAILED ] ]
 \_

; `text` as an OSC 52 report written to the terminal. FALSE: too long for one
B1 clip_terminal: [ @CONST C1 text ]
 | IF [ (str_len)[ text ] > OSC_MAX ]
 |  | RET [ FALSE ]
 |  \_
 | String seq = (clip_osc52)[ text ]
 | USIZE done = 0
 | USIZE n = (seq.size)[]
 | WHILE [ done < n ]
 |  | ISIZE w = (px_write)[ 1 | ((seq.cstr)[] + done) AS @CONST ABYSS | n - done ]
 |  | IF [ w <= 0 ]
 |  |  | BREAK
 |  |  \_
 |  | done += w AS USIZE
 |  \_
 | (seq.deinit)[]
 | RET [ done == n ]
 \_
