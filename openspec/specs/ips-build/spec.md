# IPS patch builds

## Purpose
Gerar e verificar patches IPS determinísticos para a ROM suportada.

## Requirements

### Requirement: Minimal IPS patch
For static palette presets the tool SHALL encode only changed palette bytes in a valid IPS file. For runtime modification, the tool SHALL record all additional ROM changed ranges in an explicit manifest with expected original bytes and reasons for each change. It SHALL reject unsupported ROM identities and changes outside the approved manifest.

#### Scenario: Build from supported ROM
- **GIVEN** a supported original ROM and a valid preset
- **WHEN** the build runs
- **THEN** it SHALL output a valid IPS patch and patched ROM
- **AND** every changed byte SHALL be within the palette at offset `0x029CC0` through `0x029CDF`.

#### Scenario: Runtime patch build
- **GIVEN** a validated ROM and reviewed runtime patch manifest
- **WHEN** the runtime patch is built
- **THEN** the IPS SHALL contain only reviewed modifications
- **AND** the tool SHALL verify the patched ROM by replaying the IPS onto a clean copy.

#### Scenario: Rejected manifest
- **GIVEN** a manifest entry whose expected original bytes differ from the ROM, that overlaps another entry, lacks reason/evidence, or targets a ROM with another SHA-256
- **WHEN** the runtime patch is built
- **THEN** the build SHALL fail without writing output.

### Requirement: Reproducible verification
The tool SHALL apply its own IPS output to a copy of the original ROM and verify the resulting palette.

#### Scenario: Round trip
- **WHEN** an IPS patch is built
- **THEN** applying it to the original SHALL match the requested 32-byte palette
- **AND** a JSON report SHALL enumerate original/modified bytes and source identity.

### Requirement: Declared ROM expansion
The tool SHALL support expanding the ROM to a declared size (multiple of 32 KiB, at most 4 MiB), filling new space with a declared byte through IPS RLE records. Entries in expansion space SHALL NOT declare original bytes.

#### Scenario: Expanded build
- **GIVEN** a manifest with `expandTo` and entries in the new space
- **WHEN** the patch is built and replayed
- **THEN** the patched ROM SHALL have exactly the declared size
- **AND** every byte outside manifest entries SHALL equal the original ROM or the declared fill.
