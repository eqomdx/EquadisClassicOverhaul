--[[ Equadis' Classic Overhaul :: shared market/pricing service

  One price API, multiple consumers.

  Tooltip presentation must not own auction-house knowledge. The Tooltip module
  only decides how prices are drawn; this file decides where those prices come
  from. A future ECO Auction House module can call the exact same API without
  depending on Tooltip or copying Aux-specific code.

  Current provider order for vendor values:
    * ECO learned: prices actually observed at a merchant on this account.
    * Aux: vendor resale value, auction history and today's market value.
    * ECO embedded: user-supplied Improved SellValue vanilla baseline.
    * ShaguTweaks: external static vendor-value fallback.

  Auction values remain adapter-driven. A future ECO Auction House module can
  register another provider and both Tooltip and Auction House will read it.
]]--

local OB = EquadisClassicOverhaul

OB.Market = OB.Market or {}
local Market = OB.Market

Market.providers = Market.providers or {}
Market.providerOrder = Market.providerOrder or {}

local function normalizedId(value)
    return tonumber(value) or value
end

local function providerSort(a, b)
    local pa = tonumber(a and a.priority) or 0
    local pb = tonumber(b and b.priority) or 0
    if pa == pb then return tostring(a.id or "") < tostring(b.id or "") end
    return pa > pb
end

function Market:RegisterProvider(id, provider, priority)
    if type(id) ~= "string" or id == "" or type(provider) ~= "table" then
        return false
    end

    local existing = self.providers[id]
    if existing then
        existing.provider = provider
        existing.priority = tonumber(priority) or existing.priority or 0
    else
        local entry = {
            id = id,
            provider = provider,
            priority = tonumber(priority) or 0,
        }
        self.providers[id] = entry
        table.insert(self.providerOrder, entry)
    end

    table.sort(self.providerOrder, providerSort)
    return true
end

function Market:Provider(id)
    local entry = self.providers[id]
    return entry and entry.provider or nil
end

function Market:ProviderIds()
    local ids = {}
    for i = 1, table.getn(self.providerOrder) do
        ids[i] = self.providerOrder[i].id
    end
    return ids
end


-- Store a vendor price only when ECO has actually observed it in a merchant
-- context. `OB.prices` is already account-wide SavedVariables storage; the
-- item-ID key is added alongside the legacy name key so Tooltip/Auction callers
-- do not need to know the item name first.
function Market:LearnVendor(itemId, value, name)
    itemId = normalizedId(itemId)
    value = tonumber(value)
    if not itemId or not value or value <= 0 then return false end

    OB.prices = OB.prices or {}
    OB.prices["item:" .. tostring(itemId)] = value
    if type(name) == "string" and name ~= "" then
        OB.prices[name] = value
    end
    return true
end

local function mergeValue(out, field, sourceField, value, source)
    if out[field] ~= nil or value == nil then return end
    out[field] = value
    out[sourceField] = source
end

function Market:ItemIdByName(name)
    if type(name) ~= "string" or name == "" then return nil end

    for i = 1, table.getn(self.providerOrder) do
        local entry = self.providerOrder[i]
        local provider = entry.provider
        if provider and type(provider.ItemIdByName) == "function" then
            local ok, itemId = pcall(provider.ItemIdByName, provider, name)
            if ok and itemId then return normalizedId(itemId) end
        end
    end

    return nil
end

function Market:GetVendor(itemId)
    itemId = normalizedId(itemId)
    if not itemId then return nil end

    local out = {
        itemId = itemId,
        vendor = nil,
        limited = nil,
        vendorSource = nil,
    }

    for i = 1, table.getn(self.providerOrder) do
        local entry = self.providerOrder[i]
        local provider = entry.provider
        if provider and type(provider.GetVendor) == "function" then
            local ok, values = pcall(provider.GetVendor, provider, itemId)
            if ok and type(values) == "table" then
                -- Providers may expose their source field as either `vendor`
                -- (ECO-native) or `sell` (legacy Aux/Shagu adapters). ECO only
                -- exposes the resale value; vendor purchase price is intentionally
                -- not part of the shared API.
                mergeValue(out, "vendor", "vendorSource",
                        values.vendor ~= nil and values.vendor or values.sell, entry.id)
                if out.limited == nil and values.limited ~= nil then
                    out.limited = values.limited and true or false
                end
            end
        end
    end

    return out
end

function Market:GetAuction(itemId, suffixId)
    itemId = normalizedId(itemId)
    suffixId = tonumber(suffixId) or 0
    if not itemId then return nil end

    local out = {
        itemId = itemId,
        suffixId = suffixId,
        auction = nil,
        today = nil,
        auctionSource = nil,
        todaySource = nil,
    }

    for i = 1, table.getn(self.providerOrder) do
        local entry = self.providerOrder[i]
        local provider = entry.provider
        if provider and type(provider.GetAuction) == "function" then
            local ok, values = pcall(provider.GetAuction, provider, itemId, suffixId)
            if ok and type(values) == "table" then
                mergeValue(out, "auction", "auctionSource", values.auction, entry.id)
                mergeValue(out, "today", "todaySource", values.today, entry.id)
            end
        end
    end

    return out
end

function Market:GetHistory(itemId, suffixId)
    itemId = normalizedId(itemId)
    suffixId = tonumber(suffixId) or 0
    if not itemId then return nil end

    for i = 1, table.getn(self.providerOrder) do
        local entry = self.providerOrder[i]
        local provider = entry.provider
        if provider and type(provider.GetHistory) == "function" then
            local ok, history = pcall(provider.GetHistory, provider, itemId, suffixId)
            if ok and history ~= nil then return history, entry.id end
        end
    end

    return nil
end

--[[ **What an item has been worth, rather than what it is worth today.**

     `GetHistory` has been here since this file was written and nothing has ever
     read it. It returns the provider's own series -- aux keeps up to eleven
     dated points, one per day it has seen the item -- and a series is the only
     thing that can answer "is this expensive at the moment or is it always this
     expensive", which is the question a single market value cannot.

     Averaged plainly rather than weighted. `Market:GetPrices().auction` is
     already aux's weighted median and is the better number for "what is this
     worth"; the point of this one is different -- it is the flat mean against a
     high and a low, so the three read as a range with a middle. Two differently
     weighted averages sitting next to each other would just look like a
     disagreement.

     Points with no value are skipped rather than counted as zero: a day the
     provider recorded nothing is a gap in the series, and treating it as a free
     item would drag every average down and make every low a lie. ]]--
function Market:GetStats(itemId, suffixId)
    local history = self:GetHistory(itemId, suffixId)
    if type(history) ~= "table" then return nil end

    local total, count, high, low = 0, 0, nil, nil
    local newest, oldest = nil, nil

    for _, point in pairs(history) do
        local value = point and tonumber(point.value)

        if value and value > 0 then
            total = total + value
            count = count + 1

            if not high or value > high then high = value end
            if not low or value < low then low = value end

            local when = tonumber(point.time)
            if when then
                if not newest or when > newest then newest = when end
                if not oldest or when < oldest then oldest = when end
            end
        end
    end

    if count == 0 then return nil end

    return {
        average = total / count,
        high = high,
        low = low,

        --[[ How many days the answer rests on. A high and a low taken from two
             points are two prices, not a range, and anything showing this ought
             to be able to say so. ]]--
        points = count,

        newest = newest,
        oldest = oldest,
    }
end

function OB.GetItemStats(itemId, suffixId)
    return Market:GetStats(itemId, suffixId)
end

function Market:GetPrices(itemId, suffixId)
    itemId = normalizedId(itemId)
    suffixId = tonumber(suffixId) or 0
    if not itemId then return nil end

    local vendor = self:GetVendor(itemId) or {}
    local auction = self:GetAuction(itemId, suffixId) or {}

    return {
        itemId = itemId,
        suffixId = suffixId,

        vendor = vendor.vendor,
        vendorLimited = vendor.limited,

        auction = auction.auction,
        today = auction.today,

        vendorSource = vendor.vendorSource,
        auctionSource = auction.auctionSource,
        todaySource = auction.todaySource,
    }
end

-- Short public alias for consumers which do not want to keep a local reference
-- to OB.Market. The future Auction House module can use either spelling.
function OB.GetItemPrices(itemId, suffixId)
    return Market:GetPrices(itemId, suffixId)
end

-- ---------------------------------------------------------------------------
-- ECO merchant-observed vendor values (highest authority)
-- ---------------------------------------------------------------------------

local LearnedVendorProvider = {}

function LearnedVendorProvider:GetVendor(itemId)
    if type(OB.prices) ~= "table" then return nil end

    local value = OB.prices["item:" .. tostring(itemId)]

    -- Compatibility with prices learned by older ECO builds, which stored only
    -- the item name. Item tooltips have normally cached GetItemInfo already, so
    -- this upgrades old account-wide observations without a migration pass.
    if value == nil and type(GetItemInfo) == "function" then
        local name
        local ok, found = pcall(GetItemInfo,
                "item:" .. tostring(itemId) .. ":0:0:0:0:0:0:0")
        if ok then name = found end
        if not name then
            ok, found = pcall(GetItemInfo, itemId)
            if ok then name = found end
        end
        if name then value = OB.prices[name] end
    end

    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return { vendor = value }
end

Market:RegisterProvider("eco-learned", LearnedVendorProvider, 100)

-- ---------------------------------------------------------------------------
-- Aux provider
-- ---------------------------------------------------------------------------

local AuxProvider = {}

function AuxProvider:Modules()
    -- Aux provides its own package/require implementation. Resolve lazily so ECO
    -- can load whether Aux is installed, disabled, or happens to initialize later.
    if type(require) ~= "function" then return nil, nil end

    if not self.info then
        local ok, module = pcall(require, "aux.util.info")
        if ok and type(module) == "table" then self.info = module end
    end
    if not self.history then
        local ok, module = pcall(require, "aux.core.history")
        if ok and type(module) == "table" then self.history = module end
    end

    return self.info, self.history
end

function AuxProvider:ItemIdByName(name)
    local info = self:Modules()
    if not info or type(info.item_id) ~= "function" then return nil end
    local ok, itemId = pcall(info.item_id, name)
    if ok then return itemId end
    return nil
end

function AuxProvider:GetVendor(itemId)
    local info = self:Modules()
    if not info or type(info.merchant_info) ~= "function" then return nil end

    -- Uploaded Aux version returns: sell price, buy price, limited-stock flag.
    -- ECO deliberately ignores the vendor purchase price and exposes only the
    -- amount the player receives when vendoring the item.
    local ok, sell, _, limited = pcall(info.merchant_info, itemId)
    if not ok then return nil end
    return { vendor = sell, limited = limited }
end

function AuxProvider:GetAuction(itemId, suffixId)
    local _, history = self:Modules()
    if not history then return nil end

    local key = tostring(itemId or 0) .. ":" .. tostring(suffixId or 0)
    local auction, today

    if type(history.value) == "function" then
        local ok, value = pcall(history.value, key)
        if ok then auction = value end
    end
    if type(history.market_value) == "function" then
        local ok, value = pcall(history.market_value, key)
        if ok then today = value end
    end

    if auction == nil and today == nil then return nil end
    return { auction = auction, today = today }
end

function AuxProvider:GetHistory(itemId, suffixId)
    local _, history = self:Modules()
    if not history or type(history.data_points) ~= "function" then return nil end

    local key = tostring(itemId or 0) .. ":" .. tostring(suffixId or 0)
    local ok, data = pcall(history.data_points, key)
    if ok then return data end
    return nil
end

Market:RegisterProvider("aux", AuxProvider, 50)

-- ---------------------------------------------------------------------------
-- ECO embedded vanilla vendor-value fallback
-- ---------------------------------------------------------------------------

local EmbeddedVendorProvider = {}

function EmbeddedVendorProvider:GetVendor(itemId)
    local db = EquadisClassicOverhaulVendorDB
    local values = db and db.values
    if type(values) ~= "table" then return nil end

    local value = values[itemId]
    if value == nil then value = values[tonumber(itemId)] end
    value = tonumber(value)
    if not value or value <= 0 then return nil end
    return { vendor = value }
end

-- Below Aux, above external static tables. This makes ECO self-contained while
-- still allowing live/learned server data to override the vanilla baseline.
Market:RegisterProvider("eco-static", EmbeddedVendorProvider, 20)

-- ---------------------------------------------------------------------------
-- ShaguTweaks vendor-value fallback
-- ---------------------------------------------------------------------------

local ShaguProvider = {}

function ShaguProvider:GetVendor(itemId)
    if not ShaguTweaks or type(ShaguTweaks.SellValueDB) ~= "table" then return nil end
    local sell = ShaguTweaks.SellValueDB[itemId]
    if sell == nil then sell = ShaguTweaks.SellValueDB[tostring(itemId)] end
    if sell == nil then return nil end
    return { vendor = sell }
end

Market:RegisterProvider("shagutweaks", ShaguProvider, 10)
