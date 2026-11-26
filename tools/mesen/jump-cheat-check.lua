-- Jump cheat check (regression tool): from a stage state, Mr. Nutz presses B at frames 60, 95, 130 and 165 (30
-- frames each: a jump, then presses in the air); prints the jump peak (pixels above the ground at frame 55). Cheats:
-- PAR, PAR2 (Mesen cheat engine, e.g. a ROM patch). Defines: END (default 300).
loadStateOnBoot(function()
  for _, p in ipairs({ PAR, PAR2 }) do if p then emu.addCheat(emu.cheatType.snesProActionReplay, string.format("%08X", p)) end end
end)
emu.addEventCallback(function()
  for _, f in ipairs({ 60, 95, 130, 165 }) do if FRAME >= f and FRAME < f + 30 then emu.setInput({ b = true }, 0) end end
end, emu.eventType.inputPolled)
local ground, peak = -1, 0
emu.addEventCallback(function()
  if FRAME == 55 then ground = w16(0x39) end
  if ground >= 0 and ground - w16(0x39) > peak then peak = ground - w16(0x39) end
  if FRAME == 150 then shot("jump") end
  if FRAME >= (END or 300) then print(string.format("RESULT jumpPeak=%d", peak)); emu.stop(0) end
end, emu.eventType.endFrame)
