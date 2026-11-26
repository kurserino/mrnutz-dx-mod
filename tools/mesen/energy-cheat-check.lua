-- Energy cheat check (regression tool). A Pro Action Replay code (PAR, decimal; e.g. 7E01F4B3 = full energy) is added
-- to Mesen's cheat engine (answers CPU reads like ares). MODE 0: from a stage state, random play without other cheats;
-- logs damage ($8D = 120), deaths ($81:D14A) with position, and full/empty hearts in the HUD. MODE 1: from power-on
-- (no state), Start at frame 200 and 1000 (title), then walk right; logs when gameplay starts and the hearts.
-- Defines: PAR (PAR2, PAR3: more codes), MODE, END (default 4000), SEED, SAVEFUR/SAVEOUTFIT (MODE 1), UNPAUSE=1 (Start at frame 40, e.g. a paused ares state via --prelude), RESETAT (soft reset at that frame,
-- then a new game from the title; WRAM is kept like on the console).
local END_ = END or 4000
math.randomseed(SEED or 1)
local function addPar()
  for _, p in ipairs({ PAR, PAR2, PAR3, PAR4, PAR5, PAR6, PAR7, PAR8, PAR9, PAR10, PAR11, PAR12, PAR13, PAR14, PAR15, PAR16 }) do
    if p then print("ADDCHEAT " .. string.format("%08X ", p) .. tostring(pcall(emu.addCheat, emu.cheatType.snesProActionReplay, string.format("%08X", p)))) end
  end
end
if MODE == 1 then
  local added = false
  emu.addMemoryCallback(function()
    if added then return end
    added = true
    addPar()
    if SAVEFUR then -- MODE 1: a save record like the user's (fur SAVEFUR, outfit SAVEOUTFIT) before the hook's init reads it
      local fur, outfit = SAVEFUR, SAVEOUTFIT or 0
      local w0, w2, w4 = 0x5A4E, 0x01 | (fur << 8), outfit
      local ck = 0xFFFF ~ ((w0 + w2 + w4) & 0xFFFF)
      local rec = { 0x4E, 0x5A, 0x01, fur, outfit, 0x00, ck & 0xFF, ck >> 8 }
      for i = 1, 8 do emu.write(0x100 + i - 1, rec[i], emu.memType.snesSaveRam) end
    end
  end, emu.callbackType.exec, 0x0080B5, 0x0080B5, emu.cpuType.snes, emu.memType.snesMemory)
else
  loadStateOnBoot(addPar)
end
local dir, left = true, 0
emu.addEventCallback(function()
  if RESETAT and FRAME >= RESETAT then
    -- After the soft reset: Start 200 frames later (logos) and 1000 frames later (title), then play.
    local t = FRAME - RESETAT
    if t < 1100 then
      if (t >= 200 and t < 204) or (t >= 1000 and t < 1004) then emu.setInput({ start = true }, 0) end
      return
    end
  end
  if UNPAUSE == 1 and FRAME >= 40 and FRAME < 44 then emu.setInput({ start = true }, 0); return end
  if UNPAUSE == 1 and FRAME < 60 then return end
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
  if FRAME % (SHOTEVERY or 500) == 0 then
    local f, e = hearts()
    print(string.format("F%d gameplay=%s energy(read)=%d heartPx full=%d empty=%d hits=%d", FRAME, tostring(inGameplay()), bus8(0x7E01F4) ~ 0xB7, f, e, hits))
    shot(string.format("f%04d", FRAME))
  end
  if FRAME >= END_ then
    print(string.format("RESULT hits=%d deaths=%d firstGameplay=%d", hits, deaths, firstGameplay))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
-- Screen watch: last INIDISP write and a lit/black summary every 100 frames (black screen hunt).
local inidispW = -1
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v) inidispW = v end, emu.callbackType.write, b * 0x10000 + 0x2100, b * 0x10000 + 0x2100, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if FRAME % 100 == 0 then
    local s = emu.getState()
    print(string.format("F%d SCREEN inidisp=%02X nmi=%04X pc=%02X:%04X gameplay=%s stage=%02X", FRAME, inidispW & 0xFF, w16(0x01DC), s["cpu.k"], s["cpu.pc"], tostring(inGameplay()), w8(0x054C)))
  end
end, emu.eventType.endFrame)
emu.addEventCallback(function()
  if RESETAT and FRAME == RESETAT then print(string.format("F%d SOFT RESET", FRAME)); emu.reset() end
end, emu.eventType.endFrame)
