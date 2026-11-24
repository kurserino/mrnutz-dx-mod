# Tasks

## 1. Prototype in Mesen (decide the rendering before the full build)

- [x] 1.1 Find the WRAM shadows (if any) for BG3 scroll (`$2111/$2112`), colour math (`$2130-$2132`), OBJ size/base (`$2101`) and main/sub screens (`$212C/$212D`) with write-watch traces of those registers and their source operands. Record them in `docs/knowledge/frame-cycle.md` with tags. Verify each register has a known shadow, a per-scene constant, or is marked "no shadow" with the writer PC. Done: no WRAM shadows; all are constants written at scene init (BG3 VOFS `$03FF`, OBSEL `$63`, `$212C/$212D` `$17/$00`), BG3 HOFS also re-written as 0 every gameplay NMI, colour math set by per-stage constants (never on OBJ, on BG3 only in stage-26/31). Recorded in `frame-cycle.md` (`reg-writers-00/02.log`).
- [x] 1.2 Measure, from every pausable stage state, which OBJ tile ranges the frozen OAM references while paused, and pick an OBJ tile area for the swatches (D5) that no visible entry uses in any stage. If none exists, define a candidate list. Verify the result is in `docs/traces/pause-objtiles.log` and in design D5. Done: no OBJ row is free in every stage, but with all other entries hidden while open, only Mr. Nutz's tiles (always name table 0, `$000-$055`) matter; swatches go to name table 1 tiles `$100-$13F` (VRAM `$E000-$E7FF`), backed up (`pause-measure.log`, design D5 updated).
- [ ] 1.3 Build a prototype patch with the `$80:83B8` hook (D1, D2) that, while paused, backs up and replaces BG3 with a placeholder frame and shows 32 placeholder swatches and the preview copy, then restores on Start. Verify with `probe-regs.lua` that P/D/DBR at the hook match `pause-measure.log`, and that the end scanline of each open/close step is ≤ 250.
- [ ] 1.4 Run the prototype on every pausable stage state and screenshot it, including the colour-math stages (`stage-02`, `03`, `19`, `20`, `21`, `22`, `23`, `26`). Check that the transparent cells show the swatches and the preview, and that the frame covers the scene. Verify the screenshots are reviewed, and update design D4/D5 (or switch to the D4 fallback) with the outcome.
- [ ] 1.5 Verify in the prototype that open → close leaves VRAM, CGRAM and OAM byte-identical to the pause moment in every pausable stage (Mesen memory reads), and that the gameplay frames after resuming match a run without the menu. Verify the log reports 0 differences.

## 2. Data: grid colours, shades, font, layout

- [ ] 2.1 Add `presets/grid.json` (32 base colours, D8) and `src/shades.ts` (fur 5 / outfit 4 shades). Verify unit tests for monotonic luminance (dark → light), BGR555 range and deterministic bytes.
- [ ] 2.2 Draw the 8×8 2bpp font (A-Z, 0-9, symbols used by the menu) and the frame pieces as data in `src/` (original art), plus the menu string and layout tables (D9). Verify a unit test that every character used by the menu strings has a glyph and that the tiles fit in BG3 tiles `$300-$37F`.
- [ ] 2.3 Extend the expansion layout with `GRID_FUR`, `GRID_OUTFIT`, font/frame tiles, swatch tiles and menu tables. Verify a test that no two tables overlap and that everything stays inside the declared `$A0` regions.

## 3. Selection model and save v2

- [ ] 3.1 Implement the D6 value encoding in `prepare_colors` (presets vs grid tables) and in the `Select+L/R` shortcuts (grid colour → original → presets). Verify assembler width tests, and Mesen `sweep:all` with a grid value forced into WRAM showing the right shades in every stage (`nutzOracle` with the grid expectation).
- [ ] 3.2 Save record v2 (D7): `load_save` accepts v1 and v2 and validates by range; `write_save` writes v2; TS helpers updated. Verify unit tests (v1 accepted, v2 round-trip, invalid values → 0), and extend `power-cycle.ts` with a v1 record from v0.2.0 and a grid colour restored after power-off.

## 4. Menu implementation

- [ ] 4.1 Implement `pause_hook` (D1, D2) and the open/close state machine with rollback (D3), backing up into `$7F:D040+`. Add the manifest entry with the original bytes `E2 30 AD 3D 18 8D 0C 42`. Verify a unit test of the manifest bytes and of the buffer layout (≤ 12 KB), and that the Mesen open/close byte-identity check from 1.5 passes.
- [ ] 4.2 Implement the list (PAUSE, CHANGE OUTFIT, RESUME), navigation with edge detection and wrap, and Start/RESUME to resume. Verify `pause-menu-check.lua` input scenarios (held button, wrap, Start, RESUME).
- [ ] 4.3 Implement the CHANGE OUTFIT modal: tabs with L/R, 8×4 grid cursor with wrap, live preview within one frame, A applies and saves, B returns. Verify `pause-menu-check.lua` apply/cancel scenarios: after resuming, `nutzOracle` shows the applied fur and clothes, shared palettes are unchanged, and the save record holds the values.
- [ ] 4.4 Add `tools/mesen/pause-menu-check.lua` to `sweep:all` (excluding stage states that cannot pause). Verify `npm run sweep:all` reports violations=0 and the new menu checks ok in every pausable stage.

## 5. Docs and release checks

- [ ] 5.1 Update `docs/knowledge/mod-implementation.md` (pause hook, menu state, buffer layout, selection encoding, save v2), README controls and CHANGELOG (Unreleased). Verify every new address has a tag and a log.
- [ ] 5.2 Run `npm test && npm run typecheck && npm run patch:build && npm run runtime:build`. Verify the IPS replayed on the clean ROM equals the built ROM, the manifest lists only declared entries, and the static patch still validates the ROM.
- [ ] 5.3 Manual Mesen GUI check by the user: pause in several worlds, browse and apply colours, resume, power cycle. Review the grid colours on screen (design Open Question). Record the outcome here.

## Workflow follow-up

- Sync specs (`pause-menu` new, `runtime-palette-switch` and `save-memory` updated) and archive after every check passes.
- Release v0.3.0 with the new IPS.
