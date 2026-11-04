; open.pl -- files opened with programs, as the config's open.<exts> lines
; say: the first rule with the file's extension, else open.*, else
; xdg-open. A program that wants the terminal (term:) gets it -- trufm steps
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
!USES <../core/rules.pl>
!USES <app.pl>
!USES <../ui/main.pl>

CONST @CONST C1 OPEN_FALLBACK = "xdg-open"

; how a terminal program is run where there is no terminal to step aside
; from: in a new one, $TERMINAL or else xterm; and how a program is left
; to run: away from trufm's terminal, so it cannot read its keys
CONST @CONST C1 SH_IN_TERMINAL = "l=$1; shift; (${TERMINAL:-xterm} -e sh -c \"$l\" trufm \"$@\") </dev/null >/dev/null 2>&1 &"
; a command typed after : -- run in the folder ($1), the chosen files after
; it, then waits for Enter, so what it printed can be read
CONST @CONST C1 SH_SHELL = "cd -- \"$1\" && { c=$2; shift 2; sh -c \"$c\" sh \"$@\"; }; s=$?; echo; printf '[exit %s] Enter goes back to trufm ' $s; read _ </dev/tty"
CONST @CONST C1 SH_IN_BACKGROUND = "l=$1; shift; (sh -c \"$l\" trufm \"$@\") </dev/null >/dev/null 2>&1 &"

; `files` opened with `cmd`; `term`: in this terminal, trufm stepped aside
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
 | ; sh -c <script> trufm [<line>] <files>... NULL
 | Vector<@CONST C1> argv
 | POSTLUDE (argv.deinit)[]
 | (argv.push)[ "sh" ]
 | (argv.push)[ "-c" ]
 | IF [ here ]
 |  | (argv.push)[ (line.cstr)[] ]
 |  | (argv.push)[ "trufm" ]
 | ELSE
 |  | (argv.push)[ SELECT [ term | SH_IN_TERMINAL | SH_IN_BACKGROUND ] ]
 |  | (argv.push)[ "trufm" ]
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

; `cmd` run by sh in `dir`, `files` as "$@": in this terminal, trufm stepped
; aside till Enter after it -- or, in a window, in a new terminal. In `why`
; what went wrong; FALSE then
B1 shell_with: [ @Ui ui | @CONST C1 dir | @CONST C1 cmd | @Vector<String> files | @String why ]
 | B1 here = (ui.can_pause)[]
 |
 | ; sh -c <script> trufm [<script>] <dir> <cmd> <files>... NULL
 | Vector<@CONST C1> argv
 | POSTLUDE (argv.deinit)[]
 | (argv.push)[ "sh" ]
 | (argv.push)[ "-c" ]
 | IF [ here ]
 |  | (argv.push)[ SH_SHELL ]
 |  | (argv.push)[ "trufm" ]
 | ELSE
 |  | (argv.push)[ SH_IN_TERMINAL ]
 |  | (argv.push)[ "trufm" ]
 |  | (argv.push)[ SH_SHELL ]
 |  \_
 | (argv.push)[ dir ]
 | (argv.push)[ cmd ]
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
 | @Opener o = (rule_for)[ @(CFG.openers) | ((me.pending.at)[ 0 ].cstr)[] ]
 | IF [ o == NULL ]
 |  | (open_run)[ me | ui | OPEN_FALLBACK | FALSE ]
 | ELSE
 |  | (open_run)[ me | ui | (o.cmd.cstr)[] | o.term ]
 |  \_
 \_

CONST USIZE MAX_CHOICES = 9

; the same, asked first with what: every rule that fits, in the config's
; order, then xdg-open -- each once -- to pick from by 1 to 9
ABYSS open_ask: [ @AppData me ]
 | (strings_clear)[ @(me.pending) ]
 | (main_selection)[ @(me.listing) | @(me.pending) ]
 | IF [ (me.pending.size)[] == 0 ]
 |  | RET []
 |  \_
 | (strings_clear)[ @(me.choices) ]
 | Vector<@Opener> fits
 | (rules_for)[ @(CFG.openers) | ((me.pending.at)[ 0 ].cstr)[] | @fits ]
 | FOR [ USIZE i = 0 | i <= (fits.size)[] && (me.choices.size)[] < MAX_CHOICES | i += 1 ]
 |  | C1 s{INPUT_CAP}
 |  | BufferSink b = (BufferSink.over)[ s | INPUT_CAP AS USIZE ]
 |  | IF [ i == (fits.size)[] ]
 |  |  | (b.print)[ "%s" | OPEN_FALLBACK ]
 |  | ELSE
 |  |  | @Opener o = (fits.get)[ i ]
 |  |  | (b.print)[ "%s%s" | SELECT [ o.term | "term: " | "" ] | (o.cmd.cstr)[] ]
 |  |  \_
 |  | B1 seen = FALSE
 |  | FOR [ USIZE k = 0 | k < (me.choices.size)[] | k += 1 ]
 |  |  | seen = seen || ((me.choices.at)[ k ].equals)[ s AS @CONST C1 ]
 |  |  \_
 |  | IF [ !seen ]
 |  |  | (me.choices.push)[ (String.of)[ s AS @CONST C1 ] ]
 |  |  \_
 |  \_
 | (fits.deinit)[]
 | me.prompt = PR_CHOOSE
 \_

; choice `i` of those on offer: opened with it
ABYSS open_pick: [ @AppData me | @Ui ui | USIZE i ]
 | IF [ i >= (me.choices.size)[] ]
 |  | RET []
 |  \_
 | C1 s{INPUT_CAP}
 | (str_copy)[ s | INPUT_CAP AS USIZE | ((me.choices.at)[ i ].cstr)[] ]
 | (open_typed)[ me | ui | s AS @CONST C1 ]
 \_

; none of those: a command to type, the first on offer to begin from
ABYSS open_edit: [ @AppData me ]
 | ; not SELECT: it would read choice 0 when there is none
 | IF [ (me.choices.size)[] > 0 ]
 |  | (input_set)[ @(me.field) | ((me.choices.at)[ 0 ].cstr)[] ]
 | ELSE
 |  | (input_set)[ @(me.field) | OPEN_FALLBACK ]
 |  \_
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

; --- : a command line --------------------------------------------------------

ABYSS shell_ask: [ @AppData me ]
 | (input_set)[ @(me.field) | "" ]
 | me.prompt = PR_SHELL
 \_

; the command typed after :, run in the folder, the rows chosen in visual or
; the cursor's file as "$@"
ABYSS shell_typed: [ @AppData me | @Ui ui | @CONST C1 typed ]
 | me.prompt = PR_NONE
 | @CONST C1 cmd = typed
 | WHILE [ ?cmd == ' ' ]
 |  | cmd += 1
 |  \_
 | IF [ cmd{0} == '\0' ]
 |  | RET []
 |  \_
 | (strings_clear)[ @(me.pending) ]
 | (main_selection)[ @(me.listing) | @(me.pending) ]
 | String why = (String.of)[ "" ]
 | POSTLUDE (why.deinit)[]
 | IF [ !((shell_with)[ ui | (me.cwd.cstr)[] | cmd | @(me.pending) | @why ]) ]
 |  | (app_note)[ me | (why.cstr)[] ]
 |  \_
 | (strings_clear)[ @(me.pending) ]
 | ; it may have changed anything: every column read again
 | (app_refresh)[ me | TRUE ]
 \_
