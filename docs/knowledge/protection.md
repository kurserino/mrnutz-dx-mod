# SRAM anti-copier protection

The original cartridge has no SRAM. Several routines write to `$70:xxxx` and read it back: if the write "sticks", the
game concludes it runs on a copier and hangs or sabotages itself. Our patch declares SRAM for the save, so every check
is neutralized (`mod-implementation.md` → "Save").

Evidence:
- `docs/traces/static-sram-checks.txt` [static];
- `trace-sram-all.log`: original ROM, 47 runs (boot, 40 stages, 2 soft resets, 4 game overs) [trace];
- `trace-sram-header.log`: the same sweep on a ROM with SRAM declared and the checks intact [trace];
- `trace-sram-patched.log`: the patched ROM, with no game writes to SRAM [trace].

| Id | Where | What it does | Runs in the original? | With SRAM present |
| --- | --- | --- | --- | --- |
| E | `$9C:F814` (M16/X16) | `$4F4B` to `$70:0000`; if the write sticks, endless `INC A` / `STA` loop | yes, at boot and after soft reset | **boot hangs** (frame 100, loop `$9C:F81F-F82D`, 0 gameplay frames) |
| F | pre-check `$82:BA10` + test `$82:B9C4` (M16/X8) | pointer `$70:0345` built from constants (`$B065`, `$B27D+$B27F`); compares 2 words with the table at `$82:B589`; if different, tests the write without destroying the content | yes, about every 15 gameplay frames | writes `$0052` to `$7E:054C` (`STA $054A,Y`, Y=2) |
| G | `$81:C45C` (M16/X16) | pointer `[$1A]` = `$70:00A9`; compares with `$AF05` (`$80:BE3F`) | yes, every gameplay frame | writes `$C07F` to `$7F:C07F` every frame |
| A | `$80:83EF` | `$4E75` to `$70:0034`, `BEQ *` at `$80:8400` | **never** called in any run | never called |
| B | `$81:802B` | probe `STA/CMP $700000,X`, returns carry | never | never |
| C | `$81:8F53` | `$0093` to `$70:0000`; if it sticks, skips the `RTS` and falls into an HDMA/colour-math setup (`$81:8F61`) | never | never |
| D | `$81:9D3A` | `$5858` to `$70:0004`, `BEQ *` at `$81:9D4B` | never | never |

All "runs?" and "with SRAM" cells are [trace]; the descriptions of what each routine does are [static].

- **Visible effect of F/G with SRAM:** Mr. Nutz vanishes in `stage-00` (compared with the original ROM) [trace]. It is
  not isolated whether F, G or both cause it.
- **Side effect with SRAM:** only in that variant, code at `$81:C01C` and `$81:C045` reads bytes of routines A and B in
  `stage-04`. Probably a pointer corrupted by G reading garbage [hypothesis]. No second-level check was found: in the
  original ROM nothing reads those bytes as data [trace].
- **Indirect calls:** none of the routines has a direct `JSL`/`JSR`/`JML` caller. E and F build the SRAM address from
  scattered constants, so a static scan for `$70` does not find them. Only the trace found E, F and G.
- **Pre-checks:** E passes straight through if `$70:0000` already holds `$4F4B`, and F if `$70:0345` already holds the
  `$B589` table. With fresh SRAM both fire.

## Neutralization (in the patch manifest)

| Check | Site | Original | Replacement | Why it is equivalent |
| --- | --- | --- | --- | --- |
| E | `$9C:F819` | `CF 00` | `80 15` (`BRA $9C:F830`) | without SRAM the test always ends at `$F830`, whose `LDA #$00B4` overwrites A and flags |
| F | `$82:BA22` (M16/X8) | `B7 10 D9 89` | `A0 02 80 08` (`LDY #$02 / BRA $82:BA2E`) | same exit as the no-SRAM path (Y=X=2, A reloaded by `LDA [$3F]`) |
| G | `$81:C45C` (M16/X16) | 18 bytes | `LDA #$7070 / STA $12 / LDA $1C / CLC / ADC #$000F / TAX / LDY #$AF05 / TYA / BRA $81:C484` | reproduces the no-SRAM mismatch path |
| A | `$80:8400` | `F0 FE` | `EA EA` | defensive (never reached) |
| D | `$81:9D4B` | `F0 FE` | `EA EA` | defensive |
| C | `$81:8F5E` | `F0 01` | `EA EA` (always `RTS`) | defensive |
| B | `$81:8035` | `38` (`SEC`) | `18` (`CLC`) | defensive |

Register widths at E/F/G come from `probe-regs-boot.log` and `probe-regs-stage.log`. Source of truth:
`SRAM_CHECK_PATCHES` in `src/runtime.ts`; required behaviour: `openspec/specs/save-memory/spec.md`.
