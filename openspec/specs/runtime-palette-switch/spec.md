# runtime-palette-switch Specification

## Purpose
Let the player change Mr. Nutz's fur and outfit colours during the game without affecting other objects or gameplay.

## Requirements

### Requirement: Independent runtime cycling
The patched game SHALL allow the player to cycle fur and outfit palette presets independently during gameplay with documented controller shortcuts.

#### Scenario: Change fur only
- **GIVEN** Mr. Nutz is visible and the player is in normal gameplay
- **WHEN** the player presses the assigned fur shortcut once
- **THEN** the fur colors SHALL change to the next preset
- **AND** outfit colors SHALL remain unchanged.

#### Scenario: Change outfit only
- **WHEN** the player presses the outfit shortcut once
- **THEN** outfit colors SHALL change to the next preset
- **AND** fur colors SHALL remain unchanged.

### Requirement: Documented shortcuts
The fur shortcut SHALL be `Select+L` and the outfit shortcut SHALL be `Select+R`. `L` or `R` without `Select` SHALL keep their original behavior.

#### Scenario: Wrap around
- **GIVEN** the last fur preset is selected
- **WHEN** the player presses `Select+L`
- **THEN** the fur SHALL return to the original preset.

### Requirement: Only Mr. Nutz changes colour
The patch SHALL recolour only the sprites of Mr. Nutz. Every other object, including objects that use the same palette `$85:9CC0`, SHALL keep its original colours. The palette slot assigned to `$85:9CC0` by the scene table SHALL never be written; Mr. Nutz SHALL use a private slot in the same colour-math group that no other object uses in the scene, and SHALL keep his original colours when no such slot exists.

#### Scenario: Enemy sharing the Nutz palette
- **GIVEN** an enemy drawn with the same palette as Mr. Nutz
- **WHEN** a non-original preset is selected
- **THEN** the enemy SHALL keep its original colours
- **AND** Mr. Nutz SHALL show the selected colours.

#### Scenario: No free palette slot
- **GIVEN** a scene where every other slot of the Nutz colour-math group is used by other objects
- **WHEN** a non-original preset is selected
- **THEN** Mr. Nutz SHALL keep his original colours in that scene
- **AND** no other object SHALL change colour.

### Requirement: Safe and repeatable update
Palette changes SHALL not cause rendering artifacts, gameplay regressions, or corruption of other sprites.

#### Scenario: Repeated input
- **WHEN** a shortcut is held for multiple frames
- **THEN** input SHALL be debounced so the preset cycles once per intended press.

#### Scenario: Reset and scene transitions
- **WHEN** the level changes or the player resets the game
- **THEN** the visual palette SHALL either persist as documented or reset consistently, without corruption.

### Requirement: Original visual preset
The game SHALL include the exact original color palette as a selectable preset.

#### Scenario: Restore original
- **WHEN** the original preset is selected
- **THEN** all 16 entries SHALL match the original palette.

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
