--[[ Equadis' Classic Overhaul :: render

  The bar and segment factories, and everything that paints them.

  Nothing here knows what a slot contains or which module is drawing. A module
  asks for a bar, hands it a fraction, and gets a bar filled to that fraction.

  One rule governs this whole file, and it is the most important constraint in
  the codebase (RogueBars HANDOFF section 5.2):

      A bar draws its own fill texture. The StatusBar widget's built-in fill is
      never used for anything partial or reversed.

  Vanilla 1.12 has no SetReverseFill, and the widget re-lays its texture out
  internally on a schedule Lua cannot see, so anything set from here is applied
  inconsistently and shows up as stretched art or gaps. Three separate attempts
  to work around that failed in three different ways.

  RogueBars kept combo points on the native fill because they are always drawn
  at 100%, and its own handover notes flagged that as a trap waiting to be
  sprung. Here every bar owns a fill without exception, and the frames are plain
  Frames rather than StatusBars -- with no native fill in the object at all, the
  rule cannot be broken by accident.
]]--

local OB = EquadisClassicOverhaul

local floor = math.floor

-- ---------------------------------------------------------------------------
-- fonts
-- ---------------------------------------------------------------------------

--[[ **The look, for one subsystem or for all of them.**

     Texture, font, font size, outline and border are the five settings that make
     five separate addons look like five separate addons. They belong to the
     profile, so setting them once sets them everywhere -- that is the whole
     premise of this addon and it is the reason they were global from the start.

     A subsystem may still disagree. Nameplates want a smaller font than a HUD
     bar does, and a damage meter's rows want a flatter texture than a health
     bar. So each carries the same five keys and a switch, and the switch is on
     by default: **share the look unless you say otherwise.**

     One accessor rather than each module reading the profile itself, because the
     override has to be checked in the same place every time. A module that read
     `OB.profile.texture` directly would be right until somebody used the
     override, and then wrong in exactly one place nobody would look. ]]--
local LOOK_KEYS = { "texture", "font", "fontSize", "fontOutline", "border" }

--[[ **One table per module, refilled rather than rebuilt.**

     This was the addon's largest single allocator, and it did not look like one:
     five keys copied into a fresh table, which is nothing. What made it the
     largest was where it is called from. `OB.ApplyFont` asks for a look *and*
     asks `OB.FontPath`, which asks for the look again -- two tables per call --
     and the tooltip styles every line on both sides on every tick it is on
     screen. A twenty-line tooltip is 160 tables a tick. Measured: 3879 kB
     across 159 calls, 24 kB each.

     Refilling one table per module costs nothing and needs no invalidation,
     which is the point: a cache with a lifetime is a cache that can be stale,
     and this has to be right the instant a setting changes.

     **The returned table is shared and is overwritten by the next call for the
     same module.** Every caller reads its fields immediately, which is what
     makes that safe; one that wanted to keep a look would need a copy. That is
     already the contract for the two paths below, which hand back the profile
     itself. ]]--
local lookCache = {}

function OB.Look(moduleId)
    local profile = OB.profile
    if not moduleId then return profile end

    local cfg = profile.modules and profile.modules[moduleId]
    if not cfg then return profile end

    local look = lookCache[moduleId]

    if not look then
        look = {}
        lookCache[moduleId] = look
    end

    --[[ Falls back key by key rather than wholesale. A subsystem saved before a
         look key existed has no value for it, and inheriting the shared one is
         right -- inheriting nothing would draw an invisible bar. ]]--
    for i = 1, table.getn(LOOK_KEYS) do
        local key = LOOK_KEYS[i]
        if cfg[key] ~= nil then look[key] = cfg[key] else look[key] = profile[key] end
    end

    return look
end

--[[ Dropped when the profile itself is replaced. The tables would refill
     correctly anyway -- they are rewritten on every call -- but a module that
     existed in the old profile and not the new one would keep a table nothing
     will ever ask for again. ]]--
function OB.ForgetLooks()
    lookCache = {}
end

function OB.FontPath(moduleId)
    local look = OB.Look(moduleId)

    return OB.fontPaths[look.font]
            or OB.fontPaths[OB.fontIndex["Roboto"]]
            or STANDARD_TEXT_FONT
end

--[[ Every font string the addon has made, so the self-test can walk them.

     Append-only, which is fine at the ~150 strings the HUD and the panel come to
     and is the reason nothing here is ever destroyed anyway. Phase 4's meter
     rows are the exception to watch: ShaguDPS recycles its rows, so those must
     not each register or this becomes leak-shaped. ]]--
OB.texts = {}

--[[ Create a font string that is safe to touch.

     A FontString created with no inherited template has no font object at all,
     and in 1.12 colouring or measuring one that has no font object is an error
     rather than a no-op. That is not hypothetical: one bare
     CreateFontString(nil, "OVERLAY") followed by SetTextColor threw partway
     through building the options panel's General page, which aborted the build
     and shipped a settings window with one sidebar entry and no controls -- past
     a green test suite, because the stub recorded the colour and said nothing.

     Going through here means the rule cannot be broken by forgetting an
     argument, and the registry means the self-test can prove it against the real
     client instead of assuming it. ]]--
function OB.NewText(parent, layer, template)
    local text = parent:CreateFontString(nil, layer or "OVERLAY",
            template or "GameFontNormal")

    table.insert(OB.texts, text)
    return text
end

--[[ **Every font string a bar owns, named once.**

     Four of them now -- a label, two columns and the rate the threat meter added
     -- and anything that styles text has to reach all four. Keeping the list
     here rather than repeating it at each call site is the whole fix for the bug
     that prompted it: `extra` was added to the bar and not to the styling pass,
     so one column ignored the font setting while its neighbours followed it.

     Order is cosmetic. Membership is not. ]]--
OB.BAR_TEXTS = { "left", "right", "center", "extra" }

--[[ Apply the configured family, size and outline. A missing or unreadable .ttf
     makes SetFont fail silently and leaves the string invisible, so fall back to
     the client font when that happens. ]]--
--[[ `force` is passed by callers that draw onto something other than a backdrop
     of their own -- nameplates, which draw onto the world. Unoutlined text over
     terrain does not read as plainer, it disappears, and it disappears
     differently depending on which way the camera is facing. The caller decides
     whether that applies to it; this only honours the request. ]]--
function OB.ApplyFont(fontstring, size, moduleId, force)
    if not fontstring then return end

    local look = OB.Look(moduleId)

    --[[ `force` is for text that must carry an outline whatever the profile
         says -- a label over artwork -- so it lifts a "None" to thin and leaves
         a thick one alone. ]]--
    local outline = OB.FontFlags(look.fontOutline)
    if force and not outline then outline = "OUTLINE" end

    size = size or look.fontSize

    local path = OB.FontPath(moduleId)

    --[[ **Nothing to do if it already says that.**

         `SetFont` is not free even when the font does not change -- it is a
         client call that re-resolves the file and re-measures the string -- and
         the tooltip asks for every line on both sides on every tick it is on
         screen. Nothing about the answer changes between two ticks.

         Remembered on the FontString rather than in a table beside it, because
         these are the client's own objects and outlive anything this addon
         keeps: a line created for one tooltip is reused for the next. ]]--
    if fontstring.eqEcoFontPath == path
            and fontstring.eqEcoFontSize == size
            and fontstring.eqEcoFontOutline == outline then
        return
    end

    fontstring:SetFont(path, size, outline)

    if not fontstring:GetFont() then
        fontstring:SetFont(STANDARD_TEXT_FONT, size, outline)
        path = STANDARD_TEXT_FONT
    end

    --[[ Recorded after the fallback, so what is remembered is what the
         FontString actually ended up with rather than what was asked for. ]]--
    fontstring.eqEcoFontPath = path
    fontstring.eqEcoFontSize = size
    fontstring.eqEcoFontOutline = outline
end

-- ---------------------------------------------------------------------------
-- text
-- ---------------------------------------------------------------------------

--[[ Shared by every module that shows a value, so "Current / Max" means the same
     thing on the resource bar and the health bar. RogueBars had this reading the
     energy element's setting directly; the mode is a parameter here. ]]--
function OB.FormatValue(value, max, mode)
    if mode == "none" then return "" end

    value = value or 0
    max = max or 0

    -- one place decides what a percentage is, so every mode that shows one
    -- rounds the same way
    local function percent()
        if max == 0 then return "0%" end
        return floor((value / max) * 100 + 0.5) .. "%"
    end

    if mode == "percent" then return percent() end
    if mode == "max" then return value .. "/" .. max end
    if mode == "valuepct" then return value .. " (" .. percent() .. ")" end
    if mode == "maxpct" then return value .. "/" .. max .. " (" .. percent() .. ")" end

    return "" .. value
end

-- ---------------------------------------------------------------------------
-- geometry helpers
-- ---------------------------------------------------------------------------

function OB.BorderPad(moduleId)
    return OB.borderPads[OB.Look(moduleId).border] or 0
end

--[[ One header button carrying an icon, shared by every window with a header.

     Here rather than in either meter because both grew one and a second copy is
     how two windows in the same addon end up with buttons of different sizes.

     The art is white line work on transparent, so the tint is set here rather
     than baked into more files. `SetVertexColor` on the texture region, not
     alpha on the frame: frame alpha would fade the backdrop with it. ]]--
function OB.IconButton(parent, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(16)
    b:SetHeight(14)
    --[==[ The same face and edge the panel's own buttons wear. This was a
         grey box with a grey line round it, which is what the whole interface
         looked like before there was a palette to disagree with. ]==]
    b:SetBackdrop(OB.backdrop)

    local face = OB.skin and OB.skin.raised or { 0.2, 0.2, 0.22, 1 }
    local edge = OB.skin and OB.skin.goldDim or { 0.4, 0.4, 0.4 }

    b:SetBackdropColor(face[1], face[2], face[3], face[4] or 1)
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)

    --[[ The quest-log gradient has the quest log's proportions baked in and was
         being stretched across a sixteen-pixel button. ]]--
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 1)
    b.icon:SetVertexColor(0.85, 0.85, 0.85, 1)

    b.SetIcon = function(self, name)
        self.icon:SetTexture(OB.icons[name])
    end

    b:SetIcon(icon)

    return b
end

function OB.TexturePath(moduleId)
    local look = OB.Look(moduleId)
    return OB.textures[look.texture] or OB.textures[1]
end

-- ---------------------------------------------------------------------------
-- bars
-- ---------------------------------------------------------------------------

--[[ Build a bar.

     Frame layering, lowest first:

       bar          the rect itself; mouse enabled for drag and right-click
         bg         background colour, edge to edge
         fill       the only fill that matters
         overlay    lazily built: five-second-rule shading, band tinting
         spark      lazily built: the regeneration ticker
       border       its own frame one level up
       textLayer    one level above the border

     The border sits on a dedicated frame above the bar, and the text one level
     above that. Putting the text on the bar itself leaves it *below* the border,
     and a Standard border then cuts through the numbers. ]]--
function OB.CreateBar(name, parent)
    local bar = CreateFrame("Frame", name, parent)
    bar:SetFrameLevel(parent:GetFrameLevel() + 2)
    bar:EnableMouse(true)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.fill:Hide()

    bar.border = CreateFrame("Frame", nil, bar)
    bar.border:SetFrameLevel(bar:GetFrameLevel() + 1)
    bar.border:Hide()

    bar.textLayer = CreateFrame("Frame", nil, bar)
    bar.textLayer:SetAllPoints(bar)
    bar.textLayer:SetFrameLevel(bar.border:GetFrameLevel() + 1)

    --[[ The colour is stated here rather than inherited. These three used to be
         template-less and so drew in the default white; taking a template to get
         a font object also brings that object's colour with it, and a bar's
         numbers silently turning yellow is exactly the kind of drift that gets
         noticed three sessions later. GameFontHighlight is already white, and
         the explicit SetTextColor makes that a fact of this file rather than of
         whatever Blizzard ships. ApplyFont replaces face, size and outline a
         moment later, so colour is the only thing a template could leak. ]]--
    --[[ Three text **slots**, not three positions. The names are historical: each
         one used to be nailed to an edge, and now every one of them is placed by
         OB.SetBarText wherever its module's position setting says. A module still
         picks a slot per label so two labels cannot collide by accident, but
         which end of the bar a slot sits at is the player's business. ]]--
    bar.left = OB.NewText(bar.textLayer, "OVERLAY", "GameFontHighlight")
    bar.left:SetJustifyH("CENTER")
    bar.left:SetTextColor(1, 1, 1)
    bar.left:SetPoint("LEFT", bar, "LEFT", 3, 0)

    bar.right = OB.NewText(bar.textLayer, "OVERLAY", "GameFontHighlight")
    bar.right:SetJustifyH("CENTER")
    bar.right:SetTextColor(1, 1, 1)
    bar.right:SetPoint("RIGHT", bar, "RIGHT", -3, 0)

    bar.center = OB.NewText(bar.textLayer, "OVERLAY", "GameFontHighlight")
    bar.center:SetJustifyH("CENTER")
    bar.center:SetTextColor(1, 1, 1)
    bar.center:SetPoint("CENTER", bar, "CENTER", 0, 0)

    --[[ A fourth slot, for a row that needs three columns of numbers rather than
         two: the threat meter shows a figure, a rate and a share.

         Two figures sharing one string cannot line up -- the second one's left
         edge moves with the width of the first, so a four digit threat on one
         row and a two digit one on the next put the rates in different places.
         A column has to be its own font string to be a column at all. ]]--
    bar.extra = OB.NewText(bar.textLayer, "OVERLAY", "GameFontHighlight")
    bar.extra:SetJustifyH("LEFT")
    bar.extra:SetTextColor(1, 1, 1)
    bar.extra:SetPoint("CENTER", bar, "CENTER", 0, 0)

    return bar
end

--[[ Put a label somewhere along the bar: 0 is hard left, 100 hard right.

     A position rather than a side. "Left or right" was two choices and a swap
     switch to get between them; this is the same thing with the whole width in
     between, and it costs one slider instead of one boolean per pair of labels.

     The clamp is the part worth reading. The anchor is the label's *centre*, so
     at either extreme half of it would hang off the end -- so the travel stops
     when an edge is reached rather than letting the text leave the bar. A label
     wider than the bar is centred, because there is no position that helps and
     jammed against one edge is worse than jammed in the middle. ]]--
local TEXT_PAD = 3

--[[ **What separates two numbers sharing one label.**

     The meters put several figures in a single font string -- total, rate and
     share on one row -- and how far apart they read is decided here, once, for
     both. Two spaces ran them together at the sizes people actually use; this is
     wide enough to scan as columns without a monospace font.

     Shared rather than written into each meter, because two meters open side by
     side that space their numbers differently is the kind of difference nobody
     can name but everybody notices. ]]--
OB.COLUMN_GAP = "    "

function OB.PlaceText(bar, text, pos)
    local frac = (pos or 50) / 100
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end

    local width = bar:GetWidth() or 0
    local half = (text:GetStringWidth() or 0) / 2

    local x = TEXT_PAD + (frac * (width - (TEXT_PAD * 2)))
    local low, high = TEXT_PAD + half, width - TEXT_PAD - half

    if high < low then
        x = width / 2
    elseif x < low then
        x = low
    elseif x > high then
        x = high
    end

    text:ClearAllPoints()
    text:SetPoint("CENTER", bar, "LEFT", x, 0)
end

--[[ **A column of numbers, flush left at a shared edge.**

     `PlaceText` centres one string on a point, which is right for a label and
     wrong for a column: every row's numbers are a different width, so centring
     or right-aligning them leaves the digits ragged down the window. Nothing
     lines up with anything.

     So the meters measure their widest row first and start every row's numbers
     at the same x, left justified. The block as a whole still sits against the
     right edge -- it is only the rows that align with each other.

     `x` is the distance from the bar's left edge to where the text begins. ]]--
function OB.PlaceTextLeftAt(bar, text, x)
    text:SetJustifyH("LEFT")
    text:ClearAllPoints()
    text:SetPoint("LEFT", bar, "LEFT", x, 0)
end

--[[ Where a right-hand column of `widest` pixels has to start for the block to
     finish on the bar's right edge, never crossing into the left label. ]]--
function OB.ColumnStart(bar, widest, leftUsed)
    local width = bar:GetWidth() or 0
    local x = width - TEXT_PAD - (widest or 0)

    local floorAt = (leftUsed or 0) + TEXT_PAD + TEXT_PAD
    if x < floorAt then x = floorAt end
    if x < TEXT_PAD then x = TEXT_PAD end

    return x
end

--[[ **How much room the left label has**, once the numbers on the right have
     taken theirs.

     The counterpart to ColumnStart, and the half that was missing. ColumnStart
     alone answers "where do the numbers begin", and when the answer collided
     with a long name it resolved the collision by moving the numbers *right* --
     off the end of the bar, so the last column ran past the window edge and the
     trailing "%" was cut off. That is the reported "it's cut short".

     A name is recognisable from its first several letters and a total is not
     recognisable from its first two digits, so when the two cannot both fit it
     is the name that gives way. Every meter that has solved this has solved it
     this way round. ]]--
function OB.NameRoom(bar, widest)
    local width = bar:GetWidth() or 0
    local room = width - (TEXT_PAD * 3) - (widest or 0)

    if room < 0 then room = 0 end
    return room
end

--[[ **A label cut to fit, with the cut marked.**

     1.12 font strings do not truncate: given a width they wrap onto a second
     line, which inside a fifteen-pixel bar means a name sliced through the
     middle horizontally. So the trimming is done to the string itself.

     **Seeded proportionally rather than walked from the end.** Measuring is a
     call into the font engine and this runs per row per redraw -- a dozen rows
     several times a second. Character width is near enough uniform that
     `n * (room / width)` lands within a character or two, so the loop that
     follows almost never runs more than twice; walking one character at a time
     from full length cost a dozen measurements a row for the same answer.

     Remembered against the string and the width it was fitted to, because
     neither changes between most redraws and re-deriving an unchanged answer is
     the whole cost. ]]--
function OB.FitTextTo(text, full, maxWidth)
    full = full or ""

    --[[ The font size is part of the key as much as the string is: the same
         name in the same room fits at ten points and does not at fourteen, and
         a cache that watched only the text would keep the ten-point trim after
         a restyle raised the size. ]]--
    local _, size = text:GetFont()

    if text.ecoFitFull == full and text.ecoFitMax == maxWidth
            and text.ecoFitSize == size then
        return
    end

    text.ecoFitFull = full
    text.ecoFitMax = maxWidth
    text.ecoFitSize = size

    text:SetText(full)

    if not maxWidth or maxWidth <= 0 then return end

    local width = text:GetStringWidth() or 0
    if width <= maxWidth then return end

    local n = string.len(full)
    local keep = math.floor(n * (maxWidth / width))

    if keep >= n then keep = n - 1 end
    if keep < 1 then keep = 1 end

    text:SetText(string.sub(full, 1, keep) .. "..")

    --[[ Down if the guess was long, up if it was short. Both directions,
         because a proportional guess is as likely to under-fill the space as to
         overflow it and a name cut shorter than it needed to be is the same
         defect in the other direction. ]]--
    while keep > 1 and (text:GetStringWidth() or 0) > maxWidth do
        keep = keep - 1
        text:SetText(string.sub(full, 1, keep) .. "..")
    end

    while keep < n - 1 do
        text:SetText(string.sub(full, 1, keep + 1) .. "..")

        if (text:GetStringWidth() or 0) > maxWidth then
            text:SetText(string.sub(full, 1, keep) .. "..")
            return
        end

        keep = keep + 1
    end
end

--[[ Set a label and place it, in that order.

     The order is not incidental: the clamp needs the rendered width, and a font
     string has none until it has been given something to say. ]]--
function OB.SetBarText(bar, text, value, pos)
    text:SetText(value or "")
    OB.PlaceText(bar, text, pos)
end

-- built on demand: most bars never shade anything
function OB.BarOverlay(bar)
    if not bar.overlay then
        bar.overlay = bar:CreateTexture(nil, "ARTWORK")
        bar.overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        bar.overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        bar.overlay:Hide()
    end
    return bar.overlay
end

-- likewise: only ticking resources have a spark
function OB.BarSpark(bar)
    if not bar.spark then
        bar.spark = bar.textLayer:CreateTexture(nil, "OVERLAY")
        bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        bar.spark:SetBlendMode("ADD")
        bar.spark:SetWidth(20)
        bar.spark:SetPoint("CENTER", bar, "LEFT", 0, 0)
        bar.spark:Hide()
    end
    return bar.spark
end

--[[ Fill a bar to `fraction` (0-1) from the left, or from the right when
     flipped.

     Lifted from RogueBars, comment and all, because the reasoning is what
     matters. The crop and the drawn width are always derived from the *same*
     fraction: if those two ever diverge the art stretches, and a stretched
     texture is a subtle enough fault to lose an afternoon to. ]]--
function OB.SetBarFill(bar, fraction, flip)
    local fill = bar.fill
    if not fill then return end

    if not fraction or fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end

    --[[ Kept on the bar after clamping, which is the only place the number
         survives: everything below turns it into a width and a texture crop, and
         neither can be read back as the fraction that produced it.

         Worth one field. "The bar does not fill all the way" is a report that
         cannot be checked without it -- and it was one. ]]--
    bar.fillFraction = fraction

    local width = bar:GetWidth() * fraction
    if width < 1 then
        fill:Hide()
        return
    end

    fill:ClearAllPoints()
    if flip then
        fill:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        fill:SetTexCoord(1 - fraction, 1, 0, 1)
    else
        fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
        fill:SetTexCoord(0, fraction, 0, 1)
    end

    fill:SetWidth(width)
    fill:Show()
end

-- the same discipline for the shading overlay, which spans 0..fraction too
function OB.SetBarOverlay(bar, fraction, flip, r, g, b, a)
    local overlay = OB.BarOverlay(bar)

    if not fraction or fraction <= 0 then
        overlay:Hide()
        return
    end
    if fraction > 1 then fraction = 1 end

    local width = bar:GetWidth() * fraction
    if width < 1 then
        overlay:Hide()
        return
    end

    overlay:ClearAllPoints()
    if flip then
        overlay:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
        overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    else
        overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        overlay:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    end

    overlay:SetTexture(r, g, b, a)
    overlay:SetWidth(width)
    overlay:Show()
end

--[[ A 1px full-height marker at a fixed point along the bar: the range readout's
     dead zone edge, the rage decay projection.

     Ticks are indexed because a bar may carry several, and they are built on
     demand like the spark and the overlay -- most bars never grow one.

     They live on textLayer rather than on the bar, so a tick sits above the fill
     and above the border. A tick under the fill is invisible exactly when the
     bar is full, which is when it is being read. ]]--
function OB.BarTick(bar, index)
    bar.ticks = bar.ticks or {}

    if not bar.ticks[index] then
        local tick = bar.textLayer:CreateTexture(nil, "OVERLAY")
        tick:SetWidth(1)
        tick:Hide()
        bar.ticks[index] = tick
    end

    return bar.ticks[index]
end

--[[ Place tick `index` at `fraction` along the bar.

     The span is bar:GetWidth() for the same reason the spark's is -- see
     OB.DrawSpark. A tick measured against the configured width drifts away from
     the fill it is meant to annotate as soon as the two disagree. ]]--
function OB.SetBarTick(bar, index, fraction, flip, r, g, b, a)
    local tick = OB.BarTick(bar, index)

    if not fraction then
        tick:Hide()
        return
    end

    if fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end

    local x = fraction * bar:GetWidth()

    tick:ClearAllPoints()
    if flip then
        tick:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -x, 0)
        tick:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -x, 0)
    else
        tick:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
        tick:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
    end

    tick:SetTexture(r, g, b, a or 1)
    tick:SetWidth(1)
    tick:Show()
end

function OB.HideBarTicks(bar)
    if not bar.ticks then return end
    for i = 1, table.getn(bar.ticks) do bar.ticks[i]:Hide() end
end

--[[ Sweep the ticker spark across the bar.

     Two things here have both been the cause of a bug that looked like something
     else entirely:

     The phase is *wrapped*, not clamped. Clamping parks the spark against the
     far edge whenever the cycle anchor is stale or sits in the future; wrapping
     makes it always sweep and restart.

     The span is bar:GetWidth(), never the slot's configured width. A different
     span makes the spark arrive early or late, which reads as a *timing* fault
     and sends you hunting a clock bug that does not exist. ]]--
function OB.DrawSpark(bar, start, period, now, flip)
    local spark = OB.BarSpark(bar)

    if not period or period <= 0 then
        spark:Hide()
        return
    end

    local phase = (now - start) / period
    phase = phase - floor(phase)

    local x = phase * bar:GetWidth()

    spark:ClearAllPoints()
    if flip then
        spark:SetPoint("CENTER", bar, "RIGHT", -x, 0)
    else
        spark:SetPoint("CENTER", bar, "LEFT", x, 0)
    end
end

--[[ Re-apply every appearance setting to a bar. Cheap enough to run on each
     refresh, which is what makes a texture or border change instant.

     `width` overrides the slot's own -- combo points and range bands pass their
     segment width. ]]--
--[[ `moduleId` names the subsystem whose look applies, or nil for the shared
     one. Threaded through as an argument rather than read from a global,
     because the whole point of the override is that two things on screen at
     once are allowed to disagree. ]]--
function OB.StyleBar(bar, slot, width, moduleId)
    if not bar then return end

    bar:SetWidth(width or slot.w)
    bar:SetHeight(slot.h)

    bar.fill:SetTexture(OB.TexturePath(moduleId))

    local bg = slot.bg or { 0, 0, 0, 0.5 }
    bar.bg:SetTexture(bg[1], bg[2], bg[3], bg[4] or 0.5)

    local pad = OB.BorderPad(moduleId)

    --[==[ Sized against the border frame rather than the bar: it is the frame
         the backdrop is drawn on, and it is `pad` larger on every side. Asking
         about the bar would clamp a fraction too hard and leave a border
         thinner than it had room for. ]==]
    local edge = OB.BorderEdge(OB.Look(moduleId).border,
            (width or slot.w) + (pad * 2), slot.h + (pad * 2))

    if pad > 0 and edge then
        --[==[ **Hung by the ink, not by the reserved room -- two different
             questions that `OB.BorderPad` was answering with one number.**

             Layout asks "how much room does a border need beside this bar", and
             a constant per style is right for that: bars of different heights
             have to space the same or the cluster is ragged. That is what
             `OB.borderPads` is and it stays.

             Drawing asks "how far out do I hang the frame so the art lands on
             the bar", and the answer is the edge's own `outset` at the size it
             is actually drawn -- which `OB.BorderEdge` has just scaled for this
             bar. Using the layout number for it is a guess that happens to be
             right for one style out of three.

             On a twelve pixel bar: `Classic` reserves two and its ink reaches
             one, `Blizzard` reserves five and its narrowed ink reaches under
             four. Both hung the frame further out than the art, leaving a band
             between the bar and the line with nothing drawn in it.

             Clamped to the reserved room, because hanging further out than
             layout allowed for would put the ink in the next bar's gap. ]==]
        local hang = math.floor(tonumber(edge.outset)
                or ((tonumber(edge.edgeSize) or 8) / 2))

        if hang < 1 then hang = 1 end
        if hang > pad then hang = pad end

        bar.border:ClearAllPoints()
        bar.border:SetPoint("TOPLEFT", bar, "TOPLEFT", -hang, hang)
        bar.border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", hang, -hang)
        bar.border:SetBackdrop(edge)
        bar.border:SetBackdropBorderColor(1, 1, 1, 1)
        bar.border:Show()
    else
        bar.border:SetBackdrop(nil)
        bar.border:Hide()
    end

    --[[ **Every text on the bar, and the list is the trap.**

         `bar.extra` arrived with the threat meter's third column and this call
         site was not updated, so the rate column kept whatever `GameFontHighlight`
         is -- 12pt, no outline -- while its neighbours followed the setting. The
         font picker looked broken on exactly one column.

         Written as a loop over a list defined once, so the next column added is
         a name in one place rather than a line somebody has to remember to add
         here as well. ]]--
    local size = slot.textSize or OB.Look(moduleId).fontSize

    for i = 1, table.getn(OB.BAR_TEXTS) do
        OB.ApplyFont(bar[OB.BAR_TEXTS[i]], size, moduleId)
    end

    if bar.spark then bar.spark:SetHeight(slot.h * 2) end
end

--[[ Paint the fill.

     Alpha rides on the fill's vertex colour rather than the frame's. Frame alpha
     would also fade the border, which has to stay solid -- that is RogueBars
     HANDOFF section 5.7, generalised: only leaf regions ever take an alpha. ]]--
function OB.SetBarColor(bar, color, alpha)
    local a = color[4] or 1
    if alpha then a = a * alpha end
    bar.fill:SetVertexColor(color[1], color[2], color[3], a)
end

-- ---------------------------------------------------------------------------
-- segments
-- ---------------------------------------------------------------------------

--[[ A row of equal bars inside one slot rect: five for combo points, four for
     the range bands.

     The container is a plain frame with no art of its own. Each segment is a
     full bar, so a segment can be filled, coloured and dimmed exactly like any
     other bar, and one code path covers both shapes. ]]--
function OB.CreateSegments(name, parent, count)
    local group = CreateFrame("Frame", name, parent)
    group:SetFrameLevel(parent:GetFrameLevel() + 1)
    group.bars = {}

    for i = 1, count do
        group.bars[i] = OB.CreateBar(name .. i, group)
    end

    group.count = count
    return group
end

--[[ Lay the segments out edge to edge across the slot.

     The segment width is floored to a whole pixel so the row sits flush with no
     sub-pixel overlap. When a border is on, the segments are spaced apart inside
     the same total width -- otherwise each point's border stacks on its
     neighbour's, which reads as a double-thick line between them.

     `shown` lays out fewer than were built and hides the rest, so one frame set
     can serve a shape not known until runtime -- 1.12 does not really allow
     creating and destroying frames mid-session, so the maximum is built once and
     the surplus is parked.

     Nothing passes it today. The distance readout did, back when it drew four
     bands on one client and a single continuous bar on another; it draws one bar
     coloured by state on every client now, so combo points -- always five -- is
     the only caller left. Kept because the cost is one `or` and the alternative
     is discovering the constraint again the next time a module wants a count it
     cannot know at load. ]]--
function OB.StyleSegments(group, slot, shown)
    local count = shown or group.count
    if count < 1 then count = 1 end
    if count > group.count then count = group.count end

    group.visible = count

    local pad = OB.BorderPad()

    local gap = 0
    if pad > 0 then gap = (pad * 2) + 1 end

    local segment = floor((slot.w - (gap * (count - 1))) / count)
    if segment < 1 then segment = 1 end

    group:SetWidth(slot.w)
    group:SetHeight(slot.h)

    for i = 1, count do
        local bar = group.bars[i]
        OB.StyleBar(bar, slot, segment)

        bar:ClearAllPoints()
        if i == 1 then
            bar:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)
        else
            bar:SetPoint("TOPLEFT", group.bars[i - 1], "TOPRIGHT", gap, 0)
        end

        bar:Show()
    end

    for i = count + 1, group.count do
        group.bars[i]:Hide()
    end

    group.segmentWidth = segment
end
