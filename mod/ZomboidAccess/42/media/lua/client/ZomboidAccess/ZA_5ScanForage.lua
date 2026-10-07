-- Zomboid Access: foraging (B42 search mode). The game's own way in with a pad: hold Share, "Enable search mode";
-- the same wheel offers "Pick up" for the nearest find. What a sighted player sees, and this adds:
--   "Search mode on" / "off". "You sense something nearby" when the game starts spotting a find (the eye icon a
--     sighted player sees brighten; it gives no direction, so neither does this).
--   Each find the character notices, said once: "Noticed: Blackberries, 4 metres up-left" (unidentified finds are
--     "something", as the game shows them, until you're close enough or skilled enough to tell).
--   The scanner's "Finds" category (after Loot): the noticed finds, nearest first. Square walks there; hold Square
--     (Delete) picks it up, the game's own forage action (ISForageIcon:doForage walks next to it first).
-- From ISSearchManager.getManager(player).activeIcons: icons with getIsSeen() are the ones the game shows.

local S = ZA.S
ZA.FG = ZA.FG or {}
local FG = ZA.FG

local inserted = false
for _, c in ipairs(S.categories) do if c.key == "finds" then inserted = true end end
if not inserted then
    for i, c in ipairs(S.categories) do
        if c.key == "loot_other" then
            table.insert(S.categories, i + 1, { key = "finds", name = "Finds",
                none = "nothing found. Hold Share and choose Enable search mode, then walk slowly" })
            break
        end
    end
end

local function manager()
    local p = getPlayer()
    if not p then return nil end -- menus: the game's own manager throws (and logs a stack) without a player
    local ok, m = pcall(function() return ISSearchManager.getManager(p) end)
    return ok and m or nil
end

function FG.name(icon)
    local n
    pcall(function()
        if icon.identified then
            if icon.itemList and not icon.itemList:isEmpty() and icon.itemList:get(0) then
                n = icon.itemList:get(0):getDisplayName()
            elseif icon.itemObj then
                n = icon.itemObj:getDisplayName()
            end
        end
    end)
    if not n or n == "" then n = "Something you can't make out yet" end
    pcall(function()
        local c = icon.itemList and icon.itemList:size() or 1
        if c > 1 then n = n .. ", " .. c end
    end)
    return n
end

local function seenIcons()
    local m = manager()
    local out = {}
    if not m or not m.activeIcons then return out end
    for id, icon in pairs(m.activeIcons) do
        local ok, seen = pcall(function() return icon:getIsSeen() and icon:getAlpha() > 0 end)
        if ok and seen and icon.xCoord then table.insert(out, { id = id, icon = icon }) end
    end
    return out
end

table.insert(S.postBuilders, function(lists)
    lists.finds = lists.finds or {}
    for _, f in ipairs(seenIcons()) do
        local icon = f.icon
        table.insert(lists.finds, {
            cat = "finds", key = "finds|" .. tostring(f.id), baseName = "find", icon = icon,
            name = function(e) return FG.name(e.icon) end,
            x = icon.xCoord + 0.5, y = icon.yCoord + 0.5, z = icon.zCoord or 0, walk = "onto",
            alive = function(e)
                local m = manager()
                return m ~= nil and m.activeIcons ~= nil and m.activeIcons[f.id] == e.icon
            end,
        })
    end
end)

-- hold Square / Delete on a find: pick it up (ZA_6WalkUse sends finds here)
function FG.pickUp(e)
    local ok, err = pcall(function() e.icon:doForage(nil, nil, nil, nil) end)
    if not ok then print("[ZA] forage error: " .. tostring(err)); ZA.say("Couldn't pick that up.") return end
    FG.picked = (FG.picked or 0) + 1
    ZA.say("Picking up " .. FG.name(e.icon) .. ".")
end

-- ---------- said by itself ----------

FG.said = {}
FG.sensed = {}
FG.nextCheck = 0
function FG.tick()
    local t = getTimestampMs()
    if t < FG.nextCheck then return end
    FG.nextCheck = t + 500
    local m = manager()
    if not m then return end
    local on = m.isSearchMode == true
    if FG.on ~= nil and on ~= FG.on then
        ZA.say(on and "Search mode on. Walk slowly; what you notice is said, and listed in the scanner under Finds."
            or "Search mode off.")
    end
    FG.on = on
    if not on then return end
    -- the eye a sighted player watches brightens while the character is spotting something: say that much
    local sp = m.isSpotting
    if sp and sp ~= FG.spotting and not FG.said[sp] and not FG.sensed[sp] then
        FG.sensed[sp] = true
        ZA.queue("You sense something nearby")
    end
    FG.spotting = sp
    for _, f in ipairs(seenIcons()) do
        if not FG.said[f.icon] then
            FG.said[f.icon] = true
            local x, y, z = f.icon.xCoord + 0.5, f.icon.yCoord + 0.5, f.icon.zCoord or 0
            ZA.queue("Noticed: " .. FG.name(f.icon) .. ", " .. (S.where(x, y, z)))
        end
    end
end
if not FG.ticking then
    FG.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(FG.tick)
        if not ok and not FG.errSaid then FG.errSaid = true; print("[ZA] forage tick error: " .. tostring(err)) end
    end)
end
