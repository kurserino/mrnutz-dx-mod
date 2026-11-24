# Spec Delta

## MODIFIED Requirements

### Requirement: Validated save record
The save record SHALL carry a magic value, a format version and a checksum over its payload. A record that fails any of these checks SHALL be treated as absent. Format version 2 SHALL store, for the fur and for the outfit, either the original palette, a preset or a grid colour. A valid version 1 record (presets only, release v0.2.0) SHALL still be accepted and keep its selection; the next save SHALL write version 2.

#### Scenario: Fresh save file
- **GIVEN** a new or zero-filled save file
- **WHEN** the game powers on
- **THEN** the selection SHALL be the original palette for both fur and outfit.

#### Scenario: Corrupted save file
- **GIVEN** a save file whose record checksum does not match its payload
- **WHEN** the game powers on
- **THEN** the selection SHALL be the original palette for both fur and outfit
- **AND** the game SHALL not hang or show any other colour.

#### Scenario: Out-of-range index
- **GIVEN** a record with a valid checksum but a fur or outfit value that is neither a valid preset nor a valid grid colour
- **WHEN** the game powers on
- **THEN** that value SHALL fall back to the original preset.

#### Scenario: Save from v0.2.0
- **GIVEN** a valid version 1 record with fur preset 2 and outfit preset 3
- **WHEN** the game with this change powers on
- **THEN** Mr. Nutz SHALL show fur preset 2 and outfit preset 3
- **AND** after the next colour change the record SHALL be version 2.

#### Scenario: Grid colour restored after power-off
- **GIVEN** a grid colour was applied to the outfit and saved
- **WHEN** the console is powered off and on again with the same save file
- **THEN** the outfit SHALL show that grid colour.
