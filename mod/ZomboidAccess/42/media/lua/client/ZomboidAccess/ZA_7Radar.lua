-- Zomboid Access: hearing the fight.
--   Zombie pulse (za_zombie.wav, a low double thump) from each of the 3 nearest zombies that is chasing you
--     within 20 metres, or any zombie within 10 metres: from where it is, faster as it gets closer.
--   Lock tick (za_lock.wav, a wood block) while you're aiming at a zombie close enough to hit
--     (the same test as "In reach" in ZA_7Combat).
--   Switch both on or off: the scanner's "You" list, "Zombie sounds", then Square.
-- The sounds are played only for you (PlayWorldSoundImpl): zombies don't hear them.

ZA.R = ZA.R or {}
local R = ZA.R
local S = ZA.S

R.on = true
R.next = {}        -- zombie -> time of its next pulse
R.nextLock = 0
R.nextTick = 0

local function play(name, x, y, z)
    pcall(function()
        getSoundManager():PlayWorldSoundImpl(name, false, math.floor(x), math.floor(y), math.floor(z), 0, 40, 1, false)
    end)
end

function R.tick()
    if not R.on then return end
    local p = getPlayer()
    if not p or p:isDead() or not S.inWorld() then return end
    local t = getTimestampMs()
    if t < R.nextTick then return end
    R.nextTick = t + 50
    local px, py, pz = p:getX(), p:getY(), math.floor(p:getZ())

    -- the nearest zombies worth hearing
    local zl = getCell():getZombieList()
    local list = {}
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.floor(z:getZ()) == pz then
            local d = math.sqrt((z:getX() - px) ^ 2 + (z:getY() - py) ^ 2)
            local chasing = false
            pcall(function() chasing = z:getTarget() == p end)
            if d <= 10 or (chasing and d <= 20) then table.insert(list, { z = z, d = d }) end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    local keep = {}
    for i = 1, math.min(3, #list) do
        local e = list[i]
        keep[e.z] = true
        local due = R.next[e.z] or 0
        if t >= due then
            play("ZA_Zombie", e.z:getX(), e.z:getY(), e.z:getZ())
            -- 1.6 s far away, down to 0.3 s next to you; stagger a newly heard one a little
            R.next[e.z] = t + math.max(300, math.min(1600, e.d * 90)) + (due == 0 and i * 120 or 0)
        end
    end
    for z in pairs(R.next) do if not keep[z] then R.next[z] = nil end end

    -- aimed at one in reach
    if ZA.CB and ZA.CB.inReach and t >= R.nextLock then
        play("ZA_Lock", px, py, p:getZ())
        R.nextLock = t + 450
    end
end

if not R.ticking then
    R.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(R.tick)
        if not ok then print("[ZA] radar error: " .. tostring(err)) end
    end)
end

-- On and off from the "You" list.
table.insert(S.builders, function(lists)
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|radar", noWhere = true, order = 902, baseName = "Zombie sounds",
        name = function()
            return "Zombie sounds: " .. (R.on and "on" or "off") .. ". {Square} turns them " .. (R.on and "off" or "on")
        end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function()
            R.on = not R.on
            R.next = {}
            ZA.say("Zombie sounds " .. (R.on and "on" or "off") .. ".")
        end,
    })
end)
