-- Black-screen check for entering the house in stage-07 ("FIND THE GOLDEN KEY TO ENTER THE HOUSE").
-- MODE=0 (default): door entry. At frame DOORAT (gameplay) the script does what the door trigger action $81:D4AA-$81:D4CB
--   does when Mr. Nutz stands in the door zone: $58=0, $183F=1, $A6=1, $8C=0, $0572=$CEB3 (iris-wipe start). The wipe
--   ($82:92B4) then jumps through $13B6 to $80:82A1 (enter area $0550) or $80:82D4 (next stage, $0550=$FFFF).
--   It skips JSR $81:E14D (object loop) of the real door action.
-- MODE=2: end-of-stage exit (trigger type 2, the house door): fade-out routine $81:D17F, then next stage.
-- MODE=4: golden-key pickup + house entry sequence ($9D:EF1C-$9D:EF35 RAM effects), the real house path.
-- INVULN=1 (MODE 4): invulnerability ($8D=$2D) during the automatic walk, so enemies cannot interrupt it.
-- PX/PY: teleport Mr. Nutz there 120 frames before DOORAT (needs DOORAT >= 130).
-- MODE=3: second area exit, main-loop request $80:82B6 (area $0552), without the fade.
-- MODE=1: debug stage skip (R with $1EC9 bit 0, emulator RAM only) at frame DOORAT.
-- HOPS (default 1): repeat the door entry HOPS times, HOPGAP (default 300) frames apart, to walk the stage's areas.
-- Logs every LOGEVERY frames: gameplay flag, INIDISP ($2100) last write, $13B6 targets, scene pointer; screenshots.
-- RESULT: back = first gameplay frame after the transition, litBack = first lit frame after it (INIDISP brightness > 0
-- and no forced blank). Defines: END (default 1500), DOORAT (default 60), LOGEVERY (default 60), MODE.
local END_, AT, EVERY = END or 1500, DOORAT or 60, LOGEVERY or 60
loadStateOnBoot(function() if MODE == 1 then ww(0x1EC9, w8(0x1EC9) | 0x01) end end)
if MODE == 1 then playInputs({ { AT, AT + 4, { r = true } } }) end
-- Stage-07 opens with a message box; a few B taps dismiss it.
emu.addEventCallback(function()
  if MODE ~= 1 and FRAME < AT - 10 and FRAME % 8 < 4 then emu.setInput({ b = true }, 0) end
end, emu.eventType.inputPolled)
local inidisp, fired, hops, nextAt = -1, false, 0, AT
emu.addMemoryCallback(function(_, v) inidisp = v end, emu.callbackType.write, 0x002100, 0x002100, emu.cpuType.snes, emu.memType.snesMemory)
for _, b in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(a, v)
    if (a & 1) == 1 then print(string.format("F%d target13B6=%02X%02X", FRAME, v, w8(0x13B6))) end
  end, emu.callbackType.write, b * 0x10000 + 0x13B7, b * 0x10000 + 0x13B7, emu.cpuType.snes, emu.memType.snesMemory)
end
local left, back, litBack, lastScene = false, -1, -1, -1
-- LAND=1 (MODE 4): the player physics rewrites $6D every frame, so the landing is forced right before $9D:EFB8 reads it.
emu.addMemoryCallback(function()
  if MODE == 4 and fired and LAND == 1 and w16(0x39) >= 1640 then ww(0x6D, 0); ww(0x6E, 0) end
end, emu.callbackType.exec, 0x9DEFB8, 0x9DEFB8, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  local g = inGameplay()
  if PX and FRAME == (AT - 120) then
    -- Optional start position (PX, PY): teleport Mr. Nutz (X fixed point $5A/$5C, Y $39) before the sequence.
    ww(0x5C, 0); ww(0x5D, 0); local lo = (PX << 4) & 0xFFFF; ww(0x5A, lo & 0xFF); ww(0x5B, lo >> 8)
    ww(0x39, PY & 0xFF); ww(0x3A, PY >> 8); ww(0x60, 0); ww(0x61, 0)
  end
  if MODE ~= 1 and FRAME >= nextAt and g and hops < (HOPS or 1) then
    hops = hops + 1; nextAt = FRAME + (HOPGAP or 300); fired = true
    if MODE == 4 then
      -- Golden-key pickup sequence: what $81:B9E8 -> $9D:EF10/$9D:EF1C-$9D:EF35 writes (without the sound effect $11
      -- and the jingle JSL $8A8194 X=1): $8C=0, $183F=1, $A6=1, $199F=0, $19A1=0, $58=0, $0584=$86DC. The game then
      -- runs the house check $9D:EF3E, the entry animation and $9D:EFA5 (iris wipe -> area $0550).
      ww(0x8C, 0); ww(0x183F, 1); ww(0xA6, 1); ww(0x199F, 0); ww(0x19A0, 0); ww(0x19A1, 0); ww(0x19A2, 0)
      ww(0x58, 0); ww(0x59, 0); ww(0x0584, 0xDC); ww(0x0585, 0x86)
    elseif MODE == 3 then
      -- Second area exit: main-loop request $13B6 = $80:82B6 ($0555 = 1, $0554 = 2 -> area $0552).
      ww(0x13B6, 0xB6); ww(0x13B7, 0x82)
    elseif MODE == 2 then
      -- Exit trigger type 2 ($81:D417-$81:D436, condition $18B2 == 0): fade out through $057E = $81:D17F, then
      -- $13B6 = $80:82D4 (next stage).
      ww(0x056E, 0x00); ww(0x056F, 0x0F); ww(0x057E, 0x7F); ww(0x057F, 0xD1); ww(0x18F7, 0); ww(0x18F8, 0)
      ww(0x18B0, 0x00); ww(0x18B1, 0x02); ww(0x18B2, 0x00); ww(0x18B3, 0x02)
    else
      ww(0x58, 0); ww(0x59, 0); ww(0x183F, 1); ww(0xA6, 1); ww(0x8C, 0)
      ww(0x0572, 0xB3); ww(0x0573, 0xCE)
    end
    print(string.format("F%d DOOR%d px=%d py=%d dest0550=%04X dest0552=%04X", FRAME, hops, w16(0x37), w16(0x39), w16(0x0550), w16(0x0552)))
    shot("door" .. hops)
  end
  if MODE == 4 and fired and INVULN == 1 then ww(0x008D, 0x2D) end
  -- LAND=1: once the iris has started ($19A1 = $CEB3) the game puts Mr. Nutz at Y = $069C; at the real house he stands
  -- there, here there is no floor, so hold him (Y, vertical speed $60) and lower the stage bottom $9F (fall death at
  -- $82:AB6A: Y > $9F - 4 + $40) until the area changes.
  if MODE == 4 and fired and LAND == 1 and w16(0x19A1) == 0xCEB3 and w16(0x0584) == 0x86E1 then ww(0x39, 0x9C); ww(0x3A, 0x06); ww(0x60, 0); ww(0x61, 0); ww(0x9F, 0xD0); ww(0xA0, 0x07) end
  -- LAND=1 (MODE 4): after the entry jump Mr. Nutz falls through the floor; $9D:EFA5 starts the iris only once he is
  -- on the ground (16-bit $6D = 0). Away from the real house there is no floor below, so force the landing at Y >= 1640.
  if FRAME > AT + 4 and not g then left = true end
  if left and g and back < 0 then back = FRAME end
  local lit = inidisp >= 0 and (inidisp & 0x80) == 0 and (inidisp & 0x0F) > 0
  if back >= 0 and lit and litBack < 0 then litBack = FRAME end
  local scene = w8(0x560) * 0x10000 + w16(0x55E)
  if scene ~= lastScene then print(string.format("F%d scene=%06X", FRAME, scene)); lastScene = scene end
  if FRAME % EVERY == 0 then
    print(string.format("F%d gameplay=%s inidisp=%02X vec=%04X", FRAME, tostring(g), inidisp & 0xFF, w16(0x01DC)))
    if FRAME % (EVERY * 2) == 0 then shot(string.format("f%04d", FRAME)) end
  end
  if FRAME == END_ then
    print(string.format("RESULT left=%s back=%d litBack=%d inidisp=%02X", tostring(left), back, litBack, inidisp & 0xFF))
    shot("end")
  end
  if FRAME >= END_ + 6 then emu.stop(0) end
end, emu.eventType.endFrame)
