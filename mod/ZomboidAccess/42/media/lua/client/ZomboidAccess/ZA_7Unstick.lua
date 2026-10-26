-- Zomboid Access: a safety net for a swing that never ends.
-- In game 2026-10-19 the character got stuck in the game's swing state (SwipeStatePlayer) after a stomp at a zombie
-- on the ground: attack started, stomp at the ground, for good; no moving, no swinging, nothing. A swing or a
-- stomp lasts well under 2 seconds, so after 4 seconds in that state with the attack still started, it's cleared
-- (IsoPlayer:clearHandToHandAttack, then the default state), as was done by hand that day, and logged.

ZA.UN = ZA.UN or {}
local UN = ZA.UN

UN.limit = 4000   -- ms

local function inSwing(p)
    local s = ""
    pcall(function() s = tostring(p:getCurrentState()) end)
    return s:find("SwipeStatePlayer", 1, true) ~= nil
end

function UN.tick()
    local p = getPlayer()
    if not p or p:isDead() then UN.since = nil; return end
    -- the game paused (in game 2026-10-19: the pause menu opened mid swing, cleared 4 s later for nothing)
    if isGamePaused() then UN.since = nil; return end
    local started = false
    pcall(function() started = p:isAttackStarted() end)
    if not (started and inSwing(p)) then UN.since = nil; return end
    local now = getTimestampMs()
    UN.since = UN.since or now
    if now - UN.since < UN.limit then return end
    UN.since = nil
    print("[ZA] unstick: swing state stuck for 4 s, cleared")
    pcall(function() p:setForceAim(false) end)
    pcall(function() p:clearHandToHandAttack() end)
    pcall(function() p:setDoShove(false) end)
    pcall(function() p:setAimAtFloor(false) end)
    pcall(function() p:setDefaultState() end)
end

if not UN.ticking then
    UN.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(UN.tick)
        if not ok and not UN.errSaid then UN.errSaid = true; print("[ZA] unstick error: " .. tostring(err)) end
    end)
end
