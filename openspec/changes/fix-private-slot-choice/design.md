# Design

## Context

The manager in `input_hook` chooses the private slot X from an incremental scan of the PPU OAM (`scan_chunk`, 16
entries per frame through `$2138`, VBlank only); `oam_hook` uploads the selection into X in VBlank and `frame_hook`
remaps Mr. Nutz's entries in the WRAM buffer (`docs/knowledge/mod-implementation.md`). Three gaps, found with the
user's ares savestates transplanted into Mesen (`tools/mesen/ares-import.ts`):

- The free-slot test only looks at OAM usage. `$81:C3E8` (right after the OAM upload) writes CGRAM `$91` every frame
  from the table at `[$13BC]`, which cycles in every stage (`cgram91-writers.lua` → `cgw-slot2b.log`,
  `cgadsub-writers.lua` → `cgadsub-*.log`). A private slot 1 therefore flashes (`cw-slot2-0.log`).
- X must stay in the colour-math group of S. In the witch fight every slot 4-7 is busy, but `$2131 = $20` (backdrop
  only) for the whole fight (`scenepal-08-s1.log`); in the spider stage `$2131` is `$00` then `$2F`, never OBJ
  (`scenepal-04-s1.log`). The colour-math registers are write-only and written from constants in several places
  (`$85:939C`, `$9D:ABB2`, `$81:A660`, `$82:826C`; `frame-cycle.md`).
- During the iris-in after a stage change the NMI runs the iris routine (`$82:92B4`, `$0572`) before the frame work,
  so `input_hook` executes at scanlines 0-180 for about 60 frames (`hook-scanline.lua` → `hookline-00.log`,
  `nmi-trace.lua` → `nmitrace-00.log`). `scan_chunk` never reads, no pass completes, Mr. Nutz stays original for
  69 frames (`cwskip-00.log`). `oam_hook` still runs at line ~227, inside VBlank.

## Goals / Non-Goals

**Goals:** no private slot the game writes; a coloured Mr. Nutz in the witch fight and most of the spider fight; the
selection within about 10 frames of the first gameplay frame after an iris; no change to any manifest site.

**Non-Goals:** colouring Mr. Nutz before the first gameplay frame (intro screens keep original colours by design);
detecting colour math at runtime for every scene; other bosses not measured yet.

## Decisions

1. **Animated slot.** `slot_is_free` rejects candidate 1 while the word `$13BC` is non-zero. `choose_slot` already
   re-tests the current X each frame, so an X of 1 is given back (restore in VBlank) and another slot taken.
   Alternative rejected: compare the CGRAM of X between frames (needs `$213B` reads in VBlank, more critical-path time).
2. **Cross-group scenes as data.** `CROSS_GROUP_SCENES` lists scene table pointers (`[$055E]/$0560`) measured with
   sprite colour math off: `$82:D58C` (witch, only in `stage-08`) and `$82:D620` (spider, `stage-04`). On each scene
   reset the manager sets `anyGroup` (`$7F:BD2C`); `choose_slot` tries the same group first, then the other group
   when `anyGroup` is set. Alternative rejected: hooking every `$2131` writer to keep a WRAM copy (several constant
   writers, more manifest entries, more risk).
3. **Cleared static entries.** In the witch fight 40 high-OAM entries hold the game's cleared pattern
   y = tile = attr = `$E0` (`oam-high-dump.lua` → `oamdump-08.log`); attr `$E0` reads as palette 0 and made
   `stickyMask` mark palette 0. The static branch of `scan_chunk` skips exactly that pattern.
4. **WRAM fallback scan.** When `oam_read_ok` fails and `passes = 0`, `scan_chunk` jumps to `scan_wram`, which reads
   16 entries of `$7E:0321` within the `$0024` bytes in use (the buffer the game DMAs to OAM each frame) with the same
   classification as the dynamic branch. Entries past `$0024` are left to the PPU scan. Once a pass is complete the
   fallback stops; later scans use the PPU OAM again. The colour upload stays in `oam_hook` (VBlank).
5. **State layout `$03`.** `anyGroup` is new; a WRAM from an older build (layout `$02`) gets `anyGroup = 0` and an
   impossible table bank so the next manager run resets the scene state.

Rollback: the IPS changes only the hook area (`$A0:8000+`, file `0x100000+`); applying the v0.2.0 or rc8 IPS to a
clean ROM restores the previous behaviour. Manifest sites and original bytes are unchanged
(`output/runtime-report.json`).

## Risks / Trade-offs

- A boss part placed past the `$0024` bytes during an iris is invisible to the fallback scan [hypothesis: rare; not
  measured]. The witch fight entered through the house door showed no bad frame (`rc9-house.log`), `frame_hook`
  still unmaps Mr. Nutz when another object shows up on X in the buffer, and the PPU scan corrects `stickyMask` as
  soon as VBlank is reachable.
- `CROSS_GROUP_SCENES` relies on measurements over 2400 frames per scene; a colour-math change late in those fights
  would make Mr. Nutz look slightly different (translucency), not recolour another object.
- Excluding palette 1 removes one candidate in scenes where S is in group 0-3 (`stage-09`: X moves from 1 to 2).
