-- History: chat survives reloads and logouts.
-- Each character's history is its own, in its own file (ScrivenerCharDB, 0.7.6): that's the real one, and all this character
-- ever writes. The account's file holds a copy of each (ScrivenerDB.histories, by GUID), because the game lets a character
-- read only its own file and the account's. The setting "Share history between characters" (on unless you turn it off)
-- only picks which of them show, so switching moves nothing and loses nothing. The copy is the same tables, so the game
-- saves both with no keeping in step, and a character's lines join the others' once it has logged in with 0.8.1.
-- Another character's history adds what people said. Its loot, money, XP and system lines are about that character: in
-- this one's window they'd read as this one's.
-- Private chat (whispers, guild, officer, group, For you) is kept for 30 days
-- by default with large caps; everything else you see (channels, Say, loot, system) for two days, the newest 400 of each,
-- so a /reload brings the window back as it was. Add-ons' notices aren't kept (they print again at every login), nor
-- are lines the game hid until they're read again after the fight.
-- Each saved line is { time, chat type, sender, text, channel number, why, kind }.

local P = Scrivener
if not P or P.disabled then return end

local CAPS = { WHISPER = 5000, GUILD = 3000, OFFICER = 1500, PARTY = 1500, RAID = 1500, INSTANCE = 1000, FORYOU = 1000 }
local PUBLIC_CAP, PUBLIC_DAYS = 400, 2   -- everything that isn't private chat
-- only useful in the moment: "Changed Channel", "Joined Channel" and the like aren't replayed after a reload
local NOT_KEPT = { CHANNEL_NOTICE = true, CHANNEL_NOTICE_USER = true, CHANNEL_LIST = true,
  -- Battle.net notices name a friend by this session's token, which names no one after a reload
  BN_INLINE_TOAST_ALERT = true, BN_INLINE_TOAST_BROADCAST = true, BN_INLINE_TOAST_BROADCAST_INFORM = true,
  BN_WHISPER_PLAYER_OFFLINE = true }
local Hidden = P.Hidden
local Core = P.Core

local function push(kind, entry)
  local hist = P.char.history
  local list = hist[kind]
  if not list then list = {}; hist[kind] = list end
  list[#list + 1] = entry
  local cap = CAPS[kind] or PUBLIC_CAP
  if #list > cap + math.min(200, cap) then
    local keep = {}
    for i = #list - cap + 1, #list do keep[#keep + 1] = list[i] end
    hist[kind] = keep
  end
end

function P:Save(r)
  if r.held or r.note or r.restored or type(r.text) ~= "string" or Hidden(r.text) then return end
  if r.kind == "ADDONS" then return end
  if NOT_KEPT[r.type] then return end
  -- who came online an hour ago is no use after a reload
  if r.tidy and (r.tidy.what == "online" or r.tidy.what == "offline") then return end
  local keepKind = P.KEEP[r.kind] or self.db.keepAll
  if not keepKind and not r.why then return end
  local who = r.who
  if r.bn then
    who = r.bnTag   -- a Battle.net friend is saved under their BattleTag: the token means nothing after a reload
    if not who then return end
  elseif who and r.guid and type(r.guid) == "string" then
    self.char.people[who] = r.guid
  end
  local entry = { r.t, r.type, who, r.text, r.num, r.why, r.kind }
  if keepKind then push(r.kind, entry) end
  if r.why then push("FORYOU", entry) end
end

-------------------------------------------------------------------------------------------
-- Whose history shows
-------------------------------------------------------------------------------------------

local function hasLines(history)
  for _, list in pairs(history) do if type(list) == "table" and #list > 0 then return true end end
  return false
end

---Put this character's history where the others can show it: the same tables, under its GUID in the account's file. Its own
---file remembers whose it is (char.key). A file that doesn't, with no lines, while the account's copy has some, is a lost
---one: it starts from the copy. A file that was somebody else's (a character remade under the same name) already holds
---those lines, so that copy goes.
function P:MirrorHistory()
  local key = Core.Character.Key()
  if not key then return false end
  self.charKey = key
  local char, kept = self.char, self.db.histories[key]
  if char.key and char.key ~= key then self.db.histories[char.key] = nil end
  if char.key == nil and type(kept) == "table" and type(kept.history) == "table" and kept.history ~= char.history
      and not hasLines(char.history) and hasLines(kept.history) then
    for kind, list in pairs(kept.history) do char.history[kind] = list end
    for who, guid in pairs(type(kept.people) == "table" and kept.people or {}) do char.people[who] = char.people[who] or guid end
    for who, e in pairs(type(kept.personInfo) == "table" and kept.personInfo or {}) do
      char.personInfo[who] = char.personInfo[who] or e
    end
  end
  char.key = key
  self.db.histories[key] = { name = Core.Names.Me(), history = char.history, people = char.people,
    personInfo = char.personInfo }
  return true
end

---The histories on show: this character's, and with sharing on the others': { history, people, personInfo, own = true or
---name = whose }.
function P:Histories()
  local list = { { own = true, history = self.char.history, people = self.char.people, personInfo = self.char.personInfo } }
  if not self.db.shareHistory then return list end
  if not self.charKey then self:MirrorHistory() end
  for key, h in pairs(self.db.histories) do
    if key ~= self.charKey and type(h) == "table" and type(h.history) == "table" and h.history ~= self.char.history then
      list[#list + 1] = { name = h.name, history = h.history, people = type(h.people) == "table" and h.people or {},
        personInfo = type(h.personInfo) == "table" and h.personInfo or {} }
    end
  end
  return list
end

-- what another character's history adds: talk, not what happened to that character
local function talk(kind) return kind ~= nil and (P.TALK[kind] or P.IsChannel(kind)) or false end

---Whether a saved line of one of those histories shows. The game's emotes are written to the character that saw them ("You
---wave", "Wil waves at you"), so another's would read as if they were this one's.
local function shows(e, h)
  return h.own or (talk(e[7]) and e[2] ~= "TEXT_EMOTE")
end

---Every saved line from before this session that shows, of one kind (or all), with the history it's in: fn(line, history).
function P:EachSaved(kind, fn)
  local start = self.sessionStart or time()
  for _, h in ipairs(self:Histories()) do
    local function each(list)
      for _, e in ipairs(list) do if e[1] < start and shows(e, h) then fn(e, h) end end
    end
    if kind then
      if h.history[kind] then each(h.history[kind]) end
    else
      for k, list in pairs(h.history) do if k ~= "FORYOU" then each(list) end end
    end
  end
end

-- everything that shows history follows a change in it
local function refresh()
  if P.ConvosChanged then P:ConvosChanged() end
  if P.RedrawAll then P:RedrawAll() end
  for _, win in ipairs(P.windows or {}) do
    if win.searchView and win.searchView:IsShown() then P:RunSearch(win) end
  end
end

---Show the other characters' history too, or only this one's. Nothing is moved or deleted either way.
function P:SetShareHistory(on)
  self.db.shareHistory = on and true or false
  refresh()
  if self.settingsList then self.settingsList:Refresh() end
end

local function toRecord(e, h)
  P.nextId = P.nextId + 1
  local r = { id = P.nextId, t = e[1], type = e[2], who = e[3], text = e[4], num = e[5], why = e[6], kind = e[7],
    restored = true, from = not (h and h.own) and h and h.name or nil }
  r.hasWho = type(r.who) == "string" and r.who ~= ""
  r.chan = P.IsChannel(r.kind)
  r.guid = r.who and (h and h.people or P.char.people)[r.who]
  local info = ChatTypeInfo and ChatTypeInfo[r.chan and ("CHANNEL" .. (r.num or "")) or r.type]
  r.typeColor = info
  if P.BNRestore then P:BNRestore(r) end   -- a Battle.net friend, found again by their BattleTag
  if P.Tidy then P:Tidy(r, true) end   -- money, loot and rolls come back in their short shape (without racing rolls)
  P.byId[r.id] = r
  return r
end
P.HistoryRecord = toRecord

---Saved lines from before this session that a tab shows, oldest first: the newest n, or with since, the first n from
---that moment on.
function P:HistoryFor(tab, n, since)
  local lists = {}   -- { list, the history it's in }
  for _, h in ipairs(self:Histories()) do
    if tab.special == "foryou" then
      if h.history.FORYOU then lists[#lists + 1] = { h.history.FORYOU, h } end
    elseif not tab.special then
      for kind in pairs(tab.kinds) do
        if (P.KEEP[kind] or self.db.keepAll) and h.history[kind] then lists[#lists + 1] = { h.history[kind], h } end
      end
      if tab.all and self.db.keepAll then   -- every channel
        for kind, list in pairs(h.history) do
          if P.IsChannel(kind) and not tab.kinds[kind] then lists[#lists + 1] = { list, h } end
        end
      end
    end
  end
  local start = self.sessionStart or time()
  local picked = {}
  for _, pair in ipairs(lists) do
    local list, h = pair[1], pair[2]
    local got = 0
    if since then
      for _, e in ipairs(list) do
        if e[1] >= since and e[1] < start and shows(e, h) then
          picked[#picked + 1] = { e, h }
          got = got + 1
          if got >= n then break end
        end
      end
    else
      for i = #list, 1, -1 do
        local e = list[i]
        if e[1] < start and shows(e, h) then
          picked[#picked + 1] = { e, h }
          got = got + 1
          if got >= n then break end
        end
      end
    end
  end
  table.sort(picked, function(a, b) return a[1][1] < b[1][1] end)
  local out = {}
  local first, last = math.max(1, #picked - n + 1), #picked
  if since then first, last = 1, math.min(n, #picked) end
  for i = first, last do
    local r = toRecord(picked[i][1], picked[i][2])
    if not (P.Nearby and P.Nearby(r)) then out[#out + 1] = r end   -- strangers' crafting saved before 0.7.2
  end
  return out
end

---Forget this character's history, or (all) every character's. The others' own files can't be reached from here, so the
---moment is kept and each drops its older lines when it next logs in.
function P:ClearHistory(all)
  wipe(self.char.history)
  wipe(self.char.people)
  wipe(self.char.personInfo)
  if all then
    self.db.clearedAt = time()
    self.char.clearedAt = self.db.clearedAt
    for key in pairs(self.db.histories) do if key ~= self.charKey then self.db.histories[key] = nil end end
  end
  refresh()
end

---Ask first: it can't be undone. It clears what it asked about, whatever the switch says by the time of the answer.
function P:AskClearHistory()
  local S, all = P.L.set, self.db.shareHistory and true or false
  StaticPopupDialogs["SCRIVENER_CLEAR_HISTORY"] = {
    text = all and S.clearAskAll or S.clearAskOwn,
    button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() P:ClearHistory(all) end,
  }
  StaticPopup_Show("SCRIVENER_CLEAR_HISTORY")
end

-- every character's history was cleared since this one last logged in: its older lines go now
local function dropCleared()
  local cleared = P.db.clearedAt
  if type(cleared) ~= "number" or P.char.clearedAt == cleared then return end   -- a different clear, whatever the clock said
  for kind, list in pairs(P.char.history) do
    local keep = {}
    for _, e in ipairs(list) do if e[1] > cleared then keep[#keep + 1] = e end end
    P.char.history[kind] = keep
  end
  P.char.clearedAt = cleared
end

local function ageOut(h)
  -- notices saved before they stopped being kept ("Changed Channel: []" from 0.3.0) go
  for _, list in pairs(h.history) do
    for i = #list, 1, -1 do if NOT_KEPT[list[i][2]] then table.remove(list, i) end end
  end
  local private = time() - (P.db.keepDays or 30) * 86400
  local public = time() - PUBLIC_DAYS * 86400
  for kind, list in pairs(h.history) do
    local cutoff = (CAPS[kind] and private) or public
    local first = #list + 1
    for i, e in ipairs(list) do if e[1] >= cutoff then first = i; break end end
    if first > 1 then
      local keep = {}
      for i = first, #list do keep[#keep + 1] = list[i] end
      h.history[kind] = keep
    end
  end
  local used = {}
  for _, list in pairs(h.history) do for _, e in ipairs(list) do if e[3] then used[e[3]] = true end end end
  for who in pairs(h.people) do if not used[who] then h.people[who] = nil end end
end

-- A saved file is one piece of Lua, which can hold about 260,000 different numbers and texts, and a line takes nearly two.
-- The account's file also holds the settings, so the others' copies are kept well under it: their newest lines, this many
-- in all. Their own files keep everything.
P.COPIES_MAX = 60000

local function trimCopies()
  local times = {}
  for key, h in pairs(P.db.histories) do
    if key ~= P.charKey then
      for _, list in pairs(h.history) do for _, e in ipairs(list) do times[#times + 1] = e[1] end end
    end
  end
  if #times <= P.COPIES_MAX then return end
  table.sort(times)
  local from = times[#times - P.COPIES_MAX + 1]
  for key, h in pairs(P.db.histories) do
    if key ~= P.charKey then
      for kind, list in pairs(h.history) do
        local keep = {}
        for _, e in ipairs(list) do if e[1] >= from then keep[#keep + 1] = e end end
        h.history[kind] = keep
      end
    end
  end
end

---What history needs at login: what was cleared goes, this character's is put where the others can show it, and lines past
---their days go, the others' copies' too.
function P:TidyHistories()
  P.char.people = P.char.people or {}
  dropCleared()
  P:MirrorHistory()   -- before the ageing: a lost file comes back first, and ages with the rest
  ageOut(P.char)
  -- the others' copies age too, so one you no longer play doesn't stay for good
  for key, h in pairs(P.db.histories) do
    if key ~= P.charKey then
      local whole = type(h) == "table" and type(h.history) == "table"
      if whole then
        h.people = type(h.people) == "table" and h.people or {}
        ageOut(h)
      end
      if not whole or not hasLines(h.history) then P.db.histories[key] = nil end
    end
  end
  trimCopies()
end

P:OnReady(function()
  P:TidyHistories()
  P.Core:OnLogin(function() P:MirrorHistory() end)   -- the game may say who you are only now
end)
