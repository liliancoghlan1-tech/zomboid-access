-- Zomboid Access: joining a multiplayer server with a controller (main menu, Multiplayer).
-- What the game's own code does (Project Zomboid 42.21, media/lua/client), and so what this file adds:
--
--   * The server browser (OptionScreens/MultiplayerUI.lua) is one ISPanelJoypad whose controls are found by position
--     (autoGenerateJoypadButtonsLists, line 324). Its two lists (Favorites = accountList, Internet = internetList)
--     take the controller's focus for themselves (ISScrollingListBox.lua:17-22 and 762), so while one is used the
--     focused panel is the list, not MultiplayerUI. Both lists are plain ISScrollingListBox, whose Type says nothing,
--     so they get a private Type here ("ZAFavoritesList", "ZAInternetList") to be told apart.
--   * The game never finishes the controller side of this screen, so this file does it:
--       - A on the Favorites list does nothing in the game (no double click is set, MultiplayerUI.lua:178 sets a
--         mouse handler under another name): A connects with an account, X edits, Y deletes, and a line "Add ..."
--         opens its form on A. Moving onto an "Add" line also opened its form at once (onSelectAccount, 759-783):
--         it no longer does while moving with the pad.
--       - The Favorites list holds Edit, Delete and Connect buttons for each row, moved around by the list's drawing
--         code (MultiplayerUI.lua:392-549). By position they are unreachable or reached by chance, so they are left
--         out of the controller's grid; the list's A, X and Y do their jobs.
--       - The Add or Remove favorite button is an ISMPButton, which has no isButton flag, so A does nothing on it
--         (ISPanelJoypad.lua:314 versus ISMPButton.lua:426-474): A presses it here.
--       - On the Internet list A connects, but to the last server SELECTED (connectFromBrowser, 1474-1509), and
--         moving the focus on the list does not always select: the row is selected first. X adds or removes the
--         favorite, Y reads the details (map, address, mods, description, last wipe) that are drawn on the right.
--       - Opening the screen, or changing tab with {L1} and {R1}, puts the controller on the list of that tab.
--   * The forms (ISMPEditServer, ISMPEnterServerPwd, ISMPEditAccount, ISMPEnterPassword, ISMPSelectAccount, and the
--     Yes or No dialogs made by MultiplayerUI) are added with addToUIManager and NEVER get the controller's focus
--     (no setJoypadFocus anywhere in ISUI/ISMP*.lua): with a pad they cannot be used at all. Three of them also
--     copy ISModalDialog's onGainJoypadFocus, which touches self.ok that they do not have (error), and all five drop
--     joypadData in onJoypadDown (the on-screen keyboard then fails). Here each form is given the focus a few frames
--     after it shows, with its fields as rows (up and down), Circle on its Cancel button, and the two flaws mended.
--   * Moving onto a saved password box marks it as changed (ISMPEditServer.lua:177-185, ISMPEditAccount render), and
--     Save would then erase the saved password. A pad goes through that box on its way down, so it is kept as it was
--     until something is typed.
--   * The connection screens: ConnectToServer (OptionScreens/ConnectToServer.lua) shows its progress and its failure
--     reasons in connectLabel; BootstrapConnectPopup the answer of a server invite; ServerConnectPopup the direct
--     connection form. The status is said when it changes. ConnectToServer has no controller rows at all, so when
--     the two-factor code box appears (googleAuthPopup, 67-110) it is given some. ServerConnectPopup leaves its
--     Steam relay box out of its rows (create, 91-145): it is added.
--
-- A password, or an address or port in streamer mode, is never said: only that it is hidden and how long it is.

local F = ZA.F

ZA.MJ = ZA.MJ or {}
local MJ = ZA.MJ
MJ.open = MJ.open or {}   -- forms shown (set), found through their initialise: a form can open another one

-- ---------- small helpers ----------

-- A method call on a game object that may be missing or may throw: nil then.
local function call(obj, name, ...)
    if obj == nil then return nil end
    local ok, f = pcall(function() return obj[name] end)
    if not ok or f == nil then return nil end
    local ok2, v = pcall(f, obj, ...)
    if ok2 then return v end
    return nil
end

local function int(n)
    n = tonumber(n)
    if not n then return nil end
    return math.floor(n + 0.5)
end

-- The game's button titles are in capitals (CONNECT), which a voice shouts or spells out: plain words instead.
local function plain(s)
    s = ZA.clean(s)
    if s ~= "" and s == s:upper() and s ~= s:lower() then
        s = s:sub(1, 1):upper() .. s:sub(2):lower()
    end
    return s
end

-- A label of the game's own ("Server name:"), without its colon.
local function label(key)
    local t = ZA.clean(getText(key))
    return (t:gsub("%s*:%s*$", ""))
end

local function shown(ui)
    return ui ~= nil and call(ui, "isReallyVisible") == true
end

-- Spoken parts, each without its closing full stop, as one text.
local function sentences(parts)
    local out = {}
    for _, part in ipairs(parts) do
        local s = tostring(part or "")
        s = s:gsub("[%.%s]+$", "")
        if s ~= "" then table.insert(out, s) end
    end
    return table.concat(out, ". ")
end

local function joinList(parts)
    local out = {}
    for _, s in ipairs(parts) do
        if s ~= nil and s ~= "" then table.insert(out, s) end
    end
    return table.concat(out, ", ")
end

-- ---------- describing controls ----------

local function entryText(e)
    local masked = call(e, "isMasked") == true
    local t = call(e, "getInternalText")
    if t == nil then t = call(e, "getText") end
    return tostring(t or ""), masked
end

-- A text box by what it holds; a hidden one (password, streamer mode) only by its length.
local function entryValue(e)
    local t, masked = entryText(e)
    if t == "" then return ZA.tr("ZMultiJoin_Empty") end
    if masked then return ZA.tr(#t == 1 and "ZMultiJoin_HiddenOne" or "ZMultiJoin_HiddenMany", #t) end
    return t
end

-- A button by its title; when it is switched off, why (the game keeps the reason in the tooltip).
local function buttonWords(b, why)
    local title = plain(b.title or call(b, "getTitle") or "")
    if title == "" and b.tooltip then title = plain(b.tooltip) end
    if b.enable == false then
        why = why or (b.tooltip and ZA.clean(b.tooltip)) or ""
        why = (why:gsub("[%.%s]+$", ""))   -- the game's reasons end with a full stop; the sentence has its own
        if why ~= "" then return ZA.tr("ZMultiJoin_ButtonOffWhy", title, why) end
        return ZA.tr("ZMultiJoin_ButtonOff", title)
    end
    return ZA.tr("ZMultiJoin_Button", title)
end

-- A tick box says its own text; the filters have none (the icon says it) and keep it in their tooltip.
local function tickLabel(t)
    local o = t.options and t.options[t.joypadIndex or 1]
    if type(o) == "table" then o = o.text or o.name end
    local s = plain(o or "")
    if s == "" then s = plain(t.tooltip or "") end
    return s
end

local function tickState(t)
    local on = t.selected and t.selected[t.joypadIndex or 1]
    return ZA.tr(on and "ZMultiJoin_Checked" or "ZMultiJoin_NotChecked")
end

-- Any control: words, value (said alone when only it changes), and a key when the selection inside it moves.
-- `name` is its label when the control has none of its own.
local function control(ch, name)
    local t = ch.Type or ""
    if t == "ISTextEntryBox" then
        local v = entryValue(ch)
        return ZA.tr("ZMultiJoin_Entry", name or "", v), v
    elseif t == "ISTickBox" then
        local st = tickState(ch)
        return ZA.tr("ZMultiJoin_Tick", name or tickLabel(ch), st), st
    elseif ch.isCombobox or t == "ISComboBox" then
        local w, v = F.describeBare(ch)
        if ch.expanded and ch.popup and ch.popup.selected then return w, v, ch.popup.selected end
        if name and name ~= "" then w = name .. ": " .. w end
        return w, v
    elseif ch.ISMPButton or t == "ISButton" or t == "ISMPButton" then
        return buttonWords(ch), ""
    end
    local w, v = F.describe(ch)
    return w, v
end

-- ---------- servers and accounts in the lists ----------

local function playersBit(server)
    local n, max = int(call(server, "getPlayers")), int(call(server, "getMaxPlayers"))
    if n and max then
        -- French says 0 and 1 in the singular
        local key = n == 0 and "ZMultiJoin_PlayersNone" or (n == 1 and "ZMultiJoin_PlayerOne" or "ZMultiJoin_Players")
        return ZA.tr(key, n, max)
    end
    return ZA.tr("ZMultiJoin_PlayersUnknown")
end

local function pingBit(server)
    local p = int(call(server, "getPing"))
    if p and p >= 0 then return ZA.tr("ZMultiJoin_Ping", p) end
    return ""
end

local function versionBit(server)
    local v = call(server, "getVersion")
    if v and tostring(v) ~= "" then return ZA.tr("ZMultiJoin_Version", tostring(v)) end
    return ""
end

local function modded(server)
    local m = call(server, "getMods")
    return m ~= nil and tostring(m) ~= ""
end

local function accountName(account)
    local name = tostring(call(account, "getUserName") or "")
    local full = call(account, "getPlayerFirstAndLastName")
    if full and tostring(full) ~= "" then name = name .. " (" .. tostring(full) .. ")" end
    return name
end

-- A line of the Favorites list (MultiplayerUI.lua:421-561 draws the same things).
local function favouriteWords(d)
    local kind = d.type
    if kind == "server" then
        local s = d.server
        local parts = { ZA.clean(call(s, "getName") or "") }
        if call(s, "isResponded") then
            table.insert(parts, playersBit(s))
            table.insert(parts, pingBit(s))
        else
            table.insert(parts, ZA.tr("ZMultiJoin_NotResponding"))
        end
        if call(s, "isPasswordProtected") then table.insert(parts, ZA.tr("ZMultiJoin_Password")) end
        if modded(s) then table.insert(parts, ZA.tr("ZMultiJoin_Modded")) end
        table.insert(parts, versionBit(s))
        local accounts = call(s, "getAccounts")
        local k = int(call(accounts, "size")) or 0
        table.insert(parts, k == 0 and ZA.tr("ZMultiJoin_AccountsNone")
            or ZA.tr(k == 1 and "ZMultiJoin_AccountsOne" or "ZMultiJoin_AccountsMany", k))
        return joinList(parts)
    elseif kind == "account" then
        local a = d.account
        local parts = { ZA.tr("ZMultiJoin_Account", accountName(a)) }
        local played = int(call(a, "getTimePlayed"))
        if played then table.insert(parts, ZA.tr("ZMultiJoin_Played", played)) end
        local last = call(a, "getLastLogon")
        if last and tostring(last) ~= "" then table.insert(parts, ZA.tr("ZMultiJoin_LastLogout", ZA.clean(tostring(last)))) end
        return joinList(parts)
    elseif kind == "new_account" then
        return ZA.tr("ZMultiJoin_AddAccount", ZA.clean(call(d.server, "getName") or ""))
    elseif kind == "new_server" then
        return plain(getText("UI_servers_addserver"))
    end
    return ""
end

-- A line of the Internet list (MultiplayerUI.lua:566-689).
local function internetWords(server, ui)
    local parts = { ZA.clean(call(server, "getName") or ""), playersBit(server), pingBit(server) }
    if call(server, "isPasswordProtected") then table.insert(parts, ZA.tr("ZMultiJoin_Password")) end
    if call(server, "isOpen") == false then table.insert(parts, ZA.tr("ZMultiJoin_Whitelist")) end
    if modded(server) then table.insert(parts, ZA.tr("ZMultiJoin_Modded")) end
    table.insert(parts, versionBit(server))
    if ui and call(ui, "getServerFeatured", server) ~= nil then table.insert(parts, ZA.tr("ZMultiJoin_InFavourites")) end
    return joinList(parts)
end

local function listUI(p)
    local jp = p.joypadParent
    if jp and jp.Type == "MultiplayerUI" then return jp end
    return MultiplayerUI and MultiplayerUI.instance
end

F.readers.ZAFavoritesList = function(p)
    local it = p.items and p.items[p.selected]
    local d = it and it.item
    if not d then return p, ZA.tr("ZMultiJoin_NoServers"), "" end
    return it, favouriteWords(d) .. ZA.pos(p.selected, #p.items), ""
end

F.readers.ZAInternetList = function(p)
    local it = p.items and p.items[p.selected]
    local server = it and it.item
    if not server then return p, ZA.tr("ZMultiJoin_NoServers"), "" end
    return it, internetWords(server, listUI(p)) .. ZA.pos(p.selected, #p.items), ""
end

F.screens.ZAFavoritesList = {
    name = ZA.tr("ZMultiJoin_Name"),
    intro = function(p)
        return sentences({ ZA.tr("ZMultiJoin_FavName", #(p.items or {})), ZA.tr("ZMultiJoin_FavHint") })
    end,
}
F.screens.ZAInternetList = {
    name = ZA.tr("ZMultiJoin_Name"),
    intro = function(p)
        return sentences({ ZA.tr("ZMultiJoin_NetName", #(p.items or {})), ZA.tr("ZMultiJoin_NetHint") })
    end,
}

-- ---------- the browser panel (what is not a list) ----------

F.screens.MultiplayerUI = {
    name = ZA.tr("ZMultiJoin_Name"),
    hint = ZA.tr("ZMultiJoin_Hint"),
}

-- Sort buttons: their titles are English in the game (MultiplayerUI.lua:266, 281, 296); the game has the words.
local sortKeys = { name = "UI_servers_sortType_Name", player = "UI_servers_sortType_Players", ping = "UI_servers_sortType_Ping" }

local function sortWords(ui, b)
    local what = plain(getText(sortKeys[b.internal] or "UI_servers_sortLabel"))
    if ui.sortType == b.internal then
        local dir = ZA.tr(ui.sortDown and "ZMultiJoin_Descending" or "ZMultiJoin_Ascending")
        return ZA.tr("ZMultiJoin_SortNow", what, dir), dir
    end
    return ZA.tr("ZMultiJoin_Sort", what), ""
end

local function browserField(p, ch)
    if ch == p.accountList or ch == p.internetList then
        local n = #(ch.items or {})
        return ZA.tr(ch == p.accountList and "ZMultiJoin_FavName" or "ZMultiJoin_NetName", n), ""
    elseif ch == p.buttonSortName or ch == p.buttonSortPlayer or ch == p.buttonSortPing then
        return sortWords(p, ch)
    elseif ch == p.rightPanelFavouritesButton then
        local s = p.selectedInternetServer
        local title = plain(ch.title or "")
        if ch.enable == false or not s then return ZA.tr("ZMultiJoin_ButtonOff", title), "" end
        return ZA.tr("ZMultiJoin_FavButton", title, ZA.clean(call(s, "getName") or "")), ""
    elseif ch == p.filter then
        return control(ch, plain(getText("UI_servers_nameFilter")))
    elseif ch == p.showIPAddressesTickBox then
        local w, v = control(ch)
        local tip = ch.tooltip and ZA.clean(ch.tooltip) or ""
        if tip ~= "" then w = w .. ". " .. tip end
        return w, v
    end
    return control(ch)
end

-- MultiplayerUI.lua:8 (Type); 324 and ISPanelJoypad.lua:198-244 (the grid is built from every visible control)
F.readers.MultiplayerUI = function(p)
    local ch = F.focusedChild(p)
    if not ch then return p, "", "" end
    local words, value, key = browserField(p, ch)
    return key or ch, words, value
end

-- ---------- the forms ----------

local function seeWords(entry)
    local masked = call(entry, "isMasked") == true
    local st = ZA.tr(masked and "ZMultiJoin_PwdHidden" or "ZMultiJoin_PwdShown")
    return ZA.tr("ZMultiJoin_ShowPassword", st), st
end

-- A saved password the player has not touched (the game shows "[click to change saved password]" over the empty box,
-- ISMPEditServer.lua:183): the form says it is unchanged instead of reading an empty box.
local function pwdSaved(m, entry)
    local orig = m.zaMJPwdOrig
    if orig == nil then orig = m.isPasswordModified end
    return orig == false and entryText(entry) == ""
end

local function pwdField(m, entry, name)
    if pwdSaved(m, entry) then
        local v = ZA.tr("ZMultiJoin_PwdKept")
        return ZA.tr("ZMultiJoin_Entry", name, v), v
    end
    return control(entry, name)
end

-- Why Save is switched off (ISMPEditServer.lua:155-174 checks these three boxes).
local function saveWhy(m)
    if entryText(m.serverName) == "" then return ZA.tr("ZMultiJoin_NeedName") end
    if #entryText(m.serverAddress) < 7 then return ZA.tr("ZMultiJoin_NeedAddress") end
    if entryText(m.serverPort) == "" then return ZA.tr("ZMultiJoin_NeedPort") end
    return nil
end

local function editServerField(m, ch)
    if ch == m.serverName then return control(ch, label("UI_servers_server_name"))
    elseif ch == m.serverAddress then return control(ch, label("UI_servers_ip_domain"))
    elseif ch == m.serverPort then return control(ch, label("UI_servers_port"))
    elseif ch == m.serverPassword then return pwdField(m, ch, label("UI_servers_server_password"))
    elseif ch == m.seePasswordBtn then return seeWords(m.serverPassword)
    elseif ch == m.saveBtn then return buttonWords(ch, saveWhy(m)), ""
    end
    return control(ch)
end

local function enterServerPwdField(m, ch)
    if ch == m.password then return control(ch, label("UI_servers_server_password")) end
    return control(ch)
end

local function editAccountField(m, ch)
    if ch == m.login then return control(ch, label("UI_servers_login"))
    elseif ch == m.authType then return control(ch, label("UI_servers_authentication_type"))
    elseif ch == m.password then return pwdField(m, ch, label("UI_servers_password"))
    elseif ch == m.seePasswordBtn then return seeWords(m.password)
    elseif ch == m.googleAuthButton then
        local status = m.googleAuthPopup and ZA.clean(m.googleAuthPopup.statusLabel or "") or ""
        return buttonWords(ch), status
    end
    return control(ch)
end

local function enterPasswordField(m, ch)
    if ch == m.accountPassword then return control(ch, label("UI_servers_password"))
    elseif ch == m.seePasswordBtn then return seeWords(m.accountPassword)
    end
    return control(ch)
end

local function selectAccountField(m, ch)
    if ch == m.accountList then return control(ch, label("UI_servers_account_name"))
    elseif ch == m.addNewAccountBtn then return ZA.tr("ZMultiJoin_AddAccountBtn"), ""
    end
    return control(ch)
end

local function formReader(describe)
    return function(m)
        local ch = F.focusedChild(m)
        if not ch then return m, "", "" end
        local words, value, key = describe(m, ch)
        return key or ch, words, value
    end
end

-- ISMPEditServer.lua:3, ISMPEnterServerPwd.lua:3, ISMPEditAccount.lua:3, ISMPEnterPassword.lua:3, ISMPSelectAccount.lua:3
F.readers.ISMPEditServer = formReader(editServerField)
F.readers.ISMPEnterServerPwd = formReader(enterServerPwdField)
F.readers.ISMPEditAccount = formReader(editAccountField)
F.readers.ISMPEnterPassword = formReader(enterPasswordField)
F.readers.ISMPSelectAccount = formReader(selectAccountField)

local function serverName(m)
    return ZA.clean(call(m.server, "getName") or "")
end

F.screens.ISMPEditServer = {
    name = ZA.tr("ZMultiJoin_EditServerNew"),
    intro = function(m)
        local title = m.server and ZA.tr("ZMultiJoin_EditServer", serverName(m)) or ZA.tr("ZMultiJoin_EditServerNew")
        return sentences({ title, ZA.tr("ZMultiJoin_FormHint") })
    end,
}
F.screens.ISMPEnterServerPwd = {
    name = label("UI_servers_server_password"),
    intro = function(m)
        return sentences({ getText("UI_servers_enterServerPwd", serverName(m)), ZA.tr("ZMultiJoin_FormHint") })
    end,
}
F.screens.ISMPEditAccount = {
    name = ZA.tr("ZMultiJoin_Name"),
    intro = function(m)
        local title
        if m.account then title = ZA.tr("ZMultiJoin_EditAccount", accountName(m.account))
        else title = ZA.tr("ZMultiJoin_AddAccount", serverName(m)) end
        return sentences({ title, ZA.tr("ZMultiJoin_FormHint") })
    end,
}
F.screens.ISMPEnterPassword = {
    name = label("UI_servers_password"),
    intro = function(m)
        return sentences({ ZA.tr("ZMultiJoin_PasswordFor", accountName(m.account), serverName(m)), ZA.tr("ZMultiJoin_FormHint") })
    end,
}
F.screens.ISMPSelectAccount = {
    name = ZA.tr("ZMultiJoin_Name"),
    intro = function(m)
        return sentences({ getText("IGUI_SelectAccount_Server", serverName(m)), ZA.tr("ZMultiJoin_FormHint") })
    end,
}

-- ---------- the connection screens ----------

local function statusOf(p)
    return p.connectLabel and ZA.clean(p.connectLabel.name or "") or ""
end

local function labelName(l)
    return l and ZA.clean(l.name or "") or ""
end

-- ConnectToServer.lua:1 (Type). Its rows exist only while the two-factor code box shows (see tickConnect).
F.readers.ConnectToServer = function(p)
    local status = statusOf(p)
    local ch = F.focusedChild(p)
    if ch then
        if ch == p.googleAuthEntry then
            local lab = (labelName(p.googleAuthLabel):gsub("%s*:%s*$", ""))
            return ch, sentences({ ZA.tr("ZMultiJoin_Entry", lab, entryValue(ch)), ZA.tr("ZMultiJoin_CodeHint") }), status
        end
        local words = control(ch)
        return ch, words, status
    end
    return p, "", status
end

F.screens.ConnectToServer = {
    name = ZA.tr("ZMultiJoin_Name"),
    intro = function(p)
        return sentences({
            labelName(p.title),
            -- connectCoop (connecting to a host, not a server) hides these two labels but leaves their old text
            (call(p.serverName1, "isVisible") == true and labelName(p.serverName1) ~= "")
                and (labelName(p.serverName1) .. " " .. labelName(p.serverName)) or "",
            labelName(p.userName1) ~= "" and (labelName(p.userName1) .. " " .. labelName(p.userName)) or "",
            statusOf(p),
            F.buttonHints(p),
        })
    end,
}

-- BootstrapConnectPopup.lua:3 (Type): a server invite, looking for the server
F.readers.BootstrapConnectPopup = function(p)
    return p, "", statusOf(p)
end

F.screens.BootstrapConnectPopup = {
    name = ZA.tr("ZMultiJoin_Name"),
    intro = function(p)
        return sentences({ getText("UI_BootstrapConnectPopup_Title"), statusOf(p), F.buttonHints(p) })
    end,
}

-- ServerConnectPopup.lua:6 (Type): the direct connection form. Its three boxes are the rows; "row 0" is its buttons
-- (ServerConnectPopup.lua:177-186, 247-277): Connect on {Cross}, Cancel on {Circle}.
local function bareLabel(l)
    return (labelName(l):gsub("%s*:%s*$", ""))
end

local function popupField(p, ch)
    if ch == p.serverPasswordEntry then return control(ch, label("UI_servers_serverpwd"))
    elseif ch == p.usernameEntry then return control(ch, bareLabel(p.usernameLabel))
    elseif ch == p.passwordEntry then return control(ch, bareLabel(p.passwordLabel))
    end
    return control(ch)
end

F.readers.ServerConnectPopup = function(p)
    if (p.joypadIndexY or 1) == 0 then
        local b = p.connectBtn
        if b and b.enable == false then
            local why = b.tooltip and ZA.clean(b.tooltip) or ""
            why = (why:gsub("[%.%s]+$", ""))
            return b, ZA.tr("ZMultiJoin_PopupButtonsOff", why), ""
        end
        return b or p, ZA.tr("ZMultiJoin_PopupButtons"), ""
    end
    local ch = F.focusedChild(p)
    if not ch then return p, "", "" end
    local words, value, key = popupField(p, ch)
    -- the box's own explanation (its tooltip) when the focus arrives, not each time its value changes
    local tip = ch.tooltip and ZA.clean(ch.tooltip) or ""
    if tip ~= "" and ch.Type == "ISTextEntryBox" then words = words .. ". " .. tip end
    return key or ch, words, value
end

F.screens.ServerConnectPopup = {
    name = ZA.tr("ZMultiJoin_Name"),
    intro = function(p)
        return sentences({ ZA.tr("ZMultiJoin_PopupIntro", tostring(p.ip or ""), tostring(p.port or "")), ZA.tr("ZMultiJoin_FormHint") })
    end,
}

-- ---------- patching the game ----------

-- Remove a server from the favorites: Y on its line (the game only offers the button of the right panel).
local function favouriteDialog(ui, server)
    -- the same dialog as the Remove button of the right panel (MultiplayerUI.lua:1450-1455)
    ui.modal = ISModalDialog:new(ui.x + (ui.width - 250) / 2, ui.y + (ui.height - 150) / 2, 250, 150,
        getText("UI_servers_remove_server"), true, ui, MultiplayerUI.onDeleteServer, nil, server)
    ui.modal:initialise()
    ui.modal:addToUIManager()
    ui.screenShading:setVisible(true)
    ui.screenShading:bringToTop()
    ui.modal:bringToTop()
end

-- The list's rows come with buttons the game moves around while drawing; the pad's grid leaves them out.
local function flagRowButtons(ui)
    local changed = 0
    local list = ui.accountList
    if not (list and list.items) then return 0 end
    for _, it in ipairs(list.items) do
        local d = it.item
        if type(d) == "table" then
            for _, k in ipairs({ "editButton", "deleteButton", "connectButton" }) do
                local b = d[k]
                if b and b.autoAddJoypadButton ~= false then
                    b.autoAddJoypadButton = false
                    changed = changed + 1
                end
            end
        end
    end
    return changed
end

-- The row on the focused list is the selected one before anything is done with it.
local function syncSelection(list)
    local it = list.items and list.items[list.selected]
    local d = it and it.item
    if d == nil then return end
    if list.Type == "ZAFavoritesList" then
        local ok, kind = pcall(function() return d.type end)
        if not ok or (kind ~= "server" and kind ~= "account") then return end
    end
    pcall(list.invokeOnMouseDownFunction, list)
end

-- Put the controller on the list of the tab showing (the game leaves it on the first control by position).
function MJ.enterList(ui, jd)
    if not (ui and jd and jd.focus == ui) then return end
    local internet = call(ui.tabs, "getActiveViewIndex") == 2
    local list = internet and ui.internetList or ui.accountList
    if not list then return end
    syncSelection(list)
    ui:setJoypadFocus(list, jd)
end

-- Details of an Internet server, as the right panel draws them (MultiplayerUI.lua:1128-1269).
function MJ.details(server)
    local first = { ZA.clean(call(server, "getName") or ""),
        ZA.tr("ZMultiJoin_Address", ZA.clean(call(server, "getDisplayIp") or ""), ZA.clean(call(server, "getDisplayPort") or "")) }
    ZA.say(joinList(first))
    local rest = { playersBit(server), pingBit(server), versionBit(server) }
    local map = call(server, "getMapName")
    if map and tostring(map) ~= "" then table.insert(rest, ZA.tr("ZMultiJoin_Map", ZA.clean(tostring(map)))) end
    table.insert(rest, ZA.tr(call(server, "isPasswordProtected") and "ZMultiJoin_Password" or "ZMultiJoin_NoPassword"))
    table.insert(rest, ZA.tr(call(server, "isOpen") == false and "ZMultiJoin_Whitelist" or "ZMultiJoin_OpenToAll"))
    ZA.queue(joinList(rest))
    local mods = call(server, "getMods")
    if mods and tostring(mods) ~= "" then
        local names = {}
        for piece in tostring(mods):gmatch("[^;,]+") do
            local name = piece:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" then table.insert(names, name) end
        end
        local shownNames = {}
        for i = 1, math.min(#names, 12) do shownNames[i] = names[i] end
        local text = table.concat(shownNames, ", ")
        if #names > 12 then text = text .. ", " .. ZA.tr("ZMultiJoin_AndMore", #names - 12) end
        ZA.queue(ZA.tr(#names == 1 and "ZMultiJoin_ModsOne" or "ZMultiJoin_ModsMany", #names, text))
    else
        ZA.queue(ZA.tr("ZMultiJoin_NoMods"))
    end
    local wipe = int(call(server, "getLastWipe")) or 0
    local when
    if wipe > 0 then
        local days = math.floor((getTimestamp() - wipe) / 86400)
        when = days <= 0 and getText("UI_servers_wipe_today") or getText("UI_servers_wipe_days_ago", days)
    else
        when = getText("UI_servers_wipe_unknown")
    end
    ZA.queue(ZA.clean(getText("UI_servers_last_wipe") .. " " .. when))
    local desc = ZA.clean(call(server, "getDescription") or "")
    if desc ~= "" then ZA.queue(ZA.tr("ZMultiJoin_Description", desc)) end
end

-- What A, X and Y do on a line of the Favorites list. Returns true when it was handled.
function MJ.favouriteAction(ui, d, button)
    local kind = d.type
    if button == Joypad.AButton then
        if kind == "account" then
            ui:onPressButtonOnAccountList({ internal = "CONNECT", server = d.server, account = d.account })
        elseif kind == "new_server" or kind == "new_account" then
            ui:onSelectAccount(d)   -- not moving: the form opens
        else
            ZA.say(ZA.tr("ZMultiJoin_ServerRowHint"))
        end
        return true
    elseif button == Joypad.XButton then
        if kind == "server" then
            ui:onPressButtonOnAccountList({ internal = "EDIT_SERVER", server = d.server })
        elseif kind == "account" then
            ui:onPressButtonOnAccountList({ internal = "EDIT_ACCOUNT", server = d.server, account = d.account })
        end
        return true
    elseif button == Joypad.YButton then
        if kind == "account" then
            ui:onPressButtonOnAccountList({ internal = "DELETE_ACCOUNT", server = d.server, account = d.account })
        elseif kind == "server" then
            favouriteDialog(ui, d.server)
        end
        return true
    end
    return false
end

-- Moves made with the pad, so that moving over an "Add" line does not open its form.
local function padMoves(fn)
    return function(self, jd)
        MJ.padMove = true
        local ok, err = pcall(fn, self, jd)
        MJ.padMove = false
        if not ok then print("[ZA] multi join move error: " .. tostring(err)) end
    end
end

-- Done once per browser: the two lists' controller handling.
function MJ.prepare(ui)
    MJ.prepared = ui
    local flagged = flagRowButtons(ui)

    local fav = ui.accountList
    if fav then
        fav.Type = "ZAFavoritesList"
        fav.onJoypadDirUp = padMoves(ISScrollingListBox.onJoypadDirUp)
        fav.onJoypadDirDown = padMoves(ISScrollingListBox.onJoypadDirDown)
        fav.onJoypadDown = function(self, button, jd)
            local it = self.items and self.items[self.selected]
            local d = it and it.item
            if type(d) == "table" and button ~= Joypad.BButton then
                local ok, handled = pcall(MJ.favouriteAction, ui, d, button)
                if not ok then print("[ZA] multi join list error: " .. tostring(handled)) end
                if ok and handled then return end
            end
            return ISScrollingListBox.onJoypadDown(self, button, jd)
        end
        fav:setOnMouseDownFunction(ui, MultiplayerUI.onSelectAccount)
    end

    local net = ui.internetList
    if net then
        net.Type = "ZAInternetList"
        net.onJoypadDown = function(self, button, jd)
            local it = self.items and self.items[self.selected]
            local server = it and it.item
            if server then
                if button == Joypad.AButton then
                    -- Connect uses the server selected, which is not always this row
                    pcall(self.invokeOnMouseDownFunction, self)
                elseif button == Joypad.XButton then
                    pcall(self.invokeOnMouseDownFunction, self)
                    local was = call(ui, "getServerFeatured", server) ~= nil
                    pcall(ui.onOptionMouseDown, ui, { internal = "FAVOURITES" })
                    if not was and call(ui, "getServerFeatured", server) ~= nil then ZA.say(ZA.tr("ZMultiJoin_FavAdded")) end
                    return
                elseif button == Joypad.YButton then
                    local ok, err = pcall(MJ.details, server)
                    if not ok then print("[ZA] multi join details error: " .. tostring(err)) end
                    return
                end
            end
            return ISScrollingListBox.onJoypadDown(self, button, jd)
        end
    end

    if flagged > 0 then pcall(ui.autoGenerateJoypadButtonsLists, ui) end
    ZA.log("[ZA] multi join: server browser prepared (" .. flagged .. " row buttons left out of the pad's grid)")
end

-- The browser's own methods, wrapped once: the originals are kept in MultiplayerUI.zaMJ so that loading this
-- file again does not wrap the wrappers.
if MultiplayerUI and ISScrollingListBox then
    MultiplayerUI.zaMJ = MultiplayerUI.zaMJ or {
        setVisible = MultiplayerUI.setVisible,
        onTab = MultiplayerUI.onTabViewActiveTabChanged,
        onJoypadDown = MultiplayerUI.onJoypadDown,
        onSelectAccount = MultiplayerUI.onSelectAccount,
        refreshList = MultiplayerUI.refreshList,
    }
    local O = MultiplayerUI.zaMJ

    -- Showing the browser with a pad puts the controller on its list.
    function MultiplayerUI:setVisible(visible, joypadData)
        O.setVisible(self, visible, joypadData)
        if visible and joypadData then
            local ok, err = pcall(MJ.enterList, self, joypadData)
            if not ok then print("[ZA] multi join enter error: " .. tostring(err)) end
        end
    end

    -- A tab change (MultiplayerUI.lua:327-335) gives the focus back to the panel: on to the new tab's list.
    function MultiplayerUI:onTabViewActiveTabChanged(sender)
        O.onTab(self, sender)
        local jd = JoypadState.getMainMenuJoypad()
        if jd and jd.focus == self then
            local ok, err = pcall(MJ.enterList, self, jd)
            if not ok then print("[ZA] multi join tab error: " .. tostring(err)) end
        end
    end

    -- A on the Add or Remove favorite button (an ISMPButton, which A does not press).
    function MultiplayerUI:onJoypadDown(button, joypadData)
        if button == Joypad.AButton then
            local ch = F.focusedChild(self)
            if ch and ch.ISMPButton and ch.forceClick then
                ch:forceClick()
                return
            end
        end
        return O.onJoypadDown(self, button, joypadData)
    end

    -- Moving the pad over an "Add" line must not open its form (the list calls this on every move).
    function MultiplayerUI:onSelectAccount(item)
        if MJ.padMove and type(item) == "table" and (item.type == "new_server" or item.type == "new_account") then
            self.selectedAccount = item
            return
        end
        return O.onSelectAccount(self, item)
    end

    function MultiplayerUI:refreshList()
        O.refreshList(self)
        pcall(flagRowButtons, self)
    end
end

-- The five forms: the focus they never get, the Circle button, and the two flaws (see the top of this file).
local ROWS = {
    ISMPEditServer = function(m)
        return { { m.serverName }, { m.serverAddress }, { m.serverPort }, { m.serverPassword, m.seePasswordBtn }, { m.cancelBtn, m.saveBtn } }
    end,
    ISMPEnterServerPwd = function(m)
        return { { m.password }, { m.closeBtn, m.saveBtn } }
    end,
    ISMPEditAccount = function(m)
        return { { m.login }, { m.authType }, { m.password, m.seePasswordBtn }, { m.rememberPasswordTickBox },
            { m.steamRelayTickBox }, { m.googleAuthButton }, { m.cancelBtn, m.saveBtn } }
    end,
    ISMPEnterPassword = function(m)
        return { { m.accountPassword, m.seePasswordBtn }, { m.cancelBtn, m.connectBtn } }
    end,
    ISMPSelectAccount = function(m)
        return { { m.accountList }, { m.closeBtn, m.addNewAccountBtn, m.connectBtn } }
    end,
}

-- A saved password untouched must stay saved: while its box is empty and the form opened with it unchanged,
-- it is "not modified" (the game flips that when the box merely has the focus).
local function guardPassword(m)
    if not m.zaMJGranted or m.zaMJPwdOrig ~= false then return end
    local entry = m.serverPassword or m.password
    if entry and entryText(entry) == "" then m.isPasswordModified = false end
end
MJ.guardPassword = guardPassword

local function patchForm(cls, cancelField, guarded)
    if not cls then return end
    cls.zaMJ = cls.zaMJ or { initialise = cls.initialise, onClick = cls.onClick }
    local O = cls.zaMJ

    function cls:initialise()
        O.initialise(self)
        MJ.open[self] = getTimestampMs()
    end
    function cls:onGainJoypadFocus(joypadData)
        ISPanelJoypad.onGainJoypadFocus(self, joypadData)
        local b = self[cancelField]
        if b then self:setISButtonForB(b) end
    end
    function cls:onLoseJoypadFocus(joypadData)
        ISPanelJoypad.onLoseJoypadFocus(self, joypadData)
        self:clearISButtonB()
    end
    function cls:onJoypadDown(button, joypadData)
        ISPanelJoypad.onJoypadDown(self, button, joypadData)
    end
    if guarded and O.onClick then
        function cls:onClick(button)
            pcall(guardPassword, self)
            return O.onClick(self, button)
        end
    end
end

if ISPanelJoypad then
    patchForm(ISMPEditServer, "cancelBtn", true)
    patchForm(ISMPEnterServerPwd, "closeBtn", false)
    patchForm(ISMPEditAccount, "cancelBtn", true)
    patchForm(ISMPEnterPassword, "cancelBtn", false)
    patchForm(ISMPSelectAccount, "closeBtn", false)
end

-- Give a form the controller: its fields as rows, the focus on the first one.
function MJ.grant(m, jd)
    if jd.focus == m then return end
    local rows = ROWS[m.Type]
    if rows then
        local ok, built = pcall(rows, m)
        if ok and built then
            m:clearJoypadButtonsList()
            for _, row in ipairs(built) do
                local list = {}
                for i = 1, 3 do
                    if row[i] then table.insert(list, row[i]) end
                end
                if #list > 0 then m:insertNewListOfButtons(list) end
            end
            m.joypadIndexY, m.joypadIndex = 1, 1
            m.joypadButtons = m.joypadButtonsY[1] or {}
        end
    end
    m.zaMJPwdOrig = m.isPasswordModified
    m.prevFocus = jd.focus   -- what destroy() gives the focus back to
    jd.focus = m
    updateJoypadFocus(jd)
    if rows then pcall(m.setJoypadFocusTopLeft, m, jd) end
    ZA.log("[ZA] multi join: the controller is on " .. tostring(m.Type))
end

local function watchQr(m)
    local s = m.googleAuthPopup and ZA.clean(m.googleAuthPopup.statusLabel or "") or ""
    if s ~= "" and s ~= m.zaMJQr then
        m.zaMJQr = s
        ZA.say(s)
    end
end

function MJ.tickForms(ui, jd)
    local now = getTimestampMs()
    local found = {}
    for m, _ in pairs(MJ.open) do table.insert(found, m) end
    local current = ui and ui.modal
    if current and not MJ.open[current] then table.insert(found, current) end
    for _, m in ipairs(found) do
        if shown(m) then
            m.zaMJSeen = (m.zaMJSeen or 0) + 1
            -- a few frames after it shows, once its boxes and buttons have their places
            if m.zaMJSeen >= 3 and not m.zaMJGranted then
                m.zaMJGranted = true
                if jd then MJ.grant(m, jd) end
            end
            if m.Type == "ISMPEditAccount" then watchQr(m) end
            guardPassword(m)
        elseif MJ.open[m] and (m.zaMJSeen or now - MJ.open[m] > 3000) then
            MJ.open[m] = nil
        end
    end
end

-- Connection screens: the status said when it changes, and the rows the game forgot.
local function watchStatus(p, jd)
    local s = statusOf(p)
    if jd and jd.focus == p then
        p.zaMJStatus = s   -- the focus reader says it
    elseif s ~= "" and s ~= p.zaMJStatus then
        p.zaMJStatus = s
        ZA.say(s)
    end
end

function MJ.tickConnect(jd)
    local c = ConnectToServer and ConnectToServer.instance
    if c and shown(c) then
        local popup = c.googleAuthPopup
        local want = popup ~= nil and shown(popup)
        if want and not c.zaMJTwoFactor then
            c.zaMJTwoFactor = true
            c:clearJoypadButtonsList()
            c:insertNewListOfButtons({ c.googleAuthEntry })
            c:insertNewListOfButtons({ c.googleAuthButton })
            c.joypadIndexY, c.joypadIndex = 1, 1
            c.joypadButtons = c.joypadButtonsY[1]
            if jd and jd.focus == c then c:setJoypadFocus(c.googleAuthEntry, jd) end
        elseif not want and c.zaMJTwoFactor then
            c.zaMJTwoFactor = false
            c:clearJoypadButtonsList()
        end
        watchStatus(c, jd)
    elseif c then
        c.zaMJStatus = nil
    end

    local b = BootstrapConnectPopup and BootstrapConnectPopup.instance
    if b and shown(b) then watchStatus(b, jd) elseif b then b.zaMJStatus = nil end

    -- the Steam relay box is not among the direct connection form's rows (ServerConnectPopup.lua:139-144)
    local sp = ServerConnectPopup and ServerConnectPopup.instance
    if sp and shown(sp) and sp.connectTypeEntry and not sp.zaMJRelayRow then
        sp.zaMJRelayRow = true
        sp:insertNewLineOfButtons(sp.connectTypeEntry)
        if (sp.joypadIndexY or 0) > 0 then sp.joypadButtons = sp.joypadButtonsY[sp.joypadIndexY] end
    end
end

-- "N servers" once the Internet list has stopped growing (servers answer one by one, for many seconds).
function MJ.tickCount(ui)
    local idx = ui and shown(ui) and call(ui.tabs, "getActiveViewIndex")
    if idx ~= 2 or not ui.internetList then
        MJ.count = nil
        return
    end
    local n = #(ui.internetList.items or {})
    local now = getTimestampMs()
    if MJ.count == nil then
        MJ.count, MJ.countAt, MJ.countSaid = n, now, n
    elseif MJ.count ~= n then
        MJ.count, MJ.countAt = n, now
    elseif MJ.countSaid ~= n and now - MJ.countAt > 2500 then
        MJ.countSaid = n
        if n > 0 then ZA.queue(ZA.tr(n == 1 and "ZMultiJoin_FoundOne" or "ZMultiJoin_Found", n)) end
    end
end

local function guarded(f, ...)
    local ok, err = pcall(f, ...)
    if not ok then print("[ZA] multi join error: " .. tostring(err)) end
end

function MJ.tick()
    local ui = MultiplayerUI and MultiplayerUI.instance
    if ui and ui.created and MJ.prepared ~= ui and ui.accountList and ui.internetList then guarded(MJ.prepare, ui) end
    local jd = ZA.joypad()
    guarded(MJ.tickForms, ui, jd)
    guarded(MJ.tickConnect, jd)
    guarded(MJ.tickCount, ui)
end

if not MJ.ticking then
    MJ.ticking = true
    ZA.onTick(function() MJ.tick() end)
end
