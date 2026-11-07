; syntax.pl -- the highlighter for the preview: a language picked by a file's
; name (or a script's first line), and a line cut into spans of a kind each --
; comment, string, number, keyword, ... -- the state of a block comment or a
; string that runs over lines carried from one line to the next. A language
; is mostly data: its comment marks, quotes and word lists. No colours here:
; ui/preview.pl gives each kind one

USE <std/core/core.pl>
USE <std/core/str.pl>

; --- kinds and state --------------------------------------------------------------

CONST I32 SY_PLAIN   = 0
CONST I32 SY_COMMENT = 1
CONST I32 SY_STRING  = 2
CONST I32 SY_NUMBER  = 3
CONST I32 SY_KEYWORD = 4
CONST I32 SY_TYPE    = 5
CONST I32 SY_PREPROC = 6     ; #include, !USES, a section's [name], a diff's file lines
CONST I32 SY_GUIDE   = 7     ; the | and \_ of a PLUM block
CONST I32 SY_HEAD    = 8     ; a Markdown heading
CONST I32 SY_ADD     = 9     ; a diff's + line
CONST I32 SY_DEL     = 10    ; and its - line

; what a line leaves for the next one
CONST I32 SS_NONE     = 0
CONST I32 SS_BLOCK    = 1    ; inside a block comment
CONST I32 SS_TRIPLE_D = 2    ; inside """ ... """
CONST I32 SS_TRIPLE_S = 3    ; inside ''' ... '''
CONST I32 SS_RAW      = 4    ; inside a `...` string
CONST I32 SS_FENCE    = 5    ; inside a Markdown code fence

; how a language is read
CONST I32 LM_CODE = 0
CONST I32 LM_MD   = 1
CONST I32 LM_DIFF = 2

CONST I32 LF_KEYS   = 1      ; key = value, key: value, [section] lines
CONST I32 LF_HASHPP = 2      ; a line's first # starts a directive (C)
CONST I32 LF_TRIPLE = 4      ; """ and ''' strings (Python, TOML)
CONST I32 LF_RAW    = 8      ; ` strings, which may run over lines
CONST I32 LF_DOLLAR = 16     ; $name and ${name} (shell, Make)
CONST I32 LF_CAPS   = 32     ; a Capitalised word is a type
CONST I32 LF_ANGLE  = 64     ; <...> after include or USE is a string
CONST I32 LF_STRKEY = 128    ; a string followed by : is a key (JSON, YAML)
CONST I32 LF_PLUM   = 256    ; the | and \_ marks, and !USES lines
CONST I32 LF_MAKE   = 512    ; $(name)

TYPE Lang: STRUCT
 | I32 mode
 | I32 flags
 | @CONST C1 line1          ; line comment marks, "" for none
 | @CONST C1 line2
 | @CONST C1 open           ; block comment, "" for none
 | @CONST C1 close
 | @CONST C1 quotes         ; the characters a string may start with
 | @CONST C1 keywords       ; words, a space between
 | @CONST C1 types
 \_

TYPE SynSpan: STRUCT
 | I32 at
 | I32 len
 | I32 kind
 \_

; what a line is being cut by
TYPE SynCtx: STRUCT
 | @Lang l
 | @CONST C1 s
 | I32 len
 | @SynSpan sp
 | I32 cap
 | I32 n
 \_

; --- the languages ----------------------------------------------------------------

CONST @CONST C1 KW_PLUM = "RET BREAK CONTINUE POSTLUDE STATIC_ASSERT UNREACHABLE IF ELIF ELSE SWITCH CASE LOOP WHILE FOR STRUCT UNION ENUM TYPE IFACE CLASS IMPL PUBLIC PRIVATE ANONYMOUS REQ SIZE OFFSET COUNT AS ARG COMPTIME SELECT OPTION ATOMIC_LOAD ATOMIC_STORE ATOMIC_SWAP ATOMIC_ADD ATOMIC_SUB ATOMIC_AND ATOMIC_OR ATOMIC_XOR ATOMIC_CAS FENCE RELAXED ACQUIRE RELEASE ACQ_REL SEQ_CST ASM IN OUT INOUT MEM CLOBBER CONST VOLATILE LOCAL EXTERN DATA PACKED ALIGN MODULE USE USES NORETURN NAKED INLINE NOINLINE WEAK USED SECTION ALIAS INTRINSIC INTERRUPT THREAD SYMBOL TRUE FALSE NULL"
CONST @CONST C1 TY_PLUM = "ABYSS B1 C1 U8 U16 U32 U64 USIZE I8 I16 I32 I64 ISIZE F32 F64 FN Self"

CONST @CONST C1 KW_C = "if else for while do switch case default break continue return goto sizeof typedef struct union enum static extern const volatile inline register auto restrict NULL true false"
CONST @CONST C1 TY_C = "void char short int long float double signed unsigned bool size_t ssize_t ptrdiff_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t uintptr_t intptr_t FILE"
CONST @CONST C1 KW_CPP = "if else for while do switch case default break continue return goto sizeof typedef struct union enum static extern const volatile inline register auto class namespace template typename public private protected virtual override final new delete this using try catch throw nullptr constexpr noexcept operator friend explicit mutable static_cast dynamic_cast reinterpret_cast const_cast NULL true false"

CONST @CONST C1 KW_SH = "if then else elif fi for while until do done case esac in function select return exit break continue local export readonly declare unset shift source alias eval exec set trap time"

CONST @CONST C1 KW_PY = "and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case True False None self"
CONST @CONST C1 TY_PY = "int str float bool list dict set tuple bytes object"

CONST @CONST C1 KW_RS = "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self static struct super trait true type unsafe use where while"
CONST @CONST C1 TY_RS = "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str"

CONST @CONST C1 KW_GO = "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota"
CONST @CONST C1 TY_GO = "bool byte rune string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 complex64 complex128 error any"

CONST @CONST C1 KW_JS = "as async await break case catch class const continue debugger default delete do else enum export extends false finally for from function if implements import in instanceof interface let new null of private protected public return static super switch this throw true try typeof undefined var void while with yield readonly type namespace declare abstract"
CONST @CONST C1 TY_JS = "string number boolean any unknown never object symbol bigint"

CONST @CONST C1 KW_MAKE = "ifeq ifneq ifdef ifndef else endif include sinclude define endef export override vpath"

; `l` set to the language of that mode, flags, comment marks, quotes and words
LOCAL ABYSS sy_set: [ @Lang l | I32 mode | I32 flags | @CONST C1 line1 | @CONST C1 line2 | @CONST C1 open | @CONST C1 close | @CONST C1 quotes | @CONST C1 keywords | @CONST C1 types ]
 | l.mode = mode
 | l.flags = flags
 | l.line1 = line1
 | l.line2 = line2
 | l.open = open
 | l.close = close
 | l.quotes = quotes
 | l.keywords = keywords
 | l.types = types
 \_

; a word of the space-separated `list`: the `wl` bytes of `s` from `at`
LOCAL B1 sy_word_in: [ @CONST C1 list | @CONST C1 s | I32 at | I32 wl ]
 | I32 i = 0
 | WHILE [ list{i} != '\0' ]
 |  | WHILE [ list{i} == ' ' ]
 |  |  | i += 1
 |  |  \_
 |  | I32 j = i
 |  | WHILE [ list{j} != '\0' && list{j} != ' ' ]
 |  |  | j += 1
 |  |  \_
 |  | IF [ j - i == wl ]
 |  |  | I32 k = 0
 |  |  | WHILE [ k < wl && list{i + k} == s{at + k} ]
 |  |  |  | k += 1
 |  |  |  \_
 |  |  | IF [ k == wl ]
 |  |  |  | RET [ TRUE ]
 |  |  |  \_
 |  |  \_
 |  | i = j
 |  \_
 | RET [ FALSE ]
 \_

; `c` is one of the characters of `set`
LOCAL B1 sy_has: [ @CONST C1 set | C1 c ]
 | FOR [ I32 i = 0 | set{i} != '\0' | i += 1 ]
 |  | IF [ set{i} == c ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

; the file's extension in lower case, "" for none; a dotfile's name is its own
LOCAL ABYSS sy_ext: [ @C1 out | USIZE cap | @CONST C1 name ]
 | I32 dot = -1
 | I32 n = 0
 | WHILE [ name{n} != '\0' ]
 |  | IF [ name{n} == '.' && n > 0 ]
 |  |  | dot = n
 |  |  \_
 |  | n += 1
 |  \_
 | out{0} = '\0'
 | IF [ dot < 0 || (n - dot) AS USIZE >= cap ]
 |  | RET []
 |  \_
 | I32 k = 0
 | WHILE [ name{dot + 1 + k} != '\0' ]
 |  | C1 c = name{dot + 1 + k}
 |  | out{k} = SELECT [ c >= 'A' && c <= 'Z' | (c - 'A' + 'a') AS C1 | c ]
 |  | k += 1
 |  \_
 | out{k} = '\0'
 \_

; is there no extension to go by
B1 syntax_dotless: [ @CONST C1 name ]
 | C1 ext{16}
 | (sy_ext)[ ext | 16 | name ]
 | RET [ ext{0} == '\0' ]
 \_

; `l` for the file `name`, by its extension or its well-known name. FALSE:
; no language fits
B1 syntax_by_name: [ @Lang l | @CONST C1 name ]
 | C1 ext{16}
 | (sy_ext)[ ext | 16 | name ]
 | IF [ ext{0} == '\0' ]
 |  | IF [ (str_eq)[ name | "Makefile" ] || (str_eq)[ name | "makefile" ] || (str_eq)[ name | "GNUmakefile" ] ]
 |  |  | (sy_set)[ l | LM_CODE | (LF_KEYS | LF_DOLLAR | LF_MAKE) | "#" | "" | "" | "" | "\"'" | KW_MAKE | "" ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | IF [ (str_eq)[ name | "Dockerfile" ] || (str_eq)[ name | "PKGBUILD" ] || (str_eq)[ name | ".bashrc" ] || (str_eq)[ name | ".zshrc" ] || (str_eq)[ name | ".profile" ] || (str_eq)[ name | ".bash_profile" ] || (str_eq)[ name | ".zshenv" ] ]
 |  |  | (sy_set)[ l | LM_CODE | LF_DOLLAR | "#" | "" | "" | "" | "\"'" | KW_SH | "" ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | IF [ (str_eq)[ name | ".gitignore" ] || (str_eq)[ name | ".env" ] || (str_eq)[ name | ".gitconfig" ] || (str_eq)[ name | ".editorconfig" ] ]
 |  |  | (sy_set)[ l | LM_CODE | LF_KEYS | "#" | ";" | "" | "" | "\"" | "true false" | "" ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  | RET [ FALSE ]
 |  \_
 | IF [ (sy_word_in)[ " pl plum " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_PLUM | LF_ANGLE | LF_CAPS) | ";" | "" | "" | "" | "\"'" | KW_PLUM | TY_PLUM ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " c h " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_HASHPP | LF_ANGLE) | "//" | "" | "/*" | "*/" | "\"'" | KW_C | TY_C ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " cc cpp cxx hpp hh hxx " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_HASHPP | LF_ANGLE) | "//" | "" | "/*" | "*/" | "\"'" | KW_CPP | TY_C ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " sh bash zsh ksh " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | LF_DOLLAR | "#" | "" | "" | "" | "\"'" | KW_SH | "" ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " py pyw " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_TRIPLE | LF_CAPS) | "#" | "" | "" | "" | "\"'" | KW_PY | TY_PY ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " rs " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | LF_CAPS | "//" | "" | "/*" | "*/" | "\"" | KW_RS | TY_RS ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " go " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | LF_RAW | "//" | "" | "/*" | "*/" | "\"'`" | KW_GO | TY_GO ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " js mjs cjs jsx ts tsx " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_RAW | LF_CAPS) | "//" | "" | "/*" | "*/" | "\"'`" | KW_JS | TY_JS ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " json jsonc " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | LF_STRKEY | "//" | "" | "/*" | "*/" | "\"" | "true false null" | "" ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " toml " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_KEYS | LF_TRIPLE) | "#" | "" | "" | "" | "\"'" | "true false" | "" ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " ini conf cfg desktop service timer socket rc properties env " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | LF_KEYS | "#" | ";" | "" | "" | "\"" | "true false yes no on off" | "" ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " yaml yml " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_KEYS | LF_STRKEY) | "#" | "" | "" | "" | "\"'" | "true false null yes no on off True False" | "" ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " mk mak " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_CODE | (LF_KEYS | LF_DOLLAR | LF_MAKE) | "#" | "" | "" | "" | "\"'" | KW_MAKE | "" ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " md markdown " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_MD | 0 | "" | "" | "" | "" | "" | "" | "" ]
 |  | RET [ TRUE ]
 |  \_
 | IF [ (sy_word_in)[ " diff patch " | ext | 0 | (str_len)[ ext ] AS I32 ] ]
 |  | (sy_set)[ l | LM_DIFF | 0 | "" | "" | "" | "" | "" | "" | "" ]
 |  | RET [ TRUE ]
 |  \_
 | RET [ FALSE ]
 \_

; `l` for a script whose first line `first` is #!... FALSE: it is not one
B1 syntax_by_shebang: [ @Lang l | @CONST C1 first ]
 | IF [ first{0} != '#' || first{1} != '!' ]
 |  | RET [ FALSE ]
 |  \_
 | Option<USIZE> py = (str_index)[ first | "python" ]
 | IF [ (py.is_some)[] ]
 |  | RET [ (syntax_by_name)[ l | "x.py" ] ]
 |  \_
 | Option<USIZE> js = (str_index)[ first | "node" ]
 | IF [ (js.is_some)[] ]
 |  | RET [ (syntax_by_name)[ l | "x.js" ] ]
 |  \_
 | Option<USIZE> sh = (str_index)[ first | "sh" ]
 | IF [ (sh.is_some)[] ]
 |  | RET [ (syntax_by_name)[ l | "x.sh" ] ]
 |  \_
 | RET [ FALSE ]
 \_

; --- cutting a line ---------------------------------------------------------------

; `len` bytes from `at` are of `kind`, joined to the span before if it is of
; that kind too. Past `cap` spans the last one takes the rest
LOCAL ABYSS sy_emit: [ @SynCtx c | I32 at | I32 len | I32 kind ]
 | IF [ len <= 0 ]
 |  | RET []
 |  \_
 | I32 k = c.n
 | IF [ k > 0 && (c.sp{k - 1}.kind == kind || k >= c.cap) ]
 |  | c.sp{k - 1}.len += len
 |  | RET []
 |  \_
 | c.sp{k}.at = at
 | c.sp{k}.len = len
 | c.sp{k}.kind = kind
 | c.n = k + 1
 \_

; the line has `pre` at `i`
LOCAL B1 sy_at: [ @SynCtx c | I32 i | @CONST C1 pre ]
 | RET [ pre{0} != '\0' && (str_starts)[ c.s + i | pre ] ]
 \_

; where `pre` is in the line from `from`, -1: nowhere
LOCAL I32 sy_find: [ @SynCtx c | I32 from | @CONST C1 pre ]
 | FOR [ I32 j = from | j < c.len | j += 1 ]
 |  | IF [ (sy_at)[ c | j | pre ] ]
 |  |  | RET [ j ]
 |  |  \_
 |  \_
 | RET [ -1 ]
 \_

LOCAL B1 sy_idc: [ C1 c ]
 | RET [ (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' ]
 \_

LOCAL B1 sy_digit: [ C1 c ]
 | RET [ c >= '0' && c <= '9' ]
 \_

; a string that starts with the quote at `i`, escapes with \: the index past
; its closing quote, -1: the line ends first
LOCAL I32 sy_str_end: [ @SynCtx c | I32 i ]
 | C1 q = c.s{i}
 | I32 j = i + 1
 | WHILE [ j < c.len ]
 |  | IF [ c.s{j} == '\\' && j + 1 < c.len ]
 |  |  | j += 2
 |  | ELIF [ c.s{j} == q ]
 |  |  | RET [ j + 1 ]
 |  | ELSE
 |  |  | j += 1
 |  |  \_
 |  \_
 | RET [ -1 ]
 \_

; the end past the close of a string that runs over lines (state `st`), from
; `from`; -1: not on this line
LOCAL I32 sy_multi_end: [ @SynCtx c | I32 from | I32 st ]
 | C1 q = SELECT [ st == SS_TRIPLE_D | '"' | '\'' ]
 | I32 j = from
 | WHILE [ j < c.len ]
 |  | IF [ c.s{j} == '\\' && j + 1 < c.len ]
 |  |  | j += 2
 |  | ELIF [ st == SS_RAW && c.s{j} == '`' ]
 |  |  | RET [ j + 1 ]
 |  | ELIF [ st != SS_RAW && c.s{j} == q && c.s{j + 1} == q && c.s{j + 2} == q ]
 |  |  | RET [ j + 3 ]
 |  | ELSE
 |  |  | j += 1
 |  |  \_
 |  \_
 | RET [ -1 ]
 \_

; a <...> after the word that ended at `at`, as a string; the index past what
; was taken (`at` if there is none)
LOCAL I32 sy_angle: [ @SynCtx c | I32 at ]
 | I32 k = at
 | WHILE [ c.s{k} == ' ' ]
 |  | k += 1
 |  \_
 | IF [ c.s{k} != '<' ]
 |  | RET [ at ]
 |  \_
 | I32 e = (sy_find)[ c | k | ">" ]
 | IF [ e < 0 ]
 |  | RET [ at ]
 |  \_
 | (sy_emit)[ c | at | k - at | SY_PLAIN ]
 | (sy_emit)[ c | k | e + 1 - k | SY_STRING ]
 | RET [ e + 1 ]
 \_

; a word that starts with a capital and has a small letter too
LOCAL B1 sy_capped: [ @CONST C1 s | I32 at | I32 wl ]
 | IF [ !(s{at} >= 'A' && s{at} <= 'Z') ]
 |  | RET [ FALSE ]
 |  \_
 | FOR [ I32 k = 1 | k < wl | k += 1 ]
 |  | IF [ s{at + k} >= 'a' && s{at + k} <= 'z' ]
 |  |  | RET [ TRUE ]
 |  |  \_
 |  \_
 | RET [ FALSE ]
 \_

; a key or a [section] at the start of a line (from `first`), for the key =
; value languages; the index it ends at (`first` if there is none)
LOCAL I32 sy_key: [ @SynCtx c | I32 first ]
 | I32 j = first
 | WHILE [ c.s{j} == '-' && c.s{j + 1} == ' ' ]
 |  | j += 2
 |  | WHILE [ c.s{j} == ' ' ]
 |  |  | j += 1
 |  |  \_
 |  \_
 | IF [ c.s{j} == '[' ]
 |  | I32 e = (sy_find)[ c | j | "]" ]
 |  | IF [ e > j && !(c.l.mode == LM_MD) && (c.s{e + 1} == '\0' || c.s{e + 1} == ' ') ]
 |  |  | (sy_emit)[ c | first | j - first | SY_PLAIN ]
 |  |  | (sy_emit)[ c | j | e + 1 - j | SY_PREPROC ]
 |  |  | RET [ e + 1 ]
 |  |  \_
 |  | RET [ first ]
 |  \_
 | I32 k = j
 | WHILE [ (sy_idc)[ c.s{k} ] || (sy_has)[ "._-/%$()@+,*" | c.s{k} ] ]
 |  | k += 1
 |  \_
 | I32 m = k
 | WHILE [ c.s{m} == ' ' ]
 |  | m += 1
 |  \_
 | B1 sep = c.s{m} == '=' || (c.s{m} == ':' && (c.s{m + 1} == ' ' || c.s{m + 1} == '\0' || c.s{m + 1} == '=' || c.s{m + 1} == ':'))
 | IF [ k > j && sep ]
 |  | (sy_emit)[ c | first | j - first | SY_PLAIN ]
 |  | (sy_emit)[ c | j | k - j | SY_KEYWORD ]
 |  | RET [ k ]
 |  \_
 | RET [ first ]
 \_

; a line of code in the language `c.l`
LOCAL ABYSS sy_code: [ @SynCtx c | @I32 state ]
 | @Lang l = c.l
 | @CONST C1 s = c.s
 | I32 len = c.len
 | I32 i = 0
 |
 | ; a block comment or a string still open from the line before
 | I32 st = ?state
 | IF [ st == SS_BLOCK ]
 |  | I32 e = (sy_find)[ c | 0 | l.close ]
 |  | IF [ e < 0 ]
 |  |  | (sy_emit)[ c | 0 | len | SY_COMMENT ]
 |  |  | RET []
 |  |  \_
 |  | i = e + (str_len)[ l.close ] AS I32
 |  | (sy_emit)[ c | 0 | i | SY_COMMENT ]
 |  | ?state = SS_NONE
 |  \_
 | IF [ st == SS_TRIPLE_D || st == SS_TRIPLE_S || st == SS_RAW ]
 |  | I32 e = (sy_multi_end)[ c | 0 | st ]
 |  | IF [ e < 0 ]
 |  |  | (sy_emit)[ c | 0 | len | SY_STRING ]
 |  |  | RET []
 |  |  \_
 |  | i = e
 |  | (sy_emit)[ c | 0 | i | SY_STRING ]
 |  | ?state = SS_NONE
 |  \_
 |
 | ; PLUM: the marks of the block, then a directive
 | IF [ (l.flags & LF_PLUM) != 0 && i == 0 ]
 |  | WHILE [ s{i} == ' ' || s{i} == '|' ]
 |  |  | (sy_emit)[ c | i | 1 | SELECT [ s{i} == '|' | SY_GUIDE | SY_PLAIN ] ]
 |  |  | i += 1
 |  |  \_
 |  | IF [ s{i} == '\\' && s{i + 1} == '_' ]
 |  |  | (sy_emit)[ c | i | 2 | SY_GUIDE ]
 |  |  | i += 2
 |  |  \_
 |  \_
 |
 | I32 first = i
 | WHILE [ s{first} == ' ' ]
 |  | first += 1
 |  \_
 | IF [ (l.flags & LF_KEYS) != 0 && i == 0 ]
 |  | i = (sy_key)[ c | first ]
 |  | IF [ i == first ]
 |  |  | i = 0
 |  |  \_
 |  \_
 |
 | WHILE [ i < len ]
 |  | C1 ch = s{i}
 |  |
 |  | ; a comment to the end of the line; # only at the start of a word
 |  | B1 hash_ok = i == 0 || s{i - 1} == ' ' || s{i - 1} == ';'
 |  | IF [ (sy_at)[ c | i | l.line1 ] && (l.line1{0} != '#' || hash_ok) ]
 |  |  | (sy_emit)[ c | i | len - i | SY_COMMENT ]
 |  |  | RET []
 |  |  \_
 |  | IF [ (sy_at)[ c | i | l.line2 ] && (l.line2{0} != '#' || hash_ok) ]
 |  |  | (sy_emit)[ c | i | len - i | SY_COMMENT ]
 |  |  | RET []
 |  |  \_
 |  | IF [ (sy_at)[ c | i | l.open ] ]
 |  |  | I32 olen = (str_len)[ l.open ] AS I32
 |  |  | I32 e = (sy_find)[ c | i + olen | l.close ]
 |  |  | IF [ e < 0 ]
 |  |  |  | (sy_emit)[ c | i | len - i | SY_COMMENT ]
 |  |  |  | ?state = SS_BLOCK
 |  |  |  | RET []
 |  |  |  \_
 |  |  | I32 stop = e + (str_len)[ l.close ] AS I32
 |  |  | (sy_emit)[ c | i | stop - i | SY_COMMENT ]
 |  |  | i = stop
 |  |  | CONTINUE
 |  |  \_
 |  |
 |  | ; a string, one that runs over lines too
 |  | IF [ (sy_has)[ l.quotes | ch ] ]
 |  |  | B1 triple = (l.flags & LF_TRIPLE) != 0 && (ch == '"' || ch == '\'') && s{i + 1} == ch && s{i + 2} == ch
 |  |  | IF [ triple || (ch == '`' && (l.flags & LF_RAW) != 0) ]
 |  |  |  | I32 kind = SELECT [ ch == '`' | SS_RAW | SELECT [ ch == '"' | SS_TRIPLE_D | SS_TRIPLE_S ] ]
 |  |  |  | I32 e = (sy_multi_end)[ c | i + SELECT [ triple | 3 | 1 ] | kind ]
 |  |  |  | IF [ e < 0 ]
 |  |  |  |  | (sy_emit)[ c | i | len - i | SY_STRING ]
 |  |  |  |  | ?state = kind
 |  |  |  |  | RET []
 |  |  |  |  \_
 |  |  |  | (sy_emit)[ c | i | e - i | SY_STRING ]
 |  |  |  | i = e
 |  |  |  | CONTINUE
 |  |  |  \_
 |  |  | I32 e = (sy_str_end)[ c | i ]
 |  |  | IF [ e >= 0 ]
 |  |  |  | I32 k = e
 |  |  |  | WHILE [ s{k} == ' ' ]
 |  |  |  |  | k += 1
 |  |  |  |  \_
 |  |  |  | B1 key = (l.flags & LF_STRKEY) != 0 && s{k} == ':'
 |  |  |  | (sy_emit)[ c | i | e - i | SELECT [ key | SY_TYPE | SY_STRING ] ]
 |  |  |  | i = e
 |  |  |  | CONTINUE
 |  |  |  \_
 |  |  \_
 |  |
 |  | ; #include <x>, and a PLUM directive: !USES <x>
 |  | IF [ ch == '#' && (l.flags & LF_HASHPP) != 0 && i == first ]
 |  |  | I32 j = i + 1
 |  |  | WHILE [ s{j} == ' ' ]
 |  |  |  | j += 1
 |  |  |  \_
 |  |  | I32 w = j
 |  |  | WHILE [ (sy_idc)[ s{j} ] ]
 |  |  |  | j += 1
 |  |  |  \_
 |  |  | (sy_emit)[ c | i | j - i | SY_PREPROC ]
 |  |  | i = j
 |  |  | IF [ (l.flags & LF_ANGLE) != 0 && (sy_word_in)[ " include import " | s | w | j - w ] ]
 |  |  |  | i = (sy_angle)[ c | j ]
 |  |  |  \_
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ ch == '!' && (l.flags & LF_PLUM) != 0 && i == first && s{i + 1} >= 'A' && s{i + 1} <= 'Z' ]
 |  |  | I32 j = i + 1
 |  |  | WHILE [ (sy_idc)[ s{j} ] ]
 |  |  |  | j += 1
 |  |  |  \_
 |  |  | (sy_emit)[ c | i | j - i | SY_PREPROC ]
 |  |  | I32 w0 = i
 |  |  | i = j
 |  |  | IF [ (sy_word_in)[ " !USES " | s | w0 | j - w0 ] ]
 |  |  |  | i = (sy_angle)[ c | j ]
 |  |  |  \_
 |  |  | CONTINUE
 |  |  \_
 |  |
 |  | ; $name, ${name}, $(name)
 |  | IF [ ch == '$' && (l.flags & LF_DOLLAR) != 0 ]
 |  |  | I32 j = i + 1
 |  |  | IF [ s{j} == '{' || (s{j} == '(' && (l.flags & LF_MAKE) != 0) ]
 |  |  |  | I32 e = (sy_find)[ c | j | SELECT [ s{j} == '{' | "}" | ")" ] ]
 |  |  |  | j = SELECT [ e < 0 | j | e + 1 ]
 |  |  | ELIF [ (sy_idc)[ s{j} ] ]
 |  |  |  | WHILE [ (sy_idc)[ s{j} ] ]
 |  |  |  |  | j += 1
 |  |  |  |  \_
 |  |  | ELIF [ (sy_has)[ "@<^?*#!$-" | s{j} ] ]
 |  |  |  | j += 1
 |  |  |  \_
 |  |  | IF [ j > i + 1 ]
 |  |  |  | (sy_emit)[ c | i | j - i | SY_TYPE ]
 |  |  |  | i = j
 |  |  |  | CONTINUE
 |  |  |  \_
 |  |  \_
 |  |
 |  | ; a number, not the end of a word
 |  | IF [ (sy_digit)[ ch ] && (i == 0 || !((sy_idc)[ s{i - 1} ])) ]
 |  |  | I32 j = i + 1
 |  |  | WHILE [ (sy_idc)[ s{j} ] || (s{j} == '.' && (sy_digit)[ s{j + 1} ]) ]
 |  |  |  | j += 1
 |  |  |  \_
 |  |  | (sy_emit)[ c | i | j - i | SY_NUMBER ]
 |  |  | i = j
 |  |  | CONTINUE
 |  |  \_
 |  |
 |  | ; a word: a keyword, a type, or a name
 |  | IF [ (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' ]
 |  |  | I32 j = i + 1
 |  |  | WHILE [ (sy_idc)[ s{j} ] ]
 |  |  |  | j += 1
 |  |  |  \_
 |  |  | I32 wl = j - i
 |  |  | I32 kind = SY_PLAIN
 |  |  | IF [ (sy_word_in)[ l.keywords | s | i | wl ] ]
 |  |  |  | kind = SY_KEYWORD
 |  |  | ELIF [ (sy_word_in)[ l.types | s | i | wl ] ]
 |  |  |  | kind = SY_TYPE
 |  |  | ELIF [ (l.flags & LF_CAPS) != 0 && (sy_capped)[ s | i | wl ] ]
 |  |  |  | kind = SY_TYPE
 |  |  |  \_
 |  |  | (sy_emit)[ c | i | wl | kind ]
 |  |  | i = j
 |  |  | IF [ (l.flags & LF_PLUM) != 0 && (sy_word_in)[ " USE USES " | s | i - wl | wl ] ]
 |  |  |  | i = (sy_angle)[ c | j ]
 |  |  |  \_
 |  |  | CONTINUE
 |  |  \_
 |  |
 |  | (sy_emit)[ c | i | 1 | SY_PLAIN ]
 |  | i += 1
 |  \_
 \_

; a line of Markdown: a heading, a fence, a quote, a rule, a list, and in the
; text `code`, *emphasis* and [links](url)
LOCAL ABYSS sy_markdown: [ @SynCtx c | @I32 state ]
 | @CONST C1 s = c.s
 | I32 len = c.len
 | I32 j = 0
 | WHILE [ s{j} == ' ' && j < 3 ]
 |  | j += 1
 |  \_
 | IF [ (sy_at)[ c | j | "```" ] || (sy_at)[ c | j | "~~~" ] ]
 |  | ?state = SELECT [ ?state == SS_FENCE | SS_NONE | SS_FENCE ]
 |  | (sy_emit)[ c | 0 | len | SY_COMMENT ]
 |  | RET []
 |  \_
 | IF [ ?state == SS_FENCE ]
 |  | (sy_emit)[ c | 0 | len | SY_STRING ]
 |  | RET []
 |  \_
 |
 | ; # Heading
 | I32 h = j
 | WHILE [ s{h} == '#' ]
 |  | h += 1
 |  \_
 | IF [ h > j && h - j <= 6 && (s{h} == ' ' || s{h} == '\0') ]
 |  | (sy_emit)[ c | 0 | len | SY_HEAD ]
 |  | RET []
 |  \_
 | IF [ s{j} == '>' ]
 |  | (sy_emit)[ c | 0 | len | SY_COMMENT ]
 |  | RET []
 |  \_
 |
 | ; --- and *** on a line of their own
 | C1 r = s{j}
 | IF [ r == '-' || r == '*' || r == '_' ]
 |  | I32 k = j
 |  | I32 marks = 0
 |  | WHILE [ s{k} == r || s{k} == ' ' ]
 |  |  | marks += SELECT [ s{k} == r | 1 | 0 ]
 |  |  | k += 1
 |  |  \_
 |  | IF [ s{k} == '\0' && marks >= 3 ]
 |  |  | (sy_emit)[ c | 0 | len | SY_COMMENT ]
 |  |  | RET []
 |  |  \_
 |  \_
 |
 | ; a list's mark: - * + or 1.
 | I32 i = 0
 | IF [ (r == '-' || r == '*' || r == '+') && s{j + 1} == ' ' ]
 |  | (sy_emit)[ c | 0 | j | SY_PLAIN ]
 |  | (sy_emit)[ c | j | 1 | SY_KEYWORD ]
 |  | i = j + 1
 |  \_
 | IF [ (sy_digit)[ r ] ]
 |  | I32 k = j
 |  | WHILE [ (sy_digit)[ s{k} ] ]
 |  |  | k += 1
 |  |  \_
 |  | IF [ (s{k} == '.' || s{k} == ')') && s{k + 1} == ' ' ]
 |  |  | (sy_emit)[ c | 0 | j | SY_PLAIN ]
 |  |  | (sy_emit)[ c | j | k + 1 - j | SY_KEYWORD ]
 |  |  | i = k + 1
 |  |  \_
 |  \_
 |
 | WHILE [ i < len ]
 |  | C1 ch = s{i}
 |  | IF [ ch == '\\' && i + 1 < len ]
 |  |  | (sy_emit)[ c | i | 2 | SY_PLAIN ]
 |  |  | i += 2
 |  |  | CONTINUE
 |  |  \_
 |  | IF [ ch == '`' ]
 |  |  | I32 e = (sy_find)[ c | i + 1 | "`" ]
 |  |  | IF [ e > 0 ]
 |  |  |  | (sy_emit)[ c | i | e + 1 - i | SY_STRING ]
 |  |  |  | i = e + 1
 |  |  |  | CONTINUE
 |  |  |  \_
 |  |  \_
 |  | IF [ (ch == '*' || ch == '_') && (i == 0 || s{i - 1} == ' ' || ch == '*') ]
 |  |  | ; the run of marks, and the same run closing it
 |  |  | I32 run = SELECT [ s{i + 1} == ch | 2 | 1 ]
 |  |  | IF [ s{i + run} != ' ' && s{i + run} != '\0' ]
 |  |  |  | I32 e = i + run
 |  |  |  | WHILE [ e < len && !(s{e} == ch && s{e - 1} != ' ' && (run == 1 || s{e + 1} == ch)) ]
 |  |  |  |  | e += 1
 |  |  |  |  \_
 |  |  |  | IF [ e < len ]
 |  |  |  |  | (sy_emit)[ c | i | e + run - i | SY_TYPE ]
 |  |  |  |  | i = e + run
 |  |  |  |  | CONTINUE
 |  |  |  |  \_
 |  |  |  \_
 |  |  \_
 |  | IF [ ch == '[' ]
 |  |  | I32 e = (sy_find)[ c | i + 1 | "](" ]
 |  |  | I32 f = SELECT [ e < 0 | -1 | (sy_find)[ c | e | ")" ] ]
 |  |  | IF [ e > 0 && f > 0 ]
 |  |  |  | (sy_emit)[ c | i | e + 1 - i | SY_KEYWORD ]
 |  |  |  | (sy_emit)[ c | e + 1 | f + 1 - e - 1 | SY_COMMENT ]
 |  |  |  | i = f + 1
 |  |  |  | CONTINUE
 |  |  |  \_
 |  |  \_
 |  | (sy_emit)[ c | i | 1 | SY_PLAIN ]
 |  | i += 1
 |  \_
 \_

; a line of a diff: + added, - removed, @@ a hunk, the rest the file lines
LOCAL ABYSS sy_diff: [ @SynCtx c ]
 | @CONST C1 s = c.s
 | I32 len = c.len
 | I32 kind = SY_PLAIN
 | IF [ (sy_at)[ c | 0 | "+++ " ] || (sy_at)[ c | 0 | "--- " ] || (sy_at)[ c | 0 | "diff " ] || (sy_at)[ c | 0 | "index " ] || (sy_at)[ c | 0 | "new file" ] || (sy_at)[ c | 0 | "deleted file" ] || (sy_at)[ c | 0 | "rename " ] || (sy_at)[ c | 0 | "similarity " ] ]
 |  | kind = SY_PREPROC
 | ELIF [ (sy_at)[ c | 0 | "@@" ] ]
 |  | I32 e = (sy_find)[ c | 2 | "@@" ]
 |  | IF [ e > 0 ]
 |  |  | (sy_emit)[ c | 0 | e + 2 | SY_KEYWORD ]
 |  |  | (sy_emit)[ c | e + 2 | len - e - 2 | SY_PLAIN ]
 |  |  | RET []
 |  |  \_
 |  | kind = SY_KEYWORD
 | ELIF [ s{0} == '+' ]
 |  | kind = SY_ADD
 | ELIF [ s{0} == '-' ]
 |  | kind = SY_DEL
 | ELIF [ s{0} == '\\' ]
 |  | kind = SY_COMMENT
 |  \_
 | (sy_emit)[ c | 0 | len | kind ]
 \_

; the line `s` cut into spans, at most `cap` of them, filled in `sp` and
; counted by the result. They follow one another and cover the whole line.
; `?state` is what the line before left, and what this one leaves
I32 syntax_line: [ @Lang l | @CONST C1 s | @I32 state | @SynSpan sp | I32 cap ]
 | SynCtx c = [ .l = l | .s = s | .len = (str_len)[ s ] AS I32 | .sp = sp | .cap = cap | .n = 0 ]
 | IF [ l.mode == LM_MD ]
 |  | (sy_markdown)[ @c | state ]
 | ELIF [ l.mode == LM_DIFF ]
 |  | (sy_diff)[ @c ]
 | ELSE
 |  | (sy_code)[ @c | state ]
 |  \_
 | RET [ c.n ]
 \_
