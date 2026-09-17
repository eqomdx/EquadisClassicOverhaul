--[[ Equadis' Classic Overhaul :: profile codes

  **Every setting in a profile, as one string you can paste to somebody.**

  A profile is a plain table of strings, numbers, booleans and more tables, so
  sharing one is a serialisation problem and nothing more interesting than that.

  **It is not `loadstring`, and that is the whole of the design.**

  The obvious way to write this is to serialise the table as Lua source and read
  it back with `loadstring`. Every addon that has ever done that has shipped a
  remote code execution bug: a profile code is text somebody else wrote, pasted
  by a person who cannot read it, and `loadstring` will run whatever is in it --
  `DeleteCharacter`, a mail script, anything the client exposes. The string
  being long and opaque is exactly why nobody would notice.

  So there is a parser below that accepts a grammar of data and nothing else. It
  cannot call a function because it has no way to express one. A hostile code
  can at worst be rejected, or set your settings to nonsense you can undo by
  switching profile.

  **Base64 over the wire.** The serialised form is readable text with commas and
  braces, which does not survive being pasted into a chat box and back out. It
  is encoded to a single run of letters, digits and two punctuation marks: one
  token, selectable with a triple-click, that no chat filter will reflow.

  **A checksum, because the failure being guarded is truncation.** Copying a
  four thousand character string out of an edit box is the part people get
  wrong. A code that lost its tail is still valid base64 and still parses to a
  table -- a *smaller* table, quietly missing the settings that were on the end.
  The sum catches that and refuses, which is the difference between "that code
  is broken" and "why is my minimap wrong three days later".
]]--

local OB = EquadisClassicOverhaul

local function Say(msg) OB.Print(msg, "Profiles") end

local VERSION = "ECO1"

--[[ The edit box's cap. Room for a profile several times the size of the one
     this addon ships, because the alternative to a generous number is a code
     that arrives one character short and reads as corrupt. ]]--
local CODE_LETTERS = 131072

--[[ Sixty-four characters that survive a chat box. The standard alphabet's `+`
     and `/` do not -- `/` opens a slash command if the paste lands at the start
     of a line -- so this uses the URL-safe pair. No padding: the length is
     recoverable from the data and `=` is one more character to lose. ]]--
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local B64INDEX
local function b64index()
    if B64INDEX then return B64INDEX end

    B64INDEX = {}
    for i = 1, 64 do
        B64INDEX[string.sub(B64, i, i)] = i - 1
    end

    return B64INDEX
end

--[[ Three bytes in, four characters out. Written with `math.floor` and `mod`
     rather than bit operations because 1.12's Lua has no bit library and the
     arithmetic is the same thing spelled longer. ]]--
function OB.Base64Encode(text)
    local out, n = {}, string.len(text)
    local i = 1

    while i <= n do
        local a = string.byte(text, i) or 0
        local b = string.byte(text, i + 1)
        local c = string.byte(text, i + 2)

        local packed = (a * 65536) + ((b or 0) * 256) + (c or 0)

        local c1 = math.floor(packed / 262144)
        local c2 = math.floor(mod(packed / 4096, 64))
        local c3 = math.floor(mod(packed / 64, 64))
        local c4 = math.floor(mod(packed, 64))

        table.insert(out, string.sub(B64, c1 + 1, c1 + 1))
        table.insert(out, string.sub(B64, c2 + 1, c2 + 1))

        --[[ Only as many characters as there were bytes. Two bytes make three
             characters and one makes two; emitting the fourth would decode back
             to a trailing zero byte that was never there. ]]--
        if b then table.insert(out, string.sub(B64, c3 + 1, c3 + 1)) end
        if c then table.insert(out, string.sub(B64, c4 + 1, c4 + 1)) end

        i = i + 3
    end

    return table.concat(out)
end

function OB.Base64Decode(code)
    local index = b64index()
    local out, n = {}, string.len(code)
    local i = 1

    while i <= n do
        local c1 = index[string.sub(code, i, i)]
        local c2 = index[string.sub(code, i + 1, i + 1)]
        local c3 = index[string.sub(code, i + 2, i + 2)]
        local c4 = index[string.sub(code, i + 3, i + 3)]

        --[[ A character outside the alphabet means this is not one of ours --
             a half-copied code, or something else entirely. Refused rather than
             skipped, because skipping it would decode to a table that is
             plausible and wrong. ]]--
        if not c1 or not c2 then return nil end
        if string.sub(code, i + 2, i + 2) ~= "" and not c3 then return nil end
        if string.sub(code, i + 3, i + 3) ~= "" and not c4 then return nil end

        local packed = (c1 * 262144) + (c2 * 4096) + ((c3 or 0) * 64) + (c4 or 0)

        table.insert(out, string.char(math.floor(packed / 65536)))
        if c3 then table.insert(out, string.char(math.floor(mod(packed / 256, 256)))) end
        if c4 then table.insert(out, string.char(math.floor(mod(packed, 256)))) end

        i = i + 4
    end

    return table.concat(out)
end

--[[ Order-independent, because `pairs` does not promise one and the same
     profile must produce the same sum on the machine that sends it and the one
     that receives it. Position is folded in per character so that two codes
     differing only by a transposition still differ. ]]--
function OB.ProfileChecksum(text)
    local sum = 5381

    for i = 1, string.len(text) do
        sum = mod((sum * 33) + string.byte(text, i), 16777216)
    end

    return sum
end

-- ---------------------------------------------------------------------------
-- writing
-- ---------------------------------------------------------------------------

--[==[ **The grammar.**

     A value is one of five things, each introduced by a letter so the reader
     never has to guess a type back from its spelling -- `1` the number and
     `"1"` the string are different settings and a format that cannot tell them
     apart will eventually put a string where a slider goes.

         b1 / b0     boolean
         n<number>;  number
         s<len>:<..> string, length-prefixed so it needs no escaping
         t<..>e      table
         z           nil, only ever as a table value that was explicitly false

     Strings carry their length rather than a terminator, which is what makes
     the parser total: it never has to look for a closing quote that a hostile
     code can decline to provide. ]==]
local function writeValue(value, out)
    local kind = type(value)

    if kind == "boolean" then
        table.insert(out, value and "b1" or "b0")

    elseif kind == "number" then
        --[[ `%.14g` keeps a double's meaningful digits without the trailing
             noise `%f` produces. A colour of 0.82 must come back as 0.82. ]]--
        table.insert(out, "n" .. string.format("%.14g", value) .. ";")

    elseif kind == "string" then
        table.insert(out, "s" .. string.len(value) .. ":" .. value)

    elseif kind == "table" then
        table.insert(out, "t")

        --[[ Keys are written as values, so a numeric key stays numeric. The
             action bars index windows by number and a profile that came back
             with "1" instead of 1 would build an empty one. ]]--
        for k, v in pairs(value) do
            if type(v) ~= "function" and type(v) ~= "userdata" then
                writeValue(k, out)
                writeValue(v, out)
            end
        end

        table.insert(out, "e")

    else
        table.insert(out, "z")
    end
end

--[[ The current profile as a code. Returns the string, or nil if there is no
     profile to write -- which happens only before the first login has
     finished. ]]--
--[==[ **A code carries what differs from the defaults, and nothing else.**

     Every setting went in, defaults included, so a code was around twenty
     thousand characters -- four hundred lines of chat, and past what several
     places will let somebody paste at all. Almost all of it said "this is the
     same as everybody's".

     Safe because of how a profile is loaded, and only because of that:
     `LoadConfig` copies the defaults and merges the saved profile on top, so a
     key that is absent gets the default. That is the same guarantee the
     migrations rely on, and it is asserted rather than assumed below.

     **The format is untouched.** Same version, same checksum, same encoding --
     an older code still imports, because it is a superset of a newer one. What
     changed is what goes in, not how it is written.

     Three things are kept whatever they are:

     *`schema`*, always. Without it an imported profile reads as schema 1 and
     every migration runs again over settings that have already been through
     them -- and several of those flip booleans.

     *A key the defaults have never heard of*, because there is nothing to
     compare it against and dropping it would be losing it.

     *A table of numbers, whole or not at all.* A colour is four numbers that
     mean one thing; carrying the two that differ and leaving the rest to the
     defaults is how you get a green somebody never chose. ]==]
local function isNumberList(t)
    local n = 0

    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        n = n + 1
    end

    return n > 0
end

local function sameValue(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end

    for k, v in pairs(a) do
        if not sameValue(v, b[k]) then return false end
    end

    for k in pairs(b) do
        if a[k] == nil then return false end
    end

    return true
end

local KEEP_ALWAYS = { schema = true }

function OB.PruneToDefaults(value, defaults)
    if type(value) ~= "table" or type(defaults) ~= "table" then return value end

    local out = {}
    local any = false

    for k, v in pairs(value) do
        local d = defaults[k]

        if KEEP_ALWAYS[k] or d == nil then
            out[k] = v
            any = true

        elseif type(v) == "table" and type(d) == "table" then
            if isNumberList(v) or isNumberList(d) then
                --[[ Whole or not at all: half a colour is a colour nobody
                     picked. ]]--
                if not sameValue(v, d) then
                    out[k] = v
                    any = true
                end
            else
                local inner = OB.PruneToDefaults(v, d)

                if inner ~= nil then
                    out[k] = inner
                    any = true
                end
            end

        elseif v ~= d then
            out[k] = v
            any = true
        end
    end

    if not any then return nil end

    return out
end

function OB.ExportProfileCode()
    if not OB.profile then return nil end

    local out = {}
    writeValue(OB.PruneToDefaults(OB.profile, OB.defaults) or {}, out)

    local body = table.concat(out)

    return VERSION .. ":" .. OB.ProfileChecksum(body) .. ":"
            .. OB.Base64Encode(body)
end

-- ---------------------------------------------------------------------------
-- reading
-- ---------------------------------------------------------------------------

--[[ Reads one value and answers where it ended. Every branch either consumes a
     known number of characters or fails; there is no branch that scans forward
     hoping to find something, which is what keeps a malformed code from
     becoming a hang. ]]--
local function readValue(text, pos, depth)
    if depth > 32 then return nil end

    local tag = string.sub(text, pos, pos)
    if tag == "" then return nil end

    if tag == "b" then
        local v = string.sub(text, pos + 1, pos + 1)
        if v == "1" then return true, pos + 2 end
        if v == "0" then return false, pos + 2 end
        return nil

    elseif tag == "z" then
        return nil, pos + 1, true

    elseif tag == "n" then
        local stop = string.find(text, ";", pos + 1, true)
        if not stop then return nil end

        local number = tonumber(string.sub(text, pos + 1, stop - 1))
        if not number then return nil end

        return number, stop + 1

    elseif tag == "s" then
        local stop = string.find(text, ":", pos + 1, true)
        if not stop then return nil end

        local length = tonumber(string.sub(text, pos + 1, stop - 1))
        if not length or length < 0 then return nil end

        local value = string.sub(text, stop + 1, stop + length)
        if string.len(value) ~= length then return nil end

        return value, stop + 1 + length

    elseif tag == "t" then
        local out = {}
        local at = pos + 1

        while true do
            if string.sub(text, at, at) == "e" then return out, at + 1 end
            if at > string.len(text) then return nil end

            local key, nextAt = readValue(text, at, depth + 1)
            if nextAt == nil then return nil end

            --[[ A nil key is not an error in the writer's grammar but cannot be
                 stored, so it and its value are read and dropped rather than
                 aborting an otherwise good code. ]]--
            local value, afterValue = readValue(text, nextAt, depth + 1)
            if afterValue == nil then return nil end

            if key ~= nil then out[key] = value end
            at = afterValue
        end
    end

    return nil
end

--[[ A code to a table, or nil and a sentence saying which of the four ways it
     was wrong. The sentence is the point: "that is not a valid code" tells
     somebody nothing about whether to re-copy it or ask for a new one. ]]--
function OB.DecodeProfileCode(code)
    if type(code) ~= "string" then return nil, "there is no code there." end

    code = string.gsub(code, "%s", "")
    if code == "" then return nil, "there is no code there." end

    local _, _, version, sum, payload =
            string.find(code, "^(%a+%d*):(%d+):(.+)$")

    if not version then
        return nil, "that does not look like a profile code."
    end

    if version ~= VERSION then
        return nil, "that code was made by a different version of this addon."
    end

    local body = OB.Base64Decode(payload)
    if not body then return nil, "that code has characters in it that are not "
            .. "part of one -- it was probably copied with something else." end

    if OB.ProfileChecksum(body) ~= tonumber(sum) then
        return nil, "that code is incomplete -- the usual cause is copying "
                .. "only part of it."
    end

    local value, at = readValue(body, 1, 0)

    if type(value) ~= "table" then
        return nil, "that code did not contain a profile."
    end

    if at ~= string.len(body) + 1 then
        return nil, "that code has more in it than a profile does."
    end

    return value
end

--[==[ **Applied over the current profile, and a reload follows.**

     Written into the profile the character is already using rather than made
     into a new one. Somebody pasting a code wants their interface to look like
     that; making "Imported 3" and leaving them to find the profile switcher is
     the same work with an extra step and a worse name.

     The old contents are kept under a fixed name first. An import is one paste
     and replaces every setting at once, which is the shape of action that
     wants an undo more than most. ]==]
function OB.ImportProfileCode(code)
    local profile, why = OB.DecodeProfileCode(code)

    if not profile then
        Say(why or "that code could not be read.")
        return false
    end

    if not EquadisClassicOverhaulDB or not OB.profileName then
        Say("profiles are not ready yet -- try again once you are logged in.")
        return false
    end

    EquadisClassicOverhaulDB.profiles["Before Import"] =
            OB.DeepCopy(EquadisClassicOverhaulDB.profiles[OB.profileName])

    EquadisClassicOverhaulDB.profiles[OB.profileName] = profile

    Say("imported into '" .. OB.profileName .. "'. The profile it replaced is "
            .. "kept as 'Before Import'.")

    if type(ReloadUI) == "function" then ReloadUI() end

    return true
end


-- ---------------------------------------------------------------------------
-- getting it in and out of the game
-- ---------------------------------------------------------------------------

--[==[ **A box, because a chat line cannot be selected.**

     `AddMessage` can print six hundred characters and there is no way to get
     them back out -- 1.12's chat frame is not selectable text. So the code goes
     into an `EditBox`, which is, and it is selected on open so that the paste
     is one keystroke rather than a drag across four wrapped lines.

     One box for both directions. Opening it with a code shows yours ready to
     copy; clearing it and pasting somebody else's and pressing Enter reads
     theirs. Two windows for one string would be two windows to explain. ]==]
function OB.ProfileCodeFrame()
    if OB.profileCodeFrame then return OB.profileCodeFrame end

    local frame = CreateFrame("Frame", "EquadisClassicOverhaulProfileCode",
            UIParent)
    frame:SetWidth(460)
    frame:SetHeight(150)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    if OB.SkinWindow then OB.SkinWindow(frame, 0.97) end

    frame:SetScript("OnMouseDown", function()
        if arg1 == "LeftButton" then this:StartMoving() end
    end)
    frame:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)

    frame.title = OB.NewText(frame, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -12)
    frame.title:SetText("Profile Code")

    frame.hint = OB.NewText(frame, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOP", frame.title, "BOTTOM", 0, -6)
    frame.hint:SetWidth(420)
    frame.hint:SetText("Ctrl-C to copy. To use somebody else's, select all, "
            .. "paste theirs, and press Enter.")

    --[[ A single-line box holding six hundred characters: it scrolls rather
         than wraps, which is what makes select-all-and-copy reliable. A
         multi-line box would show more of it and paste back with newlines in
         the middle, which is the one thing the format cannot survive. ]]--
    frame.box = CreateFrame("EditBox", "EquadisClassicOverhaulProfileCodeBox",
            frame, "InputBoxTemplate")
    frame.box:SetWidth(410)
    frame.box:SetHeight(22)
    frame.box:SetPoint("TOP", frame.hint, "BOTTOM", 0, -14)
    frame.box:SetAutoFocus(false)

    --[==[ **Long enough for a full profile, which eight thousand was not.**

         The default cap is a couple of hundred characters and would silently
         truncate a pasted code into one that fails the checksum -- a correct
         refusal for the wrong reason. That much was known when this was
         written. What was not is how long a code actually is: a profile with
         every module's settings in it exports to around twenty thousand
         characters, so the cap put here to prevent truncation was itself
         truncating every code this addon produced.

         Measured rather than guessed now -- the suite exports a real profile
         and checks it fits. ]==]
    frame.box:SetMaxLetters(CODE_LETTERS)

    frame.box:SetScript("OnEscapePressed", function() this:ClearFocus() end)

    frame.box:SetScript("OnEnterPressed", function()
        local text = this:GetText()
        this:ClearFocus()

        if text and text ~= "" and text ~= OB.lastShownProfileCode then
            EquadisClassicOverhaul.ImportProfileCode(text)
        end
    end)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    if UISpecialFrames then
        table.insert(UISpecialFrames, "EquadisClassicOverhaulProfileCode")
    end

    OB.profileCodeFrame = frame
    return frame
end

function OB.ShowProfileCode()
    local code = OB.ExportProfileCode()

    if not code then
        Say("there is no profile to export yet.")
        return false
    end

    local frame = OB.ProfileCodeFrame()

    --[[ Remembered so that pressing Enter on an unchanged box does not import
         the profile over itself -- harmless, but it reloads the interface and
         looks like something went wrong. ]]--
    OB.lastShownProfileCode = code

    frame.box:SetText(code)
    frame:Show()
    frame.box:SetFocus()
    frame.box:HighlightText()

    return true
end

--[[ Opened empty, for pasting into. ]]--
function OB.ShowProfileImport()
    local frame = OB.ProfileCodeFrame()

    OB.lastShownProfileCode = nil

    frame.box:SetText("")
    frame:Show()
    frame.box:SetFocus()

    return true
end
