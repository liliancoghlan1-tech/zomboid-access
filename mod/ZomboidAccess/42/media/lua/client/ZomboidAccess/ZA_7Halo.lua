-- Zomboid Access: the words the game floats above your character's head, said as they appear (Marc, 2026-10-24:
-- "everything, exactly as sighted players see it").
--   Halo text (HaloTextHelper, from the game's Lua): a recipe learnt, what a TV or radio programme does to you
--     ("Boredom" with an arrow down: "Boredom going down"), why an action can't be done (not safe to sleep here,
--     too dark to read, can't do that while dragging a body, the seat is taken...), a book you can't understand,
--     what foraging found.
--   What your character says (Say: a cough, a call, "No catch", "+1 fish", luring an animal), read from the line
--     the game shows; not in multiplayer, where your own chat comes the same way and the chat reader has it.
--   A recipe learnt by the game's own code (reading, crafting): the known recipes are watched as well.
-- Not reached: the engine's own halo notes ("The door is blocked", "The door is barricaded"), set from Java where
-- no Lua can see them. A skill level gained is said by ZA_7LevelUp.

ZA.HA = ZA.HA or {}
local HA = ZA.HA
HA.recent = HA.recent or {}

-- the text as plain words: the game's halo markup ([br/], [img=...], [col=...]) and rich text tags out
local function tidy(text)
    local t = tostring(text or "")
    t = t:gsub("%[br/%]", ". "):gsub("%[[^%]]*%]", " ")
    return ZA.clean(t)
end

-- queued, never cutting what is being said; the same words twice within 1.5 s only once
function HA.say(text)
    local t = tidy(text)
    if t == "" then return end
    local now = getTimestampMs()
    local last = HA.recent[t]
    if last and now - last >= 0 and now - last < 1500 then return end
    HA.recent[t] = now
    ZA.log("[ZA] halo " .. t)
    ZA.queue(t)
end

local function mine(p)
    local me = getPlayer()
    return me ~= nil and p == me
end

-- addTextWithArrow(player, text, [separator,] up, colour...): the arrow says which way it went
function HA.onHalo(kind, p, text, a3, a4)
    if not mine(p) then return end
    HA.lastHaloAt = getTimestampMs()
    if kind == "addTextWithArrow" then
        local up
        if type(a3) == "boolean" then up = a3 elseif type(a4) == "boolean" then up = a4 end
        if up ~= nil then
            HA.say(ZA.tr(up and "Halo_Up" or "Halo_Down", tidy(text)))
            return
        end
    end
    HA.say(text)
end

-- Every Lua caller goes through these four; wrapped once (a reload of this file keeps the first wrapping).
if not HA.wrapped and HaloTextHelper then
    HA.wrapped = true
    for _, kind in ipairs({ "addText", "addGoodText", "addBadText", "addTextWithArrow" }) do
        local orig = HaloTextHelper[kind]
        if orig then
            local ok, err = pcall(function()
                HaloTextHelper[kind] = function(p, text, ...)
                    local ok2, err2 = pcall(HA.onHalo, kind, p, text, ...)
                    if not ok2 then print("[ZA] halo error: " .. tostring(err2)) end
                    return orig(p, text, ...)
                end
            end)
            if not ok then print("[ZA] halo: can't wrap " .. kind .. ": " .. tostring(err)) end
        end
    end
end

-- What your character says: the line shown above the head, once each time it is said.
function HA.sayTick()
    local p = getPlayer()
    if not p or isClient() then HA.lastSay = nil; return end
    local speaking, line = false, nil
    pcall(function()
        speaking = p:IsSpeaking()
        line = p:getSayLine()
    end)
    if speaking and line and line ~= "" then
        if line ~= HA.lastSay then
            HA.lastSay = line
            HA.say(line)
        end
    else
        HA.lastSay = nil
    end
end

-- Recipes learnt by the game's own code: a recipe new to the known list. (Not within 2 s of a halo the game's Lua
-- showed, which already said it, by a name worded its own way.)
function HA.recipeTick()
    local p = getPlayer()
    if not p then HA.known = nil; return end
    local ok, list = pcall(function() return p:getKnownRecipes() end)
    if not ok or not list then return end
    local n = list:size()
    if not HA.known or HA.knownOf ~= p then
        HA.known, HA.knownOf, HA.knownN = {}, p, n
        for i = 0, n - 1 do HA.known[tostring(list:get(i))] = true end
        return
    end
    if n == HA.knownN then return end
    HA.knownN = n
    local quiet = HA.lastHaloAt and getTimestampMs() - HA.lastHaloAt < 2000
    for i = 0, n - 1 do
        local r = tostring(list:get(i))
        if not HA.known[r] then
            HA.known[r] = true
            if not quiet then
                local recipeName = r:gsub("^.*%.", "")
                pcall(function() recipeName = getRecipeDisplayName(recipeName) end)
                HA.say(getText("IGUI_HaloNote_LearnedRecipe", recipeName))
            end
        end
    end
end

if not HA.ticking then
    HA.ticking = true
    local nextRecipes = 0
    ZA.onTick(function()
        HA.sayTick()
        local now = getTimestampMs()
        if now >= nextRecipes or now < nextRecipes - 5000 then
            nextRecipes = now + 500
            HA.recipeTick()
        end
    end)
end
