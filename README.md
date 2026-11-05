# Mr. Nutz DX Mod

A TypeScript + OpenSpec + Claude Code project for studying and modifying the SNES **Mr. Nutz (USA) (En,Fr)** palette and building **IPS** patches, including an in-game runtime palette switch.

**No ROM is included.** You must supply your own legally obtained copy and place it in `roms/` (git-ignored). Never commit or redistribute ROM files or patched ROMs; only IPS patches are meant to be shared.

Expected source ROM (`roms/Mr. Nutz (USA) (En,Fr).sfc`, headerless):

| Field | Value |
| --- | --- |
| Size | 1,048,576 bytes (1 MiB) |
| CRC32 | `A99BDD9A` |
| SHA-256 | `3472dd574b50aed2fa998f464398db4fbb00f5a300a672c3737ee9336a008a16` |

The tools refuse to patch any other ROM.

## Status

- **Working**: strict ROM verification, BGR555 conversion, recoloring the established `C6-C9` outfit and `CB-CF` fur palette entries, IPS patch build, patched `.sfc`, and verification report.
- **Runtime switch**: `Select+L`/`Select+R` hook implemented; automated Mesen 2 sweep covers every stage, bosses, credits, pause and soft reset, with selection persistence. A manual Mesen GUI regression pass is still pending before the OpenSpec change is archived (`docs/runtime-hook.md`).
- **Not done**: in-game palette menu. Do not claim one exists.

## Requirements

Node.js 20.12+ (for `process.loadEnvFile`), npm, OpenSpec CLI, Claude Code, and Mesen 2 for emulator debugging and testing.

## Quick start

```bash
npm install
npm run rom:inspect
npm run palette:show
npm run rom:header
npm run rom:disasm -- '$9D:AC7E' 3A   # static 65C816 disassembly (lowercase m/x = 8-bit)
npm run patch:build
npm test
npm run typecheck
```

Generated files live in `output/`: `Mr. Nutz.ips`, `Mr. Nutz.patched.sfc`, and `patch-report.json`.

To use another preset:

```bash
npm run patch:build -- --preset presets/pink-fur-yellow-outfit.json
```

Place `Mr. Nutz.ips` alongside an original ROM named `Mr. Nutz.sfc` if your emulator supports IPS soft-patching; alternatively load the generated `Mr. Nutz.patched.sfc` directly.

## Runtime palette switch (in game)

`npm run runtime:build` writes `output/Mr. Nutz.runtime.ips` (2 MiB expanded LoROM) plus a local test ROM and `runtime-report.json`. In game: `Select+L` cycles fur, `Select+R` cycles outfit (presets in `presets/runtime.json`, index 0 = original). Details, evidence and open gaps: `docs/runtime-hook.md`.

Mesen 2 automation (headless `--testRunner`, Lua): copy `.env.example` to `.env`, set `MESEN_PATH`, then:

```bash
npm run sweep:prepare    # once: one savestate per stage from roms/states/level1-start.mss (original ROM)
npm run sweep:all        # regression: every stage in parallel + persistence, ~35 s, exit 1 on any violation
npm run sweep:stage -- 14,15   # only some stages
npm run verify:runtime   # power-on path smoke test (~12 s)
npm run trace:palette    # evidence traces on the original ROM (palette DMA, E4 sweep), trace:hook, trace:wram
npm run research:sweep   # slow single-run sweep kept for its investigation modes
```

Text logs go to `docs/traces/`; screenshots to `output/traces/` (private).

## Claude + OpenSpec workflow

1. Open this folder in your terminal and run `claude`.
2. Read `CLAUDE.md`, `docs/rom-map.md`, and `openspec/specs/`.
3. Run `openspec init --tools claude` to install or refresh **the current OpenSpec Claude skills and commands**. The project already includes its config, base specs, and a proposed future change; init must not remove them.
4. Review the active change in `openspec/changes/runtime-palette-switch/` (implemented; final manual verification pending).
5. Ask Claude to use the OpenSpec workflow (`/opsx:apply` or available installed OpenSpec command; check installed commands first).
6. Require an IPS build + verification after every implementation change.

## Safety rules

- Never commit ROMs, patched ROMs, or savestates (`roms/` and `output/` are git-ignored).
- Work from a copy of this specific ROM only; never mutate the source file.
- Do not patch arbitrary ROM versions. The original palette bytes and ROM length must match.
- Code/variables/comments are in English; documentation in Portuguese.
- `openspec/specs/` holds accepted behavior; `openspec/changes/` holds unimplemented work.
- Every low-level ROM hook must be backed by Mesen traces and an actual smoke test.

## Legal

Mr. Nutz is a trademark of its respective owners. This is an unofficial fan project, not affiliated with or endorsed by them. It contains no game data; it only produces patches to be applied to a ROM you own.
