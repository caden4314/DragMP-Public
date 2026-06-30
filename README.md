# DragMP

DragMP adds a multiplayer drag racing system to BeamMP on Hirochi Raceway. It is built for server owners who want a ready-to-run drag strip with working staging lights, countdown tree, timing, slips, boards, winner lights, and optional night lighting.

This repository includes two deployable BeamMP resource packages:

- `DragMP-System-WithoutBlocker`: recommended for most public servers.
- `DragMP-System-WithBlocker`: same system, but the client blocks BeamNG fun-stuff actions like boom, fling, tire break, and boost.

## Features

- Multiplayer drag racing on Hirochi Raceway's main drag strip.
- Solo runs and two-lane races.
- Stock-style pre-stage, stage, and deep-stage behavior.
- Red light detection for jumping before green.
- Pro tree and sportsman tree modes.
- 1/8 mile and 1/4 mile race modes.
- Reaction time, ET, ET without reaction time, split times, and MPH.
- Stock BeamNG timeslip integration.
- Timeboards with ET and MPH.
- Winner lights and tree/winner light testing.
- Added Hirochi drag strip lighting with synced `/drag lights` control.
- Optional DragMP race screen/GPS part for in-car timing display.

## Known Bugs

- Some players may see a short lag spike when they finish a run. This happens because DragMP sends the final run data to the server so the race state, timeslip, boards, and other racers stay synced.

## Which Package Should I Use?

Use `DragMP-System-WithoutBlocker` if you trust your server rules or already moderate fun-stuff abuse.

Use `DragMP-System-WithBlocker` if you want the DragMP client to block common fun-stuff actions during play. This helps keep public drag sessions cleaner, but it is more opinionated because it changes client input/action behavior.

Only install one DragMP package on a server at a time.

## Install

1. Download one release asset:
   - `DragMP-System-WithoutBlocker.zip`
   - `DragMP-System-WithBlocker.zip`
2. Extract it.
3. Copy the extracted `Client` and `Server` folders into your BeamMP server `Resources` folder.
4. Start or restart the BeamMP server.
5. Join Hirochi Raceway and run `/drag help`.

If your server uses a custom resource folder name, either copy the package contents into that folder or set `ResourceFolder` in `ServerConfig.toml` to the extracted package folder.

## Commands

- `/dj`: quick join.
- `/drag join`: join the next open lane.
- `/drag leave`: leave the current race.
- `/drag 1/8`: set the race distance to 1/8 mile.
- `/drag 1/4`: set the race distance to 1/4 mile.
- `/drag pro`: select pro tree auto-start.
- `/drag sport`: select sportsman tree auto-start.
- `/drag start [pro|sport]`: manually start the tree.
- `/drag status`: show race state and racers.
- `/drag stage`: show staging debug for your lane.
- `/drag reset`: reset the race.
- `/drag test [1|2]`: test tree, board, and winner lights.
- `/drag lights auto|on|off|reload`: control added drag strip lighting.

## Package Contents

Each package contains:

- `Client/DragMP.zip`
- `Server/DragMP/main.lua`

## Not Included

This public build intentionally does not include:

- Archive server upload.
- Control-log upload handling.
- EnvSync or `/env` commands.
- Persistent vehicle storage.
- Private SR electronics/controllers.
- Private mod compatibility shims.
- Ballast experiments.

Those features were kept out so public server owners can install DragMP without external backend services or private dependencies.

If you want to request access to any of the excluded features, contact me in the Scenic Route Discord at `@MYNAMEISJEFF482`, or contact me through GitHub.

## Requirements

- BeamMP Server.
- BeamNG.drive clients with BeamMP.
- Hirochi Raceway as the server map: `/levels/hirochi_raceway/info.json`.
