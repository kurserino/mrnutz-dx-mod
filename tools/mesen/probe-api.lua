-- Lists Mesen Lua API details used by the tooling: functions, SRAM memory types, access counter types and the
-- PPU state keys (for VRAM/BG layout analysis).
local names = {}
for k, v in pairs(emu) do if type(v) == "function" then names[#names + 1] = k end end
table.sort(names)
print("FUNCTIONS " .. table.concat(names, ","))
local mem = {}
for k in pairs(emu.memType) do if k:lower():find("snes") then mem[#mem + 1] = k end end
table.sort(mem)
print("MEMTYPES " .. table.concat(mem, ","))
if emu.counterType then
  local c = {}
  for k in pairs(emu.counterType) do c[#c + 1] = k end
  table.sort(c)
  print("COUNTERTYPES " .. table.concat(c, ","))
end
emu.addEventCallback(function()
  local ok, size = pcall(function() return emu.getMemorySize(emu.memType.snesSaveRam) end)
  print("SAVERAM size=" .. tostring(size) .. " ok=" .. tostring(ok))
  local keys = {}
  for k in pairs(emu.getState()) do if k:find("^ppu") or k:find("^snes.ppu") then keys[#keys + 1] = k end end
  table.sort(keys)
  print("PPUKEYS " .. table.concat(keys, ","))
  local ok2, res = pcall(function() return emu.getAccessCounters(emu.counterType.writeCount, emu.memType.snesVideoRam) end)
  print("COUNTERS ok=" .. tostring(ok2) .. " type=" .. type(res) .. (type(res) == "table" and (" n=" .. #res) or (" err=" .. tostring(res))))
  emu.stop(0)
end, emu.eventType.endFrame)
