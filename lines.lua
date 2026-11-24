-- The router: every chat event becomes one small record, handed to the tabs that want it.
-- Plain lines get everything (mentions, alerts, folding, history). Held lines (the game hides their words and sender in
-- dungeon fights) are shown as they arrive and kept by line id; when chat comes back, Scrivener reads them again with
-- C_ChatInfo.GetChatLineText and friends and swaps each for a full line in place.

local P = Scrivener
if not P or P.disabled then return end
local L = P.L
local Core = P.Core
local Hidden = P.Hidden

local CAP = 3000          -- records kept in memory for redraws and search
P.records = {}            -- oldest first
P.byId = {}
P.nextId = 0
P.heldQueue = {}          -- held records waiting to be read again
P.sawType = {}            -- [chat type id] = GetTime() of the last event of that type (to tell add-on prints apart)

local function keep(r)
  local list = P.records
  list[#list + 1] = r
  P.byId[r.id] = r
  if #list > CAP + 200 then
    local drop = #list - CAP
    for i = 1, drop do P.byId[list[i].id] = nil end
    local new = {}
    for i = drop + 1, #list do new[#new + 1] = list[i] end
    P.records = new
  end
end

function P:NewRecord(kind, ctype)
  self.nextId = self.nextId + 1
  return { id = self.nextId, t = time(), kind = kind, type = ctype }
end

-------------------------------------------------------------------------------------------
-- Delivery
-------------------------------------------------------------------------------------------

---Show a record in every tab that wants it, and remember it.
function P:Deliver(r)
  keep(r)
  self.diag.lines = self.diag.lines + 1
  if self.Show then self:Show(r) end
end

---A line of Scrivener's own ("Send again"): shown in the System chat and wherever asked.
function P:Note(text, kind, extra)
  local r = self:NewRecord(kind or "SYSTEM", "SCRIVENER")
  r.text = text
  r.note = true
  if extra then for k, v in pairs(extra) do r[k] = v end end
  self:Deliver(r)
  return r
end

-------------------------------------------------------------------------------------------
-- Folding: the same line from the same person within five minutes becomes one line with a count
-------------------------------------------------------------------------------------------

local FOLD_FOR = 300
local folds = {}      -- [kind .. "\0" .. who .. "\0" .. text] = record
local foldCount = 0

local function foldKey(r) return r.kind .. "\0" .. r.who .. "\0" .. r.text end

local function fold(r)
  if not P.db.fold or not r.who or r.kind == "WHISPER" or r.why or r.mine then return false end
  local key = foldKey(r)
  local old = folds[key]
  if old and r.t - old.t <= FOLD_FOR and P.byId[old.id] then
    old.count = (old.count or 1) + 1
    old.t0 = old.t0 or old.t   -- when it was first said (the board's "posted 3x in 9 min")
    old.t = r.t
    if P.Redraw then P:Redraw(old) end
    return true
  end
  folds[key] = r
  foldCount = foldCount + 1
  if foldCount > 2000 then
    local now = r.t
    for k, v in pairs(folds) do if now - v.t > FOLD_FOR then folds[k] = nil end end
    foldCount = 0
    for _ in pairs(folds) do foldCount = foldCount + 1 end
  end
  return false
end

-- People coming online (or going offline) within half a minute of each other share one line: "Ash Morrow, Bren
-- Talloway and 3 others came online", with "show" to list them all (the mock-up's Everyday screen).
local PEOPLE_RUN = 30
local peopleRuns = {}   -- ["online" | "offline"] = the record the names gather on

local function joinPeople(r)
  local t = r.tidy
  if not (t and (t.what == "online" or t.what == "offline") and t.who) then return false end
  local run = peopleRuns[t.what]
  if run and P.byId[run.id] and (r.t or 0) - (run.runLast or 0) <= PEOPLE_RUN then
    run.tidy.names = run.tidy.names or { run.tidy.who }
    for _, name in ipairs(run.tidy.names) do if name == t.who then return true end end
    table.insert(run.tidy.names, t.who)
    run.runLast = r.t
    if P.Redraw then P:Redraw(run) end
    return true
  end
  peopleRuns[t.what] = r
  r.runLast = r.t
  return false
end

-------------------------------------------------------------------------------------------
-- Plain lines: everything Scrivener does with chat runs here
-------------------------------------------------------------------------------------------

---Mentions, alerts and folding on a plain record, then show and save it. Returns false when it folded.
function P:Plain(r, isReread)
  if self.Tidy and not r.tidy then self:Tidy(r) end   -- money, loot and rolls read into their short shape
  if self.Nearby and self.Nearby(r) then return false end   -- a stranger crafting near you: not shown, not kept
  if self.CheckAttention then self:CheckAttention(r) end
  if not isReread and P.TALK[r.kind] or (not isReread and r.chan) then
    if fold(r) then return false end
  end
  if not isReread and joinPeople(r) then return false end
  if not isReread then
    self:Deliver(r)
  elseif r.why and self.Show then
    self:Show(r, "foryou")   -- already in its own tabs; For you only learns about it now
  end
  if self.Save then self:Save(r) end
  return true
end

-------------------------------------------------------------------------------------------
-- The router
-------------------------------------------------------------------------------------------

local function filtered(event, ...)
  local util = rawget(_G, "ChatFrameUtil")
  if not (util and util.ProcessMessageEventFilters) then return false, ... end
  local frame = DEFAULT_CHAT_FRAME
  local res = { pcall(util.ProcessMessageEventFilters, frame, event, ...) }
  if not res[1] then
    P.diag.filterErrors = (P.diag.filterErrors or 0) + 1
    if not Hidden(res[2]) then P.diag.lastFilterError = tostring(res[2]) end
    return false, ...
  end
  return unpack(res, 2, 16)
end

local function route(event, ...)
  local ctype = event:sub(10)
  local kind = P.KIND_OF[ctype]
  if not kind then return end
  local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17 = ...
  if not Hidden(a16) and a16 == true then return end                       -- the sender is hidden in a cinematic
  if ctype == "WHISPER" and not Hidden(a6) and a6 == "GM" then return end   -- the game's GM chat window has it

  local held = Hidden(a1) or Hidden(a2) or Hidden(a12)
  if not held then
    local discard
    discard, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14 =
      filtered(event, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14)
    if discard then return end
    held = Hidden(a1) or Hidden(a2) or Hidden(a12)
  end

  local r = P:NewRecord(kind, ctype)
  r.lineID = (not Hidden(a11) and type(a11) == "number") and a11 or nil
  r.lang = (not Hidden(a3)) and a3 or nil
  r.flag = (not Hidden(a6)) and a6 or nil
  r.zoneID = (not Hidden(a7)) and a7 or nil
  r.noIcons = (not Hidden(a17)) and a17 or nil
  if kind == "CHANNEL" or ((ctype == "CHANNEL_NOTICE" or ctype == "CHANNEL_NOTICE_USER" or ctype == "CHANNEL_LIST")
      and not Hidden(a9)) then
    local num = (not Hidden(a8)) and a8 or nil
    local name = (not Hidden(a9) and a9 ~= "" and a9) or (not Hidden(a4) and a4) or nil
    local key = P:SeeChannel(name, num)
    r.num = num
    r.chanName = key and P.db.chanNames[key]
    r.chanString = (not Hidden(a4) and type(a4) == "string" and a4 ~= "") and a4 or nil   -- "1. General - Elwynn Forest"
    if ctype ~= "CHANNEL" and not r.chanString and not r.chanName then return end      -- a notice about no channel at all
    if kind == "CHANNEL" then
      if not key then return end
      r.kind, r.chan = key, true
    end
  end
  if not r.chan then P.db.seen[r.kind] = true end

  local info = ChatTypeInfo and (r.chan and ChatTypeInfo["CHANNEL" .. (r.num or "")] or ChatTypeInfo[ctype])
  if info then
    r.typeColor = info
    if info.id then P.sawType[info.id] = GetTime() end
  end

  r.text, r.who, r.guid = a1, a2, a12
  r.hasWho = Hidden(a2) or (type(a2) == "string" and a2 ~= "")

  if P.BN[ctype] then
    if P.BN_NOTICE[ctype] then
      -- a notice about a friend (online, a broadcast): a finished sentence; one the game hid in a fight is dropped
      if held or not P:BNNotice(r, a13) then return end
      P:Plain(r)
      return
    end
    P:BNLine(r, a2, a13)   -- a Battle.net whisper: the token shows, the BattleTag keeps it
  end

  if held then
    r.held = true
    P.diag.held = P.diag.held + 1
    P.heldQueue[#P.heldQueue + 1] = r
    P:Deliver(r)
    if P.WHISPER_IN[ctype] and P.HeldWhisper then P:HeldWhisper(r) end
    return
  end

  if type(r.text) ~= "string" then r.text = "" end
  if r.hasWho and r.bn then
    if P.WHISPER_OUT[ctype] then r.mine = true end   -- a token is no character's name: nothing to learn
  elseif r.hasWho then
    if ctype ~= "WHISPER_INFORM" and r.guid and UnitGUID and r.guid == UnitGUID("player") then r.mine = true end
    if ctype == "WHISPER_INFORM" then r.mine = true end
    Core.Names:Learn(r.who, ctype ~= "WHISPER_INFORM" and r.guid or nil)
  else
    r.who = nil
  end
  P:Plain(r)
end

-------------------------------------------------------------------------------------------
-- Reading held lines again when the fight ends
-------------------------------------------------------------------------------------------

local TRIES = { 1, 5, 30, 120 }

local function readBack(r)
  local ci = C_ChatInfo
  if not (ci and ci.GetChatLineText and r.lineID) then return "gone" end
  if ci.IsValidChatLine then
    local ok, valid = pcall(ci.IsValidChatLine, r.lineID)
    if ok and valid == false then return "gone" end
  end
  local ok, text = pcall(ci.GetChatLineText, r.lineID)
  if not ok or text == nil then return "gone" end
  if Hidden(text) then return "hidden" end
  local who, guid
  if r.hasWho and ci.GetChatLineSenderName then
    local ok2, n = pcall(ci.GetChatLineSenderName, r.lineID)
    if ok2 and not Hidden(n) then who = n else return "hidden" end
  end
  if ci.GetChatLineSenderGUID then
    local ok3, g = pcall(ci.GetChatLineSenderGUID, r.lineID)
    if ok3 and not Hidden(g) then guid = g end
  end
  r.text, r.who, r.guid, r.held = text, who, guid, nil
  if type(r.text) ~= "string" then r.text = "" end
  if who == nil or who == "" then r.hasWho = false; r.who = nil end
  r.reread = true
  if r.hasWho and r.bn then
    P:BNLine(r, r.who, r.bnID)   -- the account behind the token, now that it can be read
    if P.WHISPER_OUT[r.type] then r.mine = true end
  elseif r.hasWho then
    if guid and UnitGUID and guid == UnitGUID("player") then r.mine = true end
    if r.type == "WHISPER_INFORM" then r.mine = true end
    Core.Names:Learn(r.who, r.type ~= "WHISPER_INFORM" and guid or nil)
  end
  return "ok"
end

local catchUpPending = false

function P:CatchUp(try)
  try = try or 1
  if #self.heldQueue == 0 then return end
  if P.ChatHidden() then return end
  local waiting = {}
  for _, r in ipairs(self.heldQueue) do
    if r.held then
      local res = readBack(r)
      if res == "ok" then
        self.diag.reread = self.diag.reread + 1
        self:Plain(r, true)
        if self.Redraw then self:Redraw(r) end
        if r.kind == "WHISPER" and self.ConvoCaught then self:ConvoCaught(r) end   -- into its conversation now
      elseif res == "hidden" then
        waiting[#waiting + 1] = r
      else
        self.diag.rereadGone = self.diag.rereadGone + 1
      end
    end
  end
  self.heldQueue = waiting
  if #waiting > 0 and TRIES[try + 1] then
    C_Timer.After(TRIES[try + 1], function() P:CatchUp(try + 1) end)
    return
  end
  self.diag.rereadHidden = self.diag.rereadHidden + #waiting
  wipe(self.heldQueue)
end

local wasHidden = false
local function restrictionsChanged()
  local now = P.ChatHidden()
  if now and not wasHidden then P.diag.lockdowns = P.diag.lockdowns + 1 end
  wasHidden = now
  if not now and #P.heldQueue > 0 and not catchUpPending then
    catchUpPending = true
    C_Timer.After(TRIES[1], function() catchUpPending = false; P:CatchUp(1) end)
  end
end

-------------------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------------------

P:OnReady(function()
  if not P.db.takeover then return end
  for ctype in pairs(P.KIND_OF) do
    local event = "CHAT_MSG_" .. ctype
    Core:On(event, "scrivener.lines", function(ev, ...)
      local ok, err = pcall(route, ev, ...)
      if not ok then
        P.diag.errors = P.diag.errors + 1
        if not Hidden(err) then P.diag.lastError = tostring(err) end
      end
    end)
  end
  Core:Listen("NORGANNON_RESTRICTIONS_CHANGED", "scrivener.lines", restrictionsChanged)
  for _, event in ipairs({ "ENCOUNTER_END", "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA" }) do
    Core:On(event, "scrivener.catchup", function() C_Timer.After(1, restrictionsChanged) end)
  end
end)
