# DragMP Public

Public DragMP package split from the private/local development system.

## Included

- Hirochi Raceway drag race server logic.
- Staging, deep staging, red lights, pro tree, and sportsman tree.
- 1/8 mile and 1/4 mile race modes.
- Stock BeamNG timeslip integration.
- DragMP race screen/GPS part.
- Timeboards, winner lights, tree test commands, and Hirochi lighting.

## Removed From Public Build

- Archive server UDP upload.
- Run/control-log upload handling.
- EnvSync and `/env` commands.
- Persistent vehicle system.
- Private SR drag electronics/controllers and compatibility shims.
- Local ballast experiments.

## Client Variants

- `dist/DragMP-Public.zip`: normal public client.
- `dist/DragMP-Public-FunBlocker.zip`: same client with the fun-stuff action blocker enabled.

Only run one client variant as `DragMP.zip` on a BeamMP server at a time.

## Local Test Servers

- `local-server`: normal public client on port `30815`.
- `local-server-funblocker`: fun-blocker client on port `30816`.

Copy a real BeamMP auth key into the matching `ServerConfig.toml` before public hosting.
