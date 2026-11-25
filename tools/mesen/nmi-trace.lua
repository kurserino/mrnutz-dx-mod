-- PCs executed right after the NMI of frame AT (stage skip transition): first 400 instructions, with scanline.
loadStateOnBoot()
emu.addEventCallback(function()
  if FRAME == 55 then ww(0x1EC9, w8(0x1EC9) | 1) end
  if FRAME >= 60 and FRAME < 64 then emu.setInput({ r = true }, 0) end
  if FRAME == 70 then ww(0x1EC9, w8(0x1EC9) & 0xFE) end
end, emu.eventType.inputPolled)
local cb, n, last = nil, 0, ""
emu.addEventCallback(function()
  if FRAME ~= (AT or 540) or cb then return end
  cb = emu.addMemoryCallback(function()
    n = n + 1
    local s = emu.getState()
    local pc = string.format("%02X:%04X", s["cpu.k"], s["cpu.pc"])
    if n <= 1200 and (n % 1 == 0) then
      if n <= 60 or n % 20 == 0 then print(string.format("I%d %s line=%d", n, pc, s["ppu.scanline"])) end
    end
    if n == 1200 then emu.removeMemoryCallback(cb, emu.callbackType.exec, 0, 0xFFFFFF) end
  end, emu.callbackType.exec, 0x000000, 0xFFFFFF, emu.cpuType.snes, emu.memType.snesMemory)
end, emu.eventType.nmi)
emu.addEventCallback(function() if FRAME >= (AT or 540) + 3 then emu.stop(0) end end, emu.eventType.endFrame)
