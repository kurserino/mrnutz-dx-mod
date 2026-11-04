import { createHash } from "node:crypto";

export const PALETTE_FILE_OFFSET = 0x029CC0;
export const PALETTE_LENGTH = 32;
export const EXPECTED_ROM_SIZE = 1048576;
export const ORIGINAL_PALETTE = Buffer.from(
  ("00 00 CE 49 52 5A D6 6A 5A 7B DE 7B 1A 03 92 02 " +
  "8A 01 C8 00 00 00 0E 00 12 00 16 00 1A 00 1E 00").replace(/\s+/g, ""),
  "hex",
);
export const DEFAULT_ROM_PATH = "roms/Mr. Nutz (USA) (En,Fr).sfc";

export function crc32(data: Uint8Array): string {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return ((crc ^ 0xffffffff) >>> 0).toString(16).padStart(8, "0").toUpperCase();
}

export function identity(rom: Buffer) {
  return {
    size: rom.length,
    crc32: crc32(rom),
    sha256: createHash("sha256").update(rom).digest("hex"),
    paletteBytes: rom.subarray(PALETTE_FILE_OFFSET, PALETTE_FILE_OFFSET + PALETTE_LENGTH).toString("hex").toUpperCase(),
  };
}

export function assertSupportedRom(rom: Buffer): void {
  if (rom.length !== EXPECTED_ROM_SIZE) {
    throw new Error(`ROM must be exactly ${EXPECTED_ROM_SIZE} bytes (unheadered), got ${rom.length}`);
  }
  const actual = rom.subarray(PALETTE_FILE_OFFSET, PALETTE_FILE_OFFSET + PALETTE_LENGTH);
  if (!actual.equals(ORIGINAL_PALETTE)) {
    throw new Error("Original character palette did not match expected bytes. Refusing to patch an unknown/modified ROM.");
  }
}

export function hexColorToBgr555(color: string): number {
  if (!/^#[0-9a-fA-F]{6}$/.test(color)) throw new Error(`Invalid color: ${color}. Expected #RRGGBB`);
  const r = Math.round(parseInt(color.slice(1, 3), 16) * 31 / 255);
  const g = Math.round(parseInt(color.slice(3, 5), 16) * 31 / 255);
  const b = Math.round(parseInt(color.slice(5, 7), 16) * 31 / 255);
  return (b << 10) | (g << 5) | r;
}

export function bgr555ToRgbHex(color: number): string {
  const r = Math.round((color & 31) * 255 / 31);
  const g = Math.round(((color >> 5) & 31) * 255 / 31);
  const b = Math.round(((color >> 10) & 31) * 255 / 31);
  return "#" + [r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("").toUpperCase();
}

export interface PalettePreset {
  name: string;
  fur: [string, string, string, string, string];
  outfit: [string, string, string, string];
}

export function buildPalette(preset: PalettePreset): Buffer {
  if (preset.fur.length !== 5 || preset.outfit.length !== 4) throw new Error("Expected 5 fur and 4 outfit shades");
  const palette = Buffer.from(ORIGINAL_PALETTE);
  // Indexed observations: $C6-$C9 = outfit, $CB-$CF = fur. To be verified visually in all animations.
  for (let i = 0; i < 4; i++) palette.writeUInt16LE(hexColorToBgr555(preset.outfit[i]), (6 + i) * 2);
  for (let i = 0; i < 5; i++) palette.writeUInt16LE(hexColorToBgr555(preset.fur[i]), (11 + i) * 2);
  return palette;
}

export interface IpsChange {
  offset: number;
  before: Buffer;
  after: Buffer;
}

export function diffPalette(rom: Buffer, palette: Buffer): IpsChange[] {
  if (palette.length !== 32) throw new Error("Palette must be 32 bytes");
  assertSupportedRom(rom);
  const patches: IpsChange[] = [];
  let index = 0;
  while (index < 32) {
    if (rom[PALETTE_FILE_OFFSET + index] === palette[index]) {
      index++;
      continue;
    }
    const start = index;
    while (index < 32 && rom[PALETTE_FILE_OFFSET + index] !== palette[index]) index++;
    patches.push({
      offset: PALETTE_FILE_OFFSET + start,
      before: Buffer.from(rom.subarray(PALETTE_FILE_OFFSET + start, PALETTE_FILE_OFFSET + index)),
      after: Buffer.from(palette.subarray(start, index)),
    });
  }
  return patches;
}

export function encodeIps(changes: IpsChange[]): Buffer {
  const parts: Buffer[] = [Buffer.from("PATCH", "ascii")];
  for (const change of changes) {
    const { offset, after } = change;
    if (offset > 0xffffff || offset < 0 || after.length > 65535 || after.length === 0) {
      throw new Error("Invalid IPS record");
    }
    const header = Buffer.alloc(5);
    header.writeUIntBE(offset, 0, 3);
    header.writeUInt16BE(after.length, 3);
    parts.push(header, after);
  }
  parts.push(Buffer.from("EOF", "ascii"));
  return Buffer.concat(parts);
}

/**
 * Apply an IPS patch. `maxSize` (default: original size) allows records that
 * extend the ROM, as needed for a declared expansion; the output length is the
 * furthest byte written or the original length, whichever is larger.
 */
export function applyIps(original: Buffer, ips: Buffer, maxSize = original.length): Buffer {
  if (ips.subarray(0, 5).toString("ascii") !== "PATCH") throw new Error("Invalid IPS header");
  const work = Buffer.alloc(Math.max(maxSize, original.length));
  original.copy(work);
  let length = original.length;
  const output = work;
  let cursor = 5;
  while (cursor < ips.length) {
    if (ips.subarray(cursor, cursor + 3).toString("ascii") === "EOF") {
      if (cursor + 3 !== ips.length) throw new Error("Unexpected IPS trailer");
      return Buffer.from(output.subarray(0, length));
    }
    if (cursor + 5 > ips.length) throw new Error("Truncated IPS record");
    const offset = ips.readUIntBE(cursor, 3);
    const size = ips.readUInt16BE(cursor + 3);
    cursor += 5;
    if (size === 0) {
      if (cursor + 3 > ips.length) throw new Error("Truncated IPS RLE record");
      const count = ips.readUInt16BE(cursor);
      const value = ips[cursor + 2];
      cursor += 3;
      if (offset + count > output.length) throw new Error("IPS record exceeds ROM");
      output.fill(value, offset, offset + count);
      length = Math.max(length, offset + count);
      continue;
    }
    if (cursor + size > ips.length || offset + size > output.length) throw new Error("IPS record exceeds buffer");
    ips.copy(output, offset, cursor, cursor + size);
    length = Math.max(length, offset + size);
    cursor += size;
  }
  throw new Error("Missing IPS EOF");
}

export function verifyPatch(original: Buffer, patch: Buffer, palette: Buffer): void {
  const actual = applyIps(original, patch);
  if (!actual.subarray(PALETTE_FILE_OFFSET, PALETTE_FILE_OFFSET + 32).equals(palette)) {
    throw new Error("Patched palette does not equal requested palette");
  }
  let diff = 0;
  for (let i = 0; i < original.length; i++) {
    if (original[i] !== actual[i]) {
      if (i < PALETTE_FILE_OFFSET || i >= PALETTE_FILE_OFFSET + 32) {
        throw new Error(`Unexpected change outside palette at 0x${i.toString(16)}`);
      }
      diff++;
    }
  }
  if (diff === 0) throw new Error("Patch changes nothing");
}
