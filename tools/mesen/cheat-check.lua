-- Checks the ares cheat codes of the user's cheat file (C:\Snes\...cheats.bml) in Mesen, emulator RAM only.
-- ares applies a RAM cheat on every CPU read; here the bytes are written at the start of each gameplay frame
-- ($81:828A) and at the end of each frame, which the game sees the same way on its next read.
-- CHEAT (define): 0 none (control), 1 super jump 7E0091:00, 2 infinite jump 7E008E:FF, 3 invulnerability 7E008D:2D,
--   4 lives x9 7E1889:BE+7E188A:A3, 5 nuts 7E0A29:99, 6 coins 7E1894:99, 7 one-hit bosses 7E05D0:00,
--   8 stage skip 7E1EC9:01 (R pressed at frame RAT, default 120).
-- INPUT: 0 random play (walk mostly right, jumps, Y attacks; SEED), 1 jump test (stand, then press B at frame 60
--   and hold, press again in the air), 2 idle.
-- Logs per LOGEVERY frames: energy $05A2, lives (word $1889 XOR $A3B7), nuts $0A29, coins $1894, $05D0, stage $054C,
-- Y $39. Counts energy drops, life losses ($81:D14A), main-loop requests ($13B6) and the jump peak.
local CODES = {
  [1] = { { 0x0091, 0x00 } },
  [2] = { { 0x008E, 0xFF } },
  [3] = { { 0x008D, 0x2D } },
  [4] = { { 0x1889, 0xBE }, { 0x188A, 0xA3 } },
  [5] = { { 0x0A29, 0x99 } },
  [6] = { { 0x1894, 0x99 } },
  [7] = { { 0x05D0, 0x00 } },
  [8] = { { 0x1EC9, 0x01 } },
}
local END_, EVERY, MODE = END or 1800, LOGEVERY or 120, INPUT or 0
local code = {}
for _, c in ipairs(CODES[CHEAT or 0] or {}) do code[#code + 1] = c end
-- CHEAT2: a second code held together with CHEAT (e.g. invulnerability while testing a boss).
for _, c in ipairs(CODES[CHEAT2 or 0] or {}) do code[#code + 1] = c end
math.randomseed(SEED or 1)
local function hold() for _, c in ipairs(code) do ww(c[1], c[2]) end end
loadStateOnBoot(hold)
emu.addMemoryCallback(hold, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
local action, left = {}, 0
emu.addEventCallback(function()
  if CHEAT == 8 and FRAME >= (RAT or 120) and FRAME < (RAT or 120) + 4 then emu.setInput({ r = true }, 0); return end
  if MODE == 2 then return end
  if MODE == 1 then
    if FRAME >= 60 and FRAME < 90 then emu.setInput({ b = true }, 0)
    elseif FRAME >= 95 and FRAME < 125 then emu.setInput({ b = true }, 0)
    elseif FRAME >= 130 and FRAME < 160 then emu.setInput({ b = true }, 0) end
    return
  end
  if FRAME < 40 then emu.setInput(FRAME % 8 < 4 and { b = true } or {}, 0); return end
  if left <= 0 then
    local r = math.random()
    action = { right = r < 0.7, left = r >= 0.85, jump = math.random() < 0.5, atk = math.random() < 0.5 }
    left = 10 + math.random(0, 20)
  end
  left = left - 1
  emu.setInput({ right = action.right, left = action.left, b = action.jump and FRAME % 12 < 6,
    y = action.atk and FRAME % 10 < 3 }, 0)
end, emu.eventType.inputPolled)
local deaths, hits, lastEnergy, groundY, peak = 0, 0, -1, -1, 0
emu.addMemoryCallback(function()
  deaths = deaths + 1
  print(string.format("F%d DEATH lives=%04X x=%d y=%d invuln8D=%02X", FRAME, w16(0x1889) ~ 0xA3B7, w16(0x37), w16(0x39), w8(0x8D))); shot("death" .. deaths)
end, emu.callbackType.exec, 0x81D14A, 0x81D14A, emu.cpuType.snes, emu.memType.snesMemory)
for _, bk in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(_, v)
    print(string.format("F%d REQUEST %02X%02X stage=%02X", FRAME, v, w8(0x13B6), w8(0x054C)))
  end, emu.callbackType.write, bk * 0x10000 + 0x13B7, bk * 0x10000 + 0x13B7, emu.cpuType.snes, emu.memType.snesMemory)
end
local function status(tag)
  return string.format("%s energy=%d lives=%04X nuts=%02X coins=%02X r05D0=%02X stage=%02X x=%d y=%d gameplay=%s",
    tag, w8(0x05A2), w16(0x1889) ~ 0xA3B7, w8(0x0A29), w8(0x1894), w8(0x05D0), w8(0x054C), w16(0x37), w16(0x39),
    tostring(inGameplay()))
end
emu.addEventCallback(function()
  hold()
  local e = w8(0x05A2)
  if inGameplay() then
    if lastEnergy >= 0 and e < lastEnergy then hits = hits + 1; print(string.format("F%d HIT energy %d->%d", FRAME, lastEnergy, e)) end
    lastEnergy = e
    if MODE == 1 then
      if FRAME == 55 then groundY = w16(0x39) end
      if groundY >= 0 and groundY - w16(0x39) > peak then peak = groundY - w16(0x39) end
    end
  end
  if FRAME == 1 then print(status("F1")) end
  if FRAME % EVERY == 0 then print(status("F" .. FRAME)) end
  if FRAME == 30 or FRAME == END_ // 2 or FRAME == END_ then shot(string.format("f%04d", FRAME)) end
  if MODE == 1 and FRAME == 100 then shot("jump") end
  if FRAME == END_ then
    print(string.format("RESULT cheat=%d hits=%d deaths=%d jumpPeak=%d %s", CHEAT or 0, hits, deaths, peak, status("end")))
  end
  if FRAME >= END_ + 6 then emu.stop(0) end
end, emu.eventType.endFrame)
