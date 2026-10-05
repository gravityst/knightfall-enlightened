# Knightfall Enlightened

An open-world, first-person medieval survival game for **Godot 4.7** (Forward+ renderer, Metal on macOS).

## Play

**In your browser:** <https://gravityst.github.io/knightfall-enlightened/>. Best in Chrome or Edge on a computer with a mouse and keyboard; phones and tablets get touch controls (hold the device sideways). The first visit downloads about 100 MB; the page keeps it in the browser's storage, so later visits start without downloading anything, and a new version only fetches the files that changed. The browser version runs on WebGL 2, so it uses lighter graphics than the desktop build: no global illumination, screen-space reflections or volumetric fog, shorter draw distance and less grass. Quick save and load are also on K and L there.

**On the desktop:** open `project.godot` in Godot 4.7 and press Play.

The very first launch imports the models and textures (about two minutes) and compiles the shaders once. After that the world is ready about 2-3 seconds after you press **Begin Your Journey**: models and map textures start loading on background threads while the title screen is showing.

## Controls

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift | Sprint (on horseback: gallop) |
| Space / Ctrl | Jump / crouch (sneak: animals notice you later). Swim up / down in water |
| E | Interact: talk, open doors, loot chests, sleep in beds, drink from rivers, skin game, ride your horse |
| Left mouse | Click to cut; hold to draw back for a heavy blow (about twice the damage, smashes a shield guard aside). Works from the saddle too. R draws or sheathes the sword |
| Right mouse | Raise your shield; raise it just as a blow lands to parry (the attacker reels, open to a riposte) |
| Alt, or double-tap A / D / S | Dodge: a quick side- or back-step that blows can't land on |
| T | Light a torch |
| G | Hold out a gold coin (servants only respond to coin) |
| H | Whistle for your horse. In the saddle: W canters, Shift gallops, Ctrl walks, S reins in (then backs up); steer with the mouse or A / D |
| Z | Wait an hour (not with enemies nearby) |
| 1 · 2 · 3 · 4 | Quick-use: eat · drink · bandage or healing draught · build a campfire |
| Tab / I · J · M · Esc | Inventory · journal (your tasks) · map (click to set a waypoint, right-click to clear it) · pause & settings |
| In the inventory | Click to select, double-click / E to use or equip, right-click for quick use, Q to drop (it falls into the world; pick it up again with E) |
| F5 / F9 | Quick save / quick load |
| F1 · F2 | Hide HUD · screenshot (saved to Pictures/Knightfall) |

**On a phone or tablet** (or add `?mobile` to the page address): the left thumb moves (a stick appears where you touch; push it to the edge to run, or gallop on horseback), and a drag anywhere else looks around. The buttons on the right strike (tap to cut, hold for a heavy blow), block (hold; just in time to parry), jump, use, dodge, draw the sword, light a torch and crouch; along the top are the menu, bag, map and tasks, and down the left eat, drink, heal and call your horse. Every menu has a Close button, tap a chosen item again to use or equip it, and the map has zoom buttons. The interface is drawn larger, and the game uses lighter graphics settings.

## The island of Aldmere

An island on a 6 x 6 km map with snowy mountains, frozen tundra, deep forests, open plains, the Qadir desert, rivers, lakes (Mirrormere has a ruined keep on its island) and coastline.

- **3 towns** (Kingsbridge, Frosthold, Sandmere) with seven knights each and twice-weekly market days, when visiting traders bring rare wares.
- **8 villages**, each guarded by two knights, with taverns, smithies, stables, chapels, shops and farms.
- **3 castles**, each behind a curtain wall with round towers under slate cones, a gatehouse and a portcullis, around a great stone keep with corner turrets. Inside the keep a high hall of pillars and banners leads up a carpet to the throne. The **King of Aldmere** and his **Queen** hold court at Castle Ravenmoor; dukes rule Wintermere and Sunspire. Each castle has a full court ranked from the ruler down: officials (snobs), knights (honourable), one falconer, guards who patrol the wall-walks (and won't talk), cooks ("Bon Appetite!") and servants (who only respond to a gold coin). The guards lower the portcullis on anyone with a bad reputation and raise it again the next day.
- **3 ruined castles** and 12 landmarks: watchtowers, ruined towers, a stone circle, bandit camps, a shrine, an old mine, a hunter's lodge, a woodcutter camp and a desert well.
- Every building has a real interior: beds, chests, hearths and upstairs floors.
- **The wilds:** about 90 smaller places lie between the settlements: hunters' camps, wagons wrecked by the road, standing stones, beasts' dens (with their wolves or bear at home), ruined houses, old barrows and wayside shrines with stone saints. Each has something to find (a chest, or a blessing that heals you) and is named on discovery.
- **Signposts** stand where every road leaves a settlement, naming where it leads and how far.
- **Finding your way:** the compass always marks every town, village and castle (with the distance), the places you have found, your tasks and your waypoint, and shows a "?" when something unfound is close by.
- Buildings follow their region: snow-laden stone and firewood stacks in the north, sun-bleached flat-roofed adobe and palms in the desert.

**People.** About 350 residents and travellers, each with a name, a personality and a daily routine.
- People dress for their climate: furs and hoods in the north, light robes and head-wraps in the desert. Knights always wear mail and steel with sword and kite shield; swords hang at the hip until there's a fight.
- Merchants and knights travel the roads, some on horseback and some escorted.
- Townsfolk talk, trade, share rumours and directions. Explorers guide you to places; some knights train you; priests bless you.
- Everyone reacts to your reputation.

**Wildlife.**
- Deer, stags, moose, foxes, alpacas, wild horses on the plains, wolves (packs that hunt deer and grow bolder at night) and bears, in roaming herds that drift as they graze. More of them now, and closer in thick forest where the trees would hide anything far off.
- Hawks wheel over open country; crows and gulls flock.
- Ducks and geese on the lakes, crows and gulls overhead, geese migrating in V formation, fish in the water.
- Livestock in the villages.

**Work and rewards.**
- Ask knights for work: they pay bounties for culling wolves or a marauding bear and for clearing bandit camps.
- Merchants need sealed parcels carried to traders in other towns; innkeepers, cooks, shopkeepers and smiths want meat, fish, hides or pelts.
- Tasks appear in the journal (J), on the HUD and as gold markers on the map. Hand them in to whoever gave them for coin and reputation.

**Combat.**
- Quick cuts and heavy blows. Each hit has weight: a brief hit-stop, sparks or blood, a hit marker and a clang on armour.
- Shield-bearers may block (a heavy blow breaks their guard). A parry staggers the attacker, who takes extra damage while reeling. A hit can interrupt a swing that's still winding up.
- Only two foes swing at you at once. The rest circle and wait their turn.
- The foe you're fighting shows its name and health under the compass, and red arcs show which way a blow came from.
- Sneak attacks (crouched, unseen) do 2.5 times the damage. From horseback, the gallop adds to the blow.
- The fallen go limp and fall with the blow (ragdoll physics). You can still search the body.

**Riding.**
- Horses gather speed through walk, trot and canter to a full gallop, and take time to pull up.
- They turn wider the faster they go, slow on climbs and refuse cliffs.
- They lean into turns, pitch with the ground, and rear if they run into something.
- The gallop tires a horse. Its wind shows on the HUD, and it snorts when blown.
- The rider rocks with the stride, with hoof-falls in time with the legs (cobbles ring, turf thuds).
- You can't jump off at speed.

**Law and order.**
- A single stray blow earns a warning. Assault, theft or murder makes you wanted in that settlement, and the nearest two or three members of the watch come to arrest you, not the whole garrison.
- When they catch you: pay the fine, serve a day or more in the cells, or resist (only then do they draw steel).
- Talking to a knight lets you pay a fine at any time, and bounties fade after a few days.
- If you die while wanted, the watch takes its fine from your purse and you wake outside the walls; the matter is closed.

**Survival.**
- Health, stamina, hunger, thirst and warmth. Cold regions freeze you, and the desert dries you out.
- Hunt, cook at fires, drink from fresh water and sleep in beds.
- Buy horses at stables (30-60 gold, faster horses cost more) and ride them.

## Graphics

Pause → Settings offers quality presets from Low to Cinematic, plus individual toggles:
- **Global illumination:** SDFGI, a signed-distance-field ray-marched GI, on Ultra and Cinematic. Godot has no hardware ray tracing, so this is the closest equivalent.
- **Screen-space effects:** reflections, ambient occlusion and indirect lighting.
- **Atmosphere:** volumetric fog with light shafts, and bloom.
- **Render scale:** from 50% (upscaled by Apple MetalFX on a Mac, AMD FSR 2 elsewhere) to 200% (supersampling; 8K internal on a 4K display). On a 4K/Retina screen the game starts at 50% so it renders 1080p internally and upscales.
- **Other:** shadow quality, view distance, grass density, field of view and interface size. The interface scales with the screen (twice as large on a 4K display) and can be adjusted.

The world itself uses:
- a GPU CDLOD terrain blending 13 photoscanned materials
- a physically based sky with moon phases and stars
- regional weather: rain, storms with lightning, snow, blizzards, fog and sandstorms
- water with flowing rivers, Gerstner ocean waves, refraction, custom screen-space reflections and caustics
- about 135,000 instanced trees, bushes and rocks with auto-generated impostors
- GPU grass

## Project layout

```
godot/
  project.godot
  scenes/          main_menu.tscn, world.tscn
  scripts/core/    game state, world data, items, audio (procedural sound & music), assets
  scripts/world/   world, terrain, atmosphere, vegetation, grass, settlements, builder, furnish
  scripts/actors/  NPCs, NPC manager, dialogue, character models, horses, animals, wildlife
  scripts/player/  first-person player
  scripts/ui/      HUD, menus, title screen, theme
  shaders/         terrain, water, sky, foliage, grass, impostor, outfit, animal, snow
  world/           baked island data (heightmap, water, biomes, layouts, vegetation)
  tools/worldgen/  Python world baker (bake_world.py, bake_textures.py)
  tools/           smoke / perf / screenshot test harnesses
```

To re-render the inventory icons after changing `scripts/core/item_models.gd`: `godot --path . -s res://tools/bake_icons.gd` (add `-- --only=id,id` for just a few).

To regenerate the island: `cd godot/tools/worldgen && python3 bake_world.py && python3 bake_textures.py` (needs numpy and Pillow).

### Building the browser version

`tools/web/build_web.sh` builds the browser version into `docs/`, which GitHub Pages publishes. It works on a copy of the project, so the desktop project is never changed:
- colour textures are capped at 1024 px and normal / roughness maps at 512 px; the game is exported twice, with the desktop's S3TC textures and with ETC2 for phones (the page picks one by what the graphics chip can read);
- the island's heights are stored losslessly as a WebP (the float values' own bytes, rounded to 1.5 cm: 64 MB becomes 6.5), the other big maps as lossy WebP;
- `world/` and `sounds/` go into a data pack (`data1-<hash>.pck`, under GitHub's 100 MB file limit);
- every big file is named by its content (`tools/web/finalize.py`), and `tools/web/sw.js`, a service worker, keeps them in the browser's storage: a repeat visit downloads nothing, and a new version only the files that changed;
- the game is exported single-threaded for WebGL 2.

On the page, `scripts/core/web_data.gd` fetches the data pack and mounts it before play. The synthesised sounds are rendered once (`-- --render-sounds=res://sounds/gen`) as QOA-compressed resources that both the desktop and browser builds load, so no machine ever has to make them.

Browser-specific optimisations:
- Fires, smoke, sparks and blood use CPU particles (WebGL runs GPU particles through a slow transform-feedback pass), and fires switch off beyond 45 m.
- Small kit pieces drop out of view sooner.
- Ambient light comes from a colour rather than the sky's light probe.
- There are fewer townsfolk and animals at once, and distant ones animate at 8 Hz.
- No lamp or character shadows.
- Every material is drawn once behind the loading screen, so shaders compile there instead of freezing the game; the townsfolk and wildlife around you appear behind it too.
- Phones (`Game.mobile`) draw the 3D at about 480 lines while the interface stays sharp, keep fewer people and animals about, a nearer horizon, half-size terrain textures and shorter shadows.

Add `?perf` to the page address for a frame-time overlay that logs each hitch and what caused it; add `?tour` to walk a set route, and `?autostart` to skip the title screen. On the Compatibility renderer, characters and animals get their own materials (`Assets.instanced_shader`), because WebGL's per-instance shader buffer is far too small for a town.

Automated checks, run from the project folder with the Godot binary:
- `-- --smoke` plays through dialogue, trade, horses, combat (heavy blows, parry, dodge, ragdoll), hunting, survival, weather, menus, the inventory (dropping and picking up), the wild places, doors, stairs, the law, tasks and save/load. Add `--quick-horse` to stop after the riding test.
- `-- --perf` prints frame timings for five standard views; add `--paused` to separate script time from rendering.
- `scenes/main_menu.tscn -- --timing --autostart=2` presses Begin after two seconds and prints every load phase (add `--reenter` to also time a second load after quitting to the title).

## Credits

| What | Source | Licence |
| --- | --- | --- |
| Buildings, props, nature, characters, outfits, hair, animations, animals, palms, crown | Quaternius | CC0 |
| Terrain materials, modular fort (castles), iron gate, kite shield, estoc, fire pit | Poly Haven | CC0 |
| Black bear, elk, moose antlers, mallard, goose, crow, hen, hawk, gull | Poly by Google (via poly.pizza) | CC-BY 3.0 |
| Sound effects: footsteps, hooves, blades, armour, shields, parries, doors, coins, glass, cloth, books, interface | Kenney (RPG Audio, Impact Sounds, Interface Sounds) | CC0 |
| Fonts: UnifrakturCook, Cinzel, EB Garamond, IM Fell English SC | Google Fonts | OFL |
| Engine | Godot Engine | MIT |

Animal calls, voices, birdsong, weather and the ambience beds are synthesised in code (`scripts/core/audio_synth.gd`) by modelling how each sound is made:
- **Voices and animal calls:** a glottal pulse train shaped by vocal-tract formants, used for the whinny, howl, moo, bleat, growls, grunts and murmur.
- **Rain and water:** rain is built from thousands of individual drops; water from bubbles ringing over a rush.
- **Other ambience:** fire from bursts of crackles and snaps over a roar; birdsong as phrases of gliding notes; crickets as pulsed chirps; waves that wash in, break and fizz out.

Combat layers several recordings: a blade slice over the impact, an axe chop for heavy blows, and a plate clank and ring on armour. The lute music is played live. The inventory icons are rendered from the game's own models by `tools/bake_icons.gd`. The island, roads, rivers and settlement layouts are generated by `tools/worldgen`.
