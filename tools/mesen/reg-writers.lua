-- Who writes the write-only PPU registers the pause menu must change and restore (pause-menu task 1.1).
-- Watches $2101 (OBSEL), $2111/$2112 (BG3 HOFS/VOFS), $212C/$212D (main/sub screens), $2130-$2132 (colour math)
-- in banks $00 and $80, during gameplay and across one debug stage skip (scene init). Prints one line per distinct
-- (register, PC) with the first value, the count, and the CPU state (A, X, Y, D, DBR, P) to locate the source.
-- Original ROM, from a stage state. Defines: WARP_AT (default 200; 0 = no skip), FRAMES (default 1500).
local WARP_AT_ = WARP_AT or 200
local FRAMES_ = FRAMES or 1500
local REGS = { 0x2101, 0x2111, 0x2112, 0x212C, 0x212D, 0x2130, 0x2131, 0x2132 }
loadStateOnBoot(function() if WARP_AT_ > 0 then ww(0x1EC9, w8(0x1EC9) | 0x01) else ww(0x1EC9, w8(0x1EC9) & 0xFE) end end)
if WARP_AT_ > 0 then playInputs({ { WARP_AT_, WARP_AT_ + 4, { r = true } } }) end

local seen, counts, order = {}, {}, {}
for _, reg in ipairs(REGS) do
  for _, bank in ipairs({ 0x00, 0x80 }) do
    local a = (bank << 16) | reg
    emu.addMemoryCallback(function(address, value)
      local s = emu.getState()
      local pc = ((s["cpu.k"] or 0) << 16) | s["cpu.pc"]
      local key = string.format("%04X@%06X", reg, pc)
      counts[key] = (counts[key] or 0) + 1
      if not seen[key] then
        seen[key] = string.format("frame=%d value=$%02X A=$%04X X=$%04X Y=$%04X D=$%04X DBR=$%02X P=$%02X gameplay=%s",
          FRAME, value, s["cpu.a"], s["cpu.x"], s["cpu.y"], s["cpu.d"], s["cpu.dbr"], s["cpu.ps"], tostring(inGameplay()))
        order[#order + 1] = key
      end
    end, emu.callbackType.write, a, a, emu.cpuType.snes, emu.memType.snesMemory)
  end
end
emu.addEventCallback(function()
  if FRAME >= FRAMES_ then
    for _, key in ipairs(order) do print(string.format("REG $%s count=%d %s", key, counts[key], seen[key])) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
