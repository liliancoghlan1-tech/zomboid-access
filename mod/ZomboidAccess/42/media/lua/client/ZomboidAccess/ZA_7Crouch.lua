-- Zomboid Access: says when the character crouches (sneaks) and when they stand up again (Marc, 2026-10-19).
-- Only changes are spoken: nothing when the game loads, and nothing while dead or in a vehicle.

ZA.Crouch = ZA.Crouch or {}   -- (not ZA.CR: that one is the craft menu, ZA_4Craft.lua)
local CR = ZA.Crouch

function CR.tick()
    local p = getPlayer()
    if not p or p:isDead() or p:getVehicle() then CR.last = nil; return end
    local sneaking = p:isSneaking() == true
    if CR.last ~= nil and sneaking ~= CR.last then
        ZA.say(ZA.tr(sneaking and "Crouch_Down" or "Crouch_Up"))
    end
    CR.last = sneaking
end

if not CR.ticking then
    CR.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(CR.tick)
        if not ok and not CR.errSaid then CR.errSaid = true; print("[ZA] crouch error: " .. tostring(err)) end
    end)
end
