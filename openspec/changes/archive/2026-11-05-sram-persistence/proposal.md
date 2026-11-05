# Proposal

## Why

The fur/outfit selection lives in WRAM (`$7FBE00`) and is lost on power-off, so the player has to pick Mr. Nutz's colours again every session. The planned pause-menu colour picker also needs somewhere durable to store choices, so persistence comes first.

This is a **runtime ROM hack** (it changes code and header bytes, not only the static palette pipeline).

## What Changes

- Declare a minimal battery-backed SRAM (2 KiB) in the LoROM header so emulators create a `.srm` save file.
- Neutralize the game's anti-copier SRAM checks. They write to bank `$70` and, if the write sticks (SRAM present = copier), either hang the game or fall through into alternate code. Static analysis found four candidates; all must be confirmed by Mesen traces before patching:
  - `$80:83EF`: `$4E75` at `$70:0034`, hangs on `BEQ *` at `$80:8400` (already documented).
  - `$81:9D3A`: `$5858` at `$70:0004`, hangs on `BEQ *` at `$81:9D4B`.
  - `$81:8F53`: `$0093` at `$70:0000`; when the write sticks the `RTS` at `$81:8F60` is skipped and execution continues at `$81:8F61` (PPU writes, effect unknown).
  - `$81:802B`: generic probe `STA/CMP $70:0000,X`, returns carry set if SRAM is writable; the caller's reaction is unknown.
  - **Trace result:** none of these four runs in the game. The trace found three other checks that do run, E `$9C:F814`, F `$82:BA10` and G `$81:C45C` (see `design.md` D2 and `docs/knowledge/protection.md`). All seven are neutralized: E-G reproduce their "no SRAM" path, A-D get defensive patches.
- Store the fur/outfit indices in a small validated SRAM record (magic + version + indices + checksum) placed away from the addresses the checks touch.
- Runtime hook: on power-on (WRAM magic absent) load the indices from a valid SRAM record, else fall back to the original palette; write the record whenever a shortcut changes the selection.
- Keep IPS soft-patching working with the original `.sfc`.

## Capabilities

### New Capabilities
- `save-memory`: battery-backed SRAM declaration, anti-copier check neutralization, and the validated save record format (fresh/corrupt fallback).

### Modified Capabilities
- `runtime-palette-switch`: the selection SHALL persist across power cycles (today only stage/world changes and soft reset are covered).

## Impact

- `src/runtime.ts`: hook code (load on init, save on change), new manifest entries (header `$FFD6`/`$FFD8`, check patches), checksum recompute already in place.
- `tests/`: manifest scope, assembled code, record checksum.
- `tools/mesen/`: new trace script for SRAM-check callers and bank `$70` accesses; sweep/persistence checks extended to cover a power cycle with a `.srm`.
- Emulator-visible: a new `.srm` file next to the ROM. Players with existing savestates from v0.1.0 should start fresh.
- Docs: `docs/knowledge/` (moved there by the `knowledge-base` change), README, CHANGELOG.

### Unverified assumptions (to confirm in Mesen before writing patch bytes)
- The four routines above are the only SRAM/copier checks, and their callers are unknown (no direct `JSL`/`JSR` found statically; they are reached indirectly).
- The game never uses bank `$70-$7D` for anything else.
- Mesen allocates SRAM from header byte `$FFD8` and persists it to `.srm` for this map mode (`$30`, LoROM + FastROM).
- Neutralizing the checks does not trigger a second-level protection (for example, a checksum over the check routines).
