-- Taking over from the game's chat windows, gently.
-- Blizzard's chat windows are parented to a hidden frame, not moved or rewritten: they keep running underneath (reply
-- targets for /r, whisper sounds, censorship prompts, GM chat). Blizzard's chat box moves into Parley's window and is
-- restyled with widget calls only; Parley never writes its fields or replaces its scripts, so /cast, /target and the
-- other protected commands typed into it keep working. If the box can't move, nothing else changes.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C
local Core = P.Core
local Hidden = P.Hidden

local vault = CreateFrame("Frame", "ParleyVault", UIParent)
vault:Hide()

local HIDE = { "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
  "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton", "TextToSpeechButtonFrame", "ChatAlertFrame",
  "CombatLogQuickButtonFrame_Custom" }
local ART = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }
local ACCENT = UI.Hex(P.ACCENT_HEX)

-------------------------------------------------------------------------------------------
-- The chat box: the game's own, in a pill at the bottom of the window you last used, with a chip at its left saying
-- where the line will go (the mock-up's .compose and .dest). The game's "Guild:" header is faded out and the chip sits
-- in its room; clicking the chip lists where else the line could go.
-------------------------------------------------------------------------------------------

local home = CreateFrame("Button", "ParleyChatBoxHome", UIParent)
home:SetHeight(P.COMPOSE_H)
home:RegisterForClicks("LeftButtonUp")
home.bg = UI.Round(home, "BACKGROUND", 0, 14)
home.bg:SetColor({ 0, 0, 0 }, .5)
home.line = UI.Round(home, "BORDER", 0, 14, "line")
-- quiet: the window's own dark gold line with a hint of Parley's colour, a little brighter while you type
local QUIET, TYPING = UI.Mix(ACCENT, C.line, .85), UI.Mix(ACCENT, C.line, .6)
home.line:SetColor(QUIET, .5)
local idle = UI.Text(home, "body", 13, C.faint)

-- The chip and the box sit side by side, never one over the other: while you type, the game lifts its box to the
-- dialog layer, above Parley's windows, and a chip under the box's edge never got the click (0.6.0's fix).
local chip = CreateFrame("Button", nil, home)
chip:SetHeight(22)
chip:EnableMouse(true)
chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
chip:SetPoint("LEFT", home, "LEFT", 4, 0)
chip.bg = UI.Round(chip, "BACKGROUND", 0, 11)
chip.bg:SetColor({ 1, 1, 1 }, .06)
chip.line = UI.Round(chip, "BORDER", 0, 11, "line")
chip.line:SetColor({ 1, 1, 1 }, .14)
chip.label = UI.Text(chip, "body", 12, C.text)
chip.label:SetPoint("LEFT", 9, 0)
chip.arrow = UI.Icon(chip, "chevron", 9, C.muted)   -- drawn: the suite's font has no arrow glyph
chip.arrow:SetPoint("LEFT", chip.label, "RIGHT", 4, -1)
idle:SetPoint("LEFT", chip, "RIGHT", 8, 0)
idle:SetText(L.composeIdle)

-- The right end: the letter count, then the pill for the game's chat menu (emotes, voice emotes, languages), as the
-- game's chat window has it. For a character who speaks more than one language the pill names the one the box speaks;
-- otherwise it shows the game's own chat menu icon. The pill is drawn by Parley; the game's own chat menu button sits on
-- it, see-through, and takes the click. Its menu is the game's, so picking a language there is the game's doing: an
-- add-on that set the language itself would leave the chat box marked as touched by an add-on, and /cast typed into it
-- could fail in combat.
local tail = CreateFrame("Frame", nil, home)
tail:SetHeight(22)
tail:SetPoint("RIGHT", home, "RIGHT", -4, 0)
local counter = UI.Text(tail, "body", 11, C.faint)
local COUNT_W = 46     -- room for "255/255"

local lang = CreateFrame("Frame", nil, tail)
lang:SetHeight(22)
lang:SetPoint("RIGHT", tail, "RIGHT", 0, 0)
lang:Hide()
lang.bg = UI.Round(lang, "BACKGROUND", 0, 11)
lang.line = UI.Round(lang, "BORDER", 0, 11, "line")
lang.label = UI.Text(lang, "body", 12, C.muted)
lang.label:SetPoint("LEFT", 9, 0)
lang.arrow = UI.Icon(lang, "chevron", 9, C.muted)
lang.arrow:SetPoint("LEFT", lang.label, "RIGHT", 4, -1)
lang.icon = lang:CreateTexture(nil, "ARTWORK")
lang.icon:SetSize(16, 16)
lang.icon:SetPoint("CENTER", 0, 0)
lang.icon:Hide()

local function paintLanguage()
  local other, hover = lang.other, lang.hover
  if other then
    lang.bg:SetColor(ACCENT, hover and .22 or .14)
    lang.line:SetColor(ACCENT, .45)
    lang.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
  else
    lang.bg:SetColor({ 1, 1, 1 }, hover and .12 or .06)
    lang.line:SetColor({ 1, 1, 1 }, .14)
    local c = hover and C.text or C.muted
    lang.label:SetTextColor(c[1], c[2], c[3])
  end
  lang.icon:SetAlpha(hover and 1 or .7)
end

local function layoutTail()
  local pill = lang:IsShown() and (lang:GetWidth() + 6) or 0
  tail:SetWidth(COUNT_W + pill)
  counter:ClearAllPoints()
  counter:SetPoint("RIGHT", tail, "RIGHT", -(pill + 8), 0)
end
layoutTail()
P.compose = { home = home, chip = chip, tail = tail, lang = lang }   -- for the tests

local boxes = {}

local TYPE_KIND = { SAY = "SAY", YELL = "YELL", EMOTE = "EMOTE", GUILD = "GUILD", OFFICER = "OFFICER", PARTY = "PARTY",
  PARTY_LEADER = "PARTY", RAID = "RAID", RAID_LEADER = "RAID", RAID_WARNING = "RAID_WARNING",
  INSTANCE_CHAT = "INSTANCE", INSTANCE_CHAT_LEADER = "INSTANCE" }

---Where the box will send: the chat type and, for whispers and channels, the target.
local function destination(box)
  local ok, ctype = pcall(box.GetChatType, box)
  if not ok or type(ctype) ~= "string" then ctype = "SAY" end
  local target
  if (ctype == "WHISPER" or ctype == "BN_WHISPER") and box.GetTellTarget then
    local ok2, t = pcall(box.GetTellTarget, box)
    if ok2 and type(t) == "string" and not Hidden(t) then target = t end
  elseif ctype == "CHANNEL" and box.GetChannelTarget then
    local ok2, t = pcall(box.GetChannelTarget, box)
    if ok2 and not Hidden(t) then target = t end
  end
  return ctype, target
end

local function channelName(num)
  num = tonumber(num)
  if not (num and GetChannelName) then return nil end
  local _, name = GetChannelName(num)
  return type(name) == "string" and name or nil
end

---The chip's words and colour for a destination.
function P.DestLabel(ctype, target)
  local info
  local text
  if ctype == "WHISPER" and target then
    text, info = Core.Names.Full(target) or target, ChatTypeInfo and ChatTypeInfo.WHISPER
  elseif ctype == "BN_WHISPER" and target then
    text, info = target, ChatTypeInfo and ChatTypeInfo.BN_WHISPER   -- the friend's token shows their name
  elseif ctype == "CHANNEL" and target then
    local key = P.ChannelKey(channelName(target))
    text = key and P.Short(key) or tostring(target)
    info = ChatTypeInfo and (ChatTypeInfo["CHANNEL" .. tostring(target)] or ChatTypeInfo.CHANNEL)
  else
    text = L.dest[TYPE_KIND[ctype] or ""] or L.dest.SAY
    info = ChatTypeInfo and ChatTypeInfo[ctype]
  end
  return text, info or { r = 1, g = 1, b = 1 }
end

local lastDest
local function updateChip(box)
  local ctype, target = destination(box)
  local key = ctype .. "\0" .. tostring(target)
  if key == lastDest then return end
  lastDest = key
  local text, info = P.DestLabel(ctype, target)
  chip.label:SetText(text)
  chip.label:SetTextColor(info.r or 1, info.g or 1, info.b or 1)
  chip:SetWidth(math.floor((chip.label:GetStringWidth() or 30) + 27))
end

local TEXT_INSET = 8   -- the box starts right after the chip; the typed text a little further in

-------------------------------------------------------------------------------------------
-- The language pill: which language you're speaking, and the game's chat menu to change it
-------------------------------------------------------------------------------------------

local MENU = "ChatFrameMenuButton"

---Lay the game's chat menu button over the pill, see-through (widget calls and HookScript only).
local function placeMenuButton()
  local btn = rawget(_G, MENU)
  if not (btn and btn.SetParent and btn.SetAllPoints) then return false end
  if btn:GetParent() ~= lang then btn:SetParent(lang) end
  if not lang.hooked then
    lang.hooked = true
    btn:HookScript("OnEnter", function()
      lang.hover = true
      paintLanguage()
      if lang.choice then
        UI.Tip(lang, L.languageTip:format(lang.name or "", rawget(_G, "LANGUAGE") or L.languageMenu))
      else
        UI.Tip(lang, L.chatMenuTip)
      end
    end)
    btn:HookScript("OnLeave", function()
      lang.hover = false
      paintLanguage()
      GameTooltip:Hide()
    end)
    btn:HookScript("OnMouseDown", function() GameTooltip:Hide() end)   -- the game's menu opens on the press
  end
  btn:ClearAllPoints()
  btn:SetAllPoints(lang)
  btn:SetFrameLevel(lang:GetFrameLevel() + 2)
  -- the game fades this button with its chat window: its own art goes for good, the frame stays clickable
  btn:SetAlpha(0)
  for _, region in ipairs({ btn:GetRegions() }) do
    if region.SetAlpha then region:SetAlpha(0) end
  end
  btn:Show()
  return true
end

---The game's chat menu icon, read from its own button (Parley's pill shows it when there's no language to name).
local function copyMenuIcon(btn)
  if lang.iconSet then return true end
  local tex = btn.GetNormalTexture and btn:GetNormalTexture()
  if not tex then return false end
  local atlas = tex.GetAtlas and tex:GetAtlas()
  if type(atlas) == "string" and atlas ~= "" then
    lang.icon:SetAtlas(atlas)
  else
    local file = tex.GetTexture and tex:GetTexture()
    if not file then return false end
    lang.icon:SetTexture(file)
    if tex.GetTexCoord then pcall(lang.icon.SetTexCoord, lang.icon, tex:GetTexCoord()) end
  end
  lang.iconSet = true
  return true
end

local lastCount, lastName, lastID = -1, false, false
---Show the pill: the game's chat menu under it, and for a character with more than one language, which one the box
---speaks now.
function P.UpdateLanguage(box)
  local count = GetNumLanguages and GetNumLanguages() or 0
  if type(count) ~= "number" or Hidden(count) then count = 0 end
  local name, id = box.language, box.languageID
  if Hidden(name) then name = nil end
  if Hidden(id) then id = nil end
  if count == lastCount and name == lastName and id == lastID then return end
  lastCount, lastName, lastID = count, name, id

  local defName, defID
  if GetDefaultLanguage then defName, defID = GetDefaultLanguage() end
  if type(name) ~= "string" and id ~= nil and GetLanguageByIndex then
    for i = 1, count do
      local n, lid = GetLanguageByIndex(i)
      if lid == id then name = n end
    end
  end
  if type(name) ~= "string" then name, id = defName, defID end

  local choice = count > 1 and type(name) == "string" and name ~= ""
  local wanted = placeMenuButton()
  lang.wanted, lang.choice = wanted, choice and true or false
  if wanted then
    if choice then
      lang.name = name
      if type(id) == "number" and type(defID) == "number" then lang.other = id ~= defID else lang.other = name ~= defName end
      lang.icon:Hide()
      lang.label:SetText(name)
      lang.arrow:Show()
      lang:SetWidth(math.floor((lang.label:GetStringWidth() or 40) + 27))
    elseif copyMenuIcon(rawget(_G, MENU)) then
      lang.name, lang.other = nil, false
      lang.label:SetText("")
      lang.arrow:Hide()
      lang.icon:Show()
      lang:SetWidth(28)
    else
      lang.name, lang.other = nil, false
      lang.icon:Hide()
      lang.label:SetText(L.emoteMenu)
      lang.arrow:Show()
      lang:SetWidth(math.floor((lang.label:GetStringWidth() or 40) + 27))
    end
    paintLanguage()
    lang:Show()
  else
    lang:Hide()
    local btn = rawget(_G, MENU)
    if btn and btn.GetParent and btn:GetParent() ~= vault then P.Safe(btn.SetParent, btn, vault) end
  end
  layoutTail()
end

-- every frame while typing (four times a second otherwise): the chip and the pill follow the box
local wait = 0
home:SetScript("OnUpdate", function(_, dt)
  local box = P.box
  if not box then return end
  local shown = box:IsShown()
  wait = wait - dt
  if not shown and wait > 0 then return end
  wait = .25
  idle:SetShown(not shown)
  if shown ~= home.typing then
    home.typing = shown
    home.line:SetColor(shown and TYPING or QUIET, shown and .6 or .5)
  end
  updateChip(box)
  P.UpdateLanguage(box)

  if box:HasFocus() then home:SetAlpha(1) end
  if shown then
    -- the game widens the box's left inset for its own "Guild:" header, which the chip replaces
    local left = box:GetTextInsets()
    if not left or math.abs(left - TEXT_INSET) > .5 then box:SetTextInsets(TEXT_INSET, 8, 0, 0) end
  end
end)

home:SetScript("OnClick", function()
  if P.box and not P.box:IsShown() then ChatFrameUtil.OpenChat("", DEFAULT_CHAT_FRAME) end
end)
chip:SetScript("OnMouseDown", function()
  -- keep what's typed: the box may close when the chip takes the click
  local text = P.box and P.box:IsShown() and P.box:GetText() or ""
  P.chipText = (type(text) == "string" and not Hidden(text)) and text or ""
end)
chip:SetScript("OnClick", function(self)
  local ok, err = pcall(P.DestMenu, P, self)
  if not ok then P:Print(L.chipFailed:format(tostring(err))) end
end)

---The idle chat box fades with the headers; while typing it always shows.
function P:SetComposeAlpha(a)
  if not (self.box and self.box:HasFocus()) then home:SetAlpha(a) end
end

---The people you whispered with last, newest first: { label, bn = account id for a Battle.net friend }.
local function recentWhispers(n)
  local out, seen = {}, {}
  local function take(r)
    local key = P.ConvoKey(r)
    if not key or seen[key] then return end
    if r.bn then
      local id = r.bnID
      if not P.BNAccount(id) then
        local info = r.bnTag and P.BNByTag(r.bnTag)
        id = info and info.bnetAccountID
      end
      if not id then return end   -- no longer on your friends list
      seen[key] = true
      out[#out + 1] = { label = r.who, bn = id }
    else
      seen[key] = true
      out[#out + 1] = { label = Core.Names.Full(r.who) or r.who }
    end
  end
  for i = #P.records, 1, -1 do
    local r = P.records[i]
    if r.kind == "WHISPER" and (P.WHISPER_IN[r.type] or P.WHISPER_OUT[r.type]) then take(r) end
    if #out >= n then return out end
  end
  local saved = P.char.history.WHISPER or {}
  for i = #saved, 1, -1 do
    local e = saved[i]
    local r = { type = e[2], who = e[3], kind = "WHISPER" }
    P:BNRestore(r)
    take(r)
    if #out >= n then break end
  end
  return out
end

---Where else the line could go: the chats you can use now, your channels and the people you whispered last.
function P:DestMenu(owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  local text = self.chipText or ""
  local function go(prefix) ChatFrameUtil.OpenChat(prefix .. text, DEFAULT_CHAT_FRAME) end
  local function colored(label, ctype)
    local info = ChatTypeInfo and ChatTypeInfo[ctype]
    if not info then return label end
    return "|c" .. P.Hex(info.r, info.g, info.b) .. label .. "|r"
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(L.sendTo)
    root:CreateButton(colored(L.dest.SAY, "SAY"), function() go("/s ") end)
    root:CreateButton(colored(L.dest.YELL, "YELL"), function() go("/y ") end)
    if IsInGuild and IsInGuild() then
      root:CreateButton(colored(L.dest.GUILD, "GUILD"), function() go("/g ") end)
      root:CreateButton(colored(L.dest.OFFICER, "OFFICER"), function() go("/o ") end)
    end
    if IsInGroup and IsInGroup() then root:CreateButton(colored(L.dest.PARTY, "PARTY"), function() go("/p ") end) end
    if IsInRaid and IsInRaid() then root:CreateButton(colored(L.dest.RAID, "RAID"), function() go("/ra ") end) end
    local instance = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
    if instance and IsInGroup and IsInGroup(instance) then
      root:CreateButton(colored(L.dest.INSTANCE, "INSTANCE_CHAT"), function() go("/i ") end)
    end
    local list = GetChannelList and { GetChannelList() } or {}
    if #list > 0 then root:CreateDivider() end
    for i = 1, #list, 3 do
      local num, name = list[i], list[i + 1]
      if type(num) == "number" and type(name) == "string" then
        local key = P.ChannelKey(name)
        local label = (key and P.Short(key) or name) .. "  |cff6e6552" .. name .. "|r"
        root:CreateButton(colored(label, "CHANNEL" .. num), function() go("/" .. num .. " ") end)
      end
    end
    local people = recentWhispers(6)
    if #people > 0 then
      root:CreateDivider()
      root:CreateTitle(L.recentWhispers)
      for _, p in ipairs(people) do
        if p.bn then
          -- the box keeps what's typed, then the game's own call turns it into a whisper to them
          root:CreateButton(colored(p.label, "BN_WHISPER"), function() go(""); P.BNTell(p.bn) end)
        else
          root:CreateButton(colored(p.label, "WHISPER"), function() go("/w " .. p.label .. " ") end)
        end
      end
    end
  end)
end

local function grab(box)
  if boxes[box] then return end
  box:SetParent(home)
  box:ClearAllPoints()
  box:SetPoint("LEFT", chip, "RIGHT", 2, 0)     -- beside the chip, not over it (see the chip above)
  box:SetPoint("RIGHT", tail, "LEFT", 0, 0)
  box:SetHeight(P.COMPOSE_H)
  local name = box:GetName()
  for _, part in ipairs(ART) do
    local tex = name and rawget(_G, name .. part)
    if tex then tex:SetAlpha(0) end
  end
  for _, key in ipairs({ "focusLeft", "focusMid", "focusRight", "header", "headerSuffix" }) do
    local region = box[key]
    if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end   -- the chip says where it goes
  end
  box:HookScript("OnHide", function() counter:SetText("") end)
  box:HookScript("OnShow", function(self) if P.ConvoBoxOpened then P:ConvoBoxOpened(self) end end)
  -- Ctrl-F while typing opens search on the window the box sits in (the mock-up's search screen)
  box:HookScript("OnKeyDown", function(self, key)
    if key == "F" and IsControlKeyDown() and P.OpenSearch then
      self:ClearFocus()
      P:OpenSearch(P.dockWin)
    end
  end)
  box:HookScript("OnTextChanged", function(self)
    local text = self:GetText()
    local plain = type(text) == "string" and not Hidden(text)
    local n = plain and #text or 0
    counter:SetText(n >= 200 and (n .. "/255") or "")
    -- typing a /command: what add-ons print in the next moments is its reply, shown where you're reading
    if plain and text:sub(1, 1) == "/" then P.replyUntil = GetTime() + 4 end
  end)
  boxes[box] = true
end

---Put the chat box at the bottom of a window (the one you last used).
function P:DockBox(win)
  if not win or not self.box then return end
  local old = self.dockWin
  self.dockWin = win
  home:SetParent(win.frame)
  home:ClearAllPoints()
  home:SetPoint("BOTTOMLEFT", win.frame, "BOTTOMLEFT", 8, 8)
  home:SetPoint("BOTTOMRIGHT", win.frame, "BOTTOMRIGHT", -8, 8)
  home:SetFrameLevel(win.frame:GetFrameLevel() + 10)
  home:Show()
  local alerts = rawget(_G, "ChatAlertFrame")
  if alerts and P.hosts.ChatAlertFrame then P.Safe(P.hosts.ChatAlertFrame, alerts) end   -- the popups follow the box
  if old and old ~= win and old.frame then self:LayoutBody(old) end
  self:LayoutBody(win)
end

-------------------------------------------------------------------------------------------
-- The game's chat windows, out of sight
-------------------------------------------------------------------------------------------

-- Some of the game's chat frames have a place in Parley instead of the vault: the combat log in a Combat log pane
-- (combatlog.lua), the alerts above the window with the chat box. P.hosts[name] places one and returns true, or false
-- when it has nowhere to go.
P.hosts = P.hosts or {}

local function hosted(name, f)
  local place = P.hosts[name]
  if not place then return false end
  local ok, placed = pcall(place, f)
  return ok and placed == true
end

-- Battle.net and quick-join popups hang off the game's chat alert frame: it sits above the window with the chat box
P.hosts.ChatAlertFrame = function(f)
  local win = P.dockWin
  if not (win and win.frame) then return false end
  if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", win.frame, "TOPLEFT", 0, 6)
  return true
end

local function sweep()
  for i = 1, 30 do
    local name = "ChatFrame" .. i
    local f = rawget(_G, name)
    if f and f.GetParent and not hosted(name, f) and f:GetParent() ~= vault then P.Safe(f.SetParent, f, vault) end
    local tab = rawget(_G, name .. "Tab")
    if tab and tab:GetParent() == UIParent then P.Safe(tab.SetParent, tab, vault) end
    local box = rawget(_G, name .. "EditBox")
    if box then P.Safe(grab, box) end
  end
  for _, name in ipairs(HIDE) do
    local f = rawget(_G, name)
    -- the chat menu button stays on the pill at the box's right end
    if f and f.SetParent and not (name == MENU and lang.wanted) and not hosted(name, f) and f:GetParent() ~= vault then
      P.Safe(f.SetParent, f, vault)
    end
  end
  if lang.wanted then P.Safe(placeMenuButton) end   -- the game re-anchors it when its chat windows dock
end
P.SweepChat = function() P.Safe(sweep) end

-------------------------------------------------------------------------------------------
-- Lines other add-ons print into the game's chat windows
-------------------------------------------------------------------------------------------

local pending = {}
local flushing = false
local lastPrint, lastPrintT

-- The game's chat windows also print lines of their own, from no chat event: the guild's message of the day, level-ups,
-- /played, Battle.net and chat server disconnects, chats Parley doesn't route itself. Each comes with its chat type's
-- id, so it goes to that chat (guild, system, a channel), not to the Add-ons tab.
local typeOfId = {}   -- [ChatTypeInfo id] = chat type ("GUILD", "CHANNEL5"), or false when no chat type has it

local function chatTypeOf(id)
  local t = typeOfId[id]
  if t == nil then
    for name, info in pairs(ChatTypeInfo or {}) do
      if type(info) == "table" and type(info.id) == "number" and typeOfId[info.id] == nil then typeOfId[info.id] = name end
    end
    t = typeOfId[id] or false
    typeOfId[id] = t
  end
  return t or nil
end

---The chat a game-printed line belongs to: a channel by its number, or the chat its type routes to.
local function gameKind(ctype)
  local num = tonumber(ctype:match("^CHANNEL(%d+)$"))
  if num then
    for key, n in pairs(P.chanNum) do if n == num then return key, num end end
    return "SYSTEM"
  end
  return P.KIND_OF[ctype] or "SYSTEM"
end

local function copy(text, r, g, b, id)
  if text == nil then return end
  if not Hidden(text) then
    if type(text) ~= "string" or text == "" then return end
    local now = GetTime()
    if lastPrint == text and lastPrintT == now then return end   -- the same line printed into two windows
    lastPrint, lastPrintT = text, now
  end
  local ctype = id ~= nil and chatTypeOf(id)
  local rec
  if ctype then
    local kind, num = gameKind(ctype)
    rec = P:NewRecord(kind, "GAME")
    if num then rec.chan, rec.num = true, num end
    P.diag.gameLines = (P.diag.gameLines or 0) + 1
  else
    local reply = (P.replyUntil and GetTime() <= P.replyUntil)
      or (not Hidden(text) and type(text) == "string" and P.PREFIX and text:find(P.PREFIX, 1, true) == 1)
    rec = P:NewRecord(reply and "SYSTEM" or "ADDONS", "ADDON")
    P.diag.copies = P.diag.copies + 1
  end
  rec.text = text
  rec.typeColor = { r = r or 1, g = g or 1, b = b or 1 }   -- the words keep the line's own colour; the bar is its chat's
  P:Deliver(rec)
end

local function flush()
  flushing = false
  local list = pending
  pending = {}
  for _, p in ipairs(list) do
    if P.sawType[p.id] ~= p.t then copy(p.text, p.r, p.g, p.b, p.id) end
  end
end

local function onAddMessage(_, text, r, g, b, id)
  if id ~= nil and not Hidden(id) and type(id) == "number" then
    -- a line the game made from a chat event: Parley shows that event itself
    local now = GetTime()
    if P.sawType[id] == now then return end
    -- a friend coming online: the game writes its line a moment later, once it has the game's icon
    if P.bnLate and P.bnLate[id] and now <= P.bnLate[id] then return end
    pending[#pending + 1] = { text = text, r = r, g = g, b = b, id = id, t = now }
    if not flushing then flushing = true; C_Timer.After(0, flush) end
    return
  end
  copy(text, r, g, b)
end

local hooked = {}
local function hookPrints()
  for i = 1, 30 do
    local f = rawget(_G, "ChatFrame" .. i)
    if f and not hooked[f] and f.AddMessage then
      hooked[f] = true
      hooksecurefunc(f, "AddMessage", onAddMessage)
    end
  end
end

-- lines printed while the game was loading, before Parley was there to see them
local function copyEarlier()
  local f = DEFAULT_CHAT_FRAME
  if not (f and f.GetNumMessages and f.GetMessageInfo) then return end
  local n = f:GetNumMessages()
  if type(n) ~= "number" then return end
  for i = 1, n do
    local text, r, g, b, id = f:GetMessageInfo(i)
    if id == nil then copy(text, r, g, b) end
  end
end

-------------------------------------------------------------------------------------------
-- "No player named Kuma": offer the full name, one click to try again
-------------------------------------------------------------------------------------------

local lastTold = {}     -- [lower-case target] = the last whisper text sent to them
local resends = {}
local NOT_FOUND

local function remember(text, kind, _, target)
  if kind == "WHISPER" and type(target) == "string" and type(text) == "string" and not Hidden(target) and not Hidden(text) then
    lastTold[target:lower()] = text
  end
end

local function notFound(_, text)
  if Hidden(text) or type(text) ~= "string" or not NOT_FOUND then return end
  local name = text:match(NOT_FOUND)
  if not name or name:find(" ") then return end
  local full = Core.Names:Address(name)
  if not full or full == name then return end
  resends[#resends + 1] = { to = full, text = lastTold[name:lower()] }
  local link = "|cff" .. P.ACCENT_HEX .. "|Haddon:Parley:resend:" .. #resends .. "|h[" .. L.sendAgainLink .. "]|h|r"
  P:Note(L.sendAgain:format(name, full) .. " " .. link, "WHISPER", { convoKey = full:lower() })
end

function P:Resend(index)
  local r = resends[index]
  if not r then return end
  ChatFrameUtil.OpenChat("/w " .. r.to .. " " .. (r.text or ""))
end

-------------------------------------------------------------------------------------------
-- Start
-------------------------------------------------------------------------------------------

function P:TakeOver()
  local main = (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or rawget(_G, "ChatFrame1EditBox")
  if not main or not self.windows[1] then
    self:Print(L.boxFailed)
    return false
  end
  if not P.Safe(grab, main) then
    self:Print(L.boxFailed)
    return false
  end
  self.box = main
  self.diag.box = true
  self:DockBox(self.dockWin or self.windows[1])   -- after the box is Parley's: docking needs it (it was a no-op before)
  sweep()
  for _, fn in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow", "FCF_DockUpdate", "FCF_UnDockFrame",
      "FCF_RestorePositionAndDimensions" }) do
    if type(rawget(_G, fn)) == "function" then hooksecurefunc(fn, function() C_Timer.After(0, sweep); C_Timer.After(0, hookPrints) end) end
  end
  -- "Move to whisper window" on a name's menu: Parley's conversation with them instead of a hidden game window
  if type(rawget(_G, "FCF_OpenTemporaryWindow")) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", function(chatType, target) P:MovedToWhisperWindow(chatType, target) end)
  end
  -- the game's chat keys scroll Parley's pane (they'd scroll the game's hidden window)
  local util = rawget(_G, "ChatFrameUtil")
  for fn, how in pairs({ ChatPageUp = "PageUp", ChatPageDown = "PageDown", ScrollToBottom = "ScrollToBottom" }) do
    if util and type(util[fn]) == "function" then hooksecurefunc(util, fn, function() P:ScrollShown(how) end) end
  end
  -- the game's calls that open the box on a whisper (the Reply keys, a name's Whisper, a Battle.net friend's): a person
  -- picked in the whisper list never overrides them
  for _, fn in ipairs({ "ReplyTell", "ReplyTell2", "SendTellWithMessage", "SendBNetTell" }) do
    if util and type(util[fn]) == "function" then hooksecurefunc(util, fn, function() P.toldAt = GetTime() end) end
  end
  -- a chat's colour changed (Parley's Channel names panel or the game's settings): the lines follow
  Core:On("UPDATE_CHAT_COLOR", "parley.colors", function()
    C_Timer.After(0, function() P:RedrawAll(); if P.RefreshNames then P:RefreshNames() end end)
  end)
  -- Edit Mode owns the game's chat window position; put it back out of sight when Edit Mode closes
  local editMode = rawget(_G, "EditModeManagerFrame")
  if editMode and type(editMode.ExitEditMode) == "function" then
    hooksecurefunc(editMode, "ExitEditMode", function() C_Timer.After(0, sweep) end)
  end
  return true
end

P:OnReady(function()
  if not P.db.takeover then
    Core:OnLogin(function() P:Print(L.turnedOff) end)
    return
  end
  local fmt = rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S")
  if type(fmt) == "string" then
    local s = fmt:gsub("%%s", "\1"):gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"):gsub("\1", "(.+)")
    NOT_FOUND = "^" .. s .. "$"
  end
  if C_ChatInfo and C_ChatInfo.SendChatMessage then hooksecurefunc(C_ChatInfo, "SendChatMessage", remember) end
  if SendChatMessage and SendChatMessage ~= (C_ChatInfo and C_ChatInfo.SendChatMessage) then
    hooksecurefunc("SendChatMessage", remember)
  end
  Core:On("CHAT_MSG_SYSTEM", "parley.resend", notFound)
  Core:OnLogin(function()
    P.Safe(hookPrints)
    P.Safe(copyEarlier)
    P:TakeOver()
  end)
end)
