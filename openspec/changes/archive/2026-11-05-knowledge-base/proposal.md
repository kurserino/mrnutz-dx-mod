# Proposal

## Why

What we know about Mr. Nutz is spread over `CLAUDE.md`, `README.md`, eight files in `docs/` (several with dated "correction" sections), the archived change and the trace logs. The user will work with both Claude Code and Codex. Today `AGENTS.md` only says "read CLAUDE.md", so every new session (or the other agent) re-derives addresses and rules. The pause menu, options and cheats are next, and they depend on this knowledge (pause NMI, options block, VRAM budget, protections).

This is **neither a palette pipeline nor a runtime ROM change**: it reorganizes documentation and agent setup only. No patch byte changes.

## What Changes

- **`AGENTS.md` becomes the single agent instruction file**, read by Codex: the project contract (ROM privacy, evidence labels, OpenSpec flow, required checks, Mesen-only testing), where to find things, and the "never re-derive" rule.
- **`CLAUDE.md` shrinks to `@AGENTS.md`** plus Claude-only notes, so nothing is written twice.
- **New `docs/knowledge/`**, an index plus one topic per file, holding everything known about how the game works:
  - memory map (ROM/WRAM/VRAM/CGRAM/SRAM);
  - frame cycle (NMI paths, input, DMA, VBlank budget);
  - scene palette tables and slots;
  - pause;
  - native options;
  - player state (lives, energy);
  - anti-copier protection;
  - research tools and methods.
  Each fact carries `[trace]`/`[byte]`/`[static]`/`[hypothesis]`/`[public]` and a log reference.
- **Existing docs become the sources:** facts move into the topic files, and the old files either point to them or are removed when fully absorbed. The dated history becomes a short changelog-style "how we learned it" note per topic, or links to logs.
- **Boundary with OpenSpec:** specs describe what the mod must do; knowledge describes how the game works. Each links to the other instead of repeating it.
- **OpenSpec for Codex:** run `openspec init --tools claude,codex` (non-destructive) so both agents get the same OpenSpec commands/skills.
- README: a short "Documentation map" section pointing to `docs/knowledge/`.
- **English only (user decision, 2026-11-04):** every project artifact is written in English. That covers code, comments, specs (including `## Purpose`), OpenSpec changes, docs, the knowledge base, README, CHANGELOG, agent files and commit messages. Today's rule "documentation may be Portuguese" is removed from `CLAUDE.md`, `README.md` and `openspec/config.yaml`. Conversations with the user may stay in Portuguese. Archived changes and trace logs are history and stay as they are.

## Capabilities

### New Capabilities
None. This is documentation and agent setup; no mod behavior changes (`skip_specs: true`).

### Modified Capabilities
None.

## Impact

- **Files:** `AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/*.md` → `docs/knowledge/*.md`, `openspec/config.yaml` (context points to the knowledge index and states the English-only rule), the `## Purpose` lines of `openspec/specs/*` and of the active `sram-persistence` delta (translated, same meaning), OpenSpec tool files for Codex.
- **No change** to `src/`, `tests/`, `tools/`, patch bytes or the IPS output. The required checks (`npm test && npm run typecheck && npm run patch:build`) must stay green.
- **Unverified assumption:** where `openspec init --tools codex` writes its files (repo vs. the user's global Codex folder) on OpenSpec 1.14.2. The change records the outcome and keeps only repo-local files under version control.
