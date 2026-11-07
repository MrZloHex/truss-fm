; look.pl -- the colours of the layout, as "TUI · file manager + picker" has
; them: its ELEMENT -> TOKEN table, for a terminal and a window alike. All
; xterm-256 greys and hues but RED. The palette is the config's to change
; (color.* in config.pl); look_derive gives each element its colour from it

USE <std/core/core.pl>
USE <modular.pl>
!USES <../core/config.pl>

; --- the palette ------------------------------------------------------------------

Color BG     = 0xFF222222     ; the panes
Color BAR    = 0xFF282828     ; the title bar
Color SEL    = 0xFF3A3A3A     ; the cursor row, a tab or a button that is off
Color LINE   = 0xFF4E4E4E     ; frames, what a filter left out
Color TEXT   = 0xFFE4E4E4
Color TEXT2  = 0xFFA8A8A8     ; a tab that is off
Color DIM    = 0xFF949494     ; labels, hidden files, binaries
Color AMBER  = 0xFFFFAF00
Color STEEL  = 0xFF87AFD7
Color SAGE   = 0xFF87AF5F     ; programs
Color OLIVE  = 0xFFAFAF00
Color ORANGE = 0xFFFF8700
Color RED    = 0xFFE46C6C
Color INK    = 0xFF222222     ; type on amber

; --- what each thing is drawn in ---------------------------------------------------

Color C_FRAME      = 0       ; a column
Color C_FOCUS      = 0      ; the column with the focus
Color C_CURSOR     = 0        ; the cursor row's fill
Color C_MARK       = 0      ; -- VISUAL LINE --
Color C_CHOSEN     = 0       ; a row chosen in visual: its fill
Color C_CHOSEN_CUR = 0xFF5F5F5F   ; and the cursor's, among them
Color C_DIR        = 0      ; ▸ and a folder's name
Color C_EXEC       = 0      ; a file that may be run
Color C_HIDDEN     = 0        ; a hidden file, a binary
Color C_BROKEN     = 0        ; ✗ and a link to nothing
Color C_REMOTE     = 0      ; ● a remote that is online
Color C_HEADER     = 0      ; the header lines of a preview
Color C_KEY          = 0      ; a key in the help, apart from its headings
Color C_MATCH      = 0      ; what a filter matched, letter by letter
Color C_NOMATCH    = 0       ; a file it left out
Color C_TASK       = 0      ; █ of a task's bar
Color C_TRACK      = 0        ; ─ what is left of it
Color C_COMMENT    = 0        ; a comment in a highlighted preview
Color C_STRING     = 0        ; a string, a `code` span
Color C_NUMBER     = 0        ; a number
Color C_KEYWORD    = 0        ; a keyword, a @@ hunk
Color C_TYPE       = 0        ; a type, a key, $VAR, emphasis
Color C_PREPROC    = 0        ; #include, !USES, [section], a diff's file lines
Color C_GUIDE      = 0        ; PLUM's | and \_ marks
Color C_ADD        = 0        ; a diff's + line
Color C_DEL        = 0        ; and its - line

; each element its colour from the palette
ABYSS look_derive: []
 | C_FRAME = LINE
 | C_FOCUS = AMBER
 | C_CURSOR = SEL
 | C_MARK = AMBER
 | C_CHOSEN = LINE
 | C_DIR = STEEL
 | C_EXEC = SAGE
 | C_HIDDEN = DIM
 | C_BROKEN = RED
 | C_REMOTE = OLIVE
 | C_HEADER = AMBER
 | C_KEY = STEEL
 | C_MATCH = AMBER
 | C_NOMATCH = LINE
 | C_TASK = AMBER
 | C_TRACK = SEL
 | C_COMMENT = DIM
 | C_STRING = SAGE
 | C_NUMBER = AMBER
 | C_KEYWORD = STEEL
 | C_TYPE = OLIVE
 | C_PREPROC = ORANGE
 | C_GUIDE = LINE
 | C_ADD = SAGE
 | C_DEL = RED
 \_

; the palette as the config set it -- the colours it did not set as they
; are -- and from it every element's: once, after config_load
ABYSS look_apply: []
 | @Color slots{} = [ @BG | @BAR | @SEL | @LINE | @TEXT | @TEXT2 | @DIM |
 |                    @AMBER | @STEEL | @SAGE | @OLIVE | @ORANGE | @RED | @INK ]
 | FOR [ I32 i = 0 | i < NCOLORS | i += 1 ]
 |  | IF [ CFG.colors{i} != 0 ]
 |  |  | ?(slots{i}) = CFG.colors{i} AS Color
 |  |  \_
 |  \_
 | (look_derive)[]
 \_

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
