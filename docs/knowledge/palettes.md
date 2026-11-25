# Palettes

## Mr. Nutz palette `$85:9CC0`

16 BGR555 little-endian colours at `$85:9CC0` / file `0x029CC0-0x029CDF` [byte]:

```
00 00 CE 49 52 5A D6 6A 5A 7B DE 7B 1A 03 92 02
8A 01 C8 00 00 00 0E 00 12 00 16 00 1A 00 1E 00
```

| Entry (slot 4 = CGRAM `$C0-$CF`) | Original | Role |
| --- | --- | --- |
| 0 (`$C0`) | `$0000` | transparent — **never recolour** |
| 1-5 (`$C1-$C5`) | `$49CE` … `$7BDE` | white/grey (eyes, belly, highlights) |
| 6-9 (`$C6-$C9`) | `$031A`, `$0292`, `$018A`, `$00C8` | **outfit**: yellow cap and vest, light → dark |
| 10 (`$CA`) | `$0000` | black (outline) |
| 11-15 (`$CB-$CF`) | `$000E` … `$001E` | **fur**: red, dark → light |

Roles confirmed by colouring one entry at a time and capturing Mr. Nutz standing, walking, jumping and hurt (E4 sweep)
[trace] `trace-palette.log`. Static recolour presets: `presets/*.json`; runtime presets: `presets/runtime.json`.

## Per-scene sprite palette table

1. `$82:8837-$82:8886` copies pointers from the scene descriptor (`$99:0051,X … $99:0057,X`) into `$055A` (BG source),
   `$055C` (BG bank) and `$055E/$0560` (long pointer to the **sprite palette table**). With `$13B8 ≠ 0` it uses the
   copies saved at `$7F:B513-$7F:B519` instead [static; hypothesis: restore after checkpoint/continue].
2. `JSL $9D:ABA7` initializes the scene PPU with `D=$2100` (called from `$82:8AC5`, `$9C:F764`, `$9D:AE49`,
   `$9D:C3BB`, `$9D:C7DC`, `$9D:E127`, `$9D:E452`) [static]. Its tail `$9D:AC4D-$9D:ACB7`:
   - `$9D:AC57-$9D:AC7B`: DMA channel 0 → `$2122`, 256 bytes from `$055C:$055A` (CGRAM `$00-$7F`, BGs);
   - `$9D:AC7E-$9D:ACB5`: loop of 8 (`$14=8`) reading 4 bytes per palette from `[$10]` (address16, bank16) and doing
     a 32-byte DMA to CGRAM `$80`, `$90`, … `$F0` in sequence. CGADD is not rewritten;
   - `$9D:ACB7`: `RTL`.
   - Old Mesen GUI captures in this loop: a CGRAM write breakpoint stops at `$9D:ACB4` (DMA trigger at `$9D:ACB3`,
     `$9D:ACB0` in the first evidence request); the call at `$9D:ACA3` is the `LDA [$10]` that reads the table entry
     (`X=$9C60` or `$9D80`, `A=$0085`). CGADD advances during the DMA, so the value seen after the breakpoint is not
     the start address [trace].
   - The init runs in forced blank: `$9D:AB48` writes `$2100=$80` and waits for VBlank [static].
3. The table is 8 entries × 4 bytes; **entry k = sprite slot k** (CGRAM `$80 + k*$10`). The tables live at `$82:D454+`
   (file `0x15454+`), with 27 occurrences of `$85:9CC0`, usually in entry 4 [byte].
4. **The Mr. Nutz slot varies per scene:** in one stage the table `[$055E] = $82:D60C` puts `$85:9CC0` in **slot 0**
   (CGRAM `$80`), and Mr. Nutz uses OAM palette 0 [trace] `sweep-debug10.log`. Always look the palette up in the
   current table (`nutzSlot()` in `tools/mesen/lib.lua`; `find_slot` in the hook).
5. The palette is only loaded at scene init (forced blank) and on death/respawn, not every frame. A colour written at
   runtime persists for ≥ 1120 frames while walking and jumping [trace] `trace-palette.log`.

## Other CGRAM writers

- Direct `$2121/$2122`: `$81:8F65` (inside anti-copier check C's fall-through, see `protection.md`), `$82:813C`,
  `$81:C3F3-$81:C404`, `$8B:FCC1` [static, not analysed].
- **Animated sprite palette 1:** `$81:C3E8` runs every gameplay frame right after the OAM upload. While the word
  `[$13BC]` is non-zero it writes CGRAM `$91` (sprite palette 1, entry 1) from the table it points to (`$13BC` cycles
  `$960D/$960F/$9611/$9613`; colours `$001F`, `$03E0`, `$03FF`). `$13BC` was non-zero in every stage state
  `stage-00..30` [static + trace] `cgw-slot2b.log`, `cgadsub-*.log`, `cw-slot2-0.log`. The private slot must never be
  palette 1.
- HDMA to `$2122` set up at `$9D:B9AE`, `$9D:B9E8`, `$9D:BE0E`, `$9D:CAC9`, `$9D:DC8B`, `$9D:EA28`, `$9D:EA62`.
  `$9D:B997` writes CGADD `$00` (backdrop) through the indirect table `$82:E4AA` [static; hypothesis: sky gradient].
- **Water:** the blue tint underwater is a scene effect; Mr. Nutz keeps OAM palette 4 (octopus uses 5). Dying in
  water reloads `$85:9CC0` by DMA [trace] `swim-blue-35.log`, `swim-blue-37.log`.

## Objects that share the Mr. Nutz palette

Several objects use `$85:9CC0` in the same slot: the cloud caterpillar, items and others. Their tiles are `$064`,
`$060-$062`, `$100-$12E`, `$104/$16E/$1C4`, `$0CC-$0EC`… [trace] `sweep-analyze.log`. **Mr. Nutz always uses tiles
`$000-$046` of name table 0.** Writing new colours into his scene slot would recolour all of them; that is why the mod
uses a private slot (`mod-implementation.md`).

## Colour math groups

- Sprite palettes 4-7 take part in colour math; palettes 0-3 do not. A private copy of the Mr. Nutz palette must stay
  in the **same group** as his scene slot, or he would look different (translucency) [trace] `sweep-colormath.log`.
- `$2131` (colour math control) is write-only and the game writes it from constants (no WRAM copy, `$85:939C`)
  [static].
- Scenes where sprite colour math is never on (CGADSUB bit 4 off), measured over 2400 frames with Mesen's PPU state
  (`scene-palettes.lua`): witch fight, scene table `$82:D58C` (`$2131 = $20`, backdrop only) [trace]
  `scenepal-08-s1.log`; spider stage, `$82:D620` (`$00`, then `$2F` = BG1-4 + backdrop) [trace] `scenepal-04-s1.log`.
  There a slot of the other group looks the same; the hook lists them in `CROSS_GROUP_SCENES` (`src/runtime.ts`).
- `$2131` writers: `$85:939C` (scene init; `$20` in the witch fight) [trace] `cgadsub-08.log`; other constant writers
  in `frame-cycle.md` [static].

## Scenes without a free slot

The mod needs one slot in Mr. Nutz's group that no other object uses in the scene. Where all four are busy, he keeps
his original colours and nothing else changes. Current numbers (Mr. Nutz in the selected colours / frames he was
visible) [trace] `sweep-all.log`:

| Stage state | Scene | Coloured |
| --- | --- | --- |
| `stage-04` | spider boss (Woody Land 5) | 45.3% in v0.2.0; 99.8% since fix-private-slot-choice |
| `stage-08` | witch boss (picture frame) | 0.0% in v0.2.0; 100% since fix-private-slot-choice (slot 0) |
| every other stage | | ≥ 99% |

Both boss scenes now use the other colour-math group (see above). In the witch fight palette 0 also looked busy:
40 high-OAM entries hold the game's cleared pattern y = tile = attr = `$E0`, and attr `$E0` reads as palette 0. The hook
skips that exact pattern [trace] `oamdump-08.log`.

Screens without gameplay (intros, continue map, final screen) always show the original colours: the hook only runs
during gameplay. The Stage Clear screen is the exception (next section).

## Stage Clear screen

- Init at `$9D:E3F0+`: `[$055E]/$0560 = $82:D474` (constant) at `$9D:E43A-$9D:E44F`, then `JSL $9DABA7` (scene init,
  palettes) at `$9D:E452`, which returns in forced blank (INIDISP `$80`, line 148). No sprite palette is written after
  it until the screen ends [static + trace] `sc-init-witch.log`. Reached from the fade-out request `$81:D20E`
  (`$13B6 = $82D4`) [trace] `w055e-witch.log`; NMI handler `$8357` while it is shown.
- Sprites: Mr. Nutz 6 entries on palette 4 (tiles `$000-$044`), slot 4 = `$85:9CC0`; chest 25 entries on palette 5;
  coins on palette 1. Same after the witch and the `stage-21` boss [trace] `sc-witch.log`, `sc-blizzard.log`.
- The patch writes the selection into that slot after `JSL $9DABA7` (`clear_hook`, stage-clear-colours)
  [trace] `sc10-witch.log`, `sc10-blizzard.log`.
- **When it appears:** only at the end of a world. `$80:82D4` (next stage) adds 2 to the stage index `$054C`; at
  `$82:82AA` the entry of the stage list `$99:E65F` at that index decides: `$FFFF` = end of world, the index skips
  the marker and the next entry (a world entry, `$E6B5`, `$E6B9`, `$E6BD`, `$E6C1`, `$E6C5`) is passed in A to
  `JSL $9DE2AE` at `$82:82D5`, the Stage Clear routine; `$FFFE` (after the last stage) = `JML $9DF00F`, the ending,
  with no Stage Clear [static + trace] `sccaller.log`, `scall-summary.log`, `scall-30.log`.
- So there are 5 Stage Clear screens, after `stage-04`, `stage-08`, `stage-15`, `stage-21` and `stage-25` (worlds 1-5);
  `stage-30` leads to the ending text. Each one shows the same sprites (Mr. Nutz 6 entries on palette 4, chest 25 on
  palette 5) and, with the patch, the selection in slot 4 and `$85:9CC0` in no slot [trace] `scall-04/08/15/21/25.log`.
  With the original selection the screen is pixel-identical to the original ROM [trace] `scall-04-orig.log`,
  `scall-04-romorig.log`.
- The debug stage skip (`$81:8307`) goes through the same `$80:82D4`, so it shows the Stage Clear screen when used in
  the last stage of a world (`tools/mesen/stage-clear-all.lua`), and not elsewhere.
