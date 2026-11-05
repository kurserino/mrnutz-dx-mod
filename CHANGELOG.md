# Changelog

## Unreleased — runtime palette switch (`openspec/changes/runtime-palette-switch`)

Patch: `npm run runtime:build` → `output/Mr. Nutz.runtime.ips` (2365 bytes, 2 MiB expanded LoROM).
Source ROM: `Mr. Nutz (USA) (En,Fr).sfc`, CRC32 `A99BDD9A`, unheadered.

### Added
- In-game colour selection: `Select+L` cycles fur, `Select+R` cycles outfit; index 0 is the original
  palette; presets in `presets/runtime.json`.
- Only Mr. Nutz changes colour: he gets a private sprite palette slot; objects that share his palette
  (`$85:9CC0`) keep their original colours.
- Selection persists across stage and world changes and soft reset (WRAM state at `$7FBE00`).
- Tooling: 65C816 disassembler (`npm run rom:disasm`), header dump (`npm run rom:header`), in-repo
  assembler with M/X width validation, manifest-driven IPS builder with ROM expansion.
- Mesen 2 headless automation (`tools/mesen/`, `.env` → `MESEN_PATH`): shared `lib.lua` oracle, per-stage
  savestates (`sweep:prepare`), parallel full-game regression (`sweep:all`, ~35 s) that fails on any violation.

### Fixed
- VBlank overrun: the OAM scan ran in the critical path and pushed the game's HDMA enable into active display
  (garbage colours in the Nutz palette in one stage). The critical hook now does only a light pass.
- Bosses / savestates: static OAM entries are read from the PPU OAM, so Mr. Nutz never borrows their slot.
- Blink when changing colours (and after unpausing): the colour upload now happens early in VBlank in the OAM
  hook; the full sweep checks every stage for blinks (flicker-check.lua, 24 changes + pause).

### Verified (Mesen 2.2.1 headless, `docs/traces/`)
- Full-game sweep, 40 stage states to the credits: original Nutz palette slot never written, no other sprite
  shown in the private slot, HDMA always enabled in VBlank; Mr. Nutz in the selected colours in >= 99% of
  visible frames in 34 stages, original colours where no slot is free (spider boss and three other stages, partly).
- Swimming in blue water (two areas), death and respawn, pause, stage transitions, soft reset.

### Known limitations
- Spider boss (Woody Land 5) and credits: no free palette slot in the same colour-math group → Mr. Nutz
  keeps his original colours there.
- Intro, "Stage Clear" and other non-gameplay screens show the original colours.
- Power-off resets the selection (no SRAM; the game hangs when it detects SRAM).

### Pending before release
- Manual Mesen GUI regression pass with this build.
