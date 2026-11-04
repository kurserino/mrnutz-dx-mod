import { existsSync, readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import {
  DEFAULT_ROM_PATH, PALETTE_FILE_OFFSET, PALETTE_LENGTH, ORIGINAL_PALETTE, crc32,
  assertSupportedRom, identity, bgr555ToRgbHex, buildPalette,
  diffPalette, encodeIps, verifyPatch, applyIps,
} from "./core.js";
import type { PalettePreset } from "./core.js";
import { disassemble, formatInstruction, parseCpuAddress, parseHeader } from "./snes.js";
import { buildRuntimePatch } from "./runtime.js";
import type { RuntimePresetFile } from "./runtime.js";

if (existsSync(".env")) process.loadEnvFile(".env");
const args = process.argv.slice(2);
const cmd = args[0] ?? "help";
const value = (flag: string, fallback: string): string => {
  const i = args.indexOf(flag);
  if (i < 0) return fallback;
  if (!args[i + 1]) throw new Error(`Missing value for ${flag}`);
  return args[i + 1];
};
const source = value("--rom", process.env.ROM_PATH || DEFAULT_ROM_PATH);
const presetPath = value("--preset", "presets/pink-fur-yellow-outfit.json");
const outputDir = value("--out", "output");

try {
  if (cmd === "help") {
    console.log("Commands: inspect | palette | header | disasm <$BB:AAAA> <len-hex> [--m16] [--x16] | build | verify");
    console.log("Options: --rom <file.sfc> --preset <file.json> --out <directory>");
    console.log("disasm flags: lowercase m/x in output = 8-bit, uppercase M/X = 16-bit; static, not a trace.");
  } else {
    const rom = readFileSync(source);
    if (cmd === "inspect") {
      console.log(JSON.stringify({ input: basename(source), ...identity(rom) }, null, 2));
      assertSupportedRom(rom);
      console.log("ROM palette signature: MATCH");
    } else if (cmd === "palette") {
      assertSupportedRom(rom);
      console.log("Palette $C0-$CF at ROM offset 0x" + PALETTE_FILE_OFFSET.toString(16));
      for (let i = 0; i < PALETTE_LENGTH / 2; i++) {
        const bgr = ORIGINAL_PALETTE.readUInt16LE(i * 2);
        console.log(`$${(0xc0 + i).toString(16).toUpperCase()}: 0x${bgr.toString(16).padStart(4, "0")} ${bgr555ToRgbHex(bgr)}`);
      }
    } else if (cmd === "header") {
      const { vectors, ...header } = parseHeader(rom);
      const hex = (n: number) => `$${n.toString(16).toUpperCase().padStart(4, "0")}`;
      console.log(JSON.stringify({
        ...header, mapMode: hex(header.mapMode), checksum: hex(header.checksum),
        checksumComplement: hex(header.checksumComplement), computedChecksum: hex(header.computedChecksum),
        vectors: Object.fromEntries(Object.entries(vectors).map(([k, v]) => [k, hex(v)])),
      }, null, 2));
    } else if (cmd === "disasm") {
      // Usage: disasm <$BB:AAAA> <length-hex> [--m16] [--x16]
      const start = parseCpuAddress(args[1] ?? "");
      const length = parseInt(args[2] ?? "40", 16);
      const lines = disassemble(rom, start, length, { m8: !args.includes("--m16"), x8: !args.includes("--x16") });
      for (const ins of lines) console.log(formatInstruction(ins));
    } else if (cmd === "runtime") {
      const presets = JSON.parse(readFileSync(value("--presets", "presets/runtime.json"), "utf8")) as RuntimePresetFile;
      const { ips, patched, manifest } = buildRuntimePatch(rom, presets);
      mkdirSync(outputDir, { recursive: true });
      writeFileSync(join(outputDir, "Mr. Nutz.runtime.ips"), ips);
      writeFileSync(join(outputDir, "Mr. Nutz.runtime.sfc"), patched);
      writeFileSync(join(outputDir, "runtime-report.json"), JSON.stringify({
        source: basename(source), sourceIdentity: identity(rom),
        patched: { size: patched.length, crc32: crc32(patched) }, ipsBytes: ips.length,
        manifest: { ...manifest, entries: manifest.entries.map((e) => ({ ...e, offset: `0x${e.offset.toString(16).toUpperCase()}` })) },
      }, null, 2));
      console.log(`Wrote ${join(outputDir, "Mr. Nutz.runtime.ips")} (${ips.length} bytes), Mr. Nutz.runtime.sfc, runtime-report.json`);
    } else if (cmd === "build" || cmd === "verify") {
      assertSupportedRom(rom);
      const preset = JSON.parse(readFileSync(presetPath, "utf8")) as PalettePreset;
      const target = buildPalette(preset);
      const changes = diffPalette(rom, target);
      const ips = encodeIps(changes);
      verifyPatch(rom, ips, target);
      const patched = applyIps(rom, ips);
      mkdirSync(outputDir, { recursive: true });
      const patchPath = join(outputDir, "Mr. Nutz.ips");
      const romPath = join(outputDir, "Mr. Nutz.patched.sfc");
      const reportPath = join(outputDir, "patch-report.json");
      if (cmd === "build") {
        writeFileSync(patchPath, ips);
        writeFileSync(romPath, patched);
        writeFileSync(reportPath, JSON.stringify({
          source: basename(source), sourceIdentity: identity(rom), preset,
          patchedIdentity: identity(patched),
          modifiedBytes: changes.reduce((sum, change) => sum + change.after.length, 0),
          changes: changes.map(({ offset, before, after }) => ({
            offset: `0x${offset.toString(16).toUpperCase()}`, before: before.toString("hex"), after: after.toString("hex"),
          })),
        }, null, 2));
        console.log(`Wrote ${patchPath}, ${romPath}, ${reportPath}`);
      } else {
        console.log(`Verified palette changes: ${changes.length} IPS records`);
        console.log(`Current expected output: ${patchPath}`);
      }
    } else {
      throw new Error(`Unknown command: ${cmd}`);
    }
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
}
