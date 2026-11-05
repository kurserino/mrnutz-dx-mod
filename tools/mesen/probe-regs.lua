-- Prints CPU state at given exec addresses (first 3 hits each), from a stage state. Used to confirm M/X widths
-- before writing patch bytes (sram-persistence D2). Defines: FRAMES=N. Sites are listed below.
local SITES = { 0x81C45C, 0x82BA22, 0x9CF819 }
local FRAMES_ = FRAMES or 300
local hits = {}
if STATE_HEX then loadStateOnBoot() end
for _, site in ipairs(SITES) do
  emu.addMemoryCallback(function()
    hits[site] = (hits[site] or 0) + 1
    if hits[site] > 3 then return end
    local s = emu.getState()
    print(string.format("SITE $%06X frame=%d P=$%02X m8=%s x8=%s A=$%04X X=$%04X Y=$%04X D=$%04X DBR=$%02X", site, FRAME, s["cpu.ps"],
      tostring((s["cpu.ps"] & 0x20) ~= 0), tostring((s["cpu.ps"] & 0x10) ~= 0), s["cpu.a"], s["cpu.x"], s["cpu.y"], s["cpu.d"], s["cpu.dbr"]))
  end, emu.callbackType.exec, site, site, emu.cpuType.snes, emu.memType.snesMemory)
end
local steps = {}
for k = 0, 11 do steps[#steps + 1] = { 200 + k * 200, 205 + k * 200, k % 2 == 0 and { start = true } or { a = true } } end
if not STATE_HEX then playInputs(steps) end
emu.addEventCallback(function()
  if FRAME >= FRAMES_ then
    for _, site in ipairs(SITES) do print(string.format("SITE total $%06X count=%d", site, hits[site] or 0)) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
