# Spec Delta

## MODIFIED Requirements

### Requirement: Only Mr. Nutz changes colour
The patch SHALL recolour only the sprites of Mr. Nutz. Every other object, including objects that use the same palette `$85:9CC0`, SHALL keep its original colours. The palette slot assigned to `$85:9CC0` by the scene table SHALL never be written; Mr. Nutz SHALL use a private slot that no other object uses in the scene and that the game does not write during the scene. The private slot SHALL be in the same colour-math group as the scene slot, except in scenes listed as having sprite colour math off, where a slot of the other group MAY be used once the same group has no free slot. Mr. Nutz SHALL keep his original colours when no such slot exists.

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
