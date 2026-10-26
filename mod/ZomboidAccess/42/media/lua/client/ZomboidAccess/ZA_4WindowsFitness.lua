-- Zomboid Access: the exercise window (ISFitnessUI), opened by the health screen's Exercise button.
-- In game 2026-10-23 it said "Exercise. Time (minutes)" and then "(ISRadioButtons)": no exercise, no duration, no
-- way to know what OK would do. The window has three rows, as the game lays them out:
--   the exercises: Up and Down go through them, Cross picks one (one that needs a dumbbell or a barbell you don't
--     carry can't be picked; the game adds "needs ..." to its name). Each says whether it is the one picked, how
--     regularly you do it, what it trains and the aches it leaves (the game's own text);
--   the duration: plus and minus, 10 minutes a step, from 10 to 60;
--   OK (starts the exercise picked, or says why it can't: too tired, too heavy a load, sitting, in pain),
--   Cancel (stops the exercise under way) and Close.
-- (loads after ZA_4Windows, whose window introduction this one replaces for this window)

local F = ZA.F

local function minutes(w)
    return tonumber(w.exeTime and w.exeTime:getInternalText() or "") or 10
end

-- how regularly you do it, as the window's bar shows it: 0 to 100
local function regularity(w, kind)
    local r = 0
    pcall(function() r = w.player:getFitness():getRegularity(kind) end)
    return math.floor((r or 0) + 0.5)
end

-- what the exercise trains, then the aches it leaves (ISFitnessUI:selectedNewExercise's text)
local stiffnessKeys = { legs = "IGUI_Fitness_LegsStiffness", arms = "IGUI_Fitness_ArmsStiffness", abs = "IGUI_Fitness_AbsStiffness" }
local function exerciseInfo(data)
    local parts = {}
    if data.tooltip and data.tooltip ~= "" then table.insert(parts, ZA.clean(data.tooltip)) end
    for v in string.gmatch(data.stiffness or "", "[^,]+") do
        if stiffnessKeys[v] then table.insert(parts, getText(stiffnessKeys[v])) end
    end
    return table.concat(parts, " ")
end

local function pickedName(w)
    local data = FitnessExercises.exercisesType[w.selectedExe]
    return data and ZA.clean(data.name or "") or ""
end

F.readers.ISFitnessUI = function(w)
    local ch = F.focusedChild(w)
    if not ch then return nil end
    local mins = minutes(w)
    if ch == w.exercises then
        local i = ch.joypadIndex or 1
        local kind = ch:getOptionData(i)
        local data = FitnessExercises.exercisesType[kind]
        local picked = ch:isSelected(i)
        local state = ZA.tr(picked and "Fitness_Picked" or "Fitness_NotPicked")
        -- (the game glues "(needs a barbell)" to the name)
        local label = ZA.clean(ch:getOptionText(i) or ""):gsub("(%S)%(", "%1 (")
        local words = label .. ", " .. state .. ZA.pos(i, #ch.options)
        if data then
            words = words .. ". " .. ZA.tr("Fitness_Regularity", regularity(w, kind))
            local info = exerciseInfo(data)
            if info ~= "" then words = words .. ". " .. info end
        end
        return "exercise" .. i, words, state
    end
    if ch == w.plusBtn or ch == w.minusBtn then
        local length = ZA.tr("Fitness_Length", mins)
        return ch, ZA.tr(ch == w.plusBtn and "Fitness_More" or "Fitness_Less") .. ". " .. length, length
    end
    if ch == w.ok then
        local words = ZA.tr("Fitness_Start", pickedName(w), mins)
        -- (the game leaves the last reason in the tooltip once OK works again: only said while OK is off)
        local why = ""
        if not w.ok.enable then why = ZA.tr("Fitness_CantStart", ZA.clean(w.ok.tooltip or "")) end
        if why ~= "" then words = words .. ". " .. why end
        return ch, words, why
    end
    if ch == w.cancel then
        local state = w.cancel.enable and "" or ZA.tr("Fitness_NothingToStop")
        return ch, ZA.tr("Fitness_Stop") .. (state ~= "" and (". " .. state) or ""), state
    end
    local words, value = F.describe(ch)
    return ch, words, value
end

local origIntro = F.screenIntro
function F.screenIntro(panel)
    if not (panel and panel.Type == "ISFitnessUI") then return origIntro(panel) end
    local parts = { ZA.windowNames.ISFitnessUI }
    if FitnessExercises.exercisesType[panel.selectedExe] then
        table.insert(parts, ZA.tr("Fitness_Current", pickedName(panel), minutes(panel), regularity(panel, panel.selectedExe)))
    end
    table.insert(parts, ZA.tr("Fitness_Help"))
    local hints = F.buttonHints(panel)
    if hints ~= "" then table.insert(parts, hints) end
    for i, t in ipairs(parts) do parts[i] = t:gsub("[%.%s]+$", "") end
    return table.concat(parts, ". ")
end
