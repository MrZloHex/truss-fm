
USE <modular.pl>
!USES <app.pl>
!USES <look.pl>

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

; a table like this has to stay on one line: plc rejects it split across lines
CONST Place PLACES{} = [ [ .kind = PK_HEAD | .name = "PLACES" | .key = "" ] |
                         [ .kind = PK_PLACE | .name = "~ home" | .key = "h" ] |
                         [ .kind = PK_PLACE | .name = "work" | .key = "w" ] |
                         [ .kind = PK_GAP | .name = "" | .key = "" ] |
                         [ .kind = PK_HEAD | .name = "DEVICES" | .key = "" ] |
                         [ .kind = PK_PLACE | .name = "nvme0 /" | .key = "" ] ]
CONST I32 NPLACES = COUNT [ PLACES ]

TYPE PlacesPane: STRUCT
 | ListState list
 | I32 active         ; the place that is open
 \_

ABYSS place_skip: [ @ListState l | I32 was ]
 | I32 dir = SELECT [ l.cursor < was | -1 | 1 ]
 | WHILE [ l.cursor >= 0 && l.cursor < NPLACES && PLACES{l.cursor}.kind != PK_PLACE ]
 |  | l.cursor += dir
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
 | (ui.box)[ "" | (pct)[15] | GROW ]
 | (ui.list)[ @(p.list) | id | NPLACES | GROW | GROW ]
 | (place_skip)[ @(p.list) | was ]
 | IF [ (ui.focused)[ id ] && (ui.take)[ KEY_ENTER ] ]
 |  | p.active = p.list.cursor
 |  \_
 | FOR [ I32 i = 0 | i < NPLACES | i += 1 ]
 |  | @CONST Place r = @(PLACES{i})
 |  | IF [ r.kind != PK_PLACE ]
 |  |  | (ui.text)[ GROW | 1 ]
 |  |  | (ui.put)[ (fg)[ DIM ] | r.name ]
 |  |  | CONTINUE
 |  |  \_
 |  | (ui.list_row)[ @(p.list) | i | id ]
 |  | (ui.put_cell)[ (fg)[ SELECT [ i == p.active | AMBER | TEXT ] ] | r.name | 16 | TRUE ]
 |  | (ui.put)[ (fg)[ DIM ] | r.key ]
 |  \_
 | (ui.close)[]
 | (ui.end)[]
 \_



ABYSS preview_pane: [ @Ui ui | @App a ]
 | (ui.box)[ "Preview" | (pct)[20] | GROW ]
 | 
 | (ui.close)[]
 \_
