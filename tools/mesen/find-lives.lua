-- RAM search for the lives counter (run on the ORIGINAL ROM from stage-00.mss, see docs/traces/find-lives.log).
-- Mr. Nutz walks right until he loses lives (same inputs as trace-sram.lua MODE=2). Full 128 KiB WRAM snapshots
-- in pairs inside three lives (HUD x2, x1, x0 per the screenshots of that run). A candidate is stable inside
-- each pair and changes by the same non-zero step between lives (any step, so nibble/BCD/offset encodings match).
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
emu.addEventCallback(function()
  local k = FRAME % 300
  if k < 4 then emu.setInput({ start = true }, 0)
  elseif k >= 150 and k < 154 then emu.setInput({ a = true }, 0)
  else emu.setInput({ right = true }, 0) end
end, emu.eventType.inputPolled)

local SIZE = 0x20000
local AT = { 1000, 1500, 4600, 4750, 6600, 6750 }
local snaps = {}
emu.addEventCallback(function()
  for i, f in ipairs(AT) do
    if FRAME == f then
      local t = {}
      for a = 0, SIZE - 1 do t[a] = w8(a) end
      snaps[i] = t
      shot(string.format("snap-%d", f))
    end
  end
  if FRAME == AT[#AT] + 10 then
    local n = 0
    for a = 0, SIZE - 1 do
      local a1, a2, b1, b2, c1, c2 = snaps[1][a], snaps[2][a], snaps[3][a], snaps[4][a], snaps[5][a], snaps[6][a]
      local d1, d2 = (b1 - a1) & 0xFF, (c1 - b1) & 0xFF
      if a1 == a2 and b1 == b2 and c1 == c2 and d1 ~= 0 and d1 == d2 then
        n = n + 1
        if n <= 40 then print(string.format("LIVES_CANDIDATE $%06X values=%d,%d,%d step=%d", 0x7E0000 + a, a1, b1, c1, d1)) end
      end
    end
    print("LIVES_CANDIDATES total=" .. n)
    emu.stop(0)
  end
end, emu.eventType.endFrame)
