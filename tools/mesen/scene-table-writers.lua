-- Writers of the scene table pointer $055E and of the main-loop request $13B6 (PC, value), with a PAR code (boss
-- health) and jumping invulnerable Mr. Nutz to reach the Stage Clear screen. Defines: PAR, END.
loadStateOnBoot(function() emu.addCheat(emu.cheatType.snesProActionReplay, string.format("%08X", PAR)) end)
math.randomseed(1)
local dir, left = true, 0
emu.addEventCallback(function()
  if left <= 0 then dir = math.random() < 0.5; left = 30 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ left = dir, right = not dir, b = FRAME % 40 < 20 }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function() ww(0x008D, 0x2D) end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
for _, b in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(a, v)
    local s = emu.getState()
    print(string.format("F%d W %04X=%02X pc=%02X:%04X sp=%04X", FRAME, a & 0xFFFF, v, s["cpu.k"], s["cpu.pc"], s["cpu.sp"]))
  end, emu.callbackType.write, b * 0x10000 + 0x055E, b * 0x10000 + 0x055E, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(a, v)
    local s = emu.getState()
    print(string.format("F%d W13B6 %04X=%02X pc=%02X:%04X", FRAME, a & 0xFFFF, v, s["cpu.k"], s["cpu.pc"]))
  end, emu.callbackType.write, b * 0x10000 + 0x13B6, b * 0x10000 + 0x13B7, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function() if FRAME >= (END or 700) then emu.stop(0) end end, emu.eventType.endFrame)
