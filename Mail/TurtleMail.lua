TurtleMail = TurtleMail or {}
L = TurtleMail.L

local m = TurtleMail
local getn = table.getn ---@diagnostic disable-line: deprecated
local function pack( ... ) return arg end

local ATTACHMENTS_MAX = 21
local ATTACHMENTS_PER_ROW_SEND = 7
local ATTACHMENTS_MAX_ROWS_SEND = 3

local INBOX_AUCTIONHOUSES = {
  [ "Stormwind Auction House" ] = true,
  [ "Alliance Auction House" ] = true,
  [ "Darnassus Auction House" ] = true,
  [ "Undercity Auction House" ] = true,
  [ "Thunder Bluff  Auction House" ] = true,
  [ "Horde Auction House" ] = true,
  [ "Blackwater Auction House" ] = true,
}

TurtleMail.api = getfenv()
TurtleMail.timer = 0
TurtleMail.log = {}
TurtleMail.orig = {}
TurtleMail.hooks = {}
TurtleMail.hook = setmetatable( {}, { __newindex = function( _, k, v ) m.hooks[ k ] = v end } )
TurtleMail.debug_enabled = false

---@type Calendar
TurtleMail.calendar = m.Calendar.new()

function TurtleMail:init()
  self.debug( "TurtleMail.init" )
  self.update_frame = m.api.CreateFrame( "Frame", "TurtleMailFrame", m.api.MailFrame )
  self.update_frame:SetScript( "OnUpdate", self.on_update )

  -- Register events
  self.update_frame:SetScript( "OnEvent", function() self[ event ]() end )
  for _, event in { "ADDON_LOADED", "PLAYER_LOGIN", "UI_ERROR_MESSAGE", "CURSOR_UPDATE", "BAG_UPDATE", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_INBOX_UPDATE" } do
    self.update_frame:RegisterEvent( event )
  end

  -- Set default log settings
  m.api.TurtleMail_Log = {
    Sent = {},
    Received = {},
    Settings = {
      --[==[ **On, because a history nobody is recording is not a history.**

           Upstream ships this off and says so in its README -- *logging is
           disabled by default, enable with `/tm log`* -- which is a reasonable
           default for a standalone addon somebody chose to install and a poor
           one here. Reported as the sent and received history simply missing:
           it was, because nothing had ever been written to it, and the two tabs
           that would have said so were hidden along with it.

           The cost of being wrong in this direction is a table of text that
           grows slowly. The cost of the other is the feature appearing not to
           exist. ]==]
      Enabled = true,
      SentFilters = { Money = 1, COD = 1, Other = 1 },
      ReceivedFilters = { Money = 1, COD = 1, Other = 1, Returned = 1, AH = 1, AHSold = 1, AHOutbid = 1, AHWon = 1, AHCancelled = 1, AHExpired = 1 }
    }
  }
  m.api.TurtleMail_AutoCompleteNames = {}

  -- hack to prevent beancounter from deleting mail
  self.TakeInboxMoney, self.TakeInboxItem, self.DeleteInboxItem = m.api.TakeInboxMoney, m.api.TakeInboxItem, m.api.DeleteInboxItem

  self.tooltip_frame = m.api.CreateFrame( "GameTooltip", "TurtleMailTooltipFrame", nil, "GameTooltipTemplate" )
  self.tooltip_frame:SetOwner( m.api.WorldFrame, "ANCHOR_NONE" );
end

---@param args string
function TurtleMail.slash_command( args )
  if args == "" or args == "help" then
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473TurtleMail " .. L[ "Help" ] .. "|r" )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm log|r " .. L[ "Toggle logging on/off" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear sent|r " .. L[ "Clear sent log" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear received|r " .. L[ "Clear received log" ] )
    m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473/tm clear names|r " .. L[ "Clear saved recipient names from autocomplete" ] )
    return
  end

  if args == "log" then
    m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ] = not m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ]
    if m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ] then
      m.info( L[ "Logging is enabled." ] )
      if m.api.MailFrame:IsVisible() then
        m.log_tabs( true )
      end
    else
      m.info( L[ "Logging is disabled." ] )
      if m.api.MailFrame:IsVisible() then
        m.log_tabs( false )
      end
    end
    m.log_enabled = m.api.TurtleMail_Log[ "Settings" ][ "Enabled" ]
  end

  if string.find( args, "^clear" ) then
    if args == "clear sent" then
      m.info( L[ "Sent log cleared." ] )
      m.api.TurtleMail_Log[ "Sent" ] = {}
    elseif args == "clear received" then
      m.info( L[ "Received log cleared." ] )
      m.api.TurtleMail_Log[ "Received" ] = {}
    elseif args == "clear names" then
      m.info( L[ "Recipient autocomplete names have been cleared." ] )
      local key = m.api.GetCVar( "realmName" ) .. "|" .. m.api.UnitFactionGroup( "player" )
      m.api.TurtleMail_AutoCompleteNames[ key ] = {}
    end
  end

  if args == "debug" then
    m.debug_enabled = not m.debug_enabled
    if m.debug_enabled then
      m.info( L[ "Debug is enabled." ] )
    else
      m.info( L[ "Debug is disabled." ] )
    end
  end
end

function TurtleMail.on_update()
  if not m.api.MailFrame or not m.api.MailFrame:IsVisible() then return end

  if m._cursorItem then
    m.debug( "on_update: cursorItem" )
    m.cursorItem = m._cursorItem
    m._cursorItem = nil
  end

  if m.sendmail_update then
    m.debug( "on_update: sendmail" )
    m.sendmail_update = nil
    if m.sendmail_sending then
      m.debug( "m.sendmail_sending" )
      m.sendmail_send()
    end
  end

  --[==[ **A nil header threw in here, and a throw in here is the reload.**

       `GetInboxHeaderInfo` answers nothing for a letter the server has not sent
       down yet -- normal in vanilla, because the inbox arrives asynchronously
       after `CheckInbox` -- and this read `COD` out of it **before** checking
       anything, then compared it with `COD > 0`. Comparing nil with a number
       raises, and a raise inside `OnUpdate` abandons the rest of the handler.

       By then `m.inbox_update` had already been set false, so nothing was left
       to drive the loop; and `m.inbox_opening` was still true, which is the
       condition on the timer twenty lines below that calls `CheckInbox` at all.
       So the mailbox stopped refreshing, permanently, and the only way out was a
       reload. That is the reported "mail often requires a reload", and it is one
       missing nil check.

       Three changes, and the order of them is the fix:

         * the **bounds check first**, so the header is never asked for out of
           range;
         * a header that is not there yet is **waited for** rather than treated
           as a letter with no COD -- it will arrive, and skipping it would open
           the mail after it instead;
         * a **watchdog**, because "wait for it" is a loop and a loop that can
           never end is the fault this is fixing wearing different clothes. Two
           hundred ticks is a few seconds; a letter that has not arrived by then
           is not going to. ]==]
  if m.inbox_update then
    m.debug( "on_update: inbox_update" )
    m.inbox_update = false

    local count = m.api.GetInboxNumItems() or 0

    if m.inbox_index > count then
      if (m.money_received or 0) > 0 then
        m.info( string.format( "%s%s.", m.format_money( m.money_received ), L[ "collected" ] ) )
      end
      m.inbox_abort()
    else
      local _, _, _, _, _, COD, _, _, _, _, _, _, isGM = m.api.GetInboxHeaderInfo( m.inbox_index )

      if COD == nil then
        m.inbox_waited = (m.inbox_waited or 0) + 1
        m.debug( "on_update: header not ready, waiting" )

        if m.inbox_waited > 200 then
          m.inbox_waited = nil
          m.info( L[ "Mail did not arrive from the server; stopping." ]
              or "Mail did not arrive from the server; stopping." )
          m.inbox_abort()
        else
          m.inbox_update = true
        end
      else
        m.inbox_waited = nil

        if m.inbox_skip or COD > 0 or isGM then
          m.inbox_skip = false
          m.inbox_index = m.inbox_index + 1
          m.inbox_update = true
        else
          m.inbox_open( m.inbox_index )
        end
      end
    end
  end

  if m.timer > 0 then
    m.timer = m.timer - 1
  elseif not m.inbox_opening then
    m.timer = 200
    m.api.CheckInbox()
  end
end

function TurtleMail.CURSOR_UPDATE()
  m.cursorItem = nil
end

function TurtleMail.get_cursor_item()
  return m.cursorItem
end

---@param item table
function TurtleMail.set_cursor_item( item )
  m._cursorItem = item
end

function TurtleMail.BAG_UPDATE()
  if m.api.MailFrame:IsVisible() then
    m.api.SendMailFrame_Update()
  end
end

function TurtleMail.MAIL_SHOW()
  if m.api.TurtleMail_Point then
    m.debug( "Set point" )
    m.api.MailFrame:SetPoint( m.api.TurtleMail_Point.point, m.api.TurtleMail_Point.x, m.api.TurtleMail_Point.y )
  end

  --[==[ **A one-shot that could fail once and then never run again.**

       The flag was set *before* the work, and the work reaches into
       `SendMailPackageButton`'s regions by position. If those are not there yet
       -- and whether they are depends on what else has skinned that button, and
       when -- indexing nil raised, which aborted the whole of `MAIL_SHOW`: the
       log tab, the timer reset and the money readout below all stopped with it.

       And the flag was already true, so it never tried again. Reported as the
       mail not showing properly and wanting a reload or two, which is exactly
       what a permanently-skipped setup looks like: a reload clears the flag and
       the next open may catch the button in a better state.

       Now the flag records whether the setup *succeeded*, so a bad first open
       is retried on the next one and no reload is needed. ]==]
  if not m.first_show then
    m.first_show = m.mail_first_show()
  end

  m.log_tabs( m.log_enabled )

  --[[ A fresh visit starts on page one -- see `hook.InboxFrame_Update`. ]]--
  if m.api.InboxFrame then m.api.InboxFrame.pageNum = 1 end

  m.timer = 0
  m.money_received = 0
  m.update_money( 0 )
end

--[==[ Answers whether it got everything done. Anything missing is a "no", and
     a "no" means try again at the next mailbox rather than limp on. ]==]
function TurtleMail.mail_first_show()
  local package = m.api.SendMailPackageButton
  if not package or not package.GetRegions then return false end

  if m.pfui_skin_enabled and m.api.pfUI and m.api.pfUI.api then
    m.api.pfUI.api.StripTextures( package )
  end

  local regions = { package:GetRegions() }

  --[[ Read by position, which is what the original did and is the part that
       could not be relied on. Checked rather than assumed. ]]--
  if not regions[ 1 ] or not regions[ 3 ] then return false end

  regions[ 1 ]:Hide()
  regions[ 3 ]:Hide()

  package:Disable()
  package:SetScript( "OnReceiveDrag", nil )
  package:SetScript( "OnDragStart", nil )

  return true
end

function TurtleMail.MAIL_CLOSED()
  m.inbox_abort()
  m.sendmail_sending = false
  m.sendmail_clear()
end

function TurtleMail.UI_ERROR_MESSAGE()
  if m.inbox_opening then
    if arg1 == m.api.ERR_INV_FULL then
      m.inbox_abort()
    elseif arg1 == m.api.ERR_ITEM_MAX_COUNT then
      m.inbox_skip = true
    end
  elseif m.sendmail_sending and (arg1 == m.api.ERR_MAIL_TO_SELF or arg1 == m.api.ERR_PLAYER_WRONG_FACTION or arg1 == m.api.ERR_MAIL_TARGET_NOT_FOUND or arg1 == m.api.ERR_MAIL_REACHED_CAP) then
    m.sendmail_sending = false
    m.sendmail_state = nil
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
  end
end

--[==[ **Bundled, so the name it is loaded under is not its own.**

     `arg1` on `ADDON_LOADED` is the addon the client just finished loading, and
     inside Equadis' Classic Overhaul that is the Overhaul. The original guard
     compared it against "TurtleMail" and so rejected the only event it was ever
     going to be handed -- and everything below here, the saved-variable merge
     included, simply never ran.

     Both names are accepted rather than one swapped for the other, so a copy of
     this file dropped back into a standalone folder still works. ]==]
TurtleMail.HOST_ADDON = "EquadisClassicOverhaul"

function TurtleMail.ADDON_LOADED()
  if arg1 ~= m.HOST_ADDON and arg1 ~= "TurtleMail" then return end

  --[[ The version is the host's now; asking for "TurtleMail" metadata answers
       nil, and "Loaded (vnil)" is worse than saying nothing. ]]--
  local version = m.api.GetAddOnMetadata( m.HOST_ADDON, "Version" )
        or m.api.GetAddOnMetadata( "TurtleMail", "Version" )

  m.info( string.format( "Loaded (|cffeda55fv%s|r).", version or "?" ) )

  --[==[ **The saved table, put back into shape before anything reads it.**

       The defaults set at file load are replaced wholesale by the client when it
       restores the saved variable, so what arrives here is whatever was written
       by whatever version last ran -- and an older or half-written one need not
       have `Settings`, `Sent` or `Received` in it at all.

       The very next line indexes `Settings`, and indexing nil **raises**. A
       raise here abandons the rest of `ADDON_LOADED`, which is where the tab
       count is set and `log.load()` runs -- so the symptom is not an error
       anybody sees, it is *no log tabs and no history*, which is exactly how
       this was reported.

       Same shape as the inbox loop: one missing nil check turning a recoverable
       state into a permanent one. ]==]
  local log = m.api.TurtleMail_Log

  if type( log ) ~= "table" then
    log = {}
    m.api.TurtleMail_Log = log
  end

  if type( log.Sent ) ~= "table" then log.Sent = {} end
  if type( log.Received ) ~= "table" then log.Received = {} end

  if type( log.Settings ) ~= "table" then
    log.Settings = {
      Enabled = true,
      SentFilters = { Money = 1, COD = 1, Other = 1 },
      ReceivedFilters = { Money = 1, COD = 1, Other = 1, Returned = 1, AH = 1,
        AHSold = 1, AHOutbid = 1, AHWon = 1, AHCancelled = 1, AHExpired = 1 }
    }
  end

  --[[ The filter tables decide what `populate` will show. Empty, every row is
       filtered out and the page reads as empty with the history sitting right
       there behind it. ]]--
  if type( log.Settings.SentFilters ) ~= "table" then
    log.Settings.SentFilters = { Money = 1, COD = 1, Other = 1 }
  end

  if type( log.Settings.ReceivedFilters ) ~= "table" then
    log.Settings.ReceivedFilters = { Money = 1, COD = 1, Other = 1,
      Returned = 1, AH = 1, AHSold = 1, AHOutbid = 1, AHWon = 1,
      AHCancelled = 1, AHExpired = 1 }
  end

  if not m.api.TurtleMail_Log[ "Settings" ].first_run then
    m.api.TurtleMail_Log[ "Settings" ].first_run = version
    m.info( "New in |cffeda55fv1.4|r: Enable logging with |cffabd473/tm log|r" )
  end

  if m.api.UIPanelWindows[ "MailFrame" ] then
    m.api.UIPanelWindows[ "MailFrame" ].pushable = 1
  else
    m.api.UIPanelWindows[ "MailFrame" ] = { area = "left", pushable = 1 }
  end

  if m.api.UIPanelWindows[ "FriendsFrame" ] then
    m.api.UIPanelWindows[ "FriendsFrame" ].pushable = 2
  else
    m.api.UIPanelWindows[ "FriendsFrame" ] = { area = "left", pushable = 2 }
  end

  m.api.MailFrame:SetScript( "OnDragStop", m.on_drag_stop )
  m.api.MailFrame:SetClampedToScreen( true )
  m.api.PanelTemplates_SetNumTabs( m.api.MailFrame, 4 )

  m.inbox_load()
  m.sendmail_load()
  m.log.load()
  m.pfui_skin()
end

function TurtleMail.PLAYER_LOGIN()
  m.debug( "PLAYER_LOGIN" )
  for k, v in m.hooks do
    m.orig[ k ] = m.api[ k ]
    m.api[ k ] = v
  end
--[==[ **The list was aged against the wrong clock, so nothing ever left it.**

     Names are stamped and then dropped after thirty days. Both halves used
     `GetTime`, which is **seconds since the client started** -- not a date. So a
     name stamped at 40000 in a long session is compared, after a relog, against
     a `GetTime` of about 12, and `12 - 40000` is not greater than thirty days.
     It is not greater than anything. Nothing was ever pruned, by anybody, ever.

     Reported as a name typed once by mistake staying in the list permanently.
     It did, and so did every other name.

     `time()` is the wall clock and is what a thirty-day rule needs. The stamps
     already written are session numbers -- small, and meaningless as dates -- so
     they are re-stamped as "now" rather than deleted: the names in somebody's
     list are worth keeping, and only their ages were ever nonsense. Anything
     below a billion cannot be a real epoch second (that was 2001) and can only
     be one of the old ones. ]==]
  local key = m.api.GetCVar( "realmName" ) .. "|" .. m.api.UnitFactionGroup( "player" )
  m.api.TurtleMail_AutoCompleteNames[ key ] = m.api.TurtleMail_AutoCompleteNames[ key ] or {}

  local now = m.api.time and m.api.time() or 0
  local EPOCH_FLOOR = 1000000000
  local THIRTY_DAYS = 60 * 60 * 24 * 30

  for char, last_seen in m.api.TurtleMail_AutoCompleteNames[ key ] do
    if type( last_seen ) ~= "number" or last_seen < EPOCH_FLOOR then
      m.api.TurtleMail_AutoCompleteNames[ key ][ char ] = now
    elseif now > 0 and now - last_seen > THIRTY_DAYS then
      m.api.TurtleMail_AutoCompleteNames[ key ][ char ] = nil
    end
  end

  --[==[ **Switched on once for a saved profile that predates this.**

       The default above only reaches somebody with no saved settings. Anybody
       who has opened a mailbox already carries `Enabled = false` -- not because
       they chose it, but because that is what upstream wrote -- and would go on
       seeing no history for ever.

       Marked as done, so this happens exactly once. Somebody who really does
       want logging off can `/tm log` afterwards and it stays off, which is the
       difference between a default and an override. ]==]
  m.add_auto_complete_name( m.api.UnitName( "player" ) )

  local settings = m.api.TurtleMail_Log[ "Settings" ]

  if not settings.DefaultedOn then
    settings.DefaultedOn = true
    settings.Enabled = true
  end

  m.log_enabled = settings.Enabled

  SLASH_TURTLEMAIL1 = "/turtlemail"
  SLASH_TURTLEMAIL2 = "/tm"
  m.api.SlashCmdList[ "TURTLEMAIL" ] = m.slash_command
end

function TurtleMail.MAIL_SEND_SUCCESS()
  m.debug( "MAIL_SEND_SUCCESS" )
  if m.sendmail_state and not m.sendmail_state.sent then
    m.sendmail_state.sent = true
    m.log.add( 'Sent', m.sendmail_state )
    m.add_auto_complete_name( m.sendmail_state.to )
  end
  if m.sendmail_sending then
    m.sendmail_update = true
  end
end

function TurtleMail.MAIL_INBOX_UPDATE()
  if m.inbox_opening then
    m.inbox_update = true
  end

  for i = 1, 7 do
    local index = (i + (m.api.InboxFrame.pageNum - 1) * 7)
    if index <= m.api.GetInboxNumItems() then
      local _, _, sender, _, _, _, _, _, _, was_returned = m.api.GetInboxHeaderInfo( index )
      if INBOX_AUCTIONHOUSES[ sender ] then
        m.api[ "TurtleMailAuctionIcon" .. i ]:Show()
      else
        m.api[ "TurtleMailAuctionIcon" .. i ]:Hide()
      end
      if was_returned then
        m.api[ "TurtleMailReturnedArrow" .. i ]:Show()
      else
        m.api[ "TurtleMailReturnedArrow" .. i ]:Hide()
      end
    end
  end
end

---@param name string
function TurtleMail.add_auto_complete_name( name )
  local key = m.mail_key()
  m.api.TurtleMail_AutoCompleteNames[ key ] = m.api.TurtleMail_AutoCompleteNames[ key ] or {}

  --[[ Wall clock, not uptime -- see the note beside the pruning. ]]--
  m.api.TurtleMail_AutoCompleteNames[ key ][ name ] = m.api.time and m.api.time() or 0
end

--[[ Realm and faction, which is how both lists are keyed: a name is only worth
     suggesting to somebody who could actually write to it. ]]--
function TurtleMail.mail_key()
  return m.api.GetCVar( "realmName" ) .. "|" .. m.api.UnitFactionGroup( "player" )
end

--[==[ **Names worth keeping at the top, and names worth forgetting.**

     The list is everybody you have ever successfully written to, newest first,
     which is a reasonable default and a poor answer once it is forty names
     long: the bank alt you mail every day sinks below a stranger you sold
     something to this morning.

     Favourites are held apart rather than as a flag on the name, because the
     name table is TurtleMail's own and a standalone copy of this addon still
     has to be able to read it. ]==]
function TurtleMail.favourites()
  if type( m.api.TurtleMail_Favourites ) ~= "table" then
    m.api.TurtleMail_Favourites = {}
  end

  local key = m.mail_key()
  m.api.TurtleMail_Favourites[ key ] = m.api.TurtleMail_Favourites[ key ] or {}

  return m.api.TurtleMail_Favourites[ key ]
end

---@param name string
function TurtleMail.is_favourite( name )
  return name and m.favourites()[ name ] and true or false
end

---@param name string
function TurtleMail.toggle_favourite( name )
  if not name or name == "" then return false end

  local list = m.favourites()

  if list[ name ] then
    list[ name ] = nil
    return false
  end

  --[==[ **Favouriting also remembers.** Somebody pinning a name they have never
       written to means it: without this the pin would hold a name the
       suggestion list has no row for, and the pin would appear to do
       nothing. ]==]
  list[ name ] = true
  m.add_auto_complete_name( name )

  return true
end

---@param name string
function TurtleMail.forget_name( name )
  if not name or name == "" then return false end

  local key = m.mail_key()
  local names = m.api.TurtleMail_AutoCompleteNames[ key ]

  if not names or not names[ name ] then return false end

  names[ name ] = nil
  m.favourites()[ name ] = nil

  return true
end

function TurtleMail.inbox_load()
  m.api.InboxFrame:EnableMouse( false )
  local btn = m.api.CreateFrame( "Button", "TurtleMailOpenMailButton", m.api.InboxFrame, "UIPanelButtonTemplate" )
  btn:SetPoint( "BOTTOM", -10, 90 )
  btn:SetText( m.api.OPENMAIL )
  btn:SetWidth( math.max( 120, 30 + ({ btn:GetRegions() })[ 1 ]:GetStringWidth() ) )
  btn:SetHeight( 25 )
  btn:SetScript( "OnClick", m.inbox_open_all )

  for i = 1, 7 do
    m.api[ "TurtleMailAuctionIcon" .. i .. "Texture" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    m.api[ "TurtleMailReturnedArrow" .. i .. "Texture" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
  end
end

function TurtleMail.inbox_open_all()
  m.inbox_opening = true
  m.inbox_waited = nil
  m.inbox_update_lock()
  m.inbox_skip = false
  m.inbox_index = 1
  m.inbox_update = true
end

function TurtleMail.inbox_abort()
  m.inbox_opening = false
  m.inbox_waited = nil
  m.inbox_update_lock()
  m.inbox_update = false
end

function TurtleMail.set_cod_text()
  local text = string.sub( m.api.COD_AMOUNT, 1, string.len( m.api.COD_AMOUNT ) - 1 )

  --if not m.api.pfUI or not m.api.pfUI.version then
  if not m.pfui_skin_enabled then
    -- `string.match` is Lua 5.1 and 1.12 is 5.0, so this is `gsub` instead --
    -- which also cannot return nil into the concatenation below when the
    -- amount is not shaped the way the pattern expects.
    text = string.gsub( text, "^(.-)%s+%S+$", "%1" )
  end

  if m.api.SendMailCODAllButton:GetChecked() then
    m.api.SendMailMoneyText:SetText( text .. " " .. L[ "each mail" ] .. ":" )
  else
    m.api.SendMailMoneyText:SetText( text .. " " .. L[ "1st mail" ] .. ":" )
  end
end

---@param copper number
function TurtleMail.format_money( copper )
  if type( copper ) ~= "number" then return "-" end

  local gold = math.floor( copper / 10000 )
  local silver = math.floor( (copper - gold * 10000) / 100 )
  local copper_remain = copper - (gold * 10000) - (silver * 100)

  local result = ""
  if gold > 0 then
    result = result .. string.format( "|cffffffff%d|cffffd700g|r ", gold )
  end
  if silver > 0 then
    result = result .. string.format( "|cffffffff%d|cffc7c7cfs|r ", silver )
  end
  if copper_remain > 0 or result == "" then
    result = result .. string.format( "|cffffffff%d|cffeda55fc|r ", copper_remain )
  end

  return result
end

---@param money number
function TurtleMail.update_money( money )
  m.money_received = m.money_received + money
  m.api.MoneyReceived:SetText( L[ "Money received" ] .. ": " .. m.format_money( m.money_received ) )

  if m.money_received > 0 then
    m.api.MoneyReceived:Show()
  else
    m.api.MoneyReceived:Hide()
  end
end

function TurtleMail.on_drag_stop()
  this:StopMovingOrSizing()
  local point, _, _, x, y = m.api.MailFrame:GetPoint()
  m.api.TurtleMail_Point = { point = point, x = x, y = y }
end

---@param i number
---@param manual boolean?
function TurtleMail.inbox_open( i, manual )
  m.debug( "inbox_open" )
  local package_icon, _, sender, subject, money, cod, _, has_item, read, returned, _, _, gm = m.api.GetInboxHeaderInfo( i )

  if has_item then
    if not m.received_icon then
      m.received_item = m.api.GetInboxItem( i )
      m.received_icon = package_icon
    end
  end

  if (read and not has_item) or manual then
    if money > 0 then
      m.update_money( money )
      m.received_money = money
    end
    if money == 0 or manual then
      m.log.add( "Received", {
        from = sender,
        subject = subject,
        money = manual and money or m.received_money,
        cod = cod,
        returned = returned,
        gm = gm,
        icon = m.received_icon,
        item = m.received_item
      } )
      m.received_money = 0
      m.received_icon = nil
      m.received_item = nil
    end
  end

  m.api.GetInboxText( i )
  m.TakeInboxMoney( i )
  m.TakeInboxItem( i )
  m.DeleteInboxItem( i )
end

function TurtleMail.inbox_update_lock()
  for i = 1, 7 do
    m.api[ "MailItem" .. i .. "ButtonIcon" ]:SetDesaturated( m.inbox_opening )
    if m.inbox_opening then
      m.api[ "MailItem" .. i .. "Button" ]:SetChecked( nil )
    end
  end
end

function TurtleMail.hook.GetInboxHeaderInfo( ... )
  local sender, canReply = arg[ 3 ], arg[ 12 ]
  if sender and canReply then
    m.add_auto_complete_name( sender )
  end

  return m.orig.GetInboxHeaderInfo( unpack( arg ) )
end

function TurtleMail.hook.OpenMail_Reply( ... )
  m.api.TurtleMail_To = nil
  return m.orig.OpenMail_Reply( unpack( arg ) )
end

function TurtleMail.hook.InboxFrame_Update()
  --[==[ **A page past the end draws nothing, and the client never turns
       back.**

       `InboxFrame.pageNum` is set to one when the frame loads and never
       again: not on a fresh visit, not when the letters on the page are
       taken. Open everything on page two, walk away, come back with one new
       letter -- the list draws page two of a one-page inbox, which is empty,
       under a minimap icon that says there is mail. A reload sets the page
       back to one, which is the whole of "it appears on reload". Clamped to
       the last page here, before the client draws; and `MAIL_SHOW` starts
       every visit on page one. ]==]
  local total = math.ceil( (m.api.GetInboxNumItems() or 0) / m.api.INBOXITEMS_TO_DISPLAY )
  if total < 1 then total = 1 end
  if (m.api.InboxFrame.pageNum or 1) > total then m.api.InboxFrame.pageNum = total end

  m.orig.InboxFrame_Update()
  for i = 1, 7 do
    -- hack for tooltip update
    m.api[ "MailItem" .. i ]:Hide()
    m.api[ "MailItem" .. i ]:Show()
  end

  local currentPage = m.api.InboxFrame.pageNum
  local totalPages = math.ceil( m.api.GetInboxNumItems() / m.api.INBOXITEMS_TO_DISPLAY )
  local text = totalPages > 0 and (currentPage .. "/" .. totalPages) or m.api.EMPTY
  m.api.InboxTitleText:SetText( m.api.INBOX .. " [" .. text .. "]" )

  m.inbox_update_lock()
end

---@param i number
function TurtleMail.hook.InboxFrame_OnClick( i )
  if m.inbox_opening or arg1 == "RightButton" and ({ m.api.GetInboxHeaderInfo( i ) })[ 6 ] > 0 then
    this:SetChecked( nil )
  elseif arg1 == "RightButton" then
    m.inbox_open( i, true )
  else
    return m.orig.InboxFrame_OnClick( i )
  end
end

function TurtleMail.hook.InboxFrameItem_OnEnter()
  m.orig.InboxFrameItem_OnEnter()
  if m.api.GetInboxItem( this.index ) then
    m.api.GameTooltip:AddLine( m.api.ITEM_OPENABLE, "", 0, 1, 0 )
    m.api.GameTooltip:Show()
  end
end

function TurtleMail.hook.SendMailFrame_Update()
  local gap
  local last = m.sendmail_num_attachments()

  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]

    local texture, count
    if btn.item then
      texture, count = m.api.GetContainerItemInfo( unpack( btn.item ) )
    end
    if not texture then
      btn:SetNormalTexture( nil )
      m.api[ btn:GetName() .. "Count" ]:Hide()
      btn.item = nil
    else
      btn:SetNormalTexture( texture )
      if count > 1 then
        m.api[ btn:GetName() .. "Count" ]:Show()
        m.api[ btn:GetName() .. "Count" ]:SetText( count )
      else
        m.api[ btn:GetName() .. "Count" ]:Hide()
      end
    end
  end

  if m.sendmail_num_attachments() > 0 then
    m.api.SendMailCODButton:Enable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if m.sendmail_num_attachments() > 1 and m.api.SendMailCODButton:GetChecked() then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    else
      m.api.SendMailCODAllButton:Disable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
      m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    end
  else
    m.api.SendMailSendMoneyButton:SetChecked( 1 )
    m.api.SendMailCODButton:SetChecked( nil )
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND )
    m.api.SendMailCODButton:Disable()
    m.api.SendMailCODButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  end

  m.api.MoneyFrame_Update( "SendMailCostMoneyFrame", m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) )

  -- Determine how many rows of attachments to show
  local itemRowCount = 1
  local temp = last
  while temp > ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND do
    itemRowCount = itemRowCount + 1
    temp = temp - ATTACHMENTS_PER_ROW_SEND
  end

  if not gap and temp == ATTACHMENTS_PER_ROW_SEND and itemRowCount < ATTACHMENTS_MAX_ROWS_SEND then
    itemRowCount = itemRowCount + 1
  end
  if m.api.SendMailFrame.maxRowsShown and last > 0 and itemRowCount < m.api.SendMailFrame.maxRowsShown then
    itemRowCount = m.api.SendMailFrame.maxRowsShown
  else
    m.api.SendMailFrame.maxRowsShown = itemRowCount
  end

  -- Compute sizes
  local cursorx = 0
  local cursory = itemRowCount - 1
  local marginxl = 8 + 6
  local marginxr = 40 + 6
  local areax = m.api.SendMailFrame:GetWidth() - marginxl - marginxr
  local iconx = m.api.MailAttachment1:GetWidth() + 2
  local icony = m.api.MailAttachment1:GetHeight() + 2
  local gapx1 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND)) / (ATTACHMENTS_PER_ROW_SEND - 1) )
  local gapx2 = m.api.floor( (areax - (iconx * ATTACHMENTS_PER_ROW_SEND) - (gapx1 * (ATTACHMENTS_PER_ROW_SEND - 1))) / 2 )
  local gapy1 = 5
  local gapy2 = 6
  local areay = (gapy2 * 2) + (gapy1 * (itemRowCount - 1)) + (icony * itemRowCount)
  local indentx = marginxl + gapx2 + 17
  local indenty = 170 + gapy2 + icony - 13
  local tabx = (iconx + gapx1) - 3 --this magic number changes the attachment spacing
  local taby = (icony + gapy1)
  local scrollHeight = 249 - areay

  m.api.MailHorizontalBarLeft:SetPoint( "TOPLEFT", m.api.SendMailFrame, "BOTTOMLEFT", 2 + 15, 184 + areay - 14 )

  m.api.SendMailScrollFrame:SetHeight( scrollHeight )
  m.api.SendMailScrollChildFrame:SetHeight( scrollHeight )

  local SendMailScrollFrameTop = ({ m.api.SendMailScrollFrame:GetRegions() })[ 3 ]
  SendMailScrollFrameTop:SetHeight( scrollHeight )
  SendMailScrollFrameTop:SetTexCoord( 0, .484375, 0, scrollHeight / 256 )

  m.api.StationeryBackgroundLeft:SetHeight( scrollHeight )
  m.api.StationeryBackgroundLeft:SetTexCoord( 0, 1, 0, scrollHeight / 256 )


  m.api.StationeryBackgroundRight:SetHeight( scrollHeight )
  m.api.StationeryBackgroundRight:SetTexCoord( 0, 1, 0, scrollHeight / 256 )

  -- Set Items
  for i = 1, ATTACHMENTS_MAX do
    if cursory >= 0 then
      m.api[ "MailAttachment" .. i ]:Enable()
      m.api[ "MailAttachment" .. i ]:Show()
      m.api[ "MailAttachment" .. i ]:SetPoint( "TOPLEFT", "SendMailFrame", "BOTTOMLEFT", indentx + (tabx * cursorx),
        indenty + (taby * cursory) )

      cursorx = cursorx + 1
      if cursorx >= ATTACHMENTS_PER_ROW_SEND then
        cursory = cursory - 1
        cursorx = 0
      end
    else
      m.api[ "MailAttachment" .. i ]:Hide()
    end
  end

  m.api.SendMailFrame_CanSend()
end

function TurtleMail.hook.SendMailRadioButton_OnClick( index )
  if (index == 1) then
    m.api.SendMailSendMoneyButton:SetChecked( 1 );
    m.api.SendMailCODButton:SetChecked( nil );
    m.api.SendMailMoneyText:SetText( m.api.AMOUNT_TO_SEND );
    m.api.SendMailCODAllButton:Disable()
    m.api.SendMailCODAllButtonText:SetTextColor( m.api.GRAY_FONT_COLOR.r, m.api.GRAY_FONT_COLOR.g, m.api.GRAY_FONT_COLOR.b )
  else
    m.api.SendMailSendMoneyButton:SetChecked( nil );
    m.api.SendMailCODButton:SetChecked( 1 );
    m.api.SendMailMoneyText:SetText( m.api.COD_AMOUNT );

    if m.sendmail_num_attachments() > 1 then
      m.api.SendMailCODAllButton:Enable()
      m.api.SendMailCODAllButtonText:SetTextColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
      m.set_cod_text()
    end
  end
  m.api.PlaySound( "igMainMenuOptionCheckBoxOn" );
end

function TurtleMail.hook.ClickSendMailItemButton()
  m.sendmail_set_attachment( m.get_cursor_item() )
end

function TurtleMail.hook.GetContainerItemInfo( bag, slot )
  local ret = pack( m.orig.GetContainerItemInfo( bag, slot ) )
  ret[ 3 ] = ret[ 3 ] or m.sendmail_attached( bag, slot ) and 1 or nil
  return unpack( ret )
end

function TurtleMail.hook.PickupContainerItem( bag, slot )
  if m.sendmail_attached( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      return m.sendmail_remove_attachment( { bag, slot } )
    end
    return m.orig.PickupContainerItem( bag, slot )
  end

  if m.api.GetContainerItemInfo( bag, slot ) then
    if arg1 == "RightButton" and m.api.MailFrame:IsVisible() then
      m.api.MailFrameTab_OnClick( 2 )
      m.sendmail_set_attachment( { bag, slot } )
      return
    else
      m.set_cursor_item( { bag, slot } )
    end
  end
  return m.orig.PickupContainerItem( bag, slot )
end

function TurtleMail.hook.SplitContainerItem( bag, slot, amount )
  if m.sendmail_attached( bag, slot ) then return end
  return m.orig.SplitContainerItem( bag, slot, amount )
end

function TurtleMail.hook.UseContainerItem( bag, slot, onself )
  if m.sendmail_attached( bag, slot ) then return end
  if m.api.IsShiftKeyDown() or m.api.IsControlKeyDown() or m.api.IsAltKeyDown() then
    return m.orig.UseContainerItem( bag, slot, onself )
  elseif m.api.MailFrame:IsVisible() then
    m.api.MailFrameTab_OnClick( 2 )
    m.sendmail_set_attachment( { bag, slot } )
  elseif m.api.TradeFrame:IsVisible() then
    for i = 1, 6 do
      if not m.api.GetTradePlayerItemLink( i ) then
        m.orig.PickupContainerItem( bag, slot )
        m.api.ClickTradeButton( i )
        return
      end
    end
  else
    return m.orig.UseContainerItem( bag, slot, onself )
  end
end

function TurtleMail.hook.SendMailFrame_CanSend()
  if not m.sendmail_sending and string.len( m.api.SendMailNameEditBox:GetText() ) > 0 and (m.api.SendMailSendMoneyButton:GetChecked() and m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ) or 0) + m.api.GetSendMailPrice() * math.max( 1, m.sendmail_num_attachments() ) <= m.api.GetMoney() then
    MailMailButton:Enable()
  else
    MailMailButton:Disable()
  end
end

--[[ Both log tabs together. They are one feature and one switch, so a caller
     that showed one and forgot the other would leave half a pair of tabs on a
     frame the client has already sized for them. ]]--
--[==[ **The tabs are always there.**

     They used to be hidden while logging was off, which hides the only thing on
     screen that could explain an empty history -- and the only way to find out
     the feature exists at all. A tab that says "nothing here yet, and here is
     how to start" is worth more than no tab.

     The `on` argument is kept because two callers pass it and because switching
     logging off should still say something; it decides what the page reads, not
     whether the tabs exist. ]==]
---@param on boolean
function TurtleMail.log_tabs( on )
  m.api.MailFrameTab3:Show()
  m.api.MailFrameTab4:Show()
end

--[==[ **Which log a tab means, in one place.**

     Tab three is Sent and tab four is Received. Written as a table rather than
     as two comparisons because three other places ask the same question, and a
     fourth tab added later should not need any of them changed. ]==]
TurtleMail.LOG_TAB = { [ 3 ] = "Sent", [ 4 ] = "Received" }

function TurtleMail.hook.MailFrameTab_OnClick( tab )
  if not tab then
    tab = this:GetID()
  end

  local log_type = m.LOG_TAB[ tab ]

  if log_type then
    m.api.PanelTemplates_SetTab( m.api.MailFrame, tab )
    m.api.InboxFrame:Hide()
    m.api.SendMailFrame:Hide()
    m.api.TurtleMailLogFrame:Show()
    m.api.MailFrameTopLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopLeft" )
    m.api.MailFrameTopRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopRight" )
    m.api.MailFrameBotLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotLeft" )
    m.api.MailFrameBotRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotRight" )
    m.api.MailFrameTopLeft:SetPoint( "TOPLEFT", "MailFrame", "TOPLEFT", 2, -1 )

    --[[ The page is per log now, so the filter and the date range somebody set
         on Sent do not follow them into Received. They are different
         questions. ]]--
    m.log.populate( log_type )
    return
  else
    m.api.TurtleMailLogFrame:Hide()
  end

  m.orig.MailFrameTab_OnClick( tab )
end

function TurtleMail.hook.OpenMailFrame_OnHide()
  if m.api.InboxFrame.openMailID then
    local package_icon, _, sender, subject, money, cod, _, itemID, _, returned, text_created, _, gm = m.api.GetInboxHeaderInfo( m.api.InboxFrame.openMailID )
    if (money == 0 and not itemID and text_created) then
      local received_item = m.api.GetInboxItem( m.api.InboxFrame.openMailID )
      m.log.add( "Received", {
        from = sender,
        subject = subject,
        money = money,
        cod = cod,
        returned = returned,
        gm = gm,
        icon = package_icon,
        item = received_item
      } )
    end
  else
    m.debug( "returning mail" )
  end

  m.orig.OpenMailFrame_OnHide()
end

function TurtleMail.send_mail_button_onclick()
  m.api.MailAutoCompleteBox:Hide()

  m.api.TurtleMail_To = m.api.SendMailNameEditBox:GetText()
  m.api.SendMailNameEditBox:HighlightText()

  m.sendmail_state = {
    to = m.api.TurtleMail_To,
    subject = MailSubjectEditBox:GetText(),
    body = m.api.SendMailBodyEditBox:GetText(),
    money = m.api.MoneyInputFrame_GetCopper( m.api.SendMailMoney ),
    cod = m.api.SendMailCODButton:GetChecked(),
    attachments = m.sendmail_attachments(),
    numMessages = math.max( 1, m.sendmail_num_attachments() ),
  }

  m.sendmail_clear()
  m.sendmail_sending = true
  m.sendmail_send()
end

function TurtleMail.sendmail_load()
  m.api.SendMailFrame:EnableMouse( false )

  m.api.SendMailFrame:CreateTexture( "MailHorizontalBarLeft", "BACKGROUND" )
  m.api.MailHorizontalBarLeft:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.api.MailHorizontalBarLeft:SetWidth( 256 )
  m.api.MailHorizontalBarLeft:SetHeight( 16 )
  m.api.MailHorizontalBarLeft:SetTexCoord( 0, 1, 0, .25 )

  m.api.SendMailFrame:CreateTexture( "MailHorizontalBarRight", "BACKGROUND" )
  m.api.MailHorizontalBarRight:SetTexture( "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar" )
  m.api.MailHorizontalBarRight:SetWidth( 75 )
  m.api.MailHorizontalBarRight:SetHeight( 16 )
  m.api.MailHorizontalBarRight:SetTexCoord( 0, .29296875, .25, .5 )
  m.api.MailHorizontalBarRight:SetPoint( "LEFT", m.api.MailHorizontalBarLeft, "RIGHT" )

  m.api.SendMailMoneyText:SetJustifyH( "LEFT" )
  m.api.SendMailMoneyText:SetPoint( "TOPLEFT", 0, 0 )
  m.api.SendMailMoney:ClearAllPoints()
  m.api.SendMailMoney:SetPoint( "TOPLEFT", m.api.SendMailMoneyText, "BOTTOMLEFT", 5, -5 )
  m.api.SendMailMoneyGoldRight:SetPoint( "RIGHT", 20, 0 )
  do ({ m.api.SendMailMoneyGold:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneyGold:SetMaxLetters( 7 )
  m.api.SendMailMoneyGold:SetWidth( 50 )
  m.api.SendMailMoneySilverRight:SetPoint( "RIGHT", 10, 0 )
  do ({ m.api.SendMailMoneySilver:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneySilver:SetWidth( 28 )
  m.api.SendMailMoneySilver:SetPoint( "LEFT", m.api.SendMailMoneyGold, "RIGHT", 30, 0 )
  m.api.SendMailMoneyCopperRight:SetPoint( "RIGHT", 10, 0 )
  do ({ m.api.SendMailMoneyCopper:GetRegions() })[ 9 ]:SetDrawLayer( "BORDER" ) end
  m.api.SendMailMoneyCopper:SetWidth( 28 )
  m.api.SendMailMoneyCopper:SetPoint( "LEFT", m.api.SendMailMoneySilver, "RIGHT", 20, 0 )
  m.api.SendMailSendMoneyButton:SetPoint( "TOPLEFT", m.api.SendMailMoney, "TOPRIGHT", 0, 12 )

  -- hack to avoid automatic subject setting and button disabling from weird blizzard code
  MailMailButton = m.api.SendMailMailButton
  m.api.SendMailMailButton = setmetatable( {}, { __index = function() return function() end end } )
  m.api.SendMailMailButton_OnClick = m.send_mail_button_onclick
  MailSubjectEditBox = m.api.SendMailSubjectEditBox
  m.api.SendMailSubjectEditBox = setmetatable( {}, {
    __index = function( _, key )
      return function( _, ... )
        return MailSubjectEditBox[ key ]( MailSubjectEditBox, unpack( arg ) )
      end
    end,
  } )

  m.api.SendMailNameEditBox._SetText = m.api.SendMailNameEditBox.SetText
  function m.api.SendMailNameEditBox:SetText( ... )
    if not m.api.TurtleMail_To then
      return self:_SetText( unpack( arg ) )
    end
  end

  m.api.SendMailNameEditBox:SetScript( "OnShow", function()
    if m.api.TurtleMail_To then
      m.api.this:_SetText( m.api.TurtleMail_To )
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnChar", function()
    m.api.TurtleMail_To = nil
    GetSuggestions()
  end )
  m.api.SendMailNameEditBox:SetScript( "OnTabPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      if m.api.IsShiftKeyDown() then
        m.previous_match()
      else
        m.next_match()
      end
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEnterPressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
      this:HighlightText( 0, 0 )
    else
      MailSubjectEditBox:SetFocus()
    end
  end )
  m.api.SendMailNameEditBox:SetScript( "OnEscapePressed", function()
    if m.api.MailAutoCompleteBox:IsVisible() then
      m.api.MailAutoCompleteBox:Hide()
    else
      this:ClearFocus()
    end
  end )
  function m.api.SendMailNameEditBox.focusLoss()
    m.api.MailAutoCompleteBox:Hide()
  end

  m.api.SendMailCODAllButtonText:SetText( "  " .. L[ "All mails" ] )
  m.api.SendMailCODAllButton:SetScript( "OnClick", m.set_cod_text )

  do
    local orig_script = m.api.SendMailNameEditBox:GetScript( "OnTextChanged" )
    m.api.SendMailNameEditBox:SetScript( "OnTextChanged", function()
      local text = this:GetText()
      local formatted = string.gsub( string.lower( text ), "^%l", string.upper )
      if text ~= formatted then
        this:SetText( formatted )
      end
      return orig_script()
    end )
  end

  for _, editBox in { m.api.SendMailNameEditBox, m.api.SendMailSubjectEditBox } do
    editBox:SetScript( "OnEditFocusGained", function()
      this:HighlightText()
    end )
    editBox:SetScript( "OnEditFocusLost", function()
      (this.focusLoss or function() end)()
      this:HighlightText( 0, 0 )
    end )
    do
      local lastClick
      editBox:SetScript( "OnMouseDown", function()
        local x, y = m.api.GetCursorPosition()
        if lastClick and m.api.GetTime() - lastClick.t < .5 and x == lastClick.x and y == lastClick.y then
          this:SetScript( "OnUpdate", function()
            this:HighlightText()
            this:SetScript( "OnUpdate", nil )
          end )
        end
        lastClick = { t = m.api.GetTime(), x = x, y = y }
      end )
    end
  end
end

--@param bag number
--@param slot number
function TurtleMail.sendmail_attached( bag, slot )
  if not m.api.MailFrame:IsVisible() then return false end
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item and btn.item[ 1 ] == bag and btn.item[ 2 ] == slot then
      return true
    end
  end
  if m.sendmail_state then
    for _, attachment in m.sendmail_state.attachments do
      if attachment[ 1 ] == bag and attachment[ 2 ] == slot then
        return true
      end
    end
  end
end

function TurtleMail.attachment_button_on_click()
  local attachedItem = this.item
  local cursorItem = m.get_cursor_item()
  if m.sendmail_set_attachment( cursorItem, this ) then
    if attachedItem then
      if arg1 == "LeftButton" then m.set_cursor_item( attachedItem ) end
      m.orig.PickupContainerItem( unpack( attachedItem ) )
      if arg1 ~= "LeftButton" then m.api.ClearCursor() end -- for the lock changed event
    end
  end
end

function TurtleMail.sendmail_remove_attachment( item )
  if not item then return end
  if type( item ) == "table" and m.sendmail_attached( item[ 1 ], item[ 2 ] ) then
    for i = 1, ATTACHMENTS_MAX do
      local btn = m.api[ "MailAttachment" .. i ]
      if btn.item and btn.item[ 1 ] == item[ 1 ] and btn.item[ 2 ] == item[ 2 ] then
        m.api[ "MailAttachment" .. i ].item = nil
        m.orig.PickupContainerItem( unpack( item ) )
        m.api.ClearCursor()
        m.api.SendMailFrame_Update()
        return
      end
    end
  end
end

-- requires an item lock changed event for a proper update
---@param item table
---@param slot number?
function TurtleMail.sendmail_set_attachment( item, slot )
  if item and not m.sendmail_pickup_mailable( item ) then
    m.api.ClearCursor()
    return
  elseif not slot then
    for i = 1, ATTACHMENTS_MAX do
      if not m.api[ "MailAttachment" .. i ].item then
        slot = m.api[ "MailAttachment" .. i ]
        break
      end
    end
  end
  if slot then
    if not (item or slot.item) then return true end
    slot.item = item
    m.api.ClearCursor()
    m.api.SendMailFrame_Update()
    return true
  end
end

---@param item table
function TurtleMail.sendmail_pickup_mailable( item )
  m.api.ClearCursor()
  m.orig.ClickSendMailItemButton()
  m.api.ClearCursor()
  m.orig.PickupContainerItem( unpack( item ) )
  m.orig.ClickSendMailItemButton()
  local mailable = m.api.GetSendMailItem() and true or false
  m.orig.ClickSendMailItemButton()
  return mailable
end

function TurtleMail.sendmail_num_attachments()
  local x = 0
  for i = 1, ATTACHMENTS_MAX do
    if m.api[ "MailAttachment" .. i ].item then
      x = x + 1
    end
  end
  return x
end

function TurtleMail.sendmail_attachments()
  local t = {}
  for i = 1, ATTACHMENTS_MAX do
    local btn = m.api[ "MailAttachment" .. i ]
    if btn.item then
      table.insert( t, btn.item )
    end
  end
  return t
end

function TurtleMail.sendmail_clear()
  local anyItem
  for i = 1, ATTACHMENTS_MAX do
    anyItem = anyItem or m.api[ "MailAttachment" .. i ].item
    m.api[ "MailAttachment" .. i ].item = nil
  end
  if anyItem then
    m.api.ClearCursor()
    m.api.PickupContainerItem( unpack( anyItem ) )
    m.api.ClearCursor()
  end
  MailMailButton:Disable()
  m.api.SendMailNameEditBox:SetText ""
  m.api.SendMailNameEditBox:SetFocus()
  MailSubjectEditBox:SetText ""
  m.api.SendMailBodyEditBox:SetText ""
  m.api.MoneyInputFrame_ResetMoney( m.api.SendMailMoney )
  m.api.SendMailRadioButton_OnClick( 1 )

  m.api.SendMailFrame_Update()
end

function TurtleMail.sendmail_send()
  local item = table.remove( m.sendmail_state.attachments, 1 )
  if item then
    m.api.ClearCursor()
    m.orig.ClickSendMailItemButton()
    m.api.ClearCursor()
    m.orig.PickupContainerItem( unpack( item ) )
    m.orig.ClickSendMailItemButton()

    if not m.api.GetSendMailItem() then
      m.api.DEFAULT_CHAT_FRAME:AddMessage( "|cffabd473TurtleMail|r: " .. m.api.ERROR_CAPS, 1, 0, 0 )

      --[==[ **This left the send half-run, and that is the second reload bug.**

           The attachment was taken off the front of the list by the
           `table.remove` above, and this path returned without putting it back
           and without clearing `sendmail_sending`. Two consequences, both
           reported as mail not sending until a reload:

           The run never ends. `MAIL_SEND_SUCCESS` asks `on_update` to call this
           again while `sendmail_sending` is set, so the next success -- from
           any mail at all -- re-enters a send whose attachment list has already
           been eaten.

           And the item is simply gone from the letter. Put back at the front,
           because it is the one this attempt was for and the next attempt
           should start there.

           `MAIL_CLOSED` clears the flag, which is why this recovers sometimes
           and not others: it depends on whether the mailbox gets closed before
           the next send is tried. ]==]
      table.insert( m.sendmail_state.attachments, 1, item )

      m.sendmail_sending = false
      m.sendmail_state = nil

      m.api.ClearCursor()

      return
    end
  end

  local amount = m.sendmail_state.money
  m.sendmail_state.sent_money = m.sendmail_state.money
  m.sendmail_state.sent = false

  if amount > 0 then
    if not m.api.SendMailCODAllButton:GetChecked() then
      m.sendmail_state.money = 0
    end
    if m.sendmail_state.cod then
      m.sendmail_state.cod = amount
      m.api.SetSendMailCOD( amount )
    else
      m.sendmail_state.money = 0
      m.api.SetSendMailMoney( amount )
    end
  end

  local subject = m.sendmail_state.subject
  if subject == "" then
    if item then
      local item_name, texture, stack_count = m.api.GetSendMailItem()
      subject = item_name .. (stack_count > 1 and " (" .. stack_count .. ")" or "")
      m.sendmail_state.item = item_name
      m.sendmail_state.icon = texture
    else
      subject = "<" .. m.api.NO_ATTACHMENTS .. ">"
    end
  elseif m.sendmail_state.numMessages > 1 then
    subject = subject .. string.format( " [%d/%d]", m.sendmail_state.numMessages - getn( m.sendmail_state.attachments ),
      m.sendmail_state.numMessages )
  end

  m.sendmail_state.sent_subject = subject

  m.debug( "SendMail" )
  m.api.SendMail( m.sendmail_state.to, subject, m.sendmail_state.body )

  if getn( m.sendmail_state.attachments ) == 0 then
    m.sendmail_sending = false
  end
end

do
  local inputLength
  local matches = {}
  local index

  local function complete()
    m.api.SendMailNameEditBox:SetText( matches[ index ] )
    m.api.SendMailNameEditBox:HighlightText( inputLength, -1 )
    for i = 1, m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
      local button = m.api[ "MailAutoCompleteButton" .. i ]
      if i == index then
        button:LockHighlight()
      else
        button:UnlockHighlight()
      end
    end
  end

  function TurtleMail.previous_match()
    if index then
      index = index > 1 and index - 1 or getn( matches )
      complete()
    end
  end

  function TurtleMail.next_match()
    if index then
      ---@diagnostic disable-next-line: undefined-global
      index = mod( index, getn( matches ) ) + 1
      complete()
    end
  end

  function TurtleMail.select_match( i )
    index = i
    complete()
    m.api.MailAutoCompleteBox:Hide()
    m.api.SendMailNameEditBox:HighlightText( 0, 0 )
  end

  --[[ The name a row is showing, without the pin mark that may be painted on
       the front of it. Read from the list rather than off the button, because
       the button's text is decorated and the list is the truth. ]]--
  function TurtleMail.match_name( i )
    return matches[ i ]
  end

  --[==[ **Three gestures on one row.**

       Left click picks the name, which is what it always did and must keep
       doing -- anything else here would be a trap.

       Right click forgets it. Asked for because a name typed wrong, or one that
       does not exist, used to sit in the list for good.

       Shift-click pins it to the top and pins are the first sort key.

       Dispatched in one place so the row's own handler stays a single line, and
       so the order between them is written down once: right click wins over
       shift, because somebody holding shift and right-clicking is far more
       likely to mean "get rid of it" than "pin it". ]==]
  function TurtleMail.autocomplete_click( i, button )
    local name = matches[ i ]
    if not name then return end

    if button == "RightButton" then
      if m.forget_name( name ) then
        m.info( string.format( "%s forgotten.", name ) )
      end

      GetSuggestions()
      return
    end

    if m.api.IsShiftKeyDown and m.api.IsShiftKeyDown() then
      local pinned = m.toggle_favourite( name )
      m.info( string.format( pinned and "%s pinned to the top." or "%s unpinned.", name ) )
      GetSuggestions()
      return
    end

    m.select_match( i )
  end

  --[[ Said on the row itself, because three gestures on one control is two more
       than anybody guesses at. ]]--
  function TurtleMail.autocomplete_tooltip( button )
    local name = matches[ button:GetID() ]
    if not name or not m.api.GameTooltip then return end

    m.api.GameTooltip:SetOwner( button, "ANCHOR_RIGHT" )
    m.api.GameTooltip:SetText( name )
    m.api.GameTooltip:AddLine( m.is_favourite( name )
        and "Shift-click to unpin" or "Shift-click to pin to the top",
        0.8, 0.8, 0.8, 1 )
    m.api.GameTooltip:AddLine( "Right click to forget", 0.8, 0.8, 0.8, 1 )
    m.api.GameTooltip:Show()
  end

  function GetSuggestions()
    local input = m.api.SendMailNameEditBox:GetText()
    inputLength = string.len( input )

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, 0 )
    index = nil

    local autoCompleteNames = {}
    for name, time in m.api.TurtleMail_AutoCompleteNames[ m.api.GetCVar "realmName" .. "|" .. m.api.UnitFactionGroup "player" ] do
      table.insert( autoCompleteNames, { name = name, time = time } )
    end
    --[==[ **Favourites first, then newest.**

         Sorting by time alone is right until the list is long: the bank alt
         written to every day sinks under a stranger sold something to this
         morning. A pin is somebody saying which of those they meant.

         The two keys in one comparison rather than two passes, because
         `table.sort` needs a total order and stitching two sorted lists
         together would put the boundary somewhere this does not have to reason
         about. ]==]
    table.sort( autoCompleteNames, function( a, b )
      local fa, fb = m.is_favourite( a.name ), m.is_favourite( b.name )
      if fa ~= fb then return fa end
      return b.time < a.time
    end )

    local ignore = { [ m.api.UnitName "player" ] = true }
    local function process( name )
      if name then
        if not ignore[ name ] and string.find( string.upper( name ), string.upper( input ), nil, true ) == 1 then
          table.insert( matches, name )
        end
        ignore[ name ] = true
      end
    end
    for _, t in autoCompleteNames do
      process( t.name )
    end
    for i = 1, m.api.GetNumFriends() do
      process( m.api.GetFriendInfo( i ) )
    end
    for i = 1, m.api.GetNumGuildMembers( true ) do
      process( m.api.GetGuildRosterInfo( i ) )
    end

    ---@diagnostic disable-next-line: undefined-field
    table.setn( matches, math.min( getn( matches ), m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS ) )
    if getn( matches ) > 0 and (getn( matches ) > 1 or input ~= matches[ 1 ]) then
      for i = 1, m.api.MAIL_AUTOCOMPLETE_MAX_BUTTONS do
        local button = m.api[ "MailAutoCompleteButton" .. i ]
        if i <= getn( matches ) then
          --[[ A pinned name says so. Without a mark the ordering is the only
               evidence a pin took, and the top of a list is where a name might
               have been anyway. ]]--
          if m.is_favourite( matches[ i ] ) then
            button:SetText( "|cffffd100*|r " .. matches[ i ] )
          else
            button:SetText( matches[ i ] )
          end

          button:GetFontString():SetPoint( "LEFT", button, "LEFT", 15, 0 )
          button:Show()
        else
          button:Hide()
        end
      end
      m.api.MailAutoCompleteBox:SetHeight( getn( matches ) * m.api.MailAutoCompleteButton1:GetHeight() + 35 )
      m.api.MailAutoCompleteBox:SetWidth( 120 )
      m.api.MailAutoCompleteBox:Show()
      index = 1
      complete()
    else
      m.api.MailAutoCompleteBox:Hide()
    end
  end
end

function TurtleMail.log.load()
  m.api.TurtleMailLogTitleText:SetText( L[ "Log" ] )

  --[[ The tabs are the switch now, so the two buttons that used to do it are
       put away rather than deleted: pfUI's skinning pass still reaches for them
       by name, and a nil there would throw in somebody else's addon. ]]--
  m.api.MailFrameTab3:SetText( L[ "Sent" ] or "Sent" )
  m.api.MailFrameTab4:SetText( L[ "Received" ] or "Received" )

  if m.api.TurtleMailLogSentButton then m.api.TurtleMailLogSentButton:Hide() end
  if m.api.TurtleMailLogReceivedButton then m.api.TurtleMailLogReceivedButton:Hide() end

  local font_file = m.pfui_skin_enabled and m.api.pfUI.font_default or "FONTS\\ARIALN.TTF"
  local font_size = 11

  for i = 1, 10 do
    m.api[ "TurtleMailLogItem" .. i .. "Background" ]:SetVertexColor( .5, .5, .5, 0.6 )
    m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetJustifyH( "LEFT" )
    m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetJustifyH( "RIGHT" )
    m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Subject" ]:SetJustifyH( "LEFT" )
    m.api[ "TurtleMailLogItem" .. i .. "Subject" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetTextColor( 1, 1, 1, 1 )
    m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetJustifyH( "LEFT" )
    m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetFont( font_file, font_size )
    m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetVertexColor( m.api.NORMAL_FONT_COLOR.r, m.api.NORMAL_FONT_COLOR.g, m.api.NORMAL_FONT_COLOR.b )
    if i > 1 then
      m.api[ "TurtleMailLogItem" .. i ]:SetPoint( "TOPLEFT", m.api[ "TurtleMailLogItem" .. i - 1 ], "BOTTOMLEFT", 0, -1 )
    end
  end
  m.api.TurtleMailLogItem10Background:Hide()

  m.api.TurtleMailLogStatusText:SetTextColor( 1, 1, 1, 1 )
  m.api.TurtleMailLogStatusText:SetFont( "Fonts\\FRIZQT__.TTF", 10 )
  m.api.TurtleMailLogScrollFrameScrollBar:SetValueStep( 1 )
  m.api.TurtleMailLogScrollFrameScrollBar:SetScript( "OnValueChanged", m.log.on_scroll_value_changed )

  m.api.TurtleMailLogScrollFrame:SetScript( "OnMouseWheel", function()
    m.log.scroll( arg1 * 10 )
  end )
  m.api.TurtleMailLogScrollFrameScrollBarScrollUpButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( 10 )
  end )
  m.api.TurtleMailLogScrollFrameScrollBarScrollDownButton:SetScript( "OnClick", function()
    m.api.PlaySound( "UChatScrollButton" );
    m.log.scroll( -10 )
  end )

  m.api.TurtleMailLogFiltersButton:SetText( L[ "Filters" ] )
  m.api.TurtleMailLogFiltersButton:GetFontString():SetPoint( "LEFT", m.api.TurtleMailLogFiltersButton, "LEFT", 10, 0 )

  m.api.TurtleMailLogFiltersButton:SetScript( "OnMouseDown", function()
    m.api.TurtleMailLogFiltersButtonArrow:SetPoint( "RIGHT", m.pfui_skin_enabled and -4 or -8, -3 )
  end )
  m.api.TurtleMailLogFiltersButton:SetScript( "OnMouseUp", function()
    m.api.TurtleMailLogFiltersButtonArrow:SetPoint( "RIGHT", m.pfui_skin_enabled and -4 or -8, -1 )
  end )

  m.api.TurtleMailLogStartTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.TurtleMailLogStartTimeButton:SetScale( 0.9 )
  m.api.TurtleMailLogEndTimeText:SetTextColor( 1, 1, 1, 1 )
  m.api.TurtleMailLogEndTimeButton:SetScale( 0.9 )

  m.api.TurtleMailLogStartTime:SetScript( "OnClick", function()
    m.api.TurtleMailLogStartTimeText:SetText( "" )
    m[ m.current_log_type .. "_start_time" ] = nil
    m.log.populate( m.current_log_type )
  end )
  m.api.TurtleMailLogEndTime:SetScript( "OnClick", function()
    m.api.TurtleMailLogEndTimeText:SetText( "" )
    m[ m.current_log_type .. "_end_time" ] = nil
    m.log.populate( m.current_log_type )
  end )

  m.api.TurtleMailLogPlayersDropDown:SetScale( 0.9 )
  m.api.UIDropDownMenu_SetText( "All players", m.api.TurtleMailLogPlayersDropDown )

  m.dropdown_filters = m.api.CreateFrame( "Frame", "TurtleMailDropDownFilters" )
  m.dropdown_filters.displayMode = "MENU"
  m.dropdown_filters.info = {}
end

function TurtleMail.log.players_dropdown_on_load()
  m.api.UIDropDownMenu_Initialize( m.api.TurtleMailLogPlayersDropDown, function()
    local info = {}
    info.notCheckable = 1
    info.text = "All players"
    info.arg1 = info.text
    info.arg2 = "All"
    info.func = m.log.select_player
    m.api.UIDropDownMenu_AddButton( info )

    if not m.current_log_type then return end

    local players = {}
    for _, v in ipairs( m.api.TurtleMail_Log[ m.current_log_type ] ) do
      if v then
        players[ v.participant ] = players[ v.participant ] and players[ v.participant ] + 1 or 1
      end
    end

    for player, count in pairs( players ) do
      info.text = player .. " (" .. count .. ")"
      info.arg1 = player
      info.arg2 = nil
      m.api.UIDropDownMenu_AddButton( info )
    end
  end )
end

function TurtleMail.log.select_player( player, is_all )
  m.api.UIDropDownMenu_SetText( player, m.api.TurtleMailLogPlayersDropDown )
  if is_all then
    m.filter_player = nil
  else
    m.filter_player = player
  end
  m.log.populate( m.current_log_type )
end

function TurtleMail.log.filter_dropdown()
  if m.dropdown_filters.initialize ~= TurtleMail.log.filters_menu then
    m.api.CloseDropDownMenus()
    m.dropdown_filters.initialize = TurtleMail.log.filters_menu
  end
  m.api.ToggleDropDownMenu( 1, nil, m.dropdown_filters, this:GetName(), 0, 0 )
end

function TurtleMail.log.filters_menu( level )
  local filters = m.api.TurtleMail_Log[ "Settings" ][ m.current_log_type .. "Filters" ] or {}
  local info = {}
  info.keepShownOnClick = 1

  local values = { "Money", "COD", "Other" }
  if m.current_log_type == "Received" then
    table.insert( values, "Returned" )
    table.insert( values, "AH" )
  end

  if level == 1 then
    for _, filter in values do
      info.text = L[ filter ]
      info.checked = filters[ filter ]
      info.arg1 = filter
      info.func = m.log.toggle_filter
      if filter == "AH" then info.hasArrow = 1 end

      m.api.UIDropDownMenu_AddButton( info, level )
    end
  elseif level == 2 then
    for _, filter in { "Sold", "Cancelled", "Expired", "Won", "Outbid" } do
      info.text = L[ filter ]
      info.checked = filters[ "AH" .. filter ]
      info.arg1 = filter
      info.arg2 = "AH"
      info.func = m.log.toggle_filter
      m.api.UIDropDownMenu_AddButton( info, level )
    end
  end
end

function TurtleMail.log.toggle_filter( filter, parent_filter )
  if not parent_filter then parent_filter = "" end
  local filter_value = m.api.TurtleMail_Log[ "Settings" ][ m.current_log_type .. "Filters" ][ parent_filter .. filter ]

  m.api.TurtleMail_Log[ "Settings" ][ m.current_log_type .. "Filters" ][ parent_filter .. filter ] = not filter_value
  m.log.populate( m.current_log_type )
end

function TurtleMail.log.show_calendar()
  if m.calendar.is_visible() then
    m.calendar.hide()
  else
    local text = string.gsub( this:GetName(), "Button", "Text" )
    m.calendar.show( m.api.TurtleMail_Log[ m.current_log_type ], time(), this, function( selected_date )
      local date_str = date( L[ "date_format" ], selected_date )
      m.api[ text ]:SetText( date_str )

      local v = m.current_log_type .. (string.find( text, "Start" ) and "_start_time" or "_end_time")
      m[ v ] = selected_date
      m.log.populate( m.current_log_type )
    end )
  end
end

function TurtleMail.log.scroll( step )
  local scroll_bar = m.api.TurtleMailLogScrollFrameScrollBar
  local current = scroll_bar:GetValue()
  local min, max = scroll_bar:GetMinMaxValues()
  local new = current - step

  if new >= max then
    scroll_bar:SetValue( max )
  elseif new <= min then
    scroll_bar:SetValue( 0 )
  else
    scroll_bar:SetValue( new )
  end
end

function TurtleMail.log.on_scroll_value_changed()
  local function round( num )
    return num + (2 ^ 52 + 2 ^ 51) - (2 ^ 52 + 2 ^ 51)
  end

  local scrollBar = m.api.TurtleMailLogScrollFrameScrollBar
  local scrollUp = m.api.TurtleMailLogScrollFrameScrollBarScrollUpButton
  local scrollDown = m.api.TurtleMailLogScrollFrameScrollBarScrollDownButton

  local minVal, maxVal = scrollBar:GetMinMaxValues()
  local currentVal = round( scrollBar:GetValue() )

  if currentVal <= round( minVal ) then
    scrollUp:Disable()
  else
    scrollUp:Enable()
  end

  if currentVal >= round( maxVal ) then
    scrollDown:Disable()
  else
    scrollDown:Enable()
  end

  m.log.populate( m.current_log_type, currentVal )
end

---@alias LogType
---| "Sent"
---| "Received"

---@param log_type LogType
---@param state table
function TurtleMail.log.add( log_type, state )
  if not m.log_enabled then return end
  m.debug( "Logging " .. log_type .. " message" )

  local data = {
    timestamp = time(),
    icon = state.icon,
    item = state.item
  }

  if state.cod and state.cod > 0 then data.cod = tonumber( state.cod ) end
  if log_type == "Sent" then
    data.participant = state.to
    data.subject = state.sent_subject
    if state.send_money and state.sent_money > 0 then data.money = tonumber( state.sent_money ) end
  else -- Received
    data.participant = state.from
    data.subject = state.subject
    data.returned = state.returned
    data.gm = state.gm

    if state.money and state.money > 0 then data.money = tonumber( state.money ) end

    if string.find( data.subject, string.gsub( m.api.AUCTION_SOLD_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Sold"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_REMOVED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Removed"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Expired"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_WON_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Won"
    elseif string.find( data.subject, string.gsub( m.api.AUCTION_OUTBID_MAIL_SUBJECT, "%%s", "" ) ) then
      data[ "ah" ] = "Outbid"
    end
  end

  table.insert( m.api.TurtleMail_Log[ log_type ], data )
end

---@param log_type LogType
---@param index number?
function TurtleMail.log.populate( log_type, index )
  m.current_log_type = log_type

  --[[ Said at the top of the page as well as on the tab, because the tab is
       small and the page is what somebody is reading. ]]--
  if m.api.TurtleMailLogTitleText then
    m.api.TurtleMailLogTitleText:SetText(
        (L[ log_type ] or log_type) .. " " .. (L[ "Log" ] or "Log") )
  end
  local filters = m.api.TurtleMail_Log[ "Settings" ][ log_type .. "Filters" ] or {}
  local start_time = m[ log_type .. "_start_time" ]
  local end_time = m[ log_type .. "_end_time" ]
  if start_time then start_time = start_time - 43200 end
  if end_time then end_time = end_time + 43140 end

  local log = m.filter( m.api.TurtleMail_Log[ log_type ], function( item )
    local ret =
        (filters.Money and item.money and item.money > 0 and (not item.cod or item.cod == 0) and not item.ah)
        or
        (filters.COD and item.cod and item.cod > 0)
        or
        (filters.Other and (not item.cod or item.cod == 0) and not item.ah and not item.returned and (not item.money or item.money == 0))
        or
        (filters.Returned and item.returned)
        or
        (filters.AH and filters.AHWon and item.ah == "Won")
        or
        (filters.AH and filters.AHSold and item.ah == "Sold")
        or
        (filters.AH and filters.AHCancelled and item.ah == "Removed")
        or
        (filters.AH and filters.AHOutbid and item.ah == "Outbid")
        or
        (filters.AH and filters.AHExpired and item.ah == "Expired")

    if m.filter_player then
      ret = ret and item.participant == m.filter_player
    end
    if start_time then
      ret = ret and item.timestamp >= start_time
    end
    if end_time then
      ret = ret and item.timestamp <= end_time
    end

    return ret
  end )

  m.api.TurtleMailLogStartTimeText:SetText( start_time and date( L[ "date_format" ], start_time ) or "" )
  m.api.TurtleMailLogEndTimeText:SetText( end_time and date( L[ "date_format" ], end_time ) or "" )

  if not log then return end
  local log_count = getn( log )

  m.api.TurtleMailLogScrollFrameScrollBar:SetMinMaxValues( 0, math.max( 0, log_count - 10 ) )

  if not index then
    m.api.TurtleMailLogScrollFrameScrollBar:SetValue( log_count - 10 )
    m.api.TurtleMailLogScrollFrameScrollBar:SetScript( "OnUpdate", function()
      m.api.TurtleMailLogScrollFrameScrollBar:SetValue( log_count - 10 )
      m.api.TurtleMailLogScrollFrameScrollBar:SetScript( "OnUpdate", nil )
    end )

    index = math.max( 0, log_count - 10 )
  end

  m.api.TurtleMailLogTitleText:SetText( string.format( "%s %s", L[ log_type ], L[ "Log" ] ) )
  --[==[ **An empty page says which kind of empty it is.**

       Nothing recorded yet and nothing recorded *ever* look identical, and only
       one of them is something the reader can do anything about. ]==]
  if log_count == 0 and not m.log_enabled then
    m.api.TurtleMailLogStatusText:SetText(
        "Logging is off -- type /tm log to start recording" )
  elseif log_count == 0 then
    m.api.TurtleMailLogStatusText:SetText( "Nothing here yet" )
  else
    m.api.TurtleMailLogStatusText:SetText( string.format( "Showing %d-%d of %d", (index == 0 and log_count == 0) and index or index + 1,
    math.min( log_count, index + 10 ), log_count ) )
  end

  for i = 1, 10 do
    if log[ index + i ] then
      local entry = log[ index + i ]

      m.api[ "TurtleMailLogItem" .. i .. "IconTexture" ]:SetTexture( entry.icon or "Interface/Icons/INV_Misc_Note_01" )
      m.api[ "TurtleMailLogItem" .. i .. "Icon" ].item = entry.item
      m.api[ "TurtleMailLogItem" .. i .. "TimeStamp" ]:SetText( date( L[ "date_format" ] .. " " .. L[ "time_format" ], entry.timestamp ) )
      m.api[ "TurtleMailLogItem" .. i .. "Subject" ]:SetText( entry.subject )

      m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetTexture( "" )
      if entry.ah then
        m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetText( "" )
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetTexture( "Interface\\Addons\\TurtleMail\\TurtleMail-AH.blp" )
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetPoint( "TOPRIGHT", 4, -10 )
      else
        m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:SetText( entry.participant )
      end
      if entry.returned then
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetTexture( "Interface\\Addons\\TurtleMail\\TurtleMail-RetArrow.blp" )
        local w = m.api[ "TurtleMailLogItem" .. i .. "Participant" ]:GetStringWidth()
        m.api[ "TurtleMailLogItem" .. i .. "Status" ]:SetPoint( "TOPRIGHT", -w + 4, -9 )
      end

      if entry.money and entry.money > 0 then
        local cod = (entry.cod and entry.cod > 0) and "COD: " or " "
        m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetText( cod .. m.format_money( entry.money ) )
      elseif entry.cod then
        m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetText( "COD" .. (entry.cod > 1 and (": " .. m.format_money( entry.cod )) or "") )
      else
        m.api[ "TurtleMailLogItem" .. i .. "Money" ]:SetText( "" )
      end

      m.api[ "TurtleMailLogItem" .. i ]:Show();
    else
      m.api[ "TurtleMailLogItem" .. i ]:Hide();
    end
  end
end

function TurtleMail.pfui_skin()
  if m.api.IsAddOnLoaded( "pfUI" ) and m.api.pfUI and m.api.pfUI.api and m.api.pfUI.env and m.api.pfUI.env.C then
    m.api.pfUI:RegisterSkin( "TurtleMail", "vanilla", function()
      -- Don't apply our skin when Mailbox skin is disabled because it doesn't make sense.
      if m.api.pfUI.env.C.disabled and (m.api.pfUI.env.C.disabled[ "skin_TurtleMail" ] == "1" or m.api.pfUI.env.C.disabled[ "skin_Mailbox" ] == "1") then
        return
      end
      m.pfui_skin_enabled = true
      local rawborder, border = m.api.pfUI.api.GetBorderSize()
      local bpad = rawborder > 1 and border - m.api.pfUI.api.GetPerfectPixel() or m.api.pfUI.api.GetPerfectPixel()

      --Inbox
      m.api.pfUI.api.SkinButton( m.api.TurtleMailOpenMailButton )

      --Sendmail
      m.api.MailHorizontalBarLeft:SetTexture( "" )
      m.api.MailHorizontalBarRight:SetTexture( "" )

      for i = 1, 21 do
        local button = m.api[ "MailAttachment" .. i ]
        m.api.pfUI.api.StripTextures( button )
        m.api.pfUI.api.SkinButton( button, nil, nil, nil, nil, true )
        local orig = button.SetNormalTexture
        button.SetNormalTexture = function( self, tex )
          orig( self, tex )

          if button.item then
            m.api.pfUI.api.HandleIcon( self, self:GetNormalTexture() )

            local link = m.api.GetContainerItemLink( button.item[ 1 ], button.item[ 2 ] )
            if link then
              local _, _, linkstr = string.find( link, "(item:%d+:%d+:%d+:%d+)" )
              local _, _, quality = m.api.GetItemInfo( linkstr )
              local r, g, b = m.api.GetItemQualityColor( quality )
              self:SetBackdropBorderColor( r, g, b, 1 )
            end
          else
            self:SetBackdropBorderColor( m.api.pfUI.api.GetStringColor( m.api.pfUI_config.appearance.border.color ) )
          end
        end
      end

      --Log
      m.api.pfUI.api.SkinTab( m.api.MailFrameTab3 )
      m.api.MailFrameTab3:ClearAllPoints()
      m.api.MailFrameTab3:SetPoint( "LEFT", m.api.MailFrameTab2, "RIGHT", border * 2 + 1, 0 )

      m.api.pfUI.api.SkinTab( m.api.MailFrameTab4 )
      m.api.MailFrameTab4:ClearAllPoints()
      m.api.MailFrameTab4:SetPoint( "LEFT", m.api.MailFrameTab3, "RIGHT", border * 2 + 1, 0 )

      m.api.TurtleMailLogTitleText:ClearAllPoints()
      m.api.TurtleMailLogTitleText:SetPoint( "TOP", m.api.MailFrame.backdrop, "TOP", 0, -10 )

      m.api.pfUI.api.CreateBackdrop( m.api.TurtleMailLogScrollFrame )

      m.api.TurtleMailLogScrollFrame:SetHeight( 307 )
      m.api.TurtleMailLogScrollFrame:ClearAllPoints()
      m.api.TurtleMailLogScrollFrame:SetPoint( "TOPLEFT", 23, -90 )
      m.api.TurtleMailLogScrollFrame:SetWidth( 299 )
      m.api.TurtleMailLogEntriesFrame:ClearAllPoints()
      m.api.TurtleMailLogEntriesFrame:SetPoint( "TOPLEFT", 23, -90 )
      m.api.TurtleMailLogEntriesFrame:SetWidth( 299 )

      m.api.pfUI.api.StripTextures( m.api.TurtleMailLogItem10 )
      m.api.pfUI.api.SkinScrollbar( m.api.TurtleMailLogScrollFrameScrollBar )
      m.api.TurtleMailLogScrollFrameScrollBar:SetPoint( "TOPLEFT", m.api.TurtleMailLogScrollFrame, "TOPRIGHT", 6, -14 )
      m.api.TurtleMailLogScrollFrameScrollBar:SetPoint( "BOTTOMLEFT", m.api.TurtleMailLogScrollFrame, "BOTTOMRIGHT", 6, 14 )

      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogSentButton )
      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogReceivedButton )
      m.api.TurtleMailLogReceivedButton:ClearAllPoints()
      m.api.TurtleMailLogReceivedButton:SetPoint( "RIGHT", m.api.TurtleMailLogSentButton, "LEFT", -2 * bpad, 0 )

      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogFiltersButton )
      m.api.TurtleMailLogFiltersButton:SetPoint( "TOPLEFT", 21, -58 )
      m.api.TurtleMailLogFiltersButton:GetFontString():SetFont( m.api.pfUI.font_default, 12 )
      m.api.TurtleMailLogFiltersButton:GetFontString():SetPoint( "TOPLEFT", 4, -4.5 )
      m.api.TurtleMailLogFiltersButton:SetWidth( 50 )
      m.api.TurtleMailLogFiltersButton:SetHeight( 20 )
      m.api.TurtleMailLogFiltersButtonArrow:SetPoint( "RIGHT", -4, -1 )
      m.api.TurtleMailLogFiltersButtonArrow:SetWidth( 8.5 )
      m.api.TurtleMailLogFiltersButtonArrow:SetHeight( 8.5 )
      m.api.TurtleMailLogFiltersButtonArrow:SetTexture( m.api.pfUI.media[ "img:down" ] )

      m.api.pfUI.api.StripTextures( m.api.TurtleMailLogStartTime )
      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogStartTime )
      m.api.pfUI.api.SkinArrowButton( m.api.TurtleMailLogStartTimeButton, "down", 16 )
      m.api.TurtleMailLogStartTime:SetPoint( "TOPLEFT", 77, -58 )
      m.api.TurtleMailLogStartTimeText:SetPoint( "LEFT", 5, 0 )
      m.api.TurtleMailLogStartTimeButton:SetPoint( "LEFT", m.api.TurtleMailLogStartTime, "RIGHT", -19, 0 )
      m.api.TurtleMailLogStartTimeTitle:SetPoint( "TOPLEFT", 1, 13 )
      m.api.TurtleMailLogStartTimeTitle:SetFont( m.api.pfUI.font_default, 10 )
      m.api.TurtleMailLogStartTimeTitle:SetText( L[ "Period start" ] )

      m.api.pfUI.api.StripTextures( m.api.TurtleMailLogEndTime )
      m.api.pfUI.api.SkinButton( m.api.TurtleMailLogEndTime )
      m.api.pfUI.api.SkinArrowButton( m.api.TurtleMailLogEndTimeButton, "down", 16 )
      m.api.TurtleMailLogEndTime:SetPoint( "TOPLEFT", 163, -58 )
      m.api.TurtleMailLogEndTimeText:SetPoint( "LEFT", 5, 0 )
      m.api.TurtleMailLogEndTimeButton:SetPoint( "LEFT", m.api.TurtleMailLogEndTime, "RIGHT", -19, 0 )
      m.api.TurtleMailLogEndTimeTitle:SetPoint( "TOPLEFT", 1, 13 )
      m.api.TurtleMailLogEndTimeTitle:SetFont( m.api.pfUI.font_default, 10 )
      m.api.TurtleMailLogEndTimeTitle:SetText( L[ "Period end" ] )

      m.api.pfUI.api.SkinDropDown( m.api.TurtleMailLogPlayersDropDown, nil, nil, nil, true )
      m.api.UIDropDownMenu_SetWidth( 90, m.api.TurtleMailLogPlayersDropDown )
      m.api.TurtleMailLogPlayersDropDown:SetScale( 1 )
      m.api.TurtleMailLogPlayersDropDown:SetPoint( "TOPLEFT", 224, -54 )
      m.api.TurtleMailLogPlayersDropDown.backdrop:SetPoint( "TOPLEFT", 26, -4 )
      m.api.TurtleMailLogPlayersDropDown.backdrop:SetPoint( "BOTTOMRIGHT", -20, 8 )
      m.api.TurtleMailLogPlayersDropDown.button.backdrop:SetWidth( 16 )
      m.api.TurtleMailLogPlayersDropDown.button.backdrop:SetHeight( 16 )

      local label = m.api.TurtleMailLogFrame:CreateFontString( nil, "BACKGROUND", "GameFontNormal" )
      label:SetFont( m.api.pfUI.font_default, 10 )
      label:SetPoint( "TOPLEFT", 251, -45 )
      label:SetText( L[ "Players" ] )
    end )
  end
end

function TurtleMail.filter( t, f, extract_field )
  if not t then return nil end
  if type( f ) ~= "function" then return t end

  local result = {}

  for i = 1, getn( t ) do
    local v = t[ i ]
    local value = type( v ) == "table" and extract_field and v[ extract_field ] or v
    if f( value ) then table.insert( result, v ) end
  end

  return result
end

function TurtleMail.info( message )
  m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473TurtleMail|r: %s", message ) )
end

function TurtleMail.dump( o )
  if not o then return "nil" end
  if type( o ) ~= 'table' then return tostring( o ) end

  local entries = 0
  local s = "{"

  for k, v in pairs( o ) do
    if (entries == 0) then s = s .. " " end
    local key = type( k ) ~= "number" and '"' .. k .. '"' or k
    if (entries > 0) then s = s .. ", " end
    s = s .. "[" .. key .. "] = " .. m.dump( v )
    entries = entries + 1
  end

  if (entries > 0) then s = s .. " " end
  return s .. "}"
end

function TurtleMail.debug( ... )
  if m.debug_enabled then
    local messages = ""
    for i = 1, getn( arg ) do
      local message = arg[ i ]
      if message then
        messages = messages == "" and "" or messages .. ", "
        if type( message ) == 'table' then
          messages = messages .. TurtleMail.dump( message )
        else
          messages = messages .. message
        end
      end
    end

    m.api.DEFAULT_CHAT_FRAME:AddMessage( string.format( "|cffabd473TurtleMail|r: %s", messages ) )
  end
end

--[==[ **Two copies of this addon stop the game loading, and this is why.**

     Both share the global `TurtleMail` table, and each file load builds its own
     update frame and registers the same events on it. So `PLAYER_LOGIN` runs
     twice, and its hook installer is not idempotent:

         for k, v in m.hooks do
           m.orig[ k ] = m.api[ k ]   -- second pass records the *hook*
           m.api[ k ] = v
         end

     The second pass stores the hook where the original belongs, so the hook
     calls itself. Unbounded recursion, during load-in. Reported as the game not
     loading at all, and worked round by switching the whole Overhaul off.

     **It cannot be guarded from the inside.** "EquadisClassicOverhaul" sorts
     before "TurtleMail", so the bundled copy loads first and the standalone --
     unmodified, and with no guard -- overwrites these functions with its own.
     Any flag set here is read by code that is about to be replaced.

     So the bundled copy stands down instead. `GetAddOnInfo` answers about an
     addon that has not loaded yet, which is what makes the decision possible
     before either has done anything: if the standalone is installed and switched
     on, it owns the mailbox and this file does nothing.

     Nothing is disabled and nobody is nagged into a choice. Two installs, one
     running, and the one running is the one somebody actually enabled. ]==]
local function standaloneEnabled()
    if type(GetAddOnInfo) ~= "function" then return false end

    local ok, _, _, _, enabled = pcall(GetAddOnInfo, "TurtleMail")

    return ok and enabled and true or false
end

if standaloneEnabled() then
    --[[ Said once, so somebody wondering which copy is running can find out
         without reading a toc. ]]--
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
                "|cffabd473TurtleMail|r: the standalone addon is enabled, "
                .. "so the bundled copy is standing down.")
    end
else
    TurtleMail:init()
end

