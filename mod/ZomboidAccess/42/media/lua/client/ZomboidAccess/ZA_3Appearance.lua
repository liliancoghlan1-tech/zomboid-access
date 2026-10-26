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
        genderCombo = ZA.tr("Appearance_LblSex"), forenameEntry = ZA.tr("Appearance_LblForename"),
        surnameEntry = ZA.tr("Appearance_LblSurname"),
        hairTypeCombo = ZA.tr("Appearance_LblHairStyle"), hairStubbleTickBox = ZA.tr("Appearance_LblHairStubble"),
        voiceTypeCombo = ZA.tr("Appearance_LblVoiceType"), voicePitchSlider = ZA.tr("Appearance_LblVoicePitch"),
        beardTypeCombo = ZA.tr("Appearance_LblBeardStyle"),
        beardStubbleTickBox = ZA.tr("Appearance_LblBeardStubble"), savedBuilds = ZA.tr("Appearance_LblSavedLooks"),
        skinColorButton = ZA.tr("Appearance_LblSkinColour"), hairColorButton = ZA.tr("Appearance_LblHairColour"),
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
    table.insert(parts, ZA.tr(desc:isFemale() and "Appearance_Woman" or "Appearance_Man", name))
    local cp = MainScreen.instance.charCreationProfession
    if cp and cp.profession then
        table.insert(parts, ZA.tr("Appearance_Occupation", ZA.clean(cp.profession:getUIName())))
    end
    if cp and cp.listboxTraitSelected and #cp.listboxTraitSelected.items > 0 then
        local t = {}
        for _, it in ipairs(cp.listboxTraitSelected.items) do table.insert(t, ZA.clean(it.text)) end
        table.insert(parts, ZA.tr("Appearance_Traits", table.concat(t, ", ")))
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
        local name = isSkin(ui) and ZA.tr("Appearance_SkinOf", ZA.skinName(c.r, c.g, c.b))
            or ZA.tr("Appearance_HairOf", ZA.colourName(c.r, c.g, c.b))
        return ZA.tr("Appearance_ColourBtn", name), name
    end
    return origBare(ui)
end

-- The colour grid that opens from those buttons.
F.readers.ISColorPicker = function(p)
    local c = p.colors and p.colors[p.index]
    if not c then return nil end
    local m = main()
    local name = (m and p == m.colorPickerSkin) and ZA.tr("Appearance_SkinOf", ZA.skinName(c.r, c.g, c.b)) or ZA.colourName(c.r, c.g, c.b)
    return p.index, name .. ZA.pos(p.index, #p.colors), ""
end
F.screens.ISColorPicker = {
    intro = function(p)
        local m = main()
        local what = (m and p == m.colorPickerSkin) and ZA.tr("Appearance_LblSkinColour") or ZA.tr("Appearance_LblHairColour")
        local rows = p.rows and p.rows > 1 and ZA.tr("Appearance_GridMove") or ZA.tr("Appearance_RowMove")
        return ZA.tr("Appearance_PickerIntro", what, rows)
    end,
}

F.screens.CharacterCreationMainCharacterPanel = {
    intro = function(panel)
        nameControls()
        return ZA.tr("Appearance_PanelIntro")
    end,
}

F.screens.CharacterCreationMain = {
    intro = function(panel)
        nameControls()
        local parts = { ZA.tr("Appearance_Ready"), AP.summary() }
        local hints = F.buttonHints(panel)
        if hints ~= "" then table.insert(parts, hints) end
        table.insert(parts, ZA.tr("Appearance_UpBack"))
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
