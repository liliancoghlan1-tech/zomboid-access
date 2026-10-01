-- Zomboid Access: use the thing selected in the scanner, from where you are (pad: hold Square; keyboard: Delete).
--   A container, or a Loot line: walk to it if needed, then open it in the loot window (with the item selected).
--   Anything else you can interact with (a door, a sink, a bed, a light, something on the ground): the game's
--     own menu for it opens at once; choosing an option there walks you over and does it.
--   An action line ("Mark this spot"): does it. A marker: hold Square again within 4 seconds to remove it.

local W, S = ZA.W, ZA.S

local function joypadData() return JoypadState.players and JoypadState.players[1] end

-- Open the loot window on a container (it must be within reach), and select an item by name.
function W.openLoot(container, itemName)
    local ui = getPlayerLoot(0)
    ui:setVisible(true)
    pcall(function() ui:refreshBackpacks() end)
    local found
    for _, b in ipairs(ui.backpacks or {}) do
        if b.inventory == container then found = b; break end
    end
    if not found then
        ZA.say("It's not within reach yet. Get right next to it.")
        return false
    end
    ui:selectContainer(found)
    local jd = joypadData()
    if jd then
        jd.focus = ui
        updateJoypadFocus(jd)
    end
    if itemName then W.pendingSelect = { ui = ui, name = itemName, until_ = getTimestampMs() + 1000 } end
    return true
end

-- The list fills a frame later: then move the selection to the item.
ZA.onTick(function()
    local ps = W.pendingSelect
    if not ps then return end
    if getTimestampMs() > ps.until_ then W.pendingSelect = nil; return end
    local pane = ps.ui.inventoryPane
    if not pane or not pane.items or #pane.items == 0 then return end
    for i, entry in ipairs(pane.items) do
        local item = (type(entry) == "table" and entry.items) and entry.items[1] or entry
        if item and instanceof(item, "InventoryItem") and item:getName() == ps.name then
            pane.joyselection = i - 1
            break
        end
    end
    W.pendingSelect = nil
end)

-- The game's own menu for one object, as the pad's interact-options button opens it (ISButtonPrompt:interact).
function W.objectMenu(obj)
    local p = getPlayer()
    local s = p:getCurrentSquare()
    local x = isoToScreenX(0, s:getX(), s:getY(), s:getZ())
    local y = isoToScreenY(0, s:getX(), s:getY(), s:getZ())
    local menu = ISContextManager.getInstance().createWorldMenu(0, nil, { obj }, x, y)
    if not menu then ZA.say("Nothing to do with it."); return end
    menu.origin = nil
    if not menu:getIsVisible() then menu:setVisible(true) end
    if menu.numOptions > 1 then
        local jd = joypadData()
        if jd then setJoypadFocus(0, menu) end
        menu.mouseOver = 1
    else
        ZA.say("Nothing to do with it.")
    end
end

function W.use()
    local p = getPlayer()
    if getGameSpeed() == 0 then ZA.say("The game is paused."); return end
    local e = S.current()
    if not e then ZA.say("Nothing selected."); return end
    if e.action then e.action(); return end
    if not S.alive(e) then ZA.say(S.entryName(e) .. " is gone."); return end
    if e.marker then
        local t = getTimestampMs()
        if W.removeAsk == e.marker and t - (W.removeAskAt or 0) < 4000 then
            W.removeAsk = nil
            ZA.MK.remove(e.marker)
        else
            W.removeAsk, W.removeAskAt = e.marker, t
            ZA.say("Remove " .. e.marker.name .. "? Hold Square again, or press Delete again, to remove it.")
        end
        return
    end
    if e.noWhere then ZA.say("Nothing to use there."); return end
    if e.far or e.walk == "mob" then W.go(); return end
    if e.container then
        local x, y, z = S.entryPos(e)
        local d = math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2)
        local item = e.itemName
        local c = e.container
        if d <= 1.9 and math.floor(z) == math.floor(p:getZ()) then
            W.openLoot(c, item)
        else
            W.afterArrive = function() W.openLoot(c, item) end
            W.go()
            if not W.action then W.afterArrive = nil end
        end
        return
    end
    if e.obj then W.objectMenu(e.obj); return end
    W.go()
end

function W.onUseKey(key)
    if key ~= Keyboard.KEY_DELETE or not S.inWorld() then return end
    local ok, err = pcall(W.use)
    if not ok then print("[ZA] use error: " .. tostring(err)) end
end
if not W.useHooked then
    W.useHooked = true
    Events.OnKeyPressed.Add(function(key) W.onUseKey(key) end)
end
