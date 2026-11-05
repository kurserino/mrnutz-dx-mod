# Research and test tools

Mesen 2 (2.2.1) is the only test emulator. Everything below runs it headless, with Lua scripts.

## Setup

- Copy `.env.example` to `.env` and set `MESEN_PATH` (and `ROM_PATH` if the ROM is not in `roms/`).
- `tools/mesen/run.ts` runs `Mesen --testRunner --timeout=3600 <rom> <script>`. Without `--timeout`, 2.2.1 kills
  scripts after about 2 minutes (exit -1). It prepends `tools/mesen/lib.lua` to every script, because Lua `require`
  needs an I/O permission that stays off.
- Output protocol (stdout): `SHOT <tag> <hex png>` → `output/traces/<name>/<tag>.png`; `STATE <name> <hex mss>` →
  `output/states/<name>.mss`; anything else → `docs/traces/<name>.log` (no ROM data, no local paths).
- `run.ts` options: `--rom`, `--name`, `--state <file.mss>` (loaded at the reset vector `$00:80B5`), `--define NAME=N`
  (injected as Lua globals).
- `lib.lua` helpers:
  - memory: `w8/w16/ww` (WRAM), `bus8/bus16` (CPU bus), `cg` (CGRAM entry), `oam`;
  - `FRAME`, `inGameplay()` (the `$81:828A` mirror ran this frame and `$01DC=$835B`), `shot`, `playInputs`,
    `loadStateOnBoot`;
  - the palette oracle `nutzOracle()` and `nutzSlot()`.
- `loadStateOnBoot` clears our SRAM record after loading a state: stage states come from the original ROM, and parallel
  runs share one `.srm` in Mesen's `Saves` folder.
- Mesen keeps battery saves in `<Mesen dir>/Saves/<rom name>.srm`. A new process is a real power-on.
- Stage states: `npm run sweep:prepare` builds `output/states/stage-00..39.mss` once from `roms/states/level1-start.mss`
  (a level 1 savestate made on the original ROM), using the debug stage skip. They do not depend on the patch build.
  `stage-36` is the last playable stage; `stage-39` is the credits scene.

## Commands

| Command | What it does | Time | Output |
| --- | --- | --- | --- |
| `npm run rom:inspect` / `rom:header` | ROM identity and header | instant | stdout |
| `npm run rom:disasm -- '$BB:AAAA' <len-hex> [--m16] [--x16]` | linear static disassembly; lowercase m/x = 8-bit | instant | stdout |
| `npm run runtime:build` | builds the runtime IPS, test ROM and report | instant | `output/` |
| `npm run sweep:all` | regression: every stage state in parallel (`stage-check.lua`, `flicker-check.lua`), persistence (`persist-check.lua`) and power cycle (`power-cycle.ts`); exit 1 on any violation | 1-2 min | `sweep-all.log` |
| `npm run sweep:stage -- 14,15` | only some stages | seconds | `sweep-all.log` |
| `npm run verify:runtime` | power-on path smoke test: shortcuts, wrap, persistence | ~12 s | `verify-runtime.log` |
| `npm run check:power` | SRAM save across real power-ons: fresh, restore + 10 stage skips into the next world, corrupted, out of range | ~1 min | `power-cycle.log` |
| `npm run check:ending` | last stage → credits → final screen → soft reset → new game | ~1 min | `ending-check.log` |
| `npm run trace:sram` / `trace:sram:all [--rom f] [--light]` | SRAM accesses, check-routine calls, "SRAM detected" branches, stalls, over the whole game | ~2 min | `trace-sram*.log` |
| `npm run survey:space` | per stage: WRAM/CGRAM/OAM blocks touched, VRAM referenced, PPU layout, pause behaviour | ~30 s | `space-survey.log` |
| `npm run probe:pause` | pause flag candidates, PCs and NMI work while paused | seconds | `pause-probe.log` |
| `npm run probe:options` | WRAM diffs around each press in OPTION MODE | seconds | `options-probe.log` |
| `npm run trace:palette` / `trace:hook` / `trace:wram` | original evidence for the palette hook (palette DMA, hook site state, untouched WRAM) | minutes | `trace-*.log` |
| `npm run research:sweep` | slow single-run whole-game sweep, kept for its investigation modes | long | `research-sweep.log` |

Scripts without an npm alias (run with `npx tsx tools/mesen/run.ts <script> [--state …] [--define …] [--name …]`):

| Script | Use |
| --- | --- |
| `find-lives.lua` | full 128 KiB WRAM snapshots at chosen frames; filters by "stable inside each life, same step between lives" |
| `poke-check.lua` | writes (or holds, `HOLD=1`) one WRAM byte and screenshots the HUD; `ADDR`, `VALUE`, `END` |
| `watch-writes.lua` | every write to one address with PC and value |
| `options-writes.lua` | every WRAM write after an A press on an OPTION MODE row (`ROW=0..4`) |
| `probe-regs.lua` | CPU state (P, widths, D, DBR) at given exec addresses — run before writing patch bytes |
| `boot-timeline.lua` | screenshots every N frames from power-on |
| `probe-api.lua` | lists Mesen Lua functions, memory types, counter types and PPU state keys |

## Methods that worked

- **Find who writes an address:** `watch-writes.lua`, then `rom:disasm` at the PC. This is how the obfuscated lives
  routine was found.
- **Find a counter whose encoding is unknown:** compare full-WRAM snapshots taken inside several "states" (lives x2, x1,
  x0) and keep the bytes that are stable inside each state and change by the same step between states.
- **Find a settings byte:** log every write in the frames after the press, compare two presses of the same row (the
  value changes, scratch writes repeat), and look for a byte that steps 0 → 1 → 2.
- **Find hidden code paths:** exec/read/write callbacks over the whole game (`trace-sram-all.ts`) instead of a static
  scan. The static scan for `$70` found 4 anti-copier checks that never run and missed the 3 that do.
- **VRAM usage:** Mesen's access counters do not see PPU reads, so mark what the tilemaps, their tiles and visible
  sprites reference (`space-survey.lua`).
- **Separate tool artefacts from real behaviour:** run the same script on the original ROM (for example
  `ending-check-original.log`, stall baselines in `trace-sram-all.log`).
- **Fast game over:** zero the lives (`game-state.md`).

## Methods that failed (do not repeat)

- Searching lives by the displayed value (obfuscated).
- WRAM diffs limited to `$0000-$1FFF` (the options are in `$7F:B0xx`).
- Diffing the options screen without excluding the animation/scratch ranges (hundreds of false changes).
- Taking the Mr. Nutz colour check on the first gameplay frames after a stage change: the hook needs a full OAM pass
  first. Wait for 120 frames of continuous gameplay.
- Treating "end-of-frame PC in one window" as a hang without a baseline: the game has several legitimate wait loops
  (`frame-cycle.md`).
- Heavy Lua callbacks on a tight loop (check E with SRAM present): Mesen crawls. Use `--light` or self-removing
  callbacks.

## Mesen GUI (manual checks)

- `Debug > Sprite Viewer`: OAM palette per sprite. `Debug > Palette Viewer`: CGRAM `$C0-$CF`.
- `Debug > Memory Viewer`, type `CGRAM`: use **Go To Address** (`0180`), not Find. CGRAM is 2 bytes per entry, BGR555
  little-endian. A changed colour may not show until emulation resumes.
- Palette loading: write breakpoint on CGRAM `$0182-$0183`; check `$4300-$4306` and `$420B` for the DMA source. Do not
  infer the source from the PC alone.
- Every patch: play stage 1 (standing, walking, jumping, hurt, area change), check that other sprites sharing the
  palette keep their colours, and that gameplay, HUD, items, music and transitions are unchanged.

## Open questions

- Do the native options (`$7F:B008-$B00C`) take effect when changed during gameplay?
- MUSIC MODE value 1 and CONTROL PAD value 1 (not captured on screen).
- What `$7E:054C` (set by check F) and `$7E:188B` control.
- The black-screen loop at `$8A:81E2` after writing energy outside gameplay.
- Sound driver (SPC700): how to control BGM and SFX volume separately.
- Pause-menu hook `$80:83B8`: register widths and VBlank time available.
