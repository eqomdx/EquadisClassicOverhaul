--[[ Equadis' Classic Overhaul :: self test

  /eq selftest -- what the offline suite cannot prove.

  tests/run.lua boots the real addon against a fake 1.12 client and checks that
  it is internally consistent. It is thorough and it is not enough, because a
  stub that agrees with a wrong assumption still passes. That is not a
  hypothetical caveat: a font string created without a font object threw on the
  real client, aborted the options panel build, and shipped a settings window
  with one sidebar entry and no controls -- past a green suite, because the
  stub's SetTextColor recorded the value and said nothing.

  So this half asks the questions only the client can answer. Does every API a
  module names actually exist here? Did the widgets end up with a size and an
  anchor? Does every font string have a font? Does GetValue return a number? Did
  the range readout find a backend? Did the panel build all four pages with every
  row placed?

  Three rules:

  It writes nothing. No ApplyOption, no SetTestMode, no touching the profile.
  Running it
  must never be the reason something changed. The one exception is building the
  settings panel, which is idempotent and is done hidden.

  Every section runs inside pcall. A self-test that dies partway through is worse
  than useless -- it reports a clean bill of health for everything it never
  reached.

  It counts propositions, not rows. "No visible row on the General page is
  unanchored" is one check with the count in its label. Sixty lines is a report;
  four hundred is a wall nobody reads.
]]--

local OB = EquadisClassicOverhaul

local GREEN = "|cff00ff00"
local RED = "|cffff5511"
local GREY = "|cffcccccc"
local WHITE = "|cffffffff"

-- ---------------------------------------------------------------------------
-- what the addon needs from the client, beyond what the modules declare
--
-- This list is here rather than split across core, render, layout and options
-- because no one of those owns it and four lists is four lists nobody keeps up
-- to date. A module gets its own `requires` because a module is a self-contained
-- unit with a descriptor to hang it on.
-- ---------------------------------------------------------------------------

local coreAPI = {
    "CreateFrame", "getglobal", "GetTime", "GetCursorPosition",
    "UnitClass", "UnitName", "GetRealmName",
    "UnitAffectingCombat", "UnitIsDeadOrGhost", "GetPlayerBuffTexture",
    "PlaySound", "IsAddOnLoaded",
    "UIDropDownMenu_Initialize", "UIDropDownMenu_AddButton",
    "UIDropDownMenu_SetWidth", "UIDropDownMenu_SetText",
    "UIDropDownMenu_SetSelectedValue",
    "StaticPopup_Show", "ShowUIPanel",
}

--[[ Widget methods the addon calls. The in-game counterpart of the stub's
     UnknownMethods() list, and deliberately a *subset* of what we really use:
     probing a method we never call would put a new entry in that list and break
     the "an unexpected entry is a typo'd API name" workflow.

     This section cannot fail under the stub, whose metatable fabricates a
     function for any PascalCase lookup. That is precisely why it belongs here
     and not in run.lua. ]]--
local frameMethods = {
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor",
    "SetClampedToScreen", "SetFrameStrata", "SetFrameLevel",
    "RegisterForDrag",
    "GetNumPoints", "CreateTexture", "CreateFontString", "EnableMouse",
}

--[[ StartMoving and StopMovingOrSizing are deliberately not probed, though the
     panel does call them. They live inside drag handlers the offline suite never
     fires, so probing them would add two entries to Stub.UnknownMethods() -- and
     that list earns its keep by being short enough that an unexpected entry
     reads as a typo'd API name. Two permanent, harmless entries would cost more
     than the check is worth, and a missing StartMoving would announce itself the
     first time anyone dragged the window. ]]--

local textureMethods = { "SetTexCoord", "SetVertexColor", "SetBlendMode", "SetTexture" }
local textMethods = { "SetFont", "GetFont", "SetText", "SetTextColor", "SetJustifyH" }

-- ---------------------------------------------------------------------------
-- the recorder
-- ---------------------------------------------------------------------------

local sections = {}

local function section(name, fn)
    table.insert(sections, { name = name, Run = fn })
end

local function newRecorder()
    local t = { passed = 0, failed = 0, failures = {}, notes = {} }

    function t:ok(condition, label)
        if condition then
            self.passed = self.passed + 1
        else
            self.failed = self.failed + 1
            table.insert(self.failures, label)
        end
    end

    -- context for the summary line: never counted, never a failure
    function t:note(text)
        table.insert(self.notes, text)
    end

    return t
end

local function exists(name)
    return type(getglobal(name)) == "function"
end

-- ---------------------------------------------------------------------------
-- 1. the client has the APIs everything here is built on
-- ---------------------------------------------------------------------------

section("client API", function(t)
    for i = 1, table.getn(coreAPI) do
        t:ok(exists(coreAPI[i]), "the client has no " .. coreAPI[i])
    end

    --[[ Every registered module, not just the ones this class can run. The API
         surface does not vary by class, so a warrior's report should be worth
         exactly as much as a rogue's -- otherwise a missing GetComboPoints only
         ever shows up for the two classes that would notice anyway. ]]--
    for i = 1, table.getn(OB.moduleOrder) do
        local id = OB.moduleOrder[i]
        local m = OB.modules[id]

        for r = 1, table.getn(m.requires) do
            t:ok(exists(m.requires[r]), id .. " needs " .. m.requires[r])
        end
    end
end)

-- ---------------------------------------------------------------------------
-- 2. the widget methods the addon calls
-- ---------------------------------------------------------------------------

local probe

local function probeFrame()
    if not probe then
        probe = CreateFrame("Frame", "EquadisClassicOverhaulProbe", UIParent)
        probe:Hide()
        probe.tex = probe:CreateTexture(nil, "ARTWORK")
        probe.text = OB.NewText(probe, "OVERLAY", "GameFontNormal")
    end
    return probe
end

section("widget methods", function(t)
    local frame = probeFrame()

    for i = 1, table.getn(frameMethods) do
        t:ok(type(frame[frameMethods[i]]) == "function",
                "Frame has no " .. frameMethods[i])
    end
    for i = 1, table.getn(textureMethods) do
        t:ok(type(frame.tex[textureMethods[i]]) == "function",
                "Texture has no " .. textureMethods[i])
    end
    for i = 1, table.getn(textMethods) do
        t:ok(type(frame.text[textMethods[i]]) == "function",
                "FontString has no " .. textMethods[i])
    end
end)

-- ---------------------------------------------------------------------------
-- 3. the bars actually got built
-- ---------------------------------------------------------------------------

local function checkBar(t, bar, label)
    if not bar then
        t:ok(false, label .. " has no frame")
        return
    end

    t:ok(bar:GetWidth() > 0, label .. " has zero width")
    t:ok(bar:GetHeight() > 0, label .. " has zero height")
    t:ok(bar:GetNumPoints() > 0, label .. " is not anchored to anything")
end

section("bound modules", function(t)
    local seen = {}
    local count = 0

    for i = 1, table.getn(OB.barOrder) do
        local slotId = OB.barOrder[i]
        local m = OB.bound[slotId]

        if m then
            count = count + 1
            local slot = OB.profile.slots[slotId]

            -- the invariant hud.lua enforces at bind time, checked against what
            -- actually ended up bound
            t:ok(not seen[m.id], m.id .. " is bound to two slots at once")
            seen[m.id] = true
            t:ok(m.slotId == slotId,
                    m.id .. " thinks it is in " .. tostring(m.slotId)
                    .. " but is bound to " .. slotId)

            if m.renders == "segments" then
                checkBar(t, m.frame, slotId .. " group")
                for s = 1, (m.frame.visible or m.frame.count) do
                    checkBar(t, m.frame.bars[s], slotId .. " segment " .. s)
                end
            else
                checkBar(t, m.frame, slotId)
            end

            --[[ Only the hard direction is a check. A hidden slot must hide its
                 module, with no exceptions. The reverse is not a rule: combo
                 points hide themselves at zero, and a druid with no mana
                 baseline hides on purpose (constraint 19). A check that fails on
                 correct behaviour teaches people to ignore it, and then to
                 ignore the one next to it. ]]--
            if not slot.show and m.frame then
                t:ok(not m.frame:IsShown(),
                        slotId .. " is switched off but " .. m.id .. " is showing")
            end
        end
    end

    t:note(count .. " modules bound")

    --[[ IsShown, never IsVisible: IsVisible walks up to OB.container, which
         hideOOC legitimately hides, so out of combat every bar would "fail". ]]--
    local state = "shown"
    if not OB.container:IsShown() then state = "hidden" end

    t:note("HUD " .. state
            .. "  show=" .. tostring(OB.profile.show)
            .. " hideOOC=" .. tostring(OB.profile.hideOOC)
            .. " combat=" .. tostring(OB.inCombat)
            .. " stealth=" .. tostring(OB.inStealth))
end)

-- ---------------------------------------------------------------------------
-- 4. every font string has a font
--
-- The check for the bug that shipped. One proposition for the whole registry,
-- with the offenders named.
-- ---------------------------------------------------------------------------

section("font strings", function(t)
    local total = table.getn(OB.texts)
    local bad = 0
    local first

    for i = 1, total do
        if not OB.texts[i]:GetFont() then
            bad = bad + 1
            if not first then
                local ok, text = pcall(OB.texts[i].GetText, OB.texts[i])
                if ok and text and text ~= "" then first = text else first = "?" end
            end
        end
    end

    t:ok(bad == 0, bad .. " of " .. total .. " font strings have no font"
            .. " (first: " .. tostring(first) .. ")")

    -- a refactor that stops registering would otherwise pass by having nothing
    -- to check
    t:ok(total > 0, "the font string registry is empty")
    t:note(total .. " registered, all fonted")
end)

-- ---------------------------------------------------------------------------
-- 5. the numbers the bars draw from are numbers
-- ---------------------------------------------------------------------------

section("module values", function(t)
    local without = 0

    for slotId, m in pairs(OB.bound) do
        if not m.GetValue then
            without = without + 1
        else
            local ok, value, max = pcall(m.GetValue, m)

            if not ok then
                t:ok(false, m.id .. ":GetValue raised " .. tostring(value))
            else
                t:ok(type(value) == "number", m.id .. ":GetValue is not a number")

                -- the only NaN test available without math.huge
                if type(value) == "number" then
                    t:ok(value == value, m.id .. ":GetValue is NaN")
                end

                if type(max) == "number" then
                    t:ok(max == max, m.id .. ":GetValue max is NaN")
                    t:ok(value <= max,
                            m.id .. " reads " .. tostring(value)
                            .. " out of a maximum of " .. tostring(max))
                end
            end
        end
    end

    if without > 0 then t:note(without .. " modules have no GetValue") end
    if OB.testMode then t:note("test mode is on -- these are simulated") end
end)

-- ---------------------------------------------------------------------------
-- 6. the range readout found a backend it can actually run
-- ---------------------------------------------------------------------------

--[[ Which modules registered, and which of them are features.

     Here because "the module does not show" has two entirely different causes --
     the file did not load, or it loaded and is switched off -- and from outside
     they look identical. This tells the two apart in one line each. ]]--
section("modules", function(t)
    local features = 0

    for i = 1, table.getn(OB.moduleOrder) do
        local id = OB.moduleOrder[i]
        local m = OB.modules[id]

        if m.feature then
            features = features + 1
            t:note("feature '" .. id .. "': registered, "
                    .. (OB.ModuleEnabled(id) and "enabled" or "|cff888888off|r")
                    .. (OB.features and OB.features[id] and ", bound" or ", not bound")
                    .. (m.frame and ", has a window" or ", no window yet"))
        end
    end

    t:note(table.getn(OB.moduleOrder) .. " modules registered, "
            .. features .. " of them features")

    --[[ A file that failed to load registers nothing, and there are only two
         ways that happens.

         **Restart the game, do not /reload.** 1.12 reads each addon's file list
         once, when the client starts. A file *added* to a TOC since then is not
         in that list, so ReloadUI re-runs everything the client already knew
         about -- which is why the version string updates and the new module does
         not, and why this looks like a broken module when nothing is broken.

         Failing that it is the TOC line itself: missing, misspelt, or naming a
         file that is not there. ]]--
    t:ok(features > 0, "no feature modules registered -- restart the game"
            .. " (not /reload) if a module file was just added, then check the TOC")
end)

section("range backend", function(t)
    local m = OB.modules.distance
    if not m then
        t:note("the range module is not registered")
        return
    end

    t:ok(m.backend ~= nil, "the range readout has no backend at all")
    if not m.backend then return end

    local cfg = m:Config()

    -- not "did it probe once" but "would it still choose this now"
    t:ok(m.backend.Available(m) and true or false,
            "the " .. m.backend.id .. " backend is no longer available")

    if cfg.backend ~= "auto" then
        t:ok(m.backend.id == cfg.backend,
                "backend forced to " .. cfg.backend
                .. " but running " .. m.backend.id)
    end

    local note = m.backend.name
    if type(GetUnitDistance) == "function" then
        note = note .. " (Nampower exact hostile distance present)"
    elseif OB.HasUnitXP and OB.HasUnitXP() then
        note = note .. " (UnitXP exact hostile distance present)"
    elseif type(UnitPosition) == "function" then
        note = note .. " (SuperWoW exact friendly distance only)"
    else
        note = note .. " (no exact-distance API)"
    end
    if not OB.bound.distance then note = note .. ", bar not drawn" end

    t:note(note)

    --[[ The action slot is found rather than configured, so the only way to know
         whether the scan worked is to say what it found. "not on a bar" is a
         normal answer, not a fault: most players never put their auto-attack on
         one, and the backend simply goes unused. ]]--
    if m.spell then
        if m.actionSlot then
            t:note(m.spell .. " found on action slot " .. tostring(m.actionSlot))
        else
            t:note(m.spell .. " is not on an action bar")
        end
    end

    --[[ Which of the two line of sight routes this client is on, and it matters
         because they behave differently enough to be different features. The
         reactive one needs nothing installed but only knows after a shot has
         been refused; the continuous one can be asked. Reported rather than
         asserted -- neither is a failure. ]]--
    if cfg.losCheck then
        t:ok(OB.IsLineOfSightError(SPELL_FAILED_LINE_OF_SIGHT),
                "the client's line of sight message is not recognised")

        if type(IsUnitInSight) == "function" then
            t:note("line of sight: continuous, via a native IsUnitInSight")
        elseif OB.HasUnitXP and OB.HasUnitXP() then
            t:note("line of sight: continuous, via UnitXP_SP3")
        else
            t:note("line of sight: reactive -- known only after a refused shot,"
                    .. " and cleared a couple of seconds later")
        end
    end
end)

-- ---------------------------------------------------------------------------
-- 7. the settings panel
-- ---------------------------------------------------------------------------

section("settings panel", function(t)
    local panel = OB.EnsurePanel()

    t:ok(panel ~= nil, "the panel could not be built: " .. tostring(OB.panelDead))
    if not panel then return end

    local faults = table.getn(OB.panelFaults)
    t:ok(faults == 0, faults .. " controls failed to build or update")
    for i = 1, faults do
        t:ok(false, "  " .. OB.panelFaults[i].label .. ": " .. OB.panelFaults[i].err)
    end

    --[[ Three fixed tabs -- Profiles, General, Bars -- plus one per subsystem.
         Counted rather than hardcoded, because a subsystem gets its tab by
         registering, so a fixed number here would fail the day one is added and
         say nothing useful about why. ]]--
    --[[ **One tab per entry in the tab list, not one per feature module.**

         Counted from the module registry until an entry was allowed to name
         several modules -- one tab built from all of them, which is how Players
         ended up inside Chat. Counting features then expected a tab that was
         deliberately not there.

         Read from the list the panel itself is built from, so the two cannot
         disagree: adding a tab moves both numbers at once. ]]--
    local tabs = table.getn(OB.featureTabs or {})

    --[[ Profiles, Bars, one per tab, then Modules.

         General used to be a tab and is the first entry in the Bars column now,
         so it is a row on that page rather than a page of its own. ]]--
    local expected = 2 + tabs + 1

    t:ok(table.getn(panel.categories) == expected,
            "expected " .. expected .. " categories, found "
            .. table.getn(panel.categories))

    --[[ Laid out with force, so the panel is measured while it stays hidden.
         Showing it would trip its OnHide on the way back out, which stops a
         preview the user might have running -- a self-test that changes what it
         is testing is not one. ]]--
    OB.RefreshPanel(true)

    local rows, unplaced, broken = 0, 0, 0

    for i = 1, table.getn(panel.categories) do
        local cat = panel.categories[i]
        local n = table.getn(cat.page.rows)

        t:ok(n > 0, "the " .. cat.name .. " page has no rows")
        rows = rows + n

        for r = 1, n do
            local widget = cat.page.rows[r]
            if widget.broken then broken = broken + 1 end
            if widget.visible and widget:GetNumPoints() == 0 then
                unplaced = unplaced + 1
            end
        end
    end

    t:ok(broken == 0, broken .. " rows gave up and were hidden")
    t:ok(unplaced == 0, unplaced .. " visible rows are unanchored")

    --[[ Every option the prompt offers has a control behind it. This catches the
         panel bug by its *symptom* rather than its cause, which is what makes it
         worth having: the next one will have a different cause. ]]--
    local missing = 0

    local function crossCheck(index)
        for key, w in pairs(index) do
            if not OB.widgets[OB.WidgetKey(w)] then missing = missing + 1 end
        end
    end

    crossCheck(OB.optionIndex.global)
    crossCheck(OB.optionIndex.slot)
    for id, index in pairs(OB.optionIndex.modules) do crossCheck(index) end

    t:ok(missing == 0, missing .. " options have no control on the panel")
    t:note(table.getn(panel.categories) .. " categories, " .. rows .. " rows")
end)

-- ---------------------------------------------------------------------------
-- running it
-- ---------------------------------------------------------------------------

-- pad a name out so the counts line up in a proportional font well enough to read
local function pad(name)
    local text = name
    while string.len(text) < 18 do text = text .. "." end
    return text
end

function OB.RunSelfTest()
    local passed, failed = 0, 0
    local failures = {}

    OB.Raw(GREY .. "Classic Overhaul self-test " .. WHITE .. OB.version
            .. GREY .. ", " .. OB.class .. ", profile '" .. OB.profileName .. "'")

    for i = 1, table.getn(sections) do
        local s = sections[i]
        local t = newRecorder()

        --[[ Each section in its own pcall. One that throws reports itself as a
             single failure and the rest still run -- a self-test that stops
             early is one that silently passes everything it never reached. ]]--
        local ok, err = pcall(s.Run, t)
        if not ok then
            t.failed = t.failed + 1
            table.insert(t.failures, "the check itself raised: " .. tostring(err))
        end

        passed = passed + t.passed
        failed = failed + t.failed

        local line = "  " .. pad(s.name) .. " "
        if t.failed > 0 then
            line = line .. RED .. t.failed .. " failed" .. WHITE
        else
            line = line .. GREEN .. t.passed .. " ok" .. WHITE
        end

        if table.getn(t.notes) > 0 then
            line = line .. "   " .. GREY .. table.concat(t.notes, "  ")
        end

        OB.Raw(line)

        for f = 1, table.getn(t.failures) do
            table.insert(failures, t.failures[f])
        end
    end

    for i = 1, table.getn(failures) do
        OB.Raw("  " .. RED .. "FAIL " .. WHITE .. failures[i])
    end

    if failed == 0 then
        OB.Raw("  " .. GREEN .. passed .. " passed" .. WHITE .. ", 0 failed.")
    else
        OB.Raw("  " .. passed .. " passed, " .. RED .. failed .. " failed" .. WHITE .. ".")
    end

    OB.selfTestResult = { passed = passed, failed = failed, failures = failures }
    return passed, failed
end

OB.commands.selftest = {
    help = "check the addon against this client, not against the test stub",
    Run = function(args) OB.RunSelfTest() end,
}

--[[ A deliberately narrow runtime trace for the distance readout.

     The offline suite can prove that fallback order and drawing are internally
     consistent, but it cannot tell us what an injected API returns on this
     particular client build. Keep this as a command instead of permanent chat
     spam: target the unit that fails, run it once, and every value involved in
     choosing the yard count is visible. ]]--
local function positionResult(token)
    if type(UnitPosition) ~= "function" then return "API missing" end
    if not token then return "no token" end

    local ok, x, y, z = pcall(UnitPosition, token)
    if not ok then return "ERROR " .. tostring(x) end
    if type(x) ~= "number" or type(y) ~= "number" then
        return "nil (" .. tostring(x) .. ", " .. tostring(y) .. ", "
                .. tostring(z) .. ")"
    end

    return tostring(x) .. ", " .. tostring(y) .. ", " .. tostring(z)
end

--[[ Which of the five kinds of target this is, in the same words the report was
     asked for. The classification is printed rather than used: the point is that
     a run can be filed against the target type it came from, so five runs make a
     table instead of five opinions. ]]--
local function targetKind()
    if not UnitExists("target") then return "none" end

    local who = UnitIsPlayer("target") and "player" or "NPC"

    if UnitCanAttack("player", "target") then
        --[[ Attackable is not the same as hostile. A neutral mob can be attacked
             and will not attack back, which is exactly the case that has to be
             told apart from an enemy here. ]]--
        if UnitCanAttack("target", "player") then return "enemy " .. who end
        return "neutral " .. who
    end

    if UnitIsFriend("player", "target") then return "friendly " .. who end
    return "other " .. who
end

--[[ Every raw probe, one per line, named after the call that produced it. A
     value here is evidence; anything derived from it is not. ]]--
local function probe(label, fn, a, b, c)
    if type(fn) ~= "function" then
        OB.Raw("    " .. label .. ": API missing")
        return
    end

    local ok, value = pcall(fn, a, b, c)
    if not ok then
        OB.Raw("    " .. label .. ": " .. RED .. "ERROR " .. WHITE .. tostring(value))
        return
    end

    OB.Raw("    " .. label .. ": " .. tostring(value)
            .. " " .. GREY .. "(" .. type(value) .. ")" .. WHITE)
end

--[[ Can a **range ladder** be built here, and how fine would it be?

     The idea: `IsSpellInRange` is a boolean, but a boolean against a *known
     threshold* is one bit of a distance. Ask it about several spells with
     different maximum ranges and the answers bracket the target -- 0 for the
     35-yard spell and 1 for the 30 puts it between the two. That is the only
     route to a hostile yard figure that does not need native code, since
     IsSpellInRange is the one call on this client that answers about a mob.

     The first pass asked by **name** and every rung failed the same way, which
     turned out to be Nampower telling us how to do it properly:

       Unable to determine spell id from spell name, possibly because it isn't
       in your spell book.  Try IsSpellInRange(SPELL_ID) instead

     So the spellbook limit is on the name lookup, not on the range check. Asking
     by id should answer for any spell in the game, which is what the dense
     ladder needs. This pass asks by id.

     The ids are hardcoded and **not trusted**: each one is printed back with the
     name and range the client itself holds for it, so a wrong id shows up as a
     wrong name rather than quietly calibrating the ladder to the wrong distance.
     Reading the range from the client also means Turtle can have retuned any of
     them and the ladder still lands where the engine says it does.

     Candidates want a **zero minimum range**. Charge reads 0 both past 25 yards
     and inside 8, so a spell with a dead zone is not one threshold but two, and
     it breaks the ordering the method depends on. Charge is included anyway,
     precisely so the dead zone shows up in the output rather than being assumed
     away. ]]--
local function rangeLadderProbe()
    OB.Raw("  " .. GREY .. "-- range ladder, asked by spell id --" .. WHITE)

    if type(IsSpellInRange) ~= "function" then
        OB.Raw("    IsSpellInRange missing -- no ladder is possible here")
        return
    end

    local candidates = OB.ladderCandidates or {}

    for i = 1, table.getn(candidates) do
        local id = candidates[i]

        --[[ What the client says this id actually is. The hardcoded label is
             only a note to the reader; this is the value that decides whether
             the id is right. ]]--
        local realName = "?"
        if type(GetSpellRecField) == "function" then
            local okName, value = pcall(GetSpellRecField, id, "name")
            if okName and type(value) == "string" then realName = value end
        end

        local dbc = "no data"
        if type(GetSpellRecField) == "function"
                and type(GetSpellRangeData) == "function" then
            local okIndex, index = pcall(GetSpellRecField, id, "rangeIndex")
            if okIndex and index then
                local okRange, minRange, maxRange = pcall(GetSpellRangeData, index)
                if okRange and type(maxRange) == "number" then
                    dbc = tostring(minRange) .. "-" .. tostring(maxRange)
                end
            end
        end

        local ok, result = pcall(IsSpellInRange, id, "target")
        local answer = ok and tostring(result) or ("ERROR " .. tostring(result))

        OB.Raw("    id " .. id .. ": " .. realName
                .. " dbc=" .. dbc .. " inRange=" .. answer)
    end
end

function OB.RunRangeDebug()
    local m = OB.modules.distance
    if not m then
        OB.Raw(RED .. "Range debug: distance module is not registered")
        return
    end

    local exists, superGuid = UnitExists("target")
    local nampowerGuid
    if type(GetUnitGUID) == "function" then
        local ok, value = pcall(GetUnitGUID, "target")
        if ok then nampowerGuid = value end
    end
    local guid = superGuid or nampowerGuid

    OB.Raw(GREY .. "Classic Overhaul range debug " .. WHITE .. OB.version
            .. GREY .. "  target type: " .. WHITE .. targetKind())
    OB.Raw("  target: exists=" .. tostring(exists)
            .. " name=" .. tostring(UnitName("target"))
            .. " attackable=" .. tostring(UnitCanAttack("player", "target"))
            .. " attacksYou=" .. tostring(UnitCanAttack("target", "player")))
    OB.Raw("  GUID: UnitExists=" .. tostring(superGuid)
            .. " GetUnitGUID=" .. tostring(nampowerGuid))

    --[[ The extension probes, before anything that depends on them. Getting
         these wrong is what disables a working install, so they are reported as
         what was asked and what came back rather than as a verdict. ]]--
    OB.Raw("  " .. GREY .. "-- client extensions --" .. WHITE)
    OB.Raw("    UnitXP global: " .. type(UnitXP)
            .. "  OB.HasUnitXP()=" .. tostring(OB.HasUnitXP()))
    probe("UnitXP('player')", UnitXP, "player")
    probe("UnitXP('inSight','player','player')", UnitXP, "inSight", "player", "player")
    probe("UnitXP('inSight','player','target')", UnitXP, "inSight", "player", "target")
    probe("UnitXP('distanceBetween','player','player')",
            UnitXP, "distanceBetween", "player", "player")
    probe("UnitXP('distanceBetween','player','target')",
            UnitXP, "distanceBetween", "player", "target")
    OB.Raw("  UnitPosition player: " .. positionResult("player"))
    OB.Raw("  UnitPosition target: " .. positionResult("target"))
    OB.Raw("  UnitPosition GUID: " .. positionResult(guid))

    local nativeDistance = "API missing"
    if type(GetUnitDistance) == "function" then
        local ok, value = pcall(GetUnitDistance, "target")
        nativeDistance = ok and tostring(value) or ("ERROR " .. tostring(value))
    end
    OB.Raw("  GetUnitDistance target: " .. nativeDistance)

    local exact = OB.UnitDistance("target")
    OB.Raw("  exact distance: " .. tostring(exact))

    local rangeResult = "API/spell unavailable"
    if type(IsSpellInRange) == "function" and (m.spellId or m.spell) then
        local ok, value = pcall(IsSpellInRange, m.spellId or m.spell, "target")
        rangeResult = ok and tostring(value) or ("ERROR " .. tostring(value))
    end
    OB.Raw("  weapon spell: " .. tostring(m.spell) .. " id="
            .. tostring(m.spellId) .. " good=" .. tostring(m.minRange)
            .. "-" .. tostring(m.maxRange) .. " IsSpellInRange=" .. rangeResult)

    --[[ The coarse fallback, spelled out. CheckInteractDistance answers nil for
         anything attackable, which is the single fact behind "it only works on
         friendly targets" -- so it is worth seeing rather than inferring. ]]--
    OB.Raw("  " .. GREY .. "-- CheckInteractDistance --" .. WHITE)
    probe("index 1 (inspect ~28y)", CheckInteractDistance, "target", 1)
    probe("index 3 (duel ~9.9y)", CheckInteractDistance, "target", 3)

    OB.Raw("  action slot: " .. tostring(m.actionSlot))
    if m.actionSlot then
        probe("IsActionInRange(slot)", IsActionInRange, m.actionSlot)
    end

    --[[ The ladder the addon actually built, which is the thing to read first:
         it is derived from the client's spell data at login, so it says what
         resolution this install can manage rather than what the candidate list
         hoped for. Wide gaps here are the argument for adding ids. ]]--
    local rungs = m.ladder or {}
    local list = ""
    for i = 1, table.getn(rungs) do
        list = list .. (i > 1 and ", " or "") .. tostring(rungs[i].max)
    end
    OB.Raw("  ladder rungs (" .. table.getn(rungs) .. "): "
            .. (list ~= "" and list or "none"))

    local low, high = m.bandLow, m.bandHigh
    if low then
        OB.Raw("  measured band: " .. tostring(low) .. "-" .. tostring(high or "")
                .. "y")
    end

    rangeLadderProbe()

    --[[ Every backend asked both questions in turn, against the target actually
         selected. "available but declines" and "never considered" look identical
         from the outside and have completely different fixes. ]]--
    OB.Raw("  " .. GREY .. "-- backends, against this target --" .. WHITE)

    --[[ Reading every backend walks paths the live readout would have skipped,
         and `bands` arms a warning when it meets an attackable unit. Left alone,
         the diagnostic prints a complaint it caused itself -- which is exactly
         the sort of thing a diagnostic must never do. ]]--
    local blindBefore, warnedBefore = m.blindToHostiles, m.warnedHostile

    for i = 1, table.getn(OB.rangeOrder) do
        local backend = OB.rangeBackends[OB.rangeOrder[i]]

        local okA, available = pcall(backend.Available, m)
        local line = "    " .. backend.id .. ": available="
                .. (okA and tostring(available) or (RED .. "ERROR" .. WHITE))

        local okR, state, yards = pcall(backend.Read, m)
        if okR then
            line = line .. " state=" .. tostring(state) .. " yards=" .. tostring(yards)
        else
            line = line .. " read=" .. RED .. "ERROR " .. WHITE .. tostring(state)
        end

        if backend == m.backend then line = line .. GREY .. "  <- selected" .. WHITE end
        OB.Raw(line)
    end

    m.blindToHostiles, m.warnedHostile = blindBefore, warnedBefore

    local state, yards = m:Read()
    OB.Raw("  " .. GREY .. "-- result --" .. WHITE)
    OB.Raw("  selected=" .. tostring(m.backend and m.backend.id)
            .. " answered=" .. tostring(m.answered and m.answered.id)
            .. " state=" .. tostring(state) .. " yards=" .. tostring(yards)
            .. " shown=" .. tostring(m.frame and m.frame:IsShown()))
end

OB.commands.rangedebug = {
    help = "report every client value used by the distance readout",
    Run = function(args) OB.RunRangeDebug() end,
}

--[==[ **Where threat could come from on this client, asked rather than assumed.**

     The meter reads a packet the server sends: request `TWT_UDTSv4` on the party
     or raid channel, receive `TWTv4=` back. That is the server's own threat
     table, which is as good as the number can get -- no estimate from a combat
     log beats being told.

     Two questions follow from that and neither can be answered from here.

     **Can a client mod do better?** Threat lives on the server and 1.12 never
     sends a threat table to the client, so none of Nampower, SuperWoW, UnitXP
     SP3 or ClassicAPI is documented to expose one. "Not documented" is not
     "absent", and the cost of finding out is one command -- so this asks
     `UnitXP` for the verbs it would plausibly use and `GetUnitField` for a field
     that looks like threat, and prints exactly what came back.

     **Can there be threat solo?** There is no group, so there is no channel to
     request on, so nothing arrives -- which is why the window says "no threat
     solo" rather than "no data". But `SendAddonMessage` has channels that exist
     while alone, and whether the server answers a request on one of them is a
     fact about the server that nobody here knows. `/eq threatdebug ask` sends on
     them and says what to watch for.

     **Separated from the report on purpose.** The plain command reads state and
     sends nothing; `ask` puts messages on the guild channel, which is other
     people's addon traffic. ]==]
local THREAT_REQUEST = "TWT_UDTSv4"

function OB.RunThreatDebug(send)
    local m = OB.modules and OB.modules.threat

    OB.Raw(GREY .. "Classic Overhaul threat debug " .. WHITE .. OB.version)

    if not m then
        OB.Raw(RED .. "  the threat module is not loaded")
        return
    end

    -- ---------------------------------------------------------------------
    -- where the meter stands
    -- ---------------------------------------------------------------------

    local raid = type(GetNumRaidMembers) == "function" and GetNumRaidMembers() or 0
    local party = type(GetNumPartyMembers) == "function" and GetNumPartyMembers() or 0

    OB.Raw("  " .. GREY .. "-- the meter --" .. WHITE)
    OB.Raw("    group: raid=" .. raid .. " party=" .. party
            .. "  solo=" .. tostring(m:Solo()))
    OB.Raw("    seen a packet this session: " .. tostring(m.seenPacket and true or false))

    if m.lastPacketAt then
        OB.Raw("    last packet: " .. OB.Round(GetTime() - m.lastPacketAt)
                .. "s ago")
    end

    OB.Raw("    window would say: " .. tostring(m:EmptyReason()))

    -- ---------------------------------------------------------------------
    -- what the client mods say, if anything
    -- ---------------------------------------------------------------------

    --[==[ Threat is server side in 1.12 and the client is never sent the table,
         so every one of these is expected to answer nothing. Printed anyway:
         "expected to" is where the last three surprises on this install came
         from, and a nil here costs one line. ]==]
    OB.Raw("  " .. GREY .. "-- client mods, which are not expected to have it --"
            .. WHITE)

    OB.Raw("    UnitXP dispatcher: " .. tostring(OB.HasUnitXP and OB.HasUnitXP()))
    probe("UnitXP('threat','player','target')", UnitXP, "threat", "player", "target")
    probe("UnitXP('threatSituation','player','target')",
            UnitXP, "threatSituation", "player", "target")
    probe("UnitXP('aggro','player','target')", UnitXP, "aggro", "player", "target")

    OB.Raw("    GetUnitField: " .. type(GetUnitField))
    probe("GetUnitField('target','threat')", GetUnitField, "target", "threat")

    probe("UnitThreatSituation('player','target')",
            UnitThreatSituation, "player", "target")
    probe("GetThreatStatus()", GetThreatStatus)

    --[==[ **Aggro is a different question from threat, and it is already
         answerable.**

         "Who is this mob attacking" needs no packet and no percentage, and
         `targettarget` answers it for your own target on a bare client. SuperWoW
         extends that to every nameplate on screen -- see `modules/nameplates`,
         which resolves a plate's GUID and asks `guid .. "target"`.

         So a solo aggro indicator is possible today whatever the rest of this
         prints. A solo threat *percentage* is a different thing and is what the
         lines above are about. ]==]
    OB.Raw("  " .. GREY .. "-- aggro, which needs no packet --" .. WHITE)
    OB.Raw("    target's target: "
            .. tostring(type(UnitName) == "function" and UnitName("targettarget")))
    OB.Raw("    SuperWoW nameplate units: " .. tostring(OB.Can
            and OB.Can("nameplateunits")))

    -- ---------------------------------------------------------------------
    -- and the one thing worth trying
    -- ---------------------------------------------------------------------

    if not send then
        OB.Raw("  " .. GREY
                .. "-- run |cff69ccf0/eq threatdebug ask|r" .. GREY
                .. " to request a packet on the channels that exist while solo"
                .. WHITE)
        return
    end

    if type(SendAddonMessage) ~= "function" then
        OB.Raw(RED .. "  SendAddonMessage is missing; nothing can be asked")
        return
    end

    local limit = "limit=" .. ((m:Config() and m:Config().rows) or 10)

    OB.Raw("  " .. GREY .. "-- asking --" .. WHITE)

    --[[ To yourself, which is the channel that always exists. Whether the
         server treats a whisper-channel request as a request is exactly the
         unknown. ]]--
    local me = type(UnitName) == "function" and UnitName("player")

    if me then
        local ok = pcall(SendAddonMessage, THREAT_REQUEST, limit, "WHISPER", me)
        OB.Raw("    WHISPER to self: " .. (ok and "sent" or "refused"))
    end

    --[[ **Guild is other people's addon traffic**, which is why this is behind
         the argument rather than in the report. One small message. ]]--
    if type(IsInGuild) == "function" and IsInGuild() then
        local ok = pcall(SendAddonMessage, THREAT_REQUEST, limit, "GUILD")
        OB.Raw("    GUILD: " .. (ok and "sent" or "refused"))
    else
        OB.Raw("    GUILD: not in one")
    end

    OB.Raw("  " .. GREY .. "now pull something and run |cff69ccf0/eq threatdebug"
            .. "|r" .. GREY .. " again. If |cff69ccf0seen a packet|r has turned"
            .. " true, the server answers while solo and the meter can." .. WHITE)
end

OB.commands.threatdebug = {
    help = "where threat could come from here, and whether it can work solo",
    Run = function(args)
        OB.RunThreatDebug(args and string.find(string.lower(args), "ask", 1, true))
    end,
}

--[[ Find every rung the client could possibly offer.

     "Is there a 25 yard rung?" is not a question to answer from memory. The
     client holds the answer in two tables and will hand both over:

       SpellRange.dbc   every distinct min/max pair in the game, a few dozen rows
       the spell table  which spells use which of those rows

     So this reads the first to see what bands exist at all, then walks the
     second to name one spell per band. Anything it prints with a zero minimum is
     a candidate rung, and adding its id to LADDER_IDS in modules/range.lua makes
     the readout that much finer.

     The walk is the expensive half and it is why this is a command rather than
     part of the login probe: thirty thousand ids is a visible pause, worth
     paying once to answer a question permanently. ]]--
local SPELL_ID_MAX = 30000
local RANGE_INDEX_MAX = 256

function OB.RunRangeScan()
    if type(GetSpellRangeData) ~= "function"
            or type(GetSpellRecField) ~= "function" then
        OB.Raw(RED .. "range scan: needs Nampower's spell range APIs")
        return
    end

    OB.Raw(GREY .. "Classic Overhaul range scan " .. WHITE .. OB.version
            .. GREY .. "  (this pauses for a moment)" .. WHITE)

    --[[ Every range row the client has. This alone settles which bands are
         possible; the spell walk below only puts a name to them. ]]--
    local wanted, rows = {}, 0

    for index = 1, RANGE_INDEX_MAX do
        local ok, minRange, maxRange = pcall(GetSpellRangeData, index)

        if ok and type(maxRange) == "number" and maxRange > 0 then
            rows = rows + 1
            local usable = (minRange or 0) == 0

            OB.Raw("  index " .. index .. ": " .. tostring(minRange) .. "-"
                    .. tostring(maxRange)
                    .. (usable and "" or GREY .. "  (dead zone, unusable)" .. WHITE))

            --[[ A minimum range disqualifies the row outright. A spell that
                 answers "out of range" from both directions is two thresholds
                 rather than one, and the binary search assumes one. ]]--
            if usable then wanted[index] = maxRange end
        end
    end

    OB.Raw("  " .. rows .. " range rows, of which "
            .. GREY .. "the zero-minimum ones are candidate rungs" .. WHITE)

    --[[ One spell per band is all that is needed, so each index is dropped from
         `wanted` the moment it is claimed and the walk gets cheaper as it goes. ]]--
    local found, remaining = {}, 0
    for _ in pairs(wanted) do remaining = remaining + 1 end

    for id = 1, SPELL_ID_MAX do
        if remaining == 0 then break end

        local ok, index = pcall(GetSpellRecField, id, "rangeIndex")
        if ok and index and wanted[index] then
            local okName, name = pcall(GetSpellRecField, id, "name")

            table.insert(found, { max = wanted[index], id = id,
                                  name = (okName and name) or "?" })
            wanted[index] = nil
            remaining = remaining - 1
        end
    end

    table.sort(found, function(a, b) return a.max < b.max end)

    OB.Raw("  " .. GREY .. "-- one spell per usable band --" .. WHITE)
    for i = 1, table.getn(found) do
        local row = found[i]
        OB.Raw("    " .. row.max .. "y: id " .. row.id .. "  " .. row.name)
    end

    if remaining > 0 then
        OB.Raw("  " .. remaining .. " band(s) had no spell below id "
                .. SPELL_ID_MAX)
    end
end

OB.commands.rangescan = {
    help = "list every distance band this client could measure, and a spell for each",
    Run = function(args) OB.RunRangeScan() end,
}
