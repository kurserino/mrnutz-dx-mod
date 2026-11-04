# ROM validation

## Purpose
Evitar patches aplicados em ROMs erradas e proteger a entrada original.

## Requirements

### Requirement: Validated input
The tool SHALL refuse unsupported ROM sizes and mismatching original palette signatures.

#### Scenario: Valid ROM
- **GIVEN** the user-provided unheadered USA En/Fr ROM with the known palette signature
- **WHEN** the tool inspects it
- **THEN** it SHALL accept it and print its size, CRC32 and SHA256.

#### Scenario: Unsupported ROM
- **GIVEN** any ROM with an unexpected size or palette signature
- **WHEN** the tool tries to build a patch
- **THEN** it SHALL fail without writing a patch.

### Requirement: Immutable source
The tool SHALL never overwrite or modify the source ROM.

#### Scenario: Build output
- **WHEN** the tool builds an IPS
- **THEN** it SHALL write all output to a separate output location.
