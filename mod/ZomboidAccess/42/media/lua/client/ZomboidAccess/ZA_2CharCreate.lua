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
    { field = "listboxProf", name = "Occupations", cross = "{Cross} chooses this occupation" },
    { field = "listboxTrait", name = "Good traits, they cost points", cross = "{Cross} adds the trait" },
    { field = "listboxBadTrait", name = "Bad traits, they give you points", cross = "{Cross} adds the trait" },
    { field = "listboxTraitSelected", name = "Your traits", cross = "{Cross} removes the trait" },
}

local function screen(panel)
    local p = panel and panel.parent
    if p and p.Type == "CharacterCreationProfession" then return p end
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
        return (-n) .. ((-n) == 1 and " point" or " points") .. " over budget"
            .. (short and "" or ": add bad traits or remove good ones before you can go on")
    end
    return n .. (n == 1 and " point left" or " points left")
end

local function costWords(trait, inYourList)
    local ok, c = pcall(trait.getCost, trait)
    if not ok or c == nil or c == 0 then return inYourList and "free, it came with your occupation" or "" end
    if c > 0 then return "costs " .. c .. (c == 1 and " point" or " points") end
    return "gives " .. (-c) .. ((-c) == 1 and " point" or " points")
end

-- What just changed: "Added Strong." / "Removed Strong." / "Occupation: Burglar."
local memo = { traits = nil, prof = nil, msg = "" }
local function changes(s)
    local now = {}
    for _, it in ipairs(s.listboxTraitSelected.items or {}) do now[it.text] = true end
    local msg = {}
    if memo.screen == s and memo.traits then
        for t in pairs(now) do if not memo.traits[t] then table.insert(msg, "Added " .. t) end end
        for t in pairs(memo.traits) do if not now[t] then table.insert(msg, "Removed " .. t) end end
    end
    local prof = s.profession
    if memo.screen == s and prof ~= memo.prof and prof then
        msg = { "Occupation: " .. ZA.clean(prof:getUIName()) }
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
        return p, (#p.items == 0 and "Empty" or "Nothing selected, press Down"), pointsWords(n)
    end
    local data = it.item
    local extra = ""
    if a.field == "listboxProf" then
        local ok, c = pcall(data.getCost, data)
        if ok and c and c ~= 0 then extra = (c > 0 and ("gives " .. c .. " points") or ("costs " .. (-c) .. " points")) end
    else
        extra = costWords(data, a.field == "listboxTraitSelected")
    end
    local desc = ZA.clean(it.tooltip or "")
    local words = ZA.clean(it.text or "") .. (extra ~= "" and (", " .. extra) or "") .. ", " .. p.selected .. " of " .. #p.items
    if desc ~= "" then words = words .. ". " .. desc end
    local what = changes(s)
    -- Moving in the occupations list chooses what you land on: its name is already the line itself, so don't
    -- say "Occupation: Burglar" before "Burglar" on every step.
    if a.field == "listboxProf" and what == "Occupation: " .. ZA.clean(it.text or "") then what = "" end
    return it, words, (what ~= "" and (what .. ". ") or "") .. pointsWords(n, true)
end

-- Arriving in a list: the whole screen's instructions the first time, then just the list's name.
local lastScreen = nil
F.screens.CharacterCreationProfessionListBox = {
    intro = function(panel)
        local a, _, s = areaOf(panel)
        if not a then return nil end
        local parts = {}
        if s ~= lastScreen then
            lastScreen = s
            table.insert(parts, "Occupation and traits")
            table.insert(parts, pointsWords(points(s)))
            table.insert(parts, a.name)
            table.insert(parts, "Up and Down move. " .. a.cross)
            table.insert(parts, "{L1} and {R1} switch between occupations, good traits, bad traits and your traits")
            table.insert(parts, "When you're done, press {Circle}, then {Cross} for the next screen")
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
        local parts = { "Occupation and traits", pointsWords(n) }
        if n ~= nil and n < 0 then table.insert(parts, "Next is locked until you are back to zero points or more") end
        local hints = F.buttonHints(panel)
        if hints ~= "" then table.insert(parts, hints) end
        table.insert(parts, "Down goes back into the lists")
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

local origRelease = JoypadControllerData.onReleaseButton
function JoypadControllerData:onReleaseButton(button)
    local jd = self.joypad
    if jd and not jd.isDoingNavigation and (button == Joypad.LBumper or button == Joypad.RBumper) and areaOf(jd.focus) then
        if switch(jd, button == Joypad.RBumper and 1 or -1) then return end
    end
    return origRelease(self, button)
end
