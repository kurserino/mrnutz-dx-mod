-- Energy search (research tool): random play without cheats in a stage state. Every frame, WRAM $0000-$1FFF bytes
-- holding 1..15 that change by exactly -1 are counted as "drops"; a death ($81:D14A) is logged. At the end, bytes with
-- at least MINDROPS drops, no other kind of change except a rise back to their first value, are printed with their
-- history. Defines: END (default 6000), SEED, MINDROPS (default 2).
local END_, MIN_ = END or 6000, MINDROPS or 2
math.randomseed(SEED or 1)
loadStateOnBoot()
local dir, left = true, 0
emu.addEventCallback(function()
  if left <= 0 then local r = math.random(); dir = r < 0.75; left = 20 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ right = dir, left = not dir, b = FRAME % 30 < 10 }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function() print(string.format("F%d DEATH", FRAME)) end, emu.callbackType.exec, 0x81D14A, 0x81D14A, emu.cpuType.snes, emu.memType.snesMemory)
local first, last, drops, bad, hist = {}, {}, {}, {}, {}
emu.addEventCallback(function()
  if FRAME < 30 then return end
  for a = 0, 0x1FFF do
    local v = w8(a)
    if first[a] == nil then first[a] = v; last[a] = v; drops[a] = 0; hist[a] = string.format("%d", v)
    elseif v ~= last[a] then
      if v == last[a] - 1 and v <= 15 then drops[a] = drops[a] + 1
      elseif v ~= first[a] then bad[a] = true end
      if #hist[a] < 100 then hist[a] = hist[a] .. string.format(">%d@%d", v, FRAME) end
      last[a] = v
    end
  end
  if FRAME >= END_ then
    for a = 0, 0x1FFF do
      if not bad[a] and drops[a] >= MIN_ and first[a] <= 15 then print(string.format("CAND $%04X drops=%d %s", a, drops[a], hist[a])) end
    end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
