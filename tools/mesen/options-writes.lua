-- Native OPTIONS: logs every CPU write to WRAM during the 12 frames after an A press on a given row, to find where
-- each option value is stored. Original ROM, power-on (timeline from options-probe.lua / boot-timeline.log).
-- Defines: ROW=0..4 (LIVES, ENERGY, CONTROL PAD, MUSIC MODE, LANGUAGE). Prints WRITE lines deduplicated by
-- (address, PC), skipping the stack page ($1Fxx) and the NMI counter.
local ROW_ = ROW or 0
local TITLE_AT, OPT_AT = 1000, 1300
local steps = { { 200, 204, { start = true } }, { TITLE_AT + 100, TITLE_AT + 104, { down = true } }, { TITLE_AT + 140, TITLE_AT + 144, { start = true } } }
for r = 1, ROW_ do steps[#steps + 1] = { OPT_AT + r * 40, OPT_AT + r * 40 + 4, { down = true } } end
local PRESS = OPT_AT + 300
steps[#steps + 1] = { PRESS, PRESS + 4, { a = true } }
steps[#steps + 1] = { PRESS + 100, PRESS + 104, { a = true } }
playInputs(steps)

local seen, n = {}, 0
local function onWrite(address, value)
  if not ((FRAME >= PRESS and FRAME < PRESS + 12) or (FRAME >= PRESS + 100 and FRAME < PRESS + 112)) then return end
  local off = address & 0x1FFFF
  if address < 0x7E0000 then off = address & 0x1FFF end
  if (off >= 0x1F00 and off < 0x2000) or off == 0x01DA or off == 0x01DB then return end
  local s = emu.getState()
  local pc = ((s["cpu.k"] or 0) << 16) | s["cpu.pc"]
  local key = off .. ":" .. pc .. ":" .. (FRAME >= PRESS + 100 and 2 or 1) -- per press window
  if seen[key] then return end
  seen[key] = true
  n = n + 1
  if n <= 2000 then print(string.format("WRITE frame=%d addr=$%06X value=$%02X pc=$%06X", FRAME - PRESS, 0x7E0000 + off, value, pc)) end
end
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x7E0000, 0x7FFFFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x000000, 0x001FFF, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if FRAME == PRESS + 140 then shot("after"); print("WRITES total=" .. n) end
  if FRAME >= PRESS + 148 then emu.stop(0) end
end, emu.eventType.endFrame)
