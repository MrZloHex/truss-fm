; git.pl -- what git says of the folder being shown: one job asks, and when
; it is done the changes are kept as a mark for the first part of each path
; under the folder (a file's own, a folder's the worst of what is in it).
; No UI here. Not a repository, no git, or `git = false`: no marks

USE <std/core/core.pl>
USE <std/core/str.pl>
USE <std/core/sort.pl>
USE <std/alloc/string.pl>
USE <std/alloc/vector.pl>
USE <std/io/io.pl>
USE <std/os/os.pl>

!USES <config.pl>
!USES <job.pl>

CONST USIZE GIT_LIMIT = 4194304         ; what is kept of its answer

; line 1 the folder's path in the work tree, line 2 the branch (empty when
; it is detached), then status's entries, each ended by a NUL. Its errors
; are not wanted, and it takes no lock the index could be left with
CONST @CONST C1 GIT_SCRIPT = "git rev-parse --show-toplevel >/dev/null 2>&1 || exit 1\ngit rev-parse --show-prefix 2>/dev/null\ngit symbolic-ref --short -q HEAD 2>/dev/null || echo\ngit --no-optional-locks status --porcelain=v1 -z --untracked-files=normal --ignored=no . 2>/dev/null"

TYPE GitMark: STRUCT
 | String name              ; the first part of a path below the folder
 | C1 mark                  ; U conflict, M changed, + staged, ? new
 \_

TYPE GitInfo: STRUCT
 | Job job
 | B1 asking                ; the job is at work
 | B1 on                    ; the folder is in a work tree: `marks` hold
 | String branch
 | Vector<GitMark> marks    ; sorted by name; a name may come more than once
 \_

; how bad a mark is; a folder shows the worst
I32 git_rank: [ C1 m ]
 | IF [ m == 'U' ]
 |  | RET [ 4 ]
 |  \_
 | IF [ m == 'M' ]
 |  | RET [ 3 ]
 |  \_
 | IF [ m == '+' ]
 |  | RET [ 2 ]
 |  \_
 | RET [ SELECT [ m == '?' | 1 | 0 ] ]
 \_

; the mark of the two status letters, \0 for none
C1 git_code: [ C1 x | C1 y ]
 | IF [ x == '?' ]
 |  | RET [ '?' ]
 |  \_
 | IF [ x == '!' ]
 |  | RET [ '\0' ]
 |  \_
 | IF [ x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D') ]
 |  | RET [ 'U' ]
 |  \_
 | IF [ y != ' ' ]
 |  | RET [ 'M' ]
 |  \_
 | RET [ SELECT [ x != ' ' | '+' | '\0' ] ]
 \_

B1 git_before: [ @CONST GitMark a | @CONST GitMark b ]
 | RET [ (str_cmp)[ (a.name.cstr)[] | (b.name.cstr)[] ] < 0 ]
 \_

; what was learned let go
ABYSS git_forget: [ @GitInfo g ]
 | FOR [ USIZE i = 0 | i < (g.marks.size)[] | i += 1 ]
 |  | ((g.marks.at)[i].name.deinit)[]
 |  \_
 | (g.marks.clear)[]
 | g.on = FALSE
 | (g.branch.deinit)[]
 | g.branch = (String.of)[ "" ]
 \_

ABYSS git_free: [ @GitInfo g ]
 | (job_stop)[ @(g.job) ]
 | (git_forget)[ g ]
 | (g.job.out.deinit)[]
 | (g.marks.deinit)[]
 | (g.branch.deinit)[]
 \_

; the folder `dir` asked about. A new folder (`keep` FALSE) loses the old
; marks at once; the same one read again keeps them until the answer comes
ABYSS git_ask: [ @GitInfo g | @CONST C1 dir | B1 keep ]
 | (job_stop)[ @(g.job) ]
 | g.asking = FALSE
 | IF [ !keep || !(CFG.git) ]
 |  | (git_forget)[ g ]
 |  \_
 | IF [ CFG.git ]
 |  | g.asking = (job_start_in)[ @(g.job) | GIT_SCRIPT | dir | "" | GIT_LIMIT ]
 |  \_
 \_

; the answer, taken in. A job that failed is no repository
ABYSS git_take: [ @GitInfo g ]
 | (git_forget)[ g ]
 | @CONST C1 s = (g.job.out.cstr)[]
 | USIZE n = (g.job.out.size)[]
 | IF [ !(g.job.ok) || n == 0 ]
 |  | RET []
 |  \_
 | ; the prefix, then the branch
 | USIZE i = 0
 | WHILE [ i < n && s{i} != '\n' ]
 |  | i += 1
 |  \_
 | USIZE pre = i
 | i += 1
 | USIZE b0 = SELECT [ i < n | i | n ]
 | i = b0
 | WHILE [ i < n && s{i} != '\n' ]
 |  | i += 1
 |  \_
 | (g.branch.append_n)[ s + b0 | i - b0 ]
 | i += 1
 | g.on = TRUE
 |
 | WHILE [ i + 3 < n ]
 |  | C1 x = s{i}
 |  | C1 y = s{i + 1}
 |  | USIZE p0 = i + 3
 |  | USIZE e = p0
 |  | WHILE [ e < n && s{e} != '\0' ]
 |  |  | e += 1
 |  |  \_
 |  | ; cut short by the limit: that entry is not whole
 |  | IF [ e >= n ]
 |  |  | BREAK
 |  |  \_
 |  | i = e + 1
 |  | ; a rename or a copy has its old path after it
 |  | IF [ x == 'R' || x == 'C' || y == 'R' || y == 'C' ]
 |  |  | WHILE [ i < n && s{i} != '\0' ]
 |  |  |  | i += 1
 |  |  |  \_
 |  |  | i += 1
 |  |  \_
 |  | C1 mark = (git_code)[ x | y ]
 |  | ; only what lies under the folder, by the first part of its path
 |  | B1 under = mark != '\0' && e - p0 > pre
 |  | FOR [ USIZE k = 0 | under && k < pre | k += 1 ]
 |  |  | under = s{p0 + k} == s{k}
 |  |  \_
 |  | IF [ under ]
 |  |  | USIZE c = p0 + pre
 |  |  | WHILE [ c < e && s{c} != '/' ]
 |  |  |  | c += 1
 |  |  |  \_
 |  |  | GitMark m
 |  |  | m.name = (String.of)[ "" ]
 |  |  | (m.name.append_n)[ s + p0 + pre | c - p0 - pre ]
 |  |  | m.mark = mark
 |  |  | (g.marks.push)[ m ]
 |  |  \_
 |  \_
 | (sort_by<GitMark>)[ g.marks.data | (g.marks.size)[] | git_before ]
 \_

; the job's answer, if it is done. TRUE: the marks are new
B1 git_pump: [ @GitInfo g ]
 | IF [ !(g.asking) || !((job_pump)[ @(g.job) ]) ]
 |  | RET [ FALSE ]
 |  \_
 | g.asking = FALSE
 | (git_take)[ g ]
 | (job_stop)[ @(g.job) ]
 | RET [ TRUE ]
 \_

; the mark of the entry called `name` in the folder; \0 for none
C1 git_mark_of: [ @GitInfo g | @CONST C1 name ]
 | IF [ !(g.on) ]
 |  | RET [ '\0' ]
 |  \_
 | USIZE lo = 0
 | USIZE hi = (g.marks.size)[]
 | WHILE [ lo < hi ]
 |  | USIZE mid = (lo + hi) / 2
 |  | IF [ (str_cmp)[ ((g.marks.at)[mid].name.cstr)[] | name ] < 0 ]
 |  |  | lo = mid + 1
 |  | ELSE
 |  |  | hi = mid
 |  |  \_
 |  \_
 | C1 best = '\0'
 | WHILE [ lo < (g.marks.size)[] && (str_eq)[ ((g.marks.at)[lo].name.cstr)[] | name ] ]
 |  | C1 m = (g.marks.at)[lo].mark
 |  | IF [ (git_rank)[ m ] > (git_rank)[ best ] ]
 |  |  | best = m
 |  |  \_
 |  | lo += 1
 |  \_
 | RET [ best ]
 \_
