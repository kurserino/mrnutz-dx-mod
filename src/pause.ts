// Pause menu (openspec/changes/pause-menu). Hook at the paused-NMI branch $80:83B8 (docs/knowledge/frame-cycle.md):
// P=$B4 (M8 X8), D=$0000, DBR=$00, entered at scanline 225 with the whole VBlank free.
// Prototype stage (tasks 1.3-1.5): open = back up BG3 map/tiles, OBJ tiles $E000, OAM and CGRAM into the WRAM
// buffer, then upload a placeholder menu (BG3 frame with transparent cells, 32 colour swatches, Mr. Nutz preview);
// Start closes = restore everything and resume. At most 2 KB of DMA per frame; DMA channel 7 is saved and restored.
import { loromToFile } from "./snes.js";

export const PAUSE_HOOK_SITE = 0x8083b8;
export const PAUSE_HOOK_ORIGINAL = "e230ad3d188d0c42"; // SEP #$30 / LDA $183D / STA $420C
export const PAUSE_ORIGIN = 0xa0a000; // code
export const PAUSE_DATA = 0xa18000; // graphics and tables (bank $A1, file 0x108000)

// WRAM: persistent menu state next to the hook state ($7F:BE00+), temporary buffer in $7F:D040-$7F:FFFF.
export const MENU_STATE = { state: 0x7fbe40, prevPad: 0x7fbe42, ch7: 0x7fbe44, scratch: 0x7fbe50 } as const;
export const MENU_BUFFER = {
  bg3Map: 0x7fd040, // 2048: VRAM $1000-$17FF
  bg3Tiles: 0x7fd840, // 2048: VRAM $3000-$37FF (BG3 tiles $300-$37F)
  objTiles: 0x7fe040, // 2048: VRAM $E000-$E7FF (OBJ name table 1 tiles $100-$13F)
  oam: 0x7fe840, // 544
  cgram: 0x7fea60, // 512
  menuOam: 0x7fec60, // 544: OAM image built for the menu
  end: 0x7fee80,
} as const;

// ROM data layout at PAUSE_DATA.
export const MENU_DATA = {
  bg3Tiles: 0xa18000, // 2048 -> VRAM $3000
  objTiles: 0xa18800, // 2048 -> VRAM $E000
  bg3Map: 0xa19000, // 2048 -> VRAM $1000
  oam: 0xa19800, // 544 template
  palBg3: 0xa19a20, // 8: BG3 palette 1 (CGRAM $04-$07)
  palObj: 0xa19a28, // 96: sprite palettes 0-2 (CGRAM $80-$AF)
  end: 0xa19a88,
} as const;

// Placeholder layout (prototype): window rows 3-26, cols 1-30 on BG3; swatch grid 8x4 at (24,72), pitch 18;
// Mr. Nutz preview centred around (196,112).
export const GRID = { x0: 24, y0: 72, pitch: 18, cols: 8, rows: 4 } as const;
export const PREVIEW = { x: 188, y: 92 } as const;
const STEPS = { idle: 9, closeFirst: 10, closeLast: 13 } as const;

const h = (v: number, d: number) => "$" + v.toString(16).toUpperCase().padStart(d, "0");
const L = (a: number) => h(a, 6);

function bgr555(r: number, g: number, b: number): number {
  return ((b >> 3) << 10) | ((g >> 3) << 5) | (r >> 3);
}

/** 32 placeholder grid colours (task 2.1 replaces them with presets/grid.json). */
export function placeholderGrid(): number[] {
  const out: number[] = [];
  for (let i = 0; i < 32; i++) {
    const hue = (i % 8) * 45;
    const light = [0.5, 0.7, 0.35, 0.85][i >> 3];
    const c = (1 - Math.abs(2 * light - 1)) * 0.9;
    const x = c * (1 - Math.abs(((hue / 60) % 2) - 1));
    const m = light - c / 2;
    const [r, g, b] = hue < 60 ? [c, x, 0] : hue < 120 ? [x, c, 0] : hue < 180 ? [0, c, x] : hue < 240 ? [0, x, c] : hue < 300 ? [x, 0, c] : [c, 0, x];
    out.push(bgr555(Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)));
  }
  return out;
}

/** Swatch colour c (0-31) -> sprite palette (0-2) and colour index (1-15). */
export function swatchSlot(c: number): { palette: number; index: number } {
  return { palette: Math.floor(c / 15), index: (c % 15) + 1 };
}

/** OBJ tile number (name table 1) of the 16x16 solid swatch for colour index k (1-15). */
export function swatchTile(k: number): number {
  const cell = k - 1; // 8 cells per 2-row band of 16 tiles
  return 0x100 + Math.floor(cell / 8) * 0x20 + (cell % 8) * 2;
}

export function buildMenuData(grid: number[] = placeholderGrid()): Buffer {
  const data = Buffer.alloc(MENU_DATA.end - PAUSE_DATA, 0);
  const off = (a: number) => a - PAUSE_DATA;
  // BG3 tiles $300 (solid colour 1) and $301 (transparent); the rest of $300-$37F blank.
  const t300 = off(MENU_DATA.bg3Tiles);
  for (let row = 0; row < 8; row++) data[t300 + row * 2] = 0xff; // plane 0 set, plane 1 clear -> colour 1
  // OBJ tiles: one solid 16x16 tile per colour index 1-15 (4bpp, 32 bytes per 8x8 tile).
  for (let k = 1; k <= 15; k++) {
    const base = swatchTile(k);
    for (const t of [base, base + 1, base + 16, base + 17]) {
      const o = off(MENU_DATA.objTiles) + (t - 0x100) * 32;
      for (let row = 0; row < 8; row++) {
        data[o + row * 2] = k & 1 ? 0xff : 0;
        data[o + row * 2 + 1] = k & 2 ? 0xff : 0;
        data[o + 16 + row * 2] = k & 4 ? 0xff : 0;
        data[o + 16 + row * 2 + 1] = k & 8 ? 0xff : 0;
      }
    }
  }
  // BG3 map: transparent everywhere; window rows 3-26 / cols 1-30 solid (palette 1, priority 1), with transparent
  // cells over the swatch grid and the preview so the sprites show through.
  const solid = 0x0300 | (1 << 10) | (1 << 13);
  const clear = 0x0301 | (1 << 13);
  for (let y = 0; y < 32; y++) {
    for (let x = 0; x < 32; x++) {
      const px = x * 8;
      const py = y * 8;
      const inWindow = y >= 3 && y <= 26 && x >= 1 && x <= 30;
      const inGrid = px >= GRID.x0 - 4 && px < GRID.x0 + GRID.cols * GRID.pitch + 2 && py >= GRID.y0 - 4 && py < GRID.y0 + GRID.rows * GRID.pitch + 2;
      const inPreview = px >= PREVIEW.x - 8 && px < PREVIEW.x + 56 && py >= PREVIEW.y - 8 && py < PREVIEW.y + 64;
      data.writeUInt16LE(inWindow && !inGrid && !inPreview ? solid : clear, off(MENU_DATA.bg3Map) + (y * 32 + x) * 2);
    }
  }
  // OAM template: 32 swatches, everything else hidden (y=$E0); high table: all small, x9 = 0.
  const oam = off(MENU_DATA.oam);
  for (let i = 0; i < 128; i++) data[oam + i * 4 + 1] = 0xe0;
  for (let c = 0; c < 32; c++) {
    const { palette, index } = swatchSlot(c);
    const tile = swatchTile(index);
    const e = oam + c * 4;
    data[e] = GRID.x0 + (c % GRID.cols) * GRID.pitch;
    data[e + 1] = GRID.y0 + Math.floor(c / GRID.cols) * GRID.pitch;
    data[e + 2] = tile & 0xff;
    data[e + 3] = 0x30 | (palette << 1) | (tile >> 8); // priority 3, palette, name table 1
  }
  // BG3 palette 1: colour 1 = dark navy frame.
  data.writeUInt16LE(bgr555(16, 24, 64), off(MENU_DATA.palBg3) + 2);
  // Sprite palettes 0-2: grid colours in entries 1-15 (entry 0 transparent).
  for (let c = 0; c < 32; c++) {
    const { palette, index } = swatchSlot(c);
    data.writeUInt16LE(grid[c], off(MENU_DATA.palObj) + palette * 32 + index * 2);
  }
  return data;
}

// One DMA on channel 7 (A8, X16 on entry and exit).
function dma(dmap: number, bbad: number, src: number, size: number): string {
  return `
    LDA #${h(dmap, 2)}
    STA $4370
    LDA #${h(bbad, 2)}
    STA $4371
    LDX #${h(src & 0xffff, 4)}
    STX $4372
    LDA #${h(src >> 16, 2)}
    STA $4374
    LDX #${h(size, 4)}
    STX $4375
    LDA #$80
    STA $420B`;
}
const vramAddr = (byteAddr: number) => `
    LDA #$80
    STA $2115
    LDX #${h(byteAddr >> 1, 4)}
    STX $2116`;
const vramRead = (byteAddr: number, dest: number, size: number) => vramAddr(byteAddr) + dma(0x81, 0x39, dest, size);
const vramWrite = (byteAddr: number, src: number, size: number) => vramAddr(byteAddr) + dma(0x01, 0x18, src, size);

/**
 * 65C816 source of pause_hook (JSL from $80:83B8). Entry: M8 X8, D=$0000, DBR=$00. Exit: M8 X8, D/DBR unchanged.
 * `nutzState` gives the addresses of the input hook's slot fields (scene slot S, private slot X).
 */
export function pauseSource(nutzState: { slotS: number; customSlot: number }): string {
  const S = MENU_STATE;
  const B = MENU_BUFFER;
  const D = MENU_DATA;
  const step = (n: number, body: string) => `
  step_${n}:
    .a8
    .i16${body}
    RTS`;
  const dispatch = Array.from({ length: STEPS.closeLast }, (_, i) => i + 1)
    .map((n) => `    CMP #${h(n, 2)}\n    BNE not_${n}\n    JSR step_${n}\n    JMP dispatched\n  not_${n}:\n    .a8\n    .i16`).join("\n");
  return `
  pause_hook:
    .a8
    .i8
    PHB
    PHK
    PLB                    ; DBR=$A0: I/O and low WRAM stay mirrored
    REP #$10
    .i16
    LDA ${L(S.state)}
    BNE ph_active
    LDA #$01               ; first paused frame: start opening
    STA ${L(S.state)}
    REP #$20
    LDA $1A6F              ; Start that paused the game is still held: it must not close the menu
    STA ${L(S.prevPad)}
    SEP #$20
  ph_active:
    .a8
    .i16
    LDA #$FF               ; hold the game's Start latch: only the menu decides when to resume
    STA $13B5
    LDX #$0000
  save_ch7:
    LDA $4370,X
    STA ${L(S.ch7)},X
    INX
    CPX #$000C
    BNE save_ch7
    LDA ${L(S.state)}
${dispatch}
  dispatched:
    .a8
    .i16
    LDX #$0000
  restore_ch7:
    LDA ${L(S.ch7)},X
    STA $4370,X
    INX
    CPX #$000C
    BNE restore_ch7
    LDA ${L(S.state)}
    BEQ hdma_back          ; menu closed this frame: HDMA as the game had it
    STZ $420C              ; HDMA off while the menu shows
    BRA ph_exit
  hdma_back:
    .a8
    .i16
    LDA $183D
    STA $420C
  ph_exit:
    .a8
    .i16
    SEP #$30
    PLB
    RTL
${step(1, vramRead(0x1000, B.bg3Map, 0x800) + next())}
${step(2, vramRead(0x3000, B.bg3Tiles, 0x800) + next())}
${step(3, vramRead(0xe000, B.objTiles, 0x800) + next())}
${step(4, `
    LDX #$0000
    STX $2102
${dma(0x80, 0x38, B.oam, 0x220)}
    STZ $2121
${dma(0x80, 0x3b, B.cgram, 0x200)}
    LDX #${h(B.menuOam & 0xffff, 4)}
    STX $2181
    LDA #${h(B.menuOam >> 16, 2)}
    STA $2183
${dma(0x00, 0x80, D.oam, 0x220)}
    JSR build_preview` + next())}
${step(5, vramWrite(0x3000, D.bg3Tiles, 0x800) + `
    STZ $2111              ; BG3 HOFS 0 (HDMA may have left another value)
    STZ $2111
    LDA #$FF               ; BG3 VOFS $03FF, the scene-init constant
    STA $2112
    LDA #$03
    STA $2112` + next())}
${step(6, vramWrite(0xe000, D.objTiles, 0x800) + next())}
${step(7, vramWrite(0x1000, D.bg3Map, 0x800) + next())}
${step(8, `
    LDA #$04
    STA $2121
${dma(0x00, 0x22, D.palBg3, 8)}
    LDA #$80
    STA $2121
${dma(0x00, 0x22, D.palObj, 96)}
    JSR preview_palette
    LDX #$0000
    STX $2102
${dma(0x00, 0x04, B.menuOam, 0x220)}` + next())}
${step(9, `
    REP #$20               ; idle: Start (new press) closes the menu
    LDA ${L(S.prevPad)}
    EOR #$FFFF
    AND $1A6F
    AND #$1000
    TAX
    LDA $1A6F
    STA ${L(S.prevPad)}
    SEP #$20
    CPX #$0000
    BEQ idle_stay
    LDA #${h(STEPS.closeFirst, 2)}
    STA ${L(S.state)}
  idle_stay:
    .a8
    .i16`)}
${step(10, vramWrite(0x1000, B.bg3Map, 0x800) + next())}
${step(11, vramWrite(0x3000, B.bg3Tiles, 0x800) + next())}
${step(12, vramWrite(0xe000, B.objTiles, 0x800) + next())}
${step(13, `
    LDX #$0000
    STX $2102
${dma(0x00, 0x04, B.oam, 0x220)}
    STZ $2121
${dma(0x00, 0x22, B.cgram, 0x200)}
    LDA #$00
    STA ${L(S.state)}      ; closed
    STZ $13B4              ; resume; $13B5 stays $FF until Start is released (gameplay path clears it)`)}

  build_preview:           ; A8 X16. Copy Mr. Nutz's OAM entries (tile < $50, name table 0, palette S or X) from
    .a8                    ; the OAM backup into menu OAM entries 32-39, moved next to the grid, palette 3.
    .i16
    LDA ${L(nutzState.slotS)}
    STA ${L(S.scratch)}        ; scratch+0 = S
    LDA ${L(nutzState.customSlot)}
    STA ${L(S.scratch + 1)}    ; scratch+1 = X ($FF = none)
    LDA #$00
    STA ${L(S.scratch + 2)}    ; scratch+2 = copied count
    LDX #$0000                 ; X = source entry offset (0..508)
  bp_loop:
    LDA ${L(B.oam + 3)},X      ; attr
    AND #$01
    BEQ bp_nt0
    JMP bp_next                ; name table 1: not Mr. Nutz
  bp_nt0:
    .a8
    .i16
    LDA ${L(B.oam + 2)},X      ; tile
    CMP #$50
    BCC bp_low
    JMP bp_next
  bp_low:
    .a8
    .i16
    LDA ${L(B.oam + 3)},X
    LSR A
    AND #$07
    CMP ${L(S.scratch)}
    BEQ bp_take
    CMP ${L(S.scratch + 1)}
    BEQ bp_take
    JMP bp_next
  bp_take:
    .a8
    .i16
    LDA ${L(S.scratch + 2)}
    BNE bp_have_origin
    LDA ${L(B.oam)},X          ; first entry fixes the offset: dx = PREVIEW.x - x, dy = PREVIEW.y - y
    EOR #$FF
    SEC
    ADC #${h(PREVIEW.x, 2)}
    STA ${L(S.scratch + 3)}
    LDA ${L(B.oam + 1)},X
    EOR #$FF
    SEC
    ADC #${h(PREVIEW.y, 2)}
    STA ${L(S.scratch + 4)}
  bp_have_origin:
    LDA ${L(S.scratch + 2)}
    CMP #$08
    BCC bp_room
    JMP bp_done                ; at most 8 entries
  bp_room:
    .a8
    .i16
    REP #$20
    AND #$00FF
    ASL A
    ASL A
    TAY                        ; Y = destination offset (entries 32+n -> +$80)
    SEP #$20
    LDA ${L(B.oam)},X
    CLC
    ADC ${L(S.scratch + 3)}
    PHX
    TYX
    STA ${L(B.menuOam + 0x80)},X
    PLX
    LDA ${L(B.oam + 1)},X
    CLC
    ADC ${L(S.scratch + 4)}
    PHX
    TYX
    STA ${L(B.menuOam + 0x81)},X
    PLX
    LDA ${L(B.oam + 2)},X
    PHX
    TYX
    STA ${L(B.menuOam + 0x82)},X
    PLX
    LDA ${L(B.oam + 3)},X
    AND #$F1                   ; keep flips and priority, palette -> 3
    ORA #$06
    PHX
    TYX
    STA ${L(B.menuOam + 0x83)},X
    PLX
    JSR bp_size                ; copy the size bit of source entry X/4 to destination entry 32+n
    LDA ${L(S.scratch + 2)}
    INC A
    STA ${L(S.scratch + 2)}
  bp_next:
    .a8
    .i16
    INX
    INX
    INX
    INX
    CPX #$0200
    BEQ bp_done
    JMP bp_loop
  bp_done:
    .a8
    .i16
    RTS

  bp_size:                     ; A8 X16. X = source offset (entry*4), scratch+2 = n. Sets the size bit of entry
    .a8                        ; 32+n in the menu OAM high table when the source entry is large.
    .i16
    PHX
    REP #$20
    TXA
    LSR A
    LSR A                      ; entry index
    PHA
    LSR A
    LSR A                      ; high-table byte
    TAX
    PLA
    AND #$0003
    ASL A
    INC A                      ; bit position of the size bit
    TAY
    SEP #$20
    LDA ${L(B.oam + 0x200)},X
  bs_shift:
    CPY #$0000
    BEQ bs_bit
    LSR A
    DEY
    BRA bs_shift
  bs_bit:
    .a8
    .i16
    AND #$01
    BEQ bs_done                ; small: menu template already has 0
    LDA ${L(S.scratch + 2)}    ; destination entry 32+n: high byte $208 + n/4, size bit (n%4)*2+1
    REP #$20
    AND #$00FF
    PHA
    LSR A
    LSR A
    TAX
    PLA
    AND #$0003
    ASL A
    INC A
    TAY
    SEP #$20
    LDA #$01
  bs_mask:
    CPY #$0000
    BEQ bs_set
    ASL A
    DEY
    BRA bs_mask
  bs_set:
    .a8
    .i16
    ORA ${L(B.menuOam + 0x208)},X
    STA ${L(B.menuOam + 0x208)},X
  bs_done:
    .a8
    .i16
    PLX
    RTS

  preview_palette:             ; A8 X16. CGRAM $B0-$BF (sprite palette 3) = Mr. Nutz's current palette from the
    .a8                        ; CGRAM backup: private slot X when set, else scene slot S.
    .i16
    LDA ${L(nutzState.customSlot)}
    CMP #$08
    BCC pp_slot
    LDA ${L(nutzState.slotS)}
    CMP #$08
    BCS pp_done
  pp_slot:
    .a8
    .i16
    REP #$20
    AND #$0007
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A                      ; slot * 32
    CLC
    ADC #$0100                 ; CGRAM byte offset of sprite palette (slot)
    TAX
    SEP #$20
    LDA #$B0
    STA $2121
    LDY #$0020
  pp_copy:
    LDA ${L(B.cgram)},X
    STA $2122
    INX
    DEY
    BNE pp_copy
  pp_done:
    .a8
    .i16
    RTS
`;
  function next(): string {
    return `
    LDA ${L(S.state)}
    INC A
    STA ${L(S.state)}`;
  }
}

export function pauseDataOffset(): number {
  return loromToFile(PAUSE_DATA);
}
