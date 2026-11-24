-- Channel names and Alerts, as the mock-up's panels: they open beside the chat window, so the lines change in front of
-- you while you edit. Channel names: how a chat shows (short name, number, full name, only the bar), a short name for
-- each channel and chat, and the command each short name makes. Alerts: a box to type a phrase or Shift-click an item
-- into, then one row per alert with its switch, what it watches, where and when, and how it tells you.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C

local ACCENT = UI.Hex(P.ACCENT_HEX)
local W = 508
local PANEL_GAP = 24
local TOP = 52       -- where a panel's contents start, under its title's line

-------------------------------------------------------------------------------------------
-- A panel: the suite window's recipe, its title over the fading line, a close button
-------------------------------------------------------------------------------------------

local function panel(name, title)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetWidth(W)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.moved = true end)
  P.Panel(f)
  P.PanelTitle(f, title, 18, 14, -11, TOP - 12)
  f.close = UI.CloseButton(f, function() f:Hide() end)
  f.close:SetPoint("TOPRIGHT", -8, -8)
  f:Hide()
  tinsert(UISpecialFrames, name)
  return f
end

local function sub(parent, text, size)
  local fs = UI.Text(parent, "body", size or 12, C.muted)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  fs:SetText(text)
  return fs
end

local function label(parent, text)
  local fs = UI.Text(parent, "body", 11, C.faint)
  fs:SetText(text:upper())
  return fs
end

---Beside the window with the chat box: on its right when there's room, else its left; bottoms lined up.
local function place(f)
  if f.moved then return end
  local win = P.dockWin or P.windows[1]
  f:ClearAllPoints()
  if not win then f:SetPoint("CENTER"); return end
  local screen = UIParent:GetWidth() or 1366
  local right = win.frame:GetRight() or 0
  if right + PANEL_GAP + W <= screen then
    f:SetPoint("BOTTOMLEFT", win.frame, "BOTTOMRIGHT", PANEL_GAP, 0)
  elseif (win.frame:GetLeft() or 0) - PANEL_GAP - W >= 0 then
    f:SetPoint("BOTTOMRIGHT", win.frame, "BOTTOMLEFT", -PANEL_GAP, 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  end
end

-- a small text box with a faint placeholder (the default it goes back to when cleared). Typing shows in the lines at
-- once (onType); the name is kept, and its command made, when you press Enter or leave the box (onDone, once).
local function aliasBox(parent, width, onType, onDone)
  local box
  local function done(text)
    if text == box.committed then return end
    box.committed = text
    onDone(text)
  end
  box = P.Own(UI.Input(parent, { size = 13, maxLetters = 20, onSubmit = done, onChange = onType }))
  box:SetSize(width, 22)
  box.placeholder = UI.Text(box, "body", 13, C.faint)
  box.placeholder:SetPoint("LEFT", 8, 0)
  box.edit:HookScript("OnTextChanged", function(self) box.placeholder:SetShown(self:GetText() == "") end)
  box.edit:HookScript("OnEditFocusLost", function(self) done(self:GetText()) end)
  function box:Fill(text)
    if self.edit:HasFocus() then return end
    self.committed = text
    self:SetText(text)
  end
  return box
end

local function swatch(parent, key)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(12, 12)
  t:SetColorTexture(P.KindColor(key))
  return t
end

-- The game keeps one colour per chat type; a chat here covers its group (Party covers the party leader's lines too),
-- a channel its number. Changing it is the game's own setting, so the game's chat and other add-ons follow.
local function chatTypesOf(key)
  if P.IsChannel(key) then
    local num = P.chanNum[key]
    return num and { "CHANNEL" .. num } or {}
  end
  local group = key == "INSTANCE" and "INSTANCE_CHAT" or key
  local list = {}
  local groups = rawget(_G, "ChatTypeGroup")
  if type(groups) == "table" and type(groups[group]) == "table" then
    for _, event in ipairs(groups[group]) do
      local t = type(event) == "string" and event:match("^CHAT_MSG_(.+)$")
      if t then list[#list + 1] = t end
    end
  end
  if #list == 0 then list[1] = group end
  return list
end
P.ChatTypesOf = chatTypesOf

---Open the game's colour picker on a chat or channel; Cancel puts the old colour back.
function P:PickChatColor(key)
  local types = chatTypesOf(key)
  local change, picker = rawget(_G, "ChangeChatColor"), rawget(_G, "ColorPickerFrame")
  if #types == 0 or not change or not (picker and picker.SetupColorPickerAndShow) then return false end
  local r0, g0, b0 = P.KindColor(key)
  local function set(r, g, b) for _, t in ipairs(types) do change(t, r, g, b) end end
  picker:SetupColorPickerAndShow({ r = r0, g = g0, b = b0, hasOpacity = false,
    swatchFunc = function() set(picker:GetColorRGB()) end,
    cancelFunc = function() set(r0, g0, b0) end })
  return true
end

---Make a swatch a button: click to change the chat's colour.
local function pickable(parent, tex, keyOf)
  local b = CreateFrame("Button", nil, parent)
  b:SetPoint("TOPLEFT", tex, "TOPLEFT", -3, 3)
  b:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 3, -3)
  b:SetScript("OnClick", function() P:PickChatColor(keyOf()) end)
  b:SetScript("OnEnter", function(self) UI.Tip(self, L.colorTip) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-------------------------------------------------------------------------------------------
-- Channel names
-------------------------------------------------------------------------------------------

local names
local SHOW = { "short", "number", "full", "bar" }
local CHATS = { "SAY", "YELL", "EMOTE", "GUILD", "OFFICER", "PARTY", "RAID", "WHISPER" }
local CH_ROW = 27

local function channelRow(i)
  local row = names.chanRows[i]
  if row then return row end
  row = CreateFrame("Frame", nil, names)
  row:SetHeight(CH_ROW)
  row.num = UI.Text(row, "body", 13, C.faint)
  row.num:SetPoint("RIGHT", row, "LEFT", 18, 0)
  row.num:SetJustifyH("RIGHT")
  row.name = UI.Text(row, "body", 14, C.text)
  row.name:SetPoint("LEFT", 26, 0)
  row.name:SetPoint("RIGHT", -170, 0)
  row.input = aliasBox(row, 80, function(text) P:SetShort(row.key, text, true) end, function(text)
    P:SetShort(row.key, text)
    names:Refresh()
  end)
  row.input:SetPoint("RIGHT", -82, 0)
  row.sw = row:CreateTexture(nil, "ARTWORK")
  row.sw:SetSize(12, 12)
  row.sw:SetPoint("LEFT", row.input, "RIGHT", 8, 0)
  row.pick = pickable(row, row.sw, function() return row.key end)
  row.cmd = UI.Text(row, "body", 12, C.faint)
  row.cmd:SetPoint("LEFT", row.sw, "RIGHT", 8, 0)
  row.rule = P.Hairline(row)
  row.rule:SetPoint("BOTTOMLEFT")
  row.rule:SetPoint("BOTTOMRIGHT")
  row.rule:SetHeight(1)
  names.chanRows[i] = row
  return row
end

local function buildNames()
  names = panel("ParleyChannelNames", L.namesTitle)
  names.sub = sub(names, L.namesSub)
  names.sub:SetPoint("TOPLEFT", 14, -TOP)
  names.sub:SetPoint("RIGHT", -14, 0)
  names.showLabel = UI.Text(names, "body", 14, C.text)
  names.showLabel:SetText(L.set.showAs)
  local items = {}
  for _, key in ipairs(SHOW) do items[#items + 1] = { key = key, label = L.showAsShort[key] } end
  names.show = UI.Segmented(names, items, function(key) P.db.showAs = key; P:RedrawAll() end, 22)
  if names.show.ApplyAccent then names.show:ApplyAccent(ACCENT) end
  names.chanLabel = label(names, L.channelsLabel)
  names.chatLabel = label(names, L.chatsLabel)
  names.chanRows = {}
  names.cells = {}
  for i, key in ipairs(CHATS) do
    local cell = CreateFrame("Frame", nil, names)
    cell:SetSize((W - 28 - 36) / 4, 24)
    cell.sw = swatch(cell, key)
    cell.sw:SetPoint("LEFT", 0, 0)
    cell.pick = pickable(cell, cell.sw, function() return key end)
    cell.name = UI.Text(cell, "body", 13, { 220 / 255, 212 / 255, 191 / 255 })
    cell.name:SetPoint("LEFT", cell.sw, "RIGHT", 5, 0)
    cell.name:SetText(P.KindLabel(key))
    cell.input = aliasBox(cell, 40, function(text) P:SetShort(key, text, true) end, function(text)
      P:SetShort(key, text)
    end)
    cell.input:SetPoint("RIGHT", 0, 0)
    cell.key = key
    names.cells[i] = cell
  end
  names.foot = sub(names, L.namesFoot)
  names:HookScript("OnShow", function() names:Refresh() end)

  function names:Refresh()
    local y = -TOP - (self.sub:GetStringHeight() or 16) - 12
    self.showLabel:ClearAllPoints()
    self.showLabel:SetPoint("TOPLEFT", 14, y - 3)
    self.show:ClearAllPoints()
    self.show:SetPoint("TOPRIGHT", -14, y)
    self.show:Select(P.db.showAs or "short", true)
    y = y - 34
    self.chanLabel:ClearAllPoints()
    self.chanLabel:SetPoint("TOPLEFT", 14, y)
    y = y - 16
    local n = 0
    for _, key in ipairs(P:PickerKinds()) do
      if P.IsChannel(key) then
        n = n + 1
        local row = channelRow(n)
        row.key = key
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 14, y)
        row:SetPoint("RIGHT", -14, 0)
        local num = P.chanNum and P.chanNum[key]
        row.num:SetText(num and tostring(num) or "")
        row.name:SetText(P.KindLabel(key))
        row.sw:SetColorTexture(P.KindColor(key))
        row.input.placeholder:SetText(P.DefaultShort(key))
        row.input:Fill(P.db.short[key] or "")
        local state, cmd = P:CommandState(key)
        row.cmd:SetText(state == "ok" and cmd or "")
        row:Show()
        y = y - CH_ROW
      end
    end
    for i = n + 1, #self.chanRows do self.chanRows[i]:Hide() end
    y = y - 10
    self.chatLabel:ClearAllPoints()
    self.chatLabel:SetPoint("TOPLEFT", 14, y)
    y = y - 18
    for i, cell in ipairs(self.cells) do
      local col, line = (i - 1) % 4, math.floor((i - 1) / 4)
      cell:ClearAllPoints()
      cell:SetPoint("TOPLEFT", 14 + col * (cell:GetWidth() + 12), y - line * 30)
      cell.sw:SetColorTexture(P.KindColor(cell.key))   -- a colour changed in the game's picker
      cell.input.placeholder:SetText(P.DefaultShort(cell.key))
      cell.input:Fill(P.db.short[cell.key] or "")
    end
    y = y - 2 * 30 - 6
    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOPLEFT", 14, y)
    self.foot:SetPoint("RIGHT", -14, 0)
    self:SetHeight(-y + (self.foot:GetStringHeight() or 16) + 14)
  end
end

function P:RefreshNames()
  if names and names:IsShown() then names:Refresh() end
end

function P:OpenNames()
  if not names then buildNames() end
  place(names)
  names:Show()
  names:Refresh()
end

-------------------------------------------------------------------------------------------
-- Alerts
-------------------------------------------------------------------------------------------

local alerts
local A_ROW = 46
local OUTS = { "toast", "sound", "flash" }
local WHERE = { "public", "all" }
local WHEN = { "always", "solo", "cities", "outside" }

---How an alert reads in its row: words in white joined by "and", a rule-out after them, items as their links.
local function alertText(text)
  local words, nots, items = {}, {}, {}
  for link in text:gmatch("|c%x+|Hitem:.-|h.-|h|r") do items[#items + 1] = link end
  local plain = text:gsub("|c%x+|Hitem:.-|h.-|h|r", " ")
  for word in plain:gmatch("%S+") do
    if word:sub(1, 1) == "-" and #word > 1 then nots[#nots + 1] = word else words[#words + 1] = word end
  end
  local parts = {}
  for _, link in ipairs(items) do parts[#parts + 1] = link end
  for _, w in ipairs(words) do parts[#parts + 1] = "|cffffffff" .. w .. "|r" end
  local out = table.concat(parts, " |cffa8a08a" .. L.alertAnd .. "|r ")
  for _, w in ipairs(nots) do out = out .. " |cffffffff" .. w .. "|r" end
  if out == "" then return text end
  return out
end

local function whereText(a)
  local s = L.alertWhere[a.where or "public"] or ""
  if (a.when or "always") ~= "always" then s = s .. "  \194\183  " .. (L.alertWhen[a.when] or ""):lower() end
  return s
end

local function outPill(parent, out, row)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(16)
  P.SwitchPill(b)
  b.text = UI.Text(b, "body", 11, C.muted)
  b.text:SetPoint("CENTER", 0, 0)
  b.text:SetText(L.alertOut[out])
  b:SetWidth((b.text:GetStringWidth() or 30) + 14)
  b.out = out
  function b:Paint(on)
    self.lit = on and true or false
    self:SetLit(self.lit, self.hover)
    local c = on and C.text or C.muted
    self.text:SetTextColor(c[1], c[2], c[3])
  end
  b:SetScript("OnClick", function(self)
    local a = P.db.alerts[row.index]
    if not a then return end
    a.outs = a.outs or P.AlertOuts(a)
    a.outs[self.out] = not a.outs[self.out]
    self:Paint(a.outs[self.out])
    P:CompileAlerts()
  end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    self:SetLit(self.lit, true)
    UI.Tip(self, L.alertOutTip[self.out])
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    self:SetLit(self.lit, false)
    GameTooltip:Hide()
  end)
  return b
end

local function alertMenu(row, owner)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(L.alertWhereTitle)
    for _, key in ipairs(WHERE) do
      root:CreateRadio(L.alertWhere[key], function() local a = P.db.alerts[row.index]; return a and (a.where or "public") == key end,
        function() local a = P.db.alerts[row.index]; if a then a.where = key; P:CompileAlerts(); alerts:Refresh() end end)
    end
    root:CreateTitle(L.alertWhenTitle)
    for _, key in ipairs(WHEN) do
      root:CreateRadio(L.alertWhen[key], function() local a = P.db.alerts[row.index]; return a and (a.when or "always") == key end,
        function() local a = P.db.alerts[row.index]; if a then a.when = key; P:CompileAlerts(); alerts:Refresh() end end)
    end
    root:CreateDivider()
    root:CreateButton(L.alertEdit, function() row:Edit() end)
    root:CreateButton(L.alertRemove, function()
      table.remove(P.db.alerts, row.index)
      P:CompileAlerts()
      alerts:Refresh()
    end)
  end)
end

local function alertRow(i)
  local row = alerts.rows[i]
  if row then return row end
  local content = alerts.scroll.content
  row = CreateFrame("Button", nil, content)
  row:SetHeight(A_ROW)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.on = UI.Toggle(row, function(on)
    local a = P.db.alerts[row.index]
    if a then a.on = on; P:CompileAlerts(); row:Paint() end
  end)
  if row.on.ApplyAccent then row.on:ApplyAccent(ACCENT) end
  row.on:SetPoint("LEFT", 0, 0)
  row.text = UI.Text(row, "body", 14, C.text)
  row.text:SetPoint("TOPLEFT", 46, -7)
  row.text:SetPoint("RIGHT", -150, 0)
  row.text:SetWordWrap(false)
  row.where = UI.Text(row, "body", 12, C.muted)
  row.where:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -3)
  row.where:SetPoint("RIGHT", -150, 0)
  row.edit = UI.Input(row, { size = 13, onSubmit = function(text)
    local a = P.db.alerts[row.index]
    if a and text:match("%S") then a.text = text; P:CompileAlerts() end
    row.edit:Hide()
    alerts:Refresh()
  end })
  P.Own(row.edit)
  row.edit:SetPoint("TOPLEFT", 42, -4)
  row.edit:SetPoint("RIGHT", -150, 0)
  row.edit:SetHeight(24)
  row.edit:Hide()
  row.edit.edit:HookScript("OnEditFocusLost", function() row.edit:Hide(); alerts:Refresh() end)
  row.outs = {}
  local prev
  for j = #OUTS, 1, -1 do
    local b = outPill(row, OUTS[j], row)
    if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("RIGHT", -2, 0) end
    prev = b
    row.outs[OUTS[j]] = b
  end
  row.rule = P.Hairline(row)
  row.rule:SetPoint("BOTTOMLEFT")
  row.rule:SetPoint("BOTTOMRIGHT")
  row.rule:SetHeight(1)
  function row:Edit()
    local a = P.db.alerts[self.index]
    if not a then return end
    self.edit:Show()
    self.edit:SetText(a.text or "")
    self.edit:SetFocus()
  end
  function row:Paint()
    local a = P.db.alerts[self.index]
    local on = a and a.on ~= false
    self.text:SetAlpha(on and 1 or .5)
    self.where:SetAlpha(on and 1 or .5)
    for _, b in pairs(self.outs) do b:SetAlpha(on and 1 or .5) end
  end
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" then return alertMenu(self, self) end
    if self.where:IsMouseOver() then return alertMenu(self, self) end
    self:Edit()
  end)
  row:SetScript("OnEnter", function(self) UI.Tip(self, L.alertRowTip) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  alerts.rows[i] = row
  return row
end

local function buildAlerts()
  alerts = panel("ParleyAlerts", L.alertsTitle)
  alerts.all = UI.Toggle(alerts, function(on) P.db.paused = not on end)
  if alerts.all.ApplyAccent then alerts.all:ApplyAccent(ACCENT) end
  alerts.all:SetPoint("RIGHT", alerts.close, "LEFT", -10, 0)
  alerts.all:SetScript("OnEnter", function(self) UI.Tip(self, L.alertsAllOn) end)
  alerts.all:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- the box to add one: a suite text field
  local add = CreateFrame("Frame", nil, alerts)
  add:SetPoint("TOPLEFT", 14, -TOP)
  add:SetPoint("TOPRIGHT", -14, -TOP)
  add:SetHeight(28)
  P.FieldLook(add)
  local edit = CreateFrame("EditBox", nil, add)
  edit:SetPoint("LEFT", 14, 0)
  edit:SetPoint("RIGHT", -14, 0)
  edit:SetHeight(22)
  edit:SetFontObject(UI.Font("body", 14))
  edit:SetTextColor(C.text[1], C.text[2], C.text[3])
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(200)
  add.hint = UI.Text(add, "body", 13, C.faint)
  add.hint:SetPoint("LEFT", 14, 0)
  add.hint:SetText(L.newAlertHint)
  edit:SetScript("OnTextChanged", function(self) add.hint:SetShown(self:GetText() == "") end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    if text and text:match("%S") then P:AddAlert(text); self:SetText("") end
    self:ClearFocus()
  end)
  edit:HookScript("OnEditFocusGained", function() add:Light(true) end)
  edit:HookScript("OnEditFocusLost", function() add:Light(false) end)
  add:EnableMouse(true)
  add:SetScript("OnMouseDown", function() edit:SetFocus() end)
  alerts.addEdit = edit

  alerts.scroll = P.Own(UI.ScrollArea(alerts))
  alerts.scroll:SetPoint("TOPLEFT", 14, -(TOP + 38))
  alerts.scroll:SetPoint("RIGHT", -14, 0)
  alerts.rows = {}
  alerts.none = UI.Text(alerts.scroll.content, "body", 13, C.faint)
  alerts.none:SetPoint("TOPLEFT", 0, -6)
  alerts.none:SetText(L.alertsNone)
  alerts.foot = sub(alerts, L.alertsFoot)
  alerts:HookScript("OnShow", function() alerts:Refresh() end)

  function alerts:Refresh()
    self.all:SetOn(not P.db.paused, true)
    local list = P.db.alerts
    for i, a in ipairs(list) do
      local row = alertRow(i)
      row.index = i
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -(i - 1) * A_ROW)
      row:SetPoint("RIGHT", 0, 0)
      row.on:SetOn(a.on ~= false, true)
      row.text:SetText(alertText(a.text or ""))
      row.where:SetText(whereText(a))
      local outs = P.AlertOuts(a)
      for key, b in pairs(row.outs) do b:Paint(outs[key]) end
      row:Paint()
      row:Show()
    end
    for i = #list + 1, #self.rows do self.rows[i]:Hide() end
    self.none:SetShown(#list == 0)
    local h = math.min(6, math.max(1, #list)) * A_ROW
    self.scroll:SetHeight(h)
    self.scroll.content:SetHeight(math.max(1, #list) * A_ROW)
    self.foot:ClearAllPoints()
    self.foot:SetPoint("TOPLEFT", self.scroll, "BOTTOMLEFT", 0, -10)
    self.foot:SetPoint("RIGHT", -14, 0)
    self:SetHeight(TOP + 38 + h + 10 + (self.foot:GetStringHeight() or 30) + 14)
  end
end

function P:OpenAlerts()
  if not alerts then buildAlerts() end
  place(alerts)
  alerts:Show()
  alerts:Refresh()
end

function P:RefreshAlertsEditor()
  if alerts and alerts:IsShown() then alerts:Refresh() end
end

-------------------------------------------------------------------------------------------
-- Shift-clicking an item while one of Parley's boxes has focus puts the link there
-------------------------------------------------------------------------------------------

local function ourFocus()
  if not (alerts and alerts:IsShown()) then return nil end
  if alerts.addEdit:HasFocus() then return alerts.addEdit end
  for _, row in ipairs(alerts.rows or {}) do
    if row:IsShown() and row.edit:IsShown() and row.edit.edit:HasFocus() then return row.edit.edit end
  end
end

P:OnReady(function()
  local function insert(text)
    local edit = ourFocus()
    if edit and type(text) == "string" then edit:Insert(text) end
  end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insert) end
  local old = rawget(_G, "ChatEdit_InsertLink")
  if type(old) == "function" and old ~= (ChatFrameUtil and ChatFrameUtil.InsertLink) then
    hooksecurefunc("ChatEdit_InsertLink", insert)
  end
end)
