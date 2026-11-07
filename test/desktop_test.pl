; desktop_test.pl -- base64 and OSC 52 (clip.pl), the mimeapps.list and
; mimeinfo.cache lookup, Exec lines as commands (desktop.pl), and shell_word
; and shell_line (rules.pl)
USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
!USES <../src/core/clip.pl>
!USES <../src/core/desktop.pl>
!USES <../src/core/rules.pl>

LOCAL I32 bad = 0

LOCAL ABYSS want: [ B1 ok | @CONST C1 what ]
 | IF [ !ok ]
 |  | (stderr.print)[ "FAIL: %s\n" | what ]
 |  | bad += 1
 |  \_
 \_

LOCAL ABYSS b64: [ @CONST C1 in | @CONST C1 expect ]
 | String s = (base64)[ in | (str_len)[ in ] ]
 | (want)[ (str_eq)[ (s.cstr)[] | expect ] | expect ]
 | (s.deinit)[]
 \_

LOCAL ABYSS exec: [ @CONST C1 in | @CONST C1 expect ]
 | String s = (desk_exec)[ in ]
 | (want)[ (str_eq)[ (s.cstr)[] | expect ] | in ]
 | IF [ !((str_eq)[ (s.cstr)[] | expect ]) ]
 |  | (stderr.print)[ "  got: %s\n" | (s.cstr)[] ]
 |  \_
 | (s.deinit)[]
 \_

LOCAL ABYSS word: [ @CONST C1 in | @CONST C1 expect ]
 | String s = (shell_word)[ in ]
 | (want)[ (str_eq)[ (s.cstr)[] | expect ] | expect ]
 | (s.deinit)[]
 \_

LOCAL ABYSS line: [ @CONST C1 in | @CONST C1 expect ]
 | String s = (shell_line)[ in ]
 | (want)[ (str_eq)[ (s.cstr)[] | expect ] | expect ]
 | (s.deinit)[]
 \_

LOCAL ABYSS put: [ @CONST C1 path | @CONST C1 text ]
 | I32 fd = (px_open)[ path | O_MAKE | 0x1A4 ]
 | (px_write)[ fd | text AS @CONST ABYSS | (str_len)[ text ] ]
 | (px_close)[ fd ]
 \_

LOCAL B1 names_are: [ @Vector<DeskApp> v | @CONST C1 list ]
 | String got = (String.of)[ "" ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | (got.append)[ ((v.at)[ i ].id.cstr)[] ]
 |  | (got.push)[ ' ' ]
 |  \_
 | B1 same = (got.equals)[ list ]
 | IF [ !same ]
 |  | (stderr.print)[ "  apps: %s\n" | (got.cstr)[] ]
 |  \_
 | (got.deinit)[]
 | RET [ same ]
 \_

I32 main: []
 | (b64)[ "" | "" ]
 | (b64)[ "f" | "Zg==" ]
 | (b64)[ "fo" | "Zm8=" ]
 | (b64)[ "foo" | "Zm9v" ]
 | (b64)[ "foob" | "Zm9vYg==" ]
 | (b64)[ "fooba" | "Zm9vYmE=" ]
 | (b64)[ "foobar" | "Zm9vYmFy" ]
 | (b64)[ "\xFF\xFE" | "//4=" ]
 | String osc = (clip_osc52)[ "a b" ]
 | (want)[ (str_eq)[ (osc.cstr)[] | "\e]52;c;YSBi\a" ] | "osc 52" ]
 | (osc.deinit)[]
 |
 | (word)[ "run.sh" | "run.sh" ]
 | (word)[ "my file" | "'my file'" ]
 | (word)[ "it's" | "'it'\\''s'" ]
 | (word)[ "a$b" | "'a$b'" ]
 | (word)[ "" | "''" ]
 | (line)[ "vim %f" | "vim \"$@\"" ]
 | (line)[ "vlc" | "vlc \"$@\"" ]
 | (line)[ "gimp %1" | "gimp \"$1\"" ]
 |
 | (exec)[ "firefox %u" | "firefox %1" ]
 | (exec)[ "gimp-2.10 %U" | "gimp-2.10 %f" ]
 | (exec)[ "app --icon %i %c %k %F" | "app --icon    %f" ]
 | (exec)[ "sh -c \"echo 100%%\"" | "sh -c \"echo 100%\"" ]
 | (exec)[ "x\\sy" | "x y" ]
 | (exec)[ "vlc" | "vlc" ]
 |
 | ; a scratch tree: a user config and data, a system data folder
 | C1 root{128}
 | BufferSink rb = (BufferSink.over)[ root | 128 ]
 | (rb.print)[ "/tmp/trufm_desktop_test.%d" | (getpid)[] AS I32 ]
 | String top = (String.of)[ root AS @CONST C1 ]
 | @CONST C1 t = (top.cstr)[]
 | @CONST C1 mk{} = [ "/uconf" | "/udata/applications" | "/sys/applications" | NULL ]
 | (fs_make_dir)[ t ]
 | FOR [ USIZE i = 0 | mk{i} != NULL | i += 1 ]
 |  | String d = (String.of)[ t ]
 |  | (d.append)[ mk{i} ]
 |  | (fs_make_dirs)[ (d.cstr)[] ]
 |  | (d.deinit)[]
 |  \_
 | String f = (String.of)[ t ]
 | USIZE base = (f.size)[]
 | (f.append)[ "/uconf/mimeapps.list" ]
 | (put)[ (f.cstr)[] | "[Default Applications]\nimage/png=b.desktop;\n[Added Associations]\nimage/png=c.desktop;z.desktop;\n[Removed Associations]\nimage/png=d.desktop;\n" ]
 | (f.truncate)[ base ]
 | (f.append)[ "/sys/applications/mimeinfo.cache" ]
 | (put)[ (f.cstr)[] | "[MIME Cache]\nimage/png=a.desktop;d.desktop;b.desktop;e.desktop;\ntext/plain=t.desktop;\n" ]
 | (f.truncate)[ base ]
 | (f.append)[ "/udata/applications/b.desktop" ]
 | (put)[ (f.cstr)[] | "[Desktop Entry]\nName=Bee\nName[de]=Biene\nExec=bee %f\nTerminal=true\n" ]
 | (f.truncate)[ base ]
 | (f.append)[ "/sys/applications/a.desktop" ]
 | (put)[ (f.cstr)[] | "[Desktop Entry]\nName=Ay\nExec=ay %F\nTryExec=ay\n[Desktop Action x]\nName=No\n" ]
 | (f.truncate)[ base ]
 | (f.append)[ "/sys/applications/c.desktop" ]
 | (put)[ (f.cstr)[] | "[Desktop Entry]\nName=Sea\nExec=sea\n" ]
 | (f.truncate)[ base ]
 | (f.append)[ "/sys/applications/d.desktop" ]
 | (put)[ (f.cstr)[] | "[Desktop Entry]\nName=Dee\nExec=dee\n" ]
 | (f.truncate)[ base ]
 | (f.append)[ "/sys/applications/e.desktop" ]
 | (put)[ (f.cstr)[] | "[Desktop Entry]\nName=Ee\nExec=ee\nHidden=true\n" ]
 | (f.truncate)[ base ]
 | (f.append)[ "/sys/applications/t.desktop" ]
 | (put)[ (f.cstr)[] | "[Desktop Entry]\nName=Tee\nExec=tee %u\n" ]
 |
 | String uc = (String.of)[ t ]
 | (uc.append)[ "/uconf" ]
 | String ud = (String.of)[ t ]
 | (ud.append)[ "/udata" ]
 | String sd = (String.of)[ t ]
 | (sd.append)[ "/sys" ]
 | Vector<DeskApp> apps
 | ; default b, added c (z has no file), a from the cache; d removed, e hidden
 | (desk_apps)[ "image/png" | (uc.cstr)[] | "/nonexistent" | (ud.cstr)[] | (sd.cstr)[] | @apps ]
 | (want)[ (names_are)[ @apps | "b.desktop c.desktop a.desktop " ] | "png apps" ]
 | IF [ (apps.size)[] >= 3 ]
 |  | (want)[ ((apps.at)[ 0 ].name.equals)[ "Bee" ] | "unlocalized name" ]
 |  | (want)[ ((apps.at)[ 0 ].command.equals)[ "term:bee %1" ] | "terminal command" ]
 |  | (want)[ ((apps.at)[ 2 ].tryexec.equals)[ "ay" ] | "tryexec" ]
 |  | (want)[ ((apps.at)[ 2 ].command.equals)[ "ay %f" ] | "Exec stops at the next group" ]
 |  \_
 | (desk_apps_free)[ @apps ]
 | ; a text type gets text/plain's too
 | (desk_apps)[ "text/x-c" | (uc.cstr)[] | "/nonexistent" | (ud.cstr)[] | (sd.cstr)[] | @apps ]
 | (want)[ (names_are)[ @apps | "t.desktop " ] | "text/plain for text" ]
 | (desk_apps_free)[ @apps ]
 | (apps.deinit)[]
 | (uc.deinit)[]
 | (ud.deinit)[]
 | (sd.deinit)[]
 | (f.deinit)[]
 | ; the tree goes
 | String rm = (String.of)[ "rm -rf " ]
 | (rm.append)[ t ]
 | @CONST C1 rmv{} = [ "sh" | "-c" | (rm.cstr)[] | NULL ]
 | (process_run)[ rmv ]
 | (rm.deinit)[]
 | (top.deinit)[]
 |
 | IF [ bad > 0 ]
 |  | RET [ 1 ]
 |  \_
 | (stdout.print)[ "desktop_test: ok\n" ]
 | RET [ 0 ]
 \_
