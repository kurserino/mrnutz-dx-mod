# Spec Delta

## ADDED Requirements

### Requirement: Selection survives power cycles
The fur and outfit selection SHALL be saved whenever the player changes it and SHALL be restored on the next power-on, as long as the save file is kept. The restored colours SHALL follow the same rules as a live selection: only Mr. Nutz changes colour, and he keeps his original colours where no private palette slot exists.

#### Scenario: Restore after power-off
- **GIVEN** the player selected a non-original fur and a non-original outfit
- **WHEN** the console is powered off and on again with the same save file
- **THEN** Mr. Nutz SHALL show the selected fur and outfit in the first gameplay scene
- **AND** objects that share his original palette SHALL keep their original colours.

#### Scenario: Last change wins
- **GIVEN** the player cycles the fur several times
- **WHEN** the console is powered off right after the last change and on again
- **THEN** the restored fur SHALL be the last one selected.

#### Scenario: No save file
- **GIVEN** no save file exists
- **WHEN** the game powers on
- **THEN** the selection SHALL be the original palette, exactly as in release v0.1.0.

#### Scenario: Soft reset keeps the selection
- **GIVEN** a non-original selection
- **WHEN** the player soft-resets the console
- **THEN** the selection SHALL persist, as in release v0.1.0.
