# DragMP

DragMP adds a multiplayer drag racing system to BeamMP on Hirochi Raceway. It is built for server owners who want a ready-to-run drag strip with working staging lights, countdown tree, timing, slips, boards, winner lights, and optional night lighting.

This repository publishes two client variants plus one shared server resource:

- `DragMP-Public-without-blocker-Client.zip`: recommended for most public servers.
- `DragMP-Public-with-blocker-Client.zip`: blocks BeamNG fun-stuff actions like boom, fling, tire break, and boost.
- `DragMP-Public-Server.zip`: shared server-authoritative timing and race control.

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

1. Download `DragMP-Public-Server.zip` and one client variant.
2. Extract the server ZIP into your BeamMP server `Resources` folder.
3. Put the selected client ZIP in `Resources/Client` and name it `DragMP.zip`.
4. Start or restart the BeamMP server.
5. Join a supported drag-strip map and run `/drag help`.

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
- Hirochi Raceway, or a map that provides a standard BeamNG two-lane `*.strip.json` descriptor.

## Timing Authority

Race state, server-observed vehicle positions, reaction time, finish crossing, elapsed time, and winner selection are evaluated by the BeamMP server. Client staging telemetry improves beam precision but is checked against server geometry and freshness limits. The winner is selected by combined elapsed time; the timing slip also exposes ET without reaction time.

## Automatic Map Support

Hirochi Raceway remains the built-in profile. DragMP also discovers BeamNG stock drag-strip descriptors mounted at `/levels/<level>/dragstrips/*.strip.json`. Custom maps that use the same stock schema can therefore work without hard-coded coordinates.

The server requires exactly two lanes with `spawn`, `stage`, and `endLine` waypoints and rejects map mismatches, invalid values, implausible lengths, and disagreeing lane geometry.
