// Minimal two-pass 65C816 assembler for the runtime patch. It reuses the
// disassembler opcode table so assemble -> disassemble round-trips are testable.
// Syntax: one instruction per line, `label:` lines, `;` comments. Operand width
// is explicit from hex digit count ($12 dp, $1234 abs, $123456 long; #$12 8-bit,
// #$1234 16-bit). Branch/JSL/JML/JMP/JSR operands may be labels.

import { TABLE } from "./snes.js";
import type { Mode } from "./snes.js";

const BRANCH8 = new Set(["BPL", "BMI", "BVC", "BVS", "BRA", "BCC", "BCS", "BNE", "BEQ"]);

function findOpcode(mnemonic: string, modes: Mode[]): { opcode: number; mode: Mode } {
  for (const mode of modes) {
    const opcode = TABLE.findIndex((e) => e.mnemonic === mnemonic && e.mode === mode);
    if (opcode >= 0) return { opcode, mode };
  }
  throw new Error(`No opcode for ${mnemonic} with modes ${modes.join("/")}`);
}

interface Parsed { mnemonic: string; modes: Mode[]; value?: number; label?: string; size: number }

function parseOperand(mnemonic: string, operand: string): Parsed {
  const op = operand.trim();
  const num = (h: string) => parseInt(h, 16);
  let m: RegExpMatchArray | null;
  if (op === "") return { mnemonic, modes: ["imp"], size: 0 };
  if (op === "A") return { mnemonic, modes: ["acc"], size: 0 };
  if (BRANCH8.has(mnemonic)) return { mnemonic, modes: ["rel"], label: op, size: 1 };
  if ((m = op.match(/^#\$([0-9A-Fa-f]+)$/))) {
    const size = m[1].length <= 2 ? 1 : 2;
    return { mnemonic, modes: size === 1 ? ["immM", "immX", "imm8"] : ["immM", "immX", "imm16"], value: num(m[1]), size };
  }
  if ((m = op.match(/^\$([0-9A-Fa-f]{2}),S$/i))) return { mnemonic, modes: ["sr"], value: num(m[1]), size: 1 };
  if ((m = op.match(/^\$([0-9A-Fa-f]+)(,[XY])?$/i))) {
    const digits = m[1].length;
    const idx = (m[2] ?? "").toUpperCase();
    const table: Record<number, Record<string, Mode>> = {
      2: { "": "dp", ",X": "dpx", ",Y": "dpy" },
      4: { "": "abs", ",X": "absx", ",Y": "absy" },
      6: { "": "long", ",X": "longx" },
    };
    const mode = table[digits]?.[idx];
    if (!mode) throw new Error(`Unsupported operand ${op}`);
    return { mnemonic, modes: [mode], value: num(m[1]), size: digits / 2 };
  }
  if (/^[A-Za-z_]\w*$/.test(op)) {
    if (mnemonic === "JSL" || mnemonic === "JML") return { mnemonic, modes: ["long"], label: op, size: 3 };
    if (mnemonic === "JMP" || mnemonic === "JSR") return { mnemonic, modes: ["abs"], label: op, size: 2 };
  }
  throw new Error(`Unsupported operand "${op}" for ${mnemonic}`);
}

/** Assemble `source` at 24-bit CPU address `origin`. Returns bytes and label addresses. */
export function assemble(source: string, origin: number): { bytes: Buffer; labels: Record<string, number> } {
  const lines = source.split("\n").map((l) => l.replace(/;.*$/, "").trim()).filter(Boolean);
  const labels: Record<string, number> = {};
  const items: { parsed: Parsed; address: number; line: string }[] = [];
  let pc = origin;
  // Width tracking: undefined = unknown. REP/SEP and .a8/.a16/.i8/.i16 set it; RTS/RTL/RTI/BRA/BRL/JMP/JML
  // make it unknown. An immediate whose digit count disagrees with a known width is an error.
  let m8: boolean | undefined;
  let x8: boolean | undefined;
  for (const line of lines) {
    const label = line.match(/^([A-Za-z_]\w*):$/);
    if (label) {
      if (labels[label[1]] !== undefined) throw new Error(`Duplicate label ${label[1]}`);
      labels[label[1]] = pc;
      continue;
    }
    const directive = line.match(/^\.(a8|a16|i8|i16)$/i);
    if (directive) {
      const d = directive[1].toLowerCase();
      if (d === "a8" || d === "a16") m8 = d === "a8"; else x8 = d === "i8";
      continue;
    }
    const [mnemonic, ...rest] = line.split(/\s+/);
    const parsed = parseOperand(mnemonic.toUpperCase(), rest.join(" "));
    const { mode } = findOpcode(parsed.mnemonic, parsed.modes);
    const width = mode === "immM" ? m8 : mode === "immX" ? x8 : undefined;
    if (width !== undefined && (parsed.size === 1) !== width) {
      throw new Error(`Immediate width mismatch (${width ? 8 : 16}-bit expected) at "${line}"`);
    }
    if (parsed.mnemonic === "REP" || parsed.mnemonic === "SEP") {
      const v = parsed.value ?? 0;
      if (v & 0x20) m8 = parsed.mnemonic === "SEP";
      if (v & 0x10) x8 = parsed.mnemonic === "SEP";
    }
    if (["RTS", "RTL", "RTI", "BRA", "BRL", "JMP", "JML"].includes(parsed.mnemonic)) { m8 = undefined; x8 = undefined; }
    items.push({ parsed, address: pc, line });
    pc += 1 + parsed.size;
  }
  const out: number[] = [];
  for (const { parsed, address, line } of items) {
    const { opcode } = findOpcode(parsed.mnemonic, parsed.modes);
    let value = parsed.value ?? 0;
    if (parsed.label !== undefined) {
      const target = labels[parsed.label];
      if (target === undefined) throw new Error(`Unknown label ${parsed.label} in "${line}"`);
      if (parsed.modes[0] === "rel") {
        if ((target & 0xff0000) !== (address & 0xff0000)) throw new Error(`Branch crosses bank: ${line}`);
        value = target - (address + 2);
        if (value < -128 || value > 127) throw new Error(`Branch out of range: ${line}`);
        value &= 0xff;
      } else if (parsed.size === 2) {
        if ((target & 0xff0000) !== (address & 0xff0000)) throw new Error(`Absolute target in another bank: ${line}`);
        value = target & 0xffff;
      } else {
        value = target;
      }
    }
    out.push(opcode);
    for (let i = 0; i < parsed.size; i++) out.push((value >> (8 * i)) & 0xff);
  }
  return { bytes: Buffer.from(out), labels };
}
