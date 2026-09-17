--[[ Equadis' Classic Overhaul :: waypoints

  **A coordinate you can point at, an arrow that keeps pointing, and a list of
  the ones worth keeping.**

  Written from scratch rather than ported. TomTom is the obvious source and
  upstream is openly distributed, but the 1.12 backport everybody actually runs
  -- `laytya/TomTom-TWOW` -- ships no licence of its own: no LICENSE file, and
  nothing in its TOC, its README or any of its three source files. Its *bundled*
  libraries do carry theirs, so the packager knew to include them. That is a gap
  rather than a grant.

  The engineering pointed the same way regardless. TomTom-TWOW is built on Ace2,
  Astrolabe and Waterfall, none of which this addon uses, so a port would mean
  adopting three dependency trees to gain one arrow. What is used here is its
  *behaviour* -- which is not anybody's to license -- and two hard-won facts
  about the client that are worth writing down:

  **There is no `GetPlayerFacing` on 1.12.** The player's facing is readable
  only off the minimap's own rotating model, which is the ninth child of
  `Minimap` and has no name. It answers `GetFacing()` in radians.

  **That child must be found once and kept.** TomTom-TWOW rebuilds
  `{Minimap:GetChildren()}` on every arrow refresh -- a whole table of frames
  allocated sixty times a second -- and the addon `TomTomPerfFix` exists purely
  to cache it. On 1.12 that cost is not CPU, it is garbage, and it is paid later
  as the collection pause people call lag. This module caches it from the start.

  **The arrow art is Guillotine's, and is licensed.** The addon around it is
  not -- that part of the note above still stands -- but `Images/ArrowLicense.txt`
  in that repository grants everyone "full permission to do whatever they want
  with this model file in any non-commercial manner", asking only that
  attribution is "nice, but not necessary". So the sheet is used here as
  `textures/waypoint-arrow.blp`, the grant travels with it as
  `textures/waypoint-arrow-LICENSE.txt`, and the attribution it says is optional
  is given anyway: **the arrow was drawn by Guillotine.**

  **A sheet, because 1.12 cannot rotate a texture.** There is no `SetRotation`
  on this client. The file is 512x512 holding a 9 by 12 grid of the same arrow
  drawn at 108 evenly spaced angles, so rotating it means picking the cell whose
  angle is closest and pointing `SetTexCoord` at it. That is a fifteenth of a
  degree of quantisation, which is not visible, and it costs four numbers.

  An earlier version of this file built a `Model` frame for the arrow on the
  reasoning that models take `SetFacing` and textures do not. It never called
  `SetModel`, so there was nothing in the frame to face: the arrow did not
  render at all. Models are also the wrong tool here -- they cost a 3D draw for
  a flat sprite, and their lighting does not match the rest of the interface.

  **What is deliberately not here: distance in yards.** Converting a map
  coordinate to a distance needs the zone's real dimensions, which is what
  Astrolabe is for and what a table of every zone's size would otherwise have to
  supply. Direction needs neither and is exact, so the arrow is exact; the
  readout says how far through the zone you are rather than inventing a number.
]]--

local OB = EquadisClassicOverhaul
--[[ `abs` is a global on this client and is not one in plain Lua, so the
     harness would find nothing there. Taken from `math` like the rest. ]]--
local floor, format, sqrt, atan2 = math.floor, string.format, math.sqrt, math.atan2
local abs = math.abs

--[[ The client's own name for the remainder -- 5.1 renamed it `fmod`, and a
     1.12 client has no such function. Localised because this is read on every
     frame an arrow is up. ]]--
local mod = mod
local pi = math.pi

local function Say(msg) OB.Print(msg, "Waypoints") end

--[==[ **How close counts as arrived -- in yards where they are known, and in
     map fractions where they are not.**

     A zone coordinate runs 0 to 1 across the whole zone, so a hundredth of it is
     a few paces in a city and a short walk in Tanaris. That was defended as the
     right shape -- "arrived should mean the same thing relative to the place you
     are in" -- and it is wrong: arriving is a fact about how far you have to
     walk, and a yard is a yard in both places. The fraction was the only measure
     available before the zone calibration, and it is the fallback now rather
     than the rule.

     Asked for as a setting, which it should always have been: a herb node wants
     to clear at five yards and a flight master at thirty. ]==]
local ARRIVE_AT = 0.01
local ARRIVE_YARDS_MIN, ARRIVE_YARDS_MAX = 3, 100

--[[ The arrow sheet: 9 across, 12 down, 108 angles, cell zero pointing straight
     up and the rest going clockwise. Named rather than spelled inline because
     the same three numbers are needed twice and a sheet with a different grid
     would otherwise have to be found in two places. ]]--
local ARROW_TEXTURE = OB.mediaPath .. "textures\\waypoint-arrow"
local ARROW_COLUMNS, ARROW_ROWS = 9, 12
local ARROW_CELLS = ARROW_COLUMNS * ARROW_ROWS

--[==[ **The grid does not fill the sheet, and assuming it did is what put bits
     of the neighbouring arrows around the edges.**

     The file is 512x512 and the cells are 56 wide by 42 tall, so the grid covers
     504x504 and leaves eight pixels of margin on two sides. Dividing the sheet
     into ninths and twelfths instead makes every cell about a pixel too wide and
     three quarters of a pixel too tall -- and the error accumulates across the
     grid, so the last column is sampling seven pixels into its neighbour. That
     is exactly the reported "extra arrow parts around the edges", worst at the
     far columns and rows, which is the signature of an accumulating offset
     rather than a filtering artefact.

     Not guessed: this artwork is TomTom-TWOW's `Arrow.blp`, byte for byte, and
     56 and 42 are the numbers its own arrow uses on it. ]==]
local ARROW_CELL_W, ARROW_CELL_H = 56, 42
local ARROW_SHEET = 512

--[==[ **The arrival animation, and the sheet it comes from was already here.**

     TomTom swaps the arrow for a second sheet when you get close and runs
     through it -- the bouncing arrow pointing down at the spot, which is what
     tells you that you have got there rather than that you are still going.
     Asked for by name, as the thing missing from ours.

     `waypoint-arrow-up.blp` is TomTom's `Arrow-UP.blp`, byte for byte, and this
     addon has been shipping it unreferenced: 350 kB of art nothing drew, flagged
     in the queue as "delete it or use it". This uses it.

     Fifty-five frames, nine to a row, cells of 53 by 70 on the same 512 sheet --
     TomTom's own numbers on TomTom's own file, the way the directional cells
     were settled.

     **It starts five yards before the waypoint clears**, which is TomTom's gap
     too (`arrivaldistance = cleardistance + 5`). Without it the animation would
     be unreachable by default: arriving is what deletes the waypoint, so an
     effect that began exactly there would play for no frames at all. ]==]
local ARROW_UP_TEXTURE = OB.mediaPath .. "textures\\waypoint-arrow-up"
local ARROW_UP_CELL_W, ARROW_UP_CELL_H = 53, 70
local ARROW_UP_COLUMNS, ARROW_UP_FRAMES = 9, 55
local ARROW_UP_MARGIN = 5
local ARROW_UP_RATE = 1 / 30

local function arrowUpCell(frameIndex)
    local cell = mod(floor(frameIndex or 0), ARROW_UP_FRAMES)

    local column = mod(cell, ARROW_UP_COLUMNS)
    local row = floor(cell / ARROW_UP_COLUMNS)

    return (column * ARROW_UP_CELL_W) / ARROW_SHEET,
           ((column + 1) * ARROW_UP_CELL_W) / ARROW_SHEET,
           (row * ARROW_UP_CELL_H) / ARROW_SHEET,
           ((row + 1) * ARROW_UP_CELL_H) / ARROW_SHEET
end

--[[ Which cell shows an angle. Rounded to nearest rather than floored: flooring
     biases every heading one cell anticlockwise, which is a visible lean at
     small angles and was the first thing to look wrong when this was written
     the obvious way. ]]--
local function arrowCell(angle)
    local twopi = 2 * pi

    while angle < 0 do angle = angle + twopi end
    while angle >= twopi do angle = angle - twopi end

    local cell = floor((angle / twopi * ARROW_CELLS) + 0.5)
    if cell >= ARROW_CELLS then cell = 0 end

    local column = mod(cell, ARROW_COLUMNS)
    local row = floor(cell / ARROW_COLUMNS)

    return (column * ARROW_CELL_W) / ARROW_SHEET,
           ((column + 1) * ARROW_CELL_W) / ARROW_SHEET,
           (row * ARROW_CELL_H) / ARROW_SHEET,
           ((row + 1) * ARROW_CELL_H) / ARROW_SHEET
end

--[==[ **The two ways the arrow can be coloured**, as a list rather than a
     boolean, so each scheme's colours can sit under the scheme that uses them.

     One flat colour first, because it is the simpler statement and the one
     somebody picks when they want the arrow to stop changing under them. ]==]
local ARROW_COLOR_SOLID, ARROW_COLOR_FACING = 1, 2

local ARROW_COLOR_MODES = OB.Enum(
        { ARROW_COLOR_SOLID, ARROW_COLOR_FACING },
        { "Solid Color", "Color By Direction" })

OB.predicates = OB.predicates or {}

local function colorMode()
    local cfg = OB.profile and OB.profile.modules
            and OB.profile.modules.waypoints

    return (cfg and tonumber(cfg.arrowColorMode)) or ARROW_COLOR_FACING
end

OB.predicates.waypoint_solid_color = function()
    return colorMode() == ARROW_COLOR_SOLID
end

OB.predicates.waypoint_color_by_facing = function()
    return colorMode() == ARROW_COLOR_FACING
end

local M = OB.RegisterModule({
    id = "waypoints",
    name = "Waypoints",

    feature = true,
    renders = "none",
    --[[ The arrow draws its name and distance as text. No bar, no border, and
         `nameSize` is its own. See `OB.LookOptions`. ]]--
    styled = { font = true, fontOutline = true },

    --[==[ **The shared Appearance rows belong on one page.**

         The panel shell appends them to whichever tab is open unless a module
         says otherwise, so Bar Texture and Font appear to be settings about
         whatever you happen to be looking at. `appearanceSection` is the answer
         and had been in `options.lua` all along with nothing setting it. ]==]
    appearanceSection = "general",

    --[==[ **On, like everything else.**

         This module shipped off. So did twelve others, which meant a fresh
         install of this addon did very nearly nothing until somebody went
         through the Modules page switching things on -- and nothing on screen
         said that was the step they were missing. It was reported as settings
         not carrying across to a new character, which is what an addon that is
         installed and not running looks like from outside.

         The flag exists for a feature that is not finished, where drawing
         nothing is indistinguishable from being broken. None of the thirteen
         were that; they were caution, and the setup walkthrough is where that
         caution belongs now -- it goes through every module in turn and offers
         exactly this switch, with a description of what the module does. A
         decision somebody is walked through is better than a default they never
         find. ]==]

    defaults = {
        --[==[ **Control-click the world map to drop a waypoint there.**

             On, because it is otherwise the only feature here you cannot reach
             without first reading a pair of numbers off the map and typing
             them back in. A held modifier rather than a mode, so the map is
             still a map the rest of the time. ]==]
        mapClick = true,

        --[==[ **Which button, because a right-click is not a free gesture.**

             Reported: control-right-clicking the map to place a waypoint
             interrupts a cast. Nothing in this module can do that -- it calls no
             spell function, does not move the player and casts nothing; the path
             is `MapClick` to `Add` to `ApplyArrow` and `ApplyMapPin`. What is
             left is the gesture, and a right-click is something the client acts
             on whether or not this addon claims it.

             A left click on the map is inert, which is the reasoning the "either
             button" note already gives for accepting it. That reasoning does not
             carry to the right button, and the difference had never been offered
             as a choice.

             **`either` is the default, so nothing changes for anybody**, and
             somebody who casts with the map open can take the right button out
             of it. ]==]
        mapClickButton = "either",

        --[==[ **A waypoint where you died, dropped for you.**

             Asked for, and it is the one waypoint nobody can set at the moment
             they need it: you are looking at a release button, not a map, and by
             the time you are a ghost you are somewhere else. The client draws a
             corpse marker on the map already and gives you no arrow to it, which
             is the half this fills.

             On, because it costs nothing until you die and it is the only
             feature here that cannot be used after the fact. Cleared when you
             are back on your feet, so it never outlives the run it was for. ]==]
        corpseWaypoint = true,

        --[[ The arrow. On when the module is, because an arrow is the whole
             point of a waypoint -- a list with nothing pointing at it is a
             notepad. ]]--
        arrow = true,
        arrowSize = 42,
        arrowX = 0,
        arrowY = 140,

        --[[ **Coloured by whether you are walking towards it.** The arrow's
             angle already says which way; the colour says whether you are
             going that way, which is the thing you read at a glance while
             moving. ]]--
        --[==[ **One choice of two schemes rather than a switch and an
             orphan.**

             `colorByFacing` was a boolean with the two directional colours under
             it, and switching it off left the arrow white with no way to say
             what colour it should be instead. So the off state had a setting
             missing from it, and the panel gave no hint that was the trade.

             A list names both schemes and puts each one's colours under it, so
             every state has its controls and neither is the absence of the
             other. `colorByFacing` is migrated into it; schema 41. ]==]
        arrowColorMode = 2,
        arrowColor = { 1, 1, 1, 1 },
        onCourseColor = { 0.2, 1, 0.2, 1 },
        offCourseColor = { 1, 0.4, 0.2, 1 },

        showName = true,
        showDistance = true,
        nameSize = 12,

        --[[ Cleared on arrival, which is what TomTom does and what everybody
             expects: a waypoint you have reached is a waypoint you are finished
             with. Off for anybody marking a place to come back to. ]]--
        --[[ Ten, which is TomTom's, and close enough that you are standing on
             the thing rather than near it. ]]--
        --[[ The mark on the minimap as well as on the world map. On, because
             the minimap is the one you are actually looking at while walking,
             and the arrow says which way without saying how far round. ]]--
        minimapPin = true,

        arriveYards = 10,

        clearOnArrival = true,
        announceArrival = true,
    },

    options = {
        { "The Arrow", "__s_arrow", "section", "arrow" },

        { "Show The Arrow", "arrow", "boolean" },
        { "Arrow Size", "arrowSize", "slider", 20, 96, 2, nil, nil, "!arrow" },

        --[[ The scheme, then only the colours that scheme uses. Hidden rather
             than dimmed: an On Course colour means nothing at all while the
             arrow is one flat colour, which is `dependsOn`'s case rather than
             `greyWhen`'s. ]]--
        { "Color", "arrowColorMode", ARROW_COLOR_MODES, 150,
          nil, nil, nil, nil, "!arrow" },

        { "Solid Color", "arrowColor", "color", true,
          nil, nil, nil, "@waypoint_solid_color", "!arrow" },

        { "On Course", "onCourseColor", "color", true,
          nil, nil, nil, "@waypoint_color_by_facing", "!arrow" },
        { "Off Course", "offCourseColor", "color", true,
          nil, nil, nil, "@waypoint_color_by_facing", "!arrow" },

        { "Show Waypoint Name", "showName", "boolean",
          nil, nil, nil, nil, nil, "!arrow" },
        { "Show Remaining Distance", "showDistance", "boolean",
          nil, nil, nil, nil, nil, "!arrow" },
        { "Text Size", "nameSize", "slider", 8, 20, 1, nil, nil, "!arrow" },

        { "General", "__s_general", "section", "general" },

        { "Control-Click The Map To Set One", "mapClick", "boolean" },

        --[[ Hidden rather than greyed when the click is off entirely: which
             button does a thing that does not happen is not a question with an
             answer. ]]--
        { "Which Button Sets One", "mapClickButton",
          OB.Enum({ "either", "left", "right" },
                  { "Either Button", "Left Only", "Right Only" }),
          nil, nil, nil, nil, "mapClick" },
        { "Show It On The Minimap", "minimapPin", "boolean" },
        { "Mark Where You Died", "corpseWaypoint", "boolean" },

        { "Arriving", "__s_arrive", "section", "arrive" },

        { "Arrive Within (Yards)", "arriveYards", "slider",
          ARRIVE_YARDS_MIN, ARRIVE_YARDS_MAX, 1 },

        { "Say So On Arrival", "announceArrival", "boolean" },
        { "Clear It On Arrival", "clearOnArrival", "boolean" },

        { "Clear Every Waypoint", "__a_clear", "action",
          function() OB.modules.waypoints:ClearAll() end,
          function() return "Clear Every Waypoint" end },
    },

    events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
               "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" },

    requires = { "GetPlayerMapPosition", "SetMapToCurrentZone",
                 "GetRealZoneText" },

    tickly = true,
})

function M:Config()
    return OB.profile.modules.waypoints
end

-- ---------------------------------------------------------------------------
-- where the player is
-- ---------------------------------------------------------------------------

--[==[ **`GetPlayerMapPosition` answers against whichever map is currently
     open**, not against the zone you are standing in -- so browsing to another
     continent silently changes what "where am I" returns.

     This used to answer that by calling `SetMapToCurrentZone()` first, **every
     tick**, and the note here claimed it was a no-op when the map already showed
     the current zone. It is not a no-op when somebody has just navigated away on
     purpose, which is the only reason the world map has navigation. Right-click
     to zoom out to the continent and a tenth of a second later this dragged the
     map back to the zone.

     Reported exactly that way: "cannot right click on world map to zoom out, it
     zooms back in after". It was not the right-click being eaten -- the click
     worked, and this undid it.

     **So the map is left alone whenever it is open.** With it shut nobody is
     looking and putting it back costs nothing. With it open the reading is
     taken as it comes, and a reading from somebody else's continent is refused
     in favour of the last good one -- which keeps the arrow pointing while you
     browse rather than blanking it, and is honest because you have not moved.

     The third return says the answer is remembered rather than fresh. Only the
     zone calibration cares: measuring a stale position against a live world
     position would invent a scale out of nothing. ]==]
function M:PlayerPosition()
    if type(GetPlayerMapPosition) ~= "function" then return nil end

    local world = getglobal("WorldMapFrame")
    local browsing = world and world.IsShown and world:IsShown()

    if not browsing and type(SetMapToCurrentZone) == "function" then
        SetMapToCurrentZone()
    end

    local x, y = GetPlayerMapPosition("player")

    --[[ Both zero means the client does not know -- inside an instance, mid
         loading screen, or looking at a map the player is not standing on. ]]--
    if x and y and not (x == 0 and y == 0) then
        self.lastPosition = { x = x, y = y }
        return x, y
    end

    if browsing and self.lastPosition then
        return self.lastPosition.x, self.lastPosition.y, true
    end

    --[[ Nil rather than a corner of the map: an arrow confidently pointing at
         the top left of Azeroth is worse than no arrow. ]]--
    return nil
end

function M:Zone()
    if type(GetRealZoneText) ~= "function" then return nil end
    local zone = GetRealZoneText()
    if not zone or zone == "" then return nil end
    return zone
end

--[[ **The player's facing, which 1.12 exposes nowhere.**

     There is no `GetPlayerFacing` on this client. The only thing that knows is
     the minimap's own rotating model -- the ninth child of `Minimap`, which has
     no name and answers `GetFacing()` in radians.

     Found once and kept. TomTom-TWOW rebuilds `{Minimap:GetChildren()}` on
     every refresh, which is a table of frames allocated sixty times a second,
     and the addon `TomTomPerfFix` exists for no other reason than to cache it.
     Dropped and re-found if it ever stops answering, because a client patch
     that reorders those children should cost one lookup rather than the
     feature. ]]--
--[==[ **The ninth child first, which is the one TomTom names.**

     This searched for the first child that answered `GetFacing` at all, on the
     reasoning that only the rotating model has that method. That is true of a
     stock minimap and this addon does not leave it stock: it parents its own
     coordinate readout, its header buttons and the addon drawer onto `Minimap`,
     and anything with a model in it would be found before the one that matters.

     TomTom-TWOW takes `({Minimap:GetChildren()})[9]` and nothing else, and it
     has been right on this client for years. So that is tried first and the
     search is kept underneath it, for a build that has reordered them.

     **A facing that never changes is not this function's fault.** With the
     client set to rotate the minimap, the map turns and the model does not, so
     `GetFacing` is a constant and no addon can do better -- TomTom included.
     `/eq waydebug` prints the CVar for exactly that reason. ]==]
local FACING_CHILD = 9

local function facingOf(child)
    if not child or not child.GetFacing then return nil end

    local ok, facing = pcall(child.GetFacing, child)
    if not ok or type(facing) ~= "number" then return nil end

    return facing
end

function M:Facing()
    if self.facingFrame then
        local facing = facingOf(self.facingFrame)
        if facing then return facing end
        self.facingFrame = nil
    end

    if not Minimap or not Minimap.GetChildren then return nil end

    local children = { Minimap:GetChildren() }

    --[[ The named one, then anything that answers. ]]--
    local named = children[FACING_CHILD]

    if facingOf(named) then
        self.facingFrame = named
        return facingOf(named)
    end

    for i = 1, table.getn(children) do
        local child = children[i]

        if facingOf(child) then
            self.facingFrame = child
            return facingOf(child)
        end
    end

    return nil
end

--[==[ **What the arrow knows, said out loud.**

     Three of the reported faults -- the arrow not turning, the yards being
     wrong, and how this compares to TomTom -- are all questions about inputs
     this addon cannot see from here. Each has more than one cause and they look
     identical on screen:

     *Not turning* is either no facing source at all, or a source that answers
     the same number every time. Printing it twice a second apart tells the two
     apart in one line.

     *Wrong yards* is either a zone never calibrated -- which needs
     `UnitPosition`, so a client without SuperWoW never learns one -- or a zone
     calibrated on one axis and borrowing it for the other.

     Everything here is read, nothing is set. ]==]
function M:Debug()
    local function say(msg) OB.Print(msg, "Waypoints") end

    say("--- waypoints ---")

    local zone = self:Zone()
    say("zone: " .. tostring(zone))

    --[[ The facing, and whether it is the same answer as a moment ago. A
         constant is what a rotating minimap gives, and reads as a dead arrow. ]]--
    local facing = self:Facing()
    say("facing: " .. tostring(facing)
            .. "   source found: " .. tostring(self.facingFrame ~= nil))

    if self.lastDebugFacing then
        local same = (facing == self.lastDebugFacing)
        say("  last time it was " .. tostring(self.lastDebugFacing)
                .. (same and "  -- UNCHANGED, so the arrow cannot turn"
                        or "  -- changed, so the source is live"))
    else
        say("  run this again after turning on the spot to see if it moves")
    end

    --[==[ **The setting that can stop the source answering -- asked for
         safely.**

         The facing comes from the minimap's own rotating model. With the client
         set to rotate the *minimap* instead, the map turns and the model does
         not, so `GetFacing` is a constant and no addon reading it can do better.
         TomTom has the identical limitation for the identical reason.

         **`GetCVar` throws on a name the client does not have** -- not nil, an
         error -- and this build has no `rotateMinimap`. So the report died on
         that line and everything below it, including the comparison this command
         exists for, never printed. That is what "Couldn't find CVar named
         'rotateMinimap'" was, and it was mine.

         Guarded, and the comparison moved above it so a fault here can never
         again cost the answer. ]==]
    self.lastDebugFacing = facing

    if type(GetCVar) == "function" then
        local ok, rotating = pcall(GetCVar, "rotateMinimap")

        if not ok or rotating == nil then
            say("  rotateMinimap: this client has no such setting, so the"
                    .. " minimap does not rotate and the facing is readable")
        else
            say("  rotateMinimap: " .. tostring(rotating)
                    .. ((rotating == "1" or rotating == 1)
                            and "  -- THIS IS WHY: the map rotates instead of"
                                    .. " the arrow, so the facing never changes."
                                    .. " Turn it off in Interface Options."
                            or ""))
        end
    end

    --[[ Position, in both the map's terms and the world's. ]]--
    local px, py = self:PlayerPosition()
    say("map position: " .. tostring(px) .. ", " .. tostring(py))

    if type(UnitPosition) ~= "function" then
        say("UnitPosition: MISSING -- no yards can ever be learned on this client")
    else
        local north, east = self:WorldPosition()
        say("world position: north " .. tostring(north)
                .. "  east " .. tostring(east))
    end

    --[[ And what has been learned about this zone, which is what the yards are
         computed from. ]]--
    local scale = self:ZoneScale()

    if not scale then
        say("zone scale: not measured yet -- walk a few seconds and ask again")
    else
        say("zone scale: x " .. tostring(scale.x) .. "  y " .. tostring(scale.y))

        if not scale.x or not scale.y then
            say("  only one axis measured, so the other borrows it --"
                    .. " a zone is wider than it is tall, so this reads long")
        end
    end

    local list = self:List(zone)
    say("waypoints here: " .. tostring(table.getn(list or {})))

    local point = self:Active()

    if point and px then
        say("active: " .. tostring(point.name)
                .. " at " .. tostring(point.x) .. ", " .. tostring(point.y))
        say("  distance: " .. tostring(self:DistanceYards(px, py, point))
                .. " yards")
    else
        say("active: none")
    end

    return true
end

-- ---------------------------------------------------------------------------
-- the waypoints themselves
-- ---------------------------------------------------------------------------

--[[ Account-wide and keyed by zone, because "the vendor is at 45, 60 in Booty
     Bay" is a fact about the world rather than a setting one character might
     disagree with. Same reasoning the roster follows. ]]--
function M:Store()
    if type(EquadisClassicOverhaulDB) ~= "table" then return nil end
    EquadisClassicOverhaulDB.waypoints = EquadisClassicOverhaulDB.waypoints or {}
    return EquadisClassicOverhaulDB.waypoints
end

function M:List(zone)
    zone = zone or self:Zone()
    if not zone then return {} end

    local store = self:Store()
    if not store then return {} end

    store[zone] = store[zone] or {}
    return store[zone]
end

--[[ Coordinates arrive as people write them -- `/way 45 60` -- which is a
     percentage. Stored as the fraction the client works in, so nothing has to
     remember which form it is holding. ]]--
function M:Add(x, y, name, zone)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return nil end

    zone = zone or self:Zone()
    if not zone then return nil end

    --[[ Out of range is a typo rather than a place. Refused rather than
         clamped: clamping `/way 450 60` to the edge of the zone would send
         somebody walking confidently in a direction nobody meant. ]]--
    if x < 0 or x > 100 or y < 0 or y > 100 then return nil end

    local list = self:List(zone)

    local point = {
        x = x / 100,
        y = y / 100,
        name = (name and name ~= "") and name or nil,
    }

    table.insert(list, point)
    self.active = point
    self.activeZone = zone
    self.arrived = nil

    --[==[ **And the arrow comes up, which is the whole point of setting one.**

         `Refresh` -- the per-tick pass -- begins `if not frame:IsShown() then
         return false end`, and only `ApplyArrow` ever shows it. Adding a
         waypoint set the active point and stopped, so the arrow stayed hidden
         and the ten-times-a-second refresh bailed on its first line, forever:
         the message went to chat, the waypoint was stored, and nothing
         appeared. A zone change happened to call `ApplyArrow` through
         `OnEvent`, which is why it could work for somebody who walked far
         enough to forget they had set one.

         Reported as exactly that -- "no arrow, still says waypoint set in
         chat". ]==]
    self:ApplyArrow()
    self:ApplyMapPin()

    return point
end

function M:Deactivate()
    self.active = nil
    self.activeZone = nil
    self.arrived = nil
    self:ApplyArrow()
    self:ApplyMapPin()
    return true
end

function M:ClearAll()
    local store = self:Store()
    if store then
        for zone in pairs(store) do store[zone] = nil end
    end

    self:Deactivate()
    Say("every waypoint cleared.")
    return true
end

--[[ The one being pointed at. Falls back to the first in the current zone, so
     walking into a zone you have marked picks the mark up without being asked
     -- which is the behaviour that makes a list worth keeping. ]]--
function M:Active()
    local zone = self:Zone()
    if not zone then return nil end

    if self.active and self.activeZone == zone then return self.active end

    local list = self:List(zone)
    if table.getn(list) == 0 then return nil end

    self.active = list[1]
    self.activeZone = zone
    self.arrived = nil
    return self.active
end

-- ---------------------------------------------------------------------------
-- pointing at it
-- ---------------------------------------------------------------------------

--[[ **The angle from the player to the waypoint, in the client's own frame of
     reference.**

     Map y grows *downwards* -- the top of the map is zero -- so the vertical
     difference is taken the other way round from what the arithmetic would
     suggest. Getting this backwards produces an arrow that is exactly right
     about east and west and exactly wrong about north and south, which reads as
     the arrow working until the first time somebody trusts it. ]]--
function M:Angle(px, py, point)
    if not px or not point then return nil end

    local dx = point.x - px
    local dy = py - point.y

    if dx == 0 and dy == 0 then return 0 end
    return atan2(dx, dy)
end

--[[ How far, as a fraction of the zone: the raw measure everything else here is
     built on. `DistanceYards` turns it into the number people actually want. ]]--
function M:Distance(px, py, point)
    if not px or not point then return nil end

    local dx = point.x - px
    local dy = point.y - py
    return sqrt((dx * dx) + (dy * dy))
end

--[==[ **Yards, measured rather than looked up.**

     "38% of the way across Un'Goro" is a true number and not the one anybody
     wants: the question is how far is left to walk. Turning a zone fraction
     into yards normally needs a table of every zone's dimensions -- Astrolabe
     carries one, and it is a large file that is wrong the day a server adds a
     zone.

     There is another source on this client. `UnitPosition` -- SuperWoW's --
     answers the player's position in world **yards**, and
     `GetPlayerMapPosition` answers the same player as a zone **fraction**. Walk
     a few steps and both change; dividing one delta by the other is how many
     yards a fraction of this zone is worth, measured on the zone somebody is
     standing in rather than assumed from a table.

     Kept per axis, because zones are not square and one scale would be wrong on
     the long side by however oblong the zone is. Each axis is updated only when
     the player has moved mostly along it -- a diagonal step says nothing about
     either on its own -- and the value is kept in the profile, so walking back
     into a zone remembers what it learned last time.

     Without SuperWoW there is no yard measure at all and the percentage stays.
     That is the honest answer rather than a guessed constant: a made-up yard is
     worse than an admitted fraction. ]==]
local CALIBRATE_MIN = 0.004   -- a fraction of the zone, roughly a few seconds' walk
local CALIBRATE_MAX = 0.08    -- more than this is a loading screen, not a walk

function M:ZoneScale(zone)
    zone = zone or self:Zone()
    if not zone then return nil end

    local store = self:Config()
    store.zoneYards = store.zoneYards or {}

    return store.zoneYards[zone]
end

--[[ The player's world position in yards, east and north, or nothing on a
     client without SuperWoW. Same call the map module measures group members
     with -- see `UnitOffsetYards` -- and the same axis convention. ]]--
function M:WorldPosition()
    if type(UnitPosition) ~= "function" then return nil end

    local ok, wx, wy = pcall(UnitPosition, "player")
    if not ok or type(wx) ~= "number" or type(wy) ~= "number" then return nil end

    --[==[ **This file had the axes the wrong way round, and it is why the yards
         were wrong.**

         It said world x counts north and y counts west, and credited `map.lua`
         for the reading. `map.lua` says the opposite, and says it at length:
         **x counts west and y counts north**, settled from a player really
         thirty yards east being drawn thirty yards west -- a reflection in one
         axis, which no choice of rotation produces. See `UnitOffsetYards`.

         With the two swapped, `CalibrateZone` divided a *north* displacement by
         an *east-west* map fraction. It only learns the x scale from a step that
         was mostly eastward, and a mostly-eastward step moves you almost no
         distance north -- so the number it learned was a rounding error over a
         real fraction. Silithus came out at **10.4 yards per map width** against
         a true figure near 4900, and a waypoint most of a zone away read as five
         yards. Reported as "yards aren't correct", and it was not the
         calibration that was wrong but the compass under it.

         Returned as north and east so the arithmetic below reads as compass
         directions. ]==]
    return wy, -wx
end

--[==[ **One sample of "this many yards is that much of the map".**

     Called from the refresh, so it learns while somebody walks toward the thing
     they marked -- which is exactly when they are looking at the number. ]==]
function M:CalibrateZone(fx, fy)
    local zone = self:Zone()
    if not zone or not fx then return false end

    local north, east = self:WorldPosition()
    if not north then return false end

    local last = self.lastSample

    --[==[ **The sample is kept until it is worth using.**

         It used to be replaced on every call, and this is called from the
         refresh -- so the pair being compared was always two adjacent passes,
         a few hundredths of a second apart. The bar for learning is four
         thousandths of the zone, about twenty yards in Silithus, and nobody
         covers twenty yards between two frames. So the zone was almost never
         measured, and `/eq waydebug` said "not measured yet" however far
         somebody walked.

         Held instead, so the distance accumulates until there is enough of it
         to divide by. Replaced only when it has been used, when the zone
         changes, or when the step is too large to be a walk -- which is a
         loading screen, and the one case where the old sample is worse than no
         sample at all. ]==]
    if not last or last.zone ~= zone then
        self.lastSample = { zone = zone, fx = fx, fy = fy,
                            north = north, east = east }
        return false
    end

    local dfx, dfy = fx - last.fx, fy - last.fy
    local dEast, dNorth = east - last.east, north - last.north

    local store = self:Config()
    store.zoneYards = store.zoneYards or {}
    local scale = store.zoneYards[zone] or {}

    local learned = false

    --[[ East is the map's x, and only believed when the step was mostly
         eastward: a step due north says nothing about how wide the zone is. ]]--
    if abs(dfx) > CALIBRATE_MIN and abs(dfx) < CALIBRATE_MAX
            and abs(dfx) > abs(dfy) * 2 then
        scale.x = abs(dEast / dfx)
        learned = true
    end

    --[[ And the map's y runs south, which the sign takes care of by being
         thrown away -- what is wanted is yards per fraction, not which way. ]]--
    if abs(dfy) > CALIBRATE_MIN and abs(dfy) < CALIBRATE_MAX
            and abs(dfy) > abs(dfx) * 2 then
        scale.y = abs(dNorth / dfy)
        learned = true
    end

    if learned then store.zoneYards[zone] = scale end

    --[==[ **And the sample only moves on once it has done its job.**

         Learned, or too far to be a walk. A step that is merely small is left
         alone, so the next pass measures from where this one started rather
         than from where it ended -- which is the whole of what was missing. ]==]
    if learned or abs(dfx) >= CALIBRATE_MAX or abs(dfy) >= CALIBRATE_MAX then
        self.lastSample = { zone = zone, fx = fx, fy = fy,
                            north = north, east = east }
    end

    return learned
end

--[[ The distance in yards, or nothing when this zone has not been measured
     yet. One axis measured is enough to answer: zones are oblong but not by
     much, and half an answer beats none while the other axis is still being
     learned. ]]--
function M:DistanceYards(px, py, point)
    if not px or not point then return nil end

    local scale = self:ZoneScale()
    if not scale then return nil end

    local sx = scale.x or scale.y
    local sy = scale.y or scale.x
    if not sx or not sy then return nil end

    local dx = (point.x - px) * sx
    local dy = (point.y - py) * sy

    return sqrt((dx * dx) + (dy * dy))
end

--[==[ **Yards where they are known, the fraction where they are not.**

     Rounded to whole yards over ten and to one decimal under, which is the
     precision of the answer: "3.4 yards" is a step and a half and "212 yards" is
     a run, and a decimal on the second would be pretending. ]==]
function M:DistanceText(distance, yards)
    if yards then
        if yards >= 10 then return format("%d yds", yards + 0.5) end
        return format("%.1f yds", yards)
    end

    if not distance then return "" end
    return format("%.1f%%", distance * 100)
end

-- ---------------------------------------------------------------------------
-- the arrow
-- ---------------------------------------------------------------------------

function M:ArrowFrame()
    if self.arrowFrame then return self.arrowFrame end

    local frame = CreateFrame("Frame", "EquadisClassicOverhaulArrow", UIParent)
    frame:SetWidth(42)
    frame:SetHeight(42)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function()
        if OB.profile and OB.profile.locked then return end
        this:StartMoving()
    end)

    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        EquadisClassicOverhaul.modules.waypoints:StoreArrow()
    end)

    --[[ The arrow itself. One cell of the sheet at a time -- see `arrowCell`
         for why this is a texture rather than the model frame it used to
         be. ]]--
    local arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetAllPoints(frame)
    arrow:SetTexture(ARROW_TEXTURE)
    frame.arrow = arrow

    frame.name = OB.NewText(frame, "OVERLAY", "GameFontNormal")
    frame.name:SetPoint("TOP", frame, "BOTTOM", 0, -2)

    frame.distance = OB.NewText(frame, "OVERLAY", "GameFontNormalSmall")
    frame.distance:SetPoint("TOP", frame.name, "BOTTOM", 0, -1)

    frame:Hide()

    self.arrowFrame = frame
    return frame
end

function M:StoreArrow()
    local frame = self.arrowFrame
    if not frame or not frame.GetCenter or not UIParent.GetCenter then return false end

    local x, y = frame:GetCenter()
    local cx, cy = UIParent:GetCenter()
    if not x or not cx then return false end

    local cfg = self:Config()
    cfg.arrowX = x - cx
    cfg.arrowY = y - cy
    return true
end

--[[ Everything the arrow shows, recomputed. Called from the tick, so it does as
     little as it can: the position and the facing are two client calls, the
     rest is arithmetic, and nothing is built. ]]--
function M:Refresh()
    local frame = self.arrowFrame
    if not frame or not frame:IsShown() then return false end

    local point = self:Active()
    if not point then
        frame:Hide()
        return false
    end

    local px, py, remembered = self:PlayerPosition()
    if not px then return false end

    local cfg = self:Config()
    local distance = self:Distance(px, py, point)

    --[[ Learned while walking, which is when somebody is watching the number.
         Never from a remembered position: pairing one of those with a live
         world position would measure a walk nobody took. See `CalibrateZone`. ]]--
    if not remembered then self:CalibrateZone(px, py) end

    --[[ Drawn here because this is the pass that already knows where the player
         is, and the pin is that same question asked of a smaller map. ]]--
    self:ApplyMinimapPin(px, py)
    local yards = self:DistanceYards(px, py, point)

    --[[ Arrival, which is a state rather than an event -- checked here because
         this is the only thing that knows where the player is. Latched, so
         walking in and out of the last few paces does not announce twice. ]]--
    --[==[ **You do not arrive anywhere while you are dead.**

         A corpse waypoint is dropped on the spot you died, which is the spot you
         are lying on -- so arrival fired on the same frame it was created and
         `clearOnArrival` deleted it before the release button had been pressed.
         The one waypoint that is always set at zero distance was the one this
         made impossible.

         Held rather than special-cased on the corpse mark, because it is true of
         every waypoint: a ghost has not walked anywhere, and whatever it is
         standing on it has not arrived at. ]==]
    local dead = type(UnitIsDeadOrGhost) == "function"
            and UnitIsDeadOrGhost("player")

    --[==[ **Yards when the zone has been measured, the fraction when it has
         not.**

         The setting is in yards because that is the question -- how far do I
         have to walk -- and the fraction only ever stood in for it. A zone this
         addon has not walked yet has no measure, and falling back is better than
         refusing to arrive at all. ]==]
    local within

    if yards then
        within = yards <= (tonumber(cfg.arriveYards) or 10)
    else
        within = distance and distance <= ARRIVE_AT
    end

    if within and not dead then
        if not self.arrived then
            self.arrived = true
            if cfg.announceArrival then
                Say("arrived at " .. (point.name or "the waypoint") .. ".")
            end
            if cfg.clearOnArrival then
                self:RemoveByValue(point)
                return true
            end
        end
    else
        self.arrived = nil
    end

    local angle = self:Angle(px, py, point)
    local facing = self:Facing()

    --[[ The arrow points at the waypoint *relative to where the player is
         looking*, which is what makes it readable while moving: straight up
         means "keep going". Without a facing the angle is still correct as a
         compass bearing, so the arrow degrades to north-up rather than
         vanishing. ]]--
    local shown = angle
    if facing then shown = angle + facing end

    --[==[ **Close enough, and the arrow becomes the one that points down at
         it.**

         Measured in yards where the zone has been walked, and in map fractions
         where it has not -- the same two measures arrival itself uses, so the
         animation and the clearing cannot disagree about what "close" means.

         The frame number advances with the clock rather than with the refresh,
         so it runs at the same speed however often this is called. ]==]
    local arriving

    if yards then
        arriving = yards <= ((tonumber(cfg.arriveYards) or 10) + ARROW_UP_MARGIN)
    else
        arriving = distance and distance <= (ARRIVE_AT * 1.5)
    end

    if frame.arrow then
        if arriving then
            local now = (type(GetTime) == "function" and GetTime()) or 0

            if frame.arrowUp ~= true then
                frame.arrow:SetTexture(ARROW_UP_TEXTURE)
                frame.arrowUp = true
                frame.arrowUpFrom = now
            end

            frame.arrow:SetTexCoord(
                    arrowUpCell((now - (frame.arrowUpFrom or now)) / ARROW_UP_RATE))
        else
            if frame.arrowUp then
                frame.arrow:SetTexture(ARROW_TEXTURE)
                frame.arrowUp = nil
            end

            frame.arrow:SetTexCoord(arrowCell(shown))
        end
    end

    --[==[ **The colour is applied, which it previously was not.**

         This worked out which of the two colours was right, assigned it to
         `frame.color`, and stopped. Nothing read that field, so the setting
         did nothing at all -- and it was guarded on `SetModelScale`, a method
         of the model frame that no longer exists here and which had nothing to
         do with colour in the first place.

         Within a right angle of straight ahead counts as on course. Wider than
         that and "you are going the right way" stops being true. ]==]
    if frame.arrow and frame.arrow.SetVertexColor then
        local color

        if colorMode() == ARROW_COLOR_FACING then
            local off = shown
            while off > pi do off = off - (2 * pi) end
            while off < -pi do off = off + (2 * pi) end

            color = (off > -(pi / 4) and off < (pi / 4))
                    and cfg.onCourseColor or cfg.offCourseColor
        else
            --[[ One flat colour, which used to be white with no way to say
                 otherwise. ]]--
            color = cfg.arrowColor
        end

        if color then
            frame.arrow:SetVertexColor(color[1] or 1, color[2] or 1,
                    color[3] or 1)
        else
            frame.arrow:SetVertexColor(1, 1, 1)
        end
    end

    if cfg.showName then
        frame.name:SetText(point.name or "Waypoint")
        frame.name:Show()
    else
        frame.name:Hide()
    end

    if cfg.showDistance then
        frame.distance:SetText(self:DistanceText(distance, yards))
        frame.distance:Show()
    else
        frame.distance:Hide()
    end

    return true
end

function M:RemoveByValue(point)
    local list = self:List()
    for i = table.getn(list), 1, -1 do
        if list[i] == point then table.remove(list, i) end
    end
    self:Deactivate()
    return true
end

function M:ApplyArrow()
    local frame = self:ArrowFrame()

    --[[ A hidden arrow forgets which sheet it had, or the next waypoint opens
         wearing the arrival animation for a place it is nowhere near. ]]--
    if frame and frame.arrowUp and not self:Active() then
        frame.arrow:SetTexture(ARROW_TEXTURE)
        frame.arrowUp = nil
    end

    --[[ And the minimap's copy goes with it: nothing to point at is nothing to
         mark, and a pin left behind outlives the waypoint it was for. ]]--
    if not self:Active() and self.minimapPinIcon then self.minimapPinIcon:Hide() end
    local cfg = self:Config()

    if not OB.ModuleEnabled("waypoints") or not cfg.arrow or not self:Active() then
        frame:Hide()
        return false
    end

    local size = tonumber(cfg.arrowSize) or 42
    frame:SetWidth(size)
    frame:SetHeight(size)

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", cfg.arrowX or 0, cfg.arrowY or 140)

    OB.ApplyFont(frame.name, tonumber(cfg.nameSize) or 12, "waypoints")
    OB.ApplyFont(frame.distance, (tonumber(cfg.nameSize) or 12) - 1, "waypoints")

    frame:Show()
    self:Refresh()

    if OB.MarkMovable then OB.MarkMovable(frame, "Waypoint Arrow") end

    --[[ Attached after the mover, so the drag handler it installs is the one
         kept and called for every button but the right. ]]--
    self:AttachMenu(frame)

    return true
end

--[==[ **The waypoint on the minimap, drawn with the world map's own icon.**

     Asked for, and everything it needs was already here: the map module turns
     yards into minimap pixels for the group markers (`MinimapScale`, which is
     `width / diameter` and was settled in game), and the zone calibration turns
     a map fraction into yards. The two together put a map coordinate on the
     minimap.

     **So it needs the zone to have been measured**, the same as the yards on the
     arrow do -- a few seconds of walking. Before that there is no honest
     conversion and the pin stays away rather than guessing at one.

     **It is clamped to the rim rather than hidden when it is out of range, and
     that is deliberately the opposite of what the group markers do.** The map
     module hides a party member past the edge, because a clamped marker says
     "somebody is roughly that way" and roughly is not good enough for a person
     you are trying to reach. A waypoint is the other case exactly: roughly that
     way is the entire question, and it is what TomTom does with it. ]==]
local MINIMAP_PIN_ICON = "Interface\\WorldMap\\WorldMapPartyIcon"

--[[ The icon, kept under a name that cannot be mistaken for the setting: the
     module's `minimapPinIcon` is the texture, the profile's `minimapPin` is
     whether to draw it. ]]--
function M:MinimapPin()
    if self.minimapPinIcon then return self.minimapPinIcon end
    if not Minimap or not Minimap.CreateTexture then return nil end

    --[[ On the minimap itself and above the engine's own blips, which are drawn
         into the frame rather than into a child of it. ]]--
    local icon = Minimap:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(MINIMAP_PIN_ICON)
    icon:SetVertexColor(1.0, 0.82, 0.0)
    icon:Hide()

    self.minimapPinIcon = icon
    return icon
end

function M:ApplyMinimapPin(px, py)
    local icon = self:MinimapPin()
    if not icon then return false end

    local cfg = self:Config()
    local point = OB.ModuleEnabled("waypoints") and cfg.minimapPin and self:Active()

    local scale = point and self:ZoneScale()
    local map = OB.modules and OB.modules.map
    local pixels = point and scale and map and map.MinimapScale
            and map:MinimapScale()

    if not point or not scale or not pixels or not px then
        icon:Hide()
        return false
    end

    --[[ Both axes borrow from each other where only one has been measured,
         exactly as the distance does. ]]--
    local sx = scale.x or scale.y
    local sy = scale.y or scale.x
    if not sx or not sy then icon:Hide() return false end

    --[[ Map x runs east and map y runs *south*, so north is the negative. ]]--
    local east = (point.x - px) * sx
    local north = (py - point.y) * sy

    local x, y = east * pixels, north * pixels

    --[==[ The minimap turns under a fixed arrow when the client is set to rotate
         it, so everything on it turns with the world rather than with the
         frame -- the same correction the group markers take. ]==]
    if OB.CVar and OB.CVar("rotateMinimap") == "1" then
        local facing = self:Facing()

        if facing then
            local s, c = math.sin(facing), math.cos(facing)
            x, y = (x * c) - (y * s), (x * s) + (y * c)
        end
    end

    local size = 16
    local radius = ((Minimap.GetWidth and Minimap:GetWidth()) or 140) / 2
    local edge = radius - (size / 2)
    local away = sqrt((x * x) + (y * y))

    --[[ Past the rim it is pulled back onto it, keeping its direction. ]]--
    if away > edge and away > 0 then
        x, y = (x / away) * edge, (y / away) * edge
    end

    icon:SetWidth(size)
    icon:SetHeight(size)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", Minimap, "CENTER", x, y)
    icon:Show()

    return true
end

--[==[ **One menu, opened from the pin or from the arrow.**

     TomTom puts a menu on both and it is the obvious place to look: the thing
     you want to be rid of is the thing you are pointing at. Reported as two
     absences -- no menu on the map pin, no menu on the arrow -- and they are one
     feature.

     `UIDropDownMenu` rather than anything of this addon's own, because the
     standing rule is the client's widgets everywhere outside the setup
     walkthrough and the options panel, and a right-click menu is as much the
     client's furniture as the unit menu it looks like.

     Built once and re-initialised on each open, so the entries describe the
     waypoint that is active *now* rather than the one that was active when the
     frame was made. ]==]
function M:MenuFrame()
    if self.menu then return self.menu end
    if type(CreateFrame) ~= "function" then return nil end

    local menu = CreateFrame("Frame", "EquadisOverhaulWaypointMenu", UIParent,
            "UIDropDownMenuTemplate")

    self.menu = menu
    return menu
end

--[==[ **What the menu offers**, as data rather than as a pile of AddButton
     calls, so the test can read the list and the two openers cannot drift.

     `isTitle` on the first entry is the client's own way of writing a heading
     into a dropdown, and it names the waypoint so a menu opened from the wrong
     pin is obvious before anything is clicked. ]==]
function M:MenuItems()
    local point = self:Active()
    local module = self

    local items = {
        { text = (point and point.name) or "Waypoint", isTitle = 1, notCheckable = 1 },
    }

    if point then
        table.insert(items, {
            text = "Clear This Waypoint",
            notCheckable = 1,
            --[[ `RemoveByValue` takes the point itself rather than an index,
                 which is what the menu has in hand and what survives the list
                 being reordered between opening the menu and clicking it. ]]--
            func = function() module:RemoveByValue(point) end,
        })
    end

    table.insert(items, {
        text = "Clear All In This Zone",
        notCheckable = 1,
        func = function() module:ClearAll() end,
    })

    --[[ The settings, because "how do I turn this arrow off" is the other
         question somebody right-clicks it to ask. ]]--
    if type(OB.OpenPanelAt) == "function" then
        table.insert(items, {
            text = "Waypoint Settings",
            notCheckable = 1,
            func = function() OB.OpenPanelAt("Waypoints") end,
        })
    end

    return items
end

function M:ShowMenu(anchor)
    local menu = self:MenuFrame()
    if not menu then return false end
    if type(UIDropDownMenu_Initialize) ~= "function" then return false end
    if type(ToggleDropDownMenu) ~= "function" then return false end

    local module = self

    UIDropDownMenu_Initialize(menu, function()
        local items = module:MenuItems()

        for i = 1, table.getn(items) do
            UIDropDownMenu_AddButton(items[i])
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, anchor or "cursor", 0, 0)

    return true
end

--[==[ **A right-click opens it, and nothing else is claimed.**

     Left is still a drag on the arrow and still the client's own on the map, so
     this takes the one button neither of them uses. Attached rather than
     replacing whatever is there: the handler that was on the frame is called
     first for every other button. ]==]
function M:AttachMenu(frame)
    if not frame or frame.eqMenuAttached then return false end
    if not frame.SetScript then return false end

    frame.eqMenuAttached = true

    if frame.EnableMouse then frame:EnableMouse(true) end

    local previous = frame.GetScript and frame:GetScript("OnMouseUp")
    local module = self

    frame:SetScript("OnMouseUp", function()
        if arg1 == "RightButton" then
            module:ShowMenu(this)
            return
        end

        if previous then previous() end
    end)

    return true
end

--[==[ **A pin for every mark in the zone, not only the one being pointed at.**

     The first version drew one, on the reasoning that the arrow points at one
     thing and the pin is the same thing on the map. That reasoning is wrong
     about what a map is for: the arrow answers "which way now" and the map
     answers "what have I marked here", and a map showing one of five marks
     cannot answer it. Reported plainly -- "only 1 pin is still showing on world
     map".

     Grown on demand and never shrunk, because 1.12 cannot destroy a frame and
     each of these takes a global name. Somebody with eleven marks in a zone
     pays for eleven frames once. ]==]
local MAX_PINS = 32

function M:MapPinAt(index)
    self.pins = self.pins or {}

    if self.pins[index] then return self.pins[index] end
    if index > MAX_PINS then return nil end

    local parent = getglobal("WorldMapButton")
    if not parent then return nil end

    local pin = CreateFrame("Frame",
            "EquadisOverhaulWaypointPin" .. index, parent)
    pin:SetWidth(16)
    pin:SetHeight(16)

    if pin.SetFrameLevel and parent.GetFrameLevel then
        pin:SetFrameLevel((parent:GetFrameLevel() or 0) + 21)
    end

    local icon = pin:CreateTexture(nil, "OVERLAY")
    icon:SetAllPoints(pin)
    icon:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")

    pin.icon = icon
    pin:Hide()

    self:AttachMenu(pin)

    self.pins[index] = pin
    return pin
end

--[[ Every mark in this zone, or none at all when the map is showing somewhere
     else. Returns how many were drawn. ]]--
function M:ApplyMapPin()
    local zone = self:Zone()
    local list = (OB.ModuleEnabled("waypoints") and zone
            and self:List(zone)) or {}

    local parent = getglobal("WorldMapButton")
    local width = parent and parent.GetWidth and parent:GetWidth()
    local height = parent and parent.GetHeight and parent:GetHeight()

    local usable = width and height and width > 0 and height > 0
    local active = self:Active()
    local drawn = 0

    if usable and self.activeZone ~= zone then
        --[[ The list belongs to this zone; the *active* mark may not. Drawing
             its flag on somebody else's map is the fault the single pin had. ]]--
        active = nil
    end

    for i = 1, table.getn(list) do
        local point = list[i]
        local pin = usable and self:MapPinAt(i)

        if pin then
            --[[ A zone fraction onto the map's own rectangle: x from the left,
                 y down from the top, which is the way map coordinates run. ]]--
            pin:ClearAllPoints()
            pin:SetPoint("CENTER", parent, "TOPLEFT",
                    point.x * width, -(point.y * height))

            --[==[ **The one being pointed at is the bright one.** Five identical
                 flags say where you have marked and not which the arrow means,
                 and that second question is the one somebody opens the map with
                 an arrow on screen to ask. ]==]
            if pin.icon and pin.icon.SetVertexColor then
                if point == active then
                    pin.icon:SetVertexColor(1.0, 0.82, 0.0)
                else
                    pin.icon:SetVertexColor(0.6, 0.6, 0.6)
                end
            end

            pin.point = point
            pin:Show()
            drawn = drawn + 1
        end
    end

    --[[ And the rest put away, or deleting a mark leaves its flag behind. ]]--
    for i = drawn + 1, table.getn(self.pins or {}) do
        local spare = self.pins[i]
        if spare then
            spare.point = nil
            spare:Hide()
        end
    end

    return drawn
end

-- ---------------------------------------------------------------------------
-- setting one from the map
-- ---------------------------------------------------------------------------

--[==[ **Where the cursor is on the world map, as a zone fraction.**

     `GetCursorPosition` answers in screen pixels at the *cursor's* scale, and
     the map is a frame with a scale of its own -- one this addon changes, since
     resizing the world map is a setting here. Dividing by the frame's effective
     scale is what puts both into the same space; skipping it is why a rescaled
     map drops its waypoint somewhere else entirely.

     Measured against `WorldMapDetailFrame` rather than `WorldMapButton`. The
     detail frame is the artwork, and a zone coordinate is a fraction of the
     artwork; the button is the click-catcher over it and is not guaranteed to
     be the same rectangle.

     Nil outside the map, which is a real answer: the pointer can be over the
     window's border or its furniture, and 1.2 is not a coordinate. ]==]
function M:CursorPosition()
    if type(GetCursorPosition) ~= "function" then return nil end

    local frame = getglobal("WorldMapDetailFrame")
    if not frame or not frame.GetLeft then return nil end

    local x, y = GetCursorPosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    local width, height = frame:GetWidth(), frame:GetHeight()
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1

    if not x or not left or not width or width <= 0 or height <= 0 then
        return nil
    end
    if not scale or scale <= 0 then scale = 1 end

    local cx = ((x / scale) - left) / width
    local cy = (top - (y / scale)) / height

    if cx < 0 or cx > 1 or cy < 0 or cy > 1 then return nil end

    return cx, cy
end

--[==[ **Control-click the map to drop a waypoint there.**

     The client has no click handler to attach to on a frame: `WorldMapButton`
     is wired to the *global* `WorldMapButton_OnClick` from XML, so the only
     seam is that global. It is wrapped rather than replaced, and the original
     is called for every click this one does not claim -- including a plain
     right-click, which is how you zoom out to the continent and would be a
     rotten thing to eat.

     **Installed once.** A second wrap would capture the first and the chain
     would grow a layer every time this ran, which is the same trap the macro
     icon hook in Quality Of Life documents at length. The flag is on the module
     rather than on the global, because a global can be replaced by a neighbour
     between our two visits and then the flag is gone with it.

     Modifier held rather than a mode to switch on: a map you can click to
     create waypoints is a map that creates a waypoint every time you meant to
     drag it. ]==]
function M:InstallMapClick()
    if self.mapClickInstalled then return false end
    if type(WorldMapButton_OnClick) ~= "function" then return false end

    self.mapClickInstalled = true

    local original = WorldMapButton_OnClick
    local module = self

    WorldMapButton_OnClick = function(a1, a2, a3)
        --[[ `arg1` on 1.12, but the client also passes the button through as
             the first parameter in some builds. Both are read, and neither is
             trusted to be there. ]]--
        local button = a1
        if type(button) ~= "string" then button = arg1 end

        if module:MapClick(button) then return end

        if original then return original(a1, a2, a3) end
    end

    return true
end

--[==[ True when this click was ours and the caller should stop.

     Either mouse button, because "control-click" is what people say and a plain
     left click on the map does nothing this could be taking away. ]==]
function M:MapClick(button)
    if not OB.ModuleEnabled("waypoints") then return false end

    local cfg = self:Config()
    if not cfg.mapClick then return false end

    if type(IsControlKeyDown) ~= "function" or not IsControlKeyDown() then
        return false
    end

    --[==[ **The button, which used not to be read at all.**

         Left alone the answer is "either", which is what this has always done
         and what the note above still describes. Narrowed, an unwanted button
         falls through to the client's own handler exactly as though this feature
         were switched off -- so a right-click still zooms the map out, which is
         the thing that would be rotten to eat. ]==]
    local wanted = cfg.mapClickButton

    if wanted == "left" and button == "RightButton" then return false end
    if wanted == "right" and button == "LeftButton" then return false end

    local x, y = self:CursorPosition()
    if not x then return false end

    local zone = self:Zone()
    if not zone then return false end

    --[==[ **Not from a continent map, because that fraction is not a zone's.**

         `GetCurrentMapZone()` answers 0 while the whole continent is shown, and
         a click there is a fraction of the continent. This filed it against
         whichever zone the *player* was standing in, so a mark dropped on
         Silithus while standing in Un'Goro became a point in Un'Goro at
         Silithus's continent coordinates -- somewhere near the corner, and
         confidently wrong.

         Reported as "on world map zoomed out to show whole region, waypoints
         are still being placed on the area map".

         Refused rather than converted, because converting needs each zone's
         rectangle on the continent and 1.12 exposes no such table -- Astrolabe
         carries one, and it is a large file that is wrong the day a server adds
         a zone. The refusal names the zone under the cursor, which the client
         has already worked out for its own label, so the instruction is "open
         that map" rather than "something went wrong". ]==]
    if type(GetCurrentMapZone) == "function" and GetCurrentMapZone() == 0 then
        local label = getglobal("WorldMapFrameAreaLabel")
        local under = label and label.GetText and label:GetText()

        if under and under ~= "" then
            Say("that is the continent map -- open " .. under
                    .. " to mark a spot in it.")
        else
            Say("that is the continent map -- open a zone to mark a spot in it.")
        end

        --[[ Claimed, so the client does not also act on it: the click was ours
             to answer and answering it with a sentence is still answering. ]]--
        return true
    end

    --[[ Named for where it is, because a list of five waypoints all called
         "Waypoint" is a list of one waypoint five times. ]]--
    local name = format("%s (%.1f, %.1f)", zone, x * 100, y * 100)

    --[==[ **Percentages, because that is what `Add` takes.**

         `CursorPosition` answers a fraction and `Add` answers to `/way 53 26`,
         so it divides by a hundred -- and this handed it the fraction, which was
         divided again. Every control-click landed at a hundredth of where it was
         aimed: 53.4, 26.0 stored as 0.53, 0.26 **percent**, which is the extreme
         top-left corner of every zone.

         The line above is why nobody caught it. The message names the place
         correctly, because it does its own multiplication -- so the addon
         confirmed the right coordinates and then walked you to the corner. That
         is the reported "the arrow doesn't work", and it was never the arrow.

         Diagnosed from `/eq waydebug`, which prints the stored fraction beside
         the name: `Silithus (53.4, 26.0) at 0.0053387, 0.0025968`. ]==]
    self:Add(x * 100, y * 100, name, zone)
    Say("waypoint set at " .. format("%.1f, %.1f", x * 100, y * 100)
            .. " in " .. zone .. ".")

    return true
end

-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

--[==[ **A mark the death event was too early for.**

     `PLAYER_DEAD` can arrive before the client will answer where you are --
     `GetPlayerMapPosition` gives 0,0 for a frame or two around a death, and
     `MarkCorpse` refuses a position of nothing rather than marking the corner of
     the zone. Refusing was right; giving up was not, because the one chance to
     record where the body is passes in that same second.

     So a failed mark is remembered and retried on the tick until it takes or
     until you are back on your feet. This is the other half of the death arrow
     not working, and the half that leaves no trace when it happens. ]==]
function M:RetryCorpse()
    if not self.wantCorpse then return false end

    local down = type(UnitIsDeadOrGhost) ~= "function"
            or UnitIsDeadOrGhost("player")

    if not down then
        self.wantCorpse = nil
        return false
    end

    if self:MarkCorpse() then
        self.wantCorpse = nil
        return true
    end

    return false
end

function M:OnUpdate(now)
    self:RetryCorpse()

    --[[ Ten times a second. The arrow has to feel attached to the camera, and a
         quarter second of lag behind a turn reads as the arrow being broken --
         but the position underneath it does not move fast enough to be worth
         sixty. ]]--
    if not self.nextRefresh or now >= self.nextRefresh then
        self.nextRefresh = now + 0.1
        self:Refresh()

        --[[ The pin with it, at the same rate: the map is a window that can be
             opened at any moment, and a pin placed only when the waypoint was
             set is a pin missing from every map opened afterwards. ]]--
        self:ApplyMapPin()
    end
end

--[==[ **The corpse run, marked at the one moment the position is still yours.**

     `PLAYER_DEAD` fires while the body is still under you, so that is where the
     mark goes. A moment later you release, and from then on
     `GetPlayerMapPosition` answers for a ghost standing at a graveyard -- which
     is the wrong place and the reason this cannot be done any later.

     Named rather than numbered, and marked so it can be found again: a corpse
     waypoint is the one thing here that should be replaced rather than added to,
     or dying five times in a row leaves five arrows and no way to tell which is
     this one. ]==]
local CORPSE_NAME = "Your Corpse"

function M:MarkCorpse()
    if not self:Config().corpseWaypoint then return false end

    local zone = self:Zone()
    if not zone then return false end

    local x, y = self:PlayerPosition()
    if not x then return false end

    --[[ The previous one first, wherever it was. A corpse you have already
         walked back to is not a place worth pointing at. ]]--
    self:ClearCorpse()

    --[[ `Add` takes percentages, which is the mistake the map click made. ]]--
    local point = self:Add(x * 100, y * 100, CORPSE_NAME, zone)
    if not point then return false end

    point.corpse = true
    self.corpsePoint = point

    OB.Print("marked where you died -- the arrow points back.", "Waypoints")

    return true
end

--[==[ **And taken away when you are on your feet again.**

     Both ways back: `PLAYER_UNGHOST` is walking to the body, `PLAYER_ALIVE` with
     no ghost left is a resurrection where you stood or at a spirit healer. Either
     way the corpse is not somewhere to walk to any more, and an arrow that
     outlives the run it was for is the reason people turn these off. ]==]
function M:ClearCorpse()
    local point = self.corpsePoint
    self.corpsePoint = nil

    if not point then return false end

    self:RemoveByValue(point)

    return true
end

function M:OnEvent()
    --[[ A new zone is a different list, so whatever was being pointed at is not
         in it. Dropped rather than kept: an arrow pointing at coordinates from
         the zone you just left is confidently wrong. ]]--
    if event == "ZONE_CHANGED_NEW_AREA" then
        self.active = nil
        self.activeZone = nil
        self.arrived = nil
    end

    if event == "PLAYER_DEAD" then
        --[[ Retried on the tick if this comes too early -- see `wantCorpse`. ]]--
        if not self:MarkCorpse() then self.wantCorpse = true end
    end

    --[==[ **Up again, by either route -- and asked with a call that exists.**

         `PLAYER_ALIVE` fires on *release* as well as on resurrection, and the
         release is the one moment the mark must survive. This asked
         `UnitIsGhost`, and got it wrong in two ways at once:

         *A missing call cleared the mark.* `type(UnitIsGhost) == "function" and
         UnitIsGhost(...)` reads as false where the call does not exist, and
         false meant "not a ghost, so clear it". The safe direction is the
         opposite: if we cannot tell, keep it.

         *And the ghost flag is not reliably set yet* when `PLAYER_ALIVE`
         arrives on a release. `UnitIsDeadOrGhost` covers both states, is what
         `hud.lua` already trusts for exactly this question, and is true through
         the whole corpse run.

         Reported as the death arrow not working, which is what it looks like
         when the mark is deleted by the release a fraction of a second after it
         is made. ]==]
    if event == "PLAYER_UNGHOST" then
        self.wantCorpse = nil
        self:ClearCorpse()
    end

    if event == "PLAYER_ALIVE" then
        local down = type(UnitIsDeadOrGhost) ~= "function"
                or UnitIsDeadOrGhost("player")

        if not down then
            self.wantCorpse = nil
            self:ClearCorpse()
        end
    end

    self:ApplyArrow()
    self:ApplyMapPin()
end

function M:OnBind()
    self.facingFrame = nil
    self:InstallMapClick()
    self:ApplyArrow()
    self:ApplyMapPin()
end

function M:OnUnbind()
    if self.arrowFrame then self.arrowFrame:Hide() end

    --[[ The pins go through the same pass that draws them: with the module
         off it draws none and puts every spare away. This used to hide the
         original single pin, which nothing had built in a long while, and
         left the list's flags on the map. ]]--
    self:ApplyMapPin()
end

function M:OnStyle()
    self:ApplyArrow()
end

function M:OnDraw() end
