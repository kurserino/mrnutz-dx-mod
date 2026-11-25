# Tasks

## 1. Evidence

- [x] 1.1 Reach STAGE CLEAR in Mesen (witch and `stage-21` boss health cheats) and log palettes, OAM and NMI handler.
  Check: `sc-witch.log`, `sc-blizzard.log` (Mr. Nutz alone on palette 4, slot 4 = `$85:9CC0`).
- [x] 1.2 Find the init, its scene table write and a hook point in forced blank with no later sprite palette write.
  Check: `w055e-witch.log`, `sc-init-witch.log`.

## 2. Implementation

- [x] 2.1 `clear_hook` in `src/runtime.ts` and the manifest entry for `$9D:E452`.
- [x] 2.2 Tests: fixture bytes for the new site, original-area change list, `clear_hook` structure. 38 tests pass.

## 3. Validation

- [x] 3.1 Mesen: slot 4 holds the selection during the whole Stage Clear after the witch and the `stage-21` boss; chest and
  coins unchanged (`sc10-witch.log`, `sc10-blizzard.log`, screenshots).
- [x] 3.1b All Stage Clear screens: `stage-clear-all.lua` on every stage state finds exactly 5 (after `stage-04`, `08`,
  `15`, `21`, `25`), each with the selection in slot 4; `stage-30` leads to the ending; with the original selection
  the screen is pixel-identical to the original ROM (`scall-summary.log`, `scall-04-orig.log`).
- [x] 3.2 `npm run sweep:all` passes (violations=0, no stage without a free slot).
- [x] 3.3 User check in ares: confirmed 2026-11-25.

## 4. Knowledge, port, archive

- [x] 4.1 Record the Stage Clear facts in `docs/knowledge/` with tags.
- [x] 4.2 Port to `wip/v0.2.1-vblank-race-and-pause` and run its tests (39 pass).
- [ ] 4.3 Archive after the user's check.
