Zomboid Access
==============

Play Project Zomboid with a screen reader (NVDA, JAWS and others): menus, character creation, a scanner for everything around you, walking by itself (round zombies when they're near), zombie warnings and escape help, health and moodles, fighting with optional lock-on, inventory and looting, cooking, farming, foraging, fishing, crafting and building, driving with a steering tone or autodrive, and an interactive tutorial with a guide on the radio.

This is an EARLY VERSION (0.9.3). It has been played through character creation, the tutorial, looting houses, fighting and dying many times, but not long-term survival. Please send what doesn't work (see Feedback at the end).

New here? Start with the tutorial: New game, Challenges, "Zomboid Access Tutorial" (see Tutorial below).

Made by Lilian Coghlan. MIT licence. Street names and lines come from the game's own map data (Build 42.21).


What you need
-------------
- Project Zomboid, Build 42 (made and tested on 42.21), on Windows.
- A screen reader: NVDA, JAWS, ZDSR and others work. With none running, it speaks with the Windows voices.
- Steam (the installer sets the game's Steam launch option; see Installing).
- The game set to English (the mod's own words are English; the game's words follow the game's language).
- A controller (tested with a PlayStation 5 controller; any controller works, see Controller). The menus and character creation are read only through a controller. In the world, the keyboard keys below work too.


Installing, updating and removing
---------------------------------
1. Start Project Zomboid once, wait about a minute, then close it with Alt+F4. (The game clears its mod list the first time it starts.)
   The very first time, the game stops on a Terms of Service screen before the main menu. Nothing reads it until the mod is installed, so just close the game there with Alt+F4.
2. Exit Steam (Steam menu, Exit). Unzip this folder anywhere and run ZomboidAccessSetup.exe. It opens on a Status box that says what you have and what the newest version is, with that version's release notes in the box after it, then the buttons Install (or Update), Reinstall, Uninstall and Close. Install:
   - checks GitHub for the newest version (if it can't, it installs the copy in this folder),
   - copies the mod into your Zomboid\mods folder and turns it on (other mods you use stay on),
   - copies the speech bridge to %LOCALAPPDATA%\ZomboidAccess, and sets Project Zomboid's launch option in Steam so the bridge starts with the game and closes with it (any launch options you had, like -debug, are kept after it),
   - keeps a copy of itself there, with a Start menu entry, "Zomboid Access Setup", for updates,
   - says which screen reader it will speak through, as a test.
   It finds the game in any of your Steam libraries, on any drive; the mod itself goes in your Zomboid folder (or the one your -cachedir= launch option names).
   If Steam was running, it tells you to exit Steam and run it again, or how to type the launch option yourself.
   Upgrading from 0.9.2 or earlier: remove the old NVDA add-on (NVDA menu, Tools, Add-on store, Installed add-ons, Zomboid Access, Remove), or everything is said twice. Setup reminds you.
3. Start Project Zomboid. If the Terms of Service screen comes up, it is read out: Up and Down move between its buttons, Enter presses one (it starts on Accept). With a controller, press Cross first, then the D-pad and Cross.
   Then the main menu says "Press Cross on your controller to start": press Cross and it reads the menu. If it says "No controller found", connect one and press Cross.

Updating: run "Zomboid Access Setup" from the Start menu. When there is a newer version it says so, shows its release notes, and asks: Update replaces only the files that changed and removes ones the new version no longer has. Your voice settings, your other options and your saves are kept.
Reinstall copies every file again, if something seems broken. Uninstall removes the mod, the speech bridge (with its voice settings) and its launch option; your saves are kept.

The game mod writes what to say into a file (Zomboid\Lua\ZomboidAccess_speech.txt), and the speech bridge reads it out through your screen reader, using Prism (https://github.com/ethindp/prism). Both are needed. The file stays small (it starts again past 256 KB) and the bridge deletes it when the game closes. The bridge reads only that file and the game's log; it doesn't use the network. While the game starts, while a world loads, and on the "press to start" screen, the game runs no mod code at all, so the bridge watches the game's log and says what's happening itself.
Not using Steam? Run the bridge with the game after it, for example: "%LOCALAPPDATA%\ZomboidAccess\ZomboidAccessBridge.exe" "C:\Games\ProjectZomboid\ProjectZomboid64.exe". It starts the game and closes with it.


Tutorial
--------
New game, then Challenges (the last game mode), then press Right to "Zomboid Access Tutorial", then Cross, and make a character. It's its own world: your saves are never touched.
A quiet house by the river with no zombies until a lesson brings one, and a guide on the radio (a short radio crackle comes before each thing they say) who teaches the game and this mod one thing at a time: the scanner and doors, looting, eating and drinking, how you're doing, injuries and healing, fighting, lock-on and getting away, cooking, foraging, farming, fishing, crafting and building, and driving.
- Each step waits until you've done it. Stuck for 40 seconds, you get a hint.
- In the fighting lessons the zombies can't really hurt you: you're healed at once.
- The You list starts with "Radio: say that again" and "Radio: choose a lesson" (to repeat one, or jump to another).
- Where you are is kept in the save: quit and come back, and the guide picks up there.


Menus and character creation
----------------------------
Every screen says its name, how to move around it, and what each button does. Each control says its label, its value, its place in the list, and what Cross does. Before you start, a summary of your character is read (name, sex, occupation, traits).

- The main menu starts on Solo. Continue and Load are above it (press up).
- Occupation and traits: L1 and R1 switch between occupations, good traits, bad traits and your traits.
- Starting the game says "Starting Project Zomboid", and "Still starting" every 20 seconds until the main menu speaks.
- Loading a world takes a minute or two: "Still loading the world" every 20 seconds. When it's done you hear "The world has loaded": press Cross (or click) to begin. Until you do, it reminds you every 20 seconds.
- Quitting a game says "Leaving the world and saving" (and "Still saving") until the main menu speaks.
- The game's own Tutorial on the main menu turns all mods off, so it would be silent: choosing it starts the Zomboid Access Tutorial instead.
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

Share is the game's Back button: on an Xbox controller it's View (the small button with two squares), on a Switch Pro controller Minus, on others Select or Back. The PlayStation touchpad isn't used: the game doesn't see it. Button names follow the game's own setting, Options, Controller tab, Button style: Xbox (A, B, X, Y, LB, RB, LT, RT, View, Menu), PlayStation (Cross, Circle, Square, Triangle, L1, R1, L2, R2, Share, Options) or Steam Deck. This README uses the PlayStation names.
To swing a weapon the game needs the right trigger almost all the way down (about 96 percent); a lighter pull only aims.

In the inventory: click the right stick (R3) on an item to hear what it is and what it's for.


Keyboard
--------
- Page Down and Page Up: the things in the category.
- Shift with Page Down or Page Up: change category.
- Home: say it again. Shift and Home: zombies and animals, only what your character can see, or everything nearby.
- End: walk there (End again stops). Shift and End: guide mode.
- Delete: use it.
- Insert: quick status. With the inventory open: details of the selected item.
- Shift and Insert: where you are.
Left Ctrl also works instead of Shift, but left Ctrl is the game's Aim key, so Shift is better.


The scanner
-----------
Everything around you, in categories, nearest first. Each line: name, state, distance, which way to push the stick (up, up-right, right and so on, as the screen is turned), the room if it's another one, and its place in the list. For example: "Door, closed, 4 metres up-right, in the kitchen, 3 of 8".

Things on your floor come first, then things on your side of the walls, then the rest. Distances are straight lines, so something inside a building you're not in says "inside" or "in another building".

The categories, in order:
- You: where you are, what you're doing and how far along it is, health, each injury and each moodle with what it means and what to do, what you're carrying, the time, then Health screen, Skills, Zombie sounds, Lock-on, Escape help and Driving help (each on or off) and Mark this spot (Square does each).
- Markers: places you've marked.
- Zombies: within 30 metres; the ones your character can't see say "out of sight"; "coming for you" if it's chasing you.
- Ways out: doors, windows, empty window frames, fences and vehicles within 12 metres that can break a chase, best first, leaving out any that are towards a zombie. Each says what to do ("Door, closed: go through, then Cross closes it behind you"; windows and fences: Circle climbs).
- Animals.
- Loot: food and drink, weapons and ammo, medical, tools and materials, clothes and bags, books and papers, everything else. What's inside the containers of the building you're in (every floor), or within 8 metres outdoors, including bodies. Each line says which container it's in.
- Doors (and gates), Windows (open, closed, broken, barricaded), Stairs (up and down).
- Containers, Things on the ground, Water (sinks, toilets, baths, rain barrels, open water).
- Crops: furrows and plants within 40 metres: the plant and its stage ("Seedling Carrots", "Ready to harvest Tomatoes", "Dead Cabbages"), its water ("water: thirsty"), and pests or mildew once your Farming is level 3, as the game shows them.
- Beds and seats, Lights and appliances (switches on or off, TVs, radios, generators).
- Bodies, Vehicles.
- Places: shops, police, clinics, warehouses and so on within 600 metres, and every town on the map.
- Houses: homes within 300 metres, "visited" once you've been inside.


Walking, travelling and guide mode
----------------------------------
- Walk there (Square or End): the game's own pathfinding takes you next to it, round walls and through doors. On arrival your character faces it, so Cross uses it. Stairs work both ways.
- Places, Houses, towns and markers are travelled to in stretches of about 30 metres, with a progress word every 50 metres.
- Walking stops at once if a zombie you weren't told about comes close: "Stopped! Zombie, 6 metres up."
- With zombies within 12 metres, walking goes round them: "Walking round the zombies to...". The route is planned square by square to keep away from them, walked in short stretches and planned again as they move. The last steps are the usual walk.
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


Where you are, and the day
--------------------------
Shift and Insert, or the first line of the You list: the town, the street ("on Main St", or "near Chenault St, 16 metres up-right"), the building and room ("in a house, in the living room"), the floor, and your nearest marker. Street names come from the game's own map.
Said by itself: "It'll be dark in about an hour", "Night has fallen", "Dawn", "Asleep" and "You woke up. It's 7:15 AM", and the day the power or the water goes off for good.


Health screen and skills
------------------------
From the You list (Health screen, or Skills, then Square), or the game's Share menu (Player Info). L1 and R1 move between the tabs.
- Health: up and down go through each hurt body part, with its injuries and what each one means. Cross shows what you can do for it (bandage, disinfect, stitch, splint, take out glass), with the things you carry. Your progress is then read out ("Bandaging, 75 percent, Finished bandaging").
- Skills: each skill, its level, and how far you are to the next level.


Sounds
------
The mod's own sounds, which only you hear (zombies don't):
- A low double thump from each of the 3 nearest zombies that are chasing you within 20 metres, or any within 10 metres. It comes from where the zombie is, and gets faster as it gets closer.
- A wood-block tick while a zombie in front of you is close enough to hit (or about to be).
- A soft bell from the place you picked in guide mode.
- Two quick rising whistles from the best way out while something chases you (Escape help).
- Driving: a low blip means steer left, a high blip steer right; faster the more you need to turn.
- Fishing: two little water plips when a fish bites.
- The tutorial: a short radio crackle before the guide speaks. If the radio has a voice of its own (see Voices), it talks alongside everything else. If it shares your screen reader's voice, the guide waits until other speech is finished, and other speech waits for the guide, so nothing cuts it off (except a zombie warning outside the tutorial).
Switch the zombie sounds off or on in the You list (Zombie sounds, then Square); Escape help and Driving help have their own switches there.


Voices
------
Options, Accessibility tab, at the end under "Zomboid Access":
- Say positions in lists, like 2 of 25: on at first. Turned off, menus, lists, tabs and the scanner leave out the "2 of 25". It is kept in Zomboid\Lua\ZomboidAccess_options.txt.
- Zomboid Access voice: everything the mod says. Radio voice: the guide on the radio in the tutorial.
- Each one is your screen reader (the default), or any SAPI or OneCore voice on your computer. Each SAPI or OneCore voice has its own speed and volume (0 to 100); the screen reader keeps its own settings.
- A change is heard at once: the Zomboid Access voice says the new setting in the new voice, and the radio says a sample.
- Giving the radio a voice of its own lets it talk while you move around menus and the scanner, without anything waiting for it.
The choices are kept by the speech bridge (voices.json next to it), so they also cover what is said while the game starts and loads.


Fighting
--------
Push the right stick at a zombie to aim, R2 swings, L2 shoves it away. After each swing: "Hit", "Hit, down" (knocked over), "Killed" or "Miss". "In reach" (and the wood-block tick) when a zombie in front of you is close enough to hit, or will be by the time your swing lands: it allows for how fast the zombie is coming, so you have time to pull R2. It works whether you aim first or pull R2 straight through. Aiming and timing stay yours.


Driving
-------
You drive; the mod tells you where the road goes. (A mod can't steer or press the pedals: the game reads the controller itself.)
- Getting in: the scanner's Vehicles category, then hold Square: you walk to the driver's door and get in. Or Cross at a car door. You hear the car's name, the engine, the key ("key in the ignition", "you have its key", "hotwired", "no key: it needs hotwiring") and the fuel.
- The car's own menu: hold D-pad up (start the engine, hotwire, headlights, horn, windows, lock the doors, mechanics, get out). R2 accelerates, L2 reverses, Circle brakes, the left stick steers, Cross gets out.
- Cruise control (the game's own): hold Square and press D-pad up or down to set the speed in steps of 5, tap Square to switch it on or off. The mod says "Cruise control 40 kilometres an hour" and "Cruise control off". With it on, you only steer.
- The steering tone: while you drive forward, the mod looks down the road (further the faster you go) and finds its middle. A low blip means steer left, a high blip steer right; the more you need to turn, the faster they come. Silence means you're on line. Left and right are the car's, whichever way it faces.
- Said by itself: "Engine running", "Engine off", what's in your path ("Car ahead, 20 metres", "Zombie ahead", "Something on the road", and trees or walls when they're close), "Junction ahead", "No road ahead", "Off the road", "Road again", "Crash!".
- Quick status (Insert, or Share twice) in a vehicle starts with the speed, cruise control, fuel, engine and headlights.
- Switch the tone and the driving words off or on: the You list, Driving help, then Square.

Driving to a place
- In the driver's seat, pick any place in the scanner: Places, Houses, a town, a marker, or anything nearby.
- Square (or End): route guidance. The mod plans a way along the roads; the steering tone follows the route instead of just the road; you hear "Turn left in 40 metres", "Turn left now", how far to go every 200 metres, "The route is behind you: turn around", and "Arrived". Square again stops it.
- Hold Square (or Delete): autodrive. The car drives itself along the same route: cruise control does the speed (20 km/h, slower for sharp turns and near zombies), the mod steers. Start the engine first. Brake (Circle) at any time and the car is yours again. It stops by itself for a car or something solid on the road ahead, and at the end.
- Routes keep to roads, and are planned as far as the game has loaded round you (about 70 metres each way), then planned again as you go, so far places are fine.


Escape help
-----------
While a zombie is chasing you, two quick rising whistles play from the best way out near you: a door to go through and close behind you, a window or empty frame to climb through, a fence to climb or hop, or a vehicle. They come faster as you get closer. Ways out that a chasing zombie is nearer to than you, or that are towards a zombie, are left out. When a chase starts you also hear where it is ("Way out: Door, closed: go through, then Cross closes it behind you, 5 metres up-left").
To walk there round the zombies: the scanner's Ways out category, then Square. To switch the help off or on: the You list, Escape help, then Square.


Lock-on
-------
Off until you switch it on (the You list, Lock-on, then Square; the choice is kept in your save). While it's on, your character turns to face the nearest zombie within about 3.5 metres (one that's chasing you first) and stays on it until it dies or gets away: "Locked on: Zombie, 2 metres right". It doesn't turn you while you walk, and pushing the right stick to aim somewhere else wins over it. While it faces a zombie and you stand still, it also aims at it for you, so pulling R2 all the way swings straight away; L2 shoves. That also makes it work with controllers whose triggers are only on or off (8BitDo and others), which can't be pulled halfway to aim. Walking, or aiming elsewhere with the right stick, lets go at once.


Choosing a square (digging, sowing, building)
---------------------------------------------
Some actions ask you to choose a square: digging a furrow, sowing seeds, and placing things. The mod says what it's for and the buttons, then after each move where the square is from you ("2 squares up-right"), whether you can do it there ("can dig furrow here", "can't sow here"), the ground (soil, gravel, grass, road), what's on it (a plant and how it's doing, a tree, a wall) and the game's own note ("Sow: Carrot Seeds, 5", "Not a furrow"). The D-pad moves the square one step: Up goes up-right, Right goes down-right, Down goes down-left, Left goes up-left. Cross does it, Circle cancels.


Farming
-------
- Dig a furrow: with the scanner off, press Square: the game's menu for where you stand and what's in front of you. Choose Dig (or Dig with hands), then choose the square. You need soil: the square says "soil" when it's diggable. The square stays chosen after digging, so you can dig a row; Circle finishes.
- Sow: stand by a furrow, press Square, choose Sow Seed and the seeds, then choose the furrow.
- Look after it: the Crops category finds your plants; hold Square on one for the game's menu (Info, Water, Fertilize, Harvest, Treat Problem, Remove).


Cooking and other windows
-------------------------
The game's small windows say their name, what they show and their buttons:
- Oven and microwave: on or off, power, how warm it is, how many things are inside, and each dial ("Temperature: 350 degrees Fahrenheit", "Timer: 20 minutes", "Temperature: power 3 of 5"). Up and Down turn a dial, Left and Right move between dials, Cross turns it on or off from anywhere in the window. "Turned on" and "Turned off" are said.
- Cooking by ear: food in anything hot near you (stove, oven, microwave, barbecue, campfire) is followed and said as it goes: "Steak cooking, in the chrome oven", "Steak, half cooked", "Steak is cooked: take it out before it burns", "Steak is about to burn!", "Steak has burnt". A steak takes about two minutes on a stove at normal speed.
- Barbecue, campfire and generator: their information (fuel, condition, lit or not), said again when it changes.
- Vehicle mechanics (Cross near a car's bonnet): the overall condition, then each part with its condition, fuel or charge, or "not installed". Left: engine and insides; Right: doors, body and lights. Cross on a part: what you can do with it.
- Seats (Enter Vehicle in a car's menu): each seat, "the driver's seat", empty or taken. Left and Right across, Up and Down between rows, Cross sits, Square gets out by that door.
- Other windows (alarm clock, radio, animal and so on) say their name and read their buttons, boxes and dials. More of them will get their own reading.


Foraging
--------
Hold Share for the Share wheel and choose Enable search mode (the same wheel switches it off, and offers Pick up for the nearest find). Then walk slowly over grass and among trees.
- "Search mode on" and "off".
- "You sense something nearby" when your character starts spotting something (what a sighted player sees as the eye icon brightening; it gives no direction).
- "Noticed: Blackberries, 4 metres up-left" when they spot it. Things you can't make out yet are "something you can't make out yet" until you're closer or more skilled, as in the game.
- The scanner's Finds category lists what you've noticed; hold Square on one to walk over and pick it up.
At night and when you're hurt you notice far less, as in the game.


Fishing
-------
Bait the rod first: in your inventory, the rod, Cross, Fishing Rod, Right, Add Bait, then the bait. Hold it in both hands (Cross on it, Equip Two Hands). Find water with the scanner (Water, Open water), go to the edge.
- Push the right stick towards the water: "Aiming at water. R2 casts."
- R2 casts: "Line out, 8 metres. Wait for a bite."
- A bite: two little water plips, then "Bite! Turn the right stick clockwise in circles to reel."
- While reeling: "Tight! Ease off" (stop turning for a moment) or "Slack, keep reeling", and the distance every 2 metres.
- "Landed it", "It got away", "The line broke". Circle stops fishing.


Crafting and building
---------------------
The game's Crafting and Building windows are pictures; the mod gives you menus instead. They open from the You list (Craft, Build), and also in place of the game's windows when you choose Crafting or Building from the Share wheel.
- First the categories, each with how many recipes it has.
- Then that category's recipes: the ones you can make now first ("Saw Log, you can make it"), then the others with what's missing ("Wooden Crate, missing Nails").
- Then one recipe: Make it (or Make several), and each thing it needs and each tool, with how many you have ("4 Nails, you have 10", "Tool: Hammer, kept, you have 1"), and about how long it takes. Progress is read out as for any action.
- Building: Place it gives the square cursor (see Choosing a square): "Choose a square to build a Wooden Fence Post", each square says "can build here" or not; L1 and R1 turn it, Cross builds, Circle cancels.

Sandbox settings and typing
---------------------------
- The sandbox settings screen (Custom Sandbox, and the settings of a new game) starts on the list of pages. Up and Down choose a page, Right goes into its settings, Left comes back. Each setting says its section, name, value, what Cross does, its place, and the game's own explanation. Circle from the pages reaches Start and Back; Down from there reaches the presets and the Advanced switch.
- Cross on a text or number box opens the game's on-screen keyboard: each key is said, and what you've typed after each key. Square deletes, Triangle types a space, Circle cancels, Accept (the right end of the third row) finishes.


Inventory and menus
-------------------
- Triangle opens your inventory. Each item: name, how many, worn or in which hand, weapon condition, rotten or stale food, what's in bottles. Left and right switch between your inventory and what's nearby; L1 and R1 change bag or container. Cross: the item's options. Square: take or put.
- R3 (or Insert) on an item: what kind of thing it is, weight, food values, weapon damage and reach, protection, what a book teaches, and how many crafting recipes use it, with examples.
- Menus (Cross on an item or object): each choice, its place, "more inside, Right opens it", "not available", and its tooltip.
- Round menus (holding a D-pad direction, holding Share): the choices are listed when it opens, and each is read as the right stick points at it; let go of the button to choose.
- Dialogs (yes or no questions, warnings) read what they're asking first.


Main menu screens
-----------------
- Load: each save with its game mode, when it was started, your character's name, alive or dead, and when you last played.
- Options: each tab says its name (L1 and R1 change tab); every setting reads with its value, volume sliders as a number out of 10.
- Mods: hold R1 and press Up to reach the list of mods; each says on or off, and Cross switches it.


Not done yet, and not right yet
-------------------------------
- Driving is the weakest part. The steering tone and autodrive work in tests, but driving by ear is still hard: the blips can feel late or busy, autodrive is slow (20 km/h) on purpose and can scrape a sharp bend, and dirt roads may not count as road. It works, it's just not the best yet. Feedback on driving is especially welcome.
- Fighting with lock-on: tested in software, not yet confirmed by many players with a real R2.
- Foraging and fishing: new in this version and lightly tested.
- The radio and TV, and the details on the animal windows, read their controls but not yet everything they show.
- The map is a picture; Places and Where you are cover what it shows.
- Only English.


Feedback
--------
Open an issue on the GitHub page (github.com/liliancoghlan1-tech/zomboid-access), saying what you did and what you heard or didn't hear. The game's log (Zomboid\console.txt) helps: the mod's lines in it start with [ZA].
