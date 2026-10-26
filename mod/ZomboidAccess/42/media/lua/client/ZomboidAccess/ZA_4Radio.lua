-- Zomboid Access: the device window of radios and televisions (Device options: ISRadioWindow), with a controller.
-- In game 2026-10-19 it said only "Rwmelement", and the game threw an error every frame while it was open
-- (ISPanelJoypad:getJoypadFocus on its sections). How the game moves through it with a controller:
--   the window itself: {R1} goes into its sections, {Cross} turns it on or off, {Triangle} mutes, {Circle} closes;
--   in the sections (RWMElement: Power, Volume, Channel...): Up and Down go from one to the next, Left and Right
--   fold and unfold one, and the buttons do what that section offers (Volume: {Cross} louder, {Circle} quieter,
--   {Triangle} mutes); {L1} leaves the window, {R1} goes back to the window itself.
-- Each section is said with its state (on or off, the volume, the channel) and what its buttons do, the game's own
-- words; then the state alone again whenever it changes.

local F = ZA.F

local padNames = { A = "{Cross}", B = "{Circle}", X = "{Square}", Y = "{Triangle}", LB = "{L1}", RB = "{R1}" }

-- "Cross: Turn off. Circle: Remove battery..." from the panel's own prompts
local function prompts(ui)
    local parts = {}
    for _, k in ipairs({ "A", "B", "X", "Y", "LB", "RB" }) do
        local fn = ui["get" .. k .. "Prompt"]
        if fn then
            local ok, t = pcall(fn, ui)
            if ok and type(t) == "string" and t ~= "" then table.insert(parts, padNames[k] .. " : " .. ZA.clean(t)) end
        end
    end
    return table.concat(parts, ". ")
end

local function onOff(dd)
    local on = false
    pcall(function() on = dd:getIsTurnedOn() end)
    return ZA.tr(on and "Radio_On" or "Radio_Off")
end

-- What a section is set to now, in a few words.
local function sectionState(el)
    local sub = el.subpanel
    if not sub then return "" end
    if not el.isExpanded then return ZA.tr("Radio_Folded") end
    local dd = sub.deviceData
    local t = sub.Type or ""
    if t == "RWMPower" or t == "RWMGridPower" then
        if not dd then return "" end
        local s = onOff(dd)
        local battery = false
        pcall(function() battery = dd:getIsBatteryPowered() end)
        if battery then
            local pw = nil
            pcall(function() pw = dd:getPower() end)
            if pw then s = s .. ", " .. ZA.tr("Radio_Battery", math.floor(pw * 100 + 0.5)) end
        end
        return s
    elseif t == "RWMVolume" then
        local bar = sub.volumeBar
        if not (dd and bar) then return "" end
        local vol = 1
        pcall(function() vol = dd:getDeviceVolume() end)
        if vol <= 0 then return ZA.tr("Radio_Muted") end
        return ZA.tr("Radio_Volume", bar:getVolume(), bar:getVolumeSteps())
    elseif sub.comboBox then
        -- a channel list: the one Up and Down are on while it's open, else the one chosen
        local c = sub.comboBox
        if sub.focusElement == c then
            local words = F.describeBare(c)
            return words
        end
        local name = F.comboText(c)
        return name ~= "" and ZA.tr("Radio_Channel", name) or ""
    end
    return ""
end

F.screens.RWMElement = F.screens.RWMElement or {}
F.screens.RWMElement.intro = function(el)
    local parts = { ZA.clean(el.titleText or "") }
    local st = sectionState(el)
    if st ~= "" then table.insert(parts, st) end
    local p = el.isExpanded and prompts(el) or ""
    if p ~= "" then table.insert(parts, p) end
    if not el.isExpanded then table.insert(parts, ZA.tr("Radio_UnfoldHint")) end
    for i, s in ipairs(parts) do parts[i] = s:gsub("[%.%s]+$", "") end
    return table.concat(parts, ". ")
end

-- The section itself is the "screen" (said whole as the focus arrives on it); only its state is watched after that.
F.readers.RWMElement = function(el)
    return el, "", sectionState(el)
end

-- The window itself (before {R1}): on or off and how to get into it, after its name.
F.readers.ISRadioWindow = function(w)
    local parts = {}
    if w.deviceData then table.insert(parts, onOff(w.deviceData)) end
    local p = prompts(w)
    if p ~= "" then table.insert(parts, p) end
    table.insert(parts, ZA.tr("Radio_WindowHint"))
    return w, table.concat(parts, ". "), w.deviceData and onOff(w.deviceData) or ""
end
