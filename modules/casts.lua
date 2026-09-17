--[[ Equadis' Classic Overhaul :: casts

  **Who is casting what, in a client that will not say.**

  1.12 has no `UnitCastingInfo` and no `UnitChannelInfo`. They arrive in 2.0. So
  every vanilla addon that draws a cast bar for anything other than the player
  has built this layer for itself, and ShaguPlates' `libcast` is the one this
  follows.

  Two halves, and they are not equally good.

  **The player's own casts are exact.** `SPELLCAST_START` hands over the spell
  name and the cast time in milliseconds, from the client, before anything is
  drawn. Nothing here is inferred.

  **Everything else is read out of the combat log**, which announces that a cast
  has begun and says nothing whatever about how long it will take. That number
  has to come from somewhere, and where it comes from is the one real design
  decision in this file.

  ShaguPlates ships a database: every spell in the game with its cast time,
  thousands of lines, one per locale. It works and it is a lot of data to carry
  and keep current.

  **This learns instead.** Every spell the player casts teaches the table its
  exact duration -- for free, from the client, with no guessing -- and mobs cast
  a great many of the same spells that players do. Fireball is Fireball. What is
  not known yet is drawn as a bar with no fill and the spell's name on it, which
  is still the useful half of a cast bar: *what* is being cast matters more than
  how far through it is.

  Keyed by unit **name**, not by unit token, which is what makes it work at all:
  a nameplate has a name and no token, so every plate can have a cast bar rather
  than only the target.
]]--

local OB = EquadisClassicOverhaul

-- ---------------------------------------------------------------------------
-- what is being cast
-- ---------------------------------------------------------------------------

--[[ In flight right now, keyed by caster name. Not saved: a cast lasts three
     seconds and nothing about it survives a reload worth keeping. ]]--
OB.casting = {}

--[[ **How long a spell takes**, learned rather than shipped. Saved, because a
     cast time is a fact about the world that does not change -- the same
     argument the roster and the price table are stored on. ]]--
function OB.CastTime(spell)
    if not spell then return nil end
    return OB.castTimes and OB.castTimes[spell]
end

function OB.LearnCastTime(spell, milliseconds)
    if not spell or not milliseconds or milliseconds <= 0 then return end
    if not OB.castTimes then return end

    --[[ **The longest seen wins**, which is the opposite of the levels rule and
         right for the opposite reason. A cast time shortens with haste and with
         talents and lengthens with nothing, so the largest number seen is the
         base -- and a bar drawn from a hasted duration finishes early on
         somebody who is not hasted, which reads as the spell being interrupted. ]]--
    local known = OB.castTimes[spell]
    if known and known >= milliseconds then return end

    OB.castTimes[spell] = milliseconds
end

--[[ Somebody has started casting.

     `duration` is given for the player, because the client provides it, and nil
     for everybody else, because the combat log does not. A nil duration is not a
     failure -- it is a bar that shows the spell's name and no progress, which is
     the honest drawing of "this is being cast and I do not know for how long". ]]--
function OB.StartCast(name, spell, duration, channel)
    if not name or not spell then return false end

    if duration then OB.LearnCastTime(spell, duration) end

    OB.casting[name] = {
        spell = spell,
        start = GetTime(),
        duration = duration or OB.CastTime(spell),
        channel = channel and true or nil,
    }

    return true
end

--[==[ **A cast can be filed under more than one key, and ending it ends all of
     them.**

     A cast learned from `UNIT_CASTEVENT` is filed under the caster's GUID, which
     is the only thing that tells two Defias Bandits apart -- and under the
     caster's name as well, because everything that reads this from before that
     event existed asks by name and should keep working.

     One record under two keys rather than two records: two would drift the
     moment one of them was stopped and the other was not, which is a bar that
     ends on one frame and not on another. ]==]
function OB.StopCast(key)
    if not key then return end

    local cast = OB.casting[key]

    if cast and cast.keys then
        for i = 1, table.getn(cast.keys) do
            if OB.casting[cast.keys[i]] == cast then OB.casting[cast.keys[i]] = nil end
        end
    end

    OB.casting[key] = nil
end

--[==[ **A cast whose caster is known exactly.**

     The GUID is the identity; the name is an alias so the name-based readers
     that predate this keep answering. `UnitName` on a GUID works because a GUID
     *is* a unit token on this client -- the same fact the nameplates use to
     resolve which mob a plate belongs to. ]==]
function OB.StartCastFor(guid, spell, duration, channel)
    if not guid or not spell then return false end
    if not OB.StartCast(guid, spell, duration, channel) then return false end

    local cast = OB.casting[guid]
    cast.keys = { guid }

    local name
    if type(UnitName) == "function" then
        local ok, resolved = pcall(UnitName, guid)
        if ok then name = resolved end
    end

    if name and name ~= "" and name ~= "Unknown" then
        OB.casting[name] = cast
        table.insert(cast.keys, name)
    end

    return true
end

--[[ **What to draw, or nothing.**

     Returns the spell, how far through it is as a fraction, and whether it is a
     channel. The fraction is nil when the duration is not known -- which the
     caller must handle rather than treat as zero, because a bar sitting at empty
     for three seconds looks like a bug and an unfilled bar with a name on it
     looks like what it is.

     **Expiry happens here rather than on a timer.** A cast that ran out is
     forgotten the next time anybody asks about it, which costs nothing and means
     there is no sweep to schedule and nothing to leak if a caster dies mid-cast
     and never sends another line. ]]--
function OB.CastInfo(name)
    if not name then return nil end

    local cast = OB.casting[name]
    if not cast then return nil end

    local elapsed = GetTime() - cast.start

    --[[ Unknown duration: kept for a few seconds and then dropped, because
         nothing will ever come along to end it. Five is longer than almost any
         vanilla cast and short enough not to linger. ]]--
    local limit = cast.duration and (cast.duration / 1000) or 5

    --[[ Through `StopCast` rather than by clearing the one key that was asked
         about, or a cast filed under a GUID *and* a name expires for whichever
         of the two happened to be read first and lingers under the other. ]]--
    if elapsed >= limit then
        OB.StopCast(name)
        return nil
    end

    if not cast.duration then
        return cast.spell, nil, cast.channel, nil
    end

    local fraction = elapsed / (cast.duration / 1000)

    --[[ A channel empties rather than fills. It is the same number read the
         other way round, and getting it backwards is the sort of thing nobody
         notices until they watch a Drain Life. ]]--
    if cast.channel then fraction = 1 - fraction end

    if fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end

    --[==[ **How long is left, which is the question the fraction cannot answer.**

         A bar three-quarters along says the same thing whether the last quarter
         is a tenth of a second or two seconds, and those are different
         decisions -- interrupt now, or step out of it. So the seconds are
         returned beside the fraction rather than derived from it by every
         caller, which would have each of them recomputing `cast.duration`.

         Fourth, so nothing that already asks for three values changes. ]==]
    local remaining = (cast.duration / 1000) - elapsed
    if remaining < 0 then remaining = 0 end

    return cast.spell, fraction, cast.channel, remaining
end

--[==[ **An icon for a spell name, which 1.12 does not hand over.**

     `SPELLCAST_START` gives a name and a duration and nothing else. Every addon
     that shows a cast icon therefore builds the name-to-picture map itself, and
     the usual way is to ship a table of every spell in the game -- which is a
     large file that is wrong the day a server adds something.

     Two sources are already here instead, and between them they cover most of
     what anybody looks at.

     **Your own spellbook is exact and free.** Everything you cast is in it, with
     its real icon, in the client's own locale. Built once and rebuilt when the
     book changes, because walking it on every cast is a loop over two hundred
     entries for a picture that has not moved.

     **The aura cache covers a good deal of the rest.** `OB.auraIcons` is filled
     as debuffs are seen on units, and a great many of the things worth watching
     a mob cast are things that then land as a debuff you have seen before.

     Anything else gets no icon, and the bar simply has none. A wrong icon is
     worse than no icon: it is a spell you would swear you recognised. ]==]
local spellIcons = nil

--[==[ **Which build of the map an answer came from.**

     A cast bar caches the icon it looked up, because the answer cannot change
     while one spell is being cast and the lookup walks a table. Keyed on the
     spell name alone, a *failed* lookup is cached just as firmly as a successful
     one -- and the map is empty until `SPELLS_CHANGED` arrives after login. Cast
     anything in that window and it has no icon for the rest of the session.

     So the generation goes up whenever the map is rebuilt, and a cache is only
     good for the generation it was taken in. ]==]
OB.spellIconGeneration = 0

function OB.RebuildSpellIcons()
    spellIcons = {}
    OB.spellIconGeneration = (OB.spellIconGeneration or 0) + 1

    if type(GetSpellName) ~= "function" then return spellIcons end
    if type(GetSpellTexture) ~= "function" then return spellIcons end

    --[==[ **Both books, not just your own.**

         A hunter's pet and a warlock's minion cast things constantly, and every
         one of those bars came up bare because the walk only ever read
         `BOOKTYPE_SPELL`. The pet book is the same two calls with a different
         argument, and it is the single largest set of spells this addon was
         choosing not to look at. ]==]
    local books = { BOOKTYPE_SPELL or "spell" }

    if BOOKTYPE_PET then table.insert(books, BOOKTYPE_PET) end

    for b = 1, table.getn(books) do
        local book = books[b]

        --[[ Walked until the book runs out rather than to a fixed count: the
             number of spells is a fact about the character, and a constant here
             would stop at whatever a level sixty rogue happened to have. ]]--
        local i = 1

        while true do
            local name = GetSpellName(i, book)
            if not name then break end

            local texture = GetSpellTexture(i, book)

            --[[ First one wins. A spell appears once per rank in this book and
                 the ranks share an icon, so the later ones have nothing to
                 add. ]]--
            if texture and not spellIcons[name] then spellIcons[name] = texture end

            i = i + 1

            --[[ A guard rather than a limit. Nothing has two thousand spells,
                 and a build whose `GetSpellName` never returns nil would
                 otherwise hang the client rather than draw a bar without an
                 icon. ]]--
            if i > 2000 then break end
        end
    end

    return spellIcons
end

--[==[ The client's own "no art for this", used where a spell cannot be
     recognised at all -- see `OB.SpellIcon`. Named once because two files draw
     it for the same reason. ]==]
UNKNOWN_SPELL_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

function OB.SpellIcon(name)
    if not name or name == "" then return nil end

    if not spellIcons then OB.RebuildSpellIcons() end

    local own = spellIcons[name]
    if own then return own end

    local seen = OB.auraIcons and OB.auraIcons[name]
    if seen then return seen end

    --[==[ **The question mark, rather than nothing.**

         This answered nil for a spell in neither book, on neither bar and never
         seen as an aura, and the cast bar hid its icon -- on the reasoning that
         no icon is better than somebody else's. That half is still right and
         this is not the other half: `INV_Misc_QuestionMark` is the client's own
         "there is no art for this", so it is not a spell anybody could mistake
         for another. It is the same placeholder the buff frames' preview uses
         and for the same reason.

         What it buys is a bar that is the same shape every time. An icon that
         appears and disappears depending on whether the caster happens to be in
         your spellbook makes the whole row jump, and a gap reads as a fault
         rather than as an absence. ]==]
    return UNKNOWN_SPELL_ICON
end

--[==[ **Seconds, rendered the way a cast bar reads them.**

     One decimal below ten, because the difference between 1.4 and 0.6 seconds
     is the whole of an interrupt decision and "1" for both throws it away.
     Whole numbers above ten, where a tenth of a second is noise on a number
     nobody is reacting to yet. ]==]
function OB.CastTimeText(seconds)
    if type(seconds) ~= "number" or seconds < 0 then return nil end

    if seconds < 10 then return string.format("%.1f", seconds) end
    return string.format("%d", math.floor(seconds + 0.5))
end

-- ---------------------------------------------------------------------------
-- watching for them
-- ---------------------------------------------------------------------------

--[[ **Not a module and not a tab.**

     This has no settings and nothing to draw. It is a source of answers that
     nameplates read from and unit frames will -- the same shape as
     `modules/parser.lua`, which is also not a module for the same reason.
     Registering it would put an empty page on the panel and a pointless line on
     the Modules list.

     So it carries its own event frame, which is three lines and owes nothing to
     the registry. ]]--
local M = { }
OB.casts = M

local EVENTS = {
    --[[ The player's own, which are exact. ]]--
    --[[ The spellbook changes when you learn, train or respec, and the icon
         map is built from it. ]]--
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",

    "SPELLCAST_START", "SPELLCAST_STOP", "SPELLCAST_FAILED",
    "SPELLCAST_INTERRUPTED", "SPELLCAST_DELAYED",
    "SPELLCAST_CHANNEL_START", "SPELLCAST_CHANNEL_STOP",

    --[==[ **Everybody else's, which arrive as sentences.**

         1.12 splits the combat log by who did what to whom, so a cast can be
         announced through any of a dozen channels and an addon has to name every
         one it wants.

         **`CREATURE_VS_SELF` was missing, and it is the one that matters most.**
         `CREATURE_VS_CREATURE` is a mob casting at another mob; a mob casting at
         *you* comes through `CREATURE_VS_SELF`, and at somebody in your group
         through `CREATURE_VS_PARTY`. Neither was registered. So the single
         commonest case in the game -- the thing you are fighting, casting at you
         -- never reached this module at all, and its nameplate never drew a bar.
         That is the reported fault, and it is an absence rather than a mistake.

         Checked against the client's own `ChatFrame.lua` rather than against
         memory or against the addon this was ported from: that file names every
         channel the client has, which is the only list that settles it. ]==]
    "CHAT_MSG_SPELL_SELF_DAMAGE",
    "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF",
    "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
    "CHAT_MSG_SPELL_CREATURE_VS_SELF_BUFF",
    "CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_CREATURE_VS_PARTY_BUFF",
    "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE",
    "CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF",
    "CHAT_MSG_SPELL_PARTY_DAMAGE",
    "CHAT_MSG_SPELL_PARTY_BUFF",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_BUFFS",

    --[==[ **And the client's own cast event, where there is one.**

         SuperWoW adds `UNIT_CASTEVENT`, which hands over the caster's GUID, the
         spell id and the cast time directly. Everything above is a sentence
         being read back into facts it was never meant to carry; this is the
         facts. Registering an event a client does not send costs nothing, so it
         is asked for unconditionally and simply never fires without it. ]==]
    "UNIT_CASTEVENT",

    --[[ **And the lines that end a cast**, which is a separate set because the
         log announces a death and an interrupt through the combat channels
         rather than the spell ones. Without these nothing ever ended anybody
         else's cast -- see `STOPS`. ]]--
    "CHAT_MSG_COMBAT_HOSTILE_DEATH",
    "CHAT_MSG_COMBAT_FRIENDLY_DEATH",
    "CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS",
    "CHAT_MSG_SPELL_BREAK_AURA",
}

--[[ **Read the caster and the spell out of one line.**

     `SPELLCASTOTHERSTART` is the client's own sentence -- "%s begins to cast
     %s." -- and going through the parser's pattern machinery rather than
     matching English is the same rule every other line in this addon follows:
     whatever the client says is what gets read, in whatever language it says it.

     `SPELLPERFORMOTHERSTART` is the same event for abilities rather than spells,
     and a client that lacks either simply never matches it. ]]--
local STARTS = { "SPELLCASTOTHERSTART", "SPELLPERFORMOTHERSTART" }

--[==[ **And the lines that end one, which nothing was reading.**

     `OB.StopCast` was called from exactly one place -- the player's own
     `SPELLCAST_STOP`. Nobody else's cast was ever ended: it sat in the table
     until it timed out, either at the spell's learned duration or at the five
     second cap for an unknown one. So a mob that finished casting, was
     interrupted, or died kept a cast bar showing a spell it was no longer
     casting, for as long as several seconds. That is the reported "incorrect
     spell always showing", and the fault is an absence rather than a mistake.

     **Which name is the caster differs by sentence**, so each carries the
     capture it lives in. "%s dies." has one name and it is the caster; "%s
     interrupts %s's %s." has the interrupter first and the caster second. The
     parser returns captures in the order the *pattern* declares them, which is
     what makes reading the second one safe in a language that reorders them. ]==]
local STOPS = {
    { "UNITDIESOTHER", 1 },
    { "UNITDESTROYEDOTHER", 1 },
    { "SPELLINTERRUPTOTHEROTHER", 2 },
    { "SPELLINTERRUPTSELFOTHER", 1 },
}

function M:ReadCastLine(text)
    if not text then return nil end

    for i = 1, table.getn(STARTS) do
        local sentence = getglobal(STARTS[i])

        if sentence then
            local who, spell = OB.ParseLine(text, sentence)
            if who and spell then return who, spell end
        end
    end

    return nil
end

function M:ReadStopLine(text)
    if not text then return nil end

    for i = 1, table.getn(STOPS) do
        local sentence = getglobal(STOPS[i][1])

        if sentence then
            local first, second = OB.ParseLine(text, sentence)
            local who = (STOPS[i][2] == 2) and second or first

            if who then return who end
        end
    end

    return nil
end

function M:OnEvent()
    if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
        OB.RebuildSpellIcons()
        return
    end

    --[[ The player's own casts, where the client hands over the exact
         duration. ]]--
    if event == "SPELLCAST_START" then
        OB.StartCast(UnitName("player"), arg1, arg2)
        return
    end

    if event == "SPELLCAST_CHANNEL_START" then
        --[[ Channels reverse the arguments: the duration comes first. Not a
             mistake in the reading -- it is what the client sends. ]]--
        OB.StartCast(UnitName("player"), arg2, arg1, true)
        return
    end

    if event == "SPELLCAST_STOP" or event == "SPELLCAST_FAILED"
            or event == "SPELLCAST_INTERRUPTED"
            or event == "SPELLCAST_CHANNEL_STOP" then
        OB.StopCast(UnitName("player"))
        return
    end

    --[[ A delayed cast is pushed back rather than restarted, which is what
         being hit while casting does. Restarting it would show the bar jumping
         back to the beginning, which is not what happened. ]]--
    if event == "SPELLCAST_DELAYED" then
        local cast = OB.casting[UnitName("player")]
        if cast and arg1 then cast.start = cast.start + (arg1 / 1000) end
        return
    end

    --[==[ **The client's own cast event, which needs no sentence read to it.**

         `UNIT_CASTEVENT(casterGUID, targetGUID, type, spellId, castTime)`. It
         carries what the log cannot: which *unit* is casting rather than which
         name, and how long the cast is rather than nothing at all.

         Only a start opens a bar. `CAST` is the completion of one -- or an
         instant, which has no bar to draw -- and either way it ends what was
         showing. Anything else this event carries, swings among them, is not a
         cast and is left alone rather than guessed at. ]==]
    if event == "UNIT_CASTEVENT" then
        local guid, kind, spellId, castTime = arg1, arg3, arg4, arg5

        if not guid then return end

        if kind == "START" or kind == "CHANNEL" then
            local spell
            if type(SpellInfo) == "function" then
                local ok, resolved = pcall(SpellInfo, spellId)
                if ok then spell = resolved end
            end

            --[[ A cast with no readable name is still a cast. It is dropped
                 rather than drawn as a blank bar: the name is the part of a
                 nameplate cast bar that carries the meaning. ]]--
            if spell and spell ~= "" then
                OB.StartCastFor(guid, spell, tonumber(castTime),
                        kind == "CHANNEL")
            end
            return
        end

        if kind == "CAST" or kind == "FAIL" then OB.StopCast(guid) end
        return
    end

    --[[ Everybody else, out of the log. ]]--
    local who, spell = self:ReadCastLine(arg1)

    if who then
        OB.StartCast(who, spell)
        return
    end

    --[[ And the end of one. Tried only when the line was not a start, because a
         line cannot be both and the start set is the commoner of the two. ]]--
    local stopped = self:ReadStopLine(arg1)
    if stopped then OB.StopCast(stopped) end
end

M.frame = CreateFrame("Frame", "EquadisOverhaulCasts", UIParent)

for i = 1, table.getn(EVENTS) do
    M.frame:RegisterEvent(EVENTS[i])
end

--[[ Cleared on entering the world. A cast in flight across a loading screen is
     a cast whose caster is no longer there. ]]--
M.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

M.frame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        OB.casting = {}
        return
    end

    M:OnEvent()
end)
