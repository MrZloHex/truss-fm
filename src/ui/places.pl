; places.pl -- the first column: places to go to, in blocks with a gap
; between: PLACES (home, the standard folders, the config's), DEVICES (the
; disks, by where they are mounted), TRASH (one row, with its item count),
; BOOKMARKS (those of $XDG_CONFIG_HOME/trufm/places, else ~/.config/trufm/places). The cursor steps over the
; headings and the gaps; Enter opens a place, ' and its key open it from any
; column. The place the program is in is amber

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/alloc/string.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>
USE <std/os/time.pl>

USE <modular.pl>
!USES <common.pl>
!USES <../core/fs.pl>
!USES <look.pl>
!USES <../core/config.pl>
!USES <../core/trash.pl>

CONST I32 PLACE_USE_W = 4       ; a disk's use against the right border: 100%
CONST I32 PLACE_KEY_W = 1       ; or a place's key
CONST I32 PLACE_COUNT_W = 5     ; or the trash's item count
CONST USIZE PLACE_LINE = 4096
CONST U64 MOUNTS_MS = 2000      ; how often the mounts are looked at

TYPE PlaceKind: ENUM
 | PK_PLACE
 | PK_HEAD
 | PK_GAP
 \_

TYPE Place: STRUCT
 | PlaceKind kind
 | String name
 | String path              ; where Enter goes; empty for a heading or a gap
 | String key               ; ' and this go here; may be empty
 | I32 used                 ; a disk's use in percent; -1: not a disk
 | I32 count                ; the trash row: its items; -1: not that row
 | B1 mark                  ; from the bookmarks file: D there takes it off
 \_

TYPE PlacesPane: STRUCT
 | ListState list
 | Vector<Place> rows
 | B1 read                  ; rows were read; FALSE: read them next frame
 | B1 jump                  ; ' was pressed: the next key names a place
 | U64 mounts               ; mounts_signature when the disks were read
 | U64 checked              ; now_ms they were last looked at
 | I64 trash_sec            ; the trash's files folder's own time when read (-1: none):
 | U32 trash_nsec           ;   an item put in or taken out changes it
 | String said              ; a word for the program to show: a bookmark
 |                          ;   taken off, or why not; empty: none
 \_

; --- rows -----------------------------------------------------------------------

ABYSS place_add: [ @Vector<Place> v | PlaceKind k | @CONST C1 name | @CONST C1 path | @CONST C1 key | I32 used ]
 | Place r
 | r.kind = k
 | r.name = (String.of)[ name ]
 | r.path = (String.of)[ path ]
 | r.key = (String.of)[ key ]
 | r.used = used
 | r.count = -1
 | (v.push)[ r ]
 \_

; every string of every row freed; the vector kept
ABYSS places_clear: [ @Vector<Place> v ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | @Place r = (v.at)[ i ]
 |  | (r.name.deinit)[]
 |  | (r.path.deinit)[]
 |  | (r.key.deinit)[]
 |  \_
 | (v.clear)[]
 \_

ABYSS dispose_places: [ @PlacesPane p ]
 | (places_clear)[ @(p.rows) ]
 | (p.rows.deinit)[]
 | (p.said.deinit)[]
 \_

; where the bookmarks are kept, in `out`
ABYSS bookmarks_file: [ @C1 out | USIZE cap ]
 | Option<@CONST C1> st = (env)[ "XDG_CONFIG_HOME" ]
 | BufferSink b = (BufferSink.over)[ out | cap ]
 | IF [ (st.is_some)[] && (st.unwrap)[]{0} == '/' ]
 |  | (b.print)[ "%s/trufm/places" | (st.unwrap)[] ]
 | ELSE
 |  | (b.print)[ "%s/.config/trufm/places" | ((env)[ "HOME" ].unwrap_or)[ "/" ] ]
 |  \_
 \_

; the time of the trash's files folder, as it is now; -1 when there is none
ABYSS trash_stamp: [ @I64 sec | @U32 nsec ]
 | C1 bin{PLACE_LINE}
 | (trash_home)[ bin | PLACE_LINE ]
 | BufferSink tb = (BufferSink.over)[ bin + (str_len)[ bin AS @CONST C1 ] | PLACE_LINE - (str_len)[ bin AS @CONST C1 ] ]
 | (tb.print)[ "/files" ]
 | ?sec = -1
 | ?nsec = 0
 | Result<FileInfo | IoError> fi = (fs_info)[ bin AS @CONST C1 ]
 | IF [ (fi.is_ok)[] ]
 |  | ?sec = (fi.unwrap)[].modified
 |  | ?nsec = (fi.unwrap)[].modified_ns
 |  \_
 \_

; the row of the place at `path`; -1: there is none. A place is listed once
LOCAL I32 place_known: [ @Vector<Place> v | @CONST C1 path ]
 | FOR [ USIZE i = 0 | i < (v.size)[] | i += 1 ]
 |  | IF [ ((v.at)[ i ].kind == PK_PLACE) && ((v.at)[ i ].path.equals)[ path ] ]
 |  |  | RET [ i AS I32 ]
 |  |  \_
 |  \_
 | RET [ -1 ]
 \_

; the folder `path` (~ for home) as a place, under `name` or, empty, its
; own; left out when it is not there. A place already there takes the key
; and the name given, so the config can rename or rekey a standard one
ABYSS place_dir: [ @Vector<Place> v | @CONST C1 name | @CONST C1 path | @CONST C1 key | @CONST C1 home | B1 mark ]
 | C1 full{PLACE_LINE}
 | BufferSink b = (BufferSink.over)[ full | PLACE_LINE ]
 | IF [ path{0} == '~' ]
 |  | (b.print)[ "%s%s" | home | path + 1 ]
 | ELSE
 |  | (b.print)[ "%s" | path ]
 |  \_
 | Result<String | IoError> r = (get_realpath)[ full AS @CONST C1 ]
 | IF [ (r.is_err)[] ]
 |  | RET []
 |  \_
 | String f = (r.unwrap)[]
 | POSTLUDE (f.deinit)[]
 | Result<FileInfo | IoError> fi = (fs_info)[ (f.cstr)[] ]
 | IF [ (fi.is_err)[] || (fi.unwrap)[].kind != FS_DIR ]
 |  | RET []
 |  \_
 | I32 was = (place_known)[ v | (f.cstr)[] ]
 | IF [ was >= 0 ]
 |  | @Place r = (v.at)[ was AS USIZE ]
 |  | IF [ key{0} != '\0' ]
 |  |  | (r.key.deinit)[]
 |  |  | r.key = (String.of)[ key ]
 |  |  \_
 |  | IF [ name{0} != '\0' ]
 |  |  | (r.name.deinit)[]
 |  |  | r.name = (String.of)[ name ]
 |  |  \_
 |  | r.mark = r.mark || mark
 |  | RET []
 |  \_
 | IF [ name{0} != '\0' ]
 |  | (place_add)[ v | PK_PLACE | name | (f.cstr)[] | key | -1 ]
 | ELSE
 |  | String own = (folder_name)[ (f.cstr)[] ]
 |  | (place_add)[ v | PK_PLACE | (own.cstr)[] | (f.cstr)[] | key | -1 ]
 |  | (own.deinit)[]
 |  \_
 | (v.at)[ (v.size)[] - 1 ].mark = mark
 \_

; a place as the config's `place =` and the bookmarks file write it: its
; key, or - for none, a space, its path, and if it is to be named so, " | "
; and the name
;   w ~/work | Work
;   - /mnt/archive
ABYSS place_line: [ @Vector<Place> v | @CONST C1 text | @CONST C1 home | B1 mark ]
 | IF [ text{0} == '\0' || text{0} == '#' || text{1} != ' ' ]
 |  | RET []
 |  \_
 | C1 key{2}
 | key{0} = SELECT [ text{0} == '-' | '\0' | text{0} ]
 | key{1} = '\0'
 | C1 path{PLACE_LINE}
 | (str_copy)[ path | PLACE_LINE | text + 2 ]
 | @CONST C1 name = ""
 | FOR [ USIZE i = 0 | path{i} != '\0' | i += 1 ]
 |  | IF [ path{i} == ' ' && path{i + 1} == '|' && path{i + 2} == ' ' ]
 |  |  | path{i} = '\0'
 |  |  | name = (path AS @CONST C1) + i + 3
 |  |  | BREAK
 |  |  \_
 |  \_
 | @CONST C1 at = path AS @CONST C1
 | WHILE [ ?at == ' ' ]
 |  | at += 1
 |  \_
 | (place_dir)[ v | name | at | key AS @CONST C1 | home | mark ]
 \_

; ~/.config/trufm/places, what b writes: a place a line, as place_line has it
ABYSS bookmarks_read: [ @Vector<Place> v | @CONST C1 home ]
 | C1 file{PLACE_LINE}
 | (bookmarks_file)[ file | PLACE_LINE ]
 | String text
 | POSTLUDE (text.deinit)[]
 | IF [ ((read_file)[ file AS @CONST C1 | @text ].is_err)[] ]
 |  | RET []
 |  \_
 | Split lines = (Split.over)[ (text.cstr)[] | '\n' ]
 | C1 line{PLACE_LINE}
 | WHILE [ (lines.next)[ line | PLACE_LINE ] ]
 |  | (place_line)[ v | line AS @CONST C1 | home | TRUE ]
 |  \_
 \_

; --- the standard places --------------------------------------------------------

; the user's folders, as xdg-user-dirs names them: XDG_<NAME>_DIR in
; ~/.config/user-dirs.dirs, or else what it would make
CONST @CONST C1 XDG_NAMES{} = [ "DESKTOP" | "DOCUMENTS" | "DOWNLOAD" | "MUSIC" | "PICTURES" | "VIDEOS" ]
CONST @CONST C1 XDG_DEFAULT{} = [ "~/Desktop" | "~/Documents" | "~/Downloads" | "~/Music" | "~/Pictures" | "~/Videos" ]
CONST @CONST C1 XDG_KEY{} = [ "e" | "o" | "d" | "m" | "p" | "v" ]
CONST I32 NXDG = COUNT [ XDG_NAMES ]

; the folder XDG_<name>_DIR is set to in `dirs`, in `out` with ~ for
; $HOME; FALSE: it is not set there
LOCAL B1 xdg_dir: [ @CONST C1 dirs | @CONST C1 name | @C1 out ]
 | C1 want{64}
 | BufferSink w = (BufferSink.over)[ want | 64 ]
 | (w.print)[ "XDG_%s_DIR=\"" | name ]
 | Split lines = (Split.over)[ dirs | '\n' ]
 | C1 line{PLACE_LINE}
 | WHILE [ (lines.next)[ line | PLACE_LINE ] ]
 |  | IF [ !((str_starts)[ line AS @CONST C1 | want AS @CONST C1 ]) ]
 |  |  | CONTINUE
 |  |  \_
 |  | @CONST C1 v = (line AS @CONST C1) + (str_len)[ want AS @CONST C1 ]
 |  | BufferSink b = (BufferSink.over)[ out | PLACE_LINE ]
 |  | IF [ (str_starts)[ v | "$HOME" ] ]
 |  |  | (b.print)[ "~" ]
 |  |  | v += 5
 |  |  \_
 |  | FOR [ USIZE i = 0 | v{i} != '\0' && v{i} != '"' | i += 1 ]
 |  |  | C1 one{2}
 |  |  | one{0} = v{i}
 |  |  | one{1} = '\0'
 |  |  | (b.print)[ "%s" | one AS @CONST C1 ]
 |  |  \_
 |  | RET [ TRUE ]
 |  \_
 | RET [ FALSE ]
 \_

; Desktop, Documents, Downloads, Music, Pictures, Videos that are there, and
; the root; one set to home itself, as xdg does with one not used, is not
ABYSS standard_read: [ @Vector<Place> v | @CONST C1 home ]
 | C1 file{PLACE_LINE}
 | BufferSink b = (BufferSink.over)[ file | PLACE_LINE ]
 | (b.print)[ "%s/.config/user-dirs.dirs" | home ]
 | String dirs
 | POSTLUDE (dirs.deinit)[]
 | IF [ ((read_file)[ file AS @CONST C1 | @dirs ].is_err)[] ]
 |  | dirs = (String.of)[ "" ]
 |  \_
 | FOR [ I32 i = 0 | i < NXDG | i += 1 ]
 |  | C1 path{PLACE_LINE}
 |  | IF [ !((xdg_dir)[ (dirs.cstr)[] | XDG_NAMES{i} | path ]) ]
 |  |  | (str_copy)[ path | PLACE_LINE | XDG_DEFAULT{i} ]
 |  |  \_
 |  | IF [ !((str_eq)[ path AS @CONST C1 | "~" ]) && !((str_eq)[ path AS @CONST C1 | "~/" ]) ]
 |  |  | (place_dir)[ v | "" | path AS @CONST C1 | XDG_KEY{i} | home | FALSE ]
 |  |  \_
 |  \_
 | (place_dir)[ v | "/ root" | "/" | "/" | home | FALSE ]
 \_

; a disk that udisks (udiskie, a desktop) mounted: under /run/media/<user>/
; or /media/, by its label
LOCAL B1 removable: [ @CONST C1 path ]
 | RET [ (str_starts)[ path | "/run/media/" ] || (str_starts)[ path | "/media/" ] ]
 \_

; the disks that are mounted, by where -- a removable one by its label,
; ⏏ before it; the device is in the top bar
ABYSS disks_read: [ @Vector<Place> v ]
 | Vector<Mount> ms
 | (read_mounts)[ @ms ]
 | POSTLUDE (mounts_free)[ @ms ]
 | FOR [ USIZE i = 0 | i < (ms.size)[] | i += 1 ]
 |  | @Mount m = (ms.at)[ i ]
 |  | @CONST C1 at = (m.path.cstr)[]
 |  | F32 used = ((get_phy_part_usage)[ at ].unwrap_or)[ 0.0 ]
 |  | IF [ (removable)[ at ] ]
 |  |  | String label = (get_dirname)[ at ]
 |  |  | C1 name{280}
 |  |  | BufferSink b = (BufferSink.over)[ name | 280 ]
 |  |  | (b.print)[ "⏏ %s" | (label.cstr)[] ]
 |  |  | (place_add)[ v | PK_PLACE | name AS @CONST C1 | at | "" | used AS I32 ]
 |  |  | (label.deinit)[]
 |  | ELSE
 |  |  | (place_add)[ v | PK_PLACE | at | at | "" | used AS I32 ]
 |  |  \_
 |  \_
 \_

; the home trash's files as one row, TRASH, with how many there are, after
; a gap; none if there is no such folder, or its path is a place already
ABYSS trash_row: [ @Vector<Place> v ]
 | C1 bin{PLACE_LINE}
 | (trash_home)[ bin | PLACE_LINE ]
 | BufferSink tb = (BufferSink.over)[ bin + (str_len)[ bin AS @CONST C1 ] | PLACE_LINE - (str_len)[ bin AS @CONST C1 ] ]
 | (tb.print)[ "/files" ]
 | Result<FileInfo | IoError> fi = (fs_info)[ bin AS @CONST C1 ]
 | IF [ (fi.is_err)[] || (fi.unwrap)[].kind != FS_DIR || (place_known)[ v | bin AS @CONST C1 ] >= 0 ]
 |  | RET []
 |  \_
 | I32 items = 0
 | Result<os:Dir | IoError> d = (os:Dir.open)[ bin AS @CONST C1 ]
 | IF [ (d.is_ok)[] ]
 |  | os:Dir dir = (d.unwrap)[]
 |  | os:DirEntry e
 |  | WHILE [ (dir.next)[ @e ] ]
 |  |  | items += 1
 |  |  \_
 |  | (dir.close)[]
 |  \_
 | (place_add)[ v | PK_GAP | "" | "" | "" | -1 ]
 | (place_add)[ v | PK_PLACE | "TRASH" | bin AS @CONST C1 | "t" | -1 ]
 | (v.at)[ (v.size)[] - 1 ].count = items
 \_

; BOOKMARKS and the bookmarks file's places after a gap; a bookmark that is
; a place already only marks that one, and with none left, no heading
ABYSS bookmark_rows: [ @Vector<Place> v | @CONST C1 home ]
 | USIZE was = (v.size)[]
 | (place_add)[ v | PK_GAP | "" | "" | "" | -1 ]
 | (place_add)[ v | PK_HEAD | "BOOKMARKS" | "" | "" | -1 ]
 | (bookmarks_read)[ v | home ]
 | IF [ (v.size)[] == was + 2 ]
 |  | FOR [ I32 i = 0 | i < 2 | i += 1 ]
 |  |  | Place r
 |  |  | (v.pop)[ @r ]
 |  |  | (r.name.deinit)[]
 |  |  | (r.path.deinit)[]
 |  |  | (r.key.deinit)[]
 |  |  \_
 |  \_
 \_

; PLACES: home, the standard ones, the config's; DEVICES: the disks; TRASH;
; BOOKMARKS. The config says which of these there are
ABYSS places_read: [ @PlacesPane p ]
 | (places_clear)[ @(p.rows) ]
 | @CONST C1 home = ((env)[ "HOME" ].unwrap_or)[ "/" ]
 | (place_add)[ @(p.rows) | PK_HEAD | "PLACES" | "" | "" | -1 ]
 | (place_dir)[ @(p.rows) | "~ home" | "~" | "h" | home | FALSE ]
 | IF [ CFG.std_places ]
 |  | (standard_read)[ @(p.rows) | home ]
 |  \_
 | FOR [ USIZE i = 0 | i < (CFG.places.size)[] | i += 1 ]
 |  | (place_line)[ @(p.rows) | ((CFG.places.at)[ i ].cstr)[] | home | FALSE ]
 |  \_
 | IF [ CFG.devices ]
 |  | (place_add)[ @(p.rows) | PK_GAP | "" | "" | "" | -1 ]
 |  | (place_add)[ @(p.rows) | PK_HEAD | "DEVICES" | "" | "" | -1 ]
 |  | (disks_read)[ @(p.rows) ]
 |  \_
 | IF [ CFG.std_places ]
 |  | (trash_row)[ @(p.rows) ]
 |  \_
 | (bookmark_rows)[ @(p.rows) | home ]
 | (trash_stamp)[ @(p.trash_sec) | @(p.trash_nsec) ]
 | p.mounts = (mounts_signature)[]
 | p.checked = (now_ms)[]
 | p.read = TRUE
 \_

CONST I32 BM_ADDED = 0
CONST I32 BM_THERE = 1          ; a place already: home, a standard one, a bookmark
CONST I32 BM_FAILED = 2         ; the file could not be written

; `cwd` among the bookmarks, with no key. The rows are read again on the
; next frame
I32 bookmark_add: [ @PlacesPane p | @CONST C1 cwd ]
 | IF [ (place_known)[ @(p.rows) | cwd ] >= 0 ]
 |  | RET [ BM_THERE ]
 |  \_
 | C1 file{PLACE_LINE}
 | (bookmarks_file)[ file | PLACE_LINE ]
 | ; the file's own folder, and what is missing above it
 | String up = (get_parent_path)[ file AS @CONST C1 ]
 | POSTLUDE (up.deinit)[]
 | (fs_make_dirs)[ (up.cstr)[] ]
 | String text
 | POSTLUDE (text.deinit)[]
 | IF [ ((read_file)[ file AS @CONST C1 | @text ].is_err)[] ]
 |  | text = (String.of)[ "" ]
 |  \_
 | IF [ (text.size)[] > 0 && (text.cstr)[]{(text.size)[] - 1} != '\n' ]
 |  | (text.append)[ "\n" ]
 |  \_
 | String short = (get_shorter_path)[ cwd ]
 | POSTLUDE (short.deinit)[]
 | (text.append)[ "- " ]
 | (text.append)[ (short.cstr)[] ]
 | (text.append)[ "\n" ]
 | p.read = FALSE
 | RET [ SELECT [ ((write_file)[ file AS @CONST C1 | (text.cstr)[] ].is_ok)[] | BM_ADDED | BM_FAILED ] ]
 \_

; the bookmark at `target` -- every line of the bookmarks file whose path is
; that folder -- taken off. How many lines went; -1: the file cannot be
; written. The rows are read again on the next frame
I32 bookmark_remove: [ @PlacesPane p | @CONST C1 target ]
 | @CONST C1 home = ((env)[ "HOME" ].unwrap_or)[ "/" ]
 | C1 file{PLACE_LINE}
 | (bookmarks_file)[ file | PLACE_LINE ]
 | String text
 | POSTLUDE (text.deinit)[]
 | IF [ ((read_file)[ file AS @CONST C1 | @text ].is_err)[] ]
 |  | RET [ 0 ]
 |  \_
 | String kept = (String.of)[ "" ]
 | POSTLUDE (kept.deinit)[]
 | I32 gone = 0
 | Split lines = (Split.over)[ (text.cstr)[] | '\n' ]
 | C1 line{PLACE_LINE}
 | WHILE [ (lines.next)[ line | PLACE_LINE ] ]
 |  | ; its path, as place_line reads it: after the key, before " | "
 |  | B1 drop = FALSE
 |  | IF [ line{0} != '\0' && line{0} != '#' && line{1} == ' ' ]
 |  |  | C1 path{PLACE_LINE}
 |  |  | (str_copy)[ path | PLACE_LINE | (line AS @CONST C1) + 2 ]
 |  |  | FOR [ USIZE i = 0 | path{i} != '\0' | i += 1 ]
 |  |  |  | IF [ path{i} == ' ' && path{i + 1} == '|' && path{i + 2} == ' ' ]
 |  |  |  |  | path{i} = '\0'
 |  |  |  |  | BREAK
 |  |  |  |  \_
 |  |  |  \_
 |  |  | @CONST C1 at = path AS @CONST C1
 |  |  | WHILE [ ?at == ' ' ]
 |  |  |  | at += 1
 |  |  |  \_
 |  |  | C1 full{PLACE_LINE}
 |  |  | BufferSink b = (BufferSink.over)[ full | PLACE_LINE ]
 |  |  | IF [ at{0} == '~' ]
 |  |  |  | (b.print)[ "%s%s" | home | at + 1 ]
 |  |  | ELSE
 |  |  |  | (b.print)[ "%s" | at ]
 |  |  |  \_
 |  |  | Result<String | IoError> r = (get_realpath)[ full AS @CONST C1 ]
 |  |  | IF [ (r.is_ok)[] ]
 |  |  |  | String f = (r.unwrap)[]
 |  |  |  | drop = (f.equals)[ target ]
 |  |  |  | (f.deinit)[]
 |  |  |  \_
 |  |  \_
 |  | IF [ drop ]
 |  |  | gone += 1
 |  | ELIF [ line{0} != '\0' ]
 |  |  | ; the empty piece after the last line, and blank ones, not kept
 |  |  | (kept.append)[ line AS @CONST C1 ]
 |  |  | (kept.append)[ "\n" ]
 |  |  \_
 |  \_
 | IF [ gone == 0 ]
 |  | RET [ 0 ]
 |  \_
 | p.read = FALSE
 | IF [ ((write_file)[ file AS @CONST C1 | (kept.cstr)[] ].is_err)[] ]
 |  | RET [ -1 ]
 |  \_
 | RET [ gone ]
 \_

; D or Delete on a place: a bookmark taken off; anything else is not the
; bookmarks file's to lose, and `said` says so
ABYSS place_forget: [ @PlacesPane p | @Place r ]
 | (p.said.deinit)[]
 | IF [ !(r.mark) ]
 |  | p.said = (String.of)[ "not a bookmark: standard places, place = lines and disks stay" ]
 |  | RET []
 |  \_
 | I32 gone = (bookmark_remove)[ p | (r.path.cstr)[] ]
 | C1 s{300}
 | BufferSink b = (BufferSink.over)[ s | 300 ]
 | IF [ gone > 0 ]
 |  | (b.print)[ "bookmark %s taken off · b puts it back" | (r.name.cstr)[] ]
 | ELSE
 |  | (b.print)[ "the bookmarks file cannot be written" ]
 |  \_
 | p.said = (String.of)[ s AS @CONST C1 ]
 \_

; --- where the program is -------------------------------------------------------

; is `cwd` `path` or in it? / holds everything
LOCAL B1 under: [ @CONST C1 cwd | @CONST C1 path ]
 | USIZE i = 0
 | WHILE [ path{i} != '\0' ]
 |  | IF [ cwd{i} != path{i} ]
 |  |  | RET [ FALSE ]
 |  |  \_
 |  | i += 1
 |  \_
 | RET [ cwd{i} == '\0' || cwd{i} == '/' || i == 1 ]
 \_

; the row of the place `cwd` is in: the longest path it is under; -1: none
I32 place_of: [ @PlacesPane p | @CONST C1 cwd ]
 | I32 best = -1
 | USIZE len = 0
 | FOR [ USIZE i = 0 | i < (p.rows.size)[] | i += 1 ]
 |  | @Place r = (p.rows.at)[ i ]
 |  | IF [ r.kind == PK_PLACE && (r.path.size)[] > len && (under)[ cwd | (r.path.cstr)[] ] ]
 |  |  | best = i AS I32
 |  |  | len = (r.path.size)[]
 |  |  \_
 |  \_
 | RET [ best ]
 \_

; --- the column -----------------------------------------------------------------

; a cursor that came onto a heading or a gap goes on the way it came, and
; back to where it `was` if there is no place that way
ABYSS place_skip: [ @PlacesPane p | I32 was ]
 | I32 n = (p.rows.size)[] AS I32
 | I32 step = SELECT [ p.list.cursor < was | -1 | 1 ]
 | WHILE [ p.list.cursor >= 0 && p.list.cursor < n && (p.rows.at)[ p.list.cursor AS USIZE ].kind != PK_PLACE ]
 |  | p.list.cursor += step
 |  \_
 | ; none that way -- gg onto the first heading: the other way, from there
 | IF [ p.list.cursor < 0 || p.list.cursor >= n ]
 |  | p.list.cursor = SELECT [ p.list.cursor < 0 | 0 | n - 1 ]
 |  | WHILE [ p.list.cursor >= 0 && p.list.cursor < n && (p.rows.at)[ p.list.cursor AS USIZE ].kind != PK_PLACE ]
 |  |  | p.list.cursor -= step
 |  |  \_
 |  \_
 | IF [ p.list.cursor < 0 || p.list.cursor >= n ]
 |  | p.list.cursor = was
 |  \_
 \_

; to the place `r`, in `go`; the main column takes the keys there
ABYSS place_go: [ @Ui ui | @String go | @Place r ]
 | (go.deinit)[]
 | ?go = (String.of)[ (r.path.cstr)[] ]
 | (ui.set_focus)[ (ui.id)[ "main" ] ]
 \_

; ' and a place's key go there, whichever column has the focus: this one
; is drawn first, so it takes the key before the others see it
ABYSS jump_keys: [ @Ui ui | @PlacesPane p | @String go ]
 | IF [ !(p.jump) ]
 |  | IF [ (ui.shortcut)[ "'" ] ]
 |  |  | p.jump = TRUE
 |  |  | (ui.redo)[]             ; the path bar, drawn before, shows it
 |  |  \_
 |  | RET []
 |  \_
 | U32 k = (ui.key)[]
 | IF [ k == 0 ]
 |  | RET []
 |  \_
 | p.jump = FALSE
 | (ui.consume)[]
 | (ui.redo)[]
 | FOR [ USIZE i = 0 | i < (p.rows.size)[] | i += 1 ]
 |  | @Place r = (p.rows.at)[ i ]
 |  | IF [ (r.key.size)[] > 0 && ((r.key.cstr)[]{0} AS U32) == k ]
 |  |  | (place_go)[ ui | go | r ]
 |  |  | RET []
 |  |  \_
 |  \_
 \_

; `go`: the place opened, if one was
ABYSS places_pane: [ @Ui ui | @PlacesPane p | @CONST C1 cwd | @String go ]
 | ; a disk mounted or taken away since: read again. Looked at now and then:
 | ; the program wakes at least once a second
 | IF [ p.read && (now_ms)[] - p.checked > MOUNTS_MS ]
 |  | p.checked = (now_ms)[]
 |  | IF [ CFG.devices && (mounts_signature)[] != p.mounts ]
 |  |  | p.read = FALSE
 |  |  \_
 |  | ; the trash filled or emptied from outside
 |  | IF [ CFG.std_places ]
 |  |  | I64 sec
 |  |  | U32 nsec
 |  |  | (trash_stamp)[ @sec | @nsec ]
 |  |  | IF [ sec != p.trash_sec || nsec != p.trash_nsec ]
 |  |  |  | p.read = FALSE
 |  |  |  \_
 |  |  \_
 |  \_
 | IF [ !(p.read) ]
 |  | (places_read)[ p ]
 |  \_
 | (jump_keys)[ ui | p | go ]
 |
 | U32 id = (ui.id)[ "places" ]
 | ; a name takes what its key or its disk's use leaves, as wide as the
 | ; column was the last frame; the key or the use at the right border
 | I32 inner = (ui.rect_of)[ id ].w - 1 - BAR_W
 | I32 n = (p.rows.size)[] AS I32
 | I32 here = (place_of)[ p | cwd ]
 | I32 was = p.list.cursor
 | IF [ (ui.focused)[ id ] ]
 |  | (move_keys)[ ui | @(p.list) ]
 |  \_
 |
 | ((ui.box)[ "" | (pct)[ CFG.places_width ] | GROW ].pads)[ ui.theme.box_pad | 0 | 0 | 0 ]
 | ; on a bookmark, with the keys: how to take it off, in the bottom edge
 | IF [ (ui.focused)[ id ] && p.list.cursor >= 0 && p.list.cursor < n && (p.rows.at)[ p.list.cursor AS USIZE ].mark ]
 |  | (ui.subtitle)[]
 |  | (ui.put)[ (fg)[ DIM ] | "[D] forget bookmark" ]
 |  \_
 | (ui.list)[ @(p.list) | id | n | GROW | GROW ]
 | ; a press on a place goes there, as a sidebar's does -- not one on a
 | ; heading, which the cursor steps off
 | I32 hit = (press_row)[ ui | id | @(p.list) | BTN_LEFT | 1 ]
 | IF [ hit >= 0 && (p.rows.at)[ hit AS USIZE ].kind == PK_PLACE ]
 |  | (place_go)[ ui | go | (p.rows.at)[ hit AS USIZE ] ]
 |  \_
 | (place_skip)[ p | was ]
 | IF [ (ui.focused)[ id ] && ((ui.take)[ KEY_ENTER ] || (ui.take)[ 'l' AS U32 ] || (ui.take)[ KEY_RIGHT ]) ]
 |  | IF [ p.list.cursor >= 0 && p.list.cursor < n ]
 |  |  | (place_go)[ ui | go | (p.rows.at)[ p.list.cursor AS USIZE ] ]
 |  |  \_
 |  \_
 | ; D or Delete: the bookmark under the cursor taken off -- the column has
 | ; the keys, so the main column's trash never sees them
 | IF [ (ui.focused)[ id ] && ((ui.take)[ 'D' AS U32 ] || (ui.take)[ KEY_DELETE ]) ]
 |  | IF [ p.list.cursor >= 0 && p.list.cursor < n ]
 |  |  | (place_forget)[ p | (p.rows.at)[ p.list.cursor AS USIZE ] ]
 |  |  | (ui.redo)[]
 |  |  \_
 |  \_
 |
 | FOR [ I32 i = 0 | i < n | i += 1 ]
 |  | @Place r = (p.rows.at)[ i AS USIZE ]
 |  | IF [ r.kind == PK_PLACE ]
 |  |  | (ui.list_row)[ @(p.list) | i | id ]
 |  |  | I32 side = SELECT [ r.count >= 0 | PLACE_COUNT_W | SELECT [ r.used >= 0 | PLACE_USE_W | PLACE_KEY_W ] ]
 |  |  | I32 name_w = SELECT [ inner - side < NAME_MIN | NAME_MIN | inner - side ]
 |  |  | (ui.put_cell)[ (fg)[ SELECT [ i == here | AMBER | SELECT [ r.count >= 0 | DIM | TEXT ] ] ] | (r.name.cstr)[] | name_w | TRUE ]
 |  |  | (ui.put)[ (fg)[ DIM ] | " " ]
 |  |  | IF [ r.count >= 0 ]
 |  |  |  | C1 num{12}
 |  |  |  | BufferSink nb = (BufferSink.over)[ num | 12 ]
 |  |  |  | (nb.print)[ "%d" | r.count ]
 |  |  |  | (ui.put_cell)[ (fg)[ DIM ] | num AS @CONST C1 | PLACE_COUNT_W | FALSE ]
 |  |  | ELIF [ r.used >= 0 ]
 |  |  |  | C1 use{8}
 |  |  |  | BufferSink b = (BufferSink.over)[ use | 8 ]
 |  |  |  | (b.print)[ "%d%%" | r.used ]
 |  |  |  | (ui.put_cell)[ (fg)[ SELECT [ r.used >= DISK_FULL | ORANGE | DIM ] ] | use AS @CONST C1 | PLACE_USE_W | FALSE ]
 |  |  | ELSE
 |  |  |  | (ui.put_cell)[ (fg)[ DIM ] | (r.key.cstr)[] | PLACE_KEY_W | FALSE ]
 |  |  |  \_
 |  | ELSE
 |  |  | (ui.text)[ GROW | 1 ]
 |  |  | (ui.put)[ (fg)[ DIM ] | (r.name.cstr)[] ]
 |  |  \_
 |  \_
 | (ui.end)[]
 | (ui.close)[]
 \_
