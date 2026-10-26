-- Zomboid Access: the remaining full screens (loaded after ZA_4World, so these wrap its versions).
--   Load: each save with its mode, character, last played, alive or dead (not its folder name).
--   The world map: named, and how to close it (it is a picture; the scanner's Places and Where am I do its job).

local F = ZA.F

-- ---------- load ----------

local function saveWords(it)
    local d = it.item or {}
    local parts = {}
    local mode = d.gameMode and (getTextOrNull("IGUI_Gametime_" .. d.gameMode) or d.gameMode) or ""
    -- the folder is "Mode\date_time": say the date as words
    local folder = tostring(it.text or "")
    local y, mo, da, h, mi = folder:match("(%d%d%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)")
    local name = d.saveName or folder
    if y then name = ZA.tr("ZScreens_Started", da, mo, y, h, mi) end
    table.insert(parts, mode ~= "" and (mode .. ", " .. name) or name)
    pcall(function()
        local pl = d.players
        if pl and pl[1] then
            local n = pl[1].name or pl[1].forename
            if n then table.insert(parts, n) end
        end
    end)
    if d.playerAlive == false then table.insert(parts, ZA.tr("ZScreens_Dead"))
    elseif d.playerAlive == true then table.insert(parts, ZA.tr("ZScreens_Alive")) end
    if d.lastPlayed then table.insert(parts, (ZA.clean(tostring(d.lastPlayed)):gsub(":%s*", " ", 1))) end
    return table.concat(parts, ", ")
end

local origList = F.readers.ISScrollingListBox
F.readers.ISScrollingListBox = function(p)
    if p.parent and p.parent.Type == "LoadGameScreen" then
        local it = p.items and p.items[p.selected]
        if not it then return p, ZA.tr("ZScreens_NoSaves"), "" end
        return it, saveWords(it) .. ZA.pos(p.selected, #p.items), ""
    end
    return origList(p)
end

local origName = F.screenName
function F.screenName(panel)
    if panel and panel.parent and panel.parent.Type == "LoadGameScreen" then
        return ZA.tr("ZScreens_LoadScreen")
    end
    -- an Options tab: its name, its place, and how to change tab
    if panel and MainOptions and MainOptions.instance and panel.parent == MainOptions.instance.tabs then
        local tabs = panel.parent
        local i = tabs:getActiveViewIndex()
        local v = tabs.viewList and tabs.viewList[i]
        if v then
            return ZA.tr("ZScreens_OptionsTab", ZA.clean(v.name), ZA.pos(i, #tabs.viewList))
        end
    end
    return origName(panel)
end

-- ---------- mods ----------

F.screens.ModSelector = { name = ZA.tr("ZScreens_Mods"), hint = ZA.tr("ZScreens_ModsHint") }
F.readers.ModListBox = function(p)
    local it = p.items and p.items[p.selected]
    if not it then return p, ZA.tr("ZScreens_NoMods"), "" end
    local d = it.item or {}
    local name = it.text or "?"
    pcall(function() name = d.modInfo:getName() end)
    local on = d.isActive and ZA.tr("ZScreens_On") or ZA.tr("ZScreens_Off")
    return it, ZA.tr("ZScreens_ModLine", ZA.clean(name), on) .. ZA.pos(p.selected, #p.items), on
end
F.screens.ModListBox = { name = ZA.tr("ZScreens_ModList"), hint = ZA.tr("ZScreens_ModListHint") }

-- ---------- the world map ----------

F.screens.ISWorldMap = { name = ZA.tr("ZScreens_WorldMap"), hint = ZA.tr("ZScreens_WorldMapHint") }

-- ---------- dialogs ----------
-- Yes/No boxes and message boxes say what they're asking before their buttons
-- (ISModalDialog keeps it in .text; the rich-text ones in a child panel's .text).
local function dialogText(panel)
    if type(panel.text) == "string" and panel.text ~= "" then return ZA.clean(panel.text) end
    for _, k in ipairs({ "chatText", "richText", "textPanel" }) do
        local c = panel[k]
        if c and type(c.text) == "string" and c.text ~= "" then return ZA.clean(c.text) end
    end
    return nil
end

local origIntro = F.screenIntro
function F.screenIntro(panel)
    local t = origIntro(panel)
    -- dialogs, and any screen we have no name for that carries its own text
    if panel and panel.Type and (panel.Type:find("Dialog") or panel.Type:find("Modal") or not F.screens[panel.Type]) then
        local q = dialogText(panel)
        if q then
            t = t:gsub("^IS%a+%.%s*", "")   -- drop a raw type name
            return q:gsub("[%.%s]+$", "") .. ". " .. t
        end
    end
    return t
end

-- ---------- the on-screen keyboard ----------
-- Opens when Cross is pressed on a text or number box with a controller (sandbox numbers, names, markers).
-- Each key by name; after each key, what's typed so far.

local keyWords = {
    ["`"] = ZA.tr("ZScreens_KeyBacktick"), ["-"] = ZA.tr("ZScreens_KeyMinus"), ["="] = ZA.tr("ZScreens_KeyEquals"),
    ["["] = ZA.tr("ZScreens_KeyLBracket"), ["]"] = ZA.tr("ZScreens_KeyRBracket"),
    ["\\"] = ZA.tr("ZScreens_KeyBackslash"), [";"] = ZA.tr("ZScreens_KeySemicolon"),
    ["'"] = ZA.tr("ZScreens_KeyApostrophe"), [","] = ZA.tr("ZScreens_KeyComma"), ["."] = ZA.tr("ZScreens_KeyFullStop"),
    ["/"] = ZA.tr("ZScreens_KeySlash"), [" "] = ZA.tr("ZScreens_KeySpace"),
}

local function oskText(osk)
    local t = osk and osk.entry and osk.entry:getText() or ""
    if osk and osk.entry and osk.entry:isMasked() then
        return ZA.tr(#t == 1 and "ZScreens_CharsOne" or "ZScreens_CharsMany", #t)
    end
    return t == "" and ZA.tr("ZScreens_Nothing") or t
end

F.screens.OnScreenKeyboardPanel = {
    name = ZA.tr("ZScreens_OskName"),
    intro = function(p)
        return ZA.tr("ZScreens_OskIntro", oskText(p.parent))
    end,
}
F.screens.OnScreenKeyboardEntry = {
    name = ZA.tr("ZScreens_OskEntryName"),
    intro = function(p) return ZA.tr("ZScreens_OskEntryIntro", oskText(p.parent)) end,
}

F.readers.OnScreenKeyboardPanel = function(p)
    local b = F.focusedChild(p)
    if not b then return nil end
    local osk = p.parent
    local word
    if b.chLower then
        local upper = osk and (osk.capsLock or osk.shiftDown)
        local ch = upper and b.chUpper or b.chLower
        word = keyWords[ch] or (ch:match("%a") and (upper and ZA.tr("ZScreens_Capital", ch) or ch)) or ch
    else
        word = ZA.clean(b.title or "")
    end
    return b, word, ZA.tr("ZScreens_Typed", oskText(osk))
end
