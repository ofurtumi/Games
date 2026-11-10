Íbúð módel má finna í öðru repo `https://github.com/ofurtumi/ibud`, þegar það er sótt má keyra ln -s /path/to/repo/ibud.blend ./assets/models/ibud.blend

## Leikurinn / The game

You are a spider in the apartment. Hunt bugs, grow stronger, lure out the
bosses: the Mouse (kitchen), Vaskur the cat (kitchen; he is netted, not hurt) and finally Tumi, the owner.

| Input | Action |
| --- | --- |
| WASD / arrows, Space | move, jump (air jump) |
| LMB (hold) | grapple / swing |
| RMB (hold) | web shot |
| Shift | pounce (dash that bites, brief invulnerability) |
| Q | web burst (area damage + slow) |
| E | enter the nest on the living room table (shop) |
| 1 / 2 / 3 | pick an upgrade |
| Esc, F | pause, fullscreen |

Loop: kills give XP (level up = pick 1 of 3 upgrades) and crumbs (spent in the
nest). Each room has its own bugs and a bonus (kitchen: crumbs, bedroom: XP,
bathroom: healing, entrance: elites). Sugar-cube caches are hidden around the
apartment each act. Enough kills summon the act's boss; bosses drop relics.
Dying or winning pays out silk, spent in the main menu on permanent upgrades
(saved to `user://ibud_save.json`).

Code map (`scripts/`): `Data.gd` holds every tunable number (zones, enemies,
bosses, upgrades), `Game.gd` runs the loop, `Enemy.gd` / `Boss.gd` are the AI,
`Hud.gd` is all UI, `MeshKit.gd` builds the placeholder primitive models,
`World.gd` adds the ceiling, room lights and boots the game.
