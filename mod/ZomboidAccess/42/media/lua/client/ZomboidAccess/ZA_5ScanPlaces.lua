-- Zomboid Access: the scanner's "Places" and "Houses" categories, from the game's map of the whole world
-- (IsoMetaGrid buildings and their room names), not only what is loaded around the player.
--   Places: shops, police, clinics, warehouses... within 600 metres, plus every town on the map.
--   Houses: homes within 300 metres, "visited" once you have been inside.
-- End / Square on one travels there on foot in short legs (ZA_6Walk.lua).

local S = ZA.S
S.placesRadius = 600   -- metres
S.housesRadius = 300

-- Room names -> what the building is, most telling first. Room names come from the map (seen in
-- Muldraugh 2026-10-01: policeoffice, pharmacy, toolstore, gas2go, armysurplus...).
local kinds = {   -- ids; the words are ScanPlaces_Kind_<id> and ScanPlaces_KindIn_<id> in the translations
    "gunstore", "armysurplus",
    -- outdoor shops: the best places for a real backpack (loot tables CampingStoreBackpacks; added 2026-10-19)
    "camping", "hunting", "outdoorsupply", "fishingstorage",
    "police", "firestation", "hospital", "medical", "pharmacy", "hardware",
    "toolstore", "mechanic", "gas2go", "gasstore", "fossoil", "grocery", "cornerstore", "generalstore",
    "liquorstore", "warehouse", "farmstorage", "weldingworkshop", "electronicsstore", "clothesstore",
    "sportstore", "golfstore", "bookstore", "library", "comicstore", "candystore", "pawnshop", "movierental",
    "barbequestore", "diner", "restaurant", "pizza", "spiffo", "bar", "motel", "school", "classroom",
    "church", "bank", "post", "gym", "fitness", "factory", "distillery", "office", "storageunit",
}

-- Returns what the building is ("Pharmacy") and the phrase that puts you inside it ("in the Pharmacy").
local function buildingKind(b)
    local rooms = b:getRooms()
    local names = {}
    for j = 0, rooms:size() - 1 do names[rooms:get(j):getName() or ""] = true end
    for _, id in ipairs(kinds) do
        for n in pairs(names) do
            if n:find(id, 1, true) then return ZA.tr("ScanPlaces_Kind_" .. id), ZA.tr("ScanPlaces_KindIn_" .. id) end
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

function S.placesBuilder(lists)
    local p = getPlayer()
    local px, py = p:getX(), p:getY()
    local mg = getWorld():getMetaGrid()
    local list = ArrayList.new()   -- (entries are keyed by position: getID() is not unique for unloaded buildings)
    local R = S.placesRadius
    -- IsoMetaGrid:getBuildingsIntersecting only looks in the one map cell (256 x 256) holding the rectangle's top
    -- left corner: its loop adds the grid's size in cells to a position in squares (build 42.21). In game
    -- 2026-10-19 that corner fell in an empty cell and no house or shop was found, with 35 houses within 300 m.
    -- So ask cell by cell, each with the part of the rectangle inside it (the game skips buildings already listed).
    local x1, y1 = math.floor(px) - R, math.floor(py) - R
    local x2, y2 = x1 + 2 * R, y1 + 2 * R
    for cy = math.floor(y1 / 256), math.floor((y2 - 1) / 256) do
        for cx = math.floor(x1 / 256), math.floor((x2 - 1) / 256) do
            local ax, ay = math.max(x1, cx * 256), math.max(y1, cy * 256)
            local bx, by = math.min(x2, (cx + 1) * 256), math.min(y2, (cy + 1) * 256)
            if bx > ax and by > ay then mg:getBuildingsIntersecting(ax, ay, bx - ax, by - ay, list) end
        end
    end
    for i = 0, list:size() - 1 do
        local b = list:get(i)
        local kind = buildingKind(b)
        local res = b:isResidential()
        local x, y = nearestPoint(b, px, py)
        local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
        local cat
        if kind and not res then cat = "places"
        elseif res and d <= S.housesRadius then cat = "houses"; kind = ZA.tr("ScanPlaces_Kind_house") end
        if cat and kind then
            local bb = b
            table.insert(lists[cat], {
                cat = cat, key = cat .. "|" .. b:getX() .. "," .. b:getY(), baseName = kind, obj = b, walk = "travel",
                x = x, y = y, z = 0, far = true,
                name = function(e)
                    local visited = false
                    pcall(function() visited = bb:isHasBeenVisited() end)
                    return e.baseName .. (visited and (", " .. ZA.tr("ScanPlaces_Visited")) or "")
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
        local here = d < S.placesRadius
        table.insert(lists.places, {
            cat = "places", key = "places|town|" .. t.name, baseName = t.name, walk = "travel", far = true,
            name = here and ZA.tr("ScanPlaces_TownHere", t.name) or ZA.tr("ScanPlaces_Town", t.name), x = t.x, y = t.y, z = 0,
        })
    end
end
-- Registered once (through S.placesBuilder, looked up each time), so this file can be reloaded in a running game.
if not S.placesHooked then
    S.placesHooked = true
    table.insert(S.builders, function(lists) S.placesBuilder(lists) end)
end
