; open.pl -- files opened with programs, as the config's open.<exts> lines
; say: the first rule with the file's extension, else open.*, else
; xdg-open. A program that wants the terminal (term:) gets it -- pluf steps
; aside till it ends, or in a window opens a terminal for it; any other is
; started in the background and left to run.
;
; The files never go into the command's text: the command runs under
; sh -c with them as "$@", %f where they go, so a name with spaces, quotes
; or $ in it is only a name

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/process.pl>

USE <modular.pl>
!USES <../core/config.pl>
!USES <app.pl>
!USES <../ui/main.pl>

CONST @CONST C1 OPEN_FALLBACK = "xdg-open"

; how a terminal program is run where there is no terminal to step aside
; from: in a new one, $TERMINAL or else xterm; and how a program is left
; to run: away from pluf's terminal, so it cannot read its keys
CONST @CONST C1 SH_IN_TERMINAL = "l=$1; shift; (${TERMINAL:-xterm} -e sh -c \"$l\" pluf \"$@\") </dev/null >/dev/null 2>&1 &"
CONST @CONST C1 SH_IN_BACKGROUND = "l=$1; shift; (sh -c \"$l\" pluf \"$@\") </dev/null >/dev/null 2>&1 &"

; the opener for the file `name`: the first rule with its extension, or
; else the first open.*; NULL: none, xdg-open then
@Opener opener_for: [ @CONST C1 name ]
 | ; its extension, lower case, between commas: ,pdf, -- none for .bashrc
 | USIZE dot = 0
 | FOR [ USIZE i = 1 | name{i} != '\0' | i += 1 ]
 |  | IF [ name{i} == '.' ]
 |  |  | dot = i
 |  |  \_
 |  \_
 | C1 want{64}
 | want{0} = '\0'
 | IF [ dot > 0 && (str_len)[ name + dot + 1 ] < 60 ]
 |  | BufferSink b = (BufferSink.over)[ want | 64 ]
 |  | (b.print)[ ",%s," | name + dot + 1 ]
 |  | FOR [ USIZE i = 0 | want{i} != '\0' | i += 1 ]
 |  |  | IF [ want{i} >= 'A' && want{i} <= 'Z' ]
 |  |  |  | want{i} = (want{i} + 32) AS C1
 |  |  |  \_
 |  |  \_
 |  \_
 |
 | @Opener any = NULL
 | FOR [ USIZE i = 0 | i < (CFG.openers.size)[] | i += 1 ]
 |  | @Opener o = (CFG.openers.at)[ i ]
 |  | IF [ want{0} != '\0' && (o.exts.contains)[ want AS @CONST C1 ] ]
 |  |  | RET [ o ]
 |  |  \_
 |  | IF [ any == NULL && (o.exts.contains)[ ",*," ] ]
 |  |  | any = o
 |  |  \_
 |  \_
 | RET [ any ]
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

; is the program `cmd` begins with there to be run? A name that sh finds
B1 program_there: [ @CONST C1 cmd ]
 | C1 word{256}
 | USIZE n = 0
 | WHILE [ cmd{n} != '\0' && cmd{n} != ' ' && n + 1 < 256 ]
 |  | word{n} = cmd{n}
 |  | n += 1
 |  \_
 | word{n} = '\0'
 | @CONST C1 argv{} = [ "sh" | "-c" | "command -v \"$1\" >/dev/null 2>&1" | "pluf" | word AS @CONST C1 | NULL ]
 | Result<ExitStatus | IoError> r = (process_run)[ argv ]
 | RET [ (r.is_ok)[] && (r.unwrap)[].exited && (r.unwrap)[].code == 0 ]
 \_

; `files` opened with `cmd`; `term`: in this terminal, pluf stepped aside
; till it ends -- or, in a window, in a new terminal. In `why` what went
; wrong; FALSE then
B1 open_with: [ @Ui ui | @CONST C1 cmd | B1 term | @Vector<String> files | @String why ]
 | IF [ !((program_there)[ cmd ]) ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ cmd ]
 |  | (why.append)[ ": no such program" ]
 |  | RET [ FALSE ]
 |  \_
 | String line = (shell_line)[ cmd ]
 | POSTLUDE (line.deinit)[]
 | B1 here = term && (ui.can_pause)[]
 |
 | ; sh -c <script> pluf [<line>] <files>... NULL
 | Vector<@CONST C1> argv
 | POSTLUDE (argv.deinit)[]
 | (argv.push)[ "sh" ]
 | (argv.push)[ "-c" ]
 | IF [ here ]
 |  | (argv.push)[ (line.cstr)[] ]
 |  | (argv.push)[ "pluf" ]
 | ELSE
 |  | (argv.push)[ SELECT [ term | SH_IN_TERMINAL | SH_IN_BACKGROUND ] ]
 |  | (argv.push)[ "pluf" ]
 |  | (argv.push)[ (line.cstr)[] ]
 |  \_
 | FOR [ USIZE i = 0 | i < (files.size)[] | i += 1 ]
 |  | (argv.push)[ ((files.at)[ i ].cstr)[] ]
 |  \_
 | (argv.push)[ NULL ]
 |
 | IF [ here ]
 |  | (ui.pause)[ TRUE ]
 |  \_
 | Result<ExitStatus | IoError> r = (process_run)[ argv.data AS @CONST @CONST C1 ]
 | IF [ here ]
 |  | (ui.pause)[ FALSE ]
 |  \_
 | IF [ (r.is_err)[] ]
 |  | (why.deinit)[]
 |  | ?why = (String.of)[ (io_error_text)[ (r.error)[] ] ]
 |  | RET [ FALSE ]
 |  \_
 | RET [ TRUE ]
 \_

; --- what Enter, l, → on a file and o do to App ---------------------------------

; the rows chosen in visual, or the file under the cursor, opened with the
; program the config gives the cursor's file
ABYSS open_now: [ @AppData me | @Ui ui ]
 | (strings_clear)[ @(me.pending) ]
 | (main_selection)[ @(me.listing) | @(me.pending) ]
 | IF [ (me.pending.size)[] == 0 ]
 |  | RET []
 |  \_
 | String name = (get_dirname)[ ((me.pending.at)[ 0 ].cstr)[] ]
 | @Opener o = (opener_for)[ (name.cstr)[] ]
 | (name.deinit)[]
 | IF [ o == NULL ]
 |  | (open_run)[ me | ui | OPEN_FALLBACK | FALSE ]
 | ELSE
 |  | (open_run)[ me | ui | (o.cmd.cstr)[] | o.term ]
 |  \_
 \_

; the same, asked first with what: the program it would be, to change
ABYSS open_ask: [ @AppData me ]
 | (strings_clear)[ @(me.pending) ]
 | (main_selection)[ @(me.listing) | @(me.pending) ]
 | IF [ (me.pending.size)[] == 0 ]
 |  | RET []
 |  \_
 | String name = (get_dirname)[ ((me.pending.at)[ 0 ].cstr)[] ]
 | @Opener o = (opener_for)[ (name.cstr)[] ]
 | (name.deinit)[]
 | C1 s{INPUT_CAP}
 | BufferSink b = (BufferSink.over)[ s | INPUT_CAP AS USIZE ]
 | IF [ o == NULL ]
 |  | (b.print)[ "%s" | OPEN_FALLBACK ]
 | ELIF [ o.term ]
 |  | (b.print)[ "term: %s" | (o.cmd.cstr)[] ]
 | ELSE
 |  | (b.print)[ "%s" | (o.cmd.cstr)[] ]
 |  \_
 | (input_set)[ @(me.field) | s AS @CONST C1 ]
 | me.prompt = PR_OPEN
 \_

; the command typed for `pending`: term: before it for a terminal one
ABYSS open_typed: [ @AppData me | @Ui ui | @CONST C1 typed ]
 | me.prompt = PR_NONE
 | B1 term = (str_starts)[ typed | "term:" ]
 | @CONST C1 cmd = typed
 | IF [ term ]
 |  | cmd = typed + 5
 |  \_
 | WHILE [ ?cmd == ' ' ]
 |  | cmd += 1
 |  \_
 | IF [ cmd{0} == '\0' ]
 |  | RET []
 |  \_
 | (open_run)[ me | ui | cmd | term ]
 \_

; `pending` opened with `cmd`; what went wrong said
ABYSS open_run: [ @AppData me | @Ui ui | @CONST C1 cmd | B1 term ]
 | String why = (String.of)[ "" ]
 | POSTLUDE (why.deinit)[]
 | IF [ !((open_with)[ ui | cmd | term | @(me.pending) | @why ]) ]
 |  | (app_note)[ me | (why.cstr)[] ]
 |  \_
 | (strings_clear)[ @(me.pending) ]
 | ; what it did may have changed the folder: an editor saved, a tar made
 | (app_refresh)[ me | TRUE ]
 \_
