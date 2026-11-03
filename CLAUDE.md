# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`pluf` is a file manager and picker written in **PLUM**, the user's own language. The compiler `plc`
and its reference `LANGUAGE.md` are at `~/mipt/04/CC/plum`. The UI is built on **modular**, the
user's immediate-mode UI library at `../../PLUM/modular`, which has its own `CLAUDE.md` listing PLUM
pitfalls. One binary runs in a terminal (TUI) or, with `--gui`, in an X11 window.

The visual spec is `TUI · file manager + picker@2x.png` at the repo root. `src/ui/look.pl` copies
its element-to-colour table, so colours should come from `look.pl`'s `C_*` and palette globals,
not from new literals in the panes.

## Commands

```sh
make                 # build ./pluf (also rebuilds modular's libmodular.a through its own Makefile when needed)
make run ARGS=~/dir  # TUI, starting in ~/dir (default ".")
make gui ARGS=~/dir  # the same in an X11 window
make run CONF=x.conf # run/gui read ./pluf.conf by default, never ~/.config/pluf/config
make test            # build and run every test/*_test.pl (there is no test/ directory yet)
make V=1             # show the full plc/cc command lines
make clean
make install PREFIX=~/.local
```

`PLC` and `MODULAR` can be overridden on the make command line. Every `src/**/*.pl` except dotfiles is
compiled with `plc -c -MD` into a matching `obj/**/*.o`, and the `.d` files track `!USES` includes.
A test is a standalone program, `test/<name>_test.pl`, that has its own `main`. It is linked with
every object except `obj/main.o`. To run a single test: `make obj/test/<name>_test && obj/test/<name>_test`.
After moving or renaming a source file, run `make clean` first, so stale objects don't get linked.

`obj/` and the `pluf` binary are committed to git, so builds show up as modified files.

## Layout

The layers depend only downward: `core` ← `ui` ← `app` ← `screen` ← `main.pl`. Keep it that
way. `core/` must not include modular or anything above it.

```
src/main.pl            entry: start folder from argv, config_load, look_apply, App.make, app_run
src/core/              no UI, no modular
  fs.pl                paths (join_path, is_under, ~), realpath, mounts, disk usage
  tasks.pl             copy/move/delete engine: Task = stack of Steps, run in slices
  config.pl            CFG and its parser; colours as plain 0xFFrrggbb in CFG.colors
src/ui/                the columns, their state and drawing
  look.pl              palette + C_* element colours (runtime globals), look_apply, theme
  common.pl            FileRecord, read_folder, row pieces, hjkl/→/Enter → go
  places.pl root.pl main.pl preview.pl     one pane each (main.pl is the main column)
src/app/               App and what operations do to it
  app.pl               AppData/AppOps/App: tabs, app_enter, refresh, vanished folder, hidden
  files.pl             file_yank/paste/ask_delete/delete_now/ask_rename/ask_mkdir/prompt_done
  open.pl              openers (opener_for, open_with) and open_now/open_ask/open_typed
src/screen/            the whole screen, built every frame
  frame.pl             frame: tick (task slices), layout, then the key handlers in order
  bars.pl              top bar (tabs, disk), path bar, hotkey line; `cells` for widths
  taskbox.pl           TASKS box and the prompt line
  keys.pl              keys_first (before drawing), keys_prompt, keys_files, keys_move
```

## How it works

- **One frame** (`screen/frame.pl`). `tick` gives tasks about 12 ms. `keys_first` catches a
  vanished folder and answers the delete prompt before anything draws, so nothing can move under
  it. Then the bars and the four panes draw, then the TASKS box. After that, `keys_prompt` (a
  focused `ui.input` takes the keys and Esc gives up), `keys_files`, and finally `keys_move`, which
  makes at most one folder change per frame (tab, `.`, `~`, `b`, `t`/`x`, or `go`) and calls
  `ui.redo()`.
- **Navigation goes through `go`.** Panes never change the cwd themselves. A focused pane writes
  the target into `String go`, and `keys_move` calls `a.go_to`. `app_enter` is the only place the
  folder changes, and it also writes the folder into the open tab. Places draws first, so a `'`
  jump takes its second key before the main column reads it. In the root pane, l/→/Enter opens a
  folder and moves the focus to `"main"`.
- **Panes** each have a `*Pane` struct, a `dispose_*`, an `update_*` that re-reads only when
  their cached `cwd` differs or `stale` is set, and a `*_pane` drawing function. A pane asks for
  work through flags the screen layer acts on (`MainPane.want_open`,
  `PreviewPane.want_open`/`want_with`).
- **Tabs.** `a.tabs` is a `Vector<Tab>` (cwd, label, saved cursor). Switching sets
  `MainPane.restore` (row plus one; 0 means none).
- **Selection.** `V` sets `MainPane.visual` and `anchor`, and also keeps the anchor by file name
  (`anchor_name`). `anchor_fix` puts it back on that file after every re-read or re-sort, or ends
  visual mode if the file is gone. Never let a selection stay on a row number, because the rows
  move during a task. `main_selection` returns the chosen rows, or the cursor's file, and ends
  visual mode.
- **Tasks** (`core/tasks.pl`). `SK_WEIGH` steps size the work a folder at a time on top of the
  stack, so there's never a tree walk in one frame. A move is a single rename, and only falls back
  to copy + `SK_DROP` (which deletes the source only if nothing failed) on `EXDEV`. `SK_SEAL`
  restores a copied folder's mode and mtime after its children, and `copy_end` does the same for
  files. Nothing is overwritten: taken names become `name (2).ext`, and files are opened `O_EXCL`.
  While a task runs, `app_refresh(a, FALSE)` re-reads the main column every `REFRESH_MS`, and only
  if the folder's own mtime changed. When it ends, `app_refresh(a, TRUE)` re-reads every column.
- **Opening** (`app/open.pl`). `open.<exts> = [term:] cmd` rules live in `CFG.openers`. Files are
  passed as `"$@"` to `sh -c` (`%f` marks where they go) and are never put into the command
  text. `term:` runs between `ui.pause(TRUE)` and `ui.pause(FALSE)`, the API added to modular for
  this. Under `--gui` it runs in `$TERMINAL -e`. Other programs run detached with stdio on
  `/dev/null`. `program_there` turns a missing program into a note.
- **Places** (`ui/places.pl`): home, the XDG folders (`~/.config/user-dirs.dirs`) and `/`, the
  config's `place =` lines, the bookmarks file, then devices. Mounts under `/run/media` and
  `/media` show as `⏏ <label>`, and the list re-reads when a hash of `/proc/self/mountinfo`
  changes (checked every 2 s; modular builds a frame at least once a second). `place_dir` lists a
  path once, and a later line for the same path changes that row's key and name.
- **Config** (`core/config.pl`). `config_load`, then `look_apply` in `main`. The format is
  `key = value`, and unknown lines are reported on stderr. Add a new key in `config_set` and in
  `pluf.conf.example`. Colours go to `CFG.colors` by `COLOR_NAMES`, and `look_apply` copies the
  set ones into the palette and recomputes the `C_*` colours, so don't turn those back into
  `CONST`s.
- **Startup.** The start folder is the first argument that isn't an option and isn't the value of
  one of modular's `VALUED` options. A bad path prints `pluf: <path>: <reason>` and exits with 1.
- **Includes.** `USE <...>` pulls in std/modular modules. `!USES <...>` textually includes project
  files, once per file, with paths relative to the including file.
- **Memory** is managed by hand. Every `String`/`Vector` has a matching `deinit` in a
  `dispose_*`, `App.dispose` or `config_free`, and `POSTLUDE` frees locals. A field that is
  replaced must have its old value `deinit`ed first (see `app_enter`).

## PLUM traps hit here

- `SELECT` evaluates both arms, so it must never pick between two calls that do something (see
  `file_prompt_done`).
- A bare `|` inside call args separates arguments, so parenthesize OR-ed flags.
- std's `os` module already has `path_join`, which is why ours is `join_path`.
- A local named `on` hides modular's `on()` style function.
- plc crashes (internal compiler error) on a struct array sized by a `COUNT [ ... ]` constant.
  Use a literal plus a `STATIC_ASSERT` (see `NCOLORS` in `core/config.pl`).

## Conventions

- Comments are short plain-English phrases that describe the code ("the folder it was read for",
  "-1: it cannot be read") and sit above or beside it. Keep this voice when adding code.
- Width constants are kept per pane (`*_W_PERC`, `ICON_W`, `SIDE_W`, ...) at the top of each file.
