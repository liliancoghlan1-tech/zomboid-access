-- Zomboid Access: the scanner's "Crops" category: furrows and plants within 40 metres, from the game's own farming
-- system (CFarmingSystem). Each line: what it is and its stage as the game names it ("Seedling Carrots",
-- "Ready to harvest Tomatoes", "Plowed Land", "Dead Cabbages"), its water as the info window words it, sickness for a
-- farmer of level 3 or more (as in the game), then distance and direction.
-- Square (walk) goes next to it; hold Square (use) opens the game's menu for it: info, water, harvest, treat, remove.

local S = ZA.S

local inserted = false
for _, c in ipairs(S.categories) do if c.key == "crops" then inserted = true end end
if not inserted then
    for i, c in ipairs(S.categories) do
        if c.key == "water" then
            table.insert(S.categories, i + 1, { key = "crops", name = "Crops", none = "no crops or furrows" })
            break
        end
    end
end

local RANGE = 40

table.insert(S.postBuilders, function(lists)
    lists.crops = lists.crops or {}
    local sys = CFarmingSystem and CFarmingSystem.instance
    if not sys then return end
    local p = getPlayer()
    local px, py = p:getX(), p:getY()
    for i = 1, sys:getLuaObjectCount() do
        local plant = sys:getLuaObjectByIndex(i)
        if plant and plant.x and math.abs(plant.x - px) <= RANGE and math.abs(plant.y - py) <= RANGE then
            local x, y, z = plant.x, plant.y, plant.z or 0
            table.insert(lists.crops, {
                cat = "crops", key = "crops|" .. x .. "," .. y .. "," .. z,
                baseName = "crop", plant = plant,
                name = function(e)
                    local ok, w = pcall(ZA.CU.plantWords, e.plant, getPlayer())
                    return ok and w or "a crop"
                end,
                x = x + 0.5, y = y + 0.5, z = z, walk = "adjacent",
                obj = plant:getObject(),
                alive = function(e)
                    return CFarmingSystem.instance:getLuaObjectAt(e.plant.x, e.plant.y, e.plant.z) ~= nil
                end,
            })
        end
    end
end)
