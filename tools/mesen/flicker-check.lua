-- Flicker check: from a stage state, cycles fur (Select+L) and outfit (Select+R) PRESSES times each, every
-- GAP frames, and classifies every gameplay frame in which Mr. Nutz is visible:
--   ok        his sprites are on the private slot X holding the current selection
--   original  his sprites are on S (original colours) although a non-original selection is active -> flicker
--   stale     his sprites are on X but X does not hold the current selection (1-frame input latency)
-- flash  = an "original" frame right after a coloured frame on the same private slot: the visible blink. Must be 0.
-- switch = the same, but X changed (another object took the slot; Mr. Nutz moves after one original frame).
-- Ends with a pause/unpause (Start), which must not blink either.
-- Prints "FLICKER ..." for the first frames of each kind and one RESULT line.
-- Run by npm run sweep:all for every stage (tools/mesen/sweep.ts).
local PRESSES, GAP, START = 12, 20, 20

loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)

local steps = {}
for k = 0, PRESSES - 1 do steps[#steps + 1] = { START + k * GAP, START + k * GAP + 4, { select = true, l = true } } end
local rStart = START + PRESSES * GAP
for k = 0, PRESSES - 1 do steps[#steps + 1] = { rStart + k * GAP, rStart + k * GAP + 4, { select = true, r = true } } end
local pauseAt = rStart + PRESSES * GAP + 20
steps[#steps + 1] = { pauseAt, pauseAt + 4, { start = true } }
steps[#steps + 1] = { pauseAt + 60, pauseAt + 64, { start = true } }
local END_AT = pauseAt + 120
playInputs(steps)

local c = { ok = 0, original = 0, stale = 0, frames = 0, flash = 0, switch = 0 }
local shown, prevKind, prevX = 0, nil, nil
emu.addEventCallback(function()
  if FRAME >= START and FRAME < END_AT and inGameplay() then
    local f, o = w8(NUTZ.fur), w8(NUTZ.outfit)
    local S, X = nutzSlot(), w8(NUTZ.customSlot)
    if f == 0 and o == 0 then prevKind = nil end -- original selection on purpose: not a blink
    if S and (f ~= 0 or o ~= 0) then
      local eOut, eFur = expectedColours()
      local onS, onX, nutz = 0, 0, 0
      for i = 0, 127 do
        if oam(i, 1) < 224 and oam(i, 2) < 0x50 and (oam(i, 3) & 1) == 0 then
          local pal = (oam(i, 3) >> 1) & 7
          if pal == S then onS = onS + 1; nutz = nutz + 1 elseif pal == X then onX = onX + 1; nutz = nutz + 1 end
        end
      end
      if nutz > 0 then
        c.frames = c.frames + 1
        local kind
        if onS > 0 then kind = "original"
        elseif X < 8 and cg(0x80 + X * 16 + 6) == eOut and cg(0x80 + X * 16 + 15) == eFur then kind = "ok"
        else kind = "stale" end
        c[kind] = c[kind] + 1
        if kind == "original" and (prevKind == "ok" or prevKind == "stale") then
          if X == prevX then c.flash = c.flash + 1 else c.switch = c.switch + 1 end
        end
        prevKind, prevX = kind, X
        if kind ~= "ok" and shown < 12 then
          shown = shown + 1
          print(string.format("FLICKER frame=%d kind=%s idx=%d/%d S=%d X=%d ready=%d applied=%d", FRAME, kind, f, o, S, X, w8(0x1BE0D), w8(0x1BE18)))
        end
      end
    end
  end
  if FRAME == END_AT then
    print(string.format("RESULT frames=%d ok=%d original=%d stale=%d flash=%d switch=%d", c.frames, c.ok, c.original, c.stale, c.flash, c.switch))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
