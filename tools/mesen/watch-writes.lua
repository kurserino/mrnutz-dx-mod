-- Logs who writes a WRAM byte (PC, value, frame), walking right from a stage state until deaths happen.
-- Defines: ADDR=<WRAM offset, decimal>, FRAMES=N. Watches both $00:xxxx (low mirror) and $7E:xxxx.
local FRAMES_ = FRAMES or 6000
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
emu.addEventCallback(function()
  local k = FRAME % 300
  if k < 4 then emu.setInput({ start = true }, 0)
  elseif k >= 150 and k < 154 then emu.setInput({ a = true }, 0)
  else emu.setInput({ right = true }, 0) end
end, emu.eventType.inputPolled)
local seen = {}
local function onWrite(address, value)
  local s = emu.getState()
  local pc = ((s["cpu.k"] or 0) << 16) | s["cpu.pc"]
  local key = pc .. ":" .. value
  if seen[key] then return end
  seen[key] = true
  print(string.format("WRITE frame=%d addr=$%06X value=%d pc=$%06X A=$%04X X=$%04X Y=$%04X", FRAME, address, value, pc, s["cpu.a"], s["cpu.x"], s["cpu.y"]))
end
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x7E0000 + ADDR, 0x7E0000 + ADDR, emu.cpuType.snes, emu.memType.snesMemory)
if ADDR < 0x2000 then
  emu.addMemoryCallback(onWrite, emu.callbackType.write, ADDR, ADDR, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function() if FRAME >= FRAMES_ then emu.stop(0) end end, emu.eventType.endFrame)
