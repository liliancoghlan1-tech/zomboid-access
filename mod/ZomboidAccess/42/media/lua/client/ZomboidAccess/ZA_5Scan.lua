-- Zomboid Access: the scanner. What is around the player, sorted into categories, nearest first.
--   Shift+PageDown / Shift+PageUp next / previous category (Ctrl works too; left Ctrl is also the game's Aim key)
--   PageDown / PageUp             next / previous thing in the category
--   Home                          say the current thing again, with a fresh distance and direction
--   Shift+Home                    zombies and animals: only what your character can see, or everything nearby
--   End                           walk there (ZA_6Walk.lua)
-- Directions are the way to push the left stick ("up-left"), since the game turns the map on its side.
-- One tile of the map is spoken as one metre.

ZA.S = ZA.S or {}
local S = ZA.S

S.radius = 20          -- tiles around the player for objects
S.mobRadius = 30       -- tiles for zombies and animals
S.maxAge = 2000        -- ms before a key press rebuilds the list
S.maxMove = 3          -- tiles moved before a key press rebuilds the list
S.seenOnly = false     -- zombies and animals: true = only those the character can see (her choice 2026-10-01: all)

S.categories = {
    { key = "you",       name = "You",                   none = "nothing to report" },
    { key = "markers",   name = "Markers",               none = "no markers yet. The You list ends with Mark this spot" },
    { key = "zombies",   name = "Zombies",               none = "no zombies" },
    { key = "animals",   name = "Animals",               none = "no animals" },
    { key = "loot_food",    name = "Loot: food and drink",    none = "no food or drink", loot = true },
    { key = "loot_weapons", name = "Loot: weapons and ammo",  none = "no weapons", loot = true },
    { key = "loot_medical", name = "Loot: medical",           none = "nothing medical", loot = true },
    { key = "loot_tools",   name = "Loot: tools and materials", none = "no tools or materials", loot = true },
    { key = "loot_clothes", name = "Loot: clothes and bags",  none = "no clothes or bags", loot = true },
    { key = "loot_books",   name = "Loot: books and papers",  none = "no books", loot = true },
    { key = "loot_other",   name = "Loot: everything else",   none = "nothing else", loot = true },
    { key = "doors",     name = "Doors",                 none = "no doors" },
    { key = "windows",   name = "Windows",               none = "no windows" },
    { key = "stairs",    name = "Stairs",                none = "no stairs" },
    { key = "containers",name = "Containers",            none = "no containers" },
    { key = "items",     name = "Things on the ground",  none = "nothing on the ground" },
    { key = "water",     name = "Water",                 none = "no water" },
    { key = "furniture", name = "Beds and seats",        none = "no beds or seats" },
    { key = "appliances",name = "Lights and appliances", none = "no lights or appliances" },
    { key = "bodies",    name = "Bodies",                none = "no bodies" },
    { key = "vehicles",  name = "Vehicles",              none = "no vehicles" },
    { key = "places",    name = "Places",                none = "no places" },
    { key = "houses",    name = "Houses",                none = "no houses" },
}
S.catIndex = 3          -- zombies first; "You" and "Markers" are to its left
S.builders = S.builders or {}   -- other files add entries that are not places (ZA_5Status: the "You" list)
S.postBuilders = S.postBuilders or {}   -- run after the squares are scanned (ZA_5ScanLoot: what's in the containers)
S.lists = {}
S.sel = {}        -- per category: key of the selected entry
S.builtAt = -1e9
S.builtX, S.builtY, S.builtZ = 0, 0, 0
S.stats = {}

-- ---------- names ----------

function S.moveableName(o)
    local spr = o:getSprite()
    if not spr then return nil end
    local props = spr:getProperties()
    if props and props:has("CustomName") then
        local n = props:get("CustomName")
        if props:has("GroupName") then n = props:get("GroupName") .. " " .. n end
        local ok, t = pcall(function() return Translator.getMoveableDisplayName(n) end)
        return (ok and t and t ~= "") and t or n
    end
    return nil
end

local function spriteName(o)
    local spr = o:getSprite()
    return spr and spr:getName() or ""
end

local function containerTitle(c)
    return getTextOrNull("IGUI_ContainerTitle_" .. c:getType()) or c:getType()
end

-- ---------- geometry ----------

local dirWords = { "right", "up-right", "up", "up-left", "left", "down-left", "down", "down-right" }

-- Screen direction from the player to a point: the way to push the stick.
function S.direction(dx, dy)
    local sx, sy = dx - dy, -(dx + dy)        -- map east goes down-right on screen, north up-right
    if math.abs(sx) < 0.01 and math.abs(sy) < 0.01 then return "" end
    local a = math.atan2(sy, sx) * 180 / math.pi
    if a < 0 then a = a + 360 end
    return dirWords[ZA.mod(math.floor((a + 22.5) / 45), 8) + 1]
end

function S.where(x, y, z)
    local p = getPlayer()
    local dx, dy = x - p:getX(), y - p:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    local dz = math.floor(z) - math.floor(p:getZ())
    local s
    if d < 1.2 then s = "right next to you"
    elseif d >= 1000 then
        s = string.format("%.1f kilometres ", d / 1000) .. S.direction(dx, dy)
    else
        local m = math.floor(d + 0.5)
        s = m .. (m == 1 and " metre " or " metres ") .. S.direction(dx, dy)
    end
    if dz == 1 then s = s .. ", 1 floor up"
    elseif dz > 1 then s = s .. ", " .. dz .. " floors up"
    elseif dz == -1 then s = s .. ", 1 floor down"
    elseif dz < -1 then s = s .. ", " .. (-dz) .. " floors down" end
    return s, d, dz
end

-- ---------- entries ----------
-- An entry: { key, cat, name = function or string, x, y, z (target point), obj, alive = function, walk = kind }

local function entryPos(e)
    if e.pos then
        local ok, x, y, z = pcall(e.pos, e)
        if ok and x then return x, y, z end
    end
    return e.x, e.y, e.z
end
S.entryPos = entryPos

local function entryName(e)
    if type(e.name) == "function" then
        local ok, n = pcall(e.name, e)
        return ok and n or e.baseName or "something"
    end
    return e.name
end
S.entryName = entryName

local function alive(e)
    if not e.alive then return true end
    local ok, r = pcall(e.alive, e)
    return ok and r
end
S.alive = alive

-- ---------- building the lists ----------

local function newLists()
    local l = {}
    for _, c in ipairs(S.categories) do l[c.key] = {} end
    return l
end

-- Objects that span several tiles (double beds, baths, garage doors) are listed once.
local function addMerged(lists, cat, e)
    for _, o in ipairs(lists[cat]) do
        if o.baseName == e.baseName and o.z == e.z and math.abs(o.x - e.x) <= 1.01 and math.abs(o.y - e.y) <= 1.01 then
            return
        end
    end
    table.insert(lists[cat], e)
end

local function staticAlive(e)
    return e.obj:getSquare() ~= nil and e.obj:getObjectIndex() >= 0
end

local function objKey(o, x, y, z)
    return x .. "," .. y .. "," .. z .. ":" .. spriteName(o) .. ":" .. tostring(o:getObjectIndex())
end

local function doorName(e)
    local o = e.obj
    local n = e.baseName
    local open = false
    pcall(function() open = o:IsOpen() end)
    n = n .. (open and ", open" or ", closed")
    local barr = false
    pcall(function() barr = o:isBarricaded() end)
    if barr then n = n .. ", barricaded" end
    return n
end

local function windowName(e)
    local o = e.obj
    local n = e.baseName
    local smashed, open, barr = false, false, false
    pcall(function() smashed = o:isSmashed() end)
    pcall(function() open = o:IsOpen() end)
    pcall(function() barr = o:isBarricaded() end)
    if smashed then n = n .. ", broken" elseif open then n = n .. ", open" else n = n .. ", closed" end
    if barr then n = n .. ", barricaded" end
    return n
end

local function switchName(e)
    local on = false
    pcall(function() on = e.obj:isActivated() end)
    return e.baseName .. (on and ", on" or ", off")
end

local function waterName(e)
    local amt = 1
    pcall(function() amt = e.obj:getFluidAmount() end)
    return e.baseName .. ((amt and amt <= 0) and ", empty" or "")
end

local function addObject(lists, o, sq, x, y, z, pz)
    local base = { obj = o, x = x + 0.5, y = y + 0.5, z = z, alive = staticAlive }
    local function make(cat, name, nameFn, walk)
        local e = {}
        for k, v in pairs(base) do e[k] = v end
        e.cat, e.baseName, e.name, e.walk = cat, name, nameFn or name, walk or "adjacent"
        e.key = cat .. "|" .. objKey(o, x, y, z)
        return e
    end

    -- stairs: going up from this floor, going down from the floor below
    local t = o:getType()
    if t == IsoObjectType.stairsBN or t == IsoObjectType.stairsBW then
        if z == pz then
            local e = make("stairs", "Stairs going up", nil, "stairsUp")
            e.north = (t == IsoObjectType.stairsBN)
            table.insert(lists.stairs, e)
        end
        return
    elseif t == IsoObjectType.stairsTN or t == IsoObjectType.stairsTW then
        if z == pz - 1 then
            local e = make("stairs", "Stairs going down", nil, "stairsDown")
            -- the top step is on the floor below; you step onto it from this floor
            e.north = (t == IsoObjectType.stairsTN)
            e.tx, e.ty, e.tz = x, y, z
            if e.north then e.ly = y - 1; e.lx = x else e.lx = x - 1; e.ly = y end
            e.x, e.y, e.z = e.lx + 0.5, e.ly + 0.5, z + 1
            table.insert(lists.stairs, e)
        end
        return
    elseif t == IsoObjectType.stairsMN or t == IsoObjectType.stairsMW then
        return
    end

    if instanceof(o, "IsoDoor") or (instanceof(o, "IsoThumpable") and o:isDoor()) then
        local n = S.moveableName(o)
        if not n then n = spriteName(o):find("garage") and "Garage door" or "Door" end
        addMerged(lists, "doors", make("doors", n, doorName, "door"))
        return
    end
    if instanceof(o, "IsoWindow") then
        addMerged(lists, "windows", make("windows", S.moveableName(o) or "Window", windowName, "door"))
        return
    end
    if instanceof(o, "IsoCurtain") or instanceof(o, "IsoWindowFrame") then return end

    local nc = o:getContainerCount()
    if nc and nc > 0 then
        for i = 0, nc - 1 do
            local c = o:getContainerByIndex(i)
            local title = c:getCustomName() or containerTitle(c)
            local mn = S.moveableName(o)
            local n = title
            if mn and mn ~= "" then
                n = mn
                if not mn:lower():find(title:lower(), 1, true) then n = mn .. ", " .. title:lower() end
            end
            local e = make("containers", n, nil, "container")
            e.key = e.key .. "#" .. i
            e.container = c
            table.insert(lists.containers, e)
        end
        return
    end

    local ok, fluid = pcall(function() return o:hasFluid() end)
    if ok and fluid then
        local n = S.moveableName(o)
        if not n then
            local ok2, fn = pcall(function() return o:getFluidUiName() end)
            n = (ok2 and fn and fn ~= "") and fn or "Water"
        end
        addMerged(lists, "water", make("water", n, waterName))
        return
    end

    if instanceof(o, "IsoLightSwitch") then
        addMerged(lists, "appliances", make("appliances", S.moveableName(o) or "Light switch", switchName))
        return
    end
    if instanceof(o, "IsoGenerator") then
        addMerged(lists, "appliances", make("appliances", "Generator", function(e)
            local on = false; pcall(function() on = e.obj:isActivated() end)
            return "Generator" .. (on and ", running" or ", off")
        end))
        return
    end
    if instanceof(o, "IsoClothingWasher") or instanceof(o, "IsoClothingDryer") or instanceof(o, "IsoCombinationWasherDryer")
        or instanceof(o, "IsoWaveSignal") then
        local n = S.moveableName(o) or (instanceof(o, "IsoWaveSignal") and "Radio or TV" or "Washing machine")
        addMerged(lists, "appliances", make("appliances", n))
        return
    end

    local spr = o:getSprite()
    local props = spr and spr:getProperties()
    if props then
        if props:has("fuelAmount") then
            addMerged(lists, "appliances", make("appliances", S.moveableName(o) or "Petrol pump"))
            return
        end
        if props:has(IsoFlagType.bed) then
            local n = S.moveableName(o)
            if n then addMerged(lists, "furniture", make("furniture", n)) end
            return
        end
    end
end

local function addSquare(lists, cell, sq, x, y, z, pz, water)
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local o = objs:get(i)
        local ok, err = pcall(addObject, lists, o, sq, x, y, z, pz)
        if not ok then S.stats.errors = (S.stats.errors or 0) + 1; S.stats.lastError = tostring(err) end
    end

    if z == pz then
        -- things on the ground: one entry per kind of thing per tile ("Nails, 5 of them")
        local w = sq:getWorldObjects()
        if w:size() > 0 then
            local byName, order = {}, {}
            for i = 0, w:size() - 1 do
                local wo = w:get(i)
                local item = wo:getItem()
                if item then
                    local n = item:getDisplayName()
                    if not byName[n] then byName[n] = { obj = wo, count = 0 }; table.insert(order, n) end
                    byName[n].count = byName[n].count + 1
                end
            end
            for _, n in ipairs(order) do
                local b = byName[n]
                table.insert(lists.items, {
                    cat = "items", key = "items|" .. x .. "," .. y .. "," .. z .. ":" .. n,
                    baseName = n, name = b.count > 1 and (n .. ", " .. b.count .. " of them") or n,
                    obj = b.obj, x = x + 0.5, y = y + 0.5, z = z, walk = "onto",
                    alive = function(e) return e.obj:getSquare() ~= nil end,
                })
            end
        end

        -- bodies
        local sm = sq:getStaticMovingObjects()
        for i = 0, sm:size() - 1 do
            local b = sm:get(i)
            if instanceof(b, "IsoDeadBody") then
                local n = "Dead body"
                pcall(function()
                    if b:isAnimal() then n = "Dead animal" elseif b:isZombie() then n = "Dead zombie" end
                end)
                table.insert(lists.bodies, {
                    cat = "bodies", key = "bodies|" .. x .. "," .. y .. "," .. z .. ":" .. i, baseName = n, name = n,
                    obj = b, x = x + 0.5, y = y + 0.5, z = z, walk = "adjacent",
                    alive = function(e) return e.obj:getSquare() ~= nil end,
                })
            end
        end

        -- vehicles: one per vehicle, wherever it is parked
        local v = sq:getVehicleContainer()
        if v and not S.seenVehicles[v] then
            S.seenVehicles[v] = true
            local n = "Vehicle"
            pcall(function()
                local sc = v:getScript()
                local model = sc:getCarModelName() or sc:getName()
                n = getTextOrNull("IGUI_VehicleName" .. model) or getTextOrNull("IGUI_VehicleName" .. sc:getName()) or n
            end)
            table.insert(lists.vehicles, {
                cat = "vehicles", key = "vehicles|" .. tostring(v:getId()), baseName = n, name = n,
                obj = v, x = v:getX(), y = v:getY(), z = v:getZ(), walk = "vehicle",
                pos = function(e) return e.obj:getX(), e.obj:getY(), e.obj:getZ() end,
                alive = function(e) return e.obj:getSquare() ~= nil end,
            })
        end

        -- open water (lakes, rivers): the nearest tile only
        local fl = sq:getFloor()
        local spr = fl and fl:getSprite()
        if spr and spr:getProperties() and spr:getProperties():has(IsoFlagType.water) then
            local p = getPlayer()
            local d = (x + 0.5 - p:getX()) ^ 2 + (y + 0.5 - p:getY()) ^ 2
            if not water.best or d < water.best then
                water.best = d
                water.entry = {
                    cat = "water", key = "water|open", baseName = "Open water", name = "Open water, a lake or river",
                    obj = fl, x = x + 0.5, y = y + 0.5, z = z, walk = "adjacent",
                }
            end
        end
    end
end

local function zombieName(e)
    local z = e.obj
    local n = "Zombie"
    pcall(function()
        if z:isCrawling() then n = "Crawling zombie"
        elseif z:isOnFloor() then n = "Zombie on the ground" end
    end)
    pcall(function() if z:getTarget() == getPlayer() then n = n .. ", coming for you" end end)
    if not S.canSeeMob(z) then n = n .. ", out of sight" end
    return n
end

local function canSee(mob)
    local sq = mob:getCurrentSquare()
    if not sq then return false end
    local ok, r = pcall(function() return sq:isCanSee(0) end)
    return ok and r
end

S.canSeeMob = canSee

local function addMobs(lists, cell, p)
    local px, py, pz = p:getX(), p:getY(), p:getZ()
    local zl = cell:getZombieList()
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.abs(z:getZ() - pz) < 3 then
            local d = math.sqrt((z:getX() - px) ^ 2 + (z:getY() - py) ^ 2)
            if d <= S.mobRadius and (not S.seenOnly or canSee(z)) then
                table.insert(lists.zombies, {
                    cat = "zombies", key = "zombies|" .. tostring(z:getID()), baseName = "Zombie", name = zombieName,
                    obj = z, x = z:getX(), y = z:getY(), z = z:getZ(), walk = "mob",
                    pos = function(e) return e.obj:getX(), e.obj:getY(), e.obj:getZ() end,
                    alive = function(e) return not e.obj:isDead() and e.obj:getCurrentSquare() ~= nil end,
                })
            end
        end
    end
end

local function addAnimalsOn(lists, sq)
    local mo = sq:getMovingObjects()
    for i = 0, mo:size() - 1 do
        local a = mo:get(i)
        if instanceof(a, "IsoAnimal") and not S.seenAnimals[a] then
            S.seenAnimals[a] = true
            local dead = false
            pcall(function() dead = a:isDead() end)
            if not dead and (not S.seenOnly or canSee(a)) then
                local id = tostring(a)
                pcall(function() id = tostring(a:getAnimalID()) end)
                table.insert(lists.animals, {
                    cat = "animals", key = "animals|" .. id, baseName = "Animal",
                    name = function(e)
                        local n = "Animal"
                        pcall(function() n = e.obj:getFullName() end)
                        if not S.canSeeMob(e.obj) then n = n .. ", out of sight" end
                        return n
                    end,
                    obj = a, x = a:getX(), y = a:getY(), z = a:getZ(), walk = "mob",
                    pos = function(e) return e.obj:getX(), e.obj:getY(), e.obj:getZ() end,
                    alive = function(e) return not e.obj:isDead() and e.obj:getCurrentSquare() ~= nil end,
                })
            end
        end
    end
end

-- The nearest zombie close to the player: one the character can see within `seen` metres, or any within
-- `near` metres (close enough to hear). Used to interrupt walking and guiding.
function S.nearestThreat(seen, near)
    local p = getPlayer()
    local px, py, pz = p:getX(), p:getY(), math.floor(p:getZ())
    local zl = getCell():getZombieList()
    local best, bd
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.floor(z:getZ()) == pz then
            local d = math.sqrt((z:getX() - px) ^ 2 + (z:getY() - py) ^ 2)
            if d <= near or (d <= seen and canSee(z)) then
                if not bd or d < bd then best, bd = z, d end
            end
        end
    end
    return best, bd
end

function S.threatText(z)
    local e = { obj = z }
    local n = zombieName(e)
    return n .. ", " .. S.where(z:getX(), z:getY(), z:getZ())
end

function S.build()
    local p = getPlayer()
    if not p then return end
    local cell = getCell()
    local t0 = getTimestampMs()
    local lists = newLists()
    S.stats = {}
    S.seenVehicles, S.seenAnimals = {}, {}
    local water = {}
    for _, f in ipairs(S.builders) do
        local ok, err = pcall(f, lists)
        if not ok then S.stats.lastError = tostring(err) end
    end
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local r = S.radius
    local nsq = 0
    for z = pz - 1, pz + 1 do
        if z >= -32 then
            for x = px - r, px + r do
                for y = py - r, py + r do
                    local sq = cell:getGridSquare(x, y, z)
                    if sq then
                        nsq = nsq + 1
                        addSquare(lists, cell, sq, x, y, z, pz, water)
                    end
                end
            end
        end
    end
    -- animals roam further than the object radius
    local mr = S.mobRadius
    for x = px - mr, px + mr do
        for y = py - mr, py + mr do
            local sq = cell:getGridSquare(x, y, pz)
            if sq then
                local ok, err = pcall(addAnimalsOn, lists, sq)
                if not ok then S.stats.lastError = tostring(err) end
            end
        end
    end
    if water.entry then table.insert(lists.water, water.entry) end
    for _, f in ipairs(S.postBuilders) do
        local ok, err = pcall(f, lists)
        if not ok then S.stats.lastError = tostring(err) end
    end
    local ok, err = pcall(addMobs, lists, cell, p)
    if not ok then S.stats.lastError = tostring(err) end

    S.lists = lists
    S.sort()
    S.builtAt = getTimestampMs()
    S.builtX, S.builtY, S.builtZ = p:getX(), p:getY(), p:getZ()
    S.stats.squares = nsq
    S.stats.ms = S.builtAt - t0
    local counts = {}
    for _, c in ipairs(S.categories) do table.insert(counts, c.key .. "=" .. #lists[c.key]) end
    print("[ZA] scan: " .. nsq .. " squares in " .. S.stats.ms .. " ms; " .. table.concat(counts, " ")
        .. (S.stats.lastError and (" ERROR " .. S.stats.lastError) or ""))
end

-- Same floor first, then nearest.
-- Same floor first, then the same side of the walls (inside this building, or outdoors), then nearest:
-- a toilet 5 metres away through a wall is further than it sounds.
function S.sort()
    local p = getPlayer()
    local pz = math.floor(p:getZ())
    local psq = p:getCurrentSquare()
    local myBuilding = psq and psq:getBuilding() or nil
    for _, list in pairs(S.lists) do
        for _, e in ipairs(list) do
            if e.noWhere then e.x, e.y, e.z = p:getX(), p:getY(), p:getZ() end
            local x, y, z = entryPos(e)
            e.d = math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2)
            e.floorGap = math.abs(math.floor(z) - pz)
            e.sideGap = 0
            if not e.far and not e.noWhere then
                local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
                if sq and sq:getBuilding() ~= myBuilding then e.sideGap = 1 end
            end
        end
        table.sort(list, function(a, b)
            if a.order or b.order then return (a.order or 0) < (b.order or 0) end
            if a.floorGap ~= b.floorGap then return a.floorGap < b.floorGap end
            if a.sideGap ~= b.sideGap then return a.sideGap < b.sideGap end
            return a.d < b.d
        end)
    end
end

function S.refreshIfStale()
    local p = getPlayer()
    local now = getTimestampMs()
    local age = now - S.builtAt
    local moved = math.abs(p:getX() - S.builtX) + math.abs(p:getY() - S.builtY)
    if age < 0 or age > S.maxAge or moved >= S.maxMove or math.floor(p:getZ()) ~= math.floor(S.builtZ) then
        S.build()
    end
end

-- ---------- selection ----------

local function cat() return S.categories[S.catIndex] end

-- Index of the selected entry in the current list (found again by its key after a rebuild).
local function selIndex()
    local c = cat()
    local list = S.lists[c.key] or {}
    local key = S.sel[c.key]
    if key then
        for i, e in ipairs(list) do if e.key == key then return i end end
    end
    return nil
end

function S.current()
    local c = cat()
    local i = selIndex()
    return i and S.lists[c.key][i] or nil
end

-- Room words: the game's room ids are joined-up English ("livingroom", "kidsbedroom").
local roomWords = {
    livingroom = "living room", diningroom = "dining room", kidsbedroom = "children's bedroom",
    laundry = "laundry room", hall = "hallway", storageunit = "storage unit", grocerystorage = "grocery store room",
    garagestorage = "garage", closet = "closet", toolstore = "tool store", gasstore = "petrol station shop",
}
function S.roomName(room)
    local r = room and room:getName()
    if not r or r == "" then return nil end
    if roomWords[r] then return roomWords[r] end
    local pre = r:match("^(%a+)room$")
    if pre and #pre > 4 and pre ~= "class" and pre ~= "store" and pre ~= "break" then return pre .. " room" end
    return r
end

-- "in the kitchen" when the thing is in another room than the player, "outside" when the player is indoors.
function S.roomPart(x, y, z)
    local p = getPlayer()
    local psq = p:getCurrentSquare()
    local sq = getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z))
    if not psq or not sq then return "" end
    local pr, r = psq:getRoom(), sq:getRoom()
    if r and pr and r == pr then return "" end
    if r then
        local n = S.roomName(r)
        local inside = pr == nil and "inside, " or ""
        if pr and psq:getBuilding() ~= sq:getBuilding() then inside = "in another building, " end
        if n then return ", " .. inside .. "in the " .. n end
        return inside ~= "" and (", " .. inside:gsub(", $", "")) or ""
    end
    if pr then return ", outside" end
    return ""
end

function S.describe(e, i, n)
    if e.noWhere then return (entryName(e):gsub("[%.%s]+$", "")) .. (i and ZA.pos(i, n) or "") end
    local x, y, z = entryPos(e)
    local w = S.where(x, y, z)
    local room = ""
    if not e.far then pcall(function() room = S.roomPart(x, y, z) end) end
    return entryName(e) .. ", " .. w .. room .. (i and ZA.pos(i, n) or "")
end

local function speakEntry(i)
    local c = cat()
    local list = S.lists[c.key]
    local e = list[i]
    S.sel[c.key] = e.key
    local text = S.describe(e, i, #list)
    print("[ZA] scan say: " .. e.key)
    ZA.say(text)
end

local function noneText(c)
    if c.loot then return c.none .. " in the containers around you" end
    if c.key == "markers" then return c.none end
    if (c.key == "zombies" or c.key == "animals") and S.seenOnly then
        return c.none .. " that you can see"
    end
    if c.key == "zombies" or c.key == "animals" then return c.none .. " within " .. S.mobRadius .. " metres" end
    return c.none .. " within " .. S.radius .. " metres"
end

function S.step(delta)
    S.refreshIfStale()
    local c = cat()
    local list = S.lists[c.key]
    if #list == 0 then ZA.say(c.name .. ": " .. noneText(c)); return end
    local i = selIndex()
    if not i then i = delta > 0 and 1 or #list
    else
        -- drop entries that have gone (a zombie killed, a door taken off)
        i = i + delta
        if i > #list then i = 1 elseif i < 1 then i = #list end
    end
    local tries = 0
    while not alive(list[i]) and tries < #list do
        i = i + (delta >= 0 and 1 or -1)
        if i > #list then i = 1 elseif i < 1 then i = #list end
        tries = tries + 1
    end
    speakEntry(i)
end

function S.switchCategory(delta)
    S.refreshIfStale()
    local n = #S.categories
    -- (Kahlua's % keeps the sign of a negative number, so wrap by hand)
    local i = S.catIndex + delta
    while i < 1 do i = i + n end
    while i > n do i = i - n end
    S.catIndex = i
    local c = cat()
    local list = S.lists[c.key]
    if #list == 0 then ZA.say(c.name .. ": " .. noneText(c)); return end
    -- a new category starts at its nearest thing
    S.sel[c.key] = list[1].key
    local e = list[1]
    local text = c.name .. ", " .. #list .. ". " .. S.describe(e, 1, #list)
    print("[ZA] scan say: " .. e.key)
    ZA.say(text)
end

function S.repeatCurrent()
    local c = cat()
    local e = S.current()
    if not e then
        S.refreshIfStale()
        e = S.current()
    end
    if not e then
        local list = S.lists[c.key] or {}
        if #list == 0 then ZA.say(c.name .. ": " .. noneText(c)) else S.step(1) end
        return
    end
    if not alive(e) then
        ZA.say(entryName(e) .. " is gone.")
        S.sel[c.key] = nil
        S.build()
        return
    end
    -- fresh distance, and its place in the fresh order
    S.sort()
    local i = selIndex()
    speakEntry(i)
end

function S.toggleSeen()
    S.seenOnly = not S.seenOnly
    S.builtAt = -1e9
    ZA.say(S.seenOnly and "Zombies and animals: only the ones your character can see."
        or "Zombies and animals: everything nearby, seen or not.")
end

-- A debug dump of the whole scan to console.txt (through the test channel: ZA.S.dump()).
function S.dump()
    S.build()
    for _, c in ipairs(S.categories) do
        for i, e in ipairs(S.lists[c.key]) do
            local x, y, z = entryPos(e)
            print(string.format("[ZA] dump %s %d %s | %s | %.1f,%.1f,%d", c.key, i, e.key, S.describe(e), x, y, z))
        end
    end
    return "dumped"
end

-- ---------- keys ----------

function S.inWorld()
    local p = getPlayer()
    if not p or p:isDead() then return false end
    if MainScreen and MainScreen.instance and MainScreen.instance:isVisible() then return false end
    return true
end

function S.onKey(key)
    if not S.inWorld() then return end
    local mod = isCtrlKeyDown() or isShiftKeyDown()
    local ok, err = pcall(function()
        if key == Keyboard.KEY_NEXT then
            if mod then S.switchCategory(1) else S.step(1) end
        elseif key == Keyboard.KEY_PRIOR then
            if mod then S.switchCategory(-1) else S.step(-1) end
        elseif key == Keyboard.KEY_HOME then
            if mod then S.toggleSeen() else S.repeatCurrent() end
        end
    end)
    if not ok then print("[ZA] scan key error: " .. tostring(err)) end
end
-- Registered once, so reloading this file in a running game does not answer every key twice.
if not S.hooked then
    S.hooked = true
    Events.OnKeyPressed.Add(function(key) S.onKey(key) end)
end

-- A new world or a load: nothing from the old place may stay selected.
Events.OnGameStart.Add(function()
    S.lists, S.sel, S.builtAt = newLists(), {}, -1e9
end)
