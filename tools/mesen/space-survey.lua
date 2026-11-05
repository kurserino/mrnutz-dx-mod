-- Expansion budget survey (pause menu research, run on the ORIGINAL ROM from a stage state).
-- 1. Resets Mesen's access counters after the state loads, plays an action cycle, pauses for PAUSE_FRAMES with Start,
--    unpauses and plays again.
-- 2. Prints which blocks were read or written ("1") per memory: WRAM in 64-byte blocks (2048 chars), VRAM in
--    256-byte blocks (256 chars), CGRAM in 32-byte palettes (16 chars), OAM in 32-byte blocks (17 chars).
--    VRAM reads by the PPU itself are not counted: only CPU/DMA writes and CPU reads.
-- 3. Prints the PPU layout (BG mode, per-layer tilemap/CHR base, OBJ base) in gameplay and while paused, and what
--    keeps running during the pause (NMI joypad mirror at $81:828A, our hook site).
-- Aggregated by tools/mesen/space-survey.ts.
local PAUSE_AT, PAUSE_FRAMES, END_AT = 300, 300, 900
loadStateOnBoot(function()
  ww(0x1EC9, w8(0x1EC9) & 0xFE)
  for _, m in ipairs({ emu.memType.snesWorkRam, emu.memType.snesVideoRam, emu.memType.snesCgRam, emu.memType.snesSpriteRam }) do
    pcall(function() emu.resetAccessCounters(m) end)
  end
  pcall(function() emu.resetAccessCounters() end)
end)

local cycle = {
  { 0, 60, { right = true } }, { 60, 64, { right = true, b = true } }, { 64, 90, { right = true } },
  { 90, 94, { y = true } }, { 100, 104, { x = true } }, { 110, 114, { a = true } },
  { 120, 160, { down = true } }, { 160, 180, { up = true } }, { 180, 220, { left = true } },
  { 220, 224, { b = true } }, { 224, 240, { right = true, y = true } },
}
local steps = { { PAUSE_AT, PAUSE_AT + 4, { start = true } }, { PAUSE_AT + PAUSE_FRAMES, PAUSE_AT + PAUSE_FRAMES + 4, { start = true } } }
for c = 0, 3 do
  for _, s in ipairs(cycle) do
    local a, b = 10 + c * 240 + s[1], 10 + c * 240 + s[2]
    if b <= PAUSE_AT or a >= PAUSE_AT + PAUSE_FRAMES + 10 then steps[#steps + 1] = { a, b, s[3] } end
  end
end
playInputs(steps)

local siteRuns = { play = 0, pause = 0 }
emu.addMemoryCallback(function()
  if FRAME > PAUSE_AT + 30 and FRAME < PAUSE_AT + PAUSE_FRAMES then siteRuns.pause = siteRuns.pause + 1 else siteRuns.play = siteRuns.play + 1 end
end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)

local function layout(tag)
  local s = emu.getState()
  local t = { string.format("LAYOUT %s frame=%d mode=%d main=$%02X sub=$%02X bright=%d forcedBlank=%s obj=$%04X oamMode=%d $01DC=$%04X",
    tag, FRAME, s["ppu.bgMode"], s["ppu.mainScreenLayers"], s["ppu.subScreenLayers"], s["ppu.screenBrightness"],
    tostring(s["ppu.forcedBlank"]), s["ppu.oamBaseAddress"], s["ppu.oamMode"], w16(0x01DC)) }
  for i = 0, 3 do
    t[#t + 1] = string.format("bg%d map=$%04X chr=$%04X", i + 1, s["ppu.layers[" .. i .. "].tilemapAddress"], s["ppu.layers[" .. i .. "].chrAddress"])
  end
  print(table.concat(t, " "))
end

local function counters(memType)
  local function get(kind)
    local ok, r = pcall(function() return emu.getAccessCounters(memType, kind) end)
    if ok and type(r) == "table" then return r end
    ok, r = pcall(function() return emu.getAccessCounters(kind, memType) end)
    if ok and type(r) == "table" then return r end
    return nil
  end
  return get(emu.counterType.readCount), get(emu.counterType.writeCount)
end

local function bitmap(name, memType, size, block)
  local r, w = counters(memType)
  if not r or not w then print("MAP " .. name .. " unavailable"); return end
  local out = {}
  for b = 0, size // block - 1 do
    local touched = false
    for i = b * block, b * block + block - 1 do
      -- Lua arrays from Mesen are 0- or 1-based depending on the build: accept both.
      local rv, wv = r[i] or r[i + 1] or 0, w[i] or w[i + 1] or 0
      if rv > 0 or wv > 0 then touched = true; break end
    end
    out[#out + 1] = touched and "1" or "0"
  end
  print("MAP " .. name .. " block=" .. block .. " " .. table.concat(out))
end

-- VRAM references (what the PPU can show): every 8 frames, decode the BG1-BG3 tilemaps (32x32 or larger per the
-- layer size flags) and the visible OAM entries, and mark the tile bytes they point at, plus the tilemaps themselves.
-- Addresses from Mesen's PPU state are VRAM word addresses; the marks are byte addresses (x2).
local vref = {}
local function markRange(lo, len)
  for a = lo, lo + len - 1 do vref[a & 0xFFFF] = true end
end
local BPP = { [0] = { 2, 2, 2, 2 }, [1] = { 4, 4, 2, 0 }, [2] = { 4, 4, 0, 0 }, [3] = { 8, 4, 0, 0 } }
local function sampleVram()
  local s = emu.getState()
  local mode = s["ppu.bgMode"]
  local bpps = BPP[mode] or { 4, 4, 2, 0 }
  for i = 0, 2 do
    local bpp = bpps[i + 1]
    if bpp > 0 then
      local map = s["ppu.layers[" .. i .. "].tilemapAddress"] * 2
      local chr = s["ppu.layers[" .. i .. "].chrAddress"] * 2
      local w = s["ppu.layers[" .. i .. "].doubleWidth"] and 2 or 1
      local h = s["ppu.layers[" .. i .. "].doubleHeight"] and 2 or 1
      local mapBytes = 0x800 * w * h
      markRange(map, mapBytes)
      for o = 0, mapBytes - 2, 2 do
        local e = emu.read16((map + o) & 0xFFFF, emu.memType.snesVideoRam, false)
        local tile = e & 0x3FF
        markRange(chr + tile * 8 * bpp, 8 * bpp)
      end
    end
  end
  local objBase = s["ppu.oamBaseAddress"] * 2
  local objGap = (s["ppu.oamAddressOffset"] or 0x1000) * 2
  for i = 0, 127 do
    local y = oam(i, 1)
    if y < 224 or y >= 240 then
      local attr = oam(i, 3)
      local tile = oam(i, 2)
      local base = (attr & 1) == 1 and (objBase + objGap) or objBase
      -- Large sprites use up to 4x4 tiles in a 16-tile row layout: mark the full 64x64 footprint conservatively.
      for ty = 0, 3 do
        for tx = 0, 3 do
          local t = ((tile + tx) & 0x0F) | ((tile + ty * 16) & 0xF0)
          markRange(base + t * 32, 32)
        end
      end
    end
  end
end
emu.addEventCallback(function()
  if FRAME > 5 and FRAME % 8 == 0 then sampleVram() end
end, emu.eventType.endFrame)

local function vrefMap()
  local out = {}
  for b = 0, 255 do
    local used = false
    for a = b * 256, b * 256 + 255 do if vref[a] then used = true; break end end
    out[#out + 1] = used and "1" or "0"
  end
  print("MAP vref block=256 " .. table.concat(out))
end

emu.addEventCallback(function()
  if FRAME == END_AT then vrefMap() end
  if FRAME == PAUSE_AT - 10 then layout("play"); shot("play") end
  if FRAME == PAUSE_AT + 150 then layout("pause"); shot("pause") end
  if FRAME == END_AT then
    bitmap("wram", emu.memType.snesWorkRam, 0x20000, 64)
    bitmap("vram", emu.memType.snesVideoRam, 0x10000, 256)
    bitmap("cgram", emu.memType.snesCgRam, 0x200, 32)
    bitmap("oam", emu.memType.snesSpriteRam, 0x220, 32)
    print(string.format("RESULT siteRunsPlay=%d siteRunsPause=%d", siteRuns.play, siteRuns.pause))
  end
  if FRAME >= END_AT + 8 then emu.stop(0) end
end, emu.eventType.endFrame)
