-- Search, as the mock-up drew it: a box across the top of the window, chips for where to look (everywhere, whispers,
-- guild, party, this session), and the results newest first: when and where on one line, who and what on the next,
-- the words you searched for marked. Pick a result to jump to it in its tab. It searches this session and everything
-- history kept, as you type. Ctrl-F in the chat box opens it too; Esc closes it.

local P = Scrivener
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C
local Hidden = P.Hidden

local ACCENT = UI.Hex(P.ACCENT_HEX)
local ROW_H, MAX_RESULTS, MAX_MARKS = 42, 200, 3
local FILTERS = { "all", "whispers", "guild", "party", "session" }
local IN = { whispers = { WHISPER = true }, guild = { GUILD = true, OFFICER = true },
  party = { PARTY = true, RAID = true, INSTANCE = true } }

-------------------------------------------------------------------------------------------
-- Finding
-------------------------------------------------------------------------------------------

-- the words of a line, plain and in lower case, kept per line so typing a longer word doesn't redo them all
local lowOf = setmetatable({}, { __mode = "k" })
local function plainLower(entry, text)
  local low = lowOf[entry]
  if low == nil then
    if type(text) ~= "string" or Hidden(text) then low = false
    else low = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):lower() end
    lowOf[entry] = low
  end
  return low
end

---Lines that say `query` (or are from someone of that name), newest first: { record, ... }.
function P:Find(query, filter)
  local needle = (query or ""):lower():match("^%s*(.-)%s*$")
  if #needle < 2 then return {} end
  local kinds = IN[filter]
  local found = {}
  local function hit(text, who, entry)
    local low = plainLower(entry, text)
    if low and low:find(needle, 1, true) then return true end
    return type(who) == "string" and not Hidden(who) and who:lower():find(needle, 1, true) ~= nil
  end
  -- this session's lines, newest first
  for i = #self.records, 1, -1 do
    local r = self.records[i]
    if not (r.held or r.note) and (not kinds or kinds[r.kind]) and r.kind ~= "ADDONS" and hit(r.text, r.who, r) then
      found[#found + 1] = r
      if #found >= MAX_RESULTS then return found end
    end
  end
  if filter == "session" then return found end
  -- then what history kept from before it
  local older = {}
  self:EachSaved(nil, function(e, h)
    if (not kinds or kinds[e[7]]) and hit(e[4], e[3], e) then older[#older + 1] = { e, h } end
  end)
  table.sort(older, function(a, b) return a[1][1] > b[1][1] end)
  for _, pair in ipairs(older) do
    found[#found + 1] = self.HistoryRecord(pair[1], pair[2])
    if #found >= MAX_RESULTS then break end
  end
  return found
end

-------------------------------------------------------------------------------------------
-- Drawing a result
-------------------------------------------------------------------------------------------

local function dayLabel(t)
  local day = date("%Y%m%d", t)
  if day == date("%Y%m%d") then return L.today end
  if day == date("%Y%m%d", time() - 86400) then return L.yesterday end
  if time() - t < 6 * 86400 then return date("%A", t) end
  return date("%d %b", t)
end

local function whoText(r)
  if type(r.who) ~= "string" or r.who == "" then return "" end
  -- a creature's emote names it in its words ("%s attempts to run away in fear!"): no name in front as well
  if P.NPC_TYPES and P.NPC_TYPES[r.type] and type(r.text) == "string" and r.text:find("%s", 1, true) then return "" end
  local shown
  if r.bn then
    shown = P.BNColor() .. r.who .. "|r"
  else
    shown = P.ShowName(P.Core.Names.Full(r.who) or r.who)
    local hex = P.ClassHex and P.ClassHex(r.guid)
    if hex then shown = "|c" .. hex .. shown .. "|r" end
  end
  if P.WHISPER_OUT[r.type] then return L.to:format(shown) .. ": " end
  return shown .. ": "
end

---The result's line, with each place the words appear in white; returns the text and, for the first few, the text
---before the match and the match itself (to measure where to draw its mark).
local function marked(r, needle)
  local text = (P.NPCText and P.NPCText(r)) or r.text or ""
  local out, marks = whoText(r), {}
  local pos = 1
  while pos <= #text do
    local s, e = text:find("|H.-|h.-|h", pos)   -- links are kept whole: nothing is marked inside one
    local plainEnd = s and s - 1 or #text
    local seg = text:sub(pos, plainEnd)
    local low = seg:lower()
    local i = 1
    while true do
      local a, b = low:find(needle, i, true)
      if not a then break end
      out = out .. seg:sub(i, a - 1)
      local word = seg:sub(a, b)
      if #marks < MAX_MARKS then marks[#marks + 1] = { before = out, word = word } end
      out = out .. "|cffffffff" .. word .. "|r"
      i = b + 1
    end
    out = out .. seg:sub(i)
    if not s then break end
    out = out .. text:sub(s, e)
    pos = e + 1
  end
  return out, marks
end

-------------------------------------------------------------------------------------------
-- The search view
-------------------------------------------------------------------------------------------

local function build(win)
  local v = CreateFrame("Frame", nil, win.frame)
  v:SetAllPoints(win.body)
  v:SetFrameLevel(win.body:GetFrameLevel() + 10)
  v:EnableMouse(true)
  v:Hide()
  win.searchView = v

  -- the box: a suite text field, lit while you type in it
  local bar = CreateFrame("Frame", nil, v)
  bar:SetPoint("TOPLEFT", 10, -8)
  bar:SetPoint("TOPRIGHT", -10, -8)
  bar:SetHeight(26)
  P.FieldLook(bar)
  v.bar = bar
  bar.icon = UI.Icon(bar, "search", 13, C.muted)
  bar.icon:SetPoint("LEFT", 10, 0)
  bar.hint = UI.Text(bar, "body", 12, C.faint)
  bar.hint:SetPoint("RIGHT", -12, 0)
  v.hint = bar.hint
  local edit = CreateFrame("EditBox", nil, bar)
  edit:SetPoint("LEFT", bar.icon, "RIGHT", 7, 0)
  edit:SetPoint("RIGHT", bar.hint, "LEFT", -8, 0)
  edit:SetHeight(20)
  edit:SetFontObject(UI.Font("body", 14))
  edit:SetTextColor(C.text[1], C.text[2], C.text[3])
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(60)
  edit:HookScript("OnEditFocusGained", function() bar:Light(true) end)
  edit:HookScript("OnEditFocusLost", function() bar:Light(false) end)
  v.edit = edit

  -- where to look
  v.chips = {}
  local x = 10
  for _, key in ipairs(FILTERS) do
    local chip = UI.Chip(v, L.searchIn[key], nil, function(on)
      if not on then v.chips[key]:SetOn(true, true); return end
      for k, c in pairs(v.chips) do if k ~= key then c:SetOn(false, true) end end
      v.filter = key
      P:RunSearch(win)
    end)
    if chip.ApplyAccent then chip:ApplyAccent(ACCENT) end
    chip:SetPoint("TOPLEFT", x, -40)
    x = x + chip:GetWidth() + 5
    v.chips[key] = chip
  end

  v.measure = v:CreateFontString(nil, "BACKGROUND")
  v.measure:SetFontObject(UI.Font("body", 13))
  v.measure:Hide()

  v.list = UI.List(v, {
    rowHeight = ROW_H,
    createRow = function(row, content)
      row.marks = {}
      for i = 1, MAX_MARKS do
        local m = content:CreateTexture(nil, "BACKGROUND", nil, 1)
        m:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], .35)
        m:Hide()
        row.marks[i] = m
      end
      row.when = UI.Text(content, "body", 11, C.faint)
      row.when:SetPoint("TOPLEFT", 12, -5)
      row.text = UI.Text(content, "body", 13, C.text)
      row.text:SetPoint("TOPLEFT", 12, -20)
      row.text:SetPoint("RIGHT", -52, 0)
      row.text:SetWordWrap(false)
      row.jump = UI.Text(content, "body", 12, ACCENT)
      row.jump:SetPoint("RIGHT", -14, 0)
      row.jump:SetText(L.jump)
      row.rule = P.Hairline(content)
      row.rule:SetPoint("BOTTOMLEFT", 0, 0)
      row.rule:SetPoint("BOTTOMRIGHT", 0, 0)
      row.rule:SetHeight(1)
    end,
    updateRow = function(row, r)
      row.when:SetText(dayLabel(r.t or time()) .. " " .. date("%H:%M", r.t or time()) .. "  \194\183  " .. P.KindLabel(r.kind)
        .. (r.from and "  \194\183  " .. r.from or ""))   -- another character's
      local text, marks = marked(r, v.needle or "")
      row.text:SetText(P.LowerIcons(text, 13))   -- 13: the row's own text size
      local room = (row.text:GetWidth() or 0)
      for i, m in ipairs(row.marks) do
        local mk = marks[i]
        m:Hide()
        if mk then
          v.measure:SetText(mk.before)
          local x0 = v.measure:GetStringWidth() or 0
          v.measure:SetText(mk.before .. mk.word)
          local x1 = v.measure:GetStringWidth() or 0
          if x1 > x0 and (room <= 0 or x1 <= room) then
            m:ClearAllPoints()
            m:SetPoint("TOPLEFT", row.text, "TOPLEFT", x0 - 1, 1)
            m:SetSize(x1 - x0 + 2, 16)
            m:Show()
          end
        end
      end
    end,
    onClick = function(r) P:JumpTo(r, win) end,
  })
  v.list:SetPoint("TOPLEFT", 0, -66)
  v.list:SetPoint("BOTTOMRIGHT", 0, 2)
  if v.list.ApplyAccent then v.list:ApplyAccent(ACCENT) end
  v.empty = UI.Text(v, "body", 13, C.faint)
  v.empty:SetPoint("TOP", v, "TOP", 0, -84)

  local pending
  edit:SetScript("OnTextChanged", function()
    if pending then return end
    pending = true
    C_Timer.After(.25, function() pending = false; P:RunSearch(win) end)
  end)
  edit:SetScript("OnEscapePressed", function() P:CloseSearch(win) end)
  edit:SetScript("OnEnterPressed", function(self)
    local first = v.results and v.results[1]
    if first then P:JumpTo(first, win) else self:ClearFocus() end
  end)
  v:SetScript("OnHide", function() edit:ClearFocus() end)
  return v
end

function P:RunSearch(win)
  local v = win.searchView
  if not v then return end
  local query = v.edit:GetText() or ""
  v.needle = query:lower():match("^%s*(.-)%s*$")
  v.results = self:Find(query, v.filter)
  v.list:SetData(v.results)
  local n = #v.results
  local typed = #v.needle >= 2
  v.empty:SetText(not typed and L.searchEmpty or (n == 0 and L.searchNone or ""))
  v.hint:SetText(not typed and L.searchEsc or (n == 1 and L.searchOne or L.searchCount:format(n)))
end

---Open the search view over a window's panes, with words already in it if given.
function P:OpenSearch(win, query)
  win = win or self.dockWin or self.windows[1]
  if not win then return end
  local v = win.searchView or build(win)
  for _, pane in ipairs(P.PanesOf(win.data.tabs[win.data.active] or {})) do
    local tf = self.tabFrames[pane]
    if tf then tf.frame:Hide() end
  end
  win.pill:Hide()
  v.filter = v.filter or "all"
  for k, c in pairs(v.chips) do c:SetOn(k == v.filter, true) end
  v:Show()
  v.edit:SetText(query or v.edit:GetText() or "")
  v.edit:SetFocus()
  v.edit:HighlightText()
  self:RunSearch(win)
end

function P:CloseSearch(win)
  local v = win and win.searchView
  if not (v and v:IsShown()) then return end
  v:Hide()
  self:SelectTab(win, win.data.active)
end

---The old command and the window menu: search for words.
function P:Search(query, win)
  self:OpenSearch(win, query)
end

-------------------------------------------------------------------------------------------
-- Jumping to a result
-------------------------------------------------------------------------------------------

local function same(a, b)
  return a == b or (a and b and a.t == b.t and a.text == b.text and a.who == b.who and a.kind == b.kind)
end

-- the line's place in a message frame, counted from the newest (the scroll offset that brings it to the bottom)
local function placeOf(smf, r)
  local n = smf.GetNumMessages and smf:GetNumMessages() or 0
  if n == 0 or not smf.GetMessageInfo then return nil end
  local ids = {}
  for i = 1, n do
    local ok, id = pcall(function() return P.EntryId(smf:GetMessageInfo(i)) end)
    ids[i] = ok and id or nil
  end
  -- which end is the newest: compare the times of the first and last lines with a record behind them
  local first, last
  for i = 1, n do local x = P.byId[ids[i]]; if type(ids[i]) == "number" and x then first = x.t; break end end
  for i = n, 1, -1 do local x = P.byId[ids[i]]; if type(ids[i]) == "number" and x then last = x.t; break end end
  local newestFirst = first and last and first > last
  for i = 1, n do
    local x = type(ids[i]) == "number" and P.byId[ids[i]]
    if x and same(x, r) then return newestFirst and (i - 1) or (n - i), x end
  end
end

---Show a search result where it was said: its tab in front, scrolled to it, marked for a few seconds.
function P:JumpTo(r, from)
  if from then self:CloseSearch(from) end
  local pane, tf
  if r.kind == "WHISPER" and self.ConvoKey(r) then
    self:Reveal(r)
    for p, t in pairs(self.tabFrames) do if p.special == "convos" then pane, tf = p, t end end
  else
    local wins = {}
    if from then wins[1] = from end
    for _, w in ipairs(self.windows) do if w ~= from then wins[#wins + 1] = w end end
    for _, win in ipairs(wins) do
      for i, tab in ipairs(win.data.tabs) do
        for _, p in ipairs(P.PanesOf(tab)) do
          if not pane and not p.special and P.TabWants(p, r) then
            pane, tf = p, self.tabFrames[p]
            win.frame:Show()
            self:SelectTab(win, i, true)
          end
        end
      end
    end
  end
  if not (pane and tf) then return self:Print(L.jumpNowhere) end
  local offset, shown = placeOf(tf.smf, r)
  if not offset and self.BackfillFrom then
    self:BackfillFrom(pane, tf, r.t)   -- older than the tab holds: show the tab from that line on
    offset, shown = placeOf(tf.smf, r)
  end
  if not offset then return end
  pcall(tf.smf.SetScrollOffset, tf.smf, math.max(0, offset - 3))
  shown.jumped = true
  self:Redraw(shown)
  C_Timer.After(4, function() shown.jumped = nil; P:Redraw(shown) end)
end
