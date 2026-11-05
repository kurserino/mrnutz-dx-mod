-- Shared helpers for the Mesen 2 (2.2.1) headless scripts. tools/mesen/run.ts prepends this file to every
-- script (Lua require needs Mesen's I/O permission, which stays off). Defines globals only; callbacks are
-- registered here just for the frame counter, the gameplay tracker and delayed screenshots.

function hex(v, n) return string.format("%0" .. n .. "X", v) end
function unhex(h) return (h:gsub("..", function(c) return string.char(tonumber(c, 16)) end)) end
function w8(a) return emu.read(a, emu.memType.snesWorkRam, false) end -- WRAM offset ($7E0000 = 0)
function w16(a) return emu.read16(a, emu.memType.snesWorkRam, false) end
function ww(a, v) emu.write(a, v, emu.memType.snesWorkRam) end
function cg(e) return emu.read16(e * 2, emu.memType.snesCgRam, false) end -- CGRAM colour index
function bus8(a) return emu.read(a, emu.memType.snesMemory, false) end -- CPU bus address
function bus16(a) return emu.read16(a, emu.memType.snesMemory, false) end
function oam(i, k) return emu.read(i * 4 + k, emu.memType.snesSpriteRam, false) end -- k: 0 x, 1 y, 2 tile, 3 attr

-- Frame counter (frames since power-on or since the savestate load) and gameplay tracker: the joypad mirror at
-- $81:828A runs once per gameplay NMI in the original and in the patched ROM (trace-hook-site.log).
FRAME = 0
local lastPadFrame = -10
emu.addMemoryCallback(function() lastPadFrame = FRAME end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
function inGameplay() return w16(0x01DC) == 0x835B and lastPadFrame >= FRAME - 1 end

-- Screenshots lag a few frames in --testRunner: shot(tag) flushes now and prints "SHOT <tag> <hex png>" 4 frames
-- later (tools/mesen/run.ts turns it into output/traces/<name>/<tag>.png).
local pendingShots = {}
function shot(tag)
  emu.takeScreenshot()
  pendingShots[#pendingShots + 1] = { at = FRAME + 4, tag = tag }
end
emu.addEventCallback(function()
  FRAME = FRAME + 1
  for i = #pendingShots, 1, -1 do
    local p = pendingShots[i]
    if FRAME >= p.at then
      local png = emu.takeScreenshot()
      print("SHOT " .. p.tag .. " " .. (png:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)))
      table.remove(pendingShots, i)
    end
  end
end, emu.eventType.endFrame)

-- Load STATE_HEX (injected by run.ts --state) at the reset vector, the first instruction after power-on.
-- loadSavestate must run inside an exec callback; a narrow one keeps Lua off every other instruction.
function loadStateOnBoot(onLoaded)
  if not STATE_HEX then error("this script needs --state <file.mss>") end
  local done = false
  emu.addMemoryCallback(function()
    if done then return end
    done = true
    print("LOAD ok=" .. tostring(emu.loadSavestate(unhex(STATE_HEX))))
    -- Stage states come from the original ROM (no hook magic in WRAM), so the hook's one-time init runs and loads
    -- the SRAM save record. Parallel runs share one .srm in Mesen's Saves folder: clear the record so every
    -- state-based check starts from the original colours (0/0). tools/mesen/power-cycle.ts tests the save itself.
    if emu.getMemorySize(emu.memType.snesSaveRam) > 0 then
      for i = 0x100, 0x107 do emu.write(i, 0, emu.memType.snesSaveRam) end
    end
    FRAME = 0
    if onLoaded then onLoaded() end
  end, emu.callbackType.exec, 0x0080B5, 0x0080B5, emu.cpuType.snes, emu.memType.snesMemory)
end

-- Inputs: steps = { {from, to, buttons}, ... } in FRAME units; first match wins.
function playInputs(steps)
  emu.addEventCallback(function()
    for _, s in ipairs(steps) do
      if FRAME >= s[1] and FRAME < s[2] then emu.setInput(s[3], 0); return end
    end
  end, emu.eventType.inputPolled)
end

-- Runtime patch model (src/runtime.ts). WRAM offsets of the hook state at $7FBE00.
NUTZ = {
  palette = 0x859CC0, magic = 0x1BE00, fur = 0x1BE02, outfit = 0x1BE03, customSlot = 0x1BE06,
  furTable = 0xA09000, furOffsets = 0xA09070, outfitTable = 0xA09080,
}

-- Palette (0-7) the scene table [$055E] assigns to $85:9CC0, or nil.
function nutzSlot()
  local ptr = (w8(0x0560) << 16) | w16(0x055E)
  for k = 0, 7 do
    if bus16(ptr + k * 4) == 0x9CC0 and bus8(ptr + k * 4 + 2) == 0x85 then return k end
  end
  return nil
end

-- Selected colours: outfit entry 6 and fur entry 15 of the private slot.
function expectedColours()
  local furOff = bus8(NUTZ.furOffsets + w8(NUTZ.fur))
  return bus16(NUTZ.outfitTable + w8(NUTZ.outfit) * 8), bus16(NUTZ.furTable + furOff + 8)
end

-- One gameplay frame of the "only Mr. Nutz changes colour" oracle. Returns a table:
--   S, X              Nutz slot from the scene table, private slot from the hook state
--   sharedChanged     S differs from the ROM palette (objects sharing it would be recoloured)
--   foreignOnX        visible non-Nutz sprites on X while X holds the selection
--   nutz, nutzOk      visible Nutz sprites (tile < $50, name table 0, palette S or X); all on X with the selection
function nutzOracle()
  local S = nutzSlot()
  if not S then return { noSlot = true } end
  local r = { S = S, X = w8(NUTZ.customSlot), sharedChanged = false, foreignOnX = 0, nutz = 0, nutzOk = true }
  local base = 0x80 + S * 16
  for e = 0, 15 do
    if cg(base + e) ~= bus16(NUTZ.palette + e * 2) then r.sharedChanged = true; r.sharedEntry = e; break end
  end
  local X = r.X
  local eOut, eFur = expectedColours()
  local xCustom = X < 8 and cg(0x80 + X * 16 + 6) == eOut and cg(0x80 + X * 16 + 15) == eFur
  for i = 0, 127 do
    if oam(i, 1) < 224 then
      local attr = oam(i, 3)
      local pal = (attr >> 1) & 7
      local tile = oam(i, 2) | ((attr & 1) << 8)
      if tile < 0x50 and (pal == S or pal == X) then
        r.nutz = r.nutz + 1
        if not (pal == X and xCustom) then r.nutzOk = false end
      elseif pal == X and xCustom then
        r.foreignOnX = r.foreignOnX + 1
      end
    end
  end
  return r
end

function paletteLine(base)
  local p = {}
  for e = 0, 15 do p[#p + 1] = hex(cg(base + e), 4) end
  return table.concat(p, " ")
end
