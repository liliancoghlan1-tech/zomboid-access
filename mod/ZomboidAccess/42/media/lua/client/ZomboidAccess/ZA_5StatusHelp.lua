-- Zomboid Access: what each moodle and injury means, and what to do about it.
-- Read in the scanner's "You" list after the condition's name: the game's own short line
-- (Moodles:getMoodleDescriptionString) first, then a plain explanation written for this mod.
-- The explanations follow the game's survival guide (first aid: rags as bandages, disinfect against infection)
-- and how Build 42 behaves; they say what to do, not exact numbers, since those change between versions.

ZA.ST = ZA.ST or {}
local ST = ZA.ST

ST.moodleHelp = {
    HUNGRY = ZA.tr("StatusHelp_Moodle_Hungry"),
    THIRST = ZA.tr("StatusHelp_Moodle_Thirst"),
    TIRED = ZA.tr("StatusHelp_Moodle_Tired"),
    ENDURANCE = ZA.tr("StatusHelp_Moodle_Endurance"),
    PANIC = ZA.tr("StatusHelp_Moodle_Panic"),
    STRESS = ZA.tr("StatusHelp_Moodle_Stress"),
    UNHAPPY = ZA.tr("StatusHelp_Moodle_Unhappy"),
    BORED = ZA.tr("StatusHelp_Moodle_Bored"),
    SICK = ZA.tr("StatusHelp_Moodle_Sick"),
    BLEEDING = ZA.tr("StatusHelp_Moodle_Bleeding"),
    INJURED = ZA.tr("StatusHelp_Moodle_Injured"),
    PAIN = ZA.tr("StatusHelp_Moodle_Pain"),
    WET = ZA.tr("StatusHelp_Moodle_Wet"),
    HAS_A_COLD = ZA.tr("StatusHelp_Moodle_HasACold"),
    HYPOTHERMIA = ZA.tr("StatusHelp_Moodle_Hypothermia"),
    HYPERTHERMIA = ZA.tr("StatusHelp_Moodle_Hyperthermia"),
    WINDCHILL = ZA.tr("StatusHelp_Moodle_Windchill"),
    HEAVY_LOAD = ZA.tr("StatusHelp_Moodle_HeavyLoad"),
    DRUNK = ZA.tr("StatusHelp_Moodle_Drunk"),
    ANGRY = ZA.tr("StatusHelp_Moodle_Angry"),
    CANT_SPRINT = ZA.tr("StatusHelp_Moodle_CantSprint"),
    UNCOMFORTABLE = ZA.tr("StatusHelp_Moodle_Uncomfortable"),
    NOXIOUS_SMELL = ZA.tr("StatusHelp_Moodle_NoxiousSmell"),
    FOOD_EATEN = ZA.tr("StatusHelp_Moodle_FoodEaten"),
    ZOMBIE = ZA.tr("StatusHelp_Moodle_Zombie"),
}

-- Keyed by the game's injury words (getText("IGUI_health_...")), filled in on first use.
local injuryKeys = {
    IGUI_health_Scratched = ZA.tr("StatusHelp_Injury_Scratched"),
    IGUI_health_Cut = ZA.tr("StatusHelp_Injury_Cut"),
    IGUI_health_DeepWound = ZA.tr("StatusHelp_Injury_DeepWound"),
    IGUI_health_Bitten = ZA.tr("StatusHelp_Injury_Bitten"),
    IGUI_health_Bleeding = ZA.tr("StatusHelp_Injury_Bleeding"),
    IGUI_health_Fracture = ZA.tr("StatusHelp_Injury_Fracture"),
    IGUI_health_Burned = ZA.tr("StatusHelp_Injury_Burned"),
    IGUI_health_LodgedBullet = ZA.tr("StatusHelp_Injury_LodgedBullet"),
    IGUI_health_LodgedGlassShards = ZA.tr("StatusHelp_Injury_LodgedGlassShards"),
    IGUI_health_Infected = ZA.tr("StatusHelp_Injury_Infected"),
    IGUI_health_Bandaged = ZA.tr("StatusHelp_Injury_Bandaged"),
}
ST.injuryHelp = nil

function ST.injuryExplain(word)
    if not ST.injuryHelp then
        ST.injuryHelp = {}
        for k, v in pairs(injuryKeys) do ST.injuryHelp[getText(k)] = v end
    end
    return ST.injuryHelp[word]
end
