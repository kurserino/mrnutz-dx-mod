# Tasks

## 1. Evidence

- [x] 1.1 Keep the reproduction logs in `docs/traces/` (`franken-masks.log`, `franken-2138.log`, `franken-vb.log`,
  `franken-v020.log`, `franken-orig.log`), each with a one-line header saying how the state was built. Check: the
  files exist and contain no ROM data or local paths.
- [x] 1.2 Record in `docs/knowledge/frame-cycle.md` the lag-frame race (input_hook at scanline 261, latch at line 0)
  and in `palettes.md` the Mr. Blizzard scene facts (table `$82:D77C`, boss palette 5, breath flakes palette 6, Mr.
  Nutz S=4, X=7). Record in `research-tools.md` the ares→Mesen transplant method (WRAM at `.bs1` offset `0xA8C`, VRAM
  `0x20C28`, CGRAM `0x311DB` for this ares version; OAM is serialized per object and skipped; trigger at `$00:822E-$8233`)
  and that `stage-31..39` are attract-mode demos. Check: each fact has a tag and a log.

## 2. Fix

- [x] 2.1 In `vblank_ok` (`src/runtime.ts`), add the lower bound `CMP #$00E1` / `BCC vb_no` after the
  `LAST_SAFE_SCANLINE` compare, and update the routine comment. Check: `npm run runtime:build` succeeds and the hook
  code still fits below `FUR_TABLE`.
- [x] 2.1b `oam_hook`: replace `LDA $4212 / BPL oh_out` with `JSR oam_window_ok / BCS oh_out` (V in 225..258,
  shared `read_vcount`). Check: race simulation (`race-fixed.log`) shows 0 hook CGRAM writes in active display.
- [x] 2.2 Add a unit test in `tests/runtime.test.ts`: the assembled `vblank_ok` contains both compares (`C9 FB 00` and
  `C9 E1 00`) followed by `BCS`/`BCC` to `vb_no`. Check: `npm test` passes.

## 3. Emulator verification (Mesen 2)

- [x] 3.1 Add to `tools/mesen/stage-check.lua` a generic assertion: no `$2138` read from the hook bank (`$A0`) outside
  scanlines 225-261. Report it in the RESULT line, and make `sweep.ts` fail on any. Check: `npm run sweep:all` passes
  on the fixed ROM.
- [x] 3.2 Run `tools/mesen/blizzard-breath.lua` (franken state, private) on the fixed ROM with a non-original selection
  through the breath attack. Check: X never becomes `$FF`, `stickyMask` stays `$01`, no ORACLE failures after the
  first full pass, and the screenshots show Mr. Nutz in the selected colours during the breath. Save the log as
  `docs/traces/blizzard-fixed.log`.
- [x] 3.3 Run the same script on the v0.2.0 ROM and check that the new assertion catches the bug there (control).

## 4. Build and regression

- [x] 4.1 `npm test && npm run typecheck && npm run patch:build && npm run runtime:build && npm run sweep:all` all pass.
  Check: command exit codes and `docs/traces/sweep-all.log`.
- [x] 4.2 ROM signature and IPS checks: the runtime build refuses another ROM (existing test). Replaying the IPS on a
  clean ROM gives a ROM byte-identical to the tested one. The static palette patch is unchanged (only `0x029CC0`).
- [x] 4.3 v0.2.1 hotfix: in a worktree from tag `v0.2.0`, apply only tasks 2.1-2.2, rebuild, and run tasks 3.2 and
  4.1-4.2 there. Check: the v0.2.1 IPS differs from v0.2.0 only inside the hook code entry.
- [x] 4.4 Manual check in the Mesen GUI before release: the Mr. Blizzard fight with a non-original selection, breath
  attack included.

## Notes

- 2.1b: implemented as `vblank_ok` (225..250) for CGRAM and `oam_read_ok` (225..257) for OAM reads; the remap moved to
  `frame_hook` (design decision 7).
- 3.1: the assertion is `ppuOut` in `stage-check.lua`/`sweep.ts` (any hook `$2138` read or CGRAM write outside VBlank).
- 3.2/3.3: `blizzard-fixed.log` (rc13, private reproduction state, no ORACLE failure after the first pass); the decisive
  control is the forced race: `race-v020.log` (HUD outline turns white) against `race-fixed.log` (0 active-display writes).
- 4.4: checked by the user in ares (breath fight) instead of the Mesen GUI.

## Workflow follow-up

- Archive this change after the checks pass, then sync `runtime-palette-switch`.
- Commit, tag and release v0.2.1 only when the user asks.
