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
    if count and count > 1 then table.insert(parts, ZA.tr("Menus_CountOf", count)) end
    if equipped then
        local p = getPlayer()
        local how = ZA.tr("Menus_Equipped")
        pcall(function()
            if p:isEquippedClothing(item) then how = ZA.tr("Menus_Worn")
            elseif p:getPrimaryHandItem() == item and p:getSecondaryHandItem() == item then how = ZA.tr("Menus_BothHands")
            elseif p:getPrimaryHandItem() == item then how = ZA.tr("Menus_MainHand")
            elseif p:getSecondaryHandItem() == item then how = ZA.tr("Menus_OtherHand") end
        end)
        table.insert(parts, how)
    end
    pcall(function()
        if instanceof(item, "HandWeapon") and item:getConditionMax() > 0 then
            table.insert(parts, ZA.tr("Menus_Condition", item:getCondition(), item:getConditionMax()))
        end
    end)
    pcall(function()
        if item:IsFood() then
            if item:isRotten() then table.insert(parts, ZA.tr("Menus_Rotten"))
            elseif item:isFresh() == false and item:getOffAgeMax() < 1000000000 then table.insert(parts, ZA.tr("Menus_Stale")) end
        end
    end)
    pcall(function()
        local fc = item:getFluidContainer()
        if fc then
            if fc:isEmpty() then table.insert(parts, ZA.tr("Menus_Empty"))
            else
                -- singular or plural as the language counts: English "1.0 litre", French below 2 ("0,2 litre")
                local amt = fc:getAmount()
                local below = tonumber(ZA.tr("Menus_LitreSingularBelow")) or 0
                local one = string.format("%.1f", amt) == "1.0" or amt < below
                table.insert(parts, ZA.tr(one and "Menus_FluidAmountOne" or "Menus_FluidAmount", ZA.clean(fc:getPrimaryFluid():getTranslatedName()), ZA.dec(amt, "%.1f")))
            end
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
    local s
    if n == 0 then s = ZA.tr("Menus_ContEmpty", title)
    elseif n == 1 then s = ZA.tr("Menus_ContOne", title)
    else s = ZA.tr("Menus_ContMany", title, n) end
    if page.onCharacter and inv then
        pcall(function()
            local p = getPlayer()
            local max = (inv == p:getInventory()) and p:getMaxWeight() or inv:getEffectiveCapacity(p)
            s = ZA.tr("Menus_ContWeight", s, ZA.dec(inv:getCapacityWeight(), "%.1f"), string.format("%.0f", max))
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
        key, words = tostring(inv) .. "#empty", (page.zaLastInv == nil) and ZA.tr("Menus_Empty") or cw
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
        -- an empty container's words are already its name ("Oven, empty"): don't say them twice
        if n > 0 then words = cw .. ". " .. words end
    end
    return key, words, ""
end

F.screens.ISInventoryPage = {
    intro = function(page)
        return ZA.tr(page.onCharacter and "Menus_InvIntroMine" or "Menus_InvIntroNear", containerWords(page))
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
    if o.subOption and not o.onSelect then table.insert(parts, ZA.tr("Menus_MoreInside")) end
    if o.notAvailable and not o.zaInfo then table.insert(parts, ZA.tr("Menus_NotAvailable")) end
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
        return ZA.tr(back and "Menus_IntroSub" or "Menus_IntroOptions")
    end,
    -- on opening: the menu's name and the selected option first, the buttons after (F7 still says it all first)
    itemFirst = function(menu)
        local back = menu.parent and menu.parent.Type == "ISContextMenu"
        return ZA.tr(back and "Menus_NameSub" or "Menus_NameOptions"), ZA.tr(back and "Menus_HintSub" or "Menus_HintOptions")
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
    if n == 0 then return ZA.tr("Menus_RoundEmpty") end
    return ZA.tr(menu.hideWhenButtonReleased and "Menus_RoundHold" or "Menus_RoundPress", n, table.concat(names, ", "))
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
    pcall(function() table.insert(parts, ZA.tr("Menus_Weight", ZA.dec(item:getUnequippedWeight(), "%.2f"))) end)
    pcall(function()
        if item:IsFood() then
            local h = math.floor(-item:getHungerChange() * 100 + 0.5)
            if h > 0 then table.insert(parts, ZA.tr("Menus_Hunger", h)) end
            local t = math.floor(-item:getThirstChange() * 100 + 0.5)
            if t > 0 then table.insert(parts, ZA.tr("Menus_Thirst", t)) end
            local off, age = item:getOffAge(), item:getAge()
            if item:isRotten() then table.insert(parts, ZA.tr("Menus_Rotten"))
            elseif off and off > 0 and off < 1000000 and age < off then
                local days = math.max(1, math.floor(off - age))
                table.insert(parts, days == 1 and ZA.tr("Menus_FreshOne") or ZA.tr("Menus_FreshMany", days))
            end
            if item:isPoison() then table.insert(parts, ZA.tr("Menus_Poisonous")) end
        end
    end)
    pcall(function()
        if instanceof(item, "HandWeapon") then
            table.insert(parts, ZA.tr("Menus_Weapon", ZA.dec(item:getMinDamage(), "%.1f"), ZA.dec(item:getMaxDamage(), "%.1f"), ZA.dec(item:getMaxRange(), "%.1f")))
            if item:isRanged() then table.insert(parts, ZA.tr("Menus_Gun")) end
            table.insert(parts, ZA.tr("Menus_Condition", item:getCondition(), item:getConditionMax()))
        end
    end)
    pcall(function()
        if instanceof(item, "Clothing") then
            local b, sc = math.floor(item:getBiteDefense()), math.floor(item:getScratchDefense())
            if b > 0 or sc > 0 then table.insert(parts, ZA.tr("Menus_Protects", b, sc)) end
        end
    end)
    pcall(function()
        if instanceof(item, "Literature") then
            local sk = item:getSkillTrained()
            if sk and sk ~= "" and sk ~= "None" then
                table.insert(parts, ZA.tr("Menus_SkillBook", tr("IGUI_perks_" .. sk) or sk, item:getMaxLevelTrained()))
            end
            -- Build 42 calls them learned recipes (getTeachedRecipes is gone); say too when you know them all already
            local rec = item:getLearnedRecipes()
            if rec and rec:size() > 0 then
                table.insert(parts, rec:size() == 1 and ZA.tr("Menus_TeachesOne") or ZA.tr("Menus_TeachesMany", rec:size()))
                local known = false
                pcall(function() known = getPlayer():getKnownRecipes():containsAll(rec) end)
                if known then table.insert(parts, ZA.tr("Menus_TeachesKnown")) end
            end
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
            local s
            if #names == 1 then s = ZA.tr("Menus_UsedOne", table.concat(shown, ", "))
            else s = ZA.tr("Menus_UsedMany", #names, table.concat(shown, ", ")) end
            table.insert(parts, s)
        else
            table.insert(parts, ZA.tr("Menus_UsedNone"))
        end
    end)
    table.insert(parts, ZA.tr("Menus_DetailsHint"))
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
    if not item then ZA.say(ZA.tr("Menus_NothingSelected")); return end
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
