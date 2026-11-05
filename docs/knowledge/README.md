# Knowledge base — Mr. Nutz (USA) (En,Fr)

Everything we know about **how the game works** and **how our patch fits into it**. Read this before researching: if
an address or mechanism is already here, do not re-derive it; if you find something new, record it here.

- **What the mod must do** (required behaviour, acceptance scenarios): `openspec/specs/`.
- **How the game works and where things are:** this folder.
- **Working rules for agents** (Claude Code and Codex): `AGENTS.md`.
- **History:** `CHANGELOG.md` and `openspec/changes/archive/`.

Everything in this repository is written in English (see `AGENTS.md`).

Supported ROM: `Mr. Nutz (USA) (En,Fr).sfc`, 1,048,576 bytes, no copier header, CRC32 `A99BDD9A`, SHA-256
`3472dd574b50aed2fa998f464398db4fbb00f5a300a672c3737ee9336a008a16`.

## Index

| File | Topic |
| --- | --- |
| [memory-map.md](memory-map.md) | LoROM, header, ROM/WRAM/VRAM/CGRAM/SRAM regions: used by the game, free, used by us |
| [frame-cycle.md](frame-cycle.md) | NMI (gameplay and paused), joypad reads, OAM upload, HDMA, VBlank budget |
| [palettes.md](palettes.md) | Mr. Nutz palette `$85:9CC0`, per-scene palette table, slots, colour math, scenes without a free slot |
| [game-state.md](game-state.md) | lives (obfuscated), energy, native options, pause, debug stage skip, public cheats, pitfalls |
| [protection.md](protection.md) | SRAM anti-copier protection (checks A-G) and how it is neutralized |
| [mod-implementation.md](mod-implementation.md) | how the patch is built: manifest, assembler, hooks, WRAM state, save |
| [research-tools.md](research-tools.md) | headless Mesen, every `npm run` command, search methods that worked or failed, open questions |

Cited logs live in `docs/traces/` (text, no ROM data). Screenshots live in `output/traces/`, which is private and
git-ignored.

## Evidence tags

| Tag | Meaning |
| --- | --- |
| `[trace]` | observed running in Mesen, with the log cited |
| `[byte]` | read directly from the ROM and covered by a test or by the patch manifest |
| `[static]` | interpretation of a disassembly, not executed |
| `[hypothesis]` | plausible interpretation without proof; do not treat it as a fact |
| `[public]` | taken from an external source (for example PAR codes), not verified here yet |

## Fact format

One line or table row with: **address or routine** → **what it is** → **tag** → **log or command that reproduces
it**. Example:

`$7E:13B4` — pause flag (`$FF` paused, `$00` playing) — [trace] `pause-probe.log`.

Addresses: CPU bank:address (`$81:828A`), WRAM as `$7E:xxxx`/`$7F:xxxx`, file offsets as `0x029CC0`, VRAM in bytes
(Mesen shows word addresses = half).

## Adding a fact

1. Reproduce it with a tool from `research-tools.md` and save the log in `docs/traces/`.
2. Write the fact in the topic file, with its tag and log.
3. If it contradicts something already written, fix the old text. If the mistake could mislead again, add it to the
   "Pitfalls" list (`game-state.md`) or the topic's equivalent section.
4. If the fact changes what the mod must do, that belongs in an OpenSpec change, not here.
