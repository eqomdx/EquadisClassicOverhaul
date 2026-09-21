--[[ Equadis' Classic Overhaul :: slash commands

  /eq, generated from the same option index the panel is generated from.

  Nothing here contains behaviour that is not reachable from the panel, and
  nothing in the panel is unreachable from here. That is the point of generating
  both from one table: Equadis' Threat Meter's predecessor had roughly a hundred
  lines of near-identical `elseif strlower(cmd) ==` blocks that had to be kept in
  step by hand, and were not.

  Grammar:

    /eq                          open the panel
    /eq help                     every option in every scope
    /eq <global option> [value]  e.g. scale 120, locked
    /eq bar <id> <key> [value]   e.g. bar resource h 20
    /eq <module> <key> [value]   e.g. power ticker nofull
    /eq profile use|new|copy|delete <name>
    /eq restack | test | reset [all]
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "Commands") end

local function p(msg) OB.Raw(msg) end

--[[ Sub-commands a later file adds, keyed by the word that invokes them:

       OB.commands.selftest = { help = "...", Run = function(args) ... end }

     The dispatcher below is an if-chain fixed at load time, and TOC order means
     anything that wants a command of its own loads after it. Rather than reach
     back and edit the chain -- which is exactly the hand-maintained drift this
     file exists to avoid -- a later file registers here and both the dispatch
     and the generated help pick it up. Phase 4's meters join the same way.

     The reserved words are matched first, so nothing appended later can shadow
     `help` or `reset`. ]]--
OB.commands = {}

local BLUE = "|cff69ccf0"
local WHITE = "|cffffffff"
local GREY = "|cffcccccc"
local GREEN = "|cffabd473"

-- ---------------------------------------------------------------------------
-- reporting
-- ---------------------------------------------------------------------------

--[[ Report a value, or flip it when no value was given.

     Flipping only makes sense for a boolean; for anything else "no value" is a
     query, which is what makes `/eq scale` a safe thing to type. ]]--
local function handleOption(w, label, args)
    if args == "" then
        if w.kind == "boolean" then
            OB.ApplyOption(w, not OB.ReadOption(w))
        end
        Say(label .. ": |cffffddcc" .. OB.DescribeOption(w))
        return
    end

    local err = OB.ParseOption(w, args)
    if err then
        Say("|cffff5511" .. err)
    else
        Say(label .. ": |cffffddcc" .. OB.DescribeOption(w))
    end
end

--[[ Option keys are camelCase (hideOOC, fontSize, textMode) but nobody types
     shift at a slash prompt, so a lookup falls back to a case-insensitive scan.
     Reserved words are matched lower-cased; option keys never are. ]]--
local function findOption(index, name)
    if not index or not name or name == "" then return nil end
    if index[name] then return index[name] end

    local wanted = string.lower(name)
    for key, w in pairs(index) do
        if string.lower(key) == wanted then return w end
    end

    return nil
end

local function listOptions(index, prefix)
    local keys = {}
    for key in pairs(index) do table.insert(keys, key) end
    table.sort(keys)

    for i = 1, table.getn(keys) do
        local w = index[keys[i]]
        p("  " .. BLUE .. prefix .. keys[i] .. WHITE .. " "
                .. OB.DescribeOption(w) .. " " .. GREY .. "- " .. w.caption)
    end
end

local function showHelp()
    --[[ **The version, first line, every time.**

         It was only ever printed by the self test, which meant the one question
         that has to be answerable before any other -- "which build am I looking
         at" -- could not be answered from inside the game. Two sessions were
         spent on a tab that was present in the code and absent on screen, and
         neither could settle it. ]]--
    p(GREEN .. OB.addonName .. WHITE .. " " .. (OB.version or "?")
            .. " commands:")
    p("  " .. BLUE .. "/eq" .. WHITE .. " / " .. BLUE .. "/eco" .. WHITE
            .. " - open the settings panel")
    p("  " .. BLUE .. "/eq test" .. WHITE .. " - start or stop the preview")
    p("  " .. BLUE .. "/eq restack" .. WHITE
            .. " - re-stack the occupied bars top to bottom")
    p("  " .. BLUE .. "/eq windows" .. WHITE
            .. " - where each meter window is stored and drawn")
    p("  " .. BLUE .. "/eq profile use|new|copy|delete <name>" .. WHITE)
    p("  " .. BLUE .. "/eq setup" .. WHITE
            .. " - the first-run walkthrough, again")
    p("  " .. BLUE .. "/eq profile export" .. WHITE
            .. " - every setting as one code to share")
    p("  " .. BLUE .. "/eq profile import" .. WHITE
            .. " - paste somebody else's")
    p("  " .. BLUE .. "/eq reset" .. WHITE .. " / " .. BLUE .. "reset all" .. WHITE
            .. " - this profile, or every profile")
    p("  " .. BLUE .. "/eq doctor" .. WHITE
            .. " - version, and which modules actually loaded")
    p("  " .. BLUE .. "/eq caps" .. WHITE
            .. " - which client extensions the addon can see, re-probed now")
    p("  " .. BLUE .. "/eq framedebug" .. WHITE
            .. " -- what the unit frames are actually wearing")
    p("  " .. BLUE .. "/eq minimapdebug" .. WHITE
            .. " -- where the group markers think they go")
    p("  " .. BLUE .. "/eq blipmatch" .. WHITE
            .. " -- draw group markers at both candidate scales at once")
    p("  " .. BLUE .. "/eq blipprobe" .. WHITE
            .. " -- paint every kind of minimap dot a different colour")
    p("  " .. BLUE .. "/eq waydebug" .. WHITE
            .. " -- what the arrow knows: facing, position and zone scale.")
    p("  " .. BLUE .. "/eq castdebug" .. WHITE
            .. " -- why each nameplate is or is not showing a cast")
    p("  " .. BLUE .. "/eq mapdebug" .. WHITE
            .. " -- everything drawn on a world map group marker")
    p("  " .. BLUE .. "/eq statdebug" .. WHITE
            .. " -- which character sheet stats this client can answer")
    p("  " .. BLUE .. "/eq debuffdebug" .. WHITE
            .. " -- why a debuff on your target has no timer under it")
    p("  " .. BLUE .. "/eq perf" .. WHITE
            .. " - start measuring; type it again for the report")
    p("  " .. BLUE .. "/eq perf time|deep" .. WHITE
            .. " - sort by time, or measure inside the hot functions")
    p("  " .. BLUE .. "/eq frames" .. WHITE
            .. " - what the unit frames and their borders actually measure")
    p("  " .. BLUE .. "/eq tm reset" .. WHITE
            .. " - threat meter back to the middle, every setting as it shipped")
    p("  " .. BLUE .. "/eq cmd" .. WHITE
            .. " - chat commands you can bind to anything in Key Bindings")

    -- listed from the registry, so a command added by a later file appears here
    -- without this function being touched
    local extra = {}
    for name in pairs(OB.commands) do table.insert(extra, name) end
    table.sort(extra)

    for i = 1, table.getn(extra) do
        local command = OB.commands[extra[i]]
        p("  " .. BLUE .. "/eq " .. extra[i] .. WHITE .. " - " .. (command.help or ""))
    end

    p(GREEN .. "Bars:" .. WHITE .. " " .. BLUE .. "/eq bar <id> <key> <value>")

    -- only the bars this class has: offering geometry for a rectangle that will
    -- never be drawn is just a way to waste somebody's afternoon
    local bars = OB.BarsForClass()
    local ids = {}
    for i = 1, table.getn(bars) do
        local id = bars[i]
        if OB.bound[id] then
            table.insert(ids, id)
        else
            table.insert(ids, id .. "=empty")
        end
    end
    p("  " .. GREY .. table.concat(ids, "  "))
    listOptions(OB.optionIndex.slot, "bar <id> ")

    p(GREEN .. "General:" .. WHITE .. " " .. BLUE .. "/eq <option> <value>")
    listOptions(OB.optionIndex.global, "")

    for i = 1, table.getn(OB.moduleOrder) do
        local id = OB.moduleOrder[i]
        local index = OB.optionIndex.modules[id]
        if index and OB.ClassAllows(OB.modules[id]) then
            p(GREEN .. OB.modules[id].name .. ":" .. WHITE .. " "
                    .. BLUE .. "/eq " .. id .. " <option> <value>")
            listOptions(index, id .. " ")
        end
    end
end

-- ---------------------------------------------------------------------------
-- sub-commands
-- ---------------------------------------------------------------------------

local function cmdBar(args)
    local _, _, barId, key, value = string.find(args, "^(%S+)%s+(%S+)%s*(.*)$")

    if not barId then
        Say("usage: /eq bar <id> <key> [value]")
        return
    end

    if not OB.profile.slots[barId] then
        Say("no bar named '" .. barId .. "'. Try: "
                .. table.concat(OB.barOrder, ", "))
        return
    end

    local w = findOption(OB.optionIndex.slot, key)
    if not w then
        Say("no bar setting named '" .. key .. "'.")
        return
    end

    --[[ Bar rows read through OB.panel.bar, which is also what the panel's
         selector drives. Pointing it at the named bar is what lets one set of
         row descriptors serve both. ]]--
    local previous = OB.panel.bar
    OB.panel.bar = barId
    handleOption(w, barId .. " " .. key, value or "")
    OB.panel.bar = previous
    OB.RefreshPanel()
end

--[[ `/eq assign <slot> <module>` lived here. It set which module drew in which
     slot, and it went with the rest of the assignment layer -- a bar and its
     module are one thing now, so there is nothing left to assign. ]]--

local function cmdProfile(args)
    local _, _, action, name = string.find(args, "^(%S*)%s*(.*)$")
    action = string.lower(action or "")

    if action == "" or action == "list" then
        local names = OB.ProfileNames()
        Say("profiles: " .. table.concat(names, ", "))
        Say("this character uses '" .. OB.profileName .. "'.")
        return
    end

    --[==[ Both take no name, so they are answered before the check below.
         A code is not a profile name and asking for one would be asking the
         reader to invent something the command does not use. ]==]
    if action == "export" or action == "code" then
        OB.ShowProfileCode()
        return
    end

    if action == "import" then
        --[[ A code pasted on the command line works, but a six hundred
             character slash command is not how anybody will do this, so an
             empty `import` opens the box rather than complaining. ]]--
        if name and name ~= "" then
            OB.ImportProfileCode(name)
        else
            OB.ShowProfileImport()
        end
        return
    end

    if name == "" then
        Say("usage: /eq profile " .. action .. " <name>")
        return
    end

    if action == "use" then OB.SetProfile(name)
    elseif action == "new" then OB.NewProfile(name)
    elseif action == "copy" then OB.CopyProfile(name)
    elseif action == "delete" then OB.DeleteProfile(name)
    else Say("usage: /eq profile use|new|copy|delete <name>, "
            .. "or export|import") end

    OB.RefreshPanel()
end

-- ---------------------------------------------------------------------------
-- dispatch
-- ---------------------------------------------------------------------------

--[[ **`/eq` and `/eco` are the names this addon goes by.**

     Everything else is history kept working. The addon was Equadis' OmniBars
     and is Equadis' Classic Overhaul, so `/eqob`, `/ob` and `/omnibars` still
     answer -- nobody should have to relearn a slash command because a title
     changed. That is a reason to keep them registered, not a reason to keep
     saying them: every message, every help line and every page of the
     documentation says `/eq`.

     `/eco` was missing from this list entirely until somebody typed it.

     Short before long, because the short ones are what get used. `/eq`, `/ob`
     and `/co` are two characters and will collide with something eventually --
     the client resolves a collision by taking whichever addon registered last,
     so if one stops working that is why, and the longer names are the ones
     that will not. ]]--
SLASH_EQUADISOMNIBARS1 = "/eq"
SLASH_EQUADISOMNIBARS2 = "/eco"
SLASH_EQUADISOMNIBARS3 = "/eqob"
SLASH_EQUADISOMNIBARS4 = "/ob"
SLASH_EQUADISOMNIBARS5 = "/omnibars"
SLASH_EQUADISOMNIBARS6 = "/co"
SLASH_EQUADISOMNIBARS7 = "/eqco"
SLASH_EQUADISOMNIBARS8 = "/equadis"
SLASH_EQUADISOMNIBARS9 = "/classicoverhaul"

--[[ **`/tt` as a command of its own**, because that is the name everybody knows
     it by. Prat shipped it and a decade of muscle memory types `/tt name` --
     `/eq tt` works too and nobody will ever use it.

     Registered separately rather than as another alias for the panel, since it
     takes an argument that has nothing to do with settings. ]]--
SLASH_EQUADISOVERHAULTELL1 = "/tt"
SLASH_EQUADISOVERHAULTELL2 = "/tellt"

SLASH_EQUADISOVERHAULCHATSCAN1 = "/chatscan"

--[[ The addon list, which 1.12 does not otherwise have once you are in the
     world -- the client's own is on the character-select screen and nowhere
     else. There is a button in the game menu as well; this is for people who
     would rather type. ]]--
SLASH_EQUADISOVERHAULBAGS1 = "/bags"
SLASH_EQUADISOVERHAULBAGS2 = "/bag"
SLASH_EQUADISOVERHAULBAGS3 = "/eqbags"

SlashCmdList["EQUADISOVERHAULBAGS"] = function(msg)
    local bags = OB.modules and OB.modules.bags

    if not bags then
        Say("the bag window is not loaded.")
        return
    end

    if not OB.ModuleEnabled("bags") then
        Say("switch Bags on first -- it is on the Modules page.")
        return
    end

    bags:Toggle()
end


--[[ **`/way` as a command of its own**, because that is the name everybody
     types. TomTom shipped it, every guide on the internet is written in it, and
     somebody pasting `/way 45 60 Vendor` out of a forum post should get a
     waypoint rather than an error.

     Registered separately rather than as another alias for the panel: it takes
     coordinates, which have nothing to do with settings. ]]--
--[==[ **What is marked in the zones you are not standing in.**

     `/way <zone> x y` can file a mark anywhere, and the map only ever draws the
     zone it is showing -- so without this a waypoint made for somewhere else is
     held and never shown again.

     Counted rather than listed. The full list answers "what is here"; this
     answers "is there anything I have forgotten", which a number does. ]==]
function OB.ListElsewhere(here)
    local way = OB.modules and OB.modules.waypoints
    local store = way and way.Store and way:Store()

    if not store then return 0 end

    local others = {}

    for zone, list in pairs(store) do
        if zone ~= here and type(list) == "table" and table.getn(list) > 0 then
            table.insert(others, zone .. " (" .. table.getn(list) .. ")")
        end
    end

    if table.getn(others) == 0 then return 0 end

    table.sort(others)
    OB.Raw("   elsewhere: " .. table.concat(others, ", "))

    return table.getn(others)
end

SLASH_EQUADISOVERHAULWAY1 = "/way"
SLASH_EQUADISOVERHAULWAY2 = "/waypoint"
SLASH_EQUADISOVERHAULWAY3 = "/eqway"

SlashCmdList["EQUADISOVERHAULWAY"] = function(msg)
    local way = OB.modules and OB.modules.waypoints

    if not way then
        Say("waypoints are not loaded.")
        return
    end

    if not OB.ModuleEnabled("waypoints") then
        Say("switch Waypoints on first -- it is on the Modules page.")
        return
    end

    msg = msg or ""

    local command = string.lower(OB.Trim(msg))

    if command == "clear" then
        way:ClearAll()
        return
    end

    if command == "" or command == "list" then
        local list = way:List()
        local zone = way:Zone() or "here"

        if table.getn(list) == 0 then
            Say("nothing marked in " .. zone .. ".")
            return
        end

        Say(table.getn(list) .. " marked in " .. zone .. ":")
        for i = 1, table.getn(list) do
            local point = list[i]
            OB.Raw(string.format("   %d. %.1f, %.1f  %s", i,
                    point.x * 100, point.y * 100, point.name or ""))
        end

        --[==[ **And what is marked everywhere else.**

             This listed the zone you are standing in and nothing more, which was
             the whole truth while a mark could only be made where you stood.
             `/way <zone> x y` broke that: a mark in Un'Goro made from Elwynn was
             then invisible from either -- not on the Elwynn list, and not on the
             map, which only draws the zone it is showing.

             A list that cannot see half of what it holds is how somebody ends up
             with waypoints they cannot find or clear. So the other zones are
             summarised rather than expanded: the full list is about *here*, and
             a count elsewhere is enough to say "go and look". ]==]
        OB.ListElsewhere(zone)
        return
    end

    --[==[ **The separator is anything that is not a number, and anything before
         the numbers is a zone.**

         Guides write coordinates every way there is: `45 60`, `45,60`,
         `45, 60`, and `45.5 60.2` with decimals. Matching two numbers and
         ignoring whatever sits between them accepts all of it, where a pattern
         built around one chosen separator rejects three quarters of what people
         paste.

         **And a name in front of them names the zone.** Control-clicking the
         continent map cannot place a mark -- converting that click needs every
         zone's rectangle on the continent and 1.12 exposes no such table -- so
         this is the way to mark somewhere you are not standing, and it is the
         way TomTom does it too.

         The leading capture is lazy, so `/way 45 60` still reads as no zone at
         all rather than as a zone with an empty name. ]==]
    local _, _, zone, x, y, name = string.find(msg,
            "^%s*(.-)%s*([%d%.]+)[^%d%.]+([%d%.]+)%s*(.*)$")

    if not x or not y then
        Say("that is not a coordinate -- try '/way 45 60', '/way 45 60 Vendor' "
                .. "or '/way Un'Goro Crater 45 60'.")
        return
    end

    if zone == "" then zone = nil end

    local point = way:Add(x, y, name, zone)

    if not point then
        Say("coordinates run from 0 to 100, and both have to be in the zone.")
        return
    end

    way:ApplyArrow()
    way:ApplyMapPin()

    --[==[ **The zone is named back whenever it was typed**, because a
         misspelled one is otherwise a mark filed somewhere nobody will ever
         look: the list is per zone, and a list for "Silithis" is a list nothing
         reads. Saying it makes the typo visible on the line that made it. ]==]
    Say("marked " .. string.format("%.1f, %.1f", point.x * 100, point.y * 100)
            .. (zone and (" in " .. zone) or "")
            .. (point.name and (" -- " .. point.name) or "") .. ".")
end
SLASH_EQUADISOVERHAULEDIT1 = "/eqedit"
SLASH_EQUADISOVERHAULEDIT2 = "/editmode"

SlashCmdList["EQUADISOVERHAULEDIT"] = function(msg)
    if type(OB.ToggleEditMode) ~= "function" then
        Say("edit mode is not loaded.")
        return
    end

    OB.ToggleEditMode()
end

SLASH_EQUADISOVERHAULADDONS1 = "/addons"
SLASH_EQUADISOVERHAULADDONS2 = "/addon"
SLASH_EQUADISOVERHAULADDONS3 = "/eqaddons"

SlashCmdList["EQUADISOVERHAULADDONS"] = function(msg)
    if type(OB.ToggleAddOnList) ~= "function" then
        Say("the addon list is not loaded.")
        return
    end

    OB.ToggleAddOnList()
end

-- Item Database shortcuts. /atlas intentionally opens ECO's unified database
-- rather than a second standalone Atlas window: Atlas-CFM and AtlasLoot are
-- bundled data/providers inside Classic Overhaul now.
SLASH_EQUADISOVERHAULDATABASE1 = "/db"
SLASH_EQUADISOVERHAULDATABASE2 = "/database"
SLASH_EQUADISOVERHAULDATABASE3 = "/eqdb"
SLASH_EQUADISOVERHAULDATABASE4 = "/atlas"

SlashCmdList["EQUADISOVERHAULDATABASE"] = function(msg)
    if not OB.profile then
        Say("still loading -- try again in a moment.")
        return
    end

    local database = OB.modules and OB.modules.itemdatabase
    if not database then
        Say("Item Database is not loaded.")
        return
    end

    database:OpenBrowser()
end

SlashCmdList["EQUADISOVERHAULTELL"] = function(msg)
    if not OB.profile then return end
    OB.modules.chat:TellTarget(msg)
end

--[==[ **`/addfriend`, which the client calls `/friend` and never mentions.**

     1.12 has the command and no way to find out it has it: it is absent from
     the social panel, absent from the help, and the panel's own Add Friend
     button opens a box you type into. Somebody who wants to add the person they
     are standing next to has to know a word nobody told them.

     Named for what it does rather than for what it is called, because that is
     the word people reach for. The client's `/friend` still works and this does
     not touch it. ]==]
SLASH_EQUADISOVERHAULADDFRIEND1 = "/addfriend"
SLASH_EQUADISOVERHAULADDFRIEND2 = "/eqfriend"

--[[ Whoever on the list answers to this name, whatever case it was typed in.
     Answered with the *stored* spelling, so the reply says the name the way the
     list has it rather than the way it was typed. ]]--
function OB.FriendNamed(name)
    if type(name) ~= "string" or name == "" then return nil end
    if type(GetNumFriends) ~= "function" then return nil end
    if type(GetFriendInfo) ~= "function" then return nil end

    local wanted = string.lower(name)

    for i = 1, (GetNumFriends() or 0) do
        local who = GetFriendInfo(i)
        if who and string.lower(who) == wanted then return who end
    end

    return nil
end

--[==[ **Adding one, and saying what happened.**

     `AddFriend` is silent in both directions: it says nothing when it works and
     nothing when the name is already on the list. The second is the one worth
     answering -- typing it twice looks exactly like typing it once and having
     it fail, so somebody types it a third time.

     **A bare command means the target**, which is the case this gets typed in:
     somebody helpful in a group, already selected. Only a player, because
     `AddFriend` on a mob's name writes a friend who can never come online. ]==]
function OB.AddFriendByName(msg)
    local name = OB.Trim(msg)

    if name == "" then
        if type(UnitExists) == "function" and UnitExists("target")
                and type(UnitIsPlayer) == "function" and UnitIsPlayer("target")
                and type(UnitName) == "function" then
            name = UnitName("target") or ""
        end
    end

    if name == "" then
        Say("who? -- /addfriend <name>, or target somebody and type it bare.")
        return false
    end

    local already = OB.FriendNamed(name)

    if already then
        Say(already .. " is already on your friends list.")
        return false
    end

    if type(AddFriend) ~= "function" then
        Say("this client has no friends list to add to.")
        return false
    end

    AddFriend(name)
    Say("added " .. name .. " to your friends list.")
    return true
end

SlashCmdList["EQUADISOVERHAULADDFRIEND"] = function(msg)
    OB.AddFriendByName(msg)
end

SlashCmdList["EQUADISOVERHAULCHATSCAN"] = function(msg)
    if not OB.profile then
        Say("still loading -- try again in a moment.")
        return
    end

    local roster = OB.modules and OB.modules.roster
    if not roster then
        Say("ChatScan is not loaded.")
        return
    end

    msg = string.gsub(msg or "", "^%s*(.-)%s*$", "%1")
    local word = string.lower(msg)

    local function tell(line) OB.Raw("   " .. line) end

    --[==[ **Three shapes, and the bare command is the first of them.**

         `/chatscan` starts the whole sweep, `/chatscan stop` ends it, and
         `/chatscan 34` or `/chatscan 50-60` scan a level or a range. That is
         the set asked for, and `start` is gone from all of them: the word
         said nothing the command did not already say. A class name still
         works in the same place a level does, and `help` says all this. ]==]
    if word == "help" or word == "?" then
        local what = "progressively scans the /who list and puts what it learns"
                .. " -- level, class, guild -- against the names in your chat."
        OB.Print(what, "ChatScan")

        tell("|cffffd100/chatscan|r  everybody, level by level")
        tell("|cffffd100/chatscan 34|r  one level")
        tell("|cffffd100/chatscan 50-60|r  a range of levels")
        tell("|cffffd100/chatscan mage|r  one class, in bands of ten")
        tell("|cffffd100/chatscan stop|r  stop the one that is running")
        return
    end

    if word == "stop" then
        if not roster:Sweeping() then
            OB.Print("nothing is running.", "ChatScan")
            return
        end

        roster:SetScanning(false)
        return
    end

    --[[ The old spelling, quietly: `/chatscan start 34` is `/chatscan 34`. ]]--
    local _, _, after = string.find(word, "^start%s*(.*)$")
    if after then word = after end

    --[[ One scan at a time. The queue is one list and a second start would
         throw away whatever the first had left to do, silently. ]]--
    if roster:Sweeping() then
        OB.Print("a scan is already running -- '/chatscan stop' first.",
                "ChatScan")
        return
    end

    if word == "" then
        roster:SetScanning(true)
        return
    end

    --[[ **A range before a single level**, because `50-60` also matches the
         number pattern at its first character and would otherwise be read as
         level fifty with some rubbish after it. ]]--
    local _, _, low, high = string.find(word, "^(%d+)%s*%-%s*(%d+)$")

    if low then
        local queued = roster:StartRangeScan(low, high)

        if queued == 0 then
            OB.Print("levels run from 1 to 60.", "ChatScan")
            return
        end

        roster:BeginQueuedScan("levels " .. low .. "-" .. high)
        return
    end

    local level = tonumber(word)

    if level then
        if level < 1 or level > 60 or level ~= math.floor(level) then
            OB.Print("levels run from 1 to 60.", "ChatScan")
            return
        end

        roster:SetScanning(true, level)
        return
    end

    --[[ Anything that is not a number is a class name, which is the only other
         thing this takes -- so an unknown word is answered as an unknown class
         rather than as a syntax error, because that is what it almost always
         is. ]]--
    local class = roster:ClassNamed(word)

    if not class then
        local unknown = "'" .. msg .. "' is not a level or a class -- "
                .. "'/chatscan help' lists what this takes."
        OB.Print(unknown, "ChatScan")
        return
    end

    roster:StartClassScan(class)
    roster:BeginQueuedScan(class .. "s")
end

SlashCmdList["EQUADISOMNIBARS"] = function(msg)
    if not OB.profile then
        Say("still loading -- try again in a moment.")
        return
    end

    local _, _, raw, args = string.find(msg or "", "^%s*(%S*)%s*(.*)$")
    raw = raw or ""
    args = args or ""

    -- reserved words match case-insensitively; option keys keep their case and
    -- go through findOption, which does its own fallback
    local cmd = string.lower(raw)

    if cmd == "" or cmd == "config" or cmd == "options" then
        OB.TogglePanel()
        return
    end

    --[[ The weapon enchant mapping, which has been guessed wrong twice. See
         `DebugEnchants`. ]]--
    if cmd == "enchantdebug" then
        local buffs = OB.modules and OB.modules.buffframes
        if buffs then buffs:DebugEnchants() else Say("buff frames not loaded.") end
        return
    end

    --[[ The green square behind the party markers and not the raid ones,
         which nothing in the module can account for. See `DebugIcons`. ]]--
    if cmd == "mapdebug" then
        local map = OB.modules and OB.modules.map
        if map then map:DebugIcons() else Say("the map module is not loaded.") end
        return
    end

    --[==[ **Which client extensions the addon can see, asked again right now.**

         Home shows the same four names, but from answers cached when the addon
         first asked -- and that was the trap. An extension injected after
         that first question stays "missing" for the whole session: the DLL
         loader says yes, the extension answers commands, and only the addon
         says no. Nothing re-asked, because `OB.RecheckCapabilities` existed
         for exactly this and nothing called it.

         So the cache is forgotten first, and what is printed is the truth as
         of this second. Each verdict carries the probes behind it, because
         "UnitXP: missing" is a conclusion and "UnitXP: unitxp=no" is a lead --
         it names the one question that failed, which is where to look next. ]==]
    if cmd == "caps" then
        OB.RecheckCapabilities()
        Say("client extensions, re-probed:")

        for i = 1, table.getn(OB.enhancements or {}) do
            local entry = OB.enhancements[i]
            local active = OB.EnhancementActive(entry.key)

            local probes = {}
            for c = 1, table.getn(entry.caps) do
                local cap = entry.caps[c]
                probes[c] = cap .. (OB.Can(cap) and "=yes" or "=no")
            end

            p("  " .. (active and GREEN or "|cffff5511") .. entry.name .. "|r  "
                    .. (active and "active" or "missing") .. "   "
                    .. GREY .. table.concat(probes, "  ") .. "|r")

            if not active and OB.enhancementLoss and OB.enhancementLoss[entry.key] then
                p("      " .. GREY .. OB.enhancementLoss[entry.key] .. "|r")
            end
        end
        return
    end

    --[[ Which stat calls this client actually has, which is what settles
         whether crit and hit can be drawn at all. See `DebugStats`. ]]--
    if cmd == "statdebug" then
        local sheet = OB.modules and OB.modules.characterpanel
        if sheet then sheet:DebugStats() else Say("the character panel is not loaded.") end
        return
    end

    --[[ Which link in the chain is missing when a debuff has no number under
         it. See `OB.DebuffChainDebug`. ]]--
    if cmd == "debuffdebug" then
        if OB.DebuffChainDebug then OB.DebuffChainDebug()
        else Say("the aura tracker is not loaded.") end
        return
    end

    if cmd == "setup" then OB.ShowSetup() return end

    if cmd == "help" then showHelp() return end

    if cmd == "test" then
        OB.ToggleTestMode()
        if OB.testMode then
            Say("preview running.")
        else
            Say("preview stopped.")
        end
        return
    end

    --[[ What the unit frames actually measure. A screenshot shows the result;
         this shows the numbers behind it, which is what says whether the bar
         moved or the border did. ]]--
    --[==[ **`/eq bars` used to be unreachable, and nothing could have said so.**

         Its whole block had been pasted *inside* this one: `if cmd == "frames"`
         opened, and the next thing after its guard was `if cmd == "bars"`, with
         the two `end`s at the bottom closing them in the wrong order. Perfectly
         valid Lua -- the braces balance -- and perfectly dead, because reaching
         the inner test required `cmd` to be both words at once.

         `/eq frames` still worked, which is why it went unnoticed: it fell past
         the bars block to its own report at the bottom. Only the second command
         was lost. ]==]
--[==[ **One block per word, because the second one is dead.**

     `frames` and `bars` each had two: a report block here and a drag-mode block
     several hundred lines below. The dispatcher is a chain of `if cmd == "..."`
     that **returns**, so the first one wins and the second could never run --
     which means *moving the action bars and the unit frames could not be asked
     for at all*, and `/eq bars reset` quietly printed a report instead of
     resetting anything.

     Third time this shape has been found. `/eq bars` was once pasted inside
     `if cmd == "frames"` and could never be typed; a second `mapdebug` was
     written an hour ago and was dead before it was saved. The suite now refuses
     two blocks claiming one word, which is the check that would have caught all
     three.

     Merged rather than renamed: `/eq frames` has meant "tell me about the
     frames" for long enough to leave alone, and the mode is what wants a word of
     its own. ]==]
    if cmd == "frames" then
        local frames = OB.modules.unitframes
        local what = string.lower(args or "")

        if not frames then
            Say("the unit frames module is not loaded.")
            return
        end

        if what == "reset" then
            frames:ResetPositions()
            return
        end

        if what == "move" then
            frames:SetDragMode(not frames:DragMode())
            return
        end

        if type(frames.ReportGeometry) ~= "function" then
            Say("the unit frames module is not loaded.")
            return
        end

        frames:ReportGeometry()
        return
    end

    --[[ What each bar was asked for, what shape that works out to, and where
         the buttons actually went -- which is three different things that a
         screenshot of a wrong-looking bar cannot tell apart. ]]--
    if cmd == "bars" then
        local bars = OB.modules.actionbars
        local what = string.lower(args or "")

        if not bars then
            Say("the action bars module is not loaded.")
            return
        end

        if what == "reset" then
            bars:ResetPositions()
            return
        end

        if what == "move" then
            bars:SetDragMode(not bars:DragMode())
            return
        end

        if type(bars.ReportBars) ~= "function" then
            Say("the action bars module is not loaded.")
            return
        end

        bars:ReportBars()
        return
    end

    if cmd == "windows" then OB.PrintWindowReport() return end

    --[[ **Where the time and the garbage go**, which is the question three
         rounds of dungeon-lag fixes were answered by guessing at. The game's
         own profiler names the frame script; this names the function.

         `perf` rather than `profile`, which this addon has meant "settings
         profile" since long before there was anything to measure. ]]--
    if cmd == "perf" then
        --[[ Guarded like every other optional call in this addon, and for a
             reason that bit immediately: **1.12 does not reliably pick up a
             file newly added to the TOC on `/reload`.** The command existed and
             the file behind it did not, so typing it threw rather than saying
             so.

             A missing function is a restart away from working, which is worth
             saying out loud. It is not worth an error. ]]--
        if type(OB.ToggleProfile) ~= "function" then
            Say("the profiler is not loaded. Adding a file needs a full restart "
                    .. "-- log out to the desktop rather than reloading.")
            return
        end

        OB.ToggleProfile(string.lower(args or ""))
        return
    end

    --[==[ **The one question a screenshot has never answered.** See
         `DebugFrameLayout`: this alignment has been diagnosed from pictures four
         times and been wrong four times, and what is missing is never the
         reasoning, it is the state. ]==]
    --[==[ **The same question as `minimapdebug`, asked with pictures.**

         That command prints both candidate distances and has now been read four
         times without settling anything, because the numbers are consistent with
         either reading. This draws both instead: the class marker where the rule
         in use puts it, a grey dot where the other rule puts it, and the
         client's own coloured dot underneath as the truth. ]==]
    --[==[ **Which cell is which**, asked with colours because there is no call
         that says. See `M:ToggleBlipProbe`. ]==]
    --[==[ **Why a plate has no cast bar**, which has six answers that look the
         same on screen. See `M:DebugCastBars`. ]==]
    if cmd == "castdebug" then
        local plates = OB.modules and OB.modules.nameplates

        if not plates or type(plates.DebugCastBars) ~= "function" then
            Say("the nameplate module is not loaded.")
            return
        end

        plates:DebugCastBars()
        return
    end

    if cmd == "waydebug" then
        local way = OB.modules and OB.modules.waypoints

        if not way or type(way.Debug) ~= "function" then
            Say("the waypoint module is not loaded.")
            return
        end

        way:Debug()
        return
    end

    --[==[ **`coorddebug`, not `mapdebug`.** This shipped as a second
         `mapdebug` block, and the one three hundred lines above it answers that
         word first -- so this was unreachable from the moment it was written.
         Exactly the `/eq bars` fault, which was a block pasted inside another
         `if` and could never be typed either. The suite types every word now and
         **refuses two blocks claiming the same one**, which is what would have
         caught this before it was written. ]==]
    --[==[ **`/eq buffs move` and `/eq buffs reset`.**

         The Buff Frames page had a Position section holding exactly these two,
         and it is gone: unlocking is what edit mode is, one gesture for every
         frame in the addon rather than a button per module. The reset had
         nowhere else to live and is the only way back from a layout somebody has
         dragged off the screen, so it comes here -- where `/eq bars reset` and
         `/eq frames reset` already are. ]==]
    if cmd == "buffs" then
        local buffs = OB.modules and OB.modules.buffframes
        local what = string.lower(args or "")

        if not buffs then
            Say("the buff frames module is not loaded.")
            return
        end

        if what == "reset" then
            buffs:ResetPositions()
            return
        end

        if what == "move" then
            buffs:SetDragMode(not buffs:DragMode())
            return
        end

        Say("'/eq buffs move' to drag them, '/eq buffs reset' to put them back.")
        return
    end

    if cmd == "coorddebug" then
        local map = OB.modules and OB.modules.map

        if not map or type(map.DebugCoordinates) ~= "function" then
            Say("the map module is not loaded.")
            return
        end

        map:DebugCoordinates()
        return
    end

    if cmd == "pvpdebug" then
        local frames = OB.modules and OB.modules.unitframes

        if not frames or type(frames.DebugPVP) ~= "function" then
            Say("the unit frame module is not loaded.")
            return
        end

        frames:DebugPVP()
        return
    end

    if cmd == "blipprobe" then
        local map = OB.modules and OB.modules.map

        if not map or type(map.ToggleBlipProbe) ~= "function" then
            Say("the map module is not loaded.")
            return
        end

        map:ToggleBlipProbe()
        return
    end

    if cmd == "blipmatch" then
        local map = OB.modules and OB.modules.map

        if not map or type(map.ToggleBlipMatch) ~= "function" then
            Say("the map module is not loaded.")
            return
        end

        map:ToggleBlipMatch()
        return
    end

    if cmd == "minimapdebug" then
        local map = OB.modules and OB.modules.map

        if not map or type(map.DebugMinimapMarkers) ~= "function" then
            Say("the map module is not loaded.")
            return
        end

        map:DebugMinimapMarkers()
        return
    end

    if cmd == "framedebug" then
        local frames = OB.modules and OB.modules.unitframes

        if not frames or type(frames.DebugFrameLayout) ~= "function" then
            Say("the unit frames module is not loaded.")
            return
        end

        frames:DebugFrameLayout()
        return
    end

    if cmd == "restack" then
        OB.RestackBars()
        OB.Refresh(true)
        OB.RefreshPanel()
        Say("slots restacked -- this moves them for every character on the '"
                .. OB.profileName .. "' profile.")
        return
    end

    if cmd == "reset" then
        if string.lower(args) == "all" then
            StaticPopup_Show("EQOB_RESET_ALL")
        else
            StaticPopup_Show("EQOB_RESET_PROFILE")
        end
        return
    end

    --[[ What the addon knows about other players, which is not a setting and so
         is not reached by either reset. `report` because a store that grows
         quietly should be countable, and `forget` because it is the only way
         back. ]]--
    if cmd == "roster" then
        if string.lower(args) == "forget" then
            OB.ForgetRoster()
        else
            OB.PrintRosterReport()
        end
        return
    end

    --[[ **Marking something to sell this once**, which is a different act from
         deciding you never want it again -- that one is a setting and lives on
         the panel.

         A command rather than a control because the panel is not what is in
         front of you at a vendor, and because this is an action rather than a
         preference. It stops being true when the merchant window closes. ]]--
    if cmd == "sell" then
        local m = OB.modules.qol

        if args == "" then
            local sold = m:SellJunk()
            Say(sold > 0 and ("sold " .. sold .. ".")
                    or "nothing to sell -- open a vendor first.")
        elseif m:MarkForSale(args) then
            Say("'" .. args .. "' will be sold at this vendor. "
                    .. "Type '/eq sell' to do it now.")
        end
        return
    end

    --[[ The never-keep list, from the keyboard. The panel holds the same string
         in a field; this is for adding the thing you are looking at without
         opening anything. ]]--
    if cmd == "trash" then
        local list = OB.TrashList()

        if args == "" then
            Say(list == "" and "nothing is on your never-keep list."
                    or ("never keeping: " .. list))
            return
        end

        --[[ Appended rather than replacing, because somebody typing
             `/eq trash Broken Fang` means "and this one too". Replacing a list
             of things to destroy on the strength of one word would be a poor
             way to find out otherwise. ]]--
        if list == "" then
            EquadisClassicOverhaulDB.trash = args
        else
            EquadisClassicOverhaulDB.trash = list .. ", " .. args
        end

        OB.RefreshPanel()
        Say("'" .. args .. "' added. Anything on this list is destroyed "
                .. "when it arrives -- '/eq trash' shows the whole list.")
        return
    end

    --[[ Trash mode. A command rather than a panel control because it is a mode
         you turn on for ten seconds with your bags open, and the panel would be
         covering the bags. ]]--
    if cmd == "select" then
        local m = OB.modules.qol
        local what = string.lower(args)

        if what == "none" then
            m:ClearSelection()
            Say("selection cleared.")
            return
        end

        if what == "trash" then
            local items = m:SelectedItems()
            local count = table.getn(items)

            if count == 0 then
                Say("nothing selected. '/eq select' then click items.")
                return
            end

            --[[ Said before the dialog, because the dialog cannot hold a list
                 and the list is the part worth reading twice. ]]--
            local valuable = m:ValuableInSelection()

            if table.getn(valuable) > 0 then
                Say("about to destroy " .. count .. " items, including: "
                        .. table.concat(valuable, ", ") .. ".")
            end

            StaticPopup_Show("EQOB_TRASH_SELECTED")
            return
        end

        if what == "sell" then
            local sold = m:SellSelected()
            Say(sold > 0 and ("sold " .. sold .. ".")
                    or "nothing sold -- open a vendor first.")
            return
        end

        m:SetSelectMode(not m:SelectMode())

        if m:SelectMode() then
            Say("trash mode on -- click items in your bags to choose them, "
                    .. "then '/eq select trash' or '/eq select sell'.")
        else
            Say("trash mode off.")
        end
        return
    end

    --[[ Bind mode, which is a mode rather than a setting: you turn it on, do a
         thing with the mouse and keyboard, and turn it off. The panel could not
         host it if it wanted to -- the first thing it does is close the panel. ]]--
    if cmd == "bind" then
        local m = OB.modules.actionbars
        m:SetBindMode(not m:BindMode())
        return
    end

    --[[ Moving the bars is `/eq bars move` now, handled with the report above.
         It lived here as a second `if cmd == "bars"` and was unreachable. ]]--

    --[[ **One command that says what actually loaded.**

         A tab going missing has one cause -- the module file threw while
         loading, so the client carried on with the next file and the
         registration never ran -- and no way to see it from inside the game
         except a line at login that is easy to miss.

         This reports the version, every declared tab and whether its module is
         there, so a bug report is one paste instead of a conversation. It reads
         nothing but the registry, so it works when the thing being diagnosed is
         a module that is not there. ]]--
    if cmd == "doctor" then
        Say(OB.addonName .. " " .. (OB.version or "?"))

        --[[ **Who else is drawing the same frames**, reported on demand.

             This is warned about once at login, and a line printed during a
             loading screen is a line nobody reads. It belongs here too: doctor
             is what somebody types when the interface looks wrong, and "two
             addons own this frame" is the answer often enough to be worth
             asking every time.

             Two addons hooking one frame do not error. The loser stops changing
             pixels, or wins some of them and not others, and the result reads as
             a module that is broken rather than as a fight. ]]--
        local clashes = OB.ConflictingAddOns()

        for i = 1, table.getn(clashes) do
            local entry = clashes[i]
            Say("  |cffff5511" .. entry.addon .. "|r is also drawing "
                    .. entry.label .. " -- turn it off in /addons and reload.")
        end

        --[[ Not a clash -- a handoff, see `bags:InstallBagHooks`. Said here
             because "why does B open Bagshui and not this" is otherwise a
             mystery with nothing in chat about it. ]]--
        local bags = OB.modules and OB.modules.bags
        if bags and bags.bagKeyOwner then
            Say("  " .. bags.bagKeyOwner .. " has the bag key; Equadis's "
                    .. "Inventory opens from its backpack button.")
        end

        --[[ **Which files actually loaded**, reported before anything else,
             because it is the first question worth answering when a command
             misbehaves and the hardest to answer from a symptom.

             A file newly added to the TOC does not reliably load on `/reload`
             on 1.12. The addon looks updated -- the version string is new,
             because that file did load -- and one file is missing. There is no
             way to tell from the outside, so it is reported from the inside. ]]--
        if not OB.profilerLoaded then
            Say("  profiler: |cffff5511did not load|r -- log out to the desktop "
                    .. "and back in, not just reload.")
        end

        --[[ How far chat.lua got before it died, which the client will not say.
             nil means it never compiled -- a syntax error, which on 1.12 means
             something Lua 5.0 rejects and 5.1 accepts. ]]--
        --[[ How far the chat files got, which the client will not say. Only
             when something is wrong with them: a marker on a healthy boot is a
             number nobody needs. ]]--
        if not OB.modules.chat or table.getn((OB.modules.chat.options) or {}) == 0 then
            Say("  chat load marker: |cffff5511"
                    .. tostring(OB.chatLoad or "nothing -- chat.lua did not compile")
                    .. "|r")
        end

        local missing = 0

        for i = 1, table.getn(OB.featureTabs or {}) do
            local entry = OB.featureTabs[i]
            local ids = entry

            if type(entry) ~= "table" then ids = { entry } end

            for k = 1, table.getn(ids) do
                local id = ids[k]

                if OB.modules[id] then
                    local rows = table.getn(OB.modules[id].options or {})

                    --[[ **A finished module with no rows is not healthy**, and
                         it reads as healthy: the tab appears, the module is
                         registered, and the page is empty. It happens when the
                         rows live in a second file that did not load -- which
                         on this client is what a new TOC entry does until the
                         game is fully restarted, because /reload does not pick
                         up a file the client did not see at launch. ]]--
                    if rows == 0 and not OB.modules[id].development then
                        missing = missing + 1
                        Say("  |cffff5511" .. id .. ": loaded but has NO "
                                .. "ROWS|r -- restart the game rather than "
                                .. "reloading")
                    else
                        Say("  " .. id .. ": loaded, " .. rows .. " rows")
                    end
                else
                    missing = missing + 1
                    Say("  |cffff5511" .. id .. ": DID NOT LOAD|r")
                end
            end
        end

        if missing > 0 then
            Say("|cffff5511" .. missing .. " module"
                    .. (missing == 1 and "" or "s") .. " missing|r -- look for a "
                    .. "Lua error at login. Turn Blizzard's error display on "
                    .. "with '/console scriptErrors 1' and reload.")
        else
            Say("every declared tab has its module.")
        end

        for i = 1, table.getn(OB.panelFaults or {}) do
            Say("  |cffff5511panel|r " .. OB.panelFaults[i].label .. ": "
                    .. OB.panelFaults[i].err)
        end

        return
    end

    --[[ What the chat commands are. A fixed list now rather than one somebody
         edits, so this reports rather than manages. ]]--
    if cmd == "cmd" or cmd == "commands" then
        OB.PrintCommands()
        return
    end

    --[[ **The way out of a window nobody can find.**

         A meter dragged off the edge, or carried over from a larger screen, is
         saved at coordinates that are nowhere on this one -- and from the
         inside that is indistinguishable from a meter that does not work. So is
         a meter hidden by Show When Solo while solo. This puts it back in the
         middle with every setting as it shipped, which answers all of those at
         once rather than asking somebody to work out which it was. ]]--
    if cmd == "tm" or cmd == "threat" then
        if string.lower(args) == "reset" then
            OB.modules.threat:ResetEverything()
        else
            --[[ Built first so the part name sits on the `OB.Print` line
                 itself: an unnamed print is checked for by matching the call
                 up to its first comma, and a message wrapped across lines puts
                 that comma out of reach. ]]--
            local help = "'/eq tm reset' puts the meter back in the middle of "
                    .. "the screen with every setting as it shipped."

            OB.Print(help, "Threat")
        end
        return
    end

    --[[ **What is actually hanging off the minimap, by name.**

         Every addon that wants a minimap button parents one to `Minimap` and
         names it whatever it likes. There is no list to read and no convention
         to rely on, so the only way to act on a particular one -- move the
         group finder onto the micro menu, say -- is to ask the client what it
         is called.

         Printed rather than guessed at. Two rounds of this were lost today to
         names assumed rather than read. ]]--
    if cmd == "minimap" then
        local map = getglobal("Minimap")

        if not map or not map.GetChildren then
            OB.Print("no minimap to look at.", "Map")
            return
        end

        local kids = { map:GetChildren() }
        local shown = 0

        OB.Print("buttons on the minimap:", "Map")

        for i = 1, table.getn(kids) do
            local child = kids[i]
            local name = child and child.GetName and child:GetName()

            if name then
                shown = shown + 1
                OB.Raw(string.format("   %-34s %s", name,
                        child.IsShown and child:IsShown() and "shown" or "hidden"))
            end
        end

        if shown == 0 then OB.Raw("   nothing named") end
        return
    end

    --[[ The same for the player and target frames: `/eq frames move`, handled
         with the report above. Separate from `bars` because they are separate
         frames with separate saved positions, and one command that moved both
         would be a mode nobody could aim. ]]--

    --[[ What each chat window is actually holding, and the way back if the
         removal memory has learned something wrong. Both exist because chat
         settings coming back changed after a reload is not something reading the
         code has been able to settle. ]]--
    if cmd == "chat" then
        --[[ Finding a line that has scrolled away. Results print into chat,
             which reads better than scrolling a window to a hit -- and is the
             reason the search box Prat anchors to every frame is not here. ]]--
        local _, _, verb, rest = string.find(args, "^(%S*)%s*(.*)$")

        if string.lower(verb or "") == "find" then
            OB.modules.chat:Find(rest)
            return
        end

        if string.lower(args) == "forget" then
            local db = EquadisClassicOverhaulDB.chatRemovals or {}
            db[OB.CharacterKey()] = {}
            OB.chatRemovals = db[OB.CharacterKey()]

            Say("forgot which channels you had taken out of which window.")
        else
            OB.modules.chat:PrintReport()
        end
        return
    end

    --[[ Whisper whoever you are looking at. Prat's `/tt`, and one of the
         most-used things it ships -- which is a fair summary of how much of a
         chat addon is small. ]]--
    if cmd == "tt" then
        OB.modules.chat:TellTarget(args)
        return
    end

    if cmd == "bar" then cmdBar(args) return end
    if cmd == "profile" then cmdProfile(args) return end

    -- a registered command beats a module id, because a command word is the more
    -- specific claim on the line
    local command = OB.commands[cmd]
    if command then command.Run(args) return end

    -- a module id claims the rest of the line
    if OB.optionIndex.modules[cmd] then
        local _, _, key, value = string.find(args, "^(%S*)%s*(.*)$")
        local w = findOption(OB.optionIndex.modules[cmd], key)

        if not w then
            Say("no '" .. cmd .. "' setting named '" .. tostring(key)
                    .. "'. Type " .. BLUE .. "/eq help" .. WHITE .. " for a list.")
            return
        end

        handleOption(w, cmd .. " " .. key, value or "")
        return
    end

    local w = findOption(OB.optionIndex.global, raw)
    if not w then
        Say("unknown option |cffff5511" .. raw .. WHITE .. ". Type "
                .. BLUE .. "/eq help" .. WHITE .. " for a list.")
        return
    end

    handleOption(w, w.caption, args)
end
