// Fast full-game regression sweep of the runtime palette patch.
//   tsx tools/mesen/sweep.ts [--prepare] [--jobs N] [--only 3,14,15] [--frames-report]
// 1. Stage savestates (output/states/stage-NN.mss) come from prepare-stages.lua on the ORIGINAL ROM; they are
//    built once (or with --prepare) and do not depend on the patch build.
// 2. stage-check.lua runs once per stage on output/Mr. Nutz.runtime.sfc, N Mesen instances in parallel
//    (SWEEP_JOBS or --jobs, default: CPU count - 1, max 6).
// 3. flicker-check.lua per stage: 24 colour changes, no frame may fall back to the original colours (flash).
// 4. persist-check.lua: selection across world changes and a soft reset.
// Writes docs/traces/sweep-all.log; exit code 1 on any violation, missing result or persistence failure.
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { availableParallelism } from "node:os";
import { join } from "node:path";
import { STATES_DIR, runMesen } from "./run.js";
import { DEFAULT_ROM_PATH } from "../../src/core.js";
import { buildRuntimePatch } from "../../src/runtime.js";
import type { RuntimePresetFile } from "../../src/runtime.js";

const args = process.argv.slice(2);
const opt = (flag: string) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};
const PATCHED = "output/Mr. Nutz.runtime.sfc";
const LEVEL1_STATE = "roms/states/level1-start.mss";
// State used for the persistence check: early Woody Land, so the warps cross into the next world.
const PERSIST_STAGE = "stage-03";
const jobs = Number(opt("--jobs") ?? process.env.SWEEP_JOBS ?? Math.min(6, Math.max(1, availableParallelism() - 1)));
const only = opt("--only")?.split(",").map((s) => `stage-${s.padStart(2, "0")}`);
const started = Date.now();

// Always test the current build (a stale output ROM once made a sweep test old code).
const presets = JSON.parse(readFileSync("presets/runtime.json", "utf8")) as RuntimePresetFile;
writeFileSync(PATCHED, buildRuntimePatch(readFileSync(process.env.ROM_PATH || DEFAULT_ROM_PATH), presets).patched);
if (args.includes("--prepare") || !existsSync(join(STATES_DIR, "stage-00.mss"))) {
  if (!existsSync(LEVEL1_STATE)) throw new Error(`${LEVEL1_STATE} missing (copy of a level 1 savestate, see docs/runtime-hook.md)`);
  console.log("preparing stage states on the original ROM...");
  const p = await runMesen({ script: "tools/mesen/prepare-stages.lua", state: LEVEL1_STATE, name: "sweep-prepare" });
  console.log(p.lines.filter((l) => l.startsWith("DONE")).join("\n"));
}
const stages = readdirSync(STATES_DIR).filter((f) => /^stage-\d+\.mss$/.test(f)).map((f) => f.slice(0, -4)).sort()
  .filter((s) => !only || only.includes(s));

interface StageResult { stage: string; result?: Record<string, string>; flicker?: Record<string, string>; events: string[]; status: number | null }
const parse = (lines: string[]) => {
  const line = lines.find((l) => l.startsWith("RESULT "));
  return line ? Object.fromEntries(line.slice(7).split(" ").map((kv) => kv.split("=") as [string, string])) : undefined;
};
const results: StageResult[] = [];
let next = 0;
async function worker() {
  while (next < stages.length) {
    const stage = stages[next++];
    const r = await runMesen({ script: "tools/mesen/stage-check.lua", rom: PATCHED, state: join(STATES_DIR, `${stage}.mss`), name: `sweep/${stage}`, log: false });
    const fl = await runMesen({ script: "tools/mesen/flicker-check.lua", rom: PATCHED, state: join(STATES_DIR, `${stage}.mss`), name: `sweep/${stage}-flicker`, log: false });
    const events = r.lines.filter((l) => /^(SHARED_CHANGED|FOREIGN_ON_X|SHORTCUT_FAIL|HDMA_LATE) /.test(l));
    results.push({ stage, result: parse(r.lines), flicker: parse(fl.lines), events, status: r.status });
    process.stdout.write(".");
  }
}
const persist = runMesen({ script: "tools/mesen/persist-check.lua", rom: PATCHED, state: join(STATES_DIR, `${PERSIST_STAGE}.mss`), name: "sweep/persist", log: false });
await Promise.all(Array.from({ length: Math.min(jobs, stages.length) }, worker));
const p = only ? undefined : await persist;
console.log("");

results.sort((a, b) => a.stage.localeCompare(b.stage));
const out: string[] = [`# sweep-all | ${stages.length} stages | jobs=${jobs} | ${((Date.now() - started) / 1000).toFixed(0)} s`];
let violations = 0;
const original: string[] = [];
for (const r of results) {
  const x = r.result;
  if (!x) { violations++; out.push(`${r.stage} NO RESULT exit=${r.status}`); continue; }
  const flash = r.flicker ? Number(r.flicker.flash) : NaN;
  const bad = Number(x.sharedChanged) > 0 || Number(x.foreignOnX) > 0 || Number(x.hdmaLate) > 0 || !(flash === 0)
    || r.events.some((e) => e.startsWith("SHORTCUT_FAIL"));
  if (bad) violations++;
  const pct = Number(x.nutzFrames) ? ((100 * Number(x.ok)) / Number(x.nutzFrames)).toFixed(1) : "-";
  if (pct !== "-" && Number(pct) < 99) original.push(`${r.stage} (${pct}%)`);
  out.push(`${r.stage} ${bad ? "VIOLATION" : "ok"} nutzColoured=${pct}% gameplay=${x.gameplay} nutzFrames=${x.nutzFrames} lostMax=${x.lostMax} sharedChanged=${x.sharedChanged} foreignOnX=${x.foreignOnX} hdmaLate=${x.hdmaLate} hdmaMaxLine=${x.hdmaMaxLine} flash=${r.flicker?.flash ?? "NO RESULT"} slotSwitch=${r.flicker?.switch ?? "-"} noSlot=${x.noSlot} slots(S/X)=${x.slots} idx=${x.idx}`);
  for (const e of r.events) out.push(`  ${e}`);
}
if (p) {
  const res = p.lines.find((l) => l.startsWith("RESULT"));
  const fails = Number(res?.match(/fails=(\d+)/)?.[1] ?? 1);
  if (!res || fails > 0) violations++;
  out.push(`persist (${PERSIST_STAGE}): ${res ?? "NO RESULT"}`);
  for (const l of p.lines.filter((l) => l.startsWith("PERSIST"))) out.push(`  ${l}`);
}
out.push(`summary: violations=${violations}; Mr. Nutz kept original colours (no free slot) in: ${original.join(", ") || "none"}`);
writeFileSync("docs/traces/sweep-all.log", out.join("\n") + "\n");
console.log(out.filter((l) => !l.startsWith("stage-") || l.includes("VIOLATION") || l.includes("NO RESULT")).join("\n"));
console.log(`-> docs/traces/sweep-all.log, screenshots in output/traces/sweep/`);
process.exitCode = violations ? 1 : 0;
