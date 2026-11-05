-- SRAM / anti-copier evidence (openspec/changes/archive/2026-11-05-sram-persistence, tasks 1.2-1.5).
-- Logs:
--   CALL <A|B|C|D>  every execution of a check routine (first 8 per routine, then counted), with the
--                   JSL/JSR return address read from the stack, A/X/Y/P and the frame.
--   SRAM_R / SRAM_W every CPU read/write to banks $70-$7D and $F0-$FD (LoROM SRAM space), first 16 distinct
--                   (address, PC) pairs, then counted.
--   CODE_READ       data reads of the check routines' bytes by code outside the routine (second-level check).
--   HANG            the frame counter kept running but the CPU stayed on one of the BEQ * loops for 60 frames.
--   DETECT <id>     a check took its "SRAM present" branch (E/F/G found by the trace, and C).
--   STALL           end-of-frame PC stuck in one 64-byte window for 120 frames (generic hang).
-- Defines (run.ts --define): MODE=0 power-on through the title into level 1 (no --state);
--                             MODE=1 from a stage state (--state), action cycle + pause; MODE=2 stage state,
--                             0 lives + walk right (deaths, game over/continue); MODE=3 soft reset from a
--                             stage state; FRAMES=N run length.
-- Run on the ORIGINAL ROM (npm run trace:sram) and on the header-only variant (task 1.4).
local MODE_ = MODE or 0
local FRAMES_ = FRAMES or 3000

local ROUTINES = {
  { id = "A", lo = 0x0083EF, hi = 0x008402, loop = 0x008400 },
  { id = "B", lo = 0x01802B, hi = 0x018038 },
  { id = "C", lo = 0x018F53, hi = 0x018F60 },
  { id = "D", lo = 0x019D3A, hi = 0x019D4D, loop = 0x019D4B },
}
local function pcFull(s) return ((s["cpu.k"] or 0) << 16) | s["cpu.pc"] end
local function bankless(a) return a & 0x7FFFFF end -- $80-$FF mirror $00-$7F for ROM code

local calls, callCount = {}, {}
local function onCall(r)
  return function()
    callCount[r.id] = (callCount[r.id] or 0) + 1
    if callCount[r.id] > 8 then return end
    local s = emu.getState()
    local sp = s["cpu.sp"]
    local b1, b2, b3 = bus8(sp + 1), bus8(sp + 2), bus8(sp + 3)
    print(string.format("CALL %s frame=%d pc=$%06X jslRet=$%02X%02X%02X jsrRet=$%02X%02X A=$%04X X=$%04X Y=$%04X P=$%02X DBR=$%02X gameplay=%s",
      r.id, FRAME, pcFull(s), b3, b2, b1, b2, b1, s["cpu.a"], s["cpu.x"], s["cpu.y"], s["cpu.ps"], s["cpu.dbr"], tostring(inGameplay())))
  end
end
for _, r in ipairs(ROUTINES) do
  for _, bank in ipairs({ 0x00, 0x80 }) do
    local a = (bank << 16) + r.lo
    emu.addMemoryCallback(onCall(r), emu.callbackType.exec, a, a, emu.cpuType.snes, emu.memType.snesMemory)
  end
end

-- SRAM space accesses
local seen, counts, byPc = {}, { r = 0, w = 0 }, {}
local function sram(kind)
  return function(address, value)
    counts[kind] = counts[kind] + 1
    local pc = pcFull(emu.getState())
    local e = byPc[pc]
    if not e then e = { r = 0, w = 0, lo = address, hi = address, first = FRAME }; byPc[pc] = e end
    e[kind] = e[kind] + 1
    if address < e.lo then e.lo = address end
    if address > e.hi then e.hi = address end
    local key = kind .. address .. ":" .. pc
    if seen[key] then return end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    if n >= 16 then return end
    seen[key] = true
    print(string.format("SRAM_%s frame=%d addr=$%06X value=$%02X pc=$%06X", kind == "r" and "R" or "W", FRAME, address, value or 0, pc))
  end
end
-- LIGHT=1 skips this logging: on a cartridge with SRAM, check E loops on SRAM forever and the per-access Lua calls
-- make Mesen crawl (task 1.4).
if (LIGHT or 0) == 0 then
  for _, range in ipairs({ { 0x700000, 0x7DFFFF }, { 0xF00000, 0xFDFFFF } }) do
    emu.addMemoryCallback(sram("r"), emu.callbackType.read, range[1], range[2], emu.cpuType.snes, emu.memType.snesMemory)
    emu.addMemoryCallback(sram("w"), emu.callbackType.write, range[1], range[2], emu.cpuType.snes, emu.memType.snesMemory)
  end
end

-- Data reads of the routines' bytes from code outside them (operand fetches come from inside the routine).
local codeReads = 0
for _, r in ipairs(ROUTINES) do
  for _, bank in ipairs({ 0x00, 0x80 }) do
    emu.addMemoryCallback(function(address)
      local pc = bankless(pcFull(emu.getState()))
      if pc >= r.lo and pc <= r.hi + 1 then return end
      codeReads = codeReads + 1
      if codeReads <= 8 then print(string.format("CODE_READ %s frame=%d addr=$%06X pc=$%06X", r.id, FRAME, address, pc)) end
    end, emu.callbackType.read, (bank << 16) + r.lo, (bank << 16) + r.hi, emu.cpuType.snes, emu.memType.snesMemory)
  end
end

-- Hang detector: CPU parked on a BEQ * loop.
local loopFrames = {}
emu.addEventCallback(function()
  local pc = bankless(pcFull(emu.getState()))
  for _, r in ipairs(ROUTINES) do
    if r.loop then
      if pc == r.loop then loopFrames[r.id] = (loopFrames[r.id] or 0) + 1 else loopFrames[r.id] = 0 end
      if loopFrames[r.id] == 60 then print(string.format("HANG %s frame=%d pc=$%06X", r.id, FRAME, pc)); shot("hang-" .. r.id) end
    end
  end
end, emu.eventType.endFrame)

-- "SRAM detected" branches of the checks found by the trace (E/F/G) and of C. Each fires only when the
-- write to $70:xxxx stuck, i.e. on a cartridge with SRAM (task 1.4, header-only variant).
-- E $9C:F82C: INC A / BRA back to STA $700000 (loops while the write keeps sticking).
-- F $82:B9E6: STA $054A,Y (flag set when $70:0345 is writable).
-- G $81:C477: restore [$1A], then STA [$10] with the value from $BE41 (write through a pointer).
-- C $81:8F61: fall-through into the HDMA/colour-math setup.
local DETECT = { { id = "E", at = 0x1CF82C }, { id = "F", at = 0x02B9E6 }, { id = "G", at = 0x01C477 }, { id = "C", at = 0x018F61 } }
local detectCount = {}
for _, d in ipairs(DETECT) do
  for _, bank in ipairs({ 0x00, 0x80 }) do
    local addr, ref = (bank << 16) + d.at, nil
    ref = emu.addMemoryCallback(function()
      detectCount[d.id] = (detectCount[d.id] or 0) + 1
      if detectCount[d.id] > 4 then
        -- Stop paying for a callback in a tight loop; the count stays at 5 = "4 logged, more happened".
        emu.removeMemoryCallback(ref, emu.callbackType.exec, addr, addr, emu.cpuType.snes, emu.memType.snesMemory)
        return
      end
      local s = emu.getState()
      local dp = s["cpu.d"]
      local ptr10 = bus8(dp + 0x10) | (bus8(dp + 0x11) << 8) | (bus8(dp + 0x12) << 16)
      print(string.format("DETECT %s frame=%d pc=$%06X A=$%04X X=$%04X Y=$%04X D=$%04X DBR=$%02X [$10]=$%06X gameplay=%s",
        d.id, FRAME, pcFull(s), s["cpu.a"], s["cpu.x"], s["cpu.y"], dp, s["cpu.dbr"], ptr10, tostring(inGameplay())))
    end, emu.callbackType.exec, addr, addr, emu.cpuType.snes, emu.memType.snesMemory)
  end
end

-- Generic stall detector: the end-of-frame PC stays inside one 64-byte window for 120 frames, outside the game's
-- normal wait loops. Ignored windows were all seen in healthy runs of the ORIGINAL ROM (trace-sram-all.log):
-- $80:8230-8232 wait for NMI; $9C:F830-F835 boot delay; $9D:AF3C-AF3D, $9D:C4CE-C4D1, $9D:C886-C888 screens
-- without gameplay (intros, transitions, continue).
local WAIT_LOOPS = { { 0x008230, 0x008232 }, { 0x1CF830, 0x1CF835 }, { 0x1DAF3C, 0x1DAF3D }, { 0x1DC4CE, 0x1DC4D1 }, { 0x1DC886, 0x1DC888 } }
local stallPc, stallFrames, stalls = -1, 0, 0
emu.addEventCallback(function()
  local pc = bankless(pcFull(emu.getState()))
  for _, w in ipairs(WAIT_LOOPS) do
    if pc >= w[1] and pc <= w[2] then stallFrames = 0; return end
  end
  if stallPc >= 0 and (pc >> 6) == (stallPc >> 6) then stallFrames = stallFrames + 1 else stallPc, stallFrames = pc, 0 end
  if stallFrames == 120 then
    stalls = stalls + 1
    if stalls <= 4 then print(string.format("STALL frame=%d pc=$%06X", FRAME, pc)); shot(string.format("stall-%d", FRAME)) end
  end
end, emu.eventType.endFrame)

-- Inputs
if MODE_ == 0 then
  local steps = {}
  for k = 0, 11 do steps[#steps + 1] = { 200 + k * 200, 205 + k * 200, k % 2 == 0 and { start = true } or { a = true } } end
  steps[#steps + 1] = { 2600, FRAMES_, { right = true } }
  playInputs(steps)
else
  loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
  if MODE_ == 1 then
    local steps, cycle = {}, {
      { 0, 60, { right = true } }, { 60, 64, { right = true, b = true } }, { 64, 90, { right = true } },
      { 90, 94, { y = true } }, { 100, 104, { x = true } }, { 110, 114, { a = true } },
      { 120, 160, { down = true } }, { 160, 180, { up = true } }, { 180, 220, { left = true } },
      { 220, 224, { b = true } }, { 224, 240, { right = true, y = true } },
    }
    for c = 0, math.floor(FRAMES_ / 240) do
      for _, s in ipairs(cycle) do steps[#steps + 1] = { 10 + c * 240 + s[1], 10 + c * 240 + s[2], s[3] } end
    end
    table.insert(steps, 1, { 500, 504, { start = true } })
    table.insert(steps, 1, { 560, 564, { start = true } })
    playInputs(steps)
  elseif MODE_ == 3 then
    -- Soft reset from gameplay at frame 300, then Start/A through the title and menus into a stage.
    local steps = { { 0, 300, { right = true } } }
    for k = 0, 11 do steps[#steps + 1] = { 500 + k * 200, 505 + k * 200, k % 2 == 0 and { start = true } or { a = true } } end
    steps[#steps + 1] = { 2900, FRAMES_, { right = true } }
    playInputs(steps)
    emu.addEventCallback(function()
      if FRAME == 300 then print("RESET frame=300"); emu.reset() end
    end, emu.eventType.endFrame)
  else
    -- Fast game over (docs/knowledge/game-state.md): 0 lives (word $1889 = BCD 0 XOR $A3B7) at frame 30, so the next death
    -- reaches game over and CONTINUE. POKE_ENERGY=1 also sets energy to 1, but that sends the game into a black-screen
    -- loop at $8A:81E2 (trace-sram-go1.log), so it is off by default. Walk right and press Start/A periodically.
    emu.addEventCallback(function()
      if FRAME == 30 then
        ww(0x1889, 0xB7); ww(0x188A, 0xA3)
        if (POKE_ENERGY or 0) == 1 then ww(0x05A2, 1) end
      end
      if FRAME % 500 == 250 then
        local s = emu.getState()
        print(string.format("PC frame=%d pc=$%02X%04X gameplay=%s lives=$%04X energy=%d", FRAME, s["cpu.k"], s["cpu.pc"], tostring(inGameplay()), w16(0x1889), w8(0x05A2)))
      end
    end, emu.eventType.endFrame)
    emu.addEventCallback(function()
      local k = FRAME % 300
      if k < 4 then emu.setInput({ start = true }, 0)
      elseif k >= 150 and k < 154 then emu.setInput({ a = true }, 0)
      else emu.setInput({ right = true }, 0) end
    end, emu.eventType.inputPolled)
  end
end

local gameplayFrames = 0
emu.addEventCallback(function()
  if inGameplay() then gameplayFrames = gameplayFrames + 1 end
  if FRAME == FRAMES_ - 10 then shot("end") end
  if MODE_ == 2 and FRAME % 500 == 250 then shot(string.format("f%05d", FRAME)) end
  if FRAME >= FRAMES_ then
    local c = {}
    for _, r in ipairs(ROUTINES) do c[#c + 1] = r.id .. "=" .. (callCount[r.id] or 0) end
    local pcs = {}
    for pc in pairs(byPc) do pcs[#pcs + 1] = pc end
    table.sort(pcs)
    for _, pc in ipairs(pcs) do
      local e = byPc[pc]
      print(string.format("SRAM_PC pc=$%06X r=%d w=%d addr=$%06X-$%06X firstFrame=%d", pc, e.r, e.w, e.lo, e.hi, e.first))
    end
    local d = {}
    for _, x in ipairs(DETECT) do d[#d + 1] = x.id .. "=" .. (detectCount[x.id] or 0) end
    print(string.format("RESULT mode=%d frames=%d gameplay=%d calls=%s detect=%s stalls=%d sramReads=%d sramWrites=%d codeReads=%d",
      MODE_, FRAME, gameplayFrames, table.concat(c, ","), table.concat(d, ","), stalls, counts.r, counts.w, codeReads))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
