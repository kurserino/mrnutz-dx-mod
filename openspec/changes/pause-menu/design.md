# Design

## Context

See `proposal.md` (Why) and the delta specs. Facts used here are in `docs/knowledge/` (`frame-cycle.md`, `memory-map.md`, `palettes.md`, `mod-implementation.md`):

- **Paused NMI** `$80:835B` → `$80:83B8` when `$13B4 ≠ 0`. At `$80:83B8`: P=`$B4` (M8 X8), D=`$0000`, DBR=`$00`, scanline 225. It re-enables HDMA (`$183D` → `$420C`), waits for auto-joypad, copies `$4218`/`$421A` to `$1A6F`/`$1A71`, handles Start (`$80:83D7`), then spins at `$80:83A0` until VBlank ends (scanline 0) and returns. The OAM upload and the gameplay mirror do not run while paused, so the OAM and the screen stay frozen.
- **Start/unpause** at `$80:83D7` [static]:
  - Start pressed and `$13B5 == 0` → `$13B4 = 0`, `$13B5 = $FF`;
  - Start not pressed → `$13B5 = 0`.
  - In gameplay, `$81:839B` sets `$13B4 = $13B5 = $FF` on a new Start press.
- **VRAM layout** (bytes):
  - BG1 map `$0000`, BG2 map `$0800`, BG3 map `$1000-$17FF`;
  - BG3 2bpp tiles from `$0000` (HUD tiles `$3800-$3CFF`); BG1/2 tiles `$4000-$BFFF`; OBJ `$C000-$FFFF`.
  - Mode 1, BG3 priority bit set.
  - Nothing is free; BG3 also draws scenery in many stages.
- **WRAM:** persistent state `$7F:B680-$7F:BFFF` (ours: `$7F:BE00-$7F:BE20`); temporary buffer `$7F:D040-$7F:FFFF` (12 KB), untouched during gameplay.
- **Colour model today** (`src/runtime.ts`): fur/outfit index → `FUR_TABLE` (+ per-index offset table) and `OUTFIT_TABLE`. The manager prepares colours, `oam_hook` uploads them to the private slot X and remaps only Mr. Nutz's OAM entries. Save record v1 at `$70:0100`.

## Goals / Non-Goals

**Goals:**
- A menu framework (screen backup/restore, input, list, modal) that Options and Cheats can reuse.
- Zero lasting side effects: after closing, VRAM/CGRAM/OAM equal their state at pause time, apart from Mr. Nutz's palette when a colour was applied.
- No new work on the gameplay critical path. Menu code runs only in the paused NMI.

**Non-Goals:**
- Options and Cheats items (later changes).
- Following the game's LANGUAGE option (English text only).
- A menu outside gameplay pauses (title, map, dialogs).
- Animating Mr. Nutz in the preview: it shows his frozen frame.

## Decisions

### D1. Hook at the paused-NMI branch `$80:83B8`
- **Patch:** replace `E2 30 AD 3D 18 8D 0C 42` (`SEP #$30 / LDA $183D / STA $420C`, 8 bytes) with `JSL pause_hook` plus 4 × `NOP`.
- **Hook body:** `pause_hook` runs the relocated instructions itself, which lets it hold HDMA off while the menu is open, then returns to `$80:83C0`.
- **Budget:** it runs at scanline 225 with the whole VBlank ahead. The original path only needs the joypad read and the Start check after it (a few lines), so the hook budget is about 30 scanlines. Each step's DMA is sized to stay under about 4 KB per frame (D3).
- *Alternative:* hook the gameplay path before the pause starts. Rejected: the pause state machine of the game would still run, and every gameplay frame would pay for it.

### D2. Owning the Start key: the `$13B5` latch
- While the menu is open, `pause_hook` sets `$13B5 = $FF` every frame before `$80:83D7` runs. The game then never unpauses by itself.
- To resume, the hook clears `$13B4` and leaves `$13B5 = $FF`. The gameplay path does not re-pause while Start is still held: it clears the latch only on release (`$81:83B5`).
- Input comes from `$1A6F` as written by the previous paused NMI (1 frame of latency), with our own edge detection (`prevPad` copy for the menu).
- *Alternative:* patch the Start check at `$80:83D7`. Rejected: a second patch site with the same effect.

### D3. Open/close as a multi-frame state machine
WRAM state at `$7F:BE40+` (persistent region): `menuState`, `step`, `cursor`, `tab`, `gridCursor`, `prevPad`, preview values. Each step runs in one paused VBlank, with the screen still showing the frozen frame:

| Step | Open | Close |
| --- | --- | --- |
| 1 | DMA VRAM→WRAM: BG3 map `$1000-$17FF` (2 KB) and BG3 tiles `$3000-$37FF` (2 KB) into the buffer | DMA WRAM→VRAM: BG3 map and tiles back |
| 2 | VRAM→WRAM: the OBJ tile area chosen in D5 (≤ 2 KB); read OAM (544 bytes) and CGRAM (512 bytes) into the buffer | OBJ tile area back, OAM back, CGRAM back (except Mr. Nutz's palette when a colour was applied) |
| 3 | upload font/frame tiles, menu tilemap, menu palettes, swatch and preview OAM | re-enable HDMA, clear `$13B4` (resume) |

- **Buffer use:** about 7.2 KB of the 12 KB buffer.
- **Rollback per step:** a state number in WRAM lets the close path undo exactly the steps that ran. If the game unpauses in an unexpected way, the hook detects `$13B4 == 0` with `menuState ≠ closed` and restores immediately in the next paused NMI it gets; otherwise `oam_hook` can do it on the first gameplay frame.
- *Alternative:* one-frame open. Rejected: about 7 KB is more than one VBlank's DMA (around 5-6 KB).

### D4. Text and frame on BG3, full replacement while open
- The menu tilemap replaces the whole BG3 map while open, so HUD and BG3 scenery disappear during the pause.
- Font and frame tiles (our own 8×8 2bpp art: A-Z, 0-9, a few symbols, 9 frame pieces; about 50 tiles, 800 bytes) go into BG3 tiles `$300-$37F` (bytes `$3000-$37FF`). That range is outside every tilemap and below the HUD tiles; scenery uses it in a few stages, which is why it is backed up.
- **Palettes:** BG3 palettes 1-2 for text and highlight (CGRAM `$04-$0B`); palette 0 colour 0 (the backdrop) is never touched.
- **Priority:**
  - the frame tiles use priority 1, so they cover BG1/BG2;
  - the grid area and the preview area are transparent BG3 cells, so the sprites under them show (in mode 1 with the BG3 priority bit, high-priority BG3 sits above sprites);
  - the scene behind the transparent cells is covered by the opaque swatches and by a dark backing sprite under the preview.
- **HDMA off while open:** `$420C = 0`, so no gradient or scroll HDMA disturbs the menu. The frozen scene loses its HDMA effects only while the menu shows.
- *Alternative:* turn BG1/BG2 off on the main screen (`$212C`) while open. That is the fallback if transparent cells look wrong: the menu would sit on the backdrop colour.

### D5. Colour swatches and preview as sprites
- **OAM:** 32 swatches + 1 grid cursor + 1 tab marker + Mr. Nutz preview (his 6 frozen OAM entries copied with an offset, `tile < $50`, name table 0) fit in 128 entries. All other entries are hidden (y=`$E0`) while open; the full OAM is restored on close.
- **Tiles:**
  - swatch tiles: one solid tile per colour index 1-15, at the game's small sprite size (16×16 in OBJ mode 3, `oamMode=3`);
  - cursor tiles: 2.
  - They go into **OBJ tiles `$100-$13F` (name table 1, VRAM `$E000-$E7FF`, 2 KB)**, backed up in D3 step 2.
  - Measured (`pause-measure.log`, task 1.2): no 16-tile row is free in every paused stage, but all other OAM entries are hidden while the menu is open, so only the tiles of the sprites we show must stay intact. Mr. Nutz always uses name table 0, tiles `$000-$055`, in every paused stage, so name table 1 rows 0-3 are safe everywhere. The scene's own sprites that use them are hidden until the close step restores both the tiles and the OAM.
- **Palettes:** borrow sprite palettes 0-3 (no colour math; CGRAM `$80-$BF`, backed up):
  - palettes 0-1 = swatch colours 1-30;
  - palette 2 = swatches 31-32, cursor and frame colours;
  - palette 3 = preview (Mr. Nutz's palette with the browsed fur/outfit shades).
- *Alternative:* swatches on BG3. Rejected: BG3 has 8 palettes × 3 colours = 24 colours, not 32 plus text colours.

### D6. Selection value encoding (fur and outfit, one byte each)
- `0` = original, `1 … N` = presets (N ≤ 11, as today), `$20 … $3F` = grid colours 0-31. Any other value = invalid → 0.
- Shortcuts (`Select+L/R`): from a grid colour go to `0`, then cycle presets as before.
- **Tables** in the expansion: `GRID_FUR` (32 × 10 bytes) and `GRID_OUTFIT` (32 × 8 bytes), next to `FUR_TABLE`/`OUTFIT_TABLE`. `prepare_colors` picks the table by the value's range. `oam_hook` and the private-slot logic are unchanged.

### D7. Save record v2
- Same 8-byte layout at `$70:0100`; version byte `$02`. Fur/outfit hold the D6 values.
- `load_save` accepts version 1 or 2 and validates values by range (presets or grid).
- `write_save` always writes version 2.
- No new SRAM address, so the anti-copier audit is unchanged.

### D8. Grid colours and shade generation (build time)
- `presets/grid.json` lists 32 base colours: 8 hues × 3 rows (vivid, light, dark) plus 8 neutrals/browns, chosen for readable fur/clothes.
- **Generator** (`src/shades.ts`): fur = 5 shades and outfit = 4 shades derived from the base colour.
  - Scale RGB by fixed factors, ordered dark → light. The light end is the base itself; the darker shades are multiplied towards black.
  - Clamp to BGR555. Pure integer maths, so the output is deterministic.
  - Unit tests check monotonic luminance and byte-identical output.
- *Alternative:* compute shades on the console. Rejected: no benefit, more code and VBlank time.

### D9. Menu text and layout
- Uppercase English. List: `PAUSE` / `CHANGE OUTFIT` / `RESUME`.
- Modal title bar: `FUR` `CLOTHES`, with the active tab highlighted. Below it the 8×4 grid on the left and the preview on the right. Bottom line: `A APPLY  B BACK  L/R TAB`.
- The layout is data: item list and strings in a table, so Options and Cheats can append items.

### D10. Verification
**`tools/mesen/pause-menu-check.lua`**, run from every pausable stage state:
- **open → close:** take a snapshot of VRAM/CGRAM/OAM at the pause, open the menu, browse, cancel, close, and compare byte for byte;
- **apply:** pick a fur and a clothes colour, check the save record and Mr. Nutz's colours after resuming (`nutzOracle`);
- **input:** held buttons, wrap-around, Start on the list;
- screenshots of the list and of the modal.

Added to `sweep:all`. The stage states that cannot pause are excluded.

## Risks / Trade-offs

- **[Colour math or windows set by the scene tint the menu]** (some stages use colour math, `pause-measure.log`) → The prototype checks screenshots in those stages. If needed, the hook writes neutral `$2130-$2132` while open. Those registers are write-only, so restoring them needs the scene's value: find the game's shadow or per-scene constant first (`$85:939C` writes constants). Until then, the fallback is to leave them untouched and accept the tint.
- **[BG3 scroll]** The BG3 scroll registers are write-only. The menu tilemap must be readable at the scene's current scroll; the hook writes BG3 scroll 0 while open, which needs the original value to restore. → Find the BG3 scroll shadow in WRAM in the prototype. If there is none, draw the menu relative to the current scroll, which is static during pause, read from the shadow the game writes from.
- **[OBJ tiles borrowed from the scene]** → resolved by hiding every other OAM entry while open (D5). Only Mr. Nutz's tiles (name table 0, `$000-$055`) must stay intact, and the borrowed area is in name table 1.
- **[OAM read-back]** OAM is read through `$2138` with the address from `$0026` (the hook already does this in v3). Restore by DMA to `$2104`.
- **[VBlank overrun]** Each step stays under about 4 KB of DMA plus a few hundred cycles of code. The prototype measures the end scanline. If it exceeds 250, split further.
- **[Game unpauses while a step is half done]** (for example a timer or a soft reset) → D3 rollback state. On a soft reset WRAM keeps our state, but VRAM is reinitialised by the game anyway: the hook clears the menu state on the init path.

## Migration Plan

1. Prototype (tasks group 1) on a branch build: hook + open/close with a placeholder screen, measured in Mesen. Update this design with the results before the full build.
2. Then implement the full menu, save v2 and tests.
3. **Rollback:** the v0.2.0 IPS. Its save v1 records stay readable by both versions; a v2 record is rejected by v0.2.0 (version check) and falls back to the original colours, with no crash.

## Open Questions

- Exact 32 grid colours: a first proposal in `presets/grid.json` is reviewed by the user on screenshots before release. This does not change code or specs.
