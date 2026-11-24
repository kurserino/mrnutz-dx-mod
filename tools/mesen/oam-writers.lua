-- Lists every PC that writes the OAM buffer ($7E:0321-$0520, tile/attr bytes and the rest) or its byte count $0024,
-- with the CPU state (M/X widths, D, DBR) at the first hit. Used to find all sprite-entry writers before hooking them
-- (openspec change fix-vblank-check-race, option B). Defines: END (frames, default 600).
-- Mesen reports the PC of the next instruction in write callbacks; "pc" below is that value.
local END_ = END or 600
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
emu.addEventCallback(function()
  local f = FRAME % 120
  if f < 50 then emu.setInput({ right = true }, 0) elseif f < 54 then emu.setInput({ b = true, right = true }, 0)
  elseif f < 60 then emu.setInput({ y = true }, 0) elseif f < 100 then emu.setInput({ left = true }, 0) end
end, emu.eventType.inputPolled)
local seen = {}
local function onWrite(kind)
  return function(address)
    local s = emu.getState()
    local key = string.format("%s %02X:%04X", kind, s["cpu.k"], s["cpu.pc"])
    if seen[key] then seen[key] = seen[key] + 1; return end
    seen[key] = 1
    local p = s["cpu.ps"]
    print(string.format("FIRST %s addr=%04X F%d m%d x%d D=%04X DBR=%02X line=%d", key, address & 0xFFFF, FRAME,
      (p >> 5) & 1, (p >> 4) & 1, s["cpu.d"] or -1, s["cpu.dbr"] or -1, s["ppu.scanline"]))
  end
end
for _, b in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(onWrite("count"), emu.callbackType.write, b * 0x10000 + 0x0024, b * 0x10000 + 0x0024, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(onWrite("buf"), emu.callbackType.write, b * 0x10000 + 0x0321, b * 0x10000 + 0x0520, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if FRAME >= END_ then
    local t = {}
    for k, n in pairs(seen) do t[#t + 1] = k .. " x" .. n end
    table.sort(t)
    for _, l in ipairs(t) do print("TOTAL " .. l) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
