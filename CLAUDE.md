# Claude Code — Mr. Nutz DX Mod

You are maintaining a spec-driven SNES ROM hacking project. Read these files before editing anything:

1. `README.md`
2. `docs/rom-map.md`
3. `docs/debugging-playbook.md`
4. `openspec/config.yaml`
5. All affected `openspec/specs/**/spec.md`
6. The active proposal/design/tasks in `openspec/changes/`

## Contract

- Use OpenSpec for any new feature, including small ROM-level changes. Follow proposal → delta specs + design → tasks → apply → validate → archive. Do not archive unfinished runtime work.
- Write code, identifiers, comments, test names, and commit messages in English. Documentation and conversations may be Portuguese.
- The user-provided ROM is a private input. NEVER commit ROM binaries or redistribute them.
- Respect 65C816 CPU details, LoROM mapping, CPU bus / CGRAM / DMA separation, little-endian BGR555 palette encoding.
- Research hypotheses are not confirmed facts; label uncertain observations.
- The existing patch builder only changes a 32-byte palette at file offset `0x029CC0`.
- The current full character palette is CGRAM `$C0-$CF` (byte offsets `$0180-$019F`). From observed ROM bytes, `$C6-$C9` is the likely outfit gradient and `$CB-$CF` the likely fur gradient; confirm on actual sprites across animation and level states.
- The first `$C0` entry is the transparent sprite color. Never recolor it.
- The entrypoint of the runtime DMA is not yet a validated safe hook. Captures show a routine near CPU `$9DAC8A-$9DACB7`, but it can update multiple sprite palettes.
- Do not assume patch ROM bank `$85` offset maps to a writable RAM code cheat for ares.
- Validate original ROM size, exact original palette bytes, and generated patch scope.
- Always run `npm test && npm run typecheck && npm run patch:build` before claiming completion.
- For new in-game features, save original disassemblies/register traces and manually verify in Mesen before producing a release patch.
- Do not modify the source ROM in place. Never silently change unrelated graphics or gameplay.

## Useful commands

```bash
npm run rom:inspect
npm run palette:show
npm run patch:build
npm run patch:verify
npm test
npm run typecheck
```

## First Claude task

Read the baseline spec and existing change `runtime-palette-switch`. Confirm current build pipeline; then design and implement one feature at a time. Begin with a Mesen tracing plan (controller reading, in-game palette DMA, VBlank timing), not speculative ASM bytes.
