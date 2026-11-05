# Agent instructions — Mr. Nutz DX Mod

Single source of rules for every coding agent working on this repository (Codex reads this file; Claude Code reads it
through `CLAUDE.md`). This is a spec-driven SNES ROM hacking project: TypeScript tooling, OpenSpec specs, IPS patches
for **Mr. Nutz (USA) (En,Fr)**.

## Language

**Everything in this repository is written in English**: code, identifiers, comments, test names, specs (including
`## Purpose`), OpenSpec proposals/designs/tasks, docs and the knowledge base, README, CHANGELOG, agent files and commit
messages. Only the conversation with the user may be in Portuguese. Archived changes and trace logs are history and
are not rewritten.

## Start here

1. `docs/knowledge/README.md`: everything known about how the game works (memory map, frame cycle, palettes, game
   state, protection, our implementation, research tools). **Do not re-derive a fact that is already there.** Record
   new facts there, with an evidence tag and a log.
2. `openspec/specs/`: what the mod must do.
3. `openspec/changes/`: active work (proposal, design, tasks). Finished changes are in `openspec/changes/archive/`.
4. `openspec/config.yaml`: project context and artifact rules.

## Contract

- **OpenSpec for every feature**, including small ROM-level changes: proposal → delta specs + design → tasks → apply →
  validate → archive. Do not archive unfinished runtime work. Knowledge (how the game works) goes in
  `docs/knowledge/`; behaviour (what the mod must do) goes in specs. Link, do not repeat.
- **The ROM is a private input.** Never commit or redistribute ROMs, patched ROMs, savestates or `.srm` files (`roms/`
  and `output/` are git-ignored). Only IPS patches are shared.
- **Never modify the source ROM.** Validate the original ROM size, exact original palette bytes and the generated patch
  scope. Never silently change unrelated graphics or gameplay.
- **Evidence before bytes.** Label facts `[trace]`, `[byte]`, `[static]`, `[hypothesis]` or `[public]`; hypotheses are
  not facts. For new in-game code, save the original disassembly and register traces (widths, DBR, D, timing) before
  writing patch bytes.
- **Mesen 2 is the only test emulator.** Runtime features are complete only after the headless Mesen regression
  (`npm run sweep:all`) passes and, before a release, a manual check in the Mesen GUI.
- **Hardware rules:** respect 65C816 widths (M/X), LoROM mapping, the CPU bus vs. CGRAM/VRAM/OAM separation, DMA/HDMA
  timing and VBlank budget, little-endian BGR555 colours. CGRAM entry 0 of a sprite palette (`$C0` for Mr. Nutz) is
  transparent: never recolour it.
- **Static palette patch scope:** `npm run patch:build` only changes the 32-byte palette at file offset `0x029CC0`.
  Everything else goes through the runtime manifest in `src/runtime.ts`, with expected original bytes, a reason and
  evidence per entry.
- **Required checks before claiming completion:** `npm test && npm run typecheck && npm run patch:build`, plus
  `npm run runtime:build` and `npm run sweep:all` when runtime code or the manifest changed.
- **Git:** commit, push, tag or publish releases only when the user asks.

## Useful commands

```bash
npm run rom:inspect              # ROM identity and palette signature
npm run rom:disasm -- '$81:828A' 20 --m16 --x16
npm run patch:build              # static palette IPS
npm run runtime:build            # runtime IPS (in-game switch + save)
npm test && npm run typecheck
npm run sweep:all                # Mesen regression over every stage + persistence + power cycle
```

All research and test commands are described in `docs/knowledge/research-tools.md`.

## OpenSpec tooling

OpenSpec skills are installed for both agents with `openspec init --tools claude,codex` (OpenSpec 1.14.2). The files
are repo-local and versioned:

- Claude Code: `.claude/skills/openspec-*` and the `/opsx:*` slash commands in `.claude/commands/opsx/`;
- Codex: `.agents/skills/openspec-*` (skills only, no commands; start a change with `$openspec-propose "…"`).

Nothing is written to the user's global `~/.codex`. Re-run the same command after upgrading OpenSpec; it keeps
`openspec/config.yaml`, specs and changes.
