-- Zomboid Access: playing WITH other people (multiplayer). Everything here is silent in single player.
--   Chat: every message that arrives is said once, with the channel and who wrote it ("Local, Marc: hello"), and
--     kept for the You list's "Chat: recent messages" line. Your own messages are not read back to you.
--     Server alerts (the big red text) are urgent. Radio messages come through the same event.
--   Typing: the game's own chat box with the real keyboard. When it opens (the vanilla Toggle Chat key) or Tab
--     changes the stream, the channel being typed into is said ("Writing in Local").
--   Players: the You list's "Players" line says who is loaded near you, how far and which way, and {Square} asks
--     the server for everyone online.
--   Safehouse and Faction: their windows (ISUserPanelUI and the rest) are mouse only, the game gives them no
--     controller focus at all, so two lines in the You list say what those windows would show.
--   Screens a controller can reach: the Players list and Invite Friends of the main menu and the "Server
--     disconnected" screen; and the server's "saving" message is said.
-- Where a new scanner category for players would go: ZA_5Scan.lua's S.categories (a "players" entry after "animals"),
-- one entry per player from the builder below with x, y, z and walk = "travel", as the markers do. Not done here:
-- this file only touches the You list.

ZA.MP = ZA.MP or {}
local MP = ZA.MP
local F = ZA.F
local S = ZA.S

-- ---------- helpers ----------

-- True only when playing on a server (isClient is false in single player, and on the main menu).
local function online()
    local ok, r = pcall(isClient)
    return ok and r == true
end
MP.online = online

local function now() return getTimestampMs() end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- What a game call returns, or nil when it fails (everything from the game goes through this).
local function try(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok and r ~= nil then return r end
    return nil
end

local function myName()
    return try(function() return getPlayer():getUsername() end)
end

-- ---------- chat: what arrives ----------

MP.history = MP.history or {}      -- oldest first: { chan, author, text, own }
MP.maxHistory = 50                 -- as many as the game's own chat window keeps (ISChat.maxLine)
MP.pageSize = 5

-- The game writes colours, pictures and fonts into a message as [col=1,0,0] [img=...] (ChatSettings allow them).
local function cleanBody(t)
    t = tostring(t or "")
    t = t:gsub("%[img=[^%]]*%]", " ")
    t = t:gsub("%[col=[^%]]*%]", "")
    t = t:gsub("%[font=[^%]]*%]", "")
    t = t:gsub("%[cdt=[^%]]*%]", "")
    t = t:gsub("%[br%]", " ")
    return ZA.clean(t)
end

-- The channel's name in the game's language: the chat's own title (Local, General, Private, Faction...).
-- Shout shares "Local" with say in the game, so it gets its own word.
function MP.channelName(msg)
    local chat = try(function() return msg:getChat() end)
    if not chat then return ZA.tr("MP_ChanChat") end
    local kind = try(function() return tostring(chat:getType()) end) or ""
    if kind == "shout" then return ZA.tr("MP_ChanShout") end
    local id = try(function() return chat:getTitleID() end)
    if id and id ~= "" then
        local t = getText(id)
        if t and t ~= id then return ZA.clean(t) end
    end
    return kind ~= "" and kind or ZA.tr("MP_ChanChat")
end

-- The sentence for one message.
function MP.line(item)
    if item.own then return ZA.tr("MP_ChatOwn", item.chan, item.text) end
    if item.author and item.author ~= "" then return ZA.tr("MP_Chat", item.chan, item.author, item.text) end
    return ZA.tr("MP_ChatServer", item.chan, item.text)
end

local function handle(msg)
    local author = try(function() return msg:getAuthor() end)
    local text = cleanBody(try(function() return msg:getText() end))
    if text == "" then return end
    -- people muted from the scoreboard stay muted for us too (ISChat.addLineInChat does the same, ISChat.lua:735)
    local chatUI = ISChat and ISChat.instance
    if author and chatUI and chatUI.mutedUsers and chatUI.mutedUsers[author] then return end
    local serverAuthor = try(function() return msg:isServerAuthor() end) == true
    local alert = try(function() return msg:isServerAlert() end) == true
    local me = myName()
    local item = {
        chan = MP.channelName(msg),
        author = (not serverAuthor and author) or nil,
        text = text,
        own = (not serverAuthor) and me ~= nil and author == me,
    }
    table.insert(MP.history, item)
    while #MP.history > MP.maxHistory do table.remove(MP.history, 1) end
    MP.pageNext = nil           -- a new message shifts the "newest first" order, so start the paging again
    if item.own then return end
    if alert then ZA.urgent(ZA.tr("MP_Alert", text)); return end
    -- Queued: a message must never cut off what you are being told about the world.
    ZA.queue(MP.line(item))
end

-- Events.OnAddMessage(message, tabID): ChatBase.showMessage (zombie/chat/ChatBase.java:271), also for the radio
-- (RadioChat.java:111) and the server's own messages (ServerChat.java:108). A server alert fires it too, then
-- OnAlertMessage, so only this one is listened to, or it would be said twice.
function MP.onMessage(msg, tabID)
    if not online() or msg == nil then return end
    if msg == MP.lastMsg then return end
    MP.lastMsg = msg
    local ok, err = pcall(handle, msg)
    if not ok then print("[ZA] chat error: " .. tostring(err)) end
end

-- "Chat: recent messages": the newest ones first, a few at a time; again soon after goes on to older ones.
function MP.readHistory()
    local n = #MP.history
    if n == 0 then ZA.say(ZA.tr("MP_HistEmpty")); return end
    local t = now()
    local first = 1
    if MP.pageNext and MP.pageAt and t - MP.pageAt < 20000 and MP.pageNext <= n then first = MP.pageNext end
    local last = math.min(n, first + MP.pageSize - 1)
    for k = first, last do
        local line = MP.line(MP.history[n - k + 1])
        if k == first then ZA.say(line) else ZA.queue(line) end
    end
    if last < n then
        ZA.queue(ZA.tr("MP_HistMore", n - last))
        MP.pageNext, MP.pageAt = last + 1, t
    else
        MP.pageNext = nil
    end
end

-- ---------- chat: the channel you are typing into ----------
-- Typing is the game's own chat box with the real keyboard. A screen reader cannot see which channel the box is
-- on, so say it: when the box opens (ISChat:focus, ISChat.lua:292, bound to the Toggle Chat key through
-- ISChat.onToggleChatBox, ISChat.lua:764) and when Tab changes the stream (ISChat.onSwitchStream, ISChat.lua:~250,
-- which puts the stream's command in the box, e.g. "/say ").

local titleIds = {
    say = "UI_chat_local_chat_title_id", faction = "UI_chat_faction_chat_title_id",
    safehouse = "UI_chat_safehouse_chat_title_id", general = "UI_chat_general_chat_title_id",
    admin = "UI_chat_admin_chat_title_id", whisper = "UI_chat_private_chat_title_id",
}

-- The channel the box's text is addressed to, from the command it starts with (none: the tab's default).
function MP.typingChannel(chat)
    local text = try(function() return chat.textEntry:getInternalText() end) or ""
    local streams = ISChat and ISChat.allChatStreams or {}
    local default = ISChat and ISChat.defaultTabStream and ISChat.defaultTabStream[chat.currentTabID or 1]
    local found
    for _, s in ipairs(streams) do
        local cmd = s.command
        local short = s.shortCommand and (s.shortCommand .. " ")
        if cmd and text:sub(1, #cmd) == cmd then found = s; break end
        if short and text:sub(1, #short) == short then found = s; break end
    end
    found = found or default
    if not found then return nil end
    if found.name == "yell" then return ZA.tr("MP_ChanShout") end
    local id = titleIds[found.name]
    if not id then return nil end
    return ZA.clean(getText(id))
end

function MP.sayTyping(chat)
    if not online() or not chat then return end
    local label = MP.typingChannel(chat)
    if label then ZA.say(ZA.tr("MP_Typing", label)) end
end

-- Wrap the two game functions once. ISChat:focus is a method found by name on each call; onSwitchStream is
-- handed to Events.SwitchChatStream by ISChat.createChat on OnGameStart, after this file has loaded, so the
-- wrapper is what gets registered.
local function hookChat()
    if MP.chatHooked or not (ISChat and ISChat.focus and ISChat.onSwitchStream) then return end
    MP.chatHooked = true
    local origFocus = ISChat.focus
    function ISChat:focus()
        origFocus(self)
        pcall(MP.sayTyping, self)
    end
    local origSwitch = ISChat.onSwitchStream
    ISChat.onSwitchStream = function()
        origSwitch()
        pcall(function() MP.sayTyping(ISChat.instance) end)
    end
end
MP.hookChat = hookChat
hookChat()


-- ---------- players ----------

-- The other players the game has loaded around us, nearest first: { name, x, y, z, d }.
-- (GameClient.getPlayers is every remote player the client knows, which are the ones in range.)
function MP.nearPlayers()
    local out = {}
    local me = getPlayer()
    if not me then return out end
    local list = try(getOnlinePlayers)
    if not list then return out end
    local mx, my = me:getX(), me:getY()
    for i = 0, list:size() - 1 do
        local pl = list:get(i)
        if pl and pl ~= me and try(function() return pl:isLocalPlayer() end) ~= true then
            -- getDisplayName follows the server's disguise settings (IsoPlayer.java:7904), the username would not
            local name = try(function() return pl:getDisplayName() end)
            if not name or name == "" then name = try(function() return pl:getUsername() end) end
            local x, y, z = try(function() return pl:getX() end), try(function() return pl:getY() end), try(function() return pl:getZ() end)
            if name and x and y and z then
                table.insert(out, { name = ZA.clean(name), x = x, y = y, z = z, d = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2) })
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

-- Asking the server for the scoreboard fills MP.onlineList by Events.OnScoreboardUpdate (below); the game's
-- own screens ask the same way (ISScoreboard.lua:363).
function MP.refreshOnline()
    local t = now()
    if MP.askedAt and t - MP.askedAt < 3000 then return end
    MP.askedAt = t
    pcall(scoreboardUpdate)
end

function MP.playersText()
    local near = MP.nearPlayers()
    -- the next visit to this line has a fresh count
    MP.refreshOnline()
    local count = ""
    if MP.onlineList and MP.onlineAt and now() - MP.onlineAt < 120000 then
        count = " " .. ZA.clean(getText("UI_Scoreboard_PlayerConnected", #MP.onlineList)) .. "."
    end
    if #near == 0 then return ZA.tr("MP_PlayersAlone") .. count end
    local parts = {}
    for i, p in ipairs(near) do
        if i > 8 then
            table.insert(parts, ZA.tr("MP_PlayersMore", #near - 8))
            break
        end
        local where = S.where(p.x, p.y, p.z, false)
        table.insert(parts, ZA.tr("MP_PlayerAt", p.name, where))
    end
    return ZA.tr("MP_PlayersNear", table.concat(parts, ". ")) .. count
end

-- The action on the line: everyone online, read when the server answers.
function MP.askWho()
    if not online() then return end
    MP.wantRead = true
    MP.wantAt = now()
    MP.askedAt = nil
    MP.refreshOnline()
    ZA.say(ZA.tr("MP_PlayersAsking"))
end

-- Events.OnScoreboardUpdate(usernames, displayNames, steamIDs, pingValues): Java lists (ScoreboardUpdatePacket.java:82).
function MP.onScoreboard(usernames, displayNames)
    if not online() then return end
    local list = {}
    local ok = pcall(function()
        for i = 0, usernames:size() - 1 do
            local user = usernames:get(i)
            local shown = displayNames and displayNames:get(i) or user
            if shown == nil or shown == "" then shown = user end
            table.insert(list, { user = user, name = ZA.clean(shown) })
        end
    end)
    if not ok then return end
    MP.onlineList, MP.onlineAt = list, now()
    if MP.wantRead then
        MP.wantRead = false
        if #list <= 1 then
            ZA.say(ZA.tr("MP_OnlineAlone"))
        else
            local names = {}
            for _, u in ipairs(list) do table.insert(names, u.name) end
            ZA.say(ZA.tr("MP_OnlineList", ZA.clean(getText("UI_Scoreboard_PlayerConnected", #list)), table.concat(names, ", ")))
        end
    end
end

-- ---------- safehouse and faction ----------

local function safehouseText()
    local noun = getText("IGUI_SafehouseUI_Safehouse")
    local p = getPlayer()
    local sh = try(function() return SafeHouse.hasSafehouse(p) end)
    if not sh then return ZA.tr("MP_SafehouseNone", noun) end
    local title = trim(try(function() return sh:getTitle() end) or "")
    local head = title ~= "" and (noun .. " " .. title) or noun
    local owner = try(function() return sh:getOwner() end) or "?"
    local mine = try(function() return sh:isOwner(p) end) == true
    local n = try(function() return sh:getPlayers():size() end) or 1
    local x, y = try(function() return sh:getX() + sh:getW() / 2 end), try(function() return sh:getY() + sh:getH() / 2 end)
    local where = x and y and S.where(x, y, p:getZ(), true) or ""
    if mine then return ZA.tr("MP_SafehouseMine", head, n, where) end
    return ZA.tr("MP_SafehouseOther", head, owner, n, where)
end

local function factionText()
    local noun = getText("UI_userpanel_factionpanel")
    local p = getPlayer()
    local inside = try(function() return Faction.isAlreadyInFaction(p) end) == true
    if not inside then return ZA.tr("MP_FactionNone", noun) end
    local f = try(function() return Faction.getPlayerFaction(p) end)
    if not f then return ZA.tr("MP_FactionNone", noun) end
    local name = trim(try(function() return f:getName() end) or "")
    local head = name ~= "" and (noun .. " " .. name) or noun
    local owner = try(function() return f:getOwner() end) or "?"
    -- the owner is not in getPlayers (ISFactionUI.lua:264 adds one)
    local n = (try(function() return f:getPlayers():size() end) or 0) + 1
    local mine = owner == myName()
    if mine then return ZA.tr("MP_FactionMine", head, n) end
    return ZA.tr("MP_FactionOther", head, owner, n)
end

-- ---------- the You list ----------

function MP.build(lists)
    if not online() then return end
    local p = getPlayer()
    if not p or not lists.you then return end
    local function add(key, order, base, name, action)
        table.insert(lists.you, {
            cat = "you", key = "you|mp_" .. key, noWhere = true, order = order, baseName = base, name = name,
            x = p:getX(), y = p:getY(), z = p:getZ(), action = action,
        })
    end
    add("players", 910, ZA.tr("MP_PlayersName"), function() return MP.playersText() end, MP.askWho)
    add("hist", 911, ZA.tr("MP_HistBase"), function()
        local n = #MP.history
        if n == 0 then return ZA.tr("MP_HistNameNone") end
        return ZA.tr("MP_HistName", n)
    end, MP.readHistory)
    add("safehouse", 912, ZA.tr("MP_SafehouseBase"), safehouseText, nil)
    add("faction", 913, ZA.tr("MP_FactionBase"), factionText, nil)
end

-- ---------- screens ----------

-- A few screens give the controller focus to a list inside them, not to the screen: the focused panel is an
-- ISScrollingListBox whose parent is the screen (InviteFriends.lua:263 and ISScoreboard.lua:90 set
-- joypadData.focus = self.listbox). Our entries are keyed by the screen's own Lua Type, found through the parent.
MP.hostTypes = { InviteFriends = true, ISScoreboard = true }

local function hostOf(panel)
    if not panel then return nil end
    if MP.hostTypes[panel.Type] then return panel.Type end
    local par = panel.parent
    if type(par) == "table" and par.Type and MP.hostTypes[par.Type] then return par.Type end
    return nil
end

local function listOf(p)
    if p.Type == "InviteFriends" or p.Type == "ISScoreboard" then return p.listbox end
    return p
end

MP.readers = {}

-- Invite Friends (main menu, InviteFriends.lua): the friend, whether online, and for a co-op host allowed or denied.
-- Cross invites, Circle goes back, Square allows or denies (lines 266-272), said by the screen's hints.
MP.readers.InviteFriends = function(p)
    local lb = listOf(p)
    if not lb then return nil end
    local it = lb.items and lb.items[lb.selected]
    if not it then return lb, ZA.tr("MP_InviteEmpty"), "" end
    local fr = it.item
    local state = ""
    pcall(function()
        local key = "UI_FriendState_" .. fr:getState()
        local t = getText(key)
        state = (t ~= key) and t or tostring(fr:getState())
    end)
    local words = ZA.tr("MP_InviteLine", ZA.clean(it.text or ""), state)
    local allowed = ""
    local host = lb.parent
    if host and host.isCoopHost then
        local yes = false
        pcall(function() yes = host.invited and host.invited[fr:getSteamID()] and true or false end)
        allowed = getText(yes and "UI_InviteFriends_Allow" or "UI_InviteFriends_Deny")
        words = words .. ", " .. allowed
    end
    return it, words .. ZA.pos(lb.selected, #lb.items), allowed
end

-- The Players list of the main menu (ISScoreboard.lua): name and ping.
MP.readers.ISScoreboard = function(p)
    local lb = listOf(p)
    if not lb then return nil end
    local it = lb.items and lb.items[lb.selected]
    if not it then return lb, ZA.tr("Focus_Empty"), "" end
    local ping = try(function() return ZA.clean(getText("UI_Ping", it.item.ping)) end) or ""
    local words = ZA.clean(it.text or "")
    if ping ~= "" then words = words .. ", " .. ping end
    return it, words .. ZA.pos(lb.selected, #lb.items), ""
end

F.readers.InviteFriends = MP.readers.InviteFriends
F.readers.ISScoreboard = MP.readers.ISScoreboard

local function hintsOf(panel, name, extra)
    local parts = { name }
    if extra and extra ~= "" then table.insert(parts, extra) end
    local hints = F.buttonHints(panel)
    if hints ~= "" then table.insert(parts, hints) end
    for i, t in ipairs(parts) do parts[i] = t:gsub("[%.%s]+$", "") end
    return table.concat(parts, ". ")
end

F.screens.InviteFriends = {
    name = ZA.clean(getText("UI_InviteFriends_Title")),
    intro = function(p)
        return hintsOf(listOf(p) or p, ZA.clean(getText("UI_InviteFriends_Title")), ZA.tr("MP_InviteHint"))
    end,
}
F.screens.ISScoreboard = {
    name = ZA.clean(getText("UI_mainscreen_scoreboard")),
    intro = function(p)
        local host = p.Type == "ISScoreboard" and p or p.parent
        local n = host and host.playersConnected or 0
        return hintsOf(listOf(p) or p, ZA.clean(getText("UI_mainscreen_scoreboard")),
            ZA.clean(getText("UI_Scoreboard_PlayerConnected", n)))
    end,
}

-- Server disconnect (ISServerDisconnectUI.lua): the reason, then Cross goes to the menu and Circle quits (the
-- panel sets A and B itself, lines 36-39; F.buttonHints reads them).
F.screens.ISServerDisconnectUI = {
    name = ZA.tr("MP_DisconnectName"),
    intro = function(p)
        local reason = ZA.clean(p.reason or "")
        if reason == "" then reason = ZA.tr("MP_LostConnection") end
        return hintsOf(p, ZA.tr("MP_DisconnectName"), reason)
    end,
}
F.readers.ISServerDisconnectUI = function(p) return p, "", "" end

-- The user panel and its windows: the game gives none of them a controller focus (they are plain ISPanel, with no
-- onGainJoypadFocus; the lists have a vestigial joypadParent), so this is only for a player who ends up on one.
local windowTitles = {
    ISUserPanelUI = "UI_mainscreen_userpanel",              -- ISUserPanelUI.lua:20
    ISSafehouseUI = "IGUI_SafehouseUI_Safehouse",           -- ISSafehouseUI.lua:1
    ISFactionUI = "UI_userpanel_factionpanel",              -- ISFactionUI.lua:1
    ISTicketsUI = "UI_userpanel_tickets",                   -- ISTicketsUI.lua:115
    ISFactionAddPlayerUI = "IGUI_SafehouseUI_ConnectedPlayers",   -- ISFactionAddPlayerUI.lua:112
    ISSafehouseAddPlayerUI = "IGUI_SafehouseUI_ConnectedPlayers", -- ISSafehouseAddPlayerUI.lua:102
    ISCreateFactionUI = "IGUI_FactionUI_CreateFaction",     -- ISCreateFactionUI.lua:50
    ISCreateFactionTagUI = "IGUI_FactionUI_ChangeTag",      -- ISCreateFactionTagUI.lua:50
}
for typ, key in pairs(windowTitles) do
    F.screens[typ] = { name = ZA.clean(getText(key)), hint = ZA.tr("MP_MouseOnly") }
end
-- (ISServerSavingMessage has no focus; it is said by the event below.)
F.screens.ISServerSavingMessage = { name = ZA.tr("MP_SavingName") }

-- Wrap the two lookups once so a list inside a known screen is described as that screen.
if not MP.wrapped then
    MP.wrapped = true
    local origCurrent = F.current
    function F.current(panel)
        local host = hostOf(panel)
        local r = host and MP.readers[host]
        if r then
            local ok, key, words, value = pcall(r, panel)
            if ok and key ~= nil then return key, words or "", value or "" end
            if not ok then print("[ZA] reader error " .. tostring(host) .. ": " .. tostring(key)) end
        end
        return origCurrent(panel)
    end
    local origIntro = F.screenIntro
    function F.screenIntro(panel)
        local host = hostOf(panel)
        local sc = host and F.screens[host]
        if sc and sc.intro then
            local ok, t = pcall(sc.intro, panel)
            if ok and t then return t end
            if not ok then print("[ZA] intro error " .. tostring(host) .. ": " .. tostring(t)) end
        end
        return origIntro(panel)
    end
end

-- ---------- disconnect and saving ----------

-- ServerDisconnectState.enter (ServerDisconnectState.java:27-31) clears EVERY Lua event callback, ours too, then
-- calls the global ISServerDisconnectUI_OnServerDisconnectUI. So the mod's tickers are dead on that screen. Wrap
-- that function: after the game's own setup, put one callback back that runs the focus reader, and say the
-- message at once for a player without a controller focus to read it.
function MP.reviveTick()
    local t = now()
    if MP.reviveAt and t - MP.reviveAt < 15 then return end
    MP.reviveAt = t
    local ok, err = pcall(F.poll)
    if not ok and not MP.reviveErr then MP.reviveErr = true; print("[ZA] disconnect reader error: " .. tostring(err)) end
end

function MP.afterDisconnect(reason)
    local ui = ISServerDisconnectUI and ISServerDisconnectUI.instance
    if Events.OnRenderTick then Events.OnRenderTick.Add(MP.reviveTick) end
    local jd = ZA.joypad and ZA.joypad() or nil
    if jd and ui and jd.focus == ui then return end   -- the focus reader says the screen's words
    if ui then
        local ok, text = pcall(F.screenIntro, ui)
        if ok and text and text ~= "" then ZA.urgent(text); return end
    end
    local r = ZA.clean(reason or "")
    ZA.urgent(ZA.tr("MP_DisconnectName") .. ". " .. (r ~= "" and r or ZA.tr("MP_LostConnection")))
end

local function hookDisconnect()
    if MP.disconnectHooked then return end
    local orig = rawget(_G, "ISServerDisconnectUI_OnServerDisconnectUI")
    if type(orig) ~= "function" then return end
    MP.disconnectHooked = true
    _G.ISServerDisconnectUI_OnServerDisconnectUI = function(reason)
        local ok, err = pcall(orig, reason)
        if not ok then print("[ZA] disconnect screen error: " .. tostring(err)) end
        pcall(MP.afterDisconnect, reason)
    end
end
MP.hookDisconnect = hookDisconnect
hookDisconnect()
if not MP.disconnectHooked and Events.OnGameBoot then Events.OnGameBoot.Add(hookDisconnect) end

-- The server pauses everyone while it saves (StartPausePacket.java:32): the game only draws a message.
function MP.onSaveStart() if online() then ZA.say(ZA.tr("MP_SaveStart")) end end
function MP.onSaveDone() if online() then ZA.say(ZA.tr("MP_SaveDone")) end end

-- ---------- ticking ----------

function MP.tick()
    if not online() then
        MP.wantRead = false
        return
    end
    -- no answer to "who is online" in a few seconds
    if MP.wantRead and now() - (MP.wantAt or 0) > 6000 then
        MP.wantRead = false
        ZA.say(ZA.tr("MP_PlayersNoAnswer"))
    end
end

-- Invite Friends says "<name> invited!" in a label only (InviteFriends.lua:129, cleared after 3 s).
local lastInvite = nil
function MP.tickMenu()
    local inv = InviteFriends and InviteFriends.instance
    if not (inv and inv.statusLabel and try(function() return inv:getIsVisible() end)) then lastInvite = nil; return end
    local t = ZA.clean(inv.statusLabel.name or "")
    if t ~= "" and t ~= lastInvite then ZA.say(t) end
    lastInvite = t ~= "" and t or nil
end

-- ---------- registering (once) ----------

if not MP.registered then
    MP.registered = true
    Events.OnAddMessage.Add(function(msg, tab) MP.onMessage(msg, tab) end)
    Events.OnScoreboardUpdate.Add(function(a, b, c, d) MP.onScoreboard(a, b) end)
    Events.OnServerStartSaving.Add(function() MP.onSaveStart() end)
    Events.OnServerFinishSaving.Add(function() MP.onSaveDone() end)
    ZA.onTick(function() MP.tick(); MP.tickMenu() end)
    table.insert(S.builders, function(lists) MP.build(lists) end)
    -- a new game starts with an empty chat memory
    Events.OnGameStart.Add(function()
        MP.history, MP.lastMsg, MP.pageNext, MP.onlineList, MP.wantRead = {}, nil, nil, nil, false
    end)
end
