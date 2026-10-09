-- Zomboid Access: the mod's settings at the end of the game's Options, Accessibility tab: positions in lists on or
-- off, and the voices.
-- Two voices: everything the mod says, and the radio (the tutorial guide). Each is the screen reader, or a SAPI or
-- OneCore voice with its own speed and volume, so the radio can talk alongside the screen reader.
-- The speech bridge lists the voices and the current settings in Zomboid/Lua/ZomboidAccess_voices.txt, and keeps
-- the settings itself; a change here goes to it at once ("V" line), with a sample for the radio ("T" line).

ZA.V = ZA.V or {}
local V = ZA.V
V.file = "ZomboidAccess_voices.txt"
V.channels = {
    { id = "speech", title = "Zomboid Access voice" },
    { id = "radio", title = "Radio voice", sample = "This is the radio. Can you hear me?" },
}

-- Fields between tabs, keeping empty ones (a screen reader has no voice name).
local function split(line)
    local t = {}
    for field in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(t, field) end
    return t
end

-- What the bridge wrote, or nil if it isn't running.
function V.read()
    local r = getFileReader(V.file, false)
    if not r then return nil end
    local st = { reader = "screen reader", voices = {}, set = {} }
    local line = r:readLine()
    while line do
        local f = split(line)
        if f[1] == "reader" then st.reader = f[2]
        elseif f[1] == "voice" then table.insert(st.voices, { engine = f[2], voice = f[3] })
        elseif f[1] == "set" and f[2] then
            st.set[f[2]] = { engine = f[3], voice = f[4] or "", rate = tonumber(f[5]) or 50, volume = tonumber(f[6]) or 100 }
        end
        line = r:readLine()
    end
    r:close()
    if #st.voices == 0 and not st.set.speech then return nil end
    return st
end

-- The drop-down's entries: the screen reader first, then every voice.
local function choices(st)
    local list = { { engine = "screen reader", voice = "", text = "Screen reader (" .. st.reader .. ")" } }
    for _, v in ipairs(st.voices) do
        table.insert(list, { engine = v.engine, voice = v.voice, text = v.engine .. ": " .. v.voice })
    end
    return list
end

local function send(row, sample)
    local c = row.choices[row.combo.selected] or row.choices[1]
    ZA.bridge("V", row.id, c.engine, c.voice, row.rate:getCurrentValue(), row.volume:getCurrentValue())
    -- The everyday voice is heard at once, saying the new setting; the radio says something of its own.
    if sample and row.sample then ZA.bridge("T", row.id, row.sample) end
end

local function toUI(row)
    local st = V.read()
    local s = st and st.set[row.id]
    if not s then return end
    row.combo.selected = 1
    for i, c in ipairs(row.choices) do
        if c.engine == s.engine and (c.engine == "screen reader" or c.voice == s.voice) then row.combo.selected = i end
    end
    row.rate:setCurrentValue(s.rate, true)
    row.volume:setCurrentValue(s.volume, true)
    row.rate.label:setName(tostring(s.rate))
    row.volume.label:setName(tostring(s.volume))
end

local function option(self, name, control, row)
    local o = GameOption:new(name, control)
    function o.toUI() toUI(row) end
    function o.apply() send(row, false) end
    function o.onChange()
        if control.label then control.label:setName(tostring(control:getCurrentValue())) end
        send(row, true)
    end
    self.gameOptions:add(o)
end

function V.addRows(self)
    local y = MainOptions.style.initialY
    local splitpoint = self:getWidth() / 2
    local comboWidth = 45 * (getCore():getOptionFontSizeReal() + 1) + 60
    self:addHorizontalLine(y, "Zomboid Access")

    -- Positions in lists and menus ("2 of 25"): on unless turned off here; changes at once.
    local hgt = MainOptions.style.buttonHeight
    local positions = self:addYesNo(splitpoint, y, hgt, hgt, "Say positions in lists, like 2 of 25")
    positions.zaLabel = "Say positions in lists, like 2 of 25"
    local po = GameOption:new("zaPositions", positions)
    function po.toUI() positions:setSelected(1, ZA.settings.positions ~= false) end
    function po.apply() ZA.setSetting("positions", positions:isSelected(1)) end
    function po.onChange() ZA.setSetting("positions", positions:isSelected(1)) end
    self.gameOptions:add(po)
    po.toUI()

    local st = V.read()
    if not st then
        self:addDescription(splitpoint - 200, y,
            "Voices can be chosen here when the game is started with the speech bridge (the installer sets this up in Steam).")
    else
        local list = choices(st)
        local names = {}
        for i, c in ipairs(list) do names[i] = c.text end
        for _, ch in ipairs(V.channels) do
            local row = { id = ch.id, sample = ch.sample, choices = list }
            row.combo = self:addCombo(splitpoint, y, comboWidth, 20, ch.title, names, 1)
            row.combo.zaLabel = ch.title
            row.rate = self:addSlider(splitpoint, y, comboWidth, ch.title .. " speed", 0, 100, 5, 50)
            row.rate.zaLabel = ch.title .. " speed (SAPI and OneCore voices)"
            row.volume = self:addSlider(splitpoint, y, comboWidth, ch.title .. " volume", 0, 100, 5, 100)
            row.volume.zaLabel = ch.title .. " volume (SAPI and OneCore voices)"
            option(self, "zaVoice_" .. ch.id, row.combo, row)
            option(self, "zaVoiceRate_" .. ch.id, row.rate, row)
            option(self, "zaVoiceVolume_" .. ch.id, row.volume, row)
            toUI(row)
        end
    end
    self.mainPanel:setScrollHeight(y + self.addY + 20)
end

if MainOptions and MainOptions.addAccessibilityPanel and not V.wrapped then
    V.wrapped = true
    local orig = MainOptions.addAccessibilityPanel
    function MainOptions:addAccessibilityPanel(...)
        orig(self, ...)
        local ok, err = pcall(V.addRows, self)
        if not ok then print("[ZA] voice options failed: " .. tostring(err)) end
    end
end
