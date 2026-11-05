# Tasks

## 0. Static analysis (no emulator required)
- [x] 0.1 Add LoROM mapping, header parser, and 65C816 static disassembler with tests (`src/snes.ts`).
- [x] 0.2 Document palette loader, pointer tables, joypad mirror, NMI dispatch, and free-space scan (`docs/static-analysis.md`).
- [x] 0.3 Write the Mesen evidence request (`docs/mesen-evidence-request.md`).

## 1. Reverse engineering (Mesen 2.2.1 headless, `tools/mesen/`, logs in `docs/traces/`)
- [x] 1.1 Capture input polling routine, register/stack state, and original bytes (`trace-hook-site.log`).
- [x] 1.2 Capture palette reload sites: scene init DMA `$9DACB3` only, across the whole game (`trace-palette.log`, `sweep-all.log`); the Nutz slot varies per scene table (`sweep-debug10.log`).
- [x] 1.3 Confirm color-to-pixel assignment for fur, outfit, eyes (E4 sweep, idle pose, level 1).
- [x] 1.4 Locate free space: ROM expansion to 2 MiB; WRAM state at `$7FBE00` inside `$7FB6C0-$7FBFFF`, untouched across the whole game, credits, reset and boot (`sweep-wram.log`).

## 2. Hook implementation
- [x] 2.1 Reproducible build on Windows: in-repo 65C816 assembler (`src/asm.ts`) with round-trip tests; no external tool.
- [x] 2.2 Input-edge detection for fur/outfit cycling (`Select+L`, `Select+R`), original controls preserved.
- [x] 2.3 Preset state and color lookup, including original palette at index 0 (`src/runtime.ts`, `presets/runtime.json`).
- [x] 2.4 VBlank-guarded CGRAM application, registers/flags preserved; private Nutz palette slot via OAM remap so objects sharing `$85:9CC0` keep their colours (`sweep-all.log`: sharedChanged=0, foreignOnX=0).
- [x] 2.5 Document all hooks and new ROM regions in the byte manifest (`docs/runtime-hook.md`).

## 3. IPS and verification
- [x] 3.1 Extend builder to accept verified hook/code bytes with strict expected originals (`src/manifest.ts`).
- [x] 3.2 Test IPS encoder/decoder, ROM expansion, and ROM identity safeguards with hook manifest.
- [x] 3.6 Fast regression: per-stage savestates + parallel `sweep:all` (~35 s) with oracle for shared palette, private slot, HDMA timing, shortcuts and persistence.
- [ ] 3.3 Verify on Mesen 2 — automated: standing, running, jumping, cycling, wrap, hold debounce, stage transitions, hanging/rolling in pipes, swimming in blue water incl. death and color change underwater (`verify-runtime.log`, `probe-warp.log`, `probe-swim.log`, `swim-blue-35.log`, `swim-blue-37.log`). Full-game sweep (`sweep-all.log`): every stage, bosses, credits, pause and soft reset (selection persists); fixed per-scene palette slot. Open: manual Mesen GUI run. Selection persists across world changes and soft reset (state moved to `$7FBE00`); non-gameplay screens keep original colors.
- [ ] 3.5 Update baseline OpenSpec specs and documentation only after passing emulator tests.

## 4. Release
- [x] 4.1 Generate IPS, patched ROM for local test, byte-level report and changelog (`npm run runtime:build`, `output/runtime-report.json`, `CHANGELOG.md`).
- [ ] 4.2 Archive this OpenSpec change only after every acceptance check passes.
