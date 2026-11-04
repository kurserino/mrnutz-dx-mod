-- Mesen 2 (2.2.1) headless: CPU state at candidate hook sites (evidence for task 1.1).
-- Prints the first state per distinct (P, DBR, D) combination and per-site execution counts.
local SITES = { 0x81828A, 0x81828D, 0x818290 }
local MAX_FRAMES = 3000
local inputs = {
  { 200, 205, { start = true } }, { 400, 405, { start = true } }, { 600, 605, { start = true } },
  { 800, 805, { start = true } }, { 1000, 1005, { start = true } }, { 1200, 1205, { start = true } },
  { 1400, 1405, { a = true } },
  { 1600, 2400, { right = true } }, { 2400, 2410, { b = true } }, { 2410, 2600, { right = true } },
  { 2600, 2605, { start = true } }, { 2700, 2705, { start = true } }, { 2710, 3000, { left = true } },
}
local frame, seen, counts = 0, {}, {}
local function hex(v, n) return string.format("%0" .. n .. "X", v) end

for _, site in ipairs(SITES) do
  counts[site] = 0
  emu.addMemoryCallback(function()
    counts[site] = counts[site] + 1
    local s = emu.getState()
    local key = hex(site, 6) .. hex(s["cpu.ps"], 2) .. hex(s["cpu.dbr"], 2) .. hex(s["cpu.d"], 4)
    if not seen[key] then
      seen[key] = true
      print("SITE $" .. hex(site, 6) .. " frame=" .. frame .. " P=$" .. hex(s["cpu.ps"], 2)
        .. " m8=" .. tostring((s["cpu.ps"] & 0x20) ~= 0) .. " x8=" .. tostring((s["cpu.ps"] & 0x10) ~= 0)
        .. " E=" .. tostring(s["cpu.emulationMode"]) .. " DBR=$" .. hex(s["cpu.dbr"], 2) .. " D=$" .. hex(s["cpu.d"], 4)
        .. " SP=$" .. hex(s["cpu.sp"], 4) .. " A=$" .. hex(s["cpu.a"], 4) .. " X=$" .. hex(s["cpu.x"], 4) .. " Y=$" .. hex(s["cpu.y"], 4)
        .. " scanline=" .. tostring(s["ppu.scanline"]))
    end
  end, emu.callbackType.exec, site, site, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  for _, st in ipairs(inputs) do
    if frame >= st[1] and frame < st[2] then emu.setInput(st[3], 0); return end
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frame = frame + 1
  if frame >= MAX_FRAMES then
    for _, site in ipairs(SITES) do print("SITE total $" .. hex(site, 6) .. " count=" .. counts[site]) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
