-- Zomboid Access: the Terms of Service panel shown once, before the main menu, on a player's first launch.
-- No controller is claimed yet at that point (Cross claims it) and the panel has no keyboard control at
-- all, so the focus poller has nothing to read and a keyboard player is stuck. This reads the panel as
-- soon as it appears and lets the keyboard move through its four buttons: Up and Down, Enter presses.

local F = ZA.F
local TS = ZA.Terms or {}
ZA.Terms = TS

F.screens.ISTermsOfServiceUI = { name = "Terms of Service and Privacy Notice" }

local function panel()
    local p = ISTermsOfServiceUI and ISTermsOfServiceUI.instance
    if p and p.isReallyVisible and p:isReallyVisible() then return p end
    return nil
end

local function buttons(p)
    return { p.button1, p.button2, p.buttonAccept, p.buttonQuit }
end

local function buttonWords(p, i)
    local b = buttons(p)[i]
    if not b then return "" end
    return ZA.clean(b.title or "") .. ", button, " .. i .. " of 4"
end

-- a controller whose focus is on the panel (after Cross), so the pad's own moves are read too
local function padOnPanel(p)
    for _, jd in pairs(JoypadState.joypads or {}) do
        if type(jd) == "table" and jd.focus == p then return jd end
    end
    for _, c in pairs(JoypadState.controllers or {}) do
        local jd = type(c) == "table" and c.joypad
        if type(jd) == "table" and jd.focus == p then return jd end
    end
    return nil
end

local keys = { up = false, down = false, enter = false }
local function pressed(name, code)
    local down = isKeyDown(code)
    local edge = down and not keys[name]
    keys[name] = down
    return edge
end

function TS.tick()
    local p = panel()
    if not p then
        TS.shown = nil
        return
    end
    if TS.shown ~= p then
        TS.shown, TS.index, TS.padFocus = p, 3, nil
        keys.up, keys.down, keys.enter = isKeyDown(Keyboard.KEY_UP), isKeyDown(Keyboard.KEY_DOWN), isKeyDown(Keyboard.KEY_RETURN)
        local text = getText("UI_TermsOfService_Prompt1")
        ZA.say(F.screens.ISTermsOfServiceUI.name .. ". " .. text)
        ZA.queue("Keyboard: Up and Down move between the buttons, Enter presses one. Controller: press {Cross} first, then the D-pad and {Cross}.")
        ZA.queue(buttonWords(p, TS.index))
        ZA.log("[ZA] terms of service panel read")
        return
    end

    -- controller: the game moves its own focus once Cross has claimed the pad; say each button it lands on
    if padOnPanel(p) then
        local ch = F.focusedChild(p)
        if ch and ch ~= TS.padFocus then
            TS.padFocus = ch
            for i, b in ipairs(buttons(p)) do
                if b == ch then TS.index = i; ZA.say(buttonWords(p, i)) end
            end
        end
    end

    -- keyboard
    if pressed("up", Keyboard.KEY_UP) then
        TS.index = TS.index <= 1 and 4 or TS.index - 1
        ZA.say(buttonWords(p, TS.index))
    elseif pressed("down", Keyboard.KEY_DOWN) then
        TS.index = TS.index >= 4 and 1 or TS.index + 1
        ZA.say(buttonWords(p, TS.index))
    elseif pressed("enter", Keyboard.KEY_RETURN) then
        local b = buttons(p)[TS.index]
        if b then
            ZA.log("[ZA] terms: pressing " .. tostring(b.title))
            if b == p.buttonAccept then ZA.say("Accepted") end
            if b == p.button1 or b == p.button2 then ZA.say("Opening the page in your web browser or the Steam overlay") end
            b:forceClick()
        end
    end
end

if not TS.ticking then
    TS.ticking = true
    ZA.onTick(TS.tick)
end
