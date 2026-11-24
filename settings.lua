-- Parley's page in the game's settings, under Norgannon.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local S = L.set
local UI = P.UI

P:OnReady(function() P.Core:OnLogin(function()
  local db = P.db
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)
  local function redraw() if db.takeover and P.RedrawAll then P:RedrawAll() end end

  list:Header(S.windows)
  list:Toggle(S.takeover, S.takeoverDesc, function() return db.takeover end, function(on)
    db.takeover = on and true or false
    ReloadUI()
  end)
  list:Slider(S.font, nil, 11, 18, 1, function() return db.font end, function(v) db.font = v; redraw() end, "%d")
  list:Dropdown(S.fontFace, nil, P:FontChoices(), function() return db.fontFace end, function(v) db.fontFace = v; redraw() end)
  list:Dropdown(S.outline, nil, { { "", S.outlineNone }, { "OUTLINE", S.outlineThin }, { "THICKOUTLINE", S.outlineThick } },
    function() return db.fontOutline or "" end, function(v) db.fontOutline = v; redraw() end)
  list:Slider(S.shadow, S.shadowDesc, 0, 1, .05, function() return db.shadow or .45 end, function(v) db.shadow = v; redraw() end,
    "%.0f%%", 100)
  list:Slider(S.background, nil, 0, 1, .05, function() return db.alpha end, function(v)
    if P.SetOpacity then P:SetOpacity(v) else db.alpha = v end
  end, "%.0f%%", 100)
  list:Toggle(S.fadeChrome, S.fadeChromeDesc, function() return db.fadeChrome end, function(on) db.fadeChrome = on end)
  list:Toggle(S.fadeBackground, S.fadeBackgroundDesc, function() return db.fadeBackground end, function(on)
    db.fadeBackground = on
    for _, w in ipairs(P.windows or {}) do P:SetChromeAlpha(w, w.headers or 1) end
  end)
  list:Toggle(S.fade, nil, function() return db.fade end, function(on) db.fade = on; redraw() end)
  list:Slider(S.fadeAfter, nil, 10, 300, 10, function() return db.fadeAfter end,
    function(v) db.fadeAfter = v; redraw() end, "%d s")
  list:Buttons(S.buttons, nil, {
    { S.pickLayout, function() P:ShowLayoutPicker() end },
    { S.arrange, function() P:SetArranging(true) end },
    { S.editNames, function() P:OpenNames() end },
    { S.resetWindows, function() P:ApplyLayout(db.layout or "one") end },
  })

  list:Header(S.lines)
  list:Toggle(S.time, nil, function() return db.time end, function(on) db.time = on; redraw() end)
  list:Toggle(S.barMiddle, S.barMiddleDesc, function() return db.barPlace == "middle" end, function(on)
    db.barPlace = on and "middle" or "start"
    redraw()
  end)
  list:Dropdown(S.names, nil, { { "full", S.namesFull }, { "short", S.namesShort }, { "first", S.namesFirst } },
    function() return db.surnames end, function(v) db.surnames = v; redraw() end)
  list:Dropdown(S.showAs, nil, { { "short", S.showShort }, { "number", S.showNumber }, { "full", S.showFull },
    { "bar", S.showBar } }, function() return db.showAs end, function(v) db.showAs = v; redraw() end)
  list:Toggle(S.group, S.groupDesc, function() return db.group end, function(on) db.group = on; redraw() end)
  list:Toggle(S.fold, S.foldDesc, function() return db.fold end, function(on) db.fold = on end)
  list:Toggle(S.tidy, S.tidyDesc, function() return db.tidy end, function(on) db.tidy = on; redraw() end)
  list:Toggle(S.craftNearby, S.craftNearbyDesc, function() return db.craftNearby end,
    function(on) db.craftNearby = on end)
  list:Toggle(S.classIcons, nil, function() return db.classIcons end, function(on) db.classIcons = on; redraw() end)
  list:Toggle(S.raceIcons, nil, function() return db.raceIcons end, function(on) db.raceIcons = on; redraw() end)

  list:Header(S.attention)
  list:Toggle(S.mentions, nil, function() return db.mentions end, function(on) db.mentions = on end)
  list:Toggle(S.toasts, S.toastsDesc, function() return db.toasts end, function(on) db.toasts = on end)
  list:Dropdown(S.whisperNotes, nil, { { "always", S.whisperAlways }, { "hidden", S.whisperHidden }, { "off", S.whisperOff } },
    function() return db.whisperNotes or "always" end, function(v) db.whisperNotes = v end)
  list:Toggle(S.sound, S.soundDesc, function() return db.sound end, function(on) db.sound = on end)
  list:Toggle(S.flash, S.flashDesc, function() return db.flash end, function(on) db.flash = on end)
  list:Toggle(S.pause, S.pauseDesc, function() return db.paused end, function(on) db.paused = on end)
  list:Buttons(S.editAlerts, nil, { { S.editAlerts, function() P:OpenAlerts() end } })

  list:Header(S.history)
  list:Toggle(S.share, S.shareDesc, function() return db.shareHistory end, function(on) P:SetShareHistory(on) end)
  list:Slider(S.keep, S.historyDesc, 1, 90, 1, function() return db.keepDays end,
    function(v) db.keepDays = v end, S.days)
  list:Toggle(S.keepAll, S.keepAllDesc, function() return db.keepAll end, function(on) db.keepAll = on end)
  list:Buttons(S.clear, S.clearDesc, { { S.clear, function() P:AskClearHistory() end } })

  page:SetScript("OnShow", function() list:Refresh() end)
  P.settingsPage, P.settingsList = page, list
  P:AddSettingsPage(page)
end) end)
