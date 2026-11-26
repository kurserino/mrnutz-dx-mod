-- First frames check (regression tool): every frame, gameplay or not, finds the visible Mr. Nutz sprites (tile < $50,
-- name table 0, palette = the slot of $85:9CC0 in the scene table or the private slot X) and checks the colours of the
-- palette they use (entries 6 and 15 = the selection). A frame counts as BAD when the screen is lit (last INIDISP
-- write: no forced blank, brightness > 0) and Mr. Nutz is drawn with other colours; screenshots of the first BAD frames
-- and of every frame of the first SHOTS frames after each lit start. Scenarios (SCENARIO):
--   1 debug stage skip at frame 60 from a stage state;  2 new game from power-on (Start at 200 and 1000);
--   3 death: lives held, Mr. Nutz falls (Y forced below the stage) at frame 60 to see the respawn.
-- Save record: SAVEFUR (default 1), outfit 0. Defines: END (default 900), SHOTS (default 0).
local END_ = END or 900
local function writeSave()
  local fur, outfit = SAVEFUR or 1, 0
  local w0, w2, w4 = 0x5A4E, 0x01 | (fur << 8), outfit
  local ck = 0xFFFF ~ ((w0 + w2 + w4) & 0xFFFF)
  local rec = { 0x4E, 0x5A, 0x01, fur, outfit, 0x00, ck & 0xFF, ck >> 8 }
  for i = 1, 8 do emu.write(0x100 + i - 1, rec[i], emu.memType.snesSaveRam) end
end
if SCENARIO == 2 then
  local done = false
  emu.addMemoryCallback(function() if not done then done = true; writeSave() end end, emu.callbackType.exec, 0x0080B5, 0x0080B5, emu.cpuType.snes, emu.memType.snesMemory)
else
  loadStateOnBoot(writeSave)
end
emu.addEventCallback(function()
  if SCENARIO == 1 then
    if FRAME == 55 then ww(0x1EC9, w8(0x1EC9) | 1) end
    if FRAME >= 60 and FRAME < 64 then emu.setInput({ r = true }, 0) end
    if FRAME == 70 then ww(0x1EC9, w8(0x1EC9) & 0xFE) end
  elseif SCENARIO == 2 then
    if (FRAME >= 200 and FRAME < 204) or (FRAME >= 1000 and FRAME < 1004) then emu.setInput({ start = true }, 0) end
  end
end, emu.eventType.inputPolled)
if SCENARIO == 3 then
  emu.addMemoryCallback(function()
    ww(0x1889, 0xB5); ww(0x188A, 0xA3)
    if FRAME >= 60 and FRAME < 64 then ww(0x39, 0xFF); ww(0x3A, 0x0F) end
  end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
end
local inid = 0
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v) inid = v end, emu.callbackType.write, b * 0x10000 + 0x2100, b * 0x10000 + 0x2100, emu.cpuType.snes, emu.memType.snesMemory)
end
local bad, litNutz, shots, lastLit, litStart = 0, 0, 0, false, -1
emu.addEventCallback(function()
  local lit = (inid & 0x80) == 0 and (inid & 0x0F) > 0
  if lit and not lastLit then litStart = FRAME; print(string.format("F%d LIT brightness=%d gameplay=%s", FRAME, inid & 0x0F, tostring(inGameplay()))) end
  if not lit and lastLit then print(string.format("F%d DARK", FRAME)) end
  lastLit = lit
  local S = nutzSlot()
  local X = w8(0x1BE06)
  local eOut, eFur = expectedColours()
  local pals = {}
  for i = 0, 127 do
    if oam(i, 1) < 224 then
      local attr = oam(i, 3)
      local tile = oam(i, 2) | ((attr & 1) << 8)
      local p = (attr >> 1) & 7
      if tile < 0x50 and (p == S or p == X) then pals[p] = (pals[p] or 0) + 1 end
    end
  end
  for p, n in pairs(pals) do
    local ok = cg(0x80 + p * 16 + 6) == eOut and cg(0x80 + p * 16 + 15) == eFur
    if lit then
      litNutz = litNutz + 1
      if not ok then
        bad = bad + 1
        print(string.format("F%d BAD nutz=%d on palette %d (S=%s X=%d) gameplay=%s brightness=%d", FRAME, n, p, tostring(S), X, tostring(inGameplay()), inid & 0x0F))
        if bad <= 6 then shot(string.format("bad%04d", FRAME)) end
      end
    end
  end
  if SHOTS and litStart >= 0 and FRAME - litStart < SHOTS then shot(string.format("lit%04d", FRAME)) end
  if FRAME >= END_ then print(string.format("RESULT litNutzFrames=%d bad=%d", litNutz, bad)); emu.stop(0) end
end, emu.eventType.endFrame)
