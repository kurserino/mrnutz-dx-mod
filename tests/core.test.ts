import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import {
  ORIGINAL_PALETTE, PALETTE_FILE_OFFSET, assertSupportedRom,
  hexColorToBgr555, buildPalette, diffPalette, encodeIps,
  applyIps, verifyPatch, crc32,
} from "../src/core.js";
import type { PalettePreset } from "../src/core.js";
const fixture = Buffer.alloc(1048576, 0);
ORIGINAL_PALETTE.copy(fixture, PALETTE_FILE_OFFSET);
const preset: PalettePreset = {
  name: "test", fur: ["#5A1023", "#8C1F3F", "#C9365E", "#FF557A", "#FF9DB3"],
  outfit: ["#FFF2A0", "#FFD84A", "#A88300", "#6B5600"]
};
describe("ROM patch pipeline", () => {
  it("converts target pink to little-endian 5F 3D", () => {
    expect(hexColorToBgr555("#FF557A")).toBe(0x3d5f);
  });
  it("rejects unknown palette", () => {
    expect(() => assertSupportedRom(Buffer.alloc(1048576))).toThrow();
  });
  it("changes only allowed palette bytes and retains transparency", () => {
    assertSupportedRom(fixture);
    const palette = buildPalette(preset);
    expect(palette.subarray(0, 2)).toEqual(ORIGINAL_PALETTE.subarray(0, 2));
    const diff = diffPalette(fixture, palette);
    const ips = encodeIps(diff);
    verifyPatch(fixture, ips, palette);
    const patched = applyIps(fixture, ips);
    expect(patched[PALETTE_FILE_OFFSET + 28]).toBe(0x5f);
    expect(patched[PALETTE_FILE_OFFSET + 29]).toBe(0x3d);
    expect(patched.subarray(0, PALETTE_FILE_OFFSET)).toEqual(fixture.subarray(0, PALETTE_FILE_OFFSET));
  });
  it("computes CRC32 using standard test vector", () => {
    expect(crc32(Buffer.from("123456789"))).toBe("CBF43926");
  });
});
