-- Mr. Blizzard (stage-35 yeti boss) breath attack: per-frame log of sprite CGRAM ($80-$FF) changes, the palettes the
-- visible OAM entries use, the hook state (S/X/pending) and every CGRAM writer (direct $2122 and DMA to $2122).
-- Mr. Nutz is invulnerable ($008D=$2D) and stands still so the boss keeps attacking.
-- Defines: END (frames, default 1500), FUR / OUTFIT (written to the hook state at frame 5; ignored on the original ROM).
local END_ = END or 1500
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
if PRESS then playInputs({ { 0, 40, { left = true } } }) end

local prev = {}
local writers = {}
local function note(kind)
  local s = emu.getState()
  local k = string.format("%s %02X:%04X", kind, s["cpu.k"], s["cpu.pc"])
  writers[k] = (writers[k] or 0) + 1
  if writers[k] == 1 then print(string.format("F%d first %s cgadd?=%02X", FRAME, k, bus8(0x2121))) end
end
for _, b in ipairs({ 0x00, 0x80 }) do
  -- direct $2122 writes: disabled (the write callback also fires for unrelated PCs in 2.2.1)
  emu.addMemoryCallback(function(_, v)
    for ch = 0, 7 do
      if (v >> ch) & 1 == 1 and bus8(0x4301 + ch * 16) == 0x22 then
        note(string.format("dma2122ch%d src=%02X%04X n=%04X", ch, bus8(0x4304 + ch * 16), bus16(0x4302 + ch * 16), bus16(0x4305 + ch * 16)))
      end
    end
  end, emu.callbackType.write, b * 0x10000 + 0x420B, b * 0x10000 + 0x420B, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  if FRAME == 0 then return end
  if FRAME == 5 and FUR then ww(NUTZ.fur, FUR); ww(NUTZ.outfit, OUTFIT or 0) end
  if INVULN and w8(0x13B4) == 0 then ww(0x008D, 0x2D) end
  local changed = {}
  for slot = -8, 7 do
    local line = paletteLine(0x80 + slot * 16)
    if prev[slot] and prev[slot] ~= line then changed[#changed + 1] = slot .. ":" .. line end
    prev[slot] = line
  end
  local used = {}
  for i = 0, 127 do
    if oam(i, 1) < 224 then
      local attr = oam(i, 3)
      local pal = (attr >> 1) & 7
      local tile = oam(i, 2) | ((attr & 1) << 8)
      used[pal] = (used[pal] or 0) + 1
    end
  end
  local u = {}
  for p = 0, 7 do if used[p] then u[#u + 1] = p .. "x" .. used[p] end end
  local o = inGameplay() and nutzOracle() or {}
  local bad = (o.foreignOnX or 0) > 0 or (o.nutz and o.nutz > 0 and not o.nutzOk)
  if bad then
    foreignFrames = (foreignFrames or 0) + 1
    local d = {}
    for i = 0, 127 do
      if oam(i, 1) < 224 and ((oam(i, 3) >> 1) & 7) == o.X then
        d[#d + 1] = string.format("%d:t%03X", i, oam(i, 2) | ((oam(i, 3) & 1) << 8))
      end
    end
    print(string.format("F%d ORACLE foreignOnX=%d nutz=%d ok=%s X=%d onX=[%s]", FRAME, o.foreignOnX or 0, o.nutz or 0, tostring(o.nutzOk), o.X, table.concat(d, " ")))
    if foreignFrames % 20 == 1 then shot(string.format("bad-%04d", FRAME)) end
  end
  if #changed > 0 then
    print(string.format("F%d game=%s S=%s X=%d pend=%02X used=[%s]", FRAME, tostring(inGameplay()), tostring(nutzSlot()), w8(NUTZ.customSlot), w8(0x1BE20), table.concat(u, " ")))
    for _, c in ipairs(changed) do print("  slot " .. c) end
  end
  if FRAME % (SHOTEVERY or 30) == 0 then shot(string.format("t-%04d", FRAME)) end
  if FRAME >= END_ then
    for k, n in pairs(writers) do print("WRITER " .. k .. " x" .. n) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
