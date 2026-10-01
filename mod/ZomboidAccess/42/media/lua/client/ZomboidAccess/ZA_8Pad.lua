-- Zomboid Access: the scanner on the controller.
--   Share, tapped         scanner layer on / off (holding Share still opens the game's own Share menu)
--   Share, tapped twice   quick status: health, injuries, the moodles that hurt (as Insert on the keyboard)
-- While the scanner layer is on (the left stick still walks, Cross still opens and picks up as normal):
--   D-pad up / down       previous / next thing
--   D-pad left / right    previous / next category
--   Triangle              say it again, with a fresh distance; hold it to start or stop guide mode
--   Square                walk there (again stops); hold it to USE it: open a container (walking there first),
--                         or the game's menu for anything else (ZA_6WalkUse.lua)
--   Circle                scanner layer off (it also does its normal job: stopping what you're doing)
-- The game itself reads Cross and Circle, so those two can't be borrowed; Square, Triangle, Share and the
-- D-pad go through the game's Lua, where this file answers them first.
-- Any controller works: Share is the same button as Back, Select or View on other pads.

ZA.P = ZA.P or {}
local P = ZA.P
local S, W, G = ZA.S, ZA.W, ZA.G

P.layer = false
P.holdMs = 450
P.down = {}      -- buttons we took on press: button -> { t = press time, held = done as a hold }

local function inWorld(c)
    local jd = c.joypad
    return jd and jd.player ~= nil and jd.focus == nil and S.inWorld() and not jd.isDoingNavigation
end

function P.setLayer(on)
    P.layer = on
    if on then
        ZA.say("Scanner on. D-pad up and down: things. Left and right: categories. Triangle: again, hold for guide. Square: walk there, hold to use it. Circle: scanner off.")
    else
        ZA.say("Scanner off.")
    end
end

local function run(f, ...)
    local ok, err = pcall(f, ...)
    if not ok then print("[ZA] pad error: " .. tostring(err)) end
end

-- ---------- wrap the controller ----------

if not P.wrapped then
    P.wrapped = true
    local C = JoypadControllerData
    local orig = {
        press = C.onPressButton, hold = C.onHoldButton, release = C.onReleaseButton,
        up = C.onPressUp, down = C.onPressDown, left = C.onPressLeft, right = C.onPressRight,
    }
    P.orig = orig

    function C:onPressButton(button)
        if inWorld(self) then
            if button == Joypad.Back then
                P.down[button] = { t = getTimestampMs() }
                return
            end
            if P.layer and (button == Joypad.XButton or button == Joypad.YButton) then
                P.down[button] = { t = getTimestampMs() }
                return
            end
            if P.layer and button == Joypad.BButton then
                P.setLayer(false)
            end
        end
        return orig.press(self, button)
    end

    function C:onHoldButton(button, time)
        local d = P.down[button]
        if d and not d.held and time >= P.holdMs then
            d.held = true
            if button == Joypad.Back then
                -- a long press: the game's own Share menu, as if we had never taken the button
                run(orig.press, self, button)
            elseif button == Joypad.YButton then
                run(G.toggle)
            elseif button == Joypad.XButton then
                run(W.use)
            end
            return
        end
        if d then return end
        return orig.hold(self, button, time)
    end

    function C:onReleaseButton(button)
        local d = P.down[button]
        if d then
            P.down[button] = nil
            -- a long Share press opened the game's Share menu, which chooses when Share is let go
            if d.held and button == Joypad.Back then return orig.release(self, button) end
            if not d.held then
                if button == Joypad.Back then
                    -- a second tap soon after the first = quick status; one tap = scanner on/off
                    local t = getTimestampMs()
                    if P.pendingTap and t - P.pendingTap < P.doubleTap then
                        P.pendingTap = nil
                        run(ZA.ST.summary)
                    else
                        P.pendingTap = t
                    end
                elseif button == Joypad.YButton then
                    run(S.repeatCurrent)
                elseif button == Joypad.XButton then
                    run(W.go)
                end
            end
            return
        end
        return orig.release(self, button)
    end

    -- The game repeats a held D-pad direction after 300 ms, so a firm tap often moved two steps (her report
    -- 2026-10-01). A press moves once; holding starts repeating only after P.repeatDelay.
    P.repeatDelay = 600
    local held = { onPressUp = "dtup", onPressDown = "dtdown", onPressLeft = "dtleft", onPressRight = "dtright" }
    local function dpad(name, action)
        C[name] = function(self)
            local dt = self[held[name]] or 0
            if dt > 0 and dt < P.repeatDelay then return end
            if P.layer and inWorld(self) then
                run(action)
                return
            end
            return orig[({ onPressUp = "up", onPressDown = "down", onPressLeft = "left", onPressRight = "right" })[name]](self)
        end
    end
    dpad("onPressUp", function() S.step(-1) end)
    dpad("onPressDown", function() S.step(1) end)
    dpad("onPressLeft", function() S.switchCategory(-1) end)
    dpad("onPressRight", function() S.switchCategory(1) end)
end

-- One Share tap waits a moment, in case a second tap follows.
P.doubleTap = 350
if not P.ticking then
    P.ticking = true
    ZA.onTick(function()
        if P.pendingTap and getTimestampMs() - P.pendingTap >= P.doubleTap then
            P.pendingTap = nil
            P.setLayer(not P.layer)
        end
    end)
end

-- A new world or a load starts with the layer off, so the D-pad does what the game expects.
Events.OnGameStart.Add(function() P.layer = false; P.down = {} end)
