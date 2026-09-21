--[[ Equadis' Classic Overhaul :: character panel

  **The paper doll, which vanilla leaves almost bare.**

  Two things live here to begin with, and both arrived from the Quality Of Life
  page -- which is where settings went when nobody had decided where they
  belonged. An item border is a fact about the item in the slot; turning the
  model is a thing you do to the model. Neither is quality of life, and neither
  was findable under that name.

  Stats come later. The scope note in the handoff is explicit that this module is
  not finished, and a page that promises groups it does not draw is worse than a
  short one.
]]--

local OB = EquadisClassicOverhaul

local M = OB.RegisterModule({
    id = "characterpanel",
    name = "Character Panel",
    feature = true,
    renders = "none",

    --[==[ Everything that can change a number on the sheet. `UNIT_INVENTORY_
         CHANGED` covers equipping, the two aura events cover buffs, and the
         paper doll's own show event covers opening it after something happened
         while it was shut. ]==]
    events = { "UNIT_INVENTORY_CHANGED", "PLAYER_AURAS_CHANGED",
               "UNIT_AURA", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD",
               "CHARACTER_POINTS_CHANGED" },
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

    --[[ Text only. There is no bar here and no border of ours -- the borders
         this module draws are the client's own item-quality colours on the
         client's own slots. ]]--
    styled = { font = true, fontOutline = true },

    --[==[ **The shared Appearance rows belong on one page.**

         The panel shell appends them to whichever tab is open unless a module
         says otherwise, so Bar Texture and Font appear to be settings about
         whatever you happen to be looking at. `appearanceSection` is the answer
         and had been in `options.lua` all along with nothing setting it. ]==]
    appearanceSection = "general",

    defaults = {
        --[[ **On, because item quality is already a colour and the slots simply
             do not use it.**

             The information exists, the client knows it, and every other place
             an item appears -- the bag, the loot roll, the tooltip's first line
             -- says it in colour. The paper doll is the one screen that makes
             you read the name to find out. ]]--
        rarityBorders = true,

        --[[ **On, and with no setting for the axis or the easing.**

             Dragging a model to turn it is what everybody expects a model to do;
             there is no version of this somebody wants switched off by default.
             The switch exists at all because it takes over the left mouse button
             on that frame, and taking over a mouse button should always be
             refusable. ]]--
        modelRotate = true,
        modelRotateSpeed = 0.010,

        --[==[ **The stat panes, on.**

             This is the module's reason to exist now: 1.12's own sheet answers
             six questions and people have twelve, and weapon skill, swing speed,
             hit and crit are all things the client knows and does not show. ]==]
        statPanes = true,

        --[[ The client's small face is ten, and beside BetterCharacterStats'
             eleven-point Myriad it reads a size or two large -- Friz Quadrata
             is a wide face. Nine was still "too high"; eight by default, and
             a slider because "too big" is a judgement about a screen this
             addon cannot see. Schema 44 moves a shipped nine down. ]]--
        statFontSize = 8,

        --[[ Which group each pane opens on. Base beside melee, which answers
             "what am I" and "what do I hit for" at the same time. ]]--
        leftGroup = "base",
        rightGroup = "melee",

        --[==[ **How bright the quality colour on an item slot is.**

             The colour is applied to the slot's own metal ring with
             `SetVertexColor`, which *multiplies* -- so a blue item tints a dark
             grey frame and comes out darker still. Reported as exactly that:
             the borders are a bit dark.

             The fix is a second, additive pass -- the same glow the bag window
             puts round a rare item -- and a number for how strong it is, because
             how bright is bright enough depends on the artwork behind it. ]==]
        borderGlow = true,
        borderGlowAlpha = 0.55,
    },

    options = {
--[==[ **One tab, because there were three settings in two.**

             `Items` held one switch and `Model` held two. Splitting three rows
             across two tabs asks the reader to guess which of two drawers a
             thing is in before they can look at it, and the answer either way
             is "the character panel". ]==]
        { "General", "__s_general", "section", "general" },

        --[[ Automatic from item quality. Individual rarity colour pickers were
             considered and are not here: the colours are the game's, every other
             addon uses the same ones, and a person who recolours "rare" has made
             their own interface disagree with the rest of the client. ]]--
        { "Colored Item Borders", "rarityBorders", "boolean" },

        --[[ The ring alone is a multiply against dark metal, so this is the pass
             that makes the colour visible. See `borderGlow`. ]]--
        { "Brighten Item Borders", "borderGlow", "boolean",
          nil, nil, nil, nil, nil, "!rarityBorders" },
        { "Border Brightness", "borderGlowAlpha", "slider", 10, 100, 5, 0.01,
          nil, "!rarityBorders,!borderGlow" },

        { "Stats", "__s_stats", "section", "stats" },
        { "Show The Stat Panes", "statPanes", "boolean" },
        { "Stat Text Size", "statFontSize", "slider", 6, 12, 1,
          nil, nil, "!statPanes" },
        { "Left Pane", "leftGroup",
          OB.Enum({ "base", "melee", "ranged", "defense" },
                  { "Base Stats", "Melee", "Ranged", "Defense" }),
          nil, nil, nil, nil, "!statPanes" },
        { "Right Pane", "rightGroup",
          OB.Enum({ "base", "melee", "ranged", "defense" },
                  { "Base Stats", "Melee", "Ranged", "Defense" }),
          nil, nil, nil, nil, "!statPanes" },

        { "General", "__s_general2", "section", "general" },
        { "Turn Character Model By Dragging", "modelRotate", "boolean" },
        { "Drag Sensitivity", "modelRotateSpeed", "slider", 2, 40, 1, 0.001,
          nil, "!modelRotate" },
    },
})

function M:Config()
    return OB.profile.modules.characterpanel
end

-- ---------------------------------------------------------------------------
-- the stats vanilla leaves out
-- ---------------------------------------------------------------------------

--[==[ **1.12's character sheet answers six questions and people have twelve.**

     Strength, Agility, Stamina, Intellect, Spirit, Armor -- and then two boxes
     of melee and ranged numbers that say attack power and damage and stop.
     Weapon skill, swing speed, hit and crit are all things the client knows or
     can be asked for, and none of them are on the screen that exists to show
     you what your character is.

     So this draws its own two boxes, each showing one **group** chosen from a
     dropdown on its header: base stats, melee, ranged, defense. Two boxes
     rather than one long list because that is the shape of the frame they sit
     in, and a dropdown rather than a tab strip because there are more groups
     than there is width for.

     **Every value is asked of the client, and a row the client cannot answer is
     not drawn.** 1.12 forks differ about which of these calls exist -- crit and
     hit are the two that come and go -- and a number this addon computed from a
     table of class ratios would be a guess wearing the same font as a fact. A
     missing row says the client does not know; a wrong row is read and acted
     on. `/eq statdebug` prints which calls this client has. ]==]

--[[ Formatting helpers. Kept here rather than in `core.lua` because they are
     about a paper doll rather than about numbers in general: a percentage on
     this screen is written to two decimals, which is what the reference this
     was ported from does and is finer than anything else in this addon. ]]--
local function statNumber(value)
    if type(value) ~= "number" then return nil end
    return tostring(OB.Round(value))
end

local function statPercent(value)
    if type(value) ~= "number" then return nil end
    return string.format("%.2f%%", value)
end

local function statPair(a, b)
    if type(a) ~= "number" then return nil end
    if type(b) ~= "number" or a == b then return statNumber(a) end
    return statNumber(a) .. " | " .. statNumber(b)
end

--[[ A call this client may not have, asked safely. Answers nil for "no such
     call" and for "the call threw", which are the same thing to a reader. ]]--
--[[ Fixed arguments rather than `...`: 1.12 is Lua 5.0 and builds `arg` for a
     vararg function, and the harness is LuaJIT and does not -- so `unpack(arg)`
     here would work in the game and read the command line in the tests. Nothing
     asked for takes more than a unit token anyway. ]]--
local function ask(name, a, b)
    local fn = getglobal(name)
    if type(fn) ~= "function" then return nil end

    local ok, r1, r2, r3, r4, r5 = pcall(fn, a, b)
    if not ok then return nil end

    return r1, r2, r3, r4, r5
end

M.ask = ask

-- ---------------------------------------------------------------------------
-- what the gear says
-- ---------------------------------------------------------------------------

--[==[ **Hit and crit cannot be asked for on this client, so they are read off
     the items that grant them.**

     This was open for a while on the assumption that some fork had back-ported
     `GetCritChance` or `GetHitModifier`. Neither is there: the client binary
     carries `GetDodgeChance`, `GetParryChance`, `GetBlockChance`,
     `UnitAttackPower`, `UnitDefense` and `UnitResistance` and no crit or hit
     call under any spelling, and none of the libraries loaded beside it add one.

     What *is* knowable exactly is what your gear says, because every point of it
     is written on an item in a sentence the client will hand over. So the item
     tooltips are read and the percentages added up. That is a fact rather than a
     formula -- no class ratios, no talent tables, nothing this addon could have
     got wrong quietly.

     **It is gear only, and the rows say so.** A rogue with Precision has hit
     this cannot see, and a label reading "Hit" would be a lie about a number
     somebody gears against. "Hit (gear)" is the whole truth in six
     characters. ]==]
local GEAR_SLOTS = 19

--[[ Longest first: "…to hit with spells by 1%" also matches "…to hit by 1%",
     and a spell-hit item counted as melee hit is a wrong number rather than a
     missing one. ]]--
local GEAR_LINES = {
    --[[ One sentence, both totals: a few items grant hit to spells and
         attacks alike, and reading it as either alone drops it from the
         other. `both` is the key the reader splits. ]]--
    { "chance to hit with spells and attacks by (%d+%.?%d*)", "both" },
    { "chance to hit with spells by (%d+%.?%d*)", "spellHit" },
    { "chance to hit by (%d+%.?%d*)", "hit" },
    { "(%d+%.?%d*)%% Hit Chance", "hit" },
    { "(%d+%.?%d*)%% to Hit", "hit" },
    --[[ The two short spellings this server writes: "/Hit +1" on a stat line
         and "+3% Ranged Hit" on a scope. Ranged hit is its own total because
         a scope does nothing for a sword. ]]--
    { "/Hit %+(%d+%.?%d*)", "hit" },
    { "%+(%d+%.?%d*)%% Ranged Hit", "rangedHit" },
    { "critical strike with spells by (%d+%.?%d*)", "spellCrit" },
    { "critical strike by (%d+%.?%d*)", "crit" },
    { "(%d+%.?%d*)%% Critical Strike", "crit" },
    { "damage and healing done by magical spells and effects by up to (%d+)",
      "spellPower" },
    { "healing done by spells and effects by up to (%d+)", "healing" },
}

local SCHOOLS = { "Arcane", "Fire", "Frost", "Holy", "Nature", "Shadow" }

--[==[ **A set bonus is printed on every piece of the set, and the ones you
     do not have yet are printed too.**

     Wearing three pieces of a set puts the set's whole bonus list on all three
     tooltips: the active bonuses as "Set: Improves your chance to hit by 1%."
     and the ones still out of reach as "(5) Set: ..." in grey. A reader that
     adds up every sentence it sees counts the active bonus three times and the
     inactive one as well -- which is the "hit isn't counting properly" report:
     a rogue in three Bloodfang pieces and no hit gear reading several percent.

     So an inactive bonus is skipped by its "(n) Set:" prefix, and an active
     one is counted once per set, keyed on the set's name -- the "Name (3/8)"
     line above the list -- and the bonus text, so two different sets that
     happen to grant the same thing are still both counted. ]==]
--[==[ **How many lines the tooltip holds right now**, and not one more.

     The client reuses one pool of font strings for every tooltip and
     `ClearLines` hides them without blanking them, so after a long tooltip a
     short one leaves the long one's tail readable past `NumLines()`. The
     three scans here walked to the first nil, which in game is never the
     end of *this* tooltip: bracers with a hit line followed by plain gloves
     counted the bracers' hit twice, and Precision's own sentence sat under
     every shorter talent read after it. That is the "hit isn't counting
     properly" that survived two rounds of pattern work -- the patterns were
     right and the lines were somebody else's.

     Capped for a client whose count cannot be trusted, and the cap is the
     old ceiling. ]==]
local SCAN_CAP = 40

local function scanCount(tip)
    local n = tip and tip.NumLines and tip:NumLines()
    if type(n) ~= "number" or n > SCAN_CAP then return SCAN_CAP end
    return n
end

--[[ `trace`, when given, collects what was read and from where, for the
     debug command: a wrong total is settled by the lines behind it. ]]--
local function readGearLine(line, out, setName, trace)
    if string.find(line, "^%(%d+%) Set:") then return false end

    if string.find(line, "^Set:") then
        local key = tostring(setName or "?") .. "|" .. line
        out.setSeen = out.setSeen or {}
        if out.setSeen[key] then return false end
        out.setSeen[key] = true
    end

    for i = 1, table.getn(GEAR_LINES) do
        local _, _, found = string.find(line, GEAR_LINES[i][1])

        if found then
            local key = GEAR_LINES[i][2]
            local value = tonumber(found) or 0

            if key == "both" then
                out.hit = (out.hit or 0) + value
                out.spellHit = (out.spellHit or 0) + value
            else
                out[key] = (out[key] or 0) + value
            end

            if trace then
                table.insert(trace, { key = key, value = value, line = line })
            end
            return true
        end
    end

    --[[ School power is one sentence with the school's name in the middle of
         it, so it is asked six times rather than pattern-matched loosely: a
         greedy match here would read "Fire" out of "Fireguard". ]]--
    for i = 1, table.getn(SCHOOLS) do
        local school = SCHOOLS[i]
        local _, _, found = string.find(line,
                "damage done by " .. school .. " spells and effects by up to (%d+)")

        if found then
            out.schools[school] = (out.schools[school] or 0) + (tonumber(found) or 0)
            return true
        end
    end

    return false
end

--[==[ **Every worn item, read once and kept for half a second.**

     Nineteen tooltips is real work and six rows all want the answer, so the
     scan is cached for long enough to draw a pane and short enough that
     equipping something and looking again shows it. The sheet is shut most of
     the time and nothing here runs while it is. ]==]
function M:GearBonuses(force)
    local now = (type(GetTime) == "function" and GetTime()) or 0

    if not force and self.gear and (now - (self.gearAt or -1)) < 0.5 then
        return self.gear
    end

    local out = { hit = 0, crit = 0, spellHit = 0, spellCrit = 0,
                  rangedHit = 0,
                  spellPower = 0, healing = 0, schools = {}, read = false,
                  trace = {} }

    for i = 1, table.getn(SCHOOLS) do out.schools[SCHOOLS[i]] = 0 end

    local tip = type(OB.ScanTooltip) == "function" and OB.ScanTooltip()

    if tip and tip.SetInventoryItem and type(OB.ScanLine) == "function" then
        out.read = true

        for slot = 1, GEAR_SLOTS do
            local worn = type(GetInventoryItemLink) ~= "function"
                    or GetInventoryItemLink("player", slot)

            if worn then
                if tip.ClearLines then tip:ClearLines() end
                tip:SetInventoryItem("player", slot)

                local setName
                local before = table.getn(out.trace)

                for index = 1, scanCount(tip) do
                    local line = OB.ScanLine(index)
                    if not line then break end

                    --[[ "Bloodfang Armor (3/8)": the line that names the set
                         its bonuses belong to, read before they are. ]]--
                    local _, _, named = string.find(line, "^(.+) %(%d+/%d+%)$")
                    if named then setName = named end

                    readGearLine(line, out, setName, out.trace)
                end

                for t = before + 1, table.getn(out.trace) do
                    out.trace[t].slot = slot
                    out.trace[t].item = OB.ScanLine(1)
                end
            end
        end
    end

    self.gear, self.gearAt = out, now
    return out
end


-- ---------------------------------------------------------------------------
-- what the talents say
-- ---------------------------------------------------------------------------

--[==[ **Hit and crit from talents, read off the talent tooltips.**

     This was left out on purpose for a while: the failure mode of reading
     talents is over-counting, and a pattern loose enough to catch Cruelty
     catches Lethality, which raises crit *damage*. So every sentence here is
     the exact wording of one talent -- Precision, Surefooted, Nature's
     Guidance, Cruelty and Malice and Conviction, Lethal Shots, Killer Instinct
     -- and nothing looser. A talent not on the list is not counted, which is
     a number that is low rather than one that is wrong.

     What is deliberately not here: Sharpened Claws, which only applies in a
     form this sheet cannot see; the school-specific spell-hit talents
     (Elemental Precision, Suppression, Shadow Focus...), which are one school
     each and do not belong in a single spell-hit number.

     **The tooltip prints the next rank underneath the current one**, after a
     "Next rank:" line, and the next rank's sentence has a bigger number in
     it. Reading past that line is the second way to over-count. ]==]
local TALENT_LINES = {
    { "Increases your chance to hit with melee weapons by (%d+%.?%d*)%%", "hit" },
    { "Increases hit chance by (%d+%.?%d*)%%", "hit" },
    { "chance to hit with melee attacks and spells by (%d+%.?%d*)%%", "both" },
    { "chance to hit with spells and melee attacks by (%d+%.?%d*)%%", "both" },
    { "Increases your chance to get a critical strike with melee weapons by (%d+%.?%d*)%%", "crit" },
    { "Increases your critical strike chance with all attacks by (%d+%.?%d*)%%", "critAll" },
    { "Increases ranged and melee critical chance by (%d+%.?%d*)%%", "critAll" },
    { "Increases your critical strike chance with ranged weapons by (%d+%.?%d*)%%", "rangedCrit" },
}

local function readTalentLine(line, out, talent)
    for i = 1, table.getn(TALENT_LINES) do
        local _, _, found = string.find(line, TALENT_LINES[i][1])

        if found then
            local key = TALENT_LINES[i][2]
            local value = tonumber(found) or 0

            if key == "both" then
                out.hit = out.hit + value
                out.spellHit = out.spellHit + value
            elseif key == "critAll" then
                out.crit = out.crit + value
                out.rangedCrit = out.rangedCrit + value
            else
                out[key] = (out[key] or 0) + value
            end

            table.insert(out.trace, { key = key, value = value,
                                      line = line, talent = talent })
            return true
        end
    end

    return false
end

--[[ Every talent with a point in it, read once and kept for half a second,
     the way the gear is. `read` is false where the client cannot show a
     talent tooltip at all, and the rows say gear-only in that case. ]]--
function M:TalentBonuses(force)
    local now = (type(GetTime) == "function" and GetTime()) or 0

    if not force and self.talents and (now - (self.talentsAt or -1)) < 0.5 then
        return self.talents
    end

    local out = { hit = 0, crit = 0, spellHit = 0, rangedCrit = 0, read = false,
                  trace = {} }

    local tip = type(OB.ScanTooltip) == "function" and OB.ScanTooltip()
    local nextRank = TOOLTIP_TALENT_NEXT_RANK or "Next rank:"

    if tip and tip.SetTalent and type(GetNumTalentTabs) == "function"
            and type(GetNumTalents) == "function"
            and type(GetTalentInfo) == "function"
            and type(OB.ScanLine) == "function" then
        out.read = true

        for tab = 1, (GetNumTalentTabs() or 0) do
            for index = 1, (GetNumTalents(tab) or 0) do
                local _, _, _, _, rank = GetTalentInfo(tab, index)

                if type(rank) == "number" and rank > 0 then
                    if tip.ClearLines then tip:ClearLines() end
                    tip:SetTalent(tab, index)

                    local talent = OB.ScanLine(1)

                    for i = 1, scanCount(tip) do
                        local line = OB.ScanLine(i)
                        if not line or line == nextRank
                                or string.find(line, "^Next rank") then
                            break
                        end
                        readTalentLine(line, out, talent)
                    end
                end
            end
        end
    end

    self.talents, self.talentsAt = out, now
    return out
end

--[==[ **The client's own melee crit, where it prints one.**

     This client's spellbook tooltip for Attack carries "X% chance to crit" --
     the server's whole number, agility and gear and talents and buffs, nothing
     for this addon to work out or get wrong. Read when it is there and
     preferred over every sum below; absent on a client that does not print
     it, in which case the sum stands. ]==]
function M:SpellbookCrit()
    if type(GetSpellName) ~= "function" then return nil end

    local tip = type(OB.ScanTooltip) == "function" and OB.ScanTooltip()
    if not tip or not tip.SetSpell or type(OB.ScanLine) ~= "function" then return nil end

    local attack = ATTACK or "Attack"
    local i = 1

    while i < 400 do
        local name = GetSpellName(i, BOOKTYPE_SPELL or "spell")
        if not name then break end

        if name == attack then
            if tip.ClearLines then tip:ClearLines() end
            tip:SetSpell(i, BOOKTYPE_SPELL or "spell")

            for l = 1, scanCount(tip) do
                local line = OB.ScanLine(l)
                if not line then break end

                local _, _, found = string.find(line, "(%d+%.?%d*)%% chance to crit")
                if found then return tonumber(found) end
            end
            return nil
        end

        i = i + 1
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- what the buffs say
-- ---------------------------------------------------------------------------

--[==[ **Hit from what is on you right now**, which is neither gear nor a
     talent and is still the chance to hit. A food that grants hit is hit
     while it lasts; a swarm of insects takes hit away while it lasts. Both
     are on the buff tooltips in a few sentences, the same ones
     BetterCharacterStats reads, and nothing looser is matched. ]==]
local AURA_LINES = {
    { "Chance to hit increased by (%d+%.?%d*)%%", "hit" },
    { "Improves your chance to hit by (%d+%.?%d*)%%", "hit" },
    { "Increases attack power by %d+ and chance to hit by (%d+%.?%d*)%%", "hit" },
    { "Chance to hit reduced by (%d+%.?%d*)%%", "hitDebuff" },
    { "Chance to hit decreased by (%d+%.?%d*)%%", "hitDebuff" },
}

local BUFF_SLOTS, DEBUFF_SLOTS = 32, 16

local function readAuraLine(line, out, aura)
    for i = 1, table.getn(AURA_LINES) do
        local _, _, found = string.find(line, AURA_LINES[i][1])

        if found then
            local key = AURA_LINES[i][2]
            local value = tonumber(found) or 0

            out[key] = (out[key] or 0) + value
            table.insert(out.trace, { key = key, value = value,
                                      line = line, aura = aura })
            return true
        end
    end

    return false
end

function M:AuraBonuses(force)
    local now = (type(GetTime) == "function" and GetTime()) or 0

    if not force and self.auras and (now - (self.aurasAt or -1)) < 0.5 then
        return self.auras
    end

    local out = { hit = 0, hitDebuff = 0, read = false, trace = {} }

    local tip = type(OB.ScanTooltip) == "function" and OB.ScanTooltip()

    if tip and tip.SetPlayerBuff and type(GetPlayerBuff) == "function"
            and type(OB.ScanLine) == "function" then
        out.read = true

        local passes = { { "HELPFUL", BUFF_SLOTS }, { "HARMFUL", DEBUFF_SLOTS } }

        for p = 1, 2 do
            local filter, slots = passes[p][1], passes[p][2]

            for position = 0, slots - 1 do
                local index = GetPlayerBuff(position, filter)
                if type(index) ~= "number" or index < 0 then break end

                if tip.ClearLines then tip:ClearLines() end
                tip:SetPlayerBuff(index)

                local aura = OB.ScanLine(1)

                for i = 1, scanCount(tip) do
                    local line = OB.ScanLine(i)
                    if not line then break end
                    readAuraLine(line, out, aura)
                end
            end
        end
    end

    self.auras, self.aurasAt = out, now
    return out
end

--[[ Gear plus talents where both scans ran, gear alone where only that one
     did, nothing where neither could. Melee and ranged hit take the buffs
     on top and the debuffs off, and never go below nothing. ]]--
local function hitTotal(gearKey, talentKey)
    local gear = M:GearBonuses()
    if not gear or not gear.read then return nil end

    local total = gear[gearKey] or 0
    local talents = M:TalentBonuses()
    if talents and talents.read then total = total + (talents[talentKey] or 0) end

    if gearKey == "hit" then
        local auras = M:AuraBonuses()
        if auras and auras.read then
            total = total + (auras.hit or 0) - (auras.hitDebuff or 0)
        end
        if total < 0 then total = 0 end
    end

    return total
end

-- ---------------------------------------------------------------------------
-- where a number came from
-- ---------------------------------------------------------------------------

--[[ Each contribution the scans traced, as a line, for the keys asked. ]]--
local function tracedLines(lines, list, keys, from)
    for i = 1, table.getn(list or {}) do
        local t = list[i]

        if keys[t.key] then
            local sign = (t.key == "hitDebuff") and "-" or "+"
            table.insert(lines, "  " .. from(t) .. ": " .. sign .. tostring(t.value) .. "%")
        end
    end
end

local function itemName(t) return tostring(t.item) end
local function talentName(t) return tostring(t.talent) end
local function auraName(t) return tostring(t.aura) end

--[[ Gear, talents and buffs, each with the lines behind it. `ranged` adds
     the scope. ]]--
local function explainHit(ranged)
    return function()
        local lines = {}
        local keys = { hit = true, both = true }
        if ranged then keys.rangedHit = true end

        local gear = M:GearBonuses()
        if gear and gear.read then
            local total = (gear.hit or 0) + (ranged and (gear.rangedHit or 0) or 0)
            table.insert(lines, "Gear: " .. statPercent(total))
            tracedLines(lines, gear.trace, keys, itemName)
        else
            table.insert(lines, "Gear: could not be read on this client")
        end

        local talents = M:TalentBonuses()
        if talents and talents.read then
            table.insert(lines, "Talents: " .. statPercent(talents.hit or 0))
            tracedLines(lines, talents.trace, { hit = true, both = true }, talentName)
        else
            table.insert(lines, "Talents: could not be read on this client")
        end

        local auras = M:AuraBonuses()
        if auras and auras.read and ((auras.hit or 0) > 0 or (auras.hitDebuff or 0) > 0) then
            table.insert(lines, "Buffs: "
                    .. statPercent((auras.hit or 0) - (auras.hitDebuff or 0)))
            tracedLines(lines, auras.trace, { hit = true, hitDebuff = true }, auraName)
        end

        return lines
    end
end

--[[ One gear total by key -- the spell page's hit and crit. ]]--
local function explainGear(key)
    return function()
        local lines = {}
        local gear = M:GearBonuses()

        if gear and gear.read then
            table.insert(lines, "Gear: " .. statPercent(gear[key] or 0))
            tracedLines(lines, gear.trace, { [key] = true, both = (key == "spellHit") or nil },
                    itemName)
        else
            table.insert(lines, "Gear: could not be read on this client")
        end

        return lines
    end
end

--[[ Crit: whichever answered -- the client, the Attack tooltip, or the sum
     of agility, gear and talents. ]]--
local function explainCrit()
    local lines = {}

    local crit = ask("GetCritChance")
    if type(crit) ~= "number" then crit = ask("GetMeleeCritChance") end
    if type(crit) == "number" then
        table.insert(lines, "From the client's own crit call")
        return lines
    end

    local book = M:SpellbookCrit()
    if type(book) == "number" then
        table.insert(lines, "From the Attack tooltip, which is the whole number")
        return lines
    end

    local agility = M:CritFromAgility()
    table.insert(lines, "Agility: " .. (agility and statPercent(agility) or "no constants for this class"))

    local gear = M:GearBonuses()
    if gear and gear.read then
        table.insert(lines, "Gear: " .. statPercent(gear.crit or 0))
        tracedLines(lines, gear.trace, { crit = true }, itemName)
    end

    local talents = M:TalentBonuses()
    if talents and talents.read then
        table.insert(lines, "Talents: " .. statPercent(talents.crit or 0))
        tracedLines(lines, talents.trace, { crit = true, critAll = true }, talentName)
    end

    return lines
end

--[==[ **Crit is mostly agility, and this sheet was showing only the gear.**

     Reported plainly: "it showed hit and crit 4%, but that's from gear, not real
     chance". Right about crit. A level 58 rogue's crit is overwhelmingly the
     agility already on the character sheet, and the couple of percent from
     suffixes is the small half.

     **Hit is a different case and the row is not wrong.** Vanilla has no base
     hit stat at all -- your chance to miss comes from weapon skill against the
     target's defence, which this panel already works out under "Boss Miss". The
     only thing that adds *hit* is gear, so "Hit (gear)" is the whole number and
     the parenthesis is the misleading part rather than the value.

     **The conversion**, per class, as a pair of agility-per-crit figures at
     level 1 and level 60 with a straight interpolation between them, plus a flat
     base for the three casters that have one. These are the server's own
     constants -- vmangos core, which is also where BetterCharacterStats takes
     them from, and its comment says so. Numbers, not code: nothing of BCS is
     copied here, and it ships no licence to copy under.

     The three missing classes are missing on purpose. Paladin, shaman and druid
     take twenty agility per point of crit at sixty, which is the well-known
     figure, but no source here gives their level-1 rate -- so rather than
     interpolate through a guess they get no agility term and the row says gear
     only, which is what it says today.

     **Talents are still not in this.** A crit talent is readable only by walking
     the spellbook and reading every tooltip, which is a pass of its own with a
     cache of its own. Left out and labelled rather than silently missing. ]==]
local CRIT_AGILITY = {
    WARRIOR = { 3.9, 20 },
    ROGUE   = { 2.2, 29 },
    HUNTER  = { 3.5, 53 },
    MAGE    = { 12.9, 20 },
    PRIEST  = { 11, 20 },
    WARLOCK = { 8.4, 20 },
}

--[[ The flat percentage three classes start with before any agility. ]]--
local CRIT_BASE = { MAGE = 3.2, PRIEST = 3, WARLOCK = 2 }

function M:CritFromAgility()
    if type(UnitClass) ~= "function" or type(UnitStat) ~= "function" then
        return nil
    end

    local _, class = UnitClass("player")
    local pair = class and CRIT_AGILITY[class]
    if not pair then return nil end

    local level = (type(UnitLevel) == "function" and UnitLevel("player")) or 60
    if type(level) ~= "number" or level < 1 then level = 1 end

    --[[ Interpolated across the sixty levels, which is how the server does it:
         the same agility is worth more crit at low level. ]]--
    local rate = (pair[1] * (60 - level) / 59) + (pair[2] * (level - 1) / 59)
    if not rate or rate <= 0 then return nil end

    local _, agility = UnitStat("player", 2)
    if type(agility) ~= "number" then return nil end

    return (agility / rate) + (CRIT_BASE[class] or 0)
end

--[[ A gear total as a row, or nothing at all where the scan could not run --
     which is the difference between "your gear grants none" and "this client
     cannot say". ]]--
local function gearPercent(key)
    local gear = M:GearBonuses()
    if not gear or not gear.read then return nil end

    return statPercent(gear[key] or 0)
end

-- ---------------------------------------------------------------------------
-- the numbers a boss fight is actually decided by
-- ---------------------------------------------------------------------------

--[==[ **A level 63 mob has 315 defense, and every melee number changes.**

     Your miss chance against a boss is not the one on the character sheet: it
     comes out of your weapon skill against its defense, and it is what decides
     whether the hit on your gear is doing anything. Same for the crit cap --
     miss, dodge and glancing take their share of the swing table first, and crit
     above what is left is crit you paid for and never see.

     **Turtle changed these**, and the client says so: `TURTLE_WOW_VERSION` is a
     global on this server and not on a stock 1.12, so both sets are here and the
     client picks. Getting that wrong is a number that is plausible, wrong, and
     gear-changing. ]==]
local BOSS_DEFENSE = 315
local BOSS_LEVELS = 3

--[[ Glancing blows are 40% of a boss swing table and cannot be avoided. ]]--
local GLANCE_CHANCE = 40

local function onTurtle()
    return TURTLE_WOW_VERSION ~= nil
end

--[[ Main and off hand weapon skill, which is what the client answers when asked
     about both hands: base plus whatever is modifying it. ]]--
function M:WeaponSkills()
    local mainBase, mainMod, offBase, offMod = ask("UnitAttackBothHands", "player")
    if type(mainBase) ~= "number" then return nil end

    local main = mainBase + (mainMod or 0)
    local off = type(offBase) == "number" and offBase > 0
            and (offBase + (offMod or 0)) or nil

    return main, off
end

function M:BossMiss(skill, dual)
    if type(skill) ~= "number" then return nil end

    --[[ The whole of hit -- gear, talents, buffs -- and not the gear alone,
         which read a miss three points too high for a rogue with Precision
         while the melee page beside it counted the talent. ]]--
    local hit = hitTotal("hit", "hit") or 0
    local diff = skill - BOSS_DEFENSE
    local miss

    if onTurtle() then
        miss = 5 - (diff * 0.2) - hit
    else
        --[[ Stock 1.12 charges double for the first ten points under the cap
             and takes one point off your hit as well, which is the rule that
             made 305 skill matter so much. ]]--
        if diff < -10 then
            miss = 5 - (diff * 0.2)
            if hit > 0 then hit = hit - 1 end
        else
            miss = 5 - (diff * 0.1)
        end

        miss = miss - hit
    end

    if dual then miss = miss + 19 end

    if miss < 0 then miss = 0 end
    if miss > 60 then miss = 60 end

    return miss
end

function M:BossDodge(skill)
    if type(skill) ~= "number" then return nil end

    local dodge = 5 + ((BOSS_DEFENSE - skill) * 0.1)
    if dodge < 0 then dodge = 0 end

    return dodge
end

--[[ What a glancing blow lands for, which is the one number here that is a
     damage figure rather than a chance. ]]--
function M:GlancingDamage(skill)
    if type(skill) ~= "number" then return nil end

    if onTurtle() then return 65 + ((skill - 300) * 2) end

    local diff = BOSS_DEFENSE - skill
    local low = math.max(math.min(1.3 - (0.05 * diff), 0.91), 0.01)
    local high = math.max(math.min(1.2 - (0.03 * diff), 0.99), 0.2)

    return 100 * (((high - low) / 2) + low)
end

--[[ What is left of the swing table once miss, dodge and glancing have taken
     theirs. Crit above this is crit that cannot happen. ]]--
function M:CritCap(skill, dual)
    local miss = self:BossMiss(skill, dual)
    local dodge = self:BossDodge(skill)
    if not miss or not dodge then return nil end

    local cap = 100 - miss - dodge - GLANCE_CHANCE

    if cap < 0 then cap = 0 end
    if cap > 100 then cap = 100 end

    return cap
end

--[[ Avoidance against something three levels above you: each level takes five
     points of its attack skill over yours, and each of those is 0.04% off
     everything you dodge, parry or block with. ]]--
function M:AvoidanceVs(value, levels)
    if type(value) ~= "number" then return nil end

    local adjusted = value - ((5 * (levels or 0)) * 0.04)
    if adjusted < 0 then adjusted = 0 end

    return adjusted
end

--[[ Both hands where there are two, one number where there is one -- a dual
     wielder has two of every melee answer and a two-hander has one. ]]--
local function pairPercent(fn)
    local main, off = M:WeaponSkills()
    if not main then return nil end

    local a = fn(main, off ~= nil)
    if type(a) ~= "number" then return nil end

    if not off then return statPercent(a) end

    local b = fn(off, true)
    if type(b) ~= "number" or math.abs(a - b) < 0.005 then return statPercent(a) end

    return string.format("%.1f%% | %.1f%%", a, b)
end

--[==[ **The groups, and what each row asks.**

     A row is `{ label, fn }` and `fn` answers a string or nothing. Nothing means
     the row is left out entirely -- see the note above about guessing.

     The order inside a group is the order somebody reads them in, which is not
     the order the client's API happens to return: weapon skill first in melee,
     because it is the one that decides whether the rest of the numbers land. ]==]
local STAT_GROUPS = {
    {
        id = "base",
        label = "Base Stats",
        rows = {
            { "Strength",  function() return statNumber((ask("UnitStat", "player", 1))) end },
            { "Agility",   function() return statNumber((ask("UnitStat", "player", 2))) end },
            { "Stamina",   function() return statNumber((ask("UnitStat", "player", 3))) end },
            { "Intellect", function() return statNumber((ask("UnitStat", "player", 4))) end },
            { "Spirit",    function() return statNumber((ask("UnitStat", "player", 5))) end },

            --[[ `UnitArmor` answers five values and the *second* is the one on
                 the character sheet: base is before buffs, effective is what
                 mitigates. Reading the first is the classic mistake here and it
                 is invisible until somebody buffs. ]]--
            { "Armor", function()
                local _, effective = ask("UnitArmor", "player")
                return statNumber(effective)
            end },
        },
    },

    {
        id = "melee",
        label = "Melee",
        rows = {
            --[[ `UnitAttackBothHands` answers main base, main modifier, off
                 base, off modifier -- the pair people call "weapon skill". Shown
                 as two numbers because a dual wielder has two, and as one when
                 they agree. ]]--
            { "Wep Skill", function()
                local mainBase, mainMod, offBase, offMod =
                        ask("UnitAttackBothHands", "player")

                if type(mainBase) ~= "number" then return nil end

                local main = mainBase + (mainMod or 0)
                local off = type(offBase) == "number"
                        and (offBase + (offMod or 0)) or nil

                if off == 0 then off = nil end
                return statPair(main, off)
            end },

            { "Damage", function()
                local low, high = ask("UnitDamage", "player")
                if type(low) ~= "number" then return nil end
                return statNumber(low) .. "-" .. statNumber(high)
            end },

            { "Speed", function()
                local main, off = ask("UnitAttackSpeed", "player")
                if type(main) ~= "number" then return nil end

                local text = string.format("%.2f", main)
                if type(off) == "number" and off > 0 then
                    text = text .. " | " .. string.format("%.2f", off)
                end

                return text
            end },

            { "Power", function()
                local base, pos, neg = ask("UnitAttackPower", "player")
                if type(base) ~= "number" then return nil end
                return statNumber(base + (pos or 0) + (neg or 0))
            end },

            --[==[ **Hit and crit, where the client has them.**

                 Neither is on 1.12's own character sheet, which is the whole
                 reason this module exists -- and neither is guaranteed to be
                 askable. Several names are tried because the forks disagree:
                 `GetHitModifier` and `GetCritChance` are the 2.0 spellings that
                 some 1.12 servers have back-ported.

                 Nothing answering means no row, not a zero. ]==]
            --[[ The call first, where a fork has one, and the gear scan
                 behind it -- which is what answers on this client. ]]--
            --[[ Gear and talents, which between them are every point of hit
                 a vanilla character has: there is no base hit stat, and no
                 buff grants it. The "(gear)" that used to be on this label
                 was true when talents were not read; it is not any more. ]]--
            { "Hit", function()
                local hit = ask("GetHitModifier")
                if type(hit) ~= "number" then hit = ask("GetHitRating") end
                if type(hit) == "number" then return statPercent(hit) end

                local total = hitTotal("hit", "hit")
                if not total then return nil end
                return statPercent(total)
            end, explainHit(false) },

            --[==[ **The client's own answer wherever it has one** -- a fork's
                 call, or the crit this client prints on the Attack tooltip --
                 and agility plus gear plus talents where it has neither. ]==]
            { "Crit", function()
                local crit = ask("GetCritChance")
                if type(crit) ~= "number" then crit = ask("GetMeleeCritChance") end
                if type(crit) ~= "number" then crit = M:SpellbookCrit() end
                if type(crit) == "number" then return statPercent(crit) end

                local agility = M:CritFromAgility()
                if not agility then return nil end

                local gear = M:GearBonuses()
                local extra = (gear and gear.read and gear.crit) or 0

                local talents = M:TalentBonuses()
                if talents and talents.read then extra = extra + (talents.crit or 0) end

                return statPercent(agility + extra)
            end, explainCrit },
        },
    },

    --[==[ **The same fight, against something that fights back at 315.**

         Every number here is the melee group re-asked against a level 63 mob,
         which is the only version of it that decides anything in a raid. ]==]
    {
        id = "meleeboss",
        label = "Melee vs Boss",
        rows = {
            { "Wep Skill", function()
                local main, off = M:WeaponSkills()
                if not main then return nil end
                return statPair(main, off)
            end },

            { "Miss", function()
                return pairPercent(function(skill, dual)
                    return M:BossMiss(skill, dual)
                end)
            end },

            { "Dodged", function()
                return pairPercent(function(skill) return M:BossDodge(skill) end)
            end },

            { "Glancing", function()
                local main = M:WeaponSkills()
                return statPercent(M:GlancingDamage(main))
            end },

            { "Crit Cap", function()
                return pairPercent(function(skill, dual)
                    return M:CritCap(skill, dual)
                end)
            end },
        },
    },

    {
        id = "ranged",
        label = "Ranged",
        rows = {
            { "Wep Skill", function()
                local base, mod = ask("UnitRangedAttack", "player")
                if type(base) ~= "number" then return nil end
                return statNumber(base + (mod or 0))
            end },

            { "Damage", function()
                local _, low, high = ask("UnitRangedDamage", "player")
                if type(low) ~= "number" then return nil end
                return statNumber(low) .. "-" .. statNumber(high)
            end },

            { "Speed", function()
                local speed = ask("UnitRangedDamage", "player")
                if type(speed) ~= "number" then return nil end
                return string.format("%.2f", speed)
            end },

            { "Power", function()
                local base, pos, neg = ask("UnitRangedAttackPower", "player")
                if type(base) ~= "number" then return nil end
                return statNumber(base + (pos or 0) + (neg or 0))
            end },

            --[==[ **Ranged crit is the same sum as melee crit**, and from the
                 same agility: the server's conversion does not distinguish the
                 two. So where no fork answers, it is worked out rather than
                 dropped -- see `CRIT_AGILITY`. ]==]
            { "Crit Chance", function()
                local asked = ask("GetRangedCritChance")
                if type(asked) == "number" then return statPercent(asked) end

                local agility = M:CritFromAgility()
                if not agility then return nil end

                local gear = M:GearBonuses()
                local extra = (gear and gear.read and gear.crit) or 0

                local talents = M:TalentBonuses()
                if talents and talents.read then extra = extra + (talents.rangedCrit or 0) end

                return statPercent(agility + extra)
            end },

            --[[ Everything that says "hit", the talents, and the scope, which
                 only a ranged attack sees. ]]--
            { "Hit", function()
                local total = hitTotal("hit", "hit")
                if not total then return nil end

                local gear = M:GearBonuses()
                return statPercent(total + ((gear and gear.rangedHit) or 0))
            end, explainHit(true) },
        },
    },

    --[==[ **What the spell side of a character is made of**, which 1.12 shows
         nowhere at all -- there is no spell power on the paper doll, and a
         caster's entire gearing question is a number the interface refuses to
         print. ]==]
    {
        id = "spell",
        label = "Spells",
        rows = {
            --[[ The call where the client has one -- `GetSpellBonusDamage` is
                 among the few things the loaded libraries do add -- and the
                 gear total where it does not. ]]--
            { "Spell Power", function()
                local power = ask("GetSpellBonusDamage")
                if type(power) == "number" then return statNumber(power) end

                local gear = M:GearBonuses()
                if not gear or not gear.read then return nil end

                return statNumber(gear.spellPower or 0)
            end },

            { "Healing", function()
                local healing = ask("GetSpellBonusHealing")
                if type(healing) == "number" then return statNumber(healing) end

                local gear = M:GearBonuses()
                if not gear or not gear.read then return nil end

                --[[ Spell power counts toward healing, which is why a healer
                     with no healing gear is not a healer with none. ]]--
                return statNumber((gear.healing or 0) + (gear.spellPower or 0))
            end },

            { "Hit (gear)", function() return gearPercent("spellHit") end,
              explainGear("spellHit") },
            { "Crit (gear)", function() return gearPercent("spellCrit") end,
              explainGear("spellCrit") },
        },
    },

    --[==[ **And the same power, school by school.**

         A staff that says "Fire spells and effects" is worth nothing to a
         frost mage, and the difference is invisible on a sheet that only totals
         them. ]==]
    {
        id = "schools",
        label = "Spell Schools",
        rows = {
            { "Arcane", function() return M:SchoolPower("Arcane") end },
            { "Fire", function() return M:SchoolPower("Fire") end },
            { "Frost", function() return M:SchoolPower("Frost") end },
            { "Holy", function() return M:SchoolPower("Holy") end },
            { "Nature", function() return M:SchoolPower("Nature") end },
            { "Shadow", function() return M:SchoolPower("Shadow") end },
        },
    },

    {
        id = "defense",
        label = "Defense",
        rows = {
            { "Armor", function()
                local _, effective = ask("UnitArmor", "player")
                return statNumber(effective)
            end },

            { "Defense", function()
                local base, mod = ask("UnitDefense", "player")
                if type(base) ~= "number" then return nil end
                return statNumber(base + (mod or 0))
            end },

            { "Dodge", function() return statPercent(ask("GetDodgeChance")) end },
            { "Parry", function() return statPercent(ask("GetParryChance")) end },
            { "Block", function() return statPercent(ask("GetBlockChance")) end },

            --[[ What all three come to, which is the number somebody tanking
                 actually watches. ]]--
            { "Avoidance", function()
                return M:TotalAvoidance(0)
            end },
        },
    },

    --[==[ **The same three, against something three levels above you.**

         A boss is level 63 and every point of avoidance on the sheet is worth
         0.6% less against it. Reading the sheet's own number and tanking on it
         is the mistake this group exists to stop. ]==]
    {
        id = "defenseboss",
        label = "Defense vs Boss",
        rows = {
            { "Armor", function()
                local _, effective = ask("UnitArmor", "player")
                return statNumber(effective)
            end },

            { "Defense", function()
                local base, mod = ask("UnitDefense", "player")
                if type(base) ~= "number" then return nil end
                return statNumber(base + (mod or 0))
            end },

            { "Dodge", function()
                return statPercent(M:AvoidanceVs(ask("GetDodgeChance"), BOSS_LEVELS))
            end },

            { "Parry", function()
                return statPercent(M:AvoidanceVs(ask("GetParryChance"), BOSS_LEVELS))
            end },

            { "Block", function()
                return statPercent(M:AvoidanceVs(ask("GetBlockChance"), BOSS_LEVELS))
            end },

            { "Avoidance", function()
                return M:TotalAvoidance(BOSS_LEVELS)
            end },
        },
    },
}

M.statGroups = STAT_GROUPS

--[[ One school's power, from the gear scan. Nothing at all where the scan could
     not run, and a nought where it ran and found none. ]]--
function M:SchoolPower(school)
    local gear = self:GearBonuses()
    if not gear or not gear.read then return nil end

    return statNumber((gear.schools and gear.schools[school]) or 0)
end

--[[ Dodge, parry and block together, at whatever level difference is being
     asked about. Missing entirely where the client cannot answer any of the
     three, rather than summing the two it can. ]]--
function M:TotalAvoidance(levels)
    local dodge = ask("GetDodgeChance")
    local parry = ask("GetParryChance")
    local block = ask("GetBlockChance")

    if type(dodge) ~= "number" and type(parry) ~= "number"
            and type(block) ~= "number" then
        return nil
    end

    local total = (self:AvoidanceVs(dodge, levels) or 0)
            + (self:AvoidanceVs(parry, levels) or 0)
            + (self:AvoidanceVs(block, levels) or 0)

    return statPercent(total)
end

--[[ A group by id, or the first one -- a saved choice can name a group that a
     later build renamed, and a panel with no rows at all is worse than a panel
     showing the wrong ones. ]]--
function M:StatGroup(id)
    for i = 1, table.getn(STAT_GROUPS) do
        if STAT_GROUPS[i].id == id then return STAT_GROUPS[i] end
    end

    return STAT_GROUPS[1]
end

--[[ The rows a group can actually fill on this client, as label/value pairs.
     Empty rows are dropped here rather than drawn blank, so the box is as tall
     as it has things to say. ]]--
--[==[ **A row that cannot be worked out says so; a row the client cannot
     answer is left out.** They were the same case, and the difference is
     the whole of three reports: a row whose function *threw* vanished as
     quietly as one whose client call did not exist, and "hit still not
     calculating" could not be told from "this client has no hit call". An
     error is a bug, and a bug drawn as an empty space is a bug nobody can
     report. Now it draws "n/a", and the row's tooltip carries the error. ]==]
function M:StatRows(id)
    local group = self:StatGroup(id)
    local out = {}

    for i = 1, table.getn(group.rows) do
        local row = group.rows[i]
        local ok, value = pcall(row[2])

        if ok and value then
            table.insert(out, { label = row[1], value = value, explain = row[3] })
        elseif not ok then
            table.insert(out, { label = row[1], value = "n/a", explain = row[3],
                                error = tostring(value) })
        end
    end

    return out
end

-- ---------------------------------------------------------------------------
-- the two boxes
-- ---------------------------------------------------------------------------

--[==[ **Two panes, each with a dropdown for what it is showing.**

     The reference this is ported from puts base stats on the left and melee on
     the right, and lets either be changed -- which is what makes four groups fit
     in the room for two. The choice is remembered per pane, so a hunter who
     wants ranged on the right gets it every time they open the sheet.

     Built on `PaperDollFrame` and sized to the space vanilla fills with its own
     two stat blocks, which are hidden while these are up. Hidden rather than
     moved: they are the client's frames and switching this module off has to put
     them back exactly, which `Restore` does by showing them again. ]==]
--[==[ **Two panes, each with the client's own dropdown on it.**

     The first build of this was wrong twice over and both faults were visible
     the moment it was on screen: the panes overlapped the paper doll and each
     other, and the header was a *cycler* -- click it and the group changed, and
     the box changed size with it. A control that resizes what it is attached to
     is a control nobody can aim at twice.

     So: a real `UIDropDownMenu`, which is the client's own widget and the thing
     somebody already knows how to use, and a **fixed** pane size chosen for the
     longest group. A shorter group leaves empty rows rather than a shorter box.

     **The client's art, not this addon's.** ECO's own skin is for the setup
     walkthrough and the options panel; anything drawn onto the client's frames
     wears the client's own furniture. That is the tooltip backdrop here, which
     is what every panel inside 1.12's windows is made of. ]==]
--[==[ **Measured off the character sheet rather than chosen.**

     The first pass picked its own numbers -- 140 wide, fourteen to a row, a box
     with the dropdown inside it -- and both panes ran under the weapon slots in
     the middle of the sheet, which is what "the text is clipping into the items"
     is. Two 140-wide boxes are 280 across plus a gap; the sheet has 230 free.

     These are `BetterCharacterStats`' numbers, which is the addon the report
     compared this against and which has occupied the same strip of the same
     window for years: two 115-wide columns, six rows of thirteen, starting 67
     across and 291 down from the paper doll's top-left corner. Eleven point
     text, which is the other half of "the text is too big" -- the client's
     small font renders at twelve.

     The dropdown sits *above* the rows rather than inside a taller box, which
     is the change that actually clears the weapon slots: the rows start where
     BCS' rows start instead of a headline lower. ]==]
local PANE_W = 115
local PANE_ROWS = 6
local ROW_H = 13

--[[ The row inside the column: BCS draws a 104-wide row 6 in from the left, so
     the label starts at 6 and the number ends 5 from the right. ]]--
local ROW_INSET = 6
--[==[ **These rows are not re-fonted at all, and that is the fix.**

     They were created from `GameFontHighlightSmall` -- the client's own
     paperdoll face at its own size -- and then immediately given this addon's
     themed face over the top. Dropping eleven to ten did not help, and could
     not: the size was never the whole of it. Roboto at ten is visibly wider and
     taller than Friz Quadrata at ten, so the rows went on reading large beside
     the client's own labels an inch away.

     The standing rule settles it rather than taste: the client's own widgets
     everywhere outside the setup walkthrough and the options panel. A stat row
     on the character sheet is as much the client's furniture as the Strength
     line above it, so it keeps the client's font object -- at the height
     `statFontSize` asks for, set in `DrawPane`. ]==]

--[[ Where the pair sits on the paper doll, from its top-left corner. ]]--
local PANE_X, PANE_Y = 67, -291

--[==[ **The client's own stat background, in the three slices it is cut into.**

     `UI-Character-StatBackground` is the art 1.12 draws behind its own
     attribute block, and this is that block: same window, same strip, same
     furniture. The coordinates are the client's own -- a cap, a body that tiles
     down the middle, and a foot -- and they are why the box has ends rather
     than a hard edge. ]==]
local STAT_ART = "Interface\\PaperDollInfoFrame\\UI-Character-StatBackground"

local STAT_SLICES = {
    { h = 16, top = 0,         bottom = 0.125 },
    { h = 53, top = 0.125,     bottom = 0.1953125 },
    { h = 16, top = 0.484375,  bottom = 0.609375 },
}

--[==[ **The pane is the art's height, and the rows sit centred in it.**

     The pane was six rows tall and the art seven pixels taller, hung from the
     pane's top -- so the rows began on the cap's rim and the slack was all at
     the foot, and each row's text hung from the top of its thirteen pixels
     with the rest below it. Both read as the text sitting high in the box,
     which is what was reported. The block of rows is centred in the art now
     and each row's text is centred in its row: no offset chosen by eye, a
     pair of midpoints. ]==]
local PANE_H = 0
for i = 1, table.getn(STAT_SLICES) do PANE_H = PANE_H + STAT_SLICES[i].h end

local ROW_TOP = math.floor((PANE_H - (PANE_ROWS * ROW_H)) / 2)

local function rowMiddle(i)
    return -(ROW_TOP + ((i - 1) * ROW_H) + math.floor(ROW_H / 2))
end

--[[ The client's own stat blocks, hidden while ours are shown. Named here
     because 1.12 has four of them and a fork may have fewer -- every one is
     asked for by name and skipped if absent. ]]--
local BLIZZ_STAT_FRAMES = {
    "CharacterAttributesFrame", "CharacterResistanceFrame",
    "PaperDollFrameStatsLeft", "PaperDollFrameStatsRight",
}

--[[ The order the dropdown lists them, which is the order somebody reads: what
     am I, what do I hit for, what do I shoot for, what happens when something
     hits me. ]]--
local GROUP_ORDER = { "base", "melee", "meleeboss", "ranged", "spell",
                      "schools", "defense", "defenseboss" }

function M:Pane(side)
    self.panes = self.panes or {}
    if self.panes[side] then return self.panes[side] end

    local parent = getglobal("PaperDollFrame")
    if not parent or not CreateFrame then return nil end

    local f = CreateFrame("Frame", "EquadisOverhaulStatPane" .. side, parent)
    f:SetWidth(PANE_W)
    f:SetHeight(PANE_H)

    --[==[ **The client's own stat background rather than a tooltip backdrop.**

         A tooltip border round a box this tight puts an edge through the top and
         bottom rows. The client already has art for exactly this block in
         exactly this window, cut into a cap, a body and a foot -- so the pane
         wears that, and the sheet ends up looking like the sheet. ]==]
    f.art = {}

    local above

    for i = 1, table.getn(STAT_SLICES) do
        local slice = STAT_SLICES[i]
        local tex = f:CreateTexture(nil, "BORDER")

        tex:SetTexture(STAT_ART)
        tex:SetWidth(PANE_W)
        tex:SetHeight(slice.h)

        if above then
            tex:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, 0)
        else
            tex:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        end

        --[[ The art is wider than the slice it is cut from, hence the right
             edge at 0.898 rather than 1. ]]--
        if tex.SetTexCoord then
            tex:SetTexCoord(0, 0.8984375, slice.top, slice.bottom)
        end

        f.art[i] = tex
        above = tex
    end

    f.ecoSide = side

    --[==[ **`UIDropDownMenu`, which is the client's own.**

         Built rather than skinned: the menu it opens, the arrow it draws and the
         way it closes when something else opens are all the client's, so this
         behaves like every other dropdown in the game without this addon having
         an opinion about any of it. ]==]
    if type(UIDropDownMenu_Initialize) == "function" then
        f.drop = CreateFrame("Frame", "EquadisOverhaulStatDrop" .. side, f,
                "UIDropDownMenuTemplate")

        --[==[ **Above the rows, not inside a taller box.**

             A dropdown inside the pane pushes every row down by its own height,
             which is how six rows ended up over the weapon slots. BCS' own
             offsets: the menu's bottom-left against the column's top-left, back
             seventeen and down eight, because a `UIDropDownMenu` carries about
             that much invisible margin on those two sides. ]==]
        f.drop:SetPoint("BOTTOMLEFT", f, "TOPLEFT", -17, -8)

        if type(UIDropDownMenu_SetWidth) == "function" then
            UIDropDownMenu_SetWidth(99, f.drop)
        end

        if type(UIDropDownMenu_JustifyText) == "function" then
            UIDropDownMenu_JustifyText("LEFT", f.drop)
        end

        UIDropDownMenu_Initialize(f.drop, function()
            local m = EquadisClassicOverhaul.modules.characterpanel
            m:BuildGroupMenu(side)
        end)
    else
        --[[ A client with no dropdown widget still gets a label, because a
             pane with no title is a box of numbers about nothing. ]]--
        f.title = OB.NewText(f, "OVERLAY", "GameFontNormalSmall")
        f.title:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 4, 2)
    end

    --[[ One label and one value per row, built to the longest group so a change
         of group is a rewrite rather than a rebuild. ]]--
    f.rows = {}

    for i = 1, PANE_ROWS do
        local row = {}

        row.label = OB.NewText(f, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", f, "TOPLEFT", ROW_INSET, rowMiddle(i))

        row.value = OB.NewText(f, "OVERLAY", "GameFontHighlightSmall")
        row.value:SetPoint("RIGHT", f, "TOPRIGHT", -(ROW_INSET - 1), rowMiddle(i))

        --[[ Green on the values, which is the client's own colour for a stat on
             the character sheet and what makes the column read as numbers. ]]--
        row.value:SetTextColor(0.30, 0.85, 0.35)

        --[==[ **The row takes the mouse, for the tooltip that says where the
             number came from** -- see `RowTooltip`. BetterCharacterStats has
             one on every row and it is the half of a stat sheet that makes
             the other half believable: a hit figure with the items, talents
             and buffs behind it listed underneath is a figure that can be
             checked against the bags. ]==]
        row.hover = CreateFrame("Frame", nil, f)
        row.hover:SetWidth(PANE_W)
        row.hover:SetHeight(ROW_H)
        row.hover:SetPoint("TOP", f, "TOP", 0, rowMiddle(i) + math.floor(ROW_H / 2))
        row.hover:EnableMouse(true)
        row.hover.ecoPane = f
        row.hover.ecoIndex = i

        row.hover:SetScript("OnEnter", function()
            local m = EquadisClassicOverhaul.modules.characterpanel
            m:RowTooltip(this.ecoPane, this.ecoIndex)
        end)
        row.hover:SetScript("OnLeave", function()
            if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
        end)

        row.label:Hide()
        row.value:Hide()
        row.hover:Hide()

        f.rows[i] = row
    end

    self.panes[side] = f
    return f
end

--[[ The menu's entries, built when the client asks for them. One per group,
     ticked on the one showing, and choosing one writes it and redraws. ]]--
function M:BuildGroupMenu(side)
    if type(UIDropDownMenu_AddButton) ~= "function" then return false end

    local at = self:PaneGroup(side)

    for i = 1, table.getn(GROUP_ORDER) do
        local id = GROUP_ORDER[i]
        local group = self:StatGroup(id)

        local info = {}
        info.text = group.label
        info.value = id
        info.checked = (id == at) and true or nil

        info.func = function()
            EquadisClassicOverhaul.modules.characterpanel:SetPaneGroup(side, id)
        end

        UIDropDownMenu_AddButton(info)
    end

    return true
end

--[[ Which group a pane is showing. Stored per side, defaulted to the pair the
     reference uses -- base stats beside melee, which answers "what am I" and
     "what do I hit for" at the same time. ]]--
function M:PaneGroup(side)
    local cfg = self:Config()
    local key = (side == "left") and "leftGroup" or "rightGroup"

    return cfg[key] or ((side == "left") and "base" or "melee")
end

function M:SetPaneGroup(side, id)
    local cfg = self:Config()
    cfg[(side == "left") and "leftGroup" or "rightGroup"] = id

    self:ApplyStats()
    return true
end

--[==[ **Drawn, or put away entirely.**

     Switching the module off has to leave the client's own sheet exactly as it
     was, so this shows Blizzard's stat blocks again rather than leaving two
     empty holes where they used to be. ]==]
function M:ApplyStats()
    local wanted = OB.ModuleEnabled("characterpanel")
            and self:Config().statPanes

    local left, right = self:Pane("left"), self:Pane("right")
    if not left or not right then return false end

    for i = 1, table.getn(BLIZZ_STAT_FRAMES) do
        local frame = getglobal(BLIZZ_STAT_FRAMES[i])

        if frame then
            if wanted then frame:Hide() else frame:Show() end
        end
    end

    if not wanted then
        left:Hide()
        right:Hide()
        return false
    end

    --[==[ **Where the client's own attribute block is, to the pixel.**

         Centred under the model was a guess, and it put both panes under the
         weapon slots. This is measured: 67 across and 291 down from the paper
         doll's top-left, two 115-wide columns side by side, which is the strip
         the client leaves free for exactly this and where every addon that has
         ever replaced this block puts it. ]==]
    local doll = getglobal("PaperDollFrame")

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", doll, "TOPLEFT", PANE_X, PANE_Y)

    right:ClearAllPoints()
    right:SetPoint("TOPLEFT", doll, "TOPLEFT", PANE_X + PANE_W, PANE_Y)

    self:DrawPane(left, self:PaneGroup("left"))
    self:DrawPane(right, self:PaneGroup("right"))

    left:Show()
    right:Show()

    return true
end

function M:DrawPane(pane, groupId)
    if not pane then return false end

    local group = self:StatGroup(groupId)
    local rows = self:StatRows(groupId)

    --[[ Kept for the tooltips: what each row is showing and how it got it. ]]--
    pane.drawn = rows

    --[[ The dropdown's own text where there is one, a plain label where the
         client has no such widget. ]]--
    if pane.drop and type(UIDropDownMenu_SetText) == "function" then
        UIDropDownMenu_SetText(group.label, pane.drop)
    elseif pane.title then
        pane.title:SetText(group.label)
    end

    --[[ The client's own face at the configured size: the path is read back
         off the string so the face never changes, only the height. Set only
         when it differs, because SetFont re-measures the string. ]]--
    local size = tonumber(self:Config().statFontSize) or 8

    local function sized(text)
        if text and text.eqEcoStatSize ~= size and text.GetFont and text.SetFont then
            local face, _, flags = text:GetFont()
            text:SetFont(face or STANDARD_TEXT_FONT, size, flags)
            text.eqEcoStatSize = size
        end
    end

    --[[ The dropdown's own label too -- the biggest text on the pane, and
         "the stat text is too high" is said of the pane as a whole. ]]--
    if pane.drop and pane.drop.GetName and pane.drop:GetName() then
        sized(getglobal(pane.drop:GetName() .. "Text"))
    end
    sized(pane.title)

    for i = 1, table.getn(pane.rows) do
        local row = pane.rows[i]
        local data = rows[i]

        if data then
            sized(row.label)
            sized(row.value)

            row.label:SetText(data.label .. ":")
            row.value:SetText(data.value)

            row.label:Show()
            row.value:Show()
            if row.hover then row.hover:Show() end
        else
            --[[ Hidden rather than shrinking the box: a pane that changes size
                 with its dropdown is a control that moves while it is being
                 used. ]]--
            row.label:Hide()
            row.value:Hide()
            if row.hover then row.hover:Hide() end
        end
    end

    return true
end

--[==[ **Where the number came from, on the row itself.**

     The value line first, then whatever the row's `explain` lists -- for hit,
     every item, talent and buff that put a point in, by name -- and, for a
     row that could not be worked out, the error that stopped it. This is
     `/eq statdebug` on the sheet, where the question is asked. ]==]
function M:RowTooltip(pane, index)
    local data = pane and pane.drawn and pane.drawn[index]
    local row = pane and pane.rows and pane.rows[index]

    if not data or not row or not GameTooltip or not GameTooltip.AddLine then
        return false
    end

    OB.OwnTooltip(row.hover, "ANCHOR_RIGHT")
    GameTooltip:AddLine(data.label .. ": " .. tostring(data.value), 1, 1, 1)

    if data.explain then
        local ok, lines = pcall(data.explain)

        if ok and type(lines) == "table" then
            for i = 1, table.getn(lines) do
                GameTooltip:AddLine(lines[i], 0.8, 0.8, 0.8)
            end
        end
    end

    if data.error then
        GameTooltip:AddLine("Could not be worked out:", 1, 0.4, 0.4)
        GameTooltip:AddLine(data.error, 1, 0.6, 0.6, 1)
    end

    GameTooltip:Show()
    return true
end

--[==[ **Which calls this client actually has.**

     The two stats worth porting are the two the forks disagree about, and
     guessing which spelling a given server uses is how a character sheet ends up
     with a row that never fills in. This says what is there. ]==]
--[==[ **Redrawn when the numbers can have changed**, which on a character sheet
     is whenever anything is equipped, a buff lands, or a level is gained. The
     sheet is not open most of the time, so this costs nothing while it is
     shut. ]==]
function M:OnEvent()
    if not getglobal("PaperDollFrame") then return end
    self:ApplyStats()
end

function M:OnBind()
    self:ApplyStats()
end

function M:OnUnbind()
    if not self.panes then return end

    --[[ Switching the module off puts the client's own blocks back, which
         `ApplyStats` does when it finds the module disabled. ]]--
    self:ApplyStats()
end

function M:AfterSet()
    self:ApplyStats()
end

function M:DebugStats()
    OB.Print("character sheet stats:", "Character Panel")

    local NAMES = {
        "UnitStat", "UnitArmor", "UnitDefense", "UnitAttackPower",
        "UnitRangedAttackPower", "UnitDamage", "UnitRangedDamage",
        "UnitAttackSpeed", "UnitAttackBothHands", "UnitRangedAttack",
        "GetCritChance", "GetMeleeCritChance", "GetRangedCritChance",
        "GetSpellCritChance", "GetHitModifier", "GetHitRating",
        "GetDodgeChance", "GetParryChance", "GetBlockChance",
    }

    --[==[ **One of these takes a second argument, and this asked it without.**

         `UnitStat(unit, index)` wants to know *which* stat, so `UnitStat("player")`
         answers nil -- and the report duly printed `UnitStat: yes -> nil`, which
         reads as a client that cannot answer its own strength. It answers fine:
         the Base Stats group below it draws six rows of six, all of them from
         that call.

         A diagnostic that lies is worse than no diagnostic, because it is
         believed. Asked for strength now, which is a number every character
         has. ]==]
    local EXTRA = { UnitStat = 1 }

    for i = 1, table.getn(NAMES) do
        local name = NAMES[i]
        local has = type(getglobal(name)) == "function"

        local answer = ""
        if has then
            local a = ask(name, "player", EXTRA[name])
            answer = "  -> " .. tostring(a)
        end

        OB.Raw("  " .. name .. ": " .. (has and "yes" or "no") .. answer)
    end

    --[==[ **And what the sheet works out for itself**, which is the half no
         client call covers: crit is agility plus gear, and neither of those is
         a question you can put to the client directly. ]==]
    local agility = self:CritFromAgility()
    local gear = self:GearBonuses()

    OB.Raw("  crit from agility: " .. tostring(agility)
            .. (agility and "" or "  (no exact constants for this class)"))
    OB.Raw("  gear scan ran: " .. tostring(gear and gear.read)
            .. "   hit " .. tostring(gear and gear.hit)
            .. "   crit " .. tostring(gear and gear.crit))

    --[==[ **Every line the totals came from**, because a wrong total is
         settled by the lines behind it and not by the total. Two rounds of
         "hit isn't counting properly" were answered with pattern work when
         the lines being read belonged to the previous item; this would have
         shown that on the first screenshot. ]==]
    local talents = self:TalentBonuses()
    local auras = self:AuraBonuses()

    local function traced(list, from)
        for i = 1, table.getn(list) do
            local t = list[i]
            OB.Raw("    " .. from(t) .. ": " .. t.key .. " +" .. tostring(t.value)
                    .. "   \"" .. tostring(t.line) .. "\"")
        end
    end

    OB.Raw("  read from gear:" .. (table.getn(gear.trace) == 0 and " nothing" or ""))
    traced(gear.trace, function(t)
        return "slot " .. tostring(t.slot) .. " " .. tostring(t.item)
    end)

    OB.Raw("  read from talents (" .. tostring(talents and talents.read) .. "):"
            .. ((not talents or table.getn(talents.trace) == 0) and " nothing" or ""))
    if talents then
        traced(talents.trace, function(t) return tostring(t.talent) end)
    end

    OB.Raw("  read from buffs (" .. tostring(auras and auras.read) .. "):"
            .. ((not auras or table.getn(auras.trace) == 0) and " nothing" or ""))
    if auras then
        traced(auras.trace, function(t) return tostring(t.aura) end)
    end

    --[[ And what each group would draw, which is the question behind the
         question: a call existing and a row filling are not the same thing. ]]--
    for i = 1, table.getn(STAT_GROUPS) do
        local group = STAT_GROUPS[i]
        local rows = self:StatRows(group.id)

        --[==[ **And which ones are missing, by name.**

             "7 of 8 rows" says a row did not draw and not which, so the one
             question it is asked -- why is there no crit line -- it cannot
             answer. A row is absent when its own function returns nothing,
             which is deliberate: a blank row says the client does not know,
             where a zero would be read and acted on. ]==]
        local drawn = {}
        for r = 1, table.getn(rows) do drawn[rows[r].label] = true end

        local absent = {}
        for r = 1, table.getn(group.rows) do
            local label = group.rows[r][1]
            if label and not drawn[label] then table.insert(absent, label) end
        end

        OB.Raw("  " .. group.label .. ": " .. table.getn(rows)
                .. " of " .. table.getn(group.rows) .. " rows"
                .. (table.getn(absent) > 0
                        and ("   missing: " .. table.concat(absent, ", "))
                        or ""))
    end
end

