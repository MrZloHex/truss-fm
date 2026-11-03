; rules.pl -- which config rule fits a file: open.<exts> and preview.<exts>
; lines alike. A rule fits by the file's extension, or -- one with a / in
; it -- by its MIME type, as `file --mime-type` tells it, asked only when a
; rule wants it. Rules are tried in the config's order; open.* (preview.*)
; fits anything, but only when nothing else did.
;
; And how a rule's command is run: under sh -c, the files as "$@" -- %f
; where they go, else after it -- so no file's name is ever in its text

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/process.pl>

!USES <config.pl>
!USES <fs.pl>

; the extension of `name`, lower case, between commas, in `out` (64): ,pdf,
; -- "" for none, as .bashrc has
ABYSS ext_key: [ @CONST C1 name | @C1 out ]
 | out{0} = '\0'
 | USIZE dot = 0
 | FOR [ USIZE i = 1 | name{i} != '\0' | i += 1 ]
 |  | IF [ name{i} == '.' ]
 |  |  | dot = i
 |  |  \_
 |  \_
 | IF [ dot == 0 || (str_len)[ name + dot + 1 ] >= 60 ]
 |  | RET []
 |  \_
 | BufferSink b = (BufferSink.over)[ out | 64 ]
 | (b.print)[ ",%s," | name + dot + 1 ]
 | FOR [ USIZE i = 0 | out{i} != '\0' | i += 1 ]
 |  | IF [ out{i} >= 'A' && out{i} <= 'Z' ]
 |  |  | out{i} = (out{i} + 32) AS C1
 |  |  \_
 |  \_
 \_

; the MIME type of the file at `path`, in `out` (128): image/png; "" when
; `file` cannot say
ABYSS mime_of: [ @CONST C1 path | @C1 out ]
 | out{0} = '\0'
 | @CONST C1 argv{} = [ "file" | "-b" | "-L" | "--mime-type" | "--" | path | NULL ]
 | String said = (String.of)[ "" ]
 | POSTLUDE (said.deinit)[]
 | IF [ ((process_output<System>)[ argv | @said ].is_err)[] ]
 |  | RET []
 |  \_
 | USIZE n = 0
 | @CONST C1 s = (said.cstr)[]
 | WHILE [ s{n} != '\0' && s{n} != '\n' && n + 1 < 128 ]
 |  | out{n} = s{n}
 |  | n += 1
 |  \_
 | out{n} = '\0'
 \_

; does one of the rule's MIME items -- image/*, text/plain -- fit `mime`?
LOCAL B1 mime_fits: [ @CONST C1 exts | @CONST C1 mime ]
 | IF [ mime{0} == '\0' ]
 |  | RET [ FALSE ]
 |  \_
 | USIZE i = 1
 | WHILE [ exts{i} != '\0' ]
 |  | USIZE j = i
 |  | WHILE [ exts{j} != '\0' && exts{j} != ',' ]
 |  |  | j += 1
 |  |  \_
 |  | ; the item exts{i .. j}: a / in it makes it a MIME type
 |  | USIZE n = j - i
 |  | B1 slash = FALSE
 |  | FOR [ USIZE k = i | k < j | k += 1 ]
 |  |  | IF [ exts{k} == '/' ]
 |  |  |  | slash = TRUE
 |  |  |  \_
 |  |  \_
 |  | IF [ slash && n >= 2 && exts{j - 1} == '*' && exts{j - 2} == '/' ]
 |  |  | ; image/* -- the part before the * the start of the type
 |  |  | B1 same = TRUE
 |  |  | FOR [ USIZE k = 0 | k < n - 1 | k += 1 ]
 |  |  |  | IF [ mime{k} != exts{i + k} ]
 |  |  |  |  | same = FALSE
 |  |  |  |  | BREAK
 |  |  |  |  \_
 |  |  |  \_
 |  |  | IF [ same ]
 |  |  |  | RET [ TRUE ]
 |  |  |  \_
 |  | ELIF [ slash && (str_len)[ mime ] == n ]
 |  |  | B1 same = TRUE
 |  |  | FOR [ USIZE k = 0 | k < n | k += 1 ]
 |  |  |  | IF [ mime{k} != exts{i + k} ]
 |  |  |  |  | same = FALSE
 |  |  |  |  | BREAK
 |  |  |  |  \_
 |  |  |  \_
 |  |  | IF [ same ]
 |  |  |  | RET [ TRUE ]
 |  |  |  \_
 |  |  \_
 |  | IF [ exts{j} == '\0' ]
 |  |  | BREAK
 |  |  \_
 |  | i = j + 1
 |  \_
 | RET [ FALSE ]
 \_

; every rule of `rules` that fits the file at `path`, in `out`, in order:
; those by extension or type first, then the open.* ones. The MIME type is
; asked only when a rule has one
ABYSS rules_for: [ @Vector<Opener> rules | @CONST C1 path | @Vector<@Opener> out ]
 | String name = (get_dirname)[ path ]
 | C1 want{64}
 | (ext_key)[ (name.cstr)[] | want ]
 | (name.deinit)[]
 | C1 mime{128}
 | B1 asked = FALSE
 | FOR [ USIZE i = 0 | i < (rules.size)[] | i += 1 ]
 |  | @Opener o = (rules.at)[ i ]
 |  | @CONST C1 exts = (o.exts.cstr)[]
 |  | B1 fits = want{0} != '\0' && (o.exts.contains)[ want AS @CONST C1 ]
 |  | IF [ !fits && (o.exts.contains)[ "/" ] ]
 |  |  | IF [ !asked ]
 |  |  |  | (mime_of)[ path | mime ]
 |  |  |  | asked = TRUE
 |  |  |  \_
 |  |  | fits = (mime_fits)[ exts | mime AS @CONST C1 ]
 |  |  \_
 |  | IF [ fits ]
 |  |  | (out.push)[ o ]
 |  |  \_
 |  \_
 | FOR [ USIZE i = 0 | i < (rules.size)[] | i += 1 ]
 |  | @Opener o = (rules.at)[ i ]
 |  | IF [ (o.exts.contains)[ ",*," ] ]
 |  |  | (out.push)[ o ]
 |  |  \_
 |  \_
 \_

; the first rule of `rules` that fits the file at `path`; NULL: none
@Opener rule_for: [ @Vector<Opener> rules | @CONST C1 path ]
 | Vector<@Opener> all
 | POSTLUDE (all.deinit)[]
 | (rules_for)[ rules | path | @all ]
 | IF [ (all.size)[] == 0 ]
 |  | RET [ NULL ]
 |  \_
 | RET [ (all.get)[ 0 ] ]
 \_

; `cmd` as a line for sh, the files in "$@": at each %f, or else at the end
String shell_line: [ @CONST C1 cmd ]
 | String out = (String.of)[ "" ]
 | B1 placed = FALSE
 | FOR [ USIZE i = 0 | cmd{i} != '\0' | i += 1 ]
 |  | IF [ cmd{i} == '%' && cmd{i + 1} == 'f' ]
 |  |  | (out.append)[ "\"$@\"" ]
 |  |  | placed = TRUE
 |  |  | i += 1
 |  |  | CONTINUE
 |  |  \_
 |  | (out.push)[ cmd{i} ]
 |  \_
 | IF [ !placed ]
 |  | (out.append)[ " \"$@\"" ]
 |  \_
 | RET [ out ]
 \_

; is the program `cmd` begins with there to be run? A name that sh finds,
; once sh has expanded it -- ${EDITOR:-vi} is vi when EDITOR is not set
B1 program_there: [ @CONST C1 cmd ]
 | C1 word{256}
 | USIZE n = 0
 | WHILE [ cmd{n} != '\0' && cmd{n} != ' ' && n + 1 < 256 ]
 |  | word{n} = cmd{n}
 |  | n += 1
 |  \_
 | word{n} = '\0'
 | @CONST C1 argv{} = [ "sh" | "-c" | "eval \"set -- $1\" 2>/dev/null && command -v \"$1\" >/dev/null 2>&1" | "pluf" | word AS @CONST C1 | NULL ]
 | Result<ExitStatus | IoError> r = (process_run)[ argv ]
 | RET [ (r.is_ok)[] && (r.unwrap)[].exited && (r.unwrap)[].code == 0 ]
 \_
