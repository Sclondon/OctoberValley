# October Valley

A 3D take on *8 Bit Evil Returns V2* mixed with Risk of Rain 2 (and some Megabonk). Godot 4.7,
GDScript, Compatibility renderer. Alone or co-op for up to four.

Play: https://sclondon.github.io/OctoberValley/build/ (on the Scareathon arcade it is a secret
cart: type VALLEY into WaysideOS).

## The loop

1. Pick a hero on the title screen: Joe (Claw), Matt (Cursed Sword), Alex (CrossBow) or Jon (Will-O-Wisp).
2. Weapons fire by themselves at the nearest enemy (or at the boss, once it is in reach). Kills drop candy; candy is experience.
3. Each level-up gives back a tenth of your health and offers three cards: a new weapon, a weapon level, or a passive. Up to 5 weapons and 5 passives.
4. Follow the beam of light (and the arrow on the screen) to the altar and summon the stage boss. Jump its shockwaves.
5. The altar works like Risk of Rain 2's teleporter: it charges while a hero stands inside its ring (75 s), and the horde keeps coming. The dead boss leaves a chest (a free card).
6. Boss dead and altar charged: the horde falls and the portal to the next stage opens.
7. Three stages (The Graveyard, The Pumpkin Patch, The Black Mire), each 280 m across, then they repeat, harder, until you die.

Difficulty rises by 1 every 90 seconds and by 1.2 per stage; it scales enemy health, damage,
numbers and the chance of elites (gold, bigger, 4x health, may drop a chest). Past difficulty 4
health and damage also grow with the square of the excess, so a strong build does not coast.
The first 100 seconds of a run are a warm-up (the horde starts at 45% of its rate), and while a
boss is alive a third of the usual horde keeps coming. The HUD names the difficulty: CALM,
UNEASY, SPOOKY, HAUNTED, CURSED, NIGHTMARE, ALL HALLOWS. All of these numbers are constants at
the top of `scripts/director.gd`.

A run ends with a score: 10 a kill, 1000 a stage cleared, 50 a level gained, 2 a second
survived. Alone, the best with each hero is kept (`user://october_valley.json`, see
`scripts/save.gd`) and shown on the title screen. On the web the score is also posted to the
page the game sits in: `window.parent.postMessage({ type: 'PLAYER_DIED', score }, '*')`.
The arcade does not listen for it yet.

## Co-op

CO-OP on the title screen: one player makes a room and gets a four-letter code, up to three
friends join with it, everyone picks a hero, and P1 starts.

- Candy is shared: everyone levels together and picks their own cards. Nothing pauses.
- The horde grows with the team (60% more credits and 20 more enemies per extra hero), and the boss leaves a chest each.
- A fallen hero watches a teammate and gets back up, at half health, on the next stage. The run ends when everyone is down.

How it works (the same design as 8 Bit Evil Returns V2): the player who made the room is the
host and runs the whole fight. Guests move their own hero and draw the enemies, shots and loot
from the host's snapshots, 20 a second. The Scareathon server only keeps the room and relays
packets (`server/routes/octoberValley.js` in scareathon-v3, which reuses V2's room code).
If the host leaves, the game ends for everyone.

## Controls

| | |
|---|---|
| WASD / left stick | move |
| Mouse / right stick | look |
| Space / A | jump, and once more in the air |
| Shift / click left stick | sprint |
| E / X | interact (altar, portal) |
| Mouse wheel | zoom |
| Esc / Start | pause |
| 1-3, arrows + Enter, or click | pick a card |
| M | sound on/off (also on the title and pause screens) |
| F1 | enemies on/off (test yard only) |

On a phone or tablet (`scripts/touch.gd`): the left half of the screen is a stick that
appears under the thumb, dragging on the right half looks around, and JUMP and RUN are bottom
right (RUN stays on until tapped again). USE appears at the altar and the portal, II (top right)
pauses, and cards, heroes and menus are tapped. The controls show themselves on a device whose
main pointer is a finger, or at the first touch anywhere; pressing a key during play puts them
away again. Add `?touch` to the page address (or `-- --touch`) to see them on a desktop.

The screen is laid out for the window's shape (`_watch_window` in `scripts/main.gd`): wide,
wide on a touch screen (larger), or upright (hero cards two by two, upgrade cards stacked, the
camera fitted to the width). On touch screens the 3D view is drawn at no more than about 1.6
million pixels and stretched; the HUD and menus stay sharp.

## Layout

The scene is built in code; `scenes/main.tscn` is just `scripts/main.gd`.

- `scripts/main.gd`: the loop and its states (title, lobby, playing, upgrade, paused, dead). Builds each stage into a fresh `world` node.
- `scripts/net.gd`, `scripts/netsync.gd`: the co-op room connection, and what the host and guests send each other.
- `scripts/team.gd`: the heroes in the run; enemies, loot and boss attacks ask it who to go for.
- `scripts/db.gd`: **all content as tables**: weapons, passives, heroes, enemies, bosses, stages, sprite sheets. Start here to add or tune things.
- `scripts/player.gd`: a hero: movement, health, experience, the build (weapons and passives), upgrade choices. In co-op, `driven` and `simulate` say what this machine's copy of a hero does.
- `scripts/weapon.gd`, `scripts/shot.gd`: a weapon's cooldown and aim; the shot behaviours (bolt, boomerang, seeker, orbit, flask/pool, flash).
- `scripts/enemy.gd`, `scripts/boss.gd`, `scripts/hazard.gd`: enemies (sprites on billboards), boss attack patterns, boss shots and shockwaves.
- `scripts/director.gd`: spawns packs on a credit budget, scales them, summons the boss, drops loot.
- `scripts/pickup.gd`, `scripts/altar.gd`: candy, hearts and chests; the altar and portal.
- `scripts/level_base.gd`, `scripts/stage.gd`, `scripts/test_level.gd`: level building blocks, the generated stages, the test yard.
- `scripts/hud.gd`, `scripts/menus.gd`: in-run display (bars, objective, the arrow to the altar, the red edge when hurt); title, cards, pause, game over. Both have a `relayout` for wide and upright screens.
- `scripts/touch.gd`: the touch controls.
- `scripts/sfx.gd`: every sound and the music, synthesised at start-up from the tables at the top of the file (no audio files). `Sfx.play`, `Sfx.at`, `Sfx.music`.
- `scripts/save.gd`: best runs and the sound setting.
- `scripts/hero_model.gd`, `scripts/camera_rig.gd`, `scripts/controls.gd`, `scripts/anim_sprite.gd`, `scripts/fx.gd`: hero models, camera (and its shake), input map, sprite sheets in 3D, damage numbers, puffs and rings.
- `shaders/terrain.gdshader`, `shaders/night_sky.gdshader`: the pixel-art ground and rock, and the sky with its stars and moon. `shaders/grid.gdshader` is the test yard's measuring grid.
- `art/build_heroes.py`: Blender script that builds the heroes.

## Commands

Godot and Blender, as installed on this machine:

    G="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
    B="C:/Program Files/Blender Foundation/Blender 4.3/blender.exe"

    "$G" --path .                                                        # play
    "$G" --headless --path . -s res://tests/smoke_test.gd                # movement, touch, models, spawning: 21 checks
    "$G" --headless --fixed-fps 60 --path . -s res://tests/loop_test.gd  # the whole loop, 18 checks
    "$G" --headless --fixed-fps 60 --path . -s res://tests/bot_run.gd -- joe 150 kite 7   # a bot plays a run: balance check
    "$G" --path . -s res://tests/shots.gd -- <out dir>                   # screenshots (needs a window)
    "$G" --path . -s res://tests/shots.gd -- <out dir> 390x844 --touch   # the same as a phone held upright (844x390: on its side)

`bot_run.gd` takes a hero, the seconds to farm before going to the altar, a bot (`kite` plays
sensibly, `circle` barely) and a seed. Headless runs make no sound and write no save.

Co-op needs a rooms server. To test without the live one, run the site's route locally (a
checkout of scareathon-v3 with `npm ci` done in `server/`), then the two-copy test:

    node tools/dev_relay.mjs <scareathon-v3>/server 3111
    tools/coop_test.sh                                   # a host and a guest; 15 checks each (pass the server's address if not on 3111)
    "$G" --path . -- --server=http://127.0.0.1:3111      # or play copies by hand against it

Web build and publish (GitHub Pages serves `build/` from Sclondon/OctoberValley):

    "$G" --headless --path . --export-release "Web" build/index.html
    node tools/serve.mjs 8791        # try it at http://127.0.0.1:8791/ (add ?server=... for co-op)

After pushing a new build, bump `OCTOBER_VALLEY_URL`'s `?v=` in scareathon-v3's
`src/pages/Arcade/games.tsx`. If the packets in `netsync.gd` change, bump its `PROTOCOL`.

A test that hits a script error never quits, so run them with a timeout and read the log.

Rebuild the heroes after editing `art/build_heroes.py`, then re-import:

    "$B" -b --factory-startup --python art/build_heroes.py -- <preview dir>
    "$G" --headless --path . --import

Each hero is a stack of boxes measured in sprite pixels (1 px = 8 cm) on a nine-bone rig. The
script overwrites `art/<hero>.blend` and `models/<hero>.glb`, so hand edits made in Blender are
lost on a rebuild: change the script, or stop using it for that hero.

## Not there yet

- Enemies and bosses are still the 2D sprites on billboards; levels are boxes, ramps and sprite props under a pixel-art shader.
- The sound and music are synthesised and have never been listened to by a person: the notes are in key by construction, but the mix and the tunes need ears.
- The touch controls pass the tests and look right in a phone-shaped window, but have not been held in a hand. Frame rate on a real phone is unmeasured.
- Saved: best runs and the sound setting only. No silver or unlocks, no weapon evolutions. The score is posted to the arcade page but the site does not record it yet.
- Co-op: no public room list or invite links, no rejoining after a page reload, and the host cannot be handed over.
- The balance is tuned against `tests/bot_run.gd` only, alone (co-op is untuned). Its kite bot beats the first boss about half the time, the second about one run in six, and has not cleared the third. A person will differ.

## Credits

Sprites, heroes, weapons and enemies are from 8 Bit Evil Returns. Font: Pixelify Sans (OFL, see `fonts/`).
