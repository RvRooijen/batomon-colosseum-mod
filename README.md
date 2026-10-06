# Batomon Colosseum mod

A mod for Batomon Showdown that replaces the Batomon with Pokémon, has them battle in a 3D stadium, and changes the names, cries and music. The game itself is not modified: Godot loads the mod through an `override.cfg` next to the game exe.

Sprites, cries and music are not included. You add those yourself.

## What it does

- Every Batomon gets the Pokémon sprite you provide, scaled to the game's style with a black outline, at double resolution.
- Batomon are renamed after their Pokémon, Toxic and Curio become Poison and Psychic, and "monster" becomes "Pokémon" in the game's English texts.
- Battles take place in a low-poly 3D stadium (day, night and snow) with a slowly moving camera. The trainers stand behind their team and throw a Poké Ball for every monster at the start.
- Cries when you buy or evolve a Pokémon, and your own music for the title screen, battles and victory.
- "Colosseum mod" in the top-left corner of the main menu, so you can see the mod is loaded.

The game files are not modified. Batomon Showdown loads `override.cfg` from its own folder, which adds `loader.gd` as an autoload. The loader mounts `batomon_mod.pck` (the arena) and makes the other changes in memory.

## Building from source

`build.sh` creates `dist/batomon-mod.zip`. It needs [GDRE Tools](https://github.com/GDRETools/gdsdecomp) to write the pck:

```
GDRE=/path/to/gdre_tools ./build.sh
```

- `mod/`: the loader, the installer, `mapping.txt` and an example `music.cfg`.
- `arena/`: the 3D arena script, the three arena scenes, the stadium model and the remaps that point the game's battle maps to the arena.
- `blender/stadium.blend`: the stadium source, in the "Stadium" scene. Export it as glTF binary to `arena/stadium.glb`, without cameras and lights.

## Notes

This is an unofficial fan project, not affiliated with the developers of Batomon Showdown, Nintendo, Game Freak or The Pokémon Company. Pokémon names are trademarks of their owners. No Pokémon sprites, cries or music are included. The mod only changes visuals and audio, but check whether modded clients are allowed before playing online.

## Installing

1. Extract this folder anywhere.
2. Double-click `Installer.bat`. The installer looks for Batomon Showdown in your Steam libraries. If it is somewhere else, pick the folder with Browse.
3. Click Install. The mod is copied to `<game>\mods\batomon-mod` and an `override.cfg` is written next to the exe.
4. Open mod folder takes you to the folder for your own sprites, cries and music.

To turn the mod off, use Uninstall in the same installer. Tick the box to also delete the mod folder. If there already was an `override.cfg`, it is kept as `override.cfg.bak` on install and restored on uninstall.

A Steam update leaves `override.cfg` and the mods folder alone.

## Your own files

- `mapping.txt`: which Pokémon goes with which Batomon, as `batomon_id=Pokémon name`. The name is also the in-game name.
- `sprites\<name>.png` and `sprites\shiny\<name>.png`: the sprite, named after the Pokémon in lowercase without spaces or symbols (`pikachu.png`, `mrmime.png`, forms like `marowak-alola.png`). A file named after the Batomon id (`joltail.png`) takes priority. Sprites may face left and can be any size. The mod scales them, adds a black outline and makes them face right. Without a shiny sprite, the normal one is used.
- `cries\<name>.ogg` (or `.mp3`/`.wav`): played when you buy a Pokémon or it evolves.
- `music\` with `music.cfg`: per slot (`title`, `battle`, `victory`, `shop`, `boss`) a file and the point in seconds where the loop starts again. The track loops from the end of the file back to `loop_start`, so cut it at the end of the loop.

```
[battle]
file="battle.ogg"
loop_start=15.88
```
