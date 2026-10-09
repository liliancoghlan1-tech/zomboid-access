-- Zomboid Access: lock-on (optional, off at first; the scanner's "You" list, "Lock-on", then Square).
--   While it's on, your character turns to face the zombie it's locked on to: the nearest one within 3.5 metres
--   (one that's chasing you first), kept until it dies or gets more than 5 metres away. "Locked on: zombie, 2 metres
--   right" when it picks one, "Lock-on free" when there's none left.
--   It never turns you while you walk (left stick), and pushing the right stick to aim somewhere else wins over it.
--   While it faces a zombie (standing still) it also keeps you aiming at it, so pulling R2 all the way swings at
--   once. That is what makes it work with controllers whose triggers are only on or off (8BitDo and others): the
--   game swings only while you aim, and such a trigger can't be pulled halfway to aim first. L2 shoves.
-- The choice is kept in the save (ModData "ZomboidAccessSettings").

ZA.LK = ZA.LK or {}
local LK = ZA.LK
local S = ZA.S

LK.reach = 3.5
LK.keep = 5

local function settings()
    local ok, t = pcall(function() return ModData.getOrCreate("ZomboidAccessSettings") end)
    return ok and t or {}
end
function LK.isOn() return settings().lockOn == true end

local function dist(p, z) return math.sqrt((z:getX() - p:getX()) ^ 2 + (z:getY() - p:getY()) ^ 2) end

local function usable(p, z)
    return z and not z:isDead() and z:getCurrentSquare() ~= nil and math.floor(z:getZ()) == math.floor(p:getZ())
end

local function pick(p)
    local zl = getCell():getZombieList()
    local best, bd, bchase
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if usable(p, z) then
            local d = dist(p, z)
            if d <= LK.reach then
                local chase = z:getTarget() == p
                -- a zombie coming for you beats a nearer one that isn't
                if not best or (chase and not bchase) or (chase == bchase and d < bd) then
                    best, bd, bchase = z, d, chase
                end
            end
        end
    end
    return best
end

-- The player steering the aim with the right stick, away from the target: leave it to them.
local tmp = Vector2.new(0, 0)
local function manualAim(p, z)
    local ok, v = pcall(function() return p:getAimVector(tmp) end)
    if not ok or not v then return false end
    local ax, ay = v:getX(), v:getY()
    if ax * ax + ay * ay < 0.25 then return false end
    local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
    local dl = math.sqrt(dx * dx + dy * dy)
    if dl < 0.01 then return false end
    local al = math.sqrt(ax * ax + ay * ay)
    return (ax * dx + ay * dy) / (al * dl) < 0.77    -- more than about 40 degrees away
end

-- Aiming held for you while lock-on faces a zombie; let go the moment it doesn't (only what we set ourselves).
local function hold(p, on)
    if on == (LK.aiming == true) then return end
    local ok, err = pcall(function() p:setForceAim(on) end)
    if ok then LK.aiming = on
    elseif not LK.aimErrSaid then LK.aimErrSaid = true; print("[ZA] lock-on aim: " .. tostring(err)) end
end

function LK.tick()
    local p = getPlayer()
    if not LK.isOn() then
        LK.target = nil
        if p then hold(p, false) end
        return
    end
    if not p or p:isDead() or p:getVehicle() then
        LK.target = nil
        if p and not p:isDead() then hold(p, false) end
        return
    end
    local t = LK.target
    if t and (not usable(p, t) or dist(p, t) > LK.keep) then
        t = nil
    end
    if not t then t = pick(p) end
    if t ~= LK.target then
        if t then
            ZA.urgent("Locked on: " .. S.threatText(t))
        elseif LK.target then
            ZA.say("Lock-on free")
        end
        LK.target = t
    end
    if not t then hold(p, false); return end
    local moving = false
    pcall(function() moving = p:isPlayerMoving() end)
    if moving or p:isPerformingAnAction() or manualAim(p, t) then hold(p, false); return end
    p:faceThisObject(t)
    hold(p, true)
end
if not LK.ticking then
    LK.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(LK.tick)
        if not ok and not LK.errSaid then LK.errSaid = true; print("[ZA] lock-on error: " .. tostring(err)) end
    end)
end

-- On and off from the "You" list, next to Zombie sounds.
table.insert(S.builders, function(lists)
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|lockon", noWhere = true, order = 903, baseName = "Lock-on",
        name = function()
            local on = LK.isOn()
            return "Lock-on: " .. (on and "on" or "off") .. ". Faces and aims at the nearest zombie within reach while you "
                .. "stand still: {R2} swings. {Square} turns it " .. (on and "off" or "on")
        end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function()
            local s = settings()
            s.lockOn = not (s.lockOn == true)
            LK.target = nil
            ZA.say("Lock-on " .. (s.lockOn and "on" or "off") .. ".")
        end,
    })
end)
