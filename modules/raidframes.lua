--[[ Equadis' Classic Overhaul :: raid frames

  **Forty people, and the client draws none of them.**

  1.12 ships party frames for four and nothing at all for a raid: the only way
  to see a raid is the Blizzard raid panel, which is a list of names and no
  health. So every raid in this era is run on an addon, and what that addon is
  for is one question -- who is about to die -- answered for forty people at a
  glance.

  **A grid rather than a list.** Health is read by area: a bar half gone is half
  gone whether you look at it or not, and forty bars in columns of five can be
  taken in without reading a single name. A list of forty rows has to be read.

  **Blizzard's frames are not reused.** The unit frame module restyles the
  client's own frames because they already know how to be a player frame. There
  is no raid frame to restyle -- these are ours from nothing, which is also why
  this file owns its own layout rather than borrowing the party module's.

  **Clicking one targets it**, which in 1.12 is simply `TargetUnit` on a button:
  this client has no protected frames, so there is no secure template to fight
  and no combat lockdown to work around.
]]--

local OB = EquadisClassicOverhaul
local M = OB.RegisterModule({
    id = "raidframes",
    name = "Raid Frames",
    feature = true,
    renders = "none",

    --[[ Off. It puts up to forty frames on screen, which is a decision
         somebody makes rather than one made for them. ]]--
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

    --[[ Bars and text, so the whole appearance block applies. ]]--
    styled = true,

    defaults = {
        --[[ Sixty-four by thirty-two is the reference implementation's size and
             it is a good one: wide enough for a name at a readable size, short
             enough that eight of them stack inside a raid's worth of screen. ]]--
        width = 64,
        height = 32,

        --[[ Five to a column, because a raid group is five people. A column
             that matches a group is a column you can find somebody in. ]]--
        perColumn = 5,

        spacing = 2,
        scale = 1,

        showPower = true,
        showName = true,

        --[==[ **Dead and offline are two different problems, and this drew them
             as one.**

             Both went to the same grey, on the reasoning that neither is a
             health problem anybody can heal. True, and it is the wrong question:
             a raid reads these frames to decide what to *do*, and the two
             answers are opposite. Somebody dead is a resurrection waiting to
             happen — the most actionable thing on the screen. Somebody offline
             is nothing anybody can act on at all, and a healer spending a second
             working out which is which is a second they did not have.

             So they are told apart: dead keeps a colour of its own and says
             which of dead or ghost it is, and offline goes flat and dims the
             whole frame, because a dimmed thing reads as "not part of this" from
             across the screen without being read at all. ]==]
        --[==[ **Dead, Ghost and Offline are not preferences.**
             ~~showStatus~~, ~~deadColor~~, ~~offlineColor~~ and ~~offlineAlpha~~
             were four controls for one behaviour that has exactly one sensible
             shape. There is no coherent player who wants a raid frame to stop
             telling them somebody is dead, and nobody picks their own colour for
             "gone". They are constants now, and an old profile carrying the
             retired keys is **ignored rather than obeyed** -- honouring a stored
             `showStatus = false` would leave somebody with a raid frame that
             says nothing and no row to explain why. ]==]




        --[[ How far an offline frame fades. Not to nothing: they are still in
             the raid and still taking up a slot in the group you are looking
             at. ]]--


        --[==[ **A column per group, because that is how a raid is spoken about.**

             Laid out by raid index, the columns are five people who happen to
             have joined in that order -- and "group three is dying" then means
             nothing you can point at. The server already knows the answer:
             `GetRaidRosterInfo` returns the subgroup, and it moves when somebody
             is dragged between groups.

             Only in a raid. A party has no groups to sort into. ]==]
        byGroup = true,

        --[==[ **A title over each group, because a column of five is not
             self-evidently a group.**

             Asked for, and asked for with a switch -- unlike the dead/ghost
             states, this one has a coherent player on both sides: somebody
             calling groups over voice needs to see which is which, and somebody
             healing a five-man needs the screen space more than the label.

             On by default, because the arrangement is already by group and a
             heading is what makes that visible rather than something you work
             out by counting. ]==]
        groupTitles = true,

        --[==[ **Which way the groups run from group one.**

             The container was anchored by its centre, so a raid gaining a group
             widened it and every column shifted half a column -- group one
             moved because group six joined. A healer who put group one against
             the edge of their screen found it a column further in at the next
             pull, which was reported as the frames not staying where they were
             put.

             So the container is anchored by the corner group one sits in, and
             this says which corner: right means group one is on the left and
             the rest extend rightward, left means group one is on the right and
             the rest extend leftward. Either way group one does not move when a
             group arrives or leaves, which is what "anchored on group one"
             means. ]==]
        growX = "right",

        --[==[ **Out of range, faded.**

             A healer's frame is a list of people they can do something about,
             and the ones they cannot are the most important thing on it -- a bar
             dropping that no heal will reach is a different problem from one
             that will.

             Faded rather than hidden: somebody out of range is still in the
             raid, and a frame that vanished would move everybody below it. ]==]
        fadeOutOfRange = true,
        rangeAlpha = 0.4,

        --[[ **Used for a party as well, off by default.** Four people fit in
             the client's own frames perfectly well, and somebody who wants one
             consistent look in both says so. ]]--
        forParty = false,

        x = -320,
        y = 0,
    },

    options = {
        { "Layout", "__s_layout", "section", "layout" },

        --[[ Moved here from "What Each Frame Shows". How the frames are
             arranged is not a thing a frame shows. ]]--
        { "A Column Per Raid Group", "byGroup", "boolean" },

        --[[ Hidden rather than greyed when the columns are not groups: "Group 3"
             over a column that is simply the third five people is a label that
             lies, and a row offering it is worse than no row. ]]--
        { "Number The Groups", "groupTitles", "boolean",
          nil, nil, nil, nil, "byGroup" },

        { "Groups Grow", "growX",
          OB.Enum({ "right", "left" }, { "Right", "Left" }) },

        { "Frame Width", "width", "slider", 40, 140, 2 },
        { "Frame Height", "height", "slider", 16, 64, 2 },
        { "Per Column", "perColumn", "slider", 1, 40, 1 },
        { "Spacing", "spacing", "slider", 0, 12, 1 },
        { "Scale", "scale", "slider", 50, 200, 5, 0.01 },

        { "Move The Frames", "__a_move", "action",
          function() OB.modules.raidframes:SetDragMode(
                  not OB.modules.raidframes:DragMode()) end,
          function()
              if OB.modules.raidframes:DragMode() then return "Done Moving" end
              return "Move The Frames"
          end },

        { "Put Them Back", "__a_reset", "action",
          function() OB.modules.raidframes:ResetPosition() end },

        { "What Each Frame Shows", "__s_shows", "section", "shows" },

        { "Show Names", "showName", "boolean" },

        { "Dead & Offline", "__s_gone", "section", "gone" },

        --[[ The four rows that used to be here are gone; see the note beside
             the defaults. ]]--
        { "Show Mana / Energy / Rage", "showPower", "boolean" },

        { "Range", "__s_range", "section", "range" },
        { "Fade Out Of Range", "fadeOutOfRange", "boolean" },
        { "Faded To", "rangeAlpha", "slider", 10, 90, 5, 0.01,
          nil, "!fadeOutOfRange" },

        { "In A Party", "__s_party", "section", "party" },

        { "Replace Party Frames With Raid-Style Frames", "forParty", "boolean" },
    },

    --[==[ **A power bar is six events, not one.**

         Reported as energy never changing on these frames. `UNIT_MANA` is the
         mana event and nothing else: 1.12 fires a *separate* event per resource
         -- `UNIT_RAGE`, `UNIT_FOCUS`, `UNIT_ENERGY` -- so a rogue's bar was only
         ever redrawn when something unrelated happened to ask for a refresh.

         Read out of the client's own `UnitFrame.lua`, where a power bar
         registers all four plus `UNIT_DISPLAYPOWER`, rather than reasoned about.
         The party frames next door already had the full set, which is what made
         the difference visible: the same bar worked in one module and not in
         the other.

         `UNIT_DISPLAYPOWER` is the one that is easy to leave out and matters
         most on this client: it fires when the resource *type* changes, which
         for a druid means every shift. Without it a bar keeps the colour and the
         maximum of the form they were last in.

         `UNIT_HAPPINESS` is deliberately not here. It is a pet resource, and no
         pet appears in a raid frame. ]==]
    --[==[ **A group size that nothing announced.**

         Reported: left a raid, joined a party, and the grid was still on screen.
         Driving that transition here does the right thing every way it can be
         driven -- both events, either event alone -- so what is left is the case
         the harness cannot produce: an event that arrives while the client still
         reports the old roster, or does not arrive at all.

         `Apply` ran **only** from `OnEvent`, and `OnDraw` was empty. So one
         mistimed `RAID_ROSTER_UPDATE` leaves a raid grid over a party until
         something else in the group changes -- which, in a two-man party doing
         nothing, is never. There was no second chance anywhere.

         The other modules that read a fact with no reliable event already do
         this: the leader crown and the loot method are read every refresh for
         the same reason. Ten times a second, comparing one number. ]==]
    tickly = true,

    events = { "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED",
               "PLAYER_ENTERING_WORLD", "UNIT_HEALTH",
               "UNIT_MAXHEALTH", "UNIT_MAXMANA",
               "UNIT_MANA", "UNIT_RAGE", "UNIT_FOCUS", "UNIT_ENERGY",
               "UNIT_DISPLAYPOWER" },
})

local MAX_RAID = 40
local MAX_PARTY = 4

local function Say(text) OB.Print(text, "Raid Frames") end

--[==[ **What "gone" looks like, as constants rather than settings.**

     **Dead is its own dark red**, because a dead player is the most actionable
     thing on a raid frame -- somebody to resurrect -- and it must not read as
     the same nothing-to-do state as a disconnect.

     **Ghost and Offline are both grey.** A ghost has released and is running
     back; there is nothing to cast on them either, which is the same answer
     Offline gives. Asked for in those words -- *ghost should make it grey* --
     and it is right: the earlier version put a ghost in the dead colour, which
     promised a resurrection that cannot be cast.

     **Only Offline fades the frame.** A ghost is coming back under their own
     power and is still in the raid; a disconnect is not part of the fight at
     all, and the fade is what says that from across the screen without being
     read. ]==]
local DEAD_COLOR = { 0.45, 0.15, 0.15 }
local GONE_COLOR = { 0.35, 0.35, 0.35 }
local OFFLINE_ALPHA = 0.45

--[[ How much of the bar the state word takes from the name when the string
     cannot be measured, and the air beside it when it can. "Offline" at the
     small font is a little under forty pixels; this is the floor, not the
     answer -- `SizeName` measures. ]]--
local STATUS_ROOM = 34
local STATUS_AIR = 4

--[==[ **"RAID" is the raid *management* list, not the raid's version of the
     party menu.**

     It was chosen on the reading that `UnitPopupMenus["RAID"]` is "the raid's
     version of the same list". It is not. In 1.12 that set is promote, demote,
     remove and the mute entries -- what a leader does *to* a raid member. The
     things somebody actually right-clicks a raid frame for are in the party set:
     whisper, **inspect**, **trade**, follow, duel, invite.

     Reported as the raid frames not giving the full menu the unit frames do, and
     that is exactly right: the party frames ask for "PARTY" and get the whole
     list, and these asked for a different list and got a shorter one.

     The unit token is a `raidN` either way, and the client's handlers act on the
     dropdown's unit rather than on the name of the set -- so the party entries
     work on a raid member without anything else changing.

     Named once, because three call sites ask for it and a fourth will
     eventually. ]==]
local RAID_MENU = "PARTY"

function M:Config()
    return OB.profile.modules.raidframes
end

-- ---------------------------------------------------------------------------
-- which units are being drawn
-- ---------------------------------------------------------------------------

--[[ **In a raid, `raid1..40` -- and that includes you.**

     `party1..4` never contains the player, so a party of five is four tokens
     plus `player`; a raid of five is five `raid` tokens. Getting that wrong
     either loses you off your own raid frames or draws you twice, and both look
     like an off-by-one in the layout rather than a unit token question. ]]--
function M:UnitFor(index)
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        return "raid" .. index
    end

    if index == 1 then return "player" end
    return "party" .. (index - 1)
end

--[[ How many frames belong on screen right now, which is not the same question
     as how many people are in the group: in a party the player is drawn too. ]]--
function M:Count()
    local cfg = self:Config()

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local raid = GetNumRaidMembers()
        if raid > MAX_RAID then raid = MAX_RAID end
        return raid
    end

    --[[ A party only when asked for. Off, the client's own four frames are
         doing the job and there is nothing here to draw. ]]--
    if not cfg.forParty then return 0 end

    local party = (GetNumPartyMembers and GetNumPartyMembers()) or 0
    if party <= 0 then return 0 end
    if party > MAX_PARTY then party = MAX_PARTY end

    --[[ Plus you. ]]--
    return party + 1
end

-- ---------------------------------------------------------------------------
-- the frames
-- ---------------------------------------------------------------------------

function M:Frame()
    if self.frame then return self.frame end
    if not CreateFrame then return nil end

    local frame = CreateFrame("Frame", "EquadisClassicOverhaulRaid", UIParent)
    frame:SetWidth(10)
    frame:SetHeight(10)
    frame:Hide()

    --[[ The drag hint, shown only while the frames are unlocked. The container
         is otherwise invisible, so without it there is nothing to aim at. ]]--
    frame.hint = frame:CreateTexture(nil, "BACKGROUND")
    frame.hint:SetAllPoints(frame)
    frame.hint:SetTexture(0.1, 0.6, 1, 0.25)
    frame.hint:Hide()

    frame:SetScript("OnDragStop", function()
        if this.StopMovingOrSizing then this:StopMovingOrSizing() end
        OB.modules.raidframes:StorePosition()
    end)

    self.frame = frame
    self.buttons = {}

    if OB.MarkMovable then OB.MarkMovable(frame, "Raid Frames") end

    return frame
end

--[==[ **The four gestures, from `layout.lua`.**

     Kept as methods on this module so the click and drag scripts above read as
     what they do, and so a test can drive one without going through a frame.
     The menu is "RAID"; it opens at the cursor, which is where the client's own
     raid pullout puts it. ]==]
function M:UnitMenu(frame)
    return OB.UnitMenuFor(frame, RAID_MENU)
end

function M:OpenUnitMenu(frame)
    return OB.OpenUnitMenuFor(frame, RAID_MENU, 0, 0)
end

function M:UnitDrop(frame)
    return OB.UnitDropOn(frame)
end

function M:UnitClick(frame, button)
    return OB.UnitGestureClick(frame, button, RAID_MENU, 0, 0)
end

--[[ One unit's frame: a health bar with a name on it, a power bar under it, and
     a click that targets whoever it is showing. ]]--
function M:Button(index)
    self:Frame()
    if self.buttons[index] then return self.buttons[index] end

    local button = CreateFrame("Button",
            "EquadisClassicOverhaulRaid" .. index, self.frame)

    button:SetID(index)

    --[==[ **A raid frame is a unit, and everything you can do to a unit you can
         do here.**

         Clicking targeted and that was the whole of it, which made these a
         readout rather than raid frames -- the same fault the party frames had
         and the same four gestures answer it: target, cast the queued spell,
         offer the item on the cursor, and a right-click menu. Asked for in those
         terms.

         The behaviour is `layout.lua`'s, shared with the party frames rather
         than copied beside them, so the next fix lands once. What differs is the
         menu: "RAID" is the client's own list for a raid member. ]==]
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:EnableMouse(true)

    button:SetScript("OnClick", function()
        EquadisClassicOverhaul.modules.raidframes:UnitClick(this, arg1)
    end)

    --[==[ **An item let go over the frame offers it to them.**

         `OnReceiveDrag` fires on any mouse-enabled frame when something is
         dropped on it. It needs no `RegisterForDrag` -- that is for *starting* a
         drag, and starting one here would mean dragging the raid member. ]==]
    button:SetScript("OnReceiveDrag", function()
        EquadisClassicOverhaul.modules.raidframes:UnitDrop(this)
    end)

    --[[ A button takes the mouse, and a frame with the mouse eats a right-drag
         that was meant for the camera. See `OB.AttachCameraDrag`. ]]--
    OB.AttachCameraDrag(button)

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints(button)
    button.bg:SetTexture(0, 0, 0, 0.6)

    button.health = CreateFrame("StatusBar", nil, button)
    button.health:SetMinMaxValues(0, 1)

    button.power = CreateFrame("StatusBar", nil, button)
    button.power:SetMinMaxValues(0, 1)

    -- The name must belong to the health StatusBar, not the outer button.
    -- StatusBar children render above regions on their parent frame in 1.12;
    -- creating the FontString on the button put the name *under* the filled
    -- health texture. It only became visible in the unfilled black portion of
    -- a bar, which is why names appeared to float in the gaps between cells.
    --[==[ **What is wrong with them, over the bar rather than instead of the
         name.**

         Replacing the name would answer "what is wrong" and lose "with whom",
         which is the half a raid leader is reading for. Centred on the bar so it
         is legible over any fill, and outlined for the same reason the plate
         text is: it is drawn over a colour that changes. ]==]
    --[[ Where the name goes, because it is what the name is replaced by --
         see `Refresh`. Placed with the name in the layout pass so the two
         cannot drift apart. ]]--
    --[==[ **The crown and the bag, which are the client's own.**

         `UI-Group-LeaderIcon` and `UI-Group-MasterLooter` are the textures the
         client puts on its own party frames for exactly these two facts, so they
         are already what a player recognises -- and they are in every install,
         which nothing this addon could draw would be.

         On the health bar rather than on the button, for the same reason the
         name is: a texture on the outer button sits *below* a child StatusBar in
         1.12, so filled health would cover it and it would leak through only in
         the empty part of a cell. ]==]
    button.leader = button.health:CreateTexture(nil, "OVERLAY")
    button.leader:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    button.leader:SetWidth(12)
    button.leader:SetHeight(12)
    button.leader:Hide()

    --[[ The same size as the crown, which is how the client draws the pair
         on its own party frames: a bag one pixel smaller sat half a pixel
         off the crown's line. ]]--
    button.looter = button.health:CreateTexture(nil, "OVERLAY")
    button.looter:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter")
    button.looter:SetWidth(12)
    button.looter:SetHeight(12)
    button.looter:Hide()

    button.status = OB.NewText(button.health, "OVERLAY", "GameFontNormalSmall")
    button.status:SetJustifyH("LEFT")
    button.status:Hide()

    button.name = OB.NewText(button.health, "OVERLAY", "GameFontNormalSmall")
    button.name:SetJustifyH("LEFT")

    self.buttons[index] = button
    return button
end

-- ---------------------------------------------------------------------------
-- where they go
-- ---------------------------------------------------------------------------

--[[ **Down a column, then across**, which is how a raid is grouped: five to a
     column means column one is group one. Filling across first would scatter a
     group over eight columns and lose the one piece of structure a raid has. ]]--
--[==[ **Which group a raid member is in**, which is the third return of
     `GetRaidRosterInfo` and the only place the answer exists. It changes when
     somebody is dragged between groups, so it is asked rather than remembered.

     Nothing in a party: there are no groups to be in. ]==]
--[==[ **Who leads, and who is holding the loot.**

     Rank comes off the roster -- 2 is the leader, 1 an assistant, 0 everybody
     else -- and it is the second return, which the client has always answered.

     The **loot master** is asked of `GetLootMethod` rather than of the roster.
     Its third return is the master's raid index, which is exactly the question
     being asked here; the alternative is a trailing return of
     `GetRaidRosterInfo` whose position differs between builds, and a mis-counted
     return puts an icon over the wrong person with nothing to say it is wrong.

     Both answer nothing outside a raid, which is right: a party has a leader the
     client already marks on its own frames, and this module only draws the raid
     grid. ]==]
function M:IsLeader(index)
    if type(GetRaidRosterInfo) ~= "function" then return false end

    local _, rank = GetRaidRosterInfo(index)
    return tonumber(rank) == 2
end

function M:IsMasterLooter(index)
    if type(GetLootMethod) ~= "function" then return false end

    local method, _, raidIndex = GetLootMethod()

    if method ~= "master" then return false end
    return tonumber(raidIndex) == index
end

function M:Subgroup(index)
    if type(GetNumRaidMembers) ~= "function" or GetNumRaidMembers() <= 0 then
        return nil
    end

    if type(GetRaidRosterInfo) ~= "function" then return nil end

    local _, _, subgroup = GetRaidRosterInfo(index)
    return tonumber(subgroup)
end

--[==[ **Where every frame goes, worked out once per layout.**

     Per-frame this would be "how many people below me are in my group", which is
     a walk of the whole roster for each of forty frames. Built as a table
     instead, in one pass. ]==]
function M:BuildCells(shown)
    local cfg = self:Config()
    local cells = {}

    local per = tonumber(cfg.perColumn) or 5
    if per < 1 then per = 1 end

    --[[ By group when there is a raid to have groups in. A party falls through
         to the plain columns below, which is what it always used. ]]--
    if cfg.byGroup and type(GetNumRaidMembers) == "function"
            and GetNumRaidMembers() > 0 then
        local filled = {}
        local ok = true

        for index = 1, shown do
            local group = self:Subgroup(index)

            --[[ A roster that will not answer is a roster this cannot sort. One
                 missing subgroup abandons the whole arrangement rather than
                 putting one person in a column of their own. ]]--
            if not group then ok = false break end

            filled[group] = (filled[group] or 0) + 1
            cells[index] = { group, filled[group] }
        end

        if ok then return cells end
    end

    for index = 1, shown do
        local column = math.ceil(index / per)

        --[[ The bare global rather than `math.mod`: 1.12 keeps Lua 5.0's name in
             both places, but only the global survives into the test harness. ]]--
        local row = mod(index, per)
        if row == 0 then row = per end

        cells[index] = { column, row }
    end

    return cells
end

--[==[ **The name gets the room the badges are not using.**

     Thirty pixels were reserved on every button so the crown and the bag would
     never be run under. On a sixty-four pixel frame that is nearly half the
     name, taken from everybody to make space for two things that are on **one**
     raid member each -- so every name in the raid started abbreviating, which is
     what was reported.

     Measured from what is actually shown. Nobody has a badge, the name has the
     whole button; the leader loses room for one; the one person holding the loot
     as well loses room for two. ]==]
local BADGE_ROOM = 13

--[==[ **Both badges on the right, the bag inboard of the crown, and each
     against the one before it that is shown.**

     The name runs from the left, so the right-hand end is the side with room.
     The crown is outermost because somebody has it for the whole raid, while
     master loot is a method that gets switched on and off -- the badge that
     comes and goes should be the one that moves nothing when it does.

     The bag used to hang off the crown's left whether or not the crown was
     there. A hidden texture keeps its rectangle, so on a master looter who is
     not the leader the bag sat a crown's width in from the edge with nothing
     beside it -- "slightly offset", which is exactly what it was. The state
     word was worse: anchored to the bar's edge under whichever badge was
     there. Right to left now, and every anchor is something on screen. ]==]
local function shown(region)
    return region and region.IsShown and region:IsShown()
end

function M:PlaceBadges(button)
    if not button or not button.health then return false end

    local anchor, edge, gap = button.health, "RIGHT", -1

    local function place(region)
        if not region then return end
        region:ClearAllPoints()

        if shown(region) then
            region:SetPoint("RIGHT", anchor, edge, gap, 0)
            anchor, edge, gap = region, "LEFT", -1
        else
            region:SetPoint("RIGHT", button.health, "RIGHT", -1, 0)
        end
    end

    place(button.leader)
    place(button.looter)

    if button.status then
        button.status:ClearAllPoints()
        button.status:SetPoint("RIGHT", anchor, edge,
                (anchor == button.health) and -2 or -STATUS_AIR, 0)
    end

    return true
end

function M:SizeName(button, width)
    if not button or not button.name or not button.name.SetWidth then return false end

    width = tonumber(width) or tonumber(self:Config().width) or 64

    local room = width - 4

    if button.leader and button.leader.IsShown and button.leader:IsShown() then
        room = room - BADGE_ROOM
    end

    if button.looter and button.looter.IsShown and button.looter:IsShown() then
        room = room - BADGE_ROOM
    end

    --[==[ **The state word, when there is one, is the third thing on that
         end -- and it takes what it measures.** "Dead" is four letters and
         "Offline" is seven; reserving one width for both either clips the long
         one or robs the name for the short one. Measured off the string the
         client is actually drawing, with the constant as the floor for a
         client that cannot say. ]==]
    if button.status and button.status.IsShown and button.status:IsShown() then
        local need = button.status.GetStringWidth
                and button.status:GetStringWidth() or 0

        if not need or need <= 0 then need = STATUS_ROOM end
        room = room - (need + STATUS_AIR)
    end

    if room < 10 then room = 10 end

    button.name:SetWidth(room)
    return true
end

function M:Cell(index)
    --[[ The cached table is built for the size of the group that was last laid
         out, so an index past it has no entry -- and answering "column one, row
         one" for those would stack every late frame on the first. A miss builds
         what it needs rather than guessing. ]]--
    local cell = self.cells and self.cells[index]

    if not cell then
        local cells = self:BuildCells(index)
        cell = cells[index]
    end

    if cell then return cell[1], cell[2] end
    return 1, 1
end

--[==[ **How tall a group heading is**, in one place, because the layout has to
     leave room for it and the container has to grow by it. Two numbers that must
     agree, so there is one. ]==]
local TITLE_HEIGHT = 14

--[[ One heading per column, grown on demand and never destroyed -- 1.12 cannot
     destroy a frame, and a raid that shrinks from eight groups to two would
     otherwise leave six headings nothing can take away. ]]--
function M:GroupTitle(column)
    self.titles = self.titles or {}
    if self.titles[column] then return self.titles[column] end

    local frame = self:Frame()
    if not frame then return nil end

    local text = OB.NewText(frame, "OVERLAY", "GameFontNormalSmall")
    text:SetJustifyH("CENTER")
    text:Hide()

    self.titles[column] = text
    return text
end

--[==[ **Only over a real group.** The headings are numbered by column, and a
     column is a subgroup only while `byGroup` is arranging them -- otherwise it
     is just the next five people and "Group 3" would be a label that lies.

     `BuildCells` already made that decision for the whole layout, and it is not
     worth making twice: the column it hands back **is** the subgroup number when
     it sorted by group, so the heading needs nothing else to be right. ]==]
function M:TitlesWanted()
    local cfg = self:Config()

    if not cfg.groupTitles or not cfg.byGroup then return false end
    if type(GetNumRaidMembers) ~= "function" then return false end

    return GetNumRaidMembers() > 0
end

--[[ The corner group one sits in, which is the corner everything is anchored
     to: the container on the screen, the buttons and titles in the container. ]]--
function M:GrowsLeft()
    return self:Config().growX == "left"
end

function M:Corner()
    return self:GrowsLeft() and "TOPRIGHT" or "TOPLEFT"
end

--[[ A column's horizontal offset from the corner, signed for the direction. ]]--
function M:ColumnX(column, width, gap)
    local x = (column - 1) * (width + gap)
    if self:GrowsLeft() then return -x end
    return x
end

function M:Layout()
    local cfg = self:Config()
    local frame = self:Frame()
    if not frame then return false end

    local corner = self:Corner()

    local width = tonumber(cfg.width) or 64
    local height = tonumber(cfg.height) or 32
    local gap = tonumber(cfg.spacing) or 2
    local shown = self:Count()

    --[[ Worked out once and read by `Cell`, so forty frames cost one pass over
         the roster rather than forty. ]]--
    self.cells = self:BuildCells(shown)

    local titles = self:TitlesWanted()
    local top = titles and TITLE_HEIGHT or 0

    --[==[ **The widest column and the tallest, from the cells rather than from
         arithmetic.**

         The container used to size itself as `ceil(shown / perColumn)` columns,
         which is only true when the frames are packed. Sorted by group they are
         not: a raid holding groups one and five occupies five columns with three
         of them empty, and the old sum answered two. Reading the cells is the
         same information without a second opinion about it. ]==]
    local widest, tallest = 0, 0

    for index = 1, shown do
        local column, row = self:Cell(index)
        if column > widest then widest = column end
        if row > tallest then tallest = row end
    end

    for index = 1, shown do
        local button = self:Button(index)
        local column, row = self:Cell(index)

        button:SetWidth(width)
        button:SetHeight(height)

        button:ClearAllPoints()
        button:SetPoint(corner, frame, corner,
                self:ColumnX(column, width, gap),
                -(top + ((row - 1) * (height + gap))))

        --[[ The name sits on the health bar and the power bar under it, so a
             frame reads as one thing rather than three stacked. ]]--
        local powerHeight = cfg.showPower and math.floor(height * 0.25) or 0
        if powerHeight < 1 then powerHeight = 0 end

        button.health:ClearAllPoints()
        button.health:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.health:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",
                -1, powerHeight + 1)

        button.power:ClearAllPoints()
        button.power:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 1, 1)
        button.power:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.power:SetHeight(powerHeight > 0 and powerHeight or 1)

        if powerHeight > 0 then button.power:Show() else button.power:Hide() end

        button.name:ClearAllPoints()
        button.name:SetPoint("LEFT", button.health, "LEFT", 2, 0)
        button.name:SetWidth(width - 4)

        --[[ On the right, and the name gives it room -- see `SizeName`. ]]--
        button.status:SetJustifyH("RIGHT")

        --[[ No width: a font string with one is a box, and a box narrower than
             "Offline" clips it to "Offlin". Left to size itself, and the name
             gives it whatever it measures. ]]--
        button.status:SetWidth(0)

        --[[ The badges and the state word, placed against what is shown --
             see `PlaceBadges`, which `UpdateButton` runs again once it knows
             who has what. ]]--
        self:PlaceBadges(button)

        --[[ Sized in `UpdateButton`, where it is known whether this particular
             button has any badges on it -- see `SizeName`. ]]--
        self:SizeName(button, width)

        button:Show()
    end

    --[[ Everything past the group's size put away rather than left holding the
         last raid's numbers. ]]--
    for index = shown + 1, table.getn(self.buttons or {}) do
        self.buttons[index]:Hide()
    end

    --[[ A heading over every column that has somebody in it, and the rest put
         away -- a raid dropping from eight groups to two must not leave six
         numbers hanging over nothing. ]]--
    local used = {}

    for index = 1, shown do
        local column = self:Cell(index)
        used[column] = true
    end

    for column = 1, math.max(widest, table.getn(self.titles or {})) do
        local text = self:GroupTitle(column)

        if text then
            if titles and used[column] then
                text:SetText("Group " .. column)
                text:ClearAllPoints()
                text:SetPoint(corner, frame, corner,
                        self:ColumnX(column, width, gap), 0)
                text:SetWidth(width)
                OB.ApplyFont(text, nil, "raidframes")
                text:Show()
            else
                text:SetText("")
                text:Hide()
            end
        end
    end

    --[[ The container sized to what it holds, so the drag hint covers the
         frames and edit mode's outline lands round them rather than round a
         ten pixel square in the corner. ]]--
    if shown > 0 then
        frame:SetWidth((widest * (width + gap)) - gap)
        frame:SetHeight(top + (tallest * (height + gap)) - gap)

        --[[ Read by `Place`: an old centre position can only be converted to a
             corner against a container that has been sized by its contents. ]]--
        self.sized = true
    end

    return true
end

-- ---------------------------------------------------------------------------
-- what each one says
-- ---------------------------------------------------------------------------

--[[ Both of these moved to core when the party frames needed the same answer:
     two copies would have been two opinions about what colour rage is. Kept as
     methods because every call site here reads `self:PowerColor(unit)`. ]]--
function M:PowerType(unit)
    return OB.PowerType(unit)
end

function M:PowerColor(unit)
    return OB.PowerColor(unit)
end

--[==[ **In range, by the best answer available.**

     Three sources, and which one answers matters less than that the fallback is
     honest about being coarser.

     An exact distance is the good case and now a real possibility -- the
     capability layer gets one from Nampower, UnitXP or SuperWoW. Forty yards is
     the usual healing range and the number the threshold is written against.

     Without one, `CheckInteractDistance(unit, 4)` is what a plain 1.12 client
     will answer: roughly twenty-eight yards, which is not the same question and
     is the closest one available. It fades a few people who could in fact be
     healed, which is the safe direction to be wrong in -- the other way round
     shows somebody as reachable when they are not.

     And with neither, nothing fades. A frame list where everyone looks out of
     range is worse than one that does not try. ]==]
local HEAL_RANGE = 40

function M:InRange(unit)
    if type(UnitIsUnit) == "function" and UnitIsUnit(unit, "player") then
        return true
    end

    if OB.UnitDistance then
        local yards = OB.UnitDistance(unit)
        if type(yards) == "number" then return yards <= HEAL_RANGE end
    end

    --[==[ **`nil` is the answer, not the absence of one.**

         `CheckInteractDistance` returns `1` or nothing -- there is no `false` in
         it -- and this read nothing as "the client could not say" and returned
         true. So on a stock client every member was in range, always, and the
         fade only ever fired on an install with an exact distance source. The
         other bug in this file hid that one: the fade's alpha was being
         overwritten anyway.

         Nothing back from a friendly unit that exists is "too far", which is the
         whole of what the call can say about one. The one case it means "not a
         unit" is a token that does not resolve, and that is asked first. ]==]
    if type(CheckInteractDistance) == "function" then
        if type(UnitExists) == "function" and not UnitExists(unit) then
            return true
        end

        local ok, near = pcall(CheckInteractDistance, unit, 4)
        if ok then return near and true or false end
    end

    return true
end

function M:UpdateButton(index)
    local button = self:Button(index)
    local unit = self:UnitFor(index)

    button.eqEcoUnit = unit

    --[[ Under the name the shared gesture handling reads, which is the same
         name the party frames use. See `OB.UnitGestureClick`. ]]--
    button.unit = unit

    local cfg = self:Config()
    local look = OB.Look("raidframes")

    local texture = OB.textures[look.texture] or OB.textures[1]
    if button.health.SetStatusBarTexture then
        button.health:SetStatusBarTexture(texture)
        button.power:SetStatusBarTexture(texture)
    end

    local health = UnitHealth(unit) or 0
    local healthMax = UnitHealthMax(unit) or 0
    if healthMax <= 0 then healthMax = 1 end

    button.health:SetMinMaxValues(0, healthMax)
    button.health:SetValue(health)

    --[[ **Coloured by class**, which is the whole reason a healer can use these
         at a glance: the shape of the raid is who is where, and class is how
         somebody knows whether the bar dropping is the tank or a mage who
         stood in something. ]]--
    --[[ Through the roster fallback, so a raid member across the zone is still
         coloured by class rather than dropped to the grey below. ]]--
    local token = OB.UnitClassToken(unit)
    local r, g, b = OB.ClassColor(token)

    if not r then r, g, b = 0.5, 0.5, 0.5 end

    --[==[ **Three states, not two.** See the note on `showStatus`.

         Offline is asked first: a disconnected player also reads as dead on some
         builds, and "they have gone" is the truer of the two answers -- nobody is
         resurrecting a client that is not there. ]==]
    local offline = type(UnitIsConnected) == "function"
            and not UnitIsConnected(unit)

    local ghost = type(UnitIsGhost) == "function" and UnitIsGhost(unit)
    local dead = type(UnitIsDeadOrGhost) == "function"
            and UnitIsDeadOrGhost(unit)

    local gone = offline or dead

    local status

    if offline then
        r, g, b = GONE_COLOR[1], GONE_COLOR[2], GONE_COLOR[3]
        status = "Offline"
    elseif ghost then
        --[[ Grey, not the dead colour. A ghost cannot be resurrected. ]]--
        r, g, b = GONE_COLOR[1], GONE_COLOR[2], GONE_COLOR[3]
        status = "Ghost"
    elseif dead then
        r, g, b = DEAD_COLOR[1], DEAD_COLOR[2], DEAD_COLOR[3]
        status = "Dead"
    end

    --[==[ **One write to alpha, after both things it depends on are known.**

         There were two. The range fade wrote its alpha near the top of this
         function, and the dead/ghost/offline pass -- added later, with the rule
         that only a disconnect fades -- wrote `offline and OFFLINE_ALPHA or 1`
         a few lines further down. The second write won every time, so the
         out-of-range fade was set and then put back to one before a frame was
         ever drawn. Reported as the fade having stopped working, which is
         exactly what it had done.

         Offline first, because a disconnected player is out of range of
         everything and that is the fade that says so. ]==]
    if button.SetAlpha then
        local alpha = 1

        if offline then
            alpha = OFFLINE_ALPHA
        elseif cfg.fadeOutOfRange and not self:InRange(unit) then
            alpha = tonumber(cfg.rangeAlpha) or 0.4
        end

        button:SetAlpha(alpha)
    end

    --[==[ **The status takes the name's place rather than sitting on top of
         it.**

         It was drawn centred on the health bar while the name was drawn along
         the left of the same bar, on the reasoning that "over, not instead of
         the name" answers *what is wrong* without losing *with whom*. On a
         sixty-four pixel button that is not a trade, it is a collision: the two
         strings overlap and neither can be read. Reported with two screenshots
         of exactly that.

         There is room for one string, so it is one string. The name is what is
         normally worth reading and the status is what is worth reading instead
         while it lasts -- and the bar colour is already saying the same thing,
         so the word is confirmation rather than the only signal. Which raid slot
         somebody is in does not move, and the tooltip still names them. ]==]
    --[==[ **Drawn, on the right, where the name is not.**

         This string has been drawn in the name's place, then instead of the
         name, then not at all -- each a report about the previous one. Over the
         name they collided; instead of the name the frame lost the one thing a
         raid frame is for; not at all, the colour alone was reported as not
         showing dead, ghost or offline, and it is a fair report: a dark red bar
         and a grey bar are two shades on a screen full of shades, and "Dead" is
         a word.

         So the word goes on the *other* end of the bar. The name runs from the
         left and `SizeName` already gives ground on the right for the badges;
         the status is one more thing on that end, and it takes its room the
         same way. A frame too narrow for both shows the name, because that is
         the order of the two questions. ]==]
    if button.status then
        button.status:SetText(status or "")

        if status then button.status:Show() else button.status:Hide() end
    end

    --[[ The crown and the bag. Read every refresh rather than on a promotion
         event, because 1.12 has no event for either: `PARTY_LEADER_CHANGED` does
         not fire for a raid promotion, and the loot method changes with no event
         at all. ]]--
    if button.leader then
        if self:IsLeader(index) then button.leader:Show() else button.leader:Hide() end
    end

    if button.looter then
        if self:IsMasterLooter(index) then button.looter:Show() else button.looter:Hide() end
    end

    --[[ After the badges and the status, because their visibility is what
         decides where each sits and how much room the name has. ]]--
    self:PlaceBadges(button)
    self:SizeName(button)

    button.health:SetStatusBarColor(r, g, b, 1)

    --[==[ **The name is always the text, and the state is always the colour.**

         The last pass had the status *replace* the name, because both drawn on a
         sixty-four pixel button collided and neither could be read. That solved
         the collision by answering the wrong question: reported straight back as
         "raid frames only show dead, needs to show player name" -- and rightly,
         because a raid frame you cannot read a name off is a list of strangers.
         Which of them is dead is only useful once you know *who*.

         So there is one string and it is the name. Everything the word was
         saying is already being said without it: **dead is a red of its own,
         ghost and offline are grey, and only offline fades.** Three states, three
         appearances, none of them costing a character of the name.

         `button.status` stays and stays hidden -- the tests read it, and a
         FontString nothing draws costs nothing. ]==]
    if cfg.showName then
        button.name:SetText(UnitName(unit) or "")
        button.name:Show()
    else
        --[[ Blanked as well as hidden: a name left in a string this module has
             stopped showing comes back the moment anything else shows it. ]]--
        button.name:SetText("")
        button.name:Hide()
    end

    OB.ApplyFont(button.name, nil, "raidframes")

    if cfg.showPower then
        local power = UnitMana(unit) or 0
        local powerMax = UnitManaMax(unit) or 0
        if powerMax <= 0 then powerMax = 1 end

        button.power:SetMinMaxValues(0, powerMax)
        button.power:SetValue(power)

        local pr, pg, pb = self:PowerColor(unit)
        if gone then pr, pg, pb = 0.4, 0.4, 0.4 end
        button.power:SetStatusBarColor(pr, pg, pb, 1)
    end

    return true
end

-- ---------------------------------------------------------------------------
-- the client's own party frames
-- ---------------------------------------------------------------------------

--[[ **Out of the way while these are drawing the same four people**, and put
     back the moment they are not.

     Hidden rather than unregistered: the client shows them again on the next
     roster change, so a one-off hide comes undone. `OnShow` is what keeps them
     down, and it is cleared again on the way back. ]]--
function M:HideBlizzardParty(hide)
    for i = 1, MAX_PARTY do
        local frame = getglobal("PartyMemberFrame" .. i)

        if frame then
            if hide then
                frame:Hide()
                frame:SetScript("OnShow", function() this:Hide() end)
            else
                frame:SetScript("OnShow", nil)

                -- Releasing the replacement should be visible immediately. The
                -- old implementation only removed the OnShow hook, leaving the
                -- stock frame hidden until Blizzard happened to refresh the
                -- roster again; that made switching the option off look broken.
                local unit = "party" .. i
                local inRaid = GetNumRaidMembers and GetNumRaidMembers() > 0
                if not inRaid and UnitExists and UnitExists(unit) then
                    frame:Show()
                else
                    frame:Hide()
                end
            end
        end
    end

    return true
end

--[[ Whether the client's frames should be down right now.

     There is deliberately no second "hide party frames" switch. Asking for
     raid-style party frames *is* asking them to replace Blizzard's party frames;
     drawing both is never a useful state and was the bug this option used to
     permit. ]]--
function M:ShouldHideParty()
    local cfg = self:Config()

    if not OB.ModuleEnabled("raidframes") then return false end

    -- Stock party frames must never sit beside the raid grid. Some 1.12 forks
    -- keep `party1..4` alive inside a raid and can re-show PartyMemberFrame after
    -- roster updates, so do not rely on Blizzard hiding them for us.
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return true end

    -- Outside a raid, suppression means exactly one thing: the user asked the
    -- raid-style layout to *replace* the normal party frames.
    if not cfg.forParty then return false end
    return self:Count() > 0
end

-- ---------------------------------------------------------------------------
-- position
-- ---------------------------------------------------------------------------

--[==[ **Placed by group one's corner, not by the middle.**

     `x` and `y` are that corner's offset from the centre of the screen. They
     used to be the container's *centre*, which is exactly the number that moves
     when a group arrives: widen the container by a column and the centre is
     half a column further along, so every frame in it shifts. Anchoring by the
     corner group one occupies means the container grows away from group one
     and group one stays where it was put.

     **An old position is carried across once.** A profile written before this
     holds a centre; read as a corner it would land the frames half a raid's
     width off. So the first placement with such a profile converts it using
     the container's size at that moment and marks it done -- approximate by
     however much the roster differs from last time, and one drag from right.
     Only when the container has a size to convert against: before the first
     layout it is a point, and a conversion against a point is the number it
     started with. ]==]
function M:Place()
    local cfg = self:Config()
    local frame = self:Frame()
    if not frame then return false end

    local corner = self:Corner()

    --[==[ Only once the container has been laid out with something in it. It is
         built as a ten pixel square and `Apply` used to place before it laid
         out, so the first placement of a session would have converted an old
         centre by five pixels instead of half a raid and marked the job done --
         a frame half a raid's width from where it was, permanently, from the
         migration meant to prevent exactly that. `Apply` lays out first now and
         this checks anyway. ]==]
    if cfg.anchor ~= "corner" and self.sized then
        local w = frame.GetWidth and frame:GetWidth() or 0
        local h = frame.GetHeight and frame:GetHeight() or 0

        if w > 0 and h > 0 then
            local x = tonumber(cfg.x) or 0
            local y = tonumber(cfg.y) or 0

            if self:GrowsLeft() then cfg.x = x + (w / 2) else cfg.x = x - (w / 2) end
            cfg.y = y + (h / 2)
            cfg.anchor = "corner"
        end
    end

    frame:ClearAllPoints()
    frame:SetPoint(corner, UIParent, "CENTER",
            tonumber(cfg.x) or 0, tonumber(cfg.y) or 0)

    if frame.SetScale then frame:SetScale(tonumber(cfg.scale) or 1) end
    return true
end

function M:StorePosition()
    local cfg = self:Config()
    local frame = self.frame
    if not frame or not frame.GetLeft or not frame:GetLeft() then return false end

    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end

    local edge = self:GrowsLeft() and frame:GetRight() or frame:GetLeft()

    cfg.x = OB.Round(edge - ((GetScreenWidth() / 2) / scale))
    cfg.y = OB.Round(frame:GetTop() - ((GetScreenHeight() / 2) / scale))
    cfg.anchor = "corner"

    return true
end

function M:ResetPosition()
    local cfg = self:Config()
    cfg.x = OB.modules.raidframes.defaults.x
    cfg.y = OB.modules.raidframes.defaults.y

    --[[ The defaults are a corner already; they must not be converted as
         though they were an old centre. ]]--
    cfg.anchor = "corner"

    self:Place()
    Say("raid frames put back where they started.")
    return true
end

function M:DragMode()
    return self.dragging and true or false
end

function M:SetDragMode(on)
    if on and not OB.ModuleEnabled("raidframes") then
        Say("switch the Raid Frames module on first.")
        return false
    end

    self.dragging = on and true or nil

    local frame = self:Frame()
    if not frame then return false end

    if not self.dragging then
        frame:EnableMouse(false)
        frame:SetMovable(false)
        frame.hint:Hide()
        return true
    end

    --[[ Shown while unlocked even with nobody in the group, or a raid frame
         layout could only be arranged inside a raid. ]]--
    frame:Show()
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame.hint:Show()

    frame:SetScript("OnDragStart", function() this:StartMoving() end)

    return true
end

-- ---------------------------------------------------------------------------
-- binding
-- ---------------------------------------------------------------------------

function M:Apply()
    local frame = self:Frame()
    if not frame then return false end

    if not OB.ModuleEnabled("raidframes") or not OB.ModuleShown("raidframes") then
        frame:Hide()
        self.appliedCount = nil
        self:HideBlizzardParty(false)
        return false
    end

    local shown = self:Count()

    --[[ What is on screen, written where it is decided. The roster tick reads
         it; see `OnUpdate`. ]]--
    self.appliedCount = shown

    self:HideBlizzardParty(self:ShouldHideParty())

    if shown <= 0 then
        --[[ Kept up while being moved, so a layout can be arranged out of a
             raid -- which is the only time anybody wants to. ]]--
        if not self.dragging then frame:Hide() end
        return false
    end

    --[[ Laid out before it is placed: the buttons anchor to the container and
         do not care where it is, and placing needs the size the layout gives
         it -- see the migration in `Place`. ]]--
    self:Layout()
    self:Place()

    for index = 1, shown do self:UpdateButton(index) end

    frame:Show()
    return true
end

--[==[ **Which frame is drawing this unit**, or nothing if none is.

     The inverse of `UnitFor`, and it has to agree with it: `raid1..40` are their
     own index, a party is the player first and `party1..4` after. Getting the
     party offset wrong here would update the frame above or below the person who
     actually changed, which reads as the numbers being wrong rather than as the
     wrong frame being written. ]==]
function M:IndexForUnit(unit)
    if type(unit) ~= "string" then return nil end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local _, _, number = string.find(unit, "^raid(%d+)$")
        return tonumber(number)
    end

    if unit == "player" then return 1 end

    local _, _, number = string.find(unit, "^party(%d+)$")
    if number then return tonumber(number) + 1 end

    return nil
end

--[==[ **One person's numbers changing is not a reason to rebuild the grid.**

     `Apply` places the container, lays out every frame and then updates every
     one of them. In a forty-man raid `UNIT_HEALTH` alone fires constantly, and
     every one of those was doing all of that: a profile of eighty-three seconds
     in a raid showed six thousand calls and four seconds of CPU inside this
     function, which is the lag.

     A unit event names its unit. So it updates that unit's frame and stops --
     no placing, no layout, no walk of the other thirty-nine.

     Everything else still rebuilds, because a roster change really can move
     every frame: somebody joining, leaving, or being dragged to another group
     changes what is in which column. ]==]
local UNIT_EVENTS = {
    UNIT_HEALTH = true,
    UNIT_MANA = true,
    UNIT_MAXHEALTH = true,
    UNIT_MAXMANA = true,
    UNIT_RAGE = true,
    UNIT_ENERGY = true,
    UNIT_FOCUS = true,
    UNIT_DISPLAYPOWER = true,
}

function M:OnBind() self:Apply() end

function M:OnEvent()
    if UNIT_EVENTS[event] and arg1 then
        --[[ Nothing to update if the grid is not up. Guarded here rather than
             inside `UpdateButton`, so a hidden module costs a table lookup per
             event instead of building a button to write into. ]]--
        if not OB.ModuleEnabled("raidframes") then return end
        if not OB.ModuleShown("raidframes") then return end

        local index = self:IndexForUnit(arg1)

        --[[ A unit nothing here draws -- a target, a pet, somebody's focus --
             is dropped before any work happens. ]]--
        if not index or index > self:Count() then return end

        self:UpdateButton(index)
        return
    end

    self:Apply()
end
function M:OnStyle() self:Apply() end
function M:OnDraw() end

--[==[ **The group size, checked rather than waited for.**

     Twice a second, and only the count -- `GetNumRaidMembers` and
     `GetNumPartyMembers` are two C calls and a comparison, which is cheaper than
     the arithmetic any one of the forty buttons does on a health event.

     Re-applied **only when the number changed**, so the common case is those two
     calls and nothing else. That is the whole cost of never again showing a raid
     grid over a party because one event went missing. ]==]
local ROSTER_INTERVAL = 0.5

function M:OnUpdate(now)
    now = now or GetTime()

    if self.nextRosterCheck and now < self.nextRosterCheck then return end
    self.nextRosterCheck = now + ROSTER_INTERVAL

    --[==[ **Compared against what is drawn, not against what this last
         sampled.**

         The first version of this kept its own `lastRosterCount` and compared
         the live count with that -- which is a different question, and wrong in
         the case that matters. The tick is throttled, so a roster that changes
         and changes back between two samples is never seen at all; and a sample
         taken while the grid was already up records a number `Apply` never drew.
         Both leave the tick agreeing with itself and disagreeing with the
         screen.

         `Apply` is the authority on what is on screen, so `Apply` writes the
         number. Anything that draws -- an event, a style pass, this -- keeps it
         current for free. ]==]
    if self.appliedCount == self:Count() then return end

    self:Apply()
end

function M:OnUnbind()
    if self.frame then self.frame:Hide() end

    --[[ The client's frames handed back, because a module switched off that
         leaves somebody with no party frames at all has not switched off. ]]--
    self:HideBlizzardParty(false)
end
