-- The combat log: the game's own, in a Scrivener pane.
-- The game's chat windows are out of sight (takeover.lua), and its combat log is one of them. A Combat log tab gives it
-- back, filter bar and all, inside Scrivener's window: its filters, colours and settings stay the game's (right-click the
-- filter bar). Scrivener only moves and shows it, with widget calls and HookScript; it never writes the game's fields.

local P = Scrivener
if not P or P.disabled then return end

local host   -- the pane holding the combat log (its tf), while one does
P.hosts = P.hosts or {}   -- [frame name] = how to place one of the game's chat frames instead of hiding it (takeover.lua)

local function frames()
  return rawget(_G, "COMBATLOG"), rawget(_G, "CombatLogQuickButtonFrame_Custom")
end

-- the log's own side buttons and resize grip would stick out of the pane; they stay hidden while Scrivener holds it
local function keepHidden(frame)
  if not frame or frame.scrivenerHidden then return end
  frame.scrivenerHidden = true
  frame:HookScript("OnShow", function(self) if host then self:Hide() end end)
  frame:Hide()
end

---Put the combat log in its pane: the filter bar along the top (where the game puts it, over the log), the log under it.
---Returns false when no pane holds it, so the game's chat windows' sweep puts it out of sight.
local function place()
  local log, bar = frames()
  if host and P.tabFrames[host.pane] ~= host then host = nil end
  if not (host and log) then return false end
  local holder, head = host.frame, host.head
  if log:GetParent() ~= holder then log:SetParent(holder) end
  local barH = 0
  if bar then
    if bar:GetParent() ~= holder then bar:SetParent(holder) end
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", log, "TOPLEFT", 0, 2)
    bar:SetPoint("BOTTOMRIGHT", log, "TOPRIGHT", 0, 2)
    barH = bar:GetHeight() or 24
    bar:Show()
  end
  log:ClearAllPoints()
  log:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 6, -(barH + 6))
  log:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -6, 4)
  log:SetFrameLevel(holder:GetFrameLevel() + 2)
  local name = log.GetName and log:GetName()
  if name then
    keepHidden(rawget(_G, name .. "ButtonFrame"))
    keepHidden(rawget(_G, name .. "ResizeButton"))
  end
  log:Show()   -- the game hides a docked window that isn't its selected tab
  return true
end
P.PlaceCombatLog = place

---A Combat log pane: its own lines are the game's log, so Scrivener's line frame steps aside.
function P:HostCombatLog(pane, tf)
  tf.pane = pane
  tf.hosting = true
  tf.smf:Hide()
  local function take()
    host = tf
    P.Safe(place)
  end
  tf.frame:HookScript("OnShow", take)
  take()
  local log = frames()
  local name = log and log.GetName and log:GetName()
  if name then
    P.hosts[name] = place
    P.hosts.CombatLogQuickButtonFrame_Custom = function(bar) return host ~= nil and bar:GetParent() == host.frame end
  end
end
