-- History: chat survives reloads and logouts, each character's its own (ParleyCharDB, 0.7.6). Private chat (whispers, guild, officer, group, For you) is kept for 30 days
-- by default with large caps; everything else you see (channels, Say, loot, system) for two days, the newest 400 of each,
-- so a /reload brings the window back as it was. Add-ons' notices aren't kept (they print again at every login), nor
-- are lines the game hid until they're read again after the fight.
-- Each saved line is { time, chat type, sender, text, channel number, why, kind }.

local P = Parley
if not P or P.disabled then return end

local CAPS = { WHISPER = 5000, GUILD = 3000, OFFICER = 1500, PARTY = 1500, RAID = 1500, INSTANCE = 1000, FORYOU = 1000 }
local PUBLIC_CAP, PUBLIC_DAYS = 400, 2   -- everything that isn't private chat
-- only useful in the moment: "Changed Channel", "Joined Channel" and the like aren't replayed after a reload
local NOT_KEPT = { CHANNEL_NOTICE = true, CHANNEL_NOTICE_USER = true, CHANNEL_LIST = true,
  -- Battle.net notices name a friend by this session's token, which names no one after a reload
  BN_INLINE_TOAST_ALERT = true, BN_INLINE_TOAST_BROADCAST = true, BN_INLINE_TOAST_BROADCAST_INFORM = true,
  BN_WHISPER_PLAYER_OFFLINE = true }
local Hidden = P.Hidden

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

local function toRecord(e)
  P.nextId = P.nextId + 1
  local r = { id = P.nextId, t = e[1], type = e[2], who = e[3], text = e[4], num = e[5], why = e[6], kind = e[7],
    restored = true }
  r.hasWho = type(r.who) == "string" and r.who ~= ""
  r.chan = P.IsChannel(r.kind)
  r.guid = r.who and P.char.people[r.who]
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
  local lists = {}
  if tab.special == "foryou" then
    lists[1] = self.char.history.FORYOU
  elseif not tab.special then
    for kind in pairs(tab.kinds) do
      if (P.KEEP[kind] or self.db.keepAll) and self.char.history[kind] then lists[#lists + 1] = self.char.history[kind] end
    end
    if tab.all and self.db.keepAll then   -- every channel
      for kind, list in pairs(self.char.history) do
        if P.IsChannel(kind) and not tab.kinds[kind] then lists[#lists + 1] = list end
      end
    end
  end
  local start = self.sessionStart or time()
  local picked = {}
  for _, list in ipairs(lists) do
    local got = 0
    if since then
      for _, e in ipairs(list) do
        if e[1] >= since and e[1] < start then
          picked[#picked + 1] = e
          got = got + 1
          if got >= n then break end
        end
      end
    else
      for i = #list, 1, -1 do
        local e = list[i]
        if e[1] < start then
          picked[#picked + 1] = e
          got = got + 1
          if got >= n then break end
        end
      end
    end
  end
  table.sort(picked, function(a, b) return a[1] < b[1] end)
  local out = {}
  local first, last = math.max(1, #picked - n + 1), #picked
  if since then first, last = 1, math.min(n, #picked) end
  for i = first, last do
    local r = toRecord(picked[i])
    if not (P.Nearby and P.Nearby(r)) then out[#out + 1] = r end   -- strangers' crafting saved before 0.7.2
  end
  return out
end

---Every saved line, as records (for search).
function P:HistoryAll()
  local out = {}
  local start = self.sessionStart or time()
  for kind, list in pairs(self.char.history) do
    if kind ~= "FORYOU" then
      for _, e in ipairs(list) do if e[1] < start then out[#out + 1] = toRecord(e) end end
    end
  end
  return out
end

function P:ClearHistory()
  wipe(self.char.history)
  wipe(self.char.people)
  if self.RedrawAll then self:RedrawAll() end
end

local function ageOut()
  -- notices saved before they stopped being kept ("Changed Channel: []" from 0.3.0) go
  for _, list in pairs(P.char.history) do
    for i = #list, 1, -1 do if NOT_KEPT[list[i][2]] then table.remove(list, i) end end
  end
  local private = time() - (P.db.keepDays or 30) * 86400
  local public = time() - PUBLIC_DAYS * 86400
  for kind, list in pairs(P.char.history) do
    local cutoff = (CAPS[kind] and private) or public
    local first = #list + 1
    for i, e in ipairs(list) do if e[1] >= cutoff then first = i; break end end
    if first > 1 then
      local keep = {}
      for i = first, #list do keep[#keep + 1] = list[i] end
      P.char.history[kind] = keep
    end
  end
  local used = {}
  for _, list in pairs(P.char.history) do for _, e in ipairs(list) do if e[3] then used[e[3]] = true end end end
  for who in pairs(P.char.people) do if not used[who] then P.char.people[who] = nil end end
end

P:OnReady(function()
  P.char.people = P.char.people or {}
  ageOut()
end)
