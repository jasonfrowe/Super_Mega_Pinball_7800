-- Multi-ball & Lock Chute qualification test script for Super Mega Pinball 7800
local f = 0
local mem = nil
local fields = {}
local held = {}

local log_file = io.open("test_multiball.log", "w")

emu.register_frame_done(function()
  f = f + 1
  if not mem then
    mem = manager:machine().devices[":maincpu"].spaces["program"]
    for tag, port in pairs(manager:machine():ioport().ports) do
      if tag:find("joy2") == nil then
        for name, field in pairs(port.fields) do
          fields[name] = field
        end
      end
    end
  end

  for name, _ in pairs(held) do
    if fields[name] then fields[name]:set_value(1) end
  end

  -- Start game at F=180
  if f == 180 then
    held["P1 Button 1"] = true
  elseif f == 200 then
    held["P1 Button 1"] = nil
    if fields["P1 Button 1"] then fields["P1 Button 1"]:set_value(0) end
  end

  -- TEST A: UNLIT LOCK CHUTE (F=250)
  -- Ball enters Upper-Right Lock Chute (X=106, Y=65) while lock is unlit (pb_lock_lit=0)
  if f == 250 then
    log_file:write("--- TEST A: UNLIT LOCK CHUTE ENTRY (X=106, Y=65, LIT=0) ---\n")
    mem:write_u8(0x2300, 1)    -- pb_state = 1
    mem:write_u8(0x2301, 3)    -- pb_balls_left = 3
    mem:write_u8(0x2303, 0)    -- pb_locks = 0
    mem:write_u8(0x233c, 0)    -- pb_lock_lit = 0
    mem:write_u8(0x2305, 0)    -- pb_drops = 0
    mem:write_u8(0x2310, 1)    -- ball_act[0] = 1
    mem:write_u8(0x2316, 106)  -- ball_xi[0] = 106 (inside lock chute)
    mem:write_u8(0x231c, 65)   -- ball_yl[0] = 65
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)    -- moving down into chute
  end

  -- TEST B: QUALIFYING LOCK BY HITTING 4 CENTER CARDS (F=320)
  -- Hit cards 0, 1, 2, 3 in succession
  if f == 320 then
    log_file:write("--- TEST B: KNOCKING DOWN 4 CENTER CARDS ---\n")
    -- Simulate ball hitting card 0 (X=44, Y=165)
    mem:write_u8(0x2316, 44)
    mem:write_u8(0x231c, 165)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  elseif f == 340 then
    -- Hit card 1 (X=60, Y=165)
    mem:write_u8(0x2316, 60)
    mem:write_u8(0x231c, 165)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  elseif f == 360 then
    -- Hit card 2 (X=76, Y=165)
    mem:write_u8(0x2316, 76)
    mem:write_u8(0x231c, 165)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  elseif f == 380 then
    -- Hit card 3 (X=92, Y=165) -> SHOULD LIGHT LOCK!
    mem:write_u8(0x2316, 92)
    mem:write_u8(0x231c, 165)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  end

  -- TEST C: FIRST LOCK WHILE LIT (F=420)
  if f == 420 then
    log_file:write("--- TEST C: FIRST LOCK IN CHUTE WHILE LIT ---\n")
    mem:write_u8(0x2316, 106)
    mem:write_u8(0x231c, 65)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  end

  -- TEST D: SECOND LOCK TRIGGERING MULTIBALL (F=480)
  -- After locking 1, player qualifies again and locks 2nd ball!
  if f == 480 then
    log_file:write("--- TEST D: SECOND LOCK TRIGGERING MULTI-BALL MANIA ---\n")
    mem:write_u8(0x233c, 1)    -- pb_lock_lit = 1
    mem:write_u8(0x2316, 106)
    mem:write_u8(0x231c, 65)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  end

  if f >= 245 and f <= 530 and f % 5 == 0 then
    local state = mem:read_u8(0x2300)
    local balls_left = mem:read_u8(0x2301)
    local locks = mem:read_u8(0x2303)
    local drops = mem:read_u8(0x2305)
    local lock_lit = mem:read_u8(0x233c)
    local bx0 = mem:read_u8(0x2316)
    local by0 = mem:read_u8(0x231c) + 256 * mem:read_u8(0x231f)
    local bvy0 = mem:read_i8(0x232b)
    local bact0 = mem:read_u8(0x2310)
    local bact1 = mem:read_u8(0x2311)
    local bact2 = mem:read_u8(0x2312)

    log_file:write(string.format("F=%d ST=%d BALLS=%d LOCKS=%d LIT=%d DROPS=%x B0=[act=%d x=%d y=%d vy=%d] ACTS=[%d,%d,%d]\n",
      f, state, balls_left, locks, lock_lit, drops, bact0, bx0, by0, bvy0, bact0, bact1, bact2))
    log_file:flush()
  end

  if f >= 540 then
    log_file:write("MULTIBALL TEST COMPLETE\n")
    log_file:close()
    manager:machine():exit()
  end
end)
