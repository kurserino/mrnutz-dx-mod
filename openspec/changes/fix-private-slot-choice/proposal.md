# Proposal

## Why

The user found three colour bugs in v0.2.1 rc8 (ares savestates of 2026-11-25, reproduced in Mesen by transplanting
their WRAM/VRAM/CGRAM into stage states):

1. **Witch house** (`stage-07` door → witch fight, `stage-08`, scene table `$82:D58C`): Mr. Nutz keeps his original
   colours. No slot in his colour-math group (4-7) is free there, so the hook gives up by design. But sprite colour
   math is off in that scene (`$2131` enables only the backdrop), so a free slot of the other group (0-3) would look
   the same [trace] `scenepal-08-s1.log`, `cw-door-4420-1.log`.
2. **Flashing colour** (`stage-09`, slot 2): the hook picked sprite palette 1 as private slot because no object uses
   it, but `$81:C3E8` writes an animated colour (red/green/yellow) into CGRAM `$91` (palette 1, entry 1) every frame
   while `$7E:13BC` is non-zero, which is the case in every stage [trace] `cw-slot2-0.log`, `cgw-slot2b.log`,
   `cgadsub-*.log`.
3. **About one second of original colours at some stage starts:** during the iris-in after a stage change the game's
   frame work runs out of VBlank (input hook at scanlines 0-180 for ~60 frames), so the OAM scan through `$2138`
   cannot run and no private slot is chosen until the iris ends (69 frames from `stage-00` to `stage-01`)
   [trace] `hookline-00.log`, `cwskip-00.log`, `nmitrace-00.log`.

## What Changes

Runtime ROM hack (`src/runtime.ts`), not the static palette pipeline.

- Slot choice never takes sprite palette 1 while `$13BC` is non-zero, and gives it back if it holds it.
- Scenes whose sprite colour math is measured off (witch `$82:D58C`, spider `$82:D620`) may use a free slot of the
  other colour-math group after the same group is exhausted. The list lives in the patch as data.
- When the manager cannot read the PPU OAM (out of VBlank) and no full pass is complete in the scene, it scans the
  game's WRAM OAM buffer (`$7E:0321`, `$0024` bytes in use) instead, so a slot can be chosen during the iris. The
  colours are still uploaded by `oam_hook` in VBlank. The PPU scan takes over again as soon as VBlank is reachable.
- Research tools: `tools/mesen/ares-import.ts` (ares savestate → Mesen prelude), `run.ts --prelude`,
  `colour-watch.lua`, `scene-palettes.lua`, `cgadsub-writers.lua`.

## Capabilities

### New Capabilities

### Modified Capabilities
- `runtime-palette-switch`: the private slot may come from the other colour-math group in scenes listed as having
  sprite colour math off; it never uses a slot the game animates; the selected colours appear within a few frames of
  the first gameplay frame of a scene, including after the iris-in.

## Impact

- `src/runtime.ts` hook code and state (new byte `anyGroup`, state layout `$03`), tests in `tests/runtime.test.ts`,
  rebuilt IPS. Manifest sites unchanged.
- Validation: Mesen headless with the transplanted user savestates (private, not committed), `npm run sweep:all`,
  a GUI check before release.
- Assumptions to verify: the WRAM buffer within `$0024` bytes holds every visible dynamic entry at scene start, and
  no boss part sits past those bytes during an iris; the two listed scenes never enable colour math on sprites.
