# Space Racer (prototype)

Mine planets, build a ship from mechanic parts, race on a track you carve
yourself. This is a sandbox for the look and feel: one planet, one generated
track, swappable builds. Godot 4.7, everything built in code.

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

## Controls

Every action is listed and rebindable under Menu > Controls (saved).
Defaults: W/S thrust and brake, A/D steer, brake while turning to drift,
Space hop, Shift boost, Ctrl laser, R rocket, Q/E strafe (expedition), F seismic
charge, X respawn, G garage, B track builder, C camera, Esc menu.

Racing is one layer plus hops. Walls are too tall to hop; barriers (yellow)
are low enough for light builds; reinforced walls (grey) need a tier-2 drill,
a laser, a rocket or a ramp in front of them.

## Garage (grid builder)

A ship is a frame (a grid shape) with shaped components on it. Left click a
part (again to put it down), click the grid to place it, R or the arrows under
the grid rotate it (every part rotates), right-click scraps a placed part
without changing your selection, clicking a placed part with nothing selected
picks it up, mouse wheel over a part repaints it. Q/E change frame, 1-5
presets, 0 random. With a part selected, the cells it can go on light up
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

## Code map (`scripts/`)

`Parts.gd` mechanics, hulls, parts, presets, stat maths ·
`ShipBuilder.gd` loadout to model · `Ship.gd` handling, drill, collisions,
shield · `Terrain.gd` destructible block grid + planet palettes ·
`Track.gd` control nodes to spline, carving, gates/pads/mines ·
`Main.gd` race loop, pickups, camera, menus, medals, save · `Mining.gd` /
`Miner.gd` expedition mode and its ship · `Controls.gd` input actions ·
`Save.gd` save file · `GridGarage.gd` grid builder ·
`TrackEditor.gd` blueprint editor · `GtMenu.gd` row menus · `Ui.gd` fonts and
panel shapes · `Hud.gd` race HUD ·
`Fx.gd` particles · `MeshKit.gd` low-poly mesh helpers.

Screenshot from the command line:
`Godot --path . -- --preset=1 --auto --shot=/tmp/a.png --frames=300`
