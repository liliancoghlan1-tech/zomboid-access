-- Zomboid Access: says when a skill goes up a level ("Cuisine, niveau 2"), as the game plays its little tune
-- (Marc, 2026-10-22: a level learnt from the TV played the tune and nothing was said).
-- The game's LevelPerk event (character, skill, level): your character only, and only a rise over the level last
-- seen, so nothing is said while a save loads or when a level is taken away.

ZA.LU = ZA.LU or {}
local LU = ZA.LU

-- every skill's level now, by skill (the levels to compare the next event with)
function LU.remember()
    local p = getPlayer()
    if not p then return end
    LU.seen = {}
    pcall(function()
        local list = PerkFactory.PerkList
        for i = 0, list:size() - 1 do
            local perk = list:get(i)
            LU.seen[tostring(perk)] = p:getPerkLevel(perk)
        end
    end)
end

function LU.onLevel(owner, perk, level)
    local p = getPlayer()
    if not LU.seen or not p or owner ~= p or not perk or not level then return end
    local key = tostring(perk)
    local before = LU.seen[key]
    LU.seen[key] = level
    if before ~= nil and level <= before then return end
    local name = tostring(perk)
    pcall(function() name = PerkFactory.getPerkName(perk) end)
    ZA.log("[ZA] level up " .. key .. " " .. tostring(level))
    ZA.queue(ZA.tr("LevelUp_Up", name, level))
end

Events.LevelPerk.Add(function(owner, perk, level) LU.onLevel(owner, perk, level) end)
Events.OnGameStart.Add(LU.remember)
Events.OnCreatePlayer.Add(function() LU.remember() end)   -- (a new character after a death)
-- (loaded into a running game: start from the levels it has now)
if getPlayer() then LU.remember() end
