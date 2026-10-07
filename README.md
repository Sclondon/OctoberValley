# October Valley

A 3D take on *8 Bit Evil Returns V2* mixed with Risk of Rain 2 (and some Megabonk). Godot 4.7,
GDScript, Compatibility renderer. Alone or co-op for up to four.

Play: https://sclondon.github.io/OctoberValley/build/ (on the Scareathon arcade it is a secret
cart: type VALLEY into WaysideOS).

## The loop

1. Pick a hero on the title screen: Joe (Claw), Matt (Cursed Sword), Alex (CrossBow) or Jon (Will-O-Wisp).
2. Weapons fire by themselves at the nearest enemy. Kills drop candy; candy is experience.
3. Each level-up offers three cards: a new weapon, a weapon level, or a passive. Up to 5 weapons and 5 passives.
4. Follow the beam of light to the altar and summon the stage boss. Jump its shockwaves.
5. The dead boss leaves a chest (a free card) and opens the portal to the next stage.
6. Three stages (The Graveyard, The Pumpkin Patch, The Black Mire), then they repeat, harder, until you die.

Difficulty rises by 1 every two minutes and by 0.6 per stage; it scales enemy health, damage,
numbers and the chance of elites (gold, bigger, 4x health, may drop a chest).

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
| F1 | enemies on/off (test yard only) |

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
- `scripts/hud.gd`, `scripts/menus.gd`: in-run display; title, cards, pause, game over.
- `scripts/hero_model.gd`, `scripts/camera_rig.gd`, `scripts/controls.gd`, `scripts/anim_sprite.gd`, `scripts/fx.gd`: hero models, camera, input map, sprite sheets in 3D, damage numbers.
- `art/build_heroes.py`: Blender script that builds the heroes.

## Commands

Godot and Blender, as installed on this machine:

    G="C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
    B="C:/Program Files/Blender Foundation/Blender 4.3/blender.exe"

    "$G" --path .                                                        # play
    "$G" --headless --path . -s res://tests/smoke_test.gd                # movement, models, spawning
    "$G" --headless --fixed-fps 60 --path . -s res://tests/loop_test.gd  # the whole loop, 16 checks
    "$G" --headless --fixed-fps 60 --path . -s res://tests/bot_run.gd -- joe 120   # a bot plays a run: balance check
    "$G" --path . -s res://tests/shots.gd -- <out dir>                   # screenshots (needs a window)

Co-op needs a rooms server. To test without the live one, run the site's route locally (a
checkout of scareathon-v3 with `npm ci` done in `server/`), then the two-copy test:

    node tools/dev_relay.mjs <scareathon-v3>/server 3111
    tools/coop_test.sh                                   # a host and a guest; 15 checks each
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

- Enemies and bosses are still the 2D sprites on billboards; levels are greybox with sprite props.
- No sound, no saved progress (silver, unlocks, best runs), no weapon evolutions, no scores sent to the arcade.
- No touch controls: it needs a keyboard and mouse, or a gamepad.
- Co-op: no public room list or invite links, no rejoining after a page reload, and the host cannot be handed over.
- The balance is a first guess, tuned only against `tests/bot_run.gd` (alone; co-op is untuned).

## Credits

Sprites, heroes, weapons and enemies are from 8 Bit Evil Returns. Font: Pixelify Sans (OFL, see `fonts/`).
