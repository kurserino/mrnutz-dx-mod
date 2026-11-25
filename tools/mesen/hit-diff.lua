-- Hit diff (research tool): same inputs as watch-writes.lua; a WRAM snapshot ($0000-$1FFF) is kept every frame and,
-- when the damage routine sets the invulnerability timer ($8D = 120, $82:A379), the bytes that changed between the
-- frame before and AFTER frames after (default 3) are printed. Defines: FRAMES (default 3000), AFTER.
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
emu.addEventCallback(function()
  local k = FRAME % 300
  if k < 4 then emu.setInput({ start = true }, 0)
  elseif k >= 150 and k < 154 then emu.setInput({ a = true }, 0)
  else emu.setInput({ right = true }, 0) end
end, emu.eventType.inputPolled)
local prev, hitAt, before = nil, nil, nil
local function snap() local t = {}; for a = 0, 0x1FFF do t[a] = w8(a) end; return t end
for _, b in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(_, v) if v == 120 and not hitAt then hitAt = FRAME; before = prev end end,
    emu.callbackType.write, b * 0x10000 + 0x8D, b * 0x10000 + 0x8D, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if hitAt and FRAME == hitAt + (AFTER or 3) then
    local now, t = snap(), {}
    for a = 0, 0x1FFF do
      if before[a] ~= now[a] and not (a >= 0x1F00) then t[#t + 1] = string.format("%04X:%d>%d", a, before[a], now[a]) end
    end
    print(string.format("HIT F%d changed=%d %s", hitAt, #t, table.concat(t, " ")))
    hitAt = nil
  end
  prev = snap()
  if FRAME >= (FRAMES or 3000) then emu.stop(0) end
end, emu.eventType.endFrame)
