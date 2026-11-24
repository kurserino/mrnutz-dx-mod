# Spec Delta

## Purpose
Give the player an in-game menu during the native pause, starting with a colour picker for Mr. Nutz's fur and outfit, and leave the game exactly as it was when the menu closes.

## ADDED Requirements

### Requirement: Menu opens with the native pause
When the player pauses the game during gameplay, the patched game SHALL show the pause menu over the frozen scene: a "PAUSE" title and a list whose items are CHANGE OUTFIT and RESUME, with the cursor on the first item. Where the original game does not pause (dialogs, intros, game-driven sequences), no menu SHALL appear.

#### Scenario: Pause during gameplay
- **GIVEN** Mr. Nutz is in normal gameplay
- **WHEN** the player presses Start
- **THEN** the game SHALL freeze as in the original game
- **AND** the menu SHALL appear with "PAUSE", CHANGE OUTFIT and RESUME, cursor on CHANGE OUTFIT.

#### Scenario: Screen that cannot pause
- **GIVEN** a dialog box or a game-driven sequence where the original game ignores Start
- **WHEN** the player presses Start
- **THEN** no menu SHALL appear and the game SHALL behave as the original.

### Requirement: Menu navigation
On the list, Up and Down SHALL move the cursor and wrap around. A or Start SHALL activate the item under the cursor. Start on the list, or activating RESUME, SHALL close the menu and resume the game. Inputs SHALL act once per press.

#### Scenario: Resume
- **GIVEN** the menu is open on the list
- **WHEN** the player presses Start, or selects RESUME and presses A
- **THEN** the menu SHALL close and gameplay SHALL continue from the frozen frame.

#### Scenario: Held button
- **WHEN** the player holds Down for several frames
- **THEN** the cursor SHALL move one item only.

### Requirement: Change Outfit modal
Activating CHANGE OUTFIT SHALL open a modal with a title bar holding FUR and CLOTHES tabs, an 8 × 4 grid of 32 colours and a preview of the Mr. Nutz sprite. The modal SHALL open on the FUR tab, with the cursor on the colour currently applied to the fur when it is a grid colour, else on the first cell. L and R SHALL switch tabs; the D-pad SHALL move the cursor in the grid, wrapping at the edges.

#### Scenario: Open the modal
- **WHEN** the player activates CHANGE OUTFIT
- **THEN** the modal SHALL show the FUR tab as active, the 32 colours and the Mr. Nutz preview.

#### Scenario: Switch tab
- **GIVEN** the FUR tab is active
- **WHEN** the player presses R
- **THEN** the CLOTHES tab SHALL become active and the grid cursor SHALL move to the colour currently applied to the outfit when it is a grid colour.

### Requirement: Live preview
The preview SHALL show Mr. Nutz with the colour under the cursor applied to the active part (fur or clothes) and the current colours on the other part, updating within one frame of each cursor move. The preview SHALL NOT change the saved selection.

#### Scenario: Browse colours
- **GIVEN** the FUR tab is active
- **WHEN** the player moves the cursor to another colour
- **THEN** the preview's fur SHALL show that colour's shades within one frame
- **AND** its clothes SHALL keep the current outfit colours.

### Requirement: Apply or cancel
In the modal, A SHALL apply the colour under the cursor to the active part, save the selection, and keep the modal open. B SHALL close the modal and return to the list. Colours previewed but not applied SHALL be discarded.

#### Scenario: Apply fur colour
- **GIVEN** the cursor is on a grid colour on the FUR tab
- **WHEN** the player presses A, then B, then resumes
- **THEN** Mr. Nutz SHALL show the new fur in gameplay
- **AND** the selection SHALL be saved.

#### Scenario: Cancel
- **GIVEN** the player moved the cursor without pressing A
- **WHEN** the player presses B and resumes
- **THEN** Mr. Nutz SHALL keep the colours he had before the pause.

### Requirement: Game state restored on close
When the menu closes, the video memory, palettes and sprite table the menu used SHALL be identical to their state at the moment the game paused, except for Mr. Nutz's own palette when a new colour was applied. Gameplay state (position, lives, energy, timers, music) SHALL be unaffected by opening, using and closing the menu.

#### Scenario: Open and close without changes
- **GIVEN** a paused stage
- **WHEN** the player opens the menu, browses the modal and resumes without applying
- **THEN** VRAM, CGRAM and OAM SHALL be byte-identical to the moment of the pause
- **AND** the next gameplay frames SHALL match a run that paused and resumed without the menu.

#### Scenario: Every pausable stage
- **WHEN** the regression opens and closes the menu in every stage state where the game can pause
- **THEN** no stage SHALL show corrupted graphics, wrong colours on other objects, or a hang.
