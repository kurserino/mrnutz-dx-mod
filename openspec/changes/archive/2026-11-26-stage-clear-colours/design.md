# Design

## Context

Stage Clear init (`$9D:E3F0+`) sets the scene table `[$055E]/$0560 = $82:D474` at `$9D:E43A-$9D:E44F` and calls
`JSL $9DABA7` (scene init) at `$9D:E452`. Trace (`stage-clear-init.lua` → `sc-init-witch.log`): the call starts at
line 127 and returns at line 148 with INIDISP `$80` (forced blank), D=`$0000`, DBR=`$00`, P=`$26`; afterwards the game
writes no sprite palette (no CGADD ≥ `$80`, no DMA to `$2122`) until the screen ends, and slot 4 holds `$85:9CC0`.
Screen contents (`stage-clear-probe.lua` → `sc-witch.log`, `sc-blizzard.log`): Mr. Nutz 6 entries, palette 4, tiles
`$000-$044`; chest 25 entries on palette 5; coins on palette 1; NMI handler `$8357`. The hook code, `find_slot`,
`offsets` and `put_custom` already exist (`docs/knowledge/mod-implementation.md`).

## Goals / Non-Goals

**Goals:** selected colours on the Stage Clear screen from its first visible frame; no change with the original
selection; no effect on gameplay.

**Non-Goals:** other non-gameplay screens (intros, map, continue, ending).

## Decisions

1. **Hook site `$9D:E452`** (file `0x0EE452`, original `22 A7 AB 9D`): replaced by `JSL clear_hook`, which first
   performs the relocated `JSL $9DABA7`, so the palettes are loaded before we write. Same pattern as `frame_hook`.
2. **Write the scene slot directly.** On this screen `$85:9CC0` has no other user, so no private slot or OAM remap is
   needed; this is the only place the patch writes the scene slot of `$85:9CC0`.
3. **Forced blank, once.** The write happens right after the game's own palette load, in the same forced blank, so it
   needs no VBlank check, and nothing reloads the slot later.
4. **Manager state untouched.** `clear_hook` saves and restores `slotS`, `sBits` and `customSlot` around
   `find_slot`/`put_custom`; the next stage changes the scene table and the manager resets as usual.
5. **Guards:** no write before the one-time init (magic) or with fur = outfit = 0.

Rollback: restore `22 A7 AB 9D` at `0x0EE452` (in `output/runtime-report.json`), or apply an older IPS to a clean ROM.

## Risks / Trade-offs

- Stage Clear only exists at the end of worlds 1-5 (stage list `$99:E65F`, `$FFFF` marker → `JSL $9DE2AE`); all five
  were checked (`scall-summary.log`). Normal stage ends inside a world show no Stage Clear in the original game.
- Tests reach the screens with the debug stage skip in the last stage of each world (`stage-clear-all.lua`).
