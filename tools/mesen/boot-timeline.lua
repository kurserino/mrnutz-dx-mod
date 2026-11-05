-- Power-on timeline: screenshots every STEP frames up to FRAMES, pressing Start only at the frames in PRESSES.
-- Used to locate the title screen and menus (no state, original ROM). Defines: FRAMES, STEP.
local FRAMES_, STEP_ = FRAMES or 2000, STEP or 100
local PRESSES = { 200 }
local steps = {}
for _, p in ipairs(PRESSES) do steps[#steps + 1] = { p, p + 4, { start = true } } end
playInputs(steps)
emu.addEventCallback(function()
  if FRAME % STEP_ == 0 then shot(string.format("t%05d", FRAME)) end
  if FRAME >= FRAMES_ + 8 then emu.stop(0) end
end, emu.eventType.endFrame)
