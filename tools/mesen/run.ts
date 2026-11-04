// Runs a Mesen 2 Lua script headless (--testRunner) and stores its output.
// CLI: tsx tools/mesen/run.ts <script.lua> [--rom file.sfc] [--name trace-name] [--state file.mss] [--define NAME=N]...
// Env (.env, see .env.example): MESEN_PATH (required), ROM_PATH (optional).
// Every script gets tools/mesen/lib.lua prepended (Lua require needs Mesen's I/O permission, which stays off).
// Output protocol on stdout:
//   SHOT <tag> <hex png>     -> output/traces/<name>/<tag>.png (private)
//   STATE <name> <hex mss>   -> output/states/<name>.mss (private savestate)
//   anything else            -> docs/traces/<name>.log (no ROM data, no local paths), unless log=false
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DEFAULT_ROM_PATH } from "../../src/core.js";

if (existsSync(".env")) process.loadEnvFile(".env");
const LIB = resolve("tools/mesen/lib.lua");
export const STATES_DIR = join("output", "states");

export interface RunOptions {
  script: string;
  rom?: string;
  name?: string;
  state?: string;
  defines?: string[];
  log?: boolean; // write docs/traces/<name>.log (default true)
}
export interface RunResult { status: number | null; lines: string[]; name: string }

export function runMesen(o: RunOptions): Promise<RunResult> {
  const mesen = process.env.MESEN_PATH;
  if (!mesen) throw new Error("MESEN_PATH is not set. Copy .env.example to .env and set it.");
  const script = resolve(o.script);
  const rom = resolve(o.rom ?? (process.env.ROM_PATH || DEFAULT_ROM_PATH));
  const name = o.name ?? basename(script, ".lua");
  const defines = o.defines ?? [];
  for (const d of defines) if (!/^[A-Z_][A-Z0-9_]*=-?\d+$/.test(d)) throw new Error(`--define expects NAME=NUMBER, got ${d}`);
  const shotsDir = join("output", "traces", name);
  mkdirSync(shotsDir, { recursive: true });
  const generated = resolve(shotsDir, "script-generated.lua");
  const prefix = (o.state ? `STATE_HEX = "${readFileSync(o.state).toString("hex")}"\n` : "") + defines.map((d) => d + "\n").join("");
  writeFileSync(generated, prefix + readFileSync(LIB, "utf8") + "\n" + readFileSync(script, "utf8"));
  return new Promise((done, fail) => {
    // --timeout: without it the test runner stops long scripts with exit -1 (seen around 2 minutes on 2.2.1).
    const child = spawn(mesen, ["--testRunner", "--timeout=3600", rom, generated]);
    let out = "";
    child.stdout.setEncoding("utf8").on("data", (c: string) => (out += c));
    child.stderr.setEncoding("utf8").on("data", (c: string) => (out += c));
    child.on("error", fail);
    child.on("close", (status) => {
      const log: string[] = [`# ${name} | exit=${status} | rom=${basename(rom)}${o.state ? ` | state=${basename(o.state)}` : ""}${defines.length ? ` | ${defines.join(" ")}` : ""}`];
      for (const line of out.split(/\r?\n/)) {
        const shot = line.match(/^SHOT (\S+) ([0-9A-F]+)$/);
        const state = line.match(/^STATE (\S+) ([0-9A-F]+)$/);
        if (shot) {
          writeFileSync(join(shotsDir, `${shot[1]}.png`), Buffer.from(shot[2], "hex"));
          log.push(`SHOT ${shot[1]} -> ${shotsDir}/${shot[1]}.png`);
        } else if (state) {
          mkdirSync(STATES_DIR, { recursive: true });
          writeFileSync(join(STATES_DIR, `${state[1]}.mss`), Buffer.from(state[2], "hex"));
          log.push(`STATE ${state[1]} -> ${STATES_DIR}/${state[1]}.mss`);
        } else if (line && !line.startsWith("[CPU] Uninitialized")) {
          log.push(line);
        }
      }
      if (o.log ?? true) {
        mkdirSync("docs/traces", { recursive: true });
        writeFileSync(join("docs/traces", `${name}.log`), log.join("\n") + "\n");
      }
      done({ status, lines: log, name });
    });
  });
}

// CLI
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opt = (flag: string) => {
    const i = args.indexOf(flag);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const defines = args.flatMap((a, i) => (a === "--define" && args[i + 1] ? [args[i + 1]] : []));
  const r = await runMesen({ script: args[0] ?? "tools/mesen/trace-palette.lua", rom: opt("--rom"), name: opt("--name"), state: opt("--state"), defines });
  console.log(`exit=${r.status} lines=${r.lines.length} -> docs/traces/${r.name}.log, output/traces/${r.name}/`);
  process.exitCode = r.status ?? 1;
}
