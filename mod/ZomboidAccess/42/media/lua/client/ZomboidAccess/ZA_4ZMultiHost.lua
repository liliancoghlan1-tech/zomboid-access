-- Zomboid Access: hosting a multiplayer game with a controller (Host on the main menu).
-- What the game does with a controller, and what is said (vanilla files in media/lua/client/OptionScreens):
--   CoopOptionsScreen (the Host screen): the focus starts on the screen itself, {Cross} starts hosting, {Circle} goes
--     back, {Triangle} aborts a launch (CoopOptionsScreen.lua:615-620); Up goes into CoopOptionsScreenPanel
--     (633-636), whose rows are the account name (not with Steam), server settings, Manage settings, memory, soft
--     reset, delete world, delete player (28-43); {Circle} there goes back to the screen (56-63). Said: each row
--     with its value, whether this server already has a saved world, why a button is unavailable; while starting,
--     every server status line as it changes (onCoopServerMessage, 638-707), and the "save cannot be loaded"
--     warnings (prerender, 301-317).
--   ServerSettingsScreen (Manage settings...): pages that replace each other (create, 3964-3996):
--     Page1 the saved settings: actions on the right (New, Edit, Duplicate, Rename, Delete), Left goes to the list
--       of saved settings, {Circle} back (1896-1997, 2104-2125). Said: the selected settings, each action.
--     Page2 / Page4 / Page5 (new, duplicate, rename): one name box. The game focuses the box and never lets the
--       controller leave it (2355-2358, 3310-3313, 3471-3474: no Down nor {Circle} on the box, so Next was out of
--       reach). Here {Circle} or Down leaves the box like CoopUserName does (CoopUserName.lua:110-129), then {Cross}
--       goes on and {Circle} goes back; Up returns to the box. Said: the box, its text, whether the name can be used.
--     Page3.ChooseModsWindow (before editing): the mods of the server, {Cross} Next, {Triangle} Choose Mods.
--     Page3 (edit): {Cross} saves, {Circle} cancels; Up or Left: the pages list (2953-2985). In the list: headings
--       and pages, Right or {R1} into the page (2971-2985). In a page (ServerSettingsScreenPanel, 222-254): tick
--       boxes, lists and number or text boxes, each with its name, value, its section, the game's own help
--       (label.tooltip), and when a typed value is refused by the game (prerender 146-161 paints it red).
--       Server (INI) options have no translated name in the game (5095: translatedName = the option's id), so the
--       id is split into words ("Default Port"); the game's translated help follows it.
--     The special pages (MultiColumnPanelJoypad: Left and Right switch columns, 99-118): Mods, Map, Steam
--       Workshop, Spawn Regions (with SpawnRegionsNameFilePanel), Presets; and Page7, the spawn points file
--       editor. Each list, box and button is named; lists are entered with {Cross} (ServerSettingsScreenBaseListBox,
--       772-788); what was added, removed or moved is said. {Square} in a list removes its line where the game
--       only offers a mouse button for it (Map, and Page7's professions and points: doDrawItem 1291-1329).
--     Page6 (delete): the files that will be deleted, {Cross} deletes, {Circle} cancels.
--   CoopUserName (a split-screen player joining a server), CoopMapSpawnSelect (its spawn list is the shared
--     MapSpawnSelectListBox, already read by ZA_1Focus), CoopCharacterCreationProfession (see the end of this file).

local F = ZA.F
if not F then return end
ZA.MH = ZA.MH or {}
local MH = ZA.MH

-- ---------- helpers ----------

-- The game's text, "" when it fails.
local function gt(key, a1, a2)
    local ok, t
    if a2 ~= nil then ok, t = pcall(getText, key, a1, a2)
    elseif a1 ~= nil then ok, t = pcall(getText, key, a1)
    else ok, t = pcall(getText, key) end
    if not ok or t == nil or t == key then return "" end
    return tostring(t)
end

-- "HOST GAME" -> "Host game" (screen readers spell some capitals), and no colon at the end.
local function title(s)
    s = ZA.clean(s or ""):gsub("%s*:%s*$", "")
    if s ~= "" and s == s:upper() and s:find("%a") then s = s:sub(1, 1) .. s:sub(2):lower() end
    return s
end
MH.title = title

-- A title of the game with a name inside ("EDIT SETTINGS: %1"): only the game's words lose their capitals.
local function titleWith(key, name)
    local tpl = title(gt(key, "@@"))
    if tpl == "" then return ZA.clean(name or "") end
    local i = tpl:find("@@", 1, true)
    if not i then return tpl end
    return tpl:sub(1, i - 1) .. ZA.clean(name or "") .. tpl:sub(i + 2)
end

local function join(parts)
    local out = {}
    for _, t in ipairs(parts) do
        t = tostring(t or ""):gsub("[%.%s]+$", "")
        if t ~= "" then table.insert(out, t) end
    end
    return table.concat(out, ". ")
end

-- Server option ids are the only name the game shows for them: "PVPMeleeDamageModifier" -> "PVP Melee Damage
-- Modifier", so they are read as words.
local KEEP = { UPnP = true }
function MH.humanize(s)
    if not s or s == "" or s:find(" ") or KEEP[s] then return s end
    local ok, t = pcall(function()
        local r = s:gsub("(%l)(%u)", "%1 %2")
        r = r:gsub("(%u)(%u%l)", "%1 %2")
        r = r:gsub("(%a)(%d)", "%1 %2")
        return r
    end)
    return ok and t or s
end

-- A control's help: a string, or the table a combo box keeps it in ({ defaultTooltip = ... }).
local function tipOf(ui)
    local t = ui and ui.tooltip
    if type(t) == "table" then t = t.defaultTooltip end
    if type(t) ~= "string" then return "" end
    return ZA.clean(t)
end

local function isOn(b) return b and b.enable ~= false end

-- Place of the focused row among the rows the controller can reach (hidden rows don't count).
local function rowPos(p)
    local rows = p.joypadButtonsY or {}
    local cur = p.joypadIndexY or 1
    local i, n = 0, 0
    for y = 1, #rows do
        local vis = true
        if p.getVisibleChildren then
            local ok, ch = pcall(p.getVisibleChildren, p, y)
            vis = ok and ch ~= nil and #ch > 0
        end
        if vis then
            n = n + 1
            if y == cur then i = n end
        end
    end
    if i == 0 then i = cur end
    return i, n
end

-- Words and value of a plain control. A third result is the key while a combo box's list is open (the line Up
-- and Down are on), so each move is said with its place.
local function controlWords(c)
    if c.isCombobox or c.Type == "ISComboBox" then
        local w, v = F.describeBare(c)
        if c.expanded and c.popup then return w, v, c.popup.selected or c end
        return w, v
    elseif c.Type == "ISTickBox" then
        local v = (c.selected and c.selected[1]) and ZA.tr("ZMultiHost_On") or ZA.tr("ZMultiHost_Off")
        return ZA.tr("ZMultiHost_TickHint", v), v
    elseif c.Type == "ISTextEntryBox" then
        local t = c:getText() or ""
        local v = t == "" and ZA.tr("ZMultiHost_Empty") or t
        return ZA.tr("ZMultiHost_EditHint", v), v
    elseif c.Type == "ISButton" then
        local w = ZA.tr("Focus_Button", title(c.title or ""))
        if not isOn(c) then return w .. ", " .. ZA.tr("ZMultiHost_Unavailable"), ZA.tr("ZMultiHost_Unavailable") end
        return w, ""
    end
    return F.describeBare(c)
end

local function setLabel(ui, text)
    if ui and text and text ~= "" then ui.zaLabel = title(text) end
end

-- Is this element inside the server settings screen? (Page1..Page7 share their names with the Workshop screen's
-- pages, WorkshopSubmitScreen.lua:7-16, so the type alone doesn't tell.)
local function inSettings(ui)
    local sss = ServerSettingsScreen and ServerSettingsScreen.instance
    local p = ui
    for _ = 1, 10 do
        if p == nil then return false end
        if (sss and p == sss) or p.Type == "ServerSettingsScreen" then return true end
        p = p.parent or p.pageEdit
    end
    return false
end
MH.inSettings = inSettings

-- The intros of types whose names other screens also use (PageN) or generic lists: by exact Lua type, through
-- F.screenIntro (the unique types use F.screens like everywhere else).
MH.intros = MH.intros or {}

-- ---------- error boxes that the game shows without the controller ----------
-- CoopOptionsScreen:onStartButtonDown (504-533) and Page2:onButtonNext (2341-2344) open an OK box without giving it
-- the controller: nothing was said and {Cross} couldn't close it. Give it the focus; ISModalDialog:destroy gives the
-- focus back (ISModalDialog.lua:50-53), and ZA_4ZScreens reads its text.
function MH.focusNewModals(jd, fn, ...)
    if not (ISModalDialog and ISModalDialog.new) then return fn(...) end
    local made = {}
    local origNew = ISModalDialog.new
    ISModalDialog.new = function(cls, ...)
        local o = origNew(cls, ...)
        table.insert(made, o)
        return o
    end
    local ok, a, b = pcall(fn, ...)
    ISModalDialog.new = origNew
    if not ok then error(a, 0) end
    local m = made[#made]
    if jd and m and jd.focus ~= m and not m.yesno then
        m.prevFocus = jd.focus
        jd.focus = m
        pcall(updateJoypadFocus, jd)
    end
    return a, b
end

-- ======================================================================
-- The Host screen (CoopOptionsScreen)
-- ======================================================================

local function hostStatus(s) return ZA.clean(s.serverStatus or "") end
local function hostWarning(s)
    local r = s.richText
    if not r then return "" end
    local vis = false
    pcall(function() vis = r:isVisible() end)
    return vis and ZA.clean(r.text or "") or ""
end
MH.hostStatus, MH.hostWarning = hostStatus, hostWarning

local function nameHost(s)
    setLabel(s.accountNameEntry, gt("UI_coopscreen_account_name"))
    setLabel(s.settingsComboBox, gt("UI_coopscreen_server_name"))
    setLabel(s.memoryComboBox, gt("UI_coopscreen_server_memory"))
end

F.screens.CoopOptionsScreen = {
    name = title(gt("UI_coopscreen_title")),
    intro = function(s)
        local parts = { title(gt("UI_coopscreen_title")), hostStatus(s), hostWarning(s) }
        if s.uiStatus == nil or s.uiStatus == "idle" then table.insert(parts, ZA.tr("ZMultiHost_HostHint")) end
        table.insert(parts, F.buttonHints(s))
        return join(parts)
    end,
}

F.screens.CoopOptionsScreenPanel = {
    name = ZA.tr("ZMultiHost_PanelName"),
    intro = function(p)
        local start = p.parent and p.parent.startButton
        return join({ ZA.tr("ZMultiHost_PanelName"), ZA.tr("ZMultiHost_PanelHint", title(start and start.title or "")) })
    end,
}

-- What a host button does, and why it can't be used now (checkWorldExists, checkPlayerExists: 554-567).
local function hostButtonWords(s, b)
    local what, why = "", ""
    if b == s.settingsButton then what = ZA.tr("ZMultiHost_ManageHint")
    elseif b == s.softResetButton then what, why = ZA.tr("ZMultiHost_SoftResetHint"), ZA.tr("ZMultiHost_NoWorld")
    elseif b == s.deleteWorldButton then what, why = ZA.tr("ZMultiHost_DeleteWorldHint"), ZA.tr("ZMultiHost_NoWorld")
    elseif b == s.deletePlayerButton then what, why = ZA.tr("ZMultiHost_DeletePlayerHint"), ZA.tr("ZMultiHost_NoPlayer") end
    local w = ZA.tr("Focus_Button", title(b.title or ""))
    if not isOn(b) then
        return w .. ", " .. ZA.tr("ZMultiHost_Unavailable") .. (why ~= "" and (", " .. why) or ""), ZA.tr("ZMultiHost_Unavailable")
    end
    return w .. (what ~= "" and (". " .. what) or ""), ""
end

local function validUser(name)
    local ok, v = pcall(isValidUserName, name)
    return not ok or v ~= false
end

F.readers.CoopOptionsScreenPanel = function(p)
    local s = p.parent
    local child = F.focusedChild(p)
    if not (s and child) then return nil end
    nameHost(s)
    if child.Type == "ISButton" then
        local w, v = hostButtonWords(s, child)
        return child, w, v
    end
    local w, v, key = controlWords(child)
    if key then return key, w, v end
    local lbl = F.labelFor(child)
    if lbl ~= "" then w = lbl .. ": " .. w end
    if child == s.accountNameEntry and not validUser(child:getText() or "") then
        w = w .. ", " .. ZA.tr("ZMultiHost_InvalidName")
        v = v .. ", " .. ZA.tr("ZMultiHost_InvalidName")
    elseif child == s.settingsComboBox and s.deleteWorldButton then
        -- the world of these settings: the game turns Delete world on only when one is saved
        local world = isOn(s.deleteWorldButton) and ZA.tr("ZMultiHost_WorldSaved") or ZA.tr("ZMultiHost_WorldNew")
        w = w .. ". " .. world
        v = v .. ", " .. world
    end
    return child, w, v
end

-- Wrapped at load, before MainScreen builds the screen: the Start button keeps the function it is given then.
if CoopOptionsScreen and CoopOptionsScreen.onStartButtonDown and not rawget(CoopOptionsScreen, "zaMHStart") then
    rawset(CoopOptionsScreen, "zaMHStart", true)
    local origStart = CoopOptionsScreen.onStartButtonDown
    CoopOptionsScreen.onStartButtonDown = function(self, ...)
        local jd = self.joyfocus or (self.panel and self.panel.joyfocus) or ZA.joypad()
        return MH.focusNewModals(jd, origStart, self, ...)
    end
end

-- While the server starts, the status line changes on its own (Launching, Loading world, Server started...) and
-- the warnings appear when another server's world can't be loaded: say each change.
MH.host = MH.host or {}
function MH.hostTick()
    local s = CoopOptionsScreen and CoopOptionsScreen.instance
    local vis = false
    if s then pcall(function() vis = s:isVisible() end) end
    local h = MH.host
    if not vis then h.status, h.warn = nil, nil return end
    local st, w = hostStatus(s), hostWarning(s)
    if h.status == nil then h.status, h.warn = st, w return end   -- just opened: the intro says them
    if st ~= h.status then
        h.status = st
        if st ~= "" then ZA.say(st) end
    end
    if w ~= h.warn then
        h.warn = w
        if w ~= "" then ZA.queue(w) end
    end
end

-- ======================================================================
-- Manage settings (ServerSettingsScreen)
-- ======================================================================

F.screens.ServerSettingsScreen = { name = title(gt("UI_ServerSettings_Title1")) }

local function twoButtons(a, b)
    return ZA.tr("ZMultiHost_TwoButtons", title(a and a.title or ""), title(b and b.title or ""))
end

-- The edit page's Save and Cancel, in the game's words, from any part of it.
local function saveCancel(ui)
    local p = ui
    for _ = 1, 4 do
        if not p then break end
        if p.Type == "Page3" or p.Type == "Page7" then break end
        p = p._instance or p.pageEdit or p.parent
    end
    local a = p and p.buttonAccept
    local c = p and p.buttonCancel
    return title(a and a.title or ""), title(c and c.title or "")
end

-- ---------- Page1: the saved settings ----------

local function page1Selected(p)
    local lb = p.listbox
    local it = lb and lb.items and lb.items[lb.selected]
    return it and ZA.clean(it.text or "") or nil
end

MH.intros.Page1 = function(p)
    if not inSettings(p) then return nil end
    local sel = page1Selected(p)
    local hint = sel and ZA.tr("ZMultiHost_P1Hint", sel) or ZA.tr("ZMultiHost_P1None", title(gt("UI_ServerSettings_ButtonNew")))
    return join({ title(gt("UI_ServerSettings_Title1")), hint, F.buttonHints(p) })
end

F.readers.Page1 = function(p)
    if not inSettings(p) then return nil end
    local child = F.focusedChild(p)
    if not child then return nil end
    local w, v = controlWords(child)
    local i, n = rowPos(p)
    return child, w .. ZA.pos(i, n), v
end

-- ---------- Page2 / Page4 / Page5: one name box ----------

local function nameValid(p, t, mustDiffer)
    local ok, v = pcall(function()
        local m = getServerSettingsManager()
        if mustDiffer and p.settings and t == p.settings:getName() then return false end
        return m:isValidNewName(t) and m:settingsFolderValidLengthChecks(t)
    end)
    if ok then return v and true or false end
    return nil
end

local NAMEPAGES = {
    Page2 = { label = "UI_ServerSettings_LabelNewName", accept = "nextButton", cancel = "backButton",
        title = function(p) return title(gt("UI_ServerSettings_Title2")) end },
    Page4 = { label = "UI_ServerSettings_LabelDuplicate", accept = "buttonAccept", cancel = "buttonCancel", differ = true,
        title = function(p) return titleWith("UI_ServerSettings_Title4", p.settings and p.settings:getName() or "") end },
    Page5 = { label = "UI_ServerSettings_LabelRename", accept = "buttonAccept", cancel = "buttonCancel", differ = true,
        title = function(p) return titleWith("UI_ServerSettings_Title5", p.settings and p.settings:getName() or "") end },
}

-- Shared by the three settings name pages and CoopUserName: the box while it has the focus, else the two buttons.
local function nameBoxReader(p, label, accept, cancel, valid)
    local e = p.entry
    if not e then return nil end
    local t = e:getText() or ""
    local ok = valid(t)
    if ok == nil then ok = isOn(accept) end
    if e.joypadFocused and (p.joypadIndexY or 1) ~= 0 then
        local w, v = controlWords(e)
        w = title(label) .. ": " .. w
        if not ok then
            w = w .. ", " .. ZA.tr("ZMultiHost_NameTaken")
            v = v .. ", " .. ZA.tr("ZMultiHost_NameTaken")
        end
        return e, w, v
    end
    if not ok then return "buttons", ZA.tr("ZMultiHost_NameButtonsLocked", title(cancel and cancel.title or "")), "" end
    return "buttons", ZA.tr("ZMultiHost_NameButtons", title(accept and accept.title or ""), title(cancel and cancel.title or "")), ""
end

for t, spec in pairs(NAMEPAGES) do
    MH.intros[t] = function(p)
        if not inSettings(p) then return nil end
        return join({ spec.title(p), ZA.tr("ZMultiHost_NameIntro", title(p[spec.accept] and p[spec.accept].title or ""),
            title(p[spec.cancel] and p[spec.cancel].title or "")) })
    end
    F.readers[t] = function(p)
        if not inSettings(p) then return nil end
        return nameBoxReader(p, gt(spec.label), p[spec.accept], p[spec.cancel],
            function(text) return nameValid(p, text, spec.differ) end)
    end
end

-- {Circle} or Down leaves the name box, Up comes back to it (the classes are local to the game's file: reached
-- through a page's metatable, once). Same moves as CoopUserName.lua:110-129.
local function leaveBox(self, jd)
    self.entry:setJoypadFocused(false, jd)
    self.joypadIndexY = 0
end
function MH.patchNamePage(page)
    local cls = page and getmetatable(page)
    if not cls or rawget(cls, "zaMHName") then return end
    rawset(cls, "zaMHName", true)
    local origDown, origUp, origDirDown = cls.onJoypadDown, cls.onJoypadDirUp, cls.onJoypadDirDown
    rawset(cls, "onJoypadDown", function(self, button, jd)
        if button == Joypad.BButton and self.entry and self.entry.joypadFocused then leaveBox(self, jd) return end
        return origDown(self, button, jd)
    end)
    rawset(cls, "onJoypadDirDown", function(self, jd)
        if self.entry and self.entry.joypadFocused then leaveBox(self, jd) return end
        if (self.joypadIndexY or 1) == 0 then return end
        return origDirDown(self, jd)
    end)
    rawset(cls, "onJoypadDirUp", function(self, jd)
        if self.entry and not self.entry.joypadFocused then self:setJoypadFocus(self.entry, jd) return end
        return origUp(self, jd)
    end)
end

-- ---------- Page3.ChooseModsWindow: the mods, before editing ----------

local function modsLine(lb)
    local names = {}
    for _, it in ipairs(lb and lb.items or {}) do table.insert(names, MH.itemWords(lb, it)) end
    local label = title(gt("UI_ServerSettings_ListOfMods"))
    return label .. ": " .. (#names == 0 and ZA.tr("ZMultiHost_None") or table.concat(names, ", "))
end

F.screens["Page3.ChooseModsWindow"] = {
    name = title(gt("UI_ServerSettings_ListOfMods")),
    intro = function(p)
        if not inSettings(p) then return nil end
        return join({ modsLine(p.listbox), F.buttonHints(p) })
    end,
}

-- ---------- Page3: edit ----------

local function editTitle(p)
    return titleWith("UI_ServerSettings_Title3", p.settings and p.settings:getName() or "")
end

MH.intros.Page3 = function(p)
    if not inSettings(p) then return nil end
    return join({ editTitle(p), ZA.tr("ZMultiHost_EditHint3"), twoButtons(p.buttonAccept, p.buttonCancel) })
end

-- The pages list: categories (Page3:create 2420: the raw names "INI" and "Sandbox") and pages.
local function pagesReader(p)
    local it = p.items and p.items[p.selected]
    if not it then return p, ZA.tr("ZMultiHost_EmptyList"), "" end
    local d = it.item or {}
    local s
    if d.category then
        local c = d.category.name == "INI" and ZA.tr("ZMultiHost_CatServer") or ZA.tr("ZMultiHost_CatSandbox")
        s = ZA.tr("ZMultiHost_Heading", c)
    else
        s = ZA.clean(it.text or "")
        local panel = d.panel
        local k = panel and not (d.page and d.page.customui) and panel.settingNames and #panel.settingNames or 0
        if k > 0 then s = ZA.tr(k == 1 and "ZMultiHost_PageCountOne" or "ZMultiHost_PageCountMany", s, k) end
    end
    return it, s .. ZA.pos(p.selected, #p.items), ""
end

-- The two plain ISScrollingListBox of this screen: Page1's saved settings and Page3's pages.
local function whichList(p)
    local par = p and p.parent
    if not (par and par.listbox == p and inSettings(par)) then return nil end
    if par.Type == "Page1" then return "settings" end
    if par.Type == "Page3" then return "pages" end
    return nil
end

MH.intros.ISScrollingListBox = function(p)
    local w = whichList(p)
    if w == "settings" then return join({ ZA.tr("ZMultiHost_ListName"), ZA.tr("ZMultiHost_ListHint") }) end
    if w == "pages" then
        local save, cancel = saveCancel(p.parent)
        return join({ ZA.tr("ZMultiHost_PagesName"), ZA.tr("ZMultiHost_PagesHint", save, cancel) })
    end
    return nil
end

if not MH.listWrapper or F.readers.ISScrollingListBox ~= MH.listWrapper then
    local prevList = F.readers.ISScrollingListBox or F.listReader
    MH.listWrapper = function(p)
        local w = whichList(p)
        if w == "pages" then return pagesReader(p) end
        if w == "settings" then
            local it = p.items and p.items[p.selected]
            if not it then return p, ZA.tr("ZMultiHost_EmptyList"), "" end
            return it, ZA.clean(it.text or "") .. ZA.pos(p.selected, #p.items), ""
        end
        return prevList(p)
    end
    F.readers.ISScrollingListBox = MH.listWrapper
end

-- ---------- a page of settings (ServerSettingsScreenPanel; ServerSettingsScreenGroupBox is the same reader,
-- though no page of 42.21 uses a group box: SettingsTable has no groupBox) ----------

local function settingName(p, child)
    for _, name in ipairs(p.settingNames or {}) do
        if p.controls and p.controls[name] == child then return name end
    end
    return nil
end

-- The section heading above a control (the big labels between rows, createPanel 2605-2614).
local function sectionOf(p, child)
    local best, bestY = nil, -1
    local cy = child:getY()
    for _, t in ipairs(p.titles or {}) do
        local ty = t:getY()
        if ty <= cy and ty > bestY then best, bestY = t, ty end
    end
    return best and ZA.clean(best.name or "") or nil
end

-- What the game itself accepts (ServerSettingsScreenPanel:prerender 146-161 paints a refused value red).
local function validValue(p, name, text)
    local ok, v = pcall(function()
        local inst = p._instance
        local opts = (p.category == "INI") and inst.settings:getServerOptions() or inst.settings:getSandboxOptions()
        local o = opts:getOptionByName(name)
        if not o then return true end
        return o:isValidString(text)
    end)
    return (not ok) or v ~= false
end

local function pageName(p)
    local inst = p._instance or p.pageEdit or p.parent
    local lb = inst and inst.listbox
    local it = lb and lb.items and lb.items[lb.selected]
    if it and it.item and it.item.panel == p then return ZA.clean(it.text or "") end
    return ZA.tr("ZMultiHost_SettingsName")
end

MH.lastSection = MH.lastSection or {}
local function settingsReader(p)
    if not inSettings(p) then return nil end
    local child = F.focusedChild(p)
    if not child then return p, ZA.tr("ZMultiHost_NoSettings"), "" end
    local i, n = rowPos(p)
    if p.tickBox and child == p.tickBox then
        -- a group box's "use the defaults" box (ServerSettingsScreenGroupBox:onTicked 311-330)
        local w, v = controlWords(child)
        return child, title(p.tickBoxLabel or "") .. ": " .. w .. ZA.pos(i, n) .. ". " .. ZA.tr("ZMultiHost_GroupNote"), v
    end
    local name = settingName(p, child)
    local label = name and p.labels and p.labels[name]
    local ttl = label and ZA.clean(label.name or "") or F.labelFor(child)
    if p.category == "INI" then ttl = MH.humanize(ttl) end
    local w, v, key = controlWords(child)
    if child.Type == "ISTextEntryBox" and name and not validValue(p, name, child:getText() or "") then
        w = w .. ", " .. ZA.tr("ZMultiHost_Invalid")
        v = v .. ", " .. ZA.tr("ZMultiHost_Invalid")
    end
    if key then return key, w, v end
    local s = ttl .. ": " .. w .. ZA.pos(i, n)
    local sec = sectionOf(p, child)
    if sec and sec ~= "" and sec ~= MH.lastSection[p] then s = sec .. ". " .. s end
    MH.lastSection[p] = sec
    local tip = tipOf(label)
    if tip == "" then tip = tipOf(child) end
    if tip ~= "" then s = s .. ". " .. tip end
    return child, s, v
end
MH.settingsReader = settingsReader

for _, t in ipairs({ "ServerSettingsScreenPanel", "ServerSettingsScreenGroupBox" }) do
    F.readers[t] = settingsReader
    F.screens[t] = {
        name = ZA.tr("ZMultiHost_SettingsName"),
        intro = function(p)
            if not inSettings(p) then return nil end
            local save, cancel = saveCancel(p)
            return join({ pageName(p), ZA.tr("ZMultiHost_SettingsHint", save, cancel) })
        end,
    }
end

-- ---------- the special pages (lists with buttons) and Page7 ----------

-- Names for the boxes and lists whose label sits above them (the game's own words).
local function nameCustom(p)
    if p.zaMHNamed then return end
    p.zaMHNamed = true
    local t = p.Type
    if t == "ServerSettingsScreenMapsPanel" then
        setLabel(p.listbox, gt("UI_ServerSettings_ListOfMaps"))
        setLabel(p.comboBox, gt("UI_ServerSettings_AddInstalledMap"))
        setLabel(p.entry, gt("UI_ServerSettings_AddOtherMap"))
    elseif t == "ServerSettingsScreenWorkshopPanel" then
        setLabel(p.listbox, gt("UI_ServerSettings_ListOfWorkshopItems"))
        setLabel(p.comboBox, gt("UI_ServerSettings_AddInstalledWorkshopItem"))
        setLabel(p.entry, gt("UI_ServerSettings_AddOtherWorkshopItem"))
    elseif t == "ServerSettingsScreenModsPanel" then
        setLabel(p.listbox, gt("UI_ServerSettings_ListOfMods"))
    elseif t == "SpawnRegionsPanel" then
        setLabel(p.listbox, gt("UI_ServerSettingGroup_SpawnRegions"))
        if p.entry then p.entry.zaLabel = ZA.tr("ZMultiHost_SpawnPoint") end
        local nf = p.nameFilePanel
        if nf then
            if nf.entryName then nf.entryName.zaLabel = ZA.tr("ZMultiHost_LblName") end
            if nf.entryFile then nf.entryFile.zaLabel = ZA.tr("ZMultiHost_LblFile") end
        end
    elseif t == "SandboxPresetPanel" then
        setLabel(p.listbox, gt("UI_ServerSettings_ListOfPresets"))
    elseif t == "Page7" then
        setLabel(p.profListBox, gt("UI_ServerSettings_ListOfSpawnProfessions"))
        setLabel(p.profComboBox, gt("UI_ServerSettings_AddSpawnProfession"))
        setLabel(p.entryOtherProfession, gt("UI_ServerSettings_AddOtherSpawnProfession"))
        setLabel(p.pointListBox, gt("UI_ServerSettings_ListOfSpawnPoints"))
        setLabel(p.entryAddSpawnPoint, gt("UI_ServerSettings_AddSpawnPoint"))
    end
end

-- One line of one of these lists, the way the game draws it (doDrawItem of each list box).
function MH.itemWords(lb, it)
    local d = it and it.item
    local par = lb and lb.parent
    if type(d) == "table" then
        if d.modID then
            if d.modInfo then
                local name = it.text
                pcall(function() name = d.modInfo:getName() end)
                return ZA.clean(name or d.modID)
            end
            local unknown = gt("UI_modselector_UnknownMod")
            return ZA.clean(d.modID) .. (unknown ~= "" and (", " .. unknown) or "")
        end
        if d.workshopID then
            local det = par and par.itemDetails and par.itemDetails[d.workshopID]
            local name = nil
            if det then pcall(function() name = det:getTitle() end) end
            return name and (ZA.clean(name) .. ", " .. tostring(d.workshopID)) or tostring(d.workshopID)
        end
        if d.name ~= nil and d.file ~= nil then
            if d.name == "" and d.file == "" then return ZA.tr("ZMultiHost_RegionEmpty") end
            return ZA.tr("ZMultiHost_Region", d.name ~= "" and ZA.clean(d.name) or "?", d.file ~= "" and d.file or "?")
        end
        if d.points then
            local n = #d.points
            local key = n == 0 and "ZMultiHost_PointsNone" or (n == 1 and "ZMultiHost_PointsOne" or "ZMultiHost_PointsMany")
            return ZA.tr(key, ZA.clean(it.text or ""), n)
        end
    end
    local text = tostring(it and it.text or "")
    if par and par.pointListBox == lb then
        local x, y, z = text:match("^(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
        if x then return ZA.tr("ZMultiHost_Point", x, y, z) end
    end
    return ZA.clean(text)
end

-- A list seen as one row of its page: its name, how many lines, the selected one.
local function listRow(lb)
    local label = lb.zaLabel or ""
    local items = lb.items or {}
    if #items == 0 then return ZA.tr("ZMultiHost_ListRowEmpty", label) end
    if #items == 1 then return ZA.tr("ZMultiHost_ListRowOne", label, MH.itemWords(lb, items[1])) end
    local it = items[lb.selected] or items[1]
    return ZA.tr("ZMultiHost_ListRow", label, #items, MH.itemWords(lb, it))
end

-- The region's name and file boxes, shown only with a controller (SpawnRegionsPanel:prerender 632-643).
local function regionFields(nf)
    local lb = nf.parent and nf.parent.listbox
    local it = lb and lb.items and lb.items[lb.selected]
    if not it then return ZA.tr("ZMultiHost_RegionNone") end
    local d = it.item or {}
    local n = (d.name or "") == "" and ZA.tr("ZMultiHost_Empty") or d.name
    local f = (d.file or "") == "" and ZA.tr("ZMultiHost_Empty") or d.file
    return ZA.tr("ZMultiHost_RegionFields", n, f)
end

-- "Preset applied: Apocalypse" (SandboxPresetPanel:onButtonApplyPreset 1787-1797 says nothing). The button keeps
-- the function it was made with, so the instance's onclick is wrapped.
local function patchPreset(p)
    local b = p.buttonApplyPreset
    if not b or b.zaMH or not b.onclick then return end
    b.zaMH = true
    local orig = b.onclick
    b.onclick = function(target, btn, ...)
        local r = orig(target, btn, ...)
        local it = p.listbox and p.listbox.items and p.listbox.items[p.listbox.selected]
        if it then ZA.say(ZA.tr("ZMultiHost_PresetApplied", ZA.clean(it.text or ""))) end
        return r
    end
end

local function page7Buttons(p)
    local s = ZA.tr("ZMultiHost_P7Buttons", title(p.buttonAccept and p.buttonAccept.title or ""),
        title(p.buttonCancel and p.buttonCancel.title or ""))
    if p.buttonAccept and not isOn(p.buttonAccept) then
        s = ZA.tr("ZMultiHost_P7Locked", title(p.buttonCancel and p.buttonCancel.title or ""))
        local tip = tipOf(p.buttonAccept)
        if tip ~= "" then s = s .. ". " .. tip end
    end
    return s
end

local function customReader(p)
    if not inSettings(p) then return nil end
    nameCustom(p)
    patchPreset(p)
    if p.Type == "Page7" and (p.joypadIndexY or 1) == 0 then return "buttons", page7Buttons(p), "" end
    local child = F.focusedChild(p)
    if not child then return nil end
    local w, v, key
    if child.items then
        w, v = listRow(child), ""
    elseif child.Type == "SpawnRegionsNameFilePanel" then
        w, v = regionFields(child), ""
    else
        w, v, key = controlWords(child)
        if key then return key, w, v end
        if child.Type ~= "ISButton" then
            local lbl = F.labelFor(child)
            if lbl ~= "" then w = lbl .. ": " .. w end
        end
    end
    local i, n = rowPos(p)
    w = w .. ZA.pos(i, n)
    local tip = tipOf(child)
    if tip ~= "" then w = w .. ". " .. tip end
    return child, w, v
end
MH.customReader = customReader

local CUSTOM = { "ServerSettingsScreenModsPanel", "ServerSettingsScreenMapsPanel", "ServerSettingsScreenWorkshopPanel",
    "SpawnRegionsPanel", "SandboxPresetPanel" }
for _, t in ipairs(CUSTOM) do
    F.readers[t] = customReader
    F.screens[t] = {
        name = ZA.tr("ZMultiHost_SettingsName"),
        intro = function(p)
            if not inSettings(p) then return nil end
            nameCustom(p)
            local cols = p.multiColumnUI and #p.multiColumnUI or 1
            local save, cancel = saveCancel(p)
            return join({ pageName(p), ZA.tr(cols > 1 and "ZMultiHost_ColsHint" or "ZMultiHost_OneColHint", save, cancel) })
        end,
    }
end

-- Page7 (Edit File of a spawn region): professions on the left, their spawn points on the right; Down past the
-- last row reaches Save and Cancel (Page7:onJoypadDirDown 3932-3942, updateWhenVisible 3726-3734).
F.readers.Page7 = customReader
MH.intros.Page7 = function(p)
    if not inSettings(p) then return nil end
    nameCustom(p)
    local file = p.region and p.region.file or ""
    local save, cancel = saveCancel(p)
    return join({ titleWith("UI_ServerSettings_Title7", file), ZA.tr("ZMultiHost_P7Hint", save, cancel) })
end

-- Page6: delete. Which files go (Page6:render 3524-3561).
MH.intros.Page6 = function(p)
    if not inSettings(p) then return nil end
    local name = p.settings and p.settings:getName() or ""
    local files = {}
    pcall(function()
        local suffixes = getServerSettingsManager():getSuffixes()
        for i = 1, suffixes:size() do
            local f = name .. suffixes:get(i - 1)
            if serverFileExists(f) then table.insert(files, f) end
        end
    end)
    local parts = { titleWith("UI_ServerSettings_Title6", name) }
    if #files > 0 then table.insert(parts, ZA.tr("ZMultiHost_DeleteFiles", table.concat(files, ", "))) end
    table.insert(parts, twoButtons(p.buttonAccept, p.buttonCancel))
    return join(parts)
end

-- ---------- inside a list (after {Cross} on it) ----------

local function removable(lb)
    return lb.onRemoveItem ~= nil and not lb.disableRemove
end

-- {Square} removes the selected line where the game lets only the mouse do it (the list's own remove button,
-- doDrawItem 1310-1326). The class is the list's metatable (ServerSettingsScreenMapsListBox: the Map list and
-- both of Page7's lists).
function MH.patchRemovable(lb)
    if not removable(lb) then return end
    local cls = getmetatable(lb)
    if not cls or rawget(cls, "zaMHRemove") then return end
    rawset(cls, "zaMHRemove", true)
    local orig = cls.onJoypadDown
    rawset(cls, "onJoypadDown", function(self, button, jd)
        if button == Joypad.XButton and removable(self) then
            local i = self.selected
            if self.items and self.items[i] then self:onRemoveItem(i) end
            return
        end
        return orig(self, button, jd)
    end)
end

local LISTS = { "ServerSettingsScreenModsListBox", "ServerSettingsScreenMapsListBox",
    "ServerSettingsScreenWorkshopListBox", "SpawnRegionsListBox" }
for _, t in ipairs(LISTS) do
    F.readers[t] = function(lb)
        if not inSettings(lb) then return F.listReader(lb) end
        if lb.parent then nameCustom(lb.parent) end
        MH.patchRemovable(lb)
        local it = lb.items and lb.items[lb.selected]
        if not it then return lb, ZA.tr("ZMultiHost_EmptyList"), "" end
        return it, MH.itemWords(lb, it) .. ZA.pos(lb.selected, #lb.items), ""
    end
    F.screens[t] = {
        name = ZA.tr("ZMultiHost_ListGeneric"),
        intro = function(lb)
            if not inSettings(lb) then return nil end
            if lb.parent then nameCustom(lb.parent) end
            local name = lb.zaLabel or ZA.tr("ZMultiHost_ListGeneric")
            return join({ name, ZA.tr(removable(lb) and "ZMultiHost_InListHintRemove" or "ZMultiHost_InListHint") })
        end,
    }
end

-- The region's name and file boxes (after {Cross} on them; {Circle} goes back, 482-488).
F.screens.SpawnRegionsNameFilePanel = {
    name = ZA.tr("ZMultiHost_RegionFieldsName"),
    intro = function() return join({ ZA.tr("ZMultiHost_RegionFieldsName"), ZA.tr("ZMultiHost_RegionFieldsHint") }) end,
}
F.readers.SpawnRegionsNameFilePanel = function(p)
    if p.parent then nameCustom(p.parent) end
    local child = F.focusedChild(p)
    if not child then return nil end
    local w, v = controlWords(child)
    local lbl = F.labelFor(child)
    if lbl ~= "" then w = lbl .. ": " .. w end
    local i, n = rowPos(p)
    return child, w .. ZA.pos(i, n), v
end

-- ---------- what changed in a list ----------
-- Adding (a box, a button, Enter in a text box), removing and moving lines happen while the focus stays put:
-- compare the lines (by the game's own line tables, so a renamed spawn region isn't taken for a new one).

MH.watched = MH.watched or {}
local function snapshot(lb, ctx)
    local refs, texts = {}, {}
    for i, it in ipairs(lb.items or {}) do
        refs[i] = it
        texts[i] = MH.itemWords(lb, it)
    end
    return { refs = refs, texts = texts, ctx = ctx }
end

function MH.watchList(lb, ctx)
    ctx = ctx or ""
    local new = snapshot(lb, ctx)
    local old = MH.watched[lb]
    MH.watched[lb] = new
    if not old or old.ctx ~= ctx then return nil end
    local inNew, inOld = {}, {}
    for _, r in ipairs(new.refs) do inNew[r] = true end
    for _, r in ipairs(old.refs) do inOld[r] = true end
    local added, removed, at = {}, {}, {}
    for i, r in ipairs(new.refs) do
        if not inOld[r] then table.insert(added, new.texts[i]); table.insert(at, i) end
    end
    for i, r in ipairs(old.refs) do
        if not inNew[r] then table.insert(removed, old.texts[i]) end
    end
    if #added == 0 and #removed == 0 then return nil end
    -- Move Up / Move Down take the line out and put a new one back (ServerSettingsScreenMapsPanel 1066-1086)
    if #added == 1 and #removed == 1 and added[1] == removed[1] then
        return ZA.tr("ZMultiHost_Moved", added[1]) .. ZA.pos(at[1], #new.refs)
    end
    local parts = {}
    if #removed > 0 then table.insert(parts, ZA.tr("ZMultiHost_Removed", table.concat(removed, ", "))) end
    if #added > 0 then table.insert(parts, ZA.tr("ZMultiHost_Added", table.concat(added, ", "))) end
    return table.concat(parts, ". ")
end

-- Page7 refills its points list for each profession (fillPointList 3800-3808): that is not an edit.
local function ctxOf(lb)
    local par = lb.parent
    if par and par.pointListBox == lb and par.profListBox then
        return par.profListBox.items and par.profListBox.items[par.profListBox.selected] or ""
    end
    return ""
end

-- The lists to watch: the one the focus is in, else those in the focused column, else the page's list.
local function watchTargets(f)
    if f.items then return { f } end
    local t = {}
    local col = f.multiColumnUI and f.multiColumnUI[f.multiColumnIndex or 1]
    for _, ui in ipairs(col or {}) do
        if ui.items then table.insert(t, ui) end
    end
    if #t == 0 and f.listbox and f.listbox.items then table.insert(t, f.listbox) end
    return t
end

function MH.listTick()
    local jd = ZA.joypad()
    local f = jd and jd.focus
    if not f or not inSettings(f) then MH.owner = nil return end
    if f.Type == "ISScrollingListBox" then return end   -- Page1 and Page3's lists change only on their own pages
    local owner = (f.items and f.parent) or f
    if owner ~= MH.owner then
        MH.owner = owner
        MH.watched = {}
    end
    for _, lb in ipairs(watchTargets(f)) do
        local msg = MH.watchList(lb, ctxOf(lb))
        if msg and msg ~= "" then ZA.queue(msg) end
    end
end

-- ---------- patches that need the screen built ----------

function MH.patchSettings()
    local sss = ServerSettingsScreen and ServerSettingsScreen.instance
    if not sss or not sss.pageSpawnPoints or MH.patchedFor == sss then return end
    MH.patchedFor = sss
    MH.patchNamePage(sss.pageNew)
    MH.patchNamePage(sss.pageDuplicate)
    MH.patchNamePage(sss.pageRename)
    local b = sss.pageNew and sss.pageNew.nextButton
    if b and b.onclick and not b.zaMH then
        b.zaMH = true
        local orig = b.onclick
        b.onclick = function(...) return MH.focusNewModals(ZA.joypad(), orig, ...) end
    end
end

-- ======================================================================
-- Split-screen joining (CoopCharacterCreation's screens)
-- ======================================================================

-- CoopUserName: the name of a second player on the server (CoopUserName.lua:98-129: {Circle} or Down leave the
-- box, then {Cross} Next, {Circle} Back; Up back to the box).
F.screens.CoopUserName = {
    name = title(gt("UI_servers_username")),
    intro = function(p)
        return join({ title(gt("UI_servers_username")), ZA.tr("ZMultiHost_NameIntro", title(p.nextButton and p.nextButton.title or ""),
            title(p.backButton and p.backButton.title or "")) })
    end,
}
F.readers.CoopUserName = function(p)
    return nameBoxReader(p, gt("UI_servers_username"), p.nextButton, p.backButton, function(t) return validUser(t) end)
end

-- CoopMapSpawnSelect gives the focus to its list at once (MapSpawnSelect:onGainJoypadFocus 850-857), which
-- ZA_1Focus reads (MapSpawnSelectListBox); this only names the screen if the focus ever rests on it.
F.screens.CoopMapSpawnSelect = { name = ZA.tr("Focus_ScrSpawn"), hint = ZA.tr("Focus_ScrSpawnHint") }

-- CoopCharacterCreationProfession (CoopCharacterCreationProfession.lua:3) has the same lists as the single-player
-- screen, but ZA_2CharCreate finds them only under a parent of type "CharacterCreationProfession" (its screen()),
-- so the coop lists said their raw type. While its reader and intro run, the coop screen answers to that name.
-- (ZA_2CharCreate's L1/R1 list switch and its Cross confirmation still need the fix described in the report.)
local function asSingleScreen(fn)
    return function(panel, ...)
        local s = panel and panel.parent
        if s and s.Type == "CoopCharacterCreationProfession" and rawget(s, "Type") == nil then
            rawset(s, "Type", "CharacterCreationProfession")
            local ok, a, b, c = pcall(fn, panel, ...)
            rawset(s, "Type", nil)
            if not ok then error(a, 0) end
            return a, b, c
        end
        return fn(panel, ...)
    end
end
if F.readers.CharacterCreationProfessionListBox and F.readers.CharacterCreationProfessionListBox ~= MH.ccReader then
    MH.ccReader = asSingleScreen(F.readers.CharacterCreationProfessionListBox)
    F.readers.CharacterCreationProfessionListBox = MH.ccReader
end
local ccScreen = F.screens.CharacterCreationProfessionListBox
if ccScreen and ccScreen.intro and ccScreen.intro ~= MH.ccIntro then
    MH.ccIntro = asSingleScreen(ccScreen.intro)
    ccScreen.intro = MH.ccIntro
end

-- ======================================================================
-- wiring
-- ======================================================================

-- PageN and the two plain lists: their intro by exact type (MH.intros), before everything else.
if F.screenIntro ~= MH.introWrapper then
    local origIntro = F.screenIntro
    MH.introWrapper = function(panel)
        local fn = panel and MH.intros[panel.Type]
        if fn then
            local ok, t = pcall(fn, panel)
            if ok and t then return t end
            if not ok then print("[ZA] multihost intro error " .. tostring(panel.Type) .. ": " .. tostring(t)) end
        end
        return origIntro(panel)
    end
    F.screenIntro = MH.introWrapper
end

if not MH.ticking then
    MH.ticking = true
    ZA.onTick(function() MH.patchSettings() end)
    ZA.onTick(function() MH.hostTick() end)
    ZA.onTick(function() MH.listTick() end)
end
