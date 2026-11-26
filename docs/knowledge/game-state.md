# Game state: lives, energy, options, pause, debug

## Player

| Address | Size | Content | Tag |
| --- | --- | --- | --- |
| `$7E:1889` | 16 bits | **Lives, obfuscated:** `lives_BCD = word($1889) XOR $A3B7`. The HUD shows the same number (`x2` = `$0002`, stored as `$A3B5`) | [trace] `watch-1889.log`, `poke-lives6281.log` |
| `$7E:01F4` | 8 bits | **Energy, obfuscated:** `energy = byte XOR $B7`; the HUD shows energy + 1 hearts (full `$FF0000`, empty `$6B0000`). `stage-00` starts at 2 (`$B5`, 3 hearts); each hit -1; below 0 = life lost. Maximum `$7F:B00E XOR $B7` = 4 (5 hearts). Set at stage start from `$188E` (`$82:82DB`) | [trace] `hud-energy-00.log`, `energy-ctl-s1.log` |
| `$7F:B00D` / `$7F:B00E` | 8 bits | start energy / maximum, XOR `$B7`, from the ENERGY option through the table `$9D:AD98` (`$B5 $B4 $B3 …`) at `$9D:ACCD-$9D:ACE7`; maximum = min(start + 2, 4) | [static + trace] `watch-energy-00.log` |
| `$7E:05A2` | 8 bits | **not energy** (wrong until 2026-11-25): high byte of the list pointer `$05A1` (writes from `$81:E108` with `$05E3`/`$0623`) | [trace] `watch-05a2-00.log` |
| `$7E:008D` | 8 bits | invulnerability: PAR `7E008D2D` | [public] |
| `$7E:0A29` | 8 bits | nuts: PAR `7E0A2999` | [public] |
| `$7E:1894` | 8 bits | coins: PAR `7E189499` | [public] |
| `$7E:05D0` | 8 bits | "one shot bosses": PAR `7E05D000` | [public] |

Checked in Mesen with `tools/mesen/cheat-check.lua` (each code held every frame, as an ares RAM cheat; 2026-11-25):

- `$8D = $2D` (invulnerability): 0 deaths in 4 × 3600 frames of random play in `stage-00`, against 6 deaths without
  it [trace] `cheat-ctl-s2..5.log`, `cheat-inv-s2..5.log`. It does **not** prevent pit deaths (Mr. Blizzard arena,
  Y 180 → 304) [trace] `cheat-bossinv-s1.log`.
- Lives `word($1889) = $A3BE` (x9): the HUD shows x9 and a death leaves it at 9 [trace] `cheat-lives.log`.
- `$0A29 = $99` (nuts) and `$1894 = $99` (coins): the HUD shows 99 [trace] `cheat-nuts.log`, `cheat-coins.log`.
- **Full infinite energy as a ROM cheat (preferred):** the hit code `$82:A19A` `LDA $01F4 / EOR #$B7 / TAX / DEC A /
  EOR #$B7 / STA $01F4` (death if `X - 1 < 0`, `$82:A1A8`) becomes `LDA #$B2 / NOP` (every hit leaves 4 = 5 hearts);
  energy is also set to `$B3` instead of `$188E` at stage start (`$82:82DB`) and on a new life (`$80:8261`), and
  instead of `$7F:B00D` on a new game (`$80:818A`, 4 bytes, M8). ares code:
  `82A19A:A9+82A19B:B2+82A19C:EA+8282DB:A9+8282DC:B3+8282DD:EA+808261:A9+808262:B3+808263:EA+80818A:A9+80818B:B3+80818C:EA+80818D:EA`.
  Verified with Mesen's cheat engine: 5 hearts from the first frame of a new game, no enemy death, normal soft reset
  [trace] `romenergy-boot.log`, `romenergy-play-s1/s2.log`, `romenergy-reset.log`. It touches no RAM read.
- **RAM read cheats can break stage loading in ares.** Two user states, both after "load a save, soft reset, new game",
  stayed black at stage start (`$0572 = $CF1C`, NMI looping over the DMA queue `$13C9+`): the garbage written over
  `$01E2-$01F3` and `$13C2-$13F1` was `$B3` with the energy code `7E01F4:B3` on, and `$FF` once only
  `7E008E:FF` (infinite jump) was left, i.e. always the value of a RAM read cheat [trace] `user-black*.bs1` (private,
  analysis in this section). Not reproduced with Mesen's cheat engine. Use ROM cheats for anything left on.
- **Infinite jump as a ROM cheat:** `$82:A71E` `LDX $8E / BEQ $A777` (air jump allowed when `$8E` is non-zero)
  becomes `LDX #$FF`: `82A71E:A2+82A71F:FF`. Jump peak 283 px against 78 (the RAM code `$8E = $FF` gives 344: other
  readers of `$8E` also change) [trace] `jump-none.log`, `jump-rom.log`, `jump-ram.log`; new game and soft reset
  normal with the ROM energy and jump codes [trace] `romcheats-boot.log`, `romcheats-reset.log`.
- The user's ares state after "load a save, soft reset, new game" with the RAM energy code on stayed black at stage
  start: `$0572 = $CF1C` (stage loading) for ~340 frames while the NMI looped over a DMA queue (`$13C9+`) filled with
  `$B3`, and `$01E0-$01F3` held an `$FF $00` pattern; a clean run spends 1 frame there with an empty queue
  [trace] `blackwatch.log`, `qdump-orig.log`. Not reproduced in Mesen (cheats, soft reset, L/R fuzz:
  `lrfuzz-s1..6.log`); [hypothesis] ares applies the RAM read code to accesses Mesen's cheat engine does not. Prefer
  the ROM cheat above.
- `$01F4 = $B3` (full infinite energy, 5 hearts): with Mesen's cheat engine, 0 deaths from enemies in 4000 frames
  (only pit deaths, energy still full), against 1-2 without it; from power-on the game starts normally with 5 hearts
  [trace] `energy-par-s1/s2.log`, `energy-ctl-s1/s2.log`, `energy-boot.log`.
- `$1EC9 = $01`: one R press goes to the next stage (`$054C` 0 → 2) [trace] `cheat-skip.log`.
- `$8E = $FF` (infinite jump) and `$91 = $00` (super jump): jump peak 300 px against 78 px [trace]
  `cheat-ctl-jump.log`, `cheat-infjump.log`, `cheat-superjump.log`.
- `$05D0 = $00` ("one shot bosses") is **not confirmed** on this ROM: `$05D0` is already `$00` in the Mr. Blizzard
  fight and the runs with and without the code are identical; in `stage-00` it changes between 0, 1 and 2 during
  normal play [trace] `cheat-boss-ctl-s1..3.log`, `cheat-boss-1hit-s1..3.log`. Purpose unknown.

### Boss health

**Mr. Blizzard** is the yeti, the final boss of `stage-30` (stage index `$50`, scene table `$82:D77C`; `blz-01.mss`, the
user's ares slot of 2026-11-22). His health address is not mapped yet.

Found with `tools/mesen/boss-hp.lua` (WRAM bytes that only fall while an invulnerable Mr. Nutz jumps around the boss
room; Mr. Nutz damages a boss by landing on its head). The boss health bar mirrors `$7E:1ED4`/`$7E:1ED6`.

| Boss | State | Health | Start value | Evidence |
| --- | --- | --- | --- | --- |
| World 4 boss (giant face, `stage-21`; not Mr. Blizzard, who is the yeti of `stage-30`) | `stage-21.mss` | `$7E:19B5` | 5 (bar 5) | [trace] `blz-hp-s1.log`: 5 → 4 → 3 with the bar |
| Witch (picture frame, `stage-08`) | `stage-08.mss` | `$7E:19A3` | 15 (bar 16) | [trace] `boss-hp-s1..3.log`: 15 → 6, one per stomp |

Cheats tested with Mesen's own cheat engine (`emu.addCheat`, Pro Action Replay type; like ares it answers CPU reads
with the code value):

- `7E19B500`: the `stage-21` boss dies as soon as the fight runs (frame 2969 of the state, no stomp needed) and the
  STAGE CLEAR screen follows; the next stage plays normally [trace] `blz-par0.log`.
- `7E19A300`: the witch dies at frame 420 and the next stage plays normally [trace] `witch-par0.log`.
- `7E19B501` (health held at 1) does **not** work: the stomp still lowers the bar (5 → 4 → 3) and the boss lives.
  The hit probably decrements the byte, and the death check reads it again (sees 1) [hypothesis] `blz-par1.log`.
- Both zero codes held together change nothing in 12 normal stages (`stage-00` … `stage-30`, 1800 frames of random
  play): every stage end matches the run without cheats or follows a death [trace] `bosscheat-*.log`.
- The other bosses (spider in `stage-04`, …) are not mapped yet; each boss seen so far has its own address.
- In `boss-hp.lua`, `emu.addCheat` called at the script top level hangs Mesen 2.2.1 headless; call it after the state
  load (inside an exec callback).

Public codes: [Almar's Guides — Mr. Nutz (USA) Pro Action Replay](https://almarsguides.com/retro/walkthroughs/snes/games/MrNutz/ProActionReplay/).
No SNES Game Genie codes are published.

### Lives

Life-loss routine at `$81:D14A` [static], run on every death [trace: PC `$81:D161`, frames 2755 and 5755 of
`watch-1889.log`]:

```
LDA $1889      ; 16-bit
EOR #$A3B7     ; undo the obfuscation
SED
SEC
SBC #$0001     ; BCD decrement
CLD
BPL keep
LDX #$8283     ; negative -> game over state
keep:
EOR #$A3B7
STA $1889
STX $13B6      ; next game state pointer
RTS
```

- **Infinite lives:** hold `word($1889) = $A3B7 XOR n` (BCD). `$A3B5` keeps the player at x2. Confirmed: held, the
  game never reaches game over in 7500 frames [trace] `poke-lives6281.log`.
- **Fast game over** (for tests): `word($1889) = $A3B7` (0 lives). The next death leads to game over and continue, and
  the game restarts with x3 (`$A3B4`). From `stage-00` this happens around frame 3000 [trace] `trace-sram-go0.log`.
- `$7E:188B` also rises by 1 per lost life, but holding it does not prevent game over [trace]. Purpose unknown.

## Native options (title → OPTIONS → "OPTION MODE")

In the menu, Up/Down move the cursor (`$7E:1EDE` row, `$7E:199F` = row × 2) and **A** changes the value. Left/Right do
nothing [trace] `options-probe.log`. The values are stored together, one byte each [trace] `options-writes-row0..4.log`:

| Address | Option | Writer | Values seen on screen |
| --- | --- | --- | --- |
| `$7F:B008` | LIVES | `$9D:C206` | 0 = 04, 1 = 05, 2 = 06 (start lives = 4 + value?) [hypothesis for the upper limit] |
| `$7F:B009` | ENERGY | `$9D:C24E` | 0 = 03, +1 per press |
| `$7F:B00A` | CONTROL PAD | `$9D:C17F` | 0 = JUMP B/A, SHOT Y, RUN X; 2 = JUMP A, SHOT Y/B, RUN X; 1 not captured |
| `$7F:B00B` | MUSIC MODE | `$9D:C298` | 0 = STEREO, 2 = NONE; 1 not captured (MONO?) |
| `$7F:B00C` | LANGUAGE | `$9D:C2DA` | 0 = ENGLISH, 1 = French (toggles) |

- `$7E:19A1` changes on each press (10/20/30), probably the menu sound effect [hypothesis].
- **Not verified yet:** whether changing these bytes **during gameplay** takes effect (controls, music, text
  language). This is a prerequisite for an in-game Options menu.

Title screen timeline from power-on (useful for scripts): one Start at frame 200 skips the logos; the title (START /
OPTIONS) is stable from about frame 900 [trace] `boot-timeline.log`.

## Pause

`$7E:13B4` = `$FF` paused, `$00` playing; `$13B5` latches Start. The paused NMI path is in `frame-cycle.md`.

## Stage list

- `$7E:054C` = stage index (2 per entry) into the word list `$99:E65F`. `$80:82D4` (next stage) adds 2; `$FFFF` marks
  the end of a world (the following entry goes to the Stage Clear routine `JSL $9DE2AE`, then the next world);
  `$FFFE` after the last stage leads to the ending (`JML $9DF00F`) [static + trace] (`palettes.md`, Stage Clear).
- Worlds end after `stage-04`, `stage-08`, `stage-15`, `stage-21`, `stage-25`; `stage-30` is the last stage
  [trace] `scall-summary.log`. Stage state → index: `stage-07` = `$12`, `stage-08` = `$14`, `stage-09` = `$1A`.

## Debug stage skip

- The debug handler (`$81:82F1-$81:8333`) reacts to the **held** pad `$1A6F`, every frame: R → `$13B6 = $82D4`,
  coins `$1894 = $0100`, `$01F4 = $7F:B00D`, `$056D = 1`; L → `$01F4 = $7F:B00E`, `$056D = 1`. With the debug bit on, the
  mod's Select+L/R colour shortcuts also trigger it [static].
- With `$7E:1EC9` bit 0 set, **R** ends the current stage and goes to the next one, and L/R write `$01F4` from
  `$7F:B00D/$7F:B00E` and set `$056D=1` (`$81:82F1-$81:8333`) [static + trace] `probe-warp.log`.
- `$1EC9` is `$00` in normal play, so L and R alone do nothing [trace] `trace-palette.log`.
- Our test tools set the bit only in emulator RAM, to reach every stage (`sweep:prepare`) or to finish the game
  (`check:ending`). Finishing stage 36 this way leads to the ending.

## Ending

After the credits, the "Starring Mr. Nutz / Final Score" screen **waits forever**: Start and A do nothing, in the
original ROM too [trace] `ending-check-original.log`. A soft reset returns to the title and a new game works
[trace] `ending-check.log`.

## Pitfalls

- **Searching lives by their displayed value fails** (2 → 1 → 0): the stored value is obfuscated. A "constant step per
  life" search found `$1889` (`tools/mesen/find-lives.lua`).
- **False lives candidates:** `$7E:060E` and `$7E:0A8A` (object table, written at `$81:E3D7`/`$81:E4E5`,
  `watch-060E.log`); `$7E:1071` (generic object queue, `$81:DACB`, `watch-1071.log`).
- **Do not write `$05A2`:** it is a list pointer byte, not energy (see the table); `$05A2 = 1` written on frame 30 of `stage-00` (still in the stage intro)
  cleared `$1889` and left the game in a black-screen loop at `$8A:81E2` [trace] `trace-sram-go1.log`. Hypotheses:
  anti-tamper check or inconsistent state. Not investigated.
- **Start presses during boot start a game:** to reach OPTIONS, press Start only once (frame 200), then Down and Start
  on the title (`options-probe.lua`).
- **Options diff noise:** `$0000-$001F`, `$0035-$0036`, `$00EC`, `$1400-$15FF` (cloud/sprite animation),
  `$1A66-$1A6C` and the stack page change on every press; the option bytes are in `$7F:B0xx`.
