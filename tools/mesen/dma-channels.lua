-- DMA channel usage (research tool): OR of every value written to $420B (DMA enable) and $420C (HDMA enable), and the
-- channels whose registers $43x0-$43xA are written at all, over END frames of a stage state with random play (or of
-- the boot sequence without a state: Start at 200 and 1000). Prints RESULT dma=<mask> hdma=<mask> regs=<mask>.
math.randomseed(SEED or 1)
if STATE_HEX then loadStateOnBoot() end
local dir, left = true, 0
emu.addEventCallback(function()
  if not STATE_HEX then
    if (FRAME >= 200 and FRAME < 204) or (FRAME >= 1000 and FRAME < 1004) then emu.setInput({ start = true }, 0) end
    if FRAME < 1100 then return end
  end
  if left <= 0 then dir = math.random() < 0.7; left = 20 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ right = dir, left = not dir, b = FRAME % 30 < 10, y = FRAME % 20 < 3 }, 0)
end, emu.eventType.inputPolled)
local dma, hdma, regs = 0, 0, 0
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v) dma = dma | v end, emu.callbackType.write, b * 0x10000 + 0x420B, b * 0x10000 + 0x420B, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(_, v) hdma = hdma | v end, emu.callbackType.write, b * 0x10000 + 0x420C, b * 0x10000 + 0x420C, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a) regs = regs | (1 << ((a >> 4) & 7)) end, emu.callbackType.write, b * 0x10000 + 0x4300, b * 0x10000 + 0x437F, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if FRAME >= (END or 1500) then print(string.format("RESULT dma=%02X hdma=%02X regs=%02X", dma, hdma, regs)); emu.stop(0) end
end, emu.eventType.endFrame)
