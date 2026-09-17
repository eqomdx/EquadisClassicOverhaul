--[[ Equadis' Classic Overhaul :: item database

  One loot model, two providers.

  ECO ships a compact snapshot generated from pfQuest + pfQuest-turtle for
  ordinary world NPC/object drops. Atlas-CFM knows curated instance and
  boss loot tables, including Turtle-specific additions. The tooltip and the
  full browser both ask this module for the same normalized source object, so a
  boss does not become a special case in every place loot is displayed.

  The full database NEVER applies the tooltip filters. Their settings live here
  beside the sorting policy because they describe how this database is presented
  in a short mouseover preview, but the Ctrl+Alt browser always preserves and
  shows every drop its providers report.

  The embedded reverse-loot data follows pfExtend's ShowLoots behaviour
  (TinyStick, MIT; see NOTICE), including reference-loot tables and its two
  Turtle-specific corrections. The index is built incrementally so opening the
  feature does not turn one frame into a full database inversion.
]]--

local OB = EquadisClassicOverhaul

local SORT_VALUES = { "chance", "rarity" }
local SORT_LABELS = { "Drop Rate", "Rarity" }

local LOOT_OVERRIDES = {
    { unit = 10184, item = 30017, chance = 2.5 },
    { unit = 60748, item = 30018, chance = 2.5 },
}

local M = OB.RegisterModule({
    id = "itemdatabase",
    name = "Item Database",
    feature = true,
    renders = "none",
    defaultEnabled = true,

    defaults = {
        sortBy = "chance",
        showItemIds = false,

        -- Legacy keys are retained so existing SavedVariables remain harmless.
        -- Tooltip now owns both minimum rarity and Hide World Drops presentation.
        minimumDropQuality = 0, -- legacy; Tooltip owns Minimum Rarity now
        filterWorldDrops = false, -- legacy; Tooltip owns Hide World Drops now
        worldDropCutoff = 1.0,
    },

    options = {
        { "Browser", "__s_database", "section", "database" },
        { "Open Item Database", "__a_open", "action",
          function() OB.modules.itemdatabase:OpenBrowser() end,
          function()
              local m = OB.modules.itemdatabase
              if m.building then return "Open Item Database (Building...)" end
              return "Open Item Database"
          end },
        { "Sort Items By", "sortBy", OB.Enum(SORT_VALUES, SORT_LABELS), 160 },
        { "Show Item IDs", "showItemIds", "boolean" },

        { "Tooltip Filtering", "__s_tooltip_filter", "section", "tooltipfilter" },
        { "World Drop Cutoff (%)", "worldDropCutoff", "slider", 0.1, 5, 0.1 },

        { "Data Sources", "__s_sources", "section", "sources" },
        { "Rebuild ECO Loot Index", "__a_rebuild", "action",
          function() OB.modules.itemdatabase:RebuildPfQuest() end,
          function()
              local m = OB.modules.itemdatabase
              if m.building then return "Building ECO Loot Index..." end
              if m.pfUnavailable then return "Embedded Loot Data Not Found" end
              return "Rebuild ECO Loot Index"
          end },
    },

    -- Ctrl+Alt belongs to the database, not to Tooltip presentation. Keeping the
    -- mouseover event here means the full browser still works when the Tooltip
    -- feature itself is disabled.
    events = { "UPDATE_MOUSEOVER_UNIT", "PLAYER_ENTERING_WORLD" },
})

function M:Config()
    return OB.profile.modules.itemdatabase
end

-- ---------------------------------------------------------------------------
-- item information
-- ---------------------------------------------------------------------------

local function clamp01(value)
    value = tonumber(value) or 0
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function hex(r, g, b)
    return string.format("%02x%02x%02x",
            math.floor(clamp01(r) * 255 + 0.5),
            math.floor(clamp01(g) * 255 + 0.5),
            math.floor(clamp01(b) * 255 + 0.5))
end

local function saneItemName(name, itemId)
    if type(name) ~= "string" or name == "" then return nil end
    local id = tostring(itemId or "")
    if name == id or name == "[" .. id .. "]" then return nil end
    if string.find(string.lower(name), "^item:%d") then return nil end
    return name
end

local function iconPath(texture)
    if type(texture) ~= "string" or texture == "" then return nil end
    if string.find(texture, "\\", 1, true) then return texture end
    return "Interface\\Icons\\" .. texture
end

-- pfQuest databases are generated from several sources and older/custom builds
-- are not perfectly consistent about numeric table keys. Normalise an ID before
-- using it as an index, and accept either the numeric or string spelling when
-- reading a foreign table.
local function normalizedId(value)
    return tonumber(value) or value
end

local function foreignById(tbl, id)
    if type(tbl) ~= "table" then return nil end
    id = normalizedId(id)
    local value = tbl[id]
    if value ~= nil then return value end
    return tbl[tostring(id)]
end

-- pfQuest-turtle keeps its patch source tables alive after merging them into the
-- core database. Normal installs therefore read only `data`, but some loader
-- orders expose the base table to another addon briefly (or leave `loc` pointing
-- at an unpatched locale table). Read an overlay exactly like patchtable.lua:
-- a Turtle row replaces the core row, and the special "_" value deletes it.
local function foreignOverlay(base, patch, id)
    local value = foreignById(patch, id)
    if value ~= nil then
        if value == "_" then return nil end
        return value
    end
    return foreignById(base, id)
end

local function pfTable(kind, key)
    return pfDB and pfDB[kind] and pfDB[kind][key] or nil
end

local function pfRefLootById(refId)
    return foreignOverlay(pfTable("refloot", "data"),
            pfTable("refloot", "data-turtle"), refId)
end

-- ECO carries a generated snapshot of the exact pfQuest + pfQuest-turtle
-- loot database used to build this release.  The packed source rows are
-- { itemId, chance, itemId, chance, ... } to keep the Lua file much smaller
-- than a second copy of pfQuest's item -> source tables.
function M:EmbeddedDB()
    local db = EquadisClassicOverhaulLootDB
    if type(db) == "table" and type(db.units) == "table" then return db end
    return nil
end

--[[ Every item the server's own database lists, by id -- see the header of
     data/octowow_items.lua for where it comes from and what it cannot reach.
     Read through here so a missing file is an ordinary answer, not an error. ]]--
function M:OctoItemDB()
    local db = EquadisClassicOverhaulItemDB
    if type(db) == "table" and type(db.names) == "table" then return db end
    return nil
end

--[==[ **"Referenced by a quest" is not "is a quest item", and the switch asks
     the second one.**

     This read pfQuest's `questItems` table, which lists **every item any quest
     mentions** -- 3436 of them, including Runecloth, Major Healing Potion,
     Major Mana Potion, Refreshing Spring Water and Dwarven Mild Cheese. So
     "Hide Quest Items" hid ordinary loot: on a Twilight Stonecaller it removed
     Runecloth at 32.7%, the single most common drop on the mob, while leaving
     a Pumpkin Bag at 0.08% in the list. Reported as the drops not being
     correct, and they were not -- the tooltip and the database window are two
     views of one list, and only the tooltip filters.

     The asymmetry is what gives it away: of one set of three greens from the
     same mob at the same 8%, the Robe is in pfQuest's table and the Mantle and
     Cowl are not. Nothing about those three differs to a player. The table is
     simply a record of which items quests happen to name.

     **The client knows the real answer.** `GetItemInfo` returns the item's
     class, and a genuine quest item is in the Quest class -- the same string the
     auction house builds its Quest category from, which is why it is taken from
     there rather than written out in English.

     **Nothing is hidden on a guess.** A class that is not Quest is an
     authoritative no. An item the client cannot answer for yet is kept, which
     is the rule this module already follows for the rarity floor one function
     along: an uncached item never disappears merely because the client has not
     got to it. Falling back to the embedded table here would put Runecloth back
     for exactly the items least likely to be cached. ]==]
function M:IsQuestItem(itemId)
    if type(GetItemInfo) ~= "function" then return false end

    itemId = tonumber(itemId) or itemId
    if not itemId then return false end

    --[[ Warmed the same way `ItemInfo` warms it, so the answer improves rather
         than staying "do not know" for the whole session. ]]--
    local _, _, _, _, class = GetItemInfo(itemId)

    if not class then
        self:PrimeItem(itemId)
        _, _, _, _, class = GetItemInfo(itemId)
    end

    if type(class) ~= "string" then return false end

    return class == M.QuestItemClass()
end

--[==[ The client's own name for the Quest class, taken from the auction house
     category rather than written out, so this is right in every locale. The
     English fallback is for a build that ships neither global; being wrong
     there costs a filter that stops matching, not one that hides the wrong
     things. ]==]
function M.QuestItemClass()
    if type(AUCTION_CATEGORY_QUEST) == "string" then return AUCTION_CATEGORY_QUEST end
    if type(ITEM_CLASS_QUEST) == "string" then return ITEM_CLASS_QUEST end
    return "Quest"
end

function M:EmbeddedLoot(kind, sourceId)
    local db = self:EmbeddedDB()
    local rows = db and db[kind]
    sourceId = normalizedId(sourceId)
    if type(rows) ~= "table" or not sourceId then return nil end

    local packed = foreignById(rows, sourceId)
    if type(packed) ~= "table" then return nil end

    local cacheKey = kind == "objects" and "embeddedObjectLootCache" or "embeddedUnitLootCache"
    self[cacheKey] = self[cacheKey] or {}
    local cached = self[cacheKey][sourceId]
    if cached then return cached end

    local loot = {}
    local count = table.getn(packed)
    local i = 1
    while i <= count do
        local itemId = normalizedId(packed[i])
        local chance = tonumber(packed[i + 1])
        if itemId and chance and chance > 0 then loot[itemId] = chance end
        i = i + 2
    end

    if next(loot) == nil then return nil end
    self[cacheKey][sourceId] = loot
    return loot
end

function M:EmbeddedUnitIdByName(name)
    local db = self:EmbeddedDB()
    local byName = db and db.unitIdsByName
    if type(byName) ~= "table" or not name or name == "" then return nil end

    local resolved = byName[name]
    if type(resolved) == "number" then return resolved end
    if type(resolved) == "table" then
        -- Same-name NPCs are rare. Prefer the first candidate that actually has
        -- an embedded loot row; every ID in this table came from a loot source.
        for i = 1, table.getn(resolved) do
            local id = normalizedId(resolved[i])
            if id and foreignById(db.units, id) then return id end
        end
        return normalizedId(resolved[1])
    end
    return nil
end

function M:PrimeItem(itemId)
    if type(GetItemInfo) ~= "function" then return end

    local name = saneItemName(GetItemInfo(itemId), itemId)
    if name then return end

    local tip = OB.ScanTooltip and OB.ScanTooltip()
    if not tip or not tip.SetHyperlink then return end

    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    if tip.ClearLines then tip:ClearLines() end
    pcall(tip.SetHyperlink, tip, "item:" .. tostring(itemId) .. ":0:0:0")
    if tip.Hide then tip:Hide() end
end

function M:AtlasNameForItem(itemId)
    if not AtlasCFM or not AtlasCFM.DataIndex or type(AtlasCFM.DataIndex.NameToID) ~= "table" then
        return nil
    end

    local names = AtlasCFM.DataIndex.NameToID
    if self.atlasNameCacheSource ~= names then
        self.atlasNameById = {}
        for name, id in pairs(names) do
            id = tonumber(id)
            if id and saneItemName(name, id) and not self.atlasNameById[id] then
                self.atlasNameById[id] = name
            end
        end
        self.atlasNameCacheSource = names
    end

    return self.atlasNameById and self.atlasNameById[tonumber(itemId)] or nil
end

function M:ScanItemName(itemId)
    local tip = OB.ScanTooltip and OB.ScanTooltip()
    if not tip or not tip.SetHyperlink then return nil end

    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    if tip.ClearLines then tip:ClearLines() end
    local ok = pcall(tip.SetHyperlink, tip, "item:" .. tostring(itemId) .. ":0:0:0")
    local line = ok and getglobal("EquadisClassicOverhaulScanTooltipTextLeft1") or nil
    local name = line and line.GetText and line:GetText() or nil
    if tip.Hide then tip:Hide() end
    return saneItemName(name, itemId)
end

function M:ItemInfo(itemId)
    itemId = tonumber(itemId) or itemId
    self.itemInfo = self.itemInfo or {}
    local cached = self.itemInfo[itemId]

    local name, rawLink, quality, texture
    if type(GetItemInfo) == "function" then
        local n, l, q, _, _, _, _, _, tex = GetItemInfo(itemId)
        name, rawLink, quality, texture = saneItemName(n, itemId), l, q, tex
    end

    if not name then
        self:PrimeItem(itemId)
        if type(GetItemInfo) == "function" then
            local n, l, q, _, _, _, _, _, tex = GetItemInfo(itemId)
            name = saneItemName(n, itemId)
            rawLink = l or rawLink
            quality = q or quality
            texture = tex or texture
        end
    end

    -- Keep names already learned from database search. This is important on the
    -- 1.12/Turtle client where uncached GetItemInfo can temporarily return a raw
    -- "item:3860:0:0:0" token instead of "Mithril Bar".
    if not name and self.knownItemNames then name = self.knownItemNames[itemId] end
    local embedded = self:EmbeddedDB()
    if not name and embedded and type(embedded.itemNames) == "table" then
        name = saneItemName(foreignById(embedded.itemNames, itemId), itemId)
    end
    if not name and pfDB and pfDB["items"] and pfDB["items"]["loc"] then
        name = saneItemName(foreignById(pfDB["items"]["loc"], itemId), itemId)
    end
    if not name and self.atlasLootItems and self.atlasLootItems[itemId] then
        name = saneItemName(self.atlasLootItems[itemId].name, itemId)
    end
    if not name then name = self:AtlasNameForItem(itemId) end
    if not name then name = self:ScanItemName(itemId) end

    if cached then
        if not name then name = saneItemName(cached.name, itemId) end
        if type(quality) ~= "number" then quality = cached.quality end
        if not texture then texture = cached.texture end
    end

    if self.atlasLootItems and self.atlasLootItems[itemId] then
        local atlasItem = self.atlasLootItems[itemId]
        if type(quality) ~= "number" then quality = atlasItem.quality end
        if not texture then texture = atlasItem.texture end
    end

    -- Rebuild the visible hyperlink from the resolved name instead of trusting a
    -- raw/cache placeholder link. That prevents rows such as
    -- "item:3860:0:0:0 [3860]" when the database already knows "Mithril Bar".
    local link
    if name then
        local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        if color then
            link = "|cff" .. hex(color.r, color.g, color.b)
                    .. "|Hitem:" .. itemId .. ":0:0:0|h[" .. name .. "]|h|r"
        else
            link = "|Hitem:" .. itemId .. ":0:0:0|h[" .. name .. "]|h"
        end
    elseif type(rawLink) == "string" and string.find(rawLink, "|Hitem:", 1, true) then
        link = rawLink
    end

    texture = iconPath(texture)

    if name or link or quality or texture then
        self.itemInfo[itemId] = {
            name = name,
            link = link,
            quality = quality,
            texture = texture,
        }
    end

    return name, link, quality, texture
end


-- The 1.12 item cache is asynchronous. A database can know an item's name/ID
-- before the client has received its icon and quality. Browser rows queue a few
-- cheap retries so the icon/name fills in by itself instead of staying a question
-- mark until the window is reopened.
function M:QueueItemRefresh(itemId)
    itemId = tonumber(itemId)
    if not itemId then return end

    self.itemRefresh = self.itemRefresh or {}
    if not self.itemRefresh[itemId] then
        self.itemRefresh[itemId] = { tries = 0, nextAt = 0 }
    end

    self:PrimeItem(itemId)
    self.tickly = true
end

function M:UpdateItemRefresh(now)
    if type(self.itemRefresh) ~= "table" then return false end

    local active = false
    local changed = false
    for itemId, state in pairs(self.itemRefresh) do
        active = true
        if now >= (state.nextAt or 0) then
            state.tries = (state.tries or 0) + 1
            state.nextAt = now + 0.10

            local before = self.itemInfo and self.itemInfo[itemId]
            local beforeName = before and before.name
            local beforeTexture = before and before.texture

            local name, _, _, texture = self:ItemInfo(itemId)
            if name and not beforeName then changed = true end
            if texture and texture ~= beforeTexture then changed = true end

            if texture or state.tries >= 12 then
                self.itemRefresh[itemId] = nil
            else
                self:PrimeItem(itemId)
            end
        end
    end

    if changed and self.browser and self.browser.IsShown and self.browser:IsShown() then
        self.browserRefreshPending = true
        self.browserRefreshAt = now + 0.01
    end

    if next(self.itemRefresh) == nil then self.itemRefresh = nil end
    return active
end

-- ---------------------------------------------------------------------------
-- pfQuest reverse index
-- ---------------------------------------------------------------------------

function M:AddPfDrop(unitId, itemId, chance)
    unitId = tonumber(unitId) or unitId
    itemId = tonumber(itemId) or itemId
    chance = tonumber(chance)

    if not unitId or not itemId or not chance or chance <= 0 then return end

    self.unitLoot[unitId] = self.unitLoot[unitId] or {}

    local old = self.unitLoot[unitId][itemId]
    if old and old >= chance then return end

    -- Count a source only the first time this item is attached to this unit.
    if not old then
        self.itemSourceCount[itemId] = (self.itemSourceCount[itemId] or 0) + 1
    end

    self.unitLoot[unitId][itemId] = chance

    self.itemUnits = self.itemUnits or {}
    self.itemUnits[itemId] = self.itemUnits[itemId] or {}
    local previous = self.itemUnits[itemId][unitId]
    if not previous or chance > previous then self.itemUnits[itemId][unitId] = chance end
end

function M:AddPfObjectDrop(objectId, itemId, chance)
    objectId = tonumber(objectId) or objectId
    itemId = tonumber(itemId) or itemId
    chance = tonumber(chance)

    if not objectId or not itemId or not chance or chance <= 0 then return end

    self.objectLoot = self.objectLoot or {}
    self.objectLoot[objectId] = self.objectLoot[objectId] or {}

    local old = self.objectLoot[objectId][itemId]
    if old and old >= chance then return end
    self.objectLoot[objectId][itemId] = chance

    self.itemObjects = self.itemObjects or {}
    self.itemObjects[itemId] = self.itemObjects[itemId] or {}
    local previous = self.itemObjects[itemId][objectId]
    if not previous or chance > previous then self.itemObjects[itemId][objectId] = chance end
end

function M:IndexPfItem(itemId, data)
    if type(data) ~= "table" then return end

    local direct = data["U"]
    if type(direct) == "table" then
        for unitId, chance in pairs(direct) do
            self:AddPfDrop(unitId, itemId, chance)
        end
    end

    local objects = data["O"]
    if type(objects) == "table" then
        for objectId, chance in pairs(objects) do
            self:AddPfObjectDrop(objectId, itemId, chance)
        end
    end

    -- Reference-loot tables are the indirect half of pfExtend's reverse index.
    local refs = data["R"]
    if type(refs) ~= "table" then return end

    for refId, chance in pairs(refs) do
        local probability = tonumber(chance)
        local ref = pfRefLootById(refId)

        -- Match pfExtend exactly here. The value stored on a refloot U/O member
        -- is not the item's drop chance and is not a validity gate; membership in
        -- the table is sufficient. Requiring sourceChance > 0 silently removed
        -- valid Turtle reference pools, including quest/boss loot. The item's
        -- probability lives on the item -> R edge and is what ShowLoots displays.
        if probability and probability > 0 and type(ref) == "table" then
            local units = ref["U"]
            if type(units) == "table" then
                for unitId in pairs(units) do
                    self:AddPfDrop(unitId, itemId, probability)
                end
            end

            local objects = ref["O"]
            if type(objects) == "table" then
                for objectId in pairs(objects) do
                    self:AddPfObjectDrop(objectId, itemId, probability)
                end
            end
        end
    end
end

function M:BeginPfQuestIndex()
    if self.pfReady or self.building then return true end

    local embedded = self:EmbeddedDB()
    if embedded then
        self.unitLoot = {}
        self.objectLoot = {}
        self.itemSourceCount = {}
        self.itemUnits = {}
        self.itemObjects = {}
        self.buildMode = "embedded_units"
        self.buildData = embedded.units
        self.buildObjectData = embedded.objects
        self.buildKey = nil
        self.building = true
        self.pfReady = nil
        self.pfUnavailable = nil
        self.tickly = true
        return true
    end

    -- Compatibility fallback for development installs that intentionally omit
    -- the embedded snapshot but still have pfQuest loaded.
    local items = pfDB and pfDB["items"] and pfDB["items"]["data"]
    if type(items) ~= "table" then
        self.pfUnavailable = true
        self.building = nil
        return false
    end

    self.unitLoot = {}
    self.objectLoot = {}
    self.itemSourceCount = {}
    self.itemUnits = {}
    self.itemObjects = {}
    self.buildMode = "pfquest"
    self.buildData = items
    self.buildKey = nil
    self.building = true
    self.pfReady = nil
    self.pfUnavailable = nil
    self.tickly = true

    return true
end

function M:FinishPfQuestIndex()
    for i = 1, table.getn(LOOT_OVERRIDES) do
        local row = LOOT_OVERRIDES[i]
        self:AddPfDrop(row.unit, row.item, row.chance)
    end

    self.buildData = nil
    self.buildObjectData = nil
    self.buildMode = nil
    self.buildKey = nil
    self.building = nil
    self.pfReady = true
    -- Direct scans are only a bridge while/around the reverse-index build. The
    -- completed index is authoritative; clear one-off hit/miss caches so a
    -- later verification reads the final post-patch pfDB state.
    self.pfDirectCache = nil

    if type(OB.RefreshPanel) == "function" then OB.RefreshPanel() end

    -- If the browser was opened on a normal mob before the reverse index had
    -- finished, resolve that mob now rather than leaving the window permanently
    -- on the "building" message. Keep the request as a name, not a half-built
    -- source object: the source must be created from the completed index.
    if self.browserWaitingName then
        local wanted = self.browserWaitingName
        self.browserWaitingName = nil
        local source = self:GetSourceByName(wanted)
        if source and self.SetBrowserSource then self:SetBrowserSource(source) end
        if self.browser and self.browser.IsShown and self.browser:IsShown()
                and self.RefreshBrowser then
            self:RefreshBrowser()
        end
    end

    if not self.browserRefreshPending and not self.watchShortcut then
        self.tickly = false
    end
end

function M:BuildPfQuestChunk(limit)
    if not self.building or not self.buildData then return false end

    -- The embedded database is already source -> items. Build only the reverse
    -- item indexes in small slices; tooltip/browser source lookup is available
    -- immediately through EmbeddedLoot even while this background pass runs.
    if self.buildMode == "embedded_units" or self.buildMode == "embedded_objects" then
        local done = 0
        local cap = math.min(limit or 40, 40)
        while done < cap do
            local sourceId, packed = next(self.buildData, self.buildKey)
            if not sourceId then
                if self.buildMode == "embedded_units" and type(self.buildObjectData) == "table" then
                    self.buildMode = "embedded_objects"
                    self.buildData = self.buildObjectData
                    self.buildObjectData = nil
                    self.buildKey = nil
                    return false
                end
                self:FinishPfQuestIndex()
                return true
            end

            self.buildKey = sourceId
            if type(packed) == "table" then
                local count = table.getn(packed)
                local i = 1
                while i <= count do
                    local itemId = packed[i]
                    local chance = packed[i + 1]
                    if self.buildMode == "embedded_objects" then
                        self:AddPfObjectDrop(sourceId, itemId, chance)
                    else
                        self:AddPfDrop(sourceId, itemId, chance)
                    end
                    i = i + 2
                end
            end
            done = done + 1
        end
        return false
    end

    local done = 0
    while done < (limit or 200) do
        local itemId, data = next(self.buildData, self.buildKey)
        if not itemId then
            self:FinishPfQuestIndex()
            return true
        end

        self.buildKey = itemId
        self:IndexPfItem(itemId, data)
        done = done + 1
    end

    return false
end

function M:RebuildPfQuest()
    -- A visible pfQuest source points into the old reverse index. Remember only
    -- its name, throw the stale source away, and resolve it again when the new
    -- index is complete.
    if self.browserSource and (self.browserSource.provider == "pfQuest"
            or self.browserSource.provider == "ECO Loot DB"
            or self.browserSource.usesPfQuest or self.browserSource.usesEmbeddedLoot) then
        self.browserWaitingName = self.browserSource.name
        self.browserSource = nil
    end

    self.unitLoot = nil
    self.objectLoot = nil
    self.itemSourceCount = nil
    self.itemUnits = nil
    self.itemObjects = nil
    self.buildData = nil
    self.buildObjectData = nil
    self.buildMode = nil
    self.buildKey = nil
    self.building = nil
    self.pfReady = nil
    self.pfUnavailable = nil
    self.pfSourceCache = nil
    self.pfDirectCache = nil
    self.embeddedUnitLootCache = nil
    self.embeddedObjectLootCache = nil
    self.mergedSourceCache = nil
    self.curatedSourceCache = nil

    -- pfQuest-turtle patches pfDB after pfQuest itself loads. Match pfExtend's
    -- proven timing and never build the reverse loot index from the half-patched
    -- addon-load state. Once the world has been entered, a manual rebuild can
    -- safely start immediately.
    if self.worldReady or OB.worldEntered then
        self.worldReady = true
        self:BeginPfQuestIndex()
    else
        self.pfWaitingForWorld = true
    end

    if self.browser and self.browser.IsShown and self.browser:IsShown()
            and self.RefreshBrowser then
        self:RefreshBrowser()
    end
    if type(OB.RefreshPanel) == "function" then OB.RefreshPanel() end
end

-- ---------------------------------------------------------------------------
-- pfQuest unit resolution
-- ---------------------------------------------------------------------------

function M:CurrentZoneId()
    if not pfMap or type(pfMap.GetMapID) ~= "function" then return nil end
    if type(GetCurrentMapContinent) ~= "function"
            or type(GetCurrentMapZone) ~= "function" then return nil end

    return pfMap:GetMapID(GetCurrentMapContinent(), GetCurrentMapZone())
end

function M:PfUnitInZone(unitId, zoneId)
    if not zoneId then return true end

    local data = foreignOverlay(pfTable("units", "data"),
            pfTable("units", "data-turtle"), unitId)
    local coords = data and data["coords"]
    if type(coords) ~= "table" then return false end

    for _, coord in pairs(coords) do
        if type(coord) == "table" and coord[3] == zoneId then return true end
    end

    return false
end

function M:PfUnitIdByName(name)
    if not name or name == "" then return nil end

    local embeddedId = self:EmbeddedUnitIdByName(name)
    if embeddedId then return embeddedId end

    local ids = {}
    local lower = string.lower(name)

    local function addMatches(base, patch)
        if type(base) ~= "table" and type(patch) ~= "table" then return end
        local seen = {}

        local function consider(rawId)
            rawId = normalizedId(rawId)
            if seen[rawId] then return end
            seen[rawId] = true

            local unitName = foreignOverlay(base, patch, rawId)
            if unitName == name
                    or (type(unitName) == "string" and string.lower(unitName) == lower) then
                ids[rawId] = unitName
            end
        end

        if type(base) == "table" then
            for rawId in pairs(base) do consider(rawId) end
        end
        if type(patch) == "table" then
            for rawId in pairs(patch) do consider(rawId) end
        end
    end

    -- First ask pfQuest itself. This is the normal and cheapest path.
    if pfDatabase and type(pfDatabase.GetIDByName) == "function" then
        local resolved = pfDatabase:GetIDByName(name, "units")
        if type(resolved) == "table" then
            for rawId, unitName in pairs(resolved) do ids[rawId] = unitName end
        end
    end

    -- The installed pfQuest 7.x data always retains its concrete locale tables.
    -- If `loc` was not initialised yet (or another addon changed it), resolve the
    -- same NPC directly from the current locale and finally enUS. Turtle patch
    -- rows are applied as an overlay instead of being blindly unioned with base.
    if next(ids) == nil and pfDB and pfDB["units"] then
        local units = pfDB["units"]
        local locale = type(GetLocale) == "function" and GetLocale() or "enUS"

        addMatches(units["loc"], nil)
        if next(ids) == nil then
            addMatches(units[locale], units[locale .. "-turtle"])
        end
        if next(ids) == nil and locale ~= "enUS" then
            addMatches(units["enUS"], units["enUS-turtle"])
        end
    end

    if next(ids) == nil then return nil end

    local zone = self:CurrentZoneId()
    local fallback
    local candidates = {}

    for rawUnitId in pairs(ids) do
        local unitId = normalizedId(rawUnitId)
        if not fallback then fallback = unitId end
        table.insert(candidates, unitId)
        if zone and self:PfUnitInZone(unitId, zone) then return unitId end
    end

    -- A map addon can leave the world map pointed at another zone. Prefer a
    -- same-name candidate for which either the completed reverse index or the
    -- raw pfQuest database can prove loot exists, then use the first exact name.
    if self.pfReady and self.unitLoot then
        for i = 1, table.getn(candidates) do
            if type(foreignById(self.unitLoot, candidates[i])) == "table" then
                return candidates[i]
            end
        end
    end

    for i = 1, table.getn(candidates) do
        if self:DirectPfLoot(candidates[i]) then return candidates[i] end
    end

    return fallback
end

-- A direct single-unit scan is the safety net for the live tooltip. pfExtend
-- reverses the entire pfDB synchronously before it ever displays loot; ECO does
-- that work in background slices to avoid a login hitch. If a mouseover arrives
-- before the reverse index is complete -- or a foreign addon mutates pfDB after
-- it was built -- this scan asks the raw item database the same question
-- pfExtend does and caches the answer for this unit.
function M:DirectPfLoot(unitId)
    unitId = normalizedId(unitId)
    if not unitId then return nil end

    local embedded = self:EmbeddedLoot("units", unitId)
    if embedded then return embedded end

    self.pfDirectCache = self.pfDirectCache or {}
    local cached = self.pfDirectCache[unitId]
    if type(cached) == "table" then return cached end

    local items = pfTable("items", "data")
    local turtleItems = pfTable("items", "data-turtle")
    if type(items) ~= "table" and type(turtleItems) ~= "table" then return nil end

    local found = {}
    local seenItems = {}

    local function add(itemId, chance)
        itemId = normalizedId(itemId)
        chance = tonumber(chance)
        if not itemId or not chance or chance <= 0 then return end
        local old = found[itemId]
        if not old or chance > old then found[itemId] = chance end
    end

    local function scanItem(itemId)
        itemId = normalizedId(itemId)
        if seenItems[itemId] then return end
        seenItems[itemId] = true

        -- Mirror pfQuest-turtle's patchtable semantics. If an item has a Turtle
        -- replacement row, that row is authoritative rather than additive.
        local data = foreignOverlay(items, turtleItems, itemId)
        if type(data) ~= "table" then return end

        local direct = data["U"]
        if type(direct) == "table" then
            local chance = foreignById(direct, unitId)
            if chance ~= nil then add(itemId, chance) end
        end

        local refs = data["R"]
        if type(refs) == "table" then
            for refId, probability in pairs(refs) do
                local chance = tonumber(probability)
                if chance and chance > 0 then
                    local ref = pfRefLootById(refId)
                    local units = ref and ref["U"]
                    if type(units) == "table" and foreignById(units, unitId) ~= nil then
                        add(itemId, chance)
                    end
                end
            end
        end
    end

    if type(items) == "table" then
        for itemId in pairs(items) do scanItem(itemId) end
    end
    if type(turtleItems) == "table" then
        for itemId in pairs(turtleItems) do scanItem(itemId) end
    end

    if next(found) == nil then
        -- Never cache a miss. pfQuest-turtle patches the live database during
        -- startup, so an early empty result must be allowed to recover later.
        return nil
    end

    self.pfDirectCache[unitId] = found
    return found
end

local function pfSourceFromLoot(self, name, unitId, loot)
    if type(loot) ~= "table" then return nil end

    local embedded = self:EmbeddedDB()
    local provider = embedded and "ECO Loot DB" or "pfQuest"
    local items = {}
    for itemId, chance in pairs(loot) do
        table.insert(items, {
            id = tonumber(itemId) or itemId,
            chance = tonumber(chance) or 0,
            provider = provider,
            sourceCount = (embedded and embedded.itemSourceCount
                    and foreignById(embedded.itemSourceCount, itemId))
                    or (self.itemSourceCount and self.itemSourceCount[itemId]) or 1,
        })
    end

    if table.getn(items) == 0 then return nil end
    return {
        key = "pfquest:" .. tostring(unitId),
        provider = provider,
        kind = "unit",
        unitId = unitId,
        name = name,
        items = items,
        usesPfQuest = not embedded and true or nil,
        usesEmbeddedLoot = embedded and true or nil,
    }
end

function M:PfSourceById(unitId, name)
    unitId = normalizedId(unitId)
    if not unitId then return nil end

    -- A completed reverse index is the fast path. Before completion, use the
    -- raw single-unit scan so the first tooltip after login still works instead
    -- of spending several seconds with no loot lines.
    if not self.pfReady then
        self:BeginPfQuestIndex()
        if not self.pfReady then
            local direct = self:DirectPfLoot(unitId)
            local source = pfSourceFromLoot(self, name or ("NPC " .. tostring(unitId)), unitId, direct)
            if source then return source, "building" end
            return nil, "building"
        end
    end

    self.pfSourceCache = self.pfSourceCache or {}
    local cached = self.pfSourceCache[unitId]
    if cached then
        cached.name = name or cached.name
        return cached
    end

    local loot = foreignById(self.unitLoot, unitId)

    -- pfExtend is the behavioural reference. If our background inversion says
    -- an NPC has no loot, verify the raw pfDB once before believing the miss.
    -- This also recovers if pfQuest-turtle patched a table after our index pass.
    if type(loot) ~= "table" then loot = self:DirectPfLoot(unitId) end
    if type(loot) ~= "table" then return nil end

    local source = pfSourceFromLoot(self, name or ("NPC " .. tostring(unitId)), unitId, loot)
    if not source then return nil end
    self.pfSourceCache[unitId] = source
    return source
end

function M:PfSource(name)
    local unitId = self:PfUnitIdByName(name)
    if not unitId then return nil end
    return self:PfSourceById(unitId, name)
end

-- ---------------------------------------------------------------------------
-- Atlas-CFM boss resolution
-- ---------------------------------------------------------------------------

local function atlasVisible(entry)
    if AtlasCFM and AtlasCFM.Server and type(AtlasCFM.Server.IsVisible) == "function" then
        return AtlasCFM.Server.IsVisible(entry)
    end
    return true
end

local function atlasServerKey()
    if AtlasCFM and AtlasCFM.Server and type(AtlasCFM.Server.GetActive) == "function" then
        return tostring(AtlasCFM.Server.GetActive())
    end
    return "default"
end

local function atlasInstanceName(key, data)
    if data and data.Name then return data.Name end
    return key
end

local function atlasLootTable(boss)
    if not boss then return nil end

    -- Atlas-CFM creates `boss.items` from `boss.loot` after applying boss-wide
    -- defaults (drop rate, description, quantity, server restrictions, etc.).
    -- Prefer that normalized list whenever it exists. Falling back to raw loot
    -- keeps ECO compatible with pages that have not run Atlas's conversion yet.
    local loot = boss.items or boss.loot
    if type(loot) == "table" then return loot end
    if type(loot) == "string" and AtlasCFMLoot_Data then return AtlasCFMLoot_Data[loot] end
    return nil
end

local function atlasPlainName(text)
    if not text then return nil end
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

-- Atlas display names sometimes append information that is not part of the
-- unit's actual name: "Spawn of Hakkar (Wanders)", "Jade (Rare)", etc. Strip
-- only trailing parenthetical annotations; the exact name is always tried first.
local function atlasBaseName(text)
    text = atlasPlainName(text)
    if not text then return nil end

    local previous
    repeat
        previous = text
        text = string.gsub(text, "%s+%b()$", "")
        text = string.gsub(text, "%s+$", "")
    until text == previous

    return text
end

local function atlasNameMatches(displayName, unitName)
    local display = atlasPlainName(displayName)
    local wanted = atlasPlainName(unitName)
    if not display or not wanted then return false end
    if display == wanted then return true end
    if atlasBaseName(display) == wanted then return true end

    -- A very small number of Atlas pages deliberately combine two bosses into
    -- one shared loot pool (for example "Sothos & Jarien"). Let either exact
    -- member open that shared pool without treating arbitrary substrings as a
    -- match.
    local marker = " & "
    local at = string.find(display, marker, 1, true)
    if at then
        local left = string.sub(display, 1, at - 1)
        local right = string.sub(display, at + string.len(marker))
        if atlasBaseName(left) == wanted or atlasBaseName(right) == wanted then
            return true
        end
    end

    return false
end

function M:CurrentAtlasInstanceKey()
    if not AtlasCFM or type(AtlasCFM.InstanceData) ~= "table" then return nil end

    local zone
    if type(GetRealZoneText) == "function" then zone = GetRealZoneText() end
    if zone and AtlasCFMZoneSubstitutions and AtlasCFMZoneSubstitutions[zone] then
        zone = AtlasCFMZoneSubstitutions[zone]
    end

    local sub
    if type(GetSubZoneText) == "function" then sub = GetSubZoneText() end
    if sub and AtlasCFM.SubZoneData and AtlasCFM.SubZoneData[sub]
            and AtlasCFM.InstanceData[AtlasCFM.SubZoneData[sub]] then
        return AtlasCFM.SubZoneData[sub]
    end

    if zone and AtlasCFM.AssocDefaults and AtlasCFM.AssocDefaults[zone]
            and AtlasCFM.InstanceData[AtlasCFM.AssocDefaults[zone]] then
        return AtlasCFM.AssocDefaults[zone]
    end

    if zone then
        for key, data in pairs(AtlasCFM.InstanceData) do
            local display = data and data.Name
            if display == zone then return key end
            if type(display) == "string" and string.len(display) >= string.len(zone)
                    and string.sub(display, string.len(display) - string.len(zone) + 1) == zone then
                return key
            end
        end
    end

    return nil
end

local function atlasIndexKey(text)
    text = atlasPlainName(text)
    if not text then return nil end
    return string.lower(text)
end

local function addAtlasCandidate(index, name, candidate)
    local key = atlasIndexKey(name)
    if not key or key == "" then return end

    index[key] = index[key] or {}
    table.insert(index[key], candidate)
end

-- Boss-name lookup is deliberately much smaller than Atlas-CFM's item index:
-- it records only {instance,boss} references and never touches item caches. A
-- normal mob must not make us walk every dungeon and raid boss on every new
-- mouseover just to discover that Atlas has no entry for it.
function M:BuildAtlasBossIndex()
    if not AtlasCFM or type(AtlasCFM.InstanceData) ~= "table" then return false end
    local server = atlasServerKey()
    if self.atlasBossIndex and self.atlasIndexedData == AtlasCFM.InstanceData
            and self.atlasIndexedServer == server then
        return true
    end

    local index = {}
    for instanceKey, instance in pairs(AtlasCFM.InstanceData) do
        if type(instance) == "table" and atlasVisible(instance)
                and type(instance.Bosses) == "table" then
            for i = 1, table.getn(instance.Bosses) do
                local boss = instance.Bosses[i]
                if boss and boss.name then
                    local candidate = {
                        boss = boss,
                        instanceKey = instanceKey,
                        instance = instance,
                    }

                    addAtlasCandidate(index, boss.name, candidate)
                    local base = atlasBaseName(boss.name)
                    if base ~= atlasPlainName(boss.name) then
                        addAtlasCandidate(index, base, candidate)
                    end

                    -- Shared pools such as "Sothos & Jarien" are one Atlas row
                    -- but two unit names in the world. Index each exact member.
                    local display = atlasPlainName(boss.name)
                    local marker = " & "
                    local at = display and string.find(display, marker, 1, true)
                    if at then
                        addAtlasCandidate(index, atlasBaseName(string.sub(display, 1, at - 1)), candidate)
                        addAtlasCandidate(index, atlasBaseName(string.sub(display,
                                at + string.len(marker))), candidate)
                    end
                end
            end
        end
    end

    self.atlasBossIndex = index
    self.atlasIndexedData = AtlasCFM.InstanceData
    self.atlasIndexedServer = server
    -- Source/miss caches are server-sensitive too. If the boss index had to be
    -- rebuilt, discard old resolved rows rather than mixing two server views.
    self.atlasSourceCache = nil
    self.mergedSourceCache = nil
    self.curatedSourceCache = nil
    return true
end

local function atlasCandidateResult(candidate, name)
    if not candidate or not candidate.boss then return nil end
    local boss = candidate.boss
    if not atlasNameMatches(boss.name, name) or not atlasVisible(boss) then return nil end

    local loot = atlasLootTable(boss)
    if type(loot) ~= "table" then return nil end

    return {
        boss = boss,
        loot = loot,
        instanceKey = candidate.instanceKey,
        instance = candidate.instance,
    }
end

function M:FindAtlasBoss(name)
    if not name or name == "" then return nil end
    if not self:BuildAtlasBossIndex() then return nil end

    local candidates = self.atlasBossIndex[atlasIndexKey(name)]
    if type(candidates) ~= "table" then return nil end

    -- Prefer the instance the player is actually standing in. Duplicate boss
    -- names then resolve deterministically instead of depending on pairs() order.
    local preferred = self:CurrentAtlasInstanceKey()
    if preferred then
        for i = 1, table.getn(candidates) do
            if candidates[i].instanceKey == preferred then
                local found = atlasCandidateResult(candidates[i], name)
                if found then return found end
            end
        end
    end

    for i = 1, table.getn(candidates) do
        if candidates[i].instanceKey ~= preferred then
            local found = atlasCandidateResult(candidates[i], name)
            if found then return found end
        end
    end

    return nil
end

local function atlasQuantityText(quantity)
    if type(quantity) == "number" then return "x" .. quantity end
    if type(quantity) == "table" then
        local low = quantity[1]
        local high = quantity[2]
        if low and high then return "x" .. low .. "-" .. high end
        if low then return "x" .. low end
    end
    return nil
end

-- Atlas-CFM has explicit global World Blues / World Epics collections. Those
-- are a much stronger signal than a percentage guess: a 0.5% item on a boss
-- can be a real boss-specific rare, while an item listed in WorldEpics is a
-- world drop regardless of the rate Atlas happens to show on one page.
function M:AtlasWorldDropSet()
    local server = atlasServerKey()
    if self.atlasWorldDropSet and self.atlasWorldDropData == AtlasCFMLoot_Data
            and self.atlasWorldDropServer == server then
        return self.atlasWorldDropSet
    end

    local set = {}
    if type(AtlasCFMLoot_Data) == "table" then
        for key, list in pairs(AtlasCFMLoot_Data) do
            if key == "WorldEpics" or string.find(tostring(key), "^WorldBlues") then
                if type(list) == "table" then
                    for i = 1, table.getn(list) do
                        local entry = list[i]
                        if type(entry) == "number" then
                            set[entry] = true
                        elseif type(entry) == "table" and atlasVisible(entry) then
                            local itemId = entry.id or (type(entry[1]) == "number" and entry[1])
                            if itemId then set[itemId] = true end
                        end
                    end
                end
            end
        end
    end

    self.atlasWorldDropSet = set
    self.atlasWorldDropData = AtlasCFMLoot_Data
    self.atlasWorldDropServer = server
    return set
end

local function atlasContainerItems(container)
    if type(container) ~= "table" then return nil end

    local out = {}
    for i = 1, table.getn(container) do
        local entry = container[i]
        if type(entry) == "number" then
            table.insert(out, entry)
        elseif type(entry) == "table" and atlasVisible(entry) then
            local itemId = entry.id or (type(entry[1]) == "number" and entry[1])
            if itemId then table.insert(out, itemId) end
        end
    end

    if table.getn(out) == 0 then return nil end
    return out
end

function M:AtlasSource(name)
    local server = atlasServerKey()
    if not self:BuildAtlasBossIndex() then return nil end

    self.atlasSourceCache = self.atlasSourceCache or {}
    local location = self:CurrentAtlasInstanceKey() or "any"
    local cacheKey = server .. ":" .. tostring(location) .. ":" .. tostring(name)

    -- Cache misses as well as hits. Ordinary mobs are the common case, and an
    -- uncached miss otherwise walks every Atlas instance/boss every frame while
    -- the pfQuest reverse index is still being built. `false` means "looked and
    -- not found"; nil still means "not checked yet".
    local cached = self.atlasSourceCache[cacheKey]
    if cached ~= nil then return cached or nil end

    local found = self:FindAtlasBoss(name)
    if not found then
        self.atlasSourceCache[cacheKey] = false
        return nil
    end

    local boss = found.boss
    local defaults = boss.defaults or {}
    local items = {}
    local worldDrops = self:AtlasWorldDropSet()

    for i = 1, table.getn(found.loot) do
        local raw = found.loot[i]
        if type(raw) == "number" then raw = { id = raw } end

        if type(raw) == "table" then
            -- `boss.items` already has these defaults. Reapplying them only when
            -- a field is absent makes the raw-loot fallback behave identically.
            local entry = {}
            for k, v in pairs(defaults) do entry[k] = v end
            for k, v in pairs(raw) do entry[k] = v end

            if atlasVisible(entry) then
                local itemId = entry.id or (type(entry[1]) == "number" and entry[1])
                if itemId then
                    table.insert(items, {
                    id = itemId,
                    chance = tonumber(entry.dropRate) or 0,
                    provider = "Atlas CFM",
                    disc = entry.disc,
                    quantity = entry.quantity,
                    quantityText = atlasQuantityText(entry.quantity),
                    container = entry.container,
                    containerItems = atlasContainerItems(entry.container),
                    -- Atlas's explicit World Blues/Epics collections beat the
                    -- percentage heuristic. Anything else stays undecided: an
                    -- Atlas-only 0.5% boss rare remains visible, while a merged
                    -- pfQuest row can still prove that the same item is a tiny
                    -- generic drop across many unrelated NPCs.
                    worldDrop = worldDrops[itemId] and true or nil,
                    })
                end
            end
        end
    end

    local source = {
        key = "atlas:" .. tostring(server) .. ":" .. tostring(found.instanceKey)
                .. ":" .. tostring(boss.id or name),
        provider = "Atlas CFM",
        kind = "boss",
        bossId = boss.id,
        name = name,
        atlasName = boss.name,
        instanceKey = found.instanceKey,
        instance = atlasInstanceName(found.instanceKey, found.instance),
        items = items,
    }
    self.atlasSourceCache[cacheKey] = source
    return source
end

-- ---------------------------------------------------------------------------
-- normalized queries and sorting
-- ---------------------------------------------------------------------------

function M:MergeSources(atlas, pf)
    if not atlas then return pf end
    if not pf then return atlas end

    self.mergedSourceCache = self.mergedSourceCache or {}
    local cacheKey = tostring(atlas.key) .. "|" .. tostring(pf.key)
    local cached = self.mergedSourceCache[cacheKey]
    if cached then return cached end

    local items, byId = {}, {}

    -- Curated database first: its chance, quantity, container and server
    -- metadata win when pfQuest reports the same item.
    local curatedProvider = atlas.provider or "Atlas CFM"
    local mergedProvider = curatedProvider .. " + pfQuest"
    for i = 1, table.getn(atlas.items or {}) do
        local row = atlas.items[i]
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        if atlas.usesAtlas or curatedProvider == "Atlas CFM" then copy.usesAtlas = true end
        if atlas.usesAtlasLoot or curatedProvider == "AtlasLoot" then copy.usesAtlasLoot = true end
        table.insert(items, copy)
        byId[copy.id] = copy
    end

    for i = 1, table.getn(pf.items or {}) do
        local row = pf.items[i]
        local existing = byId[row.id]
        if existing then
            existing.usesPfQuest = true
            existing.sourceCount = row.sourceCount or existing.sourceCount
            existing.provider = mergedProvider
            existing.pfChance = row.chance
        else
            local copy = {}
            for k, v in pairs(row) do copy[k] = v end
            copy.usesPfQuest = true
            table.insert(items, copy)
            byId[copy.id] = copy
        end
    end

    local source = {
        key = "merged:" .. cacheKey,
        provider = mergedProvider,
        kind = atlas.kind or pf.kind,
        bossId = atlas.bossId,
        unitId = pf.unitId,
        name = atlas.name or pf.name,
        atlasName = atlas.atlasName,
        instanceKey = atlas.instanceKey,
        instance = atlas.instance,
        items = items,
        usesAtlas = atlas.usesAtlas or curatedProvider == "Atlas CFM",
        usesAtlasLoot = atlas.usesAtlasLoot or curatedProvider == "AtlasLoot",
        usesPfQuest = true,
    }

    self.mergedSourceCache[cacheKey] = source
    return source
end

-- ---------------------------------------------------------------------------
-- bundled AtlasLoot provider + item-first search
-- ---------------------------------------------------------------------------

local function atlasLootPlain(text)
    if not text then return nil end
    text = tostring(text)
    text = string.gsub(text, "=q%d=", "")
    text = string.gsub(text, "=ds=", "")
    text = string.gsub(text, "=d%d=", "")
    text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = string.gsub(text, "|r", "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function atlasLootQuality(text)
    if not text then return nil end
    local _, _, q = string.find(tostring(text), "=q(%d)=")
    return q and tonumber(q) or nil
end

local function atlasLootChance(text)
    if type(text) == "number" then return text end
    if type(text) ~= "string" then return 0 end
    local _, _, n = string.find(text, "([%d%.]+)%%")
    return tonumber(n) or 0
end

local function lowerPlain(text)
    text = atlasLootPlain(text)
    if not text then return nil end
    return string.lower(text)
end

local function sourceBaseName(text)
    text = atlasLootPlain(text)
    if not text then return nil end
    local previous
    repeat
        previous = text
        text = string.gsub(text, "%s+%b()$", "")
        text = string.gsub(text, "%s+$", "")
    until text == previous
    return text
end

-- AtlasLoot commonly uses compact internal instance keys ("BlackrockDepths")
-- while Atlas-CFM stores display names ("Blackrock Depths"). They describe
-- the same location and must compare as the same source without throwing away
-- the original display text. This token is identity-only: lowercase alpha/
-- numeric characters, with spaces and punctuation ignored.
local function sourceIdentity(text)
    text = atlasLootPlain(text)
    if not text then return "" end
    text = string.lower(text)
    text = string.gsub(text, "[^%w]", "")
    return text
end

local function atlasLootInstanceName(key)
    if not key or key == "" then return nil end

    local data = AtlasCFM and AtlasCFM.InstanceData and AtlasCFM.InstanceData[key]
    if data and data.Name and data.Name ~= "" then return data.Name end

    -- AtlasLoot's instance map uses compact keys such as BlackrockDepths.
    -- Keep those keys for lookup, but never make the browser show them raw.
    local text = tostring(key)
    text = string.gsub(text, "(%l)(%u)", "%1 %2")
    text = string.gsub(text, "(%u)(%u%l)", "%1 %2")
    return text
end

function M:BuildAtlasLootIndex()
    if self.atlasLootIndexed and self.atlasLootIndexedData == AtlasLoot_Data then return true end
    if type(AtlasLoot_Data) ~= "table" then return false end

    self.atlasLootItems = {}
    self.atlasLootItemSources = {}
    self.atlasLootBossIndex = {}

    -- Map each loot table id back to an instance/page when AtlasLoot exposes it.
    local instanceByTable = {}
    local function mapButtons(buttons)
        if type(buttons) ~= "table" then return end
        for instanceKey, list in pairs(buttons) do
            if type(list) == "table" then
                for _, dataId in pairs(list) do
                    if type(dataId) == "string" and dataId ~= "" and not instanceByTable[dataId] then
                        instanceByTable[dataId] = instanceKey
                    end
                end
            end
        end
    end
    mapButtons(AtlasLootBossButtons)
    mapButtons(AtlasLootWBBossButtons)
    mapButtons(AtlasLootBattlegrounds)

    local titles = AtlasLoot_TableNames or {}

    for dataSource, sourceTables in pairs(AtlasLoot_Data) do
        if dataSource ~= "AtlasLootFallback" and type(sourceTables) == "table" then
            for dataId, rows in pairs(sourceTables) do
                if type(rows) == "table" then
                    local titleRow = titles[dataId]
                    local sourceName = titleRow and titleRow[1] or dataId
                    sourceName = atlasLootPlain(sourceName) or tostring(dataId)
                    local instanceKey = instanceByTable[dataId]
                    local instance = atlasLootInstanceName(instanceKey)
                    local sourceItems = {}

                    for i = 1, table.getn(rows) do
                        local row = rows[i]
                        if type(row) == "table" and type(row[1]) == "number" and row[1] > 0 then
                            local itemId = tonumber(row[1])
                            local name = atlasLootPlain(row[3])
                            local quality = atlasLootQuality(row[3])
                            local chance = atlasLootChance(row[5])

                            local item = self.atlasLootItems[itemId]
                            if not item then
                                item = { id = itemId, name = name, quality = quality,
                                    texture = iconPath(row[2]), provider = "AtlasLoot" }
                                self.atlasLootItems[itemId] = item
                            else
                                if not item.name and name then item.name = name end
                                if type(item.quality) ~= "number" and type(quality) == "number" then
                                    item.quality = quality
                                end
                                if not item.texture then item.texture = iconPath(row[2]) end
                            end

                            local src = {
                                id = itemId,
                                name = sourceName,
                                instance = instance,
                                instanceKey = instanceKey,
                                dataId = dataId,
                                dataSource = dataSource,
                                provider = "AtlasLoot",
                                chance = chance,
                                sourceType = string.find(string.lower(sourceName), "trash", 1, true)
                                        and "trash" or "boss",
                            }
                            self.atlasLootItemSources[itemId] = self.atlasLootItemSources[itemId] or {}
                            table.insert(self.atlasLootItemSources[itemId], src)
                            table.insert(sourceItems, {
                                id = itemId,
                                chance = chance,
                                provider = "AtlasLoot",
                                worldDrop = src.sourceType == "trash" and chance > 0 and chance < 1 or nil,
                            })
                        end
                    end

                    if table.getn(sourceItems) > 0 then
                        local source = {
                            key = "atlasloot:" .. tostring(dataSource) .. ":" .. tostring(dataId),
                            provider = "AtlasLoot",
                            kind = "boss",
                            name = sourceBaseName(sourceName) or sourceName,
                            atlasName = sourceName,
                            instance = instance,
                            instanceKey = instanceKey,
                            dataId = dataId,
                            items = sourceItems,
                        }
                        local key = lowerPlain(source.name)
                        if key and key ~= "" then
                            self.atlasLootBossIndex[key] = self.atlasLootBossIndex[key] or {}
                            table.insert(self.atlasLootBossIndex[key], source)
                        end
                    end
                end
            end
        end
    end

    self.atlasLootIndexed = true
    self.atlasLootIndexedData = AtlasLoot_Data
    return true
end

function M:AtlasLootSource(name)
    if not name or name == "" then return nil end
    if not self:BuildAtlasLootIndex() then return nil end

    local key = lowerPlain(name)
    local list = key and self.atlasLootBossIndex[key]
    if type(list) ~= "table" then return nil end

    -- Prefer an AtlasLoot source whose instance key resembles the current zone.
    local zone = type(GetRealZoneText) == "function" and GetRealZoneText() or nil
    if zone then
        local zoneKey = sourceIdentity(zone)
        for i = 1, table.getn(list) do
            local inst = list[i].instance
            local instKey = sourceIdentity(inst)
            if instKey ~= "" and zoneKey ~= ""
                    and (instKey == zoneKey
                        or string.find(instKey, zoneKey, 1, true)
                        or string.find(zoneKey, instKey, 1, true)) then
                return list[i]
            end
        end
    end
    return list[1]
end

local function filterText(value)
    if type(value) ~= "string" then return nil end
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    if value == "" then return nil end
    return string.lower(value)
end

local function searchMatch(query, name, id)
    if not query or query == "" then return false end
    local numeric = tonumber(query)
    if numeric and tonumber(id) == numeric then return true end
    if not name then return false end
    return string.find(string.lower(name), query, 1, true) and true or false
end

function M:AddSearchResult(byId, itemId, name, quality, provider)
    itemId = tonumber(itemId)
    if not itemId then return end
    name = saneItemName(name, itemId)

    if name then
        self.knownItemNames = self.knownItemNames or {}
        self.knownItemNames[itemId] = self.knownItemNames[itemId] or name
    end

    local row = byId[itemId]
    if not row then
        row = { id = itemId, name = name, quality = quality, providers = {} }
        byId[itemId] = row
    end
    if not row.name and name then row.name = name end
    if type(row.quality) ~= "number" and type(quality) == "number" then row.quality = quality end
    if provider then row.providers[provider] = true end
end

--[[ **Everything a boss drops, found by the boss's name.**

     "Search by the enemy that drops it" is the other half of the browser's job
     and it had no answer at all: typing a boss's name searched item names, found
     nothing, and said there was nothing to find.

     Answered from the same index search already builds, walking sources rather
     than names. Deliberately a separate entry point rather than folded into
     `SearchItems`, so a name that is both -- and there are a few -- returns the
     item under its own name and the boss's drops under the boss. ]]--
function M:SearchBySource(text)
    local query = filterText(text)
    if not query then return {} end

    self:BuildAtlasLootIndex()

    local byId = {}
    for itemId, sources in pairs(self.atlasLootItemSources or {}) do
        for i = 1, table.getn(sources) do
            local name = filterText(sources[i] and sources[i].name)
            if name and string.find(name, query, 1, true) then
                local itemName, _, quality = self:ItemInfo(itemId)
                self:AddSearchResult(byId, itemId, itemName, quality, "AtlasLoot")
                if byId[itemId] then byId[itemId].matchedSource = sources[i] end
                break
            end
        end
    end

    --[[ Ordinary-world mobs too, so "what does a Defias Thug drop" works
         outside a dungeon. The unit index is keyed by id, so the name has to be
         resolved first. ]]--
    local unitId = self:PfUnitIdByName(text)
    if unitId then
        local drops = self:DirectPfLoot(unitId)
        for j = 1, table.getn(drops or {}) do
            local drop = drops[j]
            if drop and drop.id then
                local itemName, _, quality = self:ItemInfo(drop.id)
                self:AddSearchResult(byId, drop.id, itemName, quality, "ECO Loot DB")
            end
        end
    end

    local out = {}
    for _, row in pairs(byId) do
        local name, link, quality = self:ItemInfo(row.id)
        row.name = name or row.name or ("Item " .. tostring(row.id))
        row.link = link
        if type(quality) == "number" then row.quality = quality end
        table.insert(out, row)
    end

    table.sort(out, function(a, b)
        local aq = tonumber(a.quality) or -1
        local bq = tonumber(b.quality) or -1
        if aq ~= bq then return aq > bq end
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)

    return out
end

function M:SearchItems(text, filter)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")

    --[[ **An empty box with a filter set is a real question**, and it used to
         answer nothing. "Every blue in Scholomance" names no item, and refusing
         to run without a word typed is what made the filters impossible to use
         as filters rather than as a second search term. ]]--
    if text == "" then
        if type(filter) ~= "table" then return {} end
        return self:FilteredCatalogue(filter)
    end

    local query = string.lower(text)
    local byId = {}

    self:BuildAtlasLootIndex()
    for itemId, item in pairs(self.atlasLootItems or {}) do
        if searchMatch(query, item.name, itemId) then
            self:AddSearchResult(byId, itemId, item.name, item.quality, "AtlasLoot")
        end
    end

    -- The embedded snapshot carries the pfQuest English item-name table for
    -- every item that occurs in a loot pool, so search works with pfQuest off.
    local embeddedDb = self:EmbeddedDB()
    local pfNames = embeddedDb and embeddedDb.itemNames
            or (pfDB and pfDB.items and pfDB.items.loc)
    local lootProvider = embeddedDb and "ECO Loot DB" or "pfQuest"
    if type(pfNames) == "table" then
        local numeric = tonumber(query)
        local directName = numeric and foreignById(pfNames, numeric) or nil
        if numeric and directName then
            self:AddSearchResult(byId, numeric, directName, nil, lootProvider)
        elseif not numeric then
            for itemId, name in pairs(pfNames) do
                if searchMatch(query, name, itemId) then
                    self:AddSearchResult(byId, itemId, name, nil, lootProvider)
                end
            end
        end
    end

    --[==[ **The server's own item list, which is what the search was missing.**

         Every source above is a loot table, and a loot table knows an item only
         if something drops it. Hearthstone is not dropped. Neither is any quest
         reward, anything a vendor sells, anything crafted -- nor one single
         OctoWow-custom item, because the snapshot is Turtle's. Typing the name
         of the thing you were looking at on octowow.st found nothing, and it
         read as the search being broken. The search was fine; it had 7,666
         names and the server has three times that.

         Added as a source rather than replacing the others: it carries no
         drop information, so a hit from here alone lists the item with an empty
         source list, and a hit the loot tables also know keeps its drops. ]==]
    local octo = self:OctoItemDB()
    if octo then
        local quality = type(octo.quality) == "table" and octo.quality or nil
        local numeric = tonumber(query)
        if numeric then
            if octo.names[numeric] then
                self:AddSearchResult(byId, numeric, octo.names[numeric],
                        quality and quality[numeric], "OctoWow DB")
            end
        else
            for itemId, name in pairs(octo.names) do
                if searchMatch(query, name, itemId) then
                    self:AddSearchResult(byId, itemId, name,
                            quality and quality[itemId], "OctoWow DB")
                end
            end
        end
    end

    -- Atlas-CFM's DataIndex adds quests, crafting and other non-boss sources.
    if AtlasCFM and AtlasCFM.DataIndex and AtlasCFM.DataIndex.FindItems then
        local ok, found = pcall(AtlasCFM.DataIndex.FindItems, text, { partial = true })
        if ok and type(found) == "table" then
            for i = 1, table.getn(found) do
                local id = found[i] and tonumber(found[i][1])
                if id then
                    local name, _, quality = self:ItemInfo(id)
                    self:AddSearchResult(byId, id, name, quality, "Atlas CFM")
                end
            end
        end
    end

    -- Numeric IDs are useful even when the client has never cached the item.
    local directId = tonumber(query)
    if directId then
        local name, _, quality = self:ItemInfo(directId)
        if name or (self.atlasLootItemSources and self.atlasLootItemSources[directId])
                or (self.itemUnits and self.itemUnits[directId])
                or (self.itemObjects and self.itemObjects[directId])
                or (AtlasCFM and AtlasCFM.DataIndex and AtlasCFM.DataIndex.LocationCache
                    and AtlasCFM.DataIndex.LocationCache[directId]) then
            self:AddSearchResult(byId, directId, name, quality, "ID")
        end
    end

    local out = {}
    for _, row in pairs(byId) do
        local name, link, quality = self:ItemInfo(row.id)
        row.name = name or row.name or (self.atlasLootItems and self.atlasLootItems[row.id]
                and self.atlasLootItems[row.id].name) or ("Item " .. tostring(row.id))
        row.link = link
        if type(quality) == "number" then row.quality = quality end
        if type(row.quality) ~= "number" and self.atlasLootItems and self.atlasLootItems[row.id] then
            row.quality = self.atlasLootItems[row.id].quality
        end
        table.insert(out, row)
    end

    table.sort(out, function(a, b)
        local aq = tonumber(a.quality) or -1
        local bq = tonumber(b.quality) or -1
        if aq ~= bq then return aq > bq end
        local an = string.lower(a.name or "")
        local bn = string.lower(b.name or "")
        if an ~= bn then return an < bn end
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)

    --[[ **Filtered last**, after the providers have all had their say. Filtering
         each provider's contribution separately would let a row that only one of
         them knows the quality of be dropped by the others. ]]--
    if type(filter) == "table" then out = self:ApplyFilter(out, filter) end

    return out
end

--[[ Every item the index knows, narrowed by a filter and nothing else.

     What a filter with no search term means. Bounded by the filter itself
     rather than by a row cap, because a cap here would silently answer "these
     forty" to a question that asked for all of them -- the browser's own list is
     where the number on screen gets limited. ]]--
function M:FilteredCatalogue(filter)
    self:BuildAtlasLootIndex()

    local byId = {}
    for itemId, item in pairs(self.atlasLootItems or {}) do
        self:AddSearchResult(byId, itemId, item.name, item.quality, "AtlasLoot")
    end

    local rows = {}
    for _, row in pairs(byId) do
        local name, link, quality = self:ItemInfo(row.id)
        row.name = name or row.name or ("Item " .. tostring(row.id))
        row.link = link
        if type(quality) == "number" then row.quality = quality end
        table.insert(rows, row)
    end

    rows = self:ApplyFilter(rows, filter)

    table.sort(rows, function(a, b)
        local aq = tonumber(a.quality) or -1
        local bq = tonumber(b.quality) or -1
        if aq ~= bq then return aq > bq end
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)

    return rows
end

-- ---------------------------------------------------------------------------
-- filtering
-- ---------------------------------------------------------------------------

--[[ **Everything a row can be narrowed by, answered from one place.**

     Search used to be a name and nothing else, which is the wrong shape for the
     question people actually have: not "what is Thunderfury" -- they know -- but
     "what blues drop in Scholomance", "what does this boss have", "what is worth
     more than a one in ten chance". Every one of those is a field the data
     already carries and the browser simply never offered.

     The filter is a plain table so callers can build one field at a time, and
     an absent field means *no opinion* rather than a default. That distinction
     matters: `minChance = 0` is "anything, including unknown drop rates" and
     `minChance = nil` is the same thing said by not asking, but `quality = 0`
     is specifically poor-quality grey items. ]]--

--[[ Does any one of an item's sources satisfy the source-shaped filters?

     **Any, not all.** An item that drops from two bosses in two dungeons is a
     Scholomance drop *and* a Stratholme drop, and filtering to Scholomance must
     keep it. Requiring every source to match would hide exactly the items worth
     knowing about. ]]--
function M:SourcesMatchFilter(itemId, filter)
    local wantInstance = filterText(filter.instance)
    local wantSource = filterText(filter.source)
    local wantType = filterText(filter.sourceType)
    local minChance = tonumber(filter.minChance)

    if not wantInstance and not wantSource and not wantType and not minChance then
        return true, nil
    end

    local sources = self:GetItemSources(itemId)
    for i = 1, table.getn(sources) do
        local src = sources[i]
        local ok = true

        if wantInstance then
            local inst = filterText(src.instance)
            if not inst or not string.find(inst, wantInstance, 1, true) then ok = false end
        end

        --[[ The enemy that drops it, matched on the source's own name -- which
             is the boss for a dungeon row and the mob for an ordinary-world
             one, so "search by what drops it" is one field rather than two. ]]--
        if ok and wantSource then
            local name = filterText(src.name)
            if not name or not string.find(name, wantSource, 1, true) then ok = false end
        end

        if ok and wantType then
            local kind = filterText(src.sourceType)
            if not kind or not string.find(kind, wantType, 1, true) then ok = false end
        end

        --[[ An unknown drop rate is stored as zero, and zero is not a small
             chance -- it is no information. Asking for "at least 5%" must not
             quietly return every row whose rate nobody recorded. ]]--
        if ok and minChance and minChance > 0 then
            local chance = tonumber(src.chance) or 0
            if chance < minChance then ok = false end
        end

        if ok then return true, src end
    end

    return false, nil
end


--[[ **The item's type, slot and required level -- which is not what `ItemInfo`
     answers.**

     `ItemInfo` returns four values: name, link, quality, texture. It is the
     name-resolution path, and it merges the client's cache with the bundled
     Atlas-CFM and AtlasLoot tables so an item nobody has ever inspected still
     has a name to show.

     `ItemMatchesFilter` was reading it as though it were `GetItemInfo` itself:

         local _, _, _, minLevel, itemType, subType, _, equipLoc = self:ItemInfo(id)

     Four values into eight names. `minLevel` got the texture path, and
     `itemType`, `subType` and `equipLoc` got nil -- every time, for every item.
     The guard is `if wantType and itemType`, so with `itemType` always nil the
     type filter never rejected anything: picking Weapon left every consumable
     and every trade good exactly where it was. The slot and level filters were
     dead the same way, and neither errored, because reading past the end of a
     return list is nil rather than a fault.

     So this asks the client directly, in the client's own order. 1.12
     `GetItemInfo` answers name, link, quality, minLevel, type, subType,
     stackCount, equipLoc, texture. There is no item level on this client --
     `minLevel` is the level you must *be*, which is the number people mean when
     they ask whether they can use something yet.

     Cached because a filter pass asks this of every row, and the answer for an
     item cannot change within a session. Only complete answers are kept: an
     uncached item answers nil now and something real once the client has seen
     it, and caching the nil would make that permanent. ]]--
function M:ItemTypeInfo(itemId)
    itemId = tonumber(itemId) or itemId
    if not itemId then return nil, nil, nil, nil end

    self.itemTypeInfo = self.itemTypeInfo or {}
    local hit = self.itemTypeInfo[itemId]
    if hit then return hit.itemType, hit.subType, hit.equipLoc, hit.minLevel end

    if type(GetItemInfo) ~= "function" then return nil, nil, nil, nil end

    local _, _, _, minLevel, itemType, subType, _, equipLoc = GetItemInfo(itemId)

    --[[ Ask the client to fetch it if it does not have it yet, so the same
         filter applied a moment later is sharper than it was. `PrimeItem` is
         the existing hook for exactly this. ]]--
    if not itemType and self.PrimeItem then self:PrimeItem(itemId) end

    if itemType then
        self.itemTypeInfo[itemId] = { itemType = itemType, subType = subType,
                equipLoc = equipLoc, minLevel = minLevel }
    end

    return itemType, subType, equipLoc, minLevel
end
--[[ The item-shaped half: what the client can tell us about the item itself.

     Read through `ItemInfo`, so an item the client has never cached answers nil
     and is *kept* rather than filtered out. Dropping unknowns would make the
     list shrink as you scrolled, which is the worst kind of wrong. ]]--
function M:ItemMatchesFilter(row, filter)
    local minQ, maxQ = tonumber(filter.minQuality), tonumber(filter.maxQuality)
    local wantType = filterText(filter.itemType)
    local wantSlot = filterText(filter.slot)
    local maxLevel = tonumber(filter.maxRequiredLevel)

    --[[ **A set of rarities, any of which will do.**

         The browser sends this instead of a floor now, because the useful
         questions are not ranges -- "epics and legendaries" is, but "blues and
         purples but not greens" is not, and a floor can only say the first.
         `minQuality`/`maxQuality` are still honoured underneath: they are a
         range, this is a membership test, and callers that want a range have
         one.

         Unknown quality is *kept*, the same rule the rest of this function
         follows: an item the client has never cached answers nil, and dropping
         those would make the list shrink as you scrolled. ]]--
    if type(filter.qualities) == "table" then
        local q = tonumber(row.quality)
        if q and not filter.qualities[q] then return false end
    end

    if minQ or maxQ then
        local q = tonumber(row.quality)
        if q then
            if minQ and q < minQ then return false end
            if maxQ and q > maxQ then return false end
        end
    end

    local wantTypes = type(filter.itemTypes) == "table" and filter.itemTypes or nil
    local wantSubTypes = type(filter.subTypes) == "table" and filter.subTypes or nil

    if not wantType and not wantSlot and not maxLevel
            and not wantTypes and not wantSubTypes then
        return true
    end

    local itemType, subType, equipLoc, minLevel = self:ItemTypeInfo(row.id)

    --[[ **Types and subtypes are one "any of these", not two filters.**

         Ticking Weapon and then Daggers under it must not mean "a dagger that
         is also every weapon" -- both are ways of saying the item qualifies, so
         either satisfying is enough. Kept as a single test rather than two
         because the alternative is an empty result for the most natural thing
         somebody would click.

         Unknown type is kept, the same rule as everywhere else here: an item
         the client has never cached answers nil, and dropping those makes the
         list shrink as you scroll. ]]--
    if (wantTypes or wantSubTypes) and (itemType or subType) then
        local ok = false

        if wantTypes and itemType and wantTypes[string.lower(itemType)] then ok = true end
        if not ok and wantSubTypes and subType
                and wantSubTypes[string.lower(subType)] then
            ok = true
        end

        if not ok then return false end
    end

    if wantType and itemType then
        local haystack = string.lower(itemType .. " " .. (subType or ""))
        if not string.find(haystack, wantType, 1, true) then return false end
    end

    if wantSlot and equipLoc then
        if not string.find(string.lower(equipLoc), wantSlot, 1, true) then return false end
    end

    if maxLevel and tonumber(minLevel) and tonumber(minLevel) > maxLevel then
        return false
    end

    return true
end

--[[ Narrow a result list. Kept apart from `SearchItems` so the same filters
     apply to a dungeon's loot pool, which never went through a search at all. ]]--
function M:ApplyFilter(rows, filter)
    if type(filter) ~= "table" then return rows end

    local out = {}
    for i = 1, table.getn(rows) do
        local row = rows[i]
        if self:ItemMatchesFilter(row, filter) then
            local ok, matched = self:SourcesMatchFilter(row.id, filter)
            if ok then
                --[[ The source that satisfied the filter travels with the row so
                     the browser can say *why* it is in the list -- "Rattlegore,
                     12%" rather than leaving the reader to click each one. ]]--
                if matched then row.matchedSource = matched end
                table.insert(out, row)
            end
        end
    end

    return out
end

--[[ **Every dungeon the data knows about**, for the filter's own list.

     Gathered from Atlas-CFM's instance table rather than from the items,
     because a dungeon nobody has an item indexed for should still be
     selectable -- an empty result is an answer, and a missing entry looks like
     a bug in the filter. ]]--
--[==[ **Cached against the table it was built from, not cached forever.**

     This kept the first answer it ever gave. `AtlasCFM.InstanceData` is another
     addon's, and it is not necessarily populated when this is first asked --
     Atlas fills it as its own files load. Asked too early, the cache took a
     handful of instances, or none, and held them for the session however much
     Atlas added afterwards.

     The symptom is precise and does not look like a caching fault: the dungeon
     filter lists `Any dungeon` and a few names in alphabetical order and will
     not scroll past them. Nothing is wrong with the scrolling -- the list really
     does end there, and a list shorter than its window has nothing to scroll.

     `AtlasWorldDropSet` in this same file already had the answer: remember which
     table the cache was built from and rebuild when it is a different one. The
     count is checked as well, because Atlas fills the *same* table rather than
     replacing it, so identity alone would never notice. ]==]
local function instanceCount(source)
    if type(source) ~= "table" then return 0 end

    local n = 0
    for _ in pairs(source) do n = n + 1 end
    return n
end

function M:KnownInstances()
    local source = AtlasCFM and AtlasCFM.InstanceData or nil
    local count = instanceCount(source)

    if self.knownInstances and self.knownInstancesFrom == source
            and self.knownInstancesCount == count then
        return self.knownInstances
    end

    local out = {}
    if type(source) == "table" then
        for key, data in pairs(source) do
            local name = data and data.Name
            if type(name) == "string" and name ~= "" then
                table.insert(out, { key = key, name = name })
            end
        end
    end

    table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)

    self.knownInstances = out
    self.knownInstancesFrom = source
    self.knownInstancesCount = count

    return out
end

--[[ **A dungeon's whole loot pool, grouped by the boss that drops it.**

     The question somebody standing in a dungeon has is not "where does this
     item come from" but "what is in here, and who has it". Atlas-CFM answers it
     against a map you have to click through boss by boss; this answers it as a
     list, which is the form you can read while somebody is pulling.

     Bosses come back in Atlas's own order rather than alphabetically, because
     that order is roughly the order you meet them. ]]--
function M:InstanceLoot(instanceKey)
    if not instanceKey then return {} end
    if not AtlasCFM or type(AtlasCFM.InstanceData) ~= "table" then return {} end

    local data = AtlasCFM.InstanceData[instanceKey]
    if type(data) ~= "table" then return {} end

    self:BuildAtlasLootIndex()

    local groups, byBoss = {}, {}
    local function group(name)
        name = name or "Unknown"
        if byBoss[name] then return byBoss[name] end
        local g = { boss = name, items = {} }
        byBoss[name] = g
        table.insert(groups, g)
        return g
    end

    --[[ Walked from the loot tables rather than from the instance record,
         because the instance record names bosses and the loot lives against the
         table ids those names resolve to. One pass over the index we already
         build for search costs nothing extra. ]]--
    for itemId, sources in pairs(self.atlasLootItemSources or {}) do
        for i = 1, table.getn(sources) do
            local src = sources[i]
            if src and sourceIdentity(src.instance) == sourceIdentity(data.Name) then
                local name, link, quality = self:ItemInfo(itemId)
                table.insert(group(src.name).items, {
                    id = itemId,
                    name = name or ("Item " .. tostring(itemId)),
                    link = link,
                    quality = quality,
                    chance = tonumber(src.chance) or 0,
                    matchedSource = src,
                })
            end
        end
    end

    for g = 1, table.getn(groups) do
        table.sort(groups[g].items, function(a, b)
            local aq = tonumber(a.quality) or -1
            local bq = tonumber(b.quality) or -1
            if aq ~= bq then return aq > bq end
            return string.lower(a.name or "") < string.lower(b.name or "")
        end)
    end

    return groups
end

function M:GetItemSources(itemId)
    itemId = tonumber(itemId)
    if not itemId then return {} end
    self:BuildAtlasLootIndex()

    local out, seen = {}, {}
    local function add(src)
        if not src then return end
        local name = src.name or src.displayName or src.boss or "Unknown"
        local inst = src.instance or src.inst or src.page
        local key = sourceIdentity(name) .. "|" .. sourceIdentity(inst)
        local existing = seen[key]
        if existing then
            -- Prefer a real drop rate over an unknown one, and Atlas CFM over a
            -- duplicate legacy AtlasLoot row when both describe the same boss.
            if (tonumber(existing.chance) or 0) <= 0 and (tonumber(src.chance) or 0) > 0 then
                existing.chance = src.chance
            end
            if src.provider == "Atlas CFM" then existing.provider = src.provider end
            return
        end
        local copy = {}
        for k, v in pairs(src) do copy[k] = v end
        copy.name = name
        copy.instance = inst
        table.insert(out, copy)
        seen[key] = copy
    end

    for i = 1, table.getn((self.atlasLootItemSources and self.atlasLootItemSources[itemId]) or {}) do
        add(self.atlasLootItemSources[itemId][i])
    end

    -- Curated Atlas-CFM locations (bosses, quests, crafting, etc.).
    local locations = AtlasCFM and AtlasCFM.DataIndex and AtlasCFM.DataIndex.LocationCache
            and AtlasCFM.DataIndex.LocationCache[itemId]
    if type(locations) == "table" then
        for i = 1, table.getn(locations) do
            local loc = locations[i]
            add({
                name = loc.boss or loc.displayName or loc.page,
                instance = loc.inst or loc.page,
                provider = "Atlas CFM",
                sourceType = loc.type,
                chance = 0,
            })
        end
    end

    -- pfQuest ordinary-world NPC drops.
    local units = self.itemUnits and self.itemUnits[itemId]
    if type(units) == "table" then
        for unitId, chance in pairs(units) do
            local embeddedDb = self:EmbeddedDB()
            local name = embeddedDb and embeddedDb.unitNames
                    and foreignById(embeddedDb.unitNames, unitId)
                    or (pfDB and pfDB.units and pfDB.units.loc
                        and foreignById(pfDB.units.loc, unitId))
            add({
                name = name or ("NPC " .. tostring(unitId)),
                unitId = unitId,
                provider = embeddedDb and "ECO Loot DB" or "pfQuest",
                sourceType = "mob",
                chance = tonumber(chance) or 0,
            })
        end
    end


    -- pfQuest world-object drops (chests, mining/herbalism objects, containers,
    -- etc.). pfExtend indexes these as loot type "O" alongside normal units; an
    -- item-first database should not silently lose them just because there is no
    -- mouseover unit to attach them to.
    local objects = self.itemObjects and self.itemObjects[itemId]
    if type(objects) == "table" then
        for objectId, chance in pairs(objects) do
            local embeddedDb = self:EmbeddedDB()
            local name = embeddedDb and embeddedDb.objectNames
                    and foreignById(embeddedDb.objectNames, objectId)
                    or (pfDB and pfDB.objects and pfDB.objects.loc
                        and foreignById(pfDB.objects.loc, objectId))
            add({
                name = name or ("Object " .. tostring(objectId)),
                objectId = objectId,
                provider = embeddedDb and "ECO Loot DB" or "pfQuest",
                sourceType = "object",
                chance = tonumber(chance) or 0,
            })
        end
    end

    table.sort(out, function(a, b)
        local ac = tonumber(a.chance) or 0
        local bc = tonumber(b.chance) or 0
        if ac ~= bc then return ac > bc end
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    return out
end

-- Merge the two bundled curated databases before pfQuest is considered.
-- Atlas-CFM owns server visibility, containers, quantities and Turtle-specific
-- annotations; AtlasLoot contributes additional rows and often carries a more
-- precise measured drop percentage.  The full browser must be the union, not
-- whichever database happened to recognize the boss first.
function M:MergeCuratedSources(cfm, atlasLoot)
    if not cfm then return atlasLoot end
    if not atlasLoot then return cfm end

    self.curatedSourceCache = self.curatedSourceCache or {}
    local cacheKey = tostring(cfm.key) .. "|" .. tostring(atlasLoot.key)
    local cached = self.curatedSourceCache[cacheKey]
    if cached then return cached end

    local items, byId = {}, {}
    for i = 1, table.getn(cfm.items or {}) do
        local row = cfm.items[i]
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end
        copy.usesAtlas = true
        copy.provider = "Atlas CFM"
        table.insert(items, copy)
        byId[copy.id] = copy
    end

    for i = 1, table.getn(atlasLoot.items or {}) do
        local row = atlasLoot.items[i]
        local existing = byId[row.id]
        if existing then
            existing.usesAtlasLoot = true
            existing.atlasLootChance = tonumber(row.chance) or 0
            existing.cfmChance = tonumber(existing.chance) or 0
            -- AtlasLoot's rows carry explicit observed percentages while CFM
            -- often uses rounded encounter defaults. Keep the CFM metadata but
            -- use the explicit AtlasLoot percentage when it exists.
            if (tonumber(row.chance) or 0) > 0 then existing.chance = row.chance end
            if row.worldDrop then existing.worldDrop = true end
            existing.provider = "Atlas CFM + AtlasLoot"
        else
            local copy = {}
            for k, v in pairs(row) do copy[k] = v end
            copy.usesAtlasLoot = true
            copy.provider = "AtlasLoot"
            table.insert(items, copy)
            byId[copy.id] = copy
        end
    end

    local source = {
        key = "curated:" .. cacheKey,
        provider = "Atlas CFM + AtlasLoot",
        kind = cfm.kind or atlasLoot.kind,
        bossId = cfm.bossId,
        name = cfm.name or atlasLoot.name,
        atlasName = cfm.atlasName or atlasLoot.atlasName,
        instanceKey = cfm.instanceKey,
        instance = cfm.instance or atlasLoot.instance,
        dataId = atlasLoot.dataId,
        items = items,
        usesAtlas = true,
        usesAtlasLoot = true,
    }

    self.curatedSourceCache[cacheKey] = source
    return source
end

--[[ **The answer for one name, remembered.**

     `M:Decorate` calls this for every tick a tooltip is on screen -- a few dozen
     times for one hover -- and each call did four database lookups and asked
     for two merges. The merges have caches of their own, but reaching them
     costs two `tostring` calls and a concatenation to build the key, and the
     four lookups above them were repeated in full every time.

     Once the databases have answered, none of it can produce a different
     result: they are loaded once and do not change while you hover a corpse. ]]--

--[[ **How long a half-built answer is worth reusing.**

     Before pfQuest's reverse index finishes, every lookup goes down a slower
     path that *builds a fresh source table from raw loot rows on each call* --
     which is the expensive case, and also the one a first-hover-after-login
     lands in. Not caching it at all leaves that rebuild happening dozens of
     times for a single hover.

     Caching it permanently is worse: "nothing yet" would become the answer for
     the rest of the session, which looks exactly like a database that does not
     work.

     A second is the compromise. One hover reuses one answer; the next hover
     asks again and picks up the finished index the moment it exists. ]]--
local BUILDING_TTL = 1

function M:CachedSource(key, state, source)
    if state == "building" then
        self.buildingCache = self.buildingCache or {}
        self.buildingCache[key] = { source = source or false, at = GetTime() }
        return source
    end

    self.sourceCache = self.sourceCache or {}
    self.sourceCache[key] = source or false

    --[[ The half-built entry goes when the real one arrives, or a stale one
         could outlive the answer that replaced it. ]]--
    if self.buildingCache then self.buildingCache[key] = nil end

    return source
end

--[[ Returns the source, whether it was found at all, and the state it was
     stored with. **The state has to come back**: a caller that sees a `nil`
     source with no state reads it as "asked and answered, nothing here" and
     stops retrying -- so a cached `building` answer would freeze the tooltip
     half-finished for as long as the entry lived. ]]--
function M:LookupSource(key)
    if self.sourceCache then
        local hit = self.sourceCache[key]

        --[[ `false` is a remembered "nothing drops from this", which is the
             common answer for most things you hover. ]]--
        if hit == false then return nil, true end
        if hit ~= nil then return hit, true end
    end

    if self.buildingCache then
        local entry = self.buildingCache[key]

        if entry and (GetTime() - entry.at) < BUILDING_TTL then
            if entry.source == false then return nil, true, "building" end
            return entry.source, true, "building"
        end
    end

    return nil, false
end

function M:ForgetSources()
    self.sourceCache = nil
    self.buildingCache = nil
end

function M:GetSourceByName(name)
    if not name then return nil end

    local cached, found, cachedState = self:LookupSource(name)
    if found then return cached, cachedState end

    -- Both bundled curated databases are additive. pfQuest then augments the
    -- combined boss pool with ordinary-world/reverse-loot rows.
    local cfm = self:AtlasSource(name)
    local atlasLoot = self:AtlasLootSource(name)
    local curated = self:MergeCuratedSources(cfm, atlasLoot)
    local pf, state = self:PfSource(name)

    if curated and pf then
        return self:CachedSource(name, state, self:MergeSources(curated, pf)), state
    end

    if curated then return self:CachedSource(name, state, curated), state end

    return self:CachedSource(name, state, pf), state
end


-- Unit tooltips on Turtle/Octo commonly expose an explicit "NPC ID" line.
-- When it is available, use it. This bypasses every same-name/zone ambiguity and
-- asks pfQuest for the exact unit the player is actually hovering.
function M:GetSourceByUnitId(unitId, name)
    unitId = normalizedId(unitId)
    if not unitId then return self:GetSourceByName(name) end

    --[[ Keyed by the id and the name together. The id alone is not enough: the
         curated half of the answer is looked up by name, so two tooltips with
         the same id and different names are two different answers. ]]--
    local key = "#" .. tostring(unitId) .. "|" .. tostring(name)

    local cached, found, cachedState = self:LookupSource(key)
    if found then return cached, cachedState end

    local cfm = name and self:AtlasSource(name) or nil
    local atlasLoot = name and self:AtlasLootSource(name) or nil
    local curated = self:MergeCuratedSources(cfm, atlasLoot)
    local pf, state = self:PfSourceById(unitId, name)

    if curated and pf then
        return self:CachedSource(key, state, self:MergeSources(curated, pf)), state
    end

    if curated then return self:CachedSource(key, state, curated), state end

    return self:CachedSource(key, state, pf), state
end

function M:IsWorldDrop(row, cutoff)
    if not row then return false end
    if row.worldDrop ~= nil then return row.worldDrop and true or false end

    -- pfQuest does not label world drops. A tiny rate by itself is not enough:
    -- legitimate boss-specific rares can be below 1%. Treat a row as generic
    -- only when it is both below the configured cutoff and appears on many
    -- unrelated NPCs in the reverse index.
    local chance = tonumber(row.chance) or 0
    local count = tonumber(row.sourceCount) or 1
    return chance < (tonumber(cutoff) or 1) and count >= 8
end

function M:SortedItems(source)
    local out = {}
    if not source or type(source.items) ~= "table" then return out end

    local sortBy = self:Config().sortBy or "chance"

    for i = 1, table.getn(source.items) do
        local row = source.items[i]
        local copy = {}
        for k, v in pairs(row) do copy[k] = v end

        -- Default Drop Rate sorting needs no item-cache queries at all. Rarity
        -- sorting explicitly asks for quality, so paying that cost is expected.
        if sortBy == "rarity" then
            local name, link, quality = self:ItemInfo(copy.id)
            copy.name = name
            copy.link = link
            copy.quality = quality
        end

        -- pfQuest favourites remain useful after pfExtend is removed. Treat the
        -- existing pfBrowser favourite list as a preference, not as a provider:
        -- the same starred item rises to the top of both a normal-mob and an
        -- Atlas boss pool because both normalize to item IDs here.
        copy.favorite = pfBrowser_fav and pfBrowser_fav["items"]
                and pfBrowser_fav["items"][copy.id] and true or false

        table.insert(out, copy)
    end

    table.sort(out, function(a, b)
        if a.favorite ~= b.favorite then return a.favorite and true or false end

        if sortBy == "rarity" then
            local aq = tonumber(a.quality) or -1
            local bq = tonumber(b.quality) or -1
            if aq ~= bq then return aq > bq end

            local ac = tonumber(a.chance) or 0
            local bc = tonumber(b.chance) or 0
            if ac ~= bc then return ac > bc end
        else
            local ac = tonumber(a.chance) or 0
            local bc = tonumber(b.chance) or 0
            if ac ~= bc then return ac > bc end
        end

        local an = a.name or tostring(a.id)
        local bn = b.name or tostring(b.id)
        return an < bn
    end)

    return out
end

-- Browser implementation is attached by modules/itembrowser.lua. Keeping this
-- stub here means the Item Database page is still safe if that later file fails
-- to load: the action reports rather than throwing from the panel.
function M:OpenBrowser(source, requestedName)
    if self.ShowBrowser then return self:ShowBrowser(source, requestedName) end

    if type(OB.Print) == "function" then
        OB.Print("Item browser is not loaded.", "Item Database")
    end
    return false
end

function M:CheckBrowserShortcut()
    if not self.watchShortcut then return false end

    if type(UnitExists) == "function" and not UnitExists("mouseover") then
        self.watchShortcut = nil
        self.modifierHeld = nil
        return false
    end
    if type(UnitPlayerControlled) == "function" and UnitPlayerControlled("mouseover") then
        self.watchShortcut = nil
        self.modifierHeld = nil
        return false
    end

    local down = false
    if type(IsAltKeyDown) == "function" and type(IsControlKeyDown) == "function" then
        down = IsAltKeyDown() and IsControlKeyDown()
    end

    if down and not self.modifierHeld then
        local name = type(UnitName) == "function" and UnitName("mouseover") or self.hoverName
        local source, state
        local tipModule = OB.modules and OB.modules.tooltip
        local npcId = tipModule and type(tipModule.TooltipNpcId) == "function"
                and tipModule:TooltipNpcId(GameTooltip) or nil
        if npcId then
            source, state = self:GetSourceByUnitId(npcId, name)
        end

        -- The tooltip's NPC-ID row can be stale for one frame when another
        -- tooltip addon rewrites GameTooltip during a mouseover transition. The
        -- embedded name index is independent and is a safe second chance. Without
        -- this fallback Ctrl+Alt could claim "No loot pool found" for a mob such
        -- as Twilight Fire Guard even though its embedded loot row is present.
        if not source and name and name ~= "" then
            local byName, byNameState = self:GetSourceByName(name)
            if byName then
                source, state = byName, byNameState
            elseif not state then
                state = byNameState
            end
        end

        if state == "building" and name then self.browserWaitingName = name end
        self:OpenBrowser(source, name)
    end

    self.modifierHeld = down and true or false
    return true
end

function M:OnEvent()
    if event == "PLAYER_ENTERING_WORLD" then
        self.worldReady = true
        self.pfWaitingForWorld = nil

        -- The embedded source table is available from addon load; this event
        -- starts only the reverse item-source index in small background slices.
        -- A live pfQuest install remains a compatibility fallback when a
        -- development build intentionally omits data/pfquest_loot.lua.
        if not self.pfBuiltAfterWorld then
            self.pfBuiltAfterWorld = true
            self.pfReady = nil
            self.building = nil
            self.buildData = nil
            self.buildKey = nil
            self.pfUnavailable = nil
            self.unitLoot = nil
            self.objectLoot = nil
            self.itemSourceCount = nil
            self.itemUnits = nil
            self.itemObjects = nil
            self.pfSourceCache = nil
            self.pfDirectCache = nil
            self.mergedSourceCache = nil
            if not self:BeginPfQuestIndex() then
                self.pfRetryCount = 0
                self.nextPfRetry = (type(GetTime) == "function" and GetTime() or 0) + 1
                self.tickly = true
            end
        end
        return
    end

    if event ~= "UPDATE_MOUSEOVER_UNIT" then return end

    local name
    if type(UnitExists) ~= "function" or UnitExists("mouseover") then
        if type(UnitPlayerControlled) ~= "function" or not UnitPlayerControlled("mouseover") then
            if type(UnitName) == "function" then name = UnitName("mouseover") end
        end
    end

    self.hoverName = name
    self.watchShortcut = name and name ~= "" and true or nil
    self.modifierHeld = nil
    if self.watchShortcut then self.tickly = true end
end

function M:OnUpdate(now)
    -- OptionalDeps normally guarantees pfQuest is ready before ECO. Some custom
    -- loaders violate that order, so recover for a short startup window instead
    -- of permanently deciding that ordinary-world loot does not exist.
    if self.pfUnavailable and not self:EmbeddedDB() and (self.pfRetryCount or 0) < 15
            and (not self.nextPfRetry or now >= self.nextPfRetry) then
        self.pfRetryCount = (self.pfRetryCount or 0) + 1
        self.nextPfRetry = now + 1
        if pfDB and pfDB["items"] and type(pfDB["items"]["data"]) == "table" then
            self.pfUnavailable = nil
            self:BeginPfQuestIndex()
        end
    end

    if self.building and (not self.nextBuildAt or now >= self.nextBuildAt) then
        self.nextBuildAt = now + 0.02
        self:BuildPfQuestChunk(200)
    end

    self:UpdateItemRefresh(now)

    if self.browserRefreshPending and self.RefreshBrowser then
        if not self.browserRefreshAt or now >= self.browserRefreshAt then
            self.browserRefreshPending = nil
            self.browserRefreshAt = nil
            self:RefreshBrowser()
        end
    end

    self:CheckBrowserShortcut()

    local retryingPf = self.pfUnavailable and (self.pfRetryCount or 0) < 15
    if not self.building and not self.browserRefreshPending and not self.watchShortcut
            and not self.itemRefresh and not retryingPf then
        self.tickly = false
    end
end

function M:OnBind()
    -- AtlasLoot is bundled and immediately searchable from its static tables.
    self:BuildAtlasLootIndex()

    -- Atlas-CFM adds quests/crafting/location metadata through its own indexed
    -- API. Its implementation already builds incrementally, so request it once.
    if AtlasCFM and AtlasCFM.DataIndex and AtlasCFM.DataIndex.CheckAndBuildIndex then
        pcall(AtlasCFM.DataIndex.CheckAndBuildIndex)
    end

    -- Source lookup from the embedded database is immediate. The background
    -- index starts once the world is entered to avoid adding work to addon load.
    -- If enabled later in an already-entered world, start it now.
    if OB.worldEntered then
        self.worldReady = true
        self.pfBuiltAfterWorld = true
        if not self:BeginPfQuestIndex() then
            self.pfRetryCount = 0
            self.nextPfRetry = (type(GetTime) == "function" and GetTime() or 0) + 1
            self.tickly = true
        end
    else
        self.pfWaitingForWorld = true
    end
end

function M:OnUnbind()
    self.watchShortcut = nil
    self.hoverName = nil
    self.modifierHeld = nil
    self.itemRefresh = nil
    self.pfRetryCount = nil
    self.nextPfRetry = nil
    if self.browser and self.browser.Hide then self.browser:Hide() end
end

function M:OnStyle()
    if self.browser and self.browser.IsShown and self.browser:IsShown()
            and self.StyleBrowser then
        self:StyleBrowser()
        if self.RefreshBrowser then self:RefreshBrowser() end
    end
end

function M:OnDraw() end
