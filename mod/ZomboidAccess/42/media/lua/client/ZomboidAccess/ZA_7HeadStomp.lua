-- Zomboid Access: stand at the head of a zombie on the ground (Marc, 2026-10-18).
-- With lock-on on, when the zombie it is locked on to is on the ground within 3 metres, and no other zombie is
-- standing within 3 metres, your character walks by itself to its head and faces it: a stomp (L2) or a swing
-- there hits the head, which takes three times the damage (CombatManager.applyMeleeHitLocationDamage), while the
-- legs take almost none. The dodge cue as it goes (no words), then "In place: L2 stomps". Touching the left stick stops the walk
-- (the game's own path action does it), and it all stops if the zombie gets up. RT and LT do nothing during the walk
-- (HS.syncBan), so a reflex swing doesn't cut it; a zombie standing up close stops the walk and gives them back.
--
-- Where the head is: the game reads it from the skeleton (CombatManager.getBoneWorldPos), which mods can't call.
-- But IsoGameCharacter:DoSwingCollisionBoneCheck(zombie, bone, r), which mods can call, says whether that bone of
-- the zombie, as the animation shows it now, is within r of the character it is called on. Asked with ever finer
-- r, it gives the distance from you to the head, and asked on the zombie itself, from its middle to its head.
-- Two distances put the head at one of two mirror points; which way the zombie fell picks the likely one, and on
-- arrival the distance is measured again (if the head isn't at your feet, the other point is tried).
-- Bone 6 is Bip01_Head: the skinning bones are numbered in the skeleton's order (ImportedSkeleton), which is the
-- order of SkeletonBone and of the frames in media/models_X/Skinned/MaleBody.x (Dummy01 0, Bip01 1, Pelvis 2,
-- Spine 3, Spine1 4, Neck 5, Head 6).

ZA.HS = ZA.HS or {}
local HS = ZA.HS
local S = ZA.S

HS.HEAD = 6
HS.trigger = 3.0     -- metres: a zombie on the ground this close sends you to its head (2 until 2026-10-19: a hit
                     -- knocks it back, and it often lay 2 to 3 metres off, too far)
HS.clear = 3.0       -- metres: no other zombie standing this close
HS.beyond = 0.35     -- metres: where you stand, past the head on the side away from the body
HS.placed = 0.55     -- metres: head this close to you counts as in place (the stomp reaches under 0.6)
HS.maxWalk = 8000    -- ms: a walk to a head that takes longer than this is given up

local function log(t) ZA.log("[ZA] head stomp: " .. t) end

-- Distance from `ref` (a character) to `bone` of zombie z, from the game's own skeleton; nil if it can't be read.
local function boneDist(ref, z, bone)
    local function within(r)
        local ok, res = pcall(function() return ref:DoSwingCollisionBoneCheck(z, bone, r) end)
        if not ok then return nil end
        return res
    end
    local hi = 4.5   -- (a zombie up to 3 m off, HS.trigger, can have its head a body length further)
    local far = within(hi)
    if far == nil or far == false then return nil end
    local lo = 0
    for _ = 1, 14 do
        local mid = (lo + hi) / 2
        if within(mid) then hi = mid else lo = mid end
    end
    return hi
end
HS.boneDist = boneDist

local function down(z)
    local d = false
    pcall(function() d = z:isProne() or z:isOnFloor() end)
    return d
end

local function standingNear(p, except)
    local zl = getCell():getZombieList()
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and z ~= except and not z:isDead() and math.floor(z:getZ()) == math.floor(p:getZ()) and not down(z) then
            local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
            if dx * dx + dy * dy <= HS.clear * HS.clear then return true end
        end
    end
    return false
end

-- The two points where the head can be, the likely one first.
local function headPoints(p, z)
    local d1 = boneDist(p, z, HS.HEAD)       -- you to the head
    local d2 = boneDist(z, z, HS.HEAD)       -- its middle to its head
    if not d1 or not d2 then return nil end
    if d2 < 0.2 or d2 > 1.6 then log("odd head distance " .. tostring(d2)); return nil end
    local px, py, zx, zy = p:getX(), p:getY(), z:getX(), z:getY()
    local D = math.sqrt((zx - px) ^ 2 + (zy - py) ^ 2)
    if D < 0.05 then return nil end
    local ux, uy = (zx - px) / D, (zy - py) / D
    local a = (d1 * d1 - d2 * d2 + D * D) / (2 * D)
    local h = math.sqrt(math.max(0, d1 * d1 - a * a))
    local mx, my = px + a * ux, py + a * uy
    local c1 = { x = mx - h * uy, y = my + h * ux }
    local c2 = { x = mx + h * uy, y = my - h * ux }
    -- which way it fell: on its back the head lies behind where it faced, on its front ahead of it
    local fx, fy = 0, 0
    pcall(function() local v = z:getForwardDirection(); fx, fy = v:getX(), v:getY() end)
    local front = false
    pcall(function() front = z:isFallOnFront() end)
    local s = front and 0.8 or -0.8
    local gx, gy = zx + fx * s, zy + fy * s
    local function off(c) return (c.x - gx) ^ 2 + (c.y - gy) ^ 2 end
    log(string.format("you-head %.2f, middle-head %.2f, apart %.2f, %s", d1, d2, D, front and "on its front" or "on its back"))
    if off(c2) < off(c1) then c1, c2 = c2, c1 end
    if h < 0.05 then return { c1 } end
    return { c1, c2 }
end

-- Where to stand for a head: a little past it, away from the body, so you face the head over the body's line.
local function spotFor(z, hx, hy)
    local zx, zy = z:getX(), z:getY()
    local dx, dy = hx - zx, hy - zy
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 0.01 then return hx, hy end
    return hx + dx / l * HS.beyond, hy + dy / l * HS.beyond
end

local function stopWalk()
    if HS.action then pcall(function() HS.action:forceStop() end) end
    HS.action = nil
end

local function walkTo(p, x, y)
    -- lock-on holds the aim for you; let it go, or the walk can be dropped at once
    pcall(function() if p:isForceAim() then p:setForceAim(false) end end)
    local a = ISPathFindAction:pathToLocationF(p, x, y, p:getZ())
    HS.action, HS.spot, HS.walkAt = a, { x = x, y = y }, getTimestampMs()
    ISTimedActionQueue.add(a)
end

local function walking(p)
    if not HS.action then return false end
    local q = ISTimedActionQueue.getTimedActionQueue(p)
    return q and q:indexOf(HS.action) > 0
end

-- Is z the zombie this module is handling right now (lock-on keeps quiet about it then)?
function HS.handles(z)
    return z ~= nil and z == HS.target and (HS.phase == "walking" or HS.phase == "retry" or HS.phase == "placed")
end

-- Will this module take z on at its next turn (so lock-on shouldn't start guiding you to it)?
function HS.wants(p, z)
    if HS.target and HS.target ~= z then return false end
    if HS.phase and HS.phase ~= "walking" and HS.phase ~= "placed" then return false end
    if not down(z) then return false end
    local dx, dy = z:getX() - p:getX(), z:getY() - p:getY()
    return dx * dx + dy * dy <= HS.trigger * HS.trigger and not standingNear(p, z)
end

local function reset()
    if HS.phase == "walking" then stopWalk() end
    HS.target, HS.phase, HS.points, HS.try, HS.userMoved, HS.retries = nil, nil, nil, nil, nil, nil
end

local function arrive(p, z)
    local d = boneDist(p, z, HS.HEAD)
    log("arrived, head at " .. tostring(d))
    if d and d <= HS.placed then
        HS.phase = "placed"
        pcall(function() p:faceThisObject(z) end)
        ZA.urgent(ZA.tr("HeadStomp_Placed"))
        return
    end
    -- not at the head: the other point, once
    if HS.points and HS.try < #HS.points then
        HS.try = HS.try + 1
        local c = HS.points[HS.try]
        walkTo(p, spotFor(z, c.x, c.y))
        return
    end
    HS.phase = "failed"
    ZA.urgent(ZA.tr("HeadStomp_Failed"))
end

function HS.tick()
    local p = getPlayer()
    local LK = ZA.LK
    if not p or p:isDead() or p:getVehicle() or not (LK and LK.isOn and LK.isOn()) then
        if HS.target then reset() end
        return
    end
    local t = LK.target
    -- the one being handled got up, died, changed, or lock-on let go: stop. "Got up" only after 0.6 s off the ground:
    -- a swing landing on it as the walk starts reads it off the ground for a moment (in game 2026-10-20: the walk
    -- given up twice within a quarter of a second, each time just after "Hit, down", the zombie still lying there)
    local up = false
    if HS.target and not down(HS.target) then
        HS.upSince = HS.upSince or getTimestampMs()
        up = getTimestampMs() - HS.upSince > 600
    else
        HS.upSince = nil
    end
    if HS.target and (t ~= HS.target or HS.target:isDead() or up) then
        if up then log("it got up") elseif t ~= HS.target then log("lock-on moved to another zombie") end
        reset()
        HS.upSince = nil
    end
    if not t or not down(t) or t:isDead() then HS.settling = nil; return end
    local d = math.sqrt((t:getX() - p:getX()) ^ 2 + (t:getY() - p:getY()) ^ 2)

    -- your swings are held back during the walk (see HS.syncBan): so if a zombie gets up close to you meanwhile, or
    -- the walk drags on, stop it and give your swings back
    if (HS.phase == "walking" or HS.phase == "retry")
        and (standingNear(p, t) or getTimestampMs() - (HS.startAt or 0) > HS.maxWalk) then
        log("walk stopped: a zombie standing close, or too long")
        stopWalk()
        HS.phase = "stopped"
        return
    end

    if HS.phase == "walking" then
        local pushed = false
        pcall(function() pushed = p:pressedMovement(false) end)
        if pushed then HS.userMoved = true end
        pcall(function() if p:isAttackStarted() then HS.attacked = true end end)
        if not walking(p) then
            HS.action = nil
            local sx, sy = HS.spot.x - p:getX(), HS.spot.y - p:getY()
            if sx * sx + sy * sy > 0.6 * 0.6 then
                -- you took over with the stick: leave it to you
                if HS.userMoved then HS.phase = "stopped"; log("stopped by the stick"); return end
                -- dropped at once (in game 2026-10-19: twice in a row, right after a swing, then fine on the next
                -- fall): the character was still busy; try the same point again, up to 3 times
                -- A swing or a shove of yours cancels the walk (in game 2026-10-19: four tries, each cut by a swing):
                -- those don't count, as long as it's within 6 seconds of the start.
                local cut = HS.attacked
                HS.attacked = false
                if cut and getTimestampMs() - (HS.startAt or 0) < 6000 then
                    HS.phase, HS.retryAt = "retry", getTimestampMs() + 300
                    log("walk cut by a swing, again once it's over")
                    return
                end
                if getTimestampMs() - (HS.walkAt or 0) < 600 and (HS.retries or 0) < 3 then
                    HS.retries = (HS.retries or 0) + 1
                    HS.phase, HS.retryAt = "retry", getTimestampMs() + 400
                    log("walk dropped at once, again in a moment (" .. HS.retries .. ")")
                    return
                end
                -- no way to that spot: the other point, else give up
                log("no way to the spot")
                if HS.points and HS.try < #HS.points then
                    HS.try = HS.try + 1
                    local c = HS.points[HS.try]
                    walkTo(p, spotFor(t, c.x, c.y))
                else
                    HS.phase = "failed"
                    ZA.urgent(ZA.tr("HeadStomp_Failed"))
                end
                return
            end
            arrive(p, t)
        end
        return
    end
    if HS.phase == "retry" then
        -- once the character is free (not swinging, not in another action), walk to the same point again
        local busy = false
        pcall(function() busy = p:isAttackStarted() or p:isPerformingAnAction() end)
        if getTimestampMs() < HS.retryAt or busy then return end
        HS.phase = "walking"
        local c = HS.points[HS.try]
        walkTo(p, spotFor(t, c.x, c.y))
        return
    end
    if HS.phase then return end    -- placed, failed or stopped: once per zombie on the ground

    -- why not now, logged once per zombie on the ground and reason (in game 2026-10-19: falls with no walk and no
    -- way to tell why from the log)
    local function notYet(why)
        if HS.whyFor ~= t or HS.why ~= why then
            HS.whyFor, HS.why = t, why
            log(string.format("not yet: %s (%.1f m)", why, d))
        end
    end
    if d > HS.trigger then notYet("too far"); return end
    if standingNear(p, t) then notYet("a zombie standing close"); return end
    local moving = false
    pcall(function() moving = p:isPlayerMoving() end)
    if moving then notYet("you are moving"); return end
    if p:isPerformingAnAction() then notYet("you are busy"); return end
    -- A swing going on no longer holds it back (in game 2026-10-19 RT was pressed about every second, so there was
    -- never a moment without one): the walk starts, your swings are held back from then on (HS.syncBan), and if the
    -- swing still going cuts it, it starts again once that swing is over.

    -- Still falling: the game calls it on the ground at once, but its body takes about a second to lie flat (in
    -- game 2026-10-19, 0.2 s after the fall: head 0.14 m from its middle, legs still in the air). Wait until the
    -- head lies away from the middle and stops moving, up to 3 seconds.
    local now = getTimestampMs()
    if HS.settling ~= t then HS.settling, HS.settleSince, HS.lastHead, HS.nextLook = t, now, nil, 0 end
    if now < HS.nextLook then return end
    HS.nextLook = now + 150
    local mid = boneDist(t, t, HS.HEAD)
    local settled = mid and mid >= 0.35 and HS.lastHead and math.abs(mid - HS.lastHead) < 0.03
    HS.lastHead = mid
    if not settled then
        if now - HS.settleSince < 3000 then return end
        log("never settled, head from middle " .. tostring(mid))
    end
    HS.settling = nil

    HS.target = t
    -- already at its head?
    local hd = boneDist(p, t, HS.HEAD)
    if hd and hd <= HS.placed then
        HS.phase = "placed"
        pcall(function() p:faceThisObject(t) end)
        ZA.urgent(ZA.tr("HeadStomp_Placed"))
        return
    end
    HS.points = headPoints(p, t)
    if not HS.points then
        HS.phase = "failed"
        log("head not readable")
        -- developer log (2026-10-19: bone 6 read 0.137 m from the middle on every zombie on the ground, so it isn't
        -- the head as the animation shows it): every bone's distance from the zombie's middle and from you, once,
        -- to find which bone moves with the head
        if ZA.dev then
            local parts = {}
            for b = 0, 45 do
                local dz, dp = boneDist(t, t, b), boneDist(p, t, b)
                table.insert(parts, b .. "=" .. (dz and string.format("%.2f", dz) or "-") .. "/" .. (dp and string.format("%.2f", dp) or "-"))
            end
            log(string.format("bones (from its middle / from you, %.2f m apart, fell on its %s): ", d,
                (pcall(function() return t:isFallOnFront() end) and t:isFallOnFront()) and "front" or "back") .. table.concat(parts, " "))
        end
        return
    end
    HS.try = 1
    HS.phase, HS.startAt, HS.attacked = "walking", getTimestampMs(), false
    -- a cue as the walk starts (Marc, 2026-10-19: WitcherAccess's dodge sound, plugin/sounds/dodge.wav), heard only
    -- by you, so you know to hold your swings
    pcall(function()
        getSoundManager():PlayWorldSoundImpl("ZA_HeadGo", false, math.floor(p:getX()), math.floor(p:getY()),
            math.floor(p:getZ()), 0, 40, 1, false)
    end)
    -- the cue alone: no words (Marc, 2026-10-19)
    walkTo(p, spotFor(t, HS.points[1].x, HS.points[1].y))
end

-- While walking to a head, RT and LT do nothing (Marc, 2026-10-19: in game every RT press cut the walk, four times in
-- a row, and the zombie was never reached): the game's own switch, IsoPlayer:setBannedAttacking, the one it uses
-- while the inventory or the map is open, stops swings, shoves and stomps. It is let go as soon as the walk is over
-- (in place, failed, stopped, the zombie got up, lock-on off...), and only if this module was the one that set it.
function HS.syncBan()
    local p = getPlayer()
    local want = p ~= nil and not p:isDead() and (HS.phase == "walking" or HS.phase == "retry")
    if want and not HS.banned then
        if not p:isBannedAttacking() then
            p:setBannedAttacking(true)
            HS.banned = true
            log("swings held back during the walk")
        end
    elseif not want and HS.banned then
        HS.banned = false
        if p and p:isBannedAttacking() then p:setBannedAttacking(false) end
        log("swings given back")
    end
end

function HS.frame()
    local ok, err = pcall(HS.tick)
    if not ok and not HS.errSaid then HS.errSaid = true; print("[ZA] head stomp error: " .. tostring(err)) end
    -- after the tick whatever happened in it, an error too: swings must never stay held back
    local ok2, err2 = pcall(HS.syncBan)
    if not ok2 and not HS.banErrSaid then HS.banErrSaid = true; print("[ZA] head stomp ban error: " .. tostring(err2)) end
end

if not HS.ticking then
    HS.ticking = true
    ZA.onTick(function() HS.frame() end)   -- looked up each frame, so a reload of this file takes effect
end
