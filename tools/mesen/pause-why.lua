-- Why does Start not pause in some stage states? From a stage state, logs every 50 frames the NMI vector $01DC,
-- the pause flags $13B4/$13B5, whether the gameplay joypad mirror ran, and the joypad mirror value; presses Start
-- at PRESS and logs writes to $13B4/$13B5 (PC, value). Defines: PRESS (default 300), FRAMES (default 600).
local PRESS_ = PRESS or 300
local FRAMES_ = FRAMES or 600
loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end)
playInputs({ { PRESS_, PRESS_ + 6, { start = true } } })
local mirror = 0
emu.addMemoryCallback(function() mirror = mirror + 1 end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
local function onWrite(address, value)
  local s = emu.getState()
  print(string.format("WRITE frame=%d addr=$%04X value=$%02X pc=$%02X%04X", FRAME, address & 0xFFFF, value, s["cpu.k"], s["cpu.pc"]))
end
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x0013B4, 0x0013B5, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(onWrite, emu.callbackType.write, 0x7E13B4, 0x7E13B5, emu.cpuType.snes, emu.memType.snesMemory)
emu.addEventCallback(function()
  if FRAME % 50 == 0 or (FRAME >= PRESS_ and FRAME <= PRESS_ + 8) then
    print(string.format("F=%d $01DC=$%04X $13B4=$%02X $13B5=$%02X mirrorRuns=%d pad=$%04X gameplay=%s", FRAME, w16(0x01DC), w8(0x13B4), w8(0x13B5), mirror, w16(0x1A6F), tostring(inGameplay())))
  end
  if FRAME == PRESS_ + 60 then shot("after-start") end
  if FRAME >= FRAMES_ then emu.stop(0) end
end, emu.eventType.endFrame)
