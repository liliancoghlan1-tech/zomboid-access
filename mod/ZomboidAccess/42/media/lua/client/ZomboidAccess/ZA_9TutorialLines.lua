-- Zomboid Access tutorial: what the radio guide says. Lilian's voice notes (2026-10-02): lighthearted, over the
-- radio, can see what you're doing and what's around you, helps you survive blind; humour now and then, not a quip
-- in every line. DRAFT lines for her to edit. Each step: say (when it starts), hint (if you're stuck), done (once
-- it's done, optional).

ZA.TUL = {
    welcome = {
        say = "Hello? Good, you're up. I'm on the radio. I can see where you are and what's around you, so I'll talk you through things. Let's start easy.",
    },
    seeing = {
        say = "Yes, I can see what you're doing. And what's around you. Don't ask how. Plenty of folks out there are relying on their eyes, and look where it's got them. You'll do fine. Stick with me.",
    },
    scannerOn = {
        say = "First, your scanner. It tells you what's around you, nearest first. Tap {Share} to switch it on.",
        hint = "{Share} is the small button left of the touchpad. One tap.",
        done = "That's it.",
    },
    scannerBrowse = {
        say = "D-pad up and down go through the things in a list. Left and right change list. Find the list called Doors.",
        hint = "Keep pressing D-pad right. Each list says its name first. You want Doors.",
        done = "Doors. Good.",
    },
    walkToDoor = {
        say = "Pick a door with up and down, then press {Square}. You'll walk there by yourself.",
        hint = "{Square} walks you to whatever the scanner has picked. {Square} again stops.",
        done = "Here you are.",
    },
    openDoor = {
        say = "{Cross} opens it. {Cross} is how you use most things right in front of you.",
        hint = "Facing the door already. Just {Cross}.",
        done = "Open. You'd be amazed how many people forget that step.",
    },
    lootFind = {
        say = "There's food in this house. The scanner's Loot lists show what's in the cupboards and drawers. Find Loot: food and drink.",
        hint = "D-pad left or right until you hear Loot: food and drink.",
        done = "There it is.",
    },
    lootOpen = {
        say = "Pick the chips, then hold {Square}. You'll walk over and the cupboard opens with them picked out.",
        hint = "Hold {Square}, don't tap it. Tapping only walks.",
        done = "Cupboard's open.",
    },
    lootTake = {
        say = "{Square} takes them. They go in your inventory.",
        hint = "In the cupboard list, with the chips picked, {Square}.",
        done = "Got them.",
    },
    closeLoot = {
        say = "{Triangle} closes the cupboard and puts you back in the world. Same for your inventory, whenever you're done with it.",
        hint = "{Triangle}. Not {Circle}: in a list, {Circle} only opens or closes a stack of things.",
        done = "Back in the room.",
    },
    eat = {
        say = "You're hungry. {Triangle} opens your inventory. Pick the chips, press {Cross}, and choose Eat.",
        hint = "{Triangle}, find the chips, {Cross}, then Eat. If there's a choice of how much, All is fine.",
        done = "Better. Not exactly a balanced diet, but we're not fussy anymore.",
    },
    drink = {
        say = "Thirsty too. There's a sink in the kitchen. Find it in the Water list, hold {Square} on it, and choose Drink.",
        hint = "Scanner, the Water list, the sink, hold {Square}, then Drink.",
        done = "Tap water. Enjoy it while it lasts.",
    },
    status = {
        say = "Now, how you're doing. Tap {Share} twice, quickly. You'll hear your health and anything bothering you.",
        hint = "Two quick taps of {Share}.",
        done = "That's your quick check. Use it often.",
    },
    youList = {
        say = "For more, the first list in the scanner, called You, explains each feeling and injury and what to do about it.",
        hint = "If your inventory or a cupboard is open, {Triangle} closes it first. Then the scanner, and D-pad left until you hear You.",
        done = "That's everything about you, in one place. That's the basics done. Take a breather if you like.",
    },

    -- ---- injuries and healing ----
    hurt = {
        say = "Ow. You've caught your hand on something. Nothing serious, but it's bleeding. The mod tells you about an injury the moment it happens. I've put some alcohol wipes and a bandage in your pocket.",
        wait = 1,
    },
    healthScreen = {
        say = "Open the Health screen. It's in the You list: find Health screen and press {Square}.",
        hint = "Scanner on, the You list, down to Health screen, {Square}.",
        done = "That's every part of you that hurts, worst first.",
    },
    disinfect = {
        say = "Clean it first. A dirty cut goes bad, and out here that can finish you. Pick the hand, press {Cross}, choose Disinfect, then the alcohol wipes.",
        hint = "Up and down to the hand, {Cross}, Disinfect, Alcohol Wipes.",
        done = "Clean. Stings, I know.",
    },
    bandage = {
        say = "Now bandage it. {Cross} on the hand again, choose Bandage, then the bandage.",
        hint = "Up and down to the hand, {Cross}, Bandage, and the bandage. {Circle} closes the screen after.",
        done = "Bandaged. Keep it clean and it'll heal on its own.",
    },
    closeHealth = {
        say = "{Circle} closes the Health screen.",
        hint = "{Circle}, until you're back in the room.",
    },

    -- ---- fighting ----
    weapon = {
        say = "Next bit's a fight, so here's the good news: in this house, they can't really hurt you. Practise all you like. I've put a baseball bat in your bag. {Triangle} opens your inventory. Pick the bat, press {Cross}, and choose Equip Two Hands.",
        hint = "{Triangle}, the bat, {Cross}, Equip Two Hands. Then {Triangle} to close the inventory.",
        done = "Bat in hand.",
    },
    closeInv = {
        say = "{Triangle} closes the inventory.",
        hint = "{Triangle}, once.",
    },
    zombieComing = {
        say = "One's coming. Hear the low thump? That's it, and it comes from where it is. The closer it gets, the faster the thump. Push the right stick towards the thump to aim, and pull {R2} all the way to swing.",
        hint = "Right stick towards the thump. When you hear a wood-block tick, it's in reach: {R2}. {L2} shoves it back if it's too close.",
        done = "Down and staying down. Nicely done.",
    },

    -- ---- lock-on and getting away ----
    lockOnSwitch = {
        say = "If aiming by ear is a fiddle, there's lock-on. It turns you to face the nearest zombie while you stand still. Switch it on: the You list, Lock-on, {Square}.",
        hint = "Scanner on, the You list, Lock-on, {Square}.",
        done = "Lock-on's on.",
    },
    lockOnFight = {
        say = "Another one. Stand still and let lock-on face it for you. It aims for you too, so when you hear the tick, pull {R2} all the way to swing.",
        hint = "Don't move the left stick: lock-on only turns and aims you while you're standing. Wait for the tick, then {R2} all the way.",
        done = "See? Less fiddly. You can switch it off again in the You list whenever you like.",
    },
    escape = {
        say = "Now, three of them. You don't fight three. Listen for two rising whistles: that's your best way out, away from them. Get through it, and close the door behind you.",
        hint = "The whistles come from the way out. Walk towards them. A door: through it, then {Cross} to close it. The Ways out list in the scanner names them too.",
        done = "They've lost you. That's how you survive a crowd: you don't let it be a crowd.",
    },

    -- ---- cooking ----
    cookIntro = {
        say = "Let's cook. There's a raw steak in your pocket and a stove in the kitchen. Find the stove: it's in the Containers list. Hold {Square} on it, and you'll walk over and look inside.",
        hint = "Scanner on, D-pad left or right to Containers, up and down to the stove, then hold {Square}.",
        done = "You're looking inside the oven.",
    },
    cookPut = {
        say = "Put the steak in. Press Left to switch to your own things, pick the steak, and press {Square}. It moves into the oven.",
        hint = "Left to your inventory, up and down to the steak, {Square}.",
        done = "Steak's in.",
    },
    cookClose = {
        say = "{Triangle} closes the oven, and then {Circle} switches the scanner off.",
        hint = "{Triangle}, then {Circle}.",
    },
    cookOn = {
        say = "Now light it. You're standing at the stove. Press {Square}: that's the menu for what's in front of you. Choose Turn On.",
        hint = "Scanner off, then {Square}, then Turn On. If you don't hear Turn On, the scanner's still on: {Circle} first.",
        done = "It's on.",
    },
    cookWait = {
        say = "Now we wait. You don't have to watch it: the mod tells you when it's half cooked, and when it's done. Take your time.",
        done = "Done. Take it out now, before it burns: hold {Square} on the stove in the Containers list, pick the steak, and {Square}.",
    },
    cookTake = {
        say = "Hold {Square} on the stove, pick the steak, {Square}.",
        hint = "Scanner on, Containers, the stove, hold {Square}. The steak, then {Square}.",
        done = "A proper meal. Turn the stove off when you're done with it: {Square}, Turn Off. Same menu.",
    },

    -- ---- foraging ----
    forageOn = {
        say = "Food grows wild out here too: berries, mushrooms, herbs. You find it by searching. Hold {Share} for the {Share} wheel, point the right stick at Enable search mode, and let go.",
        hint = "Hold {Share}, push the right stick round until you hear Enable search mode, then let go of {Share}.",
        done = "Searching.",
    },
    forageFind = {
        say = "Head outside and walk slowly over the grass. When you sense something nearby, slow right down and turn about. When you notice it, it's said, and it's listed in the scanner under Finds.",
        hint = "Slowly does it. Walk a few steps, stop, turn. Grass and trees are the best places.",
        done = "There's one.",
    },
    foragePick = {
        say = "Find it in the Finds list and hold {Square}. You'll walk over and pick it up.",
        hint = "Scanner on, D-pad to Finds, then hold {Square}.",
        done = "Got it.",
    },
    forageOff = {
        say = "Searching slows you down, so switch it off when you're done: hold {Share}, Disable search mode.",
        hint = "Hold {Share}, right stick to Disable search mode, let go.",
        done = "Good.",
    },

    -- ---- farming ----
    farmIntro = {
        say = "Food you grow yourself doesn't run out. I've put a trowel and some carrot seeds in your bag. Head outside: the scanner's Doors list will get you there.",
        hint = "Doors, an outside door, {Square} to walk there, {Cross} to open it.",
        done = "Fresh air.",
    },
    dig = {
        say = "Stand on soil. Switch the scanner off with {Circle}, then press {Square}: that's the menu for where you're standing. Choose Dig, and a square appears. The D-pad moves it, and it tells you if you can dig there. {Cross} digs.",
        hint = "{Circle} for scanner off, {Square}, Dig. Move the square until you hear can dig, then {Cross}. Grass is fine; roads and floors aren't.",
        done = "One furrow.",
    },
    sow = {
        say = "Now sow it. Stand by the furrow, {Square}, Sow Seed, the carrot seeds, then move the square onto the furrow and {Cross}.",
        hint = "{Square}, Sow Seed, Carrot Seeds. Find the square that says Plowed Land, then {Cross}.",
        done = "Planted. The Crops list will tell you how it's getting on, and when it's thirsty.",
    },

    -- ---- fishing ----
    fishBait = {
        say = "Fishing next. I've put a fishing rod and some worms in your bag. A hook needs bait first. {Triangle} opens your inventory. Pick the rod, press {Cross}, choose Fishing Rod, press Right to go into it, choose Add Bait, then the worm.",
        hint = "{Triangle}, the rod, {Cross}, Fishing Rod, Right, Add Bait, Worm. {Triangle} closes the inventory after.",
        done = "Baited.",
    },
    fishEquip = {
        say = "Now hold the rod. {Cross} on it again and choose Equip Two Hands.",
        hint = "In your inventory, the rod, {Cross}, Equip Two Hands. Then {Triangle} to close the inventory.",
        done = "Rod in hand.",
    },
    fishGo = {
        say = "The river's just past the house. Find Open water in the Water list and walk there with {Square}.",
        hint = "Scanner, the Water list, Open water, {Square}. Stop at the edge.",
        done = "That's the river.",
    },
    fishCast = {
        say = "Push the right stick towards the water: the scanner said which way. When you hear Aiming at water, pull {R2} to cast.",
        hint = "Right stick towards the water and hold it there. Aiming at water, then {R2}.",
        done = "Line's out.",
    },
    fishWait = {
        say = "Now wait. When something bites you'll hear two little plips. Then turn the right stick clockwise, in circles, to reel it in. If I say tight, ease off. If I say slack, reel.",
        hint = "Just wait for the plips. Fish take their time.",
    },
    fishLand = {
        say = "Keep reeling. Clockwise circles.",
        hint = "If it got away, cast again: right stick at the water, {R2}.",
        done = "Landed it. Dinner sorted.",
    },

    -- ---- crafting and building ----
    craft = {
        say = "Now making things. I've put a log and a saw in your bag. Planks first. The You list has Craft: press {Square} on it. Choose Carpentry, then Saw Log, then Make it.",
        hint = "Scanner on, the You list, Craft, {Square}. Then Carpentry, Saw Log, Make it. Each recipe tells you if you can make it, and what's missing if not.",
        done = "Planks. Nearly everything you build starts with those.",
    },
    build = {
        say = "Now build something. There's a hammer and nails in your bag too. The You list has Build: {Square} on it. Choose Outdoors, then Wooden Fence Post, then Place it. A square appears, same as when you dug the furrow. Move it somewhere outside, and {Cross} builds.",
        hint = "The You list, Build, Outdoors, Wooden Fence Post, Place it. Move the square until it says can build here, then {Cross}. {L1} and {R1} turn it.",
        done = "Your first fence post. A fence is just a lot of those. Walls, doors, crates: it all works the same way.",
    },

    -- ---- driving ----
    carIntro = {
        say = "Last one for now. There's a car on the road outside, and its key's in your pocket. Find it in the Vehicles list and hold {Square}: you'll walk to the driver's door, unlock it with the key and get in. Not {Cross}: {Cross} works whatever part of the car you're closest to, like the bonnet.",
        hint = "Scanner on, D-pad to Vehicles, the car, then hold {Square}. If a window opens instead, {Circle} closes it.",
        done = "Driver's seat.",
    },
    startEngine = {
        say = "Hold D-pad up for the car's menu and choose Start Engine.",
        hint = "Scanner off first, with {Circle}. Then hold D-pad up, Start Engine, {Cross}.",
        done = "Engine's running.",
    },
    drive = {
        say = "Gently on {R2}. Listen for the blips: a low one means steer left, a high one means steer right. Silence means you're straight. Drive a little way down the road.",
        hint = "{R2} gently, left stick to steer. Low blip, left. High blip, right. {Circle} brakes.",
        done = "You're driving. Keep it slow and keep listening, and you'll get where you're going.",
    },
    autodrive = {
        say = "Now let the car drive. I've marked a spot further along, called End of the lane. Find it in the Markers list and hold {Square}. The car takes you there. {Circle} brakes if you want it back.",
        hint = "Scanner on, Markers, End of the lane, hold {Square}.",
        done = "Arrived. That's driving.",
    },

    pause = {
        say = "That's everything I've got to teach for now. There's one last thing coming, but it isn't ready yet. Have a wander. I'll be here.",
    },
}
