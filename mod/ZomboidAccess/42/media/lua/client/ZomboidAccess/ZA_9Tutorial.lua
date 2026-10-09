-- Zomboid Access tutorial (Lilian's idea, 2026-10-02): a controlled world where a guide on the radio teaches the
-- game and the mod, one system after another, simple to complex.
--   Started from the main menu: New game, Challenges, "Zomboid Access Tutorial" (the game's own challenge system,
--   like Top of the World). No zombies unless a lesson puts them there. Its own world: real saves are never touched.
--   Each step: the guide says something (after a radio crackle, za_radio.wav), maybe sets something up, and waits
--   until you've done it; stuck for 40 seconds, a hint. Where you are in the lessons is kept in the save.
--   The You list starts with "Radio: say that again".
-- The guide's words are in ZA_9TutorialLines.lua.

ZA.TU = ZA.TU or {}
local TU = ZA.TU
local S = ZA.S

-- An isolated house with river water 17 squares off and a road 37 off, found by tools/find_tutorial_spot.py.
TU.home = { x = 8789, y = 15233, z = 0 }

-- ---------- the challenge ----------

TU.challenge = {
    id = "ZomboidAccessTutorial",
    gameMode = "Zomboid Access Tutorial",
    world = "Muldraugh, KY",
    x = TU.home.x, y = TU.home.y, z = 0,
    hourOfDay = 9,
    image = "media/lua/client/LastStand/top_of_the_world.png",
}
local C = TU.challenge

C.Add = function()
    addChallenge(C)
    C.name = "Zomboid Access Tutorial"
    C.description = "A quiet house by the river, no zombies until a lesson brings one, and a guide on the radio who "
        .. "talks you through the game and the accessibility mod, one thing at a time."
end

C.OnInitWorld = function()
    -- no zombies of its own, but lessons may place some: "None" (6) makes the game refuse every zombie, a mod's too
    -- (IsoWorld.getZombiesDisabled, decompiled), so "Low" with the population multiplied by nothing
    SandboxVars.Zombies = 5
    SandboxVars.ZombieRespawn = 4
    SandboxVars.ZombieMigrate = false
    pcall(function()
        SandboxVars.ZombieConfig.PopulationMultiplier = 0.0
        SandboxVars.ZombieConfig.PopulationStartMultiplier = 0.0
        SandboxVars.ZombieConfig.PopulationPeakMultiplier = 0.0
        SandboxVars.ZombieConfig.RespawnHours = 0.0
    end)
    SandboxVars.StartMonth = 7
    SandboxVars.StartDay = 9
    SandboxVars.StartTime = 2                 -- morning
    SandboxVars.WaterShut = 7                 -- water and power never go off here
    SandboxVars.ElecShut = 7
    SandboxVars.StarterKit = false
    SandboxVars.Helicopter = 1
    SandboxVars.MetaEvent = 1
end

C.OnGameStart = function() end
C.RemovePlayer = function() end
C.AddPlayer = function() end
C.Render = function() end

if not TU.registered then
    TU.registered = true
    Events.OnChallengeQuery.Add(C.Add)
end

-- The game's own TUTORIAL (main menu, or the first-launch "play the tutorial?" box) clears the mod list and
-- reloads Lua without mods (MainScreen.startTutorial), so this mod would go silent for the whole tutorial.
-- Every way into it calls MainScreen.startTutorial, so start ours instead, the way NewGameScreen:clickPlay
-- starts a challenge.
function TU.startFromMainMenu()
    local ms = MainScreen and MainScreen.instance
    if not ms or not ms.soloScreen then return false end
    -- protected: the character screen opens at once, and its first words would cut this off
    ZA.protected("The game's own tutorial turns all mods off, so Zomboid Access would go silent. "
        .. "Starting the Zomboid Access Tutorial instead.")
    ActiveMods.getById("currentGame"):copyFrom(ActiveMods.getById("default"))
    local ng = ms.soloScreen
    ng:setVisible(true, JoypadState.getMainMenuJoypad())
    C.name = C.name or "Zomboid Access Tutorial"
    ng.selectedItem = { data = { mode = C.name, challenge = C } }
    ng:clickPlay()
    return true
end

if MainScreen and MainScreen.startTutorial and not TU.wrappedStart then
    TU.wrappedStart = true
    local orig = MainScreen.startTutorial
    MainScreen.startTutorial = function(...)
        local ok, started = pcall(TU.startFromMainMenu)
        if ok and started then return end
        if not ok then print("[ZA] tutorial redirect failed: " .. tostring(started)) end
        return orig(...)
    end
end

-- ---------- state ----------

local function state()
    local ok, t = pcall(function() return ModData.getOrCreate("ZATutorial") end)
    return ok and t or nil
end
function TU.active()
    local st = state()
    return st and st.active == true
end

-- ---------- the radio ----------

function TU.radio(line, queue)
    if not line or line == "" then return end
    TU.lastLine = line
    pcall(function()
        local p = getPlayer()
        getSoundManager():PlayWorldSoundImpl("ZA_Radio", false, math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), 0, 40, 1, false)
    end)
    -- the guide waits for whatever is being said, and other speech waits for the guide (a player's report:
    -- lines got cut off); only urgent danger and combat words cut in
    ZA.guide(line)
end

-- ---------- helpers for the checks ----------

local function cat() local c = S.categories[S.catIndex]; return c and c.key end
local function near(x, y, r)
    local p = getPlayer()
    return (p:getX() - x) ^ 2 + (p:getY() - y) ^ 2 <= r * r
end
local function has(fullType)
    return getPlayer():getInventory():getFirstTypeRecurse(fullType) ~= nil
end
local function doorNearOpen()
    local p = getPlayer()
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for dx = -1, 1 do for dy = -1, 1 do
        local sq = getCell():getGridSquare(px + dx, py + dy, pz)
        if sq then
            local objs = sq:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if (instanceof(o, "IsoDoor") or (instanceof(o, "IsoThumpable") and o:isDoor())) and o:IsOpen() then return true end
            end
        end
    end end
    return false
end
-- the house's first container (a kitchen one if there is): where the lessons put things
local function houseContainer()
    local h = getCell():getGridSquare(TU.home.x, TU.home.y, 0)
    local b = h and h:getBuilding()
    local best, bestKitchen
    for x = TU.home.x - 25, TU.home.x + 25 do for y = TU.home.y - 25, TU.home.y + 25 do
        local sq = getCell():getGridSquare(x, y, 0)
        if sq and sq:getRoom() and (not b or sq:getBuilding() == b) then
            local objs = sq:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if o:getContainer() and not instanceof(o, "IsoStove") and o:getContainer():getType() ~= "fridge" then
                    local room = sq:getRoom():getName() or ""
                    if room:find("kitchen") then bestKitchen = bestKitchen or o:getContainer() end
                    best = best or o:getContainer()
                end
            end
        end
    end end
    return bestKitchen or best
end
TU.houseContainer = houseContainer

-- ---------- the lessons ----------
-- step = { line = key in ZA.TUL, setup = fn, check = fn -> true when done, wait = ms (no check: go on after this) }

local L = function(k) return ZA.TUL[k] or {} end

TU.steps = {
    { line = "welcome", wait = 9000 },
    { line = "seeing", wait = 11000 },
    { line = "scannerOn", check = function() return ZA.P and ZA.P.layer end },
    { line = "scannerBrowse", check = function() return cat() == "doors" end },
    { line = "walkToDoor", check = function()
        local e = S.current()
        return e and e.cat == "doors" and near(e.x, e.y, 2.3)
    end },
    { line = "openDoor", check = doorNearOpen },
    { line = "lootFind",
      setup = function()
          local c = houseContainer()
          if c and not c:getFirstTypeRecurse("Base.Crisps") then c:AddItem("Base.Crisps") end
      end,
      check = function() return cat() == "loot_food" end },
    { line = "lootOpen", check = function()
        local ui = getPlayerLoot(0)
        local inv = ui and ui:isVisible() and ui.inventoryPane and ui.inventoryPane.inventory
        return inv and inv:getFirstTypeRecurse("Base.Crisps") ~= nil
    end },
    { line = "lootTake", check = function() return has("Base.Crisps") end },
    { line = "closeLoot", check = function()
        local jd = JoypadState.players[1]
        if jd then return jd.focus == nil end
        return not getPlayerLoot(0):isVisible()
    end },
    { line = "eat",
      setup = function() TU.setNeed("hunger", 0.3) end,
      check = function() return not has("Base.Crisps") or TU.need("hunger") < 0.2 end },
    { line = "drink",
      setup = function() TU.setNeed("thirst", 0.3) end,
      check = function() return TU.need("thirst") < 0.15 end },
    { line = "status", check = function() return TU.statusHeard end },
    { line = "youList", check = function() return cat() == "you" end },

    -- injuries and healing
    { line = "hurt", setup = function()
          local p = getPlayer()
          p:getInventory():AddItem("Base.Bandage")
          p:getInventory():AddItem("Base.AlcoholWipes")
          local bp = p:getBodyDamage():getBodyPart(BodyPartType.Hand_L)
          bp:setScratched(true, true)
          pcall(function() bp:setBleedingTime(5) end)
      end, wait = 9000 },
    { line = "healthScreen", check = function()
          local jd = JoypadState.players[1]
          local f = jd and jd.focus
          while f do
              if f.Type == "ISHealthPanel" then return true end
              f = f.parent
          end
          return false
      end },
    { line = "disinfect", check = function()
          return getPlayer():getBodyDamage():getBodyPart(BodyPartType.Hand_L):getAlcoholLevel() > 0
      end },
    { line = "bandage", check = function()
          return getPlayer():getBodyDamage():getBodyPart(BodyPartType.Hand_L):bandaged()
      end },
    { line = "closeHealth", check = function()
          local jd = JoypadState.players[1]
          return not jd or jd.focus == nil
      end },

    -- fighting: zombies here can't hurt you (forced god mode, the game's own)
    { line = "weapon", setup = function()
          local inv = getPlayer():getInventory()
          if not inv:getFirstTypeRecurse("Base.BaseballBat") then inv:AddItem("Base.BaseballBat") end
      end, check = function()
          local h = getPlayer():getPrimaryHandItem()
          return h ~= nil and h:getFullType() == "Base.BaseballBat"
      end },
    { line = "closeInv", check = function()
          local jd = JoypadState.players[1]
          return not jd or jd.focus == nil
      end },
    { line = "zombieComing", setup = function() TU.spawn(1, 9) end, check = function() return TU.spawnedDead() end },
    { line = "lockOnSwitch", check = function() return ZA.LK and ZA.LK.isOn() end },
    { line = "lockOnFight", setup = function() TU.spawn(1, 8) end, check = function() return TU.spawnedDead() end },
    { line = "escape", setup = function() TU.spawn(3, 10, true) end, check = function() return TU.lostThem() end,
      after = function() TU.clearSpawned() end },

    -- cooking (the mod's cooking monitor, ZA_7Cooking, says half cooked / cooked / about to burn)
    { line = "cookIntro", setup = function()
          getPlayer():getInventory():AddItem("Base.Steak")
          TU.stove = TU.findStove()
      end, check = function()
          local ui = getPlayerLoot(0)
          local inv = ui and ui:isVisible() and ui.inventoryPane and ui.inventoryPane.inventory
          return inv ~= nil and TU.stove ~= nil and inv == TU.stove:getContainer()
      end },
    { line = "cookPut", check = function()
          return TU.stove ~= nil and TU.stove:getContainer():getFirstTypeRecurse("Base.Steak") ~= nil
      end },
    { line = "cookClose", check = function()
          local jd = JoypadState.players[1]
          return (not jd or jd.focus == nil) and not (ZA.P and ZA.P.layer)
      end },
    { line = "cookOn", check = function() return TU.stove ~= nil and TU.stove:Activated() end },
    { line = "cookWait", check = function()
          local it = TU.stove and TU.stove:getContainer():getFirstTypeRecurse("Base.Steak")
          return it ~= nil and it:isCooked()
      end },
    { line = "cookTake", check = function()
          -- cooked or burnt: taking it out is the lesson
          local it = getPlayer():getInventory():getFirstTypeRecurse("Base.Steak")
          return it ~= nil and (it:isCooked() or it:isBurnt())
      end },

    -- foraging (ZA_5ScanForage: search mode, Finds)
    { line = "forageOn", check = function()
          local m = ISSearchManager.getManager(getPlayer())
          return m ~= nil and m.isSearchMode == true
      end },
    { line = "forageFind", check = function()
          ZA.S.build()
          return #(ZA.S.lists.finds or {}) > 0
      end },
    { line = "foragePick", setup = function() TU.pickFrom = ZA.FG and ZA.FG.picked or 0 end,
      check = function() return ZA.FG ~= nil and (ZA.FG.picked or 0) > (TU.pickFrom or 0) end },
    { line = "forageOff", check = function()
          local m = ISSearchManager.getManager(getPlayer())
          return m ~= nil and not m.isSearchMode
      end },

    -- farming
    { line = "farmIntro", setup = function()
          local inv = getPlayer():getInventory()
          inv:AddItem("Base.HandShovel")
          for _ = 1, 5 do inv:AddItem("Base.CarrotSeed") end
      end, check = function() local sq = getPlayer():getCurrentSquare(); return sq ~= nil and not sq:getRoom() end },
    { line = "dig", check = function() return TU.cropNear(function(pl) return true end) end },
    { line = "sow", check = function() return TU.cropNear(function(pl) return pl.state == "seeded" end) end },

    -- fishing (ZA_7Fishing says the states, the bite, the tension)
    { line = "fishBait", setup = function()
          local inv = getPlayer():getInventory()
          if not inv:getFirstTypeRecurse("Base.FishingRod") then inv:AddItem("Base.FishingRod") end
          for _ = 1, 3 do inv:AddItem("Base.Worm") end
      end, check = function()
          local rod = getPlayer():getInventory():getFirstTypeRecurse("Base.FishingRod")
          return rod ~= nil and rod:getModData().fishing_Lure ~= nil
      end },
    { line = "fishEquip", check = function()
          local h = getPlayer():getPrimaryHandItem()
          return h ~= nil and h:hasTag(ItemTag.FISHING_ROD)
      end },
    { line = "fishGo", check = function() return TU.nearWater(4) end },
    { line = "fishCast", check = function() return ZA.FI ~= nil and (ZA.FI.state == "Wait" or ZA.FI.state == "ReelIn") end },
    { line = "fishWait", check = function() return ZA.FI ~= nil and ZA.FI.fish ~= nil end },
    { line = "fishLand", check = function() return ZA.FI ~= nil and (ZA.FI.landed or 0) > 0 end },

    -- crafting and building (ZA_4Craft menus; the build cursor is ZA_7Cursor)
    { line = "craft", setup = function()
          local inv = getPlayer():getInventory()
          inv:AddItem("Base.Log")
          if not inv:getFirstTypeRecurse("Base.Saw") then inv:AddItem("Base.Saw") end
          TU.planksBefore = inv:getCountTypeRecurse("Base.Plank")
      end, check = function()
          return getPlayer():getInventory():getCountTypeRecurse("Base.Plank") > (TU.planksBefore or 0)
      end },
    { line = "build", setup = function()
          local inv = getPlayer():getInventory()
          if not inv:getFirstTypeRecurse("Base.Hammer") then inv:AddItem("Base.Hammer") end
          for _ = 1, 10 do inv:AddItem("Base.Nails") end
          TU.builtBefore = ZA.CR and ZA.CR.built or 0
      end, check = function() return ZA.CR ~= nil and (ZA.CR.built or 0) > (TU.builtBefore or 0) end },

    -- driving
    { line = "carIntro", setup = function() TU.placeCar() end, check = function()
          local v = getPlayer():getVehicle()
          return v ~= nil and v:isDriver(getPlayer())
      end },
    { line = "startEngine", check = function() local v = getPlayer():getVehicle(); return v ~= nil and v:isEngineRunning() end },
    { line = "drive", setup = function() local p = getPlayer(); TU.driveFrom = { p:getX(), p:getY() } end,
      check = function()
          local p = getPlayer()
          return TU.driveFrom ~= nil and p:getVehicle() ~= nil
              and (p:getX() - TU.driveFrom[1]) ^ 2 + (p:getY() - TU.driveFrom[2]) ^ 2 > 25 * 25
      end },
    { line = "autodrive", setup = function() TU.markLaneEnd() end, check = function()
          local m = TU.laneEnd
          return m ~= nil and near(m.x, m.y, 15) and not (ZA.RT and ZA.RT.route)
      end },
    { line = "pause" },
}

-- ---------- what the lessons set up ----------

-- zombies can't really hurt you during the fighting lessons: any damage is healed at once, bites and all
-- (BodyDamage:RestoreToFullHealth, which also clears the zombie infection). The game's own god mode can't be used:
-- setGodMod(true, true) is accepted and ignored outside debug mode (tested 2026-10-02: it stays off).
TU.fightSteps = { weapon = true, closeInv = true, zombieComing = true, lockOnSwitch = true, lockOnFight = true, escape = true }
function TU.protect(step)
    if not (step and TU.fightSteps[step.line]) then return end
    local p = getPlayer()
    if not p or p:isDead() then return end
    local bd = p:getBodyDamage()
    local hurt = bd:getOverallBodyHealth() < 99.5 or bd:IsInfected()
    if not hurt then
        for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
            local bp = bd:getBodyPart(BodyPartType.FromIndex(i))
            if bp and (bp:bitten() or bp:scratched() or bp:isCut() or bp:bleeding()) then hurt = true; break end
        end
    end
    if hurt then
        bd:RestoreToFullHealth()
        if not TU.saidHealed or getTimestampMs() - TU.saidHealed > 8000 then
            TU.saidHealed = getTimestampMs()
            ZA.queue("Healed. Here, they can't really hurt you.")
        end
    end
end

-- n zombies about `dist` squares away, outdoors, coming for you
TU.spawned = {}
local function allowZombies()
    pcall(function()
        local o = getSandboxOptions():getOptionByName("Zombies")
        if o and o:getValue() == 6 then o:setValue(5) end
    end)
end
function TU.spawn(n, dist, spread)
    allowZombies()
    TU.want = { n = n, dist = dist, spread = spread, at = getTimestampMs() }
    local p = getPlayer()
    local px, py, pz = p:getX(), p:getY(), math.floor(p:getZ())
    local here = p:getCurrentSquare() and p:getCurrentSquare():getBuilding()
    -- inside the building you're in (so it comes to you through the house, not waits outside), `dist` squares
    -- off give or take; then anywhere free outdoors, closer in
    local sx, sy
    for _, want in ipairs({ "inside", "outside" }) do
        for r = (want == "inside") and dist or 5, (want == "inside") and 3 or 12, (want == "inside") and -1 or 1 do
            for a = 0, 345, 15 do
                local x = math.floor(px + math.cos(math.rad(a)) * r)
                local y = math.floor(py + math.sin(math.rad(a)) * r)
                local sq = getCell():getGridSquare(x, y, pz)
                if sq and sq:isFree(false) then
                    local inside = here ~= nil and sq:getBuilding() == here
                    if (want == "inside" and inside) or (want == "outside" and not sq:getRoom()) then sx, sy = x, y; break end
                end
            end
            if sx then break end
        end
        if sx then break end
    end
    if not sx then sx, sy = math.floor(px) + 4, math.floor(py) end
    pz = pz or 0
    for i = 1, n do
        local ox = spread and (i - 2) or 0
        local z
        pcall(function()
            local list = addZombiesInOutfit(sx + ox, sy, pz, 1, nil, 0)
            if list and list:size() > 0 then z = list:get(0) end
        end)
        if z then
            table.insert(TU.spawned, z)
            pcall(function() z:spotted(p, true) end)
            pcall(function() z:setTarget(p) end)
            pcall(function() z:pathToCharacter(p) end)
        end
    end
end
-- nobody appeared: try again every 5 seconds
local function respawnIfNone()
    local w = TU.want
    if #TU.spawned == 0 and w and getTimestampMs() - w.at > 5000 then
        print("[ZA] tutorial: zombie didn't appear, trying again")
        TU.spawn(w.n, w.dist, w.spread)
        return true
    end
    return #TU.spawned == 0
end
function TU.spawnedDead()
    if respawnIfNone() then return false end
    for _, z in ipairs(TU.spawned) do if not z:isDead() then return false end end
    TU.spawned, TU.want = {}, nil
    return true
end
-- none of them is after you any more (or they're dead), for 4 seconds
function TU.lostThem()
    if respawnIfNone() then return false end
    local p = getPlayer()
    local chasing = false
    for _, z in ipairs(TU.spawned) do
        if not z:isDead() and z:getTarget() == p then chasing = true end
    end
    local t = getTimestampMs()
    if chasing then TU.freeSince = nil; return false end
    TU.freeSince = TU.freeSince or t
    return t - TU.freeSince > 4000
end
function TU.clearSpawned()
    for _, z in ipairs(TU.spawned) do
        pcall(function() if not z:isDead() then z:removeFromWorld(); z:removeFromSquare() end end)
    end
    TU.spawned, TU.want = {}, nil
end

function TU.findStove()
    local best, bd
    local p = getPlayer()
    for x = TU.home.x - 25, TU.home.x + 25 do for y = TU.home.y - 25, TU.home.y + 25 do
        local sq = getCell():getGridSquare(x, y, 0)
        if sq then
            local objs = sq:getObjects()
            for i = 0, objs:size() - 1 do
                local o = objs:get(i)
                if instanceof(o, "IsoStove") and not o:isMicrowave() then
                    local d = (x - p:getX()) ^ 2 + (y - p:getY()) ^ 2
                    if not bd or d < bd then best, bd = o, d end
                end
            end
        end
    end end
    return best
end

function TU.cropNear(test)
    local sys = CFarmingSystem and CFarmingSystem.instance
    if not sys then return false end
    for i = 1, sys:getLuaObjectCount() do
        local pl = sys:getLuaObjectByIndex(i)
        if pl and math.abs(pl.x - TU.home.x) < 40 and math.abs(pl.y - TU.home.y) < 40 and test(pl) then return true end
    end
    return false
end

-- a car on the road nearest the house, with its key in your pocket (getting in unlocks it, the game's own way). Once: a reloaded save at this lesson
-- finds the same car (by where it was put) instead of adding another, and gives you its key if you've lost it.
local function giveKey(v)
    local inv = getPlayer():getInventory()
    if inv:haveThisKeyId(v:getKeyId()) then return end
    local key = v:createVehicleKey()
    if key then inv:AddItem(key) end
end
function TU.placeCar()
    local st = state()
    if st.car then
        for x = st.car.x - 4, st.car.x + 4 do for y = st.car.y - 4, st.car.y + 4 do
            local sq = getCell():getGridSquare(x, y, 0)
            local v = sq and sq:getVehicleContainer()
            if v then TU.car = v; giveKey(v); return end
        end end
    end
    local best, bd
    for x = TU.home.x - 60, TU.home.x + 60 do for y = TU.home.y - 60, TU.home.y + 60 do
        if ZA.DR.isRoad(x, y, 0) and ZA.DR.isRoad(x + 2, y, 0) and ZA.DR.isRoad(x - 2, y, 0) then
            local d = (x - TU.home.x) ^ 2 + (y - TU.home.y) ^ 2
            if not bd or d < bd then best, bd = { x, y }, d end
        end
    end end
    if not best then print("[ZA] tutorial: no road for the car"); return end
    local ew = ZA.DR.isRoad(best[1] + 4, best[2], 0) and ZA.DR.isRoad(best[1] - 4, best[2], 0)
    local v = addVehicleDebug("Base.CarNormal", ew and IsoDirections.E or IsoDirections.S, nil,
        getCell():getGridSquare(best[1], best[2], 0))
    if not v then print("[ZA] tutorial: car didn't spawn"); return end
    pcall(function() v:repair() end)
    local gas = v:getPartById("GasTank")
    if gas then gas:setContainerContentAmount(gas:getContainerCapacity()) end
    giveKey(v)
    TU.car = v
    st.car = { x = best[1], y = best[2] }
    print("[ZA] tutorial car at " .. best[1] .. "," .. best[2])
end

-- a marker about 50 squares along the road from where you are (within what the game has loaded)
function TU.markLaneEnd()
    local p = getPlayer()
    local sx, sy = math.floor(p:getX()), math.floor(p:getY())
    local seen, q, far = { [sx .. "," .. sy] = true }, { { sx, sy, 0 } }, nil
    while #q > 0 do
        local c = table.remove(q, 1)
        if not far or c[3] > far[3] then far = c end
        if c[3] >= 50 then break end
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local x, y = c[1] + d[1], c[2] + d[2]
            local k = x .. "," .. y
            if not seen[k] and ZA.DR.isRoad(x, y, 0) then seen[k] = true; table.insert(q, { x, y, c[3] + 1 }) end
        end
    end
    if not far then return end
    local m = { name = "End of the lane", x = far[1] + 0.5, y = far[2] + 0.5, z = 0 }
    table.insert(ZA.MK.all(), m)
    S.builtAt = -1e9
    TU.laneEnd = m
end


-- Hunger and thirst, through whichever way this build of the game exposes them.
function TU.need(which)
    local st = getPlayer():getStats()
    local ok, v = pcall(function()
        if CharacterStat then return st:get(which == "hunger" and CharacterStat.HUNGER or CharacterStat.THIRST) end
        return which == "hunger" and st:getHunger() or st:getThirst()
    end)
    return ok and v or 0
end
function TU.setNeed(which, v)
    local st = getPlayer():getStats()
    pcall(function()
        if CharacterStat then st:set(which == "hunger" and CharacterStat.HUNGER or CharacterStat.THIRST, v)
        elseif which == "hunger" then st:setHunger(v) else st:setThirst(v) end
    end)
end

-- the quick status was heard (lesson "status")
if ZA.ST and not TU.statusWrapped then
    TU.statusWrapped = true
    local orig = ZA.ST.summary
    ZA.ST.summary = function(...) TU.statusHeard = true; return orig(...) end
end

-- ---------- running them ----------

function TU.enter(i)
    local st = state()
    st.step = i
    st.stepKey = TU.steps[i] and TU.steps[i].line or nil   -- kept by name too: adding a step mustn't shift saves
    TU.stepAt, TU.hinted, TU.doneAt = getTimestampMs(), nil, nil
    local s = TU.steps[i]
    if not s then return end
    if s.setup then
        local ok, err = pcall(s.setup)
        if not ok then print("[ZA] tutorial setup error, step " .. i .. ": " .. tostring(err)) end
    end
    TU.radio(L(s.line).say)
    print("[ZA] tutorial step " .. i .. " " .. s.line)
end

function TU.tick()
    if not S.inWorld() then return end
    local st = state()
    if not st then return end
    if not st.started then
        -- a tutorial world (the game keeps the challenge's game mode in the save): begin, once
        local mode = ""
        pcall(function() mode = getWorld():getGameMode() end)
        if mode == C.gameMode then st.active, st.started, st.step = true, true, 0 end
        st.started = true
    end
    if not st.active then return end
    -- the game's own Survival Guide opens at the start of a new game: the radio does its job here
    local sg = SurvivalGuide and SurvivalGuide.instance
    if sg and sg:isVisible() then
        sg:setVisible(false)
        if JoypadState.players[1] then setJoypadFocus(0, nil) end
    end
    local t = getTimestampMs()
    if t >= (TU.nextClean or 0) then
        TU.nextClean = t + 2000
        pcall(function()
            local bd = getPlayer():getBodyDamage()
            for i = 0, BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
                local bp = bd:getBodyPart(BodyPartType.FromIndex(i))
                if bp and bp:isInfectedWound() then
                    bp:setInfectedWound(false)
                    pcall(function() bp:setWoundInfectionLevel(0) end)
                end
            end
        end)
    end
    TU.protect(TU.steps[st.step or 0])
    if (st.step or 0) == 0 then
        if not TU.startAt then TU.startAt = t + 3000 end      -- let the "you're in the world" line go first
        if t >= TU.startAt then TU.enter(1) end
        return
    end
    if not TU.stepAt then
        -- a loaded save: find the step by its name (lessons may have changed since), and say where we were
        if st.stepKey then
            for i, s2 in ipairs(TU.steps) do if s2.line == st.stepKey then st.step = i; break end end
        end
        TU.enter(st.step)
        return
    end
    local s = TU.steps[st.step]
    if not s then return end
    if TU.doneAt then
        if t >= TU.doneAt then TU.enter(st.step + 1) end
        return
    end
    local done = false
    if s.check then
        local ok, r = pcall(s.check)
        done = ok and r
    elseif s.wait then
        done = t - TU.stepAt >= s.wait
    end
    if done then
        if s.after then pcall(s.after) end
        if L(s.line).done then TU.radio(L(s.line).done) end
        TU.doneAt = t + (L(s.line).done and 3500 or 500)
        return
    end
    -- stuck: a hint after 40 seconds, again every 60
    if s.check and L(s.line).hint and t - TU.stepAt > (TU.hinted and 100000 or 40000) then
        TU.radio(L(s.line).hint)
        TU.hinted = true
        TU.stepAt = t - 40000
    end
end
if not TU.ticking then
    TU.ticking = true
    ZA.onTick(function()
        local ok, err = pcall(TU.tick)
        if not ok and not TU.errSaid then TU.errSaid = true; print("[ZA] tutorial error: " .. tostring(err)) end
    end)
end

-- "Radio: say that again", first in the You list while the tutorial runs
table.insert(S.builders, function(lists)
    if not TU.active() then return end
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|radio", noWhere = true, order = 0, baseName = "Radio",
        name = function() return "Radio: say that again. Square" end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function()
            local st = state()
            local s = st and TU.steps[st.step or 0]
            local l = s and L(s.line)
            TU.radio(TU.lastLine or (l and l.say))
            if l and l.hint then TU.radio(l.hint, true) end
        end,
    })
end)

-- for testing: jump to a step by its name (through the command channel)
function TU.jump(key)
    for i, st in ipairs(TU.steps) do
        if st.line == key then TU.enter(i); return "at " .. i end
    end
    return "no step " .. tostring(key)
end

function TU.nearWater(r)
    local p = getPlayer()
    local px, py = math.floor(p:getX()), math.floor(p:getY())
    for x = px - r, px + r do for y = py - r, py + r do
        local sq = getCell():getGridSquare(x, y, 0)
        if sq and sq:getProperties() and sq:getProperties():has(IsoFlagType.water) then return true end
    end end
    return false
end

-- ---------- choosing a lesson ----------
-- "Radio: choose a lesson" in the You list: a menu of the lessons; picking one starts it there (to repeat one, or to
-- reach new lessons from an older save).
TU.lessons = {
    { "The scanner and doors", "scannerOn" }, { "Looting", "lootFind" }, { "Eating and drinking", "eat" },
    { "How you're doing", "status" }, { "Injuries and healing", "hurt" }, { "Fighting", "weapon" },
    { "Lock-on and getting away", "lockOnSwitch" }, { "Cooking", "cookIntro" }, { "Foraging", "forageOn" },
    { "Farming", "farmIntro" }, { "Fishing", "fishBait" },
    { "Crafting and building", "craft" }, { "Driving", "carIntro" },
}
function TU.chooseLesson()
    local p = getPlayer()
    local s = p:getCurrentSquare()
    local x = isoToScreenX(0, s:getX(), s:getY(), s:getZ())
    local y = isoToScreenY(0, s:getX(), s:getY(), s:getZ())
    local menu = ISContextMenu.get(0, x, y)
    for _, l in ipairs(TU.lessons) do
        menu:addOption(l[1], nil, function()
            TU.clearSpawned()
            TU.radio("Right. " .. l[1] .. ".")
            TU.doneAt = nil
            TU.jump(l[2])
        end)
    end
    if JoypadState.players[1] then
        menu.origin = nil
        setJoypadFocus(0, menu)
        menu.mouseOver = 1
    end
end
table.insert(S.builders, function(lists)
    if not TU.active() then return end
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|lessons", noWhere = true, order = 0.5, baseName = "Lessons",
        name = function() return "Radio: choose a lesson. Square" end,
        x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function() TU.chooseLesson() end,
    })
end)
