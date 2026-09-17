--[[ Equadis' Classic Overhaul :: skin

  **The panel's own chrome, rather than the client's.**

  Every frame in the settings panel was wearing Blizzard's: `UI-DialogBox-Border`
  around the outside, `UIPanelButtonTemplate` on the buttons, the quest-log
  highlight on the sidebar. That is a reasonable way to start and it is why the
  panel has never looked like part of this addon -- it looked like the client's
  own options with somebody else's settings in it.

  **Classic, not vanilla-pastiche.** The feeling to keep is the one vanilla gets
  right: warm near-black, gold on top of it, and hairlines rather than bevels.
  What is not worth keeping is the ornament -- the carved corners and the raised
  metal edges are 2006's way of saying "this is a window", and a modern reading
  of the same palette says it more quietly.

  So: one warm dark ground, one gold, and rules a pixel wide. Nothing here is
  carved, and the only thing that glows is the row you are on.

  **Built from solids on purpose.** `WHITE8X8` is in every client that exists and
  cannot fail to load, which is not true of art -- as this addon found out when
  two of its four borders spent a release resolving to a texture nobody had. A
  panel that draws itself out of coloured rectangles has no such failure mode.
]]--

local OB = EquadisClassicOverhaul

local SOLID = "Interface\\Buttons\\WHITE8X8"

--[[ **One palette, named for what things are rather than what colour they are.**

     `gold` rather than `#ffd100`, so the day somebody wants a green profile the
     names still describe the parts. These are the vanilla values: the gold is
     the client's own quest/heading gold, and the ground is its tooltip black
     warmed slightly so it does not read as blue beside it. ]]--
OB.skin = {
    ground     = { 0.05, 0.043, 0.035, 0.94 },
    raised     = { 0.10, 0.088, 0.070, 1.00 },
    sunken     = { 0.02, 0.018, 0.014, 0.85 },

    gold       = { 1.00, 0.82, 0.00 },
    goldDim    = { 0.62, 0.50, 0.16 },
    goldFaint  = { 1.00, 0.82, 0.00, 0.14 },

    text       = { 0.86, 0.84, 0.78 },
    textDim    = { 0.55, 0.53, 0.48 },

    rule       = { 1.00, 0.82, 0.00, 0.22 },
    ruleFaint  = { 1.00, 1.00, 1.00, 0.07 },
}

local function colour(name)
    return OB.skin[name] or { 1, 1, 1, 1 }
end

--[[ A rectangle of flat colour, anchored by the caller. The panel is built out
     of these, so it is worth one function rather than four lines each time. ]]--
function OB.SkinFill(parent, layer, c)
    if not parent or not parent.CreateTexture then return nil end

    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetTexture(SOLID)

    if c then tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return tex
end

--[[ **A hairline.** One pixel, because the border this addon draws round a
     health bar is one pixel and the panel should not disagree with itself.

     Horizontal when no width is given, vertical when no height is -- which
     means the caller says which kind it is by which measurement it cares
     about. ]]--
function OB.SkinRule(parent, c, w, h)
    local tex = OB.SkinFill(parent, "ARTWORK", c or colour("rule"))
    if not tex then return nil end

    tex:SetWidth(w or 1)
    tex:SetHeight(h or 1)
    return tex
end

--[[ **The panel itself: a ground, a hairline round it, and nothing else.**

     `SetBackdrop` is deliberately cleared rather than replaced. A backdrop draws
     its edge from a texture with corners, and every corner texture in the client
     is ornamented; the whole point here is an edge that is a line. ]]--
function OB.SkinPanel(frame)
    if not frame or not frame.CreateTexture then return false end
    if frame.ecoSkinned then return true end

    if frame.SetBackdrop then frame:SetBackdrop(nil) end

    local g = colour("ground")
    frame.ecoGround = OB.SkinFill(frame, "BACKGROUND", g)
    frame.ecoGround:SetAllPoints(frame)

    --[[ Four rules rather than a backdrop edge, so the corners meet square. ]]--
    local edge = colour("goldDim")
    local sides = {
        { "TOPLEFT", "TOPRIGHT", 0, 0, nil, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 0, 0, 1, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 0, 0, 1, nil },
    }

    frame.ecoEdges = {}

    for i = 1, table.getn(sides) do
        local s = sides[i]
        local tex = OB.SkinFill(frame, "BORDER", edge)

        tex:SetPoint(s[1], frame, s[1], s[3], s[4])
        tex:SetPoint(s[2], frame, s[2], s[3], s[4])

        if s[5] then tex:SetWidth(s[5]) end
        if s[6] then tex:SetHeight(s[6]) end

        frame.ecoEdges[i] = tex
    end

    frame.ecoSkinned = true
    return true
end

--[[ **A sidebar tab.**

     Flat, and the selected one is marked by a bar down its leading edge rather
     than by a filled background. A filled row competes with the page beside it;
     a two-pixel gold edge does not, and it is the same device the client uses in
     its own quest log for the same reason.

     The highlight texture goes: `UI-QuestTitleHighlight` is a picture of a
     gradient with the quest log's proportions baked into it, and it was being
     stretched across a button a third that width. ]]--
function OB.SkinTab(button, label)
    if not button or button.ecoSkinned then return false end

    if button.SetHighlightTexture then button:SetHighlightTexture(nil) end

    button.ecoHover = OB.SkinFill(button, "BACKGROUND", colour("goldFaint"))
    button.ecoHover:SetAllPoints(button)
    button.ecoHover:Hide()

    button.ecoMark = OB.SkinFill(button, "ARTWORK", colour("gold"))
    button.ecoMark:SetWidth(2)
    button.ecoMark:SetPoint("TOPLEFT", button, "TOPLEFT", -6, -2)
    button.ecoMark:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -6, 2)
    button.ecoMark:Hide()

    if label then label:SetPoint("LEFT", button, 4, 0) end

    --[[ Hover is not selection. The two are drawn differently on purpose: one is
         where the cursor is and the other is where you are. ]]--
    button:SetScript("OnEnter", function()
        if this.ecoHover and not this.ecoSelected then this.ecoHover:Show() end
    end)

    button:SetScript("OnLeave", function()
        if this.ecoHover then this.ecoHover:Hide() end
    end)

    button.ecoSkinned = true
    return true
end

function OB.SkinTabState(button, label, selected)
    if not button then return false end

    button.ecoSelected = selected and true or false

    if button.ecoMark then
        if selected then button.ecoMark:Show() else button.ecoMark:Hide() end
    end

    if button.ecoHover and selected then button.ecoHover:Hide() end

    if label then
        local c = selected and colour("gold") or colour("textDim")
        label:SetTextColor(c[1], c[2], c[3])
    end

    return true
end

--[[ **A button that says it is a button without pretending to be metal.**

     `UIPanelButtonTemplate` is nine textures of moulded bronze. This is a
     rectangle a shade lighter than the page with a gold hairline round it, which
     is legible at any size and does not go blurry when the panel is scaled. ]]--
function OB.SkinButton(button)
    if not button or button.ecoSkinned then return false end

    --[[ The template's own art has to go first, and it is spread across several
         named regions rather than one backdrop. Anything left behind draws
         underneath and shows at the corners. ]]--
    for _, part in ipairs({ "SetNormalTexture", "SetPushedTexture",
                            "SetHighlightTexture", "SetDisabledTexture" }) do
        if button[part] then button[part](button, nil) end
    end

    if button.SetBackdrop then button:SetBackdrop(nil) end

    button.ecoFace = OB.SkinFill(button, "BACKGROUND", colour("raised"))
    button.ecoFace:SetAllPoints(button)

    button.ecoEdges = {}

    local edge = colour("goldDim")
    local sides = {
        { "TOPLEFT", "TOPRIGHT", nil, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }

    for i = 1, table.getn(sides) do
        local s = sides[i]
        local tex = OB.SkinFill(button, "BORDER", edge)

        tex:SetPoint(s[1], button, s[1], 0, 0)
        tex:SetPoint(s[2], button, s[2], 0, 0)

        if s[3] then tex:SetWidth(s[3]) end
        if s[4] then tex:SetHeight(s[4]) end

        button.ecoEdges[i] = tex
    end

    local text = button.GetFontString and button:GetFontString()
    if text then
        local c = colour("text")
        text:SetTextColor(c[1], c[2], c[3])
    end

    --[[ Brightening the edge rather than the face. A face that lights up reads
         as "pressed"; an edge that lights up reads as "reachable". ]]--
    button:SetScript("OnEnter", function()
        local hot = OB.skin.gold
        for i = 1, table.getn(this.ecoEdges or {}) do
            this.ecoEdges[i]:SetVertexColor(hot[1], hot[2], hot[3], 1)
        end
    end)

    button:SetScript("OnLeave", function()
        local cold = OB.skin.goldDim
        for i = 1, table.getn(this.ecoEdges or {}) do
            this.ecoEdges[i]:SetVertexColor(cold[1], cold[2], cold[3], 1)
        end
    end)

    button.ecoSkinned = true
    return true
end

--[[ **One call for a window, because there were ten call sites and ten
     opinions.**

     Every window this addon owns was setting its own backdrop, its own fill
     colour and its own border colour -- the same three lines, with a slightly
     different grey each time. That is why the settings panel could be reskinned
     and the item database still looked like a tooltip: nothing shared a
     definition, only a habit.

     `alpha` is the one thing worth varying. A list you read through wants to be
     opaque; a menu that appears over the game for a moment does not. ]]--
function OB.SkinWindow(frame, alpha)
    if not frame or not frame.SetBackdrop then return false end

    frame:SetBackdrop(OB.backdrop)

    local g = OB.skin.ground
    frame:SetBackdropColor(g[1], g[2], g[3], alpha or g[4] or 0.94)

    local e = OB.skin.goldDim
    frame:SetBackdropBorderColor(e[1], e[2], e[3], 1)

    return true
end
