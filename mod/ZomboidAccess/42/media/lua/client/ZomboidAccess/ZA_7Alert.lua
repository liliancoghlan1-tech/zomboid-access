-- Zomboid Access: zombie warnings, always on (scanner on or off).
--   A zombie starts chasing you   "Zombie chasing you, 8 metres up-right. 3 chasing."
--   A zombie gets very close      "Zombie right next to you, left." (once, until it moves away again)
--   The last chaser gives up      "Nothing chasing you now."
-- Warnings interrupt other speech: they matter more than anything else being said.

ZA.A = ZA.A or {}
local A = ZA.A
local S = ZA.S

A.range = 40          -- metres: chasers further away than this are not announced
A.close = 3           -- metres: "right next to you"
A.chasers = {}        -- zombie -> true, for those already announced
A.closeWarned = {}
A.nextCheck = 0
A.lastSaid = 0

local function chasing(z, p)
    local ok, r = pcall(function() return z:getTarget() == p end)
    return ok and r
end

function A.check()
    local p = getPlayer()
    if not p or p:isDead() or not S.inWorld() then
        A.chasers, A.closeWarned = {}, {}
        return
    end
    local px, py, pz = p:getX(), p:getY(), math.floor(p:getZ())
    local zl = getCell():getZombieList()
    local now = {}
    local count = 0
    local newOnes, nearestNew, nearestNewD = 0, nil, nil
    local closest, closestD = nil, nil
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and math.abs(math.floor(z:getZ()) - pz) <= 1 then
            local d = math.sqrt((z:getX() - px) ^ 2 + (z:getY() - py) ^ 2)
            if d <= A.range and chasing(z, p) then
                now[z] = true
                count = count + 1
                if not A.chasers[z] then
                    newOnes = newOnes + 1
                    if not nearestNewD or d < nearestNewD then nearestNew, nearestNewD = z, d end
                end
            end
            if d <= A.close and math.floor(z:getZ()) == pz and not A.closeWarned[z] then
                if not closestD or d < closestD then closest, closestD = z, d end
            end
            if A.closeWarned[z] and d > A.close + 2 then A.closeWarned[z] = nil end
        end
    end
    local hadChasers = false
    for _ in pairs(A.chasers) do hadChasers = true; break end   -- Kahlua has no next()
    A.chasers = now

    if closest then
        A.closeWarned[closest] = true
        A.say("Zombie right next to you, " .. (S.direction(closest:getX() - px, closest:getY() - py) ~= "" and S.direction(closest:getX() - px, closest:getY() - py) or "here") .. ".")
        return
    end
    if newOnes > 0 then
        local where = S.where(nearestNew:getX(), nearestNew:getY(), nearestNew:getZ())
        local text
        if newOnes == 1 then text = "Zombie chasing you, " .. where
        else text = newOnes .. " zombies chasing you, nearest " .. where end
        if count > newOnes then text = text .. ". " .. count .. " chasing" end
        A.say(text .. "." .. (ZA.CB and ZA.CB.firstChase() or ""))
        return
    end
    if hadChasers and count == 0 then
        A.say("Nothing chasing you now.")
    end
end

function A.say(text)
    A.lastSaid = getTimestampMs()
    print("[ZA] alert: " .. text)
    ZA.say(text)
end

if not A.ticking then
    A.ticking = true
    ZA.onTick(function()
        local t = getTimestampMs()
        if t < A.nextCheck then return end
        A.nextCheck = t + 300
        local ok, err = pcall(A.check)
        if not ok then print("[ZA] alert error: " .. tostring(err)) end
    end)
end

Events.OnGameStart.Add(function() A.chasers, A.closeWarned = {}, {} end)
