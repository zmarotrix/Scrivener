# Changelog

## 0.7.11 (2026-11-23)

- Parley's buttons, switches, selectors, text fields and scrollbars are in Parley's colour. Since Norgannon Core 1.31
  fills controls with an add-on's colour, some of Parley's came out in the suite's gold.
- The New tab builder's Tab / New window choice shows its words and works. It was two blank halves, and a new tab
  always joined the window you opened it from.
- Arrange mode's bar is wide enough for the new, larger switches.

## 0.7.10 (2026-11-23)

- Icons inside messages sit on the line. Raid marks, coins, the game's flags and other add-ons' icons came at the
  game's own height, above the middle of the words. They are now lowered by the same amount as Parley's own icons, in
  chat, search and toasts.

## 0.7.9 (2026-11-23)

- Dungeon fights no longer get anything extra. The banner over the lines, the fight clock on the tab bar, the
  hourglass on each line and the "While you fought" box afterwards are gone. Lines still show as they arrive. When the
  fight ends Parley still reads them again, quietly: names take their class colours, whispers join their
  conversations, your name and alerts are checked, and the lines go into history.

## 0.7.8 (2026-11-22)

- Copy Character Name now works in the name menus Parley opens (right-clicking a name in chat or a person in the
  whisper list). It used to fail with an "add-on tried to call a protected function" error, because the game only lets
  its own windows copy to the clipboard. It now opens a small box with the name selected: press Ctrl+C and the box
  closes. It copies the name a whisper reaches, first and last. The copy boxes for a line and for a web address close
  on Ctrl+C too.

## 0.7.7 (2026-11-22)

- Creature and boss emotes show the creature's name where the game puts it: "Murloc Forager attempts to run away in
  fear!", not "%s attempts to run away in fear!". The game's own chat fills that in, and Parley showed the words as
  they came. Search shows them the same way.

## 0.7.6 (2026-11-21)

- Chat history is each character's own. Whispers, guild, group chat and the rest no longer follow you to your alts,
  and the whisper list shows only the people that character talked to. Settings and windows stay the same on every
  character. The history kept before this goes to the character it belongs to: the first one to log in that spoke in
  it. Your other characters start with none. Clear history in Settings clears only the character you're on.
- A line's last letter is no longer sometimes cut off at the right edge. The game measures a line, wraps it at the
  pane's width and clips it at that same edge, and a line that only just fit could draw its last letter a few pixels
  past where it was measured. The clip edge now sits a little further out, in the pane's margin. Where lines wrap
  hasn't changed.

## 0.7.5 (2026-11-20)

- Left-clicking a person in the whisper list shows your conversation without opening the chat box, so your movement
  keys stay yours. Press Enter when you want to answer: the box opens on a whisper to them, not on whatever chat you
  last used, so a reply can't land in guild by mistake. The Reply key and a name menu's Whisper still go where they
  say. If the box is already open and empty, picking someone turns it to them. If you're halfway through typing
  something, it stays where you were sending it.
- Right-clicking a person in the whisper list opens the game's own menu for them (whisper, invite, add friend, ignore,
  copy name), the same one as right-clicking their name in chat. Battle.net friends get the Battle.net menu.

## 0.7.4 (2026-11-19)

- No more "attempt to perform arithmetic on local 'lineTop' (a secret number value)" warnings in dungeon fights. A line
  the game hides from add-ons has a hidden position on screen as well, and the soft fade under each pane's header did
  sums with it. It now leaves that line as the game draws it and softens the rest.

## 0.7.3 (2026-11-19)

- Right-clicking a name opens the game's own menu for them again: whisper, invite, add friend, ignore, report, copy
  name. The game ties that menu to the chat window the click came from and shuts it the moment that window is hidden,
  and its window is the one Parley hides, so the menu vanished before it drew and Parley's own line menu showed instead.
  The menu now belongs to Parley's pane. Parley's line menu (New tab with only..., Copy this line) still opens when
  the right-click isn't on a name. Battle.net names get the game's Battle.net menu the same way.
- The game leaves Target out of that menu whenever an add-on's chat window opened it (only its own chat window may
  target from a menu); `/target First Last` does it instead.
- "Move to whisper window" on that menu opens the person's conversation in Parley.
- The whisper list shows each person's level and guild after their name ("Ash Morrow  58 <Wardens of Dawn>"), and the
  conversation's header says them too. Parley learns them from people the game shows you: your target, focus and
  mouseover, your group, friendly nameplates, any /who answer, your guild roster and friends list. It never sends a
  /who of its own. They're kept for people you've whispered with; someone you've only seen is remembered for the
  session, so a whisper from them later still shows their level.

## 0.7.2 (2026-11-19)

- Strangers crafting near you stay out of chat. The game tells you what everyone in range makes ("Kallexsis Felreaver
  creates Mithril Bar") and what they gather or open ("performs Herb Gathering on Peacebloom"); in a city that's a
  flood. Parley now shows only your own and your group's, and doesn't keep the rest. Settings, Crafting by people
  nearby, brings everyone's back. Strangers' crafting saved before this doesn't come back either.

## 0.7.1 (2026-11-19)

Group loot rolls read properly again.

- WoW Forever starts most roll lines with a hidden link holding the roll's number ("[Loot]: Greed Roll - 87 for ...").
  Parley read that number as a word of the line, so every roll came out shuffled: the number where the name goes, the
  name where the item goes, and the item stuffed into a name. Parley now sets that link aside, and lines with it and
  without it (Disenchant has none) read the same: who chose what, who rolled what, who won.
- Rolls race by the game's own roll number, so two of the same item dropping together each get their own green leader.
- New lines read in the short shape: an item coming up for rolls, the game's "only show the winner" option (the
  winner and their roll; your own losing roll), and items others receive or get as bonus loot.
- A line whose pieces don't make sense (a number where a name goes, a link where a name goes) now stays as the game
  wrote it instead of coming out jumbled. The roll strings in the test harness are now the client's own.
- Saved loot lines from before come back right after the update.

## 0.7.0 (2026-11-19)

Everything the game's chat window did, checked against the client one feature at a time (docs/parley-vanilla-audit.md).

- The combat log is back, as a Combat log tab: the game's own, with its filter bar, filters and settings (right-click
  the bar). It's in the One window, Both sides and Social layouts, and on + for any window.
- Lines the game's chat window prints itself, from no chat event, go to their own chat instead of the Add-ons tab: the
  guild's message of the day in Guild, level-ups, /played and disconnects in System, a channel's line in that channel.
- Chat colours: click a colour in Channel names to change it, for any chat or channel. It's the game's own colour
  setting, so the game's chat and other add-ons follow, and the lines change as soon as you pick.
- Join or leave channels (window menu): the game's own channel list, with who's in each channel and voice.
- The pill at the chat box's right end is there for every character now: the game's chat menu, with emotes and voice
  emotes. With more than one language it still names the one you're speaking.
- The game's chat keys (Chat Page Up, Chat Page Down, Chat Bottom in its key bindings) scroll Parley's pane under the
  mouse, or the window with the chat box.
- Battle.net and quick-join popups appear above the window with the chat box; they hung off a frame Parley had hidden.
- The time follows the game's timestamp option (Options, Social) when one is chosen: 12-hour, with seconds.
- /chatlist names the channel it lists.

## 0.6.2 (2026-11-19)

- Battle.net friends. Their whispers had nowhere to go: Parley listened only for the game's own chat, so they vanished
  with the game's hidden chat windows. Now they're whispers like any other: the Whispers tab, a conversation per
  friend, notes with a Whisper button, the chip's recent people, history and search. Their name shows in the game's
  Battle.net blue and is the game's Battle.net link, so clicking it whispers them and right-clicking gives the game's
  menu. The conversation's header says which character they're on, its level and class, and where.
- A Battle.net friend is kept under their BattleTag: the name the game shows for them changes with every session, so
  after a reload their saved lines find them again by BattleTag. Someone no longer on your friends list shows the name
  part of their BattleTag.
- Friends coming online or going offline join the "came online" line, with the character they're on. Their broadcasts
  show on one line, and a whisper to a friend who's offline says so in their conversation. The game's own words where
  it has them; these notices aren't kept for after a reload.
- A whisper the game hid during a dungeon fight now joins its conversation when the fight ends; it used to show only in
  mixed tabs. A whisper that arrived when no one was picked in Whispers no longer shows twice.

## 0.6.1 (2026-11-19)

- The chip at the chat box's left opens its list again while you type. The game lifts its chat box above Parley's
  windows while you type, and the box reached under the chip, so the click went to the box. The box now starts where
  the chip ends.
- Languages: a character who speaks more than one has a pill at the chat box's right end naming the language the box
  speaks, in Parley's colour when it isn't your usual one. Clicking it opens the game's own chat menu, with your
  languages under Language. The game's menu does the switching: Parley setting the language itself would mark the chat
  box as touched by an add-on, and /cast typed into it could then fail in combat.

## 0.6.0 (2026-11-19)

The rest of the mock-up's screens.

- Conversations drop the names: you know who you picked, so their lines start with a green > and yours with a red <.
- Repeats fold to the mock-up's outlined pill (x2 to x19, then 20+). People coming online within half a minute share
  one line, "Ash Morrow, Bren Talloway and 3 others came online", with "show" to list them all; who came online isn't
  kept for after a reload.
- New since you looked: a pane you weren't looking at marks where its new lines start; the mark moves each time.
- Dungeon fights: a pane that gets a hidden line says why once, in a banner at its top, and the window with the chat
  box shows the fight's clock on its tab bar. When chat comes back, one boxed summary sits at the bottom of those panes
  (how long, whispers, mentions, group and guild lines) with Show the whisper and Show the mention; its x closes it.
  It replaces the faint "While you fought" rule.
- Search is a view over the window, not a tab: a box across the top, chips for Everywhere, Whispers, Guild, Party and
  This session, results newest first with when and where above each line and your words marked. Jump shows the line in
  its tab, scrolled to it and marked for a few seconds; a line older than the tab holds opens the tab from that line
  on. It searches as you type; Ctrl-F in the chat box opens it, Esc closes it.
- Channel names and Alerts are panels beside the window, as in the mock-up. Channel names: Show the chat as, every
  channel with its number, a short name box (the default shown faintly) and its command, and the chats in a grid; the
  lines change as you type, and the command is made only when you're done (not /l, /lf and /lfg on the way to LFG).
  Alerts: a dashed box to type a phrase or Shift-click an item into, one row per alert with its switch, the words, where
  and when (click to change), and how it tells you: Toast, Sound and Taskbar per alert. A switch at the top turns all
  alerts on or off.
- The layout picker dims the screen and shows a picture of each layout, drawn from the layouts themselves. Click one,
  then Use it; the first time, Keep the game's chat for now turns Parley off.
- Arrange mode (window menu, Settings or /parley arrange): every window outlined, a handle on each corner to resize,
  drag a window from anywhere on it, and a bar at the top with Snap, Lock all and Done. Moving a window snaps it to the
  screen's edges and to the other windows' edges, with a dashed guide. Dragging a tab lights up where it would go: the
  half of a window it would take (drop low to put it underneath), another window's tab bar, or "A window of its own".
- The Trade & LFG board: a pane with channels switches between Stream and Board in its header. One card per person,
  their latest advert, how often they posted it, gone after 15 minutes. LFM, LF, WTS and WTB; the dungeon, made from
  NorgannonDB's names (BRD, Strat, Scholo), or "A or B?" when a short form fits two; the roles asked for; the item's
  auction price when Fortune is installed; a Whisper button. Chips filter by kind and dungeon, and a box by words. The
  Trader layout opens it as a board.

## 0.5.0 (2026-11-19)

- Conversations, as in the mock-up: the Whispers tab lists everyone you've whispered with (newest first, online dot,
  name in class colour, how long ago, the last line, an unread badge, Find a person), and shows the conversation with
  the one you pick, under a header saying who they are when the friends list or guild knows. Your lines read "You";
  days are ruled off; "New since you looked" marks where you'd got to. Picking a person opens a whisper to them.
  An existing Whispers tab becomes this view.
- The New tab builder, as in the mock-up: preset cards with their chats' colours, Your own mix as a chip for every chat
  and channel, Only lines that mention me, Tab or New window, Cancel / Add tab. Shift-click a card for a window.

## 0.4.0 (2026-11-19)

- Panes can sit side by side, one above the other, two on the left and one on the right, or one on the left and two
  on the right (the split button, Arrange). Every line between panes is a handle: drag it to share the room.
- Text size per window (window menu, Text size), or the same as Settings.
- More fonts: the suite's three, the game's chat font, Friz Quadrata, Arial Narrow, Morpheus and Skurri, plus every
  SharedMedia font when it's installed (window menu, Font, or Settings). Outline (none, thin, thick), and a Text shadow
  slider: up to half it darkens (half is the old full shadow), past half it grows to 2 px, and near full the text
  gets a thin dark edge too, so it reads with no background at all. An old setting keeps its look.
- Font changes reach the lines: the game's message frame ignored being given the font it already had, and kept a
  private copy once told how to align; Parley now hands it the font afresh and lets the font carry the alignment.
  SetFont returns nothing here when it works, which had made every font fall back to the suite's.
- Fade headers works while the chat box is showing (only typing holds the headers), and its menu entry is shorter.
- Fade the background too (Settings and the window menu): with Fade headers, the dark background fades as well.
- Every whisper gives a note (unless you're typing), and flashes the taskbar when the game isn't in front; Settings,
  Whisper notes, has "Only when I can't see it" and Off. Before, a whisper in any shown pane gave none.
- Tidy lines use the game's own icons where it has them: the backpack for loot, the gold coin for money, and the roll
  frame's dice, coin, shard and cross for Need, Greed, Disenchant and Pass.
- Window opacity holds again (a texture's alpha on this client is its colour's alpha, so setting one wiped the other:
  the background went solid and the border full gold).
- Bar between the chat and the sender (Settings): the coloured bar moves after the time and the chat's short name.
- The top of a pane fades instead of stopping at a hard edge: a line the game would cut through is hidden, and the
  first whole line under it is faint.
- Every line shows its name and time again; running lines from one person together is off unless chosen in Settings.
- With Fade headers on, each pane keeps its name; the chats listed beside it, the rules and the border fade.
- Channel notices name the channel ("Changed Channel: [1. General - Elwynn Forest]", not "[]"); a notice about no
  channel at all isn't shown. Channel notices aren't kept in history.
- Channels show their own full name (LookingForGroup, Trade) unless you give them a short one in Channel names; no
  more made-up abbreviations like LFGu or Loo. A short name you give is also a command (/glo).
- The chat box is in its window from login; it used to appear only after something re-docked it (a tab click).
- Link clicks and hovers in Parley's windows are announced the way the game's chat windows announce them, so add-ons
  that listen for chat links (quest helpers, tooltip add-ons) work in Parley too.
- Crafting lines are tidy, and the item is linked when the client knows it by name (the game sends those lines with
  the name only).
- A quest shared as text by a Questie user ("[[47] The Captain's Chest (8551)]") becomes the game's quest link,
  clickable with or without Questie installed.
  /parley check counts other add-ons' chat filters that failed.
- With Fade headers on, the shown tab keeps its name in the tab bar, and each pane keeps its name.
- Hover an icon (bag, coin, dice, hourglass...) for what it means, and a line's coloured bar for its chat.
- The chat box's outline is quieter: the window's own dark gold with a hint of Parley's colour, a little brighter while
  you type.

## 0.3.0 (2026-11-19)

- Tidy lines for money, loot, rolls, experience, reputation, skills and people coming online: an icon, who, then what.
  Money is in Fortune's coin colours (Fortune's own formatter when it's installed). The highest roll on an item shows
  green and the rest grey; a new high roll turns the old leader grey in place. /roll results race the same way. Every
  pattern comes from the game's own message strings. Settings: Tidy loot, money and rolls (on).
- Add-ons' notices (the login lines most of all) have an Add-ons tab of their own and leave the mixed chats. What an
  add-on prints just after you type a /command, and Parley's own lines, still show where you're reading.
- Both sides: a pfUI-style layout with a window in each bottom corner, what matters on the left and the noise on the right.
- From Better Forever Chat, as options and off unless chosen: race and class icons beside names (the game's own
  atlases), and Keep every chat (public channels, loot, system and add-on lines in history and search).
- The bar beside each line sits on the text's middle; system, loot and money lines carry no short name (no more "Sys").
- The chat box chip draws its arrow (the suite's font had none) and opens its list: it stays in one layer (moving it
  mid-click lost the click), and if the list can't open Parley says why.
- A reload or relog brings the whole window back: channels, Say, loot and system lines are kept too (two days, the
  newest 400 of each), private chat for 30 days as before. Add-ons' notices aren't kept; they print again at login.
  Saved loot and money lines come back tidy. Settings: Keep public chat too (on).
- The Chats in this pane list shows each chat in its own colour. Two channels never share a default short name
  (LookingForGuild gets LFGu beside LookingForGroup's LFG).

## 0.2.0 (2026-11-19)

- Panes side by side, as in the mock-up: a tab shows up to three, each under a small header naming what's in it. The
  split button in the tab bar adds one; dragging a tab onto a window's lines shows it beside them. Right-click a pane's
  header for its chats, rename it, close it, or make it a tab of its own.
- One window is now the mock-up's: Social with Trade & LFG (and Global) beside it, then Whispers, Group, For you and
  Loot. After updating, the layout picker opens once; your windows stay as they are unless you pick one.
- The chat box always shows, as a pill at the bottom of the window you last used, with a chip saying where the line
  goes. Click the chip for Say, Guild, your group, your channels and the people you whispered last; what you've typed
  stays.
- Lines from one person within two minutes run together, the name and time showing once. Your name shows in Parley's
  colour when someone says it.
- Window opacity in the window menu as well as settings, and a new setting to fade the tab bar, pane headers, border and
  an idle chat box when the mouse is away.

## 0.1.1 (2026-11-19)

- Looks like the mock-up: a faint gold border and a rule under the tab bar that always show, the dark glass at 80%,
  the + right after the last tab, and unread counts as badges.
- Each line starts with its chat's bar (rounded, lit from the top), then the time, then the words.
- Windows open at the mock-up's size (712 by 366 for One window), with 13 point text. Saves from 0.1.0 still at the old
  sizes and text size move to the new ones; anything you changed stays.
- Lines stay left-justified after a settings change (the font object turned them centred).
- Lines other add-ons print get a quiet Add-ons bar instead of a bar in the add-on's own colour.
- Fixed an error every frame (`MouseIsOver` doesn't exist on this client). The harness now checks every global and
  client function Parley uses against ForeverAPI's dump of the client.

## 0.1.0 (2026-11-19)

- First build, from the plan in docs/chat-plan.md and the mock-up in design/suite/parley.html.
- Parley's own windows, tabs and layouts; the game's chat windows hidden but still running; the game's chat box moved
  in and restyled.
- Short lines with renamable channel names, each also a command. Class colours, surnames your way, folded repeats.
- For you: mentions and alerts on words and items, with toasts.
- Held lines in dungeon fights, read again when the fight ends, and a recap line.
- History for private chat, search, Send again for whispers to a first name, lines other add-ons print.
- `/parley check` reports what the client allowed, in place of a separate probe.
