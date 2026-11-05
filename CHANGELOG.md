# Changelog

## Unreleased — SRAM save (`openspec/changes/archive/2026-11-05-sram-persistence`)

Patch: `npm run runtime:build` → `output/Mr. Nutz.runtime.ips` (2584 bytes). Patched ROM: CRC32 `8DBACAD6`.

### Added
- The fur/outfit selection is saved to battery-backed SRAM (2 KiB, `.srm` next to the ROM in the emulator's
  save folder) and restored on the next power-on. A fresh or corrupted save falls back to the original colours.
- Lives and energy addresses for testing (`docs/knowledge/game-state.md`); lives are obfuscated (BCD XOR `$A3B7` at `$7E:1889`).
- Tooling: `trace:sram` / `trace:sram:all` (SRAM and anti-copier evidence), `check:power` (real power cycles),
  `check:ending` (last stage → credits → final screen → reset → new game), RAM search helpers.

### Changed
- The anti-copier SRAM checks are neutralized (needed once SRAM exists). The trace found three active checks the
  static scan had missed (boot hang, a flag at `$7E:054C`, a write to `$7F:C07F` that makes Mr. Nutz vanish).

### Verified (Mesen 2.2.1 headless)
- `sweep:all`: 40 stages, violations=0, soft reset and world changes, power cycle (4 cases).
- No SRAM write by game code in boot, 40 stages, 2 soft resets and 4 game overs (`trace-sram-patched.log`).
- End of the game: same behaviour as the original; reset → title → new game keeps the selection.

### Notes
- Savestates from v0.1.0 still load, but start fresh to get a save file.

## v0.1.0 — 2026-11-04 — runtime palette switch (`openspec/changes/archive/2026-11-04-runtime-palette-switch`)

Patch: `npm run runtime:build` → `output/Mr. Nutz.runtime.ips` (2365 bytes, 2 MiB expanded LoROM),
published as `mrnutz-dx-v0.1.0.ips` on the GitHub release.
Source ROM: `Mr. Nutz (USA) (En,Fr).sfc`, CRC32 `A99BDD9A`, unheadered. Patched ROM: CRC32 `077391CD`.

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
- Release build (2026-11-04): IPS replayed on the clean ROM equals the tested ROM; `sweep:all` (violations=0)
  and `verify:runtime` pass; screenshots reviewed (cycling, wrap, underwater, snow, after reset).

### Known limitations
- Spider boss (Woody Land 5) and credits: no free palette slot in the same colour-math group → Mr. Nutz
  keeps his original colours there.
- Intro, "Stage Clear" and other non-gameplay screens show the original colours.
- Power-off resets the selection (no SRAM; the game hangs when it detects SRAM). Fixed in the next release (SRAM save).

### Not yet verified
- Interactive (human) Mesen GUI play-through; verification so far is headless plus screenshot review.
- Continue / game over screens.
