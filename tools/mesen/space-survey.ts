// Expansion budget survey over every stage state (pause menu research). Runs tools/mesen/space-survey.lua on the
// ORIGINAL ROM per stage in parallel and aggregates:
//   - WRAM 64-byte blocks never read or written in any run (candidates for menu state / VRAM backup buffers);
//   - VRAM 256-byte blocks never referenced by a tilemap, a tile shown by BG1-3 or a visible sprite (union);
//   - CGRAM palettes / OAM blocks touched after the stage loaded;
//   - PPU layout per stage, and whether our hook site runs during the pause.
//   tsx tools/mesen/space-survey.ts [--jobs N] [--only 0,14]   (npm run survey:space)
// Writes docs/traces/space-survey.log.
import { readdirSync, writeFileSync } from "node:fs";
import { availableParallelism } from "node:os";
import { join } from "node:path";
import { STATES_DIR, runMesen } from "./run.js";
import type { RunResult } from "./run.js";

const args = process.argv.slice(2);
const opt = (flag: string) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};
const jobs = Number(opt("--jobs") ?? Math.min(6, Math.max(1, availableParallelism() - 1)));
const only = opt("--only")?.split(",").map((s) => `stage-${s.padStart(2, "0")}`);
const stages = readdirSync(STATES_DIR).filter((f) => /^stage-\d+\.mss$/.test(f)).map((f) => f.slice(0, -4)).sort()
  .filter((s) => !only || only.includes(s));

const results: { stage: string; r: RunResult }[] = [];
let next = 0;
async function worker() {
  while (next < stages.length) {
    const stage = stages[next++];
    results.push({ stage, r: await runMesen({ script: "tools/mesen/space-survey.lua", state: join(STATES_DIR, `${stage}.mss`), name: `space-survey/${stage}`, log: false }) });
    process.stdout.write(".");
  }
}
const started = Date.now();
await Promise.all(Array.from({ length: Math.min(jobs, stages.length) }, worker));
console.log("");
results.sort((a, b) => a.stage.localeCompare(b.stage));

const union = new Map<string, number[]>();
const layouts: string[] = [];
const pauseRuns: string[] = [];
for (const { stage, r } of results) {
  for (const l of r.lines) {
    const m = l.match(/^MAP (\w+) block=(\d+) ([01]+)$/);
    if (m) {
      const key = `${m[1]}/${m[2]}`;
      const cur = union.get(key) ?? Array(m[3].length).fill(0);
      [...m[3]].forEach((c, i) => { if (c === "1") cur[i]++; });
      union.set(key, cur);
    }
    if (l.startsWith("LAYOUT play")) layouts.push(`${stage}: ${l.replace(/^LAYOUT play frame=\d+ /, "")}`);
    if (l.startsWith("LAYOUT pause")) layouts.push(`${stage} (paused): ${l.replace(/^LAYOUT pause frame=\d+ /, "")}`);
    if (l.startsWith("RESULT")) pauseRuns.push(`${stage}: ${l.slice(7)}`);
  }
}
const hex = (v: number, n = 4) => "$" + v.toString(16).toUpperCase().padStart(n, "0");
// Free runs of never-touched blocks, largest first.
function freeRuns(counts: number[], block: number, base: number, minBytes: number): string[] {
  const runs: { lo: number; len: number }[] = [];
  let start = -1;
  counts.concat([1]).forEach((c, i) => {
    if (c === 0 && start < 0) start = i;
    if (c !== 0 && start >= 0) { runs.push({ lo: start, len: i - start }); start = -1; }
  });
  return runs.filter((r) => r.len * block >= minBytes).sort((a, b) => b.len - a.len)
    .map((r) => `${hex(base + r.lo * block, 6)}-${hex(base + (r.lo + r.len) * block - 1, 6)} (${r.len * block} bytes)`);
}
const out = [`# space-survey | original ROM | ${results.length} stage states | ${((Date.now() - started) / 1000).toFixed(0)} s`];
out.push("Method: per stage, counters reset after the state loads; action cycle, 300-frame pause, action cycle (900 frames).");
out.push("WRAM/CGRAM/OAM: blocks read or written by the CPU/DMA. VRAM: blocks referenced by BG1-3 tilemaps, their tiles or visible sprites.");
const wram = union.get("wram/64");
if (wram) {
  out.push("", "## WRAM never touched in any stage run (64-byte blocks, runs >= 256 bytes)");
  out.push(...freeRuns(wram, 64, 0x7e0000, 256));
}
const vref = union.get("vref/256");
if (vref) {
  out.push("", "## VRAM never referenced in any stage run (byte addresses, 256-byte blocks)");
  out.push(...freeRuns(vref, 256, 0, 256));
  out.push("", "## VRAM referenced: stages per 256-byte block (0-9, + = 10 or more)");
  out.push(vref.map((c) => (c >= 10 ? "+" : String(c))).join("").replace(/(.{64})/g, "$1\n").trim());
}
for (const k of ["cgram/32", "oam/32", "vram/256"]) {
  const u = union.get(k);
  if (u) out.push("", `## ${k}: stages that touched each block after load`, u.map((c) => (c >= 10 ? "+" : String(c))).join(""));
}
out.push("", "## PPU layout per stage (word addresses as reported by Mesen; bytes = x2)", ...layouts);
out.push("", "## Joypad mirror / hook site ($81:828A) runs while playing vs. while paused", ...pauseRuns);
writeFileSync("docs/traces/space-survey.log", out.join("\n") + "\n");
console.log(out.slice(0, out.findIndex((l) => l.startsWith("## PPU layout"))).join("\n"));
console.log(`-> docs/traces/space-survey.log`);
