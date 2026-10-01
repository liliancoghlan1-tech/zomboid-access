-- Zomboid Access: how far along a long action is (reading, researching, crafting, bandaging...).
--   An action still going after 2 seconds is named: "Reading Delicious Cocktails."
--   Then 25, 50 and 75 percent, and "Finished reading" or "Stopped reading" at the end.
--   The scanner's "You" list starts with what you're doing and how far along it is.
-- Progress is the game's own: the queue's current action, getJobDelta() from 0 to 1 (as ISHealthPanel shows it).

ZA.PR = ZA.PR or {}
local PR = ZA.PR
local S = ZA.S

local verbs = {
    ISReadABook = "Reading", ISResearchRecipe = "Researching", ISCraftAction = "Crafting",
    ISHandcraftAction = "Crafting", ISBuildAction = "Building", ISApplyBandage = "Bandaging",
    ISDisinfect = "Disinfecting", ISCleanBandage = "Cleaning a bandage", ISEatFoodAction = "Eating",
    ISDrinkFluidAction = "Drinking", ISDrinkFromBottle = "Drinking", ISTakeWaterAction = "Drinking",
    ISRestAction = "Resting", ISBarricadeAction = "Barricading", ISUnbarricadeAction = "Removing a barricade",
    ISDismantleAction = "Taking it apart", ISChopTreeAction = "Chopping", ISRepairClothing = "Mending",
    ISWashClothing = "Washing clothes", ISWashYourself = "Washing", ISCleanBlood = "Cleaning",
    ISInventoryTransferAction = "Moving items", ISGrabItemAction = "Picking up", ISDropItemAction = "Dropping",
    ISUnequipAction = "Taking off", ISWearClothing = "Putting on", ISEquipWeaponAction = "Equipping",
    ISMoveablesAction = "Moving furniture", ISScrapItemAction = "Scrapping", ISReadWorldMap = "Reading the map",
}
local skip = { ISWalkToTimedAction = true, ISPathFindAction = true }

local function words(a)
    local t = a.Type or "Doing something"
    local v = verbs[t]
    if not v then
        v = t:gsub("^IS", ""):gsub("Action$", ""):gsub("(%l)(%u)", "%1 %2")
        v = v:sub(1, 1):upper() .. v:sub(2):lower()
    end
    local what = ""
    pcall(function()
        if a.item and a.item.getName and (t == "ISReadABook" or t == "ISResearchRecipe" or t == "ISEatFoodAction"
            or t == "ISDrinkFromBottle" or t == "ISApplyBandage" or t == "ISWearClothing" or t == "ISEquipWeaponAction") then
            what = " " .. a.item:getName()
        end
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

-- "Reading Delicious Cocktails, 40 percent"
function PR.status()
    local p = getPlayer()
    local a = p and current(p)
    if not a then return nil end
    local v, what = words(a)
    return v .. what .. ", " .. math.floor(PR.delta(a) * 100) .. " percent"
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
            if d >= 0.9 then ZA.queue("Finished " .. v:lower() .. ".")
            else ZA.queue("Stopped " .. v:lower() .. ".") end
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
            ZA.queue(v .. what .. ".")
        end
        return
    end
    local step = math.floor(d * 4)   -- 1, 2, 3 = 25, 50, 75 percent
    if step > PR.step and step < 4 then
        PR.step = step
        ZA.queue((step * 25) .. " percent.")
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
        cat = "you", key = "you|doing", noWhere = true, order = 0, baseName = "Doing",
        name = function() return PR.status() or "Not doing anything now" end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
    })
end)
