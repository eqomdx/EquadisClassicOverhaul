--[[ Equadis' Classic Overhaul :: unit frames

  Ported from Equadis' UnitFrames, which is UnitFramesImproved_Vanilla by Ko0zi
  (Richard Bertilsson), which is UnitFramesImproved for Legion by Althalla (Kim
  Forsberg). MIT -- see NOTICE.

  **These are Blizzard's frames, restyled.** Not replacements. That is the whole
  design of the addon this comes from and it is the right one for 1.12: the
  player, target, target-of-target and pet frames already exist, already know
  which unit they are showing, already update on the right events, and already
  handle every case a replacement would have to rediscover -- ghosts, tapped
  mobs, the pet happiness meter, the rested indicator.

  What they do badly is *look* like 2004 and refuse to say how much health
  anybody has. Both of those are texture and font work on frames that are
  already correct.

  **The settings are reworked rather than transcribed**, which is the part that
  needed doing. The original had five pages of its own -- General, Colors, Text,
  Position, Bars -- built with its own panel code, plus four settings hidden in
  CVars because that was the only way to make them per-character. Here they are
  sections of one tab in the same generator that builds every other page, and
  the four CVars become ordinary profile keys like everything else.

  Everything the original does is here, including the four pieces it bundles
  from elsewhere: the mob health estimate, the feigning-hunter health, the
  retarget helper and the compact target frame. Two of the five it also bundled --
  the energy ticker and the druid mana estimate -- were already modules of this
  addon, ported from their own sources.

  **UFI is the behavioural baseline.** This module deliberately keeps ECO's profile,
  media and options shell, but the frame geometry, Feign Death handling, retarget
  state machine and MobHealth estimator follow UnitFramesImproved_Vanilla again.

  UFI's custom frame artwork is used automatically when the original addon folder
  is still installed (it may remain disabled). If those binary assets are not
  present, the module falls back to Blizzard's own targeting-frame art while
  keeping the same geometry and behaviour. This makes the repair usable before
  the artwork is physically copied into ECO and, importantly, never leaves a
  missing-texture rectangle on screen.

  **What took the longest to get right was not a setting but who owns the
  strings.** See "taking over the client's own text and colour" below: Blizzard
  writes into these font strings on its own schedule and hides them by default,
  so a port that sets them from an event handler has every text and colour
  setting on the page silently doing nothing. Both client functions are replaced,
  which is what the original does and the only thing 1.12 allows.
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "UnitFrames") end

-- ---------------------------------------------------------------------------
-- the frames, and what each of them is made of
-- ---------------------------------------------------------------------------

--[[ **Blizzard's own names for the pieces**, which are not consistent and cannot
     be derived.

     `PlayerFrameHealthBar` and `TargetFrameHealthBar` follow a pattern;
     `PetFrameHealthBar` follows it too but the pet's *text* is
     `PetFrameHealthBarText` while the player's is `PlayerFrameHealthBarText` --
     which looks the same until you notice target-of-target has no text at all
     and no mana bar worth the name.

     Written out rather than built from a prefix, because the exceptions are the
     whole difficulty and a loop that generated the regular cases would leave
     them to be discovered one bug report at a time.

     **`art` is written out for the same reason, and it was got wrong.**

     The border texture was previously found by sticking `Texture` and then
     `TextureFrameTexture` on the end of the frame's name. Both of those are
     *WotLK* spellings -- 3.x wrapped the target frame in a `TextureFrame` and
     the names changed with it. On 1.12 the globals are `TargetFrameTexture` and
     `TargetofTargetTexture`, so the guess found nothing for either frame, and
     the target name string `TargetFrameTextureFrameName` does not exist at all
     -- the 1.12 name is plain `TargetName`.

     None of that errors. `getglobal` on a name nobody defined returns nil, the
     code checks for nil and moves on, and the result is a Unit Frames page
     whose font and border settings change no pixels on the two frames people
     look at most. Checked against the addons that do this on a live 1.12
     client -- the standalone, DragonflightUI and ShaguTweaks all reach for
     `TargetFrameTexture` and `TargetName`, and not one of them has ever
     mentioned a `TextureFrame`. ]]--
local FRAMES = {
    {
        id = "player",
        setting = "replacePlayer",
        frame = "PlayerFrame",
        health = "PlayerFrameHealthBar",
        power = "PlayerFrameManaBar",
        name = "PlayerName",
        art = "PlayerFrameTexture",
        portrait = "PlayerPortrait",
        unit = "player",
    },
    {
        id = "target",
        setting = "replaceTarget",
        frame = "TargetFrame",
        health = "TargetFrameHealthBar",
        power = "TargetFrameManaBar",
        name = "TargetName",
        art = "TargetFrameTexture",
        portrait = "TargetPortrait",
        unit = "target",
    },
    {
        id = "targettarget",
        setting = "replaceTargetTarget",
        frame = "TargetofTargetFrame",
        health = "TargetofTargetHealthBar",
        power = "TargetofTargetManaBar",
        name = "TargetofTargetName",
        -- Not `TargetofTargetFrameTexture`. The frame is `TargetofTargetFrame`
        -- and its texture drops the `Frame`, which is exactly the kind of
        -- exception a generated name gets wrong.
        art = "TargetofTargetTexture",
        portrait = "TargetofTargetPortrait",
        unit = "targettarget",
    },
    {
        id = "pet",
        setting = "replacePet",
        frame = "PetFrame",
        health = "PetFrameHealthBar",
        power = "PetFrameManaBar",
        name = "PetName",
        art = "PetFrameTexture",
        portrait = "PetPortrait",
        unit = "pet",
    },
}

--[[ **Class portraits, from the client's own art.**

     The addon this comes from ships a copy of `UI-CLASSES-CIRCLES`, which is
     Blizzard's file. It is already installed -- it is in the client -- so the
     copy is not ported and the client's path is used instead. Nothing to
     relicense, nothing to keep in step with a patch.

     The coordinates are the TBC atlas layout, four across and three down, which
     is what the original carries and what the file contains. ]]--
--[[ **The art lives in whichever fork of UFI is on disk, not in one fixed
     folder.**

     This module is a port of UnitFramesImproved, and the port kept pointing at
     `UnitFramesImproved_Vanilla`. That is only one of the names the same asset
     tree ships under: `EquadisUnitFrames` is the fork this project is merging
     in, and it carries a byte-identical `Textures\`, `skin\texture\` and
     `UI-CLASSES-CIRCLES`. Somebody running the fork -- as this install does --
     had the folder probe fail, `legacyAssetsInstalled()` return false, and
     every custom frame texture, the status glow and the whole target aura
     skin silently fall back to stock Blizzard art. Nothing errored; the module
     just looked like it was doing nothing.

     Probed in order and cached, because `GetAddOnInfo` is a scan and this is
     asked once per styled texture. Note the addon supplying the art does not
     need to be *enabled* -- textures load from disk by path -- so this keeps
     working after the superseded addon is switched off, which is exactly what
     `ConflictingAddOns` asks the user to do. ]]--
local FEIGN_TEXTURE = "Interface\\Icons\\Ability_Rogue_FeignDeath"
local PVP_TIMER_FONT = "Fonts\\FRIZQT__.TTF"
--[[ Ten. Six was the first pass and was never looked at in game, eight was
     still small against the frame art beside it. ]]--
local PVP_TIMER_SIZE = 10
local PVP_TIMER_R, PVP_TIMER_G, PVP_TIMER_B = 1, 0.82, 0
--[[ **The square atlas, kept only as a note.**

     `UI-CharacterCreate-Classes` is what class portraits used to be cut
     from, and its corners are why they leaked outside the round portrait
     opening. The circular atlas this addon bundles replaced it -- see
     `CIRCLE_PORTRAIT_ART`. The constant is gone so nothing reaches for it
     again by accident. ]]--

-- Exact coordinates carried by UFI's copy of the TBC class-circle atlas. The
-- 0.496/0.742 values avoid sampling the neighbouring icon's edge.
local LEGACY_PORTRAITS = {
    HUNTER  = { 0,          0.25,       0.25, 0.5  },
    WARRIOR = { 0,          0.25,       0,    0.25 },
    ROGUE   = { 0.49609375, 0.7421875,  0,    0.25 },
    MAGE    = { 0.25,       0.49609375, 0,    0.25 },
    PRIEST  = { 0.49609375, 0.7421875,  0.25, 0.5  },
    WARLOCK = { 0.7421875,  0.98828125, 0.25, 0.5  },
    DRUID   = { 0.7421875,  0.98828125, 0,    0.25 },
    SHAMAN  = { 0.25,       0.49609375, 0.25, 0.5  },
    PALADIN = { 0,          0.25,       0.5,  0.75 },
}

-- Fallback atlas in the stock client. It has clean quarter boundaries rather
-- than UFI's copied texture's padded edges.

--[[ `false` rather than `nil` once a scan has come up empty, so a miss is
     cached too. `nil` would mean "not asked yet" and re-scan the whole addon
     list on every texture of every styled frame. ]]--
local legacyRootCache = nil

--[[ **This addon's own copy of the frame art, so nothing else need be installed.**

     The art used to be read out of the neighbour's folder, which meant the
     frames changed the moment somebody uninstalled it -- and they did, and they
     did. This addon is meant to work as though it were the only one installed,
     so what it needs lives inside it.

     The files are the neighbour's, bundled under its MIT licence with the
     copyright notice kept beside them in `textures/unitframes/`. The old
     folders are still looked at *second*, so an install that has one of them
     and an older copy of this addon keeps working while it updates.

     Bar textures are deliberately not copied: this addon already ships its own
     ElvUI, Gradient, ShaguPlates, Striped, TukUI and Smooth, and a second set
     under different names would be two answers to one question. ]]--
local OWN_ART_ROOT = "Interface\\AddOns\\EquadisClassicOverhaul\\textures\\"

local function legacyRoot()
    if legacyRootCache ~= nil then
        if legacyRootCache == false then return nil end
        return legacyRootCache
    end

    --[[ Ours first, and unconditionally: the files ship with this addon, so
         there is nothing to detect. `GetAddOnInfo` cannot answer for a folder
         inside our own directory anyway. ]]--
    legacyRootCache = OWN_ART_ROOT
    return legacyRootCache
end

local function legacyAssetsInstalled()
    return legacyRoot() and true or false
end


-- ---------------------------------------------------------------------------
-- module
-- ---------------------------------------------------------------------------

--[[ **The original's five formats plus one.**

     It offers value/max, value, percent, value (percent) and none. The sixth --
     value/max (percent) -- is this addon's, and is here because the HUD and the
     meters already offer it and a unit frame that could not would be the odd one
     out. Everything the original has is present and means the same thing. ]]--
OB.unitTextModes = { "None", "Current", "Percent", "Current / Max",
                     "Current (Percent)", "Current / Max (Percent)" }

--[[ The shared list, so a mode chosen on one page means the same on the
     other. See OB.unitTextKeys. ]]--
local TEXT_KEYS = OB.unitTextKeys

local M = OB.RegisterModule({
    id = "unitframes",
    --[[ One word, deliberately: it is the name of a subsystem here rather than
         a description of two things. ]]--
    name = "Unit Frames",

    feature = true,
    tickly = true,

    --[[ It draws into frames the client owns rather than into a bar of this
         addon's -- the same declaration as chat, action bars and nameplates,
         and for the same reason. ]]--

    --[[ **Draws with the shared look**, so its page carries the texture, font,
         size, outline and border rows.

         Declared rather than inferred, because nothing about a module implies
         it: `renders` says "none" for nameplates and unit frames, which draw
         into the client's frames and use every one of the five.

         Chat, the roster and quality of life do not have this, and action bars
         gave it up -- they use a font and nothing else, so three of the five
         rows were controls that did nothing. ]]--
    styled = { texture = true, font = true, fontSize = true, fontOutline = true },
    --[[ **No section**, so the shared appearance block shows on every page this
         module backs rather than only on General.

         Pinned to General, Bar Texture, Font, Font Size and Font Outline were
         invisible from the Player, Target, Target Of Target and Pet pages --
         which is where somebody adjusting one frame is standing when they want
         them. Built once and shown throughout: the same control with the same
         meaning everywhere it appears, rather than four copies writing one
         setting. ]]--
    renders = "none",

    --[[ Off. It restyles the four frames somebody is looking at all the time,
         and next to another unit frame addon it is a fight. ]]--
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
        --[[ Which frames to take over comes first because everything else
             depends on it -- and because taking over a frame somebody wanted
             left alone is the one thing a unit frame addon must not do by
             surprise. ]]--
        replacePlayer = true,
        replaceTarget = true,
        replaceTargetTarget = true,
        replacePet = true,

        --[[ Keep the four configurable frames together when requested. The
             existing per-frame keys remain available when this is off. ]]--
        syncFrames = false,

        --[[ **Text on the bars, which is the reason people install one of
             these.** 1.12 shows a percentage on mouseover and nothing the rest
             of the time. ]]--
        healthText = "maxpct",
        powerText = "value",

        --[[ Short numbers -- 1.11k rather than 1110. The original called this
             "true format" and had it off; on is right, because the whole point
             of the text is being read at a glance and five digits are not. ]]--
        shortNumbers = true,
        decimals = 1,

        healthSize = 10,
        powerSize = 10,
        nameSize = 11,
        nameOutline = true,

        --[[ Nudges, because Blizzard's art leaves the text sitting where the
             art wants it rather than where the bar is. Kept as offsets from the
             client's own anchor so zero means "where it was". ]]--
        healthX = 0, healthY = 0,
        powerX = 0, powerY = 0,
        nameX = 0, nameY = 5,

        --[[ **Colour.** Class colour on players is what everybody wants; on NPCs
             it is nonsense, because an NPC's "class" is whatever the server
             happened to give it. Off for them, and reaction colour instead. ]]--
        classColorHealth = true,
        npcClassColor = false,
        colorText = true,

        --[[ **The player's own bar, for when it is not class coloured.**

             "Not class coloured" still has to be *some* colour, and the
             client's is green -- which is Blizzard's answer, not a choice. The
             original carries this swatch for exactly that reason and the port
             had dropped it, which left switching class colour off looking like
             it did nothing. ]]--
        --[[ The name colour every frame falls back to, and the switch that
             decides whether it is used at all. ]]--

        playerColor = { 0.29, 0.67, 0.30, 1 },

        tappedColor = { 0.55, 0.55, 0.55, 1 },
        hostileColor = { 0.78, 0.25, 0.25, 1 },
        neutralColor = { 0.85, 0.77, 0.36, 1 },
        friendlyColor = { 0.29, 0.67, 0.30, 1 },

        --[[ Portraits as class icons rather than as the 3D model, which is the
             original's most-recognised feature. The art is the client's own --
             see PORTRAIT_ART. ]]--
        --[[ On. A picture of a debuff without a number is half the question:
             whether it is on is the other half, and the client answers only
             that one. ]]--
        --[[ On. The client draws a cast bar for you and nothing for anyone
             else, so "what is that mob casting" has no answer without one. ]]--
        targetCastBar = true,

        --[==[ **The client draws you a cast bar with no name and no clock.**

             1.12's own bar shows the literal word "Channeling" for every
             channelled spell -- not because the name is unavailable, but
             because its FrameXML never reads the one the event hands over.
             `SPELLCAST_CHANNEL_START` passes the spell in `arg2` and the stock
             bar ignores it. And neither a cast nor a channel gets a number, so
             "can I finish this before the pull" is answered by watching a
             rectangle. ]==]
        --[==[ **On: target-of-target and the pet, built here rather than
             borrowed.**

             Both are small frames a frame addon replaces first, and this module
             used to restyle the client's copies -- which loses to anything that
             hooks their update and hides them again. What was on screen was an
             icon, some bars, and no frame.

             A switch rather than an assumption, because somebody running
             another suite deliberately may want its versions of these two and
             ECO's everywhere else. ]==]
        ownSmallFrames = true,

        playerCastBar = true,
        castTimer = true,

        --[==[ **And the client's own cast bar goes away.**

             1.12 draws one for you and nothing for anybody else, with no spell
             name on a channel -- it prints the literal word "Channeling" -- and
             no clock on either. This module draws a better one in a place
             somebody chose, so leaving the client's underneath means two bars
             saying the same thing in different places, and the worse one is the
             one that cannot be moved.

             On, because a second cast bar is not a feature. Off puts the
             client's back, which is what makes it a setting rather than a
             removal. ]==]
        --[==[ ~~hideBlizzardCast~~ **is gone: the client's bar always goes when
             this module is on.**

             It was a switch on the reasoning that somebody might want the
             client's cast bar back. They might -- and the way to have it is the
             **Blizzard** border and the client's own bar texture, which this
             addon already offers, on a bar that is in the right place and
             answers to the same settings as everything else. Two cast bars on
             one screen was never the third option anybody wanted.

             An old profile carrying `hideBlizzardCast = false` is **ignored
             rather than obeyed**: honouring it would leave somebody with two
             bars and no row left to explain why. ]==]

        --[==[ **The picture is recognised before the word is read.**

             A cast bar is looked at out of the corner of the eye while doing
             something else, and at that distance an icon lands and a name does
             not. The name stays for the case the icon cannot cover -- a spell
             that is in neither your spellbook nor anything you have been hit
             by. ]==]
        castIcon = true,

        --[==[ Yellow, near enough to energy to read as the same family of
             thing: a resource that fills and empties on its own clock. The
             client's grey says nothing and looks like a disabled control. ]==]
        castColor = { 1.00, 0.82, 0.10, 1 },

        --[==[ **The cast bar's own border**, asked for, and the reason the
             switch above could go: with the Blizzard edge and the client's own
             bar texture this looks like the bar it replaced, in the right place
             and answering to the same settings as everything else.

             Its own rather than the module's, because the module's border is
             about the unit frames -- which are the client's own art and mostly
             want none -- and this is a bar this addon drew. ]==]
        castBorder = 3,
        castBorderColor = { 0.35, 0.35, 0.35, 1 },

        --[==[ **The cast bar's text answers for itself.**

             It took the unit frames' font, size and outline, which is right for
             the numbers on a health bar and wrong here: the spell name and the
             countdown are read in the half second before an interrupt, against a
             bar that is a different colour from everything around it, and the
             size that suits a health readout is not the size that suits that.

             An empty font follows the module, so somebody who never opens these
             rows sees exactly what they saw before. ]==]
        castFont = "",
        castFontSize = 0,
        castTextColor = { 1.00, 1.00, 1.00, 1 },

        --[==[ **How big the bar is, which was 150 by 14 and not up for
             discussion.**

             It is drawn away from the frame it belongs to and is read at a
             glance from the corner of the eye, so how big it wants to be
             depends on how far away it has been dragged and how much else is on
             screen. Somebody with the bar under their feet wants it short and
             wide; somebody with it beside the target frame wants it to match
             that frame.

             One pair for both bars, like the colour and the icon: they are the
             same bar drawn for two units, and two sets of sliders for one shape
             is two things to keep in step. ]==]
        castWidth = 150,
        castHeight = 14,

        auraTimers = true,

        --[==[ **The PvP countdown's place, as two numbers somebody can move.**

             Four passes: beside the icon, under it, further under it, and higher
             again -- each one a guess at a frame this addon cannot see. The
             faction icon is not the same size on both frames and sits over the
             portrait art, so "just below the icon" means something different
             depending on which one is drawn.

             The direction is settled and the pixels are not, which is exactly
             what a nudge is for. Everything else on these frames that had this
             problem already has one -- `nameX`, `healthY` and the rest -- and
             this should have been one of them the first time it moved.

             The default is up against the icon rather than clear of the frame:
             it is a number about the icon it is under, and a reader follows it
             from the icon. ]==]
        --[==[ **The countdown, on or off.**

             Asked for after it had been placed by hand: a switch rather than a
             thing to arrange. There is a coherent player on both sides -- the
             five minutes after `/pvp` matters if you are trying to stop being
             flagged and is noise if you never turn it off -- which is what makes
             it a setting rather than a default. ]==]
        showPVPTimer = true,

        --[==[ **Where the countdown sits on the player frame**, as an offset
             from its top-left.

             Six passes at guessing this from here -- beside the icon, under it,
             further under, higher, from the icon's top, by the icon's height --
             each one aimed at a frame this addon cannot see, and the last of
             them put the number behind the emblem. It is draggable now and this
             is only where it starts. ]==]
        pvpTimerX = 100,
        pvpTimerY = 44,

        classPortrait = true,

        --[[ **Dark mode: a different set of frame art, not a tint.**

             This said "a tint rather than a replacement, so it works whatever
             the client's art actually is" -- and the replacement is exactly
             what the art it borrows was drawn for. Tinting the light files
             towards grey washed the frames out until the bars looked like they
             were floating, which is how it was reported.

             On, as the slider was at 0.4. Migrated from that number the first
             time a profile is styled -- see DarkAmount. ]]--
        --[[ **Off, meaning "use the better art if it is there"** -- which is
             what somebody upgrading already had. On, the client's own frame
             art is used whatever else is installed, because a classic look
             is a choice rather than a fallback. ]]--
--[==[ **One choice with three answers, where there were two switches.**

             `classicFrameArt` and `compact` were independent booleans, which
             offered four states for three ideas -- and one of the four, classic
             art in compact mode, is not a thing the art supports. A reader had
             to know that "Classic Frame Art" and "Compact Player & Target
             Frames" were about the same decision before either caption made
             sense.

             The three modes:

               overhaul  this addon's frame art, with the target's mana bar
               compact   the same art, without it -- the original's Compact Mode
               classic   the client's own frame art, whatever else is installed

             `compact`, because that is what the two old defaults added up to
             and an upgrade should not change how anything looks. Migration 36
             reads the old pair. ]==]
        frameMode = "compact",

        darkMode = true,

        --[[ **The combat glow behind the player portrait, and the pet's attack
             flash.** The client draws both and they are the only indication
             that you are actually in combat rather than merely near it. On,
             because that is what the client does. ]]--
        statusGlow = false,

        --[[ **The pet frame drawn as a target-of-target frame**, which is
             smaller and better proportioned than the client's pet art, with
             happiness read as a colour: fed, content, unhappy. The original's
             Improved Pet. ]]--
        improvedPet = true,

        --[[ The pet's numbers hidden. A pet bar is small and its exact health
             is rarely the thing you are reading. The original ships this on;
             so does this. ]]--
        hidePetText = true,

        --[[ On, as vanilla draws it: a frame this small cannot hold two
             numbers without them landing on each other. ]]--
        hideTotText = true,

--[[ Derived from `frameMode` -- see `M:Compact`. Kept out of the
             defaults so there is one place the answer comes from. ]]--

        --[[ **How much health a mob actually has**, worked out rather than
             asked for.

             1.12 answers `UnitHealthMax` for a mob with 100, because what it
             gives is a percentage. MobHealth3's insight is that the percentage
             and the damage you deal are two views of the same number: hit
             something for 340 and watch it drop four percent, and it has 8500.

             On. It costs one subtraction per damage event and it is the
             difference between "62%" and "5.3k", which is the difference between
             guessing whether you can finish something and knowing. ]]--
        mobHealth = true,
        mobHealthPrecision = 10,
        mobHealthStableMax = false,

        --[[ **A hunter's real health while feigning.** The client reports a
             feigned hunter as dead at zero, which in a raid is a healer watching
             somebody they think is a corpse. The last real value is remembered
             and shown instead. ]]--
        feignHealth = true,

        --[[ **Re-target somebody who vanished.** Feign Death, Vanish and Invis
             all clear your target, and the target you had is almost always the
             target you still want. Off, because it is the one thing here that
             acts on its own. ]]--
        retarget = false,

        --[[ Where the player and target frames were dragged to, as offsets from
             the centre of the screen. Empty means the client's own anchors,
             which is where they have always been. ]]--
        positions = {},
    },

    options = {
        --[[ The UnitFrames tab owns one second-column navigation. General is
             the shared behaviour; the next four sections are the individual
             frames. This replaces the old five top-level categories. ]]--
        { "General", "__s_general", "section", "general" },

        --[==[ **All four, or none, and none is what the module switch is for.**

             These were four switches for replacing the player, target, target
             of target and pet frames separately. Nobody replaces three of them:
             the reason to have any of this is that the four look like each
             other and like the rest of the interface, and a mixed set is the
             one outcome nothing here was designed to produce.

             Somebody who does not want the frames turns the module off, which
             is a switch that already exists and says what it does. These four
             offered eleven further states, ten of which were mistakes. ]==]
        { "Frames", "__h_frames", "header" },
        { "Sync Options Across All Frames", "syncFrames", "boolean" },

        { "Numbers", "__h_numbers", "header" },
        { "Shorten Numbers Under 10k", "shortNumbers", "boolean" },
        { "Decimal Places", "decimals", "slider", 0, 3, 1,
          nil, nil, "!shortNumbers" },
        { "Hide Target Of Target's Numbers", "hideTotText", "boolean" },
        { "Hide The Pet's Numbers", "hidePetText", "boolean",
          nil, nil, nil, nil, nil, "!replacePet" },

        { "Colors", "__h_colors", "header" },
        { "Color Players By Class", "classColorHealth", "boolean" },
        { "Color NPCs By Class Too", "npcClassColor", "boolean" },
        { "Player", "playerColor", "color", true, nil, nil, nil, nil, "classColorHealth" },
        { "Hostile", "hostileColor", "color", true },
        { "Neutral", "neutralColor", "color", true },
        { "Friendly", "friendlyColor", "color", true },
        { "Tapped By Somebody Else", "tappedColor", "color", true },

        { "Behavior", "__h_behavior", "header" },
        { "Own Target-Of-Target And Pet Frames", "ownSmallFrames", "boolean" },
        { "Show Aura Timers", "auraTimers", "boolean" },

        { "Show PvP Unflag Countdown", "showPVPTimer", "boolean" },

        --[==[ **The place it is fixed at.**

             It was draggable for a release and is not any more, asked for that
             way once a position had been settled on by hand: *lock current
             position, remove it from edit mode.* The two numbers stay because
             they are what "current position" **is** -- a hardcoded pair here
             would throw away the placement that was actually chosen -- and
             because a number nobody has to drag to is the cheaper way to move it
             the one further pixel it may ever need.

             Greyed rather than hidden when the countdown is off: they are the
             answer to a question somebody is about to ask, and a row that
             vanishes reads as a setting this addon does not have. ]==]
        { "PvP Timer Across", "pvpTimerX", "slider", 0, 200, 1,
          nil, nil, "!showPVPTimer" },
        { "PvP Timer Down", "pvpTimerY", "slider", 0, 120, 1,
          nil, nil, "!showPVPTimer" },
        { "Class Icon Instead Of Portrait", "classPortrait", "boolean" },
        { "Combat Glow", "statusGlow", "boolean" },
        { "Slimmer Pet Frame", "improvedPet", "boolean",
          nil, nil, nil, nil, nil, "!replacePet" },
        --[==[ **Casting, as a section rather than five rows in Behavior.**

             They were scattered through a list about frames in general, which is
             where a setting goes when nobody has decided where it belongs. A
             cast bar is one thing with its own switches, and it is the thing
             somebody comes to this page to change after the first pull. ]==]
        { "Casting", "__s_casting", "section", "casting" },

        { "Show Your Own Cast Bar", "playerCastBar", "boolean" },
        { "Show A Target Cast Bar", "targetCastBar", "boolean" },
        --[[ The row that was here is gone; see the note beside the defaults. ]]--
        { "Show Time Left On Casts", "castTimer", "boolean" },
        { "Show The Spell Icon", "castIcon", "boolean" },
        { "Cast Bar Color", "castColor", "color", true },
        { "Cast Bar Border", "castBorder", OB.borders, 150 },
        { "Cast Bar Border Color", "castBorderColor", "color", true },

        --[[ Empty and zero mean "whatever the rest of the unit frames use", so
             these rows change nothing until somebody touches them. ]]--
        { "Cast Text Font", "castFont", OB.fonts, 150 },
        { "Cast Text Size", "castFontSize", "slider", 0, 24, 1 },
        { "Cast Text Color", "castTextColor", "color", true },
        { "Cast Bar Width", "castWidth", "slider", 80, 400, 5 },
        { "Cast Bar Height", "castHeight", "slider", 8, 40, 1 },

        --[[ Back to the general page for the rows that follow: a section marks
             where one page ends and the next begins, so the frame-wide settings
             need one of their own after Casting. ]]--
        { "Appearance", "__s_look", "section", "look" },

        { "Frame Style", "frameMode", OB.Enum(
                { "overhaul", "compact", "classic" },
                { "Overhaul", "Compact", "Classic" }) },

        { "Dark Mode", "darkMode", "boolean" },

        { "Move The Frames", "__a_ufdrag", "action",
          function() OB.modules.unitframes:SetDragMode(
                  not OB.modules.unitframes:DragMode()) end,
          function()
              if OB.modules.unitframes:DragMode() then return "Done Moving" end
              return "Move The Frames"
          end },

        { "Put Them Back", "__a_ufdragreset", "action",
          function() OB.modules.unitframes:ResetPositions() end },

        --[==[ **Mob health was seven settings and is now none of them.**

             The client does not report a mob's health, only a percentage, so
             this addon works the real number out by watching damage land. That
             is worth doing and it is not worth asking about: the section
             offered a switch for the feature, a precision slider, a stability
             toggle, a hunter special case, a re-target switch and a button to
             forget everything measured -- six controls and a header in front of
             something whose right answer is "yes, do that".

             Every one of them is now the default it always had. The behaviour
             is unchanged for anybody who never touched them, which was
             everybody who did not already know what "Mob Health Precision"
             meant. Migration 36 resets the keys so a profile that did touch
             them is not left holding a value with no way back. ]==]
    },

    --[[ **A page each, for the settings that describe one frame.**

         Built rather than written out four times: the rows differ only in which
         frame they name, and four hand-kept copies drift. The keys carry the
         frame's id -- `player_healthSize` -- so an ordinary settings row reads
         and writes them with no new plumbing.

         **Left empty means "follow the shared setting"**, which is why every
         row here defaults to nothing rather than to a number. A frame nobody
         has touched is not carrying four copies of a value it never chose. ]]--
    frameOptions = function(id, label)
        return {
            { label, "__s_" .. id, "section", id },

            { "Health Text", id .. "_healthText",
              OB.Enum(TEXT_KEYS, OB.unitTextModes) },
            { "Power Text", id .. "_powerText",
              OB.Enum(TEXT_KEYS, OB.unitTextModes) },

            { "Health Text Size", id .. "_healthSize", "slider", 6, 20, 1 },
            { "Power Text Size", id .. "_powerSize", "slider", 6, 20, 1 },
            { "Name Size", id .. "_nameSize", "slider", 6, 20, 1 },
            { "Outline The Name", id .. "_nameOutline", "boolean" },
            { "Color The Numbers", id .. "_colorText", "boolean" },

            --[[ The name's colour, which nothing could set before. Off by
                 default, so the client's own colouring stands. ]]--

            { "Health Text Across", id .. "_healthX", "slider", -60, 60, 1 },
            { "Health Text Up", id .. "_healthY", "slider", -30, 30, 1 },
            { "Power Text Across", id .. "_powerX", "slider", -60, 60, 1 },
            { "Power Text Up", id .. "_powerY", "slider", -30, 30, 1 },
            { "Name Across", id .. "_nameX", "slider", -60, 60, 1 },
            { "Name Up", id .. "_nameY", "slider", -30, 30, 1 },

            --[[ **The way back to General**, which an override system has to
                 have and which nothing else here offers. It says how many
                 settings this frame is answering for itself, so the page
                 also tells you whether it is overriding anything at all.

                 Left blank, every row above follows the shared setting; this
                 clears the ones that do not. ]]--
            { "Follow The General Settings", "__a_gen_" .. id, "action",
              function()
                  local n = OB.modules.unitframes:ResetFrameToGeneral(id)
                  Say(label .. " follows the general settings again"
                          .. " (" .. n .. " cleared).")
              end,
              function()
                  local m = OB.modules.unitframes
                  local n = m:FrameOverrideCount(id)
                  if n == 0 then return "Following The General Settings" end
                  return "Follow The General Settings (" .. n .. " set)"
              end },
        }
    end,

    --[[ Every event that changes what a frame is showing. The unit frames are
         Blizzard's and update themselves; what these are for is re-applying the
         *style* afterwards, because the client repaints a bar's colour and its
         text whenever the unit changes. ]]--
    events = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TARGET_CHANGED",
        "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_COMBAT", "UNIT_AURA",
        "UNIT_MANA", "UNIT_MAXMANA",
        "UNIT_ENERGY", "UNIT_RAGE", "UNIT_FOCUS",
        "UNIT_PET", "UNIT_FACTION", "UNIT_DISPLAYPOWER",
        "PLAYER_FLAGS_CHANGED",
        "PARTY_MEMBERS_CHANGED",
    },
})

--[[ The four frame pages are sections of UnitFrames, not categories of their
     own. Keep their row generator because it prevents four copies from
     drifting, then append those generated rows to the one UnitFrames page. ]]--
local FRAME_PAGE_ORDER = {
    { "player", "Player Frame" },
    { "target", "Target Frame" },
    { "targettarget", "Target Of Target" },
    { "pet", "Pet Frame" },
}

for i = 1, table.getn(FRAME_PAGE_ORDER) do
    local spec = FRAME_PAGE_ORDER[i]
    local rows = M.frameOptions(spec[1], spec[2])
    for r = 1, table.getn(rows) do table.insert(M.options, rows[r]) end
end

--[[ Exported so a test can drive the styling with the module's own description
     of a frame rather than a hand-made table that agrees with itself. ]]--
--[[ Not `frames`: that name is taken. `OB.HideFeature` treats a module's
     `frames` as the list of windows it owns and calls `Hide` on each, so
     putting frame *descriptions* there crashed the login path. ]]--
M.frameEntries = FRAMES

--[[ **Whether to use the borrowed frame art at all, which is a choice.**

     This was inferred: if the addon whose art it is happened to be installed,
     its art was used; otherwise the client's own. That reads as a fallback --
     something you get when the good option is missing -- and it is not. This
     addon is meant to be friendly to a classic look, and the client's own frame
     art is a perfectly good answer somebody may want on purpose.

     So it is asked rather than inferred. **Classic** uses the client's art
     whatever else is installed; the default keeps the borrowed art when it is
     there, which is what people upgrading already had.

     It also stops the appearance changing silently when somebody uninstalls the
     addon this one replaces -- which is exactly what happened here. ]]--
function M:FrameMode()
    local mode = self:Config().frameMode

    --[[ Anything unrecognised reads as the default rather than as nothing: a
         profile hand-edited to a typo should look like the addon, not like a
         frame with no art at all. ]]--
    if mode == "overhaul" or mode == "compact" or mode == "classic" then
        return mode
    end

    return "compact"
end

--[[ The target frame without its mana bar. Most things you fight do not have
     one worth watching, and the space it takes is the space the health bar
     wants. The original's Compact Mode. ]]--
function M:Compact()
    return self:FrameMode() == "compact"
end

function M:UseClassicFrameArt()
    if self:FrameMode() == "classic" then return true end

    --[[ Still the fallback when the borrowed art is not installed: classic is
         a choice here and a rescue there, and both want the client's art. ]]--
    return not legacyAssetsInstalled()
end

function M:Config()
    return OB.profile.modules.unitframes
end

-- ---------------------------------------------------------------------------
-- player PvP unflag countdown
-- ---------------------------------------------------------------------------

--[[ When /pvp is turned off, Vanilla leaves the faction PvP icon visible while
     a five-minute grace timer runs. `GetPVPTimer()` is the client-owned source
     of truth for that timer: a permanent flag reports 301000ms, while the
     actual unflag countdown is 300000ms down to zero.

     The readout deliberately has no option yet. The first pass is the requested
     fixed look: yellow Friz Quadrata at 6pt, minutes and seconds, directly beside
     the player's PvP icon. Once the size/position has been seen in-game we can
     make those adjustable if useful. ]]--
--[==[ **In a frame of its own, because a font string cannot be dragged.**

     Six passes at placing this by guesswork, each one aimed at a frame this
     addon cannot see. A `FontString` has no drag scripts, cannot be registered
     with edit mode and has nothing to outline; only a frame does. So the string
     lives in one and somebody puts it where they want it -- the same answer the
     minimap coordinates reached after the same argument.

     **Parented to the player frame**, which is what "part of the player frame"
     means: the position is stored as an offset from its top-left, so moving the
     player frame takes the countdown with it and no separate placement has to be
     kept in step.

     **Above the faction icon.** The icon is drawn by the client on the player
     frame, and a number on the same layer disappears behind the emblem -- which
     is exactly what "the timer is gone" turned out to be. A frame one level up
     draws over it whatever the client does to its own regions. ]==]
function M:PVPTimerFrame()
    if self.pvpTimerFrame then return self.pvpTimerFrame end

    local parent = getglobal("PlayerFrame") or UIParent
    if not parent or type(CreateFrame) ~= "function" then return nil end

    local frame = CreateFrame("Frame", "EquadisClassicOverhaulPVPTimerFrame", parent)

    frame:SetWidth(48)
    frame:SetHeight(PVP_TIMER_SIZE + 6)

    if frame.SetFrameLevel and parent.GetFrameLevel then
        frame:SetFrameLevel((parent:GetFrameLevel() or 0) + 5)
    end

    --[==[ **Not draggable, and not in edit mode.**

         It was both for a release, which is the standing answer for a placement
         somebody has questioned -- and here the placement got settled by hand and
         the machinery was asked to go. Fair: edit mode is a list of things worth
         arranging, and a thing that is where it belongs is clutter on it.

         **So it takes no mouse at all.** That is not incidental: this frame sits
         over the player frame, and a frame holding the mouse with nothing to do
         with it eats clicks meant for whatever is underneath -- which is the
         fault three separate reports have now been traced to. Nothing to drag
         means nothing to hold. ]==]
    frame:EnableMouse(false)

    self.pvpTimerFrame = frame
    return frame
end


function M:PVPTimerText()
    if self.pvpTimerText then return self.pvpTimerText end

    local parent = self:PVPTimerFrame() or getglobal("PlayerFrame") or UIParent
    if not parent or not parent.CreateFontString then return nil end

    local text = parent:CreateFontString("EquadisClassicOverhaulPVPTimer", "OVERLAY")
    if not text then return nil end

    --[==[ **Outlined, because it is drawn onto artwork rather than onto a
         backdrop.**

         The gap beside the portrait is the player frame's own carved metal, not
         a flat panel, and unoutlined text over that does not read as plainer --
         it disappears into whichever bit of the engraving it happens to land on.
         The nameplates force an outline on their own text for exactly this
         reason and say so at length; this is the same argument with metal in
         place of terrain.

         Forced rather than following the profile's outline setting: somebody who
         has turned outlines off has turned them off for text on backdrops, which
         this is not. ]==]
    text:SetFont(PVP_TIMER_FONT, PVP_TIMER_SIZE, "OUTLINE")
    text:SetTextColor(PVP_TIMER_R, PVP_TIMER_G, PVP_TIMER_B)
    --[[ Centred, because it is under the icon now and a string that changes
         width every second would otherwise shuffle sideways as it counts. ]]--
    text:SetJustifyH("CENTER")
    text:SetWidth(42)

    --[[ Tall enough for the glyphs it is being asked to draw. It was fixed at
         eight while the font was six; the font is ten now and a region shorter
         than its own text is a clipped number. ]]--
    text:SetHeight(PVP_TIMER_SIZE + 4)
    text:Hide()

    self.pvpTimerText = text
    self:PlacePVPTimer()
    return text
end

--[==[ **Under the icon, not beside it.**

     Beside was the first pass and it is the wrong side of the frame: the space
     to the right of the faction icon is where the player's name sits, so the
     countdown either collided with it or pushed out over the portrait. Under the
     icon there is nothing else, the number reads as belonging to the icon it is
     under, and it can be centred on it -- which is what makes a string that
     changes width every second stop shuffling sideways. ]==]
function M:PlacePVPTimer()
    local text = self.pvpTimerText
    if not text then return false end

    local cfg = self:Config()

    --[==[ **The frame carries the position and the string fills it.**

         Everything below used to anchor the string itself, against the faction
         icon, and six passes went into guessing an offset that works on both
         factions. It does not need guessing: somebody drags it once and the
         offset is theirs. ]==]
    local frame = self:PVPTimerFrame()

    if frame and not frame.dragging then
        frame:ClearAllPoints()

        local parent = getglobal("PlayerFrame")

        if parent then
            frame:SetPoint("TOPLEFT", parent, "TOPLEFT",
                    tonumber(cfg.pvpTimerX) or 100,
                    -(tonumber(cfg.pvpTimerY) or 44))
        end
    end

    if frame then
        text:ClearAllPoints()
        text:SetAllPoints(frame)
        return true
    end

    text:ClearAllPoints()

    --[[ Some 1.12-derived clients rename or omit the icon region, so the player
         name is the safe fallback rather than leaving the text unattached. ]]--
    local icon = getglobal("PlayerPVPIcon")
    local name = getglobal("PlayerName")

    --[==[ **Clear of the portrait ring, not just under the icon.**

         Directly under it was the second pass and still lands **on** the frame:
         the PvP icon sits over the player portrait, so "below the icon" is the
         portrait's own border, and a number drawn on that carved ring is
         unreadable whatever size it is. Reported with a screenshot and an arrow
         pointing at the empty space down and to the left.

         Down and out, into the gap beside the portrait where nothing else is
         drawn. Still anchored to the icon, so it moves with it and disappears
         with it. ]==]
    if icon then
        --[==[ **Below the icon, measured by asking the icon how tall it is.**

             Anchoring to the icon's *bottom* put the number halfway down the
             portrait, because the Horde emblem is most of the frame's left-hand
             side and "just below" it is already low. Anchoring to its *top* with
             a flat offset then put the number **on** the emblem -- eight pixels
             down a sixteen pixel icon is its lower half, and an eight point
             number on that artwork is invisible. Reported as the timer being
             gone, and it was: it was behind the icon.

             The icon knows its own height, so it is asked. `pvpTimerY` is the
             **gap below it** rather than a raw offset, which means the same
             thing on a sixteen pixel icon and a thirty pixel one -- and a nudge
             of two is two pixels of clear space on either faction. ]==]
        local iconHeight = 16

        if icon.GetHeight then
            local h = icon:GetHeight()
            if type(h) == "number" and h > 0 then iconHeight = h end
        end

        text:SetPoint("TOP", icon, "TOP",
                tonumber(cfg.pvpTimerX) or -10,
                -(iconHeight + (tonumber(cfg.pvpTimerY) or 2)))
    elseif name then
        text:SetPoint("TOP", name, "BOTTOM", 0, -2)
    else
        text:SetPoint("TOPLEFT", getglobal("PlayerFrame") or UIParent, "TOPLEFT", 112, -10)
    end

    return true
end

--[==[ **Minutes and seconds, and seconds carry their unit.**

     `4M 59S` was the first pass. Asked for as `4m59s` down to `1s`, which is the
     shape every other timer in this addon uses and is what people read at a
     glance -- the capitals and the space are three extra characters under a
     sixteen-pixel icon.

     The trailing `s` stays once the minutes are gone. `OB.DurationText` drops it
     there on purpose -- a bare number under a buff icon is unambiguous, because
     everything under a buff icon is seconds -- but this number sits under a
     faction icon among things that are not durations, so it says what it
     is. ]==]
function M:PVPTimerFormat(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds < 0 then return nil end

    local minutes = math.floor(seconds / 60)
    local rest = seconds - (minutes * 60)

    if minutes > 0 then
        return string.format("%dm%02ds", minutes, rest)
    end

    return string.format("%ds", rest)
end

function M:HidePVPTimer()
    if self.pvpTimerText then self.pvpTimerText:Hide() end
    self.lastPVPTimerSecond = nil
end

--[==[ **Which of the six gates is closing.**

     The countdown is guarded six times over, and every one of them fails the
     same way -- by drawing nothing. Reported as not showing, which is what all
     six look like from outside.

     Three of them are facts about this client that cannot be checked from
     anywhere but this client: whether `GetPVPTimer` exists on the build,
     what it answers during the grace period, and whether `UnitIsPVP` is still
     true while it runs. Vanilla answers milliseconds and uses `301000` as the
     sentinel for a permanent flag; a fork that never implemented the countdown
     answers the sentinel the whole time, and then no amount of code here helps.

     Run it **while the five minutes is running** -- the answer to "does this
     client count down at all" is only visible then. ]==]
function M:DebugPVP()
    local say = function(msg) OB.Print(msg, "Unit Frames") end

    say("module enabled: " .. tostring(OB.ModuleEnabled("unitframes")))
    say("replacePlayer:  " .. tostring(self:Config().replacePlayer))

    say("GetPVPTimer:    " .. type(GetPVPTimer))
    say("UnitIsPVP:      " .. type(UnitIsPVP))

    local flagged = type(UnitIsPVP) == "function" and UnitIsPVP("player") or nil
    say("UnitIsPVP(player): " .. tostring(flagged)
            .. "   -- false here is the countdown never being asked for")

    local raw = type(GetPVPTimer) == "function" and GetPVPTimer() or nil
    local ms = tonumber(raw)

    say("GetPVPTimer():  " .. tostring(raw) .. " (as a number: " .. tostring(ms) .. ")")

    if ms then
        if ms <= 0 then
            say("  -> rejected: nought or less is not a countdown")
        elseif ms > 300000 then
            say("  -> rejected: above five minutes. 301000 is vanilla's sentinel"
                    .. " for a permanent flag. If this reads 301000 while the"
                    .. " grace period is genuinely running, this build does not"
                    .. " implement the countdown and the number cannot be had.")
        else
            say("  -> accepted: " .. tostring(math.ceil(ms / 1000)) .. " seconds")
        end
    end

    local text = self.pvpTimerText
    say("readout made:   " .. tostring(text ~= nil))

    if text then
        say("  text:  [" .. tostring(text:GetText()) .. "]")
        say("  shown: " .. tostring(text:IsShown())
                .. "  alpha: " .. tostring(text.GetAlpha and text:GetAlpha()))

        local point, rel = text:GetPoint(1)
        say("  at " .. tostring(point) .. " of "
                .. tostring(rel and rel.GetName and rel:GetName() or rel))
    end

    local icon = getglobal("PlayerPVPIcon")
    say("PlayerPVPIcon:  " .. tostring(icon ~= nil)
            .. (icon and ("  shown: " .. tostring(icon:IsShown())) or ""))

    return true
end

--[==[ **This build has no `GetPVPTimer`, so the five minutes is timed here.**

     `/eq pvpdebug` on Ollie's client answers `GetPVPTimer: nil` while
     `UnitIsPVP("player")` is `1` -- flagged, and no call to ask how long is
     left. It is standard 1.12 API and this fork simply does not export it, so no
     amount of reading it differently helps.

     **What is observable** is the flag itself. Turning `/pvp` off does not
     unflag you: `UnitIsPVP` stays true and the client fires
     `PLAYER_FLAGS_CHANGED`. So a flag change that leaves you *still* flagged is
     the grace period starting, and the flag going false is it ending -- which is
     the confirmation, and the reason a mistimed start corrects itself.

     **Said as an estimate, because it is one.** The clock starts when this addon
     saw the change rather than when the server did, so it can be a moment out.
     Five minutes counted from a moment you watched happen is worth more than no
     number at all, and it is exactly right about the thing people use it for:
     whether it is nearly over.

     **`PLAYER_FLAGS_CHANGED` also fires for AFK and DND**, which would otherwise
     start a five-minute countdown for somebody going for a cup of tea. Those two
     are tracked and a change in either is not read as a PvP toggle.

     Persisted as a wall-clock time, so a `/reload` in the middle of it does not
     restart the five minutes. `GetTime` would be useless for that -- it is
     seconds since the client started, which is the mistake the mail
     autocomplete was making. ]==]
local PVP_GRACE = 300

function M:PVPFlags()
    local pvp = type(UnitIsPVP) == "function" and UnitIsPVP("player") and true or false
    local afk = type(UnitIsAFK) == "function" and UnitIsAFK("player") and true or false
    local dnd = type(UnitIsDND) == "function" and UnitIsDND("player") and true or false

    return pvp, afk, dnd
end

--[[ Called from `PLAYER_FLAGS_CHANGED`. Decides whether this was the `/pvp`
     toggle and, if so, starts the clock. ]]--
function M:NotePVPFlags()
    local pvp, afk, dnd = self:PVPFlags()

    local wasPvp = self.pvpWasFlagged
    local wasAfk, wasDnd = self.pvpWasAfk, self.pvpWasDnd

    self.pvpWasFlagged, self.pvpWasAfk, self.pvpWasDnd = pvp, afk, dnd

    --[[ No longer flagged: the grace ended, or never ran. Either way there is
         nothing left to count. ]]--
    if not pvp then
        self:ClearPVPGrace()
        return false
    end

    --[[ Away or busy changed, which is not a PvP toggle. ]]--
    if afk ~= wasAfk or dnd ~= wasDnd then return false end

    --[[ Freshly flagged rather than toggled off: no countdown yet. ]]--
    if not wasPvp then
        self:ClearPVPGrace()
        return false
    end

    --[[ Already counting. A second flag change does not restart it. ]]--
    if self:PVPGraceStart() then return false end

    self:StartPVPGrace()
    return true
end

--[==[ **Kept as state, not as a setting.**

     It lived on the profile, which survives a reload -- the thing it needs -- and
     is also what a **share code** exports. An unknown key is deliberately kept
     by the pruner, so somebody's PvP grace timestamp would have ridden along
     into everybody they gave a profile to. Junk in somebody else's settings, and
     a countdown for a flag they never had.

     `EquadisClassicOverhaulDB` is where this addon already keeps facts rather
     than preferences -- auction scan times, bag favourites, the chat log, the
     learned threat values -- and none of that is exported. **Per character**,
     through the same `OB.CharacterKey` the chat log uses: a PvP flag belongs to
     whoever is wearing it. ]==]
function M:PVPGraceStore()
    if type(EquadisClassicOverhaulDB) ~= "table" then return nil end

    EquadisClassicOverhaulDB.pvpGrace = EquadisClassicOverhaulDB.pvpGrace or {}
    return EquadisClassicOverhaulDB.pvpGrace
end

function M:PVPGraceKey()
    return (OB.CharacterKey and OB.CharacterKey()) or "Unknown"
end

function M:PVPGraceStart()
    local store = self:PVPGraceStore()
    if not store then return nil end

    local at = store[self:PVPGraceKey()]
    if type(at) ~= "number" or at <= 0 then return nil end

    return at
end

function M:StartPVPGrace()
    local store = self:PVPGraceStore()
    if not store or type(time) ~= "function" then return false end

    store[self:PVPGraceKey()] = time()
    return true
end

function M:ClearPVPGrace()
    local store = self:PVPGraceStore()
    if store then store[self:PVPGraceKey()] = nil end

    --[==[ **And the profile key this used to live on is taken out.**

         Anybody who ran the version that wrote it there is carrying it, and it
         would go on being exported in their share codes for ever. Cleared where
         the state is cleared, which every path through this feature reaches. ]==]
    if OB.profile then OB.profile.pvpGraceAt = nil end

    return true
end

--[==[ How many seconds are left, from whichever source can answer.

     The client first, always: a build that exports `GetPVPTimer` is telling the
     truth and this addon's arithmetic is a guess beside it. ]==]
function M:PVPSecondsLeft()
    if type(GetPVPTimer) == "function" then
        local ms = tonumber(GetPVPTimer())

        --[[ 301000 is vanilla's sentinel for a permanent flag, not five minutes
             and one second. ]]--
        if ms and ms > 0 and ms <= (PVP_GRACE * 1000) then
            return math.ceil(ms / 1000), true
        end

        --[[ The call exists and says "no countdown", which is an answer. Ours
             would only be second-guessing it. ]]--
        return nil, true
    end

    local at = self:PVPGraceStart()
    if not at or type(time) ~= "function" then return nil, false end

    local left = PVP_GRACE - (time() - at)

    --[==[ **Run out and still flagged means the start was wrong.** A flag change
         this addon read as a `/pvp` toggle and was not -- forgotten rather than
         left showing a number that has stopped meaning anything. ]==]
    if left <= 0 then
        self:ClearPVPGrace()
        return nil, false
    end

    return math.ceil(left), false
end

function M:UpdatePVPTimer(force)
    local cfg = self:Config()

    if not OB.ModuleEnabled("unitframes") or not cfg.replacePlayer
            or not cfg.showPVPTimer then
        self:HidePVPTimer()
        return false
    end

    --[[ Still the flag first: a countdown for somebody who is not flagged is a
         number about nothing. ]]--
    if type(UnitIsPVP) ~= "function" or not UnitIsPVP("player") then
        self:ClearPVPGrace()
        self:HidePVPTimer()
        return false
    end

    --[[ From the client where it can answer, and from our own clock where it
         cannot -- see `PVPSecondsLeft`. ]]--
    local seconds = self:PVPSecondsLeft()

    if not seconds or seconds <= 0 then
        self:HidePVPTimer()
        return false
    end

    if seconds > PVP_GRACE then seconds = PVP_GRACE end

    local text = self:PVPTimerText()
    if not text then return false end

    if force or self.lastPVPTimerSecond ~= seconds then
        text:SetText(self:PVPTimerFormat(seconds) or "")
        self.lastPVPTimerSecond = seconds
    end

    self:PlacePVPTimer()
    text:Show()
    return true
end


--[[ **Every frame gets its own copy of the settings that describe it.**

     These were one set shared by all four: one Health Text mode, one size, one
     nudge. That is the wrong shape for what people actually want -- percentages
     on the target and raw numbers on your own bars is the obvious example, and
     it could not be said at all.

     Stored flat, `player_healthSize` rather than a table per frame, because the
     settings panel binds a row to a key in the config and a flat key needs no
     new plumbing to read, write, default or save.

     **The shared value stays as the fallback**, which is what makes the
     migration free: a profile that has never seen a per-frame key reads the old
     shared one and looks exactly as it did. ]]--
local FRAME_KEYS = {
    "healthText", "powerText",
    "healthSize", "powerSize", "nameSize", "nameOutline",
    "healthX", "healthY", "powerX", "powerY", "nameX", "nameY",
    "colorText",
}

--[[ The proportions the client uses, which were hard-coded in the drawing code
     and are now the migration's opening offer instead.

     The pet's numbers sit two points smaller because its bar is a third the
     height; the pet and target-of-target names a point smaller because those
     frames are smaller. Baked into the starting values rather than subtracted
     at draw time, so that asking for size 12 on the pet gives size 12 rather
     than 10 -- a setting that quietly means something else is worse than no
     setting. ]]--
--[[ **No hidden proportion.**

     The pet drew its numbers two points smaller and the small frames' names
     one smaller, applied to whatever the shared setting said. That is a
     setting meaning something other than it says, and it is gone: every
     frame inherits the shared size as the shared size.

     Somebody who wants the pet's numbers smaller sets a size on the pet's
     own page, which is a proportion expressed as a value rather than as
     arithmetic nobody can see. ]]--

function M:FrameKey(id, key)
    return id .. "_" .. key
end

local FRAME_KEY_SET = {}
for i = 1, table.getn(FRAME_KEYS) do FRAME_KEY_SET[FRAME_KEYS[i]] = true end

local function copyFrameValue(value)
    if type(value) == "table" then return OB.DeepCopy(value) end
    return value
end

--[[ Split a flat per-frame key without Lua-pattern alternation (1.12's Lua has
     none). Longest id first so `targettarget_` cannot be mistaken for target. ]]--
function M:SplitFrameKey(key)
    if type(key) ~= "string" then return nil, nil end

    local ids = { "targettarget", "player", "target", "pet" }
    for i = 1, table.getn(ids) do
        local id = ids[i]
        local prefix = id .. "_"
        if string.sub(key, 1, string.len(prefix)) == prefix then
            return id, string.sub(key, string.len(prefix) + 1)
        end
    end

    return nil, nil
end

--[[ What the settings control should show. Per-frame keys are overrides and may
     legitimately be nil in SavedVariables; the frame itself already falls back
     to the shared setting, so the UI must show that same effective value. ]]--
function M:OptionValue(key)
    local id, frameKey = self:SplitFrameKey(key)
    if id and FRAME_KEY_SET[frameKey] then
        return self:FrameSetting(id, frameKey), true
    end
    return nil, false
end

function M:SyncFramesFrom(sourceId)
    local cfg = self:Config()
    sourceId = sourceId or "player"

    for i = 1, table.getn(FRAME_KEYS) do
        local key = FRAME_KEYS[i]
        local value = self:FrameSetting(sourceId, key)

        -- Keep the old shared fallback coherent too. That matters if a future
        -- profile clears an override, and it keeps General-era profiles from
        -- carrying a hidden value that disagrees with the synced frames.
        cfg[key] = copyFrameValue(value)

        for f = 1, table.getn(FRAME_PAGE_ORDER) do
            local id = FRAME_PAGE_ORDER[f][1]
            cfg[self:FrameKey(id, key)] = copyFrameValue(value)
        end
    end
end

--[[ One write path powers every checkbox/slider in the panel. When sync is on,
     a change on any one frame is copied to all four immediately. Turning sync
     on uses Player Frame as the source because it is the stable baseline and
     avoids silently resurrecting an older shared/default value. Turning it off
     leaves the copies in place; they simply become independent from then on. ]]--
function M:AfterSet(key, value)
    local cfg = self:Config()

    if key == "syncFrames" then
        if value then self:SyncFramesFrom("player") end
        return
    end

    if not cfg.syncFrames then return end

    local id, frameKey = self:SplitFrameKey(key)
    if not id or not FRAME_KEY_SET[frameKey] then return end

    cfg[frameKey] = copyFrameValue(value)

    for f = 1, table.getn(FRAME_PAGE_ORDER) do
        local frameId = FRAME_PAGE_ORDER[f][1]
        cfg[self:FrameKey(frameId, frameKey)] = copyFrameValue(value)
    end
end

--[[ Read per frame, falling back to the shared value. The fallback is not a
     nicety: it is what lets an old profile carry on unchanged until somebody
     touches one of these. ]]--
--[[ **A per-frame value is an override; absent means "follow the shared one".**

     Written this way rather than by copying the shared values into four sets at
     first sight, which was the first attempt. Pre-populating means a profile
     that has never opened these tabs still has its behaviour frozen into four
     copies -- and from then on the shared setting is dead, silently, including
     for anything that sets it. It also has to be got right once, on a live
     profile, with no way back.

     An override that is simply absent needs no migration at all: an untouched
     profile reads exactly what it read before, and the first per-frame change
     is the first time anything diverges.

     **The client's proportions belong to the default, not to a stated value.**
     The pet's numbers sit two points smaller and the small frames' names one
     smaller, so the fallback carries that drop -- but a size typed into the pet
     frame's own box is used as typed. A setting that means two less than it
     says is worse than no setting. ]]--
--[[ **Clearing the shadow copies an older build left behind.**

     An earlier version of this module wrote every frame's own copy of every
     setting the first time it styled a profile -- four copies of the shared
     value, none of them asked for. That model was replaced by overrides, where
     an absent key means "follow the shared one", but the copies it already
     wrote are still in people's saved variables.

     They are invisible and they win. Somebody changes a General setting, four
     shadow copies quietly outrank it, and the control appears not to work --
     which is exactly the fault this is here to prevent.

     **Only copies that still agree with the shared value are cleared.** One
     that differs is either a deliberate choice on that frame's page or a copy
     of a shared value since changed, and throwing away a number somebody may
     have typed is worse than leaving a redundant one. Equal means redundant
     means safe to drop, and dropping it changes nothing on screen today while
     letting General reach that frame tomorrow.

     Runs once. A profile that has been through it carries the marker and is
     left alone, so this cannot keep undoing later choices. ]]--
local FRAME_OVERRIDE_MIGRATION = 1

function M:MigrateFrameOverrides()
    local cfg = self:Config()

    if (tonumber(cfg.frameOverrideMigration) or 0) >= FRAME_OVERRIDE_MIGRATION then
        return 0
    end

    cfg.frameOverrideMigration = FRAME_OVERRIDE_MIGRATION

    local cleared = 0

    for f = 1, table.getn(FRAME_PAGE_ORDER) do
        local id = FRAME_PAGE_ORDER[f][1]

        for k = 1, table.getn(FRAME_KEYS) do
            local key = FRAME_KEYS[k]
            local flat = self:FrameKey(id, key)
            local own = cfg[flat]

            if own ~= nil and own == cfg[key] then
                cfg[flat] = nil
                cleared = cleared + 1
            end
        end
    end

    return cleared
end

--[[ How many of this frame's settings are its own rather than the shared
     ones. The page uses it to say whether a frame is overriding anything at
     all, which is the question "is this page doing something" asks. ]]--
function M:FrameOverrideCount(id)
    local cfg = self:Config()
    local n = 0

    for k = 1, table.getn(FRAME_KEYS) do
        if cfg[self:FrameKey(id, FRAME_KEYS[k])] ~= nil then n = n + 1 end
    end

    return n
end

--[[ Everything on one frame handed back to the shared settings, which is the
     obvious way out that an override system has to have. Offered on each
     frame's page. ]]--
function M:ResetFrameToGeneral(id)
    local cfg = self:Config()
    local cleared = 0

    for k = 1, table.getn(FRAME_KEYS) do
        local flat = self:FrameKey(id, FRAME_KEYS[k])

        if cfg[flat] ~= nil then
            cfg[flat] = nil
            cleared = cleared + 1
        end
    end

    self:Apply()
    return cleared
end

function M:FrameSetting(id, key)
    local cfg = self:Config()
    local own = cfg[self:FrameKey(id, key)]

    if own ~= nil then return own end

    --[[ The shared value, as the shared value: no proportion applied on the
         way past. ]]--
    return cfg[key]
end

--[[ **A size means that size, in points.**

     This multiplied every unit-frame size by the shared Appearance Font Size
     over twelve, so a health size showing 10 drew at 15 when the shared size
     was 18. One number on the panel, a different number on the screen, and no
     way to tell from the panel which you were going to get.

     The shared Font Size is still the module's font size -- it is what anything
     without a size of its own uses -- but it no longer scales the sizes that do
     have one. There is one meaning per control.

     Clamped at four because a font smaller than that is a smudge, and that is a
     limit rather than a transformation: it changes nothing a reader could have
     asked for. ]]--
function M:TextSize(base)
    local size = tonumber(base) or 10

    if size < 4 then size = 4 end
    return math.floor(size + 0.5)
end

--[[ **Dark mode is on or off, and was briefly a slider.**

     The slider made sense while "dark" meant tinting the light art towards
     grey: a percentage is a sensible thing to ask for when the answer is a
     multiplier. It stopped making sense the moment dark mode became what it
     always should have been -- a different set of art files, drawn dark, with
     the highlights and edges made for it. There is no such thing as art that is
     forty percent dark, so there is nothing for a slider to say.

     A fixed tint is still used for the frames that have no dark art of their
     own -- the pet, the target of target and the party. That is a constant
     rather than a setting, because the question it answers ("how dark should
     the frames without dark art be, to sit beside the ones that have it") has
     one right answer and it is not the reader's to pick. ]]--
local DARK_TINT = 0.4

function M:DarkAmount()
    local cfg = self:Config()

    --[[ **The old slider is the authority when migrating, not the old flag.**

         An earlier migration went the other way -- boolean to slider -- and
         wrote `darkMode = true` alongside `darkness = 0` to mean *off*. So a
         profile from that era has `darkMode` set true while the reader had dark
         mode switched off, and believing the flag would switch it back on for
         them. The number is the one that was telling the truth.

         Cleared once read, so the next login has nothing left to migrate. ]]--
    if cfg.darkness ~= nil then
        local raw = tonumber(cfg.darkness)

        cfg.darkMode = raw ~= nil and raw > 0
        cfg.darkness = nil
    end

    if cfg.darkMode == nil then cfg.darkMode = true end
    if not cfg.darkMode then return 0 end

    return DARK_TINT
end

function M:DarkShade()
    return 1 - self:DarkAmount()
end

-- ---------------------------------------------------------------------------
-- what colour a unit is
-- ---------------------------------------------------------------------------

--[[ **Whose colour, and why an NPC's class is not one.**

     A player gets their class colour, which is what everybody means by "class
     coloured frames".

     An NPC has a class too -- the server gives every creature one -- and it is
     meaningless: a wolf is a warrior. So NPCs get their *reaction* instead,
     which is the thing you actually want to know, and the class option for them
     is off and stays a separate switch rather than being folded in.

     A tapped mob is grey before anything else is considered. It does not matter
     what colour it would otherwise be; you cannot loot it, and that is the fact
     worth showing. ]]--
function M:UnitColor(unit)
    local cfg = self:Config()
    if not UnitExists(unit) then return nil end

    -- UFI's target update gives tap ownership first priority: a mob somebody
    -- else tagged is grey regardless of reaction or NPC class.
    if not UnitIsPlayer(unit) and type(UnitIsTapped) == "function"
            and UnitIsTapped(unit)
            and type(UnitIsTappedByPlayer) == "function"
            and not UnitIsTappedByPlayer(unit) then
        return cfg.tappedColor
    end

    if not UnitIsPlayer(unit) then
        if type(UnitIsConnected) == "function" and not UnitIsConnected(unit) then
            return cfg.tappedColor
        end
        if type(UnitIsDeadOrGhost) == "function" and UnitIsDeadOrGhost(unit) then
            return cfg.tappedColor
        end
    end

    local class = OB.UnitClassToken(unit)

    --[[ Out of range, UnitIsPlayer says no and a party member fell through to
         the NPC branch below -- coloured by reaction, or by the NPC class
         setting, rather than by their class. ]]--
    if OB.IsPlayerUnit(unit) then
        if cfg.classColorHealth and class then
            local r, g, b = OB.ClassColor(class)
            if r then return { r, g, b, 1 } end
        end
        return self:ReactionColor(unit)
    end

    if cfg.npcClassColor and class then
        local r, g, b = OB.ClassColor(class)
        if r then return { r, g, b, 1 } end
    end

    return self:ReactionColor(unit)
end

function M:ReactionColor(unit)
    local cfg = self:Config()

    if type(UnitReaction) ~= "function" then return cfg.hostileColor end

    local reaction = UnitReaction(unit, "player")
    if not reaction then return cfg.hostileColor end

    if reaction > 4 then return cfg.friendlyColor end
    if reaction == 4 then return cfg.neutralColor end

    return cfg.hostileColor
end

-- ---------------------------------------------------------------------------
-- how much health a mob actually has
-- ---------------------------------------------------------------------------

--[[ **1.12 will not tell you, and MobHealth3 worked out that it does not have
     to.**

     `UnitHealthMax` on a mob answers 100, because what the client gives is a
     percentage. But the percentage and the damage you deal are two views of the
     same number: hit something for 340, watch it drop four percent, and it has
     eight and a half thousand.

     `max = damage / percentLost * 100`, accumulated over a fight so one unlucky
     rounding does not decide it.

     **Keyed by name and level together**, which is not fussiness: a level 22
     Defias Thug and a level 24 one are different creatures with the same name,
     and averaging them gives a number that is wrong for both.

     Account-wide beside the vendor prices and the cast times, on the same
     argument -- how much health a Defias Thug has is a fact about the game. ]]--
function OB.MobKey(name, level)
    if not name or name == "" then return nil end
    return name .. ":" .. tostring(level or 0)
end

-- Accept both the old ECO sample table and the repaired MobHealth3-shaped table.
function OB.MobHealthMax(name, level)
    local key = OB.MobKey(name, level)
    local known = key and OB.mobHealth and OB.mobHealth[key]
    if type(known) == "number" then return known end
    if type(known) ~= "table" then return nil end
    return known.max
end

-- ---------------------------------------------------------------------------
-- MobHealth3 behaviour, without Ace2
-- ---------------------------------------------------------------------------

M.mobAccHP = M.mobAccHP or {}
M.mobAccPerc = M.mobAccPerc or {}
M.mobNoCalc = M.mobNoCalc or {}

function M:MobTargetChanged()
    local cfg = self:Config()

    -- Stable-max mode commits the previous fight's accumulated estimate when
    -- the target changes, exactly where MobHealth3 does it.
    local old = self.mobCurrent
    if cfg.mobHealthStableMax and old and old.accHP and old.accHP > 0
            and old.accPerc and old.accPerc > 0 and old.key then
        local max = math.floor(old.accHP / old.accPerc * 100 + 0.5)
        OB.mobHealth[old.key] = {
            max = max, damage = old.accHP, percent = old.accPerc,
        }
        self.mobAccHP[old.key], self.mobAccPerc[old.key] = old.accHP, old.accPerc
    end

    self.mobCurrent = nil
    if not cfg.mobHealth or not UnitExists("target") then return false end
    -- ECO exposes this as *mob* health. Player max HP is volatile with gear and
    -- buffs and is not useful in this account-wide creature cache.
    if UnitIsPlayer("target") then return false end
    if type(UnitCanAttack) == "function" and not UnitCanAttack("player", "target") then return false end
    if type(UnitIsDead) == "function" and UnitIsDead("target") then return false end
    if type(UnitIsFriend) == "function" and UnitIsFriend("player", "target") then return false end

    -- MobHealth3 excludes player-controlled beasts/demons so hunter/warlock pets
    -- sharing names with real creatures do not poison the cache.
    local creature = type(UnitCreatureType) == "function" and UnitCreatureType("target") or nil
    if (creature == "Beast" or creature == "Demon")
            and type(UnitPlayerControlled) == "function"
            and UnitPlayerControlled("target") then
        return false
    end

    local name, level = UnitName("target"), UnitLevel("target")
    local key = OB.MobKey(name, level)
    if not key then return false end

    local start = UnitHealth("target")
    local known = OB.mobHealth and OB.mobHealth[key]
    local accHP, accPerc = self.mobAccHP[key], self.mobAccPerc[key]

    -- Session accumulators are separate from the persistent display cache in
    -- MobHealth3. That distinction matters: a mob changed before reaching the
    -- precision threshold must keep the samples it already taught us.
    if accHP == nil or accPerc == nil then
        if type(known) == "table" and known.damage and known.percent then
            accHP, accPerc = known.damage, known.percent
        elseif type(known) == "table" and known.max then
            accHP, accPerc = known.max, 100
        elseif type(known) == "number" then
            accHP, accPerc = known, 100
        else
            accHP, accPerc = 0, 0
        end
    end

    -- MobHealth3 limits the memory of a mob to roughly two kills so variants
    -- with the same name/level can eventually correct an old estimate.
    if accPerc > 200 then
        accHP = accHP / accPerc * 100
        accPerc = 100
    end
    self.mobAccHP[key], self.mobAccPerc[key] = accHP, accPerc

    self.mobCurrent = {
        key = key, name = name, level = level,
        start = start, last = start,
        recent = 0, total = 0,
        accHP = accHP, accPerc = accPerc,
        stableHadValue = OB.MobHealthMax(name, level) and true or false,
    }
    return true
end

function M:MobCombat(amount)
    local m = self.mobCurrent
    amount = tonumber(amount)
    if not m or not amount or amount <= 0 then return false end
    m.recent = m.recent + amount
    m.total = m.total + amount
    return true
end

function M:MobHealthUpdate()
    local m = self.mobCurrent
    if not m or not UnitExists("target") then return false end
    if OB.MobKey(UnitName("target"), UnitLevel("target")) ~= m.key then
        return self:MobTargetChanged()
    end

    local current, max = UnitHealth("target"), UnitHealthMax("target")
    if self.mobNoCalc[m.key] then return false end
    if current == m.start or current == 0 then return false end

    -- Beast Lore (and some private-server APIs) can reveal real HP. Trust it and
    -- stop estimating; this is strictly better information.
    if max and max > 100 then
        OB.mobHealth[m.key] = { max = max, damage = max, percent = 100 }
        self.mobAccHP[m.key], self.mobAccPerc[m.key] = max, 100
        self.mobNoCalc[m.key] = true
        return true
    end

    -- A heal invalidates the pending damage-to-percent relationship.
    if current > m.last or m.start > 100 then
        m.last = current
        m.start = current
        m.recent = 0
        m.total = 0
        return false
    end

    if m.recent <= 0 or current == m.last then return false end

    m.accHP = m.accHP + m.recent
    m.accPerc = m.accPerc + (m.last - current)
    self.mobAccHP[m.key], self.mobAccPerc[m.key] = m.accHP, m.accPerc
    m.recent = 0
    m.last = current

    local cfg = self:Config()
    local precision = tonumber(cfg.mobHealthPrecision) or 10
    if m.accPerc < precision then return false end

    if cfg.mobHealthStableMax and m.stableHadValue then return false end

    local estimate = math.floor(m.accHP / m.accPerc * 100 + 0.5)
    OB.mobHealth[m.key] = {
        max = estimate, damage = m.accHP, percent = m.accPerc,
    }
    m.stableHadValue = true
    return true
end

-- ---------------------------------------------------------------------------
-- SimpleFeignHealth behaviour, scoped to ECO's own unit-frame text
-- ---------------------------------------------------------------------------

OB.feignedHealth = OB.feignedHealth or {}

function M:IsFeigning(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    local _, class = UnitClass(unit)
    if class ~= "HUNTER" then return false end
    if type(UnitBuff) ~= "function" then return false end

    local i = 1
    while i <= 32 do
        local texture = UnitBuff(unit, i)
        if not texture then break end
        if texture == FEIGN_TEXTURE then return true end
        i = i + 1
    end
    return false
end

local function unitDead(unit)
    if type(UnitIsDeadOrGhost) == "function" then return UnitIsDeadOrGhost(unit) and true or false end
    if type(UnitIsDead) == "function" then return UnitIsDead(unit) and true or false end
    return false
end

function M:NoteFeign(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return false end
    local name = UnitName(unit)
    local _, class = UnitClass(unit)
    if not name or class ~= "HUNTER" then return false end

    -- Never replace the cache with the zero the client reports once FD begins.
    if unitDead(unit) then return false end

    local health = UnitHealth(unit)
    if not health or health <= 0 then return false end

    OB.feignedHealth[name] = {
        health = health,
        max = UnitHealthMax(unit),
        mana = UnitMana(unit),
        manaMax = UnitManaMax(unit),
        at = type(GetTime) == "function" and GetTime() or 0,
    }
    return true
end

-- SimpleFeignHealth asks a hidden unit tooltip for a feigning hunter's real
-- current HP. Keep that useful part, but scope it to ECO rather than replacing
-- the global UnitHealth function for every addon in the UI.
function M:FeignActualHealth(unit)
    if type(CreateFrame) ~= "function" or not UIParent then return nil end

    if not self.feignScanner then
        local tip = CreateFrame("GameTooltip", "EquadisUnitFrameFeignScanner",
                UIParent, "GameTooltipTemplate")
        if not tip then return nil end
        if tip.SetOwner then tip:SetOwner(tip, "ANCHOR_NONE") end
        self.feignScanner = tip
        if tip.GetChildren then self.feignScannerBar = tip:GetChildren() end
    end

    local tip, bar = self.feignScanner, self.feignScannerBar
    if not tip or not tip.SetUnit then return nil end
    if tip.ClearLines then tip:ClearLines() end
    tip:SetUnit(unit)

    local value = bar and bar.GetValue and bar:GetValue()
    if value and value > 0 then return value end
    return nil
end

function M:HealthOf(unit)
    local live, max = UnitHealth(unit), UnitHealthMax(unit)
    if not self:Config().feignHealth or not unitDead(unit) or not self:IsFeigning(unit) then
        return live, max
    end
    local remembered = OB.feignedHealth[UnitName(unit) or ""]
    if not remembered then return live, max end
    return self:FeignActualHealth(unit) or remembered.health, remembered.max
end

function M:PowerOf(unit)
    local live, max = UnitMana(unit), UnitManaMax(unit)
    if not self:Config().feignHealth or not unitDead(unit) or not self:IsFeigning(unit) then
        return live, max
    end
    local remembered = OB.feignedHealth[UnitName(unit) or ""]
    if not remembered then return live, max end
    return remembered.mana or live, remembered.manaMax or max
end

--[[ Both of these moved to core when the party frames were asked for the same
     six modes. They stay as methods because every call site here reads
     `self:Number(v)` and `self:BarText(...)`, and because the two settings the
     shared version takes as arguments are this module's own. ]]--
function M:Number(value)
    local cfg = self:Config()
    return OB.ShortValue(value, cfg.shortNumbers, cfg.decimals)
end

function M:BarText(value, max, mode)
    local cfg = self:Config()
    return OB.BarText(value, max, mode, cfg.shortNumbers, cfg.decimals)
end

-- ---------------------------------------------------------------------------
-- taking over the client's own text and colour
-- ---------------------------------------------------------------------------

--[[ **The client owns these strings, and it keeps writing to them.**

     `TextStatusBar_UpdateTextString` runs from every status bar's own
     `OnValueChanged`, which means it fires *after* any handler that took a
     damage event as its cue. The port wrote its text on the module's events and
     stopped there, so Blizzard overwrote it a frame later -- and every text
     setting on the page read as a setting that does nothing.

     Worse, the client *hides* the string unless the `statusBarText` CVar is on,
     which it is not by default. So even the frames where the timing happened to
     work showed nothing at all.

     `HealthBar_OnValueChanged` is the same problem in colour: it paints every
     health bar green on every value change.

     **So both are replaced, which is what the original does and the only thing
     that works.** 1.12 has no `hooksecurefunc` and no ordering guarantee that
     would let an event handler win a race against the client's own callback.

     **Installed once and never removed**, on the same rule as the chat hook: a
     method slot is one deep, so restoring our saved original silently deletes
     whatever a neighbour installed after us. The switches are read *inside*, and
     a module that is off delegates to the original -- which is the same
     behaviour as not being installed, without the hazard of uninstalling. ]]--
local BAR_ROLE = {}

for i = 1, table.getn(FRAMES) do
    BAR_ROLE[FRAMES[i].health] = { entry = FRAMES[i], role = "health" }
    BAR_ROLE[FRAMES[i].power] = { entry = FRAMES[i], role = "power" }
end

--[[ Which frame a bar belongs to and which of its two it is, or nil for a bar
     that is none of ours -- the focus frame, a raid frame, another addon's. ]]--
function M:BarRole(bar)
    if not bar or not bar.GetName then return nil end

    local found = BAR_ROLE[bar:GetName() or ""]
    if not found then return nil end

    local entry = found.entry
    if found.party then entry = self:PartyEntry(found.party) end

    if not entry or not self:Owns(entry) then return nil end

    return entry, found.role
end

--[[ **ECO always draws its own status text above the bar.**

     Reusing Blizzard's `TargetFrameHealthBarText` looked convenient, but on
     several 1.12 forks that FontString is not actually a region of the
     StatusBar. It is a sibling owned by the target-frame art, at a lower draw
     level than the bar texture. The result is exactly the failure it sounds
     like: ECO writes the right number and the health texture paints over it.

     Those forks can also expose a centre string *and* left/right strings, so
     trying to pick one client string as the canonical one leaves the others
     free to reappear. The reliable ownership boundary is therefore: while ECO
     owns a unit frame, every Blizzard number string is hidden and ECO draws one
     private FontString on a small frame whose level is explicitly above the
     StatusBar. Turning the frame back over to Blizzard restores all of the
     client strings from the snapshots below. ]]--
function M:BarTextString(bar, create)
    if not bar then return nil end

    self.syntheticBarText = self.syntheticBarText or {}
    self.syntheticBarTextLayer = self.syntheticBarTextLayer or {}

    local text = self.syntheticBarText[bar]
    local layer = self.syntheticBarTextLayer[bar]

    if text then
        if layer then
            local level = (bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 20
            if layer.SetFrameLevel then layer:SetFrameLevel(level) end
            if layer.Show then layer:Show() end
        end
        return text
    end

    if not create then return nil end

    local parent = bar
    layer = CreateFrame("Frame", nil, parent)
    if not layer then return nil end

    local level = (bar.GetFrameLevel and bar:GetFrameLevel() or 0) + 20
    if layer.SetFrameLevel then layer:SetFrameLevel(level) end
    if layer.SetAllPoints then
        layer:SetAllPoints(bar)
    elseif layer.SetPoint then
        layer:ClearAllPoints()
        layer:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        layer:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end

    text = layer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if not text then
        layer:Hide()
        return nil
    end

    text:SetPoint("CENTER", layer, "CENTER", 0, 0)
    self.syntheticBarText[bar] = text
    self.syntheticBarTextLayer[bar] = layer

    return text
end

--[[ **Some 1.12 forks expose *three* number strings on a status bar.**

     The stock client normally gives us one `TextString`, but Octo/Turtle-style
     clients can also attach left/right status strings. When ECO writes its own
     centred format, those client strings remain alive underneath it -- e.g. a
     centred `4.26k/4.26k (100%)` with `100%` still printed at the lower left
     and `4263` at the lower right.

     They are not a second ECO format, so moving the centred string cannot fix
     them. While ECO owns a bar, the centred string is the *only* numeric
     display. Suppress every other FontString attached to that bar, plus the
     common named/field variants used by 1.12 forks. Alpha is forced to zero as
     well as hiding the region: a client callback that writes and Shows one of
     these later in the frame still cannot resurrect it underneath ECO's text.

     Original state is remembered per object and restored if that unit frame is
     handed back to the client. ]]--
local AUX_BAR_TEXT_FIELDS = {
    "LeftText", "RightText",
    "TextLeft", "TextRight",
    "LeftTextString", "RightTextString",
    "TextStringLeft", "TextStringRight",
}

local AUX_BAR_TEXT_SUFFIXES = {
    "TextLeft", "TextRight",
    "LeftText", "RightText",
    "LeftTextString", "RightTextString",
    "TextStringLeft", "TextStringRight",
}

function M:AuxBarTextStrings(bar, primary)
    local out, seen = {}, {}
    if not bar then return out end

    local function add(obj)
        --[[ Type first: these field names are guesses at what a client or a
             private-server wrapper might hang on a bar, and any of them may
             be something other than a region. `frame.text` is a *function*
             on this client, and `if not obj` lets a function through to the
             field check below, which throws instead of skipping. The same
             fault killed the nameplate scan. ]]--
        if type(obj) ~= "table" then return end
        if obj == primary or seen[obj] then return end

        -- FontStrings have GetText/SetText. Using the capability rather than a
        -- hard object-type check also covers private-server UI wrappers.
        if not obj.GetText or not obj.SetText then return end

        seen[obj] = true
        table.insert(out, obj)
    end

    -- The client's nominal primary is native too. `primary` is ECO's private
    -- overlay string, so hiding these cannot hide the value ECO is drawing.
    add(bar.TextString)

    for i = 1, table.getn(AUX_BAR_TEXT_FIELDS) do
        add(bar[AUX_BAR_TEXT_FIELDS[i]])
    end

    local name = bar.GetName and bar:GetName()
    if name then
        add(getglobal(name .. "Text"))

        -- Target-of-target is named both ways across 1.12 forks.
        if name == "TargetofTargetHealthBar" then
            add(getglobal("TargetofTargetFrameHealthBarText"))
        elseif name == "TargetofTargetManaBar" then
            add(getglobal("TargetofTargetFrameManaBarText"))
        end

        for i = 1, table.getn(AUX_BAR_TEXT_SUFFIXES) do
            add(getglobal(name .. AUX_BAR_TEXT_SUFFIXES[i]))
        end
    end

    -- Unknown fork spelling? If the extra text is genuinely a region of the
    -- status bar, it is still unambiguously duplicate number text. The chosen
    -- primary is excluded above, so every other FontString region can go.
    if bar.GetRegions then
        local regions = { bar:GetRegions() }
        for i = 1, table.getn(regions) do add(regions[i]) end
    end

    -- Some Octo/Turtle client builds put the extra white status numbers on a
    -- sibling frame instead of on the StatusBar itself. There is no stable
    -- global name for those regions, so discover numeric FontStrings inside
    -- the owning Blizzard unit frame as a final fallback.
    local extra = self:FrameNumericTextStrings(bar, primary)
    for i = 1, table.getn(extra) do add(extra[i]) end

    return out
end

--[[ A private-server-safe fallback for unnamed/sibling status text.

     The important scoping rule is that this never scans UIParent and never
     scans arbitrary status bars: only the Blizzard Player/Target/ToT/Pet frame
     that BarRole() already proved ECO owns. That keeps OmniBars and every other
     addon out of reach of this cleanup. ]]--
local function looksLikeStatusNumber(value)
    if type(value) ~= "string" then return false end

    local compact = string.gsub(value, "%s", "")
    if compact == "" then return false end

    -- Examples we intentionally match:
    --   3508
    --   60%
    --   5.51k/5.83k
    --   5.51k/5.83k(95%)
    -- Anything containing real words is not bar-number text.
    local rest = string.gsub(compact, "[%d%.,%%/%(%):%+%-kKmM]", "")
    return rest == ""
end

function M:FrameNumericTextStrings(bar, primary)
    local out, seen = {}, {}
    local entry = self:BarRole(bar)
    if not entry then return out end

    local root = getglobal(entry.frame)
    if not root then return out end

    local excluded = {}
    local function exclude(obj)
        if obj then excluded[obj] = true end
    end

    exclude(primary)
    exclude(getglobal(entry.name))

    -- Numeric labels that are not health/power text.
    local excludeNames = {
        "PlayerLevelText", "TargetLevelText", "PetLevelText",
        "TargetofTargetLevelText", "TargetDeadText", "PlayerPVPTimerText",
        "PlayerFrameGroupIndicatorText",
    }
    for i = 1, table.getn(excludeNames) do
        exclude(getglobal(excludeNames[i]))
    end

    if self.syntheticBarText then
        for _, text in pairs(self.syntheticBarText) do exclude(text) end
    end

    local function add(obj)
        --[[ Type first, as above: a field on a client frame may be anything,
             and indexing a function throws rather than skipping. ]]--
        if type(obj) ~= "table" then return end
        if excluded[obj] or seen[obj] then return end
        if not obj.GetText or not obj.SetText then return end
        if obj.GetObjectType and obj:GetObjectType() ~= "FontString" then return end
        if not looksLikeStatusNumber(obj:GetText()) then return end

        seen[obj] = true
        table.insert(out, obj)
    end

    local function walk(frame, depth)
        if not frame or depth > 4 then return end

        if frame.GetRegions then
            local regions = { frame:GetRegions() }
            for i = 1, table.getn(regions) do add(regions[i]) end
        end

        if frame.GetChildren then
            local children = { frame:GetChildren() }
            for i = 1, table.getn(children) do
                walk(children[i], depth + 1)
            end
        end
    end

    walk(root, 0)
    return out
end

function M:SuppressAuxBarTexts(bar, primary)
    if not bar then return 0 end

    self.auxBarTextOriginal = self.auxBarTextOriginal or {}
    self.auxBarTextByBar = self.auxBarTextByBar or {}
    self.auxBarTextByBar[bar] = self.auxBarTextByBar[bar] or {}

    local list = self:AuxBarTextStrings(bar, primary)
    local hidden = 0

    for i = 1, table.getn(list) do
        if self:HideBarText(bar, list[i]) then hidden = hidden + 1 end
    end

    return hidden
end

--[[ One string put away, and what it was doing written down first.

     Pulled out of the sweep above so that a string found some other way -- the
     client's own dead word, below -- is hidden the same way and comes back the
     same way. Restoring is `RestoreAuxBarTexts`, which reads both tables this
     writes, so anything hidden through here is put back when the module stops
     owning the frame and not before. ]]--
function M:HideBarText(bar, text)
    if not bar or type(text) ~= "table" then return false end
    if not text.GetText or not text.SetText then return false end

    self.auxBarTextOriginal = self.auxBarTextOriginal or {}
    self.auxBarTextByBar = self.auxBarTextByBar or {}
    self.auxBarTextByBar[bar] = self.auxBarTextByBar[bar] or {}

    if not self.auxBarTextOriginal[text] then
        local alpha = 1
        if text.GetAlpha then alpha = text:GetAlpha() or 1 end

        self.auxBarTextOriginal[text] = {
            alpha = alpha,
            shown = text.IsShown and text:IsShown() and true or false,
            value = text.GetText and text:GetText() or nil,
        }
    end

    self.auxBarTextByBar[bar][text] = true

    if text.SetText then text:SetText("") end
    if text.SetAlpha then text:SetAlpha(0) end
    if text.Hide then text:Hide() end

    return true
end

-- Cheap per-frame enforcement for strings we have already identified. The
-- expensive part -- discovering unnamed sibling FontStrings -- happens in
-- SuppressAuxBarTexts at 10 Hz. Once known, keeping a handful of text regions
-- hidden every rendered frame prevents the client from flashing them back on
-- between those scans.
function M:ReassertAuxBarTexts()
    if not self.auxBarTextByBar then return end

    for bar, owned in pairs(self.auxBarTextByBar) do
        if self:BarRole(bar) then
            for text in pairs(owned) do
                if text.SetText then text:SetText("") end
                if text.SetAlpha then text:SetAlpha(0) end
                if text.Hide then text:Hide() end
            end
        end
    end
end

function M:RestoreAuxBarTexts(entry)
    if not entry or not self.auxBarTextByBar then return 0 end

    local restored = 0
    local bars = { getglobal(entry.health), getglobal(entry.power) }

    for i = 1, table.getn(bars) do
        local bar = bars[i]
        local owned = bar and self.auxBarTextByBar[bar]

        if owned then
            for text in pairs(owned) do
                local snap = self.auxBarTextOriginal and self.auxBarTextOriginal[text]
                if snap then
                    if text.SetAlpha then text:SetAlpha(snap.alpha or 1) end
                    if text.SetText and snap.value ~= nil then text:SetText(snap.value) end
                    if snap.shown then
                        if text.Show then text:Show() end
                    elseif text.Hide then
                        text:Hide()
                    end

                    self.auxBarTextOriginal[text] = nil
                    restored = restored + 1
                end
            end

            self.auxBarTextByBar[bar] = nil

            -- Let the real client repopulate dynamic values immediately where
            -- possible, instead of waiting for the next health/power event.
            if EquadisOverhaulBlizzStatusText then
                EquadisOverhaulBlizzStatusText(bar)
            end
        end
    end

    return restored
end

function M:RestoreAllAuxBarTexts()
    local total = 0
    for i = 1, table.getn(FRAMES) do
        total = total + self:RestoreAuxBarTexts(FRAMES[i])
    end
    return total
end

function M:HideSyntheticBarText(entry)
    if not self.syntheticBarText or not entry then return end

    local bars = { getglobal(entry.health), getglobal(entry.power) }
    for i = 1, table.getn(bars) do
        local text = bars[i] and self.syntheticBarText[bars[i]]
        if text then
            text:SetText("")
            text:Hide()
        end
        local layer = self.syntheticBarTextLayer and self.syntheticBarTextLayer[bars[i]]
        if layer and layer.Hide then layer:Hide() end
    end
end

function M:HideAllSyntheticBarText()
    if self.syntheticBarText then
        for _, text in pairs(self.syntheticBarText) do
            if text then
                text:SetText("")
                text:Hide()
            end
        end
    end

    if self.syntheticBarTextLayer then
        for _, layer in pairs(self.syntheticBarTextLayer) do
            if layer and layer.Hide then layer:Hide() end
        end
    end
end

--[[ **What colour the numbers are, which is not the colour of the bar.**

     The port had the text matching its bar, which sounds right and is not what
     the original does -- and on a class-coloured bar it makes a warlock's health
     purple text on a purple bar, which is the one arrangement that cannot be
     read.

     The original colours the two by what each one *means*:

     - health ramps red to green by how much is left, so the number and its
       colour say the same thing twice and either one is enough at a glance;
     - resource takes its power type's own colour -- energy pale, rage red, mana
       blue -- which is the same code the client uses on the bar itself.

     The ramp is `OB.Ramp` and the anchors are the health module's, so the number
     on a unit frame and the bar in the HUD agree about what "half" looks like
     rather than being two opinions. ]]--
--[[ `frameId` so "Color The Numbers Too" can be answered per frame like the
     rest of them. Optional: a caller without one gets the shared value, which
     is what every caller outside this module has. ]]--
function M:TextColor(role, value, max, unit, frameId)
    local cfg = self:Config()

    local wants = cfg.colorText
    if frameId then wants = self:FrameSetting(frameId, "colorText") end

    if not wants then return 1, 1, 1 end

    if role == "health" then
        local fraction = 0
        if max and max > 0 then fraction = value / max end

        local health = OB.profile.modules.health
        local color = OB.Ramp(health.lowColor, health.halfColor,
                health.fullColor, fraction)

        return color[1], color[2], color[3]
    end

    --[[ Blizzard's own power colours, by type rather than by class: a druid in
         cat form is on energy and a druid in bear form is on rage, and reading
         the class would give both of them mana blue. ]]--
    local power = 0
    if type(UnitPowerType) == "function" then power = UnitPowerType(unit or "player") or 0 end

    if power == 3 then return 250 / 255, 240 / 255, 200 / 255 end
    if power == 1 then return 250 / 255, 108 / 255, 108 / 255 end

    return 0.6, 0.65, 1
end

--[[ **The text on one bar, written the way the panel asked for.**

     Everything the client's own version does is kept -- the zero text a dead
     unit shows, hiding a bar with no maximum -- because those are not styling,
     they are the frame working. What changes is the format, and that the string
     is *shown*: the CVar deciding whether Blizzard displays these at all is not
     a setting this addon should make somebody go and find. ]]--
--[==[ **The client's own "Dead", by the name the client gives it.**

     `TargetFrame` carries `TargetDeadText`: the client drops "Frame" out of the
     middle rather than appending to the frame's name. Both spellings are asked
     for because a fork may do it either way, and neither is assumed to exist --
     the player, pet and party frames have no such string at all in 1.12, which
     is exactly why this addon draws its own. ]==]
function M:ClientDeadTexts(entry)
    local out = {}
    if not entry or not entry.frame then return out end

    local function add(name)
        local obj = name and getglobal(name)
        if type(obj) == "table" and obj.GetText and obj.SetText then
            table.insert(out, obj)
        end
    end

    add((string.gsub(entry.frame, "Frame$", "")) .. "DeadText")
    add(entry.frame .. "DeadText")

    return out
end

function M:StatusText(bar)
    local entry, role = self:BarRole(bar)

    --[==[ **Not ours -- and "ours" is ownership, not recognition.**

         This asked only whether the bar was one it *knew*, which
         `PlayerFrameHealthBar` is whatever the settings say. So on a frame this
         module had declined to own, it went on writing its own numbers into the
         client's bar: `3.61k/3.61k (100%)` inside a 119-pixel bar the client
         sized for `3610 / 3610`, spilling past the bar and past the art around
         it.

         Reported as the frame not being fixed to the bars. The bars were the
         client's own and were exactly where they belong; what was too big for
         them was text this module had no business writing there.

         Third instance of one fault: a decision about a frame made in more than
         one place, with different gates. `StyleFrame` asks `Owns`; the art asks
         `Owns` through it; this asked something else. The comment below was
         already right about what should happen -- a module that is switched off
         has to look switched off -- and the condition did not implement it. ]==]
    if not entry or not self:Owns(entry) then
        return EquadisOverhaulBlizzStatusText(bar)
    end

    local text = self:BarTextString(bar, true)
    if not text then return false end

    -- Octo/Turtle-style clients can keep their own left/right numbers alive
    -- beside the primary status string. ECO owns the numeric presentation now,
    -- so there must be exactly one number string on an owned bar.
    self:SuppressAuxBarTexts(bar, text)

    local cfg = self:Config()

    -- Blizzard rewrites these strings from TextStatusBar_UpdateTextString after
    -- frame styling. Re-apply the chosen font here, at the same point ECO writes
    -- the value, so Font/Font Size cannot be silently reset a frame later.
    --[[ The pet's two-point drop is in its own migrated size now, not
         subtracted here: a size setting that means two less than it says is
         worse than none. ]]--
    local baseSize = (role == "health")
            and OB.modules.unitframes:FrameSetting(entry.id, "healthSize")
            or OB.modules.unitframes:FrameSetting(entry.id, "powerSize")
    OB.ApplyFont(text, self:TextSize(baseSize), "unitframes")

    local value, max = self:BarValues(entry, role, bar)

    if not max or max <= 0 then
        bar:Hide()
        return false
    end

    bar:Show()

    local mode = (role == "health")
            and OB.modules.unitframes:FrameSetting(entry.id, "healthText")
            or OB.modules.unitframes:FrameSetting(entry.id, "powerText")

    --[[ The pet's numbers, hidden as a whole rather than by setting its format
         to none -- which would be a second place the same decision is made. ]]--
    --[[ **Neither the pet's numbers nor target-of-target's, by default.**

         Vanilla draws no text on either, and the addon this is ported from
         leaves both alone -- it sets their bar textures and the name font
         and nothing else. A 93x45 frame given the player's numbers gets
         `62.90k/62.90k` and `20.20k` overlapping each other, which is what
         was reported.

         Hidden as a whole rather than by setting the format to none, which
         would be a second place the same decision is made. ]]--
    if cfg.hidePetText and entry.id == "pet" then mode = "none" end
    if cfg.hideTotText and entry.id == "targettarget" then mode = "none" end

    if mode == "none" then
        text:SetText("")
        text:Hide()
        return true
    end

--[==[ **"Dead", and nothing else.**

         The client writes "Dead" into its own bar text for a corpse, which is
         better than anything a number could say. This addon then wrote
         "0 / 4500" into its own string beside it, so a dead target carried both
         -- reported as the health text still being there.

         There was already a branch meant to prevent that. It asked
         `value == 0 and bar.zeroText`, and **nothing anywhere ever sets
         `zeroText`** -- it is read here and assigned nowhere in the addon. So
         the condition could not be true and the branch had never run once.

         Asked of the unit instead, which is the thing that actually knows.
         `unitDead` covers ghosts as well: a player running back is not at zero
         health and is not somebody whose health you want a number for.

         **Health only.** A corpse's mana is still a number and the power bar is
         not what anybody is reading -- overwriting it with "Dead" would be two
         words where one was wanted.

         `DEAD` is the client's own string, so it arrives translated. The
         fallback is for a build that does not define it, where an English word
         beats an empty bar. ]==]
    if role == "health" and entry.unit and UnitExists(entry.unit)
            and unitDead(entry.unit) then
        --[==[ **And the client's own dead word put away, because it has one.**

             1.12 gives the target frame a `TargetDeadText` of its own and shows
             it over the portrait for a corpse. This addon writes its own "Dead"
             into the bar, so a dead target carried *two* -- the client's in
             white above the bar and ours in red inside it, a few pixels apart.

             Reported as double dead text, and it is the same fault as the
             health numbers this branch was written for, one layer up: the
             client says something true, and saying it again beside it is not
             more true.

             Ours is the one kept. It is the string this module positions,
             fonts and sizes, and it is the only one the party and pet frames
             have -- deferring to the client's would mean the target reading one
             way and everything else another.

             Through the same bookkeeping as the duplicate numbers, so switching
             the module off puts the client's word back where it was. ]==]
        local words = self:ClientDeadTexts(entry)
        for i = 1, table.getn(words) do self:HideBarText(bar, words[i]) end

        text:SetText(DEAD or "Dead")
        bar.isZero = 1
        text:Show()
        return true
    end

    bar.isZero = nil
    text:SetText(self:BarText(value, max, mode))
    text:SetTextColor(self:TextColor(role, value, max, entry.unit, entry.id))
    text:Show()

    return true
end

--[[ What a bar should read, which is not always what the bar says.

     Two cases where the client is wrong and this addon knows better: a feigning
     hunter reports as dead at zero, and a mob reports a percentage as though it
     were health. Both are corrections to the *value*, so they belong here rather
     than in the formatter -- which then only has to turn numbers into text.

     The bar's own value is the fallback, and for anything without a unit it is
     the only answer there is. ]]--
function M:BarValues(entry, role, bar)
    local cfg = self:Config()

    if not UnitExists(entry.unit) then
        local _, max = bar:GetMinMaxValues()
        return bar:GetValue(), max
    end

    if role ~= "health" then
        return self:PowerOf(entry.unit)
    end

    local value, max = self:HealthOf(entry.unit)

    --[[ **A mob's real health, where it has been worked out.** The client
         answers 100 for max because what it gives is a percentage; if this addon
         knows the real number, the percentage is turned back into it. Falls back
         to the client's answer, so a mob nobody has hit reads exactly as it does
         without any of this. ]]--
    --[[ Same reason: an out-of-range party member reads as not-a-player, and a
         level-one alt whose max really is 100 would then be looked up in the
         mob health table by name. ]]--
    if cfg.mobHealth and not OB.IsPlayerUnit(entry.unit) and max == 100 then
        local real = OB.MobHealthMax(UnitName(entry.unit), UnitLevel(entry.unit))

        if real then
            value = math.floor((value / 100) * real + 0.5)
            max = real
        end
    end

    return value, max
end

--[[ **The player's health bar colour, which the client repaints constantly.**

     Only the player's. The target, pet and party bars are coloured by the
     styling pass and marked `lockColor`, which is how the original keeps the
     client off them; the player's bar has no such flag in 1.12, so it is handled
     here instead. Every other bar falls through to Blizzard's own green. ]]--
--[==[ **Which of this module's frames a bar belongs to, or nothing.**

     Matched on the bar itself rather than on `bar.unit`, because the client
     sets that field and a frame another addon has rebuilt may not carry it. ]==]
function M:EntryForBar(bar)
    if not bar then return nil end

    for i = 1, table.getn(FRAMES) do
        if getglobal(FRAMES[i].health) == bar then return FRAMES[i] end
    end

    return nil
end

function M:ColorUpdate(bar, value, smooth)
    if bar ~= getglobal("PlayerFrameHealthBar") or not self:Owns(FRAMES[1]) then
        --[==[ **The client paints every non-player bar green, and it does so
             from this very function.**

             `HealthBar_OnValueChanged` is the client's, and for anything that
             is not a player it sets (0, 1, 0). It skips a bar carrying
             `lockColor`, which the styling pass sets -- so for as long as that
             flag holds, handing control back here is harmless.

             It does not always hold. The flag is written by `StyleBar`, and
             only when a colour was resolved; `UnitColor` answers nothing for a
             unit that does not exist, and the frame is restored to the client
             whenever this module stops owning it. Any window where the flag is
             off, this fires on the next health tick and repaints the target
             green -- which is the reported bar flashing between green and red,
             red being ours and green arriving a tick later.

             So a bar this module owns is coloured here rather than delegated.
             The flag is reasserted at the same time, because being the last
             writer on this tick is not the same as being the last writer. ]==]
        local entry = self:EntryForBar(bar)

        if entry and self:Owns(entry) then
            local colour = self:UnitColor(entry.unit)

            if colour then
                bar:SetStatusBarColor(colour[1], colour[2], colour[3],
                        colour[4] or 1)
                bar.lockColor = true
                return true
            end
        end

        return EquadisOverhaulBlizzHealthColor(value, smooth)
    end

    local cfg = self:Config()
    local color = cfg.playerColor

    if cfg.classColorHealth then
        local r, g, b = OB.ClassColor(OB.class)
        if r then color = { r, g, b, 1 } end
    end

    bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)

    return true
end

--[[ Both replacements, installed once.

     **Guarded on a global, and the guard is the saved original itself.**

     The replaced function lives in `_G` and outlives the addon namespace, which
     is rebuilt from scratch every load. A flag on `self` resets while the
     wrapper does not, so the second install wraps the first -- and a flag on
     `OB` is worse still: the wrapper survives and the original it delegates to
     does not, so every bar that is *not* ours calls nil.

     Guard and payload are therefore one object, in the one place that lasts as
     long as the thing being guarded. Third time this rule has been learned --
     the Escape menu button and the map label were the first two. ]]--
function M:InstallTextHooks()
    if EquadisOverhaulBlizzStatusText then return false end

    EquadisOverhaulBlizzStatusText = TextStatusBar_UpdateTextString
    EquadisOverhaulBlizzHealthColor = HealthBar_OnValueChanged

    --[[ **Both wrappers reach the module through the global name, never through
         the `OB` upvalue.**

         `core.lua` assigns `EquadisClassicOverhaul = {}` on every load, so the
         upvalue every module file captured points at whichever namespace existed
         when that file ran. The wrapper outlives that -- it is in `_G` -- so a
         wrapper holding the upvalue keeps calling a dead namespace: a module
         reading a profile nobody is editing any more, which looks exactly like
         settings that do nothing. ]]--
    TextStatusBar_UpdateTextString = function(bar)
        --[[ Blizzard calls this both ways: with the bar as an argument from
             elsewhere, and bare from the bar's own script with `this` set. ]]--
        local target = bar or this
        if not target then return end

        return EquadisClassicOverhaul.modules.unitframes:StatusText(target)
    end

    -- Do not replace ShowTextStatusBarText/HideTextStatusBarText globally.
    -- OmniBars and other addons use those helpers too. A global wrapper here
    -- can therefore alter unrelated status bars even though UnitFrames only
    -- owns Player/Target/ToT/Pet. Native white text is suppressed locally by
    -- the unit-frame refresh below instead.

    HealthBar_OnValueChanged = function(value, smooth)
        if not this then return end

        return EquadisClassicOverhaul.modules.unitframes
                :ColorUpdate(this, value, smooth)
    end

    --[[ **The target frame's art has an owner, and until now it was not us.**

         `TargetFrame_CheckClassification` is the client's, and it writes
         `TargetFrameTexture` straight back to Blizzard's elite/rare art. It is
         not a one-off at login: the client calls it every time the target
         changes and again on classification changes, so styling the texture
         from `Apply` alone is a race the module wins only by happening to run
         second. Target a mob, and the frame reverts.

         Every other addon that restyles this frame reached the same
         conclusion independently -- the standalone UnitFrames replaces it,
         DragonflightUI replaces it, ShaguTweaks wraps it. Taking the function
         is the supported way to own the texture; there is no event that fires
         reliably after it.

         The classification suffix still comes from `StyleFrameArt`, so the
         Compact and Dark switches and the shared border tint keep applying and
         this stays a single source of truth for what the frame looks like. ]]--
    EquadisOverhaulBlizzClassification = TargetFrame_CheckClassification

    TargetFrame_CheckClassification = function()
        local m = EquadisClassicOverhaul.modules.unitframes

        --[[ Hand back to the client whenever the frame is not ours -- module
             switched off, or Target Frame unticked. Otherwise turning the
             module off would leave the target frame stuck on whatever texture
             was last set, with nothing left to repaint it. ]]--
        if not m or not m:Owns(FRAMES[2]) then
            if EquadisOverhaulBlizzClassification then
                return EquadisOverhaulBlizzClassification()
            end
            return
        end

        return m:StyleFrameArt(FRAMES[2])
    end

    return true
end

-- ---------------------------------------------------------------------------
-- styling one frame
-- ---------------------------------------------------------------------------

--[[ Whether this frame is ours to touch. Asked per frame rather than once,
     because the switches are per frame and somebody who has turned the pet
     frame off should keep Blizzard's pet frame exactly as it was. ]]--
function M:Owns(entry)
    if not OB.ModuleEnabled("unitframes") then return false end

    -- Party frames are a separate subsystem now. They live under
    -- Party & Raid Frames and are deliberately not owned by UnitFrames; letting
    -- both modules write the same Blizzard objects caused the duplicate numbers,
    -- names and visibility fights seen when entering a raid. Keep PartyEntry for
    -- compatibility with old saved data/tests, but never treat it as ours.
    if entry and string.find(entry.id or "", "^party") then return false end

    return self:Config()[entry.setting] and true or false
end

--[[ **What the unit frames actually measure, as opposed to what they were told
     to measure.**

     Every bar position in this module is a hardcoded offset against the frame
     art -- width 119, `TOPLEFT 106, -22` -- and the border is anchored to the
     bar and pushed out by three or five pixels. On paper the border cannot be
     much bigger than the bar it hugs.

     When it visibly is, something has moved one of them afterwards, and no
     amount of reading this file will say which: a screenshot shows the result,
     not the numbers. So the numbers are printed.

     Reports what is on the frame right now rather than what this module set,
     which is the whole point -- the two being different is the fault. ]]--
local function describe(label, region)
    if not region then
        OB.Raw("   " .. label .. ": missing")
        return
    end

    local width = region.GetWidth and region:GetWidth() or nil
    local height = region.GetHeight and region:GetHeight() or nil

    local line = string.format("   %-22s %sx%s",
            label,
            width and string.format("%.0f", width) or "?",
            height and string.format("%.0f", height) or "?")

    if region.GetNumPoints and region.GetPoint and (region:GetNumPoints() or 0) > 0 then
        local point, relativeTo, relativePoint, x, y = region:GetPoint(1)
        local anchor = relativeTo and relativeTo.GetName and relativeTo:GetName()

        line = line .. string.format("  %s -> %s %s (%.0f, %.0f)",
                tostring(point), tostring(anchor or "?"),
                tostring(relativePoint), x or 0, y or 0)
    end

    OB.Raw(line)
end

--[[ **The art layer, which the geometry says nothing about.**

     Every number above can be right while the frame still looks wrong, because
     a unit frame is bars *inside a picture of a unit frame*. If the picture is
     missing, hidden, or replaced by another addon's, the bars are floating in
     space at coordinates that measure up perfectly -- which is exactly what
     "still misaligned" looks like in a screenshot and exactly what the numbers
     cannot show.

     So: is it there, is it shown, and whose is it. The texture path is the
     interesting part -- a path with another addon's name in it says who is
     drawing this frame, and that has been the answer twice already. ]]--
--[[ **Every probe guarded, because a diagnostic must not take the client down.**

     This asked textures for their vertex colour and their size, and `/eq frames`
     started crashing the game outright -- not a Lua error, a crash. Which of
     the three calls 1.12 dislikes is not worth finding out by bisecting on
     somebody's client: the answer either way is that a command whose entire job
     is to explain a problem must be incapable of causing a worse one.

     So each value is fetched through `pcall` and reported as `?` when it cannot
     be had. A report with a gap in it is still a report; a client that quits is
     not. ]]--
local function probe(region, method)
    if not region or not region[method] then return nil end

    local ok, a, b, c = pcall(region[method], region)
    if not ok then return nil end

    return a, b, c
end

local function describeArt(label, name)
    local region = getglobal(name)

    if not region then
        OB.Raw("   " .. label .. ": missing")
        return
    end

    local shown = probe(region, "IsShown")
    local texture = probe(region, "GetTexture")
    local alpha = probe(region, "GetAlpha")
    --[[ **Not asked for.** `GetVertexColor` arrives in 2.0, and `pcall` cannot
         catch a hard client crash the way it catches a Lua error -- so a call
         this client may not survive is not worth making for a value the addon
         already knows. The tint is reported from the setting that sets it,
         in the header line above. ]]--
    local w = probe(region, "GetWidth")
    local h = probe(region, "GetHeight")

    --[[ Trimmed to the last two path parts: the full path is most of a line and
         the end of it is what identifies whose art this is. ]]--
    local short = texture

    if type(texture) == "string" then
        local _, _, tail = string.find(texture, "([^\\]+\\[^\\]+)$")
        short = tail or texture
    end

    OB.Raw(string.format("   %-22s %s a%s tint %s %sx%s  %s",
            label,
            shown and "shown" or "HIDDEN",
            type(alpha) == "number" and string.format("%.2f", alpha) or "?",
            "-",
            type(w) == "number" and string.format("%.0f", w) or "?",
            type(h) == "number" and string.format("%.0f", h) or "?",
            tostring(short or "no texture")))
end

function M:ReportGeometry()
    local cfg = self:Config()
    local look = OB.Look("unitframes")

    OB.Print("unit frame geometry:", "UnitFrames")

    OB.Raw(string.format("   compact %s, border %s, pad %s, legacy art %s, dark %s",
            tostring(self:Compact()),
            tostring(look.border),
            tostring(OB.borderPads[tonumber(look.border) or 1]),
            tostring(legacyAssetsInstalled()),
            string.format("%.2f", self:DarkAmount() or 0)))

    describe("PlayerFrame", getglobal("PlayerFrame"))
    describe("PlayerHealthBar", getglobal("PlayerFrameHealthBar"))
    describe("PlayerManaBar", getglobal("PlayerFrameManaBar"))
    describe("PlayerBackground", getglobal("PlayerFrameBackground"))

    --[[ The picture the bars sit inside. Bars measuring up perfectly inside art
         that is missing or somebody else's is what "still misaligned" looks
         like, and no amount of geometry says so. ]]--
    describeArt("PlayerArt", "PlayerFrameTexture")
    describeArt("TargetArt", "TargetFrameTexture")
    describeArt("PlayerPortrait", "PlayerPortrait")

    --[[ The smaller frames' art, which the report did not mention and which is
         the one thing worth knowing when they look wrong. Their sizes are the
         client's own, restored from a capture, so a line that disagrees with
         its frame says the capture is what is wrong. ]]--
    describeArt("ToTArt", "TargetofTargetTexture")
    describeArt("PetArt", "PetFrameTexture")

    --[[ The border this module draws, which is the thing being described as
         too big. Looked up rather than created, so asking does not build one. ]]--
    local health = getglobal("PlayerFrameHealthBar")

    if self.barBorders and health and self.barBorders[health] then
        describe("PlayerHealthBorder", self.barBorders[health])
    else
        OB.Raw("   PlayerHealthBorder:    none drawn")
    end

    describe("TargetFrame", getglobal("TargetFrame"))
    describe("TargetHealthBar", getglobal("TargetFrameHealthBar"))

    --[[ **Target of target, which only ever had its portrait positioned.**

         `StyleTargetTargetGeometry` moves the portrait and nothing else -- no
         bar widths, no bar anchors, no name. The pet frame beside it sets all
         of those, and its comment says it includes "the pieces the first ECO
         port omitted", so the omission was noticed once and fixed for one frame
         of the two.

         Whether that is what the player is seeing is a question for the numbers
         rather than for a reading of this file. ]]--
    describe("ToTFrame", getglobal("TargetofTargetFrame"))
    describe("ToTHealthBar", getglobal("TargetofTargetHealthBar"))
    describe("ToTManaBar", getglobal("TargetofTargetManaBar"))
    describe("ToTPortrait", getglobal("TargetofTargetPortrait"))
    describe("ToTName", getglobal("TargetofTargetName"))

    --[[ The stored positions, because a frame that moves back on every reload
         is either not being recorded or not being read -- and those are
         different faults with the same symptom. ]]--
    local saved = cfg.positions or {}
    local count = 0

    for name in pairs(saved) do
        count = count + 1
        OB.Raw(string.format("   saved %-16s (%s, %s)", name,
                tostring(saved[name].x), tostring(saved[name].y)))
    end

    if count == 0 then
        OB.Raw("   saved positions:       none recorded")
    end

    local targetHealth = getglobal("TargetFrameHealthBar")

    if self.barBorders and targetHealth and self.barBorders[targetHealth] then
        describe("TargetHealthBorder", self.barBorders[targetHealth])
    else
        OB.Raw("   TargetHealthBorder:    none drawn")
    end

    return true
end

--[[ **The synthetic bar border is gone, and old ones are cleaned up.**

     This drew a backdrop frame around each status bar from the shared Border
     setting. These frames already carry an ornamental metal surround, so that
     is a second border inside the first -- and it was reported as exactly that.
     The setting is no longer offered (see `styled`), so nothing can ask for it.

     `ReleaseBarBorders` stays, because removing a feature is not the same as
     removing what it left behind: a profile upgraded from a version that drew
     these still has the frames parented to its bars, and they do not go away on
     their own. Called once at bind. ]]--
function M:ReleaseBarBorders()
    if not self.barBorders then return 0 end

    local gone = 0

    for _, frame in pairs(self.barBorders) do
        if frame then
            if frame.SetBackdrop then frame:SetBackdrop(nil) end
            if frame.Hide then frame:Hide() end
            gone = gone + 1
        end
    end

    self.barBorders = nil
    return gone
end

--[[ Kept as the name the rest of the module already calls, now meaning
     "release whatever an older profile left behind" rather than "hide the
     borders this draws" -- because it no longer draws any. ]]--
function M:HideBarBorders()
    return self:ReleaseBarBorders()
end

--[[ **The bar textures, from the shared media list.**

     This is what makes a unit frame look like it belongs beside the HUD and the
     meters rather than beside the client's own art: one texture setting, read
     through `OB.Look`, the same as everything else this addon draws. ]]--
function M:StyleBar(bar, size, x, y, color)
    if not bar then return end

    local look = OB.Look("unitframes")

    if bar.SetStatusBarTexture then
        bar:SetStatusBarTexture(OB.textures[look.texture] or OB.textures[1])
    end

    if color and bar.SetStatusBarColor then
        bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)

        --[[ **`lockColor` is how the client is told to keep off a bar.** Without
             it `UnitFrame_Update` repaints this the moment the unit changes, and
             the colour set here lasts until the next target. The player's bar
             has no such flag in 1.12, which is why that one is handled by
             replacing `HealthBar_OnValueChanged` instead. ]]--
        bar.lockColor = true
    end

    local text = self:BarTextString(bar, true)

    if text then
        -- Hide fork-specific split status strings immediately on a styling pass
        -- as well as during value updates, so `/reload` cannot leave one frame
        -- of the client's old numbers underneath the new centred format.
        self:SuppressAuxBarTexts(bar, text)

        OB.ApplyFont(text, self:TextSize(size), "unitframes")

        --[[ **Anchored every pass, not only when the offset is non-zero.**

             Setting it conditionally leaves the text wherever it was last put
             once somebody returns the slider to zero: a nudge that works going
             out and not coming back, which is worse than one that never worked.

             To its own bar rather than to the frame, which is the original's
             anchor and keeps the player and target texts level automatically --
             their bars are the same size at the same height, and a bar that
             grows carries its text with it. ]]--
        if text.SetPoint then
            text:ClearAllPoints()
            text:SetPoint("CENTER", bar, "CENTER", x, y)
        end

        --[[ **As wide as the bar it sits on.**

             The client's own font strings carry a width from XML, sized for the
             client's own format -- and a string longer than that is cut off with
             an ellipsis rather than overflowing. The default format here is the
             longest one offered: `3.3k/3.3k (100%)`. It arrived on screen as
             `3.3k/3.3k...`, which reads as the addon failing to work out a
             number it had in fact worked out correctly.

             Widened to the bar rather than unset, because a font string with no
             width at all will happily run past both ends of the bar it belongs
             to. Guarded on a real width: during the first pass a bar can report
             zero, and a zero-width string shows nothing at all. ]]--
        local width = bar.GetWidth and bar:GetWidth()
        local entry = self:BarRole(bar)

        -- The small pet/ToT bars are only about 46 px wide. That is narrower
        -- than the default `current/max (percent)` string, so using the bar's
        -- width clips a correct value into an ellipsis. Give those strings the
        -- width of their frame instead; the anchor still stays on the bar.
        if entry and (entry.id == "pet" or entry.id == "targettarget") then
            local frame = getglobal(entry.frame)
            local frameWidth = frame and frame.GetWidth and frame:GetWidth()
            if frameWidth and frameWidth > (width or 0) then
                width = frameWidth - 6
            end
        end

        if text.SetWidth and width and width > 0 then
            text:SetWidth(width)
            if text.SetJustifyH then text:SetJustifyH("CENTER") end
        end

    end

    --[[ No synthetic border here any more: these frames carry real ornamental
         art and a backdrop inside it was a second border. ]]--
end

--[[ **A class icon where the portrait was.**

     The art is the client's own -- see PORTRAIT_ART -- so nothing is copied and
     nothing has to be kept in step with a patch.

     Only for players. An NPC has no class worth drawing, and a wolf with a
     warrior's crest on it is worse than the model. ]]--
function M:RememberObject(name)
    self.original = self.original or {}
    if self.original[name] ~= nil then return end

    local obj = getglobal(name)
    if not obj then
        self.original[name] = false
        return
    end

    local snap = { object = obj }
    if obj.GetWidth then snap.width = obj:GetWidth() end
    if obj.GetHeight then snap.height = obj:GetHeight() end
    if obj.GetPoint then snap.point = { obj:GetPoint(1) } end
    if obj.IsShown then snap.shown = obj:IsShown() and true or false end
    if obj.GetTexture then
        snap.hasTexture = true
        snap.texture = obj:GetTexture()
    end
    if obj.GetTexCoord then snap.texcoord = { obj:GetTexCoord() } end
    if obj.GetVertexColor then snap.vertex = { obj:GetVertexColor() } end
    if obj.GetFont then snap.font = { obj:GetFont() } end
    if obj.GetTextColor then snap.textColor = { obj:GetTextColor() } end
    if obj.GetStatusBarColor then snap.barColor = { obj:GetStatusBarColor() } end
    if obj.GetStatusBarTexture then
        local tex = obj:GetStatusBarTexture()
        if type(tex) == "string" then
            snap.barTexture = tex
        elseif tex and tex.GetTexture then
            snap.barTexture = tex:GetTexture()
        end
    end
    snap.lockColor = obj.lockColor
    snap.capNumericDisplay = obj.capNumericDisplay
    self.original[name] = snap
end

function M:RememberOriginals()
    if self.originalCaptured then return end
    self.originalCaptured = true

    --[[ The art regions first, before any styling has had a chance to change
         one: these are the client's own sizes and this is the last moment they
         can still be read. ]]--
    for i = 1, table.getn(FRAMES) do self:RememberArt(FRAMES[i]) end

    local names = {
        "PlayerFrame", "PlayerFrameTexture", "PlayerFrameBackground",
        "PlayerFrameHealthBar", "PlayerFrameManaBar", "PlayerFrameHealthBarText",
        "PlayerFrameManaBarText", "PlayerName", "PlayerPortrait", "PlayerStatusTexture",
        "TargetFrame", "TargetFrameTexture", "TargetFrameBackground",
        "TargetFrameHealthBar", "TargetFrameManaBar", "TargetFrameNameBackground",
        "TargetDeadText", "TargetName", "TargetPortrait",
        "TargetofTargetFrame", "TargetofTargetTexture", "TargetofTargetPortrait",
        "TargetofTargetHealthBar", "TargetofTargetManaBar", "TargetofTargetName",
        "PetFrame", "PetFrameTexture", "PetPortrait", "PetAttackModeTexture",
        "PetFrameHealthBar", "PetFrameManaBar", "PetFrameHealthBarText",
        "PetFrameManaBarText", "PetName", "PetFrameHappiness",
    }

    for i = 1, table.getn(names) do self:RememberObject(names[i]) end
end

function M:RestoreObject(name, geometryOnly)
    if not self.original then return false end
    local snap = self.original[name]
    if not snap or snap == false then return false end
    local obj = snap.object or getglobal(name)
    if not obj then return false end

    if snap.width and obj.SetWidth then obj:SetWidth(snap.width) end
    if snap.height and obj.SetHeight then obj:SetHeight(snap.height) end
    if snap.point and obj.SetPoint then
        obj:ClearAllPoints()
        obj:SetPoint(unpack(snap.point))
    end

    if not geometryOnly then
        -- Restore nil too. PlayerStatusTexture is deliberately cleared by the
        -- glow option, and a snapshot whose original texture was nil must be able
        -- to clear a texture ECO added later.
        if obj.SetTexture and snap.hasTexture then obj:SetTexture(snap.texture) end
        if obj.SetTexCoord and snap.texcoord and table.getn(snap.texcoord) > 0 then
            obj:SetTexCoord(unpack(snap.texcoord))
        end
        if obj.SetVertexColor and snap.vertex and table.getn(snap.vertex) >= 3 then
            obj:SetVertexColor(unpack(snap.vertex))
        end
        if obj.SetFont and snap.font and snap.font[1] then obj:SetFont(unpack(snap.font)) end
        if obj.SetTextColor and snap.textColor then obj:SetTextColor(unpack(snap.textColor)) end
        if obj.SetStatusBarTexture and snap.barTexture then obj:SetStatusBarTexture(snap.barTexture) end
        if obj.SetStatusBarColor and snap.barColor then obj:SetStatusBarColor(unpack(snap.barColor)) end
        if snap.shown ~= nil then
            if snap.shown and obj.Show then obj:Show() elseif obj.Hide then obj:Hide() end
        end
        obj.lockColor = snap.lockColor
        obj.capNumericDisplay = snap.capNumericDisplay
    end
    return true
end

function M:RestorePortrait(entry)
    local portrait = getglobal(entry.portrait)
    if portrait and portrait.SetTexCoord then portrait:SetTexCoord(0, 1, 0, 1) end
    if portrait and type(SetPortraitTexture) == "function" and UnitExists(entry.unit) then
        SetPortraitTexture(portrait, entry.unit)
    end
end

function M:RestoreOriginals()
    self:HideBarBorders()
    if not self.original then return false end
    for name, snap in pairs(self.original) do
        if snap and snap ~= false then self:RestoreObject(name, false) end
    end

    self:RestoreAllAuxBarTexts()

    for i = 1, table.getn(FRAMES) do self:RestorePortrait(FRAMES[i]) end
    return true
end

-- Restore one takeover switch immediately. The first port only stopped future
-- styling, so turning Pet/Target/etc. off left whatever ECO had already changed
-- sitting on Blizzard's frame until a reload.
function M:RestoreEntry(entry)
    if not entry then return false end
    local names = { entry.frame, entry.health, entry.power, entry.name, entry.portrait }

    if entry.id == "player" then
        names = { "PlayerFrame", "PlayerFrameTexture", "PlayerFrameBackground",
            "PlayerFrameHealthBar", "PlayerFrameManaBar", "PlayerFrameHealthBarText",
            "PlayerFrameManaBarText", "PlayerName", "PlayerPortrait", "PlayerStatusTexture" }
    elseif entry.id == "target" then
        names = { "TargetFrame", "TargetFrameTexture", "TargetFrameBackground",
            "TargetFrameHealthBar", "TargetFrameManaBar", "TargetFrameNameBackground",
            "TargetDeadText", "TargetName", "TargetPortrait" }
    elseif entry.id == "targettarget" then
        names = { "TargetofTargetFrame", "TargetofTargetTexture",
            "TargetofTargetPortrait", "TargetofTargetHealthBar",
            "TargetofTargetManaBar", "TargetofTargetName" }
    elseif entry.id == "pet" then
        names = { "PetFrame", "PetFrameTexture", "PetPortrait",
            "PetAttackModeTexture", "PetFrameHealthBar", "PetFrameManaBar",
            "PetFrameHealthBarText", "PetFrameManaBarText", "PetName",
            "PetFrameHappiness" }
    elseif string.find(entry.id or "", "^party") then
        local n = string.gsub(entry.id, "party", "")
        names = { "PartyMemberFrame" .. n, "PartyMemberFrame" .. n .. "Texture",
            "PartyMemberFrame" .. n .. "Portrait", "PartyMemberFrame" .. n .. "HealthBar",
            "PartyMemberFrame" .. n .. "ManaBar", "PartyMemberFrame" .. n .. "HealthBarText",
            "PartyMemberFrame" .. n .. "ManaBarText", "PartyMemberFrame" .. n .. "Name" }
    end

    for i = 1, table.getn(names) do self:RestoreObject(names[i], false) end
    self:RestoreAuxBarTexts(entry)
    self:HideSyntheticBarText(entry)
    --[[ Synthetic number strings exist only when the client gave a bar no text
         region. They are hidden as soon as that frame is handed back. ]]--

    self:RestorePortrait(entry)
    return true
end

--[[ **The circular class atlas, which this addon shipped and never used.**

     A unit frame's portrait opening is round. `UI-CharacterCreate-Classes` is a
     square atlas, so an icon cut from it has corners and the corners sit
     outside the opening -- the square leak this was reported as. Shrinking the
     icon does not fix that; it makes a smaller square.

     `UI-CLASSES-CIRCLES` is the round, transparent atlas the donor uses, and
     `LEGACY_PORTRAITS` above is already its coordinate table, copied exactly
     from it. Both were here the whole time; this reached for the square one.

     Bundled into this addon's own `textures/` rather than read from the donor's
     folder, so a portrait does not break when somebody uninstalls the addon
     this one replaces. ]]--
local CIRCLE_PORTRAIT_ART = "Interface\\AddOns\\EquadisClassicOverhaul\\textures\\UI-CLASSES-CIRCLES"

function M:StylePortrait(entry)
    local portrait = getglobal(entry.portrait)
    if not portrait or not portrait.SetTexture then return false end
    local cfg = self:Config()

    --[[ A class icon is a *player's* class. An NPC has one and it means
         nothing, a pet has none, and either way the real portrait belongs
         there -- which is what stops an icon staying behind when the target
         changes from a player to a mob. ]]--
    --[[ `OB.IsPlayerUnit` rather than `UnitIsPlayer`: out of range the client
         answers no about a party member, and the class icon was dropped in
         favour of the 3D portrait -- which is the one thing it certainly
         cannot draw for a unit it has no object for. The icon is precisely
         what still works at distance, so it is what should survive. ]]--
    if not cfg.classPortrait or not UnitExists(entry.unit)
            or not OB.IsPlayerUnit(entry.unit) then
        self:RestorePortrait(entry)
        return false
    end

    --[[ Through the same helper as the gate above, so the icon does not depend
         on which source can answer for the unit at this distance. ]]--
    local class = OB.UnitClassToken(entry.unit)
    local coords = class and LEGACY_PORTRAITS[class]

    --[[ An unknown class gets its real portrait rather than a wrong icon: a
         server with a class of its own would otherwise show a corner of
         somebody else's. ]]--
    if not coords then
        self:RestorePortrait(entry)
        return false
    end

    portrait:SetTexture(CIRCLE_PORTRAIT_ART)
    portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])

    return true
end

local function targetSuffix(classification)
    if classification == "worldboss" or classification == "elite" then return "-Elite" end
    if classification == "rareelite" then return "-Rare-Elite" end
    if classification == "rare" then return "-Rare" end
    return ""
end

--[[ **Four pieces of art, not two.**

     The addon this art comes from picks its frame texture from two switches --
     compact and dark -- giving `UI`, `darkUI`, `compactUI` and `DarkCompactUI`.
     This port only ever asked for two of them, and got "dark" by tinting the
     light art towards grey instead.

     Those are not the same thing, and the difference is visible. The dark files
     are drawn dark: their edges and highlights are made for it. Multiplying the
     gold art down to sixty percent grey washes the frame out until the bars
     look like they are floating on nothing -- which is what it was reported as.

     Worth noting that the source addon has the tinting approach in its own file,
     commented out, with the file swap kept. It tried this and chose the other
     way. ]]--
--[[ **Dark mode tints; it does not swap the art. Reverted, with the evidence.**

     This briefly picked `darkUI-` and `DarkCompactUI-` files, on the reasoning
     that the addon whose art this is swaps files rather than tinting -- which
     its source does, and which is true on *its* install.

     It is not true on this one. The files here are not light and dark pairs of
     one design, they are different designs:

         UI-TargetingFrame.blp        44884 bytes  b1e7994c...
         darkUI-TargetingFrame.blp    88552 bytes  27730d42...
         newUI-TargetingFrame.blp     88552 bytes  27730d42...

     `darkUI` is byte-identical to `newUI`. Asking for dark art hands back the
     *new* frame -- a wider layout drawn for different bars -- and the classic
     bars then sit inside a frame that carries on past them. Which is exactly
     what it looked like, and exactly what was reported: a border too big.

     So the art follows compact alone, and dark mode goes back to being a tint
     over whichever art that picks. A tint is the thing that cannot be wrong
     about a layout, because it does not change one. ]]--
function M:UFIFramePrefix()
    if self:Compact() then return "compactUI" end
    return "UI"
end

--[[ **The art region, put back to the size the frame was drawn for.**

     `UI-TargetingFrame` is a 256x128 file, and the client does not display it
     at 256x128. Blizzard's own XML sizes the texture to the frame -- 232x100 --
     and crops the source with tex coords: 232/256 is 0.90625 and 100/128 is
     0.78125, which is where those numbers come from. The player's is mirrored,
     so its left and right run 1.0 to 0.09375 -- and the target's run the same
     window forward, 0.09375 to 1.0, because it is the same artwork unmirrored.

     **Not 0 to 0.90625**, which was tried and is a different 232 pixels: the
     art lives in the right 232 of the 256, so a window starting at zero lands
     partly on the empty margin and draws a thin outline where the ornate border
     should be.

     Swapping the texture without restoring that leaves the region at the file's
     own size. The art is then stretched vertically by 128/100 -- 1.28 -- which
     pushes the bottom of the border down past the bars and leaves an empty
     compartment under the mana bar. That is the "border too big" that was
     reported over and over, and it was visible the whole time in `/eq frames`
     as `PlayerArt 256x128` against `PlayerFrame 232x100`. It was read as normal
     and dismissed, four times.

     Set explicitly rather than trusted, because whatever the client, another
     addon or an earlier version of this one left behind is what a bare
     `SetTexture` inherits. ]]--
local FRAME_ART_W, FRAME_ART_H = 232, 100

local function normaliseFrameArt(art, frame, mirrored)
    if not art or not frame or not art.SetTexCoord then return false end

    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    art:SetWidth(FRAME_ART_W)
    art:SetHeight(FRAME_ART_H)

    if mirrored then
        art:SetTexCoord(1.0, 0.09375, 0, 0.78125)
    else
        art:SetTexCoord(0.09375, 1.0, 0, 0.78125)
    end

    return true
end

--[[ **The smaller frames get the same treatment, from their own numbers.**

     Pet, target of target and the party have art regions of their own -- 93x45
     for target of target, smaller again for the party -- and this addon does
     not know any of them. Writing four more pairs of numbers here would be the
     player frame's bug in four new places, and wrong on any client that ships
     different art.

     So their own values are read once, before anything here has touched them,
     and put back afterwards. The client's own numbers are the correct ones by
     definition, and a capture taken before the first styling is the only place
     they can still be read. ]]--
function M:RememberArt(entry)
    local art = getglobal(entry.art or ((entry.frame or "") .. "Texture"))
    if not art or not art.GetWidth then return false end

    self.artHome = self.artHome or {}
    local key = entry.art or entry.frame

    --[[ Once. A second capture would record whatever the last pass left, which
         is the state being corrected rather than the one to return to. ]]--
    if self.artHome[key] then return false end

    local home = { width = art:GetWidth(), height = art:GetHeight() }

    if art.GetTexCoord then
        local ok, a, b, c, d = pcall(art.GetTexCoord, art)
        if ok and type(a) == "number" then home.coords = { a, b, c, d } end
    end

    self.artHome[key] = home
    return true
end

--[[ `keepCoords` is the pet's, and only the pet's. It mirrors a smaller client
     texture on purpose -- see StylePetGeometry -- so putting the captured crop
     back over it would undo styling that is doing its job. Every other frame
     wants its crop restored along with its size: a region at the right size
     showing the wrong part of the sheet is the fault the target frame had. ]]--
function M:RestoreArtRegion(entry, keepCoords)
    local art = getglobal(entry.art or ((entry.frame or "") .. "Texture"))
    if not art or not art.SetWidth then return false end

    local home = self.artHome and self.artHome[entry.art or entry.frame]
    if not home then return false end

    if home.width and home.width > 0 then art:SetWidth(home.width) end
    if home.height and home.height > 0 then art:SetHeight(home.height) end

    if not keepCoords and home.coords and art.SetTexCoord then
        art:SetTexCoord(home.coords[1], home.coords[2],
                home.coords[3], home.coords[4])
    end

    return true
end

--[==[ **Art and geometry are one decision, and this is where it is made.**

     They were two. `StyleFrameArt` branched on classic *and* compact -- three
     outcomes -- while the geometry functions branched on classic alone. So one
     combination, classic art with Compact on, painted the small stock frame and
     then applied the client's full-size bar layout: a small frame with bars
     running past it, which is what "the bars are not aligned with the frame
     overlay" has been every time it has come back.

     Every previous fix was to one side of that pair. The pair is the fault. Two
     conditionals over the same switches, written in two places, will disagree
     the moment a third switch or a fourth frame arrives -- and the disagreement
     is silent, because each side is individually reasonable.

     So the choice is made once and named. `StyleFrameArt` asks which art;
     the geometry asks which layout; neither decides. A combination that has no
     matching layout cannot be selected, because there is one list of outcomes
     rather than two sets of branches that happen to line up.

     **`classicSmall` is deliberately absent.** The client has no compact *player*
     frame and no bar layout drawn for one, so the small stock texture had
     nothing to be aligned against -- it was a guess that made Compact look
     different rather than look right. With classic art, Compact is a donor-art
     feature that does not apply. ]==]
function M:FrameArtChoice()
    if not self:UseClassicFrameArt() then
        if self:Compact() then return "donorCompact" end
        return "donorFull"
    end

    return "classicFull"
end

--[[ The layout each choice was drawn for. `RestoreObject` puts the client's own
     back; the donor's numbers are applied only under the donor's art. ]]--
function M:FrameGeometryMode()
    local choice = self:FrameArtChoice()
    if choice == "classicFull" then return "client" end
    if choice == "donorCompact" then return "compact" end
    return "full"
end

--[==[ **What the frame is actually wearing, asked rather than reasoned about.**

     "The bars are not aligned with the frame overlay" has been diagnosed from a
     screenshot four times and been wrong four times. This file's own note says
     it: *every diagnosis made from a screenshot was wrong*, and the answers came
     from reading the other implementation and comparing.

     There is nothing left here to read that has not been read. What is missing
     is the state on the machine where it happens -- which switches are on, which
     texture was actually set, and where the bars actually are. So it is printed
     rather than guessed at, the way `rangedebug` settled a question that three
     rounds of reasoning could not.

     Prints the pair this alignment depends on side by side, because the fault
     every previous time has been the two disagreeing rather than either one
     being wrong on its own. ]==]
--[==[ **The bar, asked to name whoever writes it.**

     Wrapped once and left wrapped for the session. Every write is compared
     against what this module last intended; anything else is recorded with the
     stack that produced it.

     `debugstack` is the only tool on this client that can answer "who called
     this", and the question has now survived five rounds of reading the code
     that should have been the answer. ]==]
function M:WatchPlayerGeometry()
    if self.geometryWatch then return false end

    local bar = getglobal("PlayerFrameHealthBar")
    if not bar or not bar.SetHeight or not bar.SetPoint then return false end

    self.geometryWatch = true

    local realHeight, realPoint = bar.SetHeight, bar.SetPoint

    local function record(what)
        local wanted = M.lastGeometry
        if not wanted then return end

        M.lastForeignWrite = {
            what = what,
            at = GetTime and GetTime() or 0,
            stack = type(debugstack) == "function" and debugstack(2, 4, 0)
                    or "debugstack unavailable",
        }
    end

    bar.SetHeight = function(this_, h)
        local wanted = M.lastGeometry
        if wanted and wanted.height and h and math.abs(h - wanted.height) > 0.5 then
            record("SetHeight(" .. tostring(h) .. ")")
        end
        return realHeight(this_, h)
    end

    bar.SetPoint = function(this_, point, rel, relPoint, x, y)
        local wanted = M.lastGeometry
        if wanted and wanted.y and y and math.abs(y - wanted.y) > 0.5 then
            record("SetPoint(" .. tostring(point) .. ", " .. tostring(y) .. ")")
        end
        return realPoint(this_, point, rel, relPoint, x, y)
    end

    return true
end

function M:DebugFrameLayout()
    local cfg = self:Config()
    local function say(text) OB.Print(text, "Frames") end

    --[==[ **Ownership first, because everything below is conditional on it.**

         The first dump said `art choice: donorFull` on a frame this module was
         not touching at all -- a statement of intent read as a statement of
         fact, which is the exact shape of the four wrong diagnoses this command
         exists to end. What it chooses is worth nothing until it owns the
         frame. ]==]
    --[==[ **Is this module actually live?**

         Everything else in this dump is conditional on it and none of it says
         so. `OnBind` is called through a `pcall`: if it throws, the module is
         never added to `OB.features`, so it gets **no events, no tick and no
         restyle when a setting changes** -- and `HideFeature` puts the client's
         own frame back, which reads exactly like something overwriting our
         geometry.

         That shape explains a dump where the module owns the frame, intends
         donor art, wrote the right numbers once at load, and has done nothing
         since -- and it is the only shape that also explains a settings page
         that does nothing at all.

         `bindFault` is the error text `safeModuleCall` keeps when that happens.
         It has been sitting there unread the whole time. ]==]
    local live = OB.features and OB.features.unitframes and true or false
    local ticking = false

    for i = 1, table.getn(OB.tickables or {}) do
        if OB.tickables[i] == self then ticking = true end
    end

    say("bound: " .. tostring(live) .. "   ticking: " .. tostring(ticking)
            .. "   tickly: " .. tostring(self.tickly and true or false))

    if self.bindFault then
        say("|cffff7777bind failed:|r " .. tostring(self.bindFault))
    elseif not live then
        say("|cffff7777not in OB.features -- it is not receiving events or"
                .. " settings changes|r")
    end

    local owns = self:Owns(FRAMES[1])
    say("module enabled: " .. tostring(OB.ModuleEnabled("unitframes") and true or false)
            .. "   replacePlayer: " .. tostring(cfg.replacePlayer and true or false)
            .. "   owns player: " .. tostring(owns and true or false))

    if not owns then
        say("|cffff7777not styling this frame -- everything below is the client's own|r")
    end

    say("art choice: " .. tostring(self:FrameArtChoice())
            .. "   geometry: " .. tostring(self:FrameGeometryMode())
            .. (owns and "" or "   (intended, not applied)"))
    say("frameMode=" .. tostring(self:FrameMode())
            .. "  compact=" .. tostring(self:Compact())
            .. "  darkMode=" .. tostring(cfg.darkMode and true or false)
            .. "  prefix=" .. tostring(self:UFIFramePrefix()))

    local frame = getglobal("PlayerFrame")
    local art = getglobal("PlayerFrameTexture")
    local health = getglobal("PlayerFrameHealthBar")
    local power = getglobal("PlayerFrameManaBar")

    if art and art.GetTexture then
        say("art texture: " .. tostring(art:GetTexture()))
    end

    --[==[ The art *region's* own size, not the file's. A 256x128 file drawn into
         a region of the wrong size is the one failure that looks exactly like
         bars of the wrong size, and the two are told apart only here. ]==]
    if art and art.GetWidth then
        say(string.format("art region: %.1f x %.1f", art:GetWidth() or -1,
                art:GetHeight() or -1))
    end

    if frame and frame.GetWidth then
        say(string.format("frame: %.1f x %.1f  scale %.3f  effective %.3f",
                frame:GetWidth() or -1, frame:GetHeight() or -1,
                (frame.GetScale and frame:GetScale()) or -1,
                (frame.GetEffectiveScale and frame:GetEffectiveScale()) or -1))
    end

    local function bar(name, b)
        if not b or not b.GetWidth then return end

        local point, _, relPoint, x, y
        if b.GetNumPoints and (b:GetNumPoints() or 0) > 0 then
            point, _, relPoint, x, y = b:GetPoint(1)
        end

        say(string.format("%s: %.1f x %.1f  %s->%s (%.1f, %.1f)  scale %.3f",
                name, b:GetWidth() or -1, b:GetHeight() or -1,
                tostring(point), tostring(relPoint), x or 0, y or 0,
                (b.GetScale and b:GetScale()) or -1))
    end

    bar("health", health)
    bar("power", power)

    --[==[ **Who wrote it last, named rather than reasoned about.**

         Five passes have ended at "something overwrote it". Nothing left in this
         file says what: ECO's only two restore paths are both gated off, no
         other addon in the install touches these bars, and the client's own
         `PlayerFrame.lua` does not set their geometry.

         So the bar is asked to say who. `SetHeight` and `SetPoint` are wrapped
         and any write that is not the one this module intended is recorded with
         `debugstack`, which is the one thing that can answer a question about a
         caller nobody can find by reading.

         Armed on the first `/eq framedebug` and reported on the next, so it
         costs nothing until somebody is looking. ]==]
    self:WatchPlayerGeometry()

    local foreign = self.lastForeignWrite

    if foreign then
        say("|cffff7777overwritten by:|r " .. tostring(foreign.what)
                .. string.format("  %.1fs ago", (GetTime and GetTime() or 0) - (foreign.at or 0)))

        --[[ Printed whole rather than split: a pattern for "not a newline"
             is one escape away from an unfinished string, and the stack is
             short enough to read as it comes. ]]--
        say("   " .. tostring(foreign.stack))
    elseif self.geometryWatch then
        say("watch armed -- run this again after the frame goes wrong")
    end

    --[==[ **What this module last wrote, against what is there now.**

         If they differ, something overwrote it after we did, and no amount of
         reading this file will say what -- which is the position five passes
         have ended in. If they match, the module never wrote at all and the
         question is why it did not run. ]==]
    local wrote = self.lastGeometry

    if not wrote then
        say("|cffff7777geometry has never been written -- StylePlayerGeometry has"
                .. " not run|r")
    else
        say(string.format("last wrote: height %.1f  y %.1f   %.1fs ago",
                wrote.height or -1, wrote.y or -1,
                (GetTime and GetTime() or 0) - (wrote.at or 0)))

        if health and health.GetHeight
                and math.abs((health:GetHeight() or 0) - (wrote.height or 0)) > 0.5 then
            say("|cffff7777what we wrote is not what is there -- something"
                    .. " overwrote it after us|r")
        end
    end

    --[==[ **And whether the client has its own opinion about this frame.**

         `SetUserPlaced(true)` hands the position to the client, which restores
         it from `layout-cache.txt` after this addon has placed it. That is what
         "still misaligned" turned out to be once already, after four wrong
         answers about geometry that was correct the whole time. ]==]
    if frame and frame.IsUserPlaced then
        say("user placed: " .. tostring(frame:IsUserPlaced() and true or false))
    end

    return true
end

function M:StyleFrameArt(entry)
    local cfg = self:Config()
    --[[ One tint, over whatever art compact picked. Dark mode does not choose
         a different file -- see UFIFramePrefix for why that was tried and
         reverted. ]]--
    local shade = self:DarkShade()
    local artShade = shade

    local art

    if entry.id == "player" then
        art = getglobal(entry.art)
        if art and art.SetTexture then
            --[[ Through the shared choice. The compact stock texture that used
                 to live here had no bar layout to go with it, which is the
                 misalignment this pair now exists to make impossible. ]]--
            if self:FrameArtChoice() ~= "classicFull" then
                art:SetTexture(legacyRoot() .. "Textures\\" .. self:UFIFramePrefix() .. "-TargetingFrame")
            else
                art:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame")
            end
            art:SetVertexColor(artShade, artShade, artShade)

            --[[ The region itself, not only what is drawn in it. ]]--
            normaliseFrameArt(art, getglobal(entry.frame), entry.id == "player")
        end
        return true
    end

    if entry.id == "target" then
        art = getglobal(entry.art)
        if art and art.SetTexture then
            local classification = type(UnitClassification) == "function"
                    and UnitClassification("target") or nil
            local suffix = targetSuffix(classification)
            if not self:UseClassicFrameArt() then
                art:SetTexture(legacyRoot() .. "Textures\\" .. self:UFIFramePrefix()
                        .. "-TargetingFrame" .. suffix)
            --[==[ **Unreachable on purpose, and kept as the record of why.**

                 This selected the stock *small* frame when classic art met
                 Compact. There is no bar layout drawn for that texture -- the
                 geometry below restores the client's full-size one -- so the
                 pair could never agree, and the result was bars running past a
                 frame too small for them. That is the misalignment, every time
                 it has come back.

                 `FrameArtChoice` now has three outcomes and no fourth to fall
                 into: with classic art, Compact is a donor-art feature that does
                 not apply. The branch stays so the reasoning below it is not
                 lost -- a rare border really does outrank compactness, and if
                 the small frame ever gains a layout this is the shape it
                 takes. ]==]
            elseif false then
                --[[ **A rare or elite border outranks compactness.**

                     The stock small frame has no classification variants,
                     so asking for a suffixed one would request a texture
                     the client does not have and draw nothing. This branch
                     therefore dropped the suffix -- and a rare mob got a
                     plain border, which is how it was reported.

                     A rare border says what you are fighting; the smaller
                     frame is a preference about how it looks. So a
                     classified target gets the full stock frame that has
                     the border, and everything else stays compact.

                     Only classic art reaches here: the bundled art has a
                     compact variant for every classification. ]]--
                if suffix ~= "" then
                    art:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame" .. suffix)
                else
                    art:SetTexture("Interface\\TargetingFrame\\UI-SmallTargetingFrame")
                end
            else
                art:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame" .. suffix)
            end
            art:SetVertexColor(artShade, artShade, artShade)

            --[[ The region itself, not only what is drawn in it. ]]--
            normaliseFrameArt(art, getglobal(entry.frame), entry.id == "player")
        end
        return true
    end

    --[[ UFI tints the smaller Blizzard frames rather than replacing their art.
         Named from the entry rather than assembled from the frame's name: the
         old suffix guess produced `TargetofTargetFrameTexture`, which is not a
         thing, so target-of-target was never tinted at all. Party frames have
         no `art` of their own and keep the generated name, which is right for
         them -- they really are four of the same thing. ]]--
    art = getglobal(entry.art or (entry.frame .. "Texture"))

    -- Target-of-target's border is the artwork texture itself. A previous pass
    -- could leave that region with no texture/hidden, and merely restoring its
    -- geometry does not put the border back. Reassert the stock 1.12 texture
    -- while ECO owns this frame so the border cannot disappear after a reload
    -- or after another addon touches the region. The parent frame still controls
    -- visibility, so showing the region here does not make ToT appear when no
    -- target-of-target exists.
    if entry.id == "targettarget" and art then
        if art.SetTexture then
            art:SetTexture("Interface\\TargetingFrame\\UI-TargetofTargetFrame")
        end
        if art.SetAlpha then art:SetAlpha(1) end
        if art.Show then art:Show() end
    end

    if art and art.SetVertexColor then art:SetVertexColor(shade, shade, shade) end

    --[[ And its region put back to the client's own, which is the same fault
         the player frame had: a texture left at whatever size somebody else
         left it. Restored from the capture rather than from numbers written
         here, because these frames' numbers are not known here. ]]--
    --[[ The pet keeps the crop it sets on purpose; everything else gets the
         client's back. ]]--
    self:RestoreArtRegion(entry, entry.id == "pet")
    return true
end

function M:StylePlayerGeometry()
    --[[ **Classic art keeps the client's bar layout.**

         The client's frame art has a divider drawn into it where its own
         health bar ends -- about twelve pixels down. The donor's art has
         no divider there because its health bar is twenty-nine.

         Putting the donor's tall bar inside the client's art therefore draws
         a line straight through the middle of the health bar, which is what
         was reported. Art and geometry are one decision, not two: ask for
         classic art and you get the layout it was drawn for. ]]--
    if self:FrameGeometryMode() == "client" then
        self:RestoreObject("PlayerFrameHealthBar", true)
        self:RestoreObject("PlayerFrameManaBar", true)
        self:RestoreObject("PlayerFrameBackground", true)
        return true
    end

    if not self:Owns(FRAMES[1]) then return false end
    local cfg = self:Config()
    local frame = getglobal("PlayerFrame")
    local background = getglobal("PlayerFrameBackground")
    local health = getglobal("PlayerFrameHealthBar")
    local power = getglobal("PlayerFrameManaBar")
    if not frame or not health or not power then return false end

    health.lockColor = true
    health.capNumericDisplay = true
    --[[ **The donor's numbers, restored.**

         This briefly stopped setting the width, behind a comment saying "the
         mod that had this looking right never touched the width". That was
         read off ShaguTweaks' big-health mod, which indeed does not -- and
         which is not the addon this geometry is ported from.
         `EquadisUnitFrames.lua:343` says:

             PlayerFrameHealthBar:SetWidth(119);
             PlayerFrameHealthBar:SetHeight(29);
             PlayerFrameHealthBar:SetPoint("TOPLEFT",106,-22);

         Two addons conflated in one comment, and the comment was the whole
         evidence for the change. The donor is the authority. ]]--
    health:SetWidth(119)
    health:ClearAllPoints()
    power:ClearAllPoints()

    if self:Compact() then
        if background then
            background:ClearAllPoints()
            background:SetPoint("TOPLEFT", frame, "TOPLEFT", 106, -24)
            background:SetHeight(30)
        end
        health:SetHeight(20)
        health:SetPoint("TOPLEFT", frame, "TOPLEFT", 106, -22)
        power:SetPoint("TOPLEFT", frame, "TOPLEFT", 106, -42)
    else
        if background then
            background:ClearAllPoints()
            background:SetPoint("TOPLEFT", frame, "TOPLEFT", 106, -24)
            background:SetHeight(41)
        end
        --[[ 29, which is the donor's number. ]]--
        health:SetHeight(29)
        health:SetPoint("TOPLEFT", frame, "TOPLEFT", 106, -22)
        power:SetPoint("TOPLEFT", frame, "TOPLEFT", 106, -51)
    end

    --[==[ **What was written, and when.**

         `describe` already says what is *on* the frame. The half that has been
         missing through five passes is what this module *put* there: the two
         being different is the whole fault, and neither number alone can show
         it. A screenshot cannot, a live read cannot, and reasoning about the
         code has now been wrong five times.

         Recorded here at the moment of writing rather than derived afterwards,
         because a value derived from the settings is what the code *should*
         have written and the question is what it did. ]==]
    local _, _, _, _, wroteY = health:GetPoint(1)

    self.lastGeometry = {
        at = GetTime and GetTime() or 0,
        height = health:GetHeight(),
        y = wroteY,
    }

    return true
end

function M:StyleTargetGeometry()
    --[[ The same for the target: classic art, classic layout. See the player
         geometry for why the two travel together. ]]--
    if self:FrameGeometryMode() == "client" then
        self:RestoreObject("TargetFrameHealthBar", true)
        self:RestoreObject("TargetFrameManaBar", true)
        self:RestoreObject("TargetFrameBackground", true)
        return true
    end

    if not self:Owns(FRAMES[2]) then return false end
    local cfg = self:Config()
    local frame = getglobal("TargetFrame")
    local background = getglobal("TargetFrameBackground")
    local health = getglobal("TargetFrameHealthBar")
    local power = getglobal("TargetFrameManaBar")
    local plate = getglobal("TargetFrameNameBackground")
    local dead = getglobal("TargetDeadText")
    if not frame or not health or not power then return false end

    -- Blizzard deliberately keeps the target health/mana bars one frame level
    -- below TargetFrameTextureFrame. Some 1.12 forks/addons reset those levels
    -- after PLAYER_TARGET_CHANGED, which puts TargetName (and other frame text)
    -- underneath the StatusBar texture. Reassert the stock layering every style
    -- pass before positioning anything.
    local textureFrame = getglobal("TargetFrameTextureFrame")
    if textureFrame and textureFrame.GetFrameLevel and health.SetFrameLevel then
        local artLevel = textureFrame:GetFrameLevel() or 1
        local barLevel = artLevel - 1
        if barLevel < 0 then barLevel = 0 end
        health:SetFrameLevel(barLevel)
        if power.SetFrameLevel then power:SetFrameLevel(barLevel) end
    end

    if plate and plate.Hide then plate:Hide() end
    --[[ The donor's numbers, as above: `EquadisUnitFrames.lua:447` sets the
         target bar to 119 as well. See the player geometry. ]]--
    health:SetWidth(119)
    health.lockColor = true
    health:ClearAllPoints()
    power:ClearAllPoints()

    if self:Compact() then
        if background then background:SetHeight(30) end
        health:SetHeight(20)
        health:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -22)
        power:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -106, -42)
        if dead then
            dead:ClearAllPoints()
            dead:SetPoint("CENTER", frame, "CENTER", -50, 6)
        end
    else
        if background then background:SetHeight(41) end
        local classification = type(UnitClassification) == "function"
                and UnitClassification("target") or nil
        if classification == "minus" then
            health:SetHeight(12)
            health:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -41)
            if dead then
                dead:ClearAllPoints()
                dead:SetPoint("CENTER", frame, "CENTER", -50, 4)
            end
        else
            --[[ 30, which is what the mod that had this looking right used. ]]--
        health:SetHeight(29)
            health:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -22)
            if dead then
                dead:ClearAllPoints()
                dead:SetPoint("CENTER", frame, "CENTER", -50, 6)
            end
        end
        power:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -51)
    end
    return true
end

--[[ **Everything of target-of-target's put back, then the one thing UFI changes.**

     This restored the frame and moved the portrait, and left the health bar,
     the mana bar, the name and the artwork wherever anything else had put them.
     The frame arriving in the right place with its contents scattered inside it
     is what "target of target is still a little bit broken" was.

     The donor changes exactly one thing about this frame -- it shifts the
     portrait -- so everything else is the client's and the honest way to get it
     is to ask the client for it. `RestoreObject` replays the snapshot taken
     before anything here ran, which is right at any resolution and on any
     server that ships its own numbers, where four more hardcoded offsets would
     not be.

     Vanilla's own, for the record, since the numbers are worth having written
     down somewhere: the frame is 93x45, the bars 46x7 anchored TOPRIGHT, and
     the art crops `0.015625 -> 0.7265625` by `0 -> 0.703125`. ]]--
function M:StyleTargetTargetGeometry()
    if not self:Owns(FRAMES[3]) then return false end

    local cfg = self:Config()
    local frame = getglobal("TargetofTargetFrame")
    local portrait = getglobal("TargetofTargetPortrait")
    local saved = cfg.positions and cfg.positions.TargetofTargetFrame

    --[[ The frame first, unless somebody has dragged it: a saved position is a
         deliberate answer and putting the client's back over it would throw
         away the drag. ]]--
    if frame and not saved then
        self:RestoreObject("TargetofTargetFrame", true)
    end

    --[[ Then everything inside it. Geometry only -- size and anchor -- because
         the fonts, colours and bar textures are this addon's to set and
         `StyleFrame` sets them immediately afterwards. ]]--
    local inside = {
        "TargetofTargetHealthBar", "TargetofTargetManaBar",
        "TargetofTargetName", "TargetofTargetTexture",
    }

    for i = 1, table.getn(inside) do
        self:RestoreObject(inside[i], true)
    end

    --[[ And the artwork's crop, which `RestoreObject` leaves alone under
         geometry-only because tex coords sit with the texture and the tint.
         The pet is the only frame whose crop this addon sets on purpose. ]]--
    self:RestoreArtRegion(FRAMES[3])

    --[[ **The one deliberate change.** The donor shifts this portrait and
         changes nothing else about the frame. ]]--
    if portrait and frame then
        portrait:ClearAllPoints()
        portrait:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -53, 5)
    end

    return true
end

-- Original UFI mirrored/slim pet geometry, including the pieces the first ECO
-- port omitted (portrait, attack indicator, bar widths and name position).
--[[ **Where the pet's art sits, expressed against the frame it belongs to.**

     The donor's number is `PlayerFrame` BOTTOMRIGHT minus (104, 28). That is a
     fine way to say it on an addon where the pet frame cannot move, and the
     wrong way to say it here.

     Worked out once from the two frames while they are both where the client
     put them: the distance between the player's bottom-right and the pet's is
     fixed by the client's own layout, so the same visual position expressed
     against the pet frame is that distance plus the donor's offset.

     Cached, because after the pet frame has been dragged the two are no longer
     in the client's relationship and re-deriving would chase the art back onto
     the player. Falls back to the donor's own numbers when the frames cannot be
     measured -- which is what a stub, or a login before layout, looks like. ]]--
local PET_ART_X, PET_ART_Y = -104, -28

function M:PetArtOffset(art, frame, player)
    if self.petArtOffset then
        return self.petArtOffset[1], self.petArtOffset[2]
    end

    if not frame or not player or not frame.GetRight or not player.GetRight then
        return PET_ART_X, PET_ART_Y
    end

    local pr, pb = player:GetRight(), player:GetBottom()
    local fr, fb = frame:GetRight(), frame:GetBottom()

    if not pr or not pb or not fr or not fb then
        return PET_ART_X, PET_ART_Y
    end

    --[[ Only while the pet frame is still where the client put it. Once there
         is a saved position the relationship is somebody's choice rather than
         the client's, and measuring it would bake that choice into the art. ]]--
    local cfg = self:Config()
    if cfg.positions and cfg.positions.PetFrame then
        return PET_ART_X, PET_ART_Y
    end

    local dx = (pr + PET_ART_X) - fr
    local dy = (pb + PET_ART_Y) - fb

    self.petArtOffset = { dx, dy }
    return dx, dy
end

function M:StylePetGeometry()
    if not self:Owns(FRAMES[4]) then return false end
    local cfg = self:Config()
    local names = {
        "PetFrameTexture", "PetPortrait", "PetAttackModeTexture",
        "PetFrameHealthBar", "PetFrameHealthBarText", "PetFrameManaBar",
        "PetFrameManaBarText", "PetName", "PetFrameHappiness",
    }

    if not cfg.improvedPet then
        -- The first repair pass restored geometry only, which left the mirrored
        -- target-of-target texture and flipped texcoords behind when this toggle
        -- was switched off. Restore the pet art/happiness completely; restore
        -- geometry for bars/text/name so StyleFrame can immediately re-apply
        -- ECO's selected media afterwards.
        self:RestoreObject("PetFrameTexture", false)
        self:RestoreObject("PetFrameHappiness", false)
        for i = 2, table.getn(names) - 1 do self:RestoreObject(names[i], true) end
        local happy = getglobal("PetFrameHappiness")
        if happy and happy.Show then happy:Show() end
        return false
    end

    --[[ **The pet frame itself, put back unless it has been dragged.**

         Target of target already did this and the pet did not, so a stale
         position -- from another addon, or from an edit-mode drag that was
         later reset -- survived here and nothing ever corrected it. ]]--
    if not (cfg.positions and cfg.positions.PetFrame) then
        self:RestoreObject("PetFrame", true)
    end

    local art = getglobal("PetFrameTexture")
    local frame = getglobal("PetFrame")
    local player = getglobal("PlayerFrame")
    local portrait = getglobal("PetPortrait")
    local attack = getglobal("PetAttackModeTexture")
    local health = getglobal("PetFrameHealthBar")
    local healthText = getglobal("PetFrameHealthBarText")
    local power = getglobal("PetFrameManaBar")
    local powerText = getglobal("PetFrameManaBarText")
    local name = getglobal("PetName")
    local happy = getglobal("PetFrameHappiness")

    if art then
        art:SetTexture("Interface\\TargetingFrame\\UI-TargetofTargetFrame")
        art:SetTexCoord(1, 0, 0, 1)
        art:ClearAllPoints()
        --[[ **Anchored to the pet frame, not to the player frame.**

             The donor hangs this art off `PlayerFrame`, and on that addon
             it is harmless: the pet frame is nailed to the player frame, so
             the two never separate. This addon lets the pet frame be
             dragged, and the moment somebody does, the bars, the portrait
             and the name go with it while the art stays behind on the
             player. Guaranteed misalignment, and the sort that only shows
             up after a drag.

             The offset is worked out once, from where the donor's anchor
             puts the art while both frames are still at their own
             positions, so the default layout is pixel-identical and a
             dragged pet frame takes its art with it. ]]--
        local dx, dy = self:PetArtOffset(art, frame, player)
        art:SetPoint("BOTTOMRIGHT", frame or player, "BOTTOMRIGHT", dx, dy)
    end
    if portrait then
        portrait:ClearAllPoints()
        portrait:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -86, 8)
    end
    if attack then
        attack:ClearAllPoints()
        attack:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -46, -22)
    end
    if health then
        health:ClearAllPoints(); health:SetWidth(45)
        health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -125, 27)
    end
    if healthText then
        healthText:ClearAllPoints()
        healthText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -125, 27)
    end
    if power then
        power:ClearAllPoints(); power:SetWidth(45)
        power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -125, 18)
    end
    if powerText then
        powerText:ClearAllPoints()
        powerText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -125, 17)
    end
    if name then
        name:ClearAllPoints()
        name:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -125, 6)
    end
    if happy and happy.Hide then happy:Hide() end
    return true
end

--[[ **Happiness as a colour, which is the other half of the slimmer pet frame.**

     `StylePetGeometry` hides `PetFrameHappiness` -- the meter is a full-size
     piece of art and the point of this option is a frame three units tall. That
     half shipped on its own, so switching Slimmer Pet Frame on took a hunter's
     happiness readout away and put nothing in its place.

     The bar says it instead, in space it already occupies. Run after the styling
     loops rather than beside the geometry, because `StyleFrame` sets the bar's
     colour from the unit's reaction and would otherwise paint straight over
     this.

     **Only a hunter's pet has happiness.** A warlock's demon, a totem and a
     water elemental are friendly and nothing else; coluring one of them unhappy
     because `GetPetHappiness` answered oddly for a pet that has none would
     invent a problem the player does not have. ]]--
function M:PetHappinessColor()
    local cfg = self:Config()

    if OB.class ~= "HUNTER" then return cfg.friendlyColor end
    if type(GetPetHappiness) ~= "function" then return cfg.friendlyColor end

    local happiness = GetPetHappiness()
    if not happiness then return cfg.friendlyColor end

    if happiness >= 3 then return cfg.friendlyColor end
    if happiness == 2 then return cfg.neutralColor end

    return cfg.hostileColor
end

function M:StylePetHappiness()
    if not self:Config().improvedPet then return false end
    if not self:Owns(FRAMES[4]) then return false end

    local health = getglobal("PetFrameHealthBar")
    if not health or not health.SetStatusBarColor then return false end

    local color = self:PetHappinessColor()
    if not color then return false end

    health:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
    return true
end

function M:StyleGlow()
    if not self:Owns(FRAMES[1]) then
        self:RestoreObject("PlayerStatusTexture", false)
        return false
    end
    local player = getglobal("PlayerStatusTexture")
    if not player or not player.SetTexture then return false end
    if self:Config().statusGlow then
        if legacyAssetsInstalled() then
            player:SetTexture(legacyRoot() .. "Textures\\UI-Player-Status")
        else
            player:SetTexture("Interface\\CharacterFrame\\UI-Player-Status")
        end
    else
        player:SetTexture(nil)
    end
    -- UFI never disables PetAttackModeTexture with the player glow option; the
    -- first ECO port did, which removed the pet's attack-state feedback.
    return true
end

local AURA_SECTIONS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT",
                        "TOP", "BOTTOM", "LEFT", "RIGHT" }

function M:SkinAura(frame, offset, r, g, b)
    if not legacyAssetsInstalled() or not frame or not frame.CreateTexture then return false end
    if not frame.ecoUfiBorder then
        local t = {}
        offset = offset or 0
        for i = 1, table.getn(AURA_SECTIONS) do
            local section = AURA_SECTIONS[i]
            local tex = frame:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(legacyRoot() .. "skin\\texture\\border-" .. section .. ".tga")
            t[section] = tex
        end
        t.TOPLEFT:SetWidth(8); t.TOPLEFT:SetHeight(8)
        t.TOPLEFT:SetPoint("BOTTOMRIGHT", frame, "TOPLEFT", 4 + offset, -4 - offset)
        t.TOPRIGHT:SetWidth(8); t.TOPRIGHT:SetHeight(8)
        t.TOPRIGHT:SetPoint("BOTTOMLEFT", frame, "TOPRIGHT", -4 - offset, -4 - offset)
        t.BOTTOMLEFT:SetWidth(8); t.BOTTOMLEFT:SetHeight(8)
        t.BOTTOMLEFT:SetPoint("TOPRIGHT", frame, "BOTTOMLEFT", 4 + offset, 4 + offset)
        t.BOTTOMRIGHT:SetWidth(8); t.BOTTOMRIGHT:SetHeight(8)
        t.BOTTOMRIGHT:SetPoint("TOPLEFT", frame, "BOTTOMRIGHT", -4 - offset, 4 + offset)
        t.TOP:SetHeight(8); t.TOP:SetPoint("TOPLEFT", t.TOPLEFT, "TOPRIGHT", 0, 0)
        t.TOP:SetPoint("TOPRIGHT", t.TOPRIGHT, "TOPLEFT", 0, 0)
        t.BOTTOM:SetHeight(8); t.BOTTOM:SetPoint("BOTTOMLEFT", t.BOTTOMLEFT, "BOTTOMRIGHT", 0, 0)
        t.BOTTOM:SetPoint("BOTTOMRIGHT", t.BOTTOMRIGHT, "BOTTOMLEFT", 0, 0)
        t.LEFT:SetWidth(8); t.LEFT:SetPoint("TOPLEFT", t.TOPLEFT, "BOTTOMLEFT", 0, 0)
        t.LEFT:SetPoint("BOTTOMLEFT", t.BOTTOMLEFT, "TOPLEFT", 0, 0)
        t.RIGHT:SetWidth(8); t.RIGHT:SetPoint("TOPRIGHT", t.TOPRIGHT, "BOTTOMRIGHT", 0, 0)
        t.RIGHT:SetPoint("BOTTOMRIGHT", t.BOTTOMRIGHT, "TOPRIGHT", 0, 0)
        frame.ecoUfiBorder = t
    end
    for _, tex in pairs(frame.ecoUfiBorder) do
        tex:SetVertexColor(r or 1, g or 1, b or 1, 1)
        if tex.Show then tex:Show() end
    end
    return true
end

function M:HideAuraSkins()
    for i = 1, 5 do
        local frame = getglobal("TargetFrameBuff" .. i)
        if frame and frame.ecoUfiBorder then
            for _, tex in pairs(frame.ecoUfiBorder) do if tex.Hide then tex:Hide() end end
        end
    end
    for i = 1, 4 do
        local frame = getglobal("TargetofTargetFrameDebuff" .. i)
        if frame and frame.ecoUfiBorder then
            for _, tex in pairs(frame.ecoUfiBorder) do if tex.Hide then tex:Hide() end end
        end
    end
end

--[[ **How long is left, on the icon.**

     The client draws a target's buffs and debuffs as pictures with a stack
     count and nothing else -- no duration, because 1.12 has no call that
     returns one. `OB.AuraTimeLeft` answers it from when the aura was first seen
     and a shipped table of how long each spell lasts.

     **Only when it can be answered.** A spell absent from the table shows no
     number rather than a zero: a timer reading nought on a debuff that is
     plainly still ticking is worse than no timer, because it is read as fact
     rather than as ignorance. ]]--
function M:AuraTimerText(frame)
    if not frame or not frame.CreateFontString then return nil end
    if frame.ecoAuraTimer then return frame.ecoAuraTimer end

    local text = OB.NewText(frame, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("BOTTOM", frame, "BOTTOM", 0, -2)
    text:SetJustifyH("CENTER")

    frame.ecoAuraTimer = text
    return text
end

--[[ Read off the icon rather than passed in: the client owns these buttons and
     tells us which aura is on which one only through its own fields.

     `harmful` picks which of the two tooltip setters to use. A debuff's name
     does not come out of `SetUnitBuff` -- the two lists are numbered separately,
     so slot three of one is a different spell from slot three of the other, and
     asking the wrong one answers about whatever happens to be there. ]]--
function M:AuraSpellOn(frame, unit, index, harmful)
    if not frame then return nil end

    --[[ The tooltip is the only place 1.12 puts an aura's name for a unit that
         is not the player, and reading it is what every addon that needs the
         name ends up doing. ]]--
    if type(OB.ScanTooltip) ~= "function" then return nil end

    local tip = OB.ScanTooltip()
    if not tip then return nil end

    local spell

    local setter = harmful and tip.SetUnitDebuff or tip.SetUnitBuff

    if type(setter) == "function" then
        tip:ClearLines()

        if pcall(setter, tip, unit, index) then spell = OB.ScanLine(1) end
    end

    --[[ An empty line is not a name. It is truthy, so left as it is it records
         an aura called "" against the unit and then finds no duration for it --
         which looks exactly like the tooltip having worked and the spell having
         no timer. ]]--
    if spell == "" then spell = nil end

    if spell then return spell end

    --[==[ **The tooltip said nothing, so ask the icon.**

         `SetUnitDebuff` answers nothing on this client, and the nameplates were
         given `NameByIcon` for exactly that in v0.99.217 -- NOTICE records that
         the icon fallback, not the tooltip's parent, is what actually restored
         those timers. **This frame reads the same tooltip on the same client and
         never got the same fallback**, so its debuff timers went on having no
         name and therefore no number. Reported as the timers missing, twice.

         The icon comes from the client rather than from the frame's texture: the
         frame is the client's and a reskin can repoint it, while `UnitDebuff`
         answers about the aura. ]==]
    local reader = harmful and UnitDebuff or UnitBuff
    if type(reader) ~= "function" then return nil end

    local ok, texture = pcall(reader, unit, index)
    if not ok or not texture then return nil end

    return OB.AuraNameByIcon(self:AuraOwner(unit), texture)
end

--[==[ **The aura store is keyed by name, not by unit token.**

     `OB.AddAura` records against `UnitName(unit)`, because the combat log only
     ever names a unit and a debuff on somebody who is not your target has no
     token at all. So a lookup made with "target" asks about a unit called
     "target", finds nothing, and answers no time left -- silently, which is
     indistinguishable from a spell that is simply not in the duration table.

     That is why the timers on this frame have never shown a number. The code
     was right, the table was there, and the key was a word. ]==]
function M:AuraOwner(unit)
    if not unit then return nil end
    if type(UnitName) ~= "function" then return nil end
    if type(UnitExists) == "function" and not UnitExists(unit) then return nil end

    local name = UnitName(unit)
    if not name or name == "" then return nil end

    return name
end

--[==[ **Both lists, and the debuffs are the ones that were asked for.**

     This covered `TargetFrameBuff1..5` and nothing else, so the timer people
     actually want -- how long is left on the curse you put on that thing --
     was the one it did not draw.

     Sixteen debuff slots against five buff ones, because that is what the
     client builds: `MAX_TARGET_DEBUFFS` is sixteen and a raid boss can carry
     every one of them.

     The two lists are numbered separately and read through different tooltip
     setters, which is the whole reason `harmful` exists rather than one loop
     over a combined range. ]==]
local AURA_SLOTS = {
    { prefix = "TargetFrameBuff", count = 5, harmful = false },
    { prefix = "TargetFrameDebuff", count = 16, harmful = true },
}

--[[ How often the numbers are redrawn. The same quarter second the nameplates
     use for the same job: the text is whole seconds, so anything faster redraws
     the number it already had, and the tooltip scan behind it is not free. ]]--
local AURA_TIMER_INTERVAL = 0.25

function M:ApplyAuraTimers(unit)
    local cfg = self:Config()

    if not cfg.auraTimers then
        self:HideAuraTimers()
        return 0
    end

    --[[ Resolved once for the whole pass: it is the same unit for every slot,
         and `UnitName` is not free. ]]--
    local owner = self:AuraOwner(unit)
    local shown = 0

    for s = 1, table.getn(AURA_SLOTS) do
        local set = AURA_SLOTS[s]

        for i = 1, set.count do
            local frame = getglobal(set.prefix .. i)

            if frame then
                local text = self:AuraTimerText(frame)

                local spell = owner and frame:IsShown()
                        and self:AuraSpellOn(frame, unit, i, set.harmful)

                --[==[ **What is read here starts a clock if nothing else has.**

                     A debuff put on a mob by somebody else never appears in
                     this player's combat log, so the aura store had never heard
                     of it and the timer had nothing to count. The tooltip scan
                     *has* just seen it, which is a weaker fact than "it landed
                     now" and the only one available -- so it is recorded as
                     first-seen and never re-stamped. See `OB.NoteAura`. ]==]
                if spell and OB.NoteAura then OB.NoteAura(owner, spell) end

                local left = spell and OB.AuraTimeText(owner, spell)

                if left then
                    text:SetText(left)
                    text:Show()
                    shown = shown + 1
                else
                    text:SetText("")
                    text:Hide()
                end
            end
        end
    end

    return shown
end

--[[ The same slots the pass writes, or switching the setting off leaves a
     number on every debuff it had already drawn. ]]--
function M:HideAuraTimers()
    for s = 1, table.getn(AURA_SLOTS) do
        local set = AURA_SLOTS[s]

        for i = 1, set.count do
            local frame = getglobal(set.prefix .. i)

            if frame and frame.ecoAuraTimer then
                frame.ecoAuraTimer:SetText("")
                frame.ecoAuraTimer:Hide()
            end
        end
    end

    return true
end

--[[ **A cast bar for the target, which the client does not draw at all.**

     1.12 has no `UnitCastingInfo`; it arrives in 2.0. The client draws a cast
     bar for you and nothing for anyone else, so the question "what is that mob
     casting at me" has no answer on a stock interface.

     `OB.CastInfo` answers it -- the casts module reads the combat log and learns
     durations from spells you cast yourself -- and the nameplates already draw
     from it. The unit frames did not, which is why a target casting showed
     nothing.

     **A spell with no known duration still gets a bar**, empty, with its name
     on it. What is being cast matters more than how far through it is, and a
     bar that appears only for spells already learned would be missing exactly
     when a new mob does something unfamiliar. ]]--
--[==[ **Two bars built by one function, because they are the same bar.**

     The only things that differ between yours and your target's are which unit
     is read and where it starts out. Written twice, the timer would have gone
     on one of them and the colour on the other -- which is how the target bar
     came to have neither. ]==]
local CAST_BARS = {
    player = { anchor = "PlayerFrame", label = "Cast Bar" },
    target = { anchor = "TargetFrame", label = "Target Cast Bar" },
}

--[[ The sliders' own bounds, kept here so the rows and the frame cannot
     disagree about what a legal size is -- the trap every "resize" grows when
     the two are written separately. ]]--
local CAST_MIN_W, CAST_MAX_W = 80, 400
local CAST_MIN_H, CAST_MAX_H = 8, 40

local function castSize(value, low, high, fallback)
    value = tonumber(value)
    if not value then return fallback end

    if value < low then return low end
    if value > high then return high end

    return value
end

function M:CastBar(id)
    self.castBars = self.castBars or {}
    if self.castBars[id] then return self.castBars[id] end
    if not CreateFrame then return nil end

    local spec = CAST_BARS[id]
    if not spec then return nil end

    local frame = getglobal(spec.anchor)
    if not frame then return nil end

    local bar = CreateFrame("StatusBar",
            "EquadisClassicOverhaul" .. id .. "Cast", UIParent)

    bar:SetWidth(150)
    bar:SetHeight(14)
    bar:SetPoint("TOP", frame, "BOTTOM", 0, -4)
    bar:SetMinMaxValues(0, 1)
    bar:Hide()

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetTexture(0, 0, 0, 0.6)

    --[[ A frame rather than four textures on the bar: the bar's own texture is
         swapped by the appearance setting, and a border living in its layers
         would be swapped with it. The same shape the nameplates use. ]]--
    bar.border = CreateFrame("Frame", nil, bar)

    if bar.border.SetFrameLevel and bar.GetFrameLevel then
        bar.border:SetFrameLevel((bar:GetFrameLevel() or 0) + 1)
    end

    --[==[ **The name to the left, the clock to the right.**

         Centred, they are one string and the eye has to read it to find the
         number. Pinned to opposite ends, the number is always in the same place
         -- which is the whole value of a clock you glance at rather than
         read. ]==]
    --[==[ **A square on the leading edge, outside the bar rather than over it.**

         Drawn on top, the icon covers the fill at exactly the moment the fill
         matters most -- the beginning of a cast. Beside it, the bar is still a
         whole bar and the icon is still square. ]==]
    bar.icon = bar:CreateTexture(nil, "OVERLAY")
    bar.icon:SetPoint("TOPRIGHT", bar, "TOPLEFT", -2, 0)
    bar.icon:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -2, 0)
    bar.icon:SetWidth(14)

    --[[ The border the client crops off every action button, so the icon has no
         grey frame of its own inside ours. ]]--
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.icon:Hide()

    bar.label = OB.NewText(bar, "OVERLAY", "GameFontNormalSmall")
    bar.label:SetPoint("LEFT", bar, "LEFT", 3, 0)
    bar.label:SetJustifyH("LEFT")

    bar.timer = OB.NewText(bar, "OVERLAY", "GameFontNormalSmall")
    bar.timer:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    bar.timer:SetJustifyH("RIGHT")

    bar.castId = id

    if OB.MarkMovable then OB.MarkMovable(bar, spec.label) end

    bar:SetScript("OnDragStop", function()
        if this.StopMovingOrSizing then this:StopMovingOrSizing() end
        OB.modules.unitframes:StoreCastBarPosition(this)
    end)

    self.castBars[id] = bar
    return bar
end

--[==[ Kept as its own name because other code calls it, and because "the target
     cast bar" is a thing somebody looks for. ]==]

-- ---------------------------------------------------------------------------
-- the two small frames, built here rather than borrowed
-- ---------------------------------------------------------------------------

--[==[ **Target-of-target and the pet are ours, because they were nobody's.**

     Both are small frames the client draws beside a bigger one, and both are
     what a frame addon replaces first. DragonflightUI-Reforged hides
     `TargetofTargetHealthBar` and `TargetofTargetManaBar`, swaps the frame's
     texture for its own, and then hooks `TargetofTarget_Update` to hide them
     again on every refresh.

     This module had a repair pass for exactly that: it noticed the art missing
     and put it back. Against a hook that fires on every update, a repair on a
     ten-hertz tick is a race it loses roughly nine times in ten -- which is why
     what was on screen was an icon and some bars and no frame at all.

     So they are built here now and the client's are hidden. The same answer the
     party frames got, for the same reason, and the third time today: a frame you
     do not own is a frame somebody else can take. ]==]
local SMALL_FRAMES = {
    targettarget = {
        name = "EquadisClassicOverhaulToT",
        client = "TargetofTargetFrame",
        unit = "targettarget",
        label = "Target of Target",
        anchorTo = "TargetFrame",
        point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 30, y = 14,

        --[==[ **The pieces, because hiding the parent may not reach them.**

             Hiding a frame hides its children, so naming these should be
             unnecessary -- and it is, right up until a neighbour reparents one.
             DragonflightUI-Reforged works on exactly these two by name: it
             hides them, swaps the frame's texture, and hooks
             `TargetofTarget_Update` to hide them again on every refresh. A bar
             it has taken off this frame no longer goes away when the frame
             does, and what is left is the client's bars floating over ours --
             the reported "bars are on top of the frame".

             Hiding them by name costs nothing while they are still children. ]==]
        parts = { "TargetofTargetHealthBar", "TargetofTargetManaBar" },
    },
    pet = {
        name = "EquadisClassicOverhaulPet",
        client = "PetFrame",
        unit = "pet",
        label = "Pet",
        anchorTo = "PlayerFrame",
        point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 42, y = 22,
        parts = { "PetFrameHealthBar", "PetFrameManaBar" },
    },
}

--[[ Small enough to sit beside the frame it belongs to without competing with
     it, which is the whole job of both of these. ]]--
local SMALL_SCALE = 0.62

function M:SmallFrame(id)
    local spec = SMALL_FRAMES[id]
    if not spec then return nil end

    self.smallFrames = self.smallFrames or {}
    if self.smallFrames[id] then return self.smallFrames[id] end
    if not CreateFrame then return nil end

    local parent = getglobal(spec.anchorTo) or UIParent
    local f = CreateFrame("Button", spec.name, UIParent)

    f:SetWidth(232)
    f:SetHeight(100)
    f:SetScale(SMALL_SCALE)
    f:SetPoint(spec.point, parent, spec.relPoint, spec.x, spec.y)
    f:Hide()

    --[==[ **The border art in a frame of its own, above the bars.**

         The same fault the party frames had, in the same construction: a texture
         belongs to a draw layer within its frame, and a child frame draws above
         every layer of its parent. The bars are child frames, so no value of
         `ARTWORK` or `OVERLAY` could put the border in front of them, and the
         frame rendered underneath its own bars.

         Fixed here as well as there rather than shared, because these two build
         their frames independently and a helper that both called would be a
         third place to look when one of them is wrong. ]==]
    f.artFrame = CreateFrame("Frame", nil, f)
    f.artFrame:SetAllPoints(f)
    f.artFrame:SetFrameLevel((f:GetFrameLevel() or 1) + 3)

    f.art = f.artFrame:CreateTexture(nil, "ARTWORK")
    f.art:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.art:SetWidth(232)
    f.art:SetHeight(100)
    --[[ Mirrored: the portrait is on the left here and the bars at 106, which
         is the player frame's arrangement rather than the target's. The art is
         drawn the other way round, so it is flipped to match -- see the party
         frames for the same note and the same reason. ]]--
    f.art:SetTexCoord(1.0, 0.09375, 0, 0.78125)

    f.portrait = f:CreateTexture(nil, "BACKGROUND")
    f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", 43, -18)
    f.portrait:SetWidth(58)
    f.portrait:SetHeight(58)

    f.health = CreateFrame("StatusBar", nil, f)
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 106, -22)
    f.health:SetWidth(119)
    f.health:SetHeight(20)
    f.health:SetMinMaxValues(0, 1)

    f.power = CreateFrame("StatusBar", nil, f)
    f.power:SetPoint("TOPLEFT", f, "TOPLEFT", 106, -42)
    f.power:SetWidth(119)
    f.power:SetHeight(10)
    f.power:SetMinMaxValues(0, 1)

    --[[ `nameText`, not `name`: a frame's own name lives on `name`, and putting
         a font string there hands a table to anything that builds a child's name
         by concatenation. ]]--
    --[[ Above the art, which is now above the bars. ]]--
    f.textFrame = CreateFrame("Frame", nil, f)
    f.textFrame:SetAllPoints(f)
    f.textFrame:SetFrameLevel((f:GetFrameLevel() or 1) + 6)

    f.nameText = OB.NewText(f.textFrame, "OVERLAY", "GameFontNormalSmall")
    f.nameText:SetPoint("BOTTOMLEFT", f.health, "TOPLEFT", 0, 1)

    --[[ The level, in the badge the art draws for it -- the same circle at the
         portrait's corner the party frames fill, and the same two numbers,
         because it is the same picture at a different scale. ]]--
    f.levelText = OB.NewText(f.textFrame, "OVERLAY", "GameFontNormalSmall")
    f.levelText:SetPoint("CENTER", f.portrait, "BOTTOMLEFT", 11, 13)
    f.levelText:SetJustifyH("CENTER")
    f.nameText:SetJustifyH("LEFT")

    f.unit = spec.unit
    f:RegisterForClicks("LeftButtonUp")
    f:SetScript("OnClick", function()
        if type(TargetUnit) == "function" then TargetUnit(this.unit) end
    end)

    self.smallFrames[id] = f
    return f
end

--[==[ The client's copy, kept off screen. Hidden rather than left alone: two
     target-of-target frames is worse than either one of them. ]==]
function M:HideClientSmallFrame(id)
    local spec = SMALL_FRAMES[id]
    if not spec then return false end

    local frame = getglobal(spec.client)
    if not frame or not frame.Hide then return false end

    --[[ The frame and any piece of it that might have been taken elsewhere.
         See `parts` on the spec for why the second half is not redundant. ]]--
    local hide = { frame }

    for i = 1, table.getn(spec.parts or {}) do
        local part = getglobal(spec.parts[i])
        if part and part.Hide then table.insert(hide, part) end
    end

    --[[ And they stay hidden. `TargetofTarget_Update` shows them again every
         time the unit changes, which is the same hook DragonflightUI fights. ]]--
    for i = 1, table.getn(hide) do
        local piece = hide[i]
        piece:Hide()

        if not piece.ecoHidden then
            piece.ecoHidden = true

            local shown = piece.Show
            piece.Show = function(self)
                if EquadisClassicOverhaul.modules.unitframes:OwnsSmall(id) then
                    return
                end
                return shown(self)
            end
        end
    end

    return true
end

--[[ Whether this module is drawing its own version of a small frame right now.
     Asked from inside the `Show` guard above, so it has to be answerable at any
     moment and cannot assume the panel has been built. ]]--
function M:OwnsSmall(id)
    if not OB.ModuleEnabled("unitframes") then return false end

    local spec = SMALL_FRAMES[id]
    if not spec then return false end

    local cfg = self:Config()
    return cfg.ownSmallFrames and true or false
end

function M:StyleSmallFrame(id)
    local spec = SMALL_FRAMES[id]
    if not spec then return false end

    local f = self:SmallFrame(id)
    if not f then return false end

    if not self:OwnsSmall(id) then
        f:Hide()
        return false
    end

    self:HideClientSmallFrame(id)

    local unit = spec.unit

    if type(UnitExists) ~= "function" or not UnitExists(unit) then
        --[==[ **Except while somebody is placing it.**

             Edit mode only outlines a frame that is on screen, which is the
             right rule -- an outline round a hidden frame is a rectangle over
             the world with nothing in it. But these two hide themselves
             whenever their unit is absent, and standing about with no
             target-of-target is exactly when somebody opens edit mode to
             arrange things. So there was nothing to outline and nothing to
             drag, which is the reported "the move frame still does not
             appear".

             Shown with a placeholder instead, so the thing being positioned is
             the size and shape of the thing that will be there. ]==]
        if not self:DragMode() then
            f:Hide()
            return false
        end

        f:Show()
        f.nameText:SetText(spec.label or "")
        f.levelText:SetText("??")

        f.health:SetMinMaxValues(0, 1)
        f.health:SetValue(1)
        f.health:SetStatusBarColor(0.4, 0.4, 0.4, 1)

        f.power:SetMinMaxValues(0, 1)
        f.power:SetValue(1)
        f.power:SetStatusBarColor(0.3, 0.3, 0.4, 1)

        local shade = self:DarkShade()
        f.art:SetTexture(legacyRoot() .. "Textures\\compactUI-TargetingFrame")
        f.art:SetVertexColor(shade, shade, shade)

        return true
    end

    f:Show()

    --[[ The compact art, which is what these are sized for. Asking for the
         full-size art here would draw a divider where no bar ends. ]]--
    f.art:SetTexture(legacyRoot() .. "Textures\\compactUI-TargetingFrame")

    --[[ **Tinted for dark mode like every other frame this module draws.**

         These were left at full brightness, so switching the interface to dark
         left the target-of-target and the pet lit up beside frames that were
         not. Tinted rather than swapped for a dark file, which is the decision
         this module already made and recorded for the frames it skins. ]]--
    local shade = self:DarkShade()
    f.art:SetVertexColor(shade, shade, shade)

    if type(SetPortraitTexture) == "function" then
        SetPortraitTexture(f.portrait, unit)
    end

    f.nameText:SetText(UnitName(unit) or "")

    local texture = OB.TexturePath and OB.TexturePath("unitframes") or nil
    if texture then
        f.health:SetStatusBarTexture(texture)
        f.power:SetStatusBarTexture(texture)
    end

    local health, healthMax = UnitHealth(unit) or 0, UnitHealthMax(unit) or 1
    if healthMax <= 0 then healthMax = 1 end

    f.health:SetMinMaxValues(0, healthMax)
    f.health:SetValue(health)

    --[[ **Through the same resolver as every other frame here.**

         This was a hardcoded green, so a hostile target-of-target was the same
         colour as a friendly one and a player's class never showed. `UnitColor`
         is the function the rest of the module uses: class for a player,
         reaction for an NPC, grey for a mob somebody else tapped. ]]--
    local colour = self:UnitColor(unit)

    if colour then
        f.health:SetStatusBarColor(colour[1], colour[2], colour[3], colour[4] or 1)
    else
        f.health:SetStatusBarColor(0, 1, 0)
    end

    local power, powerMax = UnitMana(unit) or 0, UnitManaMax(unit) or 1
    if powerMax <= 0 then powerMax = 1 end

    f.power:SetMinMaxValues(0, powerMax)
    f.power:SetValue(power)

    --[[ The same omission the party frames had: created, filled, shown and
         never given a colour, so it drew as the plain white texture. ]]--
    f.power:SetStatusBarColor(OB.PowerColor(unit))

    local level = type(UnitLevel) == "function" and UnitLevel(unit) or nil

    if level and level > 0 then
        f.levelText:SetText(tostring(level))
    else
        f.levelText:SetText("??")
    end

    OB.ApplyFont(f.nameText, nil, "unitframes")
    OB.ApplyFont(f.levelText, nil, "unitframes")

    return true
end

function M:StyleSmallFrames()
    self:StyleSmallFrame("targettarget")
    self:StyleSmallFrame("pet")
    return true
end

function M:StoreCastBarPosition(bar)
    if not bar or not bar.GetLeft or not bar:GetLeft() then return false end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    local scale = bar:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.positions[(bar.castId or "target") .. "Cast"] = {
        x = OB.Round((bar:GetLeft() + (bar:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((bar:GetBottom() + (bar:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[==[ **Styled on a restyle, moved on every frame.**

     A cast bar is the one widget here that has to be frame-driven: the whole
     point of it is a rectangle crossing a gap in about a second and a half, and
     a bar that jumps only when some event happens to fire does not read as slow
     so much as broken.

     But almost nothing *about* it changes at that rate. The texture, the
     colour, the fonts and the saved position turn over when somebody edits a
     setting; only the fill, the name and the clock move. Split so the per-frame
     pass writes three things instead of nine -- which is the same rule the
     geometry refresh above already follows, and for the same reason. ]==]
--[==[ **The client's own cast bar, put away and given back.**

     Hidden rather than unregistered: taking its events away would need the list
     put back exactly to restore it, and a frame that is merely hidden is one
     `Show` from being the client's again.

     The `OnShow` guard is the half that makes it stick. `CastingBarFrame_OnEvent`
     shows the bar on every cast, so hiding it once lasts until the next spell --
     which is the version of this that every addon ships broken. The original
     handler is kept and called first, so nothing the client does inside it is
     skipped. ]==]
function M:StyleBlizzardCastBar()
    local bar = getglobal("CastingBarFrame")
    if not bar or not bar.Hide then return false end

    --[[ Always, while this module is running. See the note beside the
         defaults. ]]--
    local hide = OB.ModuleEnabled("unitframes") and true or false

    --[[ Installed once, and then it reads the setting rather than being taken
         off again -- a script slot is one per frame, and clearing ours would
         clear whatever a neighbour put there afterwards. ]]--
    if not bar.eqEcoCastGuard and bar.SetScript then
        bar.eqEcoCastGuard = true

        local was = bar.GetScript and bar:GetScript("OnShow")

        bar:SetScript("OnShow", function()
            if was then was() end

            local m = EquadisClassicOverhaul.modules.unitframes

            if m and OB.ModuleEnabled("unitframes") then
                this:Hide()
            end
        end)
    end

    if hide then
        bar:Hide()
    end

    return hide
end

function M:StyleCastBar(id)
    local cfg = self:Config()
    local bar = self:CastBar(id)
    if not bar then return false end

    local saved = cfg.positions and cfg.positions[id .. "Cast"]

    if saved then
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    end

    local look = OB.Look("unitframes")

    if bar.SetStatusBarTexture then
        bar:SetStatusBarTexture(OB.textures[look.texture] or OB.textures[1])
    end

    local colour = cfg.castColor or { 1, 0.82, 0.10, 1 }
    if bar.SetStatusBarColor then
        bar:SetStatusBarColor(colour[1], colour[2], colour[3], colour[4] or 1)
    end

    self:StyleCastText(bar.label, cfg)
    self:StyleCastText(bar.timer, cfg)

    --[==[ **The size, clamped to the sliders' own range.**

         Clamped here rather than trusted, because a profile written by an older
         build has no number at all and a hand-edited one can hold any number:
         a bar four pixels tall has no room for the name that is written on it,
         and one wider than the screen cannot be dragged back. ]==]
    bar:SetWidth(castSize(cfg.castWidth, CAST_MIN_W, CAST_MAX_W, 150))
    bar:SetHeight(castSize(cfg.castHeight, CAST_MIN_H, CAST_MAX_H, 14))

    --[[ Square, off the bar's own height, so changing the bar does not leave a
         stretched icon beside it. ]]--
    local h = bar:GetHeight()
    if h and h > 0 then bar.icon:SetWidth(h) end

    self:StyleCastBorder(bar, cfg)

    return true
end

--[==[ **The cast bar's border, hung where the ink actually is.**

     `OB.BorderEdge` narrows the art to fit a short bar -- a fourteen pixel cast
     bar cannot carry an eight pixel edge without the corners meeting in the
     middle -- which is the same reason the nameplates ask for it rather than
     using the backdrop directly. That half was right and is unchanged.

     **The pad was one pixel, chosen rather than measured**, and that is what put
     the fill outside the line. A backdrop's edge band is drawn *inward* from the
     frame's boundary and the opaque art hugs the outer end of that band, so a
     border frame has to be hung outward by however far the ink reaches back in
     -- which `OB.borderEdges` records as `outset` for exactly this reason, and
     which this ignored. With the tooltip edge narrowed for a fourteen pixel bar
     that distance is nearly three pixels, so the drawn line landed about two
     pixels *inside* the bar: the border sitting on the fill instead of around
     it, and the fill running out from under it.

     The same reading the tooltip's health bar does, for the same reason. The
     nameplates hang theirs one pixel out instead, which is a deliberate override
     and says so where it is done.

     **Measured against the bar rather than against the border frame**, because
     the pad is not known until the edge has been chosen and the edge is chosen
     from what fits inside it. Off by the pad, and in the safe direction: a
     narrower edge cannot overlap its own corners. ]==]
function M:StyleCastBorder(bar, cfg)
    if not bar or not bar.border then return false end

    cfg = cfg or self:Config()

    local edge = OB.BorderEdge(tonumber(cfg.castBorder) or 1,
            bar:GetWidth(), bar:GetHeight())

    if not edge then
        bar.border:SetBackdrop(nil)
        bar.border:Hide()
        return true
    end

    local size = tonumber(edge.edgeSize) or 8
    local pad = math.floor(tonumber(edge.outset) or (size / 2))
    if pad < 1 then pad = 1 end

    bar.border:ClearAllPoints()
    bar.border:SetPoint("TOPLEFT", bar, "TOPLEFT", -pad, pad)
    bar.border:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", pad, -pad)

    --[[ Only the edge. `insets` say where a background stops and there is no
         background here; `outset` is this addon's own measurement rather than a
         key `SetBackdrop` knows. Handing the client the whole table gives it two
         fields it has no use for and hides which one is doing the work. ]]--
    bar.border:SetBackdrop({
        edgeFile = edge.edgeFile,
        edgeSize = size,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })

    --[[ Re-asserted on every pass rather than only at creation: a frame given an
         explicit level stops tracking its parent's, so the bar being raised
         afterwards would leave its border under the fill it sits over. ]]--
    if bar.border.SetFrameLevel and bar.GetFrameLevel then
        bar.border:SetFrameLevel((bar:GetFrameLevel() or 0) + 1)
    end

    local c = cfg.castBorderColor or { 0.35, 0.35, 0.35, 1 }
    bar.border:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    bar.border:Show()

    return true
end

--[==[ Written only when it changed. The fill moves every frame because that is
     what makes it a cast bar; a spell name does not change while it is being
     cast, and the clock turns over ten times a second at most. ]==]
--[==[ **The cast bar's own font, size and colour, falling back to the module's.**

     `OB.ApplyFont` is per module rather than per element, so the only way for
     one bar to differ from the frames around it is to ask for its own after.
     Applied in that order deliberately: the module's answer first so the
     outline and every other shared decision still arrive, then the two things
     this bar is allowed to disagree about.

     A blank font and a zero size mean "follow the module", which is what makes
     these rows free for anybody who never opens them. ]==]
function M:StyleCastText(region, cfg)
    if not region then return false end

    cfg = cfg or self:Config()

    local size = tonumber(cfg.castFontSize)
    if not size or size <= 0 then size = nil end

    OB.ApplyFont(region, size, "unitframes")

    --[[ The face, only where one was chosen. `OB.FontFile` answers nil for a
         name nothing ships, which leaves the module's own in place rather than
         blanking the text -- a `SetFont` with a bad path draws nothing at all. ]]--
    local face = cfg.castFont

    if face and face ~= "" and OB.FontFile and region.GetFont then
        local path = OB.FontFile(face)

        if path then
            local _, current, flags = region:GetFont()
            region:SetFont(path, size or current or 10, flags)
        end
    end

    local colour = cfg.castTextColor

    if colour and region.SetTextColor then
        region:SetTextColor(colour[1] or 1, colour[2] or 1, colour[3] or 1,
                colour[4] or 1)
    end

    return true
end

--[[ What a cast bar says while it is being arranged. A real spell name rather
     than a placeholder word, because the width of the text is part of what is
     being looked at. ]]--
local CAST_PREVIEW_NAME = "Greater Heal"

local function castText(region, cache, value)
    if not region then return end
    if region[cache] == value then return end

    region[cache] = value
    region:SetText(value or "")
end

function M:UpdateCastBar(id, unit, enabled)
    local cfg = self:Config()
    local bar = self:CastBar(id)
    if not bar then return false end

    if not enabled then
        bar:Hide()
        return false
    end

    local who = UnitName and UnitName(unit) or nil
    local spell, fraction, channel, remaining = nil, nil, nil, nil

    if who then spell, fraction, channel, remaining = OB.CastInfo(who) end

    if not spell then
        bar:Hide()
        return false
    end

    --[==[ **The fraction is used as given, and that is the fix.**

         `CastInfo` already turns a channel round -- it is the one place that
         knows, because it is the one place holding the flag. This inverted it a
         second time, so every channel filled up like a cast and the one visual
         difference between the two was not merely missing but backwards.

         Two functions both being careful about the same thing is how that
         happens. Only the one holding the flag should be. ]==]
    if fraction then
        bar:SetValue(fraction)
    else
        --[==[ Unknown duration: no fill rather than a full bar, which would
             read as a cast about to land. ]==]
        bar:SetValue(0)
    end

    castText(bar.label, "ecoLabelValue", spell)

    --[==[ Looked up per spell rather than per frame: the answer cannot change
         while one spell is being cast, and the lookup walks a table. ]==]
    if cfg.castIcon then
        --[[ The generation as well as the name. A failed lookup caches as firmly
             as a successful one, and the icon map is empty until the client
             announces the spellbook -- so without this, anything cast in the
             first moments of a session has no icon for the rest of it. ]]--
        local generation = OB.spellIconGeneration or 0

        if bar.ecoIconSpell ~= spell or bar.ecoIconGen ~= generation then
            bar.ecoIconSpell = spell
            bar.ecoIconGen = generation
            bar.ecoIconTexture = OB.SpellIcon and OB.SpellIcon(spell) or nil
        end

        --[[ No icon rather than a wrong one. A spell in neither your book nor
             anything you have been hit by simply has none, and a bar without an
             icon reads fine -- a bar with somebody else's icon is a spell you
             would swear you recognised. ]]--
        if bar.ecoIconTexture then
            bar.icon:SetTexture(bar.ecoIconTexture)
            bar.icon:Show()
        else
            bar.icon:Hide()
        end
    else
        bar.icon:Hide()
    end

    --[==[ Nothing rather than a zero when the duration was never learned. A
         clock reading 0.0 on a cast that is visibly still running is read as
         fact; a blank is read as "not known", which is what it is. ]==]
    local clock = cfg.castTimer and OB.CastTimeText(remaining) or nil

    castText(bar.timer, "ecoTimerValue", clock)

    if clock then bar.timer:Show() else bar.timer:Hide() end

    bar:Show()
    return true
end

--[==[ Both halves, for the restyle path. The per-frame pass calls the update on
     its own. ]==]
--[==[ Every cast bar shown with a sample on it, or put back to whatever is
     really happening. See `SetDragMode`. ]==]
function M:PreviewCastBars(on)
    for id in pairs(CAST_BARS) do
        local bar = self:CastBar(id)

        if bar then
            if on then
                self:StyleCastBar(id)

                bar:SetValue(0.6)
                castText(bar.label, "ecoLabelValue", CAST_PREVIEW_NAME)
                castText(bar.timer, "ecoTimerValue", "1.8")

                bar.label:Show()
                bar.timer:Show()

                if bar.icon then
                    bar.icon:SetTexture(UNKNOWN_SPELL_ICON)
                    if self:Config().castIcon then bar.icon:Show() end
                end

                bar:Show()
                bar.ecoPreview = true
            elseif bar.ecoPreview then
                --[[ Cleared so the next real pass writes rather than deciding it
                     already says the right thing. ]]--
                bar.ecoPreview = nil
                bar.ecoLabelValue = nil
                bar.ecoTimerValue = nil
                bar.ecoIconSpell = nil

                bar:Hide()
            end
        end
    end

    return true
end

function M:ApplyCastBar(id, unit, enabled)
    self:StyleCastBar(id)
    return self:UpdateCastBar(id, unit, enabled)
end

function M:TargetCastBarOn()
    return self:Config().targetCastBar and self:Owns(FRAMES[2])
end

function M:ApplyTargetCastBar()
    return self:ApplyCastBar("target", "target", self:TargetCastBarOn())
end

--[==[ The pass that actually animates them. Nothing here touches a texture, a
     font or an anchor. ]==]
function M:UpdateCastBars()
    self:UpdateCastBar("target", "target", self:TargetCastBarOn())
    self:UpdateCastBar("player", "player", self:Config().playerCastBar)
end

--[==[ Owning the player frame is not required for your own cast bar. It is a
     bar beside the frame rather than a part of it, and somebody running
     Blizzard's player frame still has nothing telling them what they are
     channelling. ]==]
function M:ApplyPlayerCastBar()
    return self:ApplyCastBar("player", "player", self:Config().playerCastBar)
end

function M:StyleTargetAuras()
    if not self:Owns(FRAMES[2]) or not legacyAssetsInstalled() then
        self:HideAuraSkins()
        return false
    end
    local shade = self:DarkShade()
    for i = 1, 5 do self:SkinAura(getglobal("TargetFrameBuff" .. i), 1, shade, shade, shade) end
    for i = 1, 4 do self:SkinAura(getglobal("TargetofTargetFrameDebuff" .. i), -1, 1, 0, 0) end
    return true
end

function M:StyleFrame(entry)
    if not self:Owns(entry) then return false end
    if not getglobal(entry.frame) then return false end

    --[==[ **A right-drag over the frame turns the camera rather than being
         eaten by it**, and a right-*click* still opens the menu it always did.

         Here rather than in `MakeMovable`, which is where it was first put and
         which only runs while drag mode is on -- so the behaviour existed for
         as long as somebody was rearranging their frames and not afterwards.
         Idempotent, so a styling pass that runs constantly costs one field
         read. See `OB.AttachCameraDrag`. ]==]
    OB.AttachCameraDrag(getglobal(entry.frame))

    local cfg = self:Config()
    local color = self:UnitColor(entry.unit)

    --[[ **The target's horizontal nudges are mirrored, like its name's.**

         The target frame's art is the player's reversed, so its numbers sit
         on the opposite side and a positive nudge has to travel the other
         way. Without it, nudging both frames right moves them apart -- which
         is what the donor mirrors for, and which this already did for the
         name and not for the numbers.

         Y is untouched: up is up on both. ]]--
    local id = entry.id
    local mirror = (id == "target") and -1 or 1

    self:StyleBar(getglobal(entry.health), self:FrameSetting(id, "healthSize"),
            self:FrameSetting(id, "healthX") * mirror,
            self:FrameSetting(id, "healthY"), color)

    --[[ The power bar keeps the client's colour. Mana is blue, rage is red and
         energy is yellow, and those are not preferences -- they are what the
         numbers mean. Only its font and position are ours. ]]--
    self:StyleBar(getglobal(entry.power), self:FrameSetting(id, "powerSize"),
            self:FrameSetting(id, "powerX") * mirror,
            self:FrameSetting(id, "powerY"), nil)

    local name = getglobal(entry.name)

    if name then
        local outline
        local look = OB.Look("unitframes")
        if self:FrameSetting(id, "nameOutline") or look.fontOutline then
            outline = "OUTLINE"
        end


        --[[ The smaller frames' one-point drop is in their migrated sizes now,
             not subtracted here. ]]--
        local size = self:FrameSetting(id, "nameSize")


        name:SetFont(OB.FontPath("unitframes"), self:TextSize(size), outline)

        --[[ **The name's own colour, when this frame asks for one.**

             Left alone otherwise: the client already colours a name usefully
             -- a player's class, an NPC's reaction -- and overwriting that by
             default throws information away for a setting nobody chose.

             Stored positionally as `{ r, g, b, a }`, like every colour here.
             Read as `c.r` it never fires at all, which from the outside is
             a setting that does nothing. ]]--
        --[==[ **The name keeps the colour it already carries.**

             There was an override here, off by default, and the comment above
             it argued against itself: a name is already coloured by something
             that means something -- a player's class, an NPC's reaction -- and
             painting over that throws information away. A setting whose own
             defence is "leave it alone" is not a setting.

             Removed rather than defaulted, so there is nothing left to switch
             on by accident. Migration 36 clears what profiles were holding. ]==]

        --[[ **Hung off the top edge of the health bar, not centred on the
             frame.**

             The original's anchor, and it is not a detail: a name centred on
             the frame lands in the middle of the portrait. Anchoring to the bar
             also keeps the player and target names level with each other for
             free, because their bars are the same size at the same height.

             Set every pass rather than only when the sliders are off zero, for
             the same reason the text offsets are -- otherwise the name never
             comes back when the slider does. ]]--
        if name.SetPoint then
            local bar = getglobal(entry.health)

            name:ClearAllPoints()

            if entry.id == "pet" and cfg.improvedPet then
                -- UFI gives the slim pet its own fixed baseline rather than the
                -- player/target name anchor. Keep ECO's nudge sliders additive
                -- so the port remains configurable without losing that geometry.
                name:SetPoint("BOTTOMRIGHT", getglobal(entry.frame), "BOTTOMRIGHT",
                        -125 + self:FrameSetting(id, "nameX"),
                        6 + self:FrameSetting(id, "nameY"))
            --[[ **Target of target keeps the client's own name position.**

                 The donor changes this frame's name font and nothing else
                 about it -- no re-anchoring. Giving it the player and
                 target's "hung off the top of the health bar" geometry is
                 giving a 93x45 frame a layout drawn for a 232x100 one, and
                 it looked like it.

                 Its own geometry was already put back by
                 StyleTargetTargetGeometry, so the nudges are applied to
                 that rather than replacing it. ]]--
            elseif entry.id == "targettarget" then
                local nx = self:FrameSetting(id, "nameX")
                local ny = self:FrameSetting(id, "nameY")

                if nx == 0 and ny == 0 then
                    self:RestoreObject(entry.name, true)
                else
                    name:SetPoint("CENTER", getglobal(entry.frame), "CENTER",
                            nx, ny)
                end

            elseif bar then
                --[[ **The target's X is mirrored**, because the target frame's
                     art is. Without it, nudging both names right moves them
                     apart rather than together. ]]--
                local x = self:FrameSetting(id, "nameX")
                --[[ The same mirror the numbers use, kept as one rule. ]]--
                x = x * mirror

                name:SetPoint("CENTER", bar, "TOP", x, self:FrameSetting(id, "nameY") + 5)
            else
                name:SetPoint("CENTER", getglobal(entry.frame), "CENTER",
                        self:FrameSetting(id, "nameX"),
                        self:FrameSetting(id, "nameY"))
            end
        end
    end

    self:StylePortrait(entry)
    self:StyleFrameArt(entry)

    return true
end

--[[ **Writing the numbers on.**

     Separate from the styling because it happens on a different clock: a frame
     is styled when a setting changes and re-lettered every time somebody takes
     damage. Doing both together would re-apply a font sixty times a second for
     no reason.

     **One writer, which is the whole point.** This goes through the client's own
     entry point rather than setting the strings itself, so the event path and
     the client's own `OnValueChanged` path end up in the same code. The port had
     two writers and they fought; the one that ran last won, and which that was
     depended on the order the events happened to arrive. ]]--
function M:UpdateText(entry)
    if not self:Owns(entry) then return false end

    --[==[ **Two named bars, not a table built to hold two named bars.**

         `ipairs({ entry.health, entry.power })` allocated a table and an
         iterator on every call, and this runs at ten hertz against four frames
         -- forty throwaway tables a second, for the whole session, to loop over
         a pair that is known at the point of writing.

         That is what makes a client hitch every few seconds rather than run
         slowly: nothing here is *slow*, it just keeps handing the collector
         work. ]==]
    self:RefreshBarText(getglobal(entry.health))
    self:RefreshBarText(getglobal(entry.power))

    return true
end

--[==[ **Re-rendered when the numbers changed, and once a second regardless.**

     `TextStatusBar_UpdateTextString` builds the "2.10k / 3.06k (69%)" string
     from scratch every call. This pass runs at ten hertz against four frames to
     undo Octo re-showing its own white status text -- so nine times in ten it
     was rebuilding a string identical to the one already on screen, forty times
     a second, for the whole session.

     Health and mana are stable most of the time: standing still, in a queue, at
     a vendor, nothing changes and none of that work is worth doing.

     **The unconditional pass stays**, once a second. The repair is about text
     somebody else re-showed, and that can happen without any value moving --
     so it cannot be driven purely by change, or the case this exists for is
     exactly the case it stops covering. One second is the longest anybody would
     see the wrong text and is still a fortieth of the work. ]==]
function M:RefreshBarText(bar, force)
    if not bar or type(TextStatusBar_UpdateTextString) ~= "function" then
        return false
    end

    if not force and bar.GetValue and bar.GetMinMaxValues then
        local value = bar:GetValue()
        local _, maximum = bar:GetMinMaxValues()

        if bar.ecoTextValue == value and bar.ecoTextMax == maximum then
            return false
        end

        bar.ecoTextValue, bar.ecoTextMax = value, maximum
    end

    TextStatusBar_UpdateTextString(bar)
    return true
end

-- ---------------------------------------------------------------------------
-- moving the frames
-- ---------------------------------------------------------------------------

--[[ **The original's Unlock button, as a mode rather than a lock.**

     On, drag, off -- the same shape the action bars use, and for the same
     reason: a permanently draggable player frame is one you move by accident
     every time you right-click your own buffs.

     **Only the player and target frames**, which is what the original offers.
     The pet and target-of-target frames are anchored to those two by the client
     and follow them; the party frames are Blizzard's own managed layout and
     moving one individually is a different feature. ]]--
--[[ **Every frame edit mode can move has to be a frame whose position is
     kept**, or dragging one works until the next reload and then quietly
     undoes itself -- which is worse than not being draggable at all. The
     target-of-target and pet frames were movable and unsaved. ]]--
--[==[ **Which frames edit mode moves, which is not always the client's.**

     This was a fixed list of the client's four, and two of them are not what is
     on screen: when this module draws its own target-of-target and pet it hides
     the client's and puts its own in their place. Drag mode was making the hidden
     one movable, so the drag worked perfectly on a frame nobody can see and the
     one you were looking at never moved. That is the reported "they need to be
     draggable via edit mode".

     Resolved when asked rather than listed, because which of the two is on
     screen depends on a setting that changes without a reload -- and both the
     drag registration and the position restore read this, so they cannot
     disagree about which frame a saved position belongs to. ]==]
function M:MovableFrames()
    local out = { "PlayerFrame", "TargetFrame" }

    for id, spec in pairs(SMALL_FRAMES) do
        table.insert(out, self:OwnsSmall(id) and spec.name or spec.client)
    end

    return out
end

function M:DragMode()
    return self.dragging and true or false
end

function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("unitframes") then
        Say("switch the Unit Frames module on first.")
        return false
    end

    self.dragging = on and true or nil

    --[==[ **The cast bars are on screen while unlocked, whatever is casting.**

         They are registered as movable and they exist only during a cast, so
         arranging them meant finding something to cast at and doing the whole
         layout inside three seconds. That is a race rather than an arrangement,
         and it is the same fault the raid frames and the PvP countdown each had
         and each wrote down: *shown while unlocked even with nobody in the
         group, or a raid frame layout could only be arranged inside a raid.*

         A sample name and a full bar rather than an empty rectangle, because an
         empty one says nothing about how wide the thing is or what the text on
         it will look like -- which is most of what somebody is arranging. ]==]
    self:PreviewCastBars(on and true or false)

    --[[ Restyled first, because the small frames decide whether to be on screen
         from this very flag: with no target-of-target they show a placeholder
         while the mode is on and hide again when it is off. Doing it after
         `MakeMovable` would mark a frame that is not shown yet, and edit mode
         only outlines what is. ]]--
    self:StyleSmallFrames()

    local movable = self:MovableFrames()

    for i = 1, table.getn(movable) do
        self:MakeMovable(getglobal(movable[i]))
    end

    if self.dragging then
        Say("drag mode on. Move the player, target, target-of-target "
                .. "and pet frames, then switch it off. "
                .. "'/eq frames reset' puts them back.")
    else
        Say("drag mode off.")
    end

    return true
end

--[[ One frame, made movable or not.

     **The border art is tinted green while the mode is on**, which is the
     original's own signal and is worth keeping: these frames are always on
     screen, so "can I drag this right now" is not otherwise answerable without
     trying it.

     `SetUserPlaced` looks like the way to make a drag stick, and is the
     opposite. It hands the position to the client, which caches it and puts
     it back on the next login -- over this addon, with its own anchor. The
     drag is stored here instead, and the frame is kept off the client's
     books. See PlaceFrames. ]]--
function M:MakeMovable(frame)
    if not frame or not frame.SetMovable then return false end

    local art = getglobal((frame:GetName() or "") .. "Texture")
            or getglobal((frame:GetName() or "") .. "TextureFrameTexture")

    if not self.dragging then
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        --[[ **Left movable, because these are the client's frames and this addon
             is not the only thing that touches them.**

             A neighbour that offers its own "hold two keys to drag" makes the
             frame movable, and one of them calls `SetUserPlaced` *before*
             `SetMovable` -- which throws "Frame PlayerFrame is not movable or
             resizable" the moment it meets a frame this addon has locked. The
             drag scripts are gone by here, so movable costs nothing: without a
             handler nothing starts a drag. Locking it only breaks somebody
             else. ]]--
        frame:SetMovable(true)

        --[[ Back to whatever dark mode says, not to white -- restoring white
             here would undo the tint every time the mode was switched off. ]]--
        self:StyleFrameArt({ frame = frame:GetName() })

        --[[ StyleFrameArt is keyed on the client's frame names, so it has
             nothing to say about this module's own frames and their green would
             have stayed on after the mode was switched off.

             Back to the dark shade rather than to white -- white is only right
             when dark mode is off, and restoring it unconditionally would turn
             these two frames bright the first time anybody dragged them. ]]--
        if frame.art and frame.art.SetVertexColor then
            local shade = self:DarkShade()
            frame.art:SetVertexColor(shade, shade, shade)
        end

        return true
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")

    --[[ Named for edit mode's outline, from the frame's own global -- these are
         Blizzard's frames rather than ours and there is no friendlier name to
         hand than the one the client gave them. ]]--
    OB.MarkMovable(frame, frame:GetName() or "Unit Frame")

    --[[ Ours keep their art on the frame rather than in a global named after
         it, so the tint has to look in both places or this module's own frames
         are the only ones with no sign they can be dragged. ]]--
    art = art or frame.art

    if art and art.SetVertexColor then art:SetVertexColor(0, 1, 0) end

    frame:SetScript("OnDragStart", function() this:StartMoving() end)

    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()

        --[[ Off the client's books, not on: the position below is this
             addon's to keep. ]]--
        if this.SetUserPlaced then this:SetUserPlaced(false) end
        EquadisClassicOverhaul.modules.unitframes:StorePosition(this)
    end)

    return true
end

--[[ Where a frame ended up, as an offset from the centre of the screen.

     **From the centre, not from a corner**, which is the rule the meters and the
     action bars already follow: a position measured from an edge is a different
     place on a different resolution, and this addon has been bitten by that
     before. The centre is the one point every screen shares. ]]--
function M:StorePosition(frame)
    if not frame or not frame.GetLeft or not frame:GetLeft() then return false end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.positions[frame:GetName() or "?"] = {
        x = OB.Round((frame:GetLeft() + (frame:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((frame:GetBottom() + (frame:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[[ A stored position put back on, or nothing at all if there is none -- in
     which case the client's own anchor stands, which is where the frame has
     always been. ]]--
--[[ **The client keeps its own copy of where these frames are, and it wins.**

     `SetUserPlaced(true)` does not mean "remember this for me". It hands the
     frame's position to the *client*, which writes it to `layout-cache.txt` on
     logout and puts it back on login -- with its own `TOPLEFT` anchor, and
     after this addon has already placed the frame. So the saved position is
     applied, then quietly overwritten, every single login.

     That is what "the unit frames are still misaligned" was. The cache on this
     install still holds coordinates left by two addons that are now switched
     off entirely, and they were being restored on top of everything this module
     did. No amount of correcting geometry could win against it, because the
     geometry was never what moved them.

     So the frames are taken *off* the client's books -- `SetUserPlaced(false)`
     -- and this addon's own saved position is the only one. A position this
     addon stores is one it can also reset, which is not true of the cache. ]]--
function M:PlaceFrames()
    local cfg = self:Config()
    if not cfg.positions then return false end

    local movable = self:MovableFrames()

    for i = 1, table.getn(movable) do
        local frame = getglobal(movable[i])
        local saved = cfg.positions[movable[i]]

        if frame and saved and frame.SetPoint then
            --[==[ **`SetUserPlaced` raises on a frame that is not movable.**

                 `Frame EquadisClassicOverhaulToT is not movable or resizable` --
                 and this runs inside `OnBind`, which the binder calls through a
                 `pcall`. So one of this addon's own frames, never marked
                 movable, threw here and took the **entire module** out of
                 `OB.features`: no events, no tick, no restyle when a setting
                 changed, and `HideFeature` putting the client's own frame back
                 afterwards.

                 That is what "the bars are not aligned with the frame overlay"
                 has been. Five passes were spent on geometry that was correct
                 and never ran, and every one of them ended at "something
                 overwrote it" -- which was this module being unbound half a
                 second after it styled.

                 The presence check that was here tested whether the *method*
                 exists, which it always does. What matters is whether the frame
                 will accept it, and only the frame can say. Two failures in this
                 addon now from that same shape -- `GetCVar` was the other -- so
                 the rule is worth stating: **a call that can raise is not
                 guarded by checking that it exists.** ]==]
            if frame.SetUserPlaced and frame.IsMovable and frame:IsMovable() then
                frame:SetUserPlaced(false)
            end

            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
        end
    end

    return true
end

--[[ Forgotten rather than moved back, so the client's own anchor takes over
     again -- which is a place that exists on every resolution, unlike any
     coordinate this addon could pick. ]]--
function M:ResetPositions()
    self:Config().positions = {}

    if type(OB.RequireReload) == "function" then
        OB.RequireReload("unit frame positions were reset")
    else
        Say("frame positions forgotten. Reload to put them back.")
    end

    return true
end

-- ---------------------------------------------------------------------------
-- the party, which is four of the same thing
-- ---------------------------------------------------------------------------

--[[ **Built once each, not once per call.**

     This made a fresh table and seven concatenated strings every time it was
     asked, and `Apply` asks for all four party entries twice -- then `OnEvent`
     calls `Apply` for every event this module listens to, which includes
     `UNIT_HEALTH`, `UNIT_MANA` and `UNIT_AURA` **for every unit in the group**.
     In a raid that is hundreds of events a second, each one throwing away eight
     tables and fifty-six strings describing frames whose names have not changed
     since the client was written.

     That was the largest single source of garbage in the addon, and garbage on
     1.12 is not paid for in CPU at the moment you make it -- it is paid for
     later, all at once, as the collection pause that reads as the game
     stuttering. `EquadisClassicOverhaulHUD:OnUpdate` sat at the top of the
     game's own profiler because of it.

     The entries are immutable: four frames, fixed names, fixed units. There was
     never a reason to build them more than once. ]]--
local partyEntries = {}

function M:PartyEntry(i)
    local entry = partyEntries[i]
    if entry then return entry end

    entry = {
        id = "party" .. i,
        setting = "replaceParty",
        frame = "PartyMemberFrame" .. i,
        health = "PartyMemberFrame" .. i .. "HealthBar",
        power = "PartyMemberFrame" .. i .. "ManaBar",
        name = "PartyMemberFrame" .. i .. "Name",
        portrait = "PartyMemberFrame" .. i .. "Portrait",
        unit = "party" .. i,
    }

    partyEntries[i] = entry
    return entry
end

-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

--[[ **Re-target somebody who vanished.**

     Feign Death, Vanish and Invisibility all clear your target, and the target
     you had is almost always the target you still want.

     `TargetByName` is noisy about failing -- it plays a sound and writes an
     error -- so both are silenced across the call and put straight back. That is
     the original's trick, from SHIRSIG's Retarget, and it is the only way: there
     is no quiet form of the call.

     **Only players.** A mob that vanished is a mob that died, and re-targeting a
     corpse is not a service. ]]--
function M:RetargetFeignOrHostile()
    if self:IsFeigning("target") then return true end
    return type(UnitCanAttack) == "function" and UnitCanAttack("player", "target") and true or false
end

function M:RetargetStep()
    if not self:Config().retarget then
        self.retargetUnit, self.retargetDead, self.retargetLost = nil, nil, nil
        return false
    end

    local target = UnitName("target")
    if target and UnitIsPlayer("target") then
        self.retargetUnit = target
        self.retargetDead = type(UnitIsDead) == "function" and UnitIsDead("target") and true or false
        self.retargetLost = false
        return false
    end

    --[[ **Only when the target was taken away, never when it was changed.**

         This fired whenever the current target was not a *player* -- which
         includes every mob in the game. Tab onto an NPC and the check above
         declined to record it, this one fell straight through, and the last
         player you had was re-targeted within a frame. Tab-targeting read as
         broken: press it and nothing happens, or you snap back to somebody
         standing behind you.

         The feature is for Vanish, Feign Death and Invisibility -- things that
         *clear* your target. A target you can see is a target you chose, and
         choosing one is not a problem to be corrected. ]]--
    if UnitExists("target") then return false end

    if not self.retargetUnit or type(TargetByName) ~= "function" then return false end

    local oldSound, oldErrors = PlaySound, UIErrorsFrame_OnEvent
    local quiet = function() end
    PlaySound, UIErrorsFrame_OnEvent = quiet, quiet
    TargetByName(self.retargetUnit, true)
    PlaySound, UIErrorsFrame_OnEvent = oldSound, oldErrors

    if UnitExists("target") then
        local nowDead = type(UnitIsDead) == "function" and UnitIsDead("target") and true or false
        if not (self.retargetLost or (not self.retargetDead and nowDead
                and self:RetargetFeignOrHostile())) then
            if type(ClearTarget) == "function" then ClearTarget() end
            self.retargetUnit, self.retargetLost = nil, false
            return false
        end
        return true
    end

    -- Failed once means the unit genuinely disappeared (Vanish/Feign/out of
    -- visibility). From now on, the first successful reacquisition is kept.
    self.retargetLost = true
    return false
end

function M:Apply()
    if not OB.ModuleEnabled("unitframes") then return end
    self:RememberOriginals()

    --[[ The client's own cast bar, put away or given back. Here rather than in
         the per-frame styling: it is one frame and it belongs to nobody's
         entry. See `StyleBlizzardCastBar`. ]]--
    self:StyleBlizzardCastBar()

    -- A per-frame switch means "give this frame back", not merely "stop touching
    -- it from now on". Undo a previous takeover before styling the frames still
    -- owned by ECO.
    for i = 1, table.getn(FRAMES) do
        if not self:Owns(FRAMES[i]) then self:RestoreEntry(FRAMES[i]) end
    end
    -- Geometry first, styling second. This makes toggles reversible without the
    -- pet/compact restore pass wiping ECO's selected bar texture afterwards.
    self:StylePlayerGeometry()
    self:StyleTargetGeometry()
    self:StyleTargetTargetGeometry()
    self:StylePetGeometry()

    for i = 1, table.getn(FRAMES) do
        self:StyleFrame(FRAMES[i])
        self:UpdateText(FRAMES[i])
    end
    self:StyleGlow()
    self:StylePetHappiness()
    self:StyleTargetAuras()
    self:ApplyAuraTimers("target")
    self:ApplyTargetCastBar()
    self:ApplyPlayerCastBar()
    self:StyleSmallFrames()

    local player = getglobal("PlayerFrameHealthBar")
    if player then self:ColorUpdate(player) end
end

--[[ **The four units this module actually draws.**

     Party frames moved to their own Party & Raid Frames subsystem, so this
     module now owns only player, target, target-of-target and pet. `UNIT_HEALTH`,
     `UNIT_MANA` and the rest still fire for every unit the client knows about;
     dropping party/raid events here prevents this module from fighting the
     group-frame modules or doing work for pixels it no longer owns.

     Anything not in this table changes no pixels this module owns, so there is
     nothing to redraw and the event is dropped. Events without a unit are not
     filtered: `PLAYER_ENTERING_WORLD`, `PARTY_MEMBERS_CHANGED` and the rest
     genuinely do concern every frame. ]]--
--[[ **The units this module draws, which no longer include the party.**

     Party frames are their own subsystem now. Two modules restyling the
     same client objects is where the duplicate group-frame text and
     visibility bugs came from, so this one stops at the four frames that
     have pages of their own. ]]--
local DRAWN_UNITS = {
    player = true, target = true, targettarget = true, pet = true,
}

function M:DrawsUnit(unit)
    if not unit then return false end
    return DRAWN_UNITS[unit] and true or false
end


--[==[ **The events that change a number and nothing else.**

     Health, power and their maximums. An aura is deliberately not here: a buff
     arriving can change what the frame draws -- the aura row, a dispel outline,
     the target's cast bar -- so it takes the long way. ]==]
local VALUE_EVENTS = {
    UNIT_HEALTH = true,
    UNIT_MAXHEALTH = true,
    UNIT_MANA = true,
    UNIT_MAXMANA = true,
    UNIT_RAGE = true,
    UNIT_ENERGY = true,
    UNIT_FOCUS = true,
}

--[==[ Which of the four frames draws this unit, or nothing. The same question
     `DrawsUnit` answers, returning the entry rather than a yes. ]==]
function M:EntryForUnit(unit)
    if not unit then return nil end

    for i = 1, table.getn(FRAMES) do
        local entry = FRAMES[i]
        if entry.unit == unit and self:Owns(entry) then return entry end
    end

    return nil
end

function M:OnEvent()
    --[[ **After the client has had its say.**

         The client restores any frame it considers user-placed from its own
         layout cache, and it does that after this module binds -- which is how
         a stale cache entry from an addon that is no longer even switched on
         kept winning. Putting the saved position back here is what makes this
         addon's copy the one that stands. ]]--
    if event == "PLAYER_ENTERING_WORLD" then
        self:PlaceFrames()
    end

    if event == "PLAYER_FLAGS_CHANGED" and (not arg1 or arg1 == "player") then
        --[[ The only moment the grace period is observable on a build with no
             `GetPVPTimer`. See `NotePVPFlags`. ]]--
        self:NotePVPFlags()

        self.nextPVPTimerRefresh = nil
        self:UpdatePVPTimer(true)
    elseif event == "UNIT_FACTION" and arg1 == "player" then
        self.nextPVPTimerRefresh = nil
        self:UpdatePVPTimer(true)
    end

    -- Record real hunter values only while alive. UNIT_AURA is included so the
    -- first frame drawn after Feign can immediately read the saved value.
    if (event == "UNIT_HEALTH" or event == "UNIT_MANA" or event == "UNIT_AURA") and arg1 then
        self:NoteFeign(arg1)
    end

    if event == "PLAYER_TARGET_CHANGED" then
        self:MobTargetChanged()
    elseif event == "UNIT_COMBAT" and arg1 == "target" then
        -- Damage accumulation changes no pixels by itself; UNIT_HEALTH follows
        -- with the percentage delta. Avoid restyling every frame for every hit.
        self:MobCombat(arg4)
        return
    elseif event == "UNIT_HEALTH" and arg1 == "target" then
        self:MobHealthUpdate()
    end

    --[[ A per-unit event about a unit nothing here draws is dropped before the
         restyle. `arg1` is only set by the `UNIT_*` events, so this leaves
         every frame-wide event -- entering the world, the party changing,
         shapeshift forms -- to apply as they always did. ]]--
    if arg1 and not self:DrawsUnit(arg1) then return end

    --[==[ **A number changing is not a reason to restyle four frames.**

         `Apply` restores anything given back, redoes the geometry of all four
         frames, restyles their art and fonts, repaints the glow, the pet's
         happiness, the target's auras and both cast bars. That is the right
         answer when a *setting* changed and a very expensive one when a health
         bar moved.

         In a raid your own health moves constantly, and a profile of
         eighty-three seconds showed thirteen thousand events reaching this
         handler and thirty-one megabytes of garbage behind them. None of that
         work was needed: art does not change because somebody took damage.

         So the pure value events write the numbers on the frame that changed and
         stop. Everything else -- auras, target changes, form changes, entering
         the world -- still goes the long way, because those really can change
         what a frame looks like. ]==]
    if VALUE_EVENTS[event] and arg1 then
        local entry = self:EntryForUnit(arg1)

        if entry then
            self:UpdateText(entry)

            --[[ The health bar's colour follows its value on the frames that
                 colour by health, so the one bar that moved is recoloured. ]]--
            local bar = getglobal(entry.health)
            if bar then self:ColorUpdate(bar) end
        end

        return
    end

    self:Apply()
end

-- UFI used per-frame OnUpdate for class portraits and SHIRSIG retarget. ECO has
-- one shared ticker, so both live here instead of installing competing globals.
function M:OnUpdate(now)
    self:RetargetStep()

    --[==[ Every frame, deliberately. A cast bar that moved only when an event
         fired would cross its gap in three or four visible jumps. ]==]
    self:UpdateCastBars()

    --[==[ **The debuff timers, which had no clock at all.**

         `ApplyAuraTimers` was called from `Apply` and from nowhere else -- a
         full restyle, which happens at login and when a setting changes. So the
         number was written once and then never again: it could not count down,
         and a debuff that landed after the last restyle never got one. Reported
         as unit frame debuffs missing their timers, and that is exactly what it
         was.

         The nameplates have always had this tick; this frame never did. ]==]
    if not self.nextAuraTimers or now >= self.nextAuraTimers then
        self.nextAuraTimers = now + AURA_TIMER_INTERVAL
        self:ApplyAuraTimers("target")
    end

    --[==[ **Target-of-target changes with no event to announce it.**

         1.12 raises nothing when your target picks a new one, which is why the
         client polls for it and why the old repair pass lived on this tick. Ten
         hertz is what the portrait refresh beside it already uses and is fast
         enough that the frame is never visibly behind. ]==]
    if not self.nextSmallRefresh or now >= self.nextSmallRefresh then
        self.nextSmallRefresh = now + 0.10
        self:StyleSmallFrames()
    end

    self:ReassertAuxBarTexts()

    --[[ Octo/Turtle can restore the stock Player/Target bar anchors after the
         UNIT_* event has already reached addons. When that happens the health
         bar drops back to Blizzard's 12px row underneath the name strip and a
         frame that should have two rows suddenly looks like three (name / HP /
         power). Reassert only the lightweight geometry/name anchors here; do
         not restyle textures/fonts every rendered frame. ]]--
    if not self.nextMainGeometryRefresh or now >= self.nextMainGeometryRefresh then
        self.nextMainGeometryRefresh = now + 0.10

        if self:Owns(FRAMES[1]) then
            self:StylePlayerGeometry()

            local name = getglobal(FRAMES[1].name)
            local bar = getglobal(FRAMES[1].health)
            if name and bar and name.SetPoint then
                name:ClearAllPoints()
                name:SetPoint("CENTER", bar, "TOP",
                        self:FrameSetting("player", "nameX"),
                        self:FrameSetting("player", "nameY") + 5)
            end
        end

        if self:Owns(FRAMES[2]) then
            self:StyleTargetGeometry()

            local name = getglobal(FRAMES[2].name)
            local bar = getglobal(FRAMES[2].health)
            if name and bar and name.SetPoint then
                name:ClearAllPoints()
                name:SetPoint("CENTER", bar, "TOP",
                        -self:FrameSetting("target", "nameX"),
                        self:FrameSetting("target", "nameY") + 5)
            end
        end

        -- ToT's border is its texture region. Some forks repaint that region
        -- after target changes; only repair it when it is actually missing.
        if self:Owns(FRAMES[3]) then
            local art = getglobal(FRAMES[3].art)
            if art then
                local texture = art.GetTexture and art:GetTexture() or nil
                if not texture and art.SetTexture then
                    art:SetTexture("Interface\\TargetingFrame\\UI-TargetofTargetFrame")
                end
                if art.IsShown and not art:IsShown() and art.Show then art:Show() end
                if art.GetAlpha and art.SetAlpha and (art:GetAlpha() or 0) == 0 then
                    art:SetAlpha(1)
                end
            end
        end
    end

    -- Octo can re-show its own white status strings after ECO's UNIT_HEALTH /
    -- UNIT_MANA handler has already run. Reassert only the four Blizzard unit
    -- frames ECO owns at 10 Hz. This deliberately replaces the earlier global
    -- ShowTextStatusBarText/HideTextStatusBarText hook, which was capable of
    -- disturbing unrelated OmniBars resource text.
    if not self.nextStatusTextRefresh or now >= self.nextStatusTextRefresh then
        self.nextStatusTextRefresh = now + 0.10

        --[==[ The once-a-second pass that does not care whether anything
             changed -- see `RefreshBarText`. ]==]
        local force = not self.nextForcedTextRefresh
                or now >= self.nextForcedTextRefresh

        if force then self.nextForcedTextRefresh = now + 1 end

        for i = 1, table.getn(FRAMES) do
            local entry = FRAMES[i]

            if self:Owns(entry) then
                if force then
                    self:RefreshBarText(getglobal(entry.health), true)
                    self:RefreshBarText(getglobal(entry.power), true)
                else
                    self:UpdateText(entry)
                end
            end
        end
    end

    -- The PvP grace timer only changes once per second, but checking the client
    -- value four times a second makes the first/last displayed second feel
    -- immediate without doing string work every frame.
    if not self.nextPVPTimerRefresh or now >= self.nextPVPTimerRefresh then
        self.nextPVPTimerRefresh = now + 0.25
        self:UpdatePVPTimer(false)
    end

    if self:Config().classPortrait then
        -- Target-of-target changes have no useful event in 1.12. A light 10 Hz
        -- refresh is enough to beat Blizzard repainting the portrait without
        -- paying UFI's seven portrait writes every rendered frame.
        if not self.nextPortraitRefresh or now >= self.nextPortraitRefresh then
            self.nextPortraitRefresh = now + 0.10

            --[[ Noted so switching the setting off can undo it. ]]--
            self.classPortraitsApplied = true
            -- UFI applies class portraits to player, target and target-target,
            -- not the pet. (Pets are not players and restoring their portrait
            -- every tick would fight the pet frame's own portrait updates.)
            for i = 1, 3 do
                if self:Owns(FRAMES[i]) then self:StylePortrait(FRAMES[i]) end
            end
        end
    elseif self.classPortraitsApplied then
        --[[ **Switched off has to undo itself.**

             The refresh above lives inside the `if`, so turning the setting off
             stopped it running -- and `StylePortrait`, which is what calls
             `RestorePortrait`, stopped being called with it. The class icon
             applied while the setting was on stayed on the frame, and nothing
             in the addon would ever take it off again.

             Once, not every tick: `SetPortraitTexture` is the client's own job
             from here, and repainting it ten times a second would fight the
             portrait updates it does for itself. ]]--
        self.classPortraitsApplied = nil

        for i = 1, 3 do
            if self:Owns(FRAMES[i]) then self:RestorePortrait(FRAMES[i]) end
        end

    end
end

function M:OnBind()
    --[[ Before anything is drawn: an older build's shadow copies would
         otherwise outrank General for the whole session. ]]--
    self:MigrateFrameOverrides()
    self:RememberOriginals()
    self:InstallTextHooks()
    self:PlaceFrames()
    self:MobTargetChanged()
    self:Apply()
    self:UpdatePVPTimer(true)
end

function M:OnUnbind()
    self.retargetUnit, self.retargetDead, self.retargetLost = nil, nil, nil
    self.mobCurrent = nil
    self.nextPortraitRefresh = nil
    self.nextPVPTimerRefresh = nil
    self.nextMainGeometryRefresh = nil
    self:HidePVPTimer()
    self:HideAuraSkins()
    self:HideBarBorders()
    self:HideAllSyntheticBarText()
    self:RestoreOriginals()
end

function M:OnStyle()
    self:Apply()
end

function M:OnDraw() end
