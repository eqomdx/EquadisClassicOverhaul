--[[ Equadis' Classic Overhaul :: chat commands

  **A slash command is a keybinding you can type**, and 1.12 gives you one of
  those and not the other. The Key Bindings panel has a hundred and forty
  entries -- Toggle Walk, Sit, Sheath Weapon, Toggle Music -- and every one of
  them is a thing you might rather type than find a spare key for.

  So: any of them can be bound to a command of your own naming. `/walk`, `/sit`,
  `/x` if that is what you want it called.

  **Two kinds of thing can be behind a command**, and the difference is worth
  keeping:

  - a **binding**, which is one of the client's own, named exactly as the Key
    Bindings panel names it. These are the "bind anything" half.
  - a **builtin**, which is one of this addon's, because the client has no
    binding for it or because the useful version does more than the binding
    does. `/fps` reports latency as well as framerate; `/hud` has to move the
    chat frame out from under the interface it is hiding, or you cannot type
    the command that brings it back.

  Both live in one list, because from the outside they are the same thing: a
  word you type that does something.

  **The shipped set is seeded once and then it is yours.** Delete `/fps` and it
  stays deleted -- `chatCommandsSeeded` in the account store is what makes that true.
  A list that refilled itself on login would not be a list you could edit.

  Ported in part from Equadis' Chat Tweaks' Commands module, which is where
  `/fps`, `/hud`, `/sheath`, `/autorun`, `/combatlog` and `/walk` come from and
  where the chat-watcher trick was worked out.
]]--

local OB = EquadisClassicOverhaul

--[[ **Every line this file writes says which part of the addon it came from.**

     One prefix, one colour, and the name after it -- so a message about the
     chat scan says so, rather than leaving the reader to work out which of
     eleven things is talking. See OB.Print. ]]--
local function Say(msg) OB.Print(msg, "Commands") end

-- ---------------------------------------------------------------------------
-- running one of the client's own bindings
-- ---------------------------------------------------------------------------

--[[ **1.12 has no way to invoke a binding by name.**

     The Key Bindings panel lists commands -- `TOGGLERUN`, `SITORSTAND` -- and
     the client holds the Lua for each one internally, keyed to a key. There is
     no `RunBinding` in vanilla to reach it with. Later clients grew one and some
     private servers have back-ported it, so it is tried first and guarded.

     Failing that, each binding is run through the API it is defined in terms
     of. That is not a workaround so much as the same thing said twice: the
     client's `TOGGLERUN` binding *is* a call to `ToggleRun`.

     **Every entry is a function rather than a name**, so a binding that takes an
     argument -- the character sheet wants to know which tab -- is written the
     way it actually reads instead of needing a second column nothing else
     uses. ]]--
local BINDING_API = {
    TOGGLERUN = function() ToggleRun() end,
    TOGGLEAUTORUN = function() ToggleAutoRun() end,
    TOGGLESHEATH = function() ToggleSheath() end,
    JUMP = function() JumpOrAscendStart() end,
    DISMOUNT = function() Dismount() end,

    SCREENSHOT = function() Screenshot() end,
    TOGGLEMUSIC = function() Sound_ToggleMusic() end,
    TOGGLESOUND = function() Sound_ToggleSound() end,
    TOGGLEFRAMERATE = function() ToggleFramerate() end,

    TOGGLEBACKPACK = function() ToggleBackpack() end,
    OPENALLBAGS = function() OpenAllBags() end,
    TOGGLEWORLDMAP = function() ToggleWorldMap() end,
    TOGGLEQUESTLOG = function() ToggleQuestLog() end,
    TOGGLETALENTS = function() ToggleTalentFrame() end,
    TOGGLESOCIAL = function() ToggleFriendsFrame() end,
    TOGGLEGAMEMENU = function() ToggleGameMenu() end,
    TOGGLECHARACTER0 = function() ToggleCharacter("PaperDollFrame") end,
    TOGGLECHARACTER1 = function() ToggleCharacter("SkillFrame") end,
    TOGGLECHARACTER2 = function() ToggleCharacter("ReputationFrame") end,
    TOGGLECHARACTER4 = function() ToggleCharacter("HonorFrame") end,
    TOGGLESPELLBOOK = function() ToggleSpellBook(BOOKTYPE_SPELL) end,
    TOGGLEPETBOOK = function() ToggleSpellBook(BOOKTYPE_PET) end,

    --[[ **Sitting is the one that needs two answers.** Vanilla and the clients
         built on it disagree about which function sits you down, and the emote
         works on all of them -- so the specific call is tried and the emote is
         the floor. ]]--
    SITORSTAND = function()
        if type(SitStandOrDescendStart) == "function" then
            SitStandOrDescendStart()
        else
            DoEmote("SIT")
        end
    end,
}

--[[ One binding, run.

     `RunBinding` first where it exists, because that is the client doing exactly
     what it does when the key is pressed -- including anything a server has
     changed about it. The table is the fallback, not the preference. ]]--
function OB.RunBinding(command)
    if not command then return false end

    if type(RunBinding) == "function" then
        RunBinding(command)
        return true
    end

    local fn = BINDING_API[command]
    if not fn then return false end

    fn()
    return true
end

--[[ **What the Key Bindings panel calls a command.**

     `BINDING_NAME_<COMMAND>` is the client's own label -- the string somebody
     read in the panel before coming here -- so it is the one to show. The raw
     command name is the fallback, which is what a server's own binding will
     answer to. ]]--
function OB.BindingLabel(command)
    if not command then return "?" end

    local label = getglobal("BINDING_NAME_" .. command)
    if label and label ~= "" then return label end

    return command
end

-- ---------------------------------------------------------------------------
-- the things this addon does that the client has no binding for
-- ---------------------------------------------------------------------------

--[[ **Hiding the interface, and being able to get it back.**

     `UIParent:Hide()` takes the chat frame with it, which means the command that
     brings it back cannot be typed. So while the interface is hidden, the chat
     frame and its edit box are moved onto `WorldFrame` for as long as the edit
     box is open, and put back afterwards.

     The watcher that notices the edit box opening cannot be a child of UIParent
     either, or its OnUpdate stops with the rest of the interface. That is the
     whole trick, and it is Equadis' Chat Tweaks'. ]]--
function OB.HudWatcher()
    if OB.hudWatcher then return OB.hudWatcher end

    local frame = CreateFrame("Frame", "EquadisOverhaulHudWatcher", WorldFrame)
    frame:Hide()

    frame:SetScript("OnUpdate", function() OB.WatchHudChat() end)

    OB.hudWatcher = frame
    return frame
end

function OB.ChatEditBox()
    return (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or ChatFrameEditBox
end

function OB.WatchHudChat()
    local box = OB.ChatEditBox()
    if not box then return end

    if box:IsShown() then
        if not OB.hudDetached then OB.DetachHudChat(box) end
    elseif OB.hudDetached then
        OB.ReattachHudChat()
    end
end

function OB.DetachHudChat(box)
    OB.hudDetached = {}

    for _, frame in ipairs({ DEFAULT_CHAT_FRAME, box }) do
        if frame then
            table.insert(OB.hudDetached, {
                frame = frame,
                parent = frame:GetParent(),
                strata = frame:GetFrameStrata(),
            })

            frame:SetParent(WorldFrame)
            frame:SetFrameStrata("DIALOG")
        end
    end

    --[[ The box asked for focus while it was invisible, so it has to ask
         again. ]]--
    if box.SetFocus then box:SetFocus() end
end

function OB.ReattachHudChat()
    if not OB.hudDetached then return false end

    for i = 1, table.getn(OB.hudDetached) do
        local saved = OB.hudDetached[i]
        saved.frame:SetParent(saved.parent or UIParent)
        saved.frame:SetFrameStrata(saved.strata)
    end

    OB.hudDetached = nil
    return true
end

function OB.ToggleHud()
    if UIParent:IsShown() then
        Say("interface hidden. Press Enter and type the same command "
                .. "to bring it back.")

        OB.HudWatcher()
        UIParent:Hide()
        OB.hudWatcher:Show()
    else
        OB.ReattachHudChat()
        if OB.hudWatcher then OB.hudWatcher:Hide() end
        UIParent:Show()
    end

    return true
end

--[[ Combat logging, which is a toggle the client exposes only as a setter that
     also happens to answer. `LoggingCombat()` with no argument reads; with one,
     writes and returns what it ended up as. ]]--
function OB.ToggleCombatLog()
    if type(LoggingCombat) ~= "function" then
        Say("combat logging is not available on this client.")
        return false
    end

    local wanted = not (LoggingCombat() and true or false)
    local got = LoggingCombat(wanted)

    if got ~= nil then wanted = got and true or false end

    Say("combat logging " .. (wanted and "on." or "off."))
    return wanted
end

--[[ Framerate and latency together, because they are the two numbers somebody
     wants at the same moment and the client shows one of them. ]]--
--[==[ **The battleground window, which the client will not open for you.**

     The group finder has a binding -- `TOGGLEGROUPFINDER`, which is why `/lfg`
     is a line in the shipped list and not a function. There is no equivalent
     for battlegrounds: all two hundred and thirty-five of this client's
     bindings were read, and the only two that mention them are the battlefield
     *minimap* and the *scoreboard*. Neither queues you for anything.

     `BattlefieldFrame` is the window, and `ShowUIPanel` is how the client opens
     it -- but the client only does that from the battlemaster's gossip, and the
     list of battlegrounds inside it is sent by the server at the same moment.
     Opened cold it is a real window with nothing in it, which reads as broken.

     So the emptiness is checked for and said out loud, rather than shown. If
     the server has sent nothing, the honest answer is that you have to go and
     talk to a battlemaster, not a blank frame you are left to interpret. ]==]
function OB.ToggleBattlegrounds()
    local frame = getglobal("BattlefieldFrame")

    if not frame then
        Say("this client has no battleground window.")
        return false
    end

    if frame:IsVisible() then
        if type(HideUIPanel) == "function" then HideUIPanel(frame) else frame:Hide() end
        return true
    end

    --[[ How many battlegrounds the server has told us about. Zero means the
         conversation that fills it has not happened. ]]--
    local known = 0
    if type(GetNumBattlefields) == "function" then
        known = GetNumBattlefields() or 0
    elseif type(GetBattlefieldInfo) == "function" then
        known = GetBattlefieldInfo() and 1 or 0
    end

    if known < 1 then
        Say("the server has not sent a battleground list yet -- talk to a "
                .. "battlemaster once and this will open it after that.")
        return false
    end

    if type(ShowUIPanel) == "function" then ShowUIPanel(frame) else frame:Show() end

    return true
end


function OB.PrintFramerate()
    local _, _, latency = GetNetStats()

    Say(string.format("%.1f fps, %d ms.", GetFramerate() or 0, latency or 0))

    if type(ToggleFramerate) == "function" then ToggleFramerate() end

    return true
end

-- ---------------------------------------------------------------------------
-- what a command can be bound to
-- ---------------------------------------------------------------------------

--[[ **What this addon adds that the client has no binding for.** Everything
     else a command can be bound to is a binding, run through the table above. ]]--
OB.commandBuiltins = {
    { id = "fps", label = "Framerate And Latency", run = OB.PrintFramerate },
    { id = "hud", label = "Hide The Interface", run = OB.ToggleHud },
    { id = "combatlog", label = "Combat Logging", run = OB.ToggleCombatLog },
    { id = "battlegrounds", label = "The Battleground Finder",
      run = OB.ToggleBattlegrounds },
}


--[[ A builtin is written `@fps`, which is not decoration: `@` cannot appear in
     a binding command name, so one namespace holds both kinds and no binding a
     server invents can ever collide with one of ours. ]]--
function OB.CommandBuiltin(action)
    if not action or string.sub(action, 1, 1) ~= "@" then return nil end

    local id = string.sub(action, 2)

    for i = 1, table.getn(OB.commandBuiltins) do
        if OB.commandBuiltins[i].id == id then return OB.commandBuiltins[i] end
    end

    return nil
end

--[[ What a command does, in the words the panel and `/eq cmd` both use. ]]--
function OB.CommandLabel(action)
    local builtin = OB.CommandBuiltin(action)
    if builtin then return builtin.label end

    return OB.BindingLabel(action)
end

function OB.RunCommandAction(action)
    local builtin = OB.CommandBuiltin(action)
    if builtin then return builtin.run() end

    if OB.RunBinding(action) then return true end

    Say("'" .. OB.BindingLabel(action)
            .. "' cannot be run from a command on this client.")

    return false
end

-- ---------------------------------------------------------------------------
-- the commands, and taking a word without stealing it
-- ---------------------------------------------------------------------------

--[[ **A fixed list, not a list somebody edits.**

     There was a compose box on the Chat page and an account store behind it, so
     any binding could be bound to any word you liked. It is gone: the words
     below are the words, and the panel has one fewer section for it.

     The machinery it needed is gone with it -- no store, no seeding, no
     re-binding, no "which of these did you delete". What is left is a table and
     a loop, which is what this always wanted to be. ]]--
local SHIPPED = {
    { "fps", "@fps" },
    { "hud", "@hud" },
    { "combatlog", "@combatlog" },
    { "cl", "@combatlog" },
    { "walk", "TOGGLERUN" },
    { "sit", "SITORSTAND" },
    { "sheath", "TOGGLESHEATH" },
    { "autorun", "TOGGLEAUTORUN" },

    --[[ `TOGGLEGROUPFINDER` is this client's own binding for the group finder,
         so `/lfg` is the binding rather than a function that reaches for a
         frame by name. The finder is a protected addon here -- Turtle_GroupUI
         ships as 257 bytes of encrypted stub -- so its frames cannot be named
         from outside, and the binding is the only supported way in. ]]--
    { "lfg", "TOGGLEGROUPFINDER" },

    --[[ No binding exists for this one. See `OB.ToggleBattlegrounds`. ]]--
    { "lfbg", "@battlegrounds" },
}

--[[ **`SlashCmdList` is flat and first come wins.**

     Nothing owns a word: writing `SLASH_FOO1 = "/sit"` takes `/sit` from
     whoever had it, silently, and they find out when a player complains. So
     every name is checked against the same walk the client does before it is
     taken, and one that belongs to somebody else is left alone and said out
     loud rather than stolen.

     Ours are recognisable by prefix and do not count -- registering twice in one
     session is this function running twice, not a collision. ]]--
local PREFIX = "EQOBCMD_"

function OB.SlashOwner(word, skipOurs)
    if not word or word == "" then return nil end

    word = "/" .. string.lower(word)

    for key in pairs(SlashCmdList) do
        local ours = string.sub(key, 1, string.len(PREFIX)) == PREFIX

        if not (skipOurs and ours) then
            for i = 1, 8 do
                local slot = getglobal("SLASH_" .. key .. i)
                if not slot then break end

                if string.lower(slot) == word then return key end
            end
        end
    end

    return nil
end

function OB.SlashTakenByOther(word)
    return OB.SlashOwner(word, true)
end

--[[ Every command, registered, and every word somebody else already answers to,
     left alone. Said once with the whole list rather than once per word, because
     three lines about channels you did not know you had is noise and one is
     information. ]]--
function OB.RegisterCommands()
    local taken = {}

    for i = 1, table.getn(SHIPPED) do
        local name, action = SHIPPED[i][1], SHIPPED[i][2]

        if OB.SlashTakenByOther(name) then
            table.insert(taken, name)
        else
            local key = PREFIX .. string.upper(name)

            SlashCmdList[key] = function() OB.RunCommandAction(action) end
            setglobal("SLASH_" .. key .. "1", "/" .. name)
        end
    end

    if table.getn(taken) > 0 then
        Say("left /" .. table.concat(taken, ", /")
                .. " alone -- something else already answers to "
                .. (table.getn(taken) == 1 and "it." or "those."))
    end

    return table.getn(SHIPPED) - table.getn(taken)
end

--[[ What there is, for somebody who wants to know without reading the source. ]]--
function OB.PrintCommands()
    Say("chat commands:")

    for i = 1, table.getn(SHIPPED) do
        Say("  /" .. SHIPPED[i][1] .. " -- "
                .. OB.CommandLabel(SHIPPED[i][2]))
    end

    return table.getn(SHIPPED)
end
