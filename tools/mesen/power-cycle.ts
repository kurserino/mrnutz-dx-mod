// Power-cycle persistence check of the SRAM save (openspec/changes/archive/2026-11-05-sram-persistence, task 3.4).
//   tsx tools/mesen/power-cycle.ts      (npm run check:power; also step 5 of npm run sweep:all)
// Each step is a new Mesen process = a real power-on; Mesen keeps the battery save in <Mesen dir>/Saves/<rom>.srm.
// The test ROM gets its own name so it never touches the user's saves:
//   1. no save file           -> boot shows the original colours (0/0); select fur 2 / outfit 3; the .srm holds the record
//   2. same save file         -> boot restores 2/3 and Mr. Nutz shows them
//   3. checksum corrupted     -> boot falls back to 0/0
//   4. fur index out of range -> fur 0, outfit kept
// Writes docs/traces/power-cycle.log; exit code 1 on any failure.
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runMesen } from "./run.js";
import { DEFAULT_ROM_PATH } from "../../src/core.js";
import { SAVE_RECORD, buildRuntimePatch, encodeSaveRecord } from "../../src/runtime.js";
import type { RuntimePresetFile } from "../../src/runtime.js";

if (existsSync(".env")) process.loadEnvFile(".env");
const NAME = "Mr. Nutz.power-test";
const RECORD_OFFSET = SAVE_RECORD.address & 0x7fff;

export async function powerCycle(): Promise<{ fails: number; lines: string[] }> {
  const mesen = process.env.MESEN_PATH;
  if (!mesen) throw new Error("MESEN_PATH is not set");
  const rom = join("output", "power-test", `${NAME}.sfc`);
  const srm = join(dirname(mesen), "Saves", `${NAME}.srm`);
  const presets = JSON.parse(readFileSync("presets/runtime.json", "utf8")) as RuntimePresetFile;
  mkdirSync(dirname(rom), { recursive: true });
  writeFileSync(rom, buildRuntimePatch(readFileSync(process.env.ROM_PATH || DEFAULT_ROM_PATH), presets).patched);

  const out: string[] = [`# power-cycle | rom=${NAME}.sfc (runtime build) | save=Saves/${NAME}.srm`];
  let fails = 0;
  const parse = (lines: string[], tag: string) => {
    const l = lines.find((x) => x.startsWith(`CHECK ${tag} `));
    const idx = l?.match(/idx=(\d+)\/(\d+)/);
    return { line: l ?? `CHECK ${tag} missing`, fur: Number(idx?.[1]), outfit: Number(idx?.[2]), nutzOk: l?.includes("nutzOk=true") ?? false };
  };
  const expect = (step: string, ok: boolean, detail: string) => {
    if (!ok) fails++;
    out.push(`${ok ? "ok  " : "FAIL"} ${step}: ${detail}`);
  };
  const writeSave = (record: Buffer) => {
    const data = Buffer.alloc(2048, 0x00);
    record.copy(data, RECORD_OFFSET);
    mkdirSync(dirname(srm), { recursive: true });
    writeFileSync(srm, data);
  };
  const run = async (step: string, select: boolean, warps = 0) => {
    const defines = [`SELECT=${select ? 1 : 0}`, `WARPS=${warps}`];
    const r = await runMesen({ script: "tools/mesen/power-check.lua", rom, name: `power-cycle/${step}`, log: false, defines });
    out.push(...r.lines.filter((l) => l.startsWith("CHECK") || l.startsWith("RESULT")).map((l) => `  ${step}: ${l}`));
    return r.lines;
  };

  // 1. Fresh: no save file.
  rmSync(srm, { force: true });
  let lines = await run("1-fresh", true);
  let b = parse(lines, "boot");
  expect("1 fresh boot is original", b.fur === 0 && b.outfit === 0, b.line);
  const sel = parse(lines, "selected");
  expect("1 selection applied", sel.fur === 2 && sel.outfit === 3 && sel.nutzOk, sel.line);
  const saved = existsSync(srm) ? readFileSync(srm).subarray(RECORD_OFFSET, RECORD_OFFSET + 8) : Buffer.alloc(0);
  const want = encodeSaveRecord(2, 3);
  expect("1 save file holds the record", saved.equals(want), `srm=${saved.toString("hex").toUpperCase()} expected=${want.toString("hex").toUpperCase()}`);

  // 2. Power cycle with the same save file, then 10 stage skips (into the next world) with the restored colours.
  lines = await run("2-restore", false, 10);
  b = parse(lines, "boot");
  expect("2 power-on restores 2/3", b.fur === 2 && b.outfit === 3 && b.nutzOk, b.line);
  const warps = lines.filter((l) => /^CHECK warp-\d+ frame/.test(l));
  // A scene without a free private slot (X=255: witch boss = stage-08, spider boss, credits) keeps the original
  // colours by design; the index must still be 2/3 and no shared palette may change.
  const warpsOk = warps.filter((l) => l.includes("idx=2/3") && l.includes("sharedChanged=false") && (l.includes("nutzOk=true") || l.includes(" X=255 ")));
  expect("2 restored colours in every stage after the power-on (10 skips, next world)", warps.length === 10 && warpsOk.length === warps.length,
    `${warpsOk.length}/${warps.length} gameplay stages ok`);

  // 3. Corrupted checksum.
  const corrupt = encodeSaveRecord(2, 3);
  corrupt[7] ^= 0x55;
  writeSave(corrupt);
  lines = await run("3-corrupt", false);
  b = parse(lines, "boot");
  expect("3 corrupted record falls back to 0/0", b.fur === 0 && b.outfit === 0, b.line);

  // 4. Valid checksum, fur index out of range.
  writeSave(encodeSaveRecord(9, 1));
  lines = await run("4-range", false);
  b = parse(lines, "boot");
  expect("4 out-of-range fur falls back to 0, outfit kept", b.fur === 0 && b.outfit === 1, b.line);

  rmSync(srm, { force: true });
  out.push(`summary: fails=${fails}`);
  writeFileSync("docs/traces/power-cycle.log", out.join("\n") + "\n");
  return { fails, lines: out };
}

// CLI
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const r = await powerCycle();
  console.log(r.lines.join("\n"));
  process.exitCode = r.fails ? 1 : 0;
}
