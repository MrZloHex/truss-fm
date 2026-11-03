; extract.pl -- an archive unpacked, as a task: always into a folder of
; its own, named for it -- foo.tar.gz into foo/, foo (2)/ if that is taken
; -- so one with no folder at its top cannot spill over the one it is in;
; and then, if all it held was one folder or one file, that one is moved up
; in its place, so proj.zip gives proj/, not proj/proj/.
;
; The work is a program's, run beside the frames: an extract.<ext> rule of
; the config's, or else EXTRACT_SCRIPT, bsdtar for most. What it prints, a
; line an entry, is counted, and the last shown

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

!USES <fs.pl>
!USES <config.pl>
!USES <rules.pl>
!USES <job.pl>
!USES <tasks.pl>

; what is kept of an archive's output at once: it is read a line at a time
CONST USIZE EXTRACT_LIMIT = 0xFFFFFFFF

; the archives pluf knows without a rule, by their last extension
CONST @CONST C1 ARCHIVE_EXTS = ",tar,tgz,tbz,tbz2,txz,tzst,tlz,gz,bz2,xz,zst,lzma,lz4,lz,z,zip,jar,war,apk,xpi,epub,7z,rar,iso,cpio,cab,deb,a,ar,"

; the default, run in the new folder with the archive as "$1": bsdtar for
; what holds files; a compressed file alone decompressed under its own
; name less the extension; rar by unrar where there is one
CONST @CONST C1 EXTRACT_SCRIPT = "case \"$1\" in\n  *.tar.*|*.tgz|*.tbz|*.tbz2|*.txz|*.tzst|*.tlz) bsdtar -xvf \"$1\" ;;\n  *.gz|*.bz2|*.xz|*.zst|*.lzma|*.lz4|*.Z)\n    n=$(basename \"$1\"); n=${n%.*}\n    case \"$1\" in\n      *.gz|*.Z) gzip -dc \"$1\" ;; *.bz2) bzip2 -dc \"$1\" ;;\n      *.xz|*.lzma) xz -dc \"$1\" ;; *.zst) zstd -dc \"$1\" ;; *.lz4) lz4 -dc \"$1\" ;;\n    esac > \"$n\" && echo \"x $n\" ;;\n  *.rar) if command -v unrar >/dev/null; then unrar x -o- \"$1\"; else bsdtar -xvf \"$1\"; fi ;;\n  *) bsdtar -xvf \"$1\" ;;\nesac"

; does `s` hold `sub` anywhere?
LOCAL B1 has_text: [ @CONST C1 s | @CONST C1 sub ]
 | FOR [ USIZE i = 0 | s{i} != '\0' | i += 1 ]
 |  | IF [ (str_starts)[ s + i | sub ] ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

; is the file at `path` one pluf can unpack? An extract. rule fits it, or
; its extension is one ARCHIVE_EXTS has
B1 is_archive: [ @CONST C1 path ]
 | IF [ (rule_for)[ @(CFG.extractors) | path ] != NULL ]
 |  | RET [ TRUE ]
 |  \_
 | String name = (get_dirname)[ path ]
 | C1 want{64}
 | (ext_key)[ (name.cstr)[] | want ]
 | (name.deinit)[]
 | RET [ want{0} != '\0' && (has_text)[ ARCHIVE_EXTS | want AS @CONST C1 ] ]
 \_

; the name an archive unpacks under: foo for foo.tar.gz, foo.tgz, foo.zip;
; one that would be empty, as for .zip, keeps its own
String archive_base: [ @CONST C1 name ]
 | String s = (String.of)[ name ]
 | USIZE n = (s.size)[]
 | USIZE dot = 0
 | FOR [ USIZE i = 1 | i < n | i += 1 ]
 |  | IF [ name{i} == '.' ]
 |  |  | dot = i
 |  |  \_
 |  \_
 | IF [ dot == 0 ]
 |  | RET [ s ]
 |  \_
 | ; foo.tar.gz: the .tar goes too
 | USIZE cut = dot
 | IF [ dot >= 5 && (str_starts)[ name + dot - 4 | ".tar" ] ]
 |  | cut = dot - 4
 |  \_
 | IF [ cut > 0 ]
 |  | (s.truncate)[ cut ]
 |  \_
 | RET [ s ]
 \_

; the archive at `archive` unpacked into a new folder in `into`, as a task
Task task_extract: [ @CONST C1 archive | @CONST C1 into ]
 | Task t = (task_new)[ TK_EXTRACT ]
 | String name = (get_dirname)[ archive ]
 | POSTLUDE (name.deinit)[]
 | String base = (archive_base)[ (name.cstr)[] ]
 | POSTLUDE (base.deinit)[]
 | String dest = (free_name)[ into | (base.cstr)[] ]
 | (t.dest.deinit)[]
 | t.dest = dest
 | (t.into.deinit)[]
 | t.into = (String.of)[ into ]
 | (t.target.deinit)[]
 | t.target = (String.of)[ archive ]
 |
 | C1 title{512}
 | BufferSink b = (BufferSink.over)[ title | 512 ]
 | String d = (get_dirname)[ (t.dest.cstr)[] ]
 | (b.print)[ "extract %s → %s/" | (name.cstr)[] | (d.cstr)[] ]
 | (d.deinit)[]
 | (t.title.deinit)[]
 | t.title = (String.of)[ title AS @CONST C1 ]
 |
 | Result<B1 | IoError> m = (fs_make_dir)[ (t.dest.cstr)[] ]
 | IF [ (m.is_err)[] ]
 |  | (task_fail_io)[ @t | (t.dest.cstr)[] | (m.error)[] ]
 |  | RET [ t ]
 |  \_
 | ; a rule's command, or the default
 | @Opener o = (rule_for)[ @(CFG.extractors) | archive ]
 | String script = (String.of)[ EXTRACT_SCRIPT ]
 | IF [ o != NULL ]
 |  | (script.deinit)[]
 |  | script = (shell_line)[ (o.cmd.cstr)[] ]
 |  \_
 | IF [ !((job_start_in)[ @(t.job) | (script.cstr)[] | (t.dest.cstr)[] | archive | EXTRACT_LIMIT ]) ]
 |  | (task_fail)[ @t | archive | "sh cannot be started" ]
 |  \_
 | (script.deinit)[]
 | t.extracting = TRUE
 | RET [ t ]
 \_

; what the program printed since: a line an entry, counted, the last one's
; name shown; only an unfinished line kept
LOCAL ABYSS extract_lines: [ @Task t ]
 | @CONST C1 s = (t.job.out.cstr)[]
 | USIZE n = (t.job.out.size)[]
 | USIZE start = 0
 | USIZE last = 0
 | USIZE last_end = 0
 | FOR [ USIZE i = 0 | i < n | i += 1 ]
 |  | IF [ s{i} == '\n' ]
 |  |  | IF [ i > start ]
 |  |  |  | t.done += 1
 |  |  |  | last = start
 |  |  |  | last_end = i
 |  |  |  \_
 |  |  | start = i + 1
 |  |  \_
 |  \_
 | IF [ last_end > last ]
 |  | ; bsdtar's "x path": the path's last part
 |  | C1 line{512}
 |  | USIZE k = 0
 |  | USIZE from = SELECT [ last_end - last > 2 && s{last} == 'x' && s{last + 1} == ' ' | last + 2 | last ]
 |  | FOR [ USIZE i = from | i < last_end && k + 1 < 512 | i += 1 ]
 |  |  | line{k} = s{i}
 |  |  | k += 1
 |  |  \_
 |  | line{k} = '\0'
 |  | (t.now.deinit)[]
 |  | t.now = (String.of)[ line AS @CONST C1 ]
 |  \_
 | IF [ start > 0 ]
 |  | String rest = (String.of)[ s + start ]
 |  | (t.job.out.deinit)[]
 |  | t.job.out = rest
 |  \_
 \_

; done well: if the new folder holds one thing only, that one in its place
LOCAL ABYSS extract_flatten: [ @Task t ]
 | Result<os:Dir | IoError> d = (os:Dir.open)[ (t.dest.cstr)[] ]
 | IF [ (d.is_err)[] ]
 |  | RET []
 |  \_
 | os:Dir dir = (d.unwrap)[]
 | I32 count = 0
 | C1 only{256}
 | DirEntry e
 | WHILE [ (dir.next)[ @e ] && count < 2 ]
 |  | (str_copy)[ only | 256 | e.name AS @CONST C1 ]
 |  | count += 1
 |  \_
 | (dir.close)[]
 | IF [ count == 0 ]
 |  | (fs_remove_dir)[ (t.dest.cstr)[] ]
 |  | (task_fail)[ t | (t.target.cstr)[] | "nothing came out of it" ]
 |  | RET []
 |  \_
 | IF [ count != 1 ]
 |  | RET []
 |  \_
 | ; the folder aside first, so its own name is free for what it holds
 | String up = (get_dirname)[ (t.dest.cstr)[] ]
 | (up.append)[ ".pluf-part" ]
 | String aside = (free_name)[ (t.into.cstr)[] | (up.cstr)[] ]
 | (up.deinit)[]
 | POSTLUDE (aside.deinit)[]
 | IF [ ((fs_rename)[ (t.dest.cstr)[] | (aside.cstr)[] ].is_err)[] ]
 |  | RET []
 |  \_
 | String inner = (join_path)[ (aside.cstr)[] | only AS @CONST C1 ]
 | POSTLUDE (inner.deinit)[]
 | String final = (free_name)[ (t.into.cstr)[] | only AS @CONST C1 ]
 | IF [ ((fs_rename)[ (inner.cstr)[] | (final.cstr)[] ].is_ok)[] ]
 |  | (fs_remove_dir)[ (aside.cstr)[] ]
 |  | (t.dest.deinit)[]
 |  | t.dest = final
 | ELSE
 |  | ; as it was, then
 |  | (fs_rename)[ (aside.cstr)[] | (t.dest.cstr)[] ]
 |  | (final.deinit)[]
 |  \_
 \_

; a frame's share of an extraction. TRUE: it has ended
B1 extract_step: [ @Task t ]
 | B1 over = (job_pump)[ @(t.job) ]
 | (extract_lines)[ t ]
 | IF [ !over ]
 |  | RET [ FALSE ]
 |  \_
 | t.extracting = FALSE
 | IF [ !(t.job.ok) ]
 |  | C1 why{300}
 |  | BufferSink b = (BufferSink.over)[ why | 300 ]
 |  | (b.print)[ "%s" | SELECT [ (t.now.size)[] > 0 | (t.now.cstr)[] | "it could not be unpacked" ] ]
 |  | (task_fail)[ t | (t.target.cstr)[] | why AS @CONST C1 ]
 |  | ; nothing came out: the folder made for it goes too -- what did is kept
 |  | (fs_remove_dir)[ (t.dest.cstr)[] ]
 |  | RET [ TRUE ]
 |  \_
 | (extract_flatten)[ t ]
 | RET [ TRUE ]
 \_
