-- Zomboid Access: the game's square-choosing cursor, spoken. It opens for digging a furrow, sowing seeds, watering,
-- harvesting, building, placing furniture and more: the game draws a highlighted square that the D-pad moves one
-- square at a time (ISBuildingObject xJoypad/yJoypad), and Cross does the thing there.
--   Opening: what it's for and the buttons (from the game's own button prompts).
--   Each move: where the square is from you, whether Cross can do it there, the ground (soil, grass, road...),
--   what's on it (a plant, a furrow, something in the way), and the game's own note (seeds left, "not a furrow").
-- The scanner layer is switched off while it's open, so the D-pad moves the square.

local S = ZA.S
ZA.CU = ZA.CU or {}
local CU = ZA.CU

-- ---------- the square ----------

local function floorWord(sq)
    local ok, kind = pcall(function() return ISShovelGroundCursor.GetDirtGravelSand(sq) end)
    if ok and kind == "dirt" then return "soil" end
    if ok and kind == "gravel" then return "gravel" end
    if ok and kind == "sand" then return "sand" end
    local f = sq:getFloor()
    local n = f and f:getSprite() and f:getSprite():getName() or ""
    if n:find("natural") then return "grass" end
    if n:find("street") or n:find("road") then return "road" end
    if n:find("interior") or sq:getRoom() then return "floor indoors" end
    if n:find("exterior") then return "paving" end
    return nil
end

-- A plant or furrow on the square, in the words the game uses (CFarmingSystem, farming_vegetableconf).
function CU.plantWords(plant, character)
    local name = farming_vegetableconf.getObjectName(plant)
    if not plant:isAlive() or plant.state == "plow" then return name end
    local parts = { name }
    local lvl = CFarmingSystem.instance:getXp(character or getPlayer())
    local ok, w = pcall(ISFarmingInfo.getWaterLvl, plant, lvl)
    if ok and w then table.insert(parts, "water: " .. ZA.clean(w):lower()) end
    -- diseases show to a farmer of level 3 or more, as in the game's info window
    if lvl >= 3 and ISFarmingInfo.hasDisease(plant) then
        local d = {}
        for _, k in ipairs({ { "aphidLvl", "Farming_Aphid" }, { "mildewLvl", "Farming_Mildew" },
                             { "fliesLvl", "Farming_Pest_Flies" }, { "slugsLvl", "Farming_Slugs" } }) do
            local v = plant[k[1]] or 0
            if v > 0 then table.insert(d, getText(k[2]) .. " " .. ISFarmingInfo.getDiseaseString(v, lvl):lower()) end
        end
        table.insert(parts, "sick: " .. table.concat(d, ", "))
    end
    return table.concat(parts, ", ")
end

-- Something standing on the square that stops you using it.
local function obstacle(sq)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        if instanceof(o, "IsoTree") then return "a tree" end
        if o ~= sq:getFloor() and not instanceof(o, "IsoWorldInventoryObject") then
            local n = S.moveableName and S.moveableName(o)
            if n and n ~= "" then return n:lower() end
        end
    end
    if sq:has(IsoFlagType.collideW) or sq:has(IsoFlagType.collideN) then return "a wall" end
    return nil
end

local function valid(drag, sq)
    if drag.canBeBuild ~= nil then return drag.canBeBuild end
    if drag.isValid then
        local ok, v = pcall(drag.isValid, drag, sq)
        if ok then return v end
    end
    return nil
end

-- The game blanks its Cross prompt on a square where it can't be done: remember the last one it gave.
-- A farming cursor's prompt is just "Farming": its own note (tooltipTxt) names the job instead.
local function noteText(drag)
    if not drag.tooltipTxt then return "" end
    return ZA.clean((drag.tooltipTxt:gsub("%s*<LINE>%s*", ". "))):gsub("^[%.%s]+", "")
end

local function actionWord(drag)
    -- a building cursor (ISBuildIsoEntity) prompts "Carpentry" and the like: say build
    if drag.craftRecipe then return "build" end
    local ok, a = pcall(function() return drag:getAPrompt() end)
    a = ok and a and ZA.clean(a) or ""
    if a == getText("ContextMenu_Farming") then
        -- the farming cursor's note says the job: "Sow: Carrot Seeds", "Water: ..."
        a = noteText(drag):match("([%a][%a ]-)%s*:") or ""
    end
    if a ~= "" then drag.zaAction = a end
    return drag.zaAction or ""
end

-- "1 square up-right", "3 squares down": the cursor moves in squares, and the direction matters even next to you
local function squaresFrom(x, y, z)
    local p = getPlayer()
    local dx, dy = x + 0.5 - p:getX(), y + 0.5 - p:getY()
    local n = math.max(math.abs(math.floor(x) - math.floor(p:getX())), math.abs(math.floor(y) - math.floor(p:getY())))
    local s = n .. (n == 1 and " square " or " squares ") .. S.direction(dx, dy)
    local dz = math.floor(z) - math.floor(p:getZ())
    if dz > 0 then s = s .. ", " .. dz .. " floor up" elseif dz < 0 then s = s .. ", " .. (-dz) .. " floor down" end
    return s
end

function CU.describe(drag)
    local x, y, z = drag.xJoypad, drag.yJoypad, drag.zJoypad or math.floor(getPlayer():getZ())
    local sq = drag.sq or getCell():getGridSquare(x, y, z)
    if not sq then return "No square there" end
    local p = getPlayer()
    local parts = {}
    if math.floor(p:getX()) == x and math.floor(p:getY()) == y then
        table.insert(parts, "Under you")
    else
        table.insert(parts, squaresFrom(x, y, z))
    end
    local v = valid(drag, sq)
    local a = actionWord(drag)
    if v == true then table.insert(parts, a ~= "" and ("can " .. a:lower() .. " here") or "yes")
    elseif v == false then table.insert(parts, a ~= "" and ("can't " .. a:lower() .. " here") or "can't do it here") end
    local plant = CFarmingSystem and CFarmingSystem.instance and CFarmingSystem.instance:getLuaObjectOnSquare(sq)
    local said = ""
    if plant then
        local ok, w = pcall(CU.plantWords, plant, p)
        if ok then table.insert(parts, w); said = farming_vegetableconf.getObjectName(plant) end
    else
        local f = floorWord(sq)
        if f then table.insert(parts, f) end
        local ob = obstacle(sq)
        if ob then table.insert(parts, ob) end
    end
    local t = noteText(drag)
    -- the game's note starts with the plant's name when there is one: said already
    if said ~= "" and t:sub(1, #said) == said then t = t:sub(#said + 1):gsub("^[%.%s]+", "") end
    if t ~= "" then table.insert(parts, t) end
    return table.concat(parts, ", ")
end

-- ---------- watching ----------

local function prompts(drag)
    local out = {}
    local function add(btn, fn)
        local ok, t = pcall(function() return drag[fn] and drag[fn](drag) end)
        if ok and t and t ~= "" then table.insert(out, btn .. ": " .. ZA.clean(t)) end
    end
    local a = actionWord(drag)
    table.insert(out, "Cross: " .. (a ~= "" and a:lower() or "do it here"))
    add("Triangle", "getYPrompt")
    add("L1", "getLBPrompt")
    add("R1", "getRBPrompt")
    table.insert(out, "Circle: cancel")
    return table.concat(out, ". ")
end

local last = {}
function CU.tick()
    local cell = getCell()
    local drag = cell and cell:getDrag(0)
    if drag ~= last.drag then
        last.drag, last.key = drag, nil
        if drag then
            if ZA.P and ZA.P.layer then ZA.P.layer = false end
            local what = actionWord(drag)
            if drag.craftRecipe then
                pcall(function() what = "build a " .. drag.craftRecipe:getTranslationName() end)
            else
                what = what:lower()
            end
            ZA.say("Choose a square" .. (what ~= "" and (" to " .. what) or "") ..
                ". The D-pad moves it one square: Up goes up-right, Right goes down-right, Down goes down-left, Left goes up-left. "
                .. prompts(drag))
        end
        return
    end
    if not drag or not drag.xJoypad then return end
    -- the square, and whether it can be used, as the game decides each frame (a frame after a move: wait 100 ms)
    local key = drag.xJoypad .. "," .. drag.yJoypad .. "," .. tostring(drag.zJoypad) .. "|" .. tostring(valid(drag, drag.sq)) .. "|" .. tostring(drag.tooltipTxt)
    if key ~= last.key then
        local t = getTimestampMs()
        if last.pending ~= key then last.pending, last.pendingAt = key, t; return end
        if t - last.pendingAt < 100 then return end
        local moved = not last.key or last.key:match("^[^|]*") ~= key:match("^[^|]*")
        last.key = key
        local ok, words = pcall(CU.describe, drag)
        if not ok then print("[ZA] cursor error: " .. tostring(words)); return end
        if moved then ZA.say(words) else ZA.queue(words) end
    end
end
ZA.onTick(function() CU.tick() end)
