#!/bin/bash
# Builds dist/batomon-mod and dist/batomon-mod.zip. Needs GDRE Tools for the pck:
#   GDRE=/path/to/gdre_tools ./build.sh
set -e
cd "$(dirname "$0")"
GDRE="${GDRE:-gdre_tools}"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/mod/arena" "$STAGE/game/maps/meadow" "$STAGE/game/maps/caves" "$STAGE/game/maps/snow_field"
cp arena/arena3d.gd arena/arena_*.tscn arena/stadium.glb "$STAGE/mod/arena/"
cp arena/remaps/meadow_map.tscn.remap "$STAGE/game/maps/meadow/"
cp arena/remaps/cave_map.tscn.remap "$STAGE/game/maps/caves/"
cp arena/remaps/snow_field_map.tscn.remap "$STAGE/game/maps/snow_field/"

rm -rf dist; mkdir -p dist/batomon-mod/sprites/shiny dist/batomon-mod/cries dist/batomon-mod/music
"$GDRE" --headless --pck-create="$STAGE" --pck-version=3 --pck-engine-version=4.7.0 --output="$PWD/dist/batomon-mod/batomon_mod.pck" > /dev/null
cp mod/* README.md dist/batomon-mod/
(cd dist && python3 -c "import shutil; shutil.make_archive('batomon-mod', 'zip', '.', 'batomon-mod')")
echo "dist/batomon-mod.zip"
