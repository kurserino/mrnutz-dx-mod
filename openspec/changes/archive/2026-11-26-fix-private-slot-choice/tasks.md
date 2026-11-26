# Tasks

## 1. Evidence

- [x] 1.1 Transplant the user's ares slots 1 and 2 into `stage-07` / `stage-09` (`tools/mesen/ares-import.ts`,
  `run.ts --prelude`) and reproduce the three bugs with `colour-watch.lua` on rc8. Check: `cw-door-4420-1.log`
  (witch X=255), `cw-slot2-0.log` (XCOLOUR every frame on slot 1), `cwskip-00.log` (FIRSTOK 69 frames after the
  first gameplay frame).
- [x] 1.2 Find the writer of CGRAM `$91` and the colour-math state of the witch and spider scenes. Check:
  `cgw-slot2b.log`, `cgadsub-*.log`, `scenepal-08-s1.log`, `scenepal-04-s1.log`, `oamdump-08.log`.
- [x] 1.3 Measure where the hook runs during the iris-in. Check: `hookline-00.log`, `nmitrace-00.log`.

## 2. Fix (`src/runtime.ts`)

- [x] 2.1 `slot_is_free`: reject palette 1 while `[$13BC]` is non-zero.
- [x] 2.2 `CROSS_GROUP_SCENES`, `anyGroup` set on scene reset, `choose_slot` falls back to the other group.
- [x] 2.3 `scan_chunk` static branch: skip the cleared pattern y = tile = attr = `$E0`.
- [x] 2.4 `scan_wram` fallback before the first pass; state layout `$03`.
- [x] 2.5 Unit tests in `tests/runtime.test.ts` for 2.1-2.4.

## 3. Validation

- [x] 3.1 `npm test && npm run typecheck && npm run runtime:build`: 37 tests pass, the hook fits.
- [x] 3.2 Mesen with the transplanted slots on the new build: witch fight coloured after entering the house
  (`rc9-house.log`, no bad frame after the fight starts), `stage-09` X=2 with no colour change after the upload
  (`rc9-slot2.log`), stage change `stage-00` → `stage-01` coloured 8 frames after the first gameplay frame
  (`rc9-skip-00.log`).
- [x] 3.3 `npm run sweep:all`: 40 stages, violations=0, no stage without a free slot; `stage-08` 100%, `stage-04`
  99.8% (`sweep-all.log`), persistence and power cycle pass.
- [x] 3.4 Manual check by the user in ares with the installed rc9 IPS (witch house, `stage-09`, stage starts): confirmed 2026-11-25.

## 3b. Follow-up: fast first pass

- [x] 3b.1 `scan_wram` reads every remaining entry at once; `scan_chunk` reads as many entries as fit in VBlank in the
  first pass of a scene. Check: `iris-rc11-00.log` first coloured frame 521 for first visible 520; 38 tests pass.
- [x] 3b.2 `npm run sweep:all` on the new build (rc11 and rc12: violations=0).
- [x] 3b.4 `scan_snapshot` (OAM DMA on channel 7 with saved registers) for the first pass: first coloured frame = first
  visible frame (`iris-rc12-*.log`), DMA ends by line 256 (`snaptime-*.log`), sweep `ppuOut=0`.
- [x] 3b.5 Every lit frame of every stage start (`first-frames.lua`, stages 00-30, deaths): no frame with original colours
  after the frame_hook start limit by buffer size and the oam_hook late remap (`ffall-*.log`, `ff13-*.log`); sweep passes.
- [x] 3b.3 User check in ares: rc9 and rc11 confirmed by the user; rc13 was installed and the user approved the v0.2.1
  release on 2026-11-26 before checking it in ares.

## 4. Knowledge and port

- [x] 4.1 Record in `docs/knowledge/` (palettes, frame cycle, research tools) the facts of section 1 with tags.
- [x] 4.2 Port the change to the `pause-menu` branch (`wip/v0.2.1-vblank-race-and-pause`) and run its tests.
- [x] 4.3 Archive with the v0.2.1 release.
