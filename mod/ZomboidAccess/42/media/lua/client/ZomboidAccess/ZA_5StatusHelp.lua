-- Zomboid Access: what each moodle and injury means, and what to do about it.
-- Read in the scanner's "You" list after the condition's name: the game's own short line
-- (Moodles:getMoodleDescriptionString) first, then a plain explanation written for this mod.
-- The explanations follow the game's survival guide (first aid: rags as bandages, disinfect against infection)
-- and how Build 42 behaves; they say what to do, not exact numbers, since those change between versions.

ZA.ST = ZA.ST or {}
local ST = ZA.ST

ST.moodleHelp = {
    HUNGRY = "You need to eat. Starving slowly hurts your health.",
    THIRST = "You need to drink. Sinks and toilets give water while the water's still on; bottles and drinks work too.",
    TIRED = "You need sleep. Tired makes you slower and worse at fighting. Sleep in a bed if you can, somewhere safe.",
    ENDURANCE = "You're out of breath from running or fighting. Walk instead of running for a while; fighting now is weak and risky.",
    PANIC = "Fear from seeing zombies. It makes your aim and fighting worse. It fades when you're safe; some pills calm it.",
    STRESS = "Stress builds from danger, injuries and cravings. Smokers ease it with cigarettes; rest and safety help.",
    UNHAPPY = "Low mood. Reading magazines or comics, good food and some drinks cheer you up.",
    BORED = "Nothing to do. Reading, the radio or the TV help. Boredom turns into unhappiness.",
    SICK = "You feel ill: bad food, a cold, or zombie infection. Rest, eat and drink. If it came after a bite, it won't go away.",
    BLEEDING = "You're losing blood. Bandage the wound now (a rag works). Bleeding keeps hurting your health until it's covered.",
    INJURED = "How hurt you are overall. Treat each wound; resting lets you heal.",
    PAIN = "Pain from wounds. It slows you down. Painkillers help.",
    WET = "You're wet. Dry off with a towel or change clothes; staying wet and cold can give you a cold.",
    HAS_A_COLD = "You have a cold. Sneezing and coughing make noise that zombies hear. Rest and keep warm.",
    HYPOTHERMIA = "You're too cold. Put on warm clothes, get indoors, find heat.",
    HYPERTHERMIA = "You're too hot. Take off layers and drink something.",
    WINDCHILL = "The wind is chilling you. A jacket helps.",
    HEAVY_LOAD = "You're carrying too much. It slows you and tires you. Drop or store things.",
    DRUNK = "From alcohol. Your fighting and moving are clumsy until it wears off.",
    ANGRY = "Angry. It wears off.",
    CANT_SPRINT = "You can't sprint right now, usually because of an injury.",
    UNCOMFORTABLE = "Something you're wearing or carrying is uncomfortable.",
    NOXIOUS_SMELL = "A horrible smell, usually rotting bodies or food nearby. Moving away helps.",
    FOOD_EATEN = "You're well fed. Good.",
    ZOMBIE = "You're turning into a zombie. The infection can't be cured.",
}

-- Keyed by the game's injury words (getText("IGUI_health_...")), filled in on first use.
local injuryKeys = {
    IGUI_health_Scratched = "A shallow scratch. Bandage it. From a zombie there's a small chance it gives you the zombie infection.",
    IGUI_health_Cut = "A laceration is a deeper cut. Bandage it. From a zombie it's more likely than a scratch to give you the zombie infection.",
    IGUI_health_DeepWound = "A deep wound needs stitches: a suture needle, or a needle and thread, from the health menu. Bandage it until then.",
    IGUI_health_Bitten = "A zombie bite. Bandage it to stop the bleeding. In a normal game a bite gives you the zombie infection, which can't be cured.",
    IGUI_health_Bleeding = "It's bleeding. Bandage it now; a rag works.",
    IGUI_health_Fracture = "A broken bone. It needs a splint (a plank or stick and a rag) from the health menu, then time to heal.",
    IGUI_health_Burned = "A burn. Keep it bandaged and clean; it heals slowly.",
    IGUI_health_LodgedBullet = "A bullet is stuck in it. Take it out with tweezers from the health menu, then bandage it.",
    IGUI_health_LodgedGlassShards = "Glass is stuck in it. Take it out with tweezers from the health menu, then bandage it.",
    IGUI_health_Infected = "The wound itself is infected (dirt, not the zombie infection). Disinfect it, with disinfectant or strong alcohol, and use clean bandages.",
    IGUI_health_Bandaged = "It's bandaged. Change the bandage when it gets dirty.",
}
ST.injuryHelp = nil

function ST.injuryExplain(word)
    if not ST.injuryHelp then
        ST.injuryHelp = {}
        for k, v in pairs(injuryKeys) do ST.injuryHelp[getText(k)] = v end
    end
    return ST.injuryHelp[word]
end
