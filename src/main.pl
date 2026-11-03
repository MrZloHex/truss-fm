; main.pl -- pluf: a file manager and picker. The folder to start in from
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
!USES <screen/frame.pl>

; the options that take the next word as their value: modular's, then
; pluf's own
CONST @CONST C1 VALUED{} = [ "--port" | "--host" | "--font" | "--font-size" | "--width" | "--height" | "--shot" | "--shot-frame" | "--cd-file" | "--init" ]
CONST I32 NVALUED = COUNT [ VALUED ]

; the folder to start in: the first word that is not an option nor an
; option's value; "." when there is none
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
 | RET [ "." ]
 \_

; --init: the shell function that makes Q take the shell to the folder
; pluf was in -- a program cannot change its shell's folder itself, so pluf
; writes it to a file and the function goes there
CONST @CONST C1 INIT_SH = "pluf() {\n  local f d\n  f=$(mktemp) || return\n  command pluf --cd-file \"$f\" \"$@\"\n  d=$(cat -- \"$f\" 2>/dev/null)\n  rm -f -- \"$f\"\n  [ -n \"$d\" ] && [ -d \"$d\" ] && [ \"$d\" != \"$PWD\" ] && cd -- \"$d\"\n}\n"
CONST @CONST C1 INIT_FISH = "function pluf\n    set -l f (mktemp); or return\n    command pluf --cd-file $f $argv\n    set -l d (cat -- $f 2>/dev/null)\n    rm -f -- $f\n    if test -n \"$d\" -a -d \"$d\" -a \"$d\" != \"$PWD\"\n        cd -- $d\n    end\nend\n"

I32 main: [ I32 argc | @@C1 argv ]
 | Args args = (Args.over)[ argc | argv ]
 |
 | ; pluf --init zsh: the function, to eval in the shell's rc file
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
 |  | (stderr.print)[ "pluf: --init %s: bash, zsh or fish\n" | sh ]
 |  | RET [ 1 ]
 |  \_
 | @CONST C1 path = (start_path)[ @args ]
 |
 | (config_load)[]
 | POSTLUDE (config_free)[]
 | (look_apply)[]
 | Result<String | IoError> cwd = (get_realpath)[ path ]
 | IF [ (cwd.is_err)[] ]
 |  | (stderr.print)[ "pluf: %s: %s\n" | path | (io_error_text)[ (cwd.error)[] ] ]
 |  | RET [ 1 ]
 |  \_
 | String dir = (cwd.unwrap)[]
 | Result<FileInfo | IoError> fi = (fs_info)[ (dir.cstr)[] ]
 | IF [ (fi.is_err)[] || (fi.unwrap)[].kind != FS_DIR ]
 |  | (stderr.print)[ "pluf: %s: not a folder\n" | path ]
 |  | (dir.deinit)[]
 |  | RET [ 1 ]
 |  \_
 | App a = (App.make)[ dir ]
 | POSTLUDE (a.dispose)[]
 | ; --cd-file: where Q writes the folder it quits in
 | Option<@CONST C1> cd = (args.after)[ "--cd-file" ]
 | IF [ (cd.is_some)[] ]
 |  | (a.cd_file.deinit)[]
 |  | a.cd_file = (String.of)[ (cd.unwrap)[] ]
 |  \_
 |
 | AppConfig cfg = [ .title = "PLUF" | .focus = "main" | .theme = (app_theme)[] ]
 | (app_run<App>)[ @cfg | argc | argv | frame | @a ]
 | RET [ 0 ]
 \_
