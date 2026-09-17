--[[ Equadis' Classic Overhaul :: where the time and the garbage go

  **Three rounds of dungeon-lag fixes were found by reading code and guessing.**

  Each round found something real -- an unthrottled aura rebuild, a string
  concatenation per plate per frame, a combat line parsed twice -- and not one of
  them could be *confirmed* as the cause, because nothing measured which of this
  addon's own functions was responsible. The game's profiler answers at the frame
  script: `EquadisClassicOverhaulHUD:OnUpdate, 28 MB`. That names the room the
  problem is in and nothing inside it.

  pfDebug already has the mechanism and it is the right one -- sample `gcinfo()`
  and `GetTime()` either side of a call, and keep the difference. What it does
  not have is reach: it hooks frame scripts, so everything this addon does
  arrives as one lump under the HUD's OnUpdate.

  So this is that technique pointed at our own methods. It wraps every module's
  hot functions by name from the registry, which means a module written later is
  measured without being remembered here.

  **It costs nothing while it is off.** The wrappers are installed when profiling
  starts and removed when it stops; there is no branch on a hot path the rest of
  the time.

  **`gcinfo` is in kilobytes and rounded**, so a single call to a cheap function
  usually reads as zero. That is fine and is why the count is kept: a thousand
  calls that each allocate a little add up to a number, and the total is what the
  collection pause is actually made of.
]]--

local OB = EquadisClassicOverhaul

local function Say(msg) OB.Print(msg, "Profile") end

--[[ The methods worth measuring: the ones that run on a clock, on an event, or
     on a redraw. Anything called from one of these is counted inside it, which
     is the point -- the report says which *entry point* is expensive, and the
     next question is answered by wrapping something narrower. ]]--
local HOT_METHODS = {
    "OnUpdate", "OnEvent", "OnDraw", "OnStyle",
    "Apply", "Refresh", "Scan", "Style",
}

--[[ **The second tier, for when the first tier has already named the room.**

     The entry points above answer "which function is expensive". They cannot
     answer "which part of it", because everything they call is counted inside
     them. The first real scan said `tooltip:OnUpdate` and `damage:OnDraw`, and
     the next question -- what inside those -- needs the narrower wrapping this
     list exists to provide.

     Off by default. Wrapping a function that runs several times per entry point
     costs more than wrapping the entry point, and a first scan should not pay
     for a question nobody has asked yet. `/eq perf deep` turns it on. ]]--
local DEEP_METHODS = {
    "Decorate", "Resize", "DrawWindow", "RowText", "RowName",
    "CacheVisibleFadeSnapshot", "PlaceBarAgainst", "AlignColumns",

    --[[ Everything one `Decorate` calls. It came back at 50 kB a call while
         being called only a few dozen times, so the cost is inside one of
         these and there is no way to tell which by reading. ]]--
    "DatabaseSource", "AddDatabaseLines", "ColorUnitInfo",
    "NormalizeItemValues", "StyleTooltip", "ApplyQuestIdVisibility",
}

--[[ Shared services that are not module methods and are on the hottest paths in
     the addon. Named because there is no registry to walk for them. ]]--
local HOT_GLOBALS = {
    "ReadCombatLine",
    "AddCombatLine",
    "AuraList",

    --[[ **Added so a fix could be checked rather than assumed.**

         `DamageRows` was rewritten to cache its sorted list after a scan blamed
         `damage:OnDraw` for 16 MB. The scan after that showed OnDraw costing
         very nearly what it cost before -- and no way to tell whether the cache
         was working and something else dominated, or the cache was not working
         at all, because a plain global is not a module method and nothing
         wrapped it. Now it is measured. ]]--
    "DamageRows",
    "SetBarText",
}

OB.profileData = OB.profileData or {}
OB.profiling = false

--[[ One entry per measured function: how many times, how long, how much.

     Negative deltas are discarded rather than clamped to zero. A collection can
     run in the middle of a measured call and hand back *less* memory than it
     started with; counting that as zero is honest, counting it as a negative
     number makes a busy function look free. ]]--
local function note(name, runtime, runmem)
    local entry = OB.profileData[name]

    if not entry then
        entry = { calls = 0, time = 0, mem = 0 }
        OB.profileData[name] = entry
    end

    entry.calls = entry.calls + 1
    if runtime > 0 then entry.time = entry.time + runtime end
    if runmem > 0 then entry.mem = entry.mem + runmem end
end

--[[ **Reentrancy is handled by not handling it.**

     `Apply` calls `Refresh`, and both are measured -- so the inner call's
     allocation is counted twice, once against itself and once against its
     caller. That is what a caller *costs*, which is the question being asked,
     and pretending otherwise would need a call stack this does not have.

     Read the report as "this entry point is responsible for this much",
     not as a partition of the total. ]]--
local function wrap(owner, key, label)
    local original = owner[key]
    if type(original) ~= "function" then return nil end

    owner[key] = function(a, b, c, d, e)
        local mem = gcinfo()
        local start = GetTime()

        local r1, r2, r3 = original(a, b, c, d, e)

        note(label, GetTime() - start, gcinfo() - mem)

        return r1, r2, r3
    end

    return original
end

--[[ What was replaced, so stopping puts it all back. Keyed by the table and the
     key rather than by the label, because that is what has to be restored. ]]--
local wrapped = {}

function OB.StartProfile(deep)
    if OB.profiling then return false end

    OB.profileData = {}
    OB.profileDeep = deep and true or false
    wrapped = {}

    for id, m in pairs(OB.modules) do
        for i = 1, table.getn(HOT_METHODS) do
            local key = HOT_METHODS[i]

            --[[ `rawget` rather than a plain index, so a method a module
                 inherits is not wrapped once per module that inherits it. ]]--
            if rawget(m, key) then
                local original = wrap(m, key, id .. ":" .. key)
                if original then
                    table.insert(wrapped, { owner = m, key = key, original = original })
                end
            end
        end

        --[[ Only when asked. See the note on DEEP_METHODS: these run inside the
             entry points above, so wrapping them costs more and answers a
             narrower question. ]]--
        if deep then
            for i = 1, table.getn(DEEP_METHODS) do
                local key = DEEP_METHODS[i]

                if rawget(m, key) then
                    local original = wrap(m, key, id .. ":" .. key)
                    if original then
                        table.insert(wrapped, { owner = m, key = key, original = original })
                    end
                end
            end
        end
    end
    for i = 1, table.getn(HOT_GLOBALS) do
        local key = HOT_GLOBALS[i]

        if type(OB[key]) == "function" then
            local original = wrap(OB, key, "OB." .. key)
            if original then
                table.insert(wrapped, { owner = OB, key = key, original = original })
            end
        end
    end

    OB.profiling = true
    OB.profileStarted = GetTime()

    Say("measuring " .. table.getn(wrapped) .. " functions. "
            .. (deep and "deep. " or "") .. "Go and do the thing that lags, then '/eq perf' again.")

    return true
end

function OB.StopProfile()
    if not OB.profiling then return false end

    for i = 1, table.getn(wrapped) do
        local entry = wrapped[i]
        entry.owner[entry.key] = entry.original
    end

    wrapped = {}
    OB.profiling = false

    return true
end

--[[ Sorted by whichever column was asked for, because the two questions are
     different: memory is what the collection pause is made of, and time is what
     a frame is made of. A function can be terrible at one and blameless at the
     other. ]]--
function OB.ProfileRows(sortBy)
    local rows = {}

    for name, entry in pairs(OB.profileData) do
        table.insert(rows, {
            name = name,
            calls = entry.calls,
            time = entry.time,
            mem = entry.mem,
        })
    end

    local key = (sortBy == "time") and "time" or "mem"

    table.sort(rows, function(a, b)
        if a[key] == b[key] then return a.name < b.name end
        return a[key] > b[key]
    end)

    return rows
end

function OB.ReportProfile(sortBy, limit)
    local rows = OB.ProfileRows(sortBy)
    --[[ Twenty rather than twelve. Twelve hid `tooltip:Resize` below the cut,
         and its absence was read as "cheap" when it could equally have meant
         "not shown" -- which nearly cost an afternoon restructuring the wrong
         function. A row costs a line of chat; a wrong conclusion costs more. ]]--
    limit = tonumber(limit) or 20

    if table.getn(rows) == 0 then
        Say("nothing was measured.")
        return false
    end

    local span = (GetTime() - (OB.profileStarted or GetTime()))
    if span < 1 then span = 1 end

    Say(string.format("%d functions over %d seconds, worst %s first:",
            table.getn(rows), span, (sortBy == "time") and "time" or "memory"))

    for i = 1, math.min(limit, table.getn(rows)) do
        local row = rows[i]

        --[[ Per second as well as total, because a five-minute sample and a
             thirty-second one are not comparable otherwise -- and the number
             worth acting on is the rate. ]]--
        OB.Raw(string.format("   %-34s %6d calls  %7.1f kB  %5.1f kB/s  %5.1f ms",
                row.name, row.calls, row.mem, row.mem / span, row.time * 1000))
    end

    return true
end

--[[ `sortBy` carries both the sort column and the depth, because the command is
     one word and people type what they remember. "deep" only means anything on
     the way in; stopping ignores it. ]]--
function OB.ToggleProfile(sortBy)
    if OB.profiling then
        OB.StopProfile()
        return OB.ReportProfile(sortBy)
    end

    return OB.StartProfile(sortBy == "deep")
end

--[[ Overwrites the fallbacks core.lua defined, and records that it got here.
     `/eq doctor` reads this, so "did the file load" has an answer that does not
     depend on guessing from a symptom. ]]--
OB.profilerLoaded = true
