-- The kinds of chat a tab can mix, their colours and short names, and the channels Parley has seen.
-- A kind is a chat (GUILD, WHISPER, LOOT...) or one channel ("#lookingforgroup"). Channels are keyed by their own name,
-- not their number, so a channel that moves from 5 to 6 keeps its short name, and zone channels (General - Elwynn
-- Forest) share one key for every zone.

local P = Parley
if not P or P.disabled then return end
local L = P.L

-- chat type (the event name after CHAT_MSG_) -> kind
P.KIND_OF = {
  SAY = "SAY", YELL = "YELL", EMOTE = "EMOTE", TEXT_EMOTE = "EMOTE",
  GUILD = "GUILD", GUILD_DISCORD = "GUILD", GUILD_ACHIEVEMENT = "GUILD", GUILD_ITEM_LOOTED = "GUILD", OFFICER = "OFFICER",
  PARTY = "PARTY", PARTY_LEADER = "PARTY", PARTY_GUIDE = "PARTY",
  RAID = "RAID", RAID_LEADER = "RAID", RAID_WARNING = "RAID",
  INSTANCE_CHAT = "INSTANCE", INSTANCE_CHAT_LEADER = "INSTANCE",
  WHISPER = "WHISPER", WHISPER_INFORM = "WHISPER", AFK = "WHISPER", DND = "WHISPER",
  BN_WHISPER = "WHISPER", BN_WHISPER_INFORM = "WHISPER", BN_WHISPER_PLAYER_OFFLINE = "WHISPER",   -- Battle.net friends
  BN_INLINE_TOAST_ALERT = "SYSTEM", BN_INLINE_TOAST_BROADCAST = "SYSTEM", BN_INLINE_TOAST_BROADCAST_INFORM = "SYSTEM",
  LOOT = "LOOT", CURRENCY = "LOOT", MONEY = "MONEY",
  COMBAT_XP_GAIN = "XP", COMBAT_HONOR_GAIN = "XP", COMBAT_FACTION_CHANGE = "XP", SKILL = "XP", COMBAT_MISC_INFO = "XP",
  TRADESKILLS = "CRAFT", OPENING = "CRAFT",
  SYSTEM = "SYSTEM", CHANNEL_NOTICE = "SYSTEM", CHANNEL_NOTICE_USER = "SYSTEM", CHANNEL_LIST = "SYSTEM", ACHIEVEMENT = "SYSTEM",
  IGNORED = "SYSTEM", FILTERED = "SYSTEM", RESTRICTED = "SYSTEM", TARGETICONS = "SYSTEM", PET_INFO = "SYSTEM",
  BG_SYSTEM_NEUTRAL = "SYSTEM", BG_SYSTEM_ALLIANCE = "SYSTEM", BG_SYSTEM_HORDE = "SYSTEM",
  MONSTER_SAY = "MONSTER", MONSTER_YELL = "MONSTER", MONSTER_EMOTE = "MONSTER", MONSTER_WHISPER = "MONSTER",
  MONSTER_PARTY = "MONSTER", RAID_BOSS_EMOTE = "MONSTER", RAID_BOSS_WHISPER = "MONSTER",
  CHANNEL = "CHANNEL",
}

-- the order chats appear in pickers
P.KINDS = { "SAY", "YELL", "EMOTE", "GUILD", "OFFICER", "PARTY", "RAID", "INSTANCE", "WHISPER", "LOOT", "MONEY", "XP",
  "CRAFT", "SYSTEM", "MONSTER", "ADDONS" }

-- kinds that are people talking (mentions, alerts and folding look at these; never at loot or system lines)
P.TALK = { SAY = true, YELL = true, EMOTE = true, GUILD = true, OFFICER = true, PARTY = true, RAID = true,
  INSTANCE = true, WHISPER = true }
-- kinds saved to history (public channels never are)
P.KEEP = { WHISPER = true, GUILD = true, OFFICER = true, PARTY = true, RAID = true, INSTANCE = true, FORYOU = true }

-- the chat type whose colour a kind shows
local COLOR_TYPE = { SAY = "SAY", YELL = "YELL", EMOTE = "EMOTE", GUILD = "GUILD", OFFICER = "OFFICER", PARTY = "PARTY",
  RAID = "RAID", INSTANCE = "INSTANCE_CHAT", WHISPER = "WHISPER", LOOT = "LOOT", MONEY = "MONEY", XP = "COMBAT_XP_GAIN",
  CRAFT = "TRADESKILLS", SYSTEM = "SYSTEM", MONSTER = "MONSTER_SAY", ADDONS = "SYSTEM" }

-- [channel key] = its number now (from events and the channel list; numbers change, keys don't)
P.chanNum = {}

---The key and display name of a channel from its own name ("Trade - City" gives "#trade", "Trade").
function P.ChannelKey(name)
  if type(name) ~= "string" or name == "" or P.Hidden(name) then return nil end
  name = name:gsub("^%d+%.%s*", "")
  local base = name:match("^(.-)%s+%-%s+.+$") or name
  return "#" .. base:lower(), base
end

function P.IsChannel(key) return type(key) == "string" and key:sub(1, 1) == "#" end

---Remember a channel's name and number, as seen in a line or the channel list.
function P:SeeChannel(name, num)
  local key, base = P.ChannelKey(name)
  if not key then return nil end
  if type(num) == "number" and num > 0 and self.chanNum[key] ~= num then
    self.chanNum[key] = num
    -- other characters' lines take this one's numbers and colours, which may only now be known
    if self.db.shareHistory and self.sessionStart and time() - self.sessionStart < 60 and self.RedrawSoon then self:RedrawSoon() end
  end
  if self.db then
    self.db.chanNames[key] = base
    self.db.seen[key] = true
  end
  return key
end

function P:ScanChannels()
  if not GetChannelList then return end
  local list = { GetChannelList() }
  for i = 1, #list, 3 do
    local num, name = list[i], list[i + 1]
    if type(num) == "number" and type(name) == "string" then self:SeeChannel(name, num) end
  end
end

local MAX_SHORT = 20

---A channel shows its own full name (LookingForGroup, Trade) unless the player gives it a short one; chats keep their
---letter (S, G, P).
function P.DefaultShort(key)
  if not P.IsChannel(key) then return L.short[key] or key end
  return (P.db and P.db.chanNames[key]) or key:sub(2)
end

function P.Short(key)
  return (P.db and P.db.short[key]) or P.DefaultShort(key)
end

function P.KindLabel(key)
  if P.IsChannel(key) then return (P.db and P.db.chanNames[key]) or key:sub(2) end
  if key == "FORYOU" then return L.tab.foryou end
  return L.kind[key] or key
end

---Set or clear (empty text) a channel's short name. typing: the lines follow as you type (a moment after), and the
---command waits until you're done, so /l, /lf and /lfg don't all become commands on the way to LFG.
function P:SetShort(key, text, typing)
  text = (text or ""):gsub("[%c|]", ""):match("^%s*(.-)%s*$")
  if text == "" or text == P.DefaultShort(key) then text = nil else text = text:sub(1, MAX_SHORT) end
  self.db.short[key] = text
  if typing then
    if self.RedrawSoon then self:RedrawSoon() end
    return
  end
  self:RegisterChannelCommand(key)
  if self.RedrawAll then self:RedrawAll() end
end

local WHITE = { r = 1, g = 1, b = 1 }
function P.KindColor(key)
  local info
  if P.IsChannel(key) then
    local num = P.chanNum[key]
    info = num and ChatTypeInfo and ChatTypeInfo["CHANNEL" .. num]
    if not info then info = ChatTypeInfo and ChatTypeInfo.CHANNEL end
  elseif key == "FORYOU" then
    local c = P.UI.Hex(P.ACCENT_HEX)
    return c[1], c[2], c[3]
  elseif key == "ADDONS" then
    local c = P.UI.C.muted   -- a quiet bar: add-ons print in every colour, so the bar doesn't take one of theirs
    return c[1], c[2], c[3]
  else
    info = ChatTypeInfo and ChatTypeInfo[COLOR_TYPE[key] or key]
  end
  info = info or WHITE
  return info.r or 1, info.g or 1, info.b or 1
end

---Every kind a picker should offer: the chats, then the channels seen, by name.
function P:PickerKinds()
  local out = {}
  for _, k in ipairs(self.KINDS) do out[#out + 1] = k end
  local chans = {}
  for key in pairs(self.db.chanNames) do chans[#chans + 1] = key end
  table.sort(chans, function(a, b) return P.KindLabel(a):lower() < P.KindLabel(b):lower() end)
  for _, k in ipairs(chans) do out[#out + 1] = k end
  return out
end

-------------------------------------------------------------------------------------------
-- Each channel's short name is also a command (/glo hello), if nothing else uses it
-------------------------------------------------------------------------------------------

local used           -- [ "/x" ] = true for every slash command the game and add-ons have, built once
local mine = {}      -- [ "/x" ] = channel key, for Parley's own

local function buildUsed()
  used = {}
  for k, v in pairs(_G) do
    if type(k) == "string" and type(v) == "string" and k:sub(1, 6) == "SLASH_" and k:sub(1, 14) ~= "SLASH_PARLEYCH" then
      used[v:lower()] = true
    end
  end
end

local function send(key, msg)
  local num = P.chanNum[key]
  if not num and GetChannelName then
    local n = GetChannelName((P.db.chanNames[key] or key:sub(2)))
    if type(n) == "number" and n > 0 then num = n end
  end
  if not num then return end
  msg = msg or ""
  if msg:match("^%s*$") then
    -- nothing to say: open the chat box on the channel once the game has closed it
    C_Timer.After(0, function() ChatFrameUtil.OpenChat("/" .. num .. " ") end)
    return
  end
  local say = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  say(msg, "CHANNEL", nil, num)
end

---Make /<short name> send to the channel. Returns "ok", "taken" or nil (not a channel).
function P:RegisterChannelCommand(key, quiet)
  if not P.IsChannel(key) or not SlashCmdList then return nil end
  if not used then buildUsed() end
  local cmd = "/" .. P.Short(key):lower()
  if not cmd:match("^/[%w]+$") then return "taken" end
  if mine[cmd] == key then return "ok" end
  if used[cmd] or mine[cmd] then
    if not quiet then self:Print(P.L.commandTaken:format(cmd:sub(2))) end
    return "taken"
  end
  local id = "PARLEYCH" .. cmd:sub(2):upper()
  _G["SLASH_" .. id .. "1"] = cmd
  SlashCmdList[id] = function(msg) send(key, msg) end
  mine[cmd] = key
  return "ok"
end

function P:CommandState(key)
  local cmd = "/" .. P.Short(key):lower()
  if mine[cmd] == key then return "ok", cmd end
  return "taken", cmd
end

P:OnReady(function()
  if not P.db.takeover then return end
  P.Core:OnLogin(function()
    P:ScanChannels()
    for key in pairs(P.db.chanNames) do P:RegisterChannelCommand(key, true) end
  end)
  for _, event in ipairs({ "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE" }) do
    P.Core:On(event, "parley.channels", function()
      P:ScanChannels()
      for key in pairs(P.db.chanNames) do P:RegisterChannelCommand(key, true) end
    end)
  end
end)
