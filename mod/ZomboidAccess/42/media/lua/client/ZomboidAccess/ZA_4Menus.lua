-- Zomboid Access: the game's in-world menus, read as the controller moves through them.
--   Inventory and loot (Triangle opens it): the container, then each item as Up and Down reach it.
--   Item and world menus (Cross on an item, or the game's context menus): each choice, its place,
--     "more inside, Right opens it", "not available".
--   Round menus (holding the D-pad, holding Share): the choice the right stick points at.

local F = ZA.F

-- ---------- inventory ----------

local function itemWords(entry, page)
    local item, count, equipped
    if instanceof(entry, "InventoryItem") then
        item, count = entry, 1
    elseif type(entry) == "table" and entry.items then
        item = entry.items[1]
        -- the game keeps a stack's first item twice (once for the stack's own line)
        count = math.max(1, #entry.items - 1)
        equipped = entry.equipped
    end
    if not item then return "" end
    local name = item:getName()
    local parts = { name }
    if count and count > 1 then table.insert(parts, count .. " of them") end
    if equipped then
        local p = getPlayer()
        local how = "equipped"
        pcall(function()
            if p:isEquippedClothing(item) then how = "worn"
            elseif p:getPrimaryHandItem() == item and p:getSecondaryHandItem() == item then how = "in both hands"
            elseif p:getPrimaryHandItem() == item then how = "in your main hand"
            elseif p:getSecondaryHandItem() == item then how = "in your other hand" end
        end)
        table.insert(parts, how)
    end
    pcall(function()
        if instanceof(item, "HandWeapon") and item:getConditionMax() > 0 then
            table.insert(parts, "condition " .. item:getCondition() .. " of " .. item:getConditionMax())
        end
    end)
    pcall(function()
        if item:IsFood() then
            if item:isRotten() then table.insert(parts, "rotten")
            elseif item:isFresh() == false and item:getOffAgeMax() < 1000000000 then table.insert(parts, "stale") end
        end
    end)
    pcall(function()
        local fc = item:getFluidContainer()
        if fc then
            if fc:isEmpty() then table.insert(parts, "empty")
            else table.insert(parts, string.format("%s, %.1f litres", ZA.clean(fc:getPrimaryFluid():getTranslatedName()), fc:getAmount())) end
        end
    end)
    return table.concat(parts, ", ")
end

local function containerWords(page)
    local inv = page.inventoryPane and page.inventoryPane.inventory
    local n = 0
    pcall(function() n = #page.inventoryPane.itemslist end)
    local title = ZA.clean(page.title or "")
    if title == "" and inv then title = getTextOrNull("IGUI_ContainerTitle_" .. inv:getType()) or inv:getType() end
    local s = title .. ", " .. (n == 0 and "empty" or (n .. (n == 1 and " kind of thing" or " kinds of things")))
    if page.onCharacter and inv then
        pcall(function()
            local p = getPlayer()
            local max = (inv == p:getInventory()) and p:getMaxWeight() or inv:getEffectiveCapacity(p)
            s = s .. string.format(", %.1f of %.0f weight", inv:getCapacityWeight(), max)
        end)
    end
    return s
end

F.readers.ISInventoryPage = function(page)
    local pane = page.inventoryPane
    if not pane or not pane.items then return nil end
    local inv = pane.inventory
    -- a container switch: the list fills on the next frame, so wait for it before reading
    if page.zaLastInv ~= nil and page.zaLastInv ~= inv then
        local t = getTimestampMs()
        if page.zaPendingInv ~= inv then page.zaPendingInv, page.zaPendingAt = inv, t end
        if t - page.zaPendingAt < 120 then return "pending", "", "" end
    end
    local cw = containerWords(page)
    local n = #pane.items
    local key, words
    if n == 0 then
        -- an empty list is either a truly empty container or one not filled in yet (next frame)
        if pane.itemslist and #pane.itemslist > 0 then return "pending", "", "" end
        key, words = tostring(inv) .. "#empty", (page.zaLastInv == nil) and "empty" or cw
    else
        local i = (pane.joyselection or 0)
        if i < 0 then i = n - 1 elseif i >= n then i = 0 end
        local entry = pane.items[i + 1]
        key = tostring(inv) .. "#" .. i .. "#" .. tostring(entry)
        words = itemWords(entry, page) .. ZA.pos((i + 1), n)
    end
    -- a new container: say which one first
    if page.zaLastInv == nil then
        page.zaLastInv = inv        -- the screen intro already named it
    elseif page.zaLastInv ~= inv then
        page.zaLastInv = inv
        words = cw .. ". " .. words
    end
    return key, words, ""
end

F.screens.ISInventoryPage = {
    intro = function(page)
        local who = page.onCharacter and "Your inventory" or "Nearby"
        return who .. ": " .. containerWords(page) .. ". Up and Down: items. Left and Right: your inventory or what's nearby. "
            .. (page.onCharacter and "{L1}: next bag. " or "{R1}: next container. ")
            .. "{Cross}: item options. {Square}: take or put. {Circle}: open or close a stack. {Triangle}: close"
    end,
}

-- ---------- context menus ----------

F.readers.ISContextMenu = function(menu)
    local i = menu.mouseOver
    local count = (menu.numOptions or 1) - 1
    if not i or i < 1 or not menu.options or not menu.options[i] then
        return menu, "", ""
    end
    local o = menu.options[i]
    local parts = { ZA.clean(o.name or "") }
    if o.subOption and not o.onSelect then table.insert(parts, "more inside, Right opens it") end
    if o.notAvailable then table.insert(parts, "not available") end
    local words = table.concat(parts, ", ") .. ZA.pos(i, count)
    pcall(function()
        local tip = o.toolTip and o.toolTip.description
        if tip and tip ~= "" then words = words .. ". " .. ZA.clean(tip) end
    end)
    return menu.zaId or i, words, ""
end

F.screens.ISContextMenu = {
    intro = function(menu)
        local back = menu.parent and menu.parent.Type == "ISContextMenu"
        return (back and "Submenu" or "Options") .. ". Up and Down choose, {Cross} does it, " .. (back and "Left goes back" or "{Circle} closes")
    end,
}

-- ---------- round menus ----------

local function radialReader(menu)
    local idx = -1
    if not (menu.joyfocus and menu.slices and #menu.slices > 0) then return "none", "", "" end
    pcall(function() idx = menu.javaObject:getSliceIndexFromJoypad(menu.joyfocus.id) end)
    local s = menu.slices and menu.slices[idx + 1]
    if not s then return "none", "", "" end
    local text = ZA.clean(s.text or "")
    if text == "" then return "none", "", "" end
    return idx, text, ""
end

local function radialIntro(menu)
    local n = 0
    for _, s in ipairs(menu.slices or {}) do if s.text and s.text ~= "" then n = n + 1 end end
    local names = {}
    for _, s in ipairs(menu.slices or {}) do
        if s.text and s.text ~= "" then table.insert(names, ZA.clean(s.text)) end
    end
    if n == 0 then return "Round menu, empty. Nothing to choose here." end
    local how = menu.hideWhenButtonReleased and "point the right stick at one and let go of the button to choose"
        or "point the right stick at one, {Cross} chooses, {Circle} closes"
    return "Round menu, " .. n .. " choices: " .. table.concat(names, ", ") .. ". " .. how:sub(1, 1):upper() .. how:sub(2)
end

local origCurrent = F.current
function F.current(panel)
    if panel and panel.slices and panel.javaObject then
        local ok, key, words, value = pcall(radialReader, panel)
        if ok then return key, words, value end
    end
    return origCurrent(panel)
end

local origIntro = F.screenIntro
function F.screenIntro(panel)
    if panel and panel.slices and panel.javaObject then
        local ok, t = pcall(radialIntro, panel)
        if ok then return t end
    end
    return origIntro(panel)
end

-- ---------- item details (R3 on an item, or Insert while the inventory is open) ----------

local function tr(s)
    if not s or s == "" then return nil end
    local t = getTextOrNull(s)
    return ZA.clean(t or s)
end

-- What an item is and what it's for, from the item's own data and the game's recipes.
function F.itemDetails(item)
    local p = getPlayer()
    local parts = { item:getName() }
    pcall(function()
        local c = item:getDisplayCategory()
        if c then table.insert(parts, tr("IGUI_ItemCat_" .. c) or c) end
    end)
    pcall(function() table.insert(parts, string.format("weight %.2f", item:getUnequippedWeight())) end)
    pcall(function()
        if item:IsFood() then
            local h = math.floor(-item:getHungerChange() * 100 + 0.5)
            if h > 0 then table.insert(parts, "eases hunger by " .. h) end
            local t = math.floor(-item:getThirstChange() * 100 + 0.5)
            if t > 0 then table.insert(parts, "eases thirst by " .. t) end
            local off, age = item:getOffAge(), item:getAge()
            if item:isRotten() then table.insert(parts, "rotten")
            elseif off and off > 0 and off < 1000000 and age < off then
                table.insert(parts, "fresh for about " .. math.max(1, math.floor(off - age)) .. " more days")
            end
            if item:isPoison() then table.insert(parts, "poisonous") end
        end
    end)
    pcall(function()
        if instanceof(item, "HandWeapon") then
            table.insert(parts, string.format("weapon, damage %.1f to %.1f, reach %.1f", item:getMinDamage(), item:getMaxDamage(), item:getMaxRange()))
            if item:isRanged() then table.insert(parts, "a gun") end
            table.insert(parts, "condition " .. item:getCondition() .. " of " .. item:getConditionMax())
        end
    end)
    pcall(function()
        if instanceof(item, "Clothing") then
            local b, sc = math.floor(item:getBiteDefense()), math.floor(item:getScratchDefense())
            if b > 0 or sc > 0 then table.insert(parts, "protects against bites " .. b .. ", scratches " .. sc) end
        end
    end)
    pcall(function()
        if instanceof(item, "Literature") then
            local sk = item:getSkillTrained()
            if sk and sk ~= "" and sk ~= "None" then
                table.insert(parts, "skill book for " .. (tr("IGUI_perks_" .. sk) or sk) .. ", up to level " .. item:getMaxLevelTrained())
            end
            local rec = item:getTeachedRecipes()
            if rec and rec:size() > 0 then table.insert(parts, "teaches " .. rec:size() .. " recipes when read") end
        end
    end)
    pcall(function()
        local t = item:getTooltip()
        if t and t ~= "" then table.insert(parts, tr(t)) end
    end)
    -- what it's used for: the game's crafting recipes that take it
    pcall(function()
        local all = ScriptManager.instance:getAllCraftRecipes()
        local names, seen = {}, {}
        for i = 0, all:size() - 1 do
            local r = all:get(i)
            local ok, used = pcall(function()
                return CraftRecipeManager.isItemValidForRecipe(r, item, p) or CraftRecipeManager.isItemToolForRecipe(r, item, p)
            end)
            if ok and used then
                local n = tr(r:getTranslationName()) or r:getName()
                if not seen[n] then seen[n] = true; table.insert(names, n) end
            end
        end
        if #names > 0 then
            local shown = {}
            for i = 1, math.min(6, #names) do shown[i] = names[i] end
            local s = "Used in " .. #names .. (#names == 1 and " recipe: " or " recipes, like: ") .. table.concat(shown, ", ")
            table.insert(parts, s)
        else
            table.insert(parts, "Not used in any recipe")
        end
    end)
    table.insert(parts, "{Cross} shows what you can do with it")
    for i, t in ipairs(parts) do parts[i] = tostring(t):gsub("[%.%s]+$", "") end
    return table.concat(parts, ". ") .. "."
end

-- The item the inventory's selection is on.
function F.selectedItem(page)
    local pane = page and page.inventoryPane
    if not pane or not pane.items or #pane.items == 0 then return nil end
    local i = pane.joyselection or 0
    if i < 0 or i >= #pane.items then i = 0 end
    local entry = pane.items[i + 1]
    if instanceof(entry, "InventoryItem") then return entry end
    if type(entry) == "table" and entry.items then return entry.items[1] end
    return nil
end

function F.sayDetails(page)
    local item = F.selectedItem(page)
    if not item then ZA.say("Nothing selected."); return end
    local ok, t = pcall(F.itemDetails, item)
    if ok then ZA.say(t) else print("[ZA] details error: " .. tostring(t)) end
end

if not F.detailsHooked then
    F.detailsHooked = true
    local orig = ISInventoryPage.onJoypadDown
    function ISInventoryPage:onJoypadDown(button, joypadData)
        if button == Joypad.RStickButton then F.sayDetails(self); return end
        return orig(self, button, joypadData)
    end
end
