--[[ Equadis' Classic Overhaul :: hud

  The driver. Binds modules to slots, routes events, and owns the single
  OnUpdate.

  Modules never draw from an event handler. They mutate their own state and call
  OB.SetDirty; the redraw is batched here on the next frame. That is ShaguDPS's
  dirty-flag decoupling applied to a HUD, and it is why a module that only
  changes on an event -- combo points, health -- costs nothing per frame.
  RogueBars recomputed every bar every frame regardless.
]]--

local OB = EquadisClassicOverhaul

-- replaced by options.lua once the panel exists
function OB.RefreshPanel() end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------

OB.inCombat = false
OB.inStealth = false
OB.testMode = false

--[[ Shared scratch space for the test cycle. Every module reads its value
     through its own GetValue, which checks OB.testMode, so simulated numbers are
     substituted in one place per module and the rendering path stays byte for
     byte identical to live play. ]]--
OB.test = {}

local stealthTextures = {
    ["Interface\\Icons\\Ability_Stealth"] = true,
    ["Interface\\Icons\\Ability_Ambush"] = true,
    ["Interface\\Icons\\ability_druid_prowl"] = true,
}

function OB.IsStealthed()
    return OB.HasPlayerBuff(stealthTextures)
end

-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

--[[ A module saying whether it has anything to draw right now.

     Separate from the bar's own Show Bar setting, and from the HUD-wide
     visibility rules, because they answer different questions: the user has
     switched this bar off, the HUD is hidden out of combat, and *there is no off
     hand equipped* are three different reasons for an empty rectangle, and only
     the module knows the third.

     Recorded on the descriptor rather than left implicit in the frame's state,
     so OB.Toggle can honour it. A frame that is merely hidden looks identical to
     one that has never been shown, and Toggle cannot tell them apart. ]]--
function OB.SetBarShown(m, visible)
    m.selfHidden = not visible

    if not visible then
        m.frame:Hide()
        return
    end

    local slot = OB.profile.slots[m.slotId]
    if slot and slot.show then m.frame:Show() end
end

function OB.SetDirty(m)
    if m then m.needsDraw = true end
    OB.hud.needsDraw = true
end

--[[ Resolve every slot's occupant and wire it up.

     Frames are built once and reused: a module that gets unbound is hidden, not
     destroyed, so switching a slot back and forth costs nothing.

     Only the events some bound module actually asked for are registered. This is
     RogueBars' RegisterEvents -- a hardcoded fifteen-line if/else that either
     registered everything or nothing depending on the class -- generalised into
     a table walk. ]]--
--[[ Features bind alongside the bars, not into them.

     A **bar module** is given a rectangle in the cluster and draws into it. A
     **feature module** -- the threat meter, the damage meter -- owns a window of
     its own, decides its own size and position, and has nothing to do with the
     stack. So the binder cannot find it by walking barOrder, because it occupies
     no bar, and it must not be handed a bar frame it did not ask for.

     What it shares is everything else: the event map, the dirty-flag redraw, the
     per-module enable flag, the class gate. That sharing is the point -- a
     feature gets the same dispatch a bar gets, so the parts of it that tick and
     redraw are somebody else's problem. ]]--
OB.features = {}

--[[ Switching a feature off has to take its windows off the screen, and this
     only ever hid `m.frame` -- singular.

     The damage meter owns `m.frames`, a list, so unticking Show did nothing
     visible at all: the module stopped ticking and its windows stayed exactly
     where they were. Reported as the toggle not working, which it was.

     Both are handled here rather than left to each module's OnUnbind, because a
     subsystem that forgets to implement one leaves a window nobody can close --
     and the failure looks like a broken checkbox rather than a missing method. ]]--
--[[ Every window a feature owns, off the screen.

     Both shapes, because a feature may own one frame or a list of them, and a
     subsystem that forgets which it is leaves a window nobody can close. ]]--
function OB.HideFeature(m)
    if m.frame then m.frame:Hide() end

    if m.frames then
        for i = 1, table.getn(m.frames) do m.frames[i]:Hide() end
    end
end

--[[ **One broken feature must not unbind the rest of the addon.**

     `BindSlots()` used to call every module's `OnBind` directly. A single Lua
     error therefore aborted the whole binding pass at that exact module: every
     bar/feature later in module order simply never registered its events or
     created its frame. From the outside that looks like unrelated systems were
     deleted together -- Threat Meter, Damage Meter, Map, OmniBars, and so on.

     Bind each module in isolation, report the failing subsystem, and keep going.
     Successful modules behave exactly as before; only the failure path changes. ]]--
local function safeModuleCall(m, method, a1)
    local fn = m and m[method]
    if not fn then return true end

    local ok, err
    if a1 ~= nil then
        ok, err = pcall(fn, m, a1)
    else
        ok, err = pcall(fn, m)
    end

    if ok then
        m.bindFault = nil
        return true
    end

    m.bindFault = tostring(err)
    if OB.Print then
        OB.Print("|cffff5511" .. (m.name or m.id or "module")
                .. " " .. method .. " failed: " .. tostring(err) .. "|r")
    end
    return false
end

local function registerModuleEvents(m)
    for e = 1, table.getn(m.events) do
        local ev = m.events[e]
        OB.eventMap[ev] = OB.eventMap[ev] or {}
        table.insert(OB.eventMap[ev], m)
    end
end

local function unbindFeatures()
    for id, m in pairs(OB.features) do
        safeModuleCall(m, "OnUnbind")
        OB.HideFeature(m)
        OB.features[id] = nil
    end
end

local function bindFeatures()
    for i = 1, table.getn(OB.moduleOrder) do
        local id = OB.moduleOrder[i]
        local m = OB.modules[id]

        if m.feature and OB.ModuleEnabled(id) then
            -- Build first. Only a feature that successfully bound is allowed
            -- into the live event/tick maps; a half-created feature otherwise
            -- turns one startup fault into repeated event faults afterwards.
            if safeModuleCall(m, "OnBind") then
                OB.features[id] = m
                registerModuleEvents(m)
                m.needsDraw = true
            else
                OB.HideFeature(m)
                OB.features[id] = nil
            end
        end
    end
end

function OB.BindSlots()
    for slotId, m in pairs(OB.bound) do
        safeModuleCall(m, "OnUnbind")
        if m.frame then m.frame:Hide() end
        m.slotId = nil
        OB.bound[slotId] = nil
    end

    unbindFeatures()
    OB.eventMap = {}

    for i = 1, table.getn(OB.barOrder) do
        local slotId = OB.barOrder[i]
        local id = OB.Occupant(slotId)
        local m = id and OB.modules[id]

        --[[ There was a guard here against one module being bound to two bars.
             It is unreachable now: a module names exactly one bar, so two bars
             cannot resolve to it. The invariant is structural rather than
             defended -- which is the good kind. ]]--

        if m then
            local slot = OB.profile.slots[slotId]
            m.slotId = slotId

            if not m.frame then
                if m.renders == "segments" then
                    m.frame = OB.CreateSegments("EqOB_" .. m.id, OB.container,
                            m.segments or 5)
                    for s = 1, m.frame.count do
                        OB.AttachMouse(m.frame.bars[s], slotId)
                    end
                else
                    m.frame = OB.CreateBar("EqOB_" .. m.id, OB.container)
                    OB.AttachMouse(m.frame, slotId)
                end
            else
                -- the frame may have been bound to a different slot last time
                if m.renders == "segments" then
                    for s = 1, m.frame.count do
                        OB.dragMap[m.frame.bars[s]] = slotId
                    end
                else
                    OB.dragMap[m.frame] = slotId
                end
            end

            OB.bound[slotId] = m

            if safeModuleCall(m, "OnBind", slot) then
                registerModuleEvents(m)
                m.needsDraw = true
            else
                if m.frame then m.frame:Hide() end
                OB.bound[slotId] = nil
                m.slotId = nil
            end
        end
    end

    -- after the bars, so a feature's events join the same map before it is
    -- turned into registrations
    bindFeatures()

    OB.events:UnregisterAllEvents()
    for ev in pairs(OB.eventMap) do OB.events:RegisterEvent(ev) end
    for i = 1, table.getn(OB.coreEvents) do
        OB.events:RegisterEvent(OB.coreEvents[i])
    end

    OB.RebuildTickables()

    OB.hud.needsDraw = true
end

--[[ **The modules that can tick, as a flat list.**

     The single OnUpdate used to walk `OB.bound` and `OB.features` with `pairs`
     every frame to find the few modules that animate. Most modules have no
     `OnUpdate` at all and can never tick, so the great majority of that walk
     answered "no" about the same modules a hundred and fifty times a second.

     pfDebug put `EquadisClassicOverhaulHUD:OnUpdate` second across every addon
     loaded, and this was the part of it that runs whether or not anything is
     animating. `/eq perf` never saw it: it wraps module methods, and this is
     the frame script that calls them.

     **`tickly` is still read per frame**, because modules flip it themselves at
     runtime -- the tooltip turns itself on for a fade and off again afterwards.
     What is precomputed is only which modules could ever tick, which changes
     when binding changes and not otherwise. ]]--
function OB.RebuildTickables()
    local list = {}

    for slotId, m in pairs(OB.bound) do
        if m.OnUpdate then table.insert(list, m) end
    end

    for id, m in pairs(OB.features) do
        if m.OnUpdate then table.insert(list, m) end
    end

    OB.tickables = list

    return list
end

OB.tickables = {}

-- ---------------------------------------------------------------------------
-- refresh
-- ---------------------------------------------------------------------------

--[[ Re-apply appearance to everything and queue a redraw.

     `force` re-styles as well as redrawing. Styling is cheap and this is not a
     per-frame path, so almost every caller passes true -- that is what makes a
     texture, border or size change land instantly. ]]--
function OB.Refresh(force)
    if not OB.profile then return end

    if force then
        OB.ApplyScale()

        for slotId, m in pairs(OB.bound) do
            local slot = OB.profile.slots[slotId]

            if m.renders == "segments" then
                OB.StyleSegments(m.frame, slot)
            else
                OB.StyleBar(m.frame, slot)
            end

            if m.OnStyle then m:OnStyle(slot) end
            m.needsDraw = true
        end

        --[[ A feature is styled with no slot, because it has none. It owns its
             own geometry and reads the shared media -- texture, font, border --
             straight from the profile, which is the whole of what the HUD's
             consistent look actually is. ]]--
        for id, m in pairs(OB.features) do
            if m.OnStyle then m:OnStyle() end
            m.needsDraw = true
        end

        OB.ApplyPositions()
        OB.UpdateMoveControls()
    end

    OB.RebuildTickables()

    OB.hud.needsDraw = true
    OB.Toggle()
end

--[[ Show or hide the whole HUD.

     Priority: the master switch, then hide-when-stealthed, then
     hide-out-of-combat. Test mode overrides all of it -- the preview must not be
     hidden by the very visibility rules it exists to help you set up. ]]--
function OB.Toggle()
    if not OB.profile then return end

    local visible = OB.profile.show and true or false

    if visible and OB.profile.hideDead and UnitIsDeadOrGhost("player") then
        visible = false
    end
    if visible and OB.profile.hideStealth and OB.inStealth then
        visible = false
    end
    if visible and OB.profile.hideOOC and not OB.inCombat then
        visible = false
    end

    if OB.testMode then visible = true end

    if visible then
        OB.container:Show()
    else
        OB.container:Hide()
    end

    --[[ Per-bar visibility: a bar can be switched off without unbinding its
         module.

         `selfHidden` is checked as well, because a module that has decided it
         has nothing to draw must not be overruled here. It used to be: this loop
         re-showed a bar the module had hidden, and whether that was ever undone
         came down to whether the module happened to be `tickly`. The distance
         readout redrew a frame later and flickered; combo points, which are not
         tickly, stayed wrongly visible until the count next changed. ]]--
    for slotId, m in pairs(OB.bound) do
        if OB.profile.slots[slotId].show and not m.selfHidden then
            m.frame:Show()
        else
            m.frame:Hide()
        end
    end

    OB.SetMouseEnabled(not OB.profile.locked)
    OB.UpdateMoveControls()
end

-- ---------------------------------------------------------------------------
-- test mode
-- ---------------------------------------------------------------------------

function OB.SetTestMode(on)
    if on == OB.testMode then return end

    OB.testMode = on and true or false
    OB.test.startedAt = GetTime()

    --[[ Features preview too, and the preview is worth *more* there than on a
         bar. Seeing a health bar's colours takes standing still; seeing a
         meter's takes a fight, a group and somebody taking damage. ]]--
    local function seed(m)
        if OB.testMode then
            if m.TestStart then m:TestStart(OB.test.startedAt) end
        else
            if m.TestStop then m:TestStop() end
        end
        m.needsDraw = true
    end

    for slotId, m in pairs(OB.bound) do seed(m) end
    for id, m in pairs(OB.features) do seed(m) end

    OB.Refresh(true)
    OB.RefreshPanel()
end

function OB.ToggleTestMode()
    OB.SetTestMode(not OB.testMode)
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

local coreHandlers = {}

coreHandlers.VARIABLES_LOADED = function()
    OB.LoadConfig()
    OB.CreateMover()
    OB.BindSlots()
    OB.Refresh(true)

    --[[ After the config, because the commands are read out of the account
         store it has just opened -- and before anything a player could type,
         which is everything from here on. ]]--
    if OB.RegisterCommands then OB.RegisterCommands() end

    --[[ **The version, out loud, every login.**

         The one question that has to be answerable before any other -- "which
         build am I running" -- had no answer inside the game: the version was
         printed only by the self test. Two sessions went on a tab that was
         present in the code and absent on screen, and neither could settle it
         because neither end knew what the other was looking at. ]]--
    OB.Print("v" .. (OB.version or "?") .. " loaded. /eq for settings.")

    --[[ **And a loud word when a tab has no module behind it.**

         The panel skips an entry whose module never registered, silently -- the
         addon looks fine and one subsystem is simply gone. That happens when a
         module file throws while loading: the client carries on with the next
         file and the registration never ran, which is exactly the shape of
         failure nobody can diagnose from the outside.

         Checked at login rather than when the panel opens, because the panel is
         built on first ask and somebody who cannot find a tab may never
         open it. ]]--
    local missing = {}

    for i = 1, table.getn(OB.featureTabs or {}) do
        local entry = OB.featureTabs[i]
        local ids = entry

        if type(entry) ~= "table" then ids = { entry } end

        for k = 1, table.getn(ids) do
            if not OB.modules[ids[k]] then table.insert(missing, ids[k]) end
        end
    end

    if table.getn(missing) > 0 then
        OB.Print("|cffff5511" .. table.concat(missing, ", ")
                .. " did not load|r -- those tabs are missing. Look for a Lua "
                .. "error above this line.")
    end

    --[[ RogueBars draws the same cluster, so both running at once shows two of
         everything. Say so once and leave it at that: forbidding the pair would
         make it impossible to compare them side by side, which is exactly what
         this version is for. ]]--
    if IsAddOnLoaded("RogueBars") then
        OB.Print("RogueBars is also loaded -- you will see two sets of bars. "
                .. "Disable it when you are done comparing.")
    end

    --[[ The rename. Said once, on the first login after it, because somebody who
         has just watched an addon disappear from their list and a differently
         named one appear deserves to be told their settings came across rather
         than having to go and check. ]]--
    --[[ The button in the Escape menu, added once the client has built it.
         Guarded rather than assumed: a server may ship its own game menu, and a
         missing button is one button missing rather than a login that throws. ]]--
    if OB.InstallGameMenuButton then OB.InstallGameMenuButton() end

    if OB.adoptedOldSaves then
        OB.Print("this was Equadis' OmniBars. Your profiles, layouts and "
                .. "everything the addon had learned came with it.")
    end
end

coreHandlers.PLAYER_ENTERING_WORLD = function()
    -- Persistent session flag for features that may be rebound after login.
    -- Item Database uses it to know that pfQuest-turtle's startup patching has
    -- completed and a reverse loot index is now safe to build.
    OB.worldEntered = true
    OB.inCombat = UnitAffectingCombat("player") and true or false
    OB.inStealth = OB.IsStealthed()
    OB.Refresh(true)

    --[[ Said here rather than at VARIABLES_LOADED: every addon has finished
         loading by now, so `IsAddOnLoaded` gives a complete answer. ]]--
    if OB.WarnConflicts then OB.WarnConflicts() end

    --[[ And the walkthrough, for an account that has never seen it. Here for
         the same reason the conflict warning is: the world is drawn, so a
         window that opens now is a window somebody actually sees rather than
         one that appears over a loading screen and gets dismissed. ]]--
    if OB.MaybeShowSetup then OB.MaybeShowSetup() end
end

coreHandlers.PLAYER_REGEN_DISABLED = function()
    OB.inCombat = true
    OB.Toggle()
end

coreHandlers.PLAYER_REGEN_ENABLED = function()
    OB.inCombat = false
    OB.Toggle()
end

-- stealth can start or stop without any other signal, and a druid changing form
-- reaches here too
local function auraChanged()
    OB.inStealth = OB.IsStealthed()
    OB.Toggle()
end

coreHandlers.PLAYER_AURAS_CHANGED = auraChanged
coreHandlers.UPDATE_SHAPESHIFT_FORMS = auraChanged
coreHandlers.PLAYER_DEAD = auraChanged
coreHandlers.PLAYER_ALIVE = auraChanged
coreHandlers.PLAYER_UNGHOST = auraChanged

OB.events:SetScript("OnEvent", function()
    local list = OB.eventMap[event]

    if list then
        for i = 1, table.getn(list) do
            local m = list[i]
            -- 'event' and 'arg1' are still in scope for the module
            if m.OnEvent then m:OnEvent() end
        end
    end

    if coreHandlers[event] then coreHandlers[event]() end
end)

for i = 1, table.getn(OB.coreEvents) do
    OB.events:RegisterEvent(OB.coreEvents[i])
end

-- ---------------------------------------------------------------------------
-- the single OnUpdate
-- ---------------------------------------------------------------------------

OB.hud:SetScript("OnUpdate", function()
    if not OB.profile then return end

    local now = GetTime()

    OB.UpdateDrag()

    --[[ And the camera, if a press on one of this addon's frames has turned
         into a drag. See `OB.StepCameraDrag`. ]]--
    if OB.StepCameraDrag then OB.StepCameraDrag() end

    --[[ Control, Shift and Alt together unlock everything. Polled because 1.12
         has no modifier event -- it is three cheap client calls, and only on a
         change does anything happen. See `OB.CheckEditHotkey`. ]]--
    if OB.CheckEditHotkey then OB.CheckEditHotkey() end

    if OB.testMode then
        for slotId, m in pairs(OB.bound) do
            if m.TestStep then m:TestStep(now) end
        end
        for id, m in pairs(OB.features) do
            if m.TestStep then m:TestStep(now) end
        end
    end

    --[[ Modules that animate continuously: a sweeping swing bar, a ticker
         spark. Walked as a flat list of the ones that *could* tick rather than
         with `pairs` over every bound module and every feature -- see
         `OB.RebuildTickables`. Most modules have no OnUpdate at all, and this
         runs a hundred and fifty times a second. ]]--
    local ticking = OB.tickables

    for i = 1, table.getn(ticking) do
        local m = ticking[i]
        if m.tickly then m:OnUpdate(now) end
    end

    if this.needsDraw then
        this.needsDraw = nil

        for slotId, m in pairs(OB.bound) do
            if m.needsDraw then
                m.needsDraw = nil
                if m.OnDraw then m:OnDraw() end
            end
        end

        for id, m in pairs(OB.features) do
            if m.needsDraw then
                m.needsDraw = nil

                --[[ A hidden feature still runs -- it is bound, it counts, it
                     ticks -- it simply does not draw. That is the whole
                     difference between Show and Enable: hide the damage meter
                     for a pull and the numbers are still there when you show it
                     again. ]]--
                if OB.ModuleShown(id) then
                    if m.OnDraw then m:OnDraw() end
                else
                    OB.HideFeature(m)
                end
            end
        end
    end
end)
