# Design: Runtime palette switching

## Current implementation
The baseline Node.js/TypeScript builder creates an IPS that changes one 32-byte table at file offset `0x029CC0`; it does **not** include runtime code.

## Proposed low-level design (research pending)
1. Investigate controller polling routine(s) and find a safe, conflict-free button-combination hook. Save complete Mesen disassembly, PC, register state and byte sequence before hooking.
2. Determine how CGRAM `$C0-$CF` is refreshed across frames, levels, death animation and transitions. Character currently uses 6 OAM sprites with palette index 4.
3. Determine ROM free space (or justified expansion plan) for 65C816 code, palette lookup tables, and state variables. Prove no overlap with existing game data.
4. On press edge, update separate fur/outfit indices, then schedule one safe VBlank palette upload or integrate with existing DMA routine.
5. Avoid writes to CGRAM while PPU actively renders; respect 65C816 P/M/X width and bank conventions, save/restore modified registers and flags.
6. Provide original preset and deterministic reset behavior.
7. Extend patch manifest to whitelist the exact hook sites, added code, tables, and every modified byte.
8. Build with assembler verified in Windows; compare IPS-applied result against expected ROM and smoke test in Mesen + ares.

## Static findings (2026-11-04, see `docs/static-analysis.md`)
- Palette `$C0-$CF` is uploaded by the tail of the scene PPU-init routine `JSL $9DABA7` (`$9DAC7E-$9DACB5`): an 8-iteration DMA loop reading 4-byte (addr, bank) pointers from `[$10]` (copied from `$055E/$0560`). Tables at `$82:D454+` always place `$85:9CC0` in slot 4. Hypothesis: no per-frame upload of `$C0-$CF`.
- Joypad 1 raw state is mirrored `$4218 → $1A6F` at `$81828A` and `$8083D1`. L/R already have a conditional function at `$8182F1-$818333` (gated by `$1EC9` bit0).
- NMI dispatches through `JMP ($01DC)`; `$01DC=$8357` routes to `JML $9DB413` (hypothesis: gameplay NMI).
- The 1 MiB ROM has no proven free space (only `$9DA500-$9DA5FF`, unproven). Runtime code SHALL live in expanded ROM.

## Implemented approach (2026-11-04, see `docs/runtime-hook.md`)
Mesen 2.2.1 traces confirmed and refined the candidate below: the hook is `JSL $A08000` at `$81:828A` (gameplay NMI, M16 X16 DBR=$00); the scanline there ranges 231-259 and reached 2 on a lag frame, so CGRAM writes are gated by `$4212` VBlank and scanline ≤ 250 and retried next frame. Scene reloads are detected by reading CGRAM `$C6`/`$CF` (masking open-bus bit 15) and comparing with the original and the last applied colors; any other value means a foreign palette in slot 4 and is left untouched. State lives at WRAM `$7FBE00-$7FBE0B` (inside `$7FB6C0-$7FBFFF`, never accessed by the game; the earlier `$7FFFF0` block is cleared on some world changes). The Nutz palette slot is found every frame by scanning the 8-entry table at `[$055E]` for `$85:9CC0` (slot 0 in at least one Living Room stage, slot 4 elsewhere). `$01DC` is `$835B` during gameplay (not `$8357`).

## Private Nutz palette (2026-11-04)
Objects share `$85:9CC0` with Mr. Nutz, so the slot S from the scene table is never written. A second hook at `$81:C36A` (inside the OAM upload at `$81:C367`, before the DMA of the `$00:0321` buffer) picks a private slot X in the same colour-math group that no other object used since the scene table pointer changed (sticky mask; full 512-byte uploads during scene loads included), writes the Nutz palette with the selection into X, and rewrites the palette field of the Mr. Nutz entries (tile < `$50`, name table 0) to X. When another object starts using X, X gets its scene palette back first. Without a free slot Mr. Nutz stays original (spider boss, credits). Evidence: `sweep-analyze.log`, `sweep-oamtiming.log`, `sweep-oamsrc8.log`, `sweep-colormath.log`, `sweep-all.log`.

## Candidate approach (superseded by the sections above)
1. Expand ROM via `PatchManifest.expandTo` (LoROM, header size byte + checksum declared as manifest entries). New banks hold code, preset tables, and the selected-palette builder.
2. Input hook: replace a verified instruction near `$81828A` (only after E1 proves it runs once per gameplay frame) with a `JSL` to new code; relocated original instructions run inside the stub.
3. Apply: queue a 9-color CGRAM write (`$C6-$C9`, `$CB-$CF`) for the next VBlank via the verified NMI path, or write during forced blank inside the `$9DABA7` loop so scene reloads keep the selection.
4. Persist selection in WRAM confirmed unused by E5; reset to original preset on power-on.

Rollback: removing the IPS restores the original ROM; each manifest entry carries the original bytes.

## Evidence to collect before implementation
- Complete controller poll routine and its call site.
- CGRAM source/dataflow at `$85:9CC0`, including reads and DMA destination initialization.
- New code location with a verified safe free-space map.
- Emulator screenshots/recordings confirming colors across all animation frames.

## Risks / decisions
- Existing code may DMA the palette repeatedly, overwriting runtime edits.
- Other sprites may share palette index 4.
- Button combinations might overlap existing inputs.
- Save states may preserve state differently from resets.
- Some palette colors belong to shoes/eyes, not just fur/clothes; visual classification is provisional.

A menu-based interface is intentionally **out of scope** until the shortcuts are proven reliable; propose as a separate OpenSpec change.
