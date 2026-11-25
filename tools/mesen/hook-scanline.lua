-- Scanline at the input hook site ($81:828A) per gameplay frame around a debug stage skip, with scanPos/passes/ready.
loadStateOnBoot(function()
  local fur, outfit = 1, 0
  local w0, w2, w4 = 0x5A4E, 0x01 | (fur << 8), outfit
  local ck = 0xFFFF ~ ((w0 + w2 + w4) & 0xFFFF)
  local rec = { 0x4E, 0x5A, 0x01, fur, outfit, 0x00, ck & 0xFF, ck >> 8 }
  for i = 1, 8 do emu.write(0x100 + i - 1, rec[i], emu.memType.snesSaveRam) end
end)
emu.addEventCallback(function()
  if FRAME == 55 then ww(0x1EC9, w8(0x1EC9) | 1) end
  if FRAME >= 60 and FRAME < 64 then emu.setInput({ r = true }, 0) end
  if FRAME == 70 then ww(0x1EC9, w8(0x1EC9) & 0xFE) end
end, emu.eventType.inputPolled)
local lines = {}
emu.addMemoryCallback(function()
  local s = emu.getState()
  lines[#lines + 1] = s["ppu.scanline"]
end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if FRAME >= (FROM or 500) and FRAME <= (TO or 600) then
    print(string.format("F%d hookLines=[%s] scanPos=%d passes=%d ready=%d X=%d 0026=%04X", FRAME, table.concat(lines, ","), w8(0x1BE0F), w8(0x1BE10), w8(0x1BE0D), w8(0x1BE06), w16(0x0026)))
  end
  lines = {}
  if FRAME >= (TO or 600) then emu.stop(0) end
end, emu.eventType.endFrame)
local inidisp = -1
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v) inidisp = v end, emu.callbackType.write, b * 0x10000 + 0x2100, b * 0x10000 + 0x2100, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if FRAME >= (FROM or 500) and FRAME <= (TO or 600) and FRAME % 6 == 0 then
    print(string.format("F%d inidisp=%02X nmi4200=? ", FRAME, inidisp)); shot(string.format("t%04d", FRAME))
  end
end, emu.eventType.endFrame)
