# IPS patch builds

## Purpose
Gerar e verificar patches IPS determinísticos para a ROM suportada.

## Requirements

### Requirement: Minimal IPS patch
The tool SHALL encode only changed palette bytes in a valid IPS file.

#### Scenario: Build from supported ROM
- **GIVEN** a supported original ROM and a valid preset
- **WHEN** the build runs
- **THEN** it SHALL output a valid IPS patch and patched ROM
- **AND** every changed byte SHALL be within the palette at offset `0x029CC0` through `0x029CDF`.

### Requirement: Reproducible verification
The tool SHALL apply its own IPS output to a copy of the original ROM and verify the resulting palette.

#### Scenario: Round trip
- **WHEN** an IPS patch is built
- **THEN** applying it to the original SHALL match the requested 32-byte palette
- **AND** a JSON report SHALL enumerate original/modified bytes and source identity.
