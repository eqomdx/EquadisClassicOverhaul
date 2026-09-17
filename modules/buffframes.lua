--[[ Equadis' Classic Overhaul :: Buff Frames v2

  The first experiment built a second aura system.  This one deliberately does
  not.  Blizzard's own BuffButton objects remain responsible for aura indexing,
  tooltips, right-click cancellation, flashing, duration strings and stacks.
  ECO only changes their anchors and scale, which is the same low-risk principle
  DragonflightUI-Reforged uses when it moves the stock aura groups.

  The useful layout controls come from the VCB idea -- per-row limits, maximums,
  spacing and growth direction -- without VCB's replacement-button machinery.
]]--

local OB = EquadisClassicOverhaul
local floor = math.floor
local ceil = math.ceil
local function Say(msg) OB.Print(msg, "Buff Frames") end

local M = OB.RegisterModule({
    id = "buffframes",
    name = "Buff Frames",
    feature = true,
    renders = "none",
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

    --[==[ A clock is the one thing here that no event announces. Auras arrive
         on `PLAYER_AURAS_CHANGED` and the layout answers that; the seconds
         counting down between two of them answer to nothing but the frame.
         `OnUpdate` writes only when the string it would write has changed, so
         being tickly costs a comparison per icon rather than a redraw. ]==]
    tickly = true,

    defaults = {
        --[[ On. A poison is spent per hit rather than on a clock, so "how
             many" is the question its icon never answers. ]]--
        showEnchantCharges = true,

        --[==[ **On, because the client's own duration text is not this.**

             1.12 does draw a duration under a buff, but only once the buff is
             close to expiring and only in its own place -- which is the corner
             this module has just moved somewhere else. Drawing our own puts the
             number on the icon wherever the icon ends up, and puts it there for
             the whole life of the buff rather than the last few seconds of
             it. ]==]
        showAuraTimers = true,

        --[==[ **The size of the number on an icon, which this addon never set.**

             The timer was built from the client's `NumberFontNormalSmall` and
             left there, so it drew at whatever that template says -- about
             twelve point. `4m59s` at twelve is wider than a thirty pixel icon,
             which is the reported overrun: it is not that the text is too big
             for the text, it is that nothing had ever measured it against the
             thing it sits under.

             Ten is what fits the default icon with the widest string it can
             hold. A setting rather than a constant because the icon size is
             itself a setting -- somebody at forty-eight has room for more and
             somebody at eighteen has room for less, and a fixed number cannot be
             right for both. ]==]
        timerFontSize = 10,

        --[==[ **How long is left before the seconds are worth showing.**

             Above this the seconds are noise -- nobody acts on the difference
             between 19m03s and 19m -- and below it they are the whole point: a
             poison at 4m59s is a different decision from one at 4m01s. Five was
             the constant and is a reasonable answer rather than the only one,
             which is what makes it a number rather than a rule. ]==]
        secondsUnder = 5,

        --[==[ **An outline of its own, because this number is over a picture.**

             The timer follows the profile's outline like every other string in
             the addon, and that is right for text on a backdrop and wrong here:
             it sits directly under -- and on a small icon, partly over -- spell
             art, which is whatever colour the artist chose. Unoutlined text
             there does not read as plainer, it disappears into the one part of
             the icon that happens to match it.

             The nameplates force an outline on their own text for exactly this
             and offer no way out; the action bars made it a choice. A choice
             here too, defaulting to the thin one, because a thick outline on an
             eight point number is more outline than number. ]==]
        timerOutline = 2,
        chargeFontSize = 11,

        --[==[ **How the number is written**, asked for as `x:xx` against
             `xmxxs`.

             A real preference rather than a default nobody would change: the
             clock is two characters shorter and reads as a stopwatch, the
             letters say their own units and cannot be mistaken for anything
             else. Neither is wrong, which is what makes it a setting. ]==]
        timerFormat = "letters",

        --[==[ **The timer coloured by how long is left.**

             Reading "4m12s" takes a moment, and a buff about to drop mid-pull
             has to be noticeable without being read. Five bands at the numbers
             people already think in -- half an hour, five minutes, two minutes,
             thirty seconds -- from comfortable to now.

             On, because a number that is only a number is what this replaces,
             and every band is a colour on the panel because what reads as
             "fine" differs between a dark interface and a bright one. ]==]
        timerColors = true,

        timerOver30mColor  = { 0.30, 0.85, 0.35, 1 },
        timerOver5mColor   = { 1.00, 1.00, 1.00, 1 },
        timerUnder5mColor  = { 1.00, 0.92, 0.30, 1 },
        timerUnder2mColor  = { 1.00, 0.60, 0.15, 1 },
        timerUnder30sColor = { 1.00, 0.25, 0.20, 1 },

        --[==[ **The flash a buff does when it is nearly gone**, which is the
             client's and was never anybody's choice.

             1.12 fades every aura icon in and out once it drops under half a
             minute. It is a good idea badly aimed: it fires on all of them at
             once, so a city buff running out and a poison about to leave you
             unarmed pulse in exactly the same way, and a full bar of
             twenty-minute blessings all landing together turns the whole row
             into a strobe.

             On, because it is what the client does and what somebody expects to
             see. Off is for people who now have a **number** under every icon
             -- this module draws one -- and do not need the icon shouting as
             well. ]==]
        flashLowAuras = true,

        --[==[ **How fast**, as a multiple of the client's own rate rather than a
             number of seconds, because one is the answer that means "leave it
             alone" and it is worth being able to see that on the panel.

             Two is twice as fast, a half is half. The client flashes on a
             three-quarter-second half cycle, which is deliberate and slow -- it
             is meant to be noticed at the edge of vision rather than read -- and
             the reason to change it is that a slow pulse is easy to miss in a
             fight and a fast one is unbearable out of it. ]==]
        flashSpeed = 1,

        --[==[ **A weapon buff is not a buff that happens to be on a weapon.**

             It is spent per swing rather than on a clock, it has charges instead
             of a duration, there are exactly two of them, and the client draws
             them in a row of their own. Everything about them is different
             except that they are square and they glow.

             They were borrowing the buff row's size, spacing and growth, which
             meant making buffs small made poisons small too, and there was no
             way to say otherwise. Their own group, with their own numbers. ]==]
        --[==[ **Which hand a weapon buff is on, in colour.**

             Two icons side by side, both wearing the client's own reddish
             overlay, and nothing on either says which weapon it belongs to. The
             only way to tell was to count charges and remember which poison went
             where -- and at a glance, with two of the same poison on, there was
             no way at all.

             `TempEnchant1` is the main hand and `TempEnchant2` the off hand,
             which is fixed: `GetWeaponEnchantInfo` answers in that order and the
             client builds the buttons in that order. So the colour can simply be
             the slot, with no guessing about which is which.

             Gold and blue because those are as far apart as this palette gets
             while both staying legible on a dark icon -- and neither is the red
             the client already uses for a debuff, which would read as a warning
             rather than as a label. ]==]
        mainHandColor = { 1.00, 0.82, 0.00, 1 },
        offHandColor = { 0.30, 0.65, 1.00, 1 },

        enchantSize = 30,
        enchantSpacingX = 5,
        enchantGrowX = "left",

        buffSize = 30,
        buffPerRow = 8,
        buffMax = 16,
        buffSpacingX = 5,
        buffSpacingY = 12,
        buffGrowX = "left",
        buffGrowY = "down",

        debuffSize = 30,
        debuffPerRow = 8,
        debuffMax = 8,
        debuffSpacingX = 5,
        debuffSpacingY = 12,
        debuffGrowX = "left",
        debuffGrowY = "down",

        positions = {},
    },

    options = {
        --[==[ **Read in the order somebody arranges these in.**

             Timers first because they are the thing every row below is about --
             a size and a spacing are decisions you make once, and whether the
             numbers are on is the one you come back for. Then the three rows in
             the order they sit on screen.

             **The Position section is gone.** It held two actions -- unlock, and
             put them back -- and unlocking is what edit mode is: one gesture for
             every frame in the addon rather than a button per module. `Put Them
             Back` moved to `/eq buffs reset`, which is where the action bars and
             the unit frames already keep theirs. ]==]
        --[==[ **General**, because it stopped being only about timers.

             It holds whether the numbers are drawn, how big they are, how they
             are written, where the seconds stop and what outlines them -- and
             the three sections under it are each about one row of icons. This is
             the page's answer to "how does this module behave", which is what a
             General section is.

             The anchor keeps its old name: it is what the page's navigation
             stores, and renaming it would send anybody's saved position to a
             section that no longer exists. ]==]
        { "General", "__s_timers", "section", "timers" },
        { "Show Time Left On Auras", "showAuraTimers", "boolean" },
        { "Timer Text Size", "timerFontSize", "slider", 6, 20, 1,
          nil, nil, "!showAuraTimers" },

        { "Timer Format", "timerFormat",
          OB.Enum({ "letters", "clock" }, { "4m59s", "4:59" }), 150,
          nil, nil, nil, "showAuraTimers" },

        --[==[ **Where the seconds stop being worth showing.**

             Above it they are noise -- nobody acts on the difference between
             19m03s and 19m -- and below it they are the whole point: a poison at
             4m59s is a different decision from one at 4m01s. Five was the
             constant this shipped with and is a reasonable answer rather than
             the only one. ]==]
        { "Show Seconds Under (Minutes)", "secondsUnder", "slider", 1, 10, 1,
          nil, "showAuraTimers" },
        { "Timer Text Outline", "timerOutline", OB.fontOutlines, 150,
          nil, nil, nil, "showAuraTimers" },

        --[[ Greyed rather than hidden when the timers are off: the colours are
             still the answer to a question somebody is about to ask, and a row
             that vanishes reads as a setting this addon does not have. ]]--
        { "Color Timers By Time Left", "timerColors", "boolean",
          nil, nil, nil, nil, nil, "!showAuraTimers" },

        { "Over 30 Minutes", "timerOver30mColor", "color", true,
          nil, nil, nil, nil, "!showAuraTimers,!timerColors" },
        { "Over 5 Minutes", "timerOver5mColor", "color", true,
          nil, nil, nil, nil, "!showAuraTimers,!timerColors" },
        { "Under 5 Minutes", "timerUnder5mColor", "color", true,
          nil, nil, nil, nil, "!showAuraTimers,!timerColors" },
        { "Under 2 Minutes", "timerUnder2mColor", "color", true,
          nil, nil, nil, nil, "!showAuraTimers,!timerColors" },
        { "Under 30 Seconds", "timerUnder30sColor", "color", true,
          nil, nil, nil, nil, "!showAuraTimers,!timerColors" },

        --[==[ Last in the section because it is about the icon rather than the
             number, and everything above it is about the number.

             Greyed rather than removed when the flash is off, for the same
             reason the colours are: "how fast" is the next question somebody
             asks after finding the switch, and a row that disappears reads as a
             setting this addon does not have. ]==]
        { "Flash Auras About To Expire", "flashLowAuras", "boolean" },
        { "Flash Speed", "flashSpeed", "slider", 0.5, 3, 0.1,
          nil, nil, "!flashLowAuras" },

        { "Buffs", "__s_buffs", "section", "buffs" },
        { "Icon Size", "buffSize", "slider", 18, 48, 1 },
        { "Buffs Per Row", "buffPerRow", "slider", 1, 16, 1 },
        { "Maximum Buffs", "buffMax", "slider", 1, 40, 1 },
        { "Horizontal Spacing", "buffSpacingX", "slider", 0, 20, 1 },
        { "Vertical Spacing", "buffSpacingY", "slider", 0, 24, 1 },
        { "Grow Horizontally", "buffGrowX",
          OB.Enum({ "left", "right" }, { "Left", "Right" }) },
        { "Grow Vertically", "buffGrowY",
          OB.Enum({ "down", "up" }, { "Down", "Up" }) },

        { "Debuffs", "__s_debuffs", "section", "debuffs" },
        { "Icon Size", "debuffSize", "slider", 18, 48, 1 },
        { "Debuffs Per Row", "debuffPerRow", "slider", 1, 16, 1 },
        { "Maximum Debuffs", "debuffMax", "slider", 1, 24, 1 },
        { "Horizontal Spacing", "debuffSpacingX", "slider", 0, 20, 1 },
        { "Vertical Spacing", "debuffSpacingY", "slider", 0, 24, 1 },
        { "Grow Horizontally", "debuffGrowX",
          OB.Enum({ "left", "right" }, { "Left", "Right" }) },
        { "Grow Vertically", "debuffGrowY",
          OB.Enum({ "down", "up" }, { "Down", "Up" }) },

        { "Weapon Buffs", "__s_enchant", "section", "enchant" },

        { "Main Hand Border", "mainHandColor", "color", true },
        { "Off Hand Border", "offHandColor", "color", true },
        { "Icon Size", "enchantSize", "slider", 18, 48, 1 },
        { "Horizontal Spacing", "enchantSpacingX", "slider", 0, 20, 1 },
        { "Grow Horizontally", "enchantGrowX",
          OB.Enum({ "left", "right" }, { "Left", "Right" }) },

        --[==[ No rows, no maximum, no vertical growth. There are two weapon
             hands and there will not be a third, so a "per row" slider on a list
             that can hold two is a control whose every setting looks the
             same. ]==]
        { "Show Charges Left", "showEnchantCharges", "boolean" },
        { "Charge Text Size", "chargeFontSize", "slider", 6, 20, 1,
          nil, nil, "!showEnchantCharges" },
    },

    events = { "PLAYER_ENTERING_WORLD", "PLAYER_AURAS_CHANGED" },

    --[[ `BuffButton_Update` is the one client call this module cannot do
         without: it is what recomputes a stock aura button after the layout has
         hidden and then un-hidden it. `BuffButtons_UpdatePositions` is
         deliberately *not* listed -- a vanilla build has no such function and
         the module is designed to work without it, so requiring it would make
         every ordinary install report a failure for behaving as intended. ]]--
    requires = { "BuffButton_Update", "getglobal" },
})

local WHITE = "Interface\\Buttons\\WHITE8X8"

function M:Config()
    return OB.profile.modules.buffframes
end

local function makeHint(frame)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(WHITE)
    t:SetAllPoints(frame)
    t:SetVertexColor(0.10, 0.60, 1.00, 0.20)
    t:Hide()
    return t
end

local function capturePoints(frame)
    local points = {}
    if not frame or not frame.GetPoint then return points end

    local count = 1
    if frame.GetNumPoints then count = frame:GetNumPoints() or 1 end
    if count < 1 then count = 1 end

    for i = 1, count do
        local point, relative, relativePoint, x, y = frame:GetPoint(i)
        if point then
            table.insert(points, {
                point = point,
                relative = relative,
                relativePoint = relativePoint,
                x = x or 0,
                y = y or 0,
            })
        end
    end
    return points
end

local function restorePoints(frame, points)
    if not frame or not points or table.getn(points) == 0 then return end
    frame:ClearAllPoints()
    for i = 1, table.getn(points) do
        local p = points[i]
        frame:SetPoint(p.point, p.relative, p.relativePoint, p.x, p.y)
    end
end

function M:CreateAnchor(name, point, x, y)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetWidth(30)
    f:SetHeight(30)
    f:SetFrameStrata("LOW")
    f:SetPoint(point, UIParent, point, x, y)
    f:EnableMouse(false)
    f.hint = makeHint(f)
    return f
end

function M:EnsureAnchors()
    if self.buffAnchor then return end

    -- Stock 1.12 BuffFrame starts at -205,-13.  Keeping the first enable close
    -- to Blizzard makes this a layout feature rather than a surprise relocation.
    --[==[ **Three rows, top to bottom: weapon buffs, buffs, debuffs.**

         The weapon enchants used to be drawn at the top of the buff anchor and
         the buffs pushed down under them, so the buff row's position depended on
         whether you happened to be a shaman. Now each has its own anchor and
         each stays where it is put.

         The defaults reproduce what a rogue with a poison already saw: enchants
         where the buff row used to start, buffs a row below, debuffs below the
         two rows of buffs. Anybody who has dragged these keeps what they
         dragged -- only the untouched defaults move. ]==]
    self.enchantAnchor = self:CreateAnchor(
            "EquadisOverhaulEnchantAnchorV2", "TOPRIGHT", -205, -13)
    self.buffAnchor = self:CreateAnchor(
            "EquadisOverhaulBuffAnchorV2", "TOPRIGHT", -205, -60)
    self.debuffAnchor = self:CreateAnchor(
            "EquadisOverhaulDebuffAnchorV2", "TOPRIGHT", -205, -160)

    self.frames = { self.enchantAnchor, self.buffAnchor, self.debuffAnchor }
end

function M:Capture(button)
    if not button then return end
    self.original = self.original or {}
    if self.original[button] then return end

    self.original[button] = {
        points = capturePoints(button),
        scale = button.GetScale and button:GetScale() or 1,
        alpha = button.GetAlpha and button:GetAlpha() or 1,
    }
end

--[[ Which list a stock aura button belongs to.

     **`buffFilter` alone was not enough to answer this.** 1.12's
     `BuffButtonTemplate` sets `this.buffFilter = "HELPFUL|HARMFUL"` in its
     OnLoad -- VCB's copy of that template still carries the line -- and only
     some builds narrow it per button afterwards. A plain `string.find(filter,
     "HELPFUL")` therefore matched *every* button on a stock client, so all
     twenty-four went into the buff list, the debuff list stayed empty, and the
     debuff half of the module silently did nothing.

     So the filter is only trusted when it names one side and not the other.
     Otherwise the index answers, which is the split DragonflightUI-Reforged
     (rows at BuffButton0/8/16) and VCB (`for i = 0, 23`) both rely on. ]]--
local BUFF_COUNT = 16  -- BuffButton0..15 are buffs, 16.. are debuffs

local function auraKind(button, index)
    local filter = button.buffFilter
    if type(filter) == "string" then
        local helpful = string.find(filter, "HELPFUL")
        local harmful = string.find(filter, "HARMFUL")
        if helpful and not harmful then return "helpful" end
        if harmful and not helpful then return "harmful" end
    end

    if index < BUFF_COUNT then return "helpful" end
    return "harmful"
end

function M:Discover()
    self:EnsureAnchors()
    self.helpful = {}
    self.harmful = {}
    self.enchants = {}

    for i = 0, 63 do
        local button = getglobal("BuffButton" .. i)
        if button then
            self:Capture(button)

            local kind = auraKind(button, i)
            local list = self[kind]
            table.insert(list, button)

            --[==[ **Where this button sits in its own row, which is the only
                 thing that resolves an aura handle.**

                 `GetPlayerBuff(position, filter)` turns a row position into the
                 handle the rest of the aura calls want, and the position is
                 simply how far along the row a button is. Stamped here, where
                 the row is being built, rather than searched for later: the
                 list is in front of us and a linear scan per icon per tick is
                 the sort of thing that gets written once and never
                 removed. ]==]
            button.eqAuraPosition = table.getn(list) - 1
            button.eqAuraHarmful = (kind == "harmful")
        end
    end

    --[[ **A temporary weapon enchant is not a `BuffButton`**, and it is the half
         every addon that moves auras forgets.

         A sharpening stone, a rogue's poison, a shaman's weapon buff and an
         enchanter's oil all land in `TempEnchant1` and `TempEnchant2` -- main
         hand and off hand -- inside `TemporaryEnchantFrame`, which the client
         lays out as a row of its own. Walking `BuffButton0..63` finds none of
         them, so the buffs went where they were told and the poison stayed in
         the corner of the screen.

         Kept as a third list rather than folded into `helpful`, because they
         are laid out as their own row: an enchant is not a buff that happens to
         be on a weapon, it is a different row the client draws above the buffs.
         DragonflightUI anchors them separately for the same reason. ]]--
    for i = 1, 2 do
        local button = getglobal("TempEnchant" .. i)
        if button then
            self:Capture(button)
            table.insert(self.enchants, button)
        end
    end

    --[[ **Blizzard's buttons stay out of `frames`.**

         They were listed here so the feature's Show tick would hide them. It
         does -- and so does the draw loop, which calls `OB.HideFeature` on its
         own every time a hidden feature is asked to redraw. That reached past
         ECO and hid the client's real aura UI, with nothing to put it back
         until the next aura change.

         Show is handled by `Restore()` instead: unticking it hands the auras
         back to Blizzard's own layout, which is what "stop showing mine" should
         mean for a module that only ever moves somebody else's widgets. ]]--
    self.frames = { self.buffAnchor, self.debuffAnchor }
end

function M:ApplyAnchorPosition(frame, key, defaultPoint, x, y)
    local cfg = self:Config()
    local saved = cfg.positions and cfg.positions[key]

    frame:ClearAllPoints()
    if saved then
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    else
        frame:SetPoint(defaultPoint, UIParent, defaultPoint, x, y)
    end
end

function M:PlaceAnchors()
    self:EnsureAnchors()
    if self.dragging then return end

    self:ApplyAnchorPosition(self.enchantAnchor, "enchants", "TOPRIGHT", -205, -13)
    self:ApplyAnchorPosition(self.buffAnchor, "buffs", "TOPRIGHT", -205, -60)
    self:ApplyAnchorPosition(self.debuffAnchor, "debuffs", "TOPRIGHT", -205, -160)
end

function M:StorePosition(key, frame)
    if not frame or not frame.GetLeft or not frame:GetLeft() then return end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    cfg.positions[key] = {
        x = OB.Round((frame:GetLeft() + frame:GetWidth() / 2) - GetScreenWidth() / 2),
        y = OB.Round((frame:GetBottom() + frame:GetHeight() / 2) - GetScreenHeight() / 2),
    }
end

function M:DragMode()
    return self.dragging and true or false
end

function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("buffframes") then
        Say("switch Buff Frames on first.")
        return
    end

    self:EnsureAnchors()
    self.dragging = on and true or nil

    local pair = {
        { self.enchantAnchor, "enchants", "Weapon Buffs" },
        { self.buffAnchor, "buffs", "Buffs" },
        { self.debuffAnchor, "debuffs", "Debuffs" },
    }

    for i = 1, table.getn(pair) do
        local frame = pair[i][1]
        frame.ecoMoveKey = pair[i][2]
        frame:EnableMouse(self.dragging and true or false)
        frame:SetMovable(self.dragging and true or false)

        if self.dragging then
            frame:RegisterForDrag("LeftButton")
            frame.hint:Show()

            --[[ Named for edit mode's outline. Both of these are empty
                 rectangles until something is actually buffing you, which is
                 precisely when an unlabelled outline is least useful. ]]--
            OB.MarkMovable(frame, pair[i][3])
            frame:SetScript("OnDragStart", function() this:StartMoving() end)
            frame:SetScript("OnDragStop", function()
                this:StopMovingOrSizing()
                EquadisClassicOverhaul.modules.buffframes
                        :StorePosition(this.ecoMoveKey, this)
            end)
        else
            frame.hint:Hide()
            frame:SetScript("OnDragStart", nil)
            frame:SetScript("OnDragStop", nil)
        end
    end

    Say(self.dragging and "move mode on." or "move mode off.")
end

function M:ResetPositions()
    local cfg = self:Config()
    cfg.positions = {}
    self.dragging = nil
    self:PlaceAnchors()
    Say("buff and debuff positions reset.")
end

--[[ `startRow` shifts the whole block down by that many rows and is how the
     weapon enchants get a row of their own above the buffs rather than sitting
     on top of them. It also returns how many rows it used, so the caller can
     put the next block underneath without counting twice. ]]--
local function layoutList(list, anchor, size, perRow, maximum, spacingX,
        spacingY, growX, growY, startRow)
    if not list or table.getn(list) == 0 then return 0 end

    startRow = startRow or 0

    if perRow < 1 then perRow = 1 end
    if maximum < 1 then maximum = 1 end

    local xdir = growX == "right" and 1 or -1
    local ydir = growY == "up" and 1 or -1
    local origin

    if ydir > 0 then
        origin = xdir > 0 and "BOTTOMLEFT" or "BOTTOMRIGHT"
    else
        origin = xdir > 0 and "TOPLEFT" or "TOPRIGHT"
    end

    local shownSlots = maximum
    if shownSlots > table.getn(list) then shownSlots = table.getn(list) end

    local cols = perRow
    if shownSlots < cols then cols = shownSlots end
    local rows = ceil(shownSlots / perRow)
    if cols < 1 then cols = 1 end
    if rows < 1 then rows = 1 end

    anchor:SetWidth((cols * size) + ((cols - 1) * spacingX))
    anchor:SetHeight((rows * size) + ((rows - 1) * spacingY))

    for i = 1, table.getn(list) do
        local button = list[i]
        local base = button.GetWidth and button:GetWidth() or 30
        if not base or base <= 0 then base = 30 end
        local scale = size / base

        button:SetScale(scale)
        button:ClearAllPoints()

        local zero = i - 1
        local col = mod(zero, perRow)
        local row = floor(zero / perRow) + startRow

        --[[ **Offsets are divided by the button's own scale.**

             `SetPoint` measures its offsets in the *moving* frame's coordinate
             space, so a button at scale 1.6 asked to sit 53 units along lands
             85 screen pixels along instead. The anchor is left at scale 1 and
             is measured in screen pixels, so the two only agree once the offset
             is converted into the button's space. Without this, Icon Size and
             the spacing sliders pulled against each other -- large icons
             drifted apart and small ones overlapped. ]]--
        button:SetPoint(origin, anchor, origin,
                (xdir * col * (size + spacingX)) / scale,
                (ydir * row * (size + spacingY)) / scale)

        --[[ Past the user's cap the button is ours to hide; inside it the aura
             state is Blizzard's to decide, so a button coming back under a
             raised cap is handed to the client to recompute rather than simply
             shown -- an empty slot must stay empty. ]]--
        if i > maximum then
            button.ecoCapped = true
            button:Hide()
        elseif button.ecoCapped then
            button.ecoCapped = nil
            M:NativeUpdate(button)
        end
    end

    --[[ How many rows this block occupied, so the caller can start the next one
         underneath rather than counting the same arithmetic a second time. ]]--
    return rows
end

-- Ask Blizzard to recalculate a button when the user raises a maximum after we
-- previously hid it.  The native function is written around the 1.12 `this`
-- global, so temporarily give it exactly the context its XML script would.
function M:NativeUpdate(button)
    if not button or type(BuffButton_Update) ~= "function" then return end

    --[==[ **Not while a preview is up.**

         `BuffButton_Update` is the client deciding what is really in a slot, and
         during test mode the honest answer is "nothing" -- so it hides every
         button the preview had just filled. The preview then consisted of the
         icons being set and immediately taken away again, which looked like the
         feature simply not working.

         Skipped rather than fought: `TestStop` calls this on every button, which
         is what puts the real state back. ]==]
    if OB.testMode and self.testEnds then return end

    local oldThis = this
    this = button
    local ok = pcall(BuffButton_Update)
    this = oldThis
    return ok
end

--[==[ **The border, tinted by which hand it is on.**

     The client draws these with `UI-Debuff-Overlays` -- the same ring it uses
     for a debuff, which is why they arrive red. It is a texture like any other
     and takes a vertex colour, so the ring itself becomes the label rather than
     something being drawn on top of it. That is the same choice the item quality
     borders make, and for the same reason: one ring reads as a border, two read
     as a mistake.

     Painted every layout pass rather than once. The client rebuilds these
     buttons whenever an enchant lands or falls off, and a colour set at bind
     time would survive exactly until the first poison ran out. ]==]
--[==[ **The client repaints these buttons, and whoever paints last wins.**

     `TemporaryEnchantFrame_Update` rebuilds both weapon buttons whenever an
     enchant lands, falls off, or ticks a charge -- and it sets the border and
     the icon as it goes. This module painted from its own layout pass, which
     runs when a setting changes, so the client's pass came afterwards and
     replaced the colours with its own.

     What that looks like from outside is exactly what was reported twice: the
     border colours are "not correct" -- they are the client's, not the ones on
     the panel -- and they are "the wrong way round", because the client's
     convention is not this module's.

     Same shape as the keybind colours on the action bars, and the same answer:
     run after the client's own function rather than trying to run more often
     than it does. The original is kept in a global for the reason every hook
     here keeps one -- the module table is rebuilt on a reload and the function
     it replaced is not. ]==]
function M:InstallEnchantHook()
    if EquadisOverhaulBlizzTempEnchant then return false end
    if type(TemporaryEnchantFrame_Update) ~= "function" then return false end

    EquadisOverhaulBlizzTempEnchant = TemporaryEnchantFrame_Update

    TemporaryEnchantFrame_Update = function(a1, a2, a3, a4, a5, a6)
        EquadisOverhaulBlizzTempEnchant(a1, a2, a3, a4, a5, a6)

        local m = EquadisClassicOverhaul.modules
                and EquadisClassicOverhaul.modules.buffframes

        if m then m:AfterEnchantUpdate() end
    end

    return true
end

--[[ Everything this module puts on a weapon button, re-put. Both, because the
     client's pass rewrites both: the charge count is drawn into the same button
     the border goes round. ]]--
function M:AfterEnchantUpdate()
    if not OB.ModuleEnabled("buffframes") then return false end
    if not OB.ModuleShown("buffframes") then return false end

    self:ApplyEnchantCharges()
    self:PaintEnchantBorders()

    return true
end

function M:PaintEnchantBorders()
    local cfg = self:Config()

    --[[ By the weapon the button is showing, not by the button's number. A
         colour on the wrong icon is worse than no colour: it is a label that
         lies, and the whole point of it is to be believed at a glance. ]]--
    local hands = self:EnchantHands()

    for i = 1, 2 do
        local border = getglobal("TempEnchant" .. i .. "Border")
        local hand = hands[i]

        local colour = hand
                and (hand.hand == "main" and cfg.mainHandColor or cfg.offHandColor)

        --[==[ **An emptied slot gives the ring back rather than keeping the
             last poison's colour.**

             The paint shows the border, which it must -- the client does not
             show this ring for a temporary enchant, so a tinted texture nobody
             can see was the fault before. What it did not do is the other half:
             a button whose enchant has run out kept the colour and the shown
             state of the enchant that was there, so a rogue whose off-hand
             poison expired was left with a blue ring over nothing.

             The client's own white and hidden, which is the state this module
             found it in -- the same reasoning `Restore` gives for putting it
             back when the module is switched off, applied per slot instead of
             once at the end. ]==]
        if border and not colour then
            if border.SetVertexColor then border:SetVertexColor(1, 1, 1, 1) end
            if border.Hide then border:Hide() end
        end

        if border and border.SetVertexColor and colour then
            border:SetVertexColor(colour[1] or 1, colour[2] or 1,
                    colour[3] or 1, colour[4] or 1)

            --[==[ **And shown, which it was not.**

                 This used to colour the ring and leave its visibility entirely
                 to the client, on the reasoning that showing it ourselves would
                 put a coloured ring around an empty slot. The guard against that
                 is right here and is not visibility: `colour` is nil unless
                 `EnchantHands` says this button really has a weapon buff on it,
                 so the branch cannot be reached for an empty slot.

                 What the old reasoning assumed is that the client shows this
                 ring for a temporary enchant at all. `UI-Debuff-Overlays` is the
                 client's **debuff type** ring, and a weapon buff has no debuff
                 type -- so a build that leaves it hidden gives a perfectly
                 tinted texture nobody can see. Reported three times as the
                 border not showing correctly, and "not correctly" turned out to
                 include "not at all".

                 Showing it is also what makes the colour mean anything: it is
                 this module's label for which hand, not the client's ring
                 borrowed. ]==]
            if border.Show then border:Show() end
        end
    end

    return true
end

function M:ApplyLayout(refreshNative)
    if not OB.ModuleEnabled("buffframes") then return end

    --[[ Show unticked means the auras go back to Blizzard's layout, not that
         they vanish: this module owns no icons of its own, so "stop showing
         mine" can only mean "show the client's". Guarded on `applied` so a
         hidden feature does not re-run the restore on every redraw. ]]--
    if not OB.ModuleShown("buffframes") then
        if self.applied then
            self.applied = nil
            self:Restore()
        end
        return
    end

    self.applied = true
    if not self.helpful then self:Discover() end
    self:PlaceAnchors()

    local cfg = self:Config()

    if refreshNative then
        for i = 1, table.getn(self.helpful) do self:NativeUpdate(self.helpful[i]) end
        for i = 1, table.getn(self.harmful) do self:NativeUpdate(self.harmful[i]) end
    end

    --[[ **The weapon enchants first, on their own row above the buffs**, which
         is where the client draws them and where people look for them.

         Laid out before the buffs and against the same anchor, so dragging the
         buff frame takes the poison with it -- which it did not before, because
         nothing here had ever heard of `TempEnchant`. They take the buff row's
         size and spacing because they are the same icons at the same scale; what
         they do not take is `buffMax`, since capping the buffs at four has
         nothing to say about how many hands you have. ]]--
    layoutList(self.enchants, self.enchantAnchor,
            cfg.enchantSize or cfg.buffSize, 2, 2,
            cfg.enchantSpacingX or cfg.buffSpacingX, 0,
            cfg.enchantGrowX or cfg.buffGrowX, "down", 0)

    --[==[ **After the row is laid out, not before it.**

         `EnchantHands` decides which weapon a button is showing by walking the
         buttons the client has *shown*. Asked before the layout, that reads the
         previous pass's visibility -- so on the first pass, when nothing has
         been shown yet, it maps nothing and no border is painted at all; and on
         a pass where the buttons have just changed, it maps them the way they
         were a moment ago.

         It was placed first on the reasoning that an early return below would
         then still leave the borders right. That was the wrong trade: a border
         that is occasionally right is worse than one that is late, because the
         whole point of it is to be believed without being checked. ]==]
    self:PaintEnchantBorders()

    --[[ **The buffs no longer start below the enchants**, because the enchants
         are no longer on this anchor. Their row used to push the buffs down,
         which made the buff row's position depend on whether anything was on
         your weapon -- so a rogue's buffs sat lower than a mage's, and moved
         when a poison ran out. ]]--
    layoutList(self.helpful, self.buffAnchor,
            cfg.buffSize, cfg.buffPerRow, cfg.buffMax,
            cfg.buffSpacingX, cfg.buffSpacingY, cfg.buffGrowX, cfg.buffGrowY, 0)

    layoutList(self.harmful, self.debuffAnchor,
            cfg.debuffSize, cfg.debuffPerRow, cfg.debuffMax,
            cfg.debuffSpacingX, cfg.debuffSpacingY, cfg.debuffGrowX, cfg.debuffGrowY)

    self.enchantAnchor:Show()
    self.buffAnchor:Show()
    self.debuffAnchor:Show()

    self:ApplyTestIcons()
end

function M:Restore()
    self.dragging = nil
    self.applied = nil

    --[[ Before the buttons are put back, because the client's next pass over
         them reads these -- handing back a button and leaving the constant that
         dims it would hand back a dim button. ]]--
    self:RestoreClientFlash()

    self:RestoreEnchantTooltips()

    --[[ The client's own red comes back with everything else. A ring left gold
         by an addon that is no longer running is a leftover nobody can trace to
         anything on screen. ]]--
    for i = 1, 2 do
        local border = getglobal("TempEnchant" .. i .. "Border")

        if border and border.SetVertexColor then
            border:SetVertexColor(1, 1, 1, 1)

            --[[ And put away, because this module is what showed it. The
                 client's own pass decides whether it comes back. ]]--
            if border.Hide then border:Hide() end
        end
    end

    if type(TemporaryEnchantFrame_Update) == "function" then
        pcall(TemporaryEnchantFrame_Update)
    end

    if self.original then
        for button, saved in pairs(self.original) do
            if button and saved then
                button:SetScale(saved.scale or 1)
                if button.SetAlpha then button:SetAlpha(saved.alpha or 1) end
                restorePoints(button, saved.points)
                self:NativeUpdate(button)
            end
        end
    end

    -- Restore the stock row-start anchors after individual originals, because
    -- Blizzard deliberately changes these two according to duration visibility.
    if EquadisOverhaulBlizzBuffPositions then
        EquadisOverhaulBlizzBuffPositions()
    elseif type(BuffButtons_UpdatePositions) == "function" then
        BuffButtons_UpdatePositions()
    end

    self:ClearAuraTimers()

    if self.enchantAnchor then self.enchantAnchor:Hide() end
    if self.buffAnchor then self.buffAnchor:Hide() end
    if self.debuffAnchor then self.debuffAnchor:Hide() end
end

--[[ Reassert ECO's anchors after the client re-anchors a row start of its own.

     **Optional, and absent on a stock 1.12 client.** `BuffButtons_UpdatePositions`
     is a later-expansion name; nothing in a vanilla build defines it, so on most
     installs this simply does not hook and the module's own
     `PLAYER_AURAS_CHANGED` registration is what keeps the layout current. It is
     kept for the builds that do have it, where the event alone would race the
     client's re-anchor. No stock script is replaced or skipped either way. ]]--
function M:InstallPositionHook()
    if EquadisOverhaulBlizzBuffPositions then return end
    if type(BuffButtons_UpdatePositions) ~= "function" then return end

    EquadisOverhaulBlizzBuffPositions = BuffButtons_UpdatePositions

    BuffButtons_UpdatePositions = function()
        EquadisOverhaulBlizzBuffPositions()

        local m = EquadisClassicOverhaul
                and EquadisClassicOverhaul.modules
                and EquadisClassicOverhaul.modules.buffframes
        if m and EquadisClassicOverhaul.ModuleEnabled("buffframes")
                and EquadisClassicOverhaul.ModuleShown("buffframes") then
            m:ApplyLayout(false)
        end
    end
end

--[==[ **Which weapon a weapon buff is on, as an inventory slot.**

     `EnchantHands` already owns the button-to-hand mapping and has been got
     wrong twice, so it is asked rather than the name of the button being
     trusted -- with only the off hand enchanted, the poison is on button one
     and belongs to the second weapon.

     Slot numbers come from `GetInventorySlotInfo` rather than being written as
     16 and 17: the constants are the client's, and a server that reorders the
     paper doll would leave a hardcoded pair pointing at somebody's gloves. ]==]
local ENCHANT_SLOT_NAME = { main = "MainHandSlot", off = "SecondaryHandSlot" }

function M:EnchantSlot(button)
    if not button or type(GetInventorySlotInfo) ~= "function" then return nil end

    local index
    for i = 1, table.getn(self.enchants or {}) do
        if self.enchants[i] == button then index = i end
    end

    if not index then return nil end

    --[==[ **Through `EnchantHands`, not through the id directly.**

         The id says which slot a button is *named* after; `EnchantHands` says
         which weapon it is *showing*, having already weighed the id, the shown
         state and whether that hand is enchanted at all. Reading the id here
         instead put slot sixteen on a button displaying the off hand's poison,
         and answered "main hand" for a button showing nothing.

         One resolved answer, asked once, or the tooltip and the border can
         disagree about the same button. ]==]
    local hands = self:EnchantHands()
    local hand = hands and hands[index]
    local named = hand and hand.hand

    if not named or not ENCHANT_SLOT_NAME[named] then return nil end

    return GetInventorySlotInfo(ENCHANT_SLOT_NAME[named])
end

--[==[ **Hovering a weapon buff shows the weapon, and shows it the way this
     addon shows every other item.**

     The icon is a poison, a sharpening stone or an oil, and the only thing that
     knows anything about it is the weapon it is on -- the enchant's name, its
     remaining time and its charges are all lines on the weapon's own tooltip.
     So that is what is shown.

     **The decoration is the point.** `GameTooltip`'s `OnShow` is where this
     addon's tooltip pass runs, and `OnShow` does not fire for a tooltip that is
     already up -- which is exactly the case here, because these two buttons sit
     next to each other and the client re-populates the live tooltip when the
     cursor crosses from one to the other. So the second weapon got the client's
     plain tooltip: no vendor price, no quality border, none of it. Reported as
     the weapon buff not showing our tooltip for the weapon.

     Asking for the decoration outright costs one flag and settles it for both
     the first hover and the crossing. ]==]
function M:ShowEnchantTooltip(button)
    if not button or not GameTooltip then return false end

    local slot = self:EnchantSlot(button)
    if not slot then return false end

    OB.OwnTooltip(button, "ANCHOR_BOTTOMLEFT")

    if type(GameTooltip.SetInventoryItem) ~= "function" then return false end
    GameTooltip:SetInventoryItem("player", slot)

    --[[ And the addon's own pass, which the client's OnShow would otherwise
         skip for a tooltip that never went away. ]]--
    local tip = OB.modules and OB.modules.tooltip

    if tip and OB.ModuleEnabled("tooltip") and tip.QueueTooltip then
        tip:QueueTooltip(true)
    end

    GameTooltip:Show()
    return true
end

function M:HideEnchantTooltip()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    return true
end

--[==[ The client's own scripts are kept and put back by `Restore`, the same as
     the anchors and the border colours are. A button left with somebody else's
     hover behaviour after the module is switched off is a leftover nobody can
     trace to anything on screen. ]==]
function M:InstallEnchantTooltips()
    self.enchantScripts = self.enchantScripts or {}

    for i = 1, 2 do
        local button = getglobal("TempEnchant" .. i)

        if button and button.SetScript and not self.enchantScripts[button] then
            self.enchantScripts[button] = {
                enter = button.GetScript and button:GetScript("OnEnter"),
                leave = button.GetScript and button:GetScript("OnLeave"),
            }

            button:SetScript("OnEnter", function()
                local m = EquadisClassicOverhaul.modules.buffframes
                if m then m:ShowEnchantTooltip(this or button) end
            end)

            button:SetScript("OnLeave", function()
                local m = EquadisClassicOverhaul.modules.buffframes
                if m then m:HideEnchantTooltip() end
            end)
        end
    end

    return true
end

function M:RestoreEnchantTooltips()
    if not self.enchantScripts then return false end

    for button, saved in pairs(self.enchantScripts) do
        if button and button.SetScript then
            button:SetScript("OnEnter", saved.enter)
            button:SetScript("OnLeave", saved.leave)
        end
    end

    self.enchantScripts = nil
    return true
end

--[==[ **After the client's own per-frame pass, which is the only way to win
     this.**

     `BuffButton_OnUpdate` is the client counting a buff down, and on a buff
     close to expiring it writes `$parentDuration` -- the same string this module
     writes -- every frame. Nothing running on a timer of its own can beat that;
     it can only alternate with it, which is the shaking text and the colour that
     would not stick.

     This is the third hook in this file with the same shape and the same reason.
     `InstallEnchantHook` says it plainly: run after the client's own function
     rather than trying to run more often than it does. The border colours were
     this exact fault, and so were the action bar keybinds two files away.

     **The wrapper does no work of its own.** It puts back the decision the
     ten-times-a-second pass already made -- one string comparison per button
     per frame, on a pass the client is running anyway.

     The original goes in a global for the reason every hook here does: the
     module table is rebuilt on a reload and the function it replaced is not. ]==]
function M:InstallDurationHook()
    if EquadisOverhaulBlizzBuffDuration then return false end
    if type(BuffButton_OnUpdate) ~= "function" then return false end

    EquadisOverhaulBlizzBuffDuration = BuffButton_OnUpdate

    BuffButton_OnUpdate = function(a1, a2, a3, a4, a5, a6)
        EquadisOverhaulBlizzBuffDuration(a1, a2, a3, a4, a5, a6)

        local m = EquadisClassicOverhaul.modules
                and EquadisClassicOverhaul.modules.buffframes

        --[[ `this` is the button the client is updating, which is the whole of
             what this needs to know. A pass over all twenty-four here would be
             twenty-four times the work for the same answer. ]]--
        if m and this and this.eqEcoTimer
                and EquadisClassicOverhaul.ModuleEnabled("buffframes")
                and EquadisClassicOverhaul.ModuleShown("buffframes") then
            m:AssertTimer(this)
        end
    end

    return true
end

function M:OnBind()
    --[[ After the client's own pass over the weapon buttons -- see
         `InstallEnchantHook`. ]]--
    self:InstallEnchantHook()
    self:InstallDurationHook()
    self:InstallEnchantTooltips()

    self:EnsureAnchors()
    self:Discover()
    self:InstallPositionHook()
    self:ApplyLayout(true)
    self:ApplyEnchantCharges()
    self:ApplyAuraFlash()
end

function M:OnUnbind()
    self:Restore()

    -- hud.lua calls OB.HideFeature immediately after OnUnbind.  Do not leave
    -- Blizzard's buttons in `frames` at that moment or the generic cleanup would
    -- hide the stock aura UI we just restored.  Discover() repopulates the list
    -- next time the feature is bound.
    self.frames = { self.buffAnchor, self.debuffAnchor }
end

-- ---------------------------------------------------------------------------
-- how many charges are left on a weapon
-- ---------------------------------------------------------------------------

--[[ **A rogue's poison has a number of charges and the client shows none of it.**

     `TempEnchant1` and `TempEnchant2` draw an icon and a duration, which answers
     "how long" and never "how many". For a sharpening stone that is fine --
     they run out on time. For poison it is the wrong question entirely: Instant
     Poison is spent per hit, so a fight can strip a full application well before
     its clock runs down, and the first anybody knows is the icon vanishing
     mid-fight.

     The client has the number the whole time. `GetWeaponEnchantInfo` returns
     charges for both hands beside the expiry it already draws -- so this is a
     font string, not a calculation.

     **Drawn only when there is a count**, because most weapon buffs have no
     charges at all and a "0" on a sharpening stone would be worse than the
     nothing it replaces. ]]--
function M:EnchantCount(button)
    if button.eqEcoCharges then return button.eqEcoCharges end

    local text = OB.NewText(button, "OVERLAY", "NumberFontNormal")

    --[[ Bottom right, which is where the client puts a stack count on every
         other icon in the interface -- and the opposite corner to the duration
         underneath, so the two never sit on each other. ]]--
    text:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    text:SetJustifyH("RIGHT")

    button.eqEcoCharges = text
    self:SizeAuraText(button)

    return text
end

--[==[ **Which player-buff slot this button is showing, and a row position is
     not one.**

     This read `button:GetID()` straight into `GetPlayerBuffTimeLeft`, and the
     two are different numbers. 1.12 keeps **one** aura handle space holding
     this player's buffs and debuffs together, and `GetPlayerBuff(position,
     filter)` is the call that turns "third icon in the buff row" into a handle
     in it. A position used as a handle therefore reads *some other aura's*
     clock -- and with any debuff on you the two spaces diverge, so it is
     usually somebody else's number rather than none.

     **This exact mistake was found once already**, in v0.99.214: `MountBuff`
     walked 0, 1, 2 into `GetPlayerBuffTexture`, one debuff was enough to make
     it decide you were not mounted, and `OB.PlayerBuffIndex` was written to be
     the one place the conversion lives. Every other reader in this addon was
     moved onto it. This module was not, and nothing noticed, because the
     harness keyed its durations by whatever number the test handed it.

     Every addon on this machine that reads a player aura does it the same way
     -- BigWigs, BetterCharacterStats and SuperCleveRoidMacros all walk
     positions from nought and resolve each one. That is not a coincidence; it
     is the only thing that works.

     **The resolve is authoritative, including when it says nothing.** A
     position holding no aura answers `-1`, and the honest reading of that is
     "this slot is empty" -- falling through to the ID there would put the old
     bug back for exactly the buttons most likely to hit it.

     `buffIndex` first, for builds that write the handle onto the button
     themselves; `GetID` last, for a client with no `GetPlayerBuff` at all,
     where a position is the only number there is. ]==]
function M:BuffIndex(button)
    if not button then return nil end

    if type(button.buffIndex) == "number" then return button.buffIndex end

    if type(button.eqAuraPosition) == "number"
            and type(GetPlayerBuff) == "function" then
        return OB.PlayerBuffIndex(button.eqAuraPosition, button.eqAuraHarmful)
    end

    if button.GetID then
        local index = button:GetID()
        if type(index) == "number" then return index end
    end

    return nil
end

--[==[ **The client answers this one exactly, which the target's auras do not.**

     A debuff on somebody else has no duration in 1.12 and has to be estimated
     from a shipped table. Your own auras are different: `GetPlayerBuffTimeLeft`
     is a real answer from the client, so this module needs no table and can
     never be wrong about a spell nobody thought to list.

     Nought or less is not a short buff, it is a buff with no clock -- an aura,
     a stance, anything until-cancelled. Those get no text rather than a zero
     that would read as "about to drop". ]==]
--[==[ **What a buff frame looks like with something on it.**

     Nobody customises an aura display while it is empty, and the honest way to
     see one full is to stand in a city collecting buffs -- which is a poor way
     to decide whether the icons are the right size.

     The question mark is the client's own "no icon for this", so it reads as a
     placeholder rather than as a spell somebody has to recognise. Every slot
     showing the same picture is the point: what is being judged here is size,
     spacing, growth and where the numbers sit, and eight different icons would
     be eight things to look at instead. ]==]
local TEST_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--[==[ **Spread rather than random.**

     `math.random` would give a different picture every time test mode is
     entered, so a change you just made and the numbers moving would be the same
     event. These are arbitrary and fixed: a few seconds, a few minutes, an hour,
     and one with no clock at all -- which is the case worth seeing, because an
     aura with no timer is the one whose icon has nothing under it.

     Prime-ish steps so neighbours do not tick over together and give the whole
     row a heartbeat. ]==]
local TEST_DURATIONS = { 7, 23, 61, 154, 0, 312, 45, 1830, 12, 96, 604, 38 }

function M:TestDuration(index)
    local n = table.getn(TEST_DURATIONS)
    local at = index - math.floor((index - 1) / n) * n
    return TEST_DURATIONS[at] or 30
end

function M:TestStart(startedAt)
    self:Discover()

    self.testEnds = {}
    local now = startedAt or GetTime()

    local function fill(list, limit)
        for i = 1, table.getn(list) do
            local button = list[i]

            if button and (not limit or i <= limit) then
                --[[ Shown by us rather than by the client, which would hide it
                     again the moment it noticed the slot is empty. ]]--
                if button.Show then button:Show() end

                local icon = getglobal((button.GetName and button:GetName() or "")
                        .. "Icon")
                if icon and icon.SetTexture then icon:SetTexture(TEST_ICON) end

                local seconds = self:TestDuration(i)
                self.testEnds[button] = (seconds > 0) and (now + seconds) or false
            end
        end
    end

    local cfg = self:Config()

    self.testFill = fill

    self:ApplyTestIcons()
    self:ApplyLayout(false)
    return true
end

--[==[ Re-applied after every layout pass, because a layout can re-anchor and
     re-show the client's own buttons underneath the preview. Cheap, and it means
     the preview survives somebody dragging a slider while it is up -- which is
     the entire situation it exists for. ]==]
function M:ApplyTestIcons()
    if not OB.testMode or not self.testEnds or not self.testFill then return end

    local cfg = self:Config()

    self.testFill(self.enchants or {})
    self.testFill(self.helpful or {}, cfg.buffMax)
    self.testFill(self.harmful or {}, cfg.debuffMax)

    return true
end

function M:TestStop()
    self.testEnds = nil
    self.testFill = nil

    --[[ Handed back to the client rather than hidden: `BuffButton_Update` is
         what knows whether a slot is really occupied, and it puts the real icon
         back at the same time. ]]--
    for _, list in ipairs({ self.enchants or {}, self.helpful or {},
                            self.harmful or {} }) do
        for i = 1, table.getn(list) do
            self:NativeUpdate(list[i])
        end
    end

    self:ApplyLayout(true)
    return true
end

function M:BuffTimeLeft(button)
    --[==[ Test mode answers first. The real call would say nought for a slot the
         client knows is empty, and every test icon would draw no timer -- which
         is exactly the thing being previewed. ]==]
    if OB.testMode and self.testEnds then
        local ends = self.testEnds[button]

        if ends == false then return nil end
        if ends then
            local left = ends - GetTime()

            --[[ Wrapped rather than expired. A preview that empties itself after
                 a minute is a preview that is blank by the time somebody has
                 finished adjusting it. ]]--
            if left <= 0 then return 1 end
            return left
        end

        return nil
    end

    if type(GetPlayerBuffTimeLeft) ~= "function" then return nil end

    local index = self:BuffIndex(button)
    if not index then return nil end

    local ok, left = pcall(GetPlayerBuffTimeLeft, index)
    if not ok or type(left) ~= "number" or left <= 0 then return nil end

    return left
end

--[==[ **The client's own duration string, not a second one on top of it.**

     The client draws a buff's remaining time in `$parentDuration`, under the
     icon. This made its own font string and put it in the same place -- so with
     the client's durations turned on there were two numbers stacked on one
     another, which is what was reported and is visible the moment they disagree
     by a second.

     Writing into the client's own is also the answer to "can we just edit the
     normal timer": there is then one string, in the place everybody's eye
     already goes, wearing whatever font the interface is using.

     The fallback stays for the buttons that have no such string -- a reskin can
     remove it, and a temporary enchant on some builds never had one. It is the
     same position, which is safe precisely because nothing else is drawing
     there in that case. ]==]
--[==[ **A timer says how long is left; a colour says whether that is a
     problem.**

     Reading "4m12s" takes a moment, and the moment is the point: a buff about
     to drop mid-pull has to be noticeable without being read. Five bands, from
     comfortable to now, and the numbers are the ones people already think in --
     half an hour, five minutes, two minutes, thirty seconds.

     Each band is a colour on the panel rather than a fixed palette, because
     what reads as "fine" against a dark UI and against a bright one are not the
     same colour, and this addon does not know which somebody is running.

     Ordered longest first and read top to bottom, so the bands cannot overlap
     and there is no arithmetic to get wrong when one is edited. ]==]
local TIMER_BANDS = {
    { 1800, "timerOver30mColor" },
    {  300, "timerOver5mColor"  },
    {  120, "timerUnder5mColor" },
    {   30, "timerUnder2mColor" },
    {    0, "timerUnder30sColor" },
}

--[[ Which band a duration falls in, as a name rather than a number, so a caller
     can tell "the same band as last time" without knowing what the bands
     are. ]]--
function M:TimerBand(seconds)
    if type(seconds) ~= "number" then return nil end

    for i = 1, table.getn(TIMER_BANDS) do
        if seconds > TIMER_BANDS[i][1] then return TIMER_BANDS[i][2] end
    end

    --[[ Zero and below is the last band rather than nothing: a timer reading
         "0" is the most urgent thing on screen, not the least. ]]--
    return TIMER_BANDS[table.getn(TIMER_BANDS)][2]
end

--[[ The colour for a duration, or nothing when the feature is off -- which the
     caller reads as "leave the text the colour the client gave it". ]]--
function M:TimerColor(seconds)
    local cfg = self:Config()
    if not cfg.timerColors then return nil end

    local band = self:TimerBand(seconds)
    local color = band and cfg[band]

    if type(color) ~= "table" then return nil end
    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

--[==[ **Our own string, and the client's turned invisible rather than fought
     over.**

     This used to return `$parentDuration` -- the client's own font string --
     on the reasoning that making a second one put two numbers on top of each
     other. The reasoning was right and the conclusion was not, because **the
     client writes that string every frame** for a buff close to expiring.

     Three goes at winning that fight, and each one failed differently:

       * a cache of what we last wrote meant the client hiding the string was
         never noticed and the timer never came back;
       * reading the widget back instead turned that into ten assertions a
         second against sixty, which is text jittering between two widths and a
         colour that reads as the client's;
       * running from `BuffButton_OnUpdate` would have settled it -- **if that
         global exists on this build.** It is not in vanilla's documented API
         surface, this addon cannot check for it on a client it is not running
         on, and a fix that silently does nothing is worse than no fix.

     So the fight is abandoned instead of won. We draw our own string and set the
     client's to **alpha zero once**, which survives every `Show` and `SetText`
     the client does -- it changes the text and the visibility of that string,
     never its alpha. Two numbers cannot stack when only one of them has any
     opacity, and nothing has to run at any particular time for that to hold.

     The alpha is put back by `Restore`, the same as the anchors and the border
     colours are. ]==]
--[==[ The client's own number, turned invisible. Its own function because two
     callers need it and both used to get it wrong by not calling it: doing this
     only where the string is built means `Restore` handing it back can never be
     undone, and showing the buff frames again would stack the two numbers a
     second time. ]==]
--[==[ **Only while we are drawing one.**

     Silencing the client's duration string is what stops two numbers stacking,
     and it was done unconditionally -- so switching **Show Time Left On Auras**
     off hid ours and left theirs invisible, and the answer to "I do not want
     your timers" became *no timer at all*, on every buff and every weapon
     enchant. That is worse than the state this module found, which is the line
     `ClearAuraTimers` already draws for handing the auras back.

     Followed to the setting rather than to whether this particular icon has a
     number: an aura with no clock -- a stance, a paladin aura -- has no number
     from either of us, and flickering the client's on for those would be two
     behaviours where there should be one. ]==]
function M:SilenceClientTimer(button, on)
    local theirs = button and button.eqEcoTheirTimer
    if not theirs or not theirs.SetAlpha then return false end

    if on == nil then on = self:Config().showAuraTimers and true or false end

    local wanted = on and 0 or 1

    --[[ Compared rather than written blindly: this is on a path that runs ten
         times a second for every icon on screen. ]]--
    if theirs.GetAlpha and theirs:GetAlpha() == wanted then return true end

    theirs:SetAlpha(wanted)
    return true
end

function M:AuraTimer(button)
    if not button then return nil end

    if button.eqEcoTimer then
        self:SilenceClientTimer(button)
        return button.eqEcoTimer
    end

    --[[ The client's, remembered so `Restore` can hand it back without having
         to work the name out again. ]]--
    if button.GetName and button:GetName() then
        local theirs = getglobal(button:GetName() .. "Duration")
        if theirs then button.eqEcoTheirTimer = theirs end
    end

    self:SilenceClientTimer(button)

    --[==[ Under the icon rather than on it. A number over the artwork hides the
         one thing the icon is for -- being recognised without being read -- and
         the charges already have the bottom-right corner. This is where the
         client draws its own, which is why it is the right place. ]==]
    local text = OB.NewText(button, "OVERLAY", "NumberFontNormalSmall")

    text:SetPoint("TOP", button, "BOTTOM", 0, 1)
    text:SetJustifyH("CENTER")

    button.eqEcoTimer = text
    self:SizeAuraText(button)

    return text
end

--[==[ **The two numbers on a buff icon, sized against the icon.**

     Neither was ever fonted by this addon: both came from a client template and
     drew at whatever that says. Applied through `OB.ApplyFont` rather than
     `SetFont` so the profile's face and outline still arrive -- the size is the
     only thing being decided here.

     Re-applied on every style pass, because the size is a setting and a number
     written once at creation would not change until a reload. ]==]
function M:SizeAuraText(button)
    if not button then return false end

    local cfg = self:Config()

    if button.eqEcoTimer then
        OB.ApplyFont(button.eqEcoTimer, tonumber(cfg.timerFontSize) or 10,
                "buffframes")

        --[==[ **The outline after the font**, because `ApplyFont` sets all three
             together and would put the profile's answer back over this one.

             Only where a choice has been made: with no setting the string keeps
             whatever `ApplyFont` gave it, which is the profile's, which is what
             every other string here does. ]==]
        local flags = OB.FontFlags(cfg.timerOutline)

        if cfg.timerOutline ~= nil and button.eqEcoTimer.GetFont then
            local path, size = button.eqEcoTimer:GetFont()

            if path then button.eqEcoTimer:SetFont(path, size, flags) end
        end

        --[==[ ~~And no width.~~ **The string is left to size itself.**

             It used to be given the icon's width, so that a string too long for
             the icon overran evenly on both sides rather than off one. What that
             actually buys is truncation: a font string with a width is a box,
             and `4m59s` too wide for a thirty pixel box is shortened to fit or
             dropped entirely -- which is the disappearing text, not a
             cosmetic overrun.

             The overrun it was fixing is a font size problem and there is now a
             font size slider. Two answers to one question, and this is the one
             that loses information. ]==]
    end

    if button.eqEcoCharges then
        OB.ApplyFont(button.eqEcoCharges, tonumber(cfg.chargeFontSize) or 11,
                "buffframes")
    end

    return true
end

--[==[ **Written only when it differs from what is on screen -- which is not
     the same as when it differs from what we last wrote.**

     Both guards here used to be caches of this module's own last write, and
     the string they guard is **the client's own**: `AuraTimer` returns
     `$parentDuration` wherever the button has one, because two numbers stacked
     on each other was the original complaint. 1.12 draws that string itself for
     a buff close to expiring and *hides it again* the rest of the time, so the
     client writing and hiding it is not an edge case, it is the normal
     behaviour of the widget.

     A cache cannot see that. Once the client hid the string, `eqEcoTimerValue`
     still held the last number written, every later pass agreed there was
     nothing to do, and **the timer never came back** -- not on the next tick,
     not on the next buff, not until a reload. Same for the colour: the band had
     not changed, so the repaint was skipped and the client's white stood.

     That is the third time this shape has been found in this addon -- the
     action bar keybind, then the macro name, now this -- and it is always the
     same lesson: a widget somebody else also writes to has to be *read*, never
     remembered.

     It costs no more than the cache did. The string comparison replaces a
     string comparison, and `SetText` is still only called when the text really
     differs, which is the redraw that was worth avoiding in the first place. ]==]
local COLOR_EPSILON = 0.004

--[==[ **Putting a decision back onto the widget, without making it again.**

     The client writes this string too, and it writes it *per frame* -- which is
     why v0.99.234's read-it-back fix turned a timer that vanished into a timer
     that shook. Ten assertions a second against sixty is not a fix, it is a
     race with a duty cycle: five frames out of six showed the client's string
     and one showed ours, so the text jittered between two widths and the colour
     read as the client's. Worst on short buffs, because a buff close to
     expiring is exactly when 1.12 starts drawing its own duration -- which is
     the "under 30 seconds has no colour" half of the same report.

     So the decision and the assertion are separated. `SetTimerText` decides,
     ten times a second, because that is how often a number of whole seconds can
     change. This puts the decision back, and is cheap enough to run from the
     client's own per-frame pass: no `GetPlayerBuff`, no arithmetic, one string
     comparison and usually nothing else.

     The stored value is a **record of what was decided**, not a licence to skip
     -- which is the distinction v0.99.234 got right and this keeps. Nothing here
     trusts it about what is on screen; it is only ever compared against what is
     really there. ]==]
function M:AssertTimer(button)
    if not button then return false end

    local text = button.eqEcoTimer
    if not text then return false end

    --[==[ **The client's own number kept invisible, every pass rather than
         once.**

         `AuraTimer` sets it to alpha zero when it builds ours, and that was the
         whole of it -- so `Restore` handing the string back (which it must, or
         switching this module off would leave the auras with no duration at
         all) could never be undone. Show the buff frames again and `AuraTimer`
         returns the cached string without re-silencing anything, and the two
         numbers are stacked once more. Found by the assertion that the alpha is
         really zero, which is a thing the harness could not read until now.

         A comparison rather than a blind write, because this runs ten times a
         second on every icon, and it self-heals if anything else raises it. ]==]
    self:SilenceClientTimer(button)

    local value = button.eqEcoTimerValue
    local rgba = button.eqEcoTimerColor

    if rgba and text.GetTextColor and text.SetTextColor then
        local haveR, haveG, haveB, haveA = text:GetTextColor()

        if not haveR
                or math.abs(haveR - rgba[1]) > COLOR_EPSILON
                or math.abs((haveG or 0) - rgba[2]) > COLOR_EPSILON
                or math.abs((haveB or 0) - rgba[3]) > COLOR_EPSILON
                or math.abs((haveA or 1) - rgba[4]) > COLOR_EPSILON then
            text:SetTextColor(rgba[1], rgba[2], rgba[3], rgba[4])
        end
    end

    local have = text.GetText and text:GetText() or nil
    local shown = text.IsShown and text:IsShown() and true or false

    if value then
        if have ~= value then text:SetText(value) end
        if not shown then text:Show() end
    else
        if have ~= "" and have ~= nil then text:SetText("") end
        if shown then text:Hide() end
    end

    return true
end

function M:SetTimerText(button, value, seconds)
    local text = self:AuraTimer(button)
    if not text then return false end

    --[==[ **The colour is decided on the seconds, not on the string.**

         "5m" is written for anything from five minutes to five minutes and
         fifty-nine seconds, so a buff can cross from comfortable into the next
         band without the text changing at all -- and a guard on the text would
         then leave the old colour on a number that no longer means it. ]==]
    local band = self:Config().timerColors and self:TimerBand(seconds) or "off"

    --[[ Kept as a record of which band is showing -- it is the useful thing to
         read when something looks the wrong colour -- but nothing is gated on
         it any more. ]]--
    button.eqEcoTimerBand = band

    local r, g, b, a

    if band == "off" then
        --[[ The client's own white, or a colour set while the feature was on
             would outlive it being switched off. ]]--
        r, g, b, a = 1, 1, 1, 1
    else
        r, g, b, a = self:TimerColor(seconds)
    end

    --[[ The decision, written down where the per-frame assertion can find it
         without doing any of this again. ]]--
    button.eqEcoTimerValue = value
    button.eqEcoTimerColor = r and { r, g or 1, b or 1, a or 1 } or nil

    return self:AssertTimer(button)
end

--[==[ **The two lists walked directly, not gathered into a third.**

     `{ self.helpful, self.harmful }` reads well and builds a table every call.
     On a per-frame pass that is a table per frame for the whole session -- and
     a table nobody reads twice is the purest form of the garbage that makes a
     client hitch every few seconds rather than run slowly. ]==]
function M:ApplyAuraTimerList(list, on)
    if not list then return end

    for j = 1, table.getn(list) do
        local button = list[j]

        --[==[ A hidden button is an empty slot, not an expired aura. The
             client keeps the whole row built and shows the ones in use, so
             asking the rest for a duration would answer about whatever was
             there last. ]==]
        local live = button and button.IsShown and button:IsShown()

        if button then
            if on and live then
                --[[ The seconds go with the string: the colour is a fact about
                     the duration and the string has already thrown most of it
                     away. ]]--
                --[==[ A weapon buff's time comes from a different call
                     entirely -- see `EnchantTimeLeft`. Asked first, because a
                     `TempEnchant` button has no player-buff index and the
                     other path would answer nothing for it. ]==]
                local left = self:EnchantTimeLeft(button)
                if not left then left = self:BuffTimeLeft(button) end

                local cfg = self:Config()

                self:SetTimerText(button,
                        OB.DurationIn(cfg.timerFormat, left, cfg.secondsUnder),
                        left)
            else
                self:SetTimerText(button, nil)
            end
        end
    end
end

--[[ Every icon this module has built a number on. Walked from `original`,
     which is the one list holding all three rows. ]]--
function M:SizeAllAuraText()
    if not self.original then return false end

    for button in pairs(self.original) do
        self:SizeAuraText(button)
    end

    return true
end

function M:ApplyAuraTimers()
    local on = self:Config().showAuraTimers

    self:ApplyAuraTimerList(self.helpful, on)
    self:ApplyAuraTimerList(self.harmful, on)

    --[[ The third row. It was missing from here, which is the whole of why a
         poison showed its charges and never its minutes. ]]--
    self:ApplyAuraTimerList(self.enchants, on)

    return true
end

--[==[ The timers go back with everything else. They are ECO's own font strings
     on Blizzard's buttons, so nothing else would ever take them off. ]==]
function M:ClearAuraTimers()
    if not self.original then return end

    for button in pairs(self.original) do
        if button and button.eqEcoTimer then
            --[[ The decision goes with the text. Left behind, the per-frame
                 assertion would put a timer back onto a button this module has
                 just handed to the client. ]]--
            button.eqEcoTimerBand = nil
            button.eqEcoTimerValue = nil
            button.eqEcoTimerColor = nil
            button.eqEcoTimer:SetText("")
            button.eqEcoTimer:Hide()

            --[[ And the client's own number becomes visible again, or handing
                 the auras back would leave them with no duration at all --
                 which is a worse state than the one this module found. ]]--
            if button.eqEcoTheirTimer and button.eqEcoTheirTimer.SetAlpha then
                button.eqEcoTheirTimer:SetAlpha(1)
            end
        end
    end
end

--[==[ **Which hand each button is actually showing, rather than which one it
     is named after.**

     Both the charge count and the border colour assumed `TempEnchant1` is the
     main hand and `TempEnchant2` the off hand, always. `GetWeaponEnchantInfo`
     does answer in that order -- but the client's own
     `TemporaryEnchantFrame_Update` fills the buttons **in sequence from the
     first**, so a rogue with a poison on the off hand and nothing on the main
     gets that poison drawn in button *one*.

     Under that assumption the number and the colour are then both attached to
     the wrong weapon, which is the "wrong or swapped" this was asked about --
     and it is silent, because one poison on one weapon looks perfectly
     reasonable however it is labelled.

     Derived from what is on screen instead: walk the buttons the client has
     shown, in order, and hand them the enchanted weapons in order. That is
     correct whether the client packs them or leaves a gap, which matters
     because *which* it does is a detail of a client this cannot interrogate --
     and being wrong about it is what caused the bug in the first place. ]==]
--[==[ **What the client says, and what is on each button, side by side.**

     This mapping has now been written twice from reasoning and been wrong
     twice: once assuming the button number is the weapon's hand, once deriving
     it from which buttons are shown. Both are defensible readings of a client
     that cannot be interrogated from here, and neither survived contact.

     So it prints the numbers instead. `GetWeaponEnchantInfo` answers six
     values; each `TempEnchant` button answers whether it is shown, what icon it
     carries and what this addon has written on it. Between them there is no
     room left for a third wrong theory. ]==]
function M:DebugEnchants()
    local say = function(text) OB.Raw("  " .. text) end
    OB.Print("weapon enchants:", "Buffs")

    if type(GetWeaponEnchantInfo) ~= "function" then
        return say("this client has no GetWeaponEnchantInfo")
    end

    local hasMain, mainExpiry, mainCharges,
          hasOff, offExpiry, offCharges = GetWeaponEnchantInfo()

    say("GetWeaponEnchantInfo answers:")
    say("   main hand: " .. (hasMain and "yes" or "no")
            .. ", " .. tostring(mainCharges) .. " charges, "
            .. tostring(mainExpiry) .. " left")
    say("   off hand:  " .. (hasOff and "yes" or "no")
            .. ", " .. tostring(offCharges) .. " charges, "
            .. tostring(offExpiry) .. " left")

    --[[ And what is actually on screen, which is the half the code has been
         guessing at. ]]--
    for i = 1, 2 do
        local button = getglobal("TempEnchant" .. i)

        if not button then
            say("TempEnchant" .. i .. ": no such button")
        else
            local icon = getglobal("TempEnchant" .. i .. "Icon")
            local shown = button.IsShown and button:IsShown()

            local count = button.eqEcoCharges
                    and button.eqEcoCharges:GetText() or "(none)"

            --[[ The red channel alone, taken by assignment rather than with
                 `select`: 1.12 is Lua 5.0 and has no such function. This client
                 happens to provide one, which is exactly how a call like that
                 gets written and never noticed. ]]--
            local border = getglobal("TempEnchant" .. i .. "Border")
            local r

            if border and border.GetVertexColor then
                local red = border:GetVertexColor()
                r = OB.Round((red or 0) * 100)
            end

            say("TempEnchant" .. i .. ": " .. (shown and "shown" or "hidden")
                    .. ", icon " .. tostring(icon and icon:GetTexture())
                    .. ", we wrote '" .. tostring(count) .. "'"
                    .. ", border red " .. tostring(r) .. "%")
        end
    end

    --[[ And what this module currently believes, so a wrong belief is visible
         beside the facts that should have produced it. ]]--
    local hands = self:EnchantHands()

    for i = 1, 2 do
        local hand = hands[i]
        local button = getglobal("TempEnchant" .. i)
        local id = button and button.GetID and button:GetID() or nil

        say("we think TempEnchant" .. i .. " is the "
                .. (hand and hand.hand or "nothing")
                .. " hand with " .. tostring(hand and hand.charges) .. " charges"
                .. "  (button id " .. tostring(id) .. " = "
                .. tostring(self:EnchantSlotHand(button) or "unknown") .. ")")
    end
end

--[==[ **Which weapon a button is showing, asked of the button.**

     The client's own `OnEnter` for these two is
     `GameTooltip:SetInventoryItem("player", this:GetID())` -- so the button
     already knows, and has known all along. Sixteen is the main hand and
     seventeen the off hand.

     Everything below used to infer it from **how many weapons are enchanted**,
     on the reasoning that the client fills the buttons in order from the first.
     That is right whenever both hands are enchanted and right whenever only the
     main hand is, which is nearly always -- and it is a guess, so a build that
     fills them any other way makes it wrong in every direction at once: the
     colours land on the wrong ring, the charges land on the wrong icon, and both
     look "swapped". Reported as exactly that.

     Asked rather than inferred, the question has one answer and no build can
     disagree with it. The packing order stays as the fallback for a build whose
     buttons carry no id. ]==]
local ENCHANT_SLOT = { [16] = "main", [17] = "off" }

function M:EnchantSlotHand(button)
    if not button or not button.GetID then return nil end

    local ok, id = pcall(button.GetID, button)
    if not ok then return nil end

    return ENCHANT_SLOT[tonumber(id) or 0]
end

function M:EnchantHands()
    local out = {}

    if type(GetWeaponEnchantInfo) ~= "function" then return out end

    local hasMain, _, mainCharges,
          hasOff, _, offCharges = GetWeaponEnchantInfo()

    --[[ In the order the client reports them, which is the order it draws
         them: main hand first. ]]--
    local wanted = {}

    if hasMain then
        table.insert(wanted, { hand = "main", charges = tonumber(mainCharges) })
    end

    if hasOff then
        table.insert(wanted, { hand = "off", charges = tonumber(offCharges) })
    end

--[==[ **The nth enchanted weapon goes on the nth button, and nothing is
         asked about the buttons themselves.**

         The first attempt at this walked the buttons the client had *shown* and
         handed them the weapons in order. That reads well and does not work:
         the shown state is set by the client's own update pass, so anything
         asking before it has run sees the previous state -- or, on the first
         pass of a session, sees nothing shown and maps nothing at all. That is
         the "main hand colour never applies" this was reported as, and the
         suite reproduced it exactly once these tests existed.

         `TemporaryEnchantFrame_Update` fills the buttons in sequence from the
         first, so the packing rule *is* the mapping and it needs no frame state
         to state it. With both weapons enchanted this is the obvious
         one-to-one; with only the off hand, its poison is on button one and is
         labelled as the off hand, which is the case the original code got
         wrong.

         If some build leaves a gap instead of packing, this writes to a button
         that build has hidden -- nothing appears where nothing is drawn, which
         is a harmless way to be wrong. Depending on visibility was not: it
         showed nothing, ever. ]==]
    --[==[ **Right whether the client packs these buttons or leaves a gap, because
         this addon cannot know which and has now been wrong about it twice.**

         The packing model -- the nth enchanted weapon on the nth button -- was
         written down as fact and is a guess. So was the id model that replaced
         it. Both are right when both hands are enchanted, which is why either
         survives casual use, and they disagree exactly when one weapon is
         enchanted and it is the off hand. Reported as the colours not applying,
         the hands swapped, and the charges swapped and missing -- which is what
         one wrong mapping looks like from three angles.

         So neither is trusted on its own. The rule uses the one fact that is not
         a model: **which buttons the client is showing.**

           * A button the client has hidden gets nothing. It is not displaying a
             weapon buff, whatever any theory says.
           * A shown button whose id names an enchanted hand is that hand. The id
             is what the client's own tooltip handler reads, so where it exists
             it is the client's own answer.
           * A shown button with no usable id takes the next enchanted hand in
             order, which is the packing model doing what it was always for.

         Under a client that packs, the shown buttons are the first n and the
         order fills them correctly. Under a client that does not, each shown
         button names itself. Neither case needs this addon to have guessed
         right. ]==]
    local taken = { main = false, off = false }
    local pending = {}

    for i = 1, table.getn(wanted) do table.insert(pending, wanted[i]) end

    --[==[ **Only once the client has drawn something, which is the fix this must
         not undo.**

         The first version of this mapping walked the *shown* buttons and handed
         them the weapons in order. It reads well and does not work: the shown
         state is set by the client's own update pass, so asking before that has
         run sees the previous state -- and on the very first pass of a session
         sees nothing at all and maps nothing. Reported as the main hand colour
         never applying, and there is a test standing over it.

         So the shown state is used to **disambiguate**, never as the source. If
         the client has not drawn either button yet there is nothing to
         disambiguate with, and the packing order answers exactly as it did
         before -- which is right often enough to have shipped, and is checked
         again by the layout pass the moment the client does draw. ]==]
    local anyShown = false

    for i = 1, 2 do
        local button = getglobal("TempEnchant" .. i)
        if button and button.IsShown and button:IsShown() then anyShown = true end
    end

    if not anyShown then
        for i = 1, 2 do out[i] = wanted[i] end
        return out
    end

    --[[ First pass: the buttons that answer for themselves. ]]--
    for i = 1, 2 do
        local button = getglobal("TempEnchant" .. i)
        local shown = button and button.IsShown and button:IsShown()
        local hand = shown and self:EnchantSlotHand(button)

        if hand == "main" and hasMain then
            out[i] = { hand = "main", charges = tonumber(mainCharges) }
            taken.main = true
        elseif hand == "off" and hasOff then
            out[i] = { hand = "off", charges = tonumber(offCharges) }
            taken.off = true
        end
    end

    --[[ Second pass: anything still showing and unaccounted for takes the next
         enchanted hand nobody has claimed. ]]--
    for i = 1, 2 do
        local button = getglobal("TempEnchant" .. i)
        local shown = button and button.IsShown and button:IsShown()

        if shown and not out[i] then
            for p = 1, table.getn(pending) do
                local entry = pending[p]

                if entry and not taken[entry.hand] then
                    out[i] = entry
                    taken[entry.hand] = true
                    break
                end
            end
        end
    end

    --[==[ **And nothing at all if the client is showing neither**, which is the
         first pass of a session: the buttons have not been built yet and
         painting a hidden one is how the borders came out blank before. The
         layout runs `PaintEnchantBorders` again after the client's own update,
         so there is a later pass that finds them shown. ]==]
    return out
end

--[==[ **A weapon buff's clock, which came from nowhere.**

     The timer pass walks `helpful` and `harmful` and stopped there, so poisons,
     sharpening stones and shaman weapon buffs -- the third list, drawn as its
     own row above the buffs -- had a charge count and no time left. Every other
     aura on screen carried a number and these did not, which reads as the buff
     frame changes not having taken.

     They cannot come from the same source either: an enchant is not a player
     buff, so `GetPlayerBuffTimeLeft` knows nothing about it.
     `GetWeaponEnchantInfo` answers both hands at once and **in milliseconds**,
     which is the detail worth stating rather than discovering.

     Which button is which hand is `EnchantHands`' problem and has been got
     wrong twice; this asks it rather than assuming, so there is one place that
     mapping lives. ]==]
function M:EnchantTimeLeft(button)
    if not button or type(GetWeaponEnchantInfo) ~= "function" then return nil end

    local index = nil

    for i = 1, table.getn(self.enchants or {}) do
        if self.enchants[i] == button then index = i end
    end

    if not index then return nil end

    local hands = self:EnchantHands()
    local hand = hands and hands[index]
    if not hand then return nil end

    local hasMain, mainExpiry, _, hasOff, offExpiry = GetWeaponEnchantInfo()

    local expiry
    if hand.hand == "main" and hasMain then expiry = mainExpiry end
    if hand.hand == "off" and hasOff then expiry = offExpiry end

    if type(expiry) ~= "number" or expiry <= 0 then return nil end

    --[[ Milliseconds, which is the one thing this call does differently from
         every other duration in the interface. ]]--
    return expiry / 1000
end

function M:ApplyEnchantCharges()
    local cfg = self:Config()

    if type(GetWeaponEnchantInfo) ~= "function" then return false end

    --[[ Read from what the client has drawn rather than from the button's
         name -- see `EnchantHands`. ]]--
    local hands = self:EnchantHands()

    for i = 1, 2 do
        local button = getglobal("TempEnchant" .. i)

        if button then
            local text = self:EnchantCount(button)
            local hand = hands[i]
            local charges = hand and hand.charges

            --[[ Zero is not a count. A weapon buff with no charge system
                 reports nothing or nought, and either way there is no number
                 worth drawing. ]]--
            if cfg.showEnchantCharges and charges and charges > 0 then
                --[[ Converted here rather than left as a number: what a font
                     string reports back should be what was asked for. ]]--
                text:SetText(tostring(charges))
                text:Show()
            else
                text:SetText("")
                text:Hide()
            end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- the flash a nearly-spent aura does
-- ---------------------------------------------------------------------------

--[==[ **Through the client's own four constants rather than by writing alpha.**

     The flash is `BuffFrame`'s: its `OnUpdate` runs a saw wave between
     `BUFF_MIN_ALPHA` and one, on a half cycle of `BUFF_FLASH_TIME_ON` then
     `BUFF_FLASH_TIME_OFF`, and every aura button under `BUFF_WARNING_TIME`
     seconds left takes that alpha every frame. Weapon buffs read the same
     value, which is why one switch covers all three rows.

     So the alpha is written sixty times a second by something that is not this
     module, and anything this module wrote there would be gone before it was
     drawn. The constants are the seam the client left, and they are the only
     thing here worth touching.

     **Off is said twice on purpose.** `BUFF_WARNING_TIME = 0` means no icon ever
     enters the flashing branch; `BUFF_MIN_ALPHA = 1` means the wave the branch
     would read is flat. Either alone is enough, and the reason for both is that
     the exact shape of that `OnUpdate` differs between builds -- a private
     server may have rewritten it -- and neither of these can make anything
     worse if it turns out to be the one that does nothing. ]==]
local CLIENT_FLASH_HALF = 0.75

--[==[ What the client had, read once and kept.

     Read once because the second read would be of our own numbers: everything
     below writes these globals, so a re-read after the first write would
     remember this module's answer as the client's and there would be nothing
     left to hand back. ]==]
function M:RememberClientFlash()
    if self.clientFlash then return self.clientFlash end

    self.clientFlash = {
        on = BUFF_FLASH_TIME_ON,
        off = BUFF_FLASH_TIME_OFF,
        minAlpha = BUFF_MIN_ALPHA,
        warning = BUFF_WARNING_TIME,
    }

    return self.clientFlash
end

--[[ **One pass, not a tick.** With the flash off the client stops writing alpha
     to these buttons at all, so whatever fade one was caught in is what it keeps
     -- an icon left at a third of its brightness, permanently, by the setting
     that was supposed to stop it doing that. ]]--
function M:ClearFlashAlpha()
    if not self.original then return false end

    for button in pairs(self.original) do
        if button and button.SetAlpha then button:SetAlpha(1) end
    end

    return true
end

function M:ApplyAuraFlash()
    local cfg = self:Config()
    local was = self:RememberClientFlash()

    if not cfg.flashLowAuras then
        BUFF_WARNING_TIME = 0
        BUFF_MIN_ALPHA = 1

        self:ClearFlashAlpha()
        return true
    end

    BUFF_WARNING_TIME = was.warning
    BUFF_MIN_ALPHA = was.minAlpha

    --[[ A multiplier divides the half cycle: faster is a shorter one. Guarded
         against nought because the slider stops at a half and a profile is a
         file somebody can edit -- and nought here is a division that never
         ends. ]]--
    local speed = tonumber(cfg.flashSpeed) or 1
    if speed <= 0 then speed = 1 end

    BUFF_FLASH_TIME_ON = (tonumber(was.on) or CLIENT_FLASH_HALF) / speed
    BUFF_FLASH_TIME_OFF = (tonumber(was.off) or CLIENT_FLASH_HALF) / speed

    return true
end

--[[ Restored to what was read, including to nothing: a build with no such
     global gets its nothing back rather than this module's idea of it. ]]--
function M:RestoreClientFlash()
    local was = self.clientFlash
    if not was then return false end

    BUFF_FLASH_TIME_ON = was.on
    BUFF_FLASH_TIME_OFF = was.off
    BUFF_MIN_ALPHA = was.minAlpha
    BUFF_WARNING_TIME = was.warning

    return true
end

function M:OnEvent()
    OB.SetDirty(self)
end

--[[ **The only pass that runs while the feature is hidden.**

     The draw loop calls `OB.HideFeature` instead of `OnDraw` for a hidden
     feature, so the un-tick of Show would never reach this module and the auras
     would sit wherever ECO last put them. `OB.Refresh(true)` styles every
     feature regardless, which makes this the hook that hands them back. ]]--
function M:OnStyle()
    --[[ The sizes are settings, so they are re-read on the pass a setting
         change runs rather than only when a string is built. ]]--
    self:SizeAllAuraText()

    self:ApplyLayout(true)
    self:ApplyEnchantCharges()
    self:ApplyAuraTimers()
    self:ApplyAuraFlash()
end

function M:OnDraw()
    self:ApplyLayout(false)
    self:ApplyEnchantCharges()
    self:ApplyAuraTimers()
end

--[==[ **Ten times a second, not sixty.**

     These timers count in whole seconds and minutes, so fifty-nine of every
     sixty passes would compute the same string and throw it away. A cast bar
     earns a per-frame pass because a moving rectangle is what it *is*; a number
     that changes once a second does not.

     Throttled here rather than by asking for a slower ticker, because the
     module shares one with everything else that ticks. ]==]
function M:OnUpdate(now)
    now = now or GetTime()

    if self.nextTimerRefresh and now < self.nextTimerRefresh then return end
    self.nextTimerRefresh = now + 0.10

    self:ApplyAuraTimers()
end
