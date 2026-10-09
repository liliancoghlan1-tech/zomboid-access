-- Zomboid Access: walk to the thing selected in the scanner (End / pad Square), using the game's own
-- pathfinding, the same walking a mouse click on an object starts. End again, or moving the stick, stops it.
-- On arrival the character turns to face it, so Cross (the game's interact button) uses it.
-- Far places (the Places and Houses categories) are travelled to in legs of about 30 metres, since the
-- game only finds paths through the part of the world that is loaded around you.

ZA.W = ZA.W or {}
local W = ZA.W
local S = ZA.S

-- The action the game queued for us, and what we are walking to.
W.action, W.entry, W.startedAt = nil, nil, 0
W.legLength = 30

local function queueTail(p)
    local q = ISTimedActionQueue.getTimedActionQueue(p)
    return q and q.queue and q.queue[#q.queue] or nil
end

local function square(x, y, z) return getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z)) end

-- Any free square next to sq the pathfinder can reach (it tries them all and takes the nearest).
local function pathNextTo(p, sq)
    local a = ISPathFindAction:pathAdjacentToSquares(p, { sq }, true)
    if a then ISTimedActionQueue.add(a); return true end
    return false
end

-- The ways to walk to each kind of thing, best first. A walk that fails tries the next way.
local function strategies(e)
    local function obj() return e.obj end
    if e.walk == "door" then
        return {
            function(p, sq) return luautils.walkAdjWindowOrDoor(p, obj():getSquare(), obj()) end,
            function(p, sq) return pathNextTo(p, obj():getSquare()) end,
        }
    elseif e.walk == "container" then
        return {
            function(p, sq) return luautils.walkAdjObject(p, obj(), true) end,
            function(p, sq) return sq and pathNextTo(p, sq) end,
        }
    elseif e.walk == "vehicle" then
        return { function(p, sq)
            local a = ISPathFindAction:pathToVehicleAdjacent(p, obj())
            if a then ISTimedActionQueue.add(a); return true end
            return false
        end }
    elseif e.walk == "stairsUp" then
        return { function(p, sq)
            -- the floor beyond the top step: the pathfinder climbs on its own
            local o = obj()
            local ox, oy, oz = o:getSquare():getX(), o:getSquare():getY(), o:getSquare():getZ()
            local top = e.north and square(ox, oy - 3, oz + 1) or square(ox - 3, oy, oz + 1)
            local target = top or (e.north and square(ox, oy + 1, oz) or square(ox + 1, oy, oz))
            if target then ISTimedActionQueue.add(ISWalkToTimedAction:new(p, target)); return true end
            return false
        end }
    elseif e.walk == "stairsDown" then
        return { function(p, sq)
            -- the floor in front of the bottom step, one floor down
            local fx, fy = e.tx, e.ty
            if e.north then fy = fy + 3 else fx = fx + 3 end
            local front = square(fx, fy, e.tz)
            if front then ISTimedActionQueue.add(ISWalkToTimedAction:new(p, front)); return true end
            return false
        end }
    end
    -- things on the ground, water, beds, bodies, zombies, animals: stand next to it
    return {
        function(p, sq) return sq and pathNextTo(p, sq) end,
        function(p, sq) return sq and luautils.walkAdj(p, sq) end,
        function(p, sq) return sq and luautils.walk(p, sq) end,
    }
end

-- Start a walk with way number `try`; returns true + the queued action, "here" when already there,
-- false when this way can't start.
local function startWalk(p, e, try)
    local x, y, z = S.entryPos(e)
    local sq = square(x, y, z)
    ISTimedActionQueue.clear(p)
    local before = queueTail(p)
    local list = strategies(e)
    local f = list[try or 1]
    if not f then return false end
    local ok = f(p, sq)
    local tail = queueTail(p)
    if tail and tail ~= before then return true, tail end
    if ok then return "here" end
    return false
end

-- Keep an eye on a queued action failing (an ISPathFindAction reports it through setOnFail).
local function watchFail(a)
    W.failed = false
    if a and a.setOnFail then a:setOnFail(function() W.failed = true end) end
end

function W.stop(quiet)
    local p = getPlayer()
    if (W.action or W.travel) and p then ISTimedActionQueue.clear(p) end
    W.action, W.entry, W.travel, W.afterArrive, W.safe = nil, nil, nil, nil, nil
    if not quiet then ZA.say("Stopped.") end
end

W.startWalk, W.watchFail, W.strategies = startWalk, watchFail, strategies

local function face(p, e)
    pcall(function()
        if e.obj and e.walk ~= "mob" and e.walk ~= "travel" then p:faceThisObject(e.obj) end
    end)
end

-- ---------- travel in legs ----------

-- A free square about `len` metres from the player toward (tx, ty), turned by `turn` degrees.
local function waypoint(p, tx, ty, len, turn)
    local px, py = p:getX(), p:getY()
    local dx, dy = tx - px, ty - py
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.01 then return nil end
    local a = math.atan2(dy, dx) + math.rad(turn or 0)
    local l = math.min(len, d)
    local wx, wy = px + math.cos(a) * l, py + math.sin(a) * l
    local z = math.floor(p:getZ())
    for r = 0, 6 do
        for ox = -r, r do
            for oy = -r, r do
                if math.max(math.abs(ox), math.abs(oy)) == r then
                    local sq = square(wx + ox, wy + oy, z)
                    if sq and sq:isFree(false) then return sq end
                end
            end
        end
    end
    return nil
end

local turns = { 0, 35, -35, 70, -70 }

local function travelLeg(p)
    local tr = W.travel
    local e = tr.entry
    local tx, ty, tz = S.entryPos(e)
    local d = math.sqrt((tx - p:getX()) ^ 2 + (ty - p:getY()) ^ 2)
    if e.marker and d <= W.legLength and tr.turn == 1 then
        local sq = square(tx, ty, tz or 0)
        if sq then
            ISTimedActionQueue.clear(p)
            local a = ISWalkToTimedAction:new(p, sq)
            ISTimedActionQueue.add(a)
            W.action, W.entry = a, e
            watchFail(a)
            return true
        end
    end
    for i = tr.turn, #turns do
        local len = (i > 3) and 15 or W.legLength
        local sq = waypoint(p, tx, ty, len, turns[i])
        if sq then
            ISTimedActionQueue.clear(p)
            local a = ISWalkToTimedAction:new(p, sq)
            ISTimedActionQueue.add(a)
            tr.turn = i
            W.action, W.entry = a, e
            watchFail(a)
            return true
        end
    end
    return false
end

local function travelArrived(p, e)
    local x, y = S.entryPos(e)
    local d = math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2)
    if e.key:find("|town|", 1, true) then return d <= 80 end
    if e.marker then
        local _, _, z = S.entryPos(e)
        return d <= 1.5 and math.floor(z) == math.floor(p:getZ())
    end
    return d <= 3
end

function W.startTravel(p, e, warn)
    W.travel = { entry = e, turn = 1, fails = 0, lastBand = nil }
    if travelArrived(p, e) then
        W.travel = nil
        ZA.say("You're already at " .. S.entryName(e) .. ".")
        return
    end
    if not travelLeg(p) then
        W.travel = nil
        ZA.say("No way to start towards " .. S.entryName(e) .. " from here.")
        return
    end
    local x, y, z = S.entryPos(e)
    ZA.log("[ZA] travel to " .. e.key)
    ZA.say(warn .. "Travelling to " .. S.entryName(e) .. ", " .. S.where(x, y, z) .. ". {Square} or End stops.")
end

-- A leg ended: go on, try another way round, or say we've arrived.
local function travelNext(p, ok)
    local tr = W.travel
    local e = tr.entry
    if travelArrived(p, e) then
        W.travel, W.action, W.entry = nil, nil, nil
        ZA.log("[ZA] travel arrived " .. e.key)
        if e.key:find("|town|", 1, true) then
            ZA.say("You're in " .. e.baseName .. ". The Places category lists what's here.")
        elseif e.marker then
            ZA.say("You're at " .. e.marker.name .. ".")
        else
            ZA.say("You've reached the " .. S.entryName(e) .. ". The Doors category lists the way in.")
        end
        return
    end
    if ok then tr.turn, tr.fails = 1, 0 else tr.turn, tr.fails = tr.turn + 1, tr.fails + 1 end
    local x, y, z = S.entryPos(e)
    if tr.fails >= #turns or not travelLeg(p) then
        W.travel, W.action, W.entry = nil, nil, nil
        print("[ZA] travel stuck " .. e.key)
        ZA.say("Can't find a way further. " .. S.entryName(e) .. " is " .. S.where(x, y, z) .. ".")
        return
    end
    -- a progress word every 50 metres
    local d = math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2)
    local band = math.floor(d / 50)
    if tr.lastBand and band < tr.lastBand then ZA.say(S.where(x, y, z) .. " to go.") end
    tr.lastBand = band
end

-- ---------- going ----------

function W.go()
    local p = getPlayer()
    if W.action or W.travel or W.safe then W.stop(); return end
    if p:getVehicle() then
        -- driving: route guidance to it (ZA_7DriveRoute); again stops the route
        if ZA.RT and ZA.RT.route then ZA.RT.stop(); return end
        local e = S.current()
        if e and not e.noWhere and not e.action and p:getVehicle():isDriver(p) and ZA.RT then
            ZA.RT.start(e, "guide")
        else
            ZA.say("You're in a vehicle.")
        end
        return
    end
    if getGameSpeed() == 0 then ZA.say("The game is paused."); return end
    local e = S.current()
    if not e then ZA.say("Nothing selected. Use Page Down to pick something first."); return end
    if e.action then e.action(); return end
    if not S.alive(e) then ZA.say(S.entryName(e) .. " is gone."); return end
    if e.noWhere then ZA.say("That's about you; pick a place in another category."); return end
    if ZA.G and ZA.G.entry then ZA.G.stop() end
    local name = S.entryName(e)
    -- zombies already close when you choose to walk (to get away, say) only get a warning
    W.known = {}
    local warn = ""
    local z = S.nearestThreat(6, 2.5)
    if z then
        warn = "Careful, " .. S.threatText(z) .. ". "
        local zl = getCell():getZombieList()
        for i = 0, zl:size() - 1 do W.known[zl:get(i)] = true end
    end
    W.startZ = p:getZ()
    if e.walk == "travel" then
        local ok, err = pcall(W.startTravel, p, e, warn)
        if not ok then print("[ZA] travel error: " .. tostring(err)); ZA.say("Can't travel there.") end
        return
    end
    -- zombies close by: walk round them in short stretches (ZA_6WalkSafe), the last few steps the usual way
    if ZA.WS and ZA.WS.wanted(p, e) then
        local ok, started = pcall(ZA.WS.start, p, e, warn)
        if ok and started then return end
        if not ok then print("[ZA] safe walk error: " .. tostring(started)) end
    end
    local ok, res, action = pcall(startWalk, p, e, 1)
    if not ok then
        print("[ZA] walk error: " .. tostring(res))
        ZA.say("Can't walk there.")
        return
    end
    local try = 1
    while not res and try < #strategies(e) do
        try = try + 1
        ok, res, action = pcall(startWalk, p, e, try)
        if not ok then res = false end
    end
    if res == "here" then
        face(p, e)
        if W.afterArrive then local f = W.afterArrive; W.afterArrive = nil; f(); return end
        ZA.say("You're already at " .. name .. ".")
        return
    end
    if not res then
        W.afterArrive = nil
        ZA.say("No way to get to " .. name .. " from here.")
        return
    end
    W.action, W.entry, W.startedAt, W.try = action, e, getTimestampMs(), try
    watchFail(action)
    ZA.log("[ZA] walk to " .. e.key)
    ZA.say(warn .. "Walking to " .. name .. ". {Square} or End stops.")
end

-- Watch the walk: arrived, stopped by the player, or no way through (then try the next way once).
function W.watch()
    if not W.action then return end
    local p = getPlayer()
    if not p or p:isDead() then W.action, W.travel, W.safe = nil, nil, nil; return end
    -- a zombie close by stops the walk: walking into one is how you die
    local t = getTimestampMs()
    if t >= (W.nextThreatCheck or 0) then
        W.nextThreatCheck = t + 250
        local z = S.nearestThreat(6, 2.5)
        if z and not (W.known and W.known[z]) then
            local e = W.entry
            W.action, W.entry, W.travel, W.safe = nil, nil, nil, nil
            ISTimedActionQueue.clear(p)
            ZA.log("[ZA] walk stopped by zombie " .. (e and e.key or ""))
            ZA.urgent("Stopped! " .. S.threatText(z) .. ".")
            return
        end
    end
    if ISTimedActionQueue.hasAction(W.action) then return end
    local e, a = W.entry, W.action
    local failed = W.failed or (a.result and a.result == BehaviorResult.Failed)
    local succeeded = a.result and a.result == BehaviorResult.Succeeded
    W.action = nil

    if W.safe then
        local ok, err = pcall(ZA.WS.legDone, p, failed, succeeded)
        if not ok then print("[ZA] safe walk error: " .. tostring(err)); W.safe, W.entry = nil, nil end
        return
    end

    if W.travel then
        -- a leg ended: stopped by the player (they moved), or done / failed
        local moved = false
        pcall(function() moved = p:pressedMovement(false) or p:pressedCancelAction() end)
        if moved and not failed and not succeeded then
            W.travel, W.entry = nil, nil
            ZA.say("Stopped.")
            return
        end
        travelNext(p, not failed)
        return
    end

    W.entry = nil
    local name = S.entryName(e)
    local x, y, z = S.entryPos(e)
    local d = math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2)
    local sameFloor = math.floor(z) == math.floor(p:getZ())
    local arrived = d <= 2.3 and sameFloor
    if e.walk == "stairsUp" then arrived = math.floor(p:getZ()) > math.floor(W.startZ or 0) end
    if e.walk == "stairsDown" then arrived = math.floor(p:getZ()) < math.floor(W.startZ or 0) end
    if arrived or (succeeded and not failed) then
        face(p, e)
        if e.walk == "stairsUp" then ZA.say("You're at the top of the stairs.")
        elseif e.walk == "stairsDown" then ZA.say("You're at the bottom of the stairs.")
        elseif W.afterArrive then
            local f = W.afterArrive
            W.afterArrive = nil
            f()
        else ZA.say("Arrived: " .. name .. ".") end
        ZA.log("[ZA] walk arrived " .. e.key)
    elseif failed then
        -- one more go another way before giving up
        local try = (W.try or 1) + 1
        if try <= #strategies(e) then
            local ok, res, action = pcall(startWalk, p, e, try)
            if ok and res == true then
                W.action, W.entry, W.try = action, e, try
                watchFail(action)
                ZA.log("[ZA] walk retry " .. try .. " " .. e.key)
                return
            end
        end
        W.afterArrive = nil
        ZA.say("Couldn't find a way to " .. name .. ". It's " .. S.where(x, y, z) .. ".")
        print("[ZA] walk failed " .. e.key)
    else
        W.afterArrive = nil
        ZA.say("Stopped. " .. name .. " is " .. S.where(x, y, z) .. ".")
        ZA.log("[ZA] walk stopped " .. e.key)
    end
end
if not W.ticking then
    W.ticking = true
    ZA.onTick(function() W.watch() end)
end

function W.onKey(key)
    if key ~= Keyboard.KEY_END or isCtrlKeyDown() or isShiftKeyDown() or not S.inWorld() then return end
    local ok, err = pcall(W.go)
    if not ok then print("[ZA] walk key error: " .. tostring(err)) end
end
if not W.hooked then
    W.hooked = true
    Events.OnKeyPressed.Add(function(key) W.onKey(key) end)
end
