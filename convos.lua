-- Conversations: the Whispers tab as the mock-up drew it. A list of everyone you've whispered with on the left (newest
-- first, an online dot, the name in class colour with their level and guild, how long ago, the last line, an unread
-- badge, and a box to find a person); the conversation with the one you pick on the right, under a header saying who they
-- are (level, class, guild, online, zone). Your own lines read "You". Days are ruled off, and "New since
-- you looked" marks where you'd got to. Picking a person readies the chat box to whisper them without opening it;
-- right-clicking one gives the game's menu for them, as their name in chat does.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C
local Core = P.Core
local Hidden = P.Hidden

local RAIL_W, ROW_H = 196, 42
local ACCENT = UI.Hex(P.ACCENT_HEX)
local FAINT = "|cff6e6552"

-------------------------------------------------------------------------------------------
-- Who a whisper line is with, and the list of people
-------------------------------------------------------------------------------------------

---The conversation a record belongs to: the other person's full name in lower case, or nil.
function P.ConvoKey(r)
  if r.convoKey then return r.convoKey end
  if r.kind ~= "WHISPER" or r.held or type(r.who) ~= "string" or Hidden(r.who) or r.who == "" then return nil end
  if r.bn then return P.BNKey(r.bnTag or r.who) end   -- a Battle.net friend, by their BattleTag
  local full = Core.Names.Full(r.who) or r.who
  return full:lower()
end

---A saved whisper as a record (a Battle.net one finds its friend again).
local function fromHistory(e)
  local r = { t = e[1], type = e[2], who = e[3], text = e[4], kind = "WHISPER", restored = true, hasWho = true,
    guid = e[3] and P.char.people[e[3]], id = 0 }
  P:BNRestore(r)
  return r
end

local index        -- [key] = { key, name, last, preview, mine, unread }

local function preview(r)
  local text = type(r.text) == "string" and not Hidden(r.text) and r.text or ""
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
  if P.WHISPER_OUT[r.type] then text = L.you .. ": " .. text end
  return text
end

-------------------------------------------------------------------------------------------
-- Level and guild, learned from what the game shows anyway: people you target or mouse over, your group, friendly
-- nameplates, and any /who (yours or another add-on's). Parley never asks the server. Kept for the people you've
-- whispered with; everyone else only for this session, in case they whisper you later.
-------------------------------------------------------------------------------------------

local sighted = {}   -- [lower full name] = { level, guild ("" for none), class, at }

local function clean(v) if v ~= nil and not Hidden(v) then return v end end

local function learn(full, level, guild, class)
  full = Core.Names.Full(clean(full))
  if not full or not Core.Names.HasSurname(full) then return end   -- a first name alone could be anyone
  local key = full:lower()
  local e = sighted[key] or P.char.personInfo[key] or {}
  local was = (e.level or 0) .. "|" .. tostring(e.guild)
  level, guild, class = clean(level), clean(guild), clean(class)
  if type(level) == "number" and level > 0 then e.level = math.max(e.level or 0, level) end
  if type(guild) == "string" then e.guild = guild end
  if type(class) == "string" and class ~= "" then e.class = class end
  e.at = time()
  sighted[key] = e
  if index and index[key] then
    P.char.personInfo[key] = e
    if was ~= (e.level or 0) .. "|" .. tostring(e.guild) then P:ConvoPersonChanged(key) end
  end
end

local function fromUnit(unit)
  if not (UnitExists(unit) and UnitIsPlayer(unit)) then return end
  local full = Core.Names:Address(unit)
  if not full then return end
  local _, class = UnitClass(unit)
  learn(full, UnitLevel(unit), (GetGuildInfo(unit)) or "", class)
end

local function fromWho()
  local friends = rawget(_G, "C_FriendList")
  if not (friends and friends.GetNumWhoResults and friends.GetWhoInfo) then return end
  local n = friends.GetNumWhoResults() or 0
  for i = 1, n do
    local ok, info = pcall(friends.GetWhoInfo, i)
    if ok and type(info) == "table" then learn(info.fullName, info.level, info.fullGuildName or "", info.filename) end
  end
end
P.LearnPerson = learn

local function note(r)
  local key = P.ConvoKey(r)
  if not key or r.type == "PARLEY" then return nil end
  local c = index[key]
  if not c then
    c = { key = key, name = r.bn and r.who or (Core.Names.Full(r.who) or r.who), last = 0, unread = 0 }
    index[key] = c
    if sighted[key] and not r.bn then P.char.personInfo[key] = sighted[key] end   -- seen earlier today, whispered now
  end
  if r.bn then
    c.bn = true
    c.bnTag = r.bnTag or c.bnTag
    if r.bnID then c.bnID, c.name = r.bnID, r.who end   -- a friend found this session: the token names them
  end
  if (r.t or 0) >= c.last then
    c.last = r.t or c.last
    c.preview = preview(r)
    c.guid = (r.type == "WHISPER" and type(r.guid) == "string") and r.guid or c.guid
  end
  return c
end

local function buildIndex()
  index = {}
  for _, e in ipairs(P.char.history.WHISPER or {}) do note(fromHistory(e)) end
  for _, r in ipairs(P.records) do
    if r.kind == "WHISPER" then note(r) end
  end
  for key in pairs(P.char.personInfo) do
    if not index[key] then P.char.personInfo[key] = nil end   -- their whispers aged out of history
  end
end

---Whether this character has a conversation with them (the Whispers tab's pick is the account's; the people are not).
function P:ConvoKnows(key)
  if not index then buildIndex() end
  return index[key] ~= nil
end

function P:ConvoList(filter)
  if not index then buildIndex() end
  local out = {}
  filter = filter and filter:lower() or ""
  for _, c in pairs(index) do
    if filter == "" or c.key:find(filter, 1, true) then out[#out + 1] = c end
  end
  table.sort(out, function(a, b) return a.last > b.last end)
  return out
end

-------------------------------------------------------------------------------------------
-- Who someone is, when the game knows: the friends list, then the guild roster, then their GUID
-------------------------------------------------------------------------------------------

local roster = {}   -- [lower full name] = { level, class, zone, online }
local function readRoster()
  wipe(roster)
  if not (GetNumGuildMembers and GetGuildRosterInfo) then return end
  local n = GetNumGuildMembers() or 0
  for i = 1, n do
    local name, _, _, level, class, zone, _, _, online = GetGuildRosterInfo(i)
    local full = name and (Core.Names.Full(name) or name)
    if full then roster[full:lower()] = { level = level, class = class, zone = zone, online = online } end
  end
end

---{ online = true/false/nil, level, class, zone, guild } for a person: the friends list, then the guild roster, then what
---Parley has seen of them, then their GUID.
function P:PersonInfo(name, guid)
  local info = {}
  local key = name:lower()
  local seen = P.char.personInfo[key] or sighted[key]
  local friends = rawget(_G, "C_FriendList")
  local g = roster[key]
  local f
  if friends and friends.GetFriendInfo then
    local ok, got = pcall(friends.GetFriendInfo, name)
    if ok and type(got) == "table" then f = got end
  end
  if f then
    info.online, info.level, info.class, info.zone = f.connected, f.level, f.className, f.area
  elseif g then
    info.online, info.level, info.class, info.zone = g.online, g.level, g.class, g.zone
  elseif type(guid) == "string" and GetPlayerInfoByGUID then
    local ok, class = pcall(GetPlayerInfoByGUID, guid)
    if ok then info.class = class end
  end
  if seen and seen.level and seen.level > (info.level or 0) then info.level = seen.level end
  local mine = g and (Core.Guild and Core.Guild.Name and Core.Guild:Name() or (GetGuildInfo and (GetGuildInfo("player"))))
  if mine then
    info.guild = mine   -- on your roster: your guild, whatever an old sighting said
  elseif seen and seen.guild and seen.guild ~= "" then
    info.guild = seen.guild
  end
  return info
end

local function guildTag(guild) return guild and ("<" .. guild .. ">") or nil end

local function infoLine(c)
  if c.bn then return P:BNInfo(c) end
  local i = P:PersonInfo(c.name, c.guid)
  local parts = {}
  if i.level and i.level > 0 and i.class then parts[#parts + 1] = L.levelClass:format(i.level, i.class)
  elseif i.level and i.level > 0 then parts[#parts + 1] = L.level:format(i.level)
  elseif i.class then parts[#parts + 1] = i.class end
  if i.guild then parts[#parts + 1] = guildTag(i.guild) end
  if i.online ~= nil then parts[#parts + 1] = i.online and L.online or L.offline end
  if i.online and i.zone and i.zone ~= "" then parts[#parts + 1] = i.zone end
  return table.concat(parts, " \194\183 "), i.online, i
end

---A conversation partner's level or guild just became known: their row and header follow.
function P:ConvoPersonChanged(key)
  for pane, tf in pairs(self.tabFrames) do
    if tf.rail then
      self:RefreshRail(pane, tf)
      if pane.person == key then self:UpdatePaneHead(pane, tf) end
    end
  end
end

local function ago(t)
  local d = time() - (t or 0)
  if d < 60 then return "" end
  if d < 3600 then return L.ago.m:format(math.floor(d / 60)) end
  if d < 86400 then return L.ago.h:format(math.floor(d / 3600)) end
  if d < 172800 then return L.ago.yesterday end
  return L.ago.days:format(math.floor(d / 86400))
end

-------------------------------------------------------------------------------------------
-- The rail
-------------------------------------------------------------------------------------------

local function colorName(c)
  if c.bn then return P.BNColor() .. c.name .. "|r" end
  local hex = P.ClassHex and P.ClassHex(c.guid)
  local shown = P.ShowName(c.name)
  return hex and ("|c" .. hex .. shown .. "|r") or shown
end

---A person's name in the list, then, faint, their level and guild when Parley knows them: "Ash Morrow  58 <Wardens of
---Dawn>". Also whether they're online (true, false, or nil when nobody can say).
function P.ConvoRowName(c)
  local _, online, i = infoLine(c)
  local meta = {}
  if i and i.level and i.level > 0 then meta[#meta + 1] = tostring(i.level) end
  if i and i.guild then meta[#meta + 1] = guildTag(i.guild) end
  return colorName(c) .. (#meta > 0 and ("  " .. FAINT .. table.concat(meta, " ") .. "|r") or ""), online
end

function P:RefreshRail(pane, tf)
  if not tf.rail then return end
  local list = self:ConvoList(tf.rail.search:GetText())
  tf.rail.list:SetData(list, true)
  local selected
  for _, c in ipairs(list) do if c.key == pane.person then selected = c end end
  if selected then tf.rail.list:Select(selected) end
  tf.rail.empty:SetShown(#list == 0)
end

function P:BuildRail(pane, tf)
  local holder = tf.frame
  local rail = CreateFrame("Frame", nil, holder)
  tf.rail = rail
  rail:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  rail:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
  rail:SetWidth(RAIL_W)
  rail.line = rail:CreateTexture(nil, "BORDER")
  rail.line:SetColorTexture(231 / 255, 198 / 255, 108 / 255, .12)
  rail.line:SetPoint("TOPRIGHT")
  rail.line:SetPoint("BOTTOMRIGHT")
  rail.line:SetWidth(1)
  rail.search = P.Own(UI.Search(rail, L.findPerson, function() P:RefreshRail(pane, tf) end))
  rail.search:SetPoint("TOPLEFT", 8, -7)
  rail.search:SetPoint("TOPRIGHT", -9, -7)
  rail.list = UI.List(rail, {
    rowHeight = ROW_H,
    createRow = function(row, content)
      row.dot = content:CreateTexture(nil, "ARTWORK")
      row.dot:SetSize(7, 7)
      row.dot:SetPoint("TOPLEFT", 10, -11)
      row.dot:SetTexture(UI.TEX and UI.TEX.circle or "Interface\\Buttons\\WHITE8X8")
      row.name = UI.Text(content, "body", 13, C.text)
      row.name:SetPoint("TOPLEFT", 24, -6)
      row.name:SetPoint("RIGHT", -52, 0)
      row.when = UI.Text(content, "body", 11, C.faint)
      row.when:SetPoint("TOPRIGHT", -12, -8)
      row.when:SetJustifyH("RIGHT")
      row.text = UI.Text(content, "body", 12, C.muted)
      row.text:SetPoint("TOPLEFT", 24, -23)
      row.text:SetPoint("RIGHT", -34, 0)
      row.badge = CreateFrame("Frame", nil, content)
      row.badge:SetSize(17, 16)
      row.badge:SetPoint("RIGHT", -10, -6)
      row.badge.bg = UI.Round(row.badge, "BACKGROUND", 0, 8)
      row.badge.bg:SetColor(ACCENT, 1)
      row.badge.n = UI.Text(row.badge, "bold", 11, { 16 / 255, 18 / 255, 31 / 255 })
      row.badge.n:SetPoint("CENTER", 0, 0)
    end,
    updateRow = function(row, c)
      local text, online = P.ConvoRowName(c)
      row.name:SetText(text)
      row.when:SetText(ago(c.last))
      row.text:SetText(c.preview or "")
      if online == true then row.dot:SetVertexColor(.56, .88, .56, 1)
      elseif online == false then row.dot:SetVertexColor(.43, .4, .32, 1)
      else row.dot:SetVertexColor(.43, .4, .32, .45) end
      row.badge:SetShown((c.unread or 0) > 0)
      row.badge.n:SetText(c.unread or "")
    end,
    onClick = function(c, _, button)
      if button == "RightButton" then P:PersonMenu(c, rail.list) else P:SelectPerson(tf, pane, c.key, true) end
    end,
  })
  rail.list:SetPoint("TOPLEFT", rail.search, "BOTTOMLEFT", -8, -6)
  rail.list:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", -1, 2)
  if rail.list.ApplyAccent then rail.list:ApplyAccent(ACCENT) end
  rail.empty = UI.Text(rail, "body", 12, C.faint)
  rail.empty:SetPoint("TOP", rail.search, "BOTTOM", 0, -14)
  rail.empty:SetText(L.convoNone)
  -- the conversation's header and lines sit to the right of the rail
  tf.head:ClearAllPoints()
  tf.head:SetPoint("TOPLEFT", holder, "TOPLEFT", RAIL_W, 0)
  tf.head:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
  self:RefreshRail(pane, tf)
end

---Turn the chat box to a whisper to the person behind a conversation.
local function tell(c)
  if c.bn then P.BNTellPerson(c) else ChatFrameUtil.OpenChat("/w " .. c.name .. " ", DEFAULT_CHAT_FRAME) end
end

---Show one person's conversation. Picked by the player it doesn't open the chat box (Maro, 20 Nov: that took the keys
---you move with); the next time you open it, it starts on a whisper to them, so an answer can't go to the guild by
---mistake. A box already open and empty turns to them now; one you're typing in keeps going where you aimed it.
function P:SelectPerson(tf, pane, key, byPlayer)
  if not index then buildIndex() end
  pane.person = key
  local c = index[key]
  tf.newSince = c and c.unread or 0
  if c then c.unread = 0 end
  self:ConvoBackfill(pane, tf)
  self:UpdatePaneHead(pane, tf)
  self:RefreshRail(pane, tf)
  if self.UpdateTabs and tf.win then self:UpdateTabs(tf.win) end
  if not (byPlayer and c) then return end
  local box = self.box
  local open = box and box:IsShown()
  local text = open and box:GetText() or ""
  if open and type(text) == "string" and not Hidden(text) and text == "" then
    self.replyTo = nil
    tell(c)
  else
    self.replyTo = { key = key, tf = tf, pane = pane }
  end
end

---The chat box opened. If you'd picked someone in the whisper list and their conversation is still on screen, it starts
---on a whisper to them, once per pick (whispers are sticky: after you send, the game keeps the box on them). Opened by the
---game's Reply key, a name's Whisper or anything else that says where it goes, or with a "/" typed, it's left alone.
function P:ConvoBoxOpened(box)
  local a = self.replyTo
  if not a then return end
  self.replyTo = nil
  local opened = GetTime()
  C_Timer.After(0, function()   -- after the game's own call that opened it, which says where it goes last
    if (self.toldAt or -1) >= opened or not box:IsShown() then return end
    local text = box:GetText() or ""
    if type(text) ~= "string" or Hidden(text) or text ~= "" then return end
    if a.pane.person ~= a.key or not (a.tf.frame and a.tf.frame:IsVisible()) then return end
    local c = index and index[a.key]
    if c then tell(c) end
  end)
end

---Right-click a person in the list: the game's own menu for them (whisper, invite, add friend, ignore, copy name...), as
---on their name in chat.
function P:PersonMenu(c, owner)
  if c.bn then
    local id = P.BNPersonID(c)
    local info = id and P.BNAccount(id)
    return info ~= nil and self:NameMenu(info.accountName, owner, id)
  end
  return self:NameMenu(c.name, owner)
end

---The header over a conversation: the person's name, then who they are.
function P:ConvoHead(pane)
  if not index then buildIndex() end
  local c = pane.person and index[pane.person]
  if not c then return L.tab.whispers, "" end
  local line = infoLine(c)
  return colorName(c), line
end

-------------------------------------------------------------------------------------------
-- The conversation's lines
-------------------------------------------------------------------------------------------

local function dayLabel(t)
  local day = date("%Y%m%d", t)
  if day == date("%Y%m%d") then return L.today end
  if day == date("%Y%m%d", time() - 86400) then return L.yesterday end
  return date("%d %b", t)
end

function P:ConvoBackfill(pane, tf)
  local smf = tf.smf
  smf:Clear()
  tf.last, tf.cont = nil, {}
  local key = pane.person
  if not key then return end
  local lines = {}
  local start = self.sessionStart or time()
  for _, e in ipairs(self.char.history.WHISPER or {}) do
    if e[1] < start and e[3] then
      local r = fromHistory(e)
      if P.ConvoKey(r) == key then lines[#lines + 1] = r end
    end
  end
  for _, r in ipairs(self.records) do
    if P.ConvoKey(r) == key then lines[#lines + 1] = r end
  end
  table.sort(lines, function(a, b) return (a.t or 0) < (b.t or 0) end)
  local fresh = #lines - (tf.newSince or 0) + 1
  local day
  for i, r in ipairs(lines) do
    local d = r.t and date("%Y%m%d", r.t)
    if d and d ~= day then
      day = d
      pcall(smf.AddMessage, smf, P:RuleText(dayLabel(r.t)), .6, .6, .6, 0)
    end
    if (tf.newSince or 0) > 0 and i == fresh then
      pcall(smf.AddMessage, smf, P:NewSinceText(), .6, .6, .9, 0)
    end
    if r.id == 0 then
      P.nextId = P.nextId + 1
      r.id = P.nextId
      P.byId[r.id] = r
    end
    local text, cr, cg, cb = P:Format(r, pane)
    if text then pcall(smf.AddMessage, smf, text, cr, cg, cb, r.id) end
  end
  tf.newSince = 0
  smf:ScrollToBottom()
end

---A whisper came in or went out: the list moves, the person's unread count grows when their conversation isn't the one
---you're looking at.
function P:ConvoSeen(pane, tf, r)
  if not index then buildIndex() end
  local c = note(r)
  if not c then return end
  local shown = tf.win and tf.win.data.tabs[tf.win.data.active] == tf.tab and tf.win.frame:IsShown()
  local drawn = false
  if not pane.person then
    pane.person = c.key
    self:ConvoBackfill(pane, tf)   -- drawn fresh, with this line already in it
    self:UpdatePaneHead(pane, tf)
    drawn = true
  elseif P.WHISPER_IN[r.type] and (c.key ~= pane.person or not shown) then
    c.unread = (c.unread or 0) + 1
    if c.key ~= pane.person and not shown then tf.unread = tf.unread + 1 end
  end
  self:RefreshRail(pane, tf)
  if tf.win then self:UpdateTabs(tf.win) end
  return drawn
end

---A whisper the game hid in a fight, read again afterwards. While hidden it belonged to no one, so it joins its
---conversation now: the list moves, and the conversation on show is drawn again with the line in its place.
function P:ConvoCaught(r)
  local key = P.ConvoKey(r)
  if not key then return end
  for pane, tf in pairs(self.tabFrames) do
    if pane.special == "convos" and tf.rail and not self:ConvoSeen(pane, tf, r) and pane.person == key then
      self:ConvoBackfill(pane, tf)
    end
  end
end

P:OnReady(function()
  if not P.db.takeover then return end
  Core:On("GUILD_ROSTER_UPDATE", "parley.convos", function()
    readRoster()
    for pane, tf in pairs(P.tabFrames) do if tf.rail then P:RefreshRail(pane, tf) end end
  end)
  Core:On("FRIENDLIST_UPDATE", "parley.convos", function()
    for pane, tf in pairs(P.tabFrames) do if tf.rail then P:RefreshRail(pane, tf) end end
  end)
  -- level and guild from the people the game shows you
  Core:On("PLAYER_TARGET_CHANGED", "parley.convos", function() fromUnit("target") end)
  Core:On("PLAYER_FOCUS_CHANGED", "parley.convos", function() fromUnit("focus") end)
  Core:On("UPDATE_MOUSEOVER_UNIT", "parley.convos", function() fromUnit("mouseover") end)
  Core:On("NAME_PLATE_UNIT_ADDED", "parley.convos", function(_, unit) if type(unit) == "string" then fromUnit(unit) end end)
  Core:On("GROUP_ROSTER_UPDATE", "parley.convos", function()
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and GetNumGroupMembers() or 4 do fromUnit((raid and "raid" or "party") .. i) end
  end)
  Core:On("WHO_LIST_UPDATE", "parley.convos", fromWho)
end)
