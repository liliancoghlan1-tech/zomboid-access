-- Zomboid Access: what's inside the containers around you, sorted into the scanner's "Loot" categories
-- (food and drink, weapons, medical, tools, clothes and bags, books, everything else).
-- Indoors: every container in the building you're in, every floor. Outdoors: containers and bodies within 8 metres.
-- Each line: the item (how many), the container it's in, distance, direction, room.
-- Hold Square (or press Delete) on one: walk to that container and open it with the item selected.

local S = ZA.S

-- The game's display categories (item:getDisplayCategory()) -> our groups.
local groups = {
    Food = "loot_food", Water = "loot_food", Drink = "loot_food", FoodB = "loot_food",
    Weapon = "loot_weapons", WeaponCrafted = "loot_weapons", Ammo = "loot_weapons", Firearm = "loot_weapons",
    ToolWeapon = "loot_weapons", Explosives = "loot_weapons",
    FirstAid = "loot_medical", Bandage = "loot_medical", Medical = "loot_medical",
    Tool = "loot_tools", Material = "loot_tools", Electronics = "loot_tools", Gardening = "loot_tools",
    Fishing = "loot_tools", Camping = "loot_tools", VehicleMaintenance = "loot_tools", LightSource = "loot_tools",
    Paint = "loot_tools", Trapping = "loot_tools", Cooking = "loot_tools",
    Clothing = "loot_clothes", Container = "loot_clothes", Accessory = "loot_clothes", Bag = "loot_clothes",
    ProtectiveGear = "loot_clothes", Appearance = "loot_clothes",
    Literature = "loot_books", SkillBook = "loot_books", Cartography = "loot_books", Paper = "loot_books",
}

local function groupOf(item)
    local c = ""
    pcall(function() c = item:getDisplayCategory() or "" end)
    local g = groups[c]
    if g then return g end
    local ok, food = pcall(function() return item:IsFood() end)
    if ok and food then return "loot_food" end
    if instanceof(item, "HandWeapon") then return "loot_weapons" end
    if instanceof(item, "Clothing") then return "loot_clothes" end
    if instanceof(item, "Literature") then return "loot_books" end
    return "loot_other"
end

-- One container's items, one line per kind of item.
local function addContainer(lists, c, obj, title, x, y, z, keyBase)
    local items = c:getItems()
    local byName, order = {}, {}
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local n = it:getName()
        if not byName[n] then byName[n] = { item = it, count = 0 }; table.insert(order, n) end
        byName[n].count = byName[n].count + 1
    end
    for _, n in ipairs(order) do
        local b = byName[n]
        local g = groupOf(b.item)
        table.insert(lists[g], {
            cat = g, key = g .. "|" .. keyBase .. "|" .. n, baseName = n, itemName = n,
            name = n .. (b.count > 1 and (", " .. b.count) or "") .. ", in the " .. title,
            obj = obj, container = c, x = x, y = y, z = z, walk = "container", lootItem = true,
            alive = function(e) return e.obj:getSquare() ~= nil and e.container:getItems():size() > 0 end,
        })
    end
end

table.insert(S.postBuilders, function(lists)
    local p = getPlayer()
    local psq = p:getCurrentSquare()
    local building = psq and psq:getBuilding()
    local px, py = p:getX(), p:getY()
    local function near(e) return (e.x - px) ^ 2 + (e.y - py) ^ 2 <= 64 end
    for _, e in ipairs(lists.containers) do
        local sq = e.obj:getSquare()
        local keep
        if building then keep = sq and sq:getBuilding() == building else keep = near(e) end
        if keep and e.container then
            local title = e.baseName:gsub(",.*$", ""):lower()   -- "green counter", not "green counter, cupboard"
            addContainer(lists, e.container, e.obj, title, e.x, e.y, e.z, e.key)
        end
    end
    -- bodies close by (zombies carry things too)
    for _, e in ipairs(lists.bodies) do
        local ok, c = pcall(function() return e.obj:getContainer() end)
        if near(e) and ok and c then
            addContainer(lists, c, e.obj, e.baseName:lower(), e.x, e.y, e.z, e.key)
        end
    end
end)
