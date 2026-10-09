-- Zomboid Access: the game's own small windows in the world (ovens, microwaves, barbecues, campfires, generators,
-- radios, alarm clocks and the rest).
--   Every window: a plain name instead of its code name, its text (fuel, condition, what's inside...), what each
--   dial, button and box is set to, and how to close it.
--   Dials (ISKnob): their name and the number the dial shows, Up and Down turn them.
--   Oven and microwave: on or off, power, the temperature now and what Cross does (Cross turns it on or off
--   from anywhere in the window, as the game does).

local F = ZA.F

-- ---------- names ----------

local names = {
    ISOvenUI = "Oven", ISMicrowaveUI = "Microwave", ISBBQInfoWindow = "Barbecue", ISCampingInfoWindow = "Campfire",
    ISGeneratorInfoWindow = "Generator", ISAlarmClockDialog = "Alarm clock", ISSleepDialog = "Sleep",
    ISFluidTransferUI = "Pour or transfer liquid", ISFluidInfoUI = "Liquid", ISAnimalUI = "Animal", ISHutchUI = "Hutch",
    ISVehicleMechanics = "Vehicle mechanics", ISRadioWindow = "Radio", ISDigitalCode = "Code lock",
    ISBombTimerDialog = "Timer", ISLiteratureUI = "Books and media you've read", ISFitnessUI = "Exercise",
    ISMakeUpUI = "Make-up", ISGarmentUI = "Clothing details", ISSearchWindow = "Foraging search",
    ISLightbarUI = "Lightbar and siren", ISVehicleSeatUI = "Seats", ISVehicleACUI = "Heater and air conditioning",
    ISButcherHookUI = "Butcher hook", ISMediaInfo = "Media", ISHandcraftWindow = "Crafting", ISBuildWindow = "Building",
    ISEntityWindow = "Workstation", ISFarmingInfo = "Plant", ISUIWriteJournal = "Writing", ISMapSymbolDialog = "Map symbol",
    ISCharacterInfoWindow = "Character", ISModalRichText = "Message",
}
ZA.windowNames = names

-- "ISSomeThingWindow" -> "Some thing", for windows we haven't named
local function humanType(t)
    t = t:gsub("^IS", ""):gsub("UI$", ""):gsub("Window$", ""):gsub("Dialog$", ""):gsub("Panel$", "")
    t = t:gsub("(%l)(%u)", "%1 %2")
    return t:sub(1, 1):upper() .. t:sub(2):lower()
end

-- ---------- reading a window ----------

-- Rich text the game wrote into the window: a tooltip panel's description, a rich text panel, a text field.
local function windowText(w)
    for _, k in ipairs({ "panel", "richText", "textPanel", "infoText", "description" }) do
        local c = w[k]
        if type(c) == "string" and c ~= "" then return ZA.clean(c) end
        if type(c) == "table" then
            local t = c.description or c.text
            if type(t) == "string" and t ~= "" then return ZA.clean(t) end
        end
    end
    return nil
end

-- The plain labels in a window, top to bottom (headings, values the game draws as labels).
local function labelTexts(w)
    local out = {}
    if not w.getChildren then return out end
    local list = {}
    for _, ch in pairs(w:getChildren()) do
        if ch.Type == "ISLabel" and ch:isVisible() then table.insert(list, ch) end
    end
    table.sort(list, function(a, b) return a:getY() < b:getY() end)
    for _, l in ipairs(list) do
        local t = ZA.clean(l.name or "")
        if t ~= "" then table.insert(out, t) end
    end
    return out
end

local specials = {}   -- per window type: function(w) -> sentence about its state

local function isWorldWindow(panel)
    if not panel or not panel.Type then return false end
    if names[panel.Type] then return true end
    return false
end

local origIntro = F.screenIntro
function F.screenIntro(panel)
    if not isWorldWindow(panel) then
        -- a window the mod doesn't know: at least not its code name
        local t = origIntro(panel)
        if panel and panel.Type and t:find("^" .. panel.Type) then
            t = humanType(panel.Type) .. t:sub(#panel.Type + 1)
        end
        return t
    end
    local parts = { names[panel.Type] }
    local sp = specials[panel.Type]
    if sp then
        local ok, s = pcall(sp, panel)
        if ok and s and s ~= "" then table.insert(parts, s) end
        if not ok then print("[ZA] window error " .. panel.Type .. ": " .. tostring(s)) end
    end
    local txt = windowText(panel)
    if txt then table.insert(parts, txt) end
    if not sp then
        for _, l in ipairs(labelTexts(panel)) do table.insert(parts, l) end
    end
    local hints = F.buttonHints(panel)
    if hints ~= "" then table.insert(parts, hints) else table.insert(parts, "{Circle} closes") end
    for i, t in ipairs(parts) do parts[i] = t:gsub("[%.%s]+$", "") end
    return table.concat(parts, ". ")
end

-- ---------- dials ----------

-- The Fahrenheit oven dial is labelled 0, 250, 300 ... 500 (read from its picture, KnobBGFarhenOvenTemp in UI2.pack);
-- the Celsius one 0, 50 ... 300, the same as the game's values.
local ovenF = { 0, 250, 300, 350, 400, 450, 500 }

local function knobWords(k)
    local v = k:getValue()
    local title = ZA.clean(k.title or "")
    local w = k.parent
    local s
    if w and w.tempKnob == k then
        if w.Type == "ISOvenUI" and not getCore():isCelsius() then
            s = (ovenF[k.selected] or v) .. " degrees Fahrenheit"
        elseif w.Type == "ISOvenUI" then
            s = v .. " degrees Celsius"
        else
            -- the microwave's dial is a power level: 50, 70, 90, 110, 130
            s = "power " .. math.floor((v - 30) / 20 + 0.5) .. " of 5"
        end
        if v == 0 and w.Type == "ISOvenUI" then s = "off" end
    elseif w and w.timerKnob == k then
        s = v == 0 and "no timer" or (v .. (v == 1 and " minute" or " minutes"))
    else
        s = tostring(v)
    end
    return title .. ": " .. s .. ", dial, Up and Down turn it", title .. ": " .. s
end

local origBare = F.describeBare
function F.describeBare(ui)
    if ui and ui.isKnob then return knobWords(ui) end
    return origBare(ui)
end

-- ---------- oven and microwave ----------

local function stoveState(w)
    local o = w.oven or w.microwave or w.object
    if not o then return nil end
    local parts = {}
    local powered = o:getContainer() and o:getContainer():isPowered()
    if not powered then
        table.insert(parts, "No power: it won't turn on")
    else
        table.insert(parts, o:Activated() and "On" or "Off")
    end
    local ok, cur = pcall(function() return o:getCurrentTemperature() end)
    if ok and cur and cur > 1 then
        table.insert(parts, "warming: " .. math.floor(cur / math.max(1, o:getMaxTemperature()) * 100 + 0.5) .. " percent of the set heat")
    end
    local c = o:getContainer()
    if c then
        local n = c:getItems():size()
        table.insert(parts, n == 0 and "Empty" or (n .. (n == 1 and " thing inside" or " things inside")))
    end
    table.insert(parts, "{Cross} turns it " .. (o:Activated() and "off" or "on") .. " from anywhere in this window. Left and Right move between the dials")
    return table.concat(parts, ". ")
end
specials.ISOvenUI = stoveState
specials.ISMicrowaveUI = stoveState

-- On and off while the window is open: say it.
local lastOn = {}
ZA.onTick(function()
    for _, cls in ipairs({ ISOvenUI, ISMicrowaveUI }) do
        if cls and cls.instance then
            local w = cls.instance[1]
            if w and w:isVisible() then
                local o = w.oven or w.microwave
                if o then
                    local on = o:Activated()
                    if lastOn[w] ~= nil and lastOn[w] ~= on then ZA.say(on and "Turned on" or "Turned off") end
                    lastOn[w] = on
                end
            end
        end
    end
end)

-- ---------- info windows: barbecue, campfire, generator ----------
-- The text is the window itself: read on opening. While it's open, say it again when it changes in more than numbers
-- (the fire goes out, the generator runs dry), not every time the fuel ticks down.

local lastShape = {}
ZA.onTick(function()
    local jd = ZA.joypad()
    local w = jd and jd.focus
    if not (w and (w.Type == "ISBBQInfoWindow" or w.Type == "ISCampingInfoWindow" or w.Type == "ISGeneratorInfoWindow")) then return end
    local t = windowText(w)
    if not t then return end
    local shape = t:gsub("[%d%.:]+", "#")
    if lastShape[w] and lastShape[w] ~= shape then ZA.say(t) end
    lastShape[w] = shape
end)

-- ---------- vehicle mechanics ----------
-- Two lists: engine and insides (left), doors, body and lights (right); headings between. Each part: name,
-- condition, fuel or charge left, or "not installed". (ISVehicleMechanics draws these itself, unread.)

local function partWords(part)
    local parts = {}
    local missing = false
    pcall(function() missing = part:getInventoryItem() == nil and part:getItemType() ~= nil and not part:getItemType():isEmpty() end)
    if missing then
        table.insert(parts, "not installed")
    else
        local c = "?"
        pcall(function() c = tostring(part:getCondition()) end)
        table.insert(parts, c .. " percent condition")
    end
    pcall(function()
        if part:isContainer() and part:getContainerContentType() then
            local cap = part:getContainerCapacity()
            if cap and cap > 0 then
                table.insert(parts, math.floor(part:getContainerContentAmount() / cap * 100) .. " percent full")
            end
        end
    end)
    pcall(function()
        local it = part:getInventoryItem()
        if part:getId() == "Battery" and it then
            table.insert(parts, math.floor(it:getCurrentUsesFloat() * 100) .. " percent charge")
        end
    end)
    return table.concat(parts, ", ")
end

F.readers.ISVehicleMechanics = function(w)
    local list = w.leftListHasFocus and w.listbox or w.bodyworklist
    local i = list and list.selected
    local it = list and list.items and list.items[i]
    if not it then return w, "", "" end
    local d = it.item
    local side = w.leftListHasFocus and "engine and insides" or "doors, body and lights"
    if d.cat then
        return it, ZA.clean(d.name or "") .. ", heading, " .. side .. ", " .. i .. " of " .. #list.items, ""
    end
    local words = ZA.clean(d.name or "") .. ", " .. partWords(d.part)
    return it, words .. ", " .. i .. " of " .. #list.items, ""
end
specials.ISVehicleMechanics = function(w)
    local s = ""
    pcall(function() w:recalculGeneralCondition() end)
    if w.generalCondition then s = "Overall condition " .. math.floor(w.generalCondition) .. " percent. " end
    return s .. "Up and Down: the parts. Left: engine and insides. Right: doors, body and lights. {Cross}: what you can do with a part"
end

-- ---------- vehicle seats ----------
-- Seats laid out as in the car, two to a row: Left and Right across, Up and Down between rows. Cross sits there,
-- Square gets out by that seat's door, Circle cancels. (ISVehicleSeatUI draws the seat name itself, unread.)

F.readers.ISVehicleSeatUI = function(w)
    local v = w.vehicle
    if not v or not w.joypadSeat then return w, "", "" end
    local seat = w.joypadSeat - 1
    local script = v:getScript()
    local id = script:getPassenger(seat):getId()
    local name = getTextOrNull("IGUI_Seat" .. id) or id
    local parts = { name .. (seat == 0 and ", the driver's seat" or "") }
    local status = "empty"
    pcall(function()
        if not w:isSeatInstalled(seat) then status = "no seat fitted"
        elseif v:getSeat(w.character) == seat then status = "where you are"
        elseif v:getCharacter(seat) then status = "someone's in it"
        elseif v:isSeatOccupied(seat) then status = "things on it"
        end
    end)
    table.insert(parts, status)
    return seat, table.concat(parts, ", ") .. ", " .. w.joypadSeat .. " of " .. script:getPassengerCount(), ""
end
specials.ISVehicleSeatUI = function(w)
    return "Choose a seat. Left and Right across the car, Up and Down between rows. {Cross} sits there, {Square} gets out by that seat's door. {Circle} cancels"
end
