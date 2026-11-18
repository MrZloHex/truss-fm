; main.pl -- trufm: a file manager and picker. The folder to start in from
; the command line, the config, App, and modular's loop running frame

USE <std/os/args.pl>
USE <std/io/io.pl>
USE <std/alloc/alloc.pl>
USE <std/core/result.pl>
USE <std/core/str.pl>
USE <std/os/os.pl>

USE <modular.pl>
!USES <core/fs.pl>
!USES <core/config.pl>
!USES <ui/look.pl>
!USES <app/app.pl>
!USES <app/state.pl>
!USES <screen/frame.pl>

; the options that take the next word as their value: modular's, then
; trufm's own
CONST @CONST C1 VALUED{} = [ "--port" | "--host" | "--font" | "--font-size" | "--width" | "--height" | "--shot" | "--shot-frame" | "--cd-file" | "--init" ]
CONST I32 NVALUED = COUNT [ VALUED ]

; the folder to start in: the first word that is not an option nor an
; option's value; NULL when there is none
@CONST C1 start_path: [ @Args args ]
 | FOR [ USIZE i = 1 | i < (args.size)[] | i += 1 ]
 |  | @CONST C1 w = (args.get)[ i ]
 |  | IF [ w{0} != '-' ]
 |  |  | RET [ w ]
 |  |  \_
 |  | FOR [ I32 k = 0 | k < NVALUED | k += 1 ]
 |  |  | IF [ (str_eq)[ w | VALUED{k} ] ]
 |  |  |  | i += 1
 |  |  |  \_
 |  |  \_
 |  \_
 | RET [ NULL ]
 \_

; --init: the shell function that makes Q take the shell to the folder
; trufm was in -- a program cannot change its shell's folder itself, so trufm
; writes it to a file and the function goes there
CONST @CONST C1 INIT_SH = "trufm() {\n  local f d\n  f=$(mktemp) || return\n  command trufm --cd-file \"$f\" \"$@\"\n  d=$(cat -- \"$f\" 2>/dev/null)\n  rm -f -- \"$f\"\n  [ -n \"$d\" ] && [ -d \"$d\" ] && [ \"$d\" != \"$PWD\" ] && cd -- \"$d\"\n}\n"
CONST @CONST C1 INIT_FISH = "function trufm\n    set -l f (mktemp); or return\n    command trufm --cd-file $f $argv\n    set -l d (cat -- $f 2>/dev/null)\n    rm -f -- $f\n    if test -n \"$d\" -a -d \"$d\" -a \"$d\" != \"$PWD\"\n        cd -- $d\n    end\nend\n"

ABYSS usage: [ @File to ]
 | (to.puts)[ "trufm -- a file manager\n\n" ]
 | (to.puts)[ "usage: trufm [FOLDER] [options]\n\n" ]
 | (to.puts)[ "  --gui                        in an X11 window\n" ]
 | (to.puts)[ "  --font NAME, --font-size N   the window's face\n" ]
 | (to.puts)[ "  --init bash|zsh|fish         print a shell function: Q then leaves the shell\n" ]
 | (to.puts)[ "                               in trufm's folder; eval \"$(trufm --init zsh)\"\n" ]
 | (to.puts)[ "  --cd-file FILE               where Q writes that folder (the function uses it)\n" ]
 | (to.puts)[ "  --help, --version\n\n" ]
 | (to.puts)[ "With no folder named, trufm opens where it was last time, or here.\n" ]
 | (to.puts)[ "The config is ~/.config/trufm/config ($TRUFM_CONFIG); in the program, ? shows every key.\n" ]
 \_

I32 main: [ I32 argc | @@C1 argv ]
 | Args args = (Args.over)[ argc | argv ]
 | IF [ (args.has)[ "--help" ] || (args.has)[ "-h" ] ]
 |  | (usage)[ @stdout ]
 |  | RET [ 0 ]
 |  \_
 | IF [ (args.has)[ "--version" ] ]
 |  | (stdout.puts)[ "trufm 0.1.0\n" ]
 |  | RET [ 0 ]
 |  \_
 |
 | ; trufm --init zsh: the function, to eval in the shell's rc file
 | Option<@CONST C1> init = (args.after)[ "--init" ]
 | IF [ (init.is_some)[] ]
 |  | @CONST C1 sh = (init.unwrap)[]
 |  | IF [ (str_eq)[ sh | "bash" ] || (str_eq)[ sh | "zsh" ] || (str_eq)[ sh | "sh" ] ]
 |  |  | (stdout.print)[ "%s" | INIT_SH ]
 |  |  | RET [ 0 ]
 |  |  \_
 |  | IF [ (str_eq)[ sh | "fish" ] ]
 |  |  | (stdout.print)[ "%s" | INIT_FISH ]
 |  |  | RET [ 0 ]
 |  |  \_
 |  | (stderr.print)[ "trufm: --init %s: bash, zsh or fish\n" | sh ]
 |  | RET [ 1 ]
 |  \_
 | @CONST C1 named = (start_path)[ @args ]
 | @CONST C1 path = SELECT [ named == NULL | "." | named ]
 |
 | (config_load)[]
 | POSTLUDE (config_free)[]
 | (look_apply)[]
 | ; a mount over the network that does not answer is not asked: a bad path
 | IF [ !((remote_ok_deep)[ path ]) ]
 |  | (stderr.print)[ "trufm: %s: not answering\n" | path ]
 |  | RET [ 1 ]
 |  \_
 | Result<String | IoError> cwd = (get_realpath)[ path ]
 | IF [ (cwd.is_err)[] ]
 |  | (stderr.print)[ "trufm: %s: %s\n" | path | (io_error_text)[ (cwd.error)[] ] ]
 |  | RET [ 1 ]
 |  \_
 | String dir = (cwd.unwrap)[]
 | Result<FileInfo | IoError> fi = (fs_info)[ (dir.cstr)[] ]
 | IF [ (fi.is_err)[] || (fi.unwrap)[].kind != FS_DIR ]
 |  | (stderr.print)[ "trufm: %s: not a folder\n" | path ]
 |  | (dir.deinit)[]
 |  | RET [ 1 ]
 |  \_
 | App a = (App.make)[ dir ]
 | POSTLUDE (a.dispose)[]
 | ; the last run's tabs, order and hidden; a folder named goes in its open tab
 | (state_load)[ @a | SELECT [ named == NULL | NULL | (a.cwd.cstr)[] ] ]
 | ; --cd-file: where Q writes the folder it quits in
 | Option<@CONST C1> cd = (args.after)[ "--cd-file" ]
 | IF [ (cd.is_some)[] ]
 |  | (a.cd_file.deinit)[]
 |  | a.cd_file = (String.of)[ (cd.unwrap)[] ]
 |  \_
 |
 | AppConfig cfg = [ .title = "TRUFM" | .focus = "main" | .theme = (app_theme)[] ]
 | (app_run<App>)[ @cfg | argc | argv | frame | @a ]
 | (state_save)[ @a ]
 | RET [ 0 ]
 \_
