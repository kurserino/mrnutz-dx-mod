-- HUD energy probe (research tool): counts full-heart pixels ($FF0000) in the energy row under "nutz" (x 0..79,
-- y 22..31; empty hearts are $6B0000) every frame
-- with emu.getPixel; when the count drops or rises, the full WRAM (128 KiB) is compared between the snapshot taken
-- DELAY frames before and now, and changed bytes are printed with plain / XOR $B7 / XOR $A3 decodings of values <= 12.
-- Same inputs as watch-writes.lua. Defines: FRAMES (default 3000), DELAY (default 20).
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
emu.addEventCallback(function()
  local k = FRAME % 300
  if k < 4 then emu.setInput({ start = true }, 0)
  elseif k >= 150 and k < 154 then emu.setInput({ a = true }, 0)
  else emu.setInput({ right = true }, 0) end
end, emu.eventType.inputPolled)
local function redCount()
  local n = 0
  for y = 22, 31 do for x = 0, 79 do
    local c = emu.getPixel(x, y)
    local r, g, b = (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
    if r > 200 and g < 40 and b < 40 then n = n + 1 end
  end end
  return n
end
local ring, last = {}, -1
local function snap() local t = {}; for a = 0, 0x1FFFF do t[a] = emu.read(a, emu.memType.snesWorkRam, false) end; return t end
emu.addEventCallback(function()
  if FRAME % 10 == 0 then ring[FRAME] = snap(); ring[FRAME - 10 * 6] = nil end
  local n = redCount()
  if last >= 0 and n ~= last then
    local base = ring[(FRAME // 10) * 10 - (DELAY or 20)]
    print(string.format("F%d RED %d -> %d", FRAME, last, n))
    if base then
      local now, t = snap(), {}
      for a = 0, 0x1FFFF do
        local b, c = base[a], now[a]
        if b ~= c and a ~= 0x1BE0E then
          local tag = {}
          if b <= 12 and c <= 12 then tag[#tag + 1] = "plain" end
          if (b ~ 0xB7) <= 12 and (c ~ 0xB7) <= 12 then tag[#tag + 1] = string.format("xB7 %d>%d", b ~ 0xB7, c ~ 0xB7) end
          if #tag > 0 then t[#t + 1] = string.format("%05X:%d>%d(%s)", a, b, c, table.concat(tag, ",")) end
        end
      end
      print("  " .. table.concat(t, " "))
    end
    shot(string.format("red%04d", FRAME))
  end
  last = n
  if FRAME >= (FRAMES or 3000) then emu.stop(0) end
end, emu.eventType.endFrame)
