-- Caller of the Stage Clear routine: stack and stage index at the first instruction executed in $9D:E300-$9D:E452,
-- with a boss health PAR code and jumping invulnerable Mr. Nutz. Defines: PAR.
loadStateOnBoot(function() emu.addCheat(emu.cheatType.snesProActionReplay, string.format("%08X", PAR)) end)
math.randomseed(1)
local dir, left = true, 0
emu.addEventCallback(function()
  if left <= 0 then dir = math.random() < 0.5; left = 30 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ left = dir, right = not dir, b = FRAME % 40 < 20 }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function() ww(0x008D, 0x2D) end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
local first = true
emu.addMemoryCallback(function()
  if not first then return end
  local s = emu.getState()
  local pc = s["cpu.pc"]
  if pc < 0xE300 or pc > 0xE452 then return end
  first = false
  local sp = s["cpu.sp"]
  local t = {}
  for a = sp + 1, 0x1FFF do t[#t + 1] = string.format("%02X", w8(a)) end
  print(string.format("F%d first pc=9D:%04X sp=%04X stack=%s 054C=%02X 1EF4=%04X 7FB3F0=%04X", FRAME, pc, sp, table.concat(t, " "), w8(0x054C), w16(0x1EF4), w16(0x1B3F0)))
end, emu.callbackType.exec, 0x9DE300, 0x9DE452, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function() if FRAME >= 600 then emu.stop(0) end end, emu.eventType.endFrame)
