--[[ Equadis' Classic Overhaul :: action bars

  **The baseline**, ported from DragonflightUI-Reforged's Bars module by Guzruul
  and Stormhand (MIT -- see NOTICE). What is here is the load-bearing half: where
  the buttons go and what the text on them looks like.

  Blizzard's 1.12 action bars are one fixed arrangement. The buttons are real
  frames with real names and they can be moved, scaled and re-parented -- what
  cannot be done is any of it *from the interface*, because there is none. That
  is the entire gap this fills, and it is why the port is mostly arithmetic.

  **What is deliberately not here yet, and why.**

  The Dragonflight *look* -- the bar backing plate, the gryphons -- is art, and
  art is the one thing a port cannot simply take. Some of those files are
  reworked Blizzard textures, which nobody downstream can relicense, so they need
  a decision rather than a copy. The layout engine is useful without them and
  they drop in on top when it is made.

  Also absent: the paging buttons, dark mode and the bar tinting. None is load
  bearing and each is a slice of its own.

  Nothing here is a bar in this addon's sense. There is no `OB.NewBar`, no slot
  and no geometry table -- these are the client's own frames, moved. Same shape
  as the chat module: `renders = "none"`, and what it owns is somebody else's
  furniture.
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "Action Bars") end

-- ---------------------------------------------------------------------------
-- what the client calls things
-- ---------------------------------------------------------------------------

--[[ **Every action button family in 1.12, and the binding prefix each answers
     to.**

     The two halves are not the same and cannot be derived from one another,
     which is exactly the sort of thing that gets written as one list and is
     wrong for two of the entries. `PetActionButton` binds to
     `BONUSACTIONBUTTON`, which reads like a mistake and is not -- 1.12's bonus
     bar and pet bar share a binding namespace. `BonusActionButton` binds to
     `ACTIONBUTTON`, because it *is* the action bar while you are in a form.

     Taken from DragonflightUI's map, which had already found this out. ]]--
local FAMILIES = {
    { prefix = "ActionButton", binding = "ACTIONBUTTON", count = 12 },
    { prefix = "BonusActionButton", binding = "ACTIONBUTTON", count = 12 },
    { prefix = "MultiBarBottomLeftButton", binding = "MULTIACTIONBAR1BUTTON", count = 12 },
    { prefix = "MultiBarBottomRightButton", binding = "MULTIACTIONBAR2BUTTON", count = 12 },
    { prefix = "MultiBarRightButton", binding = "MULTIACTIONBAR3BUTTON", count = 12 },
    { prefix = "MultiBarLeftButton", binding = "MULTIACTIONBAR4BUTTON", count = 12 },
    { prefix = "ShapeshiftButton", binding = "SHAPESHIFTBUTTON", count = 10 },
    { prefix = "PetActionButton", binding = "BONUSACTIONBUTTON", count = 10 },
}

--[[ **The six fixed shapes are gone.**

     1x12, 2x6, 3x4, 4x3, 6x2, 12x1 -- every pair of whole numbers that
     multiplies to twelve. `BarShape` replaced them with arithmetic on two
     settings, which can say "five rows of five" and "eight buttons in two rows"
     and everything else the list could not.

     The table stayed behind, defined and read by nothing, and it is exactly the
     list somebody would guess was constraining them if a bar came out the wrong
     shape. A dead lookup that looks like the cause of a live bug is worse than
     no lookup at all. ]]--

--[[ A button is 36 across in 1.12 and always has been. Not read from the frame,
     because the frame may already have been scaled by the time this runs and the
     spacing arithmetic wants the unscaled size. ]]--
local BUTTON = 36

--[[ **The eight bars, and where each one starts.**

     `FAMILIES` above is what the client calls the buttons; this is what this
     addon calls the bars they make up, which is not the same list -- the main
     bar and the bonus bar are two families in one place, because a druid in form
     is looking at the same rectangle.

     The positions are the client's own defaults expressed as offsets from the
     screen edges, so switching the module on leaves everything where it already
     was and only the shape and spacing change.

     **Declared here, above everything that reads it.** It was at the bottom of
     the file, which put it out of scope for the two functions that walk it --
     `SetDragMode` and `ResetPositions` saw a nil global, and both threw the
     moment anybody pressed the button. `local` is not hoisted; a table used by a
     function defined earlier in the chunk has to be declared earlier in the
     chunk. ]]--
local BARS = {
    { name = "Main", prefix = "ActionButton", count = 12, key = "main",
      owner = "MainMenuBarArtFrame", point = "BOTTOM", x = -216, y = 30 },
    { name = "Bonus", prefix = "BonusActionButton", count = 12, key = "main",
      owner = "BonusActionBarFrame", point = "BOTTOM", x = -216, y = 30 },
    { name = "BottomLeft", prefix = "MultiBarBottomLeftButton", count = 12,
      key = "bottomLeft", owner = "MultiBarBottomLeft",
      point = "BOTTOM", x = -216, y = 72 },
    { name = "BottomRight", prefix = "MultiBarBottomRightButton", count = 12,
      key = "bottomRight", owner = "MultiBarBottomRight",
      point = "BOTTOM", x = -216, y = 114 },
    { name = "Right", prefix = "MultiBarRightButton", count = 12,
      key = "right", owner = "MultiBarRight",
      point = "RIGHT", x = -40, y = 180 },
    { name = "Left", prefix = "MultiBarLeftButton", count = 12,
      key = "left", owner = "MultiBarLeft",
      point = "RIGHT", x = -80, y = 180 },
    { name = "Pet", prefix = "PetActionButton", count = 10, key = "pet",
      owner = "PetActionBarFrame", point = "BOTTOM", x = -180, y = 156 },
    { name = "Stance", prefix = "ShapeshiftButton", count = 10,
      key = "shapeshift", owner = "ShapeshiftBarFrame",
      point = "BOTTOM", x = -180, y = 198 },
}

local M = OB.RegisterModule({
    id = "actionbars",
    name = "Action Bars",

    feature = true,

    --[==[ **Bar text had a size and a colour but no face.**

         Keybinds and macro names were drawn in whatever the profile's font
         happened to be, hardcoded to an outline, with no way to say otherwise
         -- so the two settings that existed for this text implied a third that
         did not. Taken from the shared look, which is where every other
         subsystem's font comes from. ]==]
    styled = { font = true, fontOutline = true },
    appearanceSection = "general",

    --[[ Draws nothing of its own. Every rectangle it touches belongs to the
         client; this decides where they sit. Same shape as the chat module. ]]--
    renders = "none",

    --[==[ **Frames per second and latency are the only things here that move on
         their own.**

         Everything else this module owns changes when something happens -- a bar
         is rebound, a bag is opened, a setting is edited -- so it was all driven
         from `Apply` and that was right for all of it except these two numbers,
         which have no event and were therefore only updated when something
         unrelated happened to fire one. ]==]
    tickly = true,

    --[[ Off. It moves and re-parents Blizzard's frames, which is the loudest
         thing in this addon after destroying an item -- and next to any other
         action bar addon it is a fight rather than a feature. ]]--
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
        --[[ **The main bar.** Scale, spacing and shape, which are the three
             things people actually change and the three the client offers no
             way to change at all. ]]--
        mainScale = 1,
        mainSpacing = 6,
        mainAlpha = 1,

        --[[ Rows rather than a shape, and how many of the twelve to show at
             all. One row and all twelve is what the client does, so a profile
             nobody has touched looks untouched. ]]--
        mainRows = 1,
        mainButtons = 12,

--[==[ **Shown state is here now, and it did not used to be.**

             The reasoning against it was that `SHOW_MULTI_ACTIONBAR_1` and
             friends belong to the client's own interface options, and a second
             switch for the same thing is two switches that disagree. That holds
             for an addon sitting beside the client's options. It does not hold
             for this one, whose whole job is to be the place these decisions
             are made -- and the cost of leaving it out was a fresh character
             with no extra bars and nothing in this addon able to say why.

             There is no disagreement to have: these are written through
             `SetActionBarToggles`, which is the same call the client's own
             panel makes, so the two are the same switch rather than two.

             On by default, all four. Somebody installing an action bar addon
             is not asking for one bar. ]==]
--[==[ **Empty slots drawn, rather than the bar ending where the spells
             stop.**

             The client hides a button with nothing on it, so a half-filled bar
             is a ragged row that changes width as you learn spells and moves
             everything anchored to it. `ALWAYS_SHOW_MULTIBARS` is the client's
             own answer and it has always been there, behind a checkbox in the
             options nobody opens.

             On, because a bar you are still filling is exactly when you want to
             see where the empty slots are. ]==]
        alwaysShowBars = true,

        showBottomLeft = true,
        showBottomRight = true,
        showRight = true,
        showLeft = true,

        bottomLeftScale = 1,
        bottomLeftSpacing = 6,
        bottomLeftAlpha = 1,
        bottomLeftRows = 1,
        bottomLeftButtons = 12,

        bottomRightScale = 1,
        bottomRightSpacing = 6,
        bottomRightAlpha = 1,
        bottomRightRows = 1,
        bottomRightButtons = 12,

        rightScale = 0.8,
        rightSpacing = 6,
        rightAlpha = 1,

        -- The side bars stand upright, which is what their old shape meant.
        rightRows = 12,
        rightButtons = 12,

        leftScale = 0.8,
        leftSpacing = 6,
        leftAlpha = 1,
        leftRows = 12,
        leftButtons = 12,

        petScale = 0.8,
        petSpacing = 6,
        petAlpha = 1,

        shapeshiftScale = 0.8,
        shapeshiftSpacing = 6,
        shapeshiftAlpha = 1,

        --[[ **Keybind and macro text.**

             The reason this is worth porting rather than leaving to the client:
             1.12 draws `SHIFT-BUTTON4` in full, in a nine point font, over the
             corner of the icon. Nobody can read it and everybody leaves it on
             because the alternative is not knowing what is bound.

             The abbreviations below are what make it legible. ]]--
        showHotkeys = true,
        hotkeySize = 12,
        hotkeyColor = { 1, 0.82, 0, 1 },

        showMacroNames = true,
        macroSize = 10,
        macroColor = { 1, 1, 1, 1 },

        --[==[ **Item amounts: the third string on a button, and the one this
             module had never touched.**

             `$parentCount` is how many of a thing is left -- bandages, potions,
             a shard, a warlock's healthstone -- and it is the number a bar
             exists to keep in front of you. It kept the client's own font at the
             client's own size in the client's own colour, so a player who set
             their keybinds to nine point and their macro names to eight still
             had a fourteen point stack count in the corner of every consumable,
             in a font nothing else on screen was using.

             It is the same kind of text as the other two -- small, over
             artwork, read at a glance -- so it gets the same three controls.
             White, because a count is a fact rather than a warning and the
             client's own is white; twelve, because it sits in a corner and has
             at most three digits to fit. ]==]
        showCounts = true,
        countSize = 12,
        countColor = { 1, 1, 1, 1 },

        --[[ **Blizzard's furniture, one switch per piece.**

             This was a single Hide Art, which is all or nothing -- and the two
             things most often unwanted, the XP bar and the micro menu, were not
             covered by it at all.

             The three that made up the old switch default on, because the
             buttons floating free is the point of moving them anywhere and that
             is what this module has always done. The four that are new default
             off: they hide things the client puts there on purpose, and a
             module that quietly took somebody's bags away on upgrade would be a
             bug report rather than a feature. ]]--
        hideGryphons = true,
        hideBarArt = true,
        hideStanceArt = true,

        hideXP = true,
        hideMicroMenu = true,

        --[==[ **On, and no longer a switch.**

             Six of these were offered and the list read as six decisions about
             furniture nobody wants to make. Each one is a piece of the client's
             bar chrome that this addon already replaces: its own experience
             bar, its own latency and framerate text, its own bag button. Two
             copies of a thing is not a choice between them.

             The gryphons keep their switch, because they are the one that is
             decoration rather than duplication -- somebody can like them and
             nothing else on screen is doing their job. ]==]
        hidePerformanceBar = true,
        hideBags = true,
        hidePageArrows = false,

        --[[ Where each bar has been dragged to, keyed by bar. A bar nobody has
             moved has no entry and keeps following the client's own default, so
             turning drag mode on and off leaves everything where it was. ]]--
        positions = {},

        --[[ Off, because it puts a button on screen and that should be a
             decision. Its size matches the bag bar it stands in for. ]]--
        --[[ On. The client draws a sweeping shadow and never says how many
             seconds, which is readable at two and useless at two hundred. ]]--
        cooldownNumbers = true,

        --[[ Off. Gathering the client's own buttons into a bar of this addon's
             is a visible change to where somebody's bags are, and that should
             be asked for rather than assumed. ]]--
        bagBar = false,
        bagBarScale = 1,
        bagBarSpacing = 4,

        microBar = false,

        pagingBar = false,
        pagingBarScale = 1,
        pagingBarSpacing = 2,

        --[[ The client draws latency as a bar you have to hover to read.
             These are the number instead, coloured by what it means. ]]--
        performanceText = false,
        performanceFPS = true,
        performancePing = true,
        microBarScale = 1,
        microBarSpacing = 2,

        bagButton = true,
        bagButtonSize = 36,

        --[[ On. The client draws a sliver of art with no numbers on it, and
             "how much left" is the only question a levelling bar is asked. ]]--
        showXPBar = true,

        --[[ The client draws experience purple and reputation blue, so these
             start where somebody would expect them to and are settings because
             the bars are this addon's to colour. ]]--
        xpBarColor = { 0.6, 0.2, 0.8, 1 },
        repBarColor = { 0.2, 0.6, 0.9, 1 },
        showRepBar = true,

        --[==[ **What the bar shows when nothing is pinned.**

             Watching a faction is a deliberate act and most people never do it,
             so the bar spent most of its life empty -- which is a strip of
             screen earning nothing. Falling back to whatever you last earned
             reputation with is almost always the faction you care about right
             now: you are grinding it, which is why the line just appeared in
             your log.

             On, because an empty bar is the thing being fixed. A pinned faction
             still wins outright -- pinning is an instruction, and this is only
             a guess about what to do without one. ]==]
        repFollowsLatest = true,

        --[==[ **What each bar says, one switch per thing it says.**

             Both bars wrote one fixed sentence. The reputation bar's was the
             faction and the numbers, which is three facts crammed into a strip
             twelve pixels tall -- and the fact a player is actually tracking,
             the standing, was not among them: "am I Revered yet" was answerable
             only by pointing at the bar.

             So the standing goes on the bar, and everything on the bar becomes
             optional. Somebody watching one faction to Exalted does not need its
             name written out every time they look; somebody who never looks at
             raw numbers can have the rank alone. Neither is the right default
             for the other.

             All on, because that is the sentence the bar drew before plus the
             one piece it was missing, and a setting nobody has touched should
             leave them where they were.

             **The tooltip ignores every one of them.** Hiding a piece is a
             statement about the bar, not about the information -- so pointing at
             either bar still says all of it. That is what makes turning things
             off cheap: nothing becomes unreachable, it just stops taking up a
             strip of screen. ]==]
        repShowFaction = true,
        repShowStanding = true,
        repShowProgress = true,

        --[==[ The same three for experience, and the third is rested.

             Rested is the experience bar's standing: a real quantity, the one
             people ask about, and drawn only as a paler stretch of bar that says
             how far it reaches and never how much it is. ]==]
        xpShowLabel = true,
        xpShowProgress = true,
        xpShowRested = true,
        progressWidth = 460,
        progressHeight = 12,
    },

    options = {
        --[==[ **General: everything that is not about one bar.**

             The page had a section per feature -- Button Text, Cooldowns,
             Keybinds, Hide Elements, Bag Button, Latency -- interleaved with the
             bars themselves, so it read as a list of things this module can do
             rather than as a list of the bars you came to change. Six of the
             seventeen entries in the picker were settings that apply to all of
             them at once.

             They are headers inside one section now. The grouping is still
             visible; it just stops competing with the bars for the top of the
             list. ]==]
        { "General", "__s_general", "section", "general" },

        { "Button Text", "__h_text", "header" },

        { "Always Show Empty Slots", "alwaysShowBars", "boolean" },

        { "Show Keybinds", "showHotkeys", "boolean" },
        { "Keybind Size", "hotkeySize", "slider", 6, 20, 1,
          nil, nil, "!showHotkeys" },
        { "Keybind Color", "hotkeyColor", "color", true,
          nil, nil, nil, nil, "!showHotkeys" },

        --[==[ ~~Text Outline~~ **was a second control for a setting that
             already had one.**

             The reasoning for adding it holds and is why the module is
             `styled = { font, fontOutline }`: this text sits directly on an
             icon, which is whatever colour the art happens to be, and
             unoutlined text over that does not read as plainer, it disappears.
             So the module needs an outline of its own rather than the
             profile's -- and declaring `fontOutline` in `styled` had already
             given it one, under **Appearance**, which is where every other
             module's is.

             The row written here was a second widget onto the same key, on the
             same page, with a different caption. Two controls for one setting:
             move one and the other is wrong until the panel is reopened. The
             suite's duplicate check compared rows *across* pages and had nothing
             to say about two on one. ]==]
        { "Show Macro Names", "showMacroNames", "boolean" },
        { "Macro Name Size", "macroSize", "slider", 6, 20, 1,
          nil, nil, "!showMacroNames" },
        { "Macro Name Color", "macroColor", "color", true,
          nil, nil, nil, nil, "!showMacroNames" },

        { "Show Item Amounts", "showCounts", "boolean" },
        { "Item Amount Size", "countSize", "slider", 6, 20, 1,
          nil, nil, "!showCounts" },
        { "Item Amount Color", "countColor", "color", true,
          nil, nil, nil, nil, "!showCounts" },
        { "Cooldowns", "__h_cooldown", "header" },

        { "Show Numbers On Cooldowns", "cooldownNumbers", "boolean" },

        { "Keybinds", "__h_bind", "header" },

        --[[ The action reads the mode back, so one button says both "enter" and
             "leave" -- the panel has no other way to show that a mode is on, and
             two buttons for one mode is two things to look at. ]]--
        { "Enter Bind Mode", "__a_bind", "action",
          function() OB.modules.actionbars:SetBindMode(
                  not OB.modules.actionbars:BindMode()) end,
          function()
              if OB.modules.actionbars:BindMode() then return "Leave Bind Mode" end
              return "Enter Bind Mode"
          end },

        { "Hide Blizzard's Bar Artwork", "__h_hide", "header" },

        { "Gryphons", "hideGryphons", "boolean" },

        --[[ The green bar beside the micro menu. Latency & FPS says the same
             thing as a number, which is the thing you wanted to know. ]]--

        --[[ Its own section rather than a switch under Hide Elements: it is
             the one thing there that *adds* something to the screen, and a
             switch that puts a button back does not belong in a list of
             switches that take things away. ]]--
        { "Bag Button", "__h_bagbutton", "header" },

        { "Latency & FPS", "__h_perf", "header" },

        --[[ A number rather than a bar you have to hover to read. ]]--
        { "Show Latency & FPS", "performanceText", "boolean" },
        { "Show Frame Rate", "performanceFPS", "boolean",
          nil, nil, nil, nil, nil, "!performanceText" },
        { "Show Latency", "performancePing", "boolean",
          nil, nil, nil, nil, nil, "!performanceText" },
        --[[ **Color Latency By Connection has gone**, and it was the only
             control on this panel two switches deep: reachable by ticking Show
             Latency & FPS and then Show Latency. The colour is the whole reason
             the client's bar was worth replacing with a number rather than
             merely hidden, so off left a plain figure that says less than the
             thing it replaced. ]]--

        --[[ No switch. The client's six bag slots are hidden either way --
             they are what this replaces -- so a switch here would offer a
             state with no way to open your bags from the bar at all. ]]--
        { "Bag Button Size", "bagButtonSize", "slider", 20, 64, 2 },
        { "Put It Back", "__a_bagreset", "action",
          function() OB.modules.actionbars:ResetBagPosition() end },

        { "Main Bar", "__s_main", "section", "main" },

        --[[ Moved out of the general Hide Elements list: the paging arrows
             are on the main bar and nowhere else, so a switch for them under a
             heading that covers every bar was answering a question about one
             of them. ]]--
        { "Hide Page Arrows", "hidePageArrows", "boolean" },

        { "Scale", "mainScale", "slider", 50, 200, 5, 0.01 },
        { "Spacing", "mainSpacing", "slider", 0, 20, 1 },
        { "Opacity", "mainAlpha", "slider", 10, 100, 5, 0.01 },
        { "Rows", "mainRows", "slider", 1, 12, 1 },
        { "Buttons Shown", "mainButtons", "slider", 1, 12, 1 },

        --[[ Its own section, because seven switches under Main Bar reads as
             seven more things about the main bar rather than as the furniture
             round all of them. ]]--
        { "Main Bar", "__s_main2", "section", "main" },

        --[[ A mode rather than a lock: on, drag, off. A permanently draggable
             action bar is one you move by accident while clicking a spell. ]]--
        { "Move The Bars", "__a_drag", "action",
          function() OB.modules.actionbars:SetDragMode(
                  not OB.modules.actionbars:DragMode()) end,
          function()
              if OB.modules.actionbars:DragMode() then return "Done Moving" end
              return "Move The Bars"
          end },

        { "Put Them Back", "__a_dragreset", "action",
          function() OB.modules.actionbars:ResetPositions() end },

        --[==[ **Numbered, not placed.**

             "Bottom Left Bar" describes where Blizzard's own options happen to
             put that bar, which stops being true the moment anybody moves it --
             and this module exists to let them move it. The numbers are what the
             keybinding menu, the macro conditionals and every other addon call
             these, so they are what somebody is already holding in their head.

             `MultiBarBottomLeft` is Action Bar 2 in that scheme, BottomRight is
             3, Right is 4 and Left is 5. ]==]
        --[[ A header rather than a section: paging is a property of the main
             bar, not a feature beside it -- it is the thing the main bar does
             when you press the arrows, and nothing else on the page pages. ]]--
        { "Paging", "__h_paging", "header" },

        --[[ The arrows and the page number, on a bar that can be moved.
             Hide Elements already offers taking them away. ]]--
        { "Put Paging On Its Own Bar", "pagingBar", "boolean" },
        { "Paging Size", "pagingBarScale", "slider", 50, 200, 5, 0.01,
          nil, "!pagingBar" },
        { "Paging Spacing", "pagingBarSpacing", "slider", 0, 20, 1,
          nil, nil, "!pagingBar" },

        { "Action Bar 2", "__s_bl", "section", "bottomleft" },

        { "Show Action Bar 2", "showBottomLeft", "boolean" },

        { "Scale", "bottomLeftScale", "slider", 20, 200, 5, 0.01 },
        { "Spacing", "bottomLeftSpacing", "slider", 0, 20, 1 },
        { "Opacity", "bottomLeftAlpha", "slider", 10, 100, 5, 0.01 },
        { "Rows", "bottomLeftRows", "slider", 1, 12, 1 },
        { "Buttons Shown", "bottomLeftButtons", "slider", 1, 12, 1 },

        { "Action Bar 3", "__s_br", "section", "bottomright" },

        { "Show Action Bar 3", "showBottomRight", "boolean" },

        { "Scale", "bottomRightScale", "slider", 20, 200, 5, 0.01 },
        { "Spacing", "bottomRightSpacing", "slider", 0, 20, 1 },
        { "Opacity", "bottomRightAlpha", "slider", 10, 100, 5, 0.01 },
        { "Rows", "bottomRightRows", "slider", 1, 12, 1 },
        { "Buttons Shown", "bottomRightButtons", "slider", 1, 12, 1 },

        { "Action Bar 4", "__s_r", "section", "right" },

        { "Show Action Bar 4", "showRight", "boolean" },

        { "Scale", "rightScale", "slider", 20, 200, 5, 0.01 },
        { "Spacing", "rightSpacing", "slider", 0, 20, 1 },
        { "Opacity", "rightAlpha", "slider", 10, 100, 5, 0.01 },
        { "Rows", "rightRows", "slider", 1, 12, 1 },
        { "Buttons Shown", "rightButtons", "slider", 1, 12, 1 },

        { "Action Bar 5", "__s_l", "section", "left" },

        { "Show Action Bar 5", "showLeft", "boolean" },

        { "Scale", "leftScale", "slider", 20, 200, 5, 0.01 },
        { "Spacing", "leftSpacing", "slider", 0, 20, 1 },
        { "Opacity", "leftAlpha", "slider", 10, 100, 5, 0.01 },
        { "Rows", "leftRows", "slider", 1, 12, 1 },
        { "Buttons Shown", "leftButtons", "slider", 1, 12, 1 },

        --[==[ The bars that appear because of what you are rather than what you
             put on them: the pet bar, the stance/form bar, and whatever else a
             class is handed contextually. ]==]
        { "Special Bar", "__s_pet", "section", "pet" },

        { "Pet Bar Scale", "petScale", "slider", 20, 200, 5, 0.01 },
        { "Pet Bar Spacing", "petSpacing", "slider", 0, 20, 1 },
        { "Pet Bar Opacity", "petAlpha", "slider", 10, 100, 5, 0.01 },

        { "Stance Bar Scale", "shapeshiftScale", "slider", 20, 200, 5, 0.01 },
        { "Stance Bar Spacing", "shapeshiftSpacing", "slider", 0, 20, 1 },
        { "Stance Bar Opacity", "shapeshiftAlpha", "slider", 10, 100, 5, 0.01 },

        { "Micro Bar", "__s_micro", "section", "micro" },

        { "Put The Micro Menu On Its Own Bar", "microBar", "boolean" },
        { "Micro Menu Size", "microBarScale", "slider", 50, 200, 5, 0.01,
          nil, "!microBar" },
        { "Micro Menu Spacing", "microBarSpacing", "slider", 0, 20, 1,
          nil, nil, "!microBar" },

        --[[ Beside the micro bar rather than in its own place: the two are the
             same control -- take a row the client welded to the main bar and
             give it a bar of its own, with a size and a spacing. ]]--
        { "Bag Bar", "__h_bagbar", "header" },

        --[[ The client's six bag buttons, gathered into a bar that can be
             moved. Switching it off puts every one of them back. ]]--
        --[[ Named for what it does, not for what it acts on: "Bag Bar" already
             means "hide the bag bar" under Hide Elements, and two rows with one
             label and opposite meanings is worse than a longer name. ]]--
        { "Put The Bags On Their Own Bar", "bagBar", "boolean" },
        { "Bag Bar Size", "bagBarScale", "slider", 50, 200, 5, 0.01,
          nil, "!bagBar" },
        { "Bag Bar Spacing", "bagBarSpacing", "slider", 0, 20, 1,
          nil, nil, "!bagBar" },

        { "Experience Bar", "__s_progress", "section", "progress" },

        { "Show Experience Bar", "showXPBar", "boolean" },
        { "Show Reputation Bar", "showRepBar", "boolean" },

        { "Experience Bar Color", "xpBarColor", "color", true,
          nil, nil, nil, nil, "showXPBar" },
        { "Reputation Bar Color", "repBarColor", "color", true,
          nil, nil, nil, nil, "showRepBar" },
        { "Follow The Latest Faction", "repFollowsLatest", "boolean",
          nil, nil, nil, nil, nil, "!showRepBar" },

        --[[ Greyed rather than removed with their bar switched off: they still
             mean what they say, and a row that vanishes reads as a setting this
             addon does not have. ]]--
        { "Show Faction Name", "repShowFaction", "boolean",
          nil, nil, nil, nil, nil, "!showRepBar" },
        { "Show Reputation Standing", "repShowStanding", "boolean",
          nil, nil, nil, nil, nil, "!showRepBar" },
        { "Show Reputation Progress", "repShowProgress", "boolean",
          nil, nil, nil, nil, nil, "!showRepBar" },

        { "Show Experience Label", "xpShowLabel", "boolean",
          nil, nil, nil, nil, nil, "!showXPBar" },
        { "Show Experience Progress", "xpShowProgress", "boolean",
          nil, nil, nil, nil, nil, "!showXPBar" },
        { "Show Rested Experience", "xpShowRested", "boolean",
          nil, nil, nil, nil, nil, "!showXPBar" },
        { "Bar Width", "progressWidth", "slider", 200, 900, 10 },
        { "Bar Height", "progressHeight", "slider", 6, 32, 1 },

    },

    --[[ The bars appear and disappear as the client's own options are changed
         and as a druid changes form, and every one of those needs the layout
         re-applied to frames that were not there a moment ago. ]]--
    events = { "PLAYER_ENTERING_WORLD", "UPDATE_BONUS_ACTIONBAR",
               "ACTIONBAR_PAGE_CHANGED", "PET_BAR_UPDATE",
               "UPDATE_SHAPESHIFT_FORMS", "CVAR_UPDATE",

               --[[ A binding changing is the client rewriting every keybind
                    string on every button. The replacement handles each one as
                    it is rewritten; this is what re-applies the *font* and
                    colour, which the client does not touch. ]]--
               "UPDATE_BINDINGS",

               --[[ Reputation changes, so the bar can follow the faction you
                    are actually earning when none is pinned. ]]--
               "CHAT_MSG_COMBAT_FACTION_CHANGE" },

    --[[ The keybinding half of this module.

         Every one of these is called behind a `type(...) == "function"` guard,
         so a client without them does not error -- Bind Keys simply stops
         doing anything, silently, which is indistinguishable from the feature
         being broken. Named here so `/eq selftest` says which call is
         missing instead of leaving the user to guess.

         The layout half deliberately is not listed: it only ever calls widget
         methods on frames it has already found, and a frame that is not there
         is a bar the client does not have rather than a fault. ]]--
    requires = { "GetBindingKey", "GetBindingAction", "SetBinding",
                 "SaveBindings", "getglobal" },
})

function M:Config()
    return OB.profile.modules.actionbars
end

-- ---------------------------------------------------------------------------
-- laying a bar out
-- ---------------------------------------------------------------------------

--[[ **Where one button goes**, which is the whole engine and is four lines of
     arithmetic.

     Buttons fill left to right and then top to bottom, which is the order the
     keybinds are in and therefore the only order that does not surprise
     somebody. The Y is negative because a bar grows downwards from its anchor:
     the first row is the top one, so button thirteen of a two-row layout sits
     under button one rather than over it.

     Spacing is added to the button rather than between them, which makes the
     arithmetic one multiplication instead of a special case for the first. ]]--
function M:ButtonOffset(index, layout, spacing)
    local step = BUTTON + spacing

    local column = mod(index - 1, layout.cols)
    local row = math.floor((index - 1) / layout.cols)

    return column * step, -(row * step)
end

--[[ **The shape of one bar, from how many rows and how many buttons.**

     This was a list of six fixed arrangements -- 1x12, 2x6, 3x4 and so on -- and
     the list is the wrong shape for the question. It could not say "eight
     buttons in two rows", because eight buttons was not one of the six, and it
     could not say "only show six of them" at all.

     Rows is what the reader chooses and columns is what falls out of it, which
     is the way round that keeps the bar the width they expect: asking for two
     rows of ten gives two rows, not two rows and a stray. ]]--
--[[ **One frame that is never shown**, which is where buttons go when the
     button-count slider says they are not there.

     Created once and kept, rather than made per bar: it holds nothing, draws
     nothing and exists only to be a parent whose `IsVisible` is false. Parented
     to `UIParent` so it is a real frame in the hierarchy rather than an orphan,
     and hidden immediately -- a frame that is shown for even one pass would
     flash the buttons it is holding. ]]--
--[[ **What each bar was asked for, what shape that works out to, and where the
     buttons actually went.**

     Every number in this module is arithmetic on two settings -- how many rows
     and how many buttons -- and `BarShape` turns them into rows and columns.
     When the bar on screen does not match the shape those settings describe,
     the useful question is which of the three disagrees: the setting, the
     computed shape, or the button's real anchor.

     A screenshot answers none of them. This answers all three. ]]--
function M:ReportBars()
    local cfg = self:Config()

    OB.Print("action bars:", "Action Bars")

    for i = 1, table.getn(BARS) do
        local bar = BARS[i]
        local rows = cfg[bar.key .. "Rows"] or 1
        local shown = cfg[bar.key .. "Buttons"] or bar.count
        local shape = self:BarShape(rows, shown)

        OB.Raw(string.format("   %-14s rows %-3s shown %-3s -> %d x %d",
                bar.key, tostring(rows), tostring(shown),
                shape.rows, shape.cols))

        --[[ The first button of each row that should exist, read back off the
             frame. If the shape says three rows and every button reports the
             same Y, the shape is right and the placement is not. ]]--
        local first = getglobal(bar.prefix .. 1)

        if first and first.GetNumPoints and (first:GetNumPoints() or 0) > 0 then
            local point, relativeTo, relativePoint, x, y = first:GetPoint(1)
            local parent = relativeTo and relativeTo.GetName and relativeTo:GetName()

            OB.Raw(string.format("       button 1 %s -> %s %s (%.0f, %.0f)",
                    tostring(point), tostring(parent or "?"),
                    tostring(relativePoint), x or 0, y or 0))
        end

        --[[ The button that should start the second row, which is the one that
             proves whether rows are happening at all. ]]--
        if shape.rows > 1 and shape.cols >= 1 then
            local second = getglobal(bar.prefix .. (shape.cols + 1))

            if second and second.GetNumPoints
                    and (second:GetNumPoints() or 0) > 0 then
                local _, _, _, x, y = second:GetPoint(1)

                OB.Raw(string.format("       row 2 starts at button %d (%.0f, %.0f)",
                        shape.cols + 1, x or 0, y or 0))
            end
        end
    end

    return true
end

function M:HiddenHolder()
    if self.hiddenHolder then return self.hiddenHolder end

    local holder = CreateFrame("Frame", "EquadisClassicOverhaulHiddenBar", UIParent)
    holder:Hide()

    self.hiddenHolder = holder
    return holder
end

function M:BarShape(rows, shown)
    rows = tonumber(rows) or 1
    shown = tonumber(shown) or 0

    if rows < 1 then rows = 1 end
    if shown < 0 then shown = 0 end

    --[[ More rows than buttons is not an error, it is somebody dragging a
         slider past where it stops meaning anything. One button per row is as
         far as it goes. ]]--
    if rows > shown and shown > 0 then rows = shown end

    local cols = math.ceil(shown / rows)
    if cols < 1 then cols = 1 end

    return { rows = rows, cols = cols }
end

--[[ One bar: every button in the family placed on a container, at a scale, with
     an opacity.

     **The container is re-parented to, not created per call.** A button that
     changed parent every time a slider moved would lose its position for a frame
     each time, which reads as a flicker and is the sort of thing that gets
     blamed on the client. ]]--
function M:LayoutFamily(prefix, count, anchor, rows, spacing, scale, alpha, shown)
    --[[ How many of the family are wanted. Absent means all of them, which is
         what a profile written before this setting existed says. ]]--
    shown = tonumber(shown) or count
    if shown > count then shown = count end
    if shown < 0 then shown = 0 end

    local layout = self:BarShape(rows, shown)
    local placed = 0

    for i = 1, count do
        local button = getglobal(prefix .. i)

        --[[ **Past the count, the button goes away entirely.**

             Not faded and not left where it was: "show six" means the last six
             are not there, so the bar is six wide and nothing occupies the space
             the others had. Hidden rather than unparented so raising the slider
             brings them back without rebuilding anything -- the same
             reversibility the aura and party caps needed, and for the same
             reason: a control that only goes one way is worse than no
             control. ]]--
        --[[ **Past the count the button is parked on a hidden frame**, not
             merely hidden.

             Hiding it was not enough and could not be. The client shows action
             buttons back on its own account, and the loudest case is picking a
             spell up off the spellbook: `ACTIONBAR_SHOWGRID` runs
             `ActionButton_ShowGrid` across every button on every bar, empty
             slot or not. Drag one spell and the six buttons that were supposed
             to be gone are back, and stay back until something re-runs the
             layout -- which is exactly the complaint.

             A child of a hidden frame cannot be shown by anybody. `Show` sets
             the child's own flag and changes no pixels, so the client can call
             it as often as it likes. Nothing has to be intercepted and no event
             has to be raced. ]]--
        if button and i > shown then
            if button.SetParent and button:GetParent() ~= self:HiddenHolder() then
                button:SetParent(self:HiddenHolder())
            end
            if button.Hide then button:Hide() end
            button.ecoHiddenByCount = true

        elseif button and button.SetPoint then
            --[[ Back from a lower count. Blizzard owns whether an empty slot is
                 visible, so the button is shown and left to the client's own
                 update rather than forced. ]]--
            if button.ecoHiddenByCount then
                button.ecoHiddenByCount = nil
                if button.Show then button:Show() end

                --[[ **And told to redraw itself.**

                     Coming back from a lower count, the button was parked on a
                     hidden frame and the client stopped updating it. Showing it
                     again puts the frame back and leaves it holding whatever it
                     last drew -- which for a slot that changed while it was away
                     is the wrong icon, and for one that was empty when it left
                     is nothing at all. The bar looked like it had lost the
                     buttons until something else re-ran the layout, and the
                     thing that reliably did was a reload.

                     `this` is how 1.12 passes the button to its own updater;
                     saved and put back, because anything reading it after this
                     returns is entitled to find what it left there. ]]--
                if type(ActionButton_Update) == "function" then
                    local previous = this
                    this = button
                    pcall(ActionButton_Update)
                    this = previous
                end
            end
            local x, y = self:ButtonOffset(i, layout, spacing)

            --[[ **Re-parented, not merely re-anchored.**

                 A button is a child of one of Blizzard's bar frames, and a
                 child inherits its parent's visibility, alpha and scale.
                 Anchoring to a container of ours while leaving the button on
                 `MainMenuBarArtFrame` means the client can still hide it, fade
                 it, and move the frame it is measured against through
                 `UIPARENT_MANAGED_FRAME_POSITIONS`.

                 **Only when it has moved.** Re-parenting every pass would drop
                 and rebuild the frame's position each time a slider moved,
                 which reads as a flicker and gets blamed on the client. ]]--
            if button.SetParent and button:GetParent() ~= anchor then
                button:SetParent(anchor)
            end

            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)

            --[[ **The scale and the fade are the container's, not the button's.**

                 Now that the buttons are its children they inherit both, and
                 putting them on the container is what makes its box the bar's
                 box: sized in unscaled button units, drawn at whatever scale
                 was asked for. `StorePosition` divides by the container's scale
                 and only makes sense that way round -- it was written for this
                 and the buttons were being scaled instead, so a bar at 0.8
                 remembered a position measured against a box 25% too wide.

                 Reset to 1 rather than left, because a profile written by the
                 version that scaled buttons still has that scale on them. ]]--
            if button.SetScale then button:SetScale(1) end
            if button.SetAlpha then button:SetAlpha(1) end

            placed = placed + 1
        end
    end

    --[[ The container is sized to what it actually holds, so anything anchored
         above it lands above the buttons rather than above where twelve of them
         would have been. A druid's four stances are not ten. ]]--
    if anchor and anchor.SetWidth and placed > 0 then
        local layoutCols = layout.cols
        if placed < layoutCols then layoutCols = placed end

        local rows = math.ceil(placed / layout.cols)

        anchor:SetWidth((layoutCols * (BUTTON + spacing)) - spacing)
        anchor:SetHeight((rows * (BUTTON + spacing)) - spacing)

        if anchor.SetScale then anchor:SetScale(scale) end
        if anchor.SetAlpha then anchor:SetAlpha(alpha) end
    end

    return placed
end

-- ---------------------------------------------------------------------------
-- the frames this addon owns
-- ---------------------------------------------------------------------------

--[[ **One container per bar, made once.**

     Blizzard's own bar frames carry art, mouse handling and a place in
     `UIPARENT_MANAGED_FRAME_POSITIONS`, which is the thing that quietly moves a
     frame back where the client wants it. Anchoring to a container of our own
     instead of to `MainMenuBar` is what stops that argument happening at all.

     DragonflightUI does the same and for the same reason. ]]--
function M:Anchor(name, point, x, y)
    self.anchors = self.anchors or {}

    if not self.anchors[name] then
        local frame = CreateFrame("Frame", "EquadisOverhaulBar" .. name, UIParent)

        frame:SetWidth(BUTTON)
        frame:SetHeight(BUTTON)
        frame:SetFrameStrata("LOW")
        frame:SetPoint(point, UIParent, point, x, y)

        self.anchors[name] = frame
    end

    return self.anchors[name]
end


-- ---------------------------------------------------------------------------
-- moving them
-- ---------------------------------------------------------------------------

--[[ **A mode, not a lock.**

     The bars sit where the client's defaults put them until somebody says
     otherwise, and "otherwise" is a mode you turn on, drag in, and turn off --
     the same shape as bind mode and for the same reason. A permanently draggable
     action bar is one you move by accident while clicking a spell on it.

     **Where a bar has been dragged to is remembered per bar**, in the profile
     next to its scale and spacing. A bar nobody has moved has no saved position
     and keeps following the default, so switching this on and off again leaves
     everything exactly where it was. ]]--
function M:DragMode()
    return self.dragging and true or false
end

function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("actionbars") then
        Say("switch the Action Bars module on first.")
        return false
    end

    self.dragging = on and true or nil

    for i = 1, table.getn(BARS) do
        local anchor = self:Anchor(BARS[i].name, BARS[i].point,
                BARS[i].x, BARS[i].y)

        self:MakeDraggable(anchor, BARS[i])
    end

    if self.dragging then
        Say("drag mode on. Move the bars, then switch it off. "
                .. "'/eq bars reset' puts them back.")
    else
        Say("drag mode off.")
    end

    return true
end

--[[ One container, made movable or not.

     **The handle is the container rather than the buttons.** A button is a
     button -- it casts things -- and making one draggable means every press is a
     potential drag. The container is the empty rectangle behind them, which is
     exactly the part with nothing else to do.

     A backdrop appears with the mode so there is something to aim at: an
     invisible frame the size of a bar is not a thing anybody can grab. ]]--
function M:MakeDraggable(anchor, bar)
    if not anchor then return false end

    if not anchor.dragHint then
        local hint = anchor:CreateTexture(nil, "BACKGROUND")
        hint:SetAllPoints(anchor)
        hint:SetTexture(0.1, 0.6, 1, 0.25)
        hint:Hide()

        anchor.dragHint = hint
    end

    if not self.dragging then
        anchor:EnableMouse(false)
        anchor:SetMovable(false)
        anchor.dragHint:Hide()
        return true
    end

    anchor:EnableMouse(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor.dragHint:Show()

    --[[ Named for the outline edit mode draws round it. A bar anchor is an
         empty rectangle behind the buttons -- exactly the thing an unlabelled
         outline would leave somebody guessing about. ]]--
    OB.MarkMovable(anchor, bar.name .. " Bar")

    anchor:SetScript("OnDragStart", function() this:StartMoving() end)

    anchor:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        OB.modules.actionbars:StorePosition(bar, this)
    end)

    return true
end

--[[ Where a bar ended up, as an offset from the centre of the screen.

     **From the centre, not from a corner**, which is the rule the meters already
     follow: a position measured from an edge means a different place on a
     different resolution, and this addon has been bitten by that before -- see
     OB.ScreenLimit. The centre is the one point every screen shares. ]]--
function M:StorePosition(bar, frame)
    if not frame or not frame.GetLeft or not frame:GetLeft() then return false end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end

    --[[ **Keyed by the bar, not by the button family.** The main bar and the
         bonus bar are two families in one rectangle -- a druid in form is
         looking at the same place on screen -- so they share a key and moving
         either moves both. Keyed by name they did not, and a druid who dragged
         their bar found it back at the default the moment they shifted.

         No migration: drag mode threw on every use until now, so there is no
         saved position anywhere written under the old key. ]]--
    cfg.positions[bar.key] = {
        x = OB.Round((frame:GetLeft() + (frame:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((frame:GetBottom() + (frame:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[[ **Where a bar goes: the saved position if there is one, the default if not.**

     Applied on the style pass rather than only at login, so a bar dragged with
     the mode on stays where it was put when the next setting changes -- which is
     otherwise where a position quietly reverts.

     A bar nobody has moved has no saved position and keeps following the
     default, so turning the mode on and off again leaves everything exactly
     where it was. ]]--
function M:PlaceAnchor(anchor, bar)
    if not anchor then return false end

    --[[ Not while it is being dragged. Re-anchoring a frame somebody is holding
         takes it out from under the cursor. ]]--
    if self.dragging then return false end

    local saved = self:Config().positions
    saved = saved and saved[bar.key]

    anchor:ClearAllPoints()

    if saved then
        anchor:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    else
        anchor:SetPoint(bar.point, UIParent, bar.point, bar.x, bar.y)
    end

    return true
end

--[[ Put every bar back where the client would have had it. ]]--
function M:ResetPositions()
    self:Config().positions = {}

    for i = 1, table.getn(BARS) do
        local anchor = self.anchors and self.anchors[BARS[i].name]

        if anchor then
            anchor:ClearAllPoints()
            anchor:SetPoint(BARS[i].point, UIParent, BARS[i].point,
                    BARS[i].x, BARS[i].y)
        end
    end

    Say("action bars put back where they started.")
end

-- ---------------------------------------------------------------------------
-- one bag button, off the bar
-- ---------------------------------------------------------------------------

--[[ **A bag button that is not part of the bar.**

     Hiding the Bag Bar takes away five buttons and, with them, the only way to
     open your bags that does not involve a keybind. That is a fair trade for
     four bag slots nobody looks at and a bad one for the backpack, which is the
     button the whole group exists for.

     So the backpack comes back on its own: one button, anywhere on screen,
     moved like any other frame. The client's own artwork -- the same texture
     the bag bar draws -- because a bag button that does not look like the bag
     button is a button people have to learn.

     It opens whichever bags are in use. ECO's replacement bag window if that
     module is on, the client's bags if it is not, which is the same question
     the keybind answers and it should not answer it differently. ]]--
local BAG_TEXTURE = "Interface\\Buttons\\Button-Backpack-Up"

local BAG_BUTTONS = {
    "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
    "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
}
--[[ Whatever the client draws on its backpack button, or the stock path when
     there is nothing to read. Asked each time rather than cached: a UI addon
     may restyle that button after this one is built. ]]--
function M:BackpackTexture()
    local pack = getglobal("MainMenuBarBackpackButton")

    if pack and pack.GetNormalTexture then
        local tex = pack:GetNormalTexture()
        local path = tex and tex.GetTexture and tex:GetTexture()

        --[==[ **Not if what is on it now is ours.**

             This copies the client's own backpack art off the client's own
             button, which is right until something has already restyled that
             button -- and this addon does exactly that, on the same bar, in the
             same pass. What came back then was `SkinButton`'s border, and the
             bag button drew a border where a bag should be.

             Reported as "the bag icon isn't showing, it's using the UI border",
             which is precisely what it was doing.

             Anything under this addon's own media path is refused, and the
             known vanilla path is used instead -- a fallback that is right
             rather than a copy that is wrong. ]==]
        local ours = path and OB.mediaPath
                and string.find(path, "EquadisClassicOverhaul", 1, true)

        if path and not ours then return path end
    end

    return BAG_TEXTURE
end


function M:BagButton()
    if self.bagButton then return self.bagButton end
    if not CreateFrame then return nil end

    local button = CreateFrame("Button", "EquadisClassicOverhaulBagButton",
            UIParent)

    button:SetWidth(36)
    button:SetHeight(36)
    button:Hide()

    --[==[ **A bordered square, drawn before the icon so it sits behind it.**

         On the bar this button replaces, the slot art is what said "this is a
         thing you click"; on its own in the middle of the screen the icon
         alone reads as a stray picture. `OB.SkinButton` is the same square
         every other button in this addon wears, so it is one border rather
         than a second idea of what one looks like. ]==]
    if OB.SkinButton then OB.SkinButton(button) end

    button.icon = button:CreateTexture(nil, "ARTWORK")
    --[[ **The client's own backpack art, at whatever size this button is.**

         Read off `MainMenuBarBackpackButton` rather than named here, so this
         is the same picture the bag bar was showing -- including on a client
         or UI addon that ships its own. A path written here would be a second
         answer to "what does a bag look like", and the two would drift.

         `BAG_TEXTURE` stays as the fallback for a client that has no such
         button to copy, which is the only case where a name here is the
         best available answer. ]]--
    --[[ The second of these used to be unconditional, so the client's own
         art was read and then immediately thrown away -- the fallback was
         overwriting the thing it was a fallback for. It is only reached now
         when there is nothing to copy. ]]--
    button.icon:SetTexture(self:BackpackTexture() or BAG_TEXTURE)

    --[[ Registered for the right button as well, so the two ways of opening
         bags the client offers are both here rather than one of them being
         lost with the bar. ]]--
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button:SetScript("OnClick", function()
        OB.modules.actionbars:OpenBags(arg1 == "RightButton")
    end)

    --[[ Moved by edit mode, which drives the frame's own drag handler so the
         position is written the same way a bar's is. ]]--
    button:SetScript("OnDragStop", function()
        OB.modules.actionbars:StoreBagPosition(this)
    end)

    if OB.MarkMovable then OB.MarkMovable(button, "Bag Button") end

    self.bagButton = button
    return button
end

--[[ The backpack alone on the right, every bag on the left -- the client's own
     two answers, kept apart. ]]--
function M:OpenBags(backpackOnly)
    local bags = OB.modules.bags

    if not backpackOnly and OB.ModuleEnabled("bags") and bags and bags.Toggle then
        return bags:Toggle()
    end

    if backpackOnly then
        if ToggleBackpack then ToggleBackpack() end
        return true
    end

    if OpenAllBags then OpenAllBags() end
    return true
end

--[[ Stored the same way a bar's position is: an offset from the centre of the
     screen, so it lands in the same place at another resolution. ]]--
function M:StoreBagPosition(frame)
    if not frame or not frame.GetLeft or not frame:GetLeft() then return false end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.positions.bagButton = {
        x = OB.Round((frame:GetLeft() + (frame:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((frame:GetBottom() + (frame:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[==[ **Which of the client's four extra bars exist.**

     `SetActionBarToggles` is the client's own persistence for this -- the same
     call its options panel makes -- so writing through it means these settings
     and that panel are one switch rather than two that drift.

     **Bar 5 needs bar 4**, and that is the client's rule rather than one
     invented here: `MultiBarLeft` is drawn inboard of `MultiBarRight` and the
     client's own options grey the one out without the other. Asking for 5
     without 4 gives a column of buttons floating where nothing anchors them, so
     4 is turned on to go with it.

     `MultiActionBar_Update` is what actually shows and hides the frames;
     `UIParent_ManageFramePositions` moves everything that sits above them --
     the chat frame most visibly -- and skipping it leaves a gap where a bar
     used to be. ]==]
function M:ApplyBarVisibility()
    if type(SetActionBarToggles) ~= "function" then return false end

    local cfg = self:Config()

    local bar1 = cfg.showBottomLeft and 1 or nil
    local bar2 = cfg.showBottomRight and 1 or nil
    local bar4 = cfg.showLeft and 1 or nil
    local bar3 = (cfg.showRight or bar4) and 1 or nil

    SHOW_MULTI_ACTIONBAR_1 = bar1
    SHOW_MULTI_ACTIONBAR_2 = bar2
    SHOW_MULTI_ACTIONBAR_3 = bar3
    SHOW_MULTI_ACTIONBAR_4 = bar4

    --[[ A string, because that is what the client compares against -- it
         tests `== "1"` before it tests `== 1`, and a boolean matches neither. ]]--
    ALWAYS_SHOW_MULTIBARS = cfg.alwaysShowBars and "1" or "0"

    SetActionBarToggles(bar1, bar2, bar3, bar4)

    if type(MultiActionBar_Update) == "function" then MultiActionBar_Update() end

    --[==[ **Setting the global is not what shows the empty slots.**

         `ALWAYS_SHOW_MULTIBARS` is read by `MultiActionBar_UpdateGridVisibility`
         and by nothing else that runs on its own. Writing it and calling
         `MultiActionBar_Update` -- which is about which *bars* exist, not which
         *buttons* on them are drawn -- left the setting doing nothing until
         something else happened to poke the grids, which is why it looked
         broken rather than absent. ]==]
    if type(MultiActionBar_UpdateGridVisibility) == "function" then
        MultiActionBar_UpdateGridVisibility()
    end

    if type(UIParent_ManageFramePositions) == "function" then
        UIParent_ManageFramePositions()
    end

    return true
end

function M:ApplyBagButton()
    local button = self:BagButton()
    if not button then return false end

    local cfg = self:Config()

    --[[ **It replaces the client's bag bar rather than sitting beside it.**

         One button that opens the bags is the point; six slots plus a
         seventh button is more furniture, not less. So switching this on
         puts the client's six away, and switching it off brings them back --
         a button that took something away and cannot give it back is worse
         than the clutter it removed.

         Left alone when the bag bar is gathering them: that feature owns
         those buttons, and two features moving the same six is a fight. ]]--
    if not cfg.bagBar then
        for i = 1, table.getn(BAG_BUTTONS) do
            local slot = getglobal(BAG_BUTTONS[i])

            --[[ Always hidden. This button is what opens the bags now, and
                 a client slot left showing beside it is the duplicate the
                 button exists to remove. ]]--
            if slot then slot:Hide() end
        end
    end

    --[[ Re-read on every pass: the button is built once and lives for the
         session, and a UI addon that restyles the backpack button after that
         would otherwise leave this one showing yesterday's picture. ]]--
    if button.icon then button.icon:SetTexture(self:BackpackTexture()) end

    local size = tonumber(cfg.bagButtonSize) or 36
    button:SetWidth(size)
    button:SetHeight(size)

    --[[ Inset, so the square is a border around the icon rather than a line
         underneath its edge. Proportional: a 64px button with a 3px inset
         looks like a mistake at 20. ]]--
    if button.icon then
        local inset = math.floor(size / 12) + 1
        button.icon:ClearAllPoints()
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
    end

    local saved = cfg.positions and cfg.positions.bagButton

    button:ClearAllPoints()

    if saved then
        button:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    else
        --[[ Where the bag bar's backpack sits on a stock client, so switching
             it on does not move anything anybody was already looking at. ]]--
        button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -12, 12)
    end

    button:Show()
    return true
end


--[[ Blizzard's bar art, hidden -- and put back when the switch goes off.

     Every one of these is guarded, because the set differs between 1.12 builds
     and a private server may have removed or renamed one. A missing texture is
     not a reason to abandon the rest of the layout -- and an unguarded
     `SlidingActionBarTexture0:SetTexture` on a client that lacks it takes the
     whole module down on login, which is the failure that looks like the addon
     being broken. ]]--
--[[ **The furniture round the bars, in the pieces people actually want rid
     of separately.**

     This was one list behind one switch called Hide Art, which is all or
     nothing -- and the two things most often unwanted, the XP bar and the micro
     menu, were not in it at all. "Hide certain elements" is the request, and
     the answer is a group per element rather than a longer list behind the same
     switch.

     Every global here is checked against what addons on a live 1.12 client
     actually use, because a name that does not exist fails silently:
     `getglobal` returns nil, the loop steps over it, and the switch does
     nothing for ever. `SocialsMicroButton` is the one that catches people --
     it is Socials, plural, and the singular is a WotLK rename. There is no
     vehicle button on this client either, so there is none here. ]]--
local ART_GROUPS = {
    {
        key = "hideGryphons",
        regions = { "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap" },
    },
    {
        key = "hideBarArt",
        regions = {
            "MainMenuBarTexture0", "MainMenuBarTexture1",
            "MainMenuBarTexture2", "MainMenuBarTexture3",
            "SlidingActionBarTexture0", "SlidingActionBarTexture1",
            "BonusActionBarTexture0", "BonusActionBarTexture1",
        },
    },
    {
        key = "hideStanceArt",
        regions = { "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight" },
    },
    {
        --[[ Both bars, because the client swaps to the max-level one at sixty
             and hiding only the first leaves a bar behind at the level most
             people asking for this are. ]]--
        key = "hideXP",
        --[[ **The reputation watch bar is the same strip of screen.**

             At the level cap the client draws watched reputation on that
             bar instead of experience, through `ReputationWatchBar` -- a
             different frame with the same job in the same place. Hiding
             only the experience frames left a full-width green bar reading
             "Wardens of Time 9730 / 12000", which is what was reported.

             `MainMenuBarMaxLevelBar` is the plain strip a capped character
             gets when watching nothing. All four are the same furniture. ]]--
        regions = {
            "MainMenuExpBar", "MainMenuBarMaxLevelBar",
            "ReputationWatchBar", "ReputationWatchStatusBar",
        },
    },
    {
        --[[ **The vertical green latency bar**, which the client draws beside
             the micro menu and which says nothing a number does not say
             better. Latency & FPS replaces it with the figure itself.

             Named separately from the micro menu because hiding the whole
             menu to lose one bar is a poor trade. ]]--
        key = "hidePerformanceBar",
        regions = {
            "MainMenuBarPerformanceBar", "MainMenuBarPerformanceBarFrame",
            "MainMenuBarPerformanceBarFrameButton",
        },
    },
    {
        key = "hideMicroMenu",
        regions = {
            "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
            "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
            "MainMenuMicroButton", "HelpMicroButton",
            -- Turtle adds these; absent on a stock client and skipped there.
            "LFGMicroButton", "PVPMicroButton", "ShopMicroButton",
        },
    },
    {
        key = "hideBags",
        regions = {
            "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
            "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
        },
    },
    {
        --[[ Only worth hiding if you never page the main bar, which is most
             people once their bars are bound. ]]--
        key = "hidePageArrows",
        regions = { "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber" },
    },
}

--[[ Every region any group can touch, flattened. Used by the restore, which has
     to put back everything this module might have taken away regardless of
     which switches were on when it was turned off. ]]--
local ART = {}
for i = 1, table.getn(ART_GROUPS) do
    for j = 1, table.getn(ART_GROUPS[i].regions) do
        table.insert(ART, ART_GROUPS[i].regions[j])
    end
end

--[[ `PetActionBarFrame` is deliberately in no group, though its art is what
     everybody means by "the pet bar background". It is a frame, and it is the
     frame the client shows and hides to say whether you have a pet -- which is
     the signal the layout pass mirrors onto its own container. Hiding it would
     make that answer always "no". Its mouse handling is switched off below
     instead, which is the part that was actually in the way. ]]--

--[[ The frames that keep their mouse handling otherwise, which means an
     invisible plate swallowing clicks over an empty part of the screen. ]]--
local ART_FRAMES = { "MainMenuBar", "MainMenuBarArtFrame", "PetActionBarFrame" }

--[[ **Hidden and faded, never `SetTexture(nil)`.**

     Clearing the texture cannot be undone: the path is gone and this addon never
     knew it, so unticking the box left the art missing until a reload. Hiding
     and fading both reverse, so the switch works in both directions.

     Frames get their mouse switched off rather than hidden -- an invisible
     plate that still swallows clicks over an empty part of the screen is the
     complaint this answers, and hiding `PetActionBarFrame` outright would
     destroy the signal the layout pass reads to know whether you have a
     pet. ]]--
function M:StyleArt()
    local cfg = self:Config()

    --[[ The mouse plate follows the bar's own art rather than every group: it
         is there to stop an invisible `MainMenuBar` swallowing clicks over an
         empty part of the screen, and it is only invisible once the background
         and the gryphons are gone. Hiding the XP bar leaves the bar there. ]]--
    local barGone = cfg.hideBarArt and cfg.hideGryphons

    for i = 1, table.getn(ART_GROUPS) do
        local group = ART_GROUPS[i]
        local hide = cfg[group.key] and true or false

        --[==[ **Hiding the micro menu and moving it are the same buttons.**

             `hideMicroMenu` hides exactly the eleven buttons `microBar` puts on
             a bar of their own, and nothing stopped both being on at once. With
             both, this module built the row and then hid everything standing in
             it -- a micro menu that is nowhere, from two switches that each read
             as reasonable on their own page.

             The hide is about the client's *main bar*: it is one of a list of
             things to take off that bar, beside the page arrows and the latency
             strip. Once the buttons have left it there is nothing there to
             hide, so the question stops applying rather than being answered
             the wrong way.

             The switch is left alone rather than forced off. Turning the bar
             back off should give back the state that was set, not the state
             this decided on somebody's behalf. ]==]
        if group.key == "hideMicroMenu" and cfg.microBar then hide = false end

        for j = 1, table.getn(group.regions) do
            local region = getglobal(group.regions[j])

            if region then
                if hide then
                    if region.SetAlpha then region:SetAlpha(0) end
                    if region.Hide then region:Hide() end
                else
                    if region.SetAlpha then region:SetAlpha(1) end
                    if region.Show then region:Show() end
                end
            end
        end
    end

    for i = 1, table.getn(ART_FRAMES) do
        local frame = getglobal(ART_FRAMES[i])
        if frame and frame.EnableMouse then frame:EnableMouse(not barGone) end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- the text on a button
-- ---------------------------------------------------------------------------

--[[ **A keybind, shortened until it fits.**

     This is the single most useful thing in the port. 1.12 writes
     `SHIFT-BUTTON4` across the corner of a 36 pixel icon in a font nobody can
     read, and the result is that everybody leaves keybind text on and nobody
     reads it.

     The substitutions are DragonflightUI's and they are well chosen: the
     modifier keeps its initial, the mouse button becomes M, and the long words
     that only ever appear alone get initials. Order matters -- `NUMPAD` before
     anything that could match inside it. ]]--
local SHORTEN = {
    { "SHIFT%-", "s" },
    { "CTRL%-", "c" },
    { "ALT%-", "a" },
    { "BUTTON", "M" },
    { "MOUSEWHEELUP", "MwU" },
    { "MOUSEWHEELDOWN", "MwD" },
    { "NUMPAD", "N" },
    { "SPACE", "Sp" },
    { "PAGEUP", "PU" },
    { "PAGEDOWN", "PD" },
}

function M:ShortenKey(key)
    if not key or key == "" then return "" end

    for i = 1, table.getn(SHORTEN) do
        key = string.gsub(key, SHORTEN[i][1], SHORTEN[i][2])
    end

    return key
end

--[[ The keybind and macro strings on every button, restyled.

     Blizzard's own font strings are used rather than replaced. DragonflightUI
     hides them and makes its own, which is more control and one more thing to
     keep in step -- the client updates its string when a binding changes, and a
     replacement has to notice that and copy it across. Restyling the original
     means the client goes on maintaining the text and this only decides how it
     looks.

     **The keybind text itself goes through the replaced client function**, not
     through here, so the same code runs whether this module asked for the update
     or the client did. See `M:UpdateHotkey`. This pass sets the font and colour,
     which the client does not touch, and then asks for the text. ]]--
--[[ Set on a string in one call, so nothing here has to remember the order the
     four settings go on in. ]]--
local function paint(fontstring, size, color)
    OB.ApplyFont(fontstring, size, "actionbars")

    color = color or { 1, 1, 1, 1 }
    fontstring:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

--[==[ **Three strings on a button, and all three answer to the same four
     settings**: the module's font and outline, and a size and a colour of their
     own.

     **The font row was doing nothing.** The module declares
     `styled = { font = true }`, so the Action Bars page has offered a Font
     control for as long as that line has been there -- and this asked
     `OB.FontPath()` with no module id, which is the *profile's* font. Choosing
     one here changed the meters and the tooltip and left the bars alone. Through
     `OB.ApplyFont` with the id, which is what every other subsystem does and
     what brings the outline along with it. ]==]
function M:ApplyText()
    local cfg = self:Config()

    for f = 1, table.getn(FAMILIES) do
        local family = FAMILIES[f]

        for i = 1, family.count do
            local name = family.prefix .. i
            local hotkey = getglobal(name .. "HotKey")
            local macro = getglobal(name .. "Name")

            --[[ Absent on the stance and pet bars, which have a keybind and
                 nothing else -- there is no stack of a shapeshift form. ]]--
            local count = getglobal(name .. "Count")

            if hotkey then
                if cfg.showHotkeys then
                    paint(hotkey, cfg.hotkeySize, cfg.hotkeyColor)
                    self:UpdateHotkey(getglobal(name))
                else
                    hotkey:Hide()
                end
            end

            if macro then
                if cfg.showMacroNames then
                    paint(macro, cfg.macroSize, cfg.macroColor)
                    macro:Show()
                else
                    macro:Hide()
                end
            end

            --[[ Shown rather than left alone when switched back on: the client
                 empties this string, it never hides it, so hiding it is
                 something only this module does and only this module will
                 undo. ]]--
            if count then
                if cfg.showCounts then
                    paint(count, cfg.countSize, cfg.countColor)
                    count:Show()
                else
                    count:Hide()
                end
            end
        end
    end
end

--[[ **The client rewrites this text, and often.**

     `ActionButton_UpdateHotkeys` writes the binding out in full and runs from
     `ActionButton_Update` -- every time a spell is dragged onto a bar, every
     time a binding changes, and on entering the world. Shortening the text on
     the module's own events and stopping there means it is long again after the
     next spell drag, which reads as the setting working until you use the bar.

     Same problem as the unit frame strings and the same answer: replace the
     client's function once, read the settings inside, and delegate for any
     button that is not one of ours. Constraint 86.

     **Guarded on the saved original**, which is the durable artefact -- guard
     and payload one object, in `_G`, which is where the replaced function lives.
     Constraint 87: the wrapper reaches the module by global name, never through
     the `OB` upvalue, because `core.lua` rebuilds that namespace on every
     load. ]]--
function M:UpdateHotkey(button)
    if not button or not button.GetName then return end

    local name = button:GetName()
    local command = self:CommandForFrame(name)

    --[[ Not one of ours -- another addon's bar, or a button family this client
         has that 1.12 did not. The client's own version, unchanged. ]]--
    if not command then return EquadisOverhaulBlizzHotkeys(button) end

    local cfg = self:Config()

    --[[ Switched off is switched off: the client's own text, in the client's own
         font. A module that is not doing this has to be indistinguishable from
         one that is not installed. ]]--
    if not OB.ModuleEnabled("actionbars") or not cfg.showHotkeys then
        return EquadisOverhaulBlizzHotkeys(button)
    end

    local hotkey = getglobal(name .. "HotKey")
    if not hotkey then return end

    local bound
    if type(GetBindingKey) == "function" then bound = GetBindingKey(command) end

    hotkey:SetText(self:ShortenKey(bound or ""))

    --[==[ **The colour is set here rather than only when the bars are styled.**

         Two client behaviours were undoing it. `ActionButton_Update` greys an
         empty slot's key with `hotkey:SetVertexColor(0.6, 0.6, 0.6)`, and the
         styling pass used `SetTextColor` -- a different channel, so the two
         did not overwrite each other so much as multiply, and the keybind came
         out grey on exactly the buttons with nothing on them. And the client
         updates buttons constantly, while styling runs once, so whatever the
         client did last was what stayed.

         Setting both is what makes it stick: the vertex colour back to white
         so the client's grey is not still multiplying, and the text colour to
         the one that was asked for. Done from here because this is the
         function the client calls whenever a button changes. ]==]
    self:PaintHotkey(hotkey)
    hotkey:Show()

    --[[ And the macro name on the same button, for the same reason: the client
         has just been through this button and whatever it left is what is
         showing. ]]--
    if cfg.showMacroNames then
        self:PaintMacroName(getglobal(name .. "Name"))
    end

    return true
end

--[==[ **One keybind, in the colour that was asked for.**

     Its own function because two different client passes undo it and both have
     to put it back the same way. On a `FontString`, `SetVertexColor` and
     `SetTextColor` are the same channel -- whichever ran last is the colour --
     so this sets the vertex white first and the text colour after, and the
     order is the whole of it. ]==]
function M:PaintHotkey(hotkey)
    return self:PaintText(hotkey, self:Config().hotkeyColor)
end

--[==[ **The macro name is the same problem and had none of the answer.**

     The keybind got a repaint because two client passes undo it. The macro name
     sits on the same button, is rewritten by the same `ActionButton_Update`, and
     had its colour set once by the styling pass and never again -- so a button
     the client touched after that kept whatever the client left, and the ones it
     did not keep the setting. Two colours at once, from the same cause and one
     line further down.

     Same function for both, because "put the colour back" is one behaviour and
     having it twice is how they drift. ]==]
function M:PaintMacroName(macro)
    return self:PaintText(macro, self:Config().macroColor)
end

--[==[ **On a `FontString`, `SetVertexColor` and `SetTextColor` are the same
     channel** -- whichever ran last is the colour. The client greys an empty
     slot's text with the vertex one, so this sets that back to white first and
     the asked-for colour after, and the order is the whole of it. ]==]
function M:PaintText(text, color)
    if not text or not color then return false end

    if text.SetVertexColor then text:SetVertexColor(1, 1, 1) end

    if text.SetTextColor then
        text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1,
                color[4] or 1)
    end

    return true
end

--[==[ **And again after the client has decided whether the spell is usable.**

     `ActionButton_UpdateUsable` paints the *keybind* as well as the icon --
     white when the spell can be cast, blue when the mana is short, grey when it
     cannot -- and on a `FontString` that is the text colour, so it replaces
     whatever this module set rather than shading it.

     It runs only for a button with an action on it. So the keybinds came out in
     two colours at once: the client's white on every button holding a spell,
     and this module's own colour on the empty ones it never visited. Reported
     from a screenshot of exactly that, and it reads as the colour setting only
     half working -- which it was.

     The keybind is this module's to colour once the setting exists at all, and
     what the client is saying with it is said twice over by the icon beside it,
     which is left alone. ]==]
function M:UpdateUsable(button)
    local target = button or this
    if not target then return end

    --[[ The client's own pass first, in full: the icon's dimming is its
         business and this only takes back the keybind afterwards. ]]--
    if EquadisOverhaulBlizzUsable then EquadisOverhaulBlizzUsable(target) end

    if not target.GetName then return end
    local name = target:GetName()
    if not name or not self:CommandForFrame(name) then return end

    local cfg = self:Config()
    if not OB.ModuleEnabled("actionbars") or not cfg.showHotkeys then return end

    self:PaintHotkey(getglobal(name .. "HotKey"))

    if cfg.showMacroNames then
        self:PaintMacroName(getglobal(name .. "Name"))
    end

    return true
end

function M:InstallHotkeyHook()
    if EquadisOverhaulBlizzHotkeys then return false end

    EquadisOverhaulBlizzHotkeys = ActionButton_UpdateHotkeys

    ActionButton_UpdateHotkeys = function(button, buttonType)
        local target = button or this
        if not target then return end

        return EquadisClassicOverhaul.modules.actionbars:UpdateHotkey(target)
    end

    return true
end

--[[ The other pass that paints keybinds. Same shape as the hook above and for
     the same reason -- see `UpdateUsable` -- and guarded on the saved original
     rather than on a field of this module's, because the module is rebuilt on a
     reload and the function it replaced is not. ]]--
function M:InstallUsableHook()
    if EquadisOverhaulBlizzUsable then return false end
    if type(ActionButton_UpdateUsable) ~= "function" then return false end

    EquadisOverhaulBlizzUsable = ActionButton_UpdateUsable

    ActionButton_UpdateUsable = function(button)
        local target = button or this
        if not target then return end

        return EquadisClassicOverhaul.modules.actionbars:UpdateUsable(target)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- bind mode
-- ---------------------------------------------------------------------------

--[[ **Hover a button, press a key, that is the binding.**

     The client's own binding interface is a list of two hundred command names
     with a box beside each, and finding "the third button on my bottom right
     bar" in it means counting. Nobody does it twice. Everybody who has used a
     hover-to-bind mode wants it in every game they play afterwards, and it is
     about eighty lines.

     Three pieces, and only the first is interesting.

     **Which button the mouse is over.** `GetMouseFocus` would answer this, and
     cannot be used: the capture frame has to take the mouse to stop a left click
     casting the spell instead of binding to it, and the moment it does,
     GetMouseFocus answers the capture frame. So the button is found by geometry
     instead -- `MouseIsOver` against each one -- which is unaffected by who owns
     the mouse and is a scan of eighty-eight rectangles once per keypress.

     **Which command that button answers to**, which the FAMILIES map above
     already knows because the text pass needed the same thing.

     **What key was pressed**, which is the key plus whatever modifiers were held,
     in the client's own order. ]]--
function M:BindMode()
    return self.binding and true or false
end

--[[ The command a frame is bound by, or nothing if it is not a button that can
     be bound.

     Anchored at both ends -- `^prefix(%d+)$` -- because "ActionButton1" is a
     prefix of "ActionButton12" and a loose match would bind the wrong slot on
     every second button. ]]--
function M:CommandForFrame(name)
    if not name then return nil end

    for f = 1, table.getn(FAMILIES) do
        local family = FAMILIES[f]
        local _, _, index = string.find(name, "^" .. family.prefix .. "(%d+)$")

        if index and tonumber(index) <= family.count then
            return family.binding .. index
        end
    end

    return nil
end

--[[ The key as the client spells it: modifiers in ALT, CTRL, SHIFT order, then
     the key. That order is not cosmetic -- `SetBinding("CTRL-ALT-F")` and
     `SetBinding("ALT-CTRL-F")` are two different strings, and only one of them
     is the one the client will look up when the keys are pressed. ]]--
function M:BindingName(key)
    if not key or key == "" then return nil end

    --[[ A modifier on its own is somebody reaching for a combination, not a
         binding. Treating it as one would bind Shift to the button under the
         cursor the instant they pressed it. ]]--
    if key == "LSHIFT" or key == "RSHIFT" then return nil end
    if key == "LCTRL" or key == "RCTRL" then return nil end
    if key == "LALT" or key == "RALT" then return nil end
    if key == "UNKNOWN" then return nil end

    local name = key

    if IsShiftKeyDown() then name = "SHIFT-" .. name end
    if IsControlKeyDown() then name = "CTRL-" .. name end
    if IsAltKeyDown() then name = "ALT-" .. name end

    return name
end

--[[ Every bindable button, asked by geometry rather than by focus. See BindMode
     for why. ]]--
function M:ButtonUnderMouse()
    if type(MouseIsOver) ~= "function" then return nil end

    for f = 1, table.getn(FAMILIES) do
        local family = FAMILIES[f]

        for i = 1, family.count do
            local button = getglobal(family.prefix .. i)

            if button and button:IsVisible() and MouseIsOver(button) then
                return family.prefix .. i, family.binding .. i
            end
        end
    end

    return nil
end

--[[ One binding, set and said out loud.

     **What was there before is named**, because the commonest thing that goes
     wrong with a hover-to-bind mode is taking a key off something you wanted --
     and the client says nothing when it does. Knowing you have just moved
     `CTRL-1` off your main bar is the difference between noticing now and
     noticing in a fight. ]]--
function M:Bind(key)
    local name = self:BindingName(key)
    if not name then return false end

    local buttonName, command = self:ButtonUnderMouse()
    if not command then return false end

    if type(SetBinding) ~= "function" then return false end

    --[[ Whatever held this key, before it stops holding it. ]]--
    local previous
    if type(GetBindingAction) == "function" then
        previous = GetBindingAction(name)
    end

    SetBinding(name, command)

    if previous and previous ~= "" and previous ~= command then
        Say(name .. " bound to " .. buttonName
                .. " -- taken from " .. previous .. ".")
    else
        Say(name .. " bound to " .. buttonName .. ".")
    end

    return true
end

--[[ Clearing one, which is the other half and is what the delete keys are for.
     A hover-to-bind mode with no way to unbind is a mode you can only ever add
     with. ]]--
function M:Unbind()
    local buttonName, command = self:ButtonUnderMouse()
    if not command then return false end

    if type(GetBindingKey) ~= "function" then return false end
    if type(SetBinding) ~= "function" then return false end

    local cleared = 0
    local key = GetBindingKey(command)

    while key do
        SetBinding(key)
        cleared = cleared + 1
        key = GetBindingKey(command)

        --[[ A guard, not a formality: if SetBinding fails silently -- a
             read-only binding set, a client mod -- GetBindingKey keeps answering
             the same key and this never returns. ]]--
        if cleared > 8 then break end
    end

    if cleared > 0 then
        Say("cleared " .. cleared .. " binding"
                .. (cleared == 1 and "" or "s") .. " from " .. buttonName .. ".")
    end

    return cleared > 0
end

--[[ The frame that takes the keyboard while the mode is on.

     Made once and hidden, rather than made on entry: a frame that grabs the
     keyboard is not a thing to be creating and destroying, and hiding one
     releases the keyboard just as well. ]]--
function M:BindFrame()
    if self.bindFrame then return self.bindFrame end

    local frame = CreateFrame("Frame", "EquadisOverhaulBindMode", UIParent)

    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    frame:EnableKeyboard(true)
    frame:EnableMouseWheel(true)
    frame:Hide()

    --[==[ **It has to say it is on, because it takes everything.**

         This frame covers the screen, takes the mouse and takes the keyboard.
         While it is up you cannot turn the camera, click a mob, or fire a
         keybind -- every one of those becomes a binding attempt instead. The
         only thing that still works is the scroll wheel, because
         `EnableMouseWheel` is on and nothing here handles it.

         All of that was announced once, in chat, and then drawn nowhere.
         Somebody who missed the line -- or scrolled past it, or came back to
         the keyboard a minute later -- is looking at a game that has stopped
         responding to the mouse and the keyboard at the same time, which reads
         as a crash rather than as a mode. It was reported as exactly that.

         So: a dimmed screen and a line of text. The dimming is the important
         half; the words are for once somebody looks. ]==]
    local shade = frame:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints(frame)
    shade:SetTexture(0, 0, 0, 0.35)

    local banner = CreateFrame("Frame", nil, frame)
    banner:SetWidth(420)
    banner:SetHeight(64)
    banner:SetPoint("TOP", frame, "TOP", 0, -140)
    if OB.SkinWindow then OB.SkinWindow(banner, 0.95) end

    local title = OB.NewText(banner, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", banner, "TOP", 0, -10)
    title:SetText("Bind Mode")

    local help = OB.NewText(banner, "OVERLAY", "GameFontHighlight")
    help:SetPoint("TOP", title, "BOTTOM", 0, -6)
    help:SetWidth(400)
    help:SetText("Hover a button and press a key. "
            .. "Delete clears it. Escape finishes.")

    --[[ Escape leaves. It is the one key that cannot be bound here, and that is
         the right trade: a mode with no way out that does not involve binding
         something is a trap. ]]--
    frame:SetScript("OnKeyDown", function()
        local m = OB.modules.actionbars

        if arg1 == "ESCAPE" then m:SetBindMode(false) return end
        if arg1 == "DELETE" or arg1 == "BACKSPACE" then m:Unbind() return end

        m:Bind(arg1)
    end)

    --[==[ **Mouse buttons, except the two the world needs.**

         This frame takes the mouse so that a click lands as a binding rather
         than casting the spell under it. That was applied to all five buttons,
         and the first two are not free: `BUTTON1` is `CAMERAORSELECTORMOVE` and
         `BUTTON2` is `TURNORACTION` -- clicking to select a target, and holding
         to turn the camera.

         So one left click while this mode was open bound the left mouse button
         to an action, `SaveBindings` wrote it to disk on the way out, and the
         game was left unable to select or turn. Reported as exactly that, and
         recovered by hand with
         `SetBinding("BUTTON1", "CAMERAORSELECTORMOVE")`.

         **A plain left or right click is now refused**, and says why rather
         than doing nothing -- a mode that ignores the most obvious gesture in
         it without comment reads as broken. Held with a modifier they are fine
         and still bindable: `SHIFT-BUTTON1` is not what the camera answers to.

         The other three have no such job and are unchanged. ]==]
    frame:SetScript("OnMouseDown", function()
        local m = OB.modules.actionbars
        local key = arg1

        if key == "LeftButton" then key = "BUTTON1" end
        if key == "RightButton" then key = "BUTTON2" end
        if key == "MiddleButton" then key = "BUTTON3" end
        if key == "Button4" then key = "BUTTON4" end
        if key == "Button5" then key = "BUTTON5" end

        if (key == "BUTTON1" or key == "BUTTON2") and not m:BindModifierHeld() then
            Say("the left and right mouse buttons move the camera and pick "
                    .. "targets, so they are left alone. Hold Shift, Control "
                    .. "or Alt with one to bind it.")
            return
        end

        m:Bind(key)
    end)

    frame:SetScript("OnMouseWheel", function()
        local m = OB.modules.actionbars
        m:Bind(arg1 > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)

    self.bindFrame = frame
    return frame
end

--[[ In and out of the mode.

     **Everything closes on the way in.** The whole point is an unobstructed
     view of the bars, and the settings panel is by some distance the largest
     thing likely to be over them -- it is where somebody was standing when they
     decided to do this. ]]--
--[[ Any modifier at all. A modified mouse button is a different binding from
     the bare one, so `SHIFT-BUTTON1` can be taken without touching what the
     camera answers to. ]]--
function M:BindModifierHeld()
    if type(IsShiftKeyDown) == "function" and IsShiftKeyDown() then return true end
    if type(IsControlKeyDown) == "function" and IsControlKeyDown() then return true end
    if type(IsAltKeyDown) == "function" and IsAltKeyDown() then return true end
    return false
end

function M:SetBindMode(on)
    if on and not OB.ModuleEnabled("actionbars") then
        Say("switch the Action Bars module on first.")
        return
    end

    self.binding = on and true or nil

    local frame = self:BindFrame()

    if self.binding then
        if OB.settings then OB.settings:Hide() end
        if type(CloseAllWindows) == "function" then CloseAllWindows() end

        --[==[ **Every empty slot, for as long as the mode is open.**

             You cannot hover a button that is not drawn, so a bar with three
             spells on it offered three bindable slots and nine you could see
             the gap for and not reach. The setting that governs this the rest
             of the time is not the right answer here: somebody binding keys is
             doing it *before* the bars are full, which is exactly when the
             empties matter most.

             Put back on the way out by `ApplyBarVisibility`, which reads the
             setting again -- so this borrows the grids rather than changing
             anybody's preference. ]==]
        if type(MultiActionBar_ShowAllGrids) == "function" then
            MultiActionBar_ShowAllGrids()
        end

        frame:Show()

        Say("bind mode on. Hover a button and press a key. "
                .. "Delete clears it, Escape finishes.")
    else
        frame:Hide()

        --[[ The grids go back to whatever the setting says, which is where
             `ApplyBarVisibility` reads it from. ]]--
        self:ApplyBarVisibility()

        --[[ Written to disk on the way out rather than on every key. A binding
             set is saved whole, and saving it eighty times while somebody works
             down a bar is eighty writes for one result. ]]--
        if type(SaveBindings) == "function" then
            local which = 1
            if type(GetCurrentBindingSet) == "function" then
                which = GetCurrentBindingSet()
            end

            SaveBindings(which)
        end

        Say("bind mode off. Bindings saved.")

        --[[ The text on the buttons is now wrong: the client rewrites its
             keybind strings, but the short form is ours to redo. ]]--
        self:ApplyText()
    end
end

-- ---------------------------------------------------------------------------
-- applying the lot
-- ---------------------------------------------------------------------------


function M:ApplyBars()
    local cfg = self:Config()

    for i = 1, table.getn(BARS) do
        local bar = BARS[i]
        local anchor = self:Anchor(bar.name, bar.point, bar.x, bar.y)
        self:PlaceAnchor(anchor, bar)

        --[[ One row unless asked otherwise, and every button unless asked
             otherwise -- so a bar nobody has touched looks exactly as it did.

             The pet and stance bars carry no rows setting of their own: ten in a
             row is the only arrangement anybody wants for either, and a slider
             that is only ever left alone is a row on the page earning
             nothing. ]]--
        local rows = cfg[bar.key .. "Rows"] or 1
        local shown = cfg[bar.key .. "Buttons"] or bar.count

        self:LayoutFamily(bar.prefix, bar.count, anchor, rows,
                cfg[bar.key .. "Spacing"] or 6,
                cfg[bar.key .. "Scale"] or 1,
                cfg[bar.key .. "Alpha"] or 1,
                shown)

        self:MirrorVisibility(anchor, bar)
    end
end

--[[ **Whether a bar is shown at all stays the client's decision.**

     It used to be one for free: the buttons were children of Blizzard's frames,
     so hiding `MultiBarBottomLeft` hid its twelve buttons and there was nothing
     to do. Re-parenting them onto a container of ours takes that away -- the
     container is always shown, so every bar would appear whether the client
     wanted it or not, including the pet bar with no pet and the stance bar on a
     warrior who has not learned a stance.

     So the container copies the frame the buttons came off. **The frame, not a
     rule of our own**: "the four multibar CVars, plus does the player have a
     pet, plus how many forms" is a list that is wrong on a private server and
     right nowhere for long. The client already knows, and it says so by showing
     or hiding exactly these eight frames.

     This is also why `PetActionBarFrame` is not in the art list. Hiding it
     would make its answer permanently "no pet". ]]--
function M:MirrorVisibility(anchor, bar)
    if not anchor or not bar.owner then return false end

    local owner = getglobal(bar.owner)
    if not owner or not owner.IsShown then return false end

    local show = owner:IsShown()

    --[==[ **The main bar stands down while the bonus bar is up.**

         These two are one bar in two frames. They occupy the same rectangle,
         they share `key = "main"` so they share every setting, and -- the part
         that matters -- `BonusActionButton` binds to `ACTIONBUTTON`, the same
         twelve commands as `ActionButton`. The client shows one or the other
         and never both.

         Copying the owner's shown state works for the bonus bar, whose owner
         appears and disappears with it. It does not work for the main bar,
         because its owner is `MainMenuBarArtFrame` -- the bar's *artwork*,
         which is shown the entire time you are logged in. So the main bar's
         anchor was shown the entire time too, bonus bar or not.

         **A warrior is the worst case and the one this was reported from.**
         Every warrior is in a stance from the first level, so
         `GetBonusBarOffset()` is above zero permanently and the bonus bar is
         permanently the live one. Both bars were drawn, one on top of the
         other, both answering keys 1 to 12, and which one a keypress reached
         was decided by client state with nothing on screen to indicate it.
         That is the "my keybinds do not work" report, and the "the main bar
         gets put back on top of the bonus bar" one: the same fault, seen from
         two sides.

         Asked of the bonus frame rather than of `GetBonusBarOffset` so there is
         one source of truth: the client's own decision about which bar is live,
         which is the same thing this reads for every other bar. ]==]
    if bar.name == "Main" and type(GetBonusBarOffset) == "function" then
        --[[ The client's own condition, out of `BonusActionBarFrame.lua`:
             a bonus bar is live when there is an offset and the main bar is on
             its first page. Asked this way rather than off the frame's shown
             flag, which a UI addon or a test harness can leave standing. ]]--
        local page = CURRENT_ACTIONBAR_PAGE or 1

        if (GetBonusBarOffset() or 0) > 0 and page == 1 then show = false end
    end

    if show then anchor:Show() else anchor:Hide() end

    return true
end

--[==[ **Every bar's visibility, re-copied.**

     `MirrorVisibility` was called from `ApplyBars` and nowhere else, so it ran
     at login and whenever a setting changed -- and then never again.

     That is not often enough for the two frames whose whole job is to appear
     and disappear. `BonusActionBarFrame` is shown by the client whenever you
     are in a druid form, a stance with a bonus bar, or stealth, and hidden the
     moment you leave; `PetActionBarFrame` comes and goes with the pet. The
     buttons have been reparented onto our own anchors by then, so the client
     hiding its frame no longer hides them -- it hides an empty container while
     the buttons carry on being drawn on ours.

     The result was the main bar and the bonus bar on screen together, both
     bound to `ACTIONBUTTON1` through `12`, and which one a key reached
     depending on client state nobody could see. Reported as keybinds that
     worked, then did not, and a bonus bar that kept reappearing under the main
     one.

     Five times a second, which is far more often than a form change and far
     less often than a frame. Eight `IsShown` calls and a `Show` or `Hide` only
     where the answer moved. ]==]
function M:MirrorAllVisibility()
    if not self.anchors then return false end

    for i = 1, table.getn(BARS) do
        local bar = BARS[i]
        local anchor = self.anchors[bar.name]

        if anchor then self:MirrorVisibility(anchor, bar) end
    end

    return true
end

function M:Apply()
    if not OB.ModuleEnabled("actionbars") then return end

    --[[ Bars before art: the buttons have to be off Blizzard's frames before
         anything is done to those frames. ]]--
    self:ApplyBars()
    self:StyleArt()
    self:ApplyText()
    --[[ Before the layout: a bar that is about to be shown has to exist
         before anything can be measured or moved. ]]--
    self:ApplyBarVisibility()
    self:ApplyBagButton()
    self:ApplyProgressBars()
    self:ApplyButtonBar("bag")
    self:ApplyButtonBar("micro")
    self:ApplyButtonBar("paging")
    self:ApplyPerformanceText()
end

--[==[ **The faction you last earned reputation with.**

     Read out of the client's own sentence rather than matched against English,
     which is the rule every other line in this addon follows: whatever the
     client says is what gets read, in whatever language it says it.

     Both directions are watched. Losing reputation is still earning it in the
     sense that matters here -- you are doing something to that faction, and it
     is the one you want to see. ]==]
local FACTION_LINES = { "FACTION_STANDING_INCREASED", "FACTION_STANDING_DECREASED" }

function M:ReadFactionLine(text)
    if not text then return nil end

    for i = 1, table.getn(FACTION_LINES) do
        local sentence = getglobal(FACTION_LINES[i])

        if sentence then
            local name = OB.ParseLine(text, sentence)
            if name then return name end
        end
    end

    return nil
end

--[==[ **One faction's numbers, by name.**

     `GetFactionInfo` walks a list that contains headers as well as factions,
     and a header has no standing -- so the standing is what says which is
     which. Reading a header as a faction gives a bar with nil bounds, which
     draws as full or as empty depending on which nil is divided by which. ]==]
function M:FactionByName(want)
    if not want then return nil end
    if type(GetNumFactions) ~= "function" then return nil end
    if type(GetFactionInfo) ~= "function" then return nil end

    for i = 1, (GetNumFactions() or 0) do
        local name, _, standing, low, high, value = GetFactionInfo(i)

        if name == want and type(standing) == "number"
                and type(low) == "number" and type(high) == "number"
                and type(value) == "number" then
            return name, standing, low, high, value
        end
    end

    return nil
end

function M:OnEvent()
    if event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        local name = self:ReadFactionLine(arg1)

        --[[ Remembered even when a faction is pinned, so switching the pin off
             later has something to fall back to straight away rather than
             waiting for the next kill. ]]--
        if name then self.latestFaction = name end
    end

    self:Apply()
end


-- ---------------------------------------------------------------------------
-- giving the client its bars back
-- ---------------------------------------------------------------------------

--[[ **What the buttons looked like before this module touched them.**

     This lived in `actionbarchrome.lua` alongside the Dragonflight look, and the
     look has been scrapped. The restore has not: it is the half that matters,
     because re-parenting somebody's action bars onto frames of ours is only
     acceptable if switching the module off puts them back.

     Captured once, at the first bind, before the layout pass has moved
     anything. A second capture would record our own arrangement as the original
     and restore to it, which is not a restore. ]]--
local RESTORE_ART = {
    "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "SlidingActionBarTexture0", "SlidingActionBarTexture1",
    "BonusActionBarTexture0", "BonusActionBarTexture1",
    "ShapeshiftBarLeft", "ShapeshiftBarMiddle", "ShapeshiftBarRight",
}

local RESTORE_ART_FRAMES = { "MainMenuBar", "MainMenuBarArtFrame", "PetActionBarFrame" }

local function capturePoints(frame)
    local points = {}
    if not frame or not frame.GetPoint then return points end

    local count = 1
    if frame.GetNumPoints then count = frame:GetNumPoints() or 1 end
    if count < 1 then count = 1 end

    for i = 1, count do
        local point, relative, relativePoint, x, y = frame:GetPoint(i)
        if point then
            table.insert(points, {
                point = point,
                relative = relative,
                relativePoint = relativePoint,
                x = x or 0,
                y = y or 0,
            })
        end
    end

    return points
end

local function restorePoints(frame, points)
    if not frame or not points or table.getn(points) == 0 then return end
    frame:ClearAllPoints()
    for i = 1, table.getn(points) do
        local p = points[i]
        frame:SetPoint(p.point, p.relative, p.relativePoint, p.x, p.y)
    end
end

function M:CaptureOriginals()
    if self.originalButtons then return false end

    self.originalButtons = {}

    for f = 1, table.getn(FAMILIES) do
        local family = FAMILIES[f]

        for i = 1, family.count do
            local button = getglobal(family.prefix .. i)

            if button and not self.originalButtons[button] then
                self.originalButtons[button] = {
                    parent = button.GetParent and button:GetParent() or nil,
                    points = capturePoints(button),
                    scale = button.GetScale and button:GetScale() or 1,

        --[[ Size too, because the finders are resized to match the row they
             join. Without it, switching the bar off would hand back a round
             minimap button squared off to micro-button dimensions. ]]--
        width = button.GetWidth and button:GetWidth() or nil,
        height = button.GetHeight and button:GetHeight() or nil,
                    alpha = button.GetAlpha and button:GetAlpha() or 1,
                }
            end
        end
    end

    return true
end

function M:RestoreBlizzardActionBars()
    if self.originalButtons then
        for button, saved in pairs(self.originalButtons) do
            if button and saved then
                if button.SetParent and saved.parent then button:SetParent(saved.parent) end
                if button.SetScale then button:SetScale(saved.scale or 1) end
                if button.SetAlpha then button:SetAlpha(saved.alpha or 1) end

                --[[ A button hidden by the Buttons Shown slider is shown again:
                     that count is this module's opinion, and handing the bars
                     back means handing back all of them. ]]--
                button.ecoHiddenByCount = nil
                if button.Show then button:Show() end

                restorePoints(button, saved.points)
            end
        end
    end

    --[[ The art is hidden reversibly by `StyleArt`, but once the module is
         switched off its `Apply` correctly stops running -- so the client's own
         furniture is put back here rather than left as an invisible bar. ]]--
    for i = 1, table.getn(RESTORE_ART) do
        local region = getglobal(RESTORE_ART[i])
        if region then
            if region.SetAlpha then region:SetAlpha(1) end
            if region.Show then region:Show() end
        end
    end

    for i = 1, table.getn(RESTORE_ART_FRAMES) do
        local frame = getglobal(RESTORE_ART_FRAMES[i])
        if frame and frame.EnableMouse then frame:EnableMouse(true) end
    end

    if self.anchors then
        for _, anchor in pairs(self.anchors) do
            if anchor and anchor.Hide then anchor:Hide() end
        end
    end

    if type(UIParent_ManageFramePositions) == "function" then
        UIParent_ManageFramePositions()
    end

    return true
end

-- ---------------------------------------------------------------------------
-- how long is left on a cooldown
-- ---------------------------------------------------------------------------

--[[ **1.12 draws a sweeping shadow and never says how many seconds.**

     Which is fine for a two second cooldown and useless for a five minute one:
     the difference between a shadow at a quarter and a shadow at a third is not
     a thing anybody can read off a 30 pixel button, and the answer -- "ninety
     seconds" -- is one the client already knows.

     **There is no Cooldown frame type in this client**, so there is nothing to
     hook a method on. Every cooldown in the game goes through one global,
     `CooldownFrame_SetTimer`, and that is the seam. It catches action buttons,
     bag items, inventory slots and anything an addon starts through the same
     function, which is why this belongs here rather than being wired into the
     action bars one button at a time.

     Ported from ShaguTweaks' `cooldown-numbers`, which is the version known to
     work on this client, including the part that looks like nonsense below. ]]--

--[[ Under two seconds is the global cooldown, and a number that appears on
     every single cast and is gone before it can be read is noise on top of a
     shadow that already says the same thing. ]]--
local MIN_COOLDOWN = 2

--[[ Ten times a second. The number changes once a second, so this is four times
     more often than it needs to be and cheap enough not to matter -- and at one
     second exactly the displayed value would visibly lag the real one. ]]--
local COOLDOWN_TICK = 0.1

--[[ **Red under five seconds, yellow under ten.** The one thing a cooldown
     number is read for in a fight is "is it back yet", and the answer at four
     seconds is a different answer to the one at forty. ]]--
function OB.CountdownText(remaining)
    local colour = "|cffffffff"

    if remaining < 5 then
        colour = "|cffff5555"
    elseif remaining < 10 then
        colour = "|cffffff55"
    end

    if remaining < 60 then
        return colour .. math.ceil(remaining)
    elseif remaining < 3600 then
        return colour .. math.ceil(remaining / 60) .. "m"
    elseif remaining < 86400 then
        return colour .. math.ceil(remaining / 3600) .. "h"
    end

    return colour .. math.ceil(remaining / 86400) .. "d"
end

local function cooldownTick()
    --[[ A cooldown whose parent has gone is a frame updating forever over
         nothing. ]]--
    local parent = this:GetParent()
    if not parent then this:Hide() return end

    if not this.tick then this.tick = GetTime() + COOLDOWN_TICK end
    if this.tick > GetTime() then return end
    this.tick = GetTime() + COOLDOWN_TICK

    --[[ Alpha should be inherited from the parent and is not always, so it is
         set. A button faded because it is out of range takes its number with
         it, rather than leaving a bright number on a dim button. ]]--
    if parent.GetAlpha and this.SetAlpha then this:SetAlpha(parent:GetAlpha()) end

    if this.start and this.start < GetTime() then
        local remaining = this.duration - (GetTime() - this.start)

        if remaining > 0 then
            this.text:SetText(OB.CountdownText(remaining))
        else
            this:Hide()
        end

        return
    end

    --[[ **A start time in the future, which is the client's clock wrapping.**

         `GetTime` counts from a machine's own uptime and rolls over at 2^32
         milliseconds, so a cooldown started before the wrap has a start time
         *after* the current one. The arithmetic below reconstructs it through
         wall-clock `time()`, and is kept in the shape ShaguTweaks worked it out
         in rather than rewritten into something that reads better and is
         subtly different. ]]--
    local now = time()
    local startupTime = now - GetTime()
    local cdTime = (2 ^ 32) / 1000 - (this.start or 0)
    local cdStartTime = startupTime - cdTime
    local cdEndTime = cdStartTime + (this.duration or 0)
    local remaining = cdEndTime - now

    if remaining >= 0 then
        this.text:SetText(OB.CountdownText(remaining))
    else
        this:Hide()
    end
end

local function makeCooldownText(cooldown)
    local parent = cooldown:GetParent()
    if not parent then return nil end

    local name = (parent.GetName and parent:GetName()) or "EqEcoCooldown"

    local holder = CreateFrame("Frame", name .. "EqEcoCooldownText", cooldown)
    holder:SetAllPoints(cooldown)

    if holder.SetFrameLevel and parent.GetFrameLevel then
        holder:SetFrameLevel((parent:GetFrameLevel() or 0) + 1)
    end

    holder.text = holder:CreateFontString(nil, "OVERLAY")

    --[[ **Sized from the button rather than set.** The same hook serves a 36
         pixel action button and a 30 pixel bag slot, and one font size cannot
         be right for both -- too big overflows the icon, too small is not
         readable at a glance mid-fight. Capped, because a very large button
         does not want very large text. ]]--
    local size = (parent.GetHeight and parent:GetHeight()) or 0
    size = size > 0 and size * 0.64 or 12
    if size > 14 then size = 14 end

    holder.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    holder.text:SetPoint("CENTER", holder, "CENTER", 0, 0)

    holder:SetScript("OnUpdate", cooldownTick)

    cooldown.eqEcoCooldownText = holder
    return holder
end

--[[ Wrapped round the client's own function rather than replacing it: every
     cooldown in the game is still started the way it always was, and this only
     watches. ]]--
function OB.InstallCooldownNumbers()
    if OB.cooldownNumbersInstalled then return false end
    if type(CooldownFrame_SetTimer) ~= "function" then return false end

    OB.cooldownNumbersInstalled = true

    local original = CooldownFrame_SetTimer

    CooldownFrame_SetTimer = function(frame, start, duration, enable)
        original(frame, start, duration, enable)

        if not frame then return end

        --[[ OmniCC's own flag, honoured so that somebody running both does not
             get two numbers on every button. ]]--
        if frame.noCooldownCount then return end

        if not OB.CooldownNumbersWanted() then
            if frame.eqEcoCooldownText then frame.eqEcoCooldownText:Hide() end
            return
        end

        if not duration or duration < MIN_COOLDOWN then
            if frame.eqEcoCooldownText then frame.eqEcoCooldownText:Hide() end
            return
        end

        local holder = frame.eqEcoCooldownText or makeCooldownText(frame)
        if not holder then return end

        holder.start = start
        holder.duration = duration

        if start and start > 0 and duration > 0
                and (not enable or enable > 0) then
            holder:Show()
        else
            holder:Hide()
        end
    end

    return true
end

--[[ Asked per cooldown rather than installed and uninstalled, because the hook
     cannot be taken off again: something else may have wrapped it since, and
     unwrapping in the middle of a chain deletes whatever wrapped it after. ]]--
function OB.CooldownNumbersWanted()
    if not OB.ModuleEnabled("actionbars") then return false end

    local cfg = OB.profile and OB.profile.modules
            and OB.profile.modules.actionbars

    return (cfg and cfg.cooldownNumbers) and true or false
end

-- ---------------------------------------------------------------------------
-- experience and reputation
-- ---------------------------------------------------------------------------

--[[ **The client's own experience bar is a sliver of art under the action bars**
     with no numbers on it, and its reputation bar is the same sliver with a
     different colour. Neither says how far through you are, and the one question
     anybody asks a levelling bar is "how much left".

     So: one bar each, drawn with this addon's own media, with the numbers on
     them -- and a rested overlay, because resting is worth seeing rather than
     working out from a colour.

     **`UnitXP` cannot be trusted here, and that is not a hypothetical.**

     Stock 1.12 answers `UnitXP("player")` with a number. UnitXP_SP3 -- which a
     great many Turtle clients run -- replaces that same global with a command
     dispatcher, and a build that does not pass unknown commands through returns
     nil for it. Asking the obvious way fails on exactly the client this addon
     is for.

     The client's own bar is immune, because the client fills `MainMenuExpBar`
     from its internal values whatever an addon did to the global. So the global
     is tried, its answer is checked for being a number, and the bar is read when
     it is not. ]]--

--[[ Read rather than trusted. A `pcall` because the stock version *errors* on a
     unit token it does not know, and the SP3 version returns nil -- two
     different failures from one call, and neither should take the bar down. ]]--
function M:PlayerXP()
    local current, max

    if type(UnitXP) == "function" then
        local ok, value = pcall(UnitXP, "player")
        if ok and type(value) == "number" then current = value end
    end

    if type(UnitXPMax) == "function" then
        local ok, value = pcall(UnitXPMax, "player")
        if ok and type(value) == "number" then max = value end
    end

    --[[ **The client's own bar, which no addon can have overridden**, because
         the client fills it from values an addon cannot reach. ]]--
    if type(current) ~= "number" or type(max) ~= "number" or max <= 0 then
        local bar = getglobal("MainMenuExpBar")

        if bar and bar.GetValue and bar.GetMinMaxValues then
            local low, high = bar:GetMinMaxValues()
            current = bar:GetValue()
            max = high
            if low and low ~= 0 and current then current = current - low end
        end
    end

    if type(current) ~= "number" then current = 0 end
    if type(max) ~= "number" then max = 0 end

    return current, max
end

--[[ Rested is a pool of bonus experience, not a rate, and most of a levelling
     life is spent with none -- so nothing to draw is the ordinary case. ]]--
function M:RestedXP()
    if type(GetXPExhaustion) ~= "function" then return 0 end

    local ok, value = pcall(GetXPExhaustion)
    if not ok or type(value) ~= "number" then return 0 end

    return value
end

--[[ Nobody is required to be watching a faction, so "nothing to show" is an
     ordinary answer rather than a fault. ]]--
function M:WatchedFaction()
    if type(GetWatchedFactionInfo) ~= "function" then return nil end

    local ok, name, standing, low, high, value = pcall(GetWatchedFactionInfo)
    if not ok or not name then return nil end

    if type(low) ~= "number" or type(high) ~= "number"
            or type(value) ~= "number" then
        return nil
    end

    --[[ Reputation is reported as absolute totals within a band, so the bar
         wants the position *inside* the band rather than the raw number: the
         difference between 8,400 and 12,000 is the whole of "how far through
         Honored am I". ]]--
    return name, standing, value - low, high - low
end

--[==[ **What the bar shows, which is not always what is pinned.**

     A pinned faction wins outright: pinning is an instruction and this is only
     a guess about what to do without one. With nothing pinned the bar used to
     have nothing to draw, which is a strip of screen earning nothing for the
     majority of players who never pin anything.

     The faction you last earned reputation with is almost always the one you
     care about at that moment -- you are grinding it, which is why the line
     appeared in your log at all. ]==]
function M:BarFaction()
    local name, standing, value, max = self:WatchedFaction()
    if name then return name, standing, value, max end

    if not self:Config().repFollowsLatest then return nil end

    local fname, fstanding, low, high, fvalue = self:FactionByName(self.latestFaction)
    if not fname then return nil end

    return fname, fstanding, fvalue - low, high - low
end

--[[ **The standing's name, which the bar has never had anywhere to put.**

     `GetWatchedFactionInfo` answers with an index, and the client keeps the
     words in `FACTION_STANDING_LABEL<n>`. Those globals are what a player
     already reads on every other reputation surface, so they win -- but a
     private client is free not to define them, and the test client does not,
     so 1.12's English sits behind them rather than the line going blank. ]]--
local STANDING_LABELS = {
    "Hated", "Hostile", "Unfriendly", "Neutral",
    "Friendly", "Honored", "Revered", "Exalted",
}

function M:StandingLabel(standing)
    if type(standing) ~= "number" then return nil end
    if standing < 1 or standing > table.getn(STANDING_LABELS) then
        return nil
    end

    if getglobal then
        local label = getglobal("FACTION_STANDING_LABEL" .. standing)
        if type(label) == "string" and label ~= "" then return label end
    end

    return STANDING_LABELS[standing]
end

--[==[ **What the reputation bar says when you point at it.**

     The bar has room for the faction and the numbers and that is what it
     draws, but the standing is the thing a player is actually tracking -- "am
     I Revered yet" -- and it was the one part of the answer nowhere on screen.

     Returned as three pieces of data rather than written straight into the
     tooltip, so the wording can be checked without a mouse. A faction whose
     standing does not resolve still gets its name and numbers: a missing rank
     is a reason to say less, not to say nothing. ]==]
function M:RepTooltipLines()
    local name, standing, value, max = self:BarFaction()
    if not name then return nil end

    local progress = nil
    if type(value) == "number" and type(max) == "number" and max > 0 then
        progress = string.format("%s / %s (%d%%)", OB.Round(value),
                OB.Round(max), math.floor((value / max) * 100 + 0.5))
    end

    return name, self:StandingLabel(standing), progress
end

function M:ShowRepTooltip(frame)
    if not frame or not GameTooltip then return false end

    local name, rank, progress = self:RepTooltipLines()
    if not name then return false end

    --[[ The client's own tooltip, off the bar's right so it never covers the
         bar it is describing. ]]--
    OB.OwnTooltip(frame, "ANCHOR_RIGHT")
    GameTooltip:AddLine(name)
    if rank then GameTooltip:AddLine(rank, 1, 1, 1) end
    if progress then GameTooltip:AddLine(progress, 1, 1, 1) end
    GameTooltip:Show()

    return true
end

function M:ProgressFrame(key, name)
    self.progress = self.progress or {}
    if self.progress[key] then return self.progress[key] end
    if not CreateFrame then return nil end

    local frame = CreateFrame("StatusBar", "EquadisClassicOverhaul" .. name,
            UIParent)

    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(0, 0, 0, 0.5)

    --[[ **Rested drawn behind the fill rather than over it**, so the bar still
         reads as one bar: the rested pool is where your experience is *going*,
         and a second bar in front of the first reads as two competing numbers. ]]--
    if key == "xp" then
        frame.rested = frame:CreateTexture(nil, "ARTWORK")
        frame.rested:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.rested:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.rested:SetTexture(0.25, 0.4, 0.9, 0.55)
        frame.rested:Hide()
    end

    --[==[ **Both bars take the mouse now.**

         Only the reputation bar did, because the experience bar's label was
         held to carry everything there was to say about it. That stopped being
         true twice over: the label is three switches and can be emptied
         entirely, and rested was never in it -- it is drawn as a paler stretch
         of bar that says how far it reaches and never how much it is.

         Which is what makes hiding a piece cheap. Nothing on either bar becomes
         unreachable when it is switched off; it stops taking up a strip of
         screen and stays a hover away.

         Both frames are hidden whenever they have nothing to show, so neither is
         ever in the way while silent.

         Silent while the frames are being dragged about: edit mode puts its own
         outline over the bar, and a tooltip on top of that is answering a
         question nobody asked. ]==]
    frame:EnableMouse(true)

    frame:SetScript("OnEnter", function()
        if OB.editMode then return end

        local mod = OB.modules and OB.modules.actionbars
        if not mod then return end

        if key == "rep" then
            mod:ShowRepTooltip(this)
        else
            mod:ShowXPTooltip(this)
        end
    end)

    frame:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    frame.text = OB.NewText(frame, "OVERLAY", "GameFontNormalSmall")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame:SetScript("OnDragStop", function()
        if this.StopMovingOrSizing then this:StopMovingOrSizing() end
        OB.modules.actionbars:StoreProgressPosition(key, this)
    end)

    if OB.MarkMovable then OB.MarkMovable(frame, name) end

    self.progress[key] = frame
    return frame
end

function M:StoreProgressPosition(key, frame)
    if not frame or not frame.GetLeft or not frame:GetLeft() then return false end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.positions["progress_" .. key] = {
        x = OB.Round((frame:GetLeft() + (frame:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((frame:GetBottom() + (frame:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

--[[ One bar, placed, filled and labelled. Both bars are the same shape, so the
     only thing that differs is what the numbers mean. ]]--
function M:StyleProgressBar(key, name, value, max, label, colour, defaultY)
    local cfg = self:Config()
    local frame = self:ProgressFrame(key, name)
    if not frame then return false end

    local look = OB.Look("actionbars")

    frame:SetWidth(tonumber(cfg.progressWidth) or 460)
    frame:SetHeight(tonumber(cfg.progressHeight) or 12)

    if frame.SetStatusBarTexture then
        frame:SetStatusBarTexture(OB.textures[look.texture] or OB.textures[1])
    end

    local saved = cfg.positions and cfg.positions["progress_" .. key]

    frame:ClearAllPoints()

    if saved then
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    else
        frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, defaultY)
    end

    if max <= 0 then
        frame:Hide()
        return false
    end

    frame:SetMinMaxValues(0, max)
    frame:SetValue(value)
    frame:SetStatusBarColor(colour[1], colour[2], colour[3], 1)

    frame.text:SetText(label)
    OB.ApplyFont(frame.text, nil, "actionbars")

    frame:Show()
    return true
end

--[[ **A percentage as well as the raw numbers**, because "12,400 / 18,000" is
     two numbers to divide and "69%" is the answer to the question actually
     being asked. ]]--
local function progressNumbers(value, max)
    if type(value) ~= "number" or type(max) ~= "number" or max <= 0 then
        return nil
    end

    return string.format("%s / %s (%d%%)", OB.Round(value), OB.Round(max),
            math.floor((value / max) * 100 + 0.5))
end

--[==[ **Whichever pieces are switched on, spaced apart.**

     Written as a join rather than a format string because any of the three can
     be absent: a format leaves the gaps behind, so turning the faction name off
     would leave the numbers indented by nothing, and turning two off would leave
     a rank floating in the middle of a strip. Two spaces between what is there,
     nothing where something is not. ]==]
local function joinParts(a, b, c)
    local parts, out = { a, b, c }, ""

    for i = 1, 3 do
        local part = parts[i]

        if type(part) == "string" and part ~= "" then
            if out ~= "" then out = out .. "  " end
            out = out .. part
        end
    end

    return out
end

--[[ **What the reputation bar draws**, or nil when there is no faction at all --
     which is a different answer from an empty string, and the caller hides the
     bar for the first and draws a bare bar for the second. ]]--
function M:RepBarText()
    local cfg = self:Config()
    local name, standing, value, max = self:BarFaction()

    if not name then return nil end

    return joinParts(
            cfg.repShowFaction and name or nil,
            cfg.repShowStanding and self:StandingLabel(standing) or nil,
            cfg.repShowProgress and progressNumbers(value, max) or nil)
end

--[[ And the experience bar's. `XP` rather than the level, because the level is
     already on the character panel, the unit frame and the chat -- what this bar
     is for is the part of it that is not. ]]--
function M:XPBarText()
    local cfg = self:Config()
    local value, max = self:PlayerXP()

    local rested = self:RestedXP()
    local restedText = nil

    if cfg.xpShowRested and type(rested) == "number" and rested > 0 then
        restedText = "+" .. OB.Round(rested) .. " rested"
    end

    return joinParts(
            cfg.xpShowLabel and "XP" or nil,
            cfg.xpShowProgress and progressNumbers(value, max) or nil,
            restedText)
end

--[==[ **Everything, whatever the bar is showing.**

     The reputation bar has had this since the standing had nowhere else to go;
     the experience bar had none at all, on the reasoning that its label already
     carried everything there was to say about it. That reasoning ended twice
     over: the label is now three switches and can be empty, and rested was never
     in it -- it was drawn as a paler stretch of bar that says how far it reaches
     and never how much it is. ]==]
function M:XPTooltipLines()
    local value, max = self:PlayerXP()
    if type(max) ~= "number" or max <= 0 then return nil end

    local level = type(UnitLevel) == "function" and UnitLevel("player")
    local rested = self:RestedXP()

    local restedText = nil
    if type(rested) == "number" and rested > 0 then
        restedText = OB.Round(rested) .. " rested"
    end

    return (type(level) == "number" and level > 0)
                    and ("Level " .. level) or "Experience",
            progressNumbers(value, max), restedText
end

function M:ShowXPTooltip(frame)
    if not frame or not GameTooltip then return false end

    local title, progress, rested = self:XPTooltipLines()
    if not title then return false end

    OB.OwnTooltip(frame, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if progress then GameTooltip:AddLine(progress, 1, 1, 1) end
    if rested then GameTooltip:AddLine(rested, 1, 1, 1) end
    GameTooltip:Show()

    return true
end

--[[ **At the cap there is no experience, whatever the client answers.**

     The bar hid itself when `UnitXPMax` returned nothing, which is what a
     plain 1.12 client does at sixty. This one keeps answering a real number --
     217400 with 58 earned against it -- so the bar stayed on screen showing
     nought per cent for the rest of the character's life.

     The level is the honest question. `MAX_PLAYER_LEVEL` is the client's own
     answer to where the cap is, so a server that raised it says so and the bar
     keeps working up to the new one. ]]--
function M:AtLevelCap()
    if type(UnitLevel) ~= "function" then return false end

    local level = UnitLevel("player")
    if type(level) ~= "number" or level <= 0 then return false end

    return level >= (tonumber(MAX_PLAYER_LEVEL) or 60)
end

-- ---------------------------------------------------------------------------
-- the bag slots and the micro menu, as bars you can put somewhere
-- ---------------------------------------------------------------------------

--[[ **Two rows of buttons the client nails to one corner.**

     The bag slots and the micro menu are ordinary buttons parented to the main
     bar art, laid out by the client and movable by nobody. This addon already
     offered to *hide* each set, which is the blunt answer: somebody who wants
     their bags somewhere else does not want them gone.

     Gathered into a bar of their own, which can be scaled, spaced and dragged
     like anything else here. **Where each button came from is recorded before
     it is moved**, once, so switching the bar off puts every one of them back
     -- the same rule the minimap icon tray follows, and for the same reason: a
     button that cannot be put back is a button somebody has lost. ]]--

--[[ The paging arrows and the page number, which travel together: an arrow
     without the number it changes is half a control. ]]--
local PAGE_BUTTONS = {
    "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarPageNumber",
}

local MICRO_BUTTONS = {
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
    "MainMenuMicroButton", "HelpMicroButton",
    --[[ Turtle's own, absent on a stock client and skipped there. ]]--
    "LFGMicroButton", "PVPMicroButton", "ShopMicroButton",

    --[==[ **The group and battleground finders are not in this row.**

         They were, twice. First as the minimap frames reparented into it, which
         is the wrong shape for half of them: `MiniMapBattlefieldFrame` and
         `MiniMapMeetingStoneFrame` are `hidden="true"` in the client's own
         `Minimap.xml` and are shown only while you are queued, so the row either
         carried an icon that meant nothing or grew and lost a button as you
         joined and left a queue.

         Then as buttons of ours that forwarded the click to whichever finder
         this client has. That works, and it costs the Looking For Team eye its
         animation: the eye moves while it is searching, that movement belongs
         to the frame the client built, and a hidden frame gets no `OnUpdate`.
         The choice was a still icon in the row or a moving one on the minimap.

         The minimap won. They are left exactly where the client puts them. ]==]
}

--[[ Buttons that are not micro buttons but join their row and need squaring up
     to sit in it. Empty while the only candidates were the finders -- kept
     because the row is the one place a non-micro button would ever be added,
     and the sizing and dressing that make it fit are still here. ]]--
local MICRO_MATCH = {}

local BUTTON_BARS = {
    bag = { list = BAG_BUTTONS, name = "BagBar", label = "Bag Bar",
            setting = "bagBar", scale = "bagBarScale",
            spacing = "bagBarSpacing", y = 44 },
    micro = { list = MICRO_BUTTONS, name = "MicroBar", label = "Micro Menu",
            setting = "microBar", scale = "microBarScale",
            spacing = "microBarSpacing", y = 78 },
    --[[ **Paging is the same problem a third time**, so it is the same code.

         The arrows and the page number are three client buttons nailed to
         the bar art. Somebody who pages their bars wants them reachable;
         somebody who does not wants them gone -- and Hide Elements already
         offers the second. This offers the first. ]]--
    paging = { list = PAGE_BUTTONS, name = "PagingBar", label = "Paging",
            setting = "pagingBar", scale = "pagingBarScale",
            spacing = "pagingBarSpacing", y = 112 },
}

function M:ButtonBar(key)
    local spec = BUTTON_BARS[key]
    if not spec or not CreateFrame then return nil end

    self.buttonBars = self.buttonBars or {}
    if self.buttonBars[key] then return self.buttonBars[key] end

    local bar = CreateFrame("Frame", "EquadisClassicOverhaul" .. spec.name,
            UIParent)

    bar:SetWidth(10)
    bar:SetHeight(10)
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, spec.y)

    if OB.MarkMovable then OB.MarkMovable(bar, spec.label) end

    bar:SetScript("OnDragStop", function()
        if this.StopMovingOrSizing then this:StopMovingOrSizing() end
        OB.modules.actionbars:StoreButtonBarPosition(key, this)
    end)

    self.buttonBars[key] = bar
    return bar
end

--[[ Recorded once, the first time a button is taken. A second recording would
     save where this bar put it and the way home would be gone. ]]--
--[[ **A minimap button wearing the micro row's clothes.**

     Read off a real micro button rather than written here: whatever the client
     or a UI addon has made those look like, these match. A path hardcoded now
     would be wrong on the next client that restyles them.

     The frame is not replaced. The group finder's eye animates while it is
     searching, and that animation belongs to the frame the client built -- a
     button of ours wearing a copy of its icon would sit perfectly still. This
     changes the art *behind* the icon and leaves the icon, its animation and
     its click handler alone. ]]--
function M:DressAsMicroButton(button, ref)
    if not button or not ref then return false end
    if not button.SetNormalTexture or not ref.GetNormalTexture then return false end

    self.buttonDressed = self.buttonDressed or {}

    local name = button.GetName and button:GetName()
    if not name then return false end

    --[[ What it wore before, kept once so the switch is reversible. A second
         recording would save the borrowed art as the original. ]]--
    if not self.buttonDressed[name] then
        local function pathOf(tex)
            if tex and tex.GetTexture then return tex:GetTexture() end
            return nil
        end

        self.buttonDressed[name] = {
            normal = pathOf(button:GetNormalTexture()),
            pushed = button.GetPushedTexture and pathOf(button:GetPushedTexture()),
            highlight = button.GetHighlightTexture
                    and pathOf(button:GetHighlightTexture()),
        }
    end

    local function copy(get, set)
        if not ref[get] or not button[set] then return end

        local tex = ref[get](ref)
        local path = tex and tex.GetTexture and tex:GetTexture()

        if path then button[set](button, path) end
    end

    copy("GetNormalTexture", "SetNormalTexture")
    copy("GetPushedTexture", "SetPushedTexture")
    copy("GetHighlightTexture", "SetHighlightTexture")

    return true
end

--[[ Back to whatever it wore before, including nothing: a minimap button that
     had no normal texture must not keep a micro button's. ]]--
function M:UndressButton(button)
    local name = button and button.GetName and button:GetName()
    local worn = name and self.buttonDressed and self.buttonDressed[name]

    if not worn then return false end

    if button.SetNormalTexture then button:SetNormalTexture(worn.normal) end
    if button.SetPushedTexture then button:SetPushedTexture(worn.pushed) end

    if button.SetHighlightTexture then
        button:SetHighlightTexture(worn.highlight)
    end

    self.buttonDressed[name] = nil
    return true
end

function M:RememberButtonHome(button)
    local name = button and button.GetName and button:GetName()
    if not name then return false end

    self.buttonHomes = self.buttonHomes or {}
    if self.buttonHomes[name] then return false end

    local point, rel, relPoint, x, y = button:GetPoint(1)

    self.buttonHomes[name] = {
        parent = button:GetParent(),
        point = point, rel = rel, relPoint = relPoint, x = x, y = y,
        scale = button.GetScale and button:GetScale() or 1,

        --[[ Size too, because the finders are resized to match the row they
             join. Without it, switching the bar off would hand back a round
             minimap button squared off to micro-button dimensions. ]]--
        width = button.GetWidth and button:GetWidth() or nil,
        height = button.GetHeight and button:GetHeight() or nil,
    }

    return true
end

-- ---------------------------------------------------------------------------
-- latency and frame rate, as numbers
-- ---------------------------------------------------------------------------

--[[ **A green bar does not say how many milliseconds.**

     The client draws latency as a bar that turns yellow and then red, and you
     have to hover it to learn the number -- which the tooltip then explains at
     length. The number is the whole content: 53ms and 350ms are different
     situations and the bar shows both as "a bit of green".

     So: text. Frame rate beside it, because the pair answer the same question
     -- is it me or is it the server -- and reading one without the other
     answers half of it.

     **Coloured by what the number means**, on the thresholds somebody actually
     uses: under 40 is good, 100 is worth noticing, 350 is bad and 500 is
     unplayable. The colours run green, yellow, orange, red across those, which
     is the same language the client's own bar speaks -- it just says it in a
     number as well. ]]--
local PING_STEPS = {
    { limit = 40,  color = { 0.20, 0.85, 0.25 } },   -- green
    { limit = 100, color = { 0.95, 0.90, 0.25 } },   -- yellow
    { limit = 350, color = { 0.95, 0.60, 0.15 } },   -- orange
    { limit = 500, color = { 0.90, 0.25, 0.20 } },   -- red
}

--[[ Past the last step the colour stays red rather than running out: a reader
     at nine hundred is in the same situation as one at six hundred. ]]--
function M:PingColor(ms)
    ms = tonumber(ms) or 0

    for i = 1, table.getn(PING_STEPS) do
        if ms <= PING_STEPS[i].limit then
            local c = PING_STEPS[i].color
            return c[1], c[2], c[3]
        end
    end

    local last = PING_STEPS[table.getn(PING_STEPS)].color
    return last[1], last[2], last[3]
end

function M:PerformanceText()
    if not CreateFrame then return nil end
    if self.perfText then return self.perfText end

    local frame = CreateFrame("Frame", "EquadisClassicOverhaulPerformance",
            UIParent)

    frame:SetWidth(120)
    frame:SetHeight(14)
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 130)

    frame.fps = OB.NewText(frame, "OVERLAY", "GameFontNormalSmall")
    frame.fps:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.fps:SetJustifyH("LEFT")

    frame.ping = OB.NewText(frame, "OVERLAY", "GameFontNormalSmall")
    frame.ping:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.ping:SetJustifyH("RIGHT")

    if OB.MarkMovable then OB.MarkMovable(frame, "Latency & FPS") end

    frame:SetScript("OnDragStop", function()
        if this.StopMovingOrSizing then this:StopMovingOrSizing() end
        OB.modules.actionbars:StorePerformancePosition(this)
    end)

    self.perfText = frame
    return frame
end

function M:StorePerformancePosition(frame)
    if not frame or not frame.GetLeft or not frame:GetLeft() then return false end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.positions.performance = {
        x = OB.Round((frame:GetLeft() + (frame:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((frame:GetBottom() + (frame:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

function M:ApplyPerformanceText()
    local frame = self:PerformanceText()
    if not frame then return false end

    local cfg = self:Config()

    if not cfg.performanceText or not OB.ModuleEnabled("actionbars") then
        frame:Hide()
        return false
    end

    local saved = cfg.positions and cfg.positions.performance

    if saved then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)
    end

    local fps = type(GetFramerate) == "function" and GetFramerate() or nil
    local ping

    if type(GetNetStats) == "function" then
        local _, _, latency = GetNetStats()
        ping = latency
    end

    if cfg.performanceFPS and type(fps) == "number" then
        frame.fps:SetText(string.format("%d fps", fps))
        frame.fps:Show()
    else
        frame.fps:SetText("")
    end

    if cfg.performancePing and type(ping) == "number" then
        frame.ping:SetText(string.format("%dms", ping))

        --[[ The number carries its own colour, which is the whole reason the
             bar was worth replacing rather than merely hiding -- and why there
             is no switch for it. ]]--
        frame.ping:SetTextColor(self:PingColor(ping))

        frame.ping:Show()
    else
        frame.ping:SetText("")
    end

    frame:Show()
    return true
end

function M:ApplyButtonBar(key)
    local spec = BUTTON_BARS[key]
    if not spec then return 0 end

    local cfg = self:Config()
    local bar = self:ButtonBar(key)
    if not bar then return 0 end

    if not cfg[spec.setting] or not OB.ModuleEnabled("actionbars") then
        self:ReleaseButtonBar(key)
        bar:Hide()
        return 0
    end

    local scale = tonumber(cfg[spec.scale]) or 1
    if scale < 0.5 then scale = 0.5 end
    if scale > 2 then scale = 2 end

    local gap = tonumber(cfg[spec.spacing]) or 4
    --[[ **Positions accumulate; they are not the index times a width.**

         This placed each button at `index * (its own width + gap)`, which
         is only right while every button is the same width. The finders
         are not -- they arrive as round minimap buttons and are squared up
         to the row -- so one odd width made every button after it overlap
         or gap. That is the broken micro menu.

         Adding each width as it goes is correct whatever the buttons
         measure, and costs nothing. ]]--
    local placed, height = 0, 0
    local x = 0

    for i = 1, table.getn(spec.list) do
        local button = getglobal(spec.list[i])

        --[[ A name that is not there is a button this client does not have --
             Turtle's three, on a stock client. Skipped rather than guessed at. ]]--
        if button and button.SetPoint then
            self:RememberButtonHome(button)

            button:SetParent(bar)
            button:ClearAllPoints()

            --[[ **The odd ones out are sized to match the row they join.**

                 The group and battleground finders are round minimap buttons
                 on this client, and dropping a circle into a row of
                 rectangles reads as a mistake even when the spacing is
                 right. Sized to whatever the first real micro button
                 measures rather than to numbers written here, so a client
                 with different art still lines up.

                 Only on this bar: the same frame keeps its own size
                 everywhere else, and its home size is restored when the bar
                 is switched off. ]]--
            --[[ **The odd ones out are dressed as micro buttons.**

                 The group and battleground finders are round minimap buttons on
                 this client. Sizing them to the row lines them up and leaves
                 them round, which reads worse than leaving them alone -- a
                 circle in a row of rectangles looks like a mistake even when
                 the spacing is right.

                 So they borrow the row's own button art: the normal, pushed and
                 highlight textures are read off a real micro button rather than
                 written here, which means whatever the client or a UI addon has
                 made those look like, these match.

                 **The frame itself is kept**, not replaced with one of ours.
                 The group finder's eye animates while it searches, and that
                 animation belongs to the frame the client built -- a button
                 wearing a copy of its icon would sit still. Its own regions
                 draw on top of the borrowed art as they always did.

                 All of it is recorded in the home first, so switching the bar
                 off gives back a round minimap button rather than a squared-off
                 one wearing somebody else's frame. ]]--
            if key == "micro" and MICRO_MATCH[spec.list[i]] then
                local ref = getglobal("CharacterMicroButton")

                if ref and ref.GetWidth and ref:GetWidth() > 0 then
                    button:SetWidth(ref:GetWidth())
                    button:SetHeight(ref:GetHeight())
                end

                self:DressAsMicroButton(button, ref)
            end
            if button.SetScale then button:SetScale(scale) end

            local w = (button.GetWidth and button:GetWidth() or 30)
            local h = (button.GetHeight and button:GetHeight() or 30)
            button:SetPoint("LEFT", bar, "LEFT", x, 0)
            placed = placed + 1
            x = x + w + gap
            if h > height then height = h end

            if button.Show then button:Show() end
        end
    end

    if placed > 0 then
        --[[ The trailing gap is not part of the bar: it sits after the last
             button and would make the bar wider than what is on it. ]]--
        bar:SetWidth(x - gap)
        bar:SetHeight(height)
        self:PlaceButtonBar(key)
        bar:Show()
    else
        bar:Hide()
    end

    return placed
end

--[[ Every button put back exactly where it was found, which is what makes the
     switch reversible rather than a one-way door. ]]--
function M:ReleaseButtonBar(key)
    local spec = BUTTON_BARS[key]
    if not spec or not self.buttonHomes then return 0 end

    local put = 0

    for i = 1, table.getn(spec.list) do
        local name = spec.list[i]
        local home = self.buttonHomes[name]
        local button = getglobal(name)

        if button and home and button.SetParent then
            button:SetParent(home.parent)
            button:ClearAllPoints()

            if home.point then
                button:SetPoint(home.point, home.rel, home.relPoint,
                        home.x or 0, home.y or 0)
            end

            if button.SetScale then button:SetScale(home.scale or 1) end

            --[[ And out of the row's clothes, back into its own. ]]--
            self:UndressButton(button)

            if home.width and home.width > 0 and button.SetWidth then
                button:SetWidth(home.width)
                button:SetHeight(home.height or home.width)
            end

            self.buttonHomes[name] = nil
            put = put + 1
        end
    end

    return put
end

function M:StoreButtonBarPosition(key, bar)
    if not bar or not bar.GetLeft or not bar:GetLeft() then return false end

    local cfg = self:Config()
    cfg.positions = cfg.positions or {}

    local scale = bar:GetScale() or 1
    if scale <= 0 then scale = 1 end

    cfg.positions["buttonBar_" .. key] = {
        x = OB.Round((bar:GetLeft() + (bar:GetWidth() / 2))
                - ((GetScreenWidth() / 2) / scale)),
        y = OB.Round((bar:GetBottom() + (bar:GetHeight() / 2))
                - ((GetScreenHeight() / 2) / scale)),
    }

    return true
end

function M:PlaceButtonBar(key)
    local cfg = self:Config()
    local saved = cfg.positions and cfg.positions["buttonBar_" .. key]
    local bar = self.buttonBars and self.buttonBars[key]

    if not bar or not saved then return false end

    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", saved.x, saved.y)

    return true
end

function M:ApplyProgressBars()
    local cfg = self:Config()

    local xp = self:ProgressFrame("xp", "ExperienceBar")
    local rep = self:ProgressFrame("rep", "ReputationBar")

    if not OB.ModuleEnabled("actionbars") then
        if xp then xp:Hide() end
        if rep then rep:Hide() end
        return false
    end

    if cfg.showXPBar then
        local value, max = self:PlayerXP()

        --[[ At the level cap there is no experience left to earn, and a bar
             stuck at nothing for the rest of a character's life is furniture
             rather than information. ]]--
        if max > 0 and not self:AtLevelCap() then
            self:StyleProgressBar("xp", "ExperienceBar", value, max,
                    self:XPBarText(),
                    cfg.xpBarColor or { 0.6, 0.2, 0.8 }, 12)

            --[[ The rested pool, as far along the bar as it would carry you --
                 clamped, because a full night's rest is worth more than what is
                 left of this level and would otherwise draw past the end. ]]--
            local rested = self:RestedXP()

            if xp and xp.rested then
                if rested > 0 then
                    local reach = value + rested
                    if reach > max then reach = max end

                    xp.rested:SetWidth((reach / max) * xp:GetWidth())
                    xp.rested:Show()
                else
                    xp.rested:Hide()
                end
            end
        elseif xp then
            xp:Hide()
        end
    elseif xp then
        xp:Hide()
    end

    if cfg.showRepBar then
        --[[ Through `BarFaction`, which falls back to the faction you last
             earned reputation with when nothing is pinned. ]]--
        local name, _, value, max = self:BarFaction()

        if name and max and max > 0 then
            self:StyleProgressBar("rep", "ReputationBar", value, max,
                    self:RepBarText(),
                    cfg.repBarColor or { 0.2, 0.6, 0.9 }, 26)
        elseif rep then
            rep:Hide()
        end
    elseif rep then
        rep:Hide()
    end

    return true
end

--[==[ **An unbound left mouse button is repaired, once, on the way in.**

     `BUTTON1` is `CAMERAORSELECTORMOVE`: selecting a target and holding to turn
     the camera. There is no reason anybody would deliberately leave it unbound,
     because doing so leaves the game unplayable with the mouse -- and bind mode
     used to take it, one plain left click at a time, and then write that to
     disk with the rest of the set.

     That damage outlives the bug. `SetBinding` alone lives until the next
     reload, so somebody repairing it by hand repairs it again every session
     until they happen to also call `SaveBindings`. This does both, once, and
     says so.

     **Only when it is unbound.** A binding somebody has deliberately moved
     elsewhere is left alone -- this asks whether `BUTTON1` does anything at
     all, not whether it does the default thing. Reaching further into somebody
     else's key bindings than the damage reached is not a repair. ]==]
function M:RepairCameraBinding()
    if type(GetBindingAction) ~= "function" then return false end
    if type(SetBinding) ~= "function" then return false end

    local action = GetBindingAction("BUTTON1")
    if action and action ~= "" then return false end

    if not SetBinding("BUTTON1", "CAMERAORSELECTORMOVE") then return false end

    --[[ Saved, or it comes back next reload -- which is the half of this that
         made it look like a recurring bug rather than a one-off. ]]--
    if type(SaveBindings) == "function" then
        local which = 1
        if type(GetCurrentBindingSet) == "function" then
            which = GetCurrentBindingSet()
        end
        SaveBindings(which)
    end

    Say("the left mouse button had no binding, so it has been put back to "
            .. "moving the camera and picking targets.")

    return true
end

function M:OnBind()
    --[[ Before anything is moved. A capture taken after the layout pass would
         record our own arrangement as the original and "restore" to it. ]]--
    self:CaptureOriginals()

    self:RepairCameraBinding()

    self:InstallHotkeyHook()
    self:InstallUsableHook()

    --[[ Installed once and never removed: the hook cannot be taken off again
         without deleting whatever wrapped it after us, so the setting is read
         per cooldown instead. ]]--
    OB.InstallCooldownNumbers()
    self:Apply()
end

--[[ **Only a real switch-off puts the client's bars back.**

     `OB.BindSlots` unbinds every module before it rebinds them, so this runs
     whenever any unrelated module is ticked on or off -- and doing the full
     restore each time reparented twelve buttons, re-showed the bar art and
     called `UIParent_ManageFramePositions`, all undone a moment later by the
     rebind. What the reader saw was the action bar jumping back to the default
     layout and snapping into place again.

     The enable flag is already written by the time an unbind runs, so asking
     whether the module is still enabled distinguishes the two cases exactly.
     Drag and bind mode end either way: leaving those armed across a rebind is
     what left the keybind overlay stuck open. ]]--
function M:OnUnbind()
    self.dragging = nil
    if self.bindFrame then self.bindFrame:Hide() end
    self.binding = nil

    if not OB.ModuleEnabled("actionbars") then
        self:RestoreBlizzardActionBars()
    end
end

function M:OnStyle()
    self:Apply()
end

--[==[ **Twice a second.**

     A frame rate that updates sixty times a second is unreadable -- the digits
     churn faster than anybody can take them in, and it costs a string built
     every frame for a number nobody could act on. Once a second is too slow the
     other way: a stutter comes and goes inside one tick and the readout never
     admits it happened.

     Two is the rate at which the number is both legible and honest. ]==]
local PERF_INTERVAL = 0.5

function M:OnUpdate(now)
    now = now or GetTime()

    --[[ Before the throttle below, and on a throttle of its own: the
         performance text is a twice-a-second readout and this is a question
         about what is on screen. See `MirrorAllVisibility`. ]]--
    if not self.nextMirror or now >= self.nextMirror then
        self.nextMirror = now + 0.2
        self:MirrorAllVisibility()
    end

    if self.nextPerfRefresh and now < self.nextPerfRefresh then return end
    self.nextPerfRefresh = now + PERF_INTERVAL

    self:ApplyPerformanceText()
end

function M:OnDraw() end
