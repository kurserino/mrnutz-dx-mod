# Spec Delta

## MODIFIED Requirements

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
