// SNES helpers: LoROM address mapping, internal header parsing and a
// static 65C816 disassembler. Static disassembly is linear and only as
// accurate as the M/X flag assumptions given to it; it never replaces an
// emulator trace.

export const HEADER_OFFSET = 0x7fc0;

/** Map a 24-bit CPU address in a LoROM ROM region to a file offset. */
export function loromToFile(cpu: number): number {
  const bank = (cpu >> 16) & 0xff;
  const addr = cpu & 0xffff;
  const b = bank & 0x7f;
  if (b === 0x7e || b === 0x7f) throw new Error(`Bank $${hex(bank, 2)} is WRAM, not ROM`);
  if (addr < 0x8000 && b < 0x40) throw new Error(`$${hex(cpu, 6)} is not a LoROM ROM address`);
  return b * 0x8000 + (addr & 0x7fff);
}

/** Map a file offset to its FastROM (bank $80+) LoROM CPU address. */
export function fileToLorom(offset: number): number {
  return ((0x80 + Math.floor(offset / 0x8000)) << 16) | (0x8000 + (offset % 0x8000));
}

export interface SnesHeader {
  title: string;
  mapMode: number;
  romType: number;
  romSizeKiB: number;
  sramSizeKiB: number;
  region: number;
  version: number;
  checksum: number;
  checksumComplement: number;
  computedChecksum: number;
  vectors: { nmi: number; irq: number; reset: number; brk: number; cop: number };
}

export function parseHeader(rom: Uint8Array): SnesHeader {
  const h = HEADER_OFFSET;
  const word = (o: number) => rom[o] | (rom[o + 1] << 8);
  let sum = 0;
  for (const byte of rom) sum = (sum + byte) & 0xffff;
  return {
    title: Buffer.from(rom.subarray(h, h + 21)).toString("ascii").trimEnd(),
    mapMode: rom[h + 0x15],
    romType: rom[h + 0x16],
    romSizeKiB: 1 << rom[h + 0x17],
    sramSizeKiB: rom[h + 0x18] ? 1 << rom[h + 0x18] : 0,
    region: rom[h + 0x19],
    version: rom[h + 0x1b],
    checksumComplement: word(h + 0x1c),
    checksum: word(h + 0x1e),
    computedChecksum: sum,
    vectors: {
      cop: word(0x7fe4), brk: word(0x7fe6), nmi: word(0x7fea), irq: word(0x7fee), reset: word(0x7ffc),
    },
  };
}

export type Mode =
  | "imp" | "acc" | "imm8" | "immM" | "immX" | "dp" | "dpx" | "dpy" | "idp" | "idpx" | "idpy"
  | "ildp" | "ildpy" | "abs" | "absx" | "absy" | "long" | "longx" | "iabs" | "iabsx" | "ilabs"
  | "rel" | "rel16" | "sr" | "isry" | "blk" | "imm16";

// 65C816 opcode map, rows $00-$F0, 16 "MNEMONIC mode" entries per row.
export const TABLE = `
BRK imm8|ORA idpx|COP imm8|ORA sr|TSB dp|ORA dp|ASL dp|ORA ildp|PHP imp|ORA immM|ASL acc|PHD imp|TSB abs|ORA abs|ASL abs|ORA long
BPL rel|ORA idpy|ORA idp|ORA isry|TRB dp|ORA dpx|ASL dpx|ORA ildpy|CLC imp|ORA absy|INC acc|TCS imp|TRB abs|ORA absx|ASL absx|ORA longx
JSR abs|AND idpx|JSL long|AND sr|BIT dp|AND dp|ROL dp|AND ildp|PLP imp|AND immM|ROL acc|PLD imp|BIT abs|AND abs|ROL abs|AND long
BMI rel|AND idpy|AND idp|AND isry|BIT dpx|AND dpx|ROL dpx|AND ildpy|SEC imp|AND absy|DEC acc|TSC imp|BIT absx|AND absx|ROL absx|AND longx
RTI imp|EOR idpx|WDM imm8|EOR sr|MVP blk|EOR dp|LSR dp|EOR ildp|PHA imp|EOR immM|LSR acc|PHK imp|JMP abs|EOR abs|LSR abs|EOR long
BVC rel|EOR idpy|EOR idp|EOR isry|MVN blk|EOR dpx|LSR dpx|EOR ildpy|CLI imp|EOR absy|PHY imp|TCD imp|JML long|EOR absx|LSR absx|EOR longx
RTS imp|ADC idpx|PER rel16|ADC sr|STZ dp|ADC dp|ROR dp|ADC ildp|PLA imp|ADC immM|ROR acc|RTL imp|JMP iabs|ADC abs|ROR abs|ADC long
BVS rel|ADC idpy|ADC idp|ADC isry|STZ dpx|ADC dpx|ROR dpx|ADC ildpy|SEI imp|ADC absy|PLY imp|TDC imp|JMP iabsx|ADC absx|ROR absx|ADC longx
BRA rel|STA idpx|BRL rel16|STA sr|STY dp|STA dp|STX dp|STA ildp|DEY imp|BIT immM|TXA imp|PHB imp|STY abs|STA abs|STX abs|STA long
BCC rel|STA idpy|STA idp|STA isry|STY dpx|STA dpx|STX dpy|STA ildpy|TYA imp|STA absy|TXS imp|TXY imp|STZ abs|STA absx|STZ absx|STA longx
LDY immX|LDA idpx|LDX immX|LDA sr|LDY dp|LDA dp|LDX dp|LDA ildp|TAY imp|LDA immM|TAX imp|PLB imp|LDY abs|LDA abs|LDX abs|LDA long
BCS rel|LDA idpy|LDA idp|LDA isry|LDY dpx|LDA dpx|LDX dpy|LDA ildpy|CLV imp|LDA absy|TSX imp|TYX imp|LDY absx|LDA absx|LDX absy|LDA longx
CPY immX|CMP idpx|REP imm8|CMP sr|CPY dp|CMP dp|DEC dp|CMP ildp|INY imp|CMP immM|DEX imp|WAI imp|CPY abs|CMP abs|DEC abs|CMP long
BNE rel|CMP idpy|CMP idp|CMP isry|PEI idp|CMP dpx|DEC dpx|CMP ildpy|CLD imp|CMP absy|PHX imp|STP imp|JML ilabs|CMP absx|DEC absx|CMP longx
CPX immX|SBC idpx|SEP imm8|SBC sr|CPX dp|SBC dp|INC dp|SBC ildp|INX imp|SBC immM|NOP imp|XBA imp|CPX abs|SBC abs|INC abs|SBC long
BEQ rel|SBC idpy|SBC idp|SBC isry|PEA imm16|SBC dpx|INC dpx|SBC ildpy|SED imp|SBC absy|PLX imp|XCE imp|JSR iabsx|SBC absx|INC absx|SBC longx
`.trim().split("\n").flatMap((row) => row.split("|").map((cell) => {
  const [mnemonic, mode] = cell.split(" ");
  return { mnemonic, mode: mode as Mode };
}));
if (TABLE.length !== 256) throw new Error("Opcode table must have 256 entries");

export interface Instruction {
  address: number;
  bytes: number[];
  mnemonic: string;
  operand: string;
  /** Flag widths in effect when this instruction was decoded. */
  m8: boolean;
  x8: boolean;
}

export interface DisasmOptions {
  m8?: boolean;
  x8?: boolean;
}

function hex(value: number, digits: number): string {
  return value.toString(16).toUpperCase().padStart(digits, "0");
}

function operandSize(mode: Mode, m8: boolean, x8: boolean): number {
  switch (mode) {
    case "imp": case "acc": return 0;
    case "immM": return m8 ? 1 : 2;
    case "immX": return x8 ? 1 : 2;
    case "abs": case "absx": case "absy": case "iabs": case "iabsx": case "ilabs":
    case "rel16": case "blk": case "imm16": return 2;
    case "long": case "longx": return 3;
    default: return 1;
  }
}

/**
 * Linearly disassemble `length` bytes of `rom` starting at a LoROM CPU address.
 * REP/SEP update M/X widths as they are encountered; branches are not followed.
 */
export function disassemble(rom: Uint8Array, cpu: number, length: number, options: DisasmOptions = {}): Instruction[] {
  let m8 = options.m8 ?? true;
  let x8 = options.x8 ?? true;
  const bank = cpu & 0xff0000;
  let pc = cpu & 0xffff;
  const end = pc + length;
  const out: Instruction[] = [];
  while (pc < end) {
    const address = bank | pc;
    const offset = loromToFile(address);
    const opcode = rom[offset];
    const { mnemonic, mode } = TABLE[opcode];
    const size = operandSize(mode, m8, x8);
    const bytes = Array.from(rom.subarray(offset, offset + 1 + size));
    const v = bytes.slice(1).reduce((acc, b, i) => acc | (b << (8 * i)), 0);
    const next = pc + 1 + size;
    let operand: string;
    switch (mode) {
      case "imp": operand = ""; break;
      case "acc": operand = "A"; break;
      case "imm8": case "immM": case "immX": case "imm16": operand = `#$${hex(v, size * 2)}`; break;
      case "dp": operand = `$${hex(v, 2)}`; break;
      case "dpx": operand = `$${hex(v, 2)},X`; break;
      case "dpy": operand = `$${hex(v, 2)},Y`; break;
      case "idp": operand = `($${hex(v, 2)})`; break;
      case "idpx": operand = `($${hex(v, 2)},X)`; break;
      case "idpy": operand = `($${hex(v, 2)}),Y`; break;
      case "ildp": operand = `[$${hex(v, 2)}]`; break;
      case "ildpy": operand = `[$${hex(v, 2)}],Y`; break;
      case "abs": operand = `$${hex(v, 4)}`; break;
      case "absx": operand = `$${hex(v, 4)},X`; break;
      case "absy": operand = `$${hex(v, 4)},Y`; break;
      case "long": operand = `$${hex(v, 6)}`; break;
      case "longx": operand = `$${hex(v, 6)},X`; break;
      case "iabs": operand = `($${hex(v, 4)})`; break;
      case "iabsx": operand = `($${hex(v, 4)},X)`; break;
      case "ilabs": operand = `[$${hex(v, 4)}]`; break;
      case "sr": operand = `$${hex(v, 2)},S`; break;
      case "isry": operand = `($${hex(v, 2)},S),Y`; break;
      case "blk": operand = `$${hex(bytes[2], 2)},$${hex(bytes[1], 2)}`; break;
      case "rel": operand = `$${hex(bank | ((next + ((v << 24) >> 24)) & 0xffff), 6)}`; break;
      case "rel16": operand = `$${hex(bank | ((next + ((v << 16) >> 16)) & 0xffff), 6)}`; break;
    }
    out.push({ address, bytes, mnemonic, operand, m8, x8 });
    if (mnemonic === "REP") { if (v & 0x20) m8 = false; if (v & 0x10) x8 = false; }
    if (mnemonic === "SEP") { if (v & 0x20) m8 = true; if (v & 0x10) x8 = true; }
    pc = next;
  }
  return out;
}

export function formatInstruction(ins: Instruction): string {
  const bytes = ins.bytes.map((b) => hex(b, 2)).join(" ").padEnd(12);
  const flags = `${ins.m8 ? "m" : "M"}${ins.x8 ? "x" : "X"}`;
  return `$${hex(ins.address, 6)}  ${bytes} ${flags}  ${ins.mnemonic}${ins.operand ? " " + ins.operand : ""}`;
}

export function parseCpuAddress(text: string): number {
  const clean = text.replace(/[$:]/g, "");
  if (!/^[0-9a-fA-F]{6}$/.test(clean)) throw new Error(`Expected a 24-bit address like $9D:AC60, got ${text}`);
  return parseInt(clean, 16);
}
