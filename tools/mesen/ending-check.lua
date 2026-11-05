-- End-of-game check: from the last playable stage state (stage-36), select fur 2 / outfit 3, finish the stage once
-- with the game's debug stage skip ($1EC9 bit0 + R, emulator RAM only; then off again), let the ending and credits
-- run for 15000 frames with no input, press Start/A on the final screen (it waits forever, as in the original
-- game), soft reset, then press Start/A through the title and menus until gameplay starts again.
-- Logs every change of the game-state pointer $01DC, screenshots every 1000 frames and at each milestone, and a
-- RESULT line: credits reached, title reached, gameplay after the title, selection kept, no stall.
-- Run on the patched ROM: npx tsx tools/mesen/run.ts tools/mesen/ending-check.lua --rom "output/Mr. Nutz.runtime.sfc"
--   --state output/states/stage-36.mss --define FRAMES=40000
local FRAMES_ = FRAMES or 40000
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)

local phase = "select" -- select -> skip -> ending -> title -> newgame -> done
local phaseAt, gameRun, lastState = 0, 0, -1
local ENDING_FRAMES = 15000 -- no input: credits and the final "Starring Mr. Nutz / Final score" screen
local seenStates, milestones = {}, {}
local function mark(tag)
  milestones[#milestones + 1] = tag .. "@" .. FRAME
  print(string.format("MILESTONE %s frame=%d state=$%04X idx=%d/%d", tag, FRAME, w16(0x01DC), w8(NUTZ.fur), w8(NUTZ.outfit)))
  shot(tag)
end

emu.addEventCallback(function()
  local input = {}
  if phase == "select" then
    if FRAME >= 10 and FRAME < 14 or FRAME >= 20 and FRAME < 24 then input = { select = true, l = true } end
    if FRAME >= 30 and FRAME < 34 or FRAME >= 40 and FRAME < 44 or FRAME >= 50 and FRAME < 54 then input = { select = true, r = true } end
  elseif phase == "skip" then
    if FRAME - phaseAt >= 10 and FRAME - phaseAt < 14 then input = { r = true } end -- finish the last stage
  elseif phase == "title" or phase == "reset" or phase == "newgame" then
    local k = (FRAME - phaseAt) % 200
    if k < 5 then input = ((FRAME - phaseAt) // 200) % 2 == 0 and { start = true } or { a = true } end
  end
  emu.setInput(input, 0)
end, emu.eventType.inputPolled)

local title = { frames = 0 }
emu.addEventCallback(function()
  local st = w16(0x01DC)
  if st ~= lastState then
    if not seenStates[st] then seenStates[st] = true; print(string.format("STATE frame=%d $01DC=$%04X phase=%s", FRAME, st, phase)) end
    lastState = st
  end
  if FRAME % 1000 == 0 then shot(string.format("f%05d", FRAME)) end
  gameRun = inGameplay() and gameRun + 1 or 0

  if phase == "select" and FRAME == 90 then
    mark("selected")
    ww(0x1EC9, w8(0x1EC9) | 0x01)
    phase, phaseAt = "skip", FRAME
  elseif phase == "skip" and FRAME - phaseAt == 60 then
    ww(0x1EC9, w8(0x1EC9) & 0xFE) -- debug skip off again: the ending must run as in the original game
    phase, phaseAt = "ending", FRAME
  elseif phase == "ending" then
    if (FRAME - phaseAt) % 500 == 250 then shot(string.format("ending-%05d", FRAME)) end
    if FRAME - phaseAt == ENDING_FRAMES then mark("ending-end"); phase, phaseAt = "title", FRAME end
  elseif phase == "title" then
    -- The final screen ignores Start/A in the original game too (ending-check-original.log): after 3000 frames
    -- of presses, soft reset as a player would, then the same presses go through the title into a new game.
    if FRAME - phaseAt == 3000 and gameRun == 0 then
      mark("final-screen-waits")
      emu.reset()
      phase, phaseAt = "reset", FRAME
    end
    if gameRun == 1 then mark("gameplay-again"); phase, phaseAt = "newgame", FRAME end
  elseif phase == "reset" then
    if (FRAME - phaseAt) % 100 == 50 and FRAME - phaseAt < 3000 then shot(string.format("reset-%05d", FRAME)) end
    if gameRun == 1 then mark("gameplay-after-reset"); phase, phaseAt = "newgame", FRAME end
  elseif phase == "newgame" then
    if gameRun == 300 then
      local r = nutzOracle()
      mark("new-game")
      print(string.format("NEWGAME idx=%d/%d nutzOk=%s nutz=%s sharedChanged=%s", w8(NUTZ.fur), w8(NUTZ.outfit), tostring(r.nutzOk), tostring(r.nutz), tostring(r.sharedChanged)))
      phase, phaseAt = "done", FRAME
    end
  end
  if (phase == "done" and FRAME - phaseAt >= 8) or FRAME >= FRAMES_ then -- +8: let the last screenshot flush
    print(string.format("RESULT frames=%d phase=%s milestones=%s", FRAME, phase, table.concat(milestones, ",")))
    emu.stop(phase == "done" and 0 or 1)
  end
end, emu.eventType.endFrame)
