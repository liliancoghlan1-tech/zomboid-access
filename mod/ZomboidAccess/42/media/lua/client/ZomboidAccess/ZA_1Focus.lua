-- Zomboid Access: speak what the controller's focus is on.
-- The game already moves a controller through every menu (ISPanelJoypad). Each frame this looks at
-- the focused panel and its focused child; when either changes it speaks, and when the focused
-- control's value changes (a tick box, a list, a slider) it speaks the new value.

ZA.F = ZA.F or {}
local F = ZA.F

-- The controller in use: the main menu's, or player 1's in game.
function ZA.joypad()
    local jd = JoypadState.getMainMenuJoypad and JoypadState.getMainMenuJoypad()
    if jd then return jd end
    local p = JoypadState.players and JoypadState.players[1]
    if p then return p end
    return nil
end

-- ---------- describing a control ----------

local function str(v)
    if v == nil then return "" end
    if type(v) == "table" then return tostring(v.text or v.name or v.title or "") end
    return tostring(v)
end

function F.comboText(c, i)
    i = i or c.selected
    if c.getOptionText then
        local ok, t = pcall(c.getOptionText, c, i)
        if ok and t then return str(t) end
    end
    return str(c.options and c.options[i])
end

-- A control's name. Screens can set ui.zaLabel; otherwise the text label on the same row, to its left.
function F.labelFor(ui)
    if ui.zaLabel then return ui.zaLabel end
    local p = ui.parent
    if not p or not p.getChildren then return "" end
    local best, bestX = nil, -1
    local uy, uh = ui:getY(), ui:getHeight()
    for _, ch in pairs(p:getChildren()) do
        if ch.Type == "ISLabel" and ch ~= ui and ch:isVisible() then
            local cy = ch:getY()
            if cy >= uy - 4 and cy <= uy + uh and ch:getX() < ui:getX() and ch:getX() > bestX then
                best, bestX = ch, ch:getX()
            end
        end
    end
    return best and (ZA.clean(best.name or ""):gsub("%s*:%s*$", "")) or ""
end

-- The words for a control, and its "value" (what changes while the focus stays put).
function F.describe(ui)
    if ui == nil then return "", "" end
    local words, value = F.describeBare(ui)
    -- a button carries its own name; the label beside it belongs to the control before it
    local label = ui.Type == "ISButton" and "" or F.labelFor(ui)
    if label ~= "" and words ~= "" then words = label .. ": " .. words
    elseif label ~= "" then words = label end
    -- The value alone: the name is said when you arrive on a control, not again each time its value changes
    -- ("Maryanne", not "Voice type: Maryanne").
    return words, value
end

function F.describeBare(ui)
    if ui == nil then return "", "" end
    local t = ui.Type or ""
    if t == "ISButton" then
        local title = ui.title or (ui.getTitle and ui:getTitle()) or ""
        if title == "" and ui.tooltip then title = ui.tooltip end
        return ZA.clean(title) .. ", button", ""
    elseif t == "ISLabel" then
        return ZA.clean(ui.name or ui:getName() or ""), ""
    elseif t == "ISTickBox" and #(ui.options or {}) > 1 then
        -- Several boxes in one control (Single Context Menu: Player 1 to 4): Up and Down move between the boxes
        -- first, and only past the last (or first) one to the next row, so say the box the cursor is on.
        local n, i = #ui.options, ui.joypadIndex or 1
        local v = str(ui.options[i]) .. (ui.selected[i] and ", checked" or ", not checked") .. ", " .. i .. " of " .. n
        return v .. ". Up and Down move between the " .. n .. " boxes, then on; {Cross} ticks or unticks", v
    elseif t == "ISTickBox" then
        local parts = {}
        for i, o in ipairs(ui.options or {}) do
            table.insert(parts, str(o) .. (ui.selected[i] and " checked" or " not checked"))
        end
        local v = table.concat(parts, ", ")
        return v, v
    elseif t == "ISComboBox" then
        if ui.expanded and ui.popup and ui.popup.selected then
            -- The list is open: what Up and Down are moving through.
            local i = ui.popup.selected
            local it = ui.popup.items and ui.popup.items[i]
            local v = it and ZA.clean(it.text or "") or ""
            return v .. ", " .. i .. " of " .. #(ui.popup.items or {}), v
        end
        local v = F.comboText(ui)
        return v .. ", " .. tostring(ui.selected) .. " of " .. tostring(#(ui.options or {})) .. ", drop-down list, {Cross} opens it", v
    elseif t == "ISScrollingListBox" then
        local it = ui.items and ui.items[ui.selected]
        local v = it and ZA.clean(it.text or "") or "empty"
        return v .. ", " .. tostring(ui.selected) .. " of " .. tostring(#(ui.items or {})), v
    elseif t == "ISVolumeControl" then
        local v = tostring(ui.getVolume and ui:getVolume() or ui.volume or "?")
        return "volume " .. v .. " of 10, Left and Right change it", "volume " .. v
    elseif t == "ISTextEntryBox" then
        local v = ui:getText() or ""
        return "edit box, " .. (v == "" and "empty" or v), v
    elseif ui.getCurrentValue then
        local v = "slider " .. tostring(ui:getCurrentValue())
        return v .. ", Left and Right change it", v
    end
    local txt = ui.title or ui.name or ""
    return ZA.clean(tostring(txt)) .. (t ~= "" and (" (" .. t .. ")") or ""), ""
end

-- ---------- screens ----------
-- PlayStation names for the face buttons the game maps per screen.
F.padNames = { A = "{Cross}", B = "{Circle}", X = "{Square}", Y = "{Triangle}" }

-- Names and a one-line purpose for whole screens, by their Lua type.
F.screens = {
    MainScreen = { name = "Main menu" },
    NewGameScreen = { name = "New game: choose a game mode", hint = "Left and Right choose a mode" },
    MapSpawnSelectListBox = { name = "Choose where you start", hint = "Up and Down choose a town" },
}

function F.screenName(panel)
    if panel == nil then return "" end
    local sc = F.screens[panel.Type]
    if sc then return sc.name end
    if panel.title and panel.title ~= "" then return ZA.clean(panel.title) end
    return panel.Type or ""
end

-- "Cross: Next. Circle: Back." from the buttons this screen maps to the pad.
function F.buttonHints(panel)
    if not panel then return "" end
    local parts = {}
    for _, k in ipairs({ "A", "B", "X", "Y" }) do
        local b = panel["ISButton" .. k] or (panel.parent and panel.parent["ISButton" .. k])
        if b and b.isVisible and b:isVisible() and b.enable ~= false then
            local t = ZA.clean(b.title or "")
            if t ~= "" then table.insert(parts, F.padNames[k] .. ": " .. t:sub(1, 1):upper() .. t:sub(2):lower()) end
        end
    end
    return table.concat(parts, ". ")
end

function F.screenIntro(panel)
    local sc = F.screens[panel.Type]
    if sc and sc.intro then
        local ok, t = pcall(sc.intro, panel)
        if ok and t then return t end
        if not ok then print("[ZA] intro error " .. tostring(panel.Type) .. ": " .. tostring(t)) end
    end
    local parts = { F.screenName(panel) }
    if sc and sc.hint then table.insert(parts, sc.hint) end
    local hints = F.buttonHints(panel)
    if hints ~= "" then table.insert(parts, hints) end
    for i, t in ipairs(parts) do parts[i] = t:gsub("[%.%s]+$", "") end
    return table.concat(parts, ". ")
end

-- ---------- readers ----------
-- A reader returns what is selected on a screen that tracks its own selection:
--   key (changes when the selection moves), words (said then), value (said alone when only it changes).
F.readers = {}

F.readers.NewGameScreen = function(p)
    local it = p.selectedItem
    if not it then return nil end
    local n = 0
    for _, pan in ipairs(p.panels or {}) do if pan.title then n = n + 1 end end
    local desc = it.richText and ZA.clean(it.richText.textRaw or "") or ""
    local words = ZA.clean(it.title or "") .. ", " .. tostring(p.selectedJoypad or "?") .. " of " .. n .. (desc ~= "" and (". " .. desc) or "")
    return it, words, ""
end

-- Any list that has the focus itself: the selected line, its place, and its description if it has one.
function F.listReader(p)
    if not (p.items and p.selected) then return nil end
    local it = p.items[p.selected]
    if not it then return p, "empty list", "" end
    local text = ZA.clean(it.text or "")
    local data = it.item
    local desc = ""
    if type(data) == "table" then desc = ZA.clean(data.desc or data.description or "") end
    if desc == "" and it.tooltip then desc = ZA.clean(it.tooltip) end
    return it, text .. ", " .. p.selected .. " of " .. #p.items .. (desc ~= "" and (". " .. desc) or ""), ""
end

-- ---------- watching ----------

local last = { panel = nil, key = nil, value = nil }

function F.focusedChild(panel)
    if panel and panel.getJoypadFocus then
        local ok, ch = pcall(panel.getJoypadFocus, panel)
        if ok then return ch end
    end
    return nil
end

-- What is selected now: from the screen's reader, else the focused child control.
function F.current(panel)
    local r = panel and (F.readers[panel.Type] or (panel.items and panel.selected and F.listReader))
    if r then
        local ok, key, words, value = pcall(r, panel)
        if ok and key ~= nil then return key, words or "", value or "" end
        if not ok then print("[ZA] reader error " .. tostring(panel.Type) .. ": " .. tostring(key)) end
    end
    local child = F.focusedChild(panel)
    if child and child ~= panel then
        local words, value = F.describe(child)
        return child, words, value
    end
    return nil, "", ""
end

function F.poll()
    local jd = ZA.joypad()
    local panel = jd and jd.focus
    local key, words, value = F.current(panel)

    if panel ~= last.panel then
        -- Coming straight back from a pop-up (a colour grid, a dialog) to the screen you were on:
        -- just say where you are, not the whole screen again.
        local back = panel ~= nil and panel == last.before
        last.before = last.panel
        last.panel, last.key, last.value = panel, key, value
        if panel then
            if back and words ~= "" then ZA.say(words)
            else
                ZA.say(F.screenIntro(panel))
                if words ~= "" then ZA.queue(words) end
            end
        end
        return
    end
    if key ~= last.key then
        -- A choice can move the selection and change a value at once (a trait added moves the list
        -- and spends points): say both.
        local changed = value ~= last.value and value ~= "" and not words:find(value, 1, true)
        last.key, last.value = key, value
        if words ~= "" then ZA.say(changed and (value .. ". " .. words) or words)
        elseif changed then ZA.say(value) end
        return
    end
    if value ~= last.value then
        last.value = value
        if value ~= "" then ZA.say(value) end
    end
end

ZA.onTick(F.poll)
