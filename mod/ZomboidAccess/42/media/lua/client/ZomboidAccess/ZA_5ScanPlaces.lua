-- Zomboid Access: the scanner's "Places" and "Houses" categories, from the game's map of the whole world
-- (IsoMetaGrid buildings and their room names), not only what is loaded around the player.
--   Places: shops, police, clinics, warehouses... within 600 metres, plus every town on the map.
--   Houses: homes within 300 metres, "visited" once you have been inside.
-- End / Square on one travels there on foot in short legs (ZA_6Walk.lua).

local S = ZA.S

-- Room names -> what the building is, most telling first. Room names come from the map (seen in
-- Muldraugh 2026-10-01: policeoffice, pharmacy, toolstore, gas2go, armysurplus...).
local kinds = {
    { "gunstore", "Gun store" }, { "armysurplus", "Army surplus store" }, { "police", "Police station" },
    { "firestation", "Fire station" }, { "hospital", "Hospital" }, { "medical", "Medical clinic" },
    { "pharmacy", "Pharmacy" }, { "hardware", "Hardware store" }, { "toolstore", "Tool store" },
    { "mechanic", "Mechanic's garage" }, { "gas2go", "Gas 2 Go petrol station" }, { "gasstore", "Petrol station" },
    { "fossoil", "Fossoil petrol station" }, { "grocery", "Grocery store" }, { "cornerstore", "Corner shop" },
    { "generalstore", "General store" }, { "liquorstore", "Liquor store" }, { "warehouse", "Warehouse" },
    { "farmstorage", "Farm" }, { "weldingworkshop", "Welding workshop" }, { "electronicsstore", "Electronics store" },
    { "clothesstore", "Clothes shop" }, { "sportstore", "Sports shop" }, { "golfstore", "Golf shop" },
    { "bookstore", "Book shop" }, { "library", "Library" }, { "comicstore", "Comic shop" },
    { "candystore", "Sweet shop" }, { "pawnshop", "Pawn shop" }, { "movierental", "Video rental shop" },
    { "barbequestore", "Barbecue shop" }, { "diner", "Diner" }, { "restaurant", "Restaurant" }, { "pizza", "Pizza place" },
    { "spiffo", "Spiffo's restaurant" }, { "bar", "Bar" }, { "motel", "Motel" }, { "school", "School" },
    { "classroom", "School" }, { "church", "Church" }, { "bank", "Bank" }, { "post", "Post office" },
    { "gym", "Gym" }, { "fitness", "Gym" }, { "factory", "Factory" }, { "distillery", "Distillery" },
    { "office", "Offices" }, { "storageunit", "Storage units" },
}

local function buildingKind(b)
    local rooms = b:getRooms()
    local names = {}
    for j = 0, rooms:size() - 1 do names[rooms:get(j):getName() or ""] = true end
    for _, k in ipairs(kinds) do
        for n in pairs(names) do
            if n:find(k[1], 1, true) then return k[2] end
        end
    end
    return nil
end

S.buildingKind = buildingKind

-- The nearest point of a building's outline to the player.
local function nearestPoint(b, px, py)
    local x1, y1, x2, y2 = b:getX(), b:getY(), b:getX2(), b:getY2()
    local x = math.max(x1, math.min(px, x2 - 0.5))
    local y = math.max(y1, math.min(py, y2 - 0.5))
    return x, y
end

S.towns = {   -- median of each town's spawn points (media/maps/<Town>/spawnpoints.lua, build 42.21)
    { name = "Muldraugh", x = 10770, y = 10037 }, { name = "West Point", x = 11735, y = 6877 },
    { name = "Riverside", x = 6167, y = 5375 }, { name = "Rosewood", x = 8137, y = 11689 },
    { name = "March Ridge", x = 9883, y = 12812 }, { name = "Brandenburg", x = 2152, y = 6089 },
    { name = "Echo Creek", x = 3573, y = 10899 }, { name = "Ekron", x = 411, y = 9761 },
    { name = "Fallas Lake", x = 7213, y = 8288 }, { name = "Irvington", x = 1912, y = 14381 },
    { name = "Valley Station", x = 12595, y = 5330 },
}

table.insert(S.builders, function(lists)
    local p = getPlayer()
    local px, py = p:getX(), p:getY()
    local mg = getWorld():getMetaGrid()
    local list = ArrayList.new()   -- (entries are keyed by position: getID() is not unique for unloaded buildings)
    mg:getBuildingsIntersecting(math.floor(px) - 600, math.floor(py) - 600, 1200, 1200, list)
    for i = 0, list:size() - 1 do
        local b = list:get(i)
        local kind = buildingKind(b)
        local res = b:isResidential()
        local x, y = nearestPoint(b, px, py)
        local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
        local cat
        if kind and not res then cat = "places"
        elseif res and d <= 300 then cat = "houses"; kind = "House" end
        if cat and kind then
            local bb = b
            table.insert(lists[cat], {
                cat = cat, key = cat .. "|" .. b:getX() .. "," .. b:getY(), baseName = kind, obj = b, walk = "travel",
                x = x, y = y, z = 0, far = true,
                name = function(e)
                    local visited = false
                    pcall(function() visited = bb:isHasBeenVisited() end)
                    return e.baseName .. (visited and ", visited" or "")
                end,
                pos = function(e)
                    local pl = getPlayer()
                    local nx, ny = nearestPoint(e.obj, pl:getX(), pl:getY())
                    return nx, ny, 0
                end,
            })
        end
    end
    -- one place can be several buildings on the map (a petrol station's shop and canopy): keep the nearest
    local kept = {}
    for _, e in ipairs(lists.places) do
        local dup = false
        for _, k in ipairs(kept) do
            if k.baseName == e.baseName and math.abs(k.x - e.x) < 40 and math.abs(k.y - e.y) < 40 then
                dup = true
                if (e.x - px) ^ 2 + (e.y - py) ^ 2 < (k.x - px) ^ 2 + (k.y - py) ^ 2 then
                    for f, v in pairs(e) do k[f] = v end
                end
                break
            end
        end
        if not dup then table.insert(kept, e) end
    end
    lists.places = kept
    for _, t in ipairs(S.towns) do
        local d = math.sqrt((t.x - px) ^ 2 + (t.y - py) ^ 2)
        local here = d < 600
        table.insert(lists.places, {
            cat = "places", key = "places|town|" .. t.name, baseName = t.name, walk = "travel", far = true,
            name = "Town: " .. t.name .. (here and ", you're in it" or ""), x = t.x, y = t.y, z = 0,
        })
    end
end)
