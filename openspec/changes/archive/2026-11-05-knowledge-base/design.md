# Design

## Context

See `proposal.md`. Current sources of knowledge (2026-11-04):
- `docs/rom-map.md`, `docs/static-analysis.md`, `docs/runtime-hook.md` (224 lines, with dated "replaces the flow above" sections), `docs/ram-map.md`, `docs/expansion-budget.md`, `docs/debugging-playbook.md`, `docs/mesen-evidence-request.md`, `docs/architecture.md` (partly outdated: it says 65C816 code would go in `asm/`, but the code is in `src/asm.ts` + `src/runtime.ts`).
- Agent rules: `CLAUDE.md` (Claude-only today), `AGENTS.md` (3 lines), `openspec/config.yaml` context.
- Evidence: 68 logs in `docs/traces/`, referenced by name from the docs.
- `.claude/` holds the OpenSpec skills and commands for Claude. Codex has nothing.

## Goals / Non-Goals

**Goals:**
- One place per fact, written in English. Per the user's decision, everything in the repository is English; only the conversation with the user may be Portuguese.
- Both agents load the same rules from `AGENTS.md`.
- Before any research, a new session can answer: "what is at address X?", "what runs in NMI when paused?", "where can new code/RAM go?", "which tool reproduces this?".

**Non-Goals:**
- Rewriting OpenSpec main specs, changing code, tools or patch bytes.
- Moving or renaming trace logs (docs reference them by path).
- Translating logs.

## Decisions

### D1. Layout of `docs/knowledge/`

| File | Content (moved from) |
| --- | --- |
| `README.md` | index, evidence labels, "how to add a fact" |
| `memory-map.md` | ROM layout and LoROM mapping, our expansion regions, WRAM free/used regions, VRAM layout, CGRAM, SRAM record (from `rom-map.md`, `expansion-budget.md`, `runtime-hook.md`) |
| `frame-cycle.md` | NMI vector `$01DC`, gameplay vs. paused NMI paths, joypad mirror, OAM DMA, HDMA enable timing, VBlank budget (from `static-analysis.md`, `runtime-hook.md` v3, `expansion-budget.md`) |
| `palettes.md` | character palette `$85:9CC0`, scene palette table `[$055E]`, slots and colour-math groups, private slot technique, no-slot scenes (from `rom-map.md`, `runtime-hook.md`) |
| `game-state.md` | lives (obfuscated), energy, public PAR addresses, native options `$7F:B008-$B00C`, pause flag, debug stage skip `$1EC9` (from `ram-map.md`) |
| `protection.md` | anti-copier checks A-G, effects, neutralization reference (from `static-analysis.md`) |
| `research-tools.md` | Mesen headless runner, each `npm run` probe/trace/sweep and when to use it, RAM search methods that worked (and the ones that failed), savestates (from `debugging-playbook.md`, `mesen-evidence-request.md`, README) |
| `mod-implementation.md` | how our patch is built: manifest, assembler, hooks and their sites, state layout. Points to OpenSpec specs for required behavior (from `runtime-hook.md`, `architecture.md`) |

*Alternative:* one big `KNOWLEDGE.md`. Rejected: it would be too large to load whole, and agents read files on demand.

### D2. Old files

- When fully absorbed, delete the file and fix every link (`git grep`).
- `runtime-hook.md` keeps only what is mod-specific and moves into `mod-implementation.md`. Its dated sections are folded into the current behaviour. History stays in git, the archived change and `CHANGELOG.md`.
- `mesen-evidence-request.md` is obsolete (all items are answered by traces). Its still-open items move to `research-tools.md` → "Open questions".

### D3. Agent files

- **`AGENTS.md`** (English, since agents read it as instructions):
  - the contract from today's `CLAUDE.md`, minus outdated lines (for example "the entrypoint of the runtime DMA is not yet a validated safe hook");
  - the required checks;
  - the Mesen-only rule;
  - a "Start here" list: `docs/knowledge/README.md`, `openspec/specs/`, active changes.
- **`CLAUDE.md`:** `@AGENTS.md` plus only Claude-specific notes, such as OpenSpec skills under `.claude/`. Claude Code supports `@path` imports.
- **`openspec/config.yaml` context:** replace the list of docs with `docs/knowledge/README.md`.

### D4. OpenSpec for Codex

- Run `openspec init --tools claude,codex` (1.14.2) and inspect what it writes.
- Commit only repo-local files. If it writes into the user's global Codex folder, document that in `AGENTS.md` instead of committing it.
- Existing config, specs, changes and the archive must stay untouched: verify with `git status` before committing.

### D6. English everywhere

- The rule goes into `AGENTS.md` (contract, first lines), `openspec/config.yaml` (context and a `rules` entry for every artifact) and the README safety rules, so Claude, Codex and the OpenSpec instructions all see it.
- Existing Portuguese text is translated when it is touched by this change: all of `docs/` (it moves into `docs/knowledge/` in English) and the five `## Purpose` lines in `openspec/specs/`, plus the `save-memory` delta purpose in the active `sram-persistence` change.
- **Not translated:** archived changes and trace logs, which are history. Evidence tags become English: `[trace]`, `[byte]`, `[static]`, `[hypothesis]`, `[public]`.
- *Alternative:* keep Portuguese docs and English specs. Rejected by the user.

### D5. Fact format

Each fact is one line or one table row: address or routine, meaning, evidence label, log or command. Facts that were wrong earlier are kept only when a reader could fall into the same trap (for example "`$7E:1071` is not lives"), under "Armadilhas".

## Risks / Trade-offs

- **[Losing a fact while moving]** → Before deleting an old doc, grep every address (`\$[0-9A-F]{2}:[0-9A-F]{4}`, `\$7[EF][0-9A-F]{4}`) from it and check it appears in the new files.
- **[Broken links in specs, changes and README]** → `git grep` for each removed path. The archive is history: links inside `openspec/changes/archive/` stay as they are.
- **[`@AGENTS.md` import not honoured by some Claude surface]** → keep the critical rules short and in `AGENTS.md`. `CLAUDE.md` also names the file in plain text, so a reader without import support still finds it.
- **[OpenSpec init overwriting customized skills]** → run it, diff `.claude/`, and revert unrelated changes.

## Migration Plan

Docs only. Rollback = revert the commit. Checks: `npm test && npm run typecheck && npm run patch:build` stay green, and `openspec validate --specs --strict` passes.
