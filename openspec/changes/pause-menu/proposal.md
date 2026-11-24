# Proposal

## Why

The native pause (Start) only freezes the screen. The user wants a real pause menu where Mr. Nutz's outfit can be picked from a colour grid, instead of cycling a few presets blind with `Select+L/R`. The same menu will later host Options and Cheats, so this change also builds the menu framework those changes will reuse.

This is a **runtime ROM hack** (new hook, code, graphics and tables in the expansion; no static palette change).

## What Changes

- **Pause overlay:** when the native pause starts (`$7E:13B4` set), draw a menu over the frozen game:
  - a "PAUSE" title;
  - a list with **CHANGE OUTFIT** and **RESUME**. Options and Cheats are added by later changes, and the list is built to grow.
  - Up/Down move, A or Start confirm, B goes back. Start on the list resumes, as today.
- **CHANGE OUTFIT modal:**
  - a title bar with **FUR | CLOTHES** tabs, switched with L/R;
  - a fixed **8 × 4 grid of 32 colours**, moved with the D-pad;
  - a **preview of the Mr. Nutz sprite** beside the grid, in the colours under the cursor;
  - A applies the colour to the selected part, and B goes back without changing anything.
- **Shades:** a colour picked from the grid becomes 5 fur shades or 4 outfit shades, generated at build time into tables in the expansion ROM. Nothing is computed on the console.
- **Selection model:** fur and outfit each hold either the original, one of the presets (`Select+L/R` keep cycling them), or one of the 32 grid colours. The live recolour (private palette slot, only Mr. Nutz changes) works the same for all of them.
- **Save:** record version 2 stores the new selection model. A version 1 record from v0.2.0 is still accepted.
- **Leaving the menu restores the game exactly:** VRAM, CGRAM and OAM that the menu overwrote are backed up in the WRAM buffer `$7F:D040-$7F:FFFF` and put back before gameplay resumes.
- Menu text is English only; following the game's LANGUAGE option is out of scope.

## Capabilities

### New Capabilities
- `pause-menu`: the in-game menu shown during the native pause. Covers opening and closing, navigation, the CHANGE OUTFIT modal, the colour grid and preview, and restoring the game's screen state.

### Modified Capabilities
- `runtime-palette-switch`: the selection can also be one of 32 grid colours chosen in the pause menu (shades generated automatically), alongside the original and the presets.
- `save-memory`: the save record gains format version 2 for the new selection model; version 1 records still load.

## Impact

- **Code:**
  - `src/runtime.ts`: new pause hook, menu code, font/frame tiles, colour and shade tables, save v2, manifest entries;
  - `src/` helpers for shade generation and the font;
  - `presets/` gains the 32-colour grid definition.
- **Patch:**
  - one new hook site at the paused-NMI branch `$80:83B8` (`docs/knowledge/frame-cycle.md`);
  - the expansion grows by a few KB, out of almost 1 MiB free.
- **Tests:**
  - unit tests (tables, save v2 migration, assembled widths);
  - Mesen: a new pause-menu check (open/close restores VRAM/CGRAM/OAM byte for byte, navigation, apply, save), added to `sweep:all`.
- **Docs:** `docs/knowledge/mod-implementation.md`, README controls, CHANGELOG.

### Facts this relies on (from `docs/knowledge/`)
- Paused NMI `$80:83B8`: P=`$B4`, D=`$0000`, DBR=`$00`, entered at scanline 225. The whole VBlank until scanline 0 is free. The OAM upload and the gameplay joypad mirror do not run while paused.
- VRAM is practically full, and BG3 also draws scenery in many stages. The 12 KB WRAM buffer `$7F:D040-$7F:FFFF` is untouched during gameplay.

### Unverified assumptions (to prototype in Mesen before the full build)
- The overlay can be drawn on BG3 plus sprites without disturbing a frozen scene. In mode 1 with the BG3 priority bit, high-priority BG3 tiles sit above sprites, so the grid and preview need transparent windows in the BG3 frame.
- One VBlank (about 37 scanlines) is enough to back up and restore everything the menu uses. If not, opening and closing take 2-3 frames with the screen held.
- Stage states with game-driven input (`stage-26`, `stage-31` … `stage-39`) cannot pause, so they are excluded from the menu checks.
