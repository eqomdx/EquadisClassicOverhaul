--[[ A fake Vanilla 1.12 client, enough of one to load and drive the addon.

  Run under LuaJIT (5.1 semantics -- the closest widely available match to the
  1.12 client's Lua 5.0). Nothing here is shipped: the TOC does not list this
  directory, and WoW only loads files a TOC names.

  Two deliberate choices:

  Widgets return real values, not nil. GetWidth after SetWidth gives the width
  back, GetChecked reflects SetChecked, and so on -- otherwise every arithmetic
  path in the addon (SetBarFill in particular, which multiplies by GetWidth)
  would silently short-circuit and the tests would pass by not executing.

  Unknown methods are answered by a recorded fallback rather than an error. A
  hard error would mean chasing every cosmetic call the addon makes; instead
  Stub.UnknownMethods() lists what got faked, so a typo'd API name shows up as
  an unexpected entry rather than hiding.
]]--

Stub = {}

--[[ **The client is Lua 5.0, so the string iterator is `gfind` and `gmatch` does
     not exist.** LuaJIT has it exactly the other way round.

     Both halves matter. Adding `gfind` lets the addon use the name the client
     actually has; removing `gmatch` is what stops a 5.1-ism compiling here and
     then erroring in the game, which is the whole reason the harness runs at
     all. The same applies to `table.getn` over `#`, which is why nothing in the
     addon uses the length operator either. ]]--
if not string.gfind then string.gfind = string.gmatch end
string.gmatch = nil

--[==[ **And 5.0 calls the remainder `mod`, where 5.1 renamed it `fmod`.**

     The same shape of trap as `gmatch`, and one that had already been walked
     into: the waypoint arrow and the profile share codes both called
     `math.fmod`, which LuaJIT has and a 1.12 client does not, so both compiled
     here and would have thrown on the first frame in the game.

     So the name the client has is added and the name it does not have is taken
     away, which is what lets the suite say so. ]==]
if not math.mod then math.mod = math.fmod end
math.fmod = nil

--[==[ **And `string.match`, for the same reason and by the same rule.**

     It went unmodelled, so the one call to it in the addon compiled here and
     ran here and was never questioned -- while three separate comments in the
     source state that 1.12 does not have it. A rule the harness does not
     enforce is a rule that holds until somebody is in a hurry.

     What made it survive in the game is worse than a plain crash would have
     been: AI_VoiceOver ships a `string.match` shim, installs it into the shared
     global `string` table, and sorts before this addon in load order. So the
     call worked -- on an install that happens to have that addon, loading in
     that order. Remove it and every tooltip carrying a quest id throws. ]==]
string.match = nil

local unknown = {}
local frames = {}

--[==[ **Exposed, because a sweep over every frame is a real question.**

     `/eq bars` was unreachable and `MapClick` divided by a hundred twice, and
     both survived for the same reason: they are reachable only by a gesture, and
     nothing in the suite ever made the gesture. Typing every command found the
     first. Pressing every button is how the second kind gets found, and that
     needs the list. ]==]
Stub.frames = frames

--[[ **Which frames belong to the addon this boot is running**, set while its
     files are loading and its login events are firing. See
     `Stub.RetireLoadedFrames`: the next login has to be able to tell them from
     the client's own furniture, and the only reliable difference is who built
     them and when. ]]--
local addonLoading = false

--[[ Textures and font strings, which are not frames and are moved and repainted
     exactly as much. They take no events and no ticks, so they are kept only to
     be put back at the next login -- see `Stub.ResetSession`. ]]--
local regions = {}
local clock = 10000

-- ---------------------------------------------------------------------------
-- widget objects
-- ---------------------------------------------------------------------------

local function noop() end

--[[ Fabricate a no-op for any method the stub does not implement, and record it.

     Only PascalCase keys are treated as methods. Every WoW widget method starts
     with a capital; every field the stub keeps state in is lowercase. Without
     that discriminator, reading an unset state field (self.checked, self.value)
     would hand back a function, which is truthy -- so `self.tex or create()`
     would never create, and GetChecked() would return a function. ]]--
local widgetMT = {}
widgetMT.__index = function(t, key)
    if type(key) ~= "string" then return nil end
    if not string.find(key, "^%u") then return nil end

    unknown[(rawget(t, "__objtype") or "?") .. ":" .. key] = true
    local fn = function() end
    rawset(t, key, fn)
    return fn
end

local function newObject(objtype)
    local o = setmetatable({}, widgetMT)
    o.__objtype = objtype

    --[[ **Regions answer what they are, the same way frames do.**

         Left to the auto-faking metatable this returned nil, which is not an
         error and is worse than one: a nameplate is identified by its first
         region being a `Texture`, so a stub that would not say what a region
         *was* silently answered "not a nameplate" to every plate in the world
         and the module found nothing at all. Nothing errored. ]]--
    o.GetObjectType = function(self) return self.__objtype end

    return o
end

-- ---------------------------------------------------------------------------
-- regions: Texture and FontString
-- ---------------------------------------------------------------------------

local function definePoints(o)
    o.points = {}
    o.ClearAllPoints = function(self) self.points = {} end
    o.SetPoint = function(self, point, rel, relPoint, x, y)
        table.insert(self.points, { point, rel, relPoint, x, y })
    end
    o.GetNumPoints = function(self) return table.getn(self.points) end

    --[[ One anchor, read back. `GetPoint` is the only way to ask a frame what it
         is attached to, and the Escape menu button has to ask -- which button
         sits under Options differs between clients, so it is found rather than
         named. Answered in the client's order: point, relativeTo, relativePoint,
         x, y. ]]--
    o.GetPoint = function(self, index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    o.SetAllPoints = function(self) end

    --[[ **Screen edges, modelled rather than left to the auto-faking
         metatable.**

         Absent, these answered nil, and nil is the one value that makes the
         centre-from-edges arithmetic every draggable window does throw rather
         than misbehave. Both meters compute their dropped position from
         GetLeft/GetBottom, so *neither drop path had ever been executed* by the
         suite -- it could only ever check that a drag handler existed.

         Only CENTER-on-CENTER is modelled, because that is the anchor every
         window this addon owns actually uses. Anything else answers nil, which
         is honest: the stub does not know, and pretending would hide the next
         bug rather than the last one. ]]--
    --[==[ **Two anchors modelled, and everything else still nil.**

         `CENTER` on `CENTER` is what a dropped window stores. `TOPLEFT` on
         `UIParent`'s `TOPLEFT` is what the world map is placed with -- it is
         anchored by its visual top-left corner in physical pixels, which is the
         whole mechanism that lets a scale change grow it in a chosen direction.
         Modelling only the first meant every world-map geometry call answered
         nil, so none of that arithmetic could be asserted at all and the module
         grew a resize, a drag and a wheel zoom with no coverage between them.

         Still nil for anything else, for the reason the note below gives: a
         made-up number here hides the next bug rather than the last one. ]==]
    local function frameEdges(self)
        local p = self.points[1]
        if not p then return nil end

        if p[1] == "CENTER" and p[3] == "CENTER" then
            local left = (GetScreenWidth() / 2) + (p[4] or 0) - ((self.width or 0) / 2)
            local bottom = (GetScreenHeight() / 2) + (p[5] or 0) - ((self.height or 0) / 2)
            return left, bottom
        end

        --[==[ **Resolved across the scale boundary, which is the whole point
             of the call being modelled at all.**

             An offset is measured in the *anchored* frame's units, and the
             frame it is anchored to has a scale of its own. The map is placed by
             converting a physical pixel position into its own units and setting
             a `TOPLEFT` offset; reading it back has to undo exactly that, or the
             round trip is out by the ratio of the two scales and the arithmetic
             this exists to check passes while being wrong. ]==]
        if p[1] == "TOPLEFT" and p[3] == "TOPLEFT" then
            local rel = p[2] or UIParent
            if not rel or not rel.GetLeft then return nil end

            local relLeft, relTop = rel:GetLeft(), rel:GetTop()
            if not relLeft or not relTop then return nil end

            local relScale = rel.GetEffectiveScale and rel:GetEffectiveScale() or 1
            local scale = self.GetEffectiveScale and self:GetEffectiveScale() or 1
            if not scale or scale <= 0 then scale = 1 end
            if not relScale or relScale <= 0 then relScale = 1 end

            local left = ((relLeft * relScale) / scale) + (p[4] or 0)
            local top = ((relTop * relScale) / scale) + (p[5] or 0)
            return left, top - (self.height or 0)
        end

        return nil
    end

    o.GetLeft = function(self)
        local left = frameEdges(self)
        return left
    end

    o.GetBottom = function(self)
        local _, bottom = frameEdges(self)
        return bottom
    end

    o.GetRight = function(self)
        local left = self:GetLeft()
        if not left then return nil end
        return left + (self.width or 0)
    end

    o.GetTop = function(self)
        local bottom = self:GetBottom()
        if not bottom then return nil end
        return bottom + (self.height or 0)
    end

    --[[ **The middle, which is what a window stores when it is dropped.**

         The chat edit box's holder reads `GetCenter` rather than the two edges,
         and without it `StoreEditBox` returned early on its first line -- so
         every drag the suite performed was recorded as no drag at all, and four
         checks compared a position against the one that was already there.

         Answers nil wherever the edges do, for the same reason: the stub models
         CENTER-on-CENTER and nothing else, and a made-up number here would hide
         the next bug rather than the last one. ]]--
    o.GetCenter = function(self)
        local left, bottom = self:GetLeft(), self:GetBottom()
        if not left or not bottom then return nil end
        return left + ((self.width or 0) / 2), bottom + ((self.height or 0) / 2)
    end
end

--[[ **Showing a frame runs its OnShow, and hiding it runs its OnHide.**

     These were plain flag setters, so a window that fills itself in when it
     opens -- which is how every window in this addon works, because building the
     contents up front is building them for a window nobody may open -- came up
     empty in a test and full in the game. The bag grid was drawn by its OnShow
     and had no squares in it here at all.

     Only frames get the scripts; a texture or font string has visibility and no
     handlers, and `scripts` is nil on those. Guarded on the table rather than on
     the object's type, which is the same question asked more cheaply.

     `this` is set the way the client sets it, because a handler written for the
     game reads it and a stub that left it alone would quietly pass a handler
     that could never work. ]]--
local function fireVisibility(o, name)
    local handler = o.scripts and o.scripts[name]
    if not handler then return end

    local saved = this
    this = o
    handler()
    this = saved
end

local function defineShow(o)
    o.shown = true

    o.Show = function(self)
        --[[ Only on a change. The client does not re-run OnShow for a frame
             that was already up, and a handler that redraws would otherwise run
             on every call from anything that shows defensively. ]]--
        if self.shown then return end
        self.shown = true
        fireVisibility(self, "OnShow")
    end

    o.Hide = function(self)
        if not self.shown then return end
        self.shown = false
        fireVisibility(self, "OnHide")
    end
    --[[ **A frame's own number, which several parts of the client key on.**

         A bag's buttons are numbered by the slot they hold rather than by the
         order they were built, and an action button by the action it fires.
         `SetID` was accepted by the fallback stub and dropped, so `GetID` came
         back nil and any code reading it silently fell through to whatever it
         used as a default -- which is a border on the wrong bag slot, and looks
         like the colours being random rather than like a missing method. ]]--
    o.SetID = function(self, id) self.id = id end
    o.GetID = function(self) return self.id end

    o.IsShown = function(self) return self.shown end
    o.IsVisible = function(self)
        if not self.shown then return false end
        local p = self.parent
        while p do
            if not p.shown then return false end
            p = p.parent
        end
        return true
    end
end

local function defineSize(o)
    o.width, o.height = 0, 0
    o.SetWidth = function(self, v) self.width = v end
    o.SetHeight = function(self, v) self.height = v end
    o.GetWidth = function(self) return self.width end
    o.GetHeight = function(self) return self.height end
end

local function newTexture(parent, layer)
    local t = newObject("Texture")
    table.insert(regions, t)
    t.parent = parent
    t.layer = layer
    t.GetParent = function(self) return self.parent end
    definePoints(t)
    defineShow(t)
    defineSize(t)

    t.SetTexture = function(self, a, b, c, d)
        if type(a) == "string" then
            self.texture, self.rgba = a, nil
        else
            self.texture, self.rgba = nil, { a, b, c, d }
        end
    end
    t.GetTexture = function(self) return self.texture end
    t.SetVertexColor = function(self, r, g, b, a)
        self.vertex = { r, g, b, a }
    end

    --[[ Readable, because the tint is a thing that gets *restored*: dark mode
         sets it, drag mode overrides it green, and switching drag mode off has
         to put dark mode's back rather than white. Only the read side can tell
         those two apart. ]]--
    t.GetVertexColor = function(self)
        if not self.vertex then return 1, 1, 1, 1 end
        return self.vertex[1], self.vertex[2], self.vertex[3], self.vertex[4]
    end
    t.SetTexCoord = function(self, ...)
        self.texcoord = { ... }
    end

    --[==[ **And it answers what it was given.**

         Every sheet-cut picture in this addon is a `SetTexCoord` -- the waypoint
         arrow's heading, its arrival animation, the minimap blips -- and the
         only way to ask which cell is showing is to read the coordinates back.
         Unmodelled, the arrow's cell arithmetic could not be tested at all,
         which is how it shipped dividing a 512 sheet into ninths when its cells
         are 56 wide. ]==]
    t.GetTexCoord = function(self)
        local c = self.texcoord
        if not c then return nil end

        return c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8]
    end
    t.SetAlpha = function(self, v) self.alpha = v end
    t.GetAlpha = function(self) return self.alpha or 1 end

    --[==[ **A blend mode**, which is the difference between a glow and a
         sticker.

         `ADD` is what makes a quality glow read as light coming off the icon
         rather than a coloured rectangle sitting on top of it, and it is the
         mode every glow in this interface asks for. Unmodelled it was a nil
         call -- so any code that reached for one took the suite down rather
         than being tested. ]==]
    --[==[ **Desaturation, and it answers whether it worked.**

         The client's `SetDesaturated` returns false on hardware that cannot do
         it, which is why `SetItemButtonDesaturated` has a vertex-colour
         fallback. Answering true here exercises the ordinary path; a test that
         wants the fallback can override the method on the texture it cares
         about. ]==]
    t.SetDesaturated = function(self, on)
        self.desaturated = on and true or false
        return true
    end

    t.IsDesaturated = function(self) return self.desaturated and true or false end

    t.SetBlendMode = function(self, mode) self.blend = mode end
    t.GetBlendMode = function(self) return self.blend or "BLEND" end
    return t
end

--[[ A FontString has no font object unless it inherited one from a template or
     was given one with SetFont, and in 1.12 touching the text or its colour
     before then is an error rather than a no-op.

     This is modelled rather than ignored because ignoring it shipped a dead
     settings panel with a green test suite: one `CreateFontString(nil, "OVERLAY")`
     followed by SetTextColor threw in the real client, aborted the panel build
     midway through a page, and the stub recorded the colour and said nothing.
     A stub that agrees with a wrong assumption still passes -- so where the rule
     is known, it belongs here. ]]--
local function newFontString(parent, layer, inherits)
    local f = newObject("FontString")
    table.insert(regions, f)
    f.parent = parent
    definePoints(f)
    defineShow(f)
    defineSize(f)

    --[[ **Which frame owns it**, which is not decoration: a region's draw order
         is decided by its parent's frame level before its own layer is even
         considered. The tooltip's health number has to sit on a frame above the
         one carrying the bar's border, and `parent` was recorded here and never
         readable -- so nothing could assert the thing that actually fixes it. ]]--
    f.GetParent = function(self) return self.parent end

    if inherits then f.font = "inherited:" .. inherits end

    local function requireFont(self, what)
        if not self.font then
            error("FontString:" .. what .. " on a font string with no font: "
                    .. "create it with an inherited template, or call SetFont first", 3)
        end
    end

    f.text = ""
    --[==[ **A font string holds a string**, whatever it was handed.

         This kept the value as it came, so `SetText(538)` read back as the
         number 538 and never equalled the "538" the client would really have
         stored. Code that formatted its numbers and code that did not were
         indistinguishable here, and only one of them is right. ]==]
    f.SetText = function(self, v)
        requireFont(self, "SetText")
        if v == nil then v = "" end
        self.text = tostring(v)
    end
    f.GetText = function(self) return self.text end
    f.SetFont = function(self, path, size, flags)
        self.font, self.fontSize, self.fontFlags = path, size, flags
    end
    f.GetFont = function(self) return self.font, self.fontSize, self.fontFlags end
    f.SetTextColor = function(self, r, g, b)
        requireFont(self, "SetTextColor")
        self.color = { r, g, b }
    end

    --[[ **Reading the colour back, which the nameplate module does to decide
         whether the client has already coloured a name red for combat.**

         Answers white when nothing has set one, because that is what the client
         answers for an untouched font string -- and because the auto-faking
         metatable's alternative is nil, which turns `r > 0.9` into a comparison
         against nothing and takes the whole pass down. ]]--
    f.GetTextColor = function(self)
        local c = self.color
        if not c then return 1, 1, 1, 1 end
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end

    --[==[ **On a font string, the vertex colour *is* the text colour.**

         Two names for one channel: whichever ran last is the colour on screen,
         and neither shades the other. This stub had `SetVertexColor` going to
         the auto-faking metatable, which swallowed it -- so a client pass that
         repaints text through the vertex channel did nothing here and everything
         in the game.

         That is not hypothetical. `ActionButton_UpdateUsable` colours a keybind
         that way and only on buttons holding a spell, so a bar came out in two
         colours at once while every test agreed the colour was applied. ]==]
    f.SetVertexColor = function(self, r, g, b, a)
        self.color = { r, g, b, a }
    end

    f.GetVertexColor = function(self) return self:GetTextColor() end
    f.SetJustifyH = function(self, v) self.justify = v end
    f.SetAlpha = function(self, v) self.alpha = v end

    --[==[ **And readable, which it was not.**

         A font string could be faded and nothing could ask whether it had been.
         That is the write-only shape this harness keeps being caught by: an
         addon sets a thing, the stub swallows it, and a test asserting the
         effect has nothing to read. The buff timers turn the client's own
         duration string invisible rather than fighting it every frame, and that
         is only an assertion if the alpha can be read back. ]==]
    f.GetAlpha = function(self) return self.alpha or 1 end

    --[[ A rendered width, modelled rather than left to the auto-faking
         metatable -- which would answer nil, and nil is the one value that makes
         a clamp against the bar's edges silently do nothing.

         Half the point size per character is a rough average for a proportional
         face and wrong for any particular string. It does not need to be right:
         what depends on it is "does this label still fit", and the shape of that
         answer -- grows with the text, grows with the font size -- is what the
         stub has to get right. ]]--
    f.GetStringWidth = function(self)
        return string.len(self.text or "") * ((self.fontSize or 12) * 0.5)
    end

    --[[ Wrapped height, which is what the options layout has to know before it
         can place the row underneath.

         Modelled rather than left to the metatable for the same reason as the
         width: nil is the one answer that makes a layout silently do nothing,
         and "everything below the paragraph is drawn on top of it" was exactly
         the bug that reached the game. Lines are derived from the width the
         caller set, so a paragraph that wraps here wraps there. ]]--
    f.GetStringHeight = function(self)
        --[[ A font string with no font cannot be measured, exactly as it cannot
             be given text or a colour. This one threw inside the options page
             builder, which abandoned the rest of the page -- and since the
             description is built first, the whole tab came up empty. ]]--
        requireFont(self, "GetStringHeight")

        local size = self.fontSize or 12
        local width = self.width or 0
        local text = self.text or ""

        if width <= 0 then return size end

        local lines = math.ceil(self:GetStringWidth() / width)

        -- explicit breaks add lines the wrap calculation cannot see
        local _, breaks = string.gsub(text, "\n", "")
        lines = lines + breaks

        if lines < 1 then lines = 1 end
        return lines * size * 1.2
    end

    return f
end

-- ---------------------------------------------------------------------------
-- frames
-- ---------------------------------------------------------------------------

local templates = {}

templates.UICheckButtonTemplate = function(frame)
    if frame.name then
        _G[frame.name .. "Text"] = newFontString(frame, "OVERLAY", "GameFontNormal")
    end
end

templates.OptionsSliderTemplate = function(frame)
    if frame.name then
        _G[frame.name .. "Low"] = newFontString(frame, "OVERLAY", "GameFontNormal")
        _G[frame.name .. "High"] = newFontString(frame, "OVERLAY", "GameFontNormal")
        _G[frame.name .. "Text"] = newFontString(frame, "OVERLAY", "GameFontNormal")
    end
end

--[[ **`$parentScrollBar`, which the real template creates and this file did
     not.**

     Every faux scroll list reaches for it by name -- `FauxScrollFrame_Update`
     writes its range, and anything scrolling by code sets its value. Without it
     here, that whole path was unreachable under test: code could set the bar,
     miss, silently fall back to writing `offset` directly, and pass.

     `SetValue` drives the scroll frame the way the client does, by firing the
     owner's `OnVerticalScroll` with the pixel offset in `arg1`, so a test
     exercises the same chain the game does rather than a shortcut. ]]--
--[[ A dropdown needs to be a real frame that remembers its initialiser --
     that is the whole of what the addon uses it for. ]]--
--[[ The client's dropdown carries a `$parentText` font string for the chosen
     entry; anything sizing the pane's text has to reach it by that name. ]]--
templates.UIDropDownMenuTemplate = function(frame)
    frame.initialize = frame.initialize or nil

    local name = frame.GetName and frame:GetName()
    if name then
        _G[name .. "Text"] = newFontString(frame, "OVERLAY", "GameFontHighlightSmall")
    end
end

--[==[ **`ItemButtonTemplate`, which was not modelled at all.**

     Code that asks for it gets a frame back either way -- `CreateFrame` with an
     unknown template does not fail -- so an addon checking whether the template
     took would find it had not, and fall down its own hand-built path. That is
     the path the suite has always run, and it is not the path the game runs.

     The difference was not cosmetic. The template's `$parentCount` is
     `hidden="true"` in the client's XML, so a number written into it is
     invisible until something shows it; the hand-built font string is visible
     from the moment it exists. The junk button's count therefore passed every
     test and was never once on screen.

     Modelled with the count hidden, because that hidden flag *is* the
     behaviour worth having here. ]==]
templates.ItemButtonTemplate = function(frame)
    if not frame.name then return end

    local icon = frame:CreateTexture(frame.name .. "IconTexture", "ARTWORK")
    icon:SetAllPoints(frame)

    local border = frame:CreateTexture(frame.name .. "NormalTexture", "OVERLAY")

    local count = frame:CreateFontString(frame.name .. "Count", "OVERLAY",
            "NumberFontNormal")
    count:Hide()

    frame.iconTexture = icon
    frame.countString = count
    frame.borderTexture = border
end

templates.FauxScrollFrameTemplate = function(frame)
    if not frame.name then return end

    local bar = CreateFrame("Slider", frame.name .. "ScrollBar", frame)
    bar.scrollOwner = frame

    bar.SetValue = function(self, value)
        self.value = value or 0

        local owner = self.scrollOwner
        if not owner then return end

        local prevThis, prevArg = this, arg1

        --[==[ **Both events, because the client has two and they are not the
             same one.**

             `OnVerticalScroll` belongs to the scroll frame and fires when the
             frame is scrolled. `OnValueChanged` belongs to the slider and fires
             when its value changes. This modelled only the first, so a list
             that listened to the slider -- which is what actually moves when
             somebody drags a thumb -- had no way to be tested at all.

             Firing both is the permissive model on purpose. Which of them the
             client delivers in which situation is not knowable from here, and a
             harness that picks a side would fail correct code as readily as it
             passed broken code. What can be asserted is that a list works off
             whichever arrives. ]==]
        local bar = self.scripts and self.scripts.OnValueChanged
        if bar then
            this, arg1 = self, self.value
            bar(self.value)
            this, arg1 = prevThis, prevArg
        end

        local handler = owner.GetScript and owner:GetScript("OnVerticalScroll")
        if not handler then
            if not bar then owner.offset = 0 end
            return
        end

        -- The client sets `this` and `arg1` around the call; so does this.
        this, arg1 = owner, self.value
        handler()
        this, arg1 = prevThis, prevArg
    end

    bar.GetValue = function(self) return self.value or 0 end

    frame.scrollBar = bar
end

--[[ A scanning tooltip. Loading an item or a spell copies a block out of
     Stub.tooltips into the line font strings, which is the only part of a real
     tooltip the addon ever reads.

     These methods have to be real rather than left to the auto-faking metatable:
     NumLines answering nil would turn `for i = 1, tip:NumLines()` into an error
     rather than an empty loop, and the whole scrape would silently never run. ]]--
templates.GameTooltipTemplate = function(frame)
    frame.lines = {}
    frame.lineCount = 0

    frame.Line = function(self, i)
        if not self.lines[i] then
            self.lines[i] = newFontString(self, "OVERLAY", "GameTooltipText")
            if self.eqStubName then
                _G[self.eqStubName .. "TextLeft" .. i] = self.lines[i]
            end
        end
        return self.lines[i]
    end

    --[==[ **Clearing keeps the text.** The client's `ClearLines` drops the
         count and hides the line font strings; it does not blank them, so a
         line past `NumLines()` still answers `GetText()` with whatever the
         last tooltip left there. This blanked every line, which agreed with a
         reader that walks to the first nil -- and such a reader, in game,
         reads the previous item's tail as this item's. ]==]
    frame.ClearLines = function(self)
        self.lineCount = 0
        for i = 1, table.getn(self.lines) do self.lines[i]:Hide() end
    end

    frame.NumLines = function(self) return self.lineCount end
    --[==[ **Who owns the tooltip and how it is anchored, which was recorded by
         nothing.**

         `SetOwner` did nothing at all here, so no test could tell an ECO-placed
         tooltip from one the client anchored itself -- and the difference
         matters: almost everything in the interface reaches `GameTooltip`
         through `GameTooltip_SetDefaultAnchor`, which this addon wraps and
         re-places, while a few own it directly and keep the client's anchor.
         The need/greed popup is one of the few.

         Recorded rather than acted on. Nothing here draws, and the only reader
         is a test asking what the addon did. ]==]
    frame.SetOwner = function(self, owner, anchor)
        self.owner = owner
        self.ownerAnchor = anchor
    end

    frame.GetOwner = function(self) return self.owner, self.ownerAnchor end

    --[[ Writing to a tooltip, as opposed to scraping one. The addon only ever
         read tooltips until the meters grew a hover breakdown; without these the
         breakdown could be built and never once executed by the suite, which is
         constraint 49's shape all over again.

         Both halves of a double line are kept, because the whole point of the
         breakdown is a name on the left and a number on the right, and a stub
         that dropped one of them could not tell a correct row from an empty
         one. ]]--
    frame.AddLine = function(self, text)
        self.lineCount = self.lineCount + 1
        self:Line(self.lineCount):SetText(text or "")
        self:Line(self.lineCount):Show()
        self.rightLines = self.rightLines or {}
        self.rightLines[self.lineCount] = nil
    end

    frame.AddDoubleLine = function(self, left, right)
        self.lineCount = self.lineCount + 1
        self:Line(self.lineCount):SetText(left or "")
        self:Line(self.lineCount):Show()
        self.rightLines = self.rightLines or {}
        self.rightLines[self.lineCount] = right or ""
    end

    frame.RightLine = function(self, i)
        return self.rightLines and self.rightLines[i]
    end

    --[[ **A tooltip the client filled in, rather than one an addon built.**

         This is the case 1.12 gives no unit token for: hovering a mob populates
         the tooltip from the C client, so there is nothing to ask "which unit is
         this". Anything reading the tooltip has to read the *text*, and this
         writes the text the way the client writes it -- "Level 60 Elite
         Humanoid", one string, elite and type included.

         Then it fires OnShow, because that is the only signal an addon gets. ]]--
    --[[ **An item tooltip, with the sell price where the client puts it.**

         1.12 prints a vendor price into a *money frame* rather than into text,
         and only while a merchant window is open. Modelled that way -- a
         separate frame with gold, silver and copper of its own -- because a stub
         that wrote "Sell Price: 3s" as a line would agree with a scraper that
         only ever read lines, and the client does not write one.

         The addon reads text too, for the sell-value addons that add a line.
         Both paths exist here so both can be exercised. ]]--
    frame.SetBagItem = function(self, bag, slot)
        local b = Stub.bags[bag]
        local item = b and b[slot]

        self:ClearLines()
        if not item then return end

        self:AddLine(item.name)

        --[[ The client only prints it at a vendor. That is the constraint the
             whole learned-price store exists to work around, so it is real
             here. ]]--
        local price = nil
        if MerchantFrame and MerchantFrame:IsVisible() then
            price = item.price
        end

        --[[ For the stack, not for one, which is how the client writes it. ]]--
        if price then price = price * (item.count or 1) end

        if item.priceAsText and price then
            self:AddLine("Sell Price: " .. EquadisClassicOverhaul.Money(price))
            price = nil
        end

        self:SetMoney(price)
    end

    --[[ The money frame, named the way the client names it: `<tip>MoneyFrame1`
         with a Gold, Silver and Copper button under it, each carrying its own
         text. Anything reading it has to walk that naming. ]]--
    frame.SetMoney = function(self, copper)
        if not self.eqStubName then return end

        local units = { GoldButton = 10000, SilverButton = 100, CopperButton = 1 }
        local moneyName = self.eqStubName .. "MoneyFrame1"

        if not _G[moneyName] then
            _G[moneyName] = CreateFrame("Frame", moneyName, self)

            for suffix in pairs(units) do
                local button = CreateFrame("Frame", moneyName .. suffix, nil)
                _G[moneyName .. suffix .. "Text"] =
                        newFontString(button, "OVERLAY", "GameFontNormal")
            end
        end

        --[[ **Shown when there is money and hidden when there is not**, which
             is what the client's SetTooltipMoney / GameTooltip_ClearMoney pair
             does. An addon that hides the frame after reading it -- and the
             value block does, every time -- would otherwise never see it again
             once the next item arrived, and a test could not tell "the
             merchant price was read" from "the frame was already hidden". ]]--
        local frame = _G[moneyName]
        if copper then frame:Show() else frame:Hide() end
        frame.staticMoney = copper

        local left = copper

        for _, suffix in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
            local text = _G[moneyName .. suffix .. "Text"]

            if not left then
                text:SetText("")
            else
                local worth = units[suffix]
                text:SetText(tostring(math.floor(left / worth)))
                left = mod(left, worth)
            end
        end
    end

    --[==[ **The rollable item's own setter**, which the need/greed popup is the
         only user of and which was modelled by nothing at all.

         `GroupLootFrame`'s icon calls `GameTooltip:SetOwner(this,
         "ANCHOR_RIGHT")` and then this. Written to produce exactly what
         `SetBagItem` produces for the same item, so that any difference in what
         the addon draws afterwards is the addon's doing rather than the
         fixture's. ]==]
    frame.SetLootRollItem = function(self, id)
        local roll = Stub.lootRolls[id]

        self:ClearLines()
        if not roll then return end

        self:AddLine(roll.name)

        local price = nil
        if MerchantFrame and MerchantFrame:IsVisible() then price = roll.price end
        if price then price = price * (roll.count or 1) end

        self:SetMoney(price)

        --[[ The client's setters show the tooltip themselves. Fired the way
             `SetMob` does, because `Show` here does not run the script. ]]--
        local onShow = self:GetScript("OnShow")
        if onShow then onShow() end
    end

    frame.SetMob = function(self, name, level, kind, elite)
        self:ClearLines()
        self:AddLine(name)

        local second = "Level " .. tostring(level)
        if elite then second = second .. " Elite" end
        if kind then second = second .. " " .. kind end

        self:AddLine(second)

        local onShow = self:GetScript("OnShow")
        if onShow then onShow() end
    end

    local function load(self, key)
        self:ClearLines()

        local block = Stub.tooltips[key]
        if not block then return end

        for i = 1, table.getn(block) do
            self:Line(i):SetText(block[i])
            self:Line(i):Show()
        end
        self.lineCount = table.getn(block)
    end

    frame.SetInventoryItem = function(self, unit, slot) load(self, "item" .. slot) end
    frame.SetSpell = function(self, index, bookType) load(self, "spell" .. index) end

    --[[ A talent's tooltip, keyed "talent<tab>:<index>" like GetTalentInfo's
         rank. The client prints the current rank, a "Next rank:" line, and
         the next rank's text under it -- a fixture that wants to prove the
         reader stops there has to write all three. ]]--
    frame.SetTalent = function(self, tab, index) load(self, "talent" .. tab .. ":" .. index) end

    --[[ **A buff's own tooltip**, which is the only way to recognise the mounts
         whose icon does not give them away: a class mount, an engineering mount
         or anything a private server added carries an icon outside the family an
         addon would match on. A stub with no buff tooltips agrees with a port
         that only ever looks at icons. ]]--
    frame.SetPlayerBuff = function(self, index) load(self, "buff" .. index) end

    --[[ 1.12 has no GetActionSpell, so the only way to learn what an action
         button holds is to point a tooltip at it and read line one. The stub
         answers from Stub.actionBar, which maps slot -> name. ]]--
    frame.SetAction = function(self, slot)
        self:ClearLines()

        local name = Stub.actionBar and Stub.actionBar[slot]
        if not name then return end

        self:Line(1):SetText(name)
        self.lineCount = 1
    end
end

function CreateFrame(ftype, name, parent, template)
    local f = newObject(ftype or "Frame")
    f.frameType = ftype
    --[==[ **A frame's own name is kept out of `name`, which is the addon's.**

         `raidframes` stores its name FontString as `button.name`, which is
         ordinary and harmless in the game -- `GetName` is a C function and
         cannot be shadowed by a Lua field. Here it was the same slot, so
         `GetName()` handed back a FontString and the first thing to concatenate
         it threw.

         A harness that reserves a common field name is a harness that decides
         what the addon may call things. So it uses one nothing would collide
         with, and the two readers below follow it. ]==]
    f.eqStubName = name
    f.name = name
    f.parent = parent
    f.children = {}
    f.scripts = {}
    f.events = {}
    f.level = parent and ((parent.level or 0) + 1) or 0
    f.scale = 1

    definePoints(f)
    defineShow(f)
    defineSize(f)

    --[==[ **`GetName(1)` is SuperWoW's unit GUID, and nothing else's.**

         Without that client mod the argument is ignored and the frame answers
         its own name -- a string, so a type check passes it and only
         `UnitExists` tells the two apart. Modelled both ways round, because a
         stub that always handed back a GUID would agree with a port that never
         checked. ]==]
    f.GetName = function(self, superwow)
        if superwow == 1 and self.superwowGuid then return self.superwowGuid end
        return self.eqStubName
    end
    f.GetParent = function(self) return self.parent end

    --[[ **Re-parenting, which is a real operation and not a rename.** A child
         inherits its parent's visibility, alpha and scale, so moving a button
         off Blizzard's bar frame onto one of ours is what stops the client
         hiding it along with its own art. The list on both sides is kept
         straight because `IsVisible` walks it. ]]--
    f.SetParent = function(self, p)
        if self.parent and self.parent.children then
            for i = table.getn(self.parent.children), 1, -1 do
                if self.parent.children[i] == self then
                    table.remove(self.parent.children, i)
                end
            end
        end

        self.parent = p
        if p and p.children then table.insert(p.children, self) end
    end
    f.GetObjectType = function(self) return self.frameType end

    --[[ **A frame always has a level.**

         This answered nil until something set one, and the client never does --
         every frame has a level from the moment it exists. Code that stacks one
         frame against another reads it and adds to it, so a nil here is an
         arithmetic error in the harness for something that cannot happen in the
         game. One rather than zero because that is where the client starts. ]]--
    f.level = 1

    f.SetFrameLevel = function(self, v) self.level = v end
    f.GetFrameLevel = function(self) return self.level or 1 end

    --[[ The client refusing to let a moving frame leave the screen. Recorded
         rather than simulated: the stub does not run a drag, so what is worth
         asserting is that the window *asked* for it -- which is the thing that
         was missing and let both meters be pulled off the edge. ]]--
    --[[ **Backdrops, recorded rather than faked.** The edit box's colour is set
         on a frame behind it because 1.12's EditBox does not reliably take one
         itself, and a stub that swallowed the call could not tell the two
         apart. ]]--
    f.SetBackdrop = function(self, b) self.backdrop = b end
    f.GetBackdrop = function(self) return self.backdrop end
    f.SetBackdropColor = function(self, r, g, b, a)
        self.backdropColor = { r, g, b, a }
    end
    f.SetBackdropBorderColor = function(self, r, g, b, a)
        self.backdropBorder = { r, g, b, a }
    end

    --[[ Readable, because the client's own is: an addon that colours a border
         by item quality reads back what it set to decide whether it has
         already done it. A setter with no getter meant a test could see that a
         border was drawn but never in which colour. ]]--
    f.GetBackdropBorderColor = function(self)
        local c = self.backdropBorder
        if not c then return nil end
        return c[1], c[2], c[3], c[4]
    end

    f.SetClampedToScreen = function(self, v) self.clamped = v and true or false end
    f.IsClampedToScreen = function(self) return self.clamped or false end

    --[[ Movable, and *placed* -- two different things the client tracks
         separately. `SetUserPlaced` is what stops it putting the frame back
         where the XML says on the next load, so a drag without it works and is
         forgotten, which is indistinguishable from not working. ]]--
    f.SetMovable = function(self, v) self.movable = v and true or false end
    f.IsMovable = function(self) return self.movable or false end
    f.SetUserPlaced = function(self, v) self.userPlaced = v and true or false end
    f.IsUserPlaced = function(self) return self.userPlaced or false end

    f.SetScale = function(self, v) self.scale = v end
    f.GetScale = function(self) return self.scale end
    f.GetEffectiveScale = function(self)
        local s, p = self.scale, self.parent
        while p do s = s * (p.scale or 1); p = p.parent end
        return s
    end

    f.SetAlpha = function(self, v) self.alpha = v end
    f.GetAlpha = function(self) return self.alpha or 1 end

    f.EnableMouse = function(self, v) self.mouse = v and true or false end
    f.EnableKeyboard = function(self, v) self.keyboard = v and true or false end
    f.IsKeyboardEnabled = function(self) return self.keyboard and true or false end

    --[[ Any frame can take the wheel in 1.12; the client simply leaves it off
         until something asks. Defined here rather than on the chat windows
         alone, which is where it used to live -- a minimap that cannot be
         asked to take the wheel agrees with a port that never offers it. ]]--
    f.EnableMouseWheel = function(self, v) self.mouseWheel = v and true or false end
    f.IsMouseWheelEnabled = function(self) return self.mouseWheel and true or false end
    f.IsMouseEnabled = function(self) return self.mouse end

    --[[ **Strata, which orders frames across parents where level cannot.**

         Frame *level* only sorts frames within one strata, so a handle drawn
         over a bar full of buttons is only reliably in front if it is raised a
         layer. Edit mode does exactly that and puts it back afterwards, and the
         auto-faking metatable would have answered both calls with nothing --
         letting a test assert a strata that was never set. ]]--
    f.SetFrameStrata = function(self, strata) self.strata = strata end
    f.GetFrameStrata = function(self) return self.strata or "MEDIUM" end
    f.IsMouseEnabled = function(self) return self.mouse end

    --[[ **OnClick belongs to Button, not Frame**, and neither does
         RegisterForClicks. The auto-faking metatable answers any PascalCase
         call, so a Frame given an OnClick script looked fine here and would have
         errored the first time anyone clicked it in game -- which is how a
         click handler reached the damage meter's header bar.

         Frames get OnMouseUp and OnMouseDown; a click script on one is a
         mistake worth failing loudly for. ]]--
    local BUTTON_ONLY = { OnClick = true, OnDoubleClick = true }

    f.SetScript = function(self, which, fn)
        if BUTTON_ONLY[which] and self.frameType ~= "Button"
                and self.frameType ~= "CheckButton" then
            error(self.frameType .. " has no " .. which
                    .. " script -- that belongs to Button. Use OnMouseUp.", 2)
        end

        self.scripts[which] = fn
    end

    f.GetScript = function(self, which) return self.scripts[which] end
    f.HasScript = function() return true end

    f.RegisterForClicks = function(self)
        if self.frameType ~= "Button" and self.frameType ~= "CheckButton" then
            error(self.frameType .. " has no RegisterForClicks", 2)
        end
    end

    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.UnregisterAllEvents = function(self) self.events = {} end
    f.IsEventRegistered = function(self, e) return self.events[e] and true or false end

    --[[ **Children and regions, tracked in creation order.**

         Nothing needed these until nameplates, and nameplates need nothing else:
         a 1.12 plate has no name and no unit, so it is found by walking
         `WorldFrame:GetChildren()` and identified by what its first region is.
         Order is the whole of the identification -- `GetRegions()` answering the
         right objects in the wrong order would let a port read the level as the
         name and pass.

         Appended, never inserted, which is what the client does and what lets
         the scan look only at the new tail. ]]--
    f.children = {}
    f.regions = {}

    f.GetNumChildren = function(self) return table.getn(self.children) end
    f.GetChildren = function(self) return unpack(self.children) end
    f.GetNumRegions = function(self) return table.getn(self.regions) end
    f.GetRegions = function(self) return unpack(self.regions) end


    f.CreateTexture = function(self, tname, layer)
        local t = newTexture(self, layer)
        if tname then _G[tname] = t end
        table.insert(self.regions, t)
        return t
    end
    f.CreateFontString = function(self, fname, layer, inherits)
        local s = newFontString(self, layer, inherits)
        if fname then _G[fname] = s end
        table.insert(self.regions, s)
        return s
    end

    --[[ A status bar's own colour, which for a nameplate is not decoration: the
         client encodes hostility in it, and reading it back is the only way to
         know whether the thing on screen wants to kill you. ]]--
    f.SetStatusBarColor = function(self, r, g, b, a)
        self.barColor = { r, g, b, a }
    end

    f.GetStatusBarColor = function(self)
        if not self.barColor then return 1, 1, 1, 1 end
        return self.barColor[1], self.barColor[2], self.barColor[3], self.barColor[4]
    end

    f.SetStatusBarTexture = function(self, t) self.barTexture = t end
    f.GetStatusBarTexture = function(self) return self.barTexture end

    -- statusbar / slider value state
    f.SetMinMaxValues = function(self, lo, hi) self.min, self.max = lo, hi end
    f.GetMinMaxValues = function(self) return self.min, self.max end
    f.SetValue = function(self, v)
        self.value = v
        local fn = self.scripts.OnValueChanged
        if fn then
            local saved = this
            this = self
            fn(v)
            this = saved
        end
    end
    f.GetValue = function(self) return self.value or 0 end
    f.SetValueStep = function(self, v) self.step = v end

    --[[ Which way a slider or a status bar runs. Recorded rather than acted on:
         nothing here draws, and the only reader is a test asking whether the
         addon said so. ]]--
    f.SetOrientation = function(self, o) self.orientation = o end
    f.GetOrientation = function(self) return self.orientation or "HORIZONTAL" end

    --[[ A slider's knob, which is a real region: the panel's scrollbar sizes and
         tints it, and a stub that swallowed the path would let a `SetWidth` on
         nothing pass. ]]--
    f.SetThumbTexture = function(self, path)
        if not self.thumb then
            self.thumb = self:CreateTexture(nil, "OVERLAY")
        end

        if type(path) == "string" then self.thumb:SetTexture(path) end
        return self.thumb
    end

    f.GetThumbTexture = function(self) return self.thumb end

    --[==[ **A scroll frame**, which is one frame showing part of another.

         `SetScrollChild` **reparents**, which is the half worth modelling: the
         options panel builds its page, hands it over, and then shows and hides
         the *window* -- so a stub that merely recorded the child would let a
         page shown inside a hidden window read as visible.

         The range is arithmetic on two heights and clamps at nought. A child
         shorter than its window does not scroll upwards. ]==]
    f.SetScrollChild = function(self, child)
        self.scrollChild = child

        if child and child.SetParent and child.parent ~= self then
            child:SetParent(self)
        end
    end

    f.GetScrollChild = function(self) return self.scrollChild end

    f.GetVerticalScrollRange = function(self)
        local child = self.scrollChild
        local range = ((child and child:GetHeight()) or 0) - (self:GetHeight() or 0)

        if range < 0 then range = 0 end
        return range
    end

    f.GetVerticalScroll = function(self) return self.verticalScroll or 0 end

    f.SetVerticalScroll = function(self, v)
        self.verticalScroll = v or 0

        local fn = self.scripts.OnVerticalScroll
        if fn then
            local saved = this
            this = self
            fn(self.verticalScroll)
            this = saved
        end
    end

    --[[ The client recomputes the child's rectangle here. Nothing is cached on
         this side, so there is nothing to recompute -- but the call has to
         exist, because the addon makes it. ]]--
    f.UpdateScrollChildRect = function(self) end

    -- checkbutton
    f.SetChecked = function(self, v) self.checked = v and true or false end
    f.GetChecked = function(self) return self.checked end
    f.Disable = function(self) self.enabled = false end
    f.Enable = function(self) self.enabled = true end
    f.IsEnabled = function(self) return self.enabled ~= false end

    -- editbox
    f.SetText = function(self, v) self.text = v or "" end
    f.GetText = function(self) return self.text or "" end
    --[[ **Appending to the chat box, which is how 1.12 shift-clicks a link.**
         `ChatEdit_InsertLink` is a 2.0 function and does not exist here; what
         this client does is insert into the edit box when it is visible, which
         is what its own bag buttons do. Modelled because "did the link reach
         chat" is the assertion. ]]--
    f.Insert = function(self, text)
        self.text = (self.text or "") .. tostring(text or "")
    end

    f.SetAutoFocus = noop
    --[[ Remembered rather than swallowed: a cap below the length of what the
         addon puts in the box truncates it in the game and is invisible here,
         which is exactly what happened to the profile share codes. ]]--
    f.SetMaxLetters = function(self, n) self.maxLetters = n end
    f.GetMaxLetters = function(self) return self.maxLetters end
    f.ClearFocus = noop
    f.SetFocus = noop
    f.SetFont = noop
    f.SetJustifyH = noop

    -- button textures
    f.SetNormalTexture = function(self, path)
        self.normalTex = self.normalTex or newTexture(self, "ARTWORK")
        self.normalTex.texture = path
    end
    f.SetPushedTexture = function(self, path)
        self.pushedTex = self.pushedTex or newTexture(self, "ARTWORK")
        self.pushedTex.texture = path
    end
    f.SetHighlightTexture = function(self, path)
        self.highlightTex = self.highlightTex or newTexture(self, "HIGHLIGHT")
        self.highlightTex.texture = path
    end
    --[[ The fourth of the four, and the one that was missing. A check button
         with no checked texture cannot say it is checked, and the code that
         gives it one was calling a nil. ]]--
    f.SetCheckedTexture = function(self, path)
        self.checkedTex = self.checkedTex or newTexture(self, "OVERLAY")
        self.checkedTex.texture = path
    end

    f.GetNormalTexture = function(self) return self.normalTex end
    f.GetPushedTexture = function(self) return self.pushedTex end
    f.GetHighlightTexture = function(self) return self.highlightTex end
    f.GetCheckedTexture = function(self) return self.checkedTex end

    --[[ A button's highlight held on without the mouse, which is how the
         bag window points at a bag's slots. Recorded, so a test can ask. ]]--
    f.LockHighlight = function(self) self.highlightLocked = true end
    f.UnlockHighlight = function(self) self.highlightLocked = nil end

    --[[ The two tooltip setters, which is the only way an addon can learn what
         a unit's aura is called. Separate because the client's lists are
         numbered separately -- see `Stub.AuraNamed`. ]]--
    f.SetUnitBuff = function(self, unit, index)
        return Stub.WriteTooltipAura(self, unit, index, false)
    end

    f.SetUnitDebuff = function(self, unit, index)
        return Stub.WriteTooltipAura(self, unit, index, true)
    end

    f.SetBackdrop = function(self, bd) self.backdrop = bd end
    f.GetBackdrop = function(self) return self.backdrop end

    if name then _G[name] = f end
    if parent and parent.children then table.insert(parent.children, f) end

    --[[ Whose frame this is. Only true between `Stub.BeginAddonLoad` and
         `Stub.EndAddonLoad`, which is the boot's own window: a frame the stub
         builds lazily for a test -- the static popup, a tooltip's money frame --
         is the client's and outlives the login that first asked for it. ]]--
    f.fromAddonLoad = addonLoading
    table.insert(frames, f)

    if template and templates[template] then templates[template](f) end
    f.template = template

    return f
end

-- ---------------------------------------------------------------------------
-- driving the fake client
-- ---------------------------------------------------------------------------

--[[ Five, because `UNIT_CASTEVENT` carries five and a stub that only passed
     three would hand the handler a nil cast time -- which is the one thing that
     event exists to provide. ]]--
function Stub.FireEvent(name, a1, a2, a3, a4, a5)
    local saved, savedA1 = event, arg1
    event, arg1, arg2, arg3, arg4, arg5 = name, a1, a2, a3, a4, a5

    for i = 1, table.getn(frames) do
        local f = frames[i]
        if f.events[name] and f.scripts.OnEvent then
            local savedThis = this
            this = f
            f.scripts.OnEvent()
            this = savedThis
        end
    end

    event, arg1 = saved, savedA1
end

--[[ **How many frames are listening for an event**, which is the only way to
     ask whether a handler can ever run.

     A branch on `event == "X"` that nothing registered for is dead code that
     reads as a working feature, and the registration is usually in another file
     from the branch -- behind a list, a loop, or a module's own private frame.
     Counting listeners is the question that survives all of those. ]]--
function Stub.EventListeners(name)
    local n = 0

    for i = 1, table.getn(frames) do
        local f = frames[i]
        if f and f.events and f.events[name] then n = n + 1 end
    end

    return n
end

function Stub.Tick(dt, count)
    count = count or 1
    for n = 1, count do
        clock = clock + (dt or 0.05)
        for i = 1, table.getn(frames) do
            local f = frames[i]
            if f.scripts.OnUpdate and f:IsVisible() ~= false then
                --[[ **`arg1` as well as the parameter.**

                     1.12 hands an OnUpdate its elapsed time in the global
                     `arg1`, not as an argument, and a frame script written for
                     the client reads it there. This passed it as a parameter
                     only, so any such script read whatever `arg1` happened to
                     be holding from the last event -- usually a string, which
                     is an arithmetic error the moment somebody subtracts it.

                     Found when thirteen modules stopped shipping switched off
                     and the chat window's jump-to-bottom button began to
                     tick. ]]--
                local savedThis, savedArg = this, arg1
                this, arg1 = f, dt or 0.05
                f.scripts.OnUpdate(dt or 0.05)
                this, arg1 = savedThis, savedArg
            end
        end
    end
end

function Stub.Click(frame, button)
    if not frame or not frame.scripts.OnClick then return false end
    local savedThis, savedArg = this, arg1
    this, arg1 = frame, button or "LeftButton"
    frame.scripts.OnClick()
    this, arg1 = savedThis, savedArg
    return true
end

--[[ Hovering, which the client does by setting `this` and calling OnEnter --
     exactly as it does for a click. Calling the handler directly from a test
     leaves `this` at whatever it was, so the handler reads the wrong frame or
     nil: a bug in the test that looks like a bug in the addon. ]]--
function Stub.Hover(frame)
    if not frame or not frame.scripts.OnEnter then return false end
    local savedThis = this
    this = frame
    frame.scripts.OnEnter()
    this = savedThis
    return true
end

function Stub.Unhover(frame)
    if not frame or not frame.scripts.OnLeave then return false end
    local savedThis = this
    this = frame
    frame.scripts.OnLeave()
    this = savedThis
    return true
end

function Stub.MouseDown(frame, button)
    if not frame or not frame.scripts.OnMouseDown then return false end
    local savedThis, savedArg = this, arg1
    this, arg1 = frame, button or "LeftButton"
    frame.scripts.OnMouseDown()
    this, arg1 = savedThis, savedArg
    return true
end

function Stub.MouseUp(frame)
    if not frame or not frame.scripts.OnMouseUp then return false end
    local savedThis = this
    this = frame
    frame.scripts.OnMouseUp()
    this = savedThis
    return true
end

--[[ Open a dropdown and return the buttons it offered. The initialiser calls
     UIDropDownMenu_AddButton once per entry, so collecting them is how a test
     sees the menu without a real UI. ]]--
local menuButtons
function Stub.OpenMenu(drop)
    menuButtons = {}
    if drop and drop.initialize then
        local savedThis = this
        this = drop
        drop.initialize()
        this = savedThis
    end
    return menuButtons
end

-- pick an entry from the menu the way a click would
function Stub.ChooseMenu(drop, value)
    local buttons = Stub.OpenMenu(drop)
    for i = 1, table.getn(buttons) do
        if buttons[i].value == value then
            local savedThis = this
            this = buttons[i]
            buttons[i].func()
            this = savedThis
            return true
        end
    end
    return false
end

function Stub.Frames() return frames end
function Stub.SetClock(t) clock = t end
function Stub.Clock() return clock end

function Stub.UnknownMethods()
    local list = {}
    for k in pairs(unknown) do table.insert(list, k) end
    table.sort(list)
    return list
end

-- ---------------------------------------------------------------------------
-- the simulated character
-- ---------------------------------------------------------------------------

Stub.player = {
    class = "ROGUE",
    localizedClass = "Rogue",
    name = "Testchar",
    level = 60,
    realm = "Turtle WoW",
    powerType = 3,
    power = 100,
    powerMax = 100,
    health = 2400,
    healthMax = 3000,
    combo = 0,
    mainSpeed = 2.6,
    offSpeed = 1.7,
    inCombat = false,
    dead = false,
    buffs = {},

    rangedSpeed = 2.9,

    -- what the target is, and how far away. hasTarget nil means none at all.
    hasTarget = false,
    targetDistance = 0,

    -- UnitStat indices: 4 intellect, 5 spirit
    stats = { [1] = 20, [2] = 20, [3] = 20, [4] = 100, [5] = 80 },

    -- GetSpellTexture by book index
    spellbook = {},

    -- spell names by book index, for the distance readout's auto-attack lookup
    spellNames = {},
    spellCount = 0,

    -- GetTalentInfo rank, keyed "tab:index"
    talents = {},
}

-- blocks of tooltip text, keyed "item<slot>" and "spell<bookIndex>"
Stub.tooltips = {}

--[[ Group units answer from Stub.group; every other token is the player.

     Modelled rather than left as "always the player", because a threat meter
     that looked up every name and got its own back would colour the whole raid
     one class and pass a test that proved nothing. ]]--
local function groupMember(unit)
    if type(unit) ~= "string" then return nil end

    local _, _, index = string.find(unit, "^%a+(%d+)$")
    if not index then return nil end

    return Stub.group and Stub.group[tonumber(index)]
end

function UnitClass(unit)
    --[==[ **Quiet for an unseen unit, but not for an unseen group member.**

         The distinction is the whole point. `UnitIsPlayer` reads an object in
         the world and has nothing to read when the unit is out of range. A
         party or raid member's class does not come from that object -- it comes
         from the roster the server pushes and keeps current at any distance,
         which is why group addons have always been able to colour a frame for
         somebody across the zone.

         Modelling both as silent was over-strict, and over-strict is its own
         kind of wrong: it fails code that is correct and sends somebody looking
         for a bug that is not there. ]==]
    if unit and Stub.unseen[unit]
            and not string.find(unit, "^party%d")
            and not string.find(unit, "^raid%d") then
        return nil
    end

    local member = groupMember(unit)
    if member then return member.class, member.class end
    if unit == "target" and Stub.target then
        return Stub.target.class, Stub.target.class
    end
    return Stub.player.localizedClass, Stub.player.class
end

--[[ The target is answered from `Stub.target` rather than falling through to the
     player. It used to fall through, which was harmless while nothing read a
     target's name -- and the moment something did, it would have cached the
     player's own name against the target's class and looked like it worked. ]]--
--[==[ **`GetItemFamily`, which is how a quiver knows it holds arrows.**

     A bitmask on the item and a matching one on the bag: they overlap or the
     item cannot go in. 1.12 has this and the sorter now depends on it -- an
     arrow aimed at an ordinary slot is a move the client silently refuses, and
     a sorter that does not check reissues that same refused move on every bag
     update, for ever.

     Nought for anything the test has not said otherwise about, which is the
     right default: an ordinary item in an ordinary bag, and the case almost
     every assertion here is about. ]==]
Stub.itemFamily = {}

--[[ Not on a 1.12 client: `GetItemFamily` arrived two expansions later. The
     stub shipped it anyway, so the bag sorter's quiver handling was exercised
     through a call the game does not have while the path the game takes --
     reading the bag's and the item's types -- was never run. Off by default;
     a test for a later client switches it on. ]]--
local function stubGetItemFamily(item)
    local id = tonumber(item)

    if not id then
        local _, _, found = string.find(tostring(item or ""), "item:(%d+)")
        id = tonumber(found)
    end

    if not id then
        id = Stub.itemIds and Stub.itemIds[tostring(item)]
    end

    return (id and Stub.itemFamily[id]) or 0
end

function Stub.SetItemFamilyAPI(present)
    GetItemFamily = present and stubGetItemFamily or nil
end

function UnitName(unit)
    --[[ A GUID is a unit token on this client, so it answers `UnitName` like
         any other -- which is what lets a cast filed under a GUID also be filed
         under the caster's name. ]]--
    local plate = Stub.PlateUnit and Stub.PlateUnit(unit)
    if plate and plate.name then return plate.name end

    local member = groupMember(unit)
    if member then return member.name end
    if unit == "target" then return Stub.target and Stub.target.name end
    return Stub.player.name
end
function GetRealmName() return Stub.player.realm end
function UnitPowerType(unit)
    local member = groupMember(unit)
    if member and member.powerType ~= nil then return member.powerType end
    return Stub.player.powerType
end
function UnitMana(unit)
    local member = groupMember(unit)
    if member and member.power ~= nil then return member.power end
    return Stub.player.power
end
function UnitManaMax(unit)
    local member = groupMember(unit)
    if member and member.powerMax ~= nil then return member.powerMax end
    return Stub.player.powerMax
end
--[[ **A group member's own health when the fixture gives them one.**

     This answered the player's health for every unit token, which is fine for
     a module that only ever asks about one unit and useless for one drawing
     forty. Raid frames put unit *n* on button *n*, and a stub that gave every
     unit the same numbers would agree with a port that put the right health on
     the wrong row -- the same class of bug as colouring a bag slot by its loop
     counter.

     Explicit wins, everything else keeps the old meaning, so the many tests
     that set `Stub.player.health` and ask about a party unit still read what
     they always did. ]]--
function UnitHealth(unit)
    local member = groupMember(unit)
    if member and member.health then return member.health end
    return Stub.player.health
end

function UnitHealthMax(unit)
    local member = groupMember(unit)
    if member and member.healthMax then return member.healthMax end
    return Stub.player.healthMax
end
function UnitAttackSpeed(unit) return Stub.player.mainSpeed, Stub.player.offSpeed end
function UnitAffectingCombat(unit) return Stub.player.inCombat end
--[[ Answered per unit when a test says so, and by the player otherwise.

     This used to return the player's own death for every token, so a dead
     target read as alive and code asking "is the thing I found still alive"
     could never be told yes. But plenty of tests set `Stub.player.dead` and
     mean the target -- Feign Death among them -- so an explicit
     `Stub.target.dead` wins and everything else keeps the old meaning. ]]--
--[[ The client's own word, which is what a corpse's health bar says and is
     translated on a localised build. Modelled so the code that uses it is
     asserted against the constant rather than against an English string it
     would also produce from its own fallback. ]]--
DEAD = "Dead"

--[==[ **The PvP flag and its unflag countdown, none of which was modelled.**

     Turning `/pvp` off does not unflag you: the client leaves the faction icon
     up and runs a five-minute grace timer, and `GetPVPTimer` is the only source
     for it. It answers **milliseconds**, and `301000` is the sentinel for a
     permanent flag rather than a countdown -- a reader that treats that as
     "301 seconds left" draws five minutes that never move.

     `UnitIsPVP` and the `PlayerPVPIcon` region were missing too, so the whole
     readout returned at its first guard in every test there has ever been:
     three calls absent, one feature invisible. ]==]
--[[ The faction icon the countdown explains. A real region, because the
     readout anchors to it and an anchor to nothing is the difference between
     "under the icon" and "in the top-left corner of the screen". ]]--
Stub.pvp = { flagged = false, timer = 301000 }

function UnitIsPVP(unit)
    if unit ~= "player" then return nil end
    return Stub.pvp.flagged and 1 or nil
end

function GetPVPTimer() return Stub.pvp.timer end

--[==[ **A group member can be dead on their own now.**

     This read the target's flag, then the *player's*, for everybody else -- so
     `UnitIsDeadOrGhost("party1")` answered whether **you** were dead. A party or
     raid frame reading it got one answer for the whole group and no code could
     be wrong about whose corpse it was.

     `UnitIsGhost` was given a per-member flag when the raid frames needed one,
     and its own note says the two have to agree or a unit can be dead without
     being a ghost and a ghost without being dead. **The neighbour was left
     behind**, which made exactly that disagreement possible: a member marked as
     a ghost was not dead, so the readers fell through to the number.

     Same source, same order: the unit's own flag, then the player's. ]==]
function UnitIsDeadOrGhost(unit)
    if unit == "target" and Stub.target and Stub.target.dead ~= nil then
        return Stub.target.dead
    end

    local member = groupMember(unit)

    if member then
        --[[ A ghost is dead-or-ghost by definition, whichever way the fixture
             was written. ]]--
        if member.ghost then return true end
        if member.dead ~= nil then return member.dead end
    end

    return Stub.player.dead
end

--[==[ **Dead, as distinct from dead-or-a-ghost.**

     `UnitIsDeadOrGhost` answers yes for a corpse and for the ghost that walks
     away from it; `UnitIsDead` answers yes only for the corpse. The two have to
     agree in the one direction that matters -- **a ghost is not dead** -- or the
     harness invents a state the client never produces, which is the fault that
     had to be corrected in `UnitIsGhost` and `UnitIsConnected` before it.

     **It was not modelled at all**, and six guards read it -- including the
     whole of the retarget feature, which re-targets a player who feigned death
     or a mob that went hostile. That feature decides what to do by comparing
     "was it dead when I targeted it" against "is it dead now", so a call that
     is simply absent makes both answers false and the comparison meaningless.
     None of it had ever run. ]==]
function UnitIsDead(unit)
    if not UnitIsDeadOrGhost(unit) then return nil end

    --[[ A ghost is up and walking, so it is not dead. Asked of the same source
         `UnitIsGhost` uses, so the two cannot disagree. ]]--
    if type(UnitIsGhost) == "function" and UnitIsGhost(unit) then return nil end

    return 1
end

--[==[ **Whether a unit is driven by a person.**

     A hunter's pet, a warlock's minion and a mind-controlled mob are all player
     controlled and are not players; an ordinary mob is neither. Three guards
     read this -- the unit frames use it to decide whether an NPC's "class"
     colouring means anything, and the creature-health cache uses it to keep a
     pet sharing a name with a real mob out of the account-wide store.

     Modelled off the same group and target fixtures everything else reads, with
     the player and the party always true, because the alternative is a stub
     that answers one thing for the whole world and cannot fail a reader. ]==]
function UnitPlayerControlled(unit)
    if unit == "player" then return 1 end

    if type(UnitIsPlayer) == "function" and UnitIsPlayer(unit) then return 1 end

    --[[ Your own pet, and anything a fixture says is somebody's. ]]--
    if unit == "pet" then return 1 end

    if unit == "target" and Stub.target and Stub.target.playerControlled ~= nil then
        return Stub.target.playerControlled and 1 or nil
    end

    return nil
end

--[==[ **Dropping the target, which nothing here could do.**

     The retarget feature's give-up path calls this, so the branch that decides
     "that was not a feign, let it go" ended at a call the harness did not have.
     Modelled as the client does it -- the target simply stops existing -- so a
     reader that clears and then asks `UnitExists` gets the truth. ]==]
function ClearTarget()
    --[[ **Losing a target is audible**, which was modelled nowhere -- so the
         scanner could clear one twice a second in silence here while ticking
         steadily in game. ]]--
    if Stub.player.hasTarget and PlaySound then
        PlaySound("INTERFACESOUND_LOSTTARGETUNIT")
    end

    Stub.player.hasTarget = false
    Stub.target = nil
    return true
end
function GetComboPoints() return Stub.player.combo end

--[[ **A ghost is not simply dead**, and the difference decides one thing here:
     `PLAYER_ALIVE` fires both when you release *and* when you are resurrected,
     so the only way to tell those apart is to ask whether a ghost is left. A
     stub without this would let a corpse waypoint be cleared by the very release
     that makes it worth having. ]]--
--[==[ **Whether their client is still there**, which is a different question
     from whether they are alive and was not modelled at all.

     Unmodelled it was auto-faked, so `UnitIsConnected` answered the same thing
     for everybody for ever and no code reading it could be wrong. The raid
     frames read it to tell a disconnect from a death -- two states a raid acts on
     in opposite ways -- so the harness has to be able to say one and not the
     other.

     Group members carry their own flag; anybody else is connected, because a
     unit you can ask about at all is one the client can see. ]==]
--[==[ **Which bar the client has decided is live.**

     A warrior in a stance, a rogue in stealth or a druid in a form is on the
     *bonus* bar: `GetBonusBarOffset` answers above zero and `BonusActionButton`
     takes the same twelve `ACTIONBUTTON` bindings the main bar has. The client
     shows one or the other and never both.

     `actionbars.lua` reads this to stand the main bar down while the bonus bar
     is up, and the note there says what it is for: both bars drawn on top of
     each other, both answering keys one to twelve, and which one a keypress
     reached decided by client state with nothing on screen to say so. That is
     the reported "my keybinds do not work".

     **It was not modelled**, so `type(GetBonusBarOffset) == "function"` read
     false and the whole of that fix was skipped in every test that has ever run.
     A fix for a reported bug with no coverage is a fix waiting to be undone by
     somebody tidying. ]==]
--[==[ **Whose mob it is**, which decides whether you can loot it and is the
     first thing the unit frames colour by.

     Neither call was modelled, so `type(UnitIsTapped) == "function"` read false
     and the tapped-grey path -- a setting somebody can see and change -- was
     skipped by every test. Two calls rather than one because the question has
     two halves: tagged at all, and tagged by *you*. ]==]
Stub.tapped = {}

function UnitIsTapped(unit)
    local t = Stub.tapped[unit]
    return (t and t.tapped) and 1 or nil
end

function UnitIsTappedByPlayer(unit)
    local t = Stub.tapped[unit]
    return (t and t.byPlayer) and 1 or nil
end

Stub.bonusBarOffset = 0

function GetBonusBarOffset() return Stub.bonusBarOffset or 0 end

function UnitIsConnected(unit)
    local member = groupMember(unit)

    if member and member.connected ~= nil then
        return member.connected and 1 or nil
    end

    --[==[ **Only a player has a connection**, and only the player's own flag
         answers for the player.

         An NPC is always connected -- the client has no other answer for one --
         and the unit frames read this to decide whether to grey a *mob*. Letting
         the player's flag speak for every unit would turn every mob grey the
         moment somebody set it, which is a fault the harness would have invented
         rather than caught. ]==]
    if unit == "player" and Stub.player.connected ~= nil then
        return Stub.player.connected and 1 or nil
    end

    return 1
end

function UnitIsGhost(unit)
    --[[ A group member's own flag first, then the player's -- which is the
         shape `UnitIsDeadOrGhost` already has, and the two have to agree or a
         unit can be dead without being a ghost and a ghost without being
         dead. ]]--
    local member = groupMember(unit)

    if member and member.ghost ~= nil then
        return member.ghost and 1 or nil
    end

    return Stub.player.ghost and 1 or nil
end
--[==[ **A buff's position in the list is not its index, and this used to say it
     was.**

     `GetPlayerBuffTexture(i)` answered `buffs[i + 1]`, so walking 0, 1, 2 read
     the list straight through and every addon-side loop that did that looked
     correct. The client does not work like this: `GetPlayerBuff(position,
     "HELPFUL")` hands back an opaque index into a space that holds this player's
     debuffs too, and only that index answers.

     What the old model could not fail was the loop that walks positions as
     though they were indices -- which is what auto dismount did, and why a
     single debuff was enough to make it decide you were not mounted.

     So the two are told apart here. `Stub.player.buffs` is still authored as a
     plain list of textures, because that is what a test wants to write; what
     changed is that the handle is deliberately **not** the position. Nothing
     depends on the arithmetic -- only on the two being different. ]==]
--[==[ **One handle space holding both kinds, which is the whole point.**

     The client keeps the player's buffs and debuffs in a single index space and
     `GetPlayerBuff(position, filter)` is the only way into it. Helpful auras
     take the odd handles here and harmful ones the even -- arbitrary, and
     chosen so that no handle is ever equal to its own position and no helpful
     handle is ever a harmful one. Both properties are load-bearing: a reader
     that walks positions as though they were handles must come out wrong, and a
     reader that resolves a debuff's position against the buff list must come
     out wrong differently.

     **The harmful half was previously answered as "none".** That was written as
     truthful -- the stub held no player debuffs -- but it made the debuff half
     of every aura reader untestable, and a reader can be wrong in a way that
     answers nothing without anybody being able to tell. ]==]
local function buffHandle(position)
    return position * 2 + 1
end

local function debuffHandle(position)
    return position * 2 + 2
end

local function buffPosition(index)
    if type(index) ~= "number" then return nil end
    if index < 1 then return nil end

    local position = (index - 1) / 2
    if position ~= math.floor(position) then return nil end

    return position
end

local function debuffPosition(index)
    if type(index) ~= "number" then return nil end
    if index < 2 then return nil end

    local position = (index - 2) / 2
    if position ~= math.floor(position) then return nil end

    return position
end

--[[ The player's own harmful auras, authored the same way the buffs are: a
     plain list of textures, because that is what a test wants to write. ]]--
Stub.player.debuffs = Stub.player.debuffs or {}

function GetPlayerBuff(position, filter)
    if type(position) ~= "number" or position < 0 then return -1 end

    local list = (filter == "HARMFUL") and Stub.player.debuffs
            or Stub.player.buffs

    if not list then return -1 end
    if position >= table.getn(list) then return -1 end

    if filter == "HARMFUL" then return debuffHandle(position) end
    return buffHandle(position)
end

function GetPlayerBuffTexture(index)
    local position = buffPosition(index)

    if position then
        if not Stub.player.buffs then return nil end
        return Stub.player.buffs[position + 1]
    end

    position = debuffPosition(index)

    if position then
        if not Stub.player.debuffs then return nil end
        return Stub.player.debuffs[position + 1]
    end

    return nil
end

--[[ **A buff's tooltip, which is the only way to recognise the mounts whose
     icon does not give them away.**

     A class mount, an engineering mount or anything a private server added
     carries an icon outside the family an addon would match on, so icon-based
     detection catches some mounts and quietly misses others. Text catches all
     of them, which is why it is worth modelling here: a stub with no buff
     tooltips agrees with a port that only ever looks at icons. ]]--

function UnitExists(unit)
    if unit == "player" then return 1, "0xPLAYER" end

    --[[ Your target's target, which exists only when something is attacking it.
         It is the one relationship a nameplate can ask about at all -- see the
         nameplate module -- so it is modelled separately rather than folded into
         "has a target". ]]--
    if unit == "targettarget" then
        return Stub.player.targetsTarget and 1 or nil
    end

    if Stub.player.hasTarget then return 1, "0xTARGET" end
    return nil
end

--[[ Is your target attacking *you*? `UnitIsUnit("targettarget", "player")` is
     the whole of nameplate threat in vanilla, and it works for exactly one
     plate. ]]--
function UnitIsUnit(a, b)
    if a == "targettarget" and b == "player" then
        return Stub.player.targetsTarget == "player" and 1 or nil
    end

    --[[ Whatever `TargetUnit` last selected *is* the target, under either
         spelling -- which is what the inspect rule above is asked against. ]]--
    if b == "target" then
        if a == "target" then return 1 end
        return (Stub.targeted ~= nil and a == Stub.targeted) and 1 or nil
    end

    return a == b and 1 or nil
end

--[[ Whether you could help this unit, which is how a friendly target is told
     from a hostile one without a reaction call. ]]--
function UnitCanAssist(a, b)
    if b == "target" then return Stub.player.targetFriendly and 1 or nil end
    return 1
end

function GetUnitGUID(unit)
    if unit == "player" then return "0xPLAYER" end
    if Stub.player.hasTarget then return "0xTARGET" end
    return nil
end

function UnitRangedDamage(unit)
    return Stub.player.rangedSpeed, 40, 60, 0, 0, 100
end

--[==[ **The paper doll, and the numbers on it.**

     1.12's character sheet answers six questions -- the five stats and armor --
     and everything else somebody wants from that screen is either a call the
     client has and does not draw, or a call the forks disagree about having.
     Both halves are modelled, because the module is written around exactly that
     difference.

     `Stub.stats` is one table so a test can hand a character a weapon skill and
     a swing speed without inventing an inventory. ]==]
--[[ Parented to nothing rather than to `CharacterFrame`, which this stub
     builds later in the file: a frame is a frame here, and the parent matters
     only where visibility is inherited. ]]--
--[==[ **The client's own cast bar**, which it shows again on every cast.

     That is the half an addon gets wrong: hiding it once lasts until the next
     spell, because `CastingBarFrame_OnEvent` calls `Show` every time one starts.
     `Stub.CastBarShows()` is that event, so a test can check the hiding
     *sticks* rather than that it happened once. ]==]
CastingBarFrame = CreateFrame("StatusBar", "CastingBarFrame", nil)
CastingBarFrame:Hide()

function Stub.CastBarShows()
    CastingBarFrame:Show()
    return CastingBarFrame:IsShown()
end

PaperDollFrame = CreateFrame("Frame", "PaperDollFrame", nil)
CharacterAttributesFrame = CreateFrame("Frame", "CharacterAttributesFrame",
        PaperDollFrame)

Stub.stats = {
    armor = 1684,
    attackPower = 634,
    rangedAttackPower = 440,
    damageLow = 95, damageHigh = 129,
    rangedLow = 123, rangedHigh = 172,
    mainSkill = 306, offSkill = 306, rangedSkill = 305,

    --[[ No swing speeds here: `UnitAttackSpeed` is already modelled from
         `Stub.player`, which is where a test sets a character's weapons. Two
         sources for one number is one of them being wrong later. ]]--
    rangedSpeed = 2.90,
    defense = 300,
    dodge = 14.5, parry = 12.25, block = 0,
}

function UnitArmor(unit)
    local armor = Stub.stats.armor
    --[[ base, effective, armor, posBuff, negBuff -- and the *second* is the one
         the character sheet shows, which is the one every reader gets wrong. ]]--
    return armor - 200, armor, armor, 200, 0
end

function UnitAttackPower(unit)
    return Stub.stats.attackPower, 0, 0
end

function UnitRangedAttackPower(unit)
    return Stub.stats.rangedAttackPower, 0, 0
end

function UnitDamage(unit)
    return Stub.stats.damageLow, Stub.stats.damageHigh,
           Stub.stats.damageLow, Stub.stats.damageHigh, 0, 0, 100
end

function UnitRangedDamage(unit)
    --[[ Speed first, which is the shape of this call and the reason the ranged
         damage row and the ranged speed row read different returns. ]]--
    return Stub.stats.rangedSpeed, Stub.stats.rangedLow, Stub.stats.rangedHigh,
           0, 0, 100
end

function UnitAttackBothHands(unit)
    return Stub.stats.mainSkill, 0, Stub.stats.offSkill, 0
end

function UnitRangedAttack(unit)
    return Stub.stats.rangedSkill, 0
end

function UnitDefense(unit)
    return Stub.stats.defense, 0
end

function GetDodgeChance() return Stub.stats.dodge end
function GetParryChance() return Stub.stats.parry end
function GetBlockChance() return Stub.stats.block end

--[==[ **Crit and hit are absent by default, because they are absent in 1.12.**

     The character sheet has never shown either, and which spelling a fork
     back-ports -- `GetCritChance`, `GetMeleeCritChance`, `GetHitModifier` -- is
     the thing the module probes for. A stub that always had them would agree
     with a module that assumed one and drew a blank row on every client that
     spells it differently. ]==]
function Stub.SetCritApi(present, crit, hit)
    if not present then
        GetCritChance = nil
        GetHitModifier = nil
        GetRangedCritChance = nil
        return
    end

    GetCritChance = function() return crit or 22.96 end
    GetHitModifier = function() return hit or 9 end
    GetRangedCritChance = function() return crit or 22.96 end
end

Stub.SetCritApi(false)

function UnitStat(unit, index)
    local value = Stub.player.stats[index] or 0
    return value, value, 0, 0
end

function GetTalentInfo(tab, index)
    local rank = Stub.player.talents[tab .. ":" .. index] or 0
    return "Talent", "", 1, 1, rank, 5
end

--[[ Three trees, and as many talents in each as the fixture has put ranks
     in -- a walk over the trees visits every talent that has a rank and can
     stop there. ]]--
TOOLTIP_TALENT_NEXT_RANK = "Next rank:"

function GetNumTalentTabs()
    return 3
end

function GetNumTalents(tab)
    local most = 0
    for key in pairs(Stub.player.talents) do
        local _, _, t, i = string.find(key, "^(%d+):(%d+)$")
        if tonumber(t) == tab and tonumber(i) > most then most = tonumber(i) end
    end
    return most
end

function GetSpellTabInfo(tab)
    return "Class", "", 0, Stub.player.spellCount or 0
end

function GetSpellTexture(index, bookType)
    return Stub.player.spellbook[index]
end

--[[ Spell names by book index. Separate from `spellbook`, which holds textures:
     the druid mana scrape finds Bear Form by icon because the name is localised,
     while the distance readout has to match a name because Auto Shot and Shoot
     Gun share no icon distinction it can use.

     This is how a plain client tells a hunter's Auto Shot from a warrior's Shoot
     Gun -- the two fire the same gun to different distances, and getting it wrong
     told a warrior a forty-yard target was in range. ]]--
function GetSpellName(index, bookType)
    local name = Stub.player.spellNames and Stub.player.spellNames[index]
    if not name then return nil end
    return name, ""
end

function GetLocale() return Stub.locale or "enUS" end

--[[ Whether the target can be attacked. Hostile by default, because that is what
     a HUD is looking at almost all of the time -- and because
     CheckInteractDistance answers nothing about such a unit, which is the whole
     reason this matters. ]]--
--[==[ **It answers about the unit it was asked about, which it did not.**

     This ignored both arguments and reported on the *target* whoever it was
     asked about -- so `UnitCanAttack("player", "party1")` returned a fact about
     somebody else entirely, and any reader passing a unit of its own got the
     target's hostility wearing that unit's name.

     Two real callers pass something other than `"target"`: the tooltip asks
     about whatever unit it is decorating, and the self-test asks the question
     **backwards** (`"target", "player"`) to find out whether the target can
     attack *you*. Neither could be wrong against a stub that answers the same
     thing to everything.

     Yourself and your own group are never attackable, which needs no fixture and
     is the half a flattened answer got most obviously wrong. ]==]
function UnitCanAttack(attacker, unit)
    --[[ The backwards form asks whether the target can attack you, which is the
         same hostility with the arguments swapped. ]]--
    if attacker ~= "player" and unit == "player" then
        unit = attacker
    end

    if unit == "player" then return nil end

    if string.find(unit or "", "^party%d") or string.find(unit or "", "^raid%d") then
        return nil
    end

    if unit ~= "target" then
        --[[ Anything else is a mob until a fixture says otherwise. ]]--
        return 1
    end

    if not Stub.player.hasTarget then return nil end
    if Stub.player.friendlyTarget then return nil end
    return 1
end

--[[ UnitXP SP3's line-of-sight check, which is a *third* client mod -- separate
     from SuperWoW and from Nampower, and not installed on the development
     machine. Off unless a test asks, like every other injected API. ]]--
function Stub.SetLineOfSight(present)
    Stub.losAvailable = present and true or false
end

--[[ A Nampower build extended with a line of sight query, the way this
     installation's GetUnitDistance was. Shaped to match it: one unit token, and
     a plain boolean so "cannot tell" and "blocked" stay distinguishable. ]]--
function Stub.SetNampowerSight(present)
    if not present then
        IsUnitInSight = nil
        return
    end

    IsUnitInSight = function(unit)
        if not unit or not UnitExists(unit) then return nil end
        return Stub.player.inSight ~= false
    end
end

--[[ CheckInteractDistance's real thresholds: 1 inspect ~28yd, 2 trade ~11.1yd,
     3 duel ~9.9yd, 4 follow ~28yd.

     It answers nil, never false, and answers nil for a unit that cannot be
     interacted with at all -- which a hostile mob cannot. Stub.interactRefuses
     models exactly that case, because treating it as an error rather than as
     "too far" is the mistake the range module is written to avoid. ]]--
local INTERACT_YARDS = { 28, 11.11, 9.9, 28 }

function CheckInteractDistance(unit, index)
    --[==[ **A group member's distance is not the target's.** Every answer here
         was about the target -- no target, no answer -- so `raid7` was "too far"
         whenever nothing was selected and "as far as the target" otherwise. A
         member who exists is in range unless a test has sent them away. ]==]
    if type(unit) == "string" and (string.find(unit, "^party%d")
            or string.find(unit, "^raid%d")) and UnitExists(unit) then
        if Stub.unitFar and Stub.unitFar[unit] then return nil end
        return 1
    end

    if not Stub.player.hasTarget then return nil end
    if Stub.interactRefuses then return nil end

    --[[ **Hostile units answer nil at every index**, because duelling, trading
         and inspecting are all things you do to a player who is not trying to
         kill you. Modelled rather than glossed over: without it the stub happily
         measured range to a mob, which is the one target a HUD spends its whole
         life pointed at -- and the addon shipped a distance readout that only
         worked on friendly targets while the suite stayed green. ]]--
    if UnitCanAttack("player", unit) then return nil end

    --[==[ **A unit that is simply far away**, which this could not say about any
         unit but the target: every question about `raid7` was answered with the
         target's distance, so a raid member out of healing range was a state no
         test could put a frame in -- and the fade that colours exactly that
         state broke without a failure. ]==]
    if Stub.unitFar and Stub.unitFar[unit] then return nil end

    local limit = INTERACT_YARDS[index]
    if limit and (Stub.player.targetDistance or 0) <= limit then return 1 end
    return nil
end

--[[ Which units are out of interaction range, by token. Cleared with the rest
     of the group state. ]]--
Stub.unitFar = {}

-- 1 in range, 0 out of range, nil when the slot is not range checked
function IsActionInRange(slot)
    if Stub.actionRange == nil then return nil end
    return Stub.actionRange
end

--[[ What is on the bars: slot -> the name its tooltip shows. Empty by default,
     because most players do not keep their auto-attack on a bar and the addon
     has to cope with not finding it. ]]--
Stub.actionBar = {}

function HasAction(slot)
    return Stub.actionBar[slot] and 1 or nil
end

function UseAction(slot, checkCursor, onSelf)
    Stub.lastAction = slot
end

--[[ **Getting off a mount, which 1.12 does by cancelling a buff.**

     There is no `Dismount()` -- that is a 2.0 call -- and no id or reliable name
     on a 1.12 buff either, so a mount is identified by its icon and removed by
     its index. Both halves are modelled: `CancelPlayerBuff` really removes the
     texture from the list, so a test can watch somebody actually get off rather
     than only watch the call happen.

     `IsMounted` is deliberately **absent**. It exists on some private-server
     clients and not on a plain 1.12 one, and the addon has to work either way --
     a stub that always provided it would leave the texture path, which is what
     most people will actually run, never once executed. A test that wants the
     other branch defines it. ]]--
function CancelPlayerBuff(index)
    --[[ By the handle, which is what the client wants and what the addon now
         passes. A position arriving here cancels nothing, which is the shape of
         the bug this modelling exists to catch. ]]--
    local position = buffPosition(index)
    if not position then return end

    table.remove(Stub.player.buffs, position + 1)
    Stub.cancelledBuff = index
end

--[[ What an action slot's icon is, which is the only way to tell "this press is
     the mount itself" from "this press is a spell". They are the same art. ]]--
function GetActionTexture(slot)
    local action = Stub.actionBar[slot]
    if type(action) == "table" then return action.texture end
    return nil
end

--[[ Macros, and the equipped item art a macro icon can be mistaken for.

     A slot in `Stub.actionBar` may carry `macro = "name"`; the macros themselves
     live in `Stub.macros` as `{ name = ..., texture = ... }`. That split is the
     client's: an action slot knows the macro's *name* and nothing else, and the
     name has to be looked up to reach the icon. ]]--
Stub.macros = {}

function GetActionText(slot)
    local action = Stub.actionBar[slot]
    if type(action) == "table" then return action.macro end
    return nil
end

function GetMacroIndexByName(name)
    for i = 1, table.getn(Stub.macros) do
        if Stub.macros[i].name == name then return i end
    end

    --[[ Zero rather than nil, which is what the client answers and what callers
         therefore have to guard against. ]]--
    return 0
end

function GetMacroInfo(index)
    local macro = Stub.macros[index]
    if not macro then return nil end
    return macro.name, macro.texture, macro.body
end

--[[ Nineteen equipment slots; a test names only the ones it cares about. ]]--
Stub.equipped = {}

function GetInventoryItemTexture(unit, slot)
    return Stub.equipped[slot]
end

Stub.castCalls = {}

function CastSpellByName(name, onSelf)
    table.insert(Stub.castCalls, name)
end

--[[ **Auto-attack, which toggles.** `AttackTarget` starts a swing if you are not
     swinging and stops one if you are -- there is no separate stop call in 1.12,
     which is why cancelling an unwanted attack means calling the same function
     again. Modelled as a toggle for that reason: a stub with separate start and
     stop would let the cancel be written the way it cannot be. ]]--
Stub.attacking = false
Stub.attackCalls = 0

function AttackTarget()
    Stub.attacking = not Stub.attacking
    Stub.attackCalls = Stub.attackCalls + 1
end

--[[ Client-mod APIs.

     None of these come from an addon: they are injected into the Lua state by a
     DLL, so on a plain install they are simply absent and there is no version or
     flag to read. Tests put them in and take them out again to drive the
     distance module down each of its backends.

     Modelling them as *togglable* rather than always-present is the point. The
     addon spent three versions believing UnitXP was on the development machine
     because another addon referenced it, and every reading came from the
     coarsest backend as a result. A stub where the good path is always available
     would reproduce that mistake rather than catch it. ]]--

-- UnitXP_SP3's command dispatcher.
function Stub.SetUnitXP(present)
    if not present then
        --[[ The stock experience API already owns this global. Handed a command
             name it reads it as a unit token, finds no such unit, and **raises a
             Lua error** -- verified in game, and this is its exact wording:

               UnitXP('inSight','player','player'):
                   ERROR Unknown unit name: inSight
               UnitXP('player'): 112473 (number)

             Both halves matter. The error is why a bare `pcall` probe cannot be
             fooled into a false positive here; the number is why a probe that
             concludes "stock" from a *successful* call is the one that can. ]]--
        UnitXP = function(unit)
            if unit ~= "player" then error("Unknown unit name: " .. tostring(unit)) end
            return Stub.player.xp or 0
        end
        return
    end

    UnitXP = function(command, a, b)
        if command == "nop" then return true end
        if command == "distanceBetween" then
            --[[ **Two fixtures, one dispatcher.** The distance tests place units
                 in the world and expect the maths to run; everything else sets a
                 single `targetDistance` and expects to be told it. Positions win
                 when both units have one, because a test that placed them meant
                 it. ]]--
            local pa = Stub.positions and Stub.positions[a]
            local pb = Stub.positions and Stub.positions[b]

            if pa and pb then
                local dx, dy = pb[1] - pa[1], pb[2] - pa[2]
                local dz = (pb[3] or 0) - (pa[3] or 0)
                return math.sqrt((dx * dx) + (dy * dy) + (dz * dz))
            end

            if a == b or b == "player" then return 0 end
            return Stub.player.targetDistance or 0
        end

        --[[ SP3's line-of-sight check. A separate opt-in from UnitXP itself,
             because a client can have the distance query without it -- and
             returning a number rather than a boolean is how the addon tells
             "cannot tell" from "blocked". ]]--
        if command == "inSight" then
            if not Stub.losAvailable then return 0 end
            return Stub.player.inSight ~= false
        end

        --[[ What an unrecognised command does, and the answer is "it depends on
             the build" -- which is the whole reason the addon must not probe
             here.

             SP3 is a *compatible replacement* for a global vanilla already owns,
             so a build that passes unit tokens through to the function it
             displaced is entirely reasonable. `Stub.unitXPPassthrough` models
             that build. A probe that concluded "this is the stock API" from a
             number came back saw one on this client and switched a working
             extension off. ]]--
        if Stub.unitXPPassthrough and command == "player" then
            return Stub.player.xp or 0
        end

        return nil
    end
end

--[[ World coordinates. The player sits at the origin and the target is placed
     along one axis, so the module's own three-dimensional maths has to run to
     get the distance back out -- a stub that returned the answer directly would
     not exercise it. ]]--
--[[ Set by a test to place named units in the world. Cleared with the rest of
     the group state, because a position that outlives the unit it belongs to is
     a unit standing where nobody is. ]]--
--[==[ **`SpellInfo`, which is SuperWoW's and not vanilla's.**

     A spell id to a name and rank. `UNIT_CASTEVENT` reports the spell as an id,
     so without this there is a cast with no label -- and the label is the part
     of a nameplate cast bar that carries the meaning. ]==]
Stub.spellNames = {}

function SpellInfo(id)
    local name = Stub.spellNames[id]
    if not name then return nil end
    return name, "Rank 1"
end

Stub.positions = nil

function Stub.SetUnitPosition(present)
    if not present then
        UnitPosition = nil
        return
    end

    --[[ Hostile targets answer nil here. This was a conservative assumption for
         several versions and is now a **verified fact**, from `/eq rangedebug`
         against a hostile NPC on a SuperWoW client:

           UnitPosition player: -4623.379, 501.620, 36.766
           UnitPosition target: nil (nil, nil, nil)
           UnitPosition GUID:   nil (nil, nil, nil)

         Note the third line. Passing the unit's GUID rather than its token does
         **not** get round it, which was the obvious workaround and is now ruled
         out rather than untried. ]]--
    UnitPosition = function(unit)
        --[==[ **Real world coordinates for named units, when a test sets them.**

             The range module only ever takes a magnitude from this, and a
             magnitude does not care which way the axes point. Anything drawing a
             *direction* from it does, so a test has to be able to put a unit at
             a known point rather than at a known distance. ]==]
        if Stub.positions and Stub.positions[unit] then
            local p = Stub.positions[unit]
            return p[1], p[2], p[3] or 0
        end

        if unit == "player" or unit == "0xPLAYER" then return 0, 0, 0 end
        if not Stub.player.hasTarget then return nil end
        if unit == "target" and not Stub.player.friendlyTarget then return nil end
        if unit == "0xTARGET" then return nil end
        return Stub.player.targetDistance or 0, 0, 0
    end
end

--[[ Nampower: the engine's own range answers.

     Stub.spellRanges maps a spell name to { min, max }, so a test can give a
     hunter a dead zone and a wand none. IsSpellInRange returns the engine's
     boolean, computed from those same numbers, so the two can never disagree in
     a way the real client would not. ]]--
Stub.spellRanges = {}

--[[ Spells addressed by **id**, which is a different capability from addressing
     them by name and the whole basis of the range ladder.

     Verified in game. Asking by name for a spell outside your own book fails:

       Unable to determine spell id from spell name, possibly because it isn't
       in your spell book.  Try IsSpellInRange(SPELL_ID) instead

     Asking by id does not. A rogue got clean 0/1 answers for Fireball, Holy
     Light, Hammer of Justice and Hunter's Mark -- so the spellbook limit is on
     the name lookup, not on the range check.

     Two further rules come from the same run, and the ladder depends on both:

       * targeting restrictions are **not** applied. Holy Light, a heal,
         answered about a hostile mob. Any spell is therefore usable as a plain
         distance threshold regardless of who it could really be cast on.
       * the ranges are the classic vanilla numbers. Turtle has retuned none of
         the nine that were checked.

     These are the ids and ranges as the client reported them.

     Modelled the way the client stores it, in **two** tables: a short list of
     distinct min/max pairs, and spells that point at a row of it by index. That
     indirection is the whole basis of `/eq rangescan` -- reading the rows
     answers "which bands could this client measure" without walking a single
     spell -- so a stub that collapsed the two into one could not test it. ]]--
--[[ **The real table**, as `/eq rangescan` read it out of the client. Keyed by
     index and full of gaps, exactly as found -- index 1 is absent, and the rows
     jump from 15 to 34 and from 38 to 54. An array would have hidden that, and
     the gaps are the reason the scan walks a fixed span rather than counting.

     Two things here are worth more than the rest of the table. There **is** a
     zero-minimum 25 row, which was the open question and which closes the worst
     gap in the ladder. And there is a 0-50000 row, which is why a ladder without
     an upper cap ends up with a top band reading "100-50000y". ]]--
Stub.rangeRows = {
    [2]  = { 0, 5 },     [3]  = { 0, 20 },    [4]  = { 0, 30 },
    [5]  = { 0, 40 },    [6]  = { 0, 100 },   [7]  = { 0, 10 },
    [8]  = { 10, 20 },   [9]  = { 10, 30 },   [10] = { 10, 40 },
    [11] = { 0, 15 },    [12] = { 0, 5 },     [13] = { 0, 50000 },
    [14] = { 0, 60 },    [15] = { 0, 36 },    [34] = { 0, 25 },
    [35] = { 0, 35 },    [36] = { 0, 45 },    [37] = { 0, 50 },
    [38] = { 10, 25 },   [54] = { 5, 30 },
}

--[[ Spell ids, and every range here is the client's own. The first eight were
     guessed and confirmed; the rest the scan found by name.

     Several are not player spells. That is the point rather than a compromise:
     nothing is ever cast, the range check is arithmetic on a DBC row, and a
     spell nobody can cast measures a distance exactly as well as one anybody
     can. ]]--
Stub.spellById = {
    [2974]  = { 2,  "Wing Clip" },
    [853]   = { 7,  "Hammer of Justice" },
    [19503] = { 11, "Scatter Shot" },
    [5782]  = { 3,  "Fear" },
    [1906]  = { 34, "Debilitating Charge" },
    [116]   = { 4,  "Frostbolt" },
    [133]   = { 35, "Fireball" },
    [635]   = { 5,  "Holy Light" },
    [785]   = { 36, "True Fulfillment" },
    [15746] = { 37, "Disturb Rookery Egg" },
    [530]   = { 14, "Charm (Possess)" },
    [1130]  = { 6,  "Hunter's Mark" },

    -- absurdly long, and the reason the ladder caps itself
    [126]   = { 13, "Eye of Kilrogg" },

    --[[ A dead zone, kept so the ladder and the scan both have to prove they
         exclude it. Charge reported 8-25 when read directly, and no 8-25 row
         appeared in the scan -- so rows exist above the span it walked, which is
         why that span was widened. Modelled on the 10-25 row it did find. ]]--
    [100]   = { 38, "Charge" },
}

-- min and max for a spell id, or nil
function Stub.SpellIdRange(id)
    local spell = Stub.spellById[id]
    if not spell then return nil end

    local row = Stub.rangeRows[spell[1]]
    return row[1], row[2]
end

function Stub.SetNampower(present)
    if not present then
        GetSpellIdForName = nil
        GetSpellRecField = nil
        GetSpellRangeData = nil
        IsSpellInRange = nil
        return
    end

    --[[ Name-resolved spells get range-row indices well clear of the real rows
         above, because both live in the same index space on the client and a
         collision here would make the stub answer one lookup with the other. ]]--
    local ids, names = {}, {}
    local next = 101

    GetSpellIdForName = function(name)
        if not Stub.spellRanges[name] then return nil end
        if not ids[name] then
            ids[name] = next
            names[next] = name
            next = next + 1
        end
        return ids[name]
    end

    -- the range index is the spell id here; the indirection exists on the real
    -- client and is modelled only so the addon has to make both calls
    GetSpellRecField = function(id, field)
        local fixed = Stub.spellById[id]
        if fixed then
            if field == "name" then return fixed[2] end
            if field == "rangeIndex" then return fixed[1] end
            return nil
        end

        if field ~= "rangeIndex" then return nil end

        --[[ An id nobody has heard of resolves to nothing. Answering with the id
             itself made every number in the game look like a valid spell, which
             is the one thing a scan over thirty thousand ids must not see. ]]--
        if not names[id] then return nil end
        return id
    end

    GetSpellRangeData = function(index)
        local row = Stub.rangeRows[index]
        if row then return row[1], row[2], 0 end

        local name = names[index]
        if not name then return nil end
        local r = Stub.spellRanges[name]
        return r[1], r[2], 0, name
    end

    --[[ Takes a spell **name or id**, as Nampower's does. That matters: the
         addon has only a name unless the range-data APIs are also present, and a
         stub that insisted on an id made the whole spell backend look broken
         while the real one would have worked. ]]--
    IsSpellInRange = function(spell, unit)
        --[[ A fixed id first. No spellbook check and no targeting check: both
             were verified absent in game, and the ladder is built on their
             absence. ]]--
        local fixedMin, fixedMax = Stub.SpellIdRange(spell)
        if fixedMin then
            if not Stub.player.hasTarget then return -1 end

            local d = Stub.player.targetDistance or 0
            if d < fixedMin or d > fixedMax then return 0 end
            return 1
        end

        local name = names[spell]
        if not name and Stub.spellRanges[spell] then name = spell end
        if not name then return nil end
        if not Stub.player.hasTarget then return -1 end

        local r = Stub.spellRanges[name]
        local d = Stub.player.targetDistance or 0
        if d < r[1] then return 0 end
        if d > r[2] then return 0 end
        return 1
    end
end

-- Optional native extension proposed for Nampower. Stock 4.6.2 does not expose
-- this function even though its object manager already has both unit positions.
function Stub.SetNampowerDistance(present)
    if not present then
        GetUnitDistance = nil
        return
    end

    GetUnitDistance = function(unit)
        if unit == "player" or unit == "0xPLAYER" then return 0 end
        if not Stub.player.hasTarget then return nil end
        return Stub.player.targetDistance or 0
    end
end

-- ---------------------------------------------------------------------------
-- inventory
-- ---------------------------------------------------------------------------

--[[ What is worn, by slot number. Only the ranged slot (18) is populated, and
     only as { itemId, subtype } -- the distance module reads nothing else, and a
     fuller inventory model would be scenery. ]]--
Stub.equipped = {}

function GetInventoryItemLink(unit, slot)
    local item = Stub.equipped[slot]
    if not item then return nil end
    return "|cffffffff|Hitem:" .. item[1] .. ":0:0:0|h[Test Item]|h|r"
end

--[==[ **Every slot, because answering nought for eighteen of them made any
     slot mapping untestable.**

     This knew `RangedSlot` and returned `0` for everything else, so code asking
     for the main hand and code asking for the tabard got the same answer and
     nothing could tell a correct mapping from a wrong one. The numbers are the
     client's own and are the order the paper doll is built in. ]==]
local INVENTORY_SLOTS = {
    AmmoSlot = 0,
    HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4,
    ChestSlot = 5, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8,
    WristSlot = 9, HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12,
    Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15,
    MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18,
    TabardSlot = 19,
}

function GetInventorySlotInfo(name)
    return INVENTORY_SLOTS[name] or 0
end

--[[ **Item quality colours, which the client owns and a server may extend.**

     Returned as r, g, b and the `|cff……` prefix, in that order, because the
     fourth is the one an addon building a link actually wants and the first
     three are what a texture wants. Real here because the item-link encoding
     recovers an item's rarity from its colour when the item is not in the local
     cache -- there is nothing else left to recover it from. ]]--
local QUALITY = {
    [0] = { 0.62, 0.62, 0.62, "|cff9d9d9d" },
    [1] = { 1.00, 1.00, 1.00, "|cffffffff" },
    [2] = { 0.12, 1.00, 0.00, "|cff1eff00" },
    [3] = { 0.00, 0.44, 0.87, "|cff0070dd" },
    [4] = { 0.64, 0.21, 0.93, "|cffa335ee" },
    [5] = { 1.00, 0.50, 0.00, "|cffff8000" },
    [6] = { 0.90, 0.80, 0.50, "|cffe6cc80" },
}

function GetItemQualityColor(rarity)
    local q = QUALITY[rarity] or QUALITY[1]
    return q[1], q[2], q[3], q[4]
end

--[[ **The item cache**, which is what `GetItemInfo` is really asking. An item
     the client has never seen answers nil, and that path matters as much as the
     hit: a link to something you have not encountered still has to arrive
     readable. Empty by default so the miss is what a test gets without asking
     for it. ]]--
Stub.items = {}

--[[ GetItemInfo's sixth return is the subtype, which is how the distance module
     tells a bow from a wand from a relic. The other returns are plausible
     filler; nothing reads them. ]]--

--[[ **The client's own item categories**, which is where the item database's
     type filter gets its list.

     `GetAuctionItemClasses()` returns every top-level type as a vararg, and
     `GetAuctionItemSubClasses(index)` the subtypes of one of them. They are the
     auction house's categories, and they are the *same localised strings*
     `GetItemInfo` answers for type and subtype -- which is what makes them
     usable as a filter rather than merely as a menu. There is no numeric class
     id on 1.12; the string is the identity.

     Modelled with the real 1.12 order, because the index into
     `GetAuctionItemSubClasses` is positional and an addon that assumed Weapon
     was first would be right here and wrong in game. Trimmed to the categories
     the tests need rather than all eleven. ]]--
Stub.itemClasses = {
    { name = "Weapon", subs = { "One-Handed Axes", "Two-Handed Axes", "Bows",
        "Guns", "One-Handed Maces", "Two-Handed Maces", "Polearms",
        "One-Handed Swords", "Two-Handed Swords", "Staves", "Fist Weapons",
        "Daggers", "Thrown", "Crossbows", "Wands", "Fishing Poles" } },
    { name = "Armor", subs = { "Miscellaneous", "Cloth", "Leather", "Mail",
        "Plate", "Shields", "Librams", "Idols", "Totems" } },
    { name = "Container", subs = { "Bag", "Soul Bag", "Herb Bag",
        "Enchanting Bag", "Engineering Bag" } },
    { name = "Consumable", subs = { "Consumable", "Potion", "Elixir", "Flask",
        "Bandage", "Item Enhancement", "Scroll", "Food & Drink", "Other" } },
    { name = "Trade Goods", subs = { "Trade Goods", "Parts", "Explosives",
        "Devices", "Cloth", "Leather", "Metal & Stone", "Meat", "Herb",
        "Elemental", "Other", "Enchanting", "Materials" } },
    { name = "Recipe", subs = { "Book", "Leatherworking", "Tailoring",
        "Engineering", "Blacksmithing", "Cooking", "Alchemy", "First Aid",
        "Enchanting", "Fishing" } },
}


--[[ **aux-addon, as much of it as this addon actually talks to.**

     aux ships its own package system: a global `require` that answers module
     tables by name. `pricing.lua` has read its price history through that since
     it was written and had no coverage at all, and the auction module skins and
     scans through it too.

     Modelled rather than mocked per test, because the shape is the interesting
     part: `require` answering nil for a module that is not there is the normal
     state on an install without aux, and every caller has to survive it. ]]--
Stub.auxModules = {}

Stub.auxModules["aux.gui"] = {
    font = [[Fonts\ARIALN.TTF]],
    font_size = { small = 13, medium = 15, large = 18 },
}

--[[ The scanner. `start` records what it was asked for rather than doing
     anything, so a test can ask whether a sweep was requested and what shape
     the query had -- which is the whole of what ECO's side is responsible
     for. ]]--
Stub.auxScans = {}

Stub.auxModules["aux.core.scan"] = {
    start = function(params)
        table.insert(Stub.auxScans, params)
        return table.getn(Stub.auxScans)
    end,
    abort = function() end,
    stop = function() end,
}

Stub.auxModules["aux.core.history"] = {
    data_points = function(key) return Stub.auxHistory and Stub.auxHistory[key] end,
    value = function(key) return Stub.auxValue and Stub.auxValue[key] end,
    market_value = function(key) return Stub.auxToday and Stub.auxToday[key] end,
}

Stub.auxModules["aux.util.info"] = {
    item_id = function(name) return Stub.itemIds and Stub.itemIds[name] end,
    merchant_info = function(id) return Stub.vendorSell and Stub.vendorSell[id] end,
}

--[[ aux's saved searches. Favourites are stored as *searches* -- a filter
     string and the prettified form shown in the list -- not as items, which is
     why one favourite can name a category and have no single price. ]]--
Stub.auxFavourites = {}

--[==[ **The search tab exports nothing, and that was the whole bug.**

     This used to be listed in `Stub.auxModules`, which made `require` hand it
     back with `favorite_searches` and `add_favorite` on it. aux does not work
     that way. Its package system gives each file an environment and a separate
     exports table, and only `M.name = value` puts a name in exports -- which is
     what `require` returns. `tabs/search/` never writes to `M`, so every name
     ECO wanted came back nil.

     Modelled here as aux really is: `require 'aux.tabs.search'` answers an
     interface with nothing on it, and the names live in an environment that
     only a function defined in that file carries. The harness agreed with the
     broken code before this, which is why a green suite said nothing about a
     feature that had not worked in the game for weeks. ]==]
Stub.auxLocals = {}

Stub.auxLocals["aux.tabs.search"] = {
    favorite_searches = Stub.auxFavourites,

    add_favorite = function(filterString)
        table.insert(Stub.auxFavourites, 1, {
            filter_string = filterString,
            prettified = filterString,
        })
    end,

    update_search_listings = function() end,

    --[[ The listing frame the favourites are drawn into. `SetColInfo` and
         `SetData` are set per instance by aux's `listing.new`, which is what
         makes wrapping them from outside possible at all. ]]--
    favorite_searches_listing = {
        colInfo = nil,
        rows = nil,

        SetColInfo = function(self, colInfo) self.colInfo = colInfo end,
        SetData = function(self, rows) self.rows = rows end,
    },
}

--[[ aux's own root module. It locks itself while a bid is outstanding -- from
     `PlaceAuctionBid` until the server confirms or five seconds pass -- and
     exposes the fact, which is the only honest way to ask "is the player in the
     middle of buying something". ]]--
Stub.auxBidding = false

Stub.auxModules["aux"] = {
    bid_in_progress = function() return Stub.auxBidding end,
}

--[[ Present only when aux is. `Stub.auxLoaded` false makes `require` answer
     nothing, which is how an install without aux looks from the inside. ]]--
Stub.auxLoaded = true

--[==[ **aux's package system, modelled rather than mocked.**

     This was a lookup table, and the shape it got wrong is the whole of two
     bugs. aux gives each file an *environment* and a separate *exports* table.
     `module 'name'` swaps the file's environment, so a plain `foo = 1` lands
     only in the environment. `M.foo = 1` goes through a proxy that writes to
     both, and exports is all `require` hands back.

     Three consequences, all of which ECO was on the wrong side of:

     `require` cannot fail. Asked for a name it has never heard of it *creates*
     the module and answers an empty interface, so a caller that checks it got
     a table has learned only that something defined `require`.

     A name the module never exported is not reachable through `require` at all.
     `aux.tabs.search` exports nothing whatsoever.

     And the interface's `__newindex` discards writes. `scan.start = wrapper`
     silently does nothing while `scan.start` still reads back fine -- so a
     wrapper can appear to install and never once run.

     The way to write back is aux's own `M`, which is in the environment. Every
     function the module exported carries that environment, so one export is
     enough of a handle to find it.

     `Stub.auxLoaded` false stands for aux not being installed, where `require`
     is not a function at all. Modelled as an error because ECO reaches it
     through `pcall` either way. ]==]
local auxEnvironments, auxInterfaces = {}, {}

local function auxCreate(name)
    local exports = Stub.auxModules[name] or {}
    local environment = setmetatable({}, { __index = getfenv(0) })

    environment.M = setmetatable({}, {
        __metatable = false,
        __newindex = function(_, k, v)
            environment[k], exports[k] = v, v
        end,
    })

    --[[ What the module defined and never exported, then what it did export --
         which is in both places, exactly as writing through `M` would leave
         it. ]]--
    for k, v in pairs(Stub.auxLocals[name] or {}) do environment[k] = v end
    for k, v in pairs(exports) do environment[k] = v end

    --[[ **Every function the module owns runs in that environment**, which is
         what makes `getfenv` on an exported function the way back in. Without
         this the handles are all real and every one of them leads to the
         harness's own globals instead. ]]--
    for _, v in pairs(environment) do
        if type(v) == "function" then setfenv(v, environment) end
    end

    auxEnvironments[name] = environment
    auxInterfaces[name] = setmetatable({}, {
        __metatable = false,
        __index = exports,
        __newindex = function() end,
    })

    --[==[ **aux as it was before any addon reached into it.**

         aux is another addon and a login reloads it too, so its modules come
         back holding aux's own functions. Here they are plain Lua tables that
         outlive a boot, so ECO's wrapper on `scan.start` was still installed
         when the next login went to install one -- and the next login's wrapper
         then wrapped the previous login's, which is a chain that grows by one
         per boot and calls a module that no longer exists.

         Taken here rather than at the end of the file because a module is built
         the first time somebody asks for it, which can be in the middle of a
         boot. At this point it is aux's and nothing else has seen it. ]==]
    Stub.auxPristine = Stub.auxPristine or {}

    local envWas, exportsWas = {}, {}
    for k, v in pairs(environment) do envWas[k] = v end
    for k, v in pairs(exports) do exportsWas[k] = v end

    Stub.auxPristine[name] = {
        env = environment, envWas = envWas,
        exports = exports, exportsWas = exportsWas,
    }
end

--[[ Put every aux module back to that. Contents rather than fresh tables: the
     environment is reached by `getfenv` on a function aux exported and the
     interface indexes the exports table, so both identities have to hold. ]]--
function Stub.ResetAux()
    for _, snap in pairs(Stub.auxPristine or {}) do
        for k in pairs(snap.env) do
            if snap.envWas[k] == nil then snap.env[k] = nil end
        end
        for k, v in pairs(snap.envWas) do snap.env[k] = v end

        for k in pairs(snap.exports) do
            if snap.exportsWas[k] == nil then snap.exports[k] = nil end
        end
        for k, v in pairs(snap.exportsWas) do snap.exports[k] = v end
    end
end

function require(name)
    if not Stub.auxLoaded then error("module not found: " .. tostring(name)) end

    if not auxInterfaces[name] then auxCreate(name) end
    return auxInterfaces[name]
end

--[[ aux builds its modules as its files load, not when somebody asks. The
     search tab has to exist before the frame below can carry its
     environment. ]]--
auxCreate("aux.tabs.search")
Stub.auxSearchEnv = auxEnvironments["aux.tabs.search"]

--[[ The client's auction window. **aux hides this the moment the auction house
     opens** and draws its own in front of it, which is why asking whether it is
     shown answers "no" for exactly as long as the house is open. ]]--
AuctionFrame = CreateFrame("Frame", "AuctionFrame", UIParent)
AuctionFrame:Hide()

--[==[ **aux's own window, and the one way into its search tab.**

     aux names this frame -- it has to, to put it in `UISpecialFrames` -- and
     every tab hangs a root frame off it. The search tab's root carries an
     `OnUpdate` defined inside that tab's file, so `getfenv` on that handler is
     the module: the names aux never exported, readable and writable.

     Modelled with the environment really attached to a script rather than
     stored somewhere convenient, because the reaching is the part under
     test. ]==]
aux_frame = CreateFrame("Frame", "aux_frame", UIParent)
aux_frame:Hide()

Stub.auxSearchFrame = CreateFrame("Frame", nil, aux_frame)

do
    local onUpdate = function() end
    setfenv(onUpdate, Stub.auxSearchEnv)
    Stub.auxSearchFrame:SetScript("OnUpdate", onUpdate)
end
function GetAuctionItemClasses()
    local out = {}
    for i = 1, table.getn(Stub.itemClasses) do
        table.insert(out, Stub.itemClasses[i].name)
    end
    return unpack(out)
end

function GetAuctionItemSubClasses(classIndex)
    local class = Stub.itemClasses[tonumber(classIndex) or 0]
    if not class then return end
    return unpack(class.subs)
end
--[==[ **`GetItemInfo` takes a name, and this only ever took an id.**

     1.12 accepts an id, an item string, a link *or* a plain name, and answers
     for anything the client has cached. Modelling only the first three made the
     name path untestable -- and the name path is the one an addon reaches for
     when all it has is something the player typed.

     Cached items only, which is the client's own limit and worth keeping: an
     item nobody has seen is not in the cache and `GetItemInfo` answers nothing
     about it. ]==]
--[==[ **The client's own name for the Quest item class.**

     The auction house builds its Quest category from this, which is why an
     addon that wants to know whether something is a quest item reads it from
     here rather than writing "Quest" out: the same code then works in every
     locale.

     Modelled because the alternative is a filter that is only ever exercised
     through its English fallback, which is the half least likely to be
     wrong. ]==]
AUCTION_CATEGORY_QUEST = "Quest"

function GetItemInfo(item)
    local id = tonumber(item)
    if not id then
        local _, _, found = string.find(tostring(item), "item:(%d+)")
        id = tonumber(found)
    end

    if not id then
        for known, entry in pairs(Stub.items) do
            if entry and entry.name == item then id = known end
        end
    end

    if not id then return nil end

    for slot, entry in pairs(Stub.equipped) do
        if entry[1] == id then
            return "Test Item", "|Hitem:" .. id .. "|h", 2, 60, "Weapon", entry[2],
                    1, "Ranged", nil
        end
    end

    --[[ Anything the cache has been told about. Separate from the equipped list
         because an item you have seen in a link is not an item you are
         wearing, and the link code only ever asks the first question. ]]--
    local known = Stub.items[id]

    --[[ **Type, subtype and slot come from the fixture now**, defaulting to the
         junk they were always hardcoded to.

         Hardcoding them meant every item in every test was Miscellaneous/Junk,
         so a filter that asked "is this a Weapon" got one answer for the whole
         catalogue and no test could tell a working type filter from a broken
         one. The item database's type filter was in fact reading four return
         values into eight names and getting nil for all of these -- which the
         suite could not see, because nil and "Miscellaneous" were equally
         indistinguishable from a filter that never rejected anything. ]]--
    --[==[ **Max stack size is the seventh return, and it was always one.**

         Hardcoded, so every item in every test was unstackable -- and a restack
         asking "is this pile full" got "yes" for the whole catalogue. Code that
         never checked and code that checked correctly were indistinguishable,
         which is how a stacker that would happily try to merge two full stacks
         of arrows passed. ]==]
    if known then
        return known.name, "item:" .. id .. ":0:0:0", known.rarity or 1,
                known.minLevel or 60,
                known.itemType or "Miscellaneous", known.subType or "Junk",
                known.maxStack or 1, known.equipLoc, nil
    end

    return nil
end

-- put a weapon of the given subtype in the ranged slot; nil empties it
function Stub.SetRanged(subtype)
    if not subtype then
        Stub.equipped[18] = nil
        return
    end
    Stub.equipped[18] = { 12345, subtype }
end

--[[ The group, as the threat meter reads it to colour a row by class. Raid
     first, party second and neither by default -- solo is the common case and
     the one where a class lookup has to come back empty rather than guessing. ]]--
Stub.group = {}

function GetNumRaidMembers() return Stub.raid and table.getn(Stub.group) or 0 end
function GetNumPartyMembers() return Stub.raid and 0 or table.getn(Stub.group) end

function Stub.SetGroup(members, raid)
    Stub.group = members or {}
    Stub.raid = raid and true or false
end

--[[ **The six rosters a name cache is built from**, each with its own argument
     order and none of them the same.

     This is the whole difficulty of PlayerNames and the reason it is four
     hundred lines upstream: `GetFriendInfo` answers name, level, class;
     `GetGuildRosterInfo` answers name, rank, rankIndex, level, class;
     `GetRaidRosterInfo` puts the subgroup third. Getting one of them wrong
     stores a rank where a class belongs and colours a name by a string no
     lookup will ever match -- silently, because an unknown class just means an
     uncoloured name, which is also what an empty roster looks like.

     So the orders are modelled exactly rather than made uniform. A stub that
     tidied them up would agree with a port that got them wrong.

     **And every one of them answers a localized class name, not a token.**
     `UnitClass` is the only call in the client that gives both; these give
     "Warrior" where the colour tables are keyed "WARRIOR". Modelled, because a
     stub that answered tokens agrees with a port that never converts -- and the
     symptom in game is an uncoloured name, which is exactly what a player
     nobody has heard of looks like. ]]--

--[[ Localized the way the client localizes it: first letter up, rest down. ]]--
local function localizedClass(token)
    if not token then return nil end
    return string.upper(string.sub(token, 1, 1)) .. string.lower(string.sub(token, 2))
end

Stub.friends = {}
Stub.guild = {}
Stub.whoResults = {}
Stub.raidRoster = {}

--[==[ **`AddFriend`, which was not modelled.**

     It appends and answers nothing -- there is no return value and no error for
     a name that does not exist, which is exactly why the command around it has
     to say what it did. Modelled as an append so the "already a friend" branch
     has something real to find. ]==]
function AddFriend(name)
    if not name or name == "" then return end
    table.insert(Stub.friends, { name = name, level = 0, class = "WARRIOR" })
end

function GetNumFriends() return table.getn(Stub.friends) end

function GetFriendInfo(i)
    local f = Stub.friends[i]
    if not f then return nil end
    return f.name, f.level, localizedClass(f.class)
end

function GetNumGuildMembers() return table.getn(Stub.guild) end

function GetGuildRosterInfo(i)
    local g = Stub.guild[i]
    if not g then return nil end
    return g.name, g.rank or "Member", 0, g.level, localizedClass(g.class)
end

--[[ **`/who`, which is a request and an answer separated by the server.**

     `SendWho` does not return anything; the answer arrives later as
     WHO_LIST_UPDATE, and until then `GetWhoInfo` still holds the *previous*
     query's results. Modelled that way -- the sent query is recorded and the
     results are not touched -- because a stub that filled them in immediately
     would let a scanner pass while assuming an answer it cannot have yet.

     `SetWhoToUI` is a global switch, not a per-query flag. Left at 1, the next
     `/who` a player types answers into a frame they are not looking at, so what
     the stub records is the *current* state rather than a list of calls. ]]--
Stub.whoSent = {}
Stub.whoToUI = 0

function SendWho(query) table.insert(Stub.whoSent, query) end
function SetWhoToUI(value) Stub.whoToUI = value end

--[[ The answer coming back: set the results, then fire the event the way the
     client fires it. One call, because the two always happen together and a test
     that did them separately would be testing the stub. ]]--
--[[ `total` is what the server matched, which may be far more than it sent.
     Defaults to the number of rows, which is the ordinary case: a query that fit
     inside the page matched exactly what came back. ]]--
function Stub.WhoAnswer(results, total)
    Stub.whoResults = results or {}
    Stub.whoTotal = total

    local previous = event
    event = "WHO_LIST_UPDATE"

    local addon = EquadisClassicOverhaul
    if addon and addon.modules and addon.modules.roster then
        addon.modules.roster:OnEvent()
    end

    event = previous
end

--[[ The Who list itself, because a scan must not run while somebody is reading
     it: the query redirects results away from the interface, so scanning under
     an open Friends frame empties the list being read. ]]--
FriendsFrame = CreateFrame("Frame", "FriendsFrame", nil)
FriendsFrame:Hide()

--[[ **Channels, and specifically being put in one you did not ask for.**

     `CHAT_MSG_CHANNEL_NOTICE` is how the client announces a join, and it hands
     the name over twice: `arg9` plain, `arg4` decorated with its list position
     and the zone -- "1. General - Stormwind". Modelled with both, because the
     decorated form is the one a naive comparison fails on, and a stub that only
     supplied the plain name would agree with code that never stripped it. ]]--
Stub.channelsLeft = {}

function LeaveChannelByName(name) table.insert(Stub.channelsLeft, name) end

--[[ **A chat window's channel list, and the two calls that change it.**

     The client keeps one per window and re-adds a channel to it on every join --
     which on a server that force-joins World is every login, forever, with
     nowhere that remembers you took it out again. That is the bug the chat
     module's removal memory exists for, so both halves are modelled: a real list
     per frame, and adds and removes that really change it. ]]--
--[[ **Which chat types reopen the edit box where you left it.**

     `sticky` is a *number* in 1.12, not a boolean. Assigning `true` works by
     accident and stops the moment anything compares it to 1, so the stub holds
     what the client holds. ]]--
--[[ **And the colours, which are 1.12's own defaults rather than white.**

     Every entry here used to be `{ 1, 1, 1 }`, which is a table that exists and
     says nothing: anything reading a channel's colour got white for all of them,
     so a test could not tell a whisper from a party line and neither could a
     reader of the test. The popup notifications take their text colour straight
     out of this table, and a stub that answered white everywhere would agree
     with code that read the wrong channel entirely.

     These are the client's shipped values. They are not constants -- Chat Colors
     lets the reader change any of them, which is the whole reason the addon
     copies rather than keeps a palette of its own -- so nothing should assert
     these *numbers*; assert that a popup matches `ChatTypeInfo[kind]`. ]]--
ChatTypeInfo = {}

local CHAT_COLORS = {
    SAY          = { 1.00, 1.00, 1.00 },
    WHISPER      = { 1.00, 0.50, 1.00 },
    YELL         = { 1.00, 0.25, 0.25 },
    PARTY        = { 0.67, 0.67, 1.00 },
    GUILD        = { 0.25, 1.00, 0.25 },
    OFFICER      = { 0.25, 0.75, 0.25 },
    RAID         = { 1.00, 0.50, 0.00 },
    RAID_WARNING = { 1.00, 0.28, 0.04 },
    BATTLEGROUND = { 1.00, 0.50, 0.00 },
    CHANNEL      = { 1.00, 0.75, 0.75 },
    EMOTE        = { 1.00, 0.50, 0.25 },
}

for kind, c in pairs(CHAT_COLORS) do
    ChatTypeInfo[kind] = { r = c[1], g = c[2], b = c[3], sticky = 0 }
end

--[[ Numbered channels carry their own colours, which is why General and Trade
     do not look alike. Keyed `CHANNEL1`..`CHANNEL10`, as the client keys them. ]]--
for i = 1, 10 do
    ChatTypeInfo["CHANNEL" .. i] = { r = 0.75, g = 0.75, b = 1.00 - (i * 0.05),
                                     sticky = 0 }
end

--[[ Channels by number, which is the whole difficulty: the numbers move when
     you leave one, and a colour stored against a number moves with them. ]]--
Stub.channels = {}
Stub.chatColors = {}

function GetChannelName(which)
    if type(which) == "number" then
        local name = Stub.channels[which]
        if not name then return 0 end
        return which, name
    end

    for i = 1, table.getn(Stub.channels) do
        if Stub.channels[i] == which then return i, Stub.channels[i] end
    end

    return 0
end

function ChangeChatColor(kind, r, g, b)
    Stub.chatColors[kind] = { r, g, b }
end

--[[ Every message sent, not just the last one. The link encoder is asserted by
     sending several in a row -- to a custom channel, to General, and out
     loud -- and comparing what went out each time, which one slot cannot
     hold. `chatSent` stays because older sections read it. ]]--
Stub.sent = {}

function SendChatMessage(message, kind, language, target)
    Stub.chatSent = { message = message, kind = kind, target = target }
    table.insert(Stub.sent,
            { message = message, kind = kind, target = target })
end

ChatFrameMenuButton = CreateFrame("Button", "ChatFrameMenuButton", nil)

--[[ The three buttons in a chat window's corner, which do nothing the mouse
     wheel and a right-click do not already do. ]]--
for i = 1, 7 do
    for _, which in ipairs({ "UpButton", "DownButton", "BottomButton" }) do
        CreateFrame("Button", "ChatFrame" .. i .. which, nil)
    end
end

function ChatFrame_AddChannel(frame, channel)
    if not frame or not channel then return end

    frame.channelList = frame.channelList or {}

    for i = 1, table.getn(frame.channelList) do
        if frame.channelList[i] == channel then return end
    end

    table.insert(frame.channelList, channel)
end

function ChatFrame_RemoveChannel(frame, channel)
    if not frame or not channel or not frame.channelList then return end

    for i = table.getn(frame.channelList), 1, -1 do
        if frame.channelList[i] == channel then
            table.remove(frame.channelList, i)
        end
    end
end

function Stub.JoinedChannel(number, name, zone)
    local decorated = number .. ". " .. name
    if zone then decorated = decorated .. " - " .. zone end

    local previous = { event, arg1, arg4, arg9 }
    event, arg1, arg4, arg9 = "CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", decorated, name

    local addon = EquadisClassicOverhaul
    if addon and addon.modules and addon.modules.chat then
        addon.modules.chat:OnEvent()
    end

    event, arg1, arg4, arg9 = previous[1], previous[2], previous[3], previous[4]
end

--[[ **Two numbers, and the second is the whole of overflow detection.**

     1.12 answers with the rows it actually sent *and* the total that matched --
     the first is capped by the Who list, the second is not. The roster module
     reads both and splits a query only when the uncapped total says there was
     more than the page could hold.

     This returned one number, so `totalCount` fell back to the row count and no
     test could ever describe a server that matched two hundred players and sent
     forty-nine. The band-splitting tests tried to say that with forty-nine rows
     and were reading a rule the module deliberately stopped applying: a full
     *page* is not a full *answer*, and treating it as one sends a class-by-class
     rescan after every busy level. ]]--
function GetNumWhoResults()
    local rows = table.getn(Stub.whoResults)
    return rows, Stub.whoTotal or rows
end

function GetWhoInfo(i)
    local w = Stub.whoResults[i]
    if not w then return nil end
    return w.name, w.guild or "", w.level, w.race or "Human", localizedClass(w.class)
end

--[[ The raid roster, which is `Stub.group` plus the subgroup number the party
     version has no room for. Kept separate so a test can put somebody in group
     three without inventing a whole raid. ]]--
--[[ **Six returns, because the sixth is the one worth having.**

     1.12 answers name, rank, subgroup, level, class, fileName -- and the fifth
     is the localised class while the sixth is the token. Anything colouring by
     class needs the token, and the stub used to stop at five, so the roster
     fallback for a unit too far away for UnitClass could not be exercised at
     all. ]]--
--[==[ **How loot is being handed out, and who is handing it.**

     `GetLootMethod` answers the method and, for master loot, the master's
     **raid index** -- which is the reliable way to ask "is this frame the loot
     master". The alternative is a trailing return of `GetRaidRosterInfo` whose
     position differs between builds, and a mis-counted return is how an icon
     ends up over the wrong person with nothing to say it is wrong.

     Rank comes from the roster and is already modelled: 2 is the leader, 1 an
     assistant, 0 everybody else. ]==]
Stub.lootMethod = "group"
Stub.masterLooterRaid = nil

function GetLootMethod()
    return Stub.lootMethod, nil, Stub.masterLooterRaid
end

--[==[ **The client mods, and the mirror gap they leave.**

     The suite runs as a **bare 1.12 client** on purpose, and that is the right
     default: every assertion in it is then an assertion about somebody with
     nothing installed. It also means the other half has never been tested at
     all. `OB.UnitDistance` picks between three providers in a deliberate order
     -- Nampower's `GetUnitDistance`, then UnitXP's `UnitXP("distanceBetween")`,
     then SuperWoW's `UnitPosition` -- and with none of the three modelled that
     function has returned `nil` in every run there has ever been. The order is
     exactly the sort of thing that gets quietly reordered by somebody tidying.

     **Installed on request, removed by default**, so nothing above changes: a
     test asks for the world it wants and the bare client stays the norm.
     `OB.RecheckCapabilities` has to be called after, which is the same thing a
     player does with `/eq recheck` when they have just switched one on. ]==]
Stub.extensions = {}

--[[ Where everybody is, in the world coordinates SuperWoW reports. Only
     friendly units, which is SuperWoW's real limitation and worth modelling:
     code that assumes a hostile distance from this source is wrong on a live
     client and would pass against a stub that answered for everybody. ]]--
Stub.positions = {}

function Stub.SetExtensions(list)
    list = list or {}
    Stub.extensions = list

    --[[ Nampower. Answers for anything, which is why it is preferred. ]]--
    if list.nampower then
        GetUnitDistance = function(unit)
            local p = Stub.positions[unit]
            local me = Stub.positions["player"]
            if not p or not me then return nil end

            local dx, dy = p[1] - me[1], p[2] - me[2]
            return math.sqrt((dx * dx) + (dy * dy))
        end
    else
        GetUnitDistance = nil
    end

    --[==[ **UnitXP_SP3, through the one model of it.**

         This used to install a dispatcher of its own -- `distanceBetween` and
         nothing else -- on top of `Stub.SetUnitXP`'s, which models the whole
         thing: the sight query, the passthrough build, and the stock experience
         API that owns this global when SP3 is absent. Two models of one global,
         last caller wins, and which one a test got depended on the order it
         happened to call them in.

         Worse in one specific way: switching the extension *off* set `UnitXP` to
         nil, and a client with no SP3 does not have no `UnitXP` -- it has the
         experience API, which is the entire reason the addon's probe is as
         careful as it is. A harness that removes the trap cannot catch anything
         falling into it.

         Line of sight stays a separate opt-in. A build can have the distance
         query without it, and that build is one the addon has to behave on. ]==]
    Stub.SetUnitXP(list.unitxp and true or false)

    --[[ A Nampower build extended with `IsUnitInSight`, which is a different
         thing again from either of the above -- and the one the sight capability
         used to miss. ]]--
    Stub.SetNampowerSight(list.insight and true or false)

    --[[ SuperWoW. Coordinates rather than a distance, and **friendly units
         only** -- see above. ]]--
    if list.superwow then
        SUPERWOW_VERSION = "1.4"

        UnitPosition = function(unit)
            --[==[ **Friendly units only**, decided by the token rather than by
                 `UnitCanAttack` -- that call ignores its unit argument here and
                 answers about the *target*, so asking it about `party1` gets a
                 fact about somebody else entirely.

                 The player and the group are what SuperWoW has objects for, and
                 the token is the honest way to say so. ]==]
            local friendly = unit == "player"
                    or string.find(unit or "", "^party%d")
                    or string.find(unit or "", "^raid%d")

            if not friendly then return nil end

            local p = Stub.positions[unit]
            if not p then return nil end
            return p[1], p[2], p[3] or 0
        end
    else
        SUPERWOW_VERSION = nil
        UnitPosition = nil
    end

    if EquadisClassicOverhaul and EquadisClassicOverhaul.RecheckCapabilities then
        EquadisClassicOverhaul.RecheckCapabilities()
    end

    return true
end

function GetRaidRosterInfo(i)
    local r = Stub.raidRoster[i] or Stub.group[i]
    if not r then return nil end
    return r.name, r.rank or 0, r.subgroup or 1, r.level,
            localizedClass(r.class), r.class
end

--[[ **Whether the client has an object for this unit.**

     False for a group member out of range, which is the whole point: several
     unit APIs answer from that object and go quiet without it, and code that
     reads their silence as a fact about the unit gets it wrong. Tests set
     Stub.unseen[unit] to put somebody over the horizon. ]]--
Stub.unseen = {}

function UnitIsVisible(unit)
    if unit and Stub.unseen[unit] then return nil end
    return 1
end

--[[ How far below you a level stops being worth colouring. The client widens
     this as you level -- nine at sixty, five at ten -- so it is asked for rather
     than assumed. ]]--
function GetQuestGreenRange() return Stub.greenRange or 5 end

--[[ The client's own answer to where the cap is. Anything asking whether a
     character is done levelling reads this rather than assuming sixty, so a
     server that raised it says so. Absent from the stub, code that read it
     fell back to a hardcoded sixty and the fallback was never exercised. ]]--
MAX_PLAYER_LEVEL = 60

function UnitLevel(unit)
    local member = groupMember(unit)
    if member then return member.level or 60 end
    if unit == "target" then return Stub.target and Stub.target.level or 60 end
    return Stub.player.level or 60
end

--[[ Target defaults to nothing, which is the state a test forgets to set up.
     Answering "yes, a friendly player" for a nil target would let the cache
     fill itself from a unit that is not there. ]]--
Stub.target = nil

function UnitIsPlayer(unit)
    --[[ No object, no answer. This is the behaviour that cost distant group
         members their class colour: the client does not say "I cannot tell",
         it says no, and code that read the no as a fact about the unit
         concluded a party member was not a player. ]]--
    if unit and Stub.unseen[unit] then return nil end

    if unit == "target" then return Stub.target and Stub.target.isPlayer ~= false end
    return true
end

function UnitIsFriend(a, b)
    if b == "target" then return Stub.target and Stub.target.friendly ~= false end
    return true
end

--[[ The one the client owns and every addon borrows. Real, because the meters'
     hover breakdown writes to it and a nil global would make that path throw the
     first time anybody moved a mouse -- in game, never here. ]]--
--[[ The seven chat windows, each with the AddMessage the client gives them and
     this addon hooks. Messages are kept rather than discarded: what a hook does
     to a line is the whole of what a chat module is, and a stub that swallowed
     the text could only ever check that the hook existed. ]]--
--[[ The client exposes these as globals; LuaJIT keeps them under `os` and
     `math`. Aliased rather than wrapped, because the addon calls exactly what
     1.12 calls and the behaviour is the same function either way.

     `mod` is Lua 5.0's, which the client kept as a global long after 5.1 moved
     it to the `%` operator -- so the addon uses the name the client has. ]]--
date = os.date
--[==[ **The wall clock, which a test has to be able to move.**

     `time` was `os.time` straight through, so anything measuring a real duration
     -- the PvP grace period, the mail autocomplete's thirty-day prune -- could
     only be tested by waiting. `Stub.clockOffset` moves it, in seconds, and is
     zero unless a test says otherwise.

     Deliberately **not** wired to `GetTime`: they are different clocks and
     confusing them is the exact bug the mail autocomplete had for years. `time`
     is a date, `GetTime` is seconds since the client started. ]==]
Stub.clockOffset = 0

time = function(when)
    --[==[ **The argument is not decoration.** `time{ year = ..., hour = ... }`
         converts a date table to an epoch, and the chat timestamp tests build
         their fixed moments that way. Dropping it made every one of them read
         "now", which is the sort of break that looks like ten unrelated failures
         rather than one missing parameter.

         An explicit date is not offset: the offset moves *now*, and a date
         somebody wrote down is already the moment they meant. ]==]
    if when then return os.time(when) end

    return os.time() + (Stub.clockOffset or 0)
end

--[==[ **Away and busy, which are the other two things
     `PLAYER_FLAGS_CHANGED` fires for.**

     Unmodelled, a reader filtering them out could not be shown to filter
     anything -- and the PvP grace clock keys off that event, so without these an
     addon that started a five-minute countdown when somebody went AFK would pass
     every test. ]==]
function UnitIsAFK(unit)
    if unit ~= "player" then return nil end
    return Stub.player.afk and 1 or nil
end

function UnitIsDND(unit)
    if unit ~= "player" then return nil end
    return Stub.player.dnd and 1 or nil
end
mod = math.mod

Stub.chatFrames = {}

for i = 1, 7 do
    local f = CreateFrame("Frame", "ChatFrame" .. i, nil)
    f.lines = {}
    f.AddMessage = function(self, text) table.insert(self.lines, text or "") end

    --[[ The properties a chat module reaches in and sets. Modelled rather than
         auto-faked because GetFont answering nil makes the restore path a
         no-op, and a no-op restore looks exactly like a working one. ]]--
    f.font, f.fontSize, f.fontFlags = "Fonts/FRIZQT__.TTF", 12, nil
    f.SetFont = function(self, path, size, flags)
        self.font, self.fontSize, self.fontFlags = path, size, flags
    end
    f.GetFont = function(self) return self.font, self.fontSize, self.fontFlags end

    f.SetJustifyH = function(self, v) self.justify = v end
    f.SetFading = function(self, v) self.fading = v end
    f.SetFadeDuration = function(self, v) self.fadeDuration = v end

    --[[ **Scrollback, modelled as a position rather than a flag.**

         A ScrollingMessageFrame remembers how far up it is, and every one of
         the four scroll calls moves that number -- so a test can ask "did three
         notches of the wheel move three lines" rather than only "was ScrollUp
         called". Speed settings are the whole point of the module and a boolean
         cannot tell a fast scroll from a slow one.

         The floor is zero because that is the bottom, which is where a chat
         frame starts and where it refuses to go past. The client has no ceiling
         short of the line count, and neither does this. ]]--
    f.scrollOffset = 0
    f.maxLines = 128

    --[[ **Resizing the buffer empties it.**

         That is the client's behaviour rather than a bug in it: a new buffer
         does not carry the old one's contents. Modelled, because it is the whole
         reason ApplyScrollback has to ask before it writes -- a stub that kept
         the lines would let an unguarded call pass here and wipe somebody's chat
         on every settings change in the game. It did. ]]--
    f.SetMaxLines = function(self, n)
        self.maxLines = n
        self.lines = {}
    end

    f.GetMaxLines = function(self) return self.maxLines end

    f.ScrollUp = function(self) self.scrollOffset = self.scrollOffset + 1 end
    f.ScrollDown = function(self)
        if self.scrollOffset > 0 then
            self.scrollOffset = self.scrollOffset - 1
        end
    end

    --[[ Named for what they do rather than where they land: "top" is the oldest
         message and the largest offset, which reads backwards until you
         remember the frame counts upward from the bottom. ]]--
    f.ScrollToTop = function(self) self.scrollOffset = 999 end
    f.ScrollToBottom = function(self) self.scrollOffset = 0 end

    --[[ **Whether the newest message is on screen**, which is the whole question
         a jump-to-bottom button exists to answer.

         Zero is the bottom, so this is the position read as a yes or no rather
         than a second piece of state -- a flag kept alongside the offset could
         disagree with it, and the one that disagreed would be the one the button
         believed. ]]--
    f.AtBottom = function(self) return self.scrollOffset <= 0 end

    f.EnableMouseWheel = function(self, v) self.mouseWheel = v and true or false end
    f.IsMouseWheelEnabled = function(self) return self.mouseWheel and true or false end

    --[[ Its own number, which is how the removal memory keys what was taken out
         of which window. A chat frame with no id would file every window's
         removals under nil and undo them all together. ]]--
    f.id = i
    f.GetID = function(self) return self.id end
    f.channelList = {}

    --[[ **The tab above the window**, which is a separate frame with a separate
         name and its own visibility. Real, because the tab pass shows, hides and
         fades them -- and a nil global would make that pass do nothing while
         looking exactly like it had worked.

         `isDocked` is what decides whether a tab is a tab at all: an undocked,
         hidden window has one in the client's naming and nowhere on screen, so
         showing it would conjure a tab nobody asked for. ]]--
    local tab = CreateFrame("Button", "ChatFrame" .. i .. "Tab", f)

    --[==[ **Two of the seven are docked, which is what a fresh login has.**

         FrameXML builds all seven frames and docks General and the combat log;
         the other five exist and are hidden until somebody makes them. This
         used to read `true` for all seven, which cost nothing while nothing
         asked -- and then the settings panel started asking, so that every
         per-window row was drawn for five windows that do not exist.

         A harness that says every window is live cannot fail that mistake, so
         it says what the client says instead. ]==]
    f.isDocked = (i <= 2) or nil
    if i > 2 then f:Hide() end

    --[[ The pristine method, kept so a re-boot can put it back. See
         `Stub.ResetChatFrames`. ]]--
    f.baseAddMessage = f.AddMessage

    Stub.chatFrames[i] = f
end

--[==[ **A boot is a fresh login, and these frames were surviving one.**

     The chat module wraps every window's `AddMessage` and guards against doing
     it twice with a flag on *itself*. A `boot()` builds a new addon, so that
     flag resets -- while these frames carried the previous session's wrapper.
     Every boot therefore added a layer, and a message came out with one
     timestamp per boot in front of it.

     In the game there is one boot per session and the guard is enough. Here
     there are dozens, so the client has to be as fresh as the addon is. It only
     began to matter when chat started shipping switched on: before that the
     module bound once, when a test asked for it. ]==]
function Stub.ResetChatFrames()
    for i = 1, table.getn(Stub.chatFrames) do
        local f = Stub.chatFrames[i]

        if f and f.baseAddMessage then
            f.AddMessage = f.baseAddMessage
        end

        if f then f.lines = {} end
    end
end

--[[ Which window is at the front. The client keeps this as a global pointing at
     the frame itself rather than at its number, which is why the tab pass asks
     it for its ID rather than comparing frames. ]]--
SELECTED_CHAT_FRAME = Stub.chatFrames[1]

--[[ The modifier keys, which the client answers as functions rather than
     exposing as state. Held in `Stub` so a test can set them without reaching
     into the global the addon reads. ]]--
Stub.shiftDown, Stub.ctrlDown, Stub.altDown = false, false, false

function IsShiftKeyDown() return Stub.shiftDown end
function IsControlKeyDown() return Stub.ctrlDown end

--[==[ **What an item does everywhere in the game**: shift-click puts its link in
     whatever you are typing, control-click shows it on your character.

     **`ChatEdit_InsertLink` used to be defined here, and it is a 2.0 function.**
     1.12 has no such call -- what this client does, in its own
     `ContainerFrame.lua`, is insert into `ChatFrameEditBox` when that box is
     visible. Providing it here made a guard that could never be true in the
     game read as satisfied under test, so the item database's shift-click was
     covered, green, and did nothing at all for real.

     Left undefined on purpose. A harness that invents an API is not a weaker
     test, it is a test of a different client.

     `DressUpItemLink` takes the *link* rather than an id on 1.12 and parses the
     id back out itself, which is why anything calling it has to have built a
     real hyperlink first. ]==]
Stub.chatLinks = {}
Stub.dressedUp = {}

function DressUpItemLink(link)
    table.insert(Stub.dressedUp, link)
    return true
end
function IsAltKeyDown() return Stub.altDown end

--[[ **Blizzard's unit frames**, which the unit frame module restyles rather than
     replaces.

     Modelled with the client's own naming inconsistency intact -- and this file
     previously got the inconsistency itself wrong, which is worse than
     regularising it.

     It claimed the target's border art was `TargetFrameTextureFrameTexture` and
     its name string `TargetFrameTextureFrameName`. Those are the *WotLK*
     names: 3.x wrapped the target frame in a `TextureFrame` and the globals
     moved inside it. On 1.12 they are `TargetFrameTexture` and `TargetName`,
     and target-of-target's border drops the `Frame` entirely --
     `TargetofTargetTexture`, not `TargetofTargetFrameTexture`.

     Because the module and the stub had made the same wrong assumption, every
     test agreed with it and the two frames people look at most were silently
     left alone on a live client. Ground truth here is the addons that do this
     on 1.12 for real: the standalone UnitFrames, DragonflightUI and
     ShaguTweaks all reach for `TargetFrameTexture` and `TargetName`. ]]--
--[[ **The Escape menu, which is a fixed stack of buttons with no layout.**

     Every button is anchored to the one above it and the frame's height is a
     number in the XML, so inserting one means placing it, re-anchoring whatever
     was under it, and growing the frame. Modelled with the anchors real, because
     "which button is under Options" is a question the addon *asks* rather than
     knows -- a server may have added its own -- and a stub with no anchors would
     let that lookup return nothing while looking like it worked. ]]--
templates.GameMenuButtonTemplate = function(frame)
    frame:SetWidth(144)
    frame:SetHeight(21)
end

GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", nil)
GameMenuFrame:SetHeight(200)

for i, name in ipairs({ "GameMenuButtonOptions", "GameMenuButtonKeybindings",
                        "GameMenuButtonMacros", "GameMenuButtonLogout",
                        "GameMenuButtonQuit" }) do
    local button = CreateFrame("Button", name, GameMenuFrame,
            "GameMenuButtonTemplate")

    if i > 1 then
        button:SetPoint("TOP", _G["GameMenuButtonOptions"], "BOTTOM", 0, -1)
    end
end

--[[ Only the button directly under Options is anchored to it; the rest chain
     from each other. Corrected here so the lookup has one answer rather than
     four -- which is what the client actually does. ]]--
_G["GameMenuButtonMacros"]:ClearAllPoints()
_G["GameMenuButtonMacros"]:SetPoint("TOP", _G["GameMenuButtonKeybindings"],
        "BOTTOM", 0, -1)
_G["GameMenuButtonLogout"]:ClearAllPoints()
_G["GameMenuButtonLogout"]:SetPoint("TOP", _G["GameMenuButtonMacros"],
        "BOTTOM", 0, -1)
_G["GameMenuButtonQuit"]:ClearAllPoints()
_G["GameMenuButtonQuit"]:SetPoint("TOP", _G["GameMenuButtonLogout"],
        "BOTTOM", 0, -1)

function HideUIPanel(frame) if frame and frame.Hide then frame:Hide() end end

Stub.reaction = 4

function UnitReaction(unit, other) return Stub.reaction end

--[[ **Targeting by name, which succeeds or quietly does not.**

     `TargetByName` is how an addon re-acquires somebody who vanished, and the
     client is noisy about failing -- it plays a sound and writes to the error
     frame. Both are real here, because the retarget helper silences them across
     the call and puts them straight back, and a stub without them would let that
     save-and-restore be written wrong.

     Nothing is targetable by default, so the failure path -- the one that has to
     forget rather than keep reaching -- is the one a test gets without asking. ]]--
Stub.targetable = {}

function TargetByName(name, exact)
    if Stub.targetable[name] then
        Stub.player.hasTarget = true
        Stub.target = Stub.targetable[name]

        --[[ And so is finding one. The two halves of a probe -- select, then put
             it back -- are two target changes and therefore two sounds. ]]--
        if PlaySound then PlaySound("igCreatureAggroSelect") end
        return
    end

    --[[ Failed. The client says so out loud, which is exactly what the caller
         is silencing. ]]--
    if PlaySound then PlaySound("igQuestFailed") end
    if UIErrorsFrame_OnEvent then UIErrorsFrame_OnEvent() end
end

function UIErrorsFrame_OnEvent() Stub.lastUIError = true end
--[[ **The client replaces whatever was on the texture**, which is how a class
     icon stops being drawn when the target changes from a player to a mob.
     Recording only which unit it was called for modelled none of that, and
     agreed with a port that left the icon in place. ]]--
function SetPortraitTexture(texture, unit)
    texture.portraitOf = unit
    texture.texture = "Portrait-" .. tostring(unit)
end

for _, frame in ipairs({
    { "PlayerFrame", "PlayerFrameHealthBar", "PlayerFrameManaBar",
      "PlayerName", "PlayerPortrait", "PlayerFrameTexture" },
    { "TargetFrame", "TargetFrameHealthBar", "TargetFrameManaBar",
      "TargetName", "TargetPortrait",
      "TargetFrameTexture" },
    { "TargetofTargetFrame", "TargetofTargetHealthBar", "TargetofTargetManaBar",
      "TargetofTargetName", "TargetofTargetPortrait", "TargetofTargetTexture" },
    { "PetFrame", "PetFrameHealthBar", "PetFrameManaBar",
      "PetName", "PetPortrait", "PetFrameTexture" },
}) do
    local parent = CreateFrame("Frame", frame[1], nil)

    for i, bar in ipairs({ frame[2], frame[3] }) do
        local b = CreateFrame("StatusBar", bar, parent)
        b.frameType = "StatusBar"
        _G[bar .. "Text"] = newFontString(b, "OVERLAY", "GameFontNormalSmall")

        --[[ The client reaches its own text through `bar.TextString` and its
             own bars through `frame.healthbar` / `frame.manabar`, not through
             the global names. Both spellings are real, and a stub with only the
             globals lets a replacement of `TextStatusBar_UpdateTextString` be
             written against a field that is never there. ]]--
        b.TextString = _G[bar .. "Text"]
        b.textLockable = 1
        b.lockShow = 0
        b:SetMinMaxValues(0, 100)
        b:SetValue(100)

        if i == 1 then parent.healthbar = b else parent.manabar = b end
    end

    --[[ The client anchors every unit frame name inside its own frame, and a
         stub that left them unanchored agreed with a port that anchored them
         anywhere: there was nothing to restore and nothing to compare. ]]--
    _G[frame[4]] = newFontString(parent, "OVERLAY", "GameFontNormal")
    _G[frame[4]]:SetPoint("TOP", parent, "TOP", 0, -4)
    _G[frame[5]] = parent:CreateTexture(frame[5], "ARTWORK")
    _G[frame[6]] = parent:CreateTexture(frame[6], "OVERLAY")

    --[[ **The art region has a size, because the client's does.**

         These come from the XML, and by the time an addon binds they are
         laid out. A stub that left them at nothing agreed with a port
         that captured nothing and restored nothing -- which is the fault
         being guarded against, so the stub has to have the numbers.

         232x100 for the player and target: the frame's size, not the
         256x128 file's. 93x45 and 128x53 for the small frames. ]]--
    if frame[1] == "PlayerFrame" or frame[1] == "TargetFrame" then
        parent:SetWidth(232) parent:SetHeight(100)
        _G[frame[6]]:SetWidth(232) _G[frame[6]]:SetHeight(100)
    elseif frame[1] == "TargetofTargetFrame" then
        parent:SetWidth(93) parent:SetHeight(45)
        _G[frame[6]]:SetWidth(93) _G[frame[6]]:SetHeight(45)
    else
        parent:SetWidth(128) parent:SetHeight(53)
        --[[ **The frame is 128x53 and its texture is 128x64**, which is not a
             typo: the XML gives the art more height than the frame, because
             the art overhangs it. Written as 53 for both here at first,
             which would have agreed with a port that squashed the pet's
             art to its frame's height. ]]--
        _G[frame[6]]:SetWidth(128) _G[frame[6]]:SetHeight(64)
    end
end

--[[ The target frame's backing plate, which compact mode shortens. Real,
     because the compact layout is sizes rather than a replacement texture and a
     missing frame would make that pass do nothing while looking like it
     worked. ]]--
CreateFrame("Frame", "TargetFrameBackground", _G["TargetFrame"])

--[==[ **The target's aura buttons**, five for buffs and sixteen for debuffs,
     which is what the client builds. Neither existed here, so the pass that
     writes a timer onto them had nothing to write on and reported having drawn
     nought -- which is also what it reports when it works and finds no aura. ]==]
for i = 1, 5 do
    CreateFrame("Button", "TargetFrameBuff" .. i, _G["TargetFrame"])
end

for i = 1, 16 do
    CreateFrame("Button", "TargetFrameDebuff" .. i, _G["TargetFrame"])
end

--[[ **The client's own status text machinery, which is the thing a unit frame
     addon is actually fighting.**

     `TextStatusBar_UpdateTextString` is Blizzard's, it owns every one of these
     strings, and it runs on the bar's own `OnValueChanged` -- so it fires after
     any event handler that took damage as its cue. An addon that writes the text
     on an event and stops there has its text overwritten a frame later, which
     looks exactly like a setting that does nothing.

     Worse, the client *hides* the string unless the `statusBarText` CVar is on
     or the bar is `lockShow`n. Off by default, as it is in the client, because
     that is the case where the port's own text never appears at all.

     Modelled here rather than left out, because a stub without it agrees with
     the assumption that writing the text once is enough. The CVar itself is set
     with the others, further down -- the table does not exist yet here. ]]--

function TextStatusBar_UpdateTextString(bar)
    bar = bar or this
    if not bar then return end

    local string = bar.TextString
    if not string then return end

    local value = bar:GetValue()
    local _, valueMax = bar:GetMinMaxValues()

    if valueMax and valueMax > 0 then
        bar:Show()

        if value == 0 and bar.zeroText then
            string:SetText(bar.zeroText)
            bar.isZero = 1
            string:Show()
        else
            bar.isZero = nil
            string:SetText(value .. "/" .. valueMax)

            if GetCVar("statusBarText") == "1" and bar.textLockable then
                string:Show()
            elseif (bar.lockShow or 0) > 0 then
                string:Show()
            else
                string:Hide()
            end
        end
    else
        bar:Hide()
    end
end

--[[ **And the colour, which the client rewrites just as often.**

     `HealthBar_OnValueChanged` paints every health bar green -- or red-to-green
     if the bar asked for smoothing -- on every value change. A module that sets
     a bar's colour on an event and stops there gets one frame of its own colour
     and then Blizzard's.

     This is why the addon this is ported from replaces the function outright
     rather than calling `SetStatusBarColor` from the outside. ]]--
function HealthBar_OnValueChanged(value, smooth)
    local bar = this
    if not bar then return end
    if not value then return end

    local min, max = bar:GetMinMaxValues()
    if not min or not max then return end
    if value < min or value > max then return end

    if max - min > 0 then value = (value - min) / (max - min) else value = 0 end

    local r, g = 0, 1

    if smooth then
        if value > 0.5 then r, g = (1 - value) * 2, 1 else r, g = 1, value * 2 end
    end

    bar:SetStatusBarColor(r, g, 0)
end

--[[ The pet's per-frame update, which is where the original does its pet work.
     Real because the module replaces it, and a replacement of something that
     does not exist is a silent no-op. ]]--
function CombatFeedback_OnUpdate(elapsed) Stub.combatFeedbackRan = true end
function PetFrame_OnUpdate(elapsed) CombatFeedback_OnUpdate(elapsed) end

--[[ The target frame's border, redrawn whenever the target's classification
     changes -- elite, rare, world boss. Replaced by the module for dark
     mode. ]]--
function TargetFrame_CheckClassification() Stub.classificationChecked = true end

Stub.classification = "normal"
function UnitClassification(unit) return Stub.classification end

--[==[ **What kind of thing this is, in the client's own words.**

     The client localizes these and exposes each one as a global, which is why
     code that wants to know whether something is a totem compares against
     `CREATURE_TYPE_TOTEM` rather than against the English word. Modelled the
     same way -- globals plus a matching answer -- because a stub that only
     answered "Totem" would let a port that hardcoded the English through. ]==]
CREATURE_TYPE_TOTEM = "Totem"
CREATURE_TYPE_CRITTER = "Critter"
CREATURE_TYPE_DEMON = "Demon"
CREATURE_TYPE_BEAST = "Beast"

Stub.creatureType = nil
function UnitCreatureType(unit) return Stub.creatureType end

--[==[ **A guild, which the client answers per unit and not per name.**

     `GetGuildInfo` takes a unit token, so anything holding only a name -- a
     nameplate, a chat line, a roster row -- cannot ask it. That gap is the
     entire reason guild names have to be cached when a unit happens to be
     reachable, and a stub that answered by name would hide it.

     An empty string rather than nil for the unguilded, because that is what the
     client returns and the difference decides whether "left their guild" reads
     as news or as silence. ]==]
Stub.guildOf = {}
Stub.playerGuild = nil

function GetGuildInfo(unit)
    local name = UnitName(unit)
    if not name then return nil end

    if unit == "player" then return Stub.playerGuild end

    local guild = Stub.guildOf[name]
    if guild == nil and name == UnitName("player") then
        guild = Stub.playerGuild
    end

    return guild
end

Stub.petHappiness = 3
function GetPetHappiness() return Stub.petHappiness, 100, 0 end

--[[ The pieces the original touches by name: the combat glow behind the player
     portrait, the pet's attack flash, its happiness meter, and the plate behind
     the target's name that compact mode hides. ]]--
--[==[ **The faction icon the unflag countdown explains.**

     A real region, because the readout anchors to it -- and an anchor to nothing
     is the difference between "under the icon" and "in the corner of the
     screen", which is exactly the kind of placement a stub with no icon cannot
     tell apart. Sized as the client's, on `PlayerFrame` where the client puts
     it. ]==]
PlayerPVPIcon = _G["PlayerFrame"]:CreateTexture("PlayerPVPIcon", "OVERLAY")
PlayerPVPIcon:SetWidth(16)
PlayerPVPIcon:SetHeight(16)
PlayerPVPIcon:SetPoint("TOPLEFT", _G["PlayerFrame"], "TOPLEFT", 12, -16)

PlayerStatusTexture = _G["PlayerFrame"]:CreateTexture("PlayerStatusTexture", "OVERLAY")
PetAttackModeTexture = _G["PetFrame"]:CreateTexture("PetAttackModeTexture", "OVERLAY")
PetFrameHappiness = _G["PetFrame"]:CreateTexture("PetFrameHappiness", "OVERLAY")
TargetFrameNameBackground = _G["TargetFrame"]:CreateTexture("TargetFrameNameBackground", "ARTWORK")
TargetDeadText = newFontString(_G["TargetFrame"], "OVERLAY", "GameFontNormal")
_G["TargetDeadText"] = TargetDeadText

--[==[ **The client's combo points on the target frame**, with the cuts the
     1.12 `TargetFrame.xml` gives them: `UI-ComboPoint` is one 32x16 file,
     the socket ring in its first 0.375, the red orb to 0.5625, the shine in
     the rest. Modelled with the real coordinates because the addon reads
     its own orb's cut off `ComboPoint1Highlight` rather than guessing it --
     and a stub with no such texture would only ever exercise the guess. ]==]
CreateFrame("Frame", "ComboFrame", _G["TargetFrame"])

for i = 1, 5 do
    local point = CreateFrame("Frame", "ComboPoint" .. i, _G["ComboFrame"])

    local highlight = point:CreateTexture("ComboPoint" .. i .. "Highlight", "BACKGROUND")
    highlight:SetTexture("Interface\\TargetingFrame\\UI-ComboPoint")
    highlight:SetTexCoord(0.375, 0, 0.375, 1, 0.5625, 0, 0.5625, 1)

    local shine = point:CreateTexture("ComboPoint" .. i .. "Shine", "ARTWORK")
    shine:SetTexture("Interface\\TargetingFrame\\UI-ComboPoint")
    shine:SetTexCoord(0.5625, 0, 0.5625, 1, 1, 0, 1, 1)
end

for i = 1, 4 do
    local name = "PartyMemberFrame" .. i
    local parent = CreateFrame("Frame", name, nil)

    for j, suffix in ipairs({ "HealthBar", "ManaBar" }) do
        local b = CreateFrame("StatusBar", name .. suffix, parent)
        b.frameType = "StatusBar"
        _G[name .. suffix .. "Text"] =
                newFontString(b, "OVERLAY", "GameFontNormalSmall")

        b.TextString = _G[name .. suffix .. "Text"]
        b.textLockable = 1
        b.lockShow = 0
        b:SetMinMaxValues(0, 100)
        b:SetValue(100)

        if j == 1 then parent.healthbar = b else parent.manabar = b end
    end

    _G[name .. "Name"] = newFontString(parent, "OVERLAY", "GameFontNormal")
    _G[name .. "Portrait"] = parent:CreateTexture(name .. "Portrait", "ARTWORK")
end

--[[ **Blizzard's action bars**, which are the frames the action bar module moves
     rather than anything it makes.

     Every button is real, with the two font strings the client puts on it --
     `<name>HotKey` and `<name>Name` -- because restyling those is half the
     module, and a stub without them would let the whole text pass run against
     nothing and report success.

     The families and their counts are the client's: twelve for every action bar,
     ten for the pet and stance bars. Getting that wrong here would hide a module
     that laid out ten stance buttons as if there were twelve. ]]--
--[[ **Bindings, modelled in both directions.**

     `GetBindingKey(command)` answers the key and `GetBindingAction(key)` answers
     the command, and bind mode needs both -- the second is how it can say what a
     key was taken *from*, which is the thing the client never tells you.

     Kept as two tables that are maintained together, because that is what the
     client does and because a stub with one of them would let the "taken from"
     line be written and never checked. ]]--
Stub.bindings = {}
Stub.boundTo = {}
Stub.bindingsSaved = 0

function GetBindingKey(command) return Stub.bindings[command] end
function GetBindingAction(key) return Stub.boundTo[key] end

function SetBinding(key, command)
    --[[ A key already held by something else changes hands, which is exactly the
         case bind mode warns about. Modelled, or the warning could not be
         tested. ]]--
    local previous = Stub.boundTo[key]
    if previous then Stub.bindings[previous] = nil end

    if command then
        Stub.boundTo[key] = command
        Stub.bindings[command] = key
    else
        Stub.boundTo[key] = nil
    end

    return 1
end

function SaveBindings(which) Stub.bindingsSaved = Stub.bindingsSaved + 1 end
function GetCurrentBindingSet() return 1 end
function CloseAllWindows() Stub.windowsClosed = true end

--[[ Which frame the mouse is over, by geometry rather than by focus -- which is
     how the addon has to ask it, because its own capture frame owns the mouse
     while bind mode is on. ]]--
Stub.mouseOver = nil

function MouseIsOver(frame) return Stub.mouseOver == frame end


--[[ The bar frames and their art. Real, because the module hides the art and
     switches the mouse off -- and a nil global would make that pass do nothing
     while looking exactly like it had worked. ]]--
for _, name in ipairs({ "MainMenuBar", "MainMenuBarArtFrame", "PetActionBarFrame",
                        "BonusActionBarFrame", "ShapeshiftBarFrame",
                        "MultiBarBottomLeft", "MultiBarBottomRight",
                        "MultiBarLeft", "MultiBarRight" }) do
    CreateFrame("Frame", name, nil)
end

--[[ **The bag slots and the micro menu**, which the client parents to the main
     bar art and lays out itself.

     Modelled with a real parent, anchor and size, because code that gathers
     them into a bar of its own has to record where each came from before it
     moves it -- and a stub with no buttons agrees with a port that gathers
     nothing. The three Turtle-only micro buttons are left out on purpose: a
     name that is not there is the case a stock client presents, and the sweep
     has to skip it rather than guess. ]]--
for _, name in ipairs({
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
    "MainMenuMicroButton", "HelpMicroButton",
}) do
    local b = CreateFrame("Button", name, MainMenuBarArtFrame)
    b:SetWidth(30)
    b:SetHeight(30)
    b:SetPoint("BOTTOMRIGHT", MainMenuBarArtFrame, "BOTTOMRIGHT", 0, 0)
end

--[[ **A finder button, round and on the minimap**, which is where this client
     puts the group and battleground finders rather than in the micro menu.

     Given a size of its own -- 32 across, unlike the 30 of a micro button -- so
     a test can tell "sized to match the row it joined" from "left alone", and
     can tell whether the original size came back when the bar was switched
     off. Same size for both would agree with a port that never resized
     anything. ]]--
--[==[ **The two finders this client keeps on the minimap.**

     Turtle's battlefield frame answers `OnClick` and opens the battleground
     queue menu; the Looking For Team eye answers `OnMouseUp`, because it wants
     the release rather than the press. Both are modelled with a handler that
     records, because "the click reached the client's own frame" is the whole of
     what ECO's forwarding button is responsible for.

     Named icon regions too -- `$parentIcon` and `$parentEye` -- since that is
     how a button of ours finds the picture to wear. ]==]
Stub.finderClicks = {}

LFTMinimapButton = CreateFrame("Button", "LFTMinimapButton", Minimap)
LFTMinimapButton:SetWidth(33)
LFTMinimapButton:SetHeight(33)

LFTMinimapButtonEye = LFTMinimapButton:CreateTexture("LFTMinimapButtonEye",
        "BACKGROUND")
LFTMinimapButtonEye:SetTexture("Interface\\FrameXML\\LFT\\images\\eye")

LFTMinimapButton:SetScript("OnMouseUp", function()
    table.insert(Stub.finderClicks, "LFT:" .. tostring(this and this:GetName()))
end)

TWMiniMapBattlefieldFrame = CreateFrame("Button", "TWMiniMapBattlefieldFrame",
        Minimap)
TWMiniMapBattlefieldFrame:SetWidth(32)
TWMiniMapBattlefieldFrame:SetHeight(32)
TWMiniMapBattlefieldFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 0, 0)

TWMiniMapBattlefieldFrameIcon = TWMiniMapBattlefieldFrame:CreateTexture(
        "TWMiniMapBattlefieldFrameIcon", "ARTWORK")
TWMiniMapBattlefieldFrameIcon:SetTexture("Interface\\Icons\\ability_dualwield")

TWMiniMapBattlefieldFrame:SetScript("OnClick", function()
    table.insert(Stub.finderClicks, "TW:" .. tostring(arg1))
end)

--[[ **Experience, and the reason an addon must not simply ask for it.**

     Stock 1.12 answers `UnitXP("player")` with a number. UnitXP_SP3 -- which a
     great many Turtle clients run -- replaces that same global with a command
     dispatcher, and on a build that does not pass unknown commands through,
     asking it for experience returns **nil**. So the obvious call is the one
     that fails on exactly the client this addon targets.

     The client's own bar is immune: `MainMenuExpBar` is filled by the client
     from its internal values, whatever an addon has done to the global. Modelled
     here so a fallback can be tested rather than assumed. ]]--
MainMenuExpBar = CreateFrame("StatusBar", "MainMenuExpBar", MainMenuBarArtFrame)
MainMenuExpBar:SetMinMaxValues(0, 1)
MainMenuExpBar:SetValue(0)

function UnitXPMax(unit)
    return Stub.player.xpMax or 0
end

--[[ Rested experience, which is a pool rather than a rate: nil when there is
     none, which is the state most of a levelling life is spent in. ]]--
function GetXPExhaustion()
    return Stub.player.rested
end

--[[ **The watched faction, or nothing at all.**

     Nobody is required to be watching a faction, and the bar has to have
     something sensible to do when nobody is -- so `nil` is the ordinary case,
     not an error state. ]]--
Stub.watchedFaction = nil

function GetWatchedFactionInfo()
    local f = Stub.watchedFaction
    if not f then return nil end

    return f.name, f.standing, f.min, f.max, f.value
end

--[==[ **The reputation list, which nothing modelled.**

     Watching a faction was answerable and looking one up was not, so a bar that
     falls back to "whatever you last earned reputation with" had no way to find
     that faction's numbers -- and therefore no way to be tested.

     `GetFactionInfo` returns headers as well as factions in 1.12, and a header
     has no standing. Modelled with one in the middle on purpose: code that
     walks the list and assumes every row is a faction reads a nil standing off
     the header, and that is the shape of mistake this exists to catch. ]==]
Stub.factions = {
    { name = "Argent Dawn", standing = 4, min = 9000, max = 21000, value = 12500 },
    { name = "Other", header = true },
    { name = "Timbermaw Hold", standing = 3, min = 3000, max = 9000, value = 4200 },
}

--[==[ **Who leads the party**, which nothing modelled.

     `UnitIsPartyLeader` is the direct question; `GetPartyLeaderIndex` is the
     older one and answers with the party index of the leader, or zero when that
     is you. Both are here because a 1.12 build may have only the second, and
     code that reads just the first would silently draw no crown at all on such
     a client -- an absence that looks exactly like the bug it replaced. ]==]
Stub.partyLeader = nil

function UnitIsPartyLeader(unit)
    if not Stub.partyLeader then return nil end
    return unit == Stub.partyLeader and 1 or nil
end

function GetPartyLeaderIndex()
    if not Stub.partyLeader then return 0 end

    local _, _, n = string.find(Stub.partyLeader, "^party(%d+)$")
    return tonumber(n) or 0
end

function GetNumFactions()
    return table.getn(Stub.factions)
end

function GetFactionInfo(index)
    local f = Stub.factions[index]
    if not f then return nil end

    if f.header then
        return f.name, "", nil, nil, nil, nil, nil, nil, 1
    end

    return f.name, "", f.standing, f.min, f.max, f.value,
            nil, nil, nil
end

--[[ The line the client prints when reputation changes. Absent, so nothing
     could read a faction name out of one. ]]--
FACTION_STANDING_INCREASED = "Your %s reputation has increased by %d."
FACTION_STANDING_DECREASED = "Your %s reputation has decreased by %d."

--[[ **Every action button is a child of Blizzard's own bar frame**, which is the
     fact the whole layout pass turns on and which this stub used to leave out.

     A child inherits its parent's visibility. So hiding `PetActionBarFrame` to
     get rid of its art hides all ten pet buttons with it, and moving a button by
     `SetPoint` alone leaves it inheriting the alpha, scale and *position
     management* of a frame the client is still moving around. Parented to
     nothing, as they were here, none of that could happen and a port that only
     ever called `SetPoint` looked correct. ]]--
local BUTTON_PARENT = {
    ActionButton = "MainMenuBarArtFrame",
    BonusActionButton = "BonusActionBarFrame",
    MultiBarBottomLeftButton = "MultiBarBottomLeft",
    MultiBarBottomRightButton = "MultiBarBottomRight",
    MultiBarRightButton = "MultiBarRight",
    MultiBarLeftButton = "MultiBarLeft",
    ShapeshiftButton = "ShapeshiftBarFrame",
    PetActionButton = "PetActionBarFrame",
}

for _, family in ipairs({ { "ActionButton", 12 }, { "BonusActionButton", 12 },
                          { "MultiBarBottomLeftButton", 12 },
                          { "MultiBarBottomRightButton", 12 },
                          { "MultiBarRightButton", 12 },
                          { "MultiBarLeftButton", 12 },
                          { "ShapeshiftButton", 10 },
                          { "PetActionButton", 10 } }) do
    for i = 1, family[2] do
        local button = CreateFrame("Button", family[1] .. i,
                _G[BUTTON_PARENT[family[1]]])

        button:SetWidth(36)
        button:SetHeight(36)

        _G[family[1] .. i .. "HotKey"] =
                newFontString(button, "OVERLAY", "GameFontNormalSmall")
        _G[family[1] .. i .. "Name"] =
                newFontString(button, "OVERLAY", "GameFontNormalSmall")

        --[[ **How many are left**, which is the third string on a button and
             was modelled by nothing -- so the half of the styling pass that
             touches it could not be asserted, and for a long time there was no
             such half.

             Only where the client has one. A stance form and a pet command do
             not come in stacks, so `ShapeshiftButton` and `PetActionButton`
             carry a keybind and no count -- and a sweep that assumed all eight
             families were alike would pass here and index nil in game. ]]--
        if family[1] ~= "ShapeshiftButton" and family[1] ~= "PetActionButton" then
            _G[family[1] .. i .. "Count"] =
                    newFontString(button, "OVERLAY", "NumberFontNormal")
        end
    end
end

--[[ **The client rewrites its own keybind text, and often.**

     `ActionButton_UpdateHotkeys` runs from `ActionButton_Update` -- every time a
     spell is dragged onto a bar, every time a binding changes, and on entering
     the world -- and it writes the binding out in full. An addon that shortens
     that text once has it lengthened again on the next spell drag.

     Same shape as the unit frame text problem, and modelled for the same reason:
     without it the stub agrees that shortening once is enough. ]]--
function GetBindingText(key, prefix, returnAbbr)
    if not key or key == "" then return "" end
    return key
end

--[==[ **The client paints the keybind as well as the icon**, and that is the
     half every addon with a keybind colour misses.

     `ActionButton_UpdateUsable` writes white when the spell can be cast, blue
     when the mana is short and grey when it cannot be -- to the *icon* and to
     the `HotKey` -- and on a `FontString` a vertex colour is the text colour, so
     it replaces what an addon set rather than shading it.

     **And it only runs for a button with an action on it.** That asymmetry is
     the whole of the bug it exists to catch: the client repaints the keybinds
     on buttons holding spells and leaves the empty ones alone, so a bar came out
     in two colours at once and each half looked deliberate.

     Which buttons hold something is `Stub.actionOnButton`, by name: this stub
     has no action-slot model and inventing one to answer a colour question
     would be a second thing to keep true. ]==]
Stub.actionOnButton = {}

function ActionButton_UpdateUsable(button)
    button = button or this

    local name = button and button.GetName and button:GetName()
    if not name or not Stub.actionOnButton[name] then return end

    local hotkey = _G[name .. "HotKey"]
    if hotkey and hotkey.SetVertexColor then hotkey:SetVertexColor(1, 1, 1) end

    local icon = _G[name .. "Icon"]
    if icon and icon.SetVertexColor then icon:SetVertexColor(1, 1, 1) end
end

function ActionButton_UpdateHotkeys(button, buttonType)
    button = button or this
    if not button or not button.GetName then return end

    local hotkey = _G[(button:GetName() or "") .. "HotKey"]
    if not hotkey then return end

    local command = Stub.buttonCommand and Stub.buttonCommand[button:GetName()]
    local key = command and GetBindingKey(command)

    hotkey:SetText(key and GetBindingText(key) or "")
end

for _, name in ipairs({ "MainMenuBarTexture0", "MainMenuBarTexture1",
                        "MainMenuBarTexture2", "MainMenuBarTexture3",
                        "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
                        "SlidingActionBarTexture0", "SlidingActionBarTexture1",
                        "BonusActionBarTexture0", "BonusActionBarTexture1",
                        "ShapeshiftBarLeft", "ShapeshiftBarMiddle",
                        "ShapeshiftBarRight" }) do
    _G[name] = CreateFrame("Frame", nil, nil):CreateTexture(name, "ARTWORK")

    --[[ **With a texture already on it**, because the client's art has one and
         that is the whole reason hiding it must not be done by clearing it: the
         path is the client's and an addon that nils it cannot put it back. A
         stub whose art started blank could not tell the two apart. ]]--
    _G[name]:SetTexture("BlizzardArtFor-" .. name)
end

--[[ **The quest frames**, which in 1.12 are three windows and one conversation.

     Accept, then "have you brought it", then the reward -- each its own event
     with its own button, and the title text is the only thing that identifies
     the quest across all three. There is no quest id in this API.

     `Stub.quest` is what the window is showing. The calls that push it forward
     record themselves rather than advancing it, because what is worth asserting
     is which button was pressed, not a state machine written here. ]]--
Stub.quest = { title = "", completable = true, choices = 0 }
Stub.questCalls = {}

function GetTitleText() return Stub.quest.title end
function IsQuestCompletable() return Stub.quest.completable end
function GetNumQuestChoices() return Stub.quest.choices or 0 end

function AcceptQuest() table.insert(Stub.questCalls, "accept") end
function CompleteQuest() table.insert(Stub.questCalls, "complete") end
function GetQuestReward() table.insert(Stub.questCalls, "reward") end

--[[ An NPC's quest list, which 1.12 answers as one flat run of title, level,
     title, level. Modelled flat rather than as a list of records, because
     pulling the titles back out of that run is the part that can be got wrong. ]]--
Stub.gossipAvailable = {}
Stub.gossipActive = {}
Stub.gossipPicked = nil

local function flatten(quests)
    local out = {}

    for i = 1, table.getn(quests) do
        table.insert(out, quests[i])
        table.insert(out, 60)
    end

    return unpack(out)
end

function GetGossipAvailableQuests() return flatten(Stub.gossipAvailable) end
function GetGossipActiveQuests() return flatten(Stub.gossipActive) end

function SelectGossipAvailableQuest(i)
    Stub.gossipPicked = { kind = "available", index = i }
end

function SelectGossipActiveQuest(i)
    Stub.gossipPicked = { kind = "active", index = i }
end

--[[ The other kind of NPC menu: no gossip text, just a list, and four different
     calls to read the same two lists with. ]]--
function GetNumAvailableQuests() return table.getn(Stub.gossipAvailable) end
function GetAvailableTitle(i) return Stub.gossipAvailable[i] end
function GetNumActiveQuests() return table.getn(Stub.gossipActive) end
function GetActiveTitle(i) return Stub.gossipActive[i] end

function SelectAvailableQuest(i)
    Stub.gossipPicked = { kind = "available", index = i }
end

function SelectActiveQuest(i)
    Stub.gossipPicked = { kind = "active", index = i }
end

--[[ **Turning the wheel**, which is three pieces of client state at once: the
     frame's handler, the modifier keys, and `arg1` carrying the direction.

     `arg1` is a global in 1.12 -- the client sets it before calling the handler
     and the handler reads it off the environment -- so the stub sets it the same
     way rather than passing it in. A handler written to take it as a parameter
     would pass here and read nil in the game. ]]--
function Stub.Wheel(index, direction, modifier)
    local frame = Stub.chatFrames[index]
    local handler = frame:GetScript("OnMouseWheel")

    if not frame:IsMouseWheelEnabled() then return end
    if not handler then return end

    Stub.shiftDown = (modifier == "SHIFT")
    Stub.ctrlDown = (modifier == "CTRL")

    local previousThis, previousArg = this, arg1
    this, arg1 = frame, direction

    handler()

    this, arg1 = previousThis, previousArg
    Stub.shiftDown, Stub.ctrlDown = false, false
end

--[==[ **What aura is in which of the target's slots.**

     There is no call in 1.12 that answers "what is debuff three on the target".
     The client will only *draw* the name into a tooltip, and every addon that
     needs it reads it back out of the tooltip's font strings. None of that was
     modelled, so the code doing the reading had no way to be tested -- which is
     how a lookup made against the wrong key survived: it returned nothing, and
     nothing is what a spell with no known duration returns too.

     Buffs and debuffs are separate lists with separate numbering, which is the
     fact worth modelling: slot three of one is a different spell from slot
     three of the other, and asking the wrong setter answers about the wrong
     spell rather than failing. ]==]
Stub.unitAuras = {}

function Stub.SetUnitAuras( unit, buffs, debuffs )
    Stub.unitAuras[ unit ] = { buffs = buffs or {}, debuffs = debuffs or {} }
end

function Stub.AuraNamed( unit, index, harmful )
    local set = Stub.unitAuras[ unit ]
    if not set then return nil end

    local list = harmful and set.debuffs or set.buffs
    return list and list[ index ]
end

--[[ Written where `OB.ScanLine` looks: a font string named after the tooltip
     with `TextLeft<n>` on the end, which is how the client names them and how
     everything here finds them. ]]--
function Stub.WriteTooltipAura( tip, unit, index, harmful )
    local name = Stub.AuraNamed( unit, index, harmful )
    if not tip or not tip.name then return false end

    local key = tip.name .. "TextLeft1"
    local line = _G[ key ]

    if not line and tip.CreateFontString then
        line = tip:CreateFontString( key, "OVERLAY", "GameFontNormal" )
    end

    if line then line:SetText( name or "" ) end

    return name ~= nil
end

--[[ Server time, which 1.12 gives as hours and minutes and no seconds at all --
     the reason the chat module has to recover a second hand by watching the
     minute roll over. ]]--
--[[ The client's channel-group tables, which ChannelSeparator rewrites. Real
     tables because the module saves and restores them, and a restore that put
     back a fabricated table would pass while losing the client's own. ]]--
--[[ The format strings the client builds every chat line from. Real values,
     because the chat module saves them before overwriting and a saved nil
     restores as nil -- which blanks a channel's label rather than restoring it.
     `%s` is the speaker, substituted by the client. ]]--
CHAT_GUILD_GET = "|Hchannel:Guild|h[Guild]|h %s: "
CHAT_OFFICER_GET = "|Hchannel:o|h[Officer]|h %s: "
CHAT_PARTY_GET = "|Hchannel:party|h[Party]|h %s: "
CHAT_RAID_GET = "|Hchannel:raid|h[Raid]|h %s: "
CHAT_RAID_LEADER_GET = "|Hchannel:raid|h[Raid Leader]|h %s: "
CHAT_RAID_WARNING_GET = "[Raid Warning] %s: "
CHAT_SAY_GET = "%s says: "
CHAT_YELL_GET = "%s yells: "
CHAT_WHISPER_GET = "%s whispers: "
CHAT_WHISPER_INFORM_GET = "To %s: "

ChatTypeGroup = { GUILD = { "CHAT_MSG_GUILD" }, RAID = { "CHAT_MSG_RAID" } }
--[[ **Which message groups the chat settings offer**, and the client's list is
     longer than the obvious ones.

     Modelled with entries outside the five the separator touches -- loot, system
     messages, creature emotes -- because that is where the bug lived: replacing
     this table with a hardcoded list of the obvious groups makes every other one
     unselectable and drops it from what the client saves.

     A stub carrying only the five would have agreed with the code that replaced
     them, and the loss would have been invisible. ]]--
ChannelMenuChatTypeGroups = {
    "SAY", "YELL", "GUILD", "OFFICER", "WHISPER", "PARTY", "RAID",
    "BATTLEGROUND", "LOOT", "SYSTEM", "MONSTER_SAY", "SKILL",
}

Stub.gameTime = { hour = 12, minute = 30 }

function GetGameTime() return Stub.gameTime.hour, Stub.gameTime.minute end

--[[ **The zone name as the minimap shows it**, which is not always the real
     zone: a subzone replaces it, which is why the client has a call of its own
     for the label rather than reading `GetRealZoneText`. ]]--
function GetMinimapZoneText()
    return Stub.minimapZone or Stub.realZone or "Elwynn Forest"
end

--[[ Atlas's own saved options, because this addon bundles Atlas and switches
     its map pins through the flag Atlas already reads. ]]--
AtlasCFMOptions = AtlasCFMOptions or { ShowMapMarkers = true }

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", nil,
        "GameTooltipTemplate")

--[[ **The other tooltips**, which are separate frames with separate backdrops
     and separate font strings -- which is exactly why styling `GameTooltip`
     never reached them.

     `ItemRefTooltip` is what a chat link opens. The two `ShoppingTooltip` frames
     are the "Currently Equipped" panels that appear beside a comparison. Absent
     here, so nothing could notice that an item clicked in chat came up in the
     client's own blue-and-gold next to an ECO-skinned one. ]]--
for _, name in ipairs({ "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
    local tip = CreateFrame("GameTooltip", name, nil, "GameTooltipTemplate")
    tip:Hide()
    _G[name] = tip
end

--[[ **Hidden at rest, which is what a tooltip is nearly all of the time.**

     Every frame this stub makes starts shown, and for most of them that is a
     harmless default. Not for this one: the Tooltip module hangs an `OnUpdate`
     on GameTooltip that re-scans, re-measures and re-anchors the whole thing
     every frame it is *shown*, and a permanently-shown tooltip means that ran on
     every tick of every test. It cost nothing while `GameTooltipStatusBar` did
     not exist, because the expensive half returned immediately; modelling the
     bar doubled the suite's runtime and none of that work was real.

     A test that wants the visible path asks for it with `GameTooltip:Show()`. ]]--
GameTooltip:Hide()

--[[ **The tooltip's health bar**, which the Tooltip module re-anchors, resizes,
     borders and writes a number onto -- and which was not modelled at all, so
     none of that pass had ever been executed by the suite.

     A real StatusBar with a real frame level, because the faults it grew are
     both about *level*: the border is drawn on a child frame above the bar, so
     an OVERLAY font string on the bar itself is still underneath it. A stub
     without levels would let that pass. ]]--
GameTooltipStatusBar = CreateFrame("StatusBar", "GameTooltipStatusBar",
        GameTooltip)
GameTooltipStatusBar.frameType = "StatusBar"
GameTooltipStatusBar:SetHeight(12)
GameTooltipStatusBar:SetMinMaxValues(0, 100)
GameTooltipStatusBar:SetValue(100)
_G["GameTooltipStatusBar"] = GameTooltipStatusBar

--[[ Addon messages the addon sends. Recorded rather than delivered: what is
     worth asserting is that the request went out, on the right channel, with
     the right payload -- the reply is the server's business. ]]--
Stub.addonSent = {}

function SendAddonMessage(prefix, message, channel)
    table.insert(Stub.addonSent, { prefix = prefix, message = message,
                                   channel = channel })
end

--[[ **Console variables**, which are the client's own settings and are global,
     persistent and shared with every other addon.

     Seeded with the defaults that matter rather than left empty, so a module
     that reads one before writing it gets a number instead of nil -- which is
     what happens in game, and is the difference between a slider that starts
     where the client is and one that starts at zero. ]]--
Stub.cvars = {
    cameraYawMoveSpeed = "180",

    --[==[ **The two zoom cvars, which are the only clue to being indoors.**

         There is no `IsIndoors` on this client. `minimapInsideZoom` is the zoom
         the client snaps to indoors, so a current zoom equal to it means
         indoors -- and when the two are equal the question has no answer, which
         is a case worth being able to set up. ]==]
    --[[ The realm, which the auction house keys its notes by. Present here
       because this client has it -- the point of the list is that a name not on
       it fails the way it fails in game. ]]--
    realmName = "Turtle WoW",

    minimapZoom = "0",
    minimapInsideZoom = "3",
    rotateMinimap = "0",

    --[[ **Off, as it is in the client.** This is the switch that decides whether
         Blizzard shows the numbers on a unit frame bar at all, and with it off
         `TextStatusBar_UpdateTextString` hides every string it writes. A stub
         that shipped it on would hide the case where a port's text is written
         correctly and then never seen. ]]--
    statusBarText = "0",
}

function SetCVar(name, value) Stub.cvars[name] = tostring(value) end
--[==[ **An unknown CVar raises. It does not answer nil.**

     From a real reload: `Couldn't find CVar named 'rotateMinimap'`. A stub that
     handed back nil for a name the client does not have agreed with every
     unguarded `GetCVar` in the addon -- including one inside `LoadConfig`, where
     the cost is the addon not loading rather than one feature misbehaving.

     `Stub.cvars` is therefore the whole list of names this client knows, and
     asking for anything else fails the way it fails in game. ]==]
function GetCVar(name)
    local value = Stub.cvars[name]
    if value == nil then
        error("Couldn't find CVar named '" .. tostring(name) .. "'")
    end
    return value
end

--[[ **Bags, and the one call that means two completely different things.**

     `UseContainerItem` sells an item while a merchant window is open and *uses*
     it everywhere else -- eats the food, opens the lockbox, equips the weapon.
     Modelled with that split intact rather than as a "sell" function, because a
     stub that only ever sold would agree with code that forgot to check the
     window was open, and the failure in game is a bag of used items.

     Bags 0 to 4: the backpack and four bags, which is every bag 1.12 has. ]]--
Stub.bags = {}
Stub.used = {}
Stub.sold = {}

--[[ Quality colours as the client defines them. Only poor matters here, and it
     matters exactly: the junk sweep recognises an item by the colour its link
     starts with. ]]--
ITEM_QUALITY_COLORS = {
    [0] = { r = 0.55, g = 0.55, b = 0.55, hex = "|cff9d9d9d" },
    [1] = { r = 1.00, g = 1.00, b = 1.00, hex = "|cffffffff" },
    [2] = { r = 0.12, g = 1.00, b = 0.00, hex = "|cff1eff00" },
    [3] = { r = 0.00, g = 0.44, b = 0.87, hex = "|cff0070dd" },
    [4] = { r = 0.64, g = 0.21, b = 0.93, hex = "|cffa335ee" },

    --[[ Legendary and artifact. Absent until something asked for one and then
         indexed nil, which is a crash rather than a wrong colour -- and the
         thing that asked was a test putting a legendary in a bag, which is not
         an unreasonable thing to want to do. ]]--
    [5] = { r = 1.00, g = 0.50, b = 0.00, hex = "|cffff8000" },
    [6] = { r = 0.90, g = 0.80, b = 0.50, hex = "|cffe6cc80" },
}

--[[ **Every item has its own id**, derived from its name and remembered.

     This spelled `item:1234` into every link, so two different items in a bag
     were the same item to anything reading the id -- and the id is the only
     stable name an item has, because names are localised and shared. Anything
     keyed by item, which is what favourites, pins and custom groups all are,
     could not be tested at all: marking one thing marked everything.

     Assigned on first sight and kept, so the same name is the same id for the
     rest of the run the way it is for the rest of the expansion. A test that
     wants a particular id sets `Stub.itemIds[name]` before asking. ]]--
Stub.itemIds = {}
Stub.nextItemId = 1234

function Stub.ItemId(name)
    if not Stub.itemIds[name] then
        Stub.nextItemId = Stub.nextItemId + 1
        Stub.itemIds[name] = Stub.nextItemId
    end
    return Stub.itemIds[name]
end

--[[ A link, spelled the way the client spells one: quality colour, item id,
     bracketed name, terminator. The sweep reads the colour off the front and the
     name out of the brackets, so both have to be in the right places. ]]--
function Stub.ItemLink(name, quality)
    local colour = ITEM_QUALITY_COLORS[quality or 0] or ITEM_QUALITY_COLORS[0]
    return colour.hex .. "|Hitem:" .. Stub.ItemId(name) .. ":0:0:0|h["
            .. name .. "]|h|r"
end

function Stub.SetBag(bag, items)
    Stub.bags[bag] = items
end


--[[ **The client's own bag windows**, which an addon that colours item borders
     has to find by name.

     `MAX_CONTAINER_ITEMS` is how many buttons a container frame carries -- the
     client builds every one of them for the largest bag and shows as many as
     the bag has.

     **The buttons are numbered backwards**, and that is not a detail. The
     client lays a bag out bottom-right to top-left, so `ContainerFrame1Item1`
     is the *last* slot, and code that colours by its loop counter instead of by
     `GetID` puts the right border on the wrong item. Modelled the awkward way
     round on purpose: a stub that numbered them 1, 2, 3 would let that bug
     through, which is exactly how the square minimap passed its test while
     being broken. ]]--
MAX_CONTAINER_ITEMS = 20

for bag = 1, 2 do
    local frame = CreateFrame("Frame", "ContainerFrame" .. bag, UIParent)
    frame:SetID(bag)
    frame:Hide()

    for i = 1, MAX_CONTAINER_ITEMS do
        local button = CreateFrame("Button", "ContainerFrame" .. bag .. "Item" .. i,
                frame)

        --[==[ **Every item button has a ring**, and it is the button's normal
             texture -- the metal frame the client draws round the icon. It was
             not modelled here, so code that colours the frame the interface
             already has could not be tested at all, while code that hung a
             second frame outside it could. ]==]
        button:SetNormalTexture("Interface" .. "\\Buttons" .. "\\UI-Slot-Background")

        button:SetWidth(30)
        button:SetHeight(30)
        button:SetID(MAX_CONTAINER_ITEMS - i + 1)
    end
end

--[[ Opening a bag is a global every container shares, which is why an addon
     wraps it once rather than per frame. ]]--
function ContainerFrame_OnShow()
    Stub.containersShown = (Stub.containersShown or 0) + 1
end

--[[ The bank, twenty-eight slots, keyed as bag -1 by every container call. ]]--
BankFrame = CreateFrame("Frame", "BankFrame", UIParent)
BankFrame:Hide()

for i = 1, 28 do
    local button = CreateFrame("Button", "BankFrameItem" .. i, BankFrame)
    button:SetNormalTexture("Interface" .. "\\Buttons" .. "\\UI-Slot-Background")
    button:SetWidth(30)
    button:SetHeight(30)
    button:SetID(i)
end

--[[ **The paperdoll**, whose slots are numbered rather than linked: an equipped
     item's quality is asked for by slot, not taken apart out of a link. ]]--
Stub.inventoryQuality = {}

--[==[ **The unit is not decoration.**

     This ignored it and answered the player's gear for every unit asked about,
     which is exactly the shape of absence that lets a bug through: the inspect
     borders could read `"player"` and look correct in the harness while showing
     your own gear on somebody else's frame in the game. A stub that drops an
     argument agrees with a caller that gets it wrong. ]==]
Stub.inspectQuality = {}

function GetInventoryItemQuality(unit, slot)
    if unit and unit ~= "player" then return Stub.inspectQuality[slot] end
    return Stub.inventoryQuality[slot]
end

for slot, name in pairs({ [0] = "AmmoSlot", "HeadSlot", "NeckSlot",
        "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot", "LegsSlot",
        "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot",
        "Trinket0Slot", "Trinket1Slot", "BackSlot", "MainHandSlot",
        "SecondaryHandSlot", "RangedSlot", "TabardSlot" }) do
    local button = CreateFrame("Button", "Character" .. name, UIParent)
    button:SetNormalTexture("Interface" .. "\\Buttons" .. "\\UI-Slot-Background")
    button:SetWidth(36)
    button:SetHeight(36)
    button:SetID(slot)
end

--[==[ **The inspect window, which the client loads only when somebody uses it.**

     `InspectFrame_LoadUI` creates Blizzard_InspectUI on first inspect, so at
     bind time none of this exists. Modelled as present-but-hidden: the frames
     are real so a test can show them, and the load-on-demand timing is covered
     separately by the hook that installs on that function. ]==]
InspectFrame = CreateFrame("Frame", "InspectFrame", UIParent)
InspectFrame:Hide()

--[==[ **The map's own picture, which is the rectangle a click is a fraction
     of.**

     `waypoints.lua` measures the cursor against `WorldMapDetailFrame` rather
     than `WorldMapButton` -- the button is the click target and the detail frame
     is the drawn map -- and this was not modelled at all. `tests/run.lua`
     creates one itself in the waypoint block, which works there and means every
     other test in the file sees a map click that cannot resolve a position at
     all.

     Sized to the client's own 1002x668 map area. The accessors are overridden
     the way the test's local copy did, because a stub frame has no real screen
     rectangle and the conversion needs one. ]==]
WorldMapDetailFrame = CreateFrame("Frame", "WorldMapDetailFrame", WorldMapButton)
WorldMapDetailFrame:SetWidth(1002)
WorldMapDetailFrame:SetHeight(668)
WorldMapDetailFrame.GetLeft = function() return 0 end
WorldMapDetailFrame.GetTop = function() return 668 end
WorldMapDetailFrame.GetEffectiveScale = function() return 1 end

for slot, name in pairs({ [0] = "AmmoSlot", "HeadSlot", "NeckSlot",
        "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot", "LegsSlot",
        "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot",
        "Trinket0Slot", "Trinket1Slot", "BackSlot", "MainHandSlot",
        "SecondaryHandSlot", "RangedSlot", "TabardSlot" }) do
    local button = CreateFrame("Button", "Inspect" .. name, InspectFrame)
    button:SetNormalTexture("Interface" .. "\\Buttons" .. "\\UI-Slot-Background")
    button:SetWidth(37)
    button:SetHeight(37)
    button.eqStubSlot = slot
end

--[==[ **The client filling one inspect slot, which is the moment the borders
     have to be painted.**

     A single pass when the window opens runs before the server has answered, so
     the borders would be right only for gear the client happened to have cached
     already. `InspectPaperDollItemSlotButton_Update` is called **per slot, as
     each one arrives**, which is why the rarity work wraps it.

     **It was not modelled**, so `InstallInspectRarity` fell past its wrap to the
     on-show fallback in every test that has ever run -- the fallback being
     exactly the pass that is too early to be right. The interesting half was
     never exercised.

     Modelled as the client's own: it fills the slot's icon from whatever is
     equipped and does nothing about rarity, because rarity is what the addon is
     adding. ]==]
Stub.inspectSlotUpdates = {}

function InspectPaperDollItemSlotButton_Update(button)
    button = button or this
    if not button then return end

    table.insert(Stub.inspectSlotUpdates, button.eqStubName or "?")

    local icon = button.GetName and getglobal(button:GetName() .. "IconTexture")
    if icon and icon.SetTexture then icon:SetTexture("Interface\\Icons\\Temp") end

    return true
end

--[==[ **Loading the inspect UI, which happens on first use and therefore always
     after this addon binds.**

     That timing is the whole of a bug already fixed here: `OnBind`'s own comment
     said the lazy hook would install the rarity borders later, and it did not --
     it installed the model rotation and stopped. On a stock client, where this
     function creates `Blizzard_InspectUI` the first time somebody inspects, the
     borders were therefore never installed at all.

     A fix for that shape needs this call to exist or nothing can drive it. ]==]
Stub.inspectUILoaded = 0

function InspectFrame_LoadUI()
    Stub.inspectUILoaded = Stub.inspectUILoaded + 1
    return true
end
function GetContainerNumSlots(bag)
    local b = Stub.bags[bag]
    if not b then return 0 end
    return b.slots or table.getn(b)
end

function GetContainerItemLink(bag, slot)
    local b = Stub.bags[bag]
    local item = b and b[slot]
    if not item then return nil end

    return Stub.ItemLink(item.name, item.quality)
end

--[[ Texture, count, locked -- and no price, which is the whole difficulty of
     "destroy cheap junk". 1.12 has no call that answers what an item sells for. ]]--
--[==[ **The third return is `locked`, and it was always nil.**

     An item is locked while it is in flight -- picked up, or being moved by
     something else -- and picking up a locked item does nothing. Code that
     checked and code that did not looked identical here, so a mover that retried
     a locked slot for ever would have passed. ]==]
function GetContainerItemInfo(bag, slot)
    local b = Stub.bags[bag]
    local item = b and b[slot]
    if not item then return nil end

    return "Interface\\Icons\\INV_Misc_Bone_01", item.count or 1,
            item.locked or nil
end

function UseContainerItem(bag, slot)
    local b = Stub.bags[bag]
    local item = b and b[slot]
    if not item then return end

    if MerchantFrame and MerchantFrame:IsVisible() then
        table.insert(Stub.sold, item.name)
    else
        table.insert(Stub.used, item.name)
    end
end

--[[ **Destroying an item, which in 1.12 is two calls and a cursor.**

     There is no `DeleteItem(bag, slot)`. You pick the item up and then delete
     what you are holding, which means the cursor is a real piece of state
     between the two -- and `PickupContainerItem` onto an occupied cursor
     *swaps*, putting what you held into the bag and picking up the item.

     Modelled with that swap intact. A stub whose pickup simply overwrote the
     cursor would agree with code that deleted the wrong thing, and the wrong
     thing here is whatever the player happened to be dragging. ]]--
Stub.cursor = nil
Stub.destroyed = {}

function CursorHasItem() return Stub.cursor ~= nil end
--[[ Putting a lifted item back: its slot unlocks and nothing moved. ]]--
function ClearCursor()
    local held = Stub.cursor
    if held and held.item then held.item.locked = nil end
    Stub.cursor = nil
end

--[[ The client's own move rules, which this had wrong. A pickup onto an empty
     cursor lifts the item and locks its slot. A pickup with something on the
     cursor is a drop: into an empty slot it lands there; onto the same kind of
     item it merges up to the stack size; onto a different item the two trade
     places. In every drop case the cursor is empty afterwards and both slots
     stay locked until `Stub.SettleBags`, which is the server confirming. ]]--
function PickupContainerItem(bag, slot)
    local b = Stub.bags[bag]
    if not b then return end

    local here = b[slot]
    local held = Stub.cursor

    if not held then
        if here then
            here.locked = true
            Stub.cursor = { item = here, bag = bag, slot = slot }
        end
        return
    end

    local from = Stub.bags[held.bag]
    local item = held.item
    Stub.cursor = nil

    if not here then
        b[slot] = item
        if from then from[held.slot] = nil end
    elseif here ~= item and here.name == item.name then
        local known = Stub.items[Stub.ItemId(item.name)]
        local max = known and known.maxStack or 1
        local room = max - (here.count or 1)
        local moving = item.count or 1
        if room >= moving then
            here.count = (here.count or 1) + moving
            if from then from[held.slot] = nil end
        else
            here.count = max
            item.count = moving - room
        end
        here.locked = true
    elseif here ~= item then
        b[slot] = item
        if from then from[held.slot] = here end
        here.locked = true
    end

    item.locked = true
end

--[[ The server confirming every move in flight: every lock clears. ]]--
function Stub.SettleBags()
    for _, b in pairs(Stub.bags) do
        if type(b) == "table" then
            for _, it in pairs(b) do
                if type(it) == "table" then it.locked = nil end
            end
        end
    end
end

function DeleteCursorItem()
    if not Stub.cursor then return end

    local held = Stub.cursor
    local name = held.name or (held.item and held.item.name)
    table.insert(Stub.destroyed, name)

    local from = held.bag and Stub.bags[held.bag]
    if from and held.slot then from[held.slot] = nil end
    Stub.cursor = nil
end

--[[ The merchant, and repairing at one. `GetRepairAllCost` answers copper and
     whether there is anything to repair; `RepairAllItems` takes the money. The
     money is really taken, so a test can assert that a repair somebody could not
     afford did not happen to their purse. ]]--
MerchantFrame = CreateFrame("Frame", "MerchantFrame", nil)

--[[ The merchant window pages, and `selectedTab` is the field its own update
     reads: 1 is buy, 2 is buyback. Unmodelled, anything keyed on which tab is
     showing could only ever be tested by not testing it. ]]--
MerchantFrame.selectedTab = 1
MerchantFrame:Hide()

--[==[ **The client's own repair pair, which ECO now anchors beside.**

     `MerchantRepairItemButton` and `MerchantRepairAllButton` sit in a labelled
     row at the top of the merchant window. They were not modelled, so a reader
     that anchored to them and a reader that did not both landed on the fallback
     -- and the fallback is the case that only happens at a merchant who cannot
     repair at all. ]==]
MerchantRepairItemButton = CreateFrame("Button", "MerchantRepairItemButton",
        MerchantFrame)
MerchantRepairItemButton:SetWidth(36)
MerchantRepairItemButton:SetHeight(36)

MerchantRepairAllButton = CreateFrame("Button", "MerchantRepairAllButton",
        MerchantFrame)
MerchantRepairAllButton:SetWidth(36)
MerchantRepairAllButton:SetHeight(36)
--[==[ **Anchored the way the client anchors them, which is the reverse of what
     this stub used to say.**

     From the client's own `MerchantFrame.xml`: `MerchantRepairAllButton` is
     anchored to the *frame*, and `MerchantRepairItemButton` hangs off **its**
     left. So All is the right-hand one of the pair and is the one that carries
     the row's position.

     It mattered the moment something moved the row: moving the frame-anchored
     button moves both, and a stub with the dependency the other way round would
     have agreed with a fix that moved one and left the other behind. ]==]
MerchantRepairAllButton:ClearAllPoints()
MerchantRepairAllButton:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMLEFT", 172, 91)

MerchantRepairItemButton:ClearAllPoints()
MerchantRepairItemButton:SetPoint("RIGHT", MerchantRepairAllButton, "LEFT", -2, 0)

--[==[ **`MerchantFrame_Update`, which is what a tab change actually is.**

     Switching to buyback sends no event. It calls this. A stub without it could
     not tell the difference between a check that runs on a tab change and one
     that only ever ran when the window opened -- which is exactly the bug that
     left the junk button sitting on the buyback tab. ]==]
function MerchantFrame_Update()
    return true
end

--[[ Item-slot art, drawn at the button's own size. ECO reads this off the
     button it anchors to so its own junk button matches, so a stub where the
     neighbours wear nothing would exercise only the fallback. ]]--
for _, b in ipairs({ MerchantRepairItemButton, MerchantRepairAllButton }) do
    b:SetNormalTexture("Interface\\Buttons\\UI-Slot-Background")
    b:GetNormalTexture():SetWidth(36)
    b:GetNormalTexture():SetHeight(36)
end

--[[ The row's label, which ECO hides to make room for the junk button. Modelled
     because "is it hidden" is the assertion, and an unmodelled frame cannot be
     asked. ]]--
MerchantRepairText = CreateFrame("Frame", "MerchantRepairText", MerchantFrame)

Stub.money = 1000000
Stub.repairCost = 0
Stub.canRepair = true
Stub.repaired = 0

function GetMoney() return Stub.money end
function CanMerchantRepair() return Stub.canRepair end
function GetRepairAllCost() return Stub.repairCost, Stub.repairCost > 0 end

function RepairAllItems()
    Stub.money = Stub.money - Stub.repairCost
    Stub.repaired = Stub.repaired + 1
    Stub.repairCost = 0
end

function GetScreenWidth() return 1024 end
function GetScreenHeight() return 768 end


--[[ **`gcinfo` is how 1.12 answers "how much memory is Lua using".**

     Two returns: kilobytes in use, and the collection threshold. Kilobytes, and
     rounded -- so a single cheap call reads as zero and only a great many of
     them add up to a number. That coarseness is the reason the profiler counts
     calls beside the bytes rather than trusting one sample.

     Driven from `Stub.luaMemory` so a test can make a function allocate a known
     amount and check the profiler attributed it to the right name. ]]--
Stub.luaMemory = 1000

function gcinfo() return Stub.luaMemory, 2000 end
function GetTime() return clock end
function GetCursorPosition() return Stub.cursorX or 0, Stub.cursorY or 0 end

--[==[ **Turning the camera with the mouse**, which is what a drag over the world
     does and what a drag over a frame could not.

     Modelled as the state it is rather than as a pair of calls that vanish:
     `IsMouselooking` is the question anything stopping a turn has to ask, and a
     stub that swallowed the two setters would agree with a port that started a
     turn and never ended one -- a hidden cursor and no way back. ]==]
Stub.mouselooking = false

function MouselookStart() Stub.mouselooking = true end
function MouselookStop() Stub.mouselooking = false end
function IsMouselooking() return Stub.mouselooking end

--[[ **The character model frames, and which way they are facing.**

     1.12 puts a character in one of these and gives you two arrow buttons to
     turn it. `GetFacing` and `SetFacing` have always been there -- TomTom reads
     the player's heading off the minimap's model with exactly this pair -- and
     what has never existed is a way to drag it.

     Facing is radians and wraps; the client does not clamp it and neither does
     this, because code that assumed a range would be assuming one the client
     does not enforce. ]]--
Stub.mouseDown = {}

function IsMouseButtonDown(button)
    if not button then return Stub.mouseDown["LeftButton"] and true or false end
    return Stub.mouseDown[button] and true or false
end

for _, name in ipairs({ "CharacterModelFrame", "DressUpModel", "InspectModelFrame" }) do
    local model = CreateFrame("Model", name, nil)
    model.facing = 0
    model.SetFacing = function(self, value) self.facing = value or 0 end
    model.GetFacing = function(self) return self.facing end
    _G[name] = model
end
--[[ Counted as well as named. One sound is a feature; the same sound twice a
     second is the bug this counter exists to catch, and `lastSound` alone cannot
     tell those apart. ]]--
function PlaySound(name)
    Stub.lastSound = name
    Stub.soundCount = (Stub.soundCount or 0) + 1
end
function IsAddOnLoaded(name) return Stub.loadedAddons and Stub.loadedAddons[name] end

-- ---------------------------------------------------------------------------
-- globals the client provides
-- ---------------------------------------------------------------------------

_G = _G or getfenv(0)

STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

--[[ **Every cooldown in 1.12 goes through one global.**

     There is no Cooldown frame type in this client -- the sweeping shadow is a
     texture animated by `CooldownFrame_SetTimer`, and each caller passes the
     frame it wants animated. That makes this the only seam an addon has for
     "how long is left", which is why it is modelled here: an addon that wraps
     it has to be checked against something that actually calls it.

     Records rather than animates. What the shadow looks like is the client's
     business; that the right start and duration arrived is ours. ]]--
--[==[ **A container slot's cooldown**, which is the action bar's call with a
     bag and a slot instead of an action.

     Modelled because a bag full of healthstones and a bag full of usable ones
     look identical without it, and an addon that darkens the ones on cooldown
     has to be able to ask. `Stub.itemCooldowns` is keyed "bag:slot" so a test
     can put one slot on cooldown and leave the rest alone. ]==]
Stub.itemCooldowns = {}

function GetContainerItemCooldown(bag, slot)
    local entry = Stub.itemCooldowns[tostring(bag) .. ":" .. tostring(slot)]
    if not entry then return 0, 0, 0 end

    return entry[1] or 0, entry[2] or 0, entry[3] or 1
end

function CooldownFrame_SetTimer(frame, start, duration, enable)
    if not frame then return end

    frame.cooldownStart = start
    frame.cooldownDuration = duration
    frame.cooldownEnable = enable
end

--[[ The refusal strings, exactly as 1.12's GlobalStrings.lua spells them.
     `SPELL_FAILED_LINE_OF_SIGHT` is the one the client puts on screen and passes
     as UI_ERROR_MESSAGE's arg1; the other two do not exist in 1.12 and are left
     undefined on purpose, so anything that reads them has to cope with nil the
     way it must in game. ]]--
SPELL_FAILED_LINE_OF_SIGHT = "Target not in line of sight"

--[[ **The sentences a cast is announced with**, exactly as 1.12's
     GlobalStrings.lua spells them.

     These are the only notice a vanilla client gives that anything other than
     the player has begun casting -- there is no UnitCastingInfo until 2.0 -- so
     they are the entire input to the cast library, and they have to be right
     here rather than approximated for the reason every other global string in
     this file is: a stub with a subtly different sentence exercises a pattern the
     real client never produces. ]]--
SPELLCASTOTHERSTART = "%s begins to cast %s."

--[[ **The sentences that end a cast**, which were absent -- so nothing could
     test that anybody's cast ever stopped, and nothing did. Note the caster is
     the *second* name in an interrupt and the first in a death: getting that
     round the wrong way ends the interrupter's cast instead. ]]--
UNITDIESOTHER = "%s dies."
UNITDESTROYEDOTHER = "%s is destroyed."
SPELLINTERRUPTOTHEROTHER = "%s interrupts %s's %s."
SPELLINTERRUPTSELFOTHER = "You interrupt %s's %s."
SPELLPERFORMOTHERSTART = "%s begins to perform %s."

--[[ The combat log sentences, exactly as 1.12's GlobalStrings.lua spells them.

     These are the parser's entire input. It never matches English -- it turns
     *these* into patterns, so whatever the client says is what it reads -- and
     that is precisely why they have to be right here rather than approximated:
     a stub with a subtly different sentence would exercise a pattern the real
     client never produces.

     `%2$s` in RESIST_TRAILER is not a typo. Reordering indices are the thing
     `captures` exists to handle, so at least one string carrying them earns its
     place. ]]--
COMBATHITSELFOTHER = "You hit %s for %d."
COMBATHITCRITSELFOTHER = "You crit %s for %d."
COMBATHITSCHOOLSELFOTHER = "You hit %s for %d %s damage."
COMBATHITCRITSCHOOLSELFOTHER = "You crit %s for %d %s damage."

COMBATHITOTHERSELF = "%s hits you for %d."
COMBATHITCRITOTHERSELF = "%s crits you for %d."
COMBATHITSCHOOLOTHERSELF = "%s hits you for %d %s damage."
COMBATHITCRITSCHOOLOTHERSELF = "%s crits you for %d %s damage."

COMBATHITOTHEROTHER = "%s hits %s for %d."
COMBATHITCRITOTHEROTHER = "%s crits %s for %d."
COMBATHITSCHOOLOTHEROTHER = "%s hits %s for %d %s damage."
COMBATHITCRITSCHOOLOTHEROTHER = "%s crits %s for %d %s damage."

SPELLLOGSELFOTHER = "Your %s hits %s for %d."
SPELLLOGCRITSELFOTHER = "Your %s crits %s for %d."
SPELLLOGSCHOOLSELFOTHER = "Your %s hits %s for %d %s damage."
SPELLLOGCRITSCHOOLSELFOTHER = "Your %s crits %s for %d %s damage."

SPELLLOGSELFSELF = "Your %s hits you for %d."
SPELLLOGCRITSELFSELF = "Your %s crits you for %d."
SPELLLOGSCHOOLSELFSELF = "Your %s hits you for %d %s damage."
SPELLLOGCRITSCHOOLSELFSELF = "Your %s crits you for %d %s damage."

SPELLLOGOTHERSELF = "%s's %s hits you for %d."
SPELLLOGCRITOTHERSELF = "%s's %s crits you for %d."
SPELLLOGSCHOOLOTHERSELF = "%s's %s hits you for %d %s damage."
SPELLLOGCRITSCHOOLOTHERSELF = "%s's %s crits you for %d %s damage."

SPELLLOGOTHEROTHER = "%s's %s hits %s for %d."
SPELLLOGCRITOTHEROTHER = "%s's %s crits %s for %d."
SPELLLOGSCHOOLOTHEROTHER = "%s's %s hits %s for %d %s damage."
SPELLLOGCRITSCHOOLOTHEROTHER = "%s's %s crits %s for %d %s damage."

PERIODICAURADAMAGESELFOTHER = "%s suffers %d %s damage from your %s."
PERIODICAURADAMAGESELFSELF = "You suffer %d %s damage from your %s."
PERIODICAURADAMAGEOTHERSELF = "You suffer %d %s damage from %s's %s."
PERIODICAURADAMAGEOTHEROTHER = "%s suffers %d %s damage from %s's %s."

DAMAGESHIELDSELFOTHER = "You reflect %d %s damage to %s."
DAMAGESHIELDOTHERSELF = "%s reflects %d %s damage to you."
DAMAGESHIELDOTHEROTHER = "%s reflects %d %s damage to %s."

HEALEDSELFSELF = "Your %s heals you for %d."
HEALEDCRITSELFSELF = "Your %s critically heals you for %d."
HEALEDSELFOTHER = "Your %s heals %s for %d."
HEALEDCRITSELFOTHER = "Your %s critically heals %s for %d."

HEALEDOTHERSELF = "%s's %s heals you for %d."
HEALEDCRITOTHERSELF = "%s's %s critically heals you for %d."
HEALEDOTHEROTHER = "%s's %s heals %s for %d."
HEALEDCRITOTHEROTHER = "%s's %s critically heals %s for %d."

PERIODICAURAHEALSELFSELF = "You gain %d health from %s."
PERIODICAURAHEALSELFOTHER = "%s gains %d health from your %s."
PERIODICAURAHEALOTHERSELF = "You gain %d health from %s's %s."
PERIODICAURAHEALOTHEROTHER = "%s gains %d health from %s's %s."

ABSORB_TRAILER = " (%d absorbed)"
RESIST_TRAILER = " (%d resisted)"

-- `UnitXP` is set up by Stub.SetUnitXP, which models both the stock experience
-- API and UnitXP_SP3's dispatcher. See the note there.

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
}

Stub.chat = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, msg) table.insert(Stub.chat, msg) end,
}

function getglobal(name) return _G[name] end
function setglobal(name, v) _G[name] = v end
tinsert = table.insert
tremove = table.remove

UISpecialFrames = {}
UIPanelWindows = {}
SlashCmdList = {}

--[[ **What the Key Bindings panel can actually do**, which is what a chat
     command bound to a binding ends up calling.

     Recorded rather than simulated: there is no character to sit down, and what
     is worth asserting is that the right call was made. Each one records itself
     so a command can be traced end to end -- typed word, stored action, client
     API.

     **`RunBinding` is deliberately absent.** Vanilla has no way to invoke a
     binding by name; later clients grew one and some private servers back-port
     it. A stub that shipped it would let the fallback table -- the path almost
     every 1.12 player is actually on -- go untested. `Stub.runBinding` turns it
     on for the test that checks the other branch. ]]--
Stub.ran = {}

local function records(name)
    return function(arg)
        table.insert(Stub.ran, name)
        Stub.lastRan = name
        Stub.lastRanArg = arg
    end
end

ToggleRun = records("ToggleRun")
ToggleAutoRun = records("ToggleAutoRun")
ToggleSheath = records("ToggleSheath")
JumpOrAscendStart = records("JumpOrAscendStart")
Dismount = records("Dismount")
Screenshot = records("Screenshot")
Sound_ToggleMusic = records("Sound_ToggleMusic")
Sound_ToggleSound = records("Sound_ToggleSound")
--[[ **The framerate readout, which toggles rather than sets.** The client
     exposes no way to ask for it *on* -- only to flip it -- so an addon that
     wants it shown has to read the frame first and flip only if it is not.
     Modelled with a real frame for exactly that: a stub that only recorded the
     call could not tell "turned it on" from "turned it off". ]]--
FramerateFrame = CreateFrame("Frame", "FramerateFrame", UIParent)
FramerateFrame:Hide()

function ToggleFramerate()
    table.insert(Stub.ran, "ToggleFramerate")
    Stub.lastRan = "ToggleFramerate"

    if FramerateFrame:IsShown() then
        FramerateFrame:Hide()
    else
        FramerateFrame:Show()
    end
end
--[==[ **Every way the client opens a bag.**

     Only two of these were here, as bare recorders, and an addon that means to
     replace the bag windows has to take all of them -- the menu bar's bag
     buttons go through `ToggleBag`, a vendor goes through `OpenAllBags`, and
     the keyring has its own. A stub with two of them lets a takeover that
     misses the other eight pass.

     Recorders rather than working windows: what a test needs to know is whether
     the client's own path ran or was taken over, and the name landing in
     `Stub.ran` is exactly that. ]==]
ToggleBackpack = records("ToggleBackpack")
OpenBackpack = records("OpenBackpack")
CloseBackpack = records("CloseBackpack")
ToggleBag = records("ToggleBag")
OpenBag = records("OpenBag")
CloseBag = records("CloseBag")
OpenAllBags = records("OpenAllBags")
CloseAllBags = records("CloseAllBags")
ToggleKeyRing = records("ToggleKeyRing")
IsBagOpen = records("IsBagOpen")

--[[ The client's translation from a container number to the equipment slot the
     bag hangs in. The backpack has none -- it cannot be taken off. ]]--
function ContainerIDToInventoryID(bag)
    bag = tonumber(bag)
    if not bag or bag < 1 or bag > 4 then return nil end
    return bag + 19
end

NUM_CONTAINER_FRAMES = 12

--[[ The menu bar's bag buttons, which draw pressed in while a bag is open. The
     client keeps them in step from `ContainerFrame_OnHide`; an addon that stops
     those frames ever showing has to keep them in step itself. ]]--
MainMenuBarBackpackButton = CreateFrame("Button", "MainMenuBarBackpackButton",
        UIParent)

for i = 0, 3 do
    CreateFrame("Button", "CharacterBag" .. i .. "Slot", UIParent)
end

PutItemInBackpack = records("PutItemInBackpack")
PutItemInBag = records("PutItemInBag")
PickupBagFromSlot = records("PickupBagFromSlot")
ToggleWorldMap = records("ToggleWorldMap")
ToggleQuestLog = records("ToggleQuestLog")
ToggleTalentFrame = records("ToggleTalentFrame")
ToggleFriendsFrame = records("ToggleFriendsFrame")
ToggleGameMenu = records("ToggleGameMenu")
ToggleCharacter = records("ToggleCharacter")
ToggleSpellBook = records("ToggleSpellBook")
DoEmote = records("DoEmote")

--[[ **Vanilla does not have `SitStandOrDescendStart`**, which is why the sit
     action tries it and falls back to the emote. Left undefined so the fallback
     is what a test gets without asking for it. ]]--

BOOKTYPE_SPELL = "spell"
BOOKTYPE_PET = "pet"

--[[ The client's own labels for its bindings, which is the string somebody read
     in the Key Bindings panel before coming to name a command after it. Only a
     few, because the point is that the label is looked up rather than written
     out -- a binding with no label falls back to its command name, and that
     path matters as much. ]]--
BINDING_NAME_TOGGLERUN = "Toggle Run/Walk"
BINDING_NAME_SITORSTAND = "Sit/Stand"
BINDING_NAME_TOGGLESHEATH = "Sheath/Unsheath Weapon"
BINDING_NAME_TOGGLEAUTORUN = "Toggle Autorun"

Stub.framerate = 60
Stub.latency = 42

function GetFramerate() return Stub.framerate end
function GetNetStats() return 0, 0, Stub.latency end

--[[ Combat logging, which the client exposes as one call that both reads and
     writes: no argument queries, an argument sets and answers with what it
     ended up as. Modelled that way because the toggle is written against
     it. ]]--
Stub.combatLogging = false

function LoggingCombat(on)
    if on == nil then return Stub.combatLogging end

    Stub.combatLogging = on and true or false
    return Stub.combatLogging
end

--[[ The chat edit box, which `/hud` moves onto WorldFrame while the interface is
     hidden -- otherwise the command that brings the interface back cannot be
     typed. Real, because that reparenting is the whole of the feature and a
     missing edit box would make it a no-op that looked like it worked. ]]--
ChatFrameEditBox = CreateFrame("EditBox", "ChatFrameEditBox", UIParent)
ChatFrameEditBox:Hide()

--[[ **The three textures that make the gold frame around it.** Not a backdrop --
     1.12's edit box has none -- which is why removing the border is hiding
     these and adding one of our own rather than recolouring anything. Real,
     because a nil global would make that pass do nothing while looking like it
     had worked. ]]--
for _, piece in ipairs({ "Left", "Mid", "Right",
                         "FocusLeft", "FocusMid", "FocusRight" }) do
    _G["ChatFrameEditBox" .. piece] =
            ChatFrameEditBox:CreateTexture("ChatFrameEditBox" .. piece, "BORDER")

    --[[ With a texture on it, because the client's art has one -- and taking
         it off is only acceptable because the path is remembered first. A stub
         whose art started blank could not tell "remembered and cleared" from
         "there was nothing there". ]]--
    _G["ChatFrameEditBox" .. piece]:SetTexture("BlizzardEditBoxArt-" .. piece)
end

DEFAULT_CHAT_FRAME.editBox = ChatFrameEditBox
DEFAULT_CHAT_FRAME.GetParent = function(self) return self.parent or UIParent end
DEFAULT_CHAT_FRAME.SetParent = function(self, p) self.parent = p end
DEFAULT_CHAT_FRAME.GetFrameStrata = function(self) return self.strata or "LOW" end
DEFAULT_CHAT_FRAME.SetFrameStrata = function(self, s) self.strata = s end
--[[ The word `DELETE_GOOD_ITEM` makes you type. A client global rather than a
     literal, because it is localised. ]]--
DELETE_ITEM_CONFIRM_STRING = "DELETE"

--[[ **How the client states that an item cannot be traded or auctioned.**

     1.12 exposes bind status nowhere else -- `GetItemInfo` does not return it --
     so the only place it is stated is the line the tooltip prints. Localised
     globals rather than literals, which is why anything reading them has to
     compare against these rather than against English. ]]--
ITEM_BIND_ON_PICKUP = "Binds when picked up"
ITEM_BIND_ON_EQUIP = "Binds when equipped"
ITEM_BIND_QUEST = "Quest Item"
ITEM_SOULBOUND = "Soulbound"

StaticPopupDialogs = {}

Stub.popups = {}
function StaticPopup_Show(name)
    table.insert(Stub.popups, name)
    return StaticPopupDialogs[name]
end

--[==[ **A summon and a resurrection are offers, and the client asks them as
     popups with their own accept.**

     Modelled with `OnAccept` calling the real function, because that is the
     whole reason the addon routes these through `StaticPopupDialogs` rather than
     calling `ConfirmSummon` or `AcceptResurrect` itself: it never has to know
     what this build calls them.

     A stub whose dialogs had no `OnAccept` would let a reader that hid the popup
     without accepting anything pass -- which is exactly the bug the loot-roll
     path was written to avoid. ]==]
Stub.summonConfirmed = nil
Stub.resurrectAccepted = nil

function ConfirmSummon() Stub.summonConfirmed = true end
function AcceptResurrect() Stub.resurrectAccepted = true end

StaticPopupDialogs["CONFIRM_SUMMON"] = {
    OnAccept = function() ConfirmSummon() end,
}

--[[ Three names, one question. The client picks between them on whether
     resurrection sickness applies and whether a timer is running. ]]--
for _, name in ipairs({ "RESURRECT_REQUEST", "RESURRECT_REQUEST_NO_SICKNESS",
                        "RESURRECT_REQUEST_TIMER" }) do
    StaticPopupDialogs[name] = {
        OnAccept = function() AcceptResurrect() end,
    }
end

--[[ **The 1.12 loot-roll confirmation is an event before it is a popup.**

     UIParent receives CONFIRM_LOOT_ROLL with the roll id/type in the global
     event arguments. It creates the popup first and only then copies those
     arguments into the returned dialog's data fields. Keeping that ordering in
     the stub catches code that tries to accept the popup inside
     StaticPopup_Show, before the payload exists. ]]--
Stub.uiParentEvents = {}
Stub.confirmedLootRoll = nil

--[==[ **What is being rolled on.**

     Absent entirely, so `AutoRollChoice` -- which decides whether to press Need
     or Greed for you -- could not be exercised at all: it asks the client for
     the item name, got nothing, and returned nothing for every roll. The
     automatic roll lists therefore had no coverage of the only thing they
     exist to do.

     1.12 answers texture, name, count, quality and the bind flag. The name is
     the second return, which is the one worth being exact about: reading it
     out of the first would have looked like a working lookup here. ]==]
Stub.lootRolls = {}

function GetLootRollItemInfo(id)
    local roll = Stub.lootRolls[id]
    if not roll then return nil end

    return roll.texture or "Interface" .. "\\" .. "Icons", roll.name,
            roll.count or 1, roll.quality or 3, roll.bindOnPickUp
end

function GetLootRollItemLink(id)
    local roll = Stub.lootRolls[id]
    if not roll or not roll.name then return nil end

    return Stub.ItemLink(roll.name, roll.quality or 3)
end

--[==[ **The need/greed popup itself**, which was modelled by nothing -- so the
     one tooltip in the interface that reaches `GameTooltip` through
     `SetLootRollItem` had no way of being driven here at all.

     Four of them, because that is what the client builds, and each carries its
     roll id as the frame's own id. The icon is a button and its `OnEnter` is the
     client's: own the tooltip against the icon, then ask for the roll's item.
     That anchor is the part worth modelling -- almost every other tooltip in the
     game goes through `GameTooltip_SetDefaultAnchor`, which this addon wraps and
     re-places, and this one does not. ]==]
for i = 1, 4 do
    local name = "GroupLootFrame" .. i
    local frame = CreateFrame("Frame", name, UIParent)

    frame:SetWidth(240)
    frame:SetHeight(50)
    frame:SetID(0)
    frame:Hide()

    local icon = CreateFrame("Button", name .. "IconFrame", frame)
    icon:SetWidth(37)
    icon:SetHeight(37)
    icon:SetPoint("LEFT", frame, "LEFT", 8, 0)

    icon:SetScript("OnEnter", function()
        local roll = this:GetParent()

        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetLootRollItem(roll:GetID())
    end)

    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    _G[name .. "Name"] = newFontString(frame, "OVERLAY", "GameFontNormal")
end

--[[ Put one on screen for a roll, the way `START_LOOT_ROLL` does. ]]--
function Stub.ShowLootRoll(index, rollID)
    local frame = _G["GroupLootFrame" .. (index or 1)]
    if not frame then return nil end

    frame:SetID(rollID)
    frame:Show()

    local roll = Stub.lootRolls[rollID]
    _G[frame.eqStubName .. "Name"]:SetText(roll and roll.name or "")

    return frame
end

--[==[ **Actually rolling, which is the half nothing here could do.**

     `GetLootRollItemInfo`, `GetLootRollItemLink` and `ConfirmLootRoll` were all
     modelled; `RollOnLoot` was not -- and it is the one the automatic need/greed
     is guarded on. So the whole feature ended at
     `type(RollOnLoot) == "function"` and no test ever reached the part that
     decides what to press.

     That is worth stating plainly, because of every path in this addon it is the
     one where being wrong costs somebody an item: a rule that needs on the wrong
     thing, or greeds on the thing they wanted, is not recoverable.

     Every roll is recorded rather than only the last one -- two items can be up
     at once and a reader that only kept the newest would agree with a rule that
     rolled on one and forgot the other. ]==]
Stub.rolledOnLoot = {}

function RollOnLoot(id, rollType)
    table.insert(Stub.rolledOnLoot, { id = id, rollType = rollType })

    --[[ The client answers the roll it was given, which is what makes the
         confirmation step below reachable at all. ]]--
    Stub.lastRollOnLoot = { id, rollType }
    return true
end

function ConfirmLootRoll(id, rollType)
    Stub.confirmedLootRoll = { id, rollType }
end

function UIParent_OnEvent(event)
    table.insert(Stub.uiParentEvents, event)

    if event == "CONFIRM_LOOT_ROLL" then
        local dialog = StaticPopup_Show("CONFIRM_LOOT_ROLL")
        if dialog then
            dialog.data = arg1
            dialog.data2 = arg2
        end
    end
end

--[[ Accept a popup the way clicking its first button would.

     1.12 calls `OnAccept(dialog.data, dialog.data2)` while the global `this` is
     the accept button. A dialog with `hasEditBox` also grows a child named
     `<dialog>EditBox`, so both the arguments and the button context matter. ]]--
Stub.popupFrame = nil

local function popupFrame()
    if Stub.popupFrame then return Stub.popupFrame end

    local dialog = CreateFrame("Frame", "StaticPopup1", UIParent)
    dialog.box = CreateFrame("EditBox", "StaticPopup1EditBox", dialog)
    dialog.box.parent = dialog

    --[[ The accept **button**, because that is what `this` is when 1.12 calls
         OnAccept -- which is why every vanilla addon reaches the dialog as
         `this:GetParent()`. Setting `this` to the dialog itself would make that
         idiom resolve to UIParent and quietly find no edit box. ]]--
    dialog.button = CreateFrame("Button", "StaticPopup1Button1", dialog)
    dialog.button.parent = dialog

    Stub.popupFrame = dialog
    return dialog
end

function Stub.AcceptPopup(name, text)
    local dialog = StaticPopupDialogs[name]
    if not dialog then return end

    local frame = popupFrame()
    local previous = this

    if dialog.hasEditBox then
        this = frame
        if dialog.OnShow then dialog.OnShow() end
        frame.box:SetText(text or "")
    end

    this = frame.button
    if dialog.OnAccept then dialog.OnAccept(frame.data, frame.data2) end

    this = previous
end

-- press Enter in a popup's edit box, which is a separate handler from OnAccept
function Stub.PopupEnter(name, text)
    local dialog = StaticPopupDialogs[name]
    if not dialog or not dialog.EditBoxOnEnterPressed then return end

    local frame = popupFrame()
    frame.box:SetText(text or "")

    local previous = this
    this = frame.box
    dialog.EditBoxOnEnterPressed()
    this = previous
end

function ShowUIPanel(frame) if frame and frame.Show then frame:Show() end end
function HideUIPanel(frame) if frame and frame.Hide then frame:Hide() end end

BOOKTYPE_SPELL = "spell"

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetWidth(1024)
UIParent:SetHeight(768)

--[==[ **Anchored, because things are anchored *to* it and read back off it.**

     Without a point of its own `UIParent:GetLeft()` is nil, and every module
     that positions something in physical pixels -- the world map is the whole of
     it -- gave up on its first line and did nothing. The suite then agreed that
     nothing was what it should do.

     It covers the screen, so a centred anchor on itself is the truthful way to
     say where its edges are. ]==]
UIParent:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

WorldFrame = CreateFrame("Frame", "WorldFrame")

--[[ **A nameplate as the client makes one**, which is the only way to test a
     module whose entire job is recognising them.

     Vanilla builds a Button parented to WorldFrame with six regions in a fixed
     order -- border, glow, name, level, level icon, raid icon -- and two
     children, the health bar and the cast bar. It has no name, no unit token and
     no event announcing it, so every one of those details is load bearing:
     something with the regions in a different order is not a nameplate, and
     something with the border texture is.

     Built here rather than faked, so a port that read the level as the name
     would fail rather than pass on a stub that answered plausible things in a
     convenient order. ]]--
function Stub.NewNamePlate(name, level, r, g, b, health)
    local plate = CreateFrame("Button", nil, WorldFrame)
    plate.frameType = "Button"

    --[[ The border first, because being first is the signature. ]]--
    local border = plate:CreateTexture(nil, "ARTWORK")
    border:SetTexture("Interface\\Tooltips\\Nameplate-Border")

    plate:CreateTexture(nil, "ARTWORK")               -- glow

    local nameText = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetText(name or "Target Dummy")

    local levelText = plate:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelText:SetText(tostring(level or 60))

    plate:CreateTexture(nil, "ARTWORK")               -- level icon
    plate:CreateTexture(nil, "OVERLAY")               -- raid icon

    --[[ Health first, cast second, which is the order GetChildren answers and
         the order the takeover relies on. ]]--
    local healthBar = CreateFrame("StatusBar", nil, plate)
    healthBar.frameType = "StatusBar"
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(health or 100)
    healthBar:SetStatusBarColor(r or 1, g or 0, b or 0, 1)

    local castBar = CreateFrame("StatusBar", nil, plate)
    castBar.frameType = "StatusBar"

    plate:Show()

    return plate
end

ColorPickerFrame = CreateFrame("Frame", "ColorPickerFrame", UIParent)
ColorPickerFrame.rgb = { 1, 1, 1 }
ColorPickerFrame.SetColorRGB = function(self, r, g, b) self.rgb = { r, g, b } end
ColorPickerFrame.GetColorRGB = function(self)
    return self.rgb[1], self.rgb[2], self.rgb[3]
end
ColorPickerFrame:Hide()

OpacitySliderFrame = CreateFrame("Slider", "OpacitySliderFrame", UIParent)
OpacitySliderFrame:SetValue(0)

-- ---------------------------------------------------------------------------
-- dropdown API
-- ---------------------------------------------------------------------------

--[[ **FrameXML's faux scroll frames**, which are how every list in this addon
     shows more rows than it has widgets for.

     Not modelled at all until now, so the item browser's two lists could not be
     drawn in a test: the first `FauxScrollFrame_Update` threw and took the whole
     refresh with it. That is most of why the browser had no coverage.

     `offset` is rows, not pixels -- the client divides by the step and the
     caller reads back a row count. Kept on the frame so a test can scroll one
     by setting it and asking for a redraw. ]]--
function FauxScrollFrame_Update(frame, numItems, numToDisplay, valueStep)
    if not frame then return end

    frame.numItems = numItems or 0
    frame.numToDisplay = numToDisplay or 0
    frame.valueStep = valueStep or 1
    frame.offset = frame.offset or 0

    --[[ The client clamps the offset when the list shrinks under it, which is
         what stops a search with two results drawing from row forty. ]]--
    local maxOffset = frame.numItems - frame.numToDisplay
    if maxOffset < 0 then maxOffset = 0 end
    if frame.offset > maxOffset then frame.offset = maxOffset end
end

function FauxScrollFrame_GetOffset(frame)
    return frame and frame.offset or 0
end

function FauxScrollFrame_SetOffset(frame, offset)
    if frame then frame.offset = offset or 0 end
end

--[[ Called from the scroll handler with `this` as the scroll frame, the way the
     client calls it. The step is the row height; the addon's own callback does
     the redraw. ]]--
function FauxScrollFrame_OnVerticalScroll(step, updateFn)
    local frame = this
    if frame and arg1 and step and step > 0 then
        frame.offset = math.floor((arg1 / step) + 0.5)
        if frame.offset < 0 then frame.offset = 0 end
    end
    if updateFn then updateFn() end
end

--[==[ **Interacting with a unit, which is four calls and a menu.**

     None of these were modelled, and the auto-faking metatable meant code
     reaching for them neither failed nor could be asserted about -- so a party
     frame that did nothing but target looked exactly like one that whispered,
     promoted and traded.

     Recorded rather than acted on. What matters is *which* call a click makes,
     because the whole feature is a decision table: a left click with a spell
     queued must cast rather than target, and a right click with one queued must
     cancel rather than open a menu. ]==]
Stub.unitActions = {}

local function noteUnitAction(kind, unit)
    table.insert(Stub.unitActions, { kind = kind, unit = unit })
    Stub.lastUnitAction = kind
end

--[[ Whether a spell is waiting for a target. `SpellStopTargeting` clears it, the
     way casting or cancelling does in the client. ]]--
Stub.spellTargeting = false

function SpellIsTargeting()
    return Stub.spellTargeting and 1 or nil
end

--[==[ **`TargetUnit`, which was not modelled at all.**

     Every caller of it sits behind `type(TargetUnit) == "function"`, so with the
     global absent the guard simply failed and the targeting path was skipped in
     silence -- a party frame that never targeted anybody would have passed. ]==]
function TargetUnit(unit)
    noteUnitAction("TargetUnit", unit)
    Stub.targeted = unit
end

function SpellTargetUnit(unit)
    noteUnitAction("SpellTargetUnit", unit)
    Stub.spellTargeting = false
end

function SpellStopTargeting()
    noteUnitAction("SpellStopTargeting", nil)
    Stub.spellTargeting = false
end

--[[ The call that opens a trade with the item already in it. Deliberately not
     guarded here: the guard belongs in the addon, and a stub that refuses an
     empty cursor would hide a caller that forgot to check. ]]--
function DropItemOnUnit(unit)
    noteUnitAction("DropItemOnUnit", unit)
end

--[==[ **The unit popup, which is the menu itself.**

     `which` is the set of entries -- "PARTY" is whisper, promote, uninvite and
     the rest. Recorded rather than built, because the entries are the client's
     and the thing under test is that the right set is asked for about the right
     unit. Building a fake menu here would be inventing a client. ]==]
function UnitPopup_ShowMenu(dropdown, which, unit, name, userData)
    Stub.unitPopup = { dropdown = dropdown, which = which, unit = unit }
    noteUnitAction("UnitPopup_ShowMenu", unit)

    --[[ The client writes the unit onto the dropdown, which is where its own
         click handler reads it back from. ]]--
    if dropdown then dropdown.unit = unit end
end

--[==[ **The click on an entry, and the one entry that only works on your
     target.**

     `UnitPopup_OnClick` is the client's handler for every entry on every unit
     menu; it reads the entry's value off `this` and the unit off the dropdown
     named in `UIDROPDOWNMENU_INIT_MENU`. Modelled for Inspect alone, which is
     the entry with the rule worth having here: this client will not open the
     inspect window for a unit that is not the target. A raid frame's menu hands
     it `raid7`, and nothing happens -- which was the report. ]==]
function UnitPopup_OnClick()
    local menu = UIDROPDOWNMENU_INIT_MENU and getglobal(UIDROPDOWNMENU_INIT_MENU)
    local unit = menu and menu.unit

    Stub.lastPopupClick = { value = this and this.value, unit = unit }

    if this and this.value == "INSPECT" and unit then
        InspectUnit(unit)
    end
end

function InspectUnit(unit)
    noteUnitAction("InspectUnit", unit)

    if UnitIsUnit(unit, "target") then
        Stub.inspected = unit
    end
end

--[[ Opening a dropdown runs its initialiser, which is where the popup above is
     asked for. Without that the menu could be wired up wrong and nothing would
     notice. ]]--
function ToggleDropDownMenu(level, value, frame, anchor, x, y)
    Stub.dropDownOpen = { frame = frame, anchor = anchor, x = x, y = y }

    if frame and type(frame.initialize) == "function" then
        local saved = this
        this = frame
        frame.initialize(level or 1)
        this = saved
    end
end

--[[ **`UIDROPDOWNMENU_OPEN_MENU` starts nil**, and the client's dropdown code
     builds frame names out of it -- which is what threw
     "attempt to concatenate global 'UIDROPDOWNMENU_OPEN_MENU' (a nil value)"
     five times when the item browser built its filter row on a fresh login.

     **Left nil here, and deliberately not made to throw.** An earlier version of
     this stub raised the client's error from `UIDropDownMenu_Initialize`, which
     looked like a faithful model and was a guess: it then failed all fifty-odd
     dropdowns in the options panel, which work perfectly well in the game. The
     evidence says *something* in that API reads the global; it does not say
     which call, or under what conditions, and this file must not invent the
     difference.

     So the global is modelled as the client leaves it -- absent until something
     sets it -- and what the suite checks is that the addon fills it in. That is
     the part that is actually known. ]]--
UIDROPDOWNMENU_OPEN_MENU = nil

function UIDropDownMenu_Initialize(frame, fn) frame.initialize = fn end
function UIDropDownMenu_SetWidth(width, frame)
    if frame then frame.dropWidth = width end
end

--[[ SetSelectedValue calls UIDropDownMenu_Refresh on the real client, and Refresh
     both moves the check mark AND sets the label from the matching button. The
     addon therefore does not call SetText at all -- doing so alongside
     info.checked is what put several ticks in one menu (constraint 25).

     Modelled here rather than left as a bare assignment because a stub that only
     records the value cannot tell a working dropdown from one whose label never
     updates -- which is exactly the profile-switching bug that shipped: the
     profile changed, and the dropdown went on naming the old one. ]]--
function UIDropDownMenu_SetSelectedValue(frame, value)
    if not frame then return end

    frame.selectedValue = value
    frame.selectedText = nil

    if not frame.initialize then return end

    local buttons = Stub.OpenMenu(frame)
    for i = 1, table.getn(buttons) do
        if buttons[i].value == value then frame.selectedText = buttons[i].text end
    end
end

function UIDropDownMenu_SetText(text, frame)
    if frame then frame.selectedText = text end
end
function UIDropDownMenu_AddButton(info)
    if menuButtons then table.insert(menuButtons, info) end
end


--[[ **The world map's zone label**, which is one font string the client rewrites
     every frame from its own hit test as the cursor moves.

     Real, because that rewriting is the whole reason the level range is appended
     *after* the original handler rather than before -- and a stub without the
     handler would let the wrong order pass. ]]--

--[[ **The world map and the minimap**, which the map module rescales and
     relabels.

     `WorldMapFrame` is one of the client's own top-level frames and everything
     on it is a child, which is what makes scaling the parent the right way to
     shrink it -- modelled as a real frame here so a test can read the scale
     back off it.

     `MinimapCluster` is the minimap and its furniture together; the clock
     anchors under it because that is where every client since has put one. ]]--
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:SetWidth(1024)
WorldMapFrame:SetHeight(768)
WorldMapFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
WorldMapFrame:EnableKeyboard(true)
WorldMapFrame:Hide()

--[[ Vanilla registers the map as a fullscreen UIPanel.  A scaled fullscreen
     panel is still modal, which is the bug the map module now has to fix. ]]--
UIPanelWindows["WorldMapFrame"] = { area = "full", pushable = 0, whileDead = 1 }

WorldMapButton = CreateFrame("Button", "WorldMapButton", WorldMapFrame)
WorldMapButton:SetWidth(1002)
WorldMapButton:SetHeight(668)
WorldMapButton:SetPoint("CENTER", WorldMapFrame, "CENTER", 0, 0)

BlackoutWorld = CreateFrame("Frame", "BlackoutWorld", WorldMapFrame)
BlackoutWorld:Show()

MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
Minimap = CreateFrame("Frame", "Minimap", MinimapCluster)

--[[ **Anchored the way the client anchors it**, inside the cluster and offset
     to centre a disc inside the round art. Without an anchor here there was
     nothing for a module to capture and put back, so a square minimap was a
     one-way trip and the test that should have caught it could not. ]]--
Minimap:SetPoint("TOPLEFT", MinimapCluster, "TOPLEFT", 20, -38)

--[[ **The mask is what makes the minimap round**, so square-versus-round is a
     question about this and nothing else. Recorded rather than accepted by the
     fallback stub: a test that cannot read the mask back can only check that
     the call did not throw, which every mask would pass. ]]--
Minimap.SetMaskTexture = function(self, path) self.mask = path end
Minimap.GetMaskTexture = function(self) return self.mask end

--[==[ **The sheet the engine draws group blips from.**

     There is no getter in the client -- the value is write-only -- so the
     read-back here is the harness being more generous than the game. That is
     the right way round for this one: the thing under test is which sheet gets
     handed over, and without a way to look there is no way to assert it.

     Seeded with the client's own, so a test that checks the dots came back is
     checking against the value the client actually starts with rather than
     against nil. ]==]
Minimap.blipTexture = "Interface\\Minimap\\ObjectIcons"
Minimap.SetBlipTexture = function(self, path) self.blipTexture = path end
Minimap.GetBlipTexture = function(self) return self.blipTexture end

--[[ **The ring round the minimap is a texture, not a frame**, which is the
     whole reason the first square-minimap attempt took the border off and left
     the map round: it was hidden like a frame and the mask was never the only
     thing holding the shape up. Modelled here as what it is. ]]--
MinimapBorder = MinimapCluster:CreateTexture("MinimapBorder", "ARTWORK")
MinimapBorder:SetTexture("BlizzardArtFor-MinimapBorder")
_G["MinimapBorder"] = MinimapBorder

MinimapBorderTop = MinimapCluster:CreateTexture("MinimapBorderTop", "ARTWORK")
_G["MinimapBorderTop"] = MinimapBorderTop
MinimapZoneTextButton = CreateFrame("Button", "MinimapZoneTextButton", MinimapCluster)
MinimapZoneText = newFontString(MinimapZoneTextButton, "OVERLAY", "GameFontNormal")
_G["MinimapZoneText"] = MinimapZoneText

--[[ **Everything the client hangs on the minimap**, which is more than the map.

     The zoom pair, the mail flag and the day/night button are all separate
     frames parented to `Minimap`, and every one of them is something somebody
     wants gone. They are modelled as real frames rather than assumed present,
     because code that hides them has to cope with a client -- or a server's
     custom UI -- where one of them is not there at all.

     `Minimap:SetZoom` is the client's, and it clamps: 0 is furthest out and 5
     furthest in on 1.12. A wheel handler that runs past either end without
     checking is how the wheel stops responding until you click a button. ]]--
MinimapZoomIn = CreateFrame("Button", "MinimapZoomIn", Minimap)
MinimapZoomOut = CreateFrame("Button", "MinimapZoomOut", Minimap)
MiniMapMailFrame = CreateFrame("Frame", "MiniMapMailFrame", Minimap)
GameTimeFrame = CreateFrame("Button", "GameTimeFrame", Minimap)

--[[ The button that puts the minimap away. Modelled because ECO moves it out of
     the furniture rail and shrinks it -- it is a close control rather than
     something you reach for while reading the map -- and "where did it go and
     what size is it" is the assertion. ]]--
MinimapToggleButton = CreateFrame("Button", "MinimapToggleButton", Minimap)

--[[ **Anchored, because the client's is.**

     Every one of these buttons is placed by the client's own XML, and ECO reads
     that anchor before it moves the button so it can put it back. A stub button
     with no anchor at all answers nil to `GetPoint`, which is a state no real
     client is ever in and which quietly makes "put it back where it was" mean
     "leave it wherever it was last put". ]]--
MinimapToggleButton:SetPoint("CENTER", Minimap, "TOPLEFT", 10, -10)

MiniMapTracking = CreateFrame("Frame", "MiniMapTracking", Minimap)

Minimap.zoom = 0

Minimap.SetZoom = function(self, level)
    if level < 0 then level = 0 end
    if level > 5 then level = 5 end
    self.zoom = level
end

Minimap.GetZoom = function(self) return self.zoom or 0 end
Minimap.GetZoomLevels = function(self) return 6 end

--[[ **Somebody else's minimap button**, which is the thing a collector has to
     find without being told about it.

     There is no flag for "this is an addon's icon". They are simply buttons
     parented to the minimap, and telling them apart from the client's own is a
     matter of knowing the client's names -- which is why the list of those
     names lives in the addon and is checked by a test. ]]--
Stub.addonButtons = {}

function Stub.AddMinimapButton(name)
    local b = CreateFrame("Button", name, Minimap)
    b:SetWidth(31)
    b:SetHeight(31)
    b:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
    table.insert(Stub.addonButtons, b)
    return b
end

--[[ A Questie-style *map pin*: also a Button and also parented to Minimap, but
     absolutely not an addon launcher.  Reparenting this is what made quest
     icons drift around the screen when ECO's icon drawer was collapsed. ]]--
function Stub.AddMinimapQuestPin(name)
    local b = CreateFrame("Button", name or "QuestieFrame1", Minimap)
    b:SetWidth(16)
    b:SetHeight(16)
    b:SetPoint("CENTER", Minimap, "CENTER", 23, -17)
    b:SetScript("OnClick", function() end)
    return b
end

--[[ **Where the player is on the map**, which the waypoint arrow points from.

     `GetPlayerMapPosition` answers 0-to-1 fractions of *whichever map is
     currently open*, not of the zone you are standing in -- which is why
     `SetMapToCurrentZone` exists and why anything reading a position has to call
     it first. Modelled as a real switch here, so a test can leave the map on
     another continent and watch the position be wrong until it is put back.

     Zero, zero is what the client answers when it does not know: inside an
     instance, or mid-loading-screen. It is a real answer rather than a missing
     one, and code that treats it as a corner of the map sends people walking
     north-west with great confidence. ]]--
Stub.playerMap = { x = 0.5, y = 0.5 }
Stub.mapIsCurrentZone = true

function SetMapToCurrentZone() Stub.mapIsCurrentZone = true end

function GetPlayerMapPosition(unit)
    if not Stub.mapIsCurrentZone then return 0, 0 end
    return Stub.playerMap.x, Stub.playerMap.y
end

Stub.realZone = "Elwynn Forest"
function GetRealZoneText() return Stub.realZone end

--[[ **What kind of place you are standing in.** `GetInstanceInfo` answers
     `name, instanceType`, and the two types worth asking about are "party" for a
     five-man and "raid". Not on every 1.12 build -- Questie guards the call the
     same way -- so `Stub.instanceKind` of nil models a client that does not have
     it rather than one standing outside. ]]--
Stub.instanceKind = nil

function GetInstanceInfo()
    if not Stub.instanceKind then return Stub.realZone, "none" end
    return Stub.realZone, Stub.instanceKind
end

--[[ **The player's facing, which 1.12 exposes through nothing named.**

     There is no `GetPlayerFacing` on this client. The only thing that knows is
     the minimap's own rotating model, an unnamed child of `Minimap` answering
     `GetFacing()` in radians -- so anything wanting the facing has to go
     hunting through `Minimap:GetChildren()` for it.

     Modelled with the same shape, unnamed and among siblings that do not answer
     `GetFacing`, because finding it is the part that goes wrong. ]]--
Stub.playerFacing = 0

do
    local decoy = CreateFrame("Frame", nil, Minimap)
    decoy.frameType = "Frame"

    local facingModel = CreateFrame("Model", nil, Minimap)
    facingModel.frameType = "Model"
    facingModel.GetFacing = function(self) return Stub.playerFacing end
    facingModel.SetFacing = function(self, v) Stub.playerFacing = v end

    Stub.facingModel = facingModel
end
--[==[ **Which map is open, which is not the same as which zone you are in.**

     `GetCurrentMapZone()` answers 0 while the map is showing a whole continent
     rather than one of its zones, and a fraction read off a continent map is a
     fraction of the continent. Modelled because a stub that always claimed a
     zone lets a waypoint dropped on a continent map be filed against whichever
     zone the player happens to be standing in -- which is what shipped. ]==]
Stub.mapContinent = 1
Stub.mapZone = 1

function GetCurrentMapContinent() return Stub.mapContinent or 0 end
function GetCurrentMapZone() return Stub.mapZone or 0 end

WorldMapFrameAreaLabel = newFontString(nil, "OVERLAY", "GameFontNormal")
_G["WorldMapFrameAreaLabel"] = WorldMapFrameAreaLabel

Stub.hoveredZone = nil

function WorldMapButton_OnUpdate(elapsed)
    --[[ What the client does: writes whatever the cursor is over, blanking it
         when the cursor is over nothing. ]]--
    WorldMapFrameAreaLabel:SetText(Stub.hoveredZone or "")
end

-- ---------------------------------------------------------------------------
-- the client the bundled libraries ask about
-- ---------------------------------------------------------------------------

--[[ **The suite could not boot at all without these**, and had not since the
     Atlas-CFM/AtlasLoot bundle joined the TOC: AceLibrary calls `GetBuildInfo`
     on its second line, the file threw, and every one of the twelve thousand
     checks below it never ran. A dead suite reports nothing and looks exactly
     like a passing one you forgot to run.

     Answering as 1.12.1 rather than as the 2.0 client AceLibrary also knows
     about, because that is what this addon is built for and a stub that claims
     otherwise agrees with a port that branched the wrong way. ]]--
function GetBuildInfo() return "1.12.1", "5875", "Jul 10 2006", 11200 end

--[[ 5.0 tracked a table's length in an `n` field and `table.setn` wrote it.
     5.1 dropped both, so the honest shim is a no-op: `table.getn` already
     answers from the array part. AceLibrary takes this path on any non-2.0
     client. ]]--
table.setn = table.setn or function() end

--[[ The addon manifest. Empty, because the suite loads ECO's files itself --
     what the libraries want to know is whether some *other* copy of themselves
     is installed standalone, and the answer here is always no. ]]--
--[[ The client's error sink. AceLibrary asks for it by name and calls whatever
     comes back, so answering nil takes the library down on its own line 42. ]]--
function geterrorhandler()
    return function(err) table.insert(Stub.errors, tostring(err)) end
end

Stub.errors = {}

--[[ **The addon manifest, which the addon list is built entirely out of.**

     It answered nothing, because the only thing reading it was AceLibrary asking
     whether a standalone copy of itself is installed -- and the answer there is
     always no. The addon list asks the same API a very different question, so it
     needs real entries to answer from.

     Modelled in the client's own shape: `GetAddOnInfo` answers name, title,
     notes, enabled, loadable, reason, security, and `enabled` is a *number* on
     1.12 rather than a boolean. Titles carry colour escapes because real ones
     do, which is why the list sorts on the plain name and not on the title. ]]--
Stub.addons = {
    { name = "Bagshui", title = "|cff33ff99Bagshui|r", enabled = 1, loadable = 1 },
    { name = "EquadisClassicOverhaul", title = "Equadis' Classic Overhaul",
      enabled = 1, loadable = 1 },
    { name = "Questie-Octo", title = "Questie", enabled = 1, loadable = 1 },

    --[[ Installed but switched off, which is the state that matters: the unit
         frames module reads its frame art straight off this folder by path, so
         the textures must resolve for an addon nobody is loading. Disabled here
         on purpose -- if the probe were quietly requiring `enabled`, the art
         would vanish the moment somebody took the addon out of the login list,
         which is precisely what this project is asking people to do. ]]--
    { name = "EquadisUnitFrames", title = "Equadis' Unit Frames",
      enabled = nil, loadable = nil, reason = "DISABLED" },
    { name = "ShaguPlates", title = "ShaguPlates", enabled = nil, loadable = nil,
      reason = "DISABLED" },
    { name = "pfUI", title = "pfUI", enabled = 1, loadable = nil,
      reason = "MISSING" },
}

function GetNumAddOns() return table.getn(Stub.addons) end

--[[ **The client takes either an index or a name here**, and this stub used to
     take only an index -- so every `GetAddOnInfo("SomeAddon")` in the addon
     answered nil and the code behind it was never once exercised. That is how
     the unit frames module went so long looking for its art in a folder nobody
     has: the probe could not succeed under test either way, so the failing
     branch and the working branch were indistinguishable. ]]--
local function addonEntry(key)
    local byIndex = Stub.addons[tonumber(key) or 0]
    if byIndex then return byIndex end

    for i = 1, table.getn(Stub.addons) do
        if Stub.addons[i].name == key then return Stub.addons[i] end
    end

    return nil
end

Stub.AddOnEntry = addonEntry

function GetAddOnInfo(index)
    local a = addonEntry(index)
    if not a then return nil end
    return a.name, a.title, a.notes, a.enabled, a.loadable, a.reason, a.security
end

--[[ Enabling and disabling write to the same list the login screen reads, which
     is why the window says changes take effect on the next load: nothing here
     loads or unloads anything now. ]]--
function EnableAddOn(index)
    local a = addonEntry(index)
    if a then a.enabled = 1 end
end

function DisableAddOn(index)
    local a = addonEntry(index)
    if a then a.enabled = nil end
end

function GetAddOnMetadata(addon, field) return nil end
function LoadAddOn(name) return nil end

--[[ The three the libraries ask about and nothing else here does. `UnitLevel`
     is deliberately *not* among them: this file already models it per unit
     further up, and redefining it here to answer the player's level for every
     unit is exactly the kind of quiet shadowing that makes a stub agree with a
     bug. ]]--
function UnitRace(unit) return "Human", "Human" end
function UnitFactionGroup(unit) return "Alliance", "Alliance" end
function UnitSex(unit) return 2 end

--[[ FrameXML's own global strings, which the bundled libraries build their
     saved-variable keys out of. Enough of them to boot, and no more: this stub
     is not a localisation table. ]]--
FACTION_ALLIANCE = "Alliance"
FACTION_HORDE = "Horde"
PLAYER_OF_REALM = "%s - %s"
UNKNOWN = "Unknown"

-- ---------------------------------------------------------------------------
-- the player's aura buttons
-- ---------------------------------------------------------------------------

--[[ **Blizzard's own aura buttons, which are the frames the buff module moves
     rather than anything it makes.**

     `BuffButton0..15` are buffs and `16..23` debuffs -- the split VCB walks with
     `for i = 0, 23` and DragonflightUI-Reforged anchors rows against at 0, 8 and
     16.

     `buffFilter` is set the way 1.12's `BuffButtonTemplate` sets it: the *same*
     `"HELPFUL|HARMFUL"` on every button, which is the line VCB's copy of that
     template still carries. Modelled exactly, because a stub that helpfully
     narrowed it per button would agree with a reader that trusts the filter --
     and trusting it is what put all twenty-four buttons in the buff list and
     left the debuff half of the module doing nothing. ]]--
BuffFrame = CreateFrame("Frame", "BuffFrame", nil)
_G["BuffFrame"] = BuffFrame
TemporaryEnchantFrame = CreateFrame("Frame", "TemporaryEnchantFrame", BuffFrame)
_G["TemporaryEnchantFrame"] = TemporaryEnchantFrame

BUFF_BUTTON_COUNT = 24

for i = 0, BUFF_BUTTON_COUNT - 1 do
    local name = "BuffButton" .. i
    local b = CreateFrame("Button", name, BuffFrame)

    b.buffFilter = "HELPFUL|HARMFUL"
    b:SetID(i < 16 and i or (i - 16))
    b:SetWidth(30)
    b:SetHeight(30)

    --[[ Two rows of eight for buffs, one for debuffs, anchored where the client
         anchors them: against BuffFrame, so a module that re-anchors them has
         something real to be restored to. ]]--
    local column = i - math.floor(i / 8) * 8
    local row = math.floor(i / 8)
    b:SetPoint("TOPRIGHT", BuffFrame, "TOPRIGHT", -column * 33, -row * 42)

    _G[name .. "Icon"] = b:CreateTexture(name .. "Icon", "BACKGROUND")
    _G[name .. "Count"] = newFontString(b, "OVERLAY", "NumberFontNormal")
    _G[name .. "Duration"] = newFontString(b, "ARTWORK", "GameFontNormalSmall")
    _G[name .. "Border"] = b:CreateTexture(name .. "Border", "OVERLAY")
end


--[==[ **The flash a nearly-spent aura does**, which is four constants and one
     saw wave and was modelled by nothing at all.

     `BuffFrame`'s `OnUpdate` runs a triangle between `BUFF_MIN_ALPHA` and one,
     spending `BUFF_FLASH_TIME_ON` going up and `BUFF_FLASH_TIME_OFF` coming
     down, and leaves the result on `BuffFrame.BuffAlphaValue`. Every aura button
     with less than `BUFF_WARNING_TIME` seconds left takes that value as its
     alpha, every frame; everything else takes one. Weapon buffs read the same
     field, which is why one switch reaches all three rows.

     The four values are 1.12's own. They are read before this file's snapshot of
     the globals, so a boot that changes them gets them back at the next one.

     **Driven by an explicit call rather than from the tick**, because nothing in
     the addon reads any of this: it is the client painting the client's own
     buttons. A test that wants to watch it asks. ]==]
BUFF_FLASH_TIME_ON = 0.75
BUFF_FLASH_TIME_OFF = 0.75
BUFF_MIN_ALPHA = 0.3
BUFF_WARNING_TIME = 31

BuffFrame.BuffFrameFlashState = 1
BuffFrame.BuffFrameFlashTime = BUFF_FLASH_TIME_ON
BuffFrame.BuffAlphaValue = 1

--[[ `BuffFrame_OnUpdate`'s flash half, arithmetic for arithmetic -- including
     the carried `overtime`, which is what keeps the wave honest when a frame
     lands past the end of a half cycle rather than on it. ]]--
function Stub.BuffFlashTick(elapsed)
    local f = BuffFrame

    f.BuffFrameFlashTime = (f.BuffFrameFlashTime or 0) - (elapsed or 0)

    if f.BuffFrameFlashTime < 0 then
        local overtime = -f.BuffFrameFlashTime

        if f.BuffFrameFlashState == 1 then
            f.BuffFrameFlashState = 0
            f.BuffFrameFlashTime = BUFF_FLASH_TIME_OFF - overtime
        else
            f.BuffFrameFlashState = 1
            f.BuffFrameFlashTime = BUFF_FLASH_TIME_ON - overtime
        end
    end

    if f.BuffFrameFlashState == 1 then
        f.BuffAlphaValue =
                (BUFF_FLASH_TIME_ON - f.BuffFrameFlashTime) / BUFF_FLASH_TIME_ON
    else
        f.BuffAlphaValue = f.BuffFrameFlashTime / BUFF_FLASH_TIME_OFF
    end

    f.BuffAlphaValue = (f.BuffAlphaValue * (1 - BUFF_MIN_ALPHA)) + BUFF_MIN_ALPHA

    return f.BuffAlphaValue
end

--[[ And the branch `BuffButton_OnUpdate` takes with it: under the warning the
     button wears the wave, over it the button is simply on. ]]--
function Stub.BuffButtonAlpha(timeLeft)
    if timeLeft and timeLeft < BUFF_WARNING_TIME then
        return BuffFrame.BuffAlphaValue
    end

    return 1
end

--[[ Back to the start of an up stroke, so a test measuring a cycle starts where
     a login does rather than wherever the last test left the wave. ]]--
function Stub.ResetBuffFlash()
    BuffFrame.BuffFrameFlashState = 1
    BuffFrame.BuffFrameFlashTime = BUFF_FLASH_TIME_ON
    BuffFrame.BuffAlphaValue = 1
end


--[[ **The temporary weapon enchant buttons**, which are not `BuffButton`s and
     are the half every buff-moving addon forgets.

     A sharpening stone, a rogue's poison, a shaman's weapon buff and an
     enchanter's oil all land here rather than in the buff list, and the client
     lays them out as their own row inside `TemporaryEnchantFrame`. There are
     two: main hand and off hand.

     Modelled anchored against `TemporaryEnchantFrame` the way the client
     anchors them, so a module that re-anchors them has something real to be
     restored to -- and so a module that *forgets* them leaves them visibly
     behind, which is the bug this exists to catch. ]]--
--[[ **A weapon buff's charges, which the client knows and never draws.**

     `GetWeaponEnchantInfo` answers both hands at once: whether there is one,
     how long is left in milliseconds, and how many charges remain. The charges
     are the half nothing in the interface shows -- a rogue's poison is spent
     per hit rather than on a clock, so its icon can vanish mid-fight with the
     duration still reading minutes.

     Both hands from one call, in one flat list of six, because that is how the
     client returns it and a stub that tidied it into two tables would agree
     with a port that read the off hand out of the wrong three. ]]--
Stub.weaponEnchant = { main = nil, off = nil }

--[==[ **The client's own pass over the weapon buttons, which repaints them.**

     `TemporaryEnchantFrame_Update` runs whenever an enchant lands, falls off or
     spends a charge. It fills the buttons in sequence from the first and sets
     the icon and the border on each as it goes -- so anything an addon painted
     earlier is replaced, and the addon has to run *after* this rather than more
     often than it.

     Modelled with the repaint in it, because a stub that only filled the icons
     would agree with an addon that paints once and never again. The border
     colour here is the client's own reddish overlay: not white, so a test can
     tell "ours survived" from "nothing happened". ]==]
--[==[ **Two ways a client can fill these two buttons, and this addon cannot
     know which one it is on.**

     *Packing*: the nth enchanted weapon goes on the nth button, so one off-hand
     poison appears on `TempEnchant1`.

     *Fixed*: `TempEnchant1` is always the main hand and is simply hidden when
     that weapon has no enchant, so one off-hand poison appears on
     `TempEnchant2`.

     Both were written down as fact at different times in this addon's history
     and both are guesses. They agree whenever both hands are enchanted -- which
     is why either survives casual use -- and disagree exactly when the only
     enchant is on the off hand. That disagreement is the reported colours not
     applying, hands swapped, and charges swapped and missing: one wrong mapping
     seen from three angles.

     So the stub does both, and the module is asserted against both. Packing is
     the default because it is what was modelled first and what the existing
     tests were written against; `Stub.enchantPacks = false` gives the other. ]==]
Stub.enchantPacks = true

function TemporaryEnchantFrame_Update()
    local hands = { Stub.weaponEnchant.main, Stub.weaponEnchant.off }
    local shownAt = {}

    if Stub.enchantPacks then
        local at = 0

        for i = 1, 2 do
            if hands[i] then
                at = at + 1
                shownAt[at] = true
            end
        end
    else
        for i = 1, 2 do
            if hands[i] then shownAt[i] = true end
        end
    end

    for i = 1, 2 do
        local b = _G["TempEnchant" .. i]
        local border = _G["TempEnchant" .. i .. "Border"]

        if shownAt[i] then
            if b then b:Show() end

            --[[ The client's own reddish overlay: not white, so a test can tell
                 "ours survived" from "nothing happened". ]]--
            if border and border.SetVertexColor then
                border:SetVertexColor(0.79, 0.31, 0.26, 1)
            end
        else
            if b then b:Hide() end
        end
    end
end

function GetWeaponEnchantInfo()
    local m = Stub.weaponEnchant.main
    local o = Stub.weaponEnchant.off

    return m and 1 or nil, m and m.expires or nil, m and m.charges or nil,
           o and 1 or nil, o and o.expires or nil, o and o.charges or nil
end

for i = 1, 2 do
    local name = "TempEnchant" .. i
    local b = CreateFrame("Button", name, TemporaryEnchantFrame)

    b:SetWidth(30)
    b:SetHeight(30)
    b:SetPoint("TOPRIGHT", TemporaryEnchantFrame, "TOPRIGHT", -(i - 1) * 33, 0)

    --[==[ **The button carries the inventory slot it is showing**, which is how
         the client's own `OnEnter` knows what to put in the tooltip:
         `GameTooltip:SetInventoryItem("player", this:GetID())`. Sixteen is the
         main hand and seventeen the off hand.

         Unmodelled, the only way to work out which weapon a button was showing
         was to count how many are enchanted and assume the client fills them in
         order -- a guess that is right in the common case and wrong exactly when
         somebody has one poison on the off hand. ]==]
    b:SetID(15 + i)

    _G[name .. "Icon"] = b:CreateTexture(name .. "Icon", "BACKGROUND")
    _G[name .. "Duration"] = newFontString(b, "ARTWORK", "GameFontNormalSmall")
    _G[name .. "Border"] = b:CreateTexture(name .. "Border", "OVERLAY")

    b:Hide()

--[[ **`ChatFrame_OnEvent`, which is where the client turns an event into a
     line.**

     Every `CHAT_MSG_` the client delivers arrives here first and is formatted
     and handed to a frame's `AddMessage`. That makes it the one place an addon
     can decline to show something at all, as opposed to changing it after it is
     already on screen.

     Modelled as the real thing does it: reads `event` off the global the client
     is standing in, and appends to a list a test can read back. ]]--
--[[ The away marker the client puts beside a name, which is a different
     mechanism entirely from the auto-reply and must survive it being
     suppressed. ]]--
CHAT_FLAG_AFK = "<Away>"
CHAT_FLAG_DND = "<Busy>"

Stub.chatShown = {}

function ChatFrame_OnEvent()
    table.insert(Stub.chatShown, { event = event, text = arg1 })
end
end
--[[ The client's own per-button refresh, which the module borrows rather than
     replacing. Vanilla writes it around `this`; ShaguTweaks' hook says so in as
     many words ("tbc passes buttonName and index arguments, vanilla uses `this`
     context"), so that is the contract modelled here. ]]--
--[==[ **The client's four extra bars, and the calls that drive them.**

     `ApplyBarVisibility` opens with `if type(SetActionBarToggles) ~= "function"
     then return false end`, and that call was not modelled -- so **the entire
     function returned on its first line in every test that has ever run here**.
     Which bars exist, the always-show-empty-slots setting, and the frame
     re-layout that keeps the chat window off a bar that has just appeared: none
     of it was ever executed.

     That is a worse shape than a skipped branch, and it is the one a sweep
     looking only for `== "function"` misses, because it is written the other way
     round.

     The mapping is the client's and is not guessable from the names: toggle 1 is
     `MultiBarBottomLeft`, 2 is `MultiBarBottomRight`, **3 is `MultiBarRight`**
     and 4 is `MultiBarLeft` -- the two side bars are numbered outboard-first,
     which is why the module has to turn 3 on to get 4. ]==]
SHOW_MULTI_ACTIONBAR_1 = nil
SHOW_MULTI_ACTIONBAR_2 = nil
SHOW_MULTI_ACTIONBAR_3 = nil
SHOW_MULTI_ACTIONBAR_4 = nil
ALWAYS_SHOW_MULTIBARS = "0"

local MULTIBAR_FRAMES = {
    "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
}

function SetActionBarToggles(a, b, c, d)
    SHOW_MULTI_ACTIONBAR_1 = a
    SHOW_MULTI_ACTIONBAR_2 = b
    SHOW_MULTI_ACTIONBAR_3 = c
    SHOW_MULTI_ACTIONBAR_4 = d
    return true
end

--[[ What actually shows and hides the frames. The globals above are only a
     record until this runs, which is the distinction the module's own note
     makes about the grid setting. ]]--
function MultiActionBar_Update()
    local wanted = { SHOW_MULTI_ACTIONBAR_1, SHOW_MULTI_ACTIONBAR_2,
                     SHOW_MULTI_ACTIONBAR_3, SHOW_MULTI_ACTIONBAR_4 }

    for i = 1, 4 do
        local frame = _G[MULTIBAR_FRAMES[i]]
        if frame then
            if wanted[i] then frame:Show() else frame:Hide() end
        end
    end

    return true
end

--[==[ **Whether empty slots are drawn**, which is read out of
     `ALWAYS_SHOW_MULTIBARS` and nowhere else. The module compares it as the
     **string** `"1"`, because that is what the client compares -- so a stub
     holding a boolean would agree with a reader that got that wrong. ]==]
Stub.gridsShown = false

function MultiActionBar_UpdateGridVisibility()
    Stub.gridsShown = (ALWAYS_SHOW_MULTIBARS == "1")
    return true
end

function MultiActionBar_ShowAllGrids()
    Stub.gridsShown = true
    return true
end

--[==[ **The client moving its own managed frames back.**

     This is the call the action bars module anchors around: NOTICE records the
     decision to anchor to containers of our own *because* this exists and will
     quietly put a frame parented to `MainMenuBar` back where the client wants
     it. Nothing could test that, because the call was not here.

     Modelled as what it really is -- the client re-asserting its own layout on
     its own frames -- and deliberately **not** touching anything else. A stub
     that moved everything would fail an addon for being in the room; a stub that
     moved nothing lets one anchored to the wrong parent pass. ]==]
Stub.manageFramePositions = 0

function UIParent_ManageFramePositions()
    Stub.manageFramePositions = Stub.manageFramePositions + 1

    for i = 1, 4 do
        local frame = _G[MULTIBAR_FRAMES[i]]

        --[[ Only the client's own, and only when the client still owns them:
             a frame an addon has re-parented is no longer managed, which is the
             whole of what the module is relying on. ]]--
        if frame and frame:GetParent() == UIParent then
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 98)
        end
    end

    return true
end

--[[ The client's own per-button refresh for an action button, which is the
     action bar's equivalent of `BuffButton_Update` below and was missing for the
     same reason: written around the 1.12 `this` global. ]]--
function ActionButton_Update()
    local button = this
    if not button then return end

    local slot = button.GetID and button:GetID() or nil
    if not slot then return end

    if Stub.actionBar and Stub.actionBar[slot] then button:Show() end
end

function BuffButton_Update()
    local button = this
    if not button then return end

    local index = Stub.playerAuraIndex and Stub.playerAuraIndex[button] or nil
    if index then button:Show() else button:Hide() end
end

--[==[ **The client going through `$parentDuration`, which is not this addon's
     string.**

     1.12 draws a buff's remaining time in `$parentDuration` itself -- and hides
     it again for a buff that is not close to expiring, which is most buffs most
     of the time. So the client writing and hiding that string is the widget's
     ordinary behaviour, not an edge case.

     The buff module writes into the same string on purpose: making a second one
     put two numbers on top of each other, which is what was reported. That is
     the right call and it carries an obligation -- anything guarding its writes
     on a memory of what it last wrote will be wrong the moment the client
     touches it, and will stay wrong, because nothing tells it.

     **Nothing here could say that before.** No test could hide the string the
     way the client does, so a module that never recovered from it passed every
     run. Named as what it is rather than as a client function this stub cannot
     vouch for the spelling of. ]==]
--[==[ **The client counting a buff down, which happens every frame.**

     `BuffButton_OnUpdate` is where 1.12 draws a buff's remaining time, and it
     writes `$parentDuration` on a buff close to expiring -- so an addon writing
     the same string on a timer of its own does not replace the client's number,
     it alternates with it. Ten writes a second against sixty is five frames of
     the client's text for every one of the addon's: text that jitters between
     two widths and a colour that reads as the client's.

     **Nothing here could say that.** The stub had the client touching this
     string only when a test asked it to, one call at a time, so a module that
     lost the race sixty times a second and won it ten looked identical to one
     that owned the string outright.

     `Stub.clientDurationText` is what the client's pass writes; leaving it nil
     is a client that has decided not to draw a duration for this buff, which is
     what it does for anything not close to expiring. ]==]
Stub.clientDurationText = nil

function BuffButton_OnUpdate()
    local button = this
    if not button then return end

    Stub.ClientDurationPass(button, Stub.clientDurationText)
end

function Stub.ClientDurationPass(button, text)
    if not button or not button.GetName then return false end

    local duration = _G[button:GetName() .. "Duration"]
    if not duration then return false end

    if text then
        duration:SetText(text)
        duration:Show()
    else
        duration:SetText("")
        duration:Hide()
    end

    --[[ And the colour, which the client sets to its own normal font colour
         whenever it draws one. ]]--
    if duration.SetTextColor then duration:SetTextColor(1, 0.82, 0, 1) end

    return true
end

--[==[ **The world map's party and raid markers.**

     `WorldMapParty1` through 4 and `WorldMapRaid1` through 40, each holding a
     texture named `$parentIcon` and all of them wearing the same green dot. The
     number is the unit -- `WorldMapParty2` is `party2` -- which is the only
     reason a marker can be told whose it is.

     Modelled as a frame with a child texture rather than as a bare texture,
     because that is the shape the client uses and a reader that only handles the
     other one would pass against a simpler stub and find nothing in game. ]==]
for i = 1, 4 do
    local f = CreateFrame("Frame", "WorldMapParty" .. i, WorldMapButton)
    f:SetWidth(16)
    f:SetHeight(16)
    local t = f:CreateTexture("WorldMapParty" .. i .. "Icon", "ARTWORK")
    t:SetTexture("Interface\\WorldMap\\WorldMapPartyIcon")
end

for i = 1, 40 do
    local f = CreateFrame("Frame", "WorldMapRaid" .. i, WorldMapButton)
    f:SetWidth(16)
    f:SetHeight(16)
    local t = f:CreateTexture("WorldMapRaid" .. i .. "Icon", "ARTWORK")
    t:SetTexture("Interface\\WorldMap\\WorldMapRaidIcon")
end

--[==[ **`WorldMapPlayer`, which is not `WorldMapParty0` and has no icon.**

     Read out of the client's own `WorldMapFrameTemplates.xml`: the party and
     raid markers inherit `WorldMapUnitTemplate` and each get a `$parentIcon`
     texture, while the player's marker inherits nothing and carries no texture
     at all -- a bare sixteen-pixel frame with `id` zero.

     Both halves of that are why the bug hid. A stub with no player marker
     cannot notice one being skipped, and a stub that gave it an icon like the
     others would have passed code that had nothing to draw on. ]==]
do
    local f = CreateFrame("Frame", "WorldMapPlayer", WorldMapButton)
    f:SetWidth(16)
    f:SetHeight(16)
    f:SetFrameLevel((WorldMapButton:GetFrameLevel() or 0) + 1)
end

Stub.playerAuraIndex = {}

--[==[ **How long is left on one of the player's own auras.**

     This is the call that makes the player's buffs different from everybody
     else's. A debuff on a mob has no duration in 1.12 and has to be guessed
     from a shipped table; your own auras are answered by the client exactly,
     through this, keyed by the buff index the button carries.

     Nought for an aura with no clock -- a stance, a paladin aura, anything
     until-cancelled -- because that is what the client answers, and reading it
     as "expires now" rather than "has no timer" is the mistake worth catching
     here rather than in the game. ]==]
Stub.buffTimeLeft = {}

function GetPlayerBuffTimeLeft(index)
    if type(index) ~= "number" then return 0 end
    return Stub.buffTimeLeft[index] or 0
end

--[[ Harmful auras on a unit, as `UnitDebuff` reports them: texture, stacks,
     type. Keyed by unit so a party member and the target can differ, which is
     the whole point of a party debuff pass. ]]--
Stub.debuffs = {}

--[==[ **Helpful auras on somebody else, which is not the same call as your
     own.**

     `GetPlayerBuff` answers about *you* and hands back a handle into a shared
     index space; `UnitBuff` answers about any unit, by position, and returns the
     texture directly. This addon needs the second one to spot a hunter's feign
     death -- there is no event for it, and the only signature is the aura's
     icon on a unit that is pretending to be a corpse.

     **It was not modelled**, and `IsFeigning` opens with
     `if type(UnitBuff) ~= "function" then return false end` -- so feign
     detection answered "no" in every test that has ever run, and with it the
     half of the retarget feature that exists for exactly that case. A hunter
     feigning is the reason that feature was written.

     Keyed by unit like `UnitDebuff` beside it, and the player's own list is
     shared with `Stub.player.buffs` so the two cannot disagree about what you
     are carrying. ]==]
Stub.unitBuffs = {}

function UnitBuff(unit, index, onlyCancelable)
    local list = Stub.unitBuffs[unit]

    --[[ Your own buffs are authored in one place. A stub that let "player" hold
         two different lists would let a reader pick the convenient one. ]]--
    if not list and unit == "player" then list = Stub.player.buffs end

    if not list then return nil end

    local entry = list[index]
    if not entry then return nil end

    --[[ Authored either as a bare texture or as a table with a count, because
         most tests only care about the icon and a few care about the stack. ]]--
    if type(entry) == "table" then return entry.texture, entry.count end
    return entry, nil
end

--[==[ **The client's own world map click handler.**

     `waypoints.lua` wraps this global -- it is the only seam there is, because
     `WorldMapButton` is wired to it from XML rather than through a script an
     addon can hook. `InstallMapClick` opens with
     `if type(WorldMapButton_OnClick) ~= "function" then return false end`, so
     **the wrapper has never been installed in any test**: every waypoint test
     calls `MapClick` directly, which proves the conversion and not the reach.

     That is the same gap that let `/eq bars` ship unreachable -- a handler that
     is right is not a handler anything can get to.

     Modelled as vanilla's own: a right-click zooms the map out, and a left click
     does nothing this addon cares about. The zoom is recorded rather than
     performed, because what matters here is whether the addon ate it. ]==]
Stub.mapZoomedOut = 0

function WorldMapButton_OnClick(button)
    button = button or arg1

    if button == "RightButton" then
        Stub.mapZoomedOut = Stub.mapZoomedOut + 1
    end

    return true
end

--[[ **A PvP rank's name and number.** The tooltip draws it for players who have
     one, and the whole function was guarded on a call the harness did not
     have. ]]--
Stub.pvpRanks = {
    [1] = "Private", [2] = "Corporal", [3] = "Sergeant",
    [6] = "Knight", [11] = "Commander", [14] = "Marshal",
}

function GetPVPRankInfo(rank, unit)
    rank = tonumber(rank)
    if not rank or rank < 1 then return nil end

    return Stub.pvpRanks[rank] or ("Rank " .. rank), rank
end

--[[ **The raid marker on a unit.** unitscan puts one on what it found, and the
     call it uses to do that was absent -- so the marking half of the alert was
     dead. ]]--
Stub.raidTargets = {}

function SetRaidTarget(unit, index)
    Stub.raidTargets[unit] = index
    return true
end

--[==[ **The client's own handler for a clicked chat link.**

     Every `|Hitem:` and `|Hquest:` in the chat frame arrives here, which makes
     it the one place an addon can change what a link does. `chatbehaviour.lua`
     wraps it and was guarded on it, so that whole hook has never been
     installed. ]==]
--[==[ **Clicking a chat link, which is what the client actually does with one.**

     `SetItemRef` shows `ItemRefTooltip` and fills it from the link -- and
     crucially it does that **whether or not the tooltip was already open**.
     Click a second item and the same frame is re-filled in place: no `Hide`, no
     `Show`, and therefore no `OnShow` for anything hooked there.

     Modelled with the re-fill in it, because a stub that only recorded the call
     could not tell an addon that decorates on `OnShow` from one that decorates
     on the click -- and the difference between those two is a tooltip showing
     the previous item's rows under the current item's. ]==]
Stub.itemRefs = {}

function SetItemRef(link, text, button)
    table.insert(Stub.itemRefs, { link = link, text = text, button = button })

    local tip = _G["ItemRefTooltip"]
    if not tip then return true end

    --[[ Filled from the same store every other tooltip loader reads, keyed by
         the link so two links are two different tooltips. ]]--
    local block = Stub.tooltips and Stub.tooltips[link]

    tip:ClearLines()

    if block then
        for i = 1, table.getn(block) do
            tip:Line(i):SetText(block[i])
        end
        tip.lineCount = table.getn(block)
    end

    --[[ Shown without being hidden first, which is the whole point. ]]--
    if not tip:IsShown() then tip:Show() end

    return true
end

--[[ **Where the client puts a tooltip when nothing has claimed it.** The
     tooltip module wraps this to place tooltips somewhere of its own choosing,
     and the wrap was guarded on a call that was not here. ]]--
function GameTooltip_SetDefaultAnchor(tooltip, owner)
    if tooltip and tooltip.SetOwner then
        tooltip:SetOwner(owner or UIParent, "ANCHOR_NONE")
    end

    return true
end

--[[ **A click on a bag square**, which is the global every bag button shares
     and the seam Quality Of Life uses for its own click behaviour. ]]--
Stub.containerClicks = {}

function ContainerFrameItemButton_OnClick(button, ignoreModifiers)
    table.insert(Stub.containerClicks,
            { button = button, ignore = ignoreModifiers })
    return true
end

function UnitDebuff(unit, index, onlyDispellable)
    local list = Stub.debuffs[unit]
    if not list then return nil end

    local d = list[index]
    if not d then return nil end

    --[[ The third argument asks for auras *this character* can remove. Modelled
         rather than ignored: a stub that answered the same list either way
         would let a filter that never filters pass. ]]--
    if onlyDispellable and not d.dispellable then return nil end

    return d.texture, d.count, d.dtype
end

--[[ Debuff-type colours, keyed as the client keys them -- by the string
     `UnitDebuff` returns, with "none" for an aura that has no type. ]]--
DebuffTypeColor = {
    none    = { r = 0.80, g = 0.00, b = 0.00 },
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
}

--[[ The four debuff buttons and the dispel overlay each party frame carries.

     Added because the party module drives exactly these: it fills the `Icon`,
     colours the `Border`, writes the `Count` and shows the `Status`. Without
     them the whole debuff pass would run against nothing and report success. ]]--
for i = 1, 4 do
    local parent = _G["PartyMemberFrame" .. i]
    local base = "PartyMemberFrame" .. i

    _G[base .. "Status"] = parent:CreateTexture(base .. "Status", "OVERLAY")

    for d = 1, 4 do
        local name = base .. "Debuff" .. d
        local button = CreateFrame("Button", name, parent)
        button:SetWidth(17)
        button:SetHeight(17)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", (d - 1) * 18, -20)
        button:Hide()

        _G[name .. "Icon"] = button:CreateTexture(name .. "Icon", "ARTWORK")
        _G[name .. "Border"] = button:CreateTexture(name .. "Border", "OVERLAY")
        _G[name .. "Count"] = newFontString(button, "OVERLAY", "NumberFontNormal")
    end
end

--[==[ **Nameplates addressable as units, which vanilla cannot do.**

     SuperWoW answers a nameplate frame's `GetName(1)` with its unit's GUID, and
     that GUID is a unit token: every unit function works on it, including
     `guid .. "target"`. That is the whole of per-plate threat -- "what is this
     mob attacking" asked of every plate on screen rather than of the one mob
     `targettarget` covers.

     Keyed by a token shape rather than folded into the catch-all below, which
     answers yes to any unit at all while you have a target. A stale token has
     to be able to come back *no*, or a recycled plate keeps the previous mob's
     answers and the test agrees with it. ]==]
Stub.plateUnits = nil

local function isPlateToken(unit)
    return type(unit) == "string" and string.sub(unit, 1, 7) == "0xPLATE"
end

local function plateTokenTargeted(unit)
    if type(unit) ~= "string" then return nil end

    local length = string.len(unit)
    if length <= 6 or string.sub(unit, length - 5) ~= "target" then return nil end

    local owner = string.sub(unit, 1, length - 6)
    if not isPlateToken(owner) then return nil end

    return owner
end

function Stub.PlateUnit(unit)
    if not Stub.plateUnits then return nil end
    return Stub.plateUnits[unit]
end

--[[ Party units exist when the group has that many members, which is what the
     party frames ask before they paint anything. `UnitExists` above answers for
     the player and the target only; this is the group half of it. ]]--
local baseUnitExists = UnitExists
local baseUnitIsUnit = UnitIsUnit
local baseUnitCanAssist = UnitCanAssist

function UnitIsUnit(a, b)
    local owner = plateTokenTargeted(a)
    if owner and b == "player" then
        local plate = Stub.PlateUnit(owner)
        return (plate and plate.target == "player") and 1 or nil
    end

    return baseUnitIsUnit(a, b)
end

--[[ The catch-all below answers "yes, you could help it" for anything it does
     not recognise, so a plate token has to be answered before it reaches
     there -- otherwise every mob reads as friendly and no plate has a state. ]]--
function UnitCanAssist(a, b)
    if isPlateToken(b) then
        local plate = Stub.PlateUnit(b)
        return (plate and plate.friendly) and 1 or nil
    end

    return baseUnitCanAssist(a, b)
end

--[[ `mouseover` exists whenever the cursor is over anything at all -- a mob, a
     party frame, an item in a bag. It is deliberately *not* the same question as
     "which nameplate is hovered": the plate module pairs it with the plate's own
     glow region, because neither half answers that alone. ]]--
Stub.mouseover = nil

function UnitExists(unit)
    if unit == "mouseover" then return Stub.mouseover and 1 or nil end

    --[[ The target token first: `guid .. "target"` starts with the guid, so
         asked the other way round every "what is it attacking" is answered as
         "is there a mob called <guid>target", which there never is. ]]--
    local owner = plateTokenTargeted(unit)
    if owner then
        local plate = Stub.PlateUnit(owner)
        return (plate and plate.target) and 1 or nil
    end

    if isPlateToken(unit) then
        return Stub.PlateUnit(unit) and 1 or nil
    end

    if type(unit) == "string" and string.find(unit, "^party%d") then
        local index = tonumber(string.sub(unit, 6))
        return (index and Stub.group and Stub.group[index]) and 1 or nil
    end

    --[==[ **A raid member exists**, which this could not say: `raid7` fell
         through to the target's existence, so no raid unit was ever anything to
         the harness -- and a range check that asks `UnitExists` first before
         reading `CheckInteractDistance`'s nil as "too far" answered "in range"
         for the whole raid. Resolved the way the roster reader resolves it. ]==]
    if type(unit) == "string" and string.find(unit, "^raid%d") then
        local index = tonumber(string.sub(unit, 5))
        local member = index and ((Stub.raidRoster and Stub.raidRoster[index])
                or (Stub.group and Stub.group[index]))
        return member and 1 or nil
    end

    return baseUnitExists(unit)
end

-- ---------------------------------------------------------------------------
-- a boot is a fresh login for the client's frames too
-- ---------------------------------------------------------------------------

--[==[ **The client rebuilds its own interface on every login. This stub did
     not, and that difference invented bugs.**

     A `boot()` re-runs the addon's files, so a module gets a new table and
     captures the client's layout again from scratch. The frames it captures,
     though, were the same Lua tables the *previous* boot had finished moving --
     so from the second boot onwards a module recorded "the client keeps
     BuffButton0 against EquadisOverhaulBuffAnchorV2" and dutifully put it back
     there when it was switched off.

     Three restore tests failed on exactly that, and every one of them was
     testing correct code. Measured rather than reasoned about: a probe booting
     three times printed `BuffFrame` captured on boot one and
     `EquadisOverhaulBuffAnchorV2` on boots two and three.

     It only began to matter when the modules started shipping switched on.
     Before that most boots left the client's frames alone, so the contamination
     had nothing to carry.

     What is restored is everything an addon can touch: where a frame sits, what
     it hangs off, how big it is, whether it is up, the handlers on it, the
     fields written to it, the globals around it, and aux's modules. It grew from
     the first of those to all of them one failure at a time, and the lesson each
     time was the same -- half a rebuild is worse than none, because the addon
     then re-installs against a client that is only partly itself.

     Visibility is poked into the field rather than set through `Show`/`Hide` on
     purpose: the previous boot's `OnShow` is still attached at that moment, and
     running dead addon code during the reset is precisely the contamination
     this exists to remove. ]==]

local clientObjects = {}
local clientState = {}

--[[ The four fields that are tables with identity rather than values: each is
     restored by its own contents, and `children` by `SetParent` from both
     sides. See `Stub.ResetSession`. ]]--
local STRUCTURAL = { points = true, scripts = true, events = true, children = true }

local function copyTable(t)
    local out = {}
    if t then for k, v in pairs(t) do out[k] = v end end
    return out
end

local function copyPoints(f)
    local out = {}
    for i = 1, table.getn(f.points or {}) do
        local p = f.points[i]
        out[i] = { p[1], p[2], p[3], p[4], p[5] }
    end
    return out
end

--[==[ **The client's frames and its regions, in one list.**

     A texture is not a frame and is every bit as much of the client's own
     interface: the party marker on the world map is a texture called
     `WorldMapParty1Icon`, and the module that recolours it by class remembers
     the client's dot the first time it sees one.

     Left out of this, that memory was of the *previous* login's class marker --
     so switching the feature off restored a class marker and switching it on
     drew the same one, and a test asking whether the two differed was right to
     say they did not. ]==]
local clientList = {}

for i = 1, table.getn(frames) do clientList[i] = frames[i] end
for i = 1, table.getn(regions) do
    table.insert(clientList, regions[i])
end

for i = 1, table.getn(clientList) do
    local f = clientList[i]

    clientObjects[i] = f
    clientState[f] = {
        parent = f.parent,
        points = copyPoints(f),
        scale = f.scale,
        alpha = f.alpha,
        width = f.width,
        height = f.height,
        shown = f.shown,

        --[==[ **And its handlers, which is where a login's hooks live.**

             An addon does not replace a client frame's script, it wraps it: read
             the old one, install one that calls it. That is correct in the game,
             where the frame is rebuilt from XML on every reload and each session
             wraps a clean handler exactly once.

             Here the frame outlived the login, so every boot wrapped the
             previous boot's wrapper. A chat window switched off still scrolled,
             because the handler doing the scrolling belonged to a login two
             boots back reading a profile where the wheel was on -- a failure
             with no possible cause in the code being tested.

             `Stub.ResetChatFrames` was the first instance of this, found and
             fixed one field at a time; this is the general case it belongs
             to. ]==]
        scripts = copyTable(f.scripts),
        events = copyTable(f.events),

        --[==[ **And everything else the frame is carrying.**

             An addon does not only move a client frame, it writes on it: the
             font string it made for the charges, the flag saying its drag
             handlers are installed, the note that this button is hidden by a
             count. All of it is thrown away when the client rebuilds the frame
             at the next login, and all of it was surviving here.

             That combination is worse than either half. The handlers above are
             put back to the client's own, so the addon has to install its own
             again -- and a flag saying "already installed" that outlived the
             thing it was describing means it never does. Two crashes in this
             suite were exactly that: a chat edit box and a paper doll model
             whose drag handler was guarded by a note left on the frame by a
             login that is over.

             The four structural fields are left out because they are tables
             with identity: they are put back by contents just above, and
             `children` is maintained from both sides by `SetParent`. ]==]
        fields = copyTable(f),
    }
end

--[==[ **The client's own globals, and what they held before any addon ran.**

     An addon hooks a client function the way it hooks a script: keep the old
     one in a global of its own, install one that calls it. `ReloadUI` throws
     both away and the client's own is what the next login finds.

     Here the client's global kept the *previous* login's wrapper, so each boot
     wrapped a wrapper. Left alone that is a slow leak; paired with clearing the
     addon's globals -- which is what makes a login a login -- it is a disaster,
     because the addon then saves a wrapper as "the client's own" and calls into
     a chain that doubles in length every boot. The suite stopped finishing.

     So both halves belong together: the addon's globals go, and the client's
     come back to what the client had. ]==]
local clientGlobals = {}

for k, v in pairs(_G) do clientGlobals[k] = v end

function Stub.ResetGlobals()
    for k, v in pairs(clientGlobals) do
        if _G[k] ~= v then _G[k] = v end
    end
end

--[[ The window a boot's own frames are built in. See `Stub.RetireLoadedFrames`
     for what that mark is for. ]]--
function Stub.BeginAddonLoad() addonLoading = true end
function Stub.EndAddonLoad() addonLoading = false end

--[==[ **And the previous boot's addon is gone, the way a login makes it gone.**

     `FireEvent` and `Tick` walk every frame ever created, so a module from boot
     one was still registered for `PLAYER_ENTERING_WORLD` and still ticking
     during boot two -- and it answered, and re-applied its layout onto its own
     dead anchors. That is what beat the restore above: the frames were put back
     to the client's own by this reset and moved off again by a module that no
     longer exists, before the live module ever looked at them.

     A login destroys the previous session's frames outright. Modelled by
     dropping them from the dispatch list: they stay valid Lua tables for
     anything still holding one, and stop being asked to do anything.

     It is also what the suite's cost was made of. Every boot left its whole
     interface behind, so the hundred and twenty-fifth login dispatched every
     event to a hundred and twenty-five addons. ]==]
function Stub.RetireLoadedFrames()
    local kept, n = {}, 0

    for i = 1, table.getn(frames) do
        local f = frames[i]

        if f and f.fromAddonLoad then
            --[[ And its name stops answering. `CreateFrame` publishes a named
                 frame as a global, and an addon that asks whether its own frame
                 exists yet is asking that global -- so one left behind by the
                 previous boot reads as "already built" and the build is
                 skipped.

                 The game menu is the case that showed it: ECO guards its button
                 on `getglobal(name)`, correctly, because that guard stops a
                 second button being added within one session. Across two logins
                 in one interpreter it read as a button already there, so the
                 menu was never re-grown and the buttons under it never moved.

                 Only where the global still points at the retired frame -- a
                 boot that has already replaced it owns the name now. ]]--
            if f.name and _G[f.name] == f then _G[f.name] = nil end
        else
            n = n + 1
            kept[n] = f
        end
    end

    --[[ Written back into the same table rather than swapped for a new one:
         `FireEvent` and `Tick` close over this one. ]]--
    for i = table.getn(frames), 1, -1 do frames[i] = nil end
    for i = 1, n do frames[i] = kept[i] end
end

--[[ One login's worth of teardown, in the order it has to happen: the dead
     addon goes first, then the client is put back to itself. ]]--
function Stub.ResetSession()
    Stub.RetireLoadedFrames()
    Stub.ResetGlobals()
    Stub.ResetAux()

    for i = 1, table.getn(clientObjects) do
        local f = clientObjects[i]
        local was = clientState[f]

        if f and was then
            --[[ Through `SetParent`, which is the one field with bookkeeping on
                 the other side of it: the old parent's child list has to lose
                 this frame and the new one has to gain it. ]]--
            if f.parent ~= was.parent and f.SetParent then
                f:SetParent(was.parent)
            end

            f.points = copyPoints(was)

            --[[ Refilled rather than replaced: `FireEvent` and `Tick` reach
                 these tables through the frame, but a handler installed during
                 the previous login may be holding one directly. ]]--
            if f.scripts then
                for k in pairs(f.scripts) do f.scripts[k] = nil end
                for k, v in pairs(was.scripts) do f.scripts[k] = v end
            end

            if f.events then
                for k in pairs(f.events) do f.events[k] = nil end
                for k, v in pairs(was.events) do f.events[k] = v end
            end

            --[[ Anything the addon added is gone, and anything it changed is
                 back to what the client had. ]]--
            for k in pairs(f) do
                if not STRUCTURAL[k] and was.fields[k] == nil then f[k] = nil end
            end

            for k, v in pairs(was.fields) do
                if not STRUCTURAL[k] and f[k] ~= v then f[k] = v end
            end
        end
    end
end

return Stub
