# Spec Delta

## ADDED Requirements

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
