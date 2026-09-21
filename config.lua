--[[ Equadis' Classic Overhaul :: config

  Defaults, the profile store, and the merge that turns saved variables back into
  a live config table.

  The shape here is the whole point of the addon:

    slots   -- geometry and style. Never colour, never behaviour.
    assign  -- which module occupies which slot, per class.
    modules -- behaviour and colour. Never geometry.

  Because geometry lives on the slot and every character on a profile shares the
  slots table, a warrior's rage bar and a rogue's energy bar are literally the
  same rectangle. Only the occupant changes. Colour lives on the module
  deliberately: it is semantic, and it is the one thing that *should* differ when
  the occupant does.
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "Profiles") end

--[[ Three reports live in this file because the saved variables do, not
     because they are about profiles. They say whose they are. ]]--
local function SayWindows(msg) OB.Print(msg, "Windows") end
local function SayScan(msg) OB.Print(msg, "ChatScan") end
local function SayQol(msg) OB.Print(msg, "QoL") end

--[[ One position range, shared by the X/Y sliders, dragging, the arrow buttons
     and the saved values. They must never disagree: three separate ranges is how
     a bar ends up at a coordinate its own slider cannot reach. ]]--
OB.POS_MIN, OB.POS_MAX = -2000, 2000
OB.HEIGHT_MAX = 40

-- likewise one scale range, shared by the slider and the load-time clamp
OB.SCALE_MIN, OB.SCALE_MAX = 0.5, 1.5

function OB.ClampCoord(v)
    if not v then return 0 end
    if v < OB.POS_MIN then return OB.POS_MIN end
    if v > OB.POS_MAX then return OB.POS_MAX end
    return v
end

--[[ **How far a centre can sit and still leave the whole thing on screen.**

     The storage clamp above is +/-2000, which is a bound on the *number* and
     says nothing about the monitor. A bar dragged to 900 is saved, restored and
     invisible, and the only way back is a slider the user has to guess is the
     cause. That was reported twice.

     Everything positioned by this addon is anchored by its **centre** to the
     middle of the screen, so the limit on each axis is half the screen less half
     the object -- and the object's own scale has to come out of it, because an
     offset is in the scaled frame's units and the screen is not.

     Returns a positive magnitude; the caller bounds to +/- it. ]]--
function OB.ScreenLimit(axis, size, scale)
    local span = GetScreenWidth()
    if axis == "y" then span = GetScreenHeight() end
    if not span or span <= 0 then return OB.POS_MAX end

    if not scale or scale <= 0 then scale = 1 end

    local limit = ((span / 2) / scale) - ((size or 0) / 2)

    --[[ Something wider than the screen has no on-screen position at all, and
         pinning it to the centre is the only answer that is not a lie. ]]--
    if limit < 0 then return 0 end
    return limit
end

--[[ The container's scale relative to the screen, which is what an offset into
     it is measured in. Read as a ratio rather than as GetScale so a future
     reparenting cannot silently drop a factor. ]]--
function OB.ContainerScale()
    if not OB.container or not UIParent then return 1 end

    local mine = OB.container:GetEffectiveScale()
    local screen = UIParent:GetEffectiveScale()

    if not mine or not screen or screen <= 0 then return 1 end
    return mine / screen
end

--[[ **Where every meter window thinks it is, and where it actually is.**

     Written because two rounds of reading the code did not find why two damage
     windows come back from a reload stacked on each other, and a third round of
     reading it would not either. What settles it is one line of output: the
     stored coordinate beside the drawn one.

     Both, because they answer different halves. If the *stored* values are
     identical the loss happened before or during the save; if they differ but
     the *drawn* ones match, something is moving the frame after it is placed.
     Either way the next report is data instead of a screenshot.

     Screen size and scale are printed too, since every clamp in this addon is a
     function of them and none of it can be checked without knowing what they
     were on the machine that saw the bug. ]]--
function OB.PrintWindowReport()
    SayWindows("screen " .. OB.Round(GetScreenWidth() or 0) .. "x"
            .. OB.Round(GetScreenHeight() or 0)
            .. "  scale " .. tostring(OB.profile and OB.profile.scale))

    local damage = OB.modules and OB.modules.damage
    local cfg = damage and OB.profile.modules.damage

    if cfg and cfg.windows then
        SayWindows("damage meter: " .. table.getn(cfg.windows) .. " window(s), "
                .. table.getn(damage.frames or {}) .. " frame(s)")

        for i = 1, table.getn(cfg.windows) do
            local w = cfg.windows[i]
            local frame = damage.frames and damage.frames[i]

            --[[ The drawn position as a centre offset, so it is directly
                 comparable with the stored one rather than needing arithmetic
                 done by whoever is reading the output. ]]--
            local drawn = "no frame"
            if frame and frame:GetLeft() then
                drawn = OB.Round((frame:GetLeft() + (frame:GetWidth() / 2))
                                - ((GetScreenWidth() / 2) / (OB.profile.scale or 1)))
                        .. ", " ..
                        OB.Round((frame:GetBottom() + (frame:GetHeight() / 2))
                                - ((GetScreenHeight() / 2) / (OB.profile.scale or 1)))
            end

            OB.Raw("  [" .. i .. "] stored " .. OB.Round(w.x) .. ", "
                    .. OB.Round(w.y) .. "   drawn " .. drawn
                    .. "   w" .. w.width
                    .. "  " .. tostring(w.segment) .. "/" .. tostring(w.mode)
                    .. (frame and frame:IsShown() and "  shown" or "  hidden"))
        end
    else
        SayWindows("damage meter: not loaded")
    end

    local threat = OB.modules and OB.modules.threat
    local tcfg = threat and OB.profile.modules.threat

    if tcfg then
        SayWindows("threat meter: stored " .. OB.Round(tcfg.x) .. ", "
                .. OB.Round(tcfg.y)
                .. "   packet seen: " .. tostring(threat.seenPacket and true or false))
    end
end

--[[ **Windows do not overlap.**

     Every meter window registers its rectangle here when it is placed, and a
     window being dropped is pushed clear of the ones already down. Two windows
     stacked on top of each other are unreadable and, worse, unrecoverable: the
     one underneath cannot be grabbed to move it, so the only way out is a slider
     on a settings page for a window you cannot see.

     Rectangles are centre/size in screen units, which is the one form all the
     callers already have.

     Nothing here knows what a meter is. A window is an id and a rectangle, so a
     third subsystem that grows one is covered by registering. ]]--
OB.windowRects = {}

function OB.RegisterWindowRect(id, x, y, w, h)
    OB.windowRects[id] = { x = x, y = y, w = w, h = h }
end

local function overlaps(a, b)
    if math.abs(a.x - b.x) >= ((a.w + b.w) / 2) then return false end
    if math.abs(a.y - b.y) >= ((a.h + b.h) / 2) then return false end
    return true
end

--[[ The nearest position at or below the requested one that clears every other
     window, or the requested one if it already does.

     **Moved down, never sideways.** A window pushed horizontally lands beside
     the thing it collided with, which is usually where the next window is going
     to go -- so a third drop cascades. Down is the direction a list of windows
     grows anyway, and it is the one the user can predict. ]]--
function OB.AvoidWindows(id, x, y, w, h, scale)
    local mine = { x = x, y = y, w = w, h = h }
    local limit = OB.ScreenLimit("y", h, scale)

    for other, rect in pairs(OB.windowRects) do
        if other ~= id and overlaps(mine, rect) then
            --[[ Clear of its bottom edge, and give up rather than push a window
                 off the screen: a visible overlap beats an invisible window. ]]--
            local moved = rect.y - ((rect.h + h) / 2)
            if moved < -limit then return x, y end

            mine.y = moved
        end
    end

    return mine.x, mine.y
end

--[[ A window's coordinate, bounded to the screen against its own size.

     Same rule as a bar's, with the size passed in rather than looked up: a
     window's size is a property of the frame, and the frame is what has just
     been dragged. ]]--
function OB.ClampWindowCoord(axis, v, size, scale)
    v = OB.ClampCoord(OB.Round(v))

    local limit = OB.ScreenLimit(axis, size, scale)
    if v > limit then return OB.Round(limit) end
    if v < -limit then return OB.Round(-limit) end
    return v
end

--[[ One coordinate, bounded by both the storage range and the screen. Every
     write path for a bar's position goes through this -- drag, arrows, slider
     and restack -- because three ranges that disagree is how a bar reaches a
     coordinate its own slider cannot. ]]--
function OB.ClampSlotCoord(slotId, axis, v)
    v = OB.ClampCoord(v)

    local slot = OB.profile and OB.profile.slots and OB.profile.slots[slotId]
    if not slot then return v end

    local size = (axis == "x") and slot.w or slot.h
    local limit = OB.ScreenLimit(axis, size, OB.ContainerScale())

    if v > limit then return limit end
    if v < -limit then return -limit end
    return v
end

-- ---------------------------------------------------------------------------
-- defaults
-- ---------------------------------------------------------------------------

--[[ Bar geometry: the **centre** of each bar, as an offset from the container,
     with positive Y upward. Stacked in OB.barOrder with a 1px gap, health at the
     top. The spans below are the edges those centres produce:

       health 115..99     resource 98..74    mainhand 73..61
       offhand 60..48     ranged 47..35      distance 34..22
       secondary 21..9    extras 8..0

     x = 0 is therefore the middle of the screen, which is where a HUD under your
     character wants to start. It used to be the bar's left edge, so x = 0 put a
     200-wide bar half its width off to the right and every layout began by
     typing a number nobody should have had to work out.

     The panel lists them in this same order, so the list and the screen agree
     and there is nothing to reconcile.

     Most classes cannot fill all eight, which leaves a gap where their unusable
     bars sit. That is deliberate: geometry is account-wide, so closing the gap
     automatically for a rogue would move a hunter's bars. Restack Occupied Bars
     does it on demand -- see constraint 15. ]]--
OB.defaults = {
    schema = 44,

    -- visibility
    show = true,
    hideOOC = false,
    hideStealth = false,
    hideDead = true,

    -- movement
    --[==[ **Locked, because an unlocked bar takes the mouse and a bar with the
         mouse eats a click meant for whatever is under it.**

         `OB.SetMouseEnabled(not locked)` enables the mouse on every draggable
         HUD bar, and this shipped `false` -- so out of the box the swing timers,
         the combo points and the resource bar were all taking clicks, at MEDIUM
         strata, which is where the client's action buttons are. Anywhere one
         overlapped a button the click went to the bar and the spell did not
         cast. Reported as "sometimes I click a spell but it doesn't register",
         and the "sometimes" is the overlap.

         The action bars module reached the opposite conclusion about its own
         anchors and wrote down why: *a permanently draggable action bar is one
         you move by accident while clicking a spell on it*. Same reasoning, and
         the HUD had the other default.

         **This is edit mode's flag, not a preference of its own.**
         `OB.SetEditMode` writes `locked = not on`, so leaving edit mode locks
         and entering it unlocks. Shipping `false` meant shipping the
         edit-mode-is-on state without edit mode being on. ]==]
    locked = true,

    join = true,
    allowOverlap = false,

    --[[ **The alignment grid**, shown while edit mode is on and only then: a
         grid over the whole screen while you are playing is not an aid, and the
         one time it is one is while something is being moved.

         **On, because edit mode is the only thing that shows it.** It shipped
         off, which meant unlocking everything to move a frame gave you no way
         to line it up against anything -- and the switch that would have was on
         a different page, named for a thing that was not visible. Somebody who
         does not want it can say so; somebody who has not said anything is in
         edit mode precisely because they are lining something up.

         Thirty-two is a quarter of the usual bar height and a whole number of
         action buttons plus spacing, so most things land on it without being
         nudged. ]]--
    grid = true,
    gridSize = 32,

    --[[ Pixels left between stacked bars, on top of whatever the border needs.
         Read by RestackBars only: it changes where Restack *puts* things rather
         than moving anything by itself, because geometry is account-wide and a
         setting that silently relaid every character's HUD is the reflow bug
         this addon is built to avoid. ]]--
    barGap = 0,

    -- appearance
    scale = 1.0,
    texture = 8,           -- Interface\TargetingFrame\UI-StatusBar, RogueBars' default
    border = 1,            -- None
    font = OB.fontIndex["Roboto"] or 1,
    fontName = "Roboto",
    fontSize = 12,
    fontOutline = 2,   -- Thin; see OB.fontOutlines

    --[==[ **Dragging the camera from on top of a frame.**

         On, because the alternative is the camera not working wherever a
         nameplate happens to be, which on a pull is most of the screen. A press
         that does not move is still a click and still opens what it opened --
         see `OB.ArmCameraDrag`. ]==]
    cameraDrag = true,

    -- feedback
    audible = false,

    --[[ Per-module on/off. Absent means on: a module registered by a later
         version is enabled until the user says otherwise, which is the same
         principle as the defaults merge. ]]--
    modulesEnabled = {},

    --[[ Per-subsystem visibility, separate from modulesEnabled. See
         OB.ModuleShown for why the two are not one setting. Absent means
         shown. ]]--
    modulesShown = {},

    slots = {
        health    = { x = 0, y = 107, w = 200, h = 16, show = true,  flip = false,
                      bg = { 0, 0, 0, 0.5 }, textSize = 11 },
        resource  = { x = 0, y = 86,  w = 200, h = 24, show = true,  flip = false,
                      bg = { 0, 0, 0, 0.5 }, textSize = 12 },
        mainhand  = { x = 0, y = 67,  w = 200, h = 12, show = true,  flip = false,
                      bg = { 0, 0, 0, 0.5 }, textSize = 10 },
        offhand   = { x = 0, y = 54,  w = 200, h = 12, show = true,  flip = false,
                      bg = { 0, 0, 0, 0.5 }, textSize = 10 },
        ranged    = { x = 0, y = 41,  w = 200, h = 12, show = true,  flip = false,
                      bg = { 0, 0, 0, 0.5 }, textSize = 10 },
        distance  = { x = 0, y = 28,  w = 200, h = 12, show = true,  flip = false,
                      bg = { 0, 0, 0, 0 },   textSize = 10 },
        secondary = { x = 0, y = 15,  w = 200, h = 12, show = true,  flip = false,
                      bg = { 0, 0, 0, 0.5 }, textSize = 10 },
        extras    = { x = 0, y = 4,   w = 200, h = 8,  show = true,  flip = false,
                      bg = { 0, 0, 0, 0.5 }, textSize = 12 },
    },

    -- filled in by OB.RegisterModule as each module loads
    modules = {},
}

-- ---------------------------------------------------------------------------
-- profile migrations
--
-- A list rather than a run of inline statements, so each step says which schema
-- it produces. Equadis' Threat Meter does this as a hundred unlabelled lines in
-- the middle of LoadConfig, which will not survive five merged addons.
--
-- A migration is only needed when a key is renamed, restructured or inverted.
-- A *new* setting needs nothing: adding it to OB.defaults (or a module's
-- defaults) is what makes it exist for current users, because the merge is
-- saved-over-default.
-- ---------------------------------------------------------------------------

OB.profileMigrations = {
    --[[ aux went from a reserved spare to a slot that takes whatever module
         defaults there, so its sentinel changed meaning and a saved "none" has
         to be re-read as "auto".

         Overriding a saved value is normally the wrong thing to do. It is right
         here because in schema 1 no module named aux as its default slot at all,
         so "none" was the only value the slot could ever have held -- nobody
         chose it over an alternative, because there was none. An explicit choice
         made since is preserved: only the untouched default is rewritten. ]]--
    { 2, function(p)
        if p.assign and p.assign["*"] and p.assign["*"].aux == "none" then
            p.assign["*"].aux = "auto"
        end
    end },

    --[[ Slots became Bars.

         Six abstract slots you assigned modules to became eight named bars, each
         permanently paired with one module. The rename carries each bar's tuned
         width, height, X, text size, background and flip across; only Y is
         rewritten, by the restack below, because the order changed and the two
         new bars have to go somewhere.

         What is lost, and it is worth being straight about: a deliberate
         *assignment*. Someone who had put health where combo points went gets
         health back in the Health bar. There is no way to preserve that, because
         the thing that expressed it no longer exists -- and it is the feature the
         restructure was asked for in order to remove.

         Module settings move with their ids. `range` reads better as `distance`
         next to a `ranged` swing timer, and `swing_main` reads worse than
         `mainhand` beside a bar called Main Hand. ]]--
    { 3, function(p)
        local bars = {
            points = "extras", swingB = "offhand", swingA = "mainhand",
            aux = "distance",
            -- health and resource keep their names
        }

        local modules = {
            range = "distance", swing_main = "mainhand",
            swing_off = "offhand", swing_ranged = "ranged",
        }

        --[[ Merged over the new key, never assigned to it.

             By the time a migration runs, `p` already holds a full set of
             defaults with the saved values merged on top -- so p.slots.mainhand
             exists and is complete, while p.slots.swingA holds only whatever the
             save happened to carry. Assigning one to the other replaces a
             complete table with a partial one and quietly drops every key the
             old save never mentioned. Merging keeps the defaults underneath,
             which is the same rule that makes a new setting appear for existing
             users. ]]--
        local function rename(t, from, to)
            if not t or not t[from] then return end

            if type(t[to]) == "table" then
                OB.DeepMerge(t[to], t[from])
            else
                t[to] = t[from]
            end

            t[from] = nil
        end

        for from, to in pairs(bars) do rename(p.slots, from, to) end
        for from, to in pairs(modules) do rename(p.modules, from, to) end

        if p.modulesEnabled then
            for from, to in pairs(modules) do
                if p.modulesEnabled[from] ~= nil then
                    p.modulesEnabled[to] = p.modulesEnabled[from]
                    p.modulesEnabled[from] = nil
                end
            end
        end

        p.assign = nil

        --[[ Restack in the new order, keeping the cluster where it was.

             Done here rather than by calling OB.RestackBars because that lives in
             layout.lua, loads after this file, and works off which bars are
             *bound* -- which needs a profile that has finished loading. A
             migration cannot wait for any of that, and the job is a dozen lines
             of arithmetic anyway.

             The top of the existing stack is reused as the top of the new one, so
             the whole cluster stays where the user put it on screen rather than
             jumping to the shipped default. ]]--
        local top
        for id, bar in pairs(p.slots) do
            if not top or bar.y > top then top = bar.y end
        end
        if not top then top = 115 end

        local y = top
        for i = 1, table.getn(OB.barOrder) do
            local bar = p.slots[OB.barOrder[i]]
            if bar then
                bar.y = OB.ClampCoord(y)
                y = y - bar.h - 1
            end
        end

        Say("slots are now bars, and yours have been re-stacked in the new "
                .. "order. Drag them, or use Restack on the Bars page, to change it.")
    end },

    --[[ `hide` became `show`, inverted.

         A negative checkbox is a small papercut every single time it is read --
         "Hide Bar: unchecked" takes a beat to turn into "the bar is visible" --
         and this one had the additional problem of defaulting to off for two
         bars, so the readout you wanted was the one that looked disabled. A
         rename *and* an inversion is precisely the case the migration list
         exists for; a defaults change alone would have silently flipped every
         saved value.

         The low-health recolour goes at the same time. It is superseded by the
         planned colour-by-remaining-health, and leaving three dead keys in every
         saved profile forever is how a config file becomes archaeology. ]]--
    { 4, function(p)
        if p.slots then
            for id, bar in pairs(p.slots) do
                if bar.hide ~= nil then
                    bar.show = not bar.hide
                    bar.hide = nil
                end
            end
        end

        if p.modules and p.modules.health then
            p.modules.health.lowEnable = nil
            p.modules.health.lowThreshold = nil
            p.modules.health.lowColor = nil
        end
    end },

    --[[ Reveal the Distance bar.

         Schema 4 inverted `hide` into `show` faithfully, and faithfully was the
         bug: `aux` -- the slot that became Distance -- *shipped* hidden, so
         every profile carried `hide = true` on it without anyone having chosen
         that. The flip turned a shipped default into what looks like a decision,
         and the result was a Distance bar that came out of the upgrade switched
         off for every existing user while defaulting to on for new ones.

         Only Distance is affected. `secondary` did not exist before schema 3 and
         arrives from the defaults; every other bar shipped visible.

         This overrides a saved value, which is normally wrong. It is right here
         for the same reason the schema 2 step was: in the version that wrote it,
         the readout in that slot was hidden out of the box and the handover notes
         told you to run a command to reveal it, so `hide = true` means "never
         touched it" rather than "turned it off". The window in which somebody
         could have deliberately switched Distance off *since* the flip is a
         single version, and one release of a HUD nobody else runs.

         The general lesson, which is worth more than this fix: **inverting a key
         inverts defaults that were never chosen along with the choices.** When a
         migration flips a boolean, ask what the old default was, not just what
         the saved value is. ]]--
    { 5, function(p)
        if p.slots and p.slots.distance then p.slots.distance.show = true end
    end },

    --[[ The distance readout became one bar coloured by state.

         It used to draw four segments with exactly one lit, and its colours were
         named after the bands rather than after what they mean: `inColor`,
         `nearColor`, `outColor`. The new names say the state -- in range, too
         close, too far -- and there is a fourth for having no target at all.

         The three carry across because a colour somebody picked is worth
         keeping even though the thing it paints has changed shape. `dim`, which
         faded the unlit segments, has nothing left to fade.

         maxRange and deadZone survive but demote: they used to be *the* range
         and are now only the fallback for a slot holding a relic, or a client
         with no Nampower to ask. A saved 35/8 was the shipped default rather
         than a considered choice, so it is left alone -- the weapon type now
         answers ahead of it either way. ]]--
    { 6, function(p)
        local d = p.modules and p.modules.distance
        if not d then return end

        if d.inColor then d.inRangeColor = d.inColor end
        if d.nearColor then d.tooCloseColor = d.nearColor end
        if d.outColor then d.tooFarColor = d.outColor end

        d.inColor, d.nearColor, d.outColor, d.dim = nil, nil, nil, nil
    end },

    --[[ One background for every bar: black at 50%.

         The three swing bars shipped at 80% and everything else at 50%, for no
         reason anyone recorded -- the darker trough presumably read better under
         a thin bar at some point. It reads as inconsistency now.

         The distance readout goes fully transparent instead. It is always full
         and coloured by state, so its background can only ever be seen through a
         translucent state colour, where it muddies the one thing the bar is for.

         Applied by constraint 29: only a value that still *equals the old
         default* is rewritten. Anyone who picked their own background keeps it,
         because that one was a choice and these were not. ]]--
    { 7, function(p)
        if not p.slots then return end

        -- a colour is only "untouched" if every channel still matches
        local function isDefault(bg, r, g, b, a)
            if type(bg) ~= "table" then return false end
            return bg[1] == r and bg[2] == g and bg[3] == b and bg[4] == a
        end

        local swing = { "mainhand", "offhand", "ranged" }
        for i = 1, table.getn(swing) do
            local bar = p.slots[swing[i]]
            if bar and isDefault(bar.bg, 0, 0, 0, 0.8) then
                bar.bg = { 0, 0, 0, 0.5 }
            end
        end

        local distance = p.slots.distance
        if distance and isDefault(distance.bg, 0, 0, 0, 0.5) then
            distance.bg = { 0, 0, 0, 0 }
        end
    end },

    --[[ x and y became the bar's **centre** rather than its top-left corner.

         Y always converts, so every bar stays exactly where it is on screen: a
         top edge at 115 with a height of 16 is a centre at 107.

         X does not, and this is constraint 29 again. x = 0 was the shipped
         default for every bar and, under the old corner meaning, put a 200-wide
         bar half its width right of centre -- which is the thing that prompted
         the change. Nobody chose that, so an untouched 0 is left at 0 and the bar
         lands where the setting always claimed it would: the middle. An x
         somebody actually set was a considered position, so it converts and the
         bar does not move.

         The visible result of an upgrade is therefore: nothing moves vertically,
         and a layout still on the default horizontal position slides left to be
         properly centred. ]]--
    { 8, function(p)
        if not p.slots then return end

        for id, bar in pairs(p.slots) do
            bar.y = OB.ClampCoord(bar.y - (bar.h / 2))
            if bar.x ~= 0 then bar.x = OB.ClampCoord(bar.x + (bar.w / 2)) end
        end
    end },

    --[[ The Distance bar's no-target colour stopped being invisible, and the two
         action-slot settings stopped existing.

         Constraint 29 governs the colour: an alpha of 0 was the *shipped
         default*, so anyone still on it never chose an invisible bar -- they got
         one, and reasonably read it as the feature not working. That default is
         converted. Any other value, including a deliberate alpha of 0 reached by
         dragging the slider down, is a decision and is left alone. The test for
         "never chose" is an exact match against what shipped.

         `actionSlot` and `capture` are simply removed: the slot is found now
         rather than configured, so a stored number is a stale answer to a
         question nobody is asked any more. ]]--
    { 9, function(p)
        local distance = p.modules and p.modules.distance
        if not distance then return end

        distance.actionSlot = nil
        distance.capture = nil

        local c = distance.noTargetColor
        if c and c[1] == 0 and c[2] == 0 and c[3] == 0 and c[4] == 0 then
            distance.noTargetColor = { 0.12, 0.12, 0.12, 1 }
        end
    end },

    --[[ Text sides became text **positions**.

         Every label used to be nailed to an edge, and Swap Text Sides was the
         one way to get between the two. A position slider is the same choice
         with the whole width in between, so the boolean converts to its two
         endpoints and nothing anybody had set moves.

         The distance readout's fallback sliders go at the same time. They only
         ever applied to a ranged slot holding a relic, which is not a thing
         anyone can usefully tune. ]]--
    { 10, function(p)
        if not p.modules then return end

        local swings = { "mainhand", "offhand", "ranged" }
        for i = 1, table.getn(swings) do
            local m = p.modules[swings[i]]
            if m then
                if m.swap then
                    m.timerPos, m.speedPos = 100, 0
                else
                    m.timerPos, m.speedPos = 0, 100
                end
                m.swap = nil
            end
        end

        if p.modules.distance then
            p.modules.distance.maxRange = nil
            p.modules.distance.deadZone = nil
        end
    end },

    --[[ **One idea, one phrasing.** The bars say "Hide Out Of Combat"; the
         threat meter said "Show Out Of Combat", which is the same checkbox
         inverted. Two of them on one panel means every visit costs a moment
         working out which way round this one is.

         So the key flips with the caption, and the saved value flips with it --
         a migration that only renamed would silently turn the meter off for
         everyone who had left it at its default. ]]--
    { 11, function(p)
        local t = p.modules and p.modules.threat
        if not t then return end

        if t.showOutOfCombat ~= nil then
            t.hideOutOfCombat = not t.showOutOfCombat
            t.showOutOfCombat = nil
        end
    end },

    --[[ **A boolean with a sentence for a name becomes a two-entry list.**

         `localTime` was captioned "Use Your Clock, Not The Server's", which is a
         question you have to parse before you can answer it. `timeSource` is
         "Time: Local / Server", which you do not.

         The saved value carries: true was the local clock, which is one. ]]--
    { 12, function(p)
        local c = p.modules and p.modules.chat
        if not c then return end

        if c.localTime ~= nil then
            if c.localTime then c.timeSource = 1 else c.timeSource = 2 end
            c.localTime = nil
        end
    end },

    --[[ **A three-way list becomes a checkbox and a second swatch.**

         `nameColorMode` was "By Class / Random But Stable / One Color", which
         made the reader work out which of three things they were choosing
         between before they could choose. It is now "Color By Class", which
         overrides a Known Player Color swatch that is dimmed rather than hidden
         while it does.

         The saved answer carries as faithfully as it can: mode one was by class,
         so the checkbox goes on; the other two were not, so it goes off and
         whatever `nameColor` held becomes both swatches -- which is what those
         two modes actually looked like. Random-but-stable has no equivalent and
         is gone; a hash nobody could name was not earning three words on the
         page. ]]--
    { 13, function(p)
        local c = p.modules and p.modules.chat
        if not c then return end

        if c.nameColorMode ~= nil then
            c.nameClassColor = (c.nameColorMode == 1)

            if not c.nameClassColor and c.nameColor then
                c.nameKnownColor = { c.nameColor[1], c.nameColor[2],
                                     c.nameColor[3], c.nameColor[4] or 1 }
            end

            c.nameColorMode = nil
        end

        c.nameCommon = nil
    end },

    --[[ **Seven fade checkboxes become one.**

         Prat had one per window and so did this, and nobody has ever wanted
         window one to fade and window three not to -- it was seven rows for a
         decision made once. Any window having asked for it means yes, which is
         what somebody who ticked one of them meant. ]]--
    { 14, function(p)
        local c = p.modules and p.modules.chat
        if not c or type(c.fade) ~= "table" then return end

        local any = false
        for i = 1, 7 do if c.fade[i] then any = true end end

        c.fade = any
    end },

    --[[ **A bracket checkbox becomes the three-way list the names already
         use.** "Put Them In Brackets" could say square or nothing; angled was
         not offered because a boolean cannot offer three things.

         True was square, which is entry one. False was bare, which is entry
         three -- not entry two, and getting that backwards would put angle
         brackets on the links of everybody who had turned them off. ]]--
    { 15, function(p)
        local c = p.modules and p.modules.chat
        if not c then return end

        if type(c.urlBrackets) == "boolean" then
            if c.urlBrackets then c.urlBrackets = 1 else c.urlBrackets = 3 end
        end

        --[[ The space after a timestamp is not a setting any more: "01:23Bob:
             hi" is not a thing anybody chose. ]]--
        c.space = nil

        --[[ Searching lost its second switch: the box exists to search and
             searching needs the lines, so showing the box asks for both. ]]--
        c.search = nil
    end },

    --[[ **Twelve combinations become three answers.**

         `format` was an index into a list that wrote out every pairing of three
         independent choices -- twelve-or-twenty-four, meridiem or not, and how
         much of the clock with how much padding. A list of combinations makes
         the reader find their answer in a set rather than give it, and several
         of the twelve differed only after ten in the morning.

         Each old index maps to the three answers it stood for. The two that had
         no equivalent -- a lowercase meridiem, and a padded minute beside an
         unpadded hour -- land on their nearest neighbour, because the shapes are
         now consistent by construction: `h` and `m` pad together or not at
         all. ]]--
    { 16, function(p)
        local c = p.modules and p.modules.chat
        if not c or c.format == nil then return end

        --  index = { hour12, meridiem, shape }
        local was = {
            [1]  = { false, false, 3 },
            [2]  = { false, false, 4 },
            [3]  = { true,  true,  3 },
            [4]  = { true,  true,  4 },
            [5]  = { true,  true,  1 },
            [6]  = { true,  true,  1 },
            [7]  = { true,  true,  1 },
            [8]  = { true,  true,  3 },
            [9]  = { false, false, 1 },
            [10] = { true,  false, 1 },
            [11] = { true,  true,  2 },
            [12] = { false, false, 2 },
        }

        local pick = was[c.format] or was[1]

        c.hour12, c.meridiem, c.timeShape = pick[1], pick[2], pick[3]
        c.format = nil
    end },

    --[[ **Say and Yell split, and numbered channels stop being one thing.**

         A yell carries across a zone and a say does not, which is the whole
         difference between them; and General, Trade and whatever a guild has
         made for itself are three rooms that happen to share a naming scheme.
         Wanting one of those is not wanting all three, which is what a single
         checkbox was saying.

         The old answer carries to every part it stood for: somebody who wanted
         say-and-yell wanted both, and somebody who wanted numbered channels
         wanted the ones they are in. ]]--
    { 17, function(p)
        local c = p.modules and p.modules.chat
        if not c then return end

        if c.popupYell == nil then c.popupYell = c.popupSay and true or false end

        if type(c.popupChannel) ~= "table" then
            local was = c.popupChannel and true or false
            c.popupChannel = {}

            for i = 1, 10 do c.popupChannel[i] = was end
        end
    end },

    --[[ **Two settings become behaviour, and the anchor list flips.**

         Reopening in the channel you last used, and doing it for yell and emote
         too, were two switches for one thing nobody decides twice. They are how
         it works now.

         The message box anchor goes with them, for the same reason: the
         client's own place is under the chat frame, and wanting it elsewhere
         means wanting it exactly elsewhere. ]]--
    { 18, function(p)
        local c = p.modules and p.modules.chat
        if not c then return end

        c.sticky = nil
        c.stickyLoud = nil

        --[[ The Top/Bottom anchor is gone: the client's own place is under the
             chat frame, and somebody who wants it elsewhere wants it exactly
             elsewhere, which is what dragging is for. ]]--
        c.editAnchor = nil
    end },

    --[[ **Two settings that were asking the reader to make the author's
         decision, and one of them could not be made wrong on purpose.**

         The edit box colour goes after three goes at making it work. The last
         attempt did work, and that was the problem: a backdrop on a frame
         behind the box, painted with `UI-Tooltip-Background` -- the mottled
         brown tile every 2004 panel in this client is made of. Tinted or not it
         reads as the old chat window, which is the exact thing switching the
         border off is for. Nothing wanted is lost: the box sits over the chat
         frame's own background, which has a colour of its own on the Windows
         rows.

         The chat scan shape goes because two of its three answers were strictly
         worse. Level-and-class is five hundred and forty queries and three
         hours to pre-empt an overflow that happens at a handful of levels; by
         zone misses instances and anywhere the addon has no level range for.
         Every profile now sweeps by level and splits a full level by class,
         which is what the middle answer was buying, paid for only where it is
         needed. ]]--
    { 19, function(p)
        local c = p.modules and p.modules.chat
        if c then c.editColor = nil end

        local r = p.modules and p.modules.roster
        if r then r.scanMode = nil end
    end },

    --[[ **Seconds Between Queries goes, because only the server knows it.**

         The slider was asking the reader for a number they had no way to find:
         too low and every other query is dropped silently, too high and a sweep
         that could take twenty minutes takes an hour. 1.12 exposes no `/who`
         cooldown to read, so the gap is discovered instead -- it starts where a
         busy realm allows, widens on every dropped query and narrows on every
         answered one, and settles on the real limit within a couple of minutes.

         Nobody loses a rate they had chosen: a saved 10 was being throttled
         back to 40 by the server anyway, and a saved 60 was three times slower
         than it needed to be. ]]--
    { 20, function(p)
        local r = p.modules and p.modules.roster
        if not r then return end

        r.scanInterval = nil
    end },

    -- 0.85 shipped the newly-finished Tooltip subsystem disabled by default.
    -- Its settings page was still editable, so every control appeared broken
    -- until the separate Modules switch was found. 0.86 makes Tooltip a normal
    -- live subsystem and clears that one bad default for existing 0.85 profiles.
    { 21, function(p)
        if p.modulesEnabled and p.modulesEnabled.tooltip == false then
            p.modulesEnabled.tooltip = nil
        end
    end },

    --[[ **A colour setting says so in its key.** Five of Tooltip's did not --
         `background`, `friendlyTarget`, `neutralTarget`, `hostileTarget`,
         `playerTarget` -- so a reader met `cfg.hostileTarget` and had to go and
         look up whether that was a colour, a unit or a switch. Every other
         colour in the addon ends in `Color`, and the panel's own naming check
         had been reporting these five for as long as it has existed.

         Renamed rather than exempted, and carried forward here so somebody who
         picked their own tooltip colours keeps them.

         **Assigned unconditionally, not only when the new key is empty.** It
         never is: `LoadConfig` copies the defaults, merges the saved profile on
         top and *then* runs these steps, so by the time this reads `t[to]` it is
         holding the shipped default. Guarding on it being nil therefore threw
         away every colour this step exists to keep -- silently, and only for the
         people who had bothered to choose one. The presence of the *old* key is
         what says a value needs moving.

         Straight assignment rather than a merge: these are four-number lists,
         and merging a saved `{0.1, 0.2, 0.3}` into a default `{0, 0, 0, 0.85}`
         would keep the default's alpha. ]]--
    { 22, function(p)
        local t = p.modules and p.modules.tooltip
        if not t then return end

        local renamed = {
            background = "backgroundColor",
            friendlyTarget = "friendlyTargetColor",
            neutralTarget = "neutralTargetColor",
            hostileTarget = "hostileTargetColor",
            playerTarget = "playerTargetColor",
        }

        for from, to in pairs(renamed) do
            if t[from] ~= nil then
                t[to] = t[from]
                t[from] = nil
            end
        end
    end },

    --[[ **A shape became a number of rows, and a number of buttons.**

         The action bars offered six fixed arrangements -- 1x12, 2x6, 3x4 and so
         on -- picked from a list. The list is the wrong shape for the question:
         it cannot say "eight buttons in two rows", because eight buttons was not
         one of the six, and it cannot say "only show six of them" at all.

         The old index carried the row count already, so it converts exactly:
         entry three was three rows and still is. Anybody who had picked one
         keeps the bar they picked. ]]--
    { 23, function(p)
        local a = p.modules and p.modules.actionbars
        if not a then return end

        local rowsFor = { 1, 2, 3, 4, 6, 12 }

        for _, key in ipairs({ "main", "bottomLeft", "bottomRight",
                               "right", "left" }) do
            local old = a[key .. "Layout"]

            if old ~= nil then
                a[key .. "Rows"] = rowsFor[tonumber(old) or 1] or 1
                a[key .. "Layout"] = nil
            end

            --[[ Everything, which is what these bars did before there was a way
                 to say otherwise. Written rather than left to the default so an
                 old profile reads the same as a new one. ]]--
            if a[key .. "Buttons"] == nil then a[key .. "Buttons"] = 12 end
        end
    end },

    --[[ **One Hide Art switch becomes three.**

         It hid the gryphons, the bar background and the stance bar art
         together, and there was no way to keep one and lose another. The three
         it covered are now separate, and four more it never covered -- the XP
         bar, the micro menu, the bag bar and the page arrows -- have switches
         of their own.

         Assigned unconditionally rather than guarded on being unset, because
         defaults are merged *before* migrations run: by the time this executes
         all three already hold their default `true`, so a guard would find them
         present and leave somebody who had turned Hide Art off with three
         switches turned back on. That is the same trap migration 22 fell into
         with the tooltip colours. ]]--
    { 24, function(p)
        local a = p.modules and p.modules.actionbars
        if not a then return end

        if a.hideArt ~= nil then
            local hidden = a.hideArt and true or false
            a.hideGryphons = hidden
            a.hideBarArt = hidden
            a.hideStanceArt = hidden
            a.hideArt = nil
        end
    end },

    --[[ **Zone level ranges move from Quality Of Life to the Map.**

         They arrived on the Quality Of Life page because that is where
         quality-of-life things went, and they are about the map. The Map module
         did not exist to put them on until now.

         The key names are unchanged, so this is a move between tables rather
         than a rename: whatever somebody had set carries across exactly.

         Assigned unconditionally, because defaults merge *before* migrations
         run -- by the time this executes the map module already holds its own
         defaults, and a guard would find them present and discard the saved
         answer. Migration 22 and migration 24 both learned this the hard
         way. ]]--
    { 25, function(p)
        local qol = p.modules and p.modules.qol
        local map = p.modules and p.modules.map
        if not qol or not map then return end

        if qol.zoneLevels ~= nil then
            map.zoneLevels = qol.zoneLevels
            qol.zoneLevels = nil
        end

        if qol.zoneFaction ~= nil then
            map.zoneFaction = qol.zoneFaction
            qol.zoneFaction = nil
        end
    end },

    --[[ **The nameplate border stops being a target highlight and becomes a
         threat readout.**

         There were two switches on one surface: a flat colour that said "this
         is the one you clicked", and the four-state threat colouring. The flat
         one is gone -- the target's size and its glow say that already, twice
         -- and its two keys go with it rather than sitting in every saved
         profile forever. ]]--
    { 26, function(p)
        local n = p.modules and p.modules.nameplates
        if not n then return end

        n.targetBorder = nil
        n.targetBorderColor = nil

        --[[ Overriding a saved value, which is normally wrong and is right here
             for the reason the schema 5 step gives: this shipped off, so
             `false` is "never touched it" rather than "turned it off". The
             border it colours is now the only thing on a plate that reports
             threat, and the switch that used to occupy that surface has just
             been deleted -- so leaving it off would upgrade a working plate
             into a blank one. ]]--
        n.threatBorder = true

        --[[ The casting colour was gold to agree with the cast bar underneath
             it, which is one state saying itself twice. Rewritten only where it
             is still the shipped gold, so anybody who picked their own keeps
             it. ]]--
        local c = n.threatCastColor
        if c and c[1] == 0.90 and c[2] == 0.80 and c[3] == 0.00 then
            n.threatCastColor = { 0.25, 0.55, 1.00, 1 }
        end
    end },

    --[==[ **The border wears the art the target ring was drawn in.**

         `borderColor` was picked to sit under a flat one-pixel rectangle and is
         now a tint on that art, so the shipped near-black is rewritten and a
         colour somebody chose is not.

         **`targetGlow` is deliberately not touched here**, though a version of
         this step deleted it while that ring was gone. Defaults merge *before*
         migrations run, so nil-ing a key does not restore its default -- it
         removes it for the rest of that load, and the module reads a colour
         that is not there. A setting that is coming back is left alone. ]==]
    { 27, function(p)
        local n = p.modules and p.modules.nameplates
        if not n then return end

        local c = n.borderColor
        if c and c[1] == 0.06 and c[2] == 0.06 and c[3] == 0.06 then
            n.borderColor = { 0.65, 0.65, 0.65, 1.00 }
        end
    end },

    --[==[ **A changed default reaches nobody who already had a profile.**

         `minimapIconSize` was raised from fourteen to twenty when the note
         beside it was written -- "large enough to cover the client's own blip",
         a size chosen against something else on screen rather than a taste. It
         changed nothing for anybody already playing, because defaults are
         merged into a profile once and a profile that has the key keeps its
         own value forever.

         So the marker went on being drawn at fourteen, which the crop above now
         makes a genuine fourteen pixels and is still under the blip's size.

         Moved only where it is still the old default. Fourteen chosen on
         purpose is indistinguishable from fourteen inherited, and of the two
         readings the one that changes somebody's deliberate setting is the
         worse mistake -- but fourteen was never a choice anybody was offered:
         it was the shipped value, and the slider has been in the panel for one
         version. ]==]
    { 28, function(p)
        local m = p.modules and p.modules.map
        if not m then return end

        if m.minimapIconSize == 14 then m.minimapIconSize = 20 end
    end },

    --[[ Show Metrics is gone -- see the note where `ApplyMetrics` was. Only the
         key goes: the readout it switched on is hidden by the client on every
         load, so there is nothing in the world to put back. ]]--
    { 29, function(p)
        local q = p.modules and p.modules.qol
        if not q then return end

        q.showMetrics = nil
    end },

    --[==[ **The bag window is switched on once.**

         It shipped off, so every profile written before this carries an
         explicit `false` -- and a default flipped to true reaches none of them,
         for the reason the step before this one gives at length: defaults are
         merged into a profile once.

         The result is a bag window that is finished, tested and invisible, and
         nothing on screen says which switch is holding it shut.

         **This overrides a saved value, which is normally wrong.** It is right
         here for the same reason the schema 5 and 26 steps give: `false` is what
         this shipped as rather than something somebody chose, and the reason it
         shipped that way -- another bag addon in the install to defer to -- is
         no longer the arrangement. Done once. Switching it off after this
         sticks. ]==]
    { 30, function(p)
        p.modulesEnabled = p.modulesEnabled or {}
        if p.modulesEnabled.bags == false then p.modulesEnabled.bags = nil end
    end },

    --[[ The bag grid went from ten columns to sixteen -- see the note beside the
         default. Moved only where it is still the ten it shipped as, so a width
         somebody set on the slider is kept. ]]--
    { 31, function(p)
        local b = p.modules and p.modules.bags
        if not b then return end

        if b.columns == 10 then b.columns = 16 end
    end },

    --[[ Empty bag slots are no longer drawn -- see the note beside the default.
         Overriding a saved `true` because that is what this shipped as rather
         than something somebody chose, and because the empties were also what
         put the holes in the grid. Switching them back on after this sticks. ]]--
    { 32, function(p)
        local b = p.modules and p.modules.bags
        if not b then return end

        if b.showEmpty == true then b.showEmpty = nil end
    end },

    --[==[ **The world map markers are still drawing at twice their size.**

         The same shape of miss as the minimap markers two steps ago, and for the
         same reason. `playerIconSize` was corrected to thirteen when the markers
         were cropped to their ink -- thirteen being what the client's own
         marker actually is, measured off `WorldMapPartyIcon.blp`, which is 16x16
         with ink from 1,1 to 14,14.

         Before the crop the number was the size of a mostly empty *file*, so
         twenty-four drew a twelve pixel mark and looked right. After it, the
         number is the size of the mark, and the same twenty-four draws one
         nearly twice the client's.

         Defaults are merged into a profile once, so the correction reached
         nobody who was already playing. Moved only from the two values this
         shipped as -- twenty-four, and the sixteen that was read off the frame
         rather than off the ink. ]==]
    { 33, function(p)
        local m = p.modules and p.modules.map
        if not m then return end

        if m.playerIconSize == 24 or m.playerIconSize == 16 then
            m.playerIconSize = 13
        end
    end },

    --[==[ **The four states go back to the border, and the glow marks the
         target.**

         Schema 26 moved them the other way and this moves them back, which is
         worth being plain about rather than quietly flipping: the border is on
         every plate, so a colour there answers "what is that one doing" about
         the whole screen; the glow is on one plate by definition and could only
         ever describe the plate you were already looking at.

         Both switches are written rather than nil'd. Defaults merge before
         migrations run, so nil-ing a key removes it for the rest of that load
         and the module reads a setting that is not there -- the trap the schema
         27 note records at length. ]==]
    { 34, function(p)
        local n = p.modules and p.modules.nameplates
        if not n then return end

        n.threatBorder = true
        n.threatGlow = false

        --[[ Rewritten only where it is still the gold this shipped, so a colour
             somebody picked for their own glow survives. ]]--
        local c = n.targetGlowColor
        if c and c[1] == 1.00 and c[2] == 0.82 and c[3] == 0.35 then
            n.targetGlowColor = { 1.00, 1.00, 1.00, 0.90 }
        end
    end },

    --[==[ **The bag settings are thrown away and Bagnon's put in their place.**

         Asked for in those words, and right: the old table described a window
         that no longer exists. `blizzArt` picked whether to rebuild the client's
         backpack behind the grid; `group` bucketed items by type on screen;
         `showEmpty` hid the empty slots. Bagnon's grid is a picture of the bags
         -- every slot, in bag order, nothing rearranged -- so all three describe
         decisions that are no longer taken anywhere.

         **Written rather than nil'd**, every one of them, for the reason the
         schema 27 and 34 notes give at length: defaults merge into a profile
         before migrations run, so clearing a key removes it for the rest of that
         load and the module reads a setting that is not there. The three that
         are nil'd are the three nothing reads any more, which is the only case
         where clearing is safe.

         **This overrides values somebody may have chosen**, which is normally
         wrong and is the point here. The instruction was to start again from
         Bagnon's defaults, and a column count carried forward from a window with
         different geometry is exactly the kind of survival that makes a rebuild
         look half-done. Done once; anything set after this sticks.

         `protect` is not touched. It is not a Bagnon setting and not a layout
         one -- it is the guard on selling or trading a favourite, and quietly
         re-arming a switch somebody deliberately disarmed is not a migration. ]==]
    --[==[ **Settings whose controls are gone, put back to their defaults.**

         Removing a row does not remove the value behind it: `OB.Get` still
         reads whatever a profile last saved, so somebody who once turned mob
         health measurement off would have kept it off forever with nothing on
         screen to explain why. That is the failure mode migration 22 and 24
         both hit from the other direction.

         Cleared rather than assigned, so the defaults merge decides the value
         and there is one place that knows what it is. ]==]
    { 36, function(p)
        local u = p.modules and p.modules.unitframes

        if u then
            --[==[ **Two switches read once, into the choice they were.**

                 Classic art wins where both were set: it is the one that
                 changes which art is drawn at all, and compact is a variation
                 on art that classic is not using. Read before anything else
                 here clears keys, and only when the new one has not been
                 written -- a profile that has already chosen is not
                 re-derived. ]==]
            if u.frameMode == nil then
                if u.classicFrameArt then
                    u.frameMode = "classic"
                elseif u.compact == false then
                    u.frameMode = "overhaul"
                else
                    u.frameMode = "compact"
                end
            end

            u.classicFrameArt = nil
            u.compact = nil

            --[[ The name colour override, shared and per frame. Walked rather
                 than listed: the per-frame keys are `<id>_nameColor`, and
                 spelling out four ids here would be a second list to keep in
                 step with the one in the module. ]]--
            for key in pairs(u) do
                if string.find(key, "nameColor", 1, true) then u[key] = nil end
            end

            --[[ The four frame switches. Cleared, so the defaults merge
                 decides -- and it says all four. ]]--
            u.replacePlayer = nil
            u.replaceTarget = nil
            u.replaceTargetTarget = nil
            u.replacePet = nil

            u.mobHealth = nil
            u.mobHealthPrecision = nil
            u.mobHealthStableMax = nil
            u.feignHealth = nil
            u.retarget = nil
            u.plannedMobFleeIcon = nil
        end

        --[[ The client bar elements this addon replaces. Assigned rather than
             cleared: the default changed from shown to hidden, and a profile
             saved under the old one holds an explicit `false` that a merge
             would keep. ]]--
        local a = p.modules and p.modules.actionbars

        --[[ Nameplate settings whose controls are gone: the two health
             estimate numbers, and the five hide-health-bar switches that
             repeated the five show-a-plate switches above them. Cleared so the
             defaults merge decides. ]]--
        local n = p.modules and p.modules.nameplates

        if n then
            n.healthEstimateHits = nil
            n.healthEstimateDamage = nil
            n.hideEnemyNpcHealth = nil
            n.hideNeutralNpcHealth = nil
            n.hideEnemyPlayerHealth = nil
            n.hideFriendlyNpcHealth = nil
            n.hideFriendlyPlayerHealth = nil
        end

        --[[ The edit gesture is unconditional now. Cleared rather than left
             at whatever was saved: a profile holding `false` would have kept
             the only drag-anything gesture switched off with nothing on screen
             left to explain it. ]]--
        p.editHotkey = nil

        if a then
            --[[ The bag button lost its switch and the client's bag slots are
                 hidden for good, so a saved `false` here would leave somebody
                 with no way to open their bags from the bar. ]]--
            a.bagButton = nil

            a.hideBarArt = nil
            a.hideStanceArt = nil
            a.hideXP = true
            a.hideMicroMenu = true
            a.hidePerformanceBar = true
            a.hideBags = true
        end
    end },

    --[==[ **Numbered 37, not 35, and that was a real bug for one version.**

         The steps run in list order and each one that fires writes its own
         number into the profile. An entry numbered *below* one earlier in the
         list can therefore never fire: by the time the loop reaches it the
         schema is already higher.

         This was written as 35 and appended after a step numbered 36, on the
         assumption that the end of the list held the highest number. It did
         not. So the whole bag reset -- the thing the rewrite depends on to
         clear settings describing a window that no longer exists -- was dead
         code that ran for nobody.

         The check at the bottom of the suite now walks this list and fails if
         it is not ascending, which is the only way to notice: nothing about a
         migration that quietly does not run is visible from the game. ]==]
    { 37, function(p)
        local b = p.modules and p.modules.bags
        if not b then return end

        --[[ Settings for a window that is gone. Safe to clear precisely because
             nothing reads them. ]]--
        b.blizzArt = nil
        b.showEmpty = nil
        b.group = nil
        b.showMoney = nil

        --[[ `FrameDefaults` and the `inventory` profile out of Bagnon's
             `core/api/settings.lua`, transcribed. ]]--
        b.columns = 10
        b.bankColumns = 14
        b.itemScale = 1
        b.spacing = 2
        b.bagBreak = 0
        b.reverseBags = false
        b.reverseSlots = false
        b.showBags = false
        b.hiddenBags = {}

        b.bagToggle = true
        b.sort = true
        b.search = true
        b.money = true

        b.color = { 0, 0, 0, 0.5 }
        b.borderColor = { 1, 1, 1, 1 }

        b.glowQuality = true
        b.glowPoor = true
        b.glowAlpha = 0.5
        b.slotBackground = true

        --[==[ **And the pins, which were account-wide rather than in here.**

             They recorded "this item draws at square nine", which only meant
             anything while the window arranged items itself. Left behind they
             are a table nothing reads that grows every time somebody who
             remembers the feature tries it. Cleared here because this is the
             step that removes the feature, even though it reaches outside the
             profile to do it. ]==]
        if type(EquadisClassicOverhaulDB) == "table" then
            EquadisClassicOverhaulDB.bagPins = nil
            EquadisClassicOverhaulDB.bagGroups = nil
        end
    end },

    --[==[ **The client's minimap dots come back on.**

         Hiding them means handing the engine a transparent blip sheet, and the
         one that shipped was 8x8 -- too small for the cells the engine indexes
         out of it, so it drew vanilla's missing-texture green square on the
         minimap instead of drawing nothing.

         The sheet is the size of the client's own now and the setting has been
         defaulted off, but a default only reaches a profile that has never seen
         the key. Anybody who logged in on the version in between has `true`
         written down and would keep the green square until they found the
         switch.

         Written to `false` rather than nil'd, for the reason the schema 27 note
         gives at length: defaults merge before migrations run, so clearing a
         key removes it for the rest of that load. ]==]
    { 38, function(p)
        local m = p.modules and p.modules.map
        if not m then return end

        m.hideDefaultBlips = false
    end },

    --[==[ **The font outline switch, read as the weight it was.**

         It is a list now -- None, Thin, Thick -- so an old `true` is Thin, which
         is the only outline there was, and `false` is None.

         Both places it can be stored are walked: the profile's own key, and each
         module's, because a module's look override lives in its own settings
         rather than in a table of its own. See `OB.Look`.

         Written rather than cleared, for the reason schema 27 gives at length:
         the defaults are merged before migrations run, so nil'ing a key removes
         it for the rest of that load rather than falling back to the
         default. ]==]
    { 39, function(p)
        local function convert(t)
            if type(t) ~= "table" then return end
            if t.fontOutline == true then t.fontOutline = 2 end
            if t.fontOutline == false then t.fontOutline = 1 end
        end

        convert(p)

        if type(p.modules) == "table" then
            for _, m in pairs(p.modules) do convert(m) end
        end
    end },

    --[==[ **Every learned zone scale is thrown away.**

         `waypoints.lua` had the world axes swapped against `map.lua` -- see the
         note on `WorldPosition` -- so every number `CalibrateZone` wrote was a
         north displacement divided by an east-west map fraction. Silithus had
         learned 10.4 yards per map width against a true figure near 4900, and a
         waypoint most of a zone away read as five yards.

         Cleared rather than corrected, because there is nothing in a wrong
         reading to correct *from*: the pair of samples that produced it is long
         gone. A cleared zone re-learns itself within a few seconds of walking,
         which is cheaper than carrying a number that reads a mile as five
         yards. ]==]
    { 40, function(p)
        local w = p.modules and p.modules.waypoints
        if not w then return end

        w.zoneYards = nil
    end },

    --[==[ **The arrow's colour switch becomes a choice of two schemes.**

         `colorByFacing` was a boolean, and its off state had no colour setting
         at all -- the arrow simply went white. The replacement names both
         schemes and gives each its own colours, so an old profile has to say
         which of the two it was already in.

         Written rather than cleared, for the reason schema 27 gives at length:
         defaults merge before migrations run, so nil-ing a key removes it for
         the rest of that load rather than falling back to the default. ]==]
    { 41, function(p)
        local w = p.modules and p.modules.waypoints
        if not w then return end

        if w.colorByFacing == false then
            w.arrowColorMode = 1
        elseif w.colorByFacing == true then
            w.arrowColorMode = 2
        end

        w.colorByFacing = nil
    end },

    --[==[ **Everybody's bars are locked.**

         `locked` is edit mode's flag -- `OB.SetEditMode` writes `not on` into it
         -- and it shipped `false`, which is the unlocked state without edit mode
         being on. An unlocked HUD bar takes the mouse, at the same strata the
         action buttons are drawn at, so a click landing on one never reached the
         spell underneath.

         Anybody who has used edit mode already has `true` written down, because
         leaving it writes that. So the only profiles this moves are the ones
         that never entered it -- which are exactly the ones with the fault. ]==]
    { 42, function(p)
        p.locked = true
    end },

    --[==[ **The icon fills the slot now, as it does on the client's own buttons.**

         The three-pixel inset existed to give a mis-sized ring something to sit
         on: `UI-Quickslot2` was drawn at the button's size, so its rim landed
         inside the icon and the inset kept the picture out from under it. With
         the ring sized the way the client sizes it (v0.99.288) the rim lands on
         the icon's edge and the inset is a dark band round every item.

         Only the untouched default moves. Somebody who set 3 on purpose set the
         same number the default was, and there is no telling those apart -- but
         nobody chose a band, and a slider is one drag away. ]==]
    { 43, function(p)
        local b = p.modules and p.modules.bags
        if b and b.iconInset == 3 then b.iconInset = 0 end
    end },

    --[[ **The stat text, a size smaller.** Nine was the shipped size and was
         still read as too big beside the client's own labels. The shipped
         nine moves to eight; a size somebody dragged to stays, for the reason
         schema 43 gives. ]]--
    { 44, function(p)
        local c = p.modules and p.modules.characterpanel
        if c and c.statFontSize == 9 then c.statFontSize = 8 end
    end },
}

function OB.RunProfileMigrations(p)
    p.schema = p.schema or 1

    for i = 1, table.getn(OB.profileMigrations) do
        local step = OB.profileMigrations[i]
        if p.schema < step[1] then
            step[2](p)
            p.schema = step[1]
        end
    end
end

-- ---------------------------------------------------------------------------
-- importing RogueBars
-- ---------------------------------------------------------------------------

local rbTextureNames = {
    ["ShaguPlates"] = 2, ["TukUI"] = 3, ["ElvUI"] = 4,
    ["Gradient"] = 5, ["Striped"] = 6,
    ["Wow Status"] = 8, ["Wow Skill"] = 10,
}

-- RogueBars 2.3 renamed its own texture keys; apply that first
local rbTextureRenames = {
    ["wow status"] = "Wow Status", ["wow skill"] = "Wow Skill",
    ["shaguplates"] = "ShaguPlates", ["tukui"] = "TukUI",
    ["elvui"] = "ElvUI", ["gradient"] = "Gradient", ["striped"] = "Striped",
}

local rbBorders = { ["none"] = 1, ["thin"] = 2, ["standard"] = 3 }

local function copyColor(src, fallback)
    if type(src) ~= "table" then return fallback end
    return { src[1] or 0, src[2] or 0, src[3] or 0, src[4] or 1 }
end

-- one RogueBars element's geometry onto one slot
local function importGeometry(slot, el)
    if type(el) ~= "table" then return end

    if el.Width then slot.w = el.Width end
    if el.Height then slot.h = el.Height end
    if el.X then slot.x = OB.ClampCoord(el.X) end
    if el.Y then slot.y = OB.ClampCoord(el.Y) end
    if el.TextSize then slot.textSize = el.TextSize end
    if el.Hide ~= nil then slot.show = not el.Hide end
    if el.Flip ~= nil then slot.flip = el.Flip and true or false end
    slot.bg = copyColor(el.BGColor, slot.bg)
end

local function importSwing(cfg, el)
    if type(el) ~= "table" then return end

    cfg.color = copyColor(el.Color, cfg.color)
    if el.Decimals then cfg.decimals = el.Decimals end
    if el.Swap ~= nil then cfg.swap = el.Swap and true or false end
    if el.ShowTimer ~= nil then cfg.showTimer = el.ShowTimer and true or false end
    if el.ShowSpeed ~= nil then cfg.showSpeed = el.ShowSpeed and true or false end
    if el.Deplete ~= nil then cfg.deplete = el.Deplete and true or false end
end

--[[ Seed a fresh profile from an installed RogueBars.

     RogueBarsConfig is account-wide, which is exactly the behaviour wanted here:
     one imported layout that every character then shares. Nothing is written
     back to RogueBarsConfig and nothing is deleted from it, so uninstalling
     the Overhaul loses nothing.

     RogueBars' own pre-1.1 migration chain is deliberately not ported. A config
     five versions stale imports its post-merge shape; run RogueBars once to
     normalise it first if that matters. ]]--
function OB.ImportRogueBars(p)
    local rb = RogueBarsConfig
    if type(rb) ~= "table" or type(rb.Elements) ~= "table" then return false end

    if rb.Scale then p.scale = rb.Scale end
    if rb.Show ~= nil then p.show = rb.Show and true or false end
    if rb.HideStealth ~= nil then p.hideStealth = rb.HideStealth and true or false end
    if rb.HideOOC ~= nil then p.hideOOC = rb.HideOOC and true or false end
    if rb.Audible ~= nil then p.audible = rb.Audible and true or false end
    if rb.Locked ~= nil then p.locked = rb.Locked and true or false end
    if rb.Join ~= nil then p.join = rb.Join and true or false end
    if rb.AllowOverlap ~= nil then p.allowOverlap = rb.AllowOverlap and true or false end

    if type(rb.Texture) == "string" then
        local name = rbTextureRenames[rb.Texture] or rb.Texture
        p.texture = rbTextureNames[name] or p.texture
    end

    if type(rb.Border) == "string" then
        p.border = rbBorders[rb.Border] or p.border
    end

    local e = rb.Elements

    --[[ RogueBars' four elements onto the bars that succeeded them. Its Y values
         come across untouched, so an imported layout lands exactly where it was
         -- the other four bars are new and sit wherever the defaults put them,
         which is what Restack is for. ]]--
    importGeometry(p.slots.extras, e.Combo)
    importGeometry(p.slots.offhand, e.OffHand)
    importGeometry(p.slots.mainhand, e.MainHand)
    importGeometry(p.slots.resource, e.Energy)

    if p.modules.combopoints and type(e.Combo) == "table"
            and type(e.Combo.Colors) == "table" then
        for i = 1, 5 do
            if e.Combo.Colors[i] then
                p.modules.combopoints.colors[i] =
                        copyColor(e.Combo.Colors[i], p.modules.combopoints.colors[i])
            end
        end
    end

    if p.modules.offhand then importSwing(p.modules.offhand, e.OffHand) end
    if p.modules.mainhand then importSwing(p.modules.mainhand, e.MainHand) end

    --[[ RogueBars only ever drew energy, so its bar colour and ticker mode are
         the energy variant's. The other power types keep their own defaults. ]]--
    if p.modules.power and type(e.Energy) == "table" then
        local energy = p.modules.power.byType[3]
        if energy then
            energy.color = copyColor(e.Energy.Color, energy.color)
            if e.Energy.Ticker then energy.ticker = e.Energy.Ticker end
        end
        p.modules.power.tickerColor =
                copyColor(e.Energy.TickerColor, p.modules.power.tickerColor)
        if e.Energy.TextMode then p.modules.power.textMode = e.Energy.TextMode end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- database migrations
--
-- Each import is guarded by db.migrated.<name>, so reinstalling an old addon
-- can never re-import over a layout that has since been tuned.
-- ---------------------------------------------------------------------------

--[==[ **A setting that moved pages has to take its value with it.**

     The navigation was reorganised so that settings sit where somebody would
     look for them, and that means keys changing module. A key that changes
     module changes saved table -- so without this, everybody who had turned
     item borders off finds them on again, and the only clue is that the setting
     is somewhere else now.

     Copied rather than moved-and-trusted: the old value is only used when the
     new one has never been written, so a profile that has already been through
     this keeps whatever it was set to afterwards. Then the old key is cleared,
     because a stale copy left behind is a value that will look authoritative to
     somebody reading the saved variables later. ]==]
local function migrateKeys(db, flag, fromId, toId, keys)
    if db.migrated[flag] then return false end
    db.migrated[flag] = true

    for _, profile in pairs(db.profiles or {}) do
        local from = profile.modules and profile.modules[fromId]

        if from then
            profile.modules[toId] = profile.modules[toId] or {}
            local to = profile.modules[toId]

            for i = 1, table.getn(keys) do
                local key = keys[i]

                if from[key] ~= nil then
                    if to[key] == nil then to[key] = from[key] end
                    from[key] = nil
                end
            end
        end
    end

    return true
end

function OB.RunDBMigrations(db)
    db.migrated = db.migrated or {}

    --[==[ **Weapon buffs kept the size they were being drawn at.**

         They used to borrow the buff row's numbers, so somebody who had made
         their buffs small had made their poisons small too. Splitting them into
         their own group with their own defaults would have snapped those icons
         back to thirty pixels on upgrade -- a change nobody asked for, in a
         setting they had deliberately moved.

         So the old shared values are copied across once. Only where the new key
         has never been written, so this cannot undo a later decision. ]==]
    if not db.migrated.weaponBuffGroup then
        db.migrated.weaponBuffGroup = true

        for _, profile in pairs(db.profiles or {}) do
            local buffs = profile.modules and profile.modules.buffframes

            if buffs then
                if buffs.enchantSize == nil then
                    buffs.enchantSize = buffs.buffSize
                end
                if buffs.enchantSpacingX == nil then
                    buffs.enchantSpacingX = buffs.buffSpacingX
                end
                if buffs.enchantGrowX == nil then
                    buffs.enchantGrowX = buffs.buffGrowX
                end
            end
        end
    end

    --[==[ Item borders and model dragging were on the Quality Of Life page,
         which is where settings went when nobody had decided where they
         belonged. Both are about the character sheet.

         The Character Panel ships enabled for anybody who had either of these
         on, because otherwise the move reads as the features being removed. ]==]
    if migrateKeys(db, "characterPanelSplit", "qol", "characterpanel",
            { "rarityBorders", "modelRotate", "modelRotateSpeed" }) then
        for _, profile in pairs(db.profiles or {}) do
            local panel = profile.modules and profile.modules.characterpanel

            if panel and (panel.rarityBorders or panel.modelRotate)
                    and profile.modulesEnabled then
                profile.modulesEnabled.characterpanel = true
            end
        end
    end

    if not db.migrated.roguebars then
        db.migrated.roguebars = true
        db.pendingRogueBarsImport = true
    end

    -- UnitScan originally shipped disabled by default even though its target
    -- list is account-wide and editable while disabled.  That made it possible
    -- to add a perfectly valid rare and never scan it.  If somebody already
    -- has targets from that first build, enable the feature once when upgrading.
    if not db.migrated.unitscanEnabledWithTargets then
        db.migrated.unitscanEnabledWithTargets = true
        if type(db.unitScanTargets) == "string"
                and string.find(db.unitScanTargets, "%S") then
            for _, profile in pairs(db.profiles or {}) do
                if profile.modulesEnabled then
                    profile.modulesEnabled.unitscan = nil
                end
            end
        end
    end

    --[[ **The standalone unit frame addon's settings, imported once.**

         This slot said "reserved" for a long time and did nothing, so somebody
         switching from the addon this one replaces arrived at default settings
         and had to set everything again -- while their old choices sat in
         `UnitFramesConfig` untouched.

         The four switches are client CVars rather than addon settings, so they
         survive the addon being uninstalled and are worth reading whether or
         not its saved variables are still there.

         Runs once, keyed on the store's version. Anything already answered in
         this addon is left alone: an import is for a profile that has not been
         told yet, not a periodic overwrite of somebody's later choices. ]]--
    if db.version and db.version < 2 then
        --[[ 1 = value/max, 2 = value, 3 = percent, 4 = value (percent),
             5 = none -- the standalone's numbering, from its own comment. ]]--
        local FORMATS = { "max", "value", "percent", "valuepct", "none" }

        for _, profile in pairs(db.profiles or {}) do
            local uf = profile.modules and profile.modules.unitframes

            if uf then
                local old = UnitFramesConfig

                if type(old) == "table" then
                    if uf.healthText == nil and FORMATS[old.HealthFormat] then
                        uf.healthText = FORMATS[old.HealthFormat]
                    end

                    if uf.powerText == nil and FORMATS[old.PowerFormat] then
                        uf.powerText = FORMATS[old.PowerFormat]
                    end

                    if uf.healthSize == nil then uf.healthSize = old.HPFontSize end
                    if uf.powerSize == nil then uf.powerSize = old.MPFontSize end
                    if uf.nameSize == nil then uf.nameSize = old.NameTextFontSize end

                    if uf.healthX == nil then uf.healthX = old.HealthTextX end
                    if uf.healthY == nil then uf.healthY = old.HealthTextY end
                    if uf.powerX == nil then uf.powerX = old.PowerTextX end
                    if uf.powerY == nil then uf.powerY = old.PowerTextY end
                    if uf.nameX == nil then uf.nameX = old.NameTextX end
                    if uf.nameY == nil then uf.nameY = old.NameTextY end

                    if uf.decimals == nil then uf.decimals = old.Decimals end
                    if uf.nameOutline == nil then uf.nameOutline = old.NameOutline end
                    if uf.colorText == nil then uf.colorText = old.ColoredSbText end
                    if uf.hidePetText == nil then uf.hidePetText = old.HidePetText end
                    if uf.statusGlow == nil then uf.statusGlow = old.StatusGlow end

                    if uf.classColorHealth == nil then
                        uf.classColorHealth = old.PlayerClassColor
                    end

                    if uf.npcClassColor == nil then
                        uf.npcClassColor = old.NPCClassColor
                    end
                end

                --[==[ **The four CVars, which outlive the addon that set them
                     -- and which most people never had at all.**

                     Read through `OB.CVar`. `GetCVar` raises on a name the
                     client does not know, and the `type(GetCVar) == "function"`
                     that used to guard this checks the function and says nothing
                     about the name. On any install that never ran the donor
                     addon, this threw inside `LoadConfig` -- which is not one
                     feature failing, it is the addon not loading. ]==]
                if uf.classPortrait == nil then
                    uf.classPortrait = OB.CVar("ufClassPortrait") == "1"
                end

                if uf.darkMode == nil then
                    uf.darkMode = OB.CVar("ufDarkMode") == "1"
                end

                if uf.improvedPet == nil then
                    uf.improvedPet = OB.CVar("ufImprovedPet") == "1"
                end

                if uf.compact == nil then
                    uf.compact = OB.CVar("ufCompactMode") == "1"
                end
            end
        end
    end

    -- reserved: v2 TWT_CONFIG -> modules.threat
    --           v3 ShaguDPS_Config -> modules.meter
    --           (v4 UnitFramesConfig import is implemented above)

    --[[ Two now: the unit frame import above runs once, for stores written
         before it existed. ]]--
    db.version = 2
end

-- ---------------------------------------------------------------------------
-- load
-- ---------------------------------------------------------------------------

function OB.CharacterKey()
    local realm = GetRealmName() or "Unknown"
    return realm .. " - " .. (UnitName("player") or "Unknown")
end

--[[ Build the live config for this character.

     The resulting table *is* db.profiles[name] -- not a copy of it. That is
     Equadis' Threat Meter's trick and it removes an entire class of bug: there
     is no save step to forget, because every write already lands in the saved
     variables. ]]--
--[[ **The saved variables under their old name, adopted once.**

     The addon was called Equadis' OmniBars and its store was
     `EquadisOmniBarsDB`. Renaming the addon renames the store with it, and a
     rename with nothing behind it is somebody logging in to find every profile,
     every remembered player, every learned price and the list of things they
     never want to keep, all gone -- with the old data still sitting in the file,
     unreachable, looking exactly like a bug.

     So the old global is adopted whole if the new one is empty. Taken by
     reference rather than copied: it *is* the same store under a new name, and
     copying would leave two that drift.

     **The old one is not deleted.** A saved variable this addon no longer
     declares stops being written the moment the TOC changes, so it is already
     frozen -- and leaving it there means going back a version still works. It
     costs a few kilobytes on disk and it is the difference between a rename you
     can undo and one you cannot. ]]--
local function adoptOldName()
    if type(EquadisClassicOverhaulDB) == "table" then return false end
    if type(EquadisOmniBarsDB) ~= "table" then return false end

    EquadisClassicOverhaulDB = EquadisOmniBarsDB
    return true
end

function OB.LoadConfig()
    local adopted = adoptOldName()

    if type(EquadisClassicOverhaulDB) ~= "table" then
        EquadisClassicOverhaulDB = { version = 0, profiles = {}, chars = {}, migrated = {} }
    end

    --[[ Said once, and worth saying: somebody who renamed the folder deserves to
         know their settings came with it rather than having to check. ]]--
    if adopted then
        OB.adoptedOldSaves = true
    end

    local db = EquadisClassicOverhaulDB
    db.profiles = db.profiles or {}
    db.chars = db.chars or {}

    --[[ **What is known about other players, outside the profile entirely.**

         Everything else in this file is a setting: something you chose, which
         belongs to a profile because a second character might choose otherwise.
         This is not that. That Grimtusk is a level 60 warrior is a fact about
         the world, and it does not become less true when your rogue logs in.

         So it sits at the root of the saved variables next to `profiles` rather
         than inside one. Switching profile keeps it, resetting a profile keeps
         it, and a note you wrote on your main is there on your alt -- which is
         the whole point of writing it down.

         Held as a live reference for the same reason the profile is: there is
         no save step to forget, because every write already lands in the file.

         `OB.Roster()` is the read path and answers a table per player. It grows
         with the number of people you have seen, which is the cost of knowing
         anything about them, and `/eq roster forget` is the way back. ]]--
    db.roster = db.roster or {}
    OB.roster = db.roster

    --[[ **The never-want list**, beside the roster and outside the profile for a
         related but different reason.

         This one *is* a choice, so the profile has a claim on it. It loses,
         because of what the choice is about: a profile decides how your
         interface looks on this character, and "I never want another Broken
         Fang" is not about this character at all. Somebody who says it once has
         said it for the account, and a list that destroys things is the last
         list that should quietly empty itself when you switch profile.

         Held as a string rather than a table because that is what the panel
         edits -- one field, comma separated, the same shape as the chat
         module's never-join list. A table would need a list widget to be worth
         anything, and the field is directly readable, which for a list of things
         you are about to destroy is the more important property.

         Read through `OB.TrashList` rather than aliased into `OB` the way the
         roster is. A string is immutable, so an alias is a *copy* -- it would
         hold whatever the list said at login and never see an edit, which for a
         list that destroys things is the worst possible failure: it works, it
         just works on yesterday's answer. ]]--
    db.trash = db.trash or ""

    --[[ **Automatic loot-roll lists.**

         These are account-wide for the same reason as the never-keep list:
         "always Need Corrupted Sand" is a statement about the item, not about
         the current profile or character. The panel edits comma-separated text
         directly, and the slash commands append to these same strings. ]]--
    db.autoNeed = db.autoNeed or ""
    db.autoGreed = db.autoGreed or ""

    --[[ **Names UnitScan watches for**, account-wide for the same reason the
         never-keep list is: a rare spawn is not a character-specific UI
         preference. Kept as comma-separated text because that is exactly what
         the UnitScan page edits. ]]--
    db.unitScanTargets = db.unitScanTargets or ""

    --[[ **What things sell for**, learned rather than known.

         1.12 tells you an item's vendor price in exactly one place: its tooltip,
         while a merchant window is open. Nowhere else, and there is no call that
         answers it. So the value of the grey in your bag is unknowable while you
         are standing in a cave, which is precisely when you want to know.

         What is learnable is learnable once. A price seen at a vendor is true
         forever -- vendor prices do not change -- so it goes here, account-wide
         beside the roster, and the answer is available from then on wherever you
         are and on whichever character. ]]--
    db.prices = db.prices or {}
    OB.prices = db.prices

    --[[ **Quests you have said to hand in without reading.**

         Account-wide, and this one is not a close call: the quests people
         remember are repeatables -- the Alterac Valley turn-ins, the daily
         hand-ins -- and those are done on every character that has them. A list
         that started empty on each alt would be the wrong shape entirely.

         Keyed by title, which is what the client gives at every point in the
         conversation. There is no quest id in 1.12's quest frame API. ]]--
    db.quests = db.quests or {}
    OB.quests = db.quests

    --[[ **How long a spell takes to cast**, learned rather than shipped.

         1.12 announces that a mob has begun casting and says nothing about how
         long it will take. ShaguPlates carries a database of every spell in the
         game to answer that; this learns instead -- every spell the player casts
         reports its exact duration to the client, and mobs cast a great many of
         the same spells players do.

         A cast time does not change, so a seen one is true forever. Account-wide
         beside the roster and the prices, on the same argument. ]]--
    --[[ **What each of your abilities is worth in threat**, measured rather than
         looked up.

         There is no threat-per-spell API, the server packet carries totals only,
         and the published coefficients are a wiki page that is wrong for half
         the abilities on a private server. So it is measured: the packet gives
         your total twice a second, the combat log says what you did in between,
         and a window with exactly one event in it attributes cleanly.

         Account-wide, on the same argument as the cast times and the prices --
         what Sinister Strike costs in threat is a fact about the game. ]]--
    --[[ **How much health a mob actually has**, worked out rather than asked for.

         1.12 answers `UnitHealthMax` for a mob with 100, because what it gives
         is a percentage. MobHealth3's insight is that the percentage and the
         damage you deal are two views of one number: hit something for 340,
         watch it drop four percent, and it has eight and a half thousand.

         Keyed by name *and level*, which is not fussiness -- a level 22 Defias
         Thug and a level 24 one are different creatures with the same name, and
         averaging them gives a number wrong for both.

         Account-wide, on the same argument as everything else in this group. ]]--
    db.mobHealth = db.mobHealth or {}
    OB.mobHealth = db.mobHealth

    db.threatPerSpell = db.threatPerSpell or {}
    OB.threatPerSpell = db.threatPerSpell

    db.castTimes = db.castTimes or {}
    OB.castTimes = db.castTimes

    --[[ **What a spell's icon looks like**, learned the same way and for the
         same reason.

         The combat log announces "X is afflicted by Y" and carries no picture.
         The only place an icon is readable is your own target, so the first
         sighting there records it -- and from then on any unit afflicted by that
         spell can be drawn with it, target or not.

         An icon does not change, so a seen one is true forever. ]]--
    db.auraIcons = db.auraIcons or {}
    OB.auraIcons = db.auraIcons

    --[[ **Which channels you have taken out of which chat window.**

         Not a setting anybody types: it is a record of what somebody did. The
         client re-adds a channel to a window every time it re-joins that channel
         -- which on a server that force-joins World is every login -- and there
         is nowhere it remembers that you took it out again.

         So the removal is remembered here and re-applied. Per character, because
         which window a channel belongs in is genuinely per character: the alt
         with one chat window and the main with four do not agree, and a shared
         answer would be wrong for one of them.

         Shaped as window index -> lowercased channel -> true. ]]--
    --[[ **Channel colours, keyed by name rather than by number.**

         1.12 stores them by number, and the numbers move: leave one channel and
         every channel below it shifts up, taking your colours with it. The green
         you set on your guild channel is now on Trade.

         Account-wide, because a colour is a preference about a channel rather
         than about a character, and setting it again on every alt is the chore
         this removes. ]]--
    db.channelColors = db.channelColors or {}
    OB.channelColors = db.channelColors

    db.chatRemovals = db.chatRemovals or {}

    local me = OB.CharacterKey()
    db.chatRemovals[me] = db.chatRemovals[me] or {}
    OB.chatRemovals = db.chatRemovals[me]

    OB.RunDBMigrations(db)

    local key = OB.CharacterKey()
    local name = db.chars[key] or "Default"
    db.chars[key] = name

    -- a fresh copy every load, so a colour table is never aliased into defaults
    local p = OB.DeepCopy(OB.defaults)

    local existing = db.profiles[name]
    if existing then
        OB.DeepMerge(p, existing)
    elseif db.pendingRogueBarsImport then
        db.pendingRogueBarsImport = nil
        if OB.ImportRogueBars(p) then
            Say("imported your RogueBars layout into the '" .. name .. "' profile.")
        end
    end
    db.pendingRogueBarsImport = nil

    OB.RunProfileMigrations(p)

    -- guard every media index against a list that changed between versions
    if not OB.textures[p.texture] then p.texture = 1 end
    if not OB.borders[p.border] then p.border = 1 end

    -- the font list can gain entries, which shifts every index after the
    -- insertion point, so the saved *name* is authoritative when present
    if p.fontName and OB.fontIndex[p.fontName] then p.font = OB.fontIndex[p.fontName] end
    if not OB.fonts[p.font] then p.font = OB.fontIndex["Roboto"] or 1 end
    p.fontName = OB.fonts[p.font]

    for id, slot in pairs(p.slots) do
        slot.x = OB.ClampCoord(slot.x)
        slot.y = OB.ClampCoord(slot.y)
        if slot.w < 0 then slot.w = 0 end
        if slot.h > OB.HEIGHT_MAX then slot.h = OB.HEIGHT_MAX end
        if slot.h < 1 then slot.h = 1 end
    end

    --[[ The slider's range and this clamp are one setting in two places and must
         not disagree, or a profile can hold a scale its own slider cannot reach.
         A saved value above the ceiling is brought down rather than refused. ]]--
    if p.scale < OB.SCALE_MIN then p.scale = OB.SCALE_MIN end
    if p.scale > OB.SCALE_MAX then p.scale = OB.SCALE_MAX end

    db.profiles[name] = p
    OB.profile = p
    OB.profileName = name

    return p
end

--[[ There was an assignment layer here -- ResolveOccupant, SlotOf, AssignSlot --
     letting any module be put in any slot, per class, with "auto" and "none"
     sentinels. It is gone. A module names its bar and that is the end of it, so
     "which module draws here" is a registry lookup (OB.Occupant) rather than a
     stored, migratable, user-editable answer.

     It went because it was not earning its complexity: every bar can be dragged
     anywhere, so the ordering it existed to express was already the user's, and
     the dropdown that exposed it was the single most confusing control in the
     panel. ]]--

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

function OB.ProfileNames()
    local names = {}
    for name in pairs(EquadisClassicOverhaulDB.profiles) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

--[[ Every profile switch goes the same way: rebuild config, rebind, redraw, and
     re-read the panel.

     That last step is not optional and its absence was a real bug. LoadConfig
     replaces OB.profile wholesale, so every control on the panel is now reading
     a table that no longer exists -- and the profile dropdown in particular kept
     naming the profile you had just switched away from, which made switching
     look broken while it had in fact worked. The slash path called RefreshPanel
     itself; the panel path did not, so the control that most needed refreshing
     was the one that never got it. ]]--
local function reload()
    OB.LoadConfig()

    --[[ The look cache is keyed by module and refilled on every read, so this
         is hygiene rather than a fix: a module the old profile had and the new
         one does not would otherwise keep a table nothing asks for again.
         `ForgetLooks` was written for exactly this call and nothing made it. ]]--
    if OB.ForgetLooks then OB.ForgetLooks() end

    OB.BindSlots()
    OB.Refresh(true)
    OB.RefreshPanel()
end

function OB.SetProfile(name)
    if not EquadisClassicOverhaulDB.profiles[name] then
        Say("no profile named '" .. tostring(name) .. "'.")
        return
    end
    EquadisClassicOverhaulDB.chars[OB.CharacterKey()] = name
    reload()
    Say("using profile '" .. name .. "'.")
end

-- a new profile is a copy of the current one: starting from bare defaults is
-- almost never what someone making a variant wants
function OB.NewProfile(name)
    if not name or name == "" then return end
    if EquadisClassicOverhaulDB.profiles[name] then
        Say("profile '" .. name .. "' already exists.")
        return
    end
    EquadisClassicOverhaulDB.profiles[name] = OB.DeepCopy(OB.profile)
    EquadisClassicOverhaulDB.chars[OB.CharacterKey()] = name
    reload()
    Say("created profile '" .. name .. "' from '" .. OB.profileName .. "'.")
end

function OB.CopyProfile(from)
    local source = EquadisClassicOverhaulDB.profiles[from]
    if not source then
        Say("no profile named '" .. tostring(from) .. "'.")
        return
    end
    if from == OB.profileName then return end

    EquadisClassicOverhaulDB.profiles[OB.profileName] = OB.DeepCopy(source)
    reload()
    Say("copied '" .. from .. "' over '" .. OB.profileName .. "'.")
end

function OB.DeleteProfile(name)
    if name == "Default" then
        Say("the Default profile cannot be deleted.")
        return
    end
    if not EquadisClassicOverhaulDB.profiles[name] then return end

    EquadisClassicOverhaulDB.profiles[name] = nil

    -- anyone left pointing at it falls back to Default
    for char, used in pairs(EquadisClassicOverhaulDB.chars) do
        if used == name then EquadisClassicOverhaulDB.chars[char] = "Default" end
    end

    reload()
    Say("deleted profile '" .. name .. "'.")
end

--[[ Reset the *current* profile only, including its assignments. Other profiles
     and every character's binding are left alone -- see OB.ResetAll for the
     bigger hammer. ]]--
function OB.ResetProfile()
    EquadisClassicOverhaulDB.profiles[OB.profileName] = nil
    reload()
    Say("profile '" .. OB.profileName .. "' restored to defaults.")
end

--[[ Every profile, and only the profiles.

     **The roster survives**, because it is not a setting and this is the button
     that undoes settings. Somebody resetting their layout has not asked to
     forget a note they wrote about a guildmate two characters ago, and there is
     a separate way to say that when they mean it. ]]--
function OB.ResetAll()
    local db = EquadisClassicOverhaulDB
    local roster = db and db.roster
    local trash = db and db.trash
    local autoNeed = db and db.autoNeed
    local autoGreed = db and db.autoGreed

    EquadisClassicOverhaulDB = nil
    reload()

    if roster then
        EquadisClassicOverhaulDB.roster = roster
        OB.roster = roster
    end

    --[[ Kept for the same reason, and more firmly. Silently emptying a list that
         destroys things is bad; silently *refilling* one would be worse, and a
         reset that dropped it would do exactly that the next time somebody
         retyped it from memory and got a name slightly wrong. ]]--
    if trash then EquadisClassicOverhaulDB.trash = trash end
    if autoNeed then EquadisClassicOverhaulDB.autoNeed = autoNeed end
    if autoGreed then EquadisClassicOverhaulDB.autoGreed = autoGreed end

    Say("every profile restored to defaults. What you know about other "
            .. "players is kept -- '/eq roster forget' clears that.")
end

function OB.TrashList()
    return (EquadisClassicOverhaulDB and EquadisClassicOverhaulDB.trash) or ""
end

function OB.AutoNeedList()
    return (EquadisClassicOverhaulDB and EquadisClassicOverhaulDB.autoNeed) or ""
end

function OB.AutoGreedList()
    return (EquadisClassicOverhaulDB and EquadisClassicOverhaulDB.autoGreed) or ""
end

--[[ How much is in there, split by how much of it is actually useful. A name
     with no class and no note is somebody who spoke once; a name with a note is
     something you wrote by hand and would mind losing. ]]--
function OB.PrintRosterReport()
    local seen, classed, leveled, noted = 0, 0, 0, 0

    for _, known in pairs(OB.roster or {}) do
        seen = seen + 1
        if known.class then classed = classed + 1 end
        if known.level then leveled = leveled + 1 end
        if known.note then noted = noted + 1 end
    end

    SayScan(seen .. " players known: " .. classed .. " with a class, "
            .. leveled .. " with a level, " .. noted .. " with a note.")
end

--[[ The remembered quests, which are the one account-wide list built entirely by
     accident -- every entry is a Control-click somebody made while looking at a
     quest, rather than something typed deliberately.

     That is exactly why it needs printing. A list nobody can see and nobody
     remembers building is a list that eventually hands in a quest they wanted to
     read. ]]--
function OB.PrintQuestList()
    local titles = {}

    for title, saved in pairs(OB.quests or {}) do
        local what = ""
        if saved.accept and saved.complete then what = " (accept and hand in)"
        elseif saved.accept then what = " (accept)"
        elseif saved.complete then what = " (hand in)" end

        table.insert(titles, title .. what)
    end

    if table.getn(titles) == 0 then
        SayQol("no quests are remembered.")
        return
    end

    table.sort(titles)
    SayQol(table.getn(titles) .. " quests remembered:")

    for i = 1, table.getn(titles) do OB.Raw("  " .. titles[i]) end
end

function OB.ForgetQuests()
    local seen = 0
    for _ in pairs(OB.quests or {}) do seen = seen + 1 end

    EquadisClassicOverhaulDB.quests = {}
    OB.quests = EquadisClassicOverhaulDB.quests

    SayQol("forgot " .. seen .. " quest" .. (seen == 1 and "" or "s") .. ".")
end

--[[ And the way to say it when they do mean it. ]]--
function OB.ForgetRoster()
    local seen = 0
    for _ in pairs(OB.roster or {}) do seen = seen + 1 end

    EquadisClassicOverhaulDB.roster = {}
    OB.roster = EquadisClassicOverhaulDB.roster

    SayScan("forgot " .. seen .. " player" .. (seen == 1 and "" or "s") .. ".")
end
