-- Windows, tabs, panes and the message frames inside them (the design: design/suite/parley.html; the look: look.lua).
-- A window is a dark glass panel holding tabs. A tab shows one pane, or up to three side by side; each pane is a mix of
-- chats (or For you, or a search) under a small header naming what's in it, drawn by a ScrollingMessageFrame, the game's
-- own widget, which can show hidden lines and edit lines already shown. Drag a tab onto another window's tab bar to move
-- it, onto a window's lines to show it beside them, or onto empty screen for a new window.

local P = Scrivener
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C
local Hidden = P.Hidden

P.windows = {}        -- live windows, by index into db.windows
P.tabFrames = {}      -- [pane data] = { frame, head, smf, win, tab, unread, newCount } (a tab is its own first pane)

local ACCENT = UI.Hex(P.ACCENT_HEX)
local BAR_H, PAD = 27, 6       -- a 30 px tab bar, its rule underneath
local RULE_Y = BAR_H + 2        -- where the rule under the tab bar sits, from the top
local HEAD_H = 22               -- a pane's header: its name and the chats in it
P.COMPOSE_H = 30                -- the chat box at the bottom of the docked window
local MAX_PANES = 3
local MARK = 20                 -- Scrivener's mark at the left of the tab bar

---A dashed outline around a frame (arrange mode): white dashes (media/dash-*.tga) repeated along each
---edge and tinted. :SetColor(c, alpha), :SetShown(on).
function P.Dashed(frame, c, alpha, layer)
  local edges = {}
  local function edge(horizontal)
    local t = frame:CreateTexture(nil, layer or "BORDER", nil, 2)
    t:SetTexture(P.MEDIA .. (horizontal and "dash-h" or "dash-v"), "REPEAT", "REPEAT")
    if horizontal then t:SetHorizTile(true); t:SetHeight(1) else t:SetVertTile(true); t:SetWidth(1) end
    edges[#edges + 1] = t
    return t
  end
  local top, bottom, left, right = edge(true), edge(true), edge(false), edge(false)
  top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
  bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
  right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
  local d = { edges = edges }
  function d:SetColor(col, a) for _, t in ipairs(self.edges) do t:SetVertexColor(col[1], col[2], col[3], a or 1) end end
  function d:SetShown(on) for _, t in ipairs(self.edges) do t:SetShown(on) end end
  d:SetColor(c or ACCENT, alpha or .8)
  return d
end

---A tab's panes: the tab itself, then the ones shown beside it.
local function panesOf(tab)
  local list = { tab }
  for _, pane in ipairs(tab.split or {}) do list[#list + 1] = pane end
  return list
end
P.PanesOf = panesOf

-------------------------------------------------------------------------------------------
-- Layouts
-------------------------------------------------------------------------------------------

local function kinds(...)
  local t = {}
  for i = 1, select("#", ...) do t[select(i, ...)] = true end
  return t
end

local TABS = {
  social = function() return { name = L.tab.social, kinds = kinds("SAY", "YELL", "EMOTE", "GUILD", "OFFICER", "PARTY",
    "RAID", "INSTANCE", "WHISPER", "SYSTEM", "MONSTER") } end,
  addons = function() return { name = L.tab.addons, kinds = kinds("ADDONS") } end,
  spam = function() return { name = L.tab.world, all = true, kinds = kinds("SYSTEM") } end,
  tradeplus = function() return { name = L.tab.trade, kinds = kinds("#trade", "#lookingforgroup", "#global") } end,
  general = function() return { name = L.tab.general, all = true, kinds = kinds("SAY", "YELL", "EMOTE", "GUILD",
    "OFFICER", "PARTY", "RAID", "INSTANCE", "WHISPER", "SYSTEM", "MONSTER") } end,
  whispers = function() return { name = L.tab.whispers, kinds = kinds("WHISPER"), special = "convos" } end,
  guild = function() return { name = L.tab.guild, kinds = kinds("GUILD", "OFFICER") } end,
  group = function() return { name = L.tab.group, kinds = kinds("PARTY", "RAID", "INSTANCE", "SAY", "YELL", "EMOTE",
    "MONSTER", "SYSTEM") } end,
  trade = function() return { name = L.tab.trade, kinds = kinds("#trade", "#lookingforgroup") } end,
  tradeboard = function() return { name = L.tab.trade, kinds = kinds("#trade", "#lookingforgroup", "#global"), board = true } end,
  world = function() return { name = L.tab.world, all = true, kinds = {} } end,
  loot = function() return { name = L.tab.loot, kinds = kinds("LOOT", "MONEY", "XP", "CRAFT") } end,
  system = function() return { name = L.tab.system, kinds = kinds("SYSTEM") } end,
  foryou = function() return { name = L.tab.foryou, kinds = {}, special = "foryou" } end,
  combat = function() return { name = L.tab.combat, kinds = {}, special = "combatlog" } end,   -- the game's own log
}
P.TABS = TABS

-- Sizes from the mock-up (its main window is 712 x 366 on a 1280 x 760 screen, close to the game's UI space), placed
-- where the game's own chat sits: 100 up, clear of a centred two-row action bar. A { ... } entry is a tab with panes
-- beside it: One window is the mock-up's, Social with Trade & LFG (and Global) beside it.
P.LAYOUTS = {
  one = { { x = 18, y = 100, w = 712, h = 366,
    tabs = { { "social", "tradeplus" }, "whispers", "group", "foryou", "loot", "addons", "combat" } } },
  -- pfUI's way: one panel in each bottom corner, what matters on the left and the noise on the right
  sides = { { x = 12, y = 12, w = 440, h = 230, tabs = { "social", "whispers", "group", "foryou" } },
            { right = true, x = 12, y = 12, w = 440, h = 230, tabs = { "spam", "loot", "addons", "combat" } } },
  social = { { x = 18, y = 100, w = 560, h = 366, tabs = { "social", "guild", "whispers", "foryou" } },
             { x = 588, y = 100, w = 420, h = 366, tabs = { "world", "loot", "addons", "combat" } } },
  group = { { x = 18, y = 100, w = 640, h = 380, tabs = { "group", "guild", "foryou", "loot" } },
            { x = 668, y = 100, w = 340, h = 220, tabs = { "whispers", "trade" } } },
  trader = { { x = 18, y = 100, w = 560, h = 366, tabs = { "social", "foryou", "loot" } },
             { x = 588, y = 100, w = 460, h = 366, tabs = { "tradeboard", "guild", "whispers" } } },
}
-- 0.1.0's sizes, half the mock-up's: a save still at one of these is moved to the new size (core.lua, migration 2)
P.OLD_LAYOUTS = {
  one = { { 470, 210 } }, social = { { 430, 210 }, { 380, 210 } }, group = { { 470, 230 }, { 330, 170 } },
  trader = { { 430, 210 }, { 400, 210 } },
}

P.PRESETS = { "guild", "group", "whispers", "trade", "loot", "system", "foryou", "addons", "combat" }

-------------------------------------------------------------------------------------------
-- Which tab shows what
-------------------------------------------------------------------------------------------

function P.TabWants(tab, r)
  if tab.special == "foryou" then return r.why ~= nil end
  if tab.special == "convos" then return tab.person ~= nil and P.ConvoKey(r) == tab.person end
  if tab.special then return false end
  if tab.mentionsOnly and r.why ~= L.why.mention then return false end
  if tab.kinds[r.kind] then return true end
  return r.chan and tab.all or false
end

-------------------------------------------------------------------------------------------
-- The font
-------------------------------------------------------------------------------------------

-- The fonts Scrivener offers: the suite's, the game's own, and every font SharedMedia knows when it's installed.
local GAME_FONTS = { friz = "Fonts\\FRIZQT__.TTF", arialn = "Fonts\\ARIALN.TTF", morpheus = "Fonts\\MORPHEUS.TTF",
  skurri = "Fonts\\SKURRI.TTF" }
P.FONT_ORDER = { "suite", "suiteBold", "marcellus", "game", "friz", "arialn", "morpheus", "skurri" }

local function sharedMedia()
  local stub = rawget(_G, "LibStub")
  if type(stub) ~= "table" or not stub.GetLibrary then return nil end
  local ok, lsm = pcall(stub.GetLibrary, stub, "LibSharedMedia-3.0", true)
  return ok and lsm or nil
end

---Every font to choose from: { value, label }, the suite's and the game's first, then SharedMedia's.
function P:FontChoices()
  local out = {}
  for _, key in ipairs(P.FONT_ORDER) do out[#out + 1] = { key, L.fonts[key] } end
  local lsm = sharedMedia()
  if lsm and lsm.List then
    local ok, names = pcall(lsm.List, lsm, "font")
    if ok and type(names) == "table" then
      for _, name in ipairs(names) do out[#out + 1] = { "lsm:" .. name, name } end
    end
  end
  return out
end

---The file for a font choice.
function P.FontPath(face)
  if face == "suiteBold" then return UI.FONT_FILES.bold end
  if face == "marcellus" then return UI.FONT_FILES.title end
  if face == "game" then return (ChatFontNormal and ChatFontNormal:GetFont()) or STANDARD_TEXT_FONT end
  if GAME_FONTS[face] then return GAME_FONTS[face] end
  if type(face) == "string" and face:sub(1, 4) == "lsm:" then
    local lsm = sharedMedia()
    if lsm and lsm.Fetch then
      local ok, path = pcall(lsm.Fetch, lsm, "font", face:sub(5), true)
      if ok and path then return path end
    end
  end
  return UI.FONT_FILES.body
end

---The text shadow at a strength from 0 to 1: up to half it darkens (half is a full 1 px shadow), past half it reaches
---further (2 px at full), and from .85 the text also gets a thin dark outline, since a font has only one shadow and
---it can't be darker than black. The point is text you can read with no background behind it.
function P.ShadowFor(strength)
  strength = strength or .45
  if strength <= 0 then return 0, 0, nil end
  local alpha = math.min(1, strength * 2)
  local offset = strength <= .5 and 1 or (1 + (strength - .5) * 2)
  return alpha, offset, strength >= .85 and "OUTLINE" or nil
end

local function setupFont(font, size)
  local alpha, offset, edge = P.ShadowFor(P.db.shadow)
  local flags = P.db.fontOutline or ""
  if flags == "" and edge then flags = edge end
  -- a font the client can't load falls back to the suite's, rather than leaving the lines blank
  -- SetFont returns nothing on this client when it works, so only an explicit false counts as failing
  if font:SetFont(P.FontPath(P.db.fontFace), size, flags) == false then font:SetFont(UI.FONT_FILES.body, size, flags) end
  if alpha > 0 then
    font:SetShadowOffset(offset, -offset)
    font:SetShadowColor(0, 0, 0, alpha)
  else
    font:SetShadowOffset(0, 0)
  end
  pcall(font.SetSpacing, font, 3)   -- the mock-up's 1.36 line height
  -- A frame given a font object takes the font's justification too (centred unless the font says otherwise), so the
  -- font itself is left-justified, and each frame is told again after every change.
  font:SetJustifyH("LEFT")
end

---The text size a pane's lines use: its window's own, or the setting's.
function P:SizeFor(pane)
  local tf = pane and self.tabFrames[pane]
  local win = tf and tf.win
  return (win and win.data and win.data.font) or self.db.font or 13
end

---A window's font: shared unless the window has a text size of its own.
function P:FontFor(win)
  if not (win and win.data and win.data.font) then return self.font end
  win.font = win.font or CreateFont("ScrivenerChatFont" .. win.index)
  setupFont(win.font, win.data.font)
  return win.font
end

---Give a message frame a font, and make it notice when that font changed in place: the game's message frame ignores
---being given the font it already has, so it's handed a placeholder first. Its alignment comes from the font itself
---(left): telling the frame directly makes it keep a private copy of the font that later changes never reach.
function P.SetPaneFont(smf, font)
  if smf:GetFontObject() == font then
    if not P.blankFont then
      P.blankFont = CreateFont("ScrivenerBlankFont")
      P.blankFont:SetFont(UI.FONT_FILES.body, 12, "")
    end
    smf:SetFontObject(P.blankFont)
  end
  smf:SetFontObject(font)
end

function P:ApplyFont()
  self.font = self.font or CreateFont("ScrivenerChatFont")
  setupFont(self.font, self.db.font)
  for _, tf in pairs(self.tabFrames) do P.SetPaneFont(tf.smf, self:FontFor(tf.win)) end
  -- a run-together line leaves the time's room empty: as many spaces as the time and its gap are wide
  self.measure = self.measure or UIParent:CreateFontString(nil, "BACKGROUND")
  self.measure:SetFontObject(self.font)
  self.measure:SetText(date(P.StampFormat and P.StampFormat() or "%H:%M", 0) .. "  ")   -- the time as it reads
  local timeW = self.measure:GetStringWidth() or 0
  self.measure:SetText("a a")
  local withSpace = self.measure:GetStringWidth() or 0
  self.measure:SetText("aa")
  local space = withSpace - (self.measure:GetStringWidth() or 0)
  self.measure:SetText("")
  local n = (space and space > 0) and math.floor(timeW / space + .5) or 9
  self.contPad = string.rep(" ", math.max(0, math.min(n, 24)))
end

-------------------------------------------------------------------------------------------
-- Message frames
-------------------------------------------------------------------------------------------

local RUN = 120   -- seconds: lines from the same person within this run together
local NEW_ID = "scrivener:new"   -- the "New since you looked" divider's id in a message frame

-- the extra data of a message frame's entry, whichever way the client hands it over (unpacked, or the entry itself)
local function entryId(a, _, _, _, id)
  if type(a) == "table" and not Hidden(a) and type(a.extraData) == "table" then return a.extraData[1] end
  return id
end
P.EntryId = entryId

---The pane isn't in front: another tab is, or its window is hidden.
local function away(tf)
  local win = tf.win
  return win and (win.data.tabs[win.data.active] ~= tf.tab or not win.frame:IsShown()) or false
end

---The first line you haven't seen in a pane: the divider moves to just above it (the mock-up's "New since you looked").
local function markNew(tab, tf)
  if tab.special == "convos" then return end   -- conversations mark it themselves, per person
  local smf = tf.smf
  pcall(smf.RemoveMessagesByPredicate, smf, function(...) return entryId(...) == NEW_ID end)
  pcall(smf.AddMessage, smf, P:NewSinceText(), .6, .6, .9, NEW_ID)
  tf.last = nil
end

local function addLine(tab, tf, r, live)
  if live and tf.unread == 0 and r.kind ~= "ADDONS" and r.type ~= "SCRIVENER" and away(tf) then markNew(tab, tf) end
  local last, cont = tf.last, nil
  if P.db.group and last and P.RUNS[r.type] and not r.held and not r.why and type(r.who) == "string" and last.who == r.who
      and last.kind == r.kind and last.type == r.type and (r.t or 0) - (last.t or 0) <= RUN
      and (not r.restored) == (not last.restored) then
    cont = true
    tf.cont[r.id] = true
  end
  tf.last = (not r.held and type(r.who) == "string") and r or nil
  local text, cr, cg, cb = P:Format(r, tab, cont)
  if not text then text, cr, cg, cb = P:Placeholder(r, tab) end
  local ok = pcall(tf.smf.AddMessage, tf.smf, text, cr, cg, cb, r.id)
  if r.held and live and not r.counted then
    r.counted = true
    if ok then P.diag.heldShown = P.diag.heldShown + 1 else P.diag.heldRefused = P.diag.heldRefused + 1 end
  end
  if not ok and r.held then
    text, cr, cg, cb = P:Placeholder(r, tab)
    pcall(tf.smf.AddMessage, tf.smf, text, cr, cg, cb, r.id)
  end
  if not live then return end
  local win = tf.win
  if win and away(tf) then
    if r.kind ~= "ADDONS" and r.type ~= "SCRIVENER" then tf.unread = tf.unread + 1; P:UpdateTabs(win) end
  elseif win and tf.smf:GetScrollOffset() > 0 then
    tf.newCount = tf.newCount + 1
    win.pill.text:SetText(L.newLines:format(tf.newCount))
    win.pill:SetWidth(win.pill.text:GetStringWidth() + 20)
    win.pill:Show()
  end
end

---Show a record in every tab that wants it (only = "foryou": in For you tabs only).
function P:Show(r, only)
  for tab, tf in pairs(self.tabFrames) do
    if only == "foryou" then
      if tab.special == "foryou" then addLine(tab, tf, r, true) end
    elseif tab.special == "convos" then
      -- the list of people moves first; a conversation drawn fresh already holds this line
      local drawn = r.kind == "WHISPER" and self.ConvoSeen and self:ConvoSeen(tab, tf, r)
      if not drawn and P.TabWants(tab, r) then addLine(tab, tf, r, true) end
    elseif P.TabWants(tab, r) then
      addLine(tab, tf, r, true)
      if tab.board and self.BoardDirty then self:BoardDirty(tab, tf) end
    end
  end
end

---Draw a record again wherever it's shown (a held line read back, a fold count going up).
function P:Redraw(r)
  for tab, tf in pairs(self.tabFrames) do
    if P.TabWants(tab, r) then
      if tab.board and self.BoardDirty then self:BoardDirty(tab, tf) end
      local text, cr, cg, cb = self:Format(r, tab, tf.cont[r.id])
      if text then
        pcall(tf.smf.TransformMessages, tf.smf,
          function(_, _, _, _, id) return id == r.id end,
          function() return text, cr, cg, cb, r.id end)
      end
    end
  end
end

-- since: show the tab from that moment on (a search result older than what the tab holds), not just its newest lines
local function backfill(tab, tf, since)
  if tab.special == "convos" and P.ConvoBackfill then return P:ConvoBackfill(tab, tf) end
  tf.smf:Clear()
  tf.last, tf.cont = nil, {}
  local old = P.HistoryFor and P:HistoryFor(tab, since and 400 or 150, since) or {}
  for _, r in ipairs(old) do addLine(tab, tf, r, false) end
  if #old > 0 then pcall(tf.smf.AddMessage, tf.smf, P:RuleText(L.restored), .6, .6, .6, 0); tf.last = nil end
  local list = P.records
  local shown, start = 0, #list
  while start > 1 and shown < 400 do
    if P.TabWants(tab, list[start]) then shown = shown + 1 end
    start = start - 1
  end
  if since then
    start = 1
    while list[start] and (list[start].t or 0) < since do start = start + 1 end
  end
  for i = math.max(start, 1), #list do
    if P.TabWants(tab, list[i]) then addLine(tab, tf, list[i], false) end
  end
  tf.smf:ScrollToBottom()
end

---Show a pane from a moment on (search's Jump, for a line older than the pane holds).
function P:BackfillFrom(pane, tf, since)
  backfill(pane, tf, since)
end

local redrawDue = false
---Redraw everything a moment from now, once, however many changes ask for it (typing a short name).
function P:RedrawSoon()
  if redrawDue then return end
  redrawDue = true
  C_Timer.After(.35, function() redrawDue = false; P:RedrawAll() end)
end

function P:RedrawAll()
  self:ApplyFont()
  for tab, tf in pairs(self.tabFrames) do
    tf.smf:SetFading(self.db.fade)
    tf.smf:SetTimeVisible(self.db.fadeAfter)
    backfill(tab, tf)
  end
  for _, win in ipairs(self.windows) do self:UpdateTabs(win) end
  for pane, tf in pairs(self.tabFrames) do self:UpdatePaneHead(pane, tf) end
end

local function scrolled(tf)
  if tf.smf:GetScrollOffset() == 0 and tf.win then
    tf.newCount = 0
    tf.win.pill:Hide()
  end
end

---What a pane's header says after its name: the chats in it, For you's reason, a search's count.
function P:PaneSummary(pane)
  if pane.special == "foryou" then return L.foryouSub end
  if pane.special == "combatlog" then return L.combatSub end
  local parts = {}
  for _, key in ipairs(self:PickerKinds()) do
    if pane.kinds[key] then parts[#parts + 1] = P.KindLabel(key) end
  end
  if pane.all then parts[#parts + 1] = L.everyChannel end
  return table.concat(parts, " \194\183 ")
end

function P:UpdatePaneHead(pane, tf)
  if not tf.head then return end
  if pane.special == "convos" and self.ConvoHead then
    local name, line = self:ConvoHead(pane)   -- the person you're talking to, and who they are
    tf.head.name:SetText(name)
    tf.head.list:SetText(line)
    tf.head.close:SetShown(tf.tab ~= nil and tf.tab ~= pane)
    return
  end
  tf.head.name:SetText(pane.name or "")
  tf.head.list:SetText(self:PaneSummary(pane))
  tf.head.close:SetShown(tf.tab ~= nil and tf.tab ~= pane)
  if self.BoardSwitch then self:BoardSwitch(pane, tf) end   -- Stream or Board, for panes with channels
end

---After the message frame draws its lines: a line reaching above the pane's top (the game cuts it through) is hidden,
---and the first whole line under it starts at a fifth of its brightness, so text doesn't stop at a hard edge under the
---pane's header. The frame's own fading of old lines is untouched.
---A line holding words the game hid in a dungeon fight has a hidden position too (its top is a secret number, which
---nothing may do sums with); that line is left as the game draws it.
function P.SoftTop(smf)
  local lines = smf.visibleLines
  local top = smf:GetTop()
  if type(lines) ~= "table" or not top or Hidden(top) then return end
  local band = ((smf.GetFont and select(2, smf:GetFont())) or P.db.font or 13) * 1.4
  for _, line in ipairs(lines) do
    if line:IsShown() then
      local lineTop = line:GetTop()
      if lineTop and not Hidden(lineTop) then
        local gap = top - lineTop
        if gap < -1 then
          line:SetAlpha(0)   -- reaching above the pane, where the game would cut it through: hidden instead
        elseif gap < band then
          local alpha = line:GetAlpha()
          if Hidden(alpha) then alpha = 1 end
          line:SetAlpha((alpha or 1) * (.2 + .8 * math.max(0, gap) / band))   -- the first whole line, faint
        end
      end
    end
  end
end

P.CLIP_ROOM_LEFT, P.CLIP_ROOM_RIGHT = 2, 6   -- px a line may draw past its pane's text area (see below)

local function newMessageFrame(tab)
  local holder = CreateFrame("Frame", nil, UIParent)
  local head = CreateFrame("Button", nil, holder)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(HEAD_H)
  head:RegisterForClicks("RightButtonUp")
  head.name = UI.Text(head, "bold", 12, P.TAB_OFF)
  head.name:SetPoint("LEFT", 8, 0)
  pcall(head.name.SetIgnoreParentAlpha, head.name, true)   -- the pane's name stays when the headers fade
  head.list = UI.Text(head, "body", 12, C.faint)
  head.list:SetPoint("LEFT", head.name, "RIGHT", 7, 0)
  head.list:SetPoint("RIGHT", head, "RIGHT", -22, 0)
  head.rule = P.Hairline(head)
  head.rule:SetPoint("BOTTOMLEFT", 0, 0)
  head.rule:SetPoint("BOTTOMRIGHT", 0, 0)
  head.rule:SetHeight(1)
  head.close = CreateFrame("Button", nil, head)
  head.close:SetSize(16, 16)
  head.close:SetPoint("RIGHT", -3, 0)
  head.close.icon = UI.Icon(head.close, "close", 8, C.muted)
  head.close.icon:SetPoint("CENTER")
  local m = CreateFrame("ScrollingMessageFrame", nil, holder)
  m:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
  m:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 2)
  local tf = { frame = holder, head = head, smf = m, unread = 0, newCount = 0, cont = {} }
  head:SetScript("OnClick", function(self) if tf.win then P:PaneMenu(tf.win, tab, self) end end)
  head.close:SetScript("OnClick", function() if tf.win then P:ClosePane(tf.win, tab) end end)
  m:SetFontObject(P.font)   -- left-justified by the font itself (see P.SetPaneFont)
  m:SetMaxLines(600)
  m:SetFading(P.db.fade)
  m:SetTimeVisible(P.db.fadeAfter)
  m:SetFadeDuration(4)
  m:SetHyperlinksEnabled(true)
  m:EnableMouse(true)
  m:EnableMouseWheel(true)
  pcall(m.SetTextCopyable, m, true)
  pcall(m.SetIndentedWordWrap, m, true)
  -- The game lays each line out at the frame's width and clips the text at that same edge, so a line that only just
  -- fits could draw its last letter a few pixels past where it measured it and lose part of it (Maro, 21 Nov). The clip
  -- edge moves out into the pane's margin (8 px on the right, 7 on the left); the lines' width, and where they wrap,
  -- stay as they were.
  local clip = m.FontStringContainer
  if clip and clip.ClearAllPoints then
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", m, "TOPLEFT", -P.CLIP_ROOM_LEFT, 0)
    clip:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", P.CLIP_ROOM_RIGHT, 0)
  end
  m:SetScript("OnHyperlinkClick", function(self, link, text, button) P:ClickLink(link, text, button, self) end)
  m:SetScript("OnHyperlinkEnter", function(self, link, text, ...)
    P:LinkTip(self, link)
    local registry = rawget(_G, "EventRegistry")
    if registry and registry.TriggerEvent and not Hidden(link) then
      pcall(registry.TriggerEvent, registry, "ChatFrame.OnHyperlinkEnter", DEFAULT_CHAT_FRAME, link, text, ...)
    end
  end)
  m:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
    local registry = rawget(_G, "EventRegistry")
    if registry and registry.TriggerEvent then pcall(registry.TriggerEvent, registry, "ChatFrame.OnHyperlinkLeave", DEFAULT_CHAT_FRAME) end
  end)
  m:SetScript("OnMouseWheel", function(self, delta)
    if IsShiftKeyDown() then
      if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    elseif IsControlKeyDown() then
      if delta > 0 then self:PageUp() else self:PageDown() end
    else
      for _ = 1, 3 do if delta > 0 then self:ScrollUp() else self:ScrollDown() end end
    end
    scrolled(tf)
  end)
  pcall(m.SetOnLineRightClickedCallback, m, function(self, index) P:LineMenu(self, index) end)
  pcall(m.AddOnDisplayRefreshedCallback, m, function(self) P.SoftTop(self) end)
  pcall(m.SetOnScrollChangedCallback, m, function() scrolled(tf) end)
  P.tabFrames[tab] = tf
  if tab.special == "combatlog" and P.HostCombatLog then P:HostCombatLog(tab, tf) end
  if tab.special == "convos" and P.BuildRail then
    if not (tab.person and P:ConvoKnows(tab.person)) then   -- the pick may be another character's conversation
      local list = P:ConvoList()
      tab.person = list[1] and list[1].key
    end
    P:BuildRail(tab, tf)
  end
  backfill(tab, tf)
  return tf
end
P.NewPaneFrame = newMessageFrame

---The game's chat keys (Chat Page Up, Chat Page Down, Chat Bottom in its key bindings) scroll Scrivener's pane: the one under
---the mouse, or else the first pane of the window with the chat box. how: "PageUp", "PageDown" or "ScrollToBottom".
function P:ScrollShown(how)
  local pick
  for _, tf in pairs(self.tabFrames) do
    if tf.smf:IsVisible() and tf.frame:IsMouseOver() then pick = tf; break end
  end
  if not pick then
    local win = self.dockWin or self.windows[1]
    local tab = win and win.data.tabs[win.data.active]
    local pane = tab and panesOf(tab)[1]
    pick = pane and self.tabFrames[pane]
  end
  if pick and pick.smf:IsVisible() and pick.smf[how] then pick.smf[how](pick.smf) end
end

-------------------------------------------------------------------------------------------
-- Links
-------------------------------------------------------------------------------------------

local TIP_LINKS = { item = true, spell = true, enchant = true, quest = true, achievement = true, currency = true,
  talent = true, instancelock = true, mount = true }

function P:LinkTip(owner, link)
  if Hidden(link) or type(link) ~= "string" then return end
  local tip = link:match("^addon:Scrivener:tip:(.+)$")
  if tip then
    local kind = tip:match("^kind:(.+)$")
    local text, sub, from
    if kind then
      local k, name = kind:match("^(.-)@@(.+)$")
      if k then kind, from = k, name end
      text = P.KindLabel(kind)
      if not P.TALK[kind] and not P.IsChannel(kind) then sub = nil elseif P.Short(kind) ~= text then sub = P.Short(kind) end
    else
      text = L.tips[tip]
    end
    if not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 12, 0)
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    if sub then GameTooltip:AddLine(sub, .66, .63, .54) end
    if from then GameTooltip:AddLine(L.fromCharacter:format(from), .66, .63, .54) end
    GameTooltip:Show()
    return
  end
  local kind = link:match("^(%a+):")
  if not TIP_LINKS[kind] then return end
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT", 12, 0)
  if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() end
end

-- A name's right-click menu is the game's own (whisper, invite, ignore, report, copy name...). The game opens it owned by
-- the chat frame the click came from and closes it the moment that frame isn't visible; the game's frame is hidden in
-- Scrivener's vault, so the menu was gone before it drew. Here it's owned by the pane that was clicked, and keeps the game's
-- chat frame for what it does (Whisper uses the chat box Scrivener moved in). The same contextData the game builds in
-- FriendsFrame_ShowDropdown / FriendsFrame_ShowBNDropdown, with only the owner changed.
--
-- One entry needs help. The game's "Copy Character Name" copies with CopyToClipboard, which only the game itself may
-- call, so from a menu an add-on opened it fails (ADDON_ACTION_FORBIDDEN). The game hides its Target entry there for
-- the same reason (it checks issecure()), but not this one. In the menus Scrivener opens, that entry opens Scrivener's copy
-- box instead, with the name selected. The game's own menus are left as they are.
local function findEntry(root, text, depth)
  if depth > 3 or not (root and root.EnumerateElementDescriptions) then return end
  for _, entry in root:EnumerateElementDescriptions() do
    local label = MenuUtil.GetElementText and MenuUtil.GetElementText(entry) or entry.text
    if label == text then return entry end
    local inner = findEntry(entry, text, depth + 1)
    if inner then return inner end
  end
end

local copyHooked
local function hookCopyName()
  if copyHooked or not (Menu and Menu.ModifyMenu and MenuUtil and type(COPY_CHARACTER_NAME) == "string") then return end
  copyHooked = true
  Menu.ModifyMenu("MENU_UNIT_FRIEND", function(_, root, data)
    if data == nil or data ~= P.nameMenuData then return end   -- not a menu Scrivener opened
    pcall(function()
      local entry = findEntry(root, COPY_CHARACTER_NAME, 1)
      if entry and entry.SetResponder then
        entry:SetResponder(function() P:CopyName(data.name) end)
      end
    end)
  end)
end

local function openNameMenu(which, data, owner)
  if not (UnitPopup_OpenMenu and owner and owner.IsVisible and owner:IsVisible()) then return false end
  hookCopyName()
  data.chatFrame, data.ownerFrame = DEFAULT_CHAT_FRAME, owner
  P.menuFor = { name = data.name, bnID = data.bnetIDAccount, at = GetTime() }
  P.nameMenuData = data
  return (pcall(UnitPopup_OpenMenu, which, data))
end

---Scrivener's "Copy Character Name": the copy box with the name selected. It's the name a whisper reaches ("First Last"),
---even when the menu only knew a first name (a whisper to a first name alone fails).
function P:CopyName(name)
  if type(name) ~= "string" or Hidden(name) or name == "" then return false end
  local Names = self.Core.Names
  local full = Names:Address(name) or Names.Full(name) or name
  self:AskText(L.copyTitle, full, nil, L.copyName)
  return true
end

local function playerMenu(link, owner)
  if not (UnitPopup_OpenMenu and owner and owner.IsVisible and owner:IsVisible()) then return false end
  local kind, rest = link:match("^(%a+):(.*)$")
  local which, data
  if kind == "player" then
    local name, lineID, chatType = strsplit(":", rest)
    if not name or name == "" then return false end
    which = "FRIEND"
    data = { name = name, lineID = lineID, chatType = chatType, chatTarget = name }
  elseif kind == "BNplayer" then
    local name, id, _, chatType = strsplit(":", rest)
    id = tonumber(id)
    if not name or name == "" or not id then return false end
    if BNIsSelf and BNIsSelf(id) then return true end   -- the game has no menu for you
    which = "BN_FRIEND"
    data = { name = name, chatType = chatType, chatTarget = name, bnetIDAccount = id }
  else
    return false
  end
  return openNameMenu(which, data, owner)
end

---The same game menu for a person shown somewhere other than a chat line (the whisper list). A Battle.net friend is
---named by their account token, as in a chat link, with their account id.
function P:NameMenu(name, owner, bnID)
  if type(name) ~= "string" or Hidden(name) or name == "" then return false end
  if bnID then
    return openNameMenu("BN_FRIEND", { name = name, chatTarget = name, bnetIDAccount = bnID }, owner)
  end
  return openNameMenu("FRIEND", { name = name, chatTarget = name }, owner)
end

---"Move to whisper window" on that menu makes one of the game's whisper windows, which Scrivener keeps out of sight; Scrivener'
---own is the person's conversation, so it opens that.
function P:MovedToWhisperWindow(chatType, target)
  local m = self.menuFor
  if not (m and m.name == target and GetTime() - m.at < 300) then return end   -- the game's whisper mode makes them too
  self.menuFor = nil
  local r = { kind = "WHISPER", type = chatType, who = target }
  if chatType == "BN_WHISPER" and m.bnID and self.BNLine then self:BNLine(r, target, m.bnID) end
  self:Reveal(r)
end

function P:ClickLink(link, text, button, owner)
  if Hidden(link) or type(link) ~= "string" then return end
  if button == "RightButton" and not IsModifiedClick("CHATLINK") and playerMenu(link, owner) then
    self.nameMenuAt = GetTime()   -- the line's own menu stands aside (both come from one right-click)
    local registry = rawget(_G, "EventRegistry")
    if registry and registry.TriggerEvent then
      pcall(registry.TriggerEvent, registry, "ChatFrame.OnHyperlinkClick", DEFAULT_CHAT_FRAME, link, text, button)
    end
    return
  end
  local rest = link:match("^addon:Scrivener:(.*)$")
  if rest then
    local what, arg = rest:match("^(%a+):?(.*)$")
    if what == "url" then
      local url = P.urls[tonumber(arg)]
      if url then P:AskText(L.copyTitle, url, nil, L.copyUrl) end
    elseif what == "resend" and P.Resend then
      P:Resend(tonumber(arg))
    elseif what == "unfold" then
      local r = P.byId[tonumber(arg)]
      if r and r.tidy then r.tidy.open = true; P:Redraw(r) end
    end
    return
  end
  local registry = rawget(_G, "EventRegistry")
  if registry and registry.TriggerEvent then
    pcall(registry.TriggerEvent, registry, "ChatFrame.OnHyperlinkClick", DEFAULT_CHAT_FRAME, link, text, button)
  end
  if SetItemRef then SetItemRef(link, text, button, DEFAULT_CHAT_FRAME) end
end

-------------------------------------------------------------------------------------------
-- A small box for one line of text (rename a tab, copy an address or a line, search)
-------------------------------------------------------------------------------------------

local ask
function P:AskText(title, text, onAccept, note)
  if not ask then
    ask = CreateFrame("Frame", "ScrivenerAskFrame", UIParent)
    ask:SetSize(380, 96)
    ask:SetPoint("CENTER", 0, 140)
    ask:SetFrameStrata("DIALOG")
    ask:EnableMouse(true)
    ask:SetClampedToScreen(true)
    P.Panel(ask, 60)
    P.PanelTitle(ask, "", 16, 14, -11)
    ask.note = UI.Text(ask, "body", 12, C.muted)
    ask.note:SetPoint("TOPLEFT", ask.title, "BOTTOMLEFT", 0, -3)
    ask.close = UI.CloseButton(ask, function() ask:Hide() end)
    ask.close:SetPoint("TOPRIGHT", -6, -6)
    ask.input = UI.Input(ask, { size = 14, onSubmit = function()
      local fn = ask.onAccept
      local value = ask.input:GetText()
      ask:Hide()
      if fn then fn(value) end
    end })
    P.Own(ask.input)
    ask.input:SetPoint("BOTTOMLEFT", 12, 12)
    ask.input:SetPoint("BOTTOMRIGHT", -12, 12)
    ask.input:SetHeight(26)
    ask.input.edit:SetScript("OnEscapePressed", function() ask:Hide() end)
    -- A box that's only for copying closes once Ctrl+C has copied. The copy happens first and the box goes a frame
    -- later. A box with an OK (renaming a tab) stays open.
    ask.input.edit:HookScript("OnKeyDown", function(_, key)
      if ask.onAccept or key ~= "C" then return end
      if not (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())) then return end
      C_Timer.After(0, function() if not ask.onAccept then ask:Hide() end end)
    end)
    tinsert(UISpecialFrames, "ScrivenerAskFrame")
    ask:Hide()   -- so its first opening fades in too
  end
  ask.title:SetText(title)
  ask.note:SetText(note or "")
  ask.onAccept = onAccept
  ask:Show()
  ask.input:SetText(text or "")
  ask.input:SetFocus()
  ask.input.edit:HighlightText()
end

-------------------------------------------------------------------------------------------
-- Menus
-------------------------------------------------------------------------------------------

local function menu(owner, build)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  MenuUtil.CreateContextMenu(owner, function(_, root) build(root) end)
end
local KEEP_OPEN = MenuResponse and MenuResponse.Refresh

local function kindsMenu(root, tab, after)
  root:CreateCheckbox(L.allChannels, function() return tab.all end, function()
    tab.all = not tab.all or nil
    after()
    return KEEP_OPEN
  end)
  for _, key in ipairs(P:PickerKinds()) do
    -- each chat in the colour it has in chat, so it's easy to find
    local r, g, b = P.KindColor(key)
    local label = "|c" .. P.Hex(r, g, b) .. P.KindLabel(key) .. "|r"
    if P.IsChannel(key) then label = label .. "  |cff6e6552" .. P.Short(key) .. "|r" end
    root:CreateCheckbox(label, function() return tab.kinds[key] or false end, function()
      tab.kinds[key] = not tab.kinds[key] or nil
      after()
      return KEEP_OPEN
    end)
  end
end

local function presetTab(key)
  local tab = TABS[key]()
  return tab
end

function P:AddTab(win, tab, newWindow)
  if newWindow then
    local x, y = win.frame:GetLeft() + 40, win.frame:GetBottom() + win.frame:GetHeight() + 20
    self:NewWindow({ tab }, x, y)
    return
  end
  local tabs = win.data.tabs
  tabs[#tabs + 1] = tab
  win.data.active = #tabs
  self:SyncWindows()
end

function P:PlusMenu(win, owner)
  menu(owner, function(root)
    root:CreateTitle(L.newTab)
    for _, key in ipairs(P.PRESETS) do
      root:CreateButton(L.tab[key], function() P:AddTab(win, presetTab(key), IsShiftKeyDown()) end)
    end
    root:CreateDivider()
    root:CreateButton(L.yourOwnMix, function()
      local tab = { name = L.tab.mix, kinds = {} }
      P:AddTab(win, tab, IsShiftKeyDown())
      C_Timer.After(0, function()
        local w, i = P:FindTab(tab)
        if w then P:TabMenu(w, i, w.buttons[i]) end
      end)
    end)
    root:CreateDivider()
    root:CreateTitle("|cff6e6552" .. L.shiftNewWindow .. "|r")
  end)
end

function P:FindTab(tab)
  for _, win in ipairs(self.windows) do
    for i, t in ipairs(win.data.tabs) do if t == tab then return win, i end end
  end
end

function P:CloseTab(win, index)
  local tabs = win.data.tabs
  local tab = tabs[index]
  if #tabs == 1 then
    if #self.db.windows == 1 then return end
    return self:CloseWindow(win)
  end
  table.remove(tabs, index)
  if win.data.active >= index then win.data.active = math.max(1, win.data.active - 1) end
  for _, pane in ipairs(panesOf(tab)) do
    local tf = self.tabFrames[pane]
    if tf then tf.frame:Hide(); self.tabFrames[pane] = nil end
  end
  self:SyncWindows()
end

-------------------------------------------------------------------------------------------
-- Panes: up to three side by side in one tab
-------------------------------------------------------------------------------------------

function P:AddPane(win, pane)
  local tab = win.data.tabs[win.data.active]
  if not tab then return end
  if #panesOf(tab) >= MAX_PANES then return self:Print(L.splitFull) end
  tab.split = tab.split or {}
  tab.split[#tab.split + 1] = pane
  tab.sizes = nil
  self:SyncWindows()
end

function P:ClosePane(win, pane)
  for _, tab in ipairs(win.data.tabs) do
    for i, other in ipairs(tab.split or {}) do
      if other == pane then
        table.remove(tab.split, i)
        if #tab.split == 0 then tab.split = nil end
        tab.sizes = nil
        return self:SyncWindows()
      end
    end
  end
end

function P:PaneToTab(win, pane)
  for _, tab in ipairs(win.data.tabs) do
    for i, other in ipairs(tab.split or {}) do
      if other == pane then
        table.remove(tab.split, i)
        if #tab.split == 0 then tab.split = nil end
        win.data.tabs[#win.data.tabs + 1] = pane
        win.data.active = #win.data.tabs
        return self:SyncWindows()
      end
    end
  end
end

function P:SplitMenu(win, owner)
  local tab = win.data.tabs[win.data.active]
  menu(owner, function(root)
    root:CreateTitle(L.splitTitle)
    for _, key in ipairs(P.PRESETS) do
      root:CreateButton(L.tab[key], function() P:AddPane(win, presetTab(key)) end)
    end
    root:CreateButton(L.yourOwnMix, function()
      local pane = { name = L.tab.mix, kinds = {} }
      P:AddPane(win, pane)
      C_Timer.After(0, function()
        local tf = P.tabFrames[pane]
        if tf then P:PaneMenu(win, pane, tf.head) end
      end)
    end)
    if tab and tab.split then
      root:CreateDivider()
      local n = #panesOf(tab)
      root:CreateTitle(L.arrange)
      for _, mode in ipairs(P.ARRANGE) do
        if n == 3 or (mode ~= "left2" and mode ~= "right2") then
          root:CreateRadio(L.arrangeAs[mode], function() return P.Arrangement(tab) == mode end,
            function() P:Arrange(win, tab, mode) end)
        end
      end
      root:CreateDivider()
      root:CreateButton(L.unsplit, function() tab.split = nil; tab.sizes = nil; tab.arrange = nil; P:SyncWindows() end)
    end
  end)
end

function P:PaneMenu(win, pane, owner)
  local tab = win.data.tabs[win.data.active]
  local side = tab and tab ~= pane
  menu(owner, function(root)
    root:CreateTitle(pane.name or "")
    if not pane.special then
      local sub = root:CreateButton(L.chatsInPane)
      kindsMenu(sub, pane, function()
        local tf = P.tabFrames[pane]
        if tf then backfill(pane, tf); P:UpdatePaneHead(pane, tf) end
      end)
    end
    root:CreateButton(L.renameTab, function()
      P:AskText(L.renameTab, pane.name, function(text)
        text = (text or ""):match("^%s*(.-)%s*$")
        if text ~= "" then
          pane.name = text:sub(1, 24)
          P:UpdateTabs(win)
          if P.tabFrames[pane] then P:UpdatePaneHead(pane, P.tabFrames[pane]) end
        end
      end, L.tabName)
    end)
    if side then
      root:CreateButton(L.paneToTab, function() P:PaneToTab(win, pane) end)
      root:CreateButton(L.closePane, function() P:ClosePane(win, pane) end)
    end
  end)
end

function P:TabMenu(win, index, owner)
  local tab = win.data.tabs[index]
  if not tab then return end
  menu(owner or win.frame, function(root)
    root:CreateTitle(tab.name)
    if not tab.special then
      local sub = root:CreateButton(L.chatsInTab)
      kindsMenu(sub, tab, function()
        local tf = P.tabFrames[tab]
        if tf then backfill(tab, tf); P:UpdatePaneHead(tab, tf) end
      end)
    end
    root:CreateButton(L.renameTab, function()
      P:AskText(L.renameTab, tab.name, function(text)
        text = (text or ""):match("^%s*(.-)%s*$")
        if text ~= "" then
          tab.name = text:sub(1, 24)
          P:UpdateTabs(win)
          if P.tabFrames[tab] then P:UpdatePaneHead(tab, P.tabFrames[tab]) end
        end
      end, L.tabName)
    end)
    if #win.data.tabs > 1 then
      root:CreateButton(L.moveToNewWindow, function() P:MoveTabToNewWindow(win, index) end)
    end
    if #win.data.tabs > 1 or #P.db.windows > 1 then
      root:CreateButton(L.closeTab, function() P:CloseTab(win, index) end)
    end
  end)
end

function P:WindowMenu(win, owner)
  menu(owner, function(root)
    if (win.hiddenTabs or 0) > 0 then   -- the tabs there was no room for
      root:CreateTitle(L.moreTabs)
      for i, tab in ipairs(win.data.tabs) do
        if not win.buttons[i]:IsShown() then root:CreateButton(tab.name, function() P:SelectTab(win, i, true) end) end
      end
      root:CreateDivider()
    end
    root:CreateButton(L.newWindow, function() P:NewWindow() end)
    local lay = root:CreateButton(L.layouts)
    for _, key in ipairs({ "one", "sides", "social", "group", "trader" }) do
      lay:CreateButton(L.layout[key][1], function() P:ApplyLayout(key) end)
    end
    root:CreateButton(L.channelNames, function() P:OpenNames() end)
    if rawget(_G, "ToggleChannelFrame") then
      -- the game's own channel list: join and leave channels, who's in them, voice
      root:CreateButton(L.channelList, function() ToggleChannelFrame() end)
    end
    root:CreateButton(L.alerts, function() P:OpenAlerts() end)
    local op = root:CreateButton(L.opacity)
    for _, v in ipairs({ 1, .9, .8, .7, .6, .5, .4, .3, .2, 0 }) do
      op:CreateRadio(math.floor(v * 100 + .5) .. "%", function() return math.abs((P.db.alpha or 0) - v) < .01 end,
        function() P:SetOpacity(v) end)
    end
    local face = root:CreateButton(L.font)
    for _, choice in ipairs(P:FontChoices()) do
      face:CreateRadio(choice[2], function() return (P.db.fontFace or "suite") == choice[1] end,
        function() P.db.fontFace = choice[1]; P:RedrawAll() end)
    end
    local size = root:CreateButton(L.textSize)
    size:CreateRadio(L.textSizeSame:format(P.db.font or 13), function() return not win.data.font end,
      function() win.data.font = nil; P:RedrawAll() end)
    for v = 11, 18 do
      size:CreateRadio(tostring(v), function() return win.data.font == v end, function() win.data.font = v; P:RedrawAll() end)
    end
    root:CreateCheckbox(L.fadeHeaders, function() return P.db.fadeChrome end, function()
      P.db.fadeChrome = not P.db.fadeChrome
      return KEEP_OPEN
    end)
    root:CreateCheckbox(L.fadeBackground, function() return P.db.fadeBackground end, function()
      P.db.fadeBackground = not P.db.fadeBackground
      for _, w in ipairs(P.windows) do P:SetChromeAlpha(w, w.headers or 1) end
      return KEEP_OPEN
    end)
    root:CreateButton(L.arrangeWindows, function() P:SetArranging(true) end)
    root:CreateButton(P.db.locked and L.unlock or L.lock, function() P:SetLocked(not P.db.locked) end)
    root:CreateButton(L.settings, function() P:OpenSettings() end)
    if #P.db.windows > 1 then
      root:CreateDivider()
      root:CreateButton(L.closeWindow, function() P:CloseWindow(win) end)
    end
  end)
end

function P:LineMenu(smf, index)
  if self.nameMenuAt == GetTime() then return end   -- the right-click was on a name: the game's menu for them is open
  local line = smf.visibleLines and smf.visibleLines[index]
  local info = line and line.messageInfo
  local id = info and info.extraData and info.extraData[1]
  local r = id and self.byId[id]
  if not r then return end
  local win, here
  for tab, tf in pairs(self.tabFrames) do if tf.smf == smf then win, here = tf.win, tab end end
  menu(smf, function(root)
    if win and P.Mixed(here) and r.kind ~= "ADDONS" then
      root:CreateButton(L.lineOnly:format(P.KindLabel(r.kind)), function()
        P:AddTab(win, { name = P.KindLabel(r.kind), kinds = { [r.kind] = true } })
      end)
    end
    if r.held then return end
    if r.who and r.hasWho and not r.mine and P.TALK[r.kind] or (r.who and r.chan) then
      local full = P.Core.Names:Address(r.who) or P.Core.Names.Full(r.who) or r.who
      root:CreateButton(L.lineWhisper:format(full), function() ChatFrameUtil.SendTell(full) end)
    end
    local n = 0
    for link in (r.text or ""):gmatch("|c%x+|Hitem:[^|]+|h[^|]+|h|r") do
      n = n + 1
      if n > 3 then break end
      root:CreateButton(L.lineAlertItem:format(link), function() P:AddAlert(link); P:OpenAlerts() end)
    end
    root:CreateButton(L.lineCopy, function()
      local text = P:Format(r, nil) or ""
      text = text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
      P:AskText(L.copyTitle, text)
    end)
  end)
end

-------------------------------------------------------------------------------------------
-- Windows
-------------------------------------------------------------------------------------------

local function savePosition(win)
  local f, d = win.frame, win.data
  d.x, d.y = math.floor(f:GetLeft() + .5), math.floor(f:GetBottom() + .5)
  d.w, d.h = math.floor(f:GetWidth() + .5), math.floor(f:GetHeight() + .5)
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", d.x, d.y)
end
P.SavePosition = savePosition

local function iconButton(parent, icon, size, tip, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(18, 18)
  b.icon = UI.Icon(b, icon, size, C.muted)
  b.icon:SetPoint("CENTER")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", onClick)
  b:SetScript("OnEnter", function(self) self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3]); UI.Tip(self, tip) end)
  b:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]); GameTooltip:Hide() end)
  return b
end

local function createWindow(index)
  local win = { index = index, buttons = {} }
  local f = CreateFrame("Frame", "ScrivenerWindow" .. index, UIParent)
  win.frame = f
  f:SetFrameStrata("LOW")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(220, 110) end
  pcall(f.SetDontSavePosition, f, true)
  f:EnableMouse(false)

  -- the suite's materials on a see-through back (look.lua), and the accent's line under the tab bar, fading away
  P.Glass(win)
  win.rule = f:CreateTexture(nil, "BORDER", nil, 1)
  win.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -RULE_Y)
  win.rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -RULE_Y)
  win.rule:SetHeight(1)

  local bar = CreateFrame("Frame", nil, f)
  win.bar = bar
  bar:SetPoint("TOPLEFT", PAD, -2)
  bar:SetPoint("TOPRIGHT", -PAD, -2)
  bar:SetHeight(BAR_H)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  -- moved by hand (arrange.lua), so it can snap to the screen's edges and other windows
  bar:SetScript("OnDragStart", function() if not P.db.locked then P:BeginMove(win) end end)
  bar:SetScript("OnDragStop", function() P:EndMove(win) end)

  -- Scrivener's mark, on the window with the chat box (UpdateTabs): the window's menu, and a place to drag it by
  win.mark = CreateFrame("Button", nil, bar)
  win.mark:SetSize(MARK, MARK)
  win.mark:SetPoint("LEFT", 0, 0)
  win.mark.tex = UI.Smooth(win.mark:CreateTexture(nil, "ARTWORK"))
  win.mark.tex:SetAllPoints()
  win.mark.tex:SetTexture(P.MARK .. "-small")
  win.mark:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  win.mark:RegisterForDrag("LeftButton")
  win.mark:SetScript("OnClick", function(self) P:WindowMenu(win, self) end)
  win.mark:SetScript("OnEnter", function(self) UI.Tip(self, L.settings) end)
  win.mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.mark:SetScript("OnDragStart", function() if not P.db.locked then P:BeginMove(win) end end)
  win.mark:SetScript("OnDragStop", function() P:EndMove(win) end)
  pcall(win.mark.SetIgnoreParentAlpha, win.mark, true)   -- it stays when the headers fade (Maro, 23 Nov)
  win.mark:Hide()

  win.menuButton = iconButton(bar, "gear", 14, L.settings, function(self) P:WindowMenu(win, self) end)
  win.menuButton:SetPoint("RIGHT", 0, 0)
  win.plus = iconButton(bar, P.MEDIA .. "plus", 13, L.newTab, function(self)
    if P.OpenNewTab then P:OpenNewTab(win, self) else P:PlusMenu(win, self) end   -- the mock-up's builder
  end)   -- placed after the last tab
  win.search = CreateFrame("Button", nil, bar)
  win.search:SetSize(18, 18)
  win.search:SetPoint("RIGHT", win.menuButton, "LEFT", -4, 0)
  -- split: two panes side by side, drawn as the mock-up's columns icon
  win.split = CreateFrame("Button", nil, bar)
  win.split:SetSize(18, 18)
  win.split:SetPoint("RIGHT", win.search, "LEFT", -4, 0)
  local function edge(p1, x1, y1, p2, x2, y2)
    local t = win.split:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 1)
    t:SetPoint(p1, win.split, "CENTER", x1, y1)
    t:SetPoint(p2, win.split, "CENTER", x2, y2)
    return t
  end
  edge("TOPLEFT", -6, 5, "BOTTOMRIGHT", 6, 4)     -- top
  edge("TOPLEFT", -6, -4, "BOTTOMRIGHT", 6, -5)   -- bottom
  edge("TOPLEFT", -6, 5, "BOTTOMRIGHT", -5, -5)   -- left
  edge("TOPLEFT", 5, 5, "BOTTOMRIGHT", 6, -5)     -- right
  edge("TOPLEFT", -.5, 5, "BOTTOMRIGHT", .5, -5)  -- the middle
  win.split:SetScript("OnClick", function(self) P:SplitMenu(win, self) end)
  win.split:SetScript("OnEnter", function(self) UI.Tip(self, L.splitTitle) end)
  win.split:SetScript("OnLeave", function() GameTooltip:Hide() end)
  win.search.icon = UI.Icon(win.search, "search", 13, C.muted)
  win.search.icon:SetPoint("CENTER")
  win.search:SetScript("OnClick", function()
    if win.searchView and win.searchView:IsShown() then P:CloseSearch(win) else P:OpenSearch(win) end
  end)
  win.search:SetScript("OnEnter", function(self) UI.Tip(self, L.searchHint) end)
  win.search:SetScript("OnLeave", function() GameTooltip:Hide() end)

  win.measure = UI.Text(bar, "title", 14)   -- for the tabs' names (P.TabNameWidth)
  win.measure:Hide()

  local body = CreateFrame("Frame", nil, f)
  win.body = body
  body:SetScript("OnSizeChanged", function() if win.data then P:LayoutPanes(win) end end)
  win.seps = {}

  local pill = CreateFrame("Button", nil, f)
  win.pill = pill
  pill:SetHeight(18)
  pill:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -4, 4)
  pill:SetFrameLevel(body:GetFrameLevel() + 20)
  pill.bg = UI.Round(pill, "BACKGROUND", 0, 9)
  pill.bg:SetColor(ACCENT, .9)
  pill.text = UI.Text(pill, "bold", 12, C.void)
  pill.text:SetPoint("CENTER")
  pill:SetScript("OnClick", function()
    local tab = win.data.tabs[win.data.active]
    local tf = tab and P.tabFrames[tab]
    if tf then tf.smf:ScrollToBottom(); scrolled(tf) end
  end)
  pill:Hide()

  local grip = CreateFrame("Button", nil, f)
  win.grip = grip
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)   -- inside the round corner
  grip:SetFrameLevel(body:GetFrameLevel() + 20)
  grip.tex = UI.Smooth(grip:CreateTexture(nil, "OVERLAY"))
  grip.tex:SetAllPoints()
  grip.tex:SetTexture(P.MEDIA .. "grip")
  grip.tex:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3])
  grip:SetScript("OnMouseDown", function() if not P.db.locked then f:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); savePosition(win) end)

  f:SetScript("OnSizeChanged", function() if win.data then P:UpdateTabs(win) end end)

  -- The tabs, headers, wash and rules show; with "Fade the headers" on they fade out two seconds after the mouse
  -- leaves the window's neighbourhood, and come back when it's near. The small buttons brighten on mouse-over.
  win.chrome, win.headers, win.away = 1, 1, 0   -- the buttons and the grip fade to their rest at once
  local elapsed = 0
  f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < .05 then return end
    local step = elapsed
    elapsed = 0
    local box = P.box
    local typing = box and box:HasFocus() and P.dockWin == win   -- typing, not just a box that's showing
    local over = f:IsMouseOver() or typing
    local near = over or f:IsMouseOver(40, -40, -40, 40)
    win.away = near and 0 or (win.away + step)
    local wantHeaders = (not P.db.fadeChrome or near or win.away < 2) and 1 or 0
    if math.abs(win.headers - wantHeaders) > .01 then
      win.headers = win.headers + (wantHeaders - win.headers) * (wantHeaders > win.headers and .5 or .2)
      P:SetChromeAlpha(win, win.headers)
    end
    local target = over and 1 or 0
    if math.abs(win.chrome - target) > .01 then
      win.chrome = win.chrome + (target - win.chrome) * .5
      local show = win.chrome
      grip:SetAlpha(P.db.locked and 0 or show)
      local icons = .45 + .55 * show
      win.plus:SetAlpha(icons); win.menuButton:SetAlpha(icons); win.search:SetAlpha(icons); win.split:SetAlpha(icons)
    end
  end)
  return win
end

local function paintTab(b)
  local on, hover = b.active, b.hover
  local c = on and P.TAB_ON or (hover and C.text or P.TAB_OFF)
  b.label:SetTextColor(c[1], c[2], c[3])
  -- the shown tab is lit from below; the mouse gets a fainter light (UI.Tabs)
  b.wash:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], on and .34 or .12)
  b.wash:SetShown(on or hover or false)
  b.line:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], on and 1 or .35)
  b.line:SetShown(on or hover or false)
end

local function tabButton(win, i)
  local b = win.buttons[i]
  if b then return b end
  b = CreateFrame("Button", nil, win.bar)
  b:SetHeight(BAR_H)
  b.wash = b:CreateTexture(nil, "BACKGROUND")
  b.wash:SetTexture(UI.TEX.tabGlow)
  b.wash:SetPoint("TOPLEFT")
  b.wash:SetPoint("BOTTOMRIGHT", 0, -1)
  b.label = UI.Text(b, "title", 14, C.muted)
  -- unread: an accent badge with dark figures (the mock-up's .tab .b)
  b.badge = CreateFrame("Frame", nil, b)
  b.badge:SetHeight(16)
  b.badge:SetPoint("LEFT", b.label, "RIGHT", 5, 0)
  b.badge.bg = UI.Round(b.badge, "BACKGROUND", 0, 8)
  b.badge.bg:SetColor(ACCENT, 1)
  b.count = UI.Text(b.badge, "bold", 11, { 16 / 255, 18 / 255, 31 / 255 })
  b.count:SetPoint("CENTER", 0, 0)
  -- the active tab's line sits on the rule, fading at its ends
  b.line = b:CreateTexture(nil, "ARTWORK")
  b.line:SetTexture(UI.TEX.tabLine)
  b.line:SetPoint("BOTTOMLEFT", 0, -1)
  b.line:SetPoint("BOTTOMRIGHT", 0, -1)
  b.line:SetHeight(2)
  b:SetScript("OnEnter", function(self) self.hover = true; paintTab(self) end)
  b:SetScript("OnLeave", function(self) self.hover = false; paintTab(self) end)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then return P:TabMenu(win, self.index, self) end
    P:SelectTab(win, self.index, true)
  end)
  b:SetScript("OnDragStart", function(self) P:StartTabDrag(win, self) end)
  b:SetScript("OnDragStop", function(self) P:StopTabDrag(win, self) end)
  win.buttons[i] = b
  return b
end

-- How the tabs share the bar. Their names' size and the mark are settled by the names and a fixed allowance for badges, so
-- a line arriving, or a tab being read, moves nothing about: the room around the names gives way. Only more badges than the
-- allowance change them. When the tabs still don't fit, the last ones that aren't showing step aside (the window's menu
-- lists them).
local PAD_MOST, PAD_LEAST, TAB_GAP, BADGE_GAP = 11, 4, 1, 5
local BADGES, BADGE_W = 2, 31   -- the allowance: two tabs with a two-figure badge
local AT_RIGHT = 62 + 23        -- gear, search and split (18 each, 4 between), and the + after the last tab (4 + 18 + 1)

-- Marcellus, the suite's title font, has Latin letters only: a name with Greek, Cyrillic or the like keeps the body font
local function tabRole(name) return name:find("[\198-\225\227-\244]") and "body" or "title" end

---A tab name's width at a size, remembered per window until its scale changes.
function P.TabNameWidth(win, name, size)
  local scale = win.bar:GetEffectiveScale()
  if win.nameScale ~= scale then win.nameScale, win.nameWidths = scale, {} end
  local key = size .. ":" .. name
  local w = win.nameWidths[key]
  if not w then
    win.measure:SetFontObject(UI.Font(tabRole(name), size))
    win.measure:SetText(name)
    w = win.measure:GetStringWidth() or 0
    if w > 0 then win.nameWidths[key] = w end
  end
  return w
end

function P:UpdateTabs(win)
  local tabs = win.data.tabs
  local n = #tabs
  local width = win.frame:GetWidth()
  if not width or width < 50 then width = win.data.w or 400 end
  local room = width - 2 * PAD - AT_RIGHT
  -- the badges, and the names at each size
  local badges, names = 0, { [14] = 0, [13] = 0 }
  for i, tab in ipairs(tabs) do
    local b = tabButton(win, i)
    b.index = i
    b.active = win.data.active == i
    local unread = 0
    for _, pane in ipairs(panesOf(tab)) do unread = unread + ((self.tabFrames[pane] or {}).unread or 0) end
    b.count:SetText(unread > 0 and (unread > 99 and "99+" or tostring(unread)) or "")
    b.badge:SetWidth(math.max(16, (b.count:GetStringWidth() or 0) + 10))
    b.badge:SetShown(unread > 0)
    b.extra = unread > 0 and b.badge:GetWidth() + BADGE_GAP or 0
    badges = badges + b.extra
    for size in pairs(names) do names[size] = names[size] + P.TabNameWidth(win, tab.name, size) end
  end
  local marked = (self.dockWin or self.windows[1]) == win
  local left = marked and MARK + 5 or 0
  local least = math.max(0, n - 1) * TAB_GAP + 2 * n * PAD_LEAST
  local extra = math.max(badges, math.min(math.max(0, n - 1), BADGES) * BADGE_W)
  local size = left + names[14] + least + extra <= room and 14 or 13
  if left + names[size] + least + extra > room then marked, left = false, 0 end   -- small windows keep the room for their tabs
  win.mark:SetShown(marked)
  local free = room - left - names[size] - badges - math.max(0, n - 1) * TAB_GAP
  local pad = math.max(PAD_LEAST, math.min(PAD_MOST, math.floor(free / (2 * math.max(1, n)))))

  local function widthOf(i) return P.TabNameWidth(win, tabs[i].name, size) + 2 * pad + win.buttons[i].extra end
  -- the shown tab always has its place; the others fill what's left, in order
  local active = tabs[win.data.active] and win.data.active
  local spare = room - left - (active and widthOf(active) or 0)
  local x, full = left, false
  win.hiddenTabs = 0
  for i, tab in ipairs(tabs) do
    local b = win.buttons[i]
    local w = widthOf(i)
    local fits = i == active or (i == 1 and not active)
    if not fits and not full then
      fits = w + TAB_GAP <= spare
      if fits then spare = spare - w - TAB_GAP else full = true end   -- from here on, only the shown tab
    end
    b.label:SetText(tab.name)
    local look = tabRole(tab.name) .. size
    if b.look ~= look then
      b.look = look
      b.label:SetFontObject(UI.Font(tabRole(tab.name), size))
    end
    if b.pad ~= pad then
      b.pad = pad
      b.label:ClearAllPoints()
      b.label:SetPoint("LEFT", pad, 0)
    end
    paintTab(b)   -- after the font, which may bring its own colour
    pcall(b.label.SetIgnoreParentAlpha, b.label, b.active)   -- the shown tab keeps its name when the tab bar fades
    b:SetWidth(w)
    b:ClearAllPoints()
    b:SetPoint("LEFT", win.bar, "LEFT", x, 0)
    b:SetShown(fits)
    if fits then x = x + w + TAB_GAP else win.hiddenTabs = win.hiddenTabs + 1 end
  end
  for i = n + 1, #win.buttons do win.buttons[i]:Hide() end
  win.plus:ClearAllPoints()
  win.plus:SetPoint("LEFT", win.bar, "LEFT", x - TAB_GAP + 4, 0)   -- + sits right after the last tab, as in the mock-up
end

function P:SelectTab(win, index, byPlayer)
  if win.searchView and win.searchView:IsShown() then win.searchView:Hide() end   -- picking a tab ends a search
  win.data.active = index
  for i, tab in ipairs(win.data.tabs) do
    for _, pane in ipairs(panesOf(tab)) do
      local tf = self.tabFrames[pane]
      if tf then
        tf.frame:SetShown(i == index)
        if i == index then tf.unread = 0; tf.newCount = 0; scrolled(tf) end
      end
    end
  end
  win.pill:Hide()
  self:LayoutPanes(win)
  self:UpdateTabs(win)
  if byPlayer and self.DockBox then self:DockBox(win) end   -- the chat box follows the window you last used
end

---Bring windows in line with db.windows: frames, tabs and message frames, reusing what exists.
function P:SyncWindows()
  local datas = self.db.windows
  local keepTabs = {}
  local dock = self.dockWin
  for i, data in ipairs(datas) do
    local win = self.windows[i] or createWindow(i)
    self.windows[i] = win
    win.index, win.data = i, data
    local f = win.frame
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", data.x or 20, data.y or 60)
    f:SetSize(data.w or 440, data.h or 200)
    self:PaintWindow(win)
    f:Show()
    if not data.active or not data.tabs[data.active] then data.active = 1 end
    for _, tab in ipairs(data.tabs) do
      for _, pane in ipairs(panesOf(tab)) do
        keepTabs[pane] = true
        local tf = self.tabFrames[pane] or newMessageFrame(pane)
        tf.win, tf.tab = win, tab
        tf.frame:SetParent(win.body)
        P.SetPaneFont(tf.smf, self:FontFor(win))
        self:UpdatePaneHead(pane, tf)
      end
    end
    self:LayoutBody(win)
    self:SelectTab(win, data.active)
  end
  for i = #datas + 1, #self.windows do
    self.windows[i].frame:Hide()
    self.windows[i] = nil
  end
  for pane, tf in pairs(self.tabFrames) do
    if not keepTabs[pane] then tf.frame:Hide(); self.tabFrames[pane] = nil end
  end
  if not (dock and self.windows[dock.index] == dock) then dock = self.windows[1] end
  if self.DockBox and dock then self:DockBox(dock) end
end

function P:LayoutBody(win)
  local bottom = 4
  if self.box and self.dockWin == win then bottom = 8 + P.COMPOSE_H + 4 end   -- the chat box always has its place
  win.body:ClearAllPoints()
  win.body:SetPoint("TOPLEFT", win.frame, "TOPLEFT", 1, -(RULE_Y + 1))
  win.body:SetPoint("BOTTOMRIGHT", win.frame, "BOTTOMRIGHT", -1, bottom)
  self:LayoutPanes(win)
end

-------------------------------------------------------------------------------------------
-- Arranging a tab's panes: side by side, one above the other, or two stacked beside one. Every line between panes is
-- a handle: drag it to share the room differently. tab.arrange is the arrangement, tab.sizes the shares it uses
-- (row and stack: each pane's share; the two-and-one arrangements: the column's share, then the top pane's).
-------------------------------------------------------------------------------------------

P.ARRANGE = { "row", "stack", "left2", "right2" }
local MIN_PANE = 70

function P.Arrangement(tab)
  local n = #panesOf(tab)
  local mode = tab.arrange or "row"
  if (mode == "left2" or mode == "right2") and n ~= 3 then mode = "row" end
  return mode
end

-- the panes' rectangles (x, y from the body's top left) and the handles between them
local function plan(tab, n, W, H)
  local mode = P.Arrangement(tab)
  local sizes = tab.sizes or {}
  local rects, handles = {}, {}
  if mode == "row" or mode == "stack" then
    local across = mode == "row"
    local total = across and W or H
    local shares = sizes
    if #shares ~= n then shares = {}; for i = 1, n do shares[i] = 1 / n end end
    local pos = 0
    for i = 1, n do
      local len = total * shares[i]
      rects[i] = across and { x = pos, y = 0, w = len, h = H } or { x = 0, y = pos, w = W, h = len }
      pos = pos + len
      if i < n then
        handles[#handles + 1] = { axis = across and "x" or "y", at = pos, from = 0, len = across and H or W,
          drag = function(c)
            local before = 0
            for k = 1, i - 1 do before = before + shares[k] end
            local pair = shares[i] + shares[i + 1]
            local least = MIN_PANE / total
            local share = math.max(least, math.min(pair - least, c / total - before))
            local new = {}
            for k = 1, n do new[k] = shares[k] end
            new[i], new[i + 1] = share, pair - share
            tab.sizes = new
          end }
      end
    end
    return rects, handles
  end
  local col = sizes[1] or .5
  local top = sizes[2] or .5
  local colW, topH = W * col, H * top
  local function setCol(c) tab.sizes = { math.max(MIN_PANE / W, math.min(1 - MIN_PANE / W, c / W)), top } end
  local function setTop(c) tab.sizes = { col, math.max(MIN_PANE / H, math.min(1 - MIN_PANE / H, c / H)) } end
  if mode == "left2" then
    rects[1] = { x = 0, y = 0, w = colW, h = topH }
    rects[2] = { x = 0, y = topH, w = colW, h = H - topH }
    rects[3] = { x = colW, y = 0, w = W - colW, h = H }
    handles[1] = { axis = "x", at = colW, from = 0, len = H, drag = setCol }
    handles[2] = { axis = "y", at = topH, from = 0, len = colW, drag = setTop }
  else
    rects[1] = { x = 0, y = 0, w = colW, h = H }
    rects[2] = { x = colW, y = 0, w = W - colW, h = topH }
    rects[3] = { x = colW, y = topH, w = W - colW, h = H - topH }
    handles[1] = { axis = "x", at = colW, from = 0, len = H, drag = setCol }
    handles[2] = { axis = "y", at = topH, from = colW, len = W - colW, drag = setTop }
  end
  return rects, handles
end

---The active tab's panes, arranged; a faint rule and a drag handle on every line between them.
function P:LayoutPanes(win)
  local tab = win.data and win.data.tabs[win.data.active]
  if not tab then return end
  local panes = panesOf(tab)
  local W = win.body:GetWidth()
  if not W or W < 50 then W = (win.data.w or 400) - 2 end
  local H = win.body:GetHeight()
  if not H or H < 50 then H = (win.data.h or 300) - 80 end
  local rects, handles = plan(tab, #panes, W, H)
  win.handles = handles
  for i, pane in ipairs(panes) do
    local tf = self.tabFrames[pane]
    local r = rects[i]
    if tf and r then
      tf.frame:ClearAllPoints()
      tf.frame:SetPoint("TOPLEFT", win.body, "TOPLEFT", r.x, -r.y)
      tf.frame:SetSize(math.max(1, r.w - 1), math.max(1, r.h - 1))
      tf.smf:ClearAllPoints()
      tf.smf:SetPoint("TOPLEFT", tf.head, "BOTTOMLEFT", 7, -3)
      tf.smf:SetPoint("BOTTOMRIGHT", tf.frame, "BOTTOMRIGHT", -8, 2)
      if self.LayoutBoard then self:LayoutBoard(pane, tf) end
    end
  end
  win.dividers = win.dividers or {}
  for i, h in ipairs(handles) do
    local sep = win.seps[i]
    if not sep then
      sep = P.Hairline(win.body, .07)
      win.seps[i] = sep
    end
    sep:ClearAllPoints()
    local d = self:Divider(win, i)
    if h.axis == "x" then
      sep:SetPoint("TOPLEFT", win.body, "TOPLEFT", h.at - 1, -h.from)
      sep:SetSize(1, h.len)
      d:SetSize(9, math.max(20, h.len - 8))
    else
      sep:SetPoint("TOPLEFT", win.body, "TOPLEFT", h.from, -(h.at - 1))
      sep:SetSize(h.len, 1)
      d:SetSize(math.max(20, h.len - 8), 9)
    end
    d.axis = h.axis
    d.line:ClearAllPoints()
    if h.axis == "x" then
      d.line:SetPoint("TOP"); d.line:SetPoint("BOTTOM"); d.line:SetWidth(2)
    else
      d.line:SetPoint("LEFT"); d.line:SetPoint("RIGHT"); d.line:SetHeight(2)
    end
    d:SetPoint("CENTER", sep, "CENTER", 0, 0)
    sep:Show()
    d:Show()
  end
  for i = #handles + 1, #win.seps do win.seps[i]:Hide() end
  for i = #handles + 1, #win.dividers do win.dividers[i]:Hide() end
  self:SetChromeAlpha(win, win.headers or 1)
end

---The handle on a line between panes: drag it to share the room differently.
function P:Divider(win, i)
  win.dividers = win.dividers or {}
  local d = win.dividers[i]
  if d then d:ClearAllPoints(); return d end
  d = CreateFrame("Button", nil, win.body)
  d:SetFrameLevel(win.body:GetFrameLevel() + 30)
  d.line = d:CreateTexture(nil, "OVERLAY")
  d.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], .8)
  d.line:Hide()
  d:SetScript("OnEnter", function(self) self.line:Show() end)
  d:SetScript("OnLeave", function(self) if not self.dragging then self.line:Hide() end end)
  d:SetScript("OnMouseDown", function(self) self.dragging = true end)
  d:SetScript("OnMouseUp", function(self)
    self.dragging = nil
    if not self:IsMouseOver() then self.line:Hide() end
  end)
  d:SetScript("OnUpdate", function(self)
    if not self.dragging then return end
    local h = win.handles and win.handles[i]
    if not h then return end
    local scale = win.body:GetEffectiveScale()
    local x, y = GetCursorPosition()
    local c
    if h.axis == "x" then c = x / scale - (win.body:GetLeft() or 0)
    else c = (win.body:GetTop() or 0) - y / scale end
    h.drag(c)
    P:LayoutPanes(win)
  end)
  win.dividers[i] = d
  return d
end

---Set how a tab's panes sit: "row", "stack", "left2" or "right2".
function P:Arrange(win, tab, mode)
  tab.arrange = mode ~= "row" and mode or nil
  tab.sizes = nil
  self:LayoutPanes(win)
end

---The headers' alpha (tab bar, wash, rules, pane headers, an idle chat box): 1, or fading with "Fade the headers".
function P:SetChromeAlpha(win, a)
  win.bar:SetAlpha(a)
  self:PaintWindow(win)
  for _, sep in ipairs(win.seps) do sep:SetAlpha(a) end
  local tab = win.data and win.data.tabs[win.data.active]
  for _, pane in ipairs(tab and panesOf(tab) or {}) do
    local tf = self.tabFrames[pane]
    if tf then tf.head:SetAlpha(a) end   -- all but the pane's name, which ignores its header's alpha
  end
  if self.SetComposeAlpha and self.dockWin == win then self:SetComposeAlpha(a) end
end

---The window's glass, shadow, light and wash: the opacity setting, times the header fade when the background fades too.
function P:PaintWindow(win)
  local headers = win.headers or 1
  local glass = self.db.alpha or .8
  if self.db.fadeBackground then glass = glass * headers end
  P.PaintGlass(win, glass, headers)
end

function P:SetOpacity(v)
  self.db.alpha = v
  for _, win in ipairs(self.windows) do self:PaintWindow(win) end
  if self.settingsList then self.settingsList:Refresh() end
end

function P:NewWindow(tabs, x, y)
  local data = { x = x or 520, y = y or 300, w = 380, h = 180, tabs = tabs or { TABS.whispers() }, active = 1 }
  self.db.windows[#self.db.windows + 1] = data
  self:SyncWindows()
end

function P:CloseWindow(win)
  if #self.db.windows <= 1 then return end
  table.remove(self.db.windows, win.index)
  self:SyncWindows()
end

function P:MoveTabToNewWindow(win, index)
  local tab = table.remove(win.data.tabs, index)
  if win.data.active >= index then win.data.active = math.max(1, win.data.active - 1) end
  local f = win.frame
  self:NewWindow({ tab }, f:GetLeft() + 30, f:GetBottom() + f:GetHeight() + 16)
end

function P:ApplyLayout(name)
  local layout = self.LAYOUTS[name]
  if not layout then return self:Print(L.layoutUnknown) end
  wipe(self.db.windows)
  for _, w in ipairs(layout) do
    local tabs = {}
    for _, key in ipairs(w.tabs) do
      if type(key) == "table" then   -- a tab with panes beside it
        local tab = TABS[key[1]]()
        tab.split = {}
        for j = 2, #key do tab.split[#tab.split + 1] = TABS[key[j]]() end
        tabs[#tabs + 1] = tab
      else
        tabs[#tabs + 1] = TABS[key]()
      end
    end
    local x = w.x
    if w.right then x = math.floor((UIParent:GetWidth() or 1366) - w.w - w.x) end   -- the right-hand corner
    self.db.windows[#self.db.windows + 1] = { x = x, y = w.y, w = w.w, h = w.h, tabs = tabs, active = 1 }
  end
  self.db.layout = name
  self:SyncWindows()
end

function P:SetLocked(on)
  self.db.locked = on and true or false
  self:Print(on and L.locked or L.unlocked)
  for _, win in ipairs(self.windows) do win.chrome = 0 end
end

-------------------------------------------------------------------------------------------
-- Dragging tabs
-------------------------------------------------------------------------------------------

---Where a dragged tab would land if dropped now: "split" (beside the tab shown in a window; stack = one above the
---other), "move" (onto another window's tab bar), "reorder" (its own tab bar), "stay" (its own window, elsewhere) or
---"new" (empty screen: a window of its own).
function P:DropTarget(win, tab)
  for _, other in ipairs(self.windows) do
    if other.frame:IsShown() and other.body:IsMouseOver() then
      local shown = other.data.tabs[other.data.active]
      if shown and shown ~= tab and not tab.split and #panesOf(shown) < MAX_PANES then
        local _, y = GetCursorPosition()
        y = y / other.body:GetEffectiveScale()
        local bottom, h = other.body:GetBottom() or 0, other.body:GetHeight() or 1
        local stack = #panesOf(shown) == 1 and y < bottom + h * .35
        return "split", other, stack
      end
    end
  end
  for _, other in ipairs(self.windows) do
    if other ~= win and other.frame:IsShown() and other.frame:IsMouseOver() then return "move", other end
  end
  if win.bar:IsMouseOver() then return "reorder", win end
  if win.frame:IsMouseOver() then return "stay", win end
  return "new"
end

local ghost, drop
local function dropBox()
  if drop then return drop end
  drop = CreateFrame("Frame", nil, UIParent)
  drop:SetFrameStrata("TOOLTIP")
  drop.bg = UI.Round(drop, "BACKGROUND", 0, 4)
  drop.bg:SetColor(ACCENT, .16)
  drop.line = UI.Round(drop, "BORDER", 0, 4, "line")
  drop.line:SetColor(ACCENT, 1)
  drop.text = UI.Text(drop, "body", 13, { 1, 1, 1 })
  drop.text:SetPoint("TOP", 0, -12)
  drop:Hide()
  return drop
end

-- light up what a drop would do: the window's lines it would split (the half the new pane takes), or the tab bar
local function showDrop(win, tab)
  local kind, target, stack = P:DropTarget(win, tab)
  local d = dropBox()
  d:ClearAllPoints()
  if kind == "split" then
    local body = target.body
    if stack then
      d:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 4, 4)
      d:SetPoint("TOPRIGHT", body, "RIGHT", -4, -2)
      d.text:SetText(L.dropSplit:format(L.arrangeAs.stack))
    else
      d:SetPoint("TOPRIGHT", body, "TOPRIGHT", -4, -4)
      d:SetPoint("BOTTOMLEFT", body, "BOTTOM", 2, 4)
      local shown = target.data.tabs[target.data.active]
      local mode = #panesOf(shown) == 1 and "row" or P.Arrangement(shown)
      d.text:SetText(L.dropSplit:format(L.arrangeAs[mode] or L.arrangeAs.row))
    end
    d:Show()
  elseif kind == "move" then
    d:SetPoint("TOPLEFT", target.bar, "TOPLEFT", -2, 2)
    d:SetPoint("BOTTOMRIGHT", target.bar, "BOTTOMRIGHT", 2, -2)
    d.text:SetText("")
    d:Show()
  else
    d:Hide()
  end
  ghost.hint:SetText(kind == "new" and L.dropNew or (kind == "move" and L.dropMove or ""))
  ghost:SetWidth(math.max(ghost.text:GetStringWidth(), ghost.hint:GetStringWidth()) + 24)
  ghost:SetHeight(ghost.hint:GetText() ~= "" and 38 or 24)
end

function P:StartTabDrag(win, button)
  if not ghost then
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(120, 24)
    ghost.bg = UI.Round(ghost, "BACKGROUND", 0, 4)
    ghost.bg:SetColor(UI.Mix(C.stone, ACCENT, .05), .97)
    ghost.line = UI.Round(ghost, "BORDER", 0, 4, "line")
    ghost.line:SetColor(ACCENT, 1)
    ghost.text = UI.Text(ghost, "body", 13, C.text)
    ghost.text:SetPoint("TOP", 0, -5)
    ghost.hint = UI.Text(ghost, "body", 11, C.muted)
    ghost.hint:SetPoint("TOP", ghost.text, "BOTTOM", 0, -2)
    ghost:SetScript("OnUpdate", function(self)
      local x, y = GetCursorPosition()
      local s = UIParent:GetEffectiveScale()
      self:ClearAllPoints()
      self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 14, y / s - 10)
      if self.win and self.tab then showDrop(self.win, self.tab) end
    end)
  end
  ghost.win, ghost.tab = win, win.data.tabs[button.index]
  ghost.text:SetText(ghost.tab and ghost.tab.name or "")
  ghost.hint:SetText("")
  ghost:SetWidth(ghost.text:GetStringWidth() + 24)
  ghost:Show()
end

function P:StopTabDrag(win, button)
  if ghost then ghost:Hide(); ghost.win, ghost.tab = nil, nil end
  if drop then drop:Hide() end
  local index = button.index
  local tab = win.data.tabs[index]
  if not tab then return end
  local kind, target, stack = self:DropTarget(win, tab)
  if kind == "split" then
    -- the tab becomes a pane beside (or under) the tab shown there
    local shown = target.data.tabs[target.data.active]
    for i, t in ipairs(win.data.tabs) do if t == tab then table.remove(win.data.tabs, i); break end end
    if #win.data.tabs == 0 then table.remove(self.db.windows, win.index)
    elseif win.data.active > #win.data.tabs then win.data.active = #win.data.tabs end
    for i, t in ipairs(target.data.tabs) do if t == shown then target.data.active = i end end
    shown.split = shown.split or {}
    shown.split[#shown.split + 1] = tab
    if stack then shown.arrange = "stack"; shown.sizes = nil end
    return self:SyncWindows()
  end
  if kind == "move" then
    table.remove(win.data.tabs, index)
    if #win.data.tabs == 0 then table.remove(self.db.windows, win.index)
    elseif win.data.active >= index then win.data.active = math.max(1, win.data.active - 1) end
    target.data.tabs[#target.data.tabs + 1] = tab
    target.data.active = #target.data.tabs
    return self:SyncWindows()
  end
  if kind == "reorder" then
    -- reorder within the bar
    local x = GetCursorPosition() / win.bar:GetEffectiveScale() - win.bar:GetLeft()
    local to = #win.data.tabs
    for i, b in ipairs(win.buttons) do
      if b:IsShown() and i <= #win.data.tabs and x < (b:GetLeft() - win.bar:GetLeft()) + b:GetWidth() / 2 then to = i; break end
    end
    if to ~= index then
      table.remove(win.data.tabs, index)
      table.insert(win.data.tabs, to, tab)
      win.data.active = to
      self:SyncWindows()
    end
    return
  end
  if kind == "stay" then return end
  -- empty screen: a new window where it was dropped
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  if #win.data.tabs == 1 then
    win.data.x, win.data.y = math.floor(x / s - 40), math.floor(y / s - win.frame:GetHeight() + 10)
    return self:SyncWindows()
  end
  table.remove(win.data.tabs, index)
  if win.data.active >= index then win.data.active = math.max(1, win.data.active - 1) end
  self:NewWindow({ tab }, math.floor(x / s - 40), math.floor(y / s - 170))
end

-------------------------------------------------------------------------------------------
-- Start
-------------------------------------------------------------------------------------------

P:OnReady(function()
  if not P.db.takeover then return end
  P.sessionStart = time()
  P:ApplyFont()
  P.Core:OnLogin(function()
    -- 0.5.0's search tabs (search is a view over the window now) don't survive a reload
    for _, data in ipairs(P.db.windows) do
      for i = #data.tabs, 1, -1 do if data.tabs[i].special == "search" then table.remove(data.tabs, i) end end
      if #data.tabs == 0 then data.tabs[1] = TABS.general() end
    end
    if #P.db.windows == 0 then
      P:ApplyLayout("one")
      P.firstRun = true
    else
      P:SyncWindows()
    end
    if (P.firstRun or P.db.offerLayouts) and P.ShowLayoutPicker then
      P.db.offerLayouts = nil
      C_Timer.After(2, function() P:ShowLayoutPicker() end)
    end
  end)
end)
