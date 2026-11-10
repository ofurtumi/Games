Íbúð módel má finna í öðru repo `https://github.com/ofurtumi/ibud`, þegar það er sótt má keyra ln -s /path/to/repo/ibud.blend ./assets/models/ibud.blend

## Leikurinn / The game

You are a spider in the apartment. Hunt bugs, grow stronger, lure out the
bosses: the Mouse (kitchen), Vaskur the cat (kitchen; he is netted, not hurt) and finally Tumi, the owner.

| Input | Action |
| --- | --- |
| WASD / arrows, Space | move, jump |
| LMB (hold) | grapple: reels you in, swing with WASD, hang at the anchor; Space jumps off |
| RMB (hold) | web shot |
| Shift | pounce (dash that bites, brief invulnerability) |
| Q | web burst (area damage + slow) |
| Tab | the web (skill tree) |
| E | enter the nest on the living room table (shop) |
| 1 / 2 / 3 | pick a boss relic |
| Esc, F | pause, fullscreen |

Third person, deliberately paced. Loop: kills give XP and crumbs. Every level
up, every sugar cache (5 glowing ones hidden each act, the nearest is marked)
and every web point bought at the nest gives a point to spend in **the web**:
six spokes (movement, damage, shooting, pouncing, poison, web burst) out from
a core. A node unlocks once it touches one you own; the thread nodes on rings 2
and 4 sit between two spokes and are the only way to cross from one to the
next. Each room has its own bugs and a bonus, announced when you walk in.
Enough kills summon the act's boss; bosses drop relics. Dying or winning pays
out silk, spent in the main menu on permanent upgrades (saved to
`user://ibud_save.json`).

Code map (`scripts/`): `Data.gd` holds every tunable number (zones, enemies,
bosses, the web, relics), `Game.gd` runs the loop, `Enemy.gd` / `Boss.gd` are
the AI, `Hud.gd` is the UI, `SkillWeb.gd` draws the web, `MeshKit.gd` builds
the placeholder primitive models (the spider too), `World.gd` adds the
ceiling, room lights and boots the game. Player feel (speeds, rope, camera) is
exported on `Player.gd`.
