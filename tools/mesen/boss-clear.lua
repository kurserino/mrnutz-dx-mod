-- Plays a boss stage for real (no debug skip) with the public cheats invulnerability ($008D=$2D) and one-shot bosses
-- ($05D0=$00) and 99 nuts ($0A29) held, walking right and shooting, to reach the stage-clear path the debug skip never runs.
-- Logs NMI-vector changes, gameplay gaps and the PC when gameplay stops for long. Defines: END (frames, default 9000),
-- FUR / OUTFIT (colour indices written to the hook state at frame 5; default 0/0 = original colours).
local END_ = END or 9000
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
local lastVec, lastGame, gapReported, lastPC = -1, 0, false, 0
emu.addEventCallback(function()
  local f = FRAME % 64
  local b = { y = (f % 8) < 4 }
  if f < 40 then b.right = true elseif f < 48 then b.b = true; b.right = true end
  if FRAME > 300 then b.right = (FRAME % 128) < 6; b.left = nil end
  emu.setInput(b, 0)
end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  if FRAME == 0 then return end
  if FRAME == 5 then ww(NUTZ.fur, FUR or 0); ww(NUTZ.outfit, OUTFIT or 0) end
  if w8(0x13B4) == 0 then ww(0x008D, 0x2D); ww(0x05D0, 0x00); ww(0x0A29, 0x99) end
  local v = w16(0x01DC)
  if v ~= lastVec then print(string.format("F%d NMIvec=%04X 13B6=%04X", FRAME, v, w16(0x13B6))); lastVec = v; shot(string.format("vec-%05d", FRAME)) end
  if inGameplay() then
    if FRAME - lastGame > 30 then print(string.format("F%d gameplay resumes after %d frames", FRAME, FRAME - lastGame)); shot(string.format("resume-%05d", FRAME)) end
    lastGame = FRAME; gapReported = false
  elseif not gapReported and FRAME - lastGame > 1500 then
    gapReported = true
    local s = emu.getState()
    print(string.format("F%d NO GAMEPLAY for 1500 frames; PC=%02X:%04X INIDISP?=%s 01DC=%04X", FRAME, s["cpu.k"], s["cpu.pc"], tostring(s["ppu.forcedBlank"]), v))
    shot(string.format("stall-%05d", FRAME))
  end
  if FRAME % 600 == 0 then shot(string.format("t-%05d", FRAME)) end
  if FRAME >= END_ then emu.stop(0) end
end, emu.eventType.endFrame)
