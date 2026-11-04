-- Mesen 2 (2.2.1) headless tracer for the runtime-palette-switch evidence (E1-E4).
-- Run: Mesen.exe --testRunner <rom.sfc> trace-palette.lua   (see tools/mesen/run.ts)
-- Needs no Lua I/O permission: results and screenshots ("SHOT <tag> <hex png>") go to stdout.
-- Notes verified on 2.2.1: snesCgRam write callbacks do NOT fire for DMA uploads, so CGRAM
-- uploads are traced through CPU writes to $420B/$2121/$2122 instead. Reported PCs point to the
-- byte after the opcode/operand fetch (i.e. the next instruction), not the instruction start.

local MAGENTA = 0x7C1F
local frame = 0

-- Timeline from power-on (frames). Reaches level 1 gameplay around frame 1615 with these inputs.
local inputs = {
  { 200, 205, { start = true } }, { 400, 405, { start = true } }, { 600, 605, { start = true } },
  { 800, 805, { start = true } }, { 1000, 1005, { start = true } }, { 1200, 1205, { start = true } },
  { 1400, 1405, { a = true } },
  { 1600, 1700, { right = true } },
  -- 1700-2050 idle: E4 per-entry sweep.
  { 2100, 2500, { right = true } }, { 2500, 2510, { b = true } }, { 2510, 2700, { right = true } },
  { 2700, 2760, { select = true, l = true } },
  { 2800, 2860, { select = true, r = true } },
  { 2900, 2960, { l = true } },
  { 3000, 3060, { r = true } },
}
local MAX_FRAMES = 3200
local SWEEP_START, SWEEP_STEP = 1720, 20 -- entries $C1..$CF
local PERSIST_FROM = 2080 -- write distinct markers to $C6-$C9/$CB-$CF and watch until the end

local function hex(v, n) return string.format("%0" .. n .. "X", v) end
local function st() return emu.getState() end
local function where(s) return hex(s["cpu.k"], 2) .. ":" .. hex(s["cpu.pc"], 4) end
local function rd(a) return emu.read(a, emu.memType.snesMemory, false) end
local function cg16(entry) return emu.read16(entry * 2, emu.memType.snesCgRam, false) end
local function setCg(entry, v) emu.write16(entry * 2, v, emu.memType.snesCgRam) end
local function wram8(a) return emu.read(a, emu.memType.snesWorkRam, false) end
local function wram16(a) return emu.read16(a, emu.memType.snesWorkRam, false) end

local function shot(tag)
  local png = emu.takeScreenshot()
  print("SHOT " .. tag .. " " .. (png:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)))
end
local function palette()
  local t = {}
  for e = 0xC0, 0xCF do t[#t + 1] = hex(cg16(e), 4) end
  return table.concat(t, " ")
end
local function ramLine(tag)
  print("RAM " .. tag .. " frame=" .. frame .. " 1A6F=$" .. hex(wram16(0x1A6F), 4) .. " 1EC9=$" .. hex(wram8(0x1EC9), 2)
    .. " 01DC=$" .. hex(wram16(0x01DC), 4) .. " 01F4=$" .. hex(wram8(0x01F4), 2) .. " 056D=$" .. hex(wram8(0x056D), 2)
    .. " 13B4=$" .. hex(wram8(0x13B4), 2))
end

-- E1: joypad reads, once per unique PC, with scanline to tell VBlank/NMI from main loop.
local padSeen = {}
local function onPadRead(address)
  local s = st()
  local key = where(s) .. "@" .. hex(address & 0xFFFF, 4)
  if not padSeen[key] then
    padSeen[key] = { n = 0 }
    print("PADREAD frame=" .. frame .. " pc=" .. where(s) .. " reg=$" .. hex(address & 0xFFFF, 4)
      .. " scanline=" .. tostring(s["ppu.scanline"]) .. " sp=$" .. hex(s["cpu.sp"], 4))
  end
  padSeen[key].n = padSeen[key].n + 1
end

-- E3: DMA/HDMA/direct CGRAM uploads.
local dmaSeen = {}
local function onDmaEnable(address, value)
  if value == 0 then return end
  local s = st()
  for ch = 0, 7 do
    if (value & (1 << ch)) ~= 0 then
      local base = 0x4300 + ch * 0x10
      if rd(base + 1) == 0x22 then
        local src = hex(rd(base + 4), 2) .. ":" .. hex(rd(base + 2) | (rd(base + 3) << 8), 4)
        local size = rd(base + 5) | (rd(base + 6) << 8)
        local cga = s["ppu.cgramAddress"]
        local kind = (address & 0xFFFF) == 0x420C and "HDMA" or "DMA"
        local key = kind .. where(s) .. src .. size
        if not dmaSeen[key] or (kind == "DMA" and frame > PERSIST_FROM - 400) then
          if not dmaSeen[key] then dmaSeen[key] = 0 end
          print(kind .. " frame=" .. frame .. " pc=" .. where(s) .. " ch=" .. ch .. " src=$" .. src .. " size=$" .. hex(size, 4)
            .. " cgramAddr=$" .. hex(cga or 0, 3) .. " scanline=" .. tostring(s["ppu.scanline"]))
        end
        dmaSeen[key] = dmaSeen[key] + 1
      end
    end
  end
end
local directSeen = {}
local function onCgReg(address, value)
  local cga = emu.getState()["ppu.cgramAddress"] or 0
  local reg = address & 0xFFFF
  -- Only accesses touching the character palette; HDMA backdrop writes (CGADD $00) are noise.
  if not ((reg == 0x2121 and value >= 0xC0 and value <= 0xCF) or (reg == 0x2122 and cga >= 0xC0 and cga <= 0xCF)) then return end
  local s = st()
  local key = where(s) .. hex(address & 0xFFFF, 4)
  if not directSeen[key] then
    directSeen[key] = true
    print("CGREG frame=" .. frame .. " pc=" .. where(s) .. " reg=$" .. hex(address & 0xFFFF, 4) .. " val=$" .. hex(value, 2)
      .. " cgramAddr=$" .. hex(s["ppu.cgramAddress"] or 0, 3))
  end
end
for _, bank in ipairs({ 0x00, 0x80 }) do
  local b = bank * 0x10000
  emu.addMemoryCallback(onPadRead, emu.callbackType.read, b + 0x4218, b + 0x4218, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(onDmaEnable, emu.callbackType.write, b + 0x420B, b + 0x420C, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(onCgReg, emu.callbackType.write, b + 0x2121, b + 0x2122, emu.cpuType.snes, emu.memType.snesMemory)
end

emu.addEventCallback(function()
  for _, step in ipairs(inputs) do
    if frame >= step[1] and frame < step[2] then emu.setInput(step[3], 0); return end
  end
end, emu.eventType.inputPolled)

-- Distinct markers per entry so a partial revert is visible.
local markers = {}
for i, e in ipairs({ 0xC6, 0xC7, 0xC8, 0xC9, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF }) do markers[e] = 0x7C00 + i end
local saved = nil

emu.addEventCallback(function()
  frame = frame + 1
  if frame == 1600 then print("PALETTE gameplay frame=" .. frame .. " " .. palette()); ramLine("gameplay") end

  -- E4 sweep: one entry magenta at a time, screenshot 2 frames later, then restore.
  local k = math.floor((frame - SWEEP_START) / SWEEP_STEP)
  local phase = (frame - SWEEP_START) % SWEEP_STEP
  if frame >= SWEEP_START and k >= 0 and k < 15 then
    local entry = 0xC1 + k
    if phase == 0 then saved = cg16(entry); setCg(entry, MAGENTA) end
    if phase == SWEEP_STEP - 4 then shot("sweep-" .. hex(entry, 2)) end -- takeScreenshot lags a few frames in --testRunner
    if phase == SWEEP_STEP - 1 then setCg(entry, saved) end
  end
  if frame == SWEEP_START - 2 then shot("sweep-base") end

  -- Persistence test.
  if frame == PERSIST_FROM then
    for e, v in pairs(markers) do setCg(e, v) end
    print("PERSIST start frame=" .. frame .. " " .. palette())
  end
  if frame > PERSIST_FROM then
    for e, v in pairs(markers) do
      if cg16(e) ~= v then
        print("PERSIST changed frame=" .. frame .. " entry=$" .. hex(e, 2) .. " now=$" .. hex(cg16(e), 4) .. " " .. palette())
        markers[e] = cg16(e)
      end
    end
  end

  if frame == 2690 or frame == 2790 or frame == 2890 or frame == 2990 or frame == 3090 then ramLine("pre") end
  if frame == 2700 + 30 or frame == 2800 + 30 or frame == 2900 + 30 or frame == 3000 + 30 then ramLine("held"); shot("input-" .. frame) end
  if frame == 2400 then shot("persist-2400") end

  if frame >= MAX_FRAMES then
    for key, e in pairs(padSeen) do print("PADREAD total " .. key .. " count=" .. e.n) end
    for key, n in pairs(dmaSeen) do print("CGDMA total " .. key .. " count=" .. n) end
    print("PALETTE final frame=" .. frame .. " " .. palette())
    emu.stop(0)
  end
end, emu.eventType.endFrame)
