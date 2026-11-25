-- Colour math writers (research tool): every distinct (PC, register, value, width) writing $2130/$2131 (CGWSEL,
-- CGADSUB), with the frame of the first write, plus $13BC (sprite palette 1 entry 1 animation pointer) changes.
-- Defines: END (default 600).
loadStateOnBoot()
local seen = {}
for _, b in ipairs({ 0x00, 0x80 }) do
  for _, reg in ipairs({ 0x2130, 0x2131 }) do
    emu.addMemoryCallback(function(a, v)
      local s = emu.getState()
      local k = string.format("%04X pc=%02X:%04X v=%02X m=%s", a & 0xFFFF, s["cpu.k"], s["cpu.pc"], v, tostring((s["cpu.ps"] & 0x20) ~= 0))
      if not seen[k] then seen[k] = true; print(string.format("F%d W %s", FRAME, k)) end
    end, emu.callbackType.write, b * 0x10000 + reg, b * 0x10000 + reg, emu.cpuType.snes, emu.memType.snesMemory)
  end
end
local last13BC = -1
emu.addEventCallback(function()
  local v = w16(0x13BC)
  if v ~= last13BC then print(string.format("F%d 13BC=%04X", FRAME, v)); last13BC = v end
  if FRAME >= (END or 600) then emu.stop(0) end
end, emu.eventType.endFrame)
