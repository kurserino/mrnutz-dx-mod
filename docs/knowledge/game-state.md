# Game state: lives, energy, options, pause, debug

## Player

| Address | Size | Content | Tag |
| --- | --- | --- | --- |
| `$7E:1889` | 16 bits | **Lives, obfuscated:** `lives_BCD = word($1889) XOR $A3B7`. The HUD shows the same number (`x2` = `$0002`, stored as `$A3B5`) | [trace] `watch-1889.log`, `poke-lives6281.log` |
| `$7E:05A2` | 8 bits | **Energy** (red HUD dots). 5 at the start of `stage-00`, 6 the highest seen; drops by 1 per hit and is restored on each new life | [trace] `poke-energy05A2.log` |
| `$7E:008D` | 8 bits | invulnerability: PAR `7E008D2D` | [public] |
| `$7E:0A29` | 8 bits | nuts: PAR `7E0A2999` | [public] |
| `$7E:1894` | 8 bits | coins: PAR `7E189499` | [public] |
| `$7E:05D0` | 8 bits | "one shot bosses": PAR `7E05D000` | [public] |

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

## Debug stage skip

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
- **Do not write energy outside gameplay:** `$05A2 = 1` written on frame 30 of `stage-00` (still in the stage intro)
  cleared `$1889` and left the game in a black-screen loop at `$8A:81E2` [trace] `trace-sram-go1.log`. Hypotheses:
  anti-tamper check or inconsistent state. Not investigated.
- **Start presses during boot start a game:** to reach OPTIONS, press Start only once (frame 200), then Down and Start
  on the title (`options-probe.lua`).
- **Options diff noise:** `$0000-$001F`, `$0035-$0036`, `$00EC`, `$1400-$15FF` (cloud/sprite animation),
  `$1A66-$1A6C` and the stack page change on every press; the option bytes are in `$7F:B0xx`.
