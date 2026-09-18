--[[ Equadis' Classic Overhaul :: edit mode

  **One switch that unlocks everything this addon can move.**

  Every subsystem that owns a draggable frame grew its own way of unlocking it:
  Move Party Frames, Move Buff / Debuff Frames, Move Bars, Place The Popup, and
  a Move button on each meter. Each is on a different page, and rearranging a
  screen meant finding all of them, turning them on one at a time, dragging, and
  then finding them all again to turn them off. Somebody usually missed one and
  left a frame draggable for the rest of the session.

  So: one toggle that asks every module to unlock, and asks them all to lock
  again afterwards. It owns nothing itself -- each module still decides what
  "draggable" means for its own frames, because only it knows -- and this walks
  the registry rather than keeping a list, so a subsystem added later is included
  by having the method rather than by being remembered here.

  The grid is part of the same job: something to line frames up *against* while
  they are being dragged.
]]--

local OB = EquadisClassicOverhaul

local function Say(msg) OB.Print(msg, "Edit Mode") end

--[[ The lines are one pixel wide whatever the spacing is -- a grid drawn in
     thick lines is a grid you align to the middle of rather than to. ]]--
local GRID_LINE = 1

--[[ How far apart the lines may be asked to sit. Below four they stop being
     readable as lines and become a wash; above two hundred there is nothing
     between them to align against. ]]--
OB.GRID_MIN, OB.GRID_MAX = 4, 200

-- ---------------------------------------------------------------------------
-- the grid
-- ---------------------------------------------------------------------------

function OB.GridFrame()
    if OB.gridFrame then return OB.gridFrame end

    local f = CreateFrame("Frame", "EquadisOverhaulGrid", UIParent)
    f:SetAllPoints(UIParent)

    --[[ Behind everything and deaf to the mouse. A grid that takes clicks is a
         grid you cannot drag anything through, which is the opposite of what it
         is for. ]]--
    f:SetFrameStrata("BACKGROUND")
    if f.EnableMouse then f:EnableMouse(false) end
    f:Hide()

    f.lines = {}
    OB.gridFrame = f
    return f
end

--[[ One line, reused. The grid is rebuilt whenever the spacing changes and a
     fine spacing needs a lot of them, so they are pooled rather than made and
     thrown away -- a texture per redraw at four pixel spacing is a few hundred
     objects the client never collects. ]]--
local function gridLine(f, index)
    f.lines[index] = f.lines[index] or f:CreateTexture(nil, "BACKGROUND")
    return f.lines[index]
end

--[[ **The middle lines are a different colour**, because the middle is the one
     position on the screen worth being sure about: it is where everything this
     addon places is measured from. Without them you are counting squares. ]]--
function OB.DrawGrid()
    local f = OB.GridFrame()
    if not OB.profile then return false end

    local size = tonumber(OB.profile.gridSize) or 32
    if size < OB.GRID_MIN then size = OB.GRID_MIN end
    if size > OB.GRID_MAX then size = OB.GRID_MAX end

    local width = GetScreenWidth() or 0
    local height = GetScreenHeight() or 0
    if width <= 0 or height <= 0 then return false end

    local used = 0

    --[[ Drawn outwards from the centre rather than from a corner, so the middle
         line lands exactly on the middle at every spacing. Starting at the left
         edge puts it wherever the arithmetic happens to leave it, which is the
         one place it must not be. ]]--
    local midX, midY = width / 2, height / 2

    local function place(x, y, w, h, centre)
        used = used + 1
        local line = gridLine(f, used)

        line:SetTexture(1, 1, 1)
        line:ClearAllPoints()
        line:SetWidth(w)
        line:SetHeight(h)
        line:SetPoint("CENTER", f, "BOTTOMLEFT", x, y)

        --[[ **Yellow down the middle, grey everywhere else.**

             The two centre lines are the only ones worth being certain about:
             every position this addon stores is an offset from the centre of
             the screen, so the middle is not one gridline among many, it is the
             origin. Yellow says that at a glance and is the one colour on
             screen nothing else here uses.

             The rest are grey and faint on purpose. They are there to be
             measured against, not looked at, and a grid that competes with the
             frames being aligned is a grid people switch off. ]]--
        if centre then
            line:SetVertexColor(1, 0.82, 0.1, 0.9)
        else
            line:SetVertexColor(0.6, 0.6, 0.6, 0.3)
        end

        line:Show()
    end

    place(midX, midY, GRID_LINE, height, true)
    place(midX, midY, width, GRID_LINE, true)

    local offset = size
    while offset < midX do
        place(midX - offset, midY, GRID_LINE, height, false)
        place(midX + offset, midY, GRID_LINE, height, false)
        offset = offset + size
    end

    offset = size
    while offset < midY do
        place(midX, midY - offset, width, GRID_LINE, false)
        place(midX, midY + offset, width, GRID_LINE, false)
        offset = offset + size
    end

    -- Anything the last, finer grid needed and this one does not.
    for i = used + 1, table.getn(f.lines) do f.lines[i]:Hide() end

    f.lineCount = used
    return true
end

--[[ Shown while edit mode is on and the reader has asked for it. Not on its own
     switch alone: a grid over the whole screen while you are playing is not an
     aid, and the only time it is one is while something is being moved. ]]--
function OB.UpdateGrid()
    local f = OB.GridFrame()

    if OB.editMode and OB.profile and OB.profile.grid then
        OB.DrawGrid()
        f:Show()
        return true
    end

    f:Hide()
    return false
end

-- ---------------------------------------------------------------------------
-- the switch
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- showing what can be moved
-- ---------------------------------------------------------------------------

--[[ **Unlocking a frame does not tell anybody it is unlocked.**

     That was the whole of what made this mode unpleasant to use. Edit mode
     switched every draggable frame on and then looked exactly like the game --
     so moving anything meant already knowing what was movable, guessing where
     its edges were, and finding the one part of it that takes a drag rather
     than a click. A bar you missed by four pixels is a spell you cast.

     Every other addon that does this draws the answer. DragonflightUI puts a
     lit rectangle round each movable piece the moment you enter its edit mode,
     and there is nothing to work out: what is outlined can be moved, and the
     outline is exactly where it is.

     So: one registry of movable frames, one outline apiece, drawn while the
     mode is on and gone when it is off. Modules keep deciding what draggable
     means for their own frames -- they still own `SetDragMode` -- and they say
     what is movable by registering it here rather than by drawing anything
     themselves, so every subsystem's edit mode looks the same. ]]--

--[[ Gold, which is the client's own highlight colour and reads as "this one" on
     top of every background in the game. Bright enough to find at a glance
     against a snowfield and against a Blackrock corridor. ]]--
local OUTLINE_COLOR = { 1, 0.82, 0, 1 }

--[[ How far outside the frame the outline sits. Far enough that it is not
     mistaken for part of the thing it is marking, close enough that it is
     obviously about that thing and not its neighbour. ]]--
local OUTLINE_PAD = 2

OB.movables = OB.movables or {}

--[[ **Registered by the module that owns the frame**, once, when it builds it.

     Keyed by frame rather than appended blindly, because `SetDragMode` runs
     every time the mode is toggled and a list that grew each time would draw
     the same outline forty deep by the end of an evening. ]]--
function OB.MarkMovable(frame, label)
    if not frame or not frame.CreateTexture then return false end

    for i = 1, table.getn(OB.movables) do
        if OB.movables[i].frame == frame then
            --[[ A better name later is still worth taking: the frame may have
                 been registered before the module knew what to call it. ]]--
            if label then OB.movables[i].label = label end
            return false
        end
    end

    table.insert(OB.movables, { frame = frame, label = label })
    return true
end

--[[ The outline for one frame, built once and kept on the frame itself.

     A frame rather than four textures on the frame being outlined: the thing
     being outlined may be a bar whose textures are swapped, a container whose
     children are re-parented, or Blizzard's own furniture, and none of those
     want extra regions appearing in their layers. A separate frame anchored to
     its corners follows the size, the scale and the position without touching
     it. ]]--
function OB.MovableOutline(entry)
    local frame = entry and entry.frame
    if not frame then return nil end
    if entry.outline then return entry.outline end

    local outline = CreateFrame("Frame", nil, frame)
    outline:SetPoint("TOPLEFT", frame, "TOPLEFT", -OUTLINE_PAD, OUTLINE_PAD)
    outline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", OUTLINE_PAD, -OUTLINE_PAD)

    --[[ Above whatever it is marking, or an outline round the action bars is
         drawn underneath the buttons and visible only at the corners. ]]--
    if outline.SetFrameLevel and frame.GetFrameLevel then
        outline:SetFrameLevel(frame:GetFrameLevel() + 5)
    end

    outline:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local c = OUTLINE_COLOR
    outline:SetBackdropBorderColor(c[1], c[2], c[3], c[4])

    --[[ A wash inside as well as an edge. An edge alone disappears against a
         busy background at the exact moment you need it -- over the action bar
         art, or against a wall -- and the wash is what makes the *area* read as
         one thing rather than four lines that happen to meet. ]]--
    local fill = outline:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(outline)
    fill:SetTexture(c[1], c[2], c[3], 0.12)
    outline.fill = fill

    --[[ **Named, because an unlabelled rectangle is a puzzle.** Half of these
         frames are empty containers -- the bar anchor with no buttons in it, the
         buff anchor before any buffs -- and an outline round nothing is worse
         than no outline at all. ]]--
    local text = outline:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", outline, "CENTER", 0, 0)
    text:SetText(entry.label or "")
    text:SetTextColor(c[1], c[2], c[3], 1)
    outline.text = text

    --[[ **The outline is the handle, and it covers everything.**

         Making the frame itself draggable means dragging whatever part of it
         is not already covered by something that eats the click -- so a unit
         frame moves by its portrait and not by its health bar, and an action
         bar moves only in the gaps between buttons. That is not a bug in any
         one frame; it is what "the frame is movable" means when the frame is
         full of children that take the mouse.

         So the thing you see is the thing you grab. The outline already covers
         the whole area and is already on top; it takes the mouse as well, and
         while edit mode is on it is in front of every child of the frame
         underneath, which is also what stops those children being clickable.

         **The frame's own drag handlers still do the recording.** Each module
         stores its position differently -- unit frames by centre, buff anchors
         by key, the meters per window -- and every one of them already has an
         `OnDragStop` that knows how. The outline moves the frame and then hands
         over to it, rather than teaching this file six ways to save. ]]--
    outline:EnableMouse(true)
    outline:RegisterForDrag("LeftButton")

    outline.eqEcoTarget = frame

    outline:SetScript("OnDragStart", function()
        local target = this.eqEcoTarget
        if not target or not target.StartMoving then return end

        if target.SetMovable then target:SetMovable(true) end
        target:StartMoving()
    end)

    outline:SetScript("OnDragStop", function()
        local target = this.eqEcoTarget
        if not target then return end

        if target.StopMovingOrSizing then target:StopMovingOrSizing() end

        --[[ `this` is how 1.12 hands a frame to its own script, so it is set to
             the frame being moved rather than to the outline that moved it --
             a handler that stored the outline's position would record the
             wrong rectangle every time. Put back afterwards. ]]--
        local stop = target.GetScript and target:GetScript("OnDragStop")

        if stop then
            local previous = this
            this = target
            pcall(stop)
            this = previous
        end
    end)

    outline:Hide()

    entry.outline = outline
    return outline
end

--[[ Show or hide every outline at once, which is what the toggle actually
     does. Frames that have gone away since they were registered are dropped as
     they are found rather than swept separately -- a module rebuilt is a frame
     nobody is going to move. ]]--
function OB.ShowOutlines(on)
    local kept = {}

    for i = 1, table.getn(OB.movables) do
        local entry = OB.movables[i]
        local frame = entry.frame

        if frame and frame.IsShown then
            table.insert(kept, entry)

            local outline = OB.MovableOutline(entry)

            if outline then
                --[[ Only over something that is on screen. An outline round a
                     hidden pet bar is a rectangle floating over the world with
                     nothing in it, and it is the first thing anybody would try
                     to drag. ]]--
                if on and frame:IsShown() then
                    if outline.text then outline.text:SetText(entry.label or "") end

                    --[[ **In front of everything, not merely in front of its
                         parent.**

                         Frame *level* only orders a frame against others in the
                         same strata, and the things that swallow the click are
                         separate frames -- action buttons, a health bar -- which
                         may sit in a strata of their own. Raised for as long as
                         edit mode is on, which is also what makes the children
                         underneath unclickable: the handle is over all of them.

                         The old strata is remembered rather than assumed. These
                         frames are not all ECO's, and putting one back into the
                         wrong layer is a mess that outlives edit mode. ]]--
                    if outline.GetFrameStrata and outline.SetFrameStrata then
                        if not outline.eqEcoStrata then
                            outline.eqEcoStrata = outline:GetFrameStrata()
                        end

                        outline:SetFrameStrata("FULLSCREEN_DIALOG")
                    end

                    outline:Show()
                else
                    --[[ Put back where it was, so an outline that is not in use
                         is not sitting in the top layer of the interface. ]]--
                    if outline.eqEcoStrata and outline.SetFrameStrata then
                        outline:SetFrameStrata(outline.eqEcoStrata)
                        outline.eqEcoStrata = nil
                    end

                    outline:Hide()
                end
            end
        end
    end

    OB.movables = kept
    return table.getn(kept)
end
function OB.EditMode()
    return OB.editMode and true or false
end

-- ---------------------------------------------------------------------------
-- the edit mode interface, which is also where notices go
-- ---------------------------------------------------------------------------

--[==[ **Edit mode had no interface at all.**

     It unlocks every frame in the addon, puts an outline round each of them and
     takes the mouse away from everything underneath -- and it said so in a chat
     line. Somebody who scrolled past that line is looking at an interface where
     nothing clicks, which is the same thing bind mode was reported as before it
     got a banner: a mode reads as a crash unless it is on screen.

     So it gets the banner bind mode has, and it gets one more job. Notices had a
     frame of their own -- a red strip at the top of the screen with its own
     backdrop and its own close button -- for the single case of "this needs a
     reload". Two frames saying "something you should know" in two visual
     languages is one more than the interface needs, and this one already has to
     exist. See `OB.RequireReload`.

     **The notice wins the panel when there is one**, because a reload notice is
     the answer to something you just did and edit mode is a state you are
     already in. Dismissing it hands the panel back to edit mode if edit mode is
     still on, and hides it otherwise. ]==]
local EDIT_HELP = "Drag anything outlined. "
        .. "Ctrl+Shift+Alt, or |cff69ccf0/eqedit|r, to finish."

function OB.EditPanel()
    if OB.editPanel then return OB.editPanel end
    if not CreateFrame then return nil end

    local f = CreateFrame("Frame", "EquadisClassicOverhaulEditPanel", UIParent)
    f:SetWidth(420)
    f:SetHeight(64)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)

    --[[ The same strata bind mode uses. A notice that a dialog can cover is a
         notice somebody misses at exactly the moment a dialog is up. ]]--
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:Hide()

    if OB.SkinWindow then OB.SkinWindow(f, 0.95) end

    f.title = OB.NewText(f, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", f, "TOP", 0, -10)

    f.help = OB.NewText(f, "OVERLAY", "GameFontHighlight")
    f.help:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
    f.help:SetWidth(396)
    f.help:SetJustifyH("CENTER")

    --[[ Only ever shown beside a notice that needs it. A Reload UI button
         sitting under the edit mode instructions is an invitation to throw away
         the arrangement you are in the middle of making. ]]--
    f.reload = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reload:SetWidth(92)
    f.reload:SetHeight(22)
    f.reload:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    f.reload:SetText("Reload UI")
    f.reload:SetScript("OnClick", function()
        if ReloadUI then ReloadUI() end
    end)
    f.reload:Hide()

    --[[ Dismisses the notice, and leaves edit mode when there is no notice --
         which is what a close button on a mode's own banner means. ]]--
    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 2)
    f.close:SetScript("OnClick", function()
        if OB.pendingNotice then
            OB.DismissNotice()
        elseif OB.editMode then
            OB.SetEditMode(false)
        else
            OB.EditPanel():Hide()
        end
    end)

    OB.editPanel = f
    return f
end

--[[ Put the panel back to whatever is true now. One place decides, so the
     notice arriving, the notice going and edit mode toggling cannot disagree
     about what is on screen. ]]--
function OB.RefreshEditPanel()
    local f = OB.EditPanel()
    if not f then return false end

    if OB.pendingNotice then
        local reason = type(OB.pendingNotice) == "string"
                and OB.pendingNotice or nil

        f.title:SetText("Reload Required")
        f.help:SetText(reason or "A setting you changed needs a reload.")

        --[[ Taller, because the button needs a row of its own under the text
             rather than beside it: the reason can be a sentence. ]]--
        f:SetHeight(92)
        f.reload:Show()
        f:Show()

        return true
    end

    f.reload:Hide()
    f:SetHeight(64)

    if OB.editMode then
        f.title:SetText("Edit Mode")
        f.help:SetText(EDIT_HELP)
        f:Show()
        return true
    end

    f:Hide()
    return true
end

function OB.DismissNotice()
    OB.pendingNotice = nil
    return OB.RefreshEditPanel()
end

--[[ Every module that can unlock something, asked to. Walked from the registry
     rather than listed, so a subsystem added later joins by having the method --
     which is also why this cannot simply be a loop over four names. ]]--
function OB.SetEditMode(on)
    on = on and true or false
    OB.editMode = on

    --[[ Everything the modules say from here down is held until the one line at
         the bottom of this function. See `OB.HoldPrint`. ]]--
    OB.HoldPrint(true)

    local moved = 0

    for i = 1, table.getn(OB.moduleOrder) do
        local m = OB.modules[OB.moduleOrder[i]]

        --[[ Only a module that is actually running. Unlocking a subsystem that
             is switched off builds its frames to drag them, which is a window
             appearing for a feature the reader turned off. ]]--
        if m and m.SetDragMode and OB.ModuleEnabled(m.id) then
            --[[ Guarded, because a module may refuse -- the party frames decline
                 to unlock while the feature is off, and say so. One refusing
                 must not stop the rest unlocking. ]]--
            --[==[ **Everything they say here is dropped, and that is the whole
                 change.**

                 Two other signals were tried and both are wrong. The **return
                 value** is not something these eight agree on -- some answer
                 `true`, some answer nothing at all -- so reading a missing
                 return as a refusal named two modules that had just unlocked
                 perfectly well. And **whether the module spoke** does not
                 separate them either, because they announce success as loudly as
                 they decline.

                 There is no signal to read, and there does not need to be: a
                 module that declines does so because its feature is switched
                 off, and the line above has *already* skipped every module whose
                 feature is switched off. The refusal is guarded twice and
                 reachable through neither.

                 The messages still exist and still reach chat when somebody
                 drives one module directly -- `/eq bars move` -- which is the
                 case they were written for. ]==]
            pcall(m.SetDragMode, m, on)
            moved = moved + 1
        end
    end

    --[[ The HUD bars are not a module and lock through the profile, so they are
         handled here rather than by having a `SetDragMode` of their own that
         would be the only one not owned by a subsystem. ]]--
    if OB.profile then
        OB.profile.locked = not on
        if not on then OB.ExitMoveMode() end
    end

    --[[ After the modules have unlocked, because unlocking is what registers
         their frames -- a module asked to show outlines first would have
         nothing to show on the very first toggle of a session. ]]--
    OB.ShowOutlines(on)

    OB.UpdateGrid()
    if type(OB.UpdateMoveControls) == "function" then OB.UpdateMoveControls() end
    if type(OB.RefreshPanel) == "function" then OB.RefreshPanel() end

    --[[ The mode's own banner, which is what says the mode is on to somebody
         who was not reading chat when it started. ]]--
    OB.RefreshEditPanel()

    --[==[ **One line, and it is this one.**

         Everything the modules said while they were being unlocked was held --
         see `OB.HoldPrint` -- so what reaches chat is a count rather than a roll
         call. A module that refused is still named, because a subsystem quietly
         not unlocking is the one thing here worth interrupting somebody for. ]==]
    OB.HoldPrint(false)

    if on then
        local line = "everything is unlocked (" .. moved
                .. ") -- drag what you like, then switch it off."

        Say(line)
    else
        Say("locked.")
    end

    return on
end

--[[ **Hold Control, Shift and Alt together to unlock everything.**

     There is a slash command and a panel button already, and both mean stopping
     what you are doing to go and find them. Moving something is a thing you
     want to do *while looking at it*, so the gesture is available where your
     hands already are.

     **All three, because no two of them are safe.** Control-Shift and
     Shift-Alt are both live modifiers in this client -- on a click, on a drag,
     on a keybind -- and a gesture that fires during ordinary play is worse than
     no gesture. Three at once is not something a hand does by accident.

     **On the press, not while held.** The state is remembered so the toggle
     fires once as the third key goes down, rather than flipping on every frame
     for as long as they are all held -- which at a hundred and fifty frames a
     second would be a strobe rather than a toggle. ]]--
function OB.EditModifiersDown()
    if type(IsControlKeyDown) ~= "function" then return false end
    if type(IsShiftKeyDown) ~= "function" then return false end
    if type(IsAltKeyDown) ~= "function" then return false end

    return IsControlKeyDown() and IsShiftKeyDown() and IsAltKeyDown()
            and true or false
end

function OB.CheckEditHotkey()
    if not OB.profile then return false end

    --[==[ **Always on, and no longer a setting.**

         This was switchable, on the reasoning that somebody may have bound
         something else to the same three keys and would want the gesture out
         of the way. That case is thinner than it looks: the gesture reads the
         modifiers rather than claiming a binding, so it takes nothing from
         anybody -- and all three at once is not a chord a hand arrives at by
         accident, which is why three were required in the first place.

         What the switch actually did was let somebody turn off the only way to
         move things that does not involve stopping to find a menu, and then
         wonder why dragging had stopped working. ]==]
    local held = OB.EditModifiersDown()

    if held == OB.editKeysHeld then return false end
    OB.editKeysHeld = held

    --[[ Only the press. Releasing is what ends the gesture, not a second
         toggle -- otherwise letting go would put back what pressing undid. ]]--
    if not held then return false end

    OB.ToggleEditMode()

    return true
end

function OB.ToggleEditMode()
    return OB.SetEditMode(not OB.EditMode())
end
