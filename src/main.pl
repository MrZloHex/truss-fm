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

; modular's options that take the next word as their value
CONST @CONST C1 VALUED{} = [ "--port" | "--host" | "--font" | "--font-size" | "--width" | "--height" | "--shot" | "--shot-frame" ]
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

I32 main: [ I32 argc | @@C1 argv ]
 | Args args = (Args.over)[ argc | argv ]
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
 |
 | AppConfig cfg = [ .title = "PLUF" | .focus = "main" | .theme = (app_theme)[] ]
 | (app_run<App>)[ @cfg | argc | argv | frame | @a ]
 | RET [ 0 ]
 \_
