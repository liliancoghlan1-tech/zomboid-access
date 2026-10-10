-- Zomboid Access: the character's name and looks (CharacterCreationMain).
-- Controls sit beside separate text labels; the sex choice has no label at all. This names every
-- control, and the screen's own buttons (after Circle) come with a summary of the character.

local F = ZA.F
local AP = {}
ZA.AP = AP

local function main() return CharacterCreationMain and CharacterCreationMain.instance end

local function nameControls()
    local m = main()
    if not m or m.zaNamed then return end
    local labels = {
        genderCombo = "Sex", forenameEntry = "Forename", surnameEntry = "Surname",
        hairTypeCombo = "Hair style", hairStubbleTickBox = "Hair stubble",
        voiceTypeCombo = "Voice type", voicePitchSlider = "Voice pitch", beardTypeCombo = "Beard style",
        beardStubbleTickBox = "Beard stubble", savedBuilds = "Saved looks",
        skinColorButton = "Skin colour", hairColorButton = "Hair colour",
    }
    for field, label in pairs(labels) do
        if m[field] then m[field].zaLabel = label end
    end
    m.zaNamed = true
end

-- "Dewitt Yoon, a man. Occupation: Burglar. Traits: Strong, Clumsy."
function AP.summary()
    local desc = MainScreen.instance and MainScreen.instance.desc
    if not desc then return "" end
    local parts = {}
    -- The game copies the name boxes into desc only when the game starts, so a typed name is in the boxes.
    local m = main()
    local fore = m and m.forenameEntry and m.forenameEntry:getText() or desc:getForename()
    local sur = m and m.surnameEntry and m.surnameEntry:getText() or desc:getSurname()
    local name = ZA.clean((fore or "") .. " " .. (sur or ""))
    table.insert(parts, name .. ", " .. (desc:isFemale() and "a woman" or "a man"))
    local cp = MainScreen.instance.charCreationProfession
    if cp and cp.profession then
        table.insert(parts, "Occupation: " .. ZA.clean(cp.profession:getUIName()))
    end
    if cp and cp.listboxTraitSelected and #cp.listboxTraitSelected.items > 0 then
        local t = {}
        for _, it in ipairs(cp.listboxTraitSelected.items) do table.insert(t, ZA.clean(it.text)) end
        table.insert(parts, "Traits: " .. table.concat(t, ", "))
    end
    return table.concat(parts, ". ")
end

local function isSkin(btn) local m = main(); return m and btn == m.skinColorButton end
local function isHair(btn) local m = main(); return m and btn == m.hairColorButton end

-- The colour buttons have no text: say the colour they show.
local origBare = F.describeBare
function F.describeBare(ui)
    if ui and ui.Type == "ISButton" and (isSkin(ui) or isHair(ui)) and ui.backgroundColor then
        local c = ui.backgroundColor
        local name = isSkin(ui) and (ZA.skinName(c.r, c.g, c.b) .. " skin") or (ZA.colourName(c.r, c.g, c.b) .. " hair")
        return name .. ", colour button, {Cross} opens the colours", name
    end
    return origBare(ui)
end

-- The colour grid that opens from those buttons.
F.readers.ISColorPicker = function(p)
    local c = p.colors and p.colors[p.index]
    if not c then return nil end
    local m = main()
    local name = (m and p == m.colorPickerSkin) and (ZA.skinName(c.r, c.g, c.b) .. " skin") or ZA.colourName(c.r, c.g, c.b)
    return p.index, name .. ZA.pos(p.index, #p.colors), ""
end
F.screens.ISColorPicker = {
    intro = function(p)
        local m = main()
        local what = (m and p == m.colorPickerSkin) and "Skin colour" or "Hair colour"
        local rows = p.rows and p.rows > 1 and "The arrows move around the grid" or "Left and Right move"
        return what .. ". " .. rows .. ". {Cross} picks the colour, {Circle} closes without changing"
    end,
}

F.screens.CharacterCreationMainCharacterPanel = {
    intro = function(panel)
        nameControls()
        return "Your character's name and looks. Up and Down move between settings, Left and Right along a row. "
            .. "{Cross} opens a drop-down list, then Up and Down choose and {Cross} confirms; {Cross} also ticks a box or edits a name. "
            .. "When you're done, press {Circle}, then {Cross} to start the game"
    end,
}

F.screens.CharacterCreationMain = {
    intro = function(panel)
        nameControls()
        local parts = { "Character ready", AP.summary() }
        local hints = F.buttonHints(panel)
        if hints ~= "" then table.insert(parts, hints) end
        table.insert(parts, "Up goes back to the settings")
        return table.concat(parts, ". ")
    end,
}

ZA.onTick(function()
    if main() and main():isVisible() then nameControls() end
end)

-- Voice Preview switches the game's music to "InGame" to play the voice (the game's own FIXME: "main menu music
-- stops when this is set"), which silenced the menu music for good. Put the menu music back once the voice has
-- had time to play.
local restoreMusicAt = nil
if CharacterCreationMain and CharacterCreationMain.onOptionMouseDown and not AP.wrappedPreview then
    AP.wrappedPreview = true
    local orig = CharacterCreationMain.onOptionMouseDown
    CharacterCreationMain.onOptionMouseDown = function(self, button, ...)
        local r = orig(self, button, ...)
        if button and button.internal == "PLAYDEMOVOICE" and not (MainScreen.instance and MainScreen.instance.inGame) then
            restoreMusicAt = getTimestampMs() + 2500
        end
        return r
    end
end
ZA.onTick(function()
    if restoreMusicAt and getTimestampMs() >= restoreMusicAt then
        restoreMusicAt = nil
        if not (MainScreen.instance and MainScreen.instance.inGame) then getSoundManager():setMusicState("MainMenu") end
    end
end)
