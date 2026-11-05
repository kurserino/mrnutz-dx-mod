# Design

## Context

See `proposal.md` (Why) and the delta specs (requirements).

What v0.1.0 already does (`src/runtime.ts`, `docs/knowledge/mod-implementation.md`):
- ROM expanded to 2 MiB; hook code at `$A0:8000`, colour tables at `$A0:9000/$A0:9080`, OAM attribute tables at `$A0:9100/$A0:9200`. About 1 MiB of the expansion space is still free.
- Input hook at `$81:828A` (gameplay NMI path, M16/X16, DBR=`$00`) replaces `LDA $4218 / STA $1A6F` with `JSL`. Its first run after power-on sees no WRAM magic (`$5A4E` at `$7FBE00`) and initializes the state (fur `$7FBE02`, outfit `$7FBE03`). Soft reset keeps the magic, and with it the selection.
- The manifest builder already recomputes the header checksum and complement for the expanded image.

Header today (file offsets): `$7FD6` chipset = `$00` (ROM only), `$7FD8` SRAM size = `$00`.

Static scan of the original ROM for long-addressed accesses to banks `$70-$7D` found four SRAM-probe routines. None has a direct `JSL`/`JSR`/`JML` caller or an obvious pointer, so they are reached indirectly (callers are unknown) [static, unconfirmed]:

| Routine | Code (static) | Effect when the SRAM write sticks |
| --- | --- | --- |
| A `$80:83EF` | `LDA #$4E75; CMP $700034; BEQ ret; STA $700034; CMP $700034; BEQ *; RTL` | hang at `$80:8400` |
| D `$81:9D3A` | same pattern with `$5858` at `$700004` (M16) | hang at `$81:9D4B` |
| C `$81:8F53` | `LDA #$0093; STA $700000; CMP $700000; BEQ +1; RTS` | skips `RTS`, runs `$81:8F61+` (PPU/colour-math writes, unknown purpose) |
| B `$81:802B` | `STA $700000,X; CMP $700000,X; BNE clc; SEC; RTL` | returns carry set, so the caller's behaviour changes |

The other static hits in `$70-$7D` look like data decoded as code [static].

**Trace result (tasks 1.2-1.5, `docs/knowledge/protection.md`):**
- None of A-D runs in the whole game.
- Three more checks run that the static scan missed, because they build the SRAM address from constants:
  - **E** `$9C:F814`: boot and after soft reset; hangs with SRAM.
  - **F** `$82:BA10`/`$82:B9C4`: about every 15 gameplay frames; sets `$7E:054C`.
  - **G** `$81:C45C`: every gameplay frame; writes `$C07F` to `$7F:C07F`.
- With SRAM declared and the checks intact, the boot hangs (E) and Mr. Nutz vanishes from stage 0 (F/G).

## Goals / Non-Goals

**Goals:**
- Find every SRAM check with Mesen traces before patching any byte, and save the original disassembly of each.
- Make the smallest patch per check, without writing SRAM from game code.
- Use one small, validated save record that the hook owns.

**Non-Goals:**
- Pause menu or more presets (next change; the record reserves room for it).
- Real hardware or flash carts. Mesen is the only test emulator.
- Saving anything other than the colour selection.

## Decisions

### D1. Header: 2 KiB battery-backed SRAM
- Set `$FFD6` (file `$7FD6`) from `$00` to `$02` (ROM + RAM + battery).
- Set `$FFD8` (file `$7FD8`) from `$00` to `$01` (2 KiB).
- In LoROM, SRAM maps at `$70-$7D:0000-$7FFF`; the code uses bank `$70` only.
- *Alternative:* 8 KiB or more. Rejected: 2 KiB is the minimum and is more than enough for this change and the menu.
- *Rollback:* restore both bytes.

### D2. Neutralize each check by reproducing its "no SRAM" path without touching SRAM
Register widths and outcomes come from `probe-regs-stage.log` / `probe-regs-boot.log` and `trace-sram-all.log`.

Checks that run (all patched so that they never access bank `$70`):

| Check | Site | Original | Replacement | Why it is equivalent |
| --- | --- | --- | --- | --- |
| E | `$9C:F819` (M16/X16) | `CF 00 00 70` (`CMP $700000`) | `80 15` (`BRA $9C:F830`) + 2 unchanged bytes | Without SRAM the test always ends at `$F830`, whose `LDA #$00B4` overwrites A and flags. The skipped `JSR $F82F` is a bare `RTS`. |
| F | `$82:BA22` (M16/X8) | `B7 10 D9 89` | `A0 02 80 08` (`LDY #$02; BRA $82:BA2E`) | Without SRAM the pre-check fails, the write test fails, and execution reaches `$BA2E` with Y=2, X=2 and A reloaded by `LDA [$3F]`; `$054A,Y` stays unwritten. |
| G | `$81:C45C` (M16/X16) | 18 bytes `$C45C-$C46D` | `LDA #$7070; STA $12; LDA $1C; CLC; ADC #$000F; TAX; LDY #$AF05; TYA; BRA $81:C484` | Without SRAM: `$12` = open-bus `$7070`, X = `$1C+$0F`, Y = A = `$AF05`, then `BNE $C484`, where `LDA #$0170; TCD` takes over. |

Checks never reached (A-D): defensive, width-independent patches, so that an untraced path can never hang or sabotage:

| Check | Site | Original | Replacement |
| --- | --- | --- | --- |
| A | `$80:8400` | `F0 FE` (`BEQ *`) | `EA EA` |
| D | `$81:9D4B` | `F0 FE` (`BEQ *`) | `EA EA` |
| C | `$81:8F5E` | `F0 01` | `EA EA` (always `RTS`) |
| B | `$81:8035` | `38` (`SEC`) | `18` (`CLC`, "no SRAM") |

If one of A-D is ever reached, it can still write its own magic bytes (`$70:0000`, `$0004`, `$0034`, `$0000+X`). The save-memory spec allows writes by original checks, and none of these overlap the record.

*Alternative 1:* `RTL`/`RTS` at the entry of each routine. Rejected:
- E, F and G are inline code, not routines.
- For A-D the entry width is unknown (never traced), so an `LDA #imm` replacement could be mis-decoded.

*Alternative 2:* Pre-seed SRAM with the magic values (`$4F4B` at `$0000`, the `$B589` table at `$0345`, `$AF05` at `$00A9`) so the pre-checks pass. Rejected:
- the game would depend on save-file content;
- a fresh or corrupted `.srm` would trigger the protection again.

Each entry goes in the manifest with original bytes, replacement, reason and the trace log as evidence.

### D3. Save record at `$70:0100`
The record is 8 bytes, away from every address the checks use (E `$0000-0001`, F `$0345-0348`, G `$00A9-00AA`, A `$0034`, D `$0004`, C `$0000`, B `$0000+X`; B is never reached, so its X range is unknown):

| Offset | Size | Field |
| --- | --- | --- |
| +0 | 2 | magic `$5A4E` ("NZ") |
| +2 | 1 | version `$01` |
| +3 | 1 | fur index |
| +4 | 1 | outfit index |
| +5 | 1 | reserved `$00` (pause-menu flags later) |
| +6 | 2 | checksum = `$FFFF` XOR (16-bit sum of the words at +0, +2, +4) |

*Alternative:* store raw indices only. Rejected: emulators may fill new SRAM with `$00` or `$FF`, and a stale record from a future version must be rejected.

### D4. Load on first hook run, save on change
- **Load:** in the existing one-time WRAM init (magic absent), read the record. If it is valid, copy each index after checking it against the preset counts (out-of-range → 0). Otherwise start at 0/0, as v0.1.0 does.
- **No reload on soft reset:** WRAM keeps the magic, so the record is not read again.
- **Save:** right after a shortcut changes an index, write the payload and then the checksum, with long addressing from the NMI hook. The cost is a few cycles, once per press. The colour upload path is unchanged.

*Alternative:* save on pause or stage change. Rejected: power-off right after a change would lose it.

### D5. Evidence and tests
- **New `tools/mesen/trace-sram.lua`:**
  - logs exec of A/B/C/D with caller (stack return address), A/X/Y/P;
  - logs every CPU read and write to `$70-$7D`;
  - logs from power-on through the full-game stage states.
  - Runs on the **original ROM** and on a **header-only** variant (SRAM declared, no neutralization), to see what each check really does when SRAM exists.
  - Output goes to `docs/traces/trace-sram.log`.
- **`sweep:all`:** runs with SRAM declared and adds an audit that SRAM writes stay inside the record.
- **Persistence check, extended with a power cycle:**
  - pick a colour, write the `.srm`, hard reset with the `.srm` kept, and check the colour;
  - fresh, corrupt and out-of-range record cases.
- **Unit tests:** manifest scope (header bytes, check patches, nothing else outside the expansion), record checksum, assembled code width (M/X).

## Risks / Trade-offs

- **[More checks reached indirectly than the ones found]** → This already happened: E, F and G were missed by the static scan. The trace covers boot, every stage, bosses, credits, death, game over/continue and soft reset (`trace-sram-all.log`). The final build is re-traced with SRAM present (task 2.3); any `$70` access outside the record fails the audit.
- **[Second-level protection, e.g. a checksum over the check routines]** → Watch CPU reads of the patched byte ranges during the trace. A data read of those bytes means another check exists.
- **[Caller depends on A/flags/carry from a check]** → D2 picks return values per caller from the trace. If unclear, fall back to NOP-ing the branch.
- **[Emulator SRAM initial content is random]** → magic + version + checksum, and index range check.
- **[`.srm` written only when the emulator closes]** → This is emulator behaviour. Document that the save is persisted when Mesen closes or flushes, as for any SRAM game.
- **[Savestates from v0.1.0 carry the old header/WRAM layout]** → Release notes: start fresh. The WRAM state is unchanged, so old states still load.

## Migration Plan

1. Build a new runtime IPS (2 MiB, same expansion layout, plus the header and check entries).
2. The first boot with no `.srm` behaves exactly like v0.1.0.
3. **Rollback:** apply the v0.1.0 IPS to a clean ROM. Its header declares no SRAM, so the emulator ignores the `.srm`. Every new manifest entry lists its original bytes, so the byte-level rollback is in `output/runtime-report.json`.

## Open Questions

- How Mesen names and flushes `.srm` with IPS soft-patching versus a pre-patched ROM. This only affects documentation.
