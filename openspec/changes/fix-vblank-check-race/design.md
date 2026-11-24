# Design

## Context

See proposal.md (Why). Hook layout, `oam_hook`/`input_hook`, `stickyMask` and the private slot are described in
`docs/knowledge/mod-implementation.md`. NMI timing (joypad mirror at scanline 231-259, or 2 on a lag frame) is in
`docs/knowledge/frame-cycle.md`.

Current `vblank_ok` (`$A0` hook bank, inside `hookSource()` in `src/runtime.ts`, identical in v0.2.0):

```
LDA $4212 / BPL vb_no            ; VBlank flag
LDA $213F / LDA $2137            ; reset latch flip-flop, latch H/V
LDA $213D / XBA / LDA $213D / AND #$01 / XBA
REP #$20 / CMP #LAST_SAFE_SCANLINE+1 / SEP #$20 / BCS vb_no
CLC / RTS
```

Bad frame F891 in the reproduction [trace] `docs/traces/franken-vb.log`: `input_hook` entered at scanline 261. The
`$4212` read at line 261 returned `$C2` (VBlank). The `$213D` reads at line 0 returned `$00/$00`. V = 0 passed
`< 251`, and the 64 `$2138` reads ran on lines 0-9 [trace] `docs/traces/franken-2138.log`. `stickyMask` went from `$01`
to `$89`, and the private slot X went from 7 to `$FF` [trace] `docs/traces/franken-masks.log`.

## Goals / Non-Goals

**Goals:**
- `vblank_ok` returns C=0 only when the latched V counter is inside `225..LAST_SAFE_SCANLINE` (250).
- Every caller (scan chunk, slot restore, colour upload, restore-on-scene-change) gets the fix without changes.

**Non-Goals:**
- Changing `LAST_SAFE_SCANLINE`, the scan size (16 entries per frame) or the private-slot policy.
- Clearing `stickyMask` entries polluted by earlier garbage reads. With the fix, garbage reads no longer happen, and
  `stickyMask` is reset on every scene change anyway.
- PAL timing (the supported ROM is the NTSC USA release).

## Decisions

1. **Lower bound on the latched V counter.** After the `LAST_SAFE_SCANLINE` compare, add `CMP #$00E1` / `BCC vb_no`
   (A16). The latched value is a single sample taken after the flag read. If it is in `225..250`, VBlank was active
   at the latch, and at least 11 lines remain for work that started before the latch.
   - Alternative: latch first, then read `$4212`. This only moves the race: the flag can be read at line 0 after a
     latch at line 261, and line 261 already fails the upper bound. The lower bound alone closes both orders, so the
     flag read stays as a cheap early exit.
   - Alternative: test `$4212` bit 7 again after the latch. This gives the same result, but the V range check is
     needed anyway and keeps a single source of truth.
2. **Keep the `$4212` early exit.** It avoids latching the counters during active display. `$2137` latching is
   harmless there, but the exit saves cycles on the common non-VBlank path.
3. **Byte cost.** +5 bytes (`CMP #imm16` = 3, `BCC` = 2) inside the hook code at `$A0:8000+`. The IPS entry for the
   hook code changes length; no other manifest entry changes. Rollback: rebuild from the v0.2.0 source (the hook code
   entry's original bytes are the `$FF` expansion fill).
4. **Regression.** Add a Mesen script (`tools/mesen/blizzard-breath.lua`, already used to find the bug) that runs the
   boss reproduction with a non-original selection. It fails when X becomes `$FF` while no group slot is really used,
   when `stickyMask` gains a bit that no high-OAM entry has, or when any `$2138` read by the hook happens outside
   scanlines 225-261. The reproduction state is private (built from the user's savestate, `output/`), so this check is
   a documented manual/optional step, not part of `sweep:all`. `sweep:all` gets a generic assertion: no hook `$2138`
   read outside VBlank on any stage.

5. **`oam_hook` uses the same window (`oam_window_ok`, V in 225..258).** It only checked the `$4212` flag before its
   32-byte CGRAM writes (`restore_custom`, `put_custom`). It normally runs at 225-254 [trace] `franken-oh.log`, so
   nothing changes there. On a lag frame it now exits (no CGRAM access, no remap) instead of writing while the game's
   sky HDMA rewrites CGADD (`$00`/`$0E`) on every line.
6. **Glitch mechanism (the user-visible bug).** When a hook CGRAM write runs in active display, HDMA moves CGADD
   between our `$2122` writes, and the rest of our 32 bytes lands in BG palette 0. Simulation: forcing the race input
   (the `$4212` flag seen at line 261) at `$A0:839E` during the breath makes `restore_custom` write at line 11. CGRAM
   `$01` then goes from `$0023` to `$7BDE`, and the HUD outline turns white until the next palette load [trace]
   `race-v020.log`. With the fix and the same forcing, there are 0 active-display writes and the HUD matches the
   original ROM [trace] `race-fixed.log`.

## Risks / Trade-offs

- [Fewer frames pass the check on heavy scenes] → Correct by design: work is deferred one frame. The scan still
  completes a pass in ≥ 8 frames, and the slot is only chosen after a full pass.
- [The reproduction depends on a transplanted state (OAM not transplanted)] → The game re-uploads its OAM buffer every
  NMI, and the bug is in our check, not the scene data. The generic `sweep:all` assertion covers every stage on
  original states.
- [The `pause-menu` WIP in the working tree also edits `src/runtime.ts`] → The fix touches only `vblank_ok`. A v0.2.1
  hotfix is built from tag `v0.2.0` in a separate worktree so no WIP ships, and the same edit is applied on `main`.

## Migration Plan

Ship as v0.2.1 (IPS on a clean ROM, replaces v0.2.0). Save records are unchanged (same SRAM format), so players keep
their selection. Rollback: apply the v0.2.0 IPS to a clean ROM.
