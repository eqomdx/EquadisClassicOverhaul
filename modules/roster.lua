--[[ Equadis' Classic Overhaul :: roster

  **What the addon knows about other players, and how it finds out.**

  The store itself is in config.lua, at the root of the saved variables rather
  than inside a profile, for the reason given there: "Grimtusk is a level 60
  warrior" is a fact about the world and not a setting your rogue might disagree
  with. This module is everything that writes to it.

  Two halves. The first is passive and free -- the client hands over a guild
  roster, a friends list, a raid, and each of those is a list of people whose
  class and level are right there. Prat's PlayerNames did this and the readers
  below are its readers.

  The second half is the part Prat had no answer for: **most of the names in
  General and World belong to nobody you have ever grouped with**, so the passive
  half never learns them and they stay uncoloured forever. The only way to find
  out is to ask, and the only thing to ask with is `/who`.

  Kept separate from the chat module on purpose. Chat *shows* what is known;
  this decides what is known. Nameplates and unit frames will want the same
  answers, and neither of them should have to switch a chat module on to get
  them.
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "ChatScan") end

--[[ The server may report more matches than it can return as rows. The second
     value from GetNumWhoResults is that uncapped total; only a total above this
     threshold needs a narrower class-by-class query. ]]--
local WHO_SPLIT_THRESHOLD = 50

--[[ Where the sweep starts. Ten-level bands, because a decade of a populated
     realm is usually under the cap and the ones that are not get split -- which
     is cheaper than starting fine and sending sixty queries to learn that
     fifty-nine of them were nearly empty. ]]--
local BANDS = {
    { 1, 10 }, { 11, 20 }, { 21, 30 }, { 31, 40 }, { 41, 50 }, { 51, 60 },
}

local M = OB.RegisterModule({
    id = "roster",
    name = "Players",

    --[[ A feature that owns no window: it decorates nothing and draws nothing,
         it only knows things. Same shape as the chat module. ]]--
    feature = true,
    renders = "none",

    --[[ **On**, unlike the chat module, because the passive half costs a table
         write when the client hands over a roster it was going to build anyway,
         and because everything that colours a name reads from it. Switching it
         off is for somebody running another addon that does the same job.

         The half that talks to the server is a separate switch, below, and that
         one is off. ]]--
    defaultEnabled = true,

    --[[ Ticked, for the scan timer. Nothing else here needs a frame. ]]--
    tickly = true,

    defaults = {
        --[[ **Asking the server, which is the half that has a cost.**

             Off. Everything above this line is reading a list the client already
             had; this sends packets, and an addon that quietly starts querying
             the server on your behalf should be a decision. Blizzard throttles
             `/who` and a realm's population is a lot of queries. ]]--
        scan = false,

        --[[ On. Anybody unknown who speaks is asked about, which is exactly the
             people in front of you -- and one query answers one of them. ]]--
        scanNames = true,

        --[[ ChatScan verbosity. Off keeps a sweep quiet apart from its explicit
             start/stop/finish line; on also shows database additions, per-query
             progress, overflow notices and throttle/backoff updates. ]]--
        announceScan = false,

    },

    options = {
        { "Chat Scan", "__s_scan", "section", "scan" },

        --[[ **The sweep, as a button rather than a switch**, because it is a
             thing you start rather than a state you are in -- and because the
             button is the only place its progress can be shown. ]]--
        { "Begin Chat Scan", "__a_scan", "action",
          function()
              local m = OB.modules.roster

              --[[ Whether a *sweep* is running, not whether anything is queued:
                   between the last query going out and its answer coming back
                   the queue is empty, and a button reading Begin there would
                   start a second sweep instead of stopping the first. ]]--
              m:SetScanning(not m:Sweeping())
          end,
          function()
              local m = OB.modules.roster
              local progress = m:ScanProgress()

              if progress then return "Stop (" .. progress .. ")" end
              return "Begin Chat Scan"
          end },

        --[[ **Any unknown player who says anything gets asked about.**

             The high-value half by a distance: it is exactly the people in
             front of you, and one query answers one of them. Deduplicated, or
             a busy channel would queue the same handful forever. ]]--
        { "Automatically Scan Unknown Players", "scanNames", "boolean" },

        --[[ Off keeps the running scan quiet; on shows the individual additions
             and progress/status lines while it works. ]]--
        { "Show Database Additions In Chat", "announceScan", "boolean" },

        --[[ The store grows quietly and nothing else on this page says how big
             it is. The report is how somebody finds out what is in there, and
             resetting is the only way back out. ]]--
        { "What Is Known", "__a_report", "action",
          function() OB.PrintRosterReport() end,
          function()
              local n = 0
              for _ in pairs(OB.roster) do n = n + 1 end
              if n == 0 then return "Nobody Known Yet" end
              return "Send Known Player Report"
          end },

        { "Reset Database", "__a_forget", "action",
          function() OB.ForgetRoster() end },
    },

    --[[ The first six are the client saying "here is a list of people". The
         target is the odd one out and is worth keeping in the list rather than
         special-casing: one person is still a list.

         **The chat events are the rework of Automatically Scan Unknown
         Players.** It used to hang off name decoration -- the roster only heard
         about a speaker if the chat module happened to be drawing their name --
         so turning player colouring off silently turned the lookups off too, and
         a whisper from somebody unknown was never asked about at all because
         whispers are not decorated the same way.

         Listening for the messages themselves is what the setting has always
         claimed to do. `arg2` is the sender on every one of them. ]]--
    events = {
        "FRIENDLIST_UPDATE",
        "GUILD_ROSTER_UPDATE",
        "RAID_ROSTER_UPDATE",
        "PARTY_MEMBERS_CHANGED",
        "PLAYER_TARGET_CHANGED",
        "WHO_LIST_UPDATE",

        --[[ A `/who` somebody typed prints to chat and fires nothing else.
             See `LearnWhoLine`. ]]--
        "CHAT_MSG_SYSTEM",

        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_EMOTE",
        "CHAT_MSG_CHANNEL",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_RAID_WARNING",
    },

    requires = { "SendWho", "SetWhoToUI" },
})

function M:Config()
    return OB.profile.modules.roster
end

-- ---------------------------------------------------------------------------
-- what is known
-- ---------------------------------------------------------------------------

--[[ Raid groups, beside the roster rather than in it: a group number is true for
     one raid and misleading the moment you leave it, so it is not something to
     remember between sessions. ]]--
OB.subgroups = {}

--[==[ **How long a level stays believed against a lower answer.**

     The thing the ratchet below exists to stop is the server's own `/who`
     cache: ask twice in quick succession and the second answer can be older
     than the first. That echo comes back within one query round trip, so a
     minute is a long time next to it -- and no time at all next to a sweep,
     which takes twenty. ]==]
local LEVEL_TRUST = 60

--[==[ **When each level in the database was last written, this session only.**

     Deliberately not saved. A timestamp per player would roughly double the
     size of a swept realm's roster on disk to answer a question that only
     matters while the client is running -- and the answer it needs on a fresh
     login is "not yet", which an empty table gives for free.

     Keyed by name beside the roster rather than stored in it, for the same
     reason `OB.subgroups` is: it is true for this session and misleading the
     moment the session ends. ]==]
local levelSeen = {}

function M:Learn(name, class, level, subgroup, guild)
    if not name or name == "" then return end

    local known = OB.roster[name]
    local isNew = not known

    if not known then
        known = {}
        OB.roster[name] = known
    end

    --[[ **Both halves of the class, because they are used for different things.**

         The rosters answer a localized name -- "Warrior", not "WARRIOR" -- and a
         colour lookup keyed by token comes back white for every one of them,
         silently. So the token is derived and stored for colouring, and the
         spelling as given is kept beside it, because that is what a `/who`
         query has to be written with. ]]--
    if class and class ~= "" then
        known.className = class
        known.class = OB.ClassToken(class) or known.class
    end

    --[==[ **A level goes up on its own. It comes down when the answer is
         newer than the one already stored.**

         The rule here was "levels only ever go up", and the reasoning was sound
         as far as it went: `/who` answers from a cache the server does not
         always refresh, so a level 48 arriving seconds after a level 52 is the
         past catching up rather than somebody losing a level. Prat had this.

         What it missed is that this database outlives the session. A number
         that got in too high could never be corrected -- not by a `/who`, not
         by a sweep, not by standing next to the person. Reported as exactly
         that: a player scanned once, scanned again, and the level never moves.

         Plenty of things can put a wrong number in. A name freed by a deleted
         character and taken by a new one. A roster read while the client was
         still filling it in. A realm swept a month ago. A permanent ratchet
         turns any of those into a permanent wrong answer -- which is worse than
         the stale answer it was guarding against, because the stale one fixes
         itself on the next query and this one never does.

         So the guard keeps its job and loses its permanence. An answer arriving
         while the stored one is still warm cannot lower it; an answer arriving
         after that is simply the newer fact. The first answer of a session is
         always newer, because whatever is on disk was learned before it.

         Without a clock this falls back to the old rule rather than to
         overwriting: something that cannot tell when it learned a fact should
         not be given permission to forget it. ]==]
    if level and level > 0 then
        local now = (type(time) == "function" and time()) or 0
        local at = levelSeen[name]

        local newer = (at == nil) or (now > 0 and (now - at) >= LEVEL_TRUST)

        if not known.level or level > known.level or newer then
            known.level = level
            levelSeen[name] = now
        end
    end

    --[==[ **The guild kept, because it was already being answered and thrown
         away.**

         `GetWhoInfo` has returned it second since the beginning and the guild
         roster knows it by definition. The only reason a nameplate could not
         show a guild was that nobody wrote the answer down.

         An empty string is cleared rather than ignored. That is the client
         saying "none", and reading it as "no news" would leave somebody who had
         just left a guild still wearing it for the rest of the session. ]==]
    if guild ~= nil then
        if guild == "" then known.guild = nil else known.guild = guild end
    end

    if subgroup then OB.subgroups[name] = subgroup end

    --[[ Answered, so the queue can stop asking. Harmless when nothing asked. ]]--
    if self.wanted then self.wanted[name] = nil end

    if isNew then self.added = (self.added or 0) + 1 end

    self:Announce(name, known, isNew)
end

--[[ **Somebody new, said out loud.**

     A three-hour sweep with no visible output is a three-hour sweep nobody
     believes is running, and the only other evidence is a counter on a button
     you have to go and look at.

     **Off, because it is a lot of chat.** A guild roster hands over forty names
     the moment you log in, and a swept realm is thousands -- so it is a switch
     for somebody who wants to watch it work rather than the default.

     **Only the first time.** Somebody whose level went up is not new: the line
     means "here is one more", and re-announcing would make it unreadable. ]]--
--[[ `|cff` wants six hex digits and the colours are three floats. The same two
     lines exist in chatbehaviour for the same reason; there is nothing to share
     except the multiplication. ]]--
local function hex(r, g, b)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

--[[ **`40:Bobby`, in two colours that answer two different questions.**

     The level takes the client's difficulty colours -- red is above you, grey is
     beneath -- so the eye reads where they are relative to you without doing the
     subtraction. The name takes the class colour, which is who they are. Between
     them the line says everything the database just learned, in the shape it is
     stored in.

     Both fall back to plain rather than to a guess: a `/who` answer without a
     level is rare and a name with no class is exactly what the sweep is for. ]]--
local function stamp(name, known)
    local out = ""

    if known.level and known.level > 0 then
        out = "|cff" .. hex(OB.LevelColor(known.level)) .. known.level .. "|r:"
    end

    if known.class then
        return out .. "|cff" .. hex(OB.ClassColor(known.class)) .. name .. "|r"
    end

    return out .. name
end

function M:Announce(name, known, isNew)
    if not isNew or not self:Config().announceScan then return false end

    Say("Player added to database: " .. stamp(name, known))

    return true
end

--[[ **Six readers, six argument orders, written out separately.**

     `GetFriendInfo` answers name, level, class. `GetGuildRosterInfo` answers
     name, rank, rankIndex, level, class. `GetRaidRosterInfo` puts the subgroup
     third. `GetWhoInfo` puts the guild second. Getting one wrong stores a rank
     string where a class belongs, and the only symptom is a name that never
     gets coloured -- which is also what an unknown player looks like.

     The duplication is the point: there is nothing shared to factor out here
     except the mistake. ]]--
function M:LearnFriends()
    for i = 1, GetNumFriends() do
        local name, level, class = GetFriendInfo(i)
        self:Learn(name, class, level)
    end
end

function M:LearnGuild()
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, class = GetGuildRosterInfo(i)

        -- Everybody in this list is in this guild -- that is what makes it this
        -- list -- so the row does not repeat the guild's name and the player's
        -- own guild is the right answer for all of them.
        self:Learn(name, class, level, nil, GetGuildInfo("player"))
    end
end

--[[ Rebuilt rather than added to, because a raid you have left should not leave
     everybody wearing the group number they had in it. ]]--
function M:LearnRaid()
    OB.subgroups = {}

    for i = 1, GetNumRaidMembers() do
        local name, _, subgroup, level, class = GetRaidRosterInfo(i)
        self:Learn(name, class, level, subgroup)
    end
end

function M:LearnParty()
    for i = 1, GetNumPartyMembers() do
        local unit = "party" .. i
        local class = UnitClass(unit)
        self:Learn(UnitName(unit), class, UnitLevel(unit))
    end
end

--[[ Friendly players only. A hostile target's class is knowable, but its name on
     another realm is not the name that will ever appear in your chat. Prat's
     gate, kept. ]]--
function M:LearnTarget()
    if not UnitIsPlayer("target") then return end
    if not UnitIsFriend("player", "target") then return end

    local class = UnitClass("target")
    self:Learn(UnitName("target"), class, UnitLevel("target"))
end

--[==[ **A `/who` you typed yourself, which the structured reader never sees.**

     `LearnWho` below reads `GetWhoInfo`, and that is empty unless the answer
     was routed to the UI. A `/who` typed by hand is not: it goes to the chat
     frame as printed text, `WHO_LIST_UPDATE` does not fire, and the note at the
     top of `NoWhoWindow` says so in as many words. The consequence went
     unnoticed because the comment on `LearnWho` claims the opposite -- "a
     `/who` result is a `/who` result, whether you typed it or the queue did" --
     and that is true of the two callers it knew about and false of this one.

     Reported as a level that would not update: somebody seen at 47, looked up
     by hand, shown as 60 in the chat frame, and still 47 in every prefix
     afterwards.

     **The pattern is built from the client's own format string** rather than
     written out here, which is what makes this safe to do at all. The
     objection to parsing chat was that it means reading sentences in whatever
     language the client is running in -- and it would, if the sentence were
     spelled here. `WHO_LIST_FORMAT` *is* that sentence, in that language, as
     the client itself assembled it, so turning it into a pattern is reading
     the client's answer rather than guessing at it.

     **Only the name and the level.** The format runs `Level %d %s %s`, race
     then class, and a race can be two words -- High Elf, Night Elf. Lazy
     captures would hand back a race of "High" and a class of "Elf Warrior",
     which is worse than no class at all because it would be stored. The level
     is the thing that was wrong and the level is what this takes. ]==]
local whoLinePatterns

local function buildWhoPatterns()
    if whoLinePatterns then return whoLinePatterns end

    whoLinePatterns = {}

    for _, name in ipairs({ "WHO_LIST_GUILD_FORMAT", "WHO_LIST_FORMAT" }) do
        local format = getglobal(name)

        if type(format) == "string" then
            --[[ Everything up to and including the level, and nothing after
                 it: the tail is where the ambiguity lives. ]]--
            local cut = string.find(format, "%%d")

            if cut then
                local head = string.sub(format, 1, cut + 1)

                local pattern = string.gsub(head,
                        "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
                pattern = string.gsub(pattern, "%%d", "(%%d+)")
                pattern = string.gsub(pattern, "%%s", "(.-)")

                table.insert(whoLinePatterns, "^" .. pattern)
            end
        end
    end

    return whoLinePatterns
end

function M:LearnWhoLine(line)
    if type(line) ~= "string" or line == "" then return false end

    local patterns = buildWhoPatterns()

    for i = 1, table.getn(patterns) do
        local _, _, name, shown, level = string.find(line, patterns[i])

        --[[ The format names the player twice -- once inside the link and once
             as the text of it. The link half is the one without colour codes
             or brackets, so it is the one worth keeping. ]]--
        name = name or shown
        level = tonumber(level)

        if name and name ~= "" and level and level > 0 then
            self:Learn(name, nil, level)
            return true
        end
    end

    return false
end

--[[ The structured reader, for answers routed to the UI. A `/who` typed by
     hand does not come this way at all -- it prints to chat and is picked up by
     `LearnWhoLine`. This used to claim it did not care which of the two asked,
     which was the reason nobody noticed that one of them was never read. ]]--
function M:LearnWho()
    --[[ GetNumWhoResults returns both the number of rows the client received and
         the total number of players that matched the query. The first number is
         capped by the Who result list; the second is what tells us whether a
         class split is actually necessary. ]]--
    local count, totalCount = GetNumWhoResults()

    for i = 1, count do
        local name, guild, level, _, class = GetWhoInfo(i)
        self:Learn(name, class, level, nil, guild)
    end

    return count, totalCount or count
end

-- ---------------------------------------------------------------------------
-- asking
-- ---------------------------------------------------------------------------

--[[ **Somebody wants to know about this player.**

     Called from wherever a name is drawn -- chat today, nameplates later. It
     records the wish and returns; it never queries, because the thing calling it
     is in the middle of drawing a line and the queue runs on its own clock.

     Defined at file scope rather than as a method, so the caller does not have
     to know whether this module is loaded or switched on. A name wanted while
     the roster is off is simply dropped, which is the correct amount of
     ceremony for a colour. ]]--
function OB.WantPlayer(name)
    local m = OB.modules.roster
    if not m or not OB.ModuleEnabled("roster") then return end

    if not name or name == "" then return end
    if OB.roster[name] and OB.roster[name].class then return end

    local cfg = m:Config()
    if not cfg.scanNames then return end

    --[[ **Not while a sweep is running.** They spend the same queries out of
         the same throttle, and there is one result list between them -- so on a
         realm where General never stops, every lookup is a level the sweep
         never gets to ask about.

         Refused here rather than by unticking the box, which was a lie about
         who had decided what: the answer is still yes, it is just not in charge
         for the next twenty minutes. The row is greyed to say so. ]]--
    if m:Sweeping() then return end

    m.wanted = m.wanted or {}

    --[[ Already queued, or already asked and not answered. Asking twice for the
         same name is the failure mode this whole table exists to prevent: a busy
         channel repeats the same handful of people constantly, and without this
         the queue would be that handful, over and over, forever. ]]--
    if m.wanted[name] then return end

    m.wanted[name] = true
    table.insert(m.queue, { kind = "name", query = name,
            label = "player: " .. name })
end

--[[ The census, queued as six bands. Splitting happens on the way back, when a
     band comes back full and so has not answered its own question. ]]--
function M:StartCensus()
    for i = 1, table.getn(BANDS) do
        table.insert(self.queue, {
            kind = "band",
            low = BANDS[i][1],
            high = BANDS[i][2],
            query = BANDS[i][1] .. "-" .. BANDS[i][2],
        })
    end
end

--[[ **A band that came back full gets cut up and asked again, next.**

     Forty-nine results does not mean forty-nine players; it means at least
     forty-nine, and the rest are not coming. So the range is halved until either
     it fits under the cap or there is nothing left to halve.

     At one level and still full, the last cut available is by class -- and the
     class names have to be the client's own spelling, which is why `Learn` keeps
     it. Drawn from what has actually been seen rather than from a table: a
     hardcoded English list would send nine queries that match nothing on a
     German realm, and the guild roster hands over real spellings within seconds
     of logging in.

     **At the front of the queue, in order.** They used to go on the end, which
     put level 60's nine class queries after everything -- so a sweep that hit an
     overflow anywhere finished the levels and then ran a tail of class queries
     that, with the report naming no levels, was indistinguishable from a sweep
     going round in circles. Splitting a level is finishing that level, not
     adding work for later, and a sweep should be describable as "it is on level
     twelve" at every moment.

     Returns how many it queued, so the answer can say so once.

     Knowing no class names yet is not a failure. It means this level keeps the
     forty-nine it got, which is forty-nine more than it had. ]]--
function M:Split(band)
    if band.low < band.high then
        local middle = math.floor((band.low + band.high) / 2)

        --[[ Second half first, because each goes in at position one. ]]--
        table.insert(self.queue, 1, { kind = "band",
                low = middle + 1, high = band.high,
                query = (middle + 1) .. "-" .. band.high,
                label = "levels " .. (middle + 1) .. "-" .. band.high })
        table.insert(self.queue, 1, { kind = "band",
                low = band.low, high = middle,
                query = band.low .. "-" .. middle,
                label = "levels " .. band.low .. "-" .. middle })

        return 2
    end

    --[[ One level, already split as far as levels go. A class query that comes
         back full is simply full: there is nothing left to cut it by, and this
         is what stops the splitting rather than any depth count. ]]--
    if band.byClass then return 0 end

    local names = self:ScanClasses()

    for i = table.getn(names), 1, -1 do
        table.insert(self.queue, 1, {
            kind = "band",
            low = band.low,
            high = band.high,
            byClass = true,
            query = band.low .. ' c-"' .. names[i] .. '"',
            label = "level " .. band.low .. " " .. names[i] .. "s",
        })
    end

    return table.getn(names)
end

--[[ **The full sweep: every level, one query each, class only where it spills.**

     `/who` answers at most fifty and the server throttles how often it will
     answer at all, and those two facts together decide the whole shape of this.
     Fifty is a cap and not a count: a level that comes back full is a level
     whose remainder is simply not coming, so its answer is partly a lie.

     So the sweep asks sixty questions -- level 1, level 2, on up -- and only a
     level that answers with the cap is asked again, once per class. One level
     and one class cannot overflow on any realm anybody plays on, which is where
     the splitting stops. On most of the range it never starts.

     Sixty queries at twenty seconds is twenty minutes, plus nine more queries
     for each level that spills -- in practice sixty, and wherever the levelling
     crowd happens to be this month.

     **Level ascending.** Somebody watching sees the low levels fill in first,
     which is the order a realm's population is least interesting in -- but it
     is also the order that makes "it is on level eleven" a sentence, and a
     sweep whose progress nobody can describe is a sweep nobody trusts. ]]--
local MAX_LEVEL = 60

--[[ The nine, in English, as a floor rather than as the answer.

     `ClassNames` prefers what the roster has actually *seen*, which is the
     client's own spelling and therefore right on any locale -- but a fresh
     character has seen none, and a level-60 overflow on a new install would
     split into nothing at all. These are what a split falls back to, and the
     seen spellings replace them as they arrive. ]]--
local ENGLISH_CLASSES = {
    "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
    "Shaman", "Mage", "Warlock", "Druid",
}

function M:ScanClasses()
    local seen = self:ClassNames()
    if table.getn(seen) >= 9 then return seen end

    --[[ Union rather than either: a partly-learned realm has some real
         spellings and some guesses, and the guesses cost one wasted query each
         while the real ones cost nothing. ]]--
    local have, out = {}, {}

    for i = 1, table.getn(seen) do
        have[string.lower(seen[i])] = true
        table.insert(out, seen[i])
    end

    for i = 1, table.getn(ENGLISH_CLASSES) do
        if not have[string.lower(ENGLISH_CLASSES[i])] then
            table.insert(out, ENGLISH_CLASSES[i])
        end
    end

    return out
end

--[[ Every query the chosen shape asks for, queued. Replaces whatever was queued
     before, because starting a sweep is saying "do this now" rather than "and
     also this". ]]--
function M:StartFullScan()
    self.queue = {}
    self.scanTotal = 0

    --[[ A fresh sweep asks at the rate that was asked for. What the server
         taught the last one was about the last one -- and if it still holds,
         the first drop teaches it again within a minute. ]]--
    self.backoff = 0

    self:QueueLevels()

    self.scanTotal = table.getn(self.queue)
    self.scanDone = 0
    self.sweepAdded = 0

    return self.scanTotal
end

--[[ A targeted census uses the same queue item and result path as the full
     sweep, but asks for only one level. Level 60 therefore keeps the normal
     overflow fallback to class queries, while levels 1-59 remain one query. ]]--
function M:StartLevelScan(level)
    self.queue = {}
    self.scanTotal = 0
    self.backoff = 0

    table.insert(self.queue, {
        kind = "band", low = level, high = level,
        query = tostring(level),
        label = "level " .. level .. " players",
    })

    self.scanTotal = 1
    self.scanDone = 0
    self.sweepAdded = 0

    return self.scanTotal
end


--[[ **A range of levels, one query per level.**

     `/who 50-60` is a single query and answers at most fifty players, which on
     any realm with people on it is an overflow -- the eleven levels come back as
     whichever fifty the server felt like. One query per level is eleven queries
     that each answer completely.

     The sweep's own splitting handles the rest: a level that still overflows
     gets cut by class exactly as it does in a full scan, because these are the
     same band entries the full sweep queues. ]]--
function M:StartRangeScan(low, high)
    low, high = tonumber(low), tonumber(high)
    if not low or not high then return 0 end

    --[[ Written either way round, because somebody typing a range has no reason
         to know which end this expects. ]]--
    if low > high then low, high = high, low end

    if low < 1 then low = 1 end
    if high > MAX_LEVEL then high = MAX_LEVEL end
    if low > high then return 0 end

    self.queue = {}
    self.scanTotal = 0
    self.backoff = 0

    for level = low, high do
        table.insert(self.queue, {
            kind = "band", low = level, high = level,
            query = tostring(level),
            label = "level " .. level .. " players",
        })
    end

    self.scanTotal = table.getn(self.queue)
    self.scanDone = 0
    self.sweepAdded = 0

    return self.scanTotal
end

--[[ **One class, every level, in bands of ten.**

     `/who c-"Mage"` on its own is one query and every mage on the realm, which
     is an overflow on the first attempt. Bands of ten are what fit: a band that
     still comes back full is split by the sweep's own rule, down to single
     levels, and a single level of one class is as narrow as `/who` goes.

     Six queries rather than sixty, which is the point -- somebody asking about
     one class is asking a narrower question than the full sweep and should wait
     a tenth as long for it. ]]--
local CLASS_BAND = 10

function M:StartClassScan(class)
    if type(class) ~= "string" or class == "" then return 0 end

    self.queue = {}
    self.scanTotal = 0
    self.backoff = 0

    local low = 1
    while low <= MAX_LEVEL do
        local high = low + CLASS_BAND - 1
        if high > MAX_LEVEL then high = MAX_LEVEL end

        table.insert(self.queue, {
            kind = "band",
            low = low, high = high,

            --[[ `byClass` is deliberately *not* set. It marks a band that has
                 already been cut by class and therefore cannot be cut again --
                 and these have not been cut, they were asked that way. Setting
                 it would stop a band of ten mages splitting into single levels
                 when it overflows, which is exactly when it needs to. ]]--
            query = low .. "-" .. high .. ' c-"' .. class .. '"',
            label = "levels " .. low .. "-" .. high .. " " .. class .. "s",
        })

        low = high + 1
    end

    self.scanTotal = table.getn(self.queue)
    self.scanDone = 0
    self.sweepAdded = 0

    return self.scanTotal
end

--[[ The class this addon knows by that name, whatever case it was typed in.

     Matched against what the roster has actually seen rather than a list of
     nine, because the server's own spelling is the one `/who` wants back -- and
     on a realm this addon has never swept there is nothing to match, which is
     an honest "no" rather than a query that returns nothing. ]]--
function M:ClassNamed(text)
    if type(text) ~= "string" or text == "" then return nil end

    local wanted = string.lower(text)

    local names = self:ClassNames()
    for i = 1, table.getn(names) do
        if string.lower(names[i]) == wanted then return names[i] end
    end

    --[[ **Falls back to the nine this addon knows**, so a fresh install can ask
         about a class nobody has been seen playing yet -- which is every class,
         on a realm that has never been swept.

         `OB.ClassToken` is the same name-to-token map the colours use, and it
         is honest about locale: on a client this addon has no table for it
         answers nil, and the command says it does not know that class rather
         than sending `/who c-"Магистр"` and getting nothing back. ]]--
    if OB.ClassToken then
        local token = OB.ClassToken(text)

        if token and OB.classColors and OB.classColors[token] then
            --[[ Title case, which is the spelling `/who` wants: the server
                 answers "Mage" and matches on it, where "MAGE" matches
                 nothing. ]]--
            return string.upper(string.sub(token, 1, 1))
                    .. string.lower(string.sub(token, 2))
        end
    end

    return nil
end
--[[ **Sixty queries, one level at a time, and class only where it is needed.**

     There were three shapes on a dropdown -- level, level-and-class, and zone --
     and the choice was not one anybody could make, because two of the three are
     strictly worse. Level-and-class is five hundred and forty queries and three
     hours to avoid an overflow that happens at a handful of levels. Zone finds
     whoever is standing somewhere, which means it misses instances and anywhere
     this addon has not heard of, and it cannot be reconciled with the level
     sweep afterwards.

     So there is one shape. Sixty levels, each on its own. A level that answers
     with the cap has not answered -- fifty is a limit, not a count -- and that
     level alone is asked again once per class, which cannot overflow on any
     realm anybody plays on. See `Split`.

     In practice that is level 60 and, on a busy realm, wherever the levelling
     crowd happens to be. Everywhere else pays one query. ]]--
function M:QueueLevels()
    for level = 1, MAX_LEVEL do
        table.insert(self.queue, {
            kind = "band", low = level, high = level,
            query = tostring(level),
            label = "level " .. level .. " players",
        })
    end
end

--[[ Where the sweep has got to, as a sentence somebody can read on a button. ]]--
--[[ **Counted forwards, from what has been asked.**

     It used to be `total - remaining`, and remaining is not a countdown: a level
     that comes back full puts nine more queries on the queue, so the number went
     backwards -- 12 of 60, then 11 of 60 -- and between the last query going out
     and its answer coming back the queue was empty, which read as no sweep at
     all and turned the Stop button back into Begin.

     So the sweep counts what it has asked and grows its own total when it splits.
     Both only move forwards, and neither depends on the queue being non-empty at
     the moment somebody happens to look. ]]--
function M:ScanProgress()
    if not self:Sweeping() then return nil end

    return (self.scanDone or 0) .. " of " .. (self.scanTotal or 0)
end

--[[ **A full sweep is running**, as opposed to anything being queued at all.

     A name lookup puts an item on the same queue, so "is the queue busy" is true
     far more often than this is. Only a sweep sets `scanTotal`, and the sweep is
     what the button stops, what the progress counts, and what holds the
     automatic lookups back -- which is why this is the question every caller
     turned out to want. ]]--
function M:Sweeping()
    return self.scanTotal ~= nil
end

--[[ **The two halves share one throttle, so the sweep takes it -- without
     touching the setting.**

     Automatically Scan Unknown Players and the sweep both spend `/who` queries
     out of the same allowance, and there is only one result list, so every
     lookup a busy channel triggers is a level the sweep does not get to ask
     about. On a realm where General never stops that is most of them.

     An earlier version unticked the box and put it back afterwards, which was a
     lie about who had decided what: the reader's answer is still yes, it is just
     not in charge for the next twenty minutes. So the setting is left alone, the
     row is greyed while a sweep runs -- see `RowGreyed` -- and the lookups
     simply do not happen. Nothing to remember and nothing to restore.

     What is remembered is whether the line was said, so the one announcing it is
     back is not printed to somebody who never had them on. ]]--
function M:HoldAutoScan()
    if not self:Config().scanNames then return false end

    self.autoHeld = true

    if self:Config().announceScan then
        Say("Automatic lookup turned off while scan is running.")
    end

    if type(OB.RefreshPanel) == "function" then OB.RefreshPanel() end

    return true
end

function M:ReleaseAutoScan()
    if not self.autoHeld then return false end

    self.autoHeld = nil

    if self:Config().announceScan then
        Say("Automatic scan re-enabled.")
    end

    if type(OB.RefreshPanel) == "function" then OB.RefreshPanel() end

    return true
end

--[[ **Greyed rather than unticked while a sweep runs.**

     The row still means something -- it is what happens once the sweep is done
     -- and it is not in charge right now, which is exactly the distinction
     `greyWhen` exists for. `greyWhen` itself cannot express this, because it
     reads config keys and "a sweep is running" is not one; so the panel asks the
     module, which is the same thing it already does for a module that is not
     written yet. ]]--
function M:RowGreyed(w)
    return w.key == "scanNames" and self:Sweeping()
end

--[[ On, or off and forgotten.

     Stopping empties the queue rather than pausing it, because a sweep is
     resumable in the only sense that matters: what it has already learned is
     kept, and starting again re-queues from the bottom and re-asks a few
     hundred questions whose answers are already known. That costs time and
     nothing else. ]]--
function M:SetScanning(on, level)
    if not on then
        local added = self.sweepAdded or 0

        self.queue = {}
        self.scanTotal = nil
        self.sweepAdded = nil

        Say("Scan stopped... " .. added .. " entries were added to database.")

        self:ReleaseAutoScan()

        return false
    end

    local cfg = self:Config()

    --[[ The sweep is the reason to be asking the server at all, so turning it on
         turns querying on rather than complaining that it is off. ]]--
    cfg.scan = true

    if level then
        self:StartLevelScan(level)
        Say("Scan started for level " .. level .. "...")
    else
        self:StartFullScan()
        Say("Scan started...")
    end

    self:HoldAutoScan()

    return true
end

--[[ **Everything `SetScanning` does around building a queue, for the callers
     that build their own.**

     A range and a class scan queue themselves -- they are not one level and not
     the full sixty -- but the bookkeeping either side is identical: querying has
     to be switched on, the automatic scan has to stand aside, and somebody has
     to be told it started. Factored out rather than repeated three times,
     because three copies of "and also turn querying on" is two chances to
     forget it. ]]--
function M:BeginQueuedScan(what)
    if not self.queue or table.getn(self.queue) == 0 then return false end

    self:Config().scan = true

    Say("Scan started for " .. (what or "players") .. "...")
    self:HoldAutoScan()

    return true
end


--[[ **Every class spelling the roster has actually seen, deduplicated without
     regard to case.**

     Case matters here because these become `/who c-"..."` queries and a
     duplicate is a wasted one. `UnitClass` hands back the localized name first
     and the uppercase token second, and this module used to take the second --
     so the player's own class arrived as "MAGE" while everybody else's arrived
     as "Mage", and a level that overflowed was asked about ten times instead of
     nine, twice for the same class.

     The spelling kept is the first one seen, which on any realm with other
     players on it is the server's own. ]]--
function M:ClassNames()
    local seen, out = {}, {}

    for _, known in pairs(OB.roster) do
        if known.className then
            local key = string.lower(known.className)

            if not seen[key] then
                seen[key] = true
                table.insert(out, known.className)
            end
        end
    end

    return out
end

--[[ **Whether now is a reasonable moment to ask the server something.**

     Four reasons not to, and all four are about being a good neighbour rather
     than about correctness -- the query would work, it just should not happen.

     The Friends frame one is the important one: sending a query redirects `/who`
     results away from the interface for as long as it takes to answer, so
     scanning while somebody is reading the Who list empties the list they are
     reading. ]]--
function M:MayAsk()
    local cfg = self:Config()

    --[[ Either half being wanted is permission to ask. `scan` is set by the
         sweep button; `scanNames` is a switch of its own. Neither is a row
         called "may this addon use /who", because that question is answered by
         asking for one of the two things it is for. ]]--
    if not (cfg.scan or cfg.scanNames) then return false end
    if OB.inCombat then return false end
    if self.pending then return false end

    if FriendsFrame and FriendsFrame:IsVisible() then return false end

    return true
end
--[[ **The Who window is stopped from opening, rather than closed afterwards.**

     Closing it afterwards was two panel sounds and a flicker every twenty
     seconds, which is the sort of thing that is fine for a minute and unbearable
     for an hour.

     The chat route is not available, tempting as it looks. `SetWhoToUI(0)` sends
     the answer to the chat frame as printed text, and printed text is all it is
     -- `GetWhoInfo` stays empty and `WHO_LIST_UPDATE` does not fire, so the only
     way back to names, levels and classes would be parsing sentences in whatever
     language the client is running in. The structured answer exists only in UI
     mode.

     So the answer still goes to the UI and the UI is simply not opened.
     `ShowUIPanel` is intercepted for the second or so a query of ours is
     outstanding, and only for this one frame: everything else still opens
     normally, and a `/who` somebody typed themselves is not affected because
     `MayAsk` refuses while the Friends frame is up.

     Swallowed rather than deferred. A panel nobody asked for is not owed a
     showing later. ]]--
function M:MutePanel()
    if self.showPanel then return false end
    if type(ShowUIPanel) ~= "function" then return false end

    local mine = OB.modules.roster

    --[[ **The wrapper holds the original itself rather than reading it back off
         the module.**

         It used to call `mine.showPanel(...)`, and `UnmutePanel` clears that
         field -- while deliberately leaving the wrapper installed if somebody
         else has wrapped over the top of it since, because deleting another
         addon's hook is worse than leaving one of ours behind.

         Those two are the bug. DragonflightUI wraps `ShowUIPanel` as well, so
         after a sweep ended, ECO's wrapper was still in the chain with nothing
         behind it: the next thing to open a panel -- the bank -- called through
         it and hit `attempt to call field 'showPanel' (a nil value)`.

         An upvalue cannot be cleared from outside, so the wrapper can always
         reach the function it wrapped. Whether it *suppresses* is a separate
         question, and that is what the flag below answers -- so an orphaned
         wrapper quietly becomes a pass-through instead of a crash. ]]--
    local original = ShowUIPanel

    self.showPanel = original
    self.panelMuted = true

    ShowUIPanel = function(frame, force)
        if mine.panelMuted and frame and frame == FriendsFrame then return end
        return original(frame, force)
    end

    self.showMine = ShowUIPanel

    return true
end

--[[ Put back only if it is still ours. An addon that wrapped `ShowUIPanel` in
     the second we were holding it deserves to keep its wrapper -- restoring over
     the top would delete somebody else's hook, which is worse than leaving one
     of ours in place. ]]--
function M:UnmutePanel()
    if not self.showPanel then return false end

    --[[ Muting stops first and unconditionally. Whether the wrapper can be
         taken back out is a second question -- and if it cannot, this is what
         makes the one left behind harmless. ]]--
    self.panelMuted = nil

    if ShowUIPanel == self.showMine then ShowUIPanel = self.showPanel end

    self.showPanel = nil
    self.showMine = nil

    return true
end


--[[ One query, and then wait for it.

     `SetWhoToUI(1)` sends the answer to the interface instead of printing it in
     chat -- without it, a scan pours its results into the chat frame, which is
     the opposite of the point. It goes back to 0 the moment the answer arrives,
     because it is a global switch and leaving it flipped means the next `/who`
     somebody types answers into a frame they are not looking at.

     **When it was asked is kept too.** See OnUpdate: a query that is never
     answered would otherwise stop the sweep for the rest of the session. ]]--
function M:Ask(item, now)
    self.pending = item
    self.pendingAt = now or GetTime()

    --[[ Counted here rather than off the queue: see ScanProgress. Splits and
         name lookups both change the queue length and neither is progress. ]]--
    if self:Sweeping() and item.kind == "band" then
        self.scanDone = (self.scanDone or 0) + 1
    end

    SetWhoToUI(1)
    self:MutePanel()
    SendWho(item.query)
end

--[[ **The gap is the `/who` cooldown, and the server is the one who knows it.**

     There was a Seconds Between Queries slider, and it was asking the reader for
     a number only the server has: too low and every other query is silently
     dropped, too high and a sweep that could have taken twenty minutes takes an
     hour. Neither end of it is knowable from where the player is sitting, and
     1.12 exposes no cooldown to read either.

     So it is found rather than set. Twenty seconds is where it starts -- what a
     busy realm turns out to allow -- and every dropped query widens it while
     every answer narrows it, so it settles on the real limit within a couple of
     minutes of the sweep starting and stays there. ]]--
local ASK_EVERY = 20
local BACKOFF_CAP = 60
local EASE = 1
local GIVE_UP = 2

function M:Wait()
    return ASK_EVERY + (self.backoff or 0)
end

--[[ **A query that is never answered must not stop the sweep.**

     `MayAsk` refuses while one is outstanding, because there is one result list
     and a second query overwrites the first. That is right, and on its own it is
     also a trap: the server drops a `/who` that arrives inside its throttle and
     sends nothing back at all, so `pending` stays set and the queue never moves
     again. One lost answer and the sweep is over for the session, silently.

     So an outstanding query is abandoned after twice the wait. Twice, rather
     than once, because the wait is the throttle and an answer arriving at the
     same moment as the next ask is normal.

     **And the query goes back on the queue, at the front, once.** It used to be
     discarded -- one missing level being a small loss next to a sweep that
     stops. That was true only while dropping was rare, and it was not rare, it
     was every other query. The backoff is what makes a retry worth queueing:
     the second ask happens at a gap the server has just demonstrated it
     wants. ]]--
function M:Dropped()
    local asked = self.pending
    local was = self.backoff or 0

    self.pending = nil
    self.pendingAt = nil

    --[[ Handed back, or the next `/who` anybody types answers into a frame
         they are not looking at. ]]--
    SetWhoToUI(0)
    self:UnmutePanel()

    self.backoff = math.min(was + ASK_EVERY, BACKOFF_CAP)

    if asked and not asked.retried then
        asked.retried = true
        table.insert(self.queue, 1, asked)
    end

    --[[ Once per widening rather than once per drop: the second is a line in
         chat every time the server sneezes. ]]--
    if self.backoff ~= was and self.scanTotal and self:Config().announceScan then
        Say("the server ignored a query. Asking every " .. self:Wait()
                .. "s from now on.")
    end

    --[[ Asked again at the next opportunity rather than after another full
         gap. Giving up already took twice the wait, which is more silence
         than the widened gap asks for -- waiting again would be counting the
         same seconds twice. ]]--
    self.nextAsk = nil

    return true
end

function M:OnUpdate(now)
    if self.pending and self.pendingAt
            and now - self.pendingAt > self:Wait() * GIVE_UP then
        self:Dropped()
    end

    if table.getn(self.queue) == 0 then return end
    if not self:MayAsk() then return end

    if self.nextAsk and now < self.nextAsk then return end
    self.nextAsk = now + self:Wait()

    self:Ask(table.remove(self.queue, 1), now)
end

--[[ **One line per query: what it was worth, and when the next one is.**

     A sweep is otherwise twenty seconds of nothing followed by twenty seconds
     of nothing, and the only sign of life is a counter on a button you have to
     go and look at. One line per query is the same rate as the queries
     themselves -- slow enough to read, often enough to believe.

     It used to name the query at both ends -- "scanned for level 3 players",
     "next scan in 17 seconds -- level 4 players" -- and with the sweep walking
     the levels in order that is the reader being told twice what they can
     already count. What is not knowable from the outside is the countdown,
     because the gap widens and narrows with what the server allows.

     Only for a sweep. A `/who` you typed yourself, and the lookups this module
     does on names as they speak, do not need narrating back at you. ]]--
function M:ReportQuery(asked)
    if not self.scanTotal then return false end
    if asked.kind ~= "band" or not asked.label then return false end

    --[[ Kept across the whole sweep as well as per query, so the line at the end
         can say what the twenty minutes were worth. ]]--
    self.sweepAdded = (self.sweepAdded or 0) + (self.added or 0)

    if not self.queue[1] then
        local added = self.sweepAdded

        self.scanTotal = nil
        self.sweepAdded = nil

        Say("Scan finished... " .. added .. " entries were added to database.")

        self:ReleaseAutoScan()

        return true
    end

    --[[ Read off `nextAsk` rather than off the gap, because the gap is what was
         asked for and `nextAsk` is what is happening -- the two differ by
         however much the server has widened it. ]]--
    local left = OB.Round((self.nextAsk or 0) - GetTime())
    if left < 0 then left = 0 end

    if self:Config().announceScan then
        Say(self.added .. " results added to database - next scan in "
                .. left .. " seconds")
    end

    --[[ The Stop button carries the count, and nothing else moves it: without
         this it reads whatever it read when the panel was last opened. Once per
         query is once per twenty seconds, which is not a cost. ]]--
    if type(OB.RefreshPanel) == "function" then OB.RefreshPanel() end

    return true
end

--[[ **The answer, whoever asked for it.**

     A `/who` result is learned from unconditionally: if the player typed the
     query themselves, the results are just as true, and throwing them away to
     preserve a tidy sense of ownership would be silly.

     Only the *bookkeeping* is conditional on the query having been ours. ]]--
function M:OnWhoResults()
    --[[ Counted across this answer only, so the report below can say what
         *this* query was worth rather than what the session has come to. ]]--
    self.added = 0

    local count, totalCount = self:LearnWho()
    local asked = self.pending

    if not asked then return end

    self.pending = nil
    self.pendingAt = nil
    SetWhoToUI(0)

    --[[ An answer is the server saying this rate is fine, so the gap eases back
         towards the setting -- a second at a time, so it comes to rest just
         above the real limit instead of snapping back to a rate that has
         already been refused once. ]]--
    if (self.backoff or 0) > 0 then
        self.backoff = math.max(0, self.backoff - EASE)
    end

    --[[ **Shut again if it got through anyway.**

         `MutePanel` stops the client opening it, which is where the noise was.
         This stays as the second line of defence: a client that shows the frame
         by some route other than `ShowUIPanel` would otherwise leave a window
         over the screen, and a sweep that does that every twenty seconds is
         worse than one panel sound.

         Only ours. A `/who` somebody typed is a window they opened on purpose,
         and this only runs when a query of ours was outstanding. ]]--
    self:UnmutePanel()

    if FriendsFrame and FriendsFrame:IsVisible() and type(HideUIPanel) == "function" then
        HideUIPanel(FriendsFrame)
    end

    --[[ **A full answer is not an answer.** See Split -- it puts the smaller
         queries at the front, so an overflowing level is finished before the
         sweep moves on.

         Said once, because it is the one moment the sweep stops being "one
         query per level" and the reader has no other way to tell: without it,
         nine more identical-looking lines look like a sweep going round in
         circles. Once per overflow, not once per query. ]]--
    --[[ Only split when the server says there were MORE than fifty matches.
         The visible result list may contain 49/50 rows even when that is the
         complete answer, and treating a full-looking page as overflow causes
         unnecessary class-by-class rescans. ]]--
    -- Only level 60 falls back to class-by-class queries. Levels 1-59 are
    -- deliberately one query each even when the server reports more matches
    -- than it can return in a single /who result page.
    if asked.kind == "band"
            and asked.low == MAX_LEVEL and asked.high == MAX_LEVEL
            and totalCount > WHO_SPLIT_THRESHOLD then
        local extra = self:Split(asked) or 0

        if extra > 0 then
            --[[ The sweep just got longer, and the counter has to say so or it
                 would pass its own total. ]]--
            if self:Sweeping() then
                self.scanTotal = (self.scanTotal or 0) + extra
            end

            if self:Config().announceScan then
                Say((asked.label or asked.query) .. " came back full -- asking it "
                        .. "again by class, " .. extra .. " more queries.")
            end
        end
    end

    --[[ **After the split**, so what it names as next is what is actually next:
         a band that came back full has just put its own halves at the front of
         the queue.

         A name query that came back empty has been answered: that player is not
         online, or not on this realm, and asking again in four seconds will
         learn the same nothing. `wanted` keeps the name marked so the queue does
         not pick it up again this session. ]]--
    self:ReportQuery(asked)
end

-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

local LEARNERS = {
    FRIENDLIST_UPDATE = "LearnFriends",
    GUILD_ROSTER_UPDATE = "LearnGuild",
    RAID_ROSTER_UPDATE = "LearnRaid",
    PARTY_MEMBERS_CHANGED = "LearnParty",
    PLAYER_TARGET_CHANGED = "LearnTarget",
}

function M:OnEvent()
    if event == "WHO_LIST_UPDATE" then
        self:OnWhoResults()
        return
    end

    --[[ Answered before the `CHAT_MSG_` sweep below, which this event's name
         would otherwise fall into -- `arg2` on a system message is not a
         player and asking about it would queue a query for nobody. ]]--
    if event == "CHAT_MSG_SYSTEM" then
        self:LearnWhoLine(arg1)
        return
    end

    --[[ Somebody spoke. `WantPlayer` decides whether they are worth a query:
         it drops anybody already known, anybody already queued, and everybody
         if the setting is off. ]]--
    if string.sub(event, 1, 9) == "CHAT_MSG_" then
        OB.WantPlayer(arg2)
        return
    end

    local learner = LEARNERS[event]
    if learner then self[learner](self) end
end

function M:OnBind()
    self.queue = self.queue or {}
    self.wanted = self.wanted or {}

    --[[ **Yourself first**, because you are the one player guaranteed present
         and otherwise the only uncoloured name on screen until somebody else
         speaks. ]]--
    local class = UnitClass("player")
    self:Learn(UnitName("player"), class, UnitLevel("player"))

    self:LearnParty()
    self:LearnRaid()
    self:LearnFriends()
    self:LearnGuild()

end
--[[ Turning querying off drops what is queued: a queue that kept draining after
     the switch went off would be a switch that does not work. Turning it on does
     not start a sweep -- that is the button's job, because a sweep is three
     hours and should be asked for rather than begun by a checkbox.

     **There is no longer anything to warn about here.** There was a dialog
     asking whether somebody really meant to turn lookups on mid-sweep, because
     doing so ate the sweep's queries. Now that the setting is left alone and
     simply not consulted while a sweep runs, turning it on during one changes
     nothing until the sweep is over -- so the question had no answer worth
     asking for, and the row is greyed rather than clickable in any case. ]]--
function M:AfterSet(key, value)
    if key ~= "scan" and key ~= "scanNames" then return end

    local cfg = self:Config()
    if cfg.scan or cfg.scanNames then return end

    self.queue = {}
    self.scanTotal = nil
    self.sweepAdded = nil

    --[[ The sweep is over, so the line saying lookups are back is due. ]]--
    self:ReleaseAutoScan()

    --[[ Handed back, or the next `/who` anybody types answers into a frame
         they are not looking at. ]]--
    if self.pending then
        self.pending = nil
        SetWhoToUI(0)
        self:UnmutePanel()
    end
end

function M:OnStyle() end
function M:OnDraw() end
