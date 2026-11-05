# rom-analysis Specification

## Purpose
Provide static tools (LoROM mapping, 65C816 disassembly and header inspection) to study the supported ROM without an emulator.

## Requirements

### Requirement: LoROM address mapping
The tool SHALL convert LoROM CPU addresses to file offsets and back, and SHALL reject WRAM banks and non-ROM low halves.

#### Scenario: Character palette address
- **WHEN** `$85:9CC0` is mapped
- **THEN** the file offset SHALL be `0x029CC0`.

### Requirement: Static 65C816 disassembly
The tool SHALL disassemble ROM bytes linearly from a CPU address, tracking M/X widths through REP/SEP, and label output as static (not a trace).

#### Scenario: Width tracking
- **GIVEN** `REP #$20` followed by `LDA #imm`
- **WHEN** disassembled with 8-bit defaults
- **THEN** the `LDA` immediate SHALL be decoded as 16-bit.

### Requirement: Header inspection
The tool SHALL print the internal header, computed checksum, and interrupt vectors.

#### Scenario: Supported ROM header
- **GIVEN** the supported ROM
- **WHEN** the header is inspected
- **THEN** map mode SHALL be `$30` and the stored checksum SHALL equal the computed checksum.
