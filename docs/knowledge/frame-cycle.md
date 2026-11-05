# Frame cycle: NMI, joypad, OAM, HDMA and VBlank

## Main loop

- The main loop waits for NMI at `$80:8230-$80:8232`. The PC sits there at the end of almost every healthy frame,
  paused or not [trace] `pause-probe.log`, `trace-sram-all.log`.
- Other legitimate waits (screens without gameplay): `$9C:F830-F835` (boot delay), `$9D:AF3C-AF3D`, `$9D:C4CE-C4D1`,
  `$9D:C886-C888` [trace] `trace-sram-all.log`. A hang detector must ignore them.

## NMI

```
$80:8349  JML $80:834D          ; native NMI vector
$80:834D  REP #$FB / push A X Y D DBR
$80:8354  JMP ($01DC)           ; per-screen handler
```

- `$01DC` = **`$835B` during gameplay** [trace]. `$8357` (`JML $9D:B413`) on earlier screens (title, map, intros)
  [trace].
- Who writes the vector: `$9D:AF0C`, `$9D:C44F`, `$9D:E17D` (`$8357`); `$80:8213`, `$9D:F630` (`$835B`) [static].

### Gameplay handler `$80:835B` [static + trace]

```
$80:835B  LDA #$0000 / TCD / SEP #$30 / PHA / PLB    ; D=$0000, DBR=$00
$80:8363  INC $01DA                                  ; NMI counter
$80:8366  STZ $420C / STZ $420B / LDX $4210
$80:8370  STA $4200 (A=1)
$80:8373  LDA $13B4 / BNE $80:83B8                   ; paused?
          ... reads $2137/$213D (current scanline) and, unless the frame
          is too late (scanline $E0-$E2), JML $81:80F4 = gameplay work
$80:83B4  JML $81:80F4
```

### Gameplay work (from `$81:80F4`)

| Step | Where | Tag |
| --- | --- | --- |
| OAM upload: DMA of the `$00:0321` buffer (`$0024` bytes in use); 512 bytes in boss scenes (fixed parts in high OAM) | `$81:C367`; our `oam_hook` enters at `$81:C36A`, scanline 225-243 | [trace] `sweep-oamtiming.log` |
| HDMA enable (`$420C`) | `$81:81F6`; normally scanline 233-237, always in VBlank | [trace] `sweep-all.log` (`hdmaMaxLine`) |
| Joypad mirror: `LDA $4218 / STA $1A6F` | `$81:828A` (our `input_hook`); M16 X16 DBR=`$00` D=`$0000`; scanline 231-259, or **2** on a lag frame | [trace] `trace-hook-site.log` |
| L/R debug mode (only with `$1EC9` bit 0) | `$81:82F1-$81:8333` | [static] + [trace] |
| Start toggles the pause (`$13B4/$13B5`) | `$81:83A0` | [static] |

**VBlank budget:** the HDMA enable must happen before scanline 225 of the next frame. A hook that delayed the NMI by
about 25 scanlines made the HDMA start from stale state and write wrong colours into CGRAM (hook v2 bug,
`stage04-*.log`). Rule: heavy work goes after `$81:828A`; the critical path (`$81:C36A`) only gets a light pass. Our
limit for touching CGRAM: scanline ≤ 250.

## Pause

- **Flag:** `$7E:13B4` = `$FF` paused, `$00` playing. `$13B5` latches Start until it is released [trace]
  `pause-probe.log` + [static].
- **Paused NMI:** `$80:8376` branches to `$80:83B8` [static + trace]:

```
$80:83B8  SEP #$30 / LDA $183D / STA $420C   ; HDMA back on
$80:83C0  wait for auto-joypad ($4212)
$80:83C9  REP #$20 / LDA $421A -> $1A71 / LDA $4218 -> $1A6F
$80:83D7  BIT #$1000 (Start) -> if pressed and $13B5 == 0: unpause ($13B4 = 0)
$80:83EA  BRA $80:839E -> wait, NMI back on, RTI
```

- While paused, neither the OAM upload (`$81:C36A`) nor the gameplay joypad mirror (`$81:828A`) runs: 0 executions
  in 300 frames [trace] `pause-probe.log`. The OAM stays frozen.
- Brightness, layers and the VRAM layout do not change when pausing: the screen just freezes [trace]
  `space-survey.log`.
- **Hook point for a pause menu:** `$80:83B8`, at the start of the paused NMI, with almost all of VBlank free. From
  there the Start press can be filtered before `$80:83D7` [hypothesis: register widths and timing must be measured
  before patching].

## Joypad

- `$4218` (joypad 1) → `$7E:1A6F`; `$421A` (joypad 2) → `$7E:1A71`. Both are read in the NMI only: during gameplay
  in `$81:8284-$81:828D` (the `$4218` read is at `$81:828A`), while paused in `$80:83CB-$80:83D4` (`$4218` at
  `$80:83D1`) [trace].
- Bits (standard SNES, `$4218`): B `$8000`, Y `$4000`, Select `$2000`, Start `$1000`, Up `$0800`, Down `$0400`,
  Left `$0200`, Right `$0100`, A `$0080`, X `$0040`, L `$0020`, R `$0010`.

## Palette and scene loading

The scene PPU init (`$9D:ABA7`) runs with the screen in forced blank. Mr. Nutz's palette is only reloaded then (and on
death/respawn), not every frame [trace] `trace-palette.log`. Details in `palettes.md`.
