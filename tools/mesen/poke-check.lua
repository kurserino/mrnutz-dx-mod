-- Writes one WRAM byte from a stage state and screenshots the HUD, to confirm a RAM-search candidate.
-- Defines: ADDR=<WRAM offset, decimal>, VALUE=<byte>, HOLD=1 to rewrite every frame (cheat-like).
-- Walks right so hits/deaths happen; shots at frames 60 (before), 120 (after the write) and END (default 1500).
local END_ = END or 1500
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
playInputs({ { 200, END_ + 100, { right = true } } })
emu.addEventCallback(function()
  if FRAME == 60 then print(string.format("BEFORE $7E%04X=%d", ADDR, w8(ADDR))); shot("before") end
  if FRAME == 100 or (HOLD == 1 and FRAME > 100) then ww(ADDR, VALUE) end
  if FRAME == 120 then print(string.format("AFTER $7E%04X=%d", ADDR, w8(ADDR))); shot("after") end
  if FRAME == END_ then print(string.format("LATE $7E%04X=%d", ADDR, w8(ADDR))); shot("late") end
  if FRAME >= END_ + 10 then emu.stop(0) end
end, emu.eventType.endFrame)
