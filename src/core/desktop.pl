; desktop.pl -- the programs the desktop has for a MIME type, as the
; freedesktop mime-apps spec has them: the default of mimeapps.list first,
; then its added associations (what it removes is left out), then the
; mimeinfo.cache of each applications folder. Each is a .desktop file whose
; Name= and Exec= are read; the Exec line becomes a command of the kind the
; config's open.* rules are: %f where the files go as "$@", %1 where the
; first one goes as "$1", term: before it for Terminal=true

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

!USES <sys.pl>
!USES <fs.pl>

TYPE DeskApp: STRUCT
 | String id          ; firefox.desktop
 | String name        ; Firefox
 | String command     ; the Exec line, made into a command
 | String tryexec     ; TryExec=, or ""
 \_

; no file is read past this much
CONST USIZE DESK_MAX = 4194304

; the file at `path` in `out`; FALSE if it cannot be read
LOCAL B1 desk_read: [ @CONST C1 path | @String out ]
 | I32 fd = (px_open)[ path | O_READ ]
 | IF [ fd < 0 ]
 |  | RET [ FALSE ]
 |  \_
 | C1 buf{4096}
 | USIZE total = 0
 | WHILE [ total < DESK_MAX ]
 |  | ISIZE n = (px_read)[ fd | buf AS @ABYSS | 4095 ]
 |  | IF [ n <= 0 ]
 |  |  | BREAK
 |  |  \_
 |  | buf{n AS USIZE} = '\0'
 |  | (out.append)[ buf AS @CONST C1 ]
 |  | total += n AS USIZE
 |  \_
 | (px_close)[ fd ]
 | RET [ TRUE ]
 \_

; are the `n` characters of `a` the text `b`?
LOCAL B1 desk_same: [ @CONST C1 a | USIZE n | @CONST C1 b ]
 | IF [ (str_len)[ b ] != n ]
 |  | RET [ FALSE ]
 |  \_
 | FOR [ USIZE k = 0 | k < n | k += 1 ]
 |  | IF [ a{k} != b{k} ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  \_
 | RET [ TRUE ]
 \_

; the value of `key` in the [section] of the ini-style `text`, in `out`;
; FALSE when it is not there. Only the first is read
B1 ini_get: [ @CONST C1 text | @CONST C1 section | @CONST C1 key | @String out ]
 | B1 inside = FALSE
 | USIZE klen = (str_len)[ key ]
 | USIZE i = 0
 | WHILE [ text{i} != '\0' ]
 |  | USIZE e = i
 |  | WHILE [ text{e} != '\0' && text{e} != '\n' ]
 |  |  | e += 1
 |  |  \_
 |  | USIZE stop = e
 |  | IF [ stop > i && text{stop - 1} == '\r' ]
 |  |  | stop -= 1
 |  |  \_
 |  | IF [ text{i} == '[' ]
 |  |  | inside = FALSE
 |  |  | IF [ stop - i >= 2 && text{stop - 1} == ']' ]
 |  |  |  | inside = (desk_same)[ text + i + 1 | stop - i - 2 | section ]
 |  |  |  \_
 |  | ELIF [ inside && stop - i > klen && (desk_same)[ text + i | klen | key ] ]
 |  |  | USIZE p = i + klen
 |  |  | WHILE [ p < stop && text{p} == ' ' ]
 |  |  |  | p += 1
 |  |  |  \_
 |  |  | IF [ p < stop && text{p} == '=' ]
 |  |  |  | p += 1
 |  |  |  | WHILE [ p < stop && text{p} == ' ' ]
 |  |  |  |  | p += 1
 |  |  |  |  \_
 |  |  |  | (out.clear)[]
 |  |  |  | (out.append_n)[ text + p | stop - p ]
 |  |  |  | RET [ TRUE ]
 |  |  |  \_
 |  |  \_
 |  | i = e
 |  | IF [ text{e} == '\n' ]
 |  |  | i = e + 1
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

; `v` cut at each `sep` into new strings in `out`, the empty ones left out
LOCAL ABYSS desk_split: [ @CONST C1 v | C1 sep | @Vector<String> out ]
 | USIZE i = 0
 | WHILE [ v{i} != '\0' ]
 |  | USIZE j = i
 |  | WHILE [ v{j} != '\0' && v{j} != sep ]
 |  |  | j += 1
 |  |  \_
 |  | IF [ j > i ]
 |  |  | String s = (String.of)[ "" ]
 |  |  | (s.append_n)[ v + i | j - i ]
 |  |  | (out.push)[ s ]
 |  |  \_
 |  | IF [ v{j} == '\0' ]
 |  |  | BREAK
 |  |  \_
 |  | i = j + 1
 |  \_
 \_

LOCAL ABYSS desk_free: [ @Vector<String> v ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | ((v.at)[ i ].deinit)[]
 |  \_
 | (v.clear)[]
 \_

LOCAL B1 desk_has: [ @Vector<String> v | @CONST C1 s ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | IF [ ((v.at)[ i ].equals)[ s ] ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

; the ;-separated list of `key` in [section] of `text`, added to `out`
LOCAL ABYSS ini_list: [ @CONST C1 text | @CONST C1 section | @CONST C1 key | @Vector<String> out ]
 | String v = (String.of)[ "" ]
 | IF [ (ini_get)[ text | section | key | @v ] ]
 |  | (desk_split)[ (v.cstr)[] | ';' | out ]
 |  \_
 | (v.deinit)[]
 \_

; the desktop ids for `mime`, added to `out`: the defaults of every
; mimeapps.list in `confs` (their texts, the first the one that counts most),
; then their added associations, then those of the mimeinfo.cache texts in
; `caches`. What a list removes goes from the lists after it, and from the caches
LOCAL ABYSS desk_ids: [ @CONST C1 mime | @Vector<String> confs | @Vector<String> caches | @Vector<String> out ]
 | Vector<String> removed
 | Vector<String> got
 | FOR [ I32 pass = 0 | pass < 2 | pass += 1 ]
 |  | (desk_free)[ @removed ]
 |  | FOR [ USIZE k = 0 | k < (confs.size)[] | k += 1 ]
 |  |  | @CONST C1 text = ((confs.at)[ k ].cstr)[]
 |  |  | (ini_list)[ text | "Removed Associations" | mime | @removed ]
 |  |  | (ini_list)[ text | SELECT [ pass == 0 | "Default Applications" | "Added Associations" ] | mime | @got ]
 |  |  | FOR [ USIZE g = 0 | g < (got.size)[] | g += 1 ]
 |  |  |  | @CONST C1 id = ((got.at)[ g ].cstr)[]
 |  |  |  | IF [ !((desk_has)[ @removed | id ]) && !((desk_has)[ out | id ]) ]
 |  |  |  |  | (out.push)[ (String.of)[ id ] ]
 |  |  |  |  \_
 |  |  |  \_
 |  |  | (desk_free)[ @got ]
 |  |  \_
 |  \_
 | ; the caches come last, and nothing that was removed is in them
 | FOR [ USIZE k = 0 | k < (caches.size)[] | k += 1 ]
 |  | (ini_list)[ ((caches.at)[ k ].cstr)[] | "MIME Cache" | mime | @got ]
 |  | FOR [ USIZE g = 0 | g < (got.size)[] | g += 1 ]
 |  |  | @CONST C1 id = ((got.at)[ g ].cstr)[]
 |  |  | IF [ !((desk_has)[ @removed | id ]) && !((desk_has)[ out | id ]) ]
 |  |  |  | (out.push)[ (String.of)[ id ] ]
 |  |  |  \_
 |  |  \_
 |  | (desk_free)[ @got ]
 |  \_
 | (desk_free)[ @removed ]
 | (removed.deinit)[]
 | (got.deinit)[]
 \_

; an Exec line as a command: its escapes (\s \n \t \r \\) undone; %F and %U
; are %f, %f and %u are %1, %% is %, any other code is dropped
String desk_exec: [ @CONST C1 raw ]
 | String out = (String.of)[ "" ]
 | USIZE i = 0
 | WHILE [ raw{i} != '\0' ]
 |  | C1 c = raw{i}
 |  | IF [ c == '\\' && raw{i + 1} != '\0' ]
 |  |  | C1 d = raw{i + 1}
 |  |  | i += 2
 |  |  | IF [ d == 's' ]
 |  |  |  | (out.push)[ ' ' ]
 |  |  | ELIF [ d == 'n' ]
 |  |  |  | (out.push)[ '\n' ]
 |  |  | ELIF [ d == 't' ]
 |  |  |  | (out.push)[ '\t' ]
 |  |  | ELIF [ d == 'r' ]
 |  |  |  | (out.push)[ '\r' ]
 |  |  | ELSE
 |  |  |  | (out.push)[ d ]
 |  |  |  \_
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ c == '%' && raw{i + 1} != '\0' ]
 |  |  | C1 d = raw{i + 1}
 |  |  | i += 2
 |  |  | IF [ d == 'F' || d == 'U' ]
 |  |  |  | (out.append)[ "%f" ]
 |  |  | ELIF [ d == 'f' || d == 'u' ]
 |  |  |  | (out.append)[ "%1" ]
 |  |  | ELIF [ d == '%' ]
 |  |  |  | (out.push)[ '%' ]
 |  |  |  \_
 |  |  | CONTINUE
 |  |  \_
 |  | (out.push)[ c ]
 |  | i += 1
 |  \_
 | (out.trim)[]
 | RET [ out ]
 \_

; the .desktop file `id` in one of `dirs`, as a DeskApp in `out`; FALSE: none
; there, hidden, or with no Exec
LOCAL B1 desk_load: [ @CONST C1 id | @Vector<String> dirs | @DeskApp out ]
 | FOR [ USIZE k = 0 | k < (dirs.size)[] | k += 1 ]
 |  | String path = (join_path)[ ((dirs.at)[ k ].cstr)[] | id ]
 |  | String text = (String.of)[ "" ]
 |  | B1 read = (desk_read)[ (path.cstr)[] | @text ]
 |  | (path.deinit)[]
 |  | IF [ !read ]
 |  |  | (text.deinit)[]
 |  |  | CONTINUE
 |  |  \_
 |  | @CONST C1 t = (text.cstr)[]
 |  | String v = (String.of)[ "" ]
 |  | B1 ok = TRUE
 |  | IF [ (ini_get)[ t | "Desktop Entry" | "Hidden" | @v ] && (v.equals)[ "true" ] ]
 |  |  | ok = FALSE
 |  |  \_
 |  | String exec = (String.of)[ "" ]
 |  | IF [ !((ini_get)[ t | "Desktop Entry" | "Exec" | @exec ]) || (exec.size)[] == 0 ]
 |  |  | ok = FALSE
 |  |  \_
 |  | IF [ ok ]
 |  |  | out.id = (String.of)[ id ]
 |  |  | out.name = (String.of)[ "" ]
 |  |  | IF [ !((ini_get)[ t | "Desktop Entry" | "Name" | @(out.name) ]) || (out.name.size)[] == 0 ]
 |  |  |  | (out.name.deinit)[]
 |  |  |  | out.name = (String.of)[ id ]
 |  |  |  \_
 |  |  | out.tryexec = (String.of)[ "" ]
 |  |  | (ini_get)[ t | "Desktop Entry" | "TryExec" | @(out.tryexec) ]
 |  |  | out.command = (String.of)[ "" ]
 |  |  | IF [ (ini_get)[ t | "Desktop Entry" | "Terminal" | @v ] && (v.equals)[ "true" ] ]
 |  |  |  | (out.command.append)[ "term:" ]
 |  |  |  \_
 |  |  | String line = (desk_exec)[ (exec.cstr)[] ]
 |  |  | (out.command.append)[ (line.cstr)[] ]
 |  |  | (line.deinit)[]
 |  |  \_
 |  | (v.deinit)[]
 |  | (exec.deinit)[]
 |  | (text.deinit)[]
 |  | IF [ ok ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

ABYSS desk_apps_free: [ @Vector<DeskApp> v ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | @DeskApp d = (v.at)[ i ]
 |  | (d.id.deinit)[]
 |  | (d.name.deinit)[]
 |  | (d.command.deinit)[]
 |  | (d.tryexec.deinit)[]
 |  \_
 | (v.clear)[]
 \_

; the text of `<dir>/<file>` for each dir in `dirs` that has one, in `out`
LOCAL ABYSS desk_texts: [ @Vector<String> dirs | @CONST C1 file | @Vector<String> out ]
 | FOR [ USIZE k = 0 | k < (dirs.size)[] | k += 1 ]
 |  | String path = (join_path)[ ((dirs.at)[ k ].cstr)[] | file ]
 |  | String text = (String.of)[ "" ]
 |  | IF [ (desk_read)[ (path.cstr)[] | @text ] ]
 |  |  | (out.push)[ text ]
 |  | ELSE
 |  |  | (text.deinit)[]
 |  |  \_
 |  | (path.deinit)[]
 |  \_
 \_

; the programs for `mime`, in `out` (free with desk_apps_free), from the
; folders given as XDG's variables would be: the config home and dirs for
; mimeapps.list, the data home and dirs, whose applications/ hold the
; .desktop files, the cache and a mimeapps.list too. A text type also gets
; text/plain's. Which of them can run is not asked
ABYSS desk_apps: [ @CONST C1 mime | @CONST C1 conf_home | @CONST C1 conf_dirs | @CONST C1 data_home | @CONST C1 data_dirs | @Vector<DeskApp> out ]
 | ; where mimeapps.list may be: the config, then the data folders
 | Vector<String> cdirs
 | Vector<String> apps
 | IF [ conf_home{0} != '\0' ]
 |  | (cdirs.push)[ (String.of)[ conf_home ] ]
 |  \_
 | (desk_split)[ conf_dirs | ':' | @cdirs ]
 | Vector<String> ddirs
 | IF [ data_home{0} != '\0' ]
 |  | (ddirs.push)[ (String.of)[ data_home ] ]
 |  \_
 | (desk_split)[ data_dirs | ':' | @ddirs ]
 | FOR [ USIZE k = 0 | k < (ddirs.size)[] | k += 1 ]
 |  | (apps.push)[ (join_path)[ ((ddirs.at)[ k ].cstr)[] | "applications" ] ]
 |  | (cdirs.push)[ (join_path)[ ((ddirs.at)[ k ].cstr)[] | "applications" ] ]
 |  \_
 | Vector<String> confs
 | Vector<String> caches
 | (desk_texts)[ @cdirs | "mimeapps.list" | @confs ]
 | (desk_texts)[ @apps | "mimeinfo.cache" | @caches ]
 |
 | Vector<String> ids
 | (desk_ids)[ mime | @confs | @caches | @ids ]
 | IF [ (str_starts)[ mime | "text/" ] && !((str_eq)[ mime | "text/plain" ]) ]
 |  | (desk_ids)[ "text/plain" | @confs | @caches | @ids ]
 |  \_
 | FOR [ USIZE k = 0 | k < (ids.size)[] | k += 1 ]
 |  | DeskApp d
 |  | IF [ (desk_load)[ ((ids.at)[ k ].cstr)[] | @apps | @d ] ]
 |  |  | B1 dup = FALSE
 |  |  | FOR [ USIZE m = 0 | m < (out.size)[] | m += 1 ]
 |  |  |  | dup = dup || ((out.at)[ m ].command.equals)[ (d.command.cstr)[] ]
 |  |  |  \_
 |  |  | IF [ dup ]
 |  |  |  | (d.id.deinit)[]
 |  |  |  | (d.name.deinit)[]
 |  |  |  | (d.command.deinit)[]
 |  |  |  | (d.tryexec.deinit)[]
 |  |  | ELSE
 |  |  |  | (out.push)[ d ]
 |  |  |  \_
 |  |  \_
 |  \_
 | (desk_free)[ @cdirs ]
 | (desk_free)[ @apps ]
 | (desk_free)[ @ddirs ]
 | (desk_free)[ @confs ]
 | (desk_free)[ @caches ]
 | (desk_free)[ @ids ]
 | (cdirs.deinit)[]
 | (apps.deinit)[]
 | (ddirs.deinit)[]
 | (confs.deinit)[]
 | (caches.deinit)[]
 | (ids.deinit)[]
 \_

; a folder in `out` (cap bytes): `var` from the environment, else `home`/`rest`
LOCAL ABYSS desk_dir: [ @CONST C1 var | @CONST C1 rest | @C1 out | USIZE cap ]
 | @CONST C1 v = ((env)[ var ].unwrap_or)[ "" ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | IF [ v{0} != '\0' ]
 |  | (b.print)[ "%s" | v ]
 | ELSE
 |  | (b.print)[ "%s/%s" | ((env)[ "HOME" ].unwrap_or)[ "" ] | rest ]
 |  \_
 \_

; the same, with the folders the environment names, or XDG's defaults
ABYSS desk_apps_here: [ @CONST C1 mime | @Vector<DeskApp> out ]
 | C1 ch{1024}
 | C1 dh{1024}
 | (desk_dir)[ "XDG_CONFIG_HOME" | ".config" | ch | 1024 ]
 | (desk_dir)[ "XDG_DATA_HOME" | ".local/share" | dh | 1024 ]
 | @CONST C1 cd = ((env)[ "XDG_CONFIG_DIRS" ].unwrap_or)[ "" ]
 | @CONST C1 dd = ((env)[ "XDG_DATA_DIRS" ].unwrap_or)[ "" ]
 | (desk_apps)[ mime | ch AS @CONST C1 | SELECT [ cd{0} != '\0' | cd | "/etc/xdg" ] | dh AS @CONST C1 | SELECT [ dd{0} != '\0' | dd | "/usr/local/share:/usr/share" ] | out ]
 \_
