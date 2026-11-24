-- Pick a layout, as the mock-up's first-run screen drew it: the screen dims, one question, and a card per layout with
-- a small picture of where its windows go (drawn from the layouts themselves, so the pictures can't drift from what
-- Pick applies). Click a card, then "Use" it. The first time, "Keep the game's chat for now" turns Parley off.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C

local ACCENT = UI.Hex(P.ACCENT_HEX)
local EDGE = { 231 / 255, 198 / 255, 108 / 255 }
local KEYS = { "one", "sides", "social", "group", "trader" }
local W, PAD, GAP = 860, 22, 12
local CARD_W = math.floor((W - 2 * PAD - (#KEYS - 1) * GAP) / #KEYS)
local MINI_H = 86

local dim, modal

-- the names a window's picture carries: its first tabs, and the panes beside the first
local function windowLabel(w)
  local parts = {}
  for _, key in ipairs(w.tabs) do
    if type(key) == "table" then
      local names = {}
      for _, k in ipairs(key) do names[#names + 1] = L.tab[k] or k end
      parts[#parts + 1] = table.concat(names, " + ")
    else
      parts[#parts + 1] = L.tab[key] or key
    end
    if #parts >= 2 then break end
  end
  return table.concat(parts, " \194\183 ")
end

local function drawMini(mini, key)
  local layout = P.LAYOUTS[key]
  local sw, sh = UIParent:GetWidth() or 1366, UIParent:GetHeight() or 768
  if sw < 100 then sw, sh = 1366, 768 end
  local mw = CARD_W - 20
  local scale = math.min(mw / sw, MINI_H / sh)
  local ox, oy = (mw - sw * scale) / 2, (MINI_H - sh * scale) / 2
  for i, w in ipairs(layout) do
    local x = w.right and (sw - w.w - w.x) or w.x
    local r = CreateFrame("Frame", nil, mini)
    r:SetSize(math.max(8, w.w * scale), math.max(6, w.h * scale))
    r:SetPoint("BOTTOMLEFT", mini, "BOTTOMLEFT", ox + x * scale, oy + w.y * scale)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(11 / 255, 9 / 255, 7 / 255, .85)
    local main = i == 1
    local c = main and ACCENT or EDGE
    local a = main and .7 or .25
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
        { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
      local t = r:CreateTexture(nil, "BORDER")
      t:SetColorTexture(c[1], c[2], c[3], a)
      t:SetPoint(side[1])
      t:SetPoint(side[2])
      if side[3] then t:SetHeight(1) else t:SetWidth(1) end
    end
    local label = UI.Text(r, "body", 9, C.muted)
    label:SetPoint("TOPLEFT", 3, -2)
    label:SetPoint("RIGHT", -2, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(windowLabel(w))
  end
end

local function choose(key)
  modal.selected = key
  for _, card in ipairs(modal.cards) do
    local on = card.key == key
    card.line:SetColor(on and ACCENT or C.lineStrong, 1)
    card.glow:SetShown(on)
  end
  local name = L.layout[key][1]
  modal.use.label:SetText(L.useLayout:format(name))
  modal.use:SetWidth(math.max(110, (modal.use.label:GetStringWidth() or 60) + 28))
end

local function build()
  dim = CreateFrame("Frame", "ParleyLayoutDim", UIParent)
  dim:SetAllPoints(UIParent)
  dim:SetFrameStrata("FULLSCREEN_DIALOG")
  dim:EnableMouse(true)
  dim.tex = dim:CreateTexture(nil, "BACKGROUND")
  dim.tex:SetAllPoints()
  dim.tex:SetColorTexture(0, 0, 0, .6)
  dim:Hide()

  modal = CreateFrame("Frame", "ParleyLayoutPicker", dim)
  modal:SetWidth(W)
  modal:SetPoint("CENTER", 0, 40)
  modal:SetFrameLevel(dim:GetFrameLevel() + 5)
  modal:EnableMouse(true)
  modal.bg = UI.Round(modal, "BACKGROUND", 0, 7)
  modal.bg:SetColor(C.stone2, 1)
  modal.line = UI.Round(modal, "BORDER", 0, 7, "line")
  modal.line:SetColor(C.frameGold, 1)
  modal.title = UI.Text(modal, "title", 22, C.gold)
  modal.title:SetPoint("TOPLEFT", PAD, -20)
  modal.title:SetText(L.layoutTitle)
  modal.sub = UI.Text(modal, "body", 14, C.muted)
  modal.sub:SetPoint("TOPLEFT", modal.title, "BOTTOMLEFT", 0, -5)
  modal.sub:SetText(L.layoutSub)

  modal.cards = {}
  local cardH = 0
  for i, key in ipairs(KEYS) do
    local card = CreateFrame("Button", nil, modal)
    card.key = key
    card:SetWidth(CARD_W)
    card.bg = UI.Round(card, "BACKGROUND", 0, 6)
    card.bg:SetColor({ 0, 0, 0 }, .3)
    card.glow = card:CreateTexture(nil, "BACKGROUND", nil, -1)
    card.glow:SetTexture(UI.TEX.glow)
    card.glow:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .35)
    card.glow:SetPoint("TOPLEFT", -14, 14)
    card.glow:SetPoint("BOTTOMRIGHT", 14, -14)
    card.glow:Hide()
    card.line = UI.Round(card, "BORDER", 0, 6, "line")
    card.line:SetColor(C.lineStrong, 1)
    local mini = CreateFrame("Frame", nil, card)
    mini:SetPoint("TOPLEFT", 10, -10)
    mini:SetSize(CARD_W - 20, MINI_H)
    mini.bg = mini:CreateTexture(nil, "BACKGROUND")
    mini.bg:SetAllPoints()
    UI.Gradient(mini.bg, { 43 / 255, 36 / 255, 28 / 255 }, { 19 / 255, 16 / 255, 12 / 255 }, 1, 1)
    drawMini(mini, key)
    card.name = UI.Text(card, "bold", 15, C.text)
    card.name:SetPoint("TOPLEFT", mini, "BOTTOMLEFT", 0, -8)
    card.name:SetText(L.layout[key][1])
    card.desc = UI.Text(card, "body", 12, C.muted)
    card.desc:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)
    card.desc:SetWidth(CARD_W - 20)
    card.desc:SetJustifyH("LEFT")
    card.desc:SetWordWrap(true)
    card.desc:SetText(L.layout[key][2])
    cardH = math.max(cardH, 10 + MINI_H + 8 + 18 + 3 + (card.desc:GetStringHeight() or 30) + 12)
    card:SetPoint("TOPLEFT", PAD + (i - 1) * (CARD_W + GAP), -76)
    card:SetScript("OnClick", function() choose(key) end)
    card:SetScript("OnDoubleClick", function() choose(key); P:ApplyLayout(key); dim:Hide() end)
    card:SetScript("OnEnter", function(self) if modal.selected ~= key then self.line:SetColor(UI.Mix(C.lineStrong, ACCENT, .5), 1) end end)
    card:SetScript("OnLeave", function(self) if modal.selected ~= key then self.line:SetColor(C.lineStrong, 1) end end)
    modal.cards[i] = card
  end
  for _, card in ipairs(modal.cards) do card:SetHeight(cardH) end

  modal.use = UI.Button(modal, "", "primary", function()
    if modal.selected then P:ApplyLayout(modal.selected) end
    dim:Hide()
  end)
  P.Own(modal.use)
  modal.use:SetHeight(28)
  modal.use:SetPoint("BOTTOMRIGHT", -PAD, 18)
  modal.keep = UI.Button(modal, L.keepGameChat, "quiet", function()
    P.db.takeover = false
    ReloadUI()
  end)
  P.Own(modal.keep)
  modal.keep:SetHeight(28)
  modal.keep:SetWidth((modal.keep.label:GetStringWidth() or 160) + 28)
  modal.keep:SetPoint("RIGHT", modal.use, "LEFT", -8, 0)
  modal.cancel = P.Own(UI.Button(modal, L.cancel, "quiet", function() dim:Hide() end))
  modal.cancel:SetSize(90, 28)
  modal.cancel:SetPoint("RIGHT", modal.use, "LEFT", -8, 0)
  modal.hint = UI.Text(modal, "body", 12, C.faint)
  modal.hint:SetPoint("BOTTOMLEFT", PAD, 26)
  modal.hint:SetText(L.layoutLater)
  modal:SetHeight(76 + cardH + 18 + 28 + 18)
  tinsert(UISpecialFrames, "ParleyLayoutDim")
end

function P:ShowLayoutPicker()
  if not dim then build() end
  local first = self.firstRun and true or false
  modal.keep:SetShown(first)
  modal.cancel:SetShown(not first)
  choose(self.LAYOUTS[self.db.layout or ""] and self.db.layout or "one")
  dim:Show()
end
