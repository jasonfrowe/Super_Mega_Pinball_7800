  rem ======================================================================
  rem  SUPER MEGA PINBALL 7800: IGNITION
  rem  Inspired by Pinball Dreams (Amiga 500) for the Atari 7800 ProSystem
  rem  Powered by the AstroCart FPGA MathUnit & CORDIC Engine ($0420-$043F)
  rem  and AtariGammaForce's 160A Smooth Vertical Scrolling Display Engine
  rem ======================================================================

  set romsize 32k
  set zoneheight 16
  set screenheight 224
  displaymode 160A
  set doublewide on
  const ZONECOUNT = 1
  const DLMEMEND = $18FF

  incbasic gen/consts.bas

  dim attr_dir = a
  dim fire_wait = b
  dim debounce = c
  dim tmp = d

  dim v_cam_y      = $223B
  dim v_state      = $2300
  dim v_banner_tmr = $230D
  dim v_frame      = $230E
  dim v_joy_l      = $2340
  dim v_joy_r      = $2341
  dim v_joy_d      = $2342

  characterset charset
  asm
  jsr pf_init
  jsr pinball_init
end

  attr_dir = 0
  fire_wait = 1
  debounce = 15

  rem ======================================================================
  rem  ATTRACT / TITLE LOOP (Smoothly pans camera up & down the full table!)
  rem ======================================================================
attract_loop
  asm
  inc pb_frame
  lda M_RND
  jsr sound_update
end

  rem ** Smoothly scroll camera up and down across the 320-line Pinball table
  tmp = v_frame & 1
  if tmp = 0 then gosub pan_attract_cam

  asm
  jsr pf_frame
  jsr pinball_draw
  jsr pf_drawscreen
end

  if debounce > 0 then debounce = debounce - 1
  if !joy0fire0 && !joy0fire1 then fire_wait = 0
  if debounce > 0 then goto attract_loop
  if fire_wait > 0 then goto attract_loop

  if joy0fire0 || joy0fire1 then goto start_pinball
  if joy0down then goto start_pinball
  goto attract_loop

pan_attract_cam
  if attr_dir = 0 then goto pan_up
  if v_cam_y < 111 then v_cam_y = v_cam_y + 1 : return
  attr_dir = 0
  return
pan_up
  if v_cam_y > 0 then v_cam_y = v_cam_y - 1 : return
  attr_dir = 1
  return

start_pinball
  v_cam_y = 111
  asm
  jsr match_init
end

  rem ======================================================================
  rem  MAIN 60HZ PINBALL GAMEPLAY LOOP
  rem ======================================================================
game_loop
  if switchreset then gosub reset_to_attract : goto attract_loop

  rem ** Read Controls:
  rem **   Left / Button 1  -> Left Flipper
  rem **   Right / Button 2 -> Right Flipper
  rem **   Down             -> Pull Plunger (release to shoot ball!)
  v_joy_l = 0
  if joy0left || joy0fire1 then v_joy_l = 1

  v_joy_r = 0
  if joy0right || joy0fire0 then v_joy_r = 1

  v_joy_d = 0
  if joy0down then v_joy_d = 1

  asm
  jsr pinball_step
  jsr pf_frame
  jsr pinball_draw
  jsr pf_drawscreen
end

  if v_state = 2 then goto game_over_check
  goto game_loop

game_over_check
  if v_banner_tmr = 0 then gosub reset_to_attract : goto attract_loop
  if v_banner_tmr >= 150 then goto game_loop
  if joy0fire0 || joy0fire1 then gosub reset_to_attract : goto attract_loop
  goto game_loop

reset_to_attract
  v_state = 0
  fire_wait = 1
  debounce = 20
  asm
  jsr sound_init
  jsr spawn_plunger_ball
  lda #0
  sta pb_banner_tmr
end
  return

  inline engine.asm
  inline sound.asm
  inline physics.asm
  inline data.asm
  incbasic gen/gfx.bas
