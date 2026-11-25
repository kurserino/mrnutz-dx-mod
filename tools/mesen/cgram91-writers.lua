-- Who writes CGRAM entry $91 (sprite palette 1, entry 1)? Logs writes of $91 to CGADD ($2121) with the PC, and DMA
-- transfers to $2122 (source, size, CGADD at the time), for 120 frames.
loadStateOnBoot()
local seen, cgadd = {}, 0
local function note(k) if not seen[k] then seen[k] = 0; print(string.format("F%d %s", FRAME, k)) end; seen[k] = seen[k] + 1 end
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v)
    cgadd = v
    if v == 0x91 or v == 0x90 then local s = emu.getState(); note(string.format("CGADD=%02X pc=%02X:%04X", v, s["cpu.k"], s["cpu.pc"])) end
  end, emu.callbackType.write, b * 0x10000 + 0x2121, b * 0x10000 + 0x2121, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(_, v)
    for ch = 0, 7 do
      if (v >> ch) & 1 == 1 and bus8(0x4301 + ch * 16) == 0x22 then
        local s = emu.getState()
        note(string.format("DMA2122 ch%d src=%02X%04X n=%04X cgadd=%02X pc=%02X:%04X", ch, bus8(0x4304 + ch * 16), bus16(0x4302 + ch * 16), bus16(0x4305 + ch * 16), cgadd, s["cpu.k"], s["cpu.pc"]))
      end
    end
  end, emu.callbackType.write, b * 0x10000 + 0x420B, b * 0x10000 + 0x420B, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if FRAME >= 120 then for k, n in pairs(seen) do print("TOTAL " .. k .. " x" .. n) end; emu.stop(0) end
end, emu.eventType.endFrame)
