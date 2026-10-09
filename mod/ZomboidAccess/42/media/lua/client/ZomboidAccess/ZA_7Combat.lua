-- Zomboid Access: combat basics.
--   Each swing or shove: "Hit", "Hit, down" (knocked over), "Killed", or "Miss"
--   While aiming (right stick pushed): "In reach" when a zombie is in front of you and close enough to hit
--   The first time something chases you in a session, the controls are said once
-- Aiming and timing stay yours: nothing here aims or swings for you.

ZA.CB = ZA.CB or {}
local CB = ZA.CB
local S = ZA.S

CB.swing = nil          -- the swing in progress: { hit = zombie or nil, t = start }
CB.lastHitZombie, CB.lastHitAt = nil, 0
CB.inReach = nil
CB.hintGiven = false
CB.closing = {}         -- zombie -> { d = distance, t = time, v = closing speed } from the last frame
CB.lead = 0.6           -- seconds: about the time from pulling R2 to the swing landing
CB.lookMax = 1.5        -- metres: never say "In reach" more than this beyond the weapon's range

-- "Killed" once per zombie, whichever of the two ways notices first.
CB.saidKilled = {}
function CB.killed(z)
    if CB.saidKilled[z] then return end
    CB.saidKilled[z] = true
    ZA.say("Killed")
end

local function me(c) return c ~= nil and c == getPlayer() end

-- A hit lands (this fires for each thing a swing hits).
local function onHit(owner, weapon, target, damage)
    if not me(owner) or not instanceof(target, "IsoZombie") then return end
    CB.swing = CB.swing or { t = getTimestampMs() }
    CB.swing.hit = target
    CB.saidKilled[target] = nil   -- the game reuses zombie objects
    CB.lastHitZombie, CB.lastHitAt = target, getTimestampMs()
end

-- The swing (or shove) is over: say what happened.
local function onAttackFinished(player, weapon)
    if not me(player) then return end
    local s = CB.swing
    CB.swing = nil
    if not s or not s.hit then
        ZA.say("Miss")
        return
    end
    local z = s.hit
    -- the zombie falls a moment after the hit lands
    CB.pending = { z = z, at = getTimestampMs() + 350 }
end

local function onZombieDead(z)
    if z == CB.lastHitZombie and getTimestampMs() - CB.lastHitAt < 4000 then
        CB.pending = nil
        CB.lastHitZombie = nil
        CB.killed(z)
    end
end

function CB.tick()
    local p = getPlayer()
    if not p or p:isDead() then return end
    local t = getTimestampMs()
    if CB.pending and t >= CB.pending.at then
        local z = CB.pending.z
        CB.pending = nil
        if z:isDead() then CB.lastHitZombie = nil; CB.killed(z)
        else
            local down = false
            pcall(function() down = z:isOnFloor() or z:isKnockedDown() end)
            ZA.say(down and "Hit, down" or "Hit")
        end
    end

    -- "In reach": a zombie in front of you will be within the weapon's range by the time a swing lands.
    -- (A player's report, 0.9.1: "by the time it says I can hit, it has hit me". It used to wait until the
    -- zombie was already in range, and only while R2 was half pulled.) Now it looks ahead by how fast the
    -- zombie is closing in, and works whether you aim first or pull R2 straight through.
    if p:getVehicle() then CB.inReach = nil; return end
    local range = 1.2
    pcall(function()
        local w = p:getPrimaryHandItem()
        if w and instanceof(w, "HandWeapon") then range = w:getMaxRange() end
    end)
    local fx, fy = 0, 0
    pcall(function() local v = p:getForwardDirection(); fx, fy = v:getX(), v:getY() end)
    local fl = math.sqrt(fx * fx + fy * fy)
    if fl < 0.01 then return end
    fx, fy = fx / fl, fy / fl
    local zl = getCell():getZombieList()
    local found
    local seen = {}
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.floor(z:getZ()) == math.floor(p:getZ()) then
            local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= range + CB.lookMax + 0.4 and d > 0.01 then
                -- how fast it's closing in, in metres a second, smoothed over the last few frames
                local prev = CB.closing[z]
                local v = 0
                if prev and t > prev.t then
                    v = prev.v * 0.6 + ((prev.d - d) * 1000 / (t - prev.t)) * 0.4
                end
                seen[z] = { d = d, t = t, v = v }
                local ahead = math.min(CB.lookMax, math.max(0, v) * CB.lead)
                local dot = (dx * fx + dy * fy) / d
                -- within about 35 degrees of where you face (wider when it's right on top of you)
                if d <= range + 0.4 + ahead and (dot >= 0.82 or (d < 1 and dot >= 0.5)) then
                    if not found or d < found.d then found = { z = z, d = d } end
                end
            end
        end
    end
    CB.closing = seen
    found = found and found.z
    if found and found ~= CB.inReach then
        CB.inReach = found
        ZA.urgent("In reach")
    elseif not found then
        CB.inReach = nil
    end
end

-- Say the controls once, the first time something chases you.
function CB.firstChase()
    if CB.hintGiven then return "" end
    CB.hintGiven = true
    return " To fight: push the right stick at it to aim, or pull {R2} halfway with Lock-on on, {R2} all the way swings, {L2} shoves it away. A way out beeps with two rising whistles."
end

if not CB.hooked then
    CB.hooked = true
    if Events.OnWeaponHitXp then Events.OnWeaponHitXp.Add(function(...) pcall(onHit, ...) end) end
    if Events.OnPlayerAttackFinished then Events.OnPlayerAttackFinished.Add(function(...) pcall(onAttackFinished, ...) end) end
    if Events.OnZombieDead then Events.OnZombieDead.Add(function(...) pcall(onZombieDead, ...) end) end
    ZA.onTick(function()
        local ok, err = pcall(CB.tick)
        if not ok then print("[ZA] combat error: " .. tostring(err)) end
    end)
end
