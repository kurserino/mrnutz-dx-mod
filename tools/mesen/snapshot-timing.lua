-- scan_snapshot timing (regression tool): for every DMA started with $420B = $80 (channel 7, our OAM snapshot), the
-- scanline at the start and at the next $2102 write (OAMADD restore right after the DMA). Debug stage skip at frame
-- 60 (INPUT as colour-watch.lua 5), SAVEFUR=1 save record. RESULT max end line (must stay <= 260).
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
local started, maxEnd, n = nil, 0, 0
for _, b in ipairs({ 0x00, 0x80, 0xA0 }) do
  emu.addMemoryCallback(function(_, v)
    if v == 0x80 then started = emu.getState()["ppu.scanline"] end
  end, emu.callbackType.write, b * 0x10000 + 0x420B, b * 0x10000 + 0x420B, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function()
    if started then
      local e = emu.getState()["ppu.scanline"]
      n = n + 1
      if e > maxEnd then maxEnd = e end
      print(string.format("F%d SNAPSHOT start=%d end=%d", FRAME, started, e))
      started = nil
    end
  end, emu.callbackType.write, b * 0x10000 + 0x2102, b * 0x10000 + 0x2102, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if FRAME >= (END or 700) then print(string.format("RESULT snapshots=%d maxEndLine=%d", n, maxEnd)); emu.stop(0) end
end, emu.eventType.endFrame)
