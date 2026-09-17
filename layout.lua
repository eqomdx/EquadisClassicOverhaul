--[[ Equadis' Classic Overhaul :: layout

  The container, slot placement, collision, dragging and the movement overlay.

  Nothing here knows what a slot contains -- it moves rectangles. Which module
  draws into a rectangle is hud.lua's problem.

  Two rules carried over from RogueBars, both of which cost real debugging time:

  The container is an anchor, not a box. RogueBars pinned it at a fixed 200x56
  and its handover notes warn in capitals never to resize it: it is centre/bottom
  anchored, so growing it shifts its TOPLEFT -- the point every slot hangs from
  -- and moving one unjoined slot pushed the others the opposite way, while
  moving the bottom one was exactly cancelled. With six slots reaching 115px
  *above* that corner the rect bounds nothing it draws anyway, so it is 1x1 here.
  The rule becomes "the anchor is a point", which cannot be violated by accident.

  There is exactly one movement code path. The X/Y sliders, the arrow buttons and
  the mouse all call OB.NudgeSlot, and every one of them shares OB.POS_MIN/MAX.
  Two ways to move a bar is two chances for them to disagree.
]]--

local OB = EquadisClassicOverhaul

local floor = math.floor

-- mouse drag state. Positions are computed from a snapshot taken at drag start,
-- so rounding never accumulates over a long drag.
local drag = {
    active = false,
    slot = nil,
    cursorX = 0,
    cursorY = 0,
    start = {},
}

-- ---------------------------------------------------------------------------
-- container
-- ---------------------------------------------------------------------------

OB.container = CreateFrame("Frame", "EquadisClassicOverhaulAnchor", UIParent)
OB.container:SetWidth(1)
OB.container:SetHeight(1)
OB.container:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)

--[[ **Scale is the addon's, not the bar cluster's.**

     It used to set the container and stop, so the meters -- which own their own
     frames and hang off UIParent rather than off the container -- ignored it
     completely. Somebody scaling the addon down got smaller bars beside a
     full-size damage meter, which reads as the slider being broken rather than
     as it having a narrower reach than its name.

     A feature is asked rather than reached into, because a feature with four
     windows has to scale four frames and only it knows that. ]]--
function OB.ApplyScale()
    local scale = OB.profile.scale or 1

    OB.container:SetScale(scale)

    for id, m in pairs(OB.features) do
        if m.OnScale then m:OnScale(scale) end
    end
end

--[[ Write every slot's offset to its frame.

     The container's size is re-asserted on every call. It is a point, and any
     future code that grows it would silently reintroduce the drift bug above. ]]--
function OB.ApplyPositions()
    if not OB.profile then return end

    OB.container:SetWidth(1)
    OB.container:SetHeight(1)

    --[[ Rescued before drawing, not only when moved.

         A profile carries positions across resolution changes, monitors and
         scale settings, so a bar that was on screen when it was saved need not
         be now. Clamping only on the write paths leaves that bar invisible with
         no way back except a slider the user has to guess is the cause -- which
         is the report this answers. Doing it here catches every route in,
         including the one where nothing moved at all. ]]--
    for id, slot in pairs(OB.profile.slots) do
        slot.x = OB.ClampSlotCoord(id, "x", slot.x)
        slot.y = OB.ClampSlotCoord(id, "y", slot.y)
    end

    for i = 1, table.getn(OB.barOrder) do
        local slotId = OB.barOrder[i]
        local m = OB.bound[slotId]

        if m and m.frame then
            local slot = OB.profile.slots[slotId]
            --[[ Centre to centre. The container is 1x1, so its centre is the
                 anchor point, and a bar at x = 0 sits centred on it -- which is
                 the middle of the screen. ]]--
            m.frame:ClearAllPoints()
            m.frame:SetPoint("CENTER", OB.container, "CENTER", slot.x, slot.y)
        end
    end

    -- keep the overlay glued to its target while bars move under it
    if OB.moveTarget and OB.mover and OB.mover:IsVisible() then
        OB.PositionMover()
    end
end

-- ---------------------------------------------------------------------------
-- collision
-- ---------------------------------------------------------------------------

--[[ A bar's four edges, from its **centre**.

     `x` and `y` are the middle of the rectangle, not its top-left corner. That
     is the whole reason this helper exists: half a dozen places used to write
     `x .. x + w` and `y .. y - h` inline, which was only correct while the
     coordinate meant a corner, and changing it meant finding every one of them.
     There is one place now.

     Centre coordinates were worth the change because **x = 0 is the middle of
     the screen** with them, which is where anyone putting a HUD under their
     character wants to start. Corner coordinates put x = 0 half a bar's width to
     the right, so every layout began by typing a number nobody should have to
     work out.

     `pad` grows the rectangle by the border footprint, so border art
     participates in collision rather than overlapping unnoticed. ]]--
local function edgesOf(el, x, y, pad)
    if x == nil then x = el.x end
    if y == nil then y = el.y end
    pad = pad or 0

    local halfW, halfH = el.w / 2, el.h / 2
    -- left, right, top, bottom
    return x - halfW - pad, x + halfW + pad, y + halfH + pad, y - halfH - pad
end

OB.EdgesOf = edgesOf

-- a slot only participates in collision when something is actually drawn in it
local function slotActive(slotId)
    if not OB.bound[slotId] then return false end
    return OB.profile.slots[slotId].show and true or false
end

--[[ True when placing `slotId` at (x, y) would overlap another drawn slot.

     Rects are expanded by the border pad so border art participates: two bars
     may sit exactly edge to edge, they just cannot stack. The test is strict
     overlap for that reason.

     Hidden and unoccupied slots are skipped -- in RogueBars an invisible element
     still blocked a visible one, which looked like the bar had simply stopped
     moving for no reason. ]]--
function OB.SlotCollides(slotId, x, y)
    if not OB.profile or OB.profile.allowOverlap then return false end

    local slots = OB.profile.slots
    local pad = OB.BorderPad()
    local el = slots[slotId]

    local aL, aR, aT, aB = edgesOf(el, x, y, pad)

    for i = 1, table.getn(OB.barOrder) do
        local otherId = OB.barOrder[i]
        if otherId ~= slotId and slotActive(otherId) then
            local bL, bR, bT, bB = edgesOf(slots[otherId], nil, nil, pad)

            if (aL < bR) and (aR > bL) and (aB < bT) and (aT > bB) then
                return true
            end
        end
    end

    return false
end

--[[ Push bars apart when one of them grows into another.

     Drop each offending bar straight down until it just touches the one above --
     touching is allowed, stacking is not.

     Two things make a bar grow into its neighbour: a heavier border, and the
     width or height sliders. Only the border case used to be handled, because
     only x and y went through the collision path -- so growing a bar's height
     silently overlapped the bar below it while Allow Bar Overlap was off, which
     is the setting saying that should not happen. The size sliders now call
     this too.

     It runs at pad 0 as well. Without a border the bars simply end up touching
     rather than separated, which is the correct resolution for that case, and
     the old early return is exactly what made a plain resize overlap. ]]--
function OB.ResolveOverlap()
    if not OB.profile or OB.profile.allowOverlap then return end

    local pad = OB.BorderPad()
    local slots = OB.profile.slots

    local order = {}
    for i = 1, table.getn(OB.barOrder) do
        local id = OB.barOrder[i]
        if slotActive(id) then table.insert(order, id) end
    end
    table.sort(order, function(a, b) return slots[a].y > slots[b].y end)

    for i = 2, table.getn(order) do
        local el = slots[order[i]]
        for j = 1, i - 1 do
            local above = slots[order[j]]
            local aL, aR, aT, aB = edgesOf(el, nil, nil, pad)
            local bL, bR, bT, bB = edgesOf(above, nil, nil, pad)

            if (aL < bR) and (aR > bL) and (aT > bB) and (aB < bT) then
                --[[ Drop it until its top just meets the other's bottom. In
                     centre coordinates that is the other's bottom edge less half
                     of this bar's own height. ]]--
                local limit = (above.y - (above.h / 2)) - (el.h / 2) - (pad * 2)
                if el.y > limit then el.y = OB.ClampCoord(limit) end
            end
        end
    end
end

--[[ Re-stack every drawn slot from the topmost one downwards, at their current
     heights plus room for borders.

     Offered as a button rather than done automatically. Automatic reflow is the
     bug class the fixed anchor exists to prevent, and it would break the promise
     that two characters on one profile line up: the moment their occupancy
     differs, an automatic stack would put their bars in different places. ]]--
function OB.RestackBars()
    local slots = OB.profile.slots

    --[[ Border art plus whatever spacing was asked for. The pad is what a bar
         *must* have to avoid drawing over its neighbour; the gap is taste, and
         it was not a setting at all -- the stack was always edge to edge and
         there was no way to loosen it. Halved because the caller doubles it:
         one gap sits between two bars, not one on each. ]]--
    local pad = OB.BorderPad() + ((OB.profile.barGap or 0) / 2)

    local order = {}
    for i = 1, table.getn(OB.barOrder) do
        local id = OB.barOrder[i]
        if slotActive(id) then table.insert(order, id) end
    end
    table.sort(order, function(a, b) return slots[a].y > slots[b].y end)

    local count = table.getn(order)
    if count == 0 then return end

    --[[ Walk the *top edge* down, placing each centre half a height below it.
         The stack is an edge-to-edge thing; the coordinate is a centre. ]]--
    local first = slots[order[1]]
    local top = first.y + (first.h / 2)

    for i = 1, count do
        local el = slots[order[i]]
        el.y = OB.ClampCoord(top - (el.h / 2))
        top = top - el.h - (pad * 2)
    end

    OB.ApplyPositions()
end

-- ---------------------------------------------------------------------------
-- movement
-- ---------------------------------------------------------------------------

--[[ Shrink a joined step so no bar in the group leaves the screen.

     The step is shared, so the *first* bar to hit an edge stops all of them --
     which is what keeps the relative spacing intact. Bounding each bar
     separately would let the group deform, and a HUD whose bars slide relative
     to each other when you move it is not one arrangement any more.

     `sizes` is the live slot table (widths and heights); `from` is where each
     bar started, which is the live table for a nudge and the drag's snapshot for
     a drag -- a drag measures from the grab, not from the last frame, or the
     rounding accumulates. ]]--
function OB.ShrinkJoinedStep(sizes, from, dx, dy)
    for id, el in pairs(sizes) do
        local start = from[id]

        if start then
            local limitX = OB.ScreenLimit("x", el.w, OB.ContainerScale())
            local limitY = OB.ScreenLimit("y", el.h, OB.ContainerScale())

            if (start.x + dx) > limitX then dx = limitX - start.x end
            if (start.x + dx) < -limitX then dx = -limitX - start.x end
            if (start.y + dy) > limitY then dy = limitY - start.y end
            if (start.y + dy) < -limitY then dy = -limitY - start.y end
        end
    end

    return dx, dy
end

--[[ Move a slot by a whole-pixel offset, honouring Join.

     This is the single movement code path: the X/Y sliders, the arrow buttons
     and dragging all end up here. ]]--
function OB.NudgeSlot(slotId, dx, dy)
    if not OB.profile then return end
    local slots = OB.profile.slots
    if not slots[slotId] then return end

    if not OB.profile.join then
        local nx = OB.ClampSlotCoord(slotId, "x", slots[slotId].x + dx)
        local ny = OB.ClampSlotCoord(slotId, "y", slots[slotId].y + dy)

        --[[ Refuse a step that would create an overlap. A slot that already
             overlaps may always move, so it can escape. Joined moves keep
             relative positions and can never create one, hence only this
             branch checks. ]]--
        if OB.SlotCollides(slotId, nx, ny)
                and not OB.SlotCollides(slotId, slots[slotId].x, slots[slotId].y) then
            OB.RefreshPanel()
            return
        end

        slots[slotId].x = nx
        slots[slotId].y = ny
    else
        -- shrink the shared step so no slot leaves the allowed range, which
        -- keeps the relative spacing intact
        dx, dy = OB.ShrinkJoinedStep(slots, slots, dx, dy)

        for id, el in pairs(slots) do
            el.x = el.x + dx
            el.y = el.y + dy
        end
    end

    OB.ApplyPositions()
    OB.RefreshPanel()
end

-- set an absolute coordinate through the nudge path, so Join still applies
function OB.SetSlotCoord(slotId, axis, value)
    local slot = OB.profile.slots[slotId]
    if not slot then return end

    value = OB.ClampSlotCoord(slotId, axis, floor(value + 0.5))

    if axis == "x" then
        local delta = value - slot.x
        if delta ~= 0 then OB.NudgeSlot(slotId, delta, 0) end
    else
        local delta = value - slot.y
        if delta ~= 0 then OB.NudgeSlot(slotId, 0, delta) end
    end
end

--[[ The arrow overlay nudges whatever it targets. With Join on the target is the
     whole group, and NudgeSlot's joined branch moves every slot, so any slot id
     stands in for the group. ]]--
function OB.NudgeTarget(dx, dy)
    local target = OB.moveTarget
    if not target then return end
    if target == "ALL" then target = OB.barOrder[1] end
    OB.NudgeSlot(target, dx, dy)
end

-- ---------------------------------------------------------------------------
-- dragging
-- ---------------------------------------------------------------------------

function OB.StartDrag(frame)
    if not OB.profile or OB.profile.locked then return end

    local slotId = OB.dragMap[frame]
    if not slotId then return end

    drag.active = true
    drag.slot = slotId
    drag.cursorX, drag.cursorY = GetCursorPosition()
    drag.start = {}

    for id, el in pairs(OB.profile.slots) do
        drag.start[id] = { x = el.x, y = el.y }
    end
end

function OB.StopDrag()
    if not drag.active then return end
    drag.active = false
    OB.RefreshPanel()
end

-- ---------------------------------------------------------------------------
-- dragging the camera from on top of a frame
-- ---------------------------------------------------------------------------

--[==[ **A frame that takes the mouse takes the camera with it.**

     1.12 gives a mouse-enabled frame every button that happens over it, whether
     or not it has a handler for that button. So pressing the right button on a
     nameplate, a unit frame or a party frame and dragging turns nothing: the
     frame swallowed the press and the world never saw it. On a pull, plates
     cover most of the screen, and the camera stops working wherever you happen
     to point.

     The blunt answer already existed and is a poor one -- Click Through
     Nameplates switches their mouse off entirely, which buys the camera back by
     giving up clicking a plate at all.

     What this does instead is decide at the moment of release which of the two
     it was:

     **A press arms.** Nothing else happens; the cursor position is remembered.

     **Movement while armed starts mouselook**, which is the client's own camera
     turn and is what the world does with the same drag.

     **A release without movement is a click**, and the frame's own handler runs
     exactly as before -- so right-clicking a party member still opens the menu
     and left-clicking a plate still targets.

     Mouselook rather than `CameraOrSelectOrMoveStart`: the latter performs a
     *select* in the world when it stops, which with the cursor over a plate is
     a second targeting nobody asked for. Mouselook turns the view and does
     nothing else.

     Polled from the one OnUpdate rather than per frame. The mouse has one
     position, so at most one frame can be armed, and a per-frame handler would
     be a script on every plate on screen to watch a thing that is true of none
     of them. ]==]
local camera = { frame = nil, button = nil, x = 0, y = 0, turning = false }

--[[ How far the cursor has to travel before a click becomes a drag. Four
     pixels: a click delivered by a human hand moves one or two, and a drag that
     needed five would feel stuck. ]]--
local CAMERA_SLOP = 4

function OB.CameraDragEnabled()
    if not OB.profile or not OB.profile.cameraDrag then return false end
    return type(MouselookStart) == "function"
end

--[[ A press on a frame that would otherwise swallow it. Records where the
     cursor was; nothing turns until it moves. ]]--
function OB.ArmCameraDrag(frame, button)
    if not OB.CameraDragEnabled() then return false end

    --[[ The right button only. Left is the game's select, and taking it would
         make every click on a frame a potential camera turn -- which is the
         opposite complaint from the one this fixes. ]]--
    if button and button ~= "RightButton" then return false end

    camera.frame = frame
    camera.button = button
    camera.turning = false
    camera.swallow = false

    if type(GetCursorPosition) == "function" then
        camera.x, camera.y = GetCursorPosition()
    else
        camera.x, camera.y = 0, 0
    end

    return true
end

--[[ Called from the single OnUpdate. Starts the turn the moment the cursor has
     moved far enough to mean one. ]]--
function OB.StepCameraDrag()
    if not camera.frame or camera.turning then return false end
    if type(GetCursorPosition) ~= "function" then return false end

    local x, y = GetCursorPosition()
    local dx, dy = (x or 0) - camera.x, (y or 0) - camera.y

    if (dx * dx) + (dy * dy) < (CAMERA_SLOP * CAMERA_SLOP) then return false end

    camera.turning = true
    MouselookStart()

    return true
end

--[==[ **Release: was that a drag or a click?**

     Answers `true` when it was a drag, which is the caller's signal to do
     nothing else -- the menu it would otherwise open belongs to a click that
     did not happen.

     `IsMouselooking` is asked rather than trusted from the flag: something else
     may have ended the turn, and stopping a mouselook nobody is in leaves the
     cursor hidden. ]==]
function OB.ReleaseCameraDrag()
    local turned = camera.turning and true or false

    camera.frame, camera.button, camera.turning = nil, nil, false

    --[[ **Left standing for the click that is about to arrive.**

         1.12 delivers `OnClick` *after* `OnMouseUp`, so a handler asking "was
         that a drag" at click time is asking after this has already forgotten.
         The answer is kept until somebody takes it -- see
         `OB.ConsumeCameraDrag` -- and dropped by the next press either way, so
         a flag can never survive into a later click. ]]--
    camera.swallow = turned

    if turned then
        if type(IsMouselooking) ~= "function" or IsMouselooking() then
            if type(MouselookStop) == "function" then MouselookStop() end
        end
    end

    return turned
end

--[[ Was the click that is arriving the end of a camera turn? Answers once and
     forgets, so two handlers on one frame cannot both swallow it. ]]--
function OB.ConsumeCameraDrag()
    if not camera.swallow then return false end

    camera.swallow = false
    return true
end

--[==[ **Both halves put on a frame at once.**

     The existing handlers are kept and called: these are the client's own
     frames as often as they are this addon's, and replacing a script is how a
     nameplate stops being clickable at all. ]==]
--[==[ **What you can do to a unit, on any frame that shows one.**

     The party frames answer four gestures -- target, cast the queued spell,
     offer the item on the cursor, and a right-click menu -- and the raid frames
     answered one, which made them a readout rather than a raid frame. Asked for
     in exactly those terms.

     Lifted here rather than copied across, so the next fix lands once. It sits
     beside `OB.AttachCameraDrag` because it is the same kind of thing: a
     behaviour any frame showing a unit wants, owned by neither of the modules
     that want it.

     The unit is read off `frame.unit`, which both modules already set. ]==]
function OB.UnitMenuFor(frame, menuType)
    if not frame or not frame.GetName then return nil end
    if frame.eqMenu then return frame.eqMenu end

    if type(CreateFrame) ~= "function" then return nil end
    if type(UIDropDownMenu_Initialize) ~= "function" then return nil end

    local drop = CreateFrame("Frame", frame:GetName() .. "DropDown", frame,
            "UIDropDownMenuTemplate")

    --[==[ **The client's own menu for that kind of unit**, named rather than
         built: "PARTY" is whisper, invite, promote, pass the loot rules,
         uninvite, trade, follow and duel, and "RAID" is the raid's version of
         the same list. Naming the set means an entry the client adds arrives
         here without anybody noticing it was missing.

         The unit is closed over rather than read off `this`, which
         `ToggleDropDownMenu` leaves as whatever the caller had -- a detail that
         has moved between clients and is not worth depending on. ]==]
    UIDropDownMenu_Initialize(drop, function()
        if type(UnitPopup_ShowMenu) == "function" then
            UnitPopup_ShowMenu(drop, menuType or "PARTY", frame.unit)
        end
    end, "MENU")

    --[[ The first menu built is what installs the Inspect fix; see above. ]]--
    OB.InstallInspectTargeting()

    frame.eqMenu = drop
    return drop
end

--[==[ **Inspect targets first, because on this client it has to.**

     The menu's Inspect entry hands the client the unit off the menu -- `raid7`
     -- and the client will not open the inspect window for anything but your
     target. So Inspect from a raid frame did nothing unless you had already
     clicked the person, which is the report, and which makes the entry a
     button that only works when you did not need it.

     Targeting them first is what a person does by hand and the one path known
     to work here. `UnitPopup_OnClick` is the client's own handler for every
     entry on every unit menu, so it is wrapped once and the wrap steps in for
     Inspect alone: target the unit, then let the client do exactly what it was
     going to do -- with the menu's unit spelled as `target` for the length of
     the call, in case the check is on the spelling rather than the identity.
     Put back afterwards; the menu is closing anyway, but a field this addon
     changed is a field it restores.

     **Guarded on the saved original**, which is the durable artefact: the
     wrapper reaches the addon by global name and outlives any `OB`. Installed
     lazily, the first time a unit menu is built, so an install that never
     opens one never touches the client's handler. ]==]
function OB.InstallInspectTargeting()
    if EquadisOverhaulBlizzUnitPopupClick then return false end
    if type(UnitPopup_OnClick) ~= "function" then return false end

    EquadisOverhaulBlizzUnitPopupClick = UnitPopup_OnClick

    UnitPopup_OnClick = function()
        local menuName = UIDROPDOWNMENU_INIT_MENU
        local menu = menuName and getglobal(menuName)
        local unit = menu and menu.unit

        if this and this.value == "INSPECT" and unit
                and type(TargetUnit) == "function"
                and type(UnitExists) == "function" and UnitExists(unit)
                and not (type(UnitIsUnit) == "function"
                        and UnitIsUnit(unit, "target")) then
            TargetUnit(unit)

            menu.unit = "target"
            local ok, err = pcall(EquadisOverhaulBlizzUnitPopupClick)
            menu.unit = unit

            if not ok then error(err, 0) end
            return
        end

        return EquadisOverhaulBlizzUnitPopupClick()
    end

    return true
end

function OB.OpenUnitMenuFor(frame, menuType, x, y)
    local drop = OB.UnitMenuFor(frame, menuType)
    if not drop then return false end
    if type(ToggleDropDownMenu) ~= "function" then return false end

    ToggleDropDownMenu(1, nil, drop, frame:GetName(), x or 0, y or 0)
    return true
end

--[==[ **An item on the cursor, given to them.**

     `DropItemOnUnit` opens the trade window with the item already in it.
     Guarded on the cursor actually holding something, because the call with an
     empty cursor is not harmless: it opens an empty trade with whoever was
     clicked, which is a window somebody then has to cancel. ]==]
function OB.UnitDropOn(frame)
    if not frame or not frame.unit then return false end
    if type(CursorHasItem) ~= "function" or not CursorHasItem() then return false end
    if type(DropItemOnUnit) ~= "function" then return false end

    DropItemOnUnit(frame.unit)
    return true
end

--[==[ **`PartyMemberFrame_OnClick`, transcribed, and now shared.**

     Four outcomes and the order between them matters:

     A right click while a spell is queued **cancels the spell** rather than
     opening the menu. That is how every unit frame in the client behaves and it
     is the only way to put a spell down without casting it -- so it is answered
     before the menu, not after.

     A left click casts the queued spell at them if there is one, offers the item
     on the cursor if there is one, and otherwise targets. Targeting is last
     because it is what the other two would fall through to, and a heal that
     silently retargets instead of landing is the worst of the four. ]==]
function OB.UnitGestureClick(frame, button, menuType, x, y)
    if not frame or not frame.unit then return false end

    local targeting = type(SpellIsTargeting) == "function"
            and SpellIsTargeting() and true or false

    if targeting and button == "RightButton" then
        if type(SpellStopTargeting) == "function" then SpellStopTargeting() end
        return true
    end

    if button == "RightButton" then
        return OB.OpenUnitMenuFor(frame, menuType, x, y)
    end

    if targeting then
        if type(SpellTargetUnit) == "function" then SpellTargetUnit(frame.unit) end
        return true
    end

    if type(CursorHasItem) == "function" and CursorHasItem() then
        return OB.UnitDropOn(frame)
    end

    if type(TargetUnit) == "function" then TargetUnit(frame.unit) end
    return true
end

function OB.AttachCameraDrag(frame)
    if not frame or not frame.SetScript or frame.eqCameraDrag then return false end
    frame.eqCameraDrag = true

    local downWas = frame.GetScript and frame:GetScript("OnMouseDown")
    local upWas = frame.GetScript and frame:GetScript("OnMouseUp")

    frame:SetScript("OnMouseDown", function()
        EquadisClassicOverhaul.ArmCameraDrag(this, arg1)
        if downWas then downWas() end
    end)

    frame:SetScript("OnMouseUp", function()
        local turned = EquadisClassicOverhaul.ReleaseCameraDrag()

        --[[ A drag is not a click, so the handler underneath does not run. A
             plain press still reaches it untouched. ]]--
        if not turned and upWas then upWas() end
    end)

    --[==[ **And the click, which is a third script rather than a consequence of
         the second.**

         A `Button` fires `OnClick` after `OnMouseUp`, from the client, and that
         is where a unit frame opens its menu and a nameplate takes its target.
         Without this the drag turns the camera *and* opens the menu it was
         never meant to open.

         Only where there is one to chain: most frames this is put on have no
         `OnClick` at all, and giving one an empty handler would make it look
         clickable to everything that asks. ]==]
    local clickWas = frame.GetScript and frame:GetScript("OnClick")

    if clickWas then
        frame:SetScript("OnClick", function()
            if EquadisClassicOverhaul.ConsumeCameraDrag() then return end
            clickWas()
        end)
    end

    return true
end

function OB.UpdateDrag()
    if not drag.active then return end

    local cx, cy = GetCursorPosition()
    local scale = OB.container:GetEffectiveScale()
    local dx = floor((cx - drag.cursorX) / scale + 0.5)
    local dy = floor((cy - drag.cursorY) / scale + 0.5)

    local slots = OB.profile.slots

    if not OB.profile.join then
        local id = drag.slot
        local nx = OB.ClampSlotCoord(id, "x", drag.start[id].x + dx)
        local ny = OB.ClampSlotCoord(id, "y", drag.start[id].y + dy)

        -- slide along the free axis when the full move would collide; a slot
        -- that already collides drags freely so it can escape
        if OB.SlotCollides(id, nx, ny)
                and not OB.SlotCollides(id, slots[id].x, slots[id].y) then
            if not OB.SlotCollides(id, nx, slots[id].y) then
                ny = slots[id].y
            elseif not OB.SlotCollides(id, slots[id].x, ny) then
                nx = slots[id].x
            else
                nx, ny = slots[id].x, slots[id].y
            end
        end

        slots[id].x = nx
        slots[id].y = ny
    else
        dx, dy = OB.ShrinkJoinedStep(slots, drag.start, dx, dy)

        for id, el in pairs(slots) do
            el.x = drag.start[id].x + dx
            el.y = drag.start[id].y + dy
        end
    end

    OB.ApplyPositions()
end

--[[ Left-drag moves, right-click opens the arrow overlay. Attached by hud.lua
     when a frame is bound, and to every segment of a segmented slot so grabbing
     any pip drags the row. ]]--
function OB.AttachMouse(frame, slotId)
    OB.dragMap[frame] = slotId

    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then
            OB.StartDrag(this)
        elseif arg1 == "RightButton" then
            OB.ToggleMoveMode(this)
        end
    end)
    frame:SetScript("OnMouseUp", function() OB.StopDrag() end)
end

function OB.SetMouseEnabled(enabled)
    for frame in pairs(OB.dragMap) do
        frame:EnableMouse(enabled)
    end
end

-- ---------------------------------------------------------------------------
-- movement overlay
--
-- A single shared frame with the classic Blizzard scroll arrows around it,
-- shown on right-click and sized at runtime to wrap either one slot or the whole
-- joined layout. Each click moves exactly one pixel.
-- ---------------------------------------------------------------------------

local function arrowButton(parent, point, relativePoint, dx, dy, art, texCoord)
    local button = CreateFrame("Button", nil, parent)
    button:SetWidth(16)
    button:SetHeight(16)
    button:SetPoint(point, parent, relativePoint, 0, 0)

    button:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. art .. "Button-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. art .. "Button-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. art .. "Button-Highlight", "ADD")

    -- the left and right arrows reuse the up arrow art, rotated with the eight
    -- argument SetTexCoord
    if texCoord then
        button:GetNormalTexture():SetTexCoord(unpack(texCoord))
        button:GetPushedTexture():SetTexCoord(unpack(texCoord))
        button:GetHighlightTexture():SetTexCoord(unpack(texCoord))
    end

    button:SetScript("OnClick", function() OB.NudgeTarget(dx, dy) end)
    return button
end

function OB.CreateMover()
    if OB.mover then return OB.mover end

    local mover = CreateFrame("Frame", "EquadisClassicOverhaulMover", OB.container)
    mover:SetFrameStrata("HIGH")
    mover:SetWidth(200)
    mover:SetHeight(56)
    mover:Hide()

    arrowButton(mover, "BOTTOM", "TOP", 0, 1, "Up")
    arrowButton(mover, "TOP", "BOTTOM", 0, -1, "Down")
    arrowButton(mover, "RIGHT", "LEFT", -1, 0, "Up", { 1, 0, 0, 0, 1, 1, 0, 1 })
    arrowButton(mover, "LEFT", "RIGHT", 1, 0, "Up", { 0, 1, 1, 1, 0, 0, 1, 0 })

    OB.mover = mover
    return mover
end

-- wrap one slot when unjoined, or the bounding box of every drawn slot when not
function OB.PositionMover()
    if not OB.profile or not OB.mover then return end

    local slots = OB.profile.slots
    local target = OB.moveTarget
    local left, right, top, bottom

    if target and target ~= "ALL" and slots[target] then
        left, right, top, bottom = edgesOf(slots[target])
    else
        for i = 1, table.getn(OB.barOrder) do
            local id = OB.barOrder[i]
            if slotActive(id) then
                local l, r, t, b = edgesOf(slots[id])
                if not left or l < left then left = l end
                if not right or r > right then right = r end
                if not top or t > top then top = t end
                if not bottom or b < bottom then bottom = b end
            end
        end
    end

    if not left then return end
    if (right - left) < 1 then right = left + 1 end
    if (top - bottom) < 1 then bottom = top - 1 end

    --[[ Anchored from the container's CENTER, the same reference the bars use.
         The container is 1x1 so TOPLEFT and CENTER are half a pixel apart, but
         "the same reference" is the property worth keeping: two anchors that
         agree by rounding is how the original ghost-movement bug started. ]]--
    OB.mover:ClearAllPoints()
    OB.mover:SetPoint("TOPLEFT", OB.container, "CENTER", left, top)
    OB.mover:SetWidth(right - left)
    OB.mover:SetHeight(top - bottom)
end

--[[ Right-clicking a bar toggles the overlay. Joined: one overlay wraps the
     whole layout whichever bar was clicked. Unjoined: it wraps that bar, and
     right-clicking another retargets it. ]]--
function OB.ToggleMoveMode(frame)
    if not OB.profile or OB.profile.locked then return end

    local slotId = OB.dragMap[frame]
    if not slotId then return end

    local target = slotId
    if OB.profile.join then target = "ALL" end

    if OB.moveTarget == target then
        OB.moveTarget = nil
    else
        OB.moveTarget = target
    end

    OB.UpdateMoveControls()
end

function OB.ExitMoveMode()
    OB.moveTarget = nil
    OB.UpdateMoveControls()
end

-- the overlay is a temporary editing aid: visible only while a right-click
-- target is live, and never while the bars are locked
function OB.UpdateMoveControls()
    local mover = OB.CreateMover()

    if not OB.profile or OB.profile.locked then OB.moveTarget = nil end

    if OB.moveTarget then
        OB.PositionMover()
        mover:Show()
    else
        mover:Hide()
    end
end
