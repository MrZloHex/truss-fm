; look.pl -- the colours of the layout, as "TUI · file manager + picker" has
; them: its ELEMENT -> TOKEN table, for a terminal and a window alike. All
; xterm-256 greys and hues but RED. No state here

USE <std/core/core.pl>
USE <modular.pl>

; --- the palette ------------------------------------------------------------------

CONST Color BG     = 0xFF222222     ; the panes
CONST Color BAR    = 0xFF282828     ; the title bar
CONST Color SEL    = 0xFF3A3A3A     ; the cursor row, a tab or a button that is off
CONST Color LINE   = 0xFF4E4E4E     ; frames, what a filter left out
CONST Color TEXT   = 0xFFE4E4E4
CONST Color TEXT2  = 0xFFA8A8A8     ; a tab that is off
CONST Color DIM    = 0xFF949494     ; labels, hidden files, binaries
CONST Color AMBER  = 0xFFFFAF00
CONST Color STEEL  = 0xFF87AFD7
CONST Color OLIVE  = 0xFFAFAF00
CONST Color ORANGE = 0xFFFF8700
CONST Color RED    = 0xFFE46C6C
CONST Color INK    = 0xFF222222     ; type on amber

; --- what each thing is drawn in ---------------------------------------------------

CONST Color C_FRAME    = LINE       ; a column
CONST Color C_FOCUS    = AMBER      ; the column with the focus
CONST Color C_CURSOR   = SEL        ; the cursor row's fill
CONST Color C_MARK     = AMBER      ; ✓
CONST Color C_DIR      = STEEL      ; ▸ and a folder's name
CONST Color C_HIDDEN   = DIM        ; a hidden file, a binary
CONST Color C_BROKEN   = RED        ; ✗ and a link to nothing
CONST Color C_REMOTE   = OLIVE      ; ● a remote that is online
CONST Color C_HEADER   = AMBER      ; the header lines of a preview
CONST Color C_MATCH    = AMBER      ; what a filter matched, letter by letter
CONST Color C_NOMATCH  = LINE       ; a file it left out
CONST Color C_TASK     = AMBER      ; █ of a task's bar
CONST Color C_TRACK    = SEL        ; ─ what is left of it

; a disk from this full on is shown in orange
CONST I32 DISK_FULL = 80

Color disk_color: [ I32 percent ]
 | RET [ SELECT [ percent >= DISK_FULL | ORANGE | TEXT ] ]
 \_

Style tab_style: [ B1 lit ]
 | RET [ SELECT [ lit | (on)[ INK | AMBER ] | (on)[ TEXT2 | SEL ] ] ]
 \_

Style button_style: [ B1 lit ]
 | RET [ SELECT [ lit | (on)[ INK | AMBER ] | (on)[ TEXT | SEL ] ] ]
 \_

; --- the theme --------------------------------------------------------------------

UiTheme app_theme: []
 | UiTheme t = (default_theme)[]
 | t.bg = BG
 | t.fg = TEXT
 | t.border = C_FRAME
 | t.focus = C_FOCUS
 | t.title = (bold)[ AMBER ]
 | t.sub = (fg)[ DIM ]
 | t.frame = BDR_SINGLE
 | t.dim = DIM
 | t.cursor = C_CURSOR
 | t.cursor_blur = C_CURSOR
 | t.field = BG                     ; the path and the filter sit on the pane
 | t.field_focus = BG
 | t.field_fg = TEXT
 | t.accent = AMBER
 | t.hover = 0xFF303030
 | t.selection = LINE
 | t.box_pad = 1
 | t.panel = BG
 | t.radius = 0.0                   ; square in a window as in a terminal
 | RET [ t ]
 \_
