-- For you: lines that say your name or match one of your alerts, gathered in one list, with a toast when the line is
-- out of sight. Alerts are compiled once into patterns and item ids, so a busy Trade channel costs a few finds per line.
-- Only plain lines are matched; held lines are matched when they're read again after the fight.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C
local Core = P.Core
local Hidden = P.Hidden

local COOLDOWN = 600       -- one alert per person per alert every 10 minutes (adverts repeat)
local cooled = {}

-------------------------------------------------------------------------------------------
-- Compiling alerts
-------------------------------------------------------------------------------------------

local MAGIC = "[%(%)%.%%%+%-%*%?%[%]%^%$]"
local function wordPattern(word)
  local prefix = #word > 1 and word:sub(-1) == "*"
  if prefix then word = word:sub(1, -2) end
  word = word:gsub(MAGIC, "%%%0")
  if prefix then return "%f[%w]" .. word end
  return "%f[%w]" .. word .. "%f[^%w]"
end

local function stripLinks(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
end

---How an alert tells you: { toast, sound, flash } (the taskbar). Alerts from before 0.6.0 follow the For you settings.
function P.AlertOuts(a)
  if type(a.outs) == "table" then return a.outs end
  return { toast = P.db.toasts and true or false, sound = P.db.sound and true or false, flash = P.db.flash and true or false }
end

local compiled = {}
function P:CompileAlerts()
  compiled = {}
  for i, a in ipairs(self.db.alerts) do
    local text = a.text or ""
    if a.on ~= false and text:match("%S") then
      local c = { idx = i, words = {}, nots = {}, items = {}, where = a.where or "public", when = a.when or "always",
        outs = P.AlertOuts(a) }
      for id in text:gmatch("|Hitem:(%d+)") do c.items[tonumber(id)] = true; c.hasItems = true end
      local plain = text:gsub("|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r", " "):gsub("|H.-|h.-|h", " ")
      plain = stripLinks(plain):lower()
      for word in plain:gmatch("%S+") do
        if word:sub(1, 1) == "-" and #word > 1 then c.nots[#c.nots + 1] = wordPattern(word:sub(2))
        else c.words[#c.words + 1] = wordPattern(word) end
      end
      local label = stripLinks(text)
      c.label = #label > 28 and (label:sub(1, 26) .. "\226\128\166") or label
      if #c.words > 0 or c.hasItems then compiled[#compiled + 1] = c end
    end
  end
end

function P:AddAlert(text)
  table.insert(self.db.alerts, { text = text, where = "public", when = "always", on = true,
    outs = { toast = true, sound = true, flash = false } })
  self:CompileAlerts()
  if self.RefreshAlertsEditor then self:RefreshAlertsEditor() end
end

-------------------------------------------------------------------------------------------
-- Matching
-------------------------------------------------------------------------------------------

local PUBLIC = { SAY = true, YELL = true }

local function placeOk(when)
  if when == "solo" then return not IsInGroup() end
  if when == "cities" then return IsResting() and true or false end
  if when == "outside" then return not IsInInstance() end
  return true
end

local function matches(c, r, low)
  if c.where == "public" and not (r.chan or PUBLIC[r.kind]) then return false end
  if r.kind == "LOOT" and not (c.hasItems and c.where == "all") then return false end
  if not placeOk(c.when) then return false end
  if c.hasItems then
    local hit = false
    for id in r.text:gmatch("|Hitem:(%d+)") do
      if c.items[tonumber(id)] then hit = true; break end
    end
    if not hit then return false end
  end
  for _, p in ipairs(c.words) do if not low:find(p) then return false end end
  for _, p in ipairs(c.nots) do if low:find(p) then return false end end
  return true
end

local myPatterns, myFor
local function mentionPatterns()
  local me = P.Me()
  if me == myFor and myPatterns then return myPatterns end
  myFor, myPatterns = me, {}
  local full = Core.Names.Full(me)
  local first = Core.Names.First(me)
  if first and #first > 1 then myPatterns[#myPatterns + 1] = wordPattern(first:lower()) end
  if full and full ~= first then myPatterns[#myPatterns + 1] = wordPattern(full:lower()) end
  return myPatterns
end

-------------------------------------------------------------------------------------------
-- Telling you
-------------------------------------------------------------------------------------------

local function visible(r)
  for _, win in ipairs(P.windows) do
    local tab = win.data.tabs[win.data.active]
    for _, pane in ipairs(tab and P.PanesOf(tab) or {}) do
      local tf = P.tabFrames[pane]
      if tf and win.frame:IsVisible() and P.TabWants(pane, r) and tf.smf:GetScrollOffset() == 0 then return true end
    end
  end
  return false
end

function P:Reveal(r)
  -- a whisper opens its conversation, with that person picked
  local key = r.kind == "WHISPER" and P.ConvoKey and P.ConvoKey(r)
  if key then
    for _, win in ipairs(self.windows) do
      for i, tab in ipairs(win.data.tabs) do
        for _, pane in ipairs(P.PanesOf(tab)) do
          local tf = self.tabFrames[pane]
          if pane.special == "convos" and tf then
            win.frame:Show()
            self:SelectTab(win, i, true)
            self:SelectPerson(tf, pane, key, false)
            return
          end
        end
      end
    end
  end
  for pass = 1, 2 do
    for _, win in ipairs(self.windows) do
      for i, tab in ipairs(win.data.tabs) do
        for _, pane in ipairs(P.PanesOf(tab)) do
          local want = pass == 1 and (r.why and pane.special == "foryou") or (pass == 2 and P.TabWants(pane, r))
          if want then
            win.frame:Show()
            self:SelectTab(win, i, true)
            local tf = self.tabFrames[pane]
            if tf then tf.smf:ScrollToBottom() end
            return
          end
        end
      end
    end
  end
end

local function ring(r)
  if P.db.sound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
  local flash = rawget(_G, "FlashClientIcon")
  if P.db.flash and flash then pcall(flash) end
end

function P:CheckAttention(r)
  if r.mine or r.note or r.restored or r.held then return end
  local whisper = P.WHISPER_IN[r.type]
  if not (P.TALK[r.kind] or r.chan or r.kind == "LOOT") then return end
  if type(r.text) ~= "string" then return end
  local friends = rawget(_G, "C_FriendList")
  if r.who and not r.bn and friends and friends.IsIgnored then
    local ok, ignored = pcall(friends.IsIgnored, r.who)
    if ok and ignored then return end
  end
  local low = stripLinks(r.text):lower()
  if self.db.mentions and not whisper and r.kind ~= "LOOT" then
    for _, p in ipairs(mentionPatterns()) do
      if low:find(p) then r.why = L.why.mention; break end
    end
  end
  if not r.why and not self.db.paused then
    for _, c in ipairs(compiled) do
      if matches(c, r, low) then
        local key = c.idx .. "\0" .. (r.who or "")
        if (cooled[key] or 0) + COOLDOWN <= r.t then
          cooled[key] = r.t
          r.why = L.why.alert:format(c.label)
          r.alert = c.outs
        end
        break
      end
    end
  end
  if r.alert then
    -- each alert tells you its own way: a toast, a sound, the taskbar
    local outs = r.alert
    if outs.sound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
    local flash = rawget(_G, "FlashClientIcon")
    if outs.flash and flash then pcall(flash) end
    if outs.toast then self:ToastFor(r) end
  elseif whisper then
    -- a whisper is someone talking to you: a note every time (unless you're typing), or only when it's out of sight
    local when = self.db.whisperNotes or "always"
    local typing = self.box and self.box:HasFocus()
    local due = (when == "always" and not typing) or (when == "hidden" and not visible(r))
    if due and self.db.toasts then self:ToastFor(r) end
    if due and self.db.flash then
      local flash = rawget(_G, "FlashClientIcon")
      if flash then pcall(flash) end   -- the taskbar icon, when the game isn't in front (the game plays the sound)
    end
  elseif r.why and not visible(r) then
    ring(r)
    if self.db.toasts then self:ToastFor(r) end
  end
end

-------------------------------------------------------------------------------------------
-- Toasts
-------------------------------------------------------------------------------------------

local toasts = {}
local ACCENT = UI.Hex(P.ACCENT_HEX)
local TOAST_W, TOAST_H, SHOW_FOR = 340, 54, 8

local function placeToasts()
  local y = -110
  for _, t in ipairs(toasts) do
    if t:IsShown() then
      t:ClearAllPoints()
      t:SetPoint("TOP", UIParent, "TOP", 0, y)
      y = y - TOAST_H - 6
    end
  end
end

local function smallButton(parent, text, onClick)
  local b = P.Own(UI.Button(parent, text, "quiet", onClick))
  b:SetHeight(20)
  b:SetWidth(math.max(54, b.label:GetStringWidth() + 20))
  return b
end

local function newToast()
  local t = CreateFrame("Button", nil, UIParent)
  t:SetSize(TOAST_W, TOAST_H)
  t:SetFrameStrata("HIGH")
  P.Panel(t, 36, .12)
  t:Hide()   -- so the first one fades in too
  t.mark = t:CreateTexture(nil, "ARTWORK")
  t.mark:SetSize(26, 26)
  t.mark:SetPoint("LEFT", 10, 0)
  t.mark:SetTexture(P.MARK)
  t.title = UI.Text(t, "bold", 13, ACCENT)
  t.title:SetPoint("TOPLEFT", 44, -9)
  t.title:SetPoint("RIGHT", -130, 0)
  t.text = UI.Text(t, "body", 13, C.text)
  t.text:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3)
  t.text:SetPoint("RIGHT", -12, 0)
  t.show = smallButton(t, L.toastShow, function() if t.rec then P:Reveal(t.rec) end; t:Hide() end)
  t.show:SetPoint("TOPRIGHT", -8, -6)
  t.reply = smallButton(t, L.toastWhisper, function()
    if type(t.to) == "function" then t.to()   -- a Battle.net friend: the game's own way to whisper them
    elseif t.to then ChatFrameUtil.SendTell(t.to) end
    t:Hide()
  end)
  t.reply:SetPoint("RIGHT", t.show, "LEFT", -4, 0)
  t:SetScript("OnHide", function() placeToasts() end)
  t:SetScript("OnClick", function() if t.rec then P:Reveal(t.rec) end; t:Hide() end)
  t:SetScript("OnUpdate", function(self, dt)
    if self:IsMouseOver() then return end
    self.left = self.left - dt
    if self.left <= 0 then self:Hide() end
  end)
  toasts[#toasts + 1] = t
  return t
end

function P:Toast(title, text, rec, to)
  local t
  for _, x in ipairs(toasts) do if not x:IsShown() then t = x; break end end
  if not t then
    if #toasts >= 3 then
      t = toasts[1]
      table.remove(toasts, 1)
      toasts[#toasts + 1] = t
    else
      t = newToast()
    end
  end
  t.rec, t.to, t.left = rec, to, SHOW_FOR
  t.title:SetText(title)
  pcall(t.text.SetText, t.text, text)   -- held whispers are hidden text; a font string can still show it
  t.reply:SetShown(to ~= nil)
  t:Show()
  placeToasts()
end

function P:ToastFor(r)
  local who
  if r.bn then who = r.who   -- a Battle.net friend's token: the toast's title shows their name
  else who = r.who and (Core.Names:Address(r.who) or Core.Names.Full(r.who) or r.who) end
  local whisper = P.WHISPER_IN[r.type]
  local title
  if whisper then title = who or L.toastWhisper
  else title = (who and (who .. "  \194\183  ") or "") .. P.KindLabel(r.kind) end
  if r.why and not whisper then title = title .. "  \194\183  " .. r.why end
  local text = P.LowerIcons(stripLinks(r.text or ""), 13)
  local to = (whisper or P.TALK[r.kind] or r.chan) and who or nil
  if to and r.bn then
    local id, token = r.bnID, r.who
    to = function() P.BNTell(id, token) end
  end
  self:Toast(title, text, r, to)
end

---A whisper that came in hidden (a dungeon fight): shown as it is, no reply button until the fight ends.
function P:HeldWhisper(r)
  if not self.db.toasts or visible(r) then return end
  self:Toast(L.toastFromFight, r.text, r, nil)
end

P:OnReady(function() P:CompileAlerts() end)
