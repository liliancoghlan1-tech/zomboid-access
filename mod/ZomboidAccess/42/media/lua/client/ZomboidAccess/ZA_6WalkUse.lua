-- Zomboid Access: use the thing selected in the scanner, from where you are (pad: hold Square; keyboard: Delete).
--   A container, or a Loot line: walk to it if needed, then open it in the loot window (with the item selected).
--   Anything else you can interact with (a door, a sink, a bed, a light, something on the ground): the game's
--     own menu for it opens at once; choosing an option there walks you over and does it.
--   A vehicle: the game's own walk to the driver's door and getting in.
--   An action line ("Mark this spot"): does it. A marker: hold Square again within 4 seconds to remove it.

local W, S = ZA.W, ZA.S

local function joypadData() return JoypadState.players and JoypadState.players[1] end

-- Open the loot window on a container (it must be within reach), and select an item by name.
-- On a pad the game remembers the chosen container by its PLACE in the list (backpackChoice), and rebuilds the list
-- whenever you turn or step, so after a walk it used to jump to whatever you were facing. We set the place, ask the
-- game to hold that container (setForceSelectedContainer), and keep putting it back for 2 seconds (W.pendingSelect).
local function findButton(ui, container)
    for i, b in ipairs(ui.backpacks or {}) do
        if b.inventory == container then return b, i end
    end
end

local function choose(ui, b, i, container)
    ui.backpackChoice = i
    ui:selectContainer(b)
    ui:setForceSelectedContainer(container, 2000)
end

function W.openLoot(container, itemName)
    local ui = getPlayerLoot(0)
    ui:setVisible(true)
    pcall(function() ui:refreshBackpacks() end)
    local b, i = findButton(ui, container)
    if not b then
        ZA.say("It's not within reach yet. Get right next to it.")
        return false
    end
    choose(ui, b, i, container)
    if joypadData() then setJoypadFocus(0, ui) end
    W.pendingSelect = { ui = ui, container = container, name = itemName, until_ = getTimestampMs() + 2000 }
    return true
end

-- Every frame for 2 seconds: if the game swapped the container, put ours back; once the list shows it, select the item.
ZA.onTick(function()
    local ps = W.pendingSelect
    if not ps then return end
    if getTimestampMs() > ps.until_ then W.pendingSelect = nil; return end
    local ui = ps.ui
    if ui.inventoryPane.inventory ~= ps.container then
        local b, i = findButton(ui, ps.container)
        if b then choose(ui, b, i, ps.container) end
        return
    end
    if not ps.name or ps.selected then return end
    local pane = ui.inventoryPane
    if not pane.items or #pane.items == 0 then return end
    for i, entry in ipairs(pane.items) do
        local item = (type(entry) == "table" and entry.items) and entry.items[1] or entry
        if item and instanceof(item, "InventoryItem") and item:getName() == ps.name then
            pane.joyselection = i - 1
            ps.selected = true
            break
        end
    end
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
            ZA.say("Remove " .. e.marker.name .. "? Hold {Square} again, or press Delete again, to remove it.")
        end
        return
    end
    -- driving: autodrive to it (ZA_7DriveRoute)
    local veh = p:getVehicle()
    if veh and not e.noWhere and not e.action then
        if veh:isDriver(p) and ZA.RT then ZA.RT.start(e, "auto") else ZA.say("Only the driver can drive there.") end
        return
    end
    if e.noWhere then ZA.say("Nothing to use there."); return end
    -- a foraging find: the game's own forage action (it walks you next to it first)
    if e.cat == "finds" and e.icon and ZA.FG then ZA.FG.pickUp(e); return end
    -- a vehicle: the game walks you to the driver's door, opens it and gets you in (ISVehicleMenu.onEnter)
    if e.obj and instanceof(e.obj, "BaseVehicle") then
        if W.action or W.travel or W.safe then W.stop(true) end
        ZA.say("Getting into the driver's seat.")
        ISVehicleMenu.onEnter(p, e.obj, 0)
        return
    end
    if e.far or e.walk == "mob" then W.go(); return end
    if e.container then
        local x, y, z = S.entryPos(e)
        local d = math.sqrt((x - p:getX()) ^ 2 + (y - p:getY()) ^ 2)
        local item = e.itemName
        local c = e.container
        if d <= 1.9 and math.floor(z) == math.floor(p:getZ()) then
            W.openLoot(c, item)
        else
            -- an open loot window reads out every container you pass on the way: put it away until you arrive
            local jd = joypadData()
            if jd and (jd.focus == getPlayerLoot(0) or jd.focus == getPlayerInventory(0)) then setJoypadFocus(0, nil) end
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
