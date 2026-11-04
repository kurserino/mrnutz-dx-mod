-- Persistence check of the runtime palette patch: from a stage state (prepare-stages.lua), select fur 2 / outfit 3
-- with the shortcuts, then use the debug stage skip WARPS times (crossing world changes) and finally a soft reset.
-- After every new gameplay start the selection must still be 2/3 and Mr. Nutz must show it ("PERSIST ..." lines).
-- Run via npm run sweep:all (the state is chosen in tools/mesen/sweep.ts).
local WARPS, STEP, RESET_FRAMES = 8, 600, 2400
local fails, checks = 0, 0

loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)

local steps = {
  { 10, 14, { select = true, l = true } }, { 20, 24, { select = true, l = true } },
  { 30, 34, { select = true, r = true } }, { 40, 44, { select = true, r = true } }, { 50, 54, { select = true, r = true } },
}
for k = 1, WARPS do steps[#steps + 1] = { 100 + k * STEP, 104 + k * STEP, { r = true } } end
local resetAt = 100 + (WARPS + 1) * STEP
for k = 0, 11 do -- after the reset: Start/A through the title and menus (as in trace-palette.lua)
  steps[#steps + 1] = { resetAt + 200 + k * 200, resetAt + 205 + k * 200, k % 2 == 0 and { start = true } or { a = true } }
end
playInputs(steps)

local function check(tag)
  checks = checks + 1
  local f, o = w8(NUTZ.fur), w8(NUTZ.outfit)
  local r = nutzOracle()
  local ok = f == 2 and o == 3 and not r.noSlot and not r.sharedChanged and r.foreignOnX == 0 and (r.nutz == 0 or r.nutzOk)
  if not ok then fails = fails + 1 end
  print(string.format("PERSIST %s frame=%d idx=%d/%d S=%s X=%s nutz=%s ok=%s", tag, FRAME, f, o, tostring(r.S), tostring(r.X), tostring(r.nutz), tostring(ok)))
  shot(tag)
end

local gameRun, checkedWarp = 0, -1
emu.addEventCallback(function()
  if FRAME == 90 then check("selected") end
  local k = FRAME < resetAt and math.floor((FRAME - 100) / STEP) or -1
  if FRAME > 100 and FRAME < resetAt then
    ww(0x1EC9, w8(0x1EC9) | 0x01) -- stage skip on only after the selection was made
    gameRun = inGameplay() and gameRun + 1 or 0
    if k >= 1 and k ~= checkedWarp and gameRun == 120 then checkedWarp = k; check("warp-" .. k) end
  end
  if FRAME == resetAt then
    ww(0x1EC9, w8(0x1EC9) & 0xFE)
    print("RESET idx=" .. w8(NUTZ.fur) .. "/" .. w8(NUTZ.outfit))
    emu.reset()
  end
  if FRAME > resetAt then
    gameRun = inGameplay() and gameRun + 1 or 0
    if gameRun == 120 then check("after-reset") end
    if gameRun > 126 or FRAME > resetAt + RESET_FRAMES then -- +6: let the last screenshot flush
      if gameRun <= 120 then fails = fails + 1; print("PERSIST after-reset no gameplay reached") end
      print(string.format("RESULT checks=%d fails=%d", checks, fails))
      emu.stop(0)
    end
  end
end, emu.eventType.endFrame)
