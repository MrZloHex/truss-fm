████████╗██████╗ ██╗   ██╗███████╗███████╗
╚══██╔══╝██╔══██╗██║   ██║██╔════╝██╔════╝
   ██║   ██████╔╝██║   ██║███████╗███████╗
   ██║   ██╔══██╗██║   ██║╚════██║╚════██║
   ██║   ██║  ██║╚██████╔╝███████║███████║
   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝


  ░▒▓█ trufm █▓▒░
  A file manager for the terminal and X11, written in Plum.

  ───────────────────────────────────────────────────────────────
  ▓ OVERVIEW
  trufm is a file manager and picker in the TRUSS application suite.
  It is written in Plum and uses Modular

  ▪ Run inside a terminal (TUI) or in a separate X11 window
  ▪ Browse files through places, parent, file list, and preview columns
  ▪ Work with multiple tabs, bookmarks, and mounted devices
  ▪ Open files with configurable external programs
  ▪ Manage files without leaving the keyboard

  ───────────────────────────────────────────────────────────────
  ▓ ARCHITECTURE
  ▪ LANGUAGE:    Plum (.pl)
  ▪ COMPILER:    plc (Plum compiler)
  ▪ UI:          Modular; terminal UI and X11 window mode
  ▪ BUILD:       GNU Make; cc for final linking
  ▪ LIBRARY:     libmodular.a, built from the Modular source tree
  ▪ LINKING:     math, X11, Xft, Xrender, pthread
  ▪ CONFIG:      key = value text file
  ▪ STATE:       tabs, active tab, sort mode, hidden-file setting

  ───────────────────────────────────────────────────────────────
  ▓ FEATURES
  ▪ Vim-like movement, mouse navigation, and built-in key reference
  ▪ Search/filter, sorting by name/size/date, hidden-file toggle
  ▪ Up to nine tabs, places, bookmarks, and device navigation
  ▪ Copy, cut, paste, rename, new file/folder, and symbolic-link paste
  ▪ Copy names and paths to the clipboard; run programs with arguments
  ▪ Open with the desktop's registered applications for a file's type
  ▪ Freedesktop Trash with restore; separate permanent deletion
  ▪ Recursive permission and owner changes
  ▪ Archive extraction with progress reporting
  ▪ Background file tasks: pause, cancel, retry failed operations
  ▪ Git file-status marks, staging/unstaging, and diff preview
  ▪ Text and image preview; built-in syntax highlighting in the palette; configurable preview commands
  ▪ Per-extension or MIME-based file associations
  ▪ Shell command execution in the current directory
  ▪ Saved session state across launches

  ───────────────────────────────────────────────────────────────
  ▓ REQUIREMENTS
  ▪ Linux / Unix-like development environment
  ▪ Plum compiler (plc), with its standard library
  ▪ Modular source tree, including build support for libmodular.a
  ▪ GNU Make, a C compiler/linker, and development libraries for
    X11, Xft, Xrender, pthread, and libm
  ▪ A terminal supporting the TUI; X server or Xwayland for GUI mode

  Optional runtime tools depend on configuration. Examples include
  git, xdg-open, bat, ImageMagick (magick), poppler (pdftoppm),
  ffmpeg, bsdtar, mpv, imv, zathura, and exiftool.
  Not all of these are required for the basic file manager.

  ───────────────────────────────────────────────────────────────
  ▓ BUILD & RUN
  Clone:
      git clone https://github.com/MrZloHex/truss-fm.git
      cd truss-fm

  Build (set paths to your local Plum and Modular installations):
      make PLC=/path/to/plc MODULAR=/path/to/modular

  The Makefile has developer-local defaults for PLC and MODULAR.
  Override them if they do not match your system.

  Run in a terminal:
      make run
      make run ARGS=~/Projects
      ./trufm ~/Projects

  Run in an X11 window:
      make gui
      make gui ARGS=~/Projects
      ./trufm --gui ~/Projects

  Build options:
      make V=1              show full compiler and linker commands
      make test             build and run the Plum test programs
      make clean            remove obj/ and trufm
      make install          install to ~/.local/bin/trufm
      make uninstall        remove the installed executable
      make install PREFIX=/usr/local

  ───────────────────────────────────────────────────────────────
  ▓ CONFIGURATION
  Direct runs load ~/.config/trufm/config by default, unless
  TRUFM_CONFIG supplies another file path.

  The repository provides:
      trufm.conf          local settings for make run / make gui
      trufm.conf.example  annotated reference with supported keys

  make run and make gui explicitly use the repository configuration:
      make run CONF=trufm.conf.example
      make gui CONF=another.conf

  To configure an installed executable:
      mkdir -p ~/.config/trufm
      cp trufm.conf.example ~/.config/trufm/config

  Or select another file for one invocation:
      TRUFM_CONFIG=/path/to/trufm.conf trufm

  Main settings (all optional):
  ▪ hidden, root_hidden       visibility of dotfiles
  ▪ sort, sort_desc           name / size / date; reverse order
  ▪ git                       Git status marks
  ▪ confirm_delete            confirmation before permanent deletion
  ▪ places_width              width of the places column (5–50%)
  ▪ root_width                width of the parent column (5–50%)
  ▪ preview_width             width of the preview column (5–50%)
  ▪ places.standard, devices  standard folders and mounted devices
  ▪ place                     custom place, shortcut, and label
  ▪ tab                       initial tab (on the first run)
  ▪ open.<ext> / open.<mime>   programs for opening files
  ▪ highlight                 built-in code highlighting in the preview (default on)
  ▪ preview.<ext>             preview commands, including image: output
  ▪ extract.<ext>             custom extraction commands
  ▪ color.<name>              interface palette in #rrggbb

  Example:
      hidden = true
      sort = name
      git = true
      place = w ~/Projects | Projects
      open.md,txt = term: ${EDITOR:-vi}
      preview.md = bat --color=always --style=plain --paging=never %f

  Runtime state: $XDG_CONFIG_HOME/trufm/state, or
                 ~/.config/trufm/state if XDG_CONFIG_HOME is unset.
  Bookmarks:     $XDG_CONFIG_HOME/trufm/places, or
                 ~/.config/trufm/places.

  ───────────────────────────────────────────────────────────────
  ▓ CONTROLS
  Moving and browsing:
  ▪ j / k, arrows       move down / up
  ▪ h / l, arrows       parent directory / enter or open
  ▪ Tab / Shift-Tab     switch columns
  ▪ gg / G              first / last entry
  ▪ ~                   home directory
  ▪ /                   filter current file list
  ▪ .                   toggle hidden files
  ▪ 1–9                 switch or create tab
  ▪ t / x               new tab / close tab
  ▪ b                   bookmark current folder

  Files and tasks:
  ▪ V                   select a range of files
  ▪ y / d / p           copy / cut / paste
  ▪ D / X               trash / permanently delete
  ▪ u                   restore last trashed item
  ▪ r / n               rename / new folder
  ▪ L                   paste symbolic links
  ▪ c / C               change mode / ownership
  ▪ E                   extract an archive
  ▪ P / K / R           pause / cancel / retry a task
  ▪ a / A               Git stage / unstage
  ▪ =                   show Git diff
  ▪ i                   show file properties
  ▪ o                   open with a selected program
  ▪ :                   execute a shell command
  ▪ ?                   full in-app help
  ▪ q / Q               quit / quit and change shell directory

  See the built-in help (?) for the complete key and mouse reference.

  ───────────────────────────────────────────────────────────────
  ▓ SHELL INTEGRATION
  To make Q leave the calling shell in trufm's current directory,
  load the function generated by the program into your shell.

  Bash / Zsh:
      eval "$(trufm --init bash)"

  Fish:
      trufm --init fish | source

  The generated shell wrapper uses --cd-file; trufm itself cannot
  change the working directory of its parent shell.

  ───────────────────────────────────────────────────────────────
  ▓ FILE HANDLING
  Opening rules use a filename extension or MIME pattern, with
  xdg-open as a fallback. A term: rule runs an interactive program
  in the terminal; GUI mode can open it through $TERMINAL or xterm.

  Source files trufm knows are colored by its own highlighter
  (highlight = false hands them to preview rules).
  Preview rules can produce colored text or an image (PNG / PPM).
  External previews are run separately and stopped when the
  selection changes.

  Archive extraction creates a separate destination directory.
  Trash follows freedesktop conventions and can restore files.

  ───────────────────────────────────────────────────────────────
  ▓ FINAL WORDS
  A place for every file. A tool for every task.
