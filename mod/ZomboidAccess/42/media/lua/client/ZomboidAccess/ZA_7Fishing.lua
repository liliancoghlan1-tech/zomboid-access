-- Zomboid Access: fishing by ear. B42 fishing with a pad: a rod in your hands, aim the right stick at water, R2
-- casts, wait for a bite, then turn the right stick in circles CLOCKWISE to reel (anticlockwise lets line out),
-- keeping the line's tension in the middle: too tight and it snaps, too slack and the fish gets away. Circle stops.
-- A sighted player watches a tension bar and the bobber; this says:
--   "Aiming at water, R2 casts" (once each time), "Line out, 8 metres. Wait for a bite."
--   A bite: za_bite.wav (two water plips) at once, then "Bite! Turn the right stick clockwise in circles to reel."
--   Reeling: "Tight! Ease off" / "Slack, keep reeling" (at most every 0.8 s), the distance every 2 metres.
--   "Landed it", "It got away", "The line broke".
-- From Fishing.ManagerInstances[player number]: state (None, Idle, Cast, Wait, ReelIn, ReelOut, PickupFish),
-- fishingRod (getTension: -1 slack .. +1 tight; the game breaks or loses the fish past +-0.8), bobber, bobber.fish.

ZA.FI = ZA.FI or {}
local FI = ZA.FI

local function manager()
    local p = getPlayer()
    if not p or not Fishing or not Fishing.ManagerInstances then return nil end
    return Fishing.ManagerInstances[p:getPlayerNum()]
end

local function stateName(m)
    if not m or not m.state then return nil end
    for k, v in pairs(m.states) do if v == m.state then return k end end
    return nil
end

local function play(name)
    pcall(function()
        local p = getPlayer()
        getSoundManager():PlayWorldSoundImpl(name, false, math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), 0, 40, 1, false)
    end)
end

function FI.tick()
    local m = manager()
    local st = stateName(m)
    local t = getTimestampMs()
    local rod = m and m.fishingRod
    local bob = rod and rod.bobber
    local fish = bob and bob.fish

    if st ~= FI.state then
        local was = FI.state
        FI.state = st
        if st == "Idle" and was ~= "Idle" then ZA.say("Aiming at water. {R2} casts.")
        elseif st == "Wait" and (was == "Cast" or was == "Idle") then
            local d = bob and math.floor(IsoUtils.DistanceTo(getPlayer():getX(), getPlayer():getY(), bob:getX(), bob:getY()) + 0.5)
            ZA.say("Line out" .. (d and (", " .. d .. " metres") or "") .. ". Wait for a bite.")
        elseif st == "PickupFish" then
            FI.landed = (FI.landed or 0) + 1
            ZA.say("Landed it. It goes in your bag.")
        elseif (st == "None" or st == nil) and (was == "Wait" or was == "ReelIn" or was == "ReelOut") then
            -- the line broke if the rod in your hands isn't a whole rod any more
            local rodNow = getPlayer():getPrimaryHandItem()
            if not (rodNow and rodNow:hasTag(ItemTag.FISHING_ROD)) then ZA.say("The line broke.")
            else ZA.say("Stopped fishing.") end
        end
        FI.lastDist = nil
    end

    -- a bite, and losing it
    if fish ~= FI.fish then
        if fish and not FI.fish then
            play("ZA_Bite")
            ZA.say("Bite! Turn the right stick clockwise in circles to reel.")
        elseif FI.fish and not fish and (st == "Wait" or st == "ReelIn" or st == "ReelOut") then
            ZA.say("It got away.")
        end
        FI.fish = fish
    end

    -- reeling: tension and distance
    if bob and (st == "ReelIn" or st == "ReelOut" or (st == "Wait" and fish)) and t >= (FI.nextTension or 0) then
        local ok, ten = pcall(function() return rod:getTension() end)
        if ok and ten then
            if ten > 0.6 then
                ZA.say("Tight! Ease off"); FI.nextTension = t + 800
            elseif ten < -0.6 and fish then
                ZA.say("Slack, keep reeling"); FI.nextTension = t + 800
            end
        end
    end
    if bob and fish then
        local d = IsoUtils.DistanceTo(getPlayer():getX(), getPlayer():getY(), bob:getX(), bob:getY())
        local band = math.floor(d / 2)
        if FI.lastDist and band < FI.lastDist and d > 1 then ZA.queue(math.floor(d + 0.5) .. " metres") end
        FI.lastDist = band
    end
end

if not FI.hooked then
    FI.hooked = true
    ZA.onTick(function()
        local ok, err = pcall(FI.tick)
        if not ok and not FI.errSaid then FI.errSaid = true; print("[ZA] fishing error: " .. tostring(err)) end
    end)
end
