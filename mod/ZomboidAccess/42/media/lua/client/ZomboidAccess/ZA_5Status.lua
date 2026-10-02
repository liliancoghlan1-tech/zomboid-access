-- Zomboid Access: your character's state.
--   Insert                 quick status: health, injuries, and the moodles that matter
--   Scanner "You" category (one step left of Zombies): health, each injury, each moodle, what you carry, the time
-- Said by itself:
--   a moodle appearing or getting worse ("Hungry", "Panic"), and going away ("Hungry gone")
--   a new injury, at once ("Bitten on the right hand!")
-- Moodles, injuries and body parts use the game's own English words.

ZA.ST = ZA.ST or {}
local ST = ZA.ST
local S = ZA.S

-- Every moodle the game has (decompiled zombie/scripting/objects/MoodleType, build 42.21).
ST.moodleTypes = { "ENDURANCE", "TIRED", "HUNGRY", "PANIC", "SICK", "BORED", "UNHAPPY", "BLEEDING", "WET",
    "HAS_A_COLD", "ANGRY", "STRESS", "THIRST", "INJURED", "PAIN", "HEAVY_LOAD", "DRUNK", "ZOMBIE",
    "HYPERTHERMIA", "HYPOTHERMIA", "WINDCHILL", "CANT_SPRINT", "UNCOMFORTABLE", "NOXIOUS_SMELL", "FOOD_EATEN" }

local function moodles(p)
    local out = {}
    local m = p:getMoodles()
    for _, name in ipairs(ST.moodleTypes) do
        local t = MoodleType[name]
        if t then
            local ok, lvl = pcall(function() return m:getMoodleLevel(t) end)
            if ok and lvl and lvl > 0 then
                local text = name
                pcall(function() text = m:getMoodleDisplayString(t) end)
                local gb = 0
                pcall(function() gb = m:getGoodBadNeutral(t) end)
                local desc = ""
                pcall(function() desc = ZA.clean(m:getMoodleDescriptionString(t) or "") end)
                table.insert(out, { key = name, level = lvl, text = ZA.clean(text), good = (gb == 1), desc = desc })
            end
        end
    end
    -- worst first
    table.sort(out, function(a, b)
        if a.good ~= b.good then return not a.good end
        return a.level > b.level
    end)
    return out
end
ST.moodles = moodles

-- Injuries, as the game's health panel lists them (ISHealthPanel).
local function injuries(p)
    local out = {}
    local parts = p:getBodyDamage():getBodyParts()
    for i = 0, parts:size() - 1 do
        local bp = parts:get(i)
        local list = {}
        local function add(cond, key) if cond then table.insert(list, getText(key)) end end
        pcall(function()
            add(bp:bitten(), "IGUI_health_Bitten")
            add(bp:bleeding(), "IGUI_health_Bleeding")
            add(bp:deepWounded(), "IGUI_health_DeepWound")
            add(bp:isCut(), "IGUI_health_Cut")
            add(bp:scratched(), "IGUI_health_Scratched")
            add(bp:getFractureTime() > 0 and bp:getSplintFactor() == 0, "IGUI_health_Fracture")
            add(bp:getBurnTime() > 0, "IGUI_health_Burned")
            add(bp:haveBullet(), "IGUI_health_LodgedBullet")
            add(bp:isInfectedWound(), "IGUI_health_Infected")
            add(bp:bandaged(), "IGUI_health_Bandaged")
        end)
        if #list > 0 then
            local where = BodyPartType.getDisplayName(bp:getType())
            table.insert(out, { part = where, key = BodyPartType.ToString(bp:getType()), list = list })
        end
    end
    return out
end
ST.injuries = injuries

function ST.healthWords(p)
    local h = math.floor(p:getBodyDamage():getHealth() + 0.5)
    return "Health " .. h .. " of 100"
end

function ST.weightWords(p)
    local carried, max
    pcall(function() carried = p:getInventory():getCapacityWeight() end)
    pcall(function() max = p:getMaxWeight() end)
    if not carried then return nil end
    local s = string.format("Carrying %.1f", carried)
    if max then s = s .. string.format(" of %.0f", max) end
    return s
end

-- Insert: the short version.
function ST.summary()
    local p = getPlayer()
    if not p then return end
    local parts = { ST.healthWords(p) }
    local inj = injuries(p)
    if #inj == 0 then table.insert(parts, "no injuries")
    else
        for _, j in ipairs(inj) do table.insert(parts, j.part .. ": " .. table.concat(j.list, ", "):lower()) end
    end
    local bad = {}
    for _, m in ipairs(moodles(p)) do if not m.good then table.insert(bad, m.text) end end
    if #bad > 0 then table.insert(parts, table.concat(bad, ", ")) end
    ZA.say(table.concat(parts, ". ") .. ".")
end

-- The scanner's "You" list.
table.insert(S.builders, function(lists)
    local p = getPlayer()
    local n = 0
    local function add(key, fn)
        n = n + 1
        table.insert(lists.you, { cat = "you", key = "you|" .. key, noWhere = true, order = n, name = fn, baseName = key,
            x = p:getX(), y = p:getY(), z = p:getZ() })
    end
    add("health", function() return ST.healthWords(getPlayer()) end)
    for _, j in ipairs(injuries(p)) do
        local part = j.key
        add("injury " .. part, function()
            for _, k in ipairs(injuries(getPlayer())) do
                if k.key == part then
                    -- the injuries, then what each one means
                    local s = k.part .. ": " .. table.concat(k.list, ", "):lower() .. "."
                    for _, w in ipairs(k.list) do
                        local h = ST.injuryExplain and ST.injuryExplain(w)
                        if h then s = s .. " " .. w .. ": " .. h end
                    end
                    return s
                end
            end
            return j.part .. ": healed"
        end)
    end
    if #injuries(p) == 0 then add("injuries", function() return "No injuries" end) end
    for _, m in ipairs(moodles(p)) do
        local key = m.key
        add("moodle " .. key, function()
            for _, k in ipairs(moodles(getPlayer())) do
                if k.key == key then
                    local s = k.text .. (k.good and ", good" or "") .. "."
                    if k.desc ~= "" then s = s .. " " .. k.desc end
                    local h = ST.moodleHelp and ST.moodleHelp[k.key]
                    if h then s = s .. " " .. h end
                    return s
                end
            end
            return m.text .. ": gone"
        end)
    end
    add("weight", function() return ST.weightWords(getPlayer()) or "Carrying: unknown" end)
    add("time", function() return "It's " .. ZA.timeWords() end)
end)

-- ---------- said by itself ----------

ST.lastMoodles, ST.lastInjuries = nil, nil
ST.nextCheck = 0

function ST.check()
    local p = getPlayer()
    if not p or p:isDead() then ST.lastMoodles, ST.lastInjuries = nil, nil; return end
    local now = {}
    for _, m in ipairs(moodles(p)) do now[m.key] = m end
    local inj = {}
    for _, j in ipairs(injuries(p)) do
        for _, w in ipairs(j.list) do inj[j.key .. "|" .. w] = j.part .. "|" .. w end
    end
    if ST.lastMoodles then
        -- new injuries first: they are urgent (bandages are not news)
        -- one phrase per body part: "Left forearm: bitten, bleeding!"
        local byPart, order = {}, {}
        for k, v in pairs(inj) do
            local part, what = v:match("^(.-)|(.*)$")
            if not ST.lastInjuries[k] and what ~= getText("IGUI_health_Bandaged") then
                if not byPart[part] then byPart[part] = {}; table.insert(order, part) end
                table.insert(byPart[part], what:lower())
            end
        end
        if #order > 0 then
            local phrases = {}
            for _, part in ipairs(order) do table.insert(phrases, part .. ": " .. table.concat(byPart[part], ", ")) end
            local t = table.concat(phrases, ". ")
            print("[ZA] status: " .. t)
            ZA.say(t .. "!")
        end
        local changes = {}
        for k, m in pairs(now) do
            local old = ST.lastMoodles[k]
            if not old or m.level > old.level then table.insert(changes, m.text) end
        end
        for k, old in pairs(ST.lastMoodles) do
            if not now[k] then table.insert(changes, old.text .. " gone") end
        end
        if #changes > 0 then
            local t = table.concat(changes, ". ")
            print("[ZA] status: " .. t)
            ZA.queue(t .. ".")
        end
    end
    ST.lastMoodles, ST.lastInjuries = now, inj
end

if not ST.ticking then
    ST.ticking = true
    ZA.onTick(function()
        local t = getTimestampMs()
        if t < ST.nextCheck then return end
        ST.nextCheck = t + 500
        local ok, err = pcall(ST.check)
        if not ok then print("[ZA] status error: " .. tostring(err)) end
    end)
end

function ST.onKey(key)
    if key ~= Keyboard.KEY_INSERT or isShiftKeyDown() or isCtrlKeyDown() or not S.inWorld() then return end
    -- with the inventory open, Insert describes the selected item instead
    local jd = ZA.joypad()
    local f = jd and jd.focus
    if f and f.Type == "ISInventoryPage" then ZA.F.sayDetails(f); return end
    local ok, err = pcall(ST.summary)
    if not ok then print("[ZA] status key error: " .. tostring(err)) end
end
if not ST.hooked then
    ST.hooked = true
    Events.OnKeyPressed.Add(function(key) ST.onKey(key) end)
end

Events.OnGameStart.Add(function() ST.lastMoodles, ST.lastInjuries = nil, nil end)
