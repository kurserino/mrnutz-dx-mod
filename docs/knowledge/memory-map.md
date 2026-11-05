# Memory map

## Mapping and header

- **LoROM + FastROM** (map mode `$FFD5` = `$30`) [byte]. File offset = `(bank & $7F) * $8000 + (address & $7FFF)`,
  valid for the ROM halves only (`$8000-$FFFF`). Example: `$85:9CC0` → `0x029CC0`. Code: `loromToFile` in
  `src/snes.ts`.
- Banks `$80-$BF` mirror `$00-$3F`. I/O (`$2100-$43FF`) and low WRAM (`$0000-$1FFF`) appear in every bank
  `$00-$3F`/`$80-$BF` [byte].

| Header field (CPU `$00:FFxx`, file `0x7Fxx`) | Original | With our patch |
| --- | --- | --- |
| Title | `MR.NUTZ` | same |
| `$FFD5` map mode | `$30` | same |
| `$FFD6` chipset | `$00` (ROM only) | `$02` (ROM + RAM + battery) |
| `$FFD7` ROM size | `$0A` (1 MiB) | `$0B` (2 MiB) |
| `$FFD8` SRAM size | `$00` | `$01` (2 KiB) |
| `$FFD9` region | `$01` (USA) | same |
| `$FFDC-$FFDF` complement/checksum | `$8187` / `$7E78` | recomputed for the 2 MiB image |
| Native vectors | NMI `$8349`, IRQ `$83B3`, BRK `$83EC`, COP `$83B3` | same |
| RESET (emulation) | `$80B5` | same |

Source: `npm run rom:header`, `output/runtime-report.json` [byte].

## ROM

### Game (1 MiB, banks `$80-$9F`)

| Address | Content | Tag |
| --- | --- | --- |
| `$85:9CC0` / `0x029CC0-0x029CDF` | Mr. Nutz's 16-colour palette (see `palettes.md`) | [byte] |
| `$82:D454+` (`0x15454+`) | per-scene sprite palette pointer tables (8 × 4 bytes) | [byte] |
| `$99:0051-$99:0057,X` | scene descriptor: BG and sprite palette table pointers | [static] |
| `$9D:ABA7` | scene PPU init (palette DMA) | [byte] + [trace] |
| `$9D:A500-$9D:A5FF` | 256 × `$00`, the only filler run ≥ 256 bytes; use not ruled out, **do not use** | [static] |

The original ROM is practically full: new code goes into the **expansion**.

### Patch expansion (banks `$A0-$BF`, file `0x100000-0x1FFFFF`)

| Address | Content |
| --- | --- |
| `$A0:8000-$A0:8FFF` | hook code (`input_hook`, `load_save`, `write_save`, manager, `oam_hook`); `$66F` bytes today |
| `$A0:9000-$A0:906F` | fur table (10 bytes per preset, index 0 = original) |
| `$A0:9070-$A0:907F` | per-index offsets into the fur table |
| `$A0:9080-$A0:90FF` | outfit table (8 bytes per preset) |
| `$A0:9100-$A0:91FF` | OAM attribute → palette (0-7, `$FF` = name table 1) |
| `$A0:9200-$A0:92FF` | OAM attribute → `1 << palette` |
| rest up to `$BF:FFFF` | `$FF` — **free** (almost 1 MiB) |

Source: `src/runtime.ts` (`CODE_ORIGIN`, `FUR_TABLE`, `OUTFIT_TABLE`, `ATTR_PAL`, `ATTR_BIT`) [byte].

## WRAM (128 KiB, `$7E:0000-$7F:FFFF`)

### Used by the game (known addresses)

| Address | Content | Tag |
| --- | --- | --- |
| `$7E:01DC` | indirect NMI vector (`$835B` gameplay, `$8357` other screens) | [trace] |
| `$7E:01DA` | NMI counter | [trace] |
| `$7E:055A-$7E:0560` | scene pointers: BG (`$055A/$055C`), sprite palette table (`$055E/$0560`, long) | [static] |
| `$7E:0321+` | OAM buffer (`$0024` bytes in use) | [trace] |
| `$7E:1A6F` / `$7E:1A71` | joypad 1 / 2 mirror | [trace] |
| `$7E:13B4`, `$7E:13B5` | pause flag and Start latch (`frame-cycle.md`) | [trace] |
| `$7E:183D` | `$420C` (HDMA) value re-applied in the NMI | [static] |
| `$7E:1EC9` | bit 0 = debug stage skip (`game-state.md`) | [trace] |
| `$7E:1889`, `$7E:05A2` | lives (obfuscated), energy | [trace] |
| `$7F:B008-$7F:B00C` | native options | [trace] |
| `$7F:B00D-$7F:B00E` | read by the L/R debug mode (`$81:82F1`) | [static] |
| `$7F:B513-$7F:B519` | copies of the scene pointers, used when `$13B8 ≠ 0` (checkpoint/continue?) | [static] + [hypothesis] |
| `$7F:FFF0+` | **cleared by the game on some world changes** | [trace] |

### Free

| Region | Size | Use | Evidence |
| --- | --- | --- | --- |
| `$7F:B680-$7F:BFFF` | 2.4 KB | **persistent state**; ours lives at `$7F:BE00+` (`mod-implementation.md`) | [trace] `sweep-wram.log` measured `$7F:B6C0-$7F:BFFF` over the whole game, credits, reset and boot; `space-survey.log` extends it down to `$7F:B680` in gameplay |
| `$7F:D040-$7F:FFFF` | 12 KB | **temporary buffer** (for example the pause menu's VRAM backup). Untouched during gameplay, but its end (`$7FFFF0+`) is cleared on world changes | [trace] `space-survey.log` |
| `$7F:94C0-$7F:9FBF` | 2.8 KB | reserve, measured in gameplay windows only | [trace] `space-survey.log` |
| `$7E:EE40-$7E:F3FF` | 1.5 KB | reserve, same | [trace] `space-survey.log` |
| `$7F:AC40-$7F:AFBF`, `$7F:B040-$7F:B37F` | 0.9 + 0.8 KB | reserve, same | [trace] `space-survey.log` |

The "reserve" regions were measured over 900 frames per stage (`npm run survey:space`). Before using one for
persistent data, run a whole-game trace like `sweep-wram.log`.

## VRAM (64 KiB)

Gameplay layout, identical in all 40 stage states (byte addresses) [trace] `space-survey.log`:

| Region | Bytes | Content |
| --- | --- | --- |
| BG3 tiles (2bpp) | from `$0000` (overlaps the tilemaps; the tiles in use sit above `$1800`) | HUD |
| BG1 tilemap | `$0000-$07FF` | stage |
| BG2 tilemap | `$0800-$0FFF` | background |
| BG3 tilemap | `$1000-$17FF` | HUD |
| BG1/BG2 tiles (4bpp) | `$4000-$BFFF` | stage, streamed during play |
| Sprites (OBJ) | `$C000-$FFFF` | Mr. Nutz, enemies, items |

- BG mode 1; main screen `$17` (BG1, BG2, BG3, OBJ).
- **Practically no free space:** only `$8600-$86FF` was never referenced in any stage (conservative for sprites).
  Anything that needs VRAM (for example the pause menu) must back up and restore what it overwrites.

## CGRAM (512 bytes)

- `$00-$7F`: BG palettes (256-byte DMA at scene init).
- `$80-$FF`: 8 sprite palettes of 16 colours (slots 0-7). Which palette goes to which slot comes from the scene table
  (`palettes.md`).
- Entry 0 of each sprite palette = transparent.
- Almost every palette is written during stages [trace] `space-survey.log`.
- CGRAM reads through `$213B`: bit 15 is open bus (read `$CFBF` for `$4FBF`) [trace].

## SRAM (2 KiB, only with our patch)

- Mapped at `$70-$7D:0000-$7FFF`; we use bank `$70`.
- The original game **has no SRAM** and has protection that detects it (`protection.md`).
- Addresses the original checks touch: `$70:0000-0001`, `$0004`, `$0034`, `$00A9-00AA`, `$0345-0348`.
- Our save record lives at `$70:0100-$70:0107` (`mod-implementation.md`).
- Mesen fills new SRAM with random bytes [trace] `power-cycle.log`.
