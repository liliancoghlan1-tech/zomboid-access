-- Zomboid Access: the sandbox settings screen (Custom Sandbox, and the settings of any new game).
--   The controller starts on the list of pages (the game left it on the screen's two buttons, with the pages
--   reachable only by holding R1). Up and Down: pages. Right: into the page's settings; Left: back to the pages.
--   Each setting: its section when that changes, name, value, what Cross does, its place, and the game's own help.
--   Circle from the pages: the screen's buttons (Cross starts, Circle goes back); there Down reaches the presets
--   and the Advanced switch, Left or Up the pages again.

local F = ZA.F
if not SandboxOptionsScreen then return end

F.screens.SandboxOptionsScreen = {
    name = "Sandbox settings",
    hint = "Left or Up: the pages of settings. Down: presets and the Advanced switch",
}
F.screens.SandboxOptionsScreenListBox = {
    name = "Sandbox settings, pages",
    hint = "Up and Down choose a page, Right goes into its settings, {Circle} leaves the pages for the Start and Back buttons",
}
F.screens.SandboxOptionsScreenPanel = {
    name = "Settings",
    hint = "Up and Down move, {Cross} changes or opens a setting, Left goes back to the pages",
}
F.screens.SandboxOptionsScreenPresetPanel = {
    name = "Presets",
    hint = "Left and Right move between the preset list, Save, Delete and the Advanced switch. {Circle} goes back",
}

for _, k in ipairs({ "SandboxOptionsScreenListBox", "SandboxOptionsScreenPanel", "SandboxOptionsScreenPresetPanel" }) do
    local sc = F.screens[k]
    sc.intro = function() return sc.name .. ". " .. sc.hint end
end

-- ---------- pages ----------

F.readers.SandboxOptionsScreenListBox = function(p)
    local it = p.items and p.items[p.selected]
    if not it then return p, "No pages", "" end
    local d = it.item or {}
    local name = ZA.clean(it.text or "")
    if d.category then
        return it, name .. ", heading, " .. p.selected .. " of " .. #p.items, ""
    end
    local count = ""
    local panel = d.panel
    if panel and panel.settingNames then count = ", " .. #panel.settingNames .. " settings" end
    return it, name .. count .. ", " .. p.selected .. " of " .. #p.items, ""
end

-- ---------- settings ----------

local function rowChild(p)
    local row = p.joypadButtonsY and p.joypadButtonsY[p.joypadIndexY or 1]
    return row and row[p.joypadIndex or 1], p.joypadIndexY or 1, #(p.joypadButtonsY or {})
end

local function settingOf(p, child)
    for _, name in ipairs(p.settingNames or {}) do
        if p.controls[name] == child then return name end
    end
end

-- The section heading above a control (the titles are big labels between the rows).
local function sectionOf(p, child)
    local best, bestY = nil, -1
    local cy = child:getY()
    for _, t in ipairs(p.titles or {}) do
        local ty = t:getY()
        if ty <= cy and ty > bestY then best, bestY = t, ty end
    end
    return best and ZA.clean(best.name or "") or nil
end

local function valueOf(child)
    local c = child
    if child.Type == "SandboxAdvancedControl" then
        c = child.combo:isVisible() and child.combo or child.entry
    end
    local words, value = F.describeBare(c)
    if c.Type == "ISTickBox" then
        local on = c.selected[1] and "on" or "off"
        return on .. ", tick box, {Cross} switches it", on
    elseif c.Type == "ISTextEntryBox" then
        local v = c:getText() or ""
        return (v == "" and "empty" or v) .. ", edit box, {Cross} types a new value", v
    end
    return words, value
end

-- The game's own bug: the drop-down of a setting with an Advanced number (SandboxAdvancedControl) doesn't close
-- with Circle, and stays open on the screen when you move away. The panel's class is local to the game's file:
-- reach it through a panel's metatable, once.
local function openCombo(child)
    if not child then return nil end
    if child.isCombobox and child.expanded then return child end
    if child.Type == "SandboxAdvancedControl" and child.combo and child.combo.expanded then return child.combo end
    return nil
end
local function closeCombo(c)
    c.expanded = false
    c:hidePopup()
end

local function patchPanelClass(p)
    local cls = getmetatable(p)
    if not cls or cls.zaPatched then return end
    cls.zaPatched = true
    local origDown = cls.onJoypadDown
    function cls:onJoypadDown(button, joypadData)
        local c = openCombo(rowChild(self))
        if button == Joypad.BButton and c then closeCombo(c); return end
        return origDown(self, button, joypadData)
    end
end

local lastSection = {}
F.readers.SandboxOptionsScreenPanel = function(p)
    patchPanelClass(p)
    local child, i, n = rowChild(p)
    if not child then return p, "No settings on this page", "" end
    local name = settingOf(p, child)
    local label = name and p.labels[name]
    local title = label and ZA.clean(label.name or "") or F.labelFor(child)
    local words, value = valueOf(child)
    local s = title .. ": " .. words .. ", " .. i .. " of " .. n
    local sec = sectionOf(p, child)
    if sec and sec ~= lastSection[p] then s = sec .. ". " .. s end
    lastSection[p] = sec
    local tip = label and label.tooltip
    if tip and tip ~= "" then s = s .. ". " .. ZA.clean(tip) end
    -- an open drop-down: the list is what moves
    local combo = child.isCombobox and child or (child.combo and child.combo:isVisible() and child.combo)
    if combo and combo.expanded then
        local w, v = F.describeBare(combo)
        return combo.popup and combo.popup.selected or combo, w, v
    end
    return child, s, title .. ": " .. value
end

-- ---------- moving between the parts ----------

local function focus(jd, ui)
    if not ui then return end
    jd.focus = ui
    updateJoypadFocus(jd)
end

function SandboxOptionsScreen:onJoypadDirRight_Descendant(descendant, joypadData)
    if descendant == self.listbox and self.currentPanel then
        focus(joypadData, self.currentPanel)
        return
    end
    ISUIElement.onJoypadDirRight_Descendant(self, descendant, joypadData)
end

function SandboxOptionsScreen:onJoypadDirLeft_Descendant(descendant, joypadData)
    if descendant == self.currentPanel then
        local c = openCombo(rowChild(descendant))
        if c then closeCombo(c) end
        focus(joypadData, self.listbox)
        return
    end
    ISUIElement.onJoypadDirLeft_Descendant(self, descendant, joypadData)
end

-- on the screen itself (its Start and Back buttons): Left or Up = pages, Down = presets
function SandboxOptionsScreen:onJoypadDirLeft(joypadData) focus(joypadData, self.listbox) end
function SandboxOptionsScreen:onJoypadDirUp(joypadData) focus(joypadData, self.listbox) end
function SandboxOptionsScreen:onJoypadDirDown(joypadData) focus(joypadData, self.presetPanel) end

-- Opening the screen puts the controller on the pages (each time it's opened, not each time you come back to it).
if not ZA.sandboxWrapped then
    ZA.sandboxWrapped = true
    local origVisible = SandboxOptionsScreen.setVisible
    function SandboxOptionsScreen:setVisible(visible, joypadData)
        if visible then self.zaFresh = true end   -- before: showing it with a controller gives it the focus at once
        origVisible(self, visible, joypadData)
    end
    local origGain = SandboxOptionsScreen.onGainJoypadFocus
    function SandboxOptionsScreen:onGainJoypadFocus(joypadData)
        origGain(self, joypadData)
        if self.zaFresh and joypadData.focus == self and self.listbox then
            self.zaFresh = false
            -- the first page that holds settings, so Right has somewhere to go
            local lb = self.listbox
            if lb.items[lb.selected] and lb.items[lb.selected].item.category then
                for i, it in ipairs(lb.items) do
                    if it.item.page then lb.selected = i; lb:invokeOnMouseDownFunction(); break end
                end
            end
            focus(joypadData, lb)
        end
    end
end
