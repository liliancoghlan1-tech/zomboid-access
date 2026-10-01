Zomboid Access
==============

Play Project Zomboid with the NVDA screen reader: menus, character creation, a scanner for everything around you, walking and travelling by itself, zombie warnings, health and moodles, combat feedback, inventory, looting and markers.

This is an EARLY VERSION (0.5.1). It has been played through character creation, looting houses, fighting and dying many times, but not long-term survival. Building, driving, farming, the crafting screens and the health screen are not made accessible yet. Please send what doesn't work (see Feedback at the end).

Made by Lilian Coghlan. MIT licence.


What you need
-------------
- Project Zomboid, Build 42 (made and tested on 42.21), on Windows.
- NVDA 2024.1 or later.
- The game set to English (the mod's own words are English; the game's words follow the game's language).
- A controller is best (tested with a PlayStation 5 controller; any controller works, see Controller). The keyboard works too.


Installing
----------
1. Start Project Zomboid once, wait for the main menu, and quit. (The game clears its mod list the first time it starts.)
2. Unzip this folder anywhere and run Install.bat. It:
   - copies the mod into your Zomboid\mods folder and turns it on (other mods you use stay on),
   - opens the NVDA add-on: choose Yes, then let NVDA restart.
3. Start Project Zomboid. The main menu speaks.

To remove it: run Uninstall.bat, then remove the add-on in NVDA (NVDA menu, Tools, Add-on store, Installed add-ons, Zomboid Access, Remove).

The game mod writes what to say into a file (Zomboid\Lua\ZomboidAccess_speech.txt), and the NVDA add-on reads it out. Both are needed. The add-on reads only that file and the game's log; it doesn't use the network.


Menus and character creation
----------------------------
Every screen says its name, how to move around it, and what each button does. Each control says its label, its value, its place in the list, and what Cross does. Before you start, a summary of your character is read (name, sex, occupation, traits).

- The main menu starts on Solo. Continue and Load are above it (press up).
- Occupation and traits: L1 and R1 switch between occupations, good traits, bad traits and your traits.
- Loading takes a minute or two. When it's done NVDA says "The world has loaded": press Cross (or click) to begin.
- After dying, the screens for a new character read the same way.


Controller
----------
The game's own controls work as normal (left stick walks, right stick aims, R2 attacks, L2 shoves, Cross interacts, Triangle opens your inventory). The mod adds:

- Share, tap once: the scanner on or off.
- Share, tap twice: quick status (health, injuries, the moodles that are hurting you).
- Share, hold: the game's own Share menu, as before.

While the scanner is on (the left stick still walks; Cross still opens doors and picks things up):
- D-pad up and down: the things in the category, nearest first.
- D-pad left and right: change category.
- Triangle: say it again, with a fresh distance. Hold Triangle: guide mode on or off.
- Square: walk there by itself (Square again stops). Hold Square: use it (see Using things).
- Circle: scanner off. While the scanner is on, the D-pad doesn't open the game's round menus.

Share is the same button as View, Back or Select on other controllers. Button names are spoken the PlayStation way (Cross, Circle, Square, Triangle).

In the inventory: click the right stick (R3) on an item to hear what it is and what it's for.


Keyboard
--------
- Page Down and Page Up: the things in the category.
- Shift with Page Down or Page Up: change category.
- Home: say it again. Shift and Home: zombies and animals, only what your character can see, or everything nearby.
- End: walk there (End again stops). Shift and End: guide mode.
- Delete: use it.
- Insert: quick status. With the inventory open: details of the selected item.
Left Ctrl also works instead of Shift, but left Ctrl is the game's Aim key, so Shift is better.


The scanner
-----------
Everything around you, in categories, nearest first. Each line: name, state, distance, which way to push the stick (up, up-right, right and so on, as the screen is turned), the room if it's another one, and its place in the list. For example: "Door, closed, 4 metres up-right, in the kitchen, 3 of 8".

Things on your floor come first, then things on your side of the walls, then the rest. Distances are straight lines, so something inside a building you're not in says "inside" or "in another building".

The categories, in order:
- You: what you're doing and how far along it is, health, each injury and each moodle with what it means and what to do, what you're carrying, the time, and Mark this spot.
- Markers: places you've marked.
- Zombies: within 30 metres; the ones your character can't see say "out of sight"; "coming for you" if it's chasing you.
- Animals.
- Loot: food and drink, weapons and ammo, medical, tools and materials, clothes and bags, books and papers, everything else. What's inside the containers of the building you're in (every floor), or within 8 metres outdoors, including bodies. Each line says which container it's in.
- Doors (and gates), Windows (open, closed, broken, barricaded), Stairs (up and down).
- Containers, Things on the ground, Water (sinks, toilets, baths, rain barrels, open water).
- Beds and seats, Lights and appliances (switches on or off, TVs, radios, generators).
- Bodies, Vehicles.
- Places: shops, police, clinics, warehouses and so on within 600 metres, and every town on the map.
- Houses: homes within 300 metres, "visited" once you've been inside.


Walking, travelling and guide mode
----------------------------------
- Walk there (Square or End): the game's own pathfinding takes you next to it, round walls and through doors. On arrival your character faces it, so Cross uses it. Stairs work both ways.
- Places, Houses, towns and markers are travelled to in stretches of about 30 metres, with a progress word every 50 metres.
- Walking stops at once if a zombie you weren't told about comes close: "Stopped! Zombie, 6 metres up."
- Guide mode (hold Triangle, or Shift and End) is for walking yourself: the target beeps from where it is, faster as you get closer; when the way to push the stick changes you hear it ("up-left, 6"); walking into something says "Blocked". The beep points in a straight line, so to leave a room, pick a door first. Far places beep from 15 metres ahead in their direction. Only you hear the beep; zombies don't.


Using things (hold Square, or Delete)
-------------------------------------
- A container, or a Loot line: walks you to it and opens it, with the item selected.
- Anything else you can interact with (a door, a sink, a light, a bed, something on the ground): the game's own menu for it opens at once. Choose an option and your character walks over and does it.
- Mark this spot (end of the You list): saves where you're standing. The first marker is Home; a box opens to type a name (Enter saves it, Escape keeps the default).
- A marker: hold Square again within 4 seconds to remove it.


Warnings and status, said by themselves
---------------------------------------
- A zombie starts chasing you: "Zombie chasing you, 8 metres up-right." (the first time, with the fighting controls). Several: how many and the nearest. Very close: "Zombie right next to you, left." All gone: "Nothing chasing you now."
- New injuries at once: "Left forearm: bitten, bleeding!"
- Moodles as they appear, get worse or go away: "Hungry", "Hungry gone".
- Long actions (reading, crafting, bandaging...): named after 2 seconds, then 25, 50 and 75 percent, then Finished or Stopped.


Fighting
--------
Push the right stick at a zombie to aim, R2 swings, L2 shoves it away. After each swing: "Hit", "Hit, down" (knocked over), "Killed" or "Miss". While aiming: "In reach" when a zombie is in front of you and close enough to hit. Aiming and timing stay yours.


Inventory and menus
-------------------
- Triangle opens your inventory. Each item: name, how many, worn or in which hand, weapon condition, rotten or stale food, what's in bottles. Left and right switch between your inventory and what's nearby; L1 and R1 change bag or container. Cross: the item's options. Square: take or put.
- R3 (or Insert) on an item: what kind of thing it is, weight, food values, weapon damage and reach, protection, what a book teaches, and how many crafting recipes use it, with examples.
- Menus (Cross on an item or object): each choice, its place, "more inside, Right opens it", "not available", and its tooltip.
- Round menus (holding a D-pad direction, holding Share): the choices are listed when it opens, and each is read as the right stick points at it; let go of the button to choose.


Not done yet
------------
- Building, driving, farming, fishing, the crafting window, the health screen, the map, options and the mods list.
- Choosing an item in the round menus with the right stick: written but not yet confirmed by a player.
- "Blocked" in guide mode: written but not yet confirmed by a player.
- Only English.


Feedback
--------
Open an issue on the GitHub page (github.com/liliancoghlan1-tech/zomboid-access), saying what you did and what you heard or didn't hear. The game's log (Zomboid\console.txt) helps: the mod's lines in it start with [ZA].
