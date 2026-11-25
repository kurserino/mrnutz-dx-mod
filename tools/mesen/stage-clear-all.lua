-- Stage Clear check for one stage state (research/regression tool). After the state load (save record with SAVEFUR,
-- outfit 0), the debug stage skip (emulator RAM only: $1EC9 bit 0 + R at frame 60) ends the stage. The game shows
-- STAGE CLEAR only when the next entry of the stage list $99:E65F is $FFFF (end of a world: $80:82D4 -> $82:82D5
-- JSL $9DE2AE); other stages go straight to the next stage. A boss health PAR code can be given instead. When the Stage Clear table $82:D474 is active and the screen is lit,
-- the script checks which sprite slots hold the selection and which hold $85:9CC0, and the OAM palettes.
-- RESULT reached=<frame|-1> sel=<slots> orig=<slots> oam=<palettes>. Defines: END (default 3000), SAVEFUR, PAR, SEED.
loadStateOnBoot(function()
  local fur, outfit = SAVEFUR or 1, 0
  local w0, w2, w4 = 0x5A4E, 0x01 | (fur << 8), outfit
  local ck = 0xFFFF ~ ((w0 + w2 + w4) & 0xFFFF)
  local rec = { 0x4E, 0x5A, 0x01, fur, outfit, 0x00, ck & 0xFF, ck >> 8 }
  for i = 1, 8 do emu.write(0x100 + i - 1, rec[i], emu.memType.snesSaveRam) end
  if PAR then emu.addCheat(emu.cheatType.snesProActionReplay, string.format("%08X", PAR)) end
end)
math.randomseed(SEED or 1)
local dir, left = true, 0
emu.addEventCallback(function()
  if not PAR then return end
  if left <= 0 then dir = math.random() < 0.5; left = 30 + math.random(0, 40) end
  left = left - 1
  emu.setInput({ left = dir, right = not dir, b = FRAME % 40 < 20 }, 0)
end, emu.eventType.inputPolled)
local reached, inidisp, done = -1, 0, false
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(function(_, v) inidisp = v end, emu.callbackType.write, b * 0x10000 + 0x2100, b * 0x10000 + 0x2100, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  if PAR then return end
  if FRAME == 55 then ww(0x1EC9, w8(0x1EC9) | 1) end
  if FRAME >= 60 and FRAME < 64 then emu.setInput({ r = true }, 0) end
  if FRAME == 70 then ww(0x1EC9, w8(0x1EC9) & 0xFE) end
end, emu.eventType.inputPolled)
emu.addMemoryCallback(function() ww(0x008D, 0x2D) end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
local function slotsWith(f)
  local t = {}
  for s = 0, 7 do if f(s) then t[#t + 1] = tostring(s) end end
  return table.concat(t, ",")
end
emu.addEventCallback(function()
  local scene = w8(0x0560) * 0x10000 + w16(0x055E)
  if scene == 0x82D474 and reached < 0 then reached = FRAME; print(string.format("F%d STAGECLEAR table", FRAME)) end
  if reached >= 0 and not done and FRAME >= reached + 200 and (inidisp & 0x8F) == 0x0F then
    done = FRAME
    local eOut, eFur = expectedColours()
    local sel = slotsWith(function(s) return cg(0x80 + s * 16 + 6) == eOut and cg(0x80 + s * 16 + 15) == eFur end)
    local orig = slotsWith(function(s)
      local n = 0
      for e = 1, 15 do if cg(0x80 + s * 16 + e) == bus16(0x859CC0 + e * 2) then n = n + 1 end end
      return n == 15
    end)
    local pals = {}
    for i = 0, 127 do
      if oam(i, 1) < 224 then
        local p = (oam(i, 3) >> 1) & 7
        local tile = oam(i, 2) | ((oam(i, 3) & 1) << 8)
        local k = p .. (tile < 0x50 and "n" or "")
        pals[k] = (pals[k] or 0) + 1
      end
    end
    local pl = {}
    for k, n in pairs(pals) do pl[#pl + 1] = k .. "x" .. n end
    table.sort(pl)
    print(string.format("RESULT reached=%d sel=[%s] orig=[%s] oam=%s", reached, sel, orig, table.concat(pl, " ")))
    shot("stageclear")
  end
  if FRAME == (END or 3000) - 8 and not done then shot("end") end
  if FRAME >= (END or 3000) or (done and FRAME >= done + 8) then
    if not done then print(string.format("RESULT reached=%d sel=[] orig=[] oam=none stage=%02X", reached, w8(0x054C))) end
    emu.stop(0)
  end
end, emu.eventType.endFrame)
