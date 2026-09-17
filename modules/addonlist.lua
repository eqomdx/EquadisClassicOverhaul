--[[ Equadis' Classic Overhaul :: the addon list

  **1.12 has no addon list once you are in the world.** The client's own is on
  the character-select screen and nowhere else, so every UI pack ships one --
  and removing whichever addon was providing it leaves a hole where people
  expect a button.

  Built from the client's own API rather than from a list of our own:
  `GetNumAddOns`, `GetAddOnInfo`, `EnableAddOn`, `DisableAddOn`. That means it is
  right about addons this one has never heard of, which is the whole job.

  Enabling and disabling take effect on the next load, because that is when the
  client reads the list. The window says so rather than pretending otherwise.
]]--

local OB = EquadisClassicOverhaul

local ROW_H = 18
local ROWS = 18
local WIDTH = 460
local HEIGHT = 470
local LIST_TOP = -74

--[[ What the client answers for one addon, in the order 1.12 answers it:
     name, title, notes, enabled, loadable, reason, security. Titles carry
     colour escapes, so the plain name is kept for searching against. ]]--
local function addonRow(index)
    if type(GetAddOnInfo) ~= "function" then return nil end

    local name, title, notes, enabled, loadable, reason = GetAddOnInfo(index)
    if not name then return nil end

    return {
        index = index,
        name = name,
        title = title or name,
        notes = notes,
        enabled = enabled and true or false,
        loadable = loadable and true or false,
        reason = reason,
        -- By name rather than by index. 1.12 accepts either, and the name is
        -- what every other caller in the addon uses.
        loaded = type(IsAddOnLoaded) == "function" and IsAddOnLoaded(name) and true or false,
    }
end

function OB.AddOnRows()
    local out = {}
    if type(GetNumAddOns) ~= "function" then return out end

    for i = 1, GetNumAddOns() do
        local row = addonRow(i)
        if row then table.insert(out, row) end
    end

    --[[ Alphabetical by the name the client sorts on, not by the decorated
         title -- a title starting with a colour escape would sort under the
         escape rather than under its first letter. ]]--
    table.sort(out, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return out
end

--[[ The rows a search term leaves. Matched against the plain name *and* the
     title, because people remember either -- "questie" and "Questie-Octo" are
     the same addon to everybody except the sort. ]]--
function OB.FilterAddOnRows(rows, query)
    query = tostring(query or "")
    query = string.gsub(query, "^%s+", "")
    query = string.gsub(query, "%s+$", "")
    if query == "" then return rows end

    query = string.lower(query)

    local out = {}
    for i = 1, table.getn(rows) do
        local row = rows[i]
        local haystack = string.lower((row.name or "") .. " " .. (row.title or ""))
        if string.find(haystack, query, 1, true) then table.insert(out, row) end
    end

    return out
end

local function stateText(row)
    if row.loaded then return "Loaded", 0.4, 0.9, 0.4 end
    if row.enabled and row.loadable then return "On next load", 0.9, 0.82, 0.3 end
    if row.enabled then return row.reason or "Cannot load", 0.9, 0.4, 0.4 end
    return "Disabled", 0.55, 0.55, 0.55
end

function OB.CreateAddOnList()
    if OB.addonList then return OB.addonList end

    local f = CreateFrame("Frame", "EquadisClassicOverhaulAddOns", UIParent)
    f:SetWidth(WIDTH)
    f:SetHeight(HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    OB.SkinWindow(f, 0.97)
    f:Hide()

    if UISpecialFrames then
        table.insert(UISpecialFrames, "EquadisClassicOverhaulAddOns")
    end

    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)

    f.close = OB.IconButton(f, "close")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -5)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.title = OB.NewText(f, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
    f.title:SetText("AddOns")

    --[[ Not focused on open, the same rule the item database follows: stealing
         the keyboard means the next thing typed goes into the box rather than
         into the game. ]]--
    f.search = CreateFrame("EditBox", "EquadisClassicOverhaulAddOnSearch", f,
            "InputBoxTemplate")
    f.search:SetWidth(250)
    f.search:SetHeight(20)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -36)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(60)
    f.search:SetScript("OnTextChanged", function() OB.RefreshAddOnList() end)
    f.search:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    f.search:SetScript("OnEnterPressed", function() this:ClearFocus() end)

    f.reload = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.reload:SetWidth(90)
    f.reload:SetHeight(20)
    f.reload:SetPoint("LEFT", f.search, "RIGHT", 10, 0)
    f.reload:SetText("Reload UI")
    f.reload:SetScript("OnClick", function()
        if type(ReloadUI) == "function" then ReloadUI() end
    end)

    f.hint = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -60)
    f.hint:SetTextColor(0.6, 0.6, 0.6)
    f.hint:SetText("Changes take effect after a reload.")

    f.scroll = CreateFrame("ScrollFrame", "EquadisClassicOverhaulAddOnScroll", f,
            "FauxScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, LIST_TOP)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 40)
    f.scroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(ROW_H, function() OB.RefreshAddOnList() end)
    end)

    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetWidth(WIDTH - 46)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 14, LIST_TOP - ((i - 1) * ROW_H))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetWidth(18)
        row.check:SetHeight(18)
        row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.check:SetScript("OnClick", function()
            if this:GetParent().addon then
                OB.ToggleAddOn(this:GetParent().addon)
            end
        end)

        row.name = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 24, 0)
        row.name:SetWidth(250)
        row.name:SetJustifyH("LEFT")

        row.state = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
        row.state:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.state:SetWidth(120)
        row.state:SetJustifyH("RIGHT")

        f.rows[i] = row
    end

    f.footer = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
    f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
    f.footer:SetTextColor(0.6, 0.6, 0.6)

    f:SetScript("OnShow", function() OB.RefreshAddOnList() end)

    OB.addonList = f
    return f
end

--[[ Flip one addon and redraw. The client is the record, not a table of ours:
     `EnableAddOn`/`DisableAddOn` write to the same list the login screen reads,
     so a change here is the change the next load sees. ]]--
function OB.ToggleAddOn(row)
    if not row then return false end

    if row.enabled then
        if type(DisableAddOn) == "function" then DisableAddOn(row.index) end
    else
        if type(EnableAddOn) == "function" then EnableAddOn(row.index) end
    end

    OB.RefreshAddOnList()
    return true
end

function OB.RefreshAddOnList()
    local f = OB.addonList
    if not f or not f:IsShown() then return false end

    local all = OB.AddOnRows()
    local rows = OB.FilterAddOnRows(all, f.search:GetText())

    FauxScrollFrame_Update(f.scroll, table.getn(rows), ROWS, ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll) or 0

    for i = 1, ROWS do
        local widget = f.rows[i]
        local data = rows[offset + i]

        if data then
            widget.addon = data
            widget.check:SetChecked(data.enabled)
            widget.name:SetText(data.title or data.name)

            --[[ An addon that is on but cannot load is the case worth colouring:
                 it reads as working until something it needed is missing. ]]--
            local text, r, g, b = stateText(data)
            widget.state:SetText(text)
            widget.state:SetTextColor(r, g, b)

            if data.enabled then
                widget.name:SetTextColor(0.9, 0.9, 0.9)
            else
                widget.name:SetTextColor(0.5, 0.5, 0.5)
            end

            widget:Show()
        else
            widget.addon = nil
            widget:Hide()
        end
    end

    local total = table.getn(all)
    local shown = table.getn(rows)
    local on = 0
    for i = 1, total do
        if all[i].enabled then on = on + 1 end
    end

    if shown == total then
        f.footer:SetText(total .. " addons, " .. on .. " enabled")
    else
        f.footer:SetText(shown .. " of " .. total .. " addons, " .. on .. " enabled")
    end

    return true
end

function OB.ToggleAddOnList()
    local f = OB.CreateAddOnList()
    if not f then return false end

    if f:IsShown() then
        f:Hide()
        return false
    end

    f:Show()
    return true
end
