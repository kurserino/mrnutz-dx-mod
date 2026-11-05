-- Native OPTIONS menu research (original ROM, power-on). Reaches the title screen, opens OPTIONS and, if ACTIONS is
-- set, plays a scripted list of presses while diffing WRAM around each one:
--   OPT_CHANGE <step> $7Exxxx old->new   bytes that changed around that press (first 16), excluding bytes that also
--                                         change with no input (the "idle-1" step). In OPTION MODE, Up/Down move the
--                                         cursor and Left/Right do nothing; A changes the value (options-probe.log).
-- Screenshots: title, options, and after every step. Defines: STAGE=0 only navigation and screenshots;
-- STAGE=1 run the probe presses below.
local STAGE_ = STAGE or 0
local TITLE_AT = 1000 -- one Start at frame 200 skips the logos; the title is stable from ~900 (boot-timeline.log)
local steps = { { 200, 204, { start = true } } }
-- Title menu: START / OPTIONS. Down, then Start opens OPTIONS.
steps[#steps + 1] = { TITLE_AT + 100, TITLE_AT + 104, { down = true } }
steps[#steps + 1] = { TITLE_AT + 140, TITLE_AT + 144, { start = true } }
local OPT_AT = TITLE_AT + 300
-- Probe presses inside OPTIONS: each entry = { name, buttons }; one every 90 frames.
local PROBE = {
  { "idle-1", {} }, { "a-lives-1", { a = true } }, { "a-lives-2", { a = true } },
  { "down-1", { down = true } }, { "a-energy-1", { a = true } }, { "a-energy-2", { a = true } },
  { "down-2", { down = true } }, { "a-pad-1", { a = true } }, { "a-pad-2", { a = true } },
  { "down-3", { down = true } }, { "a-music-1", { a = true } }, { "a-music-2", { a = true } },
  { "down-4", { down = true } }, { "a-lang-1", { a = true } }, { "a-lang-2", { a = true } },
}
if STAGE_ == 1 then
  for i, p in ipairs(PROBE) do
    local at = OPT_AT + i * 90
    steps[#steps + 1] = { at, at + 4, p[2] }
  end
end
playInputs(steps)

local function snap() local t = {}; for a = 0, 0x1FFFF do t[a] = w8(a) end; return t end
local before
local noisy = {} -- bytes that change with no input (animation, scroll, frame counters)
-- Scratch/animation ranges seen changing on every press (options-probe.log, first pass): DP scratch, sprite
-- animation tables, pointer scratch, stack, NMI counter.
local function scratch(a)
  return a < 0x20 or (a >= 0x1400 and a < 0x1500) or (a >= 0x1A66 and a <= 0x1A6C) or a >= 0x1F00 or a == 0x01DA or a == 0x01DB or a == 0x0035 or a == 0x0036 or a == 0x00EC
end
emu.addEventCallback(function()
  if FRAME == TITLE_AT + 60 then shot("title") end
  if FRAME == OPT_AT then shot("options") end
  if STAGE_ == 1 then
    for i, p in ipairs(PROBE) do
      local at = OPT_AT + i * 90
      if FRAME == at - 5 then before = snap() end
      if FRAME == at + 40 then
        local n = 0
        for a = 0, 0x1FFFF do
          local v = w8(a)
          if p[1] == "idle-1" and v ~= before[a] then noisy[a] = true end
          if v ~= before[a] and not noisy[a] and not scratch(a) then
            n = n + 1
            if n <= 48 then print(string.format("OPT_CHANGE %s $%06X %02X->%02X", p[1], 0x7E0000 + a, before[a], v)) end
          end
        end
        print(string.format("OPT_STEP %s changed=%d", p[1], n))
        shot("opt-" .. p[1])
      end
    end
  end
  local last = STAGE_ == 1 and OPT_AT + (#PROBE + 1) * 90 or OPT_AT + 60
  if FRAME >= last then emu.stop(0) end
end, emu.eventType.endFrame)
