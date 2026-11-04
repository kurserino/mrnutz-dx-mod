-- Mesen 2 (2.2.1) headless WRAM usage scan (evidence E5).
-- Counters are reset after boot (frame 1000) so the boot-time RAM clear is ignored; any byte read or
-- written afterwards (menus, level load, gameplay, pause) counts as used. One run is NOT proof of
-- unused RAM across the whole game; it only rules regions out.

local RESET_AT, MAX_FRAMES, MIN_RUN = 1000, 4200, 16
local inputs = {
  { 200, 205, { start = true } }, { 400, 405, { start = true } }, { 600, 605, { start = true } },
  { 800, 805, { start = true } }, { 1000, 1005, { start = true } }, { 1200, 1205, { start = true } },
  { 1400, 1405, { a = true } },
  { 1600, 2400, { right = true } }, { 2400, 2410, { b = true } }, { 2410, 3000, { right = true } },
  { 3000, 3200, { left = true, b = true } }, { 3200, 3400, { right = true, y = true } },
  { 3500, 3505, { start = true } }, { 3700, 3705, { start = true } },
  { 3800, 4200, { right = true } },
}
local frame = 0
emu.addEventCallback(function()
  for _, s in ipairs(inputs) do
    if frame >= s[1] and frame < s[2] then emu.setInput(s[3], 0); return end
  end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  frame = frame + 1
  if frame == RESET_AT then emu.resetAccessCounters() end
  if frame >= MAX_FRAMES then
    local reads = emu.getAccessCounters(emu.memType.snesWorkRam, emu.counterType.readCount)
    local writes = emu.getAccessCounters(emu.memType.snesWorkRam, emu.counterType.writeCount)
    local size = emu.getMemorySize(emu.memType.snesWorkRam)
    local runStart, total = nil, 0
    for a = 0, size do
      local unused = a < size and (reads[a] or 0) == 0 and (writes[a] or 0) == 0
      if unused and not runStart then runStart = a end
      if not unused and runStart then
        local len = a - runStart
        if len >= MIN_RUN then
          print(string.format("UNUSED $%06X..$%06X len=%d", 0x7E0000 + runStart, 0x7E0000 + a - 1, len))
          total = total + len
        end
        runStart = nil
      end
    end
    print("UNUSED total=" .. total .. " frames=" .. frame .. " resetAt=" .. RESET_AT)
    emu.stop(0)
  end
end, emu.eventType.endFrame)
