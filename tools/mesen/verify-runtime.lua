-- Mesen 2 (2.2.1) headless smoke test of the runtime palette patch (tasks 3.3 partial).
-- Run on output/Mr. Nutz.runtime.sfc via: npm run verify:runtime
-- Prints CHECK lines with CGRAM $C6-$C9/$CB-$CF and WRAM state after each shortcut.
local frame = 0
local inputs = {
  { 200, 205, { start = true } }, { 400, 405, { start = true } }, { 600, 605, { start = true } },
  { 800, 805, { start = true } }, { 1000, 1005, { start = true } }, { 1200, 1205, { start = true } },
  { 1400, 1405, { a = true } },
  { 1750, 1790, { select = true, l = true } },  -- held 40 frames: must cycle fur exactly once
  { 1850, 1890, { select = true, r = true } },  -- outfit once
  { 1950, 1953, { select = true, l = true } },  -- fur again (short press)
  { 2000, 2500, { right = true } }, { 2500, 2510, { b = true } }, { 2510, 2700, { right = true } },
  { 2750, 2755, { select = true } }, { 2756, 2760, { select = true, l = true } }, -- fur 3
  { 2800, 2805, { select = true, l = true } },  -- fur wraps to 0 (original)
  { 2850, 2855, { l = true } },                 -- L alone: no change
  { 2900, 2905, { r = true } },                 -- R alone: no change
}
local checks = { 1745, 1800, 1900, 1960, 2490, 2740, 2790, 2840, 2890, 2940 }
local isCheck = {}
for _, f in ipairs(checks) do isCheck[f] = true end

local function hex(v, n) return string.format("%0" .. n .. "X", v) end
local function cg(e) return emu.read16(e * 2, emu.memType.snesCgRam, false) end
local function w(a) return emu.read(a - 0x7E0000, emu.memType.snesWorkRam, false) end

local hookRuns, siteRuns = 0, 0
emu.addMemoryCallback(function() hookRuns = hookRuns + 1 end, emu.callbackType.exec, 0xA08000, 0xA08000, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() siteRuns = siteRuns + 1 end, emu.callbackType.exec, 0x818290, 0x818290, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  for _, s in ipairs(inputs) do
    if frame >= s[1] and frame < s[2] then emu.setInput(s[3], 0); return end
  end
end, emu.eventType.inputPolled)

local tracked, mismatches = nil, 0
emu.addEventCallback(function()
  frame = frame + 1
  if isCheck[frame] then
    -- Private slot X (customSlot) holds the selection; slot 4 ($C0, level 1) must stay original.
    local X = w(0x7FBE06)
    local base = X < 8 and (0x80 + X * 16) or 0xC0
    local outfit, fur, s4 = {}, {}, {}
    for e = 6, 9 do outfit[#outfit + 1] = hex(cg(base + e), 4) end
    for e = 11, 15 do fur[#fur + 1] = hex(cg(base + e), 4) end
    for e = 0xC0, 0xCF do s4[#s4 + 1] = hex(cg(e), 4) end
    print("CHECK frame=" .. frame .. " furIdx=" .. w(0x7FBE02) .. " outfitIdx=" .. w(0x7FBE03)
      .. " magic=$" .. hex(w(0x7FBE01), 2) .. hex(w(0x7FBE00), 2)
      .. " outfit=" .. table.concat(outfit, ",") .. " fur=" .. table.concat(fur, ",")
      .. " X=" .. X .. " slot4=" .. table.concat(s4, ",") .. " hookRuns=" .. hookRuns .. " siteRuns=" .. siteRuns)
    emu.takeScreenshot() -- flush; the real shot is taken 4 frames later (screenshot lag in --testRunner)
  end
  if isCheck[frame - 4] then
    local png = emu.takeScreenshot()
    print("SHOT check-" .. (frame - 4) .. " " .. (png:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)))
  end
  -- Persistence while walking: CGRAM must keep the selection (fur idx 2, outfit idx 1) from 1965 to 2740.
  local X = w(0x7FBE06)
  local xb = X < 8 and (0x80 + X * 16) or 0xC0
  if frame == 1965 then tracked = cg(xb + 15) .. ":" .. cg(xb + 6) end
  if frame > 1965 and frame < 2740 and tracked and (cg(xb + 15) .. ":" .. cg(xb + 6)) ~= tracked then mismatches = mismatches + 1 end
  if frame >= 2960 then
    print("PERSIST mismatches=" .. mismatches .. " frames=1966-2739")
    print("RUNS hook=" .. hookRuns .. " site=" .. siteRuns)
    emu.stop(0)
  end
end, emu.eventType.endFrame)
