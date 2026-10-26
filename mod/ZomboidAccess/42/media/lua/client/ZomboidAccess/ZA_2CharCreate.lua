-- Zomboid Access: the occupation and traits screen (CharacterCreationProfession).
-- The game splits it into lists (occupations, good traits, bad traits, your traits) and moves
-- between them only by holding R1 and pressing the D-pad. Here:
--   - each list says its name, your points, and what Cross does in it;
--   - L1 and R1 (a short press) jump to the previous / next list;
--   - every trait says its cost or what it gives, and its description;
--   - points left are spoken whenever they change.

local F = ZA.F
local CC = {}
ZA.CC = CC

local AREAS = {
    { field = "listboxProf", name = ZA.tr("CharCreate_AreaProf"), cross = ZA.tr("CharCreate_CrossProf") },
    { field = "listboxTrait", name = ZA.tr("CharCreate_AreaGood"), cross = ZA.tr("CharCreate_CrossAdd") },
    { field = "listboxBadTrait", name = ZA.tr("CharCreate_AreaBad"), cross = ZA.tr("CharCreate_CrossAdd") },
    { field = "listboxTraitSelected", name = ZA.tr("CharCreate_AreaMine"), cross = ZA.tr("CharCreate_CrossRemove") },
}

local function screen(panel)
    local p = panel and panel.parent
    -- (the same screen for a second player joining a server: CoopCharacterCreationProfession.lua:3)
    if p and (p.Type == "CharacterCreationProfession" or p.Type == "CoopCharacterCreationProfession") then return p end
    return nil
end

local function areaOf(panel)
    local s = screen(panel)
    if not s then return nil end
    for i, a in ipairs(AREAS) do
        if s[a.field] == panel then return a, i, s end
    end
    return nil
end

local function points(s)
    local ok, n = pcall(s.PointToSpend, s)
    return ok and n or nil
end

-- short: while moving through a list, just the number; what to do about it is said with the screen.
local function pointsWords(n, short)
    if n == nil then return "" end
    if n < 0 then
        local over = ZA.tr((-n) == 1 and "CharCreate_OverOne" or "CharCreate_OverMany", -n)
        return short and over or ZA.tr("CharCreate_OverFix", over)
    end
    if n == 0 then return ZA.tr("CharCreate_LeftZero", n) end
    return ZA.tr(n == 1 and "CharCreate_LeftOne" or "CharCreate_LeftMany", n)
end

local function costWords(trait, inYourList)
    local ok, c = pcall(trait.getCost, trait)
    if not ok or c == nil or c == 0 then return inYourList and ZA.tr("CharCreate_FreeProf") or "" end
    if c > 0 then return ZA.tr(c == 1 and "CharCreate_CostOne" or "CharCreate_CostMany", c) end
    return ZA.tr((-c) == 1 and "CharCreate_GivesOne" or "CharCreate_GivesMany", -c)
end

-- What just changed: "Added Strong." / "Removed Strong." / "Occupation: Burglar."
local memo = { traits = nil, prof = nil, msg = "" }
local function changes(s)
    local now = {}
    for _, it in ipairs(s.listboxTraitSelected.items or {}) do now[it.text] = true end
    local msg = {}
    if memo.screen == s and memo.traits then
        for t in pairs(now) do if not memo.traits[t] then table.insert(msg, ZA.tr("CharCreate_Added", t)) end end
        for t in pairs(memo.traits) do if not now[t] then table.insert(msg, ZA.tr("CharCreate_Removed", t)) end end
    end
    local prof = s.profession
    if memo.screen == s and prof ~= memo.prof and prof then
        msg = { ZA.tr("CharCreate_Occupation", ZA.clean(prof:getUIName())) }
    end
    memo.screen, memo.traits, memo.prof = s, now, prof
    if #msg > 0 then memo.msg = table.concat(msg, ". ") end
    return memo.msg
end

-- The selected line of one of the lists.
F.readers.CharacterCreationProfessionListBox = function(p)
    local a, _, s = areaOf(p)
    if not a then return F.listReader(p) end
    local n = points(s)
    local it = p.items[p.selected]
    if not it then
        return p, (#p.items == 0 and ZA.tr("CharCreate_Empty") or ZA.tr("CharCreate_NoneSelected")), pointsWords(n)
    end
    local data = it.item
    local extra = ""
    if a.field == "listboxProf" then
        local ok, c = pcall(data.getCost, data)
        if ok and c and c ~= 0 then
            if c > 0 then extra = ZA.tr(c == 1 and "CharCreate_GivesOne" or "CharCreate_GivesMany", c)
            else extra = ZA.tr((-c) == 1 and "CharCreate_CostOne" or "CharCreate_CostMany", -c) end
        end
    else
        extra = costWords(data, a.field == "listboxTraitSelected")
    end
    local desc = ZA.clean(it.tooltip or "")
    local words = ZA.clean(it.text or "") .. (extra ~= "" and (", " .. extra) or "") .. ZA.pos(p.selected, #p.items)
    if desc ~= "" then words = words .. ". " .. desc end
    local what = changes(s)
    -- Moving in the occupations list chooses what you land on: its name is already the line itself, so don't
    -- say "Occupation: Burglar" before "Burglar" on every step.
    if a.field == "listboxProf" and what == ZA.tr("CharCreate_Occupation", ZA.clean(it.text or "")) then what = "" end
    return it, words, (what ~= "" and (what .. ". ") or "") .. pointsWords(n, true)
end

-- Arriving in a list: the whole screen's instructions the first time, then just the list's name.
local lastScreen = nil
F.screens.CharacterCreationProfessionListBox = {
    intro = function(panel)
        local a, _, s = areaOf(panel)
        if not a then return nil end
        local parts = {}
        if s ~= lastScreen or F.fullIntro then
            lastScreen = s
            table.insert(parts, ZA.tr("CharCreate_Title"))
            table.insert(parts, pointsWords(points(s)))
            table.insert(parts, a.name)
            table.insert(parts, ZA.tr("CharCreate_UpDown", a.cross))
            table.insert(parts, ZA.tr("CharCreate_SwitchHelp"))
            table.insert(parts, ZA.tr("CharCreate_Done"))
        else
            table.insert(parts, a.name)
            table.insert(parts, a.cross)
        end
        return table.concat(parts, ". ")
    end,
}

-- The screen itself (after Circle leaves a list): what Cross and the other buttons do now.
F.screens.CharacterCreationProfession = {
    intro = function(panel)
        lastScreen = panel
        local n = points(panel)
        local parts = { ZA.tr("CharCreate_Title"), pointsWords(n) }
        if n ~= nil and n < 0 then table.insert(parts, ZA.tr("CharCreate_NextLocked")) end
        local hints = F.buttonHints(panel)
        if hints ~= "" then table.insert(parts, hints) end
        table.insert(parts, ZA.tr("CharCreate_BackIn"))
        return table.concat(parts, ". ")
    end,
}

-- L1 / R1 (short press) jump between the lists.
local function switch(jd, dir)
    local a, i, s = areaOf(jd.focus)
    if not a then return false end
    local j = i
    for _ = 1, #AREAS do
        j = ZA.mod(j - 1 + dir, #AREAS) + 1
        local target = s[AREAS[j].field]
        if target and target:isVisible() then
            if target.selectedBeforeReset and target.selectedBeforeReset > 0 and target.selectedBeforeReset <= #target.items then
                target.selected = target.selectedBeforeReset
            elseif #target.items > 0 then
                target.selected = 1
            end
            jd.focus = target
            updateJoypadFocus(jd)
            return true
        end
    end
    return false
end

-- Moving in the occupations list already chooses (the game's own Up and Down do), so Cross changes nothing and
-- the game says nothing: confirm it.
if CharacterCreationProfessionListBox and not CC.wrappedDown then
    CC.wrappedDown = true
    local origDown = CharacterCreationProfessionListBox.onJoypadDown
    function CharacterCreationProfessionListBox:onJoypadDown(button, joypadData)
        origDown(self, button, joypadData)
        local a, _, s = areaOf(self)
        if button == Joypad.AButton and a and a.field == "listboxProf" and s.profession then
            ZA.say(ZA.tr("CharCreate_Selected", ZA.clean(s.profession:getUIName())))
        end
    end
end

-- R1 also starts the game's own "hold R1 and D-pad" navigation, at once on these lists (the hold delay is 0 unless
-- the panel says R1 is also one of its buttons), so a press of R1 was always taken for that and never reached the
-- switch below: only L1 worked (Marc, 2026-10-18). Saying so gives it the game's 250 ms: a short press switches,
-- a long one still navigates (ISUIElement:getJoypadNavigateStartDelay, JoypadControllerData:onHoldButton).
if CharacterCreationProfessionListBox and not CC.wrappedNav then
    CC.wrappedNav = true
    function CharacterCreationProfessionListBox:hasConflictWithJoypadNavigateStart()
        return areaOf(self) ~= nil
    end
end

local origRelease = JoypadControllerData.onReleaseButton
function JoypadControllerData:onReleaseButton(button)
    local jd = self.joypad
    -- R1 held long enough for the game to start its R1 navigation (the press was slower than its delay): if the
    -- navigation didn't move anywhere (still on the same list once it ends), it was a press of R1 meant for us
    if jd and jd.isDoingNavigation and button == Joypad.RBumper then
        local before = jd.currentNavigateUI
        local r = origRelease(self, button)
        -- (only on the character screen: R1 is held in game too, in the radio window for one)
        if areaOf(before) then
            ZA.log("[ZA] char create: R1 released while navigating, same list: " .. tostring(before == jd.focus))
        end
        if before ~= nil and before == jd.focus and areaOf(jd.focus) then switch(jd, 1) end
        return r
    end
    if jd and not jd.isDoingNavigation and (button == Joypad.LBumper or button == Joypad.RBumper) and areaOf(jd.focus) then
        if switch(jd, button == Joypad.RBumper and 1 or -1) then return end
    end
    return origRelease(self, button)
end
