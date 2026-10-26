-- Zomboid Access: the character window's tabs (L1 and R1 move between them).
--   Health: each injured body part, its injuries and what they mean; Cross opens its treatments
--     (bandage, disinfect, stitch, splint, remove glass...), read by the menu reader (ZA_4Menus).
--   Skills: each skill, its level, and how far to the next level.
-- Open them from the scanner's "You" list (Health screen / Skills, then Square) or the game's Share menu.

local F = ZA.F

-- ---------- health ----------

local function partWords(bp)
    local name = BodyPartType.getDisplayName(bp:getType())
    local key = BodyPartType.ToString(bp:getType())
    local s = name
    for _, j in ipairs(ZA.ST.injuries(getPlayer())) do
        if j.key == key then
            s = s .. ": " .. table.concat(j.list, ", "):lower() .. "."
            for _, w in ipairs(j.list) do
                local h = ZA.ST.injuryExplain and ZA.ST.injuryExplain(w)
                if h then s = s .. " " .. w .. ": " .. h end
            end
            return s
        end
    end
    pcall(function()
        if bp:stitched() then s = s .. ": " .. ZA.tr("Health_Stitched") end
        if bp:getSplintFactor() > 0 then s = s .. ": " .. ZA.tr("Health_Splinted") end
        if bp:getAdditionalPain() > 10 then s = s .. ": " .. ZA.tr("Health_Painful") end
    end)
    return s
end

F.readers.ISHealthPanel = function(panel)
    local lb = panel.listbox
    if not lb or not lb.items or #lb.items == 0 then
        -- the list fills a frame after the screen opens
        if #ZA.ST.injuries(getPlayer()) > 0 then return "pending", "", "" end
        return "none", ZA.tr("Health_NoInjuries"), ""
    end
    local i = lb.selected or 1
    local it = lb.items[i]
    if not it then return "none", "", "" end
    local bp = it.item.bodyPart
    return tostring(bp) .. "#" .. i, partWords(bp) .. ZA.pos(i, #lb.items), ""
end

F.screens.ISHealthPanel = {
    intro = function(panel)
        local p = getPlayer()
        local n = #ZA.ST.injuries(p)
        if n == 0 then return ZA.tr("Health_IntroNone", ZA.ST.healthWords(p)) end
        if n == 1 then return ZA.tr("Health_IntroOne", ZA.ST.healthWords(p)) end
        return ZA.tr("Health_IntroMany", ZA.ST.healthWords(p), n)
    end,
}

-- ---------- skills ----------

F.readers.ISCharacterInfo = function(panel)
    local i = panel.joypadIndex
    local bars = panel.progressBars or {}
    if not i or not bars[i] then return "none", "", "" end
    local bar = bars[i]
    local perk = bar.perk
    local p = getPlayer()
    local name, level = ZA.tr("Health_Skill"), 0
    pcall(function() name = perk:getName() end)
    pcall(function() level = p:getPerkLevel(perk) end)
    local s = ZA.tr("Health_SkillLevel", name, level)
    pcall(function()
        local xp = p:getXp():getXP(perk)
        local cur, nxt = perk:getTotalXpForLevel(level), perk:getTotalXpForLevel(level + 1)
        if level < 10 and nxt > cur then
            s = ZA.tr("Health_SkillNext", name, level, math.floor((xp - cur) / (nxt - cur) * 100), level + 1)
        end
    end)
    return perk, s .. ZA.pos(i, #bars), ""
end

F.screens.ISCharacterInfo = {
    intro = function() return ZA.tr("Health_SkillsIntro") end,
}
F.screens.ISCharacterScreen = { name = ZA.tr("Health_CharInfo"), hint = ZA.tr("Health_TabsHint") }
F.screens.ISCharacterProtection = { name = ZA.tr("Health_Protection"), hint = ZA.tr("Health_TabsHint") }
F.screens.ISClothingInsPanel = { name = ZA.tr("Health_Warmth"), hint = ZA.tr("Health_TabsHint") }

-- ---------- opening them from the mod ----------

function F.openInfoTab(which)
    local win = getPlayerInfoPanel(0)
    if not win then return end
    local name = (which == "health") and xpSystemText.health or xpSystemText.skills
    if not win:getIsVisible() or win.panel:getActiveView() ~= win.panel:getView(name) then
        win:toggleView(name)
    end
    local view = (which == "health") and win.healthView or win.characterView
    if JoypadState.players[1] then setJoypadFocus(0, view) end
end

-- (this file loads before the scanner's; ZA_5Scan keeps a builders list that already exists)
ZA.S = ZA.S or {}
ZA.S.builders = ZA.S.builders or {}
table.insert(ZA.S.builders, function(lists)
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|healthscreen", noWhere = true, order = 900, baseName = ZA.tr("Health_ScreenBase"),
        name = ZA.tr("Health_ScreenName"), x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function() F.openInfoTab("health") end,
    })
    table.insert(lists.you, {
        cat = "you", key = "you|skills", noWhere = true, order = 901, baseName = ZA.tr("Health_SkillsBase"),
        name = ZA.tr("Health_SkillsName"), x = p:getX(), y = p:getY(), z = p:getZ(),
        action = function() F.openInfoTab("skills") end,
    })
end)
