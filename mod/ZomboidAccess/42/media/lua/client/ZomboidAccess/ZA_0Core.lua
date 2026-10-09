-- Zomboid Access: core.
-- Speech: every line goes to Zomboid/Lua/ZomboidAccess_speech.txt, which our speech bridge reads aloud.
--   "S<tab>text" = say now (interrupts), "Q<tab>text" = say after what is already speaking,
--   "G<tab>text" = the tutorial guide (protected), "U<tab>text" = urgent (see ZA.say below).
-- Every line is also printed to console.txt with a [ZA] tag, so a test can read what was said.
-- Test channel (developers only): lines written to Zomboid/Lua/ZomboidAccess_cmd.txt are run as Lua, one per
-- tick, ONLY when Zomboid/Lua/ZomboidAccess_dev.txt exists. Players never have that file, so for them it's off.

ZA = ZA or {}

-- a modulo n, always 0 <= result < n. Kahlua's % keeps the sign of a negative a (-1 % 13 = -1),
-- unlike standard Lua: use this for every wrap-around.
function ZA.mod(a, n)
    local r = math.fmod(a, n)
    if r < 0 then r = r + n end
    return r
end
ZA.version = "0.9.3"
ZA.speechFile = "ZomboidAccess_speech.txt"
ZA.cmdFile = "ZomboidAccess_cmd.txt"

-- Developer mode: on only when Zomboid/Lua/ZomboidAccess_dev.txt exists (checked once at start). Players never
-- have that file. It turns on the test channel below and the mod's log lines (ZA.log): everything said, the
-- scanner's work, walking... in console.txt, for test tools. Errors are always logged (print).
do
    local r = getFileReader("ZomboidAccess_dev.txt", false)
    ZA.dev = r ~= nil
    if r then r:close() end
end
function ZA.log(text)
    if ZA.dev then print(text) end
end

-- ---------- settings ----------
-- The mod's own choices (Options, Accessibility, Zomboid Access), one "name=value" a line in
-- Zomboid/Lua/ZomboidAccess_options.txt. Voices are kept by the speech bridge instead.

ZA.optionsFile = "ZomboidAccess_options.txt"
ZA.settings = { positions = true }
do
    local r = getFileReader(ZA.optionsFile, false)
    if r then
        local line = r:readLine()
        while line do
            local k, v = line:match("^([%w_]+)=(.*)$")
            if k then
                -- not "v == 'false' and false or v": that gives the string back, never false
                if v == "true" then v = true elseif v == "false" then v = false end
                ZA.settings[k] = v
            end
            line = r:readLine()
        end
        r:close()
    end
end
function ZA.setSetting(name, value)
    ZA.settings[name] = value
    local w = getFileWriter(ZA.optionsFile, true, false)
    if w then
        for k, v in pairs(ZA.settings) do w:write(k .. "=" .. tostring(v) .. "\n") end
        w:close()
    end
end

-- A place in a list, ", 2 of 25", unless the player turned positions off.
function ZA.pos(i, n)
    if ZA.settings.positions == false then return "" end
    return ", " .. tostring(i) .. " of " .. tostring(n)
end

-- ---------- text ----------

-- Button names. The mod's own words write a button as {Cross}, {R2}, {Share}... (the PlayStation names), and they
-- are said the way the game's own Controller option "Button style" labels them: Xbox, PlayStation or Steam Deck.
-- Only these marks change, never the game's own text ("Square Table", "Wooden Cross").
ZA.buttonNames = {
    [1] = { Cross = "A", Circle = "B", Square = "X", Triangle = "Y", L1 = "LB", R1 = "RB", L2 = "LT", R2 = "RT",
        L3 = "the left stick click", R3 = "the right stick click", Share = "View", Options = "Menu" },
    [3] = { Cross = "A", Circle = "B", Square = "X", Triangle = "Y", Share = "View", Options = "Menu" },
}
function ZA.buttonStyle()
    local ok, style = pcall(function() return getCore():getOptionControllerButtonStyle() end)
    return ok and style or 2
end
function ZA.buttons(text)
    local names = ZA.buttonNames[ZA.buttonStyle()] or {}
    return (text:gsub("{(%w+)}", function(b) return names[b] or b end))
end

-- Controller buttons drawn as pictures in game text (<JOYPAD:AButton,28,28>, .../PS4_A.png).
ZA.padWords = {
    AButton = "{Cross}", BButton = "{Circle}", XButton = "{Square}", YButton = "{Triangle}",
    A = "{Cross}", B = "{Circle}", X = "{Square}", Y = "{Triangle}",
    LBumper = "{L1}", RBumper = "{R1}", LB = "{L1}", RB = "{R1}",
    LTrigger = "{L2}", RTrigger = "{R2}", LT = "{L2}", RT = "{R2}",
    LStick = "the left stick", RStick = "the right stick",
    LStickButton = "{L3}", RStickButton = "{R3}",
    DPadUp = "D-pad up", DPadDown = "D-pad down", DPadLeft = "D-pad left", DPadRight = "D-pad right",
    DPad = "the D-pad", Back = "{Share}", Start = "{Options}", Select = "{Share}",
}

function ZA.clean(text)
    if text == nil then return "" end
    text = tostring(text)
    text = text:gsub("<JOYPAD:([%w_]+)[^>]*>", function(b) return " " .. (ZA.padWords[b] or b) .. " " end)
    text = text:gsub("<IMAGE:[^>]-controller/[%w]+_([%w]+)%.png[^>]*>", function(b) return " " .. (ZA.padWords[b] or b) .. " " end)
    text = text:gsub("<[^>]*>", " ")
    text = text:gsub("%s+([%.,])", "%1")          -- rich text tags: <RGB:1,0,0>, <LINE>, <BR>, <CENTRE>...
    text = text:gsub("[\r\n\t]+", " ")
    text = text:gsub("%s%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return ZA.buttons(text)
end

-- ---------- speech ----------

local lastText, lastTime = nil, 0

-- The file only grows while the game runs, so past this size it starts again. Only after a quiet half second:
-- the bridge reads every 40 ms, so by then it has every line, and none is lost to the restart.
local SPEECH_FILE_MAX = 256 * 1024
function ZA.speechFileStart() return "#" .. tostring(getTimestampMs()) .. "\n" end
local written, lastWrite = 0, 0

local function writeLine(line)
    local now = getTimestampMs()
    local fresh = written > SPEECH_FILE_MAX and now - lastWrite > 500
    local w = getFileWriter(ZA.speechFile, true, not fresh)
    if w then
        if fresh then w:write(ZA.speechFileStart()) end
        w:write(line)
        w:close()
        written = (fresh and 0 or written) + #line
        lastWrite = now
    end
end

local function write(kind, text)
    writeLine(kind .. "\t" .. text .. "\n")
    ZA.log("[ZA] " .. (kind == "S" and "" or kind .. " ") .. text)
end

-- A command for the bridge rather than words to say, e.g. ZA.bridge("V", "radio", "SAPI", "Brian", 50, 100).
function ZA.bridge(...)
    local fields = {}
    for i, v in ipairs({ ... }) do fields[i] = tostring(v):gsub("[\t\r\n]", " ") end
    writeLine(table.concat(fields, "\t") .. "\n")
end

-- kind: "S" say now (interrupts), "Q" after what is speaking, "P" say now and don't let the next lines cut it
-- off, "G" the tutorial guide on the radio (its own voice, or protected like "P" when it shares the everyday
-- voice), "U" urgent: danger and combat, always at once.
local function speak(text, kind)
    text = ZA.clean(text)
    if text == "" then return end
    local now = getTimestampMs()
    -- The same line twice within half a second is one event seen twice (e.g. two hooks).
    if text == lastText and now - lastTime < 500 then return end
    lastText, lastTime = text, now
    ZA.last = text
    write(kind, text)
end

function ZA.say(text, queue) speak(text, queue and "Q" or "S") end
function ZA.queue(text) speak(text, "Q") end
function ZA.guide(text) speak(text, "G") end
function ZA.protected(text) speak(text, "P") end
-- In the tutorial nothing can really hurt you, so there the guide's words win: urgent is plain "S" there.
function ZA.urgent(text)
    local tutorial = false
    pcall(function() tutorial = ZA.TU and ZA.TU.active and ZA.TU.active() end)
    speak(text, tutorial and "S" or "U")
end

function ZA.repeatLast()
    if ZA.last then lastText = nil; ZA.say(ZA.last) end
end

-- Start each session with a fresh speech file, so the bridge never replays old lines.
-- Every fresh file begins with "#<time>": the bridge knows a new file by its first line changing, even when the
-- new one is already as long as what it had read of the old one.
do
    local w = getFileWriter(ZA.speechFile, true, false)
    if w then w:write(ZA.speechFileStart()); w:close() end
end

-- ---------- ticks ----------
-- Some events stop on the main menu or while paused, so listen to several and run once per frame.

ZA.tickers = ZA.tickers or {}
local lastFrame = -1
ZA.seenEvents = {}

local function tick(source)
    if not ZA.seenEvents[source] then
        ZA.seenEvents[source] = true
        ZA.log("[ZA] event fires: " .. source)
    end
    local now = getTimestampMs()
    if now == lastFrame then return end
    if now - lastFrame < 15 then return end
    lastFrame = now
    for _, f in ipairs(ZA.tickers) do
        local ok, err = pcall(f)
        if not ok then print("[ZA] ticker error: " .. tostring(err)) end
    end
end

function ZA.onTick(f) table.insert(ZA.tickers, f) end

for _, name in ipairs({ "OnTick", "OnTickEvenPaused", "OnRenderTick", "OnPreUIDraw", "OnPostUIDraw", "OnFETick" }) do
    if Events[name] then
        Events[name].Add(function() tick(name) end)
    end
end

-- ---------- test channel ----------

-- (ZA.dev: see the top of this file.)
local cmdNext, cmdDone = 0, 0
-- The file is only appended to by the test tools; the mod remembers how many lines it has run.
-- (Rewriting the file to remove a line lost lines the tools appended at the same moment.)
if ZA.dev then
    local w = getFileWriter(ZA.cmdFile, true, false)
    if w then w:write(""); w:close() end
end
ZA.onTick(function()
    if not ZA.dev then return end
    local now = getTimestampMs()
    if now < cmdNext then return end
    cmdNext = now + 200
    local r = getFileReader(ZA.cmdFile, false)
    if not r then return end
    local lines = {}
    local line = r:readLine()
    while line do
        table.insert(lines, line)
        line = r:readLine()
    end
    r:close()
    if #lines < cmdDone then cmdDone = 0 end
    if #lines == cmdDone then return end
    cmdDone = cmdDone + 1
    local cmd = lines[cmdDone]
    if cmd == nil or cmd == "" then return end
    ZA.log("[ZA] cmd: " .. cmd)
    local f, err = loadstring(cmd)
    if not f then print("[ZA] cmd compile error: " .. tostring(err)); return end
    local ok, res = pcall(f)
    if not ok then print("[ZA] cmd error: " .. tostring(res))
    elseif res ~= nil then ZA.log("[ZA] cmd result: " .. tostring(res)) end
end)

Events.OnGameBoot.Add(function() ZA.log("[ZA] Zomboid Access " .. ZA.version .. " loaded") end)
Events.OnMainMenuEnter.Add(function() ZA.log("[ZA] main menu entered") end)

-- ---------- colours ----------
-- Plain words for a colour (r, g, b from 0 to 1): "dark brown", "light grey", "golden blonde".
function ZA.colourName(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local v, d = mx, mx - mn
    local s = mx > 0 and d / mx or 0
    if s < 0.12 then
        if v > 0.9 then return "white" elseif v > 0.65 then return "light grey"
        elseif v > 0.35 then return "grey" elseif v > 0.15 then return "dark grey" else return "black" end
    end
    local h
    if mx == r then h = ZA.mod((g - b) / d, 6) elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
    local base
    if (h >= 18 and h < 50) and v < 0.62 then base = "brown"
    elseif h >= 30 and h < 58 and s < 0.65 and v >= 0.62 then base = "blonde"
    elseif h < 15 or h >= 345 then base = "red"
    elseif h < 40 then base = "orange"
    elseif h < 68 then base = "yellow"
    elseif h < 160 then base = "green"
    elseif h < 200 then base = "teal"
    elseif h < 250 then base = "blue"
    elseif h < 290 then base = "purple"
    else base = "pink" end
    local shade = ""
    if v < 0.3 then shade = "very dark "
    elseif v < 0.5 then shade = "dark "
    elseif v > 0.85 and s < 0.45 then shade = "light " end
    return shade .. base
end

-- Skin: from lightest to darkest by how bright it is.
function ZA.skinName(r, g, b)
    local v = 0.3 * r + 0.59 * g + 0.11 * b
    if v > 0.82 then return "very light" elseif v > 0.68 then return "light"
    elseif v > 0.5 then return "medium" elseif v > 0.33 then return "dark" else return "very dark" end
end
