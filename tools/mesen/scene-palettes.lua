-- Sprite palette usage of a scene (research tool): which OAM palettes Mr. Nutz (tiles < $50, name table 0) and the
-- other visible sprites use, and the PPU colour-math state, logged on every change. Mr. Nutz is invulnerable and
-- jumps around (random, SEED) so the boss keeps attacking. Defines: END (default 1800), SEED.
local END_ = END or 1800
math.randomseed(SEED or 1)
loadStateOnBoot()
local dir, left = true, 0
emu.addEventCallback(function()
  if left <= 0 then dir = math.random() < 0.5; left = 20 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ left = dir, right = not dir, b = FRAME % 40 < 20, y = FRAME % 30 < 3 }, 0)
end, emu.eventType.inputPolled)
local otherAll, nutzAll, lastMath = {}, {}, ""
emu.addEventCallback(function()
  ww(0x008D, 0x2D); ww(0x1889, 0xB5); ww(0x188A, 0xA3)
  if not inGameplay() then return end
  local other, nutz = {}, {}
  for i = 0, 127 do
    if oam(i, 1) < 224 then
      local attr = oam(i, 3)
      local pal = (attr >> 1) & 7
      local tile = oam(i, 2) | ((attr & 1) << 8)
      if tile < 0x50 then nutz[pal] = true else other[pal] = (other[pal] or 0) + 1 end
    end
  end
  for p in pairs(other) do if not otherAll[p] then otherAll[p] = FRAME; print(string.format("F%d other sprites start using palette %d", FRAME, p)) end end
  for p in pairs(nutz) do if not nutzAll[p] then nutzAll[p] = FRAME; print(string.format("F%d tiles<$50 on palette %d", FRAME, p)) end end
  local s = emu.getState()
  local m = string.format("enabled=%s addSub=%s halve=%s subtract=%s sub=%s", tostring(s["ppu.colorMathEnabled"]),
    tostring(s["ppu.colorMathAddSubscreen"]), tostring(s["ppu.colorMathHalveResult"]), tostring(s["ppu.colorMathSubtractMode"]),
    tostring(s["ppu.subScreenLayers"]))
  if m ~= lastMath then print(string.format("F%d MATH %s", FRAME, m)); lastMath = m end
  if FRAME % 300 == 0 then shot(string.format("f%04d", FRAME)) end
  if FRAME >= END_ then
    local o = {}
    for p = 0, 7 do if otherAll[p] then o[#o + 1] = tostring(p) end end
    print("RESULT other palettes: " .. table.concat(o, ","))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
