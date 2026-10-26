-- Zomboid Access: the alarm setting of a watch or an alarm clock (ISAlarmClockDialog), with a controller.
-- In game 2026-10-20 its four arrow buttons were said as "^, button" and "v, button", with no word of the time set.
-- The window: two columns (hours on the left, minutes on the right), "^" above and "v" below each; then the Alarm
-- box, then OK, which keeps the setting. Up and Down go between the rows, Left and Right between the columns.
-- Each button is said by what it does, with the time set now; the time again whenever it changes.

local F = ZA.F

local buttonKeys = {
    HOURSPLUS = "Alarm_HourUp", HOURSMINUS = "Alarm_HourDown", MINPLUS = "Alarm_MinUp", MINMINUS = "Alarm_MinDown",
}

-- "7 h 30, alarm on"
local function setting(w)
    local h = w.hours and w.hours:getText() or "?"
    local m = w.mins and w.mins:getText() or "?"
    local on = w.setAlarm and w.setAlarm:isSelected(1)
    return ZA.tr("Alarm_Time", h, m) .. ", " .. ZA.tr(on and "Alarm_IsOn" or "Alarm_IsOff")
end

F.readers.ISAlarmClockDialog = function(w)
    local ch = F.focusedChild(w)
    local value = setting(w)
    if not ch then return w, value, value end
    local key = ch.internal and buttonKeys[ch.internal]
    if key then return ch, ZA.tr(key) .. ". " .. value, value end
    if ch == w.ok then return ch, ZA.tr("Alarm_Ok"), value end
    local words = F.describe(ch)
    return ch, words, value
end
