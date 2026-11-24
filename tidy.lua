-- Tidy lines: money, loot, rolls, experience, reputation, skills and people coming online, all in one short shape:
-- an icon, who, then what. "Elowen Brightwater: 12g 40s", "Elowen Brightwater: [Arcanite Bar] | Need 87". The highest roll on an item
-- shows green and the rest grey; when someone rolls higher, the old leader's line turns grey in place.
-- Every pattern is made from the game's own message string (LOOT_ITEM, LOOT_ROLL_ROLLED_NEED...), so it matches what the
-- client prints, in its language. A line no pattern matches stays as the game wrote it.

local P = Parley
if not P or P.disabled then return end
local L = P.L
local Core = P.Core
local Hidden = P.Hidden

local ICON = P.MEDIA .. "tidy-"
local GREEN, GREY, FAINT, RED = "|cff8fe08f", "|cff8f8672", "|cff6e6552", "|cffff9478"

-------------------------------------------------------------------------------------------
-- A game format string as a Lua pattern: "%s receives loot: %sx%d." -> captures, and which argument each one is
-------------------------------------------------------------------------------------------

local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?]"
---Returns the pattern, the argument each capture is, and the arguments that sit inside a link's hidden part (the
---|Hkind:...|h of "|HlootHistory:%d|h[Loot]|h: ..."), which the reader shows nobody.
function P.CompileFormat(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local out, order, links, auto, i, inLink = {}, {}, {}, 0, 1, false
  while i <= #fmt do
    local s, e, pos, kind = fmt:find("^%%(%d*)%$?([sd])", i)
    local two = fmt:sub(i, i + 1)
    if s then
      if pos == "" then auto = auto + 1; pos = auto else pos = tonumber(pos) end
      order[#order + 1] = pos
      if inLink then links[pos] = true end
      out[#out + 1] = kind == "d" and "([%-%d,]+)" or "(.-)"
      i = e + 1
    elseif two == "%%" then
      out[#out + 1] = "%%"
      i = i + 2
    elseif two == "|H" or two == "|h" then
      inLink = two == "|H"
      out[#out + 1] = two
      i = i + 2
    else
      local c = fmt:sub(i, i)
      out[#out + 1] = c:find(MAGIC) and ("%" .. c) or c
      i = i + 1
    end
  end
  return "^" .. table.concat(out) .. "$", order, links
end

-- roles: what each argument the form names is, in the string's argument order. On WoW Forever most roll lines start
-- with "|HlootHistory:%d|h[Loot]|h: ", a link holding the roll's number, and a few don't; an argument hidden in a link
-- that the form doesn't name is set aside as the line's link id, so both shapes read the same.
local function matcher(name, roles)
  local fmt = rawget(_G, name)
  local pat, order, links = P.CompileFormat(fmt)
  if not pat then return nil end
  local positions, seen = {}, {}
  for _, pos in ipairs(order) do
    if not seen[pos] then seen[pos] = true; positions[#positions + 1] = pos end
  end
  table.sort(positions)
  local spare = #positions - #roles   -- more than that is fine: "(%s deposited to guild bank)" goes unread
  local slot, linkPos, n = {}, nil, 0
  for _, pos in ipairs(positions) do
    if spare > 0 and links[pos] then
      spare = spare - 1
      linkPos = linkPos or pos
    else
      n = n + 1
      slot[pos] = n
    end
  end
  return function(text)
    local caps = { text:match(pat) }
    if caps[1] == nil then return nil end
    local args = {}
    for k, pos in ipairs(order) do
      if slot[pos] then args[slot[pos]] = caps[k] elseif pos == linkPos then args.link = caps[k] end
    end
    return args
  end
end

-- a read that put the pieces in the wrong places (a number for a name, a link for a name) is no read at all
local ROLL_WHAT = { rolled = true, choice = true, won = true, allpassed = true, started = true }
local function sensible(f, a)
  for _, role in ipairs({ "roll", "n", "min", "max" }) do
    if a[role] and not tonumber((a[role]:gsub(",", ""))) then return false end
  end
  if a.who and (a.who == "" or a.who:find("|H", 1, true) or a.who:find("^[%d,]+$")) then return false end
  if a.item and a.item:find("^[%d,]+$") then return false end
  if ROLL_WHAT[f.what] and not (a.item and a.item:find("|H", 1, true)) then return false end   -- rolls are always on links
  -- "up for rolls" is the link and then only the item: anything more is a roll line Parley doesn't know
  if f.what == "started" and not (a.item:find("^|c[^|]*|H[^|]*|h%[[^%]]*%]|h|r$") or a.item:find("^|H[^|]*|h%[[^%]]*%]|h$")) then
    return false
  end
  return true
end

-- "You have rolled Greed - 43 for: ..." names the choice in the game's own word
local CHOICE_WORD = { NEED = "need", GREED = "greed", ROLL_DISENCHANT = "de", TRANSMOGRIFICATION = "transmog", PASS = "pass" }
local function choiceOf(word)
  for name, choice in pairs(CHOICE_WORD) do
    if rawget(_G, name) == word then return choice end
  end
end

-- [chat type] = { { game string, what it is, the role of each argument }, ... }; "self" ones are about you
local FORMS = {
  MONEY = {
    { "YOU_LOOT_MONEY", "money", { "money" }, me = true },
    { "LOOT_MONEY_SPLIT", "money", { "money" }, me = true },
    { "YOU_LOOT_MONEY_GUILD", "money", { "money" }, me = true },
    { "LOOT_MONEY_SPLIT_GUILD", "money", { "money" }, me = true },
    { "LOOT_MONEY", "money", { "who", "money" } },
  },
  LOOT = {
    { "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "rolled", { "roll", "item", "who" }, choice = "need" },
    { "LOOT_ROLL_ROLLED_NEED", "rolled", { "roll", "item", "who" }, choice = "need" },
    { "LOOT_ROLL_ROLLED_GREED", "rolled", { "roll", "item", "who" }, choice = "greed" },
    { "LOOT_ROLL_ROLLED_DE", "rolled", { "roll", "item", "who" }, choice = "de" },
    { "LOOT_ROLL_ROLLED_TRANSMOG", "rolled", { "roll", "item", "who" }, choice = "transmog" },
    -- the game's "only show the winner" loot option: the winner's line carries the roll, yours says what you rolled
    { "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "won", { "roll", "item" }, me = true, choice = "need" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_NEED_OFF_SPEC", "won", { "roll", "item" }, me = true, choice = "need" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "won", { "roll", "item" }, me = true, choice = "greed" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_DE", "won", { "roll", "item" }, me = true, choice = "de" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_TRANSMOG", "won", { "roll", "item" }, me = true, choice = "transmog" },
    { "LOOT_ROLL_WON_NO_SPAM_NEED", "won", { "who", "roll", "item" }, choice = "need" },
    { "LOOT_ROLL_WON_NO_SPAM_NEED_OFF_SPEC", "won", { "who", "roll", "item" }, choice = "need" },
    { "LOOT_ROLL_WON_NO_SPAM_GREED", "won", { "who", "roll", "item" }, choice = "greed" },
    { "LOOT_ROLL_WON_NO_SPAM_DE", "won", { "who", "roll", "item" }, choice = "de" },
    { "LOOT_ROLL_WON_NO_SPAM_TRANSMOGRIFICATION", "won", { "who", "roll", "item" }, choice = "transmog" },
    { "LOOT_ROLL_LOST_ROLL", "rolled", { "choice", "roll", "item" }, me = true },
    { "LOOT_ROLL_NEED_SELF", "choice", { "item" }, me = true, choice = "need" },
    { "LOOT_ROLL_GREED_SELF", "choice", { "item" }, me = true, choice = "greed" },
    { "LOOT_ROLL_DISENCHANT_SELF", "choice", { "item" }, me = true, choice = "de" },
    { "LOOT_ROLL_PASSED_SELF_AUTO", "choice", { "item" }, me = true, choice = "pass" },
    { "LOOT_ROLL_PASSED_SELF", "choice", { "item" }, me = true, choice = "pass" },
    { "LOOT_ROLL_NEED", "choice", { "who", "item" }, choice = "need" },
    { "LOOT_ROLL_GREED", "choice", { "who", "item" }, choice = "greed" },
    { "LOOT_ROLL_DISENCHANT", "choice", { "who", "item" }, choice = "de" },
    { "LOOT_ROLL_PASSED_AUTO_FEMALE", "choice", { "who", "item" }, choice = "pass" },
    { "LOOT_ROLL_PASSED_AUTO", "choice", { "who", "item" }, choice = "pass" },
    { "LOOT_ROLL_PASSED", "choice", { "who", "item" }, choice = "pass" },
    { "LOOT_ROLL_ALL_PASSED", "allpassed", { "item" } },
    { "LOOT_ROLL_YOU_WON", "won", { "item" }, me = true },
    { "LOOT_ROLL_WON", "won", { "who", "item" } },
    { "LOOT_ITEM_SELF_MULTIPLE", "loot", { "item", "n" }, me = true },
    { "LOOT_ITEM_SELF", "loot", { "item" }, me = true },
    { "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "loot", { "item", "n" }, me = true },
    { "LOOT_ITEM_PUSHED_SELF", "loot", { "item" }, me = true },
    { "LOOT_ITEM_CREATED_SELF_MULTIPLE", "loot", { "item", "n" }, me = true },
    { "LOOT_ITEM_CREATED_SELF", "loot", { "item" }, me = true },
    { "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "loot", { "item", "n" }, me = true },
    { "LOOT_ITEM_BONUS_ROLL_SELF", "loot", { "item" }, me = true },
    { "LOOT_ITEM_MULTIPLE", "loot", { "who", "item", "n" } },
    { "LOOT_ITEM", "loot", { "who", "item" } },
    { "LOOT_ITEM_PUSHED_MULTIPLE", "loot", { "who", "item", "n" } },
    { "LOOT_ITEM_PUSHED", "loot", { "who", "item" } },
    { "LOOT_ITEM_BONUS_ROLL_MULTIPLE", "loot", { "who", "item", "n" } },
    { "LOOT_ITEM_BONUS_ROLL", "loot", { "who", "item" } },
    { "LOOT_ROLL_STARTED", "started", { "item" } },   -- last: after its link it's only the item, so it'd match any roll line
  },
  TRADESKILLS = {
    { "TRADESKILL_LOG_FIRSTPERSON", "craft", { "item" }, me = true },
    { "TRADESKILL_LOG_THIRDPERSON", "craft", { "who", "item" } },
    { "CREATED_ITEM_MULTIPLE", "craft", { "who", "item", "n" } },
    { "CREATED_ITEM", "craft", { "who", "item" } },
  },
  OPENING = {   -- herbs, ore, chests and locks; read for who it was, and shown in the game's own words
    { "OPEN_LOCK_SELF", "open", { "spell", "target" }, me = true },
    { "OPEN_LOCK_OTHER", "open", { "who", "spell", "target" } },
  },
  CURRENCY = {
    { "CURRENCY_GAINED_MULTIPLE", "loot", { "item", "n" }, me = true },
    { "CURRENCY_GAINED", "loot", { "item" }, me = true },
  },
  COMBAT_XP_GAIN = {
    { "COMBATLOG_XPGAIN_EXHAUSTION1", "xp", { "mob", "n" } },
    { "COMBATLOG_XPGAIN_EXHAUSTION2", "xp", { "mob", "n" } },
    { "COMBATLOG_XPGAIN_EXHAUSTION4", "xp", { "mob", "n" } },
    { "COMBATLOG_XPGAIN_EXHAUSTION5", "xp", { "mob", "n" } },
    { "COMBATLOG_XPGAIN_FIRSTPERSON", "xp", { "mob", "n" } },
    { "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", "xp", { "n" } },
    { "COMBATLOG_XPGAIN_QUEST", "xp", { "n" } },
  },
  COMBAT_FACTION_CHANGE = {
    { "FACTION_STANDING_INCREASED", "rep", { "faction", "n" }, up = true },
    { "FACTION_STANDING_DECREASED", "rep", { "faction", "n" } },
    { "FACTION_STANDING_INCREASED_GENERIC", "rep", { "faction" }, up = true },
    { "FACTION_STANDING_DECREASED_GENERIC", "rep", { "faction" } },
  },
  SKILL = {
    { "SKILL_RANK_UP", "skill", { "skill", "n" } },
  },
  SYSTEM = {
    { "RANDOM_ROLL_RESULT", "random", { "who", "roll", "min", "max" } },
    { "ERR_FRIEND_ONLINE_SS", "online", { "who", "who2" } },
    { "ERR_FRIEND_OFFLINE_S", "offline", { "who" } },
    { "FACTION_STANDING_INCREASED", "rep", { "faction", "n" }, up = true },
    { "FACTION_STANDING_DECREASED", "rep", { "faction", "n" } },
    { "SKILL_RANK_UP", "skill", { "skill", "n" } },
  },
}

local compiled
local function compileAll()
  compiled = {}
  for ctype, forms in pairs(FORMS) do
    local list = {}
    for _, f in ipairs(forms) do
      local m = matcher(f[1], f[3])
      if m then list[#list + 1] = { match = m, what = f[2], roles = f[3], me = f.me, choice = f.choice, up = f.up } end
    end
    compiled[ctype] = list
  end
end

-------------------------------------------------------------------------------------------
-- Pieces
-------------------------------------------------------------------------------------------

local MONEY_PARTS
local function copperOf(text)
  if not MONEY_PARTS then
    MONEY_PARTS = {}
    for _, part in ipairs({ { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }) do
      local fmt = rawget(_G, part[1])
      if type(fmt) == "string" then
        local pat = fmt:gsub(MAGIC, "%%%0"):gsub("%%d", "(%%d+)")
        MONEY_PARTS[#MONEY_PARTS + 1] = { pat, part[2] }
      end
    end
  end
  local total, found = 0, false
  for _, part in ipairs(MONEY_PARTS) do
    local n = text:match(part[1])
    if n then total = total + tonumber(n) * part[2]; found = true end
  end
  return found and total or nil
end

local GOLD_C, SILVER_C, COPPER_C = "|cffe7c66c", "|cffc7c7c7", "|cffc7804d"   -- Fortune's coin colours
---"12g 40s" in coin colours: Fortune's own formatter when it's installed, the same style when it isn't.
function P.Money(copper)
  local fortune = rawget(_G, "Fortune")
  if type(fortune) == "table" and type(fortune.Money) == "function" then
    local ok, text = pcall(fortune.Money, copper)
    if ok and type(text) == "string" then return text end
  end
  local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
  if g > 0 and s == 0 then return GOLD_C .. g .. "g|r" end
  if g > 0 then return GOLD_C .. g .. "g|r " .. SILVER_C .. s .. "s|r" end
  if s > 0 and c > 0 and s < 10 then return SILVER_C .. s .. "s|r " .. COPPER_C .. c .. "c|r" end
  if s > 0 then return SILVER_C .. s .. "s|r" end
  return COPPER_C .. c .. "c|r"
end

-- the game's own icons where it has one players know: the backpack, the gold coin, the roll frame's dice, coin, shard
-- and cross; Parley's drawn ones for the rest
local GAME_ICON = {
  bag = "Interface\\Buttons\\Button-Backpack-Up", coin = "Interface\\MoneyFrame\\UI-GoldIcon",
  dice = "Interface\\Buttons\\UI-GroupLoot-Dice-Up", greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  started = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
  de = "Interface\\Buttons\\UI-GroupLoot-DE-Up", pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}

local function icon(name)
  local h = P.LineSize()
  local path = GAME_ICON[name] or (ICON .. name)
  return P.Explained(name, "|T" .. path .. ":" .. h .. ":" .. h .. ":0:" .. P.IconDrop() .. "|t") .. " "
end

-- a person's name as the rest of Parley shows it, in class colour when the game knows their class
local function person(who, me)
  if not me and who and P.BNPerson then
    local friend = P.BNPerson(who)   -- a Battle.net friend's token: their link and the character they're on
    if friend then return friend end
  end
  if me or not who then who = P.Me() end
  local full = Core.Names:Address(who) or Core.Names.Full(who) or who
  local shown = P.ShowName(full)
  local class
  if UnitClass then
    local ok, _, c = pcall(UnitClass, me and "player" or full)
    if ok then class = c end
  end
  local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  local hex = col and ((col.GenerateHexColor and col:GenerateHexColor()) or col.colorStr)
  if hex then shown = "|c" .. hex .. shown .. "|r" end
  return "|Hplayer:" .. full .. "|h" .. shown .. "|h"
end

-------------------------------------------------------------------------------------------
-- Reading a line, and tracking rolls
-------------------------------------------------------------------------------------------

local rolls = {}   -- ["roll:<the game's roll number>", or the item link, or "random:1-100"] = { at = time, best = record }
local ROLL_WINDOW, RANDOM_WINDOW = 600, 120

local function track(key, r, window)
  local t = rolls[key]
  if not t or (r.t or 0) - t.at > window then t = { at = r.t or 0 }; rolls[key] = t end
  t.at = r.t or t.at
  local best = t.best
  if not best or (r.tidy.roll or 0) > (best.tidy.roll or 0) then
    t.best = r
    r.tidy.lead = true
    if best then
      best.tidy.lead = false
      if P.Redraw then P:Redraw(best) end
    end
  end
end

---Read a plain system-ish line into r.tidy (who, what, item, amount, roll), if a pattern knows it.
function P:Tidy(r, quiet)
  if r.held or type(r.text) ~= "string" or Hidden(r.text) then return end
  if not compiled then compileAll() end
  local list = compiled[r.type]
  if not list then return end
  for _, f in ipairs(list) do
    local caps = f.match(r.text)
    local a = {}
    if caps then
      for i, role in ipairs(f.roles) do a[role] = caps[i] end
    end
    if caps and sensible(f, a) then
      local t = { what = f.what, me = f.me, choice = f.choice or (a.choice and choiceOf(a.choice)), up = f.up }
      t.choiceWord = a.choice
      t.rollID = caps.link
      t.who = a.who
      if a.who and P.Me() and (Core.Names.Full(a.who) == Core.Names.Full(P.Me()) or a.who == rawget(_G, "YOU")) then t.me = true end
      t.item, t.mob, t.faction, t.skill = a.item, a.mob, a.faction, a.skill
      t.n = a.n and tonumber((a.n:gsub(",", "")))
      t.roll = a.roll and tonumber(a.roll)
      t.min, t.max = a.min and tonumber(a.min), a.max and tonumber(a.max)
      if f.what == "money" then
        t.copper = a.money and copperOf(a.money)
        if not t.copper then return end
      end
      r.tidy = t
      if quiet then return end   -- a saved line: shown tidy, but it doesn't race today's rolls
      -- the game numbers each roll, so two of the same item dropping at once race apart
      local key = t.rollID and ("roll:" .. t.rollID) or t.item
      if f.what == "rolled" and key then track(key, r, ROLL_WINDOW)
      elseif f.what == "random" and t.roll then track("random:" .. (t.min or 1) .. "-" .. (t.max or 100), r, RANDOM_WINDOW)
      elseif (f.what == "won" or f.what == "allpassed" or f.what == "started") and key then rolls[key] = nil end
      return
    end
  end
end

-------------------------------------------------------------------------------------------
-- People nearby: the game tells you what everyone near you crafts and opens (herbs, ore, chests, locks). In a city
-- that's a flood of strangers, so Parley shows only yours and your group's unless Settings asks for everyone's.
-------------------------------------------------------------------------------------------

local NEARBY = { craft = true, open = true }

local function inGroup(who)
  if not (IsInGroup and IsInGroup()) then return false end
  local full = Core.Names.Full(who)
  if not full then return false end
  local first = Core.Names.First(full)
  local raid = IsInRaid and IsInRaid()
  for i = 1, raid and GetNumGroupMembers() or 4 do
    local unit = (raid and "raid" or "party") .. i
    local theirs = GetUnitName and GetUnitName(unit, true)
    if Core.Names.HasSurname(theirs) then
      if Core.Names.Full(theirs) == full then return true end
    elseif theirs and Core.Names.First(theirs) == first then   -- the client gave a first name only
      return true
    end
  end
  return false
end

---Whether a line is a stranger crafting or opening something near you, which Parley leaves out (Settings, Crafting by
---people nearby). A line Parley can't read for who it was is never left out.
function P.Nearby(r)
  local t = r.tidy
  if not (t and NEARBY[t.what]) or t.me or P.db.craftNearby then return false end
  return not inGroup(t.who)
end

local CHOICE_ICON = { need = "dice", greed = "greed", de = "de", pass = "pass" }

-- The game names a crafted item without linking it ("Elowen creates Minor Healing Potion."); Parley links it when the
-- client knows the item by that name, so it can be clicked like any other.
local linked = {}
local function linkItem(text)
  if type(text) ~= "string" or text:find("|H", 1, true) then return text end
  local name = text:match("^%[(.+)%]$") or text
  if linked[name] then return linked[name] end
  local items = rawget(_G, "C_Item")
  if items and items.GetItemInfo then
    local ok, _, link = pcall(items.GetItemInfo, name)
    if ok and type(link) == "string" then
      linked[name] = link
      return link
    end
  end
  return "|cffffffff[" .. name .. "]|r"
end
P.LinkItemName = linkItem

---The tidy line's words (after the bar and the time).
function P:TidyText(r)
  local t = r.tidy
  local T = L.tidy
  local who = person(t.who, t.me)
  local what = t.what
  if what == "money" then return icon("coin") .. who .. ": " .. P.Money(t.copper) end
  if what == "loot" then
    return icon("bag") .. who .. ": " .. (t.item or "") .. ((t.n and t.n > 1) and (" " .. GREY .. "\195\151" .. t.n .. "|r") or "")
  end
  if what == "choice" then
    local word = T[t.choice] or t.choice
    local col = t.choice == "pass" and FAINT or GREY
    return icon(CHOICE_ICON[t.choice] or "dice") .. who .. ": " .. (t.item or "") .. " " .. FAINT .. "||" .. "|r " .. col .. word .. "|r"
  end
  if what == "rolled" then
    local col = t.lead and GREEN or GREY
    return icon(CHOICE_ICON[t.choice] or "dice") .. who .. ": " .. (t.item or "") .. " " .. FAINT .. "||" .. "|r "
      .. col .. (T[t.choice] or t.choiceWord or "") .. " " .. (t.roll or "") .. "|r"
  end
  if what == "started" then return icon("started") .. (t.item or "") .. " " .. FAINT .. T.started .. "|r" end
  if what == "craft" then
    return icon("craft") .. who .. ": " .. linkItem(t.item) .. ((t.n and t.n > 1) and (" " .. GREY .. "\195\151" .. t.n .. "|r") or "")
  end
  if what == "won" then
    local roll = t.roll and (" " .. FAINT .. (T[t.choice] or "") .. " " .. t.roll .. "|r") or ""
    return icon("won") .. who .. " " .. GREEN .. T.won .. "|r " .. (t.item or "") .. roll
  end
  if what == "allpassed" then return icon("pass") .. FAINT .. T.everyonePassed .. "|r " .. (t.item or "") end
  if what == "random" then
    local col = t.lead and GREEN or GREY
    return icon("dice") .. who .. ": " .. col .. (t.roll or "") .. "|r " .. FAINT .. "(" .. (t.min or 1) .. "\226\128\147" .. (t.max or 100) .. ")|r"
  end
  if what == "xp" then
    return icon("xp") .. "|cff9fd0ff+" .. (t.n or 0) .. " " .. T.xp .. "|r" .. (t.mob and (" " .. FAINT .. "\194\183 " .. t.mob .. "|r") or "")
  end
  if what == "rep" then
    local amount = t.n and ((t.up and "+" or "\226\136\146") .. t.n) or (t.up and "+" or "\226\136\146")
    return icon("rep") .. (t.faction or "") .. " " .. (t.up and GREEN or RED) .. amount .. "|r"
  end
  if what == "skill" then return icon("skill") .. (t.skill or "") .. " " .. GREEN .. (t.n or "") .. "|r" end
  if what == "online" or what == "offline" then
    return icon(what) .. P.PeopleText(t, r.id) .. " " .. FAINT .. T[what] .. "|r" .. P.UnfoldLink(t, r.id)
  end
  return nil
end

---Who came online (or went offline) on one line: "Ash Morrow", "Ash Morrow and Bren Talloway", or, past three, "Ash
---Morrow, Bren Talloway and 3 others" until "show" lists them all.
function P.PeopleText(t)
  local names = t.names or { t.who }
  local shown = {}
  for i, name in ipairs(names) do
    if i > 2 and #names > 3 and not t.open then break end
    shown[#shown + 1] = person(name, name == P.Me())
  end
  if #names > 3 and not t.open then return L.tidy.andOthers:format(shown[1], shown[2], #names - 2) end
  if #shown == 1 then return shown[1] end
  local last = table.remove(shown)
  return L.tidy.andLast:format(table.concat(shown, ", "), last)
end

function P.UnfoldLink(t, id)
  if not (t.names and #t.names > 3 and not t.open and id) then return "" end
  return " |cff" .. P.ACCENT_HEX .. "|Haddon:Parley:unfold:" .. id .. "|h" .. L.tidy.show .. "|h|r"
end
