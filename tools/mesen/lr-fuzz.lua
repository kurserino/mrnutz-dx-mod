-- L/R fuzz around a stage start (research tool): optional ares prelude + soft reset like energy-cheat-check.lua, then
-- a new game from the title; from frame FUZZFROM to FUZZTO the pad holds a random mix of L, R, Select+L, Select+R
-- (SEED) in bursts. Cheats: PAR, PAR2, PAR3 (Mesen cheat engine). Logs brightness, effect pointer $0572, DMA queue
-- bytes $13DE-$13EF and gameplay every 50 frames; RESULT with the longest run of forced-blank frames after FUZZFROM.
math.randomseed(SEED or 1)
local added = false
local function addPar()
  if added then return end
  added = true
  for _, p in ipairs({ PAR, PAR2, PAR3, PAR4, PAR5, PAR6, PAR7, PAR8, PAR9, PAR10, PAR11 }) do if p then emu.addCheat(emu.cheatType.snesProActionReplay, string.format("%08X", p)) end end
end
if STATE_HEX then loadStateOnBoot(addPar) else
  emu.addMemoryCallback(addPar, emu.callbackType.exec, 0x0080B5, 0x0080B5, emu.cpuType.snes, emu.memType.snesMemory)
end
local R0 = RESETAT or 0
local burst, left = {}, 0
emu.addEventCallback(function()
  if RESETAT and FRAME == RESETAT then emu.reset() end
  local t = FRAME - R0
  if t < 0 then return end
  if (t >= 200 and t < 204) or (t >= 1000 and t < 1004) then emu.setInput({ start = true }, 0); return end
  if FRAME >= (FUZZFROM or 1100) and FRAME < (FUZZTO or 2200) then
    if left <= 0 then
      local r = math.random(6)
      burst = ({ { l = true }, { r = true }, { select = true, l = true }, { select = true, r = true }, {}, {} })[r]
      left = 5 + math.random(0, 40)
    end
    left = left - 1
    emu.setInput(burst, 0)
  end
end, emu.eventType.inputPolled)
local inid, blankRun, maxBlank = 0, 0, 0
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v) inid = v end, emu.callbackType.write, b * 0x10000 + 0x2100, b * 0x10000 + 0x2100, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if FRAME >= (FUZZFROM or 1100) then
    if (inid & 0x80) ~= 0 or (inid & 0x0F) == 0 then blankRun = blankRun + 1; if blankRun > maxBlank then maxBlank = blankRun end else blankRun = 0 end
  end
  if FRAME % 50 == 0 then
    local q = {}
    for a = 0x13DE, 0x13EE, 2 do q[#q + 1] = string.format("%04X", w16(a)) end
    print(string.format("F%d inidisp=%02X 0572=%04X stage=%02X gameplay=%s q=%s 01F4=%02X", FRAME, inid, w16(0x0572), w8(0x054C), tostring(inGameplay()), table.concat(q, " "), w8(0x01F4)))
  end
  if FRAME >= (END or 3000) then print(string.format("RESULT maxBlankFrames=%d stage=%02X", maxBlank, w8(0x054C))); emu.stop(0) end
end, emu.eventType.endFrame)
