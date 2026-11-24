-- One line of chat as Parley shows it: the time, a coloured bar for the chat, the chat's short name in tabs that mix
-- chats, the person in class colour, the words. Held lines (hidden by the game in a fight) are joined with `..` into
-- the same layout and never read: no comparing, measuring or matching touches them.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local Hidden = P.Hidden

local BAR = P.MEDIA .. "bar"   -- a rounded white pill lit from the top, tinted to the chat's colour
local FAINT = "|cff6e6552"
local WHY = "|cff" .. P.ACCENT_HEX
local GAP = "  "               -- the mock-up's 7 px column gap, in spaces
local GOOD, BAD = "|cff8fe08f", "|cffff9478"   -- the suite's good and bad (Core.UI.C)

local function n255(v) return math.floor((v or 1) * 255 + .5) end

---The text size of the line being drawn (a window can have its own); icons and the bar follow it.
function P.LineSize() return P.curSize or (P.db and P.db.font) or 13 end

---How far an inline icon is lowered to sit on the line's middle: the game draws inline textures above the middle of
---the text (Better Forever Chat found the same for atlases), by about a quarter of the font's height.
function P.IconDrop(size)
  return -math.floor((size or P.LineSize()) * .22 + .5)
end

-- An icon's fields after its name: height, width, x, y, then whatever follows. Left out, the width is the height, and the
-- offsets are 0. An icon its author already lowered keeps the lower of the two (Parley's own come through unchanged).
local function lowered(body, drop)
  local f = {}
  for part in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = part end
  if #f == 0 or f[1] == "" then return body end
  local function field(i, default) if not f[i] or f[i] == "" then f[i] = default end end
  field(2, "0")
  field(3, f[2])
  field(4, "0")
  local y = tonumber(f[5]) or 0
  f[5] = tostring(y > 0 and y + drop or math.min(y, drop))
  return table.concat(f, ":")
end

---A text with the icons in it lowered to the line's middle: raid marks, coins, the game's flags and other add-ons' icons
---all come at the game's own height (Maro, 23 Nov). size: the text's size, when it isn't the line being drawn. A typed
---"||T" is words, not an icon. Hidden text comes back as it is.
function P.LowerIcons(text, size)
  if type(text) ~= "string" or Hidden(text) then return text end
  local drop
  if text:find("|T", 1, true) then
    drop = P.IconDrop(size)
    text = text:gsub("(|+)T([^|]*)|t", function(pipes, body)
      if #pipes % 2 == 1 then return pipes .. "T" .. lowered(body, drop) .. "|t" end
    end)
  end
  if text:find("|A:", 1, true) then
    drop = drop or P.IconDrop(size)
    text = text:gsub("(|+)A:([^|]*)|a", function(pipes, body)
      if #pipes % 2 == 1 then return pipes .. "A:" .. lowered(body, drop) .. "|a" end
    end)
  end
  return text
end

---Wrap an icon in a link that only explains itself: hovering it shows what it means (the game shows nothing for a bare
---texture), clicking does nothing.
function P.Explained(what, texture)
  return "|Haddon:Parley:tip:" .. what .. "|h" .. texture .. "|h"
end

---The chat's bar, the first thing on every line (3 px wide, a little shorter than the text, centred on it); hovering it
---names the chat, and whose it is when it's another character's.
local function bar(r, g, b, h, kind, from)
  local tex = ("|T%s:%d:3:0:%d:8:32:0:8:0:32:%d:%d:%d|t"):format(BAR, h - 2, P.IconDrop(), n255(r), n255(g), n255(b))
  if kind then tex = P.Explained("kind:" .. kind .. (from and "@@" .. from or ""), tex) end
  return tex .. GAP
end

-------------------------------------------------------------------------------------------
-- Race and class icons beside names (off unless chosen; the game's own atlases)
-------------------------------------------------------------------------------------------

local atlasOk = {}
local function atlas(name)
  if type(name) ~= "string" then return "" end
  if atlasOk[name] == nil then
    local tex = rawget(_G, "C_Texture")
    atlasOk[name] = (tex and tex.GetAtlasInfo and tex.GetAtlasInfo(name)) and true or false
  end
  if not atlasOk[name] then return "" end
  local size = P.LineSize()
  return "|A:" .. name .. ":" .. size .. ":" .. size .. ":0:" .. P.IconDrop() .. "|a "
end

local GENDER = { [2] = "male", [3] = "female" }
function P.PlayerIcons(guid)
  if not (P.db.raceIcons or P.db.classIcons) or type(guid) ~= "string" or guid == "" or not GetPlayerInfoByGUID then
    return ""
  end
  local ok, _, class, _, race, sex = pcall(GetPlayerInfoByGUID, guid)
  if not ok then return "" end
  local out = ""
  local raceAtlas, classAtlas = rawget(_G, "GetRaceAtlas"), rawget(_G, "GetClassAtlas")
  if P.db.raceIcons and type(race) == "string" and GENDER[sex] and raceAtlas then
    local ok2, name = pcall(raceAtlas, race:lower(), GENDER[sex])
    if ok2 then out = out .. atlas(name) end
  end
  if P.db.classIcons and type(class) == "string" and classAtlas then
    local ok2, name = pcall(classAtlas, class:lower())
    if ok2 then out = out .. atlas(name) end
  end
  return out
end

---How the time reads: the game's own timestamp format when one is chosen in its options (12-hour, with seconds), else
---24-hour hours and minutes.
function P.StampFormat()
  local util = rawget(_G, "ChatFrameUtil")
  local get = util and util.GetTimestampFormat
  if get then
    local ok, f = pcall(get)
    if ok and type(f) == "string" then
      f = f:match("^%s*(.-)%s*$")
      if f ~= "" then return f end
    end
  end
  return "%H:%M"
end

local stampMin, stampText, todayMin, today, base = nil, nil, nil, nil, "%H:%M"
local function stamp(t)
  if not P.db.time or not t then return "" end
  local minute = math.floor(t / 60)
  if minute == stampMin then return stampText end    -- busy channels: one date() per minute, not per line
  local now = math.floor(time() / 60)
  if now ~= todayMin then todayMin, today, base = now, date("%Y%m%d"), P.StampFormat() end
  local fmt = base
  if date("%Y%m%d", t) ~= today then fmt = "%d %b " .. base end
  local text = FAINT .. date(fmt, t) .. "|r" .. GAP
  if fmt == base and not base:find("%S", 1, true) then stampMin, stampText = minute, text end
  return text
end

-------------------------------------------------------------------------------------------
-- Names
-------------------------------------------------------------------------------------------

local classHex = {}   -- [guid] = "ffrrggbb" once known
local function colorFor(guid)
  if type(guid) ~= "string" or guid == "" then return nil end
  local c = classHex[guid]
  if c then return c end
  if not GetPlayerInfoByGUID then return nil end
  local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
  if not ok or not class then return nil end
  local col = (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
    or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  c = col and ((col.GenerateHexColor and col:GenerateHexColor()) or col.colorStr)
  classHex[guid] = c
  return c
end
P.ClassHex = colorFor

local FIRST_CHAR = "^[%z\1-\127\194-\244][\128-\191]*"
---A full name as the player chose to see it: Elowen Brightwater, Elowen B. or Elowen.
function P.ShowName(full)
  full = P.Core.Names.Full(full) or full or ""
  local mode = P.db.surnames
  if mode == "full" then return full end
  local first, rest = full:match("^(%S+)%s+(.+)$")
  if not first then return full end
  if mode == "first" then return first end
  return first .. " " .. (rest:match(FIRST_CHAR) or "") .. "."
end

local GROUP_OF = { PARTY_LEADER = "PARTY", PARTY_GUIDE = "PARTY", RAID_LEADER = "RAID", RAID_WARNING = "RAID",
  INSTANCE_CHAT_LEADER = "INSTANCE_CHAT", WHISPER_INFORM = "WHISPER", GUILD_DISCORD = "GUILD" }
local function chatGroup(t) return GROUP_OF[t] or t end

---A channel line's number. Numbers are each character's own, and change: a line from history has this character's now.
local function chanNum(r)
  if not (r.restored and r.chan) then return r.num end
  return P.chanNum[r.kind] or (not r.from and r.num) or nil
end
P.LineChanNum = chanNum

local function playerLink(r)
  if r.bn then return P.BNLink(r) end   -- a Battle.net friend: their token, in Battle.net blue
  local group = chatGroup(r.type)
  local num = chanNum(r)
  local target = num and tostring(num) or ""
  if r.held then
    -- `..` only: the name stays hidden inside the link and the game shows it
    return "|Hplayer:" .. r.who .. ":" .. (r.lineID or 0) .. ":" .. group .. ":" .. target .. "|h" .. r.who .. "|h"
  end
  local full = P.Core.Names.Full(r.who) or r.who
  local shown = P.ShowName(full)
  local hex = colorFor(r.guid)
  if hex then shown = "|c" .. hex .. shown .. "|r" end
  if GetPlayerLink then
    local ok, link = pcall(GetPlayerLink, r.who, shown, r.lineID, group, target)
    if ok and link then return link end
  end
  return "|Hplayer:" .. r.who .. ":" .. (r.lineID or 0) .. ":" .. group .. ":" .. target .. "|h" .. shown .. "|h"
end

-------------------------------------------------------------------------------------------
-- The words
-------------------------------------------------------------------------------------------

P.urls, P.urlNext = {}, 0
local function wrapUrl(url)
  P.urlNext = P.urlNext % 500 + 1
  P.urls[P.urlNext] = url
  return "|cff9fd0ff|Haddon:Parley:url:" .. P.urlNext .. "|h" .. url .. "|h|r"
end

-- A quest shared as text, the way Questie sends it ("[[47] The Captain's Chest (8551)]"), becomes the game's own quest
-- link: Questie's link handler shows its quest tooltip for those, and the game shows its own without Questie. Text an
-- add-on already turned into a link is left alone.
local QUEST = "|cffffff00|Hquest:%s:%s|h[%s]|h|r"
function P.QuestLinks(msg)
  if not msg:find("(%d+)%)%]") then return msg end
  msg = msg:gsub("%[%[(%d+)[^%]]*%] ([^%[%]|]-) %((%d+)%)%]", function(level, name, id)
    return QUEST:format(id, level, "[" .. level .. "] " .. name)
  end)
  msg = msg:gsub("%[([^%[%]|]-) %((%d+)%)%]", function(name, id) return QUEST:format(id, "-1", name) end)
  return msg
end

function P.Linkify(msg)
  if not msg:find("[%w]%.%a") then return msg end
  msg = msg:gsub("%f[%S](%a[%w+.-]*://[^%s|]+)", wrapUrl)
  msg = msg:gsub("%f[%S](www%.[%w-]+%.[^%s|]+)", wrapUrl)
  return msg
end

local GROUP_ICONS = { PARTY = true, RAID = true, INSTANCE = true }
local function icons(r, msg)
  local ci = C_ChatInfo
  if not (ci and ci.ReplaceIconAndGroupExpressions) then return msg end
  local ok, out = pcall(ci.ReplaceIconAndGroupExpressions, msg, r.noIcons and true or nil,
    not GROUP_ICONS[r.kind] and true or nil)
  if ok and out then return out end
  return msg
end

local function escape(s) return (s:gsub("%%", "%%%%")) end

-------------------------------------------------------------------------------------------
-- Tags: the chat's short name, in tabs that mix chats
-------------------------------------------------------------------------------------------

local LINKED = { GUILD = "GUILD", OFFICER = "OFFICER", PARTY = "PARTY", RAID = "RAID", INSTANCE = "INSTANCE_CHAT" }

function P.Mixed(tab)
  if not tab then return false end
  if tab.special == "convos" then return false end   -- one person's lines: no short names
  if tab.special then return true end
  if tab.all then return true end
  local n = 0
  for _ in pairs(tab.kinds) do n = n + 1; if n > 1 then return true end end
  return false
end

-- only chats people talk in carry their short name: a system, loot or money line says what it is already
local NO_TAG = { SYSTEM = true, LOOT = true, MONEY = true, XP = true, CRAFT = true, ADDONS = true }

local function tag(r, tab)
  if not P.Mixed(tab) or P.db.showAs == "bar" or NO_TAG[r.kind] then return "" end
  local text
  local num = chanNum(r)
  if P.db.showAs == "number" and num then text = tostring(num)
  elseif P.db.showAs == "full" then text = P.KindLabel(r.kind)
  else text = P.Short(r.kind) end
  local cr, cg, cb = P.KindColor(r.kind)
  text = "|c" .. P.Hex(cr, cg, cb) .. text .. "|r"
  if r.chan and num then
    text = "|Hchannel:channel:" .. num .. "|h" .. text .. "|h"
  elseif LINKED[r.kind] then
    text = "|Hchannel:" .. LINKED[r.kind] .. "|h" .. text .. "|h"
  end
  return text .. " "
end

-------------------------------------------------------------------------------------------
-- The line
-------------------------------------------------------------------------------------------

local SENDERLESS = { SYSTEM = true, LOOT = true, CURRENCY = true, MONEY = true, COMBAT_XP_GAIN = true,
  COMBAT_HONOR_GAIN = true, COMBAT_FACTION_CHANGE = true, SKILL = true, COMBAT_MISC_INFO = true, TRADESKILLS = true,
  OPENING = true, CHANNEL_NOTICE = true, CHANNEL_NOTICE_USER = true, IGNORED = true, FILTERED = true, RESTRICTED = true,
  TARGETICONS = true, PET_INFO = true, BG_SYSTEM_NEUTRAL = true, BG_SYSTEM_ALLIANCE = true, BG_SYSTEM_HORDE = true,
  ADDON = true, PARLEY = true, GAME = true, CHANNEL_LIST = true, BN_INLINE_TOAST_ALERT = true, BN_INLINE_TOAST_BROADCAST = true,
  BN_INLINE_TOAST_BROADCAST_INFORM = true, BN_WHISPER_PLAYER_OFFLINE = true }
local NPC = { MONSTER_SAY = true, MONSTER_YELL = true, MONSTER_EMOTE = true, MONSTER_WHISPER = true,
  MONSTER_PARTY = true, RAID_BOSS_EMOTE = true, RAID_BOSS_WHISPER = true }
P.NPC_TYPES = NPC

---A creature's or boss's words with its name where the game marks the place ("%s attempts to run away in fear!").
---The game's own chat formats these lines with the name rather than showing them as typed (it leaves their % signs
---unescaped, unlike players' lines); a %% is a percent sign. Anything else is left as it came.
function P.NPCText(r, name)
  local msg = r.text
  if type(msg) ~= "string" or Hidden(msg) or not NPC[r.type] or not msg:find("%", 1, true) then return msg end
  name = name or P.Core.Names.Full(r.who) or r.who or ""
  if Hidden(name) then return msg end
  return (msg:gsub("%%([s%%])", function(c) if c == "s" then return name end return "%" end))
end

-- chat types whose lines from one person run together (the name and time show once); emotes need their name
P.RUNS = { SAY = true, YELL = true, GUILD = true, OFFICER = true, PARTY = true, PARTY_LEADER = true, RAID = true,
  RAID_LEADER = true, INSTANCE_CHAT = true, INSTANCE_CHAT_LEADER = true, WHISPER = true, CHANNEL = true,
  GUILD_DISCORD = true, BN_WHISPER = true }

-- your first name, in Parley's colour, where someone says it (not inside links or coloured text)
local mePattern, meFor
local function highlightMe(msg)
  local me = P.Core.Names.First(P.Me())
  if type(me) ~= "string" or #me < 2 or msg:find("|", 1, true) then return msg end
  if me ~= meFor then
    meFor = me
    local p = me:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%a", function(c) return "[" .. c:upper() .. c:lower() .. "]" end)
    mePattern = "%f[%w]" .. p .. "%f[^%w]"
  end
  return (msg:gsub(mePattern, WHY .. "%0|r"))
end

local function plainBody(r, cont, you)
  local t = r.type
  local msg = r.text or ""
  if SENDERLESS[t] or not r.hasWho then
    if t == "CHANNEL_LIST" and (r.chanString or r.chanName) then
      return "[" .. (r.chanString or r.chanName) .. "] " .. msg   -- /chatlist: who's in which channel
    end
    if t == "CHANNEL_NOTICE" or t == "CHANNEL_NOTICE_USER" then
      local fmt = rawget(_G, "CHAT_" .. tostring(msg) .. "_NOTICE")
      if type(fmt) == "string" then
        -- the game fills these with the channel's number and its full label, as Blizzard's own chat does
        local ok, out = pcall(string.format, fmt, r.num or 0, r.chanString or r.chanName or "", r.who or "")
        if ok then return out end
      end
    end
    return msg
  end
  if NPC[t] then
    local fmt = rawget(_G, "CHAT_" .. t .. "_GET") or "%s: "
    local name = P.Core.Names.Full(r.who) or r.who
    msg = P.NPCText(r, name)
    local ok, out = pcall(string.format, fmt .. escape(icons(r, msg)), name, name)
    return ok and out or (name .. ": " .. msg)
  end
  if t == "ACHIEVEMENT" or t == "GUILD_ACHIEVEMENT" then
    local ok, out = pcall(string.format, msg, playerLink(r))
    return ok and out or msg
  end
  if P.TALK[r.kind] or r.chan then
    if not r.mine then msg = highlightMe(msg) end
  end
  msg = P.QuestLinks(P.Linkify(icons(r, msg)))
  if r.lang and r.lang ~= "" and r.lang ~= P.language then msg = "[" .. r.lang .. "] " .. msg end
  if you then
    -- in a conversation you know who it's with: a green > for their lines, a red < for yours, no names
    if P.WHISPER_OUT[t] then return P.Explained("sent", BAD .. "<|r") .. " " .. msg end
    return P.Explained("got", GOOD .. ">|r") .. " " .. msg
  end
  if cont then return msg end   -- a run-together line: the name showed on the line above
  local link = playerLink(r)
  local flag = ""
  if r.flag and r.flag ~= "" and ChatFrameUtil and ChatFrameUtil.GetPFlag then
    local ok, f = pcall(ChatFrameUtil.GetPFlag, r.flag, r.zoneID or 0, chanNum(r) or 0)
    if ok and f then flag = f end
  end
  flag = flag .. P.PlayerIcons(r.guid)
  if t == "TEXT_EMOTE" then
    local name = r.who
    local s, e = msg:find(name, 1, true)
    if s then return msg:sub(1, s - 1) .. flag .. link .. msg:sub(e + 1) end
    return msg
  end
  if t == "EMOTE" then return flag .. link .. " " .. msg end
  if P.WHISPER_OUT[t] then return L.to:format(flag .. link) .. ": " .. msg end
  if t == "AFK" or t == "DND" then
    local fmt = rawget(_G, "CHAT_" .. t .. "_GET")
    if type(fmt) == "string" then
      local ok, out = pcall(string.format, fmt .. escape(msg), flag .. link)
      if ok then return out end
    end
  end
  return flag .. link .. ": " .. msg
end

local function heldBody(r)
  local msg = icons(r, r.text)
  if not r.hasWho or r.type == "TEXT_EMOTE" or SENDERLESS[r.type] then return msg end
  local link = playerLink(r)
  if r.type == "EMOTE" then return link .. " " .. msg end
  if P.WHISPER_OUT[r.type] then return L.to:format(link) .. ": " .. msg end
  return link .. ": " .. msg
end

---The pieces of a line in order: the bar first (the mock-up), or, with "Bar between the chat and the sender", after
---the time and the chat's short name, separating them from who's talking.
local function assemble(barText, stampText, tagText, rest)
  if P.db.barPlace == "middle" then return stampText .. tagText .. barText .. rest end
  return barText .. stampText .. tagText .. rest
end

---The text and colour of a record in a tab.
function P:Format(r, tab, cont)
  local h = self.SizeFor and self:SizeFor(tab) or self.db.font or 13   -- the window's text size
  self.curSize = h
  local cr, cg, cb = r.cr, r.cg, r.cb
  if not cr then cr, cg, cb = P.KindColor(r.kind) end
  local lr, lg, lb = cr, cg, cb
  local words = r.typeColor
  if r.restored and r.chan and ChatTypeInfo then words = ChatTypeInfo["CHANNEL" .. (chanNum(r) or "")] end
  if words then lr, lg, lb = words.r, words.g, words.b end
  -- the line reads bar, time, then the words (as in the mock-up). A held line reads the same, with no mark of its own
  -- (Maro, 23 Nov); it gets its class colour when it's read again after the fight.
  if r.held then
    local ok, body = pcall(heldBody, r)
    if not ok then return nil end
    return assemble(bar(cr, cg, cb, h, r.kind, r.from), stamp(r.t), tag(r, tab), body), lr, lg, lb
  end
  local body = (self.db.tidy and r.tidy and self.TidyText and self:TidyText(r))
    or plainBody(r, cont, tab and tab.special == "convos")
  body = P.LowerIcons(body)
  local tail = ""
  if r.count and r.count > 1 then tail = " " .. P.FoldPill(r.count) end
  if r.why and tab and tab.special == "foryou" then tail = tail .. " " .. WHY .. "\194\183 " .. r.why .. "|r" end
  if r.why and tab and tab.special ~= "foryou" and r.kind ~= "WHISPER" then
    cr, cg, cb = P.KindColor("FORYOU")   -- the bar turns Parley's colour when a line is for you
  end
  if r.jumped then
    -- the line a search result jumped to: Parley's colour for a few seconds, the bar and the words
    cr, cg, cb = P.KindColor("FORYOU")
    lr, lg, lb = cr, cg, cb
  end
  if cont then
    -- the time's room left empty and the words a little in, under the line that named the person (the mock-up's .cont)
    local pad = self.db.time and (self.contPad or "") or ""
    return assemble(bar(cr, cg, cb, h, r.kind, r.from), pad, "   ", body .. tail), lr, lg, lb
  end
  return assemble(bar(cr, cg, cb, h, r.kind, r.from), stamp(r.t), tag(r, tab), body .. tail), lr, lg, lb
end

-- The repeat count as the mock-up's outlined pill: drawn ones for x2 to x19 and 20+ (media/fold-*.tga, 64 x 32 with the
-- pill at the left; its width depends on how many characters it has).
local PILL_W = { 38, 46, 59 }
function P.FoldPill(n)
  local h = P.LineSize()
  local key, w = n, n < 10 and PILL_W[1] or PILL_W[2]
  if n >= 20 then key, w = "more", PILL_W[3] end
  local shown = math.floor(h * w / 32 + .5)
  return ("|T%sfold-%s:%d:%d:0:%d:64:32:0:%d:0:32|t"):format(P.MEDIA, key, h, shown, P.IconDrop(), w)
end

---The divider over the lines that came in while you were away (the mock-up's "New since you looked").
function P:NewSinceText()
  return WHY .. "\226\128\148\226\128\148  " .. L.newSince .. "  \226\128\148\226\128\148|r"
end

---The text a held line shows when the message frame refuses hidden text (probe test 2 failing).
function P:Placeholder(r, tab)
  local h = self.SizeFor and self:SizeFor(tab) or self.db.font or 13
  self.curSize = h
  local cr, cg, cb = P.KindColor(r.kind)
  return bar(cr, cg, cb, h) .. stamp(r.t) .. "|T" .. P.MEDIA .. "held:" .. h .. ":" .. h .. ":0:" .. P.IconDrop() .. "|t "
    .. FAINT .. L.heldPlaceholder:format(P.KindLabel(r.kind)) .. "|r", cr, cg, cb
end

---A faint rule of text across a tab ("Earlier").
function P:RuleText(text)
  return FAINT .. "\226\128\148 " .. text .. " \226\128\148|r"
end

P:OnReady(function()
  P.language = GetDefaultLanguage and GetDefaultLanguage() or nil
end)
