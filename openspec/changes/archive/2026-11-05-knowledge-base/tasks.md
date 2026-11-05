# Tasks

## 1. Knowledge files

- [x] 1.1 Create `docs/knowledge/README.md` in English: index, evidence labels (`[trace]`, `[byte]`, `[static]`, `[hypothesis]`, `[public]`), the fact format (design D5) and "how to add a fact". Verify every file listed in design D1 is linked from it.
- [x] 1.2 Write `memory-map.md` from `rom-map.md`, `expansion-budget.md` and the memory parts of `runtime-hook.md`. Verify every address in the source sections appears in the new file (grep check, design Risks).
- [x] 1.3 Write `frame-cycle.md`: NMI vector `$01DC`, gameplay vs. paused NMI, joypad mirror, OAM DMA, HDMA timing, VBlank budget. Verify each claim cites a trace log or is labelled `[static]`/`[hipótese]`.
- [x] 1.4 Write `palettes.md`: `$85:9CC0`, scene table `[$055E]`, slots and colour-math groups, private-slot technique, no-slot scenes. Verify the no-slot list matches the current `docs/traces/sweep-all.log` summary.
- [x] 1.5 Write `game-state.md`: lives (obfuscated), energy, public PAR addresses, native options `$7F:B008-$B00C`, pause flag `$13B4`, debug stage skip `$1EC9`, and an "Armadilhas" list. Verify it absorbs all of `docs/ram-map.md`.
- [x] 1.6 Write `protection.md`: checks A-G, effects with SRAM, neutralization reference to the manifest. Verify it absorbs the protection section of `docs/static-analysis.md`.
- [x] 1.7 Write `research-tools.md`: every `npm run` research/test command (what, when, run time, output), the RAM-search methods that worked and the ones that failed, savestate preparation, and open questions (from `debugging-playbook.md` and `mesen-evidence-request.md`). Verify each listed script exists in `package.json`.
- [x] 1.8 Write `mod-implementation.md`: patch manifest, assembler, hook sites and state layout, current behaviour without the dated layers of `runtime-hook.md`, and links to `openspec/specs/*`. Verify `architecture.md`'s outdated `asm/` statement is gone.

## 2. Remove duplicates and fix links

- [x] 2.1 Delete the absorbed files (`rom-map.md`, `static-analysis.md`, `runtime-hook.md`, `ram-map.md`, `expansion-budget.md`, `debugging-playbook.md`, `mesen-evidence-request.md`, `architecture.md`), keeping any that still holds unique content (then explain why in `docs/knowledge/README.md`). Verify with a grep that each address of the deleted files exists in `docs/knowledge/`.
- [x] 2.2 Fix every link to a removed path outside `openspec/changes/archive/` (README, CHANGELOG, active changes, tools comments, `src/` comments). Verify `git grep` finds no live reference to a deleted file.
- [x] 2.3 Add a short "Documentation map" to README pointing to `docs/knowledge/` and `openspec/specs/`. Verify the README links resolve.

## 3. Agent setup (Claude + Codex)

- [x] 3.1 Rewrite `AGENTS.md` in English: contract, required checks, Mesen-only testing, ROM privacy, evidence labels, "Start here" list, "do not re-derive known facts" rule. Verify it covers every still-valid rule from today's `CLAUDE.md` (compare line by line) and drops the outdated ones.
- [x] 3.2 Reduce `CLAUDE.md` to `@AGENTS.md` plus Claude-only notes. Verify no rule appears in both files.
- [x] 3.3 Run `openspec init --tools claude,codex`; inspect what it creates or changes (repo vs. global folder) and revert unrelated changes to `.claude/`. Verify `openspec validate --specs --strict` passes, existing specs/changes/archive are unchanged (`git status`), and the outcome is recorded in `AGENTS.md`.
- [x] 3.4 Point `openspec/config.yaml` context to `docs/knowledge/README.md`. Verify `openspec instructions proposal --change <any> --json` shows the new context.

- [x] 3.5 State the English-only rule in `AGENTS.md`, `openspec/config.yaml` (context + per-artifact rules) and the README, and remove every "documentation may be Portuguese" statement. Verify `git grep -i portugu` (outside the archive and traces) only matches the rule itself ("conversations may be Portuguese").
- [x] 3.6 Translate the `## Purpose` of the five main specs and of the `sram-persistence` `save-memory` delta to English (same meaning). Verify `openspec validate --specs --strict` and `openspec validate sram-persistence --type change --strict` pass.

## 4. Checks

- [x] 4.1 Run `npm test && npm run typecheck && npm run patch:build && npm run runtime:build`. Verify that the runtime IPS has the same SHA-256 as before this change (no byte change), and that the static patch still validates the ROM signature. Done: 32 tests, typecheck, both builds; runtime IPS SHA-256 `e4c53f09…` unchanged (2584 bytes).
- [x] 4.2 Ask a fresh agent session (Codex or Claude) three questions with no extra context: "what is at `$7E:1889`?", "where does the paused NMI go?", "where can the pause menu store a VRAM backup?". Verify the answers come from `docs/knowledge/` and are correct, and that every new or changed file in this change is in English. No Mesen smoke test is needed, because no patch byte changes (4.1). Done: a fresh Explore agent, starting from `AGENTS.md`, answered all three correctly from `game-state.md`, `frame-cycle.md` and `memory-map.md`, with tags and sources, and found no Portuguese in `AGENTS.md`, `CLAUDE.md` or `docs/knowledge/`.

## Workflow follow-up

- Archive this change after the checks pass. There are no specs to sync (`skip_specs: true`).
