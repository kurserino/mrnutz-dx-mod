-- Energy watch (research tool): writes to $7F:B00D/$7F:B00E (energy and maximum, stored XOR $B7; init at $9D:ACD2)
-- with PC and decoded value, plus the damage timer ($8D = 120). Same inputs as watch-writes.lua. Defines: FRAMES.
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
emu.addEventCallback(function()
  local k = FRAME % 300
  if k < 4 then emu.setInput({ start = true }, 0)
  elseif k >= 150 and k < 154 then emu.setInput({ a = true }, 0)
  else emu.setInput({ right = true }, 0) end
end, emu.eventType.inputPolled)
print(string.format("F0 B00D=%02X(%d) B00E=%02X(%d)", w8(0x1B00D), w8(0x1B00D) ~ 0xB7, w8(0x1B00E), w8(0x1B00E) ~ 0xB7))
emu.addMemoryCallback(function(a, v)
  local s = emu.getState()
  print(string.format("F%d W %06X=%02X dec=%d pc=%02X:%04X", FRAME, a, v, v ~ 0xB7, s["cpu.k"], s["cpu.pc"]))
end, emu.callbackType.write, 0x7FB00D, 0x7FB00E, emu.cpuType.snes, emu.memType.snesMemory)
for _, b in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(_, v) if v == 120 then print(string.format("F%d HIT", FRAME)) end end,
    emu.callbackType.write, b * 0x10000 + 0x8D, b * 0x10000 + 0x8D, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addMemoryCallback(function() print(string.format("F%d DEATH", FRAME)) end, emu.callbackType.exec, 0x81D14A, 0x81D14A, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if FRAME == 1 or FRAME % 500 == 0 then print(string.format("F%d B00D=%02X(%d) B00E=%02X(%d)", FRAME, w8(0x1B00D), w8(0x1B00D) ~ 0xB7, w8(0x1B00E), w8(0x1B00E) ~ 0xB7)) end
  if FRAME >= (FRAMES or 3000) then emu.stop(0) end
end, emu.eventType.endFrame)
