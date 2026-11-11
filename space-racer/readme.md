# Space Racer (prototype)

Mine planets, build a ship from mechanic parts, race on a track you carve
yourself. This is a sandbox for the look and feel: one planet, one generated
track, swappable builds. Godot 4.7, everything built in code.

## Starting up

The game opens on a title screen with your ship lapping the track behind it:
Race (practice laps and medals), Expedition, Garage, Track Builder,
Controls, Quit. Races start on a 3 · 2 · 1 · GO countdown with everyone held
on the line. Planet races end on a results screen with every pilot's place
and time, your prize, and Race again / Expedition / Main menu. The pause
menu has Main menu too.

## Modes

**Race**: one track on a planet's surface. Gates in order, shield rebuilt at
each gate. Lap under the bronze/silver/gold times (shown under BEST, scaled to
the track's length) for materials, once per medal per track.

**Expedition** (menu): mining, seen from the side. Three planets around a home
station: Cinder (home, lava pockets), Rime (big, light gravity, gas pockets,
crystal-rich), Moss (small, heavy gravity, lots of gas, hot). Each planet has
crust, mantle, a deep layer that needs a tier-3 drill (core shards), and a
core. The deeper you go the hotter it gets (drains shield, then hull). Fuel is
a fixed tank (bigger with boost tanks); heavy, high-thrust builds burn it
fast, and lasers, strafing and drilling burn some too (ECONOMY in the
garage). Depots around the system refill fuel and rockets and repair you.
Cargo only counts once you dock at the home station. Wreck the ship and the
tow home costs the cargo. The camera pulls back the longer you keep moving;
the mouse wheel sets the base zoom.

### The system

Four planets several hundred metres apart (Cinder, Rime, Moss, Magma), each
streamed in as you get near. Out in open space there's no drag, so you burn
and coast. Every planet has an outpost above its north pole run by one
mechanic: dock to bank cargo, refuel, repair, open the garage, buy from that
mechanic's market, or **race here** (three laps on the planet's own track
against its locals; Magma's racers are armoured and slow). Your finishing
place pays materials. Fuel-only depots sit between the planets.

### Rivals

The locals race with tools, and each planet's crew has its own kit:
- **Cinder**: a cutting laser, a bomb bay, a missile pod.
- **Rime**: a fast laser, a dash jet with bombs, a laser.
- **Moss**: homing missiles, a laser with a dash jet, timed bombs.
- **Magma**: armoured Basalts with missiles and bombs, and a Lance.

They hold fire for the first three seconds after GO. After that they cut
at whoever is right in front, fire missiles down the straights, drop bombs
on anyone tailing them, and dash when the road is clear. They reload every
half lap. Their shots hit you and each other but never themselves, and a
beam only bites every third of a second. Your homing missiles go for them
too.

### Contracts

Every outpost's **Contracts** board offers three jobs; you can carry three
at once (they show on the expedition HUD with their progress):
- **Haul** materials in your hold to another planet's outpost (delivered on
  docking, before the rest of the hold is unloaded)
- **Race**: win, or finish top 2, in a planet's race
- **Salvage** wrecks, anywhere
- **Survey**: reach a planet's mantle or deep layer
- **Mine** a quota of an ore
- **Bounty**: destroy a number of drones
Rewards are materials; salvage jobs sometimes also pay a blueprint you
haven't found. Taking a job puts up a fresh offer. Pick an active job on
the board to abandon it.

### Dying

Racing: a hit with no shield blows the ship apart; you're back at the last
gate a couple of seconds later with the clock still running. Mining: the
ship comes apart, your cargo stays in **your wreck** where you died (go back
for it), you're towed to the last outpost and the repairs come out of the
bank.

### Exploring

Hover slowly next to something to work it (a ring fills around the ship).
Nothing gets a marker until you've been near it, and some of it is buried.

- **Wrecks** (smoking): materials, fuel, a rocket reload, sometimes a
  blueprint. On surfaces, drifting in space, and buried in pockets you have
  to dig to.
- **Fuel**: glowing teal pockets in the rock refill the tank when you drill
  them; canisters float around the system.
- **Blueprints** unlock parts that show as `? ? ?` in the garage: Overdrive
  core, Phase drill (the only thing that cuts a planet's core), Fuel scoop
  (refuels while cruising in open space), Tractor beam (long magnet, hulls
  tow lighter).
- **Derelict hulls**: working one hooks it to your ship on a cable. Tow it
  to the station or any depot to unlock that frame (Manta, Needle, Brick).
  Space drops it. Heavy hulls drag light ships around.
- **Nine Fingers**, a black-market outpost somewhere out in the dark, sells
  the blueprints for materials (paid from the hold first, then the bank).

### Drones and traders

**Drones** guard wrecks and hulls (two at the ones carrying a blueprint or
a hull) and patrol around Moss and Magma. They sit on station until you come
close, then chase, fire slow red bolts and ram; get far enough away and they
go back. Every tool hurts them (lasers, missiles, bombs, the wrecking-ball
drill) and homing missiles go for them before ore. Dead drones drop metal
and crystal; chasing ones get a red `!` marker.

**Traders** (blue blinking beacon) fly between the outposts and park beside
the pads. Pull up slowly next to one to deal: material swaps, a refuel for
metal, and one part at 75% of the shop price. Within 500 m they get a
TRADER marker.

## Controls

Every action is listed and rebindable under Menu > Controls (saved).
Defaults: W/S thrust and brake, A/D steer, brake while turning to drift,
Space hop (drops a towed hull in the expedition), Shift boost, left mouse laser,
right mouse missile, V drop bomb, Z warp, Q/E strafe (expedition), F seismic charge,
X respawn, G garage, B track builder, C camera, Esc menu.

Racing is one layer plus hops. Walls are too tall to hop; barriers (yellow)
are low enough for light builds; reinforced walls (grey) need a tier-2 drill,
a laser, a rocket or a ramp in front of them.

## Component sub-grids

Every component with behaviour (drills, lasers, missile pods, bomb bays,
engines, thrusters, shields, magnets, tanks, scoops) has a little grid of its
own. Click a placed component in the garage to open it (hovering one says
CLICK TO WIRE). The core (the
component itself) sits on the left; place nodes from the palette, then drag
from a node's output port to another node to wire it. Only nodes wired back
to the core do anything (loose ones are dimmed). Right-click a node or wire
to remove it.

Tool wiring is the program, read along the wires:
- **mods** change the shot as it passes: Homing, Phasing, Fast, Timer, Orbit
  (Orbit on a drill makes it a wrecking ball)
- **Split** has two outputs: one shot goes down each branch
- **payloads** go off where the shot lands: Bomb, Cluster, Gravity well,
  Quench, Excavate; anything wired after a payload launches from that spot

e.g. Missile → Homing → Bomb → Split → (Timer → Quench) / (Fast → Cluster).

Other components take upgrade nodes: Capacitor / Economizer (engines),
Afterburner / Vectoring (thrusters), Hardener / Regenerator (shields),
Amplifier (magnets, tanks, scoops). Movement also has warp parts: Dash jet
and Blink drive. Many nodes are locked: find them in wrecks or buy them at
outposts and from Nine Fingers.

## Owning parts

You own parts in quantities and a build can only use what you own. New
pilots start with a small kit (one Core engine, three Thrusters, a Pilot
drill, two Air brakes, two Shield plates, two Razor fins, a Hop jet). The
garage list shows free / owned for each part; parts you have none of are
greyed out. Buy more at an outpost's **Shop**: every outpost sells stock
parts, plus its mechanics' own (Cinder: Grindhaus + Aegis, Rime: Vex, Moss:
Lodestone + Aegis, Magma: Arclight + Grindhaus, Nine Fingers: its own).
Prices are in materials and scale with size, tier and maker. Locked parts
need their blueprint before they show up. Loading a preset or saved build
you don't own the parts for is refused and tells you what's missing.

## Garage (grid builder)

A ship is a frame (a grid shape) with shaped components on it. Left click a
part (again to put it down), click the grid to place it, R or the arrows under
the grid rotate it (every part rotates), right-click scraps a placed part
without changing your selection, clicking any placed part opens its sub-grid
(a small wire mark shows which parts are wired), Esc or right-clicking an
empty cell drops the selection, mouse wheel over a part repaints it. Q/E change frame, 1-5
presets, 0 random. The tabs (POWER, MOVE, TOOLS, DEFENSE, UTILITY) filter
the parts list. With a part selected, the cells it can go on light up
green; the bar under the grid says why a spot doesn't work. The band at the
top shows what the hovered part does, who sells it, its rule and a little
demo of it working. Six save slots on the right: click an
empty one to save, a full one to load, right-click to overwrite, Delete to
clear. Engines make power and thrusters spend it; thrusters push away from
their exhaust, so sideways ones push you into turns and forward ones brake.
Drills, lasers and rocket pods work in whatever direction they face.

## Track blueprint (B)

The track is a loop of control nodes plus features (gates, boost pads, mines,
barriers, reinforced walls, ramps). The starter track is auto-generated and
free. In the editor you drag nodes, mouse wheel over a node to change the road
width there, click the road to add nodes or features, right-click to remove. The
blueprint panel checks the layout rules (length, no self-overlap, stays on the
map, enough gates) and lists the materials it needs. Rock comes from breaking
any block; metal and crystal are ore chunks you pick up (magnet range). Build
lays it onto a fresh copy of the planet. Sandbox mode ignores materials.

## Your ship model

Ships are now generated from the grid, so `assets/models/ship.blend` isn't
used for the moment (see `ShipBuilder.gd` for how the hull is built).

## Sound

All synthesised at start-up in `Sfx.gd` (no audio files): engine hum that
rises with speed, boost, drift skid, drill and laser loops, explosions sized
to the blast, missile launch, warp, hop, hits, shield down, gate chime, lap
arpeggio, pickups, bomb ticks, menu ticks and garage clunks. Only your ship
makes engine noise; rivals' weapons are heard when they're within 30 m, and
their explosions always.

## Code map (`scripts/`)

`Parts.gd` mechanics, hulls, parts, presets, stat maths ·
`ShipBuilder.gd` loadout to model · `Ship.gd` handling, drill, collisions,
shield · `Terrain.gd` destructible block grid + planet palettes ·
`Track.gd` control nodes to spline, carving, gates/pads/mines ·
`Contracts.gd` outpost jobs · `Drones.gd` hostile drones · `Traders.gd` friendly traders · `TitleCard.gd` title logo · `Sfx.gd` synthesised sound · `ToolDemo.gd` garage test range ·
`SubGridEditor.gd` component sub-grids · `Weapons.gd` runs tool programs
(shared by both modes) · `Worlds.gd` the
race/mining adapters it talks to · `Overlay.gd` death flash and banners ·
`PartDemo.gd` garage part previews ·
`Main.gd` race loop, rivals, pickups, camera, menus, medals, save · `Mining.gd` /
`Miner.gd` expedition mode and its ship · `Controls.gd` input actions ·
`Save.gd` save file · `GridGarage.gd` grid builder ·
`TrackEditor.gd` blueprint editor · `GtMenu.gd` row menus · `Ui.gd` fonts and
panel shapes · `Hud.gd` race HUD ·
`Fx.gd` particles · `MeshKit.gd` low-poly mesh helpers.

Screenshot from the command line:
`Godot --path . -- --preset=1 --auto --shot=/tmp/a.png --frames=300`
