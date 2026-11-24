-- The New tab builder, as the mock-up drew it: preset cards (each with its chats' colours, a name and what's in it),
-- then "Your own mix" as a chip for every chat and channel, "Only lines that mention me", Tab or New window, and
-- Cancel / Add tab. Shift-clicking a card opens it as a window. It opens above the + on the tab bar.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C

local W, PAD, CARD_H, GAP = 474, 14, 58, 8
local TOP = 52       -- where the cards start, under the title's line
local CARDS = { "guild", "group", "whispers", "tradeplus", "loot", "system", "foryou", "addons", "combat" }
local ACCENT = UI.Hex(P.ACCENT_HEX)

local pop

local function card(parent, key, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize((W - 2 * PAD - 2 * GAP) / 3, CARD_H)
  P.Card(b)
  local sample = P.TABS[key]()
  local x = 9
  local keys = {}
  for k in pairs(sample.kinds or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  if sample.special == "foryou" then keys = { "FORYOU" } end
  for i = 1, math.min(3, #keys) do
    local dot = b:CreateTexture(nil, "ARTWORK")
    dot:SetSize(i == 1 and 9 or 3, 3)
    dot:SetPoint("TOPLEFT", x, -8)
    local r, g, bl = P.KindColor(keys[i])
    dot:SetColorTexture(r, g, bl, 1)
    x = x + (i == 1 and 12 or 6)
  end
  b.title = UI.Text(b, "title", 14, C.text)
  b.title:SetPoint("TOPLEFT", 9, -16)
  b.title:SetText(sample.name)
  b.desc = UI.Text(b, "body", 11, C.muted)
  b.desc:SetPoint("TOPLEFT", b.title, "BOTTOMLEFT", 0, -3)
  b.desc:SetPoint("RIGHT", -8, 0)
  b.desc:SetText(L.cards[key] or "")
  b:SetScript("OnEnter", function() b:Look(true) end)
  b:SetScript("OnLeave", function() b:Look(false) end)
  b:SetScript("OnClick", function() onClick(key) end)
  return b
end

local function build()
  pop = CreateFrame("Frame", "ParleyNewTab", UIParent)
  pop:SetFrameStrata("DIALOG")
  pop:SetWidth(W)
  pop:EnableMouse(true)
  pop:SetClampedToScreen(true)
  P.Panel(pop)
  tinsert(UISpecialFrames, "ParleyNewTab")
  P.PanelTitle(pop, L.newTab, 18, PAD, -11, TOP - 12)
  pop.close = UI.CloseButton(pop, function() pop:Hide() end)
  pop.close:SetPoint("TOPRIGHT", -9, -9)

  local function addPreset(key)
    local tab = P.TABS[key]()
    P:AddTab(pop.win, tab, IsShiftKeyDown() or pop.target == "window")
    pop:Hide()
  end
  pop.cards = {}
  for i, key in ipairs(CARDS) do
    local c = card(pop, key, addPreset)
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    c:SetPoint("TOPLEFT", PAD + col * (c:GetWidth() + GAP), -TOP - row * (CARD_H + GAP))
    pop.cards[i] = c
  end
  local rows = math.ceil(#CARDS / 3)
  pop.mixY = -TOP - rows * (CARD_H + GAP) - 6

  pop.mixLabel = UI.Text(pop, "bold", 13, C.text)
  pop.mixLabel:SetPoint("TOPLEFT", PAD, pop.mixY)
  pop.mixLabel:SetText(L.yourOwnMix)
  pop.count = UI.Text(pop, "body", 12, C.faint)
  pop.count:SetPoint("TOPRIGHT", -PAD, pop.mixY)
  pop.chips = {}

  pop.mention = P.Own(UI.Toggle(pop, function(on) pop.mentions = on end))
  pop.mentionLabel = UI.Text(pop, "body", 13, C.text)
  pop.mentionLabel:SetText(L.mentionsOnly)
  pop.where = P.Own(UI.Segmented(pop, { { key = "tab", label = L.asTab }, { key = "window", label = L.asWindow } },
    function(key) pop.target = key end, 22))

  pop.hint = UI.Text(pop, "body", 12, C.faint)
  pop.hint:SetText(L.shiftPreset)
  pop.add = UI.Button(pop, L.addTab, "primary", function()
    local chosen, n, first = {}, 0, nil
    for key, on in pairs(pop.chosen) do if on then chosen[key] = true; n = n + 1; first = first or key end end
    if n == 0 then return end
    local tab = { name = n == 1 and P.KindLabel(first) or L.tab.mix, kinds = chosen, mentionsOnly = pop.mentions or nil }
    P:AddTab(pop.win, tab, pop.target == "window")
    pop:Hide()
  end)
  P.Own(pop.add)
  pop.add:SetSize(84, 26)
  pop.cancel = P.Own(UI.Button(pop, L.cancel, "quiet", function() pop:Hide() end))
  pop.cancel:SetSize(74, 26)
  pop:Hide()   -- so its first opening fades in too
end

-- the chips flow in rows across the builder; the builder grows to fit them
local function layoutChips()
  for _, chip in ipairs(pop.chips) do chip:Hide() end
  local x, y = PAD, pop.mixY - 22
  local right = W - PAD
  local kinds = P:PickerKinds()
  for i, key in ipairs(kinds) do
    local chip = pop.chips[i]
    local r, g, b = P.KindColor(key)
    if not chip or chip.key ~= key then
      if chip then chip:Hide() end
      chip = UI.Chip(pop, P.KindLabel(key), { r, g, b, 1 }, function(on)
        pop.chosen[chip.key] = on or nil
        local n = 0
        for _ in pairs(pop.chosen) do n = n + 1 end
        pop.count:SetText(n > 0 and L.chosen:format(n) or "")
      end)
      if chip.ApplyAccent then chip:ApplyAccent(ACCENT) end
      chip.key = key
      pop.chips[i] = chip
    end
    chip:SetOn(false, true)
    local w = chip:GetWidth()
    if x + w > right then x, y = PAD, y - 26 end
    chip:ClearAllPoints()
    chip:SetPoint("TOPLEFT", x, y)
    chip:Show()
    x = x + w + 6
  end
  y = y - 34
  pop.mention:ClearAllPoints()
  pop.mention:SetPoint("TOPLEFT", PAD, y)
  pop.mentionLabel:ClearAllPoints()
  pop.mentionLabel:SetPoint("LEFT", pop.mention, "RIGHT", 8, 0)
  pop.where:ClearAllPoints()
  pop.where:SetPoint("TOPRIGHT", -PAD, y + 2)
  y = y - 36
  pop.hint:ClearAllPoints()
  pop.hint:SetPoint("TOPLEFT", PAD, y - 6)
  pop.add:ClearAllPoints()
  pop.add:SetPoint("TOPRIGHT", -PAD, y)
  pop.cancel:ClearAllPoints()
  pop.cancel:SetPoint("RIGHT", pop.add, "LEFT", -8, 0)
  pop:SetHeight(-y + 26 + PAD)
end

---Open the builder above a window's +.
function P:OpenNewTab(win, owner)
  if not pop then build() end
  if pop:IsShown() and pop.win == win then pop:Hide(); return end
  pop.win = win
  pop.chosen, pop.mentions, pop.target = {}, false, "tab"
  pop.count:SetText("")
  pop.mention:SetOn(false, true)
  if pop.where.Select then pop.where:Select("tab", true) end
  layoutChips()
  pop:ClearAllPoints()
  pop:SetPoint("BOTTOMLEFT", owner or win.frame, "TOPLEFT", -40, 10)
  pop:Show()
end
