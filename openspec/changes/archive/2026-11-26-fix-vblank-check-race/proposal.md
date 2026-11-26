# Proposal

## Why

Reported in v0.2.0: during the Mr. Blizzard (yeti) boss breath attack, Mr. Nutz drops the selected colours and shows his
original palette until the scene changes. The cause is a race in the runtime hook's VBlank check. On a lag frame,
`vblank_ok` sees the VBlank flag at scanline 261, then latches V = 0 after VBlank has ended, and accepts it. The OAM
scan then reads `$2138` during active display and gets garbage. The garbage marks palettes 3 and 7 as taken by fixed boss
parts for the whole scene, so the private slot X = 7 is released and no free slot is left [trace]
`docs/traces/franken-2138.log`, `docs/traces/franken-vb.log`. The same check guards the hook's CGRAM writes, so they
can also land in active display.

## What Changes

- Runtime ROM hack (not the static palette pipeline). `vblank_ok` in the runtime hook (`src/runtime.ts`) accepts only a
  latched V counter in `225..LAST_SAFE_SCANLINE`, so a check that straddles the end of VBlank fails.
- `oam_hook` stops trusting the `$4212` flag alone before its CGRAM writes and uses the same scanline window
  (225..258). Its CGRAM writes during active display, interleaved with the game's sky HDMA, are what recolours BG
  palette 0 (HUD outline) during the breath attack.
- A failed check already defers the work to a later frame (scan chunk, slot restore, colour upload), so no caller
  changes.
- New Mesen regression for the case: a script that reproduces the breath attack and fails if the private slot is lost
  or `stickyMask` gains a palette that no high-OAM entry uses.
- Knowledge base: record the lag-frame race and the Mr. Blizzard reproduction (`frame-cycle.md`, `palettes.md`,
  `research-tools.md`).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `runtime-palette-switch`: "Safe and repeatable update" gains an explicit rule. Every PPU read or write by the hook
  must happen inside VBlank, including on lag frames. It also gets a scenario: the selected colours stay on Mr. Nutz
  through a boss attack that causes lag frames.

## Impact

- Code: `vblank_ok` in `hookSource()` (`src/runtime.ts`), a few bytes longer. The hook code size and the manifest
  entries stay the same, apart from the hook bytes.
- Tests: `tests/runtime.test.ts` (assembled `vblank_ok` checks both bounds); new Mesen script for the boss case.
- Emulator validation: `npm run sweep:all` plus the new boss reproduction in Mesen 2. The reproduction state is built
  from the user's ares savestate (WRAM/VRAM/CGRAM transplanted into the `blz-02` Mesen state of the same scene). It is
  private and not committed. Assumption to verify: transplanting OAM is not needed, because the game re-uploads the OAM
  buffer every NMI.
- Interaction: the uncommitted `pause-menu` change also edits `src/runtime.ts`. This fix touches only `vblank_ok`, and
  a v0.2.1 hotfix can be built from the `v0.2.0` tag in a separate worktree.
