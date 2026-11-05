# Mod implementation

How the patch is built and how it hooks into the game. Required behaviour lives in `openspec/specs/`:
`ips-build`, `palette-presets`, `rom-validation`, `rom-analysis`, `runtime-palette-switch`, `save-memory`.

## Two patches

| Patch | Command | What changes |
| --- | --- | --- |
| Static recolour | `npm run patch:build -- --preset presets/<file>.json` | only the 32-byte palette at `0x029CC0` (fur `$CB-$CF`, outfit `$C6-$C9`); output `output/Mr. Nutz.ips`, `Mr. Nutz.patched.sfc`, `patch-report.json` |
| Runtime (in-game switch + save) | `npm run runtime:build` | expands to 2 MiB, adds hooks and tables, declares SRAM, neutralizes the anti-copier checks; output `output/Mr. Nutz.runtime.ips`, `Mr. Nutz.runtime.sfc`, `runtime-report.json` |

Both refuse any ROM other than the supported one (size, palette signature; the runtime manifest also pins the SHA-256)
and never modify the source ROM.

## Code layout

| File | Role |
| --- | --- |
| `src/core.ts` | ROM identity, BGR555 conversion, palette diff, IPS encode/apply |
| `src/cli.ts` | command line (`inspect`, `palette`, `header`, `disasm`, `build`, `verify`, `runtime`) |
| `src/snes.ts` | LoROM mapping, header parser, linear 65C816 disassembler |
| `src/asm.ts` | in-repo 65C816 assembler with labels and M/X width tracking (`.a8/.a16/.i8/.i16`; REP/SEP); immediates that disagree with the tracked width are errors |
| `src/manifest.ts` | manifest-driven IPS builder: each entry has offset, expected original bytes, replacement, reason and evidence; overlaps, wrong originals or another ROM SHA-256 fail the build; ROM expansion with a declared fill (IPS RLE) |
| `src/runtime.ts` | hook source, preset tables, SRAM header and check patches, save record helpers, manifest assembly and checksum |
| `presets/runtime.json` | runtime presets (at most 11 per group; index 0 = original, added by the builder) |

## Runtime manifest (17 entries)

| File offset | CPU | Change |
| --- | --- | --- |
| `0x7FD6`, `0x7FD7`, `0x7FD8` | `$00:FFD6-D8` | chipset `$02`, ROM size `$0B`, SRAM size `$01` |
| `0x7FDC-0x7FDF` | `$00:FFDC` | checksum/complement recomputed |
| `0x0828A` | `$81:828A` | `AD 18 42 8D 6F 1A` (`LDA $4218 / STA $1A6F`) → `JSL input_hook` + `NOP NOP` |
| `0x0C36A` | `$81:C36A` | `A9 00 43 5B` (`LDA #$4300 / TCD`) → `JSL oam_hook` |
| 7 check sites | see `protection.md` | anti-copier neutralization |
| `0x100000+` | `$A0:8000+` | hook code, preset tables, OAM attribute tables (`memory-map.md`) |
| `0x100000-0x1FFFFF` | `$A0-$BF` | `$FF` fill |

The static palette `0x029CC0` is **not** touched by the runtime patch.

## Hooks

### `input_hook` (from `$81:828A`, gameplay NMI, after the HDMA enable; M16 X16 DBR=`$00`)

1. Runs the relocated `LDA $4218 / STA $1A6F`, saves P/X/Y/DBR, sets DBR=`$A0`.
2. **One-time init** when the WRAM magic `$5A4E` is missing (power-on): indices 0/0, then `load_save` reads the SRAM
   record. A soft reset keeps the magic, so the selection survives without re-reading the save.
3. Shortcuts: `pressed = (cur ^ prev) & cur`; with **Select** held, **L** cycles the fur and **R** the outfit (wrapping
   back to 0). After each change, `write_save` stores the record (payload first, checksum last).
4. **Manager** (non-critical): tracks the scene table (`[$055E]`), scans 16 entries of the PPU OAM per frame through
   `$2138` to learn which palettes other objects use, chooses the private slot, prepares the colours and sets
   `pending`. It never touches CGRAM itself.

### `oam_hook` (from `$81:C36A`, inside the OAM upload, early VBlank, critical path)

- Only acts when the gameplay NMI is active (`$01DC=$835B`), the manager ran in the last 2 frames (`$01DA` stamp) and
  the scene table is the one it prepared.
- Uploads pending colours to the private slot (or gives the slot its scene palette back), re-uploads after a scene
  reload, then moves **only Mr. Nutz's OAM entries** (tile < `$50`, name table 0, palette S or X) to the private slot.
  Any other object on that slot makes it get its scene palette back at once, and Mr. Nutz stays original that frame.
- Kept short so the game's HDMA enable stays in VBlank (`frame-cycle.md`).

### Private slot

- The scene slot S of `$85:9CC0` is **never written**, so every object sharing the palette keeps its colours.
- The private slot X must be in the same colour-math group as S and unused by any other object since the scene table
  changed (`stickyMask` for fixed boss parts in high OAM, plus a two-pass window for dynamic objects). It is only used
  after one full pass over the 128 entries.
- No free slot → Mr. Nutz keeps his original colours in that scene (`palettes.md`).
- A colour change has 1 frame of latency. When another object takes X, there is 1 frame of original colour by design:
  switching slots in the same frame would double the critical-path work.

## WRAM state (`$7F:BE00+`, inside the region the game never touches)

| Address | Field |
| --- | --- |
| `$7F:BE00` | magic `$5A4E` |
| `$7F:BE02` / `$7F:BE03` | fur index / outfit index |
| `$7F:BE04` | previous joypad |
| `$7F:BE06` / `$7F:BE07` | private slot X / scene slot S |
| `$7F:BE08` | scratch |
| `$7F:BE09` | `stickyMask` |
| `$7F:BE0A-BE0C` | last seen scene table pointer |
| `$7F:BE0D` / `$7F:BE0E` | `ready` / stamp of the frame the manager ran |
| `$7F:BE0F` / `$7F:BE10` | OAM scan position / completed passes |
| `$7F:BE11` / `$7F:BE12` | S / X shifted into the OAM palette field |
| `$7F:BE14` / `$7F:BE16` | expected colours at X+6 / X+15 |
| `$7F:BE18-BE1A` | slot, fur, outfit of the last upload |
| `$7F:BE1B` | scan scratch |
| `$7F:BE1C` / `$7F:BE1D` | palettes of other objects in this / the previous pass |
| `$7F:BE1E` | scan entry offset |
| `$7F:BE20` | `pending` (bit 0: upload the selection, bit 1: give X back) |

Source: `STATE` in `src/runtime.ts`. Until 2026-11-04 the state lived at `$7F:FFF0`, which the game clears on some
world changes.

## Save (SRAM)

- Record at `$70:0100`, 8 bytes: magic `$5A4E`, version `$01`, fur, outfit, reserved `$00`, checksum
  `$FFFF ^ (w0 + w2 + w4)`. Helpers: `encodeSaveRecord`/`decodeSaveRecord` in `src/runtime.ts`.
- A bad magic, version or checksum → treated as absent (0/0). An index beyond the preset count → 0 for that index.
- Header and protection changes: `memory-map.md`, `protection.md`.
- Harmless reads: the palette-restore loop (`$A0:8488`) sometimes follows an invalid scene-table pointer (banks
  `$76`/`$F0`) and reads 32 bytes for a slot nobody uses. It read open bus before SRAM existed; now it may read SRAM.
  Reads only, no visible effect [trace] `trace-sram-patched.log`.
- Rollback: apply the v0.1.0 IPS to a clean ROM. The header says "no SRAM" again and the `.srm` is ignored. Original
  bytes per entry are in `output/runtime-report.json`.

## Verification

`npm run sweep:all` is the regression gate (`research-tools.md`). Required before any release:
`npm test && npm run typecheck && npm run patch:build`, the full Mesen sweep, and the IPS replayed on a clean ROM
being byte-identical to the tested ROM.
