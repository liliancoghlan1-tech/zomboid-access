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
    { key = "you", name = ZA.tr("Scan_CatYou"), none = ZA.tr("Scan_NoneYou") },
    { key = "markers", name = ZA.tr("Scan_CatMarkers"), none = ZA.tr("Scan_NoneMarkers") },
    { key = "zombies", name = ZA.tr("Scan_CatZombies"), none = ZA.tr("Scan_NoneZombies") },
    { key = "animals", name = ZA.tr("Scan_CatAnimals"), none = ZA.tr("Scan_NoneAnimals") },
    { key = "loot_food", name = ZA.tr("Scan_CatLootFood"), none = ZA.tr("Scan_NoneLootFood"), loot = true },
    { key = "loot_weapons", name = ZA.tr("Scan_CatLootWeapons"), none = ZA.tr("Scan_NoneLootWeapons"), loot = true },
    { key = "loot_medical", name = ZA.tr("Scan_CatLootMedical"), none = ZA.tr("Scan_NoneLootMedical"), loot = true },
    { key = "loot_tools", name = ZA.tr("Scan_CatLootTools"), none = ZA.tr("Scan_NoneLootTools"), loot = true },
    { key = "loot_clothes", name = ZA.tr("Scan_CatLootClothes"), none = ZA.tr("Scan_NoneLootClothes"), loot = true },
    { key = "loot_books", name = ZA.tr("Scan_CatLootBooks"), none = ZA.tr("Scan_NoneLootBooks"), loot = true },
    { key = "loot_other", name = ZA.tr("Scan_CatLootOther"), none = ZA.tr("Scan_NoneLootOther"), loot = true },
    { key = "doors", name = ZA.tr("Scan_CatDoors"), none = ZA.tr("Scan_NoneDoors") },
    { key = "windows", name = ZA.tr("Scan_CatWindows"), none = ZA.tr("Scan_NoneWindows") },
    { key = "stairs", name = ZA.tr("Scan_CatStairs"), none = ZA.tr("Scan_NoneStairs") },
    { key = "containers", name = ZA.tr("Scan_CatContainers"), none = ZA.tr("Scan_NoneContainers") },
    { key = "items", name = ZA.tr("Scan_CatItems"), none = ZA.tr("Scan_NoneItems") },
    { key = "water", name = ZA.tr("Scan_CatWater"), none = ZA.tr("Scan_NoneWater") },
    { key = "furniture", name = ZA.tr("Scan_CatFurniture"), none = ZA.tr("Scan_NoneFurniture") },
    { key = "appliances", name = ZA.tr("Scan_CatAppliances"), none = ZA.tr("Scan_NoneAppliances") },
    { key = "bodies", name = ZA.tr("Scan_CatBodies"), none = ZA.tr("Scan_NoneBodies") },
    { key = "vehicles", name = ZA.tr("Scan_CatVehicles"), none = ZA.tr("Scan_NoneVehicles") },
    { key = "places", name = ZA.tr("Scan_CatPlaces"), none = ZA.tr("Scan_NonePlaces") },
    { key = "houses", name = ZA.tr("Scan_CatHouses"), none = ZA.tr("Scan_NoneHouses") },
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
        local custom = props:get("CustomName")
        local group = props:has("GroupName") and props:get("GroupName") or nil
        local n = group and (group .. " " .. custom) or custom
        local function moveable(s)
            local ok, t = pcall(function() return Translator.getMoveableDisplayName(s) end)
            return (ok and t and t ~= "") and t or s
        end
        local t = moveable(n)
        if t ~= n or not group then return t end
        -- The game has no words for every group + name: "White Window Door" (fixtures_doors_01_47, in game
        -- 2026-10-19) stays in English in French. When the name alone has words in this language (Door: Porte),
        -- use those rather than English; in English both are the same and the full name is kept.
        local alone = moveable(custom)
        if alone == custom then return n end
        if custom == "Door" and group:find("Window", 1, true) then return ZA.tr("Scan_DoorWindow") end
        return alone
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

local dirKeys = { "Scan_DirRight", "Scan_DirUpRight", "Scan_DirUp", "Scan_DirUpLeft", "Scan_DirLeft", "Scan_DirDownLeft", "Scan_DirDown", "Scan_DirDownRight" }

-- Screen direction from the player to a point: the way to push the stick.
function S.direction(dx, dy)
    local sx, sy = dx - dy, -(dx + dy)        -- map east goes down-right on screen, north up-right
    if math.abs(sx) < 0.01 and math.abs(sy) < 0.01 then return "" end
    local a = math.atan2(sy, sx) * 180 / math.pi
    if a < 0 then a = a + 360 end
    return ZA.tr(dirKeys[ZA.mod(math.floor((a + 22.5) / 45), 8) + 1])
end

-- noFloor: far places, houses and towns, which only know the ground: no "1 floor down" when you're upstairs.
function S.where(x, y, z, noFloor)
    local p = getPlayer()
    local dx, dy = x - p:getX(), y - p:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    local dz = noFloor and 0 or (math.floor(z) - math.floor(p:getZ()))
    local s
    if d < 1.2 then s = ZA.tr("Scan_NextToYou")
    elseif d >= 1000 then
        s = ZA.tr("Scan_Km", ZA.dec(d / 1000, "%.1f"), S.direction(dx, dy))
    else
        local m = math.floor(d + 0.5)
        s = ZA.tr(m == 1 and "Scan_MetreOne" or "Scan_MetresMany", m, S.direction(dx, dy))
    end
    if dz == 1 then s = s .. ", " .. ZA.tr("Scan_FloorUpOne")
    elseif dz > 1 then s = s .. ", " .. ZA.tr("Scan_FloorsUp", dz)
    elseif dz == -1 then s = s .. ", " .. ZA.tr("Scan_FloorDownOne")
    elseif dz < -1 then s = s .. ", " .. ZA.tr("Scan_FloorsDown", -dz) end
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
        return ok and n or e.baseName or ZA.tr("Scan_Something")
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
-- Two halves of one thing (a double door, a wide window) side by side in the same wall: facing the same way, and
-- next to each other along that wall, not across it. Without this a house's locked front door was merged into the
-- bathroom door just inside it, diagonally next to it, and never listed (in game 2026-10-20).
local function sameWall(a, b)
    -- (only wall pieces have getNorth: asking anything else throws, and the game logs every throw)
    local function wallPiece(o) return instanceof(o, "IsoDoor") or instanceof(o, "IsoWindow") or instanceof(o, "IsoThumpable") end
    if not (wallPiece(a) and wallPiece(b)) then return true end   -- anything next to it is the same thing
    local na, nb = a:getNorth(), b:getNorth()
    if na ~= nb then return false end
    local ax, ay, bx, by = a:getX(), a:getY(), b:getX(), b:getY()
    if na then return ay == by else return ax == bx end
end

local function addMerged(lists, cat, e)
    for _, o in ipairs(lists[cat]) do
        if o.baseName == e.baseName and o.z == e.z and math.abs(o.x - e.x) <= 1.01 and math.abs(o.y - e.y) <= 1.01
            and (not (o.obj and e.obj) or sameWall(o.obj, e.obj)) then
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

-- Curtains (or a sheet hung up): what hides you and your light from outside. Read as the game does (ISZoneDisplay).
-- Nothing said when there are none (Marc, 2026-10-19: "no curtains" told him nothing).
local function curtainWords(o)
    local curtains = nil
    pcall(function() curtains = o:HasCurtains() end)
    if not curtains then return nil end
    local cOpen = false
    pcall(function() cOpen = curtains:IsOpen() end)
    return ZA.tr(cOpen and "Scan_CurtainsOpen" or "Scan_CurtainsClosed")
end

-- A door you can see through (glass, not a garage door), which can take curtains like a window.
local function glassDoor(o)
    local glass = false
    pcall(function()
        local props = o:getProperties()
        glass = props ~= nil and props:has("doorTrans") and not props:has("GarageDoor")
    end)
    return glass
end

-- A door or window is on both its sides: the square on its other side (a north one sits between y and y - 1,
-- a west one between x - 1 and x), or nil when it is not a passage.
local function passageOtherSide(o, sq)
    if not o or not sq then return nil end
    local passage = instanceof(o, "IsoDoor") or instanceof(o, "IsoWindow")
    if not passage and instanceof(o, "IsoThumpable") then
        pcall(function() passage = o:isDoor() or o:isWindow() end)
    end
    if not passage then return nil end
    local north = false
    pcall(function() north = o:getNorth() end)
    if north then return getCell():getGridSquare(sq:getX(), sq:getY() - 1, sq:getZ()) end
    return getCell():getGridSquare(sq:getX() - 1, sq:getY(), sq:getZ())
end

local function doorName(e)
    local o = e.obj
    local n = e.baseName
    local open = false
    pcall(function() open = o:IsOpen() end)
    n = n .. ", " .. (open and ZA.tr("Scan_Open") or ZA.tr("Scan_Closed"))
    local barr = false
    pcall(function() barr = o:isBarricaded() end)
    if barr then n = n .. ", " .. ZA.tr("Scan_Barricaded") end
    -- a door between a building and the outside (Marc, 2026-10-19): the game's own test (IsoDoor:isExterior), or a
    -- building on one side only; isExterior misses some (in game 2026-10-22, a hall door to the garden said nothing)
    local outside = false
    if instanceof(o, "IsoDoor") then pcall(function() outside = o:isExterior() end) end
    if not outside then
        pcall(function()
            local sq = o:getSquare()
            local other = passageOtherSide(o, sq)
            if other then outside = (sq:getBuilding() == nil) ~= (other:getBuilding() == nil) end
        end)
    end
    if outside then n = n .. ", " .. ZA.tr("Scan_DoorOutside") end
    if instanceof(o, "IsoDoor") then
        local c = glassDoor(o) and curtainWords(o)
        if c then n = n .. ", " .. c end
    end
    return n
end

local function windowName(e)
    local o = e.obj
    local n = e.baseName
    local smashed, open, barr = false, false, false
    pcall(function() smashed = o:isSmashed() end)
    pcall(function() open = o:IsOpen() end)
    pcall(function() barr = o:isBarricaded() end)
    if smashed then n = n .. ", " .. ZA.tr("Scan_Broken")
    elseif open then n = n .. ", " .. ZA.tr("Scan_Open")
    else n = n .. ", " .. ZA.tr("Scan_Closed") end
    if barr then n = n .. ", " .. ZA.tr("Scan_Barricaded") end
    local c = curtainWords(o)
    if c then n = n .. ", " .. c end
    -- which storey it is on, counted from the ground (Marc, 2026-10-19): nothing on the ground floor
    local level = 0
    pcall(function() level = math.floor(o:getZ()) end)
    if level < 0 then n = n .. ", " .. ZA.tr("Scan_LevelBasement")
    elseif level >= 1 and level <= 3 then n = n .. ", " .. ZA.tr("Scan_Level" .. level)
    elseif level > 3 then n = n .. ", " .. ZA.tr("Scan_LevelN", level) end
    return n
end

local function switchName(e)
    local on = false
    pcall(function() on = e.obj:isActivated() end)
    return e.baseName .. ", " .. (on and ZA.tr("Scan_LightOn") or ZA.tr("Scan_LightOff"))
end

local function waterName(e)
    local amt = 1
    pcall(function() amt = e.obj:getFluidAmount() end)
    return e.baseName .. ((amt and amt <= 0) and (", " .. ZA.tr("Scan_Empty")) or "")
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
            local e = make("stairs", ZA.tr("Scan_StairsUp"), nil, "stairsUp")
            e.north = (t == IsoObjectType.stairsBN)
            table.insert(lists.stairs, e)
        end
        return
    elseif t == IsoObjectType.stairsTN or t == IsoObjectType.stairsTW then
        if z == pz - 1 then
            local e = make("stairs", ZA.tr("Scan_StairsDown"), nil, "stairsDown")
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
        if not n then n = spriteName(o):find("garage") and ZA.tr("Scan_DoorGarage") or ZA.tr("Scan_Door") end
        addMerged(lists, "doors", make("doors", n, doorName, "door"))
        return
    end
    if instanceof(o, "IsoWindow") then
        addMerged(lists, "windows", make("windows", S.moveableName(o) or ZA.tr("Scan_Window"), windowName, "door"))
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
            n = (ok2 and fn and fn ~= "") and fn or ZA.tr("Scan_Water")
        end
        addMerged(lists, "water", make("water", n, waterName))
        return
    end

    if instanceof(o, "IsoLightSwitch") then
        addMerged(lists, "appliances", make("appliances", S.moveableName(o) or ZA.tr("Scan_LightSwitch"), switchName))
        return
    end
    if instanceof(o, "IsoGenerator") then
        addMerged(lists, "appliances", make("appliances", ZA.tr("Scan_Generator"), function(e)
            local on = false; pcall(function() on = e.obj:isActivated() end)
            return e.baseName .. ", " .. (on and ZA.tr("Scan_GenOn") or ZA.tr("Scan_GenOff"))
        end))
        return
    end
    if instanceof(o, "IsoClothingWasher") or instanceof(o, "IsoClothingDryer") or instanceof(o, "IsoCombinationWasherDryer")
        or instanceof(o, "IsoWaveSignal") then
        local n = S.moveableName(o) or (instanceof(o, "IsoWaveSignal") and ZA.tr("Scan_RadioTv") or ZA.tr("Scan_WashingMachine"))
        addMerged(lists, "appliances", make("appliances", n))
        return
    end

    local spr = o:getSprite()
    local props = spr and spr:getProperties()
    if props then
        if props:has("fuelAmount") then
            addMerged(lists, "appliances", make("appliances", S.moveableName(o) or ZA.tr("Scan_PetrolPump")))
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
                    baseName = n, name = b.count > 1 and ZA.tr("Scan_ItemCount", n, b.count) or n,
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
                local n = ZA.tr("Scan_DeadBody")
                pcall(function()
                    if b:isAnimal() then n = ZA.tr("Scan_DeadAnimal") elseif b:isZombie() then n = ZA.tr("Scan_DeadZombie") end
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
            local n = ZA.tr("Scan_Vehicle")
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
                    cat = "water", key = "water|open", baseName = ZA.tr("Scan_OpenWater"), name = ZA.tr("Scan_OpenWaterLong"),
                    obj = fl, x = x + 0.5, y = y + 0.5, z = z, walk = "adjacent",
                }
            end
        end
    end
end

local function zombieName(e)
    local z = e.obj
    local n = ZA.tr("Scan_Zombie")
    pcall(function()
        if z:isCrawling() then n = ZA.tr("Scan_ZombieCrawling")
        elseif z:isOnFloor() then n = ZA.tr("Scan_ZombieGround") end
    end)
    pcall(function() if z:getTarget() == getPlayer() then n = n .. ", " .. ZA.tr("Scan_ComingForYou") end end)
    if not S.canSeeMob(z) then n = n .. ", " .. ZA.tr("Scan_OutOfSight") end
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
                    cat = "zombies", key = "zombies|" .. tostring(z:getID()), baseName = ZA.tr("Scan_Zombie"), name = zombieName,
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
                    cat = "animals", key = "animals|" .. id, baseName = ZA.tr("Scan_Animal"),
                    name = function(e)
                        local n = ZA.tr("Scan_Animal")
                        pcall(function() n = e.obj:getFullName() end)
                        if not S.canSeeMob(e.obj) then n = n .. ", " .. ZA.tr("Scan_OutOfSight") end
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
    local nsq = 0
    for z = pz - 1, pz + 1 do
        -- (the floors above and below stay at 20 m when the scan is widened: 40 m on three floors is 20000
        -- squares, about 0.4 s a look)
        local r = (z == pz) and S.radius or math.min(S.radius, 20)
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
    ZA.log("[ZA] scan: " .. nsq .. " squares in " .. S.stats.ms .. " ms; " .. table.concat(counts, " ")
        .. (S.stats.lastError and (" ERROR " .. S.stats.lastError) or ""))
end

-- Same floor first, then the same side of the walls (inside this building, or outdoors), then nearest:
-- a toilet 5 metres away through a wall is further than it sounds. A door or window in your side's wall counts as
-- your side (in game 2026-10-22, the locked front door 1 m away came 5th, behind doors 8 to 15 m away outdoors).
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
                if sq and sq:getBuilding() ~= myBuilding then
                    local other = passageOtherSide(e.obj, sq)
                    if not (other and other:getBuilding() == myBuilding) then e.sideGap = 1 end
                end
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

-- Room words: the game's room ids are joined-up English ("livingroom", "kidsbedroom") and the game has no
-- translation for them, so the known ids are in the mod's own catalogue (Scan_Room_<id>, Scan_RoomIn_<id>).
local roomIds = { livingroom = true, diningroom = true, kidsbedroom = true, laundry = true, hall = true, storageunit = true, grocerystorage = true, garagestorage = true, closet = true, toolstore = true, gasstore = true, bedroom = true, bathroom = true, kitchen = true, dining = true, storage = true, shed = true, barn = true, office = true, lobby = true, hoarderbedroom = true, hoarderkitchen = true, hoarderoffice = true, restaurantkitchen = true, restaurantdining = true, dinerkitchen = true, cafekitchen = true, barkitchen = true, classroom = true, elementaryclassroom = true, secondaryclassroom = true, hospitalroom = true, hospitalhallway = true, motelroom = true, motelroomoccupied = true, waitingroom = true, breakroom = true, library = true, janitor = true, security = true, evidenceroom = true, prisoncells = true, laboratory = true, morgue = true, medical = true, medicaloffice = true, pharmacy = true, policeoffice = true, cafe = true, cafeteria = true, bar = true, warehouse = true, mechanic = true, gym = true }

-- Returns the room's bare name ("kitchen") and the phrase that places something in it ("in the kitchen").
-- The phrase carries its own preposition and article, which depend on the language and the word.
function S.roomName(room)
    local r = room and room:getName()
    if not r or r == "" then return nil end
    if roomIds[r] then return ZA.tr("Scan_Room_" .. r), ZA.tr("Scan_RoomIn_" .. r) end
    local pre = r:match("^(%a+)room$")
    if pre and #pre > 4 and pre ~= "class" and pre ~= "store" and pre ~= "break" then
        return ZA.tr("Scan_RoomGen", pre), ZA.tr("Scan_RoomInGen", pre)
    end
    return r, ZA.tr("Scan_RoomInRaw", r)
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
        local parts = {}
        if pr == nil then table.insert(parts, ZA.tr("Scan_Inside"))
        elseif psq:getBuilding() ~= sq:getBuilding() then table.insert(parts, ZA.tr("Scan_OtherBuilding")) end
        local _, inPhrase = S.roomName(r)
        if inPhrase then table.insert(parts, inPhrase) end
        if #parts == 0 then return "" end
        return ", " .. table.concat(parts, ", ")
    end
    if pr then return ", " .. ZA.tr("Scan_Outside") end
    return ""
end

function S.describe(e, i, n)
    if e.noWhere then return (entryName(e):gsub("[%.%s]+$", "")) .. (i and ZA.pos(i, n) or "") end
    local x, y, z = entryPos(e)
    local w = S.where(x, y, z, e.far)
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
    ZA.log("[ZA] scan say: " .. e.key)
    ZA.say(text)
end

local function noneText(c)
    if c.loot then return ZA.tr("Scan_NoneLoot", c.none) end
    if c.key == "markers" then return c.none end
    if (c.key == "zombies" or c.key == "animals") and S.seenOnly then
        return ZA.tr("Scan_NoneSeen", c.none)
    end
    if c.key == "zombies" or c.key == "animals" then return ZA.tr("Scan_NoneWithin", c.none, S.mobRadius) end
    -- places and houses come from the map, much further than the 20 metres around you (ZA_5ScanPlaces)
    if c.key == "houses" then return ZA.tr("Scan_NoneWithin", c.none, S.housesRadius or 300) end
    if c.key == "places" then return ZA.tr("Scan_NoneWithin", c.none, S.placesRadius or 600) end
    return ZA.tr("Scan_NoneWithin", c.none, S.radius)
end

function S.step(delta)
    S.refreshIfStale()
    local c = cat()
    local list = S.lists[c.key]
    if #list == 0 then ZA.say(ZA.tr("Scan_CatNone", c.name, noneText(c))); return end
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
    if #list == 0 then ZA.say(ZA.tr("Scan_CatNone", c.name, noneText(c))); return end
    -- a new category starts at its nearest thing
    S.sel[c.key] = list[1].key
    local e = list[1]
    local text = ZA.tr("Scan_CatCount", c.name, #list, S.describe(e, 1, #list))
    ZA.log("[ZA] scan say: " .. e.key)
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
        if #list == 0 then ZA.say(ZA.tr("Scan_CatNone", c.name, noneText(c))) else S.step(1) end
        return
    end
    if not alive(e) then
        ZA.say(ZA.tr("Scan_Gone", entryName(e)))
        S.sel[c.key] = nil
        S.build()
        return
    end
    -- fresh distance, and its place in the fresh order
    S.sort()
    local i = selIndex()
    speakEntry(i)
end

-- F8: the scan widened to 40 m, the loot too, in every building round you, not only the one you're in (Marc,
-- 2026-10-22); F8 again for the usual 20 m.
function S.toggleWide()
    S.wide = not S.wide
    S.radius = S.wide and 40 or 20
    S.builtAt = -1e9
    ZA.say(ZA.tr(S.wide and "Scan_WideOn" or "Scan_WideOff"))
end

function S.toggleSeen()
    S.seenOnly = not S.seenOnly
    S.builtAt = -1e9
    ZA.say(S.seenOnly and ZA.tr("Scan_SeenOn") or ZA.tr("Scan_SeenOff"))
end

-- A debug dump of the whole scan to console.txt (through the test channel: ZA.S.dump()).
function S.dump()
    S.build()
    for _, c in ipairs(S.categories) do
        for i, e in ipairs(S.lists[c.key]) do
            local x, y, z = entryPos(e)
            ZA.log(string.format("[ZA] dump %s %d %s | %s | %.1f,%.1f,%d", c.key, i, e.key, S.describe(e), x, y, z))
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
        elseif key == Keyboard.KEY_F8 then
            S.toggleWide()
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
