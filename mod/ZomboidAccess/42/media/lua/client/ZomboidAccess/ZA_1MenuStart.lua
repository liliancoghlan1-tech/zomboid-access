-- Zomboid Access: the main menu before a controller has claimed it.
-- The menus are read through the controller's focus, and the game gives the main menu that focus
-- only when Cross is pressed on an ACTIVE controller (Options, Controller: each pad has a tick box).
-- Until then nothing is said, which sounds like the mod is broken. So, once the main menu is up and
-- no controller has it, say what to do: press Cross, or switch the pad on, or connect one.

local MS = ZA.MenuStart or {}
ZA.MenuStart = MS

local function pads()
    local connected, active = {}, {}
    if not getControllerCount then return connected, active end
    for i = 0, getControllerCount() - 1 do
        if isControllerConnected(i) then
            table.insert(connected, i)
            local ok, on = pcall(function() return getCore():getOptionActiveController(getControllerGUID(i)) end)
            if ok and on then table.insert(active, i) end
        end
    end
    return connected, active
end

-- the same thing the game's own Options screen does when no connected pad is switched on
local function switchOn(i)
    local ok, err = pcall(function()
        getCore():setOptionActiveController(i, true)
        getCore():saveOptions()
    end)
    print("[ZA] menu start: switched on controller " .. i .. " (" .. tostring(getControllerName(i)) .. ") " .. (ok and "ok" or tostring(err)))
    return ok
end

local function menuWaiting()
    local m = MainScreen and MainScreen.instance
    if not (m and not m.inGame and m.isReallyVisible and m:isReallyVisible()) then return false end
    if ISTermsOfServiceUI and ISTermsOfServiceUI.instance and ISTermsOfServiceUI.instance:isReallyVisible() then return false end
    return JoypadState.getMainMenuJoypad() == nil
end

function MS.tick()
    if not menuWaiting() then
        MS.since = nil
        if JoypadState.getMainMenuJoypad() then MS.said = nil end
        return
    end
    local now = getTimestampMs()
    MS.since = MS.since or now
    if MS.said or now - MS.since < 1500 then return end
    MS.said = true

    local connected, active = pads()
    print("[ZA] menu start: " .. #connected .. " controller(s) connected, " .. #active .. " switched on")
    if #connected == 0 then
        ZA.say("Main menu. No controller found. Zomboid Access reads the menus through a controller: connect one, then press {Cross}.")
    else
        if #active == 0 then switchOn(connected[1]) end
        ZA.say("Main menu. Press {Cross} on your controller to start.")
    end
end

-- a pad plugged in while the main menu waits: say it, and that Cross starts
function MS.onConnect(id)
    if not menuWaiting() then return end
    MS.said = true
    local _, active = pads()
    if #active == 0 then switchOn(id) end
    ZA.say("Controller connected. Press {Cross} to start.")
end

if not MS.ticking then
    MS.ticking = true
    ZA.onTick(MS.tick)
    Events.OnGamepadConnect.Add(function(id) MS.onConnect(id) end)
end
