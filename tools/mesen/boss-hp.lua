-- Boss health search (research tool, emulator RAM only). Mr. Nutz is invulnerable ($8D=$2D, lives held) and keeps
-- jumping left and right in the boss room, so he lands on the boss's head now and then. WRAM $0000-$7FFF is sampled
-- every SAMPLE frames; at the end the script prints the bytes that never rose, fell at least MINDROPS times and
-- started above 0 (boss health candidates), with their value history. Requests ($13B6) are logged (boss defeated ->
-- stage end). Defines: END (default 6000), SAMPLE (default 10), MINDROPS (default 2), SEED, HOLD (hex WRAM address
-- written with HOLDV every frame, to test a candidate).
local END_, SAMPLE_, MIN_ = END or 6000, SAMPLE or 10, MINDROPS or 2
math.randomseed(SEED or 1)
local function cheats()
  ww(0x008D, 0x2D); ww(0x1889, 0xB5); ww(0x188A, 0xA3)
  if INFJUMP == 1 then ww(0x008E, 0xFF) end
  if HOLD then ww(HOLD, HOLDV or 0) end
end
-- PAR: a Pro Action Replay code (integer, e.g. 0x7E19B501 written in decimal) added to Mesen's own cheat engine,
-- which, like ares, answers the CPU reads with the code value. Called at the top level, addCheat hangs Mesen 2.2.1
-- headless; it is added right after the state load (inside an exec callback).
loadStateOnBoot(function()
  cheats()
  if PAR then
    local ok, err = pcall(emu.addCheat, emu.cheatType.snesProActionReplay, string.format("%08X", PAR))
    print(string.format("ADDCHEAT %08X ok=%s %s", PAR, tostring(ok), tostring(err)))
  end
end)
emu.addMemoryCallback(cheats, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
local dir, left = true, 0
emu.addEventCallback(function()
  if left <= 0 then dir = math.random() < 0.5; left = 30 + math.random(0, 40) end
  left = left - 1
  if INFJUMP == 1 then emu.setInput({ left = dir, right = not dir, b = FRAME % 6 < 3 and FRAME % 200 < 120 }, 0); return end
  emu.setInput({ left = dir, right = not dir, b = FRAME % 40 < 20 }, 0)
end, emu.eventType.inputPolled)
for _, bk in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(_, v)
    print(string.format("F%d REQUEST %02X%02X", FRAME, v, w8(0x13B6))); shot(string.format("req%d", FRAME))
  end, emu.callbackType.write, bk * 0x10000 + 0x13B7, bk * 0x10000 + 0x13B7, emu.cpuType.snes, emu.memType.snesMemory)
end
local first, last, drops, rose, hist = {}, {}, {}, {}, {}
emu.addEventCallback(function()
  cheats()
  if FRAME >= 60 and FRAME % SAMPLE_ == 0 and inGameplay() then
    for a = 0, 0x7FFF do
      local v = w8(a)
      if first[a] == nil then first[a] = v; last[a] = v; drops[a] = 0; hist[a] = tostring(v)
      elseif v ~= last[a] then
        if v < last[a] then drops[a] = drops[a] + 1 else rose[a] = true end
        if #hist[a] < 120 then hist[a] = hist[a] .. ">" .. v end
        last[a] = v
      end
    end
  end
  if FRAME % 600 == 0 then
    shot(string.format("f%05d", FRAME))
    print(string.format("F%d hp19A3=%d bar1ED4=%d x=%d y=%d", FRAME, w8(0x19A3), w8(0x1ED4), w16(0x37), w16(0x39)))
  end
  if FRAME == END_ then
    for a = 0, 0x7FFF do
      if first[a] and first[a] > 0 and not rose[a] and drops[a] >= MIN_ then
        print(string.format("CAND $%04X drops=%d %s", a, drops[a], hist[a]))
      end
    end
    print("RESULT done")
  end
  if FRAME >= END_ + 6 then emu.stop(0) end
end, emu.eventType.endFrame)
