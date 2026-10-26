-- Zomboid Access: the grab cue. While a zombie is grabbing you (in its attack on you: the game's
-- IsoZombie:isZombieAttacking), a button-mash alert plays
-- (za_grabbed.wav), alone: no words since 2026-10-19 (the sound says it).
-- Works with or without lock-on. The sound is played again while the grab lasts, and stops once no
-- zombie has attacked you for a moment (a zombie's attacks come one after another, with short gaps).

ZA.GR = ZA.GR or {}
local GR = ZA.GR

GR.len = 1000      -- ms: played again every second while the grab goes on (Marc, 2026-10-18: 3 s was too slow);
                   -- the sound is heard for about 1.7 s, so each one overlaps the fading end of the one before
GR.linger = 1200   -- ms without an attack before the grab counts as over
GR.reach = 2       -- metres

-- The zombie attacking you now, if any (same floor, close by).
local function attacker(p)
    local zl = getCell():getZombieList()
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.floor(z:getZ()) == math.floor(p:getZ()) then
            local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
            if dx * dx + dy * dy <= GR.reach * GR.reach then
                local ok, att = pcall(function() return z:isZombieAttacking(p) end)
                if ok and att then return z end
            end
        end
    end
    return nil
end

-- Every sound of this grab still playing: all stopped when it ends.
GR.audios = GR.audios or {}

local function stop()
    for _, a in ipairs(GR.audios) do pcall(function() a:stop() end) end
    GR.audios = {}
end

local function play(p)
    pcall(function()
        local a = getSoundManager():PlayWorldSoundImpl("ZA_Grabbed", false, math.floor(p:getX()), math.floor(p:getY()),
            math.floor(p:getZ()), 0, 40, 1, false)
        if a then
            table.insert(GR.audios, a)
            if #GR.audios > 3 then table.remove(GR.audios, 1) end   -- older ones have finished by now
        end
    end)
    GR.playedAt = getTimestampMs()
end

function GR.tick()
    local p = getPlayer()
    local now = getTimestampMs()
    if not p or p:isDead() or p:getVehicle() then
        if GR.on then GR.on = false; stop() end
        return
    end
    if attacker(p) then
        GR.lastSeen = now
        if not GR.on then
            GR.on = true
            play(p)     -- the sound alone: no words (Marc, 2026-10-19: the sound says it)
        elseif now - (GR.playedAt or 0) > GR.len then
            play(p)
        end
    elseif GR.on and now - (GR.lastSeen or 0) > GR.linger then
        GR.on = false
        stop()
    end
end

if not GR.ticking then
    GR.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(GR.tick)
        if not ok and not GR.errSaid then GR.errSaid = true; print("[ZA] grab cue error: " .. tostring(err)) end
    end)
end
