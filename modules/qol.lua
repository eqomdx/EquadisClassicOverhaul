--[[ Equadis' Classic Overhaul :: quality of life

  **The small things, which are small individually and are the reason people run
  eight addons.**

  Nothing here is a subsystem. There is no window, no bar and no data model --
  each of these is one behaviour the client does not have, and the only thing
  they share is that none of them is worth an addon of its own. That is exactly
  what makes them worth one tab of a bundle.

  Every one is off by default. A quality-of-life change nobody switched on is a
  surprise, and several of these touch things -- your camera, your tooltips --
  that somebody may already have set up the way they like.

  First slice: the ones that only read and decorate. Nothing here destroys an
  item, cancels a buff or reparents a Blizzard frame; those come later and each
  deserves its own set of tests.
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "QoL") end

local M = OB.RegisterModule({
    id = "qol",
    name = "Automation",

    feature = true,
    renders = "none",

    --[[ On, because the module itself does nothing: every behaviour inside it
         has its own switch and every one of those is off. Leaving the module
         disabled as well would mean two switches to reach one setting. ]]--
    defaultEnabled = true,

    defaults = {
        --[[ **Camera speed**, which is a CVar the client ships with no interface
             for. 180 is the default; the slider covers half to triple.

             Stored as the number rather than a multiplier, so what the panel
             shows is what the CVar holds and a bug report can be read. ]]--
        --[[ **The framerate readout, on at every login.** The client has one and
             forgets it every time, so somebody who wants to see it wants to see
             it again after every reload. Off, because it is one more thing on
             screen and the people who want it know they do. ]]--

        --[==[ **A macro icon you chose is never resolved away, and there is no
             switch for it.**

             The switch's own note gave the reason to delete it: an icon somebody
             picked is an instruction, and *a question mark is how you ask for
             the other behaviour*. The other behaviour was already reachable
             without leaving the game, so the row was a second way to say
             something the macro editor says better. See `InstallMacroIcons`. ]==]

        --[[ On. A full bag is forty grey squares and the one blue item in it is
             the only thing worth finding at a glance. ]]--
        rarityBorders = true,

        cameraSpeed = false,
        cameraYaw = 180,

        --[[ **Turning the character model by dragging it.**

         1.12 has two arrow buttons under the model and nothing else -- so
         looking at the back of your own gear is a matter of clicking one of them
         repeatedly. The model has known how to face any direction the whole
         time; there has simply never been a way to ask it directly. ]]--
        modelRotate = true,

        --[[ Radians per pixel of drag. A tenth of a degree per pixel means a
         drag across the model box is most of a turn, which is what makes it
         feel like the model is under the cursor rather than geared to it. ]]--
        modelRotateSpeed = 0.010,

        --[[ **Vendors.**

             Two chores nobody has ever enjoyed: paying the repair bill and
             emptying a bag of grey items one right-click at a time. Both are
             entirely mechanical, both are safe -- a repair is money you owed
             anyway and a sale can be bought back -- and neither is something the
             client will ever do for you. ]]--
        autoRepair = false,

        --[[ A ceiling, in gold, above which it asks nothing and does nothing.

             Not a hedge: repair costs are what they are and you pay them
             eventually. It is for the case where you are nearly broke and a full
             set of epics wants forty gold -- being emptied without warning at
             the wrong moment is the one way an automatic repair can hurt.

             Zero means no ceiling, which is what most people want once they
             have any money at all. ]]--
        repairLimit = 0,

        --[[ Grey items only. Not a setting, because "sell my whites too" is how
             people vendor their alt's heirloom, and the ones worth selling that
             are not grey are exactly the ones worth thinking about. Anything
             else goes on the list below, by name, deliberately. ]]--
        autoSell = false,

        --[[ On. The buttons are the version of this that does not decide
             anything for you: they sit there until pressed. ]]--
        vendorButtons = true,

        --[[ On, and worth having on: something that spends and earns money on
             your behalf should say what it did. The one line it prints is the
             difference between trusting it and checking your bags. ]]--
        vendorReport = true,

        --[[ **The never-keep list**, which is the only thing in this addon that
             destroys anything.

             Off, and off is not a formality here. Everything else in this file
             can be undone: a repair is money you owed, a sale has a buyback
             window, a camera setting is a number. A destroyed item is gone, and
             no amount of care in the code changes that.

             The list itself is account-wide and lives outside the profile -- see
             config.lua. What is here is only the switch. ]]--
        autoTrash = false,

        --[[ **"Are you sure?" on something you already decided.**

             Rolling Need or Greed on a bind-on-pickup item raises a
             confirmation, and destroying an item raises another. Both appear
             *after* the decision has been made and the button pressed, and both
             are dismissed with the same click every time -- which is what makes
             them a keystroke rather than a safeguard.

             The roll is on by default. There is nothing to lose: the dialog
             confirms a choice you made by clicking Need on a specific item, and
             the only thing behind it is one more click on a timer that is
             already running down. ]]--
        confirmRoll = true,

        --[==[ **Both off, because both move you.**

             A summon takes you across the world and a resurrection decides
             where you stand up. Neither is a confirmation of something you just
             did -- they are offers from somebody else, arriving when you may be
             reading something, in a fight, or halfway through a corpse run.

             Every other automation in this module undoes a click you already
             made. These two make a decision on your behalf, which is a
             different kind of thing and gets the other default. ]==]
        autoAcceptSummon = false,
        autoAcceptRevive = false,

        --[[ **Destroying is off by default, and the two dialogs are not the
             same dialog.**

             `DELETE_ITEM` is the plain one, for ordinary items. Auto-accepting
             it is a convenience.

             `DELETE_GOOD_ITEM` is the one that makes you type DELETE, and the
             client raises it *only* for rare quality and above. That typing is
             not a formality somebody forgot to remove -- it is the guard that
             stands between a misclick and an epic. Skipping it is offered
             because somebody clearing a bank may genuinely want it, and it is
             off by default and named for what it does, because a setting that
             quietly destroys a rare item is not a quality-of-life feature. ]]--
        confirmDestroy = false,
        confirmDestroyGood = false,

        --[[ **Zone level ranges have moved to the Map module**, which is where
             they always belonged -- they arrived here because this is where
             quality-of-life things went and there was no map page to put them
             on. Migration 25 carried the two saved keys across under the same
             names. The code that draws them is still below, because it hangs
             off the same world map hook everything else here does; only the
             settings moved. ]]--

        --[[ **Right-clicking a mob should not start an auto-attack.**

             1.12 has no setting for this and it is the single most common way to
             pull something you were not ready for: you right-click to turn the
             camera, the cursor passes over a mob, and you are in combat with it.
             A rogue loses stealth, a hunter loses distance, and everybody loses
             the pull they were setting up.

             Off, because it *is* how a lot of people attack -- but it is one of
             the first things anybody who has been caught by it goes looking
             for. ]]--
        noRightClickAttack = false,

        --[[ **Dismount when you cast something.**

             1.12 will not do this and it is the single most common way to waste
             three seconds: you press a spell, the client says "You are mounted",
             you press the mount, you press the spell again.

             Off, because it hooks the casting calls and anything in that path is
             a decision -- particularly next to a bar addon. ]]--
        dismount = false,

        --[[ **Destroy grey items below a value.**

             The rule is as simple as it sounds -- grey, and worth less than this,
             so it goes. What is not simple is the *value*: see `OB.SellValue`.
             1.12 will only tell you what something sells for while you are
             standing at a vendor, which is exactly where you do not need to
             know.

             So this destroys nothing whose price it has not learned. Not a
             fallback, a refusal: guessing at the value of something before
             destroying it is the one thing this must never do. ]]--
        trashJunk = false,

        --[[ In silver. Most grey drops are worth a few, so the useful range is
             small and the slider says silver rather than copper to keep the
             number readable. ]]--
        junkValue = 5,

        --[[ **Handing quests in without reading them**, from QuestHaste by
             WobLight (MIT -- see NOTICE).

             The case it is built for is the repeatable: an Alterac Valley
             turn-in you have read forty times, four clicks each. The design that
             makes it safe is that it is **per quest** -- you tell it which ones
             you have finished reading, and it leaves everything else alone. ]]--
        questHaste = false,

        --[[ Every quest, not just remembered ones. Off, and it should stay off
             for anybody levelling: the first read of a quest is the only chance
             to notice it is the wrong one. On, it is a repeatables machine. ]]--
        questAll = false,

        --[[ **The mob tooltip, which is named and not yet written.**

             Both off, and both rows on the page are dimmed -- see the options
             list below. They are declared here rather than left out so the page
             has something real to read and write the day the functions land, and
             so a profile saved now does not gain two settings later and call it
             a change.

             `tipLevelColor` colours the level line the client already wrote,
             rather than adding a second copy of it in a different colour.
             `tipFlee` adds a line, because whether a thing runs at low health is
             new information rather than a restatement. ]]--
        tipLevelColor = false,
        tipFlee = false,
    },

    options = {
        --[[ **Metrics has gone with the row it held.** It was one section for
             one switch -- and not even a metric: Keep Chosen Macro Icons had
             been filed here, under a heading left over from a framerate readout
             that lives on the Action Bars page now. Emptying it made the
             misfiling visible, which is the argument for emptying things. ]]--

        { "Camera", "__s_camera", "section", "camera" },


        { "Set Camera Turn Speed", "cameraSpeed", "boolean" },
        { "Turn Speed", "cameraYaw", "slider", 90, 540, 10,
          nil, nil, "!cameraSpeed" },

        { "Vendors", "__s_vendor", "section", "vendor" },

        --[[ **The manual pair.** Automatic is an opinion applied to every
             vendor; a button is the same machinery on demand, and plenty of
             people want neither switched on and both available. ]]--
        { "Vendor Buttons", "vendorButtons", "boolean" },

        --[==[ **AutoSell Junk and AutoRepair Equipment used to be listed here**,
             red and permanently greyed, as the roadmap entries planned.lua
             describes.

             They are gone rather than still waiting. Nothing read either key,
             and `__notImplemented` was never a real predicate -- it read as a
             missing config value, which is false, which greyed the rows forever.
             A switch that can never be reached is not a plan somebody can see;
             it is two rows of furniture. The plan belongs in planned.lua, which
             is where it already is.

             The manual pair above does both jobs today: Vendor Buttons sells
             and repairs on demand. ]==]

        { "Never Keep", "__s_trash", "section", "trash" },

        { "Destroy These When They Arrive", "autoTrash", "boolean" },

        --[[ Bound to the saved variables rather than the profile: this is not a
             statement about how your interface looks on this character. See the
             `account` scope. ]]--
        { "Item Names (Comma Separated)", "@account:trash", "text", 200, 250,
          nil, nil, nil, "!autoTrash" },

        { "Destroy Cheap Junk", "trashJunk", "boolean" },
        { "Worth Less Than (Silver)", "junkValue", "slider", 1, 100, 1,
          nil, nil, "!trashJunk" },

        --[[ Trash mode, which is a mode and so says which one it is in. The two
             actions under it are only useful while something is selected, and
             they say how much. ]]--
        { "Choose Items In Your Bags", "__a_select", "action",
          function() OB.modules.qol:SetSelectMode(not OB.modules.qol:SelectMode()) end,
          function()
              if OB.modules.qol:SelectMode() then return "Stop Choosing Items" end
              return "Choose Items In Your Bags"
          end },

        { "Destroy What Is Chosen", "__a_dtrash", "action",
          function() OB.modules.qol:ConfirmDestroySelected() end,
          function()
              local n = table.getn(OB.modules.qol:SelectedItems())
              if n == 0 then return "Destroy What Is Chosen" end
              return "Destroy " .. n .. " Chosen Item" .. (n == 1 and "" or "s")
          end },

        { "Sell What Is Chosen", "__a_dsell", "action",
          function()
              local sold = OB.modules.qol:SellSelected()
              Say(sold > 0 and ("sold " .. sold .. ".")
                      or "nothing sold -- open a vendor first.")
          end },

        --[[ **Listed and dimmed, because the list is the plan.**

             The test suite has carried the whole design of these two for a long
             time -- `qol:ReadLevelLine`, `qol:Flees` and `qol:DecorateTooltip`,
             with every assertion written out -- and the addon has never had a
             line of it. Tests describing a feature nobody can see are a plan
             kept somewhere nobody looks.

             **Built now**, and the rows say so: the red caption and the
             `!__notImplemented` greying are gone, because a switch that works
             and looks disabled is worse than either. What each one has to do is
             in `tests/run.lua` under the mob tooltip sections. ]]--
        { "Item Rarity", "__s_rarity", "section", "rarity" },

        { "Color Item Borders By Rarity", "rarityBorders", "boolean" },

        { "Mob Tooltips", "__s_mobtip", "section", "mobtip" },

        { "Color The Level Line", "tipLevelColor", "boolean" },
        { "Say Whether It Flees", "tipFlee", "boolean" },

        --[[ The two map rows that used to be here are on the Map page now. See
             the note where their defaults were. ]]--

        { "Automatic Loot Rolls", "__s_autoroll", "section", "autoroll" },

        --[[ The box types several at once; the list below reads them back one
             per line and lets one be taken off. Two views of the same string,
             because adding four names and removing the third are different
             gestures and one control cannot be good at both. ]]--
        { "Always Need These (Comma Separated)", "@account:autoNeed", "text",
          200, 250 },
        { "Needing", "__l_need", "lines",
          function() return OB.modules.qol:AutoRollEntries("need") end, 96, nil,
          function(name) OB.modules.qol:RemoveAutoRollItem("need", name) end },

        { "Always Greed These (Comma Separated)", "@account:autoGreed", "text",
          200, 250 },
        { "Greeding", "__l_greed", "lines",
          function() return OB.modules.qol:AutoRollEntries("greed") end, 96, nil,
          function(name) OB.modules.qol:RemoveAutoRollItem("greed", name) end },

        { "Confirmations", "__s_confirm", "section", "confirm" },

        --[[ On: the dialog confirms a choice already made by clicking Need on a
             specific item, and there is a timer running down behind it. ]]--
        { "Skip Need / Greed Confirmation", "confirmRoll", "boolean" },

        { "Group", "__s_group", "section", "group" },
        { "Auto Accept Summon", "autoAcceptSummon", "boolean" },
        { "Auto Accept Revive", "autoAcceptRevive", "boolean" },

        --[[ Off, and the two destroy dialogs are separate rows on purpose --
             see the note on `confirmDestroyGood` in the defaults. ]]--
        { "Skip Destroy Confirmation", "confirmDestroy", "boolean" },
        { "Skip It For Rare Items Too", "confirmDestroyGood", "boolean",
          nil, nil, nil, nil, nil, "!confirmDestroy" },

        { "Attacking", "__s_attack", "section", "attack" },

        { "Do Not Attack On Right Click", "noRightClickAttack", "boolean" },

        { "Mounts", "__s_mount", "section", "mount" },

        { "Dismount To Cast", "dismount", "boolean" },

        { "Quests", "__s_quest", "section", "quest" },

        { "Hand In Remembered Quests", "questHaste", "boolean" },
        { "Every Quest, Not Just Remembered Ones", "questAll", "boolean",
          nil, nil, nil, nil, nil, "!questHaste" },

        --[[ The list is built by Control-clicking quests rather than typed, so
             the panel's job is to say how long it is and to offer the way back.
             A remembered quest is an automatic hand-in, and a list nobody can
             see or empty is a list that eventually surprises somebody. ]]--
        { "List Remembered Quests", "__a_qlist", "action",
          function() OB.PrintQuestList() end,
          function()
              local n = 0
              for _ in pairs(OB.quests) do n = n + 1 end
              if n == 0 then return "No Quests Remembered" end
              return "List " .. n .. " Remembered Quest" .. (n == 1 and "" or "s")
          end },

        { "Forget Every Remembered Quest", "__a_qreset", "action",
          function() OB.ForgetQuests() end },
    },

    events = { "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_UPDATE",
               "ADDON_LOADED",
               "ACTIONBAR_SLOT_CHANGED", "UNIT_INVENTORY_CHANGED",
               "UI_ERROR_MESSAGE", "PLAYERBANKSLOTS_CHANGED",
               "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
               "PLAYER_ENTER_COMBAT",
               "GOSSIP_SHOW", "QUEST_GREETING" },
})

function M:Config()
    return OB.profile.modules.qol
end

-- ---------------------------------------------------------------------------
-- camera
-- ---------------------------------------------------------------------------

--[[ **A CVar with no interface.**

     `cameraYawMoveSpeed` is how fast the camera swings when you turn it, and the
     client ships it at 180 with no way to change it short of typing
     `/console`. Tripling it is the single most-recommended thing in every
     "vanilla feels sluggish" thread, and it has been a one-line fix nobody could
     find for twenty years.

     Only written when the switch is on. **Never written back on the way off**,
     because there is no honest value to restore: whatever it was before might
     have been set by another addon, by a `/console` line in someone's notes, or
     by the client's default, and this module cannot tell those apart. Off means
     "stops changing it", not "puts it back to 180" -- guessing 180 would quietly
     undo a setting somebody made deliberately. ]]--
function M:ApplyCamera()
    local cfg = self:Config()

    if not cfg.cameraSpeed then return end
    if type(SetCVar) ~= "function" then return end

    SetCVar("cameraYawMoveSpeed", cfg.cameraYaw)
end

-- ---------------------------------------------------------------------------
-- vendors
-- ---------------------------------------------------------------------------

--[[ Money, as the client writes it. Copper is dropped once there is gold to
     say, because "12g 40s 3c" is three facts where two were wanted. ]]--
function OB.Money(copper)
    copper = copper or 0

    local gold = math.floor(copper / 10000)
    local silver = math.floor(mod(copper, 10000) / 100)
    local bronze = mod(copper, 100)

    if gold > 0 then return gold .. "g " .. silver .. "s" end
    if silver > 0 then return silver .. "s " .. bronze .. "c" end
    return bronze .. "c"
end

--[[ The colour the client paints a worthless item. Asked of the client where it
     answers, because a server may have restyled its qualities, and only fallen
     back to the literal that has been correct since 2004. ]]--
local function junkColor()
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[0]
            and ITEM_QUALITY_COLORS[0].hex then
        return ITEM_QUALITY_COLORS[0].hex
    end

    return "|cff9d9d9d"
end

--[[ An item's name, out of its link. `|cff9d9d9d|Hitem:1234:0:0:0|h[Broken
     Fang]|h|r` is one string carrying quality, item id and name, and the name is
     the only part with a stable shape. ]]--
local function linkName(link)
    if not link then return nil end

    local _, _, name = string.find(link, "%[(.-)%]")
    return name
end


local function linkItemId(link)
    if not link then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    return tonumber(id)
end

--[[ **Marked for this visit only.**

     The list the panel cannot hold: things you have decided to sell *now*,
     which is a different act from deciding you never want them again. Cleared
     when the merchant window closes, because "this once" is what it means.

     Keyed by lowercased name so typing is forgiving. When the bag selection
     lands it writes into this same table -- the storage is the interface's
     problem, not this list's. ]]--
function M:MarkForSale(name)
    if not name or name == "" then return false end

    self.marked = self.marked or {}
    self.marked[string.lower(name)] = true

    return true
end

function M:ClearMarks()
    self.marked = nil
end

function M:IsMarked(name)
    if not self.marked or not name then return false end
    return self.marked[string.lower(name)] and true or false
end

--[[ Everything in your bags worth handing over: grey by colour, or named on the
     list for this visit.

     Bags 0 to 4 -- the backpack and four bags -- which is every bag a 1.12
     character has. ]]--
--[[ `includeJunk` is the button's doing. The automatic pass only treats grey
     as junk when its own switch is on -- otherwise switching it off would still
     have it selling. A press says "this time", so the button asks for greys
     whatever the switch says, and without this it finds nothing at all and
     looks broken. ]]--
function M:SellableItems(includeJunk)
    local cfg = self:Config()
    local grey = junkColor()
    local out = {}

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0

        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)

            if link then
                local name = linkName(link)
                local isJunk = (includeJunk or cfg.autoSell)
                        and string.find(link, grey, 1, true) == 1

                if isJunk or self:IsMarked(name) then
                    table.insert(out, { bag = bag, slot = slot, name = name })
                end
            end
        end
    end

    return out
end

--[[ **`UseContainerItem` sells only while a merchant window is open. Everywhere
     else it *uses* the item.**

     That is the whole hazard of this feature, and it is not a small one: the
     same call that sells a Broken Fang at a vendor eats your food, opens your
     lockbox and equips your weapon anywhere else. A merchant frame that has
     already closed -- a stray event, a server hiccup, a second addon closing it
     first -- turns "sell my junk" into "use every grey item I own".

     So the check is not "did we get MERCHANT_SHOW", it is "is the window open
     right now", asked immediately before each call rather than once at the top. ]]--
function M:MerchantOpen()
    if not MerchantFrame then return false end
    if not MerchantFrame.IsVisible then return false end

    return MerchantFrame:IsVisible() and true or false
end

function M:SellJunk()
    local cfg = self:Config()
    if not (cfg.autoSell or self.marked) then return 0 end
    if not self:MerchantOpen() then return 0 end

    local items = self:SellableItems()
    local sold = 0

    for i = 1, table.getn(items) do
        --[[ Re-asked every time round. See above: one sale outside a merchant
             window is one item used, and the window can close mid-loop. ]]--
        if not self:MerchantOpen() then break end

        UseContainerItem(items[i].bag, items[i].slot)
        sold = sold + 1
    end

    return sold
end

--[[ The repair bill, paid if it is payable and small enough to be worth not
     asking about.

     Three refusals, and each is a different thing being wrong: the merchant does
     not repair, the bill is over your ceiling, or you cannot afford it. Only the
     middle one is a decision -- the others are facts -- but all three are worth
     saying out loud, because a repair that silently did not happen is a repair
     you find out about when your weapon breaks. ]]--
function M:Repair()
    local cfg = self:Config()
    if not cfg.autoRepair then return nil end
    if not self:MerchantOpen() then return nil end

    if type(CanMerchantRepair) ~= "function" or not CanMerchantRepair() then
        return nil
    end

    local cost = GetRepairAllCost()
    if not cost or cost <= 0 then return nil end

    if cfg.repairLimit > 0 and cost > cfg.repairLimit * 10000 then
        return nil, "over your " .. cfg.repairLimit .. "g limit"
    end

    if (GetMoney() or 0) < cost then
        return nil, "you cannot afford it"
    end

    RepairAllItems()

    return cost
end

-- ---------------------------------------------------------------------------
-- the two buttons a vendor window should have had
-- ---------------------------------------------------------------------------

--[[ **Automatic is not the same as manual, and both are wanted.**

     Auto-sell and auto-repair are opinions applied to every vendor: switch them
     on and they happen whether or not this was the visit you wanted them on.
     Plenty of people want neither on by default and both available on demand --
     sell the junk *this time*, pay the bill *at this vendor* -- which is a
     button, not a setting.

     So the two share their machinery with the automatic pass and differ in one
     way: **a press is consent.** The automatic path refuses on your behalf and
     says why; a button you pressed has already answered the question the
     refusal would have asked.

     The gold ceiling is the clearest case. Automatic repair stops above it,
     because "repair everything, always, whatever it costs" is not what anybody
     means by a convenience. Pressing Repair while looking at the price is the
     opposite: you have seen the number and asked for it anyway. So the ceiling
     is an automatic-only rule. Affordability still stands, because that is not
     an opinion. ]]--
function M:SellJunkNow()
    if not self:MerchantOpen() then return 0 end

    local items = self:SellableItems(true)
    local sold = 0

    for i = 1, table.getn(items) do
        --[[ Re-asked every time round, as the automatic pass does: the window
             can close mid-loop, and one sale outside it is one item used. ]]--
        if not self:MerchantOpen() then break end

        UseContainerItem(items[i].bag, items[i].slot)
        sold = sold + 1
    end

    return sold
end

--[[ Built once and kept, because the merchant window is opened and closed all
     day and a button per visit is a leak with a long fuse. ]]--
--[==[ **One icon, in the row the client already built.**

     This was two text buttons bolted under the merchant window, and the second
     of them duplicated a button the client puts on screen itself: two rows of
     controls doing one row's work, with the pair hanging past the bottom of the
     frame they were attached to.

     The repair button is gone rather than reskinned. The client's own repair-all
     button already does it, already shows the price, and already greys out at a
     merchant who cannot repair -- a second one is a second thing to keep
     correct. Automatic repair is still a setting; it has no button now. ]==]

--[[ Present *and* shown. A merchant who cannot repair has no repair buttons,
     and this client's merchant window is not the stock 1.12 one -- it pages and
     need not put repair where vanilla did. Anchoring to something hidden put
     ours in the same place, which is a button that exists and cannot be
     seen. ]]--
local function usable(name)
    local frame = getglobal(name)
    if not frame or not frame.IsShown or not frame:IsShown() then return nil end
    return frame
end

--[==[ **The gap the client's own row uses**, read rather than written.

     Ours sat four pixels off a pair that sits two apart -- the same size and the
     wrong gap, which reads as one icon slightly adrift. Taken off the two repair
     buttons, so a reskin that respaces that row respaces this too. ]==]
function M:RepairRowGap()
    local item = getglobal("MerchantRepairItemButton")
    if not item or not item.GetPoint then return 2 end

    local point, relative, _, x = item:GetPoint(1)
    if point == "RIGHT" and relative and type(x) == "number" then
        return math.abs(x)
    end

    return 2
end

--[==[ **The repair pair moves left, so the row keeps its place.**

     Ours ends the row, and a row that simply grew rightwards would walk off the
     place the client chose for it. One re-anchor rather than two: the item
     button hangs off All, so moving All moves both and they cannot disagree.

     `repairHome` is captured before anything is moved, so putting it back is
     the client's own anchor rather than whatever we last computed. ]==]
function M:ShiftRepairRow(by)
    local all = getglobal("MerchantRepairAllButton")
    if not all or not all.GetPoint then return false end

    if not self.repairHome then
        local point, relative, relativePoint, x, y = all:GetPoint(1)
        if not point then return false end
        self.repairHome = { point, relative, relativePoint, x, y }
    end

    local home = self.repairHome
    all:ClearAllPoints()
    all:SetPoint(home[1], home[2], home[3], home[4] - (by or 0), home[5])

    return true
end

--[==[ **And the Repair Items label goes, and stays gone.**

     It is what makes room -- the junk button sits where the label used to.
     Hiding it once per update was not enough: `MerchantFrame_UpdateRepairButtons`
     runs after us on the same event and shows it again, so it came back before
     anybody saw it go. The frame's own `Show` is overridden instead, which is
     the only way to win against a caller that runs later than you do. ]==]
function M:HideRepairLabel()
    local label = getglobal("MerchantRepairText")
    if not label or not label.Hide then return false end

    if not label.ecoShow then
        label.ecoShow = label.Show
        label.Show = function() end
    end

    label:Hide()
    return true
end

--[==[ **A tab change is not an event.**

     The buyback tab sends nothing at all -- it calls `MerchantFrame_Update` --
     so a check that keeps this button off that tab ran on `MERCHANT_SHOW` and
     never again. It was right, and it never re-ran. ]==]
function M:HookMerchantUpdate()
    if self.merchantUpdateHooked then return false end
    if type(MerchantFrame_Update) ~= "function" then return false end

    self.merchantUpdateHooked = true
    local original = MerchantFrame_Update

    MerchantFrame_Update = function()
        local result = original()

        local m = OB.modules.qol
        if m then m:UpdateVendorButtons() end

        return result
    end

    return true
end

--[[ The buy tab, which is the only one this button means anything on. Its
     second tab is buyback, where offering to sell junk is one misclick from
     selling something you were about to buy back. ]]--
function M:OnMerchantTab()
    if type(MerchantFrame) ~= "table" then return false end
    local tab = MerchantFrame.selectedTab
    return tab == nil or tab == 1
end

--[==[ **Where the junk button goes, asked every update rather than once.**

     The anchor was chosen when the button was built, and which anchor is right
     depends on whether this merchant repairs -- a question with a different
     answer at the next vendor. Built at a merchant who could not repair, the
     button kept the fallback position for the rest of the session.

     **And the fallback was wrong as well.** It offset by the width of a repair
     pair that was not there, which put the icon out over the money row --
     reported as "not in the correct position on NPCs that do not have repair".
     With no pair to sit beside, ours *is* the row, so it takes the place the
     row would have had: `MerchantRepairAllButton`'s own anchor, read out of the
     client's `MerchantFrame.xml`. ]==]
local REPAIR_HOME_X, REPAIR_HOME_Y = 172, 91

function M:PlaceJunkButton(sell)
    if not sell or not sell.SetPoint then return false end

    local anchor = usable("MerchantRepairAllButton")
            or usable("MerchantRepairItemButton")

    sell:ClearAllPoints()

    if anchor then
        sell:SetPoint("LEFT", anchor, "RIGHT", self:RepairRowGap(), 0)

        --[[ Measured from the button it sits beside, for the reason the builder
             gives: a third button keeping its own size beside two of another is
             the odd one out however good the art is. ]]--
        if anchor.GetWidth and (anchor:GetWidth() or 0) > 0 then
            sell:SetWidth(anchor:GetWidth())
            sell:SetHeight(anchor:GetHeight() or anchor:GetWidth())
        end

        return "row"
    end

    sell:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMLEFT",
            REPAIR_HOME_X, REPAIR_HOME_Y)
    return "alone"
end

function M:VendorButtons()
    if self.vendorButtons then return self.vendorButtons end
    if not CreateFrame or not MerchantFrame then return nil end

    --[==[ Read out of the client's own `MerchantFrame.xml` rather than assumed:
         `MerchantRepairAllButton` is anchored to the frame and
         `MerchantRepairItemButton` hangs off *its* left. So All is the
         right-hand one of the pair, and ours ends the row beside it. ]==]
    local anchor = usable("MerchantRepairAllButton")
            or usable("MerchantRepairItemButton")

    --[==[ **Built from the client's own item-button template.**

         This button was got wrong three times by imitating its neighbours from
         the outside -- `UI-Quickslot2` at the button's own size put the ring
         inside the frame; the neighbour's normal texture copied across still
         came back without the gold border. Each attempt matched one piece of an
         item button and missed another.

         `ItemButtonTemplate` *is* what the repair buttons are, so inheriting it
         cannot be a near miss: border, recessed ground and icon inset arrive
         together, and they match whatever the client's item buttons look like
         even if something has reskinned them.

         Whether it really arrived is asked of the pieces rather than assumed. A
         template the client does not have still returns a frame, and a button
         that believed it was templated would draw no ground and no icon. ]==]
    local name = "EquadisClassicOverhaulSellJunkButton"
    local sell

    local ok, made = pcall(CreateFrame, "Button", name, MerchantFrame,
            "ItemButtonTemplate")
    if ok and made then sell = made end

    if sell and getglobal(name .. "IconTexture") then
        sell.templated = true
        sell.icon = getglobal(name .. "IconTexture")
        sell.count = getglobal(name .. "Count")
    else
        --[[ The template did not take. Whatever it left behind is unusable as a
             half-built item button, so the pieces are made by hand. ]]--
        if sell then sell:Hide() end
        sell = CreateFrame("Button", name, MerchantFrame)
        sell.templated = false
    end

    --[[ Measured from the button it sits beside rather than from a fixed
         thirty-six, which is the stock size and stops being right the moment
         anything reskins the window. A third button keeping its own size beside
         two of another is the odd one out however good the art is. ]]--
    local size = 36
    if anchor and anchor.GetWidth and (anchor:GetWidth() or 0) > 0 then
        size = anchor:GetWidth()
    end

    sell:SetWidth(size)
    sell:SetHeight(anchor and anchor.GetHeight and anchor:GetHeight() or size)

    self:PlaceJunkButton(sell)

    if not sell.templated then
        --[==[ The dustbin is about seven tenths opaque -- it has to be, or it
             would be a square rather than a bin -- so without a ground the
             window shows through its corners and it reads as a smudge. The
             template supplies one; this path has to make it. ]==]
        sell.bg = sell:CreateTexture(nil, "BACKGROUND")
        sell.bg:SetAllPoints(sell)
        sell.bg:SetTexture(1, 1, 1, 1)
        sell.bg:SetVertexColor(0, 0, 0, 1)

        sell.icon = sell:CreateTexture(nil, "ARTWORK")
        sell.icon:SetPoint("TOPLEFT", sell, "TOPLEFT", 2, -2)
        sell.icon:SetPoint("BOTTOMRIGHT", sell, "BOTTOMRIGHT", -2, 2)

        sell.count = sell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        sell.count:SetPoint("BOTTOMRIGHT", sell, "BOTTOMRIGHT", -2, 2)
    else
        --[==[ **One border, not two.** A templated button draws the gold ring
             itself, and the supplied art arrived with that same border painted
             into it. So the ring comes off and the art is drawn across the whole
             face: it is still an item button, which is what keeps its size,
             states and hit area right, it simply stops drawing a frame the art
             already has. ]==]
        sell:SetNormalTexture("")
        if sell.icon.SetAllPoints then sell.icon:SetAllPoints(sell) end
    end

    sell.icon:SetTexture(OB.mediaPath .. "textures\\icons\\trash")

    sell:SetScript("OnClick", function()
        local m = OB.modules.qol
        local sold = m:SellJunkNow()

        --[[ Said out loud even when it is nothing, because a button that looks
             like it did nothing and a button that found nothing to do are the
             same thing from the outside. ]]--
        if sold > 0 then
            Say("sold " .. sold .. (sold == 1 and " item." or " items."))
        else
            Say("nothing to sell.")
        end

        m:UpdateVendorButtons()
    end)

    sell:SetScript("OnEnter", function()
        if not GameTooltip then return end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Sell Junk")
        GameTooltip:AddLine("Sell every grey, and anything on your sell list.",
                0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
    end)

    sell:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    self.vendorButtons = { sell = sell }
    return self.vendorButtons
end

--[==[ **Grey when there is nothing to sell.**

     `Disable()` was doing this job and could not: the art is drawn on an
     `ARTWORK` texture rather than as a button state, so disabling changes the
     hit area and nothing a reader can see. The button looked identical whether
     it had seven things to sell or none.

     `SetItemButtonDesaturated` is the client's own answer and this is its
     shape, fallback included: `SetDesaturated` reports whether it worked --
     some hardware cannot do it -- and a vertex colour is what the client falls
     back to. Copied rather than assumed, because a greyed icon that is silently
     still coloured is the bug this is fixing. ]==]
function M:DimJunkIcon(sell, dim)
    local icon = sell and sell.icon
    if not icon then return false end

    if not dim then
        if icon.SetDesaturated then icon:SetDesaturated(nil) end
        if icon.SetVertexColor then icon:SetVertexColor(1, 1, 1) end
        return false
    end

    local greyed = icon.SetDesaturated and icon:SetDesaturated(1)

    if not greyed and icon.SetVertexColor then
        icon:SetVertexColor(0.4, 0.4, 0.4)
    end

    return true
end

--[[ **What the button says before it is pressed.**

     How much junk there is, in the corner where a stack count goes. A text
     button could say "Sell Junk (7)"; an icon cannot, and the number is the
     whole reason to press it. ]]--
function M:UpdateVendorButtons()
    local buttons = self:VendorButtons()
    if not buttons then return false end

    local cfg = self:Config()
    local sell = buttons.sell

    if not cfg.vendorButtons or not OB.ModuleEnabled("qol")
            or not self:OnMerchantTab() then
        sell:Hide()

        --[[ The row goes back where the client put it, or the space it made for
             us is a gap. ]]--
        self:ShiftRepairRow(0)
        return false
    end

    sell:Show()
    self:HideRepairLabel()

    --[[ Re-asked here rather than trusted from build time: whether this
         merchant repairs decides the anchor, and it changes from vendor to
         vendor. ]]--
    local beside = self:PlaceJunkButton(sell)

    --[[ The row only moves when ours is standing in it. At a merchant who
         cannot repair there is no row to make space in, and shifting hidden
         buttons is work that shows up the moment they are shown again. ]]--
    if beside == "row" then
        self:ShiftRepairRow(sell:GetWidth() + self:RepairRowGap())
    else
        self:ShiftRepairRow(0)
    end

    local items = self:SellableItems(true)
    local count = table.getn(items)

    --[==[ Dimmed rather than hidden with nothing to sell: a button that vanishes
         is one somebody has to learn the absence of, and it moves the row.

         **Shown and hidden, not only written.** `ItemButtonTemplate`'s count is
         `hidden="true"` in the client's own XML -- `SetItemButtonCount` is what
         shows it -- so writing text into it left the number invisible on every
         real client. The hand-built path made a plain font string, which is
         visible by default, and that is the only path the harness ever ran. So
         the count worked in the tests and never once in the game. ]==]
    if count > 0 then
        sell:Enable()
        sell.count:SetText(count)
        sell.count:Show()
        self:DimJunkIcon(sell, false)
    else
        sell:Disable()
        sell.count:SetText("")
        sell.count:Hide()
        self:DimJunkIcon(sell, true)
    end

    return true
end

function M:AtMerchant()
    --[[ Built and updated whether or not the automatic pass does anything: the
         buttons are the path for somebody who has both switches off. ]]--
    self:UpdateVendorButtons()

    if not OB.ModuleEnabled("qol") then return end

    local cfg = self:Config()
    local cost, refused = self:Repair()
    local sold = self:SellJunk()

    if not cfg.vendorReport then return end

    if cost then
        Say("repaired for " .. OB.Money(cost) .. ".")
    elseif refused then
        Say("did not repair: " .. refused .. ".")
    end

    if sold > 0 then
        Say("sold " .. sold .. " item" .. (sold == 1 and "" or "s")
                .. ". Buy anything back from the vendor if that was a mistake.")
    end
end

-- ---------------------------------------------------------------------------
-- never keep
-- ---------------------------------------------------------------------------

--[[ An item's quality, back out of the colour its link starts with. There is no
     call that answers this for a bag slot in 1.12 -- `GetContainerItemInfo` gives
     you a texture, a count and whether it is locked, and stops. ]]--
local function linkQuality(link)
    if not link or not ITEM_QUALITY_COLORS then return nil end

    for quality = 0, 5 do
        local colors = ITEM_QUALITY_COLORS[quality]

        if colors and colors.hex
                and string.find(link, colors.hex, 1, true) == 1 then
            return quality
        end
    end

    return nil
end

--[[ **The highest quality this will ever destroy.**

     One, which is white. Not a setting, and this is the guardrail rather than a
     preference: the list is typed by hand, and a hand-typed list of names is one
     slip away from matching something that took a month to get. Greens and above
     sell for real money, so nobody wants them destroyed *and* the client already
     has a confirmation box for exactly that reason.

     A name on the list that turns out to be a green is simply skipped, and said
     out loud, because silence would look like the list not working. ]]--
local TRASH_MAX_QUALITY = 1

-- ---------------------------------------------------------------------------
-- what a thing is worth
-- ---------------------------------------------------------------------------

--[[ **Where a vendor value comes from.**

     A merchant tooltip is the authority because private servers can change the
     vanilla database. When a merchant is open, ECO reads that real value and
     stores it account-wide under both the legacy item name and the item ID.

     Away from a merchant, `OB.Market` supplies the shared provider stack used by
     Tooltip too: learned ECO values, Aux, the embedded SellValue baseline, then
     ShaguTweaks. `GetSellValue` remains as compatibility for addons that expose
     only that old community API.

     An unknown or zero answer remains nil. Cheap-junk deletion never guesses. ]]--
local function moneyFromTooltip(prefix)
    local frame = getglobal(prefix .. "MoneyFrame1")
    if not frame then return nil end

    local total = 0
    local found = false
    local units = { GoldButton = 10000, SilverButton = 100, CopperButton = 1 }

    for suffix, worth in pairs(units) do
        local text = getglobal(prefix .. "MoneyFrame1" .. suffix .. "Text")
        local value = text and text.GetText and tonumber(text:GetText())

        if value then
            total = total + (value * worth)
            found = true
        end
    end

    if not found then return nil end
    return total
end

--[[ Anything a sell-value addon wrote as plain text, for the ones that add a
     line rather than a money frame. Read as "<n>g <n>s <n>c" in any combination,
     which is how every one of them writes it. ]]--
local function moneyFromText(text)
    if not text then return nil end

    local total, found = 0, false

    local _, _, g = string.find(text, "(%d+)%s*[gG]")
    local _, _, s = string.find(text, "(%d+)%s*[sS]")
    local _, _, c = string.find(text, "(%d+)%s*[cC]")

    if g then total = total + tonumber(g) * 10000 found = true end
    if s then total = total + tonumber(s) * 100 found = true end
    if c then total = total + tonumber(c) found = true end

    if not found then return nil end
    return total
end

--[[ Per item, not per stack. A stack of twenty is twenty times the answer, and
     the threshold is about the thing rather than about how many of it you
     happen to be carrying. ]]--
function OB.SellValue(name, bag, slot)
    if not name then return nil end

    local link = GetContainerItemLink(bag, slot)
    local itemId = linkItemId(link)

    -- A merchant observation is the highest authority because private servers
    -- can change vanilla prices. While the merchant is open, inspect the native
    -- bag tooltip before trusting any static/addon answer, then remember it.
    if MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then
        local tip = OB.ScanTooltip()
        local value

        if type(tip.SetBagItem) == "function"
                and pcall(tip.SetBagItem, tip, bag, slot) then
            value = moneyFromTooltip("EquadisClassicOverhaulScanTooltip")

            if not value then
                for i = 1, (tip:NumLines() or 0) do
                    local line = OB.ScanLine(i)

                    if line and string.find(string.lower(line), "sell", 1, true) then
                        value = moneyFromText(line)
                        if value then break end
                    end
                end
            end

            -- The merchant tooltip reports the whole stack; ECO stores one item.
            if value and type(GetContainerItemInfo) == "function" then
                local _, count = GetContainerItemInfo(bag, slot)
                if count and count > 1 then value = math.floor(value / count) end
            end
        end

        if value and value > 0 then
            if OB.Market and OB.Market.LearnVendor and itemId then
                OB.Market:LearnVendor(itemId, value, name)
            else
                OB.prices[name] = value
            end
            return value
        end
    end

    -- Account-wide values observed on an earlier merchant visit beat every
    -- addon/static source, including values saved by pre-item-ID ECO builds.
    if itemId and OB.prices["item:" .. tostring(itemId)] then
        return OB.prices["item:" .. tostring(itemId)]
    end
    if OB.prices[name] then return OB.prices[name] end

    -- The shared provider stack is Aux first, then ECO's embedded SellValue
    -- baseline, then ShaguTweaks. This is also the path Tooltip uses.
    if itemId and OB.Market and OB.Market.GetVendor then
        local values = OB.Market:GetVendor(itemId)
        local value = values and tonumber(values.vendor)
        if value and value > 0 then return value end
    end

    -- Keep the long-standing compatibility hook for Auctioneer/other vendor
    -- addons that expose only GetSellValue and are not registered with Market.
    if type(GetSellValue) == "function" then
        local value = tonumber(GetSellValue(link))
        if value and value > 0 then return value end
    end

    return nil
end

--[[ Is this item cheap enough to be beneath keeping?

     Three ways to answer no, and only one of them is "it is expensive". Not grey
     is a no, and **not knowing is a no** -- which is the whole design. ]]--
function M:IsCheapJunk(name, bag, slot)
    local cfg = self:Config()
    if not cfg.trashJunk then return false end

    local link = GetContainerItemLink(bag, slot)
    if linkQuality(link) ~= 0 then return false end

    local value = OB.SellValue(name, bag, slot)
    if not value then return false end

    return value < (cfg.junkValue * 100)
end

--[[ Is this name on the never-keep list?

     **Whole names only, compared in full.** Never a substring, and that is the
     single most important line in this file: "Cloth" as a substring eats
     Runecloth, Mageweave and the Silk Cloth somebody is levelling tailoring
     with. The list is short and typed deliberately; matching it loosely to be
     helpful would be helpful exactly once. ]]--
function M:OnTrashList(name)
    if not name or name == "" then return false end

    local wanted = string.lower(name)

    for entry in string.gfind(OB.TrashList(), "[^,]+") do
        local trimmed = string.gsub(entry, "^%s*(.-)%s*$", "%1")
        if trimmed ~= "" and string.lower(trimmed) == wanted then return true end
    end

    return false
end

--[[ **Destroying one item, which is the one thing here that cannot be undone.**

     Three guards, in order, and each is protecting against a different way the
     obvious version goes wrong.

     `ClearCursor` first, because `PickupContainerItem` onto an occupied cursor
     *swaps* -- it would put whatever you were carrying into the bag and pick up
     the item, and the delete that follows would destroy the wrong thing. There
     is no way to ask 1.12 what is on the cursor, so the only safe move is to
     make sure the answer is nothing.

     Then the slot is re-read rather than trusted from the sweep. Bags shift: a
     `BAG_UPDATE` between building the list and acting on it moves everything
     after a removed stack up one, and a stale slot number is a correct-looking
     delete of the wrong item.

     Then the quality gate, for the reason above. ]]--
function M:DestroySlot(bag, slot, expected)
    if type(PickupContainerItem) ~= "function" then return false end
    if type(DeleteCursorItem) ~= "function" then return false end

    local link = GetContainerItemLink(bag, slot)
    local name = linkName(link)

    --[[ Not what we came for any more. Silent, because this is the normal
         outcome of bags having moved, not a problem worth a line of chat. ]]--
    if not name or name ~= expected then return false end

    local quality = linkQuality(link)

    if quality and quality > TRASH_MAX_QUALITY then
        Say("'" .. name .. "' is on your never-keep list but is not junk. "
                .. "Left alone -- remove it from the list or destroy it yourself.")
        return false
    end

    if CursorHasItem and CursorHasItem() then return false end
    if ClearCursor then ClearCursor() end

    PickupContainerItem(bag, slot)
    DeleteCursorItem()

    --[[ Always said, never a setting. Something that destroys an item without
         mentioning it is indistinguishable from an item that never dropped. ]]--
    Say("destroyed " .. name .. ".")

    return true
end

--[[ One pass over the bags.

     **One item per pass**, and then it stops. Deleting causes a `BAG_UPDATE`,
     which brings us straight back here with the bags in their new shape -- so
     the loop is the event rather than a `for`, and every delete acts on a slot
     that was read a moment ago rather than on a list assembled before anything
     moved. Slower by a frame per item and correct by construction. ]]--
function M:TrashPass()
    if not OB.ModuleEnabled("qol") then return false end

    local cfg = self:Config()

    --[[ Two ways in and they are separate switches: a named list, and a value
         rule. Neither implies the other -- somebody may want their Broken Fangs
         gone and every other grey kept, or the reverse. ]]--
    local byName = cfg.autoTrash and OB.TrashList() ~= ""
    if not (byName or cfg.trashJunk) then return false end

    --[[ Not while something is being dragged. The cursor is the player's. ]]--
    if CursorHasItem and CursorHasItem() then return false end

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0

        for slot = 1, slots do
            local name = linkName(GetContainerItemLink(bag, slot))

            if name then
                local wanted = (byName and self:OnTrashList(name))
                        or self:IsCheapJunk(name, bag, slot)

                if wanted and self:DestroySlot(bag, slot, name) then
                    return true
                end
            end
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- picking things out of your bags
-- ---------------------------------------------------------------------------

--[[ **Trash mode: choose several things, then deal with all of them at once.**

     The chore this replaces is a bag full of quest leftovers and vendor trash
     after a dungeon, cleared one right-click-delete-confirm at a time.

     Kept entirely separate from the never-keep list, which is automatic and
     therefore guarded to the point of paranoia. This is not automatic. Every
     item in the selection is there because somebody clicked it, and the friction
     that belongs on an automatic list is just noise on a deliberate one.

     What replaces it is the confirmation at the end, which is the same shape as
     the client's own: it asks once, it says how many, and it names anything good
     enough that you might not have meant it. ]]--
function M:SelectMode()
    return self.selecting and true or false
end

function M:SetSelectMode(on)
    self.selecting = on and true or nil

    if not self.selecting then self:ClearSelection() end
    self:RefreshOverlays()
end

local function slotKey(bag, slot)
    return bag .. ":" .. slot
end

--[[ **The name is stored with the slot, and it is the point.**

     Bags shift. A stack sold, a quest item handed in, anything at all between
     choosing and acting moves everything after it up one -- so a slot number
     remembered from a click is a correct-looking reference to whatever is there
     now. Storing the name means the act can be checked against the intent, and
     the check happens immediately before the delete. ]]--
function M:ToggleSlot(bag, slot)
    local name = linkName(GetContainerItemLink(bag, slot))
    if not name then return false end

    self.selection = self.selection or {}

    local key = slotKey(bag, slot)

    if self.selection[key] then
        self.selection[key] = nil
    else
        self.selection[key] = { bag = bag, slot = slot, name = name }
    end

    self:RefreshOverlays()

    return true
end

function M:SlotSelected(bag, slot)
    if not self.selection then return false end
    return self.selection[slotKey(bag, slot)] ~= nil
end

function M:ClearSelection()
    self.selection = nil
    self:RefreshOverlays()
end

--[[ What is chosen, as a list, in a fixed order.

     `pairs` over the selection would answer in whatever order the table felt
     like, and a confirmation that named things in a different order each time
     would be harder to read than one that named them in bag order. ]]--
function M:SelectedItems()
    local out = {}

    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0

        for slot = 1, slots do
            local chosen = self.selection and self.selection[slotKey(bag, slot)]
            if chosen then table.insert(out, chosen) end
        end
    end

    return out
end

--[[ Anything in the selection good enough that somebody might not have meant it.

     Green and up, which is the same line the client draws when it asks you to
     type the item's name before deleting it. Naming them in the confirmation is
     the whole safety measure here -- not refusing, because a deliberate choice
     is allowed to be a deliberate choice, but making sure the choice is seen. ]]--
function M:ValuableInSelection()
    local out = {}
    local items = self:SelectedItems()

    for i = 1, table.getn(items) do
        local link = GetContainerItemLink(items[i].bag, items[i].slot)
        local quality = linkQuality(link)

        if quality and quality > TRASH_MAX_QUALITY then
            table.insert(out, items[i].name)
        end
    end

    return out
end

--[[ Destroy everything chosen.

     **Backwards through the list**, which is the whole of why this is written
     out rather than reusing the never-keep sweep. Removing an item shifts every
     slot after it up one; walking forwards would leave every remaining
     reference pointing one slot too far along. Walking backwards, the slots
     ahead of the one being removed are the ones already dealt with.

     The name is still re-checked before each delete, because backwards is a
     defence against our own removals and not against anything else that moves a
     bag while this runs. ]]--
function M:DestroySelected()
    local items = self:SelectedItems()
    local gone = 0

    for i = table.getn(items), 1, -1 do
        if self:DestroySlot(items[i].bag, items[i].slot, items[i].name) then
            gone = gone + 1
        end
    end

    self:ClearSelection()

    return gone
end

--[[ The panel's route to destroying a selection, which is the slash command's
     route with the same warning in front of it.

     Written here rather than in the option row so both entry points get the
     naming of valuable items -- an action that skipped it because it was reached
     from a button would be the more dangerous of the two paths having the less
     careful behaviour. ]]--
function M:ConfirmDestroySelected()
    local items = self:SelectedItems()

    if table.getn(items) == 0 then
        Say("nothing chosen. Turn choosing on and click items in your bags.")
        return
    end

    local valuable = self:ValuableInSelection()

    if table.getn(valuable) > 0 then
        Say("about to destroy " .. table.getn(items) .. " items, including: "
                .. table.concat(valuable, ", ") .. ".")
    end

    StaticPopup_Show("EQOB_TRASH_SELECTED")
end

--[[ Or hand them to a vendor instead, which is the better answer whenever the
     vendor will take them.

     Written into the same marks the panel-free `/eq sell` uses, so there is
     one idea of "sell these now" rather than two. ]]--
function M:SellSelected()
    local items = self:SelectedItems()

    for i = 1, table.getn(items) do
        self:MarkForSale(items[i].name)
    end

    local sold = self:SellJunk()
    self:ClearSelection()

    return sold
end

-- ---------------------------------------------------------------------------
-- the highlight on the bag slot
-- ---------------------------------------------------------------------------

--[[ **Which button is showing which bag slot**, which is a question rather than
     a lookup: 1.12 reuses the five container frames for whichever bags happen to
     be open, so `ContainerFrame3` is not bag three -- it is the third bag you
     opened, and it will be a different one tomorrow.

     The frame carries its bag id and each button carries its slot, so the answer
     is asked of the frames every time rather than cached. Caching it is the bug
     that makes a highlight land on the wrong item after you close one bag. ]]--
function M:RefreshOverlays()
    if type(getglobal) ~= "function" then return end

    for frame = 1, 5 do
        local container = getglobal("ContainerFrame" .. frame)

        if container and container.GetID and container:IsVisible() then
            local bag = container:GetID()

            for button = 1, 20 do
                local item = getglobal("ContainerFrame" .. frame
                        .. "Item" .. button)

                if item and item.GetID then
                    self:MarkButton(item, bag, item:GetID())
                end
            end
        end
    end
end

--[[ One button's highlight, created the first time it is needed.

     Created on the button rather than pooled, because a container button lives
     as long as the client does -- there is nothing to reclaim, and a pool would
     be bookkeeping in exchange for nothing. ]]--
function M:MarkButton(button, bag, slot)
    if not button.eqobMark then
        if not button.CreateTexture then return end

        local mark = button:CreateTexture(nil, "OVERLAY")
        mark:SetAllPoints(button)
        mark:SetTexture(1, 0.2, 0.2, 0.35)
        mark:Hide()

        button.eqobMark = mark
    end

    if self:SelectMode() and self:SlotSelected(bag, slot) then
        button.eqobMark:Show()
    else
        button.eqobMark:Hide()
    end
end

--[[ **Clicking a bag slot while the mode is on chooses it instead of using it.**

     Hooked on the global the way the casting calls are, and with the same known
     hole: a bag replacement that took its own reference at load never reaches
     ours. The mode is read inside, so with it off every click goes straight
     through untouched -- which is what makes hooking this acceptable at all. ]]--
function M:InstallBagClicks()
    if self.bagClicksInstalled then return end
    if type(ContainerFrameItemButton_OnClick) ~= "function" then return end

    self.bagClicksInstalled = true

    local original = ContainerFrameItemButton_OnClick

    ContainerFrameItemButton_OnClick = function(button, ignoreShift)
        local m = OB.modules.qol

        if m:SelectMode() and this and this.GetID and this.GetParent then
            local parent = this:GetParent()

            if parent and parent.GetID then
                m:ToggleSlot(parent:GetID(), this:GetID())
                return
            end
        end

        return original(button, ignoreShift)
    end
end

-- ---------------------------------------------------------------------------
-- what level a zone is for
-- ---------------------------------------------------------------------------

--[[ **The world map does not say what level anything is.**

     Which is the one thing you want from it while levelling, and the reason
     everybody has at some point had a browser open beside the game to find out
     whether Desolace comes before or after Thousand Needles.

     From LevelRange by Bull3t and the several hands after him -- see NOTICE, and
     note that its licence is stated in its own source rather than in a file,
     which is why it is quoted there in full.

     The ranges are its table, including the zones Turtle added. That is the half
     that could not have been written from memory: most of them exist nowhere
     else.

     Faction rides with the range because one look answers both questions -- a
     horde zone is somewhere an alliance character can go and should think about
     first. ]]--
--[[ Named `zoneRanges` rather than `zoneLevels` because the *setting* is
     `zoneLevels`, and one word meaning both the switch and the data it reads is
     how somebody ends up reading the wrong one. ]]--
OB.zoneRanges = {
    ["Alterac Mountains"] = { 30, 40, "contested" },
    ["Arathi Highlands"] = { 30, 40, "contested" },
    ["Ashenvale"] = { 18, 30, "contested" },
    ["Azshara"] = { 45, 55, "contested" },
    ["Badlands"] = { 35, 45, "contested" },
    ["Balor"] = { 29, 34, "contested" },
    ["Blackstone Island"] = { 1, 10, "horde" },
    ["Blasted Lands"] = { 45, 55, "contested" },
    ["Burning Steppes"] = { 50, 58, "contested" },
    ["Darkshore"] = { 10, 20, "alliance" },
    ["Deadwind Pass"] = { 55, 60, "contested" },
    ["Desolace"] = { 30, 40, "contested" },
    ["Dun Morogh"] = { 1, 10, "alliance" },
    ["Durotar"] = { 1, 10, "horde" },
    ["Duskwood"] = { 18, 30, "contested" },
    ["Dustwallow Marsh"] = { 35, 45, "contested" },
    ["Eastern Plaguelands"] = { 53, 60, "contested" },
    ["Elwynn Forest"] = { 1, 10, "alliance" },
    ["Felwood"] = { 48, 55, "contested" },
    ["Feralas"] = { 40, 50, "contested" },
    ["Gillijim's Isle"] = { 48, 53, "contested" },
    ["Gilneas"] = { 39, 46, "contested" },
    ["Grim Reaches"] = { 33, 38, "contested" },
    ["Hillsbrad Foothills"] = { 20, 30, "contested" },
    ["Hyjal"] = { 58, 60, "contested" },
    ["Lapidis Isle"] = { 48, 53, "contested" },
    ["Loch Modan"] = { 10, 20, "alliance" },
    ["Moonglade"] = { 1, 60, "contested" },
    ["Mulgore"] = { 1, 10, "horde" },
    ["Northwind"] = { 28, 34, "contested" },
    ["Redridge Mountains"] = { 15, 25, "contested" },
    ["Scarlet Enclave"] = { 55, 60, "contested" },
    ["Searing Gorge"] = { 43, 50, "contested" },
    ["Silithus"] = { 55, 60, "contested" },
    ["Silverpine Forest"] = { 10, 20, "horde" },
    ["Stonetalon Mountains"] = { 15, 27, "contested" },
    ["Stranglethorn Vale"] = { 30, 45, "contested" },
    ["Swamp of Sorrows"] = { 35, 45, "contested" },
    ["Tanaris"] = { 40, 50, "contested" },
    ["Tel'Abim"] = { 54, 60, "contested" },
    ["Teldrassil"] = { 1, 10, "alliance" },
    ["Thalassian Highlands"] = { 1, 10, "alliance" },
    ["The Barrens"] = { 10, 25, "horde" },
    ["The Hinterlands"] = { 40, 50, "contested" },
    ["Thousand Needles"] = { 25, 35, "contested" },
    ["Tirisfal Glades"] = { 1, 10, "horde" },
    ["Un'Goro Crater"] = { 48, 55, "contested" },
    ["Western Plaguelands"] = { 51, 58, "contested" },
    ["Westfall"] = { 10, 20, "alliance" },
    ["Wetlands"] = { 20, 30, "contested" },
    ["Winterspring"] = { 55, 60, "contested" },
}

--[[ What to say about a zone, or nothing at all.

     nil for a city, a battleground, or anything not in the table -- and the
     label is then left exactly as the client drew it. That is the right answer
     rather than a fallback: a zone with no level range is not a zone with an
     unknown one, it is a zone the question does not apply to. ]]--
function OB.ZoneLevelText(zone)
    local entry = zone and OB.zoneRanges[zone]
    if not entry then return nil end

    local range = entry[1] .. "-" .. entry[2]

    --[[ One number where the range is one level wide: "60-60" spends two
         characters saying one thing. ]]--
    if entry[1] == entry[2] then range = tostring(entry[1]) end

    return range, entry[3]
end
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- attacking by accident

--[[ **Where the range is drawn: onto the label the client already writes.**

     LevelRange makes a tooltip of its own and manages showing and hiding it.
     This appends to `WorldMapFrameAreaLabel` instead, which is one font string
     the client is already updating as the cursor moves -- no frame to make, no
     tooltip to place, and nothing to hide when the cursor leaves, because the
     client blanks the label itself.

     **Hooked once, and the original runs first.** The client rewrites the label
     every frame from its own hit test, so anything written before it is thrown
     away. Appending after is the only order that survives. ]]--
local FACTION_COLOR = {
    alliance = "|cff6699ff",
    horde = "|cffff5555",
    contested = "|cffffcc44",
}

--[[ **Guarded on a global, not on the module.**

     Every other hook here guards on a field of `self`, and in the game that is
     the same thing: the addon loads once, so the module table and the wrapped
     global appear together and never again.

     It is not the same thing under a test harness, which boots the addon many
     times against one set of frames. The module table is new each time and the
     global still carries the previous wrapper, so the hook stacks -- and each
     layer closes over the namespace it was built with, reading a profile that
     was replaced two boots ago. A setting switched off in the current one is
     still on in theirs.

     That is not only a harness problem. It is exactly what the Escape menu
     button did, and there it duplicated a button on every reload. A guard
     belongs on the durable thing, and here the durable thing is the global. ]]--
function M:InstallMapLabel()
    if EquadisOverhaulMapHooked then return end
    if type(WorldMapButton_OnUpdate) ~= "function" then return end

    EquadisOverhaulMapHooked = true

    local original = WorldMapButton_OnUpdate

    WorldMapButton_OnUpdate = function(elapsed)
        original(elapsed)

        --[[ Reached through the *current* namespace rather than the one this
             closure was built with, so a reload cannot leave the hook talking to
             a profile that has been replaced. ]]--
        local m = EquadisClassicOverhaul.modules.qol
        if m then m:LabelZone() end
    end
end

--[[ The label, with the range on the end of it.

     Read back off the font string rather than tracked, because the client owns
     it and the only reliable statement about its contents is what it currently
     says. A remembered zone name would be a second source of truth that goes
     stale the moment anything else writes there. ]]--
--[[ **The switch lives on the Map page now**, and is read from there rather
     than copied back here. The hook stays in this module because it hangs off
     the same world map machinery the rest of this file uses; only the setting
     moved. Read through the profile directly rather than through the map
     module, so this keeps working whether or not the Map module is bound. ]]--
function M:ZoneConfig()
    return (OB.profile and OB.profile.modules and OB.profile.modules.map) or {}
end

-- ---------------------------------------------------------------------------
-- automatic Need / Greed lists
-- ---------------------------------------------------------------------------

local function trimLootName(text)
    text = text or ""

    -- Accept an item link pasted into the command as well as plain text.
    local _, _, linked = string.find(text, "|h%[([^%]]+)%]|h")
    if linked then text = linked end

    local clean = string.gsub(text, "^%s*(.-)%s*$", "%1")
    return clean
end

local function listHasItem(list, name)
    if not name or name == "" then return false end
    local wanted = string.lower(trimLootName(name))

    for entry in string.gfind(list or "", "[^,]+") do
        if string.lower(trimLootName(entry)) == wanted then return true end
    end

    return false
end

local function listWithoutItem(list, name)
    local wanted = string.lower(trimLootName(name or ""))
    local kept = {}

    for entry in string.gfind(list or "", "[^,]+") do
        local clean = trimLootName(entry)
        if clean ~= "" and string.lower(clean) ~= wanted then
            table.insert(kept, clean)
        end
    end

    return table.concat(kept, ", ")
end

local function appendListItem(list, name)
    name = trimLootName(name)
    if name == "" then return list or "" end
    if listHasItem(list, name) then return list or "" end
    if not list or list == "" then return name end
    return list .. ", " .. name
end

function M:AutoRollList(kind)
    if kind == "need" then return OB.AutoNeedList() end
    return OB.AutoGreedList()
end

function M:OnAutoRollList(kind, name)
    return listHasItem(self:AutoRollList(kind), name)
end

function M:PrintAutoRollList(kind)
    local list = self:AutoRollList(kind)
    local label = kind == "need" and "automatic Need" or "automatic Greed"

    if list == "" then
        Say(label .. " list is empty.")
    else
        Say(label .. ": " .. list)
    end
end

--[==[ **The list as entries rather than as one string.**

     It is stored as a comma-separated string because that is what the text box
     that edits it produces, and that is the right shape for typing four names
     at once. It is the wrong shape for looking at: a run of text does not say
     how many there are, and taking one out means finding the right comma. ]==]
function M:AutoRollEntries(kind)
    local out = {}

    for entry in string.gfind(self:AutoRollList(kind) or "", "[^,]+") do
        local clean = trimLootName(entry)
        if clean ~= "" then table.insert(out, clean) end
    end

    return out
end

function M:RemoveAutoRollItem(kind, text)
    if not EquadisClassicOverhaulDB then return false end

    local name = trimLootName(text)
    if name == "" then return false end

    local key = kind == "need" and "autoNeed" or "autoGreed"
    if not listHasItem(EquadisClassicOverhaulDB[key] or "", name) then
        return false
    end

    EquadisClassicOverhaulDB[key] =
            listWithoutItem(EquadisClassicOverhaulDB[key] or "", name)

    if OB.RefreshPanel then OB.RefreshPanel() end
    return true
end

function M:AddAutoRollItem(kind, text)
    if not EquadisClassicOverhaulDB then return false end

    local name = trimLootName(text)
    if name == "" then return false end

    local key = kind == "need" and "autoNeed" or "autoGreed"
    local other = kind == "need" and "autoGreed" or "autoNeed"

    -- One item can only have one automatic answer. Adding it to one command
    -- therefore moves it out of the other list instead of leaving an ambiguous
    -- "Need and Greed" rule behind.
    EquadisClassicOverhaulDB[other] =
            listWithoutItem(EquadisClassicOverhaulDB[other] or "", name)
    EquadisClassicOverhaulDB[key] =
            appendListItem(EquadisClassicOverhaulDB[key] or "", name)

    if OB.RefreshPanel then OB.RefreshPanel() end

    Say("'" .. name .. "' added to automatic "
            .. (kind == "need" and "Need" or "Greed") .. ".")
    return true
end

function M:LootRollName(rollID)
    local name

    if type(GetLootRollItemInfo) == "function" then
        local texture
        texture, name = GetLootRollItemInfo(rollID)
    end

    if (not name or name == "") and type(GetLootRollItemLink) == "function" then
        name = trimLootName(GetLootRollItemLink(rollID))
    end

    return trimLootName(name)
end

function M:AutoRollChoice(rollID)
    if not OB.ModuleEnabled("qol") then return nil end

    local name = self:LootRollName(rollID)
    if name == "" then return nil end

    -- Need wins if somebody manually put the same name in both panel fields.
    if self:OnAutoRollList("need", name) then return 1, name end
    if self:OnAutoRollList("greed", name) then return 2, name end

    return nil, name
end

function M:InstallAutoRollCommands()
    if self.autoRollCommandsInstalled then return true end
    if type(SlashCmdList) ~= "table" then return false end

    self.autoRollCommandsInstalled = true

    SLASH_EQUADISAUTONEED1 = "/autoneed"
    SlashCmdList["EQUADISAUTONEED"] = function(msg)
        local m = EquadisClassicOverhaul
                and EquadisClassicOverhaul.modules
                and EquadisClassicOverhaul.modules.qol
        if not m then return end

        local item = trimLootName(msg)
        if item == "" then
            m:PrintAutoRollList("need")
        else
            m:AddAutoRollItem("need", item)
        end
    end

    SLASH_EQUADISAUTOGREED1 = "/autogreed"
    SlashCmdList["EQUADISAUTOGREED"] = function(msg)
        local m = EquadisClassicOverhaul
                and EquadisClassicOverhaul.modules
                and EquadisClassicOverhaul.modules.qol
        if not m then return end

        local item = trimLootName(msg)
        if item == "" then
            m:PrintAutoRollList("greed")
        else
            m:AddAutoRollItem("greed", item)
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- confirmations you have already made your mind up about
-- ---------------------------------------------------------------------------

--[[ **The dialog appears after the decision, not before it.**

     Clicking Need on a bind-on-pickup item raises "this will bind to you, are
     you sure" -- but you clicked Need, on that item, deliberately, with a roll
     timer already running. Destroying something raises the same shape of
     question after you have dragged it out of the bag and let go. Neither
     dialog asks anything the click did not already answer.

     Which of them are skipped is per dialog rather than one switch, because
     they are not equally safe. `DELETE_GOOD_ITEM` -- the one that makes you type
     DELETE -- is raised only for rare quality and above, and that typing is the
     guard between a misclick and an epic rather than a formality. ]]--
local CONFIRM_DIALOGS = {
    CONFIRM_LOOT_ROLL = "confirmRoll",
    DELETE_ITEM = "confirmDestroy",
    DELETE_GOOD_ITEM = "confirmDestroyGood",

    --[==[ **Accepting somebody else's offer, through the client's own accept.**

         A summon and a resurrection are not confirmations of something you did
         -- they are offers from another player -- but they arrive as the same
         kind of dialog, and that is what makes them cheap to add here: this
         table already routes a named popup through
         `StaticPopupDialogs[name].OnAccept`, which is the client's own accept
         path.

         That matters more than the tidiness. Accepting a summon means calling
         whatever this build calls its summon function, and a resurrection the
         same -- going through the dialog means this addon never has to know
         either name, and a build without the dialog has no entry, finds
         nothing, and quietly does nothing rather than erroring.

         **Three names for the resurrection**, because the client picks between
         them on whether sickness applies and whether a timer is running. A
         reader that knew only the first would work until somebody rezzed you in
         combat. ]==]
    CONFIRM_SUMMON = "autoAcceptSummon",
    RESURRECT_REQUEST = "autoAcceptRevive",
    RESURRECT_REQUEST_NO_SICKNESS = "autoAcceptRevive",
    RESURRECT_REQUEST_TIMER = "autoAcceptRevive",
}

--[[ Whether this module would click through a given dialog. A method rather
     than a local so the tests and the hook read the same rule instead of two
     copies of it. ]]--
function M:SkipsConfirm(name)
    if not name then return false end
    if not OB.ModuleEnabled("qol") then return false end

    local key = CONFIRM_DIALOGS[name]
    if not key then return false end

    local cfg = self:Config()

    --[[ The rare-item dialog needs both switches: the general one says "skip
         destroy confirmations" and the specific one says "yes, those too". A
         single switch reaching the epic case would be the general setting
         quietly meaning more than it says. ]]--
    if name == "DELETE_GOOD_ITEM" then
        return (cfg.confirmDestroy and cfg.confirmDestroyGood) and true or false
    end

    return cfg[key] and true or false
end

--[[ **Need/Greed is not an ordinary popup on 1.12.**

     `CONFIRM_LOOT_ROLL` is raised by `UIParent_OnEvent`. Blizzard first calls
     `StaticPopup_Show("CONFIRM_LOOT_ROLL")`, *then* writes the roll id and roll
     type into the returned frame's `data` / `data2` fields. Trying to accept it
     from inside a `StaticPopup_Show` wrapper therefore runs too early: the
     payload does not exist yet. Worse, the object returned by
     `StaticPopup_Show` is the popup *frame*, while `OnAccept` lives in
     `StaticPopupDialogs`. The old implementation consequently hid the popup
     without ever calling `ConfirmLootRoll`, which made Need/Greed appear dead.

     Roll confirmation is intercepted one level earlier, at `UIParent_OnEvent`,
     where `arg1` and `arg2` are still the real roll id and roll type. Destroy
     confirmations can continue to use the normal popup wrapper because their
     acceptance data is already available through the popup path. ]]--
function M:InstallConfirmSkip()
    local installed = false

    if not EquadisOverhaulBlizzPopupShow and type(StaticPopup_Show) == "function" then
        EquadisOverhaulBlizzPopupShow = StaticPopup_Show

        StaticPopup_Show = function(name, a, b, data)
            local dialog = EquadisOverhaulBlizzPopupShow(name, a, b, data)

            --[[ Reached through the global namespace rather than the `OB`
                 upvalue, for the reason every other wrapper in this addon is:
                 `core.lua` assigns a fresh namespace on each load and this
                 wrapper outlives it. ]]--
            local m = EquadisClassicOverhaul
                    and EquadisClassicOverhaul.modules
                    and EquadisClassicOverhaul.modules.qol

            --[[ Loot-roll confirmation is intentionally *not* accepted here.
                 On vanilla the caller has not assigned `dialog.data` and
                 `dialog.data2` yet. It is handled by the UIParent event wrapper
                 below with the real event arguments instead. ]]--
            if name ~= "CONFIRM_LOOT_ROLL" and m and m:SkipsConfirm(name) then
                m:AcceptConfirm(name, dialog)
            end

            return dialog
        end

        installed = true
    end

    --[[ Vanilla's UIParent handler receives the confirmation payload as the
         global event arguments and only afterwards creates the popup. Handling
         it here means the original Need/Greed click is completed immediately
         and Blizzard never creates a confirmation dialog at all. ]]--
    if not EquadisOverhaulBlizzUIParentOnEvent
       and type(UIParent_OnEvent) == "function" then
        EquadisOverhaulBlizzUIParentOnEvent = UIParent_OnEvent

        --[==[ **Fixed arguments, not `...`.** 1.12 is Lua 5.0, and 5.0 has no
             `...` expression -- a body that reads `local a, b = ...` is a
             syntax error there, which fails the whole file: not this wrapper,
             every function in this module. The suite runs on LuaJIT, which
             is 5.1 and accepts it, so nothing here could see that. The
             client calls `UIParent_OnEvent(event)` with one argument and
             the payload in `arg1`, `arg2`; two spare parameters cover any
             fork that passes them positionally. ]==]
        UIParent_OnEvent = function(event, a1, a2)
            local m = EquadisClassicOverhaul
                    and EquadisClassicOverhaul.modules
                    and EquadisClassicOverhaul.modules.qol

            local rollID, rollType = a1, a2
            if rollID == nil then rollID = arg1 end
            if rollType == nil then rollType = arg2 end

            --[[ Open Blizzard's normal loot-roll frame first, then perform the
                 exact same RollOnLoot call its Need/Greed button would make.
                 Keeping the frame path intact means a client fork can still do
                 its own setup, and if a roll cannot be made the user has a
                 visible manual fallback instead of the addon swallowing it. ]]--
            if event == "START_LOOT_ROLL"
               and m and rollID ~= nil and type(RollOnLoot) == "function" then
                m.autoRollPending = m.autoRollPending or {}
                m.autoRollPending[rollID] = nil

                local result = EquadisOverhaulBlizzUIParentOnEvent(event, a1, a2)
                local choice = m:AutoRollChoice(rollID)

                if choice then
                    m.autoRollPending[rollID] = choice
                    RollOnLoot(rollID, choice)
                end

                return result
            end

            if event == "CONFIRM_LOOT_ROLL"
               and m and rollID ~= nil and rollType ~= nil
               and type(ConfirmLootRoll) == "function" then
                local automatic = m.autoRollPending
                        and m.autoRollPending[rollID] == rollType

                -- Automatic rules are truly automatic even when the general
                -- "Skip Need / Greed Confirmation" option is switched off.
                if automatic or m:SkipsConfirm("CONFIRM_LOOT_ROLL") then
                    ConfirmLootRoll(rollID, rollType)
                    if m.autoRollPending then m.autoRollPending[rollID] = nil end
                    return
                end
            end

            return EquadisOverhaulBlizzUIParentOnEvent(event, a1, a2)
        end

        installed = true
    end

    return installed
end

--[[ Accepting a normal popup exactly the way 1.12's
     `StaticPopup_OnClick(dialog, 1)` does.

     **The returned object and the dialog definition are different things.**
     `StaticPopup_Show` returns a frame containing `data` / `data2`; the
     `OnAccept` function and flags such as `hasEditBox` live in
     `StaticPopupDialogs[name]`. Keeping those separate is important both for
     destroy confirmations and for any future confirmation added here.

     The typed confirmation is filled for us because `DELETE_GOOD_ITEM` reads
     its edit box before destroying the item. ]]--
function M:AcceptConfirm(name, dialog)
    local info = type(StaticPopupDialogs) == "table" and StaticPopupDialogs[name]
    if not info then return false end

    --[[ In the real client `dialog` is a StaticPopup frame. The small test
         harness historically returned the info table itself, so accept that
         shape too without confusing it for the frame that owns `data`. ]]--
    local frame = dialog
    if not frame or type(frame.GetName) ~= "function" then
        frame = getglobal("StaticPopup1")
    end

    local frameName = frame and frame.GetName and frame:GetName() or "StaticPopup1"

    if info.hasEditBox then
        local box = getglobal(frameName .. "EditBox") or getglobal("StaticPopup1EditBox")
        if box and box.SetText then
            box:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE")
        end
    end

    if type(info.OnAccept) ~= "function" then
        if frame and frame.Hide then frame:Hide() end
        return true
    end

    --[[ This mirrors Blizzard's 1.12 `StaticPopup_OnClick`: `this` is the
         accept button and OnAccept receives dialog.data and dialog.data2. ]]--
    local previous = this
    local button = getglobal(frameName .. "Button1") or getglobal("StaticPopup1Button1")
    this = button or frame or previous

    local data = frame and frame.data or nil
    local data2 = frame and frame.data2 or nil
    local ok, dontHide = pcall(info.OnAccept, data, data2)

    this = previous

    if ok and not dontHide and frame and frame.Hide then frame:Hide() end

    return ok
end

function M:LabelZone()
    if not OB.ModuleEnabled("qol") then return false end
    if not self:ZoneConfig().zoneLevels then return false end

    local label = getglobal("WorldMapFrameAreaLabel")
    if not label or not label.GetText then return false end

    local text = label:GetText()
    if not text or text == "" then return false end

    --[[ Turtle ships at least one zone whose name carries a trailing space --
         "Northwind " -- which matches nothing. Trimmed here rather than in the
         table, so the table stays the zone names as everybody writes them. ]]--
    local zone = string.gsub(text, "^%s*(.-)%s*$", "%1")

    --[[ Already labelled. The client rewrites this every frame, so without the
         check the range would be appended sixty times a second until the string
         was longer than the screen. ]]--
    if string.find(zone, "|cff", 1, true) then return false end

    local range, side = OB.ZoneLevelText(zone)
    if not range then return false end

    local color = ""
    if self:ZoneConfig().zoneFaction then color = FACTION_COLOR[side] or "" end

    label:SetText(zone .. "  " .. color .. range .. (color ~= "" and "|r" or ""))
    return true
end
-- ---------------------------------------------------------------------------

--[[ **Right-clicking a mob starts an auto-attack, and 1.12 has no setting for
     it.**

     It is the commonest way to pull something you were not ready for: you
     right-click to turn the camera, the cursor crosses a mob, and you are in
     combat. A rogue loses stealth, a hunter loses their opener, and everybody
     loses the pull they were setting up.

     **The client does this in C and there is no hook on it.** What there *is* is
     a CVar -- `AutoInteract` -- which governs whether right-clicking a unit
     interacts with it at all. Setting it to zero stops the attack, and it stops
     right-click-to-loot and right-click-to-talk with it, which is the trade and
     is why this is a switch rather than a default.

     Written only when asked and **never written back on the way off**, for the
     reason the camera setting gives: whatever it was before might have been set
     by another addon or by a `/console` line in somebody's notes, and this
     cannot tell those apart. Off means "stops changing it". ]]--
function M:ApplyRightClick()
    local cfg = self:Config()

    if not cfg.noRightClickAttack then return false end
    if type(SetCVar) ~= "function" then return false end

    SetCVar("AutoInteract", "0")
    return true
end

--[[ **Telling an attack you asked for from one you did not.**

     This is the whole difficulty. Stopping every auto-attack would be useless --
     the point is to keep the ones you meant. So the two ways of meaning it are
     hooked and they set a flag: pressing an attack on a bar, and `/attack` or
     any macro that runs `AttackTarget`.

     A right-click reaches the client's C code and sets no flag, which is exactly
     what distinguishes it. The absence is the signal.

     Installed once and never removed, the same rule as every other hook here. ]]--
function M:InstallAttackWatch()
    if self.attackWatchInstalled then return end
    self.attackWatchInstalled = true

    if type(AttackTarget) == "function" then
        local original = AttackTarget

        AttackTarget = function()
            --[[ Set *before* the call, because the client can raise the combat
                 event synchronously inside it -- and a flag set afterwards would
                 arrive too late to protect the attack that set it. ]]--
            OB.modules.qol.attackWanted = true
            return original()
        end
    end

    --[[ An attack pressed on a bar. `UseAction` is already hooked for
         dismounting, so this rides along there rather than wrapping it twice --
         two wrappers on one global is how an order nobody chose gets built. ]]--
end

--[[ **And the half a CVar cannot cover: the attack that has already started.**

     `AutoInteract` stops the interaction, and on some builds a right-click still
     reaches the auto-attack through a different path. The client announces every
     swing start, so the belt-and-braces answer is to stop one that began while
     the setting was on and nothing else asked for it.

     Only when the player did not press anything. `self.attackWanted` is set by
     the casting hooks -- an attack somebody asked for is an attack they get. ]]--
function M:OnAttackStarted()
    if not OB.ModuleEnabled("qol") then return false end
    if not self:Config().noRightClickAttack then return false end

    --[[ Asked for, so left alone. The flag is cleared by whoever set it on the
         next event rather than here, because an attack command can produce more
         than one start. ]]--
    if self.attackWanted then return false end

    if type(AttackTarget) ~= "function" then return false end

    --[[ `AttackTarget` toggles, so calling it while attacking stops it. That is
         the only way 1.12 offers to cancel one. ]]--
    AttackTarget()
    return true
end

-- ---------------------------------------------------------------------------
-- mounts
-- ---------------------------------------------------------------------------

--[[ **1.12 has no `Dismount()`. A mount is a buff, and you get off it by
     cancelling the buff.**

     Which means finding it, and a 1.12 buff has no id and no reliable name --
     only an icon path. Every buff test in this addon is a texture comparison for
     that reason; see `OB.HasPlayerBuff`.

     Nearly every mount in the game uses `Ability_Mount_<something>`, which makes
     the prefix a good test rather than a guess. **It is still a prefix test**:
     a class mount or a server's own mount with an icon outside that family will
     not be recognised, and the failure is quiet -- the cast goes out and the
     client refuses it, which is exactly what happens today with this switched
     off. Nothing is made worse by not recognising a mount.

     `IsMounted` is asked for first where it exists. It is a 2.0 call and absent
     from a plain 1.12 client, but several private-server clients backport it,
     and a real answer beats a good heuristic every time. ]]--
local MOUNT_ICON = "ability_mount"

--[[ **What a mount buff says, for the mounts whose icon does not say it.**

     Detecting a mount by its icon works for the common ones and quietly fails
     for the rest -- a class mount, an engineering mount, or anything a private
     server added has an icon outside the `ability_mount` family, and the failure
     is silent: the cast goes out, the client refuses it, and nothing dismounts.

     Which is exactly what "auto dismount stopped working" turned out to be. The
     neighbour addon that had been doing it was matching on the buff's *text*
     rather than its icon, so it caught every mount; this one caught some.

     Matched case-insensitively on a fragment, because the full line differs by
     mount, by locale and by server. The Turtle entries are theirs specifically
     -- its riding-skill mounts word the line differently again. ]]--
local MOUNT_TEXT = {
    "increases speed by",
    "mounted",
    -- Turtle's riding-skill wording, which says nothing about a percentage.
    "speed based on",
    "slow and steady",
    "riding skill",
}

--[[ Read through the addon's shared scanning tooltip rather than one of our
     own: several parts of this addon want the same hidden tooltip and one each
     means loading the same text several times for the same answer. ]]--
function M:BuffLooksLikeMount(index)
    if type(OB.ScanTooltip) ~= "function" then return false end

    local tip = OB.ScanTooltip()
    if not tip or type(tip.SetPlayerBuff) ~= "function" then return false end

    tip:ClearLines()

    --[[ Guarded: `SetPlayerBuff` on an index that has just expired throws on
         some builds, and a buff going away mid-scan is ordinary. ]]--
    local ok = pcall(tip.SetPlayerBuff, tip, index)
    if not ok then return false end

    for line = 1, 6 do
        local text = OB.ScanLine(line)

        if text then
            local lower = string.lower(text)

            for i = 1, table.getn(MOUNT_TEXT) do
                if string.find(lower, MOUNT_TEXT[i], 1, true) then return true end
            end
        end
    end

    return false
end

--[==[ **Walked by position, read and cancelled by handle.**

     This used to pass the position straight to `GetPlayerBuffTexture`, which is
     a different number -- see `OB.PlayerBuffIndex`. Two failures came out of it,
     and the second is the worse one:

     *The walk stopped early.* The index space holds this player's debuffs as
     well, so the first slot that was not a helpful buff ended the loop and every
     buff behind it was invisible. One debuff was enough to make the game say you
     were not mounted, which is what "auto dismount is not working" was.

     *And the index it returned was a position.* `Dismount` hands that to
     `CancelPlayerBuff`, which wants the handle -- so on the occasions the walk
     did find the mount, the buff it cancelled was whichever aura happened to
     hold that index.

     Returns the handle now, which is what both callers need. ]==]
local BUFF_POSITIONS = 32

function M:MountBuff()
    if type(GetPlayerBuffTexture) ~= "function" then return nil end

    --[[ **Icon first, text second.** The icon test is a string compare against
         a value already in hand; the text test loads a tooltip. Most mounts are
         caught by the cheap one, and the expensive one only runs for the buffs
         it did not recognise -- which is at most a handful. ]]--
    local fallback = nil
    local position = 0

    while position < BUFF_POSITIONS do
        local index = OB.PlayerBuffIndex(position)
        if not index then break end

        local texture = GetPlayerBuffTexture(index)
        if not texture then break end

        if string.find(string.lower(texture), MOUNT_ICON, 1, true) then
            return index, texture
        end

        if fallback == nil and self:BuffLooksLikeMount(index) then
            fallback = { index, texture }
        end

        position = position + 1
    end

    if fallback then return fallback[1], fallback[2] end

    return nil
end

--[[ Mounted, by whatever means the client will tell us.

     The real call wins when there is one. When there is not, a mount buff is the
     answer, and when there is no mount buff either the answer is no -- which is
     right far more often than it is wrong, and wrong in the harmless direction. ]]--
--[==[ **`IsMounted` is believed when it says yes and checked when it says no.**

     It is not a vanilla call. Something in this stack provides it -- a shim, a
     client patch, one of the compatibility DLLs -- and on some builds it answers
     no while a mount buff is sitting right there in the list. Taking that no as
     final ended the question, and auto dismount did nothing at all.

     Nothing knows better than the client that you *are* mounted, so a yes is
     final. A no gets the buff list's opinion, because a mount buff being there
     is proof of the same thing. ]==]
function M:Mounted()
    if type(IsMounted) == "function" and IsMounted() then return true end
    return self:MountBuff() ~= nil
end

function M:Dismount()
    local index, texture = self:MountBuff()

    if not index then return false end
    if type(CancelPlayerBuff) ~= "function" then return false end

    CancelPlayerBuff(index)
    self.lastMount = texture

    return true
end

--[[ **Should this cast dismount you?**

     Everything except the mount itself. Pressing your mount button while mounted
     is already how you get off, and intercepting it would cancel the buff and
     then re-cast the mount -- leaving you exactly where you started, one global
     cooldown poorer.

     Told apart by icon, which is the only identity available: the action's
     texture against the buff's. They are the same art for every mount in the
     game, which is what makes this work at all. ]]--
function M:ShouldDismount(texture)
    if not OB.ModuleEnabled("qol") then return false end
    if not self:Config().dismount then return false end
    if not self:Mounted() then return false end

    if texture then
        local _, mount = self:MountBuff()

        if mount and string.lower(texture) == string.lower(mount) then
            return false
        end
    end

    return true
end

--[[ **Hooked once, on the globals, and the hole is known.**

     `range.lua` found this the hard way and wrote it down: replacing the global
     `UseAction` only catches a press if every bar addon in the chain still calls
     the global at press time. One that took its own reference at load never
     reaches ours, and there is nothing to be done about that from here.

     So the globals are hooked -- which covers the default bars, macros, the
     spellbook and most bar replacements -- and `UI_ERROR_MESSAGE` catches the
     rest after the fact. That fallback cannot save the first press, but it means
     the second one works rather than repeating the same refusal. ]]--

-- ---------------------------------------------------------------------------
-- turning the character model by dragging it
-- ---------------------------------------------------------------------------

--[[ **The model has always known how to face any direction.**

     1.12 puts two arrow buttons under it and nothing else, so looking at the
     back of your own gear is a matter of clicking one of them repeatedly. The
     frame answers `GetFacing` and takes `SetFacing`; what has never existed is a
     way to ask it directly.

     Every model frame the client puts a character in. `DressUpModel` is the
     dressing room and `InspectModelFrame` belongs to an on-demand addon that may
     not be loaded, so each is looked up rather than assumed. ]]--
local MODEL_FRAMES = { "CharacterModelFrame", "DressUpModel", "InspectModelFrame" }

--[[ **Rotation follows the speed of the drag**, because it is computed from how
     far the cursor moved since the last frame rather than from where it started.

     A fast flick turns the model quickly and a slow drag inches it round, which
     is what makes it feel like the model is under the hand rather than geared to
     it -- and it falls out of measuring the delta per frame instead of the
     distance from the anchor. ]]--
--[==[ **The dragging settings belong to the character panel, not here.**

     They moved there when that module was written -- it is the window the model
     is in, and that is where somebody looking for "turn the model" goes. The
     rotation *code* stayed here, because it also serves the inspect and dressing
     room frames, which are not the character panel.

     So this reads across rather than keeping a second copy. A duplicate pair of
     keys in this module's own defaults is worse than a lookup: both would show
     in the panel, on different pages, and only one of them would do
     anything. ]==]
function M:ModelConfig()
    local panel = OB.profile and OB.profile.modules
            and OB.profile.modules.characterpanel

    --[[ Falls back to this module's own config, so a profile written before the
         setting moved still answers rather than erroring. ]]--
    return panel or self:Config()
end

function M:RotateModel(frame)
    if not frame or not frame.GetFacing or not frame.SetFacing then return false end
    if not frame.eqRotating then return false end

    local x = GetCursorPosition()
    if not x then return false end

    local last = frame.eqRotateFrom or x
    frame.eqRotateFrom = x

    local delta = x - last
    if delta == 0 then return false end

    local speed = tonumber(self:ModelConfig().modelRotateSpeed) or 0.01

    --[[ Dragging right turns the model to its left, which is the direction the
         side under the cursor moves. The other way round reads as the model
         resisting the hand. ]]--
    frame:SetFacing((frame:GetFacing() or 0) - (delta * speed))
    return true
end

--[==[ **The client's own turn-the-model arrows, shown or hidden as a pair.**

     Named off the model frame, which is how the client names them -- and looked
     up rather than assumed, because the dressing room and the inspect window are
     load-on-demand on several 1.12 forks and may not have built theirs yet.

     Taking a control away is only safe if it can come back, so this takes the
     state rather than only ever hiding. ]==]
local MODEL_ARROWS = { "RotateLeftButton", "RotateRightButton" }

function M:ShowModelArrows(frameName, show)
    if not frameName then return false end

    local any = false

    for i = 1, table.getn(MODEL_ARROWS) do
        local button = getglobal(frameName .. MODEL_ARROWS[i])

        if button and button.Show and button.Hide then
            if show then button:Show() else button:Hide() end
            any = true
        end
    end

    return any
end

--[==[ **Which state the arrows are in follows the setting, on every style
     pass.**

     Taking a control away at install time only would leave somebody who
     switched the drag off with neither way to turn the model. So this is asked
     rather than done once, and it is asked wherever the rest of this module's
     appearance is settled. ]==]
function M:ApplyModelArrows()
    local wanted = not self:ModelConfig().modelRotate
    local any = false

    for i = 1, table.getn(MODEL_FRAMES) do
        if self:ShowModelArrows(MODEL_FRAMES[i], wanted) then any = true end
    end

    return any
end

function M:InstallModelRotation()
    for i = 1, table.getn(MODEL_FRAMES) do
        local frame = getglobal(MODEL_FRAMES[i])

        if frame and frame.SetFacing and not frame.eqRotateInstalled then
            frame.eqRotateInstalled = true

            --[[ The model frame does not take the mouse on its own -- there has
                 never been anything to click on it. ]]--
            if frame.EnableMouse then frame:EnableMouse(true) end

            --[==[ **And the two arrows under it go.**

                 They exist because 1.12 had no other way to turn the model: two
                 buttons you click repeatedly to walk it round. Dragging the
                 model is that, done properly, and leaving the arrows there
                 leaves two controls for one job -- the worse one taking up the
                 space under the picture.

                 Hidden rather than removed: 1.12 cannot destroy a frame, and
                 switching the drag off has to put them back, which is what
                 `ApplyModelArrows` is for. ]==]
            self:ApplyModelArrows()
            if frame.RegisterForDrag then frame:RegisterForDrag("LeftButton") end

            local previousDown = frame:GetScript("OnMouseDown")
            local previousUp = frame:GetScript("OnMouseUp")
            local previousUpdate = frame:GetScript("OnUpdate")

            frame:SetScript("OnMouseDown", function()
                if previousDown then previousDown() end

                local m = EquadisClassicOverhaul.modules.qol
                if not m or not m:ModelConfig().modelRotate then return end
                if arg1 and arg1 ~= "LeftButton" then return end

                this.eqRotating = true

                --[[ Cleared rather than set, so the first frame of a drag
                     measures against where the cursor is *then*. Seeding it here
                     would make the model jump by however far the cursor had
                     moved since the last drag ended. ]]--
                this.eqRotateFrom = nil
            end)

            frame:SetScript("OnMouseUp", function()
                if previousUp then previousUp() end
                this.eqRotating = nil
                this.eqRotateFrom = nil
            end)

            frame:SetScript("OnUpdate", function()
                if previousUpdate then previousUpdate() end

                local m = EquadisClassicOverhaul.modules.qol
                if not m then return end

                --[[ A drag that ended off the frame never sends the mouse-up, so
                     the button is asked about rather than trusted -- otherwise
                     the model keeps turning with the cursor after the hand has
                     let go. ]]--
                if this.eqRotating and type(IsMouseButtonDown) == "function"
                        and not IsMouseButtonDown("LeftButton") then
                    this.eqRotating = nil
                    this.eqRotateFrom = nil
                    return
                end

                m:RotateModel(this)
            end)
        end
    end

    return true
end

--[[ **Inspect and dressing-room model frames are lazy-loaded.**

     The first implementation already listed `InspectModelFrame`, but it only
     called `InstallModelRotation()` during ECO's own bind. On stock 1.12 the
     inspect UI does not exist yet at that point: `InspectFrame_LoadUI()` loads
     Blizzard_InspectUI only when somebody actually inspects a unit. The name
     was therefore correct and the timing was wrong.

     Hook the two stock entry points that can create character-model windows and
     run the idempotent installer immediately afterwards. Existing frames are
     still installed by `InstallModelRotation()` itself, and the per-frame
     `eqRotateInstalled` flag prevents double hooks if either window is opened
     repeatedly. ]]--
function M:InstallLazyModelRotation()
    if self.lazyModelRotationInstalled then return true end
    self.lazyModelRotationInstalled = true

    if type(InspectFrame_LoadUI) == "function"
            and not EquadisOverhaulInspectFrameLoadUI then
        EquadisOverhaulInspectFrameLoadUI = InspectFrame_LoadUI

        InspectFrame_LoadUI = function()
            local result = EquadisOverhaulInspectFrameLoadUI()
            local m = EquadisClassicOverhaul and EquadisClassicOverhaul.modules
                    and EquadisClassicOverhaul.modules.qol

            if m then
                m:InstallModelRotation()

                --[==[ **And the rarity borders, which this never did.**

                     `OnBind` calls `InstallInspectRarity` and says in its own
                     comment that it is harmless before the inspect UI exists
                     because "the lazy hook installs it later". The lazy hook did
                     not: it installed the model rotation and stopped. So on a
                     stock client -- where `Blizzard_InspectUI` loads the first
                     time somebody is inspected, which is always after ECO
                     binds -- the borders were never installed at all.

                     Reported as the inspect page missing item rarity borders,
                     and the comment describing the fix had been sitting above
                     the call that needed it. ]==]
                m:InstallInspectRarity()
                m:RefreshInspectRarity()
            end

            return result
        end
    end

    -- DressUpModel is present on the stock client, but several 1.12 forks move
    -- the dressing room into a load-on-demand addon just like InspectUI. Hook
    -- the public show function when it exists so those clients get the same
    -- behaviour without special-casing their addon name.
    if type(DressUpFrame_Show) == "function"
            and not EquadisOverhaulDressUpFrameShow then
        EquadisOverhaulDressUpFrameShow = DressUpFrame_Show

        DressUpFrame_Show = function()
            local result = EquadisOverhaulDressUpFrameShow()
            local m = EquadisClassicOverhaul and EquadisClassicOverhaul.modules
                    and EquadisClassicOverhaul.modules.qol
            if m then m:InstallModelRotation() end
            return result
        end
    end

    return true
end

function M:InstallDismount()
    if self.dismountInstalled then return end
    self.dismountInstalled = true

    if type(UseAction) == "function" then
        local original = UseAction

        UseAction = function(slot, checkCursor, onSelf)
            local m = OB.modules.qol
            local texture

            if type(GetActionTexture) == "function" then
                texture = GetActionTexture(slot)
            end

            if m:ShouldDismount(texture) then m:Dismount() end

            --[[ A button press is a deliberate act, so whatever it starts is
                 wanted -- including an auto-attack. See InstallAttackWatch. ]]--
            m.attackWanted = true

            return original(slot, checkCursor, onSelf)
        end
    end

    --[[ Macros and everything typed. No texture to compare against here -- there
         is no name-to-icon call in 1.12 -- so `/cast <your mount>` while mounted
         will dismount and then mount again. Rare enough to accept, and the cost
         of getting it wrong is a wasted global cooldown rather than anything
         that matters. ]]--
    if type(CastSpellByName) == "function" then
        local original = CastSpellByName

        CastSpellByName = function(name, onSelf)
            local m = OB.modules.qol
            if m:ShouldDismount(nil) then m:Dismount() end

            return original(name, onSelf)
        end
    end
end

--[[ The client refusing a cast because you are mounted. Whatever the wording,
     the shape is the same, so this matches on the mounted-ness rather than on a
     string -- there is more than one refusal that says it, and the exact
     globals differ between 1.12 and the servers built on it. ]]--
function M:OnCastRefused(message)
    if not self:Config().dismount then return false end
    if not message then return false end

    if not string.find(string.lower(message), "mounted", 1, true) then
        return false
    end

    return self:Dismount()
end

-- ---------------------------------------------------------------------------
-- quests
-- ---------------------------------------------------------------------------

--[[ **Handing in a quest you have already read**, from QuestHaste by WobLight.

     Ported rather than copied -- the storage, the settings and the event
     dispatch all belong to this addon's shapes -- but the design is WobLight's
     and it is the good part. Two decisions in particular are worth keeping
     exactly as they are.

     **It is per quest.** The obvious version of this feature accepts and hands
     in everything, and it is the version that makes you miss the one quest you
     had not read. So the list is opt-in, a quest at a time, and the thing it is
     really for -- an Alterac Valley turn-in you have read forty times -- is on
     it after the first Ctrl-click.

     **The modifiers are a full grammar rather than a switch.** Ctrl remembers
     and proceeds, Alt forgets, Shift inverts, nothing does what the list says.
     Four behaviours on keys you are already holding, and no interface at all in
     the moment you need them. ]]--
function M:QuestRemembered(title, what)
    if not title then return false end

    if self:Config().questAll then return true end

    local saved = OB.quests[title]
    return (saved and saved[what]) and true or false
end

function M:RememberQuest(title, what)
    if not title then return end

    OB.quests[title] = OB.quests[title] or {}
    OB.quests[title][what] = true

    Say("remembering '" .. title .. "'.")
end

--[[ Forgetting one half leaves the other. A quest you auto-accept but want to
     read the reward text for is a real thing, and dropping the whole entry
     because one half was cleared would quietly undo the other. ]]--
function M:ForgetQuest(title, what)
    if not title then return end

    local saved = OB.quests[title]
    if not saved then return end

    saved[what] = nil

    if not saved.accept and not saved.complete then
        OB.quests[title] = nil
    end

    Say("forgot '" .. title .. "'.")
end

--[[ **What the modifiers say to do**, in one place because all three quest
     frames ask the same question.

     Returns "forget" for Alt, or a boolean: whether to go ahead.

     The `~=` is exclusive-or and is the whole of Shift. Remembered and no Shift
     goes ahead; not remembered and Shift goes ahead; the other two do not. That
     makes Shift "do the opposite of whatever the list says", which is both a way
     to push one unremembered quest through and a way to hold a remembered one
     while you read it. ]]--
function M:QuestIntent(title, what)
    if IsAltKeyDown() then return "forget" end

    if IsControlKeyDown() then
        self:RememberQuest(title, what)
        return true
    end

    local remembered = self:QuestRemembered(title, what)
    local shift = IsShiftKeyDown() and true or false

    return remembered ~= shift
end

function M:QuestActive()
    if not OB.ModuleEnabled("qol") then return false end
    return self:Config().questHaste and true or false
end

--[[ The quest text with an Accept button: the first window of a hand-out. ]]--
function M:OnQuestDetail()
    if not self:QuestActive() then return end

    local title = GetTitleText()
    local intent = self:QuestIntent(title, "accept")

    if intent == "forget" then
        self:ForgetQuest(title, "accept")
        return
    end

    if intent then
        --[[ Remembered across the window, so a quest pushed through by hand
             carries on being pushed through at the next step rather than
             stopping halfway. WobLight's, and it is what makes Shift usable. ]]--
        self.questInFlight = title
        AcceptQuest()
    else
        self.questInFlight = nil
    end
end

--[[ The "have you brought it" window, with a Continue button. ]]--
function M:OnQuestProgress()
    if not self:QuestActive() then return end

    local title = GetTitleText()
    local intent = self:QuestIntent(title, "complete")

    if intent == "forget" then
        self:ForgetQuest(title, "complete")
        return
    end

    --[[ Not completable means the items are not there. Pressing on would be
         asking the client to do something it will refuse. ]]--
    if (self.questInFlight == title or intent) and IsQuestCompletable() then
        self.questInFlight = title
        CompleteQuest()
    else
        self.questInFlight = nil
    end
end

--[[ The reward window, which is the one place this must be careful.

     **Never when there is a choice of reward.** `GetQuestReward(index)` takes
     one, and picking for somebody is picking wrong -- the whole point of a
     choice is that only they know which. So a quest with rewards to choose
     between stops here and waits, however firmly it is on the list.

     Not a setting. There is no version of "pick a reward for me" that is a good
     idea, and offering it would be offering somebody a way to lose an item they
     wanted. ]]--
function M:OnQuestComplete()
    if not self:QuestActive() then return end

    local title = GetTitleText()
    local intent = self:QuestIntent(title, "complete")

    if intent == "forget" then
        self:ForgetQuest(title, "complete")
        return
    end

    if (self.questInFlight == title or intent) and GetNumQuestChoices() == 0 then
        GetQuestReward()
    end

    self.questInFlight = nil
end

-- ---------------------------------------------------------------------------
-- the list of quests an NPC is offering
-- ---------------------------------------------------------------------------

--[[ 1.12 answers a gossip quest list as one flat run of title, level, title,
     level. The odd entries are the titles. ]]--
local function titlesFrom(list)
    local out = {}

    for i = 1, table.getn(list) do
        if mod(i, 2) == 1 then table.insert(out, list[i]) end
    end

    return out
end

--[==[ **Which of an NPC's quests to pick**, in the order somebody would.

     Anything remembered first, available before active -- taking a repeatable
     is what starts the loop. Then, because Shift is held and Shift means
     "push this through", the first quest on offer and then the first one in
     progress: accepting first, so that Shift held across a menu takes the new
     quests and then turns the old ones in, and a turn-in that is not ready
     stops at its own window rather than being asked for first.

     It used to stop at the remembered ones, which made Shift on a menu do
     nothing for a quest you had never read -- while Shift on that quest's own
     window pushed it through. Reported as exactly that.

     Returns the kind and the index, or nothing at all, so the caller does the
     selecting and this only decides. ]==]
function M:BestQuest(available, active)
    for i = 1, table.getn(available) do
        if self:QuestRemembered(available[i], "accept") then
            return "available", i
        end
    end

    for i = 1, table.getn(active) do
        if self:QuestRemembered(active[i], "complete") then
            return "active", i
        end
    end

    if table.getn(available) > 0 then return "available", 1 end
    if table.getn(active) > 0 then return "active", 1 end

    return nil
end

--[==[ **Shift on an NPC's menu takes the obvious quest**, and on a dialogue
     with one thing to say, says it.

     Shift rather than automatic, and this is deliberate: a gossip menu is also
     how you reach a flight master, a bank and a trainer, and an addon that
     jumped to a quest every time you opened one would be taking the menu away.

     `options` is the gossip's own list of things to say. One of them is a
     "continue" -- the quest-chain dialogue that goes on for three pages --
     and Shift turns the page. Several is a menu, and a menu is left to the
     person holding the mouse. ]==]
function M:OnGossip(available, active, pickAvailable, pickActive, options, pickOption)
    if not self:QuestActive() then return false end
    if not IsShiftKeyDown() then return false end

    local kind, index = self:BestQuest(available, active)

    if kind == "available" then
        pickAvailable(index)
        return true
    elseif kind == "active" then
        pickActive(index)
        return true
    end

    if options and pickOption and table.getn(options) == 1 then
        pickOption(1)
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

function M:OnEvent()
    -- Load-on-demand character windows (most importantly Blizzard_InspectUI)
    -- can appear long after ECO bound. The installer is idempotent, so checking
    -- on addon load is a cheap fallback for clients/addons that bypass the stock
    -- InspectFrame_LoadUI entry point.
    if event == "ADDON_LOADED" then
        self:InstallModelRotation()
        return
    end

    --[[ Both caches behind the macro icon defence, dropped when the thing they
         describe changes. Cheap to rebuild and wrong to keep. ]]--
    if event == "ACTIONBAR_SLOT_CHANGED" then
        self:ForgetMacroIcons()

        --[[ **Only the cache is dropped here.** Re-installing the hook on this
             event is what made the icons stop changing altogether: a neighbour
             that also re-installs turns two hooks into a chain that grows by a
             layer every time a button changes. See `InstallMacroIcons`. ]]--
        return
    end

    if event == "UNIT_INVENTORY_CHANGED" then
        self:RefreshPaperdollRarity()
        return
    end

    --[[ The bank is only refreshed by its own event: it is not open most of the
         time, and painting twenty-eight slots on every bag change is work for a
         window nobody is looking at. ]]--
    if event == "PLAYERBANKSLOTS_CHANGED" then
        self:RefreshBankRarity()
        return
    end

    if event == "QUEST_DETAIL" then self:OnQuestDetail() return end
    if event == "QUEST_PROGRESS" then self:OnQuestProgress() return end
    if event == "QUEST_COMPLETE" then self:OnQuestComplete() return end

    if event == "GOSSIP_SHOW" then
        local options = type(GetGossipOptions) == "function"
                and titlesFrom({ GetGossipOptions() }) or {}

        self:OnGossip(titlesFrom({ GetGossipAvailableQuests() }),
                titlesFrom({ GetGossipActiveQuests() }),
                SelectGossipAvailableQuest, SelectGossipActiveQuest,
                options, SelectGossipOption)
        return
    end

    --[[ The other kind of NPC menu -- no gossip text, just a list. Same
         decision, different four calls to read it with. ]]--
    if event == "QUEST_GREETING" then
        local available, active = {}, {}

        for i = 1, GetNumAvailableQuests() do
            table.insert(available, GetAvailableTitle(i))
        end

        for i = 1, GetNumActiveQuests() do
            table.insert(active, GetActiveTitle(i))
        end

        self:OnGossip(available, active, SelectAvailableQuest, SelectActiveQuest)
        return
    end

    if event == "UI_ERROR_MESSAGE" then
        self:OnCastRefused(arg1)
        return
    end

    --[[ The client announcing that a swing has begun, which is the only notice
         there is that something started attacking. ]]--
    if event == "PLAYER_ENTER_COMBAT" then
        self:OnAttackStarted()
        self.attackWanted = nil
        return
    end

    if event == "BAG_UPDATE" then
        self:TrashPass()
        self:RefreshBagRarity()
        return
    end

    if event == "MERCHANT_SHOW" then
        self:AtMerchant()
        return
    end

    if event == "MERCHANT_CLOSED" then
        self:ClearMarks()
        return
    end
end

--[==[ **Show Metrics is gone, and it was the client's readout it turned on.**

     This addon has had a framerate and latency readout of its own for a long
     time -- on the action bar, movable, styled, with its own switches. Show
     Metrics turned on a *second* one: `FramerateLabel` and `FramerateText`, font
     strings the client hangs on WorldFrame at `BOTTOM, 0, 64`, which is directly
     behind the action bars. Nothing about it can be moved, styled or switched
     off from a panel; the only control is the key that toggles it.

     It never worked the way it was written either. The guard read
     `getglobal("FramerateFrame")`, and 1.12 has no frame by that name -- the
     readout is two font strings, not a frame -- so "do not toggle a display
     somebody else already showed" always saw nil and toggled regardless. On a UI
     where something else had shown it, this turned it off.

     Nothing to undo in the world: both strings are `hidden="true"` in
     `WorldFrame.xml` and the client does not persist the toggle, so they come
     back hidden on the next load. ]==]

-- ---------------------------------------------------------------------------
-- macro icons that stay put while you cast
-- ---------------------------------------------------------------------------

--[[ **A macro with an icon you chose keeps that icon.**

     `SuperCleveRoidMacros` resolves a `#showtooltip` macro's icon from whichever
     of its actions is currently live, and one branch of that answers with the
     *equipped inventory item's* texture whenever the live action is a slot
     number 1-19:

         local a = actions.active or actions.tooltip
         local slotId = tonumber(a.action)
         if slotId and slotId >= 1 and slotId <= 19 then
             return GetInventoryItemTexture("player", slotId)

     A poison macro is two steps -- `/use <poison>` then `/use 16` -- and while
     the first is casting its conditional stops passing, so the live action
     becomes the bare slot number and the button shows your weapon. That is why
     it only happens mid-cast, and why setting the icon does not help: `active`
     is consulted before the icon is.

     **A question mark still resolves dynamically.** That is what a `?` icon
     means and it is the whole point of the feature. This only defends an icon
     somebody deliberately picked.

     Lives here rather than in that addon's source because a patched file is
     lost the next time it updates. It lives in this module rather than in
     `actionbars` because action bars ship switched off, and a compatibility fix
     nobody has switched on is not a fix. ]]--

--[[ The icon a macro was actually given, or nil if this slot is not a macro, has
     no icon, or was left on the question mark. Three API calls, so the answer is
     remembered per slot and thrown away when the bars change. ]]--
--[[ **The icon a `#showtooltip` macro was given, which then wins outright.**

     The first version only stepped in when the resolved answer happened to be a
     worn item's texture, on the reasoning that this was the one wrong case and
     everything else was a resolution doing its job. That is a heuristic about a
     symptom, and it left the icon changing in every case the heuristic did not
     recognise.

     The rule now is the one worth stating: **a macro that opted into
     `#showtooltip` and was given a real icon keeps that icon.** Nothing is
     compared, nothing is guessed, and the answer does not depend on what you
     happen to be wearing.

     Both conditions matter:

     - **`#showtooltip` must be in the body.** A macro without it is never
       resolved dynamically by anything, so forcing its icon would be claiming
       ownership of buttons this has no business touching.
     - **A question mark is left alone.** That icon *is* the request to work it
       out, and taking it away would break the feature rather than the bug. ]]--
function M:ReadMacroIcon(slot)
    if type(GetActionText) ~= "function" then return nil end

    local name = GetActionText(slot)
    if not name or name == "" then return nil end

    if type(GetMacroIndexByName) ~= "function" then return nil end

    local index = GetMacroIndexByName(name)
    if not index or index == 0 then return nil end

    if type(GetMacroInfo) ~= "function" then return nil end

    local _, texture, body = GetMacroInfo(index)
    if not texture then return nil end

    --[[ Only macros that asked. `#show` covers `#showtooltip` and `#showicon`
         alike -- they are the same request with different spellings. ]]--
    if not body then return nil end
    if not string.find(string.lower(body), "#show") then return nil end

    --[[ A question mark is a request to work it out, so leave it alone. ]]--
    if string.find(string.lower(texture), "questionmark", 1, true) then
        return nil
    end

    return texture
end

function M:MacroIcon(slot)
    self.macroIcons = self.macroIcons or {}

    local cached = self.macroIcons[slot]

    --[[ `false` is a remembered "no icon here", which is the common answer and
         the one worth not paying for twice. `nil` means not yet asked. ]]--
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local texture = self:ReadMacroIcon(slot)
    self.macroIcons[slot] = texture or false

    return texture
end

function M:ForgetMacroIcons()
    self.macroIcons = nil
end

--[[ Installed over whatever is already there, and re-installed if something
     replaces it afterwards.

     Order matters and is the reason this is not a one-time install: ECO loads
     before `SuperCleveRoidMacros` alphabetically, so anything hooked at file
     scope ends up *inside* their override and never sees the answer it needs to
     correct. Binding happens after every addon has loaded, which puts this
     outermost. ]]--
function M:InstallMacroIcons()
    if type(GetActionTexture) ~= "function" then return false end

    --[[ **Once per session, and never again -- even if something replaces it.**

         The first version re-installed whenever the bars changed, so that a
         neighbour hooking later could be taken back. That is safe against a
         neighbour who hooks once. It is not safe against one who *also*
         re-installs: mine captures theirs, theirs captures mine, and every
         event adds a layer to a chain that already contains both of us. Each
         call then walks progressively older copies, which reads as icons that
         have stopped changing at all.

         Losing the hook to a later addon costs the fix. Growing the chain costs
         the action bar. So this installs exactly once and accepts the former. ]]--
    if self.macroIconInstalled then return false end

    local previous = GetActionTexture

    --[[ Belt and braces: never wrap ourselves, whatever the bookkeeping says. ]]--
    if previous == self.macroIconWrapper then return false end

    local wrapper = function(slot)
        local answer = previous(slot)

        local m = OB.modules.qol
        if not m then return answer end
        if not OB.ModuleEnabled("qol") then return answer end

        --[[ **The chosen icon wins outright.** No comparison against what is
             underneath, because there is nothing to compare: a macro that asked
             for `#showtooltip` and was given a real icon has already said which
             icon it wants on that button.

             `previous` is still called, and its answer is still what a slot
             this does not own gets back. Nothing else is taken away from it. ]]--
        local chosen = m:MacroIcon(slot)
        if chosen then return chosen end

        return answer
    end
    self.macroIconWrapper = wrapper
    self.macroIconInstalled = true
    GetActionTexture = wrapper

    return true
end

-- ---------------------------------------------------------------------------
-- what you are looking at
-- ---------------------------------------------------------------------------

--[[ **The level line, read out of the text.**

     1.12 has no `mouseover` unit token, so the tooltip for a mob you hover
     cannot be resolved to a unit and asked anything. The only thing there is to
     read is what the client already wrote on it.

     Line two of a creature tooltip is `Level 60 Humanoid`, with `Elite`,
     `Rare` or `Rare Elite` between the number and the type when it applies. The
     classification is stripped rather than kept: this exists to answer "how far
     above me is it" and "does it run", and neither asks.

     **`string.find` with captures, not `string.match`.** 1.12 has no
     `string.match` -- the same rule chatbehaviour.lua states where it does its
     own parsing. LuaJIT has it, so the suite would never notice.

     **A `??` level comes back as the string.** It is not a number and must not
     be turned into one: `tonumber("??")` is nil, and nil is what a colour
     function paints grey. Grey means beneath notice, which is the most
     dangerous thing this could say about something it cannot measure. ]]--
local CLASSIFICATIONS = { "Rare Elite", "Rare", "Elite" }

local function stripClassification(text)
    if not text then return nil end

    for i = 1, table.getn(CLASSIFICATIONS) do
        text = string.gsub(text, "^" .. CLASSIFICATIONS[i] .. "%s*", "")
    end

    text = string.gsub(text, "%s+$", "")
    if text == "" then return nil end

    return text
end

function M:ReadLevelLine(text)
    if type(text) ~= "string" then return nil end

    local _, _, rest = string.find(text, "^Level%s+(.+)$")
    if not rest then return nil end

    --[[ `??` first, because `%d+` will not match it. ]]--
    local _, _, unknownRest = string.find(rest, "^%?%?%s*(.*)$")

    if unknownRest then
        return "??", stripClassification(unknownRest)
    end

    local _, _, level, remainder = string.find(rest, "^(%d+)%s*(.*)$")
    if not level then return nil end

    return level, stripClassification(remainder)
end

--[[ **Whether a thing runs when you have nearly killed it.**

     There is no API for this. Fleeing is a per-creature flag on the server and
     the client tells you only by doing it, at the worst possible moment, when
     the thing you have nearly killed runs into the next camp. The creature type
     is knowable and predicts it well: things with a mind and a body run, things
     with neither do not.

     **Three answers, not two.** A type this table has never heard of is
     genuinely unknown, and saying nothing is the honest form of that. A boolean
     would have to pick a side, and picking the confident side is the one that
     gets somebody killed. ]]--
local FLEES = {
    Humanoid = true,
    Beast = true,
    Giant = true,
    Dragonkin = true,

    Undead = false,
    Elemental = false,
    Mechanical = false,
    Demon = false,
    Totem = false,
    Critter = false,
}

function M:Flees(kind)
    if type(kind) ~= "string" or kind == "" then return nil end

    --[[ **Unknown and unrecognised are the same answer**, which is why there is
         no special case for the client's own "Not specified": the lookup below
         misses it exactly as it misses a type this has never heard of, and both
         come back as nothing. A branch was written for it and removed once a
         mutation showed it changed no outcome -- a line that cannot be broken
         is a line that is not doing anything. ]]--
    local answer = FLEES[kind]
    if answer == nil then return nil end

    return answer
end

--[[ **Decorating a tooltip the client has already filled in.**

     Recolours the line that is there rather than adding a second copy of it in
     a different colour, and adds a line only for the thing that is genuinely
     new. An item tooltip has no level line and passes through untouched, which
     is the difference between decorating tooltips and taking them over. ]]--
function M:DecorateTooltip(tip)
    if not tip or not tip.NumLines then return false end

    local cfg = self:Config()
    if not cfg.tipLevelColor and not cfg.tipFlee then return false end

    local name = tip.GetName and tip:GetName() or nil
    if not name then return false end

    if (tip:NumLines() or 0) < 2 then return false end

    --[[ Line two, which is where the client puts it. Searching every line would
         find the word "Level" in an item's requirement line and colour that. ]]--
    local line = getglobal(name .. "TextLeft2")
    if not line or not line.GetText then return false end

    local level, kind = self:ReadLevelLine(line:GetText())
    if not level then return false end

    --[[ **Once per tooltip, not once per tick.**

         The tooltip module's decoration pass runs many times while one tooltip
         is on screen. Recolouring the level line that often is merely wasteful;
         adding the flee line that often would stack a dozen copies of it down
         the tooltip.

         Keyed on what the tooltip says rather than on a flag, because the
         client reuses the same frame for the next mob: a flag would have to be
         cleared by somebody, and the thing that changes is the text. ]]--
    local first = getglobal(name .. "TextLeft1")
    local key = (first and first.GetText and first:GetText() or "")
            .. "|" .. (line:GetText() or "")

    if tip.eqEcoMobKey == key then return false end
    tip.eqEcoMobKey = key

    if cfg.tipLevelColor and line.SetTextColor then
        --[[ `??` is painted red rather than passed through `tonumber`, which
             would hand `LevelColor` a nil and get grey back. ]]--
        if level == "??" then
            local red = OB.levelColors.red
            line:SetTextColor(red[1], red[2], red[3])
        else
            line:SetTextColor(OB.LevelColor(tonumber(level)))
        end
    end

    if cfg.tipFlee then
        local runs = self:Flees(kind)

        --[[ Nothing at all for a type this does not know. See `Flees`. ]]--
        if runs ~= nil and tip.AddLine then
            if runs then
                tip:AddLine("Runs at low health", 1, 0.5, 0.25)
            else
                tip:AddLine("Fights to the death", 0.5, 0.75, 1)
            end

            if tip.Show then tip:Show() end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- what an item is worth, said on the item
-- ---------------------------------------------------------------------------

--[[ **The rarity colour, drawn round the item rather than only in its tooltip.**

     1.12 puts quality in two places: the colour of an item's name in its
     tooltip, and the colour of its link in chat. Neither is visible while
     looking at a bag. So a full bag is forty grey squares, and finding the blue
     one means hovering over them in turn -- which is the actual reason people
     miss a drop they already picked up.

     A border rather than a tint over the icon, because the icon is how an item
     is recognised and washing it in colour makes twenty different things look
     like the same thing.

     Ported from ShaguTweaks' `item-colors`. Drawn with this addon's own border
     media so it matches the rest of the interface rather than importing a
     second look.

     **Common and poor are left alone.** Every bag is mostly grey items, and a
     grey border round each of them is a grid of boxes that says nothing -- the
     signal is the one item that is *not* ordinary. ]]--
--[[ ~~RARITY_INSET~~ and the outside frame it hung went with `RarityBorder`,
     which nothing called: the ring is the button's own normal texture now,
     tinted, and the frame that used to sit round it was built and hidden on
     every button for no reader at all. ]]--

--[[ Uncommon and up. One is Common and zero is Poor: both are the ordinary
     case and neither is worth a line round the icon. ]]--
local RARITY_FLOOR = 2

--[[ Every paperdoll slot in the order the client numbers them, which is what
     `GetInventoryItemQuality` is keyed by. Ammo is slot zero. ]]--
local PAPERDOLL_SLOTS = {
    [0] = "AmmoSlot", "HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot",
    "ChestSlot", "WaistSlot", "LegsSlot", "FeetSlot", "WristSlot",
    "HandsSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot",
    "BackSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "TabardSlot",
}

--[==[ **Owned by the Character Panel now, drawn from here.**

     The border is a fact about the item in a slot, so the setting belongs on the
     page about the slots. The drawing stays here because it is woven into this
     module's item hooks, which serve the bags and the loot roll as well.

     Read through the other module's own `Config`, never by reaching into the
     saved table -- the two namespaces stay separate, which is the whole point of
     having moved it. ]==]
function M:CharacterPanel()
    return OB.modules and OB.modules.characterpanel
end

function M:RarityWanted()
    local panel = self:CharacterPanel()
    if not panel then return false end

    return OB.ModuleEnabled("characterpanel")
            and panel:Config().rarityBorders and true or false
end

--[==[ **The slot's own frame is coloured, not a second one drawn around it.**

     This built a backdrop of its own and hung it outside the button, so a rare
     item wore two borders: the client's, and ours around it. Two rings where
     the interface has one, and the outer one belonged to nobody -- it did not
     match the slot's art, its corners, or its thickness.

     Every item button in 1.12 already has the ring: it is the button's *normal
     texture*, the metal frame the client draws around the icon. Tinting that is
     one call, it fits by construction, and it is what the paper doll looks like
     when it is right -- the frame you already know, in the item's colour.

     `SetVertexColor` multiplies, so white is the untouched art and anything
     else is that same art in a colour. Putting it back is therefore setting it
     to white rather than remembering a texture. ]==]
function M:PaintRarity(button, quality)
    if not button or not button.GetNormalTexture then return false end

    local ring = button:GetNormalTexture()
    if not ring or not ring.SetVertexColor then return false end

    if not self:RarityWanted() or not quality or quality < RARITY_FLOOR then
        ring:SetVertexColor(1, 1, 1)
        self:PaintRarityGlow(button, nil)
        return false
    end

    local r, g, b = GetItemQualityColor(quality)

    if not r then
        ring:SetVertexColor(1, 1, 1)
        return false
    end

    ring:SetVertexColor(r, g, b)

    --[==[ **And an additive pass over it, because a multiply against dark metal
         is dark.**

         `SetVertexColor` multiplies, so a blue item tints a grey ring and comes
         out darker than the ring was. It fits by construction and it is hard to
         see, which is what was reported.

         The second pass is the same glow the bag window puts round a rare item
         -- `UI-ActionButton-Border`, additive, larger than the button -- so the
         two windows say the same thing in the same way. ]==]
    self:PaintRarityGlow(button, r, g, b)

    return true
end

--[[ The glow itself, made once per button and kept. Sized from the button so a
     paper doll slot and a bag slot both get a ring that fits them. ]]--
function M:PaintRarityGlow(button, r, g, b)
    local panel = self:CharacterPanel()
    local cfg = panel and panel:Config() or {}

    if not button.eqEcoGlow then
        if not r or not cfg.borderGlow then return false end

        local glow = button:CreateTexture(nil, "OVERLAY")
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetPoint("CENTER", button, "CENTER", 0, 0)

        local size = (button.GetWidth and button:GetWidth() or 36) * 1.7
        glow:SetWidth(size)
        glow:SetHeight(size)

        button.eqEcoGlow = glow
    end

    local glow = button.eqEcoGlow

    if not r or not cfg.borderGlow then
        glow:Hide()
        return false
    end

    glow:SetVertexColor(r, g, b, tonumber(cfg.borderGlowAlpha) or 0.55)
    glow:Show()

    return true
end

--[[ **The quality out of an item link**, which is where it lives in 1.12.

     `GetContainerItemInfo` returns a texture and a count and no quality at all,
     so the link is taken apart and handed to `GetItemInfo`. The item is in a
     bag, so it is in the client's cache and this costs nothing. ]]--
function M:LinkQuality(link)
    if not link then return nil end

    --[[ `string.find` with a capture rather than `string.match`, which this
         client does not have. ]]--
    local _, _, item = string.find(link, "|H(.+)|h")
    if not item then return nil end

    local _, _, quality = GetItemInfo(item)
    return quality
end

function M:RefreshBagRarity()
    if type(GetContainerItemLink) ~= "function" then return false end

    local per = MAX_CONTAINER_ITEMS or 20

    for bag = 1, 12 do
        local frame = getglobal("ContainerFrame" .. bag)

        if frame and frame.GetID then
            local id = frame:GetID()

            for slot = 1, per do
                local button = getglobal("ContainerFrame" .. bag .. "Item" .. slot)

                if button then
                    --[[ The button's own id, not the loop counter: the client
                         numbers a bag's buttons from the bottom right, so the
                         two disagree and colouring by the counter puts the
                         right border on the wrong slot. ]]--
                    local at = (button.GetID and button:GetID()) or slot
                    self:PaintRarity(button, self:LinkQuality(
                            GetContainerItemLink(id, at)))
                end
            end
        end
    end

    return true
end

function M:RefreshBankRarity()
    if type(GetContainerItemLink) ~= "function" then return false end

    for slot = 1, 28 do
        local button = getglobal("BankFrameItem" .. slot)

        if button then
            self:PaintRarity(button, self:LinkQuality(
                    GetContainerItemLink(-1, slot)))
        end
    end

    return true
end

function M:RefreshPaperdollRarity()
    if type(GetInventoryItemQuality) ~= "function" then return false end

    for slot, name in pairs(PAPERDOLL_SLOTS) do
        local button = getglobal("Character" .. name)
        if button then
            self:PaintRarity(button, GetInventoryItemQuality("player", slot))
        end
    end

    return true
end

--[==[ **The same borders on somebody else's gear.**

     The paperdoll pass above is hardwired to you twice over -- `Character` slot
     buttons and `"player"` -- so inspecting somebody showed their items with no
     borders at all. The slots are the same nineteen with a different prefix,
     and the quality comes from the unit being inspected rather than from you.

     **1.12 inspects the target and has no `InspectFrame.unit`**, which later
     clients added. Reading the field first and falling back to `"target"` works
     on both without asking which one this is.

     Quality is asked for directly, with the item link as the fallback. Whether
     `GetInventoryItemQuality` answers for a unit that is not you is the one
     thing here that cannot be settled without a live inspect, and the link
     route is already proven -- it is what the bags and the bank use. ]==]
function M:InspectUnit()
    local frame = getglobal("InspectFrame")
    return (frame and frame.unit) or "target"
end

function M:RefreshInspectRarity()
    local frame = getglobal("InspectFrame")
    if not frame then return false end
    if type(GetInventoryItemQuality) ~= "function" then return false end

    local unit = self:InspectUnit()

    for slot, name in pairs(PAPERDOLL_SLOTS) do
        local button = getglobal("Inspect" .. name)

        if button then
            local quality = GetInventoryItemQuality(unit, slot)

            if not quality and type(GetInventoryItemLink) == "function" then
                quality = self:LinkQuality(GetInventoryItemLink(unit, slot))
            end

            self:PaintRarity(button, quality)
        end
    end

    return true
end

--[==[ **Painted when the client fills a slot, not when the window opens.**

     A single pass on show runs before the server has answered, so the borders
     would be right only for gear the client happened to have cached already.
     The stock `InspectPaperDollItemSlotButton_Update` is called per slot as each
     one is filled in, which is exactly the moment to paint -- so it is wrapped
     where it exists, and the window's own show is the fallback where it is not.

     Idempotent, because the inspect UI is opened repeatedly and a wrapper that
     stacked would grow a layer each time. ]==]
function M:InstallInspectRarity()
    if self.inspectRarityInstalled then return false end
    if not getglobal("InspectFrame") then return false end

    self.inspectRarityInstalled = true

    if type(InspectPaperDollItemSlotButton_Update) == "function" then
        local original = InspectPaperDollItemSlotButton_Update

        InspectPaperDollItemSlotButton_Update = function(button)
            local result = original(button)
            local m = EquadisClassicOverhaul and EquadisClassicOverhaul.modules
                    and EquadisClassicOverhaul.modules.qol
            if m then m:RefreshInspectRarity() end
            return result
        end

        return true
    end

    local frame = getglobal("InspectFrame")

    if frame.HookScript then
        frame:HookScript("OnShow", function()
            local m = EquadisClassicOverhaul and EquadisClassicOverhaul.modules
                    and EquadisClassicOverhaul.modules.qol
            if m then m:RefreshInspectRarity() end
        end)
    end

    return true
end

--[[ **Opening a bag paints it**, because `BAG_UPDATE` fires when the contents
     change and not when somebody looks at them. Without this the borders are
     correct only from the first loot after opening -- which reads as the
     feature working intermittently.

     Wrapped once. `ContainerFrame_OnShow` is a global every bag shares, and
     re-wrapping it per bag would build a chain twelve deep. ]]--
function M:InstallRarityBorders()
    if self.rarityInstalled then return false end
    if type(ContainerFrame_OnShow) ~= "function" then return false end

    self.rarityInstalled = true

    local original = ContainerFrame_OnShow

    ContainerFrame_OnShow = function()
        original()
        OB.modules.qol:RefreshBagRarity()
    end

    return true
end

function M:RefreshRarity()
    self:RefreshBagRarity()
    self:RefreshBankRarity()
    self:RefreshPaperdollRarity()
    self:RefreshInspectRarity()
    return true
end

function M:OnBind()
    self:InstallDismount()
    self:InstallModelRotation()
    self:InstallLazyModelRotation()
    self:InstallBagClicks()
    self:InstallAttackWatch()
    self:InstallMapLabel()
    self:InstallConfirmSkip()
    self:InstallAutoRollCommands()
    self:InstallMacroIcons()
    self:HookMerchantUpdate()
    self:ApplyCamera()
    self:ApplyRightClick()
    self:InstallRarityBorders()

    --[[ Harmless when the inspect UI has not loaded -- it returns false
         and the lazy hook installs it later. This is for the other
         order: a reload in a session where somebody has already been
         inspected leaves the window built and the hook unfired. ]]--
    self:InstallInspectRarity()
    self:RefreshRarity()
end

function M:OnStyle()
    self:ApplyCamera()
    self:ApplyRightClick()
    self:ApplyModelArrows()
end

function M:OnDraw() end
