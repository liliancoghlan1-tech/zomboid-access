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
    if y then name = "started " .. da .. "/" .. mo .. "/" .. y .. " at " .. h .. ":" .. mi end
    table.insert(parts, mode ~= "" and (mode .. ", " .. name) or name)
    pcall(function()
        local pl = d.players
        if pl and pl[1] then
            local n = pl[1].name or pl[1].forename
            if n then table.insert(parts, n) end
        end
    end)
    if d.playerAlive == false then table.insert(parts, "your character is dead")
    elseif d.playerAlive == true then table.insert(parts, "your character is alive") end
    if d.lastPlayed then table.insert(parts, (ZA.clean(tostring(d.lastPlayed)):gsub(":%s*", " ", 1))) end
    return table.concat(parts, ", ")
end

local origList = F.readers.ISScrollingListBox
F.readers.ISScrollingListBox = function(p)
    if p.parent and p.parent.Type == "LoadGameScreen" then
        local it = p.items and p.items[p.selected]
        if not it then return p, "No saved games", "" end
        return it, saveWords(it) .. ", " .. p.selected .. " of " .. #p.items, ""
    end
    return origList(p)
end

local origName = F.screenName
function F.screenName(panel)
    if panel and panel.parent and panel.parent.Type == "LoadGameScreen" then
        return "Load a game: Up and Down choose a save"
    end
    -- an Options tab: its name, its place, and how to change tab
    if panel and MainOptions and MainOptions.instance and panel.parent == MainOptions.instance.tabs then
        local tabs = panel.parent
        local i = tabs:getActiveViewIndex()
        local v = tabs.viewList and tabs.viewList[i]
        if v then
            return "Options, " .. ZA.clean(v.name) .. " tab, " .. i .. " of " .. #tabs.viewList .. ". L1 and R1 change tab"
        end
    end
    return origName(panel)
end

-- ---------- mods ----------

F.screens.ModSelector = { name = "Mods", hint = "Hold R1 and press Up to reach the list of mods; Cross turns the selected one on or off. Hold R1 and press Down to come back to these buttons" }
F.readers.ModListBox = function(p)
    local it = p.items and p.items[p.selected]
    if not it then return p, "No mods", "" end
    local d = it.item or {}
    local name = it.text or "?"
    pcall(function() name = d.modInfo:getName() end)
    local on = d.isActive and "on" or "off"
    return it, ZA.clean(name) .. ", " .. on .. ", " .. p.selected .. " of " .. #p.items, on
end
F.screens.ModListBox = { name = "List of mods", hint = "Up and Down choose, Cross turns a mod on or off" }

-- ---------- the world map ----------

F.screens.ISWorldMap = { name = "World map. It's a picture: the scanner's Places and Where am I say the same things in words",
    hint = "Circle closes it" }

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
