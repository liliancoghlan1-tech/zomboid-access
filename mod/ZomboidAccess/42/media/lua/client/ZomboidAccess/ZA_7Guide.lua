-- Zomboid Access: guide mode, for walking somewhere yourself (Shift+End on the thing selected in the scanner).
-- The thing makes a beacon sound from where it is (faster as you get closer), and when the way to push the
-- stick changes, the mod says it ("up-left, 6 metres"). Walking into something says "Blocked".
-- The beacon is a sound only you hear: it is not a noise in the game world, so zombies don't come to it.
-- It points in a straight line, through walls: use the Doors category to find the way out of a room.
-- Shift+End again stops it; it also stops on arrival.

ZA.G = ZA.G or {}
local G = ZA.G
local S = ZA.S

G.sound = "ZA_Chime"   -- our own soft bell (media/sound/za_chime.wav), played at the target so it comes from its direction
G.entry = nil

local function now() return getTimestampMs() end

function G.stop(text)
    G.entry = nil
    if text then ZA.say(text) end
end

function G.start()
    local e = S.current()
    if not e then ZA.say("Nothing selected. Use Page Down to pick something first."); return end
    if not S.alive(e) then ZA.say(S.entryName(e) .. " is gone."); return end
    if e.noWhere then ZA.say("That's about you; pick a place in another category."); return end
    if ZA.W and ZA.W.action then ZA.W.stop(true) end
    local p = getPlayer()
    G.entry = e
    G.lastDir, G.pendingDir, G.pendingSince, G.lastSaid = nil, nil, 0, now()
    G.nextBeep = 0
    G.lastX, G.lastY, G.stuckSince, G.saidBlocked = p:getX(), p:getY(), nil, false
    local x, y, z = S.entryPos(e)
    local w, d, dz = S.where(x, y, z)
    G.lastDir = S.direction(x - p:getX(), y - p:getY())
    G.lastBand = math.floor(d / 5)
    local extra = ""
    if dz ~= 0 then extra = " It's on another floor: find the stairs first." end
    print("[ZA] guide to " .. e.key)
    ZA.say("Guiding you to " .. S.entryName(e) .. ", " .. w .. "." .. extra .. " Hold {Triangle}, or Shift End, to stop.")
end

function G.toggle()
    if G.entry then G.stop("Guide off.") else G.start() end
end

local function beep(x, y, z)
    local ok, err = pcall(function()
        getSoundManager():PlayWorldSoundImpl(G.sound, false, math.floor(x), math.floor(y), math.floor(z), 0, 30, 1, false)
    end)
    if not ok and not G.beepError then
        G.beepError = true
        print("[ZA] guide beep error: " .. tostring(err))
    end
end

function G.tick()
    local e = G.entry
    if not e then return end
    local p = getPlayer()
    if not p or p:isDead() then G.entry = nil; return end
    if not S.alive(e) then G.stop(S.entryName(e) .. " is gone. Guide off."); return end
    local t = now()
    -- a zombie close by: say it once (and again if it goes away and comes back)
    if t >= (G.nextThreatCheck or 0) then
        G.nextThreatCheck = t + 250
        local zz = S.nearestThreat(6, 2.5)
        if zz and zz ~= G.warned then
            G.warned = zz
            ZA.say("Careful! " .. S.threatText(zz) .. ".")
            G.lastSaid = t
        elseif not zz then
            G.warned = nil
        end
    end
    local x, y, z = S.entryPos(e)
    local dx, dy = x - p:getX(), y - p:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    local sameFloor = math.floor(z) == math.floor(p:getZ())

    local reach = e.far and (e.key:find("|town|", 1, true) and 80 or 3) or 1.6
    if (sameFloor or e.far) and d <= reach then
        print("[ZA] guide arrived " .. e.key)
        G.stop("Arrived: " .. S.entryName(e) .. ". Guide off.")
        return
    end

    -- beacon: every 1.4 seconds far away, down to 0.35 seconds close by
    if t >= G.nextBeep then
        -- far away (a place across town): the beep comes from 15 metres ahead in its direction,
        -- since a sound further off is too quiet to hear
        if d > 25 then
            beep(p:getX() + dx / d * 15, p:getY() + dy / d * 15, p:getZ())
        else
            beep(x, y, z)
        end
        local gap = math.max(350, math.min(1400, d * 70))
        G.nextBeep = t + gap
    end

    -- direction: say it when it has changed and held for half a second (no chatter while turning)
    local dir = S.direction(dx, dy)
    if dir ~= G.lastDir then
        if dir ~= G.pendingDir then G.pendingDir, G.pendingSince = dir, t end
        if t - G.pendingSince >= 500 and t - G.lastSaid >= 1200 then
            G.lastDir, G.lastSaid = dir, t
            G.lastBand = math.floor(d / 5)
            ZA.say(dir .. ", " .. math.floor(d + 0.5))
        end
    else
        G.pendingDir = nil
        -- every 5 metres closer, a short distance update
        local band = math.floor(d / 5)
        if band < (G.lastBand or band) and t - G.lastSaid >= 1200 then
            G.lastBand, G.lastSaid = band, t
            ZA.say(math.floor(d + 0.5) .. " metres")
        end
    end

    -- blocked: pushing the stick but not moving for most of a second
    local moving = false
    pcall(function() moving = p:pressedMovement(false) end)
    local moved = math.abs(p:getX() - G.lastX) + math.abs(p:getY() - G.lastY)
    if moved > 0.05 then
        G.lastX, G.lastY, G.stuckSince, G.saidBlocked = p:getX(), p:getY(), nil, false
    elseif moving then
        G.stuckSince = G.stuckSince or t
        if not G.saidBlocked and t - G.stuckSince > 800 then
            G.saidBlocked = true
            ZA.say("Blocked.")
        end
    else
        G.stuckSince = nil
    end
end

if not G.ticking then
    G.ticking = true
    ZA.onTick(function() G.tick() end)
end

function G.onKey(key)
    if key ~= Keyboard.KEY_END or not (isCtrlKeyDown() or isShiftKeyDown()) or not S.inWorld() then return end
    local ok, err = pcall(G.toggle)
    if not ok then print("[ZA] guide key error: " .. tostring(err)) end
end
if not G.hooked then
    G.hooked = true
    Events.OnKeyPressed.Add(function(key) G.onKey(key) end)
end

-- A new world or a load: no guide left running from the old place.
Events.OnGameStart.Add(function() G.entry = nil end)
