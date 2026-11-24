-- Battle.net friends: their whispers, their coming online and going offline, their broadcasts.
-- The game names a Battle.net friend with a token ("|Kq12|k") that only a font string can turn into their name, and
-- that names someone else, or no one, after a reload. Their BattleTag is plain text and stays theirs. So a line keeps
-- the token to show this session, and the BattleTag for history and for which conversation it belongs to.
-- Their whispers are whispers: the same Whispers tab, conversations, notes and history as a character's, with the name
-- in the game's Battle.net blue.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local Hidden = P.Hidden

-- chat types from Battle.net (the event name after CHAT_MSG_); the whispers are routed as whispers, the rest are notices
P.BN = { BN_WHISPER = true, BN_WHISPER_INFORM = true, BN_WHISPER_PLAYER_OFFLINE = true, BN_INLINE_TOAST_ALERT = true,
  BN_INLINE_TOAST_BROADCAST = true, BN_INLINE_TOAST_BROADCAST_INFORM = true }
P.BN_NOTICE = { BN_WHISPER_PLAYER_OFFLINE = true, BN_INLINE_TOAST_ALERT = true, BN_INLINE_TOAST_BROADCAST = true,
  BN_INLINE_TOAST_BROADCAST_INFORM = true }
-- whispers coming in and going out, from characters and Battle.net friends alike
P.WHISPER_IN = { WHISPER = true, BN_WHISPER = true }
P.WHISPER_OUT = { WHISPER_INFORM = true, BN_WHISPER_INFORM = true }

local function api() return rawget(_G, "C_BattleNet") end

---A Battle.net friend's account, by the id the game gives them this session.
function P.BNAccount(id)
  local bn = api()
  if not (bn and bn.GetAccountInfoByID) or type(id) ~= "number" then return nil end
  local ok, info = pcall(bn.GetAccountInfoByID, id)
  if ok and type(info) == "table" then return info end
end

local byTag   -- [lower BattleTag] = account id, read again when the friends list changes
local function readFriends()
  byTag = {}
  local bn = api()
  if not (bn and bn.GetFriendAccountInfo and BNGetNumFriends) then return end
  local ok, n = pcall(BNGetNumFriends)
  for i = 1, (ok and tonumber(n)) or 0 do
    local ok2, info = pcall(bn.GetFriendAccountInfo, i)
    if ok2 and type(info) == "table" and type(info.battleTag) == "string" and type(info.bnetAccountID) == "number" then
      byTag[info.battleTag:lower()] = info.bnetAccountID
    end
  end
end

---A friend's account by their BattleTag, while they're on your friends list.
function P.BNByTag(tag)
  if type(tag) ~= "string" then return nil end
  if not byTag then readFriends() end
  local id = byTag[tag:lower()]
  return id and P.BNAccount(id)
end

---The account id behind a token: the one the line came with, or the game's own lookup by the token.
local function idOf(token, given)
  if not Hidden(given) and type(given) == "number" and given > 0 then return given end
  local get = rawget(_G, "BNet_GetBNetIDAccount")
  if get and type(token) == "string" and not Hidden(token) and token ~= "" then
    local ok, id = pcall(get, token)
    if ok and type(id) == "number" then return id end
  end
end

---The conversation key for a Battle.net friend.
function P.BNKey(tagOrToken) return "bn:" .. tagOrToken:lower() end

---The game's Battle.net blue, as a colour code.
function P.BNColor()
  local code = rawget(_G, "FRIENDS_BNET_NAME_COLOR_CODE")
  if type(code) == "string" then return code end
  local c = ChatTypeInfo and ChatTypeInfo.BN_WHISPER
  return c and ("|c" .. P.Hex(c.r, c.g, c.b)) or "|cffffffff"
end

-- the bar takes the chat's own colour: Battle.net lines read as Battle.net in every tab
local function tint(r)
  local c = ChatTypeInfo and ChatTypeInfo[r.type]
  if c then r.cr, r.cg, r.cb = c.r, c.g, c.b end
end

---A whisper from or to a Battle.net friend: the token to show, the account id and the BattleTag.
function P:BNLine(r, token, id)
  r.bn = true
  r.bnID = idOf(token, id)
  local info = r.bnID and P.BNAccount(r.bnID)
  if info and type(info.battleTag) == "string" then
    r.bnTag = info.battleTag
    if not byTag then readFriends() end
    byTag[r.bnTag:lower()] = r.bnID
  end
  tint(r)
end

---A Battle.net line from history: its BattleTag finds the friend again, and the token that names them this session.
---Someone no longer on the list shows the name part of their BattleTag, without a link.
function P:BNRestore(r)
  if r.bn or not P.BN[r.type] then return end
  r.bn = true
  if type(r.who) == "string" and r.who ~= "" then
    r.bnTag = r.who
    local info = P.BNByTag(r.who)
    if info and type(info.accountName) == "string" then
      r.bnID, r.who = info.bnetAccountID, info.accountName
    else
      r.who = r.bnTag:match("^(.-)#%d+$") or r.bnTag
    end
  end
  tint(r)
end

---A Battle.net friend's name as a link (click to whisper them, right-click for the game's menu about them).
function P.BNLink(r, text)
  if r.held then
    -- `..` only: the token stays hidden inside the link and the game shows it
    return "|HBNplayer:" .. r.who .. ":" .. (r.bnID or 0) .. ":" .. (r.lineID or 0) .. ":BN_WHISPER:" .. r.who .. "|h"
      .. P.BNColor() .. r.who .. "|r|h"
  end
  text = text or (P.BNColor() .. r.who .. "|r")
  if not r.bnID then return text end
  if GetBNPlayerLink then
    local ok, link = pcall(GetBNPlayerLink, r.who, text, r.bnID, r.lineID or 0, "BN_WHISPER", r.who)
    if ok and type(link) == "string" then return link end
  end
  return "|HBNplayer:" .. r.who .. ":" .. r.bnID .. ":" .. (r.lineID or 0) .. ":BN_WHISPER:" .. r.who .. "|h" .. text .. "|h"
end

---The character a friend is on in a WoW game, when they are.
local function character(info)
  local game = info and type(info.gameAccountInfo) == "table" and info.gameAccountInfo
  if not (game and game.isOnline and game.clientProgram == rawget(_G, "BNET_CLIENT_WOW")) then return nil, game end
  if type(game.characterName) ~= "string" or game.characterName == "" then return nil, game end
  return game.characterName, game
end

-- [token] = account id, for the names in "came online" lines
local people = {}

---A friend's name in a tidy line: the link, then the character they're on, faintly ("Maro (Elowen Brightwater)").
function P.BNPerson(token)
  local id = people[token]
  if not id then return nil end
  local name = P.BNLink({ who = token, bnID = id })
  local char = character(P.BNAccount(id))
  if char then name = name .. " |cff6e6552(" .. char .. ")|r" end
  return name
end

---Open the chat box on a whisper to a Battle.net friend, the game's own way. Returns false when they can't be found.
function P.BNTell(id, token)
  if type(id) == "number" then
    local info = P.BNAccount(id)
    if info and type(info.accountName) == "string" then token = info.accountName end
  end
  if type(token) ~= "string" or Hidden(token) or token == "" then return false end
  local util = rawget(_G, "ChatFrameUtil")
  if not (util and util.SendBNetTell) then return false end
  util.SendBNetTell(token)
  return true
end

---The account id of the friend behind a conversation, found again by BattleTag when the one kept is from before a reload.
function P.BNPersonID(c)
  local id = c.bnID
  if not P.BNAccount(id) and c.bnTag then
    local info = P.BNByTag(c.bnTag)
    id = info and info.bnetAccountID
    c.bnID = id
  end
  return id
end

---Open a whisper to the friend behind a conversation.
function P.BNTellPerson(c)
  return P.BNTell(P.BNPersonID(c))
end

---Who a Battle.net friend is right now, for a conversation's header: the character they're on, its level and class,
---and where; or what the game says they're doing; or offline.
function P:BNInfo(c)
  local info = c.bnID and P.BNAccount(c.bnID)
  if not info and c.bnTag then info = P.BNByTag(c.bnTag) end
  local parts = { L.bnet }
  if not info then return table.concat(parts, " \194\183 "), nil end
  local char, game = character(info)
  local online = game and game.isOnline and true or false
  if char then
    parts[#parts + 1] = char
    if type(game.characterLevel) == "number" and game.characterLevel > 0 and type(game.className) == "string" then
      parts[#parts + 1] = L.levelClass:format(game.characterLevel, game.className)
    end
  end
  parts[#parts + 1] = online and L.online or L.offline
  if online then
    local where = char and game.areaName or (game and game.richPresence)
    if type(where) == "string" and where ~= "" then parts[#parts + 1] = where end
  end
  return table.concat(parts, " \194\183 "), online
end

-------------------------------------------------------------------------------------------
-- Notices: a friend came online or went offline, changed their broadcast, or a whisper didn't reach them
-------------------------------------------------------------------------------------------

local ONLINE = { FRIEND_ONLINE = "online", FRIEND_OFFLINE = "offline" }
P.bnLate = {}   -- [chat type id] = until when the game's own copy of a notice may still arrive (it waits for an icon)

local function fmt(pattern, ...)
  if type(pattern) ~= "string" then return nil end
  local ok, out = pcall(string.format, pattern, ...)
  return ok and out or nil
end

---Turn a Battle.net notice into a finished line. The game's own words where it has them. Returns false to drop it.
function P:BNNotice(r, id)
  local t, what, token = r.type, r.text, r.who
  if type(token) ~= "string" then token = "" end
  r.bn = true
  r.bnID = idOf(token, id)
  r.hasWho = false   -- a sentence about someone, not someone talking
  tint(r)
  local link = token ~= "" and P.BNLink(r) or ""
  local text
  if t == "BN_INLINE_TOAST_ALERT" then
    if type(what) ~= "string" then return false end
    local pattern = rawget(_G, "BN_INLINE_TOAST_" .. what)
    if what == "FRIEND_REQUEST" then
      text = type(pattern) == "string" and pattern or nil
    elseif what == "FRIEND_PENDING" then
      local ok, n = pcall(BNGetNumFriendInvites)
      text = fmt(pattern, ok and tonumber(n) or 0)
    else
      if ONLINE[what] and token ~= "" and r.bnID then
        people[token] = r.bnID
        r.tidy = { what = ONLINE[what], who = token }
        if r.typeColor and r.typeColor.id then P.bnLate[r.typeColor.id] = GetTime() + 2 end
        text = fmt(pattern, P.BNPerson(token) or link)
      else
        text = fmt(pattern, link)
      end
    end
    if what == "FRIEND_ADDED" or what == "FRIEND_REMOVED" or what == "BATTLETAG_FRIEND_ADDED"
      or what == "BATTLETAG_FRIEND_REMOVED" then
      byTag = nil   -- the list changed
    end
  elseif t == "BN_INLINE_TOAST_BROADCAST" then
    if type(what) ~= "string" or what == "" then return false end
    text = fmt(rawget(_G, "BN_INLINE_TOAST_BROADCAST"), link, (what:gsub("%s+", " ")))
  elseif t == "BN_INLINE_TOAST_BROADCAST_INFORM" then
    if type(what) ~= "string" or what == "" then return false end
    text = rawget(_G, "BN_INLINE_TOAST_BROADCAST_INFORM")
  elseif t == "BN_WHISPER_PLAYER_OFFLINE" then
    -- in the conversation with them
    text = L.bnOffline:format(token ~= "" and link or L.bnFriend)
    local info = r.bnID and P.BNAccount(r.bnID)
    r.bnTag = info and type(info.battleTag) == "string" and info.battleTag or nil
    if r.bnTag or token ~= "" then r.convoKey = P.BNKey(r.bnTag or token) end
  end
  if type(text) ~= "string" then return false end
  r.text = text
  if t ~= "BN_WHISPER_PLAYER_OFFLINE" then r.who = nil end
  return true
end

P:OnReady(function()
  if not P.db.takeover then return end
  for _, event in ipairs({ "BN_FRIEND_LIST_SIZE_CHANGED", "BN_CONNECTED" }) do
    P.Core:On(event, "parley.bnet", function() byTag = nil end)
  end
end)
