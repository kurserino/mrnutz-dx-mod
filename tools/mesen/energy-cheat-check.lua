-- Energy cheat check (regression tool). A Pro Action Replay code (PAR, decimal; e.g. 7E01F4B3 = full energy) is added
-- to Mesen's cheat engine (answers CPU reads like ares). MODE 0: from a stage state, random play without other cheats;
-- logs damage ($8D = 120), deaths ($81:D14A) with position, and full/empty hearts in the HUD. MODE 1: from power-on
-- (no state), Start at frame 200 and 1000 (title), then walk right; logs when gameplay starts and the hearts.
-- Defines: PAR, MODE, END (default 4000), SEED.
local END_ = END or 4000
math.randomseed(SEED or 1)
local function addPar() if PAR then print("ADDCHEAT " .. tostring(pcall(emu.addCheat, emu.cheatType.snesProActionReplay, string.format("%08X", PAR)))) end end
if MODE == 1 then
  local added = false
  emu.addMemoryCallback(function() if not added then added = true; addPar() end end, emu.callbackType.exec, 0x0080B5, 0x0080B5, emu.cpuType.snes, emu.memType.snesMemory)
else
  loadStateOnBoot(addPar)
end
local dir, left = true, 0
emu.addEventCallback(function()
  if MODE == 1 and FRAME < 1100 then
    if (FRAME >= 200 and FRAME < 204) or (FRAME >= 1000 and FRAME < 1004) then emu.setInput({ start = true }, 0) end
    return
  end
  if left <= 0 then dir = math.random() < 0.75; left = 20 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ right = dir, left = not dir, b = FRAME % 30 < 10 }, 0)
end, emu.eventType.inputPolled)
local hits, deaths, firstGameplay = 0, 0, -1
for _, b in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(_, v) if v == 120 then hits = hits + 1 end end,
    emu.callbackType.write, b * 0x10000 + 0x8D, b * 0x10000 + 0x8D, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addMemoryCallback(function()
  deaths = deaths + 1
  print(string.format("F%d DEATH x=%d y=%d energy=%d", FRAME, w16(0x37), w16(0x39), bus8(0x7E01F4) ~ 0xB7))
end, emu.callbackType.exec, 0x81D14A, 0x81D14A, emu.cpuType.snes, emu.memType.snesMemory)
local function hearts()
  local full, empty = 0, 0
  for y = 26, 27 do for x = 0, 79 do
    local c = emu.getPixel(x, y) & 0xFFFFFF
    if c == 0xFF0000 then full = full + 1 elseif c == 0x6B0000 then empty = empty + 1 end
  end end
  return full, empty
end
emu.addEventCallback(function()
  if inGameplay() and firstGameplay < 0 then firstGameplay = FRAME; print(string.format("F%d GAMEPLAY", FRAME)) end
  if FRAME % 500 == 0 then
    local f, e = hearts()
    print(string.format("F%d gameplay=%s energy(read)=%d heartPx full=%d empty=%d hits=%d", FRAME, tostring(inGameplay()), bus8(0x7E01F4) ~ 0xB7, f, e, hits))
    shot(string.format("f%04d", FRAME))
  end
  if FRAME >= END_ then
    print(string.format("RESULT hits=%d deaths=%d firstGameplay=%d", hits, deaths, firstGameplay))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
