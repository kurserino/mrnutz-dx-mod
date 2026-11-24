-- Pause-menu feasibility measurements (original ROM, from a stage state; aggregated by pause-measure.ts).
-- Pauses at PRESS and stays paused for HOLD frames, then reports:
--   HOOK   CPU state at the paused-NMI branch $80:83B8 (P, M/X widths, D, DBR) and the scanline range on entry
--          and at its RTI ($80:83B3), i.e. how much of VBlank the paused NMI leaves free.
--   BG3    BG3 (HUD layer) while paused: tile numbers used by its tilemap, palettes, priority bits, whether
--          BG3 is on the main/sub screen, colour math and mode-1 BG3 priority.
--   OBJ    visible sprites while paused and how many use the Mr. Nutz palette slot.
local PRESS, HOLD = PRESS_AT or 120, 240 -- PRESS_AT: later Start for stages that open with a dialog or intro
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
playInputs({ { PRESS, PRESS + 4, { start = true } } })

local hook = { n = 0, minLine = 999, maxLine = -1, exitMin = 999, exitMax = -1, p = {}, d = {}, dbr = {} }
local function line() return emu.getState()["ppu.scanline"] end
emu.addMemoryCallback(function()
  local s = emu.getState()
  hook.n = hook.n + 1
  local l = s["ppu.scanline"]
  if l < hook.minLine then hook.minLine = l end
  if l > hook.maxLine then hook.maxLine = l end
  hook.p[string.format("%02X", s["cpu.ps"])] = true
  hook.d[string.format("%04X", s["cpu.d"])] = true
  hook.dbr[string.format("%02X", s["cpu.dbr"])] = true
end, emu.callbackType.exec, 0x8083B8, 0x8083B8, emu.cpuType.snes, emu.memType.snesMemory)
-- RTI of the NMI ($80:83B3) is shared by both paths; only count it while paused.
emu.addMemoryCallback(function()
  if w8(0x13B4) == 0 then return end
  local l = line()
  if l < hook.exitMin then hook.exitMin = l end
  if l > hook.exitMax then hook.exitMax = l end
end, emu.callbackType.exec, 0x8083B3, 0x8083B3, emu.cpuType.snes, emu.memType.snesMemory)

local function keys(t) local r = {}; for k in pairs(t) do r[#r + 1] = k end; table.sort(r); return table.concat(r, "/") end
local function ranges(set, maxv)
  local out, i = {}, 0
  while i <= maxv do
    if set[i] then
      local j = i
      while set[j + 1] do j = j + 1 end
      out[#out + 1] = (i == j) and string.format("%03X", i) or string.format("%03X-%03X", i, j)
      i = j + 1
    else i = i + 1 end
  end
  return table.concat(out, ",")
end

emu.addEventCallback(function()
  if FRAME == PRESS + 150 then
    local s = emu.getState()
    shot("paused")
    local map = s["ppu.layers[2].tilemapAddress"] * 2
    local tiles, pals, prio = {}, {}, { [0] = 0, [1] = 0 }
    for o = 0, 0x7FE, 2 do
      local e = emu.read16((map + o) & 0xFFFF, emu.memType.snesVideoRam, false)
      tiles[e & 0x3FF] = true
      pals[(e >> 10) & 7] = true
      prio[(e >> 13) & 1] = prio[(e >> 13) & 1] + 1
    end
    local palList = {}
    for k in pairs(pals) do palList[#palList + 1] = tostring(k) end
    table.sort(palList)
    print(string.format("BG3 map=$%04X chr=$%04X tiles=%s pals=%s prio0=%d prio1=%d main=$%02X sub=$%02X bg3prio=%s colormath=%s cmAddSub=%s",
      map, s["ppu.layers[2].chrAddress"] * 2, ranges(tiles, 0x3FF), table.concat(palList, ","), prio[0], prio[1],
      s["ppu.mainScreenLayers"], s["ppu.subScreenLayers"], tostring(s["ppu.mode1Bg3Priority"]),
      tostring(s["ppu.colorMathEnabled"]), tostring(s["ppu.colorMathAddSubscreen"])))
    local slot, vis, nutz = nutzSlot(), 0, 0
    for i = 0, 127 do
      local y = oam(i, 1)
      if y < 224 then
        vis = vis + 1
        if slot and ((oam(i, 3) >> 1) & 7) == slot and oam(i, 2) < 0x50 then nutz = nutz + 1 end
      end
    end
    print(string.format("OBJ visible=%d nutzEntries=%d nutzSlot=%s paused=$%02X", vis, nutz, tostring(slot), w8(0x13B4)))
    -- 8x8 OBJ tiles referenced by every on-screen entry (OBSEL $63: small 16x16, large 32x32; tile numbers 0-511,
    -- 256+ = name table 1). A WxH sprite at tile t uses t + x + 16*y, wrapping inside its 16-tile row.
    local used = {}
    for i = 0, 127 do
      local y = oam(i, 1)
      local hi = emu.read(0x200 + (i >> 2), emu.memType.snesSpriteRam, false)
      local sizeBit = (hi >> ((i & 3) * 2 + 1)) & 1
      local xHigh = (hi >> ((i & 3) * 2)) & 1
      local x = oam(i, 0) + xHigh * 256
      local n = sizeBit == 1 and 4 or 2
      local visibleX = x < 256 or x > 512 - n * 8
      if (y < 224 or y > 256 - n * 8) and visibleX then
        local tile = oam(i, 2) | ((oam(i, 3) & 1) << 8)
        for ty = 0, n - 1 do
          for tx = 0, n - 1 do
            local t = (tile & 0x100) | ((((tile & 0x0F) + tx) & 0x0F) | ((tile + ty * 16) & 0xF0))
            used[t] = true
          end
        end
      end
    end
    print("OBJTILES " .. ranges(used, 0x1FF))
  end
  if FRAME == PRESS + HOLD then
    print(string.format("HOOK runs=%d P=%s D=%s DBR=%s entryLine=%d-%d exitLine=%d-%d", hook.n, keys(hook.p), keys(hook.d), keys(hook.dbr),
      hook.minLine, hook.maxLine, hook.exitMin, hook.exitMax))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
