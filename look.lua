-- How Scrivener's frames look: Norgannon Core's windows, made for something that's always on screen (the mock-up:
-- design/suite/parley-suite-look.html). A chat window wants the suite's materials without its tall header: a rounded
-- panel, a soft shadow, the accent washing over its top and the light along its edge, on a back you can see through.
-- The pop-ups are the suite window's own recipe.
-- The lines keep a back as dark as ever: the suite's lighter stone, see-through over snow, took a yell's contrast from
-- 3.8:1 to 3.0:1. So the accent stays on the tab bar, above the first line.

local P = Scrivener
if not P or P.disabled then return end
local UI = P.UI
local C = UI.C

local ACCENT = UI.Hex(P.ACCENT_HEX)
local RADIUS = 10                                   -- the suite window's corners
local WHITE = { 1, 1, 1 }
local DEEP = { .106, .078, .063 }                   -- a raised chip's (UI.Chip), before its accent
local CARD = { .13, .105, .08 }                     -- a card's (UI.Card)

P.ACCENT_TEXT = UI.Readable(ACCENT)                 -- the accent, readable as small words
-- a tab's name on a back you can see through: lighter than the suite's, which are measured on solid stone (over snow at
-- 80% its accent fell to 3.2:1 and its muted words to 3.3:1; these keep 4.7 and 4.8)
P.TAB_ON = UI.Mix(ACCENT, WHITE, .45)
P.TAB_OFF = UI.Mix(C.muted, C.text, .5)
P.GLASS = UI.Mix({ 11 / 255, 9 / 255, 7 / 255 }, ACCENT, .03)   -- a window's back (its alpha is the Background setting)
P.WASH = math.max(.16, math.min(.32, 1.6 / UI.Contrast(ACCENT, C.stone)))   -- as strong as the suite washes this accent

---A quiet line, 1 px: between panes, under a pane's header, between rows.
function P.Hairline(parent, alpha)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetColorTexture(1, 1, 1, alpha or .06)
  return t
end

-------------------------------------------------------------------------------------------
-- A see-through window
-------------------------------------------------------------------------------------------

-- the wash ends where the lines start: the tab bar and a pane's header are above it
local WASH_FADE = 44

---Give a chat window its materials: win.shadow, win.bg, win.wash, win.sheen (painted by P:PaintWindow).
function P.Glass(win)
  local f = win.frame
  win.shadow = UI.ShadowRing(f, -8)   -- only outside the window: UI.Shadow would darken a see-through one
  win.bg = UI.Round(f, "BACKGROUND", -4, RADIUS)
  win.wash = UI.Wash(f, "BACKGROUND", -3, RADIUS, WASH_FADE)
  win.sheen = UI.Sheen(f, "BACKGROUND", -2)
end

local WASH_FROM = .4   -- a back fainter than this takes its wash down with it, so opacity 0 is fully clear

---Paint a chat window: glass is its back's alpha, headers how much of the tab bar shows. The shadow and the light fade
---with the back, the accent with the tab bar and, below WASH_FROM, with the opacity setting. Their strength lives in the
---textures' colour: on this client a texture's SetAlpha writes that same value.
function P.PaintGlass(win, glass, headers)
  win.bg:SetColor(P.GLASS, glass)
  win.sheen:SetColor(WHITE, glass)
  win.shadow:SetColor(WHITE, glass * (.5 + .5 * headers))
  -- gradients cost a little: only when they change
  local wash = P.WASH * headers * math.min(1, (P.db.alpha or .8) / WASH_FROM)
  if win.washed ~= wash then
    win.washed = wash
    win.wash:SetColor(ACCENT, wash)
  end
  if win.ruled ~= headers then
    win.ruled = headers
    UI.GradientH(win.rule, ACCENT, .8 * headers)
  end
end

-------------------------------------------------------------------------------------------
-- Pop-ups, as the suite's windows
-------------------------------------------------------------------------------------------

---A suite window's materials on a pop-up. washFade: how far down the accent fades (with the corners' 10 px, it has to
---fit the frame); washAlpha: the suite's own, when left out. It fades in as suite windows do: hook its OnShow, don't set
---it, and leave it hidden once built, so its first opening fades too.
function P.Panel(f, washFade, washAlpha)
  -- the suite's shadow has 56 px corners: on a shorter frame (a toast, the arrange bar) they would lie over each other
  local h = f:GetHeight() or 0
  local corner = h > 0 and h < 56 and h or 56
  f.shadow = UI.Slice(f, "BACKGROUND", -8, UI.TEX.shadow, .4375, corner, corner / 2)
  f.back = UI.Round(f, "BACKGROUND", -4, RADIUS)
  f.back:SetColor(UI.Mix(C.stone, ACCENT, .05))
  f.wash = UI.Wash(f, "BACKGROUND", -3, RADIUS, washFade or 110)
  f.wash:SetColor(ACCENT, washAlpha or P.WASH)
  f.sheen = UI.Sheen(f, "BACKGROUND", -2)
  local fade = f.CreateAnimationGroup and f:CreateAnimationGroup()
  local step = fade and fade.CreateAnimation and fade:CreateAnimation("Alpha")
  if step then
    step:SetFromAlpha(0)
    step:SetToAlpha(1)
    step:SetDuration(.12)
    f:HookScript("OnShow", function() fade:Play() end)
  end
  return f
end

---A pop-up's title in Scrivener's colour, with the suite's fading line under it, `at` px from the top.
function P.PanelTitle(f, text, size, x, y, at)
  f.title = UI.Text(f, "title", size, P.ACCENT_TEXT)
  f.title:SetPoint("TOPLEFT", x, y)
  f.title:SetText(text)
  if at then
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetHeight(1)
    f.rule:SetPoint("TOPLEFT", 0, -at)
    f.rule:SetPoint("TOPRIGHT", 0, -at)
    UI.GradientH(f.rule, ACCENT, .8)
  end
  return f.title
end

---A raised card, as UI.Card: :Look(pointed at, picked).
function P.Card(b)
  b.box = UI.SoftBox(b, "BACKGROUND", 0, 6)
  b.gleam = UI.Tex(b, "BACKGROUND", 3)                -- its top edge catches the light
  b.gleam:SetColorTexture(1, 1, 1, .07)
  b.gleam:SetHeight(1)
  b.gleam:SetPoint("TOPLEFT", 6, 0)
  b.gleam:SetPoint("TOPRIGHT", -6, 0)
  function b:Look(hover, picked)
    local line = picked and ACCENT or (hover and { ACCENT[1], ACCENT[2], ACCENT[3], .8 }) or nil
    self.picked = picked and true or false
    self.box:Set(line, UI.Mix(CARD, ACCENT, picked and .16 or .06))
  end
  b:Look()
  return b
end

-------------------------------------------------------------------------------------------
-- Pills and fields of Scrivener's own, drawn as the Core's controls
-------------------------------------------------------------------------------------------

---A raised pill you press (the chat box's chip and its menu pill): :Raise(hover, strong). strong is a deep accent. Its
---face is darker than a quiet button's: its word is in the chat's own colour, and a yell's red needs the dark.
function P.RaisedPill(b)
  b.face = UI.Face(b, "BACKGROUND", 0, true)
  function b:Raise(hover, strong)
    if strong then self.face:Set(UI.Mix(DEEP, ACCENT, hover and .5 or .38))
    else self.face:Set(UI.Mix(DEEP, ACCENT, hover and .12 or .05)) end
  end
  b:Raise(false)
  return b
end

---A pill that's on or off, as UI.Chip: raised in a deep accent, or an empty recess. :SetLit(on, hover).
function P.SwitchPill(b)
  b.well = UI.Band(b, "BACKGROUND", 0, "pillWell", true)
  b.edge = UI.Band(b, "BACKGROUND", 1, "pillLine", true)
  b.face = UI.Face(b, "BACKGROUND", 0, true)
  function b:SetLit(on, hover)
    self.face:SetShown(on)
    self.well:SetShown(not on)
    self.edge:SetShown(not on)
    if on then self.face:Set(UI.Mix(DEEP, ACCENT, hover and .5 or .38))
    else self.edge:SetColor(UI.Mix(C.line, ACCENT, hover and .6 or .2)) end
  end
  b:SetLit(false)
  return b
end

---A recessed text field around one of Scrivener's own edit boxes, as UI.Input: :Light(on) glows in Scrivener's colour.
function P.FieldLook(f)
  f.field = UI.Field(f, "BACKGROUND", 0)
  function f:Light(on)
    self.lit = on and true or false
    self.field:Set(on and ACCENT or UI.Mix(C.line, ACCENT, .22), self.lit)
  end
  f:Light(false)
  return f
end
