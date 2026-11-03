; places.pl -- the first column: places to go to, under headings. The cursor
; steps over the headings and the gaps; Enter opens a place

USE <std/core/core.pl>

USE <modular.pl>
!USES <../look.pl>

CONST I32 PLACES_W_PERC = 15
CONST I32 PLACE_NAME_W = 16     ; the name; its key after it

TYPE PlaceKind: ENUM
 | PK_PLACE
 | PK_HEAD
 | PK_GAP
 \_

TYPE Place: STRUCT
 | PlaceKind kind
 | @CONST C1 name
 | @CONST C1 key
 \_

CONST Place PLACES{} = [ [ .kind = PK_HEAD  | .name = "PLACES"  | .key = ""  ] |
                         [ .kind = PK_PLACE | .name = "~ home"  | .key = "h" ] |
                         [ .kind = PK_PLACE | .name = "work"    | .key = "w" ] |
                         [ .kind = PK_GAP   | .name = ""        | .key = ""  ] |
                         [ .kind = PK_HEAD  | .name = "DEVICES" | .key = ""  ] |
                         [ .kind = PK_PLACE | .name = "nvme0 /" | .key = ""  ] ]
CONST I32 NPLACES = COUNT [ PLACES ]

TYPE PlacesPane: STRUCT
 | ListState list
 | I32 active               ; the place that is open
 \_

; a cursor that came onto a heading or a gap goes on the way it came, and
; back to where it `was` if there is no place that way
ABYSS place_skip: [ @ListState l | I32 was ]
 | I32 step = SELECT [ l.cursor < was | -1 | 1 ]
 | WHILE [ l.cursor >= 0 && l.cursor < NPLACES && PLACES{l.cursor}.kind != PK_PLACE ]
 |  | l.cursor += step
 |  \_
 | IF [ l.cursor < 0 || l.cursor >= NPLACES ]
 |  | l.cursor = was
 |  \_
 \_

ABYSS places_pane: [ @Ui ui | @PlacesPane p ]
 | U32 id = (ui.id)[ "places" ]
 | I32 was = p.list.cursor
 | IF [ (ui.focused)[ id ] ]
 |  | IF [ (ui.take)[ 'j' AS U32 ] ]
 |  |  | p.list.cursor += 1
 |  | ELIF [ (ui.take)[ 'k' AS U32 ] ]
 |  |  | p.list.cursor -= 1
 |  |  \_
 |  \_
 |
 | (ui.box)[ "" | (pct)[ PLACES_W_PERC ] | GROW ]
 | (ui.list)[ @(p.list) | id | NPLACES | GROW | GROW ]
 | (place_skip)[ @(p.list) | was ]
 | IF [ (ui.focused)[ id ] && (ui.take)[ KEY_ENTER ] ]
 |  | p.active = p.list.cursor
 |  \_
 |
 | FOR [ I32 i = 0 | i < NPLACES | i += 1 ]
 |  | @CONST Place r = @(PLACES{i})
 |  | IF [ r.kind == PK_PLACE ]
 |  |  | (ui.list_row)[ @(p.list) | i | id ]
 |  |  | (ui.put_cell)[ (fg)[ SELECT [ i == p.active | AMBER | TEXT ] ] | r.name | PLACE_NAME_W | TRUE ]
 |  |  | (ui.put)[ (fg)[ DIM ] | r.key ]
 |  | ELSE
 |  |  | (ui.text)[ GROW | 1 ]
 |  |  | (ui.put)[ (fg)[ DIM ] | r.name ]
 |  |  \_
 |  \_
 | (ui.end)[]
 | (ui.close)[]
 \_
