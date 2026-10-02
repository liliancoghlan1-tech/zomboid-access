-- Zomboid Access: where am I, and what the day is doing.
--   Shift+Insert, or the first line of the scanner's "You" list: the town, the street, the building and room,
--     the floor, and your nearest marker. Streets come from the game's own map data
--     (media/maps/Muldraugh, KY/streets.xml, the whole map), read when first needed.
--   Said by itself: an hour before dark, nightfall, dawn, falling asleep and waking (with the time), and the
--   moment the power or the water goes off.

ZA.WH = ZA.WH or {}
local WH = ZA.WH
local S = ZA.S

-- ---------- streets ----------

WH.streets = nil   -- { { name, {x1, y1, x2, y2, ...} }, ... }

function WH.loadStreets()
    if WH.streets then return WH.streets end
    -- ZA_5WhereStreets.lua holds the map's streets (made by tools/gen_streets.py from the game's
    -- media/maps/Muldraugh, KY/streets.xml): getGameFilesTextInput only works in the game's debug mode.
    if ZA.STREETS then
        WH.streets = {}
        for _, st in ipairs(ZA.STREETS) do table.insert(WH.streets, { name = st[1], pts = st[2] }) end
        print("[ZA] streets loaded: " .. #WH.streets)
        return WH.streets
    end
    WH.streets = {}
    local ok, err = pcall(function()
        local br = getGameFilesTextInput("media/maps/Muldraugh, KY/streets.xml")
        if not br then return end
        local cur
        local line = br:readLine()
        while line do
            local name = line:match('<street%s+name="([^"]*)"')
            if name then
                cur = { name = name, pts = {} }
                table.insert(WH.streets, cur)
            elseif cur then
                local x, y = line:match('<point%s+x="([%d%.%-]+)"%s+y="([%d%.%-]+)"')
                if x then
                    table.insert(cur.pts, tonumber(x))
                    table.insert(cur.pts, tonumber(y))
                end
            end
            line = br:readLine()
        end
        endTextFileInput()
    end)
    if not ok then print("[ZA] streets error: " .. tostring(err)) end
    print("[ZA] streets loaded: " .. #WH.streets)
    return WH.streets
end

local function segDist(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local l2 = dx * dx + dy * dy
    local t = 0
    if l2 > 0 then t = math.max(0, math.min(1, ((px - x1) * dx + (py - y1) * dy) / l2)) end
    local cx, cy = x1 + t * dx, y1 + t * dy
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2), cx, cy
end

-- The nearest street: name, distance, and the nearest point on it.
function WH.nearestStreet(px, py)
    local best, bd, bx, by
    for _, st in ipairs(WH.loadStreets()) do
        local p = st.pts
        for i = 1, #p - 3, 2 do
            local d, cx, cy = segDist(px, py, p[i], p[i + 1], p[i + 2], p[i + 3])
            if not bd or d < bd then best, bd, bx, by = st.name, d, cx, cy end
        end
    end
    return best, bd, bx, by
end

-- ---------- where ----------

local function townWords(px, py)
    local best, bd
    for _, t in ipairs(S.towns or {}) do
        local d = math.sqrt((t.x - px) ^ 2 + (t.y - py) ^ 2)
        if not bd or d < bd then best, bd = t, d end
    end
    if not best then return nil end
    if bd < 700 then return "In " .. best.name end
    return "Outside town; the nearest is " .. best.name .. ", " .. S.where(best.x, best.y, 0)
end

function WH.text()
    local p = getPlayer()
    local px, py, pz = p:getX(), p:getY(), math.floor(p:getZ())
    local parts = {}
    local t = townWords(px, py)
    if t then table.insert(parts, t) end
    local name, d, sx, sy = WH.nearestStreet(px, py)
    if name then
        if d <= 7 then table.insert(parts, "on " .. name)
        elseif d <= 30 then table.insert(parts, "near " .. name .. ", " .. S.where(sx, sy, pz))
        else table.insert(parts, "the nearest street is " .. name .. ", " .. S.where(sx, sy, pz)) end
    end
    local sq = p:getCurrentSquare()
    local room = sq and sq:getRoom()
    if room then
        local where = "inside"
        pcall(function()
            local b = getWorld():getMetaGrid():getBuildingAt(math.floor(px), math.floor(py))
            local kind = b and S.buildingKind and S.buildingKind(b)
            if b and b:isResidential() then kind = "a house" elseif kind then kind = "the " .. kind end
            if kind then where = "in " .. kind end
        end)
        local rn = S.roomName and S.roomName(room)
        if rn then where = where .. ", in the " .. rn end
        table.insert(parts, where)
    else
        table.insert(parts, "outdoors")
    end
    if pz > 0 then table.insert(parts, pz == 1 and "upstairs" or ("floor " .. (pz + 1)))
    elseif pz < 0 then table.insert(parts, "in the basement") end
    -- the nearest marker
    local mk, md
    for _, m in ipairs(ZA.MK and ZA.MK.all() or {}) do
        local dd = (m.x - px) ^ 2 + (m.y - py) ^ 2
        if not md or dd < md then mk, md = m, dd end
    end
    if mk then table.insert(parts, mk.name .. " is " .. S.where(mk.x, mk.y, mk.z)) end
    local s = table.concat(parts, ", ")
    return s:sub(1, 1):upper() .. s:sub(2) .. "."
end

function WH.say()
    local ok, t = pcall(WH.text)
    if ok then ZA.say(t) else print("[ZA] where error: " .. tostring(t)) end
end

-- First line of the "You" list.
table.insert(S.builders, function(lists)
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|where", noWhere = true, order = -1, baseName = "Where",
        name = function() local ok, t = pcall(WH.text); return ok and t or "Where: unknown" end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
    })
end)

-- ---------- the day, the power and the water ----------

local function dayNumber()
    local so = getSandboxOptions()
    return getGameTime():getWorldAgeHours() / 24 + (so:getTimeSinceApo() - 1) * 30
end

function WH.utilities()
    local power, water = true, true
    pcall(function() power = getWorld():isHydroPowerOn() end)
    pcall(function()
        local m = getSandboxOptions():getWaterShutModifier()
        if m > -1 and dayNumber() >= m then water = false end
    end)
    return power, water
end

WH.next, WH.said = 0, {}

function WH.tick()
    local p = getPlayer()
    if not p or p:isDead() then return end
    local t = getTimestampMs()
    if t < WH.next then return end
    WH.next = t + 2000
    local gt = getGameTime()
    local hour = gt:getTimeOfDay()
    local day = math.floor(gt:getWorldAgeHours() / 24)
    local season = getClimateManager():getSeason()   -- today's dawn and dusk, in hours (e.g. 7.05, 21.58)
    local dawn, dusk = season:getDawn(), season:getDusk()
    local function once(key, text)
        local k = key .. day
        if WH.said[k] then return end
        WH.said[k] = true
        if WH.started then ZA.queue(text) end
    end
    if hour >= dusk - 1 and hour < dusk then once("predusk", "It'll be dark in about an hour.") end
    if hour >= dusk then once("dusk", "Night has fallen. Zombies are harder to see, and so are you.") end
    if hour >= dawn and hour < dawn + 1 then once("dawn", "Dawn: it's getting light.") end
    -- sleeping and waking
    local asleep = false
    pcall(function() asleep = p:isAsleep() end)
    if WH.started and asleep ~= WH.asleep then
        if asleep then ZA.say("Asleep.") else ZA.say("You woke up. It's " .. ZA.timeWords() .. ".") end
    end
    WH.asleep = asleep
    local power, water = WH.utilities()
    if WH.started then
        if WH.power and not power then ZA.say("The power has gone off. Lights and fridges won't work any more.") end
        if WH.water and not water then ZA.say("The water has been cut off. Taps won't run any more; collect rain or find bottles.") end
    end
    WH.power, WH.water = power, water
    WH.started = true   -- nothing is announced on the first check after loading
end

if not WH.ticking then
    WH.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(WH.tick)
        if not ok then print("[ZA] where tick error: " .. tostring(err)) end
    end)
end

Events.OnGameStart.Add(function() WH.started, WH.power, WH.water, WH.said = false, nil, nil, {} end)

function WH.onKey(key)
    if key ~= Keyboard.KEY_INSERT or not (isShiftKeyDown() or isCtrlKeyDown()) or not S.inWorld() then return end
    WH.say()
end
if not WH.hooked then
    WH.hooked = true
    Events.OnKeyPressed.Add(function(key) WH.onKey(key) end)
end
