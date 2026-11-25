-- Stage Clear screen probe (research tool). From a boss state, a Pro Action Replay code (PAR, e.g. the witch health
-- 7E19A300 in decimal) kills the boss so the game shows STAGE CLEAR. Logs every LOGEVERY frames: NMI handler
-- ($01DC), main-loop request ($13B6), scene table, which CGRAM sprite slots hold the Mr. Nutz palette ($85:9CC0), and
-- the visible OAM entries grouped by palette with their tile range; screenshots every SHOTEVERY frames.
-- SAVEFUR: write a save record with that fur (outfit 0) after the state load. Defines: END (default 1500).
loadStateOnBoot(function()
  if SAVEFUR then
    local fur, outfit = SAVEFUR, 0
    local w0, w2, w4 = 0x5A4E, 0x01 | (fur << 8), outfit
    local ck = 0xFFFF ~ ((w0 + w2 + w4) & 0xFFFF)
    local rec = { 0x4E, 0x5A, 0x01, fur, outfit, 0x00, ck & 0xFF, ck >> 8 }
    for i = 1, 8 do emu.write(0x100 + i - 1, rec[i], emu.memType.snesSaveRam) end
  end
  if PAR then emu.addCheat(emu.cheatType.snesProActionReplay, string.format("%08X", PAR)) end
end)
local function nutzSlots()
  local t = {}
  for s = 0, 7 do
    local same = 0
    for e = 1, 15 do if cg(0x80 + s * 16 + e) == bus16(0x859CC0 + e * 2) then same = same + 1 end end
    if same >= 12 then t[#t + 1] = s .. "(" .. same .. ")" end
  end
  return table.concat(t, ",")
end
local function oamSummary()
  local g = {}
  for i = 0, 127 do
    if oam(i, 1) < 224 then
      local attr = oam(i, 3)
      local pal = (attr >> 1) & 7
      local tile = oam(i, 2) | ((attr & 1) << 8)
      local r = g[pal] or { n = 0, lo = 999, hi = -1 }
      r.n = r.n + 1; if tile < r.lo then r.lo = tile end; if tile > r.hi then r.hi = tile end
      g[pal] = r
    end
  end
  local t = {}
  for p = 0, 7 do if g[p] then t[#t + 1] = string.format("p%d:%dx[%03X-%03X]", p, g[p].n, g[p].lo, g[p].hi) end end
  return table.concat(t, " ")
end
-- Mr. Nutz is invulnerable and jumps around (the boss death check runs on contact), lives held at x2.
math.randomseed(SEED or 1)
local dir, left = true, 0
emu.addEventCallback(function()
  if left <= 0 then dir = math.random() < 0.5; left = 30 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ left = dir, right = not dir, b = FRAME % 40 < 20 }, 0)
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function()
  ww(0x008D, 0x2D); ww(0x1889, 0xB5); ww(0x188A, 0xA3)
end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
local last = ""
emu.addEventCallback(function()
  local eOut, eFur = expectedColours()
  local sel = {}
  for s2 = 0, 7 do if cg(0x80 + s2 * 16 + 6) == eOut and cg(0x80 + s2 * 16 + 15) == eFur then sel[#sel + 1] = tostring(s2) end end
  local line = string.format("nmi=%04X req=%04X scene=%02X%04X selSlots=[%s] nutzSlots=[%s] oam=%s", w16(0x01DC), w16(0x13B6),
    w8(0x0560), w16(0x055E), table.concat(sel, ","), nutzSlots(), oamSummary())
  if FRAME % (LOGEVERY or 20) == 0 and line ~= last then print(string.format("F%d %s", FRAME, line)); last = line end
  if FRAME % (SHOTEVERY or 60) == 0 then shot(string.format("f%04d", FRAME)) end
  if FRAME >= (END or 1500) then emu.stop(0) end
end, emu.eventType.endFrame)
