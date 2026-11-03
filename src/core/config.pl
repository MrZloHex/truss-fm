; config.pl -- ~/.config/pluf/config, read once as the program starts: a
; line each, `key = value`, # to the end of a line a comment. A key it does
; not know, or a value it cannot read, is said on stderr and left out; a
; file that is not there leaves everything as it is. pluf.conf.example in
; the repository has every key
;
;   hidden = false
;   sort = date
;   sort_desc = true
;   tab = ~/Downloads
;   color.accent = #87afd7

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>



CONST USIZE CONFIG_LINE = 1024

; how files of some kinds are opened: open.pdf,djvu = zathura
TYPE Opener: STRUCT
 | String exts              ; ,pdf,djvu, -- lower case, a comma each side; ,*, any
 | String cmd               ; a shell command; %f where the files go, or after it
 | B1 term                  ; term: it wants the terminal, pluf steps aside
 \_

; the colours the config may set, as color.<name>; ui/look.pl gives each
; to its palette entry, in this order
CONST @CONST C1 COLOR_NAMES{} = [ "bg" | "bar" | "cursor" | "line" | "text" | "text2" | "dim" |
                                  "accent" | "dir" | "exec" | "remote" | "warn" | "error" | "ink" ]
; a number, not COUNT: plc cannot size a struct's array by COUNT yet
CONST I32 NCOLORS = 14
STATIC_ASSERT [ COUNT [ COLOR_NAMES ] == NCOLORS | "a colour name for each of NCOLORS" ]

TYPE Config: STRUCT
 | B1 hidden                ; dotfiles in the main column and the preview; . flips it
 | B1 root_hidden           ; and in the parent column, while `hidden` is on
 | I32 places_width         ; the columns' widths, in percent of the screen
 | I32 root_width
 | I32 preview_width
 | I32 sort                 ; the main column's: 0 name, 1 size, 2 date
 | B1 sort_desc
 | B1 confirm_delete        ; D asks first
 | Vector<String> tabs      ; opened at the start, after the one asked for
 | B1 std_places            ; Desktop, Documents, Downloads ... and / among the places
 | B1 devices               ; the DEVICES of the places column
 | Vector<String> places    ; place = lines, as they were: key, path, | name
 | Vector<Opener> openers   ; open.<exts> = lines, in order: the first that fits
 | U32 colors{NCOLORS}      ; COLOR_NAMES' as set, 0xFFrrggbb; 0: not set
 \_

Config CFG = [ .hidden = TRUE | .root_hidden = FALSE | .places_width = 15 | .root_width = 25 |
               .preview_width = 20 | .sort = 0 | .sort_desc = FALSE | .confirm_delete = TRUE |
               .std_places = TRUE | .devices = TRUE ]

; --- values ---------------------------------------------------------------------

LOCAL B1 read_bool: [ @CONST C1 v | @B1 out ]
 | IF [ (str_eq)[ v | "true" ] || (str_eq)[ v | "yes" ] || (str_eq)[ v | "on" ] ]
 |  | ?out = TRUE
 |  | RET [ TRUE ]
 |  \_
 | IF [ (str_eq)[ v | "false" ] || (str_eq)[ v | "no" ] || (str_eq)[ v | "off" ] ]
 |  | ?out = FALSE
 |  | RET [ TRUE ]
 |  \_
 | RET [ FALSE ]
 \_

; a whole number from `lo` to `hi`
LOCAL B1 read_int: [ @CONST C1 v | I32 lo | I32 hi | @I32 out ]
 | Option<I64> n = (parse_int)[ v ]
 | IF [ (n.is_none)[] ]
 |  | RET [ FALSE ]
 |  \_
 | I64 x = (n.unwrap)[]
 | IF [ x < (lo AS I64) || x > (hi AS I64) ]
 |  | RET [ FALSE ]
 |  \_
 | ?out = x AS I32
 | RET [ TRUE ]
 \_

LOCAL I32 hex_digit: [ C1 c ]
 | IF [ c >= '0' && c <= '9' ]
 |  | RET [ (c - '0') AS I32 ]
 |  \_
 | IF [ c >= 'a' && c <= 'f' ]
 |  | RET [ (c - 'a') AS I32 + 10 ]
 |  \_
 | IF [ c >= 'A' && c <= 'F' ]
 |  | RET [ (c - 'A') AS I32 + 10 ]
 |  \_
 | RET [ -1 ]
 \_

; #rrggbb, opaque: 0xFFrrggbb
LOCAL B1 read_color: [ @CONST C1 v | @U32 out ]
 | IF [ v{0} != '#' || (str_len)[ v ] != 7 ]
 |  | RET [ FALSE ]
 |  \_
 | U32 c = 0xFF
 | FOR [ USIZE i = 1 | i < 7 | i += 1 ]
 |  | I32 d = (hex_digit)[ v{i} ]
 |  | IF [ d < 0 ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | c = (c << 4) + (d AS U32)
 |  \_
 | ?out = c
 | RET [ TRUE ]
 \_

; `v` with a leading ~ as home, in `out`
LOCAL ABYSS expand_home: [ @CONST C1 v | @C1 out | USIZE cap ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | IF [ v{0} == '~' ]
 |  | (b.print)[ "%s%s" | ((env)[ "HOME" ].unwrap_or)[ "/" ] | v + 1 ]
 | ELSE
 |  | (b.print)[ "%s" | v ]
 |  \_
 \_

; --- lines ----------------------------------------------------------------------

; `s` with the blanks at its ends cut, in place
LOCAL @C1 trim: [ @C1 s ]
 | WHILE [ ?s == ' ' || ?s == '\t' ]
 |  | s += 1
 |  \_
 | USIZE n = (str_len)[ s AS @CONST C1 ]
 | WHILE [ n > 0 && (s{n - 1} == ' ' || s{n - 1} == '\t' || s{n - 1} == '\r') ]
 |  | n -= 1
 |  \_
 | s{n} = '\0'
 | RET [ s ]
 \_

; open.<exts> = [term:] command, into CFG.openers; FALSE: no extension, or
; no command
LOCAL B1 opener_add: [ @CONST C1 exts | @CONST C1 v ]
 | IF [ exts{0} == '\0' || v{0} == '\0' ]
 |  | RET [ FALSE ]
 |  \_
 | Opener o
 | o.term = (str_starts)[ v | "term:" ]
 | @CONST C1 cmd = SELECT [ o.term | v + 5 | v ]
 | WHILE [ ?cmd == ' ' ]
 |  | cmd += 1
 |  \_
 | IF [ cmd{0} == '\0' ]
 |  | RET [ FALSE ]
 |  \_
 | o.cmd = (String.of)[ cmd ]
 | ; ,png,jpg, -- lower case, no blanks, so ",png," finds png alone
 | o.exts = (String.of)[ "," ]
 | FOR [ USIZE i = 0 | exts{i} != '\0' | i += 1 ]
 |  | C1 c = exts{i}
 |  | IF [ c != ' ' && c != '.' ]
 |  |  | (o.exts.push)[ SELECT [ c >= 'A' && c <= 'Z' | (c + 32) AS C1 | c ] ]
 |  |  \_
 |  \_
 | (o.exts.push)[ ',' ]
 | (CFG.openers.push)[ o ]
 | RET [ TRUE ]
 \_

; one `key = value`; FALSE: the key is not known, or the value not good
LOCAL B1 config_set: [ @CONST C1 k | @CONST C1 v ]
 | IF [ (str_eq)[ k | "hidden" ] ]
 |  | RET [ (read_bool)[ v | @(CFG.hidden) ] ]
 |  \_
 | IF [ (str_eq)[ k | "root_hidden" ] ]
 |  | RET [ (read_bool)[ v | @(CFG.root_hidden) ] ]
 |  \_
 | IF [ (str_eq)[ k | "confirm_delete" ] ]
 |  | RET [ (read_bool)[ v | @(CFG.confirm_delete) ] ]
 |  \_
 | IF [ (str_eq)[ k | "sort_desc" ] ]
 |  | RET [ (read_bool)[ v | @(CFG.sort_desc) ] ]
 |  \_
 | IF [ (str_eq)[ k | "places_width" ] ]
 |  | RET [ (read_int)[ v | 5 | 50 | @(CFG.places_width) ] ]
 |  \_
 | IF [ (str_eq)[ k | "root_width" ] ]
 |  | RET [ (read_int)[ v | 5 | 50 | @(CFG.root_width) ] ]
 |  \_
 | IF [ (str_eq)[ k | "preview_width" ] ]
 |  | RET [ (read_int)[ v | 5 | 50 | @(CFG.preview_width) ] ]
 |  \_
 | IF [ (str_eq)[ k | "sort" ] ]
 |  | IF [ (str_eq)[ v | "name" ] ]
 |  |  | CFG.sort = 0
 |  | ELIF [ (str_eq)[ v | "size" ] ]
 |  |  | CFG.sort = 1
 |  | ELIF [ (str_eq)[ v | "date" ] ]
 |  |  | CFG.sort = 2
 |  | ELSE
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | RET [ TRUE ]
 |  \_
 | IF [ (str_eq)[ k | "places.standard" ] ]
 |  | RET [ (read_bool)[ v | @(CFG.std_places) ] ]
 |  \_
 | IF [ (str_eq)[ k | "places.devices" ] ]
 |  | RET [ (read_bool)[ v | @(CFG.devices) ] ]
 |  \_
 | ; key, path, | name: checked as the places are read
 | IF [ (str_eq)[ k | "place" ] ]
 |  | IF [ v{0} == '\0' || v{1} != ' ' ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | (CFG.places.push)[ (String.of)[ v ] ]
 |  | RET [ TRUE ]
 |  \_
 | ; open.pdf,djvu = zathura %f -- open.* for any; term: for a terminal one
 | IF [ (str_starts)[ k | "open." ] ]
 |  | RET [ (opener_add)[ k + 5 | v ] ]
 |  \_
 | IF [ (str_eq)[ k | "tab" ] ]
 |  | C1 path{4096}
 |  | (expand_home)[ v | path | 4096 ]
 |  | (CFG.tabs.push)[ (String.of)[ path AS @CONST C1 ] ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (str_starts)[ k | "color." ] ]
 |  | FOR [ I32 i = 0 | i < NCOLORS | i += 1 ]
 |  |  | IF [ (str_eq)[ k + 6 | COLOR_NAMES{i} ] ]
 |  |  |  | RET [ (read_color)[ v | @(CFG.colors{i}) ] ]
 |  |  |  \_
 |  |  \_
 |  | RET [ FALSE ]
 |  \_
 | RET [ FALSE ]
 \_

; the config file's path, in `out`: $PLUF_CONFIG, or ~/.config/pluf/config
ABYSS config_path: [ @C1 out | USIZE cap ]
 | Option<@CONST C1> given = (env)[ "PLUF_CONFIG" ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | IF [ (given.is_some)[] ]
 |  | (b.print)[ "%s" | (given.unwrap)[] ]
 | ELSE
 |  | (b.print)[ "%s/.config/pluf/config" | ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 \_

; CFG and the palette, from the file
ABYSS config_load: []
 | C1 file{4096}
 | (config_path)[ file | 4096 ]
 | String text
 | POSTLUDE (text.deinit)[]
 | IF [ ((read_file)[ file AS @CONST C1 | @text ].is_ok)[] ]
 |  | Split lines = (Split.over)[ (text.cstr)[] | '\n' ]
 |  | C1 buf{CONFIG_LINE}
 |  | I32 no = 0
 |  | WHILE [ (lines.next)[ buf | CONFIG_LINE ] ]
 |  |  | no += 1
 |  |  | ; a # begins a comment at the start of a line, or alone after a
 |  |  | ; blank: "# ..." -- not the # of a colour, #ffaf00
 |  |  | FOR [ USIZE i = 0 | buf{i} != '\0' | i += 1 ]
 |  |  |  | IF [ buf{i} == '#' && (i == 0 || ((buf{i - 1} == ' ' || buf{i - 1} == '\t') && (buf{i + 1} == ' ' || buf{i + 1} == '\0'))) ]
 |  |  |  |  | buf{i} = '\0'
 |  |  |  |  | BREAK
 |  |  |  |  \_
 |  |  |  \_
 |  |  | @C1 line = (trim)[ buf ]
 |  |  | IF [ line{0} == '\0' ]
 |  |  |  | CONTINUE
 |  |  |  \_
 |  |  | @C1 eq = line
 |  |  | WHILE [ ?eq != '\0' && ?eq != '=' ]
 |  |  |  | eq += 1
 |  |  |  \_
 |  |  | B1 ok = FALSE
 |  |  | IF [ ?eq == '=' ]
 |  |  |  | ?eq = '\0'
 |  |  |  | ok = (config_set)[ (trim)[ line ] AS @CONST C1 | (trim)[ eq + 1 ] AS @CONST C1 ]
 |  |  |  \_
 |  |  | IF [ !ok ]
 |  |  |  | (stderr.print)[ "pluf: %s:%d: not understood, left out\n" | file AS @CONST C1 | no ]
 |  |  |  \_
 |  |  \_
 |  \_
 \_

ABYSS config_free: []
 | FOR [ USIZE i = 0 | i < (CFG.tabs.size)[] | i += 1 ]
 |  | ((CFG.tabs.at)[ i ].deinit)[]
 |  \_
 | (CFG.tabs.deinit)[]
 | FOR [ USIZE i = 0 | i < (CFG.places.size)[] | i += 1 ]
 |  | ((CFG.places.at)[ i ].deinit)[]
 |  \_
 | (CFG.places.deinit)[]
 | FOR [ USIZE i = 0 | i < (CFG.openers.size)[] | i += 1 ]
 |  | ((CFG.openers.at)[ i ].exts.deinit)[]
 |  | ((CFG.openers.at)[ i ].cmd.deinit)[]
 |  \_
 | (CFG.openers.deinit)[]
 \_
