--[[ Equadis' Classic Overhaul :: swing timers

  Main hand and off hand, as two module ids over one implementation table. A
  third (swing_ranged) drops in the same way once the ranged timer lands.

  Swing tracking is a data source rather than a renderer, so it runs on its own
  event frame instead of on either module. Hanging it off swing_main would break
  the off-hand bar the moment someone emptied the main hand slot, and having both
  modules register the same events would attribute every swing twice.
]]--

local OB = EquadisClassicOverhaul

local swing = {
    attacking = false,
    mainStart = 0,
    offStart = 0,

    -- the ranged cycle runs independently: a hunter shooting is not swinging,
    -- and the two toggles are different events
    shooting = false,
    rangedStart = 0,
}

OB.swing = swing

-- ---------------------------------------------------------------------------
-- tracking
-- ---------------------------------------------------------------------------

local function startSwings()
    if OB.testMode then return end
    local now = GetTime()
    swing.attacking = true
    swing.mainStart = now
    swing.offStart = now
end

--[[ Auto attack stopped: the target died, moved out of range, or the player
     toggled attack off. The bars go idle rather than freezing at full.

     Without handling the stop, nothing ever clears the timers and both bars sit
     at 100% forever -- which looks exactly like a working, permanently ready
     swing. ]]--
local function stopSwings()
    if OB.testMode then return end
    swing.attacking = false
    swing.mainStart = 0
    swing.offStart = 0
end

--[[ A white swing landed (hit or miss). Vanilla's combat log does not say which
     hand it came from, so it is attributed to whichever hand has been ready
     longest.

     "Ready longest" -- largest overdue value -- and NOT "closest to its due
     time". When anything stops the swings for a while (a stun, a knockdown,
     running out of range, facing away) both hands end up overdue by different
     amounts. Ranking by distance from due lets the less-overdue hand win every
     single comparison, so the other hand is never re-anchored and its bar stays
     pinned at 100% forever. Ranking by most-overdue always re-anchors the
     starved hand first, so the pair recovers on its own within a swing or two.

     This is the single subtlest piece of logic carried over from RogueBars and
     the self-healing property is the entire reason for it. ]]--
local function swingLanded()
    if OB.testMode then return end

    local now = GetTime()
    local mainSpeed, offSpeed = UnitAttackSpeed("player")

    --[[ A landed swing proves we are attacking even if the toggle event was
         missed -- already swinging on login, or the event was eaten -- so the
         bars recover on their own rather than staying idle. ]]--
    if not swing.attacking then
        swing.attacking = true
        swing.mainStart = now
        swing.offStart = now
    end

    if offSpeed and offSpeed > 0 then
        local mainReady = now - (swing.mainStart + (mainSpeed or 0))
        local offReady = now - (swing.offStart + offSpeed)

        if mainReady >= offReady then
            swing.mainStart = now
        else
            swing.offStart = now
        end
    else
        swing.mainStart = now
    end
end

-- ---------------------------------------------------------------------------
-- ranged
-- ---------------------------------------------------------------------------

local function startShooting()
    if OB.testMode then return end
    swing.shooting = true
    swing.rangedStart = GetTime()
end

local function stopShooting()
    if OB.testMode then return end
    swing.shooting = false
    swing.rangedStart = 0
end

--[[ Re-anchor the ranged cycle on a shot that landed.

     CHAT_MSG_SPELL_SELF_DAMAGE carries every spell the player lands, not just
     the auto shot, and vanilla's combat log does not name the source in any form
     this phase can read -- recovering that needs the localisation-aware parser
     Phase 3 brings. So the event is filtered by *timing* instead: an auto shot
     can only land at the end of its own cycle, and anything arriving early in
     the cycle is some other spell and must not move the anchor.

     Three quarters of a cycle is the threshold. Too strict and a shot fired at a
     moving target never re-anchors; too loose and an instant cast fired while
     the shot is pending drags the bar backwards. Getting it wrong is
     self-correcting either way -- the next START_AUTOREPEAT_SPELL re-seeds --
     which is why a heuristic is acceptable here and was not acceptable for the
     main and off hand pair. ]]--
local function shotLanded()
    if OB.testMode or not swing.shooting then return end

    local now = GetTime()
    local speed = UnitRangedDamage("player")
    if not speed or speed <= 0 then return end

    if (now - swing.rangedStart) < (speed * 0.75) then return end

    swing.rangedStart = now
end

--[[ **The abilities that are swung rather than cast.**

     Heroic Strike, Cleave, Maul and Raptor Strike are queued onto your next
     melee swing: pressing one does nothing until the weapon comes round, and
     then it *replaces* the white hit. The swing is spent.

     The client does not report them as melee. There is no
     `CHAT_MSG_COMBAT_SELF_HITS` line for a Heroic Strike -- it arrives as
     `CHAT_MSG_SPELL_SELF_DAMAGE`, the same event a Fireball uses, because as
     far as the combat log is concerned it is a spell.

     So the swing timer never saw them. A warrior using Heroic Strike on cooldown
     -- which is every warrior -- had a swing bar that filled up and then sat
     there, because the event that would have reset it never came and the one
     that did was being handed to the ranged timer. That is the whole of the
     bug: the bar was not wrong about the swing, it never heard about it.

     **Matched by name, which is a locale assumption and the only one
     available.** The combat log gives no flag separating an on-next-swing
     ability from any other spell; the text is the only difference there is. On
     an English client this is exact. On another it stops recognising them,
     which is where the module was already. ]]--
local ON_NEXT_SWING = {
    ["Heroic Strike"] = true,
    ["Cleave"] = true,
    ["Maul"] = true,
    ["Raptor Strike"] = true,
}

--[[ Whether a spell-damage line was actually a melee swing. Exposed on `OB` so
     the tests and anything else asking get the same answer this uses, rather
     than a second copy of the list. ]]--
function OB.IsOnNextSwing(line)
    if type(line) ~= "string" then return false end

    for name in pairs(ON_NEXT_SWING) do
        --[[ Plain find rather than a pattern: these are names, and one of them
             would otherwise have to be escaped the day somebody adds an ability
             with a hyphen in it. ]]--
        if string.find(line, name, 1, true) then return true end
    end

    return false
end

local tracker = CreateFrame("Frame", "EquadisClassicOverhaulSwing", UIParent)

tracker:SetScript("OnEvent", function()
    if event == "START_AUTOREPEAT_SPELL" then
        startShooting()
        return
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        stopShooting()
        return
    elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        --[[ **On-next-swing abilities arrive here rather than as melee**, and
             they spend the swing. Checked before the ranged path, because a
             Heroic Strike is a melee swing wearing a spell's event and belongs
             to the weapon timer. ]]--
        if OB.IsOnNextSwing(arg1) then
            swingLanded()
            return
        end

        shotLanded()
        return
    end

    --[[ PLAYER_ENTER_COMBAT and PLAYER_LEAVE_COMBAT are the melee auto-attack
         toggle in vanilla, not combat state. Combat state is
         PLAYER_REGEN_DISABLED / ENABLED, which hud.lua uses separately for
         visibility. Confusing the two is why the timers used to never stop. ]]--
    if event == "PLAYER_ENTER_COMBAT" then
        startSwings()
    elseif event == "PLAYER_LEAVE_COMBAT" then
        stopSwings()
    elseif event == "PLAYER_DEAD" then
        stopSwings()
        stopShooting()
    else
        swingLanded()
    end
end)

tracker:RegisterEvent("PLAYER_ENTER_COMBAT")
tracker:RegisterEvent("PLAYER_LEAVE_COMBAT")
tracker:RegisterEvent("PLAYER_DEAD")
tracker:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
tracker:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
tracker:RegisterEvent("START_AUTOREPEAT_SPELL")
tracker:RegisterEvent("STOP_AUTOREPEAT_SPELL")
tracker:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

-- ---------------------------------------------------------------------------
-- shared implementation
-- ---------------------------------------------------------------------------

--[[ Who can put a weapon in the off hand at all.

     1.12 has no `CanDualWield`, so this is a list and lists about class
     abilities age badly -- shamans got dual wield in the Burning Crusade, not
     here, and a server is free to disagree with any of it. Two things make that
     survivable. The consequence is only that a section is **greyed**, so a wrong
     entry costs appearance and never function; and an off hand that actually
     swings overrules the list for the rest of the session (see GetSpeed).

     If this needs correcting for a server, it is the one line to correct. ]]--
local DUAL_WIELD = { WARRIOR = true, ROGUE = true, HUNTER = true }

--[[ Greyed rather than hidden, and this is the exception that proves the rule.

     A setting the class can never use is normally removed outright -- there is
     no switch to put back, so dimming would imply one. The Off Hand bar is
     different because **its geometry is account-wide**: the rectangle a mage is
     looking at is the one their warrior actually uses. Take it off the mage's
     page and the profile has settings with no way to reach them; leave it
     dimmed and it reads as what it is, a bar that will not draw for *this*
     character. ]]--
OB.predicates = OB.predicates or {}

OB.predicates.no_dual_wield = function()
    if OB.dualWieldSeen then return false end
    return not DUAL_WIELD[OB.class]
end

--[[ True while the Bars page is showing the Off Hand bar to somebody who cannot
     use it. Separate from the module rows because the geometry rows are shared
     by every bar, so they can only be dimmed by asking which bar is selected. ]]--
OB.predicates.offhand_bar_unusable = function()
    if not OB.panel or OB.panel.bar ~= "offhand" then return false end
    return OB.predicates.no_dual_wield()
end

local function swingOptions(hand)
    local rows = {
        { "Bar Color", "color", "color", true },
        --[[ Everything below a Show switch greys out when that switch is off:
             a position and a precision for a number nobody is drawing still mean
             what they say, and start applying the moment the switch comes back.
             Removing them would say they no longer exist. ]]--
        { "Show Timer", "showTimer", "boolean" },
        { "Timer Position", "timerPos", "slider", 0, 100, 1,
          nil, nil, "!showTimer" },
        --[[ A list rather than a slider. Three values is not a range worth
             dragging through, and the saved numbers are unchanged either way. ]]--
        --[[ A list's third field is its values, so `width` takes the fourth and
             dependsOn and greyWhen stay at eight and nine -- the same two places
             as every other kind. Putting the greyWhen at eight makes it a
             dependsOn, which inverts the row: shown only while the switch is
             off, which is precisely backwards. ]]--
        { "Decimal Points", "decimals", OB.Enum({ 0, 1, 2 }, { "0", "1", "2" }),
          nil, nil, nil, nil, nil, "!showTimer" },

        { "Show Weapon Speed", "showSpeed", "boolean" },
        { "Weapon Speed Position", "speedPos", "slider", 0, 100, 1,
          nil, nil, "!showSpeed" },
        { "Deplete Instead Of Fill", "deplete", "boolean" },
    }

    --[[ The whole section dims for a class that cannot dual wield, added here
         rather than written into ten rows -- a reason repeated ten times is a
         reason that drifts, and this way a new row inherits it. ]]--
    if hand == "off" then
        for i = 1, table.getn(rows) do
            local row = rows[i]
            if row[9] then
                row[9] = row[9] .. ",@no_dual_wield"
            else
                row[9] = "@no_dual_wield"
            end
        end
    end

    return rows
end

-- plausible speeds for the preview, per hand, when nothing is equipped
local TEST_SPEED = { main = 2.6, off = 1.7, ranged = 2.9 }

local impl = {}

function impl:Config()
    return OB.profile.modules[self.id]
end

-- main and off hand speeds come from one call, so which one this module wants
-- is a property of the module, not a separate API
function impl:GetSpeed()
    local speed, start

    if self.hand == "ranged" then
        speed, start = UnitRangedDamage("player"), OB.swing.rangedStart
    else
        local mainSpeed, offSpeed = UnitAttackSpeed("player")
        if self.hand == "off" then
            speed, start = offSpeed, OB.swing.offStart

            --[[ An off hand that swings is proof this character can dual wield,
                 whatever the hardcoded list below believes. Remembered for the
                 session and only ever used to *stop* greying, so a server that
                 hands dual wield to a class vanilla never did corrects the panel
                 the first time somebody equips an off hand -- and unequipping it
                 again does not make the settings flicker back to grey. ]]--
            if speed and speed > 0 and not OB.testMode then
                OB.dualWieldSeen = true
            end
        else
            speed, start = mainSpeed, OB.swing.mainStart
        end
    end

    --[[ Unarmed, no off hand equipped, nothing ranged in the slot: the preview
         still has to animate, so test mode substitutes a plausible speed. Live
         play leaves it nil and the bar draws empty. ]]--
    if OB.testMode and (not speed or speed <= 0) then
        speed = TEST_SPEED[self.hand]
    end

    return speed, start
end

-- whether this hand's cycle is running. Melee and ranged have separate toggles,
-- and a hunter shooting is emphatically not auto attacking.
function impl:Active()
    if self.hand == "ranged" then return OB.swing.shooting end
    return OB.swing.attacking
end

function impl:SetStart(now)
    if self.hand == "ranged" then
        OB.swing.rangedStart = now
    elseif self.hand == "off" then
        OB.swing.offStart = now
    else
        OB.swing.mainStart = now
    end
end

function impl:OnStyle(slot)
    local cfg = self:Config()
    OB.SetBarColor(self.frame, cfg.color)
end

function impl:OnEvent()
    OB.SetDirty(self)
end

function impl:OnUpdate(now)
    local cfg = self:Config()
    local slot = OB.profile.slots[self.slotId]
    local bar = self.frame

    local speed, start = self:GetSpeed()

    --[[ Nothing in that hand: hide the bar outright rather than draw an empty
         one. SetBarFill(0) only hides the *fill*, which leaves the background
         painted -- an empty trough that reads as a broken bar rather than an
         absent one, and the first thing anyone asks about it is why their off
         hand timer is stuck at zero. ]]--
    if not speed or speed <= 0 then
        OB.SetBarShown(self, false)
        return
    end

    OB.SetBarShown(self, true)

    --[[ The bar shows how charged the swing is, so idle -- not auto attacking --
         reads as ready rather than empty. The swing really is available. ]]--
    local elapsed = speed
    if self:Active() then
        elapsed = now - start
        if elapsed > speed then elapsed = speed end
        if elapsed < 0 then elapsed = 0 end
    end

    local timerText, speedText = "", ""

    if cfg.showTimer then
        timerText = string.format("%." .. (cfg.decimals or 1) .. "f", speed - elapsed)
    end
    if cfg.showSpeed then
        speedText = string.format("[%.2f]", speed)
    end

    -- fill: empty right after swinging, full when ready. deplete: the reverse.
    local shown = elapsed
    if cfg.deplete then shown = speed - elapsed end

    OB.SetBarFill(bar, shown / speed, slot.flip)

    --[[ One slot each, always the same slot, and the position setting decides
         where that slot sits. Swapping the two used to mean swapping which
         string went into which fixed anchor; now neither is fixed, and dragging
         one past the other is a thing the player can do rather than a mode. ]]--
    OB.SetBarText(bar, bar.left, timerText, cfg.timerPos)
    OB.SetBarText(bar, bar.right, speedText, cfg.speedPos)
end

-- the sweep is continuous, so OnUpdate does the drawing and OnDraw only has to
-- catch the frame an event lands on
function impl:OnDraw()
    self:OnUpdate(GetTime())
end

--[[ Each module starts only its own cycle. The three share one state table, so
     a module setting a flag it does not own would start a bar the user is not
     previewing -- and stop it again when a different module's TestStop ran. ]]--
function impl:TestStart(now)
    if self.hand == "ranged" then
        OB.swing.shooting = true
    else
        OB.swing.attacking = true
    end
    self:SetStart(now)
end

function impl:TestStop()
    if self.hand == "ranged" then
        OB.swing.shooting = false
    else
        OB.swing.attacking = false
    end
    self:SetStart(0)
end

function impl:TestStep(now)
    local speed, start = self:GetSpeed()
    if not speed or speed <= 0 then return end

    if (now - start) >= speed then self:SetStart(now) end
end

-- ---------------------------------------------------------------------------
-- the module ids
-- ---------------------------------------------------------------------------

local function defineSwing(id, name, hand, bar, color)
    local m = OB.RegisterModule({
        id = id,
        name = name,
        bar = bar,
        priority = 10,
        renders = "bar",
        tickly = true,

        defaults = {
            color = color,
            showTimer = true,
            showSpeed = true,

            --[[ Timer hard left, speed hard right: where the two used to be
                 nailed, so an upgrade changes nothing anybody can see. Swap Text
                 Sides was the old way to get between them and is now one point
                 on a slider that has the whole width in between. ]]--
            timerPos = 0,
            speedPos = 100,
            decimals = 1,
            deplete = false,
        },

        options = swingOptions(hand),
        requires = { "UnitAttackSpeed", "UnitRangedDamage" },
        events = { "PLAYER_ENTERING_WORLD", "UNIT_INVENTORY_CHANGED" },
    })

    m.hand = hand

    for key, fn in pairs(impl) do
        m[key] = fn
    end

    return m
end

defineSwing("mainhand", "Main Hand", "main", "mainhand", { 1.0, 0.635, 0.0, 1 })
defineSwing("offhand", "Off Hand", "off", "offhand", { 1.0, 0.745, 0.31, 1 })

--[[ The ranged timer has a bar of its own rather than sharing the main hand's.
     No class gate: a warrior with a gun gets it too, and anyone holding nothing
     ranged just sees the bar hide itself. ]]--
defineSwing("ranged", "Ranged Attack", "ranged", "ranged", { 0.45, 0.75, 1.0, 1 })
