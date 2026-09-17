--[[ Equadis' Classic Overhaul :: chat

  Ported from Equadis' Chat Tweaks, which is Prat-V, which is Prat -- by Curney
  and Krtek, inspired by idChat2. See NOTICE; the line-level work in these
  behaviours is theirs.

  **What is not ported is the whole reason this is small.** Prat ships nine Ace2
  libraries -- AceAddon, AceDB, AceConsole, AceEvent, AceHook, AceLocale,
  AceModuleCore, AceOO, AceTab -- and every one of them does a job this addon
  already does: a module registry, a profile store, an event map, a slash prompt.
  Nine thousand three hundred lines of it, replaced rather than carried.

  **And the settings become an interface for free.** Prat is usually described as
  configured "through chat", which is not quite right: each module *declares* its
  settings as a table, and Ace2 rendered that as chat commands only because Ace2
  had no panel. The declarations were always there. Re-declaring them in this
  addon's own options format is what turns them into a page -- no settings UI is
  written here, the same generator that builds every other tab builds this one.

  Timestamps first, because it is self-contained, has real settings and touches
  the one thing every other chat module will also need: a hook on AddMessage.
]]--

local OB = EquadisClassicOverhaul

--[[ **Breadcrumbs, because the client will not say where a file died.**

     `/console scriptErrors 1` does nothing on this client, so a file that
     throws while loading takes its module with it and leaves no message. What
     the client *does* do is carry on with the next file -- so anything this one
     wrote before it died survives, and the last number written says how far it
     got.

     nil means the file never compiled: a syntax error, which on 1.12 means
     something Lua 5.0 rejects and 5.1 accepts. Any number means it started, and
     which number says where it stopped. `/eq doctor` reports it. ]]--
OB.chatLoad = 10

-- ---------------------------------------------------------------------------
-- timestamps
-- ---------------------------------------------------------------------------

--[==[ **A setting per window, shown only for the windows you have.**

     Three lists on this page are one row repeated per index -- a timestamp
     switch per chat window, a search box per chat window, and a mention switch
     per numbered channel. Twenty-four rows, and for almost everybody twenty of
     them are about something that does not exist: 1.12 builds seven chat frames
     and docks two, and nobody is in ten custom channels.

     Behaving instead of hiding was the alternative and it is worse. The
     settings are all still there and still saved; make a third window and its
     row comes back holding whatever it held. What goes is the offer to
     configure a thing you do not have.

     `dependsOn` rather than `greyWhen`, which is the distinction the panel
     already draws: a greyed row still means something and is not in charge,
     while a row for a window nobody made means nothing at all. ]==]

--[[ The trailing number off `stamp.3` or `popupChannel.7`. 1.12's Lua has no
     `string.match`, so the capture comes back through `string.find`. ]]--
local function rowIndex(w)
    if not w or not w.key then return nil end

    local _, _, digits = string.find(w.key, "(%d+)$")

    return tonumber(digits)
end

OB.predicates = OB.predicates or {}

OB.predicates.chat_window_live = function(w)
    local index = rowIndex(w)
    if not index then return true end

    --[[ The first two are the client's own -- General and the combat log -- and
         are docked from a fresh install, so they are never in question. ]]--
    if index <= 2 then return true end

    local frame = getglobal("ChatFrame" .. index)
    if not frame then return false end

    --[[ Docked *or* shown. An undocked window somebody has dragged off on its
         own is still a window they made, and asking only about the dock would
         take its settings away for having been moved. ]]--
    if frame.isDocked then return true end
    if frame.IsShown and frame:IsShown() then return true end

    return false
end

OB.predicates.chat_channel_joined = function(w)
    local index = rowIndex(w)
    if not index then return true end

    --[[ Answering yes when the call is missing, because a panel that hides rows
         on a client it cannot ask is worse than one that shows a few too
         many. ]]--
    if type(GetChannelName) ~= "function" then return true end

    local _, name = GetChannelName(index)

    return (name and name ~= "") and true or false
end



--[[ A formatted time, with the padding the client insists on taken back off.

     **Only a leading zero, and only at the front.** "09:05" becomes "9:05" and
     "10:05" is left alone -- a blunter substitution would turn "10:05" into
     "1:5", which is not a time. `stripAll` unpads the later fields the same way,
     which is what an unpadded shape asks for: `h:m` at five past nine is "9:5",
     because that is what the notation says. ]]--
function OB.FormatTime(spec, when)
    local text = when and date(spec[1], when) or date(spec[1])
    if not text then return "" end

    if spec.strip then
        text = string.gsub(text, "^0", "")
        if spec.stripAll then text = string.gsub(text, ":0(%d)", ":%1") end
    end

    return text
end




--[[ **Three questions instead of one list of twelve.**

     Twelve entries was every combination of three independent choices written
     out, which is what a list becomes when the things behind it are orthogonal:
     the reader has to find their answer in a set rather than give it. Worse,
     several of the twelve differed only after ten in the morning, so the list
     could not be read at all without knowing what time it was.

     The three questions are: twelve-hour or twenty-four, is there a meridiem,
     and how much of the clock with how much padding. AM/PM is greyed rather
     than hidden when the answer is twenty-four hours, because it is still your
     answer -- it just has nothing to attach to. ]]--
OB.timeShapes = { "h:m", "h:m:s", "hh:mm", "hh:mm:ss" }



--[[ Whose clock the timestamp reads from. The server's needs a drift correction
     to be worth anything, which is why it is a choice rather than the
     default. ]]--
OB.timeSources = { "Local", "Server" }

--[[ The order matters: the index is what is stored, so appending is safe and
     reordering silently changes everybody's setting. Same rule as the texture
     and font lists in core.lua. ]]--
OB.chatJustify = { "LEFT", "CENTER", "RIGHT" }

--[[ What a numbered channel is reduced to. `[1. General]` becomes `[1]`, or
     `[General]`, or `[G]` -- all three are in use and none is obviously right,
     which is what makes it a setting rather than a decision. ]]--
--[[ What goes around a player's name. Prat's, and the list is the whole of the
     decision: square is the client's, angled is quieter, none is quietest. ]]--
OB.nameBrackets = { "[Square]", "<Angled>", "None" }

--[[ How a name is coloured.

     Class is the one people want. Random is Prat's answer to the rest: hash the
     name into a colour, so the same person is the same colour every time even
     when nobody knows what they are. It is not pretty and it is genuinely
     useful in a channel full of strangers. ]]--
--[[ **Declared here, above the module, and that is not tidiness.**

     The options table is built when `RegisterModule` runs, so a list referenced
     from a row has to exist by then. This one was declared beside the code that
     uses it, four-fifths of the way down the file -- so the row was handed nil,
     the dropdown built no buttons, and it opened onto nothing.

     Two wire formats exist because two addons invented one each. The names are
     theirs, and they are what the people reading you have to be able to
     decode. ]]--
OB.linkFormats = { "ChatLink", "ChatManager" }

--[[ Where the box you type into sits. The client puts it under the chat frame;
     above is the other answer, and there is no third.
     stamps the rows after it; a column marker moves them to the right-hand
     column until the next section. Neither is a row. ]]--
OB.chatOptions = {
        --[[ **General: the window and the box you type into.**

             Windows and Typing were two sections of four rows each asking about
             the same rectangle -- how it looks and how you put things in it --
             and neither was long enough to be worth a trip. One section, first,
             because it is what somebody opening this page came for. ]]--
        { "General", "__s_general", "section", "general" },

        --[[ Behind a switch, because the client owns these frames and this is
             the part that reaches in and changes them. Off, everything below is
             left exactly as the client and any other addon set it. ]]--
        { "Restyle Chat", "restyle", "boolean" },

        --[[ **The chat windows own font, which every other subsystem takes from
             the shared look.**

             Chat is the one place a different face genuinely earns its keep:
             these windows are read as prose rather than glanced at as numbers,
             and the client's own Friz Quadrata is a headline face doing a body
             job. So the row is here rather than in the five-row appearance
             block, which chat does not carry.

             It still goes through `OB.Look`, so leaving it alone means leaving
             it wherever the profile's font is -- share unless you say
             otherwise, the same rule as everywhere else. ]]--
        { "Font", "font", OB.fonts, 200,
          nil, nil, nil, nil, "!restyle" },

        { "Font Outline", "fontOutline", OB.fontOutlines, 150,
          nil, nil, nil, nil, "!restyle" },

        { "Font Size", "fontSize", "slider", 6, 24, 1,
          nil, nil, "!restyle" },

        --[[ **The whole window, scaled.** Font size changes the text and leaves
             the frame the size it was; this changes both, which is what
             somebody who wants a smaller chat window is asking for. ]]--
        { "Scale", "scale", "slider", 50, 150, 5, 0.01,
          nil, "!restyle" },
        { "Text Alignment", "justify", OB.chatJustify, 140,
          nil, nil, nil, nil, "!restyle" },

        --[[ **One switch for all seven**, which is what it always was in
             practice: nobody wants window one to fade and window three not to.
             It was seven checkboxes because Prat had seven, and seven rows for a
             decision nobody makes per window is six rows of noise. ]]--
        { "Enable Chat Fade", "fade", "boolean",
          nil, nil, nil, nil, nil, "!restyle" },

        { "Fade After (Seconds)", "fadeAfter", "slider", 1, 60, 1,
          nil, nil, "!restyle,!fade" },

        --[[ **The box you type into**, which is the one part of the chat window
             that sits on top of the game rather than beside it -- and the one
             part still wearing 2004 gold filigree while everything else this
             addon draws is a flat panel with a border it chose. ]]--
        { "Editbox", "__s_editbox", "section", "editbox" },

        { "Remove Editbox Border", "editBorder", "boolean" },
        { "Editbox Color", "editColor", "color", true,
          nil, nil, nil, nil, "!editBorder" },
        { "Editbox Width", "editWidth", "slider", 180, 600, 10 },
        { "Editbox Height", "editHeight", "slider", 20, 36, 1 },

        --[[ Locked is a state rather than a mode, unlike the bars and the
             popup: the box is only on screen while you are typing into it, so a
             draggable one is never in the way of something else. Unlocked, a
             left drag moves it and a right drag resizes it. ]]--
        { "Lock Editbox", "editLocked", "boolean" },

        { "Reset Position & Size", "__a_editreset", "action",
          function() OB.modules.chat:ResetEditBox() end },

        --[[ The edit box, which is the other half of the same rectangle. ]]--

        { "Timestamps", "__s_stamps", "section", "stamps" },

        { "Chat Window 1", "stamp.1", "boolean",
          nil, nil, nil, nil, "@chat_window_live" },
        { "Chat Window 2", "stamp.2", "boolean",
          nil, nil, nil, nil, "@chat_window_live" },
        { "Chat Window 3", "stamp.3", "boolean",
          nil, nil, nil, nil, "@chat_window_live" },
        { "Chat Window 4", "stamp.4", "boolean",
          nil, nil, nil, nil, "@chat_window_live" },
        { "Chat Window 5", "stamp.5", "boolean",
          nil, nil, nil, nil, "@chat_window_live" },
        { "Chat Window 6", "stamp.6", "boolean",
          nil, nil, nil, nil, "@chat_window_live" },
        { "Chat Window 7", "stamp.7", "boolean",
          nil, nil, nil, nil, "@chat_window_live" },

        --[[ Whose clock first, then what it looks like -- the source is the
             bigger decision and the format reads as a refinement of it. ]]--
        { "Time", "timeSource", OB.timeSources, 140 },
        { "12h Format", "hour12", "boolean" },

        --[[ Greyed rather than hidden on a twenty-four hour clock, because it is
             still your answer -- it just has nothing to attach to. "14:36 PM" is
             not a time. ]]--
        { "Show AM/PM", "meridiem", "boolean",
          nil, nil, nil, nil, nil, "!hour12" },

        { "Format", "timeShape", OB.timeShapes, 140 },

        --[[ The same three every other wrappable thing on this page offers.
             None by default, because a timestamp is already set apart by being
             a number at the start of the line -- brackets are for somebody who
             wants it set further apart still. ]]--
        { "Surround Timestamp With", "stampBrackets", OB.nameBrackets, 160 },

        { "Color Timestamp", "colorStamp", "boolean" },
        { "Timestamp Color", "stampColor", "color", true,
          nil, nil, nil, nil, "!colorStamp" },

        { "Channels", "__s_channels", "section", "channels" },
        { "Separate Raid And Officer Channels", "separate", "boolean" },

        { "Rename Channels", "shorten", "boolean" },
        { "Show Colon After Name", "colon", "boolean",
          nil, nil, nil, nil, nil, "!shorten" },

        --[[ Separate from the switch above, because it is a different mechanism
             with a different cost: this one runs on every message. Numbered
             channels lose their list position and their zone -- "1. General -
             Stormwind" becomes "General", which is the part that was ever worth
             reading. ]]--
        { "Shorten Numbered Channels", "shortenNumbered", "boolean" },

        --[[ The same three the player-name and link rows offer, from the same
             list, because "how is a thing wrapped" is one question and answering
             it three ways on one page is three things to learn. ]]--
        { "Surround Channel Names With", "channelBrackets", OB.nameBrackets, 160,
          nil, nil, nil, nil, "!shorten" },

        --[[ **The ten boxes go in their own column.**

             They are one thing typed ten times, and left in the flow they filled
             the page and pushed the switches that govern them into column two --
             so the reader met "Whisper From" above "Shorten Numbered Channels"
             and the two halves of the section read as unrelated. Decisions on
             the left, the typing on the right. ]]--
        { "", "__c_names", "column", 2 },

        --[[ **Twenty characters, not eight.** Eight was chosen when these were
             abbreviations -- "G", "O", "P" -- and it is a rename box: somebody
             calling their guild channel by its name has more than eight
             characters of name. The box is wider to match, because a limit you
             cannot see the end of is a limit that reads as a broken keyboard. ]]--
        { "Guild", "shortGuild", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Officer", "shortOfficer", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Party", "shortParty", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Raid", "shortRaid", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Raid Leader", "shortRaidLeader", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Raid Warning", "shortRaidWarning", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Say", "shortSay", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Yell", "shortYell", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Whisper To", "shortWhisper", "text", 110, 20, nil, nil, nil, "!shorten" },
        { "Whisper From", "shortWhisperFrom", "text", 110, 20, nil, nil, nil, "!shorten" },

        { "Links", "__s_links", "section", "links" },

        --[==[ **There is no Make Links Clickable switch.** Links always are.

             1.12 cannot select text out of a chat frame, so the click that opens
             a copy box is the only way a URL gets off the screen without being
             typed out by hand. Off was not a preference; it was the address bar
             taken away.

             The two rows below stay, because how a link is *wrapped* is a real
             question with more than one right answer. ]==]
        --[[ The same three the player-name row offers, from the same list, because
             "how is a thing wrapped" is one question and answering it two ways
             on one page is two things to learn. ]]--
        { "Surround Links With", "urlBrackets", OB.nameBrackets, 160 },
        { "Link Color", "urlColor", "color", true },

        { "Scrolling", "__s_scroll", "section", "scroll" },

        --[==[ **There is no wheel switch.** The wheel scrolls.

             1.12 wires no wheel to a chat frame at all -- the client wants you
             to drag the scrollbar -- so off was not "scroll some other way", it
             was the 2005 behaviour back, and the defaults note said as much:
             the one setting here where off is the surprising state.

             How far a notch goes is still a question, so the two sliders stay
             and are no longer gated on a switch that cannot be off. ]==]
        { "Lines Per Notch", "wheelLines", "slider", 1, 21, 1 },
        { "Lines Per Notch Holding Ctrl", "wheelFast", "slider", 1, 21, 1 },

        { "Lines Kept", "scrollback", "slider", 50, 500, 10 },

        --[[ Only while there is something below to go back to. A button that is
             always there is a button that means nothing when it appears. ]]--
        { "Jump To Newest Button", "jumpButton", "boolean" },

        { "Hide Scroll Arrows", "hideButtons", "boolean" },
        { "Hide Chat Menu Button", "hideMenuButton", "boolean" },

        --[[ **The one setting here that writes what people say to disk**, so it
             is grouped and labelled as what it is rather than tucked in among
             the scroll controls. See the note on `history` in the defaults. ]]--
        { "Keep History Across Reloads", "__s_history", "section", "history" },

        { "Keep History", "history", "boolean" },
        { "Hide Macro Directives", "hideMacroDirectives", "boolean" },
        { "Lines Kept Per Window", "historyLines", "slider", 20, 500, 10,
          nil, nil, "!history" },

        --[[ Shown as a percentage of the line's own colour, because that is
             what it is -- not a brightness in the abstract. ]]--
        { "History Brightness", "historyDim", "slider", 20, 100, 5, 0.01,
          nil, "!history" },

        { "Forget Kept History", "__a_forget", "action",
          function() OB.modules.chat:ForgetHistory() end,
          function() return "Forget Kept History" end },

        --[==[ **Channel colours are always remembered by name.**

             1.12 stores a channel's colour by its number and the numbers move:
             leave one channel and everything below it shifts up, wearing the
             wrong colours. Off did not give anybody a choice, it gave them the
             shuffle -- and the defaults note already said this one is invisible
             when it works, which is the description of something that should
             not be a switch. ]==]

        --[[ On by default, which almost nothing here is. See the note on
             `hideAwayReplies` in the defaults for why this one earns it. ]]--
        { "Hide 'Player Is Away' Replies", "hideAwayReplies", "boolean" },

        { "Player Names", "__s_names", "section", "names" },

        --[[ The master switch stays, and stays first: without it there is no way
             to have timestamps and channel names without coloured names, and
             every row below is dead when it is off. ]]--
        { "Color Player Names", "names", "boolean" },

        { "Known Player Color", "nameKnownColor", "color", true,
          nil, nil, nil, nil, "!names,nameClassColor" },
        { "Unknown Player Color", "nameColor", "color", true,
          nil, nil, nil, nil, "!names" },

        --[[ **Overrides the known swatch rather than replacing it**, which is
             why that row is dimmed rather than hidden when this is on: "your
             colour is still there, something else is winning" is what is
             actually true, and hiding it read as a deletion. ]]--
        { "Color By Class", "nameClassColor", "boolean",
          nil, nil, nil, nil, nil, "!names" },

        { "Display Player Level", "nameLevel", "boolean",
          nil, nil, nil, nil, nil, "!names" },
        { "Show Raid Group", "nameGroup", "boolean",
          nil, nil, nil, nil, nil, "!names" },

        { "Surround Player Names With", "nameBrackets", OB.nameBrackets, 160,
          nil, nil, nil, nil, "!names" },

        --[[ The server strips item links out of any channel it did not make, so
             a link pasted into a guild's own channel arrives as nothing at all.
             Encoded on the way out, decoded on the way in. ]]--
        { "Item Links", "__s_ilinks", "section", "ilinks" },

        { "Send Links Through Custom Channels", "itemLinks", "boolean" },
        { "Surround With", "linkFormat",
          OB.Enum(OB.linkFormats, OB.linkFormats), 160,
          nil, nil, nil, nil, "!itemLinks" },

        --[[ **Mentions: one section, two columns.**

             Highlighting and the popup were two sections asking "what counts as
             somebody talking to you" and then answering it separately. They are
             the quiet and loud halves of a single answer, so they sit side by
             side: the popup on the left, the highlighting on the right, read
             together because they are set together. ]]--
        { "Mentions", "__s_hl", "section", "hl" },

        --[[ The louder half. Which *channel* rather than which window, because a
             window is where you put things and a channel is what somebody
             said -- and "whisper me and I want to know" is a sentence about the
             whisper. ]]--
        { "Popup", "__h_popup", "header" },

        { "Show Mention Popup", "popup", "boolean" },

        --[[ **Your own name, first and on.** It is the answer almost everybody
             wants, and it has its own switch rather than borrowing the
             Highlights column's -- which was the bug: turning highlighting off,
             or turning your name off over there, silently stopped popups
             working for your name. ]]--
        { "Player Name Mention", "popupName", "boolean",
          nil, nil, nil, nil, nil, "!popup" },

        { "Whisper", "popupWhisper", "boolean",
          nil, nil, nil, nil, nil, "!popup" },
        { "Party", "popupParty", "boolean",
          nil, nil, nil, nil, nil, "!popup" },
        { "Raid", "popupRaid", "boolean",
          nil, nil, nil, nil, nil, "!popup" },
        { "Guild", "popupGuild", "boolean",
          nil, nil, nil, nil, nil, "!popup" },
        { "Officer", "popupOfficer", "boolean",
          nil, nil, nil, nil, nil, "!popup" },

        --[[ Two rows, because a yell carries across a zone and a say does not,
             which is the whole difference between them. ]]--
        { "Say", "popupSay", "boolean",
          nil, nil, nil, nil, nil, "!popup" },
        { "Yell", "popupYell", "boolean",
          nil, nil, nil, nil, nil, "!popup" },

        --[[ **One row per number, not one for the lot.** General, Trade and
             whatever a guild has made for itself are three different rooms that
             happen to share a naming scheme, and wanting one of them is not
             wanting all three. ]]--
        { "Channel 1", "popupChannel.1", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 2", "popupChannel.2", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 3", "popupChannel.3", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 4", "popupChannel.4", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 5", "popupChannel.5", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 6", "popupChannel.6", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 7", "popupChannel.7", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 8", "popupChannel.8", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 9", "popupChannel.9", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },
        { "Channel 10", "popupChannel.10", "boolean",
          nil, nil, nil, nil, "@chat_channel_joined", "!popup" },

        { "Seconds On Screen", "popupSeconds", "slider", 3, 30, 1,
          nil, nil, "!popup" },
        { "Scale", "popupScale", "slider", 50, 200, 5, 0.01,
          nil, "!popup" },
        { "Text Size", "popupTextSize", "slider", 8, 32, 1,
          nil, nil, "!popup" },
        { "Play A Sound", "popupSound", "boolean",
          nil, nil, nil, nil, nil, "!popup" },

        { "Move Pop-up", "__a_popupmove", "action",
          function()
              local m = OB.modules.chat
              m:SetPopupMoving(not m:PopupMoving())
          end,
          function()
              if OB.modules.chat:PopupMoving() then return "Done Placing" end
              return "Move Pop-up"
          end },

        --[[ Everything below goes in the right-hand column. ]]--
        { "", "__c_hl", "column", 2 },

        { "Highlights", "__h_hlwords", "header" },

        { "Enable Highlighting", "highlight", "boolean" },
        --[[ **By class, or by one colour of your own.** Class colour says who is
             talking as well as that they mentioned you, which is the more
             useful of the two on anything but your own name -- and it greys the
             swatch rather than hiding it, because the swatch is still your
             answer for everybody whose class nobody has looked up. ]]--
        { "Highlight By Class Color", "highlightClass", "boolean",
          nil, nil, nil, nil, nil, "!highlight" },
        { "Highlight Color", "highlightColor", "color", true,
          nil, nil, nil, nil, "!highlight,highlightClass" },

        { "Highlight Player Name", "highlightName", "boolean",
          nil, nil, nil, nil, nil, "!highlight" },

        --[[ `@name`, which is not a client convention and is entirely a player
             one -- so it is its own switch rather than folded into the name
             above. ]]--
        { "Highlight @s", "highlightAt", "boolean",
          nil, nil, nil, nil, nil, "!highlight" },

        --[[ Everybody the roster knows, which is the Chat Scan's database put to
             the one use that needs no lookup at read time. **Only when a name is
             said inside a message** -- the sender's own name in front of every
             line they write is not somebody being mentioned. ]]--
        { "Highlight Known Players", "highlightKnown", "boolean",
          nil, nil, nil, nil, nil, "!highlight" },


        --[[ Prat puts a search box on every chat frame. The box is dropped and
             the searching kept: a box anchored over the one part of the screen
             already full of text, with a hover timer and an alpha fade, is a
             lot of frame for a question better answered in chat itself. ]]--
        { "Searching", "__s_find", "section", "find" },

        --[[ **One switch, not two.** There was a "Remember Lines For Searching"
             above this that defaulted off, so the box never appeared and the
             feature looked broken -- and the pairing made no sense anyway: the
             box exists to search, and searching needs the lines. Showing the box
             *is* asking for both. ]]--
        { "Show Search Box", "showSearchBox", "boolean" },

        { "Chat Window 1", "searchWindow.1", "boolean",
          nil, nil, nil, nil, "@chat_window_live", "!showSearchBox" },
        { "Chat Window 2", "searchWindow.2", "boolean",
          nil, nil, nil, nil, "@chat_window_live", "!showSearchBox" },
        { "Chat Window 3", "searchWindow.3", "boolean",
          nil, nil, nil, nil, "@chat_window_live", "!showSearchBox" },
        { "Chat Window 4", "searchWindow.4", "boolean",
          nil, nil, nil, nil, "@chat_window_live", "!showSearchBox" },
        { "Chat Window 5", "searchWindow.5", "boolean",
          nil, nil, nil, nil, "@chat_window_live", "!showSearchBox" },
        { "Chat Window 6", "searchWindow.6", "boolean",
          nil, nil, nil, nil, "@chat_window_live", "!showSearchBox" },
        { "Chat Window 7", "searchWindow.7", "boolean",
          nil, nil, nil, nil, "@chat_window_live", "!showSearchBox" },

        { "Lines Remembered Per Window", "searchLines", "slider", 100, 2000, 100,
          nil, nil, "!showSearchBox" },


}


OB.chatLoad = 20

--[[ Not kept in a local: the behaviour is in chatbehaviour.lua, which takes
     the module back out of the registry by id. ]]--
OB.RegisterModule({
    id = "chat",
    name = "Chat",

    --[[ A feature, because it is a subsystem you would switch off to run
         somebody else's -- but one that owns no window. It decorates frames the
         client already made, which is a third shape after "a bar" and "a
         window", and the first module to have it. ]]--
    feature = true,
    renders = "none",

    --[[ Ships off. It hooks the chat frames, and anything that touches chat
         should be a decision rather than a surprise -- particularly next to
         another chat addon, which is the common case. ]]--
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
        --[[ Per window, because people use window one for everything and window
             three for combat spam, and a timestamp is worth having on one and
             noise on the other. Windows two upward default off for the same
             reason: one is where the conversation is. ]]--
        stamp = { true, false, false, false, false, false, false },

        --[[ Three answers rather than one of twelve combinations: the clock,
             the meridiem, and how much of it with how much padding. ]]--
        hour12 = false,
        meridiem = true,
        timeShape = 3,

        colorStamp = true,
        stampColor = { 0.5, 0.5, 0.5, 1 },

        --[[ None, which is what a timestamp has always been here: it is already
             set apart by being a number at the start of the line. ]]--
        stampBrackets = 3,

        --[[ Your clock, not the server's. Prat defaulted to local time too, and
             the alternative exists because a raid coordinating on server time
             wants the server's -- but it needs a drift correction to be worth
             anything, which is why it is a setting rather than the default. ]]--
        --[[ Whose clock. One is yours, two is the server's -- a list rather than
             a boolean called `localTime`, because "use your clock, not the
             server's" made somebody read a sentence to answer a question with
             two named answers. ]]--
        --[[ **Item links that survive a custom channel.** The server strips
             `|Hitem:` escapes out of any channel it did not make, so a link
             pasted into a guild's own channel arrives as nothing. Encoded as
             plain text on the way out and decoded on the way in, which is
             Prat's answer and the right one -- anybody without the addon sees a
             readable name rather than a blank. ]]--
        itemLinks = true,
        linkFormat = "ChatLink",

        --[[ **Your name, lit up.** The thing everybody actually wants from
             chat: when somebody says your name in a channel you are
             half-watching, it should be what your eye lands on.

             Prat's Highlight module never did this -- its ProcessText returns
             the text unchanged -- so this is the feature its page has been
             promising rather than a port of its code. ]]--
        highlight = true,
        highlightName = true,

        --[[ `@name`, a player convention rather than a client one, so it is its
             own switch: somebody who wants only the deliberate form is asking
             for something the plain name cannot express. ]]--
        highlightAt = true,

        --[[ Everybody the roster knows, which is the Chat Scan's database put to
             the one use that needs no lookup while reading. Off, because on a
             swept realm it is a lot of colour. ]]--
        highlightKnown = false,

        --[[ Off: your own name is the commonest highlight and you have no class
             colour to somebody reading their own chat. Known players are where
             it earns its keep. ]]--
        highlightClass = false,
        highlightColor = { 1, 0.85, 0.2, 1 },

        --[[ **The louder half of highlighting**, for when the chat window is
             not where you are looking: a line with your name in it, in the
             middle of the screen, fading out.

             Off, because it is the one thing in this module that reaches
             outside the chat window -- and the words are Highlighting's words
             rather than a second list, so there is one place to say what counts
             as your name. ]]--
        popup = false,
        --[[ By channel rather than by window: a window is where you filed
             something, a channel is what happened. Whisper and party on,
             because those are somebody talking to you rather than near you. ]]--
        popupWhisper = true,
        popupParty = true,
        popupRaid = true,
        popupGuild = true,
        popupOfficer = true,
        popupSay = false,
        popupYell = false,

        --[[ **Your own name, on.** The answer almost everybody wants, and its
             own switch rather than the Highlights column's -- borrowing that
             meant turning highlighting off stopped popups silently. ]]--
        popupName = true,

        --[[ One entry per numbered channel. They are not one thing: General,
             Trade and a guild's own channel are three different rooms that
             share a naming scheme. ]]--
        popupChannel = { [1] = false, [2] = false, [3] = false, [4] = false,
                         [5] = false, [6] = false, [7] = false, [8] = false,
                         [9] = false, [10] = false },
        popupSeconds = 10,
        popupSound = true,
        popupScale = 1,
        popupTextSize = 12,
        popupPos = { x = 0, y = 120 },

        --[[ Remembering what has been said so it can be found again. Off,
             because it costs memory for a thing most sessions never ask for --
             and the moment it is wanted, it is wanted from now on rather than
             retroactively, so switching it on when you need it is not too
             late. ]]--
        searchLines = 500,

        --[[ A box on the window itself, faint until the mouse is near it.
             Window one only, because that is where the conversation is and a
             box on all seven is seven boxes over the text they sit on. ]]--
        showSearchBox = true,
        searchWindow = { [1] = true, [2] = false, [3] = false, [4] = false,
                         [5] = false, [6] = false, [7] = false },

        timeSource = 1,

        --[[ **Window appearance**, from Prat's Justify, Fading and FontSize.

             All three were separate modules doing the same shape of thing --
             reach into `ChatFrame<i>` and set a property -- so here they are one
             section and one apply pass. Three toggles on the Modules page for
             three one-line behaviours was Ace's granularity, not a user's.

             Size and justification are shared across windows rather than set per
             window. Fading is not, because that is the one people genuinely vary:
             a combat log you scroll back through wants no fade, and the window
             you chat in does. ]]--
        restyle = false,

        --[[ **The box you type into.** Checked Remove Editbox Border uses one
             addon-owned WHITE8X8 fill. Unchecked recreates the original Blizzard
             three-piece input bar with ECO-owned textures, so switching styles
             never gives stock frame geometry control back to the client. ]]--
        editBorder = true,
        editColor = { 0, 0, 0, 0.5 },
        editWidth = 430,
        editHeight = 32,
        editLocked = true,
        editPos = {},

        --[[ Seeded from the profile's own font, so the page opens agreeing with
             the rest of the addon and changing it here changes only chat. It
             goes through `OB.Look`, which is what makes that true. ]]--
        font = OB.fontIndex["Roboto"] or 1,
        fontOutline = 1,   -- None
        fontSize = 12,

        --[[ The window itself rather than its text. One is where the client
             leaves it. ]]--
        scale = 1,
        justify = 1,

        fade = true,
        fadeAfter = 10,

        --[[ Prat's ChannelSeparator. It splits the lumped-together channel groups
             so raid warnings, raid leader and battleground leader can be sent to
             windows of their own -- which is the whole point of having windows.

             Off by default: it rewrites two globals the client owns, and an
             addon quietly changing where messages land is a surprise. ]]--
        separate = false,

        --[[ **Short channel names**, from Prat's ChannelNames.

             `[Guild]` becomes `[G]`, and on a busy screen that is the difference
             between reading the message and reading the label. The defaults are
             the abbreviations people already use, so the common case is one
             switch rather than twelve fields -- but each is yours to change,
             which is what the new text row is for. ]]--
        shorten = false,

        shortGuild = "G",
        shortOfficer = "O",
        shortParty = "P",
        shortRaid = "R",
        shortRaidLeader = "RL",
        shortRaidWarning = "RW",
        shortSay = "S",
        shortYell = "Y",
        shortWhisper = "W",
        shortWhisperFrom = "W",

        --[[ A colon after the name, and a space before it. Prat had both as
             switches and they are worth keeping: `[G] Name:` and `[G]Name:` are
             a real preference, not a rounding error. ]]--
        colon = true,

        --[[ Square, which is what the rename path has always written and so
             what every existing profile already looks like. ]]--
        channelBrackets = 1,

        --[[ **Channels to stay out of.**

             Nothing in this addon joins a channel -- there is no call to
             `JoinChannel`, `JoinPermanentChannel` or anything like it anywhere
             in it. But something does: a server that force-joins World, or the
             client re-joining what it finds in a chat frame's saved channel
             list, and leaving it does not stick because whatever put you there
             does it again next login.

             This is the answer that works regardless of which of those it is:
             name a channel here and you leave it again every time you are put
             in it. Comma separated, and matched on the base name, so "General"
             covers "1. General - Stormwind" and does not need editing every
             time you walk into a new zone.

             Empty by default, which is also what off looks like. ]]--

        --[[ **Numbered channels**, which are the noisy half: `[1. General]` and
             `[2. Trade]` are wider than most of the messages in them.

             These are the one thing that cannot be renamed by a format string.
             The client builds them from the channel list at runtime, so the only
             place to catch them is the message that has already been built --
             which is why this half needs the hook and the other half does not. ]]--
        shortenNumbered = false,

        --[[ **Sticky channels**, from Prat's StickyChannels.

             The edit box opens on whatever you last spoke in, rather than
             resetting to Say every time. It is one line of client state --
             `ChatTypeInfo[type].sticky` -- and it is the difference between
             typing to your party and typing to the room.

             **Prat offered eleven checkboxes; this offers two**, and the split
             is not arbitrary. Ten of the eleven are conversation and one group
             of three is not: yelling, raid-warning and emoting by accident are
             the three mistakes that cannot be taken back. So the ordinary ones
             are one switch and the dangerous ones are a second, off. ]]--

        --[[ **The chat frame's own furniture**, from Prat's Buttons.

             The scroll arrows and the menu button take up the corner of every
             chat window and do nothing the mouse wheel and a right-click do not
             already do. Off by default -- they are the client's and somebody may
             want them -- but this is the first thing most people turn on. ]]--
        hideButtons = false,
        hideMenuButton = false,

        --[[ **Clickable links out of anything that looks like a URL**, from
             Prat's UrlCopy.

             1.12 cannot open a browser and never will, so "clickable" means a
             box you can select the text out of. That is the whole feature and it
             is worth having: the alternative is copying a URL off the screen by
             hand, one character at a time -- which is why it has no switch. ]]--
        urlBrackets = 1,
        urlColor = { 0.35, 0.70, 1.00, 1 },

        --[[ **Channel colours, remembered by name**, from Prat's
             ChannelColorMemory.

             1.12 stores a channel's colour by its *number*, and the numbers move
             -- leave one channel and everything below it shifts up, taking your
             colours with it. Remembering by name is the fix and it is invisible
             when it works, which is why it has no switch. ]]--

        --[[ **Scrollback**, from Prat's Scroll and History -- two modules, but
             one subject: how far back you can read and how fast you get there.

             On by default, and the only thing in this file that is. 1.12's chat
             frames are not wheel-scrollable at all: the client wants you to drag
             the scrollbar, which nobody has done since 2005. Off was the one
             state nobody was asking for, so there is no longer a way to ask. ]]--

        --[[ One notch, one line, because a chat window is not a document -- you
             scroll it to re-read the thing that just went past. Ctrl is the
             coarse version for when it is not. ]]--
        wheelLines = 1,
        wheelFast = 3,

        --[[ Shared across windows rather than one number each. Prat had seven
             sliders and the only real case for varying it is a combat log you
             keep more of, which is not worth six extra rows -- the cost of a
             larger number is memory, and 500 lines of text is nothing. ]]--
        scrollback = 128,

        --[[ **The way back down**, which 1.12 does not offer at all: scroll up
             to read something and the only ways back are the wheel, the arrow,
             or a new message arriving.

             On by default and shown only while scrolled up, so it costs nothing
             to somebody who never scrolls -- and the switch is here because a
             button that appears over the chat window is exactly the kind of
             thing somebody will want gone. ]]--
        jumpButton = true,

        --[[ **The away reply, which the client sends you every single time.**

             Whisper somebody who is AFK or on Do Not Disturb and the server
             sends their auto-reply back -- "Player is Away: gone for food" --
             as `CHAT_MSG_AFK` or `CHAT_MSG_DND`. Once is useful. The client
             sends it on *every* whisper, so a conversation with somebody who
             forgot to clear their AFK is your message, their away notice, your
             message, their away notice, and the actual conversation pushed off
             the top of the window.

             **The `<AFK>` marker beside their name is untouched**, and that is
             the point rather than a caveat: the marker is drawn from
             `CHAT_FLAG_AFK` on their own lines and has nothing to do with these
             two events. You still know they are away. You are just not told
             again every time you speak.

             On by default -- one of very few things here that is -- because the
             information is not lost, only the repetition, and nobody has ever
             wanted the fourth copy. ]]--
        hideAwayReplies = true,

        --[[ **Scrollback that survives a reload**, from Prat's History.

             1.12 empties every chat window on `/reload` and on logout, so the
             conversation you were in the middle of is simply gone -- and reload
             is something you do constantly while configuring an addon. Prat
             replayed what it had seen, and the thing that made it work rather
             than merely exist was drawing the replayed lines *darker*: history
             you can read and never mistake for something that just arrived.

             **Off by default, and deliberately.** This is the one setting in
             the addon that writes what people say to disk. Everything else here
             rearranges pixels; this keeps a copy of your conversations in a
             SavedVariables file that anybody with the machine can read. That is
             a reasonable thing to want and an unreasonable thing to turn on for
             somebody without asking, which is the same line the edit box
             history draws when it refuses to persist what you typed. ]]--
        history = false,

        --[[ **Never say a macro directive out loud.** 1.12 has no
             `#showtooltip`, so the client says any line it cannot run. See
             `IsMacroDirective`. ]]--
        hideMacroDirectives = true,

        --[[ Per window. A hundred lines is a few screens -- enough to pick a
             conversation back up, short enough that the file stays small and
             the replay is instant. ]]--
        historyLines = 100,

        --[[ How much darker, as a fraction of the line's own colour. Scaling
             the colour rather than replacing it keeps a whisper pink and a
             party line blue, which is the whole point: you can still tell what
             kind of line it was, it is just visibly *past*.

             0.55 is dim enough to read as history at a glance and bright enough
             to actually read. ]]--
        historyDim = 0.55,

        --[[ **Player names**, from Prat's PlayerNames.

             The marquee feature of any chat addon and the one people install one
             for: the sender of a line coloured by class, so a wall of text
             becomes a list of people. On by default, unlike everything else
             here, because somebody who has switched this module on has asked for
             exactly this.

             It reads from the roster -- what the addon knows about other players
             -- which is account-wide and outlives the profile. See config.lua. ]]--
        names = true,

        nameBrackets = 1,

        --[[ **Two swatches and an override**, which replaced a three-way Color
             Mode nobody could read the name of. "By Class / Random But Stable /
             One Color" made the reader work out which of three things they were
             choosing between before they could choose; a checkbox that says
             what it does needs no such reading. ]]--
        nameClassColor = true,
        nameKnownColor = { 0.85, 0.85, 0.85, 1 },

        --[[ Everyone whose class nobody has looked up yet, which in General is
             most of them. A colour of their own rather than none, because an
             uncoloured name reads as a class you have not learned rather than
             as a person nobody has asked about. ]]--
        nameColor = { 0.65, 0.65, 0.65, 1 },



        --[[ Level in front, raid group behind. Both off, both cheap, and both
             clutter on a name that is already carrying brackets and a colour. ]]--
        nameLevel = false,
        nameGroup = false,
    },

    options = OB.chatOptions,

    --[[ **This module shows what is known; it does not find it out.** Learning
         who somebody is belongs to the roster module, which watches the six
         client rosters and runs the `/who` queue -- and which nameplates and
         unit frames will read from without having to switch chat on.

         The one event left is about channels rather than people: the client
         announcing that you have joined one, which is the only moment a channel
         you did not ask for can be left again. ]]--
    events = { "CHAT_MSG_CHANNEL_NOTICE", "PLAYER_ENTERING_WORLD",
               "UPDATE_CHAT_COLOR" },

    requires = { "GetGameTime", "IsShiftKeyDown", "IsControlKeyDown" },
})


--[[ The far end of the declaration. Everything below this point moved to
     modules/chatbehaviour.lua -- see its header for why. ]]--
OB.chatLoad = 30
