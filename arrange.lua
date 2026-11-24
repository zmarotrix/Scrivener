-- Arranging windows, as the mock-up's Arrange screen drew it. Moving a window (by its tab bar, or anywhere on it while
-- arranging) snaps it to the screen's edges and to the other windows' edges, with a dashed guide along the edge it
-- snapped to. Arrange mode outlines every window, puts a handle on each corner for resizing, and shows a bar at the
-- top of the screen: Snap on or off, Lock all, Done.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local UI = P.UI
local C = UI.C

local ACCENT = UI.Hex(P.ACCENT_HEX)
local SNAP = 12     -- how close an edge has to come before it snaps
local GAP = 8       -- windows that snap side by side keep this much room between them

-------------------------------------------------------------------------------------------
-- Guides: a dashed line across the screen where a window's edge snapped
-------------------------------------------------------------------------------------------

local guides
local function guideLines()
  if guides then return guides end
  guides = {}
  for _, axis in ipairs({ "x", "y" }) do
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetTexture(P.MEDIA .. (axis == "x" and "dash-v" or "dash-h"), "REPEAT", "REPEAT")
    if axis == "x" then t:SetVertTile(true) else t:SetHorizTile(true) end
    t:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], .85)
    f:Hide()
    guides[axis] = f
  end
  return guides
end

local function showGuide(axis, at)
  local g = guideLines()[axis]
  if not at then g:Hide(); return end
  g:ClearAllPoints()
  if axis == "x" then
    g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", at, 0)
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", at, 0)
    g:SetWidth(1)
  else
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, at)
    g:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, at)
    g:SetHeight(1)
  end
  g:Show()
end

-------------------------------------------------------------------------------------------
-- Snapping
-------------------------------------------------------------------------------------------

---Where a window at (x, y) (its bottom left corner) snaps to, and the guide for each axis (nil when it didn't).
function P:Snap(win, x, y)
  local w, h = win.frame:GetWidth() or 0, win.frame:GetHeight() or 0
  local sw, sh = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
  -- { where the window's left (or bottom) goes, where the guide is drawn }
  local xs = { { 0, 0 }, { sw - w, sw } }
  local ys = { { 0, 0 }, { sh - h, sh } }
  for _, other in ipairs(self.windows) do
    if other ~= win and other.frame:IsShown() then
      local f = other.frame
      local l, r, b, t = f:GetLeft() or 0, f:GetRight() or 0, f:GetBottom() or 0, f:GetTop() or 0
      xs[#xs + 1] = { l, l }              -- left edges in line
      xs[#xs + 1] = { r - w, r }          -- right edges in line
      xs[#xs + 1] = { r + GAP, r + GAP }  -- beside it, on its right
      xs[#xs + 1] = { l - w - GAP, l - GAP }
      ys[#ys + 1] = { b, b }              -- bottoms in line
      ys[#ys + 1] = { t - h, t }          -- tops in line
      ys[#ys + 1] = { t + GAP, t + GAP }  -- above it
      ys[#ys + 1] = { b - h - GAP, b - GAP }
    end
  end
  local function best(list, v)
    local pick, dist = nil, SNAP + 1
    for _, c in ipairs(list) do
      local d = math.abs(c[1] - v)
      if d < dist then pick, dist = c, d end
    end
    return pick
  end
  local bx, by = best(xs, x), best(ys, y)
  return bx and bx[1] or x, by and by[1] or y, bx and bx[2], by and by[2]
end

-------------------------------------------------------------------------------------------
-- Moving a window by hand
-------------------------------------------------------------------------------------------

local mover = CreateFrame("Frame")
mover:Hide()
mover:SetScript("OnUpdate", function(self)
  local win = self.win
  if not win then return self:Hide() end
  local f = win.frame
  local s = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local x, y = cx / s - self.dx, cy / s - self.dy
  local gx, gy
  if P.db.snap ~= false then x, y, gx, gy = P:Snap(win, x, y) end
  f:ClearAllPoints()
  f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
  showGuide("x", gx)
  showGuide("y", gy)
end)

function P:BeginMove(win)
  local f = win.frame
  local s = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  mover.win = win
  mover.dx, mover.dy = cx / s - (f:GetLeft() or 0), cy / s - (f:GetBottom() or 0)
  mover:Show()
end

function P:EndMove(win)
  if mover.win ~= win then return end
  mover:Hide()
  mover.win = nil
  showGuide("x", nil)
  showGuide("y", nil)
  P.SavePosition(win)
end

-------------------------------------------------------------------------------------------
-- Arrange mode
-------------------------------------------------------------------------------------------

local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

-- the outline, the corner handles and a sheet over the lines to drag the window by
local function decor(win)
  if win.arrange then return win.arrange end
  local f = win.frame
  local d = CreateFrame("Frame", nil, f)
  d:SetPoint("TOPLEFT", -3, 3)
  d:SetPoint("BOTTOMRIGHT", 3, -3)
  d:SetFrameLevel(f:GetFrameLevel() + 40)
  d.dash = P.Dashed(d, ACCENT, .75, "OVERLAY")
  d.sheet = CreateFrame("Frame", nil, d)
  d.sheet:SetAllPoints(win.body)
  d.sheet:EnableMouse(true)
  d.sheet:RegisterForDrag("LeftButton")
  d.sheet.tint = d.sheet:CreateTexture(nil, "BACKGROUND")
  d.sheet.tint:SetAllPoints()
  d.sheet.tint:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], .05)
  d.sheet:SetScript("OnDragStart", function() P:BeginMove(win) end)
  d.sheet:SetScript("OnDragStop", function() P:EndMove(win) end)
  d.handles = {}
  for _, corner in ipairs(CORNERS) do
    local h = CreateFrame("Button", nil, d)
    h:SetSize(9, 9)
    h:SetPoint("CENTER", f, corner, 0, 0)
    h.bg = UI.Round(h, "ARTWORK", 0, 2)
    h.bg:SetColor(ACCENT, 1)
    h:SetScript("OnMouseDown", function() f:StartSizing(corner) end)
    h:SetScript("OnMouseUp", function() f:StopMovingOrSizing(); P.SavePosition(win) end)
    d.handles[#d.handles + 1] = h
  end
  d:Hide()
  win.arrange = d
  return d
end

local bar
local function arrangeBar()
  if bar then return bar end
  bar = CreateFrame("Frame", "ParleyArrangeBar", UIParent)
  bar:SetFrameStrata("DIALOG")
  bar:SetHeight(34)
  bar:SetPoint("TOP", 0, -18)
  P.Panel(bar, 22, .12)
  bar.title = UI.Text(bar, "title", 14, P.ACCENT_TEXT)
  bar.title:SetPoint("LEFT", 12, 0)
  bar.title:SetText(L.arrangeTitle)
  bar.help = UI.Text(bar, "body", 13, C.muted)
  bar.help:SetPoint("LEFT", bar.title, "RIGHT", 10, 0)
  bar.help:SetText(L.arrangeHelp)
  bar.snap = P.Own(UI.Toggle(bar, function(on) P.db.snap = on end))
  bar.snap:SetPoint("LEFT", bar.help, "RIGHT", 14, 0)
  bar.snapLabel = UI.Text(bar, "body", 13, C.text)
  bar.snapLabel:SetPoint("LEFT", bar.snap, "RIGHT", 6, 0)
  bar.snapLabel:SetText(L.arrangeSnap)
  bar.lock = P.Own(UI.Button(bar, L.arrangeLock, "quiet", function() P:SetArranging(false); P:SetLocked(true) end))
  bar.lock:SetSize(math.max(70, (bar.lock.label:GetStringWidth() or 50) + 24), 24)
  bar.lock:SetPoint("LEFT", bar.snapLabel, "RIGHT", 14, 0)
  bar.done = P.Own(UI.Button(bar, L.arrangeDone, "primary", function() P:SetArranging(false) end))
  bar.done:SetSize(math.max(60, (bar.done.label:GetStringWidth() or 40) + 24), 24)
  bar.done:SetPoint("LEFT", bar.lock, "RIGHT", 8, 0)
  local w = 12 + (bar.title:GetStringWidth() or 50) + 10 + (bar.help:GetStringWidth() or 200) + 14 + bar.snap:GetWidth() + 6
    + (bar.snapLabel:GetStringWidth() or 30) + 14 + bar.lock:GetWidth() + 8 + bar.done:GetWidth() + 12
  bar:SetWidth(w)
  bar:Hide()
  return bar
end

---Arrange mode on or off: every window outlined, with corner handles, and the bar at the top of the screen.
function P:SetArranging(on)
  self.arranging = on and true or false
  if on and self.db.locked then self.db.locked = false end
  local b = arrangeBar()
  b.snap:SetOn(self.db.snap ~= false, true)
  b:SetShown(self.arranging)
  for _, win in ipairs(self.windows) do decor(win):SetShown(self.arranging) end
end

-- a window made while arranging gets its outline too
hooksecurefunc(P, "SyncWindows", function(self)
  if not self.arranging then return end
  for _, win in ipairs(self.windows) do decor(win):Show() end
end)
