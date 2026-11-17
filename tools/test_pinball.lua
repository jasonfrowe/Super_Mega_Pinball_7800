-- Diagnostic / Verification test script for Super Mega Pinball 7800
local f = 0
local mem = nil
local fields = {}
local held = {}

local log_file = io.open("test_run.log", "w")

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

  -- Frame 180: Start game
  if f == 180 then
    held["P1 Button 1"] = true
  elseif f == 200 then
    held["P1 Button 1"] = nil
    if fields["P1 Button 1"] then fields["P1 Button 1"]:set_value(0) end
  end

  -- SCENARIO 1: Center Drain Test at F=250
  -- Teleport ball to just above lower flippers in the center gap (X=72, Y=250, falling down)
  if f == 250 then
    log_file:write("--- SCENARIO 1: CENTER DRAIN TEST (X=72, Y=250) ---\n")
    mem:write_u8(0x2316, 72)  -- ball_xi[0] = 72 (dead center between flippers)
    mem:write_u8(0x231c, 250) -- ball_yl[0] = 250
    mem:write_u8(0x231f, 0)   -- ball_yh[0] = 0
    mem:write_u8(0x2325, 0)   -- ball_vxh[0] = 0
    mem:write_u8(0x232b, 2)   -- ball_vyh[0] = +2 (falling downward)
  end

  -- SCENARIO 2: Left Outlane Drain Test at F=400
  if f == 400 then
    log_file:write("--- SCENARIO 2: LEFT OUTLANE DRAIN TEST (X=20, Y=240) ---\n")
    mem:write_u8(0x2316, 20)  -- ball_xi[0] = 20 (inside left outlane channel)
    mem:write_u8(0x231c, 240) -- ball_yl[0] = 240
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 2)
  end

  -- SCENARIO 3: Right Outlane Drain Test at F=550
  if f == 550 then
    log_file:write("--- SCENARIO 3: RIGHT OUTLANE DRAIN TEST (X=121, Y=240) ---\n")
    mem:write_u8(0x2316, 121) -- ball_xi[0] = 121 (inside right outlane channel)
    mem:write_u8(0x231c, 240)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 2)
  end

  -- SCENARIO 4: Unlit Lock Chute Test at F=700
  -- Ball enters lock chute without cards knocked down: should NOT lock, should eject + give chute bonus!
  if f == 700 then
    log_file:write("--- SCENARIO 4: UNLIT LOCK CHUTE (X=108, Y=60) ---\n")
    mem:write_u8(0x2305, 0)   -- pb_drops = 0
    mem:write_u8(0x233c, 0)   -- pb_lock_lit = 0
    mem:write_u8(0x2303, 0)   -- pb_locks = 0
    mem:write_u8(0x2316, 108) -- ball_xi[0] = 108
    mem:write_u8(0x231c, 60)  -- ball_yl[0] = 60
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  end

  -- SCENARIO 5: Qualified Multiball Lock Test at F=800
  -- All 4 cards knocked down -> Lock is lit -> Ball enters chute -> Locks ball!
  if f == 800 then
    log_file:write("--- SCENARIO 5: QUALIFIED MULTIBALL LOCK (X=108, Y=60 with pb_lock_lit=1) ---\n")
    mem:write_u8(0x2305, 0x0F) -- all 4 cards knocked down
    mem:write_u8(0x233c, 1)    -- pb_lock_lit = 1
    mem:write_u8(0x2303, 0)    -- pb_locks = 0
    mem:write_u8(0x2316, 108)
    mem:write_u8(0x231c, 60)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  end

  -- SCENARIO 6: Second Lock triggers Multiball Mania at F=900
  if f == 900 then
    log_file:write("--- SCENARIO 6: 2ND LOCK TRIGGERS MULTIBALL MANIA ---\n")
    mem:write_u8(0x233c, 1)    -- pb_lock_lit = 1
    mem:write_u8(0x2303, 1)    -- pb_locks = 1
    mem:write_u8(0x2316, 108)
    mem:write_u8(0x231c, 60)
    mem:write_u8(0x231f, 0)
    mem:write_u8(0x2325, 0)
    mem:write_u8(0x232b, 1)
  end

  -- Log every 5 frames during scenarios
  if f >= 245 and f <= 1000 and f % 5 == 0 then
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

  if f >= 1050 then
    log_file:write("ALL SCENARIOS COMPLETE\n")
    log_file:close()
    manager:machine():exit()
  end
end)
