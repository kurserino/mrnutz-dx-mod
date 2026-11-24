-- Pause menu prototype check (pause-menu tasks 1.3-1.5), on the patched ROM from a stage state.
--   1. Start at PRESS. At the end of the first paused frame (before the menu changes anything), snapshot VRAM, CGRAM
--      and OAM.
--   2. Log the menu state and the scanline at which pause_hook returns ($80:83BC) for every step.
--   3. Screenshot the open menu, press Start again, and at the end of the frame the game resumes, compare VRAM,
--      CGRAM and OAM with the snapshot: DIFF lines and a RESULT with the counts.
-- Defines: PRESS (default 120).
local PRESS_ = PRESS or 120
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)

local MENU_STATE = 0x1BE40 -- $7F:BE40 as a WRAM offset
local snap, paused, closePressAt, result = nil, false, nil, nil
local stepLines = {}
emu.addMemoryCallback(function()
  local st = w8(MENU_STATE)
  local line = emu.getState()["ppu.scanline"]
  local key = tostring(st)
  if not stepLines[key] or line > stepLines[key] then stepLines[key] = line end
end, emu.callbackType.exec, 0x8083BC, 0x8083BC, emu.cpuType.snes, emu.memType.snesMemory)

local function dump(memType, size)
  local t = {}
  for a = 0, size - 1 do t[a] = emu.read(a, memType, false) end
  return t
end
local function snapshot()
  return { vram = dump(emu.memType.snesVideoRam, 0x10000), cgram = dump(emu.memType.snesCgRam, 0x200), oam = dump(emu.memType.snesSpriteRam, 0x220) }
end
local function compare(a, b, name, size)
  local n, first = 0, nil
  for i = 0, size - 1 do
    if a[i] ~= b[i] then n = n + 1; first = first or i end
  end
  if n > 0 then print(string.format("DIFF %s bytes=%d first=$%04X", name, n, first)) end
  return n
end

emu.addEventCallback(function()
  local input = {}
  if FRAME >= PRESS_ and FRAME < PRESS_ + 4 then input = { start = true } end
  if closePressAt and FRAME >= closePressAt and FRAME < closePressAt + 4 then input = { start = true } end
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  local p = w8(0x13B4)
  if not paused and p ~= 0 and FRAME >= PRESS_ then
    paused = true
    snap = snapshot()
    print(string.format("PAUSED frame=%d menuState=%d", FRAME, w8(MENU_STATE)))
  elseif paused and not closePressAt and FRAME > PRESS_ + 40 then
    shot("menu")
    print(string.format("OPEN frame=%d menuState=%d", FRAME, w8(MENU_STATE)))
    closePressAt = FRAME + 6
  elseif paused and closePressAt and p == 0 and not result then
    local now = snapshot()
    local v = compare(snap.vram, now.vram, "vram", 0x10000)
    local c = compare(snap.cgram, now.cgram, "cgram", 0x200)
    local o = compare(snap.oam, now.oam, "oam", 0x220)
    local steps = {}
    for k, l in pairs(stepLines) do steps[#steps + 1] = k .. ":" .. l end
    table.sort(steps)
    result = string.format("RESULT resumedFrame=%d vramDiff=%d cgramDiff=%d oamDiff=%d hookEndLine(state:max)=%s", FRAME, v, c, o, table.concat(steps, ","))
    print(result)
  end
  if result and FRAME == closePressAt + 120 then shot("after") end
  if (result and FRAME >= closePressAt + 128) or FRAME > PRESS_ + 2000 then
    if not result then print("RESULT no-resume menuState=" .. w8(MENU_STATE) .. " paused=" .. w8(0x13B4)) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
