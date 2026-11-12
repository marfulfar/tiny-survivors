# Tiny Survivors

A small turn-based tactics game made with Godot 4.8 (beta 2). Your wizard and knight face a band of skeletons. Attacks are decided with d20 rolls, adding Strength and Armour, and a natural 20 is a critical hit.

**Play in the browser:** https://marfulfar.github.io/tiny-survivors/

## Controls

| | Mouse / keyboard | Touch (phone, tablet) |
|---|---|---|
| Select, act, choose target | Left click | Tap |
| Back / cancel | Right click, Esc | Long press (½ s) |
| Move the map | Right-drag, WASD / arrows | One- or two-finger drag |
| Zoom | Mouse wheel | Pinch |
| Rotate | Middle-drag | Two-finger twist |
| End turn | End Turn button, Enter | End Turn button |

On a phone, play in landscape.

## Web build

The GitHub Actions workflow in `.github/workflows/web.yml` exports the **Web** preset on every push to `main` and publishes it to GitHub Pages. The export is single-threaded, so it runs on Pages without special server headers. To build it locally, install the 4.8-beta2 export templates and use *Project > Export > Web*.

See `STRUCTURE.md` for how the project is organised.

## Credits

3D assets by Kay Lousberg ([KayKit](https://kaylousberg.com)) and [Quaternius](https://quaternius.com), all CC0.
