--[[ Equadis' Classic Overhaul :: combat log parser

  Who hit what, for how much, without reading a word of English.

  Derived from ShaguDPS by Eric Mauser (Shagu), MIT licensed -- see NOTICE, which
  reproduces that licence in full as it requires. The idea below is his and it is
  the reason this was ported rather than written: it is the only approach that
  survives a localised client, and every alternative is a table of translated
  sentences that rots the day a server changes one.

  **The client already knows the sentences.** `COMBATHITSELFOTHER` is the global
  string "You hit %s for %d.", in whatever language the client is running. So
  rather than matching text, the patterns are turned into Lua patterns with their
  placeholders captured, and the client's own strings do the translating.

  Three things make that work, and all three are subtle enough to be worth
  naming:

  **Sanitising.** A Blizzard format string is not a Lua pattern -- it is full of
  magic characters, and `%s`/`%d` mean the wrong thing. `sanitize` escapes the
  magic, turns each placeholder into a capture, and gives numbers priority over
  strings so that "%s for %d" does not let the greedy name swallow the number.

  **Capture order.** Localised strings reorder their arguments: a language may
  put the target before the attacker, which the client writes as `%2$s` and
  `%1$s`. `captures` reads those indices out of the raw string so the values can
  be put back in the order the extractor expects. Without it every non-English
  client would silently attribute damage to the wrong player.

  **One event, several sentences.** A hit and a crit are different strings on the
  same event, so each event carries a list and the first pattern that matches
  wins.
]]--

local OB = EquadisClassicOverhaul

OB.parser = { listeners = {} }

-- ---------------------------------------------------------------------------
-- turning a Blizzard format string into a Lua pattern
-- ---------------------------------------------------------------------------

--[[ Cached because the transformation is pure and the same fifty strings are
     asked for on every combat log line. Uncached this is the parser's whole
     cost; cached it is a table lookup. ]]--
local sanitiseCache = {}

local function sanitise(pattern)
    if not sanitiseCache[pattern] then
        local ret = pattern

        -- escape the magic characters a format string is full of
        ret = string.gsub(ret, "([%+%-%*%(%)%?%[%]%^])", "%%%1")

        -- drop the reordering indices; `captures` reads them separately
        ret = string.gsub(ret, "%d%$", "")

        -- every placeholder becomes a capture
        ret = string.gsub(ret, "(%%%a)", "%(%1+%)")

        -- %s means "any run of characters", not "a space"
        ret = string.gsub(ret, "%%s%+", ".+")

        --[[ Numbers win over names. "%s for %d" with a greedy name capture eats
             the digits as part of the name and leaves nothing to match, so the
             string capture before a number is made lazy. ]]--
        ret = string.gsub(ret, "%(.%+%)%(%%d%+%)", "%(.-%)%(%%d%+%)")

        sanitiseCache[pattern] = ret
    end

    return sanitiseCache[pattern]
end

OB.SanitisePattern = sanitise

--[[ The argument order a localised string asks for, as up to five indices.

     A language that wants the target named first writes `%2$s ... %1$s`, and the
     numbers are the whole of what tells us so. Read once per string and cached,
     because they never change while the client is running. ]]--
local captureCache = {}

local function captures(pattern)
    local r = captureCache

    if not r[pattern] then
        r[pattern] = { nil, nil, nil, nil, nil }

        for a, b, c, d, e in string.gfind(
                string.gsub(pattern, "%((.+)%)", "%1"),
                string.gsub(pattern, "%d%$", "%%(.-)$")) do
            r[pattern][1] = tonumber(a)
            r[pattern][2] = tonumber(b)
            r[pattern][3] = tonumber(c)
            r[pattern][4] = tonumber(d)
            r[pattern][5] = tonumber(e)
        end
    end

    return r[pattern][1], r[pattern][2], r[pattern][3], r[pattern][4], r[pattern][5]
end

--[[ string.find, but handing the captures back in the order the *extractor*
     expects rather than the order the sentence happened to use.

     The five locals are hoisted out of the function on purpose. This runs on
     every combat log line of every fight, and in 5.0 a fresh local per call is a
     fresh table slot per call. ]]--
local ra, rb, rc, rd, re, ca, cb, cc, cd, ce
local matched, num, va, vb, vc, vd, ve

function OB.ParseLine(text, pattern)
    ca, cb, cc, cd, ce = captures(pattern)
    matched, num, va, vb, vc, vd, ve = string.find(text, sanitise(pattern))

    if not matched then return nil end

    ra = ce == 1 and ve or cd == 1 and vd or cc == 1 and vc or cb == 1 and vb or va
    rb = ce == 2 and ve or cd == 2 and vd or cc == 2 and vc or ca == 2 and va or vb
    rc = ce == 3 and ve or cd == 3 and vd or ca == 3 and va or cb == 3 and vb or vc
    rd = ce == 4 and ve or ca == 4 and va or cc == 4 and vc or cb == 4 and vb or vd
    re = ca == 5 and va or cd == 5 and vd or cc == 5 and vc or cb == 5 and vb or ve

    return ra, rb, rc, rd, re
end

-- ---------------------------------------------------------------------------
-- which sentences belong to which event
-- ---------------------------------------------------------------------------

--[[ Read from the client's globals, so a string the client does not have is
     simply absent rather than a nil key that breaks the table. Turtle removing
     or renaming one costs that one sentence, not the parser. ]]--
local function G(name) return getglobal(name) end

--[[ A table rather than varargs. 5.0 builds `arg` for a vararg function and 5.1
     does not, so `...` here would work in the client and be nil in the harness --
     which is the one direction of incompatibility that never gets caught. ]]--
local function group(names)
    local out = {}
    for i = 1, table.getn(names) do
        local s = G(names[i])
        if s then table.insert(out, s) end
    end
    return out
end

local strings = {}

strings.hitSelfOther = group({ "COMBATHITSELFOTHER", "COMBATHITSCHOOLSELFOTHER",
        "COMBATHITCRITSELFOTHER", "COMBATHITCRITSCHOOLSELFOTHER" })
strings.hitOtherSelf = group({ "COMBATHITOTHERSELF", "COMBATHITCRITOTHERSELF",
        "COMBATHITSCHOOLOTHERSELF", "COMBATHITCRITSCHOOLOTHERSELF" })
strings.hitOtherOther = group({ "COMBATHITOTHEROTHER", "COMBATHITCRITOTHEROTHER",
        "COMBATHITSCHOOLOTHEROTHER", "COMBATHITCRITSCHOOLOTHEROTHER" })

strings.spellSelf = group({ "SPELLLOGSCHOOLSELFSELF", "SPELLLOGCRITSCHOOLSELFSELF",
        "SPELLLOGSELFSELF", "SPELLLOGCRITSELFSELF", "SPELLLOGSCHOOLSELFOTHER",
        "SPELLLOGCRITSCHOOLSELFOTHER", "SPELLLOGSELFOTHER", "SPELLLOGCRITSELFOTHER" })
strings.spellOtherSelf = group({ "SPELLLOGSCHOOLOTHERSELF",
        "SPELLLOGCRITSCHOOLOTHERSELF", "SPELLLOGOTHERSELF", "SPELLLOGCRITOTHERSELF" })
strings.spellOtherOther = group({ "SPELLLOGSCHOOLOTHEROTHER",
        "SPELLLOGCRITSCHOOLOTHEROTHER", "SPELLLOGOTHEROTHER", "SPELLLOGCRITOTHEROTHER" })

strings.shieldSelf = group({ "DAMAGESHIELDSELFOTHER" })
strings.shieldOther = group({ "DAMAGESHIELDOTHERSELF", "DAMAGESHIELDOTHEROTHER" })

strings.dotOther = group({ "PERIODICAURADAMAGESELFOTHER", "PERIODICAURADAMAGEOTHEROTHER" })
strings.dotSelf = group({ "PERIODICAURADAMAGESELFSELF", "PERIODICAURADAMAGEOTHERSELF" })

strings.healSelf = group({ "HEALEDCRITSELFSELF", "HEALEDSELFSELF",
        "HEALEDCRITSELFOTHER", "HEALEDSELFOTHER" })
strings.healOther = group({ "HEALEDCRITOTHERSELF", "HEALEDOTHERSELF",
        "HEALEDCRITOTHEROTHER", "HEALEDOTHEROTHER" })
strings.hotOther = group({ "PERIODICAURAHEALSELFOTHER", "PERIODICAURAHEALOTHEROTHER" })
strings.hotSelf = group({ "PERIODICAURAHEALSELFSELF", "PERIODICAURAHEALOTHERSELF" })

OB.parser.events = {
    CHAT_MSG_COMBAT_SELF_HITS = strings.hitSelfOther,
    CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS = strings.hitOtherSelf,
    CHAT_MSG_COMBAT_PARTY_HITS = strings.hitOtherOther,
    CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS = strings.hitOtherOther,
    CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS = strings.hitOtherOther,
    CHAT_MSG_COMBAT_CREATURE_VS_CREATURE_HITS = strings.hitOtherOther,
    CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS = strings.hitOtherOther,
    CHAT_MSG_COMBAT_PET_HITS = strings.hitOtherOther,

    CHAT_MSG_SPELL_SELF_DAMAGE = strings.spellSelf,
    CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE = strings.spellOtherSelf,
    CHAT_MSG_SPELL_PARTY_DAMAGE = strings.spellOtherOther,
    CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE = strings.spellOtherOther,
    CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE = strings.spellOtherOther,
    CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE = strings.spellOtherOther,
    CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE = strings.spellOtherOther,
    CHAT_MSG_SPELL_PET_DAMAGE = strings.spellOtherOther,

    CHAT_MSG_SPELL_DAMAGESHIELDS_ON_SELF = strings.shieldSelf,
    CHAT_MSG_SPELL_DAMAGESHIELDS_ON_OTHERS = strings.shieldOther,

    CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE = strings.dotOther,
    CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE = strings.dotOther,
    CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE = strings.dotOther,
    CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE = strings.dotOther,
    CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE = strings.dotSelf,

    CHAT_MSG_SPELL_SELF_BUFF = strings.healSelf,
    CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF = strings.healOther,
    CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF = strings.healOther,
    CHAT_MSG_SPELL_PARTY_BUFF = strings.healOther,

    CHAT_MSG_SPELL_PERIODIC_PARTY_BUFFS = strings.hotOther,
    CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS = strings.hotOther,
    CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS = strings.hotOther,
    CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS = strings.hotSelf,
}

-- ---------------------------------------------------------------------------
-- what each sentence means
-- ---------------------------------------------------------------------------

--[[ One extractor per sentence, each returning the same six things:

       source, spell, target, amount, school, kind

     The whole table exists because the captures arrive in the order the sentence
     puts them, and every sentence puts them somewhere different. "You hit %s for
     %d" gives target then amount; "%s suffers %d %s damage from your %s" gives
     target, amount, school, spell. There is no shortcut: the mapping is the
     data.

     `d` carries the defaults -- the player as both source and target, physical,
     an auto hit -- so an extractor only names what its sentence actually says. ]]--
local extract = {}

local function define(name, fn)
    local s = G(name)
    if s then extract[s] = fn end
end

-- damage, player as the source
define("COMBATHITSELFOTHER", function(d, target, value)
    return d.source, d.attack, target, value, d.school, "damage" end)
define("COMBATHITCRITSELFOTHER", function(d, target, value)
    return d.source, d.attack, target, value, d.school, "damage" end)
define("COMBATHITSCHOOLSELFOTHER", function(d, target, value, school)
    return d.source, d.attack, target, value, school, "damage" end)
define("COMBATHITCRITSCHOOLSELFOTHER", function(d, target, value, school)
    return d.source, d.attack, target, value, school, "damage" end)

define("SPELLLOGSELFOTHER", function(d, attack, target, value)
    return d.source, attack, target, value, d.school, "damage" end)
define("SPELLLOGCRITSELFOTHER", function(d, attack, target, value)
    return d.source, attack, target, value, d.school, "damage" end)
define("SPELLLOGSCHOOLSELFOTHER", function(d, attack, target, value, school)
    return d.source, attack, target, value, school, "damage" end)
define("SPELLLOGCRITSCHOOLSELFOTHER", function(d, attack, target, value, school)
    return d.source, attack, target, value, school, "damage" end)

define("SPELLLOGSELFSELF", function(d, attack, value)
    return d.source, attack, d.target, value, d.school, "damage" end)
define("SPELLLOGCRITSELFSELF", function(d, attack, value)
    return d.source, attack, d.target, value, d.school, "damage" end)
define("SPELLLOGSCHOOLSELFSELF", function(d, attack, value, school)
    return d.source, attack, d.target, value, school, "damage" end)
define("SPELLLOGCRITSCHOOLSELFSELF", function(d, attack, value, school)
    return d.source, attack, d.target, value, school, "damage" end)

define("PERIODICAURADAMAGESELFOTHER", function(d, target, value, school, attack)
    return d.source, attack, target, value, school, "damage" end)
define("PERIODICAURADAMAGESELFSELF", function(d, value, school, attack)
    return d.source, attack, d.target, value, school, "damage" end)

define("DAMAGESHIELDSELFOTHER", function(d, value, school, target)
    return d.source, d.attack, target, value, school, "damage" end)

-- damage, somebody else as the source
define("COMBATHITOTHERSELF", function(d, source, value)
    return source, d.attack, d.target, value, d.school, "damage" end)
define("COMBATHITCRITOTHERSELF", function(d, source, value)
    return source, d.attack, d.target, value, d.school, "damage" end)
define("COMBATHITSCHOOLOTHERSELF", function(d, source, value, school)
    return source, d.attack, d.target, value, school, "damage" end)
define("COMBATHITCRITSCHOOLOTHERSELF", function(d, source, value, school)
    return source, d.attack, d.target, value, school, "damage" end)

define("COMBATHITOTHEROTHER", function(d, source, target, value)
    return source, d.attack, target, value, d.school, "damage" end)
define("COMBATHITCRITOTHEROTHER", function(d, source, target, value)
    return source, d.attack, target, value, d.school, "damage" end)
define("COMBATHITSCHOOLOTHEROTHER", function(d, source, target, value, school)
    return source, d.attack, target, value, school, "damage" end)
define("COMBATHITCRITSCHOOLOTHEROTHER", function(d, source, target, value, school)
    return source, d.attack, target, value, school, "damage" end)

define("SPELLLOGOTHERSELF", function(d, source, attack, value)
    return source, attack, d.target, value, d.school, "damage" end)
define("SPELLLOGCRITOTHERSELF", function(d, source, attack, value)
    return source, attack, d.target, value, d.school, "damage" end)
define("SPELLLOGSCHOOLOTHERSELF", function(d, source, attack, value, school)
    return source, attack, d.target, value, school, "damage" end)
define("SPELLLOGCRITSCHOOLOTHERSELF", function(d, source, attack, value, school)
    return source, attack, d.target, value, school, "damage" end)

define("SPELLLOGOTHEROTHER", function(d, source, attack, target, value)
    return source, attack, target, value, d.school, "damage" end)
define("SPELLLOGCRITOTHEROTHER", function(d, source, attack, target, value, school)
    return source, attack, target, value, school or d.school, "damage" end)
define("SPELLLOGSCHOOLOTHEROTHER", function(d, source, attack, target, value, school)
    return source, attack, target, value, school, "damage" end)
define("SPELLLOGCRITSCHOOLOTHEROTHER", function(d, source, attack, target, value, school)
    return source, attack, target, value, school, "damage" end)

define("PERIODICAURADAMAGEOTHERSELF", function(d, value, school, source, attack)
    return source, attack, d.target, value, school, "damage" end)
define("PERIODICAURADAMAGEOTHEROTHER", function(d, target, value, school, source, attack)
    return source, attack, target, value, school, "damage" end)

define("DAMAGESHIELDOTHERSELF", function(d, source, value, school)
    return source, d.attack, d.target, value, school, "damage" end)
define("DAMAGESHIELDOTHEROTHER", function(d, source, value, school, target)
    return source, d.attack, target, value, school, "damage" end)

-- healing
define("HEALEDSELFSELF", function(d, spell, value)
    return d.source, spell, d.target, value, d.school, "heal" end)
define("HEALEDCRITSELFSELF", function(d, spell, value)
    return d.source, spell, d.target, value, d.school, "heal" end)
define("HEALEDSELFOTHER", function(d, spell, target, value)
    return d.source, spell, target, value, d.school, "heal" end)
define("HEALEDCRITSELFOTHER", function(d, spell, target, value)
    return d.source, spell, target, value, d.school, "heal" end)

define("HEALEDOTHERSELF", function(d, source, spell, value)
    return source, spell, d.target, value, d.school, "heal" end)
define("HEALEDCRITOTHERSELF", function(d, source, spell, value)
    return source, spell, d.target, value, d.school, "heal" end)
define("HEALEDOTHEROTHER", function(d, source, spell, target, value)
    return source, spell, target, value, d.school, "heal" end)
define("HEALEDCRITOTHEROTHER", function(d, source, spell, target, value)
    return source, spell, target, value, d.school, "heal" end)

define("PERIODICAURAHEALSELFSELF", function(d, value, spell)
    return d.source, spell, d.target, value, d.school, "heal" end)
define("PERIODICAURAHEALSELFOTHER", function(d, target, value, spell)
    return d.source, spell, target, value, d.school, "heal" end)
define("PERIODICAURAHEALOTHERSELF", function(d, value, source, spell)
    return source, spell, d.target, value, d.school, "heal" end)
define("PERIODICAURAHEALOTHEROTHER", function(d, target, value, source, spell)
    return source, spell, target, value, d.school, "heal" end)

OB.parser.extract = extract

-- ---------------------------------------------------------------------------
-- reading a line
-- ---------------------------------------------------------------------------

--[[ Absorb and resist are *suffixes* appended to an otherwise ordinary
     sentence -- "... for 120 damage. (30 absorbed)" -- so they are stripped
     before matching rather than given patterns of their own. Left in place they
     break the trailing capture of every pattern they follow. ]]--
local absorbPattern, resistPattern

local function trailers()
    if absorbPattern == nil then
        absorbPattern = G("ABSORB_TRAILER") and sanitise(G("ABSORB_TRAILER")) or false
        resistPattern = G("RESIST_TRAILER") and sanitise(G("RESIST_TRAILER")) or false
    end
    return absorbPattern, resistPattern
end

local defaults = {}

--[[ Read one combat log line into { source, spell, target, amount, school, kind },
     or nil if no sentence for this event matched it.

     A pure function of the line and the event, deliberately: the damage meter
     drives it, the tests drive it, and neither has to stand up a frame or fire an
     event to ask what a sentence means. ]]--
--[[ **The last line read, and what it came to.**

     This function is the hottest thing in the addon: every combat event in the
     game arrives here, and in a forty-man raid that is hundreds a second. It is
     also called **twice for every one of them** -- the damage meter and the
     threat meter each register the full combat event list and each parse the
     line independently, doing identical work and throwing away identical
     results.

     Cached on the exact event and text, which is enough: the same sentence for
     the same event is the same line, and the two readers get it within one
     frame of each other. That halves the parsing outright.

     **The result table is reused rather than rebuilt**, which the cache is what
     makes safe: both readers see the same table, both read their fields
     immediately, and neither keeps it. A fresh table per line was hundreds of
     tables a second in a raid, and on 1.12 that is not CPU -- it is garbage, and
     it is paid later as the collection pause people call lag. ]]--
local lastEvent, lastText, lastResult
local result = {}

function OB.ReadCombatLine(event, text)
    if type(text) ~= "string" then return nil end

    if event == lastEvent and text == lastText then return lastResult end

    lastEvent, lastText = event, text
    lastResult = nil

    local patterns = OB.parser.events[event]
    if not patterns then return nil end

    --[[ **`string.gsub` allocates a new string every time, including when it
         replaced nothing** -- and almost no line carries an absorb or a resist
         trailer. Looked for first with `string.find`, which allocates nothing.
         Same fix the tooltip cleaners needed, and for the same reason. ]]--
    local absorb, resist = trailers()
    if absorb and string.find(text, absorb) then
        text = string.gsub(text, absorb, "")
    end
    if resist and string.find(text, resist) then
        text = string.gsub(text, resist, "")
    end

    local player = UnitName("player")

    defaults.source = player
    defaults.target = player
    defaults.school = "physical"
    defaults.attack = "Auto Hit"

    for i = 1, table.getn(patterns) do
        local pattern = patterns[i]
        local fn = extract[pattern]

        if fn then
            local a, b, c, d, e = OB.ParseLine(text, pattern)

            if a then
                local source, spell, target, amount, school, kind = fn(defaults, a, b, c, d, e)
                amount = tonumber(amount)

                --[[ A sentence that matched but produced no number is a pattern
                     collision, not a hit. Reporting zero damage would put a
                     phantom row in the meter for whoever was named. ]]--
                if amount and source and target then
                    --[[ Written into the one table rather than a new one. See
                         the note above `lastEvent`: this is the hottest path in
                         the addon and the readers are immediate. ]]--
                    result.source = source
                    result.spell = spell
                    result.target = target
                    result.amount = amount
                    result.school = school
                    result.kind = kind

                    lastResult = result
                    return result
                end
            end
        end
    end

    return nil
end

--[[ Every event the parser knows how to read, for a module to register.

     Built from the events table rather than listed again, so a sentence added
     above is listened for without a second edit somewhere else. ]]--
function OB.CombatLogEvents()
    local out = {}
    for name in pairs(OB.parser.events) do table.insert(out, name) end
    table.sort(out)
    return out
end
