-- Builds one savestate per stage for the fast sweep (run once, on the ORIGINAL ROM, so the states do not depend
-- on the patch build). From roms/states/level1-start.mss it uses the debug stage skip ($1EC9 bit0 + R, emulator
-- RAM only) and saves a state STABLE frames after gameplay starts in each stage ("STATE stage-NN <hex>",
-- stored by tools/mesen/run.ts in output/states/). Non-gameplay screens (intro, Stage Clear) are skipped by
-- pressing R again after WAIT_LIMIT frames. Stops after MISS_LIMIT skips in a row without gameplay.
-- Run: npm run sweep:prepare
local STABLE, WAIT_LIMIT, MISS_LIMIT, MAX_STAGES = 90, 700, 8, 70
local stage, phase, phaseAt, gameRun, misses, wantState = 0, "wait", 0, 0, 0, false

loadStateOnBoot(function() phase, phaseAt = "wait", 0 end)

-- createSavestate must run inside an exec callback: the joypad mirror at $81:828A runs every gameplay frame.
emu.addMemoryCallback(function()
  if not wantState then return end
  wantState = false
  print(string.format("STATE stage-%02d %s", stage, (emu.createSavestate():gsub(".", function(c) return string.format("%02X", string.byte(c)) end))))
  print(string.format("STAGE %02d frame=%d", stage, FRAME))
  shot(string.format("stage-%02d", stage))
  stage = stage + 1
  phase, phaseAt = "warp", FRAME
end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)

emu.addEventCallback(function()
  if phase == "warp" and FRAME - phaseAt >= 10 and FRAME - phaseAt < 14 then emu.setInput({ r = true }, 0) end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if FRAME == 0 then return end
  ww(0x1EC9, w8(0x1EC9) | 0x01)
  if phase == "warp" then
    if FRAME - phaseAt >= 20 then phase, phaseAt, gameRun = "wait", FRAME, 0 end
  elseif phase == "wait" then
    gameRun = inGameplay() and gameRun + 1 or 0
    if gameRun >= STABLE then
      misses = 0
      wantState = true
      phase = "capture"
    elseif FRAME - phaseAt > WAIT_LIMIT then
      misses = misses + 1
      print("SKIP after stage " .. (stage - 1) .. " misses=" .. misses)
      phase, phaseAt = "warp", FRAME
    end
  end
  if misses >= MISS_LIMIT or stage >= MAX_STAGES then
    print("DONE stages=" .. stage)
    emu.stop(0)
  end
end, emu.eventType.endFrame)
