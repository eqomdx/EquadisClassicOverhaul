--[[ Equadis' Classic Overhaul :: auras

  **What is on a unit that is not your target.**

  The same hole as casts and the same shape of answer. 1.12's `UnitDebuff` needs
  a unit token, a nameplate has none, and so an addon that wants to show "does
  this mob still have my Rend on it" has to keep the book itself.

  ShaguPlates' `libdebuff` is the one this follows, and the technique is the same
  as the cast library's: **keyed by unit name**, fed from two sources of very
  different quality.

  **The target is exact.** `UnitDebuff("target", i)` gives the texture and the
  stack count directly, and a target change or an aura change re-reads all of
  them. Nothing is inferred.

  **Everything else comes out of the combat log**, which announces "X is
  afflicted by Y" and stops. No icon, no duration, no stack count -- a name and
  nothing else.

  So the icon is *learned*: the first time a spell is seen on your target, its
  texture is recorded against its name, and from then on any unit afflicted by
  that spell can be drawn with it. Which means the icons fill in as you fight,
  and a spell nobody has ever had on a target is known by name and not by
  picture.

  **Durations are not tracked at all, and that is deliberate.** 1.12's
  `UnitDebuff` does not return one -- it gives a texture and a count and stops --
  so a duration can only come from a shipped table of every spell in the game.
  ShaguPlates ships one. The useful question on a nameplate is *whether* your
  debuff is on the thing, not how many seconds are left, and answering the first
  honestly beats answering the second from a table that has to be maintained.
]]--

local OB = EquadisClassicOverhaul

-- ---------------------------------------------------------------------------
-- what is on whom
-- ---------------------------------------------------------------------------

--[[ Unit name -> spell name -> when it was last seen. Not saved: an aura lasts
     under a minute and nothing about it survives a reload worth keeping. ]]--
OB.auras = {}

--[[ The same shape again, for the few auras whose length is not a fact about
     the spell. Kept beside rather than inside, because every reader of `auras`
     expects a number and a second shape there would be a rewrite of all of
     them. ]]--
OB.auraLengths = {}

--[==[ **Some debuffs are as long as the combo points that paid for them.**

     Reported as: Blind works, Cheap Shot works, Kidney Shot shows nothing. That
     is exactly the split between a fixed duration and a bought one, and the
     shipped table says so out loud --

         ['Blind']       = { [0] = 10.0 }
         ['Cheap Shot']  = { [0] =  4.0 }
         ['Kidney Shot'] = { [1] =  0,   [2] = 1.0 }

     Kidney Shot has no `[0]` because it has no fixed length: those are the
     *base* durations of its two ranks, and the rest is a second per combo
     point. With no entry to read, the code took the longest rank it could find
     -- one second -- and the timer expired while the stun was plainly still on,
     which reads as no timer at all.

     So the per-point part is here, and the base stays where it is. Rupture is
     the other one: six seconds and two more per point.

     **How many points**: they are spent before the debuff lands, so the value
     is caught on the way down. `PLAYER_COMBO_POINTS` fires as they are used,
     and the last non-zero count is kept for a couple of seconds -- long enough
     to cover the gap between spending them and the combat log announcing what
     they bought.

     **Somebody else's finisher is assumed to be a full one.** There is no way
     to know what a rogue outside your group spent, and this file's rule
     throughout is that a timer must never promise less than the aura has: a
     stun that is over according to a number still stunning you is worse than a
     number that runs a little long. ]==]
local COMBO_PER_POINT = {
    ["Kidney Shot"] = 1,
    ["Rupture"] = 2,
}

local COMBO_MAX = 5
local COMBO_WINDOW = 2

--[[ What was on the bar the moment before it was spent. ]]--
OB.comboHeld = 0
OB.comboSpent = { points = 0, at = -1 }

function OB.NoteComboPoints(points)
    points = tonumber(points) or 0

    if points > 0 then
        OB.comboHeld = points
        return points
    end

    --[[ Nought after something: that is a finisher, or a target lost. Both look
         the same from here, which is what the window below is for. ]]--
    if (OB.comboHeld or 0) > 0 then
        OB.comboSpent = { points = OB.comboHeld, at = GetTime() }
        OB.comboHeld = 0
    end

    return 0
end

--[[ The points to credit a finisher landing now: the ones just spent if they
     were spent a moment ago, and a full bar otherwise. ]]--
function OB.ComboPointsFor(spell)
    if not COMBO_PER_POINT[spell] then return nil end

    local spent = OB.comboSpent

    if spent and (spent.points or 0) > 0
            and (GetTime() - (spent.at or -1)) <= COMBO_WINDOW then
        return spent.points
    end

    return COMBO_MAX
end

--[[ **How long to believe a debuff is still there.**

     Nothing tells us when one falls off a unit we cannot see. The combat log
     announces the fade sometimes and not always -- a mob that dies takes its
     debuffs with it and says nothing -- so an entry that has not been renewed is
     dropped after this long.

     Thirty seconds is longer than most things worth showing on a nameplate and
     short enough that a stale icon is not still there when you come back. It is
     a guess, and it is the only guess in this file. ]]--
local STALE = 30

function OB.AddAura(unit, spell, texture)
    if not unit or not spell then return false end

    OB.auras[unit] = OB.auras[unit] or {}
    OB.auras[unit][spell] = GetTime()

    --[[ Worked out now rather than when somebody asks, because by then the
         combo points that decided it have been spent again on something
         else. ]]--
    local points = OB.ComboPointsFor(spell)

    if points then
        OB.auraLengths[unit] = OB.auraLengths[unit] or {}
        OB.auraLengths[unit][spell] = OB.ComboDuration(spell, points)
    end

    --[[ The icon, learned once and kept for every unit afterwards. This is what
         turns a combat log line -- which carries no picture -- into something
         that can be drawn. ]]--
    if texture and OB.auraIcons then OB.auraIcons[spell] = texture end

    return true
end

--[==[ **An aura noticed on a unit, rather than one seen to land.**

     `AddAura` stamps the current time, which is right for a combat log line --
     that line *is* the moment it landed. It is wrong for a scan: the debuff
     scanner walks the target's auras every second, and stamping each time
     restarts the clock on every pass, so a timer built on it never counts down.

     Reported as debuff timers missing on nameplates and on the target frame.
     Both read the same store, and both were reading a number that had just been
     set to now.

     So a scan *notes* rather than adds: the first sighting starts the clock and
     every one after it changes nothing. The clock is then honest about what it
     knows -- when this addon first saw the aura -- which is not always when it
     landed, and is the best any 1.12 client can do for somebody else's
     debuff. ]==]
--[==[ **Why a debuff has no number under it, link by link.**

     A timer needs four things and any one of them missing looks identical from
     outside -- an icon with nothing under it:

       the debuff has to be readable at all (`UnitDebuff`),
       its *name* has to be readable (the tooltip scan),
       the aura store has to have a first-seen time for it, and
       the shipped duration table has to know how long that spell lasts.

     Reported twice as "debuffs are missing timers", once on nameplates and once
     on the target frame -- which are two readers of the same four facts. This
     prints all four for whatever is targeted. ]==]
function OB.DebuffChainDebug()
    local unit = "target"

    if type(UnitExists) ~= "function" or not UnitExists(unit) then
        return OB.Print("target something first.", "Auras")
    end

    local who = UnitName(unit)
    OB.Print("debuffs on " .. tostring(who) .. ":", "Auras")

    local tip = OB.ScanTooltip and OB.ScanTooltip()
    local any = false

    for i = 1, 16 do
        local texture = UnitDebuff(unit, i)
        if not texture then break end

        any = true
        local spell

        if tip and type(tip.SetUnitDebuff) == "function" then
            tip:ClearLines()
            if pcall(tip.SetUnitDebuff, tip, unit, i) then spell = OB.ScanLine(1) end
        end

        if spell == "" then spell = nil end

        --[==[ **Which source named it**, because "(no name)" on its own does not
             say whether the tooltip is answering nothing on this client or the
             spell is simply one nothing has ever logged. The first is a fault
             and the second is ordinary. ]==]
        local named = spell and "tooltip" or nil
        local plates = OB.modules and OB.modules.nameplates

        if not spell and plates and plates.NameByIcon then
            spell = plates:NameByIcon(who, texture)
            if spell then named = "its icon -- THE TOOLTIP SCAN ANSWERED NOTHING" end
        end

        local seen = spell and OB.auras and OB.auras[who] and OB.auras[who][spell]
        local ranks = spell and OB.debuffDurations and OB.debuffDurations[spell]
        local left = spell and OB.AuraTimeText(who, spell)

        OB.Raw("  " .. i .. ": " .. tostring(spell or "(no name)")
                .. " | named by: " .. tostring(named or "nothing")
                .. " | first seen: " .. (seen and OB.Round(GetTime() - seen) .. "s ago" or "never")
                .. " | duration known: " .. (ranks and "yes" or "no")
                .. " | shows: " .. tostring(left or "nothing"))
    end

    if not any then OB.Raw("  the target has no debuffs on it") end

    --[[ And whether the two readers are switched on at all, which is the other
         way to end up with icons and no numbers. ]]--
    local plates = OB.modules and OB.modules.nameplates
    local frames = OB.modules and OB.modules.unitframes

    OB.Raw("  nameplate timers: "
            .. tostring(plates and plates:Config().debuffTimers))
    OB.Raw("  unit frame timers: "
            .. tostring(frames and frames:Config().auraTimers))
end

function OB.NoteAura(unit, spell, texture)
    if not unit or not spell then return false end

    if OB.auras[unit] and OB.auras[unit][spell] then
        --[[ Already ticking. The icon is still learned, because an icon this
             addon has not seen before is worth keeping whenever it turns up. ]]--
        if texture and OB.auraIcons then OB.auraIcons[spell] = texture end
        return false
    end

    return OB.AddAura(unit, spell, texture)
end

function OB.RemoveAura(unit, spell)
    if not unit or not spell then return end
    if not OB.auras[unit] then return end

    OB.auras[unit][spell] = nil
    if OB.auraLengths[unit] then OB.auraLengths[unit][spell] = nil end
end

--[==[ **Base plus what was paid for it.**

     The base is the shipped table's, per rank -- and a ranked spell seen
     without its rank takes the longest rank, which is the same rule the fixed
     durations follow and for the same reason. ]==]
function OB.ComboDuration(spell, points)
    local per = COMBO_PER_POINT[spell]
    if not per then return nil end

    local ranks = OB.debuffDurations and OB.debuffDurations[spell]
    local base = 0

    if ranks then
        base = ranks[0]

        if not base then
            for _, seconds in pairs(ranks) do
                if not base or seconds > base then base = seconds end
            end
        end
    end

    return (base or 0) + (per * (tonumber(points) or 0))
end

--[[ What is on a unit, newest first, with icons where they are known.

     **Expiry happens here** rather than on a timer, exactly as the cast library
     does it: asking is the only moment it matters, and there is no sweep to
     schedule and nothing to leak. ]]--
--[[ **How long is left, which needed one thing this module already had.**

     The header above says durations are not tracked because 1.12 gives none and
     a table of every spell would be needed. That was right, and the missing
     half was only ever the table -- because the *other* half has been here all
     along: `AddAura` records `GetTime()` when a spell is first seen on a unit.

     Seen-at plus how-long is when-it-ends. The table ships with the addon now
     (`libs/debuffdurations.lua`, from ShaguPlates under MIT), so the question
     can be answered.

     **Nil when it cannot be answered honestly.** A spell absent from the table,
     or one whose duration has run out, returns nothing rather than a zero or a
     guess -- a timer that says 0 on a debuff still ticking is worse than no
     timer, because it is read as fact. ]]--
function OB.AuraTimeLeft(unit, spell)
    if not unit or not spell then return nil end
    if not OB.auras or not OB.auras[unit] then return nil end

    local seen = OB.auras[unit][spell]
    if not seen then return nil end

    --[==[ **A length written down when the aura landed wins.**

         It is the only one that can be right for a debuff whose duration was
         bought rather than fixed: the combo points that decided a Kidney Shot's
         length are gone by the time anybody looks at the timer. ]==]
    local bought = OB.auraLengths[unit] and OB.auraLengths[unit][spell]

    if bought and bought > 0 then
        local remaining = (seen + bought) - GetTime()
        if remaining <= 0 then return nil end

        return remaining
    end

    --[==[ **Both tables, because a unit frame draws both lists.**

         `debuffDurations` is what shipped, and it is what its name says: a
         target's debuffs counted down and its buffs showed nothing. It carries a
         handful of buffs incidentally -- Battle Shout, Arcane Intellect, Mark of
         the Wild are in it -- which is what made the gap read as flaky rather
         than as missing: some buffs had a timer and most did not.

         Debuffs are asked first because that table is the larger and the more
         specific: it is generated from a debuff list, so a name in it is a
         debuff, while a name shared with the buff table is one somebody would
         have had to add here by hand. ]==]
    local ranks = (OB.debuffDurations and OB.debuffDurations[spell])
            or (OB.buffDurations and OB.buffDurations[spell])

    if not ranks then return nil end

    --[[ Rank zero is the entry for a spell whose rank does not change its
         duration, which is most of them and every mob ability. A ranked spell
         seen without its rank takes the longest, because guessing short shows a
         timer expiring while the debuff is visibly still on. ]]--
    local duration = ranks[0]

    if not duration then
        for _, seconds in pairs(ranks) do
            if not duration or seconds > duration then duration = seconds end
        end
    end

    if not duration or duration <= 0 then return nil end

    local left = (seen + duration) - GetTime()
    if left <= 0 then return nil end

    return left
end

--[[ The same, as something to put on an icon. Minutes once past a minute,
     because "83" on a two-minute curse is a number nobody reads as time. ]]--
--[==[ **One way of writing a duration, for everything that shows one.**

     Minutes above a minute, seconds below it. The alternative -- "312" on a
     five-minute buff -- is a number nobody converts at a glance, and a row of
     aura icons is read at a glance or not at all.

     Split out from `AuraTimeText` because the player's own auras get their time
     from the client directly rather than from the seen-at table, and two
     formatters would have drifted apart the first time either was touched. ]==]
--[==[ **Seconds inside the minutes while it still matters.**

     This rounded everything above a minute to whole minutes, so a buff sat on
     "2m" for a hundred and twenty seconds and then vanished. That is fine for a
     thirty-minute blessing and useless for the last stretch of anything, which
     is exactly when the number is being read.

     Five minutes is where it changes. Above it the seconds are noise -- nobody
     acts on the difference between 19m03s and 19m -- and below it they are the
     whole point: a poison at 4m59s is a different decision from one at 4m01s.

     Rounded *down* below five minutes rather than to nearest, which is the
     other half of being accurate: a timer reading 1m when there are 59 seconds
     left has rounded up into a minute that does not exist. Down means the
     number never promises time the aura has not got. ]==]
--[==[ **Where the seconds stop, as an argument rather than a constant.**

     Five minutes was chosen here and argued for above, and the argument still
     holds -- it is simply not the only reasonable answer. Somebody watching a
     thirty minute blessing wants the seconds much later than somebody watching
     a poison, and the number is cheap to offer.

     A default rather than a required argument, because three other callers read
     this function and none of them has an opinion: the nameplates and the unit
     frames want what it has always done. ]==]
local MINUTE_DETAIL = 5

function OB.DurationText(seconds, detailMinutes)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end

    if seconds >= 3600 then
        return string.format("%dh", math.floor((seconds / 3600) + 0.5))
    end

    local detail = (tonumber(detailMinutes) or MINUTE_DETAIL) * 60

    if seconds >= detail then
        return string.format("%dm", math.floor((seconds / 60) + 0.5))
    end

    if seconds >= 60 then
        local minutes = math.floor(seconds / 60)
        return string.format("%dm%02ds", minutes, math.floor(seconds - (minutes * 60)))
    end

    --[==[ **The `s` stays under a minute**, which it did not.

         It was dropped on the reasoning that a bare number under an aura icon is
         unambiguous, because everything under an aura icon is seconds. True in
         isolation and wrong as part of a format: this one is called `4m59s`, and
         a timer that says `4m01s`, then `1m00s`, then `45` has changed its mind
         about what it is at the boundary. The reader notices the change, not the
         reasoning behind it.

         It is also the one place the bare number **is** ambiguous -- the other
         number drawn on an aura icon is the stack count, and `45` beside `3` is
         two numbers with no units between them. Reported as exactly that: the
         `s` missing under sixty seconds.

         The clock format is untouched. `0:45` already says what it is by having
         a colon in it. ]==]
    return string.format("%ds", math.floor(seconds))
end

--[==[ **The same duration written as a clock.**

     Asked for as an option: `4:59` rather than `4m59s`. It is the shorter of the
     two by two characters, which on a thirty-pixel icon is most of the argument,
     and it is what a stopwatch looks like.

     **Above an hour the two agree**, and deliberately. `1:05` would be five
     minutes past one o'clock to one reader and one minute five seconds to
     another, and a timer that can be misread by an hour is worse than one that
     is two characters longer. Seconds are noise up there anyway -- nobody acts
     on the difference between 19m03s and 19m -- so both formats say `1h`.

     Below a minute it is `0:45` rather than `45`. The leading zero is what makes
     it read as a clock rather than as a stack count, which is the other number
     drawn on an aura icon. ]==]
function OB.DurationClock(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end

    --[[ Hours are the letters format's business; see above. ]]--
    if seconds >= 3600 then
        return string.format("%dh", math.floor((seconds / 3600) + 0.5))
    end

    --[[ Rounded down, the same as the letters format and for the same reason: a
         timer must never promise time the aura has not got. ]]--
    local whole = math.floor(seconds)
    local minutes = math.floor(whole / 60)

    return string.format("%d:%02d", minutes, whole - (minutes * 60))
end

--[[ Which of the two, by name, so a caller stores a word rather than a
     boolean -- a third format later is then a row on a list instead of a
     rewrite. ]]--
function OB.DurationIn(format, seconds, detailMinutes)
    if format == "clock" then return OB.DurationClock(seconds) end
    return OB.DurationText(seconds, detailMinutes)
end

--[==[ **Which spell an icon is, when the tooltip will not say.**

     `SetUnitDebuff` answers nothing on this client. Why is still unknown -- it is
     recorded in NOTICE that BetterCharacterStats builds its scanning tooltip
     character for character the same way and its scanning works -- and it does
     not need to be known: an aura nobody can name has no duration, and the icon
     is a second way of asking.

     Only among the spells **this unit is known to carry**, so two spells sharing
     art cannot be confused for one another. An aura nothing has ever logged
     stays nameless and shows an icon with no number, which is honest.

     **It lived on the nameplate module** and used nothing from it -- no `self`,
     only the shared store. That is why the unit frames did not have it: not a
     decision, an accident of where it was typed. Here, beside the store it
     reads, so the next reader finds it. ]==]
function OB.AuraNameByIcon(who, texture)
    if not who or not texture then return nil end
    if not OB.auras or not OB.auras[who] then return nil end
    if not OB.auraIcons then return nil end

    for spell in pairs(OB.auras[who]) do
        if OB.auraIcons[spell] == texture then return spell end
    end

    return nil
end

function OB.AuraTimeText(unit, spell)
    return OB.DurationText(OB.AuraTimeLeft(unit, spell))
end

function OB.AuraList(unit, limit)
    if not unit or not OB.auras[unit] then return {} end

    local now = GetTime()
    local out = {}

    for spell, seen in pairs(OB.auras[unit]) do
        if now - seen > STALE then
            OB.auras[unit][spell] = nil
        else
            table.insert(out, {
                spell = spell,
                seen = seen,
                icon = OB.auraIcons and OB.auraIcons[spell],
            })
        end
    end

    --[[ Newest first, which is the order somebody applied them in and therefore
         the order they think of them in. A stable order matters more than which
         one it is: icons that reshuffle every frame are unreadable. ]]--
    table.sort(out, function(a, b) return a.seen > b.seen end)

    if limit and table.getn(out) > limit then
        for i = table.getn(out), limit + 1, -1 do
            table.remove(out, i)
        end
    end

    return out
end

-- ---------------------------------------------------------------------------
-- watching for them
-- ---------------------------------------------------------------------------

--[[ Not a module and not a tab, for the reason `modules/casts.lua` gives: no
     settings, nothing to draw, and a source of answers rather than a subsystem. ]]--
local M = { }
OB.auraWatch = M

--[[ **Reading the target's debuffs, which is the only exact source there is.**

     `UnitDebuff` in 1.12 answers a texture and a stack count and nothing else --
     no name. The name has to come from a tooltip scan, which the addon already
     does for the action bar search, and which is affordable here because this
     runs on a target change rather than on a draw. ]]--
function M:ScanTarget()
    if not UnitExists("target") then return 0 end

    local unit = UnitName("target")
    if not unit then return 0 end

    local found = 0
    local tip = OB.ScanTooltip()

    for i = 1, 16 do
        local texture = UnitDebuff("target", i)
        if not texture then break end

        --[[ The name, out of the tooltip the client fills in for that slot. A
             debuff with no readable name is still recorded by its texture, which
             is enough to draw it even when it cannot be named. ]]--
        local spell

        if type(tip.SetUnitDebuff) == "function"
                and pcall(tip.SetUnitDebuff, tip, "target", i) then
            spell = OB.ScanLine(1)
        end

        --[==[ **Noted, not added, and this is the whole of the reported bug.**

             `AddAura` stamps the current time, which is right for a combat log
             line -- that line *is* the moment it landed. This is a scan: it
             walks the target's debuffs every second and had been re-stamping
             every one of them, so the clock restarted on every pass and the
             number under the icon never moved.

             `OB.NoteAura` exists for exactly this and says so in its own
             header. The nameplate scan and the target frame's pass were both
             moved onto it; this one -- the scanner the header is describing --
             was left behind, which is why the timers still sat still. ]==]
        if spell and spell ~= "" then
            OB.NoteAura(unit, spell, texture)
            found = found + 1
        end
    end

    return found
end

--[[ A debuff landing on somebody who is not your target, which the combat log
     announces and describes in three words.

     Through the client's own sentence rather than by matching English, the same
     rule every parsed line in this addon follows. ]]--
function M:ReadAuraLine(text)
    if not text then return nil end
    if not AURAADDEDOTHERHARMFUL then return nil end

    local unit, spell = OB.ParseLine(text, AURAADDEDOTHERHARMFUL)
    if unit and spell then return unit, spell end

    return nil
end

--[[ And one falling off, which is announced the other way round: the spell is
     named first and the unit second. Getting that backwards files every fade
     under a unit called "Rend". ]]--
function M:ReadFadeLine(text)
    if not text then return nil end
    if not AURAREMOVEDOTHER then return nil end

    local spell, unit = OB.ParseLine(text, AURAREMOVEDOTHER)
    if unit and spell then return unit, spell end

    return nil
end

local EVENTS = {
    "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
    "CHAT_MSG_SPELL_AURA_GONE_OTHER",
    "PLAYER_TARGET_CHANGED",
    "UNIT_AURA",

    --[[ Watched here rather than in the combo point module, because that one
         can be switched off and this is not about drawing them: it is the only
         moment the length of a finisher's debuff can be known. ]]--
    "PLAYER_COMBO_POINTS",
}

M.frame = CreateFrame("Frame", "EquadisOverhaulAuras", UIParent)

for i = 1, table.getn(EVENTS) do
    M.frame:RegisterEvent(EVENTS[i])
end

M.frame:RegisterEvent("PLAYER_ENTERING_WORLD")

M.frame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        OB.auras = {}
        OB.auraLengths = {}
        return
    end

    if event == "PLAYER_COMBO_POINTS" then
        OB.NoteComboPoints(type(GetComboPoints) == "function"
                and GetComboPoints() or 0)
        return
    end

    --[[ The exact source: a target change or an aura change on the target
         re-reads all of them, which is both correct and how the icons get
         learned. ]]--
    if event == "PLAYER_TARGET_CHANGED"
            or (event == "UNIT_AURA" and arg1 == "target") then
        M:ScanTarget()
        return
    end

    if event == "CHAT_MSG_SPELL_AURA_GONE_OTHER" then
        local unit, spell = M:ReadFadeLine(arg1)
        if unit then OB.RemoveAura(unit, spell) end
        return
    end

    local unit, spell = M:ReadAuraLine(arg1)
    if unit then OB.AddAura(unit, spell) end
end)
