-- One power-on of the patched game (no savestate: a new Mesen process is a real power-on, and Mesen loads the
-- battery save from its Saves folder). Presses Start/A through the title into level 1, then:
--   CHECK boot     indices restored by the hook + palette oracle, 120 frames into gameplay
--   (SELECT=1)     Select+L x2, Select+R x3, then CHECK selected
-- Mesen writes the battery save when the script stops. Orchestrated by tools/mesen/power-cycle.ts.
local SELECT_ = SELECT or 0
-- WARPS=N: after the boot check, use the debug stage skip ($1EC9 bit0 + R, emulator RAM only) N times and check the
-- restored colours in each new stage (crosses into the next world: "CHECK warp-k").
local WARPS_ = WARPS or 0
local STEP = 600
local steps = {}
for k = 0, 11 do steps[#steps + 1] = { 200 + k * 200, 205 + k * 200, k % 2 == 0 and { start = true } or { a = true } } end
playInputs(steps)

local gameRun, phase, phaseAt = 0, "boot", 0
local function check(tag)
  local r = nutzOracle()
  -- X=255: the hook found no free private slot in this scene (known limitation, Mr. Nutz stays original).
  print(string.format("CHECK %s frame=%d idx=%d/%d X=%s nutz=%s nutzOk=%s noSlot=%s sharedChanged=%s sram=%s",
    tag, FRAME, w8(NUTZ.fur), w8(NUTZ.outfit), tostring(r.X), tostring(r.nutz), tostring(r.nutzOk), tostring(r.noSlot), tostring(r.sharedChanged),
    (function()
      local t = {}
      for i = 0, 7 do t[#t + 1] = string.format("%02X", emu.read(0x100 + i, emu.memType.snesSaveRam, false)) end
      return table.concat(t)
    end)()))
  shot(tag)
end

-- Warp state: press R (stage skip), wait until gameplay was left and then ran 120 frames in a row (the hook needs a
-- full OAM pass after each scene change; checking on the first frames would catch the iris-in with the original
-- colours). Screens without gameplay (Stage Clear, intros, map) get another R after STEP frames.
local warps, pressAt, leftGameplay = 0, 0, false
emu.addEventCallback(function()
  if phase == "warp" then
    local f = FRAME - pressAt
    if f >= 10 and f < 14 then emu.setInput({ r = true }, 0) end
    return
  end
  if phase ~= "select" then return end
  local f = FRAME - phaseAt
  if f >= 10 and f < 14 or f >= 20 and f < 24 then emu.setInput({ select = true, l = true }, 0) end
  if f >= 30 and f < 34 or f >= 40 and f < 44 or f >= 50 and f < 54 then emu.setInput({ select = true, r = true }, 0) end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  gameRun = inGameplay() and gameRun + 1 or 0
  if phase == "boot" and gameRun == 120 then
    check("boot")
    if SELECT_ == 1 then phase, phaseAt = "select", FRAME
    elseif WARPS_ > 0 then phase, phaseAt, pressAt, leftGameplay = "warp", FRAME, FRAME, false
    else phase, phaseAt = "done", FRAME end
  elseif phase == "warp" then
    ww(0x1EC9, w8(0x1EC9) | 0x01)
    if gameRun == 0 then leftGameplay = true end
    if leftGameplay and gameRun == 120 then
      warps = warps + 1
      check("warp-" .. warps)
      pressAt, leftGameplay = FRAME, false
      if warps >= WARPS_ then ww(0x1EC9, w8(0x1EC9) & 0xFE); phase, phaseAt = "done", FRAME end
    elseif FRAME - pressAt >= STEP and gameRun == 0 then
      pressAt = FRAME -- non-gameplay screen: skip it too
    end
  elseif phase == "select" and FRAME - phaseAt == 120 then
    check("selected")
    phase, phaseAt = "done", FRAME
  elseif phase == "done" and FRAME - phaseAt >= 8 then
    print("RESULT ok")
    emu.stop(0)
  elseif FRAME >= 6000 + WARPS_ * 3 * STEP then
    print("RESULT no-gameplay")
    emu.stop(1)
  end
end, emu.eventType.endFrame)
