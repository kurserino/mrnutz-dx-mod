// Runtime palette switch patch (OpenSpec change runtime-palette-switch).
// Evidence: docs/static-analysis.md, docs/traces/*.log, docs/runtime-hook.md.

import { createHash } from "node:crypto";
import { ORIGINAL_PALETTE, hexColorToBgr555 } from "./core.js";
import { assemble } from "./asm.js";
import { buildManifestPatch } from "./manifest.js";
import type { ManifestEntry, ManifestPatch, PatchManifest } from "./manifest.js";
import { loromToFile } from "./snes.js";

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
}
// Mr. Nutz palette source; the scene's 8-entry sprite palette table at [$055E] decides its CGRAM slot
// (slot 4 = $C0 in most scenes, slot 0 = $80 in the stage traced in docs/traces/sweep-debug10.log).
export const NUTZ_PALETTE_CPU = 0x859cc0;
const MAGIC = 0x5a4e; // "NZ"
const MAX_PRESETS = 12;
const LAST_SAFE_SCANLINE = 250; // leave >= 11 VBlank lines for the remaining NMI work

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
    LDA #$FFFF
    STA ${L(S.customSlot)} ; customSlot = slotS = $FF
    STA ${L(S.tablePtr)}   ; impossible table pointer: the manager resets the scene state on its first run
    SEP #$20
    STA ${L(S.tablePtr + 2)}
    LDA #$00
    STA ${L(S.ready)}
    REP #$20
    LDA #${h(MAGIC, 4)}
    STA ${L(S.magic)}
  ready:
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
  input_done:
    REP #$30
    JSR manage
    REP #$30
    PLB
    PLY
    PLX
    PLP
    RTL

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
    BCS ts_defer
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
    STA ${L(S.customSlot)}
    STA ${L(S.slotS)}
    REP #$20
    JSR find_slot
    CLC
    RTS
  ts_defer:
    REP #$20
    SEC
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
    JSR vblank_ok
    BCC sc_go
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
    LDA #$10
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
    LDA ${L(S.tile)}       ; hidden ones included (they can be shown again without an upload we see)
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
    JMP sc_loop            ; loop body is longer than a branch reaches
  sc_end:
    REP #$20
    LDA $0026              ; restore OAMADD as the game leaves it ($81:C3AF: entries in use / 2)
    LSR A
    STA $2102
    SEP #$20
    LDA ${L(S.scanPos)}
    CLC
    ADC #$10
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

  slot_is_free:            ; A8 = candidate, B = 0. C=0 and A=candidate if != S, same group, unused in the scene
    .a8
    .i16
    STA ${L(S.tmp)}
    CMP ${L(S.slotS)}
    BEQ not_free
    EOR ${L(S.slotS)}
    AND #$04
    BNE not_free
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

  vblank_ok:               ; C=0 when CGRAM may be accessed now (VBlank, scanline <= ${LAST_SAFE_SCANLINE}); returns A8
    SEP #$20
    LDA $4212
    BPL vb_no
    LDA $213F              ; reset the counter latch flip-flop
    LDA $2137              ; latch H/V counters
    LDA $213D
    XBA
    LDA $213D
    AND #$01
    XBA
    REP #$20
    CMP #${h(LAST_SAFE_SCANLINE + 1, 4)}
    SEP #$20
    BCS vb_no
    CLC
    RTS
  vb_no:
    SEC
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

  oh_out16:
  oh_out:                  ; trampolines for the early exits of oam_hook (branch range)
    JMP oh_exit
  oh_nr:
    JMP oh_notready

  oam_hook:                ; critical path: keep it short
    .a16
    .i16
    PHP
    PHX
    PHY
    PHB
    PHK
    PLB
    REP #$30
    SEP #$20
    REP #$20               ; gameplay NMI and the scene table the manager prepared (also right after a pause)
    LDA $01DC
    CMP #$835B
    BNE oh_out16
    LDA $055E
    CMP ${L(S.tablePtr)}
    BNE oh_out16
    SEP #$20
    LDA $0560
    CMP ${L(S.tablePtr + 2)}
    BNE oh_out
    LDA $4212
    BPL oh_out             ; not in VBlank
    LDA ${L(S.pending)}
    BIT #$02
    BEQ oh_no_restore
    AND #$FD
    STA ${L(S.pending)}
    REP #$20
    JSR restore_custom     ; selection back to original: X gets its scene palette back; ready = 0
    JMP oh_exit
  oh_no_restore:
    .a8
    LDA ${L(S.ready)}
    BEQ oh_out
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
    BEQ oh_scan
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
  oh_scan:
    SEP #$20
    LDX #$0000
    LDY #$0000
  oh_loop:
    CPX $0024              ; OAM buffer bytes in use this frame
    BCS oh_end
    LDA $0324,X            ; attr
    AND #$0E
    CMP ${L(S.xBits)}
    BEQ oh_isx
    CMP ${L(S.sBits)}
    BEQ oh_iss
  oh_next:
    INX
    INX
    INX
    INX
    BRA oh_loop
  oh_iss:
    LDA $0323,X            ; palette S: Mr. Nutz only with tile < $50 on name table 0
    CMP #$50
    BCS oh_next
    LDA $0324,X
    LSR A
    BCS oh_next
  oh_nutz:
    CPY #${h(NUTZ_LIST_MAX, 4)}
    BCS oh_next
    PHX
    INY
    BRA oh_next
  oh_isx:
    LDA $0323,X            ; palette X: anything but Mr. Nutz is a conflict
    CMP #$50
    BCS oh_conflict
    LDA $0324,X
    LSR A
    BCS oh_conflict
    BRA oh_nutz
  oh_end:
    CPY #$0000
    BEQ oh_exit
  oh_remap:
    PLX
    LDA $0324,X
    AND #$F1
    ORA ${L(S.xBits)}
    STA $0324,X
    DEY
    BNE oh_remap
    BRA oh_exit
  oh_conflict:
    CPY #$0000
    BEQ oh_restore
  oh_pop:
    PLX
    DEY
    BNE oh_pop
  oh_restore:
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
  oh_notready:
    SEP #$20
    LDA #$00
    STA ${L(S.ready)}
    LDA #$FF               ; force the manager to upload the colours again
    STA ${L(S.applied)}
  oh_exit:
    REP #$30
    PLB
    PLY
    PLX
    PLP
    LDA #$4300             ; relocated original instructions
    TCD
    RTL
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
  const jsl = (target: number) => "22" + Buffer.from([target & 0xff, (target >> 8) & 0xff, target >> 16]).toString("hex");
  const sha = createHash("sha256").update(rom).digest("hex");
  const hookOffset = loromToFile(HOOK_SITE);
  const entries: ManifestEntry[] = [
    {
      offset: 0x7fd7, original: "0A", replacement: "0B",
      reason: "Header ROM size 1 MiB -> 2 MiB for expanded LoROM banks $A0-$BF",
      evidence: "docs/static-analysis.md (header), docs/runtime-hook.md",
    },
    {
      offset: hookOffset, original: HOOK_ORIGINAL, replacement: jsl(labels.input_hook) + "eaea",
      reason: "JSL input_hook + NOP NOP replacing LDA $4218 / STA $1A6F (relocated into the hook)",
      evidence: "docs/traces/trace-hook-site.log, docs/traces/trace-palette.log",
    },
    {
      offset: loromToFile(CODE_ORIGIN), replacement: code.toString("hex"),
      reason: "Hook code: Select+L/R input, private Nutz palette slot, OAM palette remap, CGRAM writes in VBlank",
      evidence: "docs/runtime-hook.md",
    },
    {
      offset: loromToFile(OAM_HOOK_SITE), original: OAM_HOOK_ORIGINAL, replacement: jsl(labels.oam_hook),
      reason: "JSL oam_hook replacing LDA #$4300 / TCD (relocated) right before the OAM DMA",
      evidence: "docs/traces/sweep-oamtiming.log, docs/traces/sweep-analyze.log",
    },
    {
      offset: loromToFile(ATTR_PAL), replacement: attrTables().toString("hex"),
      reason: "OAM attr lookup tables: palette or $FF (name table 1) at +$000, 1 << palette at +$100",
      evidence: "src/runtime.ts",
    },
    {
      offset: loromToFile(FUR_TABLE), replacement: Buffer.concat([tables.fur, Buffer.alloc(0x70 - tables.fur.length, 0xff), furOffsets]).toString("hex"),
      reason: "Fur preset table ($CB-$CF x N, index 0 = original) + per-index byte offsets at +$70",
      evidence: "presets/runtime.json, docs/rom-map.md",
    },
    {
      offset: loromToFile(OUTFIT_TABLE), replacement: tables.outfit.toString("hex"),
      reason: "Outfit preset table ($C6-$C9 x N, index 0 = original)",
      evidence: "presets/runtime.json, docs/rom-map.md",
    },
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
