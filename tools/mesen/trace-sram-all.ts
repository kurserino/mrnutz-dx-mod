// Runs tools/mesen/trace-sram.lua over the whole game (sram-persistence tasks 1.3-1.5) and aggregates the result.
//   tsx tools/mesen/trace-sram-all.ts [--rom file.sfc] [--name trace-sram-all] [--jobs N] [--only 3,14] [--light]
// Runs: MODE=0 power-on into level 1; MODE=1 action cycle + pause on every stage state; MODE=2 walk right with
// periodic Start/A and 0 lives on a few stage states (deaths, game over, continue); MODE=3 soft reset from a stage.
// Stage states come from sweep:prepare.
// Writes docs/traces/<name>.log: per run RESULT, then the union of check calls, SRAM accessors and hangs.
import { readdirSync, writeFileSync } from "node:fs";
import { availableParallelism } from "node:os";
import { join } from "node:path";
import { STATES_DIR, runMesen } from "./run.js";
import type { RunOptions, RunResult } from "./run.js";

const args = process.argv.slice(2);
const opt = (flag: string) => {
  const i = args.indexOf(flag);
  return i >= 0 ? args[i + 1] : undefined;
};
const name = opt("--name") ?? "trace-sram-all";
const rom = opt("--rom");
// --light: skip per-access SRAM logging (needed when SRAM exists: check E loops on it forever).
const light = args.includes("--light") ? ["LIGHT=1"] : [];
const jobs = Number(opt("--jobs") ?? Math.min(6, Math.max(1, availableParallelism() - 1)));
const only = opt("--only")?.split(",").map((s) => `stage-${s.padStart(2, "0")}`);
const stages = readdirSync(STATES_DIR).filter((f) => /^stage-\d+\.mss$/.test(f)).map((f) => f.slice(0, -4)).sort()
  .filter((s) => !only || only.includes(s));
const DEATH_STAGES = ["stage-00", "stage-13", "stage-20", "stage-30"].filter((s) => stages.includes(s));
const SCRIPT = "tools/mesen/trace-sram.lua";

const runs: { tag: string; o: RunOptions }[] = [
  { tag: "boot", o: { script: SCRIPT, rom, name: `${name}/boot`, log: false, defines: ["MODE=0", "FRAMES=3000", ...light] } },
  ...stages.map((s) => ({
    tag: s,
    o: { script: SCRIPT, rom, state: join(STATES_DIR, `${s}.mss`), name: `${name}/${s}`, log: false, defines: ["MODE=1", "FRAMES=1500", ...light] },
  })),
  ...["stage-00", "stage-20"].filter((s) => stages.includes(s)).map((s) => ({
    tag: `${s}-reset`,
    o: { script: SCRIPT, rom, state: join(STATES_DIR, `${s}.mss`), name: `${name}/${s}-reset`, log: false, defines: ["MODE=3", "FRAMES=4000", ...light] },
  })),
  ...DEATH_STAGES.map((s) => ({
    tag: `${s}-death`,
    o: { script: SCRIPT, rom, state: join(STATES_DIR, `${s}.mss`), name: `${name}/${s}-death`, log: false, defines: ["MODE=2", "FRAMES=5000", ...light] },
  })),
];
const results: { tag: string; r: RunResult }[] = [];
let next = 0;
async function worker() {
  while (next < runs.length) {
    const run = runs[next++];
    results.push({ tag: run.tag, r: await runMesen(run.o) });
    process.stdout.write(".");
  }
}
const started = Date.now();
await Promise.all(Array.from({ length: Math.min(jobs, runs.length) }, worker));
console.log("");
results.sort((a, b) => a.tag.localeCompare(b.tag));

interface Accessor { r: number; w: number; lo: number; hi: number; runs: string[] }
const out = [`# ${name} | rom=${rom ?? "original"} | ${results.length} runs | ${((Date.now() - started) / 1000).toFixed(0)} s`];
const calls = new Map<string, string>();
const pcs = new Map<string, Accessor>();
const hangs: string[] = [];
const codeReads: string[] = [];
for (const { tag, r } of results) {
  out.push(`${tag}: ${r.lines.find((l) => l.startsWith("RESULT")) ?? `NO RESULT exit=${r.status}`}`);
  for (const l of r.lines) {
    if (l.startsWith("CALL ")) {
      const key = `${l.split(" ")[1]} ${l.match(/jslRet=\S+ jsrRet=\S+/)?.[0] ?? ""}`;
      if (!calls.has(key)) calls.set(key, `${tag}: ${l}`);
    }
    if (l.startsWith("HANG ") || l.startsWith("STALL ")) hangs.push(`${tag}: ${l}`);
    if (l.startsWith("DETECT ")) {
      const key = `DETECT ${l.split(" ")[1]}`;
      if (!calls.has(key)) calls.set(key, `${tag}: ${l}`);
    }
    if (l.startsWith("CODE_READ ")) codeReads.push(`${tag}: ${l}`);
    const m = l.match(/^SRAM_PC pc=\$(\w+) r=(\d+) w=(\d+) addr=\$(\w+)-\$(\w+)/);
    if (m) {
      const e = pcs.get(m[1]) ?? { r: 0, w: 0, lo: Infinity, hi: -1, runs: [] };
      e.r += Number(m[2]);
      e.w += Number(m[3]);
      e.lo = Math.min(e.lo, parseInt(m[4], 16));
      e.hi = Math.max(e.hi, parseInt(m[5], 16));
      e.runs.push(tag);
      pcs.set(m[1], e);
    }
  }
}
const hex = (v: number) => v.toString(16).toUpperCase().padStart(6, "0");
const summary = ["", "## Check routine calls and SRAM-detected branches (first of each)", ...(calls.size ? [...calls.values()] : ["none"])];
summary.push("", "## SRAM accessors (union over all runs)");
for (const [pc, e] of [...pcs].sort()) {
  const list = e.runs.slice(0, 6).join(",") + (e.runs.length > 6 ? ",..." : "");
  summary.push(`pc=$${pc} r=${e.r} w=${e.w} addr=$${hex(e.lo)}-$${hex(e.hi)} runs=${e.runs.length} (${list})`);
}
summary.push("", "## Hangs", ...(hangs.length ? hangs : ["none"]));
summary.push("", "## Data reads of check routine bytes", ...(codeReads.length ? codeReads : ["none"]));
writeFileSync(join("docs/traces", `${name}.log`), [...out, ...summary].join("\n") + "\n");
console.log(summary.join("\n"));
console.log(`-> docs/traces/${name}.log`);
