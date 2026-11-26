# Proposal

## Why

The user wants Mr. Nutz in the selected colours on every STAGE CLEAR screen. The hooks only run in the gameplay
NMI (`$01DC = $835B`); the Stage Clear screen runs on the other handler (`$8357`), so Mr. Nutz shows his original
colours there.

## What Changes

Runtime ROM hack (`src/runtime.ts`), not the static palette pipeline.

- New manifest site `$9D:E452` (file `0x0EE452`): `JSL $9DABA7` (scene init of the Stage Clear screen, right after
  `[$055E] = $82:D474`) becomes `JSL clear_hook`. `clear_hook` runs the relocated call, then, with a non-original
  selection, writes the selected palette into the CGRAM slot that holds `$85:9CC0` in that table (slot 4), still in
  forced blank.
- On that screen Mr. Nutz is the only object drawn with `$85:9CC0` (chest on palette 5, coins on palette 1), so the
  scene slot itself can carry the selection. No other screen changes.
- Research tools: `stage-clear-probe.lua`, `stage-clear-init.lua`.

## Capabilities

### New Capabilities

### Modified Capabilities
- `runtime-palette-switch`: adds the Stage Clear screen requirement.

## Impact

- `src/runtime.ts` (hook code, one manifest entry), `tests/runtime.test.ts`, rebuilt IPS (one more original-area
  change: 4 bytes at `0x0EE452`).
- Validation: Mesen Stage Clear after the witch and the `stage-21` boss (boss health cheat), `npm run sweep:all`, user check
  in ares.
- Every Stage Clear screen goes through `$9D:E43A-$9D:E452` (constant table `$82:D474`): there is one per world end,
  five in total, all verified.
