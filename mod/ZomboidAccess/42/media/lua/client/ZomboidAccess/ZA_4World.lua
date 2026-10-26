-- Zomboid Access: starting a game, and arriving in the world.
-- While the world loads, and on the "press to start" screen after it, the game runs no Lua at all:
-- so the loading message is said as the game starts loading, and the speech bridge watches the
-- game's log for the rest ("Still loading the world", "The world has loaded...").

local F = ZA.F

-- Every way into a game (new game, continue, load) goes through forceChangeState(LoadingQueueState).
if forceChangeState and not ZA.wrappedState then
    ZA.wrappedState = true
    local orig = forceChangeState
    forceChangeState = function(state, ...)
        ZA.say(ZA.tr("World_Loading"))
        return orig(state, ...)
    end
end

-- Continue and Load: a save closed on the "press to start" screen has no mods.txt yet, and the game's own check
-- (MainScreen.checkSaveFile -> getMissingMods) then fails on it with an error and nothing on screen, so Continue
-- silently did nothing. A save without mods.txt loads with your usual mods (continueLatestSaveAux already says
-- so), so it has no missing mods.
if MainScreen and MainScreen.getMissingMods and not ZA.wrappedMissingMods then
    ZA.wrappedMissingMods = true
    local orig = MainScreen.getMissingMods
    MainScreen.getMissingMods = function(activeMods, ...)
        if activeMods == nil then return {} end
        return orig(activeMods, ...)
    end
end
-- Anything else that stops Continue is said, instead of nothing happening.
if MainScreen and MainScreen.continueLatestSave and not ZA.wrappedContinue then
    ZA.wrappedContinue = true
    local orig = MainScreen.continueLatestSave
    MainScreen.continueLatestSave = function(...)
        local ok, err = pcall(orig, ...)
        if not ok then
            print("[ZA] continue failed: " .. tostring(err))
            ZA.say(ZA.tr("World_ContinueFailed"))
        end
    end
end

function ZA.timeWords()
    local gt = getGameTime()
    local h, m = gt:getHour(), gt:getMinutes()
    local month, day = ZA.tr("World_Month" .. (gt:getMonth() + 1)), gt:getDay() + 1
    -- the clock goes by the language: 24 hours in French, AM and PM in English
    if ZA.tr("World_Use24h") == "1" then
        -- the first of the month has its own word in French: le 1er juillet
        if day == 1 then day = ZA.tr("World_DayFirst") end
        if m == 0 then return ZA.tr("World_Time24Hour", h, day, month) end
        return ZA.tr("World_Time24Min", h, string.format("%02d", m), day, month)
    end
    local ampm = h < 12 and "AM" or "PM"
    local h12 = h % 12; if h12 == 0 then h12 = 12 end
    if m == 0 then return ZA.tr("World_Time12Hour", h12, ampm, month, day) end
    return ZA.tr("World_Time12Min", h12, string.format("%02d", m), ampm, month, day)
end

Events.OnGameStart.Add(function()
    local p = getPlayer()
    local who = ""
    if p and p:getDescriptor() then
        local d = p:getDescriptor()
        who = ZA.clean((d:getForename() or "") .. " " .. (d:getSurname() or ""))
    end
    if who ~= "" then
        ZA.say(ZA.tr("World_InWorldAs", who, ZA.timeWords()))
    else
        ZA.say(ZA.tr("World_InWorld", ZA.timeWords()))
    end
end)

-- The survival guide that opens on a new game.
F.screens.SurvivalGuide = { name = ZA.tr("World_SurvivalGuide") }
F.screens.ISPostDeathUI = { name = ZA.tr("World_YouDied") }
-- The death screen shows its buttons only 3 seconds after you die (ISPostDeathUI.waitOver), and nothing moves the
-- focus then, so they were never read: say them as they appear.
local deathSaid = {}
ZA.onTick(function()
    if not ISPostDeathUI or not ISPostDeathUI.instance then return end
    for i, ui in pairs(ISPostDeathUI.instance) do
        if ui and ui:isVisible() and ui.waitOver and not deathSaid[ui] then
            deathSaid[ui] = true
            local parts = {}
            for _, b in ipairs({ { ui.buttonRespawn, "{Cross}" }, { ui.buttonQuit, "{Circle}" }, { ui.buttonExit, "{Square}" } }) do
                local btn, key = b[1], b[2]
                if btn and btn:isVisible() then
                    local title = btn.title or (btn.getTitle and btn:getTitle()) or ""
                    if title ~= "" then table.insert(parts, ZA.tr("World_DiedButton", key, ZA.clean(title))) end
                end
            end
            ZA.say(ZA.tr("World_DiedSay", table.concat(parts, ". ")))
        end
    end
end)
F.screens.ISBackButtonWheel = { name = ZA.tr("World_ShareMenu") }
local origName = F.screenName
function F.screenName(panel)
    if panel and panel.parent and panel.parent.Type == "SurvivalGuide" then
        return ZA.tr("World_SurvivalHint")
    end
    return origName(panel)
end
F.readers.ISScrollingListBox = function(p)
    if not (p.parent and p.parent.Type == "SurvivalGuide") then return F.listReader(p) end
    local it = p.items[p.selected]
    if not it then return nil end
    local d = it.item or {}
    local text = ZA.clean(d.description or d.spiffo or "")
    local title = ZA.clean(d.title or it.text or "")
    return it, title .. ZA.pos(p.selected, #p.items) .. (text ~= "" and (". " .. text) or ""), ""
end

-- After a death, "Continue with new character" uses the co-op versions of the creation screens.
F.screens.CoopCharacterCreationProfession = F.screens.CharacterCreationProfession
F.screens.CoopCharacterCreationMain = F.screens.CharacterCreationMain
