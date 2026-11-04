-- RESEARCH sweep (slow, ~10 min): the original long single-run sweep, kept for its investigation modes
-- (--define DEBUG_STAGE, ANALYZE, OAM_TIMING, OAM_SOURCES, COLORMATH, CGADSUB_STAGE, WRAM_SCAN).
-- For regression use the fast parallel sweep: npm run sweep:all (tools/mesen/sweep.ts).
-- Mesen 2 (2.2.1) headless full-game sweep of the runtime palette patch.
-- From roms/states/level1-start.mss: for each stage reached with the debug stage skip ($1EC9 bit0 + R,
-- emulator RAM only), Mr. Nutz runs an action cycle with every button except L/R/Select, pauses once,
-- and the script checks every gameplay frame that CGRAM shows the selection in the slot the scene table
-- assigns to the Nutz palette. Lives (address unknown;
-- see RELOAD_EVERY) are restored by per-stage checkpoints so the sweep never reaches game over.
-- The selection is written straight to the hook state (fur 2, outfit 3); the shortcuts themselves are
-- covered by verify-runtime.lua. Ends with a soft reset to observe persistence.
-- Run: npm run sweep:all
local function unhex(h) return (h:gsub("..", function(c) return string.char(tonumber(c, 16)) end)) end
local function hex(v, n) return string.format("%0" .. n .. "X", v) end
local function w8(a) return emu.read(a, emu.memType.snesWorkRam, false) end
local function w16(a) return emu.read16(a, emu.memType.snesWorkRam, false) end
local function cg(e) return emu.read16(e * 2, emu.memType.snesCgRam, false) end
local function rom8(a) return emu.read(a, emu.memType.snesMemory, false) end
local function rom16(a) return emu.read16(a, emu.memType.snesMemory, false) end

local STAGE_FRAMES, STAGES = 1500, 70
local FUR_SEL, OUTFIT_SEL = 2, 3
local LOST_AFTER = 30 -- consecutive gameplay frames with Mr. Nutz not in his private colours before an event
local RESET_FRAMES = 2600

local frame, loaded, stage = -1, false, 0
local selectedOnce = false
local lastHook = -10
local phaseReset, resetAt = false, nil

emu.addMemoryCallback(function()
  if loaded then return end
  loaded = true
  print("LOAD ok=" .. tostring(emu.loadSavestate(unhex(STATE_HEX))))
  frame = 0
end, emu.callbackType.exec, 0x0080B5, 0x0080B5, emu.cpuType.snes, emu.memType.snesMemory) -- reset vector: first instruction; a full-range exec callback slows the run ~100x
-- Checkpoints instead of a lives cheat: a savestate taken at the first gameplay frame of each stage is
-- reloaded every RELOAD_EVERY frames, restoring lives so the sweep never reaches game over.
-- Save/load must run inside an exec callback, so it happens at the hook entry (gameplay frames only).
local RELOAD_EVERY = 360
local checkpoint, checkpointStage, pendingReload = nil, -1, false
emu.addMemoryCallback(function()
  lastHook = frame
  if phaseReset then return end
  local s = frame % STAGE_FRAMES
  if checkpointStage ~= stage and s >= 400 and s < 700 then -- after the stage intro/iris transition
    checkpoint = emu.createSavestate(); checkpointStage = stage
  elseif pendingReload and checkpointStage == stage and checkpoint then
    pendingReload = false
    emu.loadSavestate(checkpoint)
  end
end, emu.callbackType.exec, 0xA08000, 0xA08000, emu.cpuType.snes, emu.memType.snesMemory)

-- Action cycle (240 frames) after s=200 of each stage; Start pressed twice (pause/unpause) late in the stage.
local cycle = {
  { 0, 60, { right = true } }, { 60, 64, { right = true, b = true } }, { 64, 90, { right = true } },
  { 90, 94, { y = true } }, { 100, 104, { x = true } }, { 110, 114, { a = true } },
  { 120, 160, { down = true } }, { 160, 180, { up = true } }, { 180, 220, { left = true } },
  { 220, 224, { b = true } }, { 224, 240, { right = true, y = true } },
}
emu.addEventCallback(function()
  if frame < 0 then return end
  if phaseReset then
    local r = frame - resetAt
    if r % 200 >= 100 and r % 200 < 105 then emu.setInput({ start = true }, 0) end
    if r % 200 >= 150 and r % 200 < 155 then emu.setInput({ a = true }, 0) end
    return
  end
  local s = frame % STAGE_FRAMES
  if s >= 30 and s < 34 and frame > 0 then emu.setInput({ r = true }, 0); return end
  if s >= 1300 and s < 1304 then emu.setInput({ start = true }, 0); return end
  if s >= 1360 and s < 1364 then emu.setInput({ start = true }, 0); return end
  if s >= 200 and s < 1290 then
    local c = (s - 200) % 240
    for _, st in ipairs(cycle) do
      if c >= st[1] and c < st[2] then emu.setInput(st[3], 0); return end
    end
  end
end, emu.eventType.inputPolled)

local function shot(tag)
  local png = emu.takeScreenshot()
  print("SHOT " .. tag .. " " .. (png:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)))
end
local function palette()
  local p = {}
  for e = 0xC0, 0xCF do p[#p + 1] = hex(cg(e), 4) end
  return table.concat(p, " ")
end
-- Selected colours: outfit entry 6 and fur entry 15 of the private slot (tables of src/runtime.ts).
local function expected()
  local furOff = rom8(0xA09070 + w8(0x1BE02))
  return rom16(0xA09080 + w8(0x1BE03) * 8), rom16(0xA09000 + furOff + 8)
end
local function nutzSlot()
  local ptr = (w8(0x0560) << 16) | w16(0x055E)
  for k = 0, 7 do
    if rom16(ptr + k * 4) == 0x9CC0 and rom8(ptr + k * 4 + 2) == 0x85 then return 0x80 + k * 16 end
  end
  return nil
end

local st -- per-stage stats
local function newStage()
  st = { noSlot = 0, gameplay = 0, nutzFrames = 0, ok = 0, lostRun = 0, lostMax = 0, sharedChanged = 0, foreignOnX = 0,
    reselect = 0, lostShot = false, sharedShot = false, foreignShot = false }
end
local function endStage()
  print(string.format("STAGE %02d gameplay=%d nutzFrames=%d ok=%d lostMax=%d sharedChanged=%d foreignOnX=%d noSlot=%d reselect=%d S=%s X=%s",
    stage, st.gameplay, st.nutzFrames, st.ok, st.lostMax, st.sharedChanged, st.foreignOnX, st.noSlot, st.reselect,
    tostring(st.S), tostring(st.X)))
end
newStage()
local pendingShot = {}

emu.addEventCallback(function()
  if frame < 0 then return end
  frame = frame + 1
  for k, tag in pairs(pendingShot) do if frame >= k then shot(tag); pendingShot[k] = nil end end

  if phaseReset then
    local r = frame - resetAt
    if r == 1 then print("RESET done idx=" .. w8(0x1BE02) .. "/" .. w8(0x1BE03) .. " magic=$" .. hex(w16(0x1BE00), 4)) end
    if r % 300 == 0 then
      local X = w8(0x1BE06)
      local eOut, eFur = expected()
      print("AFTERRESET r=" .. r .. " 01DC=$" .. hex(w16(0x01DC), 4) .. " idx=" .. w8(0x1BE02) .. "/" .. w8(0x1BE03)
        .. " magic=$" .. hex(w16(0x1BE00), 4) .. " X=" .. X
        .. " xCustom=" .. tostring(X < 8 and cg(0x80 + X * 16 + 6) == eOut and cg(0x80 + X * 16 + 15) == eFur))
      emu.takeScreenshot(); pendingShot[frame + 4] = "reset-" .. string.format("%04d", r)
    end
    if r >= RESET_FRAMES then print("DONE"); emu.stop(0) end
    return
  end

  local s = frame % STAGE_FRAMES
  if s == 0 then endStage(); stage = stage + 1; newStage(); pendingReload = false end
  if s > 400 and s < 1200 and (s - 400) % RELOAD_EVERY == 0 then pendingReload = true end -- s=760, 1120; never near the pause at 1300
  if s == 20 then emu.write(0x1EC9, w8(0x1EC9) | 0x01, emu.memType.snesWorkRam) end
  for _, at in ipairs({ 300, 600, 900, 1200, 1340 }) do
    if s == at then emu.takeScreenshot(); pendingShot[frame + 4] = string.format("s%02d-%04d", stage, at) end
  end

  local gameplay = w16(0x01DC) == 0x835B and lastHook >= frame - 1 -- hook runs in NMI after endFrame
  if gameplay then
    st.gameplay = st.gameplay + 1
    if w16(0x1BE00) == 0x5A4E and w8(0x1BE02) == 0 and w8(0x1BE03) == 0 then
      -- Selected once at the start; any later return to 0/0 means the game wiped the state: a failure.
      if selectedOnce then
        st.reselect = st.reselect + 1
        print("SELECTION_LOST stage=" .. stage .. " s=" .. s)
      else
        print("SELECT stage=" .. stage .. " s=" .. s)
      end
      selectedOnce = true
      emu.write(0x1BE02, FUR_SEL, emu.memType.snesWorkRam)
      emu.write(0x1BE03, OUTFIT_SEL, emu.memType.snesWorkRam)
    end
    local base = nutzSlot()
    if not base then
      st.noSlot = st.noSlot + 1
    else
      -- 1. The Nutz slot S must always hold the untouched ROM palette (objects sharing it stay original).
      for e = 0, 15 do
        if cg(base + e) ~= rom16(0x859CC0 + e * 2) then
          st.sharedChanged = st.sharedChanged + 1
          if not st.sharedShot then
            st.sharedShot = true
            print("SHARED_CHANGED stage=" .. stage .. " s=" .. s .. " entry=" .. e .. " pal=" .. palette())
            emu.takeScreenshot(); pendingShot[frame + 4] = string.format("s%02d-shared", stage)
          end
          break
        end
      end
      -- 2. Mr. Nutz sprites (tile < $50, name table 0, palette S or X) must use X holding the selection.
      -- 3. No other visible sprite may use X while X holds the selection.
      local S = (base - 0x80) // 16
      local X = w8(0x1BE06)
      st.S, st.X = S, X
      local eOut, eFur = expected()
      local xCustom = X < 8 and cg(0x80 + X * 16 + 6) == eOut and cg(0x80 + X * 16 + 15) == eFur
      local nutz, nutzOk, foreign = 0, true, 0
      for i = 0, 127 do
        if emu.read(i * 4 + 1, emu.memType.snesSpriteRam, false) < 224 then
          local attr = emu.read(i * 4 + 3, emu.memType.snesSpriteRam, false)
          local pal = (attr >> 1) & 7
          local tile = emu.read(i * 4 + 2, emu.memType.snesSpriteRam, false) | ((attr & 1) << 8)
          if tile < 0x50 and (pal == S or pal == X) then
            nutz = nutz + 1
            if not (pal == X and xCustom) then nutzOk = false end
          elseif pal == X and xCustom then
            foreign = foreign + 1
          end
        end
      end
      if foreign > 0 then
        st.foreignOnX = st.foreignOnX + 1
        if not st.foreignShot then
          st.foreignShot = true
          print("FOREIGN_ON_X stage=" .. stage .. " s=" .. s .. " X=" .. X .. " sprites=" .. foreign)
          emu.takeScreenshot(); pendingShot[frame + 4] = string.format("s%02d-foreignx", stage)
        end
      end
      if nutz > 0 then
        st.nutzFrames = st.nutzFrames + 1
        if nutzOk then
          st.ok = st.ok + 1; st.lostRun = 0
        else
          st.lostRun = st.lostRun + 1
          if st.lostRun > st.lostMax then st.lostMax = st.lostRun end
          if st.lostRun == LOST_AFTER and not st.lostShot then
            st.lostShot = true
            print("LOST stage=" .. stage .. " s=" .. s .. " S=" .. S .. " X=" .. X .. " xCustom=" .. tostring(xCustom) .. " pal=" .. palette())
            emu.takeScreenshot(); pendingShot[frame + 4] = string.format("s%02d-lost", stage)
          end
        end
      end
    end
  end

  if frame >= STAGE_FRAMES * STAGES then
    endStage()
    print("RESET start idx=" .. w8(0x1BE02) .. "/" .. w8(0x1BE03))
    phaseReset = true
    resetAt = frame
    emu.reset()
  end
end, emu.eventType.endFrame)

-- Debug mode (--define DEBUG_STAGE=n): log every CGRAM DMA during stage n, then dump OAM and sprite
-- palettes at s=600 and stop.
if DEBUG_STAGE then
  local oamSeen = false
  local function onDma(address, value)
    if stage ~= DEBUG_STAGE or value == 0 then return end
    local s = emu.getState()
    for ch = 0, 7 do
      if (value & (1 << ch)) ~= 0 and rom8(0x4301 + ch * 0x10) == 0x04 and not oamSeen then
        oamSeen = true
        print("DBGOAMDMA s=" .. (frame % STAGE_FRAMES) .. " pc=" .. hex(s["cpu.k"], 2) .. ":" .. hex(s["cpu.pc"], 4)
          .. " src=$" .. hex(rom8(0x4304 + ch * 0x10), 2) .. ":" .. hex(rom16(0x4302 + ch * 0x10), 4)
          .. " size=$" .. hex(rom16(0x4305 + ch * 0x10), 4) .. " mode=$" .. hex(rom8(0x4300 + ch * 0x10), 2))
      end
      if (value & (1 << ch)) ~= 0 and rom8(0x4301 + ch * 0x10) == 0x22 then
        print("DBGDMA s=" .. (frame % STAGE_FRAMES) .. " pc=" .. hex(s["cpu.k"], 2) .. ":" .. hex(s["cpu.pc"], 4)
          .. " src=$" .. hex(rom8(0x4304 + ch * 0x10), 2) .. ":" .. hex(rom16(0x4302 + ch * 0x10), 4)
          .. " size=$" .. hex(rom16(0x4305 + ch * 0x10), 4) .. " cgramAddr=$" .. hex(s["ppu.cgramAddress"] or 0, 3)
          .. " 055E=$" .. hex(w16(0x0560), 2) .. ":" .. hex(w16(0x055E), 4))
      end
    end
  end
  for _, bank in ipairs({ 0x00, 0x80 }) do
    emu.addMemoryCallback(onDma, emu.callbackType.write, bank * 0x10000 + 0x420B, bank * 0x10000 + 0x420B, emu.cpuType.snes, emu.memType.snesMemory)
  end
  emu.addEventCallback(function()
    if stage ~= DEBUG_STAGE or frame % STAGE_FRAMES ~= 600 then return end
    for i = 0, 127 do
      local y = emu.read(i * 4 + 1, emu.memType.snesSpriteRam, false)
      if y < 224 then
        local attr = emu.read(i * 4 + 3, emu.memType.snesSpriteRam, false)
        print(string.format("DBGOAM #%03d x=%3d y=%3d tile=$%02X pal=%d attr=$%02X", i, emu.read(i * 4, emu.memType.snesSpriteRam, false), y,
          emu.read(i * 4 + 2, emu.memType.snesSpriteRam, false), (attr >> 1) & 7, attr))
      end
    end
    for p = 0, 7 do
      local t = {}
      for e = 0, 15 do t[#t + 1] = hex(cg(0x80 + p * 16 + e), 4) end
      print("DBGPAL obj" .. p .. " $" .. hex(0x80 + p * 16, 2) .. " " .. table.concat(t, " "))
    end
    emu.stop(0)
  end, emu.eventType.endFrame)
end

-- WRAM scan mode (--define WRAM_SCAN=1): access counters are reset right after the savestate load and
-- dumped as unused ranges (no read and no write, >= 16 bytes) before and after the soft reset phase.
-- The hook's own state block shows up as used; candidates must lie elsewhere.
if WRAM_SCAN then
  local function dumpUnused(tag)
    local reads = emu.getAccessCounters(emu.memType.snesWorkRam, emu.counterType.readCount)
    local writes = emu.getAccessCounters(emu.memType.snesWorkRam, emu.counterType.writeCount)
    local size = emu.getMemorySize(emu.memType.snesWorkRam)
    local start, total = nil, 0
    for a = 0, size do
      local unused = a < size and (reads[a] or 0) == 0 and (writes[a] or 0) == 0
      if unused and not start then start = a end
      if not unused and start then
        if a - start >= 16 then
          print(string.format("UNUSED %s $%06X..$%06X len=%d", tag, 0x7E0000 + start, 0x7E0000 + a - 1, a - start))
          total = total + a - start
        end
        start = nil
      end
    end
    print("UNUSED " .. tag .. " total=" .. total)
  end
  local resetDone, dumped = false, false
  emu.addEventCallback(function()
    if frame == 2 and not resetDone then resetDone = true; emu.resetAccessCounters() end
    if phaseReset and not dumped then dumped = true; dumpUnused("game") end
    if phaseReset and frame - resetAt == RESET_FRAMES - 1 then dumpUnused("game+reset") end
  end, emu.eventType.endFrame)
end

-- Analysis mode (--define ANALYZE=1): per stage, which sprite palettes are referenced by visible OAM
-- entries, which entries share the Nutz slot, and whether "tile < $50 on name table 0" identifies Mr. Nutz.
if ANALYZE then
  local a
  local function resetA() a = { used = {}, nutzTiles = {}, sharedFrames = 0, sharedTiles = {}, frames = 0, maxNutz = 0, dupes = "" } end
  resetA()
  emu.addEventCallback(function()
    if frame < 0 or phaseReset then return end
    local s = frame % STAGE_FRAMES
    if s == 0 and frame > 0 then
      local used, nt, sh = {}, {}, {}
      for p = 0, 7 do if a.used[p] then used[#used + 1] = p end end
      for t in pairs(a.nutzTiles) do nt[#nt + 1] = hex(t, 3) end
      for t in pairs(a.sharedTiles) do sh[#sh + 1] = hex(t, 3) end
      table.sort(nt); table.sort(sh)
      print(string.format("ANALYZE stage=%02d frames=%d usedPals=%s sharedFrames=%d maxNutzSprites=%d dupes=%s nutzTiles=%s sharedTiles=%s",
        stage - 1, a.frames, table.concat(used, ","), a.sharedFrames, a.maxNutz, a.dupes, table.concat(nt, ","), table.concat(sh, ",")))
      resetA()
    end
    if not (w16(0x01DC) == 0x835B and lastHook >= frame - 1) then return end
    local base = nutzSlot()
    if not base then return end
    local slot = (base - 0x80) // 16
    a.frames = a.frames + 1
    if a.dupes == "" then
      local ptr = (w8(0x0560) << 16) | w16(0x055E)
      local seen, d = {}, {}
      for k = 0, 7 do
        local key = rom16(ptr + k * 4) .. ":" .. rom8(ptr + k * 4 + 2)
        if seen[key] then d[#d + 1] = seen[key] .. "=" .. k else seen[key] = k end
      end
      a.dupes = #d > 0 and table.concat(d, ";") or "none"
    end
    local shared, nutz = false, 0
    for i = 0, 127 do
      local y = emu.read(i * 4 + 1, emu.memType.snesSpriteRam, false)
      if y < 224 then
        local attr = emu.read(i * 4 + 3, emu.memType.snesSpriteRam, false)
        local pal = (attr >> 1) & 7
        local tile = emu.read(i * 4 + 2, emu.memType.snesSpriteRam, false) | ((attr & 1) << 8)
        a.used[pal] = true
        if pal == slot then
          if tile < 0x50 then nutz = nutz + 1; a.nutzTiles[tile] = true
          else shared = true; a.sharedTiles[tile] = true end
        end
      end
    end
    if nutz > a.maxNutz then a.maxNutz = nutz end
    if shared then a.sharedFrames = a.sharedFrames + 1 end
  end, emu.eventType.endFrame)
end

-- OAM DMA timing mode (--define OAM_TIMING=1): scanline at entry ($81C367) and at the final RTL of the
-- OAM upload wrapper, the byte count $0024, and the order relative to the palette hook ($81828A).
if OAM_TIMING then
  local entry, stats = nil, { n = 0, maxEntry = -1, minEntry = 999, maxExit = -1, maxCount = 0, beforeHook = 0, afterHook = 0, lagExit = 0 }
  local hookThisFrame = -1
  emu.addMemoryCallback(function() hookThisFrame = frame end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function()
    if phaseReset then return end
    local s = emu.getState()
    entry = s["ppu.scanline"]
    local count = w16(0x0024)
    stats.n = stats.n + 1
    if entry > stats.maxEntry then stats.maxEntry = entry end
    if entry < stats.minEntry then stats.minEntry = entry end
    if count > stats.maxCount then stats.maxCount = count end
    if hookThisFrame == frame then stats.afterHook = stats.afterHook + 1 else stats.beforeHook = stats.beforeHook + 1 end
  end, emu.callbackType.exec, 0x81C367, 0x81C367, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addMemoryCallback(function()
    if phaseReset or not entry then return end
    local sl = emu.getState()["ppu.scanline"]
    if sl < 225 and sl > stats.maxExit then stats.maxExit = sl end
    if sl < 225 then stats.lagExit = stats.lagExit + 1 end
    entry = nil
  end, emu.callbackType.exec, 0x81C366, 0x81C366, emu.cpuType.snes, emu.memType.snesMemory)
  emu.addEventCallback(function()
    if phaseReset or frame % STAGE_FRAMES ~= STAGE_FRAMES - 1 then return end
    print(string.format("OAMT stage=%02d calls=%d entryScanline=%d..%d exitInActiveDisplay=%d (max line %d) maxBytes=%d afterHook=%d beforeHook=%d",
      stage, stats.n, stats.minEntry, stats.maxEntry, stats.lagExit, stats.maxExit, stats.maxCount, stats.afterHook, stats.beforeHook))
    stats = { n = 0, maxEntry = -1, minEntry = 999, maxExit = -1, maxCount = 0, beforeHook = 0, afterHook = 0, lagExit = 0 }
  end, emu.eventType.endFrame)
end

-- OAM source mode (--define OAM_SOURCES=n): during stage n log every distinct DMA to OAM ($2104) and, at
-- s=600, the OAM entries using each palette with their index, plus the $0024 byte count.
if OAM_SOURCES then
  local seen = {}
  local function onDma(address, value)
    if stage ~= OAM_SOURCES or value == 0 then return end
    local s = emu.getState()
    for ch = 0, 7 do
      if (value & (1 << ch)) ~= 0 and rom8(0x4301 + ch * 0x10) == 0x04 then
        local key = hex(s["cpu.k"], 2) .. ":" .. hex(s["cpu.pc"], 4) .. " src=$" .. hex(rom8(0x4304 + ch * 0x10), 2) .. ":"
          .. hex(rom16(0x4302 + ch * 0x10), 4) .. " size=$" .. hex(rom16(0x4305 + ch * 0x10), 4)
        if not seen[key] then
          seen[key] = true
          print("OAMSRC s=" .. (frame % STAGE_FRAMES) .. " pc=" .. key .. " oamaddr=$" .. hex(emu.read16(0x2102, emu.memType.snesMemory, false), 4)
            .. " scanline=" .. tostring(s["ppu.scanline"]))
        end
      end
    end
  end
  for _, bank in ipairs({ 0x00, 0x80 }) do
    emu.addMemoryCallback(onDma, emu.callbackType.write, bank * 0x10000 + 0x420B, bank * 0x10000 + 0x420B, emu.cpuType.snes, emu.memType.snesMemory)
  end
  emu.addEventCallback(function()
    if stage ~= OAM_SOURCES or frame % STAGE_FRAMES ~= 600 then return end
    print("OAMCOUNT $0024=" .. w16(0x0024) .. " customSlot=" .. w8(0x1BE06))
    local byPal = {}
    for i = 0, 127 do
      if emu.read(i * 4 + 1, emu.memType.snesSpriteRam, false) < 224 then
        local attr = emu.read(i * 4 + 3, emu.memType.snesSpriteRam, false)
        local pal = (attr >> 1) & 7
        byPal[pal] = (byPal[pal] or "") .. " #" .. i .. ":" .. hex(emu.read(i * 4 + 2, emu.memType.snesSpriteRam, false) | ((attr & 1) << 8), 3)
      end
    end
    for p = 0, 7 do if byPal[p] then print("OAMPAL p" .. p .. byPal[p]) end end
    emu.takeScreenshot(); pendingShot[frame + 4] = "oamsrc"
  end, emu.eventType.endFrame)
end

-- Colour math mode (--define COLORMATH=1): per stage, OR of $2131 layer enables seen at endFrame in gameplay
-- (bit 4 = OBJ palettes 4-7). Tells whether palettes 0-3 and 4-7 render alike in a scene.
if COLORMATH then
  local acc, n = 0, 0
  emu.addEventCallback(function()
    if frame < 0 or phaseReset then return end
    if frame % STAGE_FRAMES == 0 and frame > 0 then
      print(string.format("COLORMATH stage=%02d frames=%d enabledOr=$%02X objMath=%s", stage - 1, n, acc, tostring((acc & 0x10) ~= 0)))
      acc, n = 0, 0
    end
    if w16(0x01DC) == 0x835B and lastHook >= frame - 1 then
      acc = acc | (emu.getState()["ppu.colorMathEnabled"] or 0)
      n = n + 1
    end
  end, emu.eventType.endFrame)
end

-- CGADSUB writers (--define CGADSUB_STAGE=n): distinct (PC, value) writes to $2131 during stage n, with the
-- frame phase, plus HDMA channels aimed at $2131.
if CGADSUB_STAGE then
  local seen = {}
  local function onWrite(address, value)
    if stage ~= CGADSUB_STAGE then return end
    local s = emu.getState()
    local key = hex(s["cpu.k"], 2) .. ":" .. hex(s["cpu.pc"], 4) .. "=" .. hex(value, 2)
    if not seen[key] then
      seen[key] = true
      print("CGADSUB s=" .. (frame % STAGE_FRAMES) .. " pc=" .. key .. " scanline=" .. tostring(s["ppu.scanline"])
        .. " A=$" .. hex(s["cpu.a"], 4) .. " DBR=$" .. hex(s["cpu.dbr"], 2) .. " D=$" .. hex(s["cpu.d"], 4))
    end
  end
  for _, bank in ipairs({ 0x00, 0x80 }) do
    emu.addMemoryCallback(onWrite, emu.callbackType.write, bank * 0x10000 + 0x2131, bank * 0x10000 + 0x2131, emu.cpuType.snes, emu.memType.snesMemory)
  end
end
