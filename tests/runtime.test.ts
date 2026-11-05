import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { DEFAULT_ROM_PATH, ORIGINAL_PALETTE, PALETTE_FILE_OFFSET, applyIps } from "../src/core.js";
import { assemble } from "../src/asm.js";
import { disassemble, formatInstruction, loromToFile, parseHeader } from "../src/snes.js";
import { CODE_ORIGIN, EXPANDED_SIZE, HOOK_ORIGINAL, HOOK_SITE, OAM_HOOK_ORIGINAL, OAM_HOOK_SITE, SAVE_RECORD, SRAM_CHECK_PATCHES, SRAM_HEADER, STATE, buildRuntimePatch, buildTables, decodeSaveRecord, encodeSaveRecord, hookSource } from "../src/runtime.js";
import type { RuntimePresetFile } from "../src/runtime.js";

const presets = JSON.parse(readFileSync("presets/runtime.json", "utf8")) as RuntimePresetFile;

// Synthetic ROM with only the bytes the runtime builder validates.
const fixture = Buffer.alloc(1048576, 0);
ORIGINAL_PALETTE.copy(fixture, PALETTE_FILE_OFFSET);
Buffer.from(HOOK_ORIGINAL, "hex").copy(fixture, loromToFile(HOOK_SITE));
Buffer.from(OAM_HOOK_ORIGINAL, "hex").copy(fixture, loromToFile(OAM_HOOK_SITE));
fixture[0x7fd7] = 0x0a;
for (const c of SRAM_CHECK_PATCHES) Buffer.from(c.original, "hex").copy(fixture, loromToFile(c.cpu));

describe("65C816 assembler", () => {
  it("encodes widths, labels and stack-relative operands", () => {
    const { bytes } = assemble("REP #$20\nloop:\nLDA #$1234\nCMP $03,S\nBNE loop\nLDA $7FFFF0\nJSL target\ntarget:\nRTL", 0xa08000);
    // target = $A08000 + 2+3+2+2+4+4 = $A08011
    expect(bytes.toString("hex").toUpperCase()).toBe("C220A93412C303D0F9AFF0FF7F221180A06B");
  });
  it("rejects out-of-range branches and unknown labels", () => {
    expect(() => assemble("BRA far\n" + "NOP\n".repeat(200) + "far:", 0x808000)).toThrow(/out of range/);
    expect(() => assemble("BRA nowhere", 0x808000)).toThrow(/Unknown label/);
  });
  it("rejects immediates that disagree with the tracked M/X width", () => {
    expect(() => assemble("SEP #$20\nLDA #$1234", 0x808000)).toThrow(/width mismatch/);
    expect(() => assemble("REP #$10\nLDX #$12", 0x808000)).toThrow(/width mismatch/);
    expect(() => assemble(".a8\nCMP #$0001", 0x808000)).toThrow(/width mismatch/);
    // After RTS the width is unknown again, so the last 16-bit LDA is accepted.
    expect(assemble("REP #$30\nLDA #$1234\nSEP #$20\nLDA #$12\nRTS\nLDA #$1234", 0x808000).bytes.length).toBe(13);
  });
  it("assembles both hooks with every immediate width checked", () => {
    const { bytes, labels } = assemble(hookSource(4, 4), CODE_ORIGIN);
    expect(labels.input_hook).toBe(CODE_ORIGIN);
    expect(labels.oam_hook).toBeGreaterThan(CODE_ORIGIN);
    expect(bytes.length).toBeLessThan(0x1000);
    const rom = Buffer.alloc(0x200000);
    bytes.copy(rom, loromToFile(CODE_ORIGIN));
    // The input hook is straight-line A16/X16 code up to its RTL: a linear disassembly must match.
    const lines = disassemble(rom, CODE_ORIGIN, labels.load_save - CODE_ORIGIN, { m8: false, x8: false }).map((i) => i.mnemonic);
    expect(lines[0]).toBe("LDA");
    expect(lines[lines.length - 1]).toBe("RTL");
  });
});

describe("runtime palette patch", () => {
  it("puts the exact original palette at index 0 of both tables", () => {
    const t = buildTables(presets);
    expect(t.fur.subarray(0, 10)).toEqual(ORIGINAL_PALETTE.subarray(22, 32));
    expect(t.outfit.subarray(0, 8)).toEqual(ORIGINAL_PALETTE.subarray(12, 20));
    expect(t.furCount).toBe(presets.fur.length + 1);
  });
  it("builds a 2 MiB ROM with a valid checksum and only the declared hook change in the original area", () => {
    const { patched, ips, manifest } = buildRuntimePatch(fixture, presets);
    expect(patched.length).toBe(EXPANDED_SIZE);
    const header = parseHeader(patched);
    expect(header.checksum).toBe(header.computedChecksum);
    expect((header.checksum ^ header.checksumComplement) & 0xffff).toBe(0xffff);
    const hook = loromToFile(HOOK_SITE);
    expect(patched.subarray(hook, hook + 6).toString("hex").toUpperCase()).toBe("220080A0EAEA");
    expect(patched.subarray(PALETTE_FILE_OFFSET, PALETTE_FILE_OFFSET + 32)).toEqual(ORIGINAL_PALETTE);
    const changed: number[] = [];
    for (let i = 0; i < fixture.length; i++) if (fixture[i] !== patched[i]) changed.push(i);
    const oam = loromToFile(OAM_HOOK_SITE);
    expect(patched.subarray(oam, oam + 4).toString("hex").toUpperCase().startsWith("22")).toBe(true);
    const inCheck = (i: number) => SRAM_CHECK_PATCHES.some((c) => i >= loromToFile(c.cpu) && i < loromToFile(c.cpu) + c.original.length / 2);
    const allowed = (i: number) => i === 0x7fd6 || i === 0x7fd7 || i === 0x7fd8 || (i >= 0x7fdc && i <= 0x7fdf)
      || (i >= hook && i < hook + 6) || (i >= oam && i < oam + 4) || inCheck(i);
    expect(changed.every(allowed)).toBe(true);
    expect(applyIps(fixture, ips, EXPANDED_SIZE).equals(patched)).toBe(true);
    expect(manifest.entries.every((e) => e.reason && e.evidence)).toBe(true);
  });
  it("declares 2 KiB battery-backed SRAM in the header with a valid checksum (sram-persistence D1)", () => {
    const { patched } = buildRuntimePatch(fixture, presets);
    expect(SRAM_HEADER.map((h) => h.offset)).toEqual([0x7fd6, 0x7fd8]);
    expect(patched[0x7fd6]).toBe(0x02);
    expect(patched[0x7fd8]).toBe(0x01);
    const header = parseHeader(patched);
    expect(header.checksum).toBe(header.computedChecksum);
    expect((header.checksum ^ header.checksumComplement) & 0xffff).toBe(0xffff);
  });
  it("neutralizes the anti-copier SRAM checks with the exact bytes from design D2", () => {
    const { patched } = buildRuntimePatch(fixture, presets);
    const at = (cpu: number, n: number) => patched.subarray(loromToFile(cpu), loromToFile(cpu) + n).toString("hex").toUpperCase();
    expect(at(0x9cf819, 2)).toBe("8015"); // E: BRA $9C:F830
    expect(at(0x82ba22, 4)).toBe("A0028008"); // F: LDY #$02 / BRA $82:BA2E
    expect(at(0x808400, 2)).toBe("EAEA"); // A
    expect(at(0x819d4b, 2)).toBe("EAEA"); // D
    expect(at(0x818f5e, 2)).toBe("EAEA"); // C
    expect(at(0x818035, 1)).toBe("18"); // B: CLC
    // G: no bank $70 access, same registers as the original no-SRAM path, then BRA $81:C484.
    const g = disassemble(patched, 0x81c45c, 18, { m8: false, x8: false }).map(formatInstruction).join("\n");
    expect(g).toContain("LDA #$7070");
    expect(g).toContain("STA $12");
    expect(g).toContain("ADC #$000F");
    expect(g).toContain("LDY #$AF05");
    expect(g).toContain("BRA $81C484");
    expect(g).not.toMatch(/\[\$1A\]|\$70[0-9A-F]{4}\b/); // no [$1A] pointer, no long $70xxxx address
    for (const c of SRAM_CHECK_PATCHES) {
      expect(c.replacement.length).toBe(c.original.length);
      expect(c.evidence).toMatch(/docs\/traces\//);
    }
  });
  it("keeps the hook state inside WRAM never touched by the game ($7FB6C0-$7FBFFF, sweep-wram.log)", () => {
    for (const a of Object.values(STATE)) {
      expect(a).toBeGreaterThanOrEqual(0x7fb6c0);
      expect(a + 1).toBeLessThanOrEqual(0x7fbfff);
    }
  });
  it("rejects too many presets", () => {
    const many = { ...presets, fur: Array.from({ length: 12 }, () => presets.fur[0]) };
    expect(() => buildTables(many)).toThrow(/At most/);
  });
});

describe("SRAM save record (sram-persistence D3/D4)", () => {
  const hex16 = (v: number) => "$" + (v & 0xffff).toString(16).toUpperCase().padStart(4, "0");
  it("round-trips a valid record and lays it out as designed", () => {
    const r = encodeSaveRecord(2, 3);
    // magic 4E5A, version 01, fur 02, outfit 03, reserved 00, checksum $FFFF ^ ($5A4E + $0201 + $0003) = $A3AD
    expect(r.toString("hex").toUpperCase()).toBe("4E5A01020300ADA3");
    expect(decodeSaveRecord(r, 4, 4)).toEqual({ fur: 2, outfit: 3 });
  });
  it("treats a bad magic, version or checksum as absent", () => {
    const badMagic = encodeSaveRecord(1, 1);
    badMagic[0] ^= 0xff;
    const badVersion = encodeSaveRecord(1, 1);
    badVersion[2] = 2;
    const badSum = encodeSaveRecord(1, 1);
    badSum[7] ^= 0x01;
    const tampered = encodeSaveRecord(1, 1);
    tampered[3] = 2; // payload changed, checksum not
    for (const r of [badMagic, badVersion, badSum, tampered, Buffer.alloc(8, 0), Buffer.alloc(8, 0xff)]) {
      expect(decodeSaveRecord(r, 4, 4)).toBeUndefined();
    }
  });
  it("falls back to the original preset for an out-of-range index", () => {
    expect(decodeSaveRecord(encodeSaveRecord(9, 1), 4, 4)).toEqual({ fur: 0, outfit: 1 });
    expect(decodeSaveRecord(encodeSaveRecord(1, 4), 4, 4)).toEqual({ fur: 1, outfit: 0 });
  });
  it("places the record away from every SRAM address the original checks touch", () => {
    const used = [[0x700000, 0x700001], [0x700004, 0x700005], [0x700034, 0x700035], [0x7000a9, 0x7000aa], [0x700345, 0x700348]];
    const lo = SAVE_RECORD.address;
    const hi = SAVE_RECORD.address + SAVE_RECORD.size - 1;
    for (const [a, b] of used) expect(hi < a || lo > b).toBe(true);
    expect(hi).toBeLessThan(0x700800); // inside the declared 2 KiB
  });
  it("loads the record in the one-time init and writes it after each change, checksum last", () => {
    const { bytes, labels } = assemble(hookSource(4, 4), CODE_ORIGIN);
    const rom = Buffer.alloc(0x200000);
    bytes.copy(rom, loromToFile(CODE_ORIGIN));
    const init = disassemble(rom, CODE_ORIGIN, labels.ready - CODE_ORIGIN, { m8: false, x8: false }).map(formatInstruction);
    expect(init.filter((l) => l.includes("JSR " + hex16(labels.load_save)))).toHaveLength(1);
    const input = disassemble(rom, labels.ready, labels.load_save - labels.ready, { m8: false, x8: false }).map(formatInstruction);
    expect(input.filter((l) => l.includes("JSR " + hex16(labels.write_save)))).toHaveLength(2); // fur and outfit change
    const w = disassemble(rom, labels.write_save, labels.manage - labels.write_save, { m8: false, x8: false });
    const stores = w.filter((i) => i.mnemonic === "STA").map(formatInstruction);
    expect(stores[stores.length - 1]).toContain("$700106"); // checksum last
    expect(stores.slice(0, -1).every((l) => /\$70010[0-5]/.test(l))).toBe(true);
    expect(w.map((i) => i.mnemonic).slice(-2)).toEqual(["PLP", "RTS"]);
    expect(labels.manage).toBeLessThan(0xa09000);
  });
});

describe.skipIf(!existsSync(DEFAULT_ROM_PATH))("runtime patch on the supported ROM", () => {
  it("validates against the real ROM bytes and checksum", () => {
    const rom = readFileSync(DEFAULT_ROM_PATH);
    const { patched } = buildRuntimePatch(rom, presets);
    const header = parseHeader(patched);
    expect(header.checksum).toBe(header.computedChecksum);
    expect(header.romSizeKiB).toBe(2048);
    for (const c of SRAM_CHECK_PATCHES) {
      expect(rom.subarray(loromToFile(c.cpu), loromToFile(c.cpu) + c.original.length / 2).toString("hex")).toBe(c.original);
    }
    expect(disassemble(patched, HOOK_SITE, 4, { m8: false, x8: false }).map(formatInstruction)[0]).toContain("JSL $A08000");
  });
});
