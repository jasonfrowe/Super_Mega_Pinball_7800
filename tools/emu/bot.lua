-- Autoplay bot for soak tests: starts a game, plunges, flips when a ball
-- comes near a flipper, logs once a second, snaps every SNAP_EVERY frames.
local mem = manager:machine().devices[":maincpu"].spaces["program"]
local fields = {}
for tag, port in pairs(manager:machine():ioport().ports) do
  if tag:find("joy2") == nil then for n, f in pairs(port.fields) do fields[n] = f end end
end
local out = io.open(os.getenv("BOT_OUT") or "bot.txt", "w")
local last = tonumber(os.getenv("BOT_FRAMES") or "6000")
local snapn = tonumber(os.getenv("SNAP_EVERY") or "0")
local f = 0
local lflip, rflip, down = 0, 0, 0
local function set(name, v) if fields[name] then fields[name]:set_value(v) end end
local function ball(i)
  local x = (mem:read_u8(0x2309 + i) * 256 + mem:read_u8(0x2306 + i)) / 16
  local y = (mem:read_u8(0x2312 + i) * 256 + mem:read_u8(0x230F + i)) / 16
  local vy = mem:read_u8(0x231E + i) * 256 + mem:read_u8(0x231B + i)
  if vy > 32767 then vy = vy - 65536 end
  return mem:read_u8(0x2300 + i), x, y, vy / 256
end
emu.register_frame_done(function()
  f = f + 1
  local state = mem:read_u8(0x2400)
  if f == 250 or (state == 0 and f > 300 and f % 400 == 0) then set("P1 Button 1", 1) end
  if f == 256 or (state == 0 and f > 300 and f % 400 == 6) then set("P1 Button 1", 0) end
  local wantl, wantr, wantd = false, false, false
  for i = 0, 2 do
    local act, x, y, vy = ball(i)
    if act == 1 then
      if x > 290 and y > 430 then wantd = true end
      if y > 395 and y < 440 and vy > -1 then
        if x > 80 and x < 150 then wantl = true end
        if x > 146 and x < 216 then wantr = true end
      end
    end
  end
  -- plunger: hold 40 frames then release
  if wantd then down = down + 1 else down = 0 end
  set("P1 Down", (down > 0 and down < 40) and 1 or 0)
  -- a press lasts 12 frames, then at least 14 released (lflip counts down from 26)
  if wantl and lflip == 0 then lflip = 26 end
  if wantr and rflip == 0 then rflip = 26 end
  if lflip > 0 then lflip = lflip - 1 end
  if rflip > 0 then rflip = rflip - 1 end
  set("P1 Button 1", (lflip > 14) and 1 or ((f == 250) and 1 or 0))
  set("P1 Button 2", (rflip > 14) and 1 or 0)
  if f % 60 == 0 then
    local s = ""
    for k = 0, 4 do s = s .. string.format("%02x", mem:read_u8(0x2401 + k)) end
    local act, x, y, vy = ball(0)
    local a1 = mem:read_u8(0x2301); local a2 = mem:read_u8(0x2302)
    out:write(string.format("%6d st=%d ball=%d score=%s b0=[%d %.0f,%.0f] acts=%d%d%d locks=%d mb=%d tick=%d\n",
      f, state, mem:read_u8(0x2413), s, act, x, y, act, a1, a2, mem:read_u8(0x2417), mem:read_u8(0x2419), mem:read_u8(0x55)))
    out:flush()
  end
  if snapn > 0 and f % snapn == 0 then manager:machine().screens[":screen"]:snapshot() end
  if f >= last then out:close(); manager:machine():exit() end
end)
