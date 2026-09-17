--[[ Equadis' Classic Overhaul :: threat meter

  Who has the aggro, and how close you are to taking it.

  The first **feature** module: it owns a window rather than a bar in the
  cluster, so it is bound by hud.lua's feature path and is listed on the Modules
  page. Everything else it shares with the bars -- the event map, the dirty-flag
  redraw, the profile, the media, the options panel.

  Ported from Equadis' Threat Meter, which this supersedes. Two things about that
  port are worth knowing before changing anything here.

  **The data is given, not derived.** Turtle broadcasts threat to the party over
  the addon channel as a single packet with a `TWTv4=` prefix, and this reads it.
  There is no combat log parsing anywhere in this file, which is why the threat
  meter did not have to wait for the parser the damage meter needs -- and why
  none of this works on a server that does not send the packet. It says so rather
  than showing an empty window.

  **The packet is the whole protocol**, so parsing it is the only thing that has
  to be exactly right. It is separated from everything that draws for that
  reason: OB.ParseThreatPacket is a pure function over a string, and the tests
  drive it directly with packets rather than through a window.
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "Threat") end

--[[ The prefix the server puts on a threat broadcast. Versioned by Turtle, and
     the version matters: v3 packets are a different shape and the standalone
     addon's changelog records each bump breaking the previous reader. If threat
     stops arriving after a server patch, this is the first thing to check. ]]--
local PACKET_PREFIX = "TWTv4="

--[[ One entry per player in the packet, colon separated:

       name : isTank : threat : percent : isMelee

     A sixth field exists and is relayed by the standalone addon but read by
     nothing, so it is not parsed here. Fields beyond the fifth are ignored
     rather than rejected: a later server adding one should not blank the meter.

     Percent is **percent of the tank's threat**, so it runs past 100 for
     whoever currently holds aggro. That is not a bug to clamp -- it is the
     number the whole readout is about. ]]--
local FIELDS = 5

--[[ Split on a single character. `string.gfind` is the Lua 5.0 name and the only
     one this client has; `gmatch` does not exist here, which the stub enforces.

     A pattern rather than a loop of `string.find` because the separators are
     fixed single characters and the pattern form is the one that reads. ]]--
local function split(text, sep)
    local out = {}
    if not text then return out end

    for piece in string.gfind(text, "[^" .. sep .. "]+") do
        table.insert(out, piece)
    end

    return out
end

--[[ Read a threat packet into a table keyed by player name, or nil if this is
     not one.

     nil rather than an empty table for a message that is not ours, because the
     two mean different things: an empty table is "the packet said nobody has
     threat", which is a real answer and should clear the window. A message from
     another addon should leave the window exactly as it was.

     Pure, and deliberately so. Everything about drawing is somewhere else, so a
     server changing the protocol is one function to fix and one set of tests to
     re-point. ]]--
function OB.ParseThreatPacket(message)
    if type(message) ~= "string" then return nil end

    local at = string.find(message, PACKET_PREFIX, 1, true)
    if not at then return nil end

    local body = string.sub(message, at + string.len(PACKET_PREFIX))

    local entries = {}
    local players = split(body, ";")

    for i = 1, table.getn(players) do
        local f = split(players[i], ":")

        --[[ A short entry is dropped and the rest of the packet is still read.
             One malformed player must not cost the raid: the packet arrives
             whole, so rejecting it entirely would blank a window that was
             correct a moment ago. ]]--
        if table.getn(f) >= FIELDS then
            local threat = tonumber(f[3])
            local percent = tonumber(f[4])

            if threat and percent then
                entries[f[1]] = {
                    name = f[1],
                    tank = f[2] == "1",
                    threat = threat,
                    percent = percent,
                    melee = f[5] == "1",
                }
            end
        end
    end

    return entries
end

-- ---------------------------------------------------------------------------
-- what each of your abilities is worth in threat
-- ---------------------------------------------------------------------------

--[[ **The question the meter could not answer: how much threat does *this* cost?**

     The window says where everybody stands. It has never said what to stop doing
     about it -- and the answer to "I keep pulling" is almost always one ability
     rather than all of them.

     Nothing in the game will tell you. There is no threat-per-spell API, the
     packet carries totals only, and the published coefficients are a wiki page
     that is wrong for half the abilities on a private server.

     **So it is measured.** The packet gives your total threat twice a second;
     the combat log says what you did in between. When exactly one thing happened
     in a window, the change in threat belongs to that one thing.

     A window with two events in it teaches nothing and is thrown away. That
     sounds wasteful and is not: a rotation produces a great many single-event
     windows at two packets a second, and one clean sample is worth more than
     five apportioned by a model nobody checked.

     Account-wide, beside the cast times and the vendor prices, on the same
     argument -- what Sinister Strike is worth in threat is a fact about the game
     rather than a setting. ]]--
function OB.LearnThreatFor(spell, amount)
    if not spell or not amount then return false end
    if not OB.threatPerSpell then return false end

    --[[ Zero teaches nothing and there are a lot of zeroes: any window where the
         packet arrived before the server had processed the hit. Left out rather
         than averaged in, where they would drag every figure towards nothing. ]]--
    if amount == 0 then return false end

    local known = OB.threatPerSpell[spell]

    if not known then
        known = { samples = 0, total = 0 }
        OB.threatPerSpell[spell] = known
    end

    known.samples = known.samples + 1
    known.total = known.total + amount

    return true
end

--[[ What one use of an ability is worth, and how sure that is.

     **The sample count is returned with the number and is not decoration.** One
     sample is an anecdote and thirty is a measurement, and a readout that showed
     both the same way would be inviting somebody to rebuild their rotation
     around a single lucky window. ]]--
function OB.ThreatFor(spell)
    local known = OB.threatPerSpell and OB.threatPerSpell[spell]
    if not known or known.samples == 0 then return nil, 0 end

    return known.total / known.samples, known.samples
end

--[[ Whoever the packet says is tanking, or nil.

     Read from the entries rather than tracked separately: the packet is
     authoritative and rebuilt whole each time, so a remembered tank name is a
     second source of truth that can only ever disagree with the first. ]]--
function OB.ThreatTank(entries)
    if not entries then return nil end

    for name, entry in pairs(entries) do
        if entry.tank then return entry end
    end

    return nil
end

--[[ The threat at which *this* player pulls aggro.

     Melee take aggro at 110% of the tank's threat and everyone else at 130%,
     because a ranged attacker has to exceed the tank by more to rip. That
     asymmetry is the single most useful thing the readout knows, and it is the
     reason the standalone drew a marker rather than a plain percentage. ]]--
local MELEE_PULL, RANGED_PULL = 110, 130

function OB.ThreatPullAt(melee)
    if melee then return MELEE_PULL end
    return RANGED_PULL
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

local M = OB.RegisterModule({
    id = "threat",
    name = "Threat Meter",

    --[[ A feature, not a bar: it owns a window, it is listed on the Modules
         page, and switching it off is a real decision about whether you would
         rather run somebody else's. ]]--
    feature = true,
    renders = "window",

    --[[ **Draws with the shared look**, so its page carries the texture, font,
         size, outline and border rows.

         Declared rather than inferred, because nothing about a module implies
         it: `renders` says "none" for nameplates and unit frames, which draw
         into the client's frames and use every one of the five.

         Chat, the roster and quality of life do not have this, and action bars
         gave it up -- they use a font and nothing else, so three of the five
         rows were controls that did nothing. ]]--
    styled = true,

    --[[ Ships off, because it is somebody's whole threat meter and turning it on
         should be a decision. `defaultEnabled`, not a setting called `enabled`
         in the defaults table -- the binder reads `modulesEnabled` and nothing
         else, so the latter would look like it worked and would not. ]]--
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
        x = 0, y = 0,
        width = 220,
        rowHeight = 16,
        rows = 10,

        bg = { 0, 0, 0, 0.5 },
        headerColor = { 0, 0, 0, 0.5 },
        locked = false,
        showThreat = true,

        --[[ Off, because threat arrives over the party/raid channel: alone
             there is no group to broadcast it, so the window can never have
             anything to say. On for anyone who wants it there to place. ]]--
        showSolo = false,

        --[[ On: it is what the window is for. See the options list for why it
             is nonetheless a switch like the other two. ]]--
        showPercent = true,

        --[[ A rank down the left, like the damage meter's. It answers "am I
             third" without counting rows, which on a forty-man list is the
             difference between a glance and a search. ]]--
        showRank = true,

        --[[ Off, so the window stays. Threat stops arriving the moment a fight
             ends, so out of combat the window is showing the last pull -- which
             is worth reading, and is also clutter if you would rather it went
             away.

             Phrased as *hide* rather than *show* to match the bars' own
             `hideOOC`. Two checkboxes for one idea, one saying show and one
             saying hide, means every visit costs a moment working out which way
             round this one is. ]]--
        hideOutOfCombat = false,

        --[[ A summary bar above the list: how much threat you can still gain
             before you rip. On, because it is the one directly actionable
             number the window can give -- the rows say where everybody stands,
             this says how much room is left. ]]--
        showUntilPull = true,

        --[[ Off: the bar is a headline, and a headline that shrinks is hardest
             to read exactly when it matters. On, it grows towards danger -- a
             full bar means the mob is yours. ]]--
        fillUntilPull = false,

        --[[ Off. Leaving combat is when you read the meter -- who pulled, who
             was climbing -- so throwing the list away the instant the fight
             ends is a real preference rather than the obvious default. On for
             anyone who would rather the window went blank between pulls than
             show a fight that is over. ]]--
        clearOutOfCombat = false,

        --[[ Requests per second. A real rate now that the module asks for its
             own data rather than waiting to overhear it -- see M:Request. ]]--
        updateRate = 2,

        --[[ Nothing between rows by default: the border pad is already the only
             spacing a bordered window needs, and a gap on top of it is a stripe
             of background rather than breathing room. Yours to add. ]]--
        gap = 0,

        --[[ Class colours for everybody else, a ramp for you. Somebody else's
             threat is a fact about them and the class colour is how you find
             them in the list; *your* threat is the reading the window exists
             for, so it is the one that changes colour as it climbs.

             Off by default because it is a second colour scheme on one window,
             and a list where one row follows different rules than the rest is
             worth opting into. ]]--
        classColor = true,
        rampOwnRow = true,

        --[[ What a row is when nothing knows better. See M:RowColor for the
             order, and for why this rather than the ramp is the fallback. ]]--
        barColor = { 0.35, 0.42, 0.55, 1 },

        --[[ Green to red as you approach a pull. Three anchors for the reason
             OB.Ramp explains, and yours to set -- which is the difference from
             Equadis' Threat Meter, where the same green/yellow/red were
             literals in the row painter and nothing on its panel reached
             them. ]]--
        safeColor = { 0.20, 0.75, 0.25, 1 },
        closeColor = { 0.95, 0.85, 0.15, 1 },
        pullColor = { 0.85, 0.20, 0.20, 1 },
    },

    --[[ Same three sections as the damage meter, in the same order, because two
         meters side by side that group their settings differently make you learn
         the layout twice. See modules/damage.lua for what each one is for. ]]--
    options = {
        { "Window", "__s_window", "section", "window" },

        --[[ **Shown is not Enabled.** The Modules page switch decides whether
             this subsystem runs at all. This one only decides whether the
             window is on screen, so the numbers are still there when you show
             it again. `@moduleShow:` sends the row to `modulesShown`, which is
             what `OB.ModuleShown` reads and the draw loop honours. ]]--
        { "Show The Meter", "@moduleShow:threat", "boolean" },
        { "Width", "width", "slider", 100, 500, 1 },
        { "Rows Shown", "rows", "slider", 3, 40, 1 },
        { "X Position", "x", "slider", -2000, 2000, 1 },
        { "Y Position", "y", "slider", -2000, 2000, 1 },
        { "Lock Window", "locked", "boolean" },
        { "Show When Solo", "showSolo", "boolean" },
        { "Hide Out Of Combat", "hideOutOfCombat", "boolean" },
        { "Threat Until Pull Bar", "showUntilPull", "boolean" },
        { "Fill It By Threat", "fillUntilPull", "boolean",
          nil, nil, nil, nil, "showUntilPull" },

        --[[ Dimmed when the window is hidden out of combat anyway: clearing a
             list nobody can see is a distinction without a difference. ]]--
        { "Clear On Leaving Combat", "clearOutOfCombat", "boolean",
          nil, nil, nil, nil, nil, "hideOutOfCombat" },
        { "Updates Per Second", "updateRate", "slider", 1, 10, 1 },
        { "Background Color", "bg", "color", true },
        { "Header Color", "headerColor", "color", true },

        { "Bar", "__s_bar", "section", "bar" },
        { "Height", "rowHeight", "slider", 8, 32, 1 },
        { "Gap Between Bars", "gap", "slider", 0, 12, 1 },

        --[[ **The winner first, the fallback under it.**

             The painter resolves bar colour last of the three, so listing it
             first put the least-used control at the top and the one actually in
             charge below it. Reading down the page now goes strongest to
             weakest: your own pull ramp beats class, class beats the swatch.

             Each is dimmed by whatever outranks it, so the page shows which one
             is winning rather than leaving you to work it out. Dimmed and not
             hidden, for the usual reason: your colour is still there, something
             else is simply louder. ]]--
        { "Color Your Row By Threat", "rampOwnRow", "boolean" },
        { "Low Threat Color", "safeColor", "color", true,
          nil, nil, nil, nil, "!rampOwnRow" },
        { "Medium Threat Color", "closeColor", "color", true,
          nil, nil, nil, nil, "!rampOwnRow" },
        { "High Threat Color", "pullColor", "color", true,
          nil, nil, nil, nil, "!rampOwnRow" },

        { "Color Rows By Class", "classColor", "boolean" },

        --[[ Dimmed by class colour, which overrides it on every row it can
             resolve -- which is most of them, most of the time. ]]--
        { "Bar Color", "barColor", "color", true,
          nil, nil, nil, nil, "classColor" },

        { "Text", "__s_text", "section", "text" },
        { "Rank Number", "showRank", "boolean" },
        { "Threat Number", "showThreat", "boolean" },
        --[[ Measured rather than looked up, and the action says how much it has
             to go on. Nothing in the game will answer this: no threat-per-spell
             API, a packet carrying totals only, and published coefficients that
             are wrong for half the abilities on a private server. ]]--
        { "What Your Abilities Cost", "__a_spellthreat", "action",
          function() OB.modules.threat:PrintSpellThreat() end,
          function()
              local n = 0
              for _ in pairs(OB.threatPerSpell or {}) do n = n + 1 end
              if n == 0 then return "Nothing Measured Yet" end
              return "Threat Per Use For " .. n .. " Abilit" .. (n == 1 and "y" or "ies")
          end },

        { "Forget What Was Measured", "__a_forgetthreat", "action",
          function()
              EquadisClassicOverhaulDB.threatPerSpell = {}
              OB.threatPerSpell = EquadisClassicOverhaulDB.threatPerSpell
              Say("forgot every measured threat figure.")
          end },

        --[[ The percentage was the one column with no switch, because it is the
             reading the window exists for. It is still that, and it is still a
             column -- and a page where two of three are yours to turn off and
             the third is not explains itself worse than one where all three
             are. ]]--
        { "Percent Of Tank", "showPercent", "boolean" },
    },

    --[[ Nothing from the client is required. The packet arrives on the addon
         channel, which every 1.12 client has, and a server that does not send
         one is a *server* the module cannot work with rather than a missing
         API. That is reported by the self test, not by a load gate. ]]--
    requires = { "UnitName" },

    --[[ The combat log events are here so the meter can see what *you* did
         between two packets, which is the whole of the threat-per-ability
         measurement. They are the parser's own list rather than a second copy:
         a list that drifted would attribute threat to the wrong abilities and
         look like it was working. ]]--
    --[[ **The window is only drawn when something marks it dirty**, and three
         of the things that decide whether it is on screen at all were not on
         this list.

         `OnDraw` hides the window when you are solo and `showSolo` is off, and
         again when `hideOutOfCombat` is on and you are not fighting. Both are
         states that *end* -- you join a group, you pull -- and neither ending
         was an event this module heard. So the window hid itself once and
         stayed hidden: nothing asked for another draw until a threat packet
         arrived, and solo no packet ever arrives. That is the whole of "the
         threat meter is not showing up".

         `PLAYER_REGEN_DISABLED` is combat starting. The two roster events are
         the answer to `Solo()` changing. None of them carry threat data; they
         exist so the window is redrawn when the reason it was hidden stops
         being true. ]]--
    events = { "CHAT_MSG_ADDON", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
               "PLAYER_REGEN_DISABLED",
               "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE" },

    --[[ Ticked so the request below can be sent on a clock. The window itself
         redraws on the packet, not on the tick. ]]--
    tickly = true,
})

--[[ The parser's own event list, appended rather than copied. A second list
     would drift, and a drifted list here attributes threat to the wrong
     abilities while looking exactly like it is working. ]]--
if OB.CombatLogEvents then
    local combat = OB.CombatLogEvents()

    for i = 1, table.getn(combat) do
        table.insert(M.events, combat[i])
    end
end

function M:Config()
    return OB.profile.modules.threat
end

-- ---------------------------------------------------------------------------
-- measuring what an ability costs
-- ---------------------------------------------------------------------------

--[[ **What you did since the last packet.**

     One event is a clean sample; two or more is a window that teaches nothing.
     Rather than count them and check the count later, the second event poisons
     the window outright -- so what is carried between packets is a spell name or
     the fact that it is now ambiguous, not a list.

     Only your own outgoing lines. Somebody else's damage does not move your
     threat, and a heal you receive does not either. ]]--
function M:NoteAction(line)
    if not line then return end
    if line.source ~= UnitName("player") then return end

    --[[ **`spell`, not `attack`.** `OB.ReadCombatLine` returns
         `{ source, spell, target, amount, school, kind }` and has never
         returned an `attack` field -- the damage meter, which reads the same
         table, has always read `spell`.

         So this was nil on every line, the guard below returned on every line,
         and nothing was ever noted. The window that attributes a threat change
         to the ability that caused it was closed before it opened, which is why
         the meter could show threat moving and never say what moved it. It did
         not error, because a nil field is not a fault -- it is just a name
         nobody wrote. ]]--
    local spell = line.spell
    if not spell or spell == "" then return end

    if self.windowSpell == nil then
        self.windowSpell = spell
        return
    end

    --[[ **The same ability twice is still one ability.** A rogue's off-hand
         lands beside the main hand constantly and both are "Auto Hit"; throwing
         that window away would discard most of the auto-attack samples for no
         reason -- what the window teaches is unambiguous, it is simply worth
         twice as much.

         Counted, so the amount can be divided by it. ]]--
    if self.windowSpell == spell then
        self.windowCount = (self.windowCount or 1) + 1
        return
    end

    self.windowSpell = false
end

--[[ **What everything you do costs, most expensive first.**

     Sorted by threat rather than alphabetically, because the question this
     answers is "what do I stop doing", and the answer is at the top.

     **The sample count is printed beside every figure and is not decoration.**
     One sample is an anecdote; thirty is a measurement. A list that showed both
     the same way would invite somebody to rebuild a rotation around one lucky
     window, which is a worse outcome than not having the list. ]]--
function M:PrintSpellThreat()
    local rows = {}

    for spell in pairs(OB.threatPerSpell or {}) do
        local average, samples = OB.ThreatFor(spell)
        if average then
            table.insert(rows, { spell = spell, threat = average, samples = samples })
        end
    end

    if table.getn(rows) == 0 then
        Say("nothing measured yet. Threat per ability is worked out from "
                .. "your own packets during a fight -- go and hit something.")
        return
    end

    table.sort(rows, function(a, b) return a.threat > b.threat end)

    Say("threat per use, measured from " .. table.getn(rows) .. " abilities:")

    for i = 1, table.getn(rows) do
        local row = rows[i]

        --[[ Said out loud rather than left to the reader. A figure from three
             windows and a figure from three hundred are different kinds of
             thing, and the word is shorter than the explanation. ]]--
        local confidence = "  (" .. row.samples .. " samples)"
        if row.samples < 5 then confidence = "  (" .. row.samples .. " -- rough)" end

        OB.Raw("  " .. row.spell .. ": "
                .. (row.threat >= 0 and "+" or "-")
                .. OB.ShortNumber(math.abs(row.threat)) .. confidence)
    end
end

--[[ Close the window: attribute the change if it was clean, then start again. ]]--
function M:CloseWindow(change)
    local spell, count = self.windowSpell, self.windowCount or 1

    self.windowSpell = nil
    self.windowCount = nil

    if not spell or not change then return false end

    --[[ Divided by how many times it happened, so a window with two auto-attacks
         in it teaches what one auto-attack is worth. ]]--
    return OB.LearnThreatFor(spell, change / count)
end

--[[ **There was a second `M:OnBind` further down this file**, and Lua does not
     warn about that: the later definition simply replaced this one, so
     everything here had never run since the day it was written. The window
     builder further down is the one that survived; `seenPacket` is folded into
     it, and this is left as the note explaining why it is set there rather than
     here. ]]--

--[[ **Threat per second, measured between packets.**

     The packet carries a running total and nothing else, so a rate has to be a
     difference: this total less the last one, over the time between them. That
     makes it the only figure in this window the server does not supply, and the
     only one that can be wrong -- so it is computed here, once, where the two
     packets meet, rather than in the painter where it would be recomputed on
     every redraw against a clock that has moved on.

     The first packet after a reset has nothing to subtract from and no rate.
     Zero would be a claim; nil is the truth, and the painter prints nothing.

     A name that was not in the previous packet -- somebody who just joined the
     fight -- is in the same position, and gets the same answer. ]]--
function M:MeasureRate(entries, now)
    local last, at = self.lastThreat, self.lastPacketAt
    local span = at and (now - at) or 0

    if last and span > 0 then
        for name, entry in pairs(entries) do
            local was = last[name]

            --[[ **A change, with its sign kept.**

                 This was a rate -- threat per second -- and rises only, because
                 a negative rate reads as nonsense. But dropping the falls threw
                 away the half that matters: a Feint, a Fade, a threat wipe or a
                 death are exactly the moments you want to see, and a rate that
                 silently held its last value through them was reporting the
                 past as the present.

                 So it is the difference since the last packet, signed. `-4.2k`
                 is a Feint landing and it is legible at a glance; there is no
                 rate that says that. ]]--
            if was then entry.change = entry.threat - was end
        end
    end

    self.lastThreat = {}
    for name, entry in pairs(entries) do self.lastThreat[name] = entry.threat end
    self.lastPacketAt = now
end

--[[ **Ask for the packet. Nothing sends one unprompted.**

     This is why the window said "no threat data from the server" forever: the
     module registered CHAT_MSG_ADDON and waited, and the broadcast it was
     waiting for is a *reply*. Equadis' Threat Meter sends
     `SendAddonMessage("TWT_UDTSv4", "limit=N", "RAID")` and the server answers
     with the TWTv4 packet -- the request half of the protocol was documented in
     HANDOFF and never ported, so the reader was listening to a channel nobody
     had been asked to speak on.

     `limit` is the row count, because there is no point being sent forty
     entries to draw ten of them.

     Party or raid, whichever you are in, and neither when you are in neither:
     there is no group to answer, and a message sent to an empty channel is an
     error in some clients and noise in the rest. ]]--
local REQUEST_PREFIX = "TWT_UDTSv4"

function M:Request()
    if not SendAddonMessage then return false end

    local channel = nil
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        channel = "RAID"
    elseif GetNumPartyMembers and GetNumPartyMembers() > 0 then
        channel = "PARTY"
    end

    if not channel then return false end

    SendAddonMessage(REQUEST_PREFIX,
            "limit=" .. (self:Config().rows or 10), channel)

    return true
end

--[[ How often to ask. The reply is one small message to your own group, so the
     cost is the request itself -- and the readout is worth nothing if it is
     describing the pull as it was three seconds ago.

     Yours to set, which it can be *because* we are the ones asking. While the
     module only listened, a rate slider could have thrown packets away and
     nothing else; now it decides how often they arrive. ]]--
function M:RequestStep()
    return 1 / OB.Clamp(self:Config().updateRate or 2, 1, 10)
end

function M:OnUpdate(now)
    if self.nextRequest and now < self.nextRequest then return end
    self.nextRequest = now + self:RequestStep()

    --[[ Only while it is worth asking. Out of combat there is no threat to
         report, and asking anyway is a message a second for a window showing
         the last pull. ]]--
    if OB.inCombat or OB.testMode then self:Request() end
end

--[[ Empty the list, and the rate's memory with it.

     `lastThreat` is what a threat-per-second is measured against, so leaving it
     behind would have the first packet of the next pull subtract from the last
     packet of the previous one -- across however long you spent walking between
     them. That is not a slightly wrong rate; it is an arbitrary one. ]]--
--[[ **How much threat you can still gain before you pull.**

     The tank's threat times your own pull multiplier, less what you already
     have. That is the number the window exists to convey and the only one that
     is directly actionable: percentages tell you where you stand, this tells you
     how much room is left.

     nil when there is no tank or no entry for you -- there is no headroom to
     report, and zero would read as "stop attacking now" rather than as "no
     idea". Floored at zero once you are past it, because a negative headroom is
     just aggro, and the rest of the window already says so. ]]--
function OB.ThreatUntilPull(mine, tank)
    if not mine or not tank then return nil end

    local at = tank.threat * (OB.ThreatPullAt(mine.melee) / 100)
    local left = at - mine.threat

    if left < 0 then return 0 end
    return left
end

function M:Forget()
    self.entries = {}
    self.lastThreat = nil
    self.lastPacketAt = nil

    OB.SetDirty(self)
end

function M:OnEvent()
    if event == "PLAYER_ENTERING_WORLD" then
        --[[ Cleared rather than kept. Threat does not survive a loading screen
             and the packet will arrive again within a second of combat; showing
             the previous zone's raid until then would be a confident lie. ]]--
        self:Forget()
        return
    end

    --[[ **The fight is over, and optionally so is the list.**

         Off by default, because leaving combat is exactly when the meter gets
         read -- who pulled, who was climbing -- and a window that empties itself
         the instant the boss dies answers the question a second too late. On for
         anyone who would rather see nothing between pulls than a fight that has
         already happened. ]]--
    if event == "PLAYER_REGEN_ENABLED" then
        if self:Config().clearOutOfCombat then self:Forget() end

        --[[ Marked dirty even when the list is kept, because `hideOutOfCombat`
             decides visibility from combat state and leaving combat is exactly
             when that answer changes. `Forget` marks it too; doing it twice
             costs a flag. ]]--
        OB.SetDirty(self)
        return
    end

    --[[ Combat starting, and the group changing, carry no threat data. They are
         here because they are the two ways the window stops being hidden --
         see the event list above. ]]--
    if event == "PLAYER_REGEN_DISABLED"
            or event == "PARTY_MEMBERS_CHANGED"
            or event == "RAID_ROSTER_UPDATE" then
        OB.SetDirty(self)
        return
    end

    --[[ A combat log line: note what you did, so the next packet knows what to
         attribute its change to. Not a packet, so nothing below runs. ]]--
    if event ~= "CHAT_MSG_ADDON" then
        if OB.ReadCombatLine then self:NoteAction(OB.ReadCombatLine(event, arg1)) end
        return
    end

    --[[ Every addon on the channel arrives here, so the prefix check is the
         filter and the parse is the only thing that decides. A message that is
         not a threat packet leaves the table exactly as it was. ]]--
    local entries = OB.ParseThreatPacket(arg2 or arg1)
    if not entries then return end

    self:MeasureRate(entries, GetTime())

    --[[ **The window closes on the packet**, because the packet is what says how
         much the threat moved. Your own change, since only your own actions were
         being watched. ]]--
    local mine = entries[UnitName("player")]
    self:CloseWindow(mine and mine.change)

    self.entries = entries
    self.seenPacket = true
    OB.SetDirty(self)
end

-- ---------------------------------------------------------------------------
-- preview
-- ---------------------------------------------------------------------------

--[[ A plausible pull, so the colours can be set without waiting for a boss.

     The player is put just under a rip, because that is the reading the window
     exists for and the one whose colour is worth choosing carefully. ]]--
local PREVIEW = {
    { "Warrior", true, 12000, 100, "WARRIOR" },
    { "Rogue", false, 12400, 103, "ROGUE" },
    { "Mage", false, 9600, 80, "MAGE" },
    { "Hunter", false, 7200, 60, "HUNTER" },
    { "Priest", false, 2400, 20, "PRIEST" },
}

function M:TestStart(now)
    self.liveEntries = self.entries
    self.previewAt = nil
    self:SeedPreview()
end

--[[ Re-seeded every second, so the rows actually move.

     A still preview shows the colours and hides everything the window is for --
     whether a row climbing past the tank is readable, whether the ramp reaches
     its pull colour in time to be useful. Those only appear in motion. ]]--
function M:SeedPreview()
    self.entries = {}

    local me = UnitName("player")

    for i = 1, table.getn(PREVIEW) do
        local row = PREVIEW[i]
        local name = row[1]

        --[[ One row is the player, so the ramp that colours *your* row is what
           the preview actually shows. Second, because that is where somebody
           about to pull sits. ]]--
        if i == 2 then name = me end

        --[[ The class is asserted, because a preview row is in no group and the
             roster can never answer for it. Without this every row came back
             classless and the preview showed the fallback five times over.

             **Except your own row, which keeps your own class.** The stand-in
             entry is the second one, whose preview class is Rogue -- so a mage
             looking at the preview saw their row in a rogue's yellow and read it
             as class colouring being broken. It was: for them. The one row a
             player can check against something they know has to be right. ]]--
        if name == me then
            OB.classHint[name] = OB.class
        else
            OB.classHint[name] = row[5]
        end

        -- +/- 15%, enough to reshuffle the order without ever unseating the tank
        local jitter = 0.85 + (math.random() * 0.3)

        self.entries[name] = {
            name = name, tank = row[2],
            threat = math.floor(row[3] * jitter),
            percent = math.floor(row[4] * jitter),
            melee = true,

            --[[ A change, because the preview has to exercise the column it is
                 previewing. This is a difference between two packets, and a
                 preview has no packets -- so left alone the column was empty
                 exactly when somebody turned it on to look at it.

                 **Signed, and the sign alternates**, because the whole reason
                 this stopped being a rate is that falls matter. A preview that
                 only ever showed `+` would leave the half worth seeing
                 untested by the only person who ever looks at a preview. ]]--
            change = math.floor((row[3] * jitter) / 12)
                    * (mod(i, 3) == 0 and -1 or 1),
        }
    end

    OB.SetDirty(self)
end

local PREVIEW_STEP = 1

function M:TestStep(now)
    if not self.previewAt then self.previewAt = now end
    if (now - self.previewAt) < PREVIEW_STEP then return end

    self.previewAt = now
    self:SeedPreview()
end

--[[ The real packet comes back untouched: a preview that overwrote it would
     cost somebody the pull they were reading. ]]--
function M:TestStop()
    --[[ Restored unconditionally, and to an empty table when there was nothing
         live to put back.

         Guarded on `if self.liveEntries` it was possible for the preview rows to
         simply stay: anything that left liveEntries nil -- a preview started
         before the first packet, a second TestStart -- meant TestStop had
         nothing to restore and quietly restored nothing, leaving five invented
         raiders on screen until the next packet arrived. Which, solo, is
         never. ]]--
    self.entries = self.liveEntries or {}
    self.liveEntries = nil
    self.previewAt = nil

    --[[ Cleared, or a real player who happens to be called Mage keeps the
         preview's class for the rest of the session. ]]--
    OB.classHint = {}

    OB.SetDirty(self)
end

--[==[ **Your own threat as a colour, for anything that wants to show it.**

     The nameplate's health bar asks for this. It could have had a ramp of its
     own -- the maths is four lines -- and then there would be two answers to
     "what does about to pull look like", drifting apart the first time either
     palette was touched. The meter owns the colours and this hands them out.

     **Nil when there is no reading**, which is most of the time: threat comes
     off the addon channel and there is nothing to say solo, out of combat, or
     with the meter switched off. A caller that gets nil is expected to fall
     back to whatever it drew before rather than to draw "safe" -- green for "no
     data" is a claim, and the wrong one.

     `rampFraction` is defined further down this file, so this is a method
     rather than a local: it is resolved when called, not when loaded. ]==]
function OB.MyThreatColor()
    local m = OB.modules and OB.modules.threat
    if not m or not OB.ModuleEnabled("threat") then return nil end

    local mine = m:Mine()
    if not mine or not mine.percent then return nil end

    return m:OwnRampColor(mine)
end

--[==[ **How close the next person is to taking it off you**, as a fraction of
     your own threat -- the tank's reading, where `MyThreatColor` above is the
     damage dealer's.

     A damage dealer wants to know how close *they* are to the tank. A tank wants
     the opposite: how close the closest *other* person is to them. Same packet,
     opposite question, and the nameplates ask this one when they are told the
     player is tanking.

     Raw threat rather than the packet's percent, because the percent is measured
     against whoever the server calls the tank -- and if that is somebody else,
     everyone's number is relative to the wrong person. Two raw totals divide
     into a ratio that means the same thing whoever the server thinks is in
     charge.

     **Nil when there is nothing to read**, for the reason `MyThreatColor` gives:
     solo, out of combat or with the meter off there is no packet, and a caller
     is expected to fall back rather than draw "safe". Nil too when you have no
     threat of your own -- there is no fraction of nought, and "holding" a mob you
     have not touched is not a state anybody wants painted. ]==]
function OB.RunnerUpThreatRatio()
    local m = OB.modules and OB.modules.threat
    if not m or not OB.ModuleEnabled("threat") then return nil end

    local mine = m:Mine()
    if not mine or not mine.threat or mine.threat <= 0 then return nil end

    local highest = 0

    for name, entry in pairs(m.entries or {}) do
        if name ~= mine.name and type(entry.threat) == "number"
                and entry.threat > highest then
            highest = entry.threat
        end
    end

    return highest / mine.threat
end

--[[ This player's own entry, which is what every reading is relative to. ]]--
function M:Mine()
    local name = UnitName("player")
    if not name or not self.entries then return nil end
    return self.entries[name]
end

--[[ A player's class, from the group roster.

     **The packet does not carry it**, so it is looked up rather than parsed --
     which means it is only available for people actually in your raid or party.
     A relayed name from outside the group resolves to nothing and falls back to
     the threat ramp, which is the honest outcome: a class colour invented for
     somebody the client has never seen would be a guess wearing the same paint
     as a fact.

     Walked rather than cached because a raid reshuffles and a cache would need
     invalidating on four events to be worth the trouble; this runs once per
     drawn row, and a raid is forty entries. ]]--
--[[ Classes the previews have asserted, checked before the roster.

     A preview's rows are not in anybody's group -- they cannot be, there is no
     group -- so every one of them used to come back nil and fall through to
     whatever the no-class path did. That is the bug behind *both* "color rows by
     class isn't working" and "the pull gradient is applying to all bars": the
     preview was exercising the fallback and never once the class path, which is
     the one thing a colour preview exists to show. ]]--
OB.classHint = {}

function OB.GroupClass(name)
    if not name then return nil end
    if OB.classHint[name] then return OB.classHint[name] end

    local count = GetNumRaidMembers and GetNumRaidMembers() or 0
    local prefix = "raid"

    if count == 0 then
        count = GetNumPartyMembers and GetNumPartyMembers() or 0
        prefix = "party"
    end

    for i = 1, count do
        local unit = prefix .. i
        if UnitName(unit) == name then
            local _, class = UnitClass(unit)
            return class
        end
    end

    if UnitName("player") == name then return OB.class end
    return nil
end

-- ---------------------------------------------------------------------------
-- ordering
-- ---------------------------------------------------------------------------

--[[ Highest threat first, which is the order the question is asked in: who has
     aggro, then who is closest to taking it.

     Sorted by **percent** rather than raw threat. The two agree while everyone
     is on one target and disagree the moment somebody is not, and percent is
     the one the readout is about -- it is already relative to the tank, which
     is what "am I about to pull" means.

     Name breaks a tie, so the list does not shuffle between identical readings.
     Two players on exactly equal threat is common at a pull, and a list that
     reorders itself every packet is unreadable. ]]--
function OB.SortThreat(entries)
    local list = {}
    if not entries then return list end

    for name, entry in pairs(entries) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        if a.percent == b.percent then return a.name < b.name end
        return a.percent > b.percent
    end)

    return list
end

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

--[[ How close to pulling counts as "about to". The ramp runs from nothing to
     this, so a melee player at 110% of the tank is at the red end and the
     colour has said so for a while by the time they get there. ]]--
local function rampFraction(entry, mine)
    local pullAt = OB.ThreatPullAt(mine and mine.melee)
    if pullAt <= 0 then return 0 end

    local fraction = entry.percent / pullAt
    if fraction > 1 then fraction = 1 end
    return fraction
end

--[[ A row's colour.

     The ramp is *inverted* against the health bar's: there, full is good and the
     ramp runs low-to-full; here, high threat is bad, so the "full" anchor is the
     pull colour and safe is the low end. Same OB.Ramp, opposite direction. ]]--
--[[ **Three colours, in one order: bar, then class, then your own pull.**

     The bar colour is what a row is unless something knows better. Class colour
     knows better, because it is how you find a name in a list. Your own threat
     ramp knows better still, because it is the reading the window exists for.

     The order is the whole of the rule, and the mistake it replaces is worth
     recording: the fallback used to be the *ramp*, so any row whose class could
     not be resolved -- a preview, a pet, anybody outside the group -- came out
     coloured as though it were about to pull. That read as "the gradient is
     applying to all bars", which it was, and it hid the class path completely.

     A fallback must be the dullest of the options, never the loudest. ]]--
--[[ Your own row's colour, which is the reading the whole window exists for.
     Pulled out of `RowColor` so the nameplate can ask for the same thing
     without going through a row it does not have. ]]--
function M:OwnRampColor(mine)
    local cfg = self:Config()
    return OB.Ramp(cfg.safeColor, cfg.closeColor, cfg.pullColor,
            rampFraction(mine, mine))
end

function M:RowColor(entry, mine)
    local cfg = self:Config()

    if cfg.rampOwnRow and mine and entry.name == mine.name then
        return OB.Ramp(cfg.safeColor, cfg.closeColor, cfg.pullColor,
                rampFraction(entry, mine))
    end

    if cfg.classColor then
        local class = OB.GroupClass(entry.name)
        if class then
            local r, g, b = OB.ClassColor(class)
            return { r, g, b, 1 }
        end
    end

    return cfg.barColor
end

--[[ Threat as a short number: 12.3k rather than 12345.

     Four digits of threat is noise on a sixteen pixel row, and the digit that
     matters is the leading one. Thousands only -- vanilla threat does not reach
     millions in a fight anyone is reading a meter during. ]]--
function OB.ShortNumber(n)
    if not n then return "" end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(OB.Round(n))
end

local HEADER_H = OB.HEADER_H

function M:OnBind()
    --[[ Cleared so switching the subsystem on again explains the solo hide
         again, rather than only ever doing it once per install. ]]--
    self.saidSolo = nil

    self.entries = self.entries or {}
    self.rows = self.rows or {}

    --[[ Whether a packet has been seen *this* session. Kept here because this
         is the `OnBind` that actually runs -- an earlier one further up the
         file set it and was silently replaced by this definition. ]]--
    if self.seenPacket == nil then self.seenPacket = false end

    if not self.frame then
        local f = CreateFrame("Frame", "EqOBThreat", UIParent)
        f:SetFrameStrata("MEDIUM")
        f:SetMovable(true)

        --[[ Deliberately not SetClampedToScreen -- see modules/damage.lua for
             what it did to two windows on an ultrawide. ]]--
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")

        --[[ Dragging writes the position straight back to the profile, so the
             window is where you left it without a separate save step. The lock
             is checked at drag time rather than by unregistering, so toggling it
             does not have to rebuild the frame. ]]--
        f:SetScript("OnDragStart", function()
            if OB.profile.modules.threat.locked then return end
            this:StartMoving()
        end)

        f:SetScript("OnDragStop", function()
            OB.modules.threat:StorePosition(this)
        end)

        --[[ **The header.** Three buttons rather than the damage meter's seven,
             because four of those answer questions this window does not have:
             there is one segment (now), one statistic (threat), one window, and
             nothing to reset -- the packet rebuilds the list whole every time it
             arrives, so "clear it" lasts until the next one.

             What is left is what both meters share: open my settings, lock me,
             paste me into chat. Same order, same art, same place. ]]--
        local head = CreateFrame("Frame", nil, f)
        head:SetHeight(HEADER_H)
        head:EnableMouse(true)
        head:RegisterForDrag("LeftButton")
        f.head = head

        --[[ The header has to carry the drag itself: it is a child with the
             mouse enabled, so it swallows the press before the window under it
             sees one, and the strip everybody grabs would otherwise be dead. ]]--
        head:SetScript("OnDragStart", function()
            if OB.profile.modules.threat.locked then return end
            this:GetParent():StartMoving()
        end)

        head:SetScript("OnDragStop", function()
            OB.modules.threat:StorePosition(this:GetParent())
        end)

        head.bg = head:CreateTexture(nil, "BACKGROUND")
        head.bg:SetAllPoints(head)

        --[[ One surface under every row, so a gap between two of them shows the
             window rather than whatever is behind it. See OnStyle. ]]--
        f.body = f:CreateTexture(nil, "BACKGROUND")

        head.title = OB.NewText(head, "OVERLAY", "GameFontNormalSmall")
        head.title:SetPoint("CENTER", head, "CENTER", 0, 0)
        head.title:SetJustifyH("CENTER")
        head.title:SetText("Threat")
        head.title:SetTextColor(1, 1, 1)

        head.settings = OB.IconButton(head, "settings")
        head.lock = OB.IconButton(head, "unlock")

        --[[ The line that stands in for the rows when there are none, so the
             window is a thing that is waiting rather than a thing that broke. ]]--
        --[[ **The headline bar, above the list.**

             A row of its own rather than a marker on somebody else's, because
             it is not about a player -- it is about the gap between two of them,
             and hanging that off either one would put it in a place that moves
             when the list re-sorts. Pinned at the top, it is where the eye
             already goes.

             Built here with the rest of the chrome so it exists whether or not
             it is switched on; the draw decides. ]]--
        f.pull = OB.CreateBar("EqOBThreatPull", f)
        f.pull:EnableMouse(false)

        f.empty = OB.NewText(f, "OVERLAY", "GameFontDisableSmall")
        f.empty:SetPoint("TOP", f, "TOP", 0, -(HEADER_H + 8))
        f.empty:SetJustifyH("CENTER")

        head.settings:SetScript("OnClick", function()
            OB.OpenPanelAt("Threat Meter")
        end)

        head.lock:SetScript("OnClick", function()
            local cfg = OB.profile.modules.threat
            cfg.locked = not cfg.locked

            OB.modules.threat:OnStyle()
            OB.RefreshPanel()
        end)

        self.frame = f
    end

    self:OnStyle()
end

--[[ Where a dropped window landed. Centre, not left edge -- the window is
     anchored by its centre, so storing the left edge's offset moves it half its
     own width on every drop until it walks off the screen -- and then bounded to
     the screen against its own size, so it cannot be dragged somewhere it cannot
     be dragged back from. ]]--
function M:StorePosition(frame)
    frame:StopMovingOrSizing()

    local cfg = self:Config()
    local scale = self:Scale()

    --[[ A frame the client cannot give edges for keeps the position it had. That
         happens to one that has never been laid out, and inventing a coordinate
         from a nil edge would move the window somewhere nobody asked for. ]]--
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then return end

    local x = OB.Round((left + (frame:GetWidth() / 2))
            - ((GetScreenWidth() / 2) / scale))
    local y = OB.Round((bottom + (frame:GetHeight() / 2))
            - ((GetScreenHeight() / 2) / scale))

    x = OB.ClampWindowCoord("x", x, frame:GetWidth(), scale)
    y = OB.ClampWindowCoord("y", y, frame:GetHeight(), scale)

    --[[ Pushed clear of any window already down, then bounded again: avoiding
         one can walk it into the edge, and the screen wins. ]]--
    x, y = OB.AvoidWindows("threat", x, y,
            frame:GetWidth(), frame:GetHeight(), scale)

    cfg.x = OB.ClampWindowCoord("x", x, frame:GetWidth(), scale)
    cfg.y = OB.ClampWindowCoord("y", y, frame:GetHeight(), scale)

    self:OnStyle()
    OB.RefreshPanel()
end

function M:Scale()
    local scale = OB.profile and OB.profile.scale or 1
    if scale <= 0 then return 1 end
    return scale
end

function M:OnScale(scale)
    if self.frame then self.frame:SetScale(scale) end
end

--[[ Grow or shrink the row pool to the configured count.

     Rows are built once and reused, never destroyed -- the same rule the bars
     follow. A window shrunk from twenty rows to five and back must not leak
     fifteen frames each time. ]]--
function M:EnsureRows(count)
    for i = table.getn(self.rows) + 1, count do
        local row = OB.CreateBar("EqOBThreatRow" .. i, self.frame)
        row:EnableMouse(false)
        self.rows[i] = row
    end
end

--[[ Rows are spaced by more than their own height, and inset by the border's
     width on both sides.

     Same bug RogueBars had: a border is art drawn *outside* the bar, so rows
     packed edge to edge overlap by twice the pad however carefully their heights
     line up, and the outermost ones hang over the window's edge. The spacing has
     to come from the same BorderPad the styling uses or the two disagree.

     And **exactly** the pad, with nothing added on top. A spare pixel per row is
     invisible against a border and is a stripe of window background between
     every pair of rows when the border is off, which is the gap that got
     reported. With no border the step is the height and the rows touch. ]]--
function M:RowStep(cfg)
    return cfg.rowHeight + (OB.BorderPad("threat") * 2) + (cfg.gap or 0)
end

function M:OnStyle()
    local cfg = self:Config()
    if not self.frame then return end

    self:EnsureRows(cfg.rows)

    local pad = OB.BorderPad("threat")
    local step = self:RowStep(cfg)

    self.frame:SetWidth(cfg.width)
    --[[ The headline bar takes a row's worth of space above the list when it is
         on, so the window is a row taller and every row starts a step lower. ]]--
    local lead = cfg.showUntilPull and step or 0

    self.frame:SetHeight(HEADER_H + lead + (step * cfg.rows) + (pad * 2))
    self.frame:SetScale(self:Scale())
    self.frame:ClearAllPoints()

    --[[ Bounded before it is placed, not only when it is dropped. A window saved
         at one resolution and opened at another is otherwise off screen with no
         way back except a slider nobody would guess is the cause. ]]--
    -- Drawing never moves a window; see modules/damage.lua for the three
    -- mechanisms that were caught doing it.

    self.frame:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)

    --[[ Published so other windows know to keep off. Written on every style
         pass, because a window that grew is a window that may now overlap. ]]--
    OB.RegisterWindowRect("threat", cfg.x, cfg.y,
            cfg.width, self.frame:GetHeight())

    local head = self.frame.head
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, 0)

    local hc = cfg.headerColor
    head.bg:SetTexture(hc[1], hc[2], hc[3], hc[4] or 1)

    local order = { head.lock, head.settings }
    local hx = 2

    for i = 1, table.getn(order) do
        order[i]:ClearAllPoints()
        order[i]:SetPoint("LEFT", head, "LEFT", hx, 0)
        hx = hx + order[i]:GetWidth() + 2
    end

    --[[ The padlock shows the state it is *in*, not the state clicking reaches.
         Both readings are equally plausible and half of everyone guesses. ]]--
    head.lock:SetIcon(cfg.locked and "lock" or "unlock")

    --[[ Styled through the same StyleBar the cluster uses, against a synthetic
         slot. That is what makes the meter share the HUD's texture, border and
         font rather than having its own idea of them -- which is the entire
         premise of the addon and the thing five separate addons cannot do.

         **No textSize.** It used to be `rowHeight - 5`, which tied the text to
         the bar's size and left this subsystem's own Font Size slider doing
         nothing -- dragging the height resized the text and the control meant
         to resize the text did not. Leaving it out is what hands the decision
         back to OB.Look's fontSize. ]]--
    local body = cfg.bg
    self.frame.body:SetTexture(body[1], body[2], body[3], body[4] or 0.6)
    self.frame.body:ClearAllPoints()
    --[[ Anchored here, sized in FitBackground: how tall it should be depends on
         how many rows there are to sit on it, which the draw pass knows and the
         style pass does not. ]]--
    self.frame.body:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -HEADER_H)
    self.frame.body:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -HEADER_H)

    local slot = {
        w = cfg.width - (pad * 2), h = cfg.rowHeight,
        bg = { 0, 0, 0, 0 },
    }

    --[[ Styled from the same slot as a row, so the headline cannot drift out of
         step with the list it heads: same texture, same border, same height. ]]--
    OB.StyleBar(self.frame.pull, slot, nil, "threat")
    self.frame.pull:ClearAllPoints()
    self.frame.pull:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
            pad, -(HEADER_H + pad))

    for i = 1, table.getn(self.rows) do
        local row = self.rows[i]
        OB.StyleBar(row, slot, nil, "threat")

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.frame, "TOPLEFT",
                pad, -(HEADER_H + lead + pad + ((i - 1) * step)))
    end
end

--[[ Why the window is empty, in the fewest words that are actually useful.

     Three different reasons, and telling them apart is the whole value: solo is
     nothing to fix, in a group with no packet is a server that does not send
     one, and out of combat is simply waiting. Saying "no data" to all three
     would send somebody looking for a setting in the first and third cases. ]]--
--[[ **Alone, on a server that broadcasts threat to your group.**

     There is no group, so there is no broadcast, so there is nothing this window
     can ever say. That is not "no data yet" -- it is a state in which the meter
     is structurally incapable of having any. ]]--
function M:Solo()
    local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0

    return raid == 0 and party == 0
end

function M:EmptyReason()
    if self:Solo() then return "no threat solo" end
    if not self.seenPacket then return "no threat data from the server" end
    return "waiting for a pull"
end

--[[ **Edit mode borrows the lock and gives it back.**

     This window has its own `locked`, which is what somebody uses to stop
     nudging it once it is placed. Edit mode says *everything moves*, and a
     window that is outlined like all the others and then refuses to be dragged
     is the same non-answer the map used to give.

     So the lock is overridden while edit mode is on and **restored when it goes
     off**, not cleared -- somebody who locked this deliberately still has it
     locked afterwards. The same bargain the damage meter's windows make. ]]--
function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("threat") then
        Say("switch the threat meter on first.")
        return false
    end

    local cfg = self:Config()
    if not cfg then return false end

    if on then
        --[[ Remembered once, so toggling edit mode twice does not record the
             borrowed state as if it were the real one. ]]--
        if self.lockedBeforeEdit == nil then
            self.lockedBeforeEdit = cfg.locked and true or false
        end

        cfg.locked = false

        if self.frame then OB.MarkMovable(self.frame, "Threat Meter") end

        return true
    end

    if self.lockedBeforeEdit ~= nil then
        cfg.locked = self.lockedBeforeEdit
        self.lockedBeforeEdit = nil
    end

    return true
end

--[[ **Back to the middle of the screen with every setting as it shipped.**

     The way out of a window nobody can find. A meter dragged off the edge, or
     carried over from a larger resolution, is saved at coordinates that are
     nowhere on this screen -- and from the inside that is indistinguishable
     from a meter that does not work, which is how it gets reported.

     Position first and separately, because that is the half that matters: a
     window at the centre can be seen, and whatever else is wrong with it can
     then be seen too.

     Every setting with it, because the other way to hide this window is a
     switch -- Show When Solo off while solo, Hide Out Of Combat on out of
     combat -- and somebody who cannot find the window cannot find which switch
     did it either. ]]--
function M:ResetEverything()
    local cfg = self:Config()
    local defaults = (OB.modules.threat and OB.modules.threat.defaults) or {}

    --[[ Wiped rather than overwritten key by key: a setting added since this
         profile was made has no default to copy over it, and would survive a
         reset that claimed to have cleared everything. ]]--
    for key in pairs(cfg) do cfg[key] = nil end

    OB.DeepMerge(cfg, OB.DeepCopy(defaults))

    --[[ Dead centre, which is the one place on screen that exists at every
         resolution. Set after the defaults are back so it wins even if the
         shipped position is not the middle. ]]--
    cfg.x = 0
    cfg.y = 0

    --[[ And visible: the subsystem's own Show tick is stored outside the
         module's settings, so clearing those would leave a meter that is reset,
         centred and still switched off. ]]--
    if OB.profile and OB.profile.modulesShown then
        OB.profile.modulesShown.threat = nil
    end

    self.saidSolo = nil

    if self.frame then
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        self.frame:Show()
    end

    self:OnStyle()

    Say("threat meter reset -- centre of the screen, every setting as it "
            .. "shipped.")

    return true
end

function M:OnDraw()
    local cfg = self:Config()
    if not self.frame then return end

    self:EnsureRows(cfg.rows)

    local list = OB.SortThreat(self.entries)
    local mine = self:Mine()

    --[[ **Solo, the window is gone rather than empty -- and that is off by
         default.**

         This is the one exception to "no data is a state, not an absence", and
         it earns it: threat is broadcast to your party or raid, so alone there
         is no channel to hear it on. The window is not waiting for data, it is
         waiting for a group. A permanent "no threat solo" sitting over the
         world while you quest is a label, not a readout.

         Every other empty state still shows itself, because those are real
         waits: in a group with no packet, or between pulls.

         Test mode overrides it. You configure this window standing alone in a
         city, and a preview that vanished exactly when somebody went looking
         for it would be the trap this setting exists to avoid. ]]--
    if self:Solo() and not cfg.showSolo and not OB.testMode then
        --[[ **Said once, because silence reads as broken.**

             Switching this subsystem on and seeing nothing is
             indistinguishable from a module that does not work. Solo, with
             `showSolo` off, that is exactly what happens: the window hides on
             the first draw and there is no group coming to un-hide it.

             The rule itself is right and stays. What was missing was anybody
             saying so. Cleared on bind, so switching it on again explains
             itself again. ]]--
        if not self.saidSolo then
            self.saidSolo = true
            Say("hidden while you are solo -- threat comes from your group. "
                    .. "Show When Solo keeps it up anyway.")
        end

        self.frame:Hide()
        return
    end

    --[[ Out of combat the window is showing the last pull. Worth reading, and
         also clutter -- so it is a choice rather than a rule. Test mode
         overrides it for the reason it overrides the solo rule: you configure
         this window standing still, which is out of combat by definition. ]]--
    if cfg.hideOutOfCombat and not OB.inCombat and not OB.testMode then
        self.frame:Hide()
        return
    end

    self.frame:Show()

    --[[ **No data is a state, not an absence.**

         This used to hide the whole window, which was wrong twice over. The
         packet only arrives in a group on a server that sends it, so solo -- or
         anywhere it does not -- the meter simply was not there, which reads as a
         subsystem that failed to load. And a hidden window cannot be dragged,
         so there was no way to place it before a raid started.

         Shown with the header and a line saying why instead. The header is the
         part you need when there is no data: it is how you move it, lock it and
         reach its settings. ]]--
    if table.getn(list) == 0 then
        for i = 1, table.getn(self.rows) do self.rows[i]:Hide() end

        self.frame.empty:Show()
        self.frame.empty:SetText(self:EmptyReason())
        return
    end

    self.frame.empty:Hide()

    --[[ Every row is scaled against the **leader**, not against a hundred. The
         window's job is comparison: a raid where nobody is near the tank should
         still show who is ahead of whom, and scaling to a fixed hundred would
         squash the whole list into the left edge. ]]--
    --[[ The **highest** percentage, not the first row's. Those were the same
         thing while the list was purely sorted; pinning your own row to the top
         separated them, and reading the scale off row one made every bar
         relative to *you* rather than to the leader. Your row would always be
         full width, which is exactly the reading the window must not give. ]]--
    local top = 0
    for i = 1, table.getn(list) do
        if list[i].percent > top then top = list[i].percent end
    end
    if top <= 0 then top = 1 end

    for i = 1, table.getn(self.rows) do
        local row = self.rows[i]
        local entry = list[i]

        if not entry then
            row:Hide()
        else
            row:Show()
            OB.SetBarFill(row, entry.percent / top, false)
            OB.SetBarColor(row, self:RowColor(entry, mine))

            --[[ **Name left, numbers together on the right** -- the same shape
                 the damage meter uses.

                 The threat figure used to sit at the middle of the row, which
                 left it stranded between the name and the percentage with a gulf
                 on both sides. Two numbers that belong to each other read as a
                 pair when they are next to each other and as three unrelated
                 columns when they are not. ]]--
            --[[ **Two numeric columns, each flush with itself.**

                 The percentage used to ride on the end of one combined string,
                 so its left edge moved with whatever preceded it -- a four digit
                 threat figure on one row and a two digit one on the next put the
                 percent signs in different places. Ragged, and it is the column
                 people read down.

                 So the figures that vary in width go in one column and the
                 percentage gets its own, aligned separately. Each lines up with
                 itself, which is the only thing alignment can mean. ]]--
            --[[ **Three columns, three font strings.**

                 The threat figure and the rate used to share one string joined
                 by a gap, which meant the rate's left edge moved with the width
                 of the figure in front of it -- a four digit threat on one row
                 and a two digit one on the next put the rates in different
                 places. That is the reported "not anchored to the left", and a
                 column has to be its own string to be a column at all. ]]--
            --[[ Held, not drawn. The name's room depends on the two number
                 columns to its right, which only AlignColumns knows. ]]--
            row.leftFull = self:RowName(cfg, i, entry)

            -- all three placed once the widest row is known; see M:AlignColumns
            row.center:SetText(cfg.showThreat
                    and OB.ShortNumber(entry.threat) or "")

            --[[ **No third figure.** The change column was removed once the
                 per-ability measurement existed: it answered "your threat moved
                 by this much" and the question underneath was always "because
                 of what", which the ability breakdown answers properly. A
                 column that raises a question it cannot answer is worse than the
                 space it occupies.

                 `entry.change` is still computed -- the measurement is built on
                 it -- it is simply not drawn. ]]--
            row.extra:SetText("")

            row.right:SetText(cfg.showPercent
                    and (OB.Round(entry.percent) .. "%") or "")
        end
    end

    self:DrawUntilPull(mine)
    self:AlignColumns()
    self:FitBackground(table.getn(list))
end

--[[ The headline: how much threat you can still gain before you rip.

     Filled by how far along you are rather than by the number itself, so the bar
     empties as you close on the tank -- a bar that grows towards danger reads as
     progress, and this is a countdown. Coloured by the same ramp your own row
     uses, so the two agree.

     Hidden when there is nothing to say: no tank, no entry for you, or the bar
     switched off. A headline with no headline is worse than none. ]]--
function M:DrawUntilPull(mine)
    local cfg = self:Config()
    local bar = self.frame.pull
    if not bar then return end

    local left = OB.ThreatUntilPull(mine, OB.ThreatTank(self.entries))

    if not cfg.showUntilPull or not left then
        bar:Hide()
        return
    end

    bar:Show()

    --[[ **How close you are to the tank**, zero through one: one means you have
         matched your own pull threshold, which is the moment the mob turns.

         **Derived from the headroom the bar is showing, not from the percentage.**
         It used to be `percent / pullAt`, which is a second route to the same
         idea -- and two routes to one idea disagree. Reported as "the top bar
         does not fill all the way": the number beside it reaches zero while the
         bar is still short, because the percentage is rounded to whole numbers
         by the sender and the headroom is not.

         One quantity now drives both. When the bar says nothing is left, it is
         full, because those are the same fact. ]]--
    local tank = OB.ThreatTank(self.entries)
    local at = tank and (tank.threat * (OB.ThreatPullAt(mine.melee) / 100))

    local closeness = 1

    if at and at > 0 then
        closeness = 1 - (left / at)
    end

    if closeness < 0 then closeness = 0 end
    if closeness > 1 then closeness = 1 end

    --[[ **Full unless asked otherwise.**

         It emptied as you closed on the tank, which read as a countdown and was
         wrong twice over: a headline is a label, and a label that shrinks is
         hard to read exactly when it matters most -- the bar was thinnest at the
         moment you most needed to see it.

         Full, it is a coloured strip carrying three numbers, and the colour does
         the work the length was trying to. Fill By Threat puts the length back
         for anyone who wants it, and in the direction people expect: it *grows*
         towards danger, so a full bar means the mob is yours. ]]--
    OB.SetBarFill(bar, cfg.fillUntilPull and closeness or 1, false)

    OB.SetBarColor(bar, OB.Ramp(cfg.safeColor, cfg.closeColor, cfg.pullColor,
            closeness))

    --[[ The same three columns the rows use, so the summary lines up with what
         it summarises: threat to go, your rate, your share of the tank's. ]]--
    bar.leftFull = "Threat Until Pull"
    bar.center:SetText(cfg.showThreat and OB.ShortNumber(left) or "")

    bar.extra:SetText("")

    bar.right:SetText(cfg.showPercent
            and (OB.Round(mine.percent or 0) .. "%") or "")

end

--[[ **The background stops where the rows stop.**

     Rows Shown is a ceiling, not a promise: a five-man party fills five rows of a
     window sized for ten, and the empty half used to sit there as a block of
     background with nothing on it. That reads as a window that failed to draw
     rather than as a group of five.

     So the body is sized to the rows actually shown, and hidden outright when
     none are -- the header stays, because that is what you move and lock the
     window by, and the empty-state line has the rest to say.

     The *frame* keeps its full height on purpose. It is what the resize grip and
     the overlap rectangle are measured from, and a window whose bounds changed
     every time somebody joined the group would be impossible to place. ]]--
function M:FitBackground(shown)
    local frame = self.frame
    if not frame or not frame.body then return end

    local lead = (self:Config().showUntilPull and self.frame.pull
            and self.frame.pull:IsShown()) and 1 or 0

    --[[ The headline sits on the background too, so it counts towards how far
         the paint reaches -- and keeps the background when it is the only thing
         there, which happens between pulls with the list already cleared. ]]--
    if (shown + lead) <= 0 then
        frame.body:Hide()
        return
    end

    local cfg = self:Config()
    local pad = OB.BorderPad("threat")

    frame.body:Show()
    frame.body:ClearAllPoints()
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_H)
    frame.body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER_H)
    --[[ Exactly the last row's bottom edge, not a whole step past it. A step
         includes the gap *after* a row, so multiplying by the count leaves a
         strip of background below the last bar -- background with no bar in
         front of it, which is the thing this is here to prevent. ]]--
    frame.body:SetHeight(((shown + lead - 1) * self:RowStep(cfg))
            + cfg.rowHeight + (pad * 2))
end

--[[ A rank and a name, or just a name. The rank answers "am I third" without
     counting rows; optional because on a five-row window counting is free. ]]--
function M:RowName(cfg, index, entry)
    if cfg.showRank then return index .. ". " .. entry.name end
    return entry.name
end

--[[ **One left edge for every row's numbers**, the same rule the damage meter
     follows and for the same reason: centring or right-aligning a column of
     numbers of different widths leaves the digits ragged down the window.

     Two passes, because the answer depends on every row and no row can know it
     alone. ]]--
function M:AlignColumns()
    --[[ The headline bar is measured and placed with the rows, so its figures
         sit in the same three columns rather than in a fourth set of its own. A
         summary that does not line up with what it summarises is just another
         row that happens to be at the top. ]]--
    local bars = {}
    for i = 1, table.getn(self.rows) do table.insert(bars, self.rows[i]) end
    if self.frame.pull then table.insert(bars, self.frame.pull) end

    local pct, figures = 0, 0

    for i = 1, table.getn(bars) do
        local row = bars[i]

        if row:IsShown() then
            local p = row.right:GetStringWidth() or 0
            if p > pct then pct = p end

            local f = row.center:GetStringWidth() or 0
            if f > figures then figures = f end

        end
    end

    --[[ Right to left: the percentage against the right edge, the threat figure
         a gap inside it. Every row uses the same two numbers, which is what
         makes them columns rather than a coincidence that holds until somebody
         crits.

         **Two, not three.** The change column was removed with the setting that
         drew it -- and its width came out of the measurement here as well as out
         of the drawing, or the gap it used to occupy would still be there with
         nothing in it. ]]--
    local gap = 8
    local pctAt = OB.ColumnStart(bars[1], pct, 0)
    local figuresAt = pctAt - gap - figures

    --[[ **The name gives way, not the numbers.**

         Both columns used to be shoved rightward by a long name -- the percent
         by ColumnStart and the figure by a floor of its own -- which walked the
         percentage off the right-hand edge of the window and cut it in half.
         The room left over is now the name's budget, and a name too long for it
         is trimmed. ]]--
    local room = OB.NameRoom(bars[1], pct + gap + figures)

    for i = 1, table.getn(bars) do
        local row = bars[i]

        if row:IsShown() then
            OB.FitTextTo(row.left, row.leftFull, room)
            OB.PlaceText(row, row.left, 0)

            OB.PlaceTextLeftAt(row, row.right, pctAt)
            OB.PlaceTextLeftAt(row, row.center, figuresAt)
        end
    end
end
