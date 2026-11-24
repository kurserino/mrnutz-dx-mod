-- Go-Explore style stage explorer (research tool, emulator RAM only). Keeps one savestate per visited cell of the
-- stage (CELL px), repeatedly restores a rarely chosen cell and plays random inputs for EPISODE frames. Cheats while
-- exploring: invulnerability ($8D=$2D), infinite jump ($8E=$FF), lives held (word $1889 = $A3B5).
-- Goals (exec callbacks):
--   KEY   $81:B9E8   golden-key pickup (item type 3: sound $11, then $9D:EF10 arms the house door, $0584=$86DC)
--   DOOR  $9D:EFC9   house door: the armed check ($9D:EFA5, via $0584/$81:86E1) starts the iris wipe ($0572=$CEB3)
-- On KEY the archive restarts from that state (the door only exists with the key). On DOOR (or GOAL=1 reached) the
-- state a few frames before is saved as "STATE <SAVENAME> ..." for tools/mesen/run.ts and the run stops.
-- Random actions include attack taps (Y). New entries of the item list ($1AE0, $20 bytes, type = byte $0A & $0F)
-- are logged as ITEM.
-- TELEPORT (percent chance per episode, default off): jump to a random point (TXMAX/TYMAX) and let the camera
-- follow for 8 episodes, to seed regions that walking does not reach.
-- Cell choice favours rarely chosen cells and frontier cells (unvisited neighbours, weight FRONTIER).
-- Archiving starts at frame START (default 90), after the stage message box is dismissed.
-- Defines: END (frames, default 60000), CELL (default 48), EPISODE (default 90), SEED, SAVENAME code (1 = house-key,
-- 2 = house-door).
local END_, CELL_, EPISODE_ = END or 60000, CELL or 48, EPISODE or 90
math.randomseed(SEED or 1)
loadStateOnBoot()
local archive, order = {}, {}
local stage = "key"
local want = nil -- "save" / "load"
local loadKey, episodeLeft, action, actionLeft = nil, 0, {}, 0
local hist, ring = {}, 0
local finished = false
local function cellOf() return string.format("%d,%d", w16(0x37) // CELL_, w16(0x39) // CELL_) end
local function hexs(s) return (s:gsub(".", function(c) return string.format("%02X", string.byte(c)) end)) end
local function reset(reason)
  archive, order = {}, {}
  print(string.format("F%d RESET archive (%s) at %d,%d", FRAME, reason, w16(0x37), w16(0x39)))
end
local function pick()
  local best, bestScore = nil, -1
  for _, k in ipairs(order) do
    local c = archive[k]
    local cx, cy = k:match("(%d+),(%d+)")
    cx, cy = tonumber(cx), tonumber(cy)
    local open = 0
    for dx = -1, 1 do for dy = -1, 1 do
      if not archive[string.format("%d,%d", cx + dx, cy + dy)] then open = open + 1 end
    end end
    local s = 1 / math.sqrt(c.chosen + 1) + (FRONTIER or 0.15) * open + math.random() * 0.3
    if s > bestScore then best, bestScore = k, s end
  end
  return best
end
local function newAction()
  local a = {}
  local r = math.random()
  if r < 0.4 then a.right = true elseif r < 0.8 then a.left = true end
  local jumpy = math.random() < 0.6
  local down = math.random() < 0.1
  local up = math.random() < 0.15
  local attack = math.random() < 0.35
  return { dirs = a, jumpy = jumpy, down = down, up = up, attack = attack }, 8 + math.random(0, 16)
end
-- AREA2=1: first take the stage's area exit (iris wipe, as $81:D4AA-$81:D4CB) to reach area $0550.
emu.addEventCallback(function()
  if AREA2 == 1 and FRAME == 60 then
    ww(0x58, 0); ww(0x59, 0); ww(0x183F, 1); ww(0xA6, 1); ww(0x8C, 0); ww(0x0572, 0xB3); ww(0x0573, 0xCE)
  end
end, emu.eventType.endFrame)
emu.addEventCallback(function()
  if FRAME < 40 then emu.setInput(FRAME % 8 < 4 and { b = true } or {}, 0); return end
  if actionLeft <= 0 then action, actionLeft = newAction() end
  actionLeft = actionLeft - 1
  local t = {}
  for k, v in pairs(action.dirs) do t[k] = v end
  if action.jumpy and FRAME % 6 < 3 then t.b = true end
  if action.down then t.down = true end
  if action.up then t.up = true end
  if action.attack and FRAME % 10 < 3 then t.y = true end
  emu.setInput(t, 0)
end, emu.eventType.inputPolled)
-- Savestate work must run inside an exec callback: the joypad mirror $81:828A runs once per gameplay frame.
emu.addMemoryCallback(function()
  if finished or FRAME < (START or 90) then return end
  ww(0x008D, 0x2D); ww(0x008E, 0xFF); ww(0x1889, 0xB5); ww(0x188A, 0xA3)
  ring = ring % 8 + 1
  if FRAME % 4 == 0 then hist[ring] = emu.createSavestate() end
  if want == "load" and loadKey then
    want = nil
    emu.loadSavestate(archive[loadKey].state)
    episodeLeft = EPISODE_
    return
  end
  local k = cellOf()
  if not archive[k] then
    archive[k] = { state = emu.createSavestate(), chosen = 0 }
    order[#order + 1] = k
  end
  episodeLeft = episodeLeft - 1
  if episodeLeft <= 0 and TELEPORT and math.random(100) <= TELEPORT then
    -- Seed far regions: teleport (released, falls to the ground) to a random point of the stage.
    local tx, ty = math.random(0, TXMAX or 4600), math.random(0, TYMAX or 1300)
    ww(0x5C, 0); ww(0x5D, 0); local lo = (tx << 4) & 0xFFFF; ww(0x5A, lo & 0xFF); ww(0x5B, lo >> 8)
    ww(0x39, ty & 0xFF); ww(0x3A, ty >> 8); ww(0x60, 0); ww(0x61, 0)
    episodeLeft = EPISODE_ * 8
    return
  end
  if episodeLeft <= 0 and #order > 0 then
    loadKey = pick()
    archive[loadKey].chosen = archive[loadKey].chosen + 1
    want = "load"
  end
end, emu.callbackType.exec, 0x81828A, 0x81828A, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if finished or stage ~= "key" then return end
  stage = "door"
  print(string.format("F%d KEY picked at %d,%d cells=%d", FRAME, w16(0x37), w16(0x39), #order))
  if SAVENAME == 1 then print(string.format("STATE house-key-s%d %s", SEED or 1, hexs(emu.createSavestate()))) end
  reset("key")
  shot("key")
end, emu.callbackType.exec, 0x81B9E8, 0x81B9E8, emu.cpuType.snes, emu.memType.snesMemory)
emu.addMemoryCallback(function()
  if finished then return end
  print(string.format("F%d DOOR wipe at %d,%d stage=%s", FRAME, w16(0x37), w16(0x39), stage))
  -- The savestate from a few frames earlier (before the wipe started) is the reproduction point.
  local oldest = hist[ring % 8 + 1] or hist[ring]
  if SAVENAME == 2 and oldest then print(string.format("STATE house-door-s%d %s", SEED or 1, hexs(oldest))) end
  shot("door")
  finished = true
end, emu.callbackType.exec, 0x9DEFC9, 0x9DEFC9, emu.cpuType.snes, emu.memType.snesMemory)
-- SOUNDSTATES=1: also save a state ("sound<id>-s<SEED>") a few frames before each new sound id.
-- Generic signals: main-loop requests ($13B6, except death $80:825C), scene changes, and the first time each sound
-- effect id (Y of JSL $8A80FC) plays, with the position. A request other than death saves "STATE transit-s<SEED>".
local sounds, lastScene = {}, -1
emu.addMemoryCallback(function()
  local y = emu.getState()["cpu.y"]
  if not sounds[y] and FRAME > (START or 90) then
    sounds[y] = true; print(string.format("F%d SOUND %04X at %d,%d", FRAME, y, w16(0x37), w16(0x39)))
    if SOUNDSTATES == 1 and hist[ring] then print(string.format("STATE sound%02X-s%d %s", y & 0xFF, SEED or 1, hexs(hist[ring % 8 + 1] or hist[ring]))); shot(string.format("sound%02X", y & 0xFF)) end
  end
end, emu.callbackType.exec, 0x8A80FC, 0x8A80FC, emu.cpuType.snes, emu.memType.snesMemory)
for _, bk in ipairs({ 0x00, 0x7E }) do
  emu.addMemoryCallback(function(a, v)
    local req = v * 256 + w8(0x13B6)
    if finished or req == 0 or req == 0x825C or FRAME <= (START or 90) then return end
    print(string.format("F%d REQUEST %04X at %d,%d stage=%s", FRAME, req, w16(0x37), w16(0x39), stage))
    local oldest = hist[ring % 8 + 1] or hist[ring]
    if oldest then print(string.format("STATE transit-s%d %s", SEED or 1, hexs(oldest))) end
    shot("request")
    finished = true
  end, emu.callbackType.write, bk * 0x10000 + 0x13B7, bk * 0x10000 + 0x13B7, emu.cpuType.snes, emu.memType.snesMemory)
end
emu.addEventCallback(function()
  local sc = w8(0x560) * 0x10000 + w16(0x55E)
  if sc ~= lastScene then print(string.format("F%d SCENE %06X at %d,%d", FRAME, sc, w16(0x37), w16(0x39))); lastScene = sc end
  -- Trigger zones ($18F7 list, 12 bytes: type word, x1, y1, x2, y2, map flag address).
  local a = 0x18F7
  for i = 0, 30 do
    if w16(a) == 0 then break end
    local key = string.format("T%04X/%d/%d", w16(a), w16(a + 2), w16(a + 4))
    if not sounds[key] then
      sounds[key] = true
      print(string.format("F%d TRIG type=%04X x=%d..%d y=%d..%d at %d,%d", FRAME, w16(a), w16(a + 2), w16(a + 6), w16(a + 4), w16(a + 8), w16(0x37), w16(0x39)))
    end
    a = a + 12
  end
end, emu.eventType.endFrame)
local itemsSeen = {}
emu.addEventCallback(function()
  for k = 0, 7 do
    local b = 0x1AE0 + k * 0x20
    if w16(b) == 0 then break end
    local key = string.format("%04X%04X%04X", w16(b), w16(b + 2), w16(b + 4))
    if not itemsSeen[key] and w8(b + 0x0A) & 0x0F ~= 0x0E then
      itemsSeen[key] = true
      print(string.format("F%d ITEM type=%X raw=%04X %04X %04X at %d,%d", FRAME, w8(b + 0x0A) & 0x0F, w16(b), w16(b + 2), w16(b + 4), w16(0x37), w16(0x39)))
    end
  end
  if FRAME % 3000 == 0 then
    print(string.format("F%d stage=%s cells=%d at %d,%d", FRAME, stage, #order, w16(0x37), w16(0x39)))
  end
  if finished and not stopAt then stopAt = FRAME + 8 end
  for k = 0, 15 do
    local b = 0x1AE0 + k * 0x20
    if w16(b) == 0 then break end
    if w8(b + 0x0A) & 0x0F == 3 and not itemsSeen["c3"] then itemsSeen["c3"] = true; print(string.format("F%d CLASS3 item at %d,%d", FRAME, w16(0x37), w16(0x39))) end
  end
  if (stopAt and FRAME >= stopAt) or FRAME >= END_ then
    for _, k in ipairs(order) do print("CELL " .. k) end
    print(string.format("RESULT stage=%s cells=%d frames=%d", stage, #order, FRAME))
    emu.stop(0)
  end
end, emu.eventType.endFrame)
