# Spec Delta

## ADDED Requirements

### Requirement: Grid colour selection
Besides the original palette and the presets, the fur and the outfit SHALL each accept one of 32 fixed grid colours chosen in the pause menu, shown as 5 fur shades or 4 outfit shades derived from it, ordered dark to light like the original gradients. Grid colours SHALL follow every rule that applies to presets.

#### Scenario: Grid colour in gameplay
- **GIVEN** a grid colour was applied to the fur in the pause menu
- **WHEN** gameplay resumes
- **THEN** Mr. Nutz's fur SHALL show the 5 shades generated for that colour, darkest to lightest
- **AND** objects sharing his original palette SHALL keep their colours.

#### Scenario: Same rules as presets
- **GIVEN** a grid colour on the fur and a grid colour on the outfit
- **WHEN** a scene has no free private palette slot
- **THEN** Mr. Nutz SHALL keep his original colours there
- **AND** the transparent entry and the entries outside the fur and outfit gradients SHALL keep their original values.

#### Scenario: Shades are deterministic
- **GIVEN** the 32-colour grid definition
- **WHEN** the patch is built twice
- **THEN** the generated shade tables SHALL be byte-identical.

### Requirement: Shortcuts after a grid colour
When the fur or the outfit holds a grid colour, its `Select` shortcut SHALL move it to the original palette; further presses SHALL cycle the presets as before.

#### Scenario: Leave a grid colour with the shortcut
- **GIVEN** the outfit holds a grid colour
- **WHEN** the player presses `Select+R`
- **THEN** the outfit SHALL show the original colours
- **AND** the next `Select+R` SHALL show the first preset.
