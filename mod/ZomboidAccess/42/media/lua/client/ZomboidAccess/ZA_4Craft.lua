-- Zomboid Access: crafting and building, in menus that read (her pick 2026-10-02: "Building + crafting").
-- The game's Crafting and Building windows draw icon grids and slots that nothing reads. Underneath they run the
-- game's own craft logic (HandcraftLogic, BuildLogic); this uses the same logic with plain menus (ISContextMenu,
-- read by ZA_4Menus):
--   Craft: categories (how many you can make in each) -> that category's recipes (what you can make first; the others
--   say what's missing) -> one recipe: "Make it" (or "Make several"), then what it needs and the tools, with how many
--   you have. Making it is the window's own call (ISEntityUI.HandcraftStartMultiple), progress is said as usual.
--   Build: the same, from BuildLogic:getAllBuildableRecipes(); "Place it" starts the game's placement cursor
--   (ISBuildIsoEntity, as ISBuildPanel:createBuildIsoEntity does), which ZA_7Cursor reads square by square.
-- Opened from the You list ("Craft", "Build"), and in place of the game's windows when they open (the Share wheel's
-- Crafting and Building, the toolbar).

ZA.CR = ZA.CR or {}
local CR = ZA.CR
local S = ZA.S

-- ---------- menus ----------

local function openMenu()
    local p = getPlayer()
    local sq = p:getCurrentSquare()
    local x = isoToScreenX(0, sq:getX(), sq:getY(), sq:getZ())
    local y = isoToScreenY(0, sq:getX(), sq:getY(), sq:getZ())
    local menu = ISContextMenu.get(0, x, y)
    return menu
end

local function showMenu(menu)
    if menu.numOptions and menu.numOptions < 1 then return end
    if not menu:getIsVisible() then menu:setVisible(true) end
    if JoypadState.players[1] then
        menu.origin = nil
        setJoypadFocus(0, menu)
        menu.mouseOver = 1
    end
end

local function info(menu, text)
    local o = menu:addOption(text, nil, nil)
    o.notAvailable = true
    return o
end

-- ---------- the logic ----------

local function containers() return ISInventoryPaneContextMenu.getContainers(getPlayer()) end

function CR.logic(kind)
    local p = getPlayer()
    local logic
    if kind == "build" then
        logic = BuildLogic.new(p, nil, nil)
        logic:setContainers(containers())
        logic:setRecipes(logic:getAllBuildableRecipes())
    else
        local surface = ISEntityUI.FindCraftSurface(p, 1)
        logic = HandcraftLogic.new(p, nil, surface)
        -- as ISHandCraftPanel does: ISHandcraftAction.FromLogicMultiple expects inputs picked (auto-populated)
        logic:setManualSelectInputs(true)
        logic:setContainers(containers())
        logic:setRecipes(CraftRecipeManager.queryRecipes("InHandCraft;AnySurfaceCraft"))
    end
    return logic
end

local function allRecipes(kind, logic)
    local list = {}
    local src = kind == "build" and logic:getAllBuildableRecipes() or CraftRecipeManager.queryRecipes("InHandCraft;AnySurfaceCraft")
    for i = 0, src:size() - 1 do table.insert(list, src:get(i)) end
    return list
end

local function canMake(logic, recipe)
    local ok, r = pcall(function()
        logic:setRecipe(recipe)
        logic:autoPopulateInputs()
        return logic:canPerformCurrentRecipe()
    end)
    return ok and r
end

local function catName(c)
    if not c or c == "" then return "Other" end
    local t = getTextOrNull("IGUI_CraftCategory_" .. c)
    return t or c
end

-- how many of an input you have, over the containers in reach
local function have(input)
    local n = 0
    local ok = pcall(function()
        local items = input:getPossibleInputItems()
        local cs = containers()           -- a Java ArrayList, not a Lua table
        for k = 0, cs:size() - 1 do
            local c = cs:get(k)
            for i = 0, items:size() - 1 do
                n = n + c:getCountTypeRecurse(items:get(i):getFullName())
            end
        end
    end)
    return ok and n or nil
end

local function inputName(input)
    local name
    pcall(function()
        local items = input:getPossibleInputItems()
        if items:size() > 0 then
            name = items:get(0):getDisplayName()
            if items:size() > 1 then name = name .. " or similar" end
        end
    end)
    if not name then
        pcall(function() name = tostring(input:getOriginalLine()) end)
    end
    return name or "something"
end

-- the lines of what a recipe needs: "4 Nails, you have 10", "Tool: Hammer, kept, you have 1"
function CR.needs(recipe)
    local out, missing = {}, {}
    pcall(function()
        local inputs = recipe:getInputs()
        for i = 0, inputs:size() - 1 do
            local inp = inputs:get(i)
            local amount = 1
            pcall(function() amount = inp:getIntAmount() end)
            local nm = inputName(inp)
            local h = have(inp)
            local tool = false
            pcall(function() tool = inp:isTool() or inp:isKeep() end)
            local line = (tool and ("Tool: " .. nm .. ", kept") or (amount .. " " .. nm))
            if h then line = line .. ", you have " .. h end
            table.insert(out, line)
            if h and h < amount then table.insert(missing, nm) end
        end
    end)
    return out, missing
end

-- ---------- crafting ----------

function CR.make(kind, recipe, times)
    local p = getPlayer()
    local logic = CR.logic(kind)
    logic:setRecipe(recipe)
    logic:autoPopulateInputs()
    if kind == "build" then
        local objInfo = logic:getSelectedBuildObject()
        if not objInfo then ZA.say("That one can't be placed from here."); return end
        local inv = p:getInventory()
        -- the item type for a tool, as ISBuildPanel's (private) getTool picks it
        local function tool(t)
            if not t then return nil end
            local items = t:getPossibleInputItems()
            for m = 0, items:size() - 1 do
                local r = inv:getAllTypeEvalRecurse(items:get(m):getFullName(), ISBuildIsoEntity.predicateMaterial)
                if r:size() > 0 then return r:get(0):getFullType() end
            end
            return nil
        end
        local ent = ISBuildIsoEntity:new(p, objInfo, 1, containers(), logic)
        ent.dragNilAfterPlace = false
        ent.blockAfterPlace = true
        pcall(function()
            ent.equipBothHandItem = tool(recipe:getToolBoth())
            ent.firstItem = tool(recipe:getToolRight())
            ent.secondItem = tool(recipe:getToolLeft())
        end)
        ent.blockBuild = not logic:canPerformCurrentRecipe()
        CR.buildLogic = logic       -- kept alive while the cursor is out
        getCell():setDrag(ent, p:getPlayerNum())
        return
    end
    if not logic:canPerformCurrentRecipe() then ZA.say("You can't make that yet."); return end
    -- the window moves floor items into your hands first, if the recipe can't use them from the floor
    pcall(function()
        if not recipe:isCanBeDoneFromFloor() then
            local items = logic:getRecipeData():getAllInputItems()
            for i = 0, items:size() - 1 do ISInventoryPaneContextMenu.transferIfNeeded(p, items:get(i)) end
        end
    end)
    local actions = ISEntityUI.HandcraftStartMultiple(p, logic, false, times or 1, false)
    if not actions then ZA.say("Couldn't start that. You may need a table or counter next to you."); return end
    for _, a in ipairs(actions) do ISTimedActionQueue.add(a) end
    ZA.say("Making " .. recipe:getTranslationName() .. ((times or 1) > 1 and (", " .. times .. " times") or "") .. ".")
end

function CR.recipeMenu(kind, recipe)
    local logic = CR.logic(kind)
    local ok = canMake(logic, recipe)
    local menu = openMenu()
    local name = recipe:getTranslationName()
    if ok then
        if kind == "build" then
            menu:addOption(ZA.buttons("Place it: " .. name .. ". A square appears; the D-pad moves it, {Cross} builds"), kind, function() CR.make(kind, recipe) end)
        else
            menu:addOption("Make it: " .. name, kind, function() CR.make(kind, recipe, 1) end)
            local count = 1
            pcall(function() count = logic:getPossibleCraftCount(true) end)
            if count and count > 1 then
                local n = math.min(count, 10)
                menu:addOption("Make " .. n .. " of them", kind, function() CR.make(kind, recipe, n) end)
            end
        end
    else
        info(menu, "Can't make it yet: " .. name)
    end
    local lines = CR.needs(recipe)
    for _, l in ipairs(lines) do info(menu, l) end
    pcall(function()
        local tm = recipe:getTime(getPlayer())
        if tm and tm > 0 then info(menu, "Takes about " .. math.max(1, math.floor(tm / 60 + 0.5)) .. " in-game minutes") end
    end)
    menu:addOption("Back to the list", kind, function() CR.categoryMenu(kind, CR.lastCat) end)
    showMenu(menu)
end

function CR.categoryMenu(kind, cat)
    CR.lastCat = cat
    local logic = CR.logic(kind)
    local can, cannot = {}, {}
    for _, r in ipairs(allRecipes(kind, logic)) do
        local c = ""
        pcall(function() c = r:getCategory() or "" end)
        if catName(c) == cat then
            if canMake(logic, r) then table.insert(can, r) else table.insert(cannot, r) end
        end
    end
    local byName = function(a, b) return a:getTranslationName() < b:getTranslationName() end
    table.sort(can, byName); table.sort(cannot, byName)
    local menu = openMenu()
    for _, r in ipairs(can) do
        menu:addOption(r:getTranslationName() .. ", you can make it", kind, function() CR.recipeMenu(kind, r) end)
    end
    for _, r in ipairs(cannot) do
        local _, missing = CR.needs(r)
        local m = #missing > 0 and ("missing " .. table.concat(missing, ", ")) or "can't yet"
        menu:addOption(r:getTranslationName() .. ", " .. m, kind, function() CR.recipeMenu(kind, r) end)
    end
    menu:addOption("Back to the categories", kind, function() CR.open(kind) end)
    showMenu(menu)
end

function CR.open(kind)
    local p = getPlayer()
    if not p then return end
    local logic = CR.logic(kind)
    local cats, order = {}, {}
    for _, r in ipairs(allRecipes(kind, logic)) do
        local c = ""
        pcall(function() c = r:getCategory() or "" end)
        local n = catName(c)
        if not cats[n] then cats[n] = { total = 0, can = 0 }; table.insert(order, n) end
        cats[n].total = cats[n].total + 1
    end
    table.sort(order)
    local menu = openMenu()
    for _, n in ipairs(order) do
        menu:addOption(n .. ", " .. cats[n].total .. " recipes", kind, function() CR.categoryMenu(kind, n) end)
    end
    if #order == 0 then info(menu, kind == "build" and "Nothing to build" or "Nothing to craft") end
    showMenu(menu)
    ZA.say((kind == "build" and "Build" or "Craft") .. ": pick a category. Each recipe says if you can make it, and what's missing if not.")
end

-- ---------- in place of the game's windows ----------
-- When the game's own Crafting or Building window opens, close it and open these menus instead (the windows don't
-- read). Checked each frame: the windows are created by several routes (Share wheel, toolbar, item menus).
-- (ISEntityUI keeps them in ISEntityUI.players[player number].windows[style].instance)
local function swap()
    local pl = ISEntityUI and ISEntityUI.players and ISEntityUI.players[0]
    if not pl or not pl.windows then return end
    for _, rec in pairs(pl.windows) do
        local w = rec.instance
        local kind = w and ((w.Type == "ISHandcraftWindow" and "craft") or (w.Type == "ISBuildWindow" and "build"))
        if kind and w:isVisible() and not w.zaSwapped then
            w.zaSwapped = true
            pcall(function() w:close() end)
            pcall(function() w:setVisible(false); w:removeFromUIManager() end)
            CR.open(kind)
        end
    end
end
if not CR.ticking then
    CR.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(swap)
        if not ok and not CR.errSaid then CR.errSaid = true; print("[ZA] craft swap error: " .. tostring(err)) end
    end)
end

-- "Craft" and "Build" in the You list
table.insert(S.builders, function(lists)
    local p = getPlayer()
    for i, k in ipairs({ { "craft", "Craft: make things from what you have. {Square}" }, { "build", "Build: walls, furniture, fences and more. {Square}" } }) do
        table.insert(lists.you, {
            cat = "you", key = "you|" .. k[1], noWhere = true, order = 905 + i, baseName = k[1],
            name = k[2], x = p:getX(), y = p:getY(), z = p:getZ(),
            action = function() CR.open(k[1]) end,
        })
    end
end)

-- builds placed (the tutorial's building lesson watches this): wraps the game's own placement
-- (server/BuildingObjects loads after these client files: wrap at game start, once)
function CR.wrapCreate()
    if not ISBuildIsoEntity or CR.createWrapped then return end
    CR.createWrapped = true
    local orig = ISBuildIsoEntity.create
    function ISBuildIsoEntity:create(...)
        CR.built = (CR.built or 0) + 1
        return orig(self, ...)
    end
end
Events.OnGameStart.Add(CR.wrapCreate)
CR.wrapCreate()
