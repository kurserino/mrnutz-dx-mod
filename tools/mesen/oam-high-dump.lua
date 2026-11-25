-- PPU OAM entries past the bytes in use ($0026) at frame AT: y, tile, attr, grouped.
loadStateOnBoot()
emu.addEventCallback(function()
  if FRAME == (AT or 200) then
    local lim = w16(0x0026) // 4
    local groups = {}
    for i = lim, 127 do
      local k = string.format("y=%02X tile=%02X attr=%02X", oam(i, 1), oam(i, 2), oam(i, 3))
      groups[k] = (groups[k] or 0) + 1
    end
    print(string.format("F%d bytes0024=%d bytes0026=%d sticky=%02X", FRAME, w16(0x0024), w16(0x0026), w8(0x1BE09)))
    for k, n in pairs(groups) do print("  " .. k .. " x" .. n) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
