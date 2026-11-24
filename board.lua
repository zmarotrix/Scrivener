-- The Trade & LFG board, as the mock-up drew it: a pane with channels in it can switch from the stream of lines to a
-- board of cards, one per person, their latest advert replacing the old one, with how often it was posted. Cards go
-- after 15 minutes. Each card: what kind of advert (LFM, LF, WTS, WTB), who, how long ago, the advert, then the dungeon
-- (from NorgannonDB, matched on the short forms players type, which are made from the names), the roles asked for,
-- the item's auction price (from Fortune, when it's installed) and a Whisper button. Chips filter by kind and dungeon,
-- and a box filters by words.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C
local Hidden = P.Hidden

local ACCENT = UI.Hex(P.ACCENT_HEX)
local BOARD_FOR = 900                   -- seconds a card stays
local CARD_H, CARD_GAP = 84, 8
local KIND_COLOR = { lfm = UI.Hex("ffb36b"), lf = UI.Hex("8fd0ff"), wts = UI.Hex("8fe08f"), wtb = UI.Hex("e7c66c") }
local KIND_ORDER = { "all", "lfm", "lf", "wts", "wtb" }
local MAX_DUNGEON_CHIPS = 4

-------------------------------------------------------------------------------------------
-- Reading an advert
-------------------------------------------------------------------------------------------

local function plainLower(text)
  return (text:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):lower())
end

local ROLE_WORDS = { tank = "tank", tanks = "tank", heal = "heal", heals = "heal", healer = "heal", healers = "heal",
  healz = "heal", dps = "dps", dd = "dps" }

---"lfm", "lf", "wts", "wtb" or nil for a line in lower case.
function P.AdvertKind(low)
  if low:find("%f[%w]lf%d*m%f[%W]") then return "lfm" end
  -- only the trade words: "anyone selling thorium?" is someone asking, not an advert
  if low:find("%f[%w]wts%f[%W]") then return "wts" end
  if low:find("%f[%w]wtb%f[%W]") then return "wtb" end
  if low:find("%f[%w]lfg%f[%W]") then return "lf" end
  local after = low:match("%f[%w]lf%s+(%a+)")
  if after then return ROLE_WORDS[after] and "lfm" or "lf" end
  return nil
end

local function rolesOf(low)
  local seen, out = {}, {}
  for word in low:gmatch("%a+") do
    local role = ROLE_WORDS[word]
    if role and not seen[role] then seen[role] = true; out[#out + 1] = role end
  end
  table.sort(out, function(a, b) return a > b end)   -- tank, heal, dps
  return out
end

-------------------------------------------------------------------------------------------
-- Dungeons: NorgannonDB's names, and the short forms made from them
-------------------------------------------------------------------------------------------

-- words a player types in adverts that must never read as a dungeon
local NOT_DUNGEON = {}
for word in ([[lfm lfg wts wtb need tank tanks heal heals healer dps and the for any run runs more last spot spots quest
  quests pst inv invite summon plz pls have with your you can will just each stack stacks cheap price gold also then lvl
  level group full one two all boost farm fast chill first kill boss elite whisper]]):gmatch("%a+") do
  NOT_DUNGEON[word] = true
end

local index, names   -- [token] = { tier, list = { name, ... } }; names = { lower name = name }

local VOWEL = { a = true, e = true, i = true, o = true, u = true, y = true }
---Whether letter j of a word could start the second half of a joined word: a consonant after a consonant (or after a
---silent e), not a doubled letter, with a vowel after it. Black|rock and Rage|fire, but not Ba|rrow.
function P.SyllableStart(w, j)
  local c, prev, before, nxt = w:sub(j, j), w:sub(j - 1, j - 1), w:sub(j - 2, j - 2), w:sub(j + 1, j + 1)
  if VOWEL[c] or c == prev or not VOWEL[nxt] then return false end
  if not VOWEL[prev] then return true end
  return prev == "e" and before ~= "" and not VOWEL[before]
end

local function wordsOf(name)
  local out = {}
  for w in name:lower():gsub("'s%f[%A]", ""):gmatch("%a+") do
    if w ~= "the" and w ~= "of" then out[#out + 1] = w end
  end
  return out
end

local function add(token, tier, name)
  if #token < 2 or NOT_DUNGEON[token] then return end
  local e = index[token]
  if not e or tier < e.tier then
    index[token] = { tier = tier, list = { name } }
  elseif tier == e.tier then
    for _, n in ipairs(e.list) do if n == name then return end end
    table.insert(e.list, name)
  end
end

local function buildIndex()
  index, names = {}, {}
  local db = P.Core.DB
  if not (db and db.InstanceKeys) then return end
  local ok, keys = pcall(db.InstanceKeys, db)
  if not ok or type(keys) ~= "table" then return end
  for _, key in ipairs(keys) do
    local full = db:InstanceName(key)
    if full == key then full = nil end   -- no name the client or NorgannonDB knows, only its key
    local name = type(full) == "string" and (full:match("^(.-):") or full)
    if name and name ~= "" and not names[name:lower()] then
      names[name:lower()] = name
      local ws = wordsOf(name)
      if #ws >= 2 then
        -- tier 1: the capitals (Dire Maul gives DM); tier 2: with the start of the second half of a joined word as
        -- well (Black|rock Depths gives BRD, Rage|fire Chasm gives RFC)
        local initials = ""
        for _, w in ipairs(ws) do initials = initials .. w:sub(1, 1) end
        add(initials, 1, name)
        local function walk(i, acc, extra)
          if i > #ws then
            if extra > 0 and #acc >= 3 then add(acc, 2, name) end
            return
          end
          local w = ws[i]
          walk(i + 1, acc .. w:sub(1, 1), extra)
          if extra < 2 then
            for j = 3, #w - 1 do
              if P.SyllableStart(w, j) then walk(i + 1, acc .. w:sub(1, 1) .. w:sub(j, j), extra + 1) end
            end
          end
        end
        walk(1, "", 0)
      end
      -- tier 3: the start of a name's first word (Strat, Scholo, Mara; Scarlet, Molten for longer names)
      local first = ws[1]
      if first then
        for n = (#ws == 1 and 4 or 5), #first do add(first:sub(1, n), 3, name) end
      end
    end
  end
end

---The dungeon an advert names: its name, or "A or B?" when the short form fits more than one; and the short form typed.
function P:AdvertDungeon(low)
  if not index then buildIndex() end
  -- the whole name, written out
  for lowName, name in pairs(names) do
    local bare = lowName:gsub("^the ", "")
    if low:find(bare, 1, true) then return name, nil end
  end
  local best
  for token in low:gmatch("%a+") do
    local e = index[token]
    if e and (not best or e.tier < best.tier) then best = { tier = e.tier, list = e.list, token = token } end
  end
  if not best then return nil end
  local shortForm = best.tier == 3 and (best.token:sub(1, 1):upper() .. best.token:sub(2)) or best.token:upper()
  if #best.list == 1 then return best.list[1], shortForm end
  local second = best.list[2]:gsub("^The ", "the ")
  return L.board.either:format(best.list[1], second), shortForm, true
end

-------------------------------------------------------------------------------------------
-- The adverts a pane's board shows
-------------------------------------------------------------------------------------------

local function priceOf(text, kind)
  local fortune = rawget(_G, "Fortune")
  local prices = type(fortune) == "table" and fortune.Prices
  if not (prices and prices.Of and (kind == "wts" or kind == "wtb")) then return nil end
  local link = text:match("|c%x+|Hitem:.-|h.-|h|r")
  if not link then return nil end
  local ok, info = pcall(prices.Of, prices, link)
  if not ok or type(info) ~= "table" or not info.market or info.market <= 0 then return nil end
  return L.board.price:format(P.Money(info.market))
end

---{ ad, ... } newest first: one per person, their latest advert, with how often they posted.
function P:BoardAds(pane)
  local now = time()
  local byWho, list = {}, {}
  for _, r in ipairs(self.records) do
    if not r.held and (r.t or 0) >= now - BOARD_FOR and type(r.who) == "string" and type(r.text) == "string"
        and not Hidden(r.text) and P.TabWants(pane, r) then
      -- each line is read once: what kind of advert, the dungeon, the roles (kept on the line)
      local info = r.ad
      if info == nil then
        local low = plainLower(r.text)
        local kind = P.AdvertKind(low)
        info = false
        if kind then
          info = { kind = kind, low = low, roles = {} }
          if kind == "lfm" or kind == "lf" then
            info.dungeon, info.short, info.unsure = self:AdvertDungeon(low)
            info.roles = rolesOf(low)
          end
        end
        r.ad = info
      end
      if info then
        local ad = byWho[r.who]
        if not ad then
          ad = { who = r.who, posts = 0, first = r.t0 or r.t, last = 0 }
          byWho[r.who] = ad
          list[#list + 1] = ad
        end
        ad.posts = ad.posts + (r.count or 1)
        ad.first = math.min(ad.first, r.t0 or r.t)
        if r.t >= ad.last then ad.last, ad.rec, ad.info = r.t, r, info end
      end
    end
  end
  for _, ad in ipairs(list) do
    local info = ad.info
    ad.guid, ad.kind, ad.low = ad.rec.guid, info.kind, info.low
    ad.dungeon, ad.short, ad.unsure, ad.roles = info.dungeon, info.short, info.unsure, info.roles
    if info.price == nil then info.price = priceOf(ad.rec.text, ad.kind) or false end
    ad.price = info.price or nil
  end
  table.sort(list, function(a, b) return a.last > b.last end)
  return list
end

-------------------------------------------------------------------------------------------
-- Cards
-------------------------------------------------------------------------------------------

local function pill(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetHeight(16)
  p.bg = UI.Round(p, "BACKGROUND", 0, 8)
  p.line = UI.Round(p, "BORDER", 0, 8, "line")
  p.text = UI.Text(p, "body", 11, C.text)
  p.text:SetPoint("CENTER", 0, 0)
  function p:Style(style, text)
    self.text:SetText(text)
    self:SetWidth((self.text:GetStringWidth() or 30) + 14)
    local t, fill, edge, fa, ea = C.text, { 1, 1, 1 }, { 1, 1, 1 }, .06, .12
    if style == "role" then t, fill, edge, fa, ea = C.muted, { 0, 0, 0 }, C.lineStrong, 0, 1
    elseif style == "price" then t, fill, edge, fa, ea = UI.Hex("8fd6f2"), UI.Hex("1fa3d6"), UI.Hex("1fa3d6"), .12, .5
    elseif style == "unsure" then t, fill, edge, fa, ea = C.warn, { 0, 0, 0 }, C.warn, 0, .7
    elseif style == "dungeon" then t = UI.Hex("e9dfc6") end
    self.text:SetTextColor(t[1], t[2], t[3])
    self.bg:SetColor(fill, fa)
    self.line:SetColor(edge, ea)
  end
  return p
end

local function ago(seconds)
  if seconds < 60 then return L.board.now end
  return L.ago.m:format(math.floor(seconds / 60))
end

local function newCard(parent)
  local c = CreateFrame("Button", nil, parent)
  c:SetHeight(CARD_H)
  c.bg = UI.Round(c, "BACKGROUND", 0, 6)
  c.bg:SetColor({ 0, 0, 0 }, .32)
  c.line = UI.Round(c, "BORDER", 0, 6, "line")
  c.line:SetColor({ 1, 1, 1 }, .08)
  c.kind = CreateFrame("Frame", nil, c)
  c.kind:SetHeight(15)
  c.kind:SetPoint("TOPLEFT", 10, -8)
  c.kind.line = UI.Round(c.kind, "BORDER", 0, 3, "line")
  c.kind.text = UI.Text(c.kind, "bold", 10, C.text)
  c.kind.text:SetPoint("CENTER", 0, 0)
  c.name = UI.Text(c, "body", 13, C.text)
  c.name:SetPoint("LEFT", c.kind, "RIGHT", 7, 0)
  c.age = UI.Text(c, "body", 11, C.faint)
  c.age:SetPoint("TOPRIGHT", -10, -9)
  c.text = UI.Text(c, "body", 13, { 232 / 255, 226 / 255, 208 / 255 })
  c.text:SetPoint("TOPLEFT", 10, -28)
  c.text:SetPoint("RIGHT", -10, 0)
  c.text:SetJustifyH("LEFT")
  c.text:SetWordWrap(true)
  pcall(c.text.SetMaxLines, c.text, 2)
  c.pills = {}
  c.rep = UI.Text(c, "body", 11, C.faint)
  c.whisper = P.Own(UI.Button(c, L.board.whisper, "quiet", function()
    local who = c.ad and c.ad.who
    if who then ChatFrameUtil.SendTell(P.Core.Names:Address(who) or P.Core.Names.Full(who) or who) end
  end))
  c.whisper:SetSize(64, 18)
  c.whisper:SetPoint("BOTTOMRIGHT", -8, 7)
  c:SetScript("OnEnter", function(self)
    local link = self.ad and self.ad.rec.text:match("|H(item:[^|]+)|h")
    if not link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() end
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return c
end

local function fillCard(c, ad)
  c.ad = ad
  local col = KIND_COLOR[ad.kind]
  c.kind.text:SetText(L.board.kinds[ad.kind])
  c.kind.text:SetTextColor(col[1], col[2], col[3])
  c.kind.line:SetColor(col, .5)
  c.kind:SetWidth((c.kind.text:GetStringWidth() or 20) + 12)
  local shown = P.ShowName(P.Core.Names.Full(ad.who) or ad.who)
  local hex = P.ClassHex and P.ClassHex(ad.guid)
  c.name:SetText(hex and ("|c" .. hex .. shown .. "|r") or shown)
  c.age:SetText(ago(time() - ad.last))
  c.text:SetText(ad.rec.text)
  local items = {}
  if ad.dungeon then items[#items + 1] = { ad.unsure and "unsure" or "dungeon", ad.dungeon } end
  for _, role in ipairs(ad.roles or {}) do items[#items + 1] = { "role", L.board.roles[role] } end
  if ad.price then items[#items + 1] = { "price", ad.price } end
  local x = 10
  for i, item in ipairs(items) do
    local p = c.pills[i] or pill(c)
    c.pills[i] = p
    p:Style(item[1], item[2])
    p:ClearAllPoints()
    p:SetPoint("BOTTOMLEFT", x, 8)
    p:Show()
    x = x + p:GetWidth() + 5
  end
  for i = #items + 1, #c.pills do c.pills[i]:Hide() end
  c.rep:ClearAllPoints()
  c.rep:SetPoint("BOTTOMLEFT", x + 2, 10)
  if ad.posts > 1 then
    c.rep:SetText(L.board.posted:format(ad.posts, math.max(1, math.floor((ad.last - ad.first) / 60 + .5))))
  else
    c.rep:SetText("")
  end
end

-------------------------------------------------------------------------------------------
-- The board view in a pane
-------------------------------------------------------------------------------------------

local function wantsBoard(pane)
  if pane.special then return false end
  if pane.all then return true end
  for key in pairs(pane.kinds or {}) do if P.IsChannel(key) then return true end end
  return false
end
P.CanBoard = wantsBoard

local function buildBoard(pane, tf)
  local b = CreateFrame("Frame", nil, tf.frame)
  b:SetPoint("TOPLEFT", tf.head, "BOTTOMLEFT", 0, 0)
  b:SetPoint("BOTTOMRIGHT", tf.frame, "BOTTOMRIGHT", 0, 2)
  b.chips = {}
  for _, key in ipairs(KIND_ORDER) do
    local chip = UI.Chip(b, "", nil, function(on)
      if not on then b.chips[key]:SetOn(true, true); return end
      for k, x in pairs(b.chips) do if k ~= key then x:SetOn(false, true) end end
      pane.boardKind = key ~= "all" and key or nil
      P:RefreshBoard(pane, tf)
    end)
    if chip.ApplyAccent then chip:ApplyAccent(ACCENT) end
    b.chips[key] = chip
  end
  b.dzLabel = UI.Text(b, "body", 12, C.faint)
  b.dzLabel:SetText(L.board.dungeon)
  b.dzChips = {}
  b.filter = UI.Search(b, L.board.filter, function(text)
    b.words = {}
    for w in (text or ""):lower():gmatch("[^%s,]+") do b.words[#b.words + 1] = w end
    P:RefreshBoard(pane, tf)
  end)
  b.filter:SetSize(150, 22)
  if b.filter.ApplyAccent then b.filter:ApplyAccent(ACCENT) end
  b.rule = P.Hairline(b)
  b.rule:SetHeight(1)
  b.scroll = P.Own(UI.ScrollArea(b))
  b.cards = {}
  b.none = UI.Text(b, "body", 13, C.faint)
  b.none:SetText(L.board.none)
  b.words = {}
  tf.board = b
  return b
end

local function chipText(chip, text)
  chip.label:SetText(text)
  chip:SetWidth(math.floor((chip.label:GetStringWidth() or 30) + 20))
end

local function passes(ad, kind, dz, words)
  if kind and ad.kind ~= kind then return false end
  if dz and ad.short ~= dz then return false end
  for _, w in ipairs(words) do
    local hay = ad.low .. " " .. (ad.dungeon or ""):lower()
    for _, role in ipairs(ad.roles) do hay = hay .. " " .. L.board.roles[role]:lower() end
    if not hay:find(w, 1, true) then return false end
  end
  return true
end

---Draw a pane's board again: the chips' counts, the dungeons seen, the cards that pass the filters.
function P:RefreshBoard(pane, tf)
  local b = tf.board
  if not (b and b:IsShown()) then return end
  local ads = self:BoardAds(pane)
  local counts = { all = #ads }
  local dz, dzList = {}, {}
  for _, ad in ipairs(ads) do
    counts[ad.kind] = (counts[ad.kind] or 0) + 1
    if ad.short and not ad.unsure then
      if not dz[ad.short] then dz[ad.short] = 0; dzList[#dzList + 1] = ad.short end
      dz[ad.short] = dz[ad.short] + 1
    end
  end
  table.sort(dzList, function(a, b2) return dz[a] > dz[b2] end)
  for key, chip in pairs(b.chips) do
    chipText(chip, L.board.kindCount:format(key == "all" and L.board.all or L.board.kinds[key], counts[key] or 0))
    chip:SetOn((pane.boardKind or "all") == key, true)
  end
  -- the dungeon chips: the ones adverts name most
  for i = 1, MAX_DUNGEON_CHIPS do
    local short = dzList[i]
    local chip = b.dzChips[i]
    if short and not chip then
      chip = UI.Chip(b, "", nil, function(on)
        pane.boardDungeon = on and chip.short or nil
        for _, other in ipairs(b.dzChips) do if other ~= chip then other:SetOn(false, true) end end
        P:RefreshBoard(pane, tf)
      end)
      if chip.ApplyAccent then chip:ApplyAccent(ACCENT) end
      b.dzChips[i] = chip
    end
    if chip then
      chip.short = short
      if short then chipText(chip, short) end
      chip:SetShown(short ~= nil)
      chip:SetOn(short ~= nil and pane.boardDungeon == short, true)
    end
  end
  if pane.boardDungeon and not dz[pane.boardDungeon] then pane.boardDungeon = nil end
  -- the bar: kind chips, then the dungeons, then the filter box; it wraps when the pane is narrow
  local width = tf.frame:GetWidth() or 400
  if width < 100 then width = 400 end
  local x, y = 10, -7
  local function place(frame, w)
    if x + w > width - 10 and x > 10 then x, y = 10, y - 26 end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", b, "TOPLEFT", x, y)
    x = x + w + 6
  end
  for _, key in ipairs(KIND_ORDER) do place(b.chips[key], b.chips[key]:GetWidth()) end
  local anyDz = dzList[1] ~= nil
  b.dzLabel:SetShown(anyDz)
  if anyDz then
    place(b.dzLabel, (b.dzLabel:GetStringWidth() or 50))
    b.dzLabel:ClearAllPoints()
    b.dzLabel:SetPoint("TOPLEFT", b, "TOPLEFT", x - (b.dzLabel:GetStringWidth() or 50) - 6, y - 4)
    for _, chip in ipairs(b.dzChips) do if chip:IsShown() then place(chip, chip:GetWidth()) end end
  end
  if x + 150 > width - 10 then x, y = 10, y - 26 end
  b.filter:ClearAllPoints()
  b.filter:SetPoint("TOPRIGHT", b, "TOPRIGHT", -10, y + 1)
  local barH = -y + 26
  b.rule:ClearAllPoints()
  b.rule:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -barH)
  b.rule:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -barH)
  b.scroll:ClearAllPoints()
  b.scroll:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -barH - 8)
  b.scroll:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -10, 4)
  -- the cards, two across when there's room
  local cols = width >= 440 and 2 or 1
  local cardW = math.floor((width - 20 - (cols - 1) * CARD_GAP) / cols)
  local shown = 0
  for _, ad in ipairs(ads) do
    if passes(ad, pane.boardKind, pane.boardDungeon, b.words) then
      shown = shown + 1
      local c = b.cards[shown] or newCard(b.scroll.content)
      b.cards[shown] = c
      fillCard(c, ad)
      local col, row = (shown - 1) % cols, math.floor((shown - 1) / cols)
      c:SetWidth(cardW)
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", b.scroll.content, "TOPLEFT", col * (cardW + CARD_GAP), -row * (CARD_H + CARD_GAP))
      c:Show()
    end
  end
  for i = shown + 1, #b.cards do b.cards[i]:Hide() end
  b.scroll.content:SetHeight(math.max(1, math.ceil(shown / cols) * (CARD_H + CARD_GAP)))
  b.none:ClearAllPoints()
  b.none:SetPoint("TOP", b.scroll, "TOP", 0, -20)
  b.none:SetShown(shown == 0)
end

---Stream or board: the switch in a pane's header, and which of the two shows.
function P:LayoutBoard(pane, tf)
  local can = wantsBoard(pane)
  if not can then pane.board = nil end
  local on = pane.board and true or false
  if on and not tf.board then buildBoard(pane, tf) end
  if tf.board then tf.board:SetShown(on) end
  tf.smf:SetShown(not on and not tf.hosting)   -- a pane holding the game's combat log shows that instead
  if tf.head.view then tf.head.view:Select(on and "board" or "stream", true) end
  -- drawn at once when it opens; a resize (a divider being dragged) redraws it a moment later, once
  if on and not tf.boardOn then self:RefreshBoard(pane, tf) elseif on then self:BoardDirty(pane, tf) end
  tf.boardOn = on
end

function P:BoardSwitch(pane, tf)
  local head = tf.head
  if not wantsBoard(pane) then
    if head.view then head.view:Hide() end
    return
  end
  if not head.view then
    head.view = UI.Segmented(head, { { key = "stream", label = L.board.stream }, { key = "board", label = L.board.board } },
      function(key)
        pane.board = key == "board" or nil
        P:LayoutBoard(pane, tf)
      end, 16)
    if head.view.ApplyAccent then head.view:ApplyAccent(ACCENT) end
  end
  head.view:ClearAllPoints()
  head.view:SetPoint("RIGHT", head, "RIGHT", head.close:IsShown() and -24 or -6, 0)
  head.view:Select(pane.board and "board" or "stream", true)
  head.view:Show()
  head.list:ClearAllPoints()
  head.list:SetPoint("LEFT", head.name, "RIGHT", 7, 0)
  head.list:SetPoint("RIGHT", head.view, "LEFT", -8, 0)
end

-- a new advert redraws the board a moment later (once, however many arrive together)
local due = {}
function P:BoardDirty(pane, tf)
  if not (tf.board and tf.board:IsVisible()) or due[tf] then return end
  due[tf] = true
  C_Timer.After(.5, function() due[tf] = nil; P:RefreshBoard(pane, tf) end)
end

-- cards age and go: every half minute the boards in sight are drawn again
local clock = CreateFrame("Frame")
local since = 0
clock:SetScript("OnUpdate", function(_, dt)
  since = since + dt
  if since < 30 then return end
  since = 0
  for pane, tf in pairs(P.tabFrames) do
    if tf.board and tf.board:IsVisible() then P:RefreshBoard(pane, tf) end
  end
end)
