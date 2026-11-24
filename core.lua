-- Scrivener: chat, rebuilt for WoW Forever. Built on Norgannon Core.
-- Plan and client findings: docs/chat-plan.md; the windows: design/suite/parley.html, their look: design/suite/parley-suite-look.html.
--
-- Scrivener draws its own windows and keeps Blizzard's chat running underneath, out of sight. Blizzard's chat box is moved
-- into Scrivener's window and restyled with widget calls only: Scrivener never writes its fields or replaces its scripts, so
-- /cast and the other protected commands typed into it keep working. In dungeon fights the game hides what chat lines
-- say from add-ons; Scrivener shows them as they arrive (joined with .., never read), then reads them again by line id
-- when the fight ends.

local ADDON = ...
local Core = NorgannonCore

if not (Core and Core.NewAddon) then
  local words = Scrivener and Scrivener.L
  Scrivener = { disabled = true }
  print(words and words.needsCore or "Scrivener needs Norgannon Core 1.35 or newer; it is turned off.")
  return
end

Scrivener = Scrivener or {}
local P = Scrivener
local L = P.L

P.VERSION = "0.9.0"
P.Core = Core
P.UI = Core.UI
P.MEDIA = "Interface\\AddOns\\Scrivener\\media\\"
P.MARK = P.MEDIA .. "scrivener"            -- two voices, built like every suite mark (docs/chat-plan.md section 12)
P.ACCENT_HEX = "9aa6ff"

---A Core widget in Scrivener's colour. The Core colours a widget from the suite window it sits in; Scrivener's own frames
---aren't suite windows, so without this its switches, buttons, fields and scrollbars come out in the suite's gold.
function P.Own(widget)
  local accent = P.UI.Hex(P.ACCENT_HEX)
  if widget.ApplyAccent then widget:ApplyAccent(accent) end
  local thumb = widget.thumb   -- a scroll area's own scrollbar
  if type(thumb) == "table" and thumb.ApplyAccent then thumb:ApplyAccent(accent) end
  return widget
end

-------------------------------------------------------------------------------------------
-- Saved data: settings and windows are the account's. Chat history is each character's, with a copy in the account's file
-- for your other characters to show (history.lua)
-------------------------------------------------------------------------------------------

P.DEFAULTS = {
  takeover = true,        -- Scrivener's windows instead of the game's (false: the game's chat, untouched)
  layout = false,         -- the layout picked on first run; false until one is
  windows = {},           -- { x, y, w, h, active, tabs = { { name, kinds = { [key] = true }, all, special } } }
  locked = false,
  snap = true,            -- moving a window snaps it to the screen's edges and other windows (arrange.lua)
  font = 13,             -- the mock-up's 13.5 px
  fontFace = "suite",     -- window.lua P.FONT_ORDER, or "lsm:<name>" for a SharedMedia font
  fontOutline = "",       -- "", "OUTLINE" or "THICKOUTLINE"
  shadow = .45,           -- the text shadow's strength, 0 for none (window.lua P.ShadowFor: .5 is a full 1 px shadow)
  alpha = .8,             -- background strength (the mock-up's glass is 80%)
  fade = true,
  fadeAfter = 60,         -- seconds before old lines fade
  fadeChrome = false,     -- fade the tab bar, pane headers and an idle chat box when the mouse is away
  fadeBackground = false, -- with fadeChrome, the window's background fades too
  barPlace = "start",     -- "start" (the mock-up) or "middle" (after the time and the chat's short name)
  group = false,          -- lines from one person within two minutes run together (Maro didn't like it: off unless chosen)
  tidy = true,            -- money, loot, rolls, XP, reputation and skill lines in a short shape with an icon
  craftNearby = false,    -- strangers crafting and opening things near you (a flood in cities); yours and your group's always show
  raceIcons = false,      -- the game's race icon beside names (Better Forever Chat's feature, off unless chosen)
  classIcons = false,     -- the game's class icon beside names
  shareHistory = true,    -- every character shows the others' chat history too (history.lua); off: only its own
  histories = {},         -- [character's GUID] = { name, history, people, personInfo }: what the others show
  keepAll = true,         -- history keeps public channels, Say, loot and system lines too (two days, 400 of each)
  time = true,
  surnames = "full",      -- "full", "short" (Elowen B.) or "first"
  showAs = "short",       -- "short", "number", "full" or "bar"
  fold = true,
  short = {},             -- [kind key] = the short name the player chose
  mentions = true,
  toasts = true,
  whisperNotes = "always",  -- "always" (unless typing), "hidden" (only when no shown pane has it) or "off"
  sound = true,
  flash = true,
  paused = false,         -- alerts paused
  alerts = {},            -- { text, where = "public" | "all", when = "always" | "solo" | "cities" | "outside", on,
                          --   outs = { toast, sound, flash } (0.6.0; older alerts follow the For you settings) }
  keepDays = 30,
  seen = {},              -- [kind key] = true for every chat and channel Scrivener has seen a line in (for pickers)
  chanNames = {},         -- [channel key] = the channel's own name, as last seen
}

-- Saved data (each character's own, 0.7.6): what was said to and around them
P.CHAR_DEFAULTS = {
  history = {},           -- [kind key] = { { t, type, who, text, num, why, kind }, ... } oldest first
  people = {},            -- [full name] = GUID, for class colours on saved lines
  personInfo = {},        -- [lower full name] = { level, guild ("" for none), class, at }: people you've whispered with
}

-- Saves from 0.1.0 move to the look Maro compared against the mock-up: the mock-up's window size, text size and glass.
-- Only values still at 0.1.0's defaults change; anything the player set stays.
P.MIGRATE = {
  [2] = function(sv)
    if sv.font == 14 then sv.font = 13 end
    if sv.alpha == .6 then sv.alpha = .8 end
    local old, new = P.OLD_LAYOUTS and P.OLD_LAYOUTS[sv.layout], P.LAYOUTS and P.LAYOUTS[sv.layout]
    if type(sv.windows) ~= "table" or not old or not new then return end
    for i, w in ipairs(sv.windows) do
      local o, n = old[i], new[i]
      if o and n and w.w == o[1] and w.h == o[2] then w.x, w.y, w.w, w.h = n.x, n.y, n.w, n.h end
    end
  end,
  -- 0.2.0 brings panes side by side and the mock-up's One window: offer the layouts once (nothing changes unless picked)
  [3] = function(sv)
    if type(sv.windows) == "table" and #sv.windows > 0 then sv.offerLayouts = true end
  end,
  -- 0.3.0: add-ons' notices leave the mixed chats for an Add-ons tab of their own
  [4] = function(sv)
    if type(sv.windows) ~= "table" or #sv.windows == 0 then return end
    local home = false
    for _, w in ipairs(sv.windows) do
      for _, tab in ipairs(w.tabs or {}) do
        for _, pane in ipairs({ tab, unpack(tab.split or {}) }) do
          if type(pane.kinds) == "table" and pane.kinds.ADDONS then
            local others = false
            for k in pairs(pane.kinds) do if k ~= "ADDONS" then others = true end end
            if others then pane.kinds.ADDONS = nil else home = true end
          end
        end
      end
    end
    if not home and sv.windows[1].tabs then
      table.insert(sv.windows[1].tabs, { name = P.L.tab.addons, kinds = { ADDONS = true } })
    end
  end,
  -- 0.3.0: a reload brings the whole window back, public chat included (Maro: "I should have history")
  [5] = function(sv) sv.keepAll = true end,
  -- 0.4.0: the shadow became a strength, not on or off
  [6] = function(sv)
    if sv.fontShadow == false then sv.shadow = 0 end
    sv.fontShadow = nil
  end,
  -- every line shows its name and time again; running lines together is a choice in Settings
  [7] = function(sv) sv.group = false end,
  -- the shadow scale doubled: what was full is now half, and the top half is a larger, darker shadow
  [8] = function(sv) if type(sv.shadow) == "number" then sv.shadow = sv.shadow / 2 end end,
  -- 0.5.0: a Whispers tab becomes the mock-up's conversations (people on the left, one conversation on the right)
  [9] = function(sv)
    for _, w in ipairs(sv.windows or {}) do
      for _, tab in ipairs(w.tabs or {}) do
        local only = type(tab.kinds) == "table" and tab.kinds.WHISPER and not tab.special and not tab.all
        if only then for k in pairs(tab.kinds) do if k ~= "WHISPER" then only = false end end end
        if only then tab.special = "convos" end
      end
    end
  end,
}

-------------------------------------------------------------------------------------------
-- Small helpers
-------------------------------------------------------------------------------------------

local issecretvalue = rawget(_G, "issecretvalue")
---True for a value the game has hidden from add-ons. Nothing may compare, measure or index it.
function P.Hidden(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end
local Hidden = P.Hidden

P.diag = { lines = 0, held = 0, heldShown = 0, heldRefused = 0, reread = 0, rereadHidden = 0, rereadGone = 0,
  copies = 0, lockdowns = 0, errors = 0, lastError = nil, box = false }

---Run fn and keep going if it fails; the error is counted for /scrivener check.
function P.Safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    P.diag.errors = P.diag.errors + 1
    if not Hidden(err) then P.diag.lastError = tostring(err) end
  end
  return ok, err
end

function P.Hex(r, g, b)
  return string.format("ff%02x%02x%02x", math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5))
end

function P.Me()
  return Core.Names.Me()
end

---The game is hiding chat from add-ons right now (dungeon boss fights on Forever).
function P.ChatHidden()
  local enum = rawget(_G, "Enum") and Enum.AddOnRestrictionType
  local ra = rawget(_G, "C_RestrictedActions")
  if enum and enum.Chat and ra and ra.IsAddOnRestrictionActive then
    local ok, on = pcall(ra.IsAddOnRestrictionActive, enum.Chat)
    if ok and on == true then return true end
  end
  local info = rawget(_G, "C_ChatInfo")
  if info and info.InChatMessagingLockdown then
    local ok, on = pcall(info.InChatMessagingLockdown)
    if ok and on == true then return true end
  end
  return false
end

-------------------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------------------

local function word(rest) return (rest or ""):match("^%s*(.-)%s*$") end

Core:NewAddon("scrivener", {
  folder = ADDON, api = { 1, 35 },
  name = "Scrivener", accent = P.ACCENT_HEX, role = L.role, mark = P.MARK,
  db = "ScrivenerDB", defaults = P.DEFAULTS, version = 9, migrate = P.MIGRATE,
  char = "ScrivenerCharDB", charDefaults = P.CHAR_DEFAULTS, charVersion = 1,
  slash = { "/scrivener", "/parley" },
  commands = {
    arrange = { function() if P.SetArranging then P:SetArranging(not P.arranging) end end, L.cmd.arrange },
    new = { function() if P.NewWindow then P:NewWindow() end end, L.cmd.new },
    layout = { function(rest)
      local name = word(rest):lower()
      if P.LAYOUTS and P.LAYOUTS[name] then P:ApplyLayout(name) elseif P.ShowLayoutPicker then P:ShowLayoutPicker() end
    end, L.cmd.layout },
    alert = { function(rest)
      local text = word(rest)
      if text == "" then return P:Print(L.alertNeedsWords) end
      P:AddAlert(text)
      P:Print(L.alertAdded:format(text))
    end, L.cmd.alert },
    alerts = { function() P:OpenAlerts() end, L.cmd.alerts },
    names = { function() P:OpenNames() end, L.cmd.names },
    find = { function(rest)
      local text = word(rest)
      if text == "" then return P:Print(L.findNeedsWords) end
      P:Search(text)
    end, L.cmd.find },
    off = { function() P.db.takeover = false; ReloadUI() end, L.cmd.off },
    on = { function() P.db.takeover = true; ReloadUI() end, L.cmd.on },
    check = { function() P:PrintCheck() end, L.cmd.check },
    reset = { function() P:ApplyLayout(P.db.layout or "one") end, L.cmd.reset },
  },
})
if P.disabled then return end

-- Up to 0.7.5 one history served every character on the account (Maro, 21 Nov: "Chat history should be per character").
-- It goes to the character it belongs to: the one it names among the people who spoke in it (it keeps everyone's GUID,
-- yours included once you've said anything). Another character leaves it be and starts its own. Runs before anything
-- reads history.
-- It's copied, and the account's copy goes only at a later login that finds the character's save holding the copy: the
-- game saves ScrivenerCharDB only once it has been restarted with 0.7.6's TOC, and a /reload before that would otherwise
-- lose it.
local function mergeOldest(a, b)   -- two lists, each oldest first, into one (lines from the same second keep their order)
  local out, i, j = {}, 1, 1
  while i <= #a or j <= #b do
    local x, y = a[i], b[j]
    if y == nil or (x ~= nil and (x[1] or 0) <= (y[1] or 0)) then out[#out + 1] = x; i = i + 1
    else out[#out + 1] = y; j = j + 1 end
  end
  return out
end

function P:ClaimSharedHistory()
  local old, people = self.db.history, self.db.people
  if type(old) ~= "table" then return false end
  people = type(people) == "table" and people or {}
  local guid, me = UnitGUID and UnitGUID("player"), self.Me()
  local mine = me ~= nil and people[me] ~= nil
  if not mine and guid then
    for _, g in pairs(people) do if g == guid then mine = true; break end end
  end
  if not mine then return false end
  if self.char.claimedShared then   -- the copy came back from this character's save: the account's can go
    self.db.history, self.db.people, self.db.personInfo = nil, nil, nil
    return false
  end
  local hist = self.char.history
  for kind, list in pairs(old) do
    if type(list) == "table" then hist[kind] = mergeOldest(list, hist[kind] or {}) end   -- a copy, never the same table
  end
  for name, g in pairs(people) do if self.char.people[name] == nil then self.char.people[name] = g end end
  for key, e in pairs(type(self.db.personInfo) == "table" and self.db.personInfo or {}) do
    if self.char.personInfo[key] == nil then self.char.personInfo[key] = e end
  end
  self.char.claimedShared = true
  return true
end

P:OnReady(function() P:ClaimSharedHistory() end)

function P:PrintCheck()
  local d, C = self.diag, L.check
  self:Print(C.title)
  self:Print(C.box:format(d.box and C.yes or C.no))
  self:Print(C.lines:format(d.lines))
  self:Print(C.held:format(d.held, d.heldShown, d.heldRefused))
  self:Print(C.reread:format(d.reread, d.rereadHidden, d.rereadGone))
  self:Print(C.copies:format(d.copies))
  self:Print(C.filters:format(d.filterErrors or 0))
  if d.lastFilterError then self:Print(C.lastError:format(d.lastFilterError)) end
  self:Print(C.lockdowns:format(d.lockdowns))
  self:Print(C.errors:format(d.errors))
  if d.lastError then self:Print(C.lastError:format(d.lastError)) end
end

-- Other chat add-ons (Parley is what Scrivener was called up to 0.8.2) fight over the chat box; say so once rather than quietly breaking.
local OTHERS = { "Parley", "Prat-3.0", "Chattynator", "Chatter", "Glass", "ElvUI" }
P:OnReady(function()
  if not P.db.takeover then return end
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
  if not loaded then return end
  for _, name in ipairs(OTHERS) do
    if loaded(name) then
      Core:OnLogin(function() P:Print(L.otherChat:format(name)) end)
      return
    end
  end
end)
