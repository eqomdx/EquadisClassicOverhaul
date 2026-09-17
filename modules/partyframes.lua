--[[ Equadis' Classic Overhaul :: Party Frames v2

  A thin utility layer over Blizzard's own four party frames.

  DragonflightUI-Reforged moves only PartyMemberFrame1 and scales the four stock
  frames.  Blizzard's 1.12 PartyMemberFrame code already owns the resource bars,
  the four debuff buttons and their type-coloured borders, and a `Status` overlay
  for dispellable debuffs.  This version keeps those widgets instead of replacing
  or resizing them, and it is therefore designed to coexist with ECO Unit Frames.

  What it does *not* do is call the client's own party-debuff refresher: the
  1.12 build has no such function under any name the reference addons use, so
  the four stock buttons are filled from `UnitDebuff` here.  Those are the
  client's buttons throughout -- icon, border, stack count, tooltip and click.
]]--

local OB = EquadisClassicOverhaul
local function Say(msg) OB.Print(msg, "Party Frames") end

local M = OB.RegisterModule({
    id = "partyframes",
    name = "Party Frames",
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

    --[==[ **Its own texture and font, and no border.**

         These are Blizzard's party frames restyled, not frames of ours: the
         artwork around the bars is the client's and is fixed, so a border
         setting would be a control with nothing to draw on. The same reasoning,
         and the same list, as the unit frames.

         Party keeps its own values rather than sharing the unit frames'. A raid
         grid and a party row are the same idea at two sizes, not one set of
         settings. ]==]
    styled = { texture = true, font = true, fontSize = true, fontOutline = true },

    defaults = {
        scale = 1.00,

        --[[ **Class colour, because a party frame is read by who it is.**

             Green-for-everyone answers "are they hurt", which the length of the
             bar already said. What a healer is actually doing is finding the
             warrior, and colour is the fastest way anybody finds anything on a
             screen -- it is why the raid frames every guild uses are coloured
             this way and the client's own are not. ]]--
        classHealth = true,

        --[[ **Off, because it changes the shape of the frame.**

             The stock bar is a ten-pixel strip under a portrait, sized for a
             window nobody was expected to look at. A thicker one reads at a
             glance and is what the unit frames were given for the same reason --
             but it is a visible change to a frame somebody may have arranged
             their screen around, so it is asked for rather than assumed. ]]--
        --[==[ **Dark art, as the unit frames offer.** A tint over the same
             compact frame rather than a different layout -- see the unit frames
             for why those two travel together. ]==]
        darkArt = false,

        --[[ How far apart the four sit, on top of the art's own height. ]]--
        spacing = 6,

        showResource = true,

        --[==[ **The same six shapes the unit frames offer.**

             Asked for by name, and they are the unit frames' own list rather
             than a second one: "Current / Max (Percent)" has to mean the same
             thing on both pages or the setting is lying about one of them. The
             formatter is shared -- see `OB.BarText`.

             `maxpct` to start with, which is what the unit frames' health text
             defaults to, so a party frame reads like the target frame does
             without anybody setting it. ]==]
        healthText = "maxpct",
        powerText = "none",

        --[==[ **The level has its own size, and has to.**

             It was drawn through the module's font size like the name and the
             numbers, so raising those to read the health at a glance grew the
             level too -- and the level does not live in a bar, it lives in a
             small circle the art draws. Text sized for a twenty-pixel bar does
             not fit a badge, so the two cannot share a number.

             Ten because that is the size the badge was drawn for. ]==]
        levelSize = 10,

        --[[ Off, unlike the unit frames. A party frame's bar is a third of the
             width, so the thousand-to-ten-thousand band does not fit as
             comfortably -- but above ten thousand still shortens regardless,
             which is not a preference on any bar. ]]--
        shortNumbers = true,
        decimals = 1,

        maxDebuffs = 4,
        debuffMode = "all",
        highlightDispellable = true,
        position = nil,
    },

    options = {
        { "Size And Position", "__s_layout", "section", "layout" },
        { "Party Frame Scale", "scale", "slider", 70, 160, 5, 0.01 },
        { "Move Party Frames", "__a_move", "action",
          function() OB.modules.partyframes:SetDragMode(
              not OB.modules.partyframes:DragMode()) end,
          function()
              if OB.modules.partyframes:DragMode() then return "Done Moving" end
              return "Move Party Frames"
          end },
        { "Put Them Back", "__a_reset", "action",
          function() OB.modules.partyframes:ResetPosition() end },

        { "Appearance", "__s_look", "section", "look" },
        { "Class Colored Health", "classHealth", "boolean" },
        { "Dark Frame Art", "darkArt", "boolean" },
        { "Spacing", "spacing", "slider", 0, 40, 2 },

        { "Numbers", "__s_numbers", "section", "numbers" },
        { "Health Text", "healthText",
          OB.Enum(OB.unitTextKeys, OB.unitTextModes) },
        { "Resource Text", "powerText",
          OB.Enum(OB.unitTextKeys, OB.unitTextModes) },
        { "Level Text Size", "levelSize", "slider", 6, 16, 1 },
        { "Shorten Numbers Under 10k", "shortNumbers", "boolean" },
        { "Decimal Places", "decimals", "slider", 0, 2, 1,
          nil, nil, "!shortNumbers" },

        { "Resource", "__s_resource", "section", "resource" },
        { "Show Mana / Energy / Rage", "showResource", "boolean" },

        { "Debuffs And Dispels", "__s_debuffs", "section", "debuffs" },
        { "Debuffs Shown", "maxDebuffs", "slider", 0, 4, 1 },
        { "Which Debuffs", "debuffMode",
          OB.Enum({ "all", "dispellable" }, { "All", "Dispellable Only" }) },
        { "Highlight Dispells / Decurses", "highlightDispellable", "boolean" },
    },

    events = {
        "PLAYER_ENTERING_WORLD",
        "PARTY_MEMBERS_CHANGED",
        "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE",
        "UNIT_AURA", "UNIT_MANA", "UNIT_MAXMANA",
        "UNIT_ENERGY", "UNIT_RAGE", "UNIT_FOCUS", "UNIT_DISPLAYPOWER",
    },

    --[[ **This list was empty, and that is how the debuff pass shipped broken.**

         The first version drove `RefreshBuffs` and `SHOW_DISPELLABLE_DEBUFFS`,
         neither of which exists on 1.12. Both calls were behind a `type(...) ==
         "function"` guard, so nothing errored and nothing happened -- the
         settings were simply inert. Naming the two calls this module genuinely
         cannot work without is what turns that silence into a line in
         `/eq selftest`. ]]--
    requires = { "UnitDebuff", "UnitExists", "getglobal" },
})

local WHITE = "Interface\\Buttons\\WHITE8X8"

--[==[ **Frames of our own, because restyling Blizzard's is a fight.**

     This module used to take `PartyMemberFrame1..4` and re-colour what was in
     them. That works right up until another addon replaces the same frames --
     and DragonflightUI-Reforged does exactly that: it *hides* the stock health
     and mana bars and draws its own in their place. Everything this module set
     was therefore being set on hidden widgets, so the class colouring simply
     never appeared, and what was on screen was somebody else's bars against
     somebody else's art.

     There is no version of that argument this module wins. So it builds its own
     frames out of the artwork the unit frames already use, in the compact
     variant, and hides the client's -- the same thing the settings panel did
     when it stopped wearing the client's chrome.

     **The art and the geometry are one decision.** The compact art has its
     divider drawn where a twenty-pixel health bar ends; the full-size art has it
     at twenty-nine. Putting one layout inside the other draws a line through the
     middle of a bar, which is a bug this addon has already had once on the
     player frame. ]==]
local ART_W, ART_H = 232, 100

--[==[ **Mirrored, because the portrait is on the left.**

     The donor art is drawn with the portrait on the right and the bars beside
     it -- that is the target frame's layout, and the target's compact bars start
     at x=6 for exactly that reason. The player frame flips it, which is why its
     bars start at 106 and its portrait sits at 43.

     These frames use the player's arrangement, so they need the player's
     texcoord. Written the other way round first, the art faced one way and the
     numbers the other: bars over the portrait and running off the edge of a
     frame that ended before they did. ]==]
local ART_COORDS = { 1.0, 0.09375, 0, 0.78125 }

--[[ Where each piece sits inside the art, at its own scale. Taken from the
     compact player frame rather than invented: it is the same picture. ]]--
local PORTRAIT_X, PORTRAIT_Y = 43, -18
local PORTRAIT_SIZE = 58
local BAR_X = 106
local HEALTH_Y, HEALTH_H = -22, 20
local POWER_Y, POWER_H = -42, 10
local BAR_W = 119

--[[ **The centre of the level badge**, measured from the portrait's bottom-left
     corner -- which is where the art puts the circle.

     These are the two numbers to change if the number sits off its badge. The
     first pair put it low and left of centre, hanging off the ring rather than
     inside it: the offset is to the *centre* of the circle, and the circle is
     set in from the portrait's corner rather than sitting on it. ]]--
local LEVEL_X, LEVEL_Y = 11, 13

--[[ The crown, at the portrait's top-left -- the opposite corner from the level
     badge, and where the client puts it on its own party frames. ]]--
local LEADER_X, LEADER_Y = 8, -6
local LEADER_SIZE = 16

function M:FrameArtPath()
    local dark = self:Config().darkArt and "DarkCompactUI" or "compactUI"
    return OB.mediaPath .. "textures\\Textures\\" .. dark .. "-TargetingFrame"
end

--[==[ One member's frame, built once and kept. Named, so edit mode and anything
     else that walks frames by name can find them. ]==]
function M:MemberFrame(i)
    self.frames = self.frames or {}
    if self.frames[i] then return self.frames[i] end
    if not CreateFrame then return nil end

    local base = "EquadisClassicOverhaulParty" .. i
    local f = CreateFrame("Button", base, UIParent)

    f:SetWidth(ART_W)
    f:SetHeight(ART_H)
    f:Hide()

    --[==[ **The border art needs a frame of its own, above the bars.**

         A texture belongs to a draw layer *within* its frame, and every child
         frame draws above every one of its parent's layers however high that
         layer is. The bars are child frames, so while the art was a texture on
         the frame itself there was no value of `ARTWORK` or `OVERLAY` that could
         put the border in front of them -- reported as the frame rendering
         underneath the bars, which is exactly what it was doing.

         So the stack is built out of frames rather than layers: the portrait on
         the frame itself, the bars above it, the art above those, and the text
         and debuffs above the art. Three levels apart rather than one, to leave
         room for anything that later needs to sit between two of them. ]==]
    f.artFrame = CreateFrame("Frame", nil, f)
    f.artFrame:SetAllPoints(f)
    f.artFrame:SetFrameLevel((f:GetFrameLevel() or 1) + 3)

    f.art = f.artFrame:CreateTexture(nil, "ARTWORK")
    f.art:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.art:SetWidth(ART_W)
    f.art:SetHeight(ART_H)
    f.art:SetTexCoord(ART_COORDS[1], ART_COORDS[2], ART_COORDS[3], ART_COORDS[4])

    --[[ Behind the art, so the frame's own border draws over the edge of the
         portrait exactly as it does on the player frame. ]]--
    f.portrait = f:CreateTexture(nil, "BACKGROUND")
    f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
    f.portrait:SetWidth(PORTRAIT_SIZE)
    f.portrait:SetHeight(PORTRAIT_SIZE)

    f.health = CreateFrame("StatusBar", nil, f)
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", BAR_X, HEALTH_Y)
    f.health:SetWidth(BAR_W)
    f.health:SetHeight(HEALTH_H)
    f.health:SetMinMaxValues(0, 1)

    f.power = CreateFrame("StatusBar", nil, f)
    f.power:SetPoint("TOPLEFT", f, "TOPLEFT", BAR_X, POWER_Y)
    f.power:SetWidth(BAR_W)
    f.power:SetHeight(POWER_H)
    f.power:SetMinMaxValues(0, 1)

    --[[ Above the bars rather than on them: a compact frame has no room for a
         name inside a twenty-pixel bar without it fighting the numbers. ]]--
    --[==[ `nameText`, not `name`. A frame's own name lives on it, and assigning
         a font string to `f.name` overwrites the thing `GetName` answers with --
         which then hands a table to everything that builds a child's name by
         concatenation, the debuff painter included. ]==]
    --[[ Above the art, which is now above the bars -- a name behind the border
         is the same bug one layer further on. Anchored to the bars as before;
         only the parent changed. ]]--
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel((f:GetFrameLevel() or 1) + 6)

    f.nameText = OB.NewText(f.textFrame, "OVERLAY", "GameFontNormalSmall")
    f.nameText:SetPoint("BOTTOMLEFT", f.health, "TOPLEFT", 0, 1)
    f.nameText:SetJustifyH("LEFT")

    f.healthText = OB.NewText(f.textFrame, "OVERLAY", "GameFontNormalSmall")
    f.healthText:SetPoint("CENTER", f.health, "CENTER", 0, 0)

    --[==[ **The party leader's crown, which went with the client's frames.**

         Blizzard draws it as `PartyMemberFrame<n>Leader`, and this module hides
         those frames and draws its own -- so replacing them quietly dropped the
         crown, which is the reported "party frames no longer has the party
         leader crown". Nothing broke; a thing that existed stopped being drawn
         because nobody carried it across.

         The client's own art, so it is the crown people already recognise. ]==]
    f.leader = f.textFrame:CreateTexture(nil, "OVERLAY")
    f.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    f.leader:SetWidth(LEADER_SIZE)
    f.leader:SetHeight(LEADER_SIZE)
    f.leader:SetPoint("CENTER", f.portrait, "TOPLEFT", LEADER_X, LEADER_Y)
    f.leader:Hide()

    --[[ The resource strip's own number, which there was no way to ask for. ]]--
    f.powerText = OB.NewText(f.textFrame, "OVERLAY", "GameFontNormalSmall")
    f.powerText:SetPoint("CENTER", f.power, "CENTER", 0, 0)

    --[==[ **The level, in the badge the art draws for it.**

         The compact art puts a small circle at the bottom-left of the portrait,
         which is where every frame in the client that has a level puts one.
         Nothing was drawn into it, so it read as a hole in the art rather than
         as a frame that does not show levels.

         Parented to the art frame rather than to the portrait, so it is not
         covered by the border the way the portrait's own edge is. ]==]
    f.levelText = OB.NewText(f.textFrame, "OVERLAY", "GameFontNormalSmall")
    f.levelText:SetPoint("CENTER", f.portrait, "BOTTOMLEFT", LEVEL_X, LEVEL_Y)
    f.levelText:SetJustifyH("CENTER")

--[==[ **A party frame is a unit, and everything you can do to a unit you can
         do here.**

         Clicking targeted, and that was the whole of it -- which made these a
         readout rather than a party frame. The client's own answer four
         gestures, and asked for in exactly those terms: whisper, promote,
         uninvite, and an item dropped on somebody to offer them a trade.

         `PartyMemberFrame_OnClick` is what is being matched, decision for
         decision, and `PartyMemberFrame_OnReceiveDrag` beside it. Nothing here
         is invented. The one difference is that the menu is ours, for the
         reason `UnitMenu` gives. ]==]
    f.unit = "party" .. i
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:EnableMouse(true)

    f:SetScript("OnClick", function()
        EquadisClassicOverhaul.modules.partyframes:UnitClick(this, arg1)
    end)

    --[[ A right-drag from here turns the camera rather than being swallowed;
         a right-*click* still opens the menu above. See
         `OB.AttachCameraDrag`. ]]--
    OB.AttachCameraDrag(f)

    --[==[ **An item let go over the frame offers it to them.**

         `OnReceiveDrag` fires on any mouse-enabled frame when something is
         dropped on it. It needs no `RegisterForDrag` -- that is for *starting*
         a drag, and starting one here would mean dragging the party member. ]==]
    f:SetScript("OnReceiveDrag", function()
        EquadisClassicOverhaul.modules.partyframes:UnitDrop(this)
    end)

    --[==[ Named the way the debuff painter looks them up -- `<frame>Debuff<n>`
         with an `Icon`, a `Border` and a `Count`. That painter was written
         against Blizzard's naming and needs no change to drive these, which is
         the whole reason to match it. ]==]
    for d = 1, 4 do
        local name = base .. "Debuff" .. d
        local button = CreateFrame("Button", name, f)

        --[[ Above the art for the same reason the text is. ]]--
        button:SetFrameLevel((f:GetFrameLevel() or 1) + 6)

        button:SetWidth(16)
        button:SetHeight(16)
        button:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", (d - 1) * 18, -14)
        button:Hide()

        local icon = button:CreateTexture(name .. "Icon", "ARTWORK")
        icon:SetAllPoints(button)

        local border = button:CreateTexture(name .. "Border", "OVERLAY")
        border:SetAllPoints(button)

        --[==[ Globally named, because the painter finds it the way the client
             names its own -- `<button>Count` through `getglobal`. `OB.NewText`
             creates an anonymous string, which is right nearly everywhere and
             wrong for exactly the widgets something else looks up by name. ]==]
        local count = button:CreateFontString(name .. "Count", "OVERLAY",
                "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

        table.insert(OB.texts, count)
    end

    --[[ The dispel outline the existing pass shows and hides by name. ]]--
    local status = f.textFrame:CreateTexture(base .. "Status", "OVERLAY")
    status:SetAllPoints(f)
    status:Hide()

    self.frames[i] = f
    return f
end

--[==[ **What one member's frame says right now.** ]==]
-- ---------------------------------------------------------------------------
-- interacting with a member
-- ---------------------------------------------------------------------------

--[==[ **The menu is ours, because the client's belongs to a frame we hide.**

     `PartyMemberFrame1DropDown` still exists while these frames are drawn --
     hiding a frame does not unmake its children -- but it is initialised
     against `PartyMemberFrame1`'s own id and anchored to it. Borrowing it would
     put the menu wherever the hidden frame is sitting, which is somewhere the
     reader is not looking.

     **The unit is closed over rather than read off `this`.** `ToggleDropDownMenu`
     calls the initialiser with `this` left as whatever the caller had, which is
     a detail that has moved between clients and is not worth depending on when
     a closure states exactly what is meant. One dropdown per frame, so a
     closure per frame costs four of them.

     Built on first use rather than with the frame: a party frame that is never
     right-clicked never needs one, and `UIDropDownMenuTemplate` is not free. ]==]
--[==[ **These four moved to `layout.lua` and are kept here as their names.**

     The raid frames want the same four gestures and were asked for them, so the
     behaviour is shared rather than copied -- see `OB.UnitGestureClick`. What
     stays here is the party's answer to "which menu": "PARTY", and the client's
     own 47/15 offsets, so it opens where somebody who has used the default
     frames expects it.

     Kept as methods rather than deleted because they are the module's public
     shape: the suite calls `party:UnitClick(...)` directly, and a call site is
     part of the interface whether or not it is a person typing it. ]==]
function M:UnitMenu(frame)
    return OB.UnitMenuFor(frame, "PARTY")
end

function M:OpenUnitMenu(frame)
    return OB.OpenUnitMenuFor(frame, "PARTY", 47, 15)
end

function M:UnitDrop(frame)
    return OB.UnitDropOn(frame)
end

function M:UnitClick(frame, button)
    return OB.UnitGestureClick(frame, button, "PARTY", 47, 15)
end

function M:StyleMember(i)
    local f = self:MemberFrame(i)
    if not f then return false end

    local cfg = self:Config()
    local unit = "party" .. i

    if type(UnitExists) ~= "function" or not UnitExists(unit) then
        f:Hide()
        return false
    end

    f:Show()
    f.art:SetTexture(self:FrameArtPath())

    if type(SetPortraitTexture) == "function" then
        SetPortraitTexture(f.portrait, unit)
    end

    f.nameText:SetText(UnitName(unit) or "")

    local texture = OB.TexturePath and OB.TexturePath("partyframes") or nil
    if texture then
        f.health:SetStatusBarTexture(texture)
        f.power:SetStatusBarTexture(texture)
    end

    --[==[ **Class colour, and only for a player.** Everything has a class as far
         as the server is concerned -- a party pet is a warrior -- so anything
         that is not a player keeps green. ]==]
    local health, healthMax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 1
    if healthMax <= 0 then healthMax = 1 end

    f.health:SetMinMaxValues(0, healthMax)
    f.health:SetValue(health)

    local coloured = false

    --[[ Asked of OB.IsPlayerUnit rather than UnitIsPlayer directly: the latter
         says no about a group member who is merely out of range, which turned
         every distant party member's bar green. ]]--
    if cfg.classHealth and OB.IsPlayerUnit(unit) then
        local class = OB.UnitClassToken(unit)

        if class and OB.ClassColor then
            local r, g, b = OB.ClassColor(class)
            if r then
                f.health:SetStatusBarColor(r, g, b)
                coloured = true
            end
        end
    end

    if not coloured then f.health:SetStatusBarColor(0, 1, 0) end

    --[==[ Dead, ghost and offline are read before the numbers, because all three
         leave a bar that is technically full of nothing.

         **Offline first, and a ghost named as one** -- the same order and the
         same three states the raid frames settled on, because they are the same
         three questions asked of the same people.

         A disconnected player also reads as dead on some builds, so asking
         `UnitIsDeadOrGhost` first answers "Dead" for somebody whose client is
         simply not there; "they have gone" is the truer of the two, since nobody
         is resurrecting a client that is not running.

         And a **ghost is not a corpse**. This said "Dead" for both, which
         promises a resurrection that cannot be cast: a ghost has released and is
         running back. Reported against the raid frames; it was wrong here
         too. ]==]
    if type(UnitIsConnected) == "function" and not UnitIsConnected(unit) then
        f.healthText:SetText("Offline")
    elseif type(UnitIsGhost) == "function" and UnitIsGhost(unit) then
        f.healthText:SetText("Ghost")
    elseif type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost(unit) then
        f.healthText:SetText("Dead")
    else
        --[[ **Through the shared formatter**, rather than the bare current
             value this drew before. Dead and offline still win outright: a
             number is what the bar is for, and neither of those is one. ]]--
        f.healthText:SetText(OB.BarText(health, healthMax, cfg.healthText,
                cfg.shortNumbers, cfg.decimals))
    end

    if cfg.showResource then
        local power, powerMax = UnitMana(unit) or 0, UnitManaMax(unit) or 1
        if powerMax <= 0 then powerMax = 1 end

        f.power:SetMinMaxValues(0, powerMax)
        f.power:SetValue(power)

        --[[ **Coloured by the resource, which it never was.**

             The bar was created, filled and shown, and no colour was ever set
             on it -- so it drew as the plain white texture and every party
             member appeared to have the same grey resource. Blizzard colours
             this by what the resource *is* rather than by class, and on a frame
             this small that is the whole of its value: a druid's bar turning
             yellow is how you know they shifted. ]]--
        f.power:SetStatusBarColor(OB.PowerColor(unit))

        --[[ The resource gets the same six shapes, defaulting to none: a strip
             ten pixels tall has room for a colour and not for a number, so this
             is worth offering and not worth assuming. ]]--
        f.powerText:SetText(OB.BarText(power, powerMax, cfg.powerText,
                cfg.shortNumbers, cfg.decimals))

        f.power:Show()
    else
        f.power:Hide()
    end

    --[==[ **The level, in the badge the art already draws.**

         The frame art has a small circle at the corner of the portrait -- the
         client puts a level in it on every frame that has one -- and this drew
         nothing there, so it read as an empty hole rather than as a frame
         without a level.

         `??` for a unit too far above you to read, which is what the client
         shows and what the number is for: a level you cannot see is a fact
         worth having. ]==]
    local level = type(UnitLevel) == "function" and UnitLevel(unit) or nil

    if level and level > 0 then
        --[[ As a string, because the other branch writes one and a font string
             that sometimes holds a number is a type nobody expects to compare
             against. ]]--
        f.levelText:SetText(tostring(level))
    else
        f.levelText:SetText("??")
    end

    --[==[ **Who is leading, by the best question the client will answer.**

         `UnitIsPartyLeader` is the direct one and not every 1.12 build has it,
         so `GetPartyLeaderIndex` is the fallback -- it answers with the party
         index of the leader, and zero when that is you or there is no party.
         Trusting only the first would leave the crown off entirely on a client
         that lacks it. ]==]
    local leader = false

    if type(UnitIsPartyLeader) == "function" then
        leader = UnitIsPartyLeader(unit) and true or false
    elseif type(GetPartyLeaderIndex) == "function" then
        leader = (GetPartyLeaderIndex() == i) and true or false
    end

    if leader then f.leader:Show() else f.leader:Hide() end

    OB.ApplyFont(f.nameText, nil, "partyframes")
    OB.ApplyFont(f.healthText, nil, "partyframes")
    OB.ApplyFont(f.powerText, nil, "partyframes")
    --[[ Its own size, not the module's: the badge is a circle the art draws and
         the bar text is not, so one number cannot serve both. ]]--
    OB.ApplyFont(f.levelText, cfg.levelSize, "partyframes")

    self:PaintDebuffs(f, unit, cfg.maxDebuffs or 4,
            cfg.debuffMode == "dispellable")
    self:ApplyDispelStatus(f, unit)

    return true
end

--[==[ Stacked under the mover, which is what the whole group is dragged by. The
     spacing is the art's own height plus a gap, so the frames sit apart by the
     same amount whatever scale they are drawn at. ]==]
function M:PlaceMembers()
    local cfg = self:Config()
    local scale = tonumber(cfg.scale) or 1
    if scale <= 0 then scale = 1 end

    local gap = (ART_H * 0.62) + (tonumber(cfg.spacing) or 6)

    for i = 1, 4 do
        local f = self:MemberFrame(i)

        if f then
            f:SetScale(scale)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -((i - 1) * gap))
        end
    end

    return true
end

function M:Config()
    return OB.profile.modules.partyframes
end

--[[ Party Frames owns Blizzard's compact party widgets only when those widgets
     should actually exist. In a raid they are not a second raid display, and
     when Raid Frames is replacing a normal party they are deliberately being
     replaced. Yield in both cases instead of restyling a hidden/duplicate set
     behind the raid-style grid. ]]--
function M:YieldToRaidLayout()
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end

    local raid = OB.modules and OB.modules.raidframes
    if not raid or not OB.ModuleEnabled("raidframes") or not OB.ModuleShown("raidframes") then
        return false
    end

    local cfg = raid.Config and raid:Config()
    if not cfg or not cfg.forParty then return false end

    local party = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    return party > 0
end

function M:SuppressStockParty(hide)
    local raid = OB.modules and OB.modules.raidframes
    if raid and raid.HideBlizzardParty then
        raid:HideBlizzardParty(hide and true or false)
        return true
    end

    -- Fallback for unusual load orders: one pass is still better than drawing
    -- duplicate party frames. Raid Frames normally supplies the persistent
    -- OnShow suppression used above.
    if hide then
        for i = 1, 4 do
            local frame = getglobal("PartyMemberFrame" .. i)
            if frame then frame:Hide() end
        end
    end
    return true
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

function M:EnsureMover()
    if self.frame then return self.frame end

    local mover = CreateFrame("Frame", "EquadisOverhaulPartyMoverV2", UIParent)
    mover:SetWidth(128)
    mover:SetHeight(53)
    mover:SetFrameStrata("LOW")
    mover:EnableMouse(false)

    mover.hint = mover:CreateTexture(nil, "BACKGROUND")
    mover.hint:SetTexture(WHITE)
    mover.hint:SetAllPoints(mover)
    mover.hint:SetVertexColor(0.10, 0.60, 1.00, 0.20)
    mover.hint:Hide()

    self.frame = mover
    return mover
end

function M:Capture()
    if self.original then return end
    self.original = { frames = {}, debuffs = {} }

    for i = 1, 4 do
        local frame = getglobal("PartyMemberFrame" .. i)
        local mana = getglobal("PartyMemberFrame" .. i .. "ManaBar")

        if frame then
            local health = getglobal("PartyMemberFrame" .. i .. "HealthBar")

            --[[ The bar's own height and the power bar's anchor, so a thicker
                 bar can be made thin again. Captured rather than assumed:
                 Blizzard's numbers differ between builds, and a restore that
                 writes a constant is a restore that is wrong on the build that
                 needed it. ]]--
            self.original.frames[i] = {
                points = capturePoints(frame),
                scale = frame.GetScale and frame:GetScale() or 1,
                manaAlpha = mana and mana.GetAlpha and mana:GetAlpha() or 1,
                healthHeight = health and health.GetHeight and health:GetHeight() or nil,
                healthPoints = health and capturePoints(health) or nil,
                manaPoints = mana and capturePoints(mana) or nil,
            }
        end

        self.original.debuffs[i] = {}
        for d = 1, 4 do
            local button = getglobal("PartyMemberFrame" .. i .. "Debuff" .. d)
            if button then
                self.original.debuffs[i][d] = {
                    points = capturePoints(button),
                }
            end
        end
    end
end

-- The mover begins exactly where Blizzard put PartyMemberFrame1, so merely
-- enabling the module does not relocate the party.  Only a saved drag changes it.
function M:PlaceMover()
    local mover = self:EnsureMover()
    if self.dragging then return end

    mover:ClearAllPoints()

    local saved = self:Config().position
    if saved then
        mover:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
        return
    end

    local first = self.original and self.original.frames and self.original.frames[1]
    local p = first and first.points and first.points[1]

    if p then
        mover:SetPoint(p.point, p.relative, p.relativePoint, p.x, p.y)
    else
        mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -128)
    end
end

function M:AttachFirstFrame()
    local frame = getglobal("PartyMemberFrame1")
    local mover = self:EnsureMover()
    if not frame then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", mover, "TOPLEFT", 0, 0)
end

function M:StorePosition()
    local mover = self:EnsureMover()
    if not mover:GetLeft() then return end

    self:Config().position = {
        x = OB.Round((mover:GetLeft() + mover:GetWidth() / 2) - GetScreenWidth() / 2),
        y = OB.Round((mover:GetBottom() + mover:GetHeight() / 2) - GetScreenHeight() / 2),
    }
end

function M:DragMode()
    return self.dragging and true or false
end

function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("partyframes") then
        Say("switch Party Frames on first.")
        return
    end

    local mover = self:EnsureMover()
    mover:Show()
    self.dragging = on and true or nil

    mover:EnableMouse(self.dragging and true or false)
    mover:SetMovable(self.dragging and true or false)

    if self.dragging then
        mover:RegisterForDrag("LeftButton")
        mover.hint:Show()

        --[[ Named for edit mode's outline. The mover is a handle standing in
             for four frames, so what it is has to be said rather than looked
             at -- solo there are no party frames under it at all. ]]--
        OB.MarkMovable(mover, "Party Frames")
        mover:SetScript("OnDragStart", function() this:StartMoving() end)
        mover:SetScript("OnDragStop", function()
            this:StopMovingOrSizing()
            EquadisClassicOverhaul.modules.partyframes:StorePosition()
        end)
    else
        mover.hint:Hide()
        mover:SetScript("OnDragStart", nil)
        mover:SetScript("OnDragStop", nil)
    end

    Say(self.dragging and "move mode on." or "move mode off.")
end

function M:ResetPosition()
    self:Config().position = nil
    self.dragging = nil
    self:PlaceMover()
    self:AttachFirstFrame()
    Say("party frames returned to Blizzard's starting position.")
end

--[[ **Paint the four stock party debuff buttons from `UnitDebuff` directly.**

     This asked `RefreshBuffs` to do it and set `SHOW_DISPELLABLE_DEBUFFS`
     around the call. Neither exists on a 1.12 client -- nothing in
     DragonflightUI-Reforged, VCB, ShaguTweaks or ShaguPlates names either -- so
     the guard at the top took every call, `Which Debuffs` did nothing, and
     `Debuffs Shown` hid buttons that never came back.

     `UnitDebuff` and `DebuffTypeColor` are the pair ShaguTweaks paints target
     debuffs with, and the buttons are the client's own
     `PartyMemberFrame<i>Debuff<d>` with their `Icon`, `Border` and `Count`
     children. Driving those means the icons, tooltips and click behaviour stay
     Blizzard's; only which aura lands in which slot is ours. ]]--
function M:PaintDebuffs(frame, unit, maxShown, dispellableOnly)
    if type(UnitDebuff) ~= "function" then return false end

    local slot = 0

    for i = 1, 16 do
        if slot >= maxShown then break end

        --[[ The third argument asks the client for auras this character can
             remove. Asked for only on the filtered path, so the unfiltered one
             cannot be narrowed by a class toolkit the client disagrees with. ]]--
        local texture, count, dtype
        if dispellableOnly then
            texture, count, dtype = UnitDebuff(unit, i, 1)
        else
            texture, count, dtype = UnitDebuff(unit, i)
        end

        if not texture then break end

        slot = slot + 1
        local name = frame:GetName() .. "Debuff" .. slot
        local button = getglobal(name)
        local icon = getglobal(name .. "Icon")
        local border = getglobal(name .. "Border")
        local stacks = getglobal(name .. "Count")

        if button then
            if icon then icon:SetTexture(texture) end

            if border then
                local color = DebuffTypeColor
                        and (DebuffTypeColor[dtype or "none"] or DebuffTypeColor["none"])
                if color then border:SetVertexColor(color.r, color.g, color.b) end
            end

            if stacks then
                if count and count > 1 then
                    stacks:SetText(count)
                    stacks:Show()
                else
                    stacks:Hide()
                end
            end

            button:SetID(i)
            button:Show()
        end
    end

    -- Everything past the last aura found, or past the user's cap, is empty.
    for d = slot + 1, 4 do
        local button = getglobal(frame:GetName() .. "Debuff" .. d)
        if button then button:Hide() end
    end

    return true
end

function M:DispellableType(unit)
    if type(UnitDebuff) ~= "function" then return nil end

    -- In 1.12 the third UnitDebuff argument asks the client for a debuff the
    -- player can remove.  This is preferable to a hard-coded class/spell table,
    -- especially on Turtle WoW where class toolkits can differ from stock.
    for i = 1, 4 do
        local texture, count, dtype = UnitDebuff(unit, i, 1)
        if texture then return dtype or "none" end
    end
    return nil
end

function M:ApplyDispelStatus(frame, unit)
    local cfg = self:Config()
    local status = frame and getglobal(frame:GetName() .. "Status")
    if not frame or not status then return end

    if not cfg.highlightDispellable then
        frame.hasDispellable = nil
        status:Hide()
        return
    end

    local dtype = self:DispellableType(unit)
    if not dtype then
        frame.hasDispellable = nil
        status:Hide()
        return
    end

    local color = DebuffTypeColor and DebuffTypeColor[dtype]
    if not color and DebuffTypeColor then color = DebuffTypeColor["none"] end
    if color then status:SetVertexColor(color.r, color.g, color.b) end

    -- PartyMemberFrame_OnUpdate already knows how to pulse/show this texture.
    frame.hasDispellable = 1
    frame.debuffCountdown = 30
    status:Show()
end


function M:Apply()
    if not OB.ModuleEnabled("partyframes") then return end
    if not OB.ModuleShown("partyframes") then return end

    self:Capture()

    -- Never keep a second set of party frames underneath raid-style frames.
    -- This also covers being in an actual raid, where the left-side Blizzard
    -- party frames in the screenshot were surviving roster refreshes.
    if self:YieldToRaidLayout() then
        if not self.yielding then self:Restore() end
        self.yielding = true
        self:SuppressStockParty(true)

        --[==[ **And this module's own frames go too.**

             `Restore` puts *Blizzard's* party frames back to how they were
             found; it has nothing to say about the four this module draws,
             because in every other case they are the ones that should be on
             screen. Yielding is the one case where they are not, and nothing
             hid them -- so turning Raid Frames on for a party added the grid
             and left the party frames sitting beside it. Reported as exactly
             that: it is not hiding the party frame, only adding a raid one.

             The container as well as the four, or an empty backdrop stays
             where the frames were. ]==]
        self:HideOwnFrames()
        return
    end

    self.yielding = nil

    --[==[ **The client's party frames stay hidden, always.**

         They used to be shown and restyled. That is a fight with any addon that
         replaces them -- and DragonflightUI-Reforged replaces them by hiding the
         stock bars and drawing its own, so everything this module set was being
         set on widgets nobody could see.

         The frames are ours now and the client's are simply not on screen.
         Nothing left to disagree with. ]==]
    self:SuppressStockParty(true)
    self:PlaceMover()
    self.frame:Show()

    self:PlaceMembers()
    for i = 1, 4 do self:StyleMember(i) end
end

--[[ The frames this module draws, put away. Separate from `Restore`, which is
     about giving the client's frames back rather than about hiding ours. ]]--
function M:HideOwnFrames()
    if self.frame and self.frame.Hide then self.frame:Hide() end

    for i = 1, table.getn(self.frames or {}) do
        local f = self.frames[i]
        if f and f.Hide then f:Hide() end
    end

    return true
end

function M:Restore()
    self.dragging = nil

    if self.frame then
        self.frame.hint:Hide()
        self.frame:EnableMouse(false)
    end

    if not self.original then return end

    for i = 1, 4 do
        local frame = getglobal("PartyMemberFrame" .. i)
        local mana = getglobal("PartyMemberFrame" .. i .. "ManaBar")
        local saved = self.original.frames[i]

        if frame and saved then
            frame:SetScale(saved.scale or 1)
            restorePoints(frame, saved.points)
            frame.hasDispellable = nil
            frame.debuffCountdown = nil
            local status = getglobal("PartyMemberFrame" .. i .. "Status")
            if status then status:Hide() end
        end

        if mana and saved and mana.SetAlpha then
            mana:SetAlpha(saved.manaAlpha or 1)
        end

        --[[ The bars go back to the client's own height, anchor and colour.
             Anything left painted is this module still being on screen after it
             has been switched off. ]]--
        local health = getglobal("PartyMemberFrame" .. i .. "HealthBar")

        if health and saved then
            if saved.healthHeight then health:SetHeight(saved.healthHeight) end
            if saved.healthPoints then restorePoints(health, saved.healthPoints) end

            health.lockColor = nil
            health:SetStatusBarColor(0, 1, 0)
        end

        if mana and saved and saved.manaPoints then
            restorePoints(mana, saved.manaPoints)
        end

        for d = 1, 4 do
            local button = getglobal("PartyMemberFrame" .. i .. "Debuff" .. d)
            local db = self.original.debuffs[i] and self.original.debuffs[i][d]
            if button and db then
                restorePoints(button, db.points)
            end
        end

        --[[ Repaint unfiltered and uncapped, so what is left behind is the four
             debuffs the client would have shown on its own. ]]--
        if frame and UnitExists("party" .. i) then
            self:PaintDebuffs(frame, "party" .. i, 4, false)
        end
    end

    if self.frame then self.frame:Hide() end
end

function M:OnBind()
    self:EnsureMover()
    self:Capture()
    self:Apply()
end

function M:OnUnbind()
    self.yielding = nil
    self:Restore()

    -- If Raid Frames still owns the replacement, leave Blizzard's party frames
    -- suppressed; otherwise hand visibility back. In a raid, Raid Frames will
    -- keep them down on its own event path.
    local raid = OB.modules and OB.modules.raidframes
    local replacement = raid and OB.ModuleEnabled("raidframes")
            and OB.ModuleShown("raidframes") and raid.Config
            and raid:Config().forParty
    local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
    if raid and raid.HideBlizzardParty then
        raid:HideBlizzardParty((inRaid or replacement) and true or false)
    end
end

function M:OnEvent()
    -- Ignore unrelated unit events.  Party membership/world events have no arg1
    -- and still need a full pass.
    if type(arg1) == "string" and string.sub(arg1, 1, 5) ~= "party" then
        return
    end
    OB.SetDirty(self)
end

function M:OnStyle()
    self:Apply()
end

function M:OnDraw()
    self:Apply()
end
