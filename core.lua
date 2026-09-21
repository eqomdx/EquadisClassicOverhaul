--[[ Equadis' Classic Overhaul :: core

  Namespace, shared media, table helpers and the module registry.

  Loaded first, so every later file can pick the namespace up as a file local
  ("local OB = EquadisClassicOverhaul"). The TOC load order is the dependency graph:
  nothing here may reach into config, frames or modules.

  The namespace is a plain table rather than a Frame. Equadis' Threat Meter
  makes its namespace the event frame, which means every key it stores risks
  shadowing a widget method (TWT.Show, TWT.Hide, TWT.GetName) and forces the
  whole addon through one event handler. Frames hang off this table instead.
]]--

EquadisClassicOverhaul = {}
local OB = EquadisClassicOverhaul

OB.version = "0.99.306"
OB.addonName = "Equadis' Classic Overhaul"

--[[ The addon folder name is load-bearing: every media path below hardcodes it,
     so renaming the folder silently breaks every custom texture and font. The
     repo name has to match too, or a plain clone into Interface\AddOns does not
     work. ]]--
OB.mediaPath = "Interface\\AddOns\\EquadisClassicOverhaul\\"

local _, playerClass = UnitClass("player")
OB.class = playerClass or "WARRIOR"

-- ---------------------------------------------------------------------------
-- chat
-- ---------------------------------------------------------------------------

--[[ **One prefix, one colour, and it names where the message came from.**

     `Eq <part>:` in `#008b8b` on every line this addon writes, so an Overhaul
     message is recognisable in a channel scrolling past without anybody having
     to read it -- and so a line about the chat scan says which part it is,
     rather than eleven different features all announcing themselves as the same
     word.

     **The body stays white.** Colouring a whole message teal makes it a banner
     rather than a sentence, and several of these run to three lines. The colour
     is the label's job.

     Each file names itself once, at the top, in a local `Say`. That is why this
     takes the name as an argument rather than working it out: there is no
     caller to inspect in 5.0 worth the trouble, and a constant per file is
     something a reader can see. ]]--
OB.tagColor = "|cff008b8b"

--[==[ **One switch that speaks for eight subsystems should say one thing.**

     Edit mode unlocks every module that has something to move, and each of them
     announced itself: *Action Bars: drag mode on*, *Buff Frames: move mode on*,
     *Party Frames*, *Unit Frames*, and then Edit Mode's own line under all of
     them. Five lines in the harness and more in a real profile, every time the
     mode is toggled -- and toggled is what it is for, so it is five lines going
     in and five coming out.

     Held here rather than in the eight modules because that is where the
     decision belongs: a module saying what it did is right when somebody asked
     *it* to do something, and noise when somebody asked for all of them at once.
     Each `SetDragMode` stays exactly as it was and keeps working on its own.

     **Held, not dropped.** A module that refuses -- the party frames decline
     while the feature is off -- is saying something the reader needs, and
     swallowing that would trade a noisy toggle for a silent failure. Edit mode
     reads the held lines back and folds them into its one message. ]==]
function OB.HoldPrint(on)
    if on then
        OB.heldPrints = {}
    else
        local held = OB.heldPrints
        OB.heldPrints = nil
        return held
    end
end

function OB.Print(msg, from)
    if OB.heldPrints then
        table.insert(OB.heldPrints, { msg = tostring(msg), from = from })
        return
    end

    DEFAULT_CHAT_FRAME:AddMessage(OB.tagColor .. "Eq " .. (from or "Overhaul")
            .. ":|cffffffff " .. tostring(msg))
end

-- unprefixed, for the generated help listing
function OB.Raw(msg)
    DEFAULT_CHAT_FRAME:AddMessage(msg)
end

-- ---------------------------------------------------------------------------
-- reload-required warning
-- ---------------------------------------------------------------------------

--[==[ **A setting that cannot take effect immediately must say so where the
     reader is looking, and there is now one place that does that.**

     This built a banner of its own: a dark red strip across the top of the
     screen, its own backdrop, its own close button, its own idea of where a
     notice goes. Meanwhile edit mode -- a whole mode, which unlocks every frame
     in the interface -- announced itself in **chat** and drew nothing at all,
     while bind mode had a banner of its own again.

     Three notices, three answers, none of them each other's. So there is one
     surface now and it belongs to edit mode, because edit mode is the one that
     needed an interface anyway: `OB.EditPanel` in `editmode.lua`.

     **The entry point stays here** because `core.lua` loads first and everything
     calls this; only the frame moved. Held rather than drawn if the panel is not
     loaded, so a notice raised before `editmode.lua` has run is not lost -- it
     appears the moment the panel next refreshes. ]==]
function OB.RequireReload(reason)
    OB.pendingNotice = (reason and reason ~= "") and tostring(reason) or true

    if type(OB.RefreshEditPanel) == "function" then
        OB.RefreshEditPanel()
        return
    end

    --[[ No panel yet, and a notice nobody can see is not a notice. Chat is the
         floor, not the answer. ]]--
    OB.Print("reload required" .. (type(reason) == "string"
            and (": " .. reason) or ""), "Settings")
end

-- ---------------------------------------------------------------------------
-- a tooltip this addon has placed itself
-- ---------------------------------------------------------------------------

--[==[ **This addon's own windows say where their tooltips go, and the
     placement policy leaves them alone.**

     The tooltip module wraps `GameTooltip.SetOwner` so that a *client* frame
     anchoring a tooltip beside itself -- the need/greed popup, an action button
     -- still lands where the Tooltip page says tooltips go. That was the fix for
     the roll popup's tooltip ignoring every setting.

     It swept up this addon's own calls too. A damage meter row, a bag slot, an
     item browser line, the reputation bar: each anchors its tooltip beside the
     thing it describes on purpose, some with offsets, and a policy written for
     the client's frames has no business overriding a decision this addon made
     about its own. Ten deliberate anchors were being moved to the screen's fixed
     spot, which is the regression this exists to end.

     So this addon's own callers go through here. The flag is one-shot -- set,
     honoured by the wrapper, cleared -- so nothing about the tooltip's state
     outlives the call that asked for it. ]==]
function OB.OwnTooltip(owner, anchor, x, y)
    if not GameTooltip or not GameTooltip.SetOwner then return false end

    GameTooltip.eqEcoOwnAnchor = true
    GameTooltip:SetOwner(owner, anchor, x, y)
    GameTooltip.eqEcoOwnAnchor = nil

    return true
end

-- ---------------------------------------------------------------------------
-- table helpers
-- ---------------------------------------------------------------------------

local floor = math.floor

function OB.Round(num)
    if num >= 0 then return floor(num + 0.5) end
    return -floor(-num + 0.5)
end

--[==[ **Whitespace off both ends of a typed argument.**

     Written because two commands already called it and it did not exist. Both
     spelled the call `OB.Trim and OB.Trim(msg) or msg` -- the guard that is
     meant to survive a missing helper, and which quietly *became* the
     behaviour: the trim never happened and nothing said so.

     `/way clear ` with a trailing space did not match "clear", and
     `/addfriend    ` would have written a friend whose name is four spaces.
     Neither is visible from reading the call, which is the point: a defensive
     `and ... or` around a function that is never defined is indistinguishable
     from one around a function that is.

     `%s` covers the space a keyboard produces and the tab a paste can. The
     non-greedy capture is what makes it work in one pass on 1.12's pattern
     matcher. ]==]
function OB.Trim(text)
    if type(text) ~= "string" then return "" end

    --[[ Held in a local first. `string.gsub` answers the string *and* how many
         substitutions it made, and `return` on the call would hand both back --
         harmless in `local x = Trim(s)`, and not harmless at all in
         `table.insert(t, Trim(s))`, where a second return in the final argument
         position becomes a third argument and inserts at an index. ]]--
    local out = string.gsub(text, "^%s*(.-)%s*$", "%1")
    return out
end

--[[ A value held inside a range. The same bounds the sliders use, so a value
     arriving by drag cannot reach somewhere the panel could never set. ]]--
function OB.Clamp(v, low, high)
    if v < low then return low end
    if v > high then return high end
    return v
end

function OB.DeepCopy(src)
    local copy = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            copy[k] = OB.DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

--[[ A table is a *leaf* when it is a plain tuple of scalars under numeric keys:
     a colour, {r, g, b, a}. Anything else -- a named record, or a numeric table
     whose entries are themselves tables -- is a structure worth recursing into.

     The distinction matters in both directions. A colour must be replaced
     wholesale, because merging one index by index would leave a green channel
     from the default under a red the user picked. But power.byType is numeric
     too ([0] mana through [4] happiness) and must be merged, or a saved profile
     from before a type existed would delete it. ]]--
local function isLeaf(t)
    --[[ **An empty table is not a leaf**, and getting that backwards silently
         deleted defaults.

         The loop below never runs for one, so it used to fall through to `true`
         -- and a leaf is *replaced* wholesale. So a saved profile written before
         a table had any contents, `modulesEnabled = {}` being the one that
         caught it, replaced the shipped defaults with nothing at all. Every
         module registered since was suddenly on, and every default under any
         other empty table was gone.

         Merging is the right answer because an empty table carries no
         information: recursing into nothing leaves the destination alone, which
         is exactly what "the user saved no opinion about this" should mean. ]]--
    if next(t) == nil then return false end

    for k, v in pairs(t) do
        if type(k) ~= "number" then return false end
        if type(v) == "table" then return false end
    end
    return true
end

--[[ Merge `src` over `dst` in place, recursing into structures and replacing
     leaves.

     ShaguDPS merges one level deep, so its nested per-window tables come
     straight out of the saved variables and never pick up a new default. That is
     the bug this avoids -- and with five addons' settings eventually landing in
     one profile, it would have bitten repeatedly. ]]--
function OB.DeepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table"
                and not isLeaf(v) and not isLeaf(dst[k]) then
            OB.DeepMerge(dst[k], v)
        elseif type(v) == "table" then
            dst[k] = OB.DeepCopy(v)
        else
            dst[k] = v
        end
    end
end

-- "colors.1" -> the table holding it and the final key, so a nested option key
-- reads and writes like a flat one
function OB.Resolve(root, path)
    if not root then return nil, nil end

    local container, key = root, path
    local pos = string.find(key, "%.")

    while pos do
        local head = string.sub(key, 1, pos - 1)
        local index = tonumber(head)
        if index then head = index end

        container = container[head]
        if type(container) ~= "table" then return nil, nil end

        key = string.sub(key, pos + 1)
        pos = string.find(key, "%.")
    end

    local index = tonumber(key)
    if index then key = index end

    return container, key
end

function OB.Get(root, path)
    local container, key = OB.Resolve(root, path)
    if not container then return nil end
    return container[key]
end

function OB.Set(root, path, value)
    local container, key = OB.Resolve(root, path)
    if not container then return end
    container[key] = value
end

-- ---------------------------------------------------------------------------
-- media
-- ---------------------------------------------------------------------------

--[[ Statusbar textures. The config stores the index and the panel derives the
     label by stripping everything up to the last backslash, so appending an
     entry here is all that is needed to ship a new texture. ]]--
--[[ **The client's dropdown globals, seeded before anything builds a dropdown.**

     `UIDROPDOWNMENU_OPEN_MENU` is a frame *name* and starts life nil: FrameXML
     only assigns it when something actually opens a menu. 1.12's
     `UIDropDownMenu.lua` builds names out of it, so touching the dropdown API
     before any menu has ever been opened throws "attempt to concatenate global
     'UIDROPDOWNMENU_OPEN_MENU' (a nil value)" -- once per control. The item
     browser's filter row hit it five times on `/db` on a fresh login.

     Filled in here rather than at each call site, because every dropdown in the
     addon has the same exposure: the options panel builds around fifty of them
     and only escapes by being opened later in a session, which is luck rather
     than design.

     An empty string is the right value: no frame is named "", so every
     comparison that was false against nil stays false, and the concatenations
     that were throwing now produce a string that matches nothing. Only ever
     written when the client has left it unset -- Bagshui clears this same global
     deliberately for its own menus, and it is not ours to own. ]]--
if UIDROPDOWNMENU_OPEN_MENU == nil then UIDROPDOWNMENU_OPEN_MENU = "" end
if UIDROPDOWNMENU_MENU_LEVEL == nil then UIDROPDOWNMENU_MENU_LEVEL = 1 end
if UIDROPDOWNMENU_MENU_VALUE == nil then UIDROPDOWNMENU_MENU_VALUE = "" end

OB.textures = {
    OB.mediaPath .. "textures\\Smooth",
    OB.mediaPath .. "textures\\ShaguPlates",
    OB.mediaPath .. "textures\\TukUI",
    OB.mediaPath .. "textures\\ElvUI",
    OB.mediaPath .. "textures\\Gradient",
    OB.mediaPath .. "textures\\Striped",
    "Interface\\BUTTONS\\WHITE8X8",
    "Interface\\TargetingFrame\\UI-StatusBar",
    "Interface\\Tooltips\\UI-Tooltip-Background",
    "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}

--[[ Window chrome. Line art on transparent, 32x32, drawn in near-white so
     SetVertexColor can tint it -- which is how a button dims when its action is
     unavailable rather than being swapped for a second file.

     Power-of-two and uncompressed 32-bit TGA, both of which 1.12 requires: a
     non-power-of-two texture loads as a black square, which looks like a broken
     button rather than a broken file. ]]--
OB.icons = {
    settings = OB.mediaPath .. "textures\\icons\\settings",
    lock     = OB.mediaPath .. "textures\\icons\\lock",
    unlock   = OB.mediaPath .. "textures\\icons\\unlock",
    close    = OB.mediaPath .. "textures\\icons\\close",
    new      = OB.mediaPath .. "textures\\icons\\new",
    reset    = OB.mediaPath .. "textures\\icons\\reset",

    --[==[ The junk bin on the merchant window. Its own file rather than a client
         icon, because 1.12 has no dustbin: nothing in `Interface\Icons` reads as
         "get rid of this", and the nearest candidates are bags. ]==]
    trash    = OB.mediaPath .. "textures\\icons\\trash",
}

--[[ Every window with a header sits at the same height, so two meters open side
     by side line up. Shared for the same reason the icons are. ]]--
OB.HEADER_H = 18

--[[ Fonts as { display name, path } pairs. The four Blizzard faces ship with the
     client and live outside the addon folder, which is why their path is carried
     here rather than rebuilt from the name. ]]--
local fontDefs = {
    { "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
    { "Arial Narrow", "Fonts\\ARIALN.TTF" },
    { "Skurri", "Fonts\\SKURRI.TTF" },
    { "Morpheus", "Fonts\\MORPHEUS.TTF" },

    { "BalooBhaina" }, { "BigNoodleTitling" }, { "Continuum" }, { "DieDieDie" },
    { "Expressway" }, { "Homespun" }, { "Hooge" }, { "LondrinaSolid" },
    { "Myriad-Pro" }, { "PT-Sans-Narrow-Bold" }, { "PT-Sans-Narrow-Regular" },
    { "Roboto" }, { "RobotoMono" }, { "Share" }, { "ShareBold" },
    { "Sniglet" }, { "SquadaOne" },
}

OB.fonts = {}      -- display names, in panel order
OB.fontPaths = {}  -- parallel list of paths
OB.fontIndex = {}  -- name -> index

for i, def in ipairs(fontDefs) do
    OB.fonts[i] = def[1]
    OB.fontPaths[i] = def[2] or (OB.mediaPath .. "fonts\\" .. def[1] .. ".ttf")
    OB.fontIndex[def[1]] = i
end

--[[ 1.12 knows OUTLINE and nothing else usable here -- THINOUTLINE was never a
     real font flag and rendered identically -- so the outline is a plain on/off
     flag rather than a list. ]]--

--[[ **Four borders, and the same four everywhere.**

     `None`, `Thin`, `Classic` and `Blizzard`. Every element that draws a border
     offers all four, so the word means one thing across the addon rather than
     each subsystem inventing its own list.

     `Standard` used to be the third and is now `Classic`: it was never a
     standard of anything, and the name said nothing about what it looked like.
     A profile that stored the old index keeps the same border, because the
     index is what is saved and three is still three.

     `Blizzard` is the ornate one with corner ornaments, from the client's own
     dialog art. `Thin` and `Classic` are a single-pixel line and a bevelled
     one -- the same shapes the nameplate addon this borrows from uses, under
     its MIT licence with the notice kept beside the files. ]]--
OB.borders = { "None", "Thin", "Classic", "Blizzard" }

--[==[ **How heavy a border the text wears**, which was a switch and is now a
     choice of two weights.

     1.12 draws text with `OUTLINE` or `THICKOUTLINE`, and the difference is the
     difference between text that is readable over a spell icon and text that is
     not. Keybinds are the case that asked for it -- small pale letters on top of
     art nobody chose for its contrast -- but every string this addon draws sits
     over something.

     Stored as an index like every other list on the panel. Ordered so that the
     index is the weight: nothing, thin, thick. ]==]
--[==[ **The file behind a font's display name.**

     `OB.fonts` and `OB.fontPaths` are parallel lists and every reader that
     wanted one from the other walked them itself. One place, because the answer
     for a name nothing ships has to be **nil** rather than the first font in the
     list -- `SetFont` with a bad path draws nothing at all, and a silently blank
     label is worse than the wrong face. ]==]
function OB.FontFile(name)
    if not name or name == "" then return nil end

    for i = 1, table.getn(OB.fonts) do
        if OB.fonts[i] == name then return OB.fontPaths[i] end
    end

    return nil
end

OB.fontOutlines = { "None", "Thin", "Thick" }

--[==[ **The class portraits, in one place.**

     `UI-CLASSES-CIRCLES` is the round, transparent atlas this addon bundles --
     round because the square one leaks its corners outside a portrait opening,
     which is a fault this has already been fixed for once. The coordinates are
     the donor's, transcribed.

     Here rather than private to the unit frames because the walkthrough draws
     the same portraits: two copies of a coordinate table is two things to get
     wrong, and the one that drifts is the copy nobody is looking at. ]==]
OB.classCircleArt = OB.mediaPath .. "textures\\UI-CLASSES-CIRCLES"

OB.classCircles = {
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

--[[ One class circle onto a texture that already exists, or nothing at all for
     a class this atlas does not carry -- a server with a class of its own would
     otherwise be given a corner of somebody else's. ]]--
function OB.SetClassCircle(texture, class)
    local coords = class and OB.classCircles[class]
    if not texture or not coords or not texture.SetTexture then return false end

    texture:SetTexture(OB.classCircleArt)

    if texture.SetTexCoord then
        texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end

    return true
end

--[==[ **The flags `SetFont` wants, from whatever the profile is holding.**

     Both spellings are answered because both exist in saved variables. Before
     this was a list it was a boolean, and a profile written by an older build
     says `true` -- which is Thin, the only outline there was. The migration
     rewrites them, and this makes a profile that has somehow escaped it draw
     correctly anyway rather than dropping its outline silently.

     Anything unrecognised is no outline, which is the client's own default and
     the safe end of the mistake. ]==]
function OB.FontFlags(value)
    if value == true then return "OUTLINE" end
    if not value then return nil end

    local index = tonumber(value)

    if not index then
        --[[ The name, for anything that stores one rather than an index. ]]--
        for i = 1, table.getn(OB.fontOutlines) do
            if string.lower(OB.fontOutlines[i]) == string.lower(tostring(value)) then
                index = i
            end
        end
    end

    if index == 2 then return "OUTLINE" end
    if index == 3 then return "THICKOUTLINE" end

    return nil
end

-- how far the border art sits outside the bar, per OB.borders index
OB.borderPads = { 0, 2, 5, 4 }

--[[ One table for bars, meter windows and anything else that draws a border, so
     Thin means the same thickness on all of them. ]]--
--[==[ **`outset` is where the ink actually is, and it was being guessed.**

     A backdrop's edge band is drawn *inward* from the frame's boundary, and in
     all three of these the opaque art hugs the **outer** end of that band --
     nothing is centred in it. So a frame placed to put the art somewhere has to
     be offset by how far the art reaches inward, and nothing else.

     Measured off the files rather than reasoned about, by decoding them and
     reading the alpha across one edge tile:

       * `textures\\border` -- 64x8, opaque column 0 of 8.
       * `UI-Tooltip-Border` -- 128x16, opaque columns 1..5 of 16.
       * `UI-DialogBox-Border` -- 256x32, opaque columns 3..13 of 32.

     `outset` is the inner end of that span scaled to the size the edge is drawn
     at, so a frame offset by it has the whole ornament sitting *outside* what it
     frames with its inner edge on the boundary. The tooltip was using half the
     edge size instead, which is right only for art running down the middle of
     the tile -- and gave a four, eight and nineteen pixel gap respectively. ]==]
OB.borderEdges = {
    [2] = {
        edgeFile = OB.mediaPath .. "textures\\border",
        edgeSize = 8,
        outset = 1,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    },
    [3] = {
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        outset = 5,
    },
    [4] = {
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        outset = 14,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
}

--[==[ **A border's corners cannot be bigger than the thing they frame.**

     A backdrop draws eight pieces, and the four corners are `edgeSize` square.
     Put a 14-pixel corner on a bar twenty-two pixels tall and the top pair and
     the bottom pair are asking for twenty-eight pixels of a twenty-two-pixel
     frame: they overlap in the middle, and the border reads as a doubled smear
     across the bar rather than an outline around it.

     That is what `Classic` was doing to health bars. It is not a fault of that
     style -- the same art is right on a tooltip -- it is a fault of using one
     edge size for a tooltip and for a twelve-pixel bar. So the size is clamped
     to what actually fits, per widget, rather than every caller being trusted
     to pick a number.

     **Returned as a copy.** `OB.borderEdges` is one shared table read by
     nameplates, tooltips, meters and bars; narrowing an entry in place would
     shrink the border on everything else styled afterwards -- the same trap as
     writing into the table `OB.Look` hands back. ]==]
local borderFitCache = {}

function OB.BorderEdge(index, width, height)
    local edge = OB.borderEdges[index]
    if not edge then return nil end

    local size = edge.edgeSize or 8

    --[==[ The shorter side decides, because both sides carry two corners. ]==]
    local shortest

    if type(width) == "number" and width > 0 then shortest = width end
    if type(height) == "number" and height > 0
            and (not shortest or height < shortest) then
        shortest = height
    end

    if not shortest then return edge end

    local fits = math.floor(shortest / 2)
    if fits < 1 then fits = 1 end
    if fits >= size then return edge end

    local key = index .. ":" .. fits
    if borderFitCache[key] then return borderFitCache[key] end

    --[==[ The insets come down with it. They are how far the background is held
         off the edge, so leaving them at full width on a narrowed border eats
         the middle of a small bar. ]==]
    local scale = fits / size
    local out = { edgeFile = edge.edgeFile, edgeSize = fits }

    --[[ Scaled with everything else: `outset` is a distance measured in the
         art, so an edge narrowed to fit a small bar has a proportionally
         smaller one. Left at full size it would describe art nobody is
         drawing. ]]--
    if edge.outset then out.outset = edge.outset * scale end

    if edge.tile ~= nil then out.tile = edge.tile end
    if edge.bgFile then out.bgFile = edge.bgFile end

    if edge.insets then
        out.insets = {
            left = (edge.insets.left or 0) * scale,
            right = (edge.insets.right or 0) * scale,
            top = (edge.insets.top or 0) * scale,
            bottom = (edge.insets.bottom or 0) * scale,
        }
    end

    borderFitCache[key] = out
    return out
end

--[==[ **A CVar that may not exist, asked without taking the interface down.**

     `GetCVar` does not answer nil for a name it does not know. It **raises**:

         Couldn't find CVar named 'rotateMinimap'

     which is a real error from a real reload, from asking whether the minimap
     rotates on a client that has no such setting. Guarding with
     `type(GetCVar) == "function"` -- which two places in this addon did -- checks
     that the *function* is there and says nothing about the *name*, so it reads
     like a guard and protects against nothing.

     Every name an addon does not set itself is a name some client may not have:
     `rotateMinimap` here, and the four `uf*` cvars in the migration, which
     belong to an addon most people never ran. That one would have thrown inside
     `LoadConfig`, which is the whole addon rather than one feature.

     So the question is asked through here, once, and a name that does not exist
     answers nil the way it should have. ]==]
function OB.CVar(name)
    if type(GetCVar) ~= "function" or not name then return nil end

    local ok, value = pcall(GetCVar, name)
    if not ok then return nil end

    return value
end

--[==[ **A glow is not a border with a soft texture in it.**

     A border puts its one solid line at the *outer* boundary of the band it is
     given, which is why every one of these reads as an outline: an outline is
     what it is. Drawn a second time further out -- which is what the nameplate
     module's "glow" was -- it is not a glow, it is a second outline with a gap
     behind it, and the gap is the thing that gives it away.

     A glow runs the other way. It is opaque against the thing it surrounds and
     falls off to nothing at the outer boundary, so there is no edge anywhere in
     it and nothing to leave a gap. That is what `textures\\glow` is: the same
     eight-tile edge convention as `textures\\border`, with the ramp reversed
     and a quarter falloff in the corners. It is white, so the colour is entirely
     the caller's.

     **Sized to the band, by the caller.** Anchor the frame `n` pixels outside
     whatever it wraps and ask for `n`, and the glow spans exactly the gap it was
     given: solid where it meets the bar, gone at the edge. Any other edge size
     leaves either a hard stop partway out or a band that never reaches the thing
     it is glowing around. ]==]
OB.glowEdgeFile = OB.mediaPath .. "textures\\glow"

local glowEdges = {}

function OB.GlowEdge(size)
    size = math.floor(tonumber(size) or 0)
    if size < 1 then size = 1 end

    if not glowEdges[size] then
        glowEdges[size] = { edgeFile = OB.glowEdgeFile, edgeSize = size }
    end

    return glowEdges[size]
end

--[==[ **Every window this addon owns, out of one table.**

     This was the client's tooltip background inside the client's tooltip border,
     which is why the item database, the bag window, the addon list and the
     meters all looked like tooltips somebody had put a list in. Reskinning the
     settings panel made that obvious: one window had been given a look and the
     other eight had not.

     A flat fill and a one-pixel edge, which is the same shape the panel draws
     with rules. `WHITE8X8` for the fill so the colour a window asks for is the
     colour it gets -- the tooltip background is a patterned texture, so every
     backdrop colour was being multiplied by somebody else's grey mottling.

     The edge is this addon's own thin border, the same file the Thin option
     uses on a health bar. See `skin.lua` for the palette and `OB.SkinWindow`
     for the call that applies this with the colours to match. ]==]
OB.backdrop = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = OB.mediaPath .. "textures\\border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- media entries are paths; menus and the slash prompt show the file name only
function OB.CleanLabel(label)
    local _, _, clean = string.find(label or "", ".+\\(.+)")
    return clean or label or ""
end

--[[ A dropdown whose stored value is one of its own strings rather than an index
     into it.

     Media lists (textures, fonts, borders) store an index, because the list can
     grow and a path is a poor thing to keep in saved variables. A setting like a
     ticker mode is the opposite: "nofull" should survive the list being
     reordered, and it reads far better at the slash prompt than "2". ]]--
function OB.Enum(values, labels)
    return { enum = true, values = values, labels = labels }
end

--[[ **The look, as option rows, for any subsystem that wants them.**

     Texture, font, font size, outline and border are the five settings that make
     five separate addons look like five separate addons. Every subsystem gets
     the same five, from here, so a new one cannot arrive with four of them and a
     differently worded fifth.

     `Use The Shared Look` is on by default and the other five grey out beneath
     it, which is the panel's usual rule doing exactly what it is for: the
     overrides still say what they say, and they apply the moment you switch the
     sharing off.

     Two arguments' worth of care in the defaults, though. `ownLook = false` is
     the switch; the five values are **absent**, not copied from the profile,
     because OB.Look falls back key by key. Copying them would freeze a
     subsystem's look at whatever the shared one was the day it was registered,
     and then quietly stop following it. ]]--
--[[ **The appearance block, and only the parts a subsystem actually uses.**

     `styled` was all or nothing, so a module that draws one line of text got
     Bar Texture and Border as well -- controls that change nothing, on a page
     where everything else does. The chat module had exactly this complaint made
     about it and was answered by dropping the block entirely; the map and the
     waypoint arrow have the opposite problem, because they *do* use the font
     and nothing else.

     `styled = true` still means all five, which is what a bar-drawing subsystem
     wants and what every existing module said. A table names the parts:

         styled = { font = true, fontOutline = true }

     Font Size is separate from Font on purpose. The clock and the waypoint
     arrow each carry their own size slider and pass it to `ApplyFont`
     explicitly, so the shared one is read by nothing -- a third dead control
     that looked like the two beside it. ]]--
function OB.LookOptions(styled)
    --[[ Built here rather than at file scope: `OB.textures`, `OB.fonts` and
         `OB.borders` are filled in as media is registered, and a list captured
         before that is a list of nothing. ]]--
    local rows = {
        { key = "texture",     row = { "Bar Texture", "texture", OB.textures, 200 } },
        { key = "font",        row = { "Font", "font", OB.fonts, 200 } },
        { key = "fontSize",    row = { "Font Size", "fontSize", "slider", 6, 24, 1 } },
        { key = "fontOutline", row = { "Font Outline", "fontOutline", OB.fontOutlines, 200 } },
        { key = "border",      row = { "Border", "border", OB.borders, 200 } },
    }

    local out = { { "Appearance", "__h_look", "header" } }

    for i = 1, table.getn(rows) do
        local entry = rows[i]
        local wanted = false

        if styled == true then
            wanted = true
        elseif type(styled) == "table" then
            wanted = styled[entry.key] and true or false
        end

        if wanted then table.insert(out, entry.row) end
    end

    --[[ A header with nothing under it is worse than no header: it says a
         section exists and then shows an empty page. ]]--
    if table.getn(out) == 1 then return {} end

    return out
end

--[[ Nothing. There is no switch, and that is the point.

     There was a `Use The Shared Look` toggle here and the five settings greyed
     out beneath it, which made the common case -- change this subsystem's font --
     take two clicks and a moment working out why the control was dead. Setting
     one *is* the override, and leaving it alone *is* sharing.

     So the values stay absent by default and OB.Look falls back to the profile
     key by key. A subsystem that has never been touched follows the shared look
     exactly as before; one that has, differs in precisely the keys somebody
     changed. Nothing to switch, nothing to explain. ]]--
function OB.LookDefaults()
    return {}
end

-- ---------------------------------------------------------------------------
-- scanning
--
-- Vanilla hides a good deal behind tooltip text and nowhere else: an item's mana
-- per five seconds, a spell's cost. Reading it means loading the thing into a
-- tooltip nobody can see and reading the font strings back out.
-- ---------------------------------------------------------------------------

--[[ The shared hidden tooltip, built on first use.

     One instance for the whole addon. Several things want it -- the druid mana
     estimate now, mob health and the feign-death health override later -- and a
     tooltip per caller means loading the same eighteen items several times over
     for the same answer. ]]--
function OB.ScanTooltip()
    if not OB.scanTip then
        --[==[ **Parented and owned by `UIParent`, which is what everything else
             does.**

             This was parented to nothing and owned by `WorldFrame`. Every other
             scanning tooltip in this install -- Atlas-CFM's three, Bagshui's,
             AceGUI's, LibDBIcon's -- passes `UIParent` for both, and a tooltip
             that never populates is the failure this shape is suspected of: the
             lines exist as font strings and stay empty, so a scan reads nil and
             calls it "no such aura".

             Reported as debuffs with icons and no timers on a unit that was
             targeted or moused over -- the two states where the exact scan runs
             and the tooltip is the only source of a name. ]==]
        OB.scanTip = CreateFrame("GameTooltip", "EquadisClassicOverhaulScanTooltip",
                UIParent, "GameTooltipTemplate")
        OB.scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return OB.scanTip
end

-- the text of the scanning tooltip's Nth left-hand line, or nil past the end
function OB.ScanLine(index)
    local line = getglobal("EquadisClassicOverhaulScanTooltipTextLeft" .. index)
    if not line then return nil end
    return line:GetText()
end

--[[ True when any of `textures` (a set keyed by icon path) is on the player.

     Icon paths are the only identity a 1.12 buff has from Lua -- there is no id
     and the name is localised -- so every buff test in the addon is a texture
     comparison, and they all come through here. ]]--
--[==[ **A player buff is found by position and read by handle, and they are not
     the same number.**

     `GetPlayerBuff(position, "HELPFUL")` maps the nth helpful buff to the index
     every other player-buff call wants, and answers -1 past the end. Handing the
     *position* straight to `GetPlayerBuffTexture` asks a different question of
     the same shape, and gets it wrong twice over: the index space it walks holds
     this player's debuffs too, and it stops at the first slot that is not a
     helpful buff -- so a single debuff can hide every buff behind it.

     Silent, of course. The answer is "you have no such buff", which is what you
     get for not having it.

     Every other addon in this install resolves the handle first -- BigWigs,
     BetterCharacterStats and SuperCleveRoidMacros all do, and BigWigs'
     `CancelAuraTexture` is this loop exactly. So does this now.

     Falls back to the position when the call is missing, which is what a
     stripped client would leave. ]==]
local BUFF_POSITIONS = 32

function OB.PlayerBuffIndex(position, harmful)
    if type(GetPlayerBuff) ~= "function" then return position end

    local index = GetPlayerBuff(position, harmful and "HARMFUL" or "HELPFUL")

    --[[ -1 is the end of the list. Anything else that is not a number is a
         client that cannot answer, and is treated the same way. ]]--
    if type(index) ~= "number" or index < 0 then return nil end

    return index
end

function OB.HasPlayerBuff(textures)
    local position = 0

    while position < BUFF_POSITIONS do
        local index = OB.PlayerBuffIndex(position)
        if not index then return false end

        local texture = GetPlayerBuffTexture(index)
        if not texture then return false end

        if textures[texture] then return true end

        position = position + 1
    end

    return false
end

-- ---------------------------------------------------------------------------
-- bars
--
-- A bar is a rectangle with a style, and one module draws into it. The rectangle
-- and the drawing stay separate tables -- render.lua and layout.lua are handed
-- geometry and must never learn what is drawn in it -- but the pairing is fixed:
-- one bar, one module, declared by the module and never reassigned.
--
-- An earlier version made that pairing a user setting, with an "occupant"
-- dropdown per slot. It bought nothing: every bar can be dragged anywhere, so
-- ordering was already the user's to choose, and the indirection only added a
-- concept and a control to get wrong. What is left is a flat list of named bars.
--
-- The order here is the order they appear in the panel *and* the order they are
-- stacked on screen by default, which is one less thing to reconcile.
-- ---------------------------------------------------------------------------

OB.barOrder = {
    "health", "resource", "mainhand", "offhand",
    "ranged", "distance", "secondary", "extras",
}

OB.barLabels = {
    health    = "Health",
    resource  = "Resource",
    mainhand  = "Main Hand",
    offhand   = "Off Hand",
    ranged    = "Ranged Attack",
    distance  = "Ranged Distance Check",
    secondary = "Secondary Resource",
    extras    = "Extras",
}

--[[ The one bar whose occupant depends on the class, and so the one whose name
     does too. A rogue's is combo points; a warrior's will be stances.

     Only combo points exists. The rest are named here rather than left blank
     because the name is the cheap half and it says what the bar is for before
     anything fills it. A class with no module naming `extras` simply has no
     Extras bar -- see OB.BarsForClass. ]]--
OB.extrasLabels = {
    ROGUE = "Combo Points",
    DRUID = "Combo Points",

    -- reserved, not implemented:
    -- WARRIOR = "Stances", PALADIN = "Auras", SHAMAN = "Totems",
    -- HUNTER = "Aspects", PRIEST = "Forms",
}

function OB.BarLabel(barId)
    if barId == "extras" then
        return OB.extrasLabels[OB.class] or OB.barLabels.extras
    end
    return OB.barLabels[barId] or barId
end

-- ---------------------------------------------------------------------------
-- power types
-- ---------------------------------------------------------------------------

OB.powerNames = {
    [0] = "Mana",
    [1] = "Rage",
    [2] = "Focus",
    [3] = "Energy",
    [4] = "Happiness",
}

--[[ Class colours. RAID_CLASS_COLORS exists in 1.12 but a client mod may have
     replaced or trimmed it, so this is the fallback and the lookup goes through
     OB.ClassColor. ]]--
OB.classColors = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER  = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
    SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE    = { r = 0.41, g = 0.80, b = 0.94 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    DRUID   = { r = 1.00, g = 0.49, b = 0.04 },
}

--[[ **The roster APIs answer a localized class name; everything else wants a
     token.**

     `UnitClass` is the only one that gives both -- "Rogue" and "ROGUE". The six
     roster readers give one string each, and in 1.12 that string is the
     localized name: `GetGuildRosterInfo` says "Warrior", not "WARRIOR". Feed
     that to a colour lookup keyed by token and every guildmate comes back white,
     silently, which is also what an unknown player looks like.

     This is the whole job of Ace's BabbleClass, which Prat carried for it. On an
     enUS client the mapping is `string.upper` -- every token is one word -- so
     the map is built rather than shipped, and a name that does not land on a
     known class is handed back as nil so the caller can tell "not a class I
     know" from "a class whose colour I could not find".

     A different locale needs a real table here. Recorded rather than pretended
     away: this returns nil there, and an uncoloured name is the correct failure. ]]--
function OB.ClassToken(class)
    if not class or class == "" then return nil end

    local token = string.upper(class)
    if OB.classColors[token] then return token end

    return nil
end

--[[ A point between two colours, alpha included.

     Alpha blends with the rest rather than being taken from one end, so a ramp
     whose ends have different opacities fades as smoothly as it shades. Taking
     it from either end alone would make a bar jump in opacity at the midpoint
     while its colour moved continuously. ]]--
function OB.Blend(from, to, t)
    local function mix(i, default)
        local a, b = from[i] or default, to[i] or default
        return a + ((b - a) * t)
    end

    return { mix(1, 0), mix(2, 0), mix(3, 0), mix(4, 1) }
end

--[[ **Three anchors, not two, and the middle one is why it is legible.**

     A straight blend from green to red passes through (0.5, 0.5, 0) at halfway
     -- olive-brown, dark, and it reads as a fault rather than as a middling
     value. A bright midpoint keeps every point on the ramp bright. Anyone
     wanting a plain two-colour blend sets the middle to the average of the ends.

     Shared rather than owned by the health bar, because the threat meter wants
     exactly the same ramp pointed the other way: health runs full to empty and
     threat runs safe to about-to-pull, and the arithmetic does not care which.
     Equadis' Threat Meter had this hardcoded green/yellow/red in its row
     painter with nothing on its panel able to reach it; here all three are
     settings, in both places. ]]--
function OB.Ramp(low, half, full, fraction)
    if not fraction or fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end

    if fraction >= 0.5 then return OB.Blend(half, full, (fraction - 0.5) * 2) end
    return OB.Blend(low, half, fraction * 2)
end

--[==[ **A unit's resource, coloured by what it is rather than by who has it.**

     Blizzard colours the power bar by the resource in use, not by class, and the
     difference matters on exactly the frames that are small: a druid's bar
     turning yellow is how you know they shifted.

     `ManaBarColor` is the client's own table on 1.12. A few private-server forks
     expose `UnitPowerType` while stock-era clients have the older `UnitManaType`,
     so both are tried, and vanilla colours are kept as a fallback -- without one
     the strip draws as the uncoloured white texture, which is what the party
     frames were doing.

     Here rather than in a module because the raid frames grew it first and the
     party frames needed the same answer. Two copies would have been two
     opinions about what colour rage is. ]==]
local POWER_FALLBACK = {
    [0] = { r = 0.00, g = 0.00, b = 1.00 }, -- mana
    [1] = { r = 1.00, g = 0.00, b = 0.00 }, -- rage
    [2] = { r = 1.00, g = 0.50, b = 0.25 }, -- focus
    [3] = { r = 1.00, g = 1.00, b = 0.00 }, -- energy
    [4] = { r = 0.00, g = 1.00, b = 0.00 }, -- happiness
}

--[==[ **A bar's text, in whichever of the six shapes was asked for.**

     The unit frames grew these and the party frames were asked for the same
     ones, so they live here rather than being written twice -- "Current / Max
     (Percent)" has to mean the same thing on both or the setting is lying about
     one of them.

     `shorten` and `decimals` are passed rather than read, because they are the
     one part that is genuinely per-module: the unit frames offer a switch for
     the thousand-to-ten-thousand band and the party frames need not. Above ten
     thousand always shortens either way -- five digits do not fit in a bar and
     nobody reads them, which is not a preference. ]==]
function OB.ShortValue(value, shorten, decimals)
    value = value or 0
    decimals = decimals or 0

    if value > 1000000 then
        return string.format("%." .. decimals .. "fm", value / 1000000)
    end

    if value > 10000 then
        return string.format("%." .. decimals .. "fk", value / 1000)
    end

    if value > 1000 and shorten then
        return string.format("%." .. decimals .. "fk", value / 1000)
    end

    return tostring(OB.Round(value))
end

--[[ The keys behind `OB.unitTextModes`, in the same order, so a stored index
     means the same mode wherever it was chosen. ]]--
OB.unitTextKeys = { "none", "value", "percent", "max", "valuepct", "maxpct" }

function OB.BarText(value, max, mode, shorten, decimals)
    if mode == "none" then return "" end

    value = value or 0
    max = max or 0

    local function number(v) return OB.ShortValue(v, shorten, decimals) end

    local function percent()
        if max == 0 then return "0%" end
        return math.floor((value / max) * 100 + 0.5) .. "%"
    end

    if mode == "percent" then return percent() end
    if mode == "value" then return number(value) end
    if mode == "max" then return number(value) .. "/" .. number(max) end

    if mode == "valuepct" then
        return number(value) .. " (" .. percent() .. ")"
    end

    if mode == "maxpct" then
        return number(value) .. "/" .. number(max) .. " (" .. percent() .. ")"
    end

    return number(value)
end

function OB.PowerType(unit)
    local kind

    if type(UnitPowerType) == "function" then
        kind = UnitPowerType(unit)
    elseif type(UnitManaType) == "function" then
        kind = UnitManaType(unit)
    end

    kind = tonumber(kind)
    if kind == nil then kind = 0 end

    return kind
end

function OB.PowerColor(unit)
    local kind = OB.PowerType(unit)
    local color = ManaBarColor and ManaBarColor[kind]

    if not color then color = POWER_FALLBACK[kind] or POWER_FALLBACK[0] end

    return color.r or color[1] or 0, color.g or color[2] or 0,
            color.b or color[3] or 1
end

function OB.ClassColor(class)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not c then c = OB.classColors[class] end
    if not c then return 1, 1, 1 end
    return c.r, c.g, c.b
end

--[==[ **Whether a unit is a player, in a way that survives them being far away.**

     `UnitIsPlayer` needs an object in the client's world to answer about. A
     group member on the other side of the zone does not have one, so it answers
     *no* about somebody who is plainly a player -- and every bar that colours by
     class fell back to green the moment they walked out of range. The roster has
     known their class the whole time; it is only the object that is missing.

     So a yes is taken and a no is examined. If the client cannot see the unit at
     all, its no is a statement about visibility rather than about the unit, and
     the group roster is the better witness. This is the same rule the mount
     check and the capability probes follow, for the same reason: an API that can
     only fail in one direction should only be trusted in the other.

     The token match is what makes trusting the roster safe. `party1` and
     `raid7` are group members by construction, and a pet's token -- `partypet1`,
     `raidpet7` -- does not match, because `%d` will not accept the `p`. So a pet
     out of range still falls through to a no, which is what the party frames
     wanted `UnitIsPlayer` for in the first place. ]==]
function OB.IsPlayerUnit(unit)
    if not unit then return false end
    if type(UnitIsPlayer) ~= "function" then return false end

    if UnitIsPlayer(unit) then return true end

    --[[ A no from a unit the client can see is a real no. ]]--
    if type(UnitIsVisible) ~= "function" or UnitIsVisible(unit) then
        return false
    end

    return (string.find(unit, "^party%d") or string.find(unit, "^raid%d"))
            and true or false
end

--[[ **A unit's class token, asked of the roster when the unit cannot answer.**

     `UnitClass` reads the same object `UnitIsPlayer` does, so it has the same
     blind spot. For raid members there is a second source that never goes out of
     range: the roster row itself, whose sixth return is the class token. There
     is no party equivalent in 1.12, but party members are close enough to the
     player often enough that `UnitClass` carries them. ]]--
function OB.UnitClassToken(unit)
    if not unit then return nil end

    if type(UnitClass) == "function" then
        local _, token = UnitClass(unit)
        if token then return token end
    end

    if type(GetRaidRosterInfo) ~= "function" then return nil end

    local _, _, index = string.find(unit, "^raid(%d+)$")
    if not index then return nil end

    local _, _, _, _, _, fileName = GetRaidRosterInfo(tonumber(index))
    return fileName
end

--[[ **A level's colour is the client's difficulty colour**, which says something
     a class colour cannot: not who they are, but where they are relative to you.
     Red is above you, grey is beneath, and the eye reads the five steps without
     doing the subtraction.

     The thresholds are the client's own -- five above is red, three is orange,
     within two is yellow -- and the green band is asked for rather than
     hardcoded, because `GetQuestGreenRange` widens it as you level and a fixed
     number would be wrong everywhere except one level.

     Computed here rather than borrowed from `GetDifficultyColor`: that function
     exists in 1.12 but is FrameXML rather than the API, so a client mod may have
     replaced it and a UI-hiding addon may have unloaded it. The arithmetic is
     four comparisons. ]]--
OB.levelColors = {
    red = { 1.00, 0.10, 0.10 },
    orange = { 1.00, 0.50, 0.25 },
    yellow = { 1.00, 1.00, 0.00 },
    green = { 0.25, 0.75, 0.25 },
    grey = { 0.50, 0.50, 0.50 },
}

function OB.LevelColor(level, relativeTo)
    local mine = relativeTo or UnitLevel("player") or 1
    local c = OB.levelColors

    if not level or level <= 0 then return unpack(c.grey) end

    local difference = level - mine

    if difference >= 5 then return unpack(c.red) end
    if difference >= 3 then return unpack(c.orange) end
    if difference >= -2 then return unpack(c.yellow) end

    --[[ Below yellow, green until the gap is wide enough to be beneath notice.
         Nine levels at sixty, five at ten -- the client's number, asked for. ]]--
    local green = 5
    if type(GetQuestGreenRange) == "function" then
        green = GetQuestGreenRange() or green
    end

    if -difference <= green then return unpack(c.green) end
    return unpack(c.grey)
end

-- ---------------------------------------------------------------------------
-- module registry
-- ---------------------------------------------------------------------------

OB.modules = {}      -- id -> descriptor
OB.moduleOrder = {}  -- registration order, which is also panel order
OB.bound = {}        -- slotId -> descriptor
OB.eventMap = {}     -- event -> { descriptor, ... }
OB.dragMap = {}      -- frame -> slotId

--[[ Register a module.

     A module owns behaviour, colour and semantics; it never owns geometry. Its
     `defaults` are copied straight into OB.defaults.modules[id], so config.lua
     never has to know any module exists -- the merge in LoadConfig makes new
     settings appear for existing users on its own. Modules load after config.lua
     but before LoadConfig runs at VARIABLES_LOADED, so the timing works out.

     One id occupies at most one slot, which makes the binder a single pass. That
     is why the swing timers are three ids from one implementation table rather
     than one module with instances, and it is why state can live on the
     descriptor itself (self.start, self.last) with no instance objects. ]]--
function OB.RegisterModule(m)
    if not m or not m.id then return end

    if OB.modules[m.id] then
        OB.Print("duplicate module id '" .. m.id .. "' ignored.")
        return
    end

    m.priority = m.priority or 0
    m.renders = m.renders or "bar"
    m.name = m.name or m.id
    m.events = m.events or {}

    --[[ The client APIs this module cannot work without, by name.

         Documentation the self-test reads, and never a load gate. Refusing to
         register a module because one API is missing would silently drop it on a
         client with a slightly different surface, which is strictly worse than a
         module that draws nothing and can tell you exactly which call it wanted.

         An API the module is *expected* to survive without does not belong here.
         The range readout probes for UnitXP and has two fallbacks ready, so
         listing it would make every plain install report a failure for working
         as designed. ]]--
    m.requires = m.requires or {}

    --[[ `feature = true` marks a whole optional subsystem -- the threat meter,
         the damage meter, nameplates, unit frames -- rather than a bar. Only
         features are listed on the Modules page, because switching one off is a
         real decision about whether you would rather run somebody else's.

         A bar is not that. "I do not want an off hand timer" is answered by Show
         Bar, on the Bars page, next to that bar's own settings. Every module
         still has an enable flag; only features offer it as a control. ]]--
    m.feature = m.feature and true or false

    --[[ Listed, described, and not yet real. A subsystem on the roadmap appears
         on the Modules page from the day it is planned rather than the day it
         works, so the page is the roadmap and there is one place to look.

         Its switch is disabled rather than absent -- an entry you cannot enable
         says "coming", where a missing entry says "never". ]]--
    m.development = m.development and true or false

    OB.modules[m.id] = m
    table.insert(OB.moduleOrder, m.id)

    --[[ Absent from `modulesEnabled` means on, which is what lets a module added
         by a later version work without the user going to find it. A module that
         wants the opposite has to say so, and only here: writing `enabled` into
         the module's *own* defaults looks like it would do this and does not --
         the binder reads modulesEnabled and nothing else.

         Used by a feature that is not finished. One that is switched on and
         draws nothing is indistinguishable from one that is broken. ]]--
    if m.defaultEnabled == false then
        OB.defaults.modulesEnabled = OB.defaults.modulesEnabled or {}
        OB.defaults.modulesEnabled[m.id] = false
    end

    if m.defaults then
        OB.defaults.modules = OB.defaults.modules or {}
        OB.defaults.modules[m.id] = OB.DeepCopy(m.defaults)

        --[[ Every **feature** carries the shared-look switch, whether or not it
             asked for one. The panel gives every subsystem the same appearance
             block, so the default that block reads has to exist for all of them
             -- and putting it here means a module cannot forget it. ]]--
        if m.feature then
            OB.DeepMerge(OB.defaults.modules[m.id], OB.LookDefaults())
        end
    end

    return m
end

-- true when this class may run the module at all
function OB.ClassAllows(m)
    if not m then return false end
    if not m.classes then return true end
    return m.classes[OB.class] and true or false
end

function OB.ModuleEnabled(id)
    local m = OB.modules[id]
    if not m then return false end
    if not OB.ClassAllows(m) then return false end
    if not OB.profile then return true end

    local flag = OB.profile.modulesEnabled[id]
    if flag == nil then return true end
    return flag and true or false
end

--[[ **Shown is not Enabled, and they were the same checkbox with two captions.**

     *Enable*, on the Modules page, decides whether the subsystem **runs**: it
     binds, registers events, ticks and counts. Switching it off is about what
     the addon costs.

     *Show*, on the subsystem's own page, decides only whether its windows are on
     screen. An enabled-but-hidden meter keeps counting, which is the whole
     reason the two are separate: hide the damage meter for a pull, show it again
     at the end, and the numbers are there. If Show unbound the module those
     numbers would not exist, and "hide this for a moment" would silently cost
     you the fight.

     Absent means shown, the same rule `modulesEnabled` follows and for the same
     reason: a subsystem added by a later version is visible until somebody says
     otherwise. ]]--
function OB.ModuleShown(id)
    if not OB.ModuleEnabled(id) then return false end
    if not OB.profile or not OB.profile.modulesShown then return true end

    local flag = OB.profile.modulesShown[id]
    if flag == nil then return true end
    return flag and true or false
end

--[[ Which module draws in a bar: the one that names it and whose class gate
     passes. A bar with no such module is simply empty.

     `priority` breaks a tie between two modules claiming the same bar for the
     same class. That should never happen -- Extras is the only bar more than one
     module will ever name, and each of those names a different class -- so a tie
     is a bug rather than a feature. It costs one comparison to fail loudly-ish
     instead of arbitrarily. ]]--
function OB.Occupant(barId)
    local best, bestPriority

    for i = 1, table.getn(OB.moduleOrder) do
        local id = OB.moduleOrder[i]
        local m = OB.modules[id]
        if m.bar == barId and OB.ModuleEnabled(id) then
            if not best or m.priority > bestPriority then
                best, bestPriority = id, m.priority
            end
        end
    end

    return best
end

--[[ The bars this class actually has, in panel order.

     A bar no module on this class can fill is left out of the list entirely
     rather than shown empty: a warrior has no Extras and no Secondary Resource,
     and offering rows for a rectangle that will never be drawn is just a way to
     waste somebody's afternoon. Note this asks about the *class*, not about the
     enable toggles -- a module you switched off still has its bar listed, or you
     would have no way to switch it back on from the Bars page. ]]--
function OB.BarsForClass()
    local list = {}

    for i = 1, table.getn(OB.barOrder) do
        local barId = OB.barOrder[i]
        local possible = false

        for m = 1, table.getn(OB.moduleOrder) do
            local mod = OB.modules[OB.moduleOrder[m]]
            if mod.bar == barId and OB.ClassAllows(mod) then possible = true end
        end

        if possible then table.insert(list, barId) end
    end

    return list
end

-- ---------------------------------------------------------------------------
-- frames
--
-- Created here so later files have something to attach to (ShaguDPS's core.lua
-- does the same). Neither carries a script yet.
-- ---------------------------------------------------------------------------

OB.events = CreateFrame("Frame", "EquadisClassicOverhaulEvents", UIParent)
OB.hud = CreateFrame("Frame", "EquadisClassicOverhaulHUD", UIParent)

--[[ Events the addon always wants, independent of which modules are bound.
     BindSlots re-registers the whole set, so this list and the per-module lists
     are the only two sources. ]]--
OB.coreEvents = {
    "VARIABLES_LOADED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "PLAYER_AURAS_CHANGED",
    "UPDATE_SHAPESHIFT_FORMS",
    "PLAYER_DEAD",
    "PLAYER_ALIVE",
    "PLAYER_UNGHOST",
}

-- ---------------------------------------------------------------------------
-- addons this one has absorbed
-- ---------------------------------------------------------------------------

--[[ **An all-in-one that is merging other addons in has to notice when the
     addon it replaced is still switched on.**

     Two addons that both restyle a Blizzard frame do not politely share it.
     They race: whichever installs its hook last owns the frame, and the loser's
     settings quietly stop changing pixels. Nothing errors, so it reads as "the
     module is broken" rather than "two things are fighting". This install hit
     exactly that -- Unit Frames, its own standalone ancestor and
     DragonflightUI were all switched on together, and the standalone kept the
     target frame art because it takes FrameXML functions this module did not.

     Only *loaded* addons are worth mentioning; a disabled one cannot fight.
     And the warning is tied to the module that supersedes it, so somebody who
     has deliberately turned ECO's Unit Frames off to keep the standalone is not
     nagged about a conflict they chose. ]]--
OB.supersededAddOns = {
    { addon = "EquadisUnitFrames",  feature = "unitframes", label = "UnitFrames" },
    { addon = "EquadisOmniBars",    feature = "actionbars", label = "Action Bars" },
    { addon = "EquadisChatTweaks",  feature = "chat",       label = "Chat" },
    { addon = "EquadisThreatMeter", feature = "threat",     label = "Threat" },
    { addon = "UnitFramesImproved_Vanilla", feature = "unitframes", label = "UnitFrames" },

    --[[ **DragonflightUI-Reforged, once per thing it takes over.**

         Not an Equadis addon, but it replaces whole swathes of the interface
         and this project has been removing its remnants rather than living
         alongside it.

         It was listed here for unit frames only, while the comment beside it
         said "unit frames *and action bars*" -- the sentence knew about a
         conflict the data did not, so nothing was ever said about the bars. It
         has a `map` module too, and `bags`, and `chat`, and a cast bar. Every
         one of those is a frame two addons now both believe they own, and the
         loser does not error: it simply stops changing pixels, which reads as
         "that module is broken".

         One row per module, because the warning names which of ECO's parts is
         being fought over and a single row could only name one. ]]--
    { addon = "DragonflightUI-Reforged", feature = "unitframes", label = "UnitFrames" },
    { addon = "DragonflightUI-Reforged", feature = "actionbars", label = "Action Bars" },
    { addon = "DragonflightUI-Reforged", feature = "map",        label = "Map" },
    { addon = "DragonflightUI-Reforged", feature = "chat",       label = "Chat" },
    { addon = "DragonflightUI-Reforged", feature = "bags",       label = "Bags" },

    --[[ **ShaguTweaks is a bundle, and one mod in it moves the same frames.**

         "Movable Unit Frames" watches every frame for Shift and Control held
         together and, while they are, makes `PlayerFrame` and `TargetFrame`
         draggable -- then takes the drag scripts away again on release.

         That collides with this addon twice over. ECO's edit mode gesture is
         Control-Shift-Alt, which *contains* Control-Shift, so unlocking here
         unlocks there as well; and ECO owns whether those frames are movable,
         so their `StartMoving` lands on a frame ECO has locked and throws
         "Frame PlayerFrame is not movable or resizable".

         Detected precisely rather than by name: ShaguTweaks records each mod in
         `ShaguTweaks_config` by title, `1` for on. Warning about the whole
         addon would be wrong for anybody who has already switched this one
         piece off. ]]--
    { addon = "ShaguTweaks", feature = "unitframes", label = "UnitFrames",
      detect = function()
          return ShaguTweaks_config
                  and ShaguTweaks_config["Movable Unit Frames"] == 1
      end },
    { addon = "DragonflightUI-Reforged", feature = "partyframes", label = "Party Frames" },
}

function OB.ConflictingAddOns()
    local found = {}
    if type(IsAddOnLoaded) ~= "function" then return found end

    for i = 1, table.getn(OB.supersededAddOns) do
        local entry = OB.supersededAddOns[i]

        --[[ `ModuleEnabled` is asked rather than assumed true, so this stays
             quiet for a module the user turned off on purpose. ]]--
        if IsAddOnLoaded(entry.addon) and OB.ModuleEnabled(entry.feature) then
            --[[ **A modular neighbour is asked which parts are switched on.**

                 Some addons are a bundle of small mods rather than one thing,
                 and only one of those mods may touch the same frames. Warning
                 about the whole addon would be wrong for everybody who has
                 already turned that one piece off -- and a warning that is
                 wrong is a warning people stop reading.

                 An entry without a `detect` is the ordinary case: the addon
                 being loaded at all is the conflict. ]]--
            local conflicts = true

            if entry.detect then
                local ok, answer = pcall(entry.detect)
                conflicts = ok and answer and true or false
            end

            if conflicts then table.insert(found, entry) end
        end
    end

    return found
end

--[[ Once a session. PLAYER_ENTERING_WORLD fires again on every loading screen,
     and a warning that reprints each time you step into an instance is a
     warning people learn to scroll past. ]]--
function OB.WarnConflicts()
    if OB.conflictsWarned then return false end

    local found = OB.ConflictingAddOns()
    if table.getn(found) == 0 then return false end

    OB.conflictsWarned = true

    for i = 1, table.getn(found) do
        local entry = found[i]
        OB.Print("|cffff8080" .. entry.addon .. "|r is still enabled and is "
                .. "fighting the " .. entry.label .. " module for the same "
                .. "frames. Turn it off in |cffffd100/addons|r and reload.")
    end

    return true
end

--[[ **The profiler's entry points, defined here so they are never nil.**

     `profiler.lua` overwrites every one of these when it loads. If it does not
     load, these stay and say so.

     This exists because guarding the call site was not enough. `/eq perf`
     shipped calling `OB.ToggleProfile` on a build where the file defining it
     was newly added to the TOC, and **1.12 does not reliably pick up a newly
     added file on `/reload`** -- so the command existed, the function did not,
     and typing it threw. Guarding that one call fixed that one call and left
     the shape of the bug in place: any later command pointing at a file that
     did not load fails the same way.

     A name the dispatcher calls should exist from the moment the addon is
     loaded, whatever else did or did not happen after. Load order is then a
     thing that changes the message, not a thing that throws. ]]--
local function ProfilerMissing()
    OB.Print("the profiler did not load. If this addon was just updated, log "
            .. "out to the desktop and back in -- adding a file needs a full "
            .. "restart, and reloading is not enough.", "Profile")
    return false
end

OB.StartProfile = ProfilerMissing
OB.StopProfile = ProfilerMissing
OB.ReportProfile = ProfilerMissing
OB.ToggleProfile = ProfilerMissing

--[[ Set by profiler.lua on load. `/eq doctor` reports it, because "did the file
     load" is the first question worth answering when a command misbehaves. ]]--
OB.profilerLoaded = false
