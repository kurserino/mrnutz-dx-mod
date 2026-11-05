-- Native pause research (original ROM, from a stage state). Start at PRESS, Start again at RELEASE.
--   PAUSE_FLAG  WRAM bytes equal while playing before and after the pause, different and stable while paused.
--   PC          histogram of the PC at every NMI-less sample (exec callbacks are too heavy): end-of-frame PC.
--   NMI         whether the gameplay NMI joypad mirror ($81:828A) and the OAM upload ($81:C36A) run while paused.
--   READS       who reads the pause flag candidates (first 8 distinct PCs) - the pause loop.
local PRESS, RELEASE, END_AT = 200, 500, 700
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
playInputs({ { PRESS, PRESS + 4, { start = true } }, { RELEASE, RELEASE + 4, { start = true } } })

local snaps = {}
local function snap() local t = {}; for a = 0, 0x1FFFF do t[a] = w8(a) end; return t end
local counts = { pad = { 0, 0 }, oam = { 0, 0 } }
local function phaseIdx() return (FRAME > PRESS + 20 and FRAME < RELEASE) and 2 or 1 end
emu.addMemoryCallback(function() local p = phaseIdx(); counts.pad[p] = counts.pad[p] + 1 end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function() local p = phaseIdx(); counts.oam[p] = counts.oam[p] + 1 end, emu.callbackType.exec, 0x81C36A, 0x81C36A, emu.cpuType.snes, emu.memType.snesMemory)

local pcs = {}
local candidates = {}
local readers, readerCount = {}, 0
emu.addEventCallback(function()
  if FRAME > PRESS + 20 and FRAME < RELEASE then
    local s = emu.getState()
    local pc = string.format("$%02X%04X", s["cpu.k"], s["cpu.pc"])
    pcs[pc] = (pcs[pc] or 0) + 1
  end
  if FRAME == PRESS - 10 then snaps[1] = snap(); shot("play") end
  if FRAME == PRESS + 60 then snaps[2] = snap(); shot("paused") end
  if FRAME == PRESS + 200 then snaps[3] = snap() end
  if FRAME == RELEASE + 100 then
    snaps[4] = snap()
    for a = 0, 0x1FFFF do
      local p1, q1, q2, p2 = snaps[1][a], snaps[2][a], snaps[3][a], snaps[4][a]
      if p1 == p2 and q1 == q2 and q1 ~= p1 then candidates[#candidates + 1] = a end
    end
    for i, a in ipairs(candidates) do
      if i <= 24 then print(string.format("PAUSE_FLAG $%06X play=$%02X paused=$%02X", 0x7E0000 + a, snaps[1][a], snaps[2][a])) end
    end
    print("PAUSE_FLAG total=" .. #candidates)
  end
  if FRAME == END_AT then
    local list = {}
    for pc, n in pairs(pcs) do list[#list + 1] = { pc, n } end
    table.sort(list, function(x, y) return x[2] > y[2] end)
    for i = 1, math.min(8, #list) do print(string.format("PC %s frames=%d", list[i][1], list[i][2])) end
    print(string.format("NMI pad play=%d paused=%d | oam play=%d paused=%d", counts.pad[1], counts.pad[2], counts.oam[1], counts.oam[2]))
    shot("after")
  end
  if FRAME >= END_AT + 8 then emu.stop(0) end
end, emu.eventType.endFrame)
