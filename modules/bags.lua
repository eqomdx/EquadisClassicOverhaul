--[[ Equadis' Classic Overhaul :: bags

  **Bagnon, rebuilt for 1.12.**

  This window was ours and it was wrong in ways that were not going to be fixed
  one report at a time: chrome that came out blurry, items in an order nobody
  asked for, a sort button that rearranged a picture of the bags rather than the
  bags. The instruction was to throw the settings away and take Bagnon's, which
  is the right call. Bagnon has had twenty years of people telling it what a bag
  window should do, and no amount of taste here beats that.

  **The addon itself cannot be run.** Bagnon 10.2.21 declares `Interface 11501`
  -- Classic Era -- and its first line is `local ADDON, Addon = ...`, a
  file-level vararg that a Lua 5.0 client cannot parse at all. Under that sit
  LibStub, WildAddon, Poncho, Sushi, AceEvent, C_Everywhere, `hooksecurefunc`,
  `SettingsPanel`, and a `GetContainerItemInfo` that answers a table. So this is
  a port rather than an import: the layout arithmetic, the defaults, the sort
  rule and the slot artwork are Bagnon's, copied off its source and named after
  it, driven by the scanning and storage this module already had.

  **The three things that make it Bagnon.**

  *The grid is a picture of your bags.* One button per slot, every slot, in bag
  order, empty ones included. Nothing is regrouped on screen. That is the whole
  reason its sort button is trusted and ours was not -- pressing sort moves the
  items, so what you were looking at is what changed. Ours sorted the bags into
  one order and drew them in another, and the difference read as a bug because
  it was one.

  *Search dims, it does not filter.* Non-matches drop to a third alpha and stay
  where they are, so the shape of the bag somebody knows does not rearrange
  itself under a typo.

  *Quality is a glow, not a border.* `UI-ActionButton-Border` at 67 pixels,
  additive, centred on a 37 pixel slot, at half alpha. Bagnon's numbers exactly.

  Kept from before, because Bagnon has both and 1.12 gives neither for free:
  favourites that cannot be sold or traded, and the remembered bank and alt
  bags.
]]--

local OB = EquadisClassicOverhaul
local floor = math.floor
local function Say(msg) OB.Print(msg, "Bags") end

--[[ The backpack and four bags, which is every bag 1.12 has. Zero is the
     backpack and is always there; one to four may be empty. ]]--
local FIRST_BAG, LAST_BAG = 0, 4

--[==[ **Which containers each view is made of.**

     The client numbers them awkwardly and the numbers are the only thing that
     says what a container is: the backpack is 0 and your four bags are 1 to 4,
     the bank is -1 with its own bags at 5 to 10, and the keyring is -2. Nothing
     about -2 says "keys"; it is simply the id that answers with keys in it.

     **The keyring stays its own view**, which is where this parts company with
     Bagnon. Bagnon folds `KEYRING_CONTAINER` into the inventory grid as one
     more bag -- but its sorter checks `GetItemFamily` before every move, and a
     key dropped at a normal slot is a move that silently fails. Sorting would
     stall on the first key. The family guard is ported below; the keyring is
     left out of the grid until it has been seen to work. ]==]
local VIEW_BAGS = { 0, 1, 2, 3, 4 }
local VIEW_BANK = { -1, 5, 6, 7, 8, 9, 10 }
local VIEW_KEYRING = { -2 }

--[==[ **Bagnon's numbers, off its source rather than guessed.**

     `frame.lua` starts a window at 44 by 36 and grows it, places the first menu
     button at 8, -8 and steps 4 between them; `itemGroup.lua` pitches slots at
     `37 + spacing`; `bagGroup.lua` steps bag buttons 36 apart and `bag.lua`
     draws them 32 square; the window finishes at `max(width, 156) + 16`.

     Copied rather than approximated. A layout that is nearly Bagnon's is a
     layout nobody recognises, and the point of this rewrite is recognition. ]==]
local ITEM = 37
local MENU = 20
local MENU_GAP = 4
local EDGE = 8
local ROW_GAP = 4
--[==[ **Half of Bagnon's thirty-two**, because the strip is a control surface
     and not part of the view: it toggles a bag out of the grid and takes a
     dropped bag, and at thirty-two it was a second row of item-sized squares
     saying nothing the grid under it did not already say. At sixteen it reads
     as what it is. Stepped two apart, the way the buttons above the grid are. ]==]
local BAG_BUTTON = 16
local BAG_PITCH = 18

--[[ The row under the grid holds the strip on the left and the money on the
     right, and is as tall as the taller of the two. ]]--
local FOOT_GAP = 4
local BASE_W, BASE_H = 44, 36
local MIN_BODY = 156
local FRAME_PAD = 16
local MONEY_H = 24
local MONEY_W = 140
local MONEY_GAP = 8
local SEARCH_H = 28

--[[ The least the always-open search box is allowed to be: enough for a word,
     which is what people type into one. The row widens the window by this much
     so the box exists even over the narrowest grid. ]]--
local SEARCH_MIN_W = 90

--[==[ ~~The quality glow~~ **is not this module's any more.**

     It was Bagnon's -- `UI-ActionButton-Border`, additive, 67 over a 37 pixel
     button -- and then it was Bagnon's at the paper doll's ratio, because the
     character sheet's borders were the ones that looked right. That was a copy
     of the *numbers*, with switches of its own beside them, and two copies of a
     look drift the moment either is touched: the bag had `glowQuality`,
     `glowAlpha` and `rarityRing`; the character panel had `rarityBorders`,
     `borderGlow` and `borderGlowAlpha`; and nothing kept them in step.

     So the bag no longer draws rarity at all. It hands each slot to
     `qol:PaintRarity` -- the one implementation the paper doll, the inspect
     window, the bank and the loot roll already go through -- and the character
     panel's settings govern every item slot in the interface. One look, one
     page, and a bag square is the same square as a paper doll slot because it
     is painted by the same code. ]==]

--[==[ **The ring around a slot is the client's own, and it is turned down.**

     A slot had no ring at all: the icon was drawn across the whole button, edge
     to edge, so every square was picture and nothing else -- which is what "the
     icons are too big" is. The client's own item buttons draw `UI-Quickslot2`
     over the icon's edges, which is where the raised square somebody recognises
     comes from and why an icon in the game looks smaller than the slot holding
     it.

     At full white that ring is polished chrome. `slotShine` multiplies it down
     -- `SetVertexColor` is a multiply, so white is the untouched art -- and it is
     a setting because how bright a rim wants to be depends on the background
     behind it. ]==]
local SLOT_RING = "Interface\\Buttons\\UI-Quickslot2"

--[[ `Item.Backgrounds[2]`: the paperdoll's empty backpack slot, which is what
     a slot with nothing in it looks like everywhere else in a 1.12 interface.
     Bagnon's other option is a retail-only texture, so this is the only one. ]]--
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local EMPTY_BAG = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
local BACKPACK = "Interface\\Buttons\\Button-Backpack-Up"

--[==[ **The menu row, in Bagnon's order.**

     `Frame:PlaceMenuButtons` builds it left to right as owner selector, then
     whatever the frame adds, then sort, then search. Ours adds the two views
     1.12 needs and Bagnon reaches by other means: the bank, which Bagnon opens
     as a second window, and the keyring, which it folds into the grid.

     Icons are the ones shipped for this window plus the two Bagnon names
     outright -- `INV_Misc_Bag_08` for the bag toggle, which is the icon id its
     template loads, and the spyglass for search.

     The broom rather than the sort glyph on the sort button, because this
     button now does what Bagnon's does: stack loose piles *and* order them.
     Two buttons for one operation was ours, not Bagnon's. ]==]
--[==[ **`bagBreak` is three answers, not a number between two of them.**

     Bagnon's config draws it as a dropdown and it stores nought, one or two --
     none of which is "more break" than the one before it in any sense a slider
     would imply. A slider here would ask somebody to learn that two means every
     bag while one means only where the kind changes.

     An enum list keeps the stored values Bagnon's -- so the migration and the
     grid walk both stay literal transcriptions -- and puts the words on the
     panel. ]==]
local BAG_BREAK = {
    enum = true,
    values = { 0, 1, 2 },
    labels = { "Never", "Where the kind of bag changes", "At every bag" },
}

local MENU_BUTTONS = {
    { key = "players", kind = "view", label = "Other Characters",
      icon = OB.mediaPath .. "textures\\icons\\bag_player",
      tip = "What your other characters are carrying" },

    { key = "bank", kind = "view", label = "Bank",
      icon = OB.mediaPath .. "textures\\icons\\bag_bank",
      tip = "Your bank, from the last time you opened it" },

    { key = "keyring", kind = "view", label = "Keyring",
      icon = OB.mediaPath .. "textures\\icons\\bag_key",
      tip = "Your keyring" },

    { key = "sort", kind = "action", label = "Clean Up",
      icon = OB.mediaPath .. "textures\\icons\\bag_clean",
      tip = "Stack loose piles together and put everything in order" },

    { key = "mark", kind = "toggle", label = "Mark Items",
      icon = OB.mediaPath .. "textures\\icons\\lock",
      tip = "Click items to mark them as keepers. They cannot be sold or "
            .. "traded while marked." },
}

--[==[ ~~bagToggle~~ ~~search~~ **are gone from the row.**

     The bags you are wearing are always shown now, under the grid on the left
     where the money is on the right -- so a button to show them is a button to
     hide a thing nobody asked to hide. And the search box is always open, the
     way the chat's edit box is: a box that is there costs one strip of window,
     and a button to summon it costs a click every time and a place to keep the
     button. Asked for in exactly those terms. ]==]

local M = OB.RegisterModule({
    id = "bags",
    name = "Bags",
    feature = true,
    renders = "none",
    defaultEnabled = true,

    --[[ The Border row, under Appearance, from the same four every other
         window offers. `OB.Look("bags").border` is what `Draw` reads. ]]--
    styled = { border = true },
    appearanceSection = "look",

--[==[ **Bagnon's defaults, transcribed.**

         `core/api/settings.lua` holds them: `FrameDefaults` for everything a
         window has, then an `inventory` profile that overrides four of them.
         Ten columns, slots pitched two apart, item scale one, no break between
         bags, the bag strip hidden, a half-black backdrop behind a white
         border, and the glow at half alpha.

         The old table is gone rather than migrated. Every one of its settings
         described a window that no longer exists -- backpack artwork, grouping,
         hidden empties -- and carrying a stale value forward into a layout that
         never reads it is how a settings page fills up with switches that do
         nothing. `config.lua`'s migration 35 clears what was stored. ]==]
    defaults = {
        --[[ Bagnon inventory: ten. Its bank window uses fourteen, which is the
             second number here rather than a second profile. ]]--
        columns = 10,
        bankColumns = 14,

        --[[ `itemScale` and `spacing`, both `FrameDefaults`. The pitch is
             `37 + spacing`, so two gives 39. ]]--
        itemScale = 1,
        spacing = 2,

        --[[ `bagBreak`: nought runs the bags together, one starts a fresh row
             when the kind of bag changes -- a quiver after a normal bag -- and
             two gives every bag its own row. Bagnon ships nought. ]]--
        bagBreak = 0,

        reverseBags = false,
        reverseSlots = false,

        --[==[ ~~showBags~~ ~~bagToggle~~ ~~search~~ ~~borderColor~~ **are
             retired.** The keys stay so a profile carrying them does not error,
             and a stored value is **ignored rather than obeyed**: the strip is
             always shown, the search box is always open, and the border is a
             style from the Appearance block rather than a colour. ]==]
        showBags = false,
        hiddenBags = {},
        bagToggle = true,
        search = true,

        --[[ The two things the top row can still carry, both on. ]]--
        sort = true,
        money = true,

        --[[ `color` from the inventory profile: half-opaque black. The edge is
             `border` -- see the Appearance block -- and ships as Thin, which is
             the flat line this window wore before it was a choice. ]]--
        color = { 0, 0, 0, 0.5 },
        borderColor = { 1, 1, 1, 1 },
        border = 2,

        --[==[ ~~glowQuality~~ ~~glowAlpha~~ ~~rarityRing~~ **are retired**: the
             bag's rarity colouring is the character panel's now, drawn by the
             same code under that page's `Colored Item Borders`, `Glow` and `Glow
             Strength`. The keys stay so a profile carrying them does not error,
             and a stored value is **ignored rather than obeyed** -- honouring a
             saved `rarityRing = false` here would be one bag disagreeing with
             every other item slot on screen, with no row left to say why.

             `glowPoor` stays. It is the junk marker, which is a fact about a
             bag and not about rarity, and the paper doll has no junk. ]==]
        glowQuality = true,
        glowAlpha = 0.55,
        rarityRing = true,
        glowPoor = true,

        --[[ How far the icon sits inside the ring, and how bright the ring is.
             Both are about the same square and both were fixed numbers that
             turned out to be wrong ones. Nought since the ring is sized the way
             the client sizes it -- the rim lands on the icon's edge, and any
             inset is a dark band inside it. ]]--
        iconInset = 0,
        slotShine = 0.65,

        --[[ `slotBackground`, which in Bagnon picks between two textures. There
             is one on 1.12, so it is on or off. ]]--
        slotBackground = true,

        --[==[ Ours, kept: the guard on selling or trading a favourite. Bagnon
             has no equivalent because retail has an undo and 1.12 does not.

             **No switch**, because marking an item a favourite is already the
             switch. Off meant the mark stopped meaning the one thing it was for,
             while still looking exactly as though it did -- and the cost of
             being wrong is an item that no longer exists. ]==]
    },

    options = {
        { "Layout", "__s_layout", "section", "layout" },
        { "Columns", "columns", "slider", 4, 24, 1 },
        { "Bank Columns", "bankColumns", "slider", 4, 24, 1 },
        { "Item Scale", "itemScale", "slider", 50, 150, 5, 0.01 },
        { "Slot Spacing", "spacing", "slider", 0, 12, 1 },
        { "Start A New Row", "bagBreak", BAG_BREAK },
        { "Reverse Bag Order", "reverseBags", "boolean" },
        { "Reverse Slot Order", "reverseSlots", "boolean" },

        { "Appearance", "__s_look", "section", "look" },
        { "Background", "color", "color", true },
        --[[ The Border row is the Appearance block's, generated from `styled`:
             None, Thin, Classic, Blizzard -- the same four every other window
             offers, rather than a colour picker for a line. ]]--
        { "Empty Slot Artwork", "slotBackground", "boolean" },
        --[[ The three rarity rows that were here are on the Character Panel
             page now, and govern this window too. See the note by the
             defaults. ]]--
        { "Slot Ring Brightness", "slotShine", "slider", 20, 100, 5, 0.01 },
        { "Icon Inset", "iconInset", "slider", 0, 6, 1 },
        { "Mark Junk", "glowPoor", "boolean" },

        { "Top Row", "__s_row", "section", "row" },
        { "Clean Up Button", "sort", "boolean" },
        { "Show Money", "money", "boolean" },

        --[[ **Protection has gone with the row it held.** One section for one
             switch, and the switch is now the favourite mark itself -- see the
             note on `protect` in the defaults. ]]--
    },

    events = { "BAG_UPDATE", "PLAYER_ENTERING_WORLD", "ITEM_LOCK_CHANGED",
               "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_MONEY" },

    --[[ The container calls this module cannot work without. Every one is behind
         a `type(...) == "function"` guard, which is what makes naming them here
         the difference between a silent no-op and a line in the self test. ]]--
    requires = { "GetContainerNumSlots", "GetContainerItemInfo",
                 "GetContainerItemLink", "PickupContainerItem", "UseContainerItem" },
})

function M:Config()
    return OB.profile.modules.bags
end

-- ---------------------------------------------------------------------------
-- what is a favourite
-- ---------------------------------------------------------------------------

--[[ Account-wide rather than per-profile: see the header. Read through here
     rather than reached into, so the seeding happens in one place. ]]--
function M:Favourites()
    EquadisClassicOverhaulDB.favourites = EquadisClassicOverhaulDB.favourites or {}
    return EquadisClassicOverhaulDB.favourites
end

--[[ **The item id out of a link**, which is the only stable name an item has.

     Item *names* are localised and two items can share one; the id cannot. The
     link is the client's own and always carries it in the same place. ]]--
function M:ItemIdFromLink(link)
    if type(link) ~= "string" then return nil end
    local _, _, id = string.find(link, "|Hitem:(%d+)")
    return tonumber(id)
end

function M:IsFavourite(itemId)
    if not itemId then return false end
    return self:Favourites()[itemId] and true or false
end

function M:SetFavourite(itemId, on)
    if not itemId then return false end
    self:Favourites()[itemId] = on and true or nil
    return true
end

function M:ToggleFavourite(itemId)
    if not itemId then return false end
    local now = not self:IsFavourite(itemId)
    self:SetFavourite(itemId, now)
    self:Refresh()
    return now
end

--[==[ **Pinning an item to a square is gone with the grid that had squares.**

     It meant "this item always draws here", which was only expressible while
     the window was arranging items itself. The grid is a picture of the bags
     now: a position *is* a bag and a slot, and the thing that keeps an item in
     one is the thing that stops the sorter moving it.

     Bagnon spells that `lockedSlots` and reaches it through a configuration
     mode. Here it is already spelled: a favourite is never moved by the clean
     up, which is the same guarantee with a mark somebody can see. ]==]

-- ---------------------------------------------------------------------------
-- refusing to sell or trade one
-- ---------------------------------------------------------------------------

--[[ **Is something open that would take the item away?**

     Selling and trading are the two ways an item leaves the bag by a single
     click, and both are answered by a window being visible. Nothing here knows
     what a merchant *is* -- it asks whether the frame is up. ]]--
function M:LosingWindowOpen()
    if MerchantFrame and MerchantFrame.IsVisible and MerchantFrame:IsVisible() then
        return "sold"
    end
    if TradeFrame and TradeFrame.IsVisible and TradeFrame:IsVisible() then
        return "traded"
    end
    return nil
end

function M:WouldLose(bag, slot)

    local where = self:LosingWindowOpen()
    if not where then return nil end

    if type(GetContainerItemLink) ~= "function" then return nil end
    local id = self:ItemIdFromLink(GetContainerItemLink(bag, slot))
    if not id or not self:IsFavourite(id) then return nil end

    return where, id
end

--[[ **Refused rather than warned.**

     The case this exists for is a bag of greys being cleared at a vendor with
     one finger on the mouse; a warning that arrives after the click is a receipt
     rather than a guard. So the call does not reach the client at all.

     Wrapped rather than replaced, and recognised through a global so a reload
     cannot stack this on top of an earlier copy of itself -- the same trap the
     roster's `ShowUIPanel` wrapper fell into, where the guard lived on a table
     that is rebuilt and the wrapper on a frame that is not. ]]--
function M:InstallProtection()
    if type(UseContainerItem) ~= "function" then return false end
    if UseContainerItem == EquadisOverhaulUseContainerItem then return false end

    local original = UseContainerItem
    if UseContainerItem == EquadisOverhaulUseContainerItem then
        original = EquadisOverhaulUseContainerItemInner
    end

    EquadisOverhaulUseContainerItemInner = original

    EquadisOverhaulUseContainerItem = function(bag, slot, onSelf)
        local mine = EquadisClassicOverhaul.modules.bags

        if mine and EquadisClassicOverhaul.ModuleEnabled("bags") then
            local where, id = mine:WouldLose(bag, slot)
            if where then
                mine:RefusedMessage(where, id)
                return
            end
        end

        return original(bag, slot, onSelf)
    end

    UseContainerItem = EquadisOverhaulUseContainerItem

    --[[ Picking an item up is how it reaches a trade window, so the same
         question is asked there. Refusing the pickup is refusing the trade
         without needing to know anything about trading. ]]--
    if type(PickupContainerItem) == "function"
            and PickupContainerItem ~= EquadisOverhaulPickupContainerItem then
        local pickup = PickupContainerItem
        EquadisOverhaulPickupContainerItemInner = pickup

        EquadisOverhaulPickupContainerItem = function(bag, slot)
            local mine = EquadisClassicOverhaul.modules.bags

            if mine and EquadisClassicOverhaul.ModuleEnabled("bags") then
                local where, id = mine:WouldLose(bag, slot)
                if where then
                    mine:RefusedMessage(where, id)
                    return
                end
            end

            return pickup(bag, slot)
        end

        PickupContainerItem = EquadisOverhaulPickupContainerItem
    end

    return true
end

--[[ Said once per item rather than once per click, because a refused sweep at a
     vendor is one click per item and would otherwise be a wall of the same
     line. ]]--
function M:RefusedMessage(where, id)
    self.lastRefused = self.lastRefused or {}

    local now = type(GetTime) == "function" and GetTime() or 0
    if self.lastRefused[id] and (now - self.lastRefused[id]) < 2 then return false end
    self.lastRefused[id] = now

    Say("that one is a favourite -- it will not be " .. where
            .. ". Unmark it in the bag window first.")
    return true
end

-- ---------------------------------------------------------------------------
-- reading the bags
-- ---------------------------------------------------------------------------

--[[ Every slot in every bag, in bag order. The unified grid is this list placed
     into squares, so the order here is the order on screen before pinning moves
     anything. ]]--
--[==[ **Which view is on screen.** Bags to begin with, because that is what
     the window is for; the other three are somewhere you go and come back
     from. ]==]
function M:View()
    return self.view or "bags"
end

function M:SetView(view)
    self.view = view or "bags"

    --[[ The search survives the switch. Looking for a reagent and then checking
         the bank for it is one question, not two. ]]--
    self:Draw()
    return true
end

--[==[ **Read-only away from the container.**

     A bank can only be read while its frame is open -- the client simply does
     not answer for containers you are not standing at. So what is drawn in the
     Bank view is the last thing seen there, kept in the account-wide database,
     and that is worth being honest about: the window says when it was taken. ]==]
function M:Store()
    EquadisClassicOverhaulDB = EquadisClassicOverhaulDB or {}
    local db = EquadisClassicOverhaulDB

    db.inventory = db.inventory or {}

    local me = OB.CharacterKey and OB.CharacterKey() or "Unknown"
    db.inventory[me] = db.inventory[me] or {}

    return db.inventory, me
end

function M:ScanRange(bags)
    local out = {}
    if type(GetContainerNumSlots) ~= "function" then return out end

    for i = 1, table.getn(bags) do
        local bag = bags[i]
        local slots = GetContainerNumSlots(bag) or 0

        for slot = 1, slots do
            local link = type(GetContainerItemLink) == "function"
                    and GetContainerItemLink(bag, slot) or nil
            local texture, count = nil, nil

            if type(GetContainerItemInfo) == "function" then
                texture, count = GetContainerItemInfo(bag, slot)
            end

            table.insert(out, {
                bag = bag,
                slot = slot,
                link = link,
                id = self:ItemIdFromLink(link),
                texture = texture,
                count = count or 1,
                empty = link == nil,
            })
        end
    end

    return out
end

function M:ScanBags()
    return self:ScanRange(VIEW_BAGS)
end

function M:ScanKeyring()
    return self:ScanRange(VIEW_KEYRING)
end

--[==[ Remembered whenever the bank is open, so the view has something to show
     the rest of the time. Only the parts a window needs -- a texture, a count
     and a link -- because this is written to disk and the rest is rebuildable
     from the link. ]==]
function M:RememberBank()
    local rows = self:ScanRange(VIEW_BANK)
    local inventory, me = self:Store()

    local kept = {}

    for i = 1, table.getn(rows) do
        local row = rows[i]

        if not row.empty then
            table.insert(kept, {
                link = row.link, texture = row.texture, count = row.count,
            })
        end
    end

    inventory[me].bank = kept
    inventory[me].bankSeen = time and time() or nil
    inventory[me].slots = table.getn(rows)

    return kept
end

--[==[ The same for the bags, so another character can be looked at. Recorded on
     every bag change rather than at logout: a client that crashes still leaves
     the last thing it knew, and there is no logout event worth trusting. ]==]
function M:RememberBags()
    local rows = self:ScanBags()
    local inventory, me = self:Store()

    local kept = {}

    for i = 1, table.getn(rows) do
        local row = rows[i]

        if not row.empty then
            table.insert(kept, {
                link = row.link, texture = row.texture, count = row.count,
            })
        end
    end

    inventory[me].bags = kept
    inventory[me].money = (type(GetMoney) == "function") and GetMoney() or nil
    inventory[me].bagsSeen = time and time() or nil

    return kept
end

--[==[ **Everybody except whoever is playing.**

     The Alts view answers "which of my characters has the thing", so the one
     you could simply look in your own bags for is not on the list. ]==]
function M:OtherCharacters()
    local inventory, me = self:Store()
    local out = {}

    for key, record in pairs(inventory) do
        if key ~= me then
            table.insert(out, { key = key, record = record })
        end
    end

    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end

--[==[ Remembered rows are not live slots: there is no bag and slot behind them,
     because the container they came from is not open and may be on a different
     continent. Shaped like live rows so the grid does not have to know the
     difference, and flagged `stored` so the click handlers do. ]==]
function M:StoredRows(list, owner)
    local out = {}

    for i = 1, table.getn(list or {}) do
        local row = list[i]

        table.insert(out, {
            link = row.link,
            id = self:ItemIdFromLink(row.link),
            texture = row.texture,
            count = row.count or 1,
            empty = false,
            stored = true,
            owner = owner,
        })
    end

    return out
end

--[==[ What the grid draws, whichever view is on. ]==]
function M:ScanView()
    local view = self:View()

    if view == "keyring" then return self:ScanKeyring() end

    if view == "bank" then
        --[[ Live while you are standing at it, remembered otherwise. Standing at
             the bank and seeing yesterday's contents would be the one moment
             this view is wrong. ]]--
        if self.bankOpen then return self:ScanRange(VIEW_BANK) end

        local inventory, me = self:Store()
        return self:StoredRows(inventory[me].bank, me)
    end

    if view == "players" then
        local out = {}
        local others = self:OtherCharacters()

        for i = 1, table.getn(others) do
            local entry = others[i]
            local rows = self:StoredRows(entry.record.bags, entry.key)

            for r = 1, table.getn(rows) do table.insert(out, rows[r]) end
        end

        return out
    end

    return self:ScanBags()
end

local function itemName(link)
    if type(link) ~= "string" then return nil end
    local _, _, name = string.find(link, "%[(.-)%]")
    return name
end

-- ---------------------------------------------------------------------------
-- the grid
-- ---------------------------------------------------------------------------

--[==[ **A picture of the bags, and nothing else.**

     `ItemGroup:Layout` walks the bags in order, each bag's slots in order, and
     drops one button per slot into a grid `columns` wide. There is no sorting
     here, no grouping, no filtering: what is on screen is where things are.

     That is the whole difference between this and what was here before. Ours
     bucketed items by type and ordered each bucket, which meant the grid and
     the bags disagreed -- so the sort button moved things and the window did
     not change the way you expected, and it read as broken because from where
     the reader sits it *was* broken. A window that lies about where things are
     cannot have a sort button that anybody trusts.

     Everything that used to happen here happens in the bags now. ]==]

--[[ The scan arrives flat, one row per slot in bag order. The grid walk needs
     the bag boundaries back, because a break and a reversal are both about
     bags rather than about slots. ]]--
function M:BagBuckets(rows)
    local order, byBag = {}, {}

    for i = 1, table.getn(rows) do
        local row = rows[i]
        local bag = row.bag
        if bag == nil then bag = "stored" end

        if not byBag[bag] then
            byBag[bag] = {}
            table.insert(order, bag)
        end

        table.insert(byBag[bag], row)
    end

    return order, byBag
end

--[==[ **What kind of bag this is**, which is what a row break is measured
     against and what the sorter checks before it moves anything.

     `GetItemFamily` answers a bitmask -- quiver, soul bag, herb bag -- and zero
     for an ordinary one. The backpack has no equipment slot behind it and is
     always ordinary. Zero wherever the client cannot say, which is the safe way
     to be wrong: an unknown bag is treated as a normal one, so nothing is
     refused a move it could have made. ]==]
--[[ The kinds of special bag 1.12 has, as flags, keyed by the subtype string
     `GetItemInfo` answers for the bag itself. `GetItemFamily` does not exist
     on a 1.12 client -- it arrived two expansions later -- so the family has to
     be read off the item's own type. The flags are this file's own; they only
     have to agree between a bag and what goes in it. ]]--
local BAG_KINDS = {
    ["Quiver"] = 1,
    ["Ammo Pouch"] = 2,
    ["Soul Bag"] = 4,
    ["Herb Bag"] = 8,
    ["Enchanting Bag"] = 16,
    ["Engineering Bag"] = 32,
}

--[[ And what an item is allowed into, by its type and subtype. Anything not
     listed is an ordinary item and fits an ordinary bag only. ]]--
local ITEM_KINDS = {
    ["Projectile/Arrow"] = 1,
    ["Projectile/Bullet"] = 2,
    ["Reagent/Reagent"] = 4,
    ["Trade Goods/Herb"] = 8,
    ["Trade Goods/Enchanting"] = 16,
    ["Trade Goods/Parts"] = 32,
    ["Trade Goods/Devices"] = 32,
    ["Trade Goods/Explosives"] = 32,
}

--[[ A soul shard is a reagent, but not every reagent is a soul shard; the name
     is what tells the soul bag which reagents it takes. ]]--
local SOUL_SHARD = "Soul Shard"

function M:ItemFamily(link)
    if not link then return 0 end

    --[[ A later client answers directly. ]]--
    if type(GetItemFamily) == "function" then
        return tonumber(GetItemFamily(link)) or 0
    end

    if type(GetItemInfo) ~= "function" then return 0 end

    local name, _, _, _, class, subclass = GetItemInfo(link)
    local key = tostring(class or "") .. "/" .. tostring(subclass or "")
    local family = ITEM_KINDS[key] or 0

    if family == 4 and name ~= SOUL_SHARD then return 0 end
    return family
end

function M:BagFamily(id)
    id = tonumber(id)
    if not id or id <= FIRST_BAG then return 0 end

    if type(ContainerIDToInventoryID) ~= "function" then return 0 end
    if type(GetInventoryItemLink) ~= "function" then return 0 end

    local slot = ContainerIDToInventoryID(id)
    if not slot then return 0 end

    local link = GetInventoryItemLink("player", slot)
    if not link then return 0 end

    if type(GetItemFamily) == "function" then
        return tonumber(GetItemFamily(link)) or 0
    end

    if type(GetItemInfo) ~= "function" then return 0 end

    local _, _, _, _, _, subclass = GetItemInfo(link)
    return BAG_KINDS[tostring(subclass or "")] or 0
end

--[[ Whether a bag is being kept out of the grid. Clicking its button in the
     strip is what puts it here -- Bagnon's `hiddenBags`, and the reason its bag
     buttons are check buttons rather than plain ones. ]]--
function M:BagHidden(id)
    local hidden = self:Config().hiddenBags
    if type(hidden) ~= "table" then return false end
    return hidden[id] and true or false
end

function M:SetBagHidden(id, on)
    local cfg = self:Config()
    if type(cfg.hiddenBags) ~= "table" then cfg.hiddenBags = {} end

    cfg.hiddenBags[id] = on and true or nil
    return true
end

--[==[ **The walk itself**, which is `ItemGroup:Layout` with the names changed.

     Answers a list of `{ row, x, y }` and how many lines it came to. Wrapping
     at `columns`, a fresh line when `bagBreak` says so, and both orders
     reversible -- all four are Bagnon's, and all four are settings somebody can
     move while the window is open. ]==]
function M:Grid(rows, columns)
    local cfg = self:Config()

    columns = tonumber(columns) or 10
    if columns < 1 then columns = 1 end

    local bagBreak = tonumber(cfg.bagBreak) or 0
    local order, byBag = self:BagBuckets(rows)

    local out = {}
    local x, y, group = 0, 0, 0

    local n = table.getn(order)
    local from, to, step = 1, n, 1
    if cfg.reverseBags then from, to, step = n, 1, -1 end

    for k = from, to, step do
        local bag = order[k]
        local slots = byBag[bag]

        if not self:BagHidden(bag) then
            local family = self:BagFamily(bag)

            --[[ Bagnon's own condition: two breaks at every bag, one breaks
                 only where an ordinary bag meets a special one. ]]--
            if x > 0 and (bagBreak > 1
                    or (bagBreak > 0 and ((family == 0) ~= (group == 0)))) then
                group = family
                y = y + 1
                x = 0
            end

            local m = table.getn(slots)
            local sf, st, ss = 1, m, 1
            if cfg.reverseSlots then sf, st, ss = m, 1, -1 end

            for s = sf, st, ss do
                if x == columns then
                    y = y + 1
                    x = 0
                end

                table.insert(out, { row = slots[s], x = x, y = y })
                x = x + 1
            end
        end
    end

    if x > 0 then y = y + 1 end
    return out, y
end

--[[ The search text, lowered and trimmed. Empty means everything matches, which
     is the state the box spends most of its life in. ]]--
function M:Query(text)
    text = tostring(text or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    if text == "" then return "" end
    return string.lower(text)
end

--[==[ **A search dims, it does not filter.**

     `Item:UpdateSearch` sets a non-match to a third alpha and desaturates it.
     Nothing moves. That is deliberate and it is the better behaviour: a bag is
     a shape somebody has learnt, and a search that compacts the matches to the
     top destroys the shape every time a letter is typed -- including the letters
     of a word being deleted. ]==]
function M:Matches(row, query)
    if query == "" then return true end
    if not row or row.empty or not row.link then return false end

    local name = string.lower(itemName(row.link) or "")
    return string.find(name, query, 1, true) and true or false
end

function M:Refresh()
    if not self.frame or not self.frame:IsShown() then return false end
    self:Draw()
    return true
end

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

function M:Frame()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "EquadisClassicOverhaulBags", UIParent)
    f:SetWidth(MIN_BODY + FRAME_PAD)
    f:SetHeight(BASE_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetBackdrop(OB.backdrop)
    f:Hide()

    if UISpecialFrames then
        table.insert(UISpecialFrames, "EquadisClassicOverhaulBags")
    end

    f:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)

    f.close = OB.IconButton(f, "close")
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    f.close:SetScript("OnClick", function() f:Hide() end)

    --[==[ **The menu row**, which is `BagnonMenuButtonTemplate` written out.

         A quickslot ring over a black square, a square highlight, the quickslot
         depress for pushed and the check hilight for checked -- five textures,
         and the reason a Bagnon window reads as part of the client's interface
         rather than as a panel sitting on top of it.

         Check buttons throughout. Four of these six are states rather than
         actions -- which view you are in, whether the bags are showing, whether
         the search box is open -- and a state needs somewhere to show itself.
         The two that are not simply never get checked. ]==]
    f.menu = {}

    for i = 1, table.getn(MENU_BUTTONS) do
        local spec = MENU_BUTTONS[i]
        local b = CreateFrame("CheckButton", nil, f)

        b:SetWidth(MENU)
        b:SetHeight(MENU)

        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints(b)
        b.bg:SetTexture(0, 0, 0, 1)

        b.icon = b:CreateTexture(nil, "BORDER")
        b.icon:SetAllPoints(b)
        b.icon:SetTexture(spec.icon)

        --[[ The ring is drawn 34 over a 20 pixel button, the same overhang the
             client's own quickslots have. Bagnon's template says 34. ]]--
        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        local normal = b:GetNormalTexture()
        if normal then
            normal:ClearAllPoints()
            normal:SetWidth(34)
            normal:SetHeight(34)
            normal:SetPoint("CENTER", b, "CENTER", 0, 0)
        end

        b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")

        local checked = b.GetCheckedTexture and b:GetCheckedTexture()
        if checked and checked.SetBlendMode then checked:SetBlendMode("ADD") end

        b.ecoKey = spec.key
        b.ecoKind = spec.kind

        b:SetScript("OnClick", function()
            EquadisClassicOverhaul.modules.bags:MenuClick(this.ecoKey)
        end)

        b:SetScript("OnEnter", function()
            if not GameTooltip then return end
            OB.OwnTooltip(this, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText(spec.label)
            GameTooltip:AddLine(spec.tip, 0.8, 0.8, 0.8, 1)
            GameTooltip:Show()
        end)

        b:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        b:Hide()
        f.menu[spec.key] = b
    end

    --[[ The title shares the row with the search box and gives it up when the
         box opens -- `Title:UpdateVisible` hides itself while a search is
         running, because the two want the same strip of window. ]]--
    f.title = OB.NewText(f, "OVERLAY", "GameFontNormal")
    f.title:SetJustifyH("LEFT")
    f.title:SetText("Bags")

    --[==[ **The search box is not there until it is asked for.**

         `SearchFrame` starts hidden and `SearchToggle` brings it up focused.
         That is the opposite of what was here -- a box always on screen, never
         focused -- and it is the better arrangement: the box is wanted rarely
         and wanted *ready* when it is wanted at all.

         Escape closes it and clears the search, which is `Search:OnEscape`. ]==]
    f.search = CreateFrame("EditBox", "EquadisClassicOverhaulBagSearch", f,
            "InputBoxTemplate")
    f.search:SetHeight(SEARCH_H)
    f.search:SetAutoFocus(false)
    f.search:SetMaxLetters(40)

    --[==[ **Always open, never focused until clicked** -- the chat's edit box,
         which is the thing this was asked to be like. It used to start hidden
         and arrive focused from a button; now it is a strip of the title row
         that is simply there, and typing into it is what searches. Escape
         clears it and gives the keyboard back. ]==]
    f.search:Show()

    f.search:SetScript("OnTextChanged", function()
        EquadisClassicOverhaul.modules.bags:Draw()
    end)

    f.search:SetScript("OnEscapePressed", function()
        EquadisClassicOverhaul.modules.bags:CloseSearch()
    end)

    f.search:SetScript("OnEnterPressed", function() this:ClearFocus() end)

    f.searchIcon = f.search:CreateTexture(nil, "OVERLAY")
    f.searchIcon:SetWidth(14)
    f.searchIcon:SetHeight(14)
    f.searchIcon:SetPoint("LEFT", f.search, "LEFT", 4, 0)
    f.searchIcon:SetTexture("Interface" .. "\\Common" .. "\\UI-Searchbox-Icon")
    f.searchIcon:SetVertexColor(0.7, 0.7, 0.7)

    if f.search.SetTextInsets then f.search:SetTextInsets(20, 4, 0, 0) end

    --[==[ **The bag strip**, `BagGroup` -- the bags you are wearing, in a row,
         32 square and stepped 36 apart, the backpack first.

         Hidden until the toggle above it is pressed, which is how Bagnon ships
         and is the right default: it is a control surface rather than part of
         the view, and the grid below already says everything about what is in
         the bags.

         Each is a check button and each toggles its own bag out of the grid.
         That is the feature the row exists for in Bagnon -- not decoration, and
         not only a place to drop a new bag. ]==]
    f.bagStrip = CreateFrame("Frame", nil, f)
    f.bagStrip:SetHeight(BAG_BUTTON)
    f.bagStrip:SetWidth(BAG_BUTTON)
    f.bagStrip:Hide()

    f.bagSlots = {}

    for id = FIRST_BAG, LAST_BAG do
        local b = CreateFrame("CheckButton", nil, f.bagStrip)

        b:SetWidth(BAG_BUTTON)
        b:SetHeight(BAG_BUTTON)
        b:SetPoint("LEFT", f.bagStrip, "LEFT",
                (id - FIRST_BAG) * BAG_PITCH, 0)

        b.icon = b:CreateTexture(nil, "BORDER")
        b.icon:SetAllPoints(b)

        --[[ `Bag.TextureSize` is `64 * (32/36)`, which is the quickslot ring
             at the size a 32 pixel bag button wants it. ]]--
        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        local normal = b:GetNormalTexture()
        if normal then
            normal:ClearAllPoints()
            normal:SetWidth(64 * (BAG_BUTTON / 36))
            normal:SetHeight(64 * (BAG_BUTTON / 36))
            normal:SetPoint("CENTER", b, "CENTER", 0, -1)
        end

        b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        b:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")

        local checked = b.GetCheckedTexture and b:GetCheckedTexture()
        if checked and checked.SetBlendMode then checked:SetBlendMode("ADD") end

        b.ecoBag = id

        b:SetScript("OnClick", function()
            EquadisClassicOverhaul.modules.bags:ClickBagButton(this.ecoBag)
        end)

        b:SetScript("OnReceiveDrag", function()
            EquadisClassicOverhaul.modules.bags:ClickBagSlot(this.ecoBag)
        end)

        b:SetScript("OnEnter", function()
            local m = EquadisClassicOverhaul.modules.bags
            m:BagSlotTooltip(this)
            m:HighlightBag(this.ecoBag)
        end)

        b:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
            EquadisClassicOverhaul.modules.bags:HighlightBag(nil)
        end)

        f.bagSlots[id] = b
    end

    --[[ The grid is a frame of its own, the way `ItemGroup` is, so the bag
         strip above it and the money below it have something to anchor to that
         is the size of the grid rather than the size of the window. ]]--
    f.grid = CreateFrame("Frame", nil, f)
    f.grid:SetWidth(1)
    f.grid:SetHeight(1)

    --[==[ **Money, bottom right, against the grid.**

         `PlaceMoney` anchors the money frame's TOPRIGHT to the item group's
         BOTTOMRIGHT, eight pixels out. Against the *grid* rather than against
         the window edge, which is what was wrong before: the coins were pinned
         to the frame and the grid was not, so the two drifted apart whenever
         the column count changed.

         Real coin textures rather than a `|T|t` escape in the string. The escape
         is a 2.0 addition; a 1.12 font string prints it as literal text. ]==]
    f.money = CreateFrame("Frame", nil, f)
    f.money:SetHeight(MONEY_H)
    f.money:SetWidth(MONEY_W)

    f.coins = {}
    local anchor, gap = nil, 0

    for _, coin in ipairs({ { "copper", 0.50 }, { "silver", 0.25 },
                            { "gold", 0.00 } }) do
        local icon = f.money:CreateTexture(nil, "OVERLAY")
        icon:SetWidth(12)
        icon:SetHeight(12)
        icon:SetTexture("Interface" .. "\\MoneyFrame" .. "\\UI-MoneyIcons")
        icon:SetTexCoord(coin[2], coin[2] + 0.25, 0, 1)

        if anchor then
            icon:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
        else
            icon:SetPoint("RIGHT", f.money, "RIGHT", -2, 0)
        end

        local text = OB.NewText(f.money, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("RIGHT", icon, "LEFT", -2, 0)

        f.coins[coin[1]] = text
        anchor, gap = text, 7
    end

    f.buttons = {}
    f:SetScript("OnShow", function()
        EquadisClassicOverhaul.modules.bags:Draw()
    end)

    self.frame = f
    return f
end

--[==[ **What the six buttons do.**

     Split out of the button so the handler is one line and the behaviour is
     readable in one place. A view button toggles: pressing Bank while looking
     at the bank puts you back in your bags, which is what pressing the thing
     you are already on should do. ]==]
function M:MenuClick(key)
    if key == "sort" then return self:Sort() end

    --[[ Session state rather than a saved setting: marking is something you do
         for a minute and stop. A profile that remembered it would put somebody
         back into a mode they left, and the mode swallows the click that would
         have used an item. ]]--
    if key == "mark" then
        self.marking = not self.marking and true or nil

        if self.marking then
            Say("click items to mark them. Click Mark Items again to stop.")
        end

        return self:Draw()
    end

    if self:View() == key then
        self:SetView("bags")
    else
        self:SetView(key)
    end

    return true
end

--[[ Escape: the text goes and the keyboard is given back. The box stays. ]]--
function M:CloseSearch()
    local f = self:Frame()
    f.search:SetText("")
    f.search:ClearFocus()
    self:Draw()
    return true
end

--[[ Whether a search is narrowing the grid, which is what `searching` used to
     record as a state and is now a fact about the box's text. ]]--
function M:Searching()
    local f = self:Frame()
    local text = f.search and f.search.GetText and f.search:GetText() or ""
    return text ~= ""
end

--[[ Which of the six are on screen right now. Bagnon builds the row by
     filtering, then chains what is left -- so a button switched off does not
     leave a gap, and the search box that follows the row starts wherever the
     row happened to end. ]]--
function M:MenuList()
    local cfg = self:Config()
    local out = {}

    for i = 1, table.getn(MENU_BUTTONS) do
        local spec = MENU_BUTTONS[i]
        local want = true

        if spec.key == "sort" then
            want = cfg.sort and true or false
        elseif spec.key == "mark" then
            --[[ Always. The alternative was a mouse button nobody could find;
                 a button that is sometimes missing would be the same problem
                 with an extra step. ]]--
            want = true
        elseif spec.key == "players" then
            --[[ `Frame:HasOwnerSelector` -- there is no owner to select between
                 until a second character has been seen. It stays while you are
                 looking through one, or the view would have no way back. ]]--
            want = self:View() == "players"
                    or table.getn(self:OtherCharacters()) > 0
        end

        if want then table.insert(out, spec.key) end
    end

    return out
end

--[[ How far in the icon sits, clamped to the slider's own range so a profile
     written before this existed -- or by hand -- cannot bury the picture under
     its own ring or leave it flush to the edge again. ]]--
function M:IconInset()
    local inset = tonumber(self:Config().iconInset)
    if not inset then return 0 end

    if inset < 0 then return 0 end
    if inset > 6 then return 6 end

    return inset
end

function M:PlaceSlotIcon(b)
    if not b or not b.icon then return false end

    local inset = self:IconInset()

    b.icon:ClearAllPoints()
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", inset, -inset)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -inset, inset)

    return true
end

--[==[ **The ring: the character panel's colour where there is one, and turned
     down where there is not.**

     Rarity is painted by `qol:PaintRarity`, the one implementation every item
     slot in the interface goes through, so a rare item here is the same ring
     and the same glow as on the paper doll because it is the same code. This
     module's only opinion is about the *plain* slot: a grid of ninety-eight
     squares in polished chrome is a wall of rims, and the item is what somebody
     is looking for, so an ordinary ring is multiplied down by `slotShine`. The
     paper doll has nineteen slots and does not need it.

     Returns whether a rarity colour was drawn, which is what the caller was
     already asking. ]==]
function M:PaintSlotRing(b, quality)
    if not b or not b.GetNormalTexture then return false end

    local ring = b:GetNormalTexture()
    if not ring or not ring.SetVertexColor then return false end

    local quality_ = OB.modules and OB.modules.qol

    if quality_ and quality_.PaintRarity and quality_:PaintRarity(b, quality) then
        return true
    end

    local shine = tonumber(self:Config().slotShine) or 0.65

    if shine < 0 then shine = 0 end
    if shine > 1 then shine = 1 end

    ring:SetVertexColor(shine, shine, shine)
    return false
end

--[==[ **One slot.**

     `ContainerFrameItemButtonTemplate` in Bagnon, which is 37 square with an
     icon, a count and a cooldown. Built by hand here rather than inherited: the
     1.12 template binds its scripts to its parent's container id, and this grid
     draws slots from several bags into one parent.

     What it carries is Bagnon's: the empty-slot artwork behind, the icon, the
     count bottom right, and the quality glow -- `UI-ActionButton-Border` at 67
     over a 37 pixel button, additive, centred, at `glowAlpha`.

     Pooled, because the number of squares changes with the bags and a frame per
     redraw is a frame the client never collects. ]==]
function M:Button(index)
    local f = self:Frame()
    if f.buttons[index] then return f.buttons[index] end

    local b = CreateFrame("Button", "EquadisClassicOverhaulBagSlot" .. index,
            f.grid)
    b:SetWidth(ITEM)
    b:SetHeight(ITEM)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")

    --[==[ **Press, drag, let go -- one motion**, which is how the client's
         own bag slots move an item and how a hand expects to. This window
         only answered clicks: pick up on one, put down on the next, and a
         drag between them did nothing at all, because a button that has
         not registered for a drag never hears one and a click is only a
         click if the mouse comes up where it went down.

         `OnDragStart` lifts the item the way a click does; `OnReceiveDrag`
         is what the slot the mouse is let go over hears, and it takes
         whatever is on the cursor -- the client's `ContainerFrameItemButton`
         pair, transcribed. Marking mode is a mode for clicks and stays out
         of it. ]==]
    b:RegisterForDrag("LeftButton")

    b:SetScript("OnDragStart", function()
        local m = EquadisClassicOverhaul.modules.bags
        if m.marking or not this.bag or not this.itemId then return end
        if type(PickupContainerItem) ~= "function" then return end

        PickupContainerItem(this.bag, this.slot)
    end)

    b:SetScript("OnReceiveDrag", function()
        if not this.bag or type(PickupContainerItem) ~= "function" then return end
        if not (CursorHasItem and CursorHasItem()) then return end

        PickupContainerItem(this.bag, this.slot)
    end)

    --[[ The empty slot's own artwork, which is what the client draws in a slot
         with nothing in it. Behind the icon rather than instead of it, so the
         same texture serves as the backing for a full slot too. ]]--
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetTexture(EMPTY_SLOT)

    --[==[ **Under the ring rather than over it.**

         `BORDER` is below `ARTWORK`, and a button's normal texture draws in
         `ARTWORK` -- so the client's ring lands on top of the icon's edges,
         which is the arrangement every item button in the game uses and the
         reason an icon reads as sitting *in* a slot.

         Inset as well, so there is something for the ring to sit on. ]==]
    b.icon = b:CreateTexture(nil, "BORDER")

    --[==[ **Cropped, because a WoW icon file has a border drawn into it.**

         Every `Interface\\Icons\\` texture carries a dark bevelled edge as
         part of the picture, meant for the raised slot art the client draws
         around it. Squares of icons drawn edge to edge therefore come out with
         a grid of dark lines between them and a muddy border on every item,
         which is what "the icons look bad" is.

         `0.07` to `0.93` is the standard trim -- the same crop every interface
         that draws its own icon grid uses -- and it takes the border off
         without touching the picture. ]==]
    if b.icon.SetTexCoord then b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end

    --[[ The client's own ring, which is what makes the square a slot. Tinted
         rather than replaced, so what is drawn is always the client's art. ]]--
    b:SetNormalTexture(SLOT_RING)

    --[==[ **Sixty-four over thirty-seven, or the rim lands inside the icon.**

         `UI-Quickslot2` is a picture of a rim with a clear middle, and the rim
         sits well inside the image -- the client draws it at 64 over a 37 pixel
         item button (`ContainerFrameItemButtonTemplate`) and at 66 over a 36
         pixel action button, so that the rim falls on the icon's *edge* and the
         clear middle covers the picture.

         Left to itself a normal texture takes the button's size. At 37 the rim
         shrinks to a square drawn across the middle of every icon, with the
         icon's own edges showing round the outside of it -- "each slot has an
         ugly square in the middle", which is precisely what it was. The bag
         strip a few hundred lines up already sizes this same texture 34 over
         20 for the same reason; the item slot never did.

         The one-pixel drop is the template's own offset. ]==]
    local ring = b:GetNormalTexture()
    if ring and ring.SetWidth then
        ring:ClearAllPoints()
        ring:SetWidth(64)
        ring:SetHeight(64)
        ring:SetPoint("CENTER", b, "CENTER", 0, -1)
    end

    --[==[ **On cooldown, darkened the way a spell on the bar is.**

         A healthstone that cannot be used yet looks exactly like one that can,
         and the client already has the answer: the same `Cooldown` frame the
         action buttons use, which darkens the icon and sweeps a clock over it.
         Fed from `GetContainerItemCooldown`, which is the container's own
         version of the call the bar reads.

         Built here rather than borrowed from the client's own template for the
         reason the note above gives -- the 1.12 template binds its scripts to
         its parent's container id, and this grid draws several bags into one
         parent. ]==]
    if CreateFrame then
        b.cooldown = CreateFrame("Model", nil, b, "CooldownFrameTemplate")

        if b.cooldown and b.cooldown.SetAllPoints then
            b.cooldown:SetAllPoints(b)
        end
    end

    b.count = OB.NewText(b, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    b.count:SetJustifyH("RIGHT")

    --[==[ **The junk marker**, Bagnon's `JunkIcon`.

         A coin in the corner of anything grey. Bagnon also checks the item has
         a sell price, so a worthless grey is not marked -- 1.12's `GetItemInfo`
         answers nine values and none of them is a price, so that half cannot be
         ported and every grey gets the coin. ]==]
    b.junk = b:CreateTexture(nil, "OVERLAY")
    b.junk:SetWidth(12)
    b.junk:SetHeight(12)
    b.junk:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.junk:SetTexture("Interface" .. "\\MoneyFrame" .. "\\UI-MoneyIcons")
    b.junk:SetTexCoord(0, 0.25, 0, 1)
    b.junk:Hide()

    --[==[ **The keep marker takes the other corner, and it is a padlock.**

         It was a gold square -- `SetTexture(1, 0.82, 0)`, a flat colour with no
         picture at all -- which says "something is true about this item" and
         nothing about what. The mark means the sell and trade guards will not
         let go of it, so the picture is a lock, which is that sentence in one
         glyph.

         This addon already ships the icon; it was drawn for the same idea on
         another screen. ]==]
    b.star = b:CreateTexture(nil, "OVERLAY")
    b.star:SetWidth(13)
    b.star:SetHeight(13)
    b.star:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
    b.star:SetTexture(OB.mediaPath .. "textures\\icons\\lock")
    b.star:Hide()

    b:SetScript("OnEnter", function()
        EquadisClassicOverhaul.modules.bags:ItemTooltip(this)
    end)

    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetScript("OnClick", function()
        local m = EquadisClassicOverhaul.modules.bags

        --[[ An empty slot still takes what is on the cursor, which is how you
             put something down. ]]--
        if not this.itemId then
            if CursorHasItem and CursorHasItem() and this.bag
                    and type(PickupContainerItem) == "function" then
                PickupContainerItem(this.bag, this.slot)
            end
            return
        end

--[==[ **Marking is a mode, not a mouse button.**

             Right click used to toggle the favourite mark. Two things were
             wrong with that. It is the button the whole game uses to equip or
             use an item, so the one gesture everybody already knows did the one
             thing nobody expected -- and because favourites are keyed by item
             id rather than by slot, a single click put a gold square on every
             copy of that item at once, with nothing on screen saying why.

             Marking now has its own button on the menu row: switch it on,
             click what you want marked, switch it off. A mode is the right
             shape for it because marking is something you do to several things
             in a row and then stop doing. ]==]
        if m.marking then
            m:ToggleFavourite(this.itemId)
            return
        end

        --[[ Shift puts the link in whatever is being typed, which is the
             gesture every other item in the interface answers to. ]]--
        if IsShiftKeyDown and IsShiftKeyDown() and this.link then
            if ChatFrameEditBox and ChatFrameEditBox:IsVisible()
                    and ChatFrameEditBox.Insert then
                ChatFrameEditBox:Insert(this.link)
                return
            end
        end

        --[[ Something on the cursor goes into this slot whichever button put it
             there: a swap is a swap. Answered before the two below so that a
             right click while carrying something does not try to equip what is
             already in the bag. ]]--
        if CursorHasItem and CursorHasItem() and this.bag
                and type(PickupContainerItem) == "function" then
            PickupContainerItem(this.bag, this.slot)
            return
        end

        --[[ **The client's own two answers, in the client's own places.**

             Right uses or equips; left picks up to move. That is what the bag
             this replaces does, what every other item in the interface does,
             and what a hand already knows without being told. ]]--
        if arg1 == "RightButton" then
            if type(UseContainerItem) == "function" then
                UseContainerItem(this.bag, this.slot)
            end
            return
        end

        if this.bag and type(PickupContainerItem) == "function" then
            PickupContainerItem(this.bag, this.slot)
        end
    end)

    f.buttons[index] = b
    return b
end

--[==[ **A container item's tooltip comes from its slot, not from its link.**

     `SetHyperlink` was handed the full coloured link -- `|cff...|Hitem:1234...|h
     [Name]|h|r` -- and 1.12 wants the *item string* inside it. The client
     answers "Unknown link type" and raises, which surfaced through whichever
     addon happened to be wrapping the tooltip: here it was reported as an error
     inside SuperCleveRoidMacros, which had nothing to do with it beyond being
     the wrapper in the way.

     `SetBagItem` is what the client's own container buttons use. It takes the
     bag and slot, so nothing has to be parsed, and it produces the full
     tooltip -- sell price, equipped comparison, the lot -- which a hyperlink
     tooltip does not.

     The link path stays for the views that have no live slot behind them: the
     bank drawn from memory and the other characters' bags. There the item
     string is extracted rather than passed whole, which is the fix to the
     original bug. ]==]
function M:ItemTooltip(button)
    if not button or not button.link or not GameTooltip then return false end

    OB.OwnTooltip(button, "ANCHOR_RIGHT")

    local live = self:View() == "bags"
            or (self:View() == "bank" and self.bankOpen)
            or self:View() == "keyring"

    if live and button.bag and button.slot
            and type(GameTooltip.SetBagItem) == "function" then
        GameTooltip:SetBagItem(button.bag, button.slot)
        GameTooltip:Show()
        return true
    end

    --[[ `|Hitem:1234:0:0:0|h` -- the part between the H and the h, which is what
         `SetHyperlink` understands. The colour codes and the bracketed name
         around it are for chat. ]]--
    local _, _, itemString = string.find(button.link, "|H(item:[%d:%-]+)|h")

    if itemString and type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetHyperlink(itemString)
        GameTooltip:Show()
        return true
    end

    GameTooltip:Hide()
    return false
end

function M:MaxStack(link)
    if type(GetItemInfo) ~= "function" or not link then return 1 end

    local _, _, _, _, _, _, stack = GetItemInfo(link)
    return tonumber(stack) or 1
end

--[==[ **An item in flight cannot be moved.**

     `GetContainerItemInfo` answers `locked` third: the slot is picked up, or
     something else is moving it, and a pickup aimed at it does nothing at all.
     A pass that does not look will happily reissue the same failed move on every
     update, which is a loop that looks exactly like a hang. ]==]
function M:SlotLocked(bag, slot)
    if type(GetContainerItemInfo) ~= "function" then return false end

    local _, _, locked = GetContainerItemInfo(bag, slot)
    return locked and true or false
end

--[==[ **A pass, not a step: every move that can go out, goes out at once.**

     The old engine made one move per client event. A move is a pickup and a
     drop, both slots stay locked until the server confirms, and confirmation
     is a round trip -- so sixty items took sixty round trips, which read on
     screen as the bags shuffling one square at a time for the better part of
     a minute. That was also the wrong shape for finding out why a sort was
     stopping short: a run with a hundred small steps has a hundred places to
     stop.

     A pass reads the bags once and issues every move whose two slots are
     free, marking both as in flight; the next pass waits until every slot
     the last one touched is unlocked again and the client has said the bags
     changed, then reads once more and issues the rest. The stacking pass
     comes first and stands alone, because merging changes counts and frees
     slots. Three or four passes tidy a full set of bags in a second or two.
     shirsig's SortBags for 1.12 works this way, and it is why that one is
     fast.

     `self.touched` is the set of "bag:slot" keys the last pass moved. Each
     pass begins by clearing it -- the run driver has already waited for
     them -- so calling a pass on its own, as the tests do, always starts
     clean. ]==]
local function slotKey(row)
    return tostring(row.bag) .. ":" .. tostring(row.slot)
end

--[[ One pickup and one drop, and both slots remembered as in flight.
     Whatever is on the cursor would be dropped into the first slot touched
     instead of the item we meant, so it is put back first. ]]--
function M:Move(from, to)
    if type(ClearCursor) == "function" then ClearCursor() end

    PickupContainerItem(from.bag, from.slot)
    PickupContainerItem(to.bag, to.slot)

    self.touched = self.touched or {}
    self.touched[slotKey(from)] = true
    self.touched[slotKey(to)] = true
    self.sortMoves = (self.sortMoves or 0) + 1

    return true
end

--[[ A slot this pass may touch: not moved already this pass, and not in
     flight from anything else. ]]--
function M:SlotFree(row)
    if self.touched and self.touched[slotKey(row)] then return false end
    return not self:SlotLocked(row.bag, row.slot)
end

--[==[ **The stacking pass: every pair of loose piles that can be merged.**

     Piles of one item are paired smallest onto largest, so a merge that does
     not fit leaves the remainder where the bigger pile already was -- and
     then the next pair, because both slots of a merged pair are in flight
     and out of this pass. Answers `true` when it merged anything, `"locked"`
     when a pile it would have merged is in flight, `false` when there is
     nothing loose to stack. A favourite is never a pile. ]==]
function M:CleanStep()
    if type(GetContainerItemInfo) ~= "function" then return false end
    if type(PickupContainerItem) ~= "function" then return false end

    self.touched = {}

    local rows = self:ScanBags()
    local piles, loose = {}, {}

    for i = 1, table.getn(rows) do
        local row = rows[i]
        local max = (not row.empty) and self:MaxStack(row.link) or 1

        --[[ A full pile is not a partial one, and an unstackable item never
             has a partial pile to find. Both are the same test. ]]--
        local partial = (not row.empty) and row.id
                and max > 1 and (row.count or 1) < max

        if partial and not self:IsFavourite(row.id) then
            loose[row.id] = (loose[row.id] or 0) + 1

            if self:SlotFree(row) then
                piles[row.id] = piles[row.id] or {}
                table.insert(piles[row.id], row)
            end
        end
    end

    local moved, blocked = false, false

    for id, list in pairs(piles) do
        table.sort(list, function(a, b) return (a.count or 1) > (b.count or 1) end)

        while table.getn(list) >= 2 do
            local to = table.remove(list, 1)
            local from = table.remove(list)

            self:Move(from, to)
            moved = true
        end

        --[[ One pile left over with a partner in flight is a merge to come
             back for, not a bag that is done stacking. ]]--
        if table.getn(list) == 1 and (loose[id] or 0) >= 2 then blocked = true end
    end

    --[[ And an item whose every loose pile is in flight. ]]--
    for id, n in pairs(loose) do
        if n >= 2 and not piles[id] then blocked = true end
    end

    if moved then return true end
    if blocked then return "locked" end
    return false
end

--[==[ **Closing the gaps is not a pass of its own.**

     The old sorter compared the wanted order against the *items* and so could
     reorder what was there without ever moving something into a hole. Bagnon's
     compares the order against the *slots*, in bag order -- so the n items
     land in the first n slots that will take them, and the tidying and the
     ordering are the same pass. ]==]

--[==[ **An item's quality, and its name.**

     Neither is on the scanned row: `GetContainerItemInfo` answers texture and
     count, and quality is only in the link -- as the colour code the client
     writes at the front of it. Read from `GetItemInfo` where the client knows
     the item, and from that colour where it does not.

     Nought rather than nil for an unknown, so a comparison never has to handle
     a missing side. An item the client has never heard of sorts as junk, which
     is where an unidentifiable thing belongs. ]==]
local QUALITY_BY_COLOUR = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2,
    ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6,
}

function M:RowQuality(row)
    if not row or not row.link then return 0 end

    if type(GetItemInfo) == "function" then
        local _, _, quality = GetItemInfo(row.link)
        if quality then return quality end
    end

    local _, _, hex = string.find(row.link, "|cff(%x%x%x%x%x%x)")
    return hex and QUALITY_BY_COLOUR[string.lower(hex)] or 0
end

function M:RowName(row)
    if not row or not row.link then return "" end

    local _, _, name = string.find(row.link, "%[(.-)%]")
    return name or row.link
end

-- ---------------------------------------------------------------------------
-- clean up
-- ---------------------------------------------------------------------------

--[==[ **Bagnon's sorter, which is one button rather than two.**

     `core/api/sorting.lua` does two passes in one operation: it merges every
     partial stack it can find, then it puts what is left in order. That is why
     Bagnon has a single broom where this window had a Clean and a Sort, and the
     single button is right -- "tidy my bags" is one intention, and splitting it
     across two controls made the reader decide which half they wanted.

     **The order is Bagnon's `Sort.Proprieties`, in Bagnon's sequence**, every
     key compared descending:

         set, class, subclass, equip, quality, iconFileID, level, itemID,
         stackCount

     Two of those cannot be ported. `set` needs equipment sets, which 1.12 has
     no concept of, and `iconFileID` is a number on retail where 1.12 answers a
     texture path -- the path works as a key in its own right, so it stays and
     sorts by name of file rather than by id of file. Neither changes the shape
     of the result: they are tie-breaks below class and quality.

     Descending throughout, which looks odd written down and is correct: it puts
     the best of a kind at the front of its kind, which is the order somebody
     scanning a bag is actually reading in. ]==]
function M:SortKeys(row)
    local keys = { class = "", subclass = "", equip = "", texture = "",
                   quality = 0, level = 0, id = 0, count = 0 }

    if not row or row.empty or not row.link then return keys end

    keys.id = tonumber(row.id) or 0
    keys.count = tonumber(row.count) or 1
    keys.quality = self:RowQuality(row)
    keys.texture = tostring(row.texture or "")

    if type(GetItemInfo) == "function" then
        local _, _, quality, level, class, subclass, _, equip =
                GetItemInfo(row.link)

        keys.quality = tonumber(quality) or keys.quality
        keys.level = tonumber(level) or 0
        keys.class = tostring(class or "")
        keys.subclass = tostring(subclass or "")
        keys.equip = tostring(equip or "")
    end

    return keys
end

local SORT_KEYS = { "class", "subclass", "equip", "quality",
                    "texture", "level", "id", "count" }

--[[ Keys are read once per row and hung on it, not once per comparison. A sort
     of a hundred and sixty slots is something like twelve hundred comparisons,
     and `GetItemInfo` on every one of them is a noticeable pause. ]]--
function M:OrderBefore(a, b)
    local ka = a.eqKeys or self:SortKeys(a)
    local kb = b.eqKeys or self:SortKeys(b)

    for i = 1, table.getn(SORT_KEYS) do
        local key = SORT_KEYS[i]
        if ka[key] ~= kb[key] then return ka[key] > kb[key] end
    end

    return false
end

--[==[ **Do these two bitmasks share a bit.**

     `Sort:FitsIn` uses `bit.band`. 1.12 ships no bit library, and the masks in
     question are small -- a bag family is one of about a dozen flags -- so the
     test is done by walking the bits arithmetically. It stops at the smaller of
     the two, because a bit neither side can have is not worth looking at. ]==]
function M:FamilyOverlap(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    if a <= 0 or b <= 0 then return false end

    local bit = 1
    while bit <= a and bit <= b do
        if mod(floor(a / bit), 2) == 1 and mod(floor(b / bit), 2) == 1 then
            return true
        end
        bit = bit * 2
    end

    return false
end

--[==[ **Whether this item may live in that kind of bag.**

     `Sort:FitsIn`. An ordinary bag takes anything; a quiver takes arrows and
     nothing else, and an arrow put anywhere else is a move the client silently
     refuses. Without this check the sorter aims a move at a slot that cannot
     accept it, the move does not happen, and the pass runs again on the next
     bag update and aims the same move at the same slot -- for ever.

     An empty slot is a fit by definition; there is nothing there to disagree
     with. ]==]
function M:FitsIn(row, family)
    family = tonumber(family) or 0
    if family == 0 then return true end
    if not row or row.empty or not row.link then return true end

    return self:FamilyOverlap(self:ItemFamily(row.link), family)
end

--[==[ **The ordering pass: every misplaced item that can move, moved.**

     Stacking first, and alone: merging frees slots and changes counts, so the
     ordering waits a pass for it. Then, family by family with the special
     bags first (`Sort:GetFamilies` descending -- a quiver claims the arrows
     before the ordinary bags get a chance at them), the nth wanted item goes
     to the nth slot. The pass keeps its own picture of where everything is
     as it issues moves, so the twentieth move is aimed at where the bags
     will be, not where they were when the pass began; and it skips any move
     whose slot is already in flight, leaving it for the next pass.

     **A favourite is never moved.** It is somewhere on purpose, which is the
     whole of what marking one means.

     Answers `true` when it moved anything, `"locked"` when something is left
     to do and every way of doing it is in flight, `false` when the bags are
     in order. ]==]
function M:SortStep()
    if type(PickupContainerItem) ~= "function" then return false end

    local cleaned = self:CleanStep()
    if cleaned then return cleaned end

    local rows = self:ScanBags()

    --[[ `Sort:GetSpaces` -- every slot that may be touched, remembering which
         kind of bag it belongs to. ]]--
    local spaces = {}

    for i = 1, table.getn(rows) do
        local row = rows[i]

        if row.empty or not self:IsFavourite(row.id) then
            row.eqFamily = self:BagFamily(row.bag)
            row.eqKeys = self:SortKeys(row)
            table.insert(spaces, row)
        end
    end

    --[[ The pass's own picture: a row is both a slot and, to begin with, the
         item in it. `content[slot]` is the item there now and `pos[item]` the
         slot it is in, and a move swaps the two pairs. ]]--
    local content, pos = {}, {}

    for i = 1, table.getn(spaces) do
        content[spaces[i]] = spaces[i]
        pos[spaces[i]] = spaces[i]
    end

    --[[ `Sort:GetFamilies`, descending: special bags before ordinary ones. ]]--
    local seen, families = {}, {}

    for i = 1, table.getn(spaces) do
        local family = spaces[i].eqFamily
        if not seen[family] then
            seen[family] = true
            table.insert(families, family)
        end
    end

    table.sort(families, function(a, b) return a > b end)

    local claimed = {}
    local moved, pending = false, false

    for k = 1, table.getn(families) do
        local family = families[k]

        --[[ `Sort:GetOrder` -- what fits this kind of bag and has not already
             been claimed by a narrower one, and the slots it may go in. ]]--
        local order, slots = {}, {}

        for i = 1, table.getn(spaces) do
            local row = spaces[i]

            if not row.empty and not claimed[row] and self:FitsIn(row, family) then
                table.insert(order, row)
            end

            if row.eqFamily == family then table.insert(slots, row) end
        end

        table.sort(order, function(x, y) return self:OrderBefore(x, y) end)

        local n = table.getn(order)
        if table.getn(slots) < n then n = table.getn(slots) end

        for i = 1, n do
            local want, goal = order[i], slots[i]
            claimed[want] = true

            local cur = pos[want]

            if cur ~= goal then
                local displaced = content[goal]

                --[[ Both slots free, and whatever is standing in the goal able
                     to live where the wanted item came from -- or the swap
                     trades one misplaced item for another the client will
                     refuse. ]]--
                if not self:SlotFree(goal) or not self:SlotFree(cur) then
                    pending = true
                elseif not self:FitsIn(displaced, cur.eqFamily) then
                    pending = true
                else
                    self:Move(cur, goal)

                    content[goal], pos[want] = want, goal
                    content[cur], pos[displaced] = displaced, cur
                    moved = true
                end
            end
        end
    end

    if moved then return true end
    if pending then return "locked" end
    return false
end

--[==[ **The button says what it did.**

     Bagnon says nothing, and on retail it does not need to: its sort is the
     client's own and everybody already knows the order. Here the order is a
     transcription of somebody else's rule, and a bag that comes back
     rearranged looks arbitrary unless you happen to work it out. Said once, on
     both paths -- a bag already in that order was still sorted by something. ]==]
local SORT_ORDER = "kind, then quality, then item level"

--[==[ **The run: a pass, a wait for it to land, another pass.**

     Bounded three ways, because a run that never ends is worse than one that
     stops short: a ceiling on passes, a ceiling on how many ticks a settle
     may take, and a check that the bags actually changed after a pass that
     moved something -- if they did not, the client refused the moves, and
     asking again is what the old engine spent four hundred moves doing. The
     refusal is said out loud, with the first move that was refused, because
     "the sort stops after the first bag" is a report about exactly this and
     nothing on screen said which move.

     The settle waits for two things: every slot the last pass touched to be
     unlocked, and the client to have said something since (`BAG_UPDATE` or
     `ITEM_LOCK_CHANGED`) -- or a second to have passed, for a client that
     says nothing. The lock alone is not enough: a refused move never locks
     at all. ]==]
local MAX_PASSES = 40
local MAX_WAITS = 60
local SETTLE_GRACE = 1.0

--[[ Bagshui restacks on a timer, a move every 0.15 s, and on this client
     that is the right instrument: the events are earlier when they come,
     and the ticker is what makes sure they are not the only thing. ]]--
local SORT_TICK = 0.15

function M:SortTicker()
    if self.ticker then return self.ticker end

    local ticker = CreateFrame("Frame", nil, UIParent)
    ticker.elapsed = 0
    ticker:Hide()

    ticker:SetScript("OnUpdate", function()
        local m = EquadisClassicOverhaul.modules.bags

        if not m or not m.sorting then
            this:Hide()
            return
        end

        this.elapsed = (this.elapsed or 0) + (tonumber(arg1) or 0)
        if this.elapsed < SORT_TICK then return end

        this.elapsed = 0
        m:ContinueRun()
    end)

    self.ticker = ticker
    return ticker
end

--[[ Every slot, what is in it and how many: the bags as one string, so two
     readings can be compared. ]]--
function M:Shape()
    local rows = self:ScanBags()
    local parts = {}

    for i = 1, table.getn(rows) do
        local row = rows[i]
        table.insert(parts, slotKey(row) .. "=" .. tostring(row.link or "")
                .. "x" .. tostring(row.count or 0))
    end

    return table.concat(parts, ";")
end

function M:EndRun(why)
    self.sorting = nil
    if self.ticker then self.ticker:Hide() end

    if why then Say(why) end
    return true
end

--[[ One pass, and the bookkeeping the driver needs to know whether it
     landed: what the bags looked like before it, whether it moved anything,
     and when. ]]--
function M:RunPass()
    self.shapeBefore = self:Shape()
    self.bagUpdated = nil
    self.passAt = (type(GetTime) == "function" and GetTime()) or 0

    local step = self:SortStep()

    self.passIssued = (step == true)
    if step == true then self.sortPasses = (self.sortPasses or 0) + 1 end

    return step
end

function M:Sort()
    self.sorting = true
    self.sortMoves = 0
    self.sortWaits = 0
    self.sortPasses = 0
    self.touched = {}

    local step = self:RunPass()

    if not step then
        self:EndRun()
        Say("already tidy -- sorted by " .. SORT_ORDER .. ".")
        return true
    end

    local ticker = self:SortTicker()
    ticker.elapsed = 0
    ticker:Show()

    Say("tidying up: stacking, then sorting by " .. SORT_ORDER .. ".")
    return true
end

function M:Wait()
    self.sortWaits = (self.sortWaits or 0) + 1

    if self.sortWaits >= MAX_WAITS then
        self:EndRun("stopped: a slot stayed locked for too long.")
    end

    return true
end

--[[ Whether the last pass has landed: nothing it touched is still in
     flight, and the client has said the bags changed -- or long enough has
     passed that it is not going to. ]]--
function M:Settled()
    for key in pairs(self.touched or {}) do
        local _, _, bag, slot = string.find(key, "^(-?%d+):(%d+)$")

        if bag and self:SlotLocked(tonumber(bag), tonumber(slot)) then
            return false
        end
    end

    if self.passIssued and not self.bagUpdated then
        local now = (type(GetTime) == "function" and GetTime()) or 0
        if (now - (self.passAt or 0)) < SETTLE_GRACE then return false end
    end

    return true
end

--[[ The step that keeps a run going, driven by the client telling us a move
     landed -- `BAG_UPDATE` when the contents change, `ITEM_LOCK_CHANGED` when a
     slot is released, either may be the one that arrives last -- and by the
     ticker, for when neither does. ]]--
function M:ContinueRun()
    if not self.sorting then return false end

    if (self.sortPasses or 0) >= MAX_PASSES then
        return self:EndRun("stopped: too many passes.")
    end

    if not self:Settled() then return self:Wait() end

    --[[ A pass that moved things and changed nothing was refused by the
         client. Said, with the first move it asked for, and stopped. ]]--
    if self.passIssued and self:Shape() == self.shapeBefore then
        local first
        for key in pairs(self.touched or {}) do first = first or key end

        return self:EndRun("stopped: the client refused a move"
                .. (first and (" (slot " .. first .. ")") or "") .. ".")
    end

    local step = self:RunPass()

    if step == true then
        self.sortWaits = 0
    elseif step == "locked" then
        self:Wait()
    else
        self:EndRun("sorted: " .. tostring(self.sortMoves or 0) .. " moves in "
                .. tostring(self.sortPasses or 0) .. " passes.")
    end

    return true
end

--[==[ **`Frame:Layout`, transcribed.**

     Bagnon starts a window at 44 by 36 and grows it: the top row adds its width
     but not its height, because the 36 already is the top row; the bag strip,
     the grid and the money each add their height and push the width out to
     whatever they need. The result is `max(width, 156) + 16` across.

     Everything is placed against the thing above it rather than against the
     window, which is what makes the arithmetic come out -- and is what was
     wrong with the money before. It was pinned to the frame's bottom corner
     while the grid was pinned to the top, so the two drifted apart every time
     the column count changed and the coins ended up floating. ]==]
function M:Draw()
    local f = self:Frame()
    local cfg = self:Config()

    local view = self:View()

    local columns = tonumber(view == "bank" and cfg.bankColumns or cfg.columns)
            or 10
    if columns < 1 then columns = 1 end

    local scale = tonumber(cfg.itemScale) or 1
    if scale <= 0.1 then scale = 1 end

    local spacing = tonumber(cfg.spacing) or 2
    if spacing < 0 then spacing = 0 end

    --[[ `Items:LayoutTraits`: the pitch is the button plus the gap. ]]--
    local pitch = ITEM + spacing

    local width, height = BASE_W, BASE_H

    --[[ Everything below measures from `EDGE`; a deeper border pushes all of
         it in by the same amount. The close button too, or it sits on the
         corner ornament. ]]--
    local inset = self:BorderInset()

    f.close:ClearAllPoints()
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6 - inset, -6 - inset)

    -- ---- the top row ---------------------------------------------------

    for _, b in pairs(f.menu) do b:Hide() end

    local keys = self:MenuList()
    local shown, last = {}, nil

    for i = 1, table.getn(keys) do
        local key = keys[i]
        local b = f.menu[key]

        b:ClearAllPoints()

        if last then
            b:SetPoint("TOPLEFT", last, "TOPRIGHT", MENU_GAP, 0)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + inset, -EDGE - inset)
        end

        --[[ Four of the six are states. A view button lights while you are in
             it, the bag toggle while the strip is out, the search button while
             the box is open. ]]--
        local on = false
        if b.ecoKind == "view" then
            on = (view == key)
        elseif key == "mark" then
            on = self.marking and true or false
        end

        b:SetChecked(on)
        b:Show()

        last = b
        table.insert(shown, b)
    end

    width = width + (MENU * table.getn(shown))

    -- ---- title and search share the row --------------------------------

    self:DrawTitle(f)

    f.title:ClearAllPoints()

    if last then
        f.title:SetPoint("LEFT", last, "RIGHT", 4, 0)
        width = width + (f.title:GetStringWidth() / 2) + 4
    else
        f.title:SetPoint("TOPLEFT", f, "TOPLEFT", EDGE + inset, -EDGE - inset - 4)
        width = width + f.title:GetStringWidth() + EDGE
    end

    --[==[ **The title and the box share the row and both stay.** The title
         says which view this is -- Bank, Keyring, somebody else's bags -- and
         the box is always open, so neither can give the row up to the other:
         the title takes the width it needs and the box takes the rest, up to
         the close button. ]==]
    f.title:SetWidth(0)
    f.title:Show()

    f.search:ClearAllPoints()
    f.search:SetPoint("LEFT", f.title, "RIGHT", 6, 0)
    f.search:SetPoint("RIGHT", f.close, "LEFT", -2, 0)
    f.search:Show()

    width = width + SEARCH_MIN_W

    -- ---- the bag strip -------------------------------------------------

    --[==[ **Where the next row starts, measured down from the window's top.**

         The strip and the grid used to hang off the last top-row button --
         `SetPoint("TOP", last, "BOTTOM")` -- and the comment beside it said
         "centred". It was: on that button. `TOP` fixes the horizontal as well
         as the vertical, so both rows were centred on a twenty-pixel button
         near the left of the title bar and the grid hung a hundred pixels
         past the window's edge. The wider the bag, the further out it went.

         Centred on the window means anchoring to the window, so the vertical
         is carried as a number instead: the same distances the old chain
         produced -- edge, a menu button, a gap; then a strip and a gap when
         there is one -- with nothing to hang off. Every case the old chain
         had (row or no row, strip or no strip) lands on the same pixel. ]==]
    local nextTop = EDGE + inset + ROW_GAP
    if last then nextTop = EDGE + inset + MENU + ROW_GAP end

    --[[ The strip is drawn under the grid now -- see the foot, below. ]]--

    -- ---- the grid ------------------------------------------------------

    local scanned = self:ScanView()
    local cells, lines = self:Grid(scanned, columns)
    local query = self:Query(f.search:IsShown() and f.search:GetText() or "")

    --[[ Centred on the window, because the window is often wider than the
         squares -- and on the *window*, not on whatever sat above it; see the
         note at the bag strip. ]]--
    f.grid:ClearAllPoints()
    f.grid:SetPoint("TOP", f, "TOP", 0, -nextTop)

    local total = table.getn(cells)

    for index = 1, total do
        local cell = cells[index]
        local row = cell.row
        local b = self:Button(index)

        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f.grid, "TOPLEFT",
                pitch * cell.x, -pitch * cell.y)
        b:SetScale(scale)

        b.bag, b.slot = row.bag, row.slot
        b.link, b.itemId = row.link, row.id
        b.gridIndex = index

        --[[ The empty slot's artwork is the backing for a full slot too, so it
             is a setting rather than a consequence of being empty. ]]--
        if cfg.slotBackground then
            b.bg:SetTexture(EMPTY_SLOT)
        else
            b.bg:SetTexture(0, 0, 0, 0.35)
        end

        --[[ The icon inside the ring, written here rather than at build time
             because how far in it sits is a setting. ]]--
        self:PlaceSlotIcon(b)

        --[[ The cooldown, on both branches: an emptied slot that keeps the
             sweep from whatever used to be in it is a square counting down for
             nothing. ]]--
        self:DrawSlotCooldown(b, row)

        if row.empty then
            self:PaintSlotRing(b, nil)
            b.icon:Hide()
            b.count:SetText("")
            b.junk:Hide()
            b.star:Hide()
        else
            b.icon:SetTexture(row.texture)
            b.icon:Show()
            b.count:SetText((row.count or 1) > 1 and row.count or "")

            local quality = self:RowQuality(row)

            --[==[ **The ring and the glow in the item's colour, exactly as the
                 paper doll draws them** -- through the same code, under the
                 character panel's settings. See `PaintSlotRing`. ]==]
            self:PaintSlotRing(b, quality)

            if cfg.glowPoor and quality == 0 then
                b.junk:Show()
            else
                b.junk:Hide()
            end

            if self:IsFavourite(row.id) then b.star:Show() else b.star:Hide() end
        end

        --[[ A search dims what does not match and leaves it where it is. ]]--
        if self:Matches(row, query) then
            b:SetAlpha(1)
        else
            b:SetAlpha(0.3)
        end

        b:Show()
    end

    for index = total + 1, table.getn(f.buttons) do f.buttons[index]:Hide() end

    --[[ A redraw under the mouse hands the buttons round again; the lit set
         follows the bag, not the buttons. ]]--
    if f.litBag then self:HighlightBag(f.litBag) end

    local gridW = columns * pitch * scale
    local gridH = lines * pitch * scale
    if gridH < pitch then gridH = pitch end

    f.grid:SetWidth(gridW)
    f.grid:SetHeight(gridH)

    if gridW > width then width = gridW end
    height = height + gridH

    -- ---- the foot: bags on the left, money on the right ----------------

    --[==[ **The bags you are wearing, always, bottom left.**

         They were a strip above the grid that started hidden and arrived from
         a button -- Bagnon's arrangement, and a control surface nobody could
         find. Under the grid they are where the client's own bag bar is and
         where somebody drops a new bag; on the left because the money is on
         the right, and the two together make one row rather than two.

         Not while looking at somebody else's bags: those are not bags you are
         wearing, and a strip that toggled *your* bags out of *their* grid
         would be answering the wrong question. ]==]
    local footH = 0
    local footW = 0

    if view ~= "players" then
        local n = (LAST_BAG - FIRST_BAG) + 1
        local stripW = ((n - 1) * BAG_PITCH) + BAG_BUTTON

        f.bagStrip:SetWidth(stripW)
        f.bagStrip:ClearAllPoints()
        f.bagStrip:SetPoint("TOPLEFT", f.grid, "BOTTOMLEFT", 0, -FOOT_GAP)
        f.bagStrip:Show()
        self:DrawBagSlots(f)

        footW = footW + stripW
        if BAG_BUTTON + FOOT_GAP > footH then footH = BAG_BUTTON + FOOT_GAP end
    else
        f.bagStrip:Hide()
    end

    if cfg.money then
        f.money:ClearAllPoints()
        f.money:SetPoint("TOPRIGHT", f.grid, "BOTTOMRIGHT", MONEY_GAP, 0)
        f.money:Show()

        footW = footW + MONEY_W
        if MONEY_H > footH then footH = MONEY_H end
    else
        f.money:Hide()
    end

    if footW > width then width = footW end
    height = height + footH

    self:DrawMoney(f)

    -- ---- the window itself ---------------------------------------------

    if width < MIN_BODY then width = MIN_BODY end

    f:SetWidth(width + FRAME_PAD + (inset * 2))
    f:SetHeight(height + (inset * 2))

    --[==[ **The border is one of the four styles, and the background is a
         colour.** Read every redraw, so both take effect while the window is
         open -- and applied *after* the window has its size, because
         `OB.BorderEdge` narrows the edge to fit the frame it is asked about.
         Asked before the resize it measured the 36-pixel placeholder and
         narrowed the Blizzard edge to fit that, for the one draw until the
         next redraw put it right. `None` keeps the fill and drops the
         edge. ]==]
    self:StyleWindow(f)

    return true
end

--[==[ **A slot on cooldown, darkened the way the action bar darkens one.**

     A healthstone that cannot be used yet looks exactly like one that can, and
     the client already draws the answer everywhere else: the `Cooldown` frame
     shades the icon and sweeps a clock across it.

     `GetContainerItemCooldown` is the container's own version of the call the
     action bar reads, and `CooldownFrame_SetTimer` is the client's own driver --
     so a bag slot counts down in exactly the way a spell does rather than in a
     way this addon invented.

     Guarded call by call: a fork without the container cooldown call, or
     without the template this frame is built from, gets a slot with no sweep
     rather than an error in the middle of a redraw. ]==]
function M:DrawSlotCooldown(b, row)
    local cd = b and b.cooldown
    if not cd then return false end

    if not row or row.empty or not row.bag or not row.slot
            or type(GetContainerItemCooldown) ~= "function"
            or type(CooldownFrame_SetTimer) ~= "function" then
        if cd.Hide then cd:Hide() end
        return false
    end

    local start, duration, enable = GetContainerItemCooldown(row.bag, row.slot)

    --[[ A duration of nought is the client saying "nothing is running", which
         is not the same as a cooldown of no length -- handing that to the
         driver leaves a permanently dark icon on 1.12. ]]--
    if not start or not duration or duration <= 0 then
        if cd.Hide then cd:Hide() end
        return false
    end

    if cd.Show then cd:Show() end
    CooldownFrame_SetTimer(cd, start, duration, enable or 1)

    return true
end

--[==[ **Which bags are worn, drawn from the paperdoll.**

     `ContainerIDToInventoryID` is the client's own translation from a container
     number to the equipment slot it hangs in; the backpack has no slot, because
     it is not a bag you can take off. So it gets the client's backpack art and
     the other four get whatever is actually in them, or the empty bag slot
     texture where there is nothing. ]==]
function M:BagSlotTexture(id)
    if id == FIRST_BAG then return BACKPACK end
    if type(ContainerIDToInventoryID) ~= "function" then return EMPTY_BAG end

    local slot = ContainerIDToInventoryID(id)
    if not slot then return EMPTY_BAG end

    if type(GetInventoryItemTexture) == "function" then
        local texture = GetInventoryItemTexture("player", slot)
        if texture then return texture end
    end

    return EMPTY_BAG
end

function M:DrawBagSlots(f)
    if not f or not f.bagSlots then return false end

    for id = FIRST_BAG, LAST_BAG do
        local b = f.bagSlots[id]

        if b then
            b.icon:SetTexture(self:BagSlotTexture(id))

            --[[ Checked means "in the grid", which is the state the button is
                 for. Bagnon's bag buttons are check buttons for exactly this
                 reason: clicking one takes its bag out of the view. ]]--
            b:SetChecked(not self:BagHidden(id))

            --[[ A slot with no bag in it is dimmed rather than hidden. The row
                 is also how many bags you *could* be wearing, and a gap that
                 closes up cannot say that. ]]--
            local slots = type(GetContainerNumSlots) == "function"
                    and GetContainerNumSlots(id) or 0

            b:SetAlpha((slots or 0) > 0 and 1 or 0.35)
        end
    end

    return true
end

--[==[ **Clicking a bag button.**

     Two gestures on one control, told apart by whether the cursor is carrying
     anything. Empty-handed it hides that bag from the grid, which is what
     Bagnon's does. Holding a bag it puts it in the slot, which is what the
     character sheet's does -- and this window is the one already open when a
     bag is looted. ]==]
function M:ClickBagButton(id)
    if CursorHasItem and CursorHasItem() then return self:ClickBagSlot(id) end

    self:SetBagHidden(id, not self:BagHidden(id))
    self:Draw()
    return true
end

--[[ The client's own gesture: whatever is on the cursor goes in the slot, and
     nothing on the cursor picks the bag up. The backpack cannot be taken off,
     so it only accepts. ]]--
--[==[ **Hovering a worn bag lights the slots that are in it.**

     Bagnon's `BagSlot:OnEnter` does this, and it answers the one question
     the grid cannot otherwise answer: which of these sixty squares are in
     *that* bag. Lit with each slot's own highlight, locked on -- the
     client's `ButtonHilight-Square`, the same light the mouse puts on a
     slot -- so the row reads as "these, as though hovered" rather than as a
     new colour with a meaning to learn. `nil` puts every light out. ]==]
function M:HighlightBag(id)
    local f = self:Frame()
    f.litBag = id

    for i = 1, table.getn(f.buttons or {}) do
        local b = f.buttons[i]

        if id and b.bag == id and b:IsShown() then
            if b.LockHighlight then b:LockHighlight() end
        elseif b.UnlockHighlight then
            b:UnlockHighlight()
        end
    end

    return true
end

function M:ClickBagSlot(id)
    if id == FIRST_BAG then
        if type(PutItemInBackpack) == "function" then PutItemInBackpack() end
        return true
    end

    if type(ContainerIDToInventoryID) ~= "function" then return false end
    local slot = ContainerIDToInventoryID(id)
    if not slot then return false end

    if CursorHasItem and CursorHasItem() then
        if type(PutItemInBag) == "function" then PutItemInBag(slot) end
    elseif type(PickupBagFromSlot) == "function" then
        PickupBagFromSlot(slot)
    end

    self:Refresh()
    return true
end

function M:BagSlotTooltip(button)
    if not GameTooltip or not button then return false end

    local id = button.ecoBag
    OB.OwnTooltip(button, "ANCHOR_RIGHT")

    if id == FIRST_BAG then
        GameTooltip:SetText("Backpack")
        GameTooltip:Show()
        return true
    end

    local slot = type(ContainerIDToInventoryID) == "function"
            and ContainerIDToInventoryID(id) or nil

    if slot and GameTooltip.SetInventoryItem
            and GetInventoryItemTexture
            and GetInventoryItemTexture("player", slot) then
        GameTooltip:SetInventoryItem("player", slot)
    else
        GameTooltip:SetText("Empty Bag Slot")
    end

    GameTooltip:Show()
    return true
end

function M:Toggle()
    local f = self:Frame()

    if f:IsShown() then
        f:Hide()
        return false
    end

    f:Show()
    return true
end

--[==[ **The window was built and nothing ever opened it.**

     Every bag key in the client -- B, the bag buttons on the menu bar, a vendor
     opening your bags for you -- goes through the handful of globals in
     `ContainerFrame.lua`, and none of them had been touched. So this module
     drew a combined window that only `/bags` could reach, and pressing B still
     opened the client's five separate frames. It was not that the merge was
     broken; it was that the merge was never what you were looking at.

     Taken by replacing the globals rather than by hiding the frames afterwards.
     Hiding is a race -- the client shows a frame, this hides it, and what you
     see is a flicker -- and it also loses `IsBagOpen`, which the menu bar reads
     to decide whether the backpack button is pressed in.

     The originals are kept and called when this module is switched off, so the
     switch on the Modules page really does give the client its bags back
     without a reload. ]==]
local BAG_GLOBALS = { "ToggleBackpack", "OpenBackpack", "CloseBackpack",
                      "ToggleBag", "OpenBag", "CloseBag",
                      "OpenAllBags", "CloseAllBags", "ToggleKeyRing",
                      "IsBagOpen" }

--[[ Which view a container number belongs to. The client's numbering is the
     only thing that says what a container is -- see `VIEW_BANK` above. ]]--
local function viewFor(id)
    id = tonumber(id)
    if not id then return "bags" end
    if id == -2 then return "keyring" end
    if id == -1 or id >= 5 then return "bank" end
    return "bags"
end

function M:Owns()
    return self.bagHooks and OB.ModuleEnabled("bags") and true or false
end

--[[ Whatever the client managed to open before this module took over, and the
     bank's own frames, which the client opens on your behalf. ]]--
function M:HideContainers()
    local count = tonumber(NUM_CONTAINER_FRAMES) or 12

    for i = 1, count do
        local frame = getglobal("ContainerFrame" .. i)
        if frame and frame.IsShown and frame:IsShown() then frame:Hide() end
    end

    return true
end

--[[ The menu bar draws its bag buttons pressed in while a bag is open, and it
     learns that from `ContainerFrame_OnHide` -- which no longer runs. Set here
     instead, or the buttons stay stuck in whatever state they were last left. ]]--
function M:SyncBagButtons(open)
    local backpack = getglobal("MainMenuBarBackpackButton")
    if backpack and backpack.SetChecked then backpack:SetChecked(open and 1 or 0) end

    for id = FIRST_BAG + 1, LAST_BAG do
        local button = getglobal("CharacterBag" .. (id - 1) .. "Slot")
        if button and button.SetChecked then button:SetChecked(open and 1 or 0) end
    end

    return true
end

function M:Open(view)
    local f = self:Frame()

    if view then self.view = view end
    self:HideContainers()

    if f:IsShown() then self:Draw() else f:Show() end
    self:SyncBagButtons(true)

    return true
end

function M:Close()
    local f = self:Frame()

    if f:IsShown() then f:Hide() end
    self:SyncBagButtons(false)

    return true
end

--[[ Open on the view this container belongs to, or close when that view is
     already what is in front of you -- which is what pressing the key you are
     already looking at should do. ]]--
function M:ToggleView(view)
    local f = self.frame

    if f and f:IsShown() and self:View() == view then return self:Close() end
    return self:Open(view)
end

--[==[ **Bag addons that take the same ten globals this module takes.**

     Bagshui remaps `ToggleBackpack` and `OpenAllBags` to its own toggle; Bagnon
     replaces the set outright, and this module is a port of it. Only the ones
     verified to take the door are listed -- a name here means "steps back",
     and stepping back from an addon that would have coexisted fine is its own
     bug. ]==]
local OTHER_BAG_ADDONS = { "Bagshui", "Bagnon" }

--[[ The first of those that is actually loaded, or nil. A disabled addon
     cannot take a key. ]]--
function M:OtherBagAddon()
    if type(IsAddOnLoaded) ~= "function" then return nil end

    for i = 1, table.getn(OTHER_BAG_ADDONS) do
        if IsAddOnLoaded(OTHER_BAG_ADDONS[i]) then return OTHER_BAG_ADDONS[i] end
    end

    return nil
end

function M:InstallBagHooks()
    if self.bagHooks then return false end

    --[==[ **Another bag addon already has the key, and keeps it.**

         Two owners of one door: B opened both windows, one over the other, and
         the pair read as a broken layout when it was two layouts. Whichever
         loaded last won some of the ten calls and lost the rest, and nothing
         said why -- the report was a screenshot with both windows in it.

         So this steps back. Somebody who installed a bag addon wants it on the
         key. This window is still one click away: the backpack button on the
         action bar calls `Toggle` directly and never goes through the key, so
         it opens exactly one window. Disabling the other addon and reloading
         hands the key back here, and `/eq doctor` says who has it. ]==]
    local other = self:OtherBagAddon()
    if other then
        self.bagKeyOwner = other
        return false
    end
    self.bagKeyOwner = nil

    --[[ All of them or none. A half-taken set is the worst outcome available:
         the backpack opens this window and bag three opens a client frame on
         top of it, and nothing says why. ]]--
    for i = 1, table.getn(BAG_GLOBALS) do
        if type(getglobal(BAG_GLOBALS[i])) ~= "function" then return false end
    end

    local blizzard = {}
    for i = 1, table.getn(BAG_GLOBALS) do
        blizzard[BAG_GLOBALS[i]] = getglobal(BAG_GLOBALS[i])
    end

    self.blizzardBags = blizzard
    self.bagHooks = true

    --[==[ **Resolved through the live global, not through this file's `OB`.**

         `OB` is an upvalue captured when the file loaded. That is the same table
         for the whole of a session in the game -- but not under test, where the
         addon is booted repeatedly into one Lua state, and not if anything ever
         reloads this file. A wrapper installed by an earlier boot would keep
         answering from the earlier boot's modules and profile, so a bag module
         switched off in the *current* one would go on swallowing the call.

         Read from the global by name at call time, so there is exactly one
         module this can mean: whichever one is loaded now. ]==]
    local function mine()
        local root = EquadisClassicOverhaul
        local m = root and root.modules and root.modules.bags

        if m and m:Owns() then return m end
        return nil
    end

    ToggleBackpack = function()
        local m = mine()
        if not m then return blizzard.ToggleBackpack() end
        return m:ToggleView("bags")
    end

    OpenBackpack = function()
        local m = mine()
        if not m then return blizzard.OpenBackpack() end
        return m:Open("bags")
    end

    CloseBackpack = function()
        local m = mine()
        if not m then return blizzard.CloseBackpack() end
        return m:Close()
    end

    ToggleBag = function(id)
        local m = mine()
        if not m then return blizzard.ToggleBag(id) end
        return m:ToggleView(viewFor(id))
    end

    OpenBag = function(id)
        local m = mine()
        if not m then return blizzard.OpenBag(id) end
        return m:Open(viewFor(id))
    end

    CloseBag = function(id)
        local m = mine()
        if not m then return blizzard.CloseBag(id) end
        return m:Close()
    end

    --[[ `forceOpen` is the client's own argument and it is the interesting one:
         a vendor or the bank opens your bags *for* you and must not close them
         because they happened to be open already. ]]--
    OpenAllBags = function(forceOpen)
        local m = mine()
        if not m then return blizzard.OpenAllBags(forceOpen) end
        if forceOpen then return m:Open("bags") end
        return m:ToggleView("bags")
    end

    CloseAllBags = function()
        local m = mine()
        if not m then return blizzard.CloseAllBags() end
        return m:Close()
    end

    ToggleKeyRing = function()
        local m = mine()
        if not m then return blizzard.ToggleKeyRing() end
        return m:ToggleView("keyring")
    end

    --[==[ The client returns *which* of its twelve frames holds that container,
         and every caller in FrameXML uses it as a yes or no. There is one frame
         here and it is the first one, so one is the honest answer -- and nil
         when this window is shut or looking somewhere else. ]==]
    IsBagOpen = function(id)
        local m = mine()
        if not m then return blizzard.IsBagOpen(id) end

        if not m.frame or not m.frame:IsShown() then return nil end
        if m:View() ~= viewFor(id) then return nil end

        return 1
    end

    return true
end

function M:OnBind()
    self:InstallProtection()
    self:InstallBagHooks()
    self:Refresh()
end

--[[ Switched off mid-session, the client's own bags come back -- the wrappers
     stay in place and fall through, which is what `Owns` is for. What does not
     come back on its own is this window, which would otherwise be left on
     screen with nothing able to close it. ]]--
function M:OnUnbind()
    if self.frame and self.frame:IsShown() then self.frame:Hide() end
    self:SyncBagButtons(false)
end

--[==[ **The window says what it is looking at, and when that was true.**

     A bank drawn from memory looks exactly like a bank drawn from the bank, and
     the difference matters: one of them is what is there and the other is what
     was there when you last stood at it. ]==]
--[==[ **The content never sits on the ornament now, so it never has to
     move for it.**

     It did: the Blizzard edge was drawn *on* the window, inward from its
     boundary, so the ornament lay over the first eleven pixels of the fill
     and everything inside was pushed in to clear it, and the window grown to
     pay for that. With the edge hung outside the window -- see `StyleWindow`
     -- the ornament frames the fill instead of covering it, and `EDGE` is the
     whole of the margin again. Kept as a function because the layout asks
     it in eight places, and an answer of nought is the cheapest change to
     eight places there is. ]==]
function M:BorderInset()
    return 0
end

--[==[ **The fill on the window and the edge on a frame of its own, hung
     `outset` outside it** -- the way the cast bar and the tooltip wear theirs,
     and for the same fault.

     Both were on one backdrop. A backdrop draws its edge inward from the
     frame's boundary, and where the ink sits in that band is the art's own
     business: the Thin line is the outermost pixel, the Classic tooltip
     edge's ink runs from the second pixel to the fifth, the Blizzard
     ornament from the fourth to the fourteenth. The fill, meanwhile, stops
     wherever `insets` say. So Thin left a transparent pixel between line
     and fill, Classic had the fill running out under the edge and showing
     through its transparent first column -- the leak the cast bar was fixed
     for -- and Blizzard's fill and ornament overlapped by two.

     `outset` is where the ink's inner end is, measured off the files
     (`OB.borderEdges`). A border frame hung that far outside the window
     lands the ink against the fill's boundary: no gap, no leak, and nothing
     of the window under the ornament. The fill is flush to the frame with
     no insets at all, because the frame's edge *is* where the fill should
     stop. ]==]
function M:StyleWindow(f)
    local cfg = self:Config()
    local look = OB.Look("bags")
    local ground = cfg.color or { 0, 0, 0, 0.5 }

    if not f.ecoGround then
        f:SetBackdrop({
            bgFile = OB.backdrop and OB.backdrop.bgFile
                    or "Interface\\Buttons\\WHITE8X8",
            tile = false,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        f.ecoGround = true
    end

    f:SetBackdropColor(ground[1] or 0, ground[2] or 0, ground[3] or 0,
            ground[4] or 0.5)

    if not f.border then
        f.border = CreateFrame("Frame", nil, f)
    end

    local border = f.border
    local edge = OB.BorderEdge(tonumber(look.border) or 2,
            f:GetWidth(), f:GetHeight())

    if not edge or not edge.edgeFile then
        border:SetBackdrop(nil)
        border:Hide()
        border.ecoKey = nil
        return true
    end

    local size = tonumber(edge.edgeSize) or 8
    local pad = math.floor(tonumber(edge.outset) or (size / 2))
    if pad < 1 then pad = 1 end

    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", pad, -pad)

    --[[ Only when it changed: `SetBackdrop` rebuilds nine textures. Only the
         edge, and no insets: there is no background on this frame for them
         to hold off anything. ]]--
    local key = tostring(edge.edgeFile) .. ":" .. tostring(size)

    if border.ecoKey ~= key then
        border:SetBackdrop({
            edgeFile = edge.edgeFile,
            edgeSize = size,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        border.ecoKey = key
    end

    --[[ Level re-asserted every pass, as the cast bar does: the ink is
         outside the window and covers nothing, and the band inside it is
         transparent, so it only has to be above the fill. ]]--
    if border.SetFrameLevel and f.GetFrameLevel then
        border:SetFrameLevel((f:GetFrameLevel() or 0) + 1)
    end

    border:SetBackdropBorderColor(1, 1, 1, 1)
    border:Show()

    return true
end

function M:DrawTitle(f)
    local view = self:View()
    local who = type(UnitName) == "function" and UnitName("player") or nil
    local mine = who and (who .. "'s ") or ""

    if view == "keyring" then
        f.title:SetText(mine .. "Keyring")
    elseif view == "players" then
        local n = table.getn(self:OtherCharacters())
        f.title:SetText("Other Characters (" .. n .. ")")
    elseif view == "bank" then
        f.title:SetText(mine .. (self.bankOpen and "Bank" or "Bank (remembered)"))
    else
        f.title:SetText(mine .. "Inventory")
    end
end

function M:DrawMoney(f)
    if not f.coins then return end

    if not self:Config().money or type(GetMoney) ~= "function" then
        f.coins.gold:SetText("")
        f.coins.silver:SetText("")
        f.coins.copper:SetText("")
        return
    end

    local copper = GetMoney() or 0
    local gold = floor(copper / 10000)
    local silver = floor((copper - (gold * 10000)) / 100)
    local bronze = copper - (gold * 10000) - (silver * 100)

    f.coins.gold:SetText(gold)
    f.coins.silver:SetText(silver)
    f.coins.copper:SetText(bronze)
end

function M:OnEvent()
    --[[ Whichever container the client just told us about, the remembered copy
         is now out of date. Recorded before the redraw so the Alts view of this
         character is never older than the window in front of it. ]]--
    if event == "BANKFRAME_OPENED" then self.bankOpen = true end
    if event == "BANKFRAME_CLOSED" then self.bankOpen = nil end

    if self.bankOpen then self:RememberBank() end

    if event == "BAG_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        self:RememberBags()
    end

    --[[ A move landing is what drives the next one -- and a lock clearing is
         the other half of a move landing. Either is the client saying the
         bags changed, which is what a pass waits to hear. ]]--
    if event == "BAG_UPDATE" or event == "ITEM_LOCK_CHANGED" then
        if self.sorting then self.bagUpdated = true end
        self:ContinueRun()
    end

    self:Refresh()
end

function M:OnStyle()
    self:Refresh()
end

function M:OnDraw() end
