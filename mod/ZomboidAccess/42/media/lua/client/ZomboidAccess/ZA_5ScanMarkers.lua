-- Zomboid Access: your own map markers ("Home", "Loot stash"...), saved with the game.
--   Make one: the last line of the scanner's "You" list, "Mark this spot", then Square (or End).
--     The first is called Home; a box opens to type another name (Enter keeps it, Escape keeps the default).
--   The "Markers" category (one step right of You) lists them, nearest first, with distance and direction.
--   Square / End travels there (in legs, like Places); hold Square twice to remove one.

ZA.MK = ZA.MK or {}
local MK = ZA.MK
local S = ZA.S

-- The save's own list (ModData is written into the save file).
function MK.all()
    local md = ModData.getOrCreate("ZomboidAccessMarkers")
    md.list = md.list or {}
    return md.list
end

function MK.add()
    local p = getPlayer()
    local list = MK.all()
    -- the first marker is called Home (in the game language); markers saved earlier may still say Home in English
    local home = ZA.tr("ScanMarkers_Home")
    local name = home
    for _, m in ipairs(list) do
        if m.name == home or m.name == "Home" then name = ZA.tr("ScanMarkers_Default", #list + 1) end
    end
    local m = { name = name, x = math.floor(p:getX()) + 0.5, y = math.floor(p:getY()) + 0.5, z = math.floor(p:getZ()) }
    table.insert(list, m)
    S.builtAt = -1e9
    ZA.log("[ZA] marker added " .. name)
    ZA.say(ZA.tr("ScanMarkers_Marked", name))
    MK.rename(m)
end

-- A box to type a name into (keyboard).
function MK.rename(m)
    local ok, err = pcall(function()
        -- an empty box: with the default name in it, what you type is added after it (in game 2026-10-20 the
        -- marker became "Maisonmaison principale"); left empty, the default name stays
        local box = ISTextBox:new(0, 0, 280, 180, ZA.tr("ScanMarkers_BoxTitle"), "", nil, function(target, button)
            if button.internal == "OK" then
                local t = button.parent.entry:getText()
                if t and t:match("%S") then
                    m.name = t
                    ZA.say(ZA.tr("ScanMarkers_Named", t))
                end
            end
        end, 0)
        box:initialise()
        box:addToUIManager()
        -- Enter saves the typed name, Escape keeps the default (the box has neither by itself)
        box.entry.onCommandEntered = function() box:onClick(box.yes) end
        box.entry.onOtherKey = function(entry, key)
            if key == Keyboard.KEY_ESCAPE then box:onClick(box.no) end
        end
        box.entry:focus()
    end)
    if not ok then print("[ZA] marker rename error: " .. tostring(err)) end
end

function MK.remove(m)
    local list = MK.all()
    for i, x in ipairs(list) do
        if x == m then table.remove(list, i); break end
    end
    S.builtAt = -1e9
    ZA.say(ZA.tr("ScanMarkers_Removed", m.name))
end

table.insert(S.builders, function(lists)
    for i, m in ipairs(MK.all()) do
        table.insert(lists.markers, {
            cat = "markers", key = "markers|" .. m.name .. "|" .. m.x .. "," .. m.y, baseName = m.name,
            name = function() return m.name end, marker = m,
            x = m.x, y = m.y, z = m.z, walk = "travel", far = true,
        })
    end
    -- the action at the end of the You list
    local p = getPlayer()
    table.insert(lists.you, {
        cat = "you", key = "you|mark", noWhere = true, order = 1000, baseName = ZA.tr("ScanMarkers_MarkSpot"),
        name = ZA.tr("ScanMarkers_MarkSpotHelp"), x = p:getX(), y = p:getY(), z = p:getZ(),
        action = MK.add,
    })
end)
