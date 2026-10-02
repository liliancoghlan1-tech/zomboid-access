-- Zomboid Access: driving (her choice 2026-10-02: a guidance tone for steering, speech for what's ahead).
-- A mod can't steer or press the pedals: the game reads the controller itself (CarController.updateControls).
-- What this does:
--   Steering tone: while you drive forward, it looks down the road (further the faster you go), finds the middle of
--     the road there, and if you need to turn plays a low blip (steer left) or a high blip (steer right), faster the
--     more you need to turn. Silent when you're on line. Car-relative, so it doesn't matter which way the car faces.
--   Speech: what's in your path and how far ("Tree ahead, 15 metres", "Car ahead", "Zombie ahead", "Wall ahead"),
--     "No road ahead" / "Road again", "Junction ahead", "Crash!".
--   Getting in: driver's seat, engine, keys, fuel. Engine started / stopped, cruise control on, off and its speed
--     (the game's own: hold Square and press D-pad up or down to set it, tap Square to switch it on or off).
--   Quick status (Insert, or Share twice) in a vehicle starts with speed, cruise control, fuel and engine.
--   On or off: the "You" list, "Driving help" (on at first; kept in the save).
-- Road squares: the floor sprite's name has "street" in it (floors_exterior_street_*, blends_street_*), proven on
-- the roads round her start 2026-10-02.

ZA.DR = ZA.DR or {}
local DR = ZA.DR
local S = ZA.S

local function settings()
    local ok, t = pcall(function() return ModData.getOrCreate("ZomboidAccessSettings") end)
    return ok and t or {}
end
function DR.isOn() return settings().driveOff ~= true end

local function isRoad(x, y, z)
    local sq = getCell():getGridSquare(math.floor(x), math.floor(y), z)
    local f = sq and sq:getFloor()
    local n = f and f:getSprite() and f:getSprite():getName() or ""
    return n:find("street") ~= nil, sq
end
DR.isRoad = isRoad

local fwd = Vector3f.new()
local function heading(v)
    v:getForwardVector(fwd)
    local hx, hy = fwd:x(), fwd:z()          -- the vehicle's z is the map's y
    local l = math.sqrt(hx * hx + hy * hy)
    if l < 0.01 then return 0, 1 end
    return hx / l, hy / l
end

local function driving(p)
    local v = p and p:getVehicle()
    if v and v:isDriver(p) then return v end
    return nil
end

-- ---------- where the road goes ----------

-- The middle of the road at a point: from that point sideways (rx, ry is the car's right), up to `reach` squares.
-- Returns the sideways offset of the middle (+ = right) and the road's width there, or nil if there's no road.
local function roadAcross(ax, ay, z, rx, ry, reach)
    local start
    for k = 0, reach do
        if isRoad(ax + rx * k, ay + ry * k, z) then start = k; break end
        if k > 0 and isRoad(ax - rx * k, ay - ry * k, z) then start = -k; break end
    end
    if not start then return nil end
    local lo, hi = start, start
    while hi - start < 20 and isRoad(ax + rx * (hi + 1), ay + ry * (hi + 1), z) do hi = hi + 1 end
    while start - lo < 20 and isRoad(ax + rx * (lo - 1), ay + ry * (lo - 1), z) do lo = lo - 1 end
    return (lo + hi) / 2, hi - lo + 1
end

DR.nextTone, DR.nextCheck, DR.nextAhead = 0, 0, 0
DR.saidAhead = {}

local function play(name, x, y, z)
    pcall(function()
        getSoundManager():PlayWorldSoundImpl(name, false, math.floor(x), math.floor(y), math.floor(z), 0, 40, 1, false)
    end)
end

-- ---------- what's in your path ----------

local function pathCheck(p, v, hx, hy, speed)
    local x0, y0, z = v:getX(), v:getY(), math.floor(v:getZ())
    local rx, ry = -hy, hx
    local far = math.max(12, math.min(45, speed / 3.6 * 3))
    -- things that stand still only when they're close (about 1.5 seconds away): further on, a straight line
    -- runs off the road at every bend and finds the trees beside it
    local near = math.max(6, speed / 3.6 * 1.5)
    -- on the road, the tone already says to turn at a bend: things beside the road only when under a second away
    local onRoad = isRoad(x0, y0, z)
    local nearOff = onRoad and math.max(5, speed / 3.6 * 0.9) or near
    for d = 3, far do
        for _, side in ipairs({ 0, -1, 1 }) do
            local x, y = x0 + hx * d + rx * side, y0 + hy * d + ry * side
            local sq = getCell():getGridSquare(math.floor(x), math.floor(y), z)
            if sq then
                local what
                local lim = isRoad(x, y, z) and near or nearOff
                local ok, ov = pcall(function() return sq:getVehicleContainer() end)
                if ok and ov and ov ~= v then what = "Car" end
                if not what then
                    local mo = sq:getMovingObjects()
                    for i = 0, mo:size() - 1 do
                        local o = mo:get(i)
                        if instanceof(o, "IsoZombie") and not o:isDead() then what = "Zombie"; break end
                    end
                end
                if not what and d <= lim then
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        if instanceof(objs:get(i), "IsoTree") then what = "Tree"; break end
                    end
                end
                if not what and (sq:isSolid() or sq:isSolidTrans()) then
                    -- on the road: say it from far off; beside the road: only when it's close
                    if isRoad(x, y, z) then what = "Something on the road"
                    elseif d <= lim then what = "Something solid" end
                end
                -- a wall or fence only counts across your way (a north wall when you drive north or south,
                -- a west wall when you drive east or west); one running beside the road doesn't
                if not what and d <= lim then
                    local across = math.abs(hy) >= math.abs(hx) and IsoFlagType.collideN or IsoFlagType.collideW
                    if sq:has(across) then what = "Wall or fence" end
                end
                if what then return what, d end
            end
        end
    end
    return nil
end

-- ---------- each frame ----------

function DR.tick()
    local p = getPlayer()
    local v = driving(p)
    if not v then DR.v = nil; return end
    local t = getTimestampMs()

    -- getting in, engine, cruise control
    if DR.v ~= v then
        DR.v = v
        DR.engine, DR.cruise, DR.cruiseSpeed = v:isEngineRunning(), v:isRegulator(), v:getRegulatorSpeed()
        DR.lastSpeed, DR.offRoad, DR.saidAhead = nil, nil, {}
        ZA.say(DR.getIn(p, v))
        return
    end
    local engine = v:isEngineRunning()
    if engine ~= DR.engine then
        DR.engine = engine
        ZA.say(engine and "Engine running" or "Engine off")
    end
    local cruise, cs = v:isRegulator(), math.floor(v:getRegulatorSpeed() + 0.5)
    if cruise ~= DR.cruise or (cruise and cs ~= DR.cruiseSpeed) then
        -- autodrive sets the speed itself: don't read every change
        local auto = ZA.RT and ZA.RT.route and ZA.RT.route.mode == "auto"
        if auto then
        elseif cruise then ZA.say("Cruise control " .. cs .. " kilometres an hour")
        elseif DR.cruise then ZA.say("Cruise control off") end
        DR.cruise, DR.cruiseSpeed = cruise, cs
    end

    local speed = v:getCurrentSpeedKmHour()
    -- a crash: the speed falls by a lot at once
    if DR.lastSpeed and DR.lastSpeed > 15 and speed < DR.lastSpeed - 12 and not v:isBraking() then
        ZA.say("Crash!")
    end
    if t >= (DR.nextSpeedSample or 0) then DR.lastSpeed, DR.nextSpeedSample = speed, t + 150 end

    if not DR.isOn() or speed < 3 then return end      -- reversing or standing: no guidance
    local hx, hy = heading(v)
    local z = math.floor(v:getZ())
    local rx, ry = -hy, hx

    -- the road: where its middle is a little way ahead
    if t >= DR.nextCheck then
        DR.nextCheck = t + 60
        local look = math.max(5, math.min(25, 4 + speed / 3.6 * 0.9))
        local ax, ay = v:getX() + hx * look, v:getY() + hy * look
        local mid, width = roadAcross(ax, ay, z, rx, ry, 10)
        if not mid then
            DR.steer = nil
            if DR.offRoad ~= true then
                DR.offRoad = true
                -- is there road under the car at least?
                ZA.say(isRoad(v:getX(), v:getY(), z) and "No road ahead" or "Off the road")
            end
        else
            if DR.offRoad == true then ZA.say("Road again") end
            DR.offRoad = false
            DR.steer = math.deg(math.atan2(mid, look))     -- + = right
            -- a road much wider than the one you're on: a junction or a crossing
            local _, here = roadAcross(v:getX(), v:getY(), z, rx, ry, 3)
            if here and width >= here * 2 + 4 then
                if t >= (DR.junctionQuiet or 0) then ZA.say("Junction ahead") end
                DR.junctionQuiet = t + 6000
            end
        end
    end

    -- the tone: low = steer left, high = steer right; faster the more you need to turn.
    -- With a route (ZA_7DriveRoute) it follows the route; while autodrive steers, it's quiet.
    local a = DR.steer
    local rt = ZA.RT and ZA.RT.route
    if rt then a = (rt.mode ~= "auto") and rt.steer or nil end
    DR.toneAngle = a
    if a and math.abs(a) >= 5 and t >= DR.nextTone then
        play(a > 0 and "ZA_SteerRight" or "ZA_SteerLeft", v:getX(), v:getY(), z)
        local k = math.min(1, (math.abs(a) - 5) / 25)
        DR.nextTone = t + 650 - 530 * k
    end

    -- what's in the path
    if t >= DR.nextAhead then
        DR.nextAhead = t + 250
        local what, d = pathCheck(p, v, hx, hy, speed)
        DR.lastAhead = what and { what = what, d = d, t = t } or nil
        if what then
            local band = d < 8 and 1 or (d < 20 and 2 or 3)
            local last = DR.saidAhead[what]
            if not last or band < last.band or t - last.t > 5000 then
                ZA.say(what .. " ahead, " .. math.floor(d) .. " metres")
                DR.saidAhead[what] = { band = band, t = t }
            end
        end
    end
end
if not DR.ticking then
    DR.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(DR.tick)
        if not ok and not DR.errSaid then DR.errSaid = true; print("[ZA] drive error: " .. tostring(err)) end
    end)
end

-- ---------- words ----------

local function keyWords(p, v)
    if v:isHotwired() then return "hotwired" end
    if v:isKeysInIgnition() then return "key in the ignition" end
    local ok, k = pcall(function() return p:getInventory():haveThisKeyId(v:getKeyId()) end)
    if ok and k then return "you have its key" end
    return "no key: it needs hotwiring"
end

function DR.status(v)
    local p = getPlayer()
    local parts = {}
    local sp = math.floor(math.abs(v:getCurrentSpeedKmHour()) + 0.5)
    table.insert(parts, sp == 0 and "Standing still" or (sp .. " kilometres an hour" .. (v:getCurrentSpeedKmHour() < -1 and ", reversing" or "")))
    if v:isRegulator() then table.insert(parts, "cruise control " .. math.floor(v:getRegulatorSpeed() + 0.5)) end
    table.insert(parts, "fuel " .. math.floor(v:getRemainingFuelPercentage() + 0.5) .. " percent")
    table.insert(parts, v:isEngineRunning() and "engine running" or "engine off")
    if v:getHeadlightsOn() then table.insert(parts, "headlights on") end
    return table.concat(parts, ", ")
end

function DR.getIn(p, v)
    local name = getText("IGUI_VehicleName" .. (v:getScript():getCarModelName() or v:getScript():getName()))
    local state = (v:isEngineRunning() and "engine running" or "engine off") .. ", " .. keyWords(p, v) .. ", fuel "
        .. math.floor(v:getRemainingFuelPercentage() + 0.5) .. " percent"
    local parts = { "In the driver's seat of the " .. name .. ", " .. state }
    table.insert(parts, "Hold D-pad up: the car's menu, to start the engine or hotwire it. R2 accelerates, L2 reverses, Circle brakes, the left stick steers. Cross gets out")
    return table.concat(parts, ". ")
end

-- the quick status starts with the vehicle
if ZA.ST and not DR.statusWrapped then
    DR.statusWrapped = true
    local orig = ZA.ST.summary
    ZA.ST.summary = function()
        local p = getPlayer()
        local v = p and p:getVehicle()
        if not v then return orig() end
        -- the vehicle first, then your health as usual
        ZA.say(DR.status(v) .. ".")
        local say = ZA.say
        ZA.say = ZA.queue
        pcall(orig)
        ZA.say = say
    end
end

-- ---------- the switch in "You" ----------

table.insert(S.builders, function(lists)
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|drive", noWhere = true, order = 905, baseName = "Driving help",
        name = function()
            local on = DR.isOn()
            return "Driving help: " .. (on and "on" or "off") .. ". While you drive, a low blip means steer left, a high "
                .. "blip steer right; things in your path are said. Square turns it " .. (on and "off" or "on")
        end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function()
            local s = settings()
            s.driveOff = not (s.driveOff == true)
            ZA.say("Driving help " .. (s.driveOff and "off" or "on") .. ".")
        end,
    })
end)
