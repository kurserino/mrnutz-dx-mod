// Runs tools/mesen/pause-measure.lua on every stage state (original ROM) and aggregates the pause-menu facts:
// paused-NMI hook state and scanlines, BG3 tiles/palettes in use, visible sprites. Writes docs/traces/pause-measure.log.
//   tsx tools/mesen/pause-measure.ts [--jobs N] [--only 0,14]   (npm run probe:pause-menu)
import { readdirSync, writeFileSync } from "node:fs";
import { availableParallelism } from "node:os";
import { join } from "node:path";
import { STATES_DIR, runMesen } from "./run.js";

const args = process.argv.slice(2);
const opt = (flag: string) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};
const jobs = Number(opt("--jobs") ?? Math.min(6, Math.max(1, availableParallelism() - 1)));
const only = opt("--only")?.split(",").map((s) => `stage-${s.padStart(2, "0")}`);
const stages = readdirSync(STATES_DIR).filter((f) => /^stage-\d+\.mss$/.test(f)).map((f) => f.slice(0, -4)).sort()
  .filter((s) => !only || only.includes(s));

const rows: { stage: string; lines: string[] }[] = [];
let next = 0;
async function worker() {
  while (next < stages.length) {
    const stage = stages[next++];
    const r = await runMesen({ script: "tools/mesen/pause-measure.lua", state: join(STATES_DIR, `${stage}.mss`), name: `pause-measure/${stage}`, log: false });
    rows.push({ stage, lines: r.lines.filter((l) => /^(HOOK|BG3|OBJ|OBJTILES) /.test(l)) });
    process.stdout.write(".");
  }
}
await Promise.all(Array.from({ length: Math.min(jobs, stages.length) }, worker));
console.log("");
rows.sort((a, b) => a.stage.localeCompare(b.stage));

const tilesUsed = new Set<number>();
const out = [`# pause-measure | original ROM | ${rows.length} stage states`];
for (const r of rows) {
  for (const l of r.lines) {
    out.push(`${r.stage} ${l}`);
    const t = l.match(/ tiles=(\S+)/)?.[1];
    if (t) for (const part of t.split(",")) {
      const [a, b] = part.split("-").map((x) => parseInt(x, 16));
      for (let v = a; v <= (b ?? a); v++) tilesUsed.add(v);
    }
  }
}
const sorted = [...tilesUsed].sort((a, b) => a - b);
const runs: string[] = [];
for (let i = 0; i < sorted.length; i++) {
  let j = i;
  while (j + 1 < sorted.length && sorted[j + 1] === sorted[j] + 1) j++;
  runs.push(i === j ? sorted[i].toString(16) : `${sorted[i].toString(16)}-${sorted[j].toString(16)}`);
  i = j;
}
out.push("", `## BG3 tiles used by any stage while paused (union): ${runs.join(",")}`);
// OBJ 8x8 tiles referenced by the frozen OAM, union over the stages that actually paused.
const obj = new Set<number>();
for (const r of rows) {
  if (!r.lines.some((l) => l.includes("paused=$FF"))) continue;
  const t = r.lines.find((l) => l.startsWith("OBJTILES"))?.split(" ")[1];
  if (t) {
    for (const part of t.split(",")) {
      const [a, b] = part.split("-").map((x) => parseInt(x, 16));
      for (let v = a; v <= (b ?? a); v++) obj.add(v);
    }
  }
}
const freeRows: string[] = [];
for (let row = 0; row < 32; row++) {
  let free = true;
  for (let c = 0; c < 16; c++) if (obj.has(row * 16 + c)) free = false;
  if (free) freeRows.push(`row ${row} (tiles $${(row * 16).toString(16)}, VRAM $${(0xc000 + row * 512).toString(16).toUpperCase()})`);
}
out.push(`## OBJ tile rows (16 x 8x8 tiles) never referenced by a visible sprite while paused: ${freeRows.join("; ") || "none"}`);
writeFileSync("docs/traces/pause-measure.log", out.join("\n") + "\n");
console.log(out.slice(-1).join("\n"));
for (const key of ["HOOK", "OBJ"]) {
  const vals = new Map<string, string[]>();
  for (const r of rows) for (const l of r.lines.filter((x) => x.startsWith(key))) {
    const k = l.replace(/runs=\d+ /, "").replace(/visible=\d+ nutzEntries=\d+ /, "");
    vals.set(k, [...(vals.get(k) ?? []), r.stage]);
  }
  for (const [k, s] of vals) console.log(`${k}  <- ${s.length} stages`);
}
console.log("-> docs/traces/pause-measure.log");
