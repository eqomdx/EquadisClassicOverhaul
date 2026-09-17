--[[ Equadis' Classic Overhaul :: damage meter

  Who is doing the damage, and the healing.

  A feature module: it owns a window rather than a bar in the cluster, and shares
  the event map, the dirty-flag redraw and the look with everything else.

  Reads OB.ReadCombatLine, which is the ShaguDPS-derived parser -- see
  modules/parser.lua and NOTICE. Nothing about locales or sentences reaches this
  file: it is handed a source, a spell, a target, an amount and a kind, and its
  only job is to keep the running totals and draw them.

  **Two segments, always both.** `overall` runs until you reset it; `current`
  starts fresh at each pull. Kept simultaneously rather than switching, because
  the moment anyone wants the other one the fight is over and recomputing it is
  impossible. Two counters is cheaper than a decision that cannot be undone.
]]--

local OB = EquadisClassicOverhaul

local function Say(msg) OB.Print(msg, "Damage") end

-- ---------------------------------------------------------------------------
-- the running totals
-- ---------------------------------------------------------------------------

--[[ Two segments, each holding damage and healing keyed by player name, plus
     when the segment started -- which is what turns a total into a rate. ]]--
--[[ Three buckets, and the third is not a variation on the first two.

     `damage` and `heal` are keyed by **who did it**. `taken` is keyed by **who
     it happened to**, which is the whole reason it is a separate bucket rather
     than a filter: a tank wants to know what they are absorbing, and the source
     of it is a boss they cannot influence. Same lines, opposite end. ]]--
--[[ `spells` is the same three buckets broken down one level further:

       spells[bucket][source][spellName] = amount

     Kept alongside the totals rather than derived from them, because a total is
     a sum and a sum cannot be taken apart afterwards. It is what the hover
     breakdown reads -- "where did those forty thousand come from" -- and that
     question is only ever asked after the fight, when recomputing is impossible.

     The cost is one table per player per fight, which is nothing next to being
     unable to answer. ]]--
local function newSegment(now)
    return {
        damage = {}, heal = {}, taken = {},
        spells = { damage = {}, heal = {}, taken = {} },
        started = now, last = now,

        --[[ Bumped by every line added. `OB.DamageRows` sorts against it, so
             it is what tells a redraw whether anything actually changed. ]]--
        revision = 0,
    }
end

function OB.NewDamageData(now)
    return { overall = newSegment(now), current = newSegment(now) }
end

--[[ One line's worth into the spell breakdown, building the two levels of table
     it needs on the way. Separate from AddCombatLine so the nesting is written
     once rather than twice -- damage and taken both go through it. ]]--
local function addSpell(segment, bucket, who, spell, amount)
    if not who then return end

    local byName = segment.spells[bucket]
    if not byName then return end

    if not byName[who] then byName[who] = {} end
    byName[who][spell] = (byName[who][spell] or 0) + amount
end

--[[ Add one parsed line to both segments.

     `last` moves with every line rather than with the clock, so a fight's
     duration is the span that actually had damage in it. Idle time between pulls
     would otherwise divide into the rate and make everyone look worse the longer
     they stood still. ]]--
--[[ The two segments every line is added to, held rather than rebuilt -- see
     the note where it is filled in. ]]--
local segments = {}

function OB.AddCombatLine(data, line, now)
    if not data or not line then return end
    if not line.amount or line.amount <= 0 then return end

    local bucket = line.kind == "heal" and "heal" or "damage"

    --[[ A swing has no spell, and it is still the answer to "where did that come
         from" -- usually the biggest part of it. Named rather than skipped, or
         the breakdown would omit most of a warrior's damage. ]]--
    local spell = line.spell or "Melee"

    --[[ Reused rather than built. This runs for every combat line in the game,
         and in a raid a fresh two-element table per line is hundreds of tables a
         second thrown away immediately -- the garbage that is paid for later as
         a collection pause rather than now as CPU. ]]--
    segments[1] = data.overall
    segments[2] = data.current

    for i = 1, 2 do
        local segment = segments[i]

        segment[bucket][line.source] =
                (segment[bucket][line.source] or 0) + line.amount

        addSpell(segment, bucket, line.source, spell, line.amount)

        --[[ The same line counted a second time, under whoever received it.
             Only damage: healing taken is healing done seen from the other side
             and putting it here would double every healer's row. ]]--
        if bucket == "damage" and line.target then
            segment.taken[line.target] =
                    (segment.taken[line.target] or 0) + line.amount

            addSpell(segment, "taken", line.target, spell, line.amount)
        end

        segment.last = now
        segment.revision = (segment.revision or 0) + 1
    end
end

--[[ One player's damage broken down by spell, biggest first.

     Built on demand rather than kept sorted, because it is read on hover and
     written on every combat line: sorting once per hover is free, sorting once
     per hit is not. ]]--
function OB.DamageSpells(segment, bucket, name)
    local out = {}
    if not segment or not segment.spells then return out end

    local byName = segment.spells[bucket]
    if not byName or not byName[name] then return out end

    local sum = 0
    for spell, amount in pairs(byName[name]) do
        table.insert(out, { name = spell, total = amount })
        sum = sum + amount
    end

    for i = 1, table.getn(out) do
        out[i].share = sum > 0 and (out[i].total / sum) or 0
    end

    table.sort(out, function(a, b)
        if a.total == b.total then return a.name < b.name end
        return a.total > b.total
    end)

    return out
end

--[[ Seconds a segment has been running, floored at one.

     Floored because the first line of a fight arrives at zero elapsed, and
     dividing by that is either an error or an infinity depending on the platform
     -- neither of which belongs in a number somebody reads mid-pull. ]]--
function OB.SegmentDuration(segment)
    if not segment then return 1 end

    local span = (segment.last or 0) - (segment.started or 0)
    if span < 1 then return 1 end
    return span
end

--[[ A segment's grand total for one bucket, which is what the header reports.

     Summed rather than kept as a running counter, because a counter is a second
     source of truth for something already stored and the two only ever diverge
     one way: silently. ]]--
function OB.SegmentTotal(segment, bucket)
    if not segment then return 0 end

    local sum = 0
    for name, amount in pairs(segment[bucket] or {}) do sum = sum + amount end
    return sum
end

--[[ One segment's rows, highest first: { name, total, perSecond, share }.

     Sorted by total rather than by rate. A meter answers "who did the work",
     and rate is the same ordering divided by a constant -- except for somebody
     who joined late, where rate flatters them for having been there less. Name
     breaks a tie so the list does not shuffle between identical readings. ]]--
--[[ **Hoisted, because a fresh closure per call is an allocation per redraw.**
     It captures nothing, so there was never a reason to build it each time. ]]--
local function byTotal(a, b)
    if a.total == b.total then return a.name < b.name end
    return a.total > b.total
end

--[[ **The rows a window draws, rebuilt only when the numbers change.**

     This was the single largest allocator in the addon: measured over twenty
     minutes it produced 16 MB across 3085 draws -- 5.3 kB every redraw -- and
     the redraw happens whether or not anything happened. Each call built a
     fresh list, a fresh table per player in it, and a fresh comparator, then
     sorted the lot. Out of combat, staring at a meter nobody was feeding, it
     did all of that several times a second to produce an identical answer.

     So the sorted list is kept and rebuilt only when `segment.revision` moves,
     which `OB.AddCombatLine` bumps for every line. The row tables are reused
     rather than reallocated, so a rebuild costs the sort and nothing else.

     **The returned table is shared, not a copy.** It is the same table next
     call, and its contents change underneath anyone holding it. The only
     caller draws from it immediately and keeps nothing, which is what makes
     this safe -- a second caller that stored it would need a copy. ]]--
function OB.DamageRows(segment, bucket)
    --[[ A fresh table for the empty case rather than a shared one. It is off
         the hot path entirely, so there is nothing to win by sharing it and a
         caller that decided to mutate it would be someone else's afternoon. ]]--
    if not segment then return {} end

    local caches = segment.rowCache

    if not caches then
        caches = {}
        segment.rowCache = caches
    end

    local entry = caches[bucket]

    if not entry then
        entry = { rows = {}, revision = -1, sum = 0 }
        caches[bucket] = entry
    end

    local revision = segment.revision or 0

    if entry.revision ~= revision then
        local rows = entry.rows
        local totals = segment[bucket] or {}
        local sum = 0
        local count = 0

        for name, amount in pairs(totals) do
            count = count + 1

            local row = rows[count]
            if not row then
                row = {}
                rows[count] = row
            end

            row.name = name
            row.total = amount
            sum = sum + amount
        end

        --[[ Trimmed from the end, or a segment that lost a name would keep
             drawing the row that name used to occupy. ]]--
        for i = table.getn(rows), count + 1, -1 do
            rows[i] = nil
        end

        table.sort(rows, byTotal)

        --[[ **Derived here rather than on every call**, because both of these
             follow the data and not the clock.

             That is worth stating, because the opposite is the obvious guess:
             a rate looks like something that should fall while you stand still.
             It does not. `OB.SegmentDuration` is `last - started`, and `last`
             moves only when a line lands -- deliberately, so idle time between
             pulls does not divide into the rate and make everyone look worse
             for having stopped. Duration therefore changes exactly when the
             revision changes, and there is nothing here a redraw could learn
             by recomputing. ]]--
        local duration = OB.SegmentDuration(segment)

        for i = 1, count do
            local row = rows[i]
            row.perSecond = row.total / duration
            row.share = sum > 0 and (row.total / sum) or 0
        end

        entry.revision = revision
        entry.sum = sum
    end

    return entry.rows
end

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

--[[ What one window shows. A meter is several windows over one set of totals --
     damage in one, healing beside it -- so everything that differs between them
     lives here and everything that is counted lives in the data above. ]]--
--[==[ **A window cannot be narrower than its own header.**

     The strip is three groups: two icons at the left edge, two menus centred on
     the midline, two icons at the right. The menus are placed from the centre
     and the icons from the edges, so nothing in that layout notices when they
     meet -- they simply draw on top of each other, and the result is a header
     with the cog sitting in the middle of the word `Current` and the reset and
     the plus nowhere to be seen.

     The floor was 100, which is a round number rather than a measurement. It is
     measured here instead: the two groups of icons, the pair of menus, and one
     gap between each so the centred pair does not touch what it is centred
     between. Written once and read by the slider, the resize grip and the styler
     alike -- three places that were each free to disagree, and the reason a
     window could be dragged to a width the panel would not have offered.

     The numbers are the widths those buttons are actually built at:
     `OB.IconButton` is sixteen wide and `headerButton` is asked for
     fifty-six. ]==]
local HEADER_ICON_W = 16
local HEADER_MENU_W = 56
local HEADER_GAP = 2

local MIN_WINDOW_W =
        -- lock, cog
        (HEADER_GAP + HEADER_ICON_W + HEADER_GAP + HEADER_ICON_W)
        -- clear of the centred pair
        + HEADER_GAP * 2
        -- segment, mode
        + (HEADER_MENU_W + HEADER_GAP + HEADER_MENU_W)
        + HEADER_GAP * 2
        -- reset, new (or close)
        + (HEADER_ICON_W + HEADER_GAP + HEADER_ICON_W + HEADER_GAP)

local MAX_WINDOW_W = 500

function OB.MeterMinWidth() return MIN_WINDOW_W end

local function newWindow(x, y)
    return {
        mode = "damage",
        segment = "current",

        x = x or 0, y = y or 0,
        width = 220,
        height = 15,
        rows = 10,
        locked = false,

        bg = { 0, 0, 0, 0.5 },
        headerColor = { 0, 0, 0, 0.5 },

        --[[ Nothing between rows by default: the border pad is already the only
             spacing a bordered window needs, and a gap on top of it is a stripe
             of background rather than breathing room. Yours to add. ]]--
        gap = 0,

        showRank = true,
        showTotal = true,
        showPerSecond = true,
        showPercent = true,

        --[[ Two colours, in one order: bar, then class. The bar colour is what
             a row is unless something knows better, and class knows better
             because it is how you find a name in a list.

             The threat meter has a third above these -- your own pull ramp --
             and the rule there is the same rule: the fallback is the dullest of
             the options and never the loudest. ]]--
        barColor = { 0.35, 0.42, 0.55, 1 },
        classColor = true,
    }
end

local M = OB.RegisterModule({
    id = "damage",
    name = "Damage Meter",
    feature = true,
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
    renders = "window",
    tickly = true,


    --[[ **Draws with the shared look**, so its page carries the texture, font,
         size, outline and border rows.

         Declared rather than inferred, because nothing about a module implies
         it: `renders` says "none" for nameplates and unit frames, which draw
         into the client's frames and use every one of the five.

         Chat, the roster and quality of life do not have this, and action bars
         gave it up -- they use a font and nothing else, so three of the five
         rows were controls that did nothing. ]]--
    styled = true,
    description = "Damage and healing done, parsed from the combat log."
            .. " The parser is derived from ShaguDPS, which reads the 1.12 log"
            .. " without matching translated strings -- so it works on any"
            .. " locale, including this one.",

    defaults = {
        windows = { newWindow(0, 0) },

        mergePets = true,
        trackAll = false,

        --[[ **The Overall segment is the one nobody remembers to reset.**

             `current` starts fresh at every pull and looks after itself.
             `overall` runs until somebody clears it -- which is the point of it
             -- so it quietly accumulates across an evening, and the first pull
             of a raid ends up measured against three hours of trash from the
             dungeon before it.

             On by default, because it asks rather than acts and the question is
             a good one at exactly that moment. It is only raised when the
             overall segment actually has something in it: asking whether to
             reset a meter reading zero is a dialog that can only waste a
             click. ]]--
        askResetInInstance = true,
        resetOnPull = true,

        --[[ Seconds out of combat before the next pull counts as a new fight.
             See `StartsNewFight`. ]]--
        fightGap = 5,

        --[[ Redraws per second. Per-second figures keep moving between events --
             the totals only change on a hit, but the seconds they are divided
             by do not -- so this is a real speed rather than a throttle.

             Two by default. Ten reads as live and costs five times as much on a
             fight where the numbers barely move; one is calm and lags a burst.
             Which of those is right is a taste, so it is a setting. ]]--
        updateRate = 2,
    },

    --[[ The panel edits **window one**. Everything a second window differs in is
         reached from its own header, which is where you are standing when you
         want it -- putting a second copy of every row on the page would double
         its length to configure something you can click. ]]--
    --[[ Three sections, and the second column picks between them. A `section`
         marker is not a row: it stamps every row after it until the next one.

         Window is what the meter *is* -- where, how big, what it counts. Bar is
         one row's shape and colour. Text is what a row says. Split that way
         because those are three separate sittings: you place a window once, tune
         the bars when you dislike how they look, and change the columns when you
         want a different question answered. ]]--
    options = {
        { "Window", "__s_window", "section", "window" },
        { "Reset On Pull", "resetOnPull", "boolean" },
        { "Seconds Between Fights", "fightGap", "slider", 1, 30, 1 },

        --[[ Asks rather than acts, and only when the overall segment has
             something in it. See the note on `askResetInInstance`. ]]--
        { "Ask To Reset Overall In A Dungeon", "askResetInInstance", "boolean" },
        --[[ Nearby *players*, told from mobs by the roster -- so an unswept
             realm sees fewer of them and the Chat Scan is what fills that in. ]]--
        { "Track Nearby Players", "trackAll", "boolean" },
        { "Updates Per Second", "updateRate", "slider", 1, 10, 1 },
        { "Width", "windows.1.width", "slider", MIN_WINDOW_W, MAX_WINDOW_W, 1 },
        { "Rows Shown", "windows.1.rows", "slider", 3, 40, 1 },
        { "X Position", "windows.1.x", "slider", -2000, 2000, 1 },
        { "Y Position", "windows.1.y", "slider", -2000, 2000, 1 },
        { "Lock All Windows", "windows.1.locked", "boolean" },
        { "Background Color", "windows.1.bg", "color", true },
        { "Header Color", "windows.1.headerColor", "color", true },

        { "Bar", "__s_bar", "section", "bar" },
        { "Height", "windows.1.height", "slider", 8, 32, 1 },
        { "Gap Between Bars", "windows.1.gap", "slider", 0, 12, 1 },

        --[[ The winner first, the fallback under it: class colour overrides the
             swatch on every row it can resolve, which is most of them. The
             swatch is dimmed while it does, so the page shows which one is in
             charge rather than leaving you to work it out. ]]--
        { "Color Rows By Class", "windows.1.classColor", "boolean" },
        { "Bar Color", "windows.1.barColor", "color", true,
          nil, nil, nil, nil, "windows.1.classColor" },

        { "Text", "__s_text", "section", "text" },
        { "Rank Number", "windows.1.showRank", "boolean" },
        { "Total", "windows.1.showTotal", "boolean" },
        { "Per Second", "windows.1.showPerSecond", "boolean" },
        { "Percentage", "windows.1.showPercent", "boolean" },
    },

    requires = { "UnitName" },
})

function M:Config()
    return OB.profile.modules.damage
end

function M:Window(index)
    return self:Config().windows[index]
end

--[[ Every combat log event the parser knows, plus the two that bracket a fight.

     Built from the parser rather than listed again, so a sentence added there is
     listened for without a second edit here. ]]--
local function damageEvents()
    --[[ Guarded, because this runs at file scope: if the parser is missing --
         a TOC line lost, a load order changed -- an unguarded call throws here
         and takes the rest of this file with it, so the module would vanish from
         the settings panel entirely rather than appear and do nothing. ]]--
    local events = {}
    if OB.CombatLogEvents then events = OB.CombatLogEvents() end

    table.insert(events, "PLAYER_REGEN_DISABLED")
    table.insert(events, "PLAYER_REGEN_ENABLED")

    --[[ Walking into a dungeon, which is when the overall segment is most
         likely to be answering last night question. ]]--
    table.insert(events, "PLAYER_ENTERING_WORLD")
    table.insert(events, "ZONE_CHANGED_NEW_AREA")

    return events
end

M.events = damageEvents()

--[[ Whether this line is worth counting.

     Off, the meter follows your group, because a raid boss's own damage in the
     list is noise -- you cannot improve it and it dwarfs everybody.

     **On, it follows nearby *players*, which is what the row says.** It used to
     return true for every line in the log, so the boss, its adds and every
     critter in earshot arrived in the list under their own names. That is not
     "track nearby players", it is "track everything", and the two differ by
     exactly the thing the setting is for.

     **The roster is what tells a player from a mob.** Every path into it --
     friends, guild, raid, party, a friendly target, a `/who` answer -- is
     player-only, so a name being in it is proof. A name that is not in it is
     not proof of anything, which is the honest limit: 1.12 hands the combat log
     over as text and there is nothing in a line that says what kind of thing
     said it.

     So an unswept realm sees fewer names than it might, and the Chat Scan on the
     Chat page is what fills that in. That is a real dependency and it is better
     than the alternative, which was a damage meter with Ragnaros at the top. ]]--
function M:Counts(line)
    if not line.source then return false end

    if line.source == UnitName("player") then return true end
    if OB.GroupClass(line.source) ~= nil then return true end

    if not self:Config().trackAll then return false end

    return (OB.roster and OB.roster[line.source]) ~= nil
end

--[[ **Whether this pull is a new fight or the last one continuing.**

     The current segment used to start over on `PLAYER_REGEN_DISABLED`, full
     stop. That event is "you are now in combat", and combat is not a fight: kill
     one mob of a pack and the client drops you out of combat for the moment
     between its death and the next one reaching you, then puts you straight back
     in. Every kill therefore read as a fresh pull and wiped the count -- which
     is exactly what a meter is for, gone at the moment you would look at it.

     The fix is not to trust the edge but to measure the gap. A fight has ended
     when combat has been *over* for a few seconds; anything shorter is the same
     fight still going. This is what every meter worth using does, and the number
     is a setting because a caster with long pulls and a rogue chaining packs do
     not agree on it.

     **Never having been in combat counts as new.** The first pull of a session
     resets a segment that is already empty, which costs nothing and keeps this
     from depending on the order events happen to arrive in. ]]--
function M:FightGap()
    local seconds = tonumber(self:Config().fightGap) or 5
    if seconds < 0 then seconds = 0 end
    return seconds
end

function M:StartsNewFight(now)
    --[[ In combat -- or freshly logged in and never out of it -- there is no gap
         to measure. `leftCombatAt` is cleared when a pull begins precisely so
         that a second `PLAYER_REGEN_DISABLED` arriving without an intervening
         `PLAYER_REGEN_ENABLED` cannot be read as a new fight. ]]--
    if not self.leftCombatAt then
        return self.everFought ~= true
    end

    return (now - self.leftCombatAt) >= self:FightGap()
end

function M:OnEvent()
    local now = GetTime()

    --[[ Walking into a dungeon or a raid, which is when the overall segment is
         most likely to still be answering last night's question. Asks rather
         than acts, and only when there is something to reset -- see
         `CheckInstanceReset`. ]]--
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        self:CheckInstanceReset()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        --[[ A pull starts the current segment over, if asked. The overall one is
             deliberately untouched: it is the thing you would have lost by
             switching, which is why both are kept. ]]--
        --[[ Built by the factory, **never by hand**. This wrote the segment's
             fields out literally, so when `spells` was added for the hover
             breakdown this one segment came into the world without it -- and
             every hit after the next pull threw on `segment.spells[bucket]`.

             The shape of a segment is one function's business. Anything that
             makes one and is not that function is a second definition waiting
             to fall behind the first. ]]--
        if self:Config().resetOnPull and self:StartsNewFight(now) then
            self.data.current = newSegment(now)
        end

        --[[ Cleared last, after the question above has been asked. In combat
             there is no "when we left", and that absence is what tells the next
             pull it never ended. ]]--
        self.leftCombatAt = nil
        self.everFought = true

        OB.SetDirty(self)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        --[[ **When combat ended, not that it ended.** The next pull has to know
             how long ago this was. ]]--
        self.leftCombatAt = now

        OB.SetDirty(self)
        return
    end

    local line = OB.ReadCombatLine(event, arg1)
    if not line then return end
    if not self:Counts(line) then return end

    OB.AddCombatLine(self.data, line, now)
    OB.SetDirty(self)
end

function M:Reset()
    self.data = OB.NewDamageData(GetTime())

    --[[ The fight tracking goes with the numbers. Leaving `leftCombatAt` behind
         would have the next pull measuring its gap against a fight that no
         longer exists. ]]--
    self.leftCombatAt = nil
    self.everFought = nil
    OB.SetDirty(self)
end

-- ---------------------------------------------------------------------------
-- walking into a dungeon with last night's numbers still on screen
-- ---------------------------------------------------------------------------

--[[ **The Overall segment is the one nobody remembers to reset.**

     `current` starts fresh at every pull and looks after itself. `overall` runs
     until somebody clears it -- which is the point of it -- so it quietly
     accumulates across an evening, and the first pull of a raid is measured
     against three hours of trash from the dungeon before it. The numbers are
     not wrong, they are just answering a question nobody is asking any more.

     Asked rather than done. An overall segment somebody has been deliberately
     accumulating is exactly the thing that must not be thrown away on a guess,
     and walking into an instance is a guess about intent -- a good one, which
     is why it is worth asking, and still a guess. ]]--
StaticPopupDialogs["EQOB_RESET_ON_INSTANCE"] = {
    text = "Reset the overall damage meter for this instance?",
    button1 = "Reset",
    button2 = "Keep",
    OnAccept = function()
        local m = EquadisClassicOverhaul and EquadisClassicOverhaul.modules
                and EquadisClassicOverhaul.modules.damage
        if m then m:Reset() end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

--[[ `GetInstanceInfo` answers `name, instanceType`, and the two types worth
     asking about are a five-man and a raid. Guarded on the call existing at all
     because it is not on every 1.12 build -- Questie carries the same guard --
     and a missing call means the prompt simply never appears rather than the
     module erroring on a loading screen. ]]--
function M:InstanceKind()
    if type(GetInstanceInfo) ~= "function" then return nil end

    local ok, _, kind = pcall(GetInstanceInfo)
    if not ok or type(kind) ~= "string" then return nil end
    return kind
end

--[[ Whether the overall segment has anything in it. **The prompt is only worth
     raising for a meter that is actually running** -- asking somebody whether
     to reset a meter reading zero is a dialog that can only waste a click. ]]--
function M:HasOverall()
    local data = self.data
    if not data or not data.overall then return false end

    if OB.SegmentTotal(data.overall, "damage") > 0 then return true end
    if OB.SegmentTotal(data.overall, "heal") > 0 then return true end
    return false
end

--[[ Asked once per instance rather than once per loading screen.
     `PLAYER_ENTERING_WORLD` fires again on every zone boundary inside a raid,
     and a dialog that reappears every time you cross one is a dialog people
     learn to dismiss without reading. ]]--
function M:CheckInstanceReset()
    if not OB.ModuleEnabled("damage") then return false end
    if not self:Config().askResetInInstance then return false end

    local kind = self:InstanceKind()

    if kind ~= "party" and kind ~= "raid" then
        --[[ Cleared on the way out, so the next instance asks again. Without
             this, leaving and re-entering the same raid would be silent. ]]--
        self.askedInstance = nil
        return false
    end

    local name = (type(GetRealZoneText) == "function" and GetRealZoneText()) or kind
    if self.askedInstance == name then return false end
    self.askedInstance = name

    if not self:HasOverall() then return false end

    if type(StaticPopup_Show) == "function" then
        StaticPopup_Show("EQOB_RESET_ON_INSTANCE")
    end

    return true
end

-- ---------------------------------------------------------------------------
-- the header
-- ---------------------------------------------------------------------------

local SEGMENTS = {
    { "current", "Current" },
    { "overall", "Overall" },
}

--[[ Damage and DPS are the same numbers with different columns showing, which
     is why ShaguDPS's four modes collapse to three here plus a column switch:
     picking "DPS" there is picking a column, and a column is already a
     setting. ]]--
local MODES = {
    { "damage", "Damage" },
    { "heal", "Healing" },
    { "taken", "Taken" },
}

local function labelFor(list, value)
    for i = 1, table.getn(list) do
        if list[i][1] == value then return list[i][2] end
    end
    return value
end

--[[ A small popup of buttons under a header button.

     One menu frame, reused: it is only ever open under one button at a time, and
     a pool per button would be six frames doing one frame's work. ]]--
local function ensureMenu(window)
    if window.menu then return window.menu end

    local menu = CreateFrame("Frame", nil, window)
    menu:SetFrameStrata("DIALOG")
    --[==[ A menu that appears over the game for a moment, so it sits lighter
         than a window somebody reads through. ]==]
    OB.SkinWindow(menu, 0.95)
    menu:Hide()
    menu.items = {}

    window.menu = menu
    return menu
end

local function openMenu(window, anchor, list, current, onPick)
    local menu = ensureMenu(window)

    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(72)
    menu:SetHeight((table.getn(list) * 16) + 10)

    for i = 1, table.getn(list) do
        local item = menu.items[i]

        if not item then
            item = CreateFrame("Button", nil, menu)
            item:SetWidth(64)
            item:SetHeight(16)
            item:SetHighlightTexture(
                    "Interface\\QuestFrame\\UI-QuestTitleHighlight")

            item.text = OB.NewText(item, "OVERLAY", "GameFontNormalSmall")
            item.text:SetAllPoints(item)
            item.text:SetJustifyH("LEFT")

            menu.items[i] = item
        end

        item:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -(5 + ((i - 1) * 16)))
        item.text:SetText(list[i][2])

        if list[i][1] == current then
            item.text:SetTextColor(1, 0.82, 0)
        else
            item.text:SetTextColor(0.8, 0.8, 0.8)
        end

        item.value = list[i][1]
        item:SetScript("OnClick", function()
            onPick(this.value)
            menu:Hide()
        end)

        item:Show()
    end

    for i = table.getn(list) + 1, table.getn(menu.items) do
        menu.items[i]:Hide()
    end

    if menu:IsShown() then menu:Hide() else menu:Show() end
end

--[[ One header button carrying a caption that changes: the segment and the
     mode, which are the two that have to say what they currently are. ]]--
local function headerButton(parent, width, caption)
    local b = CreateFrame("Button", nil, parent)
    b:SetWidth(width)
    b:SetHeight(14)
    b:SetBackdrop(OB.backdrop)

    local face = OB.skin and OB.skin.raised or { 0.2, 0.2, 0.22, 1 }
    local edge = OB.skin and OB.skin.goldDim or { 0.4, 0.4, 0.4 }

    b:SetBackdropColor(face[1], face[2], face[3], face[4] or 1)
    b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    b.text = OB.NewText(b, "OVERLAY", "GameFontNormalSmall")
    b.text:SetAllPoints(b)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(caption)

    --[[ White. GameFontNormalSmall is Blizzard's gold, which on a header means
         "selected" everywhere else in this interface -- so both buttons read as
         highlighted at once and neither one stood out when it was. ]]--
    b.text:SetTextColor(1, 1, 1)

    return b
end

-- ---------------------------------------------------------------------------
-- one window
-- ---------------------------------------------------------------------------

local HEADER_H = OB.HEADER_H
local GRIP = 14

function M:BuildWindow(index)
    local f = CreateFrame("Frame", "EqOBDamage" .. index, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)

    --[[ **Deliberately not SetClampedToScreen.**

         It was here, and it is what stacked two windows on an ultrawide monitor
         after every reload. 1.12 predates widescreen: UIParent is not the
         monitor, and the client's clamp pulls anything outside *its* idea of the
         screen back to that edge -- both windows, to the same edge, on the next
         show. Which is exactly the symptom, and why it survived two rounds of
         looking at our own arithmetic.

         M:RescueWindow does the job instead, and does less of it on purpose: it
         moves a window only when its centre is genuinely unreachable, so a
         window parked out on the wide part of an ultrawide is left alone. ]]--
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f.index = index
    f.rows = {}

    f:SetScript("OnDragStart", function()
        local cfg = OB.modules.damage:Window(this.index)
        if not cfg or cfg.locked then return end
        this:StartMoving()
    end)

    f:SetScript("OnDragStop", function()
        OB.modules.damage:StoreWindowPosition(this)
    end)

    --[[ The header strip, left to right:

           settings  open this subsystem's tab            (cog)
           lock      lock or unlock this window           (padlock, toggles)
           segment   Current or Overall                  (menu)
           mode      Damage, Healing or Taken             (menu)
           chat      report the current list
           close     close this window                    (X)
           reset     reset the meter                      (circular arrow)
           new       open another window                  (+)

         Reset is a dedicated icon immediately left of + on the master window.
         Extra windows keep their X instead; the data belongs to the meter, not
         to an individual view. ]]--
    --[[ The header drags the window, which is where everybody reaches for it.

         It has to say so itself: it is a child frame with the mouse enabled, so
         it swallows the press before the window under it ever sees one, and the
         window's own OnDragStart never fired from the only place a person aims
         at. The body was draggable the whole time and the strip people actually
         grab was dead. ]]--
    local head = CreateFrame("Frame", nil, f)
    head:SetHeight(HEADER_H)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    f.head = head

    head:SetScript("OnDragStart", function()
        local frame = this:GetParent()
        local cfg = OB.modules.damage:Window(frame.index)
        if not cfg or cfg.locked then return end
        frame:StartMoving()
    end)

    head:SetScript("OnDragStop", function()
        OB.modules.damage:StoreWindowPosition(this:GetParent())
    end)

    head.bg = head:CreateTexture(nil, "BACKGROUND")
    head.bg:SetAllPoints(head)

    --[[ One surface under every row, so a gap between two of them shows the
         window rather than whatever is behind it. See StyleWindow. ]]--
    f.body = f:CreateTexture(nil, "BACKGROUND")

    head.settings = OB.IconButton(head, "settings")
    head.lock     = OB.IconButton(head, "unlock")
    head.segment  = headerButton(head, 56, "Current")
    head.mode     = headerButton(head, 56, "Damage")
    head.close    = OB.IconButton(head, "close")
    head.reset    = OB.IconButton(head, "reset")
    head.new      = OB.IconButton(head, "new")

    --[[ **Every button carries its own window**, rather than walking up two
         parents to find it.

         `this:GetParent():GetParent()` is one refactor away from pointing at the
         wrong frame -- wrap a button in a container, or hang one off the window
         instead of the header, and it silently resolves to something with no
         `index`. Then `Window(nil)` is nil and the handler dies on the next
         line, which is the "attempt to index local 'cfg'" that was reported for
         the padlock. Storing the window removes the walk and the whole class of
         failure with it.

         The handlers below also refuse to run on a window that has gone rather
         than erroring: a click that arrives after RemoveWindow has renumbered
         things should do nothing, not break the frame it landed on. ]]--
    local buttons = { head.settings, head.lock, head.segment, head.mode,
                      head.close, head.reset, head.new }

    for i = 1, table.getn(buttons) do buttons[i].window = f end

    head.settings:SetScript("OnClick", function()
        OB.OpenPanelAt("Damage Meter")
    end)

    --[[ The lock is per window, so a window parked over the action bars can be
         nailed down while the one you are still placing stays draggable. ]]--
    head.lock:SetScript("OnClick", function()
        local frame = this.window
        local cfg = OB.modules.damage:Window(frame.index)
        if not cfg then return end

        cfg.locked = not cfg.locked

        OB.modules.damage:StyleWindow(frame)
        OB.RefreshPanel()
    end)

    head.segment:SetScript("OnClick", function()
        local frame = this.window
        local cfg = OB.modules.damage:Window(frame.index)
        if not cfg then return end

        openMenu(frame, this, SEGMENTS, cfg.segment, function(value)
            cfg.segment = value
            OB.modules.damage:StyleWindow(frame)
            OB.SetDirty(OB.modules.damage)
            OB.RefreshPanel()
        end)
    end)

    head.mode:SetScript("OnClick", function()
        local frame = this.window
        local cfg = OB.modules.damage:Window(frame.index)
        if not cfg then return end

        openMenu(frame, this, MODES, cfg.mode, function(value)
            cfg.mode = value
            OB.modules.damage:StyleWindow(frame)
            OB.SetDirty(OB.modules.damage)
            OB.RefreshPanel()
        end)
    end)

    head.close:SetScript("OnClick", function()
        OB.modules.damage:RemoveWindow(this.window.index)
    end)

    head.reset:SetScript("OnClick", function()
        OB.modules.damage:Reset()
    end)

    head.new:SetScript("OnClick", function()
        OB.modules.damage:AddWindow()
    end)

    --[[ The resize grip, bottom right. Hidden when the window is locked, because
         a lock that still lets the window be resized is not a lock. ]]--
    local grip = CreateFrame("Button", nil, f)
    grip:SetWidth(GRIP)
    grip:SetHeight(GRIP)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    f.grip = grip

    --[[ Resizing writes width and row count rather than a frame size, so the
         result is a whole number of rows and the window cannot end up half a row
         tall. Dragging the grip is the same edit the two sliders make. ]]--
    grip:SetScript("OnMouseDown", function()
        local frame = this:GetParent()
        if OB.modules.damage:Window(frame.index).locked then return end

        frame.sizing = true
        frame.sizeFrom = { GetCursorPosition() }
    end)

    grip:SetScript("OnMouseUp", function()
        this:GetParent().sizing = nil
        OB.RefreshPanel()
    end)

    return f
end

--[[ The drag, applied. Called from the meter's tick while the grip is held.

     Cursor coordinates come back in the client's own scale, so both deltas are
     divided by it before they mean pixels on this window. Right and *down*
     grows, which is the direction the grip sits in. ]]--
--[[ **Edit mode unlocks every window, and gives back what it borrowed.**

     Each meter window carries its own `locked`, which is the setting somebody
     uses to stop nudging a window they have finished placing. Edit mode says
     *everything moves*, and a window silently refusing to be dragged while
     outlined like all the others is the same non-answer the map used to give.

     So the lock is overridden while edit mode is on and **restored, per window,
     when it goes off** -- not cleared. Somebody who locked one window
     deliberately still has it locked afterwards, which is the difference
     between borrowing a setting and taking it. ]]--
function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("damage") then
        Say("switch the damage meter on first.")
        return false
    end

    local cfg = self:Config()
    if not cfg or not cfg.windows then return false end

    if on then
        --[[ Remembered once. Toggling edit mode twice without leaving it must
             not record the borrowed state as if it were the real one. ]]--
        if not self.lockedBeforeEdit then
            self.lockedBeforeEdit = {}

            for i = 1, table.getn(cfg.windows) do
                self.lockedBeforeEdit[i] = cfg.windows[i].locked and true or false
                cfg.windows[i].locked = false
            end
        end

        if self.frames then
            for i = 1, table.getn(cfg.windows) do
                if self.frames[i] then
                    OB.MarkMovable(self.frames[i], "Damage Meter " .. i)
                end
            end
        end

        return true
    end

    if self.lockedBeforeEdit then
        for i = 1, table.getn(cfg.windows) do
            --[[ A window created *during* edit mode has nothing remembered for
                 it, and stays as it was made rather than being locked on a
                 guess. ]]--
            if self.lockedBeforeEdit[i] ~= nil then
                cfg.windows[i].locked = self.lockedBeforeEdit[i]
            end
        end

        self.lockedBeforeEdit = nil
    end

    return true
end

function M:StepResize(frame)
    if not frame.sizing then return end

    local cfg = self:Window(frame.index)
    if not cfg or cfg.locked then
        frame.sizing = nil
        return
    end

    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end

    local dx = (x - frame.sizeFrom[1]) / scale
    local dy = (frame.sizeFrom[2] - y) / scale

    local step = self:RowStep(cfg)

    --[[ Width tracks the cursor directly; the row count only changes once the
         cursor has crossed a whole row, so the window is always a whole number
         of rows tall and never ends up half a row short. ]]--
    local width = OB.Clamp(OB.Round(cfg.width + dx), MIN_WINDOW_W, MAX_WINDOW_W)
    local rows = OB.Clamp(cfg.rows + OB.Round(dy / step), 3, 40)

    if width == cfg.width and rows == cfg.rows then return end

    cfg.width = width
    cfg.rows = rows

    -- the cursor's reference moves with what has already been applied
    frame.sizeFrom = { x, y }

    OB.Refresh(true)
end

--[[ Where a dropped window landed, written back to the profile.

     The stored offset is the window's **centre**, because that is what it is
     anchored by. Writing the left edge's distance from the middle of the screen
     and re-anchoring by centre moves the window half its own width every drop,
     and a few drags walk it off the edge.

     Then bounded to the screen, on both axes, against the window's own size --
     so a window cannot be dragged somewhere it cannot be dragged back from. ]]--
function M:StoreWindowPosition(frame)
    frame:StopMovingOrSizing()

    local cfg = self:Window(frame.index)
    if not cfg then return end

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

    x = self:ClampWindow(frame, "x", x)
    y = self:ClampWindow(frame, "y", y)

    --[[ Pushed clear of any window already down, then bounded again: avoiding
         one can walk it into the edge, and the screen wins. ]]--
    x, y = OB.AvoidWindows("damage" .. frame.index, x, y,
            frame:GetWidth(), frame:GetHeight(), self:Scale())

    cfg.x = self:ClampWindow(frame, "x", x)
    cfg.y = self:ClampWindow(frame, "y", y)

    self:StyleWindow(frame)
    OB.RefreshPanel()
end

--[[ The scale this meter's windows are drawn at, which is the addon's. ]]--
function M:Scale()
    local scale = OB.profile and OB.profile.scale or 1
    if scale <= 0 then return 1 end
    return scale
end

--[[ `RescueWindow` lived here: a softer bound for the draw pass that only moved
     a window once its centre had left the screen.

     It was the third mechanism to be caught moving windows somebody had placed,
     after SetClampedToScreen and a hard clamp in the same spot. All three shared
     one flaw -- each decided for itself where "the screen" ends, and on an
     ultrawide none of them agrees with the monitor. Softening the rule bought a
     round; it did not fix anything.

     Drawing does not move windows now. Nothing replaced this. ]]--
function M:ClampWindow(frame, axis, v)
    local size = (axis == "x") and frame:GetWidth() or frame:GetHeight()
    local limit = OB.ScreenLimit(axis, size, self:Scale())

    if v > limit then return limit end
    if v < -limit then return -limit end
    return OB.Round(v)
end

--[[ The addon's scale, applied to every window. Features are asked rather than
     reached into, because only this one knows it has more than one frame. ]]--
function M:OnScale(scale)
    if not self.frames then return end

    for i = 1, table.getn(self.frames) do
        self.frames[i]:SetScale(scale)
    end
end

--[[ **A new window is a copy of the first one, moved.**

     It used to be built from the factory defaults, so a window opened beside one
     you had spent ten minutes colouring arrived in the shipped grey and had to
     be matched by hand -- reported as new tabs not sharing the header colour,
     and it was true of every appearance setting, not only that one.

     Copied rather than sharing a table: two windows that cannot differ are one
     window drawn twice, and the whole point is damage in one and healing in the
     other. So the mode is the only thing deliberately *not* inherited -- opening
     a second window showing exactly what the first shows is never what anybody
     meant by opening a second window. ]]--
--[[ Settings that stay a property of *one* window, whatever the page does.

     Position, obviously: pushing window one's coordinates onto the rest would
     stack them all in the same place. And the two the header owns -- the segment
     and the statistic -- because a second window exists precisely to show
     something the first does not. Everything else is appearance, and appearance
     that differs between two windows of one meter is a mistake nobody made on
     purpose. ]]--
local PER_WINDOW = { x = true, y = true, mode = true, segment = true }

--[[ **The page edits every window, not just the first.**

     Its rows are written as `windows.1.*` because a page needs one concrete
     thing to bind to, and it used to mean exactly that: colour the meter and
     only the master window changed, with the others keeping whatever they had
     until you deleted and re-made them. There is no second column of settings
     for window two and no plan to add one, so a setting that reached only
     window one left the rest unreachable. ]]--
function M:AfterSet(key, value)
    local _, _, field = string.find(key or "", "^windows%.1%.(.+)$")
    if not field then return end

    local cfg = self:Config()

    --[[ **Position is bounded here, on the write.**

         It used to be bounded on the draw, which is why removing that left a
         typed coordinate free to put a window past the edge. The bound belongs
         on the deliberate act: somebody dragging a slider to its end means "as
         far as it goes", and stopping at the screen is the helpful reading. A
         draw means nothing at all and should have no opinion. ]]--
    if field == "x" or field == "y" then
        local frame = self.frames and self.frames[1]
        if frame then
            cfg.windows[1][field] = self:ClampWindow(frame, field, value)
        end
        return
    end

    if PER_WINDOW[field] then return end

    for i = 2, table.getn(cfg.windows) do
        --[[ Copied, never shared. A colour is a table, and handing every window
             the same one makes them impossible to tell apart later -- and means
             editing any of them edits all of them by accident rather than by
             this rule. ]]--
        if type(value) == "table" then
            cfg.windows[i][field] = OB.DeepCopy(value)
        else
            cfg.windows[i][field] = value
        end
    end
end

function M:AddWindow()
    local cfg = self:Config()
    if table.getn(cfg.windows) >= 4 then return end

    local first = cfg.windows[1]
    local made = OB.DeepCopy(first)

    --[[ **Offset from the window that is actually there, not always from the
         first one.**

         It was `first.x + first.width + 10` every time -- so the second window
         landed beside the first, and the third landed in *exactly* the same
         place as the second, and the fourth on top of both. Clicking New twice
         produced one visible window with two more hidden underneath it, which
         is what was reported.

         Cascaded from the last window instead, so each new one steps along from
         wherever the previous one ended up rather than from a fixed point. ]]--
    local previous = cfg.windows[table.getn(cfg.windows)] or first
    made.x = previous.x + (previous.width or first.width or 200) + 10
    made.y = previous.y

    --[[ **A new window shows what the one you copied shows.**

         It used to walk damage -> healing -> taken on the reasoning that a
         second window exists to answer the next question along. In practice
         that means clicking New hands you a healing meter you did not ask for,
         and if window one was on Overall you get overall *healing* -- two
         changes at once, neither of them requested.

         A copy is the honest reading of a button called New: it gives you
         another one of what you have, and the mode dropdown is right there on
         the header for the moment you want something else. ]]--

    table.insert(cfg.windows, made)

    OB.Refresh(true)
    OB.RefreshPanel()
end

--[[ Window one is never removed: it is the one the settings page edits, and a
     meter with no windows is a subsystem you can only switch off. ]]--
function M:RemoveWindow(index)
    if index <= 1 then return end

    local cfg = self:Config()
    table.remove(cfg.windows, index)

    --[[ **The frame pool is not touched.**

         It used to `table.remove` the frame as well, which took it out of the
         list while leaving it on screen -- and once it is out of the list,
         nothing can ever hide it again, because the sweep at the end of OnStyle
         walks exactly that list. One orphaned window per close, each of them
         permanent. That is the second meter that would not go away.

         Frames are pooled by position and reused, the rule every other pool here
         follows: frame `i` always draws window `i`, whatever window that now is,
         and any frame past the end is hidden. Nothing to renumber and nothing
         that can escape. ]]--
    OB.Refresh(true)
    OB.RefreshPanel()
end

function M:OnBind()
    self.data = self.data or OB.NewDamageData(GetTime())
    self.frames = self.frames or {}

    self:OnStyle()
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

--[[ Rows are inset by the border's own width, so two of them cannot draw their
     borders over each other.

     This is the bug RogueBars had: a border is art *outside* the bar, so bars
     packed edge to edge overlap by twice the pad however carefully the heights
     line up. Spacing them by it is the fix, and it has to come from the same
     BorderPad the styling uses or the two disagree.

     And **exactly** the pad, with nothing added on top. A spare pixel per row is
     invisible against a border and is a stripe of window background between
     every pair of rows when the border is off, which is the gap that got
     reported. With no border the step is the height and the rows touch. ]]--
function M:RowStep(cfg)
    return cfg.height + (OB.BorderPad("damage") * 2) + (cfg.gap or 0)
end

--[[ **Where the number came from**, on hover -- ShaguDPS's most useful habit and
     the reason its rows are worth pointing at.

     A total answers "who", and the next question is always "off what": whether
     the rogue's forty thousand was backstabs or a lucky proc, whether a warrior
     is actually using their rotation. That cannot be recovered from a total
     afterwards, which is why the per-spell tables are kept as the lines arrive
     rather than derived on demand.

     Capped at ten lines. A shadow priest in a long fight has thirty entries and
     the last twenty are rounding; a tooltip taller than the screen answers
     nothing. ]]--
local TOOLTIP_ROWS = 10

function M:ShowRowTooltip(row)
    if not row.entryName then return end

    local cfg = self:Window(row.windowIndex)
    if not cfg then return end

    local segment = self.data[cfg.segment] or self.data.current
    local spells = OB.DamageSpells(segment, cfg.mode, row.entryName)

    OB.OwnTooltip(row, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()

    GameTooltip:AddDoubleLine(row.entryName,
            labelFor(MODES, cfg.mode) .. "  " .. labelFor(SEGMENTS, cfg.segment))

    if table.getn(spells) == 0 then
        --[[ Says so rather than showing a name and nothing under it, which reads
             as a tooltip that failed to load. ]]--
        GameTooltip:AddLine("no breakdown recorded")
        GameTooltip:Show()
        return
    end

    for i = 1, table.getn(spells) do
        if i > TOOLTIP_ROWS then break end

        GameTooltip:AddDoubleLine(spells[i].name,
                OB.ShortNumber(spells[i].total)
                        .. "  (" .. OB.Round(spells[i].share * 100) .. "%)")
    end

    GameTooltip:Show()
end

function M:EnsureRows(frame, count)
    for i = table.getn(frame.rows) + 1, count do
        local row = OB.CreateBar("EqOBDamage" .. frame.index .. "Row" .. i, frame)

        --[[ Rows take the mouse so they can be hovered. That is safe now only
             because the header carries the drag: when the window was dragged by
             its body, a row swallowing the press would have made most of the
             window undraggable. ]]--
        row:EnableMouse(true)
        row.windowIndex = frame.index

        row:SetScript("OnEnter", function()
            OB.modules.damage:ShowRowTooltip(this)
        end)

        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        frame.rows[i] = row
    end
end

function M:StyleWindow(frame)
    local cfg = self:Window(frame.index)
    if not cfg then return end

    local step = self:RowStep(cfg)
    local pad = OB.BorderPad("damage")

    self:EnsureRows(frame, cfg.rows)

    --[==[ **Corrected on the way out, not only on the way in.**

         A width saved before the floor existed is still in the profile, and a
         clamp that only guards new input would draw it broken forever while
         quietly reporting a legal number on the settings page. Written back
         rather than merely used, so the slider and the window agree about what
         this window is. ]==]
    if (tonumber(cfg.width) or 0) < MIN_WINDOW_W then cfg.width = MIN_WINDOW_W end
    if (tonumber(cfg.width) or 0) > MAX_WINDOW_W then cfg.width = MAX_WINDOW_W end

    frame:SetWidth(cfg.width)
    frame:SetHeight(HEADER_H + (step * cfg.rows) + (pad * 2))
    frame:SetScale(self:Scale())
    frame:ClearAllPoints()

    --[[ **Drawing never moves a window. Ever.**

         Three separate mechanisms have now been caught doing it: the client's
         SetClampedToScreen, a hard clamp here, and a gentler rescue here that
         only fired when the centre left the screen. Each was defensible on its
         own and each moved windows the user had placed -- because every one of
         them decides where "the screen" ends, and on an ultrawide none of them
         agrees with the monitor.

         The stored position is the answer. It is written by exactly two things,
         both of them deliberate acts on one window: dropping a drag, and typing
         a coordinate. Neither happens while drawing, so drawing has no business
         having an opinion.

         A profile carried to a smaller monitor can leave a window off the edge.
         That is recoverable -- `/eq windows` says where everything is, and the
         sliders reach it -- and it is a far smaller cost than rearranging a
         layout somebody built, every single load. ]]--

    frame:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)

    --[[ Published so other windows know to keep off. Written on every style
         pass, because a window that grew is a window that may now overlap. ]]--
    OB.RegisterWindowRect("damage" .. frame.index, cfg.x, cfg.y,
            frame:GetWidth(), frame:GetHeight())

    frame.head:ClearAllPoints()
    frame.head:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.head:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

    local c = cfg.headerColor
    frame.head.bg:SetTexture(c[1], c[2], c[3], c[4] or 1)

    --[[ **Master controls: reset + new. Extra windows: close.**

         The master is the one the settings page edits and the one a meter cannot
         be without, so it carries the reset and add-window controls. Every extra
         window carries only its close control. ]]--
    local master = frame.index == 1

    if master then
        frame.head.close:Hide()
        frame.head.reset:Show()
        frame.head.new:Show()
    else
        frame.head.close:Show()
        frame.head.reset:Hide()
        frame.head.new:Hide()
    end

    --[[ **Three groups, not one row: window controls left, what-am-I-looking-at
         centred, add and close right.**

         They are three different kinds of thing and reading them as one strip of
         seven made you scan it every time. The two menus are the only ones whose
         answer changes, so they get the middle where the eye lands; the padlock
         is first because it is the one you reach for while arranging windows,
         and the settings cog sits beside it as the other rarely-used one. ]]--
    local left = { frame.head.lock, frame.head.settings }
    local x = 2

    for i = 1, table.getn(left) do
        left[i]:ClearAllPoints()
        left[i]:SetPoint("LEFT", frame.head, "LEFT", x, 0)
        x = x + left[i]:GetWidth() + 2
    end

    local corner = master and frame.head.new or frame.head.close
    corner:ClearAllPoints()
    corner:SetPoint("RIGHT", frame.head, "RIGHT", -2, 0)

    frame.head.reset:ClearAllPoints()
    if master then
        frame.head.reset:SetPoint("RIGHT", frame.head.new, "LEFT", -2, 0)
    end

    --[[ Centred as a pair, so the two together sit on the window's midline
         rather than one of them landing there and the other beside it. ]]--
    local pairWidth = frame.head.segment:GetWidth()
            + frame.head.mode:GetWidth() + 2

    frame.head.segment:ClearAllPoints()
    frame.head.segment:SetPoint("LEFT", frame.head, "CENTER",
            -(pairWidth / 2), 0)

    frame.head.mode:ClearAllPoints()
    frame.head.mode:SetPoint("LEFT", frame.head.segment, "RIGHT", 2, 0)

    --[[ The padlock shows the state it is in, not the state clicking would
         reach. A closed padlock on an unlocked window reads as a button that
         will lock it and as a window that is already locked, and half the
         people looking at it pick the wrong one. ]]--
    frame.head.lock:SetIcon(cfg.locked and "lock" or "unlock")

    frame.head.segment.text:SetText(labelFor(SEGMENTS, cfg.segment))
    frame.head.mode.text:SetText(labelFor(MODES, cfg.mode))

    if cfg.locked then frame.grip:Hide() else frame.grip:Show() end

    --[[ **The window's body carries the background, not each row.**

         Painting it per row leaves the gap between two rows showing whatever is
         behind the window, so raising Gap Between Bars cut stripes through it --
         reported as "the gap creates a gap in the background". A window is one
         surface; the rows sit on it.

         So the body is painted once across the whole area below the header, and
         the rows are given no background of their own. What was the row's trough
         is now the body showing through, which is the same pixels and cannot
         come apart. ]]--
    local body = cfg.bg
    frame.body:SetTexture(body[1], body[2], body[3], body[4] or 0.6)
    frame.body:ClearAllPoints()
    --[[ Anchored here, sized in FitBackground: how tall it should be depends on
         how many rows there are to sit on it, which the draw pass knows and the
         style pass does not. ]]--
    frame.body:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -HEADER_H)
    frame.body:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -HEADER_H)

    --[[ Rows are inset by the border pad on both sides, so the border art stays
         inside the window rather than hanging over its edge -- which is the
         other half of "bars must not go beyond the window region". ]]--
    local slot = {
        w = cfg.width - (pad * 2), h = cfg.height,
        bg = { 0, 0, 0, 0 },
    }

    for i = 1, table.getn(frame.rows) do
        local row = frame.rows[i]
        OB.StyleBar(row, slot, nil, "damage")

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT",
                pad, -(HEADER_H + pad + ((i - 1) * step)))
    end
end

function M:OnStyle()
    local cfg = self:Config()
    if not self.frames then return end

    -- one frame per configured window, built on demand and never destroyed
    for i = 1, table.getn(cfg.windows) do
        if not self.frames[i] then self.frames[i] = self:BuildWindow(i) end
        self:StyleWindow(self.frames[i])
    end

    for i = table.getn(cfg.windows) + 1, table.getn(self.frames) do
        self.frames[i]:Hide()
    end
end

--[[ The right-hand label: total, rate and share, in whichever combination is
     switched on. Assembled rather than fixed, because which of the three matter
     depends on what you are looking for and all three may be on at once. ]]--
--[[ **Reused, because this ran per row per redraw.**

     Measured at 4801 calls in forty-eight seconds -- eight rows a window, two
     windows, several times a second, whether or not a number had changed. A
     fresh table each time is a table a row per draw thrown away immediately. ]]--
local textParts = {}

--[[ **The formatted right-hand column, remembered against what it was made
     from.**

     Every part of this allocates: two `ShortNumber` strings, a concatenation
     for the percent, and the `concat` at the end. None of it changes unless one
     of the three numbers or one of the three settings does, and out of combat
     none of them do.

     The key is the inputs themselves rather than a revision, because that is
     what the answer actually depends on -- a row that is reused for a different
     player with an identical total wants the identical string, and gets it. ]]--
function M:RowText(cfg, row)
    local showTotal = cfg.showTotal and true or false
    local showPerSecond = cfg.showPerSecond and true or false
    local showPercent = cfg.showPercent and true or false

    if row.textValue
            and row.textTotal == row.total
            and row.textPerSecond == row.perSecond
            and row.textShare == row.share
            and row.textShowTotal == showTotal
            and row.textShowPerSecond == showPerSecond
            and row.textShowPercent == showPercent then
        return row.textValue
    end

    local count = 0

    if showTotal then
        count = count + 1
        textParts[count] = OB.ShortNumber(row.total)
    end

    if showPerSecond then
        count = count + 1
        textParts[count] = OB.ShortNumber(row.perSecond)
    end

    if showPercent then
        count = count + 1
        textParts[count] = OB.Round(row.share * 100) .. "%"
    end

    --[[ Trimmed, or turning a column off would leave its last value on the end
         of every row for as long as the table kept it. ]]--
    for i = table.getn(textParts), count + 1, -1 do
        textParts[i] = nil
    end

    local text = table.concat(textParts, OB.COLUMN_GAP)

    row.textValue = text
    row.textTotal = row.total
    row.textPerSecond = row.perSecond
    row.textShare = row.share
    row.textShowTotal = showTotal
    row.textShowPerSecond = showPerSecond
    row.textShowPercent = showPercent

    return text
end

--[[ Remembered the same way and for the same reason as the text column. With
     the rank on, this concatenates a number and a name for every row of every
     redraw; the answer changes only when the row's position or occupant does.

     With the rank off it returns the name unchanged and allocates nothing, so
     that path is left exactly as it was. ]]--
function M:RowName(cfg, index, row)
    if not cfg.showRank then return row.name end

    if row.nameValue
            and row.nameIndex == index
            and row.nameSource == row.name then
        return row.nameValue
    end

    row.nameValue = index .. ". " .. row.name
    row.nameIndex = index
    row.nameSource = row.name

    return row.nameValue
end

--[[ **Bar colour, unless class knows better.**

     The fallback is the window's own bar colour rather than a hardcoded grey,
     which is the setting the panel now carries. A row whose class cannot be
     resolved -- a pet, a boss, anybody outside the group -- is not an error and
     should not look like one. ]]--
--[[ **One table per class, not one per row per draw.**

     This returned a fresh `{ r, g, b, 1 }` every time it was asked, and it is
     asked once per row of every window on every redraw. Measured in a fight:
     978 kB across 904 draws, which is nine thousand tables for nine colours
     that have not changed since the client shipped.

     Safe to share because `OB.SetBarColor` only reads it -- and because the
     other branch has always handed back `cfg.barColor` itself, so a shared
     table is already what a caller gets half the time. ]]--
local classColors = {}

function M:RowColor(cfg, entry)
    if cfg.classColor then
        local class = OB.GroupClass(entry.name)

        if class then
            local color = classColors[class]

            if not color then
                local r, g, b = OB.ClassColor(class)
                color = { r, g, b, 1 }
                classColors[class] = color
            end

            return color
        end
    end

    return cfg.barColor
end

--[==[ The wheel, claimed on the window itself so it works wherever the cursor
     is inside it rather than only over a row. A meter is scrolled at speed while
     something else has your attention. ]==]
function M:InstallScroll(frame)
    if frame.ecoScrolls then return false end
    if not frame.EnableMouseWheel then return false end

    frame.ecoScrolls = true
    frame.scroll = 0

    frame:EnableMouseWheel(true)

    frame:SetScript("OnMouseWheel", function()
        local m = EquadisClassicOverhaul.modules.damage

        this.scroll = (this.scroll or 0) + ((arg1 and arg1 > 0) and -1 or 1)
        m:DrawWindow(this)
    end)

    return true
end

function M:DrawWindow(frame)
    local cfg = self:Window(frame.index)
    if not cfg then return end

    self:EnsureRows(frame, cfg.rows)
    self:InstallScroll(frame)

    local segment = self.data[cfg.segment] or self.data.current
    local rows = OB.DamageRows(segment, cfg.mode)

    frame:Show()

    --[[ Scaled against the leader rather than a fixed total, which is what makes
         the bars a comparison. Against a total, a raid of ten would draw every
         row at a tenth of the width and say nothing. ]]--
    local top = rows[1] and rows[1].total or 0
    if top <= 0 then top = 1 end

    --[==[ **The list scrolls, because a raid is longer than a window.**

         The meter shows the top few and there is no window size that is right
         for both a five-man and a forty-man. Scrolled rather than resized: the
         window is somewhere you put once, and what changes is how far down the
         list you are looking.

         Clamped on every draw and not only when the wheel turns. The list is
         re-sorted constantly in combat -- people join it, and somebody who was
         twentieth is fifth a moment later -- so an offset that was valid when it
         was set can be past the end by the next redraw, which would blank the
         window in the middle of a fight. ]==]
    local offset = frame.scroll or 0
    local most = table.getn(rows) - cfg.rows

    if most < 0 then most = 0 end
    if offset > most then offset = most end
    if offset < 0 then offset = 0 end

    frame.scroll = offset

    for i = 1, table.getn(frame.rows) do
        local row = frame.rows[i]
        local entry = rows[i + offset]

        if not entry or i > cfg.rows then
            row.entryName = nil
            row:Hide()
        else
            row:Show()
            OB.SetBarFill(row, entry.total / top, false)

            OB.SetBarColor(row, self:RowColor(cfg, entry))

            --[[ Whose row this is, so the hover breakdown can ask about them.
                 Stored rather than re-derived from the position, because the
                 ordering changes under the cursor mid-fight and reading the
                 sorted list again on hover would answer about whoever is there
                 *now* rather than the row being pointed at. ]]--
            row.entryName = entry.name
            row.windowIndex = frame.index

            --[[ Held rather than drawn here. How much room the name has
                 depends on the widest number column in the window, which
                 no single row knows; AlignColumns fits and places it once
                 every row has been measured. ]]--
            row.leftFull = self:RowName(cfg, i, entry)
            OB.SetBarText(row, row.center, "", 50)

            --[[ Placed below, once the widest row is known: every row's numbers
                 have to begin at the same x or the digits run ragged down the
                 window and nothing lines up with anything. ]]--
            row.right:SetText(self:RowText(cfg, entry))
        end
    end

    self:AlignColumns(frame)

    local shown = table.getn(rows)
    if shown > cfg.rows then shown = cfg.rows end
    self:FitBackground(frame, shown)
end

--[[ **The background stops where the rows stop**, so there is never background
     with no bar in front of it.

     Rows Shown is a ceiling, not a promise: three people in a window sized for
     ten left seven rows of bare colour, which reads as a window that failed to
     draw rather than as a fight with three people in it.

     The frame keeps its full height. It is what the resize grip and the overlap
     rectangle are measured from, and a window whose bounds moved every time
     somebody joined the fight could not be placed. Only the paint follows. ]]--
function M:FitBackground(frame, shown)
    if not frame.body then return end

    if shown <= 0 then
        frame.body:Hide()
        return
    end

    local cfg = self:Window(frame.index)
    local pad = OB.BorderPad("damage")

    frame.body:Show()

    --[[ Exactly the last row's bottom edge, not a whole step past it: a step
         includes the gap *after* a row, so multiplying by the count leaves a
         strip below the last bar. ]]--
    frame.body:SetHeight(((shown - 1) * self:RowStep(cfg))
            + cfg.height + (pad * 2))
end

--[[ **One left edge for every row's numbers.**

     Measured across the visible rows and applied to all of them, so the column
     is flush left with itself while the block as a whole still ends on the
     window's right edge. Two passes rather than one, because the answer depends
     on every row and no row can know it alone. ]]--
function M:AlignColumns(frame)
    local widest = 0

    --[[ The numbers first, because they are what the name has to fit around.
         Measured across every visible row: the column is only a column if all
         of them begin at the same x. ]]--
    for i = 1, table.getn(frame.rows) do
        local row = frame.rows[i]

        if row:IsShown() then
            local w = row.right:GetStringWidth() or 0
            if w > widest then widest = w end
        end
    end

    local first = frame.rows[1]
    if not first then return end

    --[[ **The names are cut to what is left, and the numbers keep their edge.**

         This used to run the other way: the names were measured too, and a row
         whose name would have reached the number column pushed that column
         right instead -- past the end of the bar, taking the trailing "%" off
         the window with it. The numbers are the reason the window is open, so
         they are the half that is guaranteed the space. ]]--
    local room = OB.NameRoom(first, widest)
    local at = OB.ColumnStart(first, widest, 0)

    for i = 1, table.getn(frame.rows) do
        local row = frame.rows[i]

        if row:IsShown() then
            OB.FitTextTo(row.left, row.leftFull, room)
            OB.PlaceText(row, row.left, 0)
            OB.PlaceTextLeftAt(row, row.right, at)
        end
    end
end

function M:OnDraw()
    if not self.frames then return end

    local cfg = self:Config()
    for i = 1, table.getn(cfg.windows) do
        if self.frames[i] then self:DrawWindow(self.frames[i]) end
    end
end

-- ---------------------------------------------------------------------------
-- preview
-- ---------------------------------------------------------------------------

--[[ A plausible raid, so the colours and columns can be set without a fight.

     Class names rather than player names, because the row colour comes from the
     group roster and a preview that could not colour itself would be failing to
     show the one thing hardest to picture. ]]--
local PREVIEW = {
    { "Rogue", 48000, "ROGUE" }, { "Mage", 41500, "MAGE" },
    { "Warrior", 33000, "WARRIOR" }, { "Hunter", 29500, "HUNTER" },
    { "Warlock", 24000, "WARLOCK" }, { "Druid", 12000, "DRUID" },
    { "Priest", 4200, "PRIEST" },
}

function M:TestStart(now)
    self.liveData = self.data
    self.previewAt = nil
    self:SeedPreview(now)
end

--[[ Re-seeded every second with fresh numbers, so the bars actually move.

     A still preview shows the colours and hides everything about the motion --
     whether the ordering settles, whether a row that overtakes another is
     readable, whether the widths are jumpy. Those are the things worth looking
     at before a raid. ]]--
function M:SeedPreview(now)
    self.data = OB.NewDamageData(now - 30)

    for i = 1, table.getn(PREVIEW) do
        local name, base = PREVIEW[i][1], PREVIEW[i][2]

        --[[ The class is asserted, because a preview row is in no group and the
             roster can never answer for it. Without this every row came back
             classless and the preview showed the fallback seven times over --
             which is what "color rows by class isn't working" was. ]]--
        OB.classHint[name] = PREVIEW[i][3]

        -- +/- 30%, so the ranking genuinely reshuffles rather than jittering
        local amount = math.floor(base * (0.7 + (math.random() * 0.6)))

        OB.AddCombatLine(self.data,
                { source = name, target = "Training Dummy",
                  amount = amount, kind = "damage" }, now)
        OB.AddCombatLine(self.data,
                { source = name, target = name,
                  amount = math.floor(amount / 3), kind = "heal" }, now)
    end

    OB.SetDirty(self)
end

--[[ The real totals come back untouched. A preview that overwrote them would
     cost somebody the fight they were reading, which is a high price for
     looking at a colour. ]]--
function M:TestStop()
    -- unconditional, for the reason threat.lua gives at the same point
    self.data = self.liveData or OB.NewDamageData(GetTime())
    self.liveData = nil
    self.previewAt = nil

    --[[ Cleared, or a real player who happens to be called Mage keeps the
         preview's class for the rest of the session. ]]--
    OB.classHint = {}

    OB.SetDirty(self)
end

--[[ **The preview re-seeds at the meter's own update rate.**

     It was pinned at once a second, so dragging Updates Per Second to ten did
     nothing you could see -- the bars still moved once a second, and the setting
     read as broken. It was not: the *redraw* was ten a second over numbers that
     changed once. Nothing to look at.

     A preview exists to show what a setting does, so the setting has to reach
     it. In a real fight the two are genuinely separate -- the numbers change
     when somebody is hit -- but the only honest way to preview a redraw rate is
     to give it something changing at that rate. ]]--
function M:TestStep(now)
    if not self.previewAt then self.previewAt = now end
    if (now - self.previewAt) < self:RedrawStep() then return end

    self.previewAt = now
    self:SeedPreview(now)
end

--[[ Ticked so a rate keeps moving while a fight runs. The totals only change on
     an event, but the seconds they are divided by do not.

     The beat is `updateRate` redraws a second, clamped to the slider's own
     bounds so a saved value from a future build cannot stop the meter
     redrawing at all. ]]--
function M:RedrawStep()
    return 1 / OB.Clamp(self:Config().updateRate or 2, 1, 10)
end

function M:OnUpdate(now)
    --[[ A drag has to be followed every frame, not on the redraw beat: a grip
         that only catches up twice a second reads as a stuck window. ]]--
    if self.frames then
        for i = 1, table.getn(self.frames) do
            if self.frames[i].sizing then self:StepResize(self.frames[i]) end
        end
    end

    if self.nextDraw and now < self.nextDraw then return end
    self.nextDraw = now + self:RedrawStep()

    OB.SetDirty(self)
end
