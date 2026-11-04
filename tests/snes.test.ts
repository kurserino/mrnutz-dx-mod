import { describe, it, expect } from "vitest";
import { existsSync, readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { DEFAULT_ROM_PATH, ORIGINAL_PALETTE, PALETTE_FILE_OFFSET, applyIps } from "../src/core.js";
import { disassemble, fileToLorom, formatInstruction, loromToFile, parseHeader } from "../src/snes.js";
import { buildManifestPatch, validateManifest } from "../src/manifest.js";
import type { PatchManifest } from "../src/manifest.js";

const fixture = Buffer.alloc(1048576, 0);
ORIGINAL_PALETTE.copy(fixture, PALETTE_FILE_OFFSET);
const fixtureSha = createHash("sha256").update(fixture).digest("hex");

describe("LoROM mapping", () => {
  it("maps documented addresses", () => {
    expect(loromToFile(0x859cc0)).toBe(0x029cc0);
    expect(loromToFile(0x059cc0)).toBe(0x029cc0);
    expect(loromToFile(0x9dac57)).toBe(0x0eac57);
    expect(loromToFile(0x82d454)).toBe(0x015454);
    expect(fileToLorom(0x0eac57)).toBe(0x9dac57);
  });
  it("rejects WRAM and low-half addresses", () => {
    expect(() => loromToFile(0x7e1a6f)).toThrow();
    expect(() => loromToFile(0x801a6f)).toThrow();
  });
});

describe("65C816 disassembler", () => {
  it("tracks REP/SEP widths for immediate operands", () => {
    const rom = Buffer.alloc(0x8000);
    Buffer.from("C220A93412E220A9018D0B42A7106B", "hex").copy(rom);
    const text = disassemble(rom, 0x808000, 15).map(formatInstruction);
    expect(text).toEqual([
      "$808000  C2 20        mx  REP #$20",
      "$808002  A9 34 12     Mx  LDA #$1234",
      "$808005  E2 20        Mx  SEP #$20",
      "$808007  A9 01        mx  LDA #$01",
      "$808009  8D 0B 42     mx  STA $420B",
      "$80800C  A7 10        mx  LDA [$10]",
      "$80800E  6B           mx  RTL",
    ]);
  });
  it("resolves relative branch targets", () => {
    const rom = Buffer.alloc(0x8000);
    Buffer.from("D0FE", "hex").copy(rom);
    expect(disassemble(rom, 0x808000, 2)[0].operand).toBe("$808000");
  });
});

describe("manifest patches", () => {
  const base = (entries: PatchManifest["entries"], extra: Partial<PatchManifest> = {}): PatchManifest => ({
    sourceSha256: fixtureSha, entries, ...extra,
  });
  it("applies reviewed entries and rejects anything else", () => {
    const m = base([{ offset: 0x100, original: "0000", replacement: "EAEA", reason: "test", evidence: "unit" }]);
    const { patched } = buildManifestPatch(fixture, m);
    expect(patched[0x100]).toBe(0xea);
    expect(patched.length).toBe(fixture.length);
  });
  it("refuses wrong original bytes, overlap, missing evidence and wrong ROM", () => {
    const e = { offset: 0x100, original: "0000", replacement: "EAEA", reason: "r", evidence: "e" };
    expect(() => validateManifest(fixture, base([{ ...e, original: "1111" }]))).toThrow(/original bytes/);
    expect(() => validateManifest(fixture, base([e, { ...e, offset: 0x101 }]))).toThrow(/overlaps/);
    expect(() => validateManifest(fixture, base([{ ...e, evidence: "" }]))).toThrow(/evidence/);
    expect(() => validateManifest(fixture, { ...base([e]), sourceSha256: "00" })).toThrow(/SHA-256/);
  });
  it("expands the ROM with RLE fill and code in new space", () => {
    const m = base(
      [{ offset: 0x100000, replacement: "6B", reason: "RTL stub", evidence: "unit" }],
      { expandTo: 0x180000, fill: 0xff },
    );
    const { patched, ips } = buildManifestPatch(fixture, m);
    expect(patched.length).toBe(0x180000);
    expect(patched[0x100000]).toBe(0x6b);
    expect(patched[0x17ffff]).toBe(0xff);
    expect(ips.length).toBeLessThan(200);
    expect(applyIps(fixture, ips, 0x180000).equals(patched)).toBe(true);
  });
  it("forbids declaring original bytes in expansion space", () => {
    const m = base([{ offset: 0x100000, original: "FF", replacement: "6B", reason: "r", evidence: "e" }], { expandTo: 0x108000 });
    expect(() => validateManifest(fixture, m)).toThrow(/expansion/);
  });
});

// Regression checks of documented static findings; skipped when the private ROM is absent.
describe.skipIf(!existsSync(DEFAULT_ROM_PATH))("documented ROM facts", () => {
  const rom = existsSync(DEFAULT_ROM_PATH) ? readFileSync(DEFAULT_ROM_PATH) : Buffer.alloc(0);
  it("header is LoROM FastROM with a valid checksum", () => {
    const h = parseHeader(rom);
    expect(h.title).toBe("MR.NUTZ");
    expect(h.mapMode).toBe(0x30);
    expect(h.checksum).toBe(h.computedChecksum);
    expect((h.checksum ^ h.checksumComplement) & 0xffff).toBe(0xffff);
    expect(h.vectors).toMatchObject({ nmi: 0x8349, reset: 0x80b5 });
  });
  it("sprite palette DMA loop at $9DAC8C matches the documented bytes", () => {
    const at = loromToFile(0x9dac8c);
    expect(rom.subarray(at, at + 44).toString("hex").toUpperCase()).toBe(
      "C220A710AAE610E610A710E610E610E2209C0B428E02438D0443A9208D05439C0643A9018D0B42C614D0D56B",
    );
  });
  it("palette pointer tables reference $85:9CC0", () => {
    expect(rom.subarray(0x15464, 0x15468).toString("hex")).toBe("c09c8500");
  });
  it("joypad 1 is mirrored from $4218 to $1A6F", () => {
    const at = loromToFile(0x81828a);
    expect(rom.subarray(at, at + 6).toString("hex").toUpperCase()).toBe("AD18428D6F1A");
  });
});
