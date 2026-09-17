--[[ Equadis' Classic Overhaul :: auction house

  ECO does not implement an auction house. aux-addon does, it does it well, and
  the copy the Octo updater installs is the one people are running.

  What this module does is the part aux leaves out and the part that keeps being
  lost: a look that matches the rest of the interface, and a full scan that
  happens on its own.

  **Everything here works from outside aux.** Nothing in this file edits aux's
  own source, and that is the whole point of it existing: the Octo updater
  tracks `OldManAlpha/aux-addon` and replaces the folder wholesale, so any change
  made inside it survives exactly until the next update. A skin applied from
  here survives every update aux ever gets.

  The limits of working from outside are real and worth stating. aux's palette
  is built with `immutable-{...}`, a proxy whose `__newindex` discards writes and
  whose `__metatable` is false, and its colours are consumed as *closures* at
  frame-build time. There is no supported way to change the palette itself. So
  the colours here are applied to the frames after aux has built them, which
  reaches the backdrops, borders and text -- everything you actually look at --
  and does not reach colour escapes aux bakes into strings it formats. Those
  stay aux's.
]]--

local OB = EquadisClassicOverhaul
local floor, format = math.floor, string.format

--[[ aux ships its own `require`, and ECO already talks to it that way in
     pricing.lua. Resolved lazily every time rather than cached at load, because
     this module loads whether aux is installed, disabled, or initialising after
     us. ]]--
local function auxModule(name)
    if type(require) ~= "function" then return nil end
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then return module end
    return nil
end

local M = OB.RegisterModule({
    id = "auction",
    name = "Auction House",

    --[[ A feature, because it is a subsystem you would switch off -- but one
         that owns no window. Like the chat module, it decorates something that
         already exists. ]]--
    feature = true,
    renders = "none",

    --[[ Off. It restyles another addon's frames and can start a scan on its own
         account; both should be decisions. ]]--
    --[==[ **On, like everything else.**

         This module shipped off. So did twelve others, which meant a fresh
         install of this addon did very nearly nothing until somebody went
         through the Modules page switching things on -- and nothing on screen
         said that was the step they were missing. It was reported as settings
         not carrying across to a new character, which is what an addon that is
         installed and not running looks like from outside.

         The flag exists for a feature that is not finished, where drawing
         nothing is indistinguishable from being broken. None of the thirteen
         were that; they were caution, and the setup walkthrough is where that
         caution belongs now -- it goes through every module in turn and offers
         exactly this switch, with a description of what the module does. A
         decision somebody is walked through is better than a default they never
         find. ]==]

    defaults = {
        --[[ **The look.**

             aux ships Arial Narrow, chosen because auction rows pack a lot of
             columns into a little space. Friz Quadrata is the client's own face
             and what the rest of this interface uses, so it is the default here
             -- but it is wider, which is exactly why this is a setting and not
             a hardcoded swap. ]]--
        skin = true,
        font = OB.fontIndex and OB.fontIndex["Friz Quadrata"] or 1,

        --[[ Left nil rather than given a number, so aux's own sizes are kept
             until somebody asks otherwise. Its listings are tuned to them and
             a blanket size would break the column fit. ]]--
        fontSize = 0,

        backgroundColor = { 0.09, 0.09, 0.10, 0.95 },
        borderColor = { 0.35, 0.35, 0.40, 1 },
        headerColor = { 1.00, 0.82, 0.00, 1 },
        textColor = { 1.00, 1.00, 1.00, 1 },

        --[[ **A full sweep on a clock.**

             The build of aux the Octo updater installs has no full-scan button,
             and `AuctionQueryThrottle.dll` has taken the client's own five
             second wait out -- so nothing is stopping a scan and nothing is
             starting one either. Price history only exists if something sweeps
             the house, and remembering to do it by hand is how people end up
             with a week-old market value.

             Four hours because that is roughly how often a realm's prices move
             enough to matter, and because a sweep is a few hundred queries: often
             enough to be current, rare enough not to be rude. ]]--
        autoScan = false,
        autoScanHours = 4,

        --[[ Only with the auction house open, because that is the only time the
             client will answer a query at all. This is a statement of fact
             rather than a policy, and it is why the timer is a *deadline* that
             is checked when the window opens rather than an alarm that fires on
             its own. ]]--
        autoScanNotify = true,

        --[==[ **ECO's sweep stays out of the way while you are buying**, and
             there is no switch for it. See `BuyInProgress`.

             A sweep competing with a purchase for the same throttle is the addon
             getting in the way of the thing the player actually came to do. Off
             did not buy anybody a faster scan; it bought them a scan that fought
             the purchase. ]==]

        --[[ **One favourite per search.** aux does not check, so a list built
             over a few sessions ends up holding the same item three times and
             scanning for it three times. See `InstallFavouriteGuard`. ]]--
        uniqueFavourites = true,

        --[[ **Price the favourites when the window opens.** Cheaper than a
             sweep -- it asks only about the things you said you cared about --
             and it is the answer you opened the auction house for. ]]--
        scanFavourites = true,
    },

    options = {
        { "Appearance", "__s_look", "section", "look" },

        --[[ Applied to aux's frames after it has built them. See the note at
             the top of this file for what that reaches and what it does not. ]]--
        { "Restyle The Auction House", "skin", "boolean" },
        { "Font", "font", OB.fonts, 200, nil, nil, nil, nil, "!skin" },
        { "Font Size", "fontSize", "slider", 0, 20, 1,
          nil, nil, "!skin" },

        { "Background", "backgroundColor", "color", true,
          nil, nil, nil, nil, "!skin" },
        { "Border", "borderColor", "color", true,
          nil, nil, nil, nil, "!skin" },
        { "Headers", "headerColor", "color", true,
          nil, nil, nil, nil, "!skin" },
        { "Text", "textColor", "color", true,
          nil, nil, nil, nil, "!skin" },

        { "Scanning", "__s_scan", "section", "scan" },

        { "Scan Automatically", "autoScan", "boolean" },
        { "Hours Between Scans", "autoScanHours", "slider", 1, 24, 1,
          nil, nil, "!autoScan" },
        { "One Of Each Favourite", "uniqueFavourites", "boolean" },
        { "Price Favourites On Open", "scanFavourites", "boolean" },
        { "Say When A Scan Starts", "autoScanNotify", "boolean",
          nil, nil, nil, nil, nil, "!autoScan" },

        { "Scan Now", "__a_scan", "action",
          function() OB.modules.auction:StartScan(true) end,
          function()
              local wait = OB.modules.auction:ScanWait()
              if wait > 0 then
                  return "Next Scan In " .. OB.modules.auction:WaitText(wait)
              end
              return "Scan Now"
          end },
    },

    --[[ The auction house opening is the only moment a scan can start, so it is
         the only event this module needs. ]]--
    events = { "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" },

    requires = { "require" },
})

function M:Config()
    return OB.profile.modules.auction
end

--[==[ **`require` is not how you reach most of aux, and this module assumed it
     was.**

     aux's package system gives each file an environment and a separate exports
     table. `module 'aux.tabs.search'` swaps the file's environment; writing
     `favorite_searches = ...` puts the name in that environment and nowhere
     else. Only `M.name = value` copies it to exports, and exports is all
     `require` hands back.

     `tabs/search/` writes to `M` nowhere. So `require 'aux.tabs.search'` returns
     a table in which every name this module wanted -- `favorite_searches`,
     `favorite_searches_listing`, `add_favorite` -- is nil.

     It fails silently in both directions, which is why it looked like the
     feature had simply stopped. Reading a missing export gives nil and every
     install here is written to return false on nil rather than complain. And
     the interface's `__newindex` is `pass`: `search.add_favorite = wrapper`
     is *discarded*, with no error and no effect.

     The environment itself is reachable, because every function aux defined in
     that file still carries it. `getfenv` on any one of them is the whole
     module -- readable, and writable, since the environment is a plain table
     whose only metamethod is `__index = _G`. The way in is a script handler on
     one of aux's own frames.

     `aux_frame` is a real global -- aux names it so it can go in
     `UISpecialFrames` -- so the search is anchored rather than a sweep of
     UIParent. ]==]
local ENV_SCRIPTS = { "OnUpdate", "OnShow", "OnHide", "OnClick", "OnEvent" }

local function envOf(frame, marker)
    for i = 1, table.getn(ENV_SCRIPTS) do
        local handler = frame.GetScript and frame:GetScript(ENV_SCRIPTS[i])

        if type(handler) == "function" then
            local ok, env = pcall(getfenv, handler)

            --[[ `rawget` rather than a plain index. The environment's metatable
                 is `__index = _G`, so asking it for a name it does not have
                 answers with the *global* of that name -- and a marker that
                 happens to be a global would match every module aux has. ]]--
            if ok and type(env) == "table" and rawget(env, marker) ~= nil then
                return env
            end
        end
    end

    return nil
end

function M:AuxEnvironment(marker)
    if type(getfenv) ~= "function" then return nil end

    local root = getglobal("aux_frame")
    if not root or not root.GetChildren then return nil end

    --[[ Breadth first and depth-limited. The tab roots are direct children of
         aux's window, so the answer is one level down; the limit is what stops
         a frame parented back up the tree from walking for ever. ]]--
    local level = { root }

    for depth = 0, 3 do
        local deeper = {}

        for i = 1, table.getn(level) do
            local frame = level[i]
            local env = envOf(frame, marker)
            if env then return env end

            if frame.GetChildren then
                for _, child in ipairs({ frame:GetChildren() }) do
                    table.insert(deeper, child)
                end
            end
        end

        if table.getn(deeper) == 0 then return nil end
        level = deeper
    end

    return nil
end

--[==[ **Putting something back into an aux module, which is not an assignment.**

     `require` answers an interface whose `__newindex` is `pass`, so
     `scan.start = wrapper` is discarded -- silently, and with the read still
     working, so the wrapper appears to be installed and never runs. That is the
     second half of the same mistake the favourites made, and it cost the scan
     watch: the sweep never stood down for the player, because the thing meant
     to notice was never in the path.

     The way through is aux's own: every module environment holds `M`, a proxy
     whose `__newindex` writes to the environment *and* to the exports table
     that `require` hands out. Assigning through it is exactly what aux's own
     files do, so both kinds of caller -- aux's internal ones, which look names
     up in the environment, and everybody else's, which go through `require` --
     end up seeing the same function.

     The write is checked rather than assumed. This whole class of bug is a
     write that goes nowhere, and the only honest way to install a wrapper is to
     confirm it landed. ]==]
function M:AuxSet(env, name, value)
    if type(env) ~= "table" then return false end

    local exports = rawget(env, "M")

    if type(exports) == "table" then
        pcall(function() exports[name] = value end)
        if rawget(env, name) == value then return true end
    end

    --[[ A module found some other way, or a build whose package system does not
         work like this one's. A plain table takes a plain write. ]]--
    pcall(function() env[name] = value end)
    return rawget(env, name) == value
end

--[[ **The environment behind an exported function.**

     A module with no frame of its own cannot be found by walking the interface,
     but any function it did export still carries its environment -- and the
     environment is where `M` lives. So one export is enough of a handle to
     write back through. ]]--
function M:AuxModuleEnv(name, exported)
    if type(getfenv) ~= "function" then return nil end

    local iface = auxModule(name)
    if not iface or type(iface[exported]) ~= "function" then return nil end

    local ok, env = pcall(getfenv, iface[exported])
    if ok and type(env) == "table" and rawget(env, "M") then return env end

    return nil
end

--[[ The search tab, however this build of aux exposes it. A build that does
     export it is believed; this one does not, and is found through its
     environment instead.

     Not cached when the answer is nil, so a bind that happens before aux has
     built its window is retried when the auction house opens. ]]--
function M:AuxSearch()
    if self.auxSearch then return self.auxSearch end

    local exported = auxModule("aux.tabs.search")
    if exported and exported.favorite_searches_listing then
        self.auxSearch = exported
        return exported
    end

    self.auxSearch = self:AuxEnvironment("update_search_listings")
    return self.auxSearch
end

--[[ Whether aux is here at all. Everything below is a no-op without it, and
     that is the correct behaviour rather than an error: this module decorates
     an addon, and an addon that is not installed is not a fault. ]]--
function M:Available()
    --[[ A named export rather than the table. aux's `require` *creates* a module
         for a name it has never heard of and hands back an empty interface, so
         a non-nil table says only that something defined `require` -- not that
         aux is running. ]]--
    local gui = auxModule("aux.gui")
    return (gui and gui.font ~= nil) and true or false
end

-- ---------------------------------------------------------------------------
-- the look
-- ---------------------------------------------------------------------------

--[[ **Applied to the frames, not to aux's palette.**

     aux's colours live in an `immutable-{...}` proxy that discards writes, and
     they are consumed as closures when a frame is built. There is no supported
     way to change them. Walking the frames afterwards reaches the backdrops,
     the borders and the text, which is everything somebody means when they say
     the auction house should match the rest of their interface.

     Recursive, because aux nests panels several deep and the interesting frames
     are all leaves. Depth-limited so a cycle -- or a frame parented to UIParent
     somewhere in the tree -- cannot take the client down with it. ]]--
function M:StyleFrame(frame, depth)
    if not frame or depth > 8 then return end

    local cfg = self:Config()

    if frame.SetBackdropColor and frame.GetBackdrop and frame:GetBackdrop() then
        local bg = cfg.backgroundColor
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)

        local border = cfg.borderColor
        if frame.SetBackdropBorderColor then
            frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
        end
    end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            self:StyleRegion(region)
        end
    end

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            self:StyleFrame(child, depth + 1)
        end
    end
end

--[[ A font string is a header if aux gave it a larger size than its own medium,
     which is how aux itself distinguishes them -- there is no flag to read.
     Everything else is body text. ]]--
function M:StyleRegion(region)
    if not region or not region.GetObjectType then return end
    if region:GetObjectType() ~= "FontString" then return end

    local cfg = self:Config()
    local gui = auxModule("aux.gui")

    local path, size, flags = region:GetFont()
    if not path then return end

    local wanted = OB.fontPaths and OB.fontPaths[tonumber(cfg.font) or 1] or nil
    local wantedSize = tonumber(cfg.fontSize) or 0
    if wantedSize <= 0 then wantedSize = size end

    if wanted then
        region:SetFont(wanted, wantedSize, flags)

        --[[ A font that will not load leaves the string invisible rather than
             erroring, so the previous one goes back on. Same guard
             `OB.ApplyFont` uses. ]]--
        if not region:GetFont() then region:SetFont(path, size, flags) end
    end

    if region.SetTextColor then
        local large = gui and gui.font_size and gui.font_size.large or 18
        local color = (size and size >= large) and cfg.headerColor or cfg.textColor
        region:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    end
end

--[[ aux builds its window once, the first time it is opened, so this runs when
     the auction house shows rather than at bind -- at bind there is nothing
     there to style. ]]--
function M:ApplySkin()
    if not OB.ModuleEnabled("auction") then return false end
    if not self:Config().skin then return false end

    --[[ Nothing to restyle without aux. Asked before the frame walk rather than
         after, so an install that does not have aux does not pay for a scan of
         every child of UIParent looking for frames that cannot be there. ]]--
    if not self:Available() then return false end

    --[[ **And nothing to restyle with the auction house shut.**

         This walks every child of UIParent to eight levels deep, and it ran on
         every `OnStyle` -- which is every `OB.Refresh`, which is a great many
         things. The frames do not change while the window is shut, so there is
         nothing to catch up on: the next `AUCTION_HOUSE_SHOW` styles them. ]]--
    if not self:HouseOpen() then return false end

    --[[ aux names its own window so it can put it in `UISpecialFrames`, which
         is the one fixed name it has. ]]--
    local frame = getglobal("aux_frame") or getglobal("AuxFrame")
    if not frame then

        --[[ aux names its frames through `gui.unique_name`, which is a counter
             -- so there is no fixed name to look for. Found instead by asking
             the client for UIParent's children and keeping the ones whose name
             looks like aux's. ]]--
        if not UIParent or not UIParent.GetChildren then return false end

        --[[ Type-checked rather than merely nil-checked. Not every child of
             UIParent answers `GetName` with a string -- some answer with
             nothing and some with an object -- and `string.find` on either
             takes the client down rather than skipping a frame. ]]--
        for _, child in ipairs({ UIParent:GetChildren() }) do
            local name = child and child.GetName and child:GetName()
            if type(name) == "string" and string.find(name, "^aux") then
                self:StyleFrame(child, 0)
            end
        end

        return true
    end

    self:StyleFrame(frame, 0)
    return true
end

--[==[ **The auction house being open is not `AuctionFrame:IsShown()`.**

     That guard was added to stop a walk of the interface running on every
     refresh, and it is the right idea gated on the wrong frame: the first thing
     aux does on `AUCTION_HOUSE_SHOW` is `AuctionFrame:Hide()`. So the client's
     own auction window is hidden for exactly as long as the auction house is
     open, and this answered "shut" every single time the skin could have been
     applied.

     Cheap and correct in both directions: aux's window when aux is drawing it,
     the client's when it is not. ]==]
function M:HouseOpen()
    local window = getglobal("aux_frame")
    if window and window.IsShown and window:IsShown() then return true end

    if type(AuctionFrame) == "table" and AuctionFrame.IsShown
            and AuctionFrame:IsShown() then
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- scanning on a clock
-- ---------------------------------------------------------------------------

--[[ When the last sweep finished, kept per realm and faction because that is
     what an auction house is: scanning Horde Kronos says nothing about Alliance
     Kronos. Stored beside the profile rather than in it, so switching profiles
     does not make the addon think it has never scanned. ]]--
function M:LastScan()
    if type(EquadisClassicOverhaulDB) ~= "table" then return 0 end

    EquadisClassicOverhaulDB.auctionScans = EquadisClassicOverhaulDB.auctionScans or {}
    local key = self:HouseKey()

    return tonumber(EquadisClassicOverhaulDB.auctionScans[key]) or 0
end

function M:NoteScan()
    if type(EquadisClassicOverhaulDB) ~= "table" then return false end

    EquadisClassicOverhaulDB.auctionScans = EquadisClassicOverhaulDB.auctionScans or {}
    EquadisClassicOverhaulDB.auctionScans[self:HouseKey()] = time()
    return true
end

function M:HouseKey()
    --[[ Through `OB.CVar`: `GetCVar` raises on a name the client does not
         know, and the `type(GetCVar) == "function"` this had checks the function
         rather than the name. Caught by the harness once the stub started
         failing the way the client does. ]]--
    local realm = OB.CVar("realmName") or "Unknown"
    local faction = (type(UnitFactionGroup) == "function"
            and UnitFactionGroup("player")) or "Unknown"
    return tostring(realm) .. "|" .. tostring(faction)
end

--[[ How long until the next sweep is due, in seconds, or zero if one is. ]]--
function M:ScanWait()
    local last = self:LastScan()
    if last <= 0 then return 0 end

    local hours = tonumber(self:Config().autoScanHours) or 4
    if hours < 1 then hours = 1 end

    local remaining = (last + (hours * 60 * 60)) - time()
    if remaining < 0 then return 0 end
    return remaining
end

function M:WaitText(seconds)
    seconds = tonumber(seconds) or 0
    --[[ Written without `mod`: it is a global on the 1.12 client and absent from
         every other Lua this file is ever loaded into, and subtracting the
         hours back off needs no such promise. ]]--
    local hours = floor(seconds / 3600)
    local minutes = floor((seconds - (hours * 3600)) / 60)
    return format("%d:%02d", hours, minutes)
end

--[[ **A full sweep of the house, through aux's own scanner.**

     Deliberately aux's rather than a scanner of our own: aux already walks the
     pages, throttles the queries, parses each row and files it into the price
     history this addon reads back through `Market`. A second scanner would
     record into a second history that nothing consumes.

     The query is empty on purpose -- no name, no category, no level range, no
     page limit -- which is what makes it a sweep rather than a search. ]]--

-- ---------------------------------------------------------------------------
-- favourites
-- ---------------------------------------------------------------------------

--[[ aux keeps its favourites as saved *searches* rather than as items: each one
     is a filter string and the prettified form shown in the list. Everything
     below reads that list rather than keeping a second one, so anything added
     through aux's own interface is a favourite here too. ]]--
local function favouritesModule()
    return OB.modules.auction:AuxSearch()
end

function M:Favourites()
    local search = favouritesModule()
    if not search then return nil end

    local list = search.favorite_searches
    if type(list) ~= "table" then return nil end

    return list
end

--[[ Two favourites for the same search are one favourite typed twice.

     Trimmed and lowercased for the comparison only. aux stores what you typed
     and shows it back, so "Copper Bar" and "copper bar " have to *count* as the
     same entry without either being rewritten into the other. ]]--
local function favouriteKey(text)
    if type(text) ~= "string" then return nil end

    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then return nil end

    return string.lower(text)
end

function M:FavouriteExists(filterString)
    local key = favouriteKey(filterString)
    if not key then return false end

    local list = self:Favourites()
    if not list then return false end

    for i = 1, table.getn(list) do
        if favouriteKey(list[i] and list[i].filter_string) == key then
            return true
        end
    end

    return false
end

--[[ **Installed over aux's own `add_favorite`, once.**

     Nothing in aux stops the same search being added again, so a list built
     over a few sessions ends up with the same item three times and every one of
     them scans separately.

     Wrapped rather than patched in place, for the reason the macro icon fix
     gives at length: a change to somebody else's file is lost the next time
     they update it. ]]--
function M:InstallFavouriteGuard()
    if self.favouriteGuard then return false end

    local search = favouritesModule()
    if not search or type(search.add_favorite) ~= "function" then return false end

    local previous = search.add_favorite

    local wrapper = function(filterString)
        local m = OB.modules.auction

        if m and OB.ModuleEnabled("auction")
                and m:Config().uniqueFavourites
                and m:FavouriteExists(filterString) then
            OB.Print("that is already a favourite.", "Auction")
            return
        end

        return previous(filterString)
    end

    if not self:AuxSet(search, "add_favorite", wrapper) then return false end

    self.favouriteGuard = wrapper
    return true
end

--[[ **What the list is worth right now, and what it usually is.**

     Two different questions and both are asked, because either alone is a trap:
     a price with no history behind it cannot tell you whether it is a bargain,
     and a historical value with no current price cannot tell you whether there
     is one on the auction house at all.

     `nil` for either half is answered as nil rather than as zero. A number
     nobody has data for is not a price of nothing. ]]--
--[==[ **A favourite's item id, from whoever can answer.**

     aux stores a filter string rather than an id, so this is only knowable for
     a favourite that names one item exactly. Anything broader -- a category, a
     level range -- has no single price to quote.

     `aux.util.info.item_id` was the only thing asked, and this build of aux does
     not have it: `util/info.lua` exports `item_key`, `parse_link` and `item`,
     all of which want a link rather than a name. So every favourite resolved to
     nothing and the whole column came out blank.

     Still asked first, because a build that has it is answering from the same
     data aux prices with. ECO's own market lookup behind it, which is the one
     that answers here -- it is the same resolver the tooltip uses to price an
     item somebody typed the name of. ]==]
function M:LabelItemId(label)
    if type(label) ~= "string" or label == "" then return nil end

    local info = auxModule("aux.util.info")

    if info and type(info.item_id) == "function" then
        local ok, id = pcall(info.item_id, label)
        if ok and id then return tonumber(id) end
    end

    local market = OB.Market
    if market and type(market.ItemIdByName) == "function" then
        local ok, id = pcall(market.ItemIdByName, market, label)
        if ok and id then return tonumber(id) end
    end

    --[==[ **And the client itself, which knows every item you have looked at.**

         1.12's `GetItemInfo` takes a name as readily as an id, and answers with
         a link -- which carries the id. It only knows items the client has
         cached, and that is exactly the right limit here: a favourite is a
         search you typed after seeing the thing, so it is cached.

         Last, because it is a lookup by *name* and names are localised and
         shared. The two above answer by identity where they can. ]==]
    if type(GetItemInfo) == "function" then
        local ok, _, link = pcall(GetItemInfo, label)

        if ok and type(link) == "string" then
            local _, _, id = string.find(link, "item:(%d+)")
            if id then return tonumber(id) end
        end
    end

    return nil
end

function M:FavouriteValue(itemId)
    if not itemId then return nil, nil end

    local history = auxModule("aux.core.history")
    if not history then return nil, nil end

    local key = tostring(itemId)
    local current, typical

    if type(history.market_value) == "function" then
        local ok, value = pcall(history.market_value, key)
        if ok then current = value end
    end

    if type(history.value) == "function" then
        local ok, value = pcall(history.value, key)
        if ok then typical = value end
    end

    return current, typical
end

--[[ **What each favourite is worth, printed when the window opens.**

     The point of a favourites list is the question "is any of this worth buying
     today", and answering it meant clicking each one in turn and remembering
     what it used to cost.

     **Current beside historical, never one alone.** A price with no history
     behind it cannot tell you whether it is a bargain, and a historical value
     with none on sale cannot tell you whether there is one to buy. Either half
     missing is said as missing rather than as zero -- a number nobody has data
     for is not a price of nothing.

     Uses aux's own history, which is the same data its tooltips quote, so this
     never disagrees with what the rest of the window says. ]]--
function M:FavouriteLine(entry)
    if not entry then return nil end

    local label = entry.prettified or entry.filter_string
    if not label or label == "" then return nil end

    --[[ aux stores a filter string rather than an item id, so the id is only
         known for a favourite that names one item exactly. Anything broader --
         a category, a level range -- has no single price to quote and is listed
         without one rather than left out: it is still a favourite. ]]--
    local itemId = self:LabelItemId(label)
    if not itemId then return label end

    local current, typical = self:FavouriteValue(itemId)

    if not current and not typical then
        return label .. " -- no prices recorded yet"
    end

    local parts = label .. " -- "

    if current then
        parts = parts .. "now " .. OB.Money(current)
    else
        parts = parts .. "none listed"
    end

    if typical then
        parts = parts .. ", usually " .. OB.Money(typical)
    end

    return parts
end

--[[ **Two columns on the favourites list: what it costs, and what that is
     against its history.**

     aux lists favourites as names and nothing else, so "is any of this worth
     buying today" meant clicking each one in turn and remembering what it used
     to cost. The two numbers that answer it are already in aux's own history --
     they are what its tooltips quote -- so nothing new has to be gathered to
     put them on screen.

     **Per cent of historical value rather than a second money figure.** Two
     amounts side by side still leave the reader doing the division; a
     percentage is the answer to the question they were dividing to get. Under a
     hundred is cheaper than it usually goes for, which is the number somebody
     scanning a list is looking for.

     Done by widening aux's listing from outside rather than by editing it: a
     change to somebody else's file is lost the next time they update it. ]]--
local FAVOURITE_COLUMNS = {
    { name = "Auto", width = 0.06, align = "CENTER" },
    { name = "Favorite Searches", width = 0.62 },
    { name = "price", width = 0.16, align = "RIGHT" },
    { name = "% of hist. value", width = 0.16, align = "RIGHT" },
}

--[[ The percentage, or nothing when either half is missing. A favourite with no
     history has no baseline to be a fraction of, and inventing one -- treating
     "unknown" as a hundred per cent -- would read as "priced exactly normally"
     about an item nobody has ever seen sold. ]]--
function M:FavouritePercent(current, typical)
    if not current or not typical then return nil end
    if typical <= 0 then return nil end

    return OB.Round((current / typical) * 100)
end

--[[ The two cells for one row, as aux's listing wants them: a list of maps with
     a `value`. Colour is the reader's shortcut -- green for cheaper than usual,
     red for dearer -- and the number is still there for anybody who wants it. ]]--
function M:FavouriteCells(search)
    local label = search and (search.prettified or search.filter_string)
    if not label then return "", "" end

    --[[ A favourite that names a category rather than one item has no single
         price to quote, and is listed with empty cells rather than left out.
         It is still a favourite. ]]--
    local itemId = self:LabelItemId(label)
    if not itemId then return "", "" end

    local current, typical = self:FavouriteValue(itemId)
    if not current then return "", "" end

    local price = OB.Money(current)
    local percent = self:FavouritePercent(current, typical)

    if not percent then return price, "" end

    local colour = "|cffabd473"
    if percent > 100 then colour = "|cffff5555" end

    return price, colour .. percent .. "%|r"
end

--[[ **Installed over aux's listing, once, from outside.**

     Two things have to change together: the listing needs four columns instead
     of two, and every row handed to it needs two more cells. Doing one without
     the other gives either headings with nothing under them or cells with
     nowhere to go.

     `SetData` is wrapped rather than `update_search_listings`, because that
     function builds its rows and hands them straight over -- intercepting the
     data is one place to stand instead of rebuilding what it just made. ]]--
function M:InstallFavouriteColumns()
    if self.favouriteColumns then return false end

    local search = self:AuxSearch()
    if not search then return false end

    local listing = search.favorite_searches_listing
    if not listing or type(listing.SetData) ~= "function" then return false end
    if type(listing.SetColInfo) ~= "function" then return false end

    local ok = pcall(listing.SetColInfo, listing, FAVOURITE_COLUMNS)
    if not ok then return false end

    local previous = listing.SetData

    local wrapper = function(self2, rows)
        local m = OB.modules.auction

        if m and OB.ModuleEnabled("auction") and type(rows) == "table" then
            for i = 1, table.getn(rows) do
                local row = rows[i]

                --[[ Guarded row by row. aux's listing is handed rows from more
                     than one place, and a shape this does not recognise is left
                     exactly as it came rather than being repaired into
                     something it might not be. ]]--
                if type(row) == "table" and type(row.cols) == "table"
                        and table.getn(row.cols) == 2 then
                    local price, percent = m:FavouriteCells(row.search)

                    table.insert(row.cols, { value = price })
                    table.insert(row.cols, { value = percent })
                end
            end
        end

        return previous(self2, rows)
    end

    listing.SetData = wrapper
    self.favouriteColumns = wrapper

    return true
end

function M:ReportFavourites()
    if not OB.ModuleEnabled("auction") then return false end

    local list = self:Favourites()
    if not list or table.getn(list) == 0 then return false end

    OB.Print("favourites:", "Auction")

    local said = 0

    for i = 1, table.getn(list) do
        local line = self:FavouriteLine(list[i])

        if line then
            OB.Raw("   " .. line)
            said = said + 1
        end
    end

    return said > 0
end

--[[ **Whether a purchase is in flight.**

     aux locks itself while a bid is outstanding and exposes the fact, so this
     is asked rather than inferred: `aux.bid_in_progress()` is true from the
     moment `PlaceAuctionBid` is called until the server confirms, or five
     seconds pass without an answer.

     Guarded like everything else that reaches into a neighbour -- an aux that
     is missing, older, or renamed answers "not buying" rather than throwing. ]]--
function M:BuyInProgress()
    local aux = auxModule("aux")
    if not aux or type(aux.bid_in_progress) ~= "function" then return false end

    local ok, busy = pcall(aux.bid_in_progress)
    if not ok then return false end

    return busy and true or false
end

function M:StartScan(manual)
    if not OB.ModuleEnabled("auction") then return false end

    local scan = auxModule("aux.core.scan")
    if not scan or type(scan.start) ~= "function" then return false end

    --[[ The client will not answer a query with the auction house closed, so a
         scan started from anywhere else is a scan that silently does nothing. ]]--
    if type(AuctionFrame) ~= "table" or not AuctionFrame.IsShown
            or not AuctionFrame:IsShown() then
        if manual then
            OB.Print("the auction house has to be open to scan it.", "Auction")
        end
        return false
    end

    --[[ Asked by hand overrides the clock. Somebody who has just clicked Scan
         Now has said what they want more clearly than the interval has. ]]--
    if not manual and self:ScanWait() > 0 then return false end

    --[[ One at a time. Starting a second sweep on top of the first aborts the
         first inside aux and leaves this module thinking both are running. ]]--
    if self.scanning then
        if manual then
            OB.Print("a scan is already running.", "Auction")
        end
        return false
    end


    --[[ **Never while a purchase is in flight.**

         A sweep is hundreds of queries. Starting one on top of somebody buying
         is the addon competing with the player for the same throttle, and what
         it looks like from the outside is the auction house scanning again
         every time you buy something.

         Applies to a manual scan too, and says so, because a sweep started by
         hand at that exact moment is still the wrong moment. ]]--
    if self:BuyInProgress() then
        if manual then
            local message = "not while you are buying -- try again once the "
                    .. "purchase has gone through."
            OB.Print(message, "Auction")
        end
        return false
    end
    if self:Config().autoScanNotify or manual then
        OB.Print("scanning the auction house.", "Auction")
    end

    --[[ Noted before rather than after. A sweep is hundreds of queries and can
         be interrupted by closing the window; recording it only on completion
         would mean an interrupted scan restarts from scratch every time the
         window opens, which is worse for the realm than missing one. ]]--
    self:NoteScan()

    --[[ Remembered so nothing starts a second one on top of the first, and so
         `on_abort` can say the sweep is over rather than leaving it looking
         like it is still running for ever. ]]--
    self.scanning = true

    --[[ Marked around our own call so the watcher below does not mistake this
         sweep for the player and stand it down from itself. ]]--
    self.startingOwnScan = true

    scan.start({
        type = "list",
        queries = { { blizzard_query = {} } },
        on_scan_start = function() end,

        on_abort = function()
            local m = EquadisClassicOverhaul.modules.auction
            if m then m.scanning = nil end
        end,

        on_complete = function()
            local m = EquadisClassicOverhaul.modules.auction
            if not m then return end

            m.scanning = nil
            if m:Config().autoScanNotify then
                OB.Print("auction house scan complete.", "Auction")
            end
        end,
    })

    --[[ Cleared the moment our own call has been made. Anything that starts a
         scan after this point is the player, and the sweep stands down for
         them. ]]--
    self.startingOwnScan = nil

    return true
end

--[[ **A sweep must get out of the way of the person using the auction house.**

     A full sweep is a few hundred queries and takes minutes. aux runs one scan
     of each type at a time, so while the sweep is going the searches and
     purchases you make are queued behind it or abort it -- and buying a dozen
     things quickly turns into a window that appears to be permanently scanning,
     because it is.

     So anything that starts a scan ECO did not start is taken as the player
     doing something, and the sweep stands down. Their scan is what they asked
     for; the sweep is what this module thought would be useful, and that is not
     a contest.

     Wrapped rather than polled, because there is no "is aux scanning" to ask --
     `scan_states` is a local inside aux's own module. The wrapper is installed
     once and reaches this module through the global namespace, for the same
     reason every other wrapper in this addon does: `core.lua` assigns a fresh
     namespace on each load and the wrapper outlives it. ]]--
function M:InstallScanWatch()
    if EquadisOverhaulAuxScanStart then return false end

    local scan = auxModule("aux.core.scan")
    if not scan or type(scan.start) ~= "function" then return false end

    --[[ The module itself rather than the interface `require` handed back.
         Writing to the interface is discarded, which is what had happened
         here: the watcher read as installed and was never in the path. ]]--
    local env = self:AuxModuleEnv("aux.core.scan", "start") or scan
    local original = scan.start

    local wrapper = function(params)
        local m = EquadisClassicOverhaul
                and EquadisClassicOverhaul.modules
                and EquadisClassicOverhaul.modules.auction

        --[[ `startingOwnScan` is set around this module's own call, so the
             sweep is not mistaken for the player and made to stand down from
             itself the moment it begins. ]]--
        if m and m.scanning and not m.startingOwnScan then
            m.scanning = nil

            if m:Config().autoScanNotify then
                OB.Print("stopping the sweep -- you are using the auction house.",
                        "Auction")
            end
        end

        return original(params)
    end

    if not self:AuxSet(env, "start", wrapper) then return false end

    --[[ Set only once the wrapper is really in place. This global is the
         "already installed" flag, and setting it on a write that went nowhere
         would make every later attempt give up as well. ]]--
    EquadisOverhaulAuxScanStart = original
    return true
end

-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

function M:OnEvent()
    --[[ **Closing the window ends any sweep, whether or not aux said so.**

         The client will not answer a query with the auction house shut, so a
         sweep cannot survive this either way -- and aux aborts its scans on
         `CLOSE` without necessarily reaching our `on_abort`. Without this the
         flag would stay set for the session and every later scan would be
         refused as "already running", which is the worst kind of stuck: silent,
         and it looks like the feature simply stopped working. ]]--
    if event == "AUCTION_HOUSE_CLOSED" then
        self.scanning = nil
        return
    end

    if event ~= "AUCTION_HOUSE_SHOW" then return end

    --[[ Styled first, because the window has just been built and this is the
         moment it exists. ]]--
    self:ApplySkin()

    --[[ The favourites first, because it is cheap, it is the question the
         window was opened to answer, and a sweep may not run at all. ]]--
    --[[ Tried here as well as at bind: aux builds its window the first time
         the auction house opens, so at bind there is no listing to widen. The
         install refuses to run twice. ]]--
    self:InstallFavouriteColumns()

    if self:Config().scanFavourites then self:ReportFavourites() end

    if self:Config().autoScan then self:StartScan(false) end
end

function M:OnBind()
    --[[ aux may already have built its window before this module was switched
         on, in which case there is something to style right now. ]]--
    self:ApplySkin()

    --[[ The watcher that makes the sweep stand aside for whatever the player is
         doing. Installed once and outlives the binding by design, like every
         other wrapper here. ]]--
    self:InstallScanWatch()
    self:InstallFavouriteGuard()
    self:InstallFavouriteColumns()
end

function M:OnStyle()
    self:ApplySkin()
end

function M:OnUnbind() end
function M:OnDraw() end
