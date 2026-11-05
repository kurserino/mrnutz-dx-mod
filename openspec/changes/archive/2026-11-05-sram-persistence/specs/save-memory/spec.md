# Spec Delta

## Purpose
Give the patched game a safe battery-backed save memory (SRAM), without triggering the original anti-copier protection, to keep the player's options between sessions.

## ADDED Requirements

### Requirement: Declared battery-backed SRAM
The runtime patch SHALL declare battery-backed SRAM of exactly 2 KiB in the internal LoROM header, so that a compliant emulator creates and keeps a save file for the patched game.

#### Scenario: Emulator creates a save file
- **GIVEN** the runtime IPS applied to the supported original ROM
- **WHEN** the game is started in Mesen and then closed
- **THEN** the emulator SHALL report 2 KiB of battery-backed save RAM
- **AND** a save file SHALL exist for the game after it is closed.

### Requirement: Anti-copier checks never trigger
With the declared SRAM present, the patched game SHALL boot and play exactly as the original does without SRAM. No anti-copier check SHALL hang the game or divert it into alternate behaviour. Every neutralized check SHALL be backed by a Mesen trace of its caller and documented with original and replacement bytes.

#### Scenario: Full game with SRAM present
- **GIVEN** the patched game with SRAM declared
- **WHEN** the full-game regression sweep runs from power-on through every stage, the bosses and the credits
- **THEN** the game SHALL never hang
- **AND** gameplay, HUD, palettes other than Mr. Nutz's, and stage order SHALL match the original game.

#### Scenario: Check routine reached
- **WHEN** any of the identified SRAM check routines executes
- **THEN** it SHALL return as if no SRAM were present.

### Requirement: Game data in SRAM is limited to the save record
The patched game SHALL write to SRAM only the save record and, if still reached after neutralization, the bytes the original checks write. The save record SHALL NOT overlap any SRAM address the original game touches.

#### Scenario: SRAM write audit
- **WHEN** the full-game sweep records every write to banks `$70-$7D`
- **THEN** every written address SHALL be inside the save record or in the documented set of original check addresses.

### Requirement: Validated save record
The save record SHALL carry a magic value, a format version and a checksum over its payload. A record that fails any of these checks SHALL be treated as absent.

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
- **GIVEN** a record with a valid checksum but a fur or outfit index beyond the preset count
- **WHEN** the game powers on
- **THEN** that index SHALL fall back to the original preset.
