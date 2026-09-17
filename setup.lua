--[[ Equadis' Classic Overhaul :: setup

  **The first thing a new character sees, instead of four hundred settings.**

  The options panel is complete and that is exactly the problem on day one:
  twenty-four subsystems, sixty-odd tabs, and no order to go through them in.
  Somebody who has just installed this does not have an opinion about health
  text position yet. They have one question -- "what does this do to my game"
  -- and a panel is the wrong shape to answer it.

  So: a handful of screens, one decision each, a sensible answer already
  chosen, and a picture of what the decision means. Pressing Next through the
  whole thing without reading gives a good interface, which is the bar this has
  to clear -- a wizard you must read is a panel with fewer columns.

  **Drawn examples, live to the look.** Each step draws its own small picture
  out of the same media the setting uses -- the bar texture you are choosing,
  drawn as bars; the font you are choosing, drawn as text -- and every picture
  redraws when either changes, wherever you are in the walkthrough. The look
  step comes last, so somebody who goes back to change the texture sees the
  change on the picture they went back for.

  What it does *not* do is drive a real nameplate or a real unit frame against a
  fake unit. That is worth doing and it is a different piece of work -- the
  modules render against the client's frames and a live preview means persuading
  them to render against something else. A picture that is honest about being a
  picture beats a preview that lies.

  **It writes settings as it goes, rather than at the end.** There is no
  "apply" and no basket of pending choices: each screen changes the thing it is
  about, immediately, so Back is a real answer and closing halfway leaves you
  with what you chose rather than nothing.
]]--

local OB = EquadisClassicOverhaul

local function Say(msg) OB.Print(msg, "Setup") end

--[==[ **Sized for the picture, because the picture is the point.**

     This was 520 by 440 with a 120 pixel pane, which was enough for one status
     bar and a caption. Now that every module draws itself there is a row of
     twelve action buttons, a raid grid and a bag to fit, and none of those say
     anything at a size a screenshot would be shrunk to.

     The pane takes most of the window and the controls under it are two or
     three rows. That is the right proportion for a page whose whole argument is
     "here is what this looks like, do you want it". ]==]
local WIDTH, HEIGHT = 760, 600
local PANE_H = 280

-- ---------------------------------------------------------------------------
-- the steps
-- ---------------------------------------------------------------------------

--[==[ **A list, so a step is a table entry rather than a new screen.**

     Each step answers `title`, `body`, and optionally `example` -- which is
     handed the preview pane and draws into it -- and `controls`, which is
     handed the body area and builds whatever that step asks with.

     Order here is the order on screen. Nothing else knows how many there
     are. ]==]
OB.setupSteps = {}

--[[ The three that are not a module, kept by name so `BuildSetupSteps` can put
     the generated ones between them. ]]--
OB.setupFixedSteps = {}

local function step(def)
    OB.setupFixedSteps[def.id] = def
    table.insert(OB.setupSteps, def)
end

-- ---------------------------------------------------------------------------
-- small builders the steps share
-- ---------------------------------------------------------------------------

--[[ A row of checkboxes bound to a getter and a setter, laid out down the
     page. Returns the next free y so a step can stack more under it. ]]--
local function checkRow(parent, y, label, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetWidth(24)
    check:SetHeight(24)
    check:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -y)
    check:SetChecked(get() and true or false)

    local text = OB.NewText(check, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetText(label)

    check:SetScript("OnClick", function()
        set(this:GetChecked() and true or false)
    end)

    return y + 28
end

--[==[ **A cycler rather than a dropdown.**

     A dropdown here would be the panel's control on the wizard's page, and the
     panel is what this exists to postpone. Left and right through a short list,
     with the example redrawing as it moves, is the whole of what choosing a
     texture is -- and it makes the picture the thing you are steering rather
     than a consequence of a menu you closed. ]==]
local function cycler(parent, y, label, list, get, set, onChange)
    local caption = OB.NewText(parent, "OVERLAY", "GameFontNormal")
    caption:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -y)
    caption:SetText(label)

    local value = OB.NewText(parent, "OVERLAY", "GameFontHighlight")
    value:SetPoint("TOPLEFT", parent, "TOPLEFT", 150, -y)

    local function show()
        local i = get()
        value:SetText(tostring(list[i] or i))
    end

    local function move(by)
        local count = table.getn(list)
        if count < 1 then return end

        local i = (get() or 1) + by
        if i < 1 then i = count end
        if i > count then i = 1 end

        set(i)
        show()
        if onChange then onChange() end
    end

    local back = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    back:SetWidth(24)
    back:SetHeight(20)
    back:SetPoint("TOPLEFT", parent, "TOPLEFT", 118, -y + 4)
    back:SetText("<")
    back:SetScript("OnClick", function() move(-1) end)
    if OB.SkinButton then OB.SkinButton(back) end

    local next = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    next:SetWidth(24)
    next:SetHeight(20)
    next:SetPoint("TOPLEFT", parent, "TOPLEFT", 300, -y + 4)
    next:SetText(">")
    next:SetScript("OnClick", function() move(1) end)
    if OB.SkinButton then OB.SkinButton(next) end

    show()
    return y + 30
end

-- ---------------------------------------------------------------------------
-- 1. what this is
-- ---------------------------------------------------------------------------

step({
    id = "welcome",
    title = "Welcome",
    body = "This sets up the interface in a few steps.\n\n"
            .. "Every answer here is also a setting in the options panel, so "
            .. "nothing you choose now is final -- and pressing Next through "
            .. "all of it gives a sensible interface without reading a word.\n\n"
            .. "You can reopen this at any time with /eq setup.",

    example = function(pane)
        local text = OB.NewText(pane, "OVERLAY", "GameFontHighlightLarge")
        text:SetPoint("CENTER", pane, "CENTER", 0, 0)
        text:SetText("Equadis' Classic Overhaul")
    end,
})

-- ---------------------------------------------------------------------------
-- 2. which subsystems run at all
-- ---------------------------------------------------------------------------

--[==[ **A line about each, because a name is not an explanation.**

     "Buff Frames" tells somebody who already knows what it does that it is
     there. The whole point of walking through these one at a time is the person
     who does not, so each gets a sentence saying what changes if they say yes.

     Keyed by module id and deliberately incomplete: a module with no line here
     still gets a step, with its name and nothing else. That is worse than a
     sentence and much better than being left out, and it means adding a module
     never silently drops it from the walkthrough. ]==]
local MODULE_BLURBS = {
    actionbars = "Moves, scales and restyles the client's action bars, and "
            .. "puts keybind and macro text under your control.",
    unitframes = "Replaces the player, target, target-of-target and pet "
            .. "frames with ones that match the rest of this.",
    nameplates = "Replaces the bars over units' heads: colours, health text, "
            .. "cast bars, debuffs and raid markers.",
    partyframes = "Replaces the party frames.",
    raidframes = "A raid grid, in place of the client's raid frames.",
    buffframes = "Rearranges your buffs and debuffs and puts timers on them.",
    bags = "One window for every bag, with search, sorting and a look at "
            .. "what your other characters are carrying.",
    map = "Resizes the world map so you can walk with it open, squares off "
            .. "the minimap and adds a clock.",
    tooltip = "Restyles the tooltip and adds a health bar to it.",
    chat = "Chat window behaviour: sizing, fading and copying text out.",
    damage = "A damage meter.",
    threat = "A threat meter.",
    waypoints = "An arrow that points at a place you picked on the map.",
    itemdatabase = "Remembers where items came from and what they sell for.",
    auction = "Auction house scanning and price memory.",
    roster = "Learns players' levels and classes so chat and nameplates can "
            .. "show them.",
    unitscan = "Watches for rare mobs by name and shouts when one appears.",
    characterpanel = "Tidies the character sheet.",
    combopoints = "A combo point display.",
    druidmana = "A mana bar while you are in a form that hides it.",
    health = "A health readout.",
    power = "A mana, rage or energy readout.",
    precise = "Finer numbers in places the client rounds.",
}

--[==[ **A picture for every module, because a name is not an answer.**

     This had two. The rest of the walkthrough was a paragraph and a checkbox --
     which is a settings panel with fewer columns per page, and the header of
     this file says that is the bar it has to clear.

     **Drawn, not live.** Each of these builds the shape out of the same media
     the module uses: the bar texture you picked, the class colours the roster
     colours names with, the quality colours the tooltip borders with. What none
     of them do is drive the real module against a fake unit. That is a
     different piece of work -- the modules render against the client's own
     frames -- and a picture honest about being a picture beats a preview that
     lies. Every pane says so in its caption.

     **They are deliberately dense.** Somebody is deciding whether to switch a
     subsystem on, and the useful question is "what will my screen look like",
     not "what is this called". A row of twelve action buttons answers that; one
     button does not. ]==]
local MODULE_EXAMPLES = {}

--[==[ **What each module can look like, rather than one specimen of it.**

     A single still is a claim about one setting. The action bars are one row or
     three; the unit frames wear the client's art or this addon's; a nameplate
     with a cast bar and a row of debuff timers on it is a different object from
     a bare one -- and somebody deciding whether to switch the module on is
     deciding about all of those, from a picture of one.

     So a module names its variations here and its painter is handed which one to
     draw. The pane cycles through them on its own, and the caption says which is
     up, because a picture that changes without saying so reads as a bug.

     A module with no entry here has one picture and does not rotate. ]==]
local MODULE_VARIANTS = {}

--[[ How long each variation is up. Long enough to look at, short enough that
     somebody who is reading the text beside it sees the second one before they
     have finished. ]]--
local VARIANT_SECONDS = 3.0

-- ---------------------------------------------------------------------------
-- the pieces the examples are drawn from
-- ---------------------------------------------------------------------------

--[==[ **The stops a moving bar visits.**

     Party frames are the case: four still bars say what one looks like and
     nothing about what a party *is*. Health that moves -- somebody at a third,
     somebody full, somebody dropping -- is the thing being judged, and it costs
     four `SetValue` calls a second.

     Stepped rather than interpolated, and each bar starts at a different stop,
     because a room where everything moves together reads as one animation
     rather than as four people. ]==]
local EX_STOPS = { 100, 66, 33, 0, 33, 66 }
local EX_STEP_SECONDS = 1.2

--[[ The texture and font being chosen two steps later, so a module drawn here
     is drawn in the look the reader has already settled on -- or is about to
     change, which is why the look step redraws its own pane. ]]--
local function exTexture()
    return OB.textures[OB.profile.texture or 1]
end

--[==[ **Which pane is being painted, and what it ended up holding.**

     Every picture in this walkthrough is built from `exBar` and `exText`, so
     recording what they make is enough to draw the whole thing again in a
     different texture or a different font -- without nineteen painters each
     keeping their own list of handles and each forgetting a different one.

     A module-scope name rather than an argument threaded through every helper:
     one pane is painted at a time, and the alternative is a parameter on twenty
     functions that exists only to be passed on. Cleared by `exPaint`, so a
     painter that errors half way cannot leave the next one appending to a pane
     that is gone. ]==]
local drawingPane

local function exRemember(kind, obj)
    if drawingPane then
        drawingPane[kind] = drawingPane[kind] or {}
        table.insert(drawingPane[kind], obj)
    end

    return obj
end

--[[ A status bar with a dark bed under it, which is what every bar in this
     addon is and what makes a half-full one read as half full rather than as a
     short bar. ]]--
local function exBar(parent, w, h, pct, r, g, b)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetWidth(w)
    bar:SetHeight(h)
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(pct)
    bar:SetStatusBarColor(r or 0.2, g or 0.65, b or 0.2)

    local path = exTexture()
    if path then bar:SetStatusBarTexture(path) end

    local bed = bar:CreateTexture(nil, "BACKGROUND")
    bed:SetAllPoints(bar)
    bed:SetTexture(0, 0, 0, 0.6)

    return exRemember("exBars", bar)
end

--[==[ **A bar that moves through the stops, from wherever it starts.**

     The phase is the caller's, so four frames in a party are at four different
     points -- which is what a party looks like and what one still cannot
     show. ]==]
local function exCycle(bar, phase)
    if not bar then return bar end

    bar.exPhase = phase or 0
    bar:SetValue(EX_STOPS[mod(bar.exPhase, table.getn(EX_STOPS)) + 1])

    return exRemember("exCycling", bar)
end

--[==[ **Moved on by the window's own clock**, once per stop rather than every
     frame: these are drawings of bars, and a drawing that eases smoothly would
     be claiming a smoothness the real ones do not have either -- 1.12 updates a
     health bar when the health changes. ]==]
local function exStepCycles(pane, now)
    if not pane or not pane.exCycling then return false end

    local at = math.floor((now or 0) / EX_STEP_SECONDS)
    if at == pane.exCycleAt then return false end

    pane.exCycleAt = at
    local stops = table.getn(EX_STOPS)

    for i = 1, table.getn(pane.exCycling) do
        local bar = pane.exCycling[i]
        bar:SetValue(EX_STOPS[mod(at + (bar.exPhase or 0), stops) + 1])
    end

    return true
end

local function exText(parent, template, text)
    local t = OB.NewText(parent, "OVERLAY", template or "GameFontNormalSmall")
    if text then t:SetText(text) end

    --[[ The template's own size is kept and only the face and the outline are
         changed on a redraw, or every label in every picture would come back
         the same size and the layout with it. ]]--
    local _, size = t:GetFont()
    t.exSize = size or 11

    return exRemember("exTexts", t)
end

--[[ A square with an icon in it and a thin dark bed behind, which is every item
     slot, action button and aura in the interface. ]]--
local function exIcon(parent, size, texture)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(size)
    f:SetHeight(size)

    local bed = f:CreateTexture(nil, "BACKGROUND")
    bed:SetAllPoints(f)
    bed:SetTexture(0.1, 0.1, 0.12, 1)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    f.icon = icon
    return f
end

--[==[ **A class portrait, from the atlas the unit frames use.**

     The walkthrough was drawing spell icons where a face belongs, so a party
     frame in it looked like a row of action buttons. These are the same circles
     `StylePortrait` puts on a real frame -- see `OB.SetClassCircle` -- which is
     what makes the picture a picture *of the module* rather than of four
     rectangles. ]==]
local function exPortrait(parent, size, class)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(size)
    f:SetHeight(size)

    local bed = f:CreateTexture(nil, "BACKGROUND")
    bed:SetAllPoints(f)
    bed:SetTexture(0.08, 0.08, 0.10, 0.85)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(f)

    --[[ A class this atlas does not carry gets the question mark rather than a
         corner of somebody else's circle. ]]--
    if not OB.SetClassCircle(icon, class) then
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    f.icon = icon
    return f
end

--[[ A panel with this addon's own edge on it, for the examples that are windows
     rather than bars. ]]--
local function exPanel(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetWidth(w)
    f:SetHeight(h)
    if OB.SkinWindow then OB.SkinWindow(f, 0.9) end
    return f
end

--[==[ **The whole pane, in whatever look is chosen now.**

     The walkthrough puts the look step *after* the module steps, and somebody
     who goes back to change the texture should see the change on the picture
     they went back for. Before this, only the look step's own bar answered --
     every module picture kept the texture it was born with, so the one place
     the choice could be judged was the one place there was nothing to judge.

     Bars take the texture, text takes the face and the outline weight, and
     both keep everything else they were given. ]==]
local function exRedraw(pane)
    if not pane then return false end

    local path = exTexture()
    local bars = pane.exBars or {}

    for i = 1, table.getn(bars) do
        --[[ Except a bar that is *showing* a texture rather than wearing the
             chosen one: the damage meter's picture cycles through textures to
             say that they can be changed, and a redraw that put the profile's
             back would take the demonstration away. ]]--
        if path and bars[i].SetStatusBarTexture and not bars[i].exOwnLook then
            bars[i]:SetStatusBarTexture(path)
        end
    end

    local texts = pane.exTexts or {}

    for i = 1, table.getn(texts) do
        if not texts[i].exOwnLook then
            OB.ApplyFont(texts[i], texts[i].exSize or 11)
        end
    end

    return true
end

--[==[ **One painter, run with the pane in hand.**

     The pane is set before and cleared after, so `exBar` and `exText` know
     where to file what they make -- and a step with a `Redraw` of its own is
     given the shared one underneath it rather than instead of it, because the
     look step redraws its own bar and would otherwise stop redrawing the rest
     of the pane the moment it grew one. ]==]
local function exPaint(pane, painter, variant, label)
    if not pane or type(painter) ~= "function" then return false end

    drawingPane = pane
    local ok, err = pcall(painter, pane, variant or 1, label)
    drawingPane = nil

    if not ok then
        --[[ A picture is not worth a walkthrough. Reported rather than
             swallowed, because a step that silently draws nothing looks like a
             module with nothing to show. ]]--
        OB.Print("could not draw the example: " .. tostring(err), "Setup")
        return false
    end

    local own = pane.Redraw

    pane.Redraw = function()
        exRedraw(pane)
        if own then own() end
    end

    --[[ Once now, so the picture opens in the chosen font rather than in the
         client's and correcting itself the first time something is cycled. ]]--
    pane.Redraw()

    return true
end

--[[ Every pane says what it is. A drawing that does not admit to being one is
     a promise the module has to keep exactly. ]]--
local function exCaption(pane, text)
    local c = exText(pane, "GameFontDisableSmall", text)
    c:SetPoint("BOTTOM", pane, "BOTTOM", 0, 2)
    return c
end

--[[ Class colours through the addon's own lookup, so the example cannot drift
     from what the roster actually paints a name. ]]--
local function exClass(token)
    local r, g, b = OB.ClassColor(token)
    return r or 1, g or 1, b or 1
end

local function exQuality(q)
    if type(GetItemQualityColor) ~= "function" then return 1, 1, 1 end
    local r, g, b = GetItemQualityColor(q)
    return r or 1, g or 1, b or 1
end

--[[ Icons chosen from the handful that have been in the client since 1.12 and
     are not class-specific, so the picture is the same whoever is reading
     it. ]]--
local EX_ICONS = {
    "Interface\\Icons\\INV_Sword_04",
    "Interface\\Icons\\Spell_Fire_FlameBolt",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\INV_Potion_51",
    "Interface\\Icons\\INV_Misc_Bag_08",
    "Interface\\Icons\\INV_Misc_QuestionMark",
    "Interface\\Icons\\Ability_Warrior_Charge",
    "Interface\\Icons\\Spell_Holy_FlashHeal",
    "Interface\\Icons\\INV_Misc_Rune_01",
}

local function exIconAt(i)
    return EX_ICONS[(mod(i - 1, table.getn(EX_ICONS))) + 1]
end

-- ---------------------------------------------------------------------------
-- one per module
-- ---------------------------------------------------------------------------

--[[ Twelve buttons, keybinds in the corner and a cooldown on one of them --
     which is the whole of what this module puts under your control. ]]--
--[==[ **Three shapes, because "action bars" is not one arrangement.**

     A twelve-wide strip, a stack of three rows, and a bar with the text taken
     off it are the three answers people actually give -- and which of them is
     on screen changes what the module is *for*. Somebody deciding whether to
     switch it on from a picture of the first would be deciding about the wrong
     thing entirely. ]==]
MODULE_VARIANTS.actionbars = {
    "Twelve across, keybinds and cooldowns",
    "Three rows, six wide",
    "Bare icons, no text at all",
}

MODULE_EXAMPLES.actionbars = function(pane, variant, label)
    local KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" }
    local SIZE, GAP = 38, 4

    --[[ Twelve in a strip, six in three rows -- the shape *is* the variation,
         so the count per row is what the number below changes. ]]--
    local perRow = 12
    if variant == 2 then perRow = 6 end

    local rows = math.ceil(12 / perRow)
    local text = variant ~= 3

    local block = CreateFrame("Frame", nil, pane)
    block:SetWidth((perRow * SIZE) + ((perRow - 1) * GAP))
    block:SetHeight((rows * SIZE) + ((rows - 1) * GAP))
    block:SetPoint("CENTER", pane, "CENTER", 0, 24)

    for i = 1, 12 do
        local col = mod(i - 1, perRow)
        local line = math.floor((i - 1) / perRow)

        local b = exIcon(block, SIZE, exIconAt(i))
        b:SetPoint("TOPLEFT", block, "TOPLEFT",
                col * (SIZE + GAP), -(line * (SIZE + GAP)))

        if text then
            local key = exText(b, "GameFontNormalSmall", KEYS[i])
            key:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -1)
        end

        --[[ One of them mid-cooldown, because the number on a darkened icon is
             the setting people actually come here for. ]]--
        if i == 4 then
            local dim = b:CreateTexture(nil, "OVERLAY")
            dim:SetAllPoints(b)
            dim:SetTexture(0, 0, 0, 0.6)

            if text then
                local count = exText(b, "GameFontNormalLarge", "3")
                count:SetPoint("CENTER", b, "CENTER", 0, 0)
                count:SetTextColor(1, 0.82, 0)
            end
        end
    end

    if text then
        local macro = exText(pane, "GameFontDisableSmall", "Charge")
        macro:SetPoint("TOP", block, "BOTTOM", 0, -4)
    end

    exCaption(pane, label or "Twelve slots, keybinds, cooldowns and macro names")
end

--[[ A player frame and a target frame, which is what this module replaces and
     the only shape worth judging it in. ]]--
--[==[ **The three states the module actually has**, which is a setting people
     change on day one and never again: this addon's own frames, the client's
     own art kept and only restyled, and the compact pair for somebody who wants
     the screen back. ]==]
MODULE_VARIANTS.unitframes = {
    "Full frames, numbers on the bars",
    "Compact -- half the height, no portrait",
    "Percentages instead of numbers",
}

MODULE_EXAMPLES.unitframes = function(pane, variant, label)
    local compact = (variant == 2)
    local percent = (variant == 3)

    local function unit(x, name, r, g, b, hp, hpMax, power, pr, pg, pb)
        local f = CreateFrame("Frame", nil, pane)
        f:SetWidth(200)
        f:SetHeight(compact and 32 or 52)
        f:SetPoint("CENTER", pane, "CENTER", x, 24)

        local width = 148

        if not compact then
            local portrait = exIcon(f, 44, exIconAt(1))
            portrait:SetPoint("LEFT", f, "LEFT", 0, 0)
        else
            --[[ No portrait is most of what compact *is*, so the bars take the
                 room it was using rather than leaving a gap where it was. ]]--
            width = 196
        end

        local label = exText(f, "GameFontNormalSmall", name)
        label:SetPoint("TOPLEFT", f, "TOPLEFT", compact and 0 or 50, -1)
        label:SetTextColor(r, g, b)

        local health = exBar(f, width, compact and 12 or 18, hp,
                0.15, 0.62, 0.15)
        health:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)

        --[[ A percentage and a pair of numbers are the two readings of the same
             bar, and which one somebody wants is the whole of the Health Text
             setting. ]]--
        local reading = math.floor(hp) .. "%"
        if not percent then
            reading = math.floor(hpMax * hp / 100) .. " / " .. hpMax
        end

        local hpText = exText(health, "GameFontHighlightSmall", reading)
        hpText:SetPoint("CENTER", health, "CENTER", 0, 0)

        local mana = exBar(f, width, compact and 7 or 10, power, pr, pg, pb)
        mana:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
    end

    unit(-110, "Equadis", exClass("PALADIN"), 84, 5850, 61, 0.2, 0.4, 0.9)
    unit(110, "Ragged Timber Wolf", 0.9, 0.3, 0.25, 43, 1240, 100, 0.9, 0.5, 0.1)

    exCaption(pane, label or "Player and target, in the same look as the rest")
end

--[==[ **A plate is four different objects depending on what is switched on.**

     A bare bar with a name; the same plate mid-cast with the seconds left on
     it; one carrying a row of debuff icons with their timers; and the small
     version somebody uses when twelve of them are on screen at once. Each is a
     real answer to "what does this module do", and a picture of any one of them
     is a picture of the wrong thing to somebody who wanted another. ]==]
MODULE_VARIANTS.nameplates = {
    "Names, health and threat colours",
    "Cast bars, with the seconds left",
    "Debuffs and how long they have to run",
    "Small plates, for a room full of them",
}

MODULE_EXAMPLES.nameplates = function(pane, variant, label)
    local casting = (variant == 2)
    local debuffs = (variant == 3)
    local small = (variant == 4)

    local width = small and 90 or 140

    local function plate(x, y, name, hp, r, g, b, showCast, showDebuffs)
        local plate = CreateFrame("Frame", nil, pane)
        plate:SetWidth(width)
        plate:SetHeight(40)
        plate:SetPoint("CENTER", pane, "CENTER", x, y)

        local label = exText(plate, "GameFontNormalSmall", name)
        label:SetPoint("TOP", plate, "TOP", 0, 0)

        local bar = exBar(plate, width, small and 9 or 13, hp, r, g, b)
        bar:SetPoint("TOP", label, "BOTTOM", 0, -2)

        if not small then
            local text = exText(bar, "GameFontHighlightSmall",
                    math.floor(hp) .. "%")
            text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
        end

        --[[ The cast bar, which is the reason people run a plate addon at all
             in a game with no target cast bar worth the name -- and the seconds
             on the end of it, which is the reason to look at one mid-pull. ]]--
        if showCast then
            local cast = exBar(plate, width, 9, 62, 0.9, 0.75, 0.2)
            cast:SetPoint("TOP", bar, "BOTTOM", 0, -2)

            local spell = exText(cast, "GameFontHighlightSmall", "Fireball")
            spell:SetPoint("LEFT", cast, "LEFT", 3, 0)

            local left = exText(cast, "GameFontHighlightSmall", "1.4")
            left:SetPoint("RIGHT", cast, "RIGHT", -3, 0)
        end

        --[[ Icons with numbers under them rather than icons alone: the icon
             answers "is it still on" and the number answers the question
             actually being asked. ]]--
        if showDebuffs then
            local seconds = { "16", "8", "24" }

            for i = 1, 3 do
                local icon = exIcon(plate, 15, exIconAt(i + 4))
                icon:SetPoint("TOPLEFT", bar, "BOTTOMLEFT",
                        (i - 1) * 17, -2)

                local timer = exText(icon, "GameFontHighlightSmall", seconds[i])
                timer:SetPoint("BOTTOM", icon, "BOTTOM", 0, -9)
            end
        end
    end

    if small then
        --[[ Six of them, because the small plates are for the case where six is
             what is on screen. ]]--
        local spots = {
            { -170, 50 }, { -60, 62 }, { 55, 44 },
            { 160, 58 }, { -110, -20 }, { 40, -34 },
        }

        local mobs = {
            { "Scarlet Myrmidon", 64, 0.8, 0.2, 0.2 },
            { "Scarlet Sorcerer", 88, 0.8, 0.2, 0.2 },
            { "Scarlet Zealot", 41, 0.85, 0.6, 0.2 },
            { "Scarlet Wizard", 100, 0.8, 0.2, 0.2 },
            { "Scarlet Chaplain", 73, 0.85, 0.6, 0.2 },
            { "Sylvie", 100, exClass("PRIEST") },
        }

        for i = 1, 6 do
            local m = mobs[i]
            plate(spots[i][1], spots[i][2], m[1], m[2], m[3], m[4], m[5])
        end
    else
        plate(-150, 40, "Ragged Timber Wolf", 64, 0.8, 0.2, 0.2,
                false, debuffs)
        plate(20, 40, "Kobold Geomancer", 88, 0.85, 0.6, 0.2,
                casting, debuffs)
        plate(-60, -40, "Sylvie", 100, exClass("PRIEST"))
    end

    exCaption(pane, label or "Drawn plates, not live ones")
end

--[==[ **The party as it actually looks, in the three styles this addon has.**

     The old picture was four rectangles with spell icons where the faces go,
     and it was reported as exactly that: not what the party frames look like.
     Two things were wrong with it. The portraits were action-bar icons, and the
     one arrangement it drew was not one of the three the module offers.

     **Overhaul, Compact and Classic** are the module's own `frameMode` values --
     the same three names on the panel -- so the picture is a picture of a
     setting rather than of a mood. Overhaul is this addon's frame: portrait,
     name, health with numbers, power under it. Compact is the same without the
     portrait and half the height, which is what somebody raiding on a small
     screen wants. Classic keeps the client's proportions and its own art.

     **And the party is alive.** Four still bars say what one frame looks like
     and nothing about what a party is: somebody at a third, somebody full,
     somebody dropping. Each bar starts at a different stop -- see `exCycle` --
     because everything moving together reads as one animation rather than as
     four people. ]==]
MODULE_VARIANTS.partyframes = {
    "Overhaul -- portraits, numbers, power",
    "Compact -- half the height, no portrait",
    "Classic -- the client's own proportions",
}

--[==[ **Real characters rather than four names.**

     A human female paladin, a tauren druid, a night elf rogue and an orc
     warrior: the classes carry the portraits and the colours, and the races are
     said in the line under the name because that is what somebody reads a party
     frame for -- who is this, and can they help. ]==]
local EX_PARTY = {
    { name = "Aurelin",  class = "PALADIN", race = "Human Female",  phase = 0 },
    { name = "Grimhoof", class = "DRUID",   race = "Tauren Male",   phase = 2 },
    { name = "Nyshara",  class = "ROGUE",   race = "Night Elf",     phase = 4 },
    { name = "Gorruk",   class = "WARRIOR", race = "Orc Male",      phase = 3 },
}

--[[ What each class fills its second bar with, because a druid's blue and a
     warrior's red are half of how a party frame is read at a glance. ]]--
local EX_POWER = {
    PALADIN = { 0.20, 0.40, 0.90 },
    DRUID   = { 0.20, 0.40, 0.90 },
    PRIEST  = { 0.20, 0.40, 0.90 },
    MAGE    = { 0.20, 0.40, 0.90 },
    WARLOCK = { 0.20, 0.40, 0.90 },
    SHAMAN  = { 0.20, 0.40, 0.90 },
    HUNTER  = { 0.20, 0.40, 0.90 },
    ROGUE   = { 1.00, 0.85, 0.20 },
    WARRIOR = { 0.85, 0.20, 0.20 },
}

MODULE_EXAMPLES.partyframes = function(pane, variant, label)
    local compact = (variant == 2)
    local classic = (variant == 3)

    local height = compact and 26 or 46
    local pitch = compact and 30 or 52
    local width = classic and 190 or 220

    for i = 1, table.getn(EX_PARTY) do
        local who = EX_PARTY[i]

        local f = CreateFrame("Frame", nil, pane)
        f:SetWidth(width)
        f:SetHeight(height)
        f:SetPoint("TOP", pane, "TOP", 0, -18 - ((i - 1) * pitch))

        local barWidth = width
        local left = 0

        --[[ The portrait is the first thing Compact gives up, which is most of
             why anybody chooses it. ]]--
        if not compact then
            local size = classic and 34 or 40
            local portrait = exPortrait(f, size, who.class)
            portrait:SetPoint("LEFT", f, "LEFT", 0, 0)

            left = size + 6
            barWidth = width - left
        end

        local name = exText(f, "GameFontNormalSmall", who.name)
        name:SetPoint("TOPLEFT", f, "TOPLEFT", left, -1)
        name:SetTextColor(exClass(who.class))

        --[[ Who they are, under the name, on the two styles with room for
             it. ]]--
        if not compact then
            local race = exText(f, "GameFontDisableSmall", who.race)
            race:SetPoint("LEFT", name, "RIGHT", 6, 0)
        end

        local health = exBar(f, barWidth, compact and 11 or 16, 100,
                0.15, 0.62, 0.15)
        health:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
        exCycle(health, who.phase)

        --[[ Numbers on the health bar in this addon's own style, a percentage
             in the client's -- which is the difference somebody is choosing
             between rather than a decoration. ]]--
        if not compact then
            local reading = exText(health, "GameFontHighlightSmall",
                    classic and "82%" or "3820 / 4650")
            reading:SetPoint("CENTER", health, "CENTER", 0, 0)
        end

        local power = EX_POWER[who.class] or { 0.2, 0.4, 0.9 }
        local mana = exBar(f, barWidth, compact and 5 or 8, 100,
                power[1], power[2], power[3])
        mana:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
        exCycle(mana, who.phase + 1)
    end

    exCaption(pane, label or "Four of them, in place of the client's own")
end

--[==[ **A grid rather than a list**, which is the whole difference between a
     raid frame and eight party frames -- and the three sizes of group it has to
     hold are three different objects, so all three are drawn.

     The bars move for the same reason the party's do: a raid is read by which
     bar is dropping, and a still picture of forty full ones says nothing about
     that. Each starts at its own stop.

     Class colours on the names rather than on the bars, because a healer finds
     a person by their name and judges them by the bar -- two jobs, two
     channels. ]==]
MODULE_VARIANTS.raidframes = {
    "Forty, as eight groups of five",
    "A single group, larger",
    "Twenty-five, with the power bars on",
}

--[[ The nine classes, in the order a raid tends to be sorted, so a column reads
     as a group rather than as a shuffle. ]]--
local EX_RAID_CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "PALADIN",
                          "DRUID", "HUNTER", "WARLOCK", "SHAMAN" }

local EX_RAID_NAMES = {
    "Aurelin", "Grimhoof", "Nyshara", "Gorruk", "Sylvie",
    "Dunkel", "Mirelle", "Thalorn", "Brakk", "Elunara",
}

MODULE_EXAMPLES.raidframes = function(pane, variant, label)
    local COLS, ROWS = 8, 5
    local W, H, GAP = 76, 26, 3
    local power = false

    if variant == 2 then
        --[[ One group, at the size somebody running a five-man actually keeps
             it -- which is a different window from the forty-man grid. ]]--
        COLS, ROWS = 1, 5
        W, H = 220, 34
    elseif variant == 3 then
        COLS, ROWS = 5, 5
        W, H = 118, 30
        power = true
    end

    local grid = CreateFrame("Frame", nil, pane)
    grid:SetWidth((COLS * W) + ((COLS - 1) * GAP))
    grid:SetHeight((ROWS * H) + ((ROWS - 1) * GAP))
    grid:SetPoint("CENTER", pane, "CENTER", 0, 14)

    for r = 1, ROWS do
        for c = 1, COLS do
            local i = ((r - 1) * COLS) + c
            local class = EX_RAID_CLASSES[(mod(i - 1, 9)) + 1]

            local cell = CreateFrame("Frame", nil, grid)
            cell:SetWidth(W)
            cell:SetHeight(H)
            cell:SetPoint("TOPLEFT", grid, "TOPLEFT",
                    (c - 1) * (W + GAP), -(r - 1) * (H + GAP))

            local barHeight = power and (H - 6) or H

            local health = exBar(cell, W, barHeight, 100, 0.15, 0.62, 0.15)
            health:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)

            --[[ A different starting point per cell, so the grid moves the way
                 a raid does rather than as one block. ]]--
            exCycle(health, i)

            --[[ A name and a class colour is what a raid frame is for: finding
                 the person. The larger arrangements have room for the whole
                 name; the forty-man grid does not, and shortening it is what
                 the module does there too. ]]--
            local shown = EX_RAID_NAMES[(mod(i - 1, 10)) + 1]
            if W < 100 then shown = string.sub(shown, 1, 5) end

            local name = exText(health, "GameFontHighlightSmall", shown)
            name:SetPoint("LEFT", health, "LEFT", 3, 0)
            name:SetTextColor(exClass(class))

            if W >= 200 then
                local portrait = exPortrait(cell, H - 4, class)
                portrait:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
            end

            if power then
                local mana = exBar(cell, W, 4, 100, 0.20, 0.40, 0.90)
                mana:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -2)
                exCycle(mana, i + 2)
            end
        end
    end

    exCaption(pane, label or "A raid as a grid, not as eight party frames")
end

--[==[ **Three rows, because a buff row is not the only thing this draws.**

     The buffs with the time left coloured by how much of it there is; the
     debuffs, which are the row people actually watch; and the weapon enchants,
     which are the half every buff-moving addon forgets and the only place the
     main hand and off hand border colours mean anything.

     The timer colours come from the module's own setting rather than from a
     palette written here, so somebody who changes them on the panel sees the
     change in this picture -- see `TimerColor`. ]==]
MODULE_VARIANTS.buffframes = {
    "Buffs, with the time left coloured",
    "Debuffs, in their own row",
    "Weapon enchants, main hand and off hand",
}

MODULE_EXAMPLES.buffframes = function(pane, variant, label)
    local buffs = OB.modules and OB.modules.buffframes

    --[[ The seconds behind each label, so the colour is the module's own answer
         to the same number rather than a guess repeated here. ]]--
    local ROW = {
        { "1h", 3600 }, { "45m", 2700 }, { "28m", 1680 }, { "12m", 720 },
        { "4m30s", 270 }, { "1m40s", 100 }, { "24", 24 }, { "6", 6 },
    }

    local function icons(list, y, size, harmful)
        local row = CreateFrame("Frame", nil, pane)
        row:SetWidth(table.getn(list) * (size + 6))
        row:SetHeight(size + 18)
        row:SetPoint("CENTER", pane, "CENTER", 0, y)

        for i = 1, table.getn(list) do
            local b = exIcon(row, size, exIconAt(i + (harmful and 5 or 1)))
            b:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (size + 6), 0)

            --[[ A debuff wears the client's own red edge, which is how anybody
                 tells the two rows apart at a glance. ]]--
            if harmful then
                local edge = b:CreateTexture(nil, "OVERLAY")
                edge:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                edge:SetBlendMode("ADD")
                edge:SetWidth(size * 1.55)
                edge:SetHeight(size * 1.55)
                edge:SetPoint("CENTER", b, "CENTER", 0, 0)
                edge:SetVertexColor(0.8, 0.15, 0.15)
                edge:SetAlpha(0.6)
            end

            local time = exText(b, "GameFontNormalSmall", list[i][1])
            time:SetPoint("TOP", b, "BOTTOM", 0, -2)

            --[[ Asked of the module, so the picture cannot disagree with what
                 the setting does. ]]--
            local r, g, bb = nil, nil, nil
            if buffs and buffs.TimerColor then
                r, g, bb = buffs:TimerColor(list[i][2])
            end

            if r then time:SetTextColor(r, g, bb) end
        end

        return row
    end

    if variant == 2 then
        local short = {}
        for i = 4, 8 do table.insert(short, ROW[i]) end
        icons(short, 24, 38, true)

    elseif variant == 3 then
        --[==[ **The weapon enchants, and the two colours that say which hand.**

             A poison on each weapon is two identical icons side by side, and
             the border is the only thing that says which is which. Read from
             the module's own settings, so somebody who picks their own pair
             sees them here. ]==]
        local cfg = OB.profile and OB.profile.modules
                and OB.profile.modules.buffframes or {}

        local hands = {
            { "Instant Poison", "18", cfg.mainHandColor or { 1, 0.82, 0, 1 },
              "Main hand" },
            { "Deadly Poison", "112", cfg.offHandColor or { 0.3, 0.65, 1, 1 },
              "Off hand" },
        }

        for i = 1, 2 do
            local hand = hands[i]

            local b = exIcon(pane, 44, exIconAt(i + 6))
            b:SetPoint("CENTER", pane, "CENTER", (i == 1) and -70 or 10, 34)

            local edge = b:CreateTexture(nil, "OVERLAY")
            edge:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            edge:SetBlendMode("ADD")
            edge:SetWidth(70)
            edge:SetHeight(70)
            edge:SetPoint("CENTER", b, "CENTER", 0, 0)
            edge:SetVertexColor(hand[3][1], hand[3][2], hand[3][3])

            --[[ The charge count in the corner, which is the number the client
                 knows and never draws. ]]--
            local charges = exText(b, "GameFontNormalSmall", hand[2])
            charges:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)

            local name = exText(pane, "GameFontHighlightSmall", hand[1])
            name:SetPoint("TOP", b, "BOTTOM", 0, -6)
            name:SetTextColor(hand[3][1], hand[3][2], hand[3][3])

            local which = exText(pane, "GameFontDisableSmall", hand[4])
            which:SetPoint("TOP", name, "BOTTOM", 0, -2)
        end

    else
        icons(ROW, 24, 38, false)
    end

    exCaption(pane, label or "Your auras, rearranged, with the time left on them")
end

--[==[ **The same five people, in the looks this window can wear.**

     A meter is a window somebody stares at for a whole raid, so the arguments
     about it are about *appearance*: rows in class colours or in one colour,
     numbers per second or as a share of the whole, and the bar texture --
     which is chosen two steps later and is the reason each of these redraws
     when it changes.

     Shown rather than described, because "coloured by class" is a sentence and
     this is a picture of it. ]==]
--[==[ **And the texture, which is half of what a meter looks like.**

     A window somebody stares at for a whole raid is judged on its bars, and the
     bar is a texture as much as it is a colour. The fourth arrangement draws the
     same five rows in four different ones at once -- which is the only honest way
     to show a choice that is normally seen one at a time. ]==]
MODULE_VARIANTS.damage = {
    "Rows in class colours, damage and share",
    "One colour for every row",
    "Damage per second, with the totals",
    "Any bar texture you like",
}

MODULE_EXAMPLES.damage = function(pane, variant, label)
    local plain = (variant == 2)
    local perSecond = (variant == 3)
    local textures = (variant == 4)

    local ROWS = {
        { "Alecander", "MAGE", 100, "1,284", "31%", "428" },
        { "Grimtusk", "WARRIOR", 82, "1,051", "25%", "350" },
        { "Equadis", "PALADIN", 61, "784", "19%", "261" },
        { "Sylvie", "PRIEST", 44, "562", "13%", "187" },
        { "Holywrath", "PALADIN", 32, "410", "10%", "137" },
    }

    local meter = exPanel(pane, 340, 150)
    meter:SetPoint("CENTER", pane, "CENTER", 0, 20)

    local title = exText(meter, "GameFontNormalSmall",
            perSecond and "Damage per second" or "Damage")
    title:SetPoint("TOPLEFT", meter, "TOPLEFT", 8, -6)

    local total = exText(meter, "GameFontDisableSmall", "4,091 total")
    total:SetPoint("TOPRIGHT", meter, "TOPRIGHT", -8, -6)

    for i = 1, table.getn(ROWS) do
        local r, g, b = exClass(ROWS[i][2])

        --[[ One colour for every row is a real preference and a real setting:
             somebody who reads the meter by name does not want five colours
             competing with the class colours on their party frames. ]]--
        if plain then r, g, b = 0.25, 0.45, 0.75 end

        local bar = exBar(meter, 324, 20, ROWS[i][3], r * 0.7, g * 0.7, b * 0.7)
        bar:SetPoint("TOPLEFT", meter, "TOPLEFT", 8, -24 - ((i - 1) * 23))

        --[==[ **A different texture per row**, so four of the choices are on
             screen at once and the difference between them is a comparison
             rather than a memory. Marked as showing its own look, or the shared
             redraw would put the profile's texture back over all four. ]==]
        if textures then
            local path = OB.textures[(mod(i - 1, table.getn(OB.textures))) + 1]

            if path and bar.SetStatusBarTexture then
                bar:SetStatusBarTexture(path)
                bar.exOwnLook = true
            end
        end

        local name = exText(bar, "GameFontHighlightSmall",
                i .. ". " .. ROWS[i][1])
        name:SetPoint("LEFT", bar, "LEFT", 4, 0)

        --[[ The name keeps its class colour even where the bar gives it up,
             which is the arrangement most people actually settle on. ]]--
        if plain then name:SetTextColor(exClass(ROWS[i][2])) end

        local right = ROWS[i][4] .. "  " .. ROWS[i][5]
        if perSecond then right = ROWS[i][6] .. " dps  " .. ROWS[i][4] end

        --[[ The texture's own name on the row that is wearing it, because a
             picture of four textures with no labels is four bars. ]]--
        if textures then
            local path = OB.textures[(mod(i - 1, table.getn(OB.textures))) + 1]
            local _, _, leaf = string.find(tostring(path), "([^\\]+)$")
            right = leaf or right
        end

        local amount = exText(bar, "GameFontHighlightSmall", right)
        amount:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    end

    exCaption(pane, label or "Who did what, without alt-tabbing to a log parser")
end

--[==[ **The list is half of it; the bar is the half people actually watch.**

     This module draws two things and the picture only had one. The list says
     who has threat on the mob; **your own bar** -- one bar, your threat against
     the tank's, filling toward the number where you pull -- is the thing that
     sits at the edge of the screen for a whole raid, and it was not in the
     walkthrough at all.

     The ramp is the point of both: the same numbers in one colour say nothing,
     and telling somebody they are about to pull is the entire job. ]==]
MODULE_VARIANTS.threat = {
    "Your own bar, filling toward a pull",
    "Everybody on the mob, ranked",
    "Both at once, which is how it ships",
}

--[[ Green through yellow to red, which is the ramp the module paints and the
     one thing about it worth learning. ]]--
local function exThreatColor(pct)
    if pct >= 90 then return 0.85, 0.20, 0.20 end
    if pct >= 75 then return 0.95, 0.60, 0.15 end
    if pct >= 50 then return 0.85, 0.85, 0.20 end
    return 0.20, 0.70, 0.20
end

MODULE_EXAMPLES.threat = function(pane, variant, label)
    local ownBar = (variant ~= 2)
    local list = (variant ~= 1)

    if ownBar then
        --[==[ **One bar, wide, with the number on it.**

             Threat is a single question -- how close am I to taking it -- and
             the answer is a fraction of the tank's. The mob's name is on it
             because in a room of three pulls the bar has to say which one it is
             about. ]==]
        local box = exPanel(pane, 360, 54)
        box:SetPoint("TOP", pane, "TOP", 0, -14)

        local who = exText(box, "GameFontNormalSmall", "Gordok Enforcer")
        who:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -6)

        local tank = exText(box, "GameFontDisableSmall", "tank: Grimtusk")
        tank:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, -6)

        local r, g, b = exThreatColor(84)
        local bar = exBar(box, 344, 22, 84, r, g, b)
        bar:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 8, 6)
        exCycle(bar, 1)

        local pct = exText(bar, "GameFontHighlightSmall", "84% of the tank")
        pct:SetPoint("CENTER", bar, "CENTER", 0, 0)

        --[[ The line you must not cross, drawn on the bar rather than described
             beside it: 110% in melee, 130% at range, and the mark is what makes
             the number mean something. ]]--
        local mark = bar:CreateTexture(nil, "OVERLAY")
        mark:SetTexture(1, 1, 1, 0.8)
        mark:SetWidth(2)
        mark:SetHeight(22)
        mark:SetPoint("LEFT", bar, "LEFT", 344 * 0.91, 0)
    end

    if list then
        local ROWS = {
            { "Grimtusk", 100, "100%" },
            { "Equadis", 84, "84%" },
            { "Alecander", 71, "71%" },
            { "Sylvie", 38, "38%" },
        }

        local meter = exPanel(pane, 320, 124)

        if ownBar then
            meter:SetPoint("TOP", pane, "TOP", 0, -80)
        else
            meter:SetPoint("CENTER", pane, "CENTER", 0, 22)
        end

        local title = exText(meter, "GameFontNormalSmall", "Threat")
        title:SetPoint("TOPLEFT", meter, "TOPLEFT", 8, -6)

        for i = 1, table.getn(ROWS) do
            local r, g, b = exThreatColor(ROWS[i][2])

            local bar = exBar(meter, 304, 20, ROWS[i][2], r, g, b)
            bar:SetPoint("TOPLEFT", meter, "TOPLEFT", 8, -24 - ((i - 1) * 23))

            local name = exText(bar, "GameFontHighlightSmall", ROWS[i][1])
            name:SetPoint("LEFT", bar, "LEFT", 4, 0)

            local pct = exText(bar, "GameFontHighlightSmall", ROWS[i][3])
            pct:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        end
    end

    exCaption(pane, label or "Green is safe and red is about to be your problem")
end

--[==[ **Two halves: the list you keep, and the moment it pays off.**

     A scanner is a list of names most of the time and a popup for four seconds
     a week, and the four seconds are the reason anybody runs one. Both are
     drawn, because somebody deciding whether to switch this on is deciding
     about the second and will live with the first. ]==]
MODULE_VARIANTS.unitscan = {
    "The alert, when one turns up",
    "The names it is watching for",
}

MODULE_EXAMPLES.unitscan = function(pane, variant, label)
    if variant == 2 then
        local box = exPanel(pane, 300, 150)
        box:SetPoint("CENTER", pane, "CENTER", 0, 22)

        local head = exText(box, "GameFontNormalSmall", "Watching for 6 names")
        head:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)

        local NAMES = {
            { "Broken Tooth", "found 3 days ago" },
            { "Azurous", "" },
            { "Ivory Moth", "" },
            { "Death Howl", "found 6 hours ago" },
            { "Old Cliff Jumper", "" },
            { "Sri'skulk", "" },
        }

        for i = 1, table.getn(NAMES) do
            local y = -30 - ((i - 1) * 18)

            local name = exText(box, "GameFontHighlightSmall", NAMES[i][1])
            name:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)

            --[[ What was found and when, because a scanner that has already
                 caught something is the reason to trust the rest of the
                 list. ]]--
            if NAMES[i][2] ~= "" then
                name:SetTextColor(1, 0.82, 0)

                local when = exText(box, "GameFontDisableSmall", NAMES[i][2])
                when:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, y)
            end
        end

        exCaption(pane, label or "Add a name with /unitscan, and forget about it")
        return
    end

    local box = exPanel(pane, 340, 92)
    box:SetPoint("CENTER", pane, "CENTER", 0, 30)

    --[[ The star, because the star is what clicking the popup does: it targets
         the thing and marks it for everyone else. ]]--
    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
    mark:SetWidth(38)
    mark:SetHeight(38)
    mark:SetPoint("LEFT", box, "LEFT", 14, 4)

    local head = exText(box, "GameFontNormalSmall", "Found")
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 60, -10)
    head:SetTextColor(1, 0.82, 0)

    local name = exText(box, "GameFontNormalLarge", "Broken Tooth")
    name:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)

    local since = exText(box, "GameFontDisableSmall", "4s ago")
    since:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -12)

    local note = exText(box, "GameFontDisableSmall",
            "Click to target and mark  |  Ctrl-drag to move")
    note:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 60, 8)

    exCaption(pane, label or "Watches for names you gave it and shouts")
end

--[==[ **A tooltip is what this addon changes most and the walkthrough showed
     least.**

     The picture was a static item tooltip with a health bar stuck on the
     bottom. What the module actually draws, and what somebody hovers a mob for,
     is: the health bar **on top** with the numbers in it, the name in the
     colour the unit's reaction gives it, what it drops with a real drop rate
     beside each line, and the line at the bottom saying which key opens the
     database.

     The three arrangements are the three settings people ask about first --
     how much of the drop list is shown, whether the health bar is there at all,
     and how heavy the background is. Each is drawn rather than described,
     because the whole argument for a tooltip addon is what it looks like. ]==]
--[==[ **And what it is made of, as well as what it says.**

     The background and the font are the two settings people change first on a
     tooltip -- it is the box that appears under the cursor a thousand times an
     evening -- and describing them is no use at all. The last arrangement draws
     the same tooltip in three backgrounds and three faces at once, which is the
     only honest way to show a choice normally seen one at a time. ]==]
MODULE_VARIANTS.tooltip = {
    "A mob: health, drops and drop rates",
    "Rare and better only",
    "An item, with what it is worth",
    "Any background and font you like",
}

MODULE_EXAMPLES.tooltip = function(pane, variant, label)
    local rareOnly = (variant == 2)
    local item = (variant == 3)

    --[==[ **Three of them side by side, each in its own look.**

         Backgrounds from black through the client's own brown to a light one,
         and a different face on each, because a font is judged against the
         colour behind it rather than on its own. Marked as showing their own
         look so the shared redraw leaves them alone. ]==]
    if variant == 4 then
        local LOOKS = {
            { "Dark", { 0.03, 0.03, 0.04, 0.95 }, 1 },
            { "The client's own", { 0.10, 0.06, 0.02, 0.92 }, 2 },
            { "Light", { 0.55, 0.55, 0.60, 0.90 }, 3 },
        }

        for i = 1, table.getn(LOOKS) do
            local look = LOOKS[i]

            local box = CreateFrame("Frame", nil, pane)
            box:SetWidth(150)
            box:SetHeight(96)
            box:SetPoint("TOP", pane, "TOP", (i - 2) * 158, -20)

            if box.SetBackdrop then
                box:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 14,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 },
                })

                box:SetBackdropColor(look[2][1], look[2][2], look[2][3], look[2][4])
            end

            local name = exText(box, "GameFontNormalSmall", "Greater Lava Spider")
            name:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -8)
            name:SetTextColor(0.85, 0.25, 0.25)

            local level = exText(box, "GameFontHighlightSmall", "Level 47 Beast")
            level:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)

            local drop = exText(box, "GameFontHighlightSmall", "Drops: 64 / 88")
            drop:SetPoint("TOPLEFT", level, "BOTTOMLEFT", 0, -3)
            drop:SetTextColor(0.45, 0.65, 0.95)

            --[[ A different face on each, applied here and left alone by the
                 redraw -- the whole point is that they differ. ]]--
            local face = OB.fontPaths[look[3]] or OB.fontPaths[1]

            for _, line in ipairs({ name, level, drop }) do
                if face then line:SetFont(face, 11) end
                line.exOwnLook = true
            end

            local caption = exText(pane, "GameFontDisableSmall", look[1])
            caption:SetPoint("TOP", box, "BOTTOM", 0, -4)
        end

        exCaption(pane, label or "The background and the font are both yours")
        return
    end

    local tip = exPanel(pane, 330, item and 168 or 186)
    tip:SetPoint("CENTER", pane, "CENTER", 0, 12)

    if item then
        local LINES = {
            { "Thunderfury, Blessed Blade", "quality", 5 },
            { "Binds when picked up", "grey" },
            { "Main Hand              Sword", "white" },
            { "44 - 115 Damage       Speed 1.90", "white" },
            { "+5 Agility", "green" },
            { "Chance on hit: Blasts your enemy", "green" },
            { "Sells for 12g 40s", "grey" },
            { "Drops in Molten Core -- 0.04%", "rate" },
        }

        local y = 10

        for i = 1, table.getn(LINES) do
            local line = exText(tip,
                    i == 1 and "GameFontNormal" or "GameFontHighlightSmall",
                    LINES[i][1])
            line:SetPoint("TOPLEFT", tip, "TOPLEFT", 10, -y)

            if LINES[i][2] == "quality" then
                line:SetTextColor(exQuality(LINES[i][3]))
            elseif LINES[i][2] == "grey" then
                line:SetTextColor(0.6, 0.6, 0.6)
            elseif LINES[i][2] == "green" then
                line:SetTextColor(0.2, 0.9, 0.2)
            elseif LINES[i][2] == "rate" then
                line:SetTextColor(1, 0.5, 0.15)
            end

            y = y + (i == 1 and 22 or 17)
        end

        exCaption(pane, label or "The client's tooltip, restyled, and told what "
                .. "the item is worth")
        return
    end

    --[==[ **The health bar sits on top of the tooltip**, not under it: it is the
         first thing read and the client puts nothing there at all. The numbers
         are inside it because a bar with no number is a proportion, and what a
         hunter wants is the number. ]==]
    local health = exBar(tip, 318, 15, 100, 0.65, 0.15, 0.15)
    health:SetPoint("BOTTOM", tip, "TOP", 0, 2)
    exCycle(health, 0)

    local hpText = exText(health, "GameFontHighlightSmall", "3.02k / 3.02k (100%)")
    hpText:SetPoint("CENTER", health, "CENTER", 0, 0)

    local name = exText(tip, "GameFontNormalLarge", "Greater Lava Spider")
    name:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -10)
    name:SetTextColor(0.85, 0.25, 0.25)

    local level = exText(tip, "GameFontHighlightSmall", "Level")
    level:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -34)

    --[[ The level in the client's own difficulty colour, which is the one piece
         of a mob tooltip somebody reads before deciding to pull it. ]]--
    local number = exText(tip, "GameFontHighlightSmall", "47")
    number:SetPoint("LEFT", level, "RIGHT", 4, 0)
    number:SetTextColor(0.55, 0.55, 0.55)

    local kind = exText(tip, "GameFontHighlightSmall", "Beast")
    kind:SetPoint("LEFT", number, "RIGHT", 4, 0)

    local drops = exText(tip, "GameFontNormalSmall", "Drops: 64 / 88")
    drops:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -52)
    drops:SetTextColor(0.45, 0.65, 0.95)

    --[==[ **What it drops, with the rate beside each line.**

         Quality colours on the names and the rate in its own colour, because
         they are two different facts and reading a list where they share one is
         reading it twice.

         The second arrangement is the same mob with the filter set to rare and
         better -- which is the setting somebody turns on the first time a
         tooltip covers half the screen with grey cloth. ]==]
    local DROPS = {
        { "[Reinforced Steel Lockbox]", 2, "0.12%" },
        { "[Pure Moonstone]", 2, "0.05%" },
        { "[Pattern: Red Mageweave Vest]", 2, "0.02%" },
        { "[Pattern: White Bandit Mask]", 3, "0.02%" },
        { "[Pattern: Red Mageweave Gloves]", 4, "0.02%" },
    }

    local shown, y = 0, 72

    for i = 1, table.getn(DROPS) do
        local row = DROPS[i]

        if not rareOnly or row[2] >= 3 then
            shown = shown + 1

            local line = exText(tip, "GameFontHighlightSmall", row[1])
            line:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -y)
            line:SetTextColor(exQuality(row[2]))

            local rate = exText(tip, "GameFontHighlightSmall", "[" .. row[3] .. "]")
            rate:SetPoint("LEFT", line, "RIGHT", 4, 0)
            rate:SetTextColor(1, 0.45, 0.15)

            y = y + 19
        end
    end

    if rareOnly then
        local hidden = exText(tip, "GameFontDisableSmall",
                "3 commons hidden by the quality filter")
        hidden:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -y)
        y = y + 19
    end

    local hint = exText(tip, "GameFontNormalSmall",
            "Ctrl+Alt: open full item database")
    hint:SetPoint("TOPLEFT", tip, "TOPLEFT", 12, -y - 4)
    hint:SetTextColor(0.45, 0.65, 0.95)

    exCaption(pane, label or "A health bar, what it drops, and how often")
end

--[==[ **The character sheet, which is the module rather than a row of gear.**

     The old picture was twelve tinted squares and a line of text, and the line
     was a claim: "Attack Power 812  Crit 24.4%  Hit +6%" written as flat text
     under some icons. What this module actually draws is two boxes with a
     dropdown header on each, and the stats vanilla knows and does not show.

     So the picture is those boxes, with the same numbers the module reads --
     and the three variations are the three questions somebody opens the sheet
     to answer: what am I, what do I hit for, and what happens when something
     hits me. ]==]
MODULE_VARIANTS.characterpanel = {
    "Base stats beside melee",
    "Melee beside ranged",
    "Defense, and gear coloured by quality",
}

--[[ The rows each pane shows, written here rather than read from the module:
     the walkthrough runs before anybody has a character worth showing, and a
     picture of a level one's empty sheet argues for nothing. ]]--
local EX_STAT_GROUPS = {
    base = { "Base Stats", {
        { "Strength", "144" }, { "Agility", "311" }, { "Stamina", "183" },
        { "Intellect", "37" }, { "Spirit", "59" }, { "Armor", "1684" },
    } },

    melee = { "Melee", {
        { "Wep Skill", "306 | 306" }, { "Damage", "95-129" },
        { "Speed", "1.19 | 1.19" }, { "Power", "634" },
        { "Hit Rating", "9.00%" }, { "Crit Chance", "22.96%" },
    } },

    ranged = { "Ranged", {
        { "Wep Skill", "305" }, { "Damage", "123-172" },
        { "Speed", "2.90" }, { "Power", "440" },
        { "Crit Chance", "18.40%" },
    } },

    defense = { "Defense", {
        { "Armor", "1684" }, { "Defense", "300" }, { "Dodge", "14.50%" },
        { "Parry", "12.25%" }, { "Block", "0.00%" },
    } },
}

MODULE_EXAMPLES.characterpanel = function(pane, variant, label)
    local pair = { "base", "melee" }
    if variant == 2 then pair = { "melee", "ranged" } end
    if variant == 3 then pair = { "defense", "base" } end

    --[==[ **A pane, with its header as a control.**

         The arrow is on it because the header *is* the dropdown: four groups in
         the room for two is what makes the sheet fit, and a header that only
         labelled would be a caption pretending to be a menu. ]==]
    local function statPane(key, x)
        local group = EX_STAT_GROUPS[key]
        local rows = group[2]

        local box = exPanel(pane, 150, 30 + (table.getn(rows) * 16))
        box:SetPoint("TOP", pane, "TOP", x, -18)

        local title = exText(box, "GameFontNormalSmall", group[1])
        title:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -7)

        local arrow = box:CreateTexture(nil, "OVERLAY")
        arrow:SetWidth(14)
        arrow:SetHeight(14)
        arrow:SetPoint("TOPRIGHT", box, "TOPRIGHT", -6, -6)
        arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")

        for i = 1, table.getn(rows) do
            local y = -26 - ((i - 1) * 16)

            local name = exText(box, "GameFontHighlightSmall", rows[i][1] .. ":")
            name:SetPoint("TOPLEFT", box, "TOPLEFT", 8, y)

            --[[ The values in the client's own green, which is what makes the
                 column read as numbers rather than as sentences. ]]--
            local value = exText(box, "GameFontHighlightSmall", rows[i][2])
            value:SetPoint("TOPRIGHT", box, "TOPRIGHT", -8, y)
            value:SetTextColor(0.30, 0.85, 0.35)
        end

        return box
    end

    statPane(pair[1], -82)
    statPane(pair[2], 82)

    --[==[ **And the gear under them, coloured by quality.**

         The other half of this module: the slot's own ring tinted by the item's
         quality, with the brightening pass over it -- a multiply against dark
         metal is dark, which is what "the borders are a bit dark" was. ]==]
    local SLOTS = { 4, 3, 4, 2, 5, 3, 4, 1, 0, 2 }

    local row = CreateFrame("Frame", nil, pane)
    row:SetWidth(10 * 30)
    row:SetHeight(28)
    row:SetPoint("BOTTOM", pane, "BOTTOM", 0, 16)

    for i = 1, 10 do
        local slot = exIcon(row, 26, exIconAt(i))
        slot:SetPoint("LEFT", row, "LEFT", (i - 1) * 30, 0)

        local r, g, b = exQuality(SLOTS[i])

        --[[ Two passes, the way the module does it: the ring tinted, and an
             additive glow over it so the colour is visible on dark art. ]]--
        local edge = slot:CreateTexture(nil, "OVERLAY")
        edge:SetPoint("TOPLEFT", slot, "TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1)
        edge:SetTexture(r, g, b)
        edge:SetAlpha(0.55)

        if SLOTS[i] > 1 then
            local glow = slot:CreateTexture(nil, "OVERLAY")
            glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            glow:SetBlendMode("ADD")
            glow:SetWidth(44)
            glow:SetHeight(44)
            glow:SetPoint("CENTER", slot, "CENTER", 0, 0)
            glow:SetVertexColor(r, g, b)
            glow:SetAlpha(0.55)
        end

        slot.icon:SetDrawLayer("OVERLAY")
    end

    exCaption(pane, label or "The stats the client hides, and gear by quality")
end

--[[ Bagnon's shape, because that is what this module is now: one grid, every
     slot, a search box and the money under it. ]]--
--[==[ **A bag is a grid, a wider grid, or a grid with the glow taken off.**

     The width is a real decision -- ten across on a small screen is a different
     window from sixteen -- and the quality glow is the one thing somebody
     either loves or wants gone immediately. Both are shown rather than
     described, because "coloured borders by item quality" is a sentence and
     this is a picture. ]==]
MODULE_VARIANTS.bags = {
    "Every bag as one grid, quality borders on",
    "Wider, for a bigger screen",
    "No quality borders",
}

MODULE_EXAMPLES.bags = function(pane, variant, label)
    local COLS, ROWS, SIZE, PITCH = 10, 4, 32, 35
    if variant == 2 then COLS, ROWS = 16, 3 end

    local glowing = (variant ~= 3)

    local win = exPanel(pane, (COLS * PITCH) + 24, (ROWS * PITCH) + 62)
    win:SetPoint("CENTER", pane, "CENTER", 0, 16)

    local search = exText(win, "GameFontDisableSmall", "Search")
    search:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -10)

    local title = exText(win, "GameFontNormalSmall", "Equadis's Inventory")
    title:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -10)

    local QUALITY = { [3] = 4, [7] = 3, [12] = 2, [19] = 5, [26] = 4, [31] = 3 }
    local slots = COLS * ROWS
    local filled = math.floor(slots * 0.55)

    for i = 1, slots do
        local col = mod(i - 1, COLS)
        local row = math.floor((i - 1) / COLS)

        local slot = exIcon(win, SIZE,
                i <= filled and exIconAt(i)
                    or "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        slot:SetPoint("TOPLEFT", win, "TOPLEFT",
                12 + (col * PITCH), -30 - (row * PITCH))

        --[[ The quality glow, which is Bagnon's and is the one thing that makes
             a full bag readable at a glance -- and the one thing somebody may
             want gone, which is why there is a picture without it. ]]--
        if glowing and QUALITY[i] and i <= filled then
            local glow = slot:CreateTexture(nil, "OVERLAY")
            glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            glow:SetBlendMode("ADD")
            glow:SetWidth(58)
            glow:SetHeight(58)
            glow:SetPoint("CENTER", slot, "CENTER", 0, 0)
            glow:SetVertexColor(exQuality(QUALITY[i]))
            glow:SetAlpha(0.5)
        end
    end

    local money = exText(win, "GameFontNormalSmall", "538g  25s  93c")
    money:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 8)

    exCaption(pane, label or "Every bag as one grid, with search and a clean-up")
end

--[==[ **One picture for two modules**, which is the argument for them sharing a
     step: the coloured name with a level in front of it *is* the roster, drawn
     by chat. Neither half is worth much alone. ]==]
--[==[ **The same five lines, with and without what this module adds.**

     Everything here is a *change to text you were going to read anyway*, and
     the honest way to show that is the same window twice: the stamp in front,
     the channel shortened, the level and the class colour on the name -- and
     then the plain client version, which is what saying no looks like. ]==]
MODULE_VARIANTS.chat = {
    "Timestamps, class colours, levels",
    "The client's own, for comparison",
    "Short channel names, for a busy window",
}

MODULE_EXAMPLES.chat = function(pane, variant, label)
    local plain = (variant == 2)
    local short = (variant == 3)

    local LINES = {
        { "[19:04]", "[2. Trade]", "Alecander", "MAGE", 60,
          "WTS [Arcanite Bar] x5" },
        { "[19:04]", "[Guild]", "Grimtusk", "WARRIOR", 60,
          "anyone up for Strat?" },
        { "[19:05]", "[Party]", "Sylvie", "PRIEST", 58,
          "give me a second to drink" },
        { "[19:05]", "[Whisper]", "Holywrath", "PALADIN", 41,
          "invite?" },
        { "[19:06]", "[1. General]", "Dunkel", nil, nil,
          "where is the flight master" },
    }

    --[[ What a shortened channel reads as: the same tag with the words taken
         out of it, which is the setting somebody in a busy Trade channel turns
         on and never turns off. ]]--
    local SHORT = {
        ["[2. Trade]"] = "[2]",
        ["[Guild]"] = "[G]",
        ["[Party]"] = "[P]",
        ["[Whisper]"] = "[W]",
        ["[1. General]"] = "[1]",
    }

    local box = exPanel(pane, 460, 150)
    box:SetPoint("CENTER", pane, "CENTER", 0, 22)

    for i = 1, table.getn(LINES) do
        local L = LINES[i]
        local y = -8 - ((i - 1) * 26)

        local anchor, gap = box, 8

        --[[ No stamp at all in the client's own version, rather than a blank
             one -- the room it takes back is part of what is being shown. ]]--
        if not plain then
            local stamp = exText(box, "GameFontDisableSmall", L[1])
            stamp:SetPoint("TOPLEFT", box, "TOPLEFT", 8, y)
            anchor, gap = stamp, 4
        end

        local tag = L[2]
        if short then tag = SHORT[tag] or tag end

        local channel = exText(box, "GameFontNormalSmall", tag)

        if anchor == box then
            channel:SetPoint("TOPLEFT", box, "TOPLEFT", gap, y)
        else
            channel:SetPoint("LEFT", anchor, "RIGHT", gap, 0)
        end

        channel:SetTextColor(0.55, 0.75, 1)

        --[==[ The level in the client's own difficulty colours and the name in
             its class colour -- two facts in the space of one, which is the
             whole of what the scanner buys. The last line is somebody nobody
             has scanned yet: plain, which is also what it looks like before the
             roster has heard of them. ]==]
        local shown = L[3]
        if not plain and L[5] then shown = L[5] .. ":" .. L[3] end

        local who = exText(box, "GameFontNormalSmall", shown)
        who:SetPoint("LEFT", channel, "RIGHT", 4, 0)

        if L[4] and not plain then
            who:SetTextColor(exClass(L[4]))
        else
            who:SetTextColor(0.75, 0.75, 0.75)
        end

        local said = exText(box, "GameFontHighlightSmall", L[6])
        said:SetPoint("LEFT", who, "RIGHT", 5, 0)
    end

    exCaption(pane, label or "Timestamps, channel names, and who is talking")
end

--[==[ **The roster is not the chat window**, and sharing chat's picture said it
     was. What this module does is remember who somebody is -- class, level,
     guild, where they were -- from every line the client hands it, and hand it
     back on a tooltip or a `/who` that already knows the answer.

     So the picture is that: names in their class colours with what is known
     about them, which is the thing chat's picture could not show. ]==]
MODULE_EXAMPLES.roster = function(pane, variant, label)
    local box = exPanel(pane, 420, 150)
    box:SetPoint("CENTER", pane, "CENTER", 0, 14)

    local head = exText(box, "GameFontNormal", "Players seen: 2,481")
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)

    local WHO = {
        { "Sylvie",   "PRIEST",  60, "Stormwind City", "Blackrock Syndicate" },
        { "Equadis",  "PALADIN", 60, "Ironforge",      "Blackrock Syndicate" },
        { "Grimtusk", "WARRIOR", 58, "Un'Goro Crater", "" },
        { "Mirelle",  "MAGE",    47, "Desolace",       "Wanderers" },
    }

    for i = 1, table.getn(WHO) do
        local row = WHO[i]
        local y = -34 - ((i - 1) * 26)

        local name = exText(box, "GameFontNormalSmall", row[1])
        name:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)
        name:SetTextColor(exClass(row[2]))

        local level = exText(box, "GameFontHighlightSmall", "level " .. row[3])
        level:SetPoint("TOPLEFT", box, "TOPLEFT", 110, y)

        local where = exText(box, "GameFontDisableSmall", row[4])
        where:SetPoint("TOPLEFT", box, "TOPLEFT", 190, y)

        --[[ The guild is what makes a name worth remembering across a session,
             so it is on the row rather than in a tooltip nobody opens. ]]--
        if row[5] ~= "" then
            local guild = exText(box, "GameFontDisableSmall", "<" .. row[5] .. ">")
            guild:SetPoint("TOPLEFT", box, "TOPLEFT", 300, y)
        end
    end

    exCaption(pane, label or "Learned from chat, /who and the world")
end

--[==[ **Square or round is the first thing anybody changes about a minimap**,
     and the group markers are the thing they keep it for. Both, plus the size
     it can be dragged to, are separate answers -- and the map that stays open
     while you walk is a different feature again. ]==]
MODULE_VARIANTS.map = {
    "Square, with the group on it in class colours",
    "Round, the way the client draws it",
    "Larger, for somebody who navigates by it",
}

MODULE_EXAMPLES.map = function(pane, variant, label)
    local round = (variant == 2)
    local size = (variant == 3) and 190 or 150

    local mini = exPanel(pane, size, size)
    mini:SetPoint("CENTER", pane, "CENTER", -110, 16)

    --[[ The round one is drawn as the client's own art rather than as a
         panel with the corners argued away: a circle is what it is. ]]--
    if round then
        local face = mini:CreateTexture(nil, "ARTWORK")
        face:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        face:SetPoint("CENTER", mini, "CENTER", 0, 0)
        face:SetWidth(size - 12)
        face:SetHeight(size - 12)
        face:SetVertexColor(0.18, 0.20, 0.18, 1)

        local ring = mini:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetPoint("CENTER", mini, "CENTER", 0, 0)
        ring:SetWidth(size + 14)
        ring:SetHeight(size + 14)
    end

    --[==[ **The bar above the map, which is what this module actually draws.**

         Where you are and what time it is, in two boxes above the map rather
         than welded into its art, with the two buttons about the map on the
         right-hand end -- the one that puts it away, and the one that opens the
         drawer of gathered addon icons.

         Drawn here because the preview had the zone name written across the top
         of the map and the time across the bottom, which is where the *client*
         puts them and is exactly what this module stopped doing. ]==]
    local bar = exPanel(mini, size, 16)
    bar:SetPoint("BOTTOM", mini, "TOP", 0, 3)

    local zone = exText(bar, "GameFontNormalSmall", "Elwynn Forest")
    zone:SetPoint("LEFT", bar, "LEFT", 6, 0)

    --[[ Group markers in class colours, which is the part of this module that
         took longest to get right and is the part somebody notices. ]]--
    local MARKS = { { 20, 18, "PRIEST" }, { -28, -10, "WARRIOR" },
                    { 34, -34, "MAGE" }, { -12, 40, "PALADIN" } }

    --[[ A round map is smaller than the square it is drawn in, so the markers
         come in with it rather than sitting outside the ring. ]]--
    local reach = round and 0.72 or 1

    for i = 1, table.getn(MARKS) do
        local dot = mini:CreateTexture(nil, "OVERLAY")
        dot:SetWidth(11)
        dot:SetHeight(11)
        dot:SetPoint("CENTER", mini, "CENTER",
                MARKS[i][1] * reach, MARKS[i][2] * reach)
        dot:SetTexture(exClass(MARKS[i][3]))
    end

    local you = mini:CreateTexture(nil, "OVERLAY")
    you:SetWidth(14)
    you:SetHeight(14)
    you:SetPoint("CENTER", mini, "CENTER", 0, 0)
    you:SetTexture(1, 1, 1)

    local clock = exText(bar, "GameFontHighlightSmall", "19:06")
    clock:SetPoint("RIGHT", bar, "RIGHT", -40, 0)

    --[[ The two buttons, as the two squares they read as at this size. ]]--
    for i = 1, 2 do
        local button = bar:CreateTexture(nil, "OVERLAY")
        button:SetWidth(11)
        button:SetHeight(11)
        button:SetPoint("RIGHT", bar, "RIGHT", -5 - ((i - 1) * 15), 0)
        button:SetTexture(0.62, 0.62, 0.66)
    end

    local world = exPanel(pane, 240, 150)
    world:SetPoint("CENTER", pane, "CENTER", 90, 16)

    local wl = exText(world, "GameFontNormalSmall", "World map, at any size")
    wl:SetPoint("TOP", world, "TOP", 0, -8)

    local note = exText(world, "GameFontHighlightSmall",
            "walk with it open")
    note:SetPoint("CENTER", world, "CENTER", 0, 0)
    note:SetTextColor(0.7, 0.7, 0.7)

    --[[ The caption the step passed in, or this one. It used to read `label`
         after a local of the same name had taken the zone text's place, so the
         step's own caption could never win and a font string was handed to a
         function that wanted a string. ]]--
    exCaption(pane, label or "A minimap with the group on it, and a map you "
            .. "can walk with")
end

--[==[ **The arrow you follow, and the pin you set.**

     Two ends of one feature: ctrl-clicking the map drops a pin, and the arrow
     at the top of the screen points at it from wherever you are. Neither picture
     is the feature on its own. ]==]
MODULE_VARIANTS.waypoints = {
    "An arrow that keeps pointing, with the yards left",
    "Set one by ctrl-clicking the map",
}

MODULE_EXAMPLES.waypoints = function(pane, variant, label)
    if variant == 2 then
        local map = exPanel(pane, 300, 170)
        map:SetPoint("CENTER", pane, "CENTER", 0, 20)

        local zone = exText(map, "GameFontNormalSmall", "Un'Goro Crater")
        zone:SetPoint("TOP", map, "TOP", 0, -8)

        --[[ The pin where it was dropped, which is the half the map was missing
             entirely: a coordinate meant something and the one screen where it
             does showed nothing at all. ]]--
        local pin = map:CreateTexture(nil, "OVERLAY")
        pin:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
        pin:SetWidth(18)
        pin:SetHeight(18)
        pin:SetPoint("CENTER", map, "CENTER", 46, 18)
        pin:SetVertexColor(1, 0.82, 0)

        local at = exText(map, "GameFontHighlightSmall", "Golakka Hot Springs")
        at:SetPoint("TOP", pin, "BOTTOM", 0, -2)

        local you = map:CreateTexture(nil, "OVERLAY")
        you:SetWidth(12)
        you:SetHeight(12)
        you:SetPoint("CENTER", map, "CENTER", -40, -30)
        you:SetTexture(1, 1, 1)

        local note = exText(pane, "GameFontDisableSmall",
                "Ctrl-click anywhere on the map, or /way 42 61")
        note:SetPoint("TOP", map, "BOTTOM", 0, -8)

        exCaption(pane, label or "A pin on the map, and a list you can go back to")
        return
    end

    local arrow = pane:CreateTexture(nil, "ARTWORK")
    arrow:SetWidth(72)
    arrow:SetHeight(72)
    arrow:SetPoint("CENTER", pane, "CENTER", 0, 46)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow.exOwnLook = true

    local dist = exText(pane, "GameFontNormalLarge", "142 yards")
    dist:SetPoint("TOP", arrow, "BOTTOM", 0, -8)
    dist:SetTextColor(1, 0.82, 0)

    local where = exText(pane, "GameFontHighlightSmall",
            "Jangolode Mine, Westfall")
    where:SetPoint("TOP", dist, "BOTTOM", 0, -4)

    exCaption(pane, label or "Click the map, follow the arrow")
end

--[==[ **A search, and the memory behind it.**

     The rows are what a scan found; the second column is what the same item went
     for last time, which is the whole reason to run a scanner rather than read
     the auction house. The second arrangement is that memory on its own -- what
     this module is when the auction house is shut. ]==]
MODULE_VARIANTS.auction = {
    "What is listed, against what it usually goes for",
    "The prices it has learned",
}

MODULE_EXAMPLES.auction = function(pane, variant, label)
    if variant == 2 then
        local box = exPanel(pane, 360, 150)
        box:SetPoint("CENTER", pane, "CENTER", 0, 22)

        local head = exText(box, "GameFontNormalSmall", "Prices learned: 4,182")
        head:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)

        local KNOWN = {
            { "Arcanite Bar", 4, "34g 20s", "seen 41 times" },
            { "Black Lotus", 4, "68g 00s", "seen 9 times" },
            { "Dreamfoil", 2, "9g 10s", "seen 220 times" },
            { "Thorium Ore", 2, "1g 40s", "seen 314 times" },
            { "Larval Acid", 1, "13g 75s", "seen 27 times" },
        }

        for i = 1, table.getn(KNOWN) do
            local y = -30 - ((i - 1) * 22)

            local icon = exIcon(box, 18, exIconAt(i + 5))
            icon:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)

            local name = exText(box, "GameFontNormalSmall", KNOWN[i][1])
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetTextColor(exQuality(KNOWN[i][2]))

            local price = exText(box, "GameFontHighlightSmall", KNOWN[i][3])
            price:SetPoint("TOPRIGHT", box, "TOPRIGHT", -80, y)

            local seen = exText(box, "GameFontDisableSmall", KNOWN[i][4])
            seen:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, y)
        end

        exCaption(pane, label or "Learned from every scan, and read back on tooltips")
        return
    end

    local ROWS = {
        { "Arcanite Bar", 4, "x5", "38g 00s", "34g 20s" },
        { "Black Lotus", 4, "x1", "72g 50s", "68g 00s" },
        { "Dreamfoil", 2, "x20", "9g 40s", "9g 10s" },
        { "Larval Acid", 1, "x10", "14g 00s", "13g 75s" },
    }

    local box = exPanel(pane, 420, 132)
    box:SetPoint("CENTER", pane, "CENTER", 0, 24)

    local head = exText(box, "GameFontDisableSmall",
            "Item                          Buyout        Seen before")
    head:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)

    for i = 1, table.getn(ROWS) do
        local y = -26 - ((i - 1) * 24)

        local icon = exIcon(box, 20, exIconAt(i + 5))
        icon:SetPoint("TOPLEFT", box, "TOPLEFT", 10, y)

        local name = exText(box, "GameFontNormalSmall",
                ROWS[i][1] .. " " .. ROWS[i][3])
        name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        name:SetTextColor(exQuality(ROWS[i][2]))

        local price = exText(box, "GameFontHighlightSmall", ROWS[i][4])
        price:SetPoint("TOPLEFT", box, "TOPLEFT", 250, y - 2)

        local was = exText(box, "GameFontDisableSmall", ROWS[i][5])
        was:SetPoint("TOPLEFT", box, "TOPLEFT", 340, y - 2)
    end

    exCaption(pane, label or "What things go for, remembered between scans")
end

--[==[ **What an item is, and where you find one.**

     The database answers two different questions and they want different
     pictures: hovering something and being told what drops it, and searching for
     a name and being given a list of places. ]==]
MODULE_VARIANTS.itemdatabase = {
    "What drops it, on the tooltip",
    "Search for anything, by name",
}

MODULE_EXAMPLES.itemdatabase = function(pane, variant, label)
    if variant == 2 then
        local box = exPanel(pane, 380, 156)
        box:SetPoint("CENTER", pane, "CENTER", 0, 20)

        local field = exText(box, "GameFontNormalSmall", "Search:  mageweave")
        field:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -10)

        local HITS = {
            { "Bolt of Mageweave", 1, "crafted -- Tailoring 175" },
            { "Mageweave Cloth", 1, "drops from 214 creatures" },
            { "Pattern: Red Mageweave Vest", 2, "Gordok Enforcer -- 0.02%" },
            { "White Bandit Mask", 2, "crafted -- Tailoring 205" },
            { "Mageweave Bag", 2, "crafted -- Tailoring 195" },
        }

        for i = 1, table.getn(HITS) do
            local y = -32 - ((i - 1) * 24)

            local icon = exIcon(box, 20, exIconAt(i + 2))
            icon:SetPoint("TOPLEFT", box, "TOPLEFT", 12, y)

            local name = exText(box, "GameFontNormalSmall", HITS[i][1])
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetTextColor(exQuality(HITS[i][2]))

            local where = exText(box, "GameFontDisableSmall", HITS[i][3])
            where:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, y)
        end

        exCaption(pane, label or "Ctrl+Alt on a tooltip, or /db anything")
        return
    end

    local box = exPanel(pane, 400, 140)
    box:SetPoint("CENTER", pane, "CENTER", 0, 22)

    local icon = exIcon(box, 44, exIconAt(1))
    icon:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -12)

    local name = exText(box, "GameFontNormal", "Staff of Jordan")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    name:SetTextColor(exQuality(3))

    local LINES = {
        "Dropped by: Archmage Arugal",
        "Shadowfang Keep",
        "Seen 3 times, last on 2 September",
        "Vendors for 4g 21s",
    }

    for i = 1, table.getn(LINES) do
        local line = exText(box, "GameFontHighlightSmall", LINES[i])
        line:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -66 - ((i - 1) * 17))
        if i >= 3 then line:SetTextColor(0.65, 0.65, 0.65) end
    end

    exCaption(pane, label or "Where a thing came from and what it is worth")
end

--[==[ **Two pictures because it is two kinds of thing.**

     The vendor is where most of it happens and is worth showing as a scene. The
     rest is a list of small decisions -- rolling, accepting, confirming -- each
     of which is one switch, and a list is the honest shape for that. ]==]
MODULE_VARIANTS.qol = {
    "At a vendor: sell the greys, repair everything",
    "The small things, each with its own switch",
}

MODULE_EXAMPLES.qol = function(pane, variant, label)
    if variant == 2 then
        local box = exPanel(pane, 380, 168)
        box:SetPoint("CENTER", pane, "CENTER", 0, 18)

        local SWITCHES = {
            { "Auto-roll greed on greens", "on" },
            { "Accept a resurrection", "on" },
            { "Accept a summon", "off" },
            { "Skip the destroy confirmation", "off" },
            { "Colour item borders by quality", "on" },
            { "Turn the character model by dragging", "on" },
        }

        for i = 1, table.getn(SWITCHES) do
            local y = -14 - ((i - 1) * 24)

            --[[ A tick and a cross rather than the words, because a list of
                 switches is read down the left edge. ]]--
            local mark = exText(box, "GameFontNormalSmall",
                    (SWITCHES[i][2] == "on") and "on" or "off")
            mark:SetPoint("TOPLEFT", box, "TOPLEFT", 14, y)

            if SWITCHES[i][2] == "on" then
                mark:SetTextColor(0.30, 0.85, 0.35)
            else
                mark:SetTextColor(0.55, 0.55, 0.55)
            end

            local name = exText(box, "GameFontHighlightSmall", SWITCHES[i][1])
            name:SetPoint("TOPLEFT", box, "TOPLEFT", 46, y)
        end

        exCaption(pane, label or "Every one of them is a switch you can find")
        return
    end

    local box = exPanel(pane, 400, 150)
    box:SetPoint("CENTER", pane, "CENTER", 0, 22)

    local title = exText(box, "GameFontNormalSmall", "At a vendor")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -8)

    local sell = exIcon(box, 34, "Interface\\Icons\\INV_Misc_Coin_02")
    sell:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -30)

    local sellText = exText(box, "GameFontHighlightSmall",
            "Sell 7 grey items for 3g 12s")
    sellText:SetPoint("LEFT", sell, "RIGHT", 8, 0)

    local repair = exIcon(box, 34, "Interface\\Icons\\Trade_BlackSmithing")
    repair:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -72)

    local repairText = exText(box, "GameFontHighlightSmall",
            "Repair everything, 11g 40s")
    repairText:SetPoint("LEFT", repair, "RIGHT", 8, 0)

    local more = exText(box, "GameFontDisableSmall",
            "and auto-roll, auto-accept, item quality borders, and more")
    more:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 8)

    exCaption(pane, label or "The small things, each with its own switch")
end

-- ---------------------------------------------------------------------------
-- 3. the look
-- ---------------------------------------------------------------------------

step({
    id = "look",
    title = "How should bars look?",
    body = "This is the bar texture and the font everything shares. "
            .. "Individual subsystems can differ later; most people never "
            .. "need them to.",

    example = function(pane)
        --[==[ **The shapes a bar actually takes, rather than one specimen.**

             This was a single three-hundred pixel bar, and a texture judged on
             one of those is judged on the wrong thing: what the choice has to
             survive is a *tall* bar with numbers written across it, a thin one
             with a spark travelling along it, a row of small squares, and a
             panel edge beside all three. A gradient that reads beautifully at
             twenty-six pixels can be a smear at eight.

             So the pane shows the bar family this addon actually draws --
             resource, swing, health, combo points -- in whatever texture and
             font is chosen, and every one of them redraws as the choice moves.
             The layouts are the ones from the HUD rather than invented ones:
             see `MODULE_EXAMPLES.unitframes` for the same rule applied to a
             module's own picture. ]==]
        local resource = exBar(pane, 320, 26, 72, 0.20, 0.45, 0.85)
        resource:SetPoint("TOP", pane, "TOP", 0, -16)

        local resourceText = exText(resource, "GameFontHighlight", "4210 / 5850")
        resourceText:SetPoint("CENTER", resource, "CENTER", 0, 0)

        --[[ The ticker, which is the one piece of the resource bar that is
             about *time* rather than about a quantity -- and the reason a
             texture with a hard edge reads differently here. ]]--
        local spark = resource:CreateTexture(nil, "OVERLAY")
        spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        spark:SetBlendMode("ADD")
        spark:SetWidth(16)
        spark:SetHeight(38)
        spark:SetPoint("CENTER", resource, "LEFT", 320 * 0.72, 0)

        local swing = exBar(pane, 320, 10, 38, 0.85, 0.70, 0.20)
        swing:SetPoint("TOP", resource, "BOTTOM", 0, -6)

        local swingText = exText(pane, "GameFontDisableSmall", "1.4s")
        swingText:SetPoint("LEFT", swing, "RIGHT", 6, 0)

        local health = exBar(pane, 200, 18, 54, 0.15, 0.62, 0.15)
        health:SetPoint("TOPLEFT", swing, "BOTTOMLEFT", 0, -10)

        local healthText = exText(health, "GameFontHighlightSmall", "54%")
        healthText:SetPoint("CENTER", health, "CENTER", 0, 0)

        --[[ Five small squares in the same texture, because the same choice has
             to survive being cut to eleven pixels. ]]--
        for i = 1, 5 do
            local point = exBar(pane, 20, 11, 100,
                    1.00, 0.85 - (i * 0.06), 0.20)
            point:SetPoint("LEFT", health, "RIGHT", 6 + ((i - 1) * 24), 0)
        end

        --[==[ **And the window edge beside them**, which is the other half of
             the look: the border chosen on the panel is what every window this
             addon draws is wearing, and judging a texture without one next to
             it is judging half the screen. ]==]
        local box = exPanel(pane, 320, 46)
        box:SetPoint("TOP", health, "BOTTOM", 60, -12)

        local line = exText(box, "GameFontHighlightSmall",
                "Windows wear the same font")
        line:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -10)

        local second = exText(box, "GameFontDisableSmall",
                "and the border chosen on the options panel")
        second:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -4)

        exCaption(pane, "Every bar, every window, the same texture and font")
    end,

    controls = function(area, pane)
        local y = 0

        y = cycler(area, y, "Bar texture", OB.textures,
                function() return OB.profile.texture or 1 end,
                function(i) OB.profile.texture = i end,
                function() if pane.Redraw then pane.Redraw() end end)

        y = cycler(area, y, "Font", OB.fonts,
                function() return OB.profile.font or 1 end,
                function(i) OB.profile.font = i end,
                function() if pane.Redraw then pane.Redraw() end end)

        --[[ A cycler rather than a tick, because the outline is a weight now:
             none, thin, thick. Same widget as the two rows above it, so the
             preview above answers all three the same way. ]]--
        y = cycler(area, y, "Text outline", OB.fontOutlines,
                function() return tonumber(OB.profile.fontOutline) or 1 end,
                function(i) OB.profile.fontOutline = i end,
                function() if pane.Redraw then pane.Redraw() end end)
    end,
})

-- ---------------------------------------------------------------------------
-- 5. done
-- ---------------------------------------------------------------------------

step({
    id = "done",
    title = "That's it",
    body = "Everything else has a sensible default and is on the options "
            .. "panel when you want it -- /eq or the Interface menu.\n\n"
            .. "Two things worth knowing:\n\n"
            .. "Hold Control, Shift and Alt together to move anything on "
            .. "screen. Let go to put it back to normal.\n\n"
            .. "/eq profile export turns every setting into one code you can "
            .. "paste to somebody else, and import takes theirs.",

    example = function(pane)
        local text = OB.NewText(pane, "OVERLAY", "GameFontHighlightLarge")
        text:SetPoint("CENTER", pane, "CENTER", 0, 0)
        text:SetText("Ready")
    end,
})

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

function OB.SetupFrame()
    if OB.setupFrame then return OB.setupFrame end

    local frame = CreateFrame("Frame", "EquadisClassicOverhaulSetup", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetHeight(HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if OB.SkinWindow then OB.SkinWindow(frame, 0.97) end

    frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    frame:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)

    --[[ The pictures rotate while the window is open. See
         `OB.StepSetupVariant`. ]]--
    frame:SetScript("OnUpdate", function()
        EquadisClassicOverhaul.StepSetupVariant(this)
    end)

    frame.title = OB.NewText(frame, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -14)

    frame.progress = OB.NewText(frame, "OVERLAY", "GameFontDisableSmall")
    frame.progress:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -18)

    frame.body = OB.NewText(frame, "OVERLAY", "GameFontHighlight")
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -46)
    frame.body:SetWidth(WIDTH - 40)
    frame.body:SetJustifyH("LEFT")
    frame.body:SetJustifyV("TOP")

    --[==[ **The example and the controls are rebuilt per step, so both live on
         a frame that is thrown away rather than emptied.**

         1.12 has no way to destroy a frame, and no way to un-parent its
         regions either -- a font string made on a frame stays on it. Reusing
         one container across five steps means every step's leftovers are still
         drawn under the current one. A fresh child per step is the only shape
         that ends up with what the step asked for and nothing else; the old one
         is hidden and left for the garbage collector to ignore forever, which
         is a handful of frames per session. ]==]
    frame.paneHolder = CreateFrame("Frame", nil, frame)
    frame.paneHolder:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -140)
    frame.paneHolder:SetWidth(WIDTH - 40)
    frame.paneHolder:SetHeight(PANE_H)

    frame.areaHolder = CreateFrame("Frame", nil, frame)
    frame.areaHolder:SetPoint("TOPLEFT", frame.paneHolder, "BOTTOMLEFT", 0, -14)
    frame.areaHolder:SetWidth(WIDTH - 40)
    --[[ Whatever is left between the pane and the buttons. Three rows of
         controls at 28 apiece is the most any step asks for. ]]--
    frame.areaHolder:SetHeight(HEIGHT - PANE_H - 200)

    frame.back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.back:SetWidth(90)
    frame.back:SetHeight(24)
    frame.back:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 16)
    frame.back:SetText("Back")
    frame.back:SetScript("OnClick", function() OB.SetupStep(OB.setupAt - 1) end)
    if OB.SkinButton then OB.SkinButton(frame.back) end

    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next:SetWidth(90)
    frame.next:SetHeight(24)
    frame.next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 16)
    frame.next:SetScript("OnClick", function()
        if OB.setupAt >= table.getn(OB.setupSteps) then
            OB.FinishSetup()
        else
            OB.SetupStep(OB.setupAt + 1)
        end
    end)
    if OB.SkinButton then OB.SkinButton(frame.next) end

    --[[ Closing is finishing. There is no state to abandon -- every screen has
         already written what it changed -- so a close box that left the wizard
         waiting to reappear would be pretending otherwise. ]]--
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    frame.close:SetScript("OnClick", function() OB.FinishSetup() end)

    if UISpecialFrames then
        table.insert(UISpecialFrames, "EquadisClassicOverhaulSetup")
    end

    OB.setupFrame = frame
    return frame
end

function OB.SetupStep(index)
    local frame = OB.SetupFrame()
    local count = table.getn(OB.setupSteps)

    if index < 1 then index = 1 end
    if index > count then index = count end

    OB.setupAt = index
    local def = OB.setupSteps[index]

    frame.title:SetText(def.title or "")
    frame.body:SetText(def.body or "")
    frame.progress:SetText(index .. " of " .. count)

    -- see the note on paneHolder: a new child each time, not a cleared one
    if frame.area then frame.area:Hide() end

    frame.area = CreateFrame("Frame", nil, frame.areaHolder)
    frame.area:SetAllPoints(frame.areaHolder)

    --[[ A step is entered at its first variation, and the clock starts from
         here rather than from wherever the last step left it -- so the first
         picture on a new screen gets its full turn. ]]--
    frame.variant = 1
    frame.variantAt = GetTime()

    OB.PaintSetupPane(frame, def)

    if def.controls then def.controls(frame.area, frame.pane) end

    if index > 1 then frame.back:Enable() else frame.back:Disable() end
    frame.next:SetText(index >= count and "Finish" or "Next")

    frame:Show()
    return true
end

--[==[ **One variation of the current step's picture, drawn into a fresh pane.**

     A new child frame each time rather than a cleared one, for the reason
     `paneHolder` gives: 1.12 has no way to delete a frame, and a pane that is
     re-used accumulates every region every variation ever drew.

     The dots under it say how many there are and which is up. Without them a
     picture that changes on its own reads as the interface glitching -- and with
     one variation there are no dots, because there is nothing to say. ]==]
function OB.PaintSetupPane(frame, def)
    if not frame or not def then return false end

    if frame.pane then frame.pane:Hide() end

    frame.pane = CreateFrame("Frame", nil, frame.paneHolder)
    frame.pane:SetAllPoints(frame.paneHolder)

    local names = def.variants or {}
    local count = table.getn(names)
    local at = frame.variant or 1

    if count > 0 and at > count then at = 1 end

    if def.example then
        exPaint(frame.pane, def.example, at, names[at])
    end

    if count > 1 then
        for i = 1, count do
            local dot = frame.pane:CreateTexture(nil, "OVERLAY")
            dot:SetWidth(6)
            dot:SetHeight(6)
            dot:SetTexture("Interface\\Buttons\\WHITE8X8")

            --[[ The one showing is bright; the rest are there to say how many
                 more there are. ]]--
            if i == at then
                dot:SetVertexColor(0.95, 0.95, 0.95, 0.9)
            else
                dot:SetVertexColor(0.5, 0.5, 0.5, 0.4)
            end

            dot:SetPoint("BOTTOM", frame.pane, "BOTTOM",
                    ((i - 1) - ((count - 1) / 2)) * 12, -8)
        end
    end

    return true
end

--[==[ **The picture moves on by itself.**

     Rotated from the window's own `OnUpdate` rather than from the addon's, so a
     walkthrough nobody has open costs nothing at all. Only when the step has
     more than one variation, and only while the window is shown. ]==]
function OB.StepSetupVariant(frame)
    frame = frame or OB.setupFrame
    if not frame or not frame:IsShown() then return false end

    local def = OB.setupSteps and OB.setupSteps[OB.setupAt or 0]
    local names = def and def.variants
    local count = names and table.getn(names) or 0

    --[[ A step with one picture still has bars that move: the party frames are
         one arrangement and four people, and the people are the point. ]]--
    if count < 2 then
        exStepCycles(frame.pane, GetTime())
        return false
    end

    --[[ The bars move whether or not the picture is about to change, so this
         runs before the variation clock rather than after it. ]]--
    exStepCycles(frame.pane, GetTime())

    local now = GetTime()
    if (now - (frame.variantAt or 0)) < VARIANT_SECONDS then return false end

    frame.variantAt = now
    frame.variant = (frame.variant or 1) + 1
    if frame.variant > count then frame.variant = 1 end

    OB.PaintSetupPane(frame, def)
    return true
end

--[==[ **Assembled when it opens, not when the file loads.**

     **In the panel's reading order, which is not the registry's.** This walked
     `OB.moduleOrder` and said in its own comment that it was following the
     Modules page -- but `moduleOrder` is *load* order, a dependency graph, and
     the panel has never used it for navigation. `OB.featureTabs` is the order
     somebody actually reads, written out in `options.lua` for exactly this
     reason.

     The difference was not subtle. `roster.lua` loads one line before
     `actionbars.lua`, so the first thing a new install saw was a screen about
     remembering players' levels -- which is a supporting feature of chat, and
     which nobody has an opinion about before they have seen the action bars.
     Reported as "players shouldn't be step one".

     It also puts the roster where the panel already had it: `featureTabs` holds
     `{ "chat", "roster", label = "Chat" }`, one entry with two modules, because
     chat name colouring and the scanning that feeds it are one subject. The
     walkthrough now agrees, and the Chat step has a switch for each.

     Read at open rather than at load so a module registered after this file is
     still walked, and rebuilt each time because the profile it reads defaults
     out of can change between one open and the next. ]==]

--[[ A tab entry is a string, or a table of module ids with a label, or a
     hand-built page with no module behind it at all. Only the first two can
     become a step: a step is a question about whether to use something, and
     `{ hand = "Omni Bars" }` has nothing to switch. ]]--
local function tabIds(entry)
    if type(entry) == "string" then return { entry } end
    if type(entry) ~= "table" then return {} end
    if entry.hand then return {} end

    local out = {}
    for i = 1, table.getn(entry) do
        if type(entry[i]) == "string" then table.insert(out, entry[i]) end
    end
    return out
end

--[[ One step covering one or more modules: a picture, a paragraph each, and a
     switch each. The switch binds as you tick it, so the answer to "did that do
     anything" is on screen behind the window -- which is the whole reason this
     is a walkthrough rather than a page of prose. ]]--
local function moduleStep(ids, label)
    local first = OB.modules[ids[1]]
    if not first then return nil end

    local body = ""
    for i = 1, table.getn(ids) do
        local blurb = MODULE_BLURBS[ids[i]]
        if blurb then
            if body ~= "" then body = body .. "\n\n" end
            body = body .. blurb
        end
    end

    if body ~= "" then body = body .. "\n\n" end
    body = body .. "You can change this later on the Modules page."

    return {
        id = "module:" .. ids[1],
        title = label or first.name,
        body = body,
        example = MODULE_EXAMPLES[ids[1]],
        variants = MODULE_VARIANTS[ids[1]],

        controls = function(area, pane)
            local y = 0

            for i = 1, table.getn(ids) do
                local id = ids[i]
                local m = OB.modules[id]

                if m then
                    y = checkRow(area, y, "Use " .. m.name,
                        function()
                            local flag = OB.profile.modulesEnabled[id]
                            return flag == nil or flag
                        end,
                        function(on)
                            OB.profile.modulesEnabled[id] = on and true or false
                            if OB.BindSlots then OB.BindSlots() end
                            --[[ Several examples draw themselves differently
                                 depending on what is switched on, which is what
                                 makes ticking one worth doing here rather than
                                 on the Modules page. ]]--
                            if pane and pane.Redraw then pane.Redraw() end
                        end)
                end
            end
        end,
    }
end

function OB.BuildSetupSteps()
    local fixed = OB.setupFixedSteps
    local out = { fixed.welcome }

    local seen = {}

    local function add(ids, label)
        local wanted = {}

        for i = 1, table.getn(ids) do
            local id = ids[i]
            local m = OB.modules[id]

            --[[ The same test the Modules page uses: features, and not the ones
                 named there but not written yet. `ClassAllows` drops the ones
                 this character could never use -- a warrior does not need a
                 step about druid mana. ]]--
            if m and m.feature and not m.development and OB.ClassAllows(m)
                    and not seen[id] then
                seen[id] = true
                table.insert(wanted, id)
            end
        end

        if table.getn(wanted) == 0 then return end

        local def = moduleStep(wanted, label)
        if def then table.insert(out, def) end
    end

    local tabs = OB.featureTabs or {}

    for i = 1, table.getn(tabs) do
        local entry = tabs[i]
        local label = type(entry) == "table" and entry.label or nil
        add(tabIds(entry), label)
    end

    --[==[ **Anything the tab list forgot still gets a step.**

         `featureTabs` is written by hand, and `options.lua` says in its own
         comment that a module missing from it "has no tab, which is a way to
         lose a page silently". The walkthrough should not inherit that: a
         subsystem nobody is ever asked about is one nobody knows they have.

         Registry order for these, because there is no better one available --
         they are here precisely because nobody has said where they belong. ]==]
    for i = 1, table.getn(OB.moduleOrder or {}) do
        add({ OB.moduleOrder[i] })
    end

    table.insert(out, fixed.look)
    table.insert(out, fixed.done)

    OB.setupSteps = out
    return out
end

function OB.ShowSetup()
    OB.BuildSetupSteps()
    OB.SetupStep(1)
    return true
end

function OB.FinishSetup()
    if OB.setupFrame then OB.setupFrame:Hide() end

    if EquadisClassicOverhaulDB then
        EquadisClassicOverhaulDB.setupDone = true
    end

    --[[ The panel may be open behind this and showing what the wizard has just
         changed underneath it. ]]--
    if OB.RefreshPanel then OB.RefreshPanel() end

    Say("setup finished. /eq setup reopens it.")
    return true
end

--[==[ **Shown once, and the flag is account-wide.**

     Per profile would run it again on every alt, which is the opposite of what
     somebody who has already set this up wants -- and a new character on an
     account that has been configured inherits a profile that is already
     right.

     Deliberately not shown while anything else is going on: `PLAYER_LOGIN`
     fires before the world is drawn on some clients, and a window that appears
     over a loading screen is a window somebody dismisses without reading. ]==]
function OB.MaybeShowSetup()
    if not EquadisClassicOverhaulDB then return false end
    if EquadisClassicOverhaulDB.setupDone then return false end

    EquadisClassicOverhaulDB.setupDone = true
    OB.ShowSetup()

    return true
end
