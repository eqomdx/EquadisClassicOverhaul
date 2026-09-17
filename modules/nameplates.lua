--[[ Equadis' Classic Overhaul :: nameplates

  ShaguPlates parity pass.

  This module keeps the Overhaul's existing 1.12 nameplate detection and shared
  style system, then ports the high-value behaviours from ShaguPlates 5.4.21:

    * verified player/NPC identity and player class colours
    * target glow, target scaling and non-target fade
    * raid-marker sizing and positioning
    * elite/rare labels when the client exposes a classification
    * level colours and optional combat-coloured names
    * learned real mob-health estimates, stored in OB.mobHealth
    * per-plate debuff caches which are cleared when a plate is recycled
    * exact target/mouseover debuff scans plus optional name-based guessing
    * whitelist/blacklist debuff filters and top/bottom positioning
    * target-only cast-bar mode
    * optional hiding of the health bar for selected unit classes
    * click-through plates and vertical/offset presentation options

  Things deliberately not copied here are the parts which require SuperWoW,
  ShaguPlates' large shipped spell/debuff databases, or its locale-specific
  critter/totem name tables. The Overhaul already has cast/aura/roster services;
  this module consumes them instead of installing a second parallel framework.
]]--

local OB = EquadisClassicOverhaul
local floor, ceil, abs = math.floor, math.ceil, math.abs

-- ---------------------------------------------------------------------------
-- vanilla plate identity
-- ---------------------------------------------------------------------------

local PLATE_TYPE = "Button"
local PLATE_BORDER = "Interface\\Tooltips\\Nameplate-Border"

local PLATE_REGIONS = {
    "border", "glow", "name", "level", "levelicon", "raidicon",
}

OB.plateKinds = {
    "ENEMY_NPC", "NEUTRAL_NPC", "FRIENDLY_NPC",
    "ENEMY_PLAYER", "FRIENDLY_PLAYER",
}

function OB.PlateKind(r, g, b)
    if not r then return nil end
    if r > 0.9 and g < 0.2 and b < 0.2 then return "ENEMY_NPC" end
    if r > 0.9 and g > 0.9 and b < 0.2 then return "NEUTRAL_NPC" end
    if r < 0.2 and g > 0.9 and b < 0.2 then return "FRIENDLY_NPC" end
    if r < 0.2 and g < 0.2 and b > 0.9 then return "FRIENDLY_PLAYER" end

    --[==[ **Tapped by somebody else, which the client says in grey.**

         A mob another player hit first gives no loot and no experience, and the
         only place the client says so is the colour of this bar -- there is no
         `UnitIsTapped` on 1.12 and no flag on the plate to read.

         It was falling through to `nil` here, because the four above are the
         four reactions and grey is not a reaction. A `nil` kind takes the
         fallback colour, so every tapped mob came out wearing the enemy colour
         and looked exactly like one worth killing.

         Matched as a band rather than an exact triple: the value is the
         client's own and a server that nudges it slightly should still read as
         a tap. Near-equal channels with none of them bright is grey and nothing
         else in this list is close -- the four above all have one channel above
         0.9 and another below 0.2. ]==]
    if r > 0.35 and r < 0.65 and g > 0.35 and g < 0.65
            and b > 0.35 and b < 0.65 then
        return "TAPPED"
    end

    return nil
end

--[[ What the client draws a tapped mob in, and what this puts back. Named
     rather than spelled at the point of use, because it is read in two
     places. ]]--
OB.PLATE_TAPPED_COLOR = { 0.5, 0.5, 0.5, 1 }

local SHOWN_BY = {
    --[[ Shown on the same terms as any other hostile NPC: a tap changes who it
         is worth killing, not whether you want to see it. ]]--
    TAPPED = "enemyNpc",

    ENEMY_NPC = "enemyNpc",
    NEUTRAL_NPC = "neutralNpc",
    FRIENDLY_NPC = "friendlyNpc",
    ENEMY_PLAYER = "enemyPlayer",
    FRIENDLY_PLAYER = "friendlyPlayer",
}

local COLOR_KEY = {
    ENEMY_NPC = "enemyColor",
    NEUTRAL_NPC = "neutralColor",
    FRIENDLY_NPC = "friendlyNpcColor",
    ENEMY_PLAYER = "enemyColor",
    FRIENDLY_PLAYER = "friendlyPlayerColor",
}

local HIDE_HEALTH_KEY = {
    ENEMY_NPC = "hideEnemyNpcHealth",
    NEUTRAL_NPC = "hideNeutralNpcHealth",
    FRIENDLY_NPC = "hideFriendlyNpcHealth",
    ENEMY_PLAYER = "hideEnemyPlayerHealth",
    FRIENDLY_PLAYER = "hideFriendlyPlayerHealth",
}

local CLASS_SUFFIX = {
    elite = "+",
    rareelite = "R+",
    rare = "R",
    worldboss = "B",
    boss = "B",
}

OB.predicates = OB.predicates or {}
OB.predicates.plates_no_combo = function()
    return OB.class ~= "ROGUE" and OB.class ~= "DRUID"
end

--[[ True while the plates are in damage dealer mode, which is when the tank's
     three colours have nothing to paint. Handed the row, like every predicate;
     this one does not need it. ]]--
OB.predicates = OB.predicates or {}

OB.predicates.plates_dps_mode = function()
    local m = OB.modules and OB.modules.nameplates
    return not (m and m.TankMode and m:TankMode())
end

local M = OB.RegisterModule({
    id = "nameplates",
    name = "Nameplates",
    feature = true,
    styled = true,

    --[[ The shared Appearance rows are appended by the panel shell. Without
         this they are drawn on whichever tab is open, so Bar Texture and Font
         appear to be settings about debuffs, or about casting, depending on
         where you happen to be standing. They belong on General. ]]--
    appearanceSection = "general",
    renders = "none",
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
    tickly = true,

    defaults = {
        -- Which nameplates are allowed to remain visible once the client creates
        -- them. Hostile and neutral are on; friendlies are opt-in.
        enemyNpc = true,
        neutralNpc = true,
        enemyPlayer = true,
        friendlyNpc = false,
        friendlyPlayer = false,

        width = 120,
        height = 8,
        verticalHealth = false,
        verticalOffset = -10,

        -- Vanilla decides how aggressively nameplates push apart from the size
        -- of the native WorldFrame child, not from the custom artwork drawn on
        -- top of it. Keep overlap enabled by default, but use a deliberately
        -- modest collision reduction rather than the 1x1/full-collapse trick.
        allowOverlap = true,
        overlapAmount = 20,

        backgroundColor = { 0.04, 0.04, 0.04, 0.72 },

        --[==[ **The colour the border rests at.**

             A tint on the client's own border art rather than a colour of its
             own, so at rest a plate wears that art as drawn: the same edge the
             rest of the interface is bordered with, at the size a nameplate can
             carry. Dimmed rather than full white, which is the brightest thing
             that can be drawn and was being wrapped around every plate on
             screen at once.

             Rest is what a plate looks like when there is nothing to report --
             a friendly, or a mob on a client that cannot say what it is doing.
             A colour only means something when the absence of it does not. ]==]
        borderColor = { 0.65, 0.65, 0.65, 1.00 },

        --[==[ **How heavy the border is, which is one number and not two.**

             The art is drawn at whatever size the band allows, so how far out
             the border sits and how thick its line comes out are the same
             question asked once. Two sliders would have let them disagree, and
             a border three pixels out drawn at one pixel is the gap this whole
             pass exists to remove.

             Two rather than one by default: one is a hairline, and a hairline
             carrying a colour is a colour you have to look for. ]==]
        borderThickness = 2,

        showName = true,
        nameSize = 10,

        --[[ **An outline on plate text, whatever the shared font setting says.**

         Every other module in this addon draws onto a backdrop of its own, so
         the shared outline switch is a taste question there. A nameplate draws
         onto the world: a name in front of snow, a health percentage over a
         torch, a cast bar against sand. Unoutlined text does not look plainer
         there, it disappears -- and it disappears differently depending on
         which way the camera is facing, which is worse than either.

         ShaguPlates hardcodes `OUTLINE` on its health and cast text for exactly
         this reason and offers no way out. This is a switch instead, on by
         default: the reason is strong enough to be the default and not strong
         enough to be a rule. Off hands the text back to the shared setting. ]]--
        forceOutline = true,
        shortenNames = true,
        nameMaxLength = 20,
        nameInCombatColor = true,
        friendlyNameClassColor = false,

        showGuildName = false,
        guildNameSize = 8,
        totemIcons = false,
        totemIconSize = 22,

        showLevel = true,
        healthText = "none",
        healthTextPos = "CENTER",

        enemyColor = { 0.90, 0.20, 0.30, 0.90 },
        neutralColor = { 1.00, 1.00, 0.30, 0.90 },
        friendlyNpcColor = { 0.60, 1.00, 0.00, 0.90 },
        friendlyPlayerColor = { 0.20, 0.60, 1.00, 0.90 },
        enemyClassColor = true,
        friendlyClassColor = true,

        --[==[ **May a name alone say that a red plate is a player?**

             Enemy players and enemy NPCs share a colour, so nothing about a red
             plate says which it is. The only proof is `UnitIsPlayer`, and that
             needs a unit token -- which a plate has only while it is your target
             or under your cursor.

             Without this, a hostile player is grey until you click them and grey
             again the moment the plate is recycled, which is every time you turn
             the camera. Reported as exactly that, twice over.

             With it, a name the roster has recorded is taken as a player. The
             roster only ever learns players -- from `/who`, guild, friends,
             party and targeting -- so the inference is sound right up to the one
             case it is not: **an NPC named the same as a real player wears that
             player's class colour.** That is the ShaguPlates bug this was
             written to avoid, and it is why this is a switch rather than
             something folded into the code.

             On, because the failure it prevents is rare and cosmetic while the
             failure it causes is the feature not working. Names a real unit has
             confirmed are believed whatever this is set to; that costs nothing
             and is never wrong. ]==]
        rosterClasses = true,

        -- Hide only the health rectangle, not the nameplate itself. The critter
        -- and totem checks are exact once that plate has been target/mouseover.
        hideEnemyNpcHealth = false,
        hideNeutralNpcHealth = false,
        hideEnemyPlayerHealth = false,
        hideFriendlyNpcHealth = false,
        hideFriendlyPlayerHealth = false,
        hideCritterHealth = true,
        hideTotemHealth = true,

        -- Target treatment closely follows the reference defaults.
        --[==[ **The plate you are reading is the one that must not move.**

             Overlap is resolved by the engine, not here: it lays the native
             plates out before any of this artwork is drawn, and the only thing
             an addon can say about it is how big each plate's collision
             footprint is. There is no way to ask the engine to prefer one plate
             over another.

             There is a way to remove one from the argument. A plate with a 1x1
             footprint has nothing to push and nothing to be pushed by, so the
             engine leaves it exactly over its mob while every other plate goes
             on separating from its neighbours.

             The cost is that the others no longer avoid it, so a plate may sit
             across your target's. That is the right way round: a target that
             stays still and is sometimes overlapped can be read, and a target
             that slides out from under the cursor every time a third mob wanders
             into the pack cannot. ]==]
        targetHoldsPosition = true,

        markTarget = true,
        targetScale = 1.15,
        otherAlpha = 0.75,
        --[==[ **A glow, which is what this setting always claimed to be.**

             It used to draw the client's tooltip edge a second time, further
             out: an outline, with a gap between it and the bar, and the gap is
             what made a targeted plate look like it was wearing two borders.

             A glow has no edge in it. It is solid where it meets the bar and
             gone by the time it reaches the outside, so there is nothing for a
             gap to open behind. ]==]
        targetGlow = true,
        --[[ White, because it has to read over a plate of any colour and the
             border beside it is already carrying four. Customisable: it is one
             mark with one meaning, so any colour that shows up will do. ]]--
        targetGlowColor = { 1.00, 1.00, 1.00, 0.90 },

        --[[ **Which plate the cursor is on.**

             Nameplates are click targets and the client gives almost no sign of
             which one you are about to click: the plate under the cursor looks
             exactly like the plate beside it, and in a pull with six mobs
             stacked that is a real question with a real cost.

             Its own glow rather than a colour on the border, because the border
             is reporting something else and a plate can be hovered whatever it
             is doing. Tighter than the target's, so hovering the thing you
             already have targeted reads as two and not as one brighter one. ]]--
        mouseoverGlow = true,
        mouseoverGlowColor = { 0.60, 0.85, 1.00, 0.85 },
        colorByThreat = false,

        --[==[ **The bar as a ramp rather than as two colours.**

             `colorByThreat` answers one question -- does it have me -- and
             paints the bar one of two colours. That is the answer you need
             *after* something has gone wrong. The ramp answers the one you need
             before it: how close am I, which is the reading the threat meter
             exists for and the reason to look at it during a pull.

             Off, and behind `colorByThreat`, because it is a refinement of that
             switch rather than a second opinion about it.

             **Only ever on your target's plate.** Threat arrives on the addon
             channel as one set of figures about one mob, so there is no such
             thing as your threat on the plate over there -- and a bar coloured
             from another mob's numbers would be confidently wrong. ]==]
        threatGradient = false,
        threatColor = { 0.85, 0.20, 0.20, 1 },
        noThreatColor = { 0.20, 0.75, 0.25, 1 },

        --[==[ **The two states the colouring never had.**

             "On you" and "on somebody else" are only two of the four things a
             mob can be doing. It can also have no target at all -- not yet
             pulled, or just lost its threat table -- and it can be casting,
             which is the state you most want to notice because it is the one
             you act on.

             Grey for no target, because nothing is happening and a colour
             would claim otherwise. Blue for casting, and deliberately *not* the
             cast bar's gold: the bar sits directly beneath the border, so
             matching them made one state say itself twice, while blue is the
             only one of the four that nothing else on a plate already is. ]==]
        threatNoneColor = { 0.55, 0.55, 0.55, 1 },
        threatCastColor = { 0.25, 0.55, 1.00, 1 },

        --[==[ **On the border rather than the health bar.**

             The existing switch recolours the bar, which means the mob's own
             colour is what changes -- so a hostile plate stops looking hostile
             to say something about threat. ShaguPlates puts it on the border
             and leaves the bar alone, and that is why it reads as an indicator
             rather than as the mob changing.

             Separate from `colorByThreat` rather than replacing it: somebody
             who has been using the bar version should not have it moved out
             from under them.

             On by default, unlike the bar version. The border is drawn on every
             plate whatever this says; the only question is whether it carries a
             colour or stays at rest, and a border that could be telling you
             something and is not is the worse default. ]==]
        --[==[ **The four states are the glow's now, not the border's.**

             The border reads well as a border: a thin bright line hard against
             the bar, the same on every plate, telling you where one plate ends
             and the next begins. Making it carry the state as well asked one
             surface to do two jobs, and the one it was already doing is the one
             it does better.

             The glow has nothing else to say. It marked your target, which the
             target's size and the fade on every other plate already say twice
             over -- so it was a third statement of a fact, and it is the natural
             home for a fact nothing else is carrying.

             Retired rather than removed: `threatBorder` stays a key so a profile
             that has it does not error, and is no longer read. ]==]
        --[==[ **The four states are the border's, and the glow marks the
             target.**

             They were the border's, then the glow's, and now the border's
             again. The reasoning that moved them was that one surface should
             not do two jobs -- and it was the wrong surface that got moved.

             The border is on every plate, so a colour there answers "what is
             that one doing" about the whole screen at once, which is what the
             four states are for. The glow is on one plate by definition, so a
             colour there can only ever describe the plate you are already
             looking at -- and it is the one plate whose state you can read from
             the rest of the interface anyway.

             So the border carries the states and the glow says "this is your
             target" and nothing else. ]==]
        threatBorder = true,
        threatGlow = false,

        --[==[ **Whose side of the threat table you are on.**

             Every colour above answers the damage dealer's question: "it is on
             you" is the bad news and "it is on somebody else" is the good news.
             A tank asks the same question and wants the opposite answer -- the
             mob being on them is the whole job -- and reading the damage
             dealer's colours in reverse, in a fight, is a translation nobody
             should be doing.

             So a mode, and three colours of its own rather than the four above
             swapped round. Three because the tank's states are not the damage
             dealer's reversed: "no target" and "casting" are the same for
             everybody and keep their colours, and the middle state -- **about
             to lose it** -- has no counterpart on the other side. It needs the
             meter's numbers, which `RunnerUpThreatRatio` reads; without a
             packet the mode still answers *holding* and *lost* from the
             client alone, which is what it drew before the middle existed.

             Green for holding because that is the tank's "fine"; red for lost
             because it is the tank's emergency. Orange between them, and not
             yellow, because yellow beside green reads as a shade of it and
             this is a different state. ]==]
        threatMode = "dps",
        tankHoldingColor = { 0.20, 0.75, 0.25, 1 },
        tankLosingColor = { 1.00, 0.55, 0.10, 1 },
        tankLostColor = { 0.85, 0.20, 0.20, 1 },

        --[==[ **How close is too close**, as a percentage of your own threat.

             Eighty, because the game's own rule is that a melee attacker takes
             aggro at a hundred and ten and a ranged one at a hundred and thirty
             -- so at eighty there is a real margin left and the warning is a
             warning rather than an obituary. A tank running Salvation-less
             warlocks wants it higher; a tank with a fury warrior wants it lower.
             Fifty is the floor because below that every pull would spend its
             first ten seconds orange. ]==]
        tankLoseAt = 80,

        showCombo = false,
        comboColor = { 1.00, 0.85, 0.20, 1 },

        castbar = true,
        castTargetOnly = false,
        castbarHeight = 8,
        castColor = { 0.90, 0.80, 0.00, 1 },
        showCastName = true,

        --[==[ **The seconds left of the cast, at the end of the bar.**

             On, for the reason the debuff timers are: the bar answers "how far
             along" and the question being asked of it is "have I time to
             interrupt". Silent where the duration is not known rather than
             guessing at one -- see `CastTimeLeft`. ]==]
        castTimer = true,

        debuffs = true,
        guessDebuffs = true,
        --[==[ **How long is left, under each icon.**

             On, because a row of pictures answers "is it still on" and the
             question actually being asked is "for how much longer". 1.12
             returns no duration for another unit's aura, so this is the
             seen-at-plus-table answer and it is silent about any spell the
             table does not carry -- see `OB.AuraTimeLeft`. ]==]
        debuffTimers = true,

        debuffSize = 14,
        debuffCount = 8,
        debuffPosition = "TOP",
        debuffOffset = 4,
        debuffFilter = "none",
        debuffList = "",

        raidIconSize = 16,
        raidIconPosition = "CENTER",
        raidIconX = 0,
        raidIconY = -5,

        clickThrough = false,

        -- ShaguPlates' libhealth defaults: require four observed health changes
        -- and five percent of total damage before trusting an inferred maximum.
        healthEstimateHits = 4,
        healthEstimateDamage = 5,
    },

    options = {
        --[==[ **General is what the feature does, not one part of it.**

             This page opened on "Which Plates" and carried two more one-idea
             tabs at the bottom -- "Interaction", a single click-through
             switch, and "Health Estimation", two sliders. Three tabs for
             seven settings that are all answers to "how do nameplates behave
             here", while the tabs that earn their place -- casting, debuffs,
             colours -- are each about one visible part of a plate.

             A tab per setting is a filing cabinet with one sheet per drawer.
             These are gathered under General, which is where a reader looks
             for a thing that is not obviously about any one part. ]==]
        { "General", "__s_general", "section", "general" },
        { "Show Enemy NPCs", "enemyNpc", "boolean" },
        { "Show Neutral NPCs", "neutralNpc", "boolean" },
        { "Show Enemy Players", "enemyPlayer", "boolean" },
        { "Show Friendly NPCs", "friendlyNpc", "boolean" },
        { "Show Friendly Players", "friendlyPlayer", "boolean" },

        { "General", "__s_general2", "section", "general" },
        { "Click Through Nameplates", "clickThrough", "boolean" },

--[==[ **How much evidence before a guess is trusted, decided here.**

             These were two sliders. The client does not report a mob's real
             health, so the numbers govern how many damage events and how large
             a share of the bar are wanted before the addon believes it has
             worked the total out.

             Nobody can answer that from the options panel. Both numbers are
             about the statistics of a measurement nobody sees, and the only way
             to know whether four is better than six is to instrument it -- at
             which point it is a constant, not a preference. Left at the values
             they shipped with. ]==]

        { "Size And Position", "__s_geometry", "section", "geometry" },
        { "Width", "width", "slider", 60, 240, 5 },
        { "Health Bar Height", "height", "slider", 4, 30, 1 },
        { "Vertical Health Fill", "verticalHealth", "boolean" },
        { "Vertical Offset", "verticalOffset", "slider", -50, 50, 1 },
        { "Allow Nameplate Overlap", "allowOverlap", "boolean" },
        { "Overlap Amount", "overlapAmount", "slider", 0, 75, 5, nil,
          "allowOverlap" },
        { "Background Color", "backgroundColor", "color", true },
        { "Border Color", "borderColor", "color", true },
        { "Border Thickness", "borderThickness", "slider", 1, 6, 1 },

        { "Names And Levels", "__s_text", "section", "text" },
        { "Show Name", "showName", "boolean" },
        { "Name Size", "nameSize", "slider", 6, 20, 1,
          nil, nil, "!showName" },

        --[[ On by default: plate text is drawn onto the world rather than onto
             a backdrop, and unoutlined text over terrain does not read as
             plainer, it disappears. Off hands it back to the shared font
             setting for anybody who wants that. ]]--
        { "Always Outline Plate Text", "forceOutline", "boolean" },
        { "Shorten Long Names", "shortenNames", "boolean",
          nil, nil, nil, nil, nil, "!showName" },
        { "Shorten After", "nameMaxLength", "slider", 12, 40, 1,
          nil, nil, "!shortenNames" },
        { "Color Name When In Combat", "nameInCombatColor", "boolean" },
        { "Class Color Friendly Player Names", "friendlyNameClassColor", "boolean" },
        { "Show Level", "showLevel", "boolean" },

        --[==[ Off by default. A guild tag is a third line of text on something
             already carrying two, and in a city it is a third line on forty of
             them. Worth having, not worth assuming. ]==]
        { "Show Guild Name", "showGuildName", "boolean" },
        { "Guild Name Size", "guildNameSize", "slider", 6, 16, 1,
          nil, nil, "!showGuildName" },

        { "Replace Totems With Icons", "totemIcons", "boolean" },
        { "Totem Icon Size", "totemIconSize", "slider", 12, 40, 2,
          nil, nil, "!totemIcons" },

        { "Health Text", "healthText", OB.Enum(
                { "none", "value", "percent", "max", "valuepct", "maxpct", "deficit" },
                { "None", "Current Only", "Percentage", "Current / Max",
                  "Current (Percent)", "Current / Max (Percent)", "Deficit" }) },
        { "Health Text Position", "healthTextPos", OB.Enum(
                { "LEFT", "CENTER", "RIGHT" },
                { "Left", "Center", "Right" }) },

        { "Health Colors", "__s_colors", "section", "colors" },
        { "Enemy", "enemyColor", "color", true },
        { "Neutral", "neutralColor", "color", true },
        { "Friendly NPC", "friendlyNpcColor", "color", true },
        { "Friendly Player", "friendlyPlayerColor", "color", true },
        { "Class Color Enemy Players", "enemyClassColor", "boolean" },
        { "Trust The Player Database", "rosterClasses", "boolean" },
        { "Class Color Friendly Players", "friendlyClassColor", "boolean" },

        --[==[ **Which plates, and how much of one, read together.**

             The five switches above decide whether a kind of unit gets a plate
             at all; these seven decide whether the plate it got has a bar on
             it. They are the same question asked twice about the same list of
             units, and they were two tabs apart -- so working out what a
             critter would look like meant holding one page in your head while
             looking at another.

             One tab, two headings, the same order of units down both. ]==]
--[==[ **Two lists asking about the same units, one of them half-working.**

             Above: whether a kind of unit gets a plate. Here: whether the plate
             it got has a health bar. Both listed enemy NPCs, neutral NPCs,
             enemy players, friendly NPCs and friendly players, which is the
             same five units twice with a different verb.

             The second list also did not finish the job -- taking the bar away
             left the target glow behind, so the answer to "hide the health bar"
             was a plate with no bar and a glow where the bar had been.

             So the five go and the two that have no equivalent above stay.
             Critters and totems are not a kind of unit you choose to see; they
             are units you have already chosen to see and would rather not read
             a health bar for. ]==]
        { "Hide Health Bars", "__s_hidebars", "section", "general" },
        { "Critters", "hideCritterHealth", "boolean" },
        { "Totems", "hideTotemHealth", "boolean" },

        { "Your Target", "__s_target", "section", "target" },
        { "Mark Your Target", "markTarget", "boolean" },
        { "Your Target Never Moves", "targetHoldsPosition", "boolean" },
        { "Target Size", "targetScale", "slider", 100, 200, 5, 0.01,
          nil, "!markTarget" },
        { "Fade Other Plates To", "otherAlpha", "slider", 20, 100, 5, 0.01,
          nil, "!markTarget" },
        { "Target Glow", "targetGlow", "boolean" },
        { "Target Glow Color", "targetGlowColor", "color", true,
          nil, nil, nil, nil, "!targetGlow" },
        { "Mouseover Glow", "mouseoverGlow", "boolean" },
        { "Mouseover Glow Color", "mouseoverGlowColor", "color", true,
          nil, nil, nil, nil, "!mouseoverGlow" },
        --[==[ **Two switches, one set of colours.**

             The bar version and the border version are two presentations of the
             same fact, so they share the colours rather than each carrying a
             copy -- which is what the first attempt did, and it put two controls
             on one key. The naming check caught it, which is the whole reason
             that check exists: a duplicated key is two controls that quietly
             overwrite each other.

             Ungated for the same reason. A colour that belongs to either switch
             cannot be hidden behind one of them. ]==]
        --[[ First, because it changes what every colour below it means. ]]--
        { "Threat Mode", "threatMode",
          OB.Enum({ "dps", "tank" }, { "Damage / Healer", "Tank" }), 150 },

        { "Color Target By Threat", "colorByThreat", "boolean" },
        { "As A Gradient", "threatGradient", "boolean",
          nil, nil, nil, nil, nil, "colorByThreat" },
        { "Color The Border By Threat", "threatBorder", "boolean" },

        { "It Is On You", "threatColor", "color", true },
        { "It Is On Somebody Else", "noThreatColor", "color", true },
        { "It Has No Target", "threatNoneColor", "color", true },
        { "It Is Casting", "threatCastColor", "color", true },

        --[[ Greyed rather than removed in the other mode: the colours still
             mean what they say, and a row that vanishes reads as a setting this
             addon does not have. `@plates_dps_mode` is true while the mode is
             not Tank. ]]--
        { "Holding Threat", "tankHoldingColor", "color", true,
          nil, nil, nil, nil, "@plates_dps_mode" },
        { "About To Lose Threat", "tankLosingColor", "color", true,
          nil, nil, nil, nil, "@plates_dps_mode" },
        { "No Threat", "tankLostColor", "color", true,
          nil, nil, nil, nil, "@plates_dps_mode" },
        { "About To Lose At (%)", "tankLoseAt", "slider", 50, 100, 5,
          nil, nil, "@plates_dps_mode" },
        { "Show Combo Points On Target", "showCombo", "boolean",
          nil, nil, nil, nil, nil, "@plates_no_combo" },
        { "Combo Point Color", "comboColor", "color", true,
          nil, nil, nil, nil, "!showCombo" },

        { "Casting", "__s_cast", "section", "cast" },
        { "Show Cast Bars", "castbar", "boolean" },
        { "Only On Your Target", "castTargetOnly", "boolean",
          nil, nil, nil, nil, nil, "!castbar" },
        { "Cast Bar Height", "castbarHeight", "slider", 2, 20, 1,
          nil, nil, "!castbar" },
        { "Cast Bar Color", "castColor", "color", true,
          nil, nil, nil, nil, "!castbar" },
        { "Show Spell Name", "showCastName", "boolean",
          nil, nil, nil, nil, nil, "!castbar" },
        { "Show Seconds Left", "castTimer", "boolean",
          nil, nil, nil, nil, nil, "!castbar" },

        { "Debuffs", "__s_debuffs", "section", "debuffs" },
        { "Show Debuffs", "debuffs", "boolean" },
        { "Guess Debuffs Away From Target", "guessDebuffs", "boolean",
          nil, nil, nil, nil, nil, "!debuffs" },
        { "Show Time Left", "debuffTimers", "boolean", nil, nil, nil, nil,
          nil, "!debuffs" },
        { "Icon Size", "debuffSize", "slider", 8, 32, 1,
          nil, nil, "!debuffs" },
        { "How Many", "debuffCount", "slider", 1, 16, 1,
          nil, nil, "!debuffs" },
        { "Position", "debuffPosition", OB.Enum(
                { "TOP", "BOTTOM" }, { "Above", "Below" }) },
        { "Offset", "debuffOffset", "slider", 0, 20, 1,
          nil, nil, "!debuffs" },
        { "Filter", "debuffFilter", OB.Enum(
                { "none", "whitelist", "blacklist" },
                { "None", "Whitelist", "Blacklist" }) },
        { "Debuff List", "debuffList", "text", 200, 255 },

        { "Raid Marker", "__s_raid", "section", "raid" },
        { "Marker Size", "raidIconSize", "slider", 8, 40, 1 },
        { "Marker Position", "raidIconPosition", OB.Enum(
                { "TOP", "TOPRIGHT", "RIGHT", "BOTTOMRIGHT", "BOTTOM",
                  "BOTTOMLEFT", "LEFT", "TOPLEFT", "CENTER" },
                { "Top", "Top Right", "Right", "Bottom Right", "Bottom",
                  "Bottom Left", "Left", "Top Left", "Center" }) },
        { "Marker X Offset", "raidIconX", "slider", -50, 50, 1 },
        { "Marker Y Offset", "raidIconY", "slider", -50, 50, 1 },

    },
})

function M:Config()
    return OB.profile.modules.nameplates
end

-- ---------------------------------------------------------------------------
-- learned mob health (ShaguPlates libhealth technique)
-- ---------------------------------------------------------------------------

local healthLearn = {
    key = nil,
    damage = 0,
    startPercent = nil,
}

local function plateLevelText(unit)
    if not UnitExists(unit) then return nil end
    local level = UnitLevel(unit)
    if level and level > 0 then return level end
    return nil
end

local function mobHealthKey(name, level)
    if not name or name == "" then return nil end
    if not level or level <= 0 then return nil end
    return name .. ":" .. level
end

local function resetHealthLearning()
    healthLearn.key = nil
    healthLearn.damage = 0
    healthLearn.startPercent = nil

    if not UnitExists("target") then return end
    if UnitIsPlayer and UnitIsPlayer("target") then return end

    local max = UnitHealthMax("target") or 0
    if max ~= 100 then return end

    local name = UnitName("target")
    local level = plateLevelText("target")
    local key = mobHealthKey(name, level)
    if not key then return end

    healthLearn.key = key
    healthLearn.startPercent = UnitHealth("target") or 100
end

local function recordHealthChange()
    if not healthLearn.key or not healthLearn.startPercent then return end
    if not OB.mobHealth then return end

    local percent = UnitHealth("target") or healthLearn.startPercent
    local diff = healthLearn.startPercent - percent

    -- Healing, evade/reset, or a recycled target invalidates the cumulative
    -- sample. Start again from the new percentage rather than poisoning the DB.
    if diff < 0 then
        healthLearn.damage = 0
        healthLearn.startPercent = percent
        return
    end

    if healthLearn.damage <= 0 or diff <= 0 then return end

    local estimate = ceil((healthLearn.damage / diff) * 100)
    if estimate <= 0 then return end

    local record = OB.mobHealth[healthLearn.key]
    if type(record) ~= "table" then
        record = { max = estimate, diff = diff, hits = 1 }
        OB.mobHealth[healthLearn.key] = record
        return
    end

    record.hits = (record.hits or 0) + 1

    -- The widest observed percentage delta is the least rounded measurement,
    -- which is why ShaguPlates keeps it in preference to a later smaller one.
    if not record.diff or diff > record.diff then
        record.max = estimate
        record.diff = diff
    end
end

local healthFrame = CreateFrame("Frame", "EquadisOverhaulNameplateHealth", UIParent)
healthFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
healthFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
healthFrame:RegisterEvent("UNIT_HEALTH")
healthFrame:RegisterEvent("UNIT_COMBAT")
healthFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED" then
        resetHealthLearning()
        return
    end

    if event == "UNIT_COMBAT" and arg1 == "target" and healthLearn.key then
        if arg2 == "HEAL" then
            healthLearn.damage = 0
            healthLearn.startPercent = UnitHealth("target") or healthLearn.startPercent
            return
        end

        local amount = tonumber(arg4)
        if amount and amount > 0 then healthLearn.damage = healthLearn.damage + amount end
        return
    end

    if event == "UNIT_HEALTH" and arg1 == "target" then recordHealthChange() end
end)

function M:EstimatedHealth(name, level, fraction)
    local cfg = self:Config()
    if not OB.mobHealth then return nil end

    local key = mobHealthKey(name, level)
    if not key then return nil end

    local record = OB.mobHealth[key]
    if type(record) ~= "table" then return nil end
    if not record.max or record.max <= 0 then return nil end
    if (record.hits or 0) < cfg.healthEstimateHits then return nil end
    if (record.diff or 0) < cfg.healthEstimateDamage then return nil end

    return ceil(record.max * fraction), record.max, true
end

-- ---------------------------------------------------------------------------
-- finding and adopting client plates
-- ---------------------------------------------------------------------------

function M:IsNamePlate(frame)
    if not frame or not frame.GetObjectType then return false end
    if frame:GetObjectType() ~= PLATE_TYPE then return false end

    local region = frame:GetRegions()
    if not region or not region.GetObjectType or not region.GetTexture then return false end
    if region:GetObjectType() ~= "Texture" then return false end

    return region:GetTexture() == PLATE_BORDER
end

function M:Scan()
    local count = WorldFrame:GetNumChildren()
    if count <= (self.seen or 0) then return 0 end

    local children = { WorldFrame:GetChildren() }
    local found = 0

    for i = (self.seen or 0) + 1, count do
        local frame = children[i]
        if self:IsNamePlate(frame) and not self.plates[frame] then
            self:Adopt(frame)
            found = found + 1
        end
    end

    self.seen = count
    return found
end

--[[ **Written only when the value would actually change.**

     Every plate is refreshed on every rendered frame -- that is the polling
     model this module is a port of, and it is why the addon it came from is the
     one people turn off when their frames drop. Twenty plates at a hundred and
     fifty frames a second is three thousand refreshes, and each one was setting
     the same text and the same colour on regions that already had them.

     `SetText` and `SetStatusBarColor` are not free: they re-measure the string,
     re-resolve the texture and mark the frame for redraw. Handing them what
     they already hold is work with no picture attached.

     **A throttle was tried first and reverted.** Rebuilding a plate ten times a
     second rather than every frame is the obvious fix and it degrades the
     things that have to be instant: the mouseover mark, the threat colour, the
     combo points, a recycled plate following its new mob. Twelve tests said so,
     each naming a behaviour somebody had decided mattered. Skipping redundant
     writes costs those nothing, because the value is identical either way.

     **Safe because these are ECO's own regions.** The overlay's name, level,
     health text and bar are built by this module and written by nothing else,
     so what was last set is what is there. ]]--
local function setText(fs, text)
    if not fs then return end
    if fs.eqEcoLastText == text then return end

    fs.eqEcoLastText = text
    fs:SetText(text)
end

local function setTextColor(fs, r, g, b, a)
    if not fs then return end
    a = a or 1

    if fs.eqEcoR == r and fs.eqEcoG == g and fs.eqEcoB == b and fs.eqEcoA == a then
        return
    end

    fs.eqEcoR, fs.eqEcoG, fs.eqEcoB, fs.eqEcoA = r, g, b, a
    fs:SetTextColor(r, g, b, a)
end

local function setBarColor(bar, r, g, b, a)
    if not bar then return end
    a = a or 1

    if bar.eqEcoR == r and bar.eqEcoG == g and bar.eqEcoB == b and bar.eqEcoA == a then
        return
    end

    bar.eqEcoR, bar.eqEcoG, bar.eqEcoB, bar.eqEcoA = r, g, b, a
    bar:SetStatusBarColor(r, g, b, a)
end

local function setBarValue(bar, value)
    if not bar then return end
    if bar.eqEcoValue == value then return end

    bar.eqEcoValue = value
    bar:SetValue(value)
end

local function silence(object)
    if not object or not object.GetObjectType then return end
    local kind = object:GetObjectType()

    if kind == "Texture" then
        object:SetTexture("")
        object:SetTexCoord(0, 0, 0, 0)
    elseif kind == "FontString" then
        object:SetWidth(0.001)
    elseif kind == "StatusBar" then
        object:SetStatusBarTexture("")
    end
end

-- Octo exposes a real cast StatusBar as the second child of each native
-- nameplate. Keep that frame alive as an exact per-mob data source, but only
-- suppress FontStrings that belong to the cast frame itself. An earlier repair
-- walked arbitrary nameplate regions looking for cast text; on this client that
-- also caught real plate regions and destroyed the established appearance.
local function collectNativeCastTexts(frame, out, seen, depth)
    if not frame or depth > 3 then return end

    local function add(obj)
        --[[ **Type first, then fields.**

             These names are guesses at what a private server might hang on
             a nameplate, and a frame is free to have any of them be
             something other than a region -- `frame.text` is a *function*
             on this client. `if not obj` lets that through, and the next
             line indexes it, which throws rather than skipping.

             The whole suite died here on the first nameplate scan. ]]--
        if type(obj) ~= "table" then return end
        if seen[obj] then return end
        if not obj.GetText or not obj.SetText then return end
        if obj.GetObjectType and obj:GetObjectType() ~= "FontString" then return end
        seen[obj] = true
        table.insert(out, obj)
    end

    -- Common private-server field names, if present.
    add(frame.TextString)
    add(frame.text)
    add(frame.spellText)
    add(frame.spellName)
    add(frame.nameText)

    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, table.getn(regions) do add(regions[i]) end
    end

    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, table.getn(children) do
            collectNativeCastTexts(children[i], out, seen, depth + 1)
        end
    end
end

local function suppressNativeCastVisuals(plate)
    if not plate or not plate.original then return end
    local cast = plate.original.cast

    -- Leave the native StatusBar itself shown/updated so GetValue() and
    -- IsShown() remain useful, but remove only its own texture.
    if cast and cast.SetStatusBarTexture then cast:SetStatusBarTexture("") end

    local texts = plate.original.castTexts or {}
    for i = 1, table.getn(texts) do
        local text = texts[i]
        if text then
            if text.SetAlpha then text:SetAlpha(0) end
            if text.Hide then text:Hide() end
        end
    end
end

local function newBorder(parent, level)
    local border = CreateFrame("Frame", nil, parent)
    border:SetFrameLevel(level)
    border:Hide()
    return border
end

function M:ResetPlateIdentity(plate)
    --[[ The unit token is the identity, more exactly than the name is: it is
         the one thing on a recycled frame that names *this* mob rather than a
         mob with this name. ]]--
    plate.unitToken = nil

    plate.identityName = nil
    plate.identityLevel = nil
    plate.playerVerified = nil
    plate.playerClass = nil
    plate.classification = nil
    plate.creatureType = nil
    plate.guildName = nil
    plate.debuffVerify = nil
    plate.nextAuraScan = 0

    --[[ The cached strings go with the identity, for exactly the reason the
         rest of this function exists: nameplate frames are recycled, so the
         same frame reappears as a different mob with a different name and
         level. A cache that outlived the identity would show the previous
         mob's name until something happened to change it. ]]--
    plate.shortNameSource = nil
    plate.shortNameValue = nil
    plate.levelTextSource = nil
    plate.levelTextSuffix = nil
    plate.levelTextValue = nil
    plate.healthTextValue = nil
    plate.healthTextCur = nil
    plate.healthTextMax = nil
    plate.healthTextPercent = nil
    plate.healthTextMode = nil

    --[[ The guessed debuff list and the verify key go with the identity, for
         the reason the rest of this function exists: the frame is recycled and
         the next mob is a different mob. ]]--
    plate.verifyName = nil
    plate.verifyLevel = nil
    plate.verifyKey = nil
    plate.guessName = nil
    plate.guessAt = nil
    plate.guessed = nil

    if plate.debuffCache then
        for i = 1, 16 do plate.debuffCache[i] = nil end
    end
end

function M:Adopt(frame)
    local plate = {
        frame = frame,
        original = {},
        debuffs = {},
        combo = {},
        debuffCache = {},
    }

    --[==[ **And a drag that starts here turns the camera.**

         A plate takes the mouse so it can be clicked, and 1.12 gives a
         mouse-enabled frame *every* button over it -- so a right-drag begun on
         a plate turned nothing at all. On a pull that is most of the screen.

         Put on at adoption rather than in the styling pass: it is a property of
         the frame rather than of how it looks, and the styling pass runs
         constantly. See `OB.AttachCameraDrag`. ]==]
    OB.AttachCameraDrag(frame)

    local health, cast = frame:GetChildren()
    plate.original.health = health
    plate.original.cast = cast
    silence(health)
    silence(cast)

    -- Exact cast data is useful on Octo, but collection is deliberately scoped
    -- to the cast child. Nothing on the parent nameplate is reclassified or
    -- hidden here, so this cannot change the plate's normal visual layout.
    plate.original.castTexts = {}
    if cast then
        collectNativeCastTexts(cast, plate.original.castTexts, {}, 0)
        suppressNativeCastVisuals(plate)
    end

    local regions = { frame:GetRegions() }
    for i = 1, table.getn(regions) do
        local key = PLATE_REGIONS[i]

        if key == "raidicon" then
            plate.raidicon = regions[i]
        elseif key then
            plate.original[key] = regions[i]
            silence(regions[i])
        else
            silence(regions[i])
        end
    end

    plate.overlay = CreateFrame("Frame", nil, frame)
    plate.overlay:SetFrameLevel(frame:GetFrameLevel() + 2)

    --[[ Scaled here as well as in the refresh, so a plate is the right size on
         the frame it appears rather than on the frame after. A mob walking into
         view and visibly resizing is exactly the kind of thing that reads as
         the addon being unfinished. ]]--
    plate.overlay:SetScale(self:UIScale())

    plate.targetGlow = newBorder(plate.overlay, plate.overlay:GetFrameLevel() + 1)

    --[[ Its own frame rather than a colour on the plate border: the three can be
         true at once -- you can hover a mob you have targeted while it casts --
         and one surface would have to pick a winner. ]]--
    plate.mouseoverGlow = newBorder(plate.overlay, plate.overlay:GetFrameLevel() + 1)

    plate.health = CreateFrame("StatusBar", nil, plate.overlay)
    plate.health:SetFrameLevel(plate.overlay:GetFrameLevel() + 2)

    plate.background = plate.health:CreateTexture(nil, "BACKGROUND")
    plate.background:SetAllPoints(plate.health)

    plate.healthBorder = newBorder(plate.overlay, plate.health:GetFrameLevel() + 1)

    plate.healthTextLayer = CreateFrame("Frame", nil, plate.overlay)
    plate.healthTextLayer:SetFrameLevel(plate.healthBorder:GetFrameLevel() + 1)
    plate.healthTextLayer:SetAllPoints(plate.health)

    plate.name = OB.NewText(plate.overlay, "OVERLAY", "GameFontNormal")
    plate.level = OB.NewText(plate.overlay, "OVERLAY", "GameFontNormalSmall")
    plate.guild = OB.NewText(plate.overlay, "OVERLAY", "GameFontNormalSmall")

    --[==[ **A totem drawn as the totem it is.**

         Twenty-six things that look identical on a nameplate -- a short bar and
         a name in small text -- and knowing which is the tremor totem is worth
         more in that moment than knowing its health. ]==]
    plate.totemIcon = plate.overlay:CreateTexture(nil, "OVERLAY")
    plate.totemIcon:SetTexCoord(0.078, 0.92, 0.079, 0.937)
    plate.totemIcon:Hide()
    plate.text = OB.NewText(plate.healthTextLayer, "OVERLAY", "GameFontHighlight")
    plate.text:SetTextColor(1, 1, 1, 1)

    plate.cast = CreateFrame("StatusBar", nil, plate.overlay)
    plate.cast:SetFrameLevel(plate.health:GetFrameLevel())
    plate.cast:Hide()

    plate.castBackground = plate.cast:CreateTexture(nil, "BACKGROUND")
    plate.castBackground:SetAllPoints(plate.cast)

    plate.castBorder = newBorder(plate.overlay, plate.cast:GetFrameLevel() + 1)

    plate.castTextLayer = CreateFrame("Frame", nil, plate.overlay)
    plate.castTextLayer:SetFrameLevel(plate.castBorder:GetFrameLevel() + 1)
    plate.castTextLayer:SetAllPoints(plate.cast)

    plate.castName = OB.NewText(plate.castTextLayer, "OVERLAY", "GameFontHighlight")
    plate.castName:SetTextColor(1, 1, 1, 1)

    --[==[ **And how long is left of it.**

         The bar says how far along a cast is and cannot say how long that
         leaves: three-quarters along reads the same whether the last quarter is
         a tenth of a second or two, and those are opposite decisions -- interrupt
         now, or step out of it.

         Its own string rather than more text in the name, because the two answer
         different questions and want to be in different places: the name in the
         middle where it is read, the number at the end where it is glanced
         at. ]==]
    plate.castTime = OB.NewText(plate.castTextLayer, "OVERLAY", "GameFontHighlight")
    plate.castTime:SetTextColor(1, 1, 1, 1)

--[==[ **A debuff icon and the seconds left on it.**

         The icon alone answers "is it still on" and not "for how much longer",
         which is the question a plate full of pictures is actually asked. 1.12
         has no call that returns a duration for another unit's aura, so the
         answer comes from `OB.AuraTimeLeft`: when the spell was first seen on
         that name, plus a shipped table of how long each one lasts.

         The text is a sibling of the icon rather than a child, because these
         are textures rather than frames -- a texture has no children. Kept in
         its own list so the positioning pass can move the pair together. ]==]
    plate.debuffTimers = plate.debuffTimers or {}

    for i = 1, 16 do
        local icon = plate.overlay:CreateTexture(nil, "OVERLAY")
        icon:SetTexCoord(0.078, 0.92, 0.079, 0.937)
        icon:Hide()
        plate.debuffs[i] = icon

        local timer = OB.NewText(plate.textLayer or plate.overlay, "OVERLAY",
                "GameFontNormalSmall")
        timer:Hide()
        plate.debuffTimers[i] = timer
    end

    for i = 1, 5 do
        local point = plate.overlay:CreateTexture(nil, "OVERLAY")
        point:SetWidth(6)
        point:SetHeight(6)
        point:Hide()
        plate.combo[i] = point
    end

    if plate.raidicon and plate.raidicon.SetParent then
        plate.raidicon:SetParent(plate.overlay)
    end

    self.plates[frame] = plate
    table.insert(self.order, plate)

    self:ResetPlateIdentity(plate)
    self:Style(plate)
    return plate
end

-- ---------------------------------------------------------------------------
-- shared-look styling
-- ---------------------------------------------------------------------------

--[==[ **A plate border is one pixel, hard against the bar.**

     The shared border styles are sized for windows: `Classic` is fourteen
     pixels of tooltip art, `Blizzard` is thirty-two of dialog frame, and a
     nameplate health bar is eight pixels tall. `OB.BorderEdge` narrows them so
     the corners stop overlapping -- which was the right fix for a border being
     smeared across the bar, and still leaves a soft band four or five pixels
     thick, held that far out by the padding the style carries.

     Tolerable while the border was decoration. Not now that it is the thing
     carrying the threat colour: a wide soft outline reports a colour badly, and
     it grows the plate's footprint in exactly the situation -- a pack of mobs
     -- where the plates are already fighting for room.

     So plates take the client's own tooltip edge -- the art the target ring
     used to be drawn in, which is the part of that ring worth keeping -- and
     take it one pixel outside the bar rather than eight. `OB.BorderEdge`
     narrows it to what fits the bar's short side, which for an eight-pixel bar
     is a thin line rather than a band.

     A flat one-pixel rectangle was tried first and is what the art replaces: it
     was crisp and it was a wireframe, with none of the bevel that makes the
     rest of the interface look like the interface.

     **And it is drawn whatever the shared border style says**, which is the one
     place this stops following the look. That setting ships as `None`, and it
     is a statement about window and bar *decoration*; the plate border is no
     longer decoration. It is the surface the threat colour is reported on, and
     it is what separates one plate from the plate behind it in a pack. Reading
     the shared style here would have left the readout switched off by default
     for everybody, which is a setting answering a question it was never
     asked. ]==]
local PLATE_BORDER_STYLE = 3     -- OB.borders[3], the client's tooltip edge

--[[ One number, clamped where it is read rather than trusted from the profile:
     a slider's range is a statement about the panel, not about the value that
     reaches here. ]]--
function M:BorderThickness()
    local pad = math.floor(tonumber(self:Config().borderThickness) or 2)
    if pad < 1 then pad = 1 end
    if pad > 6 then pad = 6 end
    return pad
end

function M:StyleBorder(border, anchor)
    local pad = self:BorderThickness()

    --[==[ Measured off the anchor plus the padding, because that is the size
         the backdrop is actually drawn at, and the corners have to fit inside
         it. A nameplate health bar is the smallest thing in the addon wearing a
         border. ]==]
    local width = anchor.GetWidth and anchor:GetWidth() or nil
    local height = anchor.GetHeight and anchor:GetHeight() or nil

    if width then width = width + (pad * 2) end
    if height then height = height + (pad * 2) end

    local edge = OB.BorderEdge(PLATE_BORDER_STYLE, width, height)

    if not edge then
        border:SetBackdrop(nil)
        border:Hide()
        return
    end

    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
    border:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
    border:SetBackdrop(edge)

    --[[ At rest here, and re-coloured by state afterwards. Set rather than left
         alone, because these frames are recycled: the next mob in this frame
         would otherwise inherit the last one's colour. ]]--
    local c = self:Config().borderColor
    border:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    border:Show()
end

--[==[ **Both of these were outlines, and neither of them is now.**

     They were the client's tooltip edge drawn a second and a third time, eight
     and five pixels outside the bar. That art puts its line at the outer
     boundary of whatever band it is given, so what came out was a ring with a
     visible gap behind it -- and a targeted plate wore two of them.

     A glow is the other way round: solid against the bar, gone by the outer
     boundary. Anchored `band` pixels out and asked for an edge size of `band`,
     it spans exactly that distance and there is nothing for a gap to open
     behind.

     **Measured from the border rather than from fixed numbers**, so a heavier
     border does not swallow the glow that is supposed to surround it.

     **Below the health bar**, which is where they were already: the frame level
     comes from `Adopt` and puts these under the bar and its border, so a glow
     bleeds out from behind the plate instead of over the top of it. ]==]
local TARGET_GLOW_BAND = 6
local MOUSEOVER_GLOW_BAND = 3

function M:StyleGlows(plate)
    local cfg = self:Config()
    local pad = self:BorderThickness()

    local target = pad + TARGET_GLOW_BAND
    plate.targetGlow:ClearAllPoints()
    plate.targetGlow:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -target, target)
    plate.targetGlow:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT",
            target, -target)
    plate.targetGlow:SetBackdrop(OB.GlowEdge(target))

    --[[ Geometry only. The colour is chosen per refresh by `RefreshGlow`,
         because it now depends on what the mob is doing rather than on a
         setting alone. ]]--

    --[[ Tighter than the target's, so hovering the thing you already have
         targeted reads as two glows rather than as one brighter one. ]]--
    local hover = pad + MOUSEOVER_GLOW_BAND
    plate.mouseoverGlow:ClearAllPoints()
    plate.mouseoverGlow:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -hover, hover)
    plate.mouseoverGlow:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT",
            hover, -hover)
    plate.mouseoverGlow:SetBackdrop(OB.GlowEdge(hover))

    local m = cfg.mouseoverGlowColor
    plate.mouseoverGlow:SetBackdropBorderColor(m[1], m[2], m[3], m[4] or 1)
end

function M:StyleHealthText(plate)
    local cfg = self:Config()
    local pos = cfg.healthTextPos or "CENTER"

    plate.text:ClearAllPoints()
    plate.text:SetJustifyH(pos)

    if pos == "LEFT" then
        plate.text:SetPoint("LEFT", plate.health, "LEFT", 2, 0)
    elseif pos == "RIGHT" then
        plate.text:SetPoint("RIGHT", plate.health, "RIGHT", -2, 0)
    else
        plate.text:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    end
end

function M:PositionDebuffs(plate)
    local cfg = self:Config()
    local size = cfg.debuffSize
    local anchor = plate.name
    local point, relativePoint, y

    if cfg.debuffPosition == "BOTTOM" then
        anchor = plate.cast:IsShown() and plate.cast or plate.health
        point, relativePoint, y = "TOPLEFT", "BOTTOMLEFT", -cfg.debuffOffset
    else
        point, relativePoint, y = "BOTTOMLEFT", "TOPLEFT", cfg.debuffOffset
    end

    for i = 1, 16 do
        local icon = plate.debuffs[i]
        icon:SetWidth(size)
        icon:SetHeight(size)
        icon:ClearAllPoints()
        icon:SetPoint(point, anchor, relativePoint, (i - 1) * (size + 2), y)

        --[==[ **In the middle of the icon, not under it.**

             It sat below, on the reasoning that a number written across a
             fourteen-pixel picture is unreadable. Two things make the middle the
             better place anyway: a row of numbers hanging under a row of icons
             reads as its own line of text with no obvious owner, and a plate is
             short of vertical room in a way it is not short of icons.

             What makes it legible is the outline below rather than the position,
             which is the same answer the cooldown numbers on the action bars
             already use. ]==]
        local timer = plate.debuffTimers and plate.debuffTimers[i]

        if timer then
            timer:ClearAllPoints()
            timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
            timer:SetJustifyH("CENTER")
        end
    end
end

function M:Style(plate)
    local cfg = self:Config()
    local look = OB.Look("nameplates")
    local texture = OB.textures[look.texture] or OB.textures[1]
    local bg = cfg.backgroundColor

    plate.overlay:ClearAllPoints()
    --[[ **The offset is divided by the scale, because `SetPoint` measures it in
         the *moving* frame's coordinate space.**

         The overlay is scaled to the UI scale so it matches the rest of the
         interface, and that makes its own units smaller than the screen's: at a
         UI scale of 0.7 an offset of -10 would move the plate seven pixels, not
         ten. Every plate would sit closer to its mob than the slider says, and
         the slider would feel like it was lying.

         Same rule the buff frames needed and for the same reason. Divide by the
         scale and the number on the page is the number on the screen. ]]--
    local overlayScale = self:UIScale()
    if not overlayScale or overlayScale == 0 then overlayScale = 1 end

    --[[ Set here as well as at adoption, so moving the UI scale slider reaches
         plates that already exist. Without it the scale would be right only for
         plates created after the change, and the two would sit side by side at
         different sizes. `RefreshTargetTreatment` writes it again every frame
         for its own reasons; this is the one that answers a setting. ]]--
    plate.overlay:SetScale(overlayScale)

    plate.overlay:SetPoint("CENTER", plate.frame, "CENTER", 0,
            (cfg.verticalOffset or 0) / overlayScale)
    plate.overlay:SetWidth(cfg.width + 80)
    plate.overlay:SetHeight(cfg.height + cfg.castbarHeight + cfg.debuffSize + 50)

    plate.health:SetWidth(cfg.width)
    plate.health:SetHeight(cfg.height)
    plate.health:ClearAllPoints()
    plate.health:SetPoint("CENTER", plate.overlay, "CENTER", 0, 0)
    plate.health:SetStatusBarTexture(texture)
    plate.health:SetOrientation(cfg.verticalHealth and "VERTICAL" or "HORIZONTAL")
    plate.background:SetTexture(bg[1], bg[2], bg[3], bg[4] or 0.72)

    self:StyleBorder(plate.healthBorder, plate.health)
    self:StyleGlows(plate)

    plate.name:ClearAllPoints()
    plate.name:SetPoint("BOTTOM", plate.health, "TOP", 0, 2)
    OB.ApplyFont(plate.name, cfg.nameSize, "nameplates", cfg.forceOutline)

    plate.level:ClearAllPoints()
    plate.level:SetPoint("RIGHT", plate.health, "LEFT", -3, 0)
    OB.ApplyFont(plate.level, cfg.nameSize, "nameplates", cfg.forceOutline)

    --[==[ **Above the name, which is not where a tooltip puts it.**

         Everything else on this plate is already spoken for. Below the health
         bar is the cast bar's, and a guild name that jumped whenever somebody
         started casting would be worse than one in an odd place. Between the
         name and the bar means reflowing the name every time a plate changes
         from a mob to a player and back.

         So it goes outside, above the name, where nothing can collide with it
         and nothing has to move. The name stays welded to the bar it belongs
         to, which is the pairing that has to stay readable. ]==]
    plate.guild:ClearAllPoints()
    plate.guild:SetPoint("BOTTOM", plate.name, "TOP", 0, 1)
    OB.ApplyFont(plate.guild, cfg.guildNameSize, "nameplates", cfg.forceOutline)

    plate.totemIcon:ClearAllPoints()
    plate.totemIcon:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
    plate.totemIcon:SetWidth(cfg.totemIconSize)
    plate.totemIcon:SetHeight(cfg.totemIconSize)

    OB.ApplyFont(plate.text, cfg.nameSize - 2, "nameplates", cfg.forceOutline)
    self:StyleHealthText(plate)

    plate.cast:ClearAllPoints()
    plate.cast:SetPoint("TOPLEFT", plate.health, "BOTTOMLEFT", 0, -3)
    plate.cast:SetPoint("TOPRIGHT", plate.health, "BOTTOMRIGHT", 0, -3)
    plate.cast:SetHeight(cfg.castbarHeight)
    plate.cast:SetStatusBarTexture(texture)
    plate.castBackground:SetTexture(bg[1], bg[2], bg[3], bg[4] or 0.72)
    self:StyleBorder(plate.castBorder, plate.cast)

    plate.castName:ClearAllPoints()
    plate.castName:SetPoint("CENTER", plate.cast, "CENTER", 0, 0)
    OB.ApplyFont(plate.castName, cfg.nameSize - 1, "nameplates", cfg.forceOutline)

    --[[ At the trailing end, so it never sits on top of the spell name however
         long that name is. Two pixels out from the bar's own edge, which is the
         same inset the health text uses. ]]--
    plate.castTime:ClearAllPoints()
    plate.castTime:SetPoint("RIGHT", plate.cast, "RIGHT", -2, 0)
    OB.ApplyFont(plate.castTime, cfg.nameSize - 1, "nameplates", cfg.forceOutline)

    --[==[ **The debuff timers, outlined whatever the profile says.**

         They are drawn in the middle of the icon they are about, so they are
         over a picture that is whatever colour the spell's art happens to be:
         legible on a dark one, invisible on a bright one. Every other string on
         a plate takes the reader's outline setting; this one is forced, because
         the alternative is a number that disappears on half the debuffs in the
         game.

         Two under the name, which is the size the health text uses -- small
         enough to sit inside a fourteen pixel icon. ]==]
    for i = 1, table.getn(plate.debuffTimers or {}) do
        OB.ApplyFont(plate.debuffTimers[i], cfg.nameSize - 2, "nameplates", true)
    end

    self:PositionDebuffs(plate)

    for i = 1, 5 do
        plate.combo[i]:ClearAllPoints()
        plate.combo[i]:SetPoint("TOPRIGHT", plate.health, "BOTTOMRIGHT",
                -((i - 1) * 8), -2)
    end

    if plate.raidicon then
        plate.raidicon:ClearAllPoints()
        plate.raidicon:SetPoint(cfg.raidIconPosition, plate.health,
                cfg.raidIconPosition, cfg.raidIconX, cfg.raidIconY)
        plate.raidicon:SetWidth(cfg.raidIconSize)
        plate.raidicon:SetHeight(cfg.raidIconSize)
    end

--[==[ **Mouse is taken away, never handed out.**

         This set `EnableMouse(not clickThrough)`, which with the setting off
         means `EnableMouse(true)` -- on every plate, on every refresh, whether
         or not the plate had the mouse to begin with.

         A mouse-enabled frame in 1.12 swallows *every* button over it, not only
         the ones it has a handler for. So forcing it on took right-click-drag
         away from the camera anywhere a plate happened to be, which on a pull is
         most of the screen. That is the same fault the world map had, from the
         same cause.

         What the plate started with is recorded once and put back. Click-through
         still switches the mouse off, because taking it away is this module's
         business; adding it was never asked for. ]==]
    if plate.frame.EnableMouse then
        if plate.frame.mouseWas == nil and plate.frame.IsMouseEnabled then
            plate.frame.mouseWas = plate.frame:IsMouseEnabled() and true or false
        end

        local want = plate.frame.mouseWas
        if want == nil then want = true end
        if cfg.clickThrough then want = false end

        plate.frame:EnableMouse(want)
    end

    -- Size changes, UI-scale changes and overlap settings all meet here.
    self:ApplyPlateCollision(plate)
end

-- ---------------------------------------------------------------------------
-- plate metadata
-- ---------------------------------------------------------------------------

function M:OriginalLevel(plate)
    local original = plate.original.level
    if not original then return nil, "??" end

    local text = original:GetText()
    local numeric = tonumber(text)
    return numeric, text or "??"
end

function M:IsTarget(plate)
    if not UnitExists("target") then return false end
    if not plate.frame.GetAlpha then return false end
    return plate.frame:GetAlpha() == 1
end

--[[ **Whether the cursor is on this plate.**

     There is no "is this frame hovered" to ask on 1.12 -- a nameplate is a
     child of `WorldFrame` and the usual `IsMouseOver` idioms do not apply to
     it. What the client does instead is show the plate's *own* glow region on
     whichever one the cursor is over, and set the `mouseover` unit at the same
     moment.

     Neither half is enough alone. The glow is shown for reasons of the client's
     own besides hovering, and `mouseover` exists whenever the cursor is over
     anything at all -- a mob in the world, a party frame, an item in a bag. The
     pair together is the signal, and it is the same one this module already
     uses to work out which unit a plate belongs to.

     Two plates can never both be hovered, so this needs no tie-break: the
     client shows the glow on one. ]]--
function M:IsMouseover(plate)
    if not plate or not plate.original then return false end
    if type(UnitExists) ~= "function" or not UnitExists("mouseover") then return false end

    local glow = plate.original.glow
    if not glow or not glow.IsShown then return false end

    return glow:IsShown() and true or false
end

function M:ExactUnit(plate, name)
    if plate.istarget and UnitExists("target") and UnitName("target") == name then
        return "target"
    end

    if UnitExists("mouseover") and UnitName("mouseover") == name then
        local glow = plate.original.glow
        if not glow or not glow.IsShown or glow:IsShown() then return "mouseover" end
    end

    return nil
end

function M:RefreshIdentity(plate, name, level, unit)
    if plate.identityName ~= name or plate.identityLevel ~= level then
        self:ResetPlateIdentity(plate)
        plate.identityName = name
        plate.identityLevel = level
    end

    if not unit or not UnitExists(unit) or UnitName(unit) ~= name then return end

    if UnitIsPlayer then
        plate.playerVerified = UnitIsPlayer(unit) and true or false
    end

    if plate.playerVerified then
        local localized, token = UnitClass(unit)
        plate.playerClass = token or OB.ClassToken(localized) or plate.playerClass

        --[==[ **Written down twice, because the two stores answer different
             questions.**

             The session table remembers that this *name* is a player, which is
             what a recycled plate needs and what nothing else records. The
             roster remembers the class, which is what a plate needs after a
             reload -- and the roster is already handed this player's guild four
             lines down, so it was learning half of what was in front of it. ]==]
        self:RememberPlayer(name, plate.playerClass)

        if plate.playerClass and OB.modules.roster
                and OB.modules.roster.Learn then
            OB.modules.roster:Learn(name, plate.playerClass)
        end
    end

    if type(UnitClassification) == "function" then
        local classification = UnitClassification(unit)
        if classification and classification ~= "normal" then
            plate.classification = classification
        elseif classification == "normal" then
            plate.classification = nil
        end
    end

    if type(UnitCreatureType) == "function" then
        plate.creatureType = UnitCreatureType(unit)
    end

    --[==[ **Asked here because here is the only place it can be asked.**

         `GetGuildInfo` wants a unit token and a nameplate does not have one --
         which is why this whole function exists. While the plate is the target
         or under the cursor there is a token, so the answer is taken then and
         kept on the plate, and handed to the roster as well so the next plate
         this player appears on already knows.

         Players only. `GetGuildInfo` on an NPC answers nothing, and asking is
         the sort of thing that stays harmless right up until a server answers
         something surprising. ]==]
    if plate.playerVerified and type(GetGuildInfo) == "function" then
        local guild = GetGuildInfo(unit)

        if guild and guild ~= "" then
            plate.guildName = guild
            if OB.modules.roster and OB.modules.roster.Learn then
                OB.modules.roster:Learn(name, nil, nil, nil, guild)
            end
        end
    end
end

--[==[ **What a real unit confirmed, kept by name rather than by frame.**

     `plate.playerVerified` is thrown away every time a plate is recycled, and a
     plate is recycled whenever it leaves the screen and comes back -- so turning
     the camera away from a hostile player and back again lost the one fact that
     made them colourable. Reported as the plate reverting to its default colour.

     The fact is about the *player*, not about the frame. `UnitIsPlayer` said
     yes about a name; that does not stop being true because a frame was reused.
     So it is remembered here, and a returning plate is coloured without asking
     again.

     Not saved between sessions, and deliberately: it is a claim made from a
     live unit, and the store that is allowed to outlive the session is the
     roster -- which this also writes to, below, so the class survives a
     reload. ]==]
M.verifiedPlayers = {}

function M:RememberPlayer(name, class)
    if not name or name == "" then return false end

    self.verifiedPlayers = self.verifiedPlayers or {}
    self.verifiedPlayers[name] = class or self.verifiedPlayers[name] or true

    return true
end

--[==[ **What is known about this name, and how well.**

     Answers the class where there is one, and whether the knowledge came from a
     confirmed unit or from the roster -- because the second is a setting and the
     first never is. ]==]
function M:KnownPlayer(name)
    if not name or name == "" then return nil end

    local seen = self.verifiedPlayers and self.verifiedPlayers[name]
    if seen then
        return true, (seen ~= true) and seen or nil
    end

    if not self:Config().rosterClasses then return nil end

    local known = OB.roster and OB.roster[name]
    if known and known.class then return true, known.class end

    return nil
end

function M:KindForPlate(plate, base, name)
    if base == "FRIENDLY_PLAYER" then return "FRIENDLY_PLAYER" end

    --[[ A red plate becomes a player plate on proof, and the proof no longer
         has to be this frame's. ]]--
    if base == "ENEMY_NPC" then
        if plate.playerVerified == true then return "ENEMY_PLAYER" end
        if self:KnownPlayer(name) then return "ENEMY_PLAYER" end
    end

    return base
end

--[==[ **Is this a player, to the standard the roster may be trusted at?**

     Blue stock plates are intrinsically players -- the client only paints that
     colour for one. Red plates are not: enemy players and enemy NPCs share a
     colour, so a red plate has to have been targeted or hovered before anything
     keyed on its *name* is believed about it.

     That distinction was written once for class colours and is now also what
     decides whether a guild tag appears, so it is asked in one place. Getting
     it wrong in either direction is the ShaguPlates NPC-name bug: a mob named
     after a player wearing that player's class colour, or their guild. ]==]
function M:PlateIsPlayer(plate, kind, name)
    if kind == "FRIENDLY_PLAYER" then return true end
    if plate.playerVerified then return true end

    --[[ And whatever has been confirmed about this name before, which survives
         the frame being handed to somebody else. ]]--
    if name and self:KnownPlayer(name) then return true end

    return false
end

function M:PlayerClass(plate, name, kind)
    if not self:PlateIsPlayer(plate, kind, name) then return nil end
    if plate.playerClass then return plate.playerClass end

    --[[ Confirmed first, then the roster -- and `KnownPlayer` is where the
         difference between those two is decided, rather than here. ]]--
    local _, class = self:KnownPlayer(name)
    if class then return class end

    local known = OB.roster and OB.roster[name]
    if known and known.class then return known.class end

    return nil
end

function M:ShouldShow(kind)
    local key = SHOWN_BY[kind]
    if not key then return true end
    return self:Config()[key] and true or false
end

function M:PlateColor(plate, kind, name)
    local cfg = self:Config()

    --[==[ **Grey wins, before anything else is asked.**

         Answered first rather than folded into the colour table below, because
         everything below is a preference and this is not: a tapped mob gives
         you nothing, and a setting that painted it like a live one would be a
         setting for being lied to. Class colouring, the reaction colours and
         the threat colouring all sit underneath this. ]==]
    if kind == "TAPPED" then return OB.PLATE_TAPPED_COLOR end

    if (kind == "ENEMY_PLAYER" and cfg.enemyClassColor)
            or (kind == "FRIENDLY_PLAYER" and cfg.friendlyClassColor) then
        local class = self:PlayerClass(plate, name, kind)
        if class then
            local r, g, b = OB.ClassColor(class)
            return { r, g, b, 1 }
        end
    end

    return cfg[COLOR_KEY[kind] or "enemyColor"] or cfg.enemyColor
end

function M:ClassificationSuffix(plate)
    local value = plate.classification
    if value and CLASS_SUFFIX[value] then return CLASS_SUFFIX[value] end

    -- The stock level icon appears only for special NPC classifications and is
    -- never a player marker. When there is no exact token, '+' is the honest
    -- amount of detail rather than guessing rare vs elite.
    if plate.playerVerified ~= true and plate.original.levelicon
            and plate.original.levelicon.IsShown
            and plate.original.levelicon:IsShown() then
        return "+"
    end

    return ""
end

--[==[ **Which totem, by name, in English only.**

     `UnitCreatureType` says *that* something is a totem in whatever language the
     client runs in -- that is why `CreatureIs` compares against the client's own
     `CREATURE_TYPE_TOTEM` global rather than a shipped word. It does not say
     which one, and the icon is the entire point of this feature.

     So the mapping is by name, and a name table is a locale table. This one is
     English, from ShaguPlates, which ships six of them. Shipping six here to
     answer one question for a client this addon is not built for is not the
     trade; an unmatched name simply keeps its health bar, which is what every
     nameplate did before this option existed.

     Non-shamans see these too. Totems are something you stand next to as often
     as something you cast, and picking the tremor totem out of a stack of four
     is a question a warrior asks more urgently than the shaman who dropped
     them. ]==]
local TOTEM_ICONS = {
    ["Disease Cleansing Totem"] = "spell_nature_diseasecleansingtotem",
    ["Earth Elemental Totem"] = "spell_nature_earthelemental_totem",
    ["Earthbind Totem"] = "spell_nature_strengthofearthtotem02",
    ["Fire Elemental Totem"] = "spell_fire_elemental_totem",
    ["Fire Nova Totem"] = "spell_fire_sealoffire",
    ["Fire Resistance Totem"] = "spell_fireresistancetotem_01",
    ["Flametongue Totem"] = "spell_nature_guardianward",
    ["Frost Resistance Totem"] = "spell_frostresistancetotem_01",
    ["Grace of Air Totem"] = "spell_nature_invisibilitytotem",
    ["Grounding Totem"] = "spell_nature_groundingtotem",
    ["Healing Stream Totem"] = "Inv_spear_04",
    ["Magma Totem"] = "spell_fire_selfdestruct",
    ["Mana Spring Totem"] = "spell_nature_manaregentotem",
    ["Mana Tide Totem"] = "spell_frost_summonwaterelemental",
    ["Nature Resistance Totem"] = "spell_nature_natureresistancetotem",
    ["Poison Cleansing Totem"] = "spell_nature_poisoncleansingtotem",
    ["Searing Totem"] = "spell_fire_searingtotem",
    ["Sentry Totem"] = "spell_nature_removecurse",
    ["Stoneclaw Totem"] = "spell_nature_stoneclawtotem",
    ["Stoneskin Totem"] = "spell_nature_stoneskintotem",
    ["Strength of Earth Totem"] = "spell_nature_earthbindtotem",
    ["Totem of Wrath"] = "spell_fire_totemofwrath",
    ["Tremor Totem"] = "spell_nature_tremortotem",
    ["Windfury Totem"] = "spell_nature_windfury",
    ["Windwall Totem"] = "spell_nature_earthbind",
    ["Wrath of Air Totem"] = "spell_nature_slowingtotem",
}

OB.totemIcons = TOTEM_ICONS

--[==[ A plate's name is the totem's name with a rank or an owner sometimes
     wrapped around it, so the match is a substring rather than equality --
     which is also how the reference does it. ]==]
function M:TotemIcon(name)
    if not name or name == "" then return nil end

    local exact = TOTEM_ICONS[name]
    if exact then return "Interface\\Icons\\" .. exact end

    for totem, icon in pairs(TOTEM_ICONS) do
        if string.find(name, totem, 1, true) then
            return "Interface\\Icons\\" .. icon
        end
    end

    return nil
end

function M:CreatureIs(plate, globalName, fallback)
    if not plate.creatureType then return false end
    local expected = getglobal(globalName) or fallback
    return expected and string.lower(plate.creatureType) == string.lower(expected)
end

function M:ShouldHideHealth(plate, kind)
    local cfg = self:Config()
    local key = HIDE_HEALTH_KEY[kind]
    if key and cfg[key] then return true end

    if cfg.hideCritterHealth and self:CreatureIs(plate, "CREATURE_TYPE_CRITTER", "Critter") then
        return true
    end

    if cfg.hideTotemHealth and self:CreatureIs(plate, "CREATURE_TYPE_TOTEM", "Totem") then
        return true
    end

    return false
end

function M:ShortName(name)
    if not name or name == "" then return "" end
    local cfg = self:Config()
    if not cfg.shortenNames then return name end
    if string.len(name) <= cfg.nameMaxLength then return name end

    -- ShaguPlates first abbreviates only the first word, preserving as much of
    -- the readable name as possible. Only if that still overflows do all leading
    -- words collapse to initials.
    local first = string.gsub(name, "^(%S+) ", function(word)
        return string.sub(word, 1, 1) .. ". "
    end)

    if string.len(first) <= cfg.nameMaxLength then return first end

    return string.gsub(name, "([^%s]+) ", function(word)
        return string.sub(word, 1, 1) .. ". "
    end)
end

-- ---------------------------------------------------------------------------
-- target state
-- ---------------------------------------------------------------------------

function M:TargetThreat()
    if not UnitExists("target") or not UnitExists("targettarget") then return nil end
    if UnitCanAssist and UnitCanAssist("player", "target") then return nil end
    return UnitIsUnit("targettarget", "player") and true or false
end

--[==[ **The four states, rather than the two `TargetThreat` can express.**

     `TargetThreat` answers a yes/no question and returns nil for everything
     else, which folds two different situations into one: a mob with no target
     at all, and a mob this does not apply to. Those want different colours --
     "nothing is happening" is worth seeing, and "not applicable" is not.

     Casting wins over all of it. It is the state you act on, and a border that
     told you about threat while the mob was mid-cast would be answering the
     less urgent question.

     **Only your target, and that is a limit of the client rather than a
     choice.** 1.12 has no unit token for an arbitrary nameplate, so there is no
     way to ask what any other plate is looking at. `targettarget` exists for
     exactly one mob. Colouring every plate the way ShaguPlates does needs a
     token per plate, which this client does not provide -- see the note on the
     cast bars, which hit the same wall. ]==]
--[==[ **A unit token for this plate, when the client can give one.**

     Vanilla cannot. There is no token for an arbitrary nameplate, which is why
     everything a plate knows about its unit is inferred from the name written
     on it, and why threat could only ever be answered for your target --
     `targettarget` exists for exactly one mob.

     SuperWoW changes that: a nameplate frame answers `GetName(1)` with its
     unit's GUID, and that GUID *is* a unit token. Every unit function then
     works on it, including `guid .. "target"` -- so "what is this mob attacking"
     becomes a question that can be asked of every plate on screen rather than
     one. It is the same route the addon this module was ported from takes.

     **Gated on the capability first, then verified by resolving one.** Without
     SuperWoW, `GetName(1)` returns the frame's own name -- a string, so a type
     check would pass it -- and `UnitExists` is what actually tells a token from
     a name. The capability comes first only so that a client without it pays
     nothing per plate per frame.

     Cached on the plate and re-checked rather than trusted: these frames are
     recycled, and a GUID that has stopped existing belongs to the previous mob.
     ClassicAPI's `nameplate1..n` tokens are deliberately not used -- they are
     addressed by index, and nothing maps an index onto the frame in hand. ]==]
function M:PlateUnit(plate)
    if not plate or not plate.frame or not plate.frame.GetName then return nil end
    if type(UnitExists) ~= "function" then return nil end
    if not OB.Can("superwow") then return nil end

    local cached = plate.unitToken
    if cached then
        local ok, exists = pcall(UnitExists, cached)
        if ok and exists then return cached end
        plate.unitToken = nil
    end

    local ok, token = pcall(plate.frame.GetName, plate.frame, 1)
    if not ok or type(token) ~= "string" or token == "" then return nil end

    local okExists, exists = pcall(UnitExists, token)
    if not okExists or not exists then return nil end

    plate.unitToken = token
    return token
end

function M:ThreatState(plate)
    --[[ **First, because it is the one state a plate can answer for itself on
         any client.** A cast bar belongs to the plate it is drawn on and needs
         no token at all. Underneath the checks below it was gated on a question
         it does not depend on, and every other plate's cast went uncoloured. ]]--
    if plate and plate.cast and plate.cast.IsShown and plate.cast:IsShown() then
        return "casting"
    end

    local unit = self:PlateUnit(plate)

    if unit then
        --[[ A friendly's target is a healer looking at a tank, not a threat
             relationship, and painting it as one would say the wrong thing
             about half a battleground. ]]--
        if UnitCanAssist and UnitCanAssist("player", unit) then return nil end

        local its = unit .. "target"
        if not UnitExists(its) then return "none" end
        return UnitIsUnit(its, "player") and "me" or "other"
    end

    --[==[ **Without a token, one plate and no more.**

         `targettarget` is the only unit of its kind vanilla exposes, so this
         answers for your target and returns nothing for everything else --
         rather than answering *as though* every plate were the target, which is
         what dropping the check would do. ]==]
    if not plate or not plate.istarget then return nil end
    if not UnitExists("target") then return nil end
    if UnitCanAssist and UnitCanAssist("player", "target") then return nil end

    if not UnitExists("targettarget") then return "none" end

    return UnitIsUnit("targettarget", "player") and "me" or "other"
end

--[[ Whether the player has said they are tanking. One reader, so the string
     is compared in one place. ]]--
function M:TankMode()
    return self:Config().threatMode == "tank"
end

--[==[ **The tank's three states, from the damage dealer's two.**

     `ThreatState` answers "who is it on" from the client alone, and that is
     enough for two of the three: on me is *holding*, on somebody else is
     *lost*. The middle one -- about to lose it -- is a number, and the number is
     the meter's: how close the next person is, as a fraction of me.

     Without a reading the middle state does not exist and the answer is the
     honest two. That is deliberate and it is the same rule the gradient
     follows: orange for "no data" would be a claim, and the wrong one. ]==]
function M:TankThreatState(state)
    if state == "other" then return "lost" end
    if state ~= "me" then return state end

    local ratio = OB.RunnerUpThreatRatio and OB.RunnerUpThreatRatio() or nil
    local at = (tonumber(self:Config().tankLoseAt) or 80) / 100

    if ratio and ratio >= at then return "losing" end
    return "holding"
end

--[[ The colour one state is drawn in, or nothing when the state has none. ]]--
function M:ThreatStateColor(state)
    local cfg = self:Config()

    if self:TankMode() then
        state = self:TankThreatState(state)

        if state == "holding" then return cfg.tankHoldingColor end
        if state == "losing" then return cfg.tankLosingColor end
        if state == "lost" then return cfg.tankLostColor end
    end

    if state == "me" then return cfg.threatColor end
    if state == "other" then return cfg.noThreatColor end
    if state == "none" then return cfg.threatNoneColor end
    if state == "casting" then return cfg.threatCastColor end

    return nil
end

function M:ComboPoints()
    if type(GetComboPoints) ~= "function" then return 0 end
    return GetComboPoints() or 0
end

--[[ **A nameplate is a child of `WorldFrame`, and `WorldFrame` is not scaled by
     the UI scale.**

     Everything else you look at -- unit frames, action bars, this addon's own
     windows -- hangs off `UIParent` and inherits its scale. A plate does not, so
     an overlay left at scale 1 is drawn at a different physical size from the
     rest of the interface: ten-point text on a plate is not ten-point text
     anywhere else, one-pixel borders land between physical pixels, and the
     whole thing reads as slightly soft next to a UI that is crisp.

     That is the difference people mean when they say the plates do not look as
     good. ShaguPlates does `SetScale(UIParent:GetScale())` on every plate it
     creates, and it is the first thing it does.

     Read live rather than cached, because the UI scale is a slider somebody can
     move without reloading. ]]--
function M:UIScale()
    if UIParent and UIParent.GetScale then
        local scale = UIParent:GetScale()
        if scale and scale > 0 then return scale end
    end
    return 1
end

--[[ **Nameplate overlap in the 1.12 client is a collision-box trick.**

     The engine positions the native child of WorldFrame before this module
     draws its replacement artwork. ShaguPlates' vanilla implementation makes
     that native child 1x1 to permit unrestricted overlap, and restores it to
     the visual plate size when overlap is disabled. A 1x1 collision box works,
     but it also lets a dense pack collapse almost completely into one spot.

     ECO keeps the same engine-side technique but makes it proportional. With
     overlap enabled, `overlapAmount` shrinks the core collision footprint by
     that percentage. With it disabled, the collision footprint is slightly
     larger than the visible health/name core so the bars are kept apart.

     Debuffs, cast bars, raid markers and glows deliberately do not enlarge this
     footprint: otherwise a temporary aura row would shove every nearby mob's
     plate around. ]]--
function M:PlateCollisionSize(plate)
    local cfg = self:Config()
    local scale = self:UIScale()

    --[==[ **Your target is taken out of the argument entirely.**

         Which plate the engine moves is not something an addon can choose. What
         it can do is make one plate weigh nothing: at 1x1 there is no overlap to
         resolve involving it, so it is left where its mob is while the rest go
         on sorting themselves out around it.

         Before the size arithmetic rather than after, because none of that
         applies -- this is not a smaller footprint, it is the absence of
         one. ]==]
    if plate and plate.istarget and cfg.targetHoldsPosition then
        return 1, 1
    end
    local width = tonumber(cfg.width) or 120
    local height = (tonumber(cfg.height) or 8) + (tonumber(cfg.nameSize) or 10) + 6

    if cfg.allowOverlap then
        local amount = tonumber(cfg.overlapAmount) or 20
        if amount < 0 then amount = 0 end
        if amount > 90 then amount = 90 end

        local remaining = 1 - (amount / 100)
        width = width * remaining
        height = height * remaining
    else
        -- A little breathing room around the core bar/name when overlap is off.
        width = width + 8
        height = height + 6
    end

    width = math.max(1, width * scale)
    height = math.max(1, height * scale)
    return width, height
end

function M:ApplyPlateCollision(plate)
    if not plate or not plate.frame then return end
    local frame = plate.frame
    if not frame.SetWidth or not frame.SetHeight then return end

    local width, height = self:PlateCollisionSize(plate)
    local currentWidth = frame.GetWidth and frame:GetWidth() or nil
    local currentHeight = frame.GetHeight and frame:GetHeight() or nil

    -- The client may restore the native dimensions when a recycled plate is
    -- shown again, so compare the live frame rather than trusting our cache.
    if not currentWidth or abs(currentWidth - width) > 0.5 then
        frame:SetWidth(width)
    end
    if not currentHeight or abs(currentHeight - height) > 0.5 then
        frame:SetHeight(height)
    end

    plate.collisionWidth = width
    plate.collisionHeight = height
end

function M:RefreshTargetTreatment(plate, target)
    local cfg = self:Config()

    --[[ The target's emphasis multiplies the UI scale rather than replacing it.
         Setting it directly was the same bug twice: the plate lost the UI scale
         *and* the emphasis was measured against the wrong baseline, so a
         `targetScale` of 1.15 was not fifteen percent bigger than its
         neighbours unless the UI scale happened to be exactly 1. ]]--
    local base = self:UIScale()

    -- Do not change strata or frame level here. The overlay was created at the
    -- native plate's level in Adopt(), and its children were layered relative to
    -- that level at the same time. The old LOW/BACKGROUND split prevented plates
    -- from overlapping naturally; mirroring the native strata is not safe either
    -- because Octo can report the sentinel value "UNKNOWN", which 1.12 rejects.
    -- Leaving the established level alone preserves the exact pre-fix visual
    -- stack while allowing the client to decide which overlapping plate is on top.

    if cfg.markTarget then
        if target then
            plate.overlay:SetScale(base * (tonumber(cfg.targetScale) or 1))
            plate.overlay:SetAlpha(1)
        else
            plate.overlay:SetScale(base)
            if UnitExists("target") then
                plate.overlay:SetAlpha(cfg.otherAlpha)
            else
                plate.overlay:SetAlpha(1)
            end
        end
    else
        plate.overlay:SetScale(base)
        plate.overlay:SetAlpha(1)
    end

    --[==[ **The glow is decided after the cast bar, not here.**

         It reports casting among its four states, and the only thing that knows
         whether this plate is casting is the cast bar -- which is refreshed at
         the bottom of `Refresh`, below this. Deciding it here reads a bar from
         the previous frame: the glow would report a cast one frame late and hold
         the casting colour one frame after it ended.

         Exactly the fault the border had, in the code that replaced it. Moving
         the state to a new surface moved the ordering requirement with it. ]==]

    --[[ **The plate under the cursor, which the client marks and then does
         nothing with.**

         There is no "is this plate hovered" to ask. What there is: the client
         shows the plate's own glow region on whichever one the cursor is over,
         and sets the `mouseover` unit at the same moment. Neither alone is
         enough -- the glow is also shown for other reasons, and `mouseover`
         exists whenever the cursor is over anything at all -- so the pair is
         the signal. It is the same trick ShaguPlates uses, and this module
         already relies on it to identify a plate's unit; it simply never drew
         anything with it. ]]--
    --[[ Not around a bar that is not drawn -- see `healthHidden`. A critter's
         plate has no bar, so the glow would be an outline round nothing, and
         hovering one is exactly when this runs. ]]--
    if cfg.mouseoverGlow and not plate.healthHidden and self:IsMouseover(plate) then
        plate.mouseoverGlow:Show()
    else
        plate.mouseoverGlow:Hide()
    end

end

--[==[ **Every plate has the border, and every plate it can be asked of
     answers.**

     The flat "highlight the target's border" switch is gone. It painted one
     colour to say "this is the one you clicked" -- which the target's size and
     the fade on every other plate already say -- and it was competing for the
     only surface that can report threat.

     Which plates can answer is `ThreatState`'s question, not this one's: with a
     unit token every plate can, and without one only your target can. A plate
     with nothing to report is left at rest rather than painted the grey of "no
     target", which would be an answer the client did not give.

     At rest rather than untouched: a recycled frame keeps the last mob's
     colour, and the mob that inherits it is not the one that earned it. ]==]
function M:RefreshBorderColor(plate)
    local cfg = self:Config()
    if not plate.healthBorder:IsShown() then return end

    --[==[ **The state where there is one, and the plain border where there is
         not.**

         Which plates can answer is `ThreatState`'s question rather than this
         one's: with a unit token every plate can, and without one only your
         target can. A plate with nothing to report wears the ordinary border
         rather than the grey of "no target", which would be an answer the
         client never gave. ]==]
    local c

    if cfg.threatBorder then
        local state = self:ThreatState(plate)
        c = state and self:ThreatStateColor(state) or nil
    end

    c = c or cfg.borderColor
    plate.healthBorder:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
end

--[==[ **The glow is on your target and nowhere else.**

     One job: which of these is the one I have selected. It briefly carried the
     four threat states as well, and that was a colour describing the only plate
     whose state you can already read from the rest of the interface -- while
     every other plate, the ones the question is actually about, had nothing.

     One colour, because there is only one thing to say. White by default: it is
     the reading that has to survive a plate of any colour underneath it, and a
     tint would compete with the border's four. ]==]
function M:RefreshGlow(plate, target)
    local cfg = self:Config()

    --[[ `healthHidden` for the same reason the mouseover glow has it: this glow
         is anchored to the health bar, and a bar that is not drawn still
         resolves its anchors. Targeting a critter would put a rectangle of light
         where its bar would have been. ]]--
    if not cfg.targetGlow or not target or plate.healthHidden then
        plate.targetGlow:Hide()
        return false
    end

    local colour = cfg.targetGlowColor
    plate.targetGlow:SetBackdropBorderColor(colour[1], colour[2], colour[3],
            colour[4] or 1)
    plate.targetGlow:Show()

    return true
end

-- ---------------------------------------------------------------------------
-- cast bars
-- ---------------------------------------------------------------------------

function M:NativeCastInfo(plate)
    local cast = plate and plate.original and plate.original.cast
    if not cast or not cast.IsShown or not cast:IsShown() then return nil end

    --[==[ **Shown is not the same as casting.**

         Vanilla hides this child when nothing is being cast, so being on screen
         was taken as proof of a cast. A client that leaves it shown and empty
         breaks that: every plate then reports whatever text the frame happens to
         be carrying, for as long as it carries it.

         A real cast has somewhere to travel. A bar whose range is degenerate --
         no maximum, or a maximum equal to its minimum -- is not measuring
         anything, whatever it is displaying. ]==]
    local low, high = 0, 1
    if cast.GetMinMaxValues then low, high = cast:GetMinMaxValues() end

    low, high = low or 0, high or 0
    if high <= low then return nil end

    suppressNativeCastVisuals(plate)

    local spell
    local texts = plate.original.castTexts or {}
    for i = 1, table.getn(texts) do
        local text = texts[i]
        local value = text and text.GetText and text:GetText()

        if value and value ~= "" then
            local compact = string.gsub(value, "%s", "")
            -- Ignore timer-only strings. A real spell name contains at least
            -- one character outside the numeric/punctuation set.
            if compact ~= "" and not string.find(compact, "^[%d%p]+$") then
                spell = value
                break
            end
        end
    end

    if not spell then return nil end

    --[==[ **A mob's own name is not a spell.**

         The texts are gathered from the cast frame and its children, which is
         the right scope -- but a frame that carries the plate's name somewhere
         inside it would hand that name back as the spell, and it would be
         printed under the plate forever because the name never changes.

         Cheap to rule out and impossible to mistake for anything else: no spell
         is called the same thing as the mob casting it. ]==]
    local who = plate.original.name and plate.original.name:GetText()
    if who and who ~= "" and spell == who then return nil end

    local value = cast.GetValue and cast:GetValue() or low
    local span = high - low
    local fraction = 0
    if span > 0 then fraction = ((value or low) - low) / span end
    if fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end

    return spell, fraction
end

--[==[ **Putting a cast bar away means all three of its pieces.**

     The bar, its border and the spell name. The name is parented to the plate's
     text layer rather than to the bar -- it has to be, or it would be clipped by
     a bar eight pixels tall -- so hiding the bar does not hide it.

     Every path that gave up on drawing a cast hid the first two and left the
     third, so the last spell a mob cast stayed printed under its nameplate for
     as long as the plate lived. That is the reported "spells are always
     appearing even if not casting", and it looked like a cast bar bug when it
     was a font string nobody was switching off. ]==]
function M:HideCast(plate)
    --[[ The measurement goes with the bar: a sample kept across a cast that
         ended would time the next one from the wrong place. ]]--
    plate.castSample = nil

    plate.cast:Hide()
    plate.castBorder:Hide()
    plate.castName:Hide()

    --[[ The fourth piece. The note above is about the spell name outliving the
         bar it belonged to; a number frozen at 0.4 under a plate that is no
         longer casting is the same fault with a smaller font. ]]--
    if plate.castTime then plate.castTime:Hide() end

    return true
end

--[==[ **How many seconds are left, asked of whichever source knows.**

     Two sources, and they know different halves.

     The client's own per-plate cast child -- where a client has one -- names the
     spell exactly, even with three mobs of the same name on screen. What it
     does not reliably give is a duration: its bar may be measured in seconds or
     normalised to a fraction, and those are indistinguishable from outside.

     This addon's own record does have the duration, because it comes from
     `SPELLCAST_START`, which carries one. What it cannot do is tell two mobs of
     the same name apart.

     So the spell comes from the first and the seconds from the second, and the
     seconds are only taken from a record that **agrees about the spell** --
     otherwise a mob would be counting down somebody else's cast, which is worse
     than no number at all. ]==]
--[==[ **And where neither source knows, the bar is timed by watching it.**

     The note above is the whole of the problem: the client's own cast child
     names the spell exactly and will not say how long it runs, and this addon's
     record has the duration and cannot tell two mobs of the same name apart. So
     a cast that comes from the plate's own child gets a bar with no number
     under it, which is the reported "some plates count down and some do not".

     A filling bar carries its own duration in how fast it fills. Two samples of
     the fraction a fifth of a second apart give a rate, and the rate gives the
     rest: a bar 40% along and rising 33% a second has two seconds left.

     Three things this has to get right, and each of them is a way it could lie:

     *A channel runs the other way.* Its bar empties, so a falling fraction is
     not a fault -- what is left is the fraction itself over the rate.

     *A new cast of the same spell looks like a channel for one frame*, because
     the fraction drops from nearly one to nearly nothing. A fall that large is
     a restart, not a channel, and the sample is thrown away rather than
     measured.

     *Nothing is shown until there is something to measure.* One sample is a
     position, not a speed, so the first fifth of a second of every cast has no
     number under it -- which is honest, and is over before it is read. ]==]
local CAST_SAMPLE_GAP = 0.2
local CAST_RESTART_DROP = 0.3

function M:NativeCastSeconds(plate, spell, fraction)
    if not plate or not spell or type(fraction) ~= "number" then return nil end

    local now = GetTime and GetTime() or 0
    local sample = plate.castSample

    --[[ A different spell is a different cast, whatever the bar is doing. ]]--
    if not sample or sample.spell ~= spell then
        plate.castSample = { spell = spell, at = now, fraction = fraction }
        return nil
    end

    --[[ A hair under the gap, because `GetTime` differences do not land on the
         number you asked for: a fifth of a second measured between two clock
         reads is 0.19999999, and a strict comparison there means the sample is
         never old enough on the frame it should be. ]]--
    local dt = now - (sample.at or now)
    if dt < (CAST_SAMPLE_GAP - 0.001) then return sample.left end

    local df = fraction - (sample.fraction or 0)

    --[[ Started again: too far back to be a channel draining. ]]--
    if df < -CAST_RESTART_DROP then
        plate.castSample = { spell = spell, at = now, fraction = fraction }
        return nil
    end

    local left

    if df > 0 then
        local rate = df / dt
        if rate > 0 then left = (1 - fraction) / rate end
    elseif df < 0 then
        --[[ A channel: what is left is what is still on the bar. ]]--
        local rate = -df / dt
        if rate > 0 then left = fraction / rate end
    end

    --[[ A bar that has not moved between two samples says nothing about how
         long it runs, so the last answer stands rather than a new guess. ]]--
    if not left then left = sample.left end

    plate.castSample = { spell = spell, at = now, fraction = fraction, left = left }

    if left and left > 0 and left < 600 then return left end

    return nil
end

function M:CastTimeLeft(plate, spell, who)
    if not spell then return nil end

    local function ask(key)
        if not key then return nil end

        local named, _, _, left = OB.CastInfo(key)
        if named == spell and left then return left end

        return nil
    end

    --[[ The token first, where there is one: a GUID is unambiguous and a name
         is not. Asked one at a time rather than over a list of the two --
         `ipairs` on a table whose first element is nil stops before it reaches
         the second, and a plate with no token is the ordinary case here, not the
         exception. ]]--
    return ask(self:PlateUnit(plate)) or ask(who)
end

--[==[ **Every reason a plate can end up with no cast bar, said out loud.**

     There are six of them and they fail identically on screen: the setting, the
     target-only setting, a plate with no name, a client that gives no cast
     source at all, a name shared by two visible mobs -- which is suppressed
     deliberately -- and simply nothing being cast.

     `RefreshCast` walks those in order and returns early from each, so a plate
     with no bar has taken one of six paths and looking at the screen cannot say
     which. This says which, for every plate on screen at once, because the
     interesting cases are the ones where one mob shows a cast and the mob beside
     it does not. ]==]
function M:DebugCastBars()
    local say = function(text) OB.Raw("  " .. text) end
    OB.Print("nameplate cast bars:", "Nameplates")

    local cfg = self:Config()

    say("module enabled: " .. tostring(OB.ModuleEnabled("nameplates"))
            .. ", castbar: " .. tostring(cfg.castbar)
            .. ", target only: " .. tostring(cfg.castTargetOnly))

    say("spell name: " .. tostring(cfg.showCastName)
            .. ", seconds left: " .. tostring(cfg.castTimer))

    --[[ The library the name path reads. A cast filed under a name is what a
         1.12 combat log can offer; a GUID is what a client extension adds. ]]--
    local known = 0
    for _ in pairs(OB.casting or {}) do known = known + 1 end
    say("casts the library is holding: " .. known)

    --[[ Keyed by the client's frame rather than numbered: the plates come and
         go and the table is a set, not a list. ]]--
    local seen = 0

    for frame, plate in pairs(self.plates or {}) do
        if plate and frame and frame.IsShown and frame:IsShown() then
            seen = seen + 1

            local who = plate.original and plate.original.name
                    and plate.original.name:GetText()

            local native, nativeFraction = self:NativeCastInfo(plate)
            local unit = self:PlateUnit(plate)
            local byUnit = unit and OB.CastInfo(unit) or nil
            local byName = who and OB.CastInfo(who) or nil

            local sharing = who and self.visibleNameCounts
                    and (self.visibleNameCounts[who] or 0) or 0

            say(tostring(who or "(no name)")
                    .. (plate.istarget and " [target]" or ""))

            say("   bar shown: " .. tostring(plate.cast and plate.cast:IsShown())
                    .. ", fill: " .. tostring(plate.cast and plate.cast:GetValue())
                    .. ", name shown: "
                    .. tostring(plate.castName and plate.castName:IsShown()))

            say("   from the plate's own child: " .. tostring(native)
                    .. (nativeFraction and (" at "
                            .. tostring(OB.Round(nativeFraction * 100)) .. "%") or ""))

            say("   from a unit token (" .. tostring(unit or "none") .. "): "
                    .. tostring(byUnit))

            say("   from the name: " .. tostring(byName)
                    .. (sharing > 1 and (" -- SUPPRESSED, " .. sharing
                            .. " plates share this name") or ""))

            local left = self:CastTimeLeft(plate, native or byUnit or byName, who)
            say("   seconds left: " .. tostring(left and OB.Round(left) or "unknown"))
        end
    end

    if seen == 0 then say("no nameplates are on screen") end
end

function M:RefreshCast(plate)
    local cfg = self:Config()

    if not cfg.castbar or (cfg.castTargetOnly and not plate.istarget)
            or not plate.original.name then
        self:HideCast(plate)
        return
    end

    -- Prefer Octo's native per-nameplate cast child when it exposes a spell
    -- label. That source is exact even when three mobs have the same name.
    local spell, fraction = self:NativeCastInfo(plate)
    local who = plate.original.name:GetText()

    --[[ 1.12 combat-log casts have a caster *name* but no GUID/unit token.
         If two visible plates have the same name, there is no truthful way to
         know which physical plate produced the line. The old code looked the
         cast up by name on every plate, so one "Scarlet Myrmidon begins to
         cast..." made every Scarlet Myrmidon show the same cast -- and a second
         same-named caster overwrote the first.

         Suppress ambiguous name-only casts instead of drawing information on
         the wrong unit. Once only one plate with that name remains visible the
         cast can be shown normally. ]]--
    --[==[ **Asked of the unit first, which removes the ambiguity rather than
         working around it.**

         The suppression below is honest and expensive: with three Scarlet
         Myrmidons on screen it hides *every* cast bar, because a name cannot say
         which of them the log line came from. A GUID can. Where the client gives
         one -- the same token the threat colouring resolves -- the cast is filed
         under it and this asks for exactly this mob's cast.

         The name path stays underneath for clients that cannot do that, and the
         suppression stays with it, because on those clients the ambiguity is
         still real. ]==]
    if not spell then
        local unit = self:PlateUnit(plate)
        if unit then spell, fraction = OB.CastInfo(unit) end
    end

    if not spell then
        if who and self.visibleNameCounts and (self.visibleNameCounts[who] or 0) > 1 then
            self:HideCast(plate)
            return
        end

        spell, fraction = OB.CastInfo(who)
    end

    if not spell then
        self:HideCast(plate)
        return
    end

    plate.cast:SetMinMaxValues(0, 1)
    -- Unknown-duration casts are real casts, but treating an unknown fraction as
    -- 100% makes the bar look frozen/full. Leave the fill empty until a duration
    -- is known; the spell name still communicates the important part.
    plate.cast:SetValue(fraction or 0)
    plate.cast:SetStatusBarColor(cfg.castColor[1], cfg.castColor[2],
            cfg.castColor[3], cfg.castColor[4] or 1)

    if cfg.showCastName then
        plate.castName:SetText(spell)
        plate.castName:Show()
    else
        plate.castName:Hide()
    end

    --[==[ **The seconds, where they are known.**

         Nothing rather than nought where they are not -- the same rule the
         debuff timers follow, and for the same reason: a number is read as fact,
         and a cast counting down from a duration nobody knows is a fact that is
         not true. The bar is still there and still filling, which is what the
         unknown case can honestly say. ]==]
    local left = cfg.castTimer and self:CastTimeLeft(plate, spell, who)

    --[[ And where no record knows the duration -- a cast named by the plate's
         own child -- the bar is timed by how fast it is filling. ]]--
    if cfg.castTimer and not left then
        left = self:NativeCastSeconds(plate, spell, fraction)
    end

    local text = left and OB.CastTimeText(left)

    if text then
        plate.castTime:SetText(text)
        plate.castTime:Show()
    else
        plate.castTime:Hide()
    end

    plate.cast:Show()
    self:StyleBorder(plate.castBorder, plate.cast)
end

-- ---------------------------------------------------------------------------
-- debuff cache / filtering
-- ---------------------------------------------------------------------------

local function trim(text)
    if not text then return "" end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

function M:BuildDebuffFilter()
    local cfg = self:Config()
    local signature = (cfg.debuffFilter or "none") .. "\031" .. (cfg.debuffList or "")

    if self.debuffFilterSignature == signature then return end
    self.debuffFilterSignature = signature
    self.debuffFilterMode = cfg.debuffFilter or "none"
    self.debuffFilterSet = {}

    local raw = string.gsub(cfg.debuffList or "", "[#;]", ",") .. ","
    string.gsub(raw, "([^,]*),", function(token)
        token = string.lower(trim(token))
        if token ~= "" then self.debuffFilterSet[token] = true end
        return ""
    end)
end

function M:DebuffAllowed(spell)
    self:BuildDebuffFilter()
    if self.debuffFilterMode == "none" then return true end
    if not spell then return self.debuffFilterMode ~= "whitelist" end

    local listed = self.debuffFilterSet[string.lower(spell)] and true or false
    if self.debuffFilterMode == "whitelist" then return listed end
    if self.debuffFilterMode == "blacklist" then return not listed end
    return true
end

--[==[ **A texture back to the spell wearing it, for when the tooltip will not
     say.**

     The exact scan reads `UnitDebuff` for the icon and a tooltip for the name,
     and on a client where that tooltip answers nothing every entry comes back
     nameless. A nameless entry has no duration and no timer -- and because the
     exact result is authoritative while the plate has a unit token, it replaced
     the *named* entries the combat log had already provided.

     That is the reported shape exactly: a debuff shows its seconds happily until
     you target or mouse over the mob, and loses them the moment you do.

     The icon is still a name if anything already knows the pair. `OB.auraIcons`
     learns one every time a spell is seen with a texture, and the search is
     narrowed to the spells this unit is actually known to be carrying, so two
     spells sharing art cannot be mistaken for one another.

     Nothing is invented: a debuff nobody has ever logged stays nameless and
     shows an icon with no number, which is the honest answer. ]==]
--[[ Moved to `OB.AuraNameByIcon`, beside the store it reads, because the unit
     frames need the same answer and this used nothing from this module. Kept as
     a method because the suite calls it by this name and a call site is part of
     the interface. ]]--
function M:NameByIcon(who, texture)
    return OB.AuraNameByIcon(who, texture)
end

function M:ScanExactDebuffs(plate, unit, verify)
    if not unit or not UnitExists(unit) then return false end
    if not plate.original.name or UnitName(unit) ~= plate.original.name:GetText() then return false end

    local tip = OB.ScanTooltip()
    local fresh = {}

    for i = 1, 16 do
        local texture, stacks = UnitDebuff(unit, i)
        if not texture then break end

        local spell
        if type(tip.SetUnitDebuff) == "function" then
            tip:ClearLines()
            if pcall(tip.SetUnitDebuff, tip, unit, i) then spell = OB.ScanLine(1) end
        end

        if spell == "" then spell = nil end

        --[[ The tooltip said nothing, so ask the icon. See `NameByIcon`. ]]--
        if not spell then spell = self:NameByIcon(UnitName(unit), texture) end

        fresh[i] = {
            spell = spell,
            icon = texture,
            stacks = tonumber(stacks) or 0,
            seen = GetTime(),
        }

        --[[ Noted, not added: this runs every second and `AddAura` stamps the
             time, so adding here restarted the clock on every pass and the
             timer under the icon never moved. See `OB.NoteAura`. ]]--
        if spell then OB.NoteAura(UnitName(unit), spell, texture) end
    end

    plate.debuffCache = fresh
    plate.debuffVerify = verify
    return true
end

function M:CachedDebuffs(plate, verify)
    if plate.debuffVerify ~= verify then return nil end
    local out = {}

    for i = 1, 16 do
        local entry = plate.debuffCache[i]
        if entry then table.insert(out, entry) end
    end

    return out
end

--[[ One table handed back for "no debuffs" rather than a fresh one each time.
     The callers only ever read it, and a new empty table per plate per frame is
     a table per plate per frame. ]]--
local NO_DEBUFFS = {}

--[[ How often the guessed list is rebuilt. The same quarter second the exact
     scan uses, and for the same reason: a debuff that appeared a fifth of a
     second ago is not late, and rebuilding is not free. ]]--
local GUESS_INTERVAL = 0.25

function M:DebuffSource(plate, unit, name, level)
    local cfg = self:Config()
    local now = GetTime()

    --[[ **The verify key was built on every plate on every frame.**

         Two concatenations and a `tostring` per plate per rendered frame, for a
         string that changes only when the plate changes mob. Rebuilt when the
         name or level moves, which is what it is made of. ]]--
    if plate.verifyName ~= name or plate.verifyLevel ~= level then
        plate.verifyName = name
        plate.verifyLevel = level
        plate.verifyKey = (name or "") .. ":" .. tostring(level or "??")
    end

    local verify = plate.verifyKey

    if unit and now >= (plate.nextAuraScan or 0) then
        self:ScanExactDebuffs(plate, unit, verify)
        plate.nextAuraScan = now + GUESS_INTERVAL
    end

    --[[ An exact scan is authoritative even when it found *nothing*, but only
         while this plate still has an exact unit token.

         There were two separate bugs here:

         1. The old `> 0` check threw away an exact empty result and fell through
            to the name-based guess cache, so a target with zero debuffs could
            inherit somebody else's stale aura.
         2. Once a target/mouseover scan *did* find debuffs, that per-plate cache
            was reused forever after the unit token disappeared. With no
            duration data in vanilla `UnitDebuff`, an icon could remain on that
            plate until the frame was recycled.

         While `unit` exists we know exactly which creature this is, so even an
         empty cache wins. Once the token is gone, fall back to the expiring
         name-based tracker instead of pretending the last exact snapshot is
         still current. ]]--
    if unit then
        local cached = self:CachedDebuffs(plate, verify)
        if cached then return cached end
    end

    --[[ A guessed aura is keyed only by unit name. With two visible units of
         the same name, applying a debuff to one cannot be assigned to a plate
         safely. The old path painted the guessed icon onto *all* matching
         plates. Exact target/mouseover scans above still work; only the
         ambiguous name-only fallback is suppressed. ]]--
    if name and self.visibleNameCounts and (self.visibleNameCounts[name] or 0) > 1 then
        plate.guessed = nil
        plate.guessName = nil
        plate.guessAt = nil
        return NO_DEBUFFS
    end

    --[[ **And the guessed list was rebuilt on every frame too.**

         `OB.AuraList` walks everything known about the name, builds a table for
         each one, and sorts the result. Every plate, every frame -- so ten
         nameplates in a dungeon is six hundred of those a second, and on 1.12
         that is not CPU, it is garbage, and it is paid for later as the
         collection pause people call lag.

         The exact scan beside it has been throttled since it was written. This
         had the same shape and none of the throttle. ]]--
    if cfg.guessDebuffs then
        if plate.guessName ~= name or not plate.guessAt or now >= plate.guessAt then
            plate.guessName = name
            plate.guessAt = now + GUESS_INTERVAL
            plate.guessed = OB.AuraList(name, 16)
        end

        return plate.guessed or NO_DEBUFFS
    end

    return NO_DEBUFFS
end

function M:RefreshDebuffs(plate, unit, name, level)
    local cfg = self:Config()
    local drawn = 0

    --[[ The shared empty table rather than a new one: this runs per plate per
         frame and the list is only ever read. ]]--
    local list = NO_DEBUFFS

    if cfg.debuffs then list = self:DebuffSource(plate, unit, name, level) end

    for i = 1, table.getn(list) do
        local entry = list[i]
        if drawn >= cfg.debuffCount then break end

        if entry and entry.icon and self:DebuffAllowed(entry.spell) then
            drawn = drawn + 1
            plate.debuffs[drawn]:SetTexture(entry.icon)
            plate.debuffs[drawn]:Show()

            --[==[ **Keyed by name, which is the only key a plate has.**

                 A nameplate usually has no unit token at all -- that is the
                 whole difficulty of this module -- and `OB.AddAura` records
                 against the unit's *name* for exactly that reason. So the plate
                 can ask the same question the target frame does.

                 **Nothing rather than nought.** A spell missing from the
                 duration table shows no number: a timer reading zero on a
                 debuff that is plainly still ticking is read as fact, and is
                 worse than admitting ignorance. ]==]
            self:DrawDebuffTimer(plate, drawn, name, entry.spell)
        end
    end

    for i = drawn + 1, 16 do
        plate.debuffs[i]:Hide()

        if plate.debuffTimers and plate.debuffTimers[i] then
            plate.debuffTimers[i]:Hide()
        end
    end

    self:PositionDebuffs(plate)
end

function M:DrawDebuffTimer(plate, slot, name, spell)
    local timer = plate.debuffTimers and plate.debuffTimers[slot]
    if not timer then return false end

    local cfg = self:Config()

    if not cfg.debuffTimers or not name or not spell then
        timer:Hide()
        return false
    end

    local left = OB.AuraTimeText and OB.AuraTimeText(name, spell)

    if not left then
        timer:Hide()
        return false
    end

    timer:SetText(left)
    timer:Show()

    return true
end

-- ---------------------------------------------------------------------------
-- health / text formatting
-- ---------------------------------------------------------------------------

function M:HealthValues(plate, name, level, fraction, unit)
    -- If an exact unit actually exposes real values, take them first.
    if unit and UnitExists(unit) then
        local cur = UnitHealth(unit) or 0
        local max = UnitHealthMax(unit) or 0
        if max > 100 then return cur, max, true end
    end

    -- Compatibility with MobHealth3 if somebody already runs it.
    if plate.istarget and (MobHealth3 or MobHealthFrame)
            and type(MobHealth_GetTargetCurHP) == "function"
            and type(MobHealth_GetTargetMaxHP) == "function" then
        local cur = MobHealth_GetTargetCurHP()
        local max = MobHealth_GetTargetMaxHP()
        if cur and max and max > 0 then return cur, max, true end
    end

    return self:EstimatedHealth(name, level, fraction)
end

function M:FormatHealth(plate, name, level, fraction, unit)
    local cfg = self:Config()
    if cfg.healthText == "none" then return "" end

    local cur, max, known = self:HealthValues(plate, name, level, fraction, unit)
    local percent = floor(fraction * 100 + 0.5)

    --[[ **Built only when the answer would be different.**

         Nameplates have no events -- everything here is discovered by polling,
         so this runs for every visible plate on every rendered frame. Every
         path below makes a new string, and a string that is identical to the
         one already on screen is pure garbage: at ten plates and sixty frames
         it was six hundred throwaway strings a second from this function alone,
         which is most of why `EquadisClassicOverhaulHUD:OnUpdate` was the worst
         thing in the game's own profiler.

         The inputs are compared one field at a time rather than joined into a
         key, because joining them would allocate the string this is trying to
         avoid. The displayed value only changes when one of these four does. ]]--
    if plate.healthTextValue ~= nil
            and plate.healthTextCur == cur
            and plate.healthTextMax == max
            and plate.healthTextPercent == percent
            and plate.healthTextMode == cfg.healthText then
        return plate.healthTextValue
    end

    plate.healthTextCur = cur
    plate.healthTextMax = max
    plate.healthTextPercent = percent
    plate.healthTextMode = cfg.healthText

    local text
    if not known or not cur or not max or max <= 0 then
        -- Never invent current/max values. A mode which asks for something we do
        -- not know degrades to the one value the stock plate actually supplies.
        text = percent .. "%"
    elseif cfg.healthText == "deficit" then
        text = "-" .. (max - cur)
    else
        text = OB.FormatValue(cur, max, cfg.healthText)
    end

    plate.healthTextValue = text
    return text
end

-- ---------------------------------------------------------------------------
-- one complete plate refresh
-- ---------------------------------------------------------------------------

function M:RefreshNameColor(plate, kind, name)
    local cfg = self:Config()

    if kind == "FRIENDLY_PLAYER" and cfg.friendlyNameClassColor then
        local class = self:PlayerClass(plate, name, kind)
        if class then
            local r, g, b = OB.ClassColor(class)
            setTextColor(plate.name, r, g, b, 1)
            return
        end
    end

    if cfg.nameInCombatColor and plate.original.name
            and plate.original.name.GetTextColor then
        local r, g, b = plate.original.name:GetTextColor()
        if r > 0.9 and g < 0.2 and b < 0.2 then
            setTextColor(plate.name, 1, 0.4, 0.2, 1)
            return
        end
    end

    setTextColor(plate.name, 1, 1, 1, 1)
end

function M:RefreshLevelColor(plate)
    if plate.original.level and plate.original.level.GetTextColor then
        local r, g, b = plate.original.level:GetTextColor()
        plate.level:SetTextColor(math.min(1, r + 0.3),
                math.min(1, g + 0.3), math.min(1, b + 0.3), 1)
    else
        setTextColor(plate.level, 1, 1, 1, 1)
    end
end

function M:Refresh(plate)
    local original = plate.original
    if not original.health then return end

    local cfg = self:Config()

    --[==[ **Asked before the footprint is set, not after.**

         The footprint now depends on whether this is your target, and this runs
         at the top of the refresh while the answer used to be worked out
         two-thirds of the way down. Read a frame late, a plate would hold its
         position for one frame after you stopped targeting it and be shoved for
         one frame after you started -- which is exactly the flicker the setting
         exists to remove. Same shape as the border reading a cast bar that had
         not been refreshed yet. ]==]
    plate.istarget = self:IsTarget(plate)

    -- Vanilla can restore a recycled nameplate's native dimensions on show.
    -- Maintaining the collision footprint here keeps the setting authoritative
    -- without changing the visual overlay itself.
    self:ApplyPlateCollision(plate)

    local value = original.health:GetValue() or 0
    local low, high = original.health:GetMinMaxValues()
    low, high = low or 0, high or 1

    local span = high - low
    if span <= 0 then span = 1 end

    local fraction = (value - low) / span
    if fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end

    local name = original.name and original.name:GetText() or ""
    local level, levelText = self:OriginalLevel(plate)

    local unit = self:ExactUnit(plate, name)
    self:RefreshIdentity(plate, name, level, unit)

    local base
    if original.health.GetStatusBarColor then
        base = OB.PlateKind(original.health:GetStatusBarColor())
    end
    base = base or "ENEMY_NPC"

    local kind = self:KindForPlate(plate, base, name)
    plate.kind = kind

    -- An exact hostile player is valuable roster data. Queue its class lookup if
    -- it is not known already, but verification still came from UnitIsPlayer.
    if (kind == "ENEMY_PLAYER" or kind == "FRIENDLY_PLAYER") and OB.WantPlayer then
        OB.WantPlayer(name)
    end

    if not self:ShouldShow(kind) then
        plate.overlay:Hide()
        return
    end
    plate.overlay:Show()

    plate.health:SetMinMaxValues(0, 1)
    setBarValue(plate.health, fraction)

    local color = self:PlateColor(plate, kind, name)

--[[ Not on a tapped mob. Threat colouring repaints whatever PlateColor
         decided, so without this the grey survived right up until the tapped
         mob became your target -- which is the moment somebody is most likely
         to be reading it. ]]--
    if plate.istarget and cfg.colorByThreat and kind ~= "TAPPED" then
        --[==[ **The ramp first, and the two colours behind it.**

             The gradient needs a threat *reading*, and there is not always one:
             solo, out of combat, or with the meter off there is nothing on the
             addon channel to read. Falling through to the binary colours is the
             right answer there -- "does it have me" is answerable from the
             client alone, and it is what this drew before the ramp existed.

             Green for "no data" would be the other option and it is a claim
             rather than an absence. ]==]
        --[==[ **The bar answers to the mode as the border does.** In tank mode
             the gradient is set aside: it is the damage dealer's ramp -- how
             close am *I* to pulling -- and a tank painted by it would go red at
             exactly the moment they are doing their job. The three tank colours
             carry the middle state instead, from the same numbers. ]==]
        local ramp = (not self:TankMode()) and cfg.threatGradient
                and OB.MyThreatColor() or nil

        if ramp then
            color = ramp
        else
            local onMe = self:TargetThreat()
            local state = nil

            if onMe == true then state = "me"
            elseif onMe == false then state = "other" end

            local c = state and self:ThreatStateColor(state) or nil
            if c then color = c end
        end
    end
    setBarColor(plate.health, color[1], color[2], color[3], color[4] or 1)

    --[==[ **A totem replaced by its icon, when it is one and we know which.**

         Two conditions, not one. `totemIcons` being on is not enough: an
         unrecognised totem name yields no icon, and hiding the health bar in
         favour of a texture that was never set would leave an empty plate.
         Whatever this is, it keeps its bar until there is something better to
         show in its place. ]==]
    local totemIcon

    if cfg.totemIcons
            and self:CreatureIs(plate, "CREATURE_TYPE_TOTEM", "Totem") then
        totemIcon = self:TotemIcon(name)
    end

    if totemIcon then
        plate.totemIcon:SetTexture(totemIcon)
        plate.totemIcon:Show()
    else
        plate.totemIcon:Hide()
    end

    local hideHealth = totemIcon or self:ShouldHideHealth(plate, kind)

    --[==[ **Written down, because two other passes need the answer and both got
         it wrong by not asking.**

         Both glows are anchored to `plate.health`. A hidden frame still resolves
         its anchors, so a glow drawn round a bar that is not there is a
         rectangle of light round nothing -- which is precisely the fault the
         option list's own note describes: *taking the bar away left the target
         glow behind, so the answer to "hide the health bar" was a plate with no
         bar and a glow where the bar had been*.

         That note was written when the five redundant switches were removed, and
         the switches were the only thing fixed. Neither glow ever asked. Then a
         **mouseover** glow was added later with the same omission, which is the
         reported one: hover a critter and the plate reads as vanishing, leaving
         a glowing outline around the empty space its bar would have occupied.

         Recorded on the plate rather than recomputed, because `ShouldHideHealth`
         reads the creature type and three settings and both readers run every
         frame on every plate on screen. ]==]
    plate.healthHidden = hideHealth and true or false

    if hideHealth then
        plate.health:Hide()
        plate.healthBorder:Hide()
        plate.text:Hide()
    else
        plate.health:Show()
        self:StyleBorder(plate.healthBorder, plate.health)
    end

    self:RefreshTargetTreatment(plate, plate.istarget)

    --[[ **Shortened once per name, not once per frame.**

         `ShortName` returns the name untouched when it is short enough, but a
         name that does need abbreviating builds two closures and two strings --
         every frame, for as long as the plate is on screen. A mob's name does
         not change while you look at it. ]]--
    if cfg.showName and original.name and not totemIcon then
        if plate.shortNameSource ~= name
                or plate.shortNameLimit ~= cfg.nameMaxLength
                or plate.shortNameOn ~= cfg.shortenNames then
            plate.shortNameSource = name
            plate.shortNameLimit = cfg.nameMaxLength
            plate.shortNameOn = cfg.shortenNames
            plate.shortNameValue = self:ShortName(name)
        end

        setText(plate.name, plate.shortNameValue)
        self:RefreshNameColor(plate, kind, name)
        plate.name:Show()
    else
        plate.name:Hide()
    end

    --[[ Same again for the level, which was a concatenation every frame for a
         number that changes when the plate changes mob and at no other time. ]]--
    --[==[ **The guild, from the plate first and the roster second.**

         The plate's own answer came from having had this exact unit targeted,
         so it is about this player. The roster's came from a guild roster or a
         `/who`, which is about a name -- and names are not unique across
         realms. The nearer answer wins; the further one is what makes the tag
         appear on somebody you have never targeted, which is the case worth
         having. ]==]
    local guild

    if cfg.showGuildName and not totemIcon then
        guild = plate.guildName

        if not guild and OB.roster and OB.roster[name]
                and self:PlateIsPlayer(plate, kind, name) then
            guild = OB.roster[name].guild
        end
    end

    if guild then
        setText(plate.guild, guild)

        --[==[ Green for your own, which is the one distinction anybody actually
             makes at a glance: everyone else's guild is a name to read, yours
             is a fact to notice. ]==]
        if GetGuildInfo and guild == GetGuildInfo("player") then
            plate.guild:SetTextColor(0.2, 0.9, 0.2, 1)
        else
            plate.guild:SetTextColor(0.8, 0.8, 0.8, 1)
        end

        plate.guild:Show()
    else
        plate.guild:Hide()
    end

    if cfg.showLevel and original.level and not totemIcon then
        local suffix = self:ClassificationSuffix(plate)

        if plate.levelTextSource ~= levelText or plate.levelTextSuffix ~= suffix then
            plate.levelTextSource = levelText
            plate.levelTextSuffix = suffix
            plate.levelTextValue = (levelText or "??") .. suffix
        end

        setText(plate.level, plate.levelTextValue)
        self:RefreshLevelColor(plate)
        plate.level:Show()
    else
        plate.level:Hide()
    end

    if not hideHealth and cfg.healthText ~= "none" then
        setText(plate.text, self:FormatHealth(plate, name, level, fraction, unit))
        plate.text:Show()
    else
        plate.text:Hide()
    end

    --[==[ **After the cast bar, not with the rest of the target treatment.**

         One of the four states the border reports is "this plate is casting",
         and the only thing that knows is the cast bar -- which is refreshed
         here, at the bottom. Coloured up with the glow and the scaling it read
         a bar that had not been updated yet, so the border reported the cast a
         frame late and then held the casting colour for a frame after the cast
         had ended. Invisible at sixty frames a second and wrong at any of
         them. ]==]
    self:RefreshCast(plate)
    self:RefreshBorderColor(plate)
    self:RefreshGlow(plate, plate.istarget)
    self:RefreshDebuffs(plate, unit, name, level)

    local points = 0
    if plate.istarget and cfg.showCombo then points = self:ComboPoints() end
    for i = 1, 5 do
        if i <= points then
            plate.combo[i]:SetTexture(cfg.comboColor[1], cfg.comboColor[2],
                    cfg.comboColor[3], cfg.comboColor[4] or 1)
            plate.combo[i]:Show()
        else
            plate.combo[i]:Hide()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Blizzard plate visibility switches
-- ---------------------------------------------------------------------------

function M:ApplyGameVisibility()
    local cfg = self:Config()

    if type(ShowNameplates) == "function" and type(HideNameplates) == "function" then
        if cfg.enemyNpc or cfg.neutralNpc or cfg.enemyPlayer then
            ShowNameplates()
        else
            HideNameplates()
        end
    end

    if type(ShowFriendNameplates) == "function" and type(HideFriendNameplates) == "function" then
        if cfg.friendlyNpc or cfg.friendlyPlayer then
            ShowFriendNameplates()
        else
            HideFriendNameplates()
        end
    end
end

-- ---------------------------------------------------------------------------
-- binding / update
-- ---------------------------------------------------------------------------

function M:OnUpdate(now)
    if not OB.ModuleEnabled("nameplates") then return end

    self:Scan()

    --[[ Count visible plate names once per update before drawing anything.

         Cast and guessed-aura combat-log data in vanilla are keyed by name,
         because the log provides no GUID. A name is only a unique plate key
         while exactly one visible plate has it. Keeping the multiplicity map
         here lets the render paths refuse ambiguous data rather than cloning a
         spell/debuff onto every same-named mob. ]]--
    self.visibleNameCounts = self.visibleNameCounts or {}
    for key in pairs(self.visibleNameCounts) do self.visibleNameCounts[key] = nil end

    for i = 1, table.getn(self.order) do
        local plate = self.order[i]
        if plate.frame:IsVisible() and plate.original and plate.original.name then
            local name = plate.original.name:GetText()
            if name and name ~= "" then
                self.visibleNameCounts[name] = (self.visibleNameCounts[name] or 0) + 1
            end
        end
    end

    for i = 1, table.getn(self.order) do
        local plate = self.order[i]
        local visible = plate.frame:IsVisible()

        if visible then
            -- Nameplate frames are recycled. A hide->show transition can be a
            -- different mob with the same name and level, so no per-plate aura
            -- or identity cache survives it. This is the latest ShaguPlates
            -- stale-debuff-cache fix, adapted to the Overhaul's polling model.
            if not plate.wasVisible then self:ResetPlateIdentity(plate) end
            plate.wasVisible = true
            self:Refresh(plate)
        else
            plate.wasVisible = false
            plate.overlay:Hide()
        end
    end
end

function M:OnBind()
    self.plates = self.plates or {}
    self.order = self.order or {}
    self.seen = 0
    self.debuffFilterSignature = nil
    self:ApplyGameVisibility()
end

function M:OnStyle()
    if not self.order then return end

    self.debuffFilterSignature = nil
    self:ApplyGameVisibility()

    for i = 1, table.getn(self.order) do self:Style(self.order[i]) end
end

function M:OnDraw() end
