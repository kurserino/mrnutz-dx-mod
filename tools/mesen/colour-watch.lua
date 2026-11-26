-- Mr. Nutz colour watch (research tool): per frame, whether the visible Mr. Nutz sprites show the selected colours,
-- with the hook state (S scene slot, X private slot, pending, ready, passes) and the scene pointer. Prints a line on
-- every change and a summary at the end. Use with --prelude output/ares/<name>.lua to start from an ares savestate.
-- Defines: END (default 600), SHOTEVERY (default 60), INPUT (0 idle, 1 hold Up from frame 30, 2 walk right,
--   3 walk left), FIRSTSHOTS (screenshot the first N gameplay frames after each scene change, default 0).
local END_ = END or 600
-- SAVEFUR / SAVEOUTFIT: write a valid save record (src/runtime.ts SAVE_RECORD) after the state load, so the hook's
-- one-time init starts with that selection (stage states have no mod state in WRAM).
loadStateOnBoot(function()
  if SAVEFUR or SAVEOUTFIT then
    local fur, outfit = SAVEFUR or 0, SAVEOUTFIT or 0
    local w0, w2, w4 = 0x5A4E, 0x01 | (fur << 8), outfit
    local ck = 0xFFFF ~ ((w0 + w2 + w4) & 0xFFFF)
    local rec = { 0x4E, 0x5A, 0x01, fur, outfit, 0x00, ck & 0xFF, ck >> 8 }
    for i = 1, 8 do emu.write(0x100 + i - 1, rec[i], emu.memType.snesSaveRam) end
  end
end)
emu.addEventCallback(function()
  if INPUT == 6 then
    -- Start at frame 40 (unpause a paused savestate), then idle.
    if FRAME >= 40 and FRAME < 44 then emu.setInput({ start = true }, 0) end
  elseif INPUT == 5 then
    -- Debug stage skip (emulator RAM only): R at frame 60 with $1EC9 bit 0 set.
    if FRAME == 55 then ww(0x1EC9, w8(0x1EC9) | 1) end
    if FRAME >= 60 and FRAME < 64 then emu.setInput({ r = true }, 0) end
    if FRAME == 70 then ww(0x1EC9, w8(0x1EC9) & 0xFE) end
  elseif INPUT == 1 and FRAME >= 30 then emu.setInput({ up = true }, 0)
  elseif INPUT == 2 and FRAME >= 30 then emu.setInput({ right = true }, 0)
  elseif INPUT == 3 and FRAME >= 30 then emu.setInput({ left = true }, 0)
  elseif INPUT == 4 and FRAME >= 30 then
    -- Walk right until X >= TX, then press ACT (1 up, 2 down, 3 Y, 4 A) in pulses.
    if w16(0x37) < (TX or 0) and not reached then emu.setInput({ right = true }, 0)
    else
      reached = true
      local b = ({ "up", "down", "y", "a" })[ACT or 1]
      if FRAME % 20 < 10 then emu.setInput({ [b] = true }, 0) end
    end
  end
end, emu.eventType.inputPolled)
local last, okFrames, badFrames, visFrames = "", 0, 0, 0
local lastScene, sceneAt, firstOk = -1, 0, -1
emu.addEventCallback(function()
  local scene = w8(0x560) * 0x10000 + w16(0x55E)
  if scene ~= lastScene then
    print(string.format("F%d SCENE %06X stage=%02X area0550=%04X x=%d y=%d", FRAME, scene, w8(0x054C), w16(0x0550), w16(0x37), w16(0x39)))
    lastScene, sceneAt, firstOk = scene, FRAME, -1
  end
  local g = inGameplay()
  local line
  if g then
    local o = nutzOracle()
    if o.noSlot then line = "noSlot"
    else
      line = string.format("S=%d X=%d nutz=%d ok=%s foreignOnX=%d shared=%s pend=%02X ready=%d passes=%d", o.S, o.X,
        o.nutz, tostring(o.nutzOk), o.foreignOnX, tostring(o.sharedChanged), w8(0x1BE20), w8(0x1BE0D), w8(0x1BE10))
      if o.nutz > 0 then
        visFrames = visFrames + 1
        if o.nutzOk then okFrames = okFrames + 1; if firstOk < 0 then firstOk = FRAME; print(string.format("F%d FIRSTOK %d frames after scene change", FRAME, FRAME - sceneAt)) end
        else badFrames = badFrames + 1 end
      end
    end
  else
    line = "nogameplay"
  end
  if line ~= last then print(string.format("F%d %s", FRAME, line)); last = line end
  -- Colours of the private slot X: log every entry that changes (another CGRAM writer, palette animation).
  local X = w8(0x1BE06)
  if g and X < 8 then
    xPrev = xPrev or {}
    for e = 1, 15 do
      local c = cg(0x80 + X * 16 + e)
      local k = X * 16 + e
      if xPrev[k] and xPrev[k] ~= c then
        xChanges = (xChanges or 0) + 1
        if xChanges <= 40 then print(string.format("F%d XCOLOUR slot%d entry%d %04X->%04X", FRAME, X, e, xPrev[k], c)) end
      end
      xPrev[k] = c
    end
  end
  if FIRSTSHOTS and FRAME - sceneAt < FIRSTSHOTS and g then shot(string.format("s%04d", FRAME)) end
  if FRAME % (SHOTEVERY or 60) == 0 then shot(string.format("f%04d", FRAME)) end
  if FRAME == END_ then
    print(string.format("RESULT visible=%d ok=%d bad=%d", visFrames, okFrames, badFrames))
  end
  if FRAME >= END_ + 6 then emu.stop(0) end
end, emu.eventType.endFrame)
