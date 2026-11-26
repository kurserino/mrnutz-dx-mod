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
The patch SHALL recolour only the sprites of Mr. Nutz; every other object SHALL keep its original colours. During gameplay the scene slot of `$85:9CC0` SHALL never be written: Mr. Nutz SHALL use a private slot that no other object uses and the game does not write, in the scene slot's colour-math group unless the scene is listed with sprite colour math off. Without such a slot he SHALL keep his original colours.

#### Scenario: Enemy sharing the Nutz palette
- **GIVEN** an enemy drawn with the same palette as Mr. Nutz
- **WHEN** a non-original preset is selected
- **THEN** the enemy SHALL keep its original colours
- **AND** Mr. Nutz SHALL show the selected colours.

#### Scenario: No free palette slot
- **GIVEN** a scene not listed as having sprite colour math off, where every other slot of the Nutz colour-math group is used by other objects
- **WHEN** a non-original preset is selected
- **THEN** Mr. Nutz SHALL keep his original colours in that scene
- **AND** no other object SHALL change colour.

#### Scenario: Scene without sprite colour math
- **GIVEN** the witch fight (scene table `$82:D58C`), where sprite palettes 2-7 are used by other objects
- **WHEN** a non-original preset is selected
- **THEN** Mr. Nutz SHALL show the selected colours from a free slot of the other group
- **AND** no other object SHALL change colour.

#### Scenario: Palette animated by the game
- **GIVEN** a stage where the game animates sprite palette 1 entry 1 (`$7E:13BC` non-zero)
- **WHEN** a non-original preset is selected
- **THEN** the private slot SHALL NOT be palette 1
- **AND** no colour of Mr. Nutz SHALL change while he stands still.

#### Scenario: Stage start with an iris-in
- **GIVEN** a stage change that opens with the iris-in transition
- **WHEN** a non-original preset is selected
- **THEN** Mr. Nutz SHALL show the selected colours from the first frame he is visible in the new scene.

#### Scenario: Stage start without an iris
- **GIVEN** a stage change where the hook reaches VBlank from the first gameplay frame
- **WHEN** a non-original preset is selected
- **THEN** Mr. Nutz SHALL show the selected colours from the first frame he is visible in the new scene.

### Requirement: Safe and repeatable update
Palette changes SHALL not cause rendering artifacts, gameplay regressions, or corruption of other sprites. Every PPU access the patch makes (CGRAM writes, OAM reads) SHALL happen inside VBlank, including on lag frames where the game's NMI work runs to the end of VBlank; when there is no time left, the access SHALL be deferred to a later frame.

#### Scenario: Repeated input
- **WHEN** a shortcut is held for multiple frames
- **THEN** input SHALL be debounced so the preset cycles once per intended press.

#### Scenario: Reset and scene transitions
- **WHEN** the level changes or the player resets the game
- **THEN** the visual palette SHALL either persist as documented or reset consistently, without corruption.

#### Scenario: Lag frames during a boss attack
- **GIVEN** a non-original preset is selected and Mr. Nutz shows it in the Mr. Blizzard (yeti) boss scene
- **WHEN** the boss's breath attack fills the screen with sprites and the game's NMI runs to the end of VBlank
- **THEN** Mr. Nutz SHALL keep the selected colours during and after the attack
- **AND** no palette slot SHALL be treated as used by another object unless an object really uses it
- **AND** every other object SHALL keep its original colours.

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

### Requirement: Selected colours on the Stage Clear screen
On every STAGE CLEAR screen, the patch SHALL show Mr. Nutz in the selected colours. Because Mr. Nutz is the only object drawn with palette `$85:9CC0` on that screen, the selection SHALL be written into the slot the screen's palette table assigns to `$85:9CC0`, once, while the screen is still in forced blank. Every other object on the screen SHALL keep its original colours. With the original selection the screen SHALL stay byte-identical to the original game.

#### Scenario: Stage Clear after a stage
- **GIVEN** a non-original preset is selected
- **WHEN** the STAGE CLEAR screen is shown after a stage
- **THEN** Mr. Nutz SHALL show the selected colours for the whole screen
- **AND** the chest and the coins SHALL keep their original colours.

#### Scenario: Original selection
- **GIVEN** the original fur and outfit are selected
- **WHEN** the STAGE CLEAR screen is shown
- **THEN** no CGRAM byte SHALL differ from the original game.

#### Scenario: Next stage
- **GIVEN** the STAGE CLEAR screen showed the selected colours
- **WHEN** the next stage starts
- **THEN** gameplay SHALL use the private slot as before, with no colour corruption of other objects.
