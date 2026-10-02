-- Zomboid Access: cooking, by ear (her report 2026-10-02: "how do I know when to take something out").
-- A sighted player watches the food change colour; the game says nothing. So: food in anything hot near you (stove,
-- oven, microwave, barbecue, campfire: any container warmer than the room, within 12 squares on your floor) is
-- followed, and said as it goes:
--   "Steak cooking, in the stove"   "Steak, half cooked"   "Steak is cooked: take it out before it burns"
--   "Steak is about to burn!"       "Steak has burnt"
-- Each line once per item. From the food's own timers (Food: getCookingTime, getMinutesToCook, getMinutesToBurn,
-- isCooked, isBurnt; it cooks only while its heat is over 1.6).

ZA.CK = ZA.CK or {}
local CK = ZA.CK

CK.range = 12
CK.seen = {}          -- item id -> stage said: 1 cooking, 2 half, 3 cooked, 4 nearly burnt, 5 burnt
CK.nextScan = 0

local function where(c)
    local o = c:getParent()
    local n = o and ZA.S.moveableName and ZA.S.moveableName(o)
    if n and n ~= "" then return n:lower() end
    local t = getTextOrNull("IGUI_ContainerTitle_" .. c:getType())
    return t and t:lower() or c:getType()
end

local function follow(item, c)
    local id = item:getID()
    local stage = CK.seen[id] or 0
    local name = item:getDisplayName():gsub("%s*%b()", "")
    local ct, mtc, mtb = item:getCookingTime(), item:getMinutesToCook(), item:getMinutesToBurn()
    local say
    if item:isBurnt() then
        if stage < 5 then stage, say = 5, name .. " has burnt" end
    elseif item:isCooked() then
        local toBurn = (mtb > ct) and (ct - mtc) / math.max(1, mtb - mtc) or 1
        if toBurn >= 0.5 and stage < 4 then
            stage, say = 4, name .. " is about to burn! Take it out"
        elseif stage < 3 then
            stage, say = 3, name .. " is cooked: take it out before it burns"
        end
    elseif ct > 0 and item:getHeat() > 1.6 then
        if ct >= mtc * 0.5 and stage < 2 then
            stage, say = 2, name .. ", half cooked"
        elseif stage < 1 then
            stage, say = 1, name .. " cooking, in the " .. where(c)
        end
    end
    CK.seen[id] = stage
    if say then
        if stage >= 3 then ZA.say(say) else ZA.queue(say) end
    end
end

function CK.tick()
    local t = getTimestampMs()
    if t < CK.nextScan then return end
    CK.nextScan = t + 1000
    local p = getPlayer()
    if not p or p:isDead() or not ZA.S.inWorld() then return end
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    local cell = getCell()
    for x = px - CK.range, px + CK.range do
        for y = py - CK.range, py + CK.range do
            local sq = cell:getGridSquare(x, y, pz)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    local n = o:getContainerCount()
                    for k = 0, (n or 0) - 1 do
                        local c = o:getContainerByIndex(k)
                        if c and c:getTemperature() > 1.0 then
                            local items = c:getItems()
                            for j = 0, items:size() - 1 do
                                local it = items:get(j)
                                if instanceof(it, "Food") and it:isIsCookable() then follow(it, c) end
                            end
                        end
                    end
                end
            end
        end
    end
end
if not CK.ticking then
    CK.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(CK.tick)
        if not ok and not CK.errSaid then CK.errSaid = true; print("[ZA] cooking error: " .. tostring(err)) end
    end)
end
