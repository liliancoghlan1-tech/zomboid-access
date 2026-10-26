-- Zomboid Access tutorial: what the radio guide says. Lilian's voice notes (2026-10-02): lighthearted, over the
-- radio, can see what you're doing and what's around you, helps you survive blind; humour now and then, not a quip
-- in every line. Each step: say (when it starts), hint (if you're stuck), done (once it's done, optional).
-- The words themselves are in the game's translation files (UI_ZA_TutorialLines_<step>_<say|hint|done>).

ZA.TUL = {
    welcome = {
        say = ZA.tr("TutorialLines_welcome_say"),
    },
    seeing = {
        say = ZA.tr("TutorialLines_seeing_say"),
    },
    scannerOn = {
        say = ZA.tr("TutorialLines_scannerOn_say"),
        hint = ZA.tr("TutorialLines_scannerOn_hint"),
        done = ZA.tr("TutorialLines_scannerOn_done"),
    },
    scannerBrowse = {
        say = ZA.tr("TutorialLines_scannerBrowse_say"),
        hint = ZA.tr("TutorialLines_scannerBrowse_hint"),
        done = ZA.tr("TutorialLines_scannerBrowse_done"),
    },
    walkToDoor = {
        say = ZA.tr("TutorialLines_walkToDoor_say"),
        hint = ZA.tr("TutorialLines_walkToDoor_hint"),
        done = ZA.tr("TutorialLines_walkToDoor_done"),
    },
    openDoor = {
        say = ZA.tr("TutorialLines_openDoor_say"),
        hint = ZA.tr("TutorialLines_openDoor_hint"),
        done = ZA.tr("TutorialLines_openDoor_done"),
    },
    lootFind = {
        say = ZA.tr("TutorialLines_lootFind_say"),
        hint = ZA.tr("TutorialLines_lootFind_hint"),
        done = ZA.tr("TutorialLines_lootFind_done"),
    },
    lootOpen = {
        say = ZA.tr("TutorialLines_lootOpen_say"),
        hint = ZA.tr("TutorialLines_lootOpen_hint"),
        done = ZA.tr("TutorialLines_lootOpen_done"),
    },
    lootTake = {
        say = ZA.tr("TutorialLines_lootTake_say"),
        hint = ZA.tr("TutorialLines_lootTake_hint"),
        done = ZA.tr("TutorialLines_lootTake_done"),
    },
    closeLoot = {
        say = ZA.tr("TutorialLines_closeLoot_say"),
        hint = ZA.tr("TutorialLines_closeLoot_hint"),
        done = ZA.tr("TutorialLines_closeLoot_done"),
    },
    eat = {
        say = ZA.tr("TutorialLines_eat_say"),
        hint = ZA.tr("TutorialLines_eat_hint"),
        done = ZA.tr("TutorialLines_eat_done"),
    },
    drink = {
        say = ZA.tr("TutorialLines_drink_say"),
        hint = ZA.tr("TutorialLines_drink_hint"),
        done = ZA.tr("TutorialLines_drink_done"),
    },
    status = {
        say = ZA.tr("TutorialLines_status_say"),
        hint = ZA.tr("TutorialLines_status_hint"),
        done = ZA.tr("TutorialLines_status_done"),
    },
    youList = {
        say = ZA.tr("TutorialLines_youList_say"),
        hint = ZA.tr("TutorialLines_youList_hint"),
        done = ZA.tr("TutorialLines_youList_done"),
    },

    -- ---- injuries and healing ----
    hurt = {
        say = ZA.tr("TutorialLines_hurt_say"),
        wait = 1,
    },
    healthScreen = {
        say = ZA.tr("TutorialLines_healthScreen_say"),
        hint = ZA.tr("TutorialLines_healthScreen_hint"),
        done = ZA.tr("TutorialLines_healthScreen_done"),
    },
    disinfect = {
        say = ZA.tr("TutorialLines_disinfect_say"),
        hint = ZA.tr("TutorialLines_disinfect_hint"),
        done = ZA.tr("TutorialLines_disinfect_done"),
    },
    bandage = {
        say = ZA.tr("TutorialLines_bandage_say"),
        hint = ZA.tr("TutorialLines_bandage_hint"),
        done = ZA.tr("TutorialLines_bandage_done"),
    },
    closeHealth = {
        say = ZA.tr("TutorialLines_closeHealth_say"),
        hint = ZA.tr("TutorialLines_closeHealth_hint"),
    },

    -- ---- fighting ----
    weapon = {
        say = ZA.tr("TutorialLines_weapon_say"),
        hint = ZA.tr("TutorialLines_weapon_hint"),
        done = ZA.tr("TutorialLines_weapon_done"),
    },
    closeInv = {
        say = ZA.tr("TutorialLines_closeInv_say"),
        hint = ZA.tr("TutorialLines_closeInv_hint"),
    },
    zombieComing = {
        say = ZA.tr("TutorialLines_zombieComing_say"),
        hint = ZA.tr("TutorialLines_zombieComing_hint"),
        done = ZA.tr("TutorialLines_zombieComing_done"),
    },

    -- ---- lock-on and getting away ----
    lockOnSwitch = {
        say = ZA.tr("TutorialLines_lockOnSwitch_say"),
        hint = ZA.tr("TutorialLines_lockOnSwitch_hint"),
        done = ZA.tr("TutorialLines_lockOnSwitch_done"),
    },
    lockOnFight = {
        say = ZA.tr("TutorialLines_lockOnFight_say"),
        hint = ZA.tr("TutorialLines_lockOnFight_hint"),
        done = ZA.tr("TutorialLines_lockOnFight_done"),
    },
    escape = {
        say = ZA.tr("TutorialLines_escape_say"),
        hint = ZA.tr("TutorialLines_escape_hint"),
        done = ZA.tr("TutorialLines_escape_done"),
    },

    -- ---- cooking ----
    cookIntro = {
        say = ZA.tr("TutorialLines_cookIntro_say"),
        hint = ZA.tr("TutorialLines_cookIntro_hint"),
        done = ZA.tr("TutorialLines_cookIntro_done"),
    },
    cookPut = {
        say = ZA.tr("TutorialLines_cookPut_say"),
        hint = ZA.tr("TutorialLines_cookPut_hint"),
        done = ZA.tr("TutorialLines_cookPut_done"),
    },
    cookClose = {
        say = ZA.tr("TutorialLines_cookClose_say"),
        hint = ZA.tr("TutorialLines_cookClose_hint"),
    },
    cookOn = {
        say = ZA.tr("TutorialLines_cookOn_say"),
        hint = ZA.tr("TutorialLines_cookOn_hint"),
        done = ZA.tr("TutorialLines_cookOn_done"),
    },
    cookWait = {
        say = ZA.tr("TutorialLines_cookWait_say"),
        done = ZA.tr("TutorialLines_cookWait_done"),
    },
    cookTake = {
        say = ZA.tr("TutorialLines_cookTake_say"),
        hint = ZA.tr("TutorialLines_cookTake_hint"),
        done = ZA.tr("TutorialLines_cookTake_done"),
    },

    -- ---- foraging ----
    forageOn = {
        say = ZA.tr("TutorialLines_forageOn_say"),
        hint = ZA.tr("TutorialLines_forageOn_hint"),
        done = ZA.tr("TutorialLines_forageOn_done"),
    },
    forageFind = {
        say = ZA.tr("TutorialLines_forageFind_say"),
        hint = ZA.tr("TutorialLines_forageFind_hint"),
        done = ZA.tr("TutorialLines_forageFind_done"),
    },
    foragePick = {
        say = ZA.tr("TutorialLines_foragePick_say"),
        hint = ZA.tr("TutorialLines_foragePick_hint"),
        done = ZA.tr("TutorialLines_foragePick_done"),
    },
    forageOff = {
        say = ZA.tr("TutorialLines_forageOff_say"),
        hint = ZA.tr("TutorialLines_forageOff_hint"),
        done = ZA.tr("TutorialLines_forageOff_done"),
    },

    -- ---- farming ----
    farmIntro = {
        say = ZA.tr("TutorialLines_farmIntro_say"),
        hint = ZA.tr("TutorialLines_farmIntro_hint"),
        done = ZA.tr("TutorialLines_farmIntro_done"),
    },
    dig = {
        say = ZA.tr("TutorialLines_dig_say"),
        hint = ZA.tr("TutorialLines_dig_hint"),
        done = ZA.tr("TutorialLines_dig_done"),
    },
    sow = {
        say = ZA.tr("TutorialLines_sow_say"),
        hint = ZA.tr("TutorialLines_sow_hint"),
        done = ZA.tr("TutorialLines_sow_done"),
    },

    -- ---- fishing ----
    fishBait = {
        say = ZA.tr("TutorialLines_fishBait_say"),
        hint = ZA.tr("TutorialLines_fishBait_hint"),
        done = ZA.tr("TutorialLines_fishBait_done"),
    },
    fishEquip = {
        say = ZA.tr("TutorialLines_fishEquip_say"),
        hint = ZA.tr("TutorialLines_fishEquip_hint"),
        done = ZA.tr("TutorialLines_fishEquip_done"),
    },
    fishGo = {
        say = ZA.tr("TutorialLines_fishGo_say"),
        hint = ZA.tr("TutorialLines_fishGo_hint"),
        done = ZA.tr("TutorialLines_fishGo_done"),
    },
    fishCast = {
        say = ZA.tr("TutorialLines_fishCast_say"),
        hint = ZA.tr("TutorialLines_fishCast_hint"),
        done = ZA.tr("TutorialLines_fishCast_done"),
    },
    fishWait = {
        say = ZA.tr("TutorialLines_fishWait_say"),
        hint = ZA.tr("TutorialLines_fishWait_hint"),
    },
    fishLand = {
        say = ZA.tr("TutorialLines_fishLand_say"),
        hint = ZA.tr("TutorialLines_fishLand_hint"),
        done = ZA.tr("TutorialLines_fishLand_done"),
    },

    -- ---- crafting and building ----
    craft = {
        say = ZA.tr("TutorialLines_craft_say"),
        hint = ZA.tr("TutorialLines_craft_hint"),
        done = ZA.tr("TutorialLines_craft_done"),
    },
    build = {
        say = ZA.tr("TutorialLines_build_say"),
        hint = ZA.tr("TutorialLines_build_hint"),
        done = ZA.tr("TutorialLines_build_done"),
    },

    -- ---- driving ----
    carIntro = {
        say = ZA.tr("TutorialLines_carIntro_say"),
        hint = ZA.tr("TutorialLines_carIntro_hint"),
        done = ZA.tr("TutorialLines_carIntro_done"),
    },
    startEngine = {
        say = ZA.tr("TutorialLines_startEngine_say"),
        hint = ZA.tr("TutorialLines_startEngine_hint"),
        done = ZA.tr("TutorialLines_startEngine_done"),
    },
    drive = {
        say = ZA.tr("TutorialLines_drive_say"),
        hint = ZA.tr("TutorialLines_drive_hint"),
        done = ZA.tr("TutorialLines_drive_done"),
    },
    autodrive = {
        say = ZA.tr("TutorialLines_autodrive_say"),
        hint = ZA.tr("TutorialLines_autodrive_hint"),
        done = ZA.tr("TutorialLines_autodrive_done"),
    },

    pause = {
        say = ZA.tr("TutorialLines_pause_say"),
    },
}
