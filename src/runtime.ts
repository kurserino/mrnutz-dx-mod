// Runtime palette switch patch (OpenSpec change runtime-palette-switch).
// Evidence: docs/knowledge/ (mod-implementation.md, frame-cycle.md, palettes.md), docs/traces/*.log.

import { createHash } from "node:crypto";
import { ORIGINAL_PALETTE, hexColorToBgr555 } from "./core.js";
import { assemble } from "./asm.js";
import { buildManifestPatch } from "./manifest.js";
import type { ManifestEntry, ManifestPatch, PatchManifest } from "./manifest.js";
import { loromToFile } from "./snes.js";
import { MENU_STATE, PAUSE_DATA, PAUSE_HOOK_ORIGINAL, PAUSE_HOOK_SITE, PAUSE_ORIGIN, buildMenuData, pauseSource } from "./pause.js";

export interface RuntimePresetFile {
  fur: { name: string; colors: string[] }[];
  outfit: { name: string; colors: string[] }[];
}

export const EXPANDED_SIZE = 0x200000; // 2 MiB LoROM: new banks $A0-$BF (file 0x100000-0x1FFFFF)
export const HOOK_SITE = 0x81828a; // LDA $4218 / STA $1A6F, gameplay NMI, M16 X16 DBR=$00 (trace-hook-site.log)
export const HOOK_ORIGINAL = "AD18428D6F1A";
export const CODE_ORIGIN = 0xa08000;
export const FUR_TABLE = 0xa09000;
export const OUTFIT_TABLE = 0xa09080;
export const ATTR_PAL = 0xa09100; // 256 bytes: OAM attr -> palette (0-7), $FF for name table 1
export const ATTR_BIT = 0xa09200; // 256 bytes: OAM attr -> 1 << palette
// OAM upload ($81:C367, called from $81:C363): LDA #$4300 / TCD, right before the OAM DMA (sweep-oamtiming.log)
export const OAM_HOOK_SITE = 0x81c36a;
export const OAM_HOOK_ORIGINAL = "A900435B";
// End of the gameplay frame work (JSL $8A8134, then wait for the end of VBlank, NMI on, RTI): the OAM buffer for the
// next frame is complete here, in active display, long before the next NMI (docs/traces/probe-frame-hook.log:
// M8 X8, D=$0000, DBR=$00, once per gameplay frame; lines 94-162 in the Mr. Blizzard breath, franken-order.log).
export const FRAME_HOOK_SITE = 0x818569;
export const FRAME_HOOK_ORIGINAL = "2234818A";
const FRAME_HOOK_CALL = 0x8a8134; // relocated call
// Stage Clear init: [$055E] = $82:D474 (constant), then JSL $9DABA7 (scene init, palettes loaded in forced blank).
// After it returns the game writes no sprite palette until the screen ends; Mr. Nutz is the only object drawn with
// $85:9CC0 there (slot 4; chest on 5, coins on 1) (stage-clear-colours, sc-init-witch.log, sc-witch.log, sc-blizzard.log).
export const CLEAR_HOOK_SITE = 0x9de452;
export const CLEAR_HOOK_ORIGINAL = "22A7AB9D";
const CLEAR_HOOK_CALL = 0x9daba7; // relocated call
const NUTZ_LIST_MAX = 16;
// WRAM $7FB6C0-$7FBFFF had no read or write during the whole game, credits, soft reset and boot
// (docs/traces/sweep-wram.log). The previous block at $7FFFF0 is cleared by the game on some world changes.
export const STATE = {
  magic: 0x7fbe00, furIndex: 0x7fbe02, outfitIndex: 0x7fbe03, prevPad: 0x7fbe04,
  customSlot: 0x7fbe06, slotS: 0x7fbe07, tmp: 0x7fbe08,
  stickyMask: 0x7fbe09, // palettes of other objects in high OAM (past the bytes in use: boss parts), kept for the scene
  tablePtr: 0x7fbe0a, // 3 bytes: last seen [$055E]/$0560
  ready: 0x7fbe0d, readyStamp: 0x7fbe0e, // private slot ready, $01DA when the manager last ran
  scanPos: 0x7fbe0f, passes: 0x7fbe10, // incremental OAM buffer scan
  sBits: 0x7fbe11, xBits: 0x7fbe12, // slot S / X shifted to the OAM attr palette field
  expC6: 0x7fbe14, expCF: 0x7fbe16, // selected colours expected at X+6 / X+15
  applied: 0x7fbe18, // 3 bytes: slot, fur, outfit of the last colour upload ($FF slot = none)
  tile: 0x7fbe1b, // scan_chunk scratch
  pending: 0x7fbe20, // bit0: upload the selection into X, bit1: give X its scene palette back (done by oam_hook)
  passMask: 0x7fbe1c, // palettes of other dynamic objects in the current pass
  prevMask: 0x7fbe1d, // ... in the previous pass. Busy slots = stickyMask | prevMask | passMask
  entryOff: 0x7fbe1e, // scan_chunk: byte offset of the entry being read
  // frame_hook remap (fix-vblank-check-race): attr -> class table for the current S/X, Mr. Nutz entry list
  classTbl: 0x7fbc00, // 256 bytes: 0 other, 1 palette S name table 0, 2 palette X name table 0, 3 palette X name table 1
  list: 0x7fbd00, // NUTZ_LIST_MAX words: OAM buffer offsets of Mr. Nutz entries found this frame
  limit: 0x7fbd20, // word: OAM buffer bytes in use ($0024) copied for the frame_hook scan (DBR=$7F there)
  listCount: 0x7fbd28, // Mr. Nutz entries in list
  classKey: 0x7fbd29, // S * 16 + X the class table was built for ($FF = none)
  layout: 0x7fbd2a, // STATE_LAYOUT once the fields above were initialized (v0.2.0 WRAM, e.g. a savestate, has garbage here)
  conflict: 0x7fbd2b, // frame_hook saw another object on palette X in the buffer
  anyGroup: 0x7fbd2c, // fix-private-slot-choice: 1 when the scene is in CROSS_GROUP_SCENES (set on each scene reset)
}
const STATE_LAYOUT = 0x03;
// Scene tables ([$055E]/$0560) whose sprites never take part in colour math (CGADSUB bit 4 off for the whole scene),
// so a private slot of the other colour-math group looks the same (fix-private-slot-choice, scenepal-*.log).
export const CROSS_GROUP_SCENES = [
  0x82d58c, // witch fight (stage-08): $2131 = $20 (backdrop only); palettes 2-7 used by other objects
  0x82d620, // spider (stage-04): $2131 = $00 / $2F (BG1-4 + backdrop)
];
// While [$13BC] is non-zero (every stage seen), $81:C3E8 writes an animated colour into CGRAM $91 (sprite palette 1,
// entry 1) every frame, so palette 1 can never be the private slot (cgw-slot2b.log, cgadsub-*.log).
const ANIMATED_SLOT = 1;
const ANIMATED_SLOT_POINTER = 0x13bc;
// Mr. Nutz palette source; the scene's 8-entry sprite palette table at [$055E] decides its CGRAM slot
// (slot 4 = $C0 in most scenes, slot 0 = $80 in the stage traced in docs/traces/sweep-debug10.log).
export const NUTZ_PALETTE_CPU = 0x859cc0;
const MAGIC = 0x5a4e; // "NZ"
// Save record in battery-backed SRAM (openspec/changes/archive/2026-11-05-sram-persistence, design D3). 8 bytes at $70:0100, away from
// every address the anti-copier checks use ($0000-0001, $0004, $0034, $00A9-00AA, $0345-0348):
// +0 magic "NZ" (16-bit), +2 version, +3 fur, +4 outfit, +5 reserved, +6 checksum = $FFFF ^ (w0 + w2 + w4).
export const SAVE_RECORD = { address: 0x700100, magic: MAGIC, version: 0x01, size: 8 } as const;

export function saveRecordChecksum(record: Buffer): number {
  return ((record.readUInt16LE(0) + record.readUInt16LE(2) + record.readUInt16LE(4)) & 0xffff) ^ 0xffff;
}

export function encodeSaveRecord(fur: number, outfit: number): Buffer {
  const r = Buffer.alloc(SAVE_RECORD.size);
  r.writeUInt16LE(SAVE_RECORD.magic, 0);
  r[2] = SAVE_RECORD.version;
  r[3] = fur;
  r[4] = outfit;
  r[5] = 0;
  r.writeUInt16LE(saveRecordChecksum(r), 6);
  return r;
}

/** Mirrors load_save in the hook: undefined when the record is absent/corrupt; out-of-range indices become 0. */
export function decodeSaveRecord(record: Buffer, furCount: number, outfitCount: number): { fur: number; outfit: number } | undefined {
  if (record.length < SAVE_RECORD.size) return undefined;
  if (record.readUInt16LE(0) !== SAVE_RECORD.magic || record[2] !== SAVE_RECORD.version) return undefined;
  if (record.readUInt16LE(6) !== saveRecordChecksum(record)) return undefined;
  return { fur: record[3] < furCount ? record[3] : 0, outfit: record[4] < outfitCount ? record[4] : 0 };
}
const MAX_PRESETS = 12;
const LAST_SAFE_SCANLINE = 250; // leave >= 11 VBlank lines for the remaining NMI work
const FIRST_VBLANK_SCANLINE = 225; // NTSC VBlank starts at line 225; a smaller latched V means VBlank already ended
// Reading OAM through $2138 is safe up to the end of VBlank; input_hook runs after the game's HDMA enable, so a read
// there delays nothing the game needs in VBlank. CGRAM writes keep the stricter LAST_SAFE_SCANLINE.
const OAM_READ_LAST_SCANLINE = 257;
// frame_hook scans the whole buffer (up to 128 entries, ~13 lines): it only starts before this line so it always ends
// before the next NMI at line 225 and never makes the game miss a frame.
const FRAME_HOOK_LAST_SCANLINE = 205;

const h = (v: number, digits: number) => "$" + v.toString(16).toUpperCase().padStart(digits, "0");

export function buildTables(presets: RuntimePresetFile): { fur: Buffer; outfit: Buffer; furCount: number; outfitCount: number } {
  const furCount = presets.fur.length + 1;
  const outfitCount = presets.outfit.length + 1;
  if (furCount > MAX_PRESETS || outfitCount > MAX_PRESETS) throw new Error(`At most ${MAX_PRESETS - 1} presets per group`);
  const encode = (colors: string[], n: number, label: string) => {
    if (colors.length !== n) throw new Error(`${label}: expected ${n} colors`);
    const b = Buffer.alloc(n * 2);
    colors.forEach((c, i) => b.writeUInt16LE(hexColorToBgr555(c), i * 2));
    return b;
  };
  // Index 0 = original ROM bytes: outfit $C6-$C9 (offset 12), fur $CB-$CF (offset 22).
  const fur = Buffer.concat([ORIGINAL_PALETTE.subarray(22, 32), ...presets.fur.map((p) => encode(p.colors, 5, p.name))]);
  const outfit = Buffer.concat([ORIGINAL_PALETTE.subarray(12, 20), ...presets.outfit.map((p) => encode(p.colors, 4, p.name))]);
  return { fur, outfit, furCount, outfitCount };
}

/**
 * 65C816 source of both hooks.
 * - input_hook: JSL from HOOK_SITE ($81:828A, gameplay NMI, after the OAM DMA and the HDMA enable, M16 X16,
 *   DBR=$00): Select+L/R, then the non-critical manager: scene tracking, incremental OAM buffer scan (16 of the
 *   128 entries per frame) into the scene's stickyMask, private slot choice, colour upload, "ready" flag.
 * - oam_hook: JSL from OAM_HOOK_SITE ($81:C36A, inside the OAM upload before its DMA, scanline 225-243). Critical
 *   path, kept short: only when the manager marked the private slot ready in the previous frame, a light pass over
 *   the used OAM bytes moves Mr. Nutz's entries (tile < $50, name table 0, palette S or X) to X. Another object
 *   on X makes X get its scene palette back at once (still in VBlank) and Mr. Nutz stays original that frame.
 * The slot S of the scene table is never written, so every object sharing the Nutz palette keeps its colours.
 */
export function hookSource(furCount: number, outfitCount: number): string {
  const L = (a: number) => h(a, 6);
  const A = (a: number) => h(a & 0xffff, 4);
  const S = STATE;
  return `
  input_hook:
    .a16
    .i16
    LDA $4218              ; relocated original instructions (DBR=$00 here)
    STA $1A6F
    PHP
    PHX
    PHY
    PHB
    PHK
    PLB                    ; DBR=$A0: I/O and low WRAM stay mirrored, tables are absolute
    REP #$30
    LDA ${L(S.magic)}      ; one-time state init (WRAM is not cleared for us)
    CMP #${h(MAGIC, 4)}
    BEQ ready
    LDA #$0000
    STA ${L(S.furIndex)}   ; fur and outfit index = 0 (original)
    STA ${L(S.prevPad)}
    JSR load_save          ; power-on: a valid SRAM record overrides the 0/0 default
    LDA #$FFFF
    STA ${L(S.customSlot)} ; customSlot = slotS = $FF
    STA ${L(S.tablePtr)}   ; impossible table pointer: the manager resets the scene state on its first run
    SEP #$20
    STA ${L(S.tablePtr + 2)}
    LDA #$00
    STA ${L(S.ready)}
    STA ${L(S.layout)}     ; new fields: initialized by the layout check below
    REP #$20
    LDA #${h(MAGIC, 4)}
    STA ${L(S.magic)}
  ready:
    SEP #$20
    LDA ${L(MENU_STATE.state)} ; pause menu state left over (soft reset, unexpected resume): drop it
    BEQ no_menu
    LDA #$00
    STA ${L(MENU_STATE.state)}
  no_menu:
    REP #$20
    SEP #$20               ; state fields added after v0.2.0: initialize once (magic already set by an older build)
    LDA ${L(S.layout)}
    CMP #${h(STATE_LAYOUT, 2)}
    BEQ layout_ok
    LDA #${h(STATE_LAYOUT, 2)}
    STA ${L(S.layout)}
    LDA #$FF
    STA ${L(S.classKey)}
    STA ${L(S.tablePtr + 2)} ; impossible bank: the manager resets the scene state (anyGroup included) next run
    LDA #$00
    STA ${L(S.listCount)}
    STA ${L(S.conflict)}
    STA ${L(S.anyGroup)}
  layout_ok:
    REP #$20
    LDA $1A6F              ; pressed = (cur ^ prev) & cur
    EOR ${L(S.prevPad)}
    AND $1A6F
    TAY
    LDA $1A6F
    STA ${L(S.prevPad)}
    AND #$2000             ; Select held
    BEQ input_done
    TYA
    AND #$0020             ; L newly pressed: next fur
    BEQ check_r
    SEP #$20
    LDA ${L(S.furIndex)}
    INC A
    CMP #${h(furCount, 2)}
    BCC fur_ok
    LDA #$00
  fur_ok:
    STA ${L(S.furIndex)}
    JSR write_save
    REP #$20
  check_r:
    TYA
    AND #$0010             ; R newly pressed: next outfit
    BEQ input_done
    SEP #$20
    LDA ${L(S.outfitIndex)}
    INC A
    CMP #${h(outfitCount, 2)}
    BCC outfit_ok
    LDA #$00
  outfit_ok:
    STA ${L(S.outfitIndex)}
    JSR write_save
  input_done:
    REP #$30
    JSR manage
    REP #$30
    PLB
    PLY
    PLX
    PLP
    RTL

  load_save:               ; A16 X16 in and out. Copies a valid SRAM record into the WRAM indices.
    .a16
    .i16
    LDA ${L(SAVE_RECORD.address)}
    CMP #${h(MAGIC, 4)}
    BNE ls_done
    LDA ${L(SAVE_RECORD.address + 2)}
    AND #$00FF
    CMP #${h(SAVE_RECORD.version, 4)}
    BNE ls_done
    LDA ${L(SAVE_RECORD.address)}
    CLC
    ADC ${L(SAVE_RECORD.address + 2)}
    CLC
    ADC ${L(SAVE_RECORD.address + 4)}
    EOR #$FFFF
    CMP ${L(SAVE_RECORD.address + 6)}
    BNE ls_done
    SEP #$20
    LDA ${L(SAVE_RECORD.address + 3)}
    CMP #${h(furCount, 2)}
    BCS ls_outfit          ; out of range: keep 0 (original)
    STA ${L(S.furIndex)}
  ls_outfit:
    LDA ${L(SAVE_RECORD.address + 4)}
    CMP #${h(outfitCount, 2)}
    BCS ls_wide
    STA ${L(S.outfitIndex)}
  ls_wide:
    REP #$20
  ls_done:
    RTS

  write_save:              ; any width in, restored on exit. Payload first, checksum last.
    PHP
    SEP #$20
    LDA #${h(SAVE_RECORD.version, 2)}
    STA ${L(SAVE_RECORD.address + 2)}
    LDA ${L(S.furIndex)}
    STA ${L(SAVE_RECORD.address + 3)}
    LDA ${L(S.outfitIndex)}
    STA ${L(SAVE_RECORD.address + 4)}
    LDA #$00
    STA ${L(SAVE_RECORD.address + 5)}
    REP #$20
    LDA #${h(MAGIC, 4)}
    STA ${L(SAVE_RECORD.address)}
    CLC
    ADC ${L(SAVE_RECORD.address + 2)}
    CLC
    ADC ${L(SAVE_RECORD.address + 4)}
    EOR #$FFFF
    STA ${L(SAVE_RECORD.address + 6)}
    PLP
    RTS

  manage:                  ; non-critical part, once per gameplay frame
    .a16
    .i16
    SEP #$20
    LDA $01DA              ; NMI frame counter: stamp of the frame this manager ran in
    STA ${L(S.readyStamp)}
    REP #$20
    JSR track_scene        ; C=1: scene changed but X could not be restored yet (not in VBlank)
    BCS m_off
    SEP #$20
    LDA ${L(S.slotS)}
    CMP #$FF
    BEQ m_off              ; Mr. Nutz palette not in this scene's table
    JSR scan_chunk
    REP #$20
    LDA ${L(S.furIndex)}   ; fur and outfit both original: no private slot
    BNE m_selected
    JSR drop_custom
    BRA m_off
  m_selected:
    .a16
    SEP #$20
    LDA ${L(S.passes)}     ; a full pass over the 128 entries since the scene changed
    BEQ m_off
    REP #$20
    JSR choose_slot
    BCS m_off
    JSR prepare_colors     ; expected colours; upload left to oam_hook (always early in VBlank)
    SEP #$20
    JSR build_classes      ; class table for this S/X before oam_hook may use it
    LDA ${L(S.customSlot)}
    ASL A
    STA ${L(S.xBits)}
    LDA #$01
    STA ${L(S.ready)}
    REP #$20
    RTS
  m_off:
    SEP #$20
    LDA #$00
    STA ${L(S.ready)}
    REP #$20
    RTS

  track_scene:             ; A16. New scene table pointer: reset the per-scene state. C=1 if deferred
    .a16
    .i16
    LDA $055E
    CMP ${L(S.tablePtr)}
    BNE ts_new
    SEP #$20
    LDA $0560
    CMP ${L(S.tablePtr + 2)}
    REP #$20
    BNE ts_new
    CLC
    RTS
  ts_new:
    SEP #$20
    LDA ${L(S.customSlot)}
    CMP #$FF
    BEQ ts_reset
    JSR vblank_ok          ; X back to the new scene's palette before it can be shown
    BCC ts_restore
    REP #$20               ; deferred: C=1
    RTS
  ts_restore:
    .a8
    REP #$20
    JSR restore_custom
  ts_reset:
    REP #$20
    LDA $055E
    STA ${L(S.tablePtr)}
    SEP #$20
    LDA $0560
    STA ${L(S.tablePtr + 2)}
    LDA #$00
    STA ${L(S.stickyMask)}
    STA ${L(S.passMask)}
    STA ${L(S.prevMask)}
    STA ${L(S.scanPos)}
    STA ${L(S.passes)}
    STA ${L(S.ready)}
    LDA #$FF
    STA ${L(S.classKey)}
    STA ${L(S.customSlot)}
    STA ${L(S.slotS)}
    LDA #$00               ; anyGroup = 1 for the scene tables with sprite colour math off
    STA ${L(S.anyGroup)}
    REP #$20
${CROSS_GROUP_SCENES.map((t, i) => `    LDA $055E
    CMP #${A(t)}
    BNE ag_next${i}
    SEP #$20
    LDA $0560
    CMP #${h(t >> 16, 2)}
    REP #$20
    BNE ag_next${i}
    SEP #$20
    LDA #$01
    STA ${L(S.anyGroup)}
    REP #$20
    BRA ag_done
  ag_next${i}:
    .a16`).join("\n")}
  ag_done:
    .a16
    JSR find_slot
    CLC
    RTS

  find_slot:               ; A16. slotS/sBits = palette (0-7) holding $85:9CC0 in the scene table, if any
    .a16
    .i16
    LDX $055E              ; table address (WRAM mirror, DBR=$A0)
    PHB
    SEP #$20
    LDA $0560              ; table bank
    PHA
    PLB
    REP #$20
    LDY #$0000
  slot_loop:
    LDA $0000,X
    CMP #${A(NUTZ_PALETTE_CPU)}
    BNE slot_next
    LDA $0002,X
    AND #$00FF
    CMP #${h(NUTZ_PALETTE_CPU >> 16, 4)}
    BEQ slot_found
  slot_next:
    INX
    INX
    INX
    INX
    INY
    CPY #$0008
    BNE slot_loop
    PLB
    RTS
  slot_found:
    PLB
    SEP #$20
    TYA
    STA ${L(S.slotS)}
    ASL A
    STA ${L(S.sBits)}
    REP #$20
    RTS

  scan_chunk:              ; A8 in/out. 16 PPU OAM entries per frame (VBlank only): palettes of other objects -> stickyMask
    .a8
    .i16
    ; The WRAM buffer at $0321 holds stale entries past the bytes in use; the PPU OAM is the truth
    ; (cleared entries have y=$E0, boss parts uploaded once stay there). Read it through $2138.
    JSR oam_read_ok
    BCC sc_go
    LDA ${L(S.passes)}     ; no PPU access (e.g. the iris-in runs the frame out of VBlank): before the first full
    BNE sc_skip            ; pass of the scene, scan the game's WRAM buffer instead so a slot can be chosen
    JMP scan_wram
  sc_skip:
    RTS
  sc_go:
    REP #$20
    LDA ${L(S.scanPos)}
    AND #$007F
    ASL A                  ; OAM word address of the entry
    STA $2102
    ASL A
    STA ${L(S.entryOff)}    ; byte offset = OAM word address * 2
    LDA #$0000             ; B = 0 for the A8 TAX/TAY below
    SEP #$20
    LDA #$80               ; up to 16 entries, never past entry 127 (the high table follows)
    SEC
    SBC ${L(S.scanPos)}
    CMP #$10
    BCC sc_count
    LDA #$10
  sc_count:
    STA ${L(S.tmp)}
  sc_loop:
    LDA $2138              ; x (unused)
    LDA $2138              ; y
    TAX
    LDA $2138              ; tile
    STA ${L(S.tile)}
    LDA $2138              ; attr
    TAY
    REP #$20
    LDA ${L(S.entryOff)}
    CMP $0026              ; past the bytes uploaded each frame: static entries (boss parts)
    SEP #$20
    BCS sc_static
    CPX #$00E0             ; hidden dynamic entry (the game clears unused OAM to $E0)
    BEQ sc_next
    LDA ${L(S.tile)}
    CMP #$50
    BCS sc_other
    LDA ${A(ATTR_PAL)},Y   ; palette, or $FF for name table 1
    CMP ${L(S.slotS)}
    BEQ sc_next            ; Mr. Nutz entry
    CMP ${L(S.customSlot)}
    BEQ sc_next            ; Mr. Nutz entry already on X
  sc_other:
    LDA ${A(ATTR_BIT)},Y
    ORA ${L(S.passMask)}
    STA ${L(S.passMask)}
    BRA sc_next
  sc_static:               ; static entries are not seen by oam_hook: keep their palettes for the whole scene,
    CPX #$00E0             ; hidden ones included (they can be shown again without an upload we see), except the
    BNE sc_static_live     ; game's cleared pattern y = tile = attr = $E0 (attr $E0 reads as palette 0; witch fight,
    CPY #$00E0             ; oamdump-08.log)
    BNE sc_static_live
    LDA ${L(S.tile)}
    CMP #$E0
    BEQ sc_next
  sc_static_live:
    LDA ${L(S.tile)}
    CMP #$50
    BCS sc_static_mark
    LDA ${A(ATTR_PAL)},Y
    CMP ${L(S.slotS)}
    BEQ sc_next
  sc_static_mark:
    LDA ${A(ATTR_BIT)},Y
    ORA ${L(S.stickyMask)}
    STA ${L(S.stickyMask)}
  sc_next:
    REP #$20
    LDA ${L(S.entryOff)}
    CLC
    ADC #$0004
    STA ${L(S.entryOff)}
    LDA #$0000             ; B = 0 again for the A8 TAX/TAY of the next entry
    SEP #$20
    LDA ${L(S.tmp)}
    DEC A
    STA ${L(S.tmp)}
    BEQ sc_end
    BIT #$03               ; every 4 entries: stop before the reads could leave VBlank, resume next frame
    BNE sc_more
    JSR read_vcount
    .a16
    CMP #${h(OAM_READ_LAST_SCANLINE + 1, 4)}
    LDA #$0000
    SEP #$20
    BCS sc_end
  sc_more:
    JMP sc_loop            ; loop body is longer than a branch reaches
  sc_end:
    .a8
    REP #$20
    LDA $0026              ; restore OAMADD as the game leaves it ($81:C3AF: entries in use / 2)
    LSR A
    STA $2102
    LDA ${L(S.entryOff)}   ; next entry = byte offset / 4 (the chunk may have stopped early)
    LSR A
    LSR A
    SEP #$20
    AND #$7F
    STA ${L(S.scanPos)}
    BNE sc_done
    LDA ${L(S.passMask)}  ; pass complete: it becomes the previous pass (dynamic objects that left free their slot)
    STA ${L(S.prevMask)}
    LDA #$00
    STA ${L(S.passMask)}
    LDA #$01
    STA ${L(S.passes)}
  sc_done:
    SEP #$20
    RTS

  scan_wram:               ; A8 in/out. Fallback of scan_chunk: 16 entries of the WRAM OAM buffer $7E:0321, which the
    .a8                    ; game uploads every frame ($0024 bytes in use). Entries past those bytes are left to the
    .i16                   ; PPU scan (boss parts); frame_hook still unmaps Mr. Nutz if another object shows up on X.
    REP #$20
    LDA ${L(S.scanPos)}
    AND #$007F
    ASL A
    ASL A
    TAX                    ; X = byte offset of the entry
    LDA #$0000             ; B = 0 for the A8 TAY below
    SEP #$20
    LDA #$80               ; up to 16 entries, never past entry 127
    SEC
    SBC ${L(S.scanPos)}
    CMP #$10
    BCC sw_count
    LDA #$10
  sw_count:
    STA ${L(S.tmp)}
  sw_loop:
    REP #$20
    TXA
    CMP $0024              ; past the bytes in use: unknown here
    LDA #$0000
    SEP #$20
    BCS sw_next
    LDA $7E0322,X          ; y
    CMP #$E0
    BEQ sw_next            ; hidden entry
    LDA $7E0324,X          ; attr
    TAY
    LDA $7E0323,X          ; tile
    CMP #$50
    BCS sw_other
    LDA ${A(ATTR_PAL)},Y   ; palette, or $FF for name table 1
    CMP ${L(S.slotS)}
    BEQ sw_next            ; Mr. Nutz entry
    CMP ${L(S.customSlot)}
    BEQ sw_next
  sw_other:
    LDA ${A(ATTR_BIT)},Y
    ORA ${L(S.passMask)}
    STA ${L(S.passMask)}
  sw_next:
    INX
    INX
    INX
    INX
    LDA ${L(S.tmp)}
    DEC A
    STA ${L(S.tmp)}
    BNE sw_loop
    REP #$20
    TXA
    LSR A
    LSR A
    SEP #$20
    AND #$7F
    STA ${L(S.scanPos)}
    BNE sw_done
    LDA ${L(S.passMask)}   ; pass complete, as in scan_chunk
    STA ${L(S.prevMask)}
    LDA #$00
    STA ${L(S.passMask)}
    LDA #$01
    STA ${L(S.passes)}
  sw_done:
    SEP #$20
    RTS

  drop_custom:             ; A16. Selection back to original: X gets its scene palette back (in VBlank)
    .a16
    .i16
    SEP #$20
    LDA ${L(S.customSlot)}
    CMP #$FF
    BEQ dc_done
    LDA ${L(S.pending)}
    ORA #$02
    STA ${L(S.pending)}
  dc_done:
    REP #$20
    RTS

  choose_slot:             ; A16. Keep X if still free, else the first free slot in S's colour-math group. C=1: none
    .a16
    .i16
    LDA #$0000             ; B = 0 for the A8 TAY in slot_is_free
    SEP #$20
    LDA ${L(S.customSlot)}
    CMP #$FF
    BEQ ch_new
    JSR slot_is_free
    BCC ch_keep
    JSR vblank_ok          ; X is needed by another object: restore it first
    BCS ch_fail
    REP #$20
    JSR restore_custom
    .a16
    LDA #$0000
    SEP #$20
  ch_new:
    LDA ${L(S.slotS)}
    AND #$04
  ch_loop:
    JSR slot_is_free       ; leaves the candidate in tmp
    BCC ch_take
    LDA ${L(S.tmp)}
    INC A
    BIT #$03
    BNE ch_loop
    LDA ${L(S.anyGroup)}   ; same group full: scenes without sprite colour math may use the other group
    BEQ ch_fail
    LDA ${L(S.slotS)}
    AND #$04
    EOR #$04
  ch_other:
    JSR slot_is_free
    BCC ch_take
    LDA ${L(S.tmp)}
    INC A
    BIT #$03
    BNE ch_other
  ch_fail:
    .a8
    REP #$20
    SEC
    RTS
  ch_take:
    .a8
    STA ${L(S.customSlot)}
  ch_keep:
    REP #$20
    CLC
    RTS

  slot_is_free:            ; A8 = candidate, B = 0. C=0 and A=candidate if != S, same group (or anyGroup), not
    .a8                    ; animated by the game, unused in the scene
    .i16
    STA ${L(S.tmp)}
    CMP ${L(S.slotS)}
    BEQ not_free
    EOR ${L(S.slotS)}
    AND #$04
    BEQ sf_group_ok
    LDA ${L(S.anyGroup)}
    BEQ not_free
  sf_group_ok:
    LDA ${L(S.tmp)}
    CMP #${h(ANIMATED_SLOT, 2)}
    BNE sf_not_animated
    LDA ${A(ANIMATED_SLOT_POINTER)} ; $81:C3E8 animates CGRAM $91 while this word is non-zero
    ORA ${A(ANIMATED_SLOT_POINTER + 1)}
    BNE not_free
  sf_not_animated:
    LDA ${L(S.tmp)}
    ASL A
    TAY
    LDA ${A(ATTR_BIT)},Y   ; 1 << candidate
    AND ${L(S.stickyMask)}
    BNE not_free
    LDA ${A(ATTR_BIT)},Y
    AND ${L(S.passMask)}
    BNE not_free
    LDA ${A(ATTR_BIT)},Y
    AND ${L(S.prevMask)}
    BNE not_free
    LDA ${L(S.tmp)}
    CLC
    RTS
  not_free:
    LDA ${L(S.tmp)}
    SEC
    RTS

  vblank_ok:               ; C=0 when PPU access is safe now: latched V in ${FIRST_VBLANK_SCANLINE}..${LAST_SAFE_SCANLINE}; returns A8
    SEP #$20               ; (the $4212 flag alone races: read at line 261, latch at line 0 -> V=0 in active display)
    LDA $4212
    BPL vb_no
    JSR read_vcount
    .a16
    CMP #${h(LAST_SAFE_SCANLINE + 1, 4)}
    BRA vb_range
  oam_read_ok:             ; same check for OAM reads ($2138): V in ${FIRST_VBLANK_SCANLINE}..${OAM_READ_LAST_SCANLINE}
    .a8
    LDA $4212
    BPL vb_no
    JSR read_vcount
    .a16
    CMP #${h(OAM_READ_LAST_SCANLINE + 1, 4)}
  vb_range:
    .a16
    BCS vb_no16
    CMP #${h(FIRST_VBLANK_SCANLINE, 4)}
    BCC vb_no16
    SEP #$20
    CLC
    RTS
  vb_no16:
    SEP #$20
  vb_no:
    .a8
    SEC
    RTS

  read_vcount:             ; A8 in, A16 out = latched V counter (9 bits). Long addressing: works with any DBR
    .a8
    LDA $00213F            ; reset the counter latch flip-flop
    LDA $002137            ; latch H/V counters
    LDA $00213D
    XBA
    LDA $00213D
    AND #$01
    XBA
    REP #$20
    RTS

  build_classes:           ; A8 X16 in/out. Class table for the current S/X (rebuilt only when they changed)
    .a8
    .i16
    LDA ${L(S.slotS)}
    ASL A
    ASL A
    ASL A
    ASL A
    ORA ${L(S.customSlot)}
    CMP ${L(S.classKey)}
    BEQ bc_done
    STA ${L(S.classKey)}
    LDX #$0000
  bc_loop:
    TXA                    ; attr = low byte of X
    AND #$0E
    LSR A
    CMP ${L(S.customSlot)}
    BEQ bc_x
    CMP ${L(S.slotS)}
    BEQ bc_s
    LDA #$00
    BRA bc_put
  bc_x:
    TXA
    AND #$01
    ORA #$02               ; 2: palette X name table 0, 3: palette X name table 1
    BRA bc_put
  bc_s:
    TXA
    AND #$01
    EOR #$01               ; 1: palette S name table 0, 0: palette S name table 1 (not Mr. Nutz)
  bc_put:
    STA ${L(S.classTbl)},X
    INX
    CPX #$0100
    BNE bc_loop
  bc_done:
    RTS

  prepare_colors:          ; A16. Expected colours of the selection; pending upload when slot/fur/outfit changed
    .a16
    .i16
    JSR offsets            ; X = outfit offset, Y = fur offset
    LDA ${A(OUTFIT_TABLE)},X
    STA ${L(S.expC6)}
    LDA ${A(FUR_TABLE + 8)},Y
    STA ${L(S.expCF)}
    SEP #$20
    LDA ${L(S.customSlot)}
    CMP ${L(S.applied)}
    BNE pc_pending
    LDA ${L(S.furIndex)}
    CMP ${L(S.applied + 1)}
    BNE pc_pending
    LDA ${L(S.outfitIndex)}
    CMP ${L(S.applied + 2)}
    BEQ pc_done
  pc_pending:
    LDA ${L(S.pending)}
    ORA #$01
    STA ${L(S.pending)}
  pc_done:
    REP #$20
    RTS

  read_cgram:              ; returns A16 = colour at the current CGRAM address (bit 15 is PPU2 open bus)
    .i16
    SEP #$20
    LDA $213B
    XBA
    LDA $213B
    XBA
    REP #$20
    AND #$7FFF
    RTS

  offsets:                 ; A16. X = outfitIndex*8, Y = fur table offset
    .a16
    .i16
    LDA ${L(S.outfitIndex)}
    AND #$00FF
    ASL A
    ASL A
    ASL A
    TAX
    LDA ${L(S.furIndex)}
    AND #$00FF
    TAY
    SEP #$20
    LDA ${A(FUR_TABLE + 0x70)},Y
    REP #$20
    AND #$00FF
    TAY
    RTS

  put_custom:              ; X = outfit offset, Y = fur offset: Nutz palette with the selection into slot X
    .i16
    SEP #$20
    LDA ${L(S.customSlot)}
    ASL A
    ASL A
    ASL A
    ASL A
    ORA #$80
    STA $2121
    PHX
    LDX #$0000
  base_loop:               ; entries 0-5 from the ROM palette
    LDA ${L(NUTZ_PALETTE_CPU)},X
    STA $2122
    INX
    CPX #$000C
    BNE base_loop
    PLX
${Array.from({ length: 8 }, () => `    LDA ${A(OUTFIT_TABLE)},X\n    STA $2122\n    INX`).join("\n")}
    LDA ${L(NUTZ_PALETTE_CPU + 20)}
    STA $2122
    LDA ${L(NUTZ_PALETTE_CPU + 21)}
    STA $2122
    TYX
${Array.from({ length: 10 }, () => `    LDA ${A(FUR_TABLE)},X\n    STA $2122\n    INX`).join("\n")}
    REP #$20
    RTS

  restore_custom:          ; copy the scene table palette of slot X back into CGRAM; customSlot = $FF; returns A16
    .i16
    REP #$20
    LDA ${L(S.customSlot)}
    AND #$00FF
    ASL A
    ASL A
    CLC
    ADC $055E
    TAX                    ; X = table entry address
    SEP #$20
    LDA ${L(S.customSlot)}
    ASL A
    ASL A
    ASL A
    ASL A
    ORA #$80
    STA $2121
    LDA $0560
    PHB
    PHA
    PLB                    ; DBR = table bank
    REP #$20
    LDA $0002,X            ; palette bank
    TAY
    LDA $0000,X            ; palette address
    TAX
    SEP #$20
    TYA
    PHA
    PLB                    ; DBR = palette bank
    LDY #$0020
  restore_loop:
    LDA $0000,X
    STA $002122
    INX
    DEY
    BNE restore_loop
    PLB
    LDA #$FF
    STA ${L(S.customSlot)}
    STA ${L(S.applied)}
    LDA #$00
    STA ${L(S.ready)}
    REP #$20
    RTS

  oh_t_unmap:              ; trampolines (branch range)
    JMP oh_unmap_exit
  oh_t_exit:
    JMP oh_exit

  oam_hook:                ; VBlank, right before the OAM DMA: CGRAM work only (the buffer was remapped by frame_hook)
    .a16
    .i16
    PHP
    PHX
    PHY
    PHB
    PHK
    PLB
    REP #$30
    LDA $01DC              ; gameplay NMI and the scene table the manager prepared (also right after a pause)
    CMP #$835B
    BNE oh_t_unmap
    LDA $055E
    CMP ${L(S.tablePtr)}
    BNE oh_t_unmap
    SEP #$20
    LDA $0560
    CMP ${L(S.tablePtr + 2)}
    BNE oh_t_unmap
    JSR vblank_ok
    BCS oh_t_exit          ; not safely in VBlank (lag frame): X keeps its colours, the remapped buffer still fits
    LDA ${L(S.pending)}
    BIT #$02
    BEQ oh_no_restore
    AND #$FD
    STA ${L(S.pending)}
    REP #$20
    JSR restore_custom     ; selection back to original: X gets its scene palette back; ready = 0
    SEP #$20
    BRA oh_t_unmap
  oh_no_restore:
    .a8
    LDA ${L(S.ready)}
    BEQ oh_t_unmap
    LDA ${L(S.conflict)}
    BNE oh_conflict
    LDA ${L(S.xBits)}      ; X still holds the selection? (scene reloads, respawn) -> upload again now
    ASL A
    ASL A
    ASL A
    ORA #$8F
    STA $2121
    JSR read_cgram
    CMP ${L(S.expCF)}
    SEP #$20
    BEQ oh_check_pending
    LDA ${L(S.pending)}
    ORA #$01
    STA ${L(S.pending)}
  oh_check_pending:
    LDA ${L(S.pending)}
    BIT #$01
    BEQ oh_t_exit
    AND #$FE
    STA ${L(S.pending)}
    REP #$20
    JSR offsets            ; X = outfit offset, Y = fur offset
    JSR put_custom         ; 32 bytes into X, still early in VBlank
    SEP #$20
    LDA ${L(S.customSlot)}
    STA ${L(S.applied)}
    LDA ${L(S.furIndex)}
    STA ${L(S.applied + 1)}
    LDA ${L(S.outfitIndex)}
    STA ${L(S.applied + 2)}
    JMP oh_exit
  oh_conflict:             ; frame_hook saw another object on X: Mr. Nutz back to S, X gets its scene palette back
    .a8
    JSR unmap_list
    LDA ${L(S.xBits)}      ; X is busy: keep it out of the free slots for this and the next pass
    REP #$20
    AND #$00FF
    TAY
    SEP #$20
    LDA ${A(ATTR_BIT)},Y
    ORA ${L(S.passMask)}
    STA ${L(S.passMask)}
    REP #$20
    JSR restore_custom     ; X gets its scene palette back before the DMA; ready = 0
    SEP #$20
    LDA #$00
    STA ${L(S.ready)}
    LDA #$FF               ; force the manager to upload the colours again
    STA ${L(S.applied)}
    BRA oh_exit
  oh_unmap_exit:           ; X cannot be used for this buffer: listed Mr. Nutz entries back to S
    SEP #$20
    JSR unmap_list
  oh_exit:
    SEP #$20
    LDA #$00               ; the list belongs to the buffer the DMA is about to upload
    STA ${L(S.listCount)}
    STA ${L(S.conflict)}
    REP #$30
    PLB
    PLY
    PLX
    PLP
    LDA #$4300             ; relocated original instructions
    TCD
    RTL

  unmap_list:              ; A8 X16, any DBR. Listed entries that still look remapped (tile < $50, palette X) -> S
    .a8
    .i16
    LDA ${L(S.listCount)}
    BEQ ul_done
    DEC A
    ASL A
    REP #$20
    AND #$00FF
    TAX
  ul_loop:
    .a16
    LDA ${L(S.list)},X
    PHX
    TAX
    SEP #$20
    LDA $7E0323,X
    CMP #$50
    BCS ul_next
    LDA $7E0324,X
    AND #$0E
    CMP ${L(S.xBits)}
    BNE ul_next
    LDA $7E0324,X
    AND #$F1
    ORA ${L(S.sBits)}
    STA $7E0324,X
  ul_next:
    REP #$20
    PLX
    DEX
    DEX
    BPL ul_loop
    SEP #$20
  ul_done:
    .a8
    RTS

  clear_hook:              ; JSL from $9D:E452 (Stage Clear init), forced blank, D=0 DBR=0. Mr. Nutz is the only object
    JSL ${L(CLEAR_HOOK_CALL)}  ; on his palette there, so the selection goes straight into that slot (relocated call first)
    PHP
    PHB
    REP #$30
    PHA
    PHX
    PHY
    PHK
    PLB                    ; DBR=$A0
    LDA ${L(S.magic)}
    CMP #${h(MAGIC, 4)}
    BNE cl_out             ; hook state not initialized yet
    LDA ${L(S.furIndex)}   ; fur and outfit both original: nothing to do
    BEQ cl_out
    SEP #$20
    LDA ${L(S.slotS)}      ; the gameplay manager's slot fields, restored below
    PHA
    LDA ${L(S.sBits)}
    PHA
    LDA ${L(S.customSlot)}
    PHA
    REP #$20
    JSR find_slot          ; slot of $85:9CC0 in the Stage Clear table
    SEP #$20
    LDA ${L(S.slotS)}
    CMP #$FF
    BEQ cl_restore
    STA ${L(S.customSlot)} ; put_custom writes into customSlot
    REP #$20
    JSR offsets
    JSR put_custom
    SEP #$20
  cl_restore:
    PLA
    STA ${L(S.customSlot)}
    PLA
    STA ${L(S.sBits)}
    PLA
    STA ${L(S.slotS)}
  cl_out:
    REP #$30
    PLY
    PLX
    PLA
    PLB
    PLP
    RTL

  frame_hook:              ; JSL from $81:8569: end of the gameplay frame work, active display, M8 X8 D=0 DBR=0
    JSL ${L(FRAME_HOOK_CALL)}  ; relocated original call
    PHP
    PHB
    REP #$30
    PHA
    PHX
    PHY
    SEP #$20
    .a8
    .i16
    LDA #$00
    STA ${L(S.listCount)}
    STA ${L(S.conflict)}
    REP #$20
    LDA ${L(S.magic)}      ; hook state initialized (input_hook ran since power-on) and this build's layout
    CMP #${h(MAGIC, 4)}
    BNE fh_t_out
    SEP #$20
    LDA ${L(S.layout)}
    CMP #${h(STATE_LAYOUT, 2)}
    BNE fh_t_out
    LDA ${L(S.ready)}
    BEQ fh_t_out
    JSR read_vcount        ; time to scan the whole buffer before the next NMI?
    .a16
    CMP #${h(FRAME_HOOK_LAST_SCANLINE + 1, 4)}
    BCS fh_t_out
    SEP #$20
    PHB
    LDA #$7F
    PHA
    PLB                    ; DBR=$7F: class table, list and state by absolute address
    REP #$20
    LDA $000024            ; OAM buffer bytes in use
    STA ${A(S.limit)}
    LDA #$0000             ; B = 0: TAY below gives Y = attr
    SEP #$20
    TAX
  fh_group:                ; 4 entries per step through the class table
    .a8
    REP #$20
    TXA
    CLC
    ADC #$000F             ; 4 more entries fit when X + 16 <= limit
    CMP ${A(S.limit)}
    LDA #$0000
    SEP #$20
    BCC fh_g4
    JMP fh_tail
  fh_t_out:
    JMP fh_out
  fh_g4:
    LDA $7E0324,X
    TAY
    LDA ${A(S.classTbl)},Y
    BNE fh_h0
  fh_r0:
    LDA $7E0328,X
    TAY
    LDA ${A(S.classTbl)},Y
    BNE fh_h1
  fh_r1:
    LDA $7E032C,X
    TAY
    LDA ${A(S.classTbl)},Y
    BNE fh_h2
  fh_r2:
    LDA $7E0330,X
    TAY
    LDA ${A(S.classTbl)},Y
    BNE fh_h3
  fh_r3:
    REP #$20
    TXA
    CLC
    ADC #$0010
    TAX
    LDA #$0000
    SEP #$20
    BRA fh_group
  fh_h0:
    JSR fh_handle
    BRA fh_r0
  fh_h1:
    INX
    INX
    INX
    INX
    JSR fh_handle
    DEX
    DEX
    DEX
    DEX
    BRA fh_r1
  fh_h2:
    REP #$20
    TXA
    CLC
    ADC #$0008
    TAX
    LDA #$0000
    SEP #$20
    JSR fh_handle
    REP #$20
    TXA
    SEC
    SBC #$0008
    TAX
    LDA #$0000
    SEP #$20
    BRA fh_r2
  fh_h3:
    REP #$20
    TXA
    CLC
    ADC #$000C
    TAX
    LDA #$0000
    SEP #$20
    JSR fh_handle
    REP #$20
    TXA
    SEC
    SBC #$000C
    TAX
    LDA #$0000
    SEP #$20
    BRA fh_r3
  fh_tail:                 ; last 0-3 entries one by one
    .a8
    CPX ${A(S.limit)}
    BCS fh_apply
    LDA $7E0324,X
    TAY
    LDA ${A(S.classTbl)},Y
    BEQ fh_tnext
    JSR fh_handle
  fh_tnext:
    INX
    INX
    INX
    INX
    BRA fh_tail
  fh_apply:                ; move the listed Mr. Nutz entries to X
    LDA ${A(S.listCount)}
    BEQ fh_scan_done
    DEC A
    ASL A
    TAY
  fh_aloop:
    REP #$20
    LDA ${A(S.list)},Y
    TAX
    SEP #$20
    LDA $7E0324,X
    AND #$F1
    ORA ${A(S.xBits)}
    STA $7E0324,X
    DEY
    DEY
    BPL fh_aloop
  fh_scan_done:
    PLB
  fh_out:
    REP #$30
    PLY
    PLX
    PLA
    PLB
    PLP
    RTL
  fh_handle:               ; A8 (B=0), X = entry offset, Y = attr: Mr. Nutz -> list; another object on X -> conflict
    .a8
    LDA ${A(S.classTbl)},Y
    CMP #$03
    BEQ fh_hconf           ; palette X, name table 1
    LDA $7E0323,X          ; tile
    CMP #$50
    BCC fh_hnutz
    LDA ${A(S.classTbl)},Y
    CMP #$02
    BEQ fh_hconf           ; palette X, tile >= $50: another object
    RTS                    ; palette S, not Mr. Nutz
  fh_hnutz:
    LDA ${A(S.listCount)}
    CMP #${h(NUTZ_LIST_MAX, 2)}
    BCS fh_hdone
    INC A
    STA ${A(S.listCount)}
    DEC A
    ASL A
    TAY
    REP #$20
    TXA
    STA ${A(S.list)},Y
    LDA #$0000
    SEP #$20
  fh_hdone:
    RTS
  fh_hconf:                ; another object on X: no remap in this buffer, oam_hook gives X its palette back
    LDA #$01
    STA ${A(S.conflict)}
    PLA
    PLA                    ; drop fh_handle's return address
    JMP fh_scan_done
  `;
}

/** OAM attribute lookups used by the scan loops (vhoopppN: palette = bits 1-3, name table = bit 0). */
export function attrTables(): Buffer {
  const t = Buffer.alloc(512);
  for (let a = 0; a < 256; a++) {
    t[a] = a & 1 ? 0xff : (a >> 1) & 7;
    t[256 + a] = 1 << ((a >> 1) & 7);
  }
  return t;
}

// Battery-backed SRAM (openspec/changes/archive/2026-11-05-sram-persistence, design D1): header chipset ROM -> ROM+RAM+battery,
// SRAM size 0 -> 2 KiB. LoROM maps it at $70-$7D:0000-$7FFF.
export const SRAM_HEADER = [
  { offset: 0x7fd6, original: "00", replacement: "02", reason: "Header chipset $00 (ROM) -> $02 (ROM + RAM + battery)" },
  { offset: 0x7fd8, original: "00", replacement: "01", reason: "Header SRAM size 0 -> 2 KiB" },
];

// Anti-copier SRAM checks (design D2, docs/knowledge/protection.md). E-G run in the game and are
// replaced by their "no SRAM" path without any bank $70 access; A-D never run and get width-independent guards.
export interface SramCheckPatch { id: string; cpu: number; original: string; replacement: string; reason: string; evidence: string }
const G_REPLACEMENT = assemble(`.a16
.i16
    LDA #$7070             ; $12 = open-bus value the original read from $70:00A9
    STA $12
    LDA $1C                ; X = $1C + $0F, as on the original mismatch path
    CLC
    ADC #$000F
    TAX
    LDY #$AF05             ; Y = A = the constant from $80:BE3F
    TYA
    BRA done
${"    NOP\n".repeat(0x16)}done:`, 0x81c45c).bytes.subarray(0, 18); // NOPs only place "done" at $81:C484 (not emitted)
export const SRAM_CHECK_PATCHES: SramCheckPatch[] = [
  {
    id: "E", cpu: 0x9cf819, original: "cf00", replacement: "8015",
    reason: "Check E (boot): BRA $9C:F830 instead of CMP $700000; the no-SRAM path always ends there",
    evidence: "docs/traces/trace-sram-header-boot.log (hang with SRAM), docs/traces/probe-regs-boot.log (M16/X16)",
  },
  {
    id: "F", cpu: 0x82ba22, original: "b710d989", replacement: "a0028008",
    reason: "Check F: LDY #$02 / BRA $82:BA2E, the no-SRAM exit (Y=X=2) without touching $70:0345",
    evidence: "docs/traces/trace-sram-header.log (sets $7E:054C with SRAM), docs/traces/probe-regs-stage.log (M16/X8)",
  },
  {
    id: "G", cpu: 0x81c45c, original: "a71a8512cd3fbef01fad3fbe871aa8a51c18", replacement: G_REPLACEMENT.toString("hex"),
    reason: "Check G: reproduce the no-SRAM mismatch path ($12=$7070, X=$1C+$0F, Y=A=$AF05) and BRA $81:C484",
    evidence: "docs/traces/trace-sram-header.log (writes $7F:C07F with SRAM), docs/traces/probe-regs-stage.log (M16/X16)",
  },
  { id: "A", cpu: 0x808400, original: "f0fe", replacement: "eaea", reason: "Check A (never reached): BEQ * -> NOP NOP", evidence: "docs/traces/static-sram-checks.txt, docs/traces/trace-sram-all.log (0 calls)" },
  { id: "D", cpu: 0x819d4b, original: "f0fe", replacement: "eaea", reason: "Check D (never reached): BEQ * -> NOP NOP", evidence: "docs/traces/static-sram-checks.txt, docs/traces/trace-sram-all.log (0 calls)" },
  { id: "C", cpu: 0x818f5e, original: "f001", replacement: "eaea", reason: "Check C (never reached): always RTS, never fall into $81:8F61", evidence: "docs/traces/static-sram-checks.txt, docs/traces/trace-sram-all.log (0 calls)" },
  { id: "B", cpu: 0x818035, original: "38", replacement: "18", reason: "Check B (never reached): SEC -> CLC, always report no SRAM", evidence: "docs/traces/static-sram-checks.txt, docs/traces/trace-sram-all.log (0 calls)" },
];

function sumWithNeutralChecksum(rom: Buffer): number {
  let sum = 0;
  for (let i = 0; i < rom.length; i++) {
    const neutral = i >= 0x7fdc && i <= 0x7fdf ? [0xff, 0xff, 0x00, 0x00][i - 0x7fdc] : rom[i];
    sum = (sum + neutral) & 0xffff;
  }
  return sum;
}

export function buildRuntimeManifest(rom: Buffer, presets: RuntimePresetFile): PatchManifest {
  const tables = buildTables(presets);
  const furOffsets = Buffer.from(Array.from({ length: tables.furCount }, (_, i) => i * 10));
  if (tables.fur.length > 0x70) throw new Error("Fur table overlaps its offset table");
  const { bytes: code, labels } = assemble(hookSource(tables.furCount, tables.outfitCount), CODE_ORIGIN);
  if (CODE_ORIGIN + code.length > FUR_TABLE) throw new Error(`Hook code too large: ${code.length} bytes`);
  const { bytes: pauseCode } = assemble(pauseSource({ slotS: STATE.slotS, customSlot: STATE.customSlot }), PAUSE_ORIGIN);
  if (pauseCode.length > 0x2000) throw new Error(`Pause code too large: ${pauseCode.length} bytes`);
  const jsl = (target: number) => "22" + Buffer.from([target & 0xff, (target >> 8) & 0xff, target >> 16]).toString("hex");
  const sha = createHash("sha256").update(rom).digest("hex");
  const hookOffset = loromToFile(HOOK_SITE);
  const entries: ManifestEntry[] = [
    {
      offset: 0x7fd7, original: "0A", replacement: "0B",
      reason: "Header ROM size 1 MiB -> 2 MiB for expanded LoROM banks $A0-$BF",
      evidence: "docs/knowledge/memory-map.md (header), docs/knowledge/mod-implementation.md",
    },
    {
      offset: hookOffset, original: HOOK_ORIGINAL, replacement: jsl(labels.input_hook) + "eaea",
      reason: "JSL input_hook + NOP NOP replacing LDA $4218 / STA $1A6F (relocated into the hook)",
      evidence: "docs/traces/trace-hook-site.log, docs/traces/trace-palette.log",
    },
    {
      offset: loromToFile(CODE_ORIGIN), replacement: code.toString("hex"),
      reason: "Hook code: Select+L/R input, private Nutz palette slot, OAM palette remap, CGRAM writes in VBlank",
      evidence: "docs/knowledge/mod-implementation.md",
    },
    {
      offset: loromToFile(OAM_HOOK_SITE), original: OAM_HOOK_ORIGINAL, replacement: jsl(labels.oam_hook),
      reason: "JSL oam_hook replacing LDA #$4300 / TCD (relocated) right before the OAM DMA",
      evidence: "docs/traces/sweep-oamtiming.log, docs/traces/sweep-analyze.log",
    },
    {
      offset: loromToFile(FRAME_HOOK_SITE), original: FRAME_HOOK_ORIGINAL, replacement: jsl(labels.frame_hook),
      reason: "JSL frame_hook replacing JSL $8A8134 (called first inside the hook) at the end of the gameplay frame work",
      evidence: "docs/traces/probe-frame-hook.log, docs/traces/franken-order.log, openspec/changes/fix-vblank-check-race/design.md",
    },
    {
      offset: loromToFile(CLEAR_HOOK_SITE), original: CLEAR_HOOK_ORIGINAL, replacement: jsl(labels.clear_hook),
      reason: "JSL clear_hook replacing JSL $9DABA7 (called first inside the hook) in the Stage Clear init",
      evidence: "docs/traces/sc-init-witch.log, docs/traces/sc-witch.log, openspec/changes/stage-clear-colours/design.md",
    },
    {
      offset: loromToFile(ATTR_PAL), replacement: attrTables().toString("hex"),
      reason: "OAM attr lookup tables: palette or $FF (name table 1) at +$000, 1 << palette at +$100",
      evidence: "src/runtime.ts",
    },
    {
      offset: loromToFile(FUR_TABLE), replacement: Buffer.concat([tables.fur, Buffer.alloc(0x70 - tables.fur.length, 0xff), furOffsets]).toString("hex"),
      reason: "Fur preset table ($CB-$CF x N, index 0 = original) + per-index byte offsets at +$70",
      evidence: "presets/runtime.json, docs/knowledge/palettes.md",
    },
    {
      offset: loromToFile(OUTFIT_TABLE), replacement: tables.outfit.toString("hex"),
      reason: "Outfit preset table ($C6-$C9 x N, index 0 = original)",
      evidence: "presets/runtime.json, docs/knowledge/palettes.md",
    },
    {
      offset: loromToFile(PAUSE_HOOK_SITE), original: PAUSE_HOOK_ORIGINAL, replacement: jsl(PAUSE_ORIGIN) + "eaeaeaea",
      reason: "JSL pause_hook + 4 NOP replacing SEP #$30 / LDA $183D / STA $420C (relocated) at the paused-NMI branch",
      evidence: "docs/traces/pause-measure.log, docs/knowledge/frame-cycle.md",
    },
    {
      offset: loromToFile(PAUSE_ORIGIN), replacement: pauseCode.toString("hex"),
      reason: "Pause menu code: open/close state machine, VRAM/OAM/CGRAM backup and restore, menu upload",
      evidence: "openspec/changes/pause-menu/design.md",
    },
    {
      offset: loromToFile(PAUSE_DATA), replacement: buildMenuData().toString("hex"),
      reason: "Pause menu data: BG3 tiles and map, swatch OBJ tiles, OAM template, palettes",
      evidence: "openspec/changes/pause-menu/design.md",
    },
    ...SRAM_HEADER.map((h) => ({ ...h, evidence: "openspec/changes/archive/2026-11-05-sram-persistence/design.md (D1)" })),
    ...SRAM_CHECK_PATCHES.map((c) => ({ offset: loromToFile(c.cpu), original: c.original, replacement: c.replacement, reason: c.reason, evidence: c.evidence })),
  ];
  const draft: PatchManifest = { sourceSha256: sha, expandTo: EXPANDED_SIZE, fill: 0xff, entries };
  const checksum = sumWithNeutralChecksum(buildManifestPatch(rom, draft).patched);
  const complement = checksum ^ 0xffff;
  const field = Buffer.alloc(4);
  field.writeUInt16LE(complement, 0);
  field.writeUInt16LE(checksum, 2);
  entries.push({
    offset: 0x7fdc, original: rom.subarray(0x7fdc, 0x7fe0).toString("hex"), replacement: field.toString("hex"),
    reason: "Header checksum/complement recomputed for the 2 MiB image", evidence: "computed by src/runtime.ts",
  });
  return draft;
}

export function buildRuntimePatch(rom: Buffer, presets: RuntimePresetFile): ManifestPatch & { manifest: PatchManifest } {
  const manifest = buildRuntimeManifest(rom, presets);
  return { ...buildManifestPatch(rom, manifest), manifest };
}
