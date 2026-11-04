-- Fast per-stage check of the runtime palette patch, from a state made by prepare-stages.lua.
-- Selects fur 2 / outfit 3 with the real shortcuts, runs an action cycle with every button except L/R/Select
-- (walk, run, jump, Y/X/A, crouch, look up, back), pauses once, and applies nutzOracle() to every gameplay frame.
-- Prints one "RESULT ..." line; tools/mesen/sweep.ts aggregates and fails on any violation.
-- Run on output/Mr. Nutz.runtime.sfc via npm run sweep:all (or sweep:stage -- --only NN).
local FUR_SEL, OUTFIT_SEL = 2, 3
local CHECK_FROM, END_AT = 70, 930

loadStateOnBoot(function() ww(0x1EC9, w8(0x1EC9) & 0xFE) end) -- debug stage skip off: Select+R must not warp

local cycle = {
  { 0, 60, { right = true } }, { 60, 64, { right = true, b = true } }, { 64, 90, { right = true } },
  { 90, 94, { y = true } }, { 100, 104, { x = true } }, { 110, 114, { a = true } },
  { 120, 160, { down = true } }, { 160, 180, { up = true } }, { 180, 220, { left = true } },
  { 220, 224, { b = true } }, { 224, 240, { right = true, y = true } },
}
local steps = {
  { 10, 14, { select = true, l = true } }, { 20, 24, { select = true, l = true } },
  { 30, 34, { select = true, r = true } }, { 40, 44, { select = true, r = true } }, { 50, 54, { select = true, r = true } },
  { 800, 804, { start = true } }, { 860, 864, { start = true } },
}
for c = 0, 2 do
  for _, s in ipairs(cycle) do steps[#steps + 1] = { 70 + c * 240 + s[1], 70 + c * 240 + s[2], s[3] } end
end
playInputs(steps)

local r = { gameplay = 0, nutzFrames = 0, ok = 0, lostRun = 0, lostMax = 0, sharedChanged = 0, foreignOnX = 0, noSlot = 0 }
local events, slots = {}, {}
-- VBlank budget: the game enables HDMA ($420C) late in its NMI. If that write lands in active display
-- (scanline < 225) HDMA starts from a stale state and writes garbage into CGRAM (seen when the hook was too slow).
local hdma = { late = 0, maxLine = 0 }
local function onHdmaEnable(address, value)
  if value == 0 or FRAME < CHECK_FROM or FRAME >= END_AT then return end
  local line = emu.getState()["ppu.scanline"]
  if line < 225 then
    hdma.late = hdma.late + 1
    if hdma.late == 1 then print("HDMA_LATE frame=" .. FRAME .. " scanline=" .. line) end
  elseif line > hdma.maxLine then
    hdma.maxLine = line
  end
end
for _, b in ipairs({ 0x00, 0x80 }) do
  emu.addMemoryCallback(onHdmaEnable, emu.callbackType.write, b * 0x10000 + 0x420C, b * 0x10000 + 0x420C, emu.cpuType.snes, emu.memType.snesMemory)
end
local function event(kind, text)
  if events[kind] then return end
  events[kind] = true
  print(kind .. " frame=" .. FRAME .. " " .. text)
  shot("event-" .. kind:lower())
end

emu.addEventCallback(function()
  if FRAME == CHECK_FROM then
    local f, o = w8(NUTZ.fur), w8(NUTZ.outfit)
    if f ~= FUR_SEL or o ~= OUTFIT_SEL then event("SHORTCUT_FAIL", "idx=" .. f .. "/" .. o) end
  end
  if FRAME == 200 or FRAME == 500 or FRAME == 830 then shot(string.format("f%04d", FRAME)) end
  if FRAME >= CHECK_FROM and FRAME < END_AT and inGameplay() then
    r.gameplay = r.gameplay + 1
    local o = nutzOracle()
    if o.noSlot then
      r.noSlot = r.noSlot + 1
    else
      slots[o.S .. "/" .. o.X] = true
      if o.sharedChanged then
        r.sharedChanged = r.sharedChanged + 1
        event("SHARED_CHANGED", "S=" .. o.S .. " entry=" .. o.sharedEntry .. " pal=" .. paletteLine(0x80 + o.S * 16))
      end
      if o.foreignOnX > 0 then
        r.foreignOnX = r.foreignOnX + 1
        event("FOREIGN_ON_X", "X=" .. o.X .. " sprites=" .. o.foreignOnX)
      end
      if o.nutz > 0 then
        r.nutzFrames = r.nutzFrames + 1
        if o.nutzOk then r.ok = r.ok + 1; r.lostRun = 0 else r.lostRun = r.lostRun + 1 end
        if r.lostRun > r.lostMax then r.lostMax = r.lostRun end
      end
    end
  end
  if FRAME >= END_AT + 6 then
    local s = {}
    for k in pairs(slots) do s[#s + 1] = k end
    table.sort(s)
    print(string.format("RESULT gameplay=%d nutzFrames=%d ok=%d lostMax=%d sharedChanged=%d foreignOnX=%d noSlot=%d hdmaLate=%d hdmaMaxLine=%d slots=%s idx=%d/%d",
      r.gameplay, r.nutzFrames, r.ok, r.lostMax, r.sharedChanged, r.foreignOnX, r.noSlot, hdma.late, hdma.maxLine, table.concat(s, ","), w8(NUTZ.fur), w8(NUTZ.outfit)))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
