--[[ Equadis' Classic Overhaul :: the map

  Three things the 1.12 client gets wrong about looking at where you are.

  **The world map is fullscreen and only fullscreen.** Opening it stops the
  game: you cannot see what is happening, cannot read chat behind it, and cannot
  keep it up while you walk. Every map addon written since does the same one
  thing about it -- scale it down and let you see past it -- and that is the
  whole of what is offered here.

  **There is no clock.** Not a small one, not a bad one: none. `GetGameTime`
  has been in the client the entire time and nothing shows it, so knowing
  whether a world boss is up means alt-tabbing. The clock here is ours rather
  than a skin over the client's, because there is nothing to skin -- and it is
  a box on the bar above the minimap rather than a window of its own, because a
  window of its own was a second thing to place and a second thing to remember
  while the bar was right there saying where you are.

  **The zone name is furniture.** `MinimapZoneText` is a fixed size in a fixed
  place in a font nobody chose, and it is the one label on screen that answers
  "where am I".

  Zone level ranges are the fourth thing and they already work -- they arrived
  on the Quality Of Life page because that is where quality-of-life things went,
  and they belong here. Migration 25 moves them, keys and all.
]]--

local OB = EquadisClassicOverhaul
local format = string.format

local function Say(msg) OB.Print(msg, "Map") end

local M = OB.RegisterModule({
    id = "map",
    name = "Map",

    --[[ A feature that owns one window -- the bar above the minimap -- and
         decorates several frames the client already made. Same shape as the
         chat module. ]]--
    feature = true,
    renders = "none",
    --[[ The bar and the zone labels draw text and nothing else -- no bar
         texture, no border, and their own size sliders. See `OB.LookOptions`. ]]--
    styled = { font = true, fontOutline = true },

    --[==[ **The shared Appearance rows belong on one page.**

         The panel shell appends them to whichever tab is open unless a module
         says otherwise, so Bar Texture and Font appear to be settings about
         whatever you happen to be looking at. `appearanceSection` is the answer
         and had been in `options.lua` all along with nothing setting it. ]==]
    appearanceSection = "general",

    --[[ Off, because it rescales Blizzard's world map and puts a frame on
         screen, and both should be decisions. ]]--
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
        --[[ **The world map, made smaller than the screen.**

             1.12 draws it at full size and nothing else is visible while it is
             up. Seventy percent is small enough to see past and large enough to
             read a zone name off. ]]--
        scaleMap = true,
        mapScale = 0.7,

        --[==[ **Control and the wheel, over the world map.**

             The size slider is the only way to change how big the map is
             without dragging a corner grip, and neither is reachable while you
             are looking at the map and want it bigger *now*.

             Control-held rather than the bare wheel, for the reason the minimap
             gives: the wheel already means something on a map to most people,
             and other addons put their own scroll behaviour on this frame. A
             modifier takes nothing away from either. ]==]
        mapWheel = true,

        --[[ Opaque by default. A translucent map is a nice idea that turns into
             a map you cannot read over a bright zone, so it is offered and not
             assumed. ]]--
        mapAlpha = 1,

        --[[ Kept for profile compatibility with earlier builds. The windowed
             map itself is now always draggable, so an old saved `false` here
             cannot silently nail the map back to the centre. ]]--
        moveMap = true,

        --[[ Coordinates are cheap to draw and make the windowed map materially
             more useful. Both player and cursor positions are shown, and the
             option can be turned off independently of the map size. ]]--
        mapCoordinates = true,

        --[[ Zone level ranges, moved here from Quality Of Life by migration 25.
             The names are unchanged so old profiles carry across. ]]--
        zoneLevels = true,
        zoneFaction = true,

        --[[ Round, which is the client's own shape. Square is a preference
             and a preference should be asked for. ]]--
        squareMinimap = false,

        --[==[ **A square minimap has to draw its own border**, because the
             client's ring is a texture shaped like a circle and there is
             nothing square to put back. That made it the one border in the
             addon with no setting behind it -- fixed at the Classic art
             whatever the rest of the interface was set to.

             Defaults to Classic so nobody's minimap changes shape on upgrade;
             it is now a choice rather than a decision already made. ]==]
        squareBorder = 3,

        --[[ The client offers no way to change this at all, so the default is
             the size it has always been. ]]--
        --[==[ **There is no scale any more, and this is why.**

             It multiplied the whole cluster, which sounds like a second way to
             make the map bigger and is really the same one: the client shows a
             fixed number of yards per zoom level, so every way of making the
             frame larger magnifies the same ground rather than revealing more of
             it. Two controls for one effect, and the one that took the furniture
             with it made the buttons and this addon's own bar grow too.

             Size stays because it is the honest version of the same thing.
             Distance is the zoom, which is the engine's and stops at level
             zero -- 466 yards outdoors, 300 indoors.

             Left in the defaults so a profile carrying one does not error, and
             ignored everywhere. ]==]
        __retired_minimapScale = 1,

        --[[ The client's own size. Changing this changes how much world
             fits in the box, which is the other half of "bigger". ]]--
        minimapBoxSize = 140,

        --[[ On: every other map in the world zooms with the wheel, and the
             client simply never switched it on for this one. ]]--
        minimapWheel = true,

        --[[ Off. Gathering somebody's icons is a visible change to where
             their buttons are, and that should be asked for. ]]--
        minimapCollect = false,

        --[==[ **Thin out map pins that are stacked on top of each other.**

             A quest objective that spawns in forty places is drawn by a quest
             addon as forty pins, because each spawn is a real point and the
             addon is right to have one. At minimap scale they overlap into a
             solid block of colour that says nothing except "somewhere around
             here", which is what one pin would have said.

             So this leaves one per patch of map and fades the rest. Nothing is
             hidden, moved, reparented or deleted -- see `ThinMinimapPins` for
             why that distinction is the whole design. ]==]
        thinPins = true,

        --[[ How close counts as the same place, in minimap pixels. Twelve is
             a little under one 16px pin, so two pins that visibly overlap are
             thinned and two that merely sit near each other are not. ]]--
        pinSpacing = 12,

        --[==[ **The client draws every party member as the same green dot.**

             Four identical dots answers "somebody is over there", which is half
             the question. Which of them is the healer is the other half, and on
             a world map it is the half that decides whether you walk. ]==]
--[==[ **On.** It was off, which meant the class-coloured group markers --
             the thing this module is most visibly for -- did not appear until
             somebody went looking for a switch they had no reason to know
             existed. Reported as the icons working on one character and not
             another, which is what a default off looks like from outside. ]==]
        replacePlayerIcons = true,

        --[==[ **The same markers on the minimap, which the client will not
             colour.**

             The engine draws the group's blips itself from one sheet and picks
             which blip by unit *type*. There is no per-unit frame to retexture
             and no class in the question it asks, so a class colour there cannot
             come from the client's own dots at any price -- not from an addon,
             and not from patching the sheet either.

             So they are drawn: one texture per group member, placed from where
             the unit actually is. The client's own dot stays underneath, which
             cannot be helped; the marker is larger and covers it.

             Its own size, because a minimap is a hundred and forty pixels across
             and the world map is a window. ]==]
        --[==[ **Large enough to cover the client's own blip.**

             The engine draws the group's dots itself and there is no API to
             retexture or hide them -- confirmed by extracting the client's
             `Minimap.lua` and `Minimap.xml`, neither of which mentions blips at
             all. So "replace the grey dots" can only mean *cover* them, and a
             marker smaller than the dot underneath leaves the dot showing round
             its edge, which reads as two icons rather than one.

             **That reasoning was overruled by looking at it.** Covering the
             blip only works if the marker is exactly over it, and it is not: a
             twenty pixel disc sitting near a ten pixel dot reads as one big
             marker and one small one, which is the two-icon problem it was
             meant to solve, arrived at from the other side.

             So the marker is sized to the client's own instead. If the two do
             not coincide the answer is to fix where it is drawn, not to grow it
             until the error is hidden underneath. ]==]
        minimapIconSize = 13,

        --[==[ **The client's own size, which is thirteen and not sixteen.**

             `WorldMapUnitTemplate` is a sixteen pixel frame, but the marker
             painted in it is a thirteen pixel dot with padding round it --
             measured off `WorldMapPartyIcon.blp`, which is 16x16 with ink from
             1,1 to 14,14. Sixteen was read off the frame and is three pixels
             too many.

             Ours is cropped to its own ink, so the number here is the size of
             the thing you can see and the two now match.

             A setting rather than a number, because how big is too big depends
             on how far out you keep the map. ]==]
        playerIconSize = 13,

        --[==[ **And the client's own dots put away underneath them.**

             Two markers for one person, and the engine's is drawn every frame
             while ours cannot be -- so ours trails its own grey shadow whenever
             anybody moves. Reported as our markers running at a lower
             framerate, which is what it looks like and is half of what it is:
             the other half is that there is something beside them to be late
             against.

             The blips are not frames. They are drawn by the engine into the
             minimap out of one sheet, and the only way to draw none of them is
             to hand it a sheet with nothing in it.

             **Off, because the first attempt at that sheet put a green square
             on the minimap.** It shipped on, on the reasoning that somebody who
             has asked for their own markers does not want the client's
             underneath -- which is still true, and is not worth a visible
             artefact on a minimap while the sheet is unverified. Whether the
             replacement loads is a thing only the game can answer, so the
             switch waits for somebody to look.

             **This is a bigger hammer than it looks.** That sheet is every blip
             the minimap draws, so tracking dots -- the yellow marks from Find
             Minerals and its kin -- go with them. Hence a setting, and hence
             the guard below: the blips come back the moment there is a group
             member we cannot place, because a marker that is merely late is
             better than a person who has vanished. ]==]
        --[==[ **On, now that it takes only the dot it should.**

             It shipped off for two reasons and both are gone. The first was
             that the replacement sheet drew a green square, which turned out to
             be a loose `Interface\\Minimap\\ObjectIcons.blp` left in the game
             folder rather than anything this addon did. The second was that
             hiding the group's dots meant hiding tracking finds with them,
             which is no longer true: the sheet that ships blanks one cell.

             What it fixes is a real fault rather than a preference. The engine
             redraws its own blips on a slower clock than this module redraws
             its markers, so on a moving group the client's dot trails its own
             replacement -- two markers for one person, one of them late.

             **So it has no switch.** Off is that fault, not a preference: the
             grey dot lagging behind its own coloured replacement is the thing
             that was reported, and nobody choosing it was choosing anything.
             Hiding follows `replacePlayerIcons` -- draw our own markers and the
             client's go; keep the client's and nothing is taken away. ]==]

        --[[ The client's furniture, all shown as the client shows it.
             Anything else would be this addon deciding what you do not
             want on your own minimap. ]]--
        minimapZoomButtons = true,
        minimapMail = true,
        minimapDayNight = true,
        minimapZoneBar = true,

        --[==[ **The header above the map: where you are, and what time it is.**

             The client welds the zone name into the minimap's top art and puts
             the clock on the ring, so neither follows the map when it is
             resized -- which is how the zone name ended up drawn under an
             enlarged map -- and neither can be switched off without the other.

             Three settings because they are three things: the art itself, and
             then each of the two things in it. Somebody who wants a clock and
             no zone name gets exactly that. ]==]
        locationTimeArt = true,
        showLocation = true,
        showTime = true,

        --[==[ **And where you are, in numbers.**

             Nothing in 1.12 shows this at all, and two addons that add it draw
             two readouts on top of each other -- which is what was reported.
             One, owned by this module, switchable. ]==]
        minimapCoordinates = true,

        --[==[ **The Atlas pins on the world map.**

             The bundled Atlas drops a pin on every dungeon entrance, boat, zeppelin
             and tram in the zone. Useful the first time somebody sails to Auberdine
             and clutter for somebody who has done it a hundred times, so it is a
             switch -- and the switch is Atlas's own flag rather than a second
             opinion beside it, because two switches for one row of pins is how
             they end up disagreeing. ]==]
        atlasMapIcons = true,

        --[==[ **The clock's two questions, which the bar above the map now
             answers.**

             Server time is what a raid invite means and what a world boss timer
             is counted in. Machine time is what your evening is measured in.
             Neither is the right default for everybody, and reading one while
             believing it is the other is how people miss things.

             **The clock that owned a window of its own is gone.** It was a
             second frame to place, a second thing to drag and a second time on
             screen once the bar above the map started showing one, and two
             clocks is one clock too many. These two stayed because they are
             about the time rather than about the frame that showed it. ]==]
        clockServer = true,
        clock24 = true,

        --[[ **The zone name.** Left at zero, meaning "whatever the client
             chose", so switching this module on changes nothing until somebody
             asks it to. A size written here would silently override a font the
             reader may have picked in another addon. ]]--
        zoneSize = 0,
        zoneColor = { 1, 1, 1, 1 },
    },

    options = {
--[==[ **A General tab that exists for the font.**

             This module draws text in two places -- the clock and the zone
             name -- and one font setting serves both. It belongs to neither
             tab, so pinning it to either would file a shared setting under one
             of the two things it affects. General is where a setting goes when
             it is about the whole feature. ]==]
        { "General", "__s_general", "section", "general" },

        { "The World Map", "__s_world", "section", "world" },

        { "Resize The Map", "scaleMap", "boolean" },

        { "Map Size", "mapScale", "slider", 40, 250, 5, 0.01,
          nil, "!scaleMap" },
        { "Map Opacity", "mapAlpha", "slider", 20, 100, 5, 0.01,
          nil, "!scaleMap" },
        { "Show Map Coordinates", "mapCoordinates", "boolean" },

        { "The Minimap", "__s_minimap", "section", "minimap" },

        { "Square Minimap", "squareMinimap", "boolean" },
        { "Square Minimap Border", "squareBorder", OB.borders, 200,
          nil, nil, "!squareMinimap" },
        --[[ **Two different questions.** Scale multiplies -- everything gets
             bigger and you see the same ground. Size changes the window, so a
             bigger box at the same zoom shows more of the world. Both are
             wanted, and they compose. ]]--


        --[[ The art first, then the two things in it -- greyed rather than
             hidden when the art is off, because they are still the answer to a
             question somebody is about to ask. ]]--
        { "Show Location/Time Art", "locationTimeArt", "boolean" },
        { "Show Location", "showLocation", "boolean",
          nil, nil, nil, nil, nil, "!locationTimeArt" },
        { "Show Time", "showTime", "boolean",
          nil, nil, nil, nil, nil, "!locationTimeArt" },
        --[[ Filed under the time they describe rather than under a clock
             section of their own: there is no clock frame left for a section to
             be about. ]]--
        { "Server Time", "clockServer", "boolean",
          nil, nil, nil, nil, nil, "!locationTimeArt,!showTime" },
        { "24 Hour", "clock24", "boolean",
          nil, nil, nil, nil, nil, "!locationTimeArt,!showTime" },
        { "Show Player Coordinates On Minimap", "minimapCoordinates", "boolean" },
        { "Show Atlas Icons On The World Map", "atlasMapIcons", "boolean" },
        { "Minimap Box Size", "minimapBoxSize", "slider", 80, 260, 10 },

        { "Zoom With The Mouse Wheel", "minimapWheel", "boolean" },

        { "Gather Addon Icons", "minimapCollect", "boolean" },

        { "Thin Out Stacked Map Pins", "thinPins", "boolean" },
        { "How Close Counts As Stacked", "pinSpacing", "slider", 6, 30, 1,
          nil, nil, "!thinPins" },

        { "Player Icons", "__s_playericons", "section", "playericons" },
        { "Replace Player Map Icons", "replacePlayerIcons", "boolean" },
        { "Player Map Icon Size", "playerIconSize", "slider", 8, 48, 1,
          nil, nil, "!replacePlayerIcons" },
        --[[ Two rows have gone from here. **The client's group dots** are no
             longer a switch -- see the note on `hideDefaultBlips`; they follow
             the row above. And a **retired size slider** was still being drawn,
             captioned `__retired_minimapIconSize`, which is a control wearing
             its own tombstone: the markers take `playerIconSize`, so it set a
             number nothing read. `minimapIconSize` stays in the defaults for a
             profile that holds one. ]]--

        { "Show Zoom Buttons", "minimapZoomButtons", "boolean" },
        { "Show The Mail Flag", "minimapMail", "boolean" },
        { "Show The Day & Night Button", "minimapDayNight", "boolean" },
        { "Show The Zone Name Bar", "minimapZoneBar", "boolean" },

        --[[ Dragged in edit mode with everything else rather than behind a
             switch of its own: one way to move things is one thing to learn. ]]--
        { "Put The Minimap Back", "__a_mmreset", "action",
          function() OB.modules.map:ResetMinimapPosition() end },

        --[[ Filed under the zone name rather than the world map. These label a
             zone with its level range; the tab they sat on is about a window
             they do not appear in. ]]--
        { "The Zone Name", "__s_zones", "section", "zone" },

        { "Show Zone Level Ranges", "zoneLevels", "boolean" },
        { "Color Them By Faction", "zoneFaction", "boolean",
          nil, nil, nil, nil, nil, "!zoneLevels" },

        { "The Zone Name", "__s_zone", "section", "zone" },

        --[[ Zero means "leave the client's own size alone", which is why the
             slider starts below its useful range rather than at it. ]]--
        { "Zone Name Size", "zoneSize", "slider", 0, 24, 1 },
        { "Zone Name Color", "zoneColor", "color", true },
    },

    --[==[ **A group change repaints the markers.**

         `StylePlayerMapIcons` reads each frame's unit and paints it in that
         class's own art, and it ran on entering the world and on changing zone
         -- neither of which is when a party changes. So `WorldMapParty1` kept
         whatever class it was given when the map module last applied, and a
         paladin who replaced a mage was drawn as a mage until the next zone.

         Reported as exactly that: the wrong colour, and a guess that it was
         left over from somebody who had been in the party before. It was. ]==]
    --[==[ **`WORLD_MAP_UPDATE` as well, which is the client redrawing its own
         markers.**

         The four above are all *our* reasons to repaint: somebody joined, the
         zone changed, you logged in. None of them is the client deciding to
         paint over what we drew -- and the client owns these frames and places
         them itself whenever the map refreshes, which is on a timer for as long
         as the map is open.

         Added for a green square behind the party markers and not the raid
         ones. Both go through the same walk here, so the difference cannot be
         in this module; the client repainting one set after us and not the
         other accounts for it exactly, and running again after the client is
         the answer whether or not that is the cause. ]==]
    events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
               "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE",
               "WORLD_MAP_UPDATE" },

    requires = { "GetGameTime", "getglobal" },

    --[[ Ticked for the time and the coordinates, which are the only things
         here that change on their own. Everything else answers a setting or an
         event. ]]--
    tickly = true,
})

function M:Config()
    return OB.profile.modules.map
end

-- ---------------------------------------------------------------------------
-- the world map
-- ---------------------------------------------------------------------------

local WORLD_MAP_MIN_SCALE = 0.40
local WORLD_MAP_MAX_SCALE = 2.50

-- The map may deliberately be larger than the viewport. 250% leaves plenty
-- of headroom while still preventing an accidental runaway scale.
function M:ClampWorldMapScale(scale)
    scale = tonumber(scale) or 0.7

    -- Do not cap the map to the physical size of UIParent. A large world map is
    -- useful precisely because it can be larger than the screen and then be
    -- dragged around. The only ceiling is the explicit Map Size limit.
    if scale < WORLD_MAP_MIN_SCALE then scale = WORLD_MAP_MIN_SCALE end
    if scale > WORLD_MAP_MAX_SCALE then scale = WORLD_MAP_MAX_SCALE end
    return scale
end


--[[ `WorldMapFrame:SetScale()` only changes how large the artwork looks.  On
     1.12 the frame is still registered with UIParent as an `area = "full"`
     panel, so opening the shrunken map still takes over the UI and blocks normal
     movement/input.  The map therefore has to be made a real centre panel, not
     merely a smaller fullscreen panel.  We keep Blizzard's frame and all of its
     children so pfQuest/Questie pins stay attached to the frame they expect. ]]--
local function RememberPoints(frame)
    local out = {}
    if not frame or not frame.GetPoint then return out end

    local count = 1
    if frame.GetNumPoints then count = frame:GetNumPoints() or 0 end

    for i = 1, count do
        local point, rel, relPoint, x, y = frame:GetPoint(i)
        if point then table.insert(out, { point, rel, relPoint, x, y }) end
    end

    return out
end

local function RestorePoints(frame, points)
    if not frame or not frame.SetPoint then return end
    frame:ClearAllPoints()

    for i = 1, table.getn(points or {}) do
        local p = points[i]
        frame:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
    end
end

local function SpecialFrameIndex(name)
    if type(UISpecialFrames) ~= "table" then return nil end

    for i = 1, table.getn(UISpecialFrames) do
        if UISpecialFrames[i] == name then return i end
    end

    return nil
end

function M:RememberWorldMapWindow()
    if self.worldMapOriginal then return self.worldMapOriginal end

    local frame = getglobal("WorldMapFrame")
    if not frame then return nil end

    --[[ A UI reload can leave the previous ECO closure on the global while the
         module table itself is rebuilt.  Do not mistake our old wrapper for the
         client's original toggle and stack another wrapper onto it. ]]--
    local originalToggle = ToggleWorldMap
    if EquadisOverhaulWorldMapToggle
            and originalToggle == EquadisOverhaulWorldMapToggle
            and EquadisOverhaulWorldMapToggleInner then
        originalToggle = EquadisOverhaulWorldMapToggleInner
    end

    local blackout = getglobal("BlackoutWorld")
    local keyboard
    if frame.IsKeyboardEnabled then keyboard = frame:IsKeyboardEnabled() end

    local mouse
    if frame.IsMouseEnabled then mouse = frame:IsMouseEnabled() end

    self.worldMapOriginal = {
        panel = type(UIPanelWindows) == "table" and UIPanelWindows["WorldMapFrame"] or nil,
        toggle = originalToggle,
        width = frame.GetWidth and frame:GetWidth() or nil,
        height = frame.GetHeight and frame:GetHeight() or nil,
        scale = frame.GetScale and frame:GetScale() or 1,
        alpha = frame.GetAlpha and frame:GetAlpha() or 1,
        strata = frame.GetFrameStrata and frame:GetFrameStrata() or nil,
        clamped = frame.IsClampedToScreen and frame:IsClampedToScreen() or nil,
        keyboard = keyboard,
        mouse = mouse,
        points = RememberPoints(frame),
        special = SpecialFrameIndex("WorldMapFrame") ~= nil,
        blackoutShown = blackout and blackout.IsShown and blackout:IsShown() or nil,
    }

    return self.worldMapOriginal
end

function M:ApplyWorldMapWindowGeometry(place)
    local frame = getglobal("WorldMapFrame")
    if not frame then return false end

    --[[ **Do not resize or directly re-anchor WorldMapFrame.**

         The 1.12 map's OnShow calls SetupFullscreenScale and its OnUpdate code
         calculates player/raid marker positions from the stock 1024x768
         positioning guide. Changing the frame's width/height (or showing it
         directly before UIParent has initialised it) can make GetCenter() return
         nil inside WorldMapButton_OnUpdate -- the familiar `centerY` arithmetic
         error that leaves the map unusable.

         Windowed mode therefore keeps Blizzard's geometry intact. The parent is
         only *scaled* after a normal ShowUIPanel path, while UIPanelWindows is
         changed from `full` to `center` so UIParent stays visible and the player
         can keep moving. ]]--
    if frame.EnableKeyboard then frame:EnableKeyboard(false) end

    -- The stock map paints an opaque black 1024x768 texture because it expects
    -- UIParent itself to be hidden. In centre-panel mode UIParent remains up, so
    -- remove only that blackout; every actual map/art/pin stays untouched.
    local blackout = getglobal("BlackoutWorld")
    if blackout and blackout.Hide then blackout:Hide() end

    return true
end

function M:InstallWorldMapWindow()
    local frame = getglobal("WorldMapFrame")
    if not frame then return false end

    self:RememberWorldMapWindow()

    -- The key change: make Blizzard open the map as an ordinary centre panel.
    -- We still go through its own ToggleWorldMap -> ShowUIPanel/HideUIPanel
    -- path, because a raw `WorldMapFrame:Show()` on 1.12 can run the map's
    -- OnUpdate before its positioning guide has a centre and crash on centerY.
    if type(UIPanelWindows) == "table" then
        UIPanelWindows["WorldMapFrame"] = { area = "center", pushable = 0, whileDead = 1 }
    end

    if not self.worldMapToggle then
        self.worldMapToggle = function()
            local mapModule = EquadisClassicOverhaul
                    and EquadisClassicOverhaul.modules
                    and EquadisClassicOverhaul.modules.map
            local world = getglobal("WorldMapFrame")
            if not world then return end

            local original = mapModule and mapModule.worldMapOriginal
                    and mapModule.worldMapOriginal.toggle

            -- Use the client's normal panel path. This is deliberately *not*
            -- world:Show()/Hide(): direct Show is what produces the nil-centerY
            -- failure on old clients and some Turtle/Octo FrameXML forks.
            if type(original) == "function" and original ~= ToggleWorldMap then
                original()
            elseif world:IsShown() then
                if type(HideUIPanel) == "function" then HideUIPanel(world)
                else world:Hide() end
            else
                if type(ShowUIPanel) == "function" then ShowUIPanel(world)
                else world:Show() end
            end

            -- WorldMapFrame's own OnShow runs SetupFullscreenScale, so apply
            -- ECO's scale *after* the normal show has completely initialised it.
            if mapModule and world:IsShown() then
                mapModule:ApplyWorldMapWindowGeometry(false)

                local cfg = mapModule:Config()
                local scale = mapModule:ClampWorldMapScale(cfg.mapScale)
                cfg.mapScale = scale
                if world.SetScale then world:SetScale(scale) end
                if world.SetAlpha then world:SetAlpha(tonumber(cfg.mapAlpha) or 1) end

                mapModule:SetMapMovable(true)
                mapModule:SetMapResizable(true)
                mapModule:PlaceWorldMap()
                mapModule:RefreshMapCoordinates(true)
            end
        end
    end

    EquadisOverhaulWorldMapToggleInner = self.worldMapOriginal
            and self.worldMapOriginal.toggle or ToggleWorldMap
    EquadisOverhaulWorldMapToggle = self.worldMapToggle
    ToggleWorldMap = self.worldMapToggle

    self:ApplyWorldMapWindowGeometry(false)
    return true
end

function M:RestoreWorldMapWindow()
    local frame = getglobal("WorldMapFrame")
    local snap = self.worldMapOriginal
    if not frame or not snap then return false end

    if type(UIPanelWindows) == "table" then
        UIPanelWindows["WorldMapFrame"] = snap.panel
    end

    if ToggleWorldMap == self.worldMapToggle or ToggleWorldMap == EquadisOverhaulWorldMapToggle then
        ToggleWorldMap = snap.toggle
    end

    if self.worldMapSpecialAdded and type(UISpecialFrames) == "table" then
        local i = SpecialFrameIndex("WorldMapFrame")
        if i then table.remove(UISpecialFrames, i) end
    end
    self.worldMapSpecialAdded = nil

    if frame.SetWidth and snap.width then frame:SetWidth(snap.width) end
    if frame.SetHeight and snap.height then frame:SetHeight(snap.height) end
    if frame.SetScale then frame:SetScale(snap.scale or 1) end
    if frame.SetAlpha then frame:SetAlpha(snap.alpha or 1) end
    if frame.SetFrameStrata and snap.strata then frame:SetFrameStrata(snap.strata) end
    if frame.SetClampedToScreen and snap.clamped ~= nil then
        frame:SetClampedToScreen(snap.clamped)
    end
    if frame.EnableKeyboard and snap.keyboard ~= nil then frame:EnableKeyboard(snap.keyboard) end

    --[[ A fullscreen map wants the mouse back: there is nothing behind it to
         click, and the frame is what stops a click reaching the world. ]]--
    if frame.EnableMouse and snap.mouse ~= nil then frame:EnableMouse(snap.mouse) end
    RestorePoints(frame, snap.points)

    local blackout = getglobal("BlackoutWorld")
    if blackout and snap.blackoutShown ~= nil then
        if snap.blackoutShown then blackout:Show() else blackout:Hide() end
    end

    self.worldMapWindowPlaced = nil
    self.worldMapWasShown = nil
    self.mapDragEnabled = nil
    self.mapResizeState = nil
    self.mapDragState = nil
    self:ResumeWorldMapButtonUpdate()
    if self.mapResizeGrip then self.mapResizeGrip:Hide() end
    if self.mapDragHandles then
        for i = 1, table.getn(self.mapDragHandles) do self.mapDragHandles[i]:Hide() end
    end
    return true
end

--[[ WorldMapButton_OnUpdate assumes that its positioning guide has a valid
     centre every single frame. Vanilla's StartMoving() temporarily breaks that
     assumption on some 1.12/Turtle builds, producing the FrameXML centerY=nil
     error. We therefore move the map ourselves with atomic SetPoint calls
     instead of ever calling StartMoving on WorldMapFrame. ]]--
function M:WorldMapPhysicalBounds()
    local frame = getglobal("WorldMapFrame")
    if not frame or not frame.GetWidth or not frame.GetHeight then return nil end

    local width, height = frame:GetWidth(), frame:GetHeight()
    local effective = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not width or not height or width <= 0 or height <= 0
            or not effective or effective <= 0 then
        return nil
    end

    local left = frame.GetLeft and frame:GetLeft() or nil
    local top = frame.GetTop and frame:GetTop() or nil
    if not left or not top then
        local cx, cy
        if frame.GetCenter then cx, cy = frame:GetCenter() end
        if not cx or not cy then return nil end
        left = cx - width / 2
        top = cy + height / 2
    end

    left = left * effective
    top = top * effective
    local shownWidth = width * effective
    local shownHeight = height * effective
    return left, top, left + shownWidth, top - shownHeight, shownWidth, shownHeight
end

local function WorldMapParentPhysicalBounds()
    if not UIParent or not UIParent.GetWidth or not UIParent.GetHeight then return nil end

    local scale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if not scale or scale <= 0 then scale = 1 end

    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return nil end

    local left = UIParent.GetLeft and UIParent:GetLeft() or nil
    local top = UIParent.GetTop and UIParent:GetTop() or nil
    if not left or not top then
        local cx, cy
        if UIParent.GetCenter then cx, cy = UIParent:GetCenter() end
        if not cx or not cy then return nil end
        left = cx - width / 2
        top = cy + height / 2
    end

    left = left * scale
    top = top * scale
    return left, top, left + width * scale, top - height * scale, scale
end

-- The old v4 clamp kept the entire map inside UIParent. At larger sizes that
-- leaves almost no room to move, which feels like the map is trapped in a box.
-- During an actual drag we now do *no* positional clamp at all. This recovery
-- clamp is used only when reopening/reloading, and merely keeps 36 pixels of the
-- map reachable if a saved position no longer fits the current resolution.
function M:ClampWorldMapTopLeft(left, top)
    left, top = tonumber(left), tonumber(top)
    if not left or not top then return left or 0, top or 0 end

    local _, _, _, _, shownWidth, shownHeight = self:WorldMapPhysicalBounds()
    local parentLeft, parentTop, parentRight, parentBottom = WorldMapParentPhysicalBounds()
    if not shownWidth or not shownHeight or not parentLeft then return left, top end

    local visible = 36
    local minLeft = parentLeft - shownWidth + visible
    local maxLeft = parentRight - visible
    local minTop = parentBottom + visible
    local maxTop = parentTop + shownHeight - visible

    if left < minLeft then left = minLeft elseif left > maxLeft then left = maxLeft end
    if top < minTop then top = minTop elseif top > maxTop then top = maxTop end
    return left, top
end

-- Anchor the map by its *visual* top-left corner in physical screen pixels.
-- Recomputing the TOPLEFT offset for the current effective scale is what makes
-- scale changes grow only toward bottom-right instead of around the centre.
function M:SetWorldMapTopLeft(left, top, save, recover)
    local frame = getglobal("WorldMapFrame")
    if not frame or not frame.SetPoint or not UIParent then return false end

    left, top = tonumber(left), tonumber(top)
    if not left or not top then return false end
    if recover then left, top = self:ClampWorldMapTopLeft(left, top) end

    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not frameScale or frameScale <= 0 then frameScale = 1 end

    local parentLeft, parentTop = WorldMapParentPhysicalBounds()
    if not parentLeft or not parentTop then return false end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
            (left - parentLeft) / frameScale,
            (top - parentTop) / frameScale)

    if save then
        self:Config().mapPosition = { left = left, top = top }
    end
    return true
end

function M:SetWorldMapOffset(x, y, save)
    local frame = getglobal("WorldMapFrame")
    if not frame or not UIParent then return false end

    x, y = tonumber(x) or 0, tonumber(y) or 0
    local parentLeft, parentTop, parentRight, parentBottom, parentScale = WorldMapParentPhysicalBounds()
    local _, _, _, _, shownWidth, shownHeight = self:WorldMapPhysicalBounds()
    if not parentLeft or not parentScale or not shownWidth or not shownHeight then return false end

    local pcx = (parentLeft + parentRight) / 2
    local pcy = (parentTop + parentBottom) / 2
    local centreX = pcx + x * parentScale
    local centreY = pcy + y * parentScale
    return self:SetWorldMapTopLeft(
            centreX - shownWidth / 2,
            centreY + shownHeight / 2,
            save, false)
end

function M:StoreWorldMapPosition()
    local left, top = self:WorldMapPhysicalBounds()
    if not left or not top then return false end
    self:Config().mapPosition = { left = left, top = top }
    return true
end

function M:PlaceWorldMap()
    local cfg = self:Config()
    local saved = cfg and cfg.mapPosition

    if saved and saved.left and saved.top then
        return self:SetWorldMapTopLeft(saved.left, saved.top, true, true)
    end

    if saved and (saved.x or saved.y) then
        -- One-time migration from the centre-offset format used by v1-v4.
        if self:SetWorldMapOffset(saved.x or 0, saved.y or 0, false) then
            local left, top = self:WorldMapPhysicalBounds()
            if left and top then return self:SetWorldMapTopLeft(left, top, true, true) end
        end
    end

    local left, top = self:WorldMapPhysicalBounds()
    if not left or not top then return false end
    return self:SetWorldMapTopLeft(left, top, false, true)
end


-- Pause only the stock hover/click coordinate updater while the frame is in
-- motion. That function is exactly where FrameXML line 493 does arithmetic on
-- WorldMapButton:GetCenter(); freezing it for the fraction of a second spent
-- dragging/resizing removes the transient nil-center race without touching any
-- map texture, pin, or navigation logic.
function M:PauseWorldMapButtonUpdate()
    if self.worldMapButtonUpdatePaused then return true end
    local button = getglobal("WorldMapButton")
    if not button or not button.GetScript or not button.SetScript then return false end

    self.worldMapButtonUpdateScript = button:GetScript("OnUpdate")
    button:SetScript("OnUpdate", nil)
    self.worldMapButtonUpdatePaused = true
    return true
end

function M:ResumeWorldMapButtonUpdate()
    if self.mapDragState or self.mapResizeState then return false end
    if not self.worldMapButtonUpdatePaused then return true end
    local button = getglobal("WorldMapButton")
    if button and button.SetScript then
        button:SetScript("OnUpdate", self.worldMapButtonUpdateScript)
    end
    self.worldMapButtonUpdateScript = nil
    self.worldMapButtonUpdatePaused = nil
    return true
end

function M:MapCoordinateStrings()
    if self.mapCursorCoordinates and self.mapPlayerCoordinates then
        return self.mapCursorCoordinates, self.mapPlayerCoordinates
    end

    local button = getglobal("WorldMapButton")
    if not button or not button.CreateFontString then return nil, nil end

    local cursor = button:CreateFontString(
            "EquadisClassicOverhaulMapCursorCoordinates", "OVERLAY", "GameFontNormalSmall")
    cursor:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 8)
    cursor:SetJustifyH("LEFT")

    local player = button:CreateFontString(
            "EquadisClassicOverhaulMapPlayerCoordinates", "OVERLAY", "GameFontNormalSmall")
    player:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 8)
    player:SetJustifyH("RIGHT")

    self.mapCursorCoordinates = cursor
    self.mapPlayerCoordinates = player
    return cursor, player
end

--[==[ **Somebody else is already drawing coordinates in that corner.**

     Reported as two cursor positions overlapping at the bottom left of the world
     map. It is not TomTom -- disabled on every character here -- and no other
     installed addon draws one, so it is the client's own: this build shows map
     coordinates natively, in the corner this module puts its own.

     **The frame cannot be named from here.** It is a client frame on a fork,
     there is no reference to it in any addon on this machine, and guessing a
     global is how an addon ends up silently doing nothing. So it is found by
     what it *is* rather than by what it is called: a font string on the world
     map, not one of ours, currently reading like a pair of coordinates.

     **Alpha rather than `Hide`.** Whatever draws it will show it again on its
     own schedule, and a hide that has to win a race is the fault that took three
     goes to settle on the buff timers. Alpha survives `Show` and `SetText`.

     Found once and remembered. `/eq mapdebug` prints what was found, so if this
     ever grabs the wrong string there is one command that says so rather than a
     guess. ]==]
local COORD_PATTERN = "%d+%.?%d*%s*,%s*%d+%.?%d*"

function M:ForeignCoordinateStrings()
    self.foreignCoords = self.foreignCoords or {}

    local map = getglobal("WorldMapFrame")
    if not map or not map.GetRegions then return self.foreignCoords end

    local ours = {}
    if self.mapCursorCoordinates then ours[self.mapCursorCoordinates] = true end
    if self.mapPlayerCoordinates then ours[self.mapPlayerCoordinates] = true end

    --[[ The map frame's own regions and those of its children one deep, which is
         where a client puts a label like this. Deeper is the pin layer, and a
         pin's text is not what this is looking for. ]]--
    local function consider(region)
        if not region or ours[region] then return end
        if type(region.GetText) ~= "function" then return end
        if not region.SetAlpha then return end

        local text = region:GetText()
        if type(text) ~= "string" or text == "" then return end

        --[[ Ours are excluded by identity above; anything else reading like a
             coordinate pair is the duplicate. ]]--
        if not string.find(text, COORD_PATTERN) then return end

        for i = 1, table.getn(self.foreignCoords) do
            if self.foreignCoords[i] == region then return end
        end

        table.insert(self.foreignCoords, region)
    end

    local function scan(frame)
        if not frame or type(frame.GetRegions) ~= "function" then return end

        local regions = { frame:GetRegions() }
        for i = 1, table.getn(regions) do consider(regions[i]) end
    end

    scan(map)

    if type(map.GetChildren) == "function" then
        local kids = { map:GetChildren() }
        for i = 1, table.getn(kids) do scan(kids[i]) end
    end

    return self.foreignCoords
end

--[[ Silenced while ours is drawn, and handed back the moment it is not. ]]--
function M:SilenceForeignCoordinates(on)
    local found = self:ForeignCoordinateStrings()

    for i = 1, table.getn(found) do
        local region = found[i]

        if region and region.SetAlpha then
            local wanted = on and 0 or 1

            if not region.GetAlpha or region:GetAlpha() ~= wanted then
                region:SetAlpha(wanted)
            end
        end
    end

    return table.getn(found)
end

--[==[ **What is drawing coordinates on this map, and which of them is ours.**

     The duplicate readout cannot be named from here -- it is a client frame on a
     fork with no reference to it in any addon on this machine -- so it is found
     by shape, and a thing found by shape needs a way to say what it caught. One
     command rather than a guess.

     Prints every font string on the world map carrying a coordinate-looking
     pair, with its name where it has one, whether this addon owns it, and its
     corner. If this ever silences something it should not, this is the line that
     says so. ]==]
function M:DebugCoordinates()
    local say = function(msg) OB.Print(msg, "Map") end

    local map = getglobal("WorldMapFrame")
    if not map then say("no world map frame."); return false end

    if not (map.IsShown and map:IsShown()) then
        say("open the world map first, and hover it so the numbers have text.")
    end

    say("ours: cursor=" .. tostring(self.mapCursorCoordinates
                    and self.mapCursorCoordinates:GetText())
            .. " player=" .. tostring(self.mapPlayerCoordinates
                    and self.mapPlayerCoordinates:GetText()))

    local found = self:ForeignCoordinateStrings()
    say("others found: " .. table.getn(found))

    for i = 1, table.getn(found) do
        local region = found[i]
        local name = region.GetName and region:GetName() or nil
        local point = region.GetPoint and region:GetPoint(1) or nil

        say("  " .. i .. ": " .. (name or "(unnamed)")
                .. "  [" .. tostring(region.GetText and region:GetText()) .. "]"
                .. "  at " .. tostring(point)
                .. "  alpha " .. tostring(region.GetAlpha and region:GetAlpha()))
    end

    if table.getn(found) == 0 then
        say("nothing else is drawing a coordinate pair right now. If two are "
                .. "still showing, hover the map and run this again -- a string "
                .. "with no text cannot be recognised.")
    end

    return true
end

function M:RefreshMapCoordinates(force)
    local cursorText, playerText = self:MapCoordinateStrings()
    if not cursorText or not playerText then return false end

    local cfg = self:Config()
    local world = getglobal("WorldMapFrame")
    local button = getglobal("WorldMapButton")
    local visible = OB.ModuleEnabled("map") and cfg.mapCoordinates
            and world and world.IsShown and world:IsShown() and button

    if not visible then
        cursorText:Hide()
        playerText:Hide()

        --[[ Whoever else draws them gets their corner back. ]]--
        self:SilenceForeignCoordinates(false)
        return false
    end

    cursorText:Show()
    playerText:Show()

    self:SilenceForeignCoordinates(true)

    if OB.ApplyFont then
        OB.ApplyFont(cursorText, 11, "map")
        OB.ApplyFont(playerText, 11, "map")
    end

    local px, py
    if type(GetPlayerMapPosition) == "function" then px, py = GetPlayerMapPosition("player") end

    if px and py and (px > 0 or py > 0) then
        playerText:SetText(format("Player: %.1f, %.1f", px * 100, py * 100))
    else
        playerText:SetText("Player: --, --")
    end

    if type(MouseIsOver) == "function" and MouseIsOver(button)
            and type(GetCursorPosition) == "function" and button.GetCenter then
        local width, height = button:GetWidth(), button:GetHeight()
        local mx, my = button:GetCenter()
        local scale = button.GetEffectiveScale and button:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()

        if width and height and width > 0 and height > 0 and mx and my and scale and scale > 0 then
            local cx = (((x / scale) - (mx - width / 2)) / width) * 100
            local cy = (((my + height / 2) - (y / scale)) / height) * 100

            if cx >= 0 and cx <= 100 and cy >= 0 and cy <= 100 then
                cursorText:SetText(format("Cursor: %.1f, %.1f", cx, cy))
            else
                cursorText:SetText("")
            end
        else
            cursorText:SetText("")
        end
    else
        cursorText:SetText("")
    end

    return true
end

function M:ApplyMap()
    local frame = getglobal("WorldMapFrame")
    if not frame or not frame.SetScale then return false end

    local cfg = self:Config()

    if not OB.ModuleEnabled("map") or not cfg.scaleMap then
        self:RestoreWorldMapWindow()
        frame:SetScale(1)
        if frame.SetAlpha then frame:SetAlpha(1) end
        self:SetMapMovable(false)
        self:SetMapResizable(false)
        self:RefreshMapCoordinates(true)
        return false
    end

    self:InstallWorldMapWindow()

    local scale = self:ClampWorldMapScale(cfg.mapScale)
    cfg.mapScale = scale

    frame:SetScale(scale)
    if frame.SetAlpha then frame:SetAlpha(tonumber(cfg.mapAlpha) or 1) end

    --[==[ **The map's own frame stops swallowing the mouse.**

         `WorldMapFrame` is `setAllPoints="true"` and `enableMouse="true"` in the
         client's own XML -- a screen-sized frame that takes every button press
         over it. That is right for a fullscreen map, where there is nothing
         behind it to click.

         Windowed, it is wrong twice over. The frame still covers far more than
         the map you can see, and a mouse-enabled frame in 1.12 eats *every*
         button, not merely the ones it has a handler for -- so right-click to
         turn the camera died in a wide region around the map, while the far
         edges of the screen still worked. That is the shape of the report:
         fine at the outskirts, dead near the map.

         Only the container is released. `WorldMapButton` is the map picture and
         has its own mouse, so clicking the map still does what it did; the
         drag strips and the resize grip are ECO's own frames and keep theirs.
         What is given back is the empty space the container was claiming.

         Recorded before it is changed, and put back by `RestoreWorldMapWindow`
         -- a fullscreen map needs it. ]==]
    if frame.EnableMouse then frame:EnableMouse(false) end

    self:SetMapMovable(true)
    self:SetMapResizable(true)
    if frame.IsShown and frame:IsShown() then self:PlaceWorldMap() end
    self:RefreshMapCoordinates(true)
    return true
end

--[[ Dragging uses thin UIParent-level hit strips that sit on the decorative
     border. They are independent of WorldMapButton, so changing between world,
     continent, and zone map modes cannot steal the drag surface. ]]--
function M:MapDragHandles()
    if self.mapDragHandles then return self.mapDragHandles end

    local frame = getglobal("WorldMapFrame")
    if not frame or not UIParent then return nil end

    local function NewHandle(name)
        local h = CreateFrame("Button", name, UIParent)
        if h.EnableMouse then h:EnableMouse(true) end
        if h.SetFrameStrata then h:SetFrameStrata("TOOLTIP") end
        if h.SetFrameLevel then h:SetFrameLevel(90) end
        h:SetScript("OnMouseDown", function()
            if arg1 and arg1 ~= "LeftButton" then return end
            OB.modules.map:BeginMapDrag()
        end)
        h:SetScript("OnMouseUp", function()
            if arg1 and arg1 ~= "LeftButton" then return end
            OB.modules.map:StopMapDrag()
        end)
        h:Hide()
        return h
    end

    local top = NewHandle("EquadisClassicOverhaulMapDragTop")
    top:SetHeight(10)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -1)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -72, -1)

    local left = NewHandle("EquadisClassicOverhaulMapDragLeft")
    left:SetWidth(12)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -12)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 12)

    local right = NewHandle("EquadisClassicOverhaulMapDragRight")
    right:SetWidth(12)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -12)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 52)

    local bottom = NewHandle("EquadisClassicOverhaulMapDragBottom")
    bottom:SetHeight(12)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 1)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -52, 1)

    -- One shown handle can drive the drag no matter which border started it.
    top:SetScript("OnUpdate", function()
        local mapModule = OB.modules and OB.modules.map
        if not mapModule or not mapModule.mapDragState then return end
        if type(IsMouseButtonDown) == "function"
                and not IsMouseButtonDown("LeftButton") then
            mapModule:StopMapDrag()
        else
            mapModule:StepMapDrag()
        end
    end)

    self.mapDragHandles = { top, left, right, bottom }

    --[[ Kept so `SyncMapFurniture` can put them back after a scale change,
         without a second copy of the offsets above to fall out of step. ]]--
    for i = 1, table.getn(self.mapDragHandles) do
        self.mapDragHandles[i].ecoAnchor = RememberPoints(self.mapDragHandles[i])
    end

    return self.mapDragHandles
end

function M:SetMapMovable(on)
    local frame = getglobal("WorldMapFrame")
    local handles = self:MapDragHandles()
    if not frame or not handles then return false end

    -- Explicitly remove the old StartMoving path from v1-v3. StartMoving on
    -- WorldMapFrame is what can make WorldMapButton:GetCenter() nil mid-frame.
    if frame.RegisterForDrag then frame:RegisterForDrag() end
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)

    local show = on and frame.IsShown and frame:IsShown()
    for i = 1, table.getn(handles) do
        if show then handles[i]:Show() else handles[i]:Hide() end
    end

    if not on and self.mapDragState then
        self.mapDragState = nil
        self:ResumeWorldMapButtonUpdate()
    end

    self.mapDragEnabled = on and true or false
    if on and OB.MarkMovable then OB.MarkMovable(frame, "World Map") end
    return on and true or false
end

--[==[ **One notch of the size slider per click of the wheel.**

     The same number, so the two controls cannot disagree about what a step is:
     the slider moves in fives of a percent and so does this.

     **Grown about its centre, in all four directions.** The grip pins the
     top-left because a grip is a corner you are holding: you dragged the
     bottom-right, so the bottom-right is the only thing that should move. A
     wheel is not a corner. There is nothing being held, so pinning one is
     picking a direction for the map to run in -- and it ran down and to the
     right until it was off the screen.

     The minimap answers this the same way for the same reason: its wheel
     resizes about `CENTER` and its four grips each pin their opposite corner.

     The centre is read *before* the scale changes and the frame re-anchored to
     put it back afterwards. A scale change grows a frame about its own anchor
     point, so nothing about it is centred on its own.

     Refuses while a drag or a resize is in progress: both of those own the
     frame's position for the length of the gesture, and a scale change
     underneath them would be measured against a corner that has already
     moved. ]==]
local WORLD_MAP_WHEEL_STEP = 0.05

function M:ZoomWorldMap(direction)
    local frame = getglobal("WorldMapFrame")
    if not frame or not frame.SetScale or not frame.GetScale then return false end
    if not frame.IsShown or not frame:IsShown() then return false end
    if self.mapDragState or self.mapResizeState then return false end

    local step = (direction or 0) > 0 and WORLD_MAP_WHEEL_STEP or -WORLD_MAP_WHEEL_STEP
    local was = self:ClampWorldMapScale(frame:GetScale())
    local want = self:ClampWorldMapScale(was + step)

    --[[ At either limit nothing changes, and re-anchoring regardless would walk
         the map a pixel per click at the end of the range -- the same trap
         `ResizeMinimap` returns false for. ]]--
    if math.abs(want - was) < 0.0005 then return false end

    --[[ Read before the scale changes. Afterwards it is the centre of a frame
         that has already grown about its anchor, which is the thing being
         preserved. ]]--
    local left, top, right, bottom = self:WorldMapPhysicalBounds()
    local centreX, centreY
    if left and right then centreX = (left + right) / 2 end
    if top and bottom then centreY = (top + bottom) / 2 end

    frame:SetScale(want)
    self:Config().mapScale = want

    if centreX and centreY then
        local _, _, _, _, shownWidth, shownHeight = self:WorldMapPhysicalBounds()

        if shownWidth and shownHeight then
            self:SetWorldMapTopLeft(centreX - shownWidth / 2,
                    centreY + shownHeight / 2, true, false)
        end
    end

    self:SyncMapFurniture()
    if OB.RefreshPanel then OB.RefreshPanel() end

    return true
end

--[==[ **The grip and the drag strips hang off the map and have to be told when
     it changes size.**

     They are `UIParent` children anchored across to `WorldMapFrame`, which is
     deliberate -- `WorldMapButton` is a mouse layer covering practically the
     whole window and wins the click against any child of the map, however high
     its frame level. The cost of living outside that hierarchy is that they are
     anchored across a scale boundary, and a cross-scale anchor set at one scale
     does not survive the frame being scaled to another: the grip ends up sitting
     a visible distance away from the corner it belongs to.

     Re-applied from the points each of them was built with, rather than from a
     second copy of those numbers written here -- which is how the four strips
     would come to disagree with the four `SetPoint` calls that made them. ]==]
function M:SyncMapFurniture()
    local synced = 0

    local function reanchor(frame)
        if not frame or not frame.ecoAnchor then return end
        RestorePoints(frame, frame.ecoAnchor)
        synced = synced + 1
    end

    reanchor(self.mapResizeGrip)

    local handles = self.mapDragHandles
    if handles then
        for i = 1, table.getn(handles) do reanchor(handles[i]) end
    end

    return synced > 0
end

--[==[ **Wired on every frame that can be under the cursor, not just the map.**

     `WorldMapButton` is a mouse layer covering practically the whole map, and
     the drag handles sit on the border above everything. An unhandled wheel does
     not reliably reach the parent on 1.12 -- the database filter's rows were the
     same bug -- so a handler on `WorldMapFrame` alone is a handler that fires
     only where there is nothing to fire over.

     One closure, shared, so there is one behaviour rather than four that can
     drift apart. ]==]
function M:WorldMapWheelFrames()
    local out = {}
    local names = { "WorldMapFrame", "WorldMapButton", "WorldMapDetailFrame" }

    for i = 1, table.getn(names) do
        local frame = getglobal(names[i])
        if frame and frame.EnableMouseWheel then table.insert(out, frame) end
    end

    --[[ Created lazily, so asked for rather than assumed: before the map has
         been opened once there are none, and after it there are five. ]]--
    local handles = self.mapDragHandles
    if handles then
        for i = 1, table.getn(handles) do
            local h = handles[i]
            if h and h.EnableMouseWheel then table.insert(out, h) end
        end
    end

    local grip = self.mapResizeGrip
    if grip and grip.EnableMouseWheel then table.insert(out, grip) end

    return out
end

function M:StyleWorldMapWheel()
    local frames = self:WorldMapWheelFrames()
    if table.getn(frames) == 0 then return false end

    local cfg = self:Config()
    --[==[ **Always on, because a resize gesture is not a preference.**

         This was a switch, and a switch on "can I resize the map" is a switch
         nobody sets to off on purpose -- the gesture costs nothing when it is
         not used, since it needs Control held down. Asked for in those words:
         remove the setting, keep the behaviour.

         The stored key is left where it is rather than migrated away: it is one
         boolean in a saved profile, nothing reads it any more, and a migration
         that deletes settings is a migration that can delete the wrong one. ]==]
    local on = OB.ModuleEnabled("map")

    if not self.worldMapWheelScript then
        self.worldMapWheelScript = function()
            --[==[ **Control only.** Held rather than toggled, so there is no
                 mode to be left in, and the bare wheel is left to whatever else
                 wants it -- a quest addon's own map scrolling, or nothing. ]==]
            if not IsControlKeyDown or not IsControlKeyDown() then return end
            OB.modules.map:ZoomWorldMap(arg1)
        end
    end

    for i = 1, table.getn(frames) do
        local frame = frames[i]

        if on then
            frame:EnableMouseWheel(true)
            frame:SetScript("OnMouseWheel", self.worldMapWheelScript)
        elseif frame:GetScript("OnMouseWheel") == self.worldMapWheelScript then
            --[[ Only ours is taken off. Another addon's handler on the same
                 frame is not this module's to remove. ]]--
            frame:EnableMouseWheel(false)
            frame:SetScript("OnMouseWheel", nil)
        end
    end

    return on and true or false
end

function M:BeginMapDrag()
    local frame = getglobal("WorldMapFrame")
    if not self.mapDragEnabled or self.mapResizeState
            or not frame or not frame.IsShown or not frame:IsShown() then
        return false
    end
    if type(GetCursorPosition) ~= "function" then return false end

    local left, top = self:WorldMapPhysicalBounds()
    if not left or not top then return false end

    local x, y = GetCursorPosition()
    self:PauseWorldMapButtonUpdate()
    self.mapDragState = {
        cursorX = x,
        cursorY = y,
        startLeft = left,
        startTop = top,
    }
    return true
end

function M:StepMapDrag()
    local state = self.mapDragState
    if not state then return false end

    local frame = getglobal("WorldMapFrame")
    if not frame or not frame.IsShown or not frame:IsShown() then
        self.mapDragState = nil
        self:ResumeWorldMapButtonUpdate()
        return false
    end

    local x, y = GetCursorPosition()
    -- CursorPosition is already in physical screen pixels, as are the stored
    -- map edges. No UIParent clamp or scale conversion is needed here.
    return self:SetWorldMapTopLeft(
            state.startLeft + (x - state.cursorX),
            state.startTop + (y - state.cursorY),
            true, false)
end

function M:StopMapDrag()
    if not self.mapDragState then return false end
    self:StepMapDrag()
    self.mapDragState = nil
    self:ResumeWorldMapButtonUpdate()
    self:StoreWorldMapPosition()
    return true
end


--[[ Resize by changing the map's scale, never its 1024x768 geometry. Vanilla's
     WorldMapButton_OnUpdate assumes those stock dimensions; changing them is
     what caused the old nil-center and clipped-map failures. A small visible
     grabber is shown in the bottom-right corner while the existing map
     border/artwork remains otherwise untouched. ]]--
function M:MapResizeGrip()
    if self.mapResizeGrip then return self.mapResizeGrip end

    local frame = getglobal("WorldMapFrame")
    if not frame or not UIParent then return nil end

    -- Keep the hit target OUTSIDE WorldMapFrame's child hierarchy.  On the
    -- 1.12/Turtle FrameXML the WorldMapButton mouse layer covers practically
    -- the whole window and can win the click even when a child grip has a
    -- higher frame level.  A UIParent-level overlay is reliably above that
    -- hierarchy while still following the map through a cross-frame anchor.
    local grip = CreateFrame("Button", "EquadisClassicOverhaulMapResizeGrip", UIParent)
    grip:SetWidth(40)
    grip:SetHeight(40)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
    if grip.EnableMouse then grip:EnableMouse(true) end
    if grip.SetFrameStrata then grip:SetFrameStrata("TOOLTIP") end
    if grip.SetFrameLevel then grip:SetFrameLevel(100) end

    -- Try Blizzard's familiar resize-grabber art, but do not rely on it: some
    -- 1.12/Turtle clients do not ship that ChatFrame texture. The permanent
    -- ASCII slash mark underneath guarantees there is always a visible cue.
    local icon = grip:CreateTexture(nil, "OVERLAY")
    icon:SetWidth(22)
    icon:SetHeight(22)
    icon:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip.resizeIcon = icon

    local mark = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mark:SetWidth(30)
    mark:SetHeight(18)
    mark:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3, 4)
    mark:SetJustifyH("RIGHT")
    mark:SetText("///")
    mark:SetTextColor(1, 1, 1, 1)
    if mark.SetShadowColor then mark:SetShadowColor(0, 0, 0, 1) end
    if mark.SetShadowOffset then mark:SetShadowOffset(1, -1) end
    grip.resizeMark = mark

    if grip.SetHighlightTexture then
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end

    grip:SetScript("OnMouseDown", function()
        if arg1 and arg1 ~= "LeftButton" then return end
        OB.modules.map:BeginMapResize()
    end)
    grip:SetScript("OnMouseUp", function()
        if arg1 and arg1 ~= "LeftButton" then return end
        OB.modules.map:StopMapResize()
    end)

    -- Drive resizing from the grip itself instead of relying on the module's
    -- periodic tick. This makes the drag immediate even on builds where the
    -- module tick is throttled. IsMouseButtonDown is optional on old clients;
    -- OnMouseUp remains the fallback when it is unavailable.
    grip:SetScript("OnUpdate", function()
        local mapModule = OB.modules and OB.modules.map
        local world = getglobal("WorldMapFrame")

        if mapModule and mapModule.mapResizeState then
            if type(IsMouseButtonDown) == "function"
                    and not IsMouseButtonDown("LeftButton") then
                mapModule:StopMapResize()
            else
                mapModule:StepMapResize()
            end
        elseif not world or not world.IsShown or not world:IsShown() then
            this:Hide()
        end
    end)

    grip:Hide()

    --[[ Same reason as the drag strips: this is a cross-scale anchor, and it
         has to be re-applied when the map is scaled or the grip drifts off the
         corner it names. ]]--
    grip.ecoAnchor = RememberPoints(grip)

    self.mapResizeGrip = grip
    return grip
end

function M:SetMapResizable(on)
    local grip = self:MapResizeGrip()
    if not grip then return false end

    local frame = getglobal("WorldMapFrame")
    if on and frame and frame.IsShown and frame:IsShown() then
        grip:Show()
    else
        grip:Hide()
    end

    if not on then
        self.mapResizeState = nil
        self:ResumeWorldMapButtonUpdate()
    end
    return on and true or false
end

function M:BeginMapResize()
    local frame = getglobal("WorldMapFrame")
    if self.mapDragState or not frame or not frame.IsShown or not frame:IsShown() then return false end
    if type(GetCursorPosition) ~= "function" then return false end

    local left, top = self:WorldMapPhysicalBounds()
    local width, height = frame:GetWidth(), frame:GetHeight()
    local scale = frame:GetScale() or 1
    local effective = frame.GetEffectiveScale and frame:GetEffectiveScale() or scale
    if not left or not top or not width or not height or width <= 0 or height <= 0
            or scale <= 0 or effective <= 0 then
        return false
    end

    local x, y = GetCursorPosition()
    self:PauseWorldMapButtonUpdate()
    self.mapResizeState = {
        startScale = scale,
        baseEffective = effective / scale,
        width = width,
        height = height,
        left = left,
        top = top,
        cursorX = x,
        cursorY = y,
    }

    -- Re-anchor immediately to the current visual top-left. From this point on
    -- that corner is the resize origin, so all growth is down and to the right.
    self:SetWorldMapTopLeft(left, top, false, false)
    return true
end

function M:StopMapResize()
    if not self.mapResizeState then return false end
    self:StepMapResize()
    self.mapResizeState = nil
    self:ResumeWorldMapButtonUpdate()
    self:StoreWorldMapPosition()
    if OB.RefreshPanel then OB.RefreshPanel() end
    return true
end

function M:StepMapResize()
    local state = self.mapResizeState
    if not state then return false end

    local frame = getglobal("WorldMapFrame")
    if not frame or not frame.IsShown or not frame:IsShown() then
        self.mapResizeState = nil
        self:ResumeWorldMapButtonUpdate()
        return false
    end

    local x, y = GetCursorPosition()
    local base = state.baseEffective
    if not base or base <= 0 then return false end

    -- The pointer is measured from the fixed visual top-left. Whichever axis
    -- represents the larger scale change wins, keeping the stock aspect ratio.
    local scaleX = ((x - state.left) / state.width) / base
    local scaleY = ((state.top - y) / state.height) / base
    local dx = math.abs(scaleX - state.startScale)
    local dy = math.abs(scaleY - state.startScale)
    local scale = dx >= dy and scaleX or scaleY

    scale = self:ClampWorldMapScale(scale)
    if math.abs((frame:GetScale() or 1) - scale) >= 0.0005 then
        frame:SetScale(scale)
        self:Config().mapScale = scale
    end

    -- Recompute the TOPLEFT offset at the new effective scale. This is the key
    -- difference from v4: the top and left edges do not move at all, so the map
    -- can only expand/contract toward the bottom-right corner being dragged.
    self:SetWorldMapTopLeft(state.left, state.top, true, false)

    --[[ The grip is anchored across a scale boundary, so it needs putting back
         on the corner after every step -- otherwise it drifts away from the map
         under the cursor that is dragging it. ]]--
    self:SyncMapFurniture()
    return true
end


-- ---------------------------------------------------------------------------
-- the clock
-- ---------------------------------------------------------------------------

--[[ **`GetGameTime` is server time and `date` is your machine's**, and the
     difference is the whole reason this has a switch.

     Server time is what a raid invite means and what a world boss timer is
     counted in. Machine time is what your evening is measured in. Neither is
     the right default for everybody, and reading one while believing it is the
     other is how people miss things. ]]--
--[[ **Edit mode's hook, which this module had everything for except the name.**

     `OB.SetEditMode` walks the module registry and asks anything with a
     `SetDragMode` to unlock. The map already knew how to unlock -- see
     `SetMapMovable` above -- and already registered its frames with edit mode
     so they are outlined. It simply never got asked, because the method it
     answers to is called something else.

     The result was the worst of both: the outline appeared in edit mode and the
     frame underneath would not move, which reads as edit mode being broken
     rather than as a module that was never wired in.

     The clock is always draggable and does not need unlocking -- it is a small
     frame that is nothing but a handle -- so only the map is switched here. ]]--
--[[ **The minimap, which the client nails to the top right corner.**

     There is no client setting for this and never was. `MinimapCluster` is the
     frame that moves: the zone name, the tracking button and the clock are all
     positioned against it, and dragging the map alone leaves its own furniture
     behind in the corner.

     **`SetUserPlaced` is not used here, and that is deliberate.** It hands the
     position to the client, which caches it and restores it on the next login
     over whatever this addon did -- which is exactly the fault that made the
     unit frames unfixable for most of a day. The position is this addon's, it
     is stored from the centre of the screen, and it is put back after the
     client has had its say. See the unit frame module for the full story. ]]--
function M:SetMinimapMovable(on)
    local cluster = getglobal("MinimapCluster")
    if not cluster or not cluster.SetMovable then return false end

    if not on then
        cluster:SetScript("OnDragStart", nil)
        cluster:SetScript("OnDragStop", nil)

        --[[ Left movable with no handler, as the unit frames are: what stops a
             drag is having nothing to start one, and locking a frame somebody
             else may want to move only breaks them. ]]--
        cluster:SetMovable(true)
        self:StyleMinimapGrips(false)
        return true
    end

    cluster:SetMovable(true)
    cluster:EnableMouse(true)
    cluster:RegisterForDrag("LeftButton")

    cluster:SetScript("OnDragStart", function() this:StartMoving() end)

    cluster:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        OB.modules.map:StoreMinimapPosition()
    end)

    if OB.MarkMovable then OB.MarkMovable(cluster, "Minimap") end

    --[[ The corner grips come out with the mover and go away with it. ]]--
    self:StyleMinimapGrips(true)

    return true
end

--[[ Where it ended up, measured from the centre of the screen -- the rule the
     meters, the bars and the unit frames all follow. A position measured from a
     corner is a different place on a different resolution, and this addon has
     been bitten by that before. ]]--
function M:StoreMinimapPosition()
    local cluster = getglobal("MinimapCluster")
    if not cluster or not cluster.GetLeft or not cluster:GetLeft() then
        return false
    end

    local cfg = self:Config()
    local scale = cluster:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.minimapPosition = {
        x = OB.Round((cluster:GetLeft() + (cluster:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((cluster:GetBottom() + (cluster:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[[ Put back, or left alone when there is nothing stored -- in which case the
     client's own corner stands, which is where it has always been. ]]--
function M:PlaceMinimap()
    local cfg = self:Config()
    local saved = cfg.minimapPosition

    if not saved then return false end

    local cluster = getglobal("MinimapCluster")
    if not cluster or not cluster.SetPoint then return false end

    cluster:ClearAllPoints()
    cluster:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)

    return true
end

--[[ Forgotten rather than moved back to a guess, which is what the unit frames
     do for the same reason: the client's own corner exists on every screen and
     no coordinate this addon picked would. ]]--
function M:ResetMinimapPosition()
    self:Config().minimapPosition = nil

    --[[ The bar goes home too: it is part of the minimap as far as anybody
         reaching for this button is concerned, and leaving it out in the middle
         of the screen would be half a reset. ]]--
    self:Config().headerPosition = nil
    self:ApplyMinimapHeader()

    --[[ And the coordinates, which are part of the minimap as far as anybody
         reaching for this button is concerned. ]]--
    self:Config().coordPosition = nil
    self:RefreshMinimapCoords()

    if type(OB.RequireReload) == "function" then
        OB.RequireReload("the minimap position was reset")
    else
        Say("minimap position forgotten. Reload to put it back.")
    end

    return true
end

--[==[ **A frame that is only draggable takes the mouse only while it is
     draggable.**

     Reported twice as clicking a spell and nothing happening. The first time it
     was the HUD bars, which enabled the mouse on everything movable and shipped
     unlocked -- fixed in v0.99.233, and the note there says the rule plainly.

     These two broke the same rule the other way round: the mouse is enabled
     **unconditionally** and only the *drag handler* asks whether things are
     locked. So the minimap header bar and the coordinates readout take clicks
     all the time, at MEDIUM strata ten levels above the map -- which is above
     the client's action buttons -- and anywhere they overlap one, the click goes
     to them and the spell never casts. Both are movable, so "anywhere" is
     wherever somebody has put them.

     **The location box is deliberately not in this.** Clicking the zone name
     opens the world map, which is what `MinimapZoneTextButton` has always done;
     it takes the mouse because it has something to do with it, which is the
     whole distinction. ]==]
--[==[ `unlocked` is passed in by `SetDragMode` rather than read off the profile,
     because **`OB.SetEditMode` writes `profile.locked` after it has asked every
     module to unlock**. Reading the profile from inside that loop answers with
     the state being left rather than the one being entered, so the bar took the
     mouse back one toggle late -- caught by the assertion that it can be grabbed
     again. Falls back to the profile for every other caller. ]==]
function M:ApplyHeaderMouse(unlocked)
    local locked

    if unlocked ~= nil then
        locked = not unlocked
    else
        locked = not (OB.profile and OB.profile.locked == false)
    end

    local holder = self.minimapHeader

    if holder then
        if holder.EnableMouse then holder:EnableMouse(not locked) end

        --[[ The clock box only forwards its drag to the bar, so it wants the
             mouse for exactly as long as the bar does. ]]--
        if holder.clock and holder.clock.EnableMouse then
            holder.clock:EnableMouse(not locked)
        end
    end

    --[[ The **frame**, not `minimapCoords` -- that field holds the font string
         inside it, and a FontString has no mouse to enable. ]]--
    local coords = self.minimapCoordFrame

    if coords and coords.EnableMouse then coords:EnableMouse(not locked) end

    return true
end

function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("map") then
        Say("switch Map on first.")
        return false
    end

    local cfg = self:Config()
    self:SetMapMovable(cfg and cfg.scaleMap and true or false)

    --[[ The minimap unlocks with everything else: it is nailed to a corner by
         the client and there has never been a setting for it. ]]--
    self:SetMinimapMovable(on and true or false)

    self:ApplyHeaderMouse(on and true or false)

    return true
end

function M:ClockText()
    local cfg = self:Config()

    local hour, minute

    if cfg.clockServer and type(GetGameTime) == "function" then
        hour, minute = GetGameTime()
    end

    --[[ Falls through to the machine when the client will not answer, rather
         than showing nothing. A clock that is occasionally an hour out is worth
         more than a blank rectangle. ]]--
    if not hour then
        local now = date("*t")
        if not now then return "" end
        hour, minute = now.hour, now.min
    end

    hour = tonumber(hour) or 0
    minute = tonumber(minute) or 0

    if cfg.clock24 then return format("%d:%02d", hour, minute) end

    --[[ Midnight and noon are twelve rather than zero, which is the one thing
         a twelve-hour clock written the obvious way always gets wrong. ]]--
    local suffix = hour >= 12 and "pm" or "am"
    local shown = hour
    if shown == 0 then shown = 12 elseif shown > 12 then shown = shown - 12 end

    return format("%d:%02d%s", shown, minute, suffix)
end

--[==[ **There is no clock frame any more, and this is where it was.**

     It was a small box under the minimap that could be dragged anywhere, drawn
     by this addon because the client has nothing of the sort. Then the bar
     above the minimap started showing the time, and the same minute was on
     screen twice, in two places, with two ways to move it.

     What survived is `ClockText` above -- server or machine, twelve hour or
     twenty-four -- because that was never about the frame. The bar asks it. ]==]

-- ---------------------------------------------------------------------------
-- the shape and size of the minimap
-- ---------------------------------------------------------------------------

--[[ **Round or square, which is a mask, a position and a border.**

     The minimap is round because a texture says so: the mask decides which
     pixels of it survive, and the client's own mask is a circle. A plain white
     square keeps all of them.

     **The mask alone is not enough, which is what the first attempt got wrong.**
     Changing it and hiding the ring took the border off and left the map round,
     because two more things hold the round shape up:

     *The map is positioned for a circle.* `Minimap` sits inside `MinimapCluster`
     at an offset chosen to centre a disc inside the round art. Left there, a
     square map is a square in the wrong place.

     *The ring is a texture, not a frame.* `MinimapBorder` is a texture on the
     cluster, so it is cleared with `SetTexture` -- and a square map with no
     border at all is a bare square, so one is drawn to replace it.

     The sequence is ShaguTweaks' `minimap-square`, which is the one known to
     work on this client. Everything captured before it is changed, because a
     module switched off that leaves the minimap square has not switched off. ]]--
--[==[ **The sheet the engine draws minimap blips from.**

     `SetBlipTexture` is the only lever there is: the blips are engine-drawn
     into the minimap rather than into frames of it, so there is nothing to
     hide, move or reparent. Handing it a transparent sheet draws nothing.

     **256 by 256, which is the size of the client's own sheet**, entirely
     transparent, shipped rather than borrowed.

     It was 8x8 first, and that put vanilla's missing-texture green square on
     the minimap -- the exact failure the paragraph below was written to avoid,
     arrived at by a different route. The format was never the problem:
     `ShaguPlates.tga` ships at 8x8 32-bit and loads perfectly well. So the
     sheet handed to `SetBlipTexture` is not treated as an ordinary texture --
     the engine indexes cells out of it, and a file too small to hold them
     fails.

     `ObjectIcons` is an 8x8 grid of 32-pixel blips. Matching its geometry gives
     the engine the cells it expects with nothing in any of them.

     The other way to do this is to point the call at a path that does not
     resolve, which is not worth the risk -- a texture that fails to load is not
     reliably invisible, and being wrong about that means a coloured block in
     the middle of the minimap, which is precisely what the first attempt
     produced.

     The client's own is restored by name because there is no getter to have
     recorded it from. That is the one thing here taken on trust rather than
     read back, and it is the client's constant rather than a guess. ]==]
--[==[ **One sheet draws every blip the engine puts on the minimap.**

     Party members and tracking finds -- herbs, veins -- are both cut from
     `ObjectIcons` by *cell index*: the engine picks a rectangle out of the sheet
     and draws it. There is no per-blip call, so `SetBlipTexture` is the only
     lever and it swaps the sheet for all of them at once.

     **Which is why the sheet that ships is the client's own with one cell
     erased**, rather than a blank one. `/eq blipprobe` painted every cell a
     colour the real art does not use and asked: tracking finds came out white
     (cell 0,0) and group members purple (cell 0,1). Only the second is a
     duplicate of what this module draws, so only the second is taken.

     **Raid markers are not in that set.** This module draws group markers itself
     as textures parented to the minimap, so they never touch the sheet -- which
     is why they were unaffected while the party dots, the herbs and the quest
     pins were showing a green square.

     **And the replacement has to be the same size as the sheet it replaces**:
     128x128, because the engine indexes cells on the sheet's own geometry and a
     file of another size puts every cell off the picture. It shipped at 8x8 and
     then at 256x256 before that was understood.

     What ships is a BLP2 DXT3 128x128 with every block zeroed -- alpha nought,
     colour black -- which is the client's own format for this file saying
     nothing.

     -----------------------------------------------------------------------
     **The green square was never any of this, and chasing it here cost days.**

     It came back after the sheet was the right size, the right format and
     switched off entirely -- `hideDefaultBlips` reads false in the reporter's
     own saved variables, so nothing in this file was touching the sheet at all.

     The cause was a **loose file in the client's own folder**:
     `Interface\\Minimap\\ObjectIcons.blp`, written during an earlier attempt to
     blank the blips. The client reads loose files ahead of its archives, so
     every blip on the minimap -- party dots, herbs, ore, quest objectives --
     was being cut from a hand-modified sheet with one of its five blips erased,
     and the party cell landed on the green one.

     Two lessons worth more than the fix:

     *An addon cannot see that file.* No amount of reading this module could
     have found it, and every change made here was tested against a client that
     was still loading somebody's leftover. The answer came from listing
     `Interface\\Minimap` on disk, which is not a thing Lua can do.

     *Restoring a texture by path is not the same as not touching it.* The pass
     below used to set the sheet on its first run even when nothing was hidden,
     which loads whatever that path resolves to now. It only ever writes the
     sheet it has actually changed. ]==]
--[==[ **The client's own sheet with one cell taken out of it.**

     Not a blank sheet. Blanking the whole thing takes every dot the engine cuts
     from it, and the probe above named them: cell 0,0 is what a tracking find
     uses -- the herb or the vein somebody switched tracking on to see -- and
     cell 0,1 is the group. Only one of those is a duplicate of something this
     module already draws.

     So what ships is a copy of the client's sheet with cell 0,1 zeroed at every
     mip level, and nothing else touched. A zeroed DXT3 block is alpha nought,
     which is the format's own way of saying nothing at all. ]==]
local GROUPLESS_BLIP = OB.mediaPath .. "textures\\blip-nogroup"
local CLIENT_BLIP = "Interface\\Minimap\\ObjectIcons"

--[==[ **A sheet with every cell a different colour, to find out which cell is
     which.**

     The engine cuts every blip out of one sheet by cell index and there is no
     call that says which index a party member uses. That matters because the
     group's own dots are the ones worth hiding -- they duplicate the markers
     this module draws and they update on the engine's slower clock, so they
     trail their own replacements whenever anybody walks -- while the tracking
     dots on the same sheet are worth keeping.

     Blanking the whole sheet takes both. To take one, the cell has to be named,
     and painting each cell a colour that appears nowhere in the client's art
     turns that into something a screenshot answers. ]==]
local PROBE_BLIP = OB.mediaPath .. "textures\\blipprobe"

--[[ The size the client's own sheet is, asserted by the suite against the file
     this addon ships -- see "the blank blip sheet". ]]--
OB.blipSheetSize = 128

local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

--[[ Where the square map sits inside the cluster. The round art is not centred
     on the disc it surrounds, so a square map needs its own offset rather than
     the one the circle was using. ]]--
local SQUARE_POINT = { "CENTER", "MinimapCluster", "TOP", 9, -98 }

function M:RememberMinimap()
    if self.minimapOriginal then return self.minimapOriginal end

    local map = getglobal("Minimap")
    if not map then return nil end

    local snap = {}

    --[[ `GetTexture` on the ring, so putting it back is the client's own art
         rather than a path written down here and wrong on a private server. ]]--
    local ring = getglobal("MinimapBorder")
    if ring and ring.GetTexture then snap.ring = ring:GetTexture() end

    if map.GetPoint then
        local point, relative, relativePoint, x, y = map:GetPoint()

        if point then
            snap.point = { point,
                    (relative and relative.GetName and relative:GetName())
                            or "MinimapCluster",
                    relativePoint, x, y }
        end
    end

    self.minimapOriginal = snap
    return snap
end

--[[ The border drawn round a square minimap, made once. The client's ring is a
     circle and cannot be reused, and a square map with nothing round it reads
     as a hole in the interface rather than as a map. ]]--
function M:MinimapBorderFrame()
    if self.minimapBorder then return self.minimapBorder end

    local map = getglobal("Minimap")
    if not map or not CreateFrame then return nil end

    local frame = CreateFrame("Frame", "EquadisClassicOverhaulMinimapBorder", map)

    --[[ Behind the map itself: a border in front of it would draw over the
         blips at the edges, which are the ones worth seeing. ]]--
    if frame.SetFrameStrata then frame:SetFrameStrata("BACKGROUND") end
    if frame.SetFrameLevel then frame:SetFrameLevel(1) end

    frame:SetPoint("TOPLEFT", map, "TOPLEFT", -3, 3)
    frame:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 3, -3)

    self.minimapBorder = frame
    return frame
end

function M:StyleMinimapShape()
    local map = getglobal("Minimap")
    if not map then return false end

    local cfg = self:Config()
    local square = OB.ModuleEnabled("map") and cfg.squareMinimap and true or false

    self:RememberMinimap()

    local ring = getglobal("MinimapBorder")
    local border = self:MinimapBorderFrame()

    if not square then
        if map.SetMaskTexture then map:SetMaskTexture(ROUND_MASK) end

        --[[ Put back by what it was, not by hiding and showing: the ring is
             cleared with `SetTexture(nil)` and showing it again would show a
             texture that is no longer there. ]]--
        local snap = self.minimapOriginal or {}

        if ring then
            if snap.ring and ring.SetTexture then ring:SetTexture(snap.ring) end
            if ring.Show then ring:Show() end
        end

        if snap.point and map.SetPoint then
            map:ClearAllPoints()
            map:SetPoint(snap.point[1], getglobal(snap.point[2]) or UIParent,
                    snap.point[3], snap.point[4], snap.point[5])
        end

        if border then border:Hide() end
        return false
    end

    if map.SetMaskTexture then map:SetMaskTexture(SQUARE_MASK) end

    --[[ The ring cleared rather than hidden, which is how the client's own
         art comes off a texture. Hidden as well, for a build that draws it
         from somewhere this does not know about. ]]--
    if ring then
        if ring.SetTexture then ring:SetTexture(nil) end
        if ring.Hide then ring:Hide() end
    end

    --[[ **Only moved if there is somewhere to move it back to.** Repositioning
         without having captured the original anchor makes square a one-way
         trip: switching it off would put the mask back and leave the map
         sitting where the square wanted it. ]]--
    local snap = self.minimapOriginal or {}

    if map.SetPoint and snap.point then
        map:ClearAllPoints()
        map:SetPoint(SQUARE_POINT[1], getglobal(SQUARE_POINT[2]) or UIParent,
                SQUARE_POINT[3], SQUARE_POINT[4], SQUARE_POINT[5])
    end

    if border then
        --[==[ Through the shared fitter like every other border, so `None`
             genuinely draws nothing rather than drawing a nil backdrop and
             leaving the frame shown. ]==]
        local edge = OB.BorderEdge(tonumber(cfg.squareBorder) or 3,
                border.GetWidth and border:GetWidth() or nil,
                border.GetHeight and border:GetHeight() or nil)

        border:SetBackdrop(edge)

        if edge then
            border:SetBackdropBorderColor(0.9, 0.8, 0.5, 1)
            border:Show()
        else
            border:Hide()
        end
    end

    return true
end

--[[ **How big the minimap is**, which the client offers no way to change at all.

     The whole cluster is scaled rather than the map alone: the zone name, the
     tracking button and the clock are positioned against the map, and scaling
     one of them leaves the rest at the old size around a map that has moved. ]]--
--[[ **The client's own minimap furniture**, by name, because there is no flag
     that says "this one is the client's".

     A collector that gathers addon icons has to tell them from the client's,
     and the only difference is which names the client uses. Getting this list
     wrong in the generous direction sweeps the zoom buttons and the mail flag
     into a tray; getting it wrong the other way leaves an addon's icon sitting
     on the map after you asked for it to be put away.

     `MinimapBackdrop` and `MiniMapTrackingFrame` are here even though they are
     not buttons: the sweep looks at every child, and a name check is cheaper
     than a type check that has to be right about frame types. ]]--
local CLIENT_MINIMAP = {
    ["MinimapZoomIn"] = true, ["MinimapZoomOut"] = true,
    ["MiniMapMailFrame"] = true, ["GameTimeFrame"] = true,
    ["MiniMapTracking"] = true, ["MiniMapTrackingFrame"] = true,
    ["MiniMapTrackingButton"] = true, ["MinimapBackdrop"] = true,
    ["MinimapZoneTextButton"] = true, ["MinimapToggleButton"] = true,
    ["MiniMapWorldMapButton"] = true, ["Minimap"] = true,
    ["MiniMapBattlefieldFrame"] = true, ["MiniMapMeetingStoneFrame"] = true,
    ["MiniMapLFGFrame"] = true, ["MinimapPing"] = true,
    ["MinimapNorthTag"] = true, ["MiniMapVoiceChatFrame"] = true,
    ["MiniMapInstanceDifficulty"] = true, ["MinimapCluster"] = true,
    ["MinimapBackdrop"] = true,

    --[==[ **Turtle's finders are not listed here any more.**

         They were, while the micro menu was gathering them onto its own bar:
         two features moving one button is a fight and the loser is whichever
         ran second. The micro menu no longer takes them, so the reason is gone
         and they are ordinary addon-style buttons that belong in the tray with
         the rest. ]==]
}

--[[ **Size and scale are two different questions, and this addon offered one.**

     Scale multiplies: everything gets bigger and you see exactly the same
     ground, the way a magnifying glass works. Size changes the window: a bigger
     map at the same zoom shows *more of the world*, which is what somebody
     asking for "a bigger minimap" usually means and what the scale slider could
     never give them.

     Both are wanted and they compose, so both are offered. The scale stays on
     the cluster because the zone name and the buttons are positioned against
     the map and scaling the map alone leaves them stranded; the size goes on
     the map itself, because that is the frame whose dimensions decide how much
     world fits inside it. ]]--
--[[ Frames parented to Minimap itself follow a resized minimap automatically.
     A few stock controls do not: GameTimeFrame and MinimapToggleButton are
     parented to MinimapCluster, while the zoom buttons sit on a fixed-offset
     backdrop.  Once the map grows, those controls are stranded over the map's
     interior.  Put them in a small rail just outside whichever horizontal edge
     has room, and restore their exact stock anchors when the module is disabled. ]]--
function M:RememberMinimapFurniture()
    if self.minimapFurnitureOriginal then return end

    self.minimapFurnitureOriginal = {}
    local names = { "GameTimeFrame", "MinimapToggleButton", "MinimapZoomIn",
                    "MinimapZoomOut", "MiniMapTracking", "MiniMapMailFrame",
                    "MiniMapBattlefieldFrame", "MiniMapLFGFrame" }

    for i = 1, table.getn(names) do
        local frame = getglobal(names[i])
        if frame and frame.GetPoint then
            self.minimapFurnitureOriginal[names[i]] = RememberPoints(frame)

            --[[ Kept beside the anchors rather than with them: the collapse
                 button is scaled down as well as moved, and a restore that put
                 back the position and left the size would hand back a button
                 nobody recognises. ]]--
            if frame.GetScale then
                self.minimapFurnitureScale = self.minimapFurnitureScale or {}
                self.minimapFurnitureScale[names[i]] = frame:GetScale() or 1
            end
        end
    end
end

function M:RestoreMinimapFurniture()
    if not self.minimapFurnitureOriginal then return false end

    for name, points in pairs(self.minimapFurnitureOriginal) do
        local frame = getglobal(name)

        if frame then
            RestorePoints(frame, points)

            local scale = self.minimapFurnitureScale
                    and self.minimapFurnitureScale[name]
            if scale and frame.SetScale then frame:SetScale(scale) end
        end
    end

    return true
end

function M:StyleMinimapFurniturePositions()
    local map = getglobal("Minimap")
    if not map then return false end

    self:RememberMinimapFurniture()

    local cfg = self:Config()
    local size = tonumber(cfg.minimapBoxSize) or 140
    local furnitureNeedsRail = cfg.squareMinimap or math.abs(size - 140) > 0.1

    -- At the stock 140x140 round size the client's own anchors are correct and
    -- should be left alone.  The rail is only needed when ECO changes the box
    -- geometry; that is when fixed MinimapCluster/Backdrop offsets land on top
    -- of the visible map.
    if not OB.ModuleEnabled("map") or not furnitureNeedsRail then
        self:RestoreMinimapFurniture()
        return false
    end

    local onRight = self:MinimapOnRight()

    local sidePoint = onRight and "TOPRIGHT" or "TOPLEFT"
    local mapPoint = onRight and "TOPLEFT" or "TOPRIGHT"
    local x = onRight and -4 or 4

    local day = getglobal("GameTimeFrame")
    if day and day.SetPoint then
        day:ClearAllPoints()
        day:SetPoint(sidePoint, map, mapPoint, x, 0)
    end

    --[==[ **The collapse button goes in the corner, small.**

         It was in the rail beside the zoom buttons, which is where the client's
         furniture goes -- and it is not that kind of control. The zoom buttons
         are things you reach for while reading the map; this one puts the map
         away, and it was drawn at full size out on the left where it read as a
         large red X floating beside the minimap rather than as part of it.

         Top right corner and a little over half size, which is where a close
         control lives everywhere else in this interface and small enough that
         it stops competing with the map for attention.

         On the map rather than in the rail, so it does not move with the rail
         when the rail changes sides. ]==]
    --[[ Unless the bar above the map has it, which is where it belongs when
         there is a bar: two passes placing one button is how it ends up back in
         the corner a moment after being put on the bar. ]]--
    local collapse = not self:MinimapHeaderShown()
            and getglobal("MinimapToggleButton")

    if collapse and collapse.SetPoint then
        collapse:ClearAllPoints()
        collapse:SetPoint("CENTER", map, "TOPRIGHT", -6, -6)
        if collapse.SetScale then collapse:SetScale(0.6) end
    end

    local zoomIn = getglobal("MinimapZoomIn")
    if zoomIn and zoomIn.SetPoint then
        zoomIn:ClearAllPoints()
        zoomIn:SetPoint(sidePoint, map, mapPoint, x, -86)
    end

    local zoomOut = getglobal("MinimapZoomOut")
    if zoomOut and zoomOut.SetPoint then
        zoomOut:ClearAllPoints()
        zoomOut:SetPoint(sidePoint, map, mapPoint, x, -120)
    end

    --[==[ **And the rest of the client's furniture, on the same side.**

         Tracking, the mail flag and the battleground marker were left where the
         client put them, which is the right-hand edge -- so a minimap on the
         right of the screen had its zoom buttons swing across to the free side
         and its tracking eye stay pinned against the screen edge. Reported as
         the map icon being on the wrong side.

         The rule is the drawer's: away from the edge the map is nearest. One
         answer, `MinimapOnRight`, and everything that hangs off the map reads
         it. ]==]
    local rail = {
        { name = "MiniMapTracking", y = -30 },
        { name = "MiniMapMailFrame", y = -152 },
        { name = "MiniMapBattlefieldFrame", y = -184 },
        { name = "MiniMapLFGFrame", y = -214 },
    }

    for i = 1, table.getn(rail) do
        local frame = getglobal(rail[i].name)

        if frame and frame.SetPoint then
            frame:ClearAllPoints()
            frame:SetPoint(sidePoint, map, mapPoint, x, rail[i].y)
        end
    end

    return true
end

--[==[ **One place that changes the size**, so the wheel, the grips and the
     slider cannot disagree about the limits.

     The bounds are the slider's own. A value the slider cannot reach is a value
     nobody can undo without editing the saved file, which is the trap every
     "resize by dragging" grows if the two are written separately. ]==]
local MINIMAP_MIN, MINIMAP_MAX = 80, 260

function M:MinimapSize()
    local size = tonumber(self:Config().minimapBoxSize) or 140

    if size < MINIMAP_MIN then size = MINIMAP_MIN end
    if size > MINIMAP_MAX then size = MINIMAP_MAX end

    return size
end

--[==[ **Resized about a corner, so it grows the way you pulled it.**

     `anchor` names the corner that must not move. Dragging the top-left grip
     grows the map up and left, which means the bottom-right stays where it is --
     and since the size is applied from the frame's own anchor, the cluster has
     to be moved by the difference or the map appears to grow in one direction
     only, whichever way you pulled.

     Returns whether anything changed, because at either limit the answer is no
     and a caller that re-anchors regardless would drift the frame a pixel per
     wheel click at the end of the range. ]==]
function M:ResizeMinimap(delta, anchor)
    local cfg = self:Config()
    local was = self:MinimapSize()
    local want = was + (delta or 0)

    if want < MINIMAP_MIN then want = MINIMAP_MIN end
    if want > MINIMAP_MAX then want = MINIMAP_MAX end
    if want == was then return false end

    cfg.minimapBoxSize = want

    local grew = want - was

    --[==[ **The stored offset is adjusted, not the frame's current place.**

         This used to require `cluster:GetLeft()` before touching anything,
         which is a question about where the frame is on screen -- and the
         arithmetic below does not need one. The offsets are numbers we already
         hold, and reading the frame only added a way for the whole step to be
         skipped when the client had not laid it out yet.

         Nothing stored means the map is wherever the client put it, and there
         is no offset to move. Recording where it is first gives the resize
         something to adjust, which is better than growing about the wrong
         corner silently. ]==]
    if anchor and anchor ~= "CENTER" then
        if not self:Config().minimapPosition then self:StoreMinimapPosition() end
        --[[ Half the growth in each direction the corner is *not* pinned to.
             Pinning the bottom-right means the frame's own top-left travels by
             the whole difference; the cluster is anchored from its centre, so
             it moves by half. ]]--
        local dx, dy = 0, 0

        if string.find(anchor, "LEFT") then dx = grew / 2 end
        if string.find(anchor, "RIGHT") then dx = -grew / 2 end
        if string.find(anchor, "TOP") then dy = -grew / 2 end
        if string.find(anchor, "BOTTOM") then dy = grew / 2 end

        --[[ `minimapPosition`, which is the key `StoreMinimapPosition` writes
             and `PlaceMinimap` reads. Written to a name of its own it would
             have moved nothing and quietly grown a second position nobody
             reads. ]]--
        if cfg.minimapPosition then
            cfg.minimapPosition.x = (cfg.minimapPosition.x or 0) + dx
            cfg.minimapPosition.y = (cfg.minimapPosition.y or 0) + dy
        end
    end

    self:StyleMinimapBox()
    self:PlaceMinimap()
    self:StyleMinimapShape()
    self:StyleMinimapFurniturePositions()
    OB.RefreshPanel()

    return true
end

--[==[ **A grip in every corner, each growing the map the way you pulled it.**

     One in the bottom right is the convention and it is also the only corner
     that needs no thought: the frame is anchored from its top left, so growing
     down and right leaves everything else where it was. The other three have to
     move the frame as they resize it, or dragging the top-left corner grows the
     map down and right -- away from the cursor, which reads as a broken grip
     rather than as an anchoring decision.

     `ResizeMinimap` takes the corner that must stay put and does that
     arithmetic once, so the four grips are the same code with a different
     argument rather than four sets of sign errors.

     Parented to UIParent rather than to the minimap: a child of a frame being
     resized is a child whose own anchors move underneath it. ]==]
local MINIMAP_CORNERS = {
    { point = "TOPLEFT",     fixed = "BOTTOMRIGHT", x = -4, y = 4 },
    { point = "TOPRIGHT",    fixed = "BOTTOMLEFT",  x = 4,  y = 4 },
    { point = "BOTTOMLEFT",  fixed = "TOPRIGHT",    x = -4, y = -4 },
    { point = "BOTTOMRIGHT", fixed = "TOPLEFT",     x = 4,  y = -4 },
}

function M:MinimapGrips()
    if self.minimapGrips then return self.minimapGrips end

    local map = getglobal("Minimap")
    if not map or not CreateFrame then return nil end

    self.minimapGrips = {}

    for i = 1, table.getn(MINIMAP_CORNERS) do
        local corner = MINIMAP_CORNERS[i]

        local grip = CreateFrame("Button",
                "EquadisClassicOverhaulMinimapGrip" .. i, UIParent)

        grip:SetWidth(16)
        grip:SetHeight(16)
        grip:SetPoint("CENTER", map, corner.point, corner.x, corner.y)
        grip:EnableMouse(true)
        if grip.SetFrameStrata then grip:SetFrameStrata("TOOLTIP") end

        grip.corner = corner.fixed

        local art = grip:CreateTexture(nil, "OVERLAY")
        art:SetAllPoints(grip)
        art:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip.art = art

        --[==[ **Measured from where the cursor was last frame**, not from where
             the drag began: the size is changed a step at a time, so the origin
             has to move with it or every step is measured against a start point
             the map has already grown away from. ]==]
        grip:SetScript("OnMouseDown", function()
            this.sizing = true
            this.fromX, this.fromY = GetCursorPosition()
        end)

        grip:SetScript("OnMouseUp", function()
            this.sizing = nil
            OB.modules.map:StoreMinimapPosition()
        end)

        grip:SetScript("OnUpdate", function()
            if not this.sizing then return end

            local x, y = GetCursorPosition()
            if not x or not this.fromX then return end

            --[[ Signed by the corner: pulling a left-hand grip leftwards is
                 growth, and pulling a right-hand one leftwards is not. ]]--
            local dx = x - this.fromX
            local dy = y - this.fromY

            if string.find(this.corner, "RIGHT") then dx = -dx end
            if string.find(this.corner, "TOP") then dy = -dy end

            --[[ The larger axis wins, so a diagonal drag does not resize twice
                 as fast as a straight one. ]]--
            local delta = dx
            if math.abs(dy) > math.abs(dx) then delta = dy end

            if math.abs(delta) < 2 then return end

            this.fromX, this.fromY = x, y
            OB.modules.map:ResizeMinimap(delta, this.corner)
        end)

        grip:Hide()
        self.minimapGrips[i] = grip
    end

    return self.minimapGrips
end

--[[ Shown only while the minimap can be moved, which is when somebody is
     arranging it. Four grabbable squares round the map at all times is four
     things to catch a click meant for the map itself. ]]--
function M:StyleMinimapGrips(on)
    local grips = self:MinimapGrips()
    if not grips then return false end

    for i = 1, table.getn(grips) do
        if on then grips[i]:Show() else grips[i]:Hide() end
    end

    return true
end

--[[ The client's own ring is 156 across for a 140 map. Kept as a ratio rather
     than as two numbers, so a map at any size wears a ring in proportion. ]]--
local RING_RATIO = 156 / 140

function M:StyleMinimapBox()
    local map = getglobal("Minimap")
    if not map or not map.SetWidth then return false end

    local cfg = self:Config()
    local size = tonumber(cfg.minimapBoxSize) or 140

    --[[ The client's own is 140. Off, or out of range, means that. ]]--
    if not OB.ModuleEnabled("map") then size = 140 end
    if size < 80 then size = 80 end
    if size > 260 then size = 260 end

    map:SetWidth(size)
    map:SetHeight(size)

    --[[ The backdrop is the art behind the map and is sized independently, so a
         map that grew past it sits on a ring that no longer fits. ]]--
    local backdrop = getglobal("MinimapBackdrop")

    if backdrop and backdrop.SetWidth then
        backdrop:SetWidth(size + 40)
        backdrop:SetHeight(size + 40)
    end

    --[==[ **And the ring itself, which is a texture with a size of its own.**

         `MinimapBorder` is 156 across for the client's 140 map -- the art is
         wider than the circle it frames, because the frame is drawn outside it.
         Nothing scaled it, so a map dragged out to 220 sat inside a ring still
         drawn for 140: reported as the border being disconnected from the
         resizing.

         Kept in proportion rather than set to the map's size, or the ring would
         be drawn *inside* the circle it is supposed to go round. ]==]
    local ring = getglobal("MinimapBorder")

    if ring and ring.SetWidth then
        ring:SetWidth(size * RING_RATIO)
        ring:SetHeight(size * RING_RATIO)

        --[[ Centred on the map, because a texture that keeps its old anchor
             grows off one side. ]]--
        if ring.ClearAllPoints and ring.SetPoint then
            ring:ClearAllPoints()
            ring:SetPoint("CENTER", map, "CENTER", 0, 0)
        end
    end

    --[[ The header goes with it: two boxes sized to the map they sit over. ]]--
    self:ApplyMinimapHeader()

    return true
end

--[[ **The wheel, which every other map in the world zooms with.**

     `Minimap` has mouse wheel input switched off by default in 1.12, so the
     wheel does nothing over it and there is no setting anywhere that turns it
     on. Two lines of addon and it behaves the way people expect.

     **Clamped at both ends deliberately.** `SetZoom` past either end is not an
     error, it just does nothing -- but the *button* states go stale, and the
     usual symptom is a wheel that appears to stop working until you click a
     zoom button. Asking the map for its own limits rather than hard-coding six
     levels, because a server that changed them should not break this. ]]--
function M:StyleMinimapWheel()
    local map = getglobal("Minimap")
    if not map or not map.EnableMouseWheel then return false end

    local cfg = self:Config()

    if not cfg.minimapWheel or not OB.ModuleEnabled("map") then
        map:EnableMouseWheel(false)
        map:SetScript("OnMouseWheel", nil)
        return false
    end

    map:EnableMouseWheel(true)

    --[==[ **The wheel zooms. That is all it does.**

         Control-wheel used to resize the frame, on the reasoning that a gesture
         nobody else uses is free. It is not free: the two look identical while
         you are doing them -- the map gets bigger either way -- and only one of
         them changes what you can see. Somebody reaching for more ground and
         getting magnification instead has been given the wrong answer by an
         interface that looked like it agreed with them.

         Size is a slider and a drag on the grips, where it is deliberate and
         labelled. The wheel is the zoom, which is the control that actually
         changes the view. ]==]
    map:SetScript("OnMouseWheel", function()
        OB.modules.map:ZoomMinimap(arg1)
    end)

    return true
end

function M:ZoomMinimap(direction)
    local map = getglobal("Minimap")
    if not map or not map.SetZoom or not map.GetZoom then return false end

    local levels = 5
    if map.GetZoomLevels then levels = (map:GetZoomLevels() or 6) - 1 end

    local now = map:GetZoom() or 0
    local want = now + ((direction or 0) > 0 and 1 or -1)

    if want < 0 then want = 0 end
    if want > levels then want = levels end

    if want ~= now then map:SetZoom(want) end

    --[[ **Synced even when nothing moved**, which is the case that matters.

         The client's own buttons dim at the ends and only ever learn about it
         from their own OnClick, so a wheel that zooms without telling them
         leaves a lit button that does nothing. Returning early when the zoom
         did not change is exactly the moment the buttons are wrong -- at the
         end of the range, which is the only place they need to be dim. ]]--
    local zin, zout = getglobal("MinimapZoomIn"), getglobal("MinimapZoomOut")

    if zin and zin.Enable then
        if want >= levels then zin:Disable() else zin:Enable() end
    end

    if zout and zout.Enable then
        if want <= 0 then zout:Disable() else zout:Enable() end
    end

    return want ~= now
end

--[[ One switch, one frame, and nothing clever: each of these is a thing on the
     minimap that somebody wants gone and somebody else does not. ]]--
function M:StyleMinimapParts()
    local cfg = self:Config()
    local on = OB.ModuleEnabled("map")

    --[==[ **The bar wins over these three while it is up.**

         `minimapZoneBar` and `minimapDayNight` are older switches about the
         client's own zone bar and its clock, and this pass runs after the bar's
         does -- so with both defaulting on, it showed the client's zone name and
         clock back a moment after the bar had hidden them. That is exactly the
         reported fault: the old name still on screen beside the new one. ]==]
    local header = self:MinimapHeaderShown()

    local parts = {
        { name = "MinimapZoomIn", show = cfg.minimapZoomButtons },
        { name = "MinimapZoomOut", show = cfg.minimapZoomButtons },
        { name = "MiniMapMailFrame", show = cfg.minimapMail },
        { name = "GameTimeFrame", show = not header and cfg.minimapDayNight },
        { name = "MinimapBorderTop", show = not header and cfg.minimapZoneBar },
        { name = "MinimapZoneTextButton", show = not header and cfg.minimapZoneBar },
    }

    for i = 1, table.getn(parts) do
        local frame = getglobal(parts[i].name)

        if frame and frame.Show then
            --[[ Switched off, everything goes back on: this module hiding the
                 client's own furniture and then being disabled must not leave
                 somebody with no mail flag and no way to get it back. ]]--
            if not on or parts[i].show then frame:Show() else frame:Hide() end
        end
    end

    return true
end

--[[ **The ring of addon icons, put in a drawer.**

     Every addon that wants a minimap button parents one to `Minimap` and places
     it round the edge, and nobody coordinates. Ten addons is a ring of icons
     covering the map they are sitting on.

     They are gathered into a tray behind one button. Not hidden -- gathered:
     hiding somebody's icon takes away the only way to reach that addon, which
     is worse than the clutter.

     **Where each one came from is remembered before it is moved**, because this
     module can be switched off and a button that cannot be put back is a button
     somebody has lost. That is the whole reason this stores parent and point
     rather than just reparenting and hoping. ]]--
--[==[ **Which half of the screen the map is on.**

     Everything that hangs off the minimap has to know: the furniture rail
     changes sides so it is never off the edge, and the drawer of addon icons
     opens away from the edge rather than into it.

     Measured from the frame rather than from the stored position, because the
     map has a position only once somebody has moved it -- and the client's own
     corner, which is where it starts, is a position too.

     Right when it cannot be asked: that is the corner the client nails it to,
     so a client that will not answer is answering "right" in every way but
     saying so. ]==]
function M:MinimapOnRight()
    local map = getglobal("Minimap")
    local centre = map and map.GetCenter and map:GetCenter()

    if not centre or type(GetScreenWidth) ~= "function" then return true end

    return centre >= (GetScreenWidth() / 2)
end

--[==[ **The drawer opens into the screen, not off it.**

     It hung below the map's bottom-right corner, which is fine in the corner the
     client puts the map in and wrong everywhere else: a map dragged to the left
     edge opened its drawer over the map itself, and one at the bottom opened it
     under the screen.

     Sideways instead, and away from the nearest edge -- left of the map when the
     map is on the right of the screen, right of it when it is on the left. The
     tray is clamped to the screen as well, which catches the corners this rule
     alone does not. ]==]
local TRAY_GAP = 6

function M:PlaceMinimapTray()
    local tray = self.minimapTray
    local map = getglobal("Minimap")
    if not tray or not map or not tray.SetPoint then return nil end

    tray:ClearAllPoints()

    if self:MinimapOnRight() then
        tray:SetPoint("TOPRIGHT", map, "TOPLEFT", -TRAY_GAP, 0)
        return "left"
    end

    tray:SetPoint("TOPLEFT", map, "TOPRIGHT", TRAY_GAP, 0)
    return "right"
end

function M:MinimapTray()
    if self.minimapTray then return self.minimapTray end
    if not CreateFrame then return nil end

    local map = getglobal("Minimap")
    if not map then return nil end

    local tray = CreateFrame("Frame", "EquadisClassicOverhaulMinimapTray", UIParent)
    tray:SetWidth(10)
    tray:SetHeight(10)
    tray:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", 0, -6)
    if tray.SetFrameStrata then tray:SetFrameStrata("DIALOG") end
    if tray.SetClampedToScreen then tray:SetClampedToScreen(true) end
    tray:Hide()

    local toggle = CreateFrame("Button", "EquadisClassicOverhaulMinimapToggle", map)
    toggle:SetWidth(16)
    toggle:SetHeight(16)
    toggle:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 2, -2)
    if toggle.SetFrameLevel and map.GetFrameLevel then
        toggle:SetFrameLevel((map:GetFrameLevel() or 0) + 20)
    end

    --[==[ **Its art is the button's normal texture, not a picture laid on top.**

         It used to be an ARTWORK texture parented to the button, which looks the
         same and is not the same thing. The header bar sizes both buttons to its
         own square and stretches *the normal texture* to fit -- a step that
         silently did nothing here, because there was no normal texture to
         stretch. And giving a button a pushed texture when it has no normal one
         means the press has nothing to draw over, so the client's small
         minimise glyph became the whole button: the reported "the plus becomes a
         small x".

         The same kind of button as the client's collapse control beside it, so
         one code path dresses both. `icon` is kept as the name for it, because
         several places already say `toggle.icon` and they all still mean the
         picture on the button.

         Closed starts with a plus. The old code showed a minus while the drawer
         was closed, which looked like a stray red X pinned to the map. ]==]
    toggle:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    toggle.icon = toggle:GetNormalTexture()

    if toggle.icon and toggle.icon.SetAllPoints then
        toggle.icon:SetAllPoints(toggle)
    end

    toggle:SetScript("OnClick", function()
        OB.modules.map:ToggleMinimapTray()
    end)

    --[==[ **A plus sign on a bar is not self-explanatory.**

         Everything else up there says what it is -- the zone names itself, the
         clock is a time, the red cross is the one control everybody already
         knows. This one is a small plus that opens a drawer of other addons'
         icons, and there is no way to guess that from the picture.

         The client's own tooltip, in the corner the client puts minimap
         tooltips in. ]==]
    toggle:SetScript("OnEnter", function()
        if not GameTooltip then return end

        OB.OwnTooltip(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("Addon Buttons")
        GameTooltip:AddLine("Show or hide the minimap buttons gathered from "
                .. "your other addons.", 1, 1, 1)
        GameTooltip:Show()
    end)

    toggle:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.minimapTray = tray
    self.minimapToggle = toggle

    return tray
end

--[[ Quest addons also parent their *map pins* to Minimap.  Treating every named
     child as a launcher was the collector's core bug: when the drawer closed,
     Questie/pfQuest nodes had been reparented to UIParent and their coordinate
     updater kept moving them as if they still lived on the minimap.  Only
     launcher-shaped buttons are allowed into the drawer now. ]]--
function M:IsMinimapLauncher(child)
    if not child or not child.GetName then return false end

    local name = child:GetName()
    if not name or CLIENT_MINIMAP[name]
            or string.find(name, "EquadisClassicOverhaul", 1, true) then
        return false
    end

    local kind = child.GetObjectType and child:GetObjectType()
    if kind ~= "Button" and kind ~= "CheckButton" then return false end

    local lower = string.lower(name)

    -- Explicit launcher conventions win over the generic marker words below.
    if lower == "pfquesticon"
            or string.find(lower, "minimapbutton", 1, true)
            or string.find(lower, "minimapicon", 1, true)
            or string.find(lower, "libdbicon", 1, true) then
        return true
    end

    -- Questie's pooled pins are QuestieFrame1, QuestieFrame2, ... .  pfMap and
    -- most other map libraries similarly say node/pin/poi/marker in the frame
    -- name.  Those are data points, not addon launchers.
    if string.find(lower, "^questieframe%d*")
            or string.find(lower, "^questiepin")
            or string.find(lower, "^pfmap")
            or string.find(lower, "mapnode", 1, true)
            or string.find(lower, "minimapnode", 1, true)
            or string.find(lower, "questpin", 1, true)
            or string.find(lower, "questmarker", 1, true)
            or string.find(lower, "questobjective", 1, true)
            or string.find(lower, "poi", 1, true)
            or string.find(lower, "marker", 1, true)
            or string.find(lower, "node", 1, true)
            or string.find(lower, "pin", 1, true) then
        return false
    end

    -- Older launchers are not consistent about using the words "minimap" in
    -- their names, but they almost always identify themselves as a button,
    -- icon or launcher (AtlasButton, CensusPlus_Button, etc.).  Requiring that
    -- extra launcher hint is intentionally stricter than the old "any clickable
    -- 20px frame" fallback: a false negative leaves one addon button on the
    -- minimap; a false positive steals a live quest/objective pin and makes it
    -- drift with the player when the drawer is closed.
    --[==[ **`minimap` counts as a launcher hint too.**

         The three words above miss a whole class of them, and the ones they
         miss are the ones people notice: `TWMiniMapBattlefieldFrame` is
         Turtle's battleground finder and `EBC_Minimap` is the Booty Bay radio.
         Both are buttons that sit on the minimap and do nothing else, and
         neither calls itself a button.

         Safe because the pin, node, marker and objective names are rejected
         above this, before any hint is looked for -- so a data pin that happens
         to have "minimap" in its name is already gone. ]==]
    if not string.find(lower, "button", 1, true)
            and not string.find(lower, "icon", 1, true)
            and not string.find(lower, "launcher", 1, true)
            and not string.find(lower, "minimap", 1, true) then
        return false
    end

    local width = child.GetWidth and child:GetWidth() or 0
    local height = child.GetHeight and child:GetHeight() or 0
    if width < 18 or height < 18 or width > 70 or height > 70 then return false end

    local clickable = child.GetScript
            and (child:GetScript("OnClick") or child:GetScript("OnMouseUp"))
    return clickable and true or false
end

--[[ Addon launchers do not all use the same parent.  Most are children of
     Minimap, some are children of MinimapCluster, and a few are children of
     UIParent but anchored to one of those frames.  Scan all three forms, while
     only accepting UIParent children whose anchors actually point at the
     minimap.  This catches the real launchers without turning the collector
     back into a generic map-pin vacuum. ]]--
function M:IsAnchoredToMinimap(child)
    if not child then return false end

    local map = getglobal("Minimap")
    local cluster = getglobal("MinimapCluster")
    local parent = child.GetParent and child:GetParent()

    if parent == map or parent == cluster then return true end
    if not child.GetPoint then return false end

    local count = 1
    if child.GetNumPoints then count = child:GetNumPoints() or 0 end

    for i = 1, count do
        local _, relative = child:GetPoint(i)
        if relative == map or relative == cluster
                or relative == "Minimap" or relative == "MinimapCluster" then
            return true
        end
    end

    return false
end

--[==[ **A launcher one level down, inside a holder of its own.**

     Atlas puts its button inside `AtlasCFMButtonFrame`, a plain Frame parented
     to the minimap -- so the button is a *grandchild*, and a sweep of direct
     children never sees it. It is a common enough shape: the holder exists to
     carry the drag handling or the event registration, and the button hangs off
     it.

     One level, and only through something that is holding a launcher rather
     than through anything: a Frame the size of a button, on the minimap, whose
     children are checked by exactly the same test. Descending further, or
     through frames of any size, is how a collector turns back into the map-pin
     vacuum this one was written to stop being. ]==]
local function HoldsLauncher(frame)
    if not frame or not frame.GetObjectType then return false end
    if frame:GetObjectType() ~= "Frame" then return false end

    local width = frame.GetWidth and frame:GetWidth() or 0
    return width >= 18 and width <= 70
end

local function AppendMinimapLauncherChildren(module, source, out, seen, requireAnchor)
    if not source or not source.GetChildren then return end

    local children = { source:GetChildren() }
    for i = 1, table.getn(children) do
        local child = children[i]

        if child and not seen[child]
                and (not requireAnchor or module:IsAnchoredToMinimap(child)) then
            if module:IsMinimapLauncher(child) then
                seen[child] = true
                table.insert(out, child)

            elseif HoldsLauncher(child) then
                local inner = { child:GetChildren() }

                for j = 1, table.getn(inner) do
                    local grand = inner[j]

                    if grand and not seen[grand]
                            and module:IsMinimapLauncher(grand) then
                        seen[grand] = true
                        table.insert(out, grand)
                    end
                end
            end
        end
    end
end

function M:MinimapAddonButtons()
    local map = getglobal("Minimap")
    if not map then return {} end

    local out, seen = {}, {}
    AppendMinimapLauncherChildren(self, map, out, seen, false)
    AppendMinimapLauncherChildren(self, getglobal("MinimapCluster"), out, seen, false)

    -- Only the anchored subset of UIParent is relevant.  Scanning every UI
    -- button without this check would collect action buttons and menu controls.
    AppendMinimapLauncherChildren(self, UIParent, out, seen, true)

    return out
end

local function LauncherVisualSize(button)
    local largest = 0

    if button.GetWidth then largest = math.max(largest, button:GetWidth() or 0) end
    if button.GetHeight then largest = math.max(largest, button:GetHeight() or 0) end

    if button.GetRegions then
        local regions = { button:GetRegions() }
        for i = 1, table.getn(regions) do
            local region = regions[i]
            if region and region.GetWidth then
                largest = math.max(largest, region:GetWidth() or 0)
            end
            if region and region.GetHeight then
                largest = math.max(largest, region:GetHeight() or 0)
            end
        end
    end

    return largest
end

function M:CollectMinimapButtons()
    local cfg = self:Config()
    local tray = self:MinimapTray()
    if not tray then return 0 end

    if not cfg.minimapCollect or not OB.ModuleEnabled("map") then
        self:ReleaseMinimapButtons()
        if self.minimapToggle then self.minimapToggle:Hide() end
        return 0
    end

    if self.minimapToggle then self.minimapToggle:Show() end

    local buttons = self:MinimapAddonButtons()
    self.minimapHomes = self.minimapHomes or {}

    for i = 1, table.getn(buttons) do
        local button = buttons[i]
        local name = button:GetName()

        --[[ Recorded once, before the first reparent.  An addon is allowed to
             re-anchor its own launcher later; that must not overwrite the only
             copy of the real home. ]]--
        if not self.minimapHomes[name] then
            local point, rel, relPoint, x, y = button:GetPoint(1)

            self.minimapHomes[name] = {
                parent = button:GetParent(),
                point = point, rel = rel, relPoint = relPoint, x = x, y = y,
                scale = button.GetScale and button:GetScale() or 1,
            }
        end

        button:SetParent(tray)
    end

    -- Lay out *everything currently held*, not merely buttons discovered on
    -- this sweep.  The old pass forgot already-reparented buttons and put the
    -- next arrival on top of the first cell.
    local held = {}
    for name in pairs(self.minimapHomes) do
        local button = getglobal(name)
        if button and button:GetParent() == tray then table.insert(held, button) end
    end

    table.sort(held, function(a, b) return a:GetName() < b:GetName() end)

--[==[ **The cell and the icon in it.**

     `targetVisual` is what every launcher is scaled towards, so wildly
     different icon art comes out the same size in the drawer; `cell` is the
     square it sits in and has to stay comfortably larger, or neighbours touch.

     Raised from 34 in a 40 cell. That was sized against the minimap's own
     buttons, which are small because they are competing with the map for room
     -- and the drawer is not on the map. Nothing here is fighting for space, so
     they can be the size they are meant to be read at. ]==]
    local columns, cell, targetVisual = 3, 46, 40

    for i = 1, table.getn(held) do
        local button = held[i]
        local visual = LauncherVisualSize(button)
        local fit = 1

        if visual > targetVisual then fit = targetVisual / visual end
        if fit < 0.45 then fit = 0.45 end
        if button.SetScale then button:SetScale(fit) end

        button:ClearAllPoints()

        local column = mod(i - 1, columns)
        local row = math.floor((i - 1) / columns)
        button:SetPoint("CENTER", tray, "TOPLEFT",
                4 + (column * cell) + (cell / 2),
                -4 - (row * cell) - (cell / 2))
    end

    local count = table.getn(held)
    if count > 0 then
        local usedColumns = count > columns and columns or count
        local rows = math.floor((count - 1) / columns) + 1
        tray:SetWidth(8 + (usedColumns * cell))
        tray:SetHeight(8 + (rows * cell))

        --[[ Placed after it is sized, because which corner it is anchored by
             decides which way it grows from the map. ]]--
        self:PlaceMinimapTray()
    else
        tray:SetWidth(10)
        tray:SetHeight(10)
        tray:Hide()
    end

    self.minimapHeld = count
    return count
end

--[==[ **Anything the drawer holds that has wandered off, brought back.**

     Only names already in `minimapHomes` are considered, which is what makes
     this safe to run on a clock: it can never gather something new, so it
     cannot take a button somebody has not already agreed to have gathered. A
     home is never re-recorded here either -- the one in hand is from before the
     first reparent, and the position a dragged button is sitting at now is not
     where it came from. ]==]
--[==[ **How many things are hanging off the minimap right now.**

     Cheap enough to ask twice a second, and it is the whole of what says
     "somebody has added a button since the last sweep". Counting rather than
     inspecting: what the new child *is* is `IsMinimapLauncher`'s question, and
     asking it of every child every half second is the walk this avoids. ]==]
function M:MinimapChildCount()
    local total = 0

    for _, name in ipairs({ "Minimap", "MinimapCluster" }) do
        local frame = getglobal(name)

        if frame and frame.GetChildren then
            local kids = { frame:GetChildren() }
            total = total + table.getn(kids)
        end
    end

    return total
end

--[==[ **A button that arrives after this module has bound.**

     The sweep ran once at bind and then only while the drawer was *open* -- and
     the drawer starts closed. Every addon that makes its minimap button at
     `PLAYER_LOGIN` or later therefore missed it: FuBar's plugins, Atlas,
     Questie. They sat on the map for the session unless you happened to open
     the tray, which is a thing you would only do to look at the buttons that
     were not there.

     Watched by counting rather than by sweeping: a walk of every child twice a
     second to find nothing is the cost this exists to avoid, and a count that
     has not moved is proof there is nothing new to find. ]==]
function M:CollectLateArrivals()
    local cfg = self:Config()
    if not cfg.minimapCollect or not OB.ModuleEnabled("map") then return false end

    local count = self:MinimapChildCount()
    if count == self.minimapChildren then return false end

    self:CollectMinimapButtons()

    --[[ **Counted again afterwards, not before.** Gathering reparents buttons
         off the minimap, so the sweep changes the very number that triggered
         it -- recording the old count would leave the watcher firing on its own
         result, every half second, for ever. ]]--
    self.minimapChildren = self:MinimapChildCount()

    return true
end

function M:ReclaimMinimapButtons()
    local cfg = self:Config()
    if not cfg.minimapCollect or not OB.ModuleEnabled("map") then return 0 end
    if not self.minimapHomes then return 0 end

    local tray = self.minimapTray
    if not tray then return 0 end

    local strayed = 0

    for name in pairs(self.minimapHomes) do
        local button = getglobal(name)

        if button and button.GetParent and button:GetParent() ~= tray then
            --[[ Put back here rather than left to the collector: that sweeps
                 the minimap, and a button dragged onto UIParent and anchored
                 wherever it was dropped is no longer on the minimap to be
                 found. Reclaiming by name is the only route home. ]]--
            button:SetParent(tray)
            strayed = strayed + 1
        end
    end

    --[[ Re-laid out through the collector rather than reparented here, so the
         grid is rebuilt around whatever came back and one pass owns the
         arrangement. ]]--
    if strayed > 0 then self:CollectMinimapButtons() end

    return strayed
end

--[[ Every launcher goes back with both its original anchor and scale.  Scale
     has to be restored because the drawer normalises wildly different icon art
     into equal visual cells. ]]--
function M:ReleaseMinimapButtons()
    if not self.minimapHomes then return 0 end

    local put = 0

    for name, home in pairs(self.minimapHomes) do
        local button = getglobal(name)

        if button and button.SetParent then
            button:SetParent(home.parent)
            button:ClearAllPoints()

            if home.point then
                button:SetPoint(home.point, home.rel, home.relPoint,
                        home.x or 0, home.y or 0)
            end
            if button.SetScale and home.scale then button:SetScale(home.scale) end

            put = put + 1
        end
    end

    self.minimapHomes = nil
    self.minimapHeld = 0

    if self.minimapTray then self.minimapTray:Hide() end

    --[[ Asked rather than written: see `RefreshHeaderGlyphs`. ]]--
    self:RefreshHeaderGlyphs()

    return put
end

function M:ToggleMinimapTray()
    local tray = self:MinimapTray()
    if not tray then return false end

    if tray:IsShown() then
        tray:Hide()
    else
        -- Pick up launchers created since the last sweep before opening.
        self:CollectMinimapButtons()
        if (self.minimapHeld or 0) <= 0 then return false end

        --[[ Again on the way out: the map may have been dragged across the
             screen since the drawer was last filled. ]]--
        self:PlaceMinimapTray()
        tray:Show()
    end

    --[[ One place decides what each button wears, and it reads the tray rather
         than being told. ]]--
    self:RefreshHeaderGlyphs()

    return tray:IsShown()
end

function M:StyleMinimapSize()
    local cluster = getglobal("MinimapCluster")
    if not cluster or not cluster.SetScale then return false end

    local cfg = self:Config()
    --[[ One, always. See the note on the retired setting: scaling the cluster
         magnifies the same ground the size already magnifies, and takes the
         furniture with it. ]]--
    local scale = 1

    if not OB.ModuleEnabled("map") then scale = 1 end

    if scale < 0.5 then scale = 0.5 end
    if scale > 2 then scale = 2 end

    cluster:SetScale(scale)
    return true
end

--[[ Round again and back to the client's size, called when the module is
     switched off rather than left to the next login. ]]--
function M:RestoreMinimapShape()
    local map = getglobal("Minimap")
    if not map then return false end

    if map.SetMaskTexture then map:SetMaskTexture(ROUND_MASK) end

    local snap = self.minimapOriginal or {}
    local ring = getglobal("MinimapBorder")

    if ring then
        if snap.ring and ring.SetTexture then ring:SetTexture(snap.ring) end
        if ring.Show then ring:Show() end
    end

    if snap.point and map.SetPoint then
        map:ClearAllPoints()
        map:SetPoint(snap.point[1], getglobal(snap.point[2]) or UIParent,
                snap.point[3], snap.point[4], snap.point[5])
    end

    if self.minimapBorder then self.minimapBorder:Hide() end

    local cluster = getglobal("MinimapCluster")
    if cluster and cluster.SetScale then cluster:SetScale(1) end

    return true
end

-- ---------------------------------------------------------------------------
-- the zone name
-- ---------------------------------------------------------------------------

--[==[ **The minimap's own header: where you are, and what time it is.**

     The client puts the zone name in a bar welded across the top of the minimap
     art -- `MinimapBorderTop` -- and the clock on a button stuck to the ring.
     Neither moves when the map is resized, which is how the zone name ended up
     drawn *underneath* an enlarged map, and neither can be turned off without
     losing the other.

     Two boxes above the map instead: a wide one for the location and a narrow
     one for the time, sized to whatever the map is. They are the client's own
     tooltip furniture -- this addon's skin is for the setup walkthrough and the
     options panel, and this is drawn onto the client's own minimap.

     Three switches, because the three things are separate: the art, the
     location, and the time. Somebody who wants the clock and not the zone name
     gets exactly that. ]==]
local HEADER_H = 20
local HEADER_GAP = 3
local TIME_W = 52

--[[ One square per button at the right end, sized to the bar rather than to the
     art on them: the client's collapse button is drawn a good deal larger than
     this and is scaled down to fit rather than allowed to set the height. ]]--
local HEADER_BUTTON = 18

function M:MinimapHeader()
    if self.minimapHeader then return self.minimapHeader end

    local map = getglobal("Minimap")
    if not map or not CreateFrame then return nil end

    local holder = CreateFrame("Frame", "EquadisOverhaulMinimapHeader",
            getglobal("MinimapCluster") or map)

    --[==[ **Above the map and above its art.**

         The zone name drawing under the minimap is what this replaces, and the
         cause was a frame level: the client's own top bar sits below the map's
         own strata once the map is enlarged over it. Put on the strata above the
         map, which is where a label about the map belongs. ]==]
    if holder.SetFrameStrata then holder:SetFrameStrata("MEDIUM") end
    if holder.SetFrameLevel and map.GetFrameLevel then
        holder:SetFrameLevel((map:GetFrameLevel() or 0) + 10)
    end

    --[==[ **One bar, not a row of boxes.**

         Each part carried a backdrop of its own, so where you are, what time it
         is and the two buttons about the map arrived as four separate windows
         stacked along one line -- four borders and three gaps for one strip of
         information that is always about the same thing.

         The backdrop belongs to the bar. What is inside it is text and buttons,
         which is what the client's own furniture looks like everywhere else: a
         panel with things on it. ]==]
    if holder.SetBackdrop then
        holder:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })

        holder:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
    end

    --[[ A part of the bar: a region to put text in and to measure, with no
         edge of its own. Kept as frames rather than plain font strings because
         either can be hidden on its own and the widths are what the layout is
         written in. ]]--
    local function box(name)
        local f = CreateFrame("Frame", name, holder)

        f.text = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("CENTER", f, "CENTER", 0, 0)

        return f
    end

    holder.location = box("EquadisOverhaulMinimapLocation")
    holder.clock = box("EquadisOverhaulMinimapClock")

    --[==[ **Clicking the location box opens the world map**, which is what
         clicking the zone name has always done -- `MinimapZoneTextButton` is a
         button for exactly that reason, and taking its job without taking its
         behaviour would be a regression dressed as a redesign. ]==]
    holder.location:EnableMouse(true)

    holder.location:SetScript("OnMouseUp", function()
        --[[ A drag that finishes over the box is not a click on it: both
             handlers fire, and the world map opening every time the bar is
             moved is not what moving the bar means. ]]--
        if holder.justDragged then holder.justDragged = nil return end

        --[[ Edit mode is for moving things rather than opening them. ]]--
        if OB.profile and not OB.profile.locked then return end

        if type(ToggleWorldMap) == "function" then ToggleWorldMap() end
    end)

    --[==[ **The bar moves, and it moves in edit mode with everything else.**

         It carries the zone name, the time and the two buttons about the map,
         which between them are the first thing anybody repositions -- and it
         was the one frame this addon drew that was nailed where it was put.

         Locked through the profile rather than behind a switch of its own:
         `OB.SetEditMode` writes `locked`, so a frame that reads it unlocks by
         the same gesture as every other frame here, and there is one thing to
         learn rather than two.

         **The boxes hand their drag up to the bar**, because they cover it --
         grabbing the zone name has to move the whole bar rather than pull one
         box out of three. ]==]
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")

    --[[ The mouse follows the lock rather than being claimed here for ever;
         see `ApplyHeaderMouse`. ]]--

    local function grab()
        if OB.profile and OB.profile.locked then return end

        holder:StartMoving()
        holder.dragging = true
    end

    local function drop()
        if not holder.dragging then return end

        holder.dragging = nil
        holder:StopMovingOrSizing()
        holder.justDragged = true

        EquadisClassicOverhaul.modules.map:StoreMinimapHeader()
    end

    holder:SetScript("OnDragStart", grab)
    holder:SetScript("OnDragStop", drop)

    local boxes = { holder.location, holder.clock }

    for i = 1, table.getn(boxes) do
        --[[ The location box keeps the mouse -- clicking it opens the world map
             -- and the clock box gets it from `ApplyHeaderMouse` with the bar,
             because forwarding a drag is all it does with it. ]]--
        if boxes[i] == holder.location then boxes[i]:EnableMouse(true) end

        boxes[i]:RegisterForDrag("LeftButton")
        boxes[i]:SetScript("OnDragStart", grab)
        boxes[i]:SetScript("OnDragStop", drop)
    end

    self.minimapHeader = holder
    return holder
end

--[[ Is the bar up? Asked by the furniture pass and by the parts pass, both of
     which would otherwise put back the things this bar replaced -- which is
     exactly how the client's own zone name ended up on screen under ours. ]]--
function M:MinimapHeaderShown()
    local cfg = self:Config()
    return (OB.ModuleEnabled("map") and cfg.locationTimeArt and true or false)
end

--[[ Where the bar ended up, measured from the centre of the screen -- the rule
     the meters, the bars, the unit frames and the minimap itself all follow,
     because a position measured from an edge is a different place on a
     different resolution. ]]--
function M:StoreMinimapHeader()
    local holder = self.minimapHeader
    if not holder or not holder.GetLeft or not holder:GetLeft() then return false end

    local cfg = self:Config()
    local scale = holder:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.headerPosition = {
        x = OB.Round((holder:GetLeft() + (holder:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((holder:GetBottom() + (holder:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[[ Put back where it was dropped, or over the map when it has never been
     moved -- in which case it follows the map's size and position, which is the
     whole reason it is drawn above the map rather than welded into its art. ]]--
function M:PlaceMinimapHeader()
    local holder = self.minimapHeader
    local map = getglobal("Minimap")
    if not holder or not map then return false end

    --[[ Never while it is being dragged. This is placed on a settings change
         rather than on a clock, so it has not bitten -- but an `Apply` landing
         mid-drag would take the bar out of the reader's hand exactly the way
         the coordinates were being taken. ]]--
    if holder.dragging then return false end

    local saved = self:Config().headerPosition

    holder:ClearAllPoints()

    if saved and ((saved.x or 0) ~= 0 or (saved.y or 0) ~= 0) then
        holder:SetPoint("CENTER", UIParent, "CENTER", saved.x or 0, saved.y or 0)
        return true
    end

    holder:SetPoint("BOTTOM", map, "TOP", 0, HEADER_GAP)
    return true
end

--[==[ **The two buttons that are about the map rather than in it.**

     Putting the minimap away and opening the drawer of gathered addon icons are
     both things you do *to* the map, and both were pinned to the map itself --
     one in the top corner over the art, one hanging off the bottom edge -- where
     they read as strays stuck onto the minimap rather than as its controls.

     They go on the bar, together, at the end the eye finishes on, and they move
     with it.

     **Where each one came from is remembered before it is moved**, because this
     bar can be switched off and a button that cannot be put back is a button
     somebody has lost. The same rule the drawer follows for everybody else's
     icons, for the same reason. ]==]
--[==[ **A square for a button to sit in, so the two of them match.**

     The one that puts the map away is the client's, drawn at about twice this
     size with its own frame painted into the art; the one that opens the drawer
     of addon icons is ours, sixteen pixels of plus sign. Put on a bar side by
     side they were plainly two different controls -- different size, one with a
     border and one without -- which reads as one of them not belonging.

     So neither is trusted to draw its own frame. Each goes in a square of this
     module's making, both the same size, both wearing the bar's own edge, and
     the button inside is scaled until it fits. What differs between them is
     then only the picture, which is the part that is supposed to differ. ]==]
function M:HeaderSlot(key, scale)
    local holder = self:MinimapHeader()
    if not holder or not CreateFrame then return nil end

    self.headerSlots = self.headerSlots or {}
    if self.headerSlots[key] then return self.headerSlots[key] end

    local slot = CreateFrame("Frame", "EquadisOverhaulMinimapSlot" .. key, holder)
    slot:SetWidth(HEADER_BUTTON)
    slot:SetHeight(HEADER_BUTTON)

    --[==[ **No border of its own.**

         The square was given the bar's edge so the two buttons would match, and
         they did -- as two boxed controls inside a box, three borders deep. The
         art the buttons wear already draws its own frame, and one is enough.

         The square stays because it is what holds them the same size and the
         same distance apart. It simply does not draw anything. ]==]

    if slot.SetFrameLevel and holder.GetFrameLevel then
        slot:SetFrameLevel((holder:GetFrameLevel() or 0) + 1)
    end

    slot.eqScale = scale
    self.headerSlots[key] = slot

    return slot
end

--[==[ **Both buttons wear the client's own square glyphs.**

     One was ours -- a plus that turns into a minus as the drawer opens -- and
     the other was the client's collapse control, a red cross drawn in its own
     heavier frame. Side by side on one bar they read as two controls from two
     different interfaces.

     The client ships a matched pair for exactly this: a small square plus and
     the same square with a minus in it. Both buttons take it, so the two are
     the same size, the same weight and the same colour, and what differs
     between them is the state each is in:

     - the drawer shows a plus while it is closed and a minus while it is open;
     - the map shows a minus while it is up (press to put it away) and a plus
       while it is away.

     Which is the same sentence twice: plus opens, minus closes. ]==]
local GLYPH_PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local GLYPH_MINUS = "Interface\\Buttons\\UI-MinusButton-Up"

--[[ What a press looks like. The client's own pressed square, so the button
     answers a click the way every other one in the interface does. ]]--
local GLYPH_PUSHED = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down"

--[[ The map's own button, kept in step with the map. A texture write costs
     nothing and this runs on the same beat as the header's clock, but it is
     compared first because most of those beats change nothing. ]]--
--[==[ **Both buttons, and each one derived rather than remembered.**

     This drove only the map's collapse button. The drawer's glyph was written by
     hand at each of the three places that open or close the tray -- and a state
     kept in three places is a state that gets out of step, which is the reported
     "it doesn't go back to a plus": the sweep that empties the drawer put the
     plus back, and the toggle that closed it did not always run.

     Neither button remembers anything now. The map's glyph is read off whether
     the map is shown, the drawer's off whether the tray is, on the bar's own
     clock. There is no third state to be left in. ]==]
local function setGlyph(button, want)
    if not button or not button.SetNormalTexture then return false end
    if button.eqGlyph == want then return false end

    button.eqGlyph = want
    button:SetNormalTexture(want)

    --[[ Re-stretched, because a fresh texture object arrives at whatever size
         its art is rather than at the size of the button under it. ]]--
    local art = button.GetNormalTexture and button:GetNormalTexture()

    if art and art.SetAllPoints then
        art:ClearAllPoints()
        art:SetAllPoints(button)
    end

    button.icon = art or button.icon

    return true
end

function M:RefreshHeaderGlyphs()
    if not self:MinimapHeaderShown() then return false end

    local map = getglobal("Minimap")
    local up = not map or not map.IsShown or map:IsShown()

    local changed = setGlyph(getglobal("MinimapToggleButton"),
            up and GLYPH_MINUS or GLYPH_PLUS)

    --[[ The drawer says the same sentence about itself: plus opens, minus
         closes. ]]--
    local tray = self.minimapTray
    local open = tray and tray.IsShown and tray:IsShown()

    if setGlyph(self.minimapToggle, open and GLYPH_MINUS or GLYPH_PLUS) then
        changed = true
    end

    return changed
end

function M:HeaderButtons()
    --[[ Asked for rather than hoped for: the drawer's button is built the first
         time the collector runs, and the bar is applied before it. Waiting
         would give a bar with one button on it. ]]--
    self:MinimapTray()

    --[==[ **Sized rather than scaled, because they were never the same size.**

         `SetScale` multiplies whatever a frame already is, and these two are not
         the same thing: the drawer's button is sixteen pixels of ours and the
         client's collapse button is about thirty-two with its art laid out by
         XML. The same scale on both therefore kept the client's at twice the
         size, which is the button reported as too big.

         So both are given the square's own size and left at scale one, and the
         art they wear is told to fill them. ]==]
    return {
        { frame = getglobal("MinimapToggleButton"), key = "close" },
        { frame = self.minimapToggle, key = "drawer" },
    }
end

function M:PlaceHeaderButtons(on)
    local holder = self.minimapHeader
    if not holder then return false end

    --[==[ **The furniture pass takes its snapshot before this moves anything.**

         It reads the collapse button's anchor the first time it runs and puts
         that back when the map module is switched off -- and it runs *after*
         this does. Left to itself it would have recorded the bar as the button's
         home, so switching the module off would send the button back to a bar
         that is no longer there.

         Asked here instead, where it is still the client's own anchor being
         read. It only ever records once, so this is free on every pass but the
         first. ]==]
    self:RememberMinimapFurniture()

    local buttons = self:HeaderButtons()
    self.headerButtonHomes = self.headerButtonHomes or {}

    for i = 1, table.getn(buttons) do
        local button = buttons[i].frame

        if button and button.SetPoint then
            --[[ Read once, the first time this runs, and before anything here
                 has touched it: read again later and home would be the bar. ]]--
            if not self.headerButtonHomes[i] then
                local point, rel, relPoint, x, y

                if button.GetPoint then
                    point, rel, relPoint, x, y = button:GetPoint(1)
                end

                --[[ The art as well as the anchor, because this bar retextures
                     the client's collapse button so the pair matches -- and a
                     button that cannot be given its own picture back is a
                     button somebody has lost the look of. ]]--
                local art = button.GetNormalTexture and button:GetNormalTexture()

                self.headerButtonHomes[i] = {
                    parent = button.GetParent and button:GetParent(),
                    scale = (button.GetScale and button:GetScale()) or 1,
                    point = point and { point, rel, relPoint, x or 0, y or 0 } or nil,
                    texture = art and art.GetTexture and art:GetTexture() or nil,
                    width = button.GetWidth and button:GetWidth() or nil,
                    height = button.GetHeight and button:GetHeight() or nil,

                    --[[ Its hover handlers too: this bar gives the collapse
                         button a tooltip it did not have, and taking that back
                         off means remembering there was nothing there. ]]--
                    onEnter = button.GetScript and button:GetScript("OnEnter"),
                    onLeave = button.GetScript and button:GetScript("OnLeave"),
                    hooked = true,
                }
            end

            local home = self.headerButtonHomes[i]

            if on then
                local slot = self:HeaderSlot(buttons[i].key, buttons[i].scale)

                --[[ From the right in, in the order they are listed: the one
                     that puts the map away sits at the end, which is where a
                     close control lives everywhere else in this interface. ]]--
                if slot then
                    slot:ClearAllPoints()
                    slot:SetPoint("CENTER", holder, "RIGHT",
                            -(HEADER_BUTTON / 2) - HEADER_GAP
                                    - ((i - 1) * (HEADER_BUTTON + HEADER_GAP)), 0)
                    slot:Show()
                end

                if button.SetParent then button:SetParent(slot or holder) end

                --[[ One size for both, and the art stretched to it: the client's
                     own textures are laid out by XML at their own size and do
                     not follow a frame that has been resized under them. ]]--
                if button.SetScale then button:SetScale(1) end
                if button.SetWidth then button:SetWidth(HEADER_BUTTON) end
                if button.SetHeight then button:SetHeight(HEADER_BUTTON) end

                local art = button.GetNormalTexture and button:GetNormalTexture()

                if art and art.SetAllPoints then
                    art:ClearAllPoints()
                    art:SetAllPoints(button)
                end

                --[==[ **And nothing of the old art left underneath.**

                     The collapse button carries a pushed and a highlight texture
                     as well as a normal one, both drawn at the size its XML
                     chose. Left alone they are the large red control this bar is
                     replacing, appearing on mouse-down and mouse-over. ]==]
                if button.SetPushedTexture then
                    button:SetPushedTexture(GLYPH_PUSHED)
                end

                if button.SetHighlightTexture then
                    button:SetHighlightTexture(
                            "Interface\\Buttons\\UI-Common-MouseHilight")
                end

                button:ClearAllPoints()
                button:SetPoint("CENTER", slot or holder, "CENTER", 0, 0)

                if button.SetFrameLevel and holder.GetFrameLevel then
                    button:SetFrameLevel((holder:GetFrameLevel() or 0) + 2)
                end

                --[[ And the glyph, so the pair matches from the first draw
                     rather than from the first time the map is toggled. ]]--
                self:RefreshHeaderGlyphs()

                --[==[ **And it says what it does.**

                     A red cross needs no caption. A small square minus beside a
                     small square plus does, and this is the one that puts the
                     whole map away -- which is a surprise to press by
                     accident. ]==]
                if buttons[i].key == "close" and button.SetScript then
                    button:SetScript("OnEnter", function()
                        if not GameTooltip then return end

                        local map = getglobal("Minimap")
                        local up = not map or not map.IsShown or map:IsShown()

                        OB.OwnTooltip(this, "ANCHOR_LEFT")
                        GameTooltip:AddLine(up and "Hide The Minimap"
                                or "Show The Minimap")
                        GameTooltip:Show()
                    end)

                    button:SetScript("OnLeave", function()
                        if GameTooltip then GameTooltip:Hide() end
                    end)
                end
            else
                local slot = self.headerSlots and self.headerSlots[buttons[i].key]
                if slot then slot:Hide() end

                if home.parent and button.SetParent then
                    button:SetParent(home.parent)
                end

                if button.SetScale then button:SetScale(home.scale or 1) end

                --[[ Its own picture back, and the note that it is wearing ours
                     cleared with it. ]]--
                if home.texture and button.SetNormalTexture then
                    button:SetNormalTexture(home.texture)
                    button.eqGlyph = nil
                end

                if home.width and button.SetWidth then button:SetWidth(home.width) end
                if home.height and button.SetHeight then button:SetHeight(home.height) end

                if home.hooked and button.SetScript then
                    button:SetScript("OnEnter", home.onEnter)
                    button:SetScript("OnLeave", home.onLeave)
                end

                if home.point then
                    button:ClearAllPoints()
                    button:SetPoint(home.point[1], home.point[2], home.point[3],
                            home.point[4], home.point[5])
                end
            end
        end
    end

    return on and true or false
end

--[==[ **Where the player is, on the minimap, in the coordinates people read
     out to each other.**

     Nothing in 1.12 shows this anywhere, and two addons that add it draw two
     readouts on top of each other -- which is what was reported. This is one,
     it belongs to the map module, and it can be switched off.

     Under the map rather than on it: the corners of a round minimap are empty
     and the middle is the thing being looked at. ]==]
--[==[ **In a frame of its own, because a font string cannot be dragged.**

     The readout was a string parented to the bar, which is fine until somebody
     wants it somewhere else -- and everything else this addon draws moves in
     edit mode. A `FontString` has no drag scripts, cannot be registered with
     edit mode, and has nothing to outline; only a frame does.

     So the string lives in one. Same rules as the bar above it: locked through
     the profile rather than behind a switch of its own, dropped position stored
     from the centre of the screen, and back under the map when it has never
     been moved. ]==]
function M:MinimapCoordFrame()
    if self.minimapCoordFrame then return self.minimapCoordFrame end

    local map = getglobal("Minimap")
    if not map or not CreateFrame then return nil end

    local frame = CreateFrame("Frame", "EquadisOverhaulMinimapCoords",
            getglobal("MinimapCluster") or map)

    frame:SetWidth(70)
    frame:SetHeight(14)

    if frame.SetFrameStrata then frame:SetFrameStrata("MEDIUM") end
    if frame.SetFrameLevel and map.GetFrameLevel then
        frame:SetFrameLevel((map:GetFrameLevel() or 0) + 10)
    end

    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")

    --[[ Same rule as the header bar: the mouse follows the lock. ]]--

    frame:SetScript("OnDragStart", function()
        if OB.profile and OB.profile.locked then return end

        frame:StartMoving()
        frame.dragging = true
    end)

    frame:SetScript("OnDragStop", function()
        if not frame.dragging then return end

        frame.dragging = nil
        frame:StopMovingOrSizing()

        EquadisClassicOverhaul.modules.map:StoreMinimapCoords()
    end)

    frame.text = OB.NewText(frame, "OVERLAY", "GameFontNormalSmall")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)

    self.minimapCoordFrame = frame
    self.minimapCoords = frame.text

    return frame
end

function M:MinimapCoordText()
    local frame = self:MinimapCoordFrame()
    return frame and frame.text
end

--[[ Where it ended up, from the centre of the screen -- the rule the bar, the
     meters and the minimap itself all follow. ]]--
function M:StoreMinimapCoords()
    local frame = self.minimapCoordFrame
    if not frame or not frame.GetLeft or not frame:GetLeft() then return false end

    local cfg = self:Config()
    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.coordPosition = {
        x = OB.Round((frame:GetLeft() + (frame:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((frame:GetBottom() + (frame:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[[ Put back where it was dropped, or under the map when it has never been
     moved -- which is where somebody reading a coordinate off the map looks. ]]--
function M:PlaceMinimapCoords()
    local frame = self.minimapCoordFrame
    local map = getglobal("Minimap")
    if not frame or not map then return false end

    --[==[ **Not while it is being dragged**, which is the whole of the bug this
         guard exists for.

         The readout is redrawn four times a second, and every redraw placed it
         again -- so the frame was anchored back under the map between one mouse
         movement and the next and could not be moved at all. Reported as the
         coordinates snapping back.

         The bar above has the same shape and never showed it, because the bar
         is placed when a setting changes rather than on a clock. ]==]
    if frame.dragging then return false end

    local saved = self:Config().coordPosition

    --[==[ **And only when the answer has changed.**

         Re-anchoring to the same point every quarter second is work for nothing
         and a chance to be wrong for something. The key is what the placement
         depends on: a stored position, or the map. ]==]
    local key = saved and ((saved.x or 0) .. ":" .. (saved.y or 0)) or "map"

    if frame.eqPlaceKey == key and frame.GetNumPoints
            and frame:GetNumPoints() > 0 then
        return true
    end

    frame.eqPlaceKey = key
    frame:ClearAllPoints()

    if saved and ((saved.x or 0) ~= 0 or (saved.y or 0) ~= 0) then
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x or 0, saved.y or 0)
        return true
    end

    frame:SetPoint("TOP", map, "BOTTOM", 0, -2)
    return true
end

--[==[ **Atlas's pins, switched through Atlas's own flag.**

     `AtlasCFM.MapMarkers.UpdateMarkers` reads `AtlasCFMOptions.ShowMapMarkers`
     and clears every pin when it is off, which is exactly the behaviour wanted
     -- so this writes that flag and asks for a redraw rather than reaching in
     and hiding frames Atlas will put back on its next update.

     Guarded on both halves being present: Atlas is bundled here and is still
     somebody else's addon, and a build without it should cost nothing rather
     than error. ]==]
function M:ApplyAtlasIcons()
    if type(AtlasCFMOptions) ~= "table" then return false end

    local on = OB.ModuleEnabled("map") and self:Config().atlasMapIcons
    AtlasCFMOptions.ShowMapMarkers = on and true or false

    --[==[ **One owner for the bottom-left corner.**

         Two cursor readouts overlapping there, reported with a screenshot -- and
         `/eq coorddebug` named the other one: `AtlasCFMWorldMapCursorText`, from
         **the Atlas build this addon bundles**. Not a foreign addon at all; ECO
         shipping two of its own things into one corner.

         Atlas has a switch for it and this addon already drives Atlas's options
         from here, so it is switched at the source rather than faded at runtime.
         The runtime silencer stays for genuinely foreign readouts -- somebody
         else's addon is not ours to reconfigure -- but it should not be doing the
         work for a bundle we control.

         Followed to ECO's own setting rather than pinned off: switch **Show Map
         Coordinates** off and Atlas's come back, so the corner is never empty
         because two features both stood aside. ]==]
    local ours = OB.ModuleEnabled("map") and self:Config().mapCoordinates

    AtlasCFMOptions.AtlasCursorCoords = (not ours) and true or false

    local atlasCoords = getglobal("AtlasCFMWorldMapCursorText")

    if atlasCoords and ours and atlasCoords.Hide then atlasCoords:Hide() end

    if AtlasCFM and AtlasCFM.MapMarkers
            and type(AtlasCFM.MapMarkers.UpdateMarkers) == "function" then
        pcall(AtlasCFM.MapMarkers.UpdateMarkers)
    end

    return on
end

--[[ The three boxes placed and filled, or put away. Called from the size pass
     as well, because a header is measured against the map it sits over. ]]--
function M:ApplyMinimapHeader()
    local holder = self:MinimapHeader()
    if not holder then return false end

    local cfg = self:Config()
    local map = getglobal("Minimap")
    local on = OB.ModuleEnabled("map") and cfg.locationTimeArt and map

    --[==[ **The client's own two go away while ours are up, and come back when
         they are not.**

         `MinimapZoneTextButton` is the bar across the top and `GameTimeFrame`
         is the clock on the ring. Both are the client's, and a module that hides
         them and cannot put them back has taken something away rather than
         replaced it. ]==]
    local zone = getglobal("MinimapZoneTextButton")
    local top = getglobal("MinimapBorderTop")
    local clock = getglobal("GameTimeFrame")

    if not on then
        holder:Hide()
        self:PlaceHeaderButtons(false)

        if zone and cfg.minimapZoneBar and zone.Show then zone:Show() end
        if top and cfg.minimapZoneBar and top.Show then top:Show() end
        if clock and cfg.minimapDayNight and clock.Show then clock:Show() end

        return false
    end

    --[==[ **The bar the name is painted on goes too, not just the button on
         it.**

         Hiding `MinimapZoneTextButton` alone left the client's own zone name on
         screen -- which is what was reported. The name is drawn on
         `MinimapBorderTop`, a separate region welded across the top of the
         minimap art, and it was still up there under ours. ]==]
    if zone and zone.Hide then zone:Hide() end
    if top and top.Hide then top:Hide() end
    if clock and clock.Hide then clock:Hide() end

    local width = map.GetWidth and map:GetWidth() or 140

    self:PlaceMinimapHeader()
    holder:SetWidth(width)
    holder:SetHeight(HEADER_H)

    --[==[ **The two buttons take the right end and the text shares what is
         left**, the location taking whatever the time does not -- so hiding the
         time widens the name rather than leaving a hole in the middle of one
         bar.

         Three gaps rather than two: one either side of each button and one
         between the pair, because they sit in squares of their own now and a
         square flush against the bar's edge reads as a mistake. ]==]
    local timeShown = cfg.showTime and true or false
    local buttonsW = (2 * HEADER_BUTTON) + (3 * HEADER_GAP)
    local locationW = width - buttonsW - (timeShown and (TIME_W + HEADER_GAP) or 0)

    --[[ Inside the bar's own edge, which is three pixels of border. ]]--
    holder.location:ClearAllPoints()
    holder.location:SetPoint("LEFT", holder, "LEFT", HEADER_GAP, 0)
    holder.location:SetWidth(locationW - HEADER_GAP)
    holder.location:SetHeight(HEADER_H)

    holder.clock:ClearAllPoints()
    holder.clock:SetPoint("RIGHT", holder, "RIGHT", -buttonsW, 0)
    holder.clock:SetWidth(TIME_W)
    holder.clock:SetHeight(HEADER_H)

    self:PlaceHeaderButtons(true)

    if cfg.showLocation then holder.location:Show() else holder.location:Hide() end
    if timeShown then holder.clock:Show() else holder.clock:Hide() end

    holder:Show()

    if OB.MarkMovable then OB.MarkMovable(holder, "Minimap Bar") end

    self:RefreshMinimapHeader()
    return true
end

--[==[ **What the two boxes say, refreshed on the tick.**

     The zone changes on an event and the clock changes on its own, so both are
     written here rather than each having a reason of its own to be redrawn --
     one string comparison per second is cheaper than the event plumbing would
     be. ]==]
function M:RefreshMinimapHeader()
    local holder = self.minimapHeader
    if not holder or not holder:IsShown() then return false end

    local cfg = self:Config()

    if cfg.showLocation and type(GetMinimapZoneText) == "function" then
        local zone = GetMinimapZoneText()

        if holder.location.eqText ~= zone then
            holder.location.eqText = zone
            holder.location.text:SetText(zone or "")

            --[[ In the colour the client paints the zone name, which says
                 whether it is friendly, hostile or contested -- the one fact
                 that label carries besides the name. ]]--
            local pvp = getglobal("MinimapZoneText")

            if pvp and pvp.GetTextColor then
                holder.location.text:SetTextColor(pvp:GetTextColor())
            end
        end

        OB.ApplyFont(holder.location.text, tonumber(cfg.zoneSize) or 11, "map")
    end

    if cfg.showTime then
        --[[ The clock's own string: server or machine, twelve hour or
             twenty-four. The frame it used to be written in is gone; the
             question it answered is not. ]]--
        local text = self:ClockText()

        if holder.clock.eqText ~= text then
            holder.clock.eqText = text
            holder.clock.text:SetText(text)
        end

        OB.ApplyFont(holder.clock.text, tonumber(cfg.zoneSize) or 11, "map")
    end

    self:RefreshMinimapCoords()
    return true
end

--[[ The coordinates, in the same pass. Hidden as a whole when switched off, so
     nothing is drawn for somebody who does not want them. ]]--
function M:RefreshMinimapCoords()
    local frame = self:MinimapCoordFrame()
    local text = frame and frame.text
    if not text then return false end

    local cfg = self:Config()
    local map = getglobal("Minimap")

    if not OB.ModuleEnabled("map") or not cfg.minimapCoordinates or not map then
        text:Hide()
        frame:Hide()
        return false
    end

    self:PlaceMinimapCoords()
    OB.ApplyFont(text, tonumber(cfg.zoneSize) or 11, "map")

    local x, y

    if type(GetPlayerMapPosition) == "function" then
        x, y = GetPlayerMapPosition("player")
    end

    --[[ Both zero is the client saying it does not know -- inside an instance,
         or mid-loading-screen -- rather than a corner of the map. ]]--
    if x and y and (x > 0 or y > 0) then
        text:SetText(format("%.1f, %.1f", x * 100, y * 100))
    else
        text:SetText("--, --")
    end

    --[[ Sized to what it says, so the thing being dragged is the thing being
         read rather than a box around it. ]]--
    if text.GetStringWidth then
        local width = text:GetStringWidth()
        if width and width > 0 then frame:SetWidth(width + 8) end
    end

    text:Show()
    frame:Show()

    if OB.MarkMovable then OB.MarkMovable(frame, "Minimap Coordinates") end

    return true
end

--[[ `MinimapZoneText` is the one label on screen that answers "where am I", and
     the client draws it at a fixed size in a font nobody chose.

     Left alone entirely when `zoneSize` is zero, which is the default: this
     module switching on should not silently take over a font string another
     addon may already have styled. ]]--
function M:ApplyZone()
    local text = getglobal("MinimapZoneText")
    if not text or not text.SetTextColor then return false end

    if not OB.ModuleEnabled("map") then return false end

    local cfg = self:Config()

    local color = cfg.zoneColor or { 1, 1, 1, 1 }
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)

    local size = tonumber(cfg.zoneSize) or 0
    if size > 0 then OB.ApplyFont(text, size, "map") end

    return true
end



-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

--[==[ **Which marker replaces the green dot.**

     One constant, because the choice of art is the one thing here somebody is
     likely to want different and it should be a line to change rather than a
     hunt.

     The class-circle atlas is what this addon already ships and already reads --
     the unit frames draw their circular class portraits out of it -- so a
     replacement built on it needs no new art and gives each class a marker of
     its own shape as well as its own colour. ]==]
--[==[ **One file per class, rather than one square of an atlas.**

     The markers were cut from `UI-CLASSES-CIRCLES` with a texcoord per class,
     which is how the client's own class art is packed. The replacements are
     supplied as separate images, and separate is the easier shape to live with:
     no coordinates to get wrong, and editing one class cannot disturb another.

     Padded to sixty-four square rather than scaled. They arrived at 37x35 and
     1.12 will not load a texture whose sides are not powers of two -- the same
     rule that made the merchant junk icon draw nothing at all. Padding keeps
     every pixel the artist drew; scaling would soften art made at this size on
     purpose. ]==]
local PLAYER_ICON_ROOT = OB.mediaPath .. "textures\\mapicons\\"

--[[ The three that are not classes. `GREY` is the fallback: a marker for
     somebody whose class cannot be read should say "I do not know" rather than
     assert a class at random. ]]--
local PLAYER_ICON_FALLBACK = "GREY"

--[==[ **The size setting was being applied to the file, not to the mark.**

     Every one of the twelve marker textures is a 64x64 file with a disc of ink
     about 34 pixels across floating in the middle of it -- a hair over half the
     width, and 17% of the area. Drawn whole, a marker set to 20 pixels puts a
     **nine pixel** disc on screen, which is smaller than the client's own blip
     underneath it. That is the reported symptom exactly: a tiny class icon
     sitting inside a gold ring, reading as two markers rather than one.

     The same mistake the merchant's trash icon made, from the other direction.
     There it was fixed by cropping the file; here the files are shipped and a
     crop would need the client restarted to take, so it is done with
     coordinates instead -- which is exact, and takes effect on a reload.

     Measured off the alpha of all twelve rather than eyeballed. The ink spans
     x 13..46 and y 15..47 across the set, so it is **not centred**: its middle
     is two pixels left of the file's. Cropping to the ink's own centre fixes
     that as well, which is why the marker never sat quite over the blip.

     One pixel of bleed each side, so nothing is clipped by rounding. ]==]
local ICON_INK_LEFT = 13 / 64
local ICON_INK_RIGHT = 47 / 64
local ICON_INK_TOP = 15 / 64
local ICON_INK_BOTTOM = 49 / 64

--[[ Applied wherever one of these markers is drawn, so `size` means the size of
     the thing you can see. A texture that is not one of ours is not cropped:
     the client's own dot, put back when the setting is switched off, is a whole
     file and would lose its edges. ]]--
function OB.SetPlayerIconCoords(icon, ours)
    if not icon or not icon.SetTexCoord then return false end

    if ours then
        icon:SetTexCoord(ICON_INK_LEFT, ICON_INK_RIGHT,
                ICON_INK_TOP, ICON_INK_BOTTOM)
    else
        icon:SetTexCoord(0, 1, 0, 1)
    end

    return true
end

function OB.PlayerMapIcon(class)
    if class and class ~= "" then
        return PLAYER_ICON_ROOT .. class
    end

    return PLAYER_ICON_ROOT .. PLAYER_ICON_FALLBACK
end


--[==[ **The world map's party and raid markers, by name.**

     `WorldMapParty1` through 4 and `WorldMapRaid1` through 40, each holding a
     texture called `$parentIcon`. The number is the unit: `WorldMapParty2` is
     `party2`, which is the only reason a marker can be told whose it is.

     The minimap's dots are not here and cannot be. The client draws those itself
     from one blip sheet and gives an addon nothing to take hold of -- there is no
     per-unit frame to retexture. ]==]
--[==[ **`WorldMapPlayer` is deliberately not in this list.**

     It was, briefly. The reported symptom -- every other party member wearing
     their class while the player did not -- was the player's marker being its own
     frame with `id` zero and no number in its name, so a loop over the numbered
     sets walked straight past it. That reading was right and the conclusion was
     wrong: the answer to "why is the player different" turned out to be that the
     player *should* be different.

     A class icon says which of several people this one is. There is only ever
     one of you, so it answers a question nobody asks -- and it costs the thing
     the arrow does say, which is which way you are facing. Left to the client. ]==]
local ICON_SETS = {
    { frame = "WorldMapParty", unit = "party", count = 4 },
    { frame = "WorldMapRaid", unit = "raid", count = 40 },
}

--[==[ **`$parentIcon` and nothing else.**

     Every marker this touches inherits `WorldMapUnitTemplate`, which gives it
     one -- read out of the client's own `WorldMapFrameTemplates.xml`. A marker
     that has none is not one of ours.

     There used to be a second branch here for a build where the global was the
     texture itself, tested with `if frame.SetTexture`. That question cannot be
     answered that way: a frame answers politely to anything on this client, and
     in the harness the auto-faking metatable made it true for every frame. It
     was a guess, and a guess that could swallow a whole frame silently. ]==]
function M:PlayerIconTexture(name)
    local icon = getglobal(name .. "Icon")
    if icon and icon.SetTexture then return icon end

    return nil
end

--[==[ **Bigger, and above the pins.**

     Both belong to the frame rather than to the texture: the client's markers
     set their icon to fill the frame, so the frame is what has a size, and a
     draw layer ranks only *within* one frame -- it can say nothing about this
     marker against a quest pin that is a frame of its own. That is the same
     rule the party frame's border ran into from the other side.

     Levels are set absolutely rather than nudged: this runs on every map event,
     and a relative bump would climb by one each time until the markers were
     above the window they live in. ]==]
local ICON_LEVEL_OVER_PINS = 20

function M:StyleIconFrame(name)
    local frame = getglobal(name)
    if not frame then return false end

    local size = tonumber(self:Config().playerIconSize) or 13
    if size < 8 then size = 8 end
    if size > 48 then size = 48 end

    if frame.SetWidth then frame:SetWidth(size) end
    if frame.SetHeight then frame:SetHeight(size) end

    local button = getglobal("WorldMapButton")
    if frame.SetFrameLevel and button and button.GetFrameLevel then
        frame:SetFrameLevel((button:GetFrameLevel() or 0) + ICON_LEVEL_OVER_PINS)
    end

    return true
end

--[==[ **Everything drawn on a group marker, said out loud.**

     A green square appeared behind the party markers on the world map and not
     behind the raid ones. Nothing in this module can produce that: both sets go
     through the same walk, take the same texture from the same function, and
     differ only in how the unit behind a frame is found. So whatever is drawing
     it is on the frame already -- another region the client or another addon
     put there, or a child frame of its own -- and none of that is knowable from
     outside the game.

     It prints both sets side by side for that reason. Party against raid with
     the same fields under each is the comparison that names the difference,
     where either alone is a list of things that all look plausible. ]==]
function M:DebugIcons()
    local say = function(text) OB.Raw("  " .. text) end
    OB.Print("world map group markers:", "Map")

    local cfg = self:Config()
    say("replacePlayerIcons is " .. tostring(cfg and cfg.replacePlayerIcons)
            .. ", module enabled: " .. tostring(OB.ModuleEnabled("map"))
            .. ", size " .. tostring(cfg and cfg.playerIconSize))

    --[[ A few of each. Forty raid frames would push the party half off the top
         of the chat window, which is the half being compared against. ]]--
    local sets = {
        { frame = "WorldMapParty", count = 4 },
        { frame = "WorldMapRaid", count = 4 },
        { frame = "WorldMapPlayer", count = 0 },
    }

    for s = 1, table.getn(sets) do
        local set = sets[s]

        for i = 0, set.count do
            --[[ `WorldMapPlayer` has no number; everything else is numbered
                 from one. ]]--
            local name = (set.count == 0) and set.frame or (set.frame .. i)

            if i > 0 or set.count == 0 then
                self:DebugOneIcon(name)
            end
        end
    end
end

--[[ One marker: the frame, then everything drawn on it, then anything hanging
     off it. Guarded call by call because a region answers a different set of
     methods on every client, and a debug command that errors half way through
     is worse than none at all. ]]--
function M:DebugOneIcon(name)
    local frame = getglobal(name)

    if not frame then
        return OB.Raw("  " .. name .. ": no such frame")
    end

    local shown = frame.IsShown and frame:IsShown()
    local width = frame.GetWidth and frame:GetWidth()
    local level = frame.GetFrameLevel and frame:GetFrameLevel()

    OB.Raw("  " .. name .. ": " .. (shown and "shown" or "hidden")
            .. ", " .. tostring(width and OB.Round(width)) .. "px"
            .. ", level " .. tostring(level)
            .. ", unit " .. tostring(frame.unit))

    --[[ Every region on it, not only the one this module writes to. The whole
         question is what the *other* ones are. ]]--
    local count = frame.GetNumRegions and frame:GetNumRegions() or 0
    local regions = (count > 0 and frame.GetRegions) and { frame:GetRegions() } or {}

    if count == 0 then OB.Raw("      no regions") end

    for r = 1, table.getn(regions) do
        local region = regions[r]

        if region then
            local kind = region.GetObjectType and region:GetObjectType() or "?"
            local layer = region.GetDrawLayer and region:GetDrawLayer() or "?"
            local texture = region.GetTexture and region:GetTexture() or nil
            local up = region.IsShown and region:IsShown()

            local tint = ""
            if region.GetVertexColor then
                local cr, cg, cb, ca = region:GetVertexColor()
                tint = " tint " .. tostring(OB.Round((cr or 1) * 100))
                        .. "/" .. tostring(OB.Round((cg or 1) * 100))
                        .. "/" .. tostring(OB.Round((cb or 1) * 100))
                        .. "/" .. tostring(OB.Round((ca or 1) * 100))
            end

            OB.Raw("      region " .. r .. ": " .. tostring(kind)
                    .. " " .. tostring(region.GetName and region:GetName() or "unnamed")
                    .. ", " .. tostring(layer)
                    .. ", " .. (up and "shown" or "hidden")
                    .. ", texture " .. tostring(texture) .. tint)
        end
    end

    --[[ And anything parented to it, because a square drawn by another addon
         is as likely to be a frame of its own as a region on this one. ]]--
    local kids = frame.GetNumChildren and frame:GetNumChildren() or 0

    if kids > 0 and frame.GetChildren then
        local children = { frame:GetChildren() }

        for c = 1, table.getn(children) do
            local child = children[c]
            OB.Raw("      child " .. c .. ": "
                    .. tostring(child and child.GetName and child:GetName() or "unnamed")
                    .. ", " .. ((child and child.IsShown and child:IsShown())
                            and "shown" or "hidden"))
        end
    end

    --[[ What this module remembers as the client's own, which is what it hands
         back when the feature is switched off. ]]--
    local saved = self.iconOriginals and self.iconOriginals[name]
    if saved then
        OB.Raw("      we remember the client's as " .. tostring(saved.texture))
    end
end

--[==[ Captured before anything is changed, so switching the setting off puts the
     client's own dot back rather than leaving whatever we last drew. ]==]
function M:CapturePlayerIcon(icon, name)
    self.iconOriginals = self.iconOriginals or {}
    if self.iconOriginals[name] then return end

    self.iconOriginals[name] = {
        texture = icon.GetTexture and icon:GetTexture() or nil,
    }
end

--[==[ **Which unit a marker is actually showing, asked of the marker.**

     The frame number is the unit number for `WorldMapParty1..4` and is *not*
     for `WorldMapRaid1..40`. Read out of the client's own placement pass:

         partyMemberFrame = _G["WorldMapRaid" .. playerCount + 1];
         ...
         partyMemberFrame.unit = unit;
         playerCount = playerCount + 1;

     The raid frames are handed out in the order raid members are found *with a
     position on this map*, so `WorldMapRaid3` is the third one placed rather
     than `raid3`. Deriving the unit from the number therefore paints a class on
     whoever happens to be third -- which is the reported symptom exactly: the
     right icons, in the right places, on the wrong people.

     The client leaves the answer on the frame, so that is where it is read
     from. Two things it also leaves:

     - **`frame.name` set means this is not a unit at all.** Raid frames past
       the group are reused for battlefield positions, which come from
       `GetBattlefieldPosition` and have a name and no unit id. Those get the
       fallback marker rather than a class read off a stale field.
     - **`frame.unit` on a party frame** is set by the template's own OnLoad and
       already agrees with the number, so the two paths do not disagree.

     Falls back to the number only for party, where it is correct by
     construction. ]==]
function M:IconFrameUnit(frame, set, index)
    local unit = frame and frame.unit

    --[==[ **A unit token, and checked rather than trusted.**

         The first version read `frame.unit` if it was a non-empty string and
         treated `frame.name` as "this is a battlefield position, not a unit".
         Both halves were wrong to lean on. `name` is not ours: the test harness
         puts the frame's own name there on every frame, so every marker looked
         like a battlefield entry and fell back to grey. A neighbouring addon
         may put anything on a frame for its own reasons, and neither field is
         documented as belonging to the client.

         So the token is matched against the shape it has to have. That is true
         of the thing being asked -- "is this raid7" -- rather than of a field
         that happens to be set, and it cannot be made wrong by somebody else
         writing to the frame. ]==]
    if type(unit) == "string"
            and string.find(unit, "^" .. set.unit .. "%d+$") then
        return unit
    end

    --[[ Party frames are numbered by unit -- the client's own template sets
         `this.unit = "party"..this:GetID()` -- so the number is a safe answer
         there. Raid frames are packed and it is not, so an unreadable one gets
         the fallback marker rather than a guess. ]]--
    if set.unit == "party" then return set.unit .. index end

    return nil
end

--[==[ **The arrow is drawn last, and drawn bigger.**

     It is the one marker on the map that is *you*, and it is the one thing on
     the map that says which way you are facing -- so it is the marker that must
     not be underneath somebody else's. Every other marker is placed at the same
     frame level, so which of two overlapping ones you can see is whatever order
     the client happened to create them in: on a crowded map the arrow
     disappeared under a raid member standing on the same spot.

     A fifth again above the rest of them rather than an absolute number, so it
     stays above whatever `StyleIconFrame` is doing without the two having to be
     kept in step by hand.

     **A fifth larger**, for the same reason it is on top: it is the marker you
     look for first and the only one whose *shape* carries information. Taken
     off the same setting the others use, so moving that slider moves all of
     them together and the arrow stays the bigger one. ]==]
local ARROW_SCALE = 1.2
local ARROW_LEVEL_OVER_ICONS = 10

--[==[ **The arrow is where you are, and nothing is allowed over it.**

     The world map is a pile of other people's pins: Questie's objectives, Atlas'
     entrances, whatever the zone happens to be carrying. They are all children
     of the same button as the arrow, they are made after it, and several of them
     raise themselves -- so the one marker on that map that answers "where am I"
     ends up underneath a stack of yellow dots.

     Frame level alone is not enough, because a pin in a higher **strata** wins
     whatever its level is. So both are read: the highest strata anything on the
     map is drawn in, and the highest level inside it, and the arrow goes one
     clear step above.

     **Capped below `TOOLTIP`** deliberately -- an arrow drawn over the tooltip
     you opened by hovering a pin is a different bug of the same kind. ]==]
local STRATA_ORDER = {
    BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4,
    DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8,
}

local STRATA_NAME = {
    "BACKGROUND", "LOW", "MEDIUM", "HIGH",
    "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}

--[[ One clear step, rather than the highest number the client will take: a
     level that is merely *above* everything is what is wanted, and a huge one
     is a number somebody else's addon then has to beat. ]]--
local ARROW_HEADROOM = 4

--[[ Below the tooltip, always. ]]--
local ARROW_STRATA_CAP = 6

--[==[ **How high the pins on the map are drawn**, as a strata and a level.

     Two levels deep, because a pin is not always a direct child: several quest
     addons put theirs inside a holder frame, which is the same shape of problem
     the minimap's icon drawer had to solve. Deeper than that is somebody's own
     furniture rather than a marker. ]==]
function M:MapPinCeiling()
    local button = getglobal("WorldMapButton")
    if not button or not button.GetChildren then return nil end

    local arrow = getglobal("WorldMapPlayer")
    local strata, level = 0, 0

    local function look(frame, depth)
        if not frame or frame == arrow then return end

        if frame.IsShown and not frame:IsShown() then return end

        local s = frame.GetFrameStrata and STRATA_ORDER[frame:GetFrameStrata()]
        local l = frame.GetFrameLevel and frame:GetFrameLevel()

        if s and s > strata then strata, level = s, l or 0
        elseif s and s == strata and l and l > level then level = l end

        if depth > 0 and frame.GetChildren then
            local kids = { frame:GetChildren() }

            for i = 1, table.getn(kids) do look(kids[i], depth - 1) end
        end
    end

    local kids = { button:GetChildren() }
    for i = 1, table.getn(kids) do look(kids[i], 1) end

    if strata == 0 then return nil end

    return strata, level
end

--[[ Throttled, because `WORLD_MAP_UPDATE` fires on a timer while the map is
     open and walking every pin on it several times a second is real work for an
     answer that only changes when somebody else adds a pin. ]]--
function M:RaisePlayerArrow(force)
    if not OB.ModuleEnabled("map") then return false end

    local arrow = getglobal("WorldMapPlayer")
    if not arrow or not arrow.SetFrameLevel then return false end

    local now = (type(GetTime) == "function" and GetTime()) or 0

    if not force and (now - (self.arrowRaisedAt or -1)) < 0.3 then return false end
    self.arrowRaisedAt = now

    local button = getglobal("WorldMapButton")
    local base = (button and button.GetFrameLevel and button:GetFrameLevel()) or 0

    --[[ What the client had it in, read once and before anything here has
         touched it -- a strata this raised is a strata this has to be able to
         put back. ]]--
    if not self.arrowStrata and arrow.GetFrameStrata then
        self.arrowStrata = arrow:GetFrameStrata()
    end

    local strata, level = self:MapPinCeiling()

    --[==[ **Nothing else on the map**: the arrow goes clear of the button it
         sits on, which is what the marker styling used to do on its own, and
         back into the strata it started in.

         Coming back down matters: a map that had a quest addon's pins on it and
         no longer does would otherwise leave the arrow parked in a strata
         nothing else uses, which is a difference that only shows up as a
         surprise somewhere else. ]==]
    if not strata then
        if arrow.SetFrameStrata and self.arrowStrata then
            arrow:SetFrameStrata(self.arrowStrata)
        end

        arrow:SetFrameLevel(base + ICON_LEVEL_OVER_PINS + ARROW_LEVEL_OVER_ICONS)
        return true
    end

    if strata > ARROW_STRATA_CAP then strata = ARROW_STRATA_CAP end

    if arrow.SetFrameStrata and STRATA_NAME[strata] then
        arrow:SetFrameStrata(STRATA_NAME[strata])
    end

    arrow:SetFrameLevel((level or 0) + ARROW_HEADROOM)
    return true
end

function M:StylePlayerArrow()
    local frame = getglobal("WorldMapPlayer")
    if not frame then return false end

    --[==[ **Over everything, whatever else is switched on.**

         Being on top is not part of the marker styling: it is about the one
         thing on that map somebody is actually looking for, and it is wanted by
         anybody with a quest addon installed. So it runs before the setting
         below is read. ]==]
    self:RaisePlayerArrow(true)

    --[[ The *size* is left exactly as the client draws it when the marker
         styling is off. The arrow is the client's own and that part is a change
         to how ECO's markers sit around it, not a change to the arrow. ]]--
    if not (OB.ModuleEnabled("map") and self:Config().replacePlayerIcons) then
        return false
    end

    local size = tonumber(self:Config().playerIconSize) or 13
    if size < 8 then size = 8 end
    if size > 48 then size = 48 end

    size = OB.Round(size * ARROW_SCALE)

    if frame.SetWidth then frame:SetWidth(size) end
    if frame.SetHeight then frame:SetHeight(size) end

    local button = getglobal("WorldMapButton")
    if frame.SetFrameLevel and button and button.GetFrameLevel then
        frame:SetFrameLevel((button:GetFrameLevel() or 0)
                + ICON_LEVEL_OVER_PINS + ARROW_LEVEL_OVER_ICONS)
    end


    return true
end

function M:StylePlayerMapIcons()
    local cfg = self:Config()
    local on = OB.ModuleEnabled("map") and cfg.replacePlayerIcons

    for s = 1, table.getn(ICON_SETS) do
        local set = ICON_SETS[s]

        for i = 1, set.count do
            local name = set.frame .. i
            local icon = self:PlayerIconTexture(name)

            if icon then
                self:CapturePlayerIcon(icon, name)

                if on then
                    --[[ Asked of the frame rather than worked out from its
                         number, which is wrong for raid markers. See
                         `IconFrameUnit`. ]]--
                    local unit = self:IconFrameUnit(getglobal(name), set, i)
                    local class

                    --[[ Through the shared resolver: a group member's class
                         comes from the roster and survives them being out of
                         range, which is what a map marker most needs. ]]--
                    if unit and UnitExists(unit) then
                        class = OB.UnitClassToken(unit)
                    end

                    icon:SetTexture(OB.PlayerMapIcon(class))

                    --[[ Cropped to the ink, so the size setting is the size of
                         the marker rather than the size of the mostly empty
                         file it is painted in. See `OB.SetPlayerIconCoords`. ]]--
                    OB.SetPlayerIconCoords(icon, true)

                    --[==[ **Drawn as it was painted, with no tint at all.**

                         The old markers were cut from an atlas of class
                         *emblems* on a neutral ring, so a class colour had to be
                         applied over them to make a warrior's marker look like a
                         warrior. The replacements are painted per class already
                         -- the mage's is blue because it is the mage's -- and
                         multiplying that by the class colour again is what put a
                         red wash over everything.

                         So the tint is gone rather than defaulted off: a switch
                         that can only make correct art worse is not a setting,
                         it is a leftover. Explicitly reset, because the marker
                         may still be carrying one from the client or from a
                         previous pass. ]==]
                    if icon.SetVertexColor then
                        icon:SetVertexColor(1, 1, 1, 1)
                    end

                    self:StyleIconFrame(name)
                else
                    local saved = self.iconOriginals[name]

                    if saved then
                        icon:SetTexture(saved.texture)
                        OB.SetPlayerIconCoords(icon, false)
                        if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1, 1) end
                    end
                end
            end
        end
    end

    return true
end

--[==[ **How many yards the minimap is showing, which nothing will tell you.**

     There is no API for it. The numbers are the client's own and are the same
     ones `Astrolabe` carries -- checked against the copy TomTom-TWOW ships in
     this install rather than remembered, because a wrong diameter does not fail,
     it just puts every marker in the wrong place by a constant.

     Indexed by `Minimap:GetZoom()`, zero through five. ]==]
local MINIMAP_DIAMETER = {
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}

--[==[ **Indoors and outdoors use different tables and the client will not say
     which you are in.**

     What it will say is the two zoom cvars. `minimapInsideZoom` is the zoom the
     client snaps to indoors, so a current zoom equal to it means indoors --
     except when the two cvars are equal, where the answer is genuinely
     ambiguous and Astrolabe resolves it by nudging the zoom a step and looking
     again.

     That nudge is not done here. It is a visible flicker of the whole minimap,
     and this would be asking ten times a second; the ambiguity costs a wrong
     diameter in one case, and a flickering minimap costs it always. Assumed
     outdoors when ambiguous, which is where you are for almost all of a
     session. ]==]
--[==[ **Asked of the client, rather than inferred from the zoom.**

     The old test was `Minimap:GetZoom() == minimapInsideZoom`, on the reasoning
     that indoors is the zoom the client snaps to. It is -- right up until the
     wheel is touched. After that you are indoors at a zoom that is not the
     inside zoom, the test says outdoors, and every marker is placed against a
     diameter meant for open country.

     That is exactly the shape of the reported bug. Indoors with the two zoom
     cvars at 2 and 4: at full zoom, five, the test says outdoors and the
     markers are placed against 133 yards when the truth is 50, so they land at
     a third of their real distance and mostly outside the rim check. One notch
     out lands on four, which *is* `minimapInsideZoom`, the test starts saying
     indoors by coincidence, and everything is correct again. "Wrong zoomed all
     the way in, right one notch out" is the signature of a test that only
     answers correctly at one zoom.

     The client will say, if asked. Setting the zoom writes it into whichever of
     the two cvars is live, so setting a value neither one holds and reading
     which one moved is exact rather than inferred.

     **The flicker objection stood against the old caller, not this one.** Both
     `SetZoom` calls happen inside this function with no frame drawn between
     them, so nothing is visible; what could not be afforded was asking ten
     times a second, which is what `MinimapIndoors` caches against. ]==]
function M:DetectIndoors()
    if not Minimap or not Minimap.GetZoom or not Minimap.SetZoom then return nil end
    if type(GetCVar) ~= "function" then return nil end

    --[[ A hook on SetZoom that redraws would land back in here. ]]--
    if self.probingIndoors then return nil end

    local zoom = Minimap:GetZoom()
    if type(zoom) ~= "number" then return nil end

    local inside = tonumber(OB.CVar("minimapInsideZoom"))
    local outside = tonumber(OB.CVar("minimapZoom"))
    if not inside then return nil end

    --[[ A probe the answer cannot already be sitting on: equal to the current
         zoom and the client may write nothing, equal to either stored cvar and
         a match would prove nothing. Three exclusions out of six levels, so
         this never leaves the range. ]]--
    local probe = 0
    while probe == zoom or probe == inside or probe == outside do
        probe = probe + 1
    end

    self.probingIndoors = true
    Minimap:SetZoom(probe)
    local insideNow = tonumber(OB.CVar("minimapInsideZoom"))
    local outsideNow = tonumber(OB.CVar("minimapZoom"))
    Minimap:SetZoom(zoom)
    self.probingIndoors = nil

    --[==[ **Three answers, and "I could not tell" is one of them.**

         The first version returned `insideNow == probe`, so a client that wrote
         neither cvar came back `false` -- a confident "outdoors" built on no
         evidence, which is worse than the inference it replaced because it also
         skipped the fallback. The harness is exactly such a client, and said so.

         Whichever cvar moved to the probe is the live one. If neither did, the
         write did not take and this cannot answer; `nil` sends the caller to
         the inference instead of inventing a reading. ]==]
    if insideNow == probe then return true end
    if outsideNow == probe then return false end

    return nil
end

--[==[ **Cached against the zoom it was measured at.**

     This is read from the tick, and the probe above is two `SetZoom` calls that
     other addons may be watching -- so it runs when the answer can have changed
     and not otherwise. Every indoor/outdoor transition snaps the zoom, so a
     zoom that has not moved is an answer that has not changed. ]==]
function M:MinimapIndoors()
    if type(GetCVar) ~= "function" or not Minimap or not Minimap.GetZoom then
        return false
    end

    local zoom = Minimap:GetZoom() or 0

    --[==[ **Keyed on every input, not just the zoom.**

         The first version cached against the zoom alone, on the reasoning that
         an indoor/outdoor change always snaps it. That is true of the client
         and not true of the inputs: the two cvars are read here as well, and
         anything that writes them without moving the zoom leaves a cached
         answer standing over changed evidence. A stale `true` survived into a
         case that had become ambiguous, which is how the tests found it.

         The key is the whole of what the answer depends on, so it cannot go
         stale without changing. ]==]
    local key = zoom .. ":" .. tostring(OB.CVar("minimapInsideZoom"))
            .. ":" .. tostring(OB.CVar("minimapZoom"))

    if self.indoorsKey == key and self.indoorsIs ~= nil then
        return self.indoorsIs
    end

    local answer = self:DetectIndoors()

    --[[ A client that will not answer falls back to the old inference, which is
         right whenever the zoom has not been moved by hand -- worse than
         asking, better than assuming outdoors everywhere. ]]--
    if answer == nil then
        local inside = tonumber(OB.CVar("minimapInsideZoom"))
        local outside = tonumber(OB.CVar("minimapZoom"))

        if not inside then return false end
        if outside and inside == outside then return false end

        answer = (zoom == inside)
    end

    self.indoorsKey = key
    self.indoorsIs = answer

    return answer
end

--[[ Pixels per yard at the current zoom, or nil when the minimap cannot be
     measured -- which is a reason to draw nothing rather than to guess. ]]--
--[==[ **A resized minimap magnifies: the same ground, drawn larger.**

     This was changed to a fixed hundred-and-forty on the reading that a bigger
     frame reveals more world, and that was wrong. `/eq minimapdebug` settled
     it on a 220-pixel map at zoom 5 indoors, where the table says the minimap
     covers 50 yards:

         a 25 yard radius against a 110 pixel frame radius is 4.4 px/yard,
         which is exactly `width / diameter`.

     The other reading puts the 50-yard circle at 70 pixels of a 110-pixel
     frame, leaving a ring of ground the table says is not shown -- so the table
     is a statement about the frame's *whole* width whatever that width is, and
     the frame-independent constant was the error.

     It is Astrolabe's rule as well, which every 1.12 map addon uses and which
     works for people who resize their minimap. Reverting to it rather than
     keeping a second opinion.

     **Left as an observation with its evidence**, because the temptation to
     "fix" this again by reasoning is exactly what produced the wrong version.
     The numbers above came from the game; anything that disagrees with them
     needs its own run of that command, not an argument. ]==]
local STOCK_MINIMAP = 140

function M:MinimapScale()
    if not Minimap or not Minimap.GetZoom or not Minimap.GetWidth then
        return nil
    end

    local zoom = Minimap:GetZoom() or 0
    local table_ = self:MinimapIndoors() and MINIMAP_DIAMETER.indoor
            or MINIMAP_DIAMETER.outdoor

    local diameter = table_[zoom]
    if not diameter or diameter <= 0 then return nil end

    local width = Minimap:GetWidth()
    if not width or width <= 0 then width = STOCK_MINIMAP end

    return width / diameter
end

--[==[ **Where a unit is, in yards, relative to you.**

     `UnitPosition` is SuperWoW's and is friendly-only, which is exactly the set
     of units this draws: your own group. Without it there is no source for a
     position at all -- `GetPlayerMapPosition` is normalised to the zone and
     turning that into yards needs a table of every zone's dimensions, which is a
     different and much larger feature.

     **The axis convention is the one thing here that cannot be read off this
     install.** `range.lua` uses the same call for distance, and a magnitude does
     not care which way the axes point. World coordinates in this client run
     north on +x and west on +y, so east is -y and north is +x; if the markers
     come out mirrored or turned a quarter, this is the one place it is
     decided. ]==]
--[==[ `px` and `py` are the player's position when the caller already has it.

     Every marker is measured from the same player, so reading it once per pass
     rather than once per marker halves the calls -- which matters now that this
     runs every frame instead of ten times a second. Optional, because the
     diagnostic and the tests ask about one unit and should not have to know
     that. ]==]
function M:UnitOffsetYards(unit, px, py)
    if type(UnitPosition) ~= "function" then return nil end

    if type(px) ~= "number" then
        local ok
        ok, px, py = pcall(UnitPosition, "player")
        if not ok or type(px) ~= "number" then return nil end
    end

    local ok2, ux, uy = pcall(UnitPosition, unit)
    if not ok2 or type(ux) ~= "number" then return nil end

    --[==[ **East runs the other way, and that was the whole minimap bug.**

         This was settled once from a screenshot of a party member below and to
         the right of the player, read as a quarter turn and undone as the
         identity: east on +x, north on +y. That reading was wrong, and being
         wrong by a *rotation* is what made it survive so long -- every marker
         landed somewhere plausible, at roughly the right distance, so every
         investigation that followed went looking at the scale instead.

         The observation that settles it is not a rotation at all. Reported
         plainly: a player really thirty yards east is drawn thirty yards west,
         and the north-south position is right. That is a reflection in one
         axis, and no choice of rotation produces it.

         So the first component is negated and the second left alone. Written as
         `px - ux` rather than as a minus sign in front of the whole expression,
         because the sign *is* the fact here and a reader has to be able to see
         which way round it goes without unwrapping anything.

         **Why this is believable rather than another guess.** It agrees with
         how this client stores world positions -- the axis that reads as
         `x` counts westward, so the difference from the player is a distance
         *west* and east is its negative. The previous reading had no such
         backing; it had one screenshot and a plausible story about a quarter
         turn.

         **And it explains the symptom that never made sense**: the world map
         was always right and the minimap never was. The world map's markers are
         placed by the client from its own map coordinates and never touch this
         function. The minimap's are placed by us, from this. ]==]
    return (px - ux), (uy - py)
end

--[==[ **What the marker maths actually computed, in words.**

     Placing a marker on the minimap turns yards into pixels, and that
     conversion rests on one thing nothing here can observe: whether making the
     minimap frame bigger shows *more world* or *the same world larger*.

     If it magnifies, a yard is `width / diameter` pixels and a resized map
     needs no allowance. If it reveals more ground, a yard is a fixed
     `140 / diameter` however wide the frame is, and dividing by the live width
     pushes every marker outward by `width / 140`.

     Both are defensible from the code and they differ by a factor this install
     happens to make large -- the map is dragged out to 220. Rather than pick
     again, this prints the numbers beside a party member's real position, so
     one line of output says which reading is right.

     The two candidate distances are both shown. Whichever matches where the
     client's own dot actually sits is the rule, and the other is wrong. ]==]
function M:DebugMinimapMarkers()
    local say = function(text) OB.Raw("  " .. text) end
    OB.Print("minimap markers:", "Map")

    local map = getglobal("Minimap")
    if not map then return Say and Say("no minimap") end

    local width = map.GetWidth and map:GetWidth() or 0
    local zoom = map.GetZoom and map:GetZoom() or 0
    local indoors = self:MinimapIndoors()

    local table_ = indoors and MINIMAP_DIAMETER.indoor or MINIMAP_DIAMETER.outdoor
    local diameter = table_[zoom] or 0

    say("frame width " .. OB.Round(width) .. ", zoom " .. tostring(zoom)
            .. ", " .. (indoors and "indoors" or "outdoors"))

    --[==[ **Whether the indoors call can be trusted, said out loud.**

         It is a guess from two cvars: the client snaps the zoom to
         `minimapInsideZoom` indoors and to `minimapZoom` outdoors, so a zoom
         sitting on one of them names where you are -- unless it sits on both,
         where nothing here can tell. Astrolabe resolves that by nudging the
         zoom and looking again, which flickers the whole minimap; this reports
         the ambiguity instead of hiding it.

         It matters because the two tables differ by more than half: at zoom
         nought it is 300 yards indoors against 466 outdoors, so a wrong answer
         puts every marker half again too far out. ]==]
    local inside = tonumber(OB.CVar("minimapInsideZoom"))
    local outside = tonumber(OB.CVar("minimapZoom"))

    say("zoom cvars: inside " .. tostring(inside)
            .. ", outside " .. tostring(outside))

    if inside and outside and inside == outside then
        say("   both are the same, so indoors/outdoors here is a guess")
    elseif inside and zoom == inside then
        say("   the zoom sits on the inside cvar, so indoors is firm")
    elseif outside and zoom == outside then
        say("   the zoom sits on the outside cvar, so outdoors is firm")
    else
        say("   the zoom matches neither cvar -- the reading is a fallback")
    end

    say("diameter for that zoom: " .. OB.Round(diameter) .. " yards")

    if diameter <= 0 then return end

    --[==[ **Asked rather than assumed.**

         This printed a fixed label saying which rule was in use, and the rule
         then changed underneath it -- so the diagnostic went on naming the
         wrong one, which is worse than printing nothing. `MinimapScale` is the
         only thing that knows, so it is what is asked. ]==]
    local magnify = width / diameter
    local reveal = STOCK_MINIMAP / diameter
    local live = self:MinimapScale() or 0

    local function mark(value)
        if math.abs(value - live) < 0.0001 then return "   <-- in use" end
        return ""
    end

    say("if resizing magnifies:  " .. string.format("%.3f", magnify)
            .. " pixels per yard" .. mark(magnify))
    say("if resizing reveals:    " .. string.format("%.3f", reveal)
            .. " pixels per yard" .. mark(reveal))

    local units = self:MinimapGroupUnits()

    if table.getn(units) == 0 then
        say("no group member to measure against -- stand near one and try again")
        return
    end

    for i = 1, table.getn(units) do
        local unit = units[i]
        local east, north = self:UnitOffsetYards(unit)

        if east then
            local yards = math.sqrt((east * east) + (north * north))

            --[==[ **Which way, as well as how far.**

                 This printed a distance, and a distance cannot be wrong in a
                 way anybody can see -- which is why an east-west reflection sat
                 here for weeks while every reading of this output looked
                 reasonable. A signed pair can be checked against the person
                 standing in front of you. ]==]
            say((UnitName(unit) or unit) .. ": " .. OB.Round(yards)
                    .. " yards away, " .. OB.Round(math.abs(east)) .. " "
                    .. (east >= 0 and "east" or "west") .. " and "
                    .. OB.Round(math.abs(north)) .. " "
                    .. (north >= 0 and "north" or "south"))
            say("   magnify puts it " .. OB.Round(yards * magnify)
                    .. "px out, reveal puts it " .. OB.Round(yards * reveal)
                    .. "px out, map radius is " .. OB.Round(width / 2) .. "px")
        else
            say((UnitName(unit) or unit) .. ": no position (needs SuperWoW)")
        end
    end
end

--[[ The group, and never the player: your own blip is the arrow in the middle
     and the minimap is already centred on you. ]]--
function M:MinimapGroupUnits()
    local out = {}

    if type(GetNumRaidMembers) == "function" and (GetNumRaidMembers() or 0) > 0 then
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            if not UnitIsUnit(unit, "player") then table.insert(out, unit) end
        end
        return out
    end

    if type(GetNumPartyMembers) == "function" then
        for i = 1, (GetNumPartyMembers() or 0) do
            table.insert(out, "party" .. i)
        end
    end

    return out
end

--[==[ **Both readings of the scale, drawn at once, so one look settles it.**

     Turning yards into pixels rests on a thing nothing in Lua can observe:
     whether making the minimap frame bigger shows the same ground larger
     (`width / diameter`) or more ground at the same size (`140 / diameter`).
     The two differ by the ratio of the frame to a stock minimap, which on a map
     dragged out to 200 is a marker landing 40 pixels out instead of 28.

     `/eq blipmatch` draws every group member twice: their class marker at the
     scale in use, and a grey dot at the other one. The client's own coloured dot
     is the truth -- whichever of the two sits on it is the right rule, and that
     is a question a screenshot answers and an argument does not.

     Deliberately a mode rather than a print. The last three attempts at this
     were settled from numbers in a chat window, and the numbers were consistent
     with both readings every time. ]==]
function M:MatchMarker(index)
    self.matchMarkers = self.matchMarkers or {}
    if self.matchMarkers[index] then return self.matchMarkers[index] end
    if not Minimap or not Minimap.CreateTexture then return nil end

    local icon = Minimap:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(OB.mediaPath .. "textures\\mapicons\\GREY")
    icon:Hide()

    self.matchMarkers[index] = icon
    return icon
end

--[[ The reading not in use, for the mode above to draw. ]]--
function M:MinimapScaleOther()
    local live = self:MinimapScale()
    if not live then return nil end

    local width = Minimap.GetWidth and Minimap:GetWidth() or STOCK_MINIMAP
    if not width or width <= 0 then return nil end

    --[[ `live` is width/diameter; the other reading is 140/diameter, which is
         the same number scaled by how far the frame is from stock. ]]--
    return live * (STOCK_MINIMAP / width)
end

function M:ToggleBlipMatch()
    self.blipMatch = not self.blipMatch and true or nil

    if not self.blipMatch then
        local pool = self.matchMarkers or {}
        for i = 1, table.getn(pool) do pool[i]:Hide() end

        OB.Print("marker match off.", "Map")
        return false
    end

    local said = "marker match on: your class markers are drawn at the scale "
            .. "in use, and a grey dot at the other one. Whichever sits on the "
            .. "client's own dot is the right rule -- say which."

    OB.Print(said, "Map")

    return true
end

function M:MinimapMarker(index)
    self.minimapMarkers = self.minimapMarkers or {}
    if self.minimapMarkers[index] then return self.minimapMarkers[index] end
    if not Minimap or not Minimap.CreateTexture then return nil end

    --[[ On the minimap itself and above its own blips, which are drawn by the
         engine into the frame rather than into a child of it. ]]--
    local icon = Minimap:CreateTexture(nil, "OVERLAY")
    icon:Hide()

    self.minimapMarkers[index] = icon
    return icon
end

--[==[ **Placed from a real position rather than from the client's dot.**

     Rotated by the player's facing when the minimap rotates, which is a setting
     and not a constant. The facing comes from the minimap's own rotating model
     -- the one thing on this client that knows it -- through the waypoints
     module, which already finds and caches that frame.

     Anything past the edge is hidden rather than pinned to the rim. A marker
     clamped to the edge says "somebody is roughly that way", which is what the
     edge of a minimap already says about everything beyond it, and four of them
     stacked on the same point of the rim say less than nothing. ]==]
--[==[ **The client's blips, on or off.**

     Idempotent and cheap to ask for: the refresh below calls this every frame,
     and `SetBlipTexture` is a texture swap rather than a no-op when the sheet
     is already right. So the wanted state is remembered and the call is only
     made when it changes.

     Guarded on the method existing. `SetMaskTexture` from the same widget
     family is already used here and works on this client, so this is expected
     to be present -- but "expected" is not "checked", and the failure if it is
     absent should be that the dots stay rather than that the minimap raises
     every frame. ]==]
--[==[ **The probe, on and off.**

     Deliberately not routed through `StyleMinimapBlips`: that function owns one
     question -- are the group's dots hidden -- and answering a second one
     through it is how a flag ends up meaning two things. This writes the sheet
     directly and hands the client's own back afterwards, then tells the pass
     that nothing of its doing is hidden any more. ]==]
function M:ToggleBlipProbe()
    local map = getglobal("Minimap")
    if not map or type(map.SetBlipTexture) ~= "function" then return false end

    self.blipProbe = not self.blipProbe and true or nil

    if not self.blipProbe then
        map:SetBlipTexture(CLIENT_BLIP)
        self.blipsHidden = false

        OB.Print("blip probe off; the client has its own sheet back.", "Map")
        return false
    end

    map:SetBlipTexture(PROBE_BLIP)
    self.blipsHidden = false

    OB.Print("blip probe on. Every kind of minimap dot is now a flat colour:",
            "Map")

    OB.Raw("  white, magenta, cyan, orange on the top row")
    OB.Raw("  purple, pink, brown, black on the second")
    OB.Raw("  say which colour your party members are, and which colour a")
    OB.Raw("  tracked herb or vein is -- that names the cells, and the sheet")
    OB.Raw("  that ships can then blank one and keep the other.")

    return true
end

function M:StyleMinimapBlips(hide)
    local map = getglobal("Minimap")
    if not map or type(map.SetBlipTexture) ~= "function" then return false end

    hide = hide and true or false

    --[==[ **Nothing is hidden until this hides it.**

         `blipsHidden` started as nil, so the first pass -- which is a pass with
         nothing to hide, on a client where this feature ships off -- compared
         nil against false, decided that was a change, and set the sheet to the
         client's own path.

         That is not a no-op. It loads whatever that path resolves to at that
         moment, which on a client carrying a loose override in
         `Interface\\Minimap` is not the sheet the engine already had. An addon
         that has changed nothing should write nothing. ]==]
    if self.blipsHidden == nil then self.blipsHidden = false end

    if self.blipsHidden == hide then return true end

    map:SetBlipTexture(hide and GROUPLESS_BLIP or CLIENT_BLIP)
    self.blipsHidden = hide
    return true
end

--[==[ **Which frames on the minimap belong to somebody else's map addon.**

     Anonymous `Button` children of `Minimap`, and that is the whole test.

     It sounds loose and is the opposite. Every launcher this addon knows how to
     collect has a name -- that is how `IsMinimapLauncher` finds them and how
     `minimapHomes` remembers where they came from -- so "no name" excludes all
     of them by construction. Our own markers are textures rather than frames
     and `GetChildren` does not return them at all. What is left is the pooled,
     unnamed pins that map addons create by the hundred: Questie-Octo's are
     `CreateFrame("Button", nil, Minimap)`, and pfQuest's are the same shape.

     Naming the addons instead would be worse. A list of names is a list that is
     wrong the day somebody installs the one that is not on it. ]==]
function M:ForeignMinimapPins()
    local map = getglobal("Minimap")
    if not map or not map.GetChildren then return {} end

    local out = {}
    local children = { map:GetChildren() }

    for i = 1, table.getn(children) do
        local child = children[i]
        local kind = child and child.GetObjectType and child:GetObjectType()

        if kind == "Button" and child.GetName and not child:GetName()
                and child.IsShown and child:IsShown()
                and child.GetCenter and child.SetAlpha then
            table.insert(out, child)
        end
    end

    return out
end

--[==[ **Faded, not hidden -- and the difference is the reason this is safe.**

     The owning addon shows and hides its own pins constantly as you move, and
     anything here that also called `Show` or `Hide` would be two pieces of code
     writing one property, which resolves as flicker at whatever rate the slower
     one runs. Reparenting is worse again: it is what `CollectMinimapButtons`
     does to launchers, and the comment there already says that doing it to a
     live objective pin steals it.

     Frame alpha is a property nothing else is writing. Questie-Octo's
     `Visuals:SetAlpha` sets the *texture's* vertex colour, and the two are
     independent -- it can repaint a pin as often as it likes without
     disturbing this, and this can fade one without disturbing that. Read out of
     `Map/Visuals.lua:196` rather than assumed.

     **A faded pin does not take the mouse, which is a correction.**

     It used to, on the reasoning that the information was never the problem --
     the forty copies of it were -- so hovering the patch could still name what
     was under it. That reads well and is wrong in the hand: an invisible frame
     that answers the mouse means a tooltip for something not on screen, and on
     a stack it means the tooltip of whichever invisible one happens to be on
     top rather than of the one you are pointing at.

     So the mouse goes with the picture. The pin that stayed visible is the pin
     that answers, which is the whole point of leaving one. ]==]
function M:ThinMinimapPins()
    local cfg = self:Config()
    self.thinnedPins = self.thinnedPins or {}

    if not OB.ModuleEnabled("map") or not cfg.thinPins then
        return self:RestoreMinimapPins()
    end

    local spacing = tonumber(cfg.pinSpacing) or 12
    if spacing < 1 then spacing = 1 end

    local pins = self:ForeignMinimapPins()
    local taken, dim = {}, {}

    for i = 1, table.getn(pins) do
        local pin = pins[i]
        local x, y = pin:GetCenter()

        if x and y then
            --[[ One cell of a grid the size of a pin. Whoever lands in a cell
                 first keeps it; the rest of that cell fades. Which one wins
                 does not matter -- they are all saying the same thing -- but it
                 has to be stable between passes or the survivor would flicker
                 between them, so the order `GetChildren` gives is used as it
                 comes rather than sorted by anything that moves. ]]--
            local key = math.floor(x / spacing) .. ":" .. math.floor(y / spacing)

            if taken[key] then
                dim[pin] = true
            else
                taken[key] = true
            end
        end
    end

    --[[ Anything that was faded and is no longer crowded comes back before
         anything new is faded, so a pin never spends a pass invisible because
         its neighbour moved away. ]]--
    for pin in pairs(self.thinnedPins) do
        if not dim[pin] then
            if pin.SetAlpha then pin:SetAlpha(1) end
            if pin.EnableMouse then pin:EnableMouse(true) end
            self.thinnedPins[pin] = nil
        end
    end

    local faded = 0
    for pin in pairs(dim) do
        if not self.thinnedPins[pin] then
            pin:SetAlpha(0)

            --[[ Guarded: `EnableMouse` is not on every frame type, and a pin
                 that cannot answer the mouse anyway does not need telling. ]]--
            if pin.EnableMouse then pin:EnableMouse(false) end

            self.thinnedPins[pin] = true
        end
        faded = faded + 1
    end

    return faded
end

--[[ Everything this ever faded, put back. Called when the setting goes off and
     when the module does, because a pin left at zero alpha by an addon that has
     stopped running is a pin nobody can explain. ]]--
function M:RestoreMinimapPins()
    if not self.thinnedPins then return 0 end

    local restored = 0
    for pin in pairs(self.thinnedPins) do
        if pin and pin.SetAlpha then pin:SetAlpha(1) end
        if pin and pin.EnableMouse then pin:EnableMouse(true) end
        self.thinnedPins[pin] = nil
        restored = restored + 1
    end

    return restored
end

function M:RefreshMinimapMarkers()
    local cfg = self:Config()
    local on = OB.ModuleEnabled("map") and cfg.replacePlayerIcons

    local units = on and self:MinimapGroupUnits() or {}
    local scale = on and self:MinimapScale() or nil

--[==[ **The same size as the world map's markers.**

         They had a slider of their own, on the reasoning that a minimap is a
         hundred and forty pixels across and the world map is a window. That was
         true while the number sized a mostly empty file; now that it sizes the
         mark, the honest answer is that a marker is a marker and thirteen
         pixels is what the client's own is.

         One number rather than two also means they cannot disagree, which they
         had: the minimap's was migrated to twenty and the world map's to
         thirteen, so the same party member was two different sizes depending on
         which map you looked at. ]==]
    local size = tonumber(cfg.playerIconSize) or 13
    if size < 8 then size = 8 end
    if size > 48 then size = 48 end

    local radius = Minimap and Minimap.GetWidth and ((Minimap:GetWidth() or 0) / 2) or 0

    --[==[ **Through `OB.CVar`, because this name does not exist everywhere.**

         `rotateMinimap` is absent on this client and `GetCVar` raises rather
         than answering nil, ten times a second from the tick below. Absent
         means not rotating, which is also what the setting being off means --
         so nil and "0" land in the same place. ]==]
    local rotate = OB.CVar("rotateMinimap") == "1"

    local facing
    if rotate then
        local waypoints = OB.modules and OB.modules.waypoints
        if waypoints and waypoints.Facing then facing = waypoints:Facing() end
    end

    local drawn = 0

    --[==[ **How many of the group we could not place.**

         `UnitPosition` answers for friendly units on a SuperWoW client and
         answers nothing on any other -- and nothing for a member who is not
         somewhere it can see, which does happen. It is the number that decides
         whether the client's own dots may be put away: they can only go while
         every single person is accounted for by one of ours. ]==]
    local missing = 0

    --[[ Read once for the whole pass rather than once per marker. ]]--
    local px, py

    if type(UnitPosition) == "function" then
        local ok
        ok, px, py = pcall(UnitPosition, "player")
        if not ok or type(px) ~= "number" then px, py = nil, nil end
    end

    if scale then
        for i = 1, table.getn(units) do
            local unit = units[i]
            local east, north = self:UnitOffsetYards(unit, px, py)

            if not east then missing = missing + 1 end

            if east and UnitExists(unit) then
                local x, y = east * scale, north * scale

                --[==[ The minimap turns under a fixed arrow, so everything on it
                     turns with the world rather than with the frame. ]==]
                if facing then
                    local s, c = math.sin(facing), math.cos(facing)
                    x, y = (x * c) - (y * s), (x * s) + (y * c)
                end

                if math.sqrt((x * x) + (y * y)) + (size / 2) <= radius then
                    drawn = drawn + 1
                    local icon = self:MinimapMarker(drawn)

                    if icon then
                        --[==[ **Only touched when something about it changed.**

                             This runs every frame now, and a raid standing
                             still is forty markers being told the position they
                             are already at. Comparing first is a handful of
                             floats against a texture swap and two anchor
                             writes.

                             Half a pixel, because a marker cannot move less
                             than that visibly and floating point will not
                             produce the same number twice from a player who is
                             breathing. ]==]
                        local texture = OB.PlayerMapIcon(OB.UnitClassToken(unit))

                        if icon.eqTexture ~= texture or icon.eqSize ~= size then
                            icon:SetWidth(size)
                            icon:SetHeight(size)
                            icon:SetTexture(texture)
                            OB.SetPlayerIconCoords(icon, true)
                            if icon.SetVertexColor then
                                icon:SetVertexColor(1, 1, 1, 1)
                            end
                            icon.eqTexture, icon.eqSize = texture, size
                        end

                        if icon.eqX == nil
                                or math.abs(icon.eqX - x) >= 0.5
                                or math.abs(icon.eqY - y) >= 0.5 then
                            icon:ClearAllPoints()
                            icon:SetPoint("CENTER", Minimap, "CENTER", x, y)
                            icon.eqX, icon.eqY = x, y
                        end

                        icon:Show()
                    end

                    --[[ The same member at the other reading of the scale,
                         while the match mode is on. ]]--
                    if self.blipMatch then
                        local other = self:MinimapScaleOther()
                        local mark = other and self:MatchMarker(drawn)

                        if mark then
                            local mx, my = east * other, north * other

                            if facing then
                                local s, c = math.sin(facing), math.cos(facing)
                                mx, my = (mx * c) - (my * s), (mx * s) + (my * c)
                            end

                            mark:SetWidth(size)
                            mark:SetHeight(size)
                            OB.SetPlayerIconCoords(mark, true)
                            mark:ClearAllPoints()
                            mark:SetPoint("CENTER", Minimap, "CENTER", mx, my)
                            mark:Show()
                        end
                    end
                end
            end
        end
    end

    --[[ The pool is never shrunk, only hidden past the last one drawn: a raid
         that goes from forty to five and back should not rebuild textures. ]]--
    local pool = self.minimapMarkers or {}
    for i = drawn + 1, table.getn(pool) do pool[i]:Hide() end

    local matches = self.matchMarkers or {}
    for i = (self.blipMatch and drawn or 0) + 1, table.getn(matches) do
        matches[i]:Hide()
    end

    --[==[ **And the client's dots go away only while nobody would be lost.**

         Off when the feature is off, obviously. Off as well whenever a single
         group member has no position we can read -- on a client without
         SuperWoW that is all of them, and even with it a member somewhere the
         call cannot see answers nothing.

         Hiding the blips in that state would take a person off the minimap
         altogether, which is a worse failure than the one this is fixing: a
         marker that is a frame late is still a marker, and a missing party
         member is a wrong answer that looks like a right one.

         Note what is deliberately not a condition: whether the member is inside
         the minimap's reach. Somebody two hundred yards away is not drawn by
         us, and the client does not draw them either -- so there is nobody to
         lose. `missing` counts only the ones we could not *ask* about. ]==]
    local hide = on and missing == 0
            and table.getn(units) > 0

    self:StyleMinimapBlips(hide)

    return drawn
end

function M:Apply()
    self:ApplyMap()
    self:StylePlayerMapIcons()
    self:StylePlayerArrow()
    self:RefreshMapCoordinates(true)
    self:ApplyZone()
    self:ApplyMinimapHeader()
    self:ApplyAtlasIcons()
    self:StyleMinimapShape()
    self:StyleMinimapSize()
    self:StyleMinimapBox()
    self:StyleMinimapFurniturePositions()
    self:StyleWorldMapWheel()
    self:StyleMinimapWheel()
    self:StyleMinimapParts()
    self:CollectMinimapButtons()
    self:PlaceMinimap()
end

function M:OnEvent()
    --[[ Indoors is measured, and the measurement is kept against the zoom it
         was taken at. A zone change is the one thing that can make it wrong
         without the zoom moving -- two zones whose inside and outside zooms
         happen to match -- so it is dropped here and taken again on demand. ]]--
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        self.indoorsKey = nil
        self.indoorsIs = nil
    end

    --[[ A group change is not a reason to re-place the minimap, re-collect its
         buttons and rebuild the furniture. Only the markers can have gone stale,
         so only the markers are repainted. ]]--
    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        self:StylePlayerMapIcons()
        return
    end

    --[[ The markers again, after the client has finished with them. Only while
         the map is open: this fires on a timer whenever it is, and repainting
         forty-four markers nobody is looking at is work for nothing -- opening
         the map fires it again, which is when it matters. ]]--
    if event == "WORLD_MAP_UPDATE" then
        local frame = getglobal("WorldMapFrame")
        if frame and frame.IsShown and not frame:IsShown() then return end

        self:StylePlayerMapIcons()

        --[[ And back on top of whatever the client -- or a quest addon
             answering the same event -- has just drawn over it. ]]--
        self:RaisePlayerArrow()
        return
    end

    self:Apply()
end

--[[ Only the clock ticks, and only to notice the minute rolling over. Checked
     four times a second: often enough that the change is not visibly late,
     rare enough to cost nothing. ]]--
function M:OnUpdate(now)
    if self.mapDragState then self:StepMapDrag() end
    if self.mapResizeState then self:StepMapResize() end

    --[==[ **Every frame, because the thing beside it is drawn every frame.**

         This was ten times a second on the reasoning that a party member
         walking is not a per-frame question. That is true of the party member
         and false of the *minimap*, which is centred on you: every marker on it
         has to move whenever **you** do, and you move every frame. At ten hertz
         a running player drags the whole group behind them in visible steps.

         Reported as our markers running at a lower framerate. They were.

         Two things pay for the six-fold increase, and between them this pass is
         cheaper per marker than the one it replaces: the player's position is
         read once rather than once per member, and a marker that has not moved
         half a pixel is not written to. A raid standing still costs one
         `UnitPosition` per member and nothing else. ]==]
    self:RefreshMinimapMarkers()

    --[==[ **Four times a second, unlike the markers above.**

         Those move because *you* move, so they are a per-frame question. This
         one is about pins moving relative to each other, which happens at
         walking pace, and it walks a list of every frame on the minimap to ask
         it. Sixty times a second that is real work for an answer that changes a
         few times a second at most. ]==]
    if not self.nextThin or now >= self.nextThin then
        self.nextThin = now + 0.25
        self:ThinMinimapPins()

        --[[ The header and the coordinates on the same beat: a clock turns over
             once a minute and a coordinate changes at walking pace, so four
             times a second is already more often than either needs. ]]--
        self:RefreshMinimapHeader()

        --[[ And the map's own button, which has to say whether the map is up.
             A comparison four times a second; a texture write only when the
             answer has changed. ]]--
        self:RefreshHeaderGlyphs()
    end

    --[==[ **A launcher that has left the drawer is put back in it.**

         Most minimap buttons let you drag them with control held, and several
         of them finish that drag by reparenting themselves -- Turtle's
         battlefield frame ends its `OnDragStop` with `SetParent("UIParent")`,
         and it is far from alone. The button then sits wherever it was dropped
         and never returns, because the sweep that gathers them only looks at
         things on the minimap and it is no longer one of those.

         So the drawer reclaims what it is already holding, by name, rather than
         by sweeping again. Half a second: this is a correction for something a
         hand did, not a hot path.

         **While the drawer is on, the drawer owns the position.** Dragging one
         out and having it snap back is the honest behaviour of a grid -- the
         alternative is a button that silently stops being gathered, which is
         the thing that was reported. ]==]
    if not self.nextMinimapReclaim or now >= self.nextMinimapReclaim then
        self.nextMinimapReclaim = now + 0.50

        --[[ New arrivals first: a button that has just been made is not one
             that has wandered off, and gathering it also gives the reclaim
             something to hold on to. ]]--
        self:CollectLateArrivals()
        self:ReclaimMinimapButtons()
    end

    -- WorldMapFrame can be opened by other addons with ShowUIPanel rather than
    -- ToggleWorldMap. Keep the resize grip in sync with the frame itself so it
    -- is available regardless of which path opened the map. This also fixes the
    -- case where ApplyMap created the grip while the map was still hidden.
    if not self.nextMapResizeGripCheck or now >= self.nextMapResizeGripCheck then
        self.nextMapResizeGripCheck = now + 0.10
        local world = getglobal("WorldMapFrame")
        local cfg = self:Config()
        local shouldShow = world and world.IsShown and world:IsShown()
                and OB.ModuleEnabled("map") and cfg and cfg.scaleMap
        local grip = self.mapResizeGrip or self:MapResizeGrip()
        local handles = self.mapDragHandles or self:MapDragHandles()
        self.mapDragEnabled = shouldShow and true or false
        if grip then
            if shouldShow then
                if not grip:IsShown() then grip:Show() end
            elseif grip:IsShown() then
                grip:Hide()
            end
        end
        if handles then
            for i = 1, table.getn(handles) do
                if shouldShow then
                    if not handles[i]:IsShown() then handles[i]:Show() end
                elseif handles[i]:IsShown() then
                    handles[i]:Hide()
                end
            end
        end

        -- ShowUIPanel can be called directly by other addons and by alternate
        -- map-mode buttons, bypassing our ToggleWorldMap wrapper. On each real
        -- hidden->shown transition reassert ECO's scale and saved/clamped
        -- position after Blizzard has finished its own map initialisation.
        if shouldShow and not self.worldMapWasShown then
            local scale = self:ClampWorldMapScale(cfg.mapScale)
            cfg.mapScale = scale
            if world.SetScale then world:SetScale(scale) end
            if world.SetAlpha then world:SetAlpha(tonumber(cfg.mapAlpha) or 1) end
            self.mapDragEnabled = true
            self:PlaceWorldMap()
        elseif not shouldShow then
            if self.mapResizeState then self.mapResizeState = nil end
            if self.mapDragState then self.mapDragState = nil end
            self:ResumeWorldMapButtonUpdate()
        end
        self.worldMapWasShown = shouldShow and true or false
    end

    if not self.nextMapCoordinateCheck or now >= self.nextMapCoordinateCheck then
        self.nextMapCoordinateCheck = now + 0.10
        if not self.mapDragState and not self.mapResizeState then
            self:RefreshMapCoordinates(false)
        end
    end

    -- Some old minimap launchers continuously re-apply their saved edge anchor
    -- in OnUpdate.  While the drawer is open that can pull an icon back out of
    -- its grid cell.  Reassert the drawer layout at a deliberately slow rate;
    -- when it is closed nothing is scanned or moved.
    if self.minimapTray and self.minimapTray.IsShown and self.minimapTray:IsShown()
            and (not self.nextMinimapTrayLayout or now >= self.nextMinimapTrayLayout) then
        self.nextMinimapTrayLayout = now + 0.50
        self:CollectMinimapButtons()
    end
end

function M:OnBind()
    self.lastClockText = nil
    self:Apply()
end

function M:OnUnbind()
    --[[ Before anything else: a pin left faded by an addon that has stopped
         running is a pin nobody can explain, and the owning addon has no reason
         to look at its own frame alpha again. ]]--
    self:RestoreMinimapPins()

    -- Return the world map to the exact panel/toggle/geometry state captured
    -- before ECO made it a window, not merely to scale 1.
    self:RestoreWorldMapWindow()

    local frame = getglobal("WorldMapFrame")
    if frame and frame.SetScale then
        frame:SetScale(1)
        if frame.SetAlpha then frame:SetAlpha(1) end
    end
    self:SetMapMovable(false)
    self:SetMapResizable(false)
    self:RefreshMapCoordinates(true)

    self:ReleaseMinimapButtons()
    if self.minimapToggle then self.minimapToggle:Hide() end

    --[[ The engine's own blips come back. Nothing else puts them back once the
         tick that decides has stopped running, and a minimap left with no dots
         on it by an addon that is no longer loaded is the worst kind of
         leftover: there is nothing on screen to connect it to. ]]--
    self:StyleMinimapBlips(false)

    self:RestoreMinimapShape()
    self:RestoreMinimapFurniture()
    self:StyleMinimapParts()

    if self.clockFrame then self.clockFrame:Hide() end
end

function M:OnStyle()
    self:Apply()
end

function M:OnDraw() end
