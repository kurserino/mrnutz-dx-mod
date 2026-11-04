// Manifest-driven ROM patching for runtime hacks. Every byte the IPS changes
// must belong to a reviewed manifest entry whose expected original bytes match
// the validated source ROM. Bytes past the original ROM end (expansion) have no
// original and must be declared through `expandTo` plus explicit entries.

import { createHash } from "node:crypto";
import { applyIps, assertSupportedRom } from "./core.js";
import type { IpsChange } from "./core.js";

export interface ManifestEntry {
  /** File offset (unheadered). */
  offset: number;
  /** Expected original bytes as hex; must be omitted for expansion space. */
  original?: string;
  /** Replacement bytes as hex. */
  replacement: string;
  /** Why the change exists. */
  reason: string;
  /** Pointer to Mesen trace / disassembly evidence backing the change. */
  evidence: string;
}

export interface PatchManifest {
  /** SHA-256 of the only ROM this manifest may be applied to. */
  sourceSha256: string;
  /** Optional expanded ROM size in bytes; new space is filled with `fill`. */
  expandTo?: number;
  fill?: number;
  entries: ManifestEntry[];
}

export interface ManifestPatch {
  changes: IpsChange[];
  /** RLE padding records for ROM expansion. */
  padding: { offset: number; count: number; value: number }[];
  ips: Buffer;
  patched: Buffer;
}

const hexBytes = (text: string): Buffer => {
  const clean = text.replace(/\s+/g, "");
  if (!/^([0-9a-fA-F]{2})+$/.test(clean)) throw new Error(`Invalid hex byte string: ${text}`);
  return Buffer.from(clean, "hex");
};

export function validateManifest(rom: Buffer, manifest: PatchManifest): void {
  assertSupportedRom(rom);
  const sha = createHash("sha256").update(rom).digest("hex");
  if (sha !== manifest.sourceSha256.toLowerCase()) throw new Error("Manifest source SHA-256 does not match ROM");
  const size = manifest.expandTo ?? rom.length;
  if (size < rom.length || size % 0x8000 !== 0 || size > 0x400000) {
    throw new Error(`expandTo must be a multiple of 32 KiB between ${rom.length} and 4 MiB`);
  }
  const sorted = [...manifest.entries].sort((a, b) => a.offset - b.offset);
  let previousEnd = -1;
  for (const entry of sorted) {
    if (!entry.reason?.trim() || !entry.evidence?.trim()) {
      throw new Error(`Entry 0x${entry.offset.toString(16)} needs a reason and evidence`);
    }
    const replacement = hexBytes(entry.replacement);
    const end = entry.offset + replacement.length;
    if (entry.offset < 0 || end > size) throw new Error(`Entry 0x${entry.offset.toString(16)} is outside the ROM`);
    if (entry.offset < previousEnd) throw new Error(`Entry 0x${entry.offset.toString(16)} overlaps a previous entry`);
    previousEnd = end;
    const inOriginal = entry.offset < rom.length;
    if (inOriginal) {
      if (end > rom.length) throw new Error(`Entry 0x${entry.offset.toString(16)} straddles the original ROM end`);
      if (entry.original === undefined) throw new Error(`Entry 0x${entry.offset.toString(16)} must declare original bytes`);
      const original = hexBytes(entry.original);
      if (original.length !== replacement.length) throw new Error(`Entry 0x${entry.offset.toString(16)} original/replacement length mismatch`);
      if (!rom.subarray(entry.offset, end).equals(original)) {
        throw new Error(`Entry 0x${entry.offset.toString(16)} original bytes do not match ROM`);
      }
    } else if (entry.original !== undefined) {
      throw new Error(`Entry 0x${entry.offset.toString(16)} is expansion space and cannot declare original bytes`);
    }
  }
}

/** Encode IPS with normal records plus RLE padding records. */
export function encodeIpsWithPadding(changes: IpsChange[], padding: ManifestPatch["padding"]): Buffer {
  const parts: Buffer[] = [Buffer.from("PATCH", "ascii")];
  const records = [
    ...padding.map((p) => ({ offset: p.offset, write: () => {
      const r = Buffer.alloc(8);
      r.writeUIntBE(p.offset, 0, 3); r.writeUInt16BE(0, 3); r.writeUInt16BE(p.count, 5); r[7] = p.value;
      return r;
    } })),
    ...changes.map((c) => ({ offset: c.offset, write: () => {
      const h = Buffer.alloc(5);
      h.writeUIntBE(c.offset, 0, 3); h.writeUInt16BE(c.after.length, 3);
      return Buffer.concat([h, c.after]);
    } })),
  ];
  // Padding first so later normal records overwrite expansion fill.
  for (const record of records) {
    if (record.offset === 0x454f46) throw new Error("IPS offset 0x454F46 collides with the EOF marker");
    parts.push(record.write());
  }
  parts.push(Buffer.from("EOF", "ascii"));
  return Buffer.concat(parts);
}

export function buildManifestPatch(rom: Buffer, manifest: PatchManifest): ManifestPatch {
  validateManifest(rom, manifest);
  const size = manifest.expandTo ?? rom.length;
  const fill = manifest.fill ?? 0xff;
  const padding: ManifestPatch["padding"] = [];
  for (let offset = rom.length; offset < size; offset += 0xffff) {
    padding.push({ offset, count: Math.min(0xffff, size - offset), value: fill });
  }
  const changes: IpsChange[] = [...manifest.entries]
    .sort((a, b) => a.offset - b.offset)
    .map((e) => ({
      offset: e.offset,
      before: e.original === undefined ? Buffer.alloc(0) : hexBytes(e.original),
      after: hexBytes(e.replacement),
    }));
  for (const c of changes) if (c.after.length === 0 || c.after.length > 0xffff) throw new Error("Invalid record size");
  const ips = encodeIpsWithPadding(changes, padding);
  const patched = applyIps(rom, ips, size);
  verifyManifestPatch(rom, patched, manifest);
  return { changes, padding, ips, patched };
}

/** Replay check: every differing byte must be covered by a manifest entry. */
export function verifyManifestPatch(rom: Buffer, patched: Buffer, manifest: PatchManifest): void {
  const size = manifest.expandTo ?? rom.length;
  if (patched.length !== size) throw new Error(`Patched ROM is ${patched.length} bytes, expected ${size}`);
  const covered = new Uint8Array(size);
  for (const e of manifest.entries) {
    const bytes = hexBytes(e.replacement);
    for (let i = 0; i < bytes.length; i++) {
      covered[e.offset + i] = 1;
      if (patched[e.offset + i] !== bytes[i]) throw new Error(`Byte 0x${(e.offset + i).toString(16)} not patched as declared`);
    }
  }
  const fill = manifest.fill ?? 0xff;
  for (let i = 0; i < size; i++) {
    if (covered[i]) continue;
    const expected = i < rom.length ? rom[i] : fill;
    if (patched[i] !== expected) throw new Error(`Undeclared change at 0x${i.toString(16)}`);
  }
}
