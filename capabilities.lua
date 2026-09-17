--[[ Equadis' Classic Overhaul :: client capabilities

  **What this client can actually answer, asked once.**

  An OctoWoW install may carry Nampower, ClassicAPI, SuperWoW and UnitXP_SP3, or
  none of them, or three of four with one switched off this session. Every module
  wants to know, and before this file each of them found out for itself: the
  range module probed UnitXP, the action bars probed it again for the experience
  bar, and nothing remembered the answer between calls.

  So the probes live here and the answers are cached. A module asks
  `OB.Can("distance")` and gets a boolean; it does not learn how the question is
  answered, which is the point -- when a build starts exposing a better source,
  one function here changes and nine modules inherit it.

  **Capabilities, not products.** Modules care whether an exact distance can be
  had, not whose DLL provides it. Product names are derived separately, and only
  for the one place a person wants them: the status line on Home.

  **Never assumed from the launcher.** OctoWoW managing an extension is not the
  same as that extension being loaded now -- the player may have turned it off,
  or the build may predate the feature being probed for. Everything here is a
  runtime question about the function in front of us. ]]--

local OB = EquadisClassicOverhaul

--[[ Answers, keyed by capability name. `nil` means "not asked yet"; `false` is a
     real answer and has to survive, which is why this is not `or`-ed anywhere. ]]--
OB.caps = {}

--[[ **A probe must be positive, and this one was got wrong once already.**

     `UnitXP` exists on every stock 1.12 client as the experience API and means
     nothing by itself. UnitXP_SP3 replaces that same global with a command
     dispatcher.

     The first attempt asked the *stock* question -- `UnitXP("player")` -- and
     concluded "no SP3" when a number came back. That is a bet on SP3 rejecting a
     unit token, and it is the wrong bet: SP3 is a compatible replacement, so it
     can pass an unrecognised command through to the function it displaced. On
     such a build the probe saw a number, concluded "stock", and switched the
     extension off on a machine where it was installed and working.

     So probe on a **shape the experience API cannot produce**. It returns a
     number or nothing; no path through it yields a boolean. A boolean back is
     proof the dispatcher answered, and does not depend on guessing what SP3 does
     with input meant for something else.

     Moved here verbatim from the range module rather than rewritten. It is the
     second version of this probe and it was expensive to arrive at. ]]--
local function probeUnitXP()
    if type(UnitXP) ~= "function" then return false end

    local ok, sight = pcall(UnitXP, "inSight", "player", "player")
    if ok and type(sight) == "boolean" then return true end

    --[[ An SP3 build too old for inSight. Weaker, so it is second and it is
         guarded: distance from yourself to yourself is exactly zero, and the
         stock API has to have *failed* to answer its own question first. Without
         that guard a client whose UnitXP returns 0 for an unknown unit reads as
         SP3, and every distance comes back 0 -- a bar stuck on "too close" is
         worse than one admitting it cannot measure. ]]--
    local okX, xp = pcall(UnitXP, "player")
    if okX and type(xp) == "number" then return false end

    local okD, yards = pcall(UnitXP, "distanceBetween", "player", "player")
    return (okD and type(yards) == "number" and yards == 0) and true or false
end

--[[ Present, callable, and answering the shape we need. `type(f) == "function"`
     is most of it, but a global that throws on every call is not a capability,
     so the ones with a safe self-directed question get asked it. ]]--
local function callable(name)
    return type(getglobal(name)) == "function"
end

local PROBES = {}

--[[ **A true distance in yards between two units.**

     Three sources, and the module asking does not care which. Nampower's
     `GetUnitDistance` uses the object manager it already maintains and covers
     hostile units; UnitXP covers everything; SuperWoW's `UnitPosition`
     deliberately answers for friendly units only, so it is last and partial. ]]--
PROBES.distance = function()
    if callable("GetUnitDistance") then return true end
    if probeUnitXP() then return true end
    return callable("UnitPosition")
end

--[[ **Line of sight, which is UnitXP's alone.**

     Kept as its own capability rather than folded into `distance`, because a
     build can measure and not see: SuperWoW positions give yardage with no
     opinion about walls.

     UnitXP's own documentation calls this a local calculation and does not claim
     precision. It is good enough to fade a party frame and not good enough to
     refuse to cast, and nothing here should present it as server truth. ]]--
PROBES.sight = function()
    --[==[ **A native `IsUnitInSight` counts, and this probe used to miss it.**

         `OB.InSight` asks that function first and UnitXP second -- a Nampower
         build extended the way this installation's `GetUnitDistance` was answers
         perfectly well without SP3 anywhere near it. This probe asked only about
         UnitXP, so on such a build the capability said "no line of sight" while
         the function that provides it sat there answering.

         Nothing read the capability at the time, which is why it went unnoticed:
         a wrong answer nobody asks for looks exactly like a right one. The
         distance module asks now. ]==]
    if type(IsUnitInSight) == "function" then
        local ok, sight = pcall(IsUnitInSight, "player")
        if ok and type(sight) == "boolean" then return true end
    end

    if not probeUnitXP() then return false end
    local ok, sight = pcall(UnitXP, "inSight", "player", "player")
    return (ok and type(sight) == "boolean") and true or false
end

PROBES.unitxp = probeUnitXP

--[[ A stable identity for a unit, which vanilla has no concept of. Everything
     that wants to stop identifying mobs by their displayed name needs this. ]]--
PROBES.guid = function()
    if not callable("UnitGUID") then return false end
    local ok, guid = pcall(UnitGUID, "player")
    return (ok and guid ~= nil and guid ~= "") and true or false
end

--[[ The engine's own in-range answer for a spell. Boolean rather than a number,
     but it is the server's threshold rather than our table of assumptions. ]]--
PROBES.spellrange = function() return callable("IsSpellInRange") end

--[[ Reading a unit's underlying fields directly -- real health, real power, the
     values the client already has and vanilla will not hand over. This is what
     makes learned mob-health estimates unnecessary. ]]--
PROBES.unitfield = function() return callable("GetUnitField") end

--[[ Modern power APIs. Vanilla has `UnitMana` and a power *type*; these are the
     later shape, and having them means not switching on the type by hand. ]]--
PROBES.power = function()
    return callable("UnitPower") and callable("UnitPowerMax")
end

--[[ **Nameplates addressable as units.**

     The single largest upgrade available to that module: a token turns every
     unit function on a plate, replacing name matching that cannot tell two
     Defias Bandits apart. Probed by resolving one rather than by testing for a
     global, because the token only means anything if `UnitExists` accepts it. ]]--
PROBES.nameplateunits = function()
    if type(UnitExists) ~= "function" then return false end
    local ok, exists = pcall(UnitExists, "nameplate1")
    return (ok and type(exists) ~= "nil") and true or false
end

--[[ SuperWoW announces itself, which is rare enough to be worth using directly.
     Everything else here is inferred from the functions in front of us. ]]--
PROBES.superwow = function()
    return SUPERWOW_VERSION ~= nil
end

--[[ **Ask once; remember, including the noes.**

     A false is as expensive to establish as a true and just as stable within a
     session, so both are kept. `pcall` around the probe because a probe that
     throws is answering "no" in the least convenient way available. ]]--
function OB.Can(name)
    if OB.caps[name] ~= nil then return OB.caps[name] end

    local probe = PROBES[name]
    if not probe then return false end

    local ok, value = pcall(probe)
    OB.caps[name] = (ok and value) and true or false

    return OB.caps[name]
end

--[[ Forget the answers. An extension cannot appear mid-session, but a reload can
     bring one in, and the slash command exists so a player who has just switched
     one on does not have to be told to log out. ]]--
function OB.RecheckCapabilities()
    OB.caps = {}
    return true
end

--[[ **`OB.HasUnitXP` kept as a name**, because the range module and its tests
     have called it since before this file existed and it reads better at the
     call sites than `OB.Can("unitxp")`. It is now cached, which it was not: it
     re-probed on every distance lookup, which is a `pcall` and a dispatcher call
     per frame per unit. ]]--
function OB.HasUnitXP()
    return OB.Can("unitxp")
end

--[[ **The four names a person recognises**, for the status line on Home and
     nowhere else. No module should branch on these -- a module wants to know
     whether it can have a distance, not whose code supplies one.

     Only SuperWoW is detected by an announcement. The other three are inferred
     from functions they are known to provide, so a false negative is possible if
     a build ships without the feature we look for. That is the right way round:
     the status line then under-claims, and everything else in the addon keys off
     the capability that actually failed. ]]--
OB.enhancements = {
    { key = "nampower", name = "Nampower",
      caps = { "unitfield", "spellrange" } },
    { key = "classicapi", name = "ClassicAPI",
      caps = { "power", "guid", "nameplateunits" } },
    { key = "superwow", name = "SuperWoW", caps = { "superwow" } },
    { key = "unitxp", name = "UnitXP", caps = { "unitxp" } },
}

function OB.EnhancementActive(key)
    for i = 1, table.getn(OB.enhancements) do
        local entry = OB.enhancements[i]

        if entry.key == key then
            --[[ Any one of its capabilities is enough. These are inferences, and
                 requiring all of them would report "missing" for a build that
                 ships most of what it is known for. ]]--
            for c = 1, table.getn(entry.caps) do
                if OB.Can(entry.caps[c]) then return true end
            end
            return false
        end
    end

    return false
end

--[[ What to say when something is absent. Named for the thing the player loses
     rather than the DLL they lack, because "UnitXP not detected" is a fact about
     their install and "precise distance unavailable" is a fact about their
     interface, and only the second one tells them whether they care. ]]--
OB.enhancementLoss = {
    unitxp = "precise distance and line-of-sight features unavailable",
    nampower = "exact unit values and engine range checks unavailable",
    classicapi = "modern unit and nameplate APIs unavailable",
    superwow = "enhanced unit resolution unavailable",
}
