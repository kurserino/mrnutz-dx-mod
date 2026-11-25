-- Stage Clear init (research tool): state when $9D:E452 (JSL $9DABA7, scene init right after [$055E] = $82:D474)
-- is entered and when it returns to $9D:E456: last INIDISP write, scanline, P/DBR/D, CGRAM slot 4 vs $85:9CC0; then
-- every later CGRAM DMA/CGADD write to the sprite slots until END. PAR kills the boss (see stage-clear-probe.lua).
loadStateOnBoot(function() emu.addCheat(emu.cheatType.snesProActionReplay, string.format("%08X", PAR)) end)
math.randomseed(1)
local dir, left = true, 0
emu.addEventCallback(function()
  if left <= 0 then dir = math.random() < 0.5; left = 30 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ left = dir, right = not dir, b = FRAME % 40 < 20 }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function() ww(0x008D, 0x2D) end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
local inidisp, cgadd, after = -1, 0, false
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v) inidisp = v end, emu.callbackType.write, b * 0x10000 + 0x2100, b * 0x10000 + 0x2100, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(_, v)
    cgadd = v
    if after and v >= 0x80 then local s = emu.getState(); print(string.format("F%d CGADD=%02X pc=%02X:%04X", FRAME, v, s["cpu.k"], s["cpu.pc"])) end
  end, emu.callbackType.write, b * 0x10000 + 0x2121, b * 0x10000 + 0x2121, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function(_, v)
    if not after then return end
    for ch = 0, 7 do
      if (v >> ch) & 1 == 1 and bus8(0x4301 + ch * 16) == 0x22 then
        local s = emu.getState()
        print(string.format("F%d DMA2122 cgadd=%02X n=%04X src=%02X%04X pc=%02X:%04X", FRAME, cgadd, bus16(0x4305 + ch * 16), bus8(0x4304 + ch * 16), bus16(0x4302 + ch * 16), s["cpu.k"], s["cpu.pc"]))
      end
    end
  end, emu.callbackType.write, b * 0x10000 + 0x420B, b * 0x10000 + 0x420B, emu.cpuType.snes, emu.memType.snesMemory)
end
local function slot4()
  local same = 0
  for e = 1, 15 do if cg(0xC0 + e) == bus16(0x859CC0 + e * 2) then same = same + 1 end end
  return same
end
local function regs(tag)
  local s = emu.getState()
  print(string.format("F%d %s inidisp=%02X line=%d P=%02X DBR=%02X D=%04X S=%04X slot4match=%d/15 nmi=%04X 4200?", FRAME, tag, inidisp,
    s["ppu.scanline"], s["cpu.ps"], s["cpu.dbr"], s["cpu.d"], s["cpu.sp"], slot4(), w16(0x01DC)))
end
emu.addMemoryCallback(function() regs("enter E452") end, emu.callbackType.exec, 0x9DE452, 0x9DE452, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() regs("back E456"); after = true end, emu.callbackType.exec, 0x9DE456, 0x9DE456, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if after and FRAME % 100 == 0 then print(string.format("F%d slot4match=%d/15 inidisp=%02X", FRAME, slot4(), inidisp)) end
  if FRAME >= (END or 1300) then emu.stop(0) end
end, emu.eventType.endFrame)
