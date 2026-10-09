-- Zomboid Access: walking round zombies.
-- The game's pathfinder takes the shortest way and ignores zombies. When a zombie is within 12 metres, a walk
-- (Square / End, hold Square, escape) plans its own route square by square on this floor, where every square near a
-- zombie costs more (much more right next to one), and walks it in stretches of about 6 squares with the game's own
-- walking (which opens doors and goes round furniture). Each stretch is planned again, since zombies move.
-- The last few steps are the usual walk, so you still end up facing the door or container.
-- Doors, windows and low fences can be crossed; they cost a little more (opening, climbing).

ZA.WS = ZA.WS or {}
local WS = ZA.WS
local W, S = ZA.W, ZA.S

WS.near = 12          -- zombies this close switch the walk to this planner
WS.leg = 6            -- squares per stretch
WS.finish = 3.5       -- this close to the target: the usual walk does the rest
WS.margin = 10        -- squares around you and the target the planner looks at
WS.maxSide = 70

local function zombiesNear(p, r)
    local out = {}
    local zl = getCell():getZombieList()
    local pz = math.floor(p:getZ())
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.floor(z:getZ()) == pz then
            local d = math.sqrt((z:getX() - p:getX()) ^ 2 + (z:getY() - p:getY()) ^ 2)
            if d <= r then table.insert(out, z) end
        end
    end
    return out
end

function WS.wanted(p, e)
    if not e or e.walk == "travel" or e.walk == "stairsUp" or e.walk == "stairsDown" or e.walk == "mob" then return false end
    local _, _, z = S.entryPos(e)
    if math.floor(z or 0) ~= math.floor(p:getZ()) then return false end
    return #zombiesNear(p, WS.near) > 0
end

-- ---------- the planner (A*) ----------

-- a small binary heap of {f, node}
local function hpush(h, f, n)
    table.insert(h, { f, n })
    local i = #h
    while i > 1 do
        local pi = math.floor(i / 2)
        if h[pi][1] <= h[i][1] then break end
        h[pi], h[i] = h[i], h[pi]
        i = pi
    end
end
local function hpop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
        h[1] = last
        local i = 1
        while true do
            local l, r, m = i * 2, i * 2 + 1, i
            if l <= #h and h[l][1] < h[m][1] then m = l end
            if r <= #h and h[r][1] < h[m][1] then m = r end
            if m == i then break end
            h[m], h[i] = h[i], h[m]
            i = m
        end
    end
    return top
end

-- What crossing from square a to the next square b costs extra, or nil if it can't be crossed.
local function edgeCost(a, b)
    if not a:isBlockedTo(b) then return 0 end
    if a:isDoorTo(b) then return 2 end
    if a:isWindowTo(b) or a:getWindowFrameTo(b) then return 5 end
    if a:isHoppableTo(b) then return 3 end
    return nil
end

local function danger(zs, x, y)
    local c = 0
    for _, z in ipairs(zs) do
        local d = math.sqrt((z:getX() - x - 0.5) ^ 2 + (z:getY() - y - 0.5) ^ 2)
        if d < 1.5 then c = c + 60
        elseif d < 2.5 then c = c + 20
        elseif d < 4 then c = c + 6
        elseif d < 6 then c = c + 2 end
    end
    return c
end

-- A route of squares from the player to (tx, ty), avoiding zombies; nil if there's none in the area looked at.
function WS.plan(p, tx, ty)
    local z = math.floor(p:getZ())
    local sx, sy = math.floor(p:getX()), math.floor(p:getY())
    tx, ty = math.floor(tx), math.floor(ty)
    local x0 = math.max(math.min(sx, tx) - WS.margin, math.max(sx, tx) - WS.maxSide)
    local x1 = math.min(math.max(sx, tx) + WS.margin, math.min(sx, tx) + WS.maxSide)
    local y0 = math.max(math.min(sy, ty) - WS.margin, math.max(sy, ty) - WS.maxSide)
    local y1 = math.min(math.max(sy, ty) + WS.margin, math.min(sy, ty) + WS.maxSide)
    local W_ = x1 - x0 + 1
    local function id(x, y) return (y - y0) * W_ + (x - x0) end
    local zs = zombiesNear(p, 40)
    local cell = getCell()
    local sqCache = {}
    local function sq(x, y)
        local k = id(x, y)
        local v = sqCache[k]
        if v == nil then
            v = cell:getGridSquare(x, y, z) or false
            sqCache[k] = v
        end
        return v or nil
    end
    local function walkable(s) return s and (s:isFree(false) or s:getFloor() ~= nil and not s:isSolid() and not s:isSolidTrans()) end
    local g, came, closed = {}, {}, {}
    local h = {}
    local start, goal = id(sx, sy), id(tx, ty)
    g[start] = 0
    hpush(h, 0, start)
    local steps = 0
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
    local found
    while #h > 0 do
        steps = steps + 1
        if steps > 6000 then break end
        local cur = hpop(h)[2]
        if not closed[cur] then
            closed[cur] = true
            local cx, cy = x0 + cur % W_, y0 + math.floor(cur / W_)
            -- near enough: the usual walk does the last steps (the target itself may be a wall, a door, a counter)
            if cur == goal or (math.abs(cx - tx) <= 1 and math.abs(cy - ty) <= 1) then found = cur; break end
            local a = sq(cx, cy)
            for _, d in ipairs(dirs) do
                local nx, ny = cx + d[1], cy + d[2]
                if nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
                    local b = sq(nx, ny)
                    local nid = id(nx, ny)
                    if b and not closed[nid] and walkable(b) then
                        local extra
                        if d[1] ~= 0 and d[2] ~= 0 then
                            -- diagonal: both straight ways round must be open (no cutting corners through walls)
                            local s1, s2 = sq(cx + d[1], cy), sq(cx, cy + d[2])
                            if s1 and s2 and not a:isBlockedTo(s1) and not a:isBlockedTo(s2)
                                and not s1:isBlockedTo(b) and not s2:isBlockedTo(b) and walkable(s1) and walkable(s2) then
                                extra = 0.41
                            end
                        else
                            extra = edgeCost(a, b)
                        end
                        if extra then
                            local ng = g[cur] + 1 + extra + danger(zs, nx, ny)
                            if not g[nid] or ng < g[nid] then
                                g[nid] = ng
                                came[nid] = cur
                                local hx, hy = math.abs(nx - tx), math.abs(ny - ty)
                                hpush(h, ng + math.max(hx, hy) + 0.41 * math.min(hx, hy), nid)
                            end
                        end
                    end
                end
            end
        end
    end
    if not found then return nil end
    local path = {}
    local n = found
    while n do
        table.insert(path, 1, { x = x0 + n % W_, y = y0 + math.floor(n / W_), z = z })
        n = came[n]
    end
    return path
end

-- ---------- walking it ----------

local function startLeg(p)
    local st = W.safe
    local e = st.entry
    local tx, ty = S.entryPos(e)
    local path = WS.plan(p, tx, ty)
    if not path or #path < 2 then return false end
    -- the end of this stretch: WS.leg squares on, or the end of the route
    local i = math.min(#path, WS.leg + 1)
    local to = getCell():getGridSquare(path[i].x, path[i].y, path[i].z)
    if not to then return false end
    ISTimedActionQueue.clear(p)
    local a = ISWalkToTimedAction:new(p, to)
    ISTimedActionQueue.add(a)
    W.action, W.entry = a, e
    W.watchFail(a)
    st.legs = st.legs + 1
    ZA.log("[ZA] safe leg " .. st.legs .. " to " .. path[i].x .. "," .. path[i].y .. " (" .. #path .. " squares left)")
    return true
end

-- The usual walk for the last steps (it knows doors, containers, facing).
local function finish(p)
    local e = W.safe.entry
    W.safe = nil
    local ok, res, action = pcall(W.startWalk, p, e, 1)
    if ok and res == true then
        W.action, W.entry, W.try = action, e, 1
        W.watchFail(action)
        return
    end
    if ok and res == "here" then
        pcall(function() if e.obj then p:faceThisObject(e.obj) end end)
        if W.afterArrive then local f = W.afterArrive; W.afterArrive = nil; f(); return end
        ZA.say("Arrived: " .. S.entryName(e) .. ".")
        return
    end
    W.afterArrive = nil
    ZA.say("Couldn't get right up to " .. S.entryName(e) .. ".")
end

function WS.start(p, e, warn)
    W.safe = { entry = e, legs = 0, fails = 0 }
    local x, y = S.entryPos(e)
    if math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2) <= WS.finish then
        W.safe = nil
        return false
    end
    if not startLeg(p) then W.safe = nil; return false end
    -- the zombies you're walking round don't stop the walk; a new one coming close still does
    W.known = {}
    local zl = getCell():getZombieList()
    for i = 0, zl:size() - 1 do W.known[zl:get(i)] = true end
    ZA.log("[ZA] safe walk to " .. e.key)
    ZA.say((warn or "") .. "Walking round the zombies to " .. S.entryName(e) .. ". {Square} or End stops.")
    return true
end

function WS.legDone(p, failed, succeeded)
    local st = W.safe
    local e = st.entry
    local moved = false
    pcall(function() moved = p:pressedMovement(false) or p:pressedCancelAction() end)
    if moved and not failed and not succeeded then
        W.safe, W.entry = nil, nil
        ZA.say("Stopped.")
        return
    end
    local x, y = S.entryPos(e)
    local d = math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2)
    if d <= WS.finish or #zombiesNear(p, WS.near) == 0 then
        finish(p)
        return
    end
    if failed then st.fails = st.fails + 1 end
    if st.fails >= 3 or st.legs >= 40 or not startLeg(p) then
        -- no way round found: the usual walk, so the player still gets somewhere
        finish(p)
    end
end
