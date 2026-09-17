--[[ Equadis' Classic Overhaul :: item database browser

  One window, two entry paths:

    * Open Item Database -> search any item by partial name or exact item ID.
    * Ctrl+Alt over a unit -> open that unit's complete, unfiltered drop pool.

  Selecting an item shows every known source from bundled Atlas-CFM, bundled
  AtlasLoot and pfQuest. Tooltip-only world-drop/rarity filters are deliberately
  never applied here.
]]--

local OB = EquadisClassicOverhaul
local M = OB.modules.itemdatabase
if not M then return end

local ROW_H = 22
local ROWS = 16
local WIDTH = 790
local LEFT_X = 12
local LEFT_W = 372
local RIGHT_X = 407
local RIGHT_W = 355

--[[ The lists start below the filter row, which is a row taller than the window
     used to be. Everything below the search box hangs off these two so the
     block moves as one. ]]--
local FILTER_TOP = -64
local LIST_TOP = -122

--[[ How far the scroll frames stop short of the bottom edge, leaving room for
     the footer line. ]]--
local FOOTER_INSET = 42

-- A little air under the last row, so it does not sit on the footer.
local LIST_SLACK = 10

--[[ **The window's height is derived, not chosen.**

     It was a constant, and adding the filter row broke it: `LIST_TOP` moved down
     twenty-six pixels to make space and the height stayed at five hundred, so
     sixteen rows now ended lower than the scroll frame they live in. The list
     ran into the footer and the scrollbar disagreed with the rows about where
     the bottom was -- which is what "it does not expand properly" looks like.

     Written as the sum of its parts so the next thing added to the top of the
     window takes the height with it. The one number that must not be hardcoded
     is the one that is the total of the others. ]]--
local HEIGHT = -LIST_TOP + (ROWS * ROW_H) + LIST_SLACK + FOOTER_INSET

--[[ **The rarities, in the client's own order, each one its own answer.**

     These used to be floors -- Common+, Uncommon+, Rare+ -- on the reasoning
     that "show me blues" usually means "blues and better". It does not hold.
     The question people actually bring to a loot table is "what epics and
     legendaries drop here", and a floor cannot say that: picking Epic+ to get
     the two of them is fine, but picking blues *and* purples while leaving out
     greens has no floor that expresses it. Every floor is a range starting at
     the bottom, and the useful selections are not.

     So each rarity is a checkbox and any combination is sayable. Nothing
     checked means no opinion, which is what "Any rarity" sets -- it is not a
     seventh state, it is the empty one, which is why ticking it clears the
     rest and why ticking anything else clears it. ]]--
local QUALITY_CHOICES = {
    { label = "Poor", quality = 0 },
    { label = "Common", quality = 1 },
    { label = "Uncommon", quality = 2 },
    { label = "Rare", quality = 3 },
    { label = "Epic", quality = 4 },
    { label = "Legendary", quality = 5 },
}

local QUALITY_ROW_H = 16

-- How many subtype rows the flyout builds. The longest 1.12 category is Weapon
-- at sixteen, so the panel never has to grow when it is re-filled.
local SUBTYPE_ROWS = 16

--[[ The client's checkbox art, named once. Three picker panels use it and a
     path typed four times each is four chances to typo one into an invisible
     tick. ]]--
local CHECK_UP = "Interface\\Buttons\\UI-CheckBox-Up"
local CHECK_DOWN = "Interface\\Buttons\\UI-CheckBox-Down"
local CHECK_HIGHLIGHT = "Interface\\Buttons\\UI-CheckBox-Highlight"
local CHECK_TICK = "Interface\\Buttons\\UI-CheckBox-Check"

--[[ **There is no drop-rate filter any more.**

     It offered floors -- 1%+, 5%+, 25%+ -- over numbers that are a survey
     rather than a measurement, gathered by different databases with different
     sample sizes and then merged. Filtering on them suggests a precision the
     data does not have, and the honest form of the question is already answered
     on each source row, where the drop rate sits as one fact among several
     rather than as the thing deciding what you are allowed to see.

     `minChance` is still honoured by `SourcesMatchFilter` for any caller that
     wants it. Nothing on screen sends it. ]]--

--[[ What the source is, rather than which one. Atlas-CFM records this per
     location and it is the difference between "drops in here" and "is sold in
     here", which are not the same errand. ]]--
local SOURCE_TYPE_CHOICES = {
    { label = "Any source", value = nil },
    { label = "Boss drops", value = "boss" },
    { label = "Quest rewards", value = "quest" },
    { label = "Crafted", value = "craft" },
    { label = "Vendor", value = "vendor" },
}

local function qualityName(quality)
    if quality == 0 then return "Poor" end
    if quality == 1 then return "Common" end
    if quality == 2 then return "Uncommon" end
    if quality == 3 then return "Rare" end
    if quality == 4 then return "Epic" end
    if quality == 5 then return "Legendary" end
    return "Unknown"
end

local function qualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

local function chanceText(chance)
    chance = tonumber(chance) or 0
    if chance <= 0 then return "?" end
    return string.format("%.2f%%", chance)
end

local function itemEnter()
    local row = this
    local data = row.data
    if not data or not data.id then return end

    OB.OwnTooltip(row, "ANCHOR_RIGHT", 8, 0)
    GameTooltip:SetHyperlink("item:" .. tostring(data.id) .. ":0:0:0")

    --[[ Said, because these are the two things everybody tries on an item and
         a row that does them silently is a row nobody knows does them. ]]--
    GameTooltip:AddLine("Shift-click to link, Ctrl-click to try on",
            0.6, 0.9, 0.6)

    GameTooltip:Show()
end

local function itemLeave()
    GameTooltip:Hide()
end

--[[ **The two things everybody tries on an item, and this list did neither.**

     Shift-click puts the link in whatever you are typing and control-click
     shows it on your character. They are not features of the bag frame or the
     loot window -- they are what an *item* does everywhere in the game, and a
     list of items that does not do them reads as a list of text that happens to
     look like items.

     The link is the client's own hyperlink rather than a name in brackets: a
     bare `[Thunderfury]` is a string, and what people want when they shift-click
     is the thing others can hover.

     **`ChatEdit_InsertLink` does not exist on 1.12.** It is a 2.0 function, and
     asking for it by name meant the guard was simply never true: shift-clicking
     a row did nothing at all, silently, which is how it was reported.

     What this client does is in its own `ContainerFrame.lua`, on every bag
     button: if the chat edit box is *visible*, insert into it. There is no
     "open it for you" -- shift-clicking with chat closed is not a request to
     start typing, and a bag item behaves the same way, so the two agree.

     The 2.0 name is still tried first for a fork that provides it. ]]--
local function itemLinkFor(id)
    local name, link = M:ItemInfo(id)
    if link then return link, name end

    --[[ Built by hand only when the client has never cached the item, which is
         the normal state for anything in this database you have not seen. Still
         a real hyperlink, so it is hoverable and clickable at the other end. ]]--
    if name then
        return "|cffffffff|Hitem:" .. tostring(id) .. ":0:0:0|h["
                .. name .. "]|h|r", name
    end

    return nil, nil
end

--[[ Into the chat box the client is already showing, which is what a bag item
     does. A method rather than a local so a test can call it without going
     through a row -- and so anything else in this window that grows a link has
     one place to put it. ]]--
function M:InsertLink(link)
    if not link then return false end

    if type(ChatEdit_InsertLink) == "function" then
        ChatEdit_InsertLink(link)
        return true
    end

    local box = getglobal("ChatFrameEditBox")
    if box and box.IsVisible and box:IsVisible() and box.Insert then
        box:Insert(link)
        return true
    end

    return false
end

local function itemClick()
    local row = this
    local data = row.data
    if not data or not data.id then return end

    local link, name = itemLinkFor(data.id)

    --[[ Shift first, because shift-clicking with the chat box already open is
         the common case and anything else here would swallow it. ]]--
    if IsShiftKeyDown and IsShiftKeyDown() then
        if link then M:InsertLink(link) end
        return
    end

    --[[ Control opens the dressing room, which on 1.12 takes the link rather
         than an id -- `DressUpItemLink` parses it back out itself. Nothing to
         show for an item the client cannot resolve, and a dressing room that
         opened empty would look broken rather than unavailable. ]]--
    if IsControlKeyDown and IsControlKeyDown() then
        if link and type(DressUpItemLink) == "function" then
            DressUpItemLink(link)
        end
        return
    end

    if arg1 == "RightButton" then
        local text = link or (name and ("[" .. name .. "]")) or tostring(data.id)
        SetItemRef("item:" .. tostring(data.id) .. ":0:0:0", text, arg1)
        return
    end

    M:SelectBrowserItem(data)
end

local function sourceEnter()
    local row = this
    local data = row.data
    local selected = M.browserSelected
    if not data or not selected or not selected.id then return end

    OB.OwnTooltip(row, "ANCHOR_LEFT", -8, 0)
    GameTooltip:SetHyperlink("item:" .. tostring(selected.id) .. ":0:0:0")
    GameTooltip:AddLine("Source: " .. tostring(data.name or "Unknown"), 0.55, 0.75, 1)
    if data.instance then GameTooltip:AddLine("Location: " .. tostring(data.instance), 0.7, 0.7, 0.7) end
    if data.provider then GameTooltip:AddLine("Database: " .. tostring(data.provider), 0.7, 0.7, 0.7) end
    local chance = tonumber(data.chance) or 0
    if chance > 0 then GameTooltip:AddLine("Drop rate: " .. chanceText(chance), 0.85, 0.85, 0.85) end

    --[[ Said, because a row that does something when clicked and looks exactly
         like one that does not is a feature nobody finds. ]]--
    if data.name and data.name ~= "" then
        GameTooltip:AddLine("Click to see everything " .. data.name .. " drops",
                0.6, 0.9, 0.6)
    end

    GameTooltip:Show()
end

--[[ **Clicking who drops it asks the obvious next question.**

     Search Shadowcraft, pick the pants, and the right-hand list says Baron
     Rivendare. The thing anybody wants next is the rest of what he drops -- and
     until now that meant reading the name, clicking the search box, and typing
     it back in by hand, which is the addon making you copy something it already
     knows.

     The name goes into the search box rather than straight into a result list,
     deliberately: the box is then showing the query that produced what you are
     looking at, so it can be edited, cleared or narrowed with a filter like any
     other search. A result list that did not match its own search box would be
     a dead end you cannot back out of.

     The main search already answers a boss name -- `SearchBySource` is merged
     into it -- so this is a click that types, not a second kind of search. ]]--
local function sourceClick()
    local row = this
    local data = row and row.data
    if not data or not data.name or data.name == "" then return end

    M:SearchFor(data.name)
end

local function sourceLeave()
    GameTooltip:Hide()
end

function M:CreateBrowserItemRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(LEFT_W - 26)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", LEFT_X + 2, LIST_TOP - ((i - 1) * ROW_H))
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnEnter", itemEnter)
    row:SetScript("OnLeave", itemLeave)
    row:SetScript("OnClick", itemClick)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(1, 1, 1, (math.floor(i / 2) * 2 == i) and 0.035 or 0.015)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(18)
    row.icon:SetHeight(18)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:Hide()

    row.name = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 24, 0)
    row.name:SetWidth(229)
    row.name:SetJustifyH("LEFT")

    row.meta = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
    row.meta:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.meta:SetWidth(88)
    row.meta:SetJustifyH("RIGHT")

    return row
end

function M:CreateBrowserSourceRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetWidth(RIGHT_W - 26)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", RIGHT_X + 2, LIST_TOP - ((i - 1) * ROW_H))
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnEnter", sourceEnter)
    row:SetScript("OnLeave", sourceLeave)
    row:SetScript("OnClick", sourceClick)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture(1, 1, 1, (math.floor(i / 2) * 2 == i) and 0.035 or 0.015)

    row.name = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.name:SetWidth(220)
    row.name:SetJustifyH("LEFT")

    row.rate = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
    row.rate:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.rate:SetWidth(92)
    row.rate:SetJustifyH("RIGHT")

    return row
end

--[[ **One dropdown, built the same way five times.**

     `UIDropDownMenu` on 1.12 is a global-state API -- the menu being built is
     whichever frame `UIDropDownMenu_Initialize` was last handed -- so each of
     these keeps its own choice list and its own callback rather than sharing a
     builder that would have to remember which one it was in the middle of. ]]--
--[[ **One dropdown, built the way this addon already knows how to build them.**

     The first version set `info.checked` and called `UIDropDownMenu_SetText`,
     and options.lua has a long comment saying why neither belongs here. Both are
     repeated verbatim because they are easy to reach for and wrong in ways that
     do not show up where you made the mistake:

     `info.checked` *shows* a tick on 1.12 and never hides one -- only
     `UIDropDownMenu_Refresh`, which `SetSelectedValue` calls, does both -- and
     the check textures are process-global, shared with every other dropdown in
     the client. So one menu lights a tick that another never clears.

     `SetText` masks the same bug rather than causing it: Refresh already sets
     the label from the matching button, so writing it by hand makes the label
     read correctly while the tick sits on the wrong row.

     And selection is applied from `Update`, not at creation. `SetSelectedValue`
     drives Refresh, which walks the client's shared menu frames -- calling it
     while no menu has ever been opened is what threw
     `UIDROPDOWNMENU_OPEN_MENU (a nil value)` five times on opening the
     browser, once per control. ]]--
function M:FilterDropdown(parent, name, width, choices, onPick)
    local drop = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    drop.choices = choices
    drop.selected = 1

    local function build()
        for i = 1, table.getn(drop.choices) do
            local info = {}
            info.text = drop.choices[i].label

            -- REQUIRED: Refresh matches button.value against selectedValue.
            -- With no value nothing is ever selected and the label never
            -- updates. See the note in options.lua.
            info.value = i

            info.func = function()
                local index = this.value or i
                drop.selected = index
                UIDropDownMenu_SetSelectedValue(drop, index)
                onPick(drop.choices[index])
            end

            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(drop, build)
    UIDropDownMenu_SetWidth(width, drop)

    --[[ Applying a selection without going through the menu, for `Pick` and for
         Reset. Guarded on the frame being visible for the same reason the
         initial call was removed: Refresh needs the client's menu frames to
         have been set up, and they are not until something is on screen. ]]--
    drop.Update = function(self)

        UIDropDownMenu_Initialize(self, build)
        UIDropDownMenu_SetSelectedValue(self, self.selected)
    end

    drop.Pick = function(index)
        drop.selected = index
        drop:Update()
        onPick(drop.choices[index])
    end

    return drop
end

--[[ The filter as the database layer wants it: absent fields mean no opinion.

     Rebuilt from the controls on every search rather than mutated as they
     change, so a control that failed to fire its callback cannot leave a stale
     narrowing in place that nothing on screen accounts for. ]]--
function M:BrowserFilter()
    local f = self.browser
    if not f then return {} end

    local filter = {}

    --[[ A set, not a floor. Left absent entirely when nothing is ticked, so
         "no opinion" stays the same shape as every other unset filter here
         rather than becoming an empty table the database layer has to know to
         treat as permissive. ]]--
    local chosen = self:QualitySelection()
    for q in pairs(chosen) do
        filter.qualities = filter.qualities or {}
        filter.qualities[q] = true
    end
    if f.sourceTypeDrop then
        local c = f.sourceTypeDrop.choices[f.sourceTypeDrop.selected]
        filter.sourceType = c and c.value
    end
    --[[ Two sets, matched as an "any of these" the way rarity is. A type and a
         subtype are different claims and are sent as different fields, so
         ticking Weapon and then Daggers under it is not a contradiction the
         database layer has to unpick -- both are satisfied by a dagger. ]]--
    local wantTypes = self:TypeSelection()
    for name in pairs(wantTypes.types) do
        filter.itemTypes = filter.itemTypes or {}
        filter.itemTypes[string.lower(name)] = true
    end
    for name in pairs(wantTypes.subTypes) do
        filter.subTypes = filter.subTypes or {}
        filter.subTypes[string.lower(name)] = true
    end
    if f.instanceChoices and f.instanceSelected then
        local c = f.instanceChoices[f.instanceSelected]
        filter.instance = c and c.value
    end
    return filter
end

--[[ True when anything at all is narrowed, which is what lets an empty search
     box still be a question worth answering. ]]--
function M:BrowserFilterActive()
    local filter = self:BrowserFilter()
    for _ in pairs(filter) do return true end
    return false
end

function M:BuildFilterRow(f)
    --[[ The dungeon list is built from the data rather than written out, so a
         bundled instance that Atlas knows about is selectable the day it lands.
         "Any dungeon" first, and "This dungeon" second so the thing somebody
         standing in one wants is the shortest reach. ]]--
    local instances = { { label = "Any dungeon", value = nil } }
    local known = self:KnownInstances()
    for i = 1, table.getn(known) do
        table.insert(instances, { label = known[i].name, value = known[i].name,
                                  key = known[i].key })
    end

    f.filterLabel = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
    f.filterLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, FILTER_TOP - 6)
    f.filterLabel:SetText("Filter")
    f.filterLabel:SetTextColor(0.6, 0.6, 0.6)

    local function rerun()
        M:RunBrowserSearch(f.search:GetText())
    end

    --[[ **The dungeon picker is a list of our own, not a dropdown.**

         There are forty-odd instances and 1.12's `UIDropDownMenu` cannot scroll:
         it lays every button out in one column, runs past its own
         `UIDROPDOWNMENU_MAXBUTTONS`, and puts the result wherever it will fit --
         which is what threw the menu far above the control with a gap under it
         while the five short menus opened normally. It was one fault, not two.

         So this one gets a scrolling panel: eight rows at a time, a scrollbar,
         and it opens directly under the button because we place it. The other
         five stay as dropdowns because five entries is what a dropdown is
         for. ]]--
    f.instanceButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.instanceButton:SetWidth(140)
    f.instanceButton:SetHeight(20)
    f.instanceButton:SetPoint("LEFT", f.filterLabel, "RIGHT", 6, 0)
    f.instanceButton:SetText(instances[1].label)
    f.instanceButton:SetScript("OnClick", function() M:ToggleInstanceList() end)

    f.instanceChoices = instances
    f.instanceSelected = 1

    --[[ A button and a panel of checkboxes rather than a dropdown, because
         rarity is the one filter here where more than one answer is normal --
         see `QUALITY_CHOICES`. The other four stay dropdowns: they are all
         "pick one of these". ]]--
    f.qualityButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.qualityButton:SetWidth(90)
    f.qualityButton:SetHeight(20)
    f.qualityButton:SetPoint("LEFT", f.instanceButton, "RIGHT", 6, 0)
    f.qualityButton:SetText("Any rarity")
    f.qualityButton:SetScript("OnClick", function() M:ToggleQualityList() end)

    f.sourceTypeDrop = self:FilterDropdown(f, "EquadisClassicOverhaulDbSourceType",
            95, SOURCE_TYPE_CHOICES, rerun)
    f.sourceTypeDrop:SetPoint("LEFT", f.qualityButton, "RIGHT", -10, -2)

    --[[ A button and a panel, like rarity, because a type has subtypes under it
         and a dropdown has nowhere to put them. ]]--
    f.typeButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.typeButton:SetWidth(100)
    f.typeButton:SetHeight(20)
    f.typeButton:SetPoint("LEFT", f.sourceTypeDrop, "RIGHT", -10, 2)
    f.typeButton:SetText("Any type")
    f.typeButton:SetScript("OnClick", function() M:ToggleTypeList() end)

    --[[ **There is no "dropped by" box any more.**

         It was a second place to type, doing something the main search box
         already does: a term is asked of the item names *and* of the things that
         drop them, and both answers come back merged. Two boxes for one question
         is two boxes to wonder about, and the one on the filter row was the
         wrong one -- filters narrow a result, and this was another way to
         produce one. ]]--

    --[[ Every control back to "no opinion" in one click. Separate from Clear,
         which empties the search term: the two are different regrets. ]]--
    f.resetFilter = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.resetFilter:SetWidth(60)
    f.resetFilter:SetHeight(20)
    f.resetFilter:SetPoint("LEFT", f.typeButton, "RIGHT", 6, 0)
    f.resetFilter:SetText("Reset")
    f.resetFilter:SetScript("OnClick", function() M:ResetBrowserFilter() end)
end

local INSTANCE_ROWS = 8
local INSTANCE_ROW_H = 16

--[[ **A scrolling list of dungeons, opened under its own button.**

     Eight rows at a time out of forty-odd, with the client's own faux scroll
     frame doing the scrolling -- the same machinery the item lists use, so it
     behaves the way the rest of the window does.

     Placed against the button rather than left to the client: this is the whole
     of the other half of the bug report. `UIDropDownMenu` decides for itself
     where a menu will fit, and a menu forty entries tall does not fit anywhere
     near its control, so it landed high on the screen with a gap under it. A
     frame we anchor ourselves opens where we say. ]]--
function M:InstanceList()
    if self.instanceList then return self.instanceList end

    local f = self.browser
    if not f then return nil end

    local list = CreateFrame("Frame", "EquadisClassicOverhaulDbInstanceList", f)
    list:SetWidth(180)
    list:SetHeight((INSTANCE_ROWS * INSTANCE_ROW_H) + 14)
    list:SetFrameStrata("DIALOG")

    -- One level above the window so the rows take the mouse rather than
    -- whatever is drawn underneath them.
    if list.SetFrameLevel and f.GetFrameLevel then
        list:SetFrameLevel(f:GetFrameLevel() + 10)
    end

    OB.SkinWindow(list, 0.98)
    list:EnableMouse(true)
    list:Hide()

    -- Directly under the button, which is where a list belonging to it goes.
    list:SetPoint("TOPLEFT", f.instanceButton, "BOTTOMLEFT", 0, -2)

    --[==[ **A slider this module drives, rather than a faux scroll frame.**

         This list has failed to scroll three times, each time with a different
         part of `FauxScrollFrame` in the way, and each fix was a guess about a
         client function nothing here can read. The parts were: a scroll frame
         whose child is one pixel tall, so `SetVerticalScroll` clamps to nothing;
         `FauxScrollFrame_Update`, which shows and hides the frame, resets the
         bar to zero and sets a value step in *pixels*; and two events -- the
         frame's `OnVerticalScroll` and the bar's `OnValueChanged` -- that fire in
         different situations on different builds.

         None of that is needed to move eight rows. So none of it is here: a
         plain `Slider` in the client's own scrollbar art, measured in **rows**
         rather than pixels, and one handler. What the list shows is
         `list.instanceOffset`, and the slider is a picture of that number which
         can also change it.

         The fourth attempt is the one that stops asking the client how far it
         has scrolled. ]==]
    list.bar = CreateFrame("Slider", "EquadisClassicOverhaulDbInstanceBar",
            list, "UIPanelScrollBarTemplate")

    list.bar:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -24)
    list.bar:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -8, 24)
    list.bar:SetMinMaxValues(0, 0)
    list.bar:SetValueStep(1)
    list.bar:SetValue(0)

    list.bar:SetScript("OnValueChanged", function()
        --[==[ **The slider is asked, and `arg1` is not read at all.**

             1.12 does not hand a slider's handler its value, and `arg1` is a
             *global* the client leaves holding whatever the last event put
             there. Reading `arg1 or this:GetValue()` therefore takes a stale
             number from some unrelated event whenever that number is not nil --
             and nought is not nil, so a drag would jump the list to the top.

             That is the last of the four links: this handler now depends on
             nothing but the slider it is on. ]==]
        M:InstanceBarMoved(this.GetValue and this:GetValue())
    end)

    --[==[ **The template's two buttons, wired here.**

         `UIPanelScrollBarTemplate` draws an up and a down button and leaves
         their behaviour to whatever owns the bar -- normally a `ScrollFrame`,
         which this deliberately no longer has. One row each, which is what the
         arrows on a list of eight mean. ]==]
    for i, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local button = getglobal("EquadisClassicOverhaulDbInstanceBar" .. suffix)

        if button and button.SetScript then
            local step = (i == 1) and -1 or 1
            button:SetScript("OnClick", function() M:ScrollInstanceList(step) end)
        end
    end

    --[[ **The wheel, which a FauxScrollFrame does not wire for you.**

         1.12's template gives you a scrollbar and nothing else -- there is no
         `OnMouseWheel` anywhere in it. Every addon that wants a wheel adds one,
         and on a popup list eight rows tall the wheel is how anybody would
         actually try to scroll it. A page at a time on shift, one row
         otherwise. ]]--
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function()
        local step = IsShiftKeyDown() and INSTANCE_ROWS or 1
        M:ScrollInstanceList(-(arg1 or 0) * step)
    end)

    --[[ **Rows stop short of the scrollbar.**

         They were 150 wide from x=8, so they ran to 158 -- and the scrollbar
         starts around 154. Siblings at the same frame level are hit in creation
         order and the rows are created after the scroll frame, so the rows were
         on top of the scrollbar and swallowed every click meant for it. The
         list could not be dragged at all, which is what "stuck at the top"
         was. ]]--
    --[==[ **And the bar itself**, because the two events are not the same one.

         `OnVerticalScroll` belongs to the scroll frame and fires when the frame
         is actually scrolled; `OnValueChanged` belongs to the slider and fires
         when the thumb moves. On a faux list the frame never really scrolls --
         its child is a pixel tall -- so the slider's event is the one that
         reliably happens when somebody drags. Listening to both costs nothing:
         they funnel into the same setter and it ignores the second. ]==]


    list.rows = {}
    for i = 1, INSTANCE_ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetWidth(140)
        row:SetHeight(INSTANCE_ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -7 - ((i - 1) * INSTANCE_ROW_H))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        --[==[ **The row passes the wheel through to the list under it.**

             The wheel was wired on the list and the list is completely covered
             by its own rows, which are Buttons and therefore take the mouse. An
             unhandled wheel event does not reliably reach the parent on 1.12, so
             the only place the wheel worked was the few pixels of margin the
             rows do not cover -- which is indistinguishable from a list that
             does not scroll, and is what this was reported as.

             The same handler rather than a shared one, because the alternative
             is a row that knows which list it belongs to. ]==]
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function()
            local step = IsShiftKeyDown() and INSTANCE_ROWS or 1
            M:ScrollInstanceList(-(arg1 or 0) * step)
        end)

        row.name = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.name:SetWidth(136)
        row.name:SetJustifyH("LEFT")

        row:SetScript("OnClick", function()
            if this.choiceIndex then M:PickInstance(this.choiceIndex) end
        end)

        list.rows[i] = row
    end

    self.instanceList = list
    return list
end

--[==[ **The choices are rebuilt, not snapshotted when the panel was made.**

     `instanceChoices` was filled once while the browser was being built, which
     is early -- and the list it comes from grows as Atlas loads. A panel built
     before that finished kept the short list for the session, and no amount of
     scrolling reaches names that are not in the array.

     Rebuilt only when the count has actually changed, so opening the picker is
     not forty table inserts every time. The selection is carried by *value*
     rather than by index, because an index into a list that just grew points at
     a different dungeon. ]==]
function M:SyncInstanceChoices(f)
    if not f then return false end

    local known = OB.modules.itemdatabase:KnownInstances()
    local want = table.getn(known) + 1

    if f.instanceChoices and table.getn(f.instanceChoices) == want then
        return false
    end

    local wasValue
    if f.instanceChoices and f.instanceSelected then
        local previous = f.instanceChoices[f.instanceSelected]
        wasValue = previous and previous.value
    end

    local choices = { { label = "Any dungeon", value = nil } }

    for i = 1, table.getn(known) do
        table.insert(choices, { label = known[i].name, value = known[i].name,
                                key = known[i].key })
    end

    f.instanceChoices = choices
    f.instanceSelected = 1

    if wasValue then
        for i = 1, table.getn(choices) do
            if choices[i].value == wasValue then f.instanceSelected = i end
        end
    end

    return true
end

--[==[ **The offset is ours, and now so is the scrollbar.**

     Three attempts, three different parts of `FauxScrollFrame` in the way.

     The first wrote the bar and read the answer back out of the faux frame,
     which is a chain with four links -- the bar's `OnValueChanged`, the frame's
     `SetVerticalScroll`, its `OnVerticalScroll`, and
     `FauxScrollFrame_OnVerticalScroll` writing `frame.offset` -- and the third
     link is dead by construction: a faux frame's scroll child is one pixel
     tall, so its scroll range is nought and a clamped `SetVerticalScroll` never
     moves anything.

     The second took the offset away from that chain and made the bar a picture
     of a number this file owns. That was right and not enough, because
     `FauxScrollFrame_Update` was still in the path: it shows and hides the
     frame, resets the bar to zero when the list fits, and sets a value step
     measured in *pixels* -- so what the bar reported and what the rows wanted
     were the same number in two units, converted by rounding.

     The third is this one, and it stops asking the client anything. There is no
     scroll frame, no faux update, and no pixels: a `Slider` whose range **is**
     the offset's range, and which the module writes and reads in rows. Every
     link in the path is now in this file.

     **The harness could not have caught either of the first two**, and its own
     comment beside the scrollbar stub says why: it fires the handler with the
     value it was given, which is the chain as this code hoped it worked rather
     than as the client implements it. That is still true -- what changed is that
     there is no longer a chain to be wrong about. ]==]
function M:InstanceOffset()
    local list = self.instanceList
    if not list then return 0 end
    return tonumber(list.instanceOffset) or 0
end

function M:InstanceMaxOffset()
    local f = self.browser
    local total = f and f.instanceChoices and table.getn(f.instanceChoices) or 0

    local maxOffset = total - INSTANCE_ROWS
    if maxOffset < 0 then maxOffset = 0 end

    return maxOffset
end

--[[ `fromBar` says the scrollbar is where this came from, so the bar is not
     written back to -- which would be a loop, and on a client that rounds
     differently to us a loop that never settles. ]]--
function M:SetInstanceOffset(offset, fromBar)
    local list = self.instanceList
    if not list then return false end

    offset = math.floor(tonumber(offset) or 0)

    local maxOffset = self:InstanceMaxOffset()
    if offset < 0 then offset = 0 end
    if offset > maxOffset then offset = maxOffset end

    list.instanceOffset = offset

    if not fromBar and list.bar and list.bar.SetValue then
        --[[ The guard, so the bar's own handler does not answer us back with
             the number we just gave it. ]]--
        list.settingBar = true
        list.bar:SetValue(offset)
        list.settingBar = nil
    end

    return true
end

--[[ Both ways the client can tell us the bar moved. The scroll frame's is what
     a faux list normally listens to; the bar's own is what fires when the thumb
     is dragged. Either is welcome and both land in the same place. ]]--
function M:InstanceBarMoved(value)
    local list = self.instanceList
    if not list or list.settingBar then return false end

    --[[ Rows, not pixels: the slider's range *is* the offset range, so there is
         no step to divide by and nothing to round differently from the client. ]]--
    self:SetInstanceOffset(tonumber(value) or 0, true)
    self:RefreshInstanceList()
    return true
end

function M:RefreshInstanceList()
    local list = self:InstanceList()
    local f = self.browser
    if not list or not f then return false end

    self:SyncInstanceChoices(f)

    local choices = f.instanceChoices or {}
    local total = table.getn(choices)

    --[[ Re-clamped here rather than only where it is set, because the list
         shrinks under the offset whenever the dungeons are rebuilt. ]]--
    local offset = self:InstanceOffset()
    local maxOffset = self:InstanceMaxOffset()

    if offset > maxOffset then
        self:SetInstanceOffset(maxOffset)
        offset = self:InstanceOffset()
    end

    --[==[ **The bar's range is the offset's range**, set here because the list
         is what changes length -- a search that narrows forty dungeons to three
         has to leave a bar that cannot be dragged rather than one that can be
         dragged to nowhere.

         Hidden outright when everything fits, which is what the faux frame did
         by hiding itself and is the one part of it worth keeping. ]==]
    if list.bar then
        list.bar:SetMinMaxValues(0, maxOffset)

        --[[ Written without waking our own handler: this is a picture of the
             offset, and the picture does not get to move it. ]]--
        list.settingBar = true
        list.bar:SetValue(offset)
        list.settingBar = nil

        if maxOffset > 0 then list.bar:Show() else list.bar:Hide() end
    end

    for i = 1, INSTANCE_ROWS do
        local row = list.rows[i]
        local index = offset + i
        local choice = choices[index]

        if choice then
            row.choiceIndex = index
            row.name:SetText(choice.label)

            -- The current pick, so the list says where you already are.
            if index == f.instanceSelected then
                row.name:SetTextColor(1, 0.82, 0)
            else
                row.name:SetTextColor(0.9, 0.9, 0.9)
            end

            row:Show()
        else
            row.choiceIndex = nil
            row:Hide()
        end
    end

    return true
end

--[[ Move the list by whole rows and re-draw.

     Driven through the scrollbar rather than by writing `scroll.offset`
     directly, because the bar is what `FauxScrollFrame_GetOffset` reads back
     and a list whose thumb disagrees with its rows is worse than one that does
     not scroll. Clamped here too: the client lets a scrollbar be set past its
     own maximum and simply shows nothing. ]]--
function M:ScrollInstanceList(rows)
    local list = self.instanceList
    if not list then return false end

    self:SetInstanceOffset(self:InstanceOffset() + (rows or 0))
    self:RefreshInstanceList()
    return true
end

function M:ToggleInstanceList()
    local list = self:InstanceList()
    if not list then return false end

    if list:IsShown() then
        list:Hide()
        return false
    end

    self:RefreshInstanceList()
    list:Show()
    return true
end

function M:PickInstance(index)
    local f = self.browser
    if not f then return false end

    local choice = f.instanceChoices and f.instanceChoices[index]
    if not choice then return false end

    f.instanceSelected = index
    f.instanceButton:SetText(choice.label)

    if self.instanceList then self.instanceList:Hide() end
    self:RunBrowserSearch(f.search:GetText())
    return true
end

-- ---------------------------------------------------------------------------
-- the rarity picker
-- ---------------------------------------------------------------------------

--[[ **Checkboxes, not a dropdown, and for a specific reason.**

     1.12's `UIDropDownMenu` can show a tick from `info.checked` but cannot
     reliably clear one: the check textures are process-global and shared
     between menus, so a menu that unticks an entry leaves the texture behind
     for the next menu that opens. A control whose whole job is showing which of
     six things are on cannot be built on that.

     A panel of real CheckButtons has none of that problem, opens where we put
     it, and is the same shape as the dungeon list next to it. ]]--
function M:QualitySelection()
    self.qualitySelected = self.qualitySelected or {}
    return self.qualitySelected
end

--[[ What the button says. Naming the one selected rarity is worth doing --
     "Epic" tells you what you asked for where "1 rarity" makes you open the
     menu to find out. Past one there is no room, so it counts. ]]--
function M:QualityLabel()
    local chosen = self:QualitySelection()
    local count, only = 0, nil

    for i = 1, table.getn(QUALITY_CHOICES) do
        local q = QUALITY_CHOICES[i].quality
        if chosen[q] then
            count = count + 1
            only = QUALITY_CHOICES[i].label
        end
    end

    if count == 0 then return "Any rarity" end
    if count == 1 then return only end
    return count .. " rarities"
end

function M:QualityList()
    if self.qualityList then return self.qualityList end

    local f = self.browser
    if not f then return nil end

    local rows = table.getn(QUALITY_CHOICES) + 1

    local list = CreateFrame("Frame", "EquadisClassicOverhaulDbQualityList", f)
    list:SetWidth(120)
    list:SetHeight((rows * QUALITY_ROW_H) + 14)
    list:SetFrameStrata("DIALOG")

    if list.SetFrameLevel and f.GetFrameLevel then
        list:SetFrameLevel(f:GetFrameLevel() + 10)
    end

    OB.SkinWindow(list, 0.98)
    list:EnableMouse(true)
    list:Hide()

    -- Directly under its own button, the same as the dungeon list.
    list:SetPoint("TOPLEFT", f.qualityButton, "BOTTOMLEFT", 0, -2)

    list.rows = {}

    --[[ "Any rarity" first and separated by nothing but its position, because it
         is not a rarity -- it is the absence of a choice, and it reads as the
         way back to that. ]]--
    for i = 1, rows do
        local row = CreateFrame("CheckButton", nil, list)
        row:SetWidth(14)
        row:SetHeight(14)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -7 - ((i - 1) * QUALITY_ROW_H))

        row:SetNormalTexture(CHECK_UP)
        row:SetPushedTexture(CHECK_DOWN)
        row:SetHighlightTexture(CHECK_HIGHLIGHT)
        row:SetCheckedTexture(CHECK_TICK)

        row.name = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "RIGHT", 4, 0)
        row.name:SetWidth(92)
        row.name:SetJustifyH("LEFT")

        if i == 1 then
            row.anyRarity = true
            row.name:SetText("Any rarity")
        else
            local choice = QUALITY_CHOICES[i - 1]
            row.quality = choice.quality
            row.name:SetText(choice.label)

            --[[ Each rarity written in its own colour, which is the fastest way
                 to read this list and matches how the results below are drawn. ]]--
            local r, g, b = qualityColor(choice.quality)
            if r then row.name:SetTextColor(r, g, b) end
        end

        row:SetScript("OnClick", function()
            M:ToggleQuality(this.anyRarity and nil or this.quality)
        end)

        list.rows[i] = row
    end

    self.qualityList = list
    return list
end

--[[ `nil` means "Any rarity", which is the empty selection rather than a
     seventh box. Ticking it clears everything; ticking anything else clears it,
     because it is cleared by there being something else ticked. ]]--
function M:ToggleQuality(quality)
    local chosen = self:QualitySelection()

    if quality == nil then
        for k in pairs(chosen) do chosen[k] = nil end
    else
        chosen[quality] = not chosen[quality] or nil
    end

    self:RefreshQualityList()

    local f = self.browser
    if f then
        f.qualityButton:SetText(self:QualityLabel())
        self:RunBrowserSearch(f.search:GetText())
    end

    return true
end

function M:RefreshQualityList()
    local list = self.qualityList
    if not list then return false end

    local chosen = self:QualitySelection()
    local any = true
    for _ in pairs(chosen) do any = false end

    for i = 1, table.getn(list.rows) do
        local row = list.rows[i]
        if row.anyRarity then
            row:SetChecked(any)
        else
            row:SetChecked(chosen[row.quality] and true or false)
        end
    end

    return true
end

function M:ToggleQualityList()
    local list = self:QualityList()
    if not list then return false end

    if list:IsShown() then
        list:Hide()
        return false
    end

    self:RefreshQualityList()
    list:Show()
    return true
end

-- ---------------------------------------------------------------------------
-- the item type picker, and its subtypes
-- ---------------------------------------------------------------------------

--[[ **The categories come from the client, not from a list written here.**

     `GetAuctionItemClasses` and `GetAuctionItemSubClasses` are the auction
     house's own categories, and they answer the *same localised strings*
     `GetItemInfo` gives for an item's type and subtype. That is what makes them
     usable as a filter rather than only as a menu: there is no numeric class id
     on 1.12, so the string is the identity, and any list of our own would be an
     English-only guess that silently matched nothing on another locale.

     The hardcoded seven-entry list this replaces was exactly that guess, and it
     carried no subtypes at all -- so "Weapon" was as fine as the filter got and
     there was no way to ask for daggers. ]]--
function M:ItemClasses()
    if self.itemClasses then return self.itemClasses end

    local out = {}
    if type(GetAuctionItemClasses) == "function" then
        local names = { GetAuctionItemClasses() }
        for i = 1, table.getn(names) do
            if type(names[i]) == "string" and names[i] ~= "" then
                table.insert(out, { label = names[i], index = i })
            end
        end
    end

    self.itemClasses = out
    return out
end

--[[ Subtypes of one category, by the *positional* index the client uses. Cached
     per class because the flyout asks every time the mouse crosses a row. ]]--
function M:ItemSubClasses(classIndex)
    classIndex = tonumber(classIndex)
    if not classIndex then return {} end

    self.itemSubClasses = self.itemSubClasses or {}
    if self.itemSubClasses[classIndex] then return self.itemSubClasses[classIndex] end

    local out = {}
    if type(GetAuctionItemSubClasses) == "function" then
        local names = { GetAuctionItemSubClasses(classIndex) }
        for i = 1, table.getn(names) do
            if type(names[i]) == "string" and names[i] ~= "" then
                table.insert(out, names[i])
            end
        end
    end

    self.itemSubClasses[classIndex] = out
    return out
end

--[[ Two sets rather than one, because a type and one of its subtypes are
     different claims: Weapon means every weapon, and Daggers means daggers
     whether or not Weapon is ticked. Kept apart so unticking a type does not
     silently drop the subtypes somebody chose under it. ]]--
function M:TypeSelection()
    self.typeSelected = self.typeSelected or { types = {}, subTypes = {} }
    return self.typeSelected
end

function M:TypeLabel()
    local chosen = self:TypeSelection()
    local count, only = 0, nil

    for name in pairs(chosen.types) do count = count + 1; only = name end
    for name in pairs(chosen.subTypes) do count = count + 1; only = name end

    if count == 0 then return "Any type" end
    if count == 1 then return only end
    return count .. " types"
end

--[[ Both nil means "Any type" -- the empty selection, the same way "Any rarity"
     works. Ticking it clears both sets. ]]--
function M:ToggleType(typeName, subTypeName)
    local chosen = self:TypeSelection()

    if typeName == nil and subTypeName == nil then
        chosen.types = {}
        chosen.subTypes = {}
    elseif subTypeName then
        chosen.subTypes[subTypeName] = not chosen.subTypes[subTypeName] or nil
    else
        chosen.types[typeName] = not chosen.types[typeName] or nil
    end

    self:RefreshTypeList()
    self:RefreshTypeSubList()

    local f = self.browser
    if f then
        if f.typeButton then f.typeButton:SetText(self:TypeLabel()) end
        self:RunBrowserSearch(f.search:GetText())
    end

    return true
end

function M:TypeList()
    if self.typeList then return self.typeList end

    local f = self.browser
    if not f then return nil end

    local classes = self:ItemClasses()
    local rows = table.getn(classes) + 1

    local list = CreateFrame("Frame", "EquadisClassicOverhaulDbTypeList", f)
    list:SetWidth(140)
    list:SetHeight((rows * QUALITY_ROW_H) + 14)
    list:SetFrameStrata("DIALOG")
    if list.SetFrameLevel and f.GetFrameLevel then
        list:SetFrameLevel(f:GetFrameLevel() + 10)
    end

    OB.SkinWindow(list, 0.98)
    list:EnableMouse(true)
    list:Hide()
    list:SetPoint("TOPLEFT", f.typeButton, "BOTTOMLEFT", 0, -2)

    list.rows = {}
    for i = 1, rows do
        local row = CreateFrame("CheckButton", nil, list)
        row:SetWidth(14)
        row:SetHeight(14)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -7 - ((i - 1) * QUALITY_ROW_H))
        row:SetNormalTexture(CHECK_UP)
        row:SetPushedTexture(CHECK_DOWN)
        row:SetHighlightTexture(CHECK_HIGHLIGHT)
        row:SetCheckedTexture(CHECK_TICK)

        row.name = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "RIGHT", 4, 0)
        row.name:SetWidth(100)
        row.name:SetJustifyH("LEFT")

        if i == 1 then
            row.anyType = true
            row.name:SetText("Any type")
        else
            local class = classes[i - 1]
            row.typeName = class.label
            row.classIndex = class.index
            row.name:SetText(class.label)

            --[[ A caret, because a row that opens something else has to look
                 different from one that does not. ]]--
            row.arrow = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
            row.arrow:SetPoint("LEFT", row.name, "RIGHT", 2, 0)
            row.arrow:SetText(">")
            row.arrow:SetTextColor(0.6, 0.6, 0.6)
        end

        --[[ **Hovering opens the subtypes, clicking ticks the type.**

             Two different things on one row, which is what was asked for: the
             flyout is a way to reach the subtypes, not a way to choose the
             type. Opening on hover rather than on click leaves the click
             meaning what it means on every other row here. ]]--
        row:SetScript("OnEnter", function()
            if this.classIndex then
                M:ShowTypeSubList(this.classIndex)
            else
                M:HideTypeSubList()
            end
        end)

        row:SetScript("OnClick", function()
            M:ToggleType(this.anyType and nil or this.typeName)
        end)

        list.rows[i] = row
    end

    self.typeList = list
    return list
end

function M:RefreshTypeList()
    local list = self.typeList
    if not list then return false end

    local chosen = self:TypeSelection()
    local any = true
    for _ in pairs(chosen.types) do any = false end
    for _ in pairs(chosen.subTypes) do any = false end

    for i = 1, table.getn(list.rows) do
        local row = list.rows[i]
        if row.anyType then
            row:SetChecked(any)
        else
            row:SetChecked(chosen.types[row.typeName] and true or false)
        end
    end

    return true
end

--[[ **The subtype flyout: one panel, re-filled per type.**

     One frame rather than one per category, because only ever one is open and
     eleven panels of up to sixteen rows is a great many frames to build for a
     menu. Sized to the longest list so re-filling never has to grow it. ]]--
function M:TypeSubList()
    if self.typeSubList then return self.typeSubList end

    local f = self.browser
    if not f then return nil end

    local list = CreateFrame("Frame", "EquadisClassicOverhaulDbSubTypeList", f)
    list:SetWidth(150)
    list:SetHeight((SUBTYPE_ROWS * QUALITY_ROW_H) + 14)
    list:SetFrameStrata("DIALOG")
    if list.SetFrameLevel and f.GetFrameLevel then
        list:SetFrameLevel(f:GetFrameLevel() + 20)
    end

    OB.SkinWindow(list, 0.98)
    list:EnableMouse(true)
    list:Hide()

    list.rows = {}
    for i = 1, SUBTYPE_ROWS do
        local row = CreateFrame("CheckButton", nil, list)
        row:SetWidth(14)
        row:SetHeight(14)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -7 - ((i - 1) * QUALITY_ROW_H))
        row:SetNormalTexture(CHECK_UP)
        row:SetPushedTexture(CHECK_DOWN)
        row:SetHighlightTexture(CHECK_HIGHLIGHT)
        row:SetCheckedTexture(CHECK_TICK)

        row.name = OB.NewText(row, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row, "RIGHT", 4, 0)
        row.name:SetWidth(120)
        row.name:SetJustifyH("LEFT")

        row:SetScript("OnClick", function()
            if this.subTypeName then M:ToggleType(nil, this.subTypeName) end
        end)

        list.rows[i] = row
    end

    self.typeSubList = list
    return list
end

--[[ Opened to the right of the panel it belongs to, which is where a submenu
     goes. ]]--
function M:ShowTypeSubList(classIndex)
    local list = self:TypeSubList()
    local parent = self.typeList
    if not list or not parent then return false end

    local subs = self:ItemSubClasses(classIndex)
    if table.getn(subs) == 0 then
        self:HideTypeSubList()
        return false
    end

    self.typeSubListClass = classIndex

    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
    list:SetHeight((table.getn(subs) * QUALITY_ROW_H) + 14)

    self:RefreshTypeSubList()
    list:Show()
    return true
end

function M:HideTypeSubList()
    if self.typeSubList then self.typeSubList:Hide() end
    self.typeSubListClass = nil
    return true
end

function M:RefreshTypeSubList()
    local list = self.typeSubList
    if not list or not self.typeSubListClass then return false end

    local subs = self:ItemSubClasses(self.typeSubListClass)
    local chosen = self:TypeSelection()

    for i = 1, SUBTYPE_ROWS do
        local row = list.rows[i]
        local name = subs[i]

        if name then
            row.subTypeName = name
            row.name:SetText(name)
            row:SetChecked(chosen.subTypes[name] and true or false)
            row:Show()
        else
            row.subTypeName = nil
            row:Hide()
        end
    end

    return true
end

function M:ToggleTypeList()
    local list = self:TypeList()
    if not list then return false end

    if list:IsShown() then
        list:Hide()
        self:HideTypeSubList()
        return false
    end

    self:RefreshTypeList()
    list:Show()
    return true
end

--[[ Every filter control's label, refreshed from its selection. Called on show
     rather than at creation -- see `FilterDropdown`. ]]--
function M:UpdateFilterDropdowns()
    local f = self.browser
    if not f then return false end

    local drops = { f.sourceTypeDrop }

    for i = 1, table.getn(drops) do
        if drops[i] then drops[i]:Update() end
    end

    -- Rarity and type are buttons rather than dropdowns, so their labels are
    -- written here rather than by `FilterDropdown`.
    if f.qualityButton then f.qualityButton:SetText(self:QualityLabel()) end
    if f.typeButton then f.typeButton:SetText(self:TypeLabel()) end

    return true
end

--[[ Put every filter control back to its first choice and re-ask. ]]--
function M:ResetBrowserFilter(quiet)
    local f = self.browser
    if not f then return false end

    local drops = { f.sourceTypeDrop }
    for i = 1, table.getn(drops) do
        local drop = drops[i]
        if drop then
            drop.selected = 1
            drop:Update()
        end
    end

    --[[ Rarity resets to nothing ticked, which is "Any rarity" -- the empty
         selection *is* the permissive one, so there is no first entry to go
         back to. ]]--
    self.qualitySelected = {}
    self:RefreshQualityList()
    if f.qualityButton then f.qualityButton:SetText(self:QualityLabel()) end
    if self.qualityList then self.qualityList:Hide() end

    -- Type the same way, both sets at once, and the flyout closed behind it.
    self.typeSelected = { types = {}, subTypes = {} }
    self:RefreshTypeList()
    if f.typeButton then f.typeButton:SetText(self:TypeLabel()) end
    if self.typeList then self.typeList:Hide() end
    self:HideTypeSubList()

    --[[ The dungeon picker is not a dropdown, so it resets on its own terms:
         back to "Any dungeon", which is always the first entry. ]]--
    if f.instanceChoices then
        f.instanceSelected = 1
        f.instanceButton:SetText(f.instanceChoices[1].label)
        if self.instanceList then self.instanceList:Hide() end
    end

    if not quiet then M:RunBrowserSearch(f.search:GetText()) end
    return true
end

function M:CreateBrowser()
    if self.browser then return self.browser end

    local f = CreateFrame("Frame", "EquadisClassicOverhaulItemDatabase", UIParent)
    f:SetWidth(WIDTH)
    f:SetHeight(HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    OB.SkinWindow(f, 0.97)
    f:Hide()

    if UISpecialFrames then table.insert(UISpecialFrames, "EquadisClassicOverhaulItemDatabase") end

    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
    f:SetScript("OnHide", function() GameTooltip:Hide() end)

    f.close = OB.IconButton(f, "close")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -5)
    f.close:SetScript("OnClick", function() f:Hide() end)

    f.title = OB.NewText(f, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
    f.title:SetText("Item Database")

    f.search = CreateFrame("EditBox", "EquadisClassicOverhaulItemDatabaseSearch", f,
            "InputBoxTemplate")
    f.search:SetWidth(440)
    f.search:SetHeight(22)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(80)
    f.search:SetScript("OnEnterPressed", function()
        M:RunBrowserSearch(this:GetText())
        this:ClearFocus()
    end)
    f.search:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    f.searchButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.searchButton:SetWidth(76)
    f.searchButton:SetHeight(22)
    f.searchButton:SetPoint("LEFT", f.search, "RIGHT", 8, 0)
    f.searchButton:SetText("Search")
    f.searchButton:SetScript("OnClick", function() M:RunBrowserSearch(f.search:GetText()) end)

    f.clearButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.clearButton:SetWidth(64)
    f.clearButton:SetHeight(22)
    f.clearButton:SetPoint("LEFT", f.searchButton, "RIGHT", 6, 0)
    f.clearButton:SetText("Clear")
    f.clearButton:SetScript("OnClick", function()
        f.search:SetText("")
        M:ShowSearchHome()
    end)

    -- Between the search row and the results, so it reads as narrowing what is
    -- below it rather than as a second thing to type into.
    self:BuildFilterRow(f)

    f.subtitle = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
    f.subtitle:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -96)
    f.subtitle:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -96)
    f.subtitle:SetJustifyH("LEFT")

    f.leftHead = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
    f.leftHead:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X + 2, -110)
    f.leftHead:SetText("Items")

    f.rightHead = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
    f.rightHead:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X + 2, -110)
    f.rightHead:SetText("Sources")

    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetTexture(1, 1, 1, 0.12)
    f.divider:SetWidth(1)
    f.divider:SetHeight(ROWS * ROW_H + 8)
    f.divider:SetPoint("TOPLEFT", f, "TOPLEFT", 394, LIST_TOP + 4)

    f.itemScroll = CreateFrame("ScrollFrame", "EquadisClassicOverhaulItemDatabaseItemScroll",
            f, "FauxScrollFrameTemplate")
    f.itemScroll:SetPoint("TOPLEFT", f, "TOPLEFT", LEFT_X, LIST_TOP)
    f.itemScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", LEFT_X + LEFT_W, FOOTER_INSET)
    f.itemScroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(ROW_H, function() M:RefreshBrowserItemRows() end)
    end)

    f.sourceScroll = CreateFrame("ScrollFrame", "EquadisClassicOverhaulItemDatabaseSourceScroll",
            f, "FauxScrollFrameTemplate")
    f.sourceScroll:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_X, LIST_TOP)
    f.sourceScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", RIGHT_X + RIGHT_W, FOOTER_INSET)
    f.sourceScroll:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(ROW_H, function() M:RefreshBrowserSourceRows() end)
    end)

    f.itemRows = {}
    f.sourceRows = {}
    for i = 1, ROWS do
        f.itemRows[i] = self:CreateBrowserItemRow(f, i)
        f.sourceRows[i] = self:CreateBrowserSourceRow(f, i)
    end

    f.footer = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
    f.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    f.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    f.footer:SetJustifyH("LEFT")
    f.footer:SetTextColor(0.6, 0.6, 0.6)

    f:SetScript("OnShow", function()
        M:StyleBrowser()

        --[[ The filter labels are written by `UIDropDownMenu_Refresh`, which
             needs the client's shared menu frames -- so it can only run once
             something is actually on screen. Doing it at creation threw
             `UIDROPDOWNMENU_OPEN_MENU (a nil value)`, once per control, before
             the window had ever been shown. ]]--
        M:UpdateFilterDropdowns()

        M:RefreshBrowser()
    end)

    self.browser = f
    return f
end

function M:StyleBrowser()
    local f = self:CreateBrowser()
    OB.ApplyFont(f.title, 15)
    OB.ApplyFont(f.subtitle, 11)
    OB.ApplyFont(f.leftHead, 10)
    OB.ApplyFont(f.rightHead, 10)
    OB.ApplyFont(f.footer, 9)
    for i = 1, ROWS do
        OB.ApplyFont(f.itemRows[i].name, 11)
        OB.ApplyFont(f.itemRows[i].meta, 10)
        OB.ApplyFont(f.sourceRows[i].name, 11)
        OB.ApplyFont(f.sourceRows[i].rate, 10)
    end
end

function M:BrowserItemMeta(row)
    if self.browserMode == "unit" then return chanceText(row.chance) end

    --[[ In a dungeon the rarity is already the colour of the name, and the
         thing worth the second column is how often it actually drops -- which is
         the number people are weighing when they decide whether to come back. ]]--
    if self.browserMode == "instance" and (tonumber(row.chance) or 0) > 0 then
        return chanceText(row.chance)
    end

    --[[ A filtered or by-enemy search carries the source that satisfied it, so
         the row can say why it is in the list rather than making the reader
         click each one to find out. ]]--
    if row.matchedSource and row.matchedSource.name and self.browserMode == "search" then
        local chance = tonumber(row.matchedSource.chance) or 0
        if chance > 0 then
            return row.matchedSource.name .. "  " .. chanceText(chance)
        end
        return row.matchedSource.name
    end

    if self:Config().showItemIds then return tostring(row.id) end
    return qualityName(row.quality)
end

function M:RefreshBrowserItemRows()
    local f = self.browser
    if not f then return end
    local rows = self.browserItems or {}
    local total = table.getn(rows)
    FauxScrollFrame_Update(f.itemScroll, total, ROWS, ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.itemScroll) or 0

    for i = 1, ROWS do
        local widget = f.itemRows[i]
        local data = rows[offset + i]

        --[[ **A boss heading, which is a row that is not an item.**

             The dungeon view interleaves them with the drops so one scroll
             reads as "who, then what" -- and every path that touches `data.id`
             below would fall over on a row that has none, so headings are drawn
             here and nothing after this runs for them. ]]--
        if data and data.header then
            widget.data = nil
            if widget.icon then widget.icon:Hide() end
            widget.name:SetText(data.name or "")
            widget.name:SetTextColor(1, 0.82, 0)
            widget.meta:SetText("")
            widget:Show()

        elseif data then
            widget.data = data
            local name, link, quality, texture = self:ItemInfo(data.id)
            data.name = name or data.name
            data.link = link or data.link
            data.texture = texture or data.texture
            if type(quality) == "number" then data.quality = quality end
            if type(data.quality) ~= "number" and self.atlasLootItems
                    and self.atlasLootItems[data.id] then
                data.quality = self.atlasLootItems[data.id].quality
            end

            local text = data.name or ("Item " .. tostring(data.id))
            widget.name:SetText(text)
            if data.texture then
                widget.icon:SetTexture(data.texture)
                widget.icon:Show()
            else
                widget.icon:Hide()
                if self.QueueItemRefresh then self:QueueItemRefresh(data.id) end
            end
            local r, g, b = qualityColor(data.quality)
            widget.name:SetTextColor(r, g, b)
            widget.meta:SetText(self:BrowserItemMeta(data))
            widget.meta:SetTextColor(r, g, b)
            widget:Show()
        else
            widget.data = nil
            if widget.icon then widget.icon:Hide() end
            widget:Hide()
        end
    end
end

function M:RefreshBrowserSourceRows()
    local f = self.browser
    if not f then return end
    local rows = self.browserSources or {}
    local total = table.getn(rows)
    FauxScrollFrame_Update(f.sourceScroll, total, ROWS, ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.sourceScroll) or 0

    for i = 1, ROWS do
        local widget = f.sourceRows[i]
        local data = rows[offset + i]
        if data then
            widget.data = data
            local text = tostring(data.name or "Unknown")
            if data.instance and tostring(data.instance) ~= "" then
                text = text .. " |cff777777- " .. tostring(data.instance) .. "|r"
            end
            widget.name:SetText(text)
            local provider = data.provider and (" |cff666666" .. tostring(data.provider) .. "|r") or ""
            widget.rate:SetText(chanceText(data.chance) .. provider)
            widget:Show()
        else
            widget.data = nil
            widget:Hide()
        end
    end
end

function M:SelectBrowserItem(item)
    if not item or not item.id then return end
    self.browserSelected = item
    self.browserSources = self:GetItemSources(item.id)

    local f = self:CreateBrowser()
    local name = item.name
    if not name then name = self:ItemInfo(item.id) end
    f.rightHead:SetText("Sources for " .. tostring(name or ("Item " .. item.id)))
    self:RefreshBrowserSourceRows()
end

function M:SortSearchResults(rows)
    local sortBy = self:Config().sortBy or "chance"
    for i = 1, table.getn(rows) do
        if sortBy == "chance" then
            local sources = self:GetItemSources(rows[i].id)
            rows[i].bestChance = sources[1] and tonumber(sources[1].chance) or 0
        end
    end

    table.sort(rows, function(a, b)
        if sortBy == "rarity" then
            local aq = tonumber(a.quality) or -1
            local bq = tonumber(b.quality) or -1
            if aq ~= bq then return aq > bq end
        else
            local ac = tonumber(a.bestChance) or 0
            local bc = tonumber(b.bestChance) or 0
            if ac ~= bc then return ac > bc end
        end
        local an = string.lower(a.name or "")
        local bn = string.lower(b.name or "")
        if an ~= bn then return an < bn end
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
end

--[[ **Put a term in the box and run it**, which is what a click that means
     "search for this" has to do -- both halves, or the box and the list start
     disagreeing about what is on screen.

     Used by the source rows and available to anything else that wants to hand
     the browser a query. The window is opened if it is not already, because a
     search nobody can see is not a search. ]]--
function M:SearchFor(text)
    if not text or text == "" then return false end

    local f = self:CreateBrowser()
    if not f or not f.search then return false end

    if not f:IsShown() then f:Show() end

    f.search:SetText(text)

    --[[ The cursor is put at the end rather than the term left selected, so the
         next keystroke narrows it instead of replacing it -- somebody who
         clicked a boss and then wants "Baron Rivendare bracers" is one word
         away, not a retype away. ]]--
    if f.search.SetCursorPosition then
        f.search:SetCursorPosition(string.len(text))
    end

    self:RunBrowserSearch(text)
    return true
end

function M:RunBrowserSearch(text)
    local f = self:CreateBrowser()
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    local filter = self:BrowserFilter()

    --[[ An empty box is only "nothing to do" when nothing is narrowed either.
         With a filter set it is a real question -- "every epic in Stratholme" --
         and answering it with the welcome screen was what made the filters feel
         like a second search term rather than a filter. ]]--
    if text == "" and not self:BrowserFilterActive() then
        return self:ShowSearchHome()
    end

    local results = self:SearchItems(text, filter)

    --[[ **A name is asked of the items and of the things that drop them, and
         both answers are kept.**

         Typing a boss's name searched item names, found nothing, and reported
         nothing to find -- the single most obvious question the browser could
         not answer.

         The first repair only tried the boss lookup when the item search came
         back empty, and that is wrong in exactly the case it matters: bosses
         lend their names to their own loot. "Rattlegore" matches the item
         *Rattlegore Blade*, so the item search succeeded, the boss lookup never
         ran, and asking about a boss returned one sword instead of everything
         they carry.

         So both, merged by id and item matches first. Somebody who meant the
         item finds it at the top; somebody who meant the boss has the rest
         underneath it. ]]--
    self.browserSourceQuery = nil

    if text ~= "" then
        local bySource = self:ApplyFilter(self:SearchBySource(text), filter)

        if table.getn(bySource) > 0 then
            local seen = {}
            for i = 1, table.getn(results) do seen[results[i].id] = true end

            local added = 0
            for i = 1, table.getn(bySource) do
                local row = bySource[i]
                if not seen[row.id] then
                    seen[row.id] = true
                    table.insert(results, row)
                    added = added + 1
                end
            end

            --[[ Only claimed when the lookup actually contributed. A term that
                 found the same rows both ways is an item search that happens to
                 agree, and saying "dropped by" about it would be a guess. ]]--
            if added > 0 then self.browserSourceQuery = text end
        end
    end

    self:SortSearchResults(results)
    self.browserMode = "search"
    self.browserItems = results
    self.browserSources = {}
    self.browserSelected = nil
    self.browserSource = nil

    f.leftHead:SetText("Search results")
    f.rightHead:SetText("Sources")

    --[[ The subtitle says what was actually asked, which is not always what was
         typed: a filter with no term, or a term that turned out to be a mob. ]]--
    local said
    if self.browserSourceQuery and text ~= "" then
        said = "Search: " .. text .. " + what it drops"
    elseif text == "" then
        said = "Filtered"
    else
        said = "Search: " .. text
    end

    local narrowed = self:DescribeBrowserFilter()
    if narrowed ~= "" then said = said .. "  (" .. narrowed .. ")" end

    f.subtitle:SetText(said .. "  -  " .. table.getn(results) .. " matching item"
            .. (table.getn(results) == 1 and "" or "s"))
    f.footer:SetText("Full database search: bundled Atlas-CFM + AtlasLoot"
            .. ((pfDB and pfDB.items) and " + pfQuest" or "")
            .. ". Right-click an item to open its item link.")

    self:RefreshBrowserItemRows()
    self:RefreshBrowserSourceRows()
    if results[1] then self:SelectBrowserItem(results[1]) end
end

--[[ What the filter row currently narrows, in words, for the subtitle. Only the
     controls that are saying something -- a line listing five "Any"s would be
     noise where the point is to notice at a glance that a filter is on. ]]--
function M:DescribeBrowserFilter()
    local f = self.browser
    if not f then return "" end

    local parts = {}

    -- Rarity first, because it is first on the row. Silent when nothing is
    -- ticked, which is the same rule the dropdowns follow for their "Any".
    local rarity = self:QualityLabel()
    if rarity ~= "Any rarity" then table.insert(parts, rarity) end

    local kind = self:TypeLabel()
    if kind ~= "Any type" then table.insert(parts, kind) end

    local drops = { f.sourceTypeDrop }

    for i = 1, table.getn(drops) do
        local drop = drops[i]
        if drop and drop.selected and drop.selected > 1 then
            table.insert(parts, drop.choices[drop.selected].label)
        end
    end

    return table.concat(parts, ", ")
end

--[[ **The loot pool of the dungeon you are standing in, by boss.**

     The question somebody in a dungeon has is "what is in here and who has it",
     and Atlas-CFM answers it against a map you click through one boss at a
     time. Here it is a list, which is the form you can read while somebody is
     pulling.

     Bosses become headers in the item column: the left list is already the
     thing being scrolled, and a second column of bosses would mean choosing one
     before seeing anything -- which is the clicking this exists to remove. ]]--
function M:ShowInstanceLoot(instanceKey, instanceName)
    local f = self:CreateBrowser()
    local groups = self:InstanceLoot(instanceKey)

    if table.getn(groups) == 0 then return false end

    local filter = self:BrowserFilter()
    local rows, shown = {}, 0

    for g = 1, table.getn(groups) do
        local group = groups[g]
        local items = self:ApplyFilter(group.items, filter)

        --[[ A boss whose every drop the filter removed is left out with them.
             An empty heading says the filter is broken rather than that the
             boss has nothing you asked for. ]]--
        if table.getn(items) > 0 then
            table.insert(rows, { header = true, name = group.boss })
            for i = 1, table.getn(items) do
                table.insert(rows, items[i])
                shown = shown + 1
            end
        end
    end

    self.browserMode = "instance"
    self.browserItems = rows
    self.browserSources = {}
    self.browserSelected = nil
    self.browserSource = nil
    self.browserSourceQuery = nil

    f.leftHead:SetText("Loot by boss")
    f.rightHead:SetText("Sources")

    local said = instanceName or "This dungeon"
    local narrowed = self:DescribeBrowserFilter()
    if narrowed ~= "" then said = said .. "  (" .. narrowed .. ")" end
    f.subtitle:SetText(said .. "  -  " .. shown .. " item" .. (shown == 1 and "" or "s")
            .. " across " .. table.getn(groups) .. " boss"
            .. (table.getn(groups) == 1 and "" or "es"))

    f.footer:SetText("You are in " .. (instanceName or "a dungeon")
            .. ". Search or change a filter to leave this view.")

    self:RefreshBrowserItemRows()
    self:RefreshBrowserSourceRows()
    return true
end

function M:ShowSearchHome()
    local f = self:CreateBrowser()

    --[[ **Standing in a dungeon is itself a question**, and the welcome screen
         was answering it with instructions. If the client can say where we are
         and Atlas knows the place, open on its loot rather than on a prompt to
         type something the player is standing inside. ]]--
    local key = self:CurrentAtlasInstanceKey()
    if key then
        local data = AtlasCFM and AtlasCFM.InstanceData and AtlasCFM.InstanceData[key]
        if self:ShowInstanceLoot(key, data and data.Name) then return end
    end

    self.browserMode = "search"
    self.browserItems = {}
    self.browserSources = {}
    self.browserSelected = nil
    self.browserSource = nil
    self.browserSourceQuery = nil

    f.leftHead:SetText("Items")
    f.rightHead:SetText("Sources")
    f.subtitle:SetText("Search by item name or ID, by the enemy that drops it, "
            .. "or set a filter and leave the box empty.")
    f.footer:SetText("The full database is never affected by tooltip filtering.")
    self:RefreshBrowserItemRows()
    self:RefreshBrowserSourceRows()
end

function M:SetBrowserSource(source)
    self.browserSource = source
    if source then self.lastBrowserSource = source end
end

function M:ShowBrowser(source, requestedName)
    local f = self:CreateBrowser()
    f:Show()

    if source then
        self.browserMode = "unit"
        self:SetBrowserSource(source)
        self.browserSelected = nil
        self.browserSources = {}
        self.browserItems = self:SortedItems(source) -- full list; no tooltip filters
        f.leftHead:SetText("Drops from " .. tostring(source.name or requestedName or "unit"))
        f.rightHead:SetText("Sources")

        local bits = { source.name or requestedName or "Unknown" }
        if source.instance then table.insert(bits, tostring(source.instance)) end
        if source.provider then table.insert(bits, tostring(source.provider)) end
        table.insert(bits, tostring(table.getn(self.browserItems)) .. " drops")
        f.subtitle:SetText(table.concat(bits, "  -  "))
        f.footer:SetText("Ctrl+Alt view: complete drop pool. Tooltip filters are not applied.")
        self:RefreshBrowserItemRows()
        self:RefreshBrowserSourceRows()
        if self.browserItems[1] then self:SelectBrowserItem(self.browserItems[1]) end
        return true
    end

    if requestedName then
        self.browserMode = "unit"
        self.browserItems = {}
        self.browserSources = {}
        self.browserSelected = nil
        f.leftHead:SetText("Drops from " .. tostring(requestedName))
        f.rightHead:SetText("Sources")

        if self.building or self.browserWaitingName == requestedName then
            f.subtitle:SetText("Building pfQuest loot index for " .. tostring(requestedName) .. "...")
            f.footer:SetText("The window will update automatically when the world-mob index is ready.")
        else
            f.subtitle:SetText("No loot pool found for " .. tostring(requestedName)
                    .. ". You can still search the full database above.")
            f.footer:SetText("Full item search remains available even when a unit has no known loot table.")
        end

        self:RefreshBrowserItemRows()
        self:RefreshBrowserSourceRows()
        return true
    end

    --[[ **Not focused on open.** Stealing the keyboard means the next thing
         typed goes into the box instead of the game -- and somebody opening the
         database in a dungeon is usually there to read it, not to type. Clicking
         the box is one click and is the player asking for it. ]]--
    self:ShowSearchHome()
    return true
end

function M:RefreshBrowser()
    local f = self.browser
    if not f or not f.IsShown or not f:IsShown() then return end

    if self.browserMode == "unit" and self.browserSource then
        self.browserItems = self:SortedItems(self.browserSource)
        self:RefreshBrowserItemRows()
        if self.browserSelected then self:SelectBrowserItem(self.browserSelected) end
    elseif self.browserMode == "search" and f.search and f.search:GetText() ~= "" then
        -- Do not rerun an expensive search for a pure style refresh. Existing
        -- results remain valid; only the rendered item info needs refreshing.
        self:RefreshBrowserItemRows()
        self:RefreshBrowserSourceRows()
    else
        self:ShowSearchHome()
    end
end
