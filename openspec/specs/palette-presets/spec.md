# Palette presets

## Purpose
Allow different fur and outfit colours through a preset.

## Requirements

### Requirement: Independent fur and outfit colors
The tool SHALL accept five ordered fur shades and four ordered outfit shades, encoded as RGB hex colors.

#### Scenario: Different color families
- **GIVEN** a pink fur preset and yellow outfit preset
- **WHEN** a palette is built
- **THEN** fur entries CB through CF and outfit entries C6 through C9 SHALL change independently.
- **AND** all other entries SHALL remain identical to the input palette.

### Requirement: SNES palette encoding
The tool SHALL encode each selected color as little-endian BGR555.

#### Scenario: Target pink
- **GIVEN** the color `#FF557A`
- **WHEN** converted to BGR555
- **THEN** it SHALL produce the little-endian bytes `5F 3D`.
