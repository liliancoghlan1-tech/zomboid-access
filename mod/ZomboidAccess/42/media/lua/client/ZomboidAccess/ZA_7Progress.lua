-- Zomboid Access: how far along a long action is (reading, researching, crafting, bandaging...).
--   An action still going after 2 seconds is named: "Reading Delicious Cocktails."
--   Then 25, 50 and 75 percent, and "Finished reading" or "Stopped reading" at the end.
--   The scanner's "You" list starts with what you're doing and how far along it is.
-- Progress is the game's own: the queue's current action, getJobDelta() from 0 to 1 (as ISHealthPanel shows it).

ZA.PR = ZA.PR or {}
local PR = ZA.PR
local S = ZA.S

-- action type (an id) -> what it is called, said through the translation system, one key each
local verbs = {
    ISReadABook = function() return ZA.tr("Progress_Reading") end,
    ISResearchRecipe = function() return ZA.tr("Progress_Researching") end,
    ISCraftAction = function() return ZA.tr("Progress_Crafting") end,
    ISHandcraftAction = function() return ZA.tr("Progress_Crafting") end,
    ISBuildAction = function() return ZA.tr("Progress_Building") end,
    ISApplyBandage = function() return ZA.tr("Progress_Bandaging") end,
    ISDisinfect = function() return ZA.tr("Progress_Disinfecting") end,
    ISCleanBandage = function() return ZA.tr("Progress_CleaningBandage") end,
    ISEatFoodAction = function() return ZA.tr("Progress_Eating") end,
    ISDrinkFluidAction = function() return ZA.tr("Progress_Drinking") end,
    ISDrinkFromBottle = function() return ZA.tr("Progress_Drinking") end,
    ISTakeWaterAction = function() return ZA.tr("Progress_Drinking") end,
    ISRestAction = function() return ZA.tr("Progress_Resting") end,
    ISBarricadeAction = function() return ZA.tr("Progress_Barricading") end,
    ISUnbarricadeAction = function() return ZA.tr("Progress_Unbarricading") end,
    ISDismantleAction = function() return ZA.tr("Progress_Dismantling") end,
    ISChopTreeAction = function() return ZA.tr("Progress_Chopping") end,
    ISRepairClothing = function() return ZA.tr("Progress_Mending") end,
    ISWashClothing = function() return ZA.tr("Progress_WashingClothes") end,
    ISWashYourself = function() return ZA.tr("Progress_Washing") end,
    ISCleanBlood = function() return ZA.tr("Progress_Cleaning") end,
    ISInventoryTransferAction = function() return ZA.tr("Progress_MovingItems") end,
    ISGrabItemAction = function() return ZA.tr("Progress_PickingUp") end,
    ISDropItemAction = function() return ZA.tr("Progress_Dropping") end,
    ISUnequipAction = function() return ZA.tr("Progress_TakingOff") end,
    ISWearClothing = function() return ZA.tr("Progress_PuttingOn") end,
    ISEquipWeaponAction = function() return ZA.tr("Progress_Equipping") end,
    ISMoveablesAction = function() return ZA.tr("Progress_MovingFurniture") end,
    ISScrapItemAction = function() return ZA.tr("Progress_Scrapping") end,
    ISReadWorldMap = function() return ZA.tr("Progress_ReadingMap") end,
    ISFitnessAction = function() return ZA.tr("Progress_Exercising") end,
}
local skip = { ISWalkToTimedAction = true, ISPathFindAction = true }

local function words(a)
    local t = a.Type or "Doing something"
    local v
    if verbs[t] then
        v = verbs[t]()
    else
        -- an action the mod has no name for: the class name made readable (English) in English, a general word elsewhere
        v = t:gsub("^IS", ""):gsub("Action$", ""):gsub("(%l)(%u)", "%1 %2")
        v = v:sub(1, 1):upper() .. v:sub(2):lower()
        -- (the key says whether this language shows that English name: yes in English, no elsewhere)
        if ZA.tr("Progress_OtherNamed") ~= "1" then v = ZA.tr("Progress_Doing") end
    end
    local what = ""
    pcall(function()
        if a.item and a.item.getName and (t == "ISReadABook" or t == "ISResearchRecipe" or t == "ISEatFoodAction"
            or t == "ISDrinkFromBottle" or t == "ISWearClothing" or t == "ISEquipWeaponAction") then
            what = a.item:getName()
        end
        -- the exercise picked in the exercise window: "Exercising: Squats"
        if t == "ISFitnessAction" and a.exeData and a.exeData.name then what = a.exeData.name end
    end)
    return v, what
end

local function current(p)
    local q = ISTimedActionQueue.getTimedActionQueue(p)
    local a = q and q.queue and q.queue[1]
    if a and not skip[a.Type] then return a end
    return nil
end

function PR.delta(a)
    local ok, d = pcall(function() return a:getJobDelta() end)
    return ok and d or 0
end

-- "Reading Delicious Cocktails": the action, then the item when there is one
function PR.label(v, what)
    if what == "" then return v end
    return ZA.tr("Progress_WithItem", v, what)
end

-- "Reading Delicious Cocktails, 40 percent"
function PR.status()
    local p = getPlayer()
    local a = p and current(p)
    if not a then return nil end
    local v, what = words(a)
    return ZA.tr("Progress_Percent", PR.label(v, what), math.floor(PR.delta(a) * 100))
end

PR.a, PR.next = nil, 0

function PR.tick()
    local p = getPlayer()
    if not p or p:isDead() then PR.a = nil; return end
    local t = getTimestampMs()
    if t < PR.next then return end
    PR.next = t + 250
    local a = current(p)
    if a ~= PR.a then
        -- the old one ended: finished, or stopped part way
        if PR.a and PR.a.zaSaid then
            local v = words(PR.a)
            local d = PR.lastDelta or 0
            if d >= 0.9 then ZA.queue(ZA.tr("Progress_Finished", v:lower()))
            else ZA.queue(ZA.tr("Progress_Stopped", v:lower())) end
        end
        PR.a, PR.started, PR.step, PR.lastDelta = a, t, 0, 0
        return
    end
    if not a then return end
    local d = PR.delta(a)
    PR.lastDelta = d
    if not a.zaSaid then
        if t - PR.started >= 2000 and d < 0.8 then
            a.zaSaid = true
            local v, what = words(a)
            ZA.queue(ZA.tr("Progress_Named", PR.label(v, what)))
        end
        return
    end
    local step = math.floor(d * 4)   -- 1, 2, 3 = 25, 50, 75 percent
    if step > PR.step and step < 4 then
        PR.step = step
        ZA.queue(ZA.tr("Progress_Step", step * 25))
    end
end

if not PR.ticking then
    PR.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(PR.tick)
        if not ok then print("[ZA] progress error: " .. tostring(err)) end
    end)
end

-- First line of the "You" list while something is going on.
table.insert(S.builders, function(lists)
    local p = getPlayer()
    if not current(p) then return end
    table.insert(lists.you, {
        cat = "you", key = "you|doing", noWhere = true, order = 0, baseName = ZA.tr("Progress_DoingName"),
        name = function() return PR.status() or ZA.tr("Progress_Nothing") end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
    })
end)
