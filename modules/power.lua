--[[ Equadis' Classic Overhaul :: power

  The resource bar. One module for every power type in the game.

  In vanilla, UnitMana() and UnitManaMax() return the *current* power whatever
  its type -- mana, rage, energy, focus, happiness -- so there is exactly one
  accessor and RogueBars' energy rendering path generalises without a single
  branch. The work is entirely in the ticker.

  A druid changing form does not change which module holds the slot. It changes
  which *variant* of this module is active: cfg.byType[UnitPowerType] carries the
  colour and the ticker mode. Geometry, texture, border, background, text size
  and flip all belong to the slot, so the bar recolours in place and does not
  move a pixel. That is the whole point of the slot model.
]]--

local OB = EquadisClassicOverhaul

local floor = math.floor

-- ---------------------------------------------------------------------------
-- ticker strategies
--
-- Both produce the same thing -- a cycle start and a cycle length -- and both
-- feed the same renderer. Which one runs is chosen by power type.
-- ---------------------------------------------------------------------------

OB.tickers = {}

--[[ Energy and focus: regeneration arrives as a visible pulse, so the cycle can
     be anchored to a real observation.

     **Energy does not only arrive on the tick**, and the cycle must not follow
     anything that is not one.

     A rogue with Vigor gets 2 energy back on each poison application;
     Relentless Strikes pays 25 on a finisher; Thistle Tea hands over 100. Every
     one of those used to re-anchor the cycle, so the sweep restarted mid-beat
     and the spark stopped predicting the thing it exists to predict.

     Two things separate a tick from a talent, and a gain has to survive both.

     **When.** A tick cannot arrive much sooner than a period after the last one.
     `lastTick` is what that is measured from -- and it is deliberately a
     different field from `start`.

     That distinction is the whole of the desync bug. `start` is the *drawing*
     anchor and it rolls forward whenever a period elapses, so that the sweep
     keeps running when nothing is observed. Measuring "how long since the last
     tick" from it meant the roll happened first: the moment the true interval
     ran a hair over the assumed two seconds -- which it always does, between
     server latency and the frame the gain is noticed on -- `start` had already
     jumped, the real tick read as 0.05s old, and every tick after it was
     rejected. The cycle then free-ran on a perfect two-second beat anchored to
     one stale observation and drifted further out with every minute.

     **How much.** A partial gain arriving early is somebody's talent. A partial
     gain arriving *on* the beat is a real tick against a nearly full bar, which
     is why the size test only applies while the timing is also suspect.

     **How fast.** The cadence is *learned slowly*, and this has now been wrong
     in both directions.

     It began as the raw interval between two observations, which made the
     ticker visibly breathe: `UNIT_ENERGY` is noticed on a rendered frame after
     the server has already moved the number, so a single sample carries frame
     and latency jitter and one bad one could make the sweep run visibly slow or
     fast.

     The reaction was to nail it to exactly two seconds and use real ticks only
     to correct the phase. That removed the breathing and introduced the
     opposite fault: on a realm whose pulse is not exactly two seconds the sweep
     runs at the wrong speed for ever, so the energy arrives *before* the marker
     reaches the end of the bar, every single cycle. Snapping the phase back
     hides it for an instant and then it happens again.

     Neither the raw sample nor the constant is right. The sample is right and
     the *weighting* was wrong: the interval is folded into a running estimate
     that starts at two seconds and moves a fraction of the way to each new
     observation, so jitter averages out and a genuinely different cadence is
     still followed within a few ticks. It is clamped, because the estimate also
     sets the windows that decide what counts as a tick and a runaway there
     would reject everything.

     Only clean samples are fed in: a full tick, on the beat, at a plausible
     distance from the one before it. A partial gain against a nearly full bar
     says nothing about cadence, and the double-length gap after a rejected
     observation says something actively wrong. ]]--
local PULSE_PERIOD = 2

--[[ The estimate never leaves this range. Every pulse anyone plays on is two
     seconds or near enough; these are wide enough for a server that differs and
     tight enough that the tick windows stay meaningful. ]]--
local PULSE_MIN = 1.5
local PULSE_MAX = 2.5

--[[ How much of the error one clean sample is allowed to correct, once enough
     of them have been seen. Early samples count for more -- see the prior
     below -- so the estimate settles in a handful of ticks rather than a
     minute, and then stops moving perceptibly. ]]--
local PULSE_WEIGHT_FLOOR = 0.08

--[[ The estimate starts as if two seconds had already been observed three
     times. Without a prior the first sample would carry all the weight and be
     exactly the single noisy reading this is here to stop trusting. ]]--
local PULSE_PRIOR = 3

--[[ A gain this much of a period early cannot be the tick. Keep the window
     loose enough that a genuine pulse observed a little early because of frame
     timing can still correct the phase. ]]--
local PULSE_EARLY = 0.75

-- and on the beat, size stops mattering: a small gain there is a full tick
-- against a nearly full bar
local PULSE_ONBEAT = 0.9

OB.tickers.pulse = {
    Reset = function(t, now)
        t.start = now
        t.period = PULSE_PERIOD
        t.lastTick = nil
        t.tickSize = nil

        -- The beat is unknown again, so a bigger gain may re-anchor freely
        -- until one has been timed against another. See the accept branch.
        t.tickConfirmed = nil

        -- and the cadence goes back to the assumption, not to whatever the
        -- previous form or power type happened to pulse at
        t.periodSamples = nil
    end,

    Observe = function(t, now, current, previous)
        local diff = current - previous

        if diff > 0 then
            local since = t.lastTick and (now - t.lastTick)
            local early = since and (since < t.period * PULSE_EARLY)

            --[[ The full tick is the largest gain that keeps happening, so the
                 largest seen is the best estimate of it without knowing the
                 class, the talents or the server's numbers. ]]--
            local partial = t.tickSize and (diff < t.tickSize)
            local offBeat = since and (since < t.period * PULSE_ONBEAT)

            --[[ A gain bigger than anything seen so far is believed *on the
                 timing*, because the timing is only as good as the anchor it
                 came from -- and a bigger gain is proof that anchor was not a
                 full tick.

                 This is what rescues the first observation after a login or a
                 form change. There is no history then, so the first gain anchors
                 the cycle whatever it was; if it was a two-energy refund, the
                 next real tick is ten times larger and takes the phase back at
                 once instead of over the two cycles the timing test alone would
                 need. That still works: the refund sets `lastTick`, the real
                 tick lands a full period later, and a period later is not
                 early. ]]--
            local biggest = diff > (t.tickSize or 0)

            --[[ **Nothing arrives early once the beat is known, however big it
                 is.**

                 This read `biggest or (...)`, so any gain larger than the
                 running estimate re-anchored the cycle no matter when it landed
                 -- and the preamble above names the case that breaks it:
                 Relentless Strikes pays 25 against a 20 energy tick, on every
                 finisher. Each one moved `start` into the middle of the beat,
                 and the genuine tick that followed then read as early and was
                 thrown away. On a rogue that is most of a fight, which is what
                 "the spark is not synced to the ticker" looks like from the
                 outside. Thistle Tea is the same case on a longer timer.

                 **But only once the beat is known**, which is what
                 `tickConfirmed` is for. `biggest` has a real job at bootstrap:
                 the first gain after a login or a form change anchors the cycle
                 whatever it was, and if that was a two energy refund then the
                 real tick -- ten times larger, and arriving whenever it arrives
                 -- has to be allowed to take the phase back. Vetoing early gains
                 from the very first observation would leave the sweep anchored
                 to the refund for a full cycle.

                 So the veto applies only against an anchor that has itself been
                 confirmed by timing: a gain accepted a proper interval after the
                 one before it. Until then a bigger gain is still better evidence
                 than an anchor nobody has checked. ]]--
            local settled = early and t.tickConfirmed

            if not settled
                    and (biggest or (not early and not (partial and offBeat))) then
                if diff > (t.tickSize or 0) then t.tickSize = diff end

                --[[ **Confirmed means "a proper interval after the last one".**

                     Not merely accepted: the bootstrap path accepts a refund
                     with no history at all, and an anchor nobody has timed is
                     exactly the one a bigger gain should still be allowed to
                     overrule. `since` has to exist -- so there was a previous
                     tick to measure from -- and the gap has to be a real one.

                     Once set it stays set. The cadence does not change while the
                     character does; `Reset` clears it, which is a login, a form
                     change, or a new power type. ]]--
                if since and not early then t.tickConfirmed = true end

                --[[ **The cadence, from clean samples only.**

                     `since` has to be a plausible tick interval in its own
                     right: after a rejected observation the next accepted gain
                     is two periods away, and feeding that in would teach the
                     sweep to run at half speed. `partial` is excluded for the
                     same reason -- a small gain against a nearly full bar is a
                     real tick, and its *timing* is fine, but it tends to arrive
                     alongside the cap and is not worth the risk.

                     Weighted by how many samples have been seen, so the estimate
                     settles quickly and then holds still. See PULSE_PRIOR. ]]--
                if since and not early and not partial
                        and since >= PULSE_MIN and since <= PULSE_MAX then
                    t.periodSamples = (t.periodSamples or PULSE_PRIOR) + 1

                    local weight = 1 / t.periodSamples
                    if weight < PULSE_WEIGHT_FLOOR then
                        weight = PULSE_WEIGHT_FLOOR
                    end

                    local blended = (t.period * (1 - weight)) + (since * weight)

                    if blended < PULSE_MIN then blended = PULSE_MIN end
                    if blended > PULSE_MAX then blended = PULSE_MAX end

                    t.period = blended
                end

                t.lastTick = now
                t.start = now
                return true
            end
        end

        --[[ Nothing seen, so the cycle advances by *whole* periods rather than
             restarting. Restarting would put the sweep off-beat, so the spark
             would be in the wrong place the moment you dumped energy, which is
             precisely when it matters. This moves `start` and never `lastTick`:
             a projection is not an observation. ]]--
        while now >= t.start + t.period do
            t.start = t.start + t.period
        end

        return false
    end,
}

--[[ Mana: there is no pulse to observe, because spirit and mp5 both trickle in
     between ticks. The sweep is inferred from what the last change looked like.

     Spending starts a five second window -- the five-second rule, during which
     spirit regen is suppressed and only mp5 gear keeps paying out. A gain large
     enough to stand out from the remembered trickle is a real tick and starts a
     two second window.

     Restructured from Equadis' UnitFrames, where the same logic was spread over
     manaStart / manaPeriod / manaRestart / manaTrickle plus a deferred-restart
     flag. The sweep length is one piece of state here. ]]--
OB.tickers.fsr = {
    Reset = function(t, now)
        t.start = now
        t.period = 2
        t.trickle = nil
    end,

    Observe = function(t, now, current, previous)
        local diff = current - previous

        if diff < 0 then
            t.start = now
            t.period = 5
            return true
        end

        if diff > 0 then
            local threshold = 5
            if t.trickle then threshold = t.trickle * 1.2 end

            if t.period ~= 5 and diff > threshold then
                t.start = now
                t.period = 2
                return true
            end

            t.trickle = diff
        end

        -- ticks keep coming whether or not mana moved, so roll the window over
        if now >= t.start + t.period then
            t.start = now
            t.period = 2
        end

        return false
    end,
}

-- rage and happiness do not tick
OB.powerTickers = { [0] = "fsr", [2] = "pulse", [3] = "pulse" }

--[[ Predicates for this module's own rows: which settings have stopped doing
     anything because the switch above them is off.

     A setting in that state is **greyed, not hidden**. Removing it from the page
     says it does not exist; dimming it says it is not currently in charge, which
     is the true thing and the one that survives switching the toggle back. ]]--
OB.predicates = OB.predicates or {}

local function powerConfig()
    return OB.profile and OB.profile.modules and OB.profile.modules.power
end

-- the spark's colour, with the spark switched off for this power type
OB.predicates.power_no_ticker = function()
    local m = OB.modules.power
    local variant = m and m.VariantTable and m:VariantTable()
    return (variant and variant.ticker == "never") and true or false
end

-- where to put a number that is not being drawn
OB.predicates.power_no_text = function()
    local cfg = powerConfig()
    return (cfg and cfg.textMode == "none") and true or false
end

-- ---------------------------------------------------------------------------
-- rage decay
--
-- Rage is the one resource that leaks while you stand still, and the rate is a
-- server constant the 1.12 client never handed to Lua. Turtle may well have
-- retuned it. So it is measured rather than assumed: the marker points wherever
-- this server's own behaviour says it will, and needs no constant to keep up to
-- date.
--
-- A run of falling values is anchored and then divided. Two things end a run:
-- any gain, and a step too abrupt to be decay -- spending rage is not the bar
-- draining, and averaging a cost into the rate would put the marker on the
-- floor. The estimate is taken once enough rage has actually been lost rather
-- than after a fixed wait, so it holds whether the server ticks four times a
-- second or once.
-- ---------------------------------------------------------------------------

local DECAY_MIN_DROP = 2    -- rage that must be lost before a rate is believed
local DECAY_SPEND = 5       -- a single step larger than this is a cost

-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

local M = OB.RegisterModule({
    id = "power",
    name = "Resource",
    bar = "resource",
    priority = 10,
    renders = "bar",
    tickly = true,

    defaults = {
        textMode = "value",
        textPos = 50,
        tickerColor = { 1, 1, 1, 1 },
        fsrShade = true,
        fsrColor = { 0.3, 0.5, 1.0, 0.25 },

        rageDecay = false,
        rageDecaySeconds = 3,
        rageDecayColor = { 1.0, 0.85, 0.35, 0.9 },

        --[[ Keyed by UnitPowerType. Only colour and ticker mode live here: the
             per-type entry is what a druid swaps between, and everything else
             about the bar has to stay put across that swap. ]]--
        byType = {
            [0] = { color = { 0.20, 0.40, 0.90, 1 }, ticker = "always" },
            [1] = { color = { 0.90, 0.20, 0.20, 1 }, ticker = "never" },
            [2] = { color = { 1.00, 0.50, 0.25, 1 }, ticker = "always" },
            [3] = { color = { 0.87, 0.86, 0.00, 1 }, ticker = "always" },
            [4] = { color = { 0.00, 0.80, 0.20, 1 }, ticker = "never" },
        },
    },

    options = {
        { "Bar Color", "@variant:color", "color", true },
        { "Ticker Visibility", "@variant:ticker", OB.Enum(
                { "always", "nofull", "never" },
                { "Show Always", "Hide When Full", "Never Show" }) },
        { "Ticker Color", "tickerColor", "color", true,
          nil, nil, nil, nil, "@power_no_ticker" },
        { "Text", "textMode", OB.Enum(
                { "none", "value", "percent", "max", "valuepct", "maxpct" },
                { "None", "Current Only", "Percentage", "Current / Max",
                  "Current (Percent)", "Current / Max (Percent)" }) },
        { "Text Position", "textPos", "slider", 0, 100, 1,
          nil, nil, "@power_no_text" },

        --[[ The two `@power_*` dependencies **hide** rather than grey, and that
             is the distinction: a rage setting on a mana bar has no meaning at
             all, where a colour whose switch is off still means what it says and
             starts applying again the moment the switch comes back. ]]--
        { "Shade Five Second Rule", "fsrShade", "boolean", nil, nil, nil, nil, "@power_mana" },
        { "Five Second Rule Color", "fsrColor", "color", true,
          nil, nil, nil, "@power_mana", "!fsrShade" },
        { "Mark Rage Decay", "rageDecay", "boolean", nil, nil, nil, nil, "@power_rage" },
        { "Decay Look Ahead", "rageDecaySeconds", "slider", 1, 10, 1,
          nil, "@power_rage", "!rageDecay" },
        { "Decay Marker Color", "rageDecayColor", "color", true,
          nil, nil, nil, "@power_rage", "!rageDecay" },
    },

    requires = { "UnitMana", "UnitManaMax", "UnitPowerType" },

    events = {
        "UNIT_MANA", "UNIT_MAXMANA",
        "UNIT_RAGE", "UNIT_MAXRAGE",
        "UNIT_ENERGY", "UNIT_MAXENERGY",
        "UNIT_FOCUS", "UNIT_MAXFOCUS",
        "UNIT_HAPPINESS",
        "UNIT_DISPLAYPOWER",
        "PLAYER_ENTERING_WORLD",
    },
})

M.state = { start = 0, period = 2 }

function M:Config()
    return OB.profile.modules.power
end

--[[ The variant for the power type in play. Also the panel's "variant" scope, so
     a druid editing the bar colour edits the colour of the form they are in. ]]--
function M:VariantTable()
    local cfg = self:Config()
    local t = self.ptype or UnitPowerType("player") or 0
    return cfg.byType[t] or cfg.byType[0]
end

--[[ The one accessor, and the one place test mode substitutes. Everything below
     draws from this, so the preview path and the live path are identical. ]]--
function M:GetValue()
    if OB.testMode then
        return OB.test.power or 0, OB.test.powerMax or 100
    end
    return UnitMana("player") or 0, UnitManaMax("player") or 0
end

--[[ Adopt the current power type: pick the ticker, restart it, and re-seed the
     last-known value.

     That last step is not optional. Shifting form changes what UnitMana reports
     in a single step, and without re-seeding, the jump reads as an enormous
     regeneration tick and yanks the sweep to the wrong phase. ]]--
function M:AdoptPowerType(now)
    self.ptype = UnitPowerType("player") or 0

    local strategy = OB.powerTickers[self.ptype]
    self.ticker = strategy and OB.tickers[strategy] or nil

    if self.ticker then self.ticker.Reset(self.state, now) end

    local value = self:GetValue()
    self.last = value
end

function M:OnBind(slot)
    self:AdoptPowerType(GetTime())
end

--[[ Watch a run of falling rage and keep a rate estimate. See the note above the
     constants for why this is measured and not assumed.

     `decayFrom` doubles as the "rage is falling right now" flag, which is what
     the marker keys off: a projection drawn while rage is climbing points at a
     number that will never happen. ]]--
function M:ObserveRageDecay(now, current, previous)
    local diff = current - previous

    if diff > 0 or diff < -DECAY_SPEND then
        self.decayFrom = nil
        return
    end

    --[[ Rage held still. Not a gain, so an open run continues -- the client
         reports rage in whole numbers and a slow drain shows as flat frames
         between steps -- but it must not *start* one. Without this, sitting at
         full rage arms a run and the marker appears on a bar that is not going
         anywhere. ]]--
    if diff == 0 then return end

    if not self.decayFrom then
        self.decayFrom = { at = now, value = current }
        return
    end

    local elapsed = now - self.decayFrom.at
    local lost = self.decayFrom.value - current

    if elapsed <= 0 or lost < DECAY_MIN_DROP then return end

    self.rageRate = lost / elapsed

    -- re-anchor so the estimate keeps tracking instead of freezing on the first
    -- sample it ever took
    self.decayFrom = { at = now, value = current }
end

function M:OnStyle(slot)
    local cfg = self:Config()
    local variant = self:VariantTable()

    OB.SetBarColor(self.frame, variant.color)

    local spark = OB.BarSpark(self.frame)
    spark:SetHeight(slot.h * 2)
    spark:SetVertexColor(cfg.tickerColor[1], cfg.tickerColor[2],
            cfg.tickerColor[3], cfg.tickerColor[4] or 1)
end

function M:OnEvent()
    if event == "UNIT_DISPLAYPOWER" or event == "PLAYER_ENTERING_WORLD" then
        self:AdoptPowerType(GetTime())
        OB.SetDirty(self)
        -- the colour belongs to the new variant, so the bar has to be restyled
        if self.frame and self.slotId then
            self:OnStyle(OB.profile.slots[self.slotId])
        end
        return
    end

    if arg1 and arg1 ~= "player" then return end
    OB.SetDirty(self)
end

function M:OnUpdate(now)
    local cfg = self:Config()
    local value, max = self:GetValue()

    if self.last == nil then self.last = value end

    --[[ Test mode drives the cycle itself, so the observer is skipped: otherwise
         the simulated numbers would be read as real regeneration and fight the
         script for control of the phase. ]]--
    if self.ticker and not OB.testMode then
        if self.ticker.Observe(self.state, now, value, self.last) then
            OB.SetDirty(self)
            if OB.profile.audible and value > self.last then
                PlaySound("UChatScrollButton")
            end
        end
    end

    --[[ Unlike the tickers, this one runs in test mode too. It has no cycle for
         the preview to fight over -- it only learns a number -- and letting the
         simulated drain feed it is what puts the marker on screen before anyone
         has stood in a field waiting for real rage to leak away. ]]--
    if self.ptype == 1 then
        self:ObserveRageDecay(now, value, self.last)
    end

    self.last = value

    local bar = self.frame
    local slot = OB.profile.slots[self.slotId]
    local variant = self:VariantTable()

    -- three-state visibility, kept per power type so a druid can tick in cat
    -- form and stay silent in bear
    local mode = variant.ticker
    local show = self.ticker
            and (mode == "always" or (mode == "nofull" and value < max))

    if show then
        OB.DrawSpark(bar, self.state.start, self.state.period, now, slot.flip)
        OB.BarSpark(bar):Show()
    elseif bar.spark then
        bar.spark:Hide()
    end

    --[[ Shade the five second rule as a shrinking region over the fill. An
         invisible state you have to count out in your head is not a readout. ]]--
    if cfg.fsrShade and self.ticker and self.state.period == 5 then
        local phase = (now - self.state.start) / self.state.period
        if phase < 0 then phase = 0 end
        if phase > 1 then phase = 1 end
        local c = cfg.fsrColor
        OB.SetBarOverlay(bar, 1 - phase, slot.flip, c[1], c[2], c[3], c[4] or 0.25)
    elseif bar.overlay then
        bar.overlay:Hide()
    end
end

function M:OnDraw()
    local cfg = self:Config()
    local value, max = self:GetValue()

    local fraction = 0
    if max > 0 then fraction = value / max end

    local slot = OB.profile.slots[self.slotId]
    OB.SetBarFill(self.frame, fraction, slot.flip)
    OB.SetBarText(self.frame, self.frame.center,
            OB.FormatValue(value, max, cfg.textMode), cfg.textPos)

    --[[ Where rage will have leaked to by the time the look-ahead is up, as a
         line on the bar. Drawn only while it is actually leaking and only once a
         rate has been observed, so it never asserts a number the addon has not
         watched this server produce. ]]--
    if cfg.rageDecay and self.ptype == 1 and self.decayFrom and self.rageRate
            and max > 0 then
        local projected = value - (self.rageRate * cfg.rageDecaySeconds)
        if projected < 0 then projected = 0 end

        local c = cfg.rageDecayColor
        OB.SetBarTick(self.frame, 1, projected / max, slot.flip,
                c[1], c[2], c[3], c[4] or 1)
    else
        OB.HideBarTicks(self.frame)
    end
end

-- ---------------------------------------------------------------------------
-- test mode
--
-- The cycle keys off the power type actually in play, so a warrior previews rage
-- building and dumping rather than watching an energy pattern in red.
-- ---------------------------------------------------------------------------

function M:TestStart(now)
    self.ptype = UnitPowerType("player") or 0

    -- read the real maximum straight from the API: OB.testMode is already on by
    -- the time this runs, so GetValue would hand back the (empty) test values
    local realMax = UnitManaMax("player")
    if not realMax or realMax < 1 then realMax = 100 end

    OB.test.powerMax = realMax
    OB.test.powerRefill = false
    OB.test.powerSpendAt = now + 1
    OB.test.powerTickAt = now + 2

    if self.ptype == 1 then
        -- rage starts empty and builds
        OB.test.power = 0
        OB.test.powerRefill = true
        OB.test.powerDecayAt = now + 1
    else
        OB.test.power = realMax
    end

    self.state.start = now
    self.state.period = 2
end

function M:TestStop()
    -- the observer was idle throughout, so a stale value would read as a
    -- phantom tick the moment it resumes
    self.last = self:GetValue()
    self.state.start = GetTime()
end

function M:TestStep(now)
    local max = OB.test.powerMax or 100
    local step = max * 0.2
    local spend = max * 0.4
    local changed = false

    if now >= OB.test.powerTickAt then
        OB.test.powerTickAt = now + 2

        OB.test.power = OB.test.power + step
        if OB.test.power > max then OB.test.power = max end
        if OB.test.powerRefill and OB.test.power >= max then
            OB.test.powerRefill = false
        end
        if not OB.test.powerRefill then OB.test.powerSpendAt = now + 1 end

        -- keep the spark phase-locked to the simulated tick
        self.state.start = now
        self.state.period = 2

        if OB.profile.audible then PlaySound("UChatScrollButton") end
        changed = true
    end

    if not OB.test.powerRefill and OB.test.powerSpendAt > 0
            and now >= OB.test.powerSpendAt then
        OB.test.powerSpendAt = 0
        OB.test.power = OB.test.power - spend

        if OB.test.power <= 0 then
            OB.test.power = 0
            OB.test.powerRefill = true
        end

        -- a spend is what starts the five second rule, so the preview shows it
        if self.ticker == OB.tickers.fsr then
            self.state.start = now
            self.state.period = 5
        end

        changed = true
    end

    --[[ Rage leaks in the preview because the decay marker has nothing to point
         at otherwise. A whole number once a second, so the floor below cannot
         eat a fractional step -- and the rate the observer then measures off
         this is the preview's rate, not a claim about any server. ]]--
    if self.ptype == 1 and not OB.test.powerRefill
            and now >= (OB.test.powerDecayAt or 0) then
        OB.test.powerDecayAt = now + 1

        OB.test.power = OB.test.power - 3
        if OB.test.power < 0 then OB.test.power = 0 end
        changed = true
    end

    OB.test.power = floor(OB.test.power)
    if changed then OB.SetDirty(self) end
end
