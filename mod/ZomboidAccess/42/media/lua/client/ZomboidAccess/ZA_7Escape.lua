-- Zomboid Access: escape help (Lilian's idea, 2026-10-02).
-- While a zombie is chasing you, a ways-out beacon (za_escape.wav, two rising whistles, nothing like the zombie
-- thump or the guide bell) plays from the best way to break the chase within 12 metres:
--   a door (go through and close it behind you), a window or empty frame (climb through), a tall or low fence
--   (climb or hop over), a vehicle (get in).
-- "Best": near you, and not towards the zombies: a way out that a chasing zombie is nearer to than you, or that
-- lies in the direction of a zombie closer than it, is left out. Faster beeps as you get closer.
-- The scanner's "Ways out" category (next to Zombies) lists them all, best first; Square walks there, round the
-- zombies (ZA_6WalkSafe). On or off: the "You" list, "Escape help" (on at first; kept in the save).

ZA.ES = ZA.ES or {}
local ES = ZA.ES
local S = ZA.S

ES.range = 12
ES.chaseRange = 25

local function settings()
    local ok, t = pcall(function() return ModData.getOrCreate("ZomboidAccessSettings") end)
    return ok and t or {}
end
function ES.isOn() return settings().escapeOff ~= true end

local function props(o)
    local ok, pr = pcall(function() return o:getProperties() end)
    return ok and pr or nil
end

-- ---------- finding ways out ----------

local kinds = {
    door = { name = "Door", how = "go through, then {Cross} closes it behind you", bonus = -2, walk = "door" },
    window = { name = "Window", how = "{Circle} climbs through", bonus = -1, walk = "door" },
    frame = { name = "Empty window frame", how = "{Circle} climbs through", bonus = -1, walk = "door" },
    tallfence = { name = "Tall fence", how = "{Circle} climbs over", bonus = -1, walk = "adjacent" },
    fence = { name = "Low fence", how = "{Circle} hops over; zombies trip on it", bonus = 0, walk = "adjacent" },
    vehicle = { name = "Vehicle", how = "get in", bonus = 2, walk = "vehicle" },
}

local function classify(o)
    if instanceof(o, "IsoDoor") or (instanceof(o, "IsoThumpable") and o:isDoor()) then
        local locked = false
        pcall(function() locked = o:isLocked() and not o:IsOpen() end)
        if locked then return nil end
        return "door"
    end
    if instanceof(o, "IsoWindow") then
        local barred = false
        pcall(function() barred = o:isBarricaded() end)
        if barred then return nil end
        return "window"
    end
    if instanceof(o, "IsoWindowFrame") then
        -- a frame holding a window is the window, listed already
        local sq = o:getSquare()
        local objs = sq and sq:getObjects()
        if objs then
            for i = 0, objs:size() - 1 do if instanceof(objs:get(i), "IsoWindow") then return nil end end
        end
        return "frame"
    end
    local pr = props(o)
    if pr and (pr:has(IsoFlagType.TallHoppableN) or pr:has(IsoFlagType.TallHoppableW)) then return "tallfence" end
    local ok, hop = pcall(function() return o:isHoppable() end)
    if ok and hop then return "fence" end
    return nil
end

-- Every way out within range on your floor, scored (lower is better); nil score = left out.
function ES.find(p)
    local px, py, pz = p:getX(), p:getY(), math.floor(p:getZ())
    local zs = {}
    local zl = getCell():getZombieList()
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.floor(z:getZ()) == pz then
            local d = math.sqrt((z:getX() - px) ^ 2 + (z:getY() - py) ^ 2)
            if d <= ES.chaseRange then
                local chasing = false
                pcall(function() chasing = z:getTarget() == p end)
                table.insert(zs, { z = z, d = d, chasing = chasing })
            end
        end
    end
    local out, seen = {}, {}
    local cell = getCell()
    local r = ES.range
    for x = math.floor(px) - r, math.floor(px) + r do
        for y = math.floor(py) - r, math.floor(py) + r do
            local sq = cell:getGridSquare(x, y, pz)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local k = classify(o)
                    if k then
                        -- one per kind per few squares (a fence is many pieces)
                        local cluster = k .. ":" .. math.floor(x / 3) .. "," .. math.floor(y / 3)
                        if not seen[cluster] then
                            seen[cluster] = true
                            table.insert(out, { kind = k, obj = o, x = x + 0.5, y = y + 0.5, z = pz })
                        end
                    end
                end
                local ok, v = pcall(function() return sq:getVehicleContainer() end)
                if ok and v and not seen["v" .. tostring(v)] then
                    seen["v" .. tostring(v)] = true
                    table.insert(out, { kind = "vehicle", obj = v, x = v:getX(), y = v:getY(), z = pz })
                end
            end
        end
    end
    -- score: distance + what kind it is; leave out ways out the zombies are closer to, or that lie towards them
    local keep = {}
    for _, c in ipairs(out) do
        local dx, dy = c.x - px, c.y - py
        local dc = math.sqrt(dx * dx + dy * dy)
        local bad = false
        for _, z in ipairs(zs) do
            local zd = math.sqrt((z.z:getX() - c.x) ^ 2 + (z.z:getY() - c.y) ^ 2)
            if z.chasing and zd < dc then bad = true; break end
            if z.d < dc and dc > 0.5 then
                local ax, ay = z.z:getX() - px, z.z:getY() - py
                local cos = (ax * dx + ay * dy) / (math.max(0.01, z.d) * dc)
                if cos > 0.7 then bad = true; break end      -- within about 45 degrees of a nearer zombie
            end
        end
        if not bad then
            c.d = dc
            c.score = dc + kinds[c.kind].bonus
            table.insert(keep, c)
        end
    end
    table.sort(keep, function(a, b) return a.score < b.score end)
    return keep, zs
end

function ES.words(c)
    local k = kinds[c.kind]
    local n = k.name
    if c.kind == "door" or c.kind == "window" then
        local m = S.moveableName and S.moveableName(c.obj)
        if m and m ~= "" then n = m end
        local open = false
        pcall(function() open = c.obj:IsOpen() end)
        if c.kind == "window" then
            local broken = false
            pcall(function() broken = c.obj:isSmashed() end)
            if broken then n = n .. ", broken" elseif open then n = n .. ", open" else n = n .. ", closed" end
        else
            n = n .. (open and ", open" or ", closed")
        end
    end
    return n .. ": " .. k.how
end

-- ---------- the beacon ----------

local function chased(zs)
    for _, z in ipairs(zs) do if z.chasing then return true end end
    return false
end

ES.nextFind, ES.nextBeep = 0, 0
function ES.tick()
    if not ES.isOn() then ES.best = nil; return end
    local p = getPlayer()
    if not p or p:isDead() or p:getVehicle() or not S.inWorld() then ES.best = nil; return end
    local t = getTimestampMs()
    if t >= ES.nextFind then
        ES.nextFind = t + 1000
        local list, zs = ES.find(p)
        local was = ES.best
        ES.best = chased(zs) and list[1] or nil
        -- say where the way out is when a chase starts, or when the old one is no good any more
        if ES.best and (not was or (was.obj ~= ES.best.obj and not ES.stillGood(was, list))) then
            ZA.queue("Way out: " .. ES.words(ES.best) .. ", " .. S.where(ES.best.x, ES.best.y, ES.best.z))
        end
    end
    local b = ES.best
    if b and t >= ES.nextBeep then
        local d = math.sqrt((b.x - p:getX()) ^ 2 + (b.y - p:getY()) ^ 2)
        pcall(function()
            getSoundManager():PlayWorldSoundImpl("ZA_Escape", false, math.floor(b.x), math.floor(b.y), b.z, 0, 40, 1, false)
        end)
        ES.nextBeep = t + math.max(450, math.min(1400, d * 110))
    end
end

function ES.stillGood(c, list)
    for _, o in ipairs(list) do if o.obj == c.obj then return true end end
    return false
end

if not ES.ticking then
    ES.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(ES.tick)
        if not ok and not ES.errSaid then ES.errSaid = true; print("[ZA] escape error: " .. tostring(err)) end
    end)
end

-- ---------- the scanner: "Ways out", and the switch in "You" ----------

local inserted = false
for _, c in ipairs(S.categories) do if c.key == "escape" then inserted = true end end
if not inserted then
    for i, c in ipairs(S.categories) do
        if c.key == "zombies" then
            table.insert(S.categories, i + 1, { key = "escape", name = "Ways out", none = "no way out that isn't towards a zombie" })
            break
        end
    end
end

table.insert(S.postBuilders, function(lists)
    lists.escape = lists.escape or {}
    local p = getPlayer()
    local list = ES.find(p)
    for i, c in ipairs(list) do
        local e = {
            cat = "escape", key = "escape|" .. c.kind .. "|" .. math.floor(c.x) .. "," .. math.floor(c.y),
            baseName = kinds[c.kind].name, obj = c.obj, x = c.x, y = c.y, z = c.z,
            walk = kinds[c.kind].walk, order = i, name = ES.words(c),
            alive = function(e) return e.obj ~= nil end,
        }
        if c.kind == "vehicle" then e.walk = "vehicle" end
        table.insert(lists.escape, e)
    end
end)

table.insert(S.builders, function(lists)
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|escape", noWhere = true, order = 904, baseName = "Escape help",
        name = function()
            local on = ES.isOn()
            return "Escape help: " .. (on and "on" or "off") .. ". While a zombie chases you, two rising whistles play "
                .. "from the best way out. {Square} turns it " .. (on and "off" or "on")
        end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function()
            local s = settings()
            s.escapeOff = not (s.escapeOff == true)
            ES.best = nil
            ZA.say("Escape help " .. (s.escapeOff and "off" or "on") .. ".")
        end,
    })
end)
